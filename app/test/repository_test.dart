import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garss_app/data/repository.dart';

void main() {
  const generated = '2026-10-01T00:00:00Z';
  final feeds = jsonEncode({
    'generated_at': generated,
    'feeds': [
      {'id': 's', 'title': 'Source', 'feed_url': 'https://example.com/feed'},
    ],
  });
  final articles = jsonEncode({
    'generated_at': generated,
    'articles': [
      {
        'id': 'a',
        'source_id': 's',
        'title': 'Article',
        'url': 'https://example.com/post',
        'published_at': generated,
      },
    ],
  });
  Map<String, Object> contract(String body) => {
    'bytes': utf8.encode(body).length,
    'sha256': sha256.convert(utf8.encode(body)).toString(),
  };
  Map<String, dynamic> documents() => {
    '/garss-next/api/index.json': {
      'current_version': 'v1',
      'versions': {'v1': './v1/meta.json'},
    },
    '/garss-next/api/v1/meta.json': {
      'generated_at': generated,
      'snapshot_id': 'one',
      'snapshot_endpoint': './snapshots/one/manifest.json',
    },
    '/garss-next/api/v1/snapshots/one/manifest.json': {
      'generated_at': generated,
      'snapshot_id': 'one',
      'feeds_endpoint': './feeds.json',
      'articles_endpoint': './articles.json',
      'files': {
        'feeds.json': contract(feeds),
        'articles.json': contract(articles),
      },
    },
    '/garss-next/api/v1/snapshots/one/feeds.json': feeds,
    '/garss-next/api/v1/snapshots/one/articles.json': articles,
  };
  CatalogRepository repository(Map<String, dynamic> docs) => CatalogRepository(
    MockClient((request) async {
      final value = docs[request.url.path];
      return http.Response(
        value is String ? value : jsonEncode(value),
        value == null ? 404 : 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  test('verified snapshot resolves source names and supports older no-media records', () async {
    final catalog = await repository(documents()).fetch();
    expect(catalog.articles.single.sourceTitle, 'Source');
    expect(catalog.articles.single.summary, isEmpty);
    expect(catalog.articles.single.imageUrl, isEmpty);
  });
  test('tampered snapshot is rejected', () async {
    final docs = documents();
    docs['/garss-next/api/v1/snapshots/one/articles.json'] = articles
        .replaceFirst('Article', 'Tampered');
    await expectLater(repository(docs).fetch(), throwsFormatException);
  });
  test('foreign endpoint cannot receive API requests', () async {
    final repo = repository(documents());
    expect(
      () => repo.endpoint(
        Uri.parse('https://chcaty.github.io/garss-next/api/index.json'),
        'https://evil.example/data',
      ),
      throwsFormatException,
    );
    expect(
      () => repo.endpoint(
        Uri.parse('https://chcaty.github.io/garss-next/api/index.json'),
        '../../other/api.json',
      ),
      throwsFormatException,
    );
  });
}
