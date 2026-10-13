class Feed {
  const Feed({
    required this.id,
    required this.title,
    required this.url,
    this.description = '',
    this.status = 'ok',
    this.enabled = true,
    this.category = '',
    this.error = '',
    this.collectionStatus = '',
  });
  final String id,
      title,
      url,
      description,
      status,
      category,
      error,
      collectionStatus;
  String get effectiveStatus => !enabled
      ? collectionStatus == 'archived'
            ? 'archived'
            : 'disabled'
      : status == 'error'
      ? 'error'
      : collectionStatus.isNotEmpty
      ? collectionStatus
      : status == 'ok'
      ? 'active'
      : status;
  final bool enabled;
  factory Feed.fromJson(Map<String, dynamic> json) => Feed(
    id: json['id'] as String,
    title: json['title'] as String,
    url: json['feed_url'] as String,
    description: json['description'] as String? ?? '',
    status: json['status'] as String? ?? 'ok',
    enabled: json['enabled'] as bool? ?? true,
    category: json['category'] as String? ?? '',
    error: json['error'] as String? ?? '',
    collectionStatus: json['collection_status'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'feed_url': url,
    'description': description,
    'status': status,
    'enabled': enabled,
    'category': category,
    'error': error,
    'collection_status': collectionStatus,
  };
}

class Article {
  Article({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.url,
    required this.publishedAt,
    this.sourceTitle = '',
    this.summary = '',
    this.imageUrl = '',
    List<String> sourceIds = const [],
    List<String> legacyIds = const [],
    this.dateInferred = false,
    List<String> savedCategories = const [],
  }) : sourceIds = List.unmodifiable(sourceIds),
       legacyIds = List.unmodifiable(legacyIds),
       savedCategories = List.unmodifiable(savedCategories),
       sources = List.unmodifiable(sourceIds.isEmpty ? [sourceId] : sourceIds),
       searchText = '$title $sourceTitle $summary'.toLowerCase(),
       publishedEpoch = publishedAt.microsecondsSinceEpoch;
  final String id, sourceId, title, url, sourceTitle, summary, imageUrl;
  final DateTime publishedAt;
  final bool dateInferred;
  final List<String> sourceIds, legacyIds, savedCategories;
  final List<String> sources;
  final String searchText;
  final int publishedEpoch;
  factory Article.fromJson(
    Map<String, dynamic> json, [
    Map<String, Feed> feeds = const {},
  ]) {
    final url = json['url'] as String;
    if (!isWebUrl(url)) throw const FormatException('Invalid article URL');
    if ((json['id'] as String).isEmpty) {
      throw const FormatException('Missing article identity');
    }
    return Article(
      id: json['id'] as String,
      sourceIds: List<String>.from(json['source_ids'] as List<dynamic>? ?? []),
      legacyIds: List<String>.from(json['legacy_ids'] as List<dynamic>? ?? []),
      savedCategories: List<String>.from(
        json['saved_categories'] as List<dynamic>? ?? [],
      ),
      sourceId: json['source_id'] as String,
      title: json['title'] as String,
      url: url,
      publishedAt: DateTime.parse(json['published_at'] as String),
      dateInferred: json['date_inferred'] as bool? ?? false,
      sourceTitle:
          feeds[json['source_id']]?.title ??
          json['source_title'] as String? ??
          '未知来源',
      summary: json['summary'] as String? ?? '',
      imageUrl: isWebUrl(json['image_url'] as String? ?? '')
          ? json['image_url'] as String
          : '',
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'source_id': sourceId,
    'source_ids': sources,
    'legacy_ids': legacyIds,
    'saved_categories': savedCategories,
    'source_title': sourceTitle,
    'title': title,
    'url': url,
    'published_at': publishedAt.toUtc().toIso8601String(),
    'date_inferred': dateInferred,
    'summary': summary,
    'image_url': imageUrl,
  };
}

bool isWebUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      {'https', 'http'}.contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

class Catalog {
  Catalog({
    required this.generatedAt,
    required List<Feed> feeds,
    required List<Article> articles,
    Map<String, String> sourceAliases = const {},
  }) : feeds = List.unmodifiable(feeds),
       articles = List.unmodifiable(sortArticles(articles)),
       sourceAliases = Map.unmodifiable(sourceAliases) {
    feedsById = Map.unmodifiable({for (final feed in feeds) feed.id: feed});
    feedSearch = Map.unmodifiable({
      for (final feed in feeds)
        feed.id:
            '${feed.title} ${feed.description} ${feed.url} ${feed.category}'
                .toLowerCase(),
    });
    categories = List.unmodifiable(
      feeds
          .map((feed) => feed.category)
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort(),
    );
    final counts = <String, int>{};
    for (final article in articles) {
      for (final id in article.sources.toSet()) {
        counts.update(id, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    articleCounts = Map.unmodifiable(counts);
  }
  final DateTime generatedAt;
  late final Map<String, Feed> feedsById;
  late final Map<String, String> feedSearch;
  late final Map<String, int> articleCounts;
  late final List<String> categories;
  final List<Feed> feeds;
  final List<Article> articles;
  final Map<String, String> sourceAliases;
  factory Catalog.fromJson(Map<String, dynamic> json) {
    final feeds = (json['feeds'] as List<dynamic>)
        .map((value) => Feed.fromJson(value as Map<String, dynamic>))
        .toList();
    final byId = {for (final feed in feeds) feed.id: feed};
    final articles = (json['articles'] as List<dynamic>)
        .where(
          (value) =>
              byId.containsKey((value as Map<String, dynamic>)['source_id']),
        )
        .map((value) => Article.fromJson(value as Map<String, dynamic>, byId))
        .toList();
    return Catalog(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      feeds: feeds,
      articles: articles,
      sourceAliases: (json['source_aliases'] as Map<String, dynamic>? ?? {})
          .cast<String, String>(),
    );
  }
  Map<String, dynamic> toJson() => {
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'source_aliases': sourceAliases,
    'feeds': feeds.map((feed) => feed.toJson()).toList(),
    'articles': articles.map((article) => article.toJson()).toList(),
  };
}

/// Keep input order for equal timestamps, including after filtering a queue.
List<Article> sortArticles(Iterable<Article> articles) {
  final indexed = articles.indexed.toList()
    ..sort((a, b) {
      final byDate = b.$2.publishedEpoch.compareTo(a.$2.publishedEpoch);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
  return indexed.map((entry) => entry.$2).toList();
}
