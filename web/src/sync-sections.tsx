import type { Source } from './catalog.ts';
import type { Health } from './source-manager-model.ts';
import type { Run, Discovery, SyncSourceStatus } from './sync-model.ts';
import type { PublishedSection } from './use-published.ts';
export const actions = 'https://github.com/chcaty/garss-next/actions';
const stamp = (value?: string) => value ? new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Shanghai' }).format(new Date(value)) : '暂无记录';
export function SectionState({ state, label }: {
  state: {
    loading: boolean;
    error: boolean;
    reload: () => void;
  };
  label: string;
}) {
  return state.loading ? <p role="status" className="py-4 text-sm text-muted">正在读取{label}…</p> : state.error ? <div role="status" className="my-4 flex flex-wrap items-center gap-3 text-sm text-muted">
    <span>
      {label}读取失败，数量暂时未知。已显示的数据保留。</span>
    <button className="btn" onClick={state.reload}>重试{label}
    </button>
  </div> : null;
}
export function SyncOverview({ data, statesKnown, latest, status }: {
  data: {
    generated?: string;
    feeds: Source[];
  };
  statesKnown: boolean;
  latest?: Run;
  status: (source: Source) => SyncSourceStatus;
}) {
  return <section aria-label="最近同步" className="border-y border-line py-6">
    <div className="flex flex-wrap items-center justify-between gap-5">
      <div>
        <h2 className="text-lg font-semibold">最近已发布采集</h2>
        <p className="mt-2 text-sm text-muted">
          {data.generated ? '北京时间 ' + stamp(data.generated) : '发布时间未知'}
        </p>
      </div>
      <p className="text-sm text-muted">正常 <strong className="text-ink">
        {statesKnown ? data.feeds.filter(source => status(source) === 'ok').length : '—'}
      </strong> · 异常 <strong className="text-red-800">
          {statesKnown ? data.feeds.filter(source => status(source) === 'error').length : '—'}
        </strong> · 归档 <strong className="text-ink">
          {statesKnown ? data.feeds.filter(source => status(source) === 'archived').length : '—'}
        </strong>
      </p>
    </div>
    <details className="mt-4 text-sm text-muted">
      <summary className="min-h-11 cursor-pointer py-3">采集计划与发布说明</summary>
      <p className="text-xs leading-6">每天北京时间 06:00、13:00、17:00、22:00 计划采集，实际启动时间可能受 GitHub 排队影响。{latest ? `本次检查 ${latest.checked} 个来源，耗时 ${latest.duration_seconds} 秒，发布 ${latest.article_count} 篇去重文章。` : ''}
      </p>
      <p className="mt-1 text-xs leading-6 text-muted">此处展示已发布的数据；运行中或未发布的失败任务，请查看采集日志。</p>
    </details>
  </section>;
}
function SourceStatusRow({ source, state, condition, statesKnown, names }: { source: Source; state?: Health; condition: SyncSourceStatus; statesKnown: boolean; names: Record<string, string> }) {
  return <article className="border-b border-line py-4" key={source.id}>
    <div className="flex flex-wrap items-center justify-between gap-2">
      <h3 className="text-sm font-semibold">
        {source.title}
      </h3>
      <span className={condition === 'error' ? 'text-xs text-red-800' : 'text-xs text-muted'}>
        {statesKnown ? names[condition] : '采集状态未知'}
      </span>
    </div>
    <p className="mt-2 text-xs leading-6 text-muted">
      {source.category} · {source.article_count ?? 0} 篇保留文章 · 最近检查 {stamp(state?.last_checked_at)}
    </p>
    {state?.last_error ? <p className="mt-2 break-words text-xs leading-6 text-red-800">
      {state.last_error}
    </p> : null}
    {state?.last_success_at ? <p className="mt-1 text-xs text-muted">最近成功 {stamp(state.last_success_at)}
    </p> : null}
  </article>;
}

export function SourceStatusSection({ entries, current, pages, query, filter, names, health, statesKnown, setQuery, setFilter, setPage, status }: {
  entries: Source[];
  current: number;
  pages: number;
  query: string;
  filter: string;
  names: Record<string, string>;
  health: Record<string, Health>;
  statesKnown: boolean;
  setQuery: (value: string) => void;
  setFilter: (value: string) => void;
  setPage: (value: number) => void;
  status: (source: Source) => SyncSourceStatus;
}) {
  return <section className="mt-8" aria-labelledby="source-status-title">
    <div className="flex flex-wrap items-center justify-between gap-4">
      <h2 id="source-status-title" className="text-xl font-semibold">来源采集情况</h2>
      <a className="text-sm text-brand underline underline-offset-4" href="./sources.html">维护订阅源</a>
    </div>
    <div className="my-5 grid gap-3 sm:grid-cols-2">
      <label className="text-xs text-muted">查找来源<input className="field mt-2" type="search" value={query} placeholder="名称、分类或 RSS 地址" onChange={event => { setQuery(event.target.value); setPage(1); }} />
      </label>
      <label className="text-xs text-muted">采集状态<select aria-label="采集状态" className="field mt-2" value={filter} onChange={event => { setFilter(event.target.value); setPage(1); }}>
        {[['all', '全部状态'], ...Object.entries(names)].map(([value, label]) => <option key={value} value={value}>
          {label}
        </option>)}
      </select>
      </label>
    </div>
    <p className="mb-3 text-xs text-muted">
      {entries.length} 个来源</p>
    <div className="border-t border-line">
      {entries.slice((current - 1) * 20, current * 20).map(source => (
        <SourceStatusRow key={source.id} source={source} state={health[source.id]} condition={status(source)} statesKnown={statesKnown} names={names} />
      ))}
      {!entries.length ? <div className="py-8 text-sm text-muted">
        <p>
          {!statesKnown ? '来源状态尚未读取成功，请重试后查看异常。' : filter === 'error' && !query ? '当前没有采集异常的来源。' : '没有匹配的来源，调整关键词或状态筛选。'}
        </p>
        <button className="btn mt-3" onClick={() => { setFilter('all'); setQuery(''); setPage(1); }}>查看全部来源</button>
      </div> : null}
    </div>
    <nav aria-label="状态列表分页" className="my-5 flex items-center justify-between">
      <button className="btn" disabled={current === 1} onClick={() => setPage(current - 1)}>上一页</button>
      <span className="text-xs text-muted">第 {current} / {pages} 页</span>
      <button className="btn" disabled={current === pages} onClick={() => setPage(current + 1)}>下一页</button>
    </nav>
  </section>;
}
export function SyncHistory({ runs, history }: {
  runs: PublishedSection<{
    runs: Run[];
  }>;
  history: Run[];
}) {
  return <section className="mt-10 border-t border-line pt-6">
    <h2 className="text-xl font-semibold">采集批次</h2>
    <SectionState state={runs} label="采集历史" />
    <p className="mt-2 text-xs leading-6 text-muted">保留最近 30 次已发布记录，成功数包含正常但没有新文章的来源。</p>
    {history.length ? <div className="mt-5 divide-y divide-line">
      {history.map(run => <div key={run.generated_at} className="flex flex-wrap items-center justify-between gap-3 py-4 text-sm">
        <div>
          <p className="font-medium">
            {stamp(run.generated_at)}
          </p>
          <p className="mt-2 text-xs text-muted">正常 {run.succeeded} / 异常 {run.failed} · {run.article_count} 篇文章 · {run.duration_seconds} 秒</p>
        </div>
        {/^\d+$/.test(run.workflow_run_id ?? '') ? <a className="btn" href={`${actions}/runs/${run.workflow_run_id}`} target="_blank" rel="noopener noreferrer">本次日志</a> : null}
      </div>)}
    </div> : <p className="mt-5 text-sm text-muted">
      {runs.value ? '历史记录从新版采集发布后开始积累。' : ''}
    </p>}
  </section>;
}
export function SyncDiscovery({ discovery }: {
  discovery: PublishedSection<Discovery>;
}) {
  const data = discovery.value ?? {};
  return <section className="mt-10 border-t border-line py-6">
    <h2 className="text-xl font-semibold">新来源发现</h2>
    <SectionState state={discovery} label="发现状态" />
    <a className="mt-3 inline-block text-sm text-brand underline" href="./sources.html#provenance">查看发现出处</a>
    <p className="mt-3 text-sm leading-7 text-muted">最近发现检查 {stamp(data.last_attempt_at)} · 待确认 {discovery.value ? data.candidates?.length ?? 0 : '—'} 个 · 目录异常 {discovery.value ? data.directory_errors?.length ?? 0 : '—'} 个</p>
    <p className="mt-2 text-xs leading-6 text-muted">外部目录每 7 天检查一次；只有验证通过的候选才会进入订阅源页面，加入草稿，在 GitHub 确认并通过校验后参与采集。</p>
    {data.directory_errors?.map(item => <p key={item.directory} className="mt-2 break-words text-xs text-red-800">
      {item.directory}：{item.error}
    </p>)}
  </section>;
}
