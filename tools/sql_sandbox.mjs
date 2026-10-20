// sql_sandbox.mjs —— 本机空库跑服务端 SQL（2026-10-20 · 账号删除 / 昵称举报那次加）
//
// 本机没有 postgres。PGlite = 编进 WebAssembly 的 PostgreSQL 16（真 plpgsql / jsonb / sha256），
// node 里起一个内存库：桩出 Supabase 的 auth / cron / 三个角色 → 整份 schema.sql → 给定的迁移 → 给定的检查脚本。
//
// 一次性准备（不进仓库）：
//   npm install --prefix <某个目录> @electric-sql/pglite@0.2.17
//   PGLITE_MODULE=<某个目录>/node_modules/@electric-sql/pglite/dist/index.js
// 用法：
//   node tools/sql_sandbox.mjs server/supabase/migrations/20261020b_account_delete_and_reports.sql \
//        server/supabase/tests/20261020b_account_delete_and_reports_check.sql
//   ⇒ 检查脚本最后一句一定抛异常：'ALL PASS' 退出码 0，其余（FAIL / 语法错）退出码 1。
//
// ★桩只模拟到「本仓 SQL 用得到」的那一层：auth.users 只有本仓读写的列，auth.uid() 读 request.jwt.claims，
//   cron.schedule / unschedule 只记一行。它证明的是「我们的 SQL 在真 PG16 上语法对、逻辑对」，
//   不证明生产库上没有别的约束 —— 那一层由同一份检查脚本在生产的回滚事务里再跑一次（方案书上线步骤）。
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const mod = process.env.PGLITE_MODULE;
if (!mod) {
  console.error('PGLITE_MODULE 没设（见文件头）');
  process.exit(2);
}
const { PGlite } = await import(pathToFileURL(mod).href);

const STUB = `
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator nologin; end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (
  id uuid primary key, instance_id uuid, aud text, role text, email text,
  is_anonymous boolean not null default false,
  created_at timestamptz default now(), last_sign_in_at timestamptz
);
create or replace function auth.uid() returns uuid language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$f$;
create or replace function auth.jwt() returns jsonb language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$f$;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant execute on function auth.jwt() to anon, authenticated, service_role;
create schema if not exists cron;
create table cron.job (jobid serial primary key, jobname text, schedule text, command text);
create or replace function cron.schedule(p_name text, p_sched text, p_cmd text) returns bigint language sql as $f$
  insert into cron.job (jobname, schedule, command) values (p_name, p_sched, p_cmd) returning jobid::bigint
$f$;
create or replace function cron.unschedule(p_id bigint) returns boolean language sql as $f$
  delete from cron.job where jobid = p_id returning true
$f$;
create or replace function cron.unschedule(p_name text) returns boolean language sql as $f$
  delete from cron.job where jobname = p_name returning true
$f$;
`;

const files = ['server/supabase/schema.sql', ...process.argv.slice(2)];
const db = new PGlite();
const notices = [];
async function run(label, sql) {
  try {
    await db.exec(sql);
    return true;
  } catch (e) {
    const m = String(e.message || e);
    console.log(`[${label}] ${m}`);
    return m;
  }
}

let r = await run('stub', STUB);
if (r !== true) process.exit(1);
// 生产的 schema.sql 是一路追加的历史：逐条执行会撞到「已在生产手动处理过」的少数语句。
// 整份一次 exec ⇒ 第一处错误就停 —— 那正是要看见的。
for (let i = 0; i < files.length; i++) {
  const f = files[i];
  const sql = readFileSync(f, 'utf8');
  r = await run(f, sql);
  const last = i === files.length - 1;
  if (r !== true) {
    if (last && /ALL PASS/.test(r)) {
      console.log('SQL 沙盒: ALL PASS');
      process.exit(0);
    }
    process.exit(1);
  }
}
console.log('SQL 沙盒: 最后一个文件没有抛出结论（检查脚本必须以 ALL PASS / FAIL 异常结尾）');
process.exit(1);
