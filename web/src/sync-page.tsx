import { useState } from 'react';
import { Shell } from './shell.tsx';
import { type Source } from './catalog.ts';
import { type Health } from './source-manager-model.ts';
import { syncSourceStatus, filterSyncSources, type Run, type Discovery } from './sync-model.ts';
import { usePublished } from './use-published.ts';
import { SectionState, SyncOverview, SourceStatusSection, SyncHistory, SyncDiscovery, actions } from './sync-sections.tsx';
export function Sync() {
  const meta = usePublished<{
    generated_at: string;
  }>('./api/v1/meta.json');
  const feeds = usePublished<{
    feeds: Source[];
  }>('./api/v1/feeds.json');
  const states = usePublished<{
    sources: Record<string, Health>;
  }>('./api/v1/source-state.json');
  const runs = usePublished<{
    runs: Run[];
  }>('./api/v1/sync.json');
  const discovery = usePublished<Discovery>('./api/v1/source-discovery.json');
  const [filter, setFilter] = useState('error');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const data = feeds.value ? {
    generated: meta.value?.generated_at,
    feeds: feeds.value.feeds,
    states: states.value?.sources ?? {},
    runs: runs.value?.runs ?? [],
  } : undefined;
  const refresh = () => {
    meta.reload();
    feeds.reload();
    states.reload();
    runs.reload();
    discovery.reload();
  };
  const status = (source: Source) => syncSourceStatus(source, data?.states ?? {});
  const names: Record<string, string> = {
    ok: '采集正常',
    error: '采集异常',
    archived: '已归档',
    disabled: '已停用',
    pending: states.value ? '等待采集' : '状态未知',
  };
  const entries = filterSyncSources(data?.feeds ?? [], data?.states ?? {}, filter, query);
  const pages = Math.max(1, Math.ceil(entries.length / 20));
  const current = Math.min(page, pages);
  const latest = data?.runs[0];
  return <>
    <Shell current="sync" />
    <main className="mx-auto max-w-7xl px-4 py-8 sm:px-8 sm:py-10">
      <div className="page-intro">
        <div>
          <h1 className="page-title">同步记录</h1>
          <p className="mt-3 text-sm leading-6 text-muted">确认信息何时更新，查看每个来源的采集情况。</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button className="btn" onClick={refresh}>刷新状态</button>
          <a className="btn" href={actions} target="_blank" rel="noopener noreferrer">采集任务与日志</a>
        </div>
      </div>

      <SectionState state={meta} label="发布时间" />
      <SectionState state={feeds} label="来源目录" />

      {!data ? null : <>

        <SyncOverview data={data} statesKnown={Boolean(states.value)} latest={latest} status={status} />

        <SectionState state={states} label="来源状态" />

        <SourceStatusSection
          entries={entries} current={current} pages={pages}
          query={query} filter={filter} names={names}
          health={data.states} statesKnown={Boolean(states.value)}
          setQuery={setQuery} setFilter={setFilter} setPage={setPage}
          status={status}
        />

        <SyncHistory runs={runs} history={data.runs} />

        <SyncDiscovery discovery={discovery} />
      </>}

    </main>
  </>;
}
