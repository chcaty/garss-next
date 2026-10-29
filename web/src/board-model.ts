import {filterArticles, sourceIds, type Article, type Source} from './catalog.ts';

export const typeLabels: Record<string,string> = {article:'文章',topic:'话题',video:'视频',repository:'项目',item:'影视'};
export interface BoardFilters {query:string;source:string;category:string;kind:string;onlyNew:boolean;savedOnly?:boolean}
export interface SourceGroup {source:Source;articles:Article[];newIds:Set<string>}
export interface FeedEntry {source:Source;article:Article;fresh:boolean}

export const isChronologicalFeed=(source:Source)=>!source.adapter||source.adapter==='rss';
export function observation(article:Article,source:string) {return article.observations?.[source]??article.metadata??{};}
export function sourceGroups(articles:Article[],sources:Source[],filters:BoardFilters):SourceGroup[] {
  const entries=filterArticles(articles,filters.query,filters.source,sources)
    .filter(article=>filters.kind==='all'||(article.content_type??'article')===filters.kind);
  const bySource=new Map<string,Article[]>();
  for(const article of entries) for(const id of new Set(sourceIds(article))) {
    const list=bySource.get(id)??[];list.push(article);bySource.set(id,list);
  }
  return sources.filter(source=>(filters.savedOnly||source.status!=='error')&&(!filters.source||source.id===filters.source)&&(!filters.category||source.category===filters.category))
    .map(source=>{
      const newIds=new Set(source.status==='ok'&&source.baseline_known?source.new_ids??[]:[]);
      const all=bySource.get(source.id)??[];
      const entries=filters.onlyNew?all.filter(article=>newIds.has(article.id)):all;
      const ranked=source.adapter&&source.adapter!=='rss'&&source.adapter!=='devto';
      return {source,newIds,articles:[...entries].sort((a,b)=>ranked?
        Number(observation(a,source.id).rank??Infinity)-Number(observation(b,source.id).rank??Infinity):Date.parse(b.published_at)-Date.parse(a.published_at))};
    }).filter(group=>group.articles.length>0);
}
export function feedEntries(groups:SourceGroup[],includeRankedSources=false):FeedEntry[] {
  const entries=new Map<string,FeedEntry>();
  for(const group of groups) {
    if(!includeRankedSources&&!isChronologicalFeed(group.source))continue;
    for(const article of group.articles) {
    const fresh=group.newIds.has(article.id),existing=entries.get(article.id);
    if(!existing||fresh&&!existing.fresh)entries.set(article.id,{source:group.source,article,fresh});
    }
  }
  return [...entries.values()].sort((a,b)=>Date.parse(b.article.published_at)-Date.parse(a.article.published_at));
}
export function boardTotals(groups:SourceGroup[]) {
  const all=new Set<string>(),fresh=new Set<string>();
  for(const group of groups) for(const article of group.articles){all.add(article.id);if(group.newIds.has(article.id))fresh.add(article.id);}
  return {count:all.size,fresh:fresh.size};
}
export function sourceCondition(source:Source) {
  if(source.status==='error')return '采集异常 · 保留上次内容';
  if(source.initialized===false)return '等待首次采集';
  if(source.baseline_known===false)return '首次接入 · 已建立基线';
  return source.status==='ok'?'采集正常':'状态未知';
}
