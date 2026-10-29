import {useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {loadCatalog,type Article,type Source} from './catalog.ts';
import {ReadingLibrary,bookmarkSources,type SavedArticle} from './reading-state.ts';
import {sourceGroups,feedEntries,boardTotals,observation,sourceCondition,isChronologicalFeed,typeLabels,type SourceGroup} from './board-model.ts';
import {Shell} from './shell.tsx';

type Catalog=Awaited<ReturnType<typeof loadCatalog>>;
const time=new Intl.DateTimeFormat('zh-CN',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Shanghai'});
const number=new Intl.NumberFormat('zh-CN',{notation:'compact',maximumFractionDigits:1});
const stamp=(value?:string|null)=>value&&Number.isFinite(Date.parse(value))?time.format(new Date(value)):'暂无记录';
function initialLibrary(){try{return new ReadingLibrary(JSON.parse(localStorage.getItem('garss-reading')??'{}'));}catch{return new ReadingLibrary();}}
function BookmarkIcon({saved}:{saved:boolean}) {return <svg viewBox="0 0 24 24" width="20" height="20" fill={saved?'currentColor':'none'} stroke="currentColor" strokeWidth="1.6" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z"/></svg>;}

export function ResultCard({article,source,fresh,saved,onSave}:{article:Article;source:Source;fresh:boolean;saved:boolean;onSave:()=>void}) {
  const values=observation(article,source.id),kind=article.content_type??'article';
  const metrics:[string,string][]=[];
  for(const [field,label] of [['stars','Star'],['stars_today','今日新增 Star'],['views','播放'],['likes','赞'],['replies','回复'],['heat','热度'],['rating','评分'],['votes','评分人数'],['score','分数'],['answers','回答']] as const){
    const value=values[field];if(typeof value==='number'&&Number.isFinite(value)&&(value>=0||field==='score'))metrics.push([field,`${field==='views'&&kind!=='video'?'阅读':label} ${number.format(value)}`]);
  }
  const duration=values.duration;
  const durationText=typeof duration==='number'?`${Math.floor(duration/60)}:${String(duration%60).padStart(2,'0')}`:duration;
  return <article className={`result-card ${fresh?'is-new':''}`}>
    <a className="card" href={article.url} target="_blank" rel="noopener noreferrer">
      {values.rank?<span className="result-rank" aria-label={`排名 ${values.rank}`}>{values.rank}</span>:null}
      {article.image_url?<div className={`thumb ${kind==='repository'?'av':kind==='item'?'':'wide'}`}><img src={article.image_url} alt="" loading="lazy" referrerPolicy="no-referrer" onError={event=>{event.currentTarget.hidden=true;event.currentTarget.parentElement?.classList.add('noimg');}}/>{kind==='video'&&durationText?<span className="dur">{durationText}</span>:null}</div>:null}
      <div className="body"><div className="card-category"><span>{typeLabels[kind]??'条目'}</span><span className="card-source">{source.title} · {source.category}</span>{fresh?<span className="badge new">新增</span>:null}</div>
        <h3 className="title">{article.title}</h3>
        {article.summary?<p className="desc">{article.summary}</p>:null}
        <div className="meta">
          {values.author?<span>{values.author}</span>:null}{values.language?<span className="chip">{values.language}</span>:null}{values.label?<span className="chip">{values.label}</span>:null}{values.code?<span className="chip">{values.code}</span>:null}
          {metrics.map(([key,label])=><span className="num" key={key}>{label}</span>)}
          <span>{article.date_inferred?'首次发现 ':'发布 '}{stamp(article.published_at)}</span>
        </div>
      </div>
    </a>
    <button className={`bookmark ${saved?'selected':''}`} aria-label={`${saved?'移出':'加入'}收藏：${article.title}`} title={saved?'移出收藏':'加入收藏'} onClick={onSave}><BookmarkIcon saved={saved}/></button>
  </article>;
}
function BoardSection({group,library,onSave,savedOnly}:{group:SourceGroup;library:ReadingLibrary;onSave:(article:Article)=>void;savedOnly:boolean}) {
  const [limit,setLimit]=useState(6);
  const {source,articles,newIds}=group;
  const fresh=articles.filter(article=>newIds.has(article.id)).length;
  return <section className="board-section" aria-labelledby={`board-${source.id}`}>
    <div className="board-section-heading"><div><h2 id={`board-${source.id}`}>{source.title}</h2><p>{source.category} · {savedOnly?'本机收藏':sourceCondition(source)}</p></div><span>{articles.length} 条{fresh?` · 新增 ${fresh}`:''}</span></div>
    <div className="grid">{articles.slice(0,limit).map(article=><ResultCard key={article.id} article={article} source={source} fresh={newIds.has(article.id)} saved={library.saved.has(article.id)} onSave={()=>onSave(article)}/>)}</div>
    {articles.length>limit?<button className="text-button board-section-more" onClick={()=>setLimit(value=>value+12)}>展开本榜单 · 还有 {articles.length-limit} 条</button>:limit>6?<button className="text-button board-section-more" onClick={()=>setLimit(6)}>收起榜单</button>:null}
  </section>;
}
export function Dashboard({initialCatalog}:{initialCatalog?:Catalog}={}) {
  const [catalog,setCatalog]=useState<Catalog|undefined>(initialCatalog),[loading,setLoading]=useState(!initialCatalog),[error,setError]=useState(''),[attempt,retry]=useState(0);
  const [library]=useState(initialLibrary),[,renderLibrary]=useState(0),[storageError,setStorageError]=useState(false);
  const [scope,setScope]=useState('all'),[query,setQuery]=useState(''),[source,setSource]=useState(()=>new URLSearchParams(location.search).get('source')??''),[category,setCategory]=useState(''),[kind,setKind]=useState('all'),[onlyNew,setOnlyNew]=useState(false),[compact,setCompact]=useState(false),[limit,setLimit]=useState(12);
  const [view,setView]=useState<'boards'|'feed'>('boards');
  const [filtersOpen,setFiltersOpen]=useState(false);
  const [removed,setRemoved]=useState<SavedArticle>(),[feedback,setFeedback]=useState('');
  useEffect(()=>{
    if(initialCatalog)return;
    let alive=true;setLoading(true);setError('');
    void loadCatalog(location.href).then(next=>{if(alive){library.reconcile(next.articles,next.sources);try{localStorage.setItem('garss-reading',JSON.stringify(library));}catch{setStorageError(true);}setCatalog(next);renderLibrary(value=>value+1);}}).catch(reason=>{if(alive)setError(reason instanceof Error?reason.message:'目录读取失败');}).finally(()=>{if(alive)setLoading(false);});
    return()=>{alive=false;};
  },[initialCatalog,attempt,library]);
  useEffect(()=>{if(!feedback)return;const timer=setTimeout(()=>{setFeedback('');setRemoved(undefined);},8000);return()=>clearTimeout(timer);},[feedback]);
  const persist=()=>{try{localStorage.setItem('garss-reading',JSON.stringify(library));setStorageError(false);}catch{setStorageError(true);}renderLibrary(value=>value+1);};
  const save=(article:Article)=>{const old=library.bookmarks.get(article.id);library.toggleSaved(article,catalog?.sources??[]);setRemoved(old);setFeedback(old?'已移出收藏':'已加入收藏');persist();};
  const saved=scope==='saved';
  const sources=saved?bookmarkSources([...library.bookmarks.values()]).map(item=>({...item,baseline_known:false,new_ids:[]})):(catalog?.sources??[]).filter(item=>item.status!=='error'&&item.article_count!==0);
  const articles=saved?[...library.bookmarks.values()]:catalog?.articles??[];
  const canonical=catalog?.sourceAliases[source]??source;
  const selected=sources.some(item=>item.id===canonical)?canonical:'';
  const selectedSource=sources.find(item=>item.id===selected);
  const groups=sourceGroups(articles,sources,{query,source:selected,category,kind,onlyNew:!saved&&onlyNew,savedOnly:saved});
  const entries=feedEntries(groups,saved);
  const sourceOptions=saved||view==='boards'?sources:sources.filter(isChronologicalFeed);
  const totals=boardTotals(groups);
  const categories=[...new Set(sourceOptions.map(item=>item.category))].sort();
  const reset=()=>{setQuery('');setSource('');setCategory('');setKind('all');setOnlyNew(false);setLimit(12);};
  const canClear=!!(query||source||category||kind!=='all'||onlyNew);
  return <><div className="board-shell"><Shell current="reader"/></div><main className={`wrap dashboard ${compact?'compact':''}`}>
    <div className="board-heading"><div><h1>{saved?'我的收藏':'榜单'}</h1></div><div className="update-status"><span>北京时间 {stamp(catalog?.generatedAt)} 更新</span><a href="./sync.html">采集记录</a></div></div>
    <div className="board-overview"><div className="scope-tabs" role="group" aria-label="内容范围">{[['all','全部榜单'],['saved','我的收藏']].map(([value,label])=><button key={value} aria-pressed={scope===value} onClick={()=>{setScope(value);reset();}}>{label}</button>)}</div><p role="status">{totals.count} 条内容 · {groups.length} 个榜单{!saved?` · 新增 ${groups.some(group=>group.source.baseline_known)?totals.fresh:'—'}`:''}</p></div>
    {!saved?<div className="view-tabs" role="group" aria-label="浏览方式"><button aria-pressed={view==='boards'} onClick={()=>{setView('boards');setLimit(12);}}>榜单</button><button aria-pressed={view==='feed'} onClick={()=>{setView('feed');if(selectedSource&&!isChronologicalFeed(selectedSource))setSource('');setLimit(12);}}>信息流</button></div>:null}
    <div className="board-tools"><label className="board-search"><span className="visually-hidden">搜索内容</span><input type="search" placeholder="搜索标题、摘要或榜单" value={query} onChange={event=>{setQuery(event.target.value);setLimit(12);}}/></label>
      <div className="board-filter-panel" data-open={filtersOpen}><button className="filter-toggle" aria-expanded={filtersOpen} onClick={()=>setFiltersOpen(value=>!value)}>筛选</button><div className="board-filter-fields">
      <label>榜单<select aria-label="榜单" value={selected} onChange={event=>{setSource(event.target.value);setLimit(12);}}><option value="">全部榜单</option>{sourceOptions.map(item=><option key={item.id} value={item.id}>{item.title}</option>)}</select></label>
      <label>分类<select aria-label="分类" value={category} onChange={event=>{setCategory(event.target.value);setLimit(12);}}><option value="">全部分类</option>{categories.map(item=><option key={item}>{item}</option>)}</select></label>
      <label>类型<select aria-label="类型" value={kind} onChange={event=>{setKind(event.target.value);setLimit(12);}}><option value="all">全部类型</option>{Object.entries(typeLabels).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label></div></div>
    </div>
    <div className="view-options">{!saved?<label><input type="checkbox" checked={onlyNew} onChange={event=>{setOnlyNew(event.target.checked);setLimit(12);}}/>只看新增</label>:null}<label><input type="checkbox" checked={compact} onChange={event=>setCompact(event.target.checked)}/>紧凑视图</label>{canClear?<button className="text-button" onClick={reset}>清除筛选</button>:null}</div>
    {loading?<p className="board-message" role="status">正在读取最新目录…</p>:null}
    {error?<div className="board-message error" role="alert"><strong>暂时无法更新目录</strong><p>{error}。已取得的内容和本机收藏仍可查看。</p><button className="button" onClick={()=>retry(value=>value+1)}>重新加载</button>{!saved?<button className="button" onClick={()=>{setScope('saved');reset();}}>查看本机收藏</button>:null}</div>:null}
    {storageError?<p className="board-message error" role="alert">浏览器保存失败，当前收藏修改只在本次会话有效。</p>:null}
    {saved&&library.missingBookmarks?<p className="board-message" role="status">{library.missingBookmarks} 条旧收藏暂无内容备份；内容仍在目录中时会自动补齐。</p>:null}
    <div id="results" className={view==='feed'||saved?'stream-grid':'board-list'} aria-busy={loading}>{saved||view==='feed'?entries.slice(0,limit).map(entry=><ResultCard key={`${scope}-${entry.article.id}`} article={entry.article} source={entry.source} fresh={entry.fresh} saved={library.saved.has(entry.article.id)} onSave={()=>save(entry.article)}/>):groups.slice(0,limit).map(group=><BoardSection key={`${scope}-${group.source.id}`} group={group} savedOnly={saved} library={library} onSave={save}/>)}</div>
    {!loading&&!(saved||view==='feed'?entries.length:groups.length)?<div className="board-empty" role="status"><h2>{saved&&!canClear?'暂无收藏':'没有符合条件的内容'}</h2>{canClear?<button className="button" onClick={reset}>清除筛选</button>:saved?<button className="button" onClick={()=>setScope('all')}>返回榜单</button>:null}</div>:null}
    {(saved||view==='feed'?entries.length:groups.length)>limit?<button className="button more-items" onClick={()=>setLimit(value=>value+12)}>显示更多{view==='boards'&&!saved?'榜单':'内容'} · 还有 {(saved||view==='feed'?entries.length:groups.length)-limit} 条</button>:null}
    <footer><span>拾阅 · 挑选信息，慢慢阅读</span><span>RSS / JSON / 网页 · <a href="./sources.html">管理公共来源</a> · <a href="./api/index.json">开放数据</a></span></footer>
  </main>{feedback?<div className="board-feedback" role="status"><span>{feedback}</span>{removed?<button className="text-button" onClick={()=>{library.restoreSaved(removed);persist();setRemoved(undefined);setFeedback('已恢复收藏');}}>撤销</button>:null}</div>:null}</>;
}
createRoot(document.getElementById('root')!).render(<Dashboard/>);
