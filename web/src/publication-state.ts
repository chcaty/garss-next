import {readJson, validateConfig, type SourceConfig} from './catalog.ts';
import {sourceOperations, type Operation} from './source-request.ts';

export function operationApplied(operation:Operation,config:SourceConfig):boolean{
 const source=config.sources.find(item=>item.id===operation.id);
 return operation.remove?!source:!!source&&Object.entries(operation.set??{}).every(([key,value])=>source[key as keyof typeof source]===value);
}
export interface PublicationStatus {published:SourceConfig;applied:number;total:number;message:string;failed:boolean}
export async function checkPublication(base:SourceConfig,draft:SourceConfig):Promise<PublicationStatus>{
 const operations=await sourceOperations(base,draft);
 const published=await readJson<SourceConfig>('./api/v1/sources.json');validateConfig(published);
 const repoFields=['owner','name','branch','path'] as const;
 if(repoFields.some(key=>published.repository[key]!==base.repository[key]))throw Error('发布目录与当前仓库不一致，请重新加载页面。');
 const count=(config:SourceConfig)=>operations.filter(operation=>operationApplied(operation,config)).length;
 const applied=count(published);
 if(!operations.length)return {published,applied,total:0,message:'当前没有待发布改动。',failed:false};
 if(applied===operations.length)return {published,applied,total:operations.length,message:`${applied} 个来源改动已在公共目录发布。手机刷新文章后可读取更新。`,failed:false};
 const {owner,name,branch,path}=base.repository;
 const repo=`https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`;
 async function github<T>(url:string,accept='application/vnd.github+json'):Promise<T>{
  const response=await fetch(url,{cache:'no-cache',headers:{Accept:accept},signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw Error('GitHub 状态读取失败，可能是网络或访问次数限制。请查看提交记录或稍后重试。');
  return response.json() as Promise<T>;
 }
 const commit=await github<{sha:string}>(`${repo}/commits/${encodeURIComponent(branch)}`);
 const current=await github<SourceConfig>(`${repo}/contents/${path.split('/').map(encodeURIComponent).join('/')}?ref=${commit.sha}`,'application/vnd.github.raw+json');validateConfig(current);
 const accepted=count(current);
 if(accepted===0)return {published,applied,total:operations.length,message:`公共目录已发布 ${applied}/${operations.length} 个改动。其余改动尚未应用；请在 GitHub 确认请求，或查看校验与冲突结果。`,failed:false};
 const runs=await github<{workflow_runs:{status:string;conclusion:string|null}[]}>(`${repo}/actions/workflows/collect.yml/runs?head_sha=${commit.sha}&per_page=1`);
 const run=runs.workflow_runs[0];
 const failed=!!run&&run.status==='completed'&&run.conclusion!=='success';
 const stage=failed?'采集或部署未成功，请查看采集日志。':run?.status==='completed'?'采集任务已完成，公共目录尚未显示全部改动，请稍后再次检查。':run?'采集或部署正在排队／进行中。':'等待采集与发布，请查看采集日志。';
 return {published,applied,total:operations.length,message:`配置已应用 ${accepted}/${operations.length} 个改动，公共目录已发布 ${applied}/${operations.length} 个。${stage}`,failed};
}
