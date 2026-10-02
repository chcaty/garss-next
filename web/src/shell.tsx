import {Appearance} from './appearance.tsx';
export function Shell({current}:{current:'reader'|'sources'|'sync'}) {
  return <header className="app-header"><div className="app-nav"><a href="./" className="flex items-center gap-2 text-lg font-semibold tracking-tight"><img src="./assets/shared/brand.svg" className="size-7" alt=""/>拾阅</a><nav aria-label="主导航" className="app-links">{[['reader','./','信息流'],['sources','./sources.html','订阅源'],['sync','./sync.html','同步记录']].map(([id,url,title])=><a key={id} href={url} aria-current={id===current?'page':undefined}>{title}</a>)}<Appearance/></nav></div></header>;
}
