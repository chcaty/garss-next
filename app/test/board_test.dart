import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/board.dart';
import 'package:garss_app/state/library.dart';

void main() {
  final time = DateTime.utc(2026, 10, 29);
  final entry = Article(
    id: 'one',
    sourceId: 'a',
    sourceIds: const ['a', 'b', 'b'],
    title: 'Shared',
    url: 'https://example.com/one',
    publishedAt: time,
    contentType: 'video',
    metadata: const {'views': 12345, 'duration': '1:30'},
  );
  LibraryState state({bool known = true, String status = 'ok'}) => LibraryState(
    catalog: Catalog(
      generatedAt: time,
      feeds: [
        Feed(
          id: 'a',
          title: 'A',
          url: 'https://example.com/rss',
          baselineKnown: known,
          status: status,
          newIds: const ['one'],
        ),
        const Feed(id: 'b', title: 'B', url: 'https://example.com/b'),
      ],
      articles: [entry],
    ),
  );
  test(
    'source groups deduplicate membership and preserve metric snapshots',
    () {
      final groups = resultGroups(state());
      expect(groups.length, 2);
      expect(groups.last.articles.length, 1);
      final stream = feedEntries(groups);
      expect(stream, hasLength(1));
      expect(stream.single.article.id, 'one');
      expect(stream.single.feed.id, 'a');
      expect(stream.single.isNew, isTrue);
      expect(Article.fromJson(entry.toJson()).metadata['views'], 12345);
      expect(Article.fromJson(entry.toJson()).contentType, 'video');
      expect(resultGroups(state(), kind: 'article'), isEmpty);
      expect(
        resultGroups(
          state(),
          source: 'a',
          kind: 'video',
          onlyNew: true,
        ).single.articles.single.id,
        'one',
      );
    },
  );
  test('unknown and failed baselines do not create new items', () {
    expect(resultGroups(state(known: false), onlyNew: true), isEmpty);
    expect(resultGroups(state(status: 'error'), onlyNew: true), isEmpty);
    expect(
      resultGroups(state(status: 'error')).any((group) => group.feed.id == 'a'),
      isFalse,
    );
  });
  test('ranked boards keep rank order while the feed uses publish time', () {
    final newest = Article(
      id: 'newest',
      sourceId: 'ranked',
      sourceIds: const ['ranked', 'rss'],
      title: 'Newest',
      url: 'https://example.com/newest',
      publishedAt: time,
      observations: const {
        'ranked': {'rank': 2},
      },
    );
    final rankedFirst = Article(
      id: 'ranked-first',
      sourceId: 'ranked',
      sourceIds: const ['ranked', 'rss'],
      title: 'Ranked first',
      url: 'https://example.com/ranked-first',
      publishedAt: time.subtract(const Duration(days: 1)),
      observations: const {
        'ranked': {'rank': 1},
      },
    );
    final library = LibraryState(
      catalog: Catalog(
        generatedAt: time,
        feeds: [
          const Feed(
            id: 'ranked',
            title: 'Ranked',
            url: 'https://example.com/ranked',
            adapter: 'bilibili',
          ),
          const Feed(id: 'rss', title: 'RSS', url: 'https://example.com/rss'),
        ],
        articles: [newest, rankedFirst],
      ),
    );
    final groups = resultGroups(library);
    expect(groups.first.articles.map((article) => article.id), [
      'ranked-first',
      'newest',
    ]);
    expect(feedEntries(groups).map((entry) => entry.article.id), [
      'newest',
      'ranked-first',
    ]);
    expect(feedEntries(groups).every((item) => item.feed.id == 'rss'), isTrue);
    expect(feedEntries([groups.first]), isEmpty);
  });
  test(
    'saved multi-type content outlives public catalog and retains categories',
    () {
      final saved = Article.fromJson({
        ...entry.toJson(),
        'saved_categories': ['Tech'],
      });
      final library = LibraryState(
        catalog: Catalog(generatedAt: time, feeds: [], articles: []),
        saved: {saved.id: saved},
      );
      final groups = resultGroups(
        library,
        savedOnly: true,
        kind: 'video',
        category: 'Tech',
      );
      expect(groups, hasLength(2));
      expect(groups.first.articles.single.metadata['duration'], '1:30');
      expect(groups.first.newIds, isEmpty);
    },
  );
}
