import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
await build({entryPoints: {'reader/app':'web/src/reader.ts','sources/app':'web/src/sources.tsx'},
  outdir:'web/build',outExtension:{'.js':'.mjs'},bundle:true,format:'esm',target:'es2022',minify:true,
  define:{'process.env.NODE_ENV':'"production"'}});
execFileSync(process.execPath,['node_modules/@tailwindcss/cli/dist/index.mjs','-i','web/src/sources.css','-o','web/build/sources/styles.css','--minify'],{stdio:'inherit'});
