import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled = await build({entryPoints:['web/src/reading-index.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {ReadingIndex} = await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const now = Date.parse('2026-10-13T04:00:00Z');
const source = (id,title,category) => ({id,title,category});
const article = (id,published_at,source_ids=['a']) => ({id,title:id,summary:'Useful summary',published_at,source_id:source_ids[0],source_ids});
const sources = [source('a','Alpha','技术'),source('b','Beta','新闻')];
const entries = [article('old','2026-10-01T00:00:00Z'),article('shared','2026-10-12T16:00:00Z',['a','b']),article('same','2026-10-12T16:00:00Z'),article('future','2026-10-14T00:00:00Z')];
test('indexed filters combine Beijing windows, shared category, names, source and unread', () => {
 const index = new ReadingIndex(entries,sources);
 assert.deepEqual(index.select({query:'beta',category:'新闻',source:'b',window:'today',now}).map(x=>x.id),['shared']);
 assert.deepEqual(index.select({window:'today',now,unreadOnly:true,read:new Set(['shared'])}).map(x=>x.id),['same']);
 assert.deepEqual(index.select({query:'useful summary',window:'week',now}).map(x=>x.id),['shared','same']);
});
test('precomputed sorts preserve equal-date order and do not mutate inputs', () => {
 const original=entries.slice(); const index=new ReadingIndex(entries,sources);
 assert.deepEqual(index.select().map(x=>x.id),['future','shared','same','old']);
 assert.deepEqual(index.select({oldest:true}).map(x=>x.id),['old','shared','same','future']);
 assert.deepEqual(entries,original);
});
test('saved articles retain individual source metadata after source renames', () => {
 const saved={...entries[1],saved_sources:[source('a','Original name','原分类'),source('b','Other','其他')]};
 const index=new ReadingIndex([saved],sources);
 assert.equal(index.select({query:'original name',category:'原分类'}).length,1);
 assert.equal(index.select({query:'alpha'}).length,0);
 assert.equal(index.select({category:'技术'}).length,0);
});
test('read-set changes apply immediately without rebuilding the index', () => {
 const index=new ReadingIndex(entries,sources),read=new Set();
 assert.equal(index.select({unreadOnly:true,read}).length,4);
 read.add('old'); assert.equal(index.select({unreadOnly:true,read}).length,3);
 read.delete('old'); assert.equal(index.select({unreadOnly:true,read}).length,4);
});
