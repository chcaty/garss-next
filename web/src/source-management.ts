import type {Source} from './catalog.ts';
export function duplicateUrls(sources: Source[]): Set<string> {
  const seen = new Set<string>(), duplicates = new Set<string>();
  for (const source of sources) {if (seen.has(source.feed_url)) duplicates.add(source.feed_url); seen.add(source.feed_url);}
  return duplicates;
}
export function matchesSource(source: Source, query: string, category: string): boolean {
  return (category === 'all' || source.category === category) &&
    `${source.title} ${source.description} ${source.category} ${source.feed_url}`.toLowerCase().includes(query.trim().toLowerCase());
}
export function changes(before: Source[], after: Source[]): {id:string;title:string;kind:string}[] {
  const previous = new Map(before.map(source => [source.id,source])), current = new Map(after.map(source => [source.id,source]));
  const result = [];
  for (const source of after) {const old = previous.get(source.id);
    if (!old) result.push({id:source.id,title:source.title,kind:'新增'});
    else if (['title','feed_url','description','category','enabled'].some(key => old[key as keyof Source] !== source[key as keyof Source])) result.push({id:source.id,title:source.title,kind:'修改'});
  }
  for (const source of before) if (!current.has(source.id)) result.push({id:source.id,title:source.title,kind:'删除'});
  return result;
}
