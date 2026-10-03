import {sourceIds,type Article,type Source} from './catalog.ts';
export type ReadingWindow='all'|'today'|'week';
export function windowStart(window:ReadingWindow,now=Date.now()):number{
 if(window==='all')return -Infinity;
 const offset=8*60*60*1000,day=24*60*60*1000,start=Math.floor((now+offset)/day)*day-offset;
 return window==='today'?start:start-6*day;
}
export function readingSelection(articles:Article[],sources:Source[],category='',window:ReadingWindow='all',now=Date.now()):Article[]{
 const categories=new Map(sources.map(source=>[source.id,source.category])),start=windowStart(window,now);
 return articles.filter(article=>(!category||sourceIds(article).some(id=>categories.get(id)===category))&&(window==='all'||Date.parse(article.published_at)>=start&&Date.parse(article.published_at)<=now));
}
export function unreadCounts(articles:Article[],read:Set<string>):Map<string,number>{const counts=new Map<string,number>();for(const article of articles)if(!read.has(article.id))for(const id of new Set(sourceIds(article)))counts.set(id,(counts.get(id)??0)+1);return counts;}
