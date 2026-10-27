-- 20261027 闯关赛在线瑞士轮 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261027_gauntlet_online_queue
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、删的约束、插的行一个都不留。
-- 假时间照 20261021 / 20261026b 检查脚本：本事务里删掉 server_clock_prod_zero、env 切 beta、写偏移（回滚即还原）。
-- 判据（每组都配了分母或对照）：
--   A  权限：三个排队接口只给 authenticated；调度器接口只给 service_role；内部函数 / 两张新表客户端碰不到
--   G  闸：join 与 referee_gauntlet_start 对同一输入回同一个 reason（未登录 / 开关 / 版本 / 规则版本 / 周 / 时段三点 / 阵容 / 打完 / 场次对不上）；
--      不带版本参数时取请求头 X-Client-Version
--   Q  配对：两个真人同格子 ⇒ 只建 1 条任务、两边 paired、side 一 a 一 b、A = 先来的；重复 join 不多建；格子锁真的拿了；
--      不同格子不配；心跳过期不配（并被置 expired）；交手过不配（配对局 / 旧路快照局两种）+ 对照（第三个人照配）；
--      版本不同不配；取消；等待秒数；90 秒兜底（89 秒不兜、91 秒兜、陪练号不兜 + 对照）；陪练号对陪练号 / 真人对陪练号照配；
--      同一账号同一周两条 waiting 被唯一索引挡住
--   S  调度器视图：排队（真人 + 陪练号、is_bot、心跳断了的不列）、交过手的人（两个方向）、在打的、陪练号的格子 / 在算 / 排队 / 打完 / 晋级 / 上一局
--   W  写回：两边战绩互反、matches 一行（left = A / right = B）、两边快照池、排队行 done、账本 coins / coins_b；
--      B 查 referee_job_status 回 B 的视角；两边各自第 4 胜都登记决赛；B 删号后照样算完只记 A（排队行 / 陪练号名单随删号走）；
--      算失败的配对局 ⇒ 两边排队行作废、各自重排、两人不再互配
--   P  旧入口：referee_gauntlet_start 认配对局里的 B（回那一场、对手卡是 A）；被打的快照主人不受影响；
--      referee_gauntlet_pick 的排除表看配对局里我当 B 的那一侧 + 对照
--   E  旧路任务逐字不变：改前的 referee_complete（20261026b）/ referee_job_status（20261023）函数体原样抄成 pg_temp 函数，
--      与新函数对同一输入（周六机器人局 / 周六真人快照局 / 兜底局 / 周日决赛局 + 未算完 / 算失败）比回包与落账
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array[
  'h1','h2','h3','h4','h5','h6','h7','h8','h9','h10','h11','h12','h13','h14','h15','h16','h17','h18','h19',
  'k1','k2','k3','k4','k5','d1','d2','e1','e2','z1','z2','z3','z4','p1','p2','p3',
  'x1','x2','x3','x4','xb','y1','y2','y3','y4','yb']);
create temp table _r (k text primary key, r jsonb);
create temp table _fw as select 4102444800::bigint as wk;   -- E 组用的假周（2100 年，不撞真实数据）
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u, _fw to public;
grant all on _r to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.keep(p_k text, p_r jsonb) returns jsonb language sql as $$
  insert into _r (k, r) values (p_k, p_r) on conflict (k) do update set r = excluded.r returning r
$$;
create or replace function pg_temp.r(p_k text) returns jsonb language sql as $$ select r from _r where k = p_k $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 假时间 = 真实时间所在那一周的第 wd 天（ISO 1~7）h:m（UTC）；向上取整同 20261021
create or replace function pg_temp.set_fake(wd int, h int, m int default 0) returns void language plpgsql as $$
declare wk timestamptz := date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (wk + make_interval(days => wd - 1, hours => h, mins => m)) - now()))::bigint where id = 1;
end $$;
create or replace function pg_temp.fake_week() returns bigint language sql as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
create or replace function pg_temp.snap(p_name text) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name, 'tag', 'chk-' || p_name),
    'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')),
    'season_level', 3)
$$;
create or replace function pg_temp.rec(p_k text, p_gw int, p_gl int) returns void language sql as $$
  insert into public.gauntlet_records (season_week, account_id, gw, gl) values (pg_temp.fake_week(), pg_temp.u(p_k), p_gw, p_gl)
    on conflict (season_week, account_id) do update set gw = excluded.gw, gl = excluded.gl
$$;
create or replace function pg_temp.j(p_k text, p_mn int default 0, p_cv text default '9.9.9') returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  return public.gauntlet_queue_join(pg_temp.fake_week(), pg_temp.snap(p_k), p_mn, p_cv, 1);
end $$;
create or replace function pg_temp.p(p_k text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  return public.gauntlet_queue_poll(pg_temp.fake_week());
end $$;
create or replace function pg_temp.c(p_k text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  return public.gauntlet_queue_cancel(pg_temp.fake_week());
end $$;
create or replace function pg_temp.js(p_k text, p_job bigint) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  return public.referee_job_status(p_job);
end $$;
create or replace function pg_temp.qrow(p_k text) returns public.gauntlet_queue language sql as $$
  select * from public.gauntlet_queue where season_week = pg_temp.fake_week() and account_id = pg_temp.u(p_k)
   order by id desc limit 1
$$;
create or replace function pg_temp.njobs() returns bigint language sql as $$
  select count(*) from public.referee_jobs
   where season_week = pg_temp.fake_week() and kind = 'gauntlet'
     and (a_account in (select id from _u) or b_account in (select id from _u))
$$;
create or replace function pg_temp.claim(p_job bigint) returns void language sql as $$
  update public.referee_jobs set status = 'claimed', claimed_by = 'chk-worker', claimed_at = now(), attempts = 1
   where job_id = p_job
$$;
create or replace function pg_temp.res(p_job bigint, p_winner text, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql as $$
  select jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', j.seed, 'client_version', j.client_version,
           'winner', p_winner, 'steps', 100, 'replay_b64', 'QUJD', 'score_code', 1) || p_extra
    from public.referee_jobs j where j.job_id = p_job
$$;
create or replace function pg_temp.done(p_job bigint, p_winner text, p_extra jsonb default '{}'::jsonb) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.claim(p_job);
  return public.referee_complete(p_job, 'chk-worker', pg_temp.res(p_job, p_winner, p_extra));
end $$;
-- 同一输入：join 与旧接口 referee_gauntlet_start 各调一次，回「join 的 reason|start 的 reason」
create or replace function pg_temp.both(p_uid uuid, p_week bigint, p_snap jsonb, p_mn int, p_cv text, p_rv int) returns text
language plpgsql as $$
declare a text; b text;
begin
  perform pg_temp.as_user(p_uid);
  a := public.gauntlet_queue_join(p_week, p_snap, p_mn, p_cv, p_rv) ->> 'reason';
  b := public.referee_gauntlet_start(p_week, p_snap, p_mn, p_cv, p_rv) ->> 'reason';
  return coalesce(a, '-') || '|' || coalesce(b, '-');
end $$;

-- 内测服口径（本事务里）：能写假时间
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false, gauntlet_server_pick = true where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 1), ('9.9.8', true, 1)
  on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;
insert into public.bot_accounts (account_id) select id from _u where k in ('k1', 'k2', 'k3', 'k4', 'k5');
select pg_temp.set_fake(6, 12);

-- ── A 权限 ──
select pg_temp.ck('A 三个排队接口: anon 没有、authenticated 有',
  not has_function_privilege('anon', 'public.gauntlet_queue_join(bigint, jsonb, int, text, int)', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_poll(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_cancel(bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.gauntlet_queue_join(bigint, jsonb, int, text, int)', 'execute')
  and has_function_privilege('authenticated', 'public.gauntlet_queue_poll(bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.gauntlet_queue_cancel(bigint)', 'execute'));
select pg_temp.ck('A 调度器视图只给 service_role',
  not has_function_privilege('authenticated', 'public.gauntlet_service_state(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_service_state(bigint)', 'execute')
  and has_function_privilege('service_role', 'public.gauntlet_service_state(bigint)', 'execute'));
select pg_temp.ck('A 内部函数客户端调不了（推进 / 兜底挑机器人 / 排除表 / 结果视图）',
  not has_function_privilege('authenticated', 'public.gauntlet_queue_advance(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_gauntlet_pick_bot(int, int, int, int, text[])', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_gauntlet_opp_ex(uuid, bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.gauntlet_queue_view(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.gauntlet_opponents(bigint, uuid)', 'execute'));
select pg_temp.ck('A 两张新表客户端直连读不到; service_role 读写得到',
  not has_table_privilege('authenticated', 'public.gauntlet_queue', 'select')
  and not has_table_privilege('anon', 'public.gauntlet_queue', 'select')
  and not has_table_privilege('authenticated', 'public.bot_accounts', 'select')
  and has_table_privilege('service_role', 'public.bot_accounts', 'insert')
  and has_table_privilege('service_role', 'public.gauntlet_queue', 'select'));

-- ── G 闸（与 referee_gauntlet_start 同一组 reason）──
select pg_temp.keep('g1', to_jsonb(pg_temp.both(null, pg_temp.fake_week(), pg_temp.snap('z1'), 0, '9.9.9', 1)));
select pg_temp.ck('G1 未登录 ⇒ not_signed_in（两边同）', pg_temp.r('g1') #>> '{}' = 'not_signed_in|not_signed_in', pg_temp.r('g1') #>> '{}');
select pg_temp.keep('g2', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), pg_temp.snap('z1'), 0, '0.0.1', 1)));
select pg_temp.ck('G2 没登记的版本 ⇒ update_required（两边同）', pg_temp.r('g2') #>> '{}' = 'update_required|update_required', pg_temp.r('g2') #>> '{}');
select pg_temp.keep('g3', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), pg_temp.snap('z1'), 0, '9.9.9', 2)));
select pg_temp.ck('G3 规则版本不对 ⇒ update_required（两边同）', pg_temp.r('g3') #>> '{}' = 'update_required|update_required', pg_temp.r('g3') #>> '{}');
select pg_temp.keep('g4', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week() - 604800, pg_temp.snap('z1'), 0, '9.9.9', 1)));
select pg_temp.ck('G4 不是本周 ⇒ wrong_week（两边同）', pg_temp.r('g4') #>> '{}' = 'wrong_week|wrong_week', pg_temp.r('g4') #>> '{}');
select pg_temp.keep('g5', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), null, 0, '9.9.9', 1)));
select pg_temp.ck('G5 阵容为空 ⇒ bad_snapshot（两边同）', pg_temp.r('g5') #>> '{}' = 'bad_snapshot|bad_snapshot', pg_temp.r('g5') #>> '{}');
select pg_temp.keep('g5b', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(),
  pg_temp.snap('z1') || '{"leaders":["ninja","ninja","pirate"]}'::jsonb, 0, '9.9.9', 1)));
select pg_temp.ck('G5 三统领有重复 ⇒ bad_snapshot（两边同）', pg_temp.r('g5b') #>> '{}' = 'bad_snapshot|bad_snapshot', pg_temp.r('g5b') #>> '{}');
select pg_temp.set_fake(5, 12);
select pg_temp.keep('g6a', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), pg_temp.snap('z1'), 0, '9.9.9', 1)));
select pg_temp.set_fake(7, 17, 31);
select pg_temp.keep('g6b', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), pg_temp.snap('z1'), 0, '9.9.9', 1)));
select pg_temp.set_fake(7, 17, 29);
select pg_temp.keep('g6c', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), null, 0, '9.9.9', 1)));
select pg_temp.set_fake(6, 12);
select pg_temp.ck('G6 假周五 12:00 ⇒ closed（两边同）', pg_temp.r('g6a') #>> '{}' = 'closed|closed', pg_temp.r('g6a') #>> '{}');
select pg_temp.ck('G6 假周日 17:31 ⇒ closed（两边同）', pg_temp.r('g6b') #>> '{}' = 'closed|closed', pg_temp.r('g6b') #>> '{}');
select pg_temp.ck('G6 假周日 17:29 ⇒ 过了时间闸（空阵容 ⇒ bad_snapshot，两边同）', pg_temp.r('g6c') #>> '{}' = 'bad_snapshot|bad_snapshot', pg_temp.r('g6c') #>> '{}');
select pg_temp.rec('z1', 4, 0);
select pg_temp.keep('g7', to_jsonb(pg_temp.both(pg_temp.u('z1'), pg_temp.fake_week(), pg_temp.snap('z1'), 4, '9.9.9', 1)));
select pg_temp.ck('G7 已 4 胜 ⇒ finished（两边同）', pg_temp.r('g7') #>> '{}' = 'finished|finished', pg_temp.r('g7') #>> '{}');
select pg_temp.keep('g7b', pg_temp.j('z1', 4));
select pg_temp.ck('G7 finished 带账本 gw / gl', (pg_temp.r('g7b')->>'gw')::int = 4 and (pg_temp.r('g7b')->>'gl')::int = 0, pg_temp.r('g7b')::text);
select pg_temp.rec('z2', 1, 0);
select pg_temp.keep('g8', to_jsonb(pg_temp.both(pg_temp.u('z2'), pg_temp.fake_week(), pg_temp.snap('z2'), 0, '9.9.9', 1)));
select pg_temp.ck('G8 场次对不上账本 ⇒ stale（两边同）', pg_temp.r('g8') #>> '{}' = 'stale|stale', pg_temp.r('g8') #>> '{}');
update public.referee_config set gauntlet_on = false where id = 1;
select pg_temp.keep('g9', to_jsonb(pg_temp.both(pg_temp.u('z2'), pg_temp.fake_week(), pg_temp.snap('z2'), 1, '9.9.9', 1)));
update public.referee_config set gauntlet_on = true where id = 1;
select pg_temp.ck('G9 周六开关关着 ⇒ off（两边同）', pg_temp.r('g9') #>> '{}' = 'off|off', pg_temp.r('g9') #>> '{}');
select pg_temp.ck('G 分母: G1~G9 没有一条建出排队行', not exists (select 1 from public.gauntlet_queue q
  where q.account_id in (pg_temp.u('z1'), pg_temp.u('z2'))));
-- 不带版本参数（客户端只给 3 个参数）⇒ 读请求头 X-Client-Version
select set_config('request.headers', '{"x-client-version":"9.9.9"}', true);
select pg_temp.as_user(pg_temp.u('z3'));
select pg_temp.keep('g10', public.gauntlet_queue_join(pg_temp.fake_week(), pg_temp.snap('z3'), 0));
select set_config('request.headers', '{"x-client-version":"0.0.1"}', true);
select pg_temp.as_user(pg_temp.u('z4'));
select pg_temp.keep('g10b', public.gauntlet_queue_join(pg_temp.fake_week(), pg_temp.snap('z4'), 0));
select set_config('request.headers', '', true);
select pg_temp.ck('G10 只给 3 个参数 ⇒ 按请求头 9.9.9 进队列（版本 / 规则版本记对）',
  pg_temp.r('g10')->>'status' = 'waiting' and (pg_temp.qrow('z3')).client_version = '9.9.9' and (pg_temp.qrow('z3')).rules_ver = 1,
  pg_temp.r('g10')::text);
select pg_temp.ck('G10 请求头是没登记的版本 ⇒ update_required', pg_temp.r('g10b')->>'reason' = 'update_required', pg_temp.r('g10b')::text);
select pg_temp.keep('g10c', pg_temp.c('z3'));

-- ── Q 配对 ──
create temp table _n as select pg_temp.njobs() as n0;
select pg_temp.keep('q1', pg_temp.j('h1'));
select pg_temp.ck('Q1 h1 进队列 ⇒ waiting（0-0，等了 0 秒）', pg_temp.r('q1')->>'status' = 'waiting'
  and (pg_temp.r('q1')->>'gw')::int = 0 and (pg_temp.r('q1')->>'gl')::int = 0 and (pg_temp.r('q1')->>'waited_sec')::int = 0, pg_temp.r('q1')::text);
select pg_temp.keep('q2', pg_temp.j('h2'));
select pg_temp.ck('Q2 h2 同格子进来 ⇒ 当场配上（paired / side b / 对手卡是 h1）',
  pg_temp.r('q2')->>'status' = 'paired' and pg_temp.r('q2')->>'side' = 'b'
  and pg_temp.r('q2')->'opp'->'profile'->>'name' = 'h1' and jsonb_array_length(pg_temp.r('q2')->'opp'->'leaders') = 3, pg_temp.r('q2')::text);
select pg_temp.ck('Q2 只建了 1 条任务（分母: 之前的条数）', pg_temp.njobs() = (select n0 from _n) + 1,
  format('之前 %s / 之后 %s', (select n0 from _n), pg_temp.njobs()));
create temp table _j1 as select * from public.referee_jobs where job_id = (pg_temp.r('q2')->>'job_id')::bigint;
select pg_temp.ck('Q2 任务: A = 先来的 h1 / B = h2 / meta.pair / 两边快照各是自己锁定的那份 / 版本 9.9.9 / pending',
  (select a_account = pg_temp.u('h1') and b_account = pg_temp.u('h2') and meta->>'pair' = 'true' and kind = 'gauntlet'
          and a_snapshot->'profile'->>'name' = 'h1' and b_snapshot->'profile'->>'name' = 'h2'
          and client_version = '9.9.9' and status = 'pending' and match_key like 'gpair:%' from _j1),
  coalesce((select row_to_json(x)::text from (select a_account, b_account, meta, client_version, status, match_key from _j1) x), '无'));
select pg_temp.ck('Q2 两条排队行都 paired、同一 job_id、side 一 a 一 b',
  (pg_temp.qrow('h1')).status = 'paired' and (pg_temp.qrow('h2')).status = 'paired'
  and (pg_temp.qrow('h1')).job_id = (select job_id from _j1) and (pg_temp.qrow('h2')).job_id = (select job_id from _j1)
  and (pg_temp.qrow('h1')).side = 'a' and (pg_temp.qrow('h2')).side = 'b');
select pg_temp.keep('q3', pg_temp.p('h1'));
select pg_temp.ck('Q3 h1 poll ⇒ paired / side a / 对手卡是 h2 / 同一局',
  pg_temp.r('q3')->>'status' = 'paired' and pg_temp.r('q3')->>'side' = 'a' and pg_temp.r('q3')->'opp'->'profile'->>'name' = 'h2'
  and (pg_temp.r('q3')->>'job_id')::bigint = (select job_id from _j1) and pg_temp.r('q3')->>'job_status' = 'pending', pg_temp.r('q3')::text);
select pg_temp.keep('q4', pg_temp.j('h2'));
select pg_temp.keep('q4b', pg_temp.j('h1'));
select pg_temp.ck('Q4 配上之后再 join（双击 / 重进）⇒ 回同一局（in_flight），不多建',
  (pg_temp.r('q4')->>'job_id')::bigint = (select job_id from _j1) and pg_temp.r('q4')->>'in_flight' = 'true'
  and pg_temp.r('q4')->>'side' = 'b' and (pg_temp.r('q4b')->>'job_id')::bigint = (select job_id from _j1)
  and pg_temp.r('q4b')->>'side' = 'a' and pg_temp.njobs() = (select n0 from _n) + 1, pg_temp.r('q4')::text);
select pg_temp.ck('Q5 并发保护: 格子锁（事务级 advisory，键 = 周 + 0-0 格子）真的拿了',
  exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.classid::text = '20261027' and l.objsubid = 2
           and l.objid::text::bigint = (hashtext(format('gauntlet_cell:%s:0:0', pg_temp.fake_week()))::bigint + 4294967296) % 4294967296),
  (select string_agg(format('%s/%s/%s', classid, objid, objsubid), ',') from pg_locks where locktype = 'advisory'));
-- 不同格子
select pg_temp.rec('h3', 1, 0);
select pg_temp.rec('h4', 0, 1);
select pg_temp.keep('q6a', pg_temp.j('h3', 1));
select pg_temp.keep('q6b', pg_temp.j('h4', 1));
select pg_temp.ck('Q6 不同格子（1-0 / 0-1）⇒ 都在等、不配',
  pg_temp.r('q6a')->>'status' = 'waiting' and pg_temp.r('q6b')->>'status' = 'waiting'
  and (pg_temp.r('q6a')->>'gw')::int = 1 and (pg_temp.r('q6b')->>'gl')::int = 1 and pg_temp.njobs() = (select n0 from _n) + 1,
  pg_temp.r('q6a')::text || ' / ' || pg_temp.r('q6b')::text);
-- 心跳过期
select pg_temp.keep('q7a', pg_temp.j('h5'));
update public.gauntlet_queue set last_seen = now() - interval '20 seconds' where id = (pg_temp.qrow('h5')).id;
select pg_temp.keep('q7b', pg_temp.j('h6'));
select pg_temp.ck('Q7 h5 心跳断了 20 秒 ⇒ h6 进同一格子不配它（h6 在等）',
  pg_temp.r('q7a')->>'status' = 'waiting' and pg_temp.r('q7b')->>'status' = 'waiting' and pg_temp.njobs() = (select n0 from _n) + 1,
  pg_temp.r('q7b')::text);
select pg_temp.ck('Q7 h5 那条在扫格子时被置 expired', (pg_temp.qrow('h5')).status = 'expired', (pg_temp.qrow('h5')).status);
select pg_temp.keep('q7c', pg_temp.p('h5'));
select pg_temp.ck('Q7 h5 回来 poll ⇒ expired（客户端重新排）', pg_temp.r('q7c')->>'status' = 'expired', pg_temp.r('q7c')::text);
-- 交手过（配对局）+ 对照
select pg_temp.rec('h7', 1, 1);
select pg_temp.rec('h8', 1, 1);
select pg_temp.rec('h9', 1, 1);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta, status)
  values ('gauntlet', 'chk20261027:met:' || pg_temp.u('h7'), pg_temp.fake_week(), '9.9.9', 777, pg_temp.u('h7'), pg_temp.u('h8'),
          pg_temp.snap('h7'), pg_temp.snap('h8'), jsonb_build_object('pair', true, 'opp', pg_temp.u('h8')::text), 'done');
update _n set n0 = pg_temp.njobs();
select pg_temp.keep('q8a', pg_temp.j('h7', 2));
select pg_temp.keep('q8b', pg_temp.j('h8', 2));
select pg_temp.ck('Q8 h7 / h8 本周交手过（h8 当 B）⇒ 同格子也不配',
  pg_temp.r('q8a')->>'status' = 'waiting' and pg_temp.r('q8b')->>'status' = 'waiting' and pg_temp.njobs() = (select n0 from _n),
  pg_temp.r('q8b')::text);
select pg_temp.keep('q8c', pg_temp.j('h9', 2));
select pg_temp.ck('Q8 对照: h9 进同一格子 ⇒ 配先来的 h7（h8 照样在等）',
  pg_temp.r('q8c')->>'status' = 'paired' and pg_temp.r('q8c')->'opp'->'profile'->>'name' = 'h7'
  and (pg_temp.qrow('h8')).status = 'waiting' and pg_temp.njobs() = (select n0 from _n) + 1, pg_temp.r('q8c')::text);
-- 交手过（旧路：h10 打过 h11 的快照）
select pg_temp.rec('h10', 2, 0);
select pg_temp.rec('h11', 2, 0);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta, status)
  values ('gauntlet', 'chk20261027:old:' || pg_temp.u('h10'), pg_temp.fake_week(), '9.9.9', 778, pg_temp.u('h10'), pg_temp.u('h11'),
          pg_temp.snap('h10'), pg_temp.snap('h11'), jsonb_build_object('opp', pg_temp.u('h11')::text, 'pick', 'fresh'), 'done');
update _n set n0 = pg_temp.njobs();
select pg_temp.keep('q8d', pg_temp.j('h11', 2));
select pg_temp.keep('q8e', pg_temp.j('h10', 2));
select pg_temp.ck('Q8 旧路打过对方快照的也算交手过 ⇒ 不配',
  pg_temp.r('q8d')->>'status' = 'waiting' and pg_temp.r('q8e')->>'status' = 'waiting' and pg_temp.njobs() = (select n0 from _n),
  pg_temp.r('q8e')::text);
-- 版本不同
select pg_temp.rec('h12', 2, 1);
select pg_temp.rec('h13', 2, 1);
select pg_temp.keep('q9a', pg_temp.j('h12', 3, '9.9.8'));
select pg_temp.keep('q9b', pg_temp.j('h13', 3, '9.9.9'));
select pg_temp.ck('Q9 客户端版本不同（9.9.8 / 9.9.9）⇒ 不配',
  pg_temp.r('q9a')->>'status' = 'waiting' and pg_temp.r('q9b')->>'status' = 'waiting' and pg_temp.njobs() = (select n0 from _n),
  pg_temp.r('q9b')::text);
-- 取消
select pg_temp.keep('q10a', pg_temp.c('h6'));
select pg_temp.keep('q10b', pg_temp.p('h6'));
select pg_temp.keep('q10c', pg_temp.c('h6'));
select pg_temp.keep('q10d', pg_temp.c('h1'));
select pg_temp.ck('Q10 waiting 取消 ⇒ cancelled（行也是 cancelled）', pg_temp.r('q10a')->>'status' = 'cancelled'
  and (pg_temp.qrow('h6')).status = 'cancelled', pg_temp.r('q10a')::text);
select pg_temp.ck('Q10 取消后 poll ⇒ none；再取消一次 ⇒ ok / none',
  pg_temp.r('q10b')->>'status' = 'none' and pg_temp.r('q10c')->>'ok' = 'true' and pg_temp.r('q10c')->>'status' = 'none',
  pg_temp.r('q10b')::text || ' / ' || pg_temp.r('q10c')::text);
select pg_temp.ck('Q10 已配上的取消 ⇒ {ok:false, reason:paired, job_id, side}',
  pg_temp.r('q10d')->>'ok' = 'false' and pg_temp.r('q10d')->>'reason' = 'paired'
  and (pg_temp.r('q10d')->>'job_id')::bigint = (select job_id from _j1) and pg_temp.r('q10d')->>'side' = 'a', pg_temp.r('q10d')::text);
-- 等待秒数
update public.gauntlet_queue set joined_at = now() - interval '30 seconds' where id = (pg_temp.qrow('h3')).id;
select pg_temp.keep('q11', pg_temp.p('h3'));
select pg_temp.ck('Q11 进队 30 秒 ⇒ poll 回 waited_sec = 30', pg_temp.r('q11')->>'status' = 'waiting'
  and (pg_temp.r('q11')->>'waited_sec')::int = 30, pg_temp.r('q11')::text);
-- 90 秒兜底
select pg_temp.rec('h14', 0, 2);
insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
  values (1, 2, 0, 2, 99, pg_temp.snap('池子二'), '9.9.9'), (1, 4, 2, 2, 99, pg_temp.snap('池子四'), '9.9.9')
  on conflict (rules_ver, battles, gw, gl, variant) do nothing;
update _n set n0 = pg_temp.njobs();
select pg_temp.keep('q12a', pg_temp.j('h14', 2));
update public.gauntlet_queue set joined_at = now() - interval '89 seconds' where id = (pg_temp.qrow('h14')).id;
select pg_temp.keep('q12b', pg_temp.p('h14'));
select pg_temp.ck('Q12 真人等 89 秒 ⇒ 还在等（不兜底）', pg_temp.r('q12b')->>'status' = 'waiting' and pg_temp.njobs() = (select n0 from _n),
  pg_temp.r('q12b')::text);
update public.gauntlet_queue set joined_at = now() - interval '91 seconds' where id = (pg_temp.qrow('h14')).id;
select pg_temp.keep('q12c', pg_temp.p('h14'));
create temp table _jf as select * from public.referee_jobs where job_id = (pg_temp.r('q12c')->>'job_id')::bigint;
select pg_temp.ck('Q12 等满 91 秒 ⇒ 兜底配上（paired / side a / 有对手卡；回包不带 pick / fallback 字样）',
  pg_temp.r('q12c')->>'status' = 'paired' and pg_temp.r('q12c')->>'side' = 'a' and pg_temp.r('q12c')->'opp'->'profile' is not null
  and not (pg_temp.r('q12c') ? 'pick') and not (pg_temp.r('q12c') ? 'fallback') and pg_temp.njobs() = (select n0 from _n) + 1,
  pg_temp.r('q12c')::text);
select pg_temp.ck('Q12 兜底任务 = 机器人池快照、b_account 空、不是配对局（只记真人一边）',
  (select a_account = pg_temp.u('h14') and b_account is null and not (meta ? 'pair') and meta->>'fallback' = 'true'
          and meta->>'pick' = 'bot' and meta->>'opp' like 'bot:1:2:0:2:%' and status = 'pending' from _jf),
  coalesce((select meta::text from _jf), '无'));
select pg_temp.rec('k3', 2, 2);
update _n set n0 = pg_temp.njobs();
select pg_temp.keep('q12d', pg_temp.j('k3', 4));
update public.gauntlet_queue set joined_at = now() - interval '120 seconds' where id = (pg_temp.qrow('k3')).id;
select pg_temp.keep('q12e', pg_temp.p('k3'));
select pg_temp.ck('Q12 陪练号等 120 秒也不兜底（池子里这一格有货）', pg_temp.r('q12e')->>'status' = 'waiting'
  and pg_temp.njobs() = (select n0 from _n), pg_temp.r('q12e')::text);
select pg_temp.rec('h15', 2, 2);
select pg_temp.keep('q12f', pg_temp.j('h15', 4));
select pg_temp.ck('Q12 对照: 真人 h15 进同一格子 ⇒ 配上陪练号 k3（先来的 k3 当 A）',
  pg_temp.r('q12f')->>'status' = 'paired' and pg_temp.r('q12f')->>'side' = 'b' and pg_temp.r('q12f')->'opp'->'profile'->>'name' = 'k3'
  and (select a_account = pg_temp.u('k3') and b_account = pg_temp.u('h15') and meta->>'pair' = 'true'
         from public.referee_jobs where job_id = (pg_temp.r('q12f')->>'job_id')::bigint), pg_temp.r('q12f')::text);
-- 陪练号对陪练号
select pg_temp.rec('k1', 1, 2);
select pg_temp.rec('k2', 1, 2);
select pg_temp.keep('q13a', pg_temp.j('k1', 3));
select pg_temp.keep('q13b', pg_temp.j('k2', 3));
select pg_temp.ck('Q13 陪练号对陪练号同样配（k1 = A / k2 = B）', pg_temp.r('q13a')->>'status' = 'waiting'
  and pg_temp.r('q13b')->>'status' = 'paired'
  and (select a_account = pg_temp.u('k1') and b_account = pg_temp.u('k2') and meta->>'pair' = 'true'
         from public.referee_jobs where job_id = (pg_temp.r('q13b')->>'job_id')::bigint), pg_temp.r('q13b')::text);
-- 同一账号同一周两条 waiting
do $$
declare ok boolean := false;
begin
  begin
    insert into public.gauntlet_queue (season_week, account_id, gw, gl, rules_ver, client_version, snapshot)
      values (pg_temp.fake_week(), pg_temp.u('h4'), 0, 1, 1, '9.9.9', pg_temp.snap('h4'));
  exception when unique_violation then
    ok := true;
  end;
  perform pg_temp.ck('Q14 同一账号同一周第二条 waiting ⇒ 唯一索引挡住', ok);
end $$;

-- ── S 调度器视图 ──
select pg_temp.rec('k4', 4, 1);
select pg_temp.rec('k5', 3, 0);
select pg_temp.keep('s0', pg_temp.j('k5', 3));
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, client_version)
  select pg_temp.u('k1'), pg_temp.fake_week(), 16, pg_temp.snap('k1'), 11, '9.9.9'
  union all select pg_temp.u('k1'), pg_temp.fake_week(), 3, pg_temp.snap('k1'), 3, '9.9.9'
  union all select pg_temp.u('k2'), pg_temp.fake_week(), 16, pg_temp.snap('k2'), 10, '9.9.9';
update public.gauntlet_queue set last_seen = now() - interval '20 seconds' where id = (pg_temp.qrow('h13')).id;
-- k4 本周已经打完过一局（结果写回）⇒ last_played_at 有值
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, meta, status, done_at)
  values ('gauntlet', 'chk20261027:k4done:' || pg_temp.u('k4'), pg_temp.fake_week(), '9.9.9', 780, pg_temp.u('k4'),
          pg_temp.snap('k4'), pg_temp.snap('池子'), '{}'::jsonb, 'done', now());
select pg_temp.keep('s', public.gauntlet_service_state(pg_temp.fake_week()));
create temp table _sp as select e from jsonb_array_elements(pg_temp.r('s')->'playing') e
  where (e->>'account_id')::uuid in (select id from _u);
create temp table _sw as select e from jsonb_array_elements(pg_temp.r('s')->'waiting') e
  where (e->>'account_id')::uuid in (select id from _u);
create temp table _sb as select e from jsonb_array_elements(pg_temp.r('s')->'bots') e
  where (e->>'account_id')::uuid in (select id from _u);
create or replace function pg_temp.sb(p_k text) returns jsonb language sql as $$
  select e from _sb where (e->>'account_id')::uuid = pg_temp.u(p_k)
$$;
select pg_temp.ck('S1 排队: 真人 h4（0-1，is_bot false）/ 陪练号 k5（3-0，is_bot true）都在；心跳断了的 h13、已配上的 h1、已取消的 h6 不在',
  exists (select 1 from _sw where (e->>'account_id')::uuid = pg_temp.u('h4') and (e->>'gw')::int = 0 and (e->>'gl')::int = 1
            and (e->>'seen_sec')::int = 0 and e ? 'waited_sec' and e->>'is_bot' = 'false')
  and exists (select 1 from _sw where (e->>'account_id')::uuid = pg_temp.u('k5') and (e->>'gw')::int = 3 and (e->>'gl')::int = 0
            and e->>'is_bot' = 'true')
  and not exists (select 1 from _sw where (e->>'account_id')::uuid in (pg_temp.u('h13'), pg_temp.u('h1'), pg_temp.u('h6'))),
  (select string_agg(e::text, ' ') from _sw));
select pg_temp.ck('S1 opponents 两个方向: h8 的有 h7（配对局里当 B）/ h11 的有 h10（h10 打过 h11 的快照）/ h4 的是空的',
  exists (select 1 from _sw where (e->>'account_id')::uuid = pg_temp.u('h8') and e->'opponents' ? pg_temp.u('h7')::text)
  and exists (select 1 from _sw where (e->>'account_id')::uuid = pg_temp.u('h11') and e->'opponents' ? pg_temp.u('h10')::text)
  and exists (select 1 from _sw where (e->>'account_id')::uuid = pg_temp.u('h4') and jsonb_array_length(e->'opponents') = 0),
  (select string_agg(e::text, ' ') from _sw where (e->>'account_id')::uuid in (pg_temp.u('h8'), pg_temp.u('h11'))));
select pg_temp.ck('S1 playing: k3（a，陪练号）/ h15（b，真人）/ k1 / k2 / h1 / h2 都在，同一局的 job_id 相同',
  (select count(*) from _sp where (e->>'account_id')::uuid in (pg_temp.u('k1'), pg_temp.u('k2'), pg_temp.u('k3'), pg_temp.u('h15'),
                                                                 pg_temp.u('h1'), pg_temp.u('h2'))) = 6
  and exists (select 1 from _sp where (e->>'account_id')::uuid = pg_temp.u('k3') and e->>'side' = 'a' and e->>'is_bot' = 'true')
  and exists (select 1 from _sp where (e->>'account_id')::uuid = pg_temp.u('h15') and e->>'side' = 'b' and e->>'is_bot' = 'false'
                and (e->>'job_id')::bigint = (pg_temp.r('q12f')->>'job_id')::bigint),
  (select string_agg(e::text, ' ') from _sp));
select pg_temp.ck('S1 h13 心跳断了 ⇒ 读视图时被置 expired', (pg_temp.qrow('h13')).status = 'expired');
select pg_temp.ck('S2 陪练号 5 个都在（分母）', (select count(*) from _sb) = 5, (select count(*) from _sb)::text);
select pg_temp.ck('S2 k1: 1-2 / 在算 / 忙 / 晋级（battles 最大那份 11 胜）/ 没打完',
  (pg_temp.sb('k1')->>'gw')::int = 1 and (pg_temp.sb('k1')->>'gl')::int = 2 and pg_temp.sb('k1')->>'in_job' = 'true'
  and pg_temp.sb('k1')->>'busy' = 'true' and pg_temp.sb('k1')->>'promoted' = 'true' and pg_temp.sb('k1')->>'finished' = 'false'
  and pg_temp.sb('k1')->>'last_played_at' is null and jsonb_array_length(pg_temp.sb('k1')->'opponents') = 1
  and pg_temp.sb('k1')->'opponents' ? pg_temp.u('k2')::text, pg_temp.sb('k1')::text);
select pg_temp.ck('S2 k2: 10 胜 ⇒ 没晋级', pg_temp.sb('k2')->>'promoted' = 'false', pg_temp.sb('k2')::text);
select pg_temp.ck('S2 k4: 4-1 ⇒ 打完 / 不忙 / last_played_at = 那一局写回的 epoch 秒', pg_temp.sb('k4')->>'finished' = 'true'
  and pg_temp.sb('k4')->>'busy' = 'false' and pg_temp.sb('k4')->>'in_job' = 'false'
  and (pg_temp.sb('k4')->>'last_played_at')::bigint = floor(extract(epoch from now()))::bigint, pg_temp.sb('k4')::text);
select pg_temp.ck('S2 k5: 在排队 ⇒ 忙（waiting = true / in_job = false）', pg_temp.sb('k5')->>'busy' = 'true'
  and pg_temp.sb('k5')->>'waiting' = 'true' and pg_temp.sb('k5')->>'in_job' = 'false', pg_temp.sb('k5')::text);
select pg_temp.ck('S2 k3: 与 h15 那一局在算 ⇒ in_job', pg_temp.sb('k3')->>'in_job' = 'true', pg_temp.sb('k3')::text);
select pg_temp.ck('S3 收盘 = 周日 17:30、now = app_now()、两个常量',
  (pg_temp.r('s')->>'close_ts')::bigint = pg_temp.fake_week() + 6 * 86400 + 17 * 3600 + 1800
  and (pg_temp.r('s')->>'now_ts')::bigint = floor(extract(epoch from public.app_now()))::bigint
  and (pg_temp.r('s')->>'ttl_sec')::int = 15 and (pg_temp.r('s')->>'fallback_sec')::int = 90 and pg_temp.r('s')->>'gauntlet_on' = 'true',
  pg_temp.r('s')::text);

-- ── P 旧入口 ──
select pg_temp.as_user(pg_temp.u('h15'));
select pg_temp.keep('p1', public.referee_gauntlet_start(pg_temp.fake_week(), pg_temp.snap('h15'), 4, '9.9.9', 1));
select pg_temp.ck('P1 旧接口: 配对局里我是 B ⇒ 回那一场（in_flight），对手卡是 A（k3）',
  pg_temp.r('p1')->>'in_flight' = 'true' and (pg_temp.r('p1')->>'job_id')::bigint = (pg_temp.r('q12f')->>'job_id')::bigint
  and pg_temp.r('p1')->'opp'->'profile'->>'name' = 'k3', pg_temp.r('p1')::text);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta, status)
  values ('gauntlet', 'chk20261027:snapowner:' || pg_temp.u('p2'), pg_temp.fake_week(), '9.9.9', 779, pg_temp.u('p2'), pg_temp.u('p3'),
          pg_temp.snap('p2'), pg_temp.snap('p3'), jsonb_build_object('opp', pg_temp.u('p3')::text, 'pick', 'fresh'), 'pending');
-- 「p3 有没有在算的局」要在调旧接口之前量：旧接口挑得到对手时会当场给 p3 建一局（内测服机器人池有货）
select pg_temp.keep('p2pre', to_jsonb(public.gauntlet_in_job(pg_temp.fake_week(), pg_temp.u('p3'))));
select pg_temp.as_user(pg_temp.u('p3'));
select pg_temp.keep('p2', public.referee_gauntlet_start(pg_temp.fake_week(), pg_temp.snap('p3'), 0, '9.9.9', 1));
select pg_temp.ck('P2 旧路里只是「被打的快照主人」⇒ 不算在算（不回别人那一场）',
  pg_temp.r('p2')->>'in_flight' is null and (pg_temp.r('p2')->>'job_id')::bigint is distinct from
    (select job_id from public.referee_jobs where match_key = 'chk20261027:snapowner:' || pg_temp.u('p2'))
  and pg_temp.r('p2pre') = 'false'::jsonb, pg_temp.r('p2')::text);
insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
  values (pg_temp.u('h1'), pg_temp.fake_week(), 2, 2, pg_temp.snap('h1'), '9.9.9', 99);
select pg_temp.keep('p3', public.referee_gauntlet_pick(pg_temp.u('h2'), pg_temp.fake_week(), 2, 2, 99, 0));
select pg_temp.keep('p3b', public.referee_gauntlet_pick(pg_temp.u('p1'), pg_temp.fake_week(), 2, 2, 99, 0));
select pg_temp.ck('P3 挑对手排除表看配对局里我当 B 的那一侧: h2 挑不到 h1',
  pg_temp.r('p3') is null or pg_temp.r('p3')->>'opp' is distinct from pg_temp.u('h1')::text, coalesce(pg_temp.r('p3')::text, 'null'));
select pg_temp.ck('P3 对照: 没碰过 h1 的 p1 同一格子挑得到 h1', pg_temp.r('p3b')->>'opp' = pg_temp.u('h1')::text,
  coalesce(pg_temp.r('p3b')::text, 'null'));

-- ── W 写回 ──
select pg_temp.keep('w1', pg_temp.done((select job_id from _j1), 'b', jsonb_build_object('coins', 5, 'coins_b', 7,
  'chest', jsonb_build_object('value', 11), 'chest_b', jsonb_build_object('value', 22),
  'incense', jsonb_build_object('marks', 1), 'incense_b', jsonb_build_object('marks', 2))));
select pg_temp.ck('W1 写回 ok（h1 = A 输 / h2 = B 赢）', pg_temp.r('w1')->>'ok' = 'true', pg_temp.r('w1')::text);
select pg_temp.ck('W1 两边战绩互反: h1 0-1 / h2 1-0',
  public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('h1')) = array[0, 1]
  and public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('h2')) = array[1, 0],
  public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('h1'))::text || ' / ' || public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('h2'))::text);
select pg_temp.ck('W1 matches 只有一行: left = h1 / right = h2 / result 里 A 输、gw_b gl_b 是 B 的',
  (select count(*) = 1 and bool_and(left_account = pg_temp.u('h1') and right_account = pg_temp.u('h2') and phase = 'gauntlet'
          and result->>'won' = 'false' and (result->>'gw')::int = 0 and (result->>'gl')::int = 1
          and (result->>'gw_b')::int = 1 and (result->>'gl_b')::int = 0 and not (result ? 'coins'))
     from public.matches where match_id = (select match_id from _j1)),
  coalesce((select result::text from public.matches where match_id = (select match_id from _j1)), '无'));
select pg_temp.ck('W1 两边快照池: h1 挂 0-1、h2 挂 1-0（各自的阵容、rules_ver 1）',
  exists (select 1 from public.gauntlet_ghosts where account_id = pg_temp.u('h1') and season_week = pg_temp.fake_week()
            and gw = 0 and gl = 1 and snapshot->'profile'->>'name' = 'h1' and rules_ver = 1)
  and exists (select 1 from public.gauntlet_ghosts where account_id = pg_temp.u('h2') and season_week = pg_temp.fake_week()
            and gw = 1 and gl = 0 and snapshot->'profile'->>'name' = 'h2' and rules_ver = 1 and client_version = '9.9.9'));
select pg_temp.ck('W1 两条排队行 ⇒ done', (pg_temp.qrow('h1')).status = 'done' and (pg_temp.qrow('h2')).status = 'done');
select pg_temp.ck('W1 账本 coins = 5（A）/ coins_b = 7（B）',
  (select (result->'ledger'->>'coins')::int = 5 and (result->'ledger'->>'coins_b')::int = 7 and status = 'done'
     from public.referee_jobs where job_id = (select job_id from _j1)));
select pg_temp.keep('w1b', pg_temp.js('h2', (select job_id from _j1)));
select pg_temp.keep('w1a', pg_temp.js('h1', (select job_id from _j1)));
select pg_temp.keep('w1c', pg_temp.js('h3', (select job_id from _j1)));
select pg_temp.ck('W1 B 查 referee_job_status ⇒ B 的视角（赢 / 1-0 / coins 7 / chest·incense 取 _b / side b）',
  pg_temp.r('w1b')->>'ok' = 'true' and pg_temp.r('w1b')->>'status' = 'done' and pg_temp.r('w1b')->>'won' = 'true'
  and (pg_temp.r('w1b')->>'gw')::int = 1 and (pg_temp.r('w1b')->>'gl')::int = 0 and (pg_temp.r('w1b')->>'coins')::int = 7
  and (pg_temp.r('w1b')->'chest'->>'value')::int = 22 and (pg_temp.r('w1b')->'incense'->>'marks')::int = 2
  and pg_temp.r('w1b')->>'side' = 'b' and pg_temp.r('w1b')->>'match_id' = (select match_id::text from _j1), pg_temp.r('w1b')::text);
select pg_temp.ck('W1 A 查 ⇒ A 的视角（输 / 0-1 / coins 5 / chest·incense 是 A 的 / side a）',
  pg_temp.r('w1a')->>'won' = 'false' and (pg_temp.r('w1a')->>'gw')::int = 0 and (pg_temp.r('w1a')->>'gl')::int = 1
  and (pg_temp.r('w1a')->>'coins')::int = 5 and (pg_temp.r('w1a')->'chest'->>'value')::int = 11
  and (pg_temp.r('w1a')->'incense'->>'marks')::int = 1 and pg_temp.r('w1a')->>'side' = 'a', pg_temp.r('w1a')::text);
select pg_temp.ck('W1 第三个人查 ⇒ no_job', pg_temp.r('w1c')->>'reason' = 'no_job', pg_temp.r('w1c')::text);
select pg_temp.keep('w1d', pg_temp.p('h2'));
select pg_temp.ck('W1 算完后 B poll ⇒ paired + job_status done（客户端按 job_id 取结果）',
  pg_temp.r('w1d')->>'status' = 'paired' and pg_temp.r('w1d')->>'job_status' = 'done', pg_temp.r('w1d')::text);
-- 第 4 胜两边各自登记（本周若已分组 ⇒ 不登记；内测服假时钟可能已经分过组 ⇒ 本事务里先清掉，回滚即还原）
delete from public.finals_buckets where season_week = pg_temp.fake_week();
select pg_temp.rec('h16', 3, 1);
select pg_temp.rec('h17', 3, 1);
select pg_temp.keep('w2a', pg_temp.j('h16', 4));
select pg_temp.keep('w2b', pg_temp.j('h17', 4));
select pg_temp.keep('w2c', pg_temp.done((pg_temp.r('w2b')->>'job_id')::bigint, 'a'));
select pg_temp.rec('h18', 3, 2);
select pg_temp.rec('h19', 3, 2);
select pg_temp.keep('w2d', pg_temp.j('h18', 5));
select pg_temp.keep('w2e', pg_temp.j('h19', 5));
select pg_temp.keep('w2f', pg_temp.done((pg_temp.r('w2e')->>'job_id')::bigint, 'b'));
select pg_temp.ck('W2 分母: 两局都配上、都写回了', pg_temp.r('w2b')->>'status' = 'paired' and pg_temp.r('w2e')->>'status' = 'paired'
  and pg_temp.r('w2c')->>'ok' = 'true' and pg_temp.r('w2f')->>'ok' = 'true', pg_temp.r('w2b')::text || ' / ' || pg_temp.r('w2e')::text);
select pg_temp.ck('W2 A 拿到第 4 胜 ⇒ A（h16）登记决赛（4-1，名字取 A 的快照）/ B（h17）3-2 不登记',
  exists (select 1 from public.finals_pending where season_week = pg_temp.fake_week() and account_id = pg_temp.u('h16')
            and gw = 4 and gl = 1 and name = 'h16')
  and not exists (select 1 from public.finals_pending where account_id = pg_temp.u('h17'))
  and public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('h17')) = array[3, 2]);
select pg_temp.ck('W2 B 拿到第 4 胜 ⇒ B（h19）登记决赛（4-2，名字 / 快照取 B 的）/ A（h18）3-3 不登记',
  exists (select 1 from public.finals_pending where season_week = pg_temp.fake_week() and account_id = pg_temp.u('h19')
            and gw = 4 and gl = 2 and name = 'h19' and snapshot->'profile'->>'name' = 'h19')
  and not exists (select 1 from public.finals_pending where account_id = pg_temp.u('h18'))
  and public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('h18')) = array[3, 3]);
-- B 删号：配对局照样算完、只记 A；排队行 / 陪练号名单随删号走
update public.gauntlet_queue set status = 'cancelled' where account_id in (select id from _u) and status = 'waiting';
insert into public.bot_accounts (account_id) values (pg_temp.u('d2'));
select pg_temp.keep('w3a', pg_temp.j('d1'));
select pg_temp.keep('w3b', pg_temp.j('d2'));
select pg_temp.as_user(pg_temp.u('d2'));
select pg_temp.keep('w3c', public.account_delete_self());
select pg_temp.ck('W3 分母: d1 / d2 配上了、d2 删号成功', pg_temp.r('w3b')->>'status' = 'paired' and pg_temp.r('w3c')->>'ok' = 'true',
  pg_temp.r('w3b')::text || ' / ' || pg_temp.r('w3c')::text);
select pg_temp.ck('W3 删号级联: d2 的排队行 / 陪练号名单都没了',
  not exists (select 1 from public.gauntlet_queue where account_id = pg_temp.u('d2'))
  and not exists (select 1 from public.bot_accounts where account_id = pg_temp.u('d2')));
select pg_temp.ck('W3 那一局还在（pending）、b_account 断开', (select status = 'pending' and b_account is null
  from public.referee_jobs where job_id = (pg_temp.r('w3b')->>'job_id')::bigint));
select pg_temp.keep('w3d', pg_temp.done((pg_temp.r('w3b')->>'job_id')::bigint, 'a'));
select pg_temp.ck('W3 照样写回、只记 A（d1 1-0）、matches.right_account 空、d1 排队行 done',
  pg_temp.r('w3d')->>'ok' = 'true' and public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u('d1')) = array[1, 0]
  and (select right_account is null and left_account = pg_temp.u('d1') from public.matches
        where match_id = (select match_id from public.referee_jobs where job_id = (pg_temp.r('w3b')->>'job_id')::bigint))
  and (pg_temp.qrow('d1')).status = 'done', pg_temp.r('w3d')::text);
-- 算失败的配对局
select pg_temp.keep('w4a', pg_temp.j('e1'));
select pg_temp.keep('w4b', pg_temp.j('e2'));
update public.referee_jobs set status = 'failed', error = 'chk_fail', done_at = now()
 where job_id = (pg_temp.r('w4b')->>'job_id')::bigint;
select pg_temp.keep('w4c', pg_temp.p('e2'));
select pg_temp.ck('W4 分母: e1 / e2 配上了', pg_temp.r('w4b')->>'status' = 'paired', pg_temp.r('w4b')::text);
select pg_temp.ck('W4 那一局算失败 ⇒ B poll 回 none / job_failed / job_id，排队行作废',
  pg_temp.r('w4c')->>'status' = 'none' and pg_temp.r('w4c')->>'reason' = 'job_failed'
  and (pg_temp.r('w4c')->>'job_id')::bigint = (pg_temp.r('w4b')->>'job_id')::bigint and (pg_temp.qrow('e2')).status = 'cancelled',
  pg_temp.r('w4c')::text);
select pg_temp.keep('w4d', pg_temp.js('e2', (pg_temp.r('w4b')->>'job_id')::bigint));
select pg_temp.ck('W4 B 查那一局 ⇒ failed + error', pg_temp.r('w4d')->>'status' = 'failed' and pg_temp.r('w4d')->>'error' = 'chk_fail',
  pg_temp.r('w4d')::text);
select pg_temp.keep('w4e', pg_temp.j('e1'));
select pg_temp.keep('w4f', pg_temp.j('e2'));
select pg_temp.ck('W4 两边重新排: 都是新的 waiting（不再互配）、A 那条旧行也作废了',
  pg_temp.r('w4e')->>'status' = 'waiting' and pg_temp.r('w4f')->>'status' = 'waiting'
  and (select count(*) from public.gauntlet_queue where account_id = pg_temp.u('e1') and status = 'cancelled'
         and job_id = (pg_temp.r('w4b')->>'job_id')::bigint) = 1, pg_temp.r('w4e')::text || ' / ' || pg_temp.r('w4f')::text);

-- ── E 旧路任务逐字不变（改前函数体原样抄成 pg_temp 函数，对同一输入比）──
-- referee_complete 改前 = 20261026b 版（schema.sql 里 20261027 之前最后一份），由生成脚本逐字抄入：
create or replace function pg_temp.rc_old(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql as $old$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
begin
  select * into j from public.referee_jobs where job_id = p_job_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  if j.status = 'done' then
    return jsonb_build_object('ok', true, 'reason', 'already_done');
  end if;
  if j.status <> 'claimed' or j.claimed_by is distinct from p_worker then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or coalesce(p_result->>'ok', 'false') <> 'true'
     or p_result->>'match_id' is distinct from j.match_id::text
     or jsonb_typeof(p_result->'seed') <> 'number' or (p_result->>'seed')::numeric <> j.seed
     or p_result->>'client_version' is distinct from j.client_version
     or coalesce(p_result->>'winner', '') not in ('a', 'b')
     or jsonb_typeof(p_result->'steps') <> 'number' or (p_result->>'steps')::numeric <= 0
     or jsonb_typeof(p_result->'replay_b64') <> 'string'
     or octet_length(p_result->>'replay_b64') not between 1 and 65536      -- = matches_replay_size = 客户端 REPLAY_MAX_B64
     or (p_result->>'replay_b64') !~ '^[A-Za-z0-9+/]+={0,2}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_result');
  end if;
  won := p_result->>'winner' = 'a';
  sc := case when jsonb_typeof(p_result->'score_code') = 'number' then (p_result->>'score_code')::numeric::int else -1 end;
  -- ★2026-10-20 战斗内铸币（缺 / 不是数 / 越界 ⇒ 0；不是整数 ⇒ 向下取整）
  if jsonb_typeof(p_result->'coins') = 'number' and (p_result->>'coins')::numeric between 0 and 999 then
    v_coins := floor((p_result->>'coins')::numeric)::int;
  end if;
  -- ★2026-10-20d 右方（B）的战斗内铸币：周日决赛两边都是真人，各按自己那一侧发（同一道夹：缺 / 不是数 / 越界 ⇒ 0）
  if jsonb_typeof(p_result->'coins_b') = 'number' and (p_result->>'coins_b')::numeric between 0 and 999 then
    v_coins_b := floor((p_result->>'coins_b')::numeric)::int;
  end if;
  res := jsonb_build_object('won', won, 'steps', (p_result->>'steps')::numeric::int, 'surrendered', false,
                            'referee', true, 'score', sc);
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.a_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.a_account, case when won then 1 else 0 end, case when won then 0 else 1 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw, v_gl;
    res := res || jsonb_build_object('gw', v_gw, 'gl', v_gl);
    -- ★2026-10-20 规则版本：任务里记的那个（服务端挑对手时定的）> 裁判版本登记的 > 0（老任务、老口径）
    v_rv := coalesce(case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    -- 以打完这一场的新战绩标签挂进快照池（同 E-A4：下一场要找的是「跟我现在同样几胜几负」的人）
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.a_account, j.season_week, v_gw, v_gl, j.a_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
    -- ★2026-10-26 第 4 胜由服务端直接登记决赛报名（= phase2_config.GAUNTLET_WINS_IN；同 finals_enter 的 floor_wins）。
    --   闯关赛延到周日 17:30、分桶 18:00 只剩 30 分钟；原来只靠客户端结算后 / 开主菜单时报名，第 4 胜结算晚或玩家关了游戏
    --   ⇒ 18:00 后才报 ⇒ already_seated，错过决赛。客户端那两条留作兜底（finals_enter 同一张表、幂等 upsert）。
    --   已经有人报过（客户端先到）就不动它；桶已坐定就不再塞人（与 finals_enter 同一条）。
    if v_gw >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.a_account, coalesce(nullif(j.a_snapshot->'profile'->>'name', ''), '?'), j.a_snapshot, v_gw, v_gl)
        on conflict (season_week, account_id) do nothing;
    end if;
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  -- ★2026-10-20d 周日任务的账本多一个 coins_b（右方 B 的战斗内铸币；周六不记）
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins)
                  || case when j.kind = 'finals' then jsonb_build_object('coins_b', v_coins_b) else '{}'::jsonb end)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $old$;
-- referee_job_status 改前 = 20261023 版：
create or replace function pg_temp.js_old(p_job_id bigint)
returns jsonb language plpgsql stable as $old$
declare j record;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
    'won', j.result->'ledger'->'won', 'score', j.result->'ledger'->'score',
    'gw', j.result->'ledger'->'gw', 'gl', j.result->'ledger'->'gl',
    'coins', j.result->'ledger'->'coins',
    'error', case when j.status = 'failed' then j.error end)
    -- 2026-10-22b：这一局结束时我方宝箱龟的进度（财宝值 + 已开战利品）
    || case when j.status = 'done' and jsonb_typeof(j.result->'chest') = 'object'
            then jsonb_build_object('chest', j.result->'chest') else '{}'::jsonb end
    -- 2026-10-23：这一局结束时我方 093 香火石的刻痕 + 充能
    || case when j.status = 'done' and jsonb_typeof(j.result->'incense') = 'object'
            then jsonb_build_object('incense', j.result->'incense') else '{}'::jsonb end;
end $old$;

create or replace function pg_temp.eq_mk(p_acc uuid, p_b uuid, p_kind text, p_key text, p_meta jsonb, p_status text default 'claimed')
returns bigint language plpgsql as $$
declare jid bigint;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account,
      a_snapshot, b_snapshot, level, meta, status, claimed_by, claimed_at, attempts)
    values (p_kind, p_key, (select wk from _fw), '9.9.9', 4242, p_acc, p_b, pg_temp.snap('甲'), pg_temp.snap('乙'), 3,
            p_meta, p_status, case when p_status = 'claimed' then 'chk-worker' end,
            case when p_status = 'claimed' then now() end, 1)
    returning job_id into jid;
  return jid;
end $$;
-- 一局落账之后看得见的一切（账号 / 任务号 / 录像号 / 决赛场号归一掉）
create or replace function pg_temp.eq_state(p_acc uuid, p_job bigint) returns jsonb language sql as $$
  select jsonb_build_object(
    'rec', (select jsonb_build_object('gw', r.gw, 'gl', r.gl) from public.gauntlet_records r
             where r.season_week = j.season_week and r.account_id = p_acc),
    'gh', (select jsonb_agg(jsonb_build_object('gw', g.gw, 'gl', g.gl, 'snap', g.snapshot, 'cv', g.client_version, 'rv', g.rules_ver)
                            order by g.gw, g.gl)
             from public.gauntlet_ghosts g where g.season_week = j.season_week and g.account_id = p_acc),
    'fp', (select jsonb_build_object('name', f.name, 'gw', f.gw, 'gl', f.gl, 'snap', f.snapshot) from public.finals_pending f
            where f.season_week = j.season_week and f.account_id = p_acc),
    'b_rec', (select count(*) from public.gauntlet_records r where r.season_week = j.season_week and r.account_id = j.b_account),
    'b_gh', (select count(*) from public.gauntlet_ghosts g where g.season_week = j.season_week and g.account_id = j.b_account),
    'b_fp', (select count(*) from public.finals_pending f where f.season_week = j.season_week and f.account_id = j.b_account),
    'm', (select jsonb_build_object('n', count(*), 'phase', max(m.phase),
                   'left_is_a', bool_and(m.left_account is not distinct from j.a_account),
                   'right_is_b', bool_and(m.right_account is not distinct from j.b_account),
                   'right_null', bool_and(m.right_account is null), 'seed', max(m.seed),
                   'ls', (array_agg(m.left_snapshot))[1], 'rs', (array_agg(m.right_snapshot))[1],
                   'res', (array_agg(m.result - 'fm'))[1], 'cv', max(m.client_version), 'replay', max(m.replay))
            from public.matches m where m.match_id = j.match_id),
    'fr', (select jsonb_build_object('w', r.winner_side, 'll', r.loser_lanes, 'seed', r.seed_used) from public.finals_results r
            where j.kind = 'finals' and r.season_week = j.season_week and r.bucket_no = (j.meta->>'bucket')::int
              and r.round = (j.meta->>'round')::int and r.match_no = (j.meta->>'match')::int),
    'job', jsonb_build_object('status', j.status, 'error', j.error,
             'result', case when j.result is null then null
                            else (j.result - 'match_id') || jsonb_build_object('ledger', (j.result->'ledger') - 'fm') end))
  from public.referee_jobs j where j.job_id = p_job
$$;
create temp table _eq (sc text primary key, jx bigint, jy bigint, rx jsonb, ry jsonb);
grant all on _eq to public;
create or replace function pg_temp.eq_run(p_sc text, p_x text, p_y text, p_bx text, p_by text, p_kind text, p_meta_x jsonb,
    p_meta_y jsonb, p_winner text, p_extra jsonb) returns void language plpgsql as $$
declare jx bigint; jy bigint; rx jsonb; ry jsonb;
begin
  jx := pg_temp.eq_mk(pg_temp.u(p_x), pg_temp.u(p_bx), p_kind, 'chk20261027:eq:' || p_sc || ':x', p_meta_x);
  jy := pg_temp.eq_mk(pg_temp.u(p_y), pg_temp.u(p_by), p_kind, 'chk20261027:eq:' || p_sc || ':y', p_meta_y);
  rx := pg_temp.rc_old(jx, 'chk-worker', pg_temp.res(jx, p_winner, p_extra));
  ry := public.referee_complete(jy, 'chk-worker', pg_temp.res(jy, p_winner, p_extra));
  insert into _eq values (p_sc, jx, jy, rx, ry);
end $$;
-- 账本起点（两组账号一模一样）
insert into public.gauntlet_records (season_week, account_id, gw, gl)
  select (select wk from _fw), pg_temp.u(k), 3, 1 from unnest(array['x1', 'y1']) k
  union all select (select wk from _fw), pg_temp.u(k), 1, 1 from unnest(array['x2', 'y2']) k;
-- E1 周六机器人局（b_account 空）、A 拿第 4 胜（含铸币 / 宝箱 / 香火 / 右方字段）
select pg_temp.eq_run('E1', 'x1', 'y1', null, null, 'gauntlet',
  jsonb_build_object('account', pg_temp.u('x1'), 'gw0', 3, 'gl0', 1, 'rules_ver', 1, 'pick', 'bot', 'opp', 'bot:1:4:3:1:0'),
  jsonb_build_object('account', pg_temp.u('y1'), 'gw0', 3, 'gl0', 1, 'rules_ver', 1, 'pick', 'bot', 'opp', 'bot:1:4:3:1:0'),
  'a', jsonb_build_object('coins', 9, 'coins_b', 4, 'chest', jsonb_build_object('value', 3), 'chest_b', jsonb_build_object('value', 5),
                          'incense', jsonb_build_object('marks', 2), 'incense_b', jsonb_build_object('marks', 6)));
-- E2 周六真人快照局（旧路：b_account = 被打的快照主人）、A 输 ⇒ ★B 不许被记一场
select pg_temp.eq_run('E2', 'x2', 'y2', 'xb', 'yb', 'gauntlet',
  jsonb_build_object('account', pg_temp.u('x2'), 'gw0', 1, 'gl0', 1, 'rules_ver', 1, 'pick', 'fresh', 'opp', pg_temp.u('xb')::text),
  jsonb_build_object('account', pg_temp.u('y2'), 'gw0', 1, 'gl0', 1, 'rules_ver', 1, 'pick', 'fresh', 'opp', pg_temp.u('yb')::text),
  'b', jsonb_build_object('coins', 2, 'coins_b', 8));
-- E3 排队兜底局（meta.fallback，b_account 空）、A 赢、结果单没带 rules_ver 以外的东西
select pg_temp.eq_run('E3', 'x3', 'y3', null, null, 'gauntlet',
  jsonb_build_object('account', pg_temp.u('x3'), 'gw0', 0, 'gl0', 0, 'pick', 'bot', 'fallback', true, 'opp', 'bot:1:0:0:0:1'),
  jsonb_build_object('account', pg_temp.u('y3'), 'gw0', 0, 'gl0', 0, 'pick', 'bot', 'fallback', true, 'opp', 'bot:1:0:0:0:1'),
  'a', '{}'::jsonb);
-- E4 周日决赛局（两边都是账号）、B 赢 1-1 比分码
select pg_temp.eq_run('E4', 'x4', 'y4', 'xb', 'yb', 'finals',
  jsonb_build_object('bucket', 9, 'round', 1, 'match', 0), jsonb_build_object('bucket', 9, 'round', 1, 'match', 1),
  'b', jsonb_build_object('coins', 1, 'coins_b', 3, 'chest_b', jsonb_build_object('value', 7)));
select pg_temp.ck('E 分母: 四局都写进去了（新旧各 4）', (select count(*) from _eq where rx->>'ok' = 'true' and ry->>'ok' = 'true') = 4,
  (select string_agg(sc || ':' || rx::text || '/' || ry::text, ' ') from _eq));
select pg_temp.ck('E1 机器人局: 回包 / 战绩 / 快照池 / 决赛报名 / 录像 / 账本 与改前逐字相同',
  (select rx = ry and pg_temp.eq_state(pg_temp.u('x1'), jx) = pg_temp.eq_state(pg_temp.u('y1'), jy) from _eq where sc = 'E1'),
  (select pg_temp.eq_state(pg_temp.u('x1'), jx)::text || ' ≠? ' || pg_temp.eq_state(pg_temp.u('y1'), jy)::text from _eq where sc = 'E1'));
select pg_temp.ck('E1 分母: 状态不是空的（4-1、报了名、录像一行）',
  (select (s->'rec'->>'gw')::int = 4 and s->'fp' is not null and (s->'m'->>'n')::int = 1 and s->'job'->>'status' = 'done'
     from (select pg_temp.eq_state(pg_temp.u('y1'), jy) s from _eq where sc = 'E1') x));
select pg_temp.ck('E2 真人快照局: 与改前逐字相同（B 没被记、right_account 仍空）',
  (select rx = ry and pg_temp.eq_state(pg_temp.u('x2'), jx) = pg_temp.eq_state(pg_temp.u('y2'), jy) from _eq where sc = 'E2'),
  (select pg_temp.eq_state(pg_temp.u('x2'), jx)::text || ' ≠? ' || pg_temp.eq_state(pg_temp.u('y2'), jy)::text from _eq where sc = 'E2'));
select pg_temp.ck('E2 分母: A 1-2、B 0 行、录像 right 空',
  (select (s->'rec'->>'gl')::int = 2 and (s->>'b_rec')::int = 0 and (s->>'b_gh')::int = 0 and s->'m'->>'right_null' = 'true'
     from (select pg_temp.eq_state(pg_temp.u('y2'), jy) s from _eq where sc = 'E2') x));
select pg_temp.ck('E3 兜底局: 与改前逐字相同',
  (select rx = ry and pg_temp.eq_state(pg_temp.u('x3'), jx) = pg_temp.eq_state(pg_temp.u('y3'), jy) from _eq where sc = 'E3'),
  (select pg_temp.eq_state(pg_temp.u('x3'), jx)::text || ' ≠? ' || pg_temp.eq_state(pg_temp.u('y3'), jy)::text from _eq where sc = 'E3'));
select pg_temp.ck('E4 决赛局: 与改前逐字相同（finals_results / coins_b / right_account）',
  (select rx = ry and pg_temp.eq_state(pg_temp.u('x4'), jx) = pg_temp.eq_state(pg_temp.u('y4'), jy) from _eq where sc = 'E4'),
  (select pg_temp.eq_state(pg_temp.u('x4'), jx)::text || ' ≠? ' || pg_temp.eq_state(pg_temp.u('y4'), jy)::text from _eq where sc = 'E4'));
select pg_temp.ck('E4 分母: 决赛结果行在、账本有 coins_b',
  (select s->'fr' is not null and (s->'job'->'result'->'ledger'->>'coins_b')::int = 3
     from (select pg_temp.eq_state(pg_temp.u('y4'), jy) s from _eq where sc = 'E4') x));
-- referee_job_status：四局写完的 + 未算完的 + 算失败的，A 查到的回包与改前逐字相同（录像号归一）
insert into _eq select 'E5', pg_temp.eq_mk(pg_temp.u('x1'), null, 'gauntlet', 'chk20261027:eq:E5:x', '{}'::jsonb, 'pending'),
                             pg_temp.eq_mk(pg_temp.u('y1'), null, 'gauntlet', 'chk20261027:eq:E5:y', '{}'::jsonb, 'pending'), null, null;
insert into _eq select 'E6', pg_temp.eq_mk(pg_temp.u('x2'), pg_temp.u('xb'), 'gauntlet', 'chk20261027:eq:E6:x', '{}'::jsonb, 'claimed'),
                             pg_temp.eq_mk(pg_temp.u('y2'), pg_temp.u('yb'), 'gauntlet', 'chk20261027:eq:E6:y', '{}'::jsonb, 'claimed'), null, null;
update public.referee_jobs set status = 'failed', error = 'lease_expired' where job_id in (select jx from _eq where sc = 'E6' union all select jy from _eq where sc = 'E6');
create or replace function pg_temp.js_pair(p_sc text) returns text language plpgsql as $$
declare e record; a jsonb; b jsonb; kx text; ky text;
begin
  select * into e from _eq where sc = p_sc;
  select k into kx from _u where id = (select a_account from public.referee_jobs where job_id = e.jx);
  select k into ky from _u where id = (select a_account from public.referee_jobs where job_id = e.jy);
  perform pg_temp.as_user(pg_temp.u(kx));
  a := pg_temp.js_old(e.jx) - 'match_id';
  perform pg_temp.as_user(pg_temp.u(ky));
  b := public.referee_job_status(e.jy) - 'match_id';
  return case when a = b then 'same' else a::text || ' ≠ ' || b::text end;
end $$;
select pg_temp.ck('E7 referee_job_status（A 查）六种旧路任务 与改前逐字相同',
  (select bool_and(pg_temp.js_pair(sc) = 'same') and count(*) = 6 from _eq),
  (select string_agg(sc || '=' || pg_temp.js_pair(sc), ' ') from _eq));
select pg_temp.as_user(pg_temp.u('y1'));
select pg_temp.keep('e7', (select public.referee_job_status(jy) from _eq where sc = 'E1'));
select pg_temp.ck('E7 分母: 回包里真有结果（E1 的 won / gw / coins / chest）',
  pg_temp.r('e7')->>'won' = 'true' and (pg_temp.r('e7')->>'gw')::int = 4 and (pg_temp.r('e7')->>'coins')::int = 9
  and (pg_temp.r('e7')->'chest'->>'value')::int = 3, pg_temp.r('e7')::text);

-- ★红的那几条排在最前面（每条截 600 字）：Management API 回的报错只有约 3600 字，91 条全列出来时红的那条会被截掉
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
