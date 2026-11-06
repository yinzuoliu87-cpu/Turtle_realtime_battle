-- 20261106f 服务器局的小木斧击杀经验带回客户端 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261106f_axe_kills_status
-- 判据：
--   A1 A 方查 referee_job_status ⇒ axe_kills = 结果单 axe_kills
--   A2 ★配对局 B 方查 ⇒ axe_kills = 结果单 axe_kills_b（按视角换好，客户端一行不用改）
--   A3 ★结果单没这个键（老裁判）⇒ 回包一个键都不多
--   A4 没算完的任务 ⇒ 不带
--   F1 决赛 A 方查 referee_finals_coins ⇒ axe_kills
--   F2 ★决赛 B 方查 ⇒ axe_kills_b
--   F3 结果单没这个键 ⇒ 不带
--   S1 chest / incense / coins 这些现有的键原样还在
--   P1 权限：anon 没有 execute，authenticated 有
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('a'), ('b');
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.job(p_kind text, p_key text, p_status text, p_meta jsonb, p_res jsonb) returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, status, meta, result)
    values (p_kind, p_key, 1793577600, '0.22.8', 1, pg_temp.u('a'), pg_temp.u('b'), '{}', '{}', p_status, p_meta, p_res)
  returning job_id
$$;
create or replace function pg_temp.st(p_k text, p_job bigint) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  r := public.referee_job_status(p_job);
  perform pg_temp.as_user(null);
  return r;
end $$;
create or replace function pg_temp.fc(p_k text, p_b int) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  r := public.referee_finals_coins(1793577600, p_b, 1, 0);
  perform pg_temp.as_user(null);
  return r;
end $$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

create temp table _j (k text primary key, id bigint);
grant select on _j to public;
insert into _j values
  ('pair', pg_temp.job('gauntlet', 'chk:p', 'done', '{"pair":"true"}',
     '{"ledger":{"won":true,"coins":1,"coins_b":2,"gw_b":0,"gl_b":1},"axe_kills":4,"axe_kills_b":2,"chest":{"value":5,"won":[]},"incense":{"marks":1,"charge":1}}')),
  ('old', pg_temp.job('gauntlet', 'chk:o', 'done', '{"pair":"true"}', '{"ledger":{"won":true,"coins":1}}')),
  ('run', pg_temp.job('gauntlet', 'chk:r', 'pending', '{"pair":"true"}', null));

select pg_temp.ck('A1 A 方 ⇒ axe_kills 4', (pg_temp.st('a', (select id from _j where k = 'pair')) ->> 'axe_kills')::int = 4, pg_temp.st('a', (select id from _j where k = 'pair'))::text);
select pg_temp.ck('A2 ★配对局 B 方 ⇒ axe_kills 2(取 axe_kills_b)', (pg_temp.st('b', (select id from _j where k = 'pair')) ->> 'axe_kills')::int = 2, pg_temp.st('b', (select id from _j where k = 'pair'))::text);
select pg_temp.ck('A3 ★结果单没这个键 ⇒ A / B 回包都不带', not (pg_temp.st('a', (select id from _j where k = 'old')) ? 'axe_kills') and not (pg_temp.st('b', (select id from _j where k = 'old')) ? 'axe_kills'));
select pg_temp.ck('A4 没算完 ⇒ 不带', not (pg_temp.st('a', (select id from _j where k = 'run')) ? 'axe_kills'));
select pg_temp.ck('S1 现有的键原样还在(币 / 宝箱 / 香火 / 胜负)', pg_temp.st('a', (select id from _j where k = 'pair')) @> '{"coins":1,"won":true,"chest":{"value":5},"incense":{"marks":1}}'::jsonb);

-- 决赛：0 号桶带这个键，1 号桶不带
insert into public.finals_buckets (season_week, bucket_no, n, round, closed) values (1793577600, 0, 2, 2, false), (1793577600, 1, 2, 2, false);
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used) values (1793577600, 0, 1, 0, 0, 1), (1793577600, 1, 1, 0, 0, 1);
insert into _j values
  ('f0', pg_temp.job('finals', 'finals:1793577600:0:1:0', 'done', '{"bucket":0,"round":1,"match":0}', '{"ledger":{"won":true,"coins":3,"coins_b":4},"axe_kills":5,"axe_kills_b":1}')),
  ('f1', pg_temp.job('finals', 'finals:1793577600:1:1:0', 'done', '{"bucket":1,"round":1,"match":0}', '{"ledger":{"won":true,"coins":3,"coins_b":4}}'));
select pg_temp.ck('F1 决赛 A 方 ⇒ axe_kills 5、币 3', pg_temp.fc('a', 0) @> '{"axe_kills":5,"coins":3}'::jsonb, pg_temp.fc('a', 0)::text);
select pg_temp.ck('F2 ★决赛 B 方 ⇒ axe_kills 1、币 4', pg_temp.fc('b', 0) @> '{"axe_kills":1,"coins":4}'::jsonb, pg_temp.fc('b', 0)::text);
select pg_temp.ck('F3 结果单没这个键 ⇒ 不带', not (pg_temp.fc('a', 1) ? 'axe_kills') and (pg_temp.fc('a', 1) ->> 'coins')::int = 3, pg_temp.fc('a', 1)::text);
select pg_temp.ck('P1 权限: anon 没有、authenticated 有',
  not has_function_privilege('anon', 'public.referee_job_status(bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.referee_job_status(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.referee_finals_coins(bigint,int,int,int)', 'execute')
  and has_function_privilege('authenticated', 'public.referee_finals_coins(bigint,int,int,int)', 'execute'));

do $$
declare nf int; nt int; msg text; fmsg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  select string_agg(left(format('[FAIL] %s %s', name, info), 600), E'\n' order by n) into fmsg from _chk where not pass;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || fmsg || E'\n──── 全部 ────\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
