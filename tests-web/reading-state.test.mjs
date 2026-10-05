import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['web/src/reading-state.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {ReadingLibrary,bookmarkSources}=await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const article={id:'current',title:'收藏文章',url:'https://example.com/post',source_id:'a',source_ids:['a'],published_at:'2026-10-03T00:00:00Z',summary:'离线摘要',legacy_ids:['old']};
const source={id:'a',title:'原来源',category:'技术',feed_url:'https://example.com/rss',description:'',enabled:true};
test('bookmarks retain content and categories after the public catalog expires',()=>{
 const library=new ReadingLibrary();library.toggleSaved(article,[source]);
 const restarted=new ReadingLibrary(JSON.parse(JSON.stringify(library)));restarted.reconcile([],[]);
 assert.equal(restarted.bookmarks.get('current').summary,'离线摘要');
 assert.equal(bookmarkSources([...restarted.bookmarks.values()])[0].category,'技术');
 restarted.reconcile([article],[{...source,category:'新分类'}]);
 assert.equal(restarted.bookmarks.get('current').saved_sources[0].category,'技术');
 restarted.toggleSaved(article,[]);assert.equal(restarted.bookmarks.size,0);
});
test('legacy read and bookmark IDs migrate, and marking unread survives reconciliation',()=>{
 const library=new ReadingLibrary({read:['old'],saved:['old','missing']});library.reconcile([article],[source]);
 assert.equal(library.read.has('current'),true);assert.deepEqual([...library.saved],['missing','current']);assert.equal(library.missingBookmarks,1);
 library.markUnread(article);library.reconcile([article],[source]);assert.equal(library.read.has('current'),false);
});
test('corrupt individual bookmarks do not discard valid local content',()=>{
 const library=new ReadingLibrary({bookmarks:[null,{...article,url:'javascript:bad'}, {...article,saved_sources:[source],source_ids:42}]});
 assert.equal(library.bookmarks.size,1);assert.equal(library.bookmarks.get('current').source_ids,undefined);
});

test('undo restores an expired snapshot and preserves other saves and later changes',()=>{
 const library=new ReadingLibrary();library.toggleSaved(article,[source]);
 const removed=library.bookmarks.get(article.id);library.toggleSaved(article,[]);
 const other={...article,id:'other'};library.toggleSaved(other,[source]);library.reconcile([],[]);
 library.restoreSaved(removed);
 assert.equal(library.bookmarks.get(article.id).summary,'离线摘要');
 assert.equal(library.bookmarks.get(article.id).saved_sources[0].category,'技术');
 assert.equal(library.bookmarks.has('other'),true);
 library.toggleSaved(article,[]);library.toggleSaved({...article,summary:'后来重新保存'},[]);library.restoreSaved(removed);
 assert.equal(library.bookmarks.get(article.id).summary,'后来重新保存');
});
