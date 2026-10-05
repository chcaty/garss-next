import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['web/src/publication-state.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {checkPublication,operationApplied}=await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const source={id:'a',title:'来源',category:'技术',feed_url:'https://example.com/rss',description:'',enabled:true};
const base={schema_version:'1.0',sources:[source],repository:{owner:'owner',name:'repo',branch:'main',path:'sources.json'}};
const draft={...base,sources:[{...source,title:'新名称'}]};
test('publication checks report actual public content, pending deployment and failure separately',async()=>{
 const original=globalThis.fetch;
 try{
  for(const stage of ['published','pending','failed','unconfirmed']){
   globalThis.fetch=async url=>{
    const value=String(url);
    const body=value.startsWith('./')?(stage==='published'?draft:base):value.includes('/commits/')?{sha:'revision'}:value.includes('/contents/')?(stage==='unconfirmed'?base:draft):{workflow_runs:[{status:stage==='failed'?'completed':'in_progress',conclusion:stage==='failed'?'failure':null}]};
    return new Response(JSON.stringify(body),{status:200});
   };
   const result=await checkPublication(base,draft);
   assert.equal(result.applied,stage==='published'?1:0);
   assert.equal(result.failed,stage==='failed');
   assert.match(result.message,stage==='published'?/已在公共目录发布/:stage==='failed'?/未成功/:stage==='pending'?/进行中/:/尚未应用/);
  }
 }finally{globalThis.fetch=original;}
});
test('a publication matches requested fields without discarding unrelated edits',()=>{
 assert.equal(operationApplied({id:'a',before:'hash',set:{title:'新名称'}},{...draft,sources:[{...draft.sources[0],category:'远程分类'}]}),true);
 assert.equal(operationApplied({id:'a',before:'hash',remove:true},base),false);
 assert.equal(operationApplied({id:'a',before:'hash',remove:true},{...base,sources:[]}),true);
});
