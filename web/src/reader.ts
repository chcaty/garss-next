import {loadCatalog, filterArticles, sourceIds, type Article, type Source} from './catalog.ts';
const byId = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const create = (tag: string, text = '', className = '') => {
  const element = document.createElement(tag); element.textContent = text; element.className = className; return element;
};
let sources: Source[] = [], articles: Article[] = [], source = new URLSearchParams(location.search).get('source') ?? '', page = 1;
const date = new Intl.DateTimeFormat('zh-CN', {month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Shanghai'});
function renderSources() {
  const query = byId<HTMLInputElement>('source-search').value.trim().toLowerCase();
  byId('source-list').replaceChildren();
  for (const item of [{id: '', title: '全部来源'}, ...sources.filter(item => `${item.title} ${item.category}`.toLowerCase().includes(query))]) {
    const button = create('button', '', 'source-button') as HTMLButtonElement;
    button.type = 'button'; button.setAttribute('aria-pressed', String(source === item.id));
    button.append(create('span', item.title), create('span', String(item.id ? articles.filter(article => sourceIds(article).includes(item.id)).length : articles.length)));
    button.onclick = () => { source = item.id; page = 1; renderSources(); renderArticles(); };
    byId('source-list').append(button);
  }
}
function renderArticles() {
  const filtered = filterArticles(articles, byId<HTMLInputElement>('article-search').value, source, sources)
    .sort((a, b) => (Date.parse(b.published_at) - Date.parse(a.published_at)) * (byId<HTMLSelectElement>('article-sort').value === 'oldest' ? -1 : 1));
  const pages = Math.max(1, Math.ceil(filtered.length / 30)); page = Math.min(page, pages);
  byId('stream-title').textContent = sources.find(item => item.id === source)?.title ?? '全部文章';
  byId('result-count').textContent = `${filtered.length} 篇文章`;
  byId('clear-filters').hidden = !source && !byId<HTMLInputElement>('article-search').value;
  byId('articles').replaceChildren();
  for (const article of filtered.slice((page - 1) * 30, page * 30)) {
    const row = create('article', '', 'article-row'), content = create('div'), meta = create('div', '', 'article-meta');
    meta.append(create('span', sourceIds(article).map(id => sources.find(item => item.id === id)?.title ?? id).join(' · '), 'article-source'), create('time', `${article.date_inferred ? '首次发现 ' : ''}${date.format(new Date(article.published_at))}`));
    const heading = create('h3'), link = create('a', article.title) as HTMLAnchorElement;
    link.href = article.url; link.target = '_blank'; link.rel = 'noopener noreferrer'; heading.append(link);
    content.append(meta, heading); row.append(content); byId('articles').append(row);
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
    const data = await loadCatalog(location.href); sources = data.sources; articles = data.articles;
    byId('edition-date').textContent = new Intl.DateTimeFormat('zh-CN', {dateStyle: 'long', timeZone: 'Asia/Shanghai'}).format(new Date(data.generatedAt));
    byId('snapshot-info').textContent = `最近同步 ${date.format(new Date(data.generatedAt))} · ${sources.length} 个启用来源`;
    byId('source-count').textContent = String(sources.length); renderSources(); renderArticles();
  } catch {
    byId('reader-message').hidden = false; byId('reader-message').textContent = '读取失败，请检查网络后重试'; byId('retry-load').hidden = false;
  } finally { byId('articles').setAttribute('aria-busy', 'false'); }
}
byId('source-search').oninput = renderSources;
byId('article-search').oninput = () => { page = 1; renderArticles(); };
byId('article-sort').onchange = () => { page = 1; renderArticles(); };
byId('clear-filters').onclick = () => { source = ''; page = 1; byId<HTMLInputElement>('article-search').value = ''; renderSources(); renderArticles(); };
byId('previous-page').onclick = () => { page--; renderArticles(); byId('stream-title').scrollIntoView(); };
byId('next-page').onclick = () => { page++; renderArticles(); byId('stream-title').scrollIntoView(); };
byId('retry-load').onclick = load;
void load();
