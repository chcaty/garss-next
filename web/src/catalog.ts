export interface FeedHealth {
  raw_entry_count?: number;
  valid_article_count?: number;
  new_article_count?: number;
  drop_reasons?: Record<string, number>;
  latest_article_at?: string;
  last_new_article_at?: string;
}
export interface CandidateArticle { title: string; url: string; published_at: string; date_inferred?: boolean }
export interface Source {
  id: string; title: string; description: string; category: string;
  feed_url: string; enabled: boolean; status?: string; article_count?: number;
  allow_undated?: boolean;
  recheck_requested_at?: string; discovered_from?: string; verified_at?: string;
  recent_articles?: CandidateArticle[];
  health?: FeedHealth;
  validation_status?: 'verified' | 'error' | 'empty';
  checked_at?: string; expires_at?: string; validation_error?: string; health_checked_at?: string;
}
export interface Article {
  id: string; source_id: string; source_ids?: string[]; title: string;
  url: string; published_at: string; date_inferred?: boolean; summary?: string; image_url?: string; legacy_ids?: string[];
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
export interface Catalog {
  sources: Source[];
  articles: Article[];
  generatedAt: string;
  sourceAliases: Record<string, string>;
}
type Manifest = {snapshot_id: string; generated_at: string; files: Record<string, {sha256: string; bytes: number}>};
type SnapshotIdentity = {manifestUrl: string; snapshotId: string; generatedAt: string; files: string};
// Only reuse objects that this module fully verified during this page session.
const verifiedCatalogs = new WeakMap<Catalog, SnapshotIdentity>();

export async function loadCatalog(base: string, previous?: Catalog): Promise<Catalog> {
  const metaUrl = new URL('./api/v1/meta.json', base);
  const apiRoot = new URL('./api/', base);
  function withinApi(url: URL) {
    if (url.origin !== metaUrl.origin || !url.pathname.startsWith(apiRoot.pathname) || url.username || url.password) throw Error('数据地址不合法');
  }
  const meta = await readJson<{ snapshot_id: string; snapshot_endpoint: string; generated_at: string }>(metaUrl);
  if (!meta.snapshot_id || !meta.snapshot_endpoint || !Number.isFinite(Date.parse(meta.generated_at))) throw Error('数据结构不正确');
  const manifestUrl = new URL(meta.snapshot_endpoint, metaUrl);
  withinApi(manifestUrl);
  const manifest = await readJson<Manifest>(manifestUrl);
  if (manifest.snapshot_id !== meta.snapshot_id || manifest.generated_at !== meta.generated_at) throw Error('数据版本变化，请重试');
  const names = ['feeds.json', 'articles.json'];
  for (const name of names) {
    const file = manifest.files?.[name];
    if (!file || !Number.isSafeInteger(file.bytes) || file.bytes < 0 || !/^[a-f0-9]{64}$/.test(file.sha256)) throw Error('数据校验信息不正确');
  }
  const identity: SnapshotIdentity = {
    manifestUrl: manifestUrl.href, snapshotId: meta.snapshot_id, generatedAt: meta.generated_at,
    files: JSON.stringify(names.map(name => [name, manifest.files[name].bytes, manifest.files[name].sha256])),
  };
  const prior = previous && verifiedCatalogs.get(previous);
  if (prior && prior.manifestUrl === identity.manifestUrl && prior.snapshotId === identity.snapshotId &&
      prior.generatedAt === identity.generatedAt && prior.files === identity.files) return previous!;
  async function verified<T>(name: string): Promise<T> {
    const url = new URL(name, manifestUrl);
    withinApi(url);
    const response = await fetch(url, {cache: 'no-cache'});
    if (!response.ok) throw Error('快照读取失败');
    const bytes = await response.arrayBuffer();
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), value => value.toString(16).padStart(2, '0')).join('');
    if (bytes.byteLength !== manifest.files[name].bytes || hash !== manifest.files[name].sha256) throw Error('数据校验失败');
    return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)) as T;
  }
  const [feeds, entries] = await Promise.all([verified<{feeds: Source[]; generated_at: string; source_aliases?: Record<string,string>}>('feeds.json'), verified<{articles: Article[]; generated_at: string}>('articles.json')]);
  if (feeds.generated_at !== meta.generated_at || entries.generated_at !== meta.generated_at || !Array.isArray(feeds.feeds) || !Array.isArray(entries.articles)) throw Error('数据结构不正确');
  const catalog: Catalog = {sources: feeds.feeds.filter(source => source.enabled !== false), articles: entries.articles.filter(article => webUrl(article.url)), generatedAt: meta.generated_at, sourceAliases: feeds.source_aliases ?? {}};
  verifiedCatalogs.set(catalog, identity);
  return catalog;
}
