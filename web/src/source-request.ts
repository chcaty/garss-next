import {type Source,type SourceConfig,validateConfig} from './catalog.ts';
import {duplicateUrls} from './source-management.ts';
export const marker='<!-- shiyue-source-request:v1 -->';
export const requestFields=['title','description','category','feed_url','enabled','allow_undated','recheck_requested_at','discovered_from','verified_at'] as const;
export type Operation={id:string;before:string|null;set?:Record<string,unknown>;remove?:true};
export type RequestBatch={url:string;body:string;count:number};
const canonical=(value:unknown)=>JSON.stringify(value,(_key,item)=>item&&typeof item==='object'&&!Array.isArray(item)?Object.fromEntries(Object.keys(item).sort().map(key=>[key,item[key]])):item);
async function hash(source:Source){const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical(source)));return [...new Uint8Array(digest)].map(byte=>byte.toString(16).padStart(2,'0')).join('');}
export async function sourceOperations(base:SourceConfig,draft:SourceConfig):Promise<Operation[]>{
 validateConfig(base);validateConfig(draft);if(canonical(base.repository)!==canonical(draft.repository))throw Error('草稿不能更改仓库。');if(duplicateUrls(draft.sources).size)throw Error('请先清理重复 RSS 地址。');
 const old=new Map(base.sources.map(source=>[source.id,source])),current=new Map(draft.sources.map(source=>[source.id,source])),operations:Operation[]=[];
 for(const source of base.sources)if(!current.has(source.id))operations.push({id:source.id,before:await hash(source),remove:true});
 for(const source of draft.sources){const prior=old.get(source.id),set:Record<string,unknown>={};for(const key of requestFields)if(source[key]!==undefined&&(!prior||source[key]!==prior[key]))set[key]=source[key];if(Object.keys(set).length)operations.push({id:source.id,before:prior?await hash(prior):null,set});}
 return operations;
}
export async function sourceRequestBatches(base:SourceConfig,draft:SourceConfig):Promise<RequestBatch[]>{
 const operations=await sourceOperations(base,draft),{owner,name,branch,path}=base.repository;if(!/^[\w.-]+$/.test(owner)||!/^[\w.-]+$/.test(name)||branch!=='main'||path!=='sources.json')throw Error('仓库配置不支持此提交方式。');
 function batch(items:Operation[]):RequestBatch{
 const request={version:1,repository:`${owner}/${name}`,operations:items},body=`${marker}\n\n请应用以下 ${items.length} 个来源改动。校验通过后，由 CI 更新配置并采集发布。\n\n\`\`\`json\n${JSON.stringify(request)}\n\`\`\`\n`;
 const url=new URL(`https://github.com/${owner}/${name}/issues/new`);url.searchParams.set('title',`[拾阅订阅源] 更新 ${items.length} 个来源`);url.searchParams.set('body',body);return {url:url.href,body,count:items.length};
 }
 const batches:RequestBatch[]=[];let items:Operation[]=[];
 for(const operation of operations){const candidate=batch([...items,operation]);if(candidate.url.length>6500||items.length===40){if(items.length)batches.push(batch(items));items=[operation];if(batch(items).url.length>6500)throw Error('单个来源内容过长，请精简简介，或下载 JSON 后手动提交。');}else items.push(operation);}
 if(items.length)batches.push(batch(items));return batches;
}
