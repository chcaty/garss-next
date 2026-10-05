import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garss_app/state/appearance.dart';
import 'package:garss_app/data/sync_report.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/ui/article.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'source state distinguishes public disable, archive and transient errors',
    () {
      final report = SyncReport(
        generatedAt: DateTime.utc(2026, 10, 3),
        runs: [],
        sources: {
          'disabled': const SourceHealth(status: 'active'),
          'archived': const SourceHealth(status: 'archived'),
          'error': const SourceHealth(status: 'active'),
        },
        feeds: {
          'disabled': const Feed(
            id: 'disabled',
            title: 'Disabled',
            url: 'https://example.com/rss',
            enabled: false,
            collectionStatus: 'disabled',
          ),
          'archived': const Feed(
            id: 'archived',
            title: 'Archived',
            url: 'https://example.com/rss',
            enabled: false,
            collectionStatus: 'archived',
          ),
          'error': const Feed(
            id: 'error',
            title: 'Error',
            url: 'https://example.com/rss',
            status: 'error',
            collectionStatus: 'active',
          ),
        },
      );
      final restored = SyncReport.fromJson(report.toJson());
      expect(restored.statusFor('disabled'), 'disabled');
      expect(restored.statusFor('archived'), 'archived');
      expect(restored.statusFor('error'), 'error');
      expect(articleDate(DateTime.utc(2026, 10, 2, 17)), '10月3日 01:00');
    },
  );
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
