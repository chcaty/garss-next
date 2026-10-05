import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['web/src/source-manager-model.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {rebaseDraft,archived,draftConflicts}=await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
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

test('rebase exposes same-field conflicts and remote deletion before choosing local values',()=>{
 const base=config([a]),local=config([{...a,title:'Local'}]),remote=config([{...a,title:'Remote'}]);
 assert.deepEqual(draftConflicts(base,local,remote).map(value=>[value.key,value.local,value.remote]),[['title','Local','Remote']]);
 assert.equal(rebaseDraft(base,local,remote).sources[0].title,'Local');
 assert.equal(draftConflicts(base,local,config([]))[0].key,'source');
 assert.deepEqual(draftConflicts(base,config([]),config([])),[]);
});
