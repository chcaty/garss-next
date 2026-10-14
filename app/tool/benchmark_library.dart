// CPU/model microbenchmark, not a device or rendering benchmark.
// dart --suppress-analytics run tool/benchmark_library.dart feeds.json articles.json output.json
import 'dart:convert';
import 'dart:io';

import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/reading_filter.dart';
import 'package:garss_app/state/library_state.dart';

void main(List<String> args) {
  if (args.length != 3) {
    throw ArgumentError('Expected feeds.json articles.json output.json');
  }
  final feeds =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final articles =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final catalog = Catalog.fromJson({
    ...feeds,
    'articles': articles['articles'],
  });
  final byId = {for (final article in catalog.articles) article.id: article};
  // Fixed fixture IDs ensure sorting changes cannot change the workload itself.
  final ids = (articles['articles'] as List)
      .map((value) => value['id'] as String)
      .where(byId.containsKey)
      .toList();
  final state = LibraryState(
    catalog: catalog,
    saved: {for (final id in ids.take(2000)) id: byId[id]!},
    read: ids.take(3000).toSet(),
    hidden: {
      for (final feed in catalog.feeds.indexed)
        if (feed.$1 % 5 == 0) feed.$2.id,
    },
  );
  final category = catalog.feeds
      .firstWhere((feed) => feed.category.isNotEmpty)
      .category;
  final source = catalog.feeds
      .firstWhere((feed) => feed.enabled && !state.hidden.contains(feed.id))
      .id;
  Map<String, List<String>> queries() => {
    'all': state.visible().map((article) => article.id).toList(),
    '技术': state.visible(query: '技术').map((article) => article.id).toList(),
    'Python': state
        .visible(query: 'Python')
        .map((article) => article.id)
        .toList(),
    'AI': state.visible(query: 'AI').map((article) => article.id).toList(),
    'category': state
        .visible(category: category)
        .map((article) => article.id)
        .toList(),
    'source_unread': state
        .visible(source: source, unreadOnly: true)
        .map((article) => article.id)
        .toList(),
    'week_unread': state
        .visible(
          period: ReadingPeriod.week,
          now: catalog.generatedAt,
          unreadOnly: true,
        )
        .map((article) => article.id)
        .toList(),
    'saved_AI': state
        .visible(savedOnly: true, query: 'AI')
        .map((article) => article.id)
        .toList(),
  };
  var checksum = 0;
  void measure() {
    checksum += state.articleCounts.values.fold(0, (sum, value) => sum + value);
    checksum += state.unreadCounts.values.fold(0, (sum, value) => sum + value);
    checksum += state.readingFeeds.length + state.savedCategories.length;
    checksum += queries().values.fold(0, (sum, value) => sum + value.length);
  }

  for (var i = 0; i < 3; i++) {
    measure();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < 30; i++) {
    measure();
  }
  watch.stop();
  final results = queries();
  final summary = {
    'articles': catalog.articles.length,
    'feeds': catalog.feeds.length,
    'saved': state.saved.length,
    'iterations': 30,
    'elapsed_ms': watch.elapsedMicroseconds / 1000,
    'checksum': checksum,
    'category': category,
    'source': source,
    'query_counts': results.map((key, value) => MapEntry(key, value.length)),
  };
  File(args[2]).writeAsStringSync(
    jsonEncode({
      ...summary,
      'ordered_query_ids': results,
      'published_at': {
        for (final article in catalog.articles)
          article.id: article.publishedAt.toUtc().toIso8601String(),
      },
    }),
  );
  stdout.writeln(jsonEncode(summary));
}
