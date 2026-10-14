import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../data/library_codec.dart';

import '../data/sync_report.dart';
import 'library.dart';

final syncProvider = AsyncNotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncStatus {
  const SyncStatus(
    this.report, {
    this.refreshing = false,
    this.message = '',
    this.fromCache = false,
  });
  final SyncReport report;
  final bool refreshing, fromCache;
  final String message;
}

class SyncController extends AsyncNotifier<SyncStatus> {
  @override
  Future<SyncStatus> build() async {
    final storage = await ref.read(libraryStorageProvider.future);
    try {
      final cached = storage.read('sync-report-v1') as String?;
      if (cached != null) {
        return SyncStatus(
          await compute(decodeCachedSyncReport, cached),
          message: '显示缓存记录，正在检查最新状态',
          fromCache: true,
        );
      }
    } catch (_) {}
    final report = await ref.read(repositoryProvider).fetchSyncReport();
    return SyncStatus(report, message: await _saveReport(report));
  }

  Future<String> _saveReport(SyncReport report) async {
    try {
      final storage = await ref.read(libraryStorageProvider.future);
      final encoded = await compute(encodeSyncReport, report);
      if (await storage.write('sync-report-v1', encoded)) return '';
    } catch (_) {
      // A public report remains usable in memory when cache persistence fails.
    }
    return '同步记录已更新，但缓存保存失败，仅在本次会话有效';
  }

  Future<void> refresh() async {
    final current = state.asData?.value;
    if (current == null || current.refreshing) return;
    state = AsyncData(SyncStatus(current.report, refreshing: true));
    try {
      final report = await ref.read(repositoryProvider).fetchSyncReport();
      final message = await _saveReport(report);
      if (ref.mounted) state = AsyncData(SyncStatus(report, message: message));
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          SyncStatus(current.report, message: '状态刷新失败，继续显示缓存记录'),
        );
      }
    }
  }
}
