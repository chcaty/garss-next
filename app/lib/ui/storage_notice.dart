import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';

class StorageNotice extends ConsumerWidget {
  const StorageNotice({super.key, required this.library});
  final LibraryState library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!library.savedRecoveryRequired && library.storageMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    final message = library.savedRecoveryRequired
        ? library.savedRecoveryCanRestore
              ? '稍后读记录损坏，原始内容未被覆盖。可读收藏仍可查看；恢复前，稍后读改动仅在本次会话有效。'
              : '稍后读记录读取失败，已停止覆盖。请重试读取，原始记录不会被清空。'
        : library.storageMessage;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (library.savedRecoveryRequired &&
                    library.storageMessage.isNotEmpty)
                  Text(library.storageMessage),
                Wrap(
                  spacing: 8,
                  children: [
                    if (library.savedRecoveryCanRestore)
                      TextButton(
                        onPressed: library.recoveringSaved
                            ? null
                            : () async {
                                final accepted = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('恢复可读收藏？'),
                                    content: Text(
                                      '先单独备份完整原始记录，再将当前可读的 ${library.saved.length} 篇收藏保存为新的稍后读。无法读取的记录只保留在备份中。备份失败时不会替换原始记录。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('备份并恢复'),
                                      ),
                                    ],
                                  ),
                                );
                                if (accepted == true && context.mounted) {
                                  await ref
                                      .read(libraryProvider.notifier)
                                      .recoverSaved();
                                }
                              },
                        child: Text(
                          library.recoveringSaved ? '正在恢复…' : '恢复可读收藏',
                        ),
                      ),
                    if (library.storageReadFailed)
                      TextButton(
                        onPressed: () async {
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('重新读取本机记录？'),
                              content: const Text(
                                '重新读取不会覆盖原始记录，但会丢弃本次会话中尚未保存的改动。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('重新读取'),
                                ),
                              ],
                            ),
                          );
                          if (accepted == true && context.mounted) {
                            await ref
                                .read(libraryProvider.notifier)
                                .pendingWrites;
                            if (!context.mounted) return;
                            ref.invalidate(libraryStorageProvider);
                            ref.invalidate(libraryProvider);
                          }
                        },
                        child: const Text('重试读取'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
