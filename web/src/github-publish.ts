import {validateConfig,type SourceConfig} from './catalog.ts';
import {duplicateUrls} from './source-management.ts';
export interface Submission {url:string;number:number;branch:string;head:string;fingerprint:string;}
export class RemoteChanged extends Error {constructor(readonly config:SourceConfig){super('远程配置已更新，请先合并远程更新，再检查改动。');}}
export class BranchCreated extends Error {constructor(readonly url:string){super('配置分支已创建，但提交或创建 PR 未完成。请打开分支继续创建，避免重复提交。');}}
export type Fetcher=typeof fetch;
const stable=(value:unknown):string=>JSON.stringify(value,(_key,item)=>item&&typeof item==='object'&&!Array.isArray(item)?Object.fromEntries(Object.entries(item).sort(([a],[b])=>a.localeCompare(b))):item);
export const fingerprint=(config:SourceConfig)=>stable(config);
function endpoint(config:SourceConfig){const {owner,name,branch,path}=config.repository;if(!/^[\w.-]+$/.test(owner)||!/^[\w.-]+$/.test(name)||branch!=='main'||path!=='sources.json')throw Error('仅支持此项目 main 分支的 sources.json 配置。');return `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`;}
function api(token:string,fetcher:Fetcher){if(!token.trim())throw Error('请填写具有此仓库写入权限的 GitHub Token。');return async(path:string,method='GET',body?:unknown,publicRead=false)=>{
 const response=await fetcher(`https://api.github.com${path}`,{method,redirect:'error',cache:'no-store',headers:{Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28',...(publicRead?{}:{Authorization:`Bearer ${token.trim()}`}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
 if(!response.ok){const text:Record<number,string>={401:'Token 无效或已过期。',403:'权限不足或 API 限额已用尽。请检查仓库权限后重试。',404:'仓库、分支或 PR 不可访问，请检查 Token 的仓库范围。',409:'远程版本有变化，请刷新后重试。',422:'GitHub 未接受此操作，请检查分支或 PR 状态。'};throw Error(text[response.status]??`GitHub 操作失败 (${response.status})。`);}
 return response.json();
 };}
function encode(value:string){let raw='';for(const byte of new TextEncoder().encode(value))raw+=String.fromCharCode(byte);return btoa(raw);}
function decode(value:string){return new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(value.replace(/\s/g,'')),char=>char.charCodeAt(0)));}
export async function submitConfiguration(base:SourceConfig,draft:SourceConfig,token:string,fetcher:Fetcher=fetch):Promise<Submission>{
 validateConfig(base);validateConfig(draft);const repo=endpoint(base);if(stable(base.repository)!==stable(draft.repository))throw Error('草稿不能更改目标仓库。');if(duplicateUrls(draft.sources).size)throw Error('请先清理重复 RSS 地址。');if(stable(base)===stable(draft))throw Error('没有待提交改动。');
 const request=api(token,fetcher),ref=await request(`${repo}/git/ref/heads/main`),head=ref.object.sha;
 const file=await request(`${repo}/contents/sources.json?ref=${encodeURIComponent(head)}`);if(file.encoding!=='base64'||typeof file.sha!=='string')throw Error('远程配置无法读取。');const remote=JSON.parse(decode(file.content));validateConfig(remote);if(stable(remote)!==stable(base))throw new RemoteChanged(remote);
 const branch=`sources/${new Date().toISOString().slice(0,10)}-${crypto.randomUUID().slice(0,8)}`;
 await request(`${repo}/git/refs`,'POST',{ref:`refs/heads/${branch}`,sha:head});
 const compare=`https://github.com/${base.repository.owner}/${base.repository.name}/compare/main...${branch}?expand=1`;
 try {
 const commit=await request(`${repo}/contents/sources.json`,'PUT',{message:'更新 RSS 订阅源',content:encode(JSON.stringify(draft,null,2)+'\n'),branch,sha:file.sha});
 const result=await request(`${repo}/pulls`,'POST',{title:'更新 RSS 订阅源',head:branch,base:'main',body:'通过拾阅订阅源页面提交配置。\n\n合并前请核对来源改动及地址校验结果；合并后由 CI 采集并发布。'});
 return {url:result.html_url,number:result.number,branch,head:commit.commit.sha,fingerprint:fingerprint(draft)};
 }catch(error){throw new BranchCreated(compare);}
}
export async function submissionStatus(config:SourceConfig,submission:Submission,token:string,fetcher:Fetcher=fetch):Promise<{merged:boolean;ready:boolean;message:string}>{
 const request=api(token,fetcher),repo=endpoint(config),pull=await request(`${repo}/pulls/${submission.number}`);
 if(pull.base.ref!=='main'||pull.base.repo.full_name.toLowerCase()!==`${config.repository.owner}/${config.repository.name}`.toLowerCase()||pull.head.ref!==submission.branch||pull.head.sha!==submission.head)throw Error('PR 分支或提交已变化，请在 GitHub 核对后操作。');
 if(pull.merged)return {merged:true,ready:false,message:'已合并，等待 CI 采集和发布。'};
 if(pull.state!=='open')return {merged:false,ready:false,message:'PR 已关闭，未合并。请打开 GitHub 查看。'};
 const runs=await request(`${repo}/commits/${encodeURIComponent(submission.head)}/check-runs?per_page=100`,'GET',undefined,true);
 const required=runs.check_runs.filter((run:any)=>run.name==='check'&&run.app?.slug==='github-actions').sort((a:any,b:any)=>Date.parse(b.started_at)-Date.parse(a.started_at))[0];
 const ready=required?.status==='completed'&&required.conclusion==='success'&&pull.mergeable===true&&pull.mergeable_state==='clean';
 return {merged:false,ready,message:ready?'校验通过，可以合并并启动采集。':required?.conclusion==='failure'?'校验未通过，请打开 PR 查看详情。':'等待 GitHub 校验与合并检查，请稍后刷新。'};
}
export async function mergeSubmission(config:SourceConfig,submission:Submission,token:string,fetcher:Fetcher=fetch){
 const status=await submissionStatus(config,submission,token,fetcher);if(status.merged)return;if(!status.ready)throw Error(status.message);
 const result=await api(token,fetcher)(`${endpoint(config)}/pulls/${submission.number}/merge`,'PUT',{sha:submission.head,merge_method:'squash'});if(!result.merged)throw Error('GitHub 未完成合并，请打开 PR 核对。');
}
