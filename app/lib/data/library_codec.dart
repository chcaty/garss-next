import 'dart:convert';

import 'models.dart';
import 'sync_report.dart';

class SavedDocument {
  SavedDocument(Map<String, Article> saved, this.requiresRecovery)
    : saved = Map.unmodifiable(saved);
  final Map<String, Article> saved;
  final bool requiresRecovery;
}

/// These top-level codecs can run in compute without capturing UI or storage.
SavedDocument decodeSavedDocument(String? original) {
  final saved = <String, Article>{};
  var requiresRecovery = false;
  if (original == null) return SavedDocument(saved, false);
  try {
    for (final value in jsonDecode(original) as List<dynamic>) {
      try {
        final article = Article.fromJson(value as Map<String, dynamic>);
        if (saved.containsKey(article.id)) {
          throw const FormatException('Duplicate saved identity');
        }
        saved[article.id] = article;
      } catch (_) {
        requiresRecovery = true;
      }
    }
  } catch (_) {
    requiresRecovery = true;
  }
  return SavedDocument(saved, requiresRecovery);
}

Catalog decodeCachedCatalog(String raw) =>
    Catalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);

String encodeCatalog(Catalog catalog) => jsonEncode(catalog.toJson());

String encodeSavedDocument(Map<String, Article> saved) =>
    jsonEncode(saved.values.map((article) => article.toJson()).toList());

SyncReport decodeCachedSyncReport(String raw) =>
    SyncReport.fromJson(jsonDecode(raw) as Map<String, dynamic>);

String encodeSyncReport(SyncReport report) => jsonEncode(report.toJson());
