import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {renderToStaticMarkup} from 'react-dom/server';

const require = createRequire(import.meta.url);
const source = {id:'a',title:'来源 A',description:'',category:'Tech',feed_url:'https://example.com/rss',enabled:true,status:'error',article_count:3};
const fixtures = {
  ready: {
    'meta.json':{generated_at:'2026-10-05T00:00:00Z'},
    'feeds.json':{feeds:[source,{...source,id:'b',title:'来源 B',status:'ok'}]},
    'source-state.json':{sources:{a:{status:'error',last_error:'Timed out',last_checked_at:'2026-10-05T00:00:00Z'}}},
    'sync.json':{runs:[{generated_at:'2026-10-05T00:00:00Z',duration_seconds:12,checked:2,succeeded:1,failed:1,archived:0,article_count:5,workflow_run_id:'123'}]},
    'source-discovery.json':{candidates:[{}],directory_errors:[{directory:'Example',error:'Unavailable'}]},
  },
  unknown: {'feeds.json':{feeds:[source]}},
  noFeeds: {},
};

// Replace only transport and mounting. Render the real component tree with React.
const result = await build({
  entryPoints:['web/src/sync-page.tsx'],bundle:true,write:false,platform:'node',format:'cjs',jsx:'automatic',
  external:['react','react-dom','react-dom/*'],
  plugins:[{name:'sync-render',setup(builder){
    builder.onLoad({filter:/[\\/]use-published\.ts$/},()=>({contents:'export const usePublished = globalThis.__syncPublished;',loader:'ts'}));
    builder.onLoad({filter:/[\\/]theme\.ts$/},()=>({contents:"export const currentTheme = () => 'system'; export const setTheme = () => {};",loader:'ts'}));
  }}],
});
const renderFixture = (documents) => {
  globalThis.__syncPublished = url => ({value:documents[url.split('/').at(-1)],loading:false,error:!documents[url.split('/').at(-1)],reload:()=>{}});
  const module = {exports:{}};
  new Function('require','module','exports',result.outputFiles[0].text)(require,module,module.exports);
  const markup = renderToStaticMarkup(require('react').createElement(module.exports.Sync));
  delete globalThis.__syncPublished;
  return markup;
};

const expected = JSON.parse(await readFile(new URL('./fixtures/sync-markup.json', import.meta.url),'utf8'));
for (const [name,documents] of Object.entries(fixtures)) {
  test(`sync rendering retains ${name} content, semantics and DOM structure`,()=>{
    const markup=renderFixture(documents);
    assert.equal(createHash('sha256').update(markup).digest('hex'),expected[name]);
    assert.match(markup,/同步记录/);
    if(name==='ready') assert.match(markup,/actions\/runs\/123/);
    if(name==='unknown') assert.match(markup,/数量暂时未知/);
  });
}
