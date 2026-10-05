import test from 'node:test';
import assert from 'node:assert/strict';
import {transform} from 'esbuild';
import {readFile} from 'node:fs/promises';

const code=await transform(await readFile(new URL('../web/src/sync-model.ts',import.meta.url),'utf8'),{loader:'ts',format:'esm'});
const {syncSourceStatus,filterSyncSources}=await import(`data:text/javascript;base64,${Buffer.from(code.code).toString('base64')}`);
const source={id:'a',title:'Source A',description:'Not searchable here',category:'Tech',feed_url:'https://example.com/rss',enabled:true,status:'ok'};

test('sync source status retains archive, disable and error precedence with missing health',()=>{
  assert.equal(syncSourceStatus({...source,enabled:false},{a:{status:'archived'}}),'archived');
  assert.equal(syncSourceStatus({...source,enabled:false},{a:{status:'error'}}),'disabled');
  assert.equal(syncSourceStatus(source,{a:{status:'error'}}),'error');
  assert.equal(syncSourceStatus({...source,status:'error'},{a:{status:'active'}}),'error');
  assert.equal(syncSourceStatus(source,{}),'ok');
  assert.equal(syncSourceStatus({...source,status:undefined},{}),'pending');
});

test('sync filtering combines health and search while retaining source order and inputs',()=>{
  const feeds=[source,{...source,id:'b',status:'error'},{...source,id:'c',category:'News',status:'error'}];
  const snapshot=JSON.stringify(feeds);
  assert.deepEqual(filterSyncSources(feeds,{},'error','  TECH  ').map(item=>item.id),['b']);
  assert.deepEqual(filterSyncSources(feeds,{},'all','example.com').map(item=>item.id),['a','b','c']);
  assert.deepEqual(filterSyncSources(feeds,{},'all','Not searchable here'),[]);
  assert.equal(JSON.stringify(feeds),snapshot);
});
