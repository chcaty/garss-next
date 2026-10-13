import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/data/library_codec.dart';
import 'package:garss_app/state/library_state.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/reading_filter.dart';

import 'library_storage_test.dart' show cachedCatalog, savedArticle;

String _serializeAndIdentifyIsolate(Map<String, dynamic> request) =>
    '${Isolate.current.debugName}\n${encodeCatalog(decodeCachedCatalog(request['raw'] as String))}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cache decode and serialization roundtrip is compute-compatible off the caller isolate', () async {
    final raw = jsonEncode(cachedCatalog.toJson());
    final result = await compute(_serializeAndIdentifyIsolate, {
      'raw': raw,
    }, debugLabel: 'catalog-codec');
    expect(result.split('\n').first, 'catalog-codec');
    expect(result.split('\n').first, isNot(Isolate.current.debugName));
    final decoded = await compute(
      decodeCachedCatalog,
      result.substring(result.indexOf('\n') + 1),
    );
    final canonical = decodeCachedCatalog(raw).toJson();
    expect(decoded.toJson(), canonical);
    expect(decoded.articles.single.sourceTitle, '来源');
    final encoded = await compute(encodeCatalog, decoded);
    expect(jsonDecode(encoded), canonical);
  });

  test('saved codecs retain recovery guard and exact readable values across isolates', () async {
    final raw = jsonEncode([
      savedArticle.toJson(),
      {'invalid': true},
    ]);
    final document = await compute(decodeSavedDocument, raw);
    expect(document.requiresRecovery, isTrue);
    expect(document.saved.keys, [savedArticle.id]);
    final encoded = await compute(encodeSavedDocument, document.saved);
    expect(jsonDecode(encoded), [savedArticle.toJson()]);
    expect(
      (await compute(decodeSavedDocument, '{broken')).requiresRecovery,
      isTrue,
    );
  });

  test('derived state caches invalidate only with their relevant data', () {
    final state = LibraryState(
      catalog: cachedCatalog,
      saved: {savedArticle.id: savedArticle},
    );
    final unread = state.unreadCounts;
    final categories = state.savedCategories;
    expect(state.articleCounts['source'], 1);
    expect(identical(state.unreadCounts, unread), isTrue);
    expect(identical(state.savedCategories, categories), isTrue);
    final settings = state.copyWith(fontScale: 1.2);
    expect(identical(settings.unreadCounts, unread), isTrue);
    expect(identical(settings.savedCategories, categories), isTrue);
    final read = state.copyWith(read: {savedArticle.id});
    expect(read.unreadCounts['source'] ?? 0, 0);
    expect(read.visible(unreadOnly: true), isEmpty);
    expect(state.unreadCounts['source'], 1);
    final cleared = state.copyWith(saved: {});
    expect(cleared.visible(savedOnly: true), isEmpty);
    expect(cleared.savedCategories, isEmpty);
    expect(state.visible(savedOnly: true).single.id, savedArticle.id);
    expect(state.copyWith(hidden: {'source'}).visible(), isEmpty);
    final replaced = state.copyWith(
      catalog: Catalog(
        generatedAt: cachedCatalog.generatedAt,
        feeds: const [
          Feed(
            id: 'source',
            title: '来源',
            url: 'https://example.com/rss',
            category: '新闻',
          ),
        ],
        articles: [],
      ),
    );
    expect(replaced.unreadCounts, isEmpty);
    expect(replaced.savedCategories, ['新闻']);
    expect(state.savedCategories, ['技术']);
  });
  test(
    'equal publication times keep input order in catalog and saved queues',
    () {
      final items = [
        for (final id in ['z', 'a', 'm'])
          Article.fromJson({...savedArticle.toJson(), 'id': id}),
      ];
      final state = LibraryState(
        catalog: Catalog(
          generatedAt: cachedCatalog.generatedAt,
          feeds: cachedCatalog.feeds,
          articles: items,
        ),
        saved: {for (final article in items) article.id: article},
      );
      expect(state.visible().map((article) => article.id), ['z', 'a', 'm']);
      expect(state.visible(savedOnly: true).map((article) => article.id), [
        'z',
        'a',
        'm',
      ]);
      expect(
        state
            .copyWith(read: {'a'})
            .visible(unreadOnly: true)
            .map((article) => article.id),
        ['z', 'm'],
      );
    },
  );

  test('precomputed timestamps preserve microsecond period boundaries', () {
    final now = DateTime.utc(2026, 10, 1, 12);
    final future = Article.fromJson({
      ...savedArticle.toJson(),
      'published_at': now
          .add(const Duration(microseconds: 1))
          .toIso8601String(),
    });
    final state = LibraryState(
      catalog: Catalog(
        generatedAt: now,
        feeds: cachedCatalog.feeds,
        articles: [future],
      ),
    );
    expect(state.visible(period: ReadingPeriod.today, now: now), isEmpty);
    expect(state.visible(period: ReadingPeriod.all, now: now), hasLength(1));
  });
}
