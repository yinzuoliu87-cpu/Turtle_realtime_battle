-- 20261125 114 仪式匕首【血契】一大轮内跨场累积(由 20261119 竹叶龟那份照抄改名) —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261125_ritual_marks
-- ★周号用 2099-01-01(4070908800)：正式服演练时 1793577600(2026-11-02)那一周有真实决赛分组, 插测试分组撞主键(11-19 实测)。
-- 判据：
--   A1 A 方查 referee_job_status ⇒ ritual_new = 结果单 ritual_new
--   A2 ★配对局 B 方查 ⇒ ritual_new = 结果单 ritual_new_b（按视角换好）
--   A3 ★结果单没这个键（老裁判）/ 不是数 ⇒ 回包不带
--   S1 现有的键（wheel_new / 币 / 胜负）原样还在
--   F1 决赛 A 方查 referee_finals_coins ⇒ ritual_new；F2 ★B 方 ⇒ ritual_new_b；F3 没这个键 ⇒ 不带
--   W1 ★合计 = A 方积分赛 9 + B 方闯关配对局 3 + B 方决赛 2 = 14
--   W2 ★不算：积分赛的 B（别人的快照）、偷袭、别的周、没算完、不是数
--   W3 账号为空 ⇒ 0
--   T1 ★econ_on 开：变成 claimed ⇒ meta 带 a_ritual / b_ritual；竹叶龟的 a_bamboo 仍在（两个触发器不互相顶掉）
--   T2 ★econ_on 关：不盖
--   P1 权限：econ_ritual_sum 谁都不能直接调；两个回包函数 anon 没有、authenticated 有
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('a'), ('b'), ('c');
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
create or replace function pg_temp.job(p_kind text, p_key text, p_week bigint, p_a text, p_b text, p_status text, p_meta jsonb, p_res jsonb)
returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, status, meta, result)
    values (p_kind, p_key, p_week, '0.23.5', 1, pg_temp.u(p_a), pg_temp.u(p_b), '{"bamboo_hp":999}', '{"bamboo_hp":888}', p_status, p_meta, p_res)
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
  r := public.referee_finals_coins(4070908800, p_b, 1, 0);
  perform pg_temp.as_user(null);
  return r;
end $$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

create temp table _j (k text primary key, id bigint);
grant select on _j to public;

-- ── 回包 ──
insert into _j values
  ('pair', pg_temp.job('gauntlet', 'chk:rt:p', 4070908800, 'c', 'a', 'done', '{"pair":"true"}',
     '{"ledger":{"won":true,"coins":1,"coins_b":2,"gw_b":0,"gl_b":1},"wheel_new":{"spade":2},"ritual_new":7,"ritual_new_b":3}')),
  ('old',  pg_temp.job('gauntlet', 'chk:rt:o', 4070908800, 'c', 'a', 'done', '{"pair":"true"}', '{"ledger":{"won":true,"coins":1}}')),
  ('bad',  pg_temp.job('gauntlet', 'chk:rt:x', 4070908800, 'c', 'a', 'done', '{"pair":"true"}', '{"ledger":{"won":true,"coins":1},"ritual_new":"9","ritual_new_b":{"v":1}}'));

select pg_temp.ck('A1 A 方 ⇒ ritual_new 自己那一份(7)', (pg_temp.st('c', (select id from _j where k = 'pair')) ->> 'ritual_new')::numeric = 7,
  pg_temp.st('c', (select id from _j where k = 'pair'))::text);
select pg_temp.ck('A2 ★配对局 B 方 ⇒ 取 ritual_new_b(3)', (pg_temp.st('a', (select id from _j where k = 'pair')) ->> 'ritual_new')::numeric = 3,
  pg_temp.st('a', (select id from _j where k = 'pair'))::text);
select pg_temp.ck('A3 ★没这个键 / 不是数 ⇒ A / B 回包都不带',
  not (pg_temp.st('c', (select id from _j where k = 'old')) ? 'ritual_new') and not (pg_temp.st('a', (select id from _j where k = 'old')) ? 'ritual_new')
  and not (pg_temp.st('c', (select id from _j where k = 'bad')) ? 'ritual_new') and not (pg_temp.st('a', (select id from _j where k = 'bad')) ? 'ritual_new'));
select pg_temp.ck('S1 现有的键原样还在(wheel_new / 币 / 胜负)', pg_temp.st('c', (select id from _j where k = 'pair')) @> '{"coins":1,"won":true,"wheel_new":{"spade":2}}'::jsonb,
  pg_temp.st('c', (select id from _j where k = 'pair'))::text);

insert into public.finals_buckets (season_week, bucket_no, n, round, closed) values (4070908800, 0, 2, 2, false), (4070908800, 1, 2, 2, false);
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used) values (4070908800, 0, 1, 0, 0, 1), (4070908800, 1, 1, 0, 0, 1);
insert into _j values
  ('f0', pg_temp.job('finals', 'finals:4070908800:0:1:0', 4070908800, 'c', 'a', 'done', '{"bucket":0,"round":1,"match":0}',
     '{"ledger":{"won":true,"coins":3,"coins_b":4},"ritual_new":5,"ritual_new_b":2}')),
  ('f1', pg_temp.job('finals', 'finals:4070908800:1:1:0', 4070908800, 'c', 'a', 'done', '{"bucket":1,"round":1,"match":0}', '{"ledger":{"won":true,"coins":3,"coins_b":4}}'));
select pg_temp.ck('F1 决赛 A 方 ⇒ ritual_new 5、币 3', pg_temp.fc('c', 0) @> '{"ritual_new":5,"coins":3}'::jsonb, pg_temp.fc('c', 0)::text);
select pg_temp.ck('F2 ★决赛 B 方 ⇒ 取 ritual_new_b 2、币 4', pg_temp.fc('a', 0) @> '{"ritual_new":2,"coins":4}'::jsonb, pg_temp.fc('a', 0)::text);
select pg_temp.ck('F3 没这个键 ⇒ 不带', not (pg_temp.fc('c', 1) ? 'ritual_new') and (pg_temp.fc('c', 1) ->> 'coins')::int = 3, pg_temp.fc('c', 1)::text);

-- ── 记账合计(a 的账): A 方积分赛 9 + 上面配对局 B 方 3 + 上面决赛 B 方 2 = 14 ──
select pg_temp.job('ranked', 'chk:rt:r1', 4070908800, 'a', 'b', 'done', '{}', '{"ritual_new":9,"ritual_new_b":70}');
-- 不该算进 a 的：
select pg_temp.job('ranked', 'chk:rt:r2', 4070908800, 'c', 'a', 'done', '{}', '{"ritual_new":1,"ritual_new_b":60}');   -- a 是积分赛的 B（快照）
select pg_temp.job('raid', 'chk:rt:x1', 4070908800, 'a', 'c', 'done', '{}', '{"ritual_new":80}');                       -- 偷袭
select pg_temp.job('ranked', 'chk:rt:o1', 4070304000, 'a', 'b', 'done', '{}', '{"ritual_new":80}');                     -- 上一周
select pg_temp.job('ranked', 'chk:rt:n1', 4070908800, 'a', 'b', 'claimed', '{}', '{"ritual_new":80}');                  -- 没算完
select pg_temp.job('ranked', 'chk:rt:j1', 4070908800, 'a', 'b', 'done', '{}', '{"ritual_new":"80"}');                   -- 不是数

select pg_temp.ck('W1 ★合计 = 积分赛 A 9 + 配对局 B 3 + 决赛 B 2 = 14',
  public.econ_ritual_sum(pg_temp.u('a'), 4070908800) = 14, public.econ_ritual_sum(pg_temp.u('a'), 4070908800)::text);
select pg_temp.ck('W2 ★积分赛的 B / 偷袭 / 别的周 / 没算完 / 不是数都不算(合计没有 60 / 80 那些)',
  public.econ_ritual_sum(pg_temp.u('a'), 4070908800) < 20, public.econ_ritual_sum(pg_temp.u('a'), 4070908800)::text);
select pg_temp.job('ranked', 'chk:rt:big', 4070908800, 'b', 'c', 'done', '{}', '{"ritual_new":999}');                     -- b 自己一局报 999
select pg_temp.ck('W4 ★单局按上限 150 夹(b 只有这一局 ⇒ 150)', public.econ_ritual_sum(pg_temp.u('b'), 4070908800) = 150,
  public.econ_ritual_sum(pg_temp.u('b'), 4070908800)::text);
select pg_temp.ck('W3 账号为空 ⇒ 0',
  public.econ_ritual_sum(null, 4070908800) = 0,
  public.econ_ritual_sum(pg_temp.u('b'), 4070908800)::text);

-- ── 盖章 ──
update public.referee_config set econ_on = true where id = 1;
insert into _j values
  ('on',  pg_temp.job('gauntlet', 'chk:rt:s1', 4070908800, 'a', 'c', 'pending', '{"pair":"true"}', null)),
  ('off', pg_temp.job('ranked', 'chk:rt:s3', 4070908800, 'a', 'b', 'pending', '{}', null));
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'on');
select pg_temp.ck('T1 ★开着: a_ritual = a 的合计 14、b_ritual = c 的合计(配对局 A 7 + 决赛 A 5 + 积分赛 A 1 = 13)',
  (select (meta ->> 'a_ritual')::numeric = 14 and (meta ->> 'b_ritual')::numeric = 13 from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.ck('T1 ★竹叶龟的 a_bamboo 仍在(两个触发器不互相顶掉)、pair 原样',
  (select meta ? 'a_bamboo' and meta ->> 'pair' = 'true' from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
update public.referee_config set econ_on = false where id = 1;
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'off');
select pg_temp.ck('T2 ★关着: 不盖',
  (select not (meta ? 'a_ritual') and not (meta ? 'b_ritual') from public.referee_jobs where job_id = (select id from _j where k = 'off')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'off')));

select pg_temp.ck('P1 权限: econ_ritual_sum 谁都不能直接调; 回包函数 anon 没有、authenticated 有',
  not has_function_privilege('anon', 'public.econ_ritual_sum(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_ritual_sum(uuid,bigint)', 'execute')
  and not has_function_privilege('anon', 'public.referee_job_status(bigint)', 'execute')
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
