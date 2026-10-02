import test from 'node:test';
import assert from 'node:assert/strict';
import { transform } from 'esbuild';
import {readFile} from 'node:fs/promises';
const code = await transform(await readFile(new URL('../web/src/catalog.ts', import.meta.url), 'utf8'), {loader:'ts', format:'esm'});
const {filterArticles, validateConfig} = await import(`data:text/javascript;base64,${Buffer.from(code.code).toString('base64')}`);
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
