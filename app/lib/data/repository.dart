import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  CatalogRepository(
    this.client, {
    String baseUrl = defaultBaseUrl,
    this.requestTimeout = const Duration(seconds: 20),
  }) : base = Uri.parse(baseUrl);
  final http.Client client;
  final Uri base;
  final Duration requestTimeout;
  static const maxDocumentBytes = 20 * 1024 * 1024;
  static const maxMetadataBytes = 64 * 1024;
  static const maxFeedBytes = 4 * 1024 * 1024;

  Uri get appMetaUrl => base.resolve('api/v1/app/meta.json');

  Uri endpoint(Uri parent, String value) {
    final result = parent.resolve(value);
    if (!isWebUrl(result.toString()) ||
        result.origin != base.origin ||
        !result.path.startsWith(base.resolve('api/').path)) {
      throw const FormatException('Snapshot endpoint is outside this catalog');
    }
    return result;
  }

  Uri _appEndpoint(Uri parent, String value) {
    final result = endpoint(parent, value);
    if (!result.path.startsWith(base.resolve('api/v1/app/').path) ||
        result.hasQuery ||
        result.hasFragment) {
      throw const FormatException('Snapshot endpoint is outside the app API');
    }
    return result;
  }

  Future<http.Response> get(Uri url, {int maxBytes = maxDocumentBytes}) async {
    // Bound the actual stream, even when Content-Length is absent or dishonest.
    // A single deadline covers headers and body, including a slow-drip stream.
    final abort = Completer<void>();
    final deadline = DateTime.now().add(requestTimeout);
    StreamIterator<List<int>>? chunks;
    Duration remaining() {
      final value = deadline.difference(DateTime.now());
      if (value <= Duration.zero) throw TimeoutException('Catalog timed out');
      return value;
    }

    try {
      final request =
          http.AbortableRequest('GET', url, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers['Cache-Control'] = 'no-cache';
      final response = await client.send(request).timeout(remaining());
      chunks = StreamIterator(response.stream);
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength! > maxBytes)) {
        throw const FormatException('Catalog unavailable or too large');
      }
      final bytes = BytesBuilder(copy: false);
      while (await chunks.moveNext().timeout(remaining())) {
        final chunk = chunks.current;
        if (chunk.length > maxBytes - bytes.length) {
          throw const FormatException(
            'Catalog download exceeds its byte limit',
          );
        }
        bytes.add(chunk);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
        request: response.request,
      );
    } finally {
      abort.complete();
      // Start cancellation immediately without letting asynchronous teardown
      // keep a failed download (and its UI spinner) pending indefinitely.
      final cancellation = chunks?.cancel();
      if (cancellation != null) {
        unawaited(cancellation.then<void>((_) {}, onError: (Object _) {}));
      }
    }
  }

  Map<String, dynamic> decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

  void _validateAppMetadata(Map<String, dynamic> metadata) {
    if (metadata['api_version'] != '1.0' ||
        metadata['retention_days'] != 5 ||
        metadata['timezone'] != 'Asia/Shanghai' ||
        metadata['snapshot_id'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$')
            .hasMatch(metadata['snapshot_id'] as String) ||
        metadata['generated_at'] is! String ||
        DateTime.tryParse(metadata['generated_at'] as String) == null) {
      throw const FormatException('Unsupported app snapshot');
    }
  }

  Future<Catalog> fetch({Catalog? cached}) async {
    // Retry discovery once if a Pages deployment rotated the snapshot pointer.
    // Never fall back to the larger, 30-day web catalog.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final metaUrl = appMetaUrl;
        final meta = decode(await get(metaUrl, maxBytes: maxMetadataBytes));
        _validateAppMetadata(meta);
        final manifestUrl = _appEndpoint(
          metaUrl,
          meta['snapshot_endpoint'] as String,
        );
        if (cached != null &&
            cached.snapshotId == meta['snapshot_id'] &&
            cached.generatedAt ==
                DateTime.parse(meta['generated_at'] as String) &&
            cached.retentionDays == 5 &&
            cached.timezone == 'Asia/Shanghai' &&
            cached.snapshotSource == metaUrl.toString()) {
          return cached;
        }
        final manifest = decode(
          await get(manifestUrl, maxBytes: maxMetadataBytes),
        );
        _validateAppMetadata(manifest);
        for (final key in [
          'snapshot_id',
          'generated_at',
          'window_start',
          'window_end',
        ]) {
          if (manifest[key] != meta[key]) {
            throw const FormatException('Snapshot pointer changed');
          }
        }
        final files = manifest['files'] as Map<String, dynamic>;
        final limits = <int>[];
        for (final name in ['feeds.json', 'articles.json']) {
          final contract = files[name] as Map<String, dynamic>;
          final bytes = contract['bytes'];
          final checksum = contract['sha256'];
          final maximum = name == 'feeds.json'
              ? maxFeedBytes
              : maxDocumentBytes;
          if (bytes is! int ||
              bytes < 1 ||
              bytes > maximum ||
              checksum is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
            throw const FormatException('Invalid snapshot file contract');
          }
          limits.add(bytes);
        }
        final responses = await Future.wait([
          get(
            _appEndpoint(manifestUrl, manifest['feeds_endpoint'] as String),
            maxBytes: limits[0],
          ),
          get(
            _appEndpoint(manifestUrl, manifest['articles_endpoint'] as String),
            maxBytes: limits[1],
          ),
        ]);
        return await compute(_decodeSnapshot, {
          'manifest': manifest,
          'source': metaUrl.toString(),
          'feeds_bytes': responses[0].bodyBytes,
          'articles_bytes': responses[1].bodyBytes,
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
      get(base.resolve('api/v1/feeds.json')),
    ]);
    final ledger = decode(documents[0]),
        health = decode(documents[1]),
        feeds = decode(documents[2]);
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

// Decoding, hashing, and model construction run away from the UI isolate.
Catalog _decodeSnapshot(Map<String, dynamic> input) {
  final manifest = input['manifest'] as Map<String, dynamic>;
  final files = manifest['files'] as Map<String, dynamic>;
  final documents = <Map<String, dynamic>>[];
  for (final name in ['feeds', 'articles']) {
    final bytes = input['${name}_bytes'] as Uint8List;
    final contract = files['$name.json'] as Map<String, dynamic>;
    if (bytes.length != contract['bytes'] ||
        sha256.convert(bytes).toString() != contract['sha256']) {
      throw const FormatException('Snapshot integrity check failed');
    }
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (document['api_version'] != '1.0' ||
        document['generated_at'] != manifest['generated_at']) {
      throw const FormatException('Mixed snapshots');
    }
    documents.add(document);
  }
  return Catalog.fromJson({
    'generated_at': manifest['generated_at'],
    'snapshot_id': manifest['snapshot_id'],
    'snapshot_source': input['source'],
    'retention_days': manifest['retention_days'],
    'timezone': manifest['timezone'],
    'feeds': documents[0]['feeds'],
    'source_aliases': documents[0]['source_aliases'],
    'articles': documents[1]['articles'],
  });
}
