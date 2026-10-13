import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';

const compiled = await build({entryPoints: ['web/src/reading-storage.ts'], bundle: true, write: false, format: 'esm', platform: 'node'});
const {ReadingStorage, LEGACY_READING_KEY, READING_STORAGE_PREFIX} = await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);

class SharedStorage {
  records = new Map();
  beforeWrite;
  failKey;
  get length() { return this.records.size; }
  key(index) { return [...this.records.keys()][index] ?? null; }
  getItem(key) { return this.records.get(key) ?? null; }
  setItem(key, value) {
    const hook = this.beforeWrite;
    this.beforeWrite = undefined;
    hook?.(key, value);
    if (key === this.failKey) throw Error('Storage write rejected');
    this.records.set(key, value);
  }
}

const old = {id: 'old', source_id: 'source', title: 'Old saved article', url: 'https://example.test/old', published_at: '2026-10-12T00:00:00Z', saved_sources: []};
const canonical = {...old, id: 'new', legacy_ids: ['old'], title: 'Canonical article'};
function seeded(field) {
  const port = new SharedStorage();
  port.setItem(LEGACY_READING_KEY, JSON.stringify({version: 2, read: field === 'read' ? ['old'] : [], saved: field === 'saved' ? ['old'] : [], bookmarks: field === 'saved' ? [old] : []}));
  return port;
}
function remove(storage, field) {
  if (field === 'read') storage.library.markUnread(old);
  else storage.library.toggleSaved(old, []);
  assert.equal(storage.persist(), true);
}
function assertRemoved(port, field) {
  const restarted = new ReadingStorage(port);
  assert.equal(restarted.status.kind, 'ready');
  assert.deepEqual([...restarted.library[field]], []);
  if (field === 'saved') assert.equal(restarted.library.bookmarks.size, 0);
}

for (const field of ['read', 'saved']) {
  for (const [migratorId, removerId] of [['a', 'z'], ['z', 'a']]) {
    test(`${field}: same-clock alias migration cannot defeat removal (${migratorId}/${removerId})`, () => {
      const port = seeded(field);
      const migrator = new ReadingStorage(port, () => migratorId);
      const remover = new ReadingStorage(port, () => removerId);
      port.beforeWrite = () => remove(remover, field);
      assert.equal(migrator.reconcile([canonical], []), true);
      assertRemoved(port, field);
    });
  }

  test(`${field}: stale alias removal follows an already committed canonical migration`, () => {
    const port = seeded(field);
    const migrator = new ReadingStorage(port, () => 'migration');
    const remover = new ReadingStorage(port, () => 'removal');
    assert.equal(migrator.reconcile([canonical], []), true);
    remove(remover, field);
    assertRemoved(port, field);
  });

  test(`${field}: stale reconciliation cannot undo an already committed removal`, () => {
    const port = seeded(field);
    const migrator = new ReadingStorage(port, () => 'migration');
    const remover = new ReadingStorage(port, () => 'removal');
    migrator.library.reconcile([canonical], []);
    remove(remover, field);
    assert.equal(migrator.persist([canonical]), true);
    assertRemoved(port, field);
  });
}

test('concurrent disjoint first operations preserve both and retain exact legacy bytes', () => {
  const port = seeded('read');
  const original = port.getItem(LEGACY_READING_KEY);
  const first = new ReadingStorage(port, () => 'a');
  const second = new ReadingStorage(port, () => 'z');
  first.library.read.add('one');
  second.library.read.add('two');
  port.beforeWrite = () => assert.equal(second.persist(), true);
  assert.equal(first.persist(), true);
  assert.deepEqual([...new ReadingStorage(port).library.read].sort(), ['old', 'one', 'two']);
  assert.equal(port.getItem(LEGACY_READING_KEY), original);
});

test('an older page rewriting legacy state after migration blocks writes without overwriting either version', () => {
  const port = seeded('read');
  const original = port.getItem(LEGACY_READING_KEY);
  const storage = new ReadingStorage(port, () => 'one');
  storage.library.read.add('new-read');
  assert.equal(storage.persist(), true);
  const later = JSON.stringify({version: 2, read: ['changed-in-old-page'], saved: [], bookmarks: []});
  port.setItem(LEGACY_READING_KEY, later);
  assert.equal(storage.refresh(), false);
  assert.equal(storage.status.kind, 'recovery');
  const recordCount = port.length;
  storage.library.read.add('must-not-save');
  assert.equal(storage.persist(), false);
  assert.equal(port.length, recordCount);
  assert.equal(port.getItem(LEGACY_READING_KEY), later);
  assert.equal(JSON.parse(port.getItem(`${READING_STORAGE_PREFIX}op:one`)).base.legacy, original);
});

test('recovery interrupted after verified backup remains blocked across restart', () => {
  const port = new SharedStorage();
  const original = '{ unparseable, but valuable original bytes';
  port.setItem(LEGACY_READING_KEY, original);
  port.failKey = `${READING_STORAGE_PREFIX}recovery:first`;
  const storage = new ReadingStorage(port, () => 'first');
  assert.equal(storage.recover(), false);
  const backup = port.getItem(`${READING_STORAGE_PREFIX}quarantine:first`);
  assert.equal(JSON.parse(backup).records[0].raw, original);
  assert.equal(port.getItem(LEGACY_READING_KEY), original);
  const restarted = new ReadingStorage(port, () => 'second');
  assert.equal(restarted.status.kind, 'recovery');
  port.failKey = undefined;
  assert.equal(restarted.recover(), true);
  assert.equal(port.getItem(`${READING_STORAGE_PREFIX}quarantine:first`), backup);
  assert.equal(port.getItem(LEGACY_READING_KEY), original);
});

test('a newly damaged recovery receipt is itself quarantined without replacing an earlier backup', () => {
  const port = new SharedStorage();
  port.setItem(LEGACY_READING_KEY, '{bad');
  const storage = new ReadingStorage(port, () => 'first');
  assert.equal(storage.recover(), true);
  const backup = port.getItem(`${READING_STORAGE_PREFIX}quarantine:first`);
  const receiptKey = `${READING_STORAGE_PREFIX}recovery:first`;
  port.setItem(receiptKey, '{damaged receipt');
  const restarted = new ReadingStorage(port, () => 'second');
  assert.equal(restarted.status.kind, 'recovery');
  assert.equal(restarted.recover(), true);
  assert.equal(port.getItem(`${READING_STORAGE_PREFIX}quarantine:first`), backup);
  const recovered = JSON.parse(port.getItem(`${READING_STORAGE_PREFIX}quarantine:second`));
  assert.ok(recovered.records.some(record => record.key === receiptKey && record.raw === '{damaged receipt'));
});
