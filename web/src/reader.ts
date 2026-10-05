import {readingSelection,unreadCounts,type ReadingWindow} from './reading-filter.ts';
import {currentTheme,setTheme,type Theme} from './theme.ts';
import {loadCatalog, filterArticles, sourceIds, type Article, type Source} from './catalog.ts';
import {ReadingLibrary, bookmarkSources, type SavedArticle} from './reading-state.ts';
const byId = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const create = (tag: string, text = '', className = '') => {
  const element = document.createElement(tag); element.textContent = text; element.className = className; return element;
};
let sources: Source[] = [], articles: Article[] = [], source = new URLSearchParams(location.search).get('source') ?? '', page = 1;
let mode='all', focusIndex=0, focusQueue:Article[]=[],selectedArticle='';
let library = new ReadingLibrary();
let storageAvailable=true;
try { library=new ReadingLibrary(JSON.parse(localStorage.getItem('garss-reading') ?? '{}')); }catch{storageAvailable=false;}
const readIds=library.read, savedIds=library.saved;
let catalogNotice='';
let removedBookmark:SavedArticle|undefined;let feedbackTimer:ReturnType<typeof setTimeout>;let returnArticle='';let returnScroll=0;
function feedback(message:string,removed?:SavedArticle){const dialog=byId<HTMLDialogElement>('focus-reader');(dialog.open?dialog:document.body).append(byId('reading-feedback'));clearTimeout(feedbackTimer);removedBookmark=removed;byId('feedback-text').textContent=message;byId('undo-save').hidden=!removed;byId('reading-feedback').hidden=false;feedbackTimer=setTimeout(()=>{byId('reading-feedback').hidden=true;removedBookmark=undefined;},8000);}
byId('undo-save').onclick=()=>{if(!removedBookmark)return;library.restoreSaved(removedBookmark);persistReading();renderCategories();renderSources();renderArticles();if(byId<HTMLDialogElement>('focus-reader').open)showFocus(false);feedback('已恢复稍后读');};
function readingNotice(){
 const messages=[catalogNotice];
 if(!storageAvailable)messages.push('浏览器无法保存阅读记录；请检查存储空间。当前改动仅在本次会话有效。');
 if(mode==='saved'&&library.missingBookmarks)messages.push(`${library.missingBookmarks} 篇旧收藏尚无内容备份；文章仍在目录时会自动补齐。`);
 byId('reading-status').textContent=messages.filter(Boolean).join(' ');
 byId('reading-status').hidden=!messages.some(Boolean);
}
function persistReading(){ try {localStorage.setItem('garss-reading',JSON.stringify(library));storageAvailable=true;}catch{storageAvailable=false;}readingNotice(); }
function visibleSources(){return mode==='saved'?bookmarkSources([...library.bookmarks.values()]):sources;}
function visibleArticles(){return mode==='saved'?[...library.bookmarks.values()]:articles;}
function articleSources(article:Article){return 'saved_sources' in article?(article as import('./reading-state.ts').SavedArticle).saved_sources:sources;}
function sourceNames(article:Article){const names=articleSources(article);return sourceIds(article).map(id=>names.find(item=>item.id===id)?.title??id).join(' · ');}
function toggleSaved(article:Article){
 const removed=library.bookmarks.get(article.id);const wasSaved=savedIds.has(article.id);
 library.toggleSaved(article,articleSources(article));persistReading();feedback(wasSaved?'已移出稍后读':'已加入稍后读',removed);
 if(mode==='saved'){
  if(source&&!visibleSources().some(item=>item.id===source))source='';
  renderCategories();renderSources();
 }
}
function matchingArticles(){
 const category=byId<HTMLSelectElement>('reading-category').value,window=byId<HTMLSelectElement>('reading-window').value as ReadingWindow;
 let selection=readingSelection(visibleArticles(),visibleSources(),mode==='saved'?'':category,window);
 if(mode==='saved'&&category)selection=selection.filter(article=>articleSources(article).some(item=>item.category===category));
 return filterArticles(selection,byId<HTMLInputElement>('article-search').value,source,visibleSources()).filter(article=>(mode==='unread'||byId<HTMLInputElement>('saved-unread').checked)?!readIds.has(article.id):true).sort((a,b)=>(Date.parse(b.published_at)-Date.parse(a.published_at))*(byId<HTMLSelectElement>('article-sort').value==='oldest'?-1:1));
}
function showFocus(markRead=true){
  const article=focusQueue[focusIndex];if(!article)return;
  if(markRead){readIds.add(article.id);persistReading();}
  byId('focus-title').textContent=article.title;
  byId('focus-meta').textContent=sourceNames(article)+' · 北京时间 '+date.format(new Date(article.published_at));
  const document=new DOMParser().parseFromString(article.summary??'', 'text/html');
  document.querySelectorAll('script,style').forEach(node=>node.remove());
  document.querySelectorAll('br').forEach(node=>node.replaceWith('\n'));
  document.querySelectorAll('p,li,div').forEach(node=>node.append('\n\n'));
  const summary=document.body.textContent?.trim()??'';
  byId('focus-summary').textContent=summary||'这个来源没有提供文章摘要。';
  byId('focus-hint').textContent=storageAvailable?'内容来自 RSS，完整内容请查看原文。':'浏览器无法保存阅读进度；本次会话仍可继续阅读。';
  byId<HTMLAnchorElement>('focus-original').href=article.url;
  byId('focus-save').textContent=savedIds.has(article.id)?'移出稍后读':'加入稍后读';
  byId('focus-read').textContent=readIds.has(article.id)?'标记为未读':'标记为已读';
  byId('focus-position').textContent=`本次筛选 · 第 ${focusIndex+1} / ${focusQueue.length} 篇`;
  byId<HTMLButtonElement>('focus-previous').disabled=focusIndex===0;
  byId<HTMLButtonElement>('focus-next').disabled=focusIndex===focusQueue.length-1;
  if(markRead)byId('focus-reader').querySelector('.focus-content')!.scrollTop=0;
}
const sourceCounts = new Map<string, number>();
const date = new Intl.DateTimeFormat('zh-CN', {month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Shanghai'});
function renderSources() {
  const query = byId<HTMLInputElement>('source-search').value.trim().toLowerCase();
  const pool=visibleArticles(),unread=unreadCounts(pool,readIds);
  const counts=new Map<string,number>();for(const article of pool)for(const id of new Set(sourceIds(article)))counts.set(id,(counts.get(id)??0)+1);
  byId('source-count').textContent=String(visibleSources().length);
  byId('source-note').textContent=mode==='saved'?'这里列出收藏时的来源，文章退出公共目录后仍保留。':'显示每个来源的未读数。这里只列出有文章的来源。';
  byId('source-list').replaceChildren();
  for (const item of [{id: '', title: '全部来源'}, ...visibleSources().filter(item => `${item.title} ${item.category}`.toLowerCase().includes(query))]) {
    const button = create('button', '', 'source-button') as HTMLButtonElement;
    button.type = 'button'; button.setAttribute('aria-pressed', String(source === item.id));
    button.append(create('span', item.title), create('span', `${item.id?unread.get(item.id)??0:pool.filter(article=>!readIds.has(article.id)).length} 未读`));
    button.title=`${item.id?counts.get(item.id)??0:pool.length} 篇文章`;
    button.onclick = () => { source = item.id; page = 1; renderSources(); renderArticles(); };
    byId('source-list').append(button);
  }
}
function renderArticles() {
  const filtered = matchingArticles();
  const pages = Math.max(1, Math.ceil(filtered.length / 30)); page = Math.min(page, pages);
  byId('stream-title').textContent = visibleSources().find(item => item.id === source)?.title ?? (mode==='saved'?'全部稍后读':'全部文章');
  byId('result-count').textContent = `${filtered.length} 篇文章`;
  byId('unread-total').textContent=`${filtered.filter(article=>!readIds.has(article.id)).length} 篇未读`;
  byId('clear-filters').hidden = !source && !byId<HTMLInputElement>('article-search').value && mode!=='unread' && !byId<HTMLInputElement>('saved-unread').checked && !byId<HTMLSelectElement>('reading-category').value && byId<HTMLSelectElement>('reading-window').value==='all' && byId<HTMLSelectElement>('article-sort').value==='newest';
  renderActiveFilters();
  byId('articles').replaceChildren();
  for (const article of filtered.slice((page - 1) * 30, page * 30)) {
    const row = create('article', '', `article-row${readIds.has(article.id)?' is-read':''}${selectedArticle===article.id?' is-selected':''}`), content = create('div'), meta = create('div', '', 'article-meta');
    meta.append(create('span', sourceNames(article), 'article-source'), create('time', `${article.date_inferred ? '首次发现 ' : ''}${date.format(new Date(article.published_at))}`));
    row.dataset.articleId=article.id;
    const heading=create('h3'), link=create('button',article.title,'article-title') as HTMLButtonElement;
    link.type='button';link.onclick=()=>{focusQueue=filtered;focusIndex=filtered.findIndex(item=>item.id===article.id);returnArticle=article.id;returnScroll=window.scrollY;showFocus();byId<HTMLDialogElement>('focus-reader').showModal();};heading.append(link);
    const save=create('button',savedIds.has(article.id)?'已收藏':'稍后读','button save-article') as HTMLButtonElement;
    save.type='button';save.setAttribute('aria-label',`${savedIds.has(article.id)?'移出':'加入'}稍后读：${article.title}`);save.setAttribute('aria-pressed',String(savedIds.has(article.id)));save.onclick=()=>{toggleSaved(article);renderArticles();};
    const read=create('button',readIds.has(article.id)?'标记未读':'标记已读','text-button') as HTMLButtonElement;
    read.type='button';read.setAttribute('aria-label',`${readIds.has(article.id)?'标记未读':'标记已读'}：${article.title}`);
    read.onclick=()=>{readIds.has(article.id)?library.markUnread(article):readIds.add(article.id);persistReading();renderSources();renderArticles();};
    const actions=create('div','','article-actions');actions.append(save,read);
    content.append(meta,heading);row.append(content,actions);byId('articles').append(row);
  }
  byId('reader-message').hidden = filtered.length > 0;
  const noSaved=mode==='saved'&&!library.bookmarks.size;
  byId('reader-message').replaceChildren(create('strong', noSaved?library.missingBookmarks?'旧收藏内容尚未补齐':'还没有稍后读':filtered.length===0&&byId<HTMLInputElement>('saved-unread').checked?'当前筛选没有未读文章':'没有匹配的文章'),create('p',noSaved?library.missingBookmarks?'这些旧记录只有文章 ID；文章重新出现在目录时会自动补齐内容。':'在信息流中把想读的文章加入稍后读，内容会保存在本机。':'可以清除筛选，重新查看文章。'));
  const emptyAction=create('button',noSaved?'去信息流':'清除筛选','button') as HTMLButtonElement;emptyAction.type='button';emptyAction.onclick=()=>noSaved?switchMode('all'):byId('clear-filters').click();byId('reader-message').append(emptyAction);
  byId('page-indicator').textContent = `第 ${page} / ${pages} 页`;
  byId<HTMLButtonElement>('previous-page').disabled = page <= 1;
  byId<HTMLButtonElement>('next-page').disabled = page >= pages;
  readingNotice();
}
function renderCategories(){const select=byId<HTMLSelectElement>('reading-category'),previous=select.value,pool=mode==='saved'?[...library.bookmarks.values()].flatMap(article=>article.saved_sources):sources;select.replaceChildren(new Option('全部分类',''));[...new Set(pool.map(item=>item.category))].sort((a,b)=>a.localeCompare(b,'zh')).forEach(value=>select.add(new Option(value,value)));select.value=[...select.options].some(option=>option.value===previous)?previous:'';}
async function load() {
  byId('articles').setAttribute('aria-busy', 'true'); byId('retry-load').hidden = true;
  try {
    const data = await loadCatalog(location.href); articles = data.articles;
    sourceCounts.clear();
    for (const article of articles) for (const id of new Set(sourceIds(article))) sourceCounts.set(id, (sourceCounts.get(id) ?? 0) + 1);
    sources = data.sources.filter(item => (sourceCounts.get(item.id) ?? 0) > 0);
    library.reconcile(articles,data.sources);persistReading();catalogNotice='';
    source = data.sourceAliases[source] ?? source;
    if (source && !sources.some(item => item.id === source)) source = '';
    byId('edition-date').textContent = new Intl.DateTimeFormat('zh-CN', {dateStyle: 'long', timeZone: 'Asia/Shanghai'}).format(new Date(data.generatedAt));
    byId('snapshot-info').textContent = `最近同步 ${date.format(new Date(data.generatedAt))} · ${sources.length} 个有文章的来源`;
    renderCategories();
    byId('source-count').textContent = String(sources.length); renderSources(); renderArticles();
  } catch {
    byId('edition-date').textContent='同步暂时不可用';byId('snapshot-info').textContent='公共目录读取失败 · 稍后读可继续使用';
    catalogNotice='公共目录读取失败，请检查网络后重试；已备份的稍后读仍可查看。';
    if(library.bookmarks.size){switchMode('saved');}
    byId('reader-message').hidden = false; byId('reader-message').textContent = '读取失败，请检查网络后重试'; byId('retry-load').hidden = false;
    if(library.bookmarks.size)renderArticles();readingNotice();
  } finally { byId('articles').setAttribute('aria-busy', 'false'); }
}
byId('source-search').oninput = renderSources;
byId('article-search').oninput = () => { page = 1; renderArticles(); };
byId('reading-category').onchange=byId('reading-window').onchange=()=>{page=1;renderArticles();};
byId('article-sort').onchange = () => { page = 1; renderArticles(); };
byId('clear-filters').onclick = () => { source = ''; if(mode==='unread')mode='all';byId<HTMLInputElement>('saved-unread').checked=false;updateModes();page = 1; byId<HTMLInputElement>('article-search').value = '';byId<HTMLSelectElement>('reading-category').value='';byId<HTMLSelectElement>('reading-window').value='all';byId<HTMLSelectElement>('article-sort').value='newest'; renderSources(); renderArticles(); };
byId('previous-page').onclick = () => { page--; renderArticles(); byId('stream-title').scrollIntoView(); };
byId('next-page').onclick = () => { page++; renderArticles(); byId('stream-title').scrollIntoView(); };
byId('retry-load').onclick = load;
void load();

type Filters={source:string;query:string;category:string;window:string;unread:boolean;sort:string};
const filters=new Map<string,Filters>();
function updateModes(){document.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.mode===mode)));byId('page-title').textContent=mode==='saved'?'稍后读':'信息流';}
function switchMode(next:string){
 const scope=mode==='saved'?'saved':'stream',nextScope=next==='saved'?'saved':'stream';
 filters.set(scope,{source,query:byId<HTMLInputElement>('article-search').value,category:byId<HTMLSelectElement>('reading-category').value,window:byId<HTMLSelectElement>('reading-window').value,unread:byId<HTMLInputElement>('saved-unread').checked,sort:byId<HTMLSelectElement>('article-sort').value});
 mode=next;const values=filters.get(nextScope);source=values?.source??'';
 byId<HTMLInputElement>('article-search').value=values?.query??'';byId<HTMLSelectElement>('reading-window').value=values?.window??'all';byId<HTMLSelectElement>('article-sort').value=values?.sort??'newest';byId<HTMLInputElement>('saved-unread').checked=values?.unread??false;
 renderCategories();byId<HTMLSelectElement>('reading-category').value=values?.category??'';
 if(!visibleSources().some(item=>item.id===source))source='';
 page=1;updateModes();renderSources();renderArticles();
}
document.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach(button=>{button.onclick=()=>switchMode(button.dataset.mode??'all');});
byId('saved-unread').onchange=()=>{page=1;renderArticles();};
byId('focus-close').onclick=()=>byId<HTMLDialogElement>('focus-reader').close();
byId<HTMLDialogElement>('focus-reader').onclose=()=>{document.body.append(byId('reading-feedback'));renderSources();renderArticles();window.scrollTo({top:returnScroll,behavior:'instant'});const rows=[...document.querySelectorAll<HTMLElement>('.article-row')];const target=rows.find(row=>row.dataset.articleId===returnArticle)??rows[0];const button=target?.querySelector<HTMLButtonElement>('.article-title');if(button)button.focus({preventScroll:true});else{byId('stream-title').tabIndex=-1;byId('stream-title').focus({preventScroll:true});}};
byId('focus-save').onclick=()=>{toggleSaved(focusQueue[focusIndex]);showFocus(false);};
byId('focus-read').onclick=()=>{const article=focusQueue[focusIndex];readIds.has(article.id)?library.markUnread(article):readIds.add(article.id);persistReading();showFocus(false);};
byId('focus-previous').onclick=()=>{focusIndex--;showFocus();};
byId('focus-next').onclick=()=>{focusIndex++;showFocus();};
const icons:Record<Theme,string>={system:'<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',light:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.4 1.4m11.2 11.2L19 19M5 19l1.4-1.4M17.6 6.4 19 5"/>',dark:'<path d="M20 14.2A8.6 8.6 0 0 1 9.8 4a8.6 8.6 0 1 0 10.2 10.2Z"/>'};
function updateAppearance(){const mode=currentTheme();const labels={system:'跟随系统',light:'浅色',dark:'深色'};byId('theme-choice').setAttribute('aria-label',`外观：${labels[mode]}`);byId('theme-choice').title=`外观：${labels[mode]}`;byId('theme-choice').querySelector('svg')!.innerHTML=icons[mode];document.querySelectorAll<HTMLButtonElement>('[data-theme-choice]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.themeChoice===mode)));}
document.querySelectorAll<HTMLButtonElement>('[data-theme-choice]').forEach(button=>{button.onclick=()=>{setTheme(button.dataset.themeChoice as Theme);updateAppearance();byId<HTMLDetailsElement>('theme-menu').open=false;byId('theme-choice').focus();};});
document.addEventListener('click',event=>{if(!byId('theme-menu').contains(event.target as Node))byId<HTMLDetailsElement>('theme-menu').open=false;});
byId('theme-menu').onkeydown=event=>{if(event.key==='Escape'){byId<HTMLDetailsElement>('theme-menu').open=false;byId('theme-choice').focus();}};
updateAppearance();

document.addEventListener('keydown',event=>{
 if(event.isComposing||event.altKey||event.ctrlKey||event.metaKey||(event.target as Element)?.closest('input,textarea,select,[contenteditable="true"],#theme-menu[open],#filter-dialog[open]'))return;
 const key=event.key.toLowerCase(),dialog=byId<HTMLDialogElement>('focus-reader');
 if(dialog.open){if(key==='j'||key==='k'){event.preventDefault();const next=focusIndex+(key==='j'?1:-1);if(next>=0&&next<focusQueue.length){focusIndex=next;showFocus();}}else if(key==='f'){event.preventDefault();toggleSaved(focusQueue[focusIndex]);showFocus(false);}return;}
 const rows=[...document.querySelectorAll<HTMLElement>('.article-row')],index=rows.findIndex(row=>row.dataset.articleId===selectedArticle);
 if(key==='/'){event.preventDefault();byId('article-search').focus();}
 else if(key==='j'||key==='k'){event.preventDefault();const next=index<0?0:Math.max(0,Math.min(rows.length-1,index+(key==='j'?1:-1))),row=rows[next];if(row){selectedArticle=row.dataset.articleId??'';rows.forEach(item=>item.classList.toggle('is-selected',item===row));row.querySelector<HTMLElement>('.article-title')?.focus({preventScroll:true});row.scrollIntoView({block:'nearest'});}}
 else if(index>=0&&(key==='o'||key==='f')){event.preventDefault();rows[index].querySelector<HTMLButtonElement>(key==='o'?'.article-title':'.save-article')?.click();}
});

function renderActiveFilters(){
 const host=byId('active-filters');host.replaceChildren();
 const add=(text:string,clear:()=>void)=>{const button=create('button',text+' ×','filter-chip') as HTMLButtonElement;button.type='button';button.setAttribute('aria-label','移除筛选：'+text);button.onclick=()=>{clear();page=1;renderSources();renderArticles();};host.append(button);};
 if(source)add(visibleSources().find(item=>item.id===source)?.title??source,()=>{source='';});
 for(const id of ['reading-category','reading-window','article-sort']){const select=byId<HTMLSelectElement>(id);if(select.value!==({ 'reading-category':'','reading-window':'all','article-sort':'newest'}[id]))add(select.selectedOptions[0]?.textContent??'',()=>{select.value=({'reading-category':'','reading-window':'all','article-sort':'newest'}[id])??'';});}
 if(byId<HTMLInputElement>('article-search').value)add('搜索：'+byId<HTMLInputElement>('article-search').value,()=>{byId<HTMLInputElement>('article-search').value='';});
 byId('open-filters').textContent=host.childElementCount?'筛选 · '+host.childElementCount:'筛选';
}
const filterDialog=byId<HTMLDialogElement>('filter-dialog');
byId('open-filters').onclick=()=>filterDialog.showModal();
byId('close-filters').onclick=()=>filterDialog.close();
const narrow=matchMedia('(max-width: 720px)');
function adaptFilters(){filterDialog.close();byId(narrow.matches?'mobile-source-host':'desktop-source-host').append(document.querySelector('.source-index')!);byId(narrow.matches?'mobile-filter-host':'desktop-filter-host').append(byId('filter-fields'));}
narrow.addEventListener('change',adaptFilters);adaptFilters();
