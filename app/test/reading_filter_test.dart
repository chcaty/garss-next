import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/reading_filter.dart';
import 'package:garss_app/state/library.dart';

void main() {
  final now = DateTime.utc(2026, 10, 3, 2);
  Article entry(String id, DateTime time, {List<String> ids = const ['a']}) =>
      Article(
        id: id,
        sourceId: ids.first,
        sourceIds: ids,
        title: id,
        url: 'https://example.com/$id',
        publishedAt: time,
      );
  test(
    'Beijing calendar filters do not include yesterday or future entries',
    () {
      expect(
        readingStart(ReadingPeriod.today, now),
        DateTime.utc(2026, 10, 2, 16),
      );
      expect(
        readingStart(ReadingPeriod.week, now),
        DateTime.utc(2026, 9, 26, 16),
      );
      expect(
        inReadingPeriod(
          entry('today', DateTime.utc(2026, 10, 2, 16)),
          ReadingPeriod.today,
          now,
        ),
        isTrue,
      );
      expect(
        inReadingPeriod(
          entry('yesterday', DateTime.utc(2026, 10, 2, 15, 59)),
          ReadingPeriod.today,
          now,
        ),
        isFalse,
      );
      expect(
        inReadingPeriod(
          entry('future', DateTime.utc(2026, 10, 4)),
          ReadingPeriod.today,
          now,
        ),
        isFalse,
      );
    },
  );
  test('category and unread filters retain shared source memberships', () {
    final shared = entry(
      'shared',
      DateTime.utc(2026, 10, 2),
      ids: ['a', 'a', 'b'],
    );
    final state = LibraryState(
      catalog: Catalog(
        generatedAt: now,
        feeds: [
          const Feed(
            id: 'a',
            title: 'A',
            url: 'https://a.test/rss',
            category: '技术',
          ),
          const Feed(
            id: 'b',
            title: 'B',
            url: 'https://b.test/rss',
            category: '新闻',
          ),
        ],
        articles: [shared],
      ),
    );
    expect(
      state
          .visible(category: '新闻', period: ReadingPeriod.week, now: now)
          .single
          .id,
      'shared',
    );
    expect(state.unreadCounts, {'a': 1, 'b': 1});
    expect(state.articleCounts, {'a': 1, 'b': 1});
    final readState = state.copyWith(read: {'shared'}, hidden: {'a'});
    expect(readState.unreadCounts, isEmpty);
    expect(readState.articleCounts, {'a': 1, 'b': 1});
    expect(state.unreadCounts, {'a': 1, 'b': 1});
  });
}
