import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/data/library_storage.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/repository.dart';
import 'package:garss_app/state/library.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeLibraryStorage implements LibraryStorage {
  FakeLibraryStorage([Map<String, Object>? initial]) : values = {...?initial};
  final Map<String, Object> values;
  final List<String> writes = [];
  final Set<String> failReads = {};
  String? rejectPrefix, throwPrefix;

  @override
  Object? read(String key) {
    if (failReads.contains(key)) throw StateError('Read failed');
    return values[key];
  }

  @override
  Future<bool> write(String key, Object value) async {
    writes.add(key);
    if (throwPrefix != null && key.startsWith(throwPrefix!)) {
      throw StateError('Write failed');
    }
    if (rejectPrefix != null && key.startsWith(rejectPrefix!)) return false;
    values[key] = value;
    return true;
  }
}

final savedArticle = Article(
  id: 'saved',
  sourceId: 'source',
  title: '保留的收藏',
  url: 'https://example.com/saved',
  publishedAt: DateTime.utc(2026, 10, 1),
);
final cachedCatalog = Catalog(
  generatedAt: savedArticle.publishedAt,
  feeds: const [
    Feed(
      id: 'source',
      title: '来源',
      url: 'https://example.com/rss',
      category: '技术',
    ),
  ],
  articles: [savedArticle],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer open(FakeLibraryStorage storage) {
    final container = ProviderContainer(
      overrides: [
        libraryStorageProvider.overrideWith((ref) async => storage),
        repositoryProvider.overrideWithValue(
          CatalogRepository(
            MockClient((request) async => http.Response('offline', 503)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  FakeLibraryStorage stored(String raw) => FakeLibraryStorage({
    'catalog-v1': jsonEncode(cachedCatalog.toJson()),
    'saved-v2': raw,
  });

  for (final raw in ['{broken', '{"wrong":"shape"}', 'null']) {
    test(
      'malformed whole document is preserved across startup and mutations: $raw',
      () async {
        final storage = stored(raw);
        final container = open(storage);
        final state = await container.read(libraryProvider.future);
        expect(state.savedRecoveryRequired, isTrue);
        expect(state.savedRecoveryCanRestore, isTrue);
        final controller = container.read(libraryProvider.notifier);
        controller.markRead('saved');
        controller.toggleSaved(savedArticle);
        controller.follow('source', false);
        await controller.pendingWrites;
        await controller.refresh();
        expect(storage.values['saved-v2'], raw);
        expect(storage.writes, isNot(contains('saved-v2')));
        expect(
          container.read(libraryProvider).requireValue.savedRecoveryRequired,
          isTrue,
        );
      },
    );
  }

  for (final malformed in [
    {'id': 'bad'},
    {
      ...savedArticle.toJson(),
      'id': 'bad',
      'source_ids': [42],
    },
    {
      ...savedArticle.toJson(),
      'id': 'bad',
      'saved_categories': [false],
    },
    savedArticle
        .toJson(), // Duplicate identity must not silently overwrite data.
  ]) {
    test(
      'one invalid record retains readable records and exact original: $malformed',
      () async {
        final raw = jsonEncode([savedArticle.toJson(), malformed]);
        final storage = stored(raw);
        final container = open(storage);
        final state = await container.read(libraryProvider.future);
        expect(state.saved.keys, ['saved']);
        expect(state.savedRecoveryRequired, isTrue);
        expect(storage.values['saved-v2'], raw);
        expect(storage.writes, isEmpty);
      },
    );
  }

  test(
    'explicit recovery backs up exact original before replacing readable data',
    () async {
      final raw = jsonEncode([
        savedArticle.toJson(),
        {'bad': true},
      ]);
      final storage = stored(raw);
      final container = open(storage);
      await container.read(libraryProvider.future);
      final controller = container.read(libraryProvider.notifier);
      await controller.recoverSaved();
      expect(storage.writes.first, startsWith('saved-v2-quarantine-'));
      expect(storage.values[storage.writes.first], raw);
      expect(storage.writes.last, 'saved-v2');
      expect(
        container.read(libraryProvider).requireValue.savedRecoveryRequired,
        isFalse,
      );
      final restarted = open(storage);
      final state = await restarted.read(libraryProvider.future);
      expect(state.saved.keys, ['saved']);
      expect(state.savedRecoveryRequired, isFalse);
    },
  );

  for (final throws in [false, true]) {
    test(
      'failed quarantine ($throws) never replaces original or clears protection',
      () async {
        const raw = 'broken';
        final storage = stored(raw);
        if (throws) {
          storage.throwPrefix = 'saved-v2-quarantine-';
        } else {
          storage.rejectPrefix = 'saved-v2-quarantine-';
        }
        final container = open(storage);
        await container.read(libraryProvider.future);
        await container.read(libraryProvider.notifier).recoverSaved();
        final state = container.read(libraryProvider).requireValue;
        expect(storage.values['saved-v2'], raw);
        expect(storage.writes, isNot(contains('saved-v2')));
        expect(state.savedRecoveryRequired, isTrue);
        expect(state.recoveringSaved, isFalse);
        expect(state.storageMessage, contains('保存失败'));
      },
    );
  }

  test('recovery interrupted after backup keeps original and can retry after restart', () async {
    const raw = 'broken';
    final storage = stored(raw)..rejectPrefix = 'saved-v2';
    // Allow backup while refusing the replacement itself.
    final wrapper = _RejectReplacement(storage);
    final container = ProviderContainer(
      overrides: [libraryStorageProvider.overrideWith((ref) async => wrapper)],
    );
    addTearDown(container.dispose);
    storage.rejectPrefix = null;
    await container.read(libraryProvider.future);
    await container.read(libraryProvider.notifier).recoverSaved();
    expect(storage.values['saved-v2'], raw);
    final backups = storage.values.keys
        .where((key) => key.startsWith('saved-v2-quarantine-'))
        .toList();
    expect(backups, hasLength(1));
    expect(storage.values[backups.single], raw);
    expect(
      container.read(libraryProvider).requireValue.savedRecoveryRequired,
      isTrue,
    );
    final restarted = open(storage);
    await restarted.read(libraryProvider.future);
    await restarted.read(libraryProvider.notifier).recoverSaved();
    expect(storage.values[backups.single], raw);
    expect(
      storage.values.keys.where(
        (key) => key.startsWith('saved-v2-quarantine-'),
      ),
      hasLength(2),
    );
    expect(storage.values['saved-v2'], '[]');
  });

  test(
    'bookmark read failure cannot masquerade as an empty writable library',
    () async {
      final raw = jsonEncode([savedArticle.toJson()]);
      final storage = stored(raw)..failReads.add('saved-v2');
      final container = open(storage);
      final state = await container.read(libraryProvider.future);
      expect(state.savedRecoveryRequired, isTrue);
      expect(state.savedRecoveryCanRestore, isFalse);
      expect(state.storageMessage, contains('读取失败'));
      final controller = container.read(libraryProvider.notifier);
      controller.toggleSaved(savedArticle);
      await controller.pendingWrites;
      await controller.recoverSaved();
      expect(storage.values['saved-v2'], raw);
      expect(storage.writes, isNot(contains('saved-v2')));
    },
  );

  test(
    'wrong stored root type is protected rather than treated as empty',
    () async {
      final storage = stored('[]');
      storage.values['saved-v2'] = 42;
      final container = open(storage);
      final state = await container.read(libraryProvider.future);
      expect(state.savedRecoveryRequired, isTrue);
      expect(state.savedRecoveryCanRestore, isFalse);
      final controller = container.read(libraryProvider.notifier);
      controller.toggleSaved(savedArticle);
      await controller.pendingWrites;
      expect(storage.values['saved-v2'], 42);
      expect(storage.writes, isNot(contains('saved-v2')));
    },
  );

  test(
    'other unreadable preferences are not overwritten by unrelated mutations',
    () async {
      final storage = stored('[]');
      storage.values['read-v1'] = ['keep'];
      storage.failReads.add('read-v1');
      final container = open(storage);
      final state = await container.read(libraryProvider.future);
      expect(state.storageMessage, contains('读取失败'));
      final controller = container.read(libraryProvider.notifier);
      controller.follow('source', false);
      await controller.pendingWrites;
      expect(storage.values['read-v1'], ['keep']);
      expect(storage.writes, isNot(contains('read-v1')));
    },
  );

  test(
    'valid category migration is backup-first and idempotent on restart',
    () async {
      final raw = jsonEncode([savedArticle.toJson()]);
      final storage = stored(raw);
      final container = open(storage);
      final state = await container.read(libraryProvider.future);
      expect(state.saved['saved']!.savedCategories, ['技术']);
      expect(storage.writes.first, startsWith('saved-v2-quarantine-'));
      expect(storage.values[storage.writes.first], raw);
      expect(storage.writes.last, 'saved-v2');
      storage.writes.clear();
      await open(storage).read(libraryProvider.future);
      expect(storage.writes, isEmpty);
    },
  );

  test('migration interruption before backup preserves original and resumes on restart', () async {
    final raw = jsonEncode([savedArticle.toJson()]);
    final storage = stored(raw)..rejectPrefix = 'saved-v2-quarantine-';
    final state = await open(storage).read(libraryProvider.future);
    expect(state.storageMessage, contains('升级未保存'));
    expect(storage.values['saved-v2'], raw);
    expect(storage.writes, isNot(contains('saved-v2')));
    storage.rejectPrefix = null;
    final restarted = await open(storage).read(libraryProvider.future);
    expect(restarted.saved['saved']!.savedCategories, ['技术']);
    expect(
      (jsonDecode(
        storage.values['saved-v2'] as String,
      ) as List).single['saved_categories'],
      ['技术'],
    );
  });

  test('migration interruption after backup retains recoverable original and retries', () async {
    final raw = jsonEncode([savedArticle.toJson()]);
    final storage = stored(raw);
    final container = ProviderContainer(
      overrides: [
        libraryStorageProvider.overrideWith(
          (ref) async => _RejectReplacement(storage),
        ),
      ],
    );
    addTearDown(container.dispose);
    final state = await container.read(libraryProvider.future);
    expect(state.storageMessage, contains('升级未保存'));
    expect(storage.values['saved-v2'], raw);
    expect(storage.values[storage.writes.first], raw);
    final restarted = await open(storage).read(libraryProvider.future);
    expect(restarted.saved['saved']!.savedCategories, ['技术']);
    expect(
      (jsonDecode(
        storage.values['saved-v2'] as String,
      ) as List).single['saved_categories'],
      ['技术'],
    );
  });

  test('one rejected changed field does not prevent another changed field persisting', () async {
    final storage = stored('[]')..rejectPrefix = 'read-v1';
    final container = open(storage);
    final state = await container.read(libraryProvider.future);
    final controller = container.read(libraryProvider.notifier);
    controller.saveMutation(
      state.copyWith(read: {'saved'}, hidden: {'source'}),
    );
    await controller.pendingWrites;
    expect(storage.values['hidden-v1'], ['source']);
    expect(
      container.read(libraryProvider).requireValue.storageMessage,
      contains('保存失败'),
    );
  });

  for (final key in [
    'saved-v2',
    'read-v1',
    'hidden-v1',
    'font-scale',
    'show-images',
  ]) {
    for (final throws in [false, true]) {
      test(
        'preference write $key failure ($throws) is visible and queue remains usable',
        () async {
          final storage = stored('[]');
          final container = open(storage);
          await container.read(libraryProvider.future);
          if (throws) {
            storage.throwPrefix = key;
          } else {
            storage.rejectPrefix = key;
          }
          final controller = container.read(libraryProvider.notifier);
          switch (key) {
            case 'saved-v2':
              controller.toggleSaved(savedArticle);
            case 'read-v1':
              controller.markRead('first');
            case 'hidden-v1':
              controller.follow('source', false);
            case 'font-scale':
              controller.setFontScale(1.2);
            case 'show-images':
              controller.setImages(false);
          }
          await controller.pendingWrites;
          expect(
            container.read(libraryProvider).requireValue.storageMessage,
            contains('保存失败'),
          );
          storage.throwPrefix = storage.rejectPrefix = null;
          controller.markRead('saved');
          await controller.pendingWrites;
          expect(storage.values['read-v1'], contains('saved'));
        },
      );
    }
  }

  test(
    'read-only changes never rewrite bookmarks or depend on their storage',
    () async {
      final original = jsonEncode([
        {
          ...savedArticle.toJson(),
          'saved_categories': ['技术'],
        },
      ]);
      final storage = stored(original)..rejectPrefix = 'saved-v2';
      final container = open(storage);
      await container.read(libraryProvider.future);
      final controller = container.read(libraryProvider.notifier);
      controller.markRead('saved');
      await controller.pendingWrites;
      expect(storage.writes, ['read-v1']);
      expect(storage.values['saved-v2'], original);
      expect(
        (await open(storage).read(libraryProvider.future)).read,
        contains('saved'),
      );
    },
  );

  test('unchanged refresh skips cache writes but retries an earlier rejected cache write', () async {
    final storage = stored('[]');
    final fresh = Catalog(
      generatedAt: cachedCatalog.generatedAt.add(const Duration(hours: 1)),
      feeds: cachedCatalog.feeds,
      articles: cachedCatalog.articles,
    );
    final container = ProviderContainer(
      overrides: [
        libraryStorageProvider.overrideWith((ref) async => storage),
        repositoryProvider.overrideWithValue(_FixedRepository(fresh)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);
    final controller = container.read(libraryProvider.notifier);
    storage.rejectPrefix = 'catalog-v1';
    await controller.refresh();
    expect(
      container.read(libraryProvider).requireValue.storageMessage,
      contains('目录缓存保存失败'),
    );
    storage.rejectPrefix = null;
    await controller.refresh();
    expect(storage.writes.where((key) => key == 'catalog-v1'), hasLength(2));
    await controller.refresh();
    expect(storage.writes.where((key) => key == 'catalog-v1'), hasLength(2));
    final state = container.read(libraryProvider).requireValue;
    expect(state.storageMessage, isEmpty);
    expect(state.message, '已检查，目录未变化');
    expect(state.lastCheckedAt, isNotNull);
  });

  test('queued background bookmark serialization preserves the latest ordered mutation', () async {
    final storage = stored('[]');
    final container = open(storage);
    await container.read(libraryProvider.future);
    final controller = container.read(libraryProvider.notifier);
    controller.toggleSaved(savedArticle);
    controller.toggleSaved(savedArticle);
    controller.toggleSaved(
      Article.fromJson({...savedArticle.toJson(), 'summary': 'latest'}),
    );
    await controller.pendingWrites;
    final raw = jsonDecode(storage.values['saved-v2'] as String) as List;
    expect(raw, hasLength(1));
    expect(raw.single['summary'], 'latest');
    expect(storage.writes, ['saved-v2', 'saved-v2', 'saved-v2']);
  });

  test(
    'corrupt bookmarks expose recovery even without cache or connectivity',
    () async {
      final storage = FakeLibraryStorage({'saved-v2': 'broken'});
      final state = await open(storage).read(libraryProvider.future);
      expect(state.catalog.articles, isEmpty);
      expect(state.savedRecoveryRequired, isTrue);
      expect(storage.values['saved-v2'], 'broken');
    },
  );
}

class _RejectReplacement implements LibraryStorage {
  _RejectReplacement(this.storage);
  final FakeLibraryStorage storage;
  @override
  Object? read(String key) => storage.read(key);
  @override
  Future<bool> write(String key, Object value) async =>
      key == 'saved-v2' ? false : storage.write(key, value);
}

class _FixedRepository extends CatalogRepository {
  _FixedRepository(this.catalog)
    : super(MockClient((request) async => http.Response('unused', 500)));
  final Catalog catalog;
  @override
  Future<Catalog> fetch() async => catalog;
}
