import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garss_app/data/repository.dart';

const snapshotGenerated = '2026-10-01T00:00:00Z';
const appMetaPath = '/garss-next/api/v1/app/meta.json';
const snapshotPath = '/garss-next/api/v1/app/snapshots/one';

Map<String, dynamic> snapshotDocuments({List<Map<String, dynamic>>? entries}) {
  final feeds = jsonEncode({
    'api_version': '1.0',
    'generated_at': snapshotGenerated,
    'feeds': [
      {'id': 's', 'title': 'Source', 'feed_url': 'https://example.com/feed'},
    ],
  });
  final articles = jsonEncode({
    'api_version': '1.0',
    'generated_at': snapshotGenerated,
    'articles':
        entries ??
        [
          {
            'id': 'a',
            'source_id': 's',
            'title': 'Article',
            'url': 'https://example.com/post',
            'published_at': snapshotGenerated,
          },
        ],
  });
  Map<String, Object> contract(String body) => {
    'bytes': utf8.encode(body).length,
    'sha256': sha256.convert(utf8.encode(body)).toString(),
  };
  const metadata = {
    'api_version': '1.0',
    'generated_at': snapshotGenerated,
    'snapshot_id': 'one',
    'retention_days': 5,
    'timezone': 'Asia/Shanghai',
    'window_start': '2026-09-27',
    'window_end': '2026-10-01',
  };
  return {
    appMetaPath: {
      ...metadata,
      'snapshot_endpoint': './snapshots/one/manifest.json',
    },
    '$snapshotPath/manifest.json': {
      ...metadata,
      'feeds_endpoint': './feeds.json',
      'articles_endpoint': './articles.json',
      'files': {
        'feeds.json': contract(feeds),
        'articles.json': contract(articles),
      },
    },
    '$snapshotPath/feeds.json': feeds,
    '$snapshotPath/articles.json': articles,
  };
}

CatalogRepository snapshotRepository(
  Map<String, dynamic> docs, {
  List<String>? requests,
}) => CatalogRepository(
  MockClient((request) async {
    requests?.add(request.url.path);
    final value = docs[request.url.path];
    return http.Response(
      value is String ? value : jsonEncode(value),
      value == null ? 404 : 200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);
