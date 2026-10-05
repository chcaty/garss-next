import '../data/models.dart';
import '../data/reading_filter.dart';

class LibraryState {
  LibraryState({
    required this.catalog,
    Map<String, Article> saved = const {},
    Set<String> read = const {},
    Set<String> hidden = const {},
    this.syncing = false,
    this.message = '',
    this.fontScale = 1,
    this.showImages = true,
  }) : saved = Map.unmodifiable(saved),
       read = Set.unmodifiable(read),
       hidden = Set.unmodifiable(hidden);
  final Catalog catalog;
  final Map<String, Article> saved;
  final Set<String> read, hidden;
  final bool syncing, showImages;
  final String message;
  final double fontScale;
  LibraryState copyWith({
    Catalog? catalog,
    Map<String, Article>? saved,
    Set<String>? read,
    Set<String>? hidden,
    bool? syncing,
    String? message,
    double? fontScale,
    bool? showImages,
  }) => LibraryState(
    catalog: catalog ?? this.catalog,
    saved: saved ?? this.saved,
    read: read ?? this.read,
    hidden: hidden ?? this.hidden,
    syncing: syncing ?? this.syncing,
    message: message ?? this.message,
    fontScale: fontScale ?? this.fontScale,
    showImages: showImages ?? this.showImages,
  );
  Map<String, int> get articleCounts => _countArticles();

  Map<String, int> get unreadCounts => _countArticles(unreadOnly: true);

  Map<String, int> _countArticles({bool unreadOnly = false}) {
    final counts = <String, int>{};
    for (final article in catalog.articles) {
      if (unreadOnly && read.contains(article.id)) continue;
      for (final id in article.sources.toSet()) {
        counts.update(id, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  List<Feed> get readingFeeds {
    final counts = articleCounts;
    return catalog.feeds
        .where(
          (feed) =>
              feed.enabled &&
              !hidden.contains(feed.id) &&
              (counts[feed.id] ?? 0) > 0,
        )
        .toList();
  }

  List<String> get savedCategories =>
      saved.values
          .expand((article) => categoriesFor(article, savedOnly: true))
          .where((category) => category.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  Iterable<String> categoriesFor(Article article, {bool savedOnly = false}) {
    if (savedOnly && article.savedCategories.isNotEmpty) {
      return article.savedCategories;
    }
    return catalog.feeds
        .where((feed) => article.sources.contains(feed.id))
        .map((feed) => feed.category);
  }

  List<Article> visible({
    String query = '',
    bool savedOnly = false,
    bool unreadOnly = false,
    String source = '',
    String category = '',
    ReadingPeriod period = ReadingPeriod.all,
    DateTime? now,
  }) {
    final needle = query.trim().toLowerCase();
    final enabled = {
      for (final feed in catalog.feeds)
        if (feed.enabled && !hidden.contains(feed.id)) feed.id,
    };
    final canonical = catalog.sourceAliases[source] ?? source;
    final readingNow = now ?? DateTime.now();
    return (savedOnly ? saved.values : catalog.articles)
        .where(
          (article) =>
              (savedOnly || article.sources.any(enabled.contains)) &&
              (!unreadOnly || !read.contains(article.id)) &&
              (category.isEmpty ||
                  categoriesFor(
                    article,
                    savedOnly: savedOnly,
                  ).contains(category)) &&
              inReadingPeriod(article, period, readingNow) &&
              (canonical.isEmpty || article.sources.contains(canonical)) &&
              (needle.isEmpty ||
                  '${article.title} ${article.sourceTitle} ${article.summary}'
                      .toLowerCase()
                      .contains(needle)),
        )
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }
}
