// Loopback-only SQL review. No credentials or user data are served.
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
const sql = (await readFile(process.argv[2] === 'cancellations' ? 'supabase/check_cancellation_consistency.sql' : process.argv[2] === 'offers' ? 'supabase/check_offer_capacity.sql' : process.argv[2] === 'ride' ? 'supabase/check_ride_lifecycle.sql' : 'supabase/check_driver_application_review.sql','utf8')).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
createServer((req,res)=>{
 if(req.url!=='/'){res.writeHead(404);res.end();return;}
 res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"});
 res.end('<!doctype html><meta charset="utf-8"><title>Rukkab native application review check</title><h1>Rollback-only server smoke check</h1><label for="sql">Reviewed smoke check SQL</label><textarea id="sql" readonly style="width:98%;height:80vh">'+sql+'</textarea>');
}).listen(5179,'127.0.0.1',()=>console.log('Review: http://127.0.0.1:5179/'));
