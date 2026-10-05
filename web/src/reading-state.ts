import {sourceIds, webUrl, type Article, type Source} from './catalog.ts';

export interface SavedArticle extends Article { saved_sources: Source[] }

/** Bookmarks own their content; the rolling public catalog can expire independently. */
export class ReadingLibrary {
  readonly read = new Set<string>();
  readonly saved = new Set<string>();
  readonly bookmarks = new Map<string, SavedArticle>();

  constructor(value: unknown = {}) {
    const data = value && typeof value === 'object' ? value as Record<string, unknown> : {};
    for (const key of ['read', 'saved'] as const) {
      if (Array.isArray(data[key])) for (const id of data[key]) if (typeof id === 'string') this[key].add(id);
    }
    if (Array.isArray(data.bookmarks)) for (const item of data.bookmarks) {
      if (!item || typeof item !== 'object') continue;
      const article = item as SavedArticle;
      if (typeof article.id !== 'string' || typeof article.title !== 'string' || !webUrl(article.url) ||
          !Number.isFinite(Date.parse(article.published_at)) || typeof article.source_id !== 'string') continue;
      const sources = Array.isArray(article.saved_sources) ? article.saved_sources.filter(source =>
        source && typeof source.id === 'string' && typeof source.title === 'string' && typeof source.category === 'string') : [];
      const ids = (value:unknown) => Array.isArray(value) ? value.filter(id=>typeof id==='string') : undefined;
      this.bookmarks.set(article.id, {...article, source_ids: ids(article.source_ids), legacy_ids: ids(article.legacy_ids), saved_sources: sources});
      this.saved.add(article.id);
    }
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
