import test from 'node:test';
import assert from 'node:assert/strict';
import {transform} from 'esbuild';
import {readFile} from 'node:fs/promises';
const code = await transform(await readFile(new URL('../web/src/source-management.ts', import.meta.url),'utf8'),{loader:'ts',format:'esm'});
const {changes,duplicateUrls,matchesSource} = await import(`data:text/javascript;base64,${Buffer.from(code.code).toString('base64')}`);
const source = {id:'a',title:'来源 A',category:'技术',description:'',feed_url:'https://example.com/feed',enabled:true};
test('review retains deletions and distinguishes added, edited and collection-only updates', () => {
  assert.deepEqual(changes([source],[{...source,status:'error',article_count:3}]),[]);
  const diff = changes([source,{...source,id:'b'}],[{...source,enabled:false},{...source,id:'c'}]);
  assert.deepEqual(diff.map(item => [item.id,item.kind]),[['a','修改'],['c','新增'],['b','删除']]);
});
test('duplicate detection and URL/category search find management problems', () => {
  assert.deepEqual([...duplicateUrls([source,{...source,id:'b'},{...source,id:'c',feed_url:'https://other.test/rss'}])],[source.feed_url]);
  assert.equal(matchesSource(source,' EXAMPLE.COM ','技术'),true);
  assert.equal(matchesSource(source,'','新闻'),false);
});

test('duplicate detection ignores fragments and domain case but keeps distinct feed paths', () => {
 const other={...source,id:'b',feed_url:'https://EXAMPLE.com/feed#comments'};
 assert.deepEqual([...duplicateUrls([source,other,{...source,id:'c',feed_url:'https://example.com/news/feed'}])],[source.feed_url,other.feed_url]);
});
