import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Two complete slots and a small commit pointer keep interrupted writes from
/// replacing the last usable catalog. Reading state and bookmarks are separate.
class CatalogCache {
  CatalogCache(this.preferences);
  final SharedPreferences preferences;
  static const activeKey = 'catalog-app-active-v1';
  static const slotPrefix = 'catalog-app-slot-v1-';
  String? _activeSlot;

  Catalog? load() {
    final active = preferences.get(activeKey);
    if (active is String && (active == 'a' || active == 'b')) {
      for (final slot in [active, active == 'a' ? 'b' : 'a']) {
        try {
          final encoded = preferences.getString('$slotPrefix$slot');
          if (encoded == null) continue;
          final envelope = jsonDecode(encoded) as Map<String, dynamic>;
          final payload = envelope['payload'] as String;
          final bytes = utf8.encode(payload);
          if (envelope['version'] != 1 ||
              envelope['bytes'] != bytes.length ||
              envelope['sha256'] != sha256.convert(bytes).toString()) {
            continue;
          }
          final catalog = Catalog.fromJson(
            jsonDecode(payload) as Map<String, dynamic>,
          );
          _activeSlot = slot;
          return catalog;
        } catch (_) {
          // Try the other complete slot, then the pre-upgrade offline cache.
        }
      }
    }
    try {
      final legacy = preferences.getString('catalog-v1');
      if (legacy != null) {
        return Catalog.fromJson({
          ...jsonDecode(legacy) as Map<String, dynamic>,
          // An old cache has no verified app identity and cannot skip a download.
          'snapshot_id': null,
          'snapshot_source': null,
          'retention_days': null,
          'timezone': null,
        });
      }
    } catch (_) {
      // A corrupt cache must not prevent a fresh download or offline bookmarks.
    }
    return null;
  }

  Future<void> save(Catalog catalog) async {
    final encoded = await compute(_encodeCache, catalog.toJson());
    final next = _activeSlot == 'a' ? 'b' : 'a';
    try {
      if (!await preferences.setString('$slotPrefix$next', encoded)) {
        throw StateError('Could not stage catalog cache');
      }
      if (!await preferences.setString(activeKey, next)) {
        throw StateError('Could not commit catalog cache');
      }
    } catch (_) {
      // SharedPreferences optimistically changes its in-memory map before a
      // platform write completes. Reload it if a write is rejected.
      try {
        await preferences.reload();
      } catch (_) {}
      rethrow;
    }
    _activeSlot = next;
    // Only retire the large legacy cache after the smaller snapshot is committed.
    try {
      await preferences.remove('catalog-v1');
    } catch (_) {}
  }
}

String _encodeCache(Map<String, dynamic> catalog) {
  final payload = jsonEncode(catalog);
  final bytes = utf8.encode(payload);
  return jsonEncode({
    'version': 1,
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'payload': payload,
  });
}
