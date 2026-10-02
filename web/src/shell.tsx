import {useState} from 'react';
import {currentTheme,setTheme,type Theme} from './theme.ts';
export function Shell({current}:{current:'reader'|'sources'|'sync'}) {
  const [theme,update]=useState(currentTheme);
  return <header className="app-header"><div className="app-nav"><a href="./" className="text-lg font-semibold tracking-tight">GARSS</a><nav aria-label="主导航" className="app-links">{[['reader','./','信息流'],['sources','./sources.html','订阅源'],['sync','./sync.html','同步记录']].map(([id,url,title])=><a key={id} href={url} aria-current={id===current?'page':undefined}>{title}</a>)}<label><span className="sr-only">外观</span><select aria-label="外观" className="min-h-11 rounded-md bg-paper px-2 text-sm text-ink" value={theme} onChange={event=>{const value=event.target.value as Theme;setTheme(value);update(value);}}><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></label></nav></div></header>;
}
