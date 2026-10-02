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
  });
  final String id, title, url, description, status, category, error;
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
  };
}

class Article {
  const Article({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.url,
    required this.publishedAt,
    this.sourceTitle = '',
    this.summary = '',
    this.imageUrl = '',
    this.sourceIds = const [],
    this.legacyIds = const [],
    this.dateInferred = false,
  });
  final String id, sourceId, title, url, sourceTitle, summary, imageUrl;
  final DateTime publishedAt;
  final bool dateInferred;
  final List<String> sourceIds, legacyIds;
  List<String> get sources => sourceIds.isEmpty ? [sourceId] : sourceIds;
  factory Article.fromJson(
    Map<String, dynamic> json, [
    Map<String, Feed> feeds = const {},
  ]) {
    final url = json['url'] as String;
    if (!isWebUrl(url)) throw const FormatException('Invalid article URL');
    return Article(
      id: json['id'] as String,
      sourceIds: (json['source_ids'] as List<dynamic>? ?? []).cast<String>(),
      legacyIds: (json['legacy_ids'] as List<dynamic>? ?? []).cast<String>(),
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
       articles = List.unmodifiable(articles),
       sourceAliases = Map.unmodifiable(sourceAliases);
  final DateTime generatedAt;
  final List<Feed> feeds;
  final List<Article> articles;
  final Map<String, String> sourceAliases;
  factory Catalog.fromJson(Map<String, dynamic> json) {
    final feeds = (json['feeds'] as List<dynamic>)
        .map((value) => Feed.fromJson(value as Map<String, dynamic>))
        .toList();
    final byId = {for (final feed in feeds) feed.id: feed};
    final articles =
        (json['articles'] as List<dynamic>)
            .where(
              (value) => byId.containsKey(
                (value as Map<String, dynamic>)['source_id'],
              ),
            )
            .map(
              (value) => Article.fromJson(value as Map<String, dynamic>, byId),
            )
            .toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
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
