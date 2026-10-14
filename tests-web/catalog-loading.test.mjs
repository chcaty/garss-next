import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['web/src/catalog.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {loadCatalog}=await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const base='https://example.test/reader/';
const generated_at='2026-10-13T04:00:00Z';
function fixture() {
 const data={
  'feeds.json':{generated_at,feeds:[{id:'a',title:'A',enabled:true}],source_aliases:{}},
  'articles.json':{generated_at,articles:[{id:'a',url:'https://example.test/post'}]},
 };
 const bodies=Object.fromEntries(Object.entries(data).map(([key,value])=>[key,JSON.stringify(value)]));
 const manifest={snapshot_id:'one',generated_at,files:Object.fromEntries(Object.entries(bodies).map(([name,body])=>[name,{bytes:Buffer.byteLength(body),sha256:createHash('sha256').update(body).digest('hex')}]))};
 const meta={snapshot_id:'one',generated_at,snapshot_endpoint:'snapshots/one/manifest.json'};
 const calls=[];
 const fetcher=async url=>{url=String(url);calls.push(url);if(url.endsWith('meta.json'))return Response.json(meta);if(url.endsWith('manifest.json'))return Response.json(manifest);return new Response(bodies[url.split('/').at(-1)]);};
 return {bodies,manifest,meta,calls,fetcher};
}
test('same validated snapshot only requests metadata and manifest; cloned/unverified cache never skips checks',async()=>{
 const f=fixture();const prior=globalThis.fetch;globalThis.fetch=f.fetcher;
 try {
  const catalog=await loadCatalog(base);assert.equal(f.calls.length,4);
  assert.equal(await loadCatalog(base,catalog),catalog);assert.equal(f.calls.length,6);
  await loadCatalog(base,{...catalog});assert.equal(f.calls.length,10);
 }finally{globalThis.fetch=prior;}
});
test('changed manifest cannot reuse an old snapshot identity and checksum failure leaves old catalog usable',async()=>{
 const f=fixture();const prior=globalThis.fetch;globalThis.fetch=f.fetcher;
 try {
  const catalog=await loadCatalog(base);
  f.manifest.files['articles.json'].sha256='0'.repeat(64);
  await assert.rejects(loadCatalog(base,catalog),/校验失败/);
  assert.equal(catalog.articles.length,1);assert.equal(f.calls.length,8);
 }finally{globalThis.fetch=prior;}
});
test('foreign or escaped manifest addresses fail before fetching them',async()=>{
 for(const endpoint of ['https://foreign.test/manifest.json','../../../manifest.json']){
  const f=fixture();f.meta.snapshot_endpoint=endpoint;const prior=globalThis.fetch;globalThis.fetch=f.fetcher;
  try {await assert.rejects(loadCatalog(base),/地址不合法/);assert.equal(f.calls.length,1);}finally{globalThis.fetch=prior;}
 }
});
test('mismatched metadata and manifest never reuse previous data as fresh',async()=>{
 const f=fixture();const prior=globalThis.fetch;globalThis.fetch=f.fetcher;
 try {const catalog=await loadCatalog(base);f.meta.snapshot_id='two';await assert.rejects(loadCatalog(base,catalog),/版本变化/);}finally{globalThis.fetch=prior;}
});
