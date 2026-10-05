import {chromium} from 'playwright';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
const svg=await readFile('assets/brand/rukkab-symbol.svg','utf8');
await mkdir('work/screenshots',{recursive:true});
const browser=await chromium.launch({channel:'msedge',headless:true});
try{
 const page=await browser.newPage({viewport:{width:1024,height:1024},deviceScaleFactor:1});
 await page.setContent('<style>html,body{margin:0;background:transparent}svg{display:block;width:100%;height:100%}</style>'+svg);
 await page.screenshot({path:'assets/brand/rukkab-symbol-1024.png',omitBackground:true});
 for(const [density,size] of [['mdpi',48],['hdpi',72],['xhdpi',96],['xxhdpi',144],['xxxhdpi',192]]){
  await page.setViewportSize({width:size,height:size});
  await page.screenshot({path:'apps/mobile/android/app/src/main/res/mipmap-'+density+'/ic_launcher.png',omitBackground:true});
 }
 const ios='apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset';
 try{const contents=JSON.parse(await readFile(path.join(ios,'Contents.json'),'utf8'));for(const asset of contents.images){if(!asset.filename)continue;const size=Math.round(Number(asset.size.split('x')[0])*Number(asset.scale.replace('x','')));await page.setViewportSize({width:size,height:size});await page.screenshot({path:path.join(ios,asset.filename),omitBackground:false});}}catch(error){if(error.code!=='ENOENT')throw error;}
 console.log('Rendered original vector mark and native launcher icons.');
}finally{await browser.close();}
