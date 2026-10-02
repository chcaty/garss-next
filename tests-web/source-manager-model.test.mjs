import test from 'node:test';
import assert from 'node:assert/strict';
import {transform} from 'esbuild';
import {readFile} from 'node:fs/promises';
const code=await transform(await readFile(new URL('../web/src/source-manager-model.ts',import.meta.url),'utf8'),{loader:'ts',format:'esm'});
const {rebaseDraft,archived}=await import(`data:text/javascript;base64,${Buffer.from(code.code).toString('base64')}`);
const a={id:'a',title:'A',description:'',category:'Tech',feed_url:'https://a.test/rss',enabled:true};
const config=sources=>({schema_version:'1.0',repository:{owner:'o',name:'n',branch:'main',path:'sources.json'},sources});
test('draft rebase preserves remote additions and untouched remote fields while applying local edits and deletion',()=>{
 const base=config([a,{...a,id:'b'}]),local=config([{...a,title:'Local A'}]),remote=config([{...a,category:'Remote category'},{...a,id:'b'},{...a,id:'c'}]);
 const merged=rebaseDraft(base,local,remote);
 assert.deepEqual(merged.sources.map(item=>item.id),['a','c']);
 assert.equal(merged.sources[0].category,'Remote category');assert.equal(merged.sources[0].title,'Local A');
});
test('explicit retry or changed URL leaves archive in draft without claiming collection recovered',()=>{
 const health={status:'archived',failures:3,signature:[a.feed_url,'']};
 assert.equal(archived(a,health),true);assert.equal(archived({...a,recheck_requested_at:'2026-10-03'},health),false);
 assert.equal(archived({...a,feed_url:'https://new.test/rss'},health),false);
});
