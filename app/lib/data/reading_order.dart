import 'models.dart';

List<Article> diversify(List<Article> articles) {
  final groups = <String, List<Article>>{};
  for (final article in articles) {
    groups.putIfAbsent(article.sourceId, () => []).add(article);
  }
  final result = <Article>[];
  for (var round = 0; result.length < articles.length; round++) {
    final batch = [
      for (final group in groups.values)
        if (round < group.length) group[round],
    ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    result.addAll(batch);
  }
  return result;
}
