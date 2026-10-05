import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
const sql=await readFile('supabase/check_driver_registration.sql','utf8');
const escaped=sql.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
createServer((req,res)=>{
  if(req.url!=='/') {res.writeHead(404);res.end();return;}
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});
  res.end(`<h1>Driver registration smoke check</h1><p>Native PostgreSQL · all fixtures rolled back</p><textarea aria-label="Reviewed registration check" style="width:95vw;height:80vh">${escaped}</textarea>`);
}).listen(5177,'127.0.0.1',()=>console.log('Registration check: http://127.0.0.1:5177/'));
