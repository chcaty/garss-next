import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['web/src/board-model.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {sourceGroups,feedEntries,boardTotals}=await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const filters={query:'',source:'',category:'',kind:'all',onlyNew:false};
const source={id:'a',title:'Alpha',description:'',category:'Tech',enabled:true,feed_url:'https://example.com/rss',status:'ok',baseline_known:true,new_ids:['shared']};
const article={id:'shared',source_id:'a',source_ids:['a','b','b'],title:'Shared topic',url:'https://example.com/topic',published_at:'2026-10-29T00:00:00Z',content_type:'topic'};
test('board totals and per-source new filters share the same unique IDs',()=>{
 const groups=sourceGroups([article],[source,{...source,id:'b'}],filters);
 assert.equal(groups.length,2);assert.deepEqual(boardTotals(groups),{count:1,fresh:1});
 const stream=feedEntries(groups);
 assert.equal(stream.length,1);assert.equal(stream[0].source.id,'a');assert.equal(stream[0].fresh,true);
 assert.deepEqual(boardTotals(sourceGroups([article],[source],{...filters,onlyNew:true})),{count:1,fresh:1});
 assert.equal(sourceGroups([article],[{...source,status:'error'}],{...filters,onlyNew:true}).length,0);
 assert.equal(sourceGroups([article],[{...source,baseline_known:false}],{...filters,onlyNew:true}).length,0);
 assert.equal(sourceGroups([article],[{...source,status:'error'}],filters).length,0);
 assert.equal(sourceGroups([article],[{...source,status:'error'}],{...filters,savedOnly:true}).length,1);
});
test('feed entries are unique and ordered by newest publication time',()=>{
 const older={...article,id:'older',published_at:'2026-10-28T00:00:00Z'};
 const entries=feedEntries(sourceGroups([older,article],[source,{...source,id:'b',title:'Beta'}],filters));
 assert.deepEqual(entries.map(entry=>entry.article.id),['shared','older']);
});
test('榜单保留来源排名，信息流独立按发布时间排序',()=>{
 const rankedSource={...source,adapter:'bilibili'};
 const rssSource={...source,id:'b',title:'RSS',adapter:'rss'};
 const newest={...article,id:'newest',published_at:'2026-10-29T02:00:00Z',observations:{a:{rank:2}}};
 const rankedFirst={...article,id:'ranked-first',published_at:'2026-10-28T00:00:00Z',observations:{a:{rank:1}}};
 const groups=sourceGroups([newest,rankedFirst],[rankedSource,rssSource],filters);
 assert.deepEqual(groups[0].articles.map(item=>item.id),['ranked-first','newest']);
 assert.deepEqual(feedEntries(groups).map(item=>item.article.id),['newest','ranked-first']);
 assert.ok(feedEntries(groups).every(item=>item.source.id==='b'));
 assert.deepEqual(feedEntries([groups[0]]),[]);
});
test('source, category, type and search combine without mutating input or global rank',()=>{
 const prior=structuredClone(article);
 assert.equal(sourceGroups([article],[source],{...filters,kind:'video'}).length,0);
 assert.equal(sourceGroups([article],[source],{...filters,query:'alpha',source:'a',category:'Tech',kind:'topic'}).length,1);
 assert.equal(sourceGroups([article],[source],{...filters,source:'missing'}).length,0);
 assert.deepEqual(article,prior);
});
