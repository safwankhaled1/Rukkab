// Local-only review page for transferring reviewed SQL to the Supabase SQL editor.
// No tokens or service credentials are served. Use CLI migrations for later upgrades.
import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';

const after = process.argv[2];
const reviewPort = Number(process.env.RUKKAB_REVIEW_PORT ?? 5174);
if (!Number.isInteger(reviewPort) || reviewPort < 1024 || reviewPort > 65535) throw new Error('Invalid review port');
if (after && !/^\d{12}$/.test(after)) throw new Error('Expected a 12 digit migration version');
const files = (await readdir('supabase/migrations')).filter(f => /^\d+_.*\.sql$/.test(f)).sort().filter(f => !after || f.slice(0,12) > after);
const parts = after ? [`begin;
do $$ begin
 if (select max(version) from supabase_migrations.schema_migrations) is distinct from '${after}' then
  raise exception 'UNEXPECTED_MIGRATION_VERSION';
 end if;
end $$;`] : [`begin;
do $$ begin
  if exists(select 1 from information_schema.tables where table_schema='public') then
    raise exception 'INITIAL_SETUP_REQUIRES_EMPTY_PUBLIC_SCHEMA';
  end if;
end $$;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations(
  version text primary key, statements text[], name text
);
alter table supabase_migrations.schema_migrations enable row level security;
revoke all on supabase_migrations.schema_migrations from public, anon, authenticated;
do $$ begin
  if exists(select 1 from supabase_migrations.schema_migrations) then
    raise exception 'INITIAL_SETUP_REQUIRES_EMPTY_MIGRATION_HISTORY';
  end if;
end $$;`];
for (const file of files) {
  const [, version, name] = file.match(/^(\d+)_(.+)\.sql$/);
  parts.push(`-- ${file}\n${await readFile(`supabase/migrations/${file}`, 'utf8')}`);
  parts.push(`insert into supabase_migrations.schema_migrations(version,name) values('${version}','${name}');`);
}
parts.push(`commit;\nselect count(*) as installed_migrations from supabase_migrations.schema_migrations;`);
const sql = parts.join('\n\n');
await mkdir('work/deployment', { recursive: true });
await writeFile(`work/deployment/${after ? 'update' : 'initial-setup'}.sql`, sql);
const escaped = sql.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const checkSql = (await readFile('supabase/check_deployment.sql', 'utf8')).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
createServer((req, res) => {
  if (!['/', '/check'].includes(req.url)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'" });
  res.end(`<!doctype html><meta charset="utf-8"><title>Rukkab database deployment review</title><h1>Rukkab database ${req.url === '/check' ? 'smoke check' : after ? 'incremental update' : 'initial setup'}</h1><p>${files.length} migrations · transaction · no owner account or credentials.</p><a href="/check">Review smoke check</a><label for="sql">Reviewed deployment SQL</label><textarea id="sql" style="display:block;width:98%;height:75vh" readonly>${req.url === '/check' ? checkSql : escaped}</textarea>`);
}).listen(reviewPort, '127.0.0.1', () => console.log(`Review: http://127.0.0.1:${reviewPort}/ (${files.length} migrations)`));
