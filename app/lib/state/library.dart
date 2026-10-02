import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';

final repositoryProvider = Provider<CatalogRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return CatalogRepository(client);
});
final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class LibraryState {
  LibraryState({
    required this.catalog,
    Map<String, Article> saved = const {},
    Set<String> read = const {},
    Set<String> hidden = const {},
    this.syncing = false,
    this.message = '',
    this.fontScale = 1,
    this.showImages = true,
  }) : saved = Map.unmodifiable(saved),
       read = Set.unmodifiable(read),
       hidden = Set.unmodifiable(hidden);
  final Catalog catalog;
  final Map<String, Article> saved;
  final Set<String> read, hidden;
  final bool syncing, showImages;
  final String message;
  final double fontScale;
  LibraryState copyWith({
    Catalog? catalog,
    Map<String, Article>? saved,
    Set<String>? read,
    Set<String>? hidden,
    bool? syncing,
    String? message,
    double? fontScale,
    bool? showImages,
  }) => LibraryState(
    catalog: catalog ?? this.catalog,
    saved: saved ?? this.saved,
    read: read ?? this.read,
    hidden: hidden ?? this.hidden,
    syncing: syncing ?? this.syncing,
    message: message ?? this.message,
    fontScale: fontScale ?? this.fontScale,
    showImages: showImages ?? this.showImages,
  );
  List<Article> visible({
    String query = '',
    bool savedOnly = false,
    bool unreadOnly = false,
    String source = '',
  }) {
    final needle = query.trim().toLowerCase();
    return (savedOnly ? saved.values : catalog.articles)
        .where(
          (article) =>
              (savedOnly ||
                  article.sources.any(
                    (id) =>
                        !hidden.contains(id) &&
                        catalog.feeds.any(
                          (feed) => feed.id == id && feed.enabled,
                        ),
                  )) &&
              (!unreadOnly || !read.contains(article.id)) &&
              (source.isEmpty || article.sources.contains(source)) &&
              (needle.isEmpty ||
                  '${article.title} ${article.sourceTitle} ${article.summary}'
                      .toLowerCase()
                      .contains(needle)),
        )
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }
}

class LibraryController extends AsyncNotifier<LibraryState> {
  late SharedPreferences _preferences;
  Future<void> _writes = Future.value();
  @override
  Future<LibraryState> build() async {
    _preferences = await SharedPreferences.getInstance();
    Catalog? cached;
    try {
      final value = _preferences.getString('catalog-v1');
      if (value != null) {
        cached = Catalog.fromJson(jsonDecode(value) as Map<String, dynamic>);
      }
    } catch (_) {
      /* Corrupt caches can be replaced by a fresh download. */
    }
    final saved = <String, Article>{};
    try {
      for (final value in jsonDecode(
        _preferences.getString('saved-v1') ?? '[]',
      ) as List<dynamic>) {
        try {
          final article = Article.fromJson(value as Map<String, dynamic>);
          saved[article.id] = article;
        } catch (_) {
          /* Preserve other bookmarks. */
        }
      }
    } catch (_) {
      /* Bad bookmark documents must not prevent startup. */
    }
    String message = '';
    Catalog catalog;
    if (cached != null) {
      catalog = cached;
      message = '显示本机缓存，可下拉刷新';
    } else {
      try {
        catalog = await ref.read(repositoryProvider).fetch();
        await _preferences.setString(
          'catalog-v1',
          jsonEncode(catalog.toJson()),
        );
      } catch (_) {
        if (saved.isEmpty) rethrow;
        catalog = Catalog(
          generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          feeds: [],
          articles: [],
        );
        message = '暂时无法同步，你的收藏仍可阅读';
      }
    }
    return LibraryState(
      catalog: catalog,
      saved: saved,
      read: migrateRead(
        catalog,
        (_preferences.getStringList('read-v1') ?? []).toSet(),
      ),
      hidden: (_preferences.getStringList('hidden-v1') ?? []).toSet(),
      fontScale: (_preferences.getDouble('font-scale') ?? 1).clamp(1, 1.4),
      showImages: _preferences.getBool('show-images') ?? true,
      message: message,
    );
  }

  Set<String> migrateRead(Catalog catalog, Set<String> read) => {
    ...read,
    for (final article in catalog.articles)
      if (article.legacyIds.any(read.contains)) article.id,
  };

  Future<void> refresh() async {
    final current = state.asData?.value;
    if (current == null || current.syncing) return;
    state = AsyncData(current.copyWith(syncing: true, message: '正在同步…'));
    try {
      final catalog = await ref.read(repositoryProvider).fetch();
      await _preferences.setString('catalog-v1', jsonEncode(catalog.toJson()));
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(
            catalog: catalog,
            read: migrateRead(catalog, state.requireValue.read),
            syncing: false,
            message: '已同步最新文章',
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

  void saveMutation(LibraryState next) {
    state = AsyncData(next);
    _writes = _writes
        .then((_) async {
          await _preferences.setString(
            'saved-v1',
            jsonEncode(
              next.saved.values.map((article) => article.toJson()).toList(),
            ),
          );
          await _preferences.setStringList('read-v1', next.read.toList());
          await _preferences.setStringList('hidden-v1', next.hidden.toList());
          await _preferences.setDouble('font-scale', next.fontScale);
          await _preferences.setBool('show-images', next.showImages);
        })
        .catchError((Object error) {
          if (ref.mounted && state.hasValue) {
            state = AsyncData(
              state.requireValue.copyWith(message: '本机保存失败，请检查设备存储空间'),
            );
          }
        });
  }

  void toggleSaved(Article article) {
    final current = state.requireValue, saved = {...state.requireValue.saved};
    saved.containsKey(article.id)
        ? saved.remove(article.id)
        : saved[article.id] = article;
    saveMutation(current.copyWith(saved: saved));
  }

  void markRead(String id) => saveMutation(
    state.requireValue.copyWith(read: {...state.requireValue.read, id}),
  );
  void markUnread(String id) => saveMutation(
    state.requireValue.copyWith(read: {...state.requireValue.read}..remove(id)),
  );
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
