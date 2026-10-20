-- 20261020d 周日决赛服务器局发战斗内铸币 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：node tools/sql_sandbox.mjs server/supabase/migrations/20261020d_finals_coins.sql \
--             server/supabase/tests/20261020d_finals_coins_check.sql
--   · 内测服 / 生产（迁移执行之后；生产要用户同意）：SQL 编辑器整段粘贴运行。
--     ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 整个事务回滚，造的账号 / 配置改动 / 组 / 任务一个都不留。
-- 判据（每条配对照组）：
--   E  分母：真建任务那条路（referee_enqueue_finals）给这一场建出 a = 上侧、b = 下侧的任务
--   W1 写回 coins = 7 / coins_b = 4 ⇒ 账本两个数都在；matches.result 里没有币数（那一行所有登录用户读得到）
--   R0 任务还没算完 ⇒ pending
--   R1 不剧透：结果写了但那一轮没翻面 ⇒ 两边都 pending、不回数
--   R2 翻面后：A（a_account）拿 7、B（b_account）拿 4 —— 侧由服务端认，不是客户端报
--   R3 收盘（closed）也算翻面
--   R4 不在这一场的人 ⇒ not_in_match；没登录 ⇒ not_signed_in；没这个组 ⇒ no_bucket
--   O1 老裁判程序（结果单没有 coins_b）⇒ B 拿 0，A 照旧
--   O2 没有裁判局（兜底判）⇒ done、0；任务还没算完而结果已兜底 ⇒ 0；裁判结果被兜底抢先（superseded）⇒ 两边 0
--   C  coins_b 不可信的形状：越界 / 负数 / 字符串 ⇒ 0；小数 ⇒ 向下取整；周六任务不记 coins_b
--   G  权限：referee_finals_coins 只给 authenticated；referee_complete 仍只给 service_role
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as h, gen_random_uuid() as x,
         extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint + 6 * 86400 as wk;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ids to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.snap(p_name text) returns jsonb language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array('basic', 'stone', 'bamboo'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('basic', 'stone'), 'bottom', jsonb_build_array('bamboo')),
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name), 'season_level', 5)
$$;
-- 一个两人组（第 1 轮已过购物窗）
create or replace function pg_temp.bucket(p_b int) returns void language sql as $$
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
    values ((select wk from _ids), p_b, 2, 1, now() - interval '1 hour', false);
  insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
    values ((select wk from _ids), p_b, 0, (select a from _ids), 'amy', pg_temp.snap('amy')),
           ((select wk from _ids), p_b, 1, (select h from _ids), 'hal', pg_temp.snap('hal'));
$$;
-- 直接造一份已领的周日任务（第 1 轮第 0 场）
create or replace function pg_temp.job(p_b int) returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account,
      a_snapshot, b_snapshot, status, claimed_by, claimed_at, meta)
    values ('finals', format('finals:%s:%s:%s:%s', (select wk from _ids), p_b, 1, 0), (select wk from _ids), '9.9.9', 77,
      (select a from _ids), (select h from _ids), pg_temp.snap('amy'), pg_temp.snap('hal'), 'claimed', 'w1', now(),
      jsonb_build_object('bucket', p_b, 'round', 1, 'match', 0, 'seed0', 0, 'seed1', 1))
  returning job_id
$$;
create or replace function pg_temp.result(p_job bigint, p_extra jsonb) returns jsonb language sql as $$
  select jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', j.seed, 'client_version', j.client_version,
    'winner', 'b', 'steps', 4000, 'score_code', 1, 'replay_b64', 'QUJD') || coalesce(p_extra, '{}'::jsonb)
  from public.referee_jobs j where j.job_id = p_job
$$;
create or replace function pg_temp.coins(p_uid uuid, p_b int) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(p_uid);
  return public.referee_finals_coins((select wk from _ids), p_b, 1, 0);
end $$;
create or replace function pg_temp.reveal(p_b int) returns void language sql as $$
  update public.finals_buckets set round = 2 where season_week = (select wk from _ids) and bucket_no = p_b
$$;

-- ── 造数据 ──
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select a, 'authenticated', 'authenticated', false, now() from _ids
  union all select h, 'authenticated', 'authenticated', false, now() from _ids
  union all select x, 'authenticated', 'authenticated', false, now() from _ids;
update public.referee_config set finals_on = true, finals_version = '9.9.9' where id = 1;
insert into public.referee_versions (client_version, enabled) values ('9.9.9', true)
  on conflict (client_version) do update set enabled = true;

-- E ─ 真建任务那条路
select pg_temp.bucket(0);
create temp table _enq as select public.referee_enqueue_finals((select wk from _ids)) as n;
create temp table _j0 as select * from public.referee_jobs
  where match_key = format('finals:%s:0:1:0', (select wk from _ids));
select pg_temp.ck('E 分母: referee_enqueue_finals 建出这一场', (select count(*) from _j0) = 1, (select n::text from _enq));
select pg_temp.ck('E 任务 a = 上侧（amy）/ b = 下侧（hal）',
  (select a_account from _j0) = (select a from _ids) and (select b_account from _j0) = (select h from _ids));

-- R0 ─ 还没算完 ⇒ pending
select pg_temp.ck('R0 任务还没算完 ⇒ pending', pg_temp.coins((select a from _ids), 0)->>'status' = 'pending',
  pg_temp.coins((select a from _ids), 0)::text);

-- W1 ─ 裁判写回（两侧各带币）
create temp table _cl as select public.referee_claim('w1', array['9.9.9'], 5) as r;
select pg_temp.ck('W1 分母: 裁判领到这一份', ((select r from _cl)->0->>'job_id')::bigint = (select job_id from _j0));
create temp table _cp as select public.referee_complete((select job_id from _j0), 'w1',
  pg_temp.result((select job_id from _j0), '{"coins": 7, "coins_b": 4}'::jsonb)) as r;
select pg_temp.ck('W1 写回成功、没被兜底抢先', ((select r from _cp)->>'ok')::boolean and not ((select r from _cp)->>'superseded')::boolean,
  (select r::text from _cp));
select pg_temp.ck('W1 账本 coins = 7 / coins_b = 4',
  (select (result->'ledger'->>'coins')::int = 7 and (result->'ledger'->>'coins_b')::int = 4
     from public.referee_jobs where job_id = (select job_id from _j0)));
select pg_temp.ck('W1 matches.result 里没有币数',
  not ((select result from public.matches where match_id = (select match_id from _j0)) ?| array['coins', 'coins_b']));
select pg_temp.ck('W1 赛果写进 finals_results（下侧胜）',
  (select winner_side from public.finals_results where season_week = (select wk from _ids) and bucket_no = 0 and round = 1 and match_no = 0) = 1);

-- R1 ─ 不剧透
select pg_temp.ck('R1 没翻面 ⇒ A pending、不回数', pg_temp.coins((select a from _ids), 0)->>'status' = 'pending'
  and not (pg_temp.coins((select a from _ids), 0) ? 'coins'));
select pg_temp.ck('R1 没翻面 ⇒ B pending、不回数', pg_temp.coins((select h from _ids), 0)->>'status' = 'pending'
  and not (pg_temp.coins((select h from _ids), 0) ? 'coins'));

-- R2 ─ 翻面
select pg_temp.reveal(0);
select pg_temp.ck('R2 A（上侧）⇒ done、7', pg_temp.coins((select a from _ids), 0) = '{"ok": true, "status": "done", "coins": 7}'::jsonb,
  pg_temp.coins((select a from _ids), 0)::text);
select pg_temp.ck('R2 B（下侧）⇒ done、4', pg_temp.coins((select h from _ids), 0) = '{"ok": true, "status": "done", "coins": 4}'::jsonb,
  pg_temp.coins((select h from _ids), 0)::text);

-- R4 ─ 不相干 / 没登录 / 没这个组
select pg_temp.ck('R4 不在这一场 ⇒ not_in_match', pg_temp.coins((select x from _ids), 0)->>'reason' = 'not_in_match');
select pg_temp.ck('R4 没登录 ⇒ not_signed_in', pg_temp.coins(null, 0)->>'reason' = 'not_signed_in');
select pg_temp.ck('R4 没这个组 ⇒ no_bucket', pg_temp.coins((select a from _ids), 99)->>'reason' = 'no_bucket');

-- O1 / R3 ─ 老裁判程序（没有 coins_b）；收盘算翻面
select pg_temp.bucket(1);
create temp table _j1 as select pg_temp.job(1) as id;
select public.referee_complete((select id from _j1), 'w1', pg_temp.result((select id from _j1), '{"coins": 5}'::jsonb));
select pg_temp.ck('R3 对照: 没翻面没收盘 ⇒ pending', pg_temp.coins((select a from _ids), 1)->>'status' = 'pending');
update public.finals_buckets set closed = true where season_week = (select wk from _ids) and bucket_no = 1;
select pg_temp.ck('R3 收盘 ⇒ 翻面（A 拿 5）', (pg_temp.coins((select a from _ids), 1)->>'coins')::int = 5);
select pg_temp.ck('O1 老结果单没有 coins_b ⇒ B 拿 0（done）', pg_temp.coins((select h from _ids), 1) = '{"ok": true, "status": "done", "coins": 0}'::jsonb,
  pg_temp.coins((select h from _ids), 1)::text);
select pg_temp.ck('O1 账本 coins_b = 0', (select (result->'ledger'->>'coins_b')::int from public.referee_jobs where job_id = (select id from _j1)) = 0);

-- O2 ─ 没有裁判局 / 还没算完 / 被兜底抢先
select pg_temp.bucket(2);
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
  values ((select wk from _ids), 2, 1, 0, 0, 1);
select pg_temp.reveal(2);
select pg_temp.ck('O2 没有裁判局（兜底判）⇒ done、0', pg_temp.coins((select a from _ids), 2) = '{"ok": true, "status": "done", "coins": 0}'::jsonb);
create temp table _j2 as select pg_temp.job(2) as id;
select pg_temp.ck('O2 任务还没算完、结果已兜底 ⇒ 0', (pg_temp.coins((select h from _ids), 2)->>'coins')::int = 0);
create temp table _cp2 as select public.referee_complete((select id from _j2), 'w1',
  pg_temp.result((select id from _j2), '{"coins": 9, "coins_b": 6}'::jsonb)) as r;
select pg_temp.ck('O2 分母: 写回被记成 superseded', ((select r from _cp2)->>'superseded')::boolean);
select pg_temp.ck('O2 superseded ⇒ 两边都 0', (pg_temp.coins((select a from _ids), 2)->>'coins')::int = 0
  and (pg_temp.coins((select h from _ids), 2)->>'coins')::int = 0);

-- C ─ coins_b 的形状
create or replace function pg_temp.coins_b_of(p_v jsonb) returns int language plpgsql as $$
declare jid bigint; v int; bk int := 100 + (select count(*) from public.finals_buckets where season_week = (select wk from _ids))::int;
begin
  perform pg_temp.bucket(bk);
  jid := pg_temp.job(bk);
  perform public.referee_complete(jid, 'w1', pg_temp.result(jid, case when p_v is null then '{}'::jsonb
    else jsonb_build_object('coins_b', p_v) end));
  select (result->'ledger'->>'coins_b')::int into v from public.referee_jobs where job_id = jid;
  return v;
end $$;
select pg_temp.ck('C coins_b 5000 ⇒ 0', pg_temp.coins_b_of('5000'::jsonb) = 0);
select pg_temp.ck('C coins_b -3 ⇒ 0', pg_temp.coins_b_of('-3'::jsonb) = 0);
select pg_temp.ck('C coins_b "7"(字符串) ⇒ 0', pg_temp.coins_b_of('"7"'::jsonb) = 0);
select pg_temp.ck('C coins_b 3.9 ⇒ 3', pg_temp.coins_b_of('3.9'::jsonb) = 3);
select pg_temp.ck('C 对照: coins_b 12 ⇒ 12', pg_temp.coins_b_of('12'::jsonb) = 12);
create temp table _jg as select 0::bigint as job_id;
with i as (insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
    status, claimed_by, claimed_at, meta)
  values ('gauntlet', 'chk:' || gen_random_uuid()::text, (select wk from _ids), '9.9.9', 77, null, '{}'::jsonb, '{}'::jsonb,
    'claimed', 'w1', now(), '{}'::jsonb) returning job_id)
update _jg set job_id = (select job_id from i);
select public.referee_complete((select job_id from _jg), 'w1', pg_temp.result((select job_id from _jg), '{"coins": 3, "coins_b": 5}'::jsonb));
select pg_temp.ck('C 周六任务: 账本记 coins、不记 coins_b',
  (select (result->'ledger'->>'coins')::int = 3 and not (result->'ledger' ? 'coins_b') from public.referee_jobs where job_id = (select job_id from _jg)));

-- G ─ 权限
select pg_temp.ck('G referee_finals_coins: authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.referee_finals_coins(bigint, int, int, int)', 'execute')
  and not has_function_privilege('anon', 'public.referee_finals_coins(bigint, int, int, int)', 'execute'));
select pg_temp.ck('G referee_complete 仍只给 service_role',
  has_function_privilege('service_role', 'public.referee_complete(bigint, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_complete(bigint, text, jsonb)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 30 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
