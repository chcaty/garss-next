import {currentTheme,setTheme,type Theme} from './theme.ts';
import {loadCatalog, filterArticles, sourceIds, type Article, type Source} from './catalog.ts';
const byId = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const create = (tag: string, text = '', className = '') => {
  const element = document.createElement(tag); element.textContent = text; element.className = className; return element;
};
let sources: Source[] = [], articles: Article[] = [], source = new URLSearchParams(location.search).get('source') ?? '', page = 1;
let mode='all', focusIndex=0, focusQueue:Article[]=[];
const readIds=new Set<string>(), savedIds=new Set<string>();
let storageAvailable=true;
try { const saved=JSON.parse(localStorage.getItem('garss-reading') ?? '{}');for(const id of saved.read ?? [])if(typeof id==='string')readIds.add(id);for(const id of saved.saved ?? [])if(typeof id==='string')savedIds.add(id); }catch{storageAvailable=false;}
function persistReading(){ try {localStorage.setItem('garss-reading',JSON.stringify({read:[...readIds].slice(-10000),saved:[...savedIds].slice(-10000)}));storageAvailable=true;}catch{storageAvailable=false;} }
function toggleSaved(article:Article){savedIds.has(article.id)?savedIds.delete(article.id):savedIds.add(article.id);persistReading();}
function matchingArticles(){ return filterArticles(articles,byId<HTMLInputElement>('article-search').value,source,sources).filter(article=>mode==='saved'?savedIds.has(article.id):mode==='unread'?!readIds.has(article.id):true).sort((a,b)=>(Date.parse(b.published_at)-Date.parse(a.published_at))*(byId<HTMLSelectElement>('article-sort').value==='oldest'?-1:1)); }
function showFocus(){
  const article=focusQueue[focusIndex];if(!article)return;
  readIds.add(article.id);persistReading();
  byId('focus-title').textContent=article.title;
  byId('focus-meta').textContent=sourceIds(article).map(id=>sources.find(item=>item.id===id)?.title??id).join(' · ')+' · '+date.format(new Date(article.published_at));
  const document=new DOMParser().parseFromString(article.summary??'', 'text/html');
  document.querySelectorAll('script,style').forEach(node=>node.remove());
  document.querySelectorAll('br').forEach(node=>node.replaceWith('\n'));
  document.querySelectorAll('p,li,div').forEach(node=>node.append('\n\n'));
  const summary=document.body.textContent?.trim()??'';
  byId('focus-summary').textContent=summary||'这个来源没有提供文章摘要。';
  byId('focus-hint').textContent=storageAvailable?'内容来自 RSS，完整内容请查看原文。':'浏览器无法保存阅读进度；本次会话仍可继续阅读。';
  byId<HTMLAnchorElement>('focus-original').href=article.url;
  byId('focus-save').textContent=savedIds.has(article.id)?'移出稍后读':'加入稍后读';
  byId('focus-position').textContent=`${focusIndex+1} / ${focusQueue.length}`;
  byId<HTMLButtonElement>('focus-previous').disabled=focusIndex===0;
  byId<HTMLButtonElement>('focus-next').disabled=focusIndex===focusQueue.length-1;
  byId<HTMLDialogElement>('focus-reader').scrollTop=0;
}
const sourceCounts = new Map<string, number>();
const date = new Intl.DateTimeFormat('zh-CN', {month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Shanghai'});
function renderSources() {
  const query = byId<HTMLInputElement>('source-search').value.trim().toLowerCase();
  byId('source-list').replaceChildren();
  for (const item of [{id: '', title: '全部来源'}, ...sources.filter(item => `${item.title} ${item.category}`.toLowerCase().includes(query))]) {
    const button = create('button', '', 'source-button') as HTMLButtonElement;
    button.type = 'button'; button.setAttribute('aria-pressed', String(source === item.id));
    button.append(create('span', item.title), create('span', String(item.id ? sourceCounts.get(item.id) ?? 0 : articles.length)));
    button.onclick = () => { source = item.id; page = 1; renderSources(); renderArticles(); };
    byId('source-list').append(button);
  }
}
function renderArticles() {
  const filtered = matchingArticles();
  const pages = Math.max(1, Math.ceil(filtered.length / 30)); page = Math.min(page, pages);
  byId('stream-title').textContent = sources.find(item => item.id === source)?.title ?? '全部文章';
  byId('result-count').textContent = `${filtered.length} 篇文章`;
  byId('clear-filters').hidden = !source && !byId<HTMLInputElement>('article-search').value && mode==='all';
  byId('articles').replaceChildren();
  for (const article of filtered.slice((page - 1) * 30, page * 30)) {
    const row = create('article', '', `article-row${readIds.has(article.id)?' is-read':''}`), content = create('div'), meta = create('div', '', 'article-meta');
    meta.append(create('span', sourceIds(article).map(id => sources.find(item => item.id === id)?.title ?? id).join(' · '), 'article-source'), create('time', `${article.date_inferred ? '首次发现 ' : ''}${date.format(new Date(article.published_at))}`));
    const heading=create('h3'), link=create('button',article.title,'article-title') as HTMLButtonElement;
    link.type='button';link.onclick=()=>{focusQueue=filtered;focusIndex=filtered.findIndex(item=>item.id===article.id);showFocus();byId<HTMLDialogElement>('focus-reader').showModal();};heading.append(link);
    const save=create('button',savedIds.has(article.id)?'已收藏':'稍后读','button save-article') as HTMLButtonElement;
    save.type='button';save.setAttribute('aria-label',`${savedIds.has(article.id)?'移出':'加入'}稍后读：${article.title}`);save.setAttribute('aria-pressed',String(savedIds.has(article.id)));save.onclick=()=>{toggleSaved(article);renderArticles();};
    content.append(meta,heading);row.append(content,save);byId('articles').append(row);
  }
  byId('reader-message').hidden = filtered.length > 0;
  byId('reader-message').replaceChildren(create('strong', '没有匹配的文章'), create('p', '调整关键词或来源，或清除筛选。'));
  byId('page-indicator').textContent = `第 ${page} / ${pages} 页`;
  byId<HTMLButtonElement>('previous-page').disabled = page <= 1;
  byId<HTMLButtonElement>('next-page').disabled = page >= pages;
}
async function load() {
  byId('articles').setAttribute('aria-busy', 'true'); byId('retry-load').hidden = true;
  try {
    const data = await loadCatalog(location.href); articles = data.articles;
    sourceCounts.clear();
    for (const article of articles) for (const id of new Set(sourceIds(article))) sourceCounts.set(id, (sourceCounts.get(id) ?? 0) + 1);
    sources = data.sources.filter(item => (sourceCounts.get(item.id) ?? 0) > 0);
    source = data.sourceAliases[source] ?? source;
    if (source && !sources.some(item => item.id === source)) source = '';
    byId('edition-date').textContent = new Intl.DateTimeFormat('zh-CN', {dateStyle: 'long', timeZone: 'Asia/Shanghai'}).format(new Date(data.generatedAt));
    byId('snapshot-info').textContent = `最近同步 ${date.format(new Date(data.generatedAt))} · ${sources.length} 个有文章的来源`;
    byId('source-count').textContent = String(sources.length); renderSources(); renderArticles();
  } catch {
    byId('reader-message').hidden = false; byId('reader-message').textContent = '读取失败，请检查网络后重试'; byId('retry-load').hidden = false;
  } finally { byId('articles').setAttribute('aria-busy', 'false'); }
}
byId('source-search').oninput = renderSources;
byId('article-search').oninput = () => { page = 1; renderArticles(); };
byId('article-sort').onchange = () => { page = 1; renderArticles(); };
byId('clear-filters').onclick = () => { source = ''; mode='all';updateModes();page = 1; byId<HTMLInputElement>('article-search').value = ''; renderSources(); renderArticles(); };
byId('previous-page').onclick = () => { page--; renderArticles(); byId('stream-title').scrollIntoView(); };
byId('next-page').onclick = () => { page++; renderArticles(); byId('stream-title').scrollIntoView(); };
byId('retry-load').onclick = load;
void load();

function updateModes(){document.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.mode===mode)));}
document.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach(button=>{button.onclick=()=>{mode=button.dataset.mode??'all';page=1;updateModes();renderArticles();};});
byId('focus-close').onclick=()=>byId<HTMLDialogElement>('focus-reader').close();
byId<HTMLDialogElement>('focus-reader').onclose=()=>{renderArticles();byId('stream-title').tabIndex=-1;byId('stream-title').focus({preventScroll:true});};
byId('focus-save').onclick=()=>{toggleSaved(focusQueue[focusIndex]);showFocus();};
byId('focus-previous').onclick=()=>{focusIndex--;showFocus();};
byId('focus-next').onclick=()=>{focusIndex++;showFocus();};
const icons:Record<Theme,string>={system:'<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',light:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.4 1.4m11.2 11.2L19 19M5 19l1.4-1.4M17.6 6.4 19 5"/>',dark:'<path d="M20 14.2A8.6 8.6 0 0 1 9.8 4a8.6 8.6 0 1 0 10.2 10.2Z"/>'};
function updateAppearance(){const mode=currentTheme();const labels={system:'跟随系统',light:'浅色',dark:'深色'};byId('theme-choice').setAttribute('aria-label',`外观：${labels[mode]}`);byId('theme-choice').title=`外观：${labels[mode]}`;byId('theme-choice').querySelector('svg')!.innerHTML=icons[mode];document.querySelectorAll<HTMLButtonElement>('[data-theme-choice]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.themeChoice===mode)));}
document.querySelectorAll<HTMLButtonElement>('[data-theme-choice]').forEach(button=>{button.onclick=()=>{setTheme(button.dataset.themeChoice as Theme);updateAppearance();byId<HTMLDetailsElement>('theme-menu').open=false;byId('theme-choice').focus();};});
document.addEventListener('click',event=>{if(!byId('theme-menu').contains(event.target as Node))byId<HTMLDetailsElement>('theme-menu').open=false;});
byId('theme-menu').onkeydown=event=>{if(event.key==='Escape'){byId<HTMLDetailsElement>('theme-menu').open=false;byId('theme-choice').focus();}};
updateAppearance();
