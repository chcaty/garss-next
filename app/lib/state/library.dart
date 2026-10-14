import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/library_storage.dart';
import '../data/library_codec.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'library_state.dart';

export 'library_state.dart' show LibraryState;

final repositoryProvider = Provider<CatalogRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return CatalogRepository(client);
});
final libraryStorageProvider = FutureProvider<LibraryStorage>((ref) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return PreferencesLibraryStorage(preferences);
  } catch (_) {
    throw const LibraryStorageException('preferences');
  }
});
final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class LibraryController extends AsyncNotifier<LibraryState> {
  late LibraryStorage _storage;
  Catalog? _persistedCatalog;
  Future<void> _writes = Future.value();
  final Set<String> _unreadableKeys = {};
  bool _savedWritesBlocked = false;
  String? _savedOriginal, _pendingSavedBackup;
  int _backupSequence = 0;

  /// Includes all queued writes, useful to await before testing a restart.
  Future<void> get pendingWrites => _writes;

  T? _read<T>(String key) {
    try {
      return _storage.read(key) as T?;
    } catch (_) {
      _unreadableKeys.add(key);
      return null;
    }
  }

  List<String> _readList(String key) {
    try {
      return List<String>.from(_storage.read(key) as List? ?? []);
    } catch (_) {
      _unreadableKeys.add(key);
      return [];
    }
  }

  Future<void> _write(String key, Object value) async {
    if (!await _storage.write(key, value)) {
      throw LibraryStorageException(key);
    }
  }

  Future<void> _backupSaved(String original) async {
    // Never reuse a backup key: a later recovery must not erase an earlier one.
    String key;
    do {
      key =
          'saved-v2-quarantine-${DateTime.now().microsecondsSinceEpoch}-${_backupSequence++}';
    } while (_storage.read(key) != null);
    await _write(key, original);
    if (_storage.read(key) != original) {
      throw LibraryStorageException(key);
    }
  }

  Future<void> _writeSaved(Map<String, Article> saved) async {
    if (_savedWritesBlocked || _unreadableKeys.contains('saved-v2')) return;
    final original = _pendingSavedBackup;
    if (original != null) {
      await _backupSaved(original);
      _pendingSavedBackup = null;
    }
    await _write('saved-v2', await compute(encodeSavedDocument, saved));
  }

  @override
  Future<LibraryState> build() async {
    _storage = await ref.watch(libraryStorageProvider.future);
    _unreadableKeys.clear();
    _savedWritesBlocked = false;
    _savedOriginal = null;
    _pendingSavedBackup = null;
    Catalog? cached;
    try {
      final value = _read<String>('catalog-v1');
      if (value != null) {
        cached = await compute(decodeCachedCatalog, value);
      }
    } catch (_) {
      // A public cache can be replaced; personal records must be preserved.
    }
    _persistedCatalog = cached;
    final original = _read<String>('saved-v2');
    final document = await compute(decodeSavedDocument, original);
    final saved = {...document.saved};
    _savedWritesBlocked = document.requiresRecovery;
    if (_savedWritesBlocked) _savedOriginal = original;
    _savedWritesBlocked =
        _savedWritesBlocked || _unreadableKeys.contains('saved-v2');
    String message = '', storageMessage = '';
    Catalog catalog;
    if (cached != null) {
      catalog = cached;
      message = '显示本机缓存，可下拉刷新';
    } else {
      var fetched = false;
      try {
        catalog = await ref.read(repositoryProvider).fetch();
        fetched = true;
      } catch (_) {
        if (saved.isEmpty && !_savedWritesBlocked) rethrow;
        catalog = Catalog(
          generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          feeds: [],
          articles: [],
        );
        message = '暂时无法同步，可查看本机稍后读与恢复选项';
      }
      if (fetched) {
        try {
          await _write('catalog-v1', await compute(encodeCatalog, catalog));
          _persistedCatalog = catalog;
        } catch (_) {
          storageMessage = _catalogSaveFailure;
        }
      }
    }
    var migrated = false;
    for (final entry in saved.entries.toList()) {
      if (entry.value.savedCategories.isEmpty) {
        final categories = entry.value.sources
            .map((id) => catalog.feedsById[id]?.category ?? '')
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList();
        if (categories.isNotEmpty) {
          saved[entry.key] = Article.fromJson({
            ...entry.value.toJson(),
            'saved_categories': categories,
          });
          migrated = true;
        }
      }
    }
    // Upgrades are backup-first and idempotent. A failed/interrupted backup or
    // replacement leaves the original or its exact backup available on restart.
    if (migrated && !_savedWritesBlocked && original != null) {
      _pendingSavedBackup = original;
      try {
        await _writeSaved(saved);
      } catch (_) {
        storageMessage = '收藏分类升级未保存，原有内容已保留；请检查存储空间';
      }
    }
    final read = migrateRead(catalog, _readList('read-v1').toSet());
    final hidden = {
      for (final id in _readList('hidden-v1')) catalog.sourceAliases[id] ?? id,
    };
    final fontScale = (_read<double>('font-scale') ?? 1).clamp(1.0, 1.4);
    final showImages = _read<bool>('show-images') ?? true;
    if (_unreadableKeys.isNotEmpty) {
      storageMessage = '部分本机记录读取失败，已停止覆盖这些记录；请重试读取';
    }
    return LibraryState(
      catalog: catalog,
      saved: saved,
      read: read,
      hidden: hidden,
      fontScale: fontScale,
      showImages: showImages,
      message: message,
      storageMessage: storageMessage,
      storageReadFailed: _unreadableKeys.isNotEmpty,
      savedRecoveryRequired: _savedWritesBlocked,
      savedRecoveryCanRestore: _savedOriginal != null,
    );
  }

  Set<String> migrateRead(Catalog catalog, Set<String> read) => {
    ...read,
    for (final article in catalog.articles)
      if (article.legacyIds.any(read.contains)) article.id,
  };

  static const _catalogSaveFailure = '目录缓存保存失败，本次同步内容仅在本次会话有效';

  Future<void> refresh() async {
    final current = state.asData?.value;
    if (current == null || current.syncing) return;
    state = AsyncData(current.copyWith(syncing: true, message: '正在同步…'));
    try {
      final catalog = await ref.read(repositoryProvider).fetch();
      String? storageMessage;
      try {
        if (!identical(catalog, _persistedCatalog)) {
          await _write('catalog-v1', await compute(encodeCatalog, catalog));
          _persistedCatalog = catalog;
        }
        if (ref.mounted &&
            state.requireValue.storageMessage == _catalogSaveFailure) {
          storageMessage = '';
        }
      } catch (_) {
        storageMessage = _catalogSaveFailure;
      }
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(
            catalog: catalog,
            hidden: {
              for (final id in state.requireValue.hidden)
                catalog.sourceAliases[id] ?? id,
            },
            read: migrateRead(catalog, state.requireValue.read),
            syncing: false,
            message: identical(catalog, current.catalog)
                ? '已检查，目录未变化'
                : '目录已更新',
            lastCheckedAt: DateTime.now(),
            storageMessage: storageMessage,
          ),
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(syncing: false, message: '同步失败，继续使用本机缓存'),
        );
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    return _writes = _writes.then((_) => operation()).catchError((
      Object error,
    ) {
      if (ref.mounted && state.hasValue) {
        state = AsyncData(
          state.requireValue.copyWith(
            storageMessage: '本机保存失败，改动仅在本次会话有效；请检查设备存储空间',
            recoveringSaved: false,
          ),
        );
      }
    });
  }

  void saveMutation(LibraryState next) {
    final previous = state.requireValue;
    final savedChanged = !mapEquals(previous.saved, next.saved);
    final changes = <String, Object>{
      if (!setEquals(previous.read, next.read)) 'read-v1': next.read.toList(),
      if (!setEquals(previous.hidden, next.hidden))
        'hidden-v1': next.hidden.toList(),
      if (previous.fontScale != next.fontScale) 'font-scale': next.fontScale,
      if (previous.showImages != next.showImages)
        'show-images': next.showImages,
    };
    state = AsyncData(next);
    if (!savedChanged && changes.isEmpty) return;
    _enqueue(() async {
      var failed = false;
      if (savedChanged) {
        try {
          await _writeSaved(next.saved);
        } catch (_) {
          failed = true;
        }
      }
      for (final entry in changes.entries) {
        if (!_unreadableKeys.contains(entry.key)) {
          try {
            await _write(entry.key, entry.value);
          } catch (_) {
            failed = true;
          }
        }
      }
      if (failed) throw const LibraryStorageException('mutation');
    });
  }

  /// Called only after the user explicitly accepts recovery in the UI.
  Future<void> recoverSaved() async {
    final original = _savedOriginal;
    if (original == null ||
        !_savedWritesBlocked ||
        state.requireValue.recoveringSaved) {
      return;
    }
    state = AsyncData(state.requireValue.copyWith(recoveringSaved: true));
    await _enqueue(() async {
      await _backupSaved(original);
      // Keep the guard set until the replacement has actually been accepted.
      await _write(
        'saved-v2',
        await compute(encodeSavedDocument, state.requireValue.saved),
      );
      _savedWritesBlocked = false;
      _savedOriginal = null;
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(
            savedRecoveryRequired: false,
            savedRecoveryCanRestore: false,
            recoveringSaved: false,
            storageMessage: '已恢复可读收藏，损坏的原始记录已单独备份在本机',
          ),
        );
      }
    });
  }

  void toggleSaved(Article article) {
    final current = state.requireValue, saved = {...state.requireValue.saved};
    saved.containsKey(article.id)
        ? saved.remove(article.id)
        : saved[article.id] = Article.fromJson({
            ...article.toJson(),
            'saved_categories': current
                .categoriesFor(article)
                .where((category) => category.isNotEmpty)
                .toSet()
                .toList(),
          });
    saveMutation(current.copyWith(saved: saved));
  }

  void restoreSaved(Article article) {
    final current = state.requireValue;
    if (current.saved.containsKey(article.id)) return;
    saveMutation(
      current.copyWith(saved: {...current.saved, article.id: article}),
    );
  }

  void markRead(String id) => saveMutation(
    state.requireValue.copyWith(read: {...state.requireValue.read, id}),
  );
  void markUnread(String id) {
    final current = state.requireValue;
    final aliases = [...current.catalog.articles, ...current.saved.values]
        .where((article) => article.id == id)
        .expand((article) => article.legacyIds);
    saveMutation(
      current.copyWith(read: {...current.read}..removeAll([id, ...aliases])),
    );
  }

  Set<String> markManyRead(Iterable<String> ids) {
    final changed = ids.toSet().difference(state.requireValue.read);
    if (changed.isNotEmpty) {
      saveMutation(
        state.requireValue.copyWith(
          read: {...state.requireValue.read, ...changed},
        ),
      );
    }
    return changed;
  }

  void markManyUnread(Set<String> ids) => saveMutation(
    state.requireValue.copyWith(read: state.requireValue.read.difference(ids)),
  );
  void follow(String id, bool enabled) => saveMutation(
    state.requireValue.copyWith(
      hidden: {...state.requireValue.hidden}
        ..remove(id)
        ..addAll(enabled ? <String>[] : [id]),
    ),
  );
  void setFontScale(double value) =>
      saveMutation(state.requireValue.copyWith(fontScale: value));
  void setImages(bool value) =>
      saveMutation(state.requireValue.copyWith(showImages: value));
}
