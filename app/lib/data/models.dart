class Feed {
  const Feed({
    required this.id,
    required this.title,
    required this.url,
    this.description = '',
    this.status = 'ok',
    this.enabled = true,
    this.category = '',
  });
  final String id, title, url, description, status, category;
  final bool enabled;
  factory Feed.fromJson(Map<String, dynamic> json) => Feed(
    id: json['id'] as String,
    title: json['title'] as String,
    url: json['feed_url'] as String,
    description: json['description'] as String? ?? '',
    status: json['status'] as String? ?? 'ok',
    enabled: json['enabled'] as bool? ?? true,
    category: json['category'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'feed_url': url,
    'description': description,
    'status': status,
    'enabled': enabled,
    'category': category,
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
  });
  final String id, sourceId, title, url, sourceTitle, summary, imageUrl;
  final DateTime publishedAt;
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
  }) : feeds = List.unmodifiable(feeds),
       articles = List.unmodifiable(articles);
  final DateTime generatedAt;
  final List<Feed> feeds;
  final List<Article> articles;
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
    );
  }
  Map<String, dynamic> toJson() => {
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'feeds': feeds.map((feed) => feed.toJson()).toList(),
    'articles': articles.map((article) => article.toJson()).toList(),
  };
}
