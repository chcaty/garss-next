import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garss_app/data/catalog_cache.dart';
import 'package:garss_app/data/models.dart';

import 'support/snapshot_fixture.dart';

class RejectingPreferences implements SharedPreferences {
  RejectingPreferences(this.delegate, this.rejectedKey);
  final SharedPreferences delegate;
  final String rejectedKey;
  @override
  Object? get(String key) => delegate.get(key);
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  Future<bool> setString(String key, String value) async =>
      key == rejectedKey ? false : delegate.setString(key, value);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<void> reload() => delegate.reload();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy cache stays usable but cannot claim a verified app identity',
    () async {
      final catalog = await snapshotRepository(snapshotDocuments()).fetch();
      SharedPreferences.setMockInitialValues({
        'catalog-v1': jsonEncode(catalog.toJson()),
      });
      final preferences = await SharedPreferences.getInstance();
      final cache = CatalogCache(preferences);
      expect(cache.load()!.snapshotId, isNull);
      expect(cache.load()!.articles.single.id, 'a');
      expect(preferences.containsKey('catalog-v1'), isTrue);
      await cache.save(catalog);
      expect(preferences.containsKey('catalog-v1'), isFalse);
      final restored = CatalogCache(preferences).load()!;
      expect(restored.snapshotId, 'one');
      expect(restored.retentionDays, 5);
      expect(restored.timezone, 'Asia/Shanghai');
      final requests = <String>[];
      expect(
        await snapshotRepository(
          snapshotDocuments(),
          requests: requests,
        ).fetch(cached: restored),
        same(restored),
      );
      expect(requests, [appMetaPath]);
    },
  );

  test('corrupt active slot restores the previous complete snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final cache = CatalogCache(preferences);
    final first = await snapshotRepository(snapshotDocuments()).fetch();
    await cache.save(first);
    final second = Catalog.fromJson({...first.toJson(), 'snapshot_id': 'two'});
    await cache.save(second);
    final active = preferences.getString(CatalogCache.activeKey)!;
    final key = '${CatalogCache.slotPrefix}$active';
    final envelope =
        jsonDecode(preferences.getString(key)!) as Map<String, dynamic>;
    envelope['payload'] = (envelope['payload'] as String).replaceFirst(
      'Article',
      'Changed',
    );
    await preferences.setString(key, jsonEncode(envelope));
    final restored = CatalogCache(preferences).load()!;
    expect(restored.snapshotId, 'one');
    expect(restored.articles.single.title, 'Article');
  });

  test(
    'interrupted staged write does not replace the committed slot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final cache = CatalogCache(preferences);
      final first = await snapshotRepository(snapshotDocuments()).fetch();
      await cache.save(first);
      final committed = preferences.getString(CatalogCache.activeKey)!;
      final next = committed == 'a' ? 'b' : 'a';
      // A terminated app can leave an incomplete inactive slot, but not a pointer.
      await preferences.setString(
        '${CatalogCache.slotPrefix}$next',
        '{partial',
      );
      expect(CatalogCache(preferences).load()!.snapshotId, first.snapshotId);
    },
  );

  test(
    'invalid cache checksum and byte length force a fresh download',
    () async {
      final catalog = await snapshotRepository(snapshotDocuments()).fetch();
      for (final field in ['sha256', 'bytes']) {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        await CatalogCache(preferences).save(catalog);
        final slot = preferences.getString(CatalogCache.activeKey)!;
        final key = '${CatalogCache.slotPrefix}$slot';
        final envelope =
            jsonDecode(preferences.getString(key)!) as Map<String, dynamic>;
        envelope[field] = field == 'bytes' ? 0 : 'broken';
        await preferences.setString(key, jsonEncode(envelope));
        final cached = CatalogCache(preferences).load();
        expect(cached, isNull);
        final requests = <String>[];
        await snapshotRepository(
          snapshotDocuments(),
          requests: requests,
        ).fetch(cached: cached);
        expect(requests, hasLength(4));
      }
    },
  );

  test('failed staging or commit keeps the previous cache readable', () async {
    final first = await snapshotRepository(snapshotDocuments()).fetch();
    final second = Catalog.fromJson({...first.toJson(), 'snapshot_id': 'two'});
    for (final rejected in [
      '${CatalogCache.slotPrefix}b',
      CatalogCache.activeKey,
    ]) {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await CatalogCache(preferences).save(first);
      final cache = CatalogCache(RejectingPreferences(preferences, rejected));
      expect(cache.load()!.snapshotId, 'one');
      await expectLater(cache.save(second), throwsStateError);
      expect(CatalogCache(preferences).load()!.snapshotId, 'one');
      expect(preferences.getString(CatalogCache.activeKey), 'a');
    }
  });

  test('an uncommitted first slot is ignored after restart', () async {
    SharedPreferences.setMockInitialValues({
      '${CatalogCache.slotPrefix}a': '{partial',
    });
    expect(CatalogCache(await SharedPreferences.getInstance()).load(), isNull);
  });
}
