import {sourceIds, webUrl, type Article, type Source} from './catalog.ts';

export interface SavedArticle extends Article { saved_sources: Source[] }

/** Bookmarks own their content; the rolling public catalog can expire independently. */
export class ReadingLibrary {
  readonly read = new Set<string>();
  readonly saved = new Set<string>();
  readonly bookmarks = new Map<string, SavedArticle>();
  /** Parsing is deliberately loss-aware. Storage must not write a salvaged view back silently. */
  readonly issues: string[] = [];

  constructor(value: unknown = {}) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      this.issues.push('阅读记录不是对象'); return;
    }
    const data = value as Record<string, unknown>;
    if (data.version !== undefined && data.version !== 1 && data.version !== 2) this.issues.push('阅读记录版本不受支持');
    for (const key of ['read', 'saved'] as const) {
      if (data[key] === undefined) continue;
      if (!Array.isArray(data[key])) { this.issues.push(`${key} 不是列表`); continue; }
      for (const id of data[key]) {
        if (typeof id === 'string' && id) this[key].add(id);
        else this.issues.push(`${key} 包含损坏的 ID`);
      }
    }
    if (data.bookmarks !== undefined && !Array.isArray(data.bookmarks)) this.issues.push('收藏内容不是列表');
    if (Array.isArray(data.bookmarks)) for (const item of data.bookmarks) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) { this.issues.push('收藏记录不是对象'); continue; }
      const article = item as SavedArticle;
      if (typeof article.id !== 'string' || !article.id || typeof article.title !== 'string' || typeof article.url !== 'string' || !webUrl(article.url) ||
          typeof article.published_at !== 'string' || !Number.isFinite(Date.parse(article.published_at)) || typeof article.source_id !== 'string' || !article.source_id) {
        this.issues.push('收藏记录的必需字段损坏'); continue;
      }
      if (this.bookmarks.has(article.id)) { this.issues.push('收藏记录的 ID 重复'); continue; }
      const sources: Source[] = [];
      if (article.saved_sources !== undefined && !Array.isArray(article.saved_sources)) this.issues.push('收藏来源列表损坏');
      if (Array.isArray(article.saved_sources)) for (const source of article.saved_sources) {
        if (source && typeof source.id === 'string' && typeof source.title === 'string' && typeof source.category === 'string') sources.push({...source});
        else this.issues.push('收藏来源记录损坏');
      }
      const ids = (value: unknown) => {
        if (value === undefined) return undefined;
        if (!Array.isArray(value)) { this.issues.push('收藏关联 ID 列表损坏'); return undefined; }
        if (value.some(id => typeof id !== 'string')) this.issues.push('收藏关联 ID 损坏');
        return value.filter((id): id is string => typeof id === 'string');
      };
      const clean: SavedArticle = {...article, source_ids: ids(article.source_ids), legacy_ids: ids(article.legacy_ids), saved_sources: sources};
      for (const key of ['summary', 'image_url'] as const) if (clean[key] !== undefined && typeof clean[key] !== 'string') {
        this.issues.push(`收藏 ${key} 损坏`); delete clean[key];
      }
      if (clean.date_inferred !== undefined && typeof clean.date_inferred !== 'boolean') { this.issues.push('收藏日期标记损坏'); delete clean.date_inferred; }
      this.bookmarks.set(article.id, clean);
      this.saved.add(article.id);
    }
  }

  /** Keep Set/Map identities stable for reader views and indexes. */
  replace(value: ReadingLibrary) {
    this.read.clear(); for (const id of value.read) this.read.add(id);
    this.saved.clear(); for (const id of value.saved) this.saved.add(id);
    this.bookmarks.clear(); for (const [id, article] of value.bookmarks) this.bookmarks.set(id, article);
    this.issues.splice(0, this.issues.length, ...value.issues);
  }

  reconcile(articles: Article[], sources: Source[]) {
    for (const article of articles) {
      const aliases = article.legacy_ids ?? [];
      if (aliases.some(id => this.read.has(id))) this.read.add(article.id);
      if (!this.saved.has(article.id) && !aliases.some(id => this.saved.has(id))) continue;
      for (const id of aliases) if (id !== article.id) { this.saved.delete(id); this.bookmarks.delete(id); }
      this.saved.add(article.id);
      // Keep the content and categories selected at the time of saving.
      if (!this.bookmarks.has(article.id)) this.bookmarks.set(article.id, this.snapshot(article, sources));
    }
  }

  private snapshot(article: Article, sources: Source[]): SavedArticle {
    return {...article, saved_sources: sources.filter(source => sourceIds(article).includes(source.id)).map(source => ({...source}))};
  }

  toggleSaved(article: Article, sources: Source[]) {
    if (this.saved.has(article.id)) { this.saved.delete(article.id); this.bookmarks.delete(article.id); }
    else { this.saved.add(article.id); this.bookmarks.set(article.id, this.snapshot(article, sources)); }
  }

  restoreSaved(article: SavedArticle) {
    // Undo one removal without overwriting saves made in the meantime.
    if (this.saved.has(article.id)) return;
    this.saved.add(article.id);
    this.bookmarks.set(article.id, article);
  }

  markUnread(article: Article) {
    this.read.delete(article.id);
    for (const id of article.legacy_ids ?? []) this.read.delete(id);
  }

  get missingBookmarks() { return [...this.saved].filter(id => !this.bookmarks.has(id)).length; }
  toJSON() { return {version: 2, read: [...this.read], saved: [...this.saved], bookmarks: [...this.bookmarks.values()]}; }
}

export function bookmarkSources(bookmarks: SavedArticle[]): Source[] {
  return [...new Map(bookmarks.flatMap(article => article.saved_sources).map(source => [source.id, source])).values()];
}
