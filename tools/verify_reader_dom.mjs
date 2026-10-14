#!/usr/bin/env node
/**
 * DOM-runtime integration smoke for the real reader entrypoint and HTML.
 * This does not launch a browser or verify rendered layout, native dialog behavior,
 * keyboard defaults, phone behavior, CSP enforcement, or real network/storage APIs.
 *
 * Install the optional DOM dependency OUTSIDE this repository, then run:
 * npm install --prefix /tmp/shiyue-test-tools --cache /tmp/shiyue-npm-cache --ignore-scripts --no-audit --no-fund jsdom@30.1.2
 * JSDOM_MODULE_ROOT=/tmp/shiyue-test-tools node tools/verify_reader_dom.mjs --fixture /path/to/pinned-fixture
 * Without --fixture, only the deterministic synthetic integration scenarios run.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {resolve, dirname, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash, webcrypto} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {build} from 'esbuild';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const externalRoot = process.env.JSDOM_MODULE_ROOT;
const require = createRequire(externalRoot ? resolve(externalRoot, 'package.json') : import.meta.url);
let JSDOM, VirtualConsole;
try { ({JSDOM, VirtualConsole} = require('jsdom')); }
catch { throw Error('Optional jsdom dependency unavailable. Install it outside the repository and set JSDOM_MODULE_ROOT. See this script header.'); }
const fixtureFlag = process.argv.indexOf('--fixture');
const realFixtureRoot = fixtureFlag < 0 ? undefined : resolve(process.argv[fixtureFlag + 1]);
const html = await readFile(resolve(root, 'web/public/index.html'), 'utf8');
const built = await build({absWorkingDir: root, entryPoints:['web/src/reader.ts'], bundle:true, write:false, format:'iife', platform:'browser', target:'es2022'});
const bundle = built.outputFiles[0].text;
const baseUrl = 'https://reader.test/';
const fixedNow = Date.parse('2026-10-13T10:00:00Z');
const LEGACY = 'garss-reading';
const PREFIX = 'garss-reading-v3:';
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, label, timeout = 10000) {
  const start = performance.now();
  while (!predicate()) {
    if (performance.now() - start > timeout) throw Error(`Timed out: ${label}`);
    await delay(5);
  }
}
function makeSnapshot(id = 'synthetic', suffix = '') {
  const sources = [
    {id:'alpha',title:'Alpha feed',category:'技术',enabled:true},
    {id:'beta',title:'Beta feed',category:'新闻',enabled:true},
    {id:'empty',title:'Empty feed',category:'生活',enabled:true},
  ];
  const articles = Array.from({length:43}, (_, i) => ({
    id:`entry-${String(i).padStart(3,'0')}${suffix}`,
    source_id:i % 2 ? 'beta' : 'alpha',
    source_ids:i % 3 === 0 ? ['alpha','beta'] : [i % 2 ? 'beta':'alpha'],
    title:`Article ${i}${suffix}`,
    summary:i === 0 ? '<p>Readable summary</p><script>doNotRun()</script><style>.hidden{}</style><div>Second line</div>' : `<p>Useful body ${i} ${i % 2 ? 'odd':'even'}</p>`,
    url:`https://news.test/article/${i}${suffix}`,
    published_at:new Date(fixedNow - (i + 1) * 3600000).toISOString(),
  }));
  return snapshotFromData(id, sources, articles);
}
function snapshotFromData(id, sources, articles) {
  const generated_at = new Date(fixedNow).toISOString();
  const dir = `/api/v1/snapshots/${id}/`;
  const bodies = new Map([
    [dir+'feeds.json', Buffer.from(JSON.stringify({generated_at,feeds:sources,source_aliases:{old_alpha:'alpha'}}))],
    [dir+'articles.json', Buffer.from(JSON.stringify({generated_at,articles}))],
  ]);
  const manifest = {snapshot_id:id,generated_at,files:Object.fromEntries([...bodies].map(([path,body]) => [path.split('/').at(-1),{bytes:body.length,sha256:createHash('sha256').update(body).digest('hex')}]))};
  bodies.set(dir+'manifest.json', Buffer.from(JSON.stringify(manifest)));
  bodies.set('/api/v1/meta.json', Buffer.from(JSON.stringify({snapshot_id:id,generated_at,snapshot_endpoint:`./snapshots/${id}/manifest.json`})));
  return {id,sources,articles,bodies,generated_at};
}
async function loadRealSnapshot(directory) {
  const meta = JSON.parse(await readFile(resolve(directory,'api/v1/meta.json'),'utf8'));
  const manifestUrl = new URL(meta.snapshot_endpoint, new URL('/api/v1/meta.json',baseUrl));
  const paths = ['/api/v1/meta.json',manifestUrl.pathname,...['feeds.json','articles.json'].map(name=>new URL(name,manifestUrl).pathname)];
  const bodies = new Map();
  for (const path of paths) {
    const full = resolve(directory, '.'+path);
    assert.ok(full.startsWith(directory+sep), 'Fixture reads stay inside selected fixture directory');
    bodies.set(path, await readFile(full));
  }
  const sourceData = JSON.parse(bodies.get(paths[2]).toString());
  const articleData = JSON.parse(bodies.get(paths[3]).toString());
  const sources=sourceData.feeds.filter(source=>source.enabled!==false);
  const articles=articleData.articles.filter(article=>{try{const url=new URL(article.url);return ['http:','https:'].includes(url.protocol)&&!url.username&&!url.password;}catch{return false;}});
  return {id:meta.snapshot_id,sources,articles,bodies,generated_at:meta.generated_at};
}
class FixtureNetwork {
  calls=[]; fail=false; holdNextMeta=false; pending=[];
  constructor(snapshot) { this.snapshot=snapshot; this.bodies=new Map(snapshot.bodies); }
  setSnapshot(snapshot) { this.snapshot=snapshot; for(const [key,value] of snapshot.bodies)this.bodies.set(key,value); }
  fetch=async input => {
    const url = new URL(String(input),baseUrl);
    assert.equal(url.origin, new URL(baseUrl).origin, 'No real/external fetches');
    this.calls.push(url.pathname);
    if(this.fail)throw Error('Synthetic offline fixture');
    const body=this.bodies.get(url.pathname);
    if(url.pathname==='/api/v1/meta.json' && this.holdNextMeta){
      this.holdNextMeta=false;
      return new Promise(resolve=>this.pending.push(()=>resolve(new Response(body,{status:200}))));
    }
    return new Response(body,{status:body?200:404});
  };
}
class SharedStorage {
  values=new Map(); writes=[]; tabs=new Set(); failWrite=false; queueEvents=true; pending=[];
  constructor(seed={}) { for(const [key,value] of Object.entries(seed))this.values.set(key,typeof value==='string'?value:JSON.stringify(value)); }
  attach(window) {
    this.tabs.add(window); const self=this;
    return {
      get length(){return self.values.size;},
      key(index){return [...self.values.keys()][index]??null;},
      getItem(key){return self.values.get(String(key))??null;},
      setItem(key,value){
        if(self.failWrite)throw new window.DOMException('Synthetic quota full','QuotaExceededError');
        key=String(key);value=String(value);const oldValue=self.values.get(key)??null;
        self.values.set(key,value);self.writes.push({key,value});
        for(const other of self.tabs)if(other!==window){
          const emit=()=>other.dispatchEvent(new other.StorageEvent('storage',{key,oldValue,newValue:value,url:baseUrl}));
          if(self.queueEvents)self.pending.push(emit);else queueMicrotask(emit);
        }
      },
    };
  }
  flush(){for(const emit of this.pending.splice(0))emit();}
}
async function openReader({snapshot=makeSnapshot(),network=new FixtureNetwork(snapshot),storage=new SharedStorage(),search='',narrow=false,awaitLoad=true}={}) {
  const errors=[]; const virtualConsole=new VirtualConsole();
  virtualConsole.on('jsdomError',error=>errors.push(error));
  const dom=new JSDOM(html,{url:baseUrl+search,runScripts:'outside-only',pretendToBeVisual:true,virtualConsole});
  const {window}=dom; const nativeDate=window.Date;
  class FixedDate extends nativeDate { constructor(...args){super(...(args.length?args:[fixedNow]));} static now(){return fixedNow;} }
  window.Date=FixedDate;
  Object.defineProperty(window,'crypto',{value:webcrypto,configurable:true});
  Object.defineProperty(window,'localStorage',{value:storage.attach(window),configurable:true});
  window.TextDecoder=TextDecoder;window.TextEncoder=TextEncoder;window.fetch=network.fetch;
  window.matchMedia=query=>({matches:query.includes('max-width')?narrow:false,media:query,addEventListener(){},removeEventListener(){}});
  window.scrollTo=()=>{};window.HTMLElement.prototype.scrollIntoView=function(){};
  window.HTMLDialogElement.prototype.showModal=function(){this.open=true;};
  window.HTMLDialogElement.prototype.close=function(){if(!this.open)return;this.open=false;this.dispatchEvent(new window.Event('close'));};
  window.URL.createObjectURL=()=> 'blob:https://reader.test/fixture-backup';window.URL.revokeObjectURL=()=>{};
  window.eval(bundle);
  const $=id=>window.document.getElementById(id);
  const rows=()=>[...window.document.querySelectorAll('.article-row')];
  const resultCount=()=>Number($('result-count').textContent.match(/^\d+/)?.[0]);
  const click=id=>$(id).click();
  const set=(id,value,event='change')=>{const node=$(id);if(node.type==='checkbox')node.checked=value;else node.value=value;node.dispatchEvent(new window.Event(event,{bubbles:true}));};
  const done=()=>until(()=>$('articles').getAttribute('aria-busy')==='false','catalog load',20000);
  const close=()=>{storage.tabs.delete(window);dom.window.close();assert.equal(errors.length,0,errors.map(error=>error.stack).join('\n'));};
  if(awaitLoad)await done();
  return {window,document:window.document,$,rows,resultCount,click,set,network,storage,done,close,errors};
}
function expectedSelection(snapshot,{query='',source='',category='',unread=new Set(),unreadOnly=false,window='all',oldest=false}={}) {
  const names=new Map(snapshot.sources.map(value=>[value.id,value]));
  const start=Math.floor((fixedNow+8*3600000)/86400000)*86400000-8*3600000-(window==='week'?6*86400000:0);
  return snapshot.articles.filter(article=>{
    const ids=article.source_ids??[article.source_id];
    const stamp=Date.parse(article.published_at);
    return (!source||ids.includes(source)) && (!category||ids.some(id=>names.get(id)?.category===category)) &&
      (window==='all'||stamp>=start&&stamp<=fixedNow) && (!unreadOnly||!unread.has(article.id)) &&
      `${article.title} ${article.summary??''} ${ids.map(id=>names.get(id)?.title??id).join(' ')}`.toLowerCase().includes(query.trim().toLowerCase());
  }).sort((a,b)=>oldest?Date.parse(a.published_at)-Date.parse(b.published_at):Date.parse(b.published_at)-Date.parse(a.published_at));
}
function assertRows(ui,expected){assert.equal(ui.resultCount(),expected.length);assert.deepEqual(ui.rows().map(row=>row.dataset.articleId),expected.slice(0,30).map(article=>article.id));}
function rowFor(ui,id){return ui.rows().find(row=>row.dataset.articleId===id);}
function clickSource(ui,title){const button=[...ui.$('source-list').querySelectorAll('button')].find(node=>node.querySelector('span')?.textContent===title);assert.ok(button,`Source exists: ${title}`);button.click();}

console.log('DOM-runtime integration only. Browser rendering, native dialog, CSP, accessibility and phone/device behavior are not tested.');

test('initial real entrypoint load, metadata, source alias, filters, search, pagination and indexed selections',async()=>{
 const snapshot=makeSnapshot();const ui=await openReader({snapshot,search:'?source=old_alpha'});
 try{
  assert.equal(ui.network.calls.length,4);assert.match(ui.$('snapshot-info').textContent,/公共采集.*本机检查.*2 个有文章的来源/);
  assert.equal(ui.$('source-count').textContent,'2');assertRows(ui,expectedSelection(snapshot,{source:'alpha'}));
  ui.click('clear-filters');assertRows(ui,expectedSelection(snapshot));assert.equal(ui.rows().length,30);
  ui.click('next-page');assert.equal(ui.rows().length,13);assert.equal(ui.$('page-indicator').textContent,'第 2 / 2 页');
  ui.click('previous-page');ui.set('article-search','useful body','input');ui.set('reading-category','新闻');ui.set('reading-window','today');ui.set('article-sort','oldest');
  assertRows(ui,expectedSelection(snapshot,{query:'useful body',category:'新闻',window:'today',oldest:true}));
  ui.set('reading-window','week');clickSource(ui,'Beta feed');
  assertRows(ui,expectedSelection(snapshot,{query:'useful body',category:'新闻',window:'week',oldest:true,source:'beta'}));
  ui.set('source-search','alpha','input');assert.equal(ui.$('source-list').querySelectorAll('button').length,2);
  ui.click('clear-filters');assertRows(ui,expectedSelection(snapshot));
  assert.equal(ui.network.calls.length,4,'filters do not re-fetch catalog');assert.equal(ui.storage.writes.length,0,'load/filtering never writes empty reading state');
 }finally{ui.close();}
});

test('focus open/read/unread, summary sanitization, close focus, saved filters, remove/undo and persistence',async()=>{
 const snapshot=makeSnapshot();const storage=new SharedStorage();const ui=await openReader({snapshot,storage});
 try{
  const first=snapshot.articles[0];rowFor(ui,first.id).querySelector('.article-title').click();
  assert.equal(ui.$('focus-reader').open,true);assert.equal(ui.$('focus-title').textContent,first.title);assert.match(ui.$('focus-summary').textContent,/Readable summary/);
  assert.doesNotMatch(ui.$('focus-summary').textContent,/doNotRun|hidden/);assert.equal(ui.$('focus-read').textContent,'标记为未读');
  ui.click('focus-read');assert.equal(ui.$('focus-read').textContent,'标记为已读');ui.click('focus-save');assert.equal(ui.$('focus-save').textContent,'移出稍后读');
  ui.click('focus-next');assert.equal(ui.$('focus-position').textContent,'本次筛选 · 第 2 / 43 篇');ui.click('focus-previous');
  ui.click('focus-close');assert.equal(ui.$('focus-reader').open,false);assert.equal(ui.document.activeElement.textContent,first.title);assert.equal(rowFor(ui,first.id).classList.contains('is-read'),true);
  rowFor(ui,first.id).querySelector('.text-button').click();assert.equal(rowFor(ui,first.id).classList.contains('is-read'),false);
  ui.set('article-search','Useful','input');ui.document.querySelector('[data-mode="saved"]').click();assert.equal(ui.$('article-search').value,'');assert.equal(ui.resultCount(),1);
  ui.set('saved-unread',true);assert.equal(ui.resultCount(),1);rowFor(ui,first.id).querySelector('.save-article').click();assert.equal(ui.resultCount(),0);assert.equal(ui.$('undo-save').hidden,false);
  ui.click('undo-save');assert.equal(ui.resultCount(),1);assert.equal(ui.$('undo-save').hidden,true);
  ui.document.querySelector('[data-mode="all"]').click();assert.equal(ui.$('article-search').value,'Useful');
  const reopened=await openReader({snapshot,storage});try{reopened.document.querySelector('[data-mode="saved"]').click();assert.equal(reopened.resultCount(),1);assert.equal(reopened.rows()[0].dataset.articleId,first.id);}finally{reopened.close();}
 }finally{ui.close();}
});

test('corruption blocks changes; recovery checkbox and cancel preserve exact original, explicit recovery retains quarantine',async()=>{
 const snapshot=makeSnapshot();const first=snapshot.articles[0];
 const raw=JSON.stringify({version:2,read:[first.id],saved:[first.id,'bad'],bookmarks:[{...first,saved_sources:[snapshot.sources[0],snapshot.sources[1]]},{id:'bad',url:'javascript:bad'}]});
 const storage=new SharedStorage({[LEGACY]:raw});const ui=await openReader({snapshot,storage});
 try{
  assert.equal(ui.$('reading-recovery').hidden,false);assert.match(ui.$('reading-status').textContent,/损坏|版本冲突/);assert.equal(storage.writes.length,0);
  assert.equal(ui.rows()[0].querySelector('.save-article').disabled,true);ui.rows()[0].querySelector('.article-title').click();assert.equal(ui.$('focus-save').disabled,true);ui.click('focus-close');
  ui.click('recover-reading');assert.equal(ui.$('reading-recovery-dialog').open,true);assert.equal(ui.$('apply-reading-recovery').disabled,true);
  ui.click('apply-reading-recovery');assert.equal(storage.writes.length,0);ui.set('confirm-reading-recovery',true);assert.equal(ui.$('apply-reading-recovery').disabled,false);
  ui.click('cancel-reading-recovery');assert.equal(ui.$('reading-recovery-dialog').open,false);assert.equal(storage.writes.length,0);assert.equal(storage.values.get(LEGACY),raw);
  ui.click('recover-reading');assert.equal(ui.$('confirm-reading-recovery').checked,false);assert.equal(ui.$('apply-reading-recovery').disabled,true);
  ui.set('confirm-reading-recovery',true);ui.click('apply-reading-recovery');assert.equal(ui.$('reading-recovery').hidden,true);assert.equal(storage.values.get(LEGACY),raw);
  const quarantines=storage.writes.filter(record=>record.key.startsWith(PREFIX+'quarantine:'));assert.equal(quarantines.length,1);assert.ok(JSON.parse(quarantines[0].value).records.some(record=>record.key===LEGACY&&record.raw===raw));
  assert.ok(storage.writes.some(record=>record.key.startsWith(PREFIX+'recovery:')));
  ui.document.querySelector('[data-mode="saved"]').click();assert.equal(ui.resultCount(),1);assert.equal(ui.rows()[0].dataset.articleId,first.id);assert.equal(ui.rows()[0].querySelector('.save-article').disabled,false);
 }finally{ui.close();}
});

test('two actual reader instances merge independent stale-tab operations and storage-event removals without writeback',async()=>{
 const snapshot=makeSnapshot();const storage=new SharedStorage();const a=await openReader({snapshot,storage});const b=await openReader({snapshot,storage});
 try{
  const [first,second]=snapshot.articles;
  rowFor(a,first.id).querySelector('.save-article').click();rowFor(b,second.id).querySelector('.save-article').click();
  const writeCount=storage.writes.length;assert.equal(writeCount,2);storage.flush();await delay(65);
  a.document.querySelector('[data-mode="saved"]').click();b.document.querySelector('[data-mode="saved"]').click();assert.equal(a.resultCount(),2);assert.equal(b.resultCount(),2);assert.equal(storage.writes.length,writeCount);
  rowFor(a,first.id).querySelector('.save-article').click();storage.flush();await delay(65);assert.equal(a.resultCount(),1);assert.equal(b.resultCount(),1);assert.equal(b.rows()[0].dataset.articleId,second.id);
  rowFor(b,second.id).querySelector('.text-button').click();storage.flush();await delay(65);assert.equal(a.rows()[0].classList.contains('is-read'),true);assert.equal(b.rows()[0].classList.contains('is-read'),true);
  const count=storage.writes.length;b.window.dispatchEvent(new b.window.StorageEvent('storage',{key:null,url:baseUrl}));await delay(65);assert.equal(storage.writes.length,count);
 }finally{a.close();b.close();}
});

test('same-snapshot refresh reuses verified bodies; failed refresh retains catalog and reading state; retry works',async()=>{
 const snapshot=makeSnapshot();const ui=await openReader({snapshot});
 try{
  ui.rows()[0].querySelector('.save-article').click();const writes=ui.storage.writes.length;
  for(let i=0;i<3;i++){const before=ui.network.calls.length;ui.click('refresh-catalog');await ui.done();assert.equal(ui.network.calls.length-before,2);assert.match(ui.$('reading-status').textContent,/暂无变化/);assertRows(ui,expectedSelection(snapshot));}
  assert.equal(ui.storage.writes.length,writes);ui.network.fail=true;ui.click('refresh-catalog');await ui.done();
  assertRows(ui,expectedSelection(snapshot));assert.match(ui.$('reading-status').textContent,/继续显示上次通过校验的目录/);assert.equal(ui.$('retry-load').hidden,false);assert.equal(ui.rows()[0].querySelector('.save-article').getAttribute('aria-pressed'),'true');
  ui.network.fail=false;ui.click('retry-load');await ui.done();assert.equal(ui.$('retry-load').hidden,true);assertRows(ui,expectedSelection(snapshot));assert.equal(ui.storage.writes.length,writes);
 }finally{ui.close();}
});

test('overlapping load-handler calls ignore late older completion and retain newest metadata/content',async()=>{
 const older=makeSnapshot('older','-old');const newer=makeSnapshot('newer','-new');const network=new FixtureNetwork(older);network.holdNextMeta=true;
 const ui=await openReader({snapshot:older,network,awaitLoad:false});
 try{
  await until(()=>network.pending.length===1,'held old metadata');network.setSnapshot(newer);
  // Invoke the already-bound public button handler to exercise an overlapping
  // asynchronous call, without claiming users can click the disabled button.
  ui.$('refresh-catalog').onclick(new ui.window.MouseEvent('click'));await ui.done();assert.equal(ui.rows()[0].dataset.articleId,newer.articles[0].id);
  network.pending.shift()();await until(()=>network.calls.filter(path=>path.includes('/older/')).length===3,'old load completes');await delay(30);
  assert.equal(ui.rows()[0].dataset.articleId,newer.articles[0].id);assert.equal(ui.$('refresh-catalog').disabled,false);assert.equal(ui.$('retry-load').hidden,true);
 }finally{ui.close();}
});

test('write failure rolls back visible save and blocks writes until storage retry',async()=>{
 const snapshot=makeSnapshot();const storage=new SharedStorage();const ui=await openReader({snapshot,storage});
 try{
  storage.failWrite=true;ui.rows()[0].querySelector('.save-article').click();assert.equal(storage.writes.length,0);assert.equal(ui.rows()[0].querySelector('.save-article').getAttribute('aria-pressed'),'false');
  assert.equal(ui.rows()[0].querySelector('.save-article').disabled,true);assert.match(ui.$('reading-status').textContent,/无法读取或保存/);
  storage.failWrite=false;ui.click('retry-reading-storage');assert.equal(ui.rows()[0].querySelector('.save-article').disabled,false);ui.rows()[0].querySelector('.save-article').click();assert.equal(storage.writes.length,1);
 }finally{ui.close();}
});

if(realFixtureRoot)test('full real immutable fixture: verified load and repeated index-driven DOM search/filter/count checks',async t=>{
 const snapshot=await loadRealSnapshot(realFixtureRoot);const started=performance.now();const ui=await openReader({snapshot});const loadMs=performance.now()-started;
 try{
  assertRows(ui,expectedSelection(snapshot));const queries=['AI','人工智能','Python','开源','Useful nonexistent query 983457',''];const times=[];
  for(let repeat=0;repeat<3;repeat++)for(const query of queries){const start=performance.now();ui.set('article-search',query,'input');times.push(performance.now()-start);assertRows(ui,expectedSelection(snapshot,{query}));}
  const category=ui.$('reading-category').options[1]?.value;assert.ok(category);ui.set('reading-category',category);ui.set('article-sort','oldest');assertRows(ui,expectedSelection(snapshot,{category,oldest:true}));
  ui.click('clear-filters');const before=ui.network.calls.length;ui.click('refresh-catalog');await ui.done();assert.equal(ui.network.calls.length-before,2);assertRows(ui,expectedSelection(snapshot));
  t.diagnostic(JSON.stringify({verification:'DOM runtime only',snapshot:snapshot.id,articles:snapshot.articles.length,sources:Number(ui.$('source-count').textContent),initialLoadMs:Number(loadMs.toFixed(1)),searchCount:times.length,medianSearchMs:Number([...times].sort((a,b)=>a-b)[Math.floor(times.length/2)].toFixed(1)),maximumSearchMs:Number(Math.max(...times).toFixed(1)),refreshBodyRequests:0}));
 }finally{ui.close();}
});

test('offline initial load retains saved article snapshots; successful retry restores the stream',async()=>{
 const snapshot=makeSnapshot();const first=snapshot.articles[0];
 const raw=JSON.stringify({version:2,read:[],saved:[first.id],bookmarks:[{...first,saved_sources:snapshot.sources.slice(0,2)}]});
 const storage=new SharedStorage({[LEGACY]:raw});const network=new FixtureNetwork(snapshot);network.fail=true;
 const ui=await openReader({snapshot,storage,network});
 try{
  assert.equal(ui.$('page-title').textContent,'稍后读');assert.equal(ui.resultCount(),1);assert.equal(ui.rows()[0].dataset.articleId,first.id);
  assert.match(ui.$('reading-status').textContent,/公共目录读取失败/);assert.equal(ui.$('retry-load').hidden,false);assert.equal(storage.writes.length,0);
  ui.rows()[0].querySelector('.article-title').click();assert.match(ui.$('focus-summary').textContent,/Readable summary/);ui.click('focus-close');
  network.fail=false;ui.click('retry-load');await ui.done();assert.equal(ui.$('retry-load').hidden,true);assert.equal(ui.resultCount(),1);
  ui.document.querySelector('[data-mode="all"]').click();assertRows(ui,expectedSelection(snapshot));assert.equal(storage.values.get(LEGACY),raw);
 }finally{ui.close();}
});

test('malformed JSON preserves exact bytes and never silently writes an empty replacement',async()=>{
 const original='{"read":["kept"], BROKEN';const storage=new SharedStorage({[LEGACY]:original});const ui=await openReader({storage});
 try{
  assert.equal(ui.$('reading-recovery').hidden,false);assert.equal(storage.writes.length,0);assert.equal(storage.values.get(LEGACY),original);
  ui.rows()[0].querySelector('.article-title').click();assert.equal(ui.$('focus-read').disabled,true);ui.click('focus-close');assert.equal(storage.writes.length,0);
  ui.click('recover-reading');ui.click('cancel-reading-recovery');assert.equal(storage.values.get(LEGACY),original);assert.equal(storage.writes.length,0);
 }finally{ui.close();}
});

test('narrow media-query DOM hosts and dialog close retain filters; shortcut input/composition guards work',async()=>{
 const ui=await openReader({narrow:true});
 try{
  assert.equal(ui.$('filter-fields').parentElement.id,'mobile-filter-host');assert.equal(ui.document.querySelector('.source-index').parentElement.id,'mobile-source-host');
  ui.click('open-filters');assert.equal(ui.$('filter-dialog').open,true);ui.set('reading-category','新闻');const count=ui.resultCount();ui.click('close-filters');
  assert.equal(ui.$('filter-dialog').open,false);assert.equal(ui.$('reading-category').value,'新闻');assert.equal(ui.resultCount(),count);
  ui.click('open-filters');ui.click('close-filters');assert.equal(ui.resultCount(),count);
  ui.document.body.dispatchEvent(new ui.window.KeyboardEvent('keydown',{key:'/',bubbles:true}));assert.equal(ui.document.activeElement,ui.$('article-search'));
  ui.$('article-search').dispatchEvent(new ui.window.KeyboardEvent('keydown',{key:'j',bubbles:true}));assert.equal(ui.document.querySelectorAll('.is-selected').length,0);
  ui.document.body.dispatchEvent(new ui.window.KeyboardEvent('keydown',{key:'j',isComposing:true,bubbles:true}));assert.equal(ui.document.querySelectorAll('.is-selected').length,0);
  ui.document.body.dispatchEvent(new ui.window.KeyboardEvent('keydown',{key:'j',bubbles:true}));assert.equal(ui.document.querySelectorAll('.is-selected').length,1);
  ui.document.body.dispatchEvent(new ui.window.KeyboardEvent('keydown',{key:'o',bubbles:true}));assert.equal(ui.$('focus-reader').open,true);ui.click('focus-close');
 }finally{ui.close();}
});
