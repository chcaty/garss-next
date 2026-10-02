import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garss_app/state/appearance.dart';
import 'package:garss_app/data/sync_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('appearance persists independently of catalog availability', () async {
    SharedPreferences.setMockInitialValues({});
    var container = ProviderContainer();
    expect(await container.read(appearanceProvider.future), ThemeMode.system);
    expect(
      await container.read(appearanceProvider.notifier).change(ThemeMode.dark),
      true,
    );
    container.dispose();
    container = ProviderContainer();
    expect(await container.read(appearanceProvider.future), ThemeMode.dark);
    container.dispose();
  });
  test('sync report preserves source errors and bounds historical batches', () {
    final time = DateTime.utc(2026, 10, 3);
    final run = SyncRun(
      generatedAt: time,
      succeeded: 135,
      failed: 103,
      checked: 238,
      articleCount: 2871,
      durationSeconds: 60,
      workflowRunId: '123',
    );
    final report = SyncReport(
      generatedAt: time,
      runs: List.filled(40, run),
      sources: {
        'a': SourceHealth(
          status: 'error',
          error: 'timeout',
          lastCheckedAt: time,
        ),
      },
    );
    final restored = SyncReport.fromJson(report.toJson());
    expect(restored.runs.length, 30);
    expect(restored.sources['a']?.error, 'timeout');
    expect(restored.runs.first.workflowRunId, '123');
  });
}
