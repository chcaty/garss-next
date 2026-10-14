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
  String? _validatedIdentity;
  Catalog? _validatedCatalog;
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

  Future<Map<String, dynamic>> decode(http.Response response) =>
      compute(_decodeJsonBytes, response.bodyBytes);
  Future<Catalog> fetch() async {
    // Retry discovery once if a Pages deployment rotated the snapshot pointer.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final indexUrl = base.resolve('api/index.json');
        final index = await decode(await get(indexUrl));
        if (index['current_version'] != 'v1') {
          throw const FormatException('Unsupported API version');
        }
        final metaUrl = endpoint(
          indexUrl,
          (index['versions'] as Map<String, dynamic>)['v1'] as String,
        );
        final meta = await decode(await get(metaUrl));
        final manifestUrl = endpoint(
          metaUrl,
          meta['snapshot_endpoint'] as String,
        );
        final manifest = await decode(await get(manifestUrl));
        if (manifest['snapshot_id'] != meta['snapshot_id'] ||
            manifest['generated_at'] != meta['generated_at']) {
          throw const FormatException('Snapshot pointer changed');
        }
        final files = manifest['files'] as Map<String, dynamic>;
        final feedsUrl = endpoint(
          manifestUrl,
          manifest['feeds_endpoint'] as String,
        );
        final articlesUrl = endpoint(
          manifestUrl,
          manifest['articles_endpoint'] as String,
        );
        final feedContract = _fileContract(files['feeds.json']);
        final articleContract = _fileContract(files['articles.json']);
        final identity = jsonEncode([
          manifestUrl.toString(),
          manifest['snapshot_id'] as String,
          manifest['generated_at'] as String,
          feedsUrl.toString(),
          articlesUrl.toString(),
          feedContract['bytes'],
          feedContract['sha256'],
          articleContract['bytes'],
          articleContract['sha256'],
        ]);
        // Only reuse a catalog this repository actually verified. A disk cache,
        // equal timestamp, or snapshot ID alone is never proof of integrity.
        if (identity == _validatedIdentity && _validatedCatalog != null) {
          return _validatedCatalog!;
        }
        final responses = await Future.wait([get(feedsUrl), get(articlesUrl)]);
        final catalog = await compute(
          _decodeSnapshot,
          _SnapshotBytes(
            responses[0].bodyBytes,
            responses[1].bodyBytes,
            feedContract,
            articleContract,
            manifest['generated_at'] as String,
          ),
        );
        _validatedIdentity = identity;
        _validatedCatalog = catalog;
        return catalog;
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
      get(base.resolve('api/v1/feeds.json')),
    ]);
    final decoded = await Future.wait(documents.map(decode));
    final ledger = decoded[0], health = decoded[1], feeds = decoded[2];
    if (ledger['generated_at'] != health['generated_at'] ||
        ledger['generated_at'] != feeds['generated_at']) {
      throw const FormatException('Mixed sync records');
    }
    return SyncReport.fromJson({
      ...ledger,
      'sources': health['sources'],
      'feeds': feeds['feeds'],
    });
  }
}

Map<String, dynamic> _decodeJsonBytes(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

Map<String, dynamic> _fileContract(dynamic value) {
  final contract = value as Map<String, dynamic>;
  final bytes = contract['bytes'] as int;
  final hash = contract['sha256'] as String;
  if (bytes < 0 ||
      bytes > 20 * 1024 * 1024 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
    throw const FormatException('Invalid snapshot file contract');
  }
  return {'bytes': bytes, 'sha256': hash};
}

class _SnapshotBytes {
  const _SnapshotBytes(
    this.feeds,
    this.articles,
    this.feedContract,
    this.articleContract,
    this.generatedAt,
  );
  final Uint8List feeds, articles;
  final Map<String, dynamic> feedContract, articleContract;
  final String generatedAt;
}

Catalog _decodeSnapshot(_SnapshotBytes snapshot) {
  for (final (bytes, contract) in [
    (snapshot.feeds, snapshot.feedContract),
    (snapshot.articles, snapshot.articleContract),
  ]) {
    if (bytes.length != contract['bytes'] ||
        sha256.convert(bytes).toString() != contract['sha256']) {
      throw const FormatException('Snapshot integrity check failed');
    }
  }
  final feeds = _decodeJsonBytes(snapshot.feeds),
      articles = _decodeJsonBytes(snapshot.articles);
  if (feeds['generated_at'] != snapshot.generatedAt ||
      articles['generated_at'] != snapshot.generatedAt) {
    throw const FormatException('Mixed snapshots');
  }
  return Catalog.fromJson({
    'generated_at': snapshot.generatedAt,
    'feeds': feeds['feeds'],
    'source_aliases': feeds['source_aliases'],
    'articles': articles['articles'],
  });
}
