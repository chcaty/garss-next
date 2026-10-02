import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync_report.dart';
import 'library.dart';

final syncProvider = AsyncNotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncStatus {
  const SyncStatus(this.report, {this.refreshing = false, this.message = ''});
  final SyncReport report;
  final bool refreshing;
  final String message;
}

class SyncController extends AsyncNotifier<SyncStatus> {
  @override
  Future<SyncStatus> build() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final cached = preferences.getString('sync-report-v1');
      if (cached != null) {
        return SyncStatus(
          SyncReport.fromJson(jsonDecode(cached) as Map<String, dynamic>),
          message: '显示缓存记录，正在检查最新状态',
        );
      }
    } catch (_) {}
    final report = await ref.read(repositoryProvider).fetchSyncReport();
    await preferences.setString('sync-report-v1', jsonEncode(report.toJson()));
    return SyncStatus(report);
  }

  Future<void> refresh() async {
    final current = state.asData?.value;
    if (current == null || current.refreshing) return;
    state = AsyncData(SyncStatus(current.report, refreshing: true));
    try {
      final report = await ref.read(repositoryProvider).fetchSyncReport();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'sync-report-v1',
        jsonEncode(report.toJson()),
      );
      if (ref.mounted) state = AsyncData(SyncStatus(report));
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          SyncStatus(current.report, message: '状态刷新失败，继续显示缓存记录'),
        );
      }
    }
  }
}
