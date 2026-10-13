import {sourceIds, type Article, type Source} from './catalog.ts';
import {windowStart, type ReadingWindow} from './reading-filter.ts';

export interface IndexedFilters {
  query?: string;
  source?: string;
  category?: string;
  window?: ReadingWindow;
  oldest?: boolean;
  unreadOnly?: boolean;
  read?: ReadonlySet<string>;
  now?: number;
}

type Entry = {
  article: Article;
  ids: ReadonlySet<string>;
  categories: ReadonlySet<string>;
  search: string;
  timestamp: number;
};

/** Build once per immutable catalog/bookmark revision, not per keystroke. */
export class ReadingIndex {
  private readonly newest: Entry[];
  private readonly oldest: Entry[];

  constructor(articles: readonly Article[], sources: readonly Source[]) {
    const byId = new Map(sources.map(source => [source.id, source]));
    const entries = articles.map(article => {
      const ids = new Set(sourceIds(article));
      // Saved articles keep the names and categories from the time of saving.
      const savedSources = 'saved_sources' in article && Array.isArray(article.saved_sources)
        ? article.saved_sources as Source[] : undefined;
      const metadata = savedSources ? new Map(savedSources.map(source => [source.id, source])) : byId;
      const memberships = [...ids];
      return {
        article,
        ids,
        categories: new Set(memberships.map(id => metadata.get(id)?.category).filter((value): value is string => value !== undefined)),
        search: `${article.title} ${article.summary ?? ''} ${memberships.map(id => metadata.get(id)?.title ?? id).join(' ')}`.toLowerCase(),
        timestamp: Date.parse(article.published_at),
      };
    });
    // Independent stable sorts keep equal-date articles in original order in both directions.
    this.newest = [...entries].sort((a, b) => b.timestamp - a.timestamp);
    this.oldest = [...entries].sort((a, b) => a.timestamp - b.timestamp);
  }

  select(filters: IndexedFilters = {}): Article[] {
    const needle = (filters.query ?? '').trim().toLowerCase();
    const window = filters.window ?? 'all';
    const now = filters.now ?? Date.now();
    const start = windowStart(window, now);
    return (filters.oldest ? this.oldest : this.newest)
      .filter(entry =>
        (!filters.source || entry.ids.has(filters.source)) &&
        (!filters.category || entry.categories.has(filters.category)) &&
        (window === 'all' || entry.timestamp >= start && entry.timestamp <= now) &&
        (!needle || entry.search.includes(needle)) &&
        (!filters.unreadOnly || !filters.read?.has(entry.article.id)))
      .map(entry => entry.article);
  }
}
