import { build } from 'esbuild';
await build({ entryPoints: { 'reader/app': 'web/src/reader.ts', 'sources/app': 'web/src/sources.ts' },
  outdir: 'web/build', outExtension: { '.js': '.mjs' }, bundle: true,
  format: 'esm', target: 'es2022', minify: true });
