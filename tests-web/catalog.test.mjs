import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import {readFile} from 'node:fs/promises';
const code = await build({entryPoints:['web/src/catalog.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {filterArticles, validateConfig, adapters} = await import(`data:text/javascript;base64,${Buffer.from(code.outputFiles[0].text).toString('base64')}`);

test('named adapters require their registered endpoint and keep legacy RSS valid',()=>{
  const source={id:'direct',title:'Direct',category:'Tech',description:'',enabled:true,adapter:'v2ex',feed_url:adapters.v2ex.url};
  const config={schema_version:'1.0',repository:{owner:'owner',name:'repo',branch:'main',path:'sources.json'},sources:[source]};
  assert.doesNotThrow(()=>validateConfig(config));
  assert.throws(()=>validateConfig({...config,sources:[{...source,feed_url:'https://example.com/not-v2ex'}]}));
  assert.throws(()=>validateConfig({...config,sources:[{...source,adapter:'unknown'}]}));
});
test('shared articles remain visible under every source', () => {
  const articles = [{id:'one',title:'Article',summary:'Summary',source_id:'a',source_ids:['a','b'],url:'https://example.com/post',published_at:'2026-10-01T00:00:00Z'}];
  assert.equal(filterArticles(articles, '', 'b').length, 1);
  assert.equal(filterArticles(articles, 'source b', '', [{id:'b',title:'Source B'}]).length, 1);
});
test('source validation permits explicit disable and rejects unsafe addresses', () => {
  const config = {schema_version:'1.0',repository:{owner:'owner',name:'repo',branch:'main',path:'sources.json'},sources:[{id:'a',title:'A',description:'',category:'Tech',feed_url:'https://example.com/feed',enabled:false}]};
  assert.doesNotThrow(() => validateConfig(config));
  config.sources[0].feed_url='javascript:alert(1)';
  assert.throws(() => validateConfig(config));
});
