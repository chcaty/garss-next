export interface Source {
  id: string; title: string; description: string; category: string;
  feed_url: string; enabled: boolean; status?: string; article_count?: number;
  allow_undated?: boolean;
  recheck_requested_at?: string; discovered_from?: string; verified_at?: string;
}
export interface Article {
  id: string; source_id: string; source_ids?: string[]; title: string;
  url: string; published_at: string; date_inferred?: boolean; summary?: string; image_url?: string;
}
export interface SourceConfig {
  schema_version: '1.0'; sources: Source[];
  repository: { owner: string; name: string; branch: string; path: string };
}
export function webUrl(value: string): boolean {
  try { const url = new URL(value); return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password; }
  catch { return false; }
}
export function sourceIds(article: Article): string[] { return article.source_ids ?? [article.source_id]; }
export function filterArticles(articles: Article[], query = '', source = '', sources: Source[] = []): Article[] {
  const needle = query.trim().toLowerCase();
  const names = new Map(sources.map(value => [value.id, value.title]));
  return articles.filter(article => (!source || sourceIds(article).includes(source)) &&
    (!needle || `${article.title} ${article.summary ?? ''} ${sourceIds(article).map(id => names.get(id) ?? id).join(' ')}`.toLowerCase().includes(needle)));
}
export function validateConfig(value: unknown): asserts value is SourceConfig {
  const config = value as Partial<SourceConfig>;
  if (!config || config.schema_version !== '1.0' || !Array.isArray(config.sources) || !config.repository) throw Error('配置格式不正确');
  const ids = new Set<string>();
  for (const source of config.sources) {
    if (!/^[A-Za-z0-9_-]+$/.test(source.id) || ids.has(source.id) || !source.title?.trim() || !source.category?.trim() ||
        typeof source.description !== 'string' || typeof source.enabled !== 'boolean' || !webUrl(source.feed_url)) throw Error('来源字段不完整、地址不合法或 ID 重复');
    ids.add(source.id);
  }
  for (const key of ['owner', 'name', 'branch', 'path'] as const) if (typeof config.repository[key] !== 'string' || !config.repository[key]) throw Error('仓库配置缺失');
}
export async function readJson<T>(url: URL | string): Promise<T> {
  const response = await fetch(url, { cache: 'no-cache' });
  if (!response.ok) throw Error(`读取失败 (${response.status})`);
  return response.json() as Promise<T>;
}
export async function loadCatalog(base: string): Promise<{sources: Source[]; articles: Article[]; generatedAt: string}> {
  const metaUrl = new URL('./api/v1/meta.json', base);
  const meta = await readJson<{ snapshot_id: string; snapshot_endpoint: string; generated_at: string }>(metaUrl);
  const manifestUrl = new URL(meta.snapshot_endpoint, metaUrl);
  const manifest = await readJson<{ snapshot_id: string; generated_at: string; files: Record<string, {sha256: string; bytes: number}> }>(manifestUrl);
  if (manifest.snapshot_id !== meta.snapshot_id || manifest.generated_at !== meta.generated_at) throw Error('数据版本变化，请重试');
  async function verified<T>(name: string): Promise<T> {
    const url = new URL(name, manifestUrl);
    if (url.origin !== metaUrl.origin || !url.pathname.startsWith(new URL('./api/', base).pathname)) throw Error('数据地址不合法');
    const response = await fetch(url, {cache: 'no-cache'});
    if (!response.ok) throw Error('快照读取失败');
    const bytes = await response.arrayBuffer();
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), value => value.toString(16).padStart(2, '0')).join('');
    if (bytes.byteLength !== manifest.files[name]?.bytes || hash !== manifest.files[name]?.sha256) throw Error('数据校验失败');
    return JSON.parse(new TextDecoder().decode(bytes)) as T;
  }
  const [feeds, entries] = await Promise.all([verified<{feeds: Source[]; generated_at: string}>('feeds.json'), verified<{articles: Article[]; generated_at: string}>('articles.json')]);
  if (feeds.generated_at !== meta.generated_at || entries.generated_at !== meta.generated_at || !Array.isArray(feeds.feeds) || !Array.isArray(entries.articles)) throw Error('数据结构不正确');
  return {sources: feeds.feeds.filter(source => source.enabled !== false), articles: entries.articles.filter(article => webUrl(article.url)), generatedAt: meta.generated_at};
}
