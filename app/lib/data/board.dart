import '../state/library_state.dart';
import 'models.dart';

const contentLabels = {
  'article': '文章',
  'topic': '话题',
  'video': '视频',
  'repository': '项目',
  'item': '影视',
};

class ResultGroup {
  ResultGroup(this.feed, this.articles, {bool savedOnly = false})
    : newIds = !savedOnly && feed.status == 'ok' && feed.baselineKnown == true
          ? feed.newIds.toSet()
          : <String>{};
  final Feed feed;
  final List<Article> articles;
  final Set<String> newIds;
}

class FeedEntry {
  const FeedEntry({
    required this.article,
    required this.feed,
    required this.isNew,
  });
  final Article article;
  final Feed feed;
  final bool isNew;
}

bool isChronologicalFeed(Feed feed) => feed.adapter == 'rss';

List<ResultGroup> resultGroups(
  LibraryState library, {
  bool savedOnly = false,
  String query = '',
  String source = '',
  String category = '',
  String kind = 'all',
  bool onlyNew = false,
}) {
  final sourceNames = {
    for (final feed in library.catalog.feeds) feed.id: feed.title,
  };
  final entries = library
      .visible(
        savedOnly: savedOnly,
        query: '',
        source: source,
        category: category,
      )
      .where((article) => kind == 'all' || article.contentType == kind)
      .where((article) {
        final names = article.sources
            .map((id) => sourceNames[id] ?? '')
            .join(' ');
        return '${article.title} ${article.summary} ${article.sourceTitle} $names'
            .toLowerCase()
            .contains(query.trim().toLowerCase());
      });
  final feeds = <String, Feed>{
    for (final feed in library.catalog.feeds)
      if (savedOnly ||
          feed.enabled &&
              feed.status != 'error' &&
              !library.hidden.contains(feed.id))
        feed.id: feed,
  };
  if (savedOnly) {
    for (final article in library.saved.values) {
      for (final feed in article.savedSources) {
        feeds[feed.id] = feed;
      }
    }
  }
  final bySource = <String, List<Article>>{};
  for (final article in entries) {
    for (final id in article.sources.toSet()) {
      if (savedOnly) {
        feeds.putIfAbsent(
          id,
          () => Feed(
            id: id,
            title: article.sourceTitle.isEmpty ? id : article.sourceTitle,
            url: article.url,
            category: article.savedCategories.firstOrNull ?? '',
          ),
        );
      }
      if (feeds.containsKey(id)) {
        bySource.putIfAbsent(id, () => []).add(article);
      }
    }
  }
  final canonical = library.catalog.sourceAliases[source] ?? source;
  final groups = <ResultGroup>[];
  for (final feed in feeds.values) {
    if (canonical.isNotEmpty && feed.id != canonical) continue;
    if (category.isNotEmpty && feed.category != category) {
      continue;
    }
    var items = bySource[feed.id] ?? <Article>[];
    if (!savedOnly && onlyNew) {
      items = items
          .where(
            (article) =>
                feed.status == 'ok' &&
                feed.baselineKnown == true &&
                feed.newIds.contains(article.id),
          )
          .toList();
    }
    if (items.isEmpty) continue;
    if (feed.adapter != 'rss' && feed.adapter != 'devto') {
      items.sort(
        (a, b) => ((a.observation(feed.id)['rank'] as num?) ?? double.infinity)
            .compareTo(
              (b.observation(feed.id)['rank'] as num?) ?? double.infinity,
            ),
      );
    }
    groups.add(ResultGroup(feed, items, savedOnly: savedOnly));
  }
  return groups;
}

List<FeedEntry> feedEntries(
  List<ResultGroup> groups, {
  bool includeRankedSources = false,
}) {
  final entries = <String, FeedEntry>{};
  for (final group in groups) {
    if (!includeRankedSources && !isChronologicalFeed(group.feed)) continue;
    for (final article in group.articles) {
      final isNew = group.newIds.contains(article.id);
      final existing = entries[article.id];
      if (existing == null || isNew && !existing.isNew) {
        entries[article.id] = FeedEntry(
          article: article,
          feed: group.feed,
          isNew: isNew,
        );
      }
    }
  }
  final result = entries.values.toList()
    ..sort((a, b) => b.article.publishedAt.compareTo(a.article.publishedAt));
  return result;
}

String collectionCondition(Feed feed) {
  if (feed.status == 'error') return '采集异常 · 保留上次内容';
  if (feed.initialized == false) return '等待首次采集';
  if (feed.baselineKnown == false) return '首次接入 · 已建立基线';
  return feed.status == 'ok' ? '采集正常' : '状态未知';
}

String compactNumber(num value) => value >= 100000000
    ? '${(value / 100000000).toStringAsFixed(1)}亿'
    : value >= 10000
    ? '${(value / 10000).toStringAsFixed(1)}万'
    : '$value';
