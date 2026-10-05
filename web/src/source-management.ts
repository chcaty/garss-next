import type {Source} from './catalog.ts';
export const sourceFields = ['title','feed_url','description','category','enabled','allow_undated','recheck_requested_at','discovered_from','verified_at'] as const;
export type SourceField = typeof sourceFields[number];
export const fieldLabels: Record<SourceField,string> = {title:'名称',feed_url:'RSS 地址',description:'简介',category:'分类',enabled:'参与公共采集',allow_undated:'允许推断时间',recheck_requested_at:'复查请求',discovered_from:'发现出处',verified_at:'验证时间'};
export const fieldValue = (value:unknown) => value===undefined||value===''?'未设置':typeof value==='boolean'?value?'是':'否':String(value);
export interface SourceChange {id:string;title:string;kind:string;fields:{key:SourceField;before:unknown;after:unknown}[]}
export function duplicateUrls(sources: Source[]): Set<string> {
  const seen = new Map<string,string>(), duplicates = new Set<string>();
  for (const source of sources) {
    let key=source.feed_url;try {const url=new URL(key);url.hash='';key=url.href;}catch{}
    const prior=seen.get(key);if(prior!==undefined){duplicates.add(prior);duplicates.add(source.feed_url);}else seen.set(key,source.feed_url);
  }
  return duplicates;
}
export function matchesSource(source: Source, query: string, category: string): boolean {
  return (category === 'all' || source.category === category) &&
    `${source.title} ${source.description} ${source.category} ${source.feed_url}`.toLowerCase().includes(query.trim().toLowerCase());
}
export function changes(before: Source[], after: Source[]): SourceChange[] {
  const previous = new Map(before.map(source => [source.id,source])), current = new Map(after.map(source => [source.id,source]));
  const result:SourceChange[] = [];
  for (const source of after) {const old = previous.get(source.id);
    const fields=sourceFields.filter(key=>source[key]!==old?.[key]).map(key=>({key,before:old?.[key],after:source[key]}));
    if (!old || fields.length) result.push({id:source.id,title:source.title,kind:old?'修改':'新增',fields});
  }
  for (const source of before) if (!current.has(source.id)) result.push({id:source.id,title:source.title,kind:'删除',fields:sourceFields.filter(key=>source[key]!==undefined).map(key=>({key,before:source[key],after:undefined}))});
  return result;
}
