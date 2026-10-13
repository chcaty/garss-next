import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/state/library.dart';
import 'package:garss_app/ui/sources_page.dart';
import 'package:garss_app/ui/storage_notice.dart';

import 'library_storage_test.dart'
    show FakeLibraryStorage, savedArticle, cachedCatalog;

void main() {
  Future<ProviderContainer> setup(
    WidgetTester tester,
    FakeLibraryStorage storage, {
    bool notice = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [libraryStorageProvider.overrideWith((ref) async => storage)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(libraryProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final library = ref.watch(libraryProvider).requireValue;
                return notice
                    ? StorageNotice(library: library)
                    : SourcesPage(library: library);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final status in ['archived', 'disabled']) {
    testWidgets(
      'local follow filter and switch remain independent of $status collection',
      (tester) async {
        final catalog = Catalog(
          generatedAt: cachedCatalog.generatedAt,
          feeds: [
            Feed(
              id: 'source',
              title: '已关注来源',
              url: 'https://example.com/rss',
              enabled: false,
              collectionStatus: status,
            ),
            Feed(
              id: 'hidden',
              title: '未关注来源',
              url: 'https://example.net/rss',
              enabled: false,
              collectionStatus: status,
            ),
          ],
          articles: [savedArticle],
        );
        final storage = FakeLibraryStorage({
          'catalog-v1': jsonEncode(catalog.toJson()),
          'hidden-v1': ['hidden'],
        });
        final container = await setup(tester, storage);
        expect(
          container.read(libraryProvider).requireValue.readingFeeds,
          isEmpty,
        );
        expect(container.read(libraryProvider).requireValue.visible(), isEmpty);
        await tester.runAsync(() => tester.tap(find.text('只看本机关注')));
        await tester.runAsync(
          () => tester.tap(find.text(status == 'archived' ? '自动归档' : '公共停用')),
        );
        await tester.pumpAndSettle();
        expect(find.text('已关注来源'), findsOneWidget);
        expect(find.text('未关注来源'), findsNothing);
        final tile = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('source')),
        );
        expect(tile.value, isTrue);
        expect(tile.onChanged, isNotNull);
        await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('source'))),
        );
        await tester.pumpAndSettle();
        expect(find.text('已关注来源'), findsNothing);
        expect(
          container.read(libraryProvider).requireValue.hidden,
          contains('source'),
        );
        await tester.runAsync(() => tester.tap(find.text('清除来源筛选')));
        await tester.pumpAndSettle();
        final hidden = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('source')),
        );
        expect(hidden.value, isFalse);
        expect(hidden.onChanged, isNotNull);
        await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('source'))),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(libraryProvider).requireValue.isFollowed('source'),
          isTrue,
        );
        expect(container.read(libraryProvider).requireValue.visible(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'recovery requires explicit confirmation and cancellation preserves exact data',
    (tester) async {
      final raw = jsonEncode([
        savedArticle.toJson(),
        {'bad': 'record'},
      ]);
      final storage = FakeLibraryStorage({
        'catalog-v1': jsonEncode(cachedCatalog.toJson()),
        'saved-v2': raw,
      });
      final container = await setup(tester, storage, notice: true);
      expect(find.textContaining('原始内容未被覆盖'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('恢复可读收藏')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('取消')));
      await tester.pumpAndSettle();
      expect(storage.values['saved-v2'], raw);
      expect(storage.writes, isEmpty);
      await tester.runAsync(() => tester.tap(find.text('恢复可读收藏')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('备份并恢复')));
      await tester.runAsync(
        () => container.read(libraryProvider.notifier).pendingWrites,
      );
      await tester.pumpAndSettle();
      expect(storage.values[storage.writes.first], raw);
      expect(find.text('恢复可读收藏'), findsNothing);
      expect(find.textContaining('原始记录已单独备份'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
