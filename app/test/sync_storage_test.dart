import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/ui/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/data/repository.dart';
import 'package:garss_app/data/sync_report.dart';
import 'package:garss_app/state/library.dart';
import 'package:garss_app/state/sync.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'library_storage_test.dart' show FakeLibraryStorage;

class _ReportRepository extends CatalogRepository {
  _ReportRepository(this.report)
    : super(MockClient((request) async => http.Response('unused', 500)));
  final SyncReport report;
  int fetches = 0;
  @override
  Future<SyncReport> fetchSyncReport() async {
    fetches++;
    return report;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final report = SyncReport(
    generatedAt: DateTime.utc(2026, 10, 13),
    runs: [],
    sources: {},
  );
  for (final throws in [false, true]) {
    for (final cached in [false, true]) {
      test(
        'sync report cache failure ($throws, cached=$cached) is visible without discarding fetched data',
        () async {
          final storage = FakeLibraryStorage({
            if (cached)
              'sync-report-v1': jsonEncode(
                SyncReport(
                  generatedAt: DateTime.utc(2026, 10, 12),
                  runs: [],
                  sources: {},
                ).toJson(),
              ),
          });
          if (throws) {
            storage.throwPrefix = 'sync-report-v1';
          } else {
            storage.rejectPrefix = 'sync-report-v1';
          }
          final container = ProviderContainer(
            overrides: [
              libraryStorageProvider.overrideWith((ref) async => storage),
              repositoryProvider.overrideWithValue(_ReportRepository(report)),
            ],
          );
          addTearDown(container.dispose);
          await container.read(syncProvider.future);
          if (cached) await container.read(syncProvider.notifier).refresh();
          final state = container.read(syncProvider).requireValue;
          expect(state.report.generatedAt, report.generatedAt);
          expect(state.message, contains('缓存保存失败'));
          storage.throwPrefix = storage.rejectPrefix = null;
          await container.read(syncProvider.notifier).refresh();
          expect(container.read(syncProvider).requireValue.message, isEmpty);
          expect(
            jsonDecode(storage.values['sync-report-v1'] as String),
            report.toJson(),
          );
        },
      );
    }
  }
  for (final throws in [false, true]) {
    testWidgets(
      'fresh report with failed cache write ($throws) does not trigger a duplicate startup fetch',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final storage = FakeLibraryStorage();
        if (throws) {
          storage.throwPrefix = 'sync-report-v1';
        } else {
          storage.rejectPrefix = 'sync-report-v1';
        }
        final repository = _ReportRepository(report);
        final container = ProviderContainer(
          overrides: [
            libraryStorageProvider.overrideWith((ref) async => storage),
            repositoryProvider.overrideWithValue(repository),
            libraryProvider.overrideWith(_ReadyLibraryController.new),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SyncScreen()),
          ),
        );
        final elapsed = Stopwatch()..start();
        do {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
          if (elapsed.elapsed > const Duration(seconds: 10)) {
            fail('Sync report did not settle');
          }
        } while (!container.read(syncProvider).hasValue ||
            container.read(syncProvider).requireValue.refreshing);
        await tester.pumpAndSettle();
        expect(repository.fetches, 1);
        expect(container.read(syncProvider).requireValue.fromCache, isFalse);
        expect(find.textContaining('缓存保存失败'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _ReadyLibraryController extends LibraryController {
  @override
  Future<LibraryState> build() async => LibraryState(
    catalog: Catalog(
      generatedAt: DateTime.utc(2026, 10, 13),
      feeds: [],
      articles: [],
    ),
  );
}
