import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {createRequire} from 'node:module';
const compiled=await build({entryPoints:['web/src/source-quality.tsx'],bundle:true,write:false,format:'cjs',platform:'node',external:['react','react-dom','react-dom/*']});
const module={exports:{}};
new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),module,module.exports);
const {CandidatePreview,SourceQuality,UpstreamFailures}=module.exports;
const render=(component,props)=>renderToStaticMarkup(React.createElement(component,props));
test('candidate preview preserves stale warning and rejects unsafe samples',()=>{
 const html=render(CandidatePreview,{source:{title:'Sample',validation_status:'error',validation_error:'HTTP 404',recent_articles:[{title:'Unsafe',url:'javascript:alert(1)'},{title:'Good',url:'https://example.com/post',published_at:'2026-10-01T01:00:00Z'}]}});
 assert.match(html,/最近复查失败/);assert.match(html,/Good/);assert.doesNotMatch(html,/Unsafe|javascript:/);assert.match(html,/noopener noreferrer/);
});
test('expired candidate and old v1 candidate have explicit incomplete/expired states',()=>{
 assert.match(render(CandidatePreview,{source:{title:'Old',expires_at:'2026-10-01T00:00:00Z'},now:Date.parse('2026-10-13T00:00:00Z')}),/验证已过期/);
 assert.match(render(CandidatePreview,{source:{title:'Legacy'}}),/旧候选尚无内容预览/);
});
test('zero-new source remains a normal low-frequency source, with separate no-valid warning',()=>{
 assert.match(render(SourceQuality,{health:{raw_entry_count:4,valid_article_count:4,new_article_count:0}}),/低频更新仍属正常/);
 const empty=render(SourceQuality,{health:{raw_entry_count:4,valid_article_count:0,new_article_count:0,drop_reasons:{missing_date:4}}});
 assert.match(empty,/暂无可读文章/);assert.match(empty,/缺少日期/);assert.doesNotMatch(empty,/低频更新仍属正常/);
});

test('shared upstream diagnosis reports observations without declaring original publishers dead',()=>{
 const html=render(UpstreamFailures,{groups:[{host:'rsshub.example',http_status:404,count:21}],onSelect:()=>{}});
 assert.match(html,/21 个来源/);assert.match(html,/HTTP 404/);assert.match(html,/不表示每个原站都已停更/);
 assert.equal(render(UpstreamFailures,{groups:[{host:'one.example',count:1}],onSelect:()=>{}}),'');
});
