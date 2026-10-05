import {useEffect,useRef,useState} from 'react';
import {type SourceConfig} from './catalog.ts';
import {sourceRequestBatches,type RequestBatch} from './source-request.ts';
import {checkPublication} from './publication-state.ts';

export function Publisher({base,draft,blocked,onPublished}:{base:SourceConfig;draft:SourceConfig;blocked:boolean;onPublished:(config:SourceConfig)=>void}){
 const [batches,setBatches]=useState<RequestBatch[]>([]),[error,setError]=useState(''),[preparing,setPreparing]=useState(true);
 const [opened,setOpened]=useState<Set<number>>(new Set()),[checking,setChecking]=useState(false),[result,setResult]=useState('');
 const generation=useRef(0);
 useEffect(()=>{let alive=true;setPreparing(true);setChecking(false);setError('');setOpened(new Set());setResult('');
  void sourceRequestBatches(base,draft).then(value=>{if(alive)setBatches(value);}).catch(reason=>{if(alive)setError(reason instanceof Error?reason.message:'暂时无法整理改动，请下载 JSON 备份后重试。');}).finally(()=>{if(alive)setPreparing(false);});
  generation.current++;
  return()=>{alive=false;generation.current++;};
 },[base,draft]);
 async function check(){
  const requestGeneration=generation.current;
  setChecking(true);setResult('正在检查配置和公共目录…');
  try{const status=await checkPublication(base,draft);if(requestGeneration!==generation.current)return;setResult(status.message);if(status.total&&status.applied===status.total)onPublished(status.published);}
  catch(reason){if(requestGeneration===generation.current)setResult(reason instanceof Error?reason.message:'发布结果读取失败，请稍后重试。');}
  finally{if(requestGeneration===generation.current)setChecking(false);}
 }
 const issueUrl=`https://github.com/${base.repository.owner}/${base.repository.name}/issues?q=${encodeURIComponent('is:issue [拾阅订阅源]')}`;
 return <section className="mt-5 space-y-4" aria-label="提交来源改动">
  <h3 className="font-semibold">2 · 在 GitHub 提交</h3>
  <p className="text-sm leading-7 text-muted">使用仓库所有者账号登录 GitHub 并提交请求。配置校验通过后启动采集，部署完成后才会出现在公共目录。Issue 关闭表示配置已应用、采集已启动。</p>
  {error?<p role="alert" className="text-sm text-muted">{error}</p>:null}
  {preparing?<p role="status" className="text-sm text-muted">正在整理改动…</p>:blocked?<p className="text-sm text-muted">先处理草稿冲突或重复地址，再提交改动。</p>:batches.length?<div className="space-y-3">{batches.map((batch,index)=><div key={index} className="flex flex-wrap items-center gap-3"><a className="btn btn-primary" href={batch.url} target="_blank" rel="noopener noreferrer" onClick={()=>setOpened(previous=>new Set([...previous,index]))}>{batches.length===1?'前往 GitHub 确认':`提交第 ${index+1} 批 · ${batch.count} 个来源`}</a><span className="text-xs text-muted">{opened.has(index)?'已打开确认页，仍需在 GitHub 提交':'尚未打开确认页'}</span></div>)}</div>:<p className="text-sm text-muted">当前没有待提交改动。</p>}
  {batches.length>1?<p className="text-xs leading-6 text-muted">共 {batches.length} 批，请逐批确认；各批独立校验。下方检查已应用和已发布的来源数量。</p>:null}
  <h3 className="border-t border-line pt-5 font-semibold">3 · 检查发布结果</h3><p className="text-xs leading-6 text-muted">提交请求 → 配置应用 → 采集发布。只有公共目录包含改动时才完成；打开确认页不代表已提交。</p><div className="flex flex-wrap items-center gap-4"><button className="btn" disabled={checking||preparing||blocked} onClick={()=>void check()}>{checking?'正在检查…':'检查发布结果'}</button><a className="text-xs text-brand underline" href={issueUrl} target="_blank" rel="noopener noreferrer">查看提交记录</a><a className="text-xs text-brand underline" href="./sync.html">查看同步记录</a></div>
  {result?<p role="status" aria-live="polite" className="text-sm leading-7 text-muted">{result}</p>:null}
  <p className="text-xs leading-6 text-muted">地址校验失败或同一来源已被修改时，请在提交记录查看原因。草稿保留在浏览器；确认全部改动已发布后会更新本机基线。</p>
 </section>;
}
