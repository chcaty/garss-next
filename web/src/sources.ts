import {readJson, validateConfig, webUrl, type Source, type SourceConfig} from './catalog.ts';
import {changes, duplicateUrls, matchesSource} from './source-management.ts';
const byId = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const draftKey = `garss-next-sources:${location.pathname}`;
let config: SourceConfig | undefined;
let published: SourceConfig | undefined;
let health = new Map<string, Source>();
let page = 1;
const pageSize = 20;
const selected = new Set<string>();
let editingId: string | null = null;
let editorDirty = false;
const status = (message: string) => { byId('status').textContent = message; };
function persist() {
  if (!config) return;
  validateConfig(config);
  try { localStorage.setItem(draftKey, JSON.stringify(config)); status('草稿已保存在此浏览器，提交并发布后生效'); }
  catch { status('浏览器无法保存草稿，请下载 JSON 备份，避免刷新后丢失改动'); }
}
function filtered(): Source[] {
  const query = byId<HTMLInputElement>('search').value, filter = byId<HTMLSelectElement>('filter').value;
  const category = byId<HTMLSelectElement>('category').value;
  const duplicates = duplicateUrls(config?.sources ?? []);
  const modified = new Set(changes(published?.sources ?? [], config?.sources ?? []).map(item => item.id));
  return (config?.sources ?? []).filter(source => matchesSource(source, query, category) &&
    (filter === 'all' || filter === 'enabled' && source.enabled || filter === 'disabled' && !source.enabled ||
     filter === 'error' && source.enabled && health.get(source.id)?.status === 'error' ||
     filter === 'duplicate' && duplicates.has(source.feed_url) || filter === 'changed' && modified.has(source.id)));
}
function element<K extends keyof HTMLElementTagNameMap>(tag: K, text = '', className = '') {
  const node = document.createElement(tag); node.textContent = text; node.className = className; return node;
}
function updateCategories() {
  const select = byId<HTMLSelectElement>('category'), value = select.value;
  const categories = [...new Set(config?.sources.map(source => source.category))].sort((a,b) => a.localeCompare(b, 'zh'));
  select.replaceChildren(new Option('全部分类', 'all'), ...categories.map(value => new Option(value, value)));
  select.value = categories.includes(value) ? value : 'all';
  byId('categories').replaceChildren(...categories.map(value => { const option = element('option'); option.value = value; return option; }));
}
function renderChanges() {
  const diff = changes(published?.sources ?? [], config?.sources ?? []);
  byId('draft-count').textContent = diff.length ? `${diff.length} 个来源有未发布改动` : `共 ${config?.sources.length ?? 0} 个来源 · 与发布配置一致`;
  byId('change-summary').textContent = diff.length ? '以下改动仅存在本机草稿，删除也会包含在提交配置中。' : '当前没有待提交改动。';
  byId('change-list').replaceChildren(...diff.map(item => element('li', `${item.kind} · ${item.title}`)));
  byId<HTMLButtonElement>('reset').disabled = !diff.length;
}
function render() {
  const sources = filtered(), pages = Math.max(1, Math.ceil(sources.length / pageSize)); page = Math.min(page, pages);
  const visible = sources.slice((page - 1) * pageSize, page * pageSize), duplicates = duplicateUrls(config?.sources ?? []);
  const diff = new Set(changes(published?.sources ?? [], config?.sources ?? []).map(item => item.id));
  byId('list').replaceChildren();
  for (const source of visible) {
    const row = element('article', '', `source-row${selected.has(source.id) ? ' selected' : ''}`);
    const check = element('input'); check.type = 'checkbox'; check.checked = selected.has(source.id); check.setAttribute('aria-label', `选择 ${source.title} (${source.id})`);
    check.onchange = () => {if (check.checked) selected.add(source.id); else selected.delete(source.id); render();};
    const body = element('div'), name = element('div', source.title, 'source-name'), url = element('div', source.feed_url, 'source-url'); url.title = source.feed_url;
    const meta = element('div', '', 'source-meta'), last = health.get(source.id);
    meta.append(element('span', source.category), element('span', source.enabled ? '已启用' : '已停用'));
    if (diff.has(source.id)) meta.append(element('span', '未发布改动', 'pending'));
    else if (source.enabled && last) { const state = element('span', last.status === 'error' ? '采集异常' : last.status === 'ok' ? '采集正常' : '暂无采集结果', last.status === 'error' ? 'problem' : last.status === 'ok' ? 'healthy' : ''); meta.append(state); }
    if (last?.article_count !== undefined) meta.append(element('span', `${last.article_count} 篇已发布`));
    if (duplicates.has(source.feed_url)) meta.append(element('span', '地址重复', 'problem'));
    body.append(name, url, meta);
    const edit = element('button', '编辑'); edit.setAttribute('aria-label', `编辑 ${source.title} (${source.id})`); edit.onclick = () => openEditor(source.id);
    row.append(check, body, edit); byId('list').append(row);
  }
  if (!visible.length) {byId('list').append(element('p', config?.sources.length ? '没有匹配的来源。试试其他关键词或筛选条件。' : '还没有来源。添加一个 RSS 地址，开始建立信息入口。', 'empty'));}
  byId('results').textContent = `${sources.length} 个匹配 / ${config?.sources.length ?? 0} 个来源`;
  byId('page').textContent = `第 ${page} / ${pages} 页`;
  byId<HTMLButtonElement>('prev').disabled = page <= 1; byId<HTMLButtonElement>('next').disabled = page >= pages;
  const all = byId<HTMLInputElement>('select-page'); all.checked = visible.length > 0 && visible.every(source => selected.has(source.id)); all.indeterminate = !all.checked && visible.some(source => selected.has(source.id)); all.disabled = !visible.length;
  byId('bulk').hidden = !selected.size; byId('selected-count').textContent = `已选 ${selected.size} 个来源`;
  renderChanges();
}
function formField(name: string) { return byId<HTMLFormElement>('edit').elements.namedItem(name) as HTMLInputElement; }
function closeEditor() {
  if (editorDirty && !confirm('离开编辑面板将丢弃尚未保存的输入。继续？')) return;
  editorDirty = false;
  byId('editor').classList.remove('active');
  byId('edit').hidden = true; byId('editor-empty').hidden = false; editingId = null;
  byId('list').focus();
}
function openEditor(id: string | null) {
  if (!config) return;
  if (editorDirty && !confirm('切换来源将丢弃尚未保存的输入。继续？')) return;
  editorDirty = false;
  const source = config.sources.find(item => item.id === id);
  editingId = id; byId('editor').classList.add('active'); byId('edit').hidden = false; byId('editor-empty').hidden = true;
  byId('editor-title').textContent = source ? '编辑来源' : '添加来源';
  for (const key of ['title','feed_url','category','description'] as const) formField(key).value = source?.[key] ?? '';
  formField('enabled').checked = source?.enabled ?? true;
  const last = source ? health.get(source.id) : undefined;
  byId('editor-meta').textContent = source ? `来源 ID：${source.id}${last?.status === 'error' ? ' · 上次采集失败，请核对 RSS 地址。' : ''}` : '添加后存入本机草稿，提交发布后开始采集。';
  byId('remove').hidden = !source; byId('preview').hidden = !source;
  byId<HTMLAnchorElement>('preview').href = `./?source=${encodeURIComponent(id ?? '')}`;
  byId('edit-error').textContent = '';
  byId('editor').scrollIntoView({block:'nearest'}); formField('title').focus({preventScroll:true});
}
async function load() {
  if (editorDirty && !confirm('刷新将丢弃尚未保存的输入。继续？')) return;
  if (config && changes(published?.sources ?? [], config.sources).length && !confirm('刷新将重新读取发布配置，并恢复已保存的本机草稿。继续？')) return;
  status('正在读取来源配置…'); byId<HTMLButtonElement>('retry').disabled = true;
  try {
    const value = await readJson<unknown>('./api/v1/sources.json'); validateConfig(value); published = structuredClone(value); config = structuredClone(value);
    let draftWarning = '';
    try {const saved = localStorage.getItem(draftKey); if (saved) {const draft: unknown = JSON.parse(saved); validateConfig(draft);
      if (draft.repository.owner === value.repository.owner && draft.repository.name === value.repository.name) {config = draft; draftWarning = '已恢复本机草稿；提交前请核对远程配置是否有更新。';}
    }} catch {draftWarning = '原草稿无法读取，已加载发布配置。';}
    editorDirty = false; selected.clear(); page = 1; closeEditor(); updateCategories(); render();
    byId<HTMLButtonElement>('new').disabled = false; byId<HTMLButtonElement>('review').disabled = false;
    status(draftWarning || '已加载发布配置。改动先保存为草稿。');
    health.clear();
    try {const feeds = await readJson<{feeds:Source[]}>('./api/v1/feeds.json'); if (!Array.isArray(feeds.feeds)) throw Error(); health = new Map(feeds.feeds.map(source => [source.id, source])); render();}
    catch {status(`${draftWarning || '来源配置已加载。'} 暂时无法读取采集状态，可继续编辑。`);}
  } catch {status('无法读取来源配置。请检查网络，再点击刷新配置。');}
  finally {byId<HTMLButtonElement>('retry').disabled = false;}
}
function text(): string {if (!config) throw Error('请先加载配置'); validateConfig(config); return JSON.stringify(config, null, 2) + '\n';}
function download(name: string, content: string, type: string) {
  const url = URL.createObjectURL(new Blob([content], {type})); const link = document.createElement('a'); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
for (const id of ['search','filter','category']) byId(id).addEventListener(id === 'search' ? 'input' : 'change', () => {page = 1; render();});
byId('select-page').onchange = () => {const checked = byId<HTMLInputElement>('select-page').checked; for (const source of filtered().slice((page-1)*pageSize,page*pageSize)) {if (checked) selected.add(source.id); else selected.delete(source.id);} render();};
byId('clear-selection').onclick = () => {selected.clear(); render();};
for (const [id, enabled] of [['enable', true], ['disable', false]] as const) byId(id).onclick = () => {if (!config) return; if (editorDirty && !confirm('批量操作将丢弃编辑面板中尚未保存的输入。继续？')) return; editorDirty = false; for (const source of config.sources) if (selected.has(source.id)) source.enabled = enabled; selected.clear(); persist(); render(); if (editingId) openEditor(editingId);};
for (const [id, offset] of [['prev',-1],['next',1]] as const) byId(id).onclick = () => {page += offset; render(); byId('list').scrollIntoView({block:'start'});};
byId('new').onclick = () => openEditor(null); byId('close-editor').onclick = closeEditor;
byId('edit').oninput = () => {editorDirty = true;};
window.addEventListener('beforeunload', event => {if (editorDirty) {event.preventDefault(); event.returnValue = '';}});
byId<HTMLFormElement>('edit').onsubmit = event => {
  event.preventDefault(); if (!config) return;
  const candidate: Source = {id:editingId ?? `user-${crypto.randomUUID()}`,title:formField('title').value.trim(),feed_url:formField('feed_url').value.trim(),category:formField('category').value.trim(),description:formField('description').value.trim(),enabled:formField('enabled').checked};
  if (!candidate.title || !candidate.category || !webUrl(candidate.feed_url)) {byId('edit-error').textContent = '请填写名称和分类，并输入有效的 HTTP(S) RSS 地址。'; return;}
  const original = config.sources.find(source => source.id === editingId);
  if (candidate.feed_url !== original?.feed_url && config.sources.some(source => source.id !== candidate.id && source.feed_url === candidate.feed_url)) {byId('edit-error').textContent = '这个 RSS 地址已存在，请编辑已有来源，避免重复采集。'; return;}
  if (original) Object.assign(original, candidate); else config.sources.push(candidate);
  editorDirty = false; persist(); updateCategories(); render(); openEditor(candidate.id); status(`「${candidate.title}」已保存到草稿，尚未发布。`);
};
byId('remove').onclick = () => {const source = config?.sources.find(item => item.id === editingId); if (!source || !confirm(`从本机草稿删除「${source.title}」？提交发布后才会从公共配置移除。`)) return;
  config!.sources = config!.sources.filter(item => item.id !== editingId); selected.delete(source.id); editorDirty = false; persist(); closeEditor(); updateCategories(); render();};
byId('review').onclick = () => {byId('changes').hidden = false; renderChanges(); byId('changes').scrollIntoView({block:'start'}); byId('changes').focus({preventScroll:true});};
byId('copy').onclick = async () => {try {await navigator.clipboard.writeText(text()); status('配置已复制。下一步打开 GitHub 编辑页，粘贴并提交到新分支。');} catch {status('无法复制，请下载 JSON 后手动粘贴到 GitHub。');}};
byId('download').onclick = () => {try {download('sources.json', text(), 'application/json'); status('草稿已导出为 JSON，尚未提交。');} catch {status('请先加载来源配置');}};
byId('submit').onclick = () => {if (!config || !published) return; const repo = published.repository;
  window.open(`https://github.com/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/edit/${encodeURIComponent(repo.branch)}/${repo.path.split('/').map(encodeURIComponent).join('/')}`, '_blank', 'noopener,noreferrer');
  status('已打开 GitHub 编辑页：粘贴配置，选择新分支并创建 PR。合并发布后生效。');};
byId('reset').onclick = () => {if (published && confirm('丢弃所有已保存的本机来源草稿，恢复发布配置？')) {config = structuredClone(published); try {localStorage.removeItem(draftKey);} catch {} selected.clear(); editorDirty = false; closeEditor(); updateCategories(); render(); status('已恢复发布配置。');}};
byId('retry').onclick = load;
byId('export-opml').onclick = () => {
  if (!config) return;
  const xml = document.implementation.createDocument('', 'opml', null); xml.documentElement.setAttribute('version', '2.0');
  const body = xml.createElement('body'); xml.documentElement.append(body);
  for (const source of config.sources) {const outline = xml.createElement('outline'); for (const [key, value] of Object.entries({type:'rss', text:source.title, title:source.title, xmlUrl:source.feed_url, category:source.category, description:source.description})) outline.setAttribute(key, value); body.append(outline);}
  download('subscriptions.opml', new XMLSerializer().serializeToString(xml), 'text/xml');
};
byId<HTMLInputElement>('import-opml').onchange = async event => {
  const file = (event.target as HTMLInputElement).files?.[0]; if (!file || !config) return;
  if (file.size > 2_000_000) {status('OPML 文件过大'); return;}
  const xml = new DOMParser().parseFromString(await file.text(), 'text/xml'); if (xml.querySelector('parsererror')) {status('OPML 格式不正确'); return;}
  let count = 0;
  for (const outline of xml.querySelectorAll('outline[xmlUrl]')) {const url = outline.getAttribute('xmlUrl')!.trim();
    if (!webUrl(url) || config.sources.some(source => source.feed_url === url)) continue;
    config.sources.push({id:`user-${crypto.randomUUID()}`, title:outline.getAttribute('title')?.trim() || outline.getAttribute('text')?.trim() || url,
      feed_url:url, category:outline.getAttribute('category')?.trim() || '导入来源', description:outline.getAttribute('description') || '', enabled:true}); count++;
  }
  persist(); updateCategories(); render(); (event.target as HTMLInputElement).value = ''; status(`已导入 ${count} 个来源到本机草稿，尚未生效`);
};
void load();
