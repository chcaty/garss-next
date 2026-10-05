import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import '../state/appearance.dart';
import 'appearance.dart';
import 'sync.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final appearance = ref.watch(appearanceProvider).value ?? ThemeMode.system;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('阅读与外观', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('外观'),
          subtitle: Text(appearanceLabel(appearance)),
          trailing: const AppearanceButton(),
        ),
        const Divider(height: 32),
        Text('文章字号', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '当前字号 ${(library.fontScale * 100).round()}%',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        Slider(
          value: library.fontScale,
          min: 1,
          max: 1.4,
          divisions: 4,
          label: '${(library.fontScale * 100).round()}%',
          onChanged: (value) =>
              ref.read(libraryProvider.notifier).setFontScale(value),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: colors.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '阅读，从一篇好文章开始',
                style: TextStyle(
                  fontSize: 18 * library.fontScale,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '这是字号预览。选好信息后，按自己的节奏阅读。',
                style: TextStyle(
                  fontSize: 14 * library.fontScale,
                  height: 1.8,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('专注阅读显示图片'),
          subtitle: const Text('图片来自原站，关闭可节省流量。'),
          value: library.showImages,
          onChanged: (value) =>
              ref.read(libraryProvider.notifier).setImages(value),
        ),
        const Divider(height: 32),
        Text('本机阅读记录', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(
          '${library.saved.length} 篇稍后读 · ${library.read.length} 篇已读',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Text(
          '稍后读、摘要、已读和关注保存在本机。原文和远程图片需要联网。',
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.8),
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('同步记录'),
          subtitle: const Text('最近采集、异常来源与历史批次'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (context) => const SyncScreen()),
          ),
        ),
        const Divider(height: 32),
        const Text(
          '拾阅 · Android 预览版 0.2.1',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          '数据由 GitHub 定时采集并发布。手机只同步文章快照，文章离开目录后，稍后读仍然保留。',
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.8),
        ),
      ],
    );
  }
}
