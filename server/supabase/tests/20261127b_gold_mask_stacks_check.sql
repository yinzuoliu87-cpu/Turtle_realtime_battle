-- 20261127b 135 黄金面具层数跨对局保留(由 20261125 血契那份照抄改) —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261127b_gold_mask_stacks
-- ★周号用 2099-01-01(4070908800)与前一周(4070304000), 不撞真数据。
-- 判据：
--   A1 A 方查 referee_job_status ⇒ gold_new = 结果单 gold_new(对象原样)
--   A2 ★配对局 B 方查 ⇒ gold_new = 结果单 gold_new_b
--   A3 ★结果单没这个键 / 不是对象 ⇒ 回包不带
--   S1 现有的键（ritual_new / wheel_new / 币 / 胜负）原样还在
--   F1 决赛 A 方 ⇒ gold_new；F2 ★B 方 ⇒ gold_new_b；F3 没这个键 ⇒ 不带
--   W1 ★合计(全部周) = A 方积分赛 3+2 + B 方闯关配对局 4 + B 方决赛 1 + 上一周积分赛 6 = 16
--   W2 ★不算：积分赛的 B、偷袭、没算完、值不是数
--   W4 ★单件单局按 50 夹
--   W3 账号为空 ⇒ 0
--   T1 ★econ_on 开：claimed ⇒ meta 带 a_gold / b_gold；血契 a_ritual 仍在（触发器不互相顶掉）
--   T2 ★econ_on 关：不盖
--   P1 权限：econ_gold_sum 谁都不能直接调；两个回包函数 anon 没有、authenticated 有
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
    values (p_kind, p_key, p_week, '0.23.6', 1, pg_temp.u(p_a), pg_temp.u(p_b), '{"bamboo_hp":999}', '{"bamboo_hp":888}', p_status, p_meta, p_res)
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
  ('pair', pg_temp.job('gauntlet', 'chk:gm:p', 4070908800, 'c', 'a', 'done', '{"pair":"true"}',
     '{"ledger":{"won":true,"coins":1,"coins_b":2,"gw_b":0,"gl_b":1},"wheel_new":{"spade":2},"ritual_new":7,"ritual_new_b":3,"gold_new":{"ninja|p2eq_135":5},"gold_new_b":{"dice|p2eq_135":4}}')),
  ('old',  pg_temp.job('gauntlet', 'chk:gm:o', 4070908800, 'c', 'a', 'done', '{"pair":"true"}', '{"ledger":{"won":true,"coins":1}}')),
  ('bad',  pg_temp.job('gauntlet', 'chk:gm:x', 4070908800, 'c', 'a', 'done', '{"pair":"true"}', '{"ledger":{"won":true,"coins":1},"gold_new":9,"gold_new_b":"x"}'));

select pg_temp.ck('A1 A 方 ⇒ gold_new 自己那一份(对象原样)', pg_temp.st('c', (select id from _j where k = 'pair')) -> 'gold_new' = '{"ninja|p2eq_135":5}'::jsonb,
  pg_temp.st('c', (select id from _j where k = 'pair'))::text);
select pg_temp.ck('A2 ★配对局 B 方 ⇒ 取 gold_new_b', pg_temp.st('a', (select id from _j where k = 'pair')) -> 'gold_new' = '{"dice|p2eq_135":4}'::jsonb,
  pg_temp.st('a', (select id from _j where k = 'pair'))::text);
select pg_temp.ck('A3 ★没这个键 / 不是对象 ⇒ A / B 回包都不带',
  not (pg_temp.st('c', (select id from _j where k = 'old')) ? 'gold_new') and not (pg_temp.st('a', (select id from _j where k = 'old')) ? 'gold_new')
  and not (pg_temp.st('c', (select id from _j where k = 'bad')) ? 'gold_new') and not (pg_temp.st('a', (select id from _j where k = 'bad')) ? 'gold_new'));
select pg_temp.ck('S1 现有的键原样还在(ritual_new / wheel_new / 币 / 胜负)', pg_temp.st('c', (select id from _j where k = 'pair')) @> '{"coins":1,"won":true,"wheel_new":{"spade":2},"ritual_new":7}'::jsonb,
  pg_temp.st('c', (select id from _j where k = 'pair'))::text);

insert into public.finals_buckets (season_week, bucket_no, n, round, closed) values (4070908800, 0, 2, 2, false), (4070908800, 1, 2, 2, false);
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used) values (4070908800, 0, 1, 0, 0, 1), (4070908800, 1, 1, 0, 0, 1);
insert into _j values
  ('f0', pg_temp.job('finals', 'finals:4070908800:0:1:0', 4070908800, 'c', 'a', 'done', '{"bucket":0,"round":1,"match":0}',
     '{"ledger":{"won":true,"coins":3,"coins_b":4},"gold_new":{"ninja|p2eq_135":2},"gold_new_b":{"dice|p2eq_135":1}}')),
  ('f1', pg_temp.job('finals', 'finals:4070908800:1:1:0', 4070908800, 'c', 'a', 'done', '{"bucket":1,"round":1,"match":0}', '{"ledger":{"won":true,"coins":3,"coins_b":4}}'));
select pg_temp.ck('F1 决赛 A 方 ⇒ gold_new、币 3', pg_temp.fc('c', 0) @> '{"gold_new":{"ninja|p2eq_135":2},"coins":3}'::jsonb, pg_temp.fc('c', 0)::text);
select pg_temp.ck('F2 ★决赛 B 方 ⇒ 取 gold_new_b、币 4', pg_temp.fc('a', 0) @> '{"gold_new":{"dice|p2eq_135":1},"coins":4}'::jsonb, pg_temp.fc('a', 0)::text);
select pg_temp.ck('F3 没这个键 ⇒ 不带', not (pg_temp.fc('c', 1) ? 'gold_new') and (pg_temp.fc('c', 1) ->> 'coins')::int = 3, pg_temp.fc('c', 1)::text);

-- ── 记账合计(a 的账, 全部周): 积分赛 A 3+2 + 配对局 B 4 + 决赛 B 1 + 上一周积分赛 A 6 = 16 ──
select pg_temp.job('ranked', 'chk:gm:r1', 4070908800, 'a', 'b', 'done', '{}', '{"gold_new":{"ninja|p2eq_135":3,"ninja|p2eq_135#2":2},"gold_new_b":{"x|p2eq_135":70}}');
select pg_temp.job('ranked', 'chk:gm:o1', 4070304000, 'a', 'b', 'done', '{}', '{"gold_new":{"ninja|p2eq_135":6}}');                     -- 上一周(层数永久 ⇒ 算)
-- 不该算进 a 的：
select pg_temp.job('ranked', 'chk:gm:r2', 4070908800, 'c', 'a', 'done', '{}', '{"gold_new":{"q|p2eq_135":1},"gold_new_b":{"q|p2eq_135":60}}');   -- a 是积分赛的 B
select pg_temp.job('raid', 'chk:gm:x1', 4070908800, 'a', 'c', 'done', '{}', '{"gold_new":{"q|p2eq_135":80}}');                       -- 偷袭
select pg_temp.job('ranked', 'chk:gm:n1', 4070908800, 'a', 'b', 'claimed', '{}', '{"gold_new":{"q|p2eq_135":80}}');                  -- 没算完
select pg_temp.job('ranked', 'chk:gm:j1', 4070908800, 'a', 'b', 'done', '{}', '{"gold_new":{"q|p2eq_135":"abc"}}');                  -- 值不是数

select pg_temp.ck('W1 ★合计(全部周) = 3+2 + 4 + 1 + 6 = 16', public.econ_gold_sum(pg_temp.u('a')) = 16, public.econ_gold_sum(pg_temp.u('a'))::text);
select pg_temp.ck('W2 ★积分赛的 B / 偷袭 / 没算完 / 不是数都不算', public.econ_gold_sum(pg_temp.u('a')) < 20, public.econ_gold_sum(pg_temp.u('a'))::text);
select pg_temp.job('ranked', 'chk:gm:big', 4070908800, 'b', 'c', 'done', '{}', '{"gold_new":{"z|p2eq_135":999}}');
select pg_temp.ck('W4 ★单件单局按 50 夹(b: 这一局 50)', public.econ_gold_sum(pg_temp.u('b')) = 50, public.econ_gold_sum(pg_temp.u('b'))::text);
select pg_temp.ck('W3 账号为空 ⇒ 0', public.econ_gold_sum(null) = 0);

-- ── 盖章 ──
update public.referee_config set econ_on = true where id = 1;
insert into _j values
  ('on',  pg_temp.job('gauntlet', 'chk:gm:s1', 4070908800, 'a', 'c', 'pending', '{"pair":"true"}', null)),
  ('off', pg_temp.job('ranked', 'chk:gm:s3', 4070908800, 'a', 'b', 'pending', '{}', null));
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'on');
select pg_temp.ck('T1 ★开着: a_gold = a 的合计 16、b_gold = c 的合计(配对局 A 5 + 决赛 A 2 + 积分赛 A 1 = 8)',
  (select (meta ->> 'a_gold')::numeric = 16 and (meta ->> 'b_gold')::numeric = 8 from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.ck('T1 ★血契的 a_ritual 仍在(两个触发器不互相顶掉)、pair 原样',
  (select meta ? 'a_ritual' and meta ->> 'pair' = 'true' from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
update public.referee_config set econ_on = false where id = 1;
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'off');
select pg_temp.ck('T2 ★关着: 不盖',
  (select not (meta ? 'a_gold') and not (meta ? 'b_gold') from public.referee_jobs where job_id = (select id from _j where k = 'off')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'off')));

select pg_temp.ck('P1 权限: econ_gold_sum 谁都不能直接调; 回包函数 anon 没有、authenticated 有',
  not has_function_privilege('anon', 'public.econ_gold_sum(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_gold_sum(uuid)', 'execute')
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
