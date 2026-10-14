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
    this.lastCheckedAt,
    this.fontScale = 1,
    this.showImages = true,
    this.storageMessage = '',
    this.storageReadFailed = false,
    this.savedRecoveryRequired = false,
    this.savedRecoveryCanRestore = false,
    this.recoveringSaved = false,
  }) : saved = Map.unmodifiable(saved),
       read = Set.unmodifiable(read),
       hidden = Set.unmodifiable(hidden);
  final Catalog catalog;
  final Map<String, Article> saved;
  final Set<String> read, hidden;
  final bool syncing, showImages;
  final String message, storageMessage;
  final DateTime? lastCheckedAt;
  final bool storageReadFailed;
  final bool savedRecoveryRequired, savedRecoveryCanRestore, recoveringSaved;
  final double fontScale;
  List<Article>? _sortedSavedCache;
  List<String>? _savedCategoriesCache;
  Map<String, int>? _unreadCountsCache;

  List<Article> get _sortedSaved =>
      _sortedSavedCache ??= List.unmodifiable(sortArticles(saved.values));
  LibraryState copyWith({
    Catalog? catalog,
    Map<String, Article>? saved,
    Set<String>? read,
    Set<String>? hidden,
    bool? syncing,
    String? message,
    DateTime? lastCheckedAt,
    double? fontScale,
    bool? showImages,
    String? storageMessage,
    bool? storageReadFailed,
    bool? savedRecoveryRequired,
    bool? savedRecoveryCanRestore,
    bool? recoveringSaved,
  }) {
    final next = LibraryState(
      catalog: catalog ?? this.catalog,
      saved: saved ?? this.saved,
      read: read ?? this.read,
      hidden: hidden ?? this.hidden,
      syncing: syncing ?? this.syncing,
      message: message ?? this.message,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      fontScale: fontScale ?? this.fontScale,
      showImages: showImages ?? this.showImages,
      storageMessage: storageMessage ?? this.storageMessage,
      storageReadFailed: storageReadFailed ?? this.storageReadFailed,
      savedRecoveryRequired:
          savedRecoveryRequired ?? this.savedRecoveryRequired,
      savedRecoveryCanRestore:
          savedRecoveryCanRestore ?? this.savedRecoveryCanRestore,
      recoveringSaved: recoveringSaved ?? this.recoveringSaved,
    );
    if (saved == null) next._sortedSavedCache = _sortedSavedCache;
    if (saved == null && catalog == null) {
      next._savedCategoriesCache = _savedCategoriesCache;
    }
    if (read == null && catalog == null) {
      next._unreadCountsCache = _unreadCountsCache;
    }
    return next;
  }

  bool isFollowed(String id) => !hidden.contains(id);

  Map<String, int> get articleCounts => catalog.articleCounts;

  Map<String, int> get unreadCounts =>
      _unreadCountsCache ??= Map.unmodifiable(_countUnreadArticles());

  Map<String, int> _countUnreadArticles() {
    final counts = <String, int>{};
    for (final article in catalog.articles) {
      if (read.contains(article.id)) continue;
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
      _savedCategoriesCache ??= List.unmodifiable(
        saved.values
            .expand((article) => categoriesFor(article, savedOnly: true))
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
      );

  Iterable<String> categoriesFor(Article article, {bool savedOnly = false}) {
    if (savedOnly && article.savedCategories.isNotEmpty) {
      return article.savedCategories;
    }
    return article.sources.map((id) => catalog.feedsById[id]?.category ?? '');
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
    final start = readingStart(period, readingNow)?.microsecondsSinceEpoch;
    final end = readingNow.microsecondsSinceEpoch;
    return (savedOnly ? _sortedSaved : catalog.articles)
        .where(
          (article) =>
              (savedOnly || article.sources.any(enabled.contains)) &&
              (!unreadOnly || !read.contains(article.id)) &&
              (category.isEmpty ||
                  categoriesFor(
                    article,
                    savedOnly: savedOnly,
                  ).contains(category)) &&
              (start == null ||
                  (article.publishedEpoch >= start &&
                      article.publishedEpoch <= end)) &&
              (canonical.isEmpty || article.sources.contains(canonical)) &&
              (needle.isEmpty || article.searchText.contains(needle)),
        )
        .toList();
  }
}
