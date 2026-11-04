import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/repository.dart';

import 'support/snapshot_fixture.dart';

class StreamingClient extends http.BaseClient {
  StreamingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  test(
    'verified five-day snapshot uses app API only and resolves names',
    () async {
      final requests = <String>[];
      final catalog = await snapshotRepository(
        snapshotDocuments(),
        requests: requests,
      ).fetch();
      expect(catalog.articles.single.sourceTitle, 'Source');
      expect(catalog.articles.single.summary, isEmpty);
      expect(catalog.articles.single.imageUrl, isEmpty);
      expect(catalog.snapshotId, 'one');
      expect(catalog.retentionDays, 5);
      expect(catalog.timezone, 'Asia/Shanghai');
      expect(requests, hasLength(4));
      expect(
        requests.every((path) => path.startsWith('/garss-next/api/v1/app/')),
        isTrue,
      );
    },
  );

  test('unchanged snapshot only fetches meta with valid app cache', () async {
    final requests = <String>[];
    final repo = snapshotRepository(snapshotDocuments(), requests: requests);
    final cached = Catalog.fromJson((await repo.fetch()).toJson());
    requests.clear();
    expect(await repo.fetch(cached: cached), same(cached));
    expect(requests, [appMetaPath]);
  });

  test(
    'legacy, different host, and different ID caches cannot skip data',
    () async {
      final requests = <String>[];
      final repo = snapshotRepository(snapshotDocuments(), requests: requests);
      final cached = (await repo.fetch()).toJson();
      for (final change in [
        {'snapshot_id': null},
        {'snapshot_id': 'older'},
        {'snapshot_source': 'https://other.example/api/v1/app/meta.json'},
        {'retention_days': 30},
      ]) {
        requests.clear();
        await repo.fetch(cached: Catalog.fromJson({...cached, ...change}));
        expect(requests, hasLength(4));
      }
    },
  );

  test('tampered, truncated and mixed snapshots are rejected', () async {
    for (final replacement in ['Tampered', 'Article ']) {
      final docs = snapshotDocuments();
      docs['$snapshotPath/articles.json'] =
          (docs['$snapshotPath/articles.json'] as String).replaceFirst(
            'Article',
            replacement,
          );
      await expectLater(
        snapshotRepository(docs).fetch(),
        throwsFormatException,
      );
    }
    final docs = snapshotDocuments();
    (docs['$snapshotPath/manifest.json']
            as Map<String, dynamic>)['generated_at'] =
        '2026-10-02T00:00:00Z';
    await expectLater(snapshotRepository(docs).fetch(), throwsFormatException);
  });

  test('deployment rotation rediscovers once and succeeds', () async {
    final docs = snapshotDocuments();
    var discoveries = 0, manifests = 0;
    final repo = CatalogRepository(
      MockClient((request) async {
        if (request.url.path == appMetaPath) discoveries++;
        var value = docs[request.url.path];
        if (request.url.path.endsWith('manifest.json') && manifests++ == 0) {
          value = {...value as Map<String, dynamic>, 'snapshot_id': 'rotated'};
        }
        return http.Response(value is String ? value : jsonEncode(value), 200);
      }),
    );
    expect((await repo.fetch()).snapshotId, 'one');
    expect(discoveries, 2);
  });

  test('missing app endpoint never falls back to the web catalog', () async {
    final requests = <String>[];
    await expectLater(
      snapshotRepository({}, requests: requests).fetch(),
      throwsFormatException,
    );
    expect(requests, [appMetaPath, appMetaPath]);
  });

  test(
    'wrong retention policy and oversized manifest fail before data fetch',
    () async {
      for (final change in [
        {'retention_days': 30},
        {'timezone': 'UTC'},
        {'api_version': '2.0'},
      ]) {
        final docs = snapshotDocuments(), requests = <String>[];
        docs[appMetaPath] = {
          ...docs[appMetaPath] as Map<String, dynamic>,
          ...change,
        };
        await expectLater(
          snapshotRepository(docs, requests: requests).fetch(),
          throwsFormatException,
        );
        expect(requests, [appMetaPath, appMetaPath]);
      }
      final docs = snapshotDocuments(), requests = <String>[];
      final manifest =
          docs['$snapshotPath/manifest.json'] as Map<String, dynamic>;
      (manifest['files']['articles.json'] as Map<String, Object>)['bytes'] =
          CatalogRepository.maxDocumentBytes + 1;
      await expectLater(
        snapshotRepository(docs, requests: requests).fetch(),
        throwsFormatException,
      );
      expect(requests.any((path) => path.endsWith('/articles.json')), isFalse);
    },
  );

  test(
    'foreign and 30-day endpoints cannot receive app data requests',
    () async {
      for (final endpoint in [
        'https://evil.example/data',
        '../../../../other/api.json',
        '../snapshots/one/manifest.json',
        './snapshots/one/manifest.json?redirect=1',
      ]) {
        final docs = snapshotDocuments(), requests = <String>[];
        (docs[appMetaPath] as Map<String, dynamic>)['snapshot_endpoint'] =
            endpoint;
        await expectLater(
          snapshotRepository(docs, requests: requests).fetch(),
          throwsFormatException,
        );
        expect(requests, [appMetaPath, appMetaPath]);
      }
    },
  );

  test(
    'unknown or dishonest content length is bounded during streaming',
    () async {
      for (final contentLength in <int?>[null, 1]) {
        var emitted = 0;
        final cancelled = Completer<void>();
        Stream<List<int>> body() async* {
          try {
            for (var i = 0; i < 100; i++) {
              emitted++;
              yield [0, 1];
            }
          } finally {
            cancelled.complete();
          }
        }

        final repo = CatalogRepository(
          StreamingClient(
            (_) async => http.StreamedResponse(
              body(),
              200,
              contentLength: contentLength,
            ),
          ),
        );
        await expectLater(
          repo.get(repo.appMetaUrl, maxBytes: 3),
          throwsFormatException,
        );
        expect(emitted, 2);
        await cancelled.future.timeout(const Duration(seconds: 1));
        expect(emitted, 2);
      }
    },
  );

  test('oversized Content-Length is rejected without buffering body', () async {
    var received = 0;
    final repo = CatalogRepository(
      StreamingClient(
        (_) async => http.StreamedResponse(
          Stream.value([0]).map((chunk) {
            received++;
            return chunk;
          }),
          200,
          contentLength: 100,
        ),
      ),
    );
    await expectLater(
      repo.get(repo.appMetaUrl, maxBytes: 5),
      throwsFormatException,
    );
    expect(received, 0);
  });

  test('redirects cannot escape app endpoint validation', () async {
    final repo = CatalogRepository(
      StreamingClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: {'location': 'https://example.com/30-day-articles.json'},
        );
      }),
    );
    await expectLater(repo.fetch(), throwsFormatException);
  });

  test('a stalled body times out and cancels the stream', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final repo = CatalogRepository(
      StreamingClient((_) async => http.StreamedResponse(body.stream, 200)),
      requestTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      repo.get(repo.appMetaUrl),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await body.close();
  });
}
