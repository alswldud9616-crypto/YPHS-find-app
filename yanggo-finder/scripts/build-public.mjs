// Publish the existing interface in an explicit read-only, disconnected state.
// The operational Next.js APIs are not part of this static artifact.
import fs from 'node:fs/promises';import path from 'node:path';import {build} from 'esbuild';
await fs.rm('dist',{recursive:true,force:true});await fs.mkdir('dist',{recursive:true});
await fs.cp('.next/static','dist/_next/static',{recursive:true});await fs.copyFile('public/favicon.svg','dist/favicon.svg');
const css=(await fs.readdir('.next/static/css')).filter(f=>f.endsWith('.css'));
await build({entryPoints:['public-view/entry.tsx'],outdir:'dist/assets',bundle:true,minify:true,format:'esm',jsx:'automatic',alias:{'next/link':path.resolve('public-view/link.tsx'),'next/navigation':path.resolve('public-view/navigation.tsx'),'@':process.cwd()},define:{'process.env.NODE_ENV':'"production"'}});
// Only CSS and its font/media assets are needed from the Next build.
await fs.rm('dist/_next/static/chunks',{recursive:true,force:true});
await fs.writeFile('dist/index.html',`<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#ffdf76"><title>양고 찾기 | 양평고등학교</title><meta name="description" content="양평고등학교 분실물 안내. 운영 서버 연결 준비 중입니다."><link rel="icon" href="/favicon.svg">${css.map(f=>`<link rel="stylesheet" href="/_next/static/css/${f}">`).join('')}</head><body><div id="root"></div><noscript>양고 찾기를 이용하려면 자바스크립트를 켜주세요.</noscript><script type="module" src="/assets/entry.js"></script></body></html>`);
console.log('Public interface built: read-only, no personal-data collection, no mock records.');
