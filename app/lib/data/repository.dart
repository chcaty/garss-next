import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'sync_report.dart';

const defaultBaseUrl = String.fromEnvironment(
  'GARSS_BASE_URL',
  defaultValue: 'https://chcaty.github.io/garss-next/',
);

class CatalogRepository {
  CatalogRepository(this.client, {String baseUrl = defaultBaseUrl})
    : base = Uri.parse(baseUrl);
  final http.Client client;
  final Uri base;
  Uri endpoint(Uri parent, String value) {
    final result = parent.resolve(value);
    if (result.origin != base.origin ||
        !result.path.startsWith(base.resolve('api/').path)) {
      throw const FormatException('Snapshot endpoint is outside this catalog');
    }
    return result;
  }

  Future<http.Response> get(Uri url) async {
    final response = await client
        .get(url, headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Catalog unavailable');
    }
    return response;
  }

  Map<String, dynamic> decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  Future<Catalog> fetch() async {
    // Retry discovery once if a Pages deployment rotated the snapshot pointer.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final indexUrl = base.resolve('api/index.json');
        final index = decode(await get(indexUrl));
        if (index['current_version'] != 'v1') {
          throw const FormatException('Unsupported API version');
        }
        final metaUrl = endpoint(
          indexUrl,
          (index['versions'] as Map<String, dynamic>)['v1'] as String,
        );
        final meta = decode(await get(metaUrl));
        final manifestUrl = endpoint(
          metaUrl,
          meta['snapshot_endpoint'] as String,
        );
        final manifest = decode(await get(manifestUrl));
        if (manifest['snapshot_id'] != meta['snapshot_id'] ||
            manifest['generated_at'] != meta['generated_at']) {
          throw const FormatException('Snapshot pointer changed');
        }
        final files = manifest['files'] as Map<String, dynamic>;
        final responses = await Future.wait([
          get(endpoint(manifestUrl, manifest['feeds_endpoint'] as String)),
          get(endpoint(manifestUrl, manifest['articles_endpoint'] as String)),
        ]);
        for (var i = 0; i < 2; i++) {
          final name = i == 0 ? 'feeds.json' : 'articles.json';
          final contract = files[name] as Map<String, dynamic>;
          if (responses[i].bodyBytes.length != contract['bytes'] ||
              sha256.convert(responses[i].bodyBytes).toString() !=
                  contract['sha256']) {
            throw const FormatException('Snapshot integrity check failed');
          }
        }
        final feeds = decode(responses[0]), articles = decode(responses[1]);
        if (feeds['generated_at'] != manifest['generated_at'] ||
            articles['generated_at'] != manifest['generated_at']) {
          throw const FormatException('Mixed snapshots');
        }
        return await compute(Catalog.fromJson, {
          'generated_at': manifest['generated_at'],
          'feeds': feeds['feeds'],
          'source_aliases': feeds['source_aliases'],
          'articles': articles['articles'],
        });
      } catch (_) {
        if (attempt == 1) rethrow;
      }
    }
    throw const FormatException('Catalog unavailable');
  }

  Future<SyncReport> fetchSyncReport() async {
    final documents = await Future.wait([
      get(base.resolve('api/v1/sync.json')),
      get(base.resolve('api/v1/source-state.json')),
    ]);
    final ledger = decode(documents[0]), health = decode(documents[1]);
    if (ledger['generated_at'] != health['generated_at']) {
      throw const FormatException('Mixed sync records');
    }
    return SyncReport.fromJson({...ledger, 'sources': health['sources']});
  }
}
