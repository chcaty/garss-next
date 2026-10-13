import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled = await build({entryPoints:['web/src/reading-storage.ts'], bundle:true, write:false, format:'esm', platform:'node'});
const {ReadingStorage, LEGACY_READING_KEY, READING_STORAGE_PREFIX} = await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const OP = `${READING_STORAGE_PREFIX}op:`, RECOVERY = `${READING_STORAGE_PREFIX}recovery:`, QUARANTINE = `${READING_STORAGE_PREFIX}quarantine:`;
const article = (id = 'one') => ({id,title:id,url:`https://example.com/${id}`,source_id:'source',published_at:'2026-10-03T00:00:00Z',summary:`summary ${id}`,saved_sources:[]});
class MemoryStorage {
  data = new Map(); writes = []; failRead = false; failWrite = false; beforeWrite; afterWrite;
  get length() { if (this.failRead) throw Error('access denied'); return this.data.size; }
  key(index) { if (this.failRead) throw Error('access denied'); return [...this.data.keys()][index] ?? null; }
  getItem(key) { if (this.failRead) throw Error('access denied'); return this.data.get(key) ?? null; }
  setItem(key, value) {
    if (this.failWrite) throw new DOMException('full', 'QuotaExceededError');
    this.beforeWrite?.(key,value); this.data.set(key,value); this.writes.push({key,value}); this.afterWrite?.(key,value);
  }
}
function setup(value) {
  const storage = new MemoryStorage();
  if (value !== undefined) storage.data.set(LEGACY_READING_KEY, typeof value === 'string' ? value : JSON.stringify(value));
  let sequence = 0;
  return {storage, open: (prefix='tab') => new ReadingStorage(storage, () => `${prefix}-${String(++sequence).padStart(6,'0')}`)};
}
const save = (store,id) => { store.library.toggleSaved(article(id),[]); return store.persist(); };

test('valid legacy data is read without writeback; first mutation and seed are one atomic append',()=>{
  const {storage,open}=setup({version:2,read:['old'],saved:['one'],bookmarks:[article()]});
  const raw=storage.getItem(LEGACY_READING_KEY), store=open();
  assert.equal(storage.writes.length,0); assert.equal(store.library.bookmarks.size,1);
  assert.equal(save(store,'two'),true);
  assert.equal(storage.writes.length,1); assert.equal(JSON.parse(storage.writes[0].value).base.legacy,raw);
  assert.equal(storage.getItem(LEGACY_READING_KEY),raw);
  const restarted=open(); assert.deepEqual([...restarted.library.saved],['one','two']); assert.equal(restarted.library.read.has('old'),true);
});

test('malformed whole JSON never becomes automatic empty writeback, and exports exact bytes',()=>{
  const original='{"read":["old"], BROKEN'; const {storage,open}=setup(original), store=open();
  assert.equal(store.status.kind,'recovery'); assert.equal(save(store,'new'),false);
  assert.equal(storage.writes.length,0); assert.equal(storage.getItem(LEGACY_READING_KEY),original); assert.equal(store.library.saved.size,0);
  assert.equal(JSON.parse(store.exportRecovery()).records[0].raw,original);
  assert.equal(store.recover(),true); assert.equal(storage.getItem(LEGACY_READING_KEY),original);
  assert.ok(storage.writes[0].key.startsWith(QUARANTINE)); assert.ok(storage.writes[1].key.startsWith(RECOVERY));
  assert.equal(JSON.parse(storage.writes[0].value).records[0].raw,original);
  assert.equal(save(store,'after-explicit-recovery'),true); assert.equal(open().library.saved.has('after-explicit-recovery'),true);
});

test('one damaged saved record preserves valid content and raw damaged record until explicit recovery',()=>{
  const bad={...article('bad'),url:'javascript:bad'}, {storage,open}=setup({version:2,read:['read'],saved:['one','bad'],bookmarks:[article(),bad]});
  const original=storage.getItem(LEGACY_READING_KEY), store=open();
  assert.equal(store.status.kind,'recovery'); assert.equal(store.library.bookmarks.get('one').summary,'summary one'); assert.equal(store.library.missingBookmarks,1);
  store.library.read.add('changed'); assert.equal(store.persist(),false); assert.equal(store.library.read.has('changed'),false);
  assert.equal(storage.getItem(LEGACY_READING_KEY),original); assert.equal(storage.writes.length,0);
  assert.equal(store.recover(),true); assert.equal(open().library.bookmarks.has('one'),true);
  assert.equal(JSON.parse(store.exportRecovery()).records[0].raw,original);
});

test('partial optional-field damage and unknown legacy versions pause writes instead of silently normalizing',()=>{
  for(const payload of [{version:2,bookmarks:[{...article(),source_ids:42}]},{version:99,read:['one'],saved:['two']}]) {
    const {storage,open}=setup(payload), store=open();
    assert.equal(store.status.kind,'recovery'); assert.equal(save(store,'blocked'),false); assert.equal(storage.writes.length,0);
    assert.deepEqual(JSON.parse(storage.getItem(LEGACY_READING_KEY)),payload);
  }
});

test('quota/write failure rolls back local mutation and retains old storage byte-for-byte',()=>{
  const {storage,open}=setup({version:2,saved:['one'],bookmarks:[article()]}), store=open(), before=[...storage.data];
  storage.failWrite=true; assert.equal(save(store,'two'),false);
  assert.equal(store.status.kind,'unavailable'); assert.deepEqual([...storage.data],before); assert.equal(store.library.saved.has('two'),false);
  storage.failWrite=false; assert.equal(store.refresh(),true); assert.equal(save(store,'two'),true);
});

test('read failures never turn a library into empty success or allow mutation',()=>{
  const {storage,open}=setup({version:2,saved:['one'],bookmarks:[article()]}), store=open();
  storage.failRead=true; assert.equal(store.refresh(),false); assert.equal(store.library.saved.has('one'),true); assert.equal(save(store,'two'),false);
  assert.equal(store.status.kind,'unavailable'); assert.equal(storage.writes.length,0);
  assert.throws(()=>store.exportRecovery());
  storage.failRead=false; assert.equal(store.refresh(),true); assert.equal(store.library.saved.has('two'),false);
});

test('accessor, enumeration, and verification failures fail closed',()=>{
  assert.equal(new ReadingStorage(()=>{throw Error('denied');}).status.kind,'unavailable');
  const {storage,open}=setup(), store=open();
  storage.key=()=>{throw Error('enumeration denied');}; storage.data.set('other','value');
  assert.equal(save(store,'one'),false); assert.equal(storage.writes.length,0);
  const second=setup(), uncertain=second.open(); second.storage.afterWrite=()=>{second.storage.failRead=true;};
  assert.equal(save(uncertain,'one'),false); assert.equal(uncertain.status.kind,'unavailable');
  second.storage.failRead=false; second.storage.afterWrite=undefined;
  assert.equal(uncertain.refresh(),true); assert.equal(uncertain.library.saved.has('one'),true); assert.equal(second.storage.writes.length,1);
});

test('interrupted migration is either the intact legacy value or a fully replayable atomic operation',()=>{
  const original={version:2,read:['old']}, {storage,open}=setup(original), store=open();
  storage.failWrite=true; assert.equal(save(store,'one'),false); assert.equal(open().library.read.has('old'),true); assert.equal(storage.writes.length,0);
  storage.failWrite=false; store.refresh(); storage.afterWrite=()=>{throw Error('page terminated after atomic write');};
  assert.equal(save(store,'one'),false); storage.afterWrite=undefined;
  const restarted=open(); assert.equal(restarted.status.kind,'ready'); assert.equal(restarted.library.saved.has('one'),true); assert.equal(restarted.library.read.has('old'),true);
});

test('interrupted recovery retains quarantine and keeps all reading mutations blocked',()=>{
  const {storage,open}=setup('{broken'), store=open();
  storage.beforeWrite=(key)=>{if(key.startsWith(RECOVERY))throw Error('interrupted');};
  assert.equal(store.recover(),false); assert.equal(storage.getItem(LEGACY_READING_KEY),'{broken');
  assert.equal([...storage.data.keys()].filter(key=>key.startsWith(QUARANTINE)).length,1);
  const restarted=open(); assert.equal(restarted.status.kind,'recovery'); assert.equal(save(restarted,'one'),false);
  storage.beforeWrite=undefined; assert.equal(restarted.recover(),true); assert.equal(open().status.kind,'ready');
});

test('backup failure cannot acknowledge recovery',()=>{
  const {storage,open}=setup('{broken'),store=open(); storage.failWrite=true;
  assert.equal(store.recover(),false); assert.equal(storage.writes.length,0); storage.failWrite=false;
  assert.equal(open().status.kind,'recovery');
});

test('stale tabs merge saves/read changes and do not revive removed items or read tombstones',()=>{
  const {storage,open}=setup({version:2,read:['old'],saved:['one'],bookmarks:[article()]}), a=open('a'),b=open('b');
  a.library.toggleSaved(article(),[]); a.library.read.delete('old'); assert.equal(a.persist(),true);
  b.library.read.add('new'); assert.equal(save(b,'two'),true);
  const merged=open(); assert.deepEqual([...merged.library.saved],['two']); assert.deepEqual([...merged.library.read],['new']);
  assert.equal(a.refresh(),true); assert.equal(a.library.saved.has('two'),true);
  assert.equal(storage.writes.filter(item=>item.key.startsWith(OP)).length,2);
});

test('simultaneous tabs passing the same pre-write barrier both survive with independent atomic keys',()=>{
  const {storage,open}=setup(),a=open('a'),b=open('b');
  a.library.toggleSaved(article('a'),[]);a.library.read.add('a');b.library.toggleSaved(article('b'),[]);b.library.read.add('b');
  let once=false; storage.beforeWrite=(key)=>{if(!once&&key.startsWith(OP)){once=true;assert.equal(b.persist(),true);}};
  assert.equal(a.persist(),true); storage.beforeWrite=undefined;
  const merged=open(); assert.deepEqual([...merged.library.saved].sort(),['a','b']); assert.deepEqual([...merged.library.read].sort(),['a','b']);
  const operations=storage.writes.filter(item=>item.key.startsWith(OP)).map(item=>JSON.parse(item.value));
  assert.deepEqual(operations.map(item=>item.clock),[1,1]); assert.notEqual(operations[0].id,operations[1].id);
  a.refresh();b.refresh();assert.deepEqual(a.library.toJSON(),b.library.toJSON());
});

test('same-revision conflicts deterministically prefer removal; later deliberate restoration works',()=>{
  const {storage,open}=setup({version:2,saved:['one'],bookmarks:[article()]}),a=open('a'),b=open('z');
  a.library.toggleSaved(article(),[]);
  // B observed absence before A removes: this is an explicit concurrent save.
  b.library.saved.delete('one');b.library.bookmarks.delete('one');b.persist();
  const c=open('c'); c.library.toggleSaved(article(),[]);
  let once=false; storage.beforeWrite=(key)=>{if(!once&&key.startsWith(OP)){once=true;assert.equal(c.persist(),true);}};
  assert.equal(a.persist(),true);storage.beforeWrite=undefined;
  const merged=open();assert.equal(merged.library.saved.has('one'),false);
  assert.equal(save(merged,'one'),true); assert.equal(open().library.saved.has('one'),true);
});

test('stale background snapshot enrichment does not resurrect a concurrent removal',()=>{
  const {open}=setup({version:2,saved:['one']}), a=open('a'),b=open('b');
  a.library.reconcile([article()],[]);b.library.toggleSaved(article(),[]);assert.equal(b.persist(),true);
  assert.equal(a.persist([article()]),true);assert.equal(open().library.saved.has('one'),false);
});

test('stale alias reconciliation cannot undo a removal or mark-unread',()=>{
  const old=article('old'),current={...article('new'),legacy_ids:['old']};
  const {open}=setup({version:2,read:['old'],saved:['old'],bookmarks:[old]}),a=open('a'),b=open('b');
  a.library.reconcile([current],[]); b.library.toggleSaved(old,[]); b.library.markUnread(old); assert.equal(b.persist(),true);
  assert.equal(a.persist([current]),true); const merged=open();
  assert.equal(merged.library.saved.size,0);assert.equal(merged.library.read.size,0);assert.equal(merged.library.bookmarks.size,0);
});

test('legacy alias migration preserves saved content/read state when its prerequisites still exist',()=>{
  const current={...article('new'),legacy_ids:['old']}, {open}=setup({version:2,read:['old'],saved:['old']}), store=open();
  assert.equal(store.reconcile([current],[]),true); const restarted=open();
  assert.equal(restarted.library.read.has('new'),true);assert.deepEqual([...restarted.library.saved],['new']);assert.equal(restarted.library.bookmarks.has('new'),true);
});

test('malformed operation and unknown journal versions are preserved and block new writes',()=>{
  for(const raw of ['{broken',JSON.stringify({version:99,id:'bad',clock:1,changes:[]})]) {
    const {storage,open}=setup();storage.data.set(OP+'bad',raw);const store=open();
    assert.equal(store.status.kind,'recovery');assert.equal(save(store,'one'),false);assert.equal(storage.writes.length,0);
    assert.equal(store.recover(),true);assert.equal(storage.getItem(OP+'bad'),raw);assert.equal(save(store,'one'),true);assert.equal(open().library.saved.has('one'),true);
  }
});

test('single malformed operation change is quarantined without discarding valid changes',()=>{
  const {storage,open}=setup(); storage.data.set(OP+'bad',JSON.stringify({version:3,id:'bad',clock:1,base:{legacy:null},changes:[{field:'read',id:'one',value:true},{field:'saved',id:'bad',value:true,bookmark:{id:'bad'}}]}));
  const store=open();assert.equal(store.status.kind,'recovery');assert.equal(store.library.read.has('one'),true);assert.equal(store.library.saved.has('bad'),false);
  assert.equal(store.recover(),true);assert.equal(open().library.read.has('one'),true);
});

test('an older app changing the legacy blob after migration is detected, not silently lost',()=>{
  const {storage,open}=setup({version:2,read:['old']}), store=open();save(store,'one');
  const changed=JSON.stringify({version:2,read:['other']});storage.data.set(LEGACY_READING_KEY,changed);
  assert.equal(store.refresh(),false);assert.equal(store.status.kind,'recovery');assert.equal(store.library.saved.has('one'),true);
  assert.equal(save(store,'blocked'),false);assert.equal(storage.getItem(LEGACY_READING_KEY),changed);
  assert.ok(JSON.parse(store.exportRecovery()).records.some(record=>record.raw===changed));
});

test('recovery only acknowledges exact bytes: subsequent corruption blocks again',()=>{
  const {storage,open}=setup('{broken'),store=open();assert.equal(store.recover(),true);
  storage.data.set(LEGACY_READING_KEY,'{different broken');assert.equal(store.refresh(),false);assert.equal(store.status.kind,'recovery');
});

test('UUID collision refuses overwrite and stable collection identities survive refresh',()=>{
  const {storage}=setup(),store=new ReadingStorage(storage,()=> 'same'),read=store.library.read,saved=store.library.saved,bookmarks=store.library.bookmarks;
  assert.equal(save(store,'one'),true);const before=[...storage.data];assert.equal(save(store,'two'),false);assert.deepEqual([...storage.data],before);
  store.refresh();assert.equal(store.library.read,read);assert.equal(store.library.saved,saved);assert.equal(store.library.bookmarks,bookmarks);
});

test('a denied storage accessor can be retried after permissions change',()=>{
  const storage=new MemoryStorage();let denied=true;
  const store=new ReadingStorage(()=>{if(denied)throw Error('denied');return storage;},()=> 'available');
  assert.equal(store.status.kind,'unavailable');denied=false;assert.equal(store.refresh(),true);assert.equal(save(store,'one'),true);
});

test('state revision changes only when an accepted local or remote state changes',()=>{
  const {open}=setup(),a=open('a'),b=open('b');const initial=a.revision;
  a.refresh();assert.equal(a.revision,initial);save(a,'one');assert.equal(a.revision,initial+1);
  a.refresh();assert.equal(a.revision,initial+1);save(b,'two');a.refresh();assert.equal(a.revision,initial+2);
});
