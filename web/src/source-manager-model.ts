import type {Source, SourceConfig} from './catalog.ts';
const keys = ['title','description','category','feed_url','enabled','recheck_requested_at','discovered_from'] as const;
export function rebaseDraft(base: SourceConfig, draft: SourceConfig, remote: SourceConfig): SourceConfig {
  const prior = new Map(base.sources.map(source => [source.id,source]));
  const local = new Map(draft.sources.map(source => [source.id,source]));
  const sources = remote.sources.filter(source => !prior.has(source.id) || local.has(source.id)).map(source => {
    const before = prior.get(source.id), edited = local.get(source.id);
    if (!before || !edited) return source;
    const merged = {...source};
    for (const key of keys) if (edited[key] !== before[key]) Object.assign(merged,{[key]:edited[key]});
    return merged;
  });
  const ids = new Set(sources.map(source => source.id));
  for (const source of draft.sources) if (!ids.has(source.id) && (!prior.has(source.id) || keys.some(key => source[key] !== prior.get(source.id)![key]))) sources.push(source);
  return {...remote,sources};
}
export interface Health {
  status: 'active'|'pending'|'error'|'archived'; failures:number; last_error?:string;
  first_failed_at?:string; archived_at?:string; last_checked_at?:string; last_success_at?:string;
  signature?:[string,string];
}
export function archived(source: Source, state?: Health): boolean {
  return state?.status === 'archived' && (!state.signature || state.signature[0] === source.feed_url && state.signature[1] === (source.recheck_requested_at ?? ''));
}
export function exportOpml(sources: Source[]): string {
  const xml = document.implementation.createDocument('', 'opml', null); xml.documentElement.setAttribute('version','2.0');
  const body = xml.createElement('body'); xml.documentElement.append(body);
  for (const source of sources) {const outline=xml.createElement('outline');
    for (const [key,value] of Object.entries({type:'rss',text:source.title,title:source.title,xmlUrl:source.feed_url,category:source.category,description:source.description})) outline.setAttribute(key,value);
    body.append(outline);
  }
  return new XMLSerializer().serializeToString(xml);
}
export function importOpml(content: string, existing: Source[]): Source[] {
  const xml = new DOMParser().parseFromString(content,'text/xml');
  if (xml.querySelector('parsererror') || /<!DOCTYPE|<!ENTITY/i.test(content)) throw Error('OPML 格式不正确或包含不支持的声明');
  const urls = new Set(existing.map(source => source.feed_url)); const result:Source[]=[];
  for (const node of xml.querySelectorAll('outline[xmlUrl]')) {
    const url=node.getAttribute('xmlUrl')!.trim();
    try {const parsed=new URL(url); if (!['http:','https:'].includes(parsed.protocol) || parsed.username || parsed.password || urls.has(url)) continue;} catch {continue;}
    urls.add(url); result.push({id:`user-${crypto.randomUUID()}`,title:node.getAttribute('title')?.trim() || node.getAttribute('text')?.trim() || url,feed_url:url,category:node.getAttribute('category')?.trim() || '导入来源',description:node.getAttribute('description') ?? '',enabled:true});
    if (result.length >= 500) break;
  }
  return result;
}
