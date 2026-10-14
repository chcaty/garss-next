// Reproducible CPU/model benchmark; this is not a browser or phone frame-time measurement.
// node tools/benchmark_reading.mjs /path/to/articles.json /path/to/feeds.json
import {readFile} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const [articleFile,feedFile]=process.argv.slice(2);
if(!articleFile||!feedFile)throw Error('Supply pinned articles.json and feeds.json paths');
async function module(path){const result=await build({entryPoints:[path],bundle:true,write:false,format:'esm',platform:'node'});return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);}
const [{ReadingIndex},{filterArticles},{readingSelection}]=await Promise.all([module('web/src/reading-index.ts'),module('web/src/catalog.ts'),module('web/src/reading-filter.ts')]);
const raw=await readFile(articleFile);const document=JSON.parse(raw);const articles=document.articles;const sources=JSON.parse(await readFile(feedFile,'utf8')).feeds;
const now=Date.parse(document.generated_at),read=new Set(articles.filter((_,i)=>i%3===0).map(article=>article.id));
const filters=[{query:''},{query:'技术'},{query:'python'},{query:'flutter'},{query:'AI',window:'week'},{source:sources[0].id},{category:sources.find(source=>source.category)?.category,unreadOnly:true},{query:'a',oldest:true}];
function before(filter){return filterArticles(readingSelection(articles,sources,filter.category??'',filter.window??'all',now),filter.query??'',filter.source??'',sources).filter(article=>!filter.unreadOnly||!read.has(article.id)).sort((a,b)=>(Date.parse(b.published_at)-Date.parse(a.published_at))*(filter.oldest?-1:1));}
const start=performance.now();const index=new ReadingIndex(articles,sources);const buildMs=performance.now()-start;
const after=filter=>index.select({...filter,now,read});
for(const filter of filters)assert.deepEqual(after(filter).map(x=>x.id),before(filter).map(x=>x.id));
function measure(fn){const times=[];for(let i=0;i<20;i++)for(const filter of filters){const start=performance.now();fn(filter);if(i>=3)times.push(performance.now()-start);}times.sort((a,b)=>a-b);return {medianMs:times[Math.floor(times.length/2)],p95Ms:times[Math.floor(times.length*.95)],samples:times.length};}
const baseline=measure(before),indexed=measure(after);
console.log(JSON.stringify({runtime:process.version,articles:articles.length,uncompressedBytes:raw.length,sources:sources.length,generatedAt:document.generated_at,indexBuildMs:buildMs,baseline,indexed,medianSpeedup:baseline.medianMs/indexed.medianMs,identicalResults:true},null,2));
