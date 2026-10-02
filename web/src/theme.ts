export type Theme = 'system'|'light'|'dark';
const key='garss-appearance';
const media=matchMedia('(prefers-color-scheme: dark)');
export function currentTheme():Theme { try { const value=localStorage.getItem(key);return value==='light'||value==='dark'?value:'system'; } catch { return 'system'; } }
export function applyTheme(value:Theme):void { document.documentElement.dataset.theme=value==='system'?(media.matches?'dark':'light'):value; }
export function setTheme(value:Theme):void { try {localStorage.setItem(key,value);}catch{} applyTheme(value); }
export function initializeTheme():void { applyTheme(currentTheme());media.addEventListener('change',()=>applyTheme(currentTheme()));window.addEventListener('storage',event=>{if(event.key===key)applyTheme(currentTheme());}); }
initializeTheme();
