import {webUrl, type FeedHealth, type Source} from './catalog.ts';

const stamp = (value?: string) => value && Number.isFinite(Date.parse(value))
  ? new Date(value).toLocaleString('zh-CN', {timeZone:'Asia/Shanghai',month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'}) : '未知';
const count = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
const reasons: Record<string, string> = {
  missing_date:'缺少日期', future_date:'日期在未来', invalid_url:'链接无效', missing_title:'缺少标题',
  empty_title:'缺少标题', duplicate:'重复链接', old_article:'超出保留期',
  missing_or_invalid_date:'日期缺失或无效', unsafe_or_missing_url:'链接缺失或不安全', duplicate_url:'重复链接', outside_retention:'超出保留期',
};

export function SourceQuality({health}: {health?: FeedHealth}) {
  if (!health) return null;
  const drops = Object.entries(health.drop_reasons ?? {}).filter(([, value]) => count(value) && value > 0);
  return <div className="mt-3 text-xs leading-6 text-muted">
    <p>{count(health.raw_entry_count) ? `原始 ${health.raw_entry_count} 条` : '原始条目数未知'}
      {count(health.valid_article_count) ? ` · 可读 ${health.valid_article_count} 篇` : ''}
      {count(health.new_article_count) ? ` · 本次新增 ${health.new_article_count} 篇` : ''}</p>
    {health.valid_article_count === 0 ? <p>请求已完成，暂无可读文章。可查看丢弃原因后再判断。</p> : null}
    {health.new_article_count === 0 && health.valid_article_count !== 0 ? <p>本次没有新文章，低频更新仍属正常。</p> : null}
    {health.last_new_article_at ? <p>最近发现新文章 {stamp(health.last_new_article_at)}</p> : null}
    {drops.length ? <details><summary className="cursor-pointer">查看未收录原因</summary><ul>{drops.map(([reason, total]) => <li key={reason}>{reasons[reason] ?? reason}：{total}</li>)}</ul></details> : null}
  </div>;
}

export function CandidatePreview({source, now = Date.now()}: {source: Source; now?: number}) {
  const expired = !!source.expires_at && Number.isFinite(Date.parse(source.expires_at)) && Date.parse(source.expires_at) <= now;
  const stale = expired || source.validation_status === 'error' || source.validation_status === 'empty';
  const samples = (Array.isArray(source.recent_articles) ? source.recent_articles : [])
    .filter(article => article && typeof article.title === 'string' && webUrl(article.url)).slice(0, 3);
  return <section className="mt-4 rounded-md bg-soft p-3" aria-label={`${source.title} 的内容预览`}>
    <p className={stale ? 'text-xs leading-6 text-red-800' : 'text-xs leading-6 text-muted'}>
      {source.validation_status === 'error' ? '最近复查失败，以下保留上次通过的样文。'
        : source.validation_status === 'empty' ? '最近复查暂无可读文章，以下可能是较早样文。'
        : expired ? '验证已过期，等待下一轮复查。'
        : source.validation_status === 'verified' ? '最近验证可用，加入后仍需提交公共配置。'
        : '旧候选尚无内容预览，下一轮复查后补齐。'}
      {source.checked_at ? ` 检查时间 ${stamp(source.checked_at)}` : ''}
    </p>
    {source.validation_error ? <p className="mt-1 break-words text-xs text-muted">{source.validation_error}</p> : null}
    {source.health_checked_at ? <p className="mt-2 text-xs text-muted">以下质量统计来自 {stamp(source.health_checked_at)}</p> : null}
    <SourceQuality health={source.health}/>
    {samples.length ? <ul className="mt-2 space-y-2">{samples.map((article, index) => <li key={`${article.url}:${index}`}>
      <a className="break-words text-sm underline underline-offset-4" href={article.url} target="_blank" rel="noopener noreferrer">{article.title}</a>
      <span className="ml-2 text-xs text-muted">{article.date_inferred ? '首次发现' : '发布于'} {stamp(article.published_at)}</span>
    </li>)}</ul> : <p className="mt-2 text-xs text-muted">暂无样文。可先查看发现出处，再决定是否加入。</p>}
  </section>;
}

export interface UpstreamFailureGroup { host: string; http_status?: number; count: number; archived_count?: number; source_ids?: string[] }
export function UpstreamFailures({groups, onSelect}: {groups: UpstreamFailureGroup[]; onSelect: (host: string) => void}) {
  const visible = groups.filter(group => typeof group.host === 'string' && count(group.count) && group.count >= 2).slice(0, 20);
  if (!visible.length) return null;
  return <section className="my-4 rounded-md bg-soft p-4" aria-label="共享上游异常">
    <h2 className="text-sm font-semibold">多个来源出现相同上游异常</h2>
    <p className="mt-1 text-xs leading-6 text-muted">这些来源使用同一个 RSS 主机；该主机出错不表示每个原站都已停更。</p>
    <ul className="mt-2 space-y-2">{visible.map(group => <li key={`${group.host}:${group.http_status ?? 'unknown'}`} className="flex flex-wrap items-center gap-2 text-xs">
      <span className="break-all">{group.host} · {group.count} 个来源{count(group.http_status) ? ` · HTTP ${group.http_status}` : ' · 请求异常'}</span>
      <button className="underline underline-offset-4" onClick={() => onSelect(group.host)}>查看这些来源</button>
    </li>)}</ul>
  </section>;
}
