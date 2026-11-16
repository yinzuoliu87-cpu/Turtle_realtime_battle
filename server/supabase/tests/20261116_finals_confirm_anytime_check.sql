-- 20261116 背包「确定阵容」什么时候交都算 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261116_finals_confirm_anytime
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261116_finals_confirm_anytime
-- 时间：同 20261101b 的检查脚本（本事务内 env = beta、删约束、偏移拨到「真实那一周 + 3 周」的周日）。
-- 造人：4 个晋级（≤ 8 人 ⇒ 每人一组、坐下即收盘 ⇒ 20:00 冠军杯赛 4 人）+ 1 个没晋级的 p5。
-- 判据：
--   C1 入座前：p1 交新阵容 ⇒ 'seat'、finals_pending 换成新的；坏阵容 ⇒ bad_lineup 且不动；p5 没晋级 ⇒ not_entered
--   C2 入座：p1 组里坐下的是 C1 交的那份
--   C3 小组收盘后、冠军杯成表前：p1 交 ⇒ 'cup'（组冠军）；成表后杯里是这一份、组里那一行的待生效清空不影响
--   C4 杯第 1 轮备战窗内：p2 交 ⇒ 'now'、杯里 snapshot 当场换掉、没有待生效
--   C5 锁定之后：p4 交 ⇒ 'next'、snapshot 不动、存进待生效；本轮建任务时用的仍是旧的、待生效留着
--   C6 下一轮：锁定时刻挪到待生效之后 ⇒ 建任务前换上、待生效清空
--   C7 已收盘 / 没参赛（p5 分组后）⇒ closed
--   P  finals_confirm_snapshot 给 authenticated、不给 anon
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
create or replace function pg_temp.good(p_name text) returns jsonb language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array('basic', 'stone', 'bamboo'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('basic', 'stone'), 'bottom', jsonb_build_array('bamboo')),
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name), 'season_level', 5)
$$;
create or replace function pg_temp.bad(p_name text) returns jsonb language sql as $$
  select pg_temp.good(p_name) || jsonb_build_object('leaders', jsonb_build_array('basic', 'basic', 'stone'))
$$;
create or replace function pg_temp.conf(p_i int, p_snap jsonb) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.uid(p_i));
  return public.finals_confirm_snapshot(pg_temp.wk(), p_snap);
end $$;
create or replace function pg_temp.ent(p_b int, p_i int) returns public.finals_entrants language sql as $$
  select * from public.finals_entrants where season_week = pg_temp.wk() and bucket_no = p_b and account_id = pg_temp.uid(p_i)
$$;
create or replace function pg_temp.cup() returns int language sql as $$ select public.finals_cup_no() $$;

-- ── 造数据 ──
update public.service_env set env = 'beta' where id = 1;
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.referee_config set finals_on = true, finals_version = '9.9.9', finals_sequential = true where id = 1;
insert into public.referee_versions (client_version, enabled) values ('9.9.9', true)
  on conflict (client_version) do update set enabled = true;
insert into _ppl (i, id) select g, gen_random_uuid() from generate_series(1, 5) g;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _ppl;
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl) values
  (pg_temp.wk(), pg_temp.uid(1), 'p1', pg_temp.good('p1'), 7, 0),
  (pg_temp.wk(), pg_temp.uid(2), 'p2', pg_temp.good('p2'), 6, 0),
  (pg_temp.wk(), pg_temp.uid(3), 'p3', pg_temp.good('p3'), 5, 0),
  (pg_temp.wk(), pg_temp.uid(4), 'p4', pg_temp.good('p4'), 4, 0);

-- C1 入座前（周日 17:00）
select pg_temp.at(-3600);
create temp table _c1 as select
  pg_temp.conf(1, pg_temp.good('p1_seat')) as a,
  pg_temp.conf(2, pg_temp.bad('p2_bad')) as b,
  pg_temp.conf(5, pg_temp.good('p5')) as c;
select pg_temp.ck('C1 ★入座前交 ⇒ ok / applies seat', (select a from _c1) = '{"ok": true, "applies": "seat"}'::jsonb, (select a::text from _c1));
select pg_temp.ck('C1 ★finals_pending 换成刚交的那份',
  (select snapshot from public.finals_pending where season_week = pg_temp.wk() and account_id = pg_temp.uid(1)) = pg_temp.good('p1_seat'));
select pg_temp.ck('C1 坏阵容 ⇒ bad_lineup、晋级那一行不动',
  (select b from _c1) = '{"ok": false, "reason": "bad_lineup"}'::jsonb
  and (select snapshot from public.finals_pending where season_week = pg_temp.wk() and account_id = pg_temp.uid(2)) = pg_temp.good('p2'),
  (select b::text from _c1));
select pg_temp.ck('C1 没晋级 ⇒ not_entered', (select c from _c1) = '{"ok": false, "reason": "not_entered"}'::jsonb, (select c::text from _c1));

-- C2 入座（18:00）
select pg_temp.at(0);
select pg_temp.ck('C2 分母: finals_seat 分了 4 组', public.finals_seat(pg_temp.wk()) = 4);
select pg_temp.ck('C2 ★p1 组里坐下的是入座前交的那份',
  (select snapshot from public.finals_entrants where season_week = pg_temp.wk() and account_id = pg_temp.uid(1) and bucket_no <> pg_temp.cup())
  = pg_temp.good('p1_seat'));

-- C3 小组都已收盘（每人一组），冠军杯成表前（19:00）：p1 是自己组的冠军
select pg_temp.at(3600);
create temp table _c3 as select pg_temp.conf(1, pg_temp.good('p1_cup')) as a;
select pg_temp.ck('C3 ★组冠军、冠军杯没成表 ⇒ applies cup', (select a from _c3) = '{"ok": true, "applies": "cup"}'::jsonb, (select a::text from _c3));
select pg_temp.at(2 * 3600 + 30);
select pg_temp.ck('C3 分母: 冠军杯赛成表 4 人', public.finals_cup_seat(pg_temp.wk()) = 4);
select pg_temp.ck('C3 ★杯里 p1 是成表前交的那份', (pg_temp.ent(pg_temp.cup(), 1)).snapshot = pg_temp.good('p1_cup'),
  (pg_temp.ent(pg_temp.cup(), 1)).snapshot::text);
select pg_temp.ck('C3 对照: 杯里 p3 仍是入座那份', (pg_temp.ent(pg_temp.cup(), 3)).snapshot = pg_temp.good('p3'));

-- C4 杯第 1 轮备战窗内（成表后 30 秒）：p2 交 ⇒ 当场生效
select pg_temp.at(2 * 3600 + 60);
create temp table _c4 as select pg_temp.conf(2, pg_temp.good('p2_now')) as a;
select pg_temp.ck('C4 ★备战窗内 ⇒ applies now', (select a from _c4) = '{"ok": true, "applies": "now"}'::jsonb, (select a::text from _c4));
select pg_temp.ck('C4 ★杯里 snapshot 当场换掉、没有待生效',
  (pg_temp.ent(pg_temp.cup(), 2)).snapshot = pg_temp.good('p2_now') and (pg_temp.ent(pg_temp.cup(), 2)).pending_snapshot is null);

-- C5 锁定之后（成表后 300 秒 > 备战 180 秒）：p4 交 ⇒ 下一轮
select pg_temp.at(2 * 3600 + 330);
create temp table _c5 as select pg_temp.conf(4, pg_temp.good('p4_next')) as a;
select pg_temp.ck('C5 ★锁定之后 ⇒ applies next', (select a from _c5) = '{"ok": true, "applies": "next"}'::jsonb, (select a::text from _c5));
select pg_temp.ck('C5 snapshot 不动、存进待生效',
  (pg_temp.ent(pg_temp.cup(), 4)).snapshot = pg_temp.good('p4') and (pg_temp.ent(pg_temp.cup(), 4)).pending_snapshot = pg_temp.good('p4_next'));
select pg_temp.ck('C5 分母: 本轮建了任务', public.referee_enqueue_finals(pg_temp.wk()) >= 1);
select pg_temp.ck('C5 ★本轮任务里 p4 还是旧阵容、待生效留着',
  exists (select 1 from public.referee_jobs where season_week = pg_temp.wk() and kind = 'finals'
           and ((a_account = pg_temp.uid(4) and a_snapshot = pg_temp.good('p4')) or (b_account = pg_temp.uid(4) and b_snapshot = pg_temp.good('p4'))))
  and (pg_temp.ent(pg_temp.cup(), 4)).pending_snapshot = pg_temp.good('p4_next'));

-- C6 下一轮：把杯的 round_at 挪到 p4 交之前一点（锁定时刻 = round_at + 180 秒 > 待生效时刻）、钟拨过锁定 ⇒ 建任务前换上
update public.finals_buckets set round_at = (pg_temp.ent(pg_temp.cup(), 4)).pending_at - interval '10 seconds'
 where season_week = pg_temp.wk() and bucket_no = pg_temp.cup();
select pg_temp.at(2 * 3600 + 330 + 200);
select public.referee_enqueue_finals(pg_temp.wk());
select pg_temp.ck('C6 ★锁定前交的待生效 ⇒ 换上、待生效清空',
  (pg_temp.ent(pg_temp.cup(), 4)).snapshot = pg_temp.good('p4_next') and (pg_temp.ent(pg_temp.cup(), 4)).pending_snapshot is null
  and (pg_temp.ent(pg_temp.cup(), 4)).pending_at is null, (pg_temp.ent(pg_temp.cup(), 4)).snapshot::text);

-- C7 分组之后没参赛的 p5 ⇒ closed
create temp table _c7 as select pg_temp.conf(5, pg_temp.good('p5')) as a;
select pg_temp.ck('C7 没参赛 ⇒ closed', (select a from _c7) = '{"ok": false, "reason": "closed"}'::jsonb, (select a::text from _c7));

-- P 权限
select pg_temp.as_user(null);
select pg_temp.ck('P finals_confirm_snapshot 给 authenticated、不给 anon',
  has_function_privilege('authenticated', 'public.finals_confirm_snapshot(bigint, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.finals_confirm_snapshot(bigint, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_enqueue_finals(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.finals_cup_seat(bigint)', 'execute'));

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
