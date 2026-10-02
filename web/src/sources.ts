import {readJson, validateConfig, webUrl, type Source, type SourceConfig} from './catalog.ts';
const byId = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const draftKey = `garss-next-sources:${location.pathname}`;
let config: SourceConfig | undefined;
let published: SourceConfig | undefined;
const status = (message: string) => { byId('status').textContent = message; };
function persist() {
  if (!config) return;
  validateConfig(config);
  try { localStorage.setItem(draftKey, JSON.stringify(config)); status('本机草稿已保存，尚未提交或生效'); }
  catch { status('本机存储不可用，请下载配置备份；改动尚未生效'); }
}
function filtered(): Source[] {
  const query = byId<HTMLInputElement>('search').value.trim().toLowerCase(), filter = byId<HTMLSelectElement>('filter').value;
  return (config?.sources ?? []).filter(source => `${source.title} ${source.description} ${source.category}`.toLowerCase().includes(query) &&
    (filter === 'all' || source.enabled === (filter === 'enabled')));
}
function render() {
  byId('list').replaceChildren();
  for (const source of filtered()) {
    const row = document.createElement('section'); row.className = 'source';
    const fields = document.createElement('div'); fields.className = 'source-fields';
    for (const [key, text] of [['title', '名称'], ['feed_url', 'RSS 地址'], ['category', '分类'], ['description', '简介']] as const) {
      const label = document.createElement('label'); label.textContent = text;
      const input = document.createElement('input'); input.value = source[key]; input.type = key === 'feed_url' ? 'url' : 'text';
      input.onchange = () => {
        const next = input.value.trim();
        if (key === 'feed_url' ? !webUrl(next) : key !== 'description' && !next) { status('字段不合法，请检查名称、分类和 RSS 地址'); input.value = source[key]; return; }
        source[key] = next; persist();
      };
      label.append(input); fields.append(label);
    }
    const actions = document.createElement('div'); actions.className = 'source-actions';
    const toggleLabel = document.createElement('label'), toggle = document.createElement('input'); toggle.type = 'checkbox'; toggle.checked = source.enabled;
    toggle.onchange = () => {source.enabled = toggle.checked; persist(); render();};
    toggleLabel.append(toggle, document.createTextNode('参与 CI 采集'));
    const remove = document.createElement('button'); remove.textContent = '删除来源';
    remove.onclick = () => { if (confirm(`从配置删除「${source.title}」？本机草稿提交生效后执行。`)) { config!.sources = config!.sources.filter(item => item.id !== source.id); persist(); render(); } };
    const preview = document.createElement('a'); preview.href = `./?source=${encodeURIComponent(source.id)}`; preview.textContent = '查看文章';
    actions.append(toggleLabel, preview, remove); row.append(fields, actions); byId('list').append(row);
  }
  if (!filtered().length) byId('list').textContent = '没有匹配的来源';
}
async function load() {
  try {
    const value = await readJson<unknown>('./api/v1/sources.json'); validateConfig(value); published = structuredClone(value); config = structuredClone(value);
    try {const saved = localStorage.getItem(draftKey); if (saved) { const draft: unknown = JSON.parse(saved); validateConfig(draft);
      if (draft.repository.owner === value.repository.owner && draft.repository.name === value.repository.name) config = draft;
    }} catch {status('草稿无法读取，已加载发布配置');}
    status(JSON.stringify(config) === JSON.stringify(published) ? `已加载 ${config.sources.length} 个来源` : '已恢复本机草稿，尚未提交；如远程配置已更新，请丢弃草稿后重做改动'); render();
  } catch { status('来源配置读取失败，请点击重新加载'); }
}
function text(): string { if (!config) throw Error('请先加载配置'); validateConfig(config); return JSON.stringify(config, null, 2) + '\n'; }
function download(name: string, content: string, type: string) {
  const url = URL.createObjectURL(new Blob([content], {type})); const link = document.createElement('a'); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
byId('search').oninput = render; byId('filter').onchange = render;
for (const [id, enabled] of [['enable', true], ['disable', false]] as const) byId(id).onclick = () => { if (!config) return; for (const source of filtered()) source.enabled = enabled; persist(); render(); };
byId<HTMLFormElement>('add').onsubmit = event => {
  event.preventDefault(); if (!config) return;
  const form = byId<HTMLFormElement>('add'), values = new FormData(form), url = String(values.get('feed_url')).trim();
  if (!webUrl(url)) {status('请输入 HTTP(S) RSS 地址'); return;}
  if (config.sources.some(source => source.feed_url === url)) {status('这个地址已经存在'); return;}
  const source: Source = {id: `user-${crypto.randomUUID()}`, title: String(values.get('title')).trim(), category: String(values.get('category')).trim(), description: String(values.get('description')).trim(), feed_url: url, enabled: true};
  config.sources.push(source); persist(); form.reset(); render();
};
byId('copy').onclick = async () => {try {await navigator.clipboard.writeText(text()); status('配置已复制，请到 GitHub 新分支提交并创建 PR');} catch {status('无法复制，请下载 JSON 后手动粘贴');}};
byId('download').onclick = () => {try {download('sources.json', text(), 'application/json');} catch {status('请先加载来源配置');}};
byId('submit').onclick = () => {
  if (!config) return;
  const repo = published!.repository;
  window.open(`https://github.com/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/edit/${encodeURIComponent(repo.branch)}/${repo.path.split('/').map(encodeURIComponent).join('/')}`, '_blank', 'noopener,noreferrer');
  status('已打开 GitHub 编辑页：粘贴配置，选择新分支并创建 PR；合并发布后生效');
};
byId('reset').onclick = () => { if (published && confirm('丢弃本机来源草稿？')) {config = structuredClone(published); try {localStorage.removeItem(draftKey);} catch {} render(); status('已恢复发布配置');} };
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
  for (const outline of xml.querySelectorAll('outline[xmlUrl]')) {const url = outline.getAttribute('xmlUrl')!;
    if (!webUrl(url) || config.sources.some(source => source.feed_url === url)) continue;
    config.sources.push({id:`user-${crypto.randomUUID()}`, title:outline.getAttribute('title') || outline.getAttribute('text') || url,
      feed_url:url, category:outline.getAttribute('category') || '导入来源', description:outline.getAttribute('description') || '', enabled:true}); count++;
  }
  persist(); render(); status(`已导入 ${count} 个来源到本机草稿，尚未生效`);
};
void load();
