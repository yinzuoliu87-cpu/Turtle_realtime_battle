-- 20261101b 决赛日快照校验 + 坏快照回退 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261101b_finals_snapshot_guard
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261101b_finals_snapshot_guard
-- 时间：同 20261101 的检查脚本（本事务内 env = beta、删约束、偏移拨到「真实那一周 + 3 周」的周日）。
-- 造人：4 个号（≤ 8 人 ⇒ 每人一组、坐下即收盘 ⇒ 20:00 冠军杯赛 4 人：第 1 轮两场）。
--   p1 好快照（gw 7 ⇒ 杯 0 号）/ p3 入座快照坏、没有别的（gw 6 ⇒ 杯 1 号）/ p2 入座快照坏、闯关赛有一份好的（gw 5 ⇒ 杯 2 号）/ p4 好（gw 4 ⇒ 杯 3 号）
--   ⇒ 杯第 1 轮：场 0 = p1（上）vs p4（下）；场 1 = p3（上，坏）vs p2（下，回退好）。
-- 判据：
--   U1 finals_update_snapshot：四种坏快照（没统领 / 统领重复 / 一只分到两路 / 没有 lane_assign）全拒、原快照不动；对照：好快照收
--   S1 finals_seat：p2 换成闯关赛那份（最新的那份是坏的 ⇒ 取次新的好的，去掉 origin）；p3 一份都没有 ⇒ 照原样坐下；p1 / p4 原样
--   S2 finals_cup_seat：同一条回退（成表前把 p4 组里那份写坏 ⇒ 杯里回退成他入座时那份；p2 已是好的；p3 仍坏）
--   E1 ★场 1：上半区 p3 没有能开打的快照 ⇒ 当场判下半区（side 1）赢、seed_used 0、不建任务（P21：原来是等 24 分钟后判上半区晋级）
--   E2 场 0：两侧都好 ⇒ 建任务、任务里是好快照
--   E3 裁判判 a_bad_snapshot（与本判据不一致、回退不出别的）⇒ 下一次推进当场判 A 负（side 1 赢）
--   E4 ★本轮在「备战结束 + 60 秒」就翻面（不等 3 倍时长）
--   R1 老代码建的任务（任务里 A 是坏快照）被裁判判坏 ⇒ 回退出入座时那份好的 ⇒ 任务换快照、退回 pending、attempts 归零；参赛者快照也写回
--   P  finals_good_snapshot 客户端调不了；finals_update_snapshot 仍给 authenticated
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ctx as
  select extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint + 3 * 604800 as wk;
create temp table _ppl (i int primary key, id uuid not null);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ctx to public;
grant all on _ppl to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.wk() returns bigint language sql as $$ select wk from _ctx $$;
create or replace function pg_temp.at(p_sec int) returns void language plpgsql as $$
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (to_timestamp(pg_temp.wk() + 6 * 86400 + 18 * 3600 + p_sec) - now())))::bigint where id = 1;
end $$;
create or replace function pg_temp.uid(p_i int) returns uuid language sql as $$ select id from _ppl where i = p_i $$;
-- 好快照 / 四种坏快照
create or replace function pg_temp.good(p_name text) returns jsonb language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array('basic', 'stone', 'bamboo'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('basic', 'stone'), 'bottom', jsonb_build_array('bamboo')),
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name), 'season_level', 5)
$$;
create or replace function pg_temp.bad(p_kind text, p_name text) returns jsonb language sql as $$
  select case p_kind
    when 'none' then jsonb_build_object('leaders', '[]'::jsonb, 'profile', jsonb_build_object('name', p_name))
    when 'dup' then pg_temp.good(p_name) || jsonb_build_object('leaders', jsonb_build_array('basic', 'basic', 'stone'))
    when 'twice' then pg_temp.good(p_name) || jsonb_build_object('lane_assign',
         jsonb_build_object('top', jsonb_build_array('basic', 'stone', 'bamboo'), 'bottom', jsonb_build_array('bamboo')))
    else pg_temp.good(p_name) - 'lane_assign' end
$$;
create or replace function pg_temp.ent(p_b int, p_acc uuid) returns jsonb language sql as $$
  select snapshot from public.finals_entrants where season_week = pg_temp.wk() and bucket_no = p_b and account_id = p_acc
$$;
create or replace function pg_temp.res(p_b int, p_r int, p_m int) returns public.finals_results language sql as $$
  select * from public.finals_results where season_week = pg_temp.wk() and bucket_no = p_b and round = p_r and match_no = p_m
$$;
create or replace function pg_temp.job(p_b int, p_r int, p_m int) returns public.referee_jobs language sql as $$
  select * from public.referee_jobs where match_key = format('finals:%s:%s:%s:%s', pg_temp.wk(), p_b, p_r, p_m)
$$;
create or replace function pg_temp.cupb() returns public.finals_buckets language sql as $$
  select * from public.finals_buckets where season_week = pg_temp.wk() and bucket_no = public.finals_cup_no()
$$;

-- ── 造数据 ──
update public.service_env set env = 'beta' where id = 1;
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.referee_config set finals_on = true, finals_version = '9.9.9', finals_sequential = true where id = 1;
insert into public.referee_versions (client_version, enabled) values ('9.9.9', true)
  on conflict (client_version) do update set enabled = true;
insert into _ppl (i, id) select g, gen_random_uuid() from generate_series(1, 6) g;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _ppl;
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl) values
  (pg_temp.wk(), pg_temp.uid(1), 'p1', pg_temp.good('p1'), 7, 0),
  (pg_temp.wk(), pg_temp.uid(2), 'p2', pg_temp.bad('none', 'p2'), 5, 0),
  (pg_temp.wk(), pg_temp.uid(3), 'p3', pg_temp.bad('twice', 'p3'), 6, 0),
  (pg_temp.wk(), pg_temp.uid(4), 'p4', pg_temp.good('p4'), 4, 0);
-- p2 闯关赛上传过两份：早的一份好（带 origin），最新的一份坏
insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, uploaded_at) values
  (pg_temp.uid(2), pg_temp.wk(), 4, 0, pg_temp.good('p2') || '{"origin": "gauntlet"}'::jsonb, '9.9.9', now() - interval '2 hours'),
  (pg_temp.uid(2), pg_temp.wk(), 5, 0, pg_temp.bad('dup', 'p2'), '9.9.9', now() - interval '1 hour');
select pg_temp.ck('分母: 判据本身认得出好坏（好 1 / 四种坏 0）',
  public.referee_lineup_ok(pg_temp.good('x')) and not public.referee_lineup_ok(pg_temp.bad('none', 'x'))
  and not public.referee_lineup_ok(pg_temp.bad('dup', 'x')) and not public.referee_lineup_ok(pg_temp.bad('twice', 'x'))
  and not public.referee_lineup_ok(pg_temp.bad('nolane', 'x')));

-- S1 入座（4 人 ⇒ 每人一组）
select pg_temp.at(0);
select pg_temp.ck('S1 分母: finals_seat 分了 4 组', public.finals_seat(pg_temp.wk()) = 4);
create temp table _s1 as select account_id, bucket_no, snapshot from public.finals_entrants where season_week = pg_temp.wk();
select pg_temp.ck('S1 ★p2 入座快照坏 ⇒ 换成闯关赛里最新的一份好的（去掉 origin）',
  (select snapshot from _s1 where account_id = pg_temp.uid(2)) = pg_temp.good('p2'),
  (select snapshot::text from _s1 where account_id = pg_temp.uid(2)));
select pg_temp.ck('S1 p3 一份能开打的都没有 ⇒ 照原样坐下（到建任务时判）',
  (select snapshot from _s1 where account_id = pg_temp.uid(3)) = pg_temp.bad('twice', 'p3'));
select pg_temp.ck('S1 对照: p1 / p4 好快照原样',
  (select snapshot from _s1 where account_id = pg_temp.uid(1)) = pg_temp.good('p1')
  and (select snapshot from _s1 where account_id = pg_temp.uid(4)) = pg_temp.good('p4'));

-- S2 冠军杯赛成表（20:00:30）。成表前把 p4 组里那份写坏（他入座时那份是好的）⇒ 杯里应回退成好的
update public.finals_entrants set snapshot = pg_temp.bad('nolane', 'p4')
 where season_week = pg_temp.wk() and account_id = pg_temp.uid(4) and bucket_no <> public.finals_cup_no();
select pg_temp.at(2 * 3600 + 30);
select pg_temp.ck('S2 分母: 冠军杯赛成表 4 人', public.finals_cup_seat(pg_temp.wk()) = 4);
select pg_temp.ck('S2 杯里: p1 = 0 号 / p3 = 1 号 / p2 = 2 号 / p4 = 3 号（场 0 = p1 vs p4、场 1 = p3 vs p2）',
  (select string_agg(name, ',' order by seed) from public.finals_entrants where season_week = pg_temp.wk() and bucket_no = public.finals_cup_no()) = 'p1,p3,p2,p4');
select pg_temp.ck('S2 ★成表时回退: p4 组里那份坏了 ⇒ 杯里是他入座时那份好的', pg_temp.ent(public.finals_cup_no(), pg_temp.uid(4)) = pg_temp.good('p4'),
  pg_temp.ent(public.finals_cup_no(), pg_temp.uid(4))::text);
select pg_temp.ck('S2 杯里 p2 是好快照、p3 仍是坏的',
  pg_temp.ent(public.finals_cup_no(), pg_temp.uid(2)) = pg_temp.good('p2')
  and pg_temp.ent(public.finals_cup_no(), pg_temp.uid(3)) = pg_temp.bad('twice', 'p3'));

-- U1 备战时推快照（杯第 1 轮购物窗内，p1）
select pg_temp.at(2 * 3600 + 60);
select pg_temp.as_user(pg_temp.uid(1));
create temp table _u1 as select
  public.finals_update_snapshot(pg_temp.wk(), public.finals_cup_no(), pg_temp.bad('none', 'p1')) as a,
  public.finals_update_snapshot(pg_temp.wk(), public.finals_cup_no(), pg_temp.bad('dup', 'p1')) as b,
  public.finals_update_snapshot(pg_temp.wk(), public.finals_cup_no(), pg_temp.bad('twice', 'p1')) as c,
  public.finals_update_snapshot(pg_temp.wk(), public.finals_cup_no(), pg_temp.bad('nolane', 'p1')) as d;
select pg_temp.as_user(null);
select pg_temp.ck('U1 ★四种坏快照全拒、原快照不动',
  not (select a or b or c or d from _u1) and pg_temp.ent(public.finals_cup_no(), pg_temp.uid(1)) = pg_temp.good('p1'),
  (select format('%s %s %s %s', a, b, c, d) from _u1));
select pg_temp.as_user(pg_temp.uid(1));
create temp table _u2 as select public.finals_update_snapshot(pg_temp.wk(), public.finals_cup_no(),
  pg_temp.good('p1') || '{"season_level": 6}'::jsonb) as ok;
select pg_temp.as_user(null);
select pg_temp.ck('U1 对照: 好快照收下、写进参赛者',
  (select ok from _u2) and (pg_temp.ent(public.finals_cup_no(), pg_temp.uid(1)) ->> 'season_level') = '6');

-- E1 / E2 购物窗一关（+200）
select pg_temp.at(2 * 3600 + 30 + 200);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('E1 ★场 1 上半区 p3 没有能开打的快照 ⇒ 当场判下半区赢、seed_used 0、不建任务',
  (pg_temp.res(public.finals_cup_no(), 1, 1)).winner_side = 1 and (pg_temp.res(public.finals_cup_no(), 1, 1)).seed_used = 0
  and (pg_temp.job(public.finals_cup_no(), 1, 1)).job_id is null,
  format('winner=%s job=%s', (pg_temp.res(public.finals_cup_no(), 1, 1)).winner_side, (pg_temp.job(public.finals_cup_no(), 1, 1)).job_id));
select pg_temp.ck('E2 场 0 两侧都好 ⇒ 建任务、任务里是两份好快照',
  (pg_temp.job(public.finals_cup_no(), 1, 0)).status = 'pending'
  and public.referee_lineup_ok((pg_temp.job(public.finals_cup_no(), 1, 0)).a_snapshot)
  and public.referee_lineup_ok((pg_temp.job(public.finals_cup_no(), 1, 0)).b_snapshot));

-- E3 裁判判 a_bad_snapshot（与本判据不一致）⇒ 回退不出别的 ⇒ 当场判 A 负
update public.referee_jobs set status = 'claimed', claimed_by = 'chk', claimed_at = now(), attempts = 1
 where job_id = (pg_temp.job(public.finals_cup_no(), 1, 0)).job_id;
select public.referee_fail((pg_temp.job(public.finals_cup_no(), 1, 0)).job_id, 'chk', 'a_bad_snapshot', true);
select pg_temp.ck('E3 分母: 任务永久失败 a_bad_snapshot', (pg_temp.job(public.finals_cup_no(), 1, 0)).status = 'failed'
  and (pg_temp.job(public.finals_cup_no(), 1, 0)).error = 'a_bad_snapshot');
select pg_temp.at(2 * 3600 + 30 + 230);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('E3 ★下一次推进当场判 A（上半区）负: side 1 赢、seed_used 0; 任务不重开',
  (pg_temp.res(public.finals_cup_no(), 1, 0)).winner_side = 1 and (pg_temp.res(public.finals_cup_no(), 1, 0)).seed_used = 0
  and (pg_temp.job(public.finals_cup_no(), 1, 0)).status = 'failed');

-- E4 本轮在备战结束 + 60 就翻（不等 3 倍时长 1440）
select pg_temp.ck('E4 分母: 还没翻（230 秒 < 240）', (pg_temp.cupb()).round = 1);
select pg_temp.at(2 * 3600 + 30 + 241);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('E4 ★241 秒就翻面进第 2 轮（原来坏快照要等到 1440 秒）', (pg_temp.cupb()).round = 2,
  format('round=%s', (pg_temp.cupb()).round));

-- R1 老代码建的任务（A 是坏快照）被裁判判坏 ⇒ 回退出入座时那份好的 ⇒ 任务换快照、重算
--   造法：杯第 2 轮（p4 vs p2）购物窗关之前，手工插一份老样子的任务（A = 坏快照），并把 p4 的参赛者快照写坏
select pg_temp.at(2 * 3600 + 30 + 300);
update public.finals_entrants set snapshot = pg_temp.bad('dup', 'p4')
 where season_week = pg_temp.wk() and bucket_no = public.finals_cup_no() and account_id = pg_temp.uid(4);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account,
    a_snapshot, b_snapshot, status, attempts, error, done_at, meta)
  values ('finals', format('finals:%s:%s:2:0', pg_temp.wk(), public.finals_cup_no()), pg_temp.wk(), '9.9.9', 4242,
    pg_temp.uid(4), pg_temp.uid(2), pg_temp.bad('dup', 'p4'), pg_temp.good('p2'), 'failed', 1, 'a_bad_snapshot', now(),
    jsonb_build_object('bucket', public.finals_cup_no(), 'round', 2, 'match', 0));
select pg_temp.at(2 * 3600 + 30 + 241 + 200);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('R1 ★任务换上回退出的好快照（入座时那份）、退回 pending、attempts 归零、没判结果',
  (pg_temp.job(public.finals_cup_no(), 2, 0)).status = 'pending' and (pg_temp.job(public.finals_cup_no(), 2, 0)).attempts = 0
  and (pg_temp.job(public.finals_cup_no(), 2, 0)).error is null
  and (pg_temp.job(public.finals_cup_no(), 2, 0)).a_snapshot = pg_temp.good('p4')
  and (pg_temp.res(public.finals_cup_no(), 2, 0)).winner_side is null,
  format('%s / %s', (pg_temp.job(public.finals_cup_no(), 2, 0)).status, (pg_temp.job(public.finals_cup_no(), 2, 0)).a_snapshot));
select pg_temp.ck('R1 参赛者快照也写回成好的（之后的轮次也用它）', pg_temp.ent(public.finals_cup_no(), pg_temp.uid(4)) = pg_temp.good('p4'));

-- P 权限
select pg_temp.ck('P finals_good_snapshot 客户端调不了; finals_update_snapshot 仍给 authenticated、不给 anon',
  not has_function_privilege('authenticated', 'public.finals_good_snapshot(bigint, uuid, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.finals_good_snapshot(bigint, uuid, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.finals_update_snapshot(bigint, int, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.finals_update_snapshot(bigint, int, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_enqueue_finals(bigint)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 18 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
