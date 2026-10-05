import type { Source } from './catalog.ts';
import type { Health } from './source-manager-model.ts';

export type Run = {
  generated_at: string;
  finished_at?: string;
  duration_seconds: number;
  checked: number;
  succeeded: number;
  failed: number;
  archived: number;
  article_count: number;
  workflow_run_id?: string;
};
export type Discovery = {
  last_attempt_at?: string;
  candidates?: unknown[];
  directory_errors?: { directory: string; error: string }[];
};
export type SyncSourceStatus = 'archived' | 'disabled' | 'error' | 'ok' | 'pending';

export function syncSourceStatus(source: Source, health: Record<string, Health>): SyncSourceStatus {
  if(health[source.id]?.status === 'archived') return 'archived';
  if(!source.enabled) return 'disabled';
  if(source.status === 'error' || health[source.id]?.status === 'error') return 'error';
  return source.status === 'ok' ? 'ok' : 'pending';
}

export function filterSyncSources(feeds: Source[], health: Record<string, Health>, filter: string, query: string): Source[] {
  const needle = query.trim().toLowerCase();
  return feeds.filter(source =>
    (filter === 'all' || syncSourceStatus(source, health) === filter) &&
    `${source.title} ${source.category} ${source.feed_url}`.toLowerCase().includes(needle));
}
