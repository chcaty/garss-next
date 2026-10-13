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
  CatalogRepository repository(
    Map<String, dynamic> docs, {
    void Function(Uri)? onRequest,
  }) => CatalogRepository(
    MockClient((request) async {
      onRequest?.call(request.url);
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
  test('same verified snapshot only fetches index meta and manifest and returns identical object', () async {
    final requests = <String>[];
    final repo = repository(
      documents(),
      onRequest: (uri) => requests.add(uri.path),
    );
    final first = await repo.fetch();
    expect(requests, hasLength(5));
    requests.clear();
    final second = await repo.fetch();
    expect(identical(first, second), isTrue);
    expect(requests, hasLength(3));
    expect(
      requests.where(
        (path) =>
            path.endsWith('/articles.json') || path.endsWith('/feeds.json'),
      ),
      isEmpty,
    );
  });

  test('fresh repository cannot trust previous snapshot ID without verifying files', () async {
    final docs = documents();
    await repository(docs).fetch();
    docs['/garss-next/api/v1/snapshots/one/articles.json'] = 'tampered';
    await expectLater(repository(docs).fetch(), throwsFormatException);
  });

  test('changed checksum under same snapshot ID is revalidated instead of short circuited', () async {
    final docs = documents();
    final requests = <String>[];
    final repo = repository(docs, onRequest: (uri) => requests.add(uri.path));
    final old = await repo.fetch();
    final changed = articles.replaceFirst('Article', 'Changed');
    docs['/garss-next/api/v1/snapshots/one/articles.json'] = changed;
    docs['/garss-next/api/v1/snapshots/one/manifest.json']['files']['articles.json'] =
        contract(changed);
    requests.clear();
    final next = await repo.fetch();
    expect(next.articles.single.title, 'Changed');
    expect(identical(old, next), isFalse);
    expect(requests, hasLength(5));
  });

  test('changed byte count cannot reuse a previously verified snapshot', () async {
    final docs = documents();
    final repo = repository(docs);
    await repo.fetch();
    docs['/garss-next/api/v1/snapshots/one/manifest.json']['files']['articles.json']['bytes'] +=
        1;
    await expectLater(repo.fetch(), throwsFormatException);
  });

  test('endpoint changes are checked even for previously verified snapshot ID', () async {
    final docs = documents();
    final repo = repository(docs);
    await repo.fetch();
    docs['/garss-next/api/v1/snapshots/one/manifest.json']['articles_endpoint'] =
        'https://evil.example/articles.json';
    await expectLater(repo.fetch(), throwsFormatException);
  });

  test('same-origin endpoint change fetches and verifies files again', () async {
    final docs = documents();
    final requests = <String>[];
    final repo = repository(docs, onRequest: (uri) => requests.add(uri.path));
    await repo.fetch();
    docs['/garss-next/api/v1/snapshots/one/manifest.json']['articles_endpoint'] =
        './alternate.json';
    docs['/garss-next/api/v1/snapshots/one/alternate.json'] = articles;
    requests.clear();
    await repo.fetch();
    expect(requests, hasLength(5));
    expect(
      requests,
      contains('/garss-next/api/v1/snapshots/one/alternate.json'),
    );
  });

  test('mixed generation is rejected after matching file checksums', () async {
    final docs = documents();
    final changed = articles.replaceAll(generated, '2026-10-02T00:00:00Z');
    docs['/garss-next/api/v1/snapshots/one/articles.json'] = changed;
    docs['/garss-next/api/v1/snapshots/one/manifest.json']['files']['articles.json'] =
        contract(changed);
    await expectLater(repository(docs).fetch(), throwsFormatException);
  });

  test('malformed JSON remains rejected even with matching SHA and byte length', () async {
    final docs = documents();
    const changed = '{bad json';
    docs['/garss-next/api/v1/snapshots/one/articles.json'] = changed;
    docs['/garss-next/api/v1/snapshots/one/manifest.json']['files']['articles.json'] =
        contract(changed);
    await expectLater(repository(docs).fetch(), throwsFormatException);
  });

  test(
    'rotation rediscovery retries once and validates the new complete snapshot',
    () async {
      final docs = documents();
      var discoveries = 0;
      final repo = repository(
        docs,
        onRequest: (uri) {
          if (uri.path.endsWith('/index.json')) {
            discoveries++;
            if (discoveries == 1) {
              docs['/garss-next/api/v1/meta.json']['snapshot_endpoint'] =
                  './snapshots/gone/manifest.json';
            } else {
              docs['/garss-next/api/v1/meta.json']['snapshot_endpoint'] =
                  './snapshots/one/manifest.json';
            }
          }
        },
      );
      final snapshot = await repo.fetch();
      expect(snapshot.articles.single.id, 'a');
      expect(discoveries, 2);
    },
  );

  test(
    'failed rotated refresh does not poison last validated snapshot',
    () async {
      final docs = documents();
      final repo = repository(docs);
      final verified = await repo.fetch();
      final manifest = docs['/garss-next/api/v1/snapshots/one/manifest.json'];
      final goodContract =
          manifest['files']['articles.json'] as Map<String, Object>;
      manifest['files']['articles.json'] = <String, Object>{
        ...goodContract,
        'sha256': List.filled(64, '0').join(),
      };
      await expectLater(repo.fetch(), throwsFormatException);
      manifest['files']['articles.json'] = goodContract;
      expect(identical(await repo.fetch(), verified), isTrue);
    },
  );
}
