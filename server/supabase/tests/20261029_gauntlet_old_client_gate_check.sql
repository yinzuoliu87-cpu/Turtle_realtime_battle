-- 20261029 闯关赛旧客户端闸 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261029_gauntlet_old_client_gate
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
-- 假时间照 20261026b / 20261027b 检查脚本（本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原）。
-- 判据（假周六 12:00，阵容合法、第 0 场；同格子种了一份真人快照，新版本走旧路一定挑得到对手、建得出任务）：
--   G1 0.22.2 ⇒ update_required；G2 不建任务（这个号名下 0 条任务）；G3 回包 ≥ 600 字（> 0.22.2 整屏墙判据的 512），
--      min_version = '0.22.3'；G4 0.21.3 ⇒ 同样挡
--   G5 边界 0.22.3 ⇒ 照旧开局（ok、有任务号、任务的 client_version 就是它）；G6 0.22.10 ⇒ 照旧开局（数字比较，不是字串比较）
--   K  旧客户端在闸前那几道照旧：K1 假周五 ⇒ closed；K2 坏阵容 ⇒ bad_snapshot；K3 4-0 ⇒ finished；
--      K4 有一场在算 ⇒ 回那一场（in_flight，同一个任务号）；K5 本机战绩落后 ⇒ stale
--   K6 失败的那一场不重交：旧客户端第 0 场有一条 failed 任务 ⇒ update_required，任务仍是 failed、attempts 不变
--   S1 函数体 = 20261027 版 + 本段那一块（逐字；去掉那一块后与改前逐字相同）
--   S2 权限：authenticated 能调、anon 不能；gauntlet_queue_min_client 客户端两个角色都调不了
--   分母：本脚本里 referee_gauntlet_start 新建的任务恰好 2 条（G5 / G6）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['old', 'old21', 'new3', 'new10', 'fri', 'bad', 'fin', 'fly', 'stale', 'fail', 'opp']);
create temp table _r (k text primary key, r jsonb);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
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
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')))
$$;
-- 以 p_k 的身份、报 p_ver 版本开第 p_no 场（阵容默认合法）
create or replace function pg_temp.start(p_k text, p_ver text, p_no int default 0, p_snap jsonb default null) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  r := public.referee_gauntlet_start(pg_temp.fake_week(), coalesce(p_snap, pg_temp.snap(p_k)), p_no, p_ver, 1);
  perform pg_temp.as_user(null);
  return pg_temp.keep(p_k, r);
end $$;
create or replace function pg_temp.jobs_of(p_k text) returns int language sql as $$
  select count(*)::int from public.referee_jobs where a_account = pg_temp.u(p_k)
$$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false, gauntlet_server_pick = true where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver)
  values ('0.21.3', true, 1), ('0.22.2', true, 1), ('0.22.3', true, 1), ('0.22.10', true, 1)
  on conflict (client_version) do update set enabled = true, rules_ver = 1;
select pg_temp.set_fake(6, 12);
-- 同格子（0-0）种一份真人快照：新版本走旧路时一定挑得到对手（沙盒里机器人池是空的）
insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
  values (pg_temp.u('opp'), pg_temp.fake_week(), 0, 0, pg_temp.snap('opp'), '0.22.3', 1);
create temp table _j0 as select coalesce(max(job_id), 0) as j from public.referee_jobs;
grant select on _j0 to public;

-- ── G 闸 ──
select pg_temp.start('old', '0.22.2');
select pg_temp.ck('G1 0.22.2 假周六 ⇒ update_required', pg_temp.r('old')->>'ok' = 'false'
  and pg_temp.r('old')->>'reason' = 'update_required', left(pg_temp.r('old')::text, 200));
select pg_temp.ck('G2 0.22.2 ⇒ 不建任务（名下 0 条）', pg_temp.jobs_of('old') = 0, pg_temp.jobs_of('old')::text);
select pg_temp.ck('G3 回包 ≥ 600 字（0.22.2 整屏墙判据是 ≤512）且 min_version = 0.22.3',
  length(pg_temp.r('old')::text) >= 600 and length(pg_temp.r('old')::jsonb::text) > 512
  and pg_temp.r('old')->>'min_version' = '0.22.3', length(pg_temp.r('old')::text)::text || ' 字');
select pg_temp.start('old21', '0.21.3');
select pg_temp.ck('G4 0.21.3 ⇒ 同样挡、不建任务', pg_temp.r('old21')->>'reason' = 'update_required' and pg_temp.jobs_of('old21') = 0,
  left(pg_temp.r('old21')::text, 120));
select pg_temp.start('new3', '0.22.3');
select pg_temp.ck('G5 边界 0.22.3 ⇒ 照旧开局（ok、有任务、任务版本 0.22.3）',
  pg_temp.r('new3')->>'ok' = 'true' and (pg_temp.r('new3')->>'job_id')::bigint > 0
  and (select client_version from public.referee_jobs where job_id = (pg_temp.r('new3')->>'job_id')::bigint) = '0.22.3'
  and not (pg_temp.r('new3') ? 'pad'), left(pg_temp.r('new3')::text, 200));
select pg_temp.start('new10', '0.22.10');
select pg_temp.ck('G6 0.22.10 ⇒ 照旧开局（数字比较：字串比较下 0.22.10 < 0.22.3）',
  pg_temp.r('new10')->>'ok' = 'true' and pg_temp.jobs_of('new10') = 1, left(pg_temp.r('new10')::text, 200));

-- ── K 闸前那几道对旧客户端照旧 ──
select pg_temp.set_fake(5, 12);
select pg_temp.start('fri', '0.22.2');
select pg_temp.ck('K1 0.22.2 假周五 ⇒ closed（不是 update_required）', pg_temp.r('fri')->>'reason' = 'closed', pg_temp.r('fri')::text);
select pg_temp.set_fake(6, 12);
select pg_temp.start('bad', '0.22.2', 0, '{"leaders": ["ninja"]}'::jsonb);
select pg_temp.ck('K2 0.22.2 坏阵容 ⇒ bad_snapshot', pg_temp.r('bad')->>'reason' = 'bad_snapshot', pg_temp.r('bad')::text);
insert into public.gauntlet_records (season_week, account_id, gw, gl) values (pg_temp.fake_week(), pg_temp.u('fin'), 4, 0);
select pg_temp.start('fin', '0.22.2', 4);
select pg_temp.ck('K3 0.22.2 已 4-0 ⇒ finished', pg_temp.r('fin')->>'reason' = 'finished', pg_temp.r('fin')::text);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, meta, status)
  values ('gauntlet', 'chk20261029:fly:' || pg_temp.u('fly'), pg_temp.fake_week(), '0.22.2', 4243, pg_temp.u('fly'),
          pg_temp.snap('fly'), pg_temp.snap('opp'), '{"rules_ver": 1}'::jsonb, 'pending');
select pg_temp.start('fly', '0.22.2');
select pg_temp.ck('K4 0.22.2 有一场在算 ⇒ 回那一场（in_flight、同一个任务号）',
  pg_temp.r('fly')->>'ok' = 'true' and pg_temp.r('fly')->>'in_flight' = 'true'
  and (pg_temp.r('fly')->>'job_id')::bigint = (select job_id from public.referee_jobs where a_account = pg_temp.u('fly'))
  and pg_temp.jobs_of('fly') = 1, left(pg_temp.r('fly')::text, 200));
select pg_temp.start('stale', '0.22.2', 2);
select pg_temp.ck('K5 0.22.2 报第 2 场、账本 0-0 ⇒ stale', pg_temp.r('stale')->>'reason' = 'stale', pg_temp.r('stale')::text);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
    meta, status, attempts, error)
  values ('gauntlet', format('gauntlet:%s:%s:%s', pg_temp.fake_week(), pg_temp.u('fail'), 0), pg_temp.fake_week(), '0.22.2', 4243,
          pg_temp.u('fail'), pg_temp.snap('fail'), pg_temp.snap('opp'), '{"rules_ver": 1}'::jsonb, 'failed', 3, 'timeout');
select pg_temp.start('fail', '0.22.2');
select pg_temp.ck('K6 0.22.2 第 0 场有一条 failed ⇒ update_required，不重交（仍 failed、attempts 仍 3）',
  pg_temp.r('fail')->>'reason' = 'update_required'
  and (select status = 'failed' and attempts = 3 from public.referee_jobs where a_account = pg_temp.u('fail')),
  (select status || ' / ' || attempts from public.referee_jobs where a_account = pg_temp.u('fail')));

-- ── S 函数体 / 权限 ──
create temp table _src as select replace(prosrc, E'\r', '') as s from pg_proc
  where oid = 'public.referee_gauntlet_start(bigint, jsonb, int, text, int)'::regprocedure;
grant select on _src to public;
select pg_temp.ck('S1 函数体 = 20261027 版 + 本段那一块（去掉那一块后逐字相同，那一块恰好出现 1 次）',
  (select replace(s, $blk$  -- ★2026-10-29 旧客户端闸（迁移 20261029）：闯关赛改成在线排队后，0.22.3 起的客户端走 gauntlet_queue_join、不再调本函数；
  --   低于 gauntlet_queue_min_client() 的客户端在这里停下 —— 不建任务、不重交失败的那一场，回 update_required。
  --   回包补到 600 字以上（pad）：0.22.2 把「≤512 字且含 "update_required"」的回包当成整个版本停服，弹整屏「需要更新」墙
  --   （它的 version_gate.gd is_update_required_response），可它平日积分赛照常能打；补长之后它只在匹配屏写一行
  --   「版本过旧，请更新」，左上「←」能回主菜单。放在「在算的那场 / 账本对齐」之后：切换前交上去的那一场照样能查到、补记。
  if coalesce(public.semver_arr(p_client_version), array[0, 0, 0, 0]) < public.semver_arr(public.gauntlet_queue_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required', 'min_version', public.gauntlet_queue_min_client(),
      'pad', repeat('-', 600));
  end if;
$blk$, '') from _src) = $old$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text; v_rv int;
        v_b int; pk jsonb; jid bigint; mid uuid; st text; v_snap_b jsonb; v_meta jsonb; v_found boolean;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = p_client_version and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is distinct from v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 00:00 ~ 周日 17:30（周锚点 + 5 天 ~ + 6 天 17:30；2026-10-26 起，原为周六一整天；UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or octet_length(p_snapshot::text) > 65536 or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- ★2026-10-27 在线瑞士轮：配对局（meta.pair）里我是 B 也算「在算的那场」，对手卡给 A 那一侧。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人，不是在场的人。
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end),
      'gw', v_gw, 'gl', v_gl);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'gw', v_gw, 'gl', v_gl);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta->'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta->>'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_gauntlet_pick(uid, p_week, v_gw, v_gl, v_rv,
              coalesce((v_meta->>'battles')::int, v_gw + v_gl));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'gw', v_gw, 'gl', v_gl);
      end if;
      v_snap_b := pk->'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk->>'opp', 'pick', pk->>'pick');
      update public.referee_jobs set b_account = (pk->>'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = p_client_version,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then p_snapshot else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(p_snapshot) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'gw', v_gw, 'gl', v_gl);
  end if;
  -- 机器人强度 = 我的本周场次（客户端 gauntlet_bot_battles = max(本大轮场次, gw + gl)）。
  --   快照自报的 season_total_battles 只能往上抬（报高了 = 自己打更强的机器人）；地板 = 服务端看得到的积分赛场次 + 周六已打场次。
  v_b := greatest(
    case when jsonb_typeof(p_snapshot->'season_total_battles') = 'number'
         then least((p_snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = uid and season_week = p_week), 0) + v_gw + v_gl,
    v_gw + v_gl);
  pk := public.referee_gauntlet_pick(uid, p_week, v_gw, v_gl, v_rv, v_b);
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'gw', v_gw, 'gl', v_gl);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, (pk->>'account')::uuid,
      p_snapshot, pk->'snap', public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', v_rv, 'battles', v_b, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'gw', v_gw, 'gl', v_gl);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk->'snap'), 'gw', v_gw, 'gl', v_gl);
end $old$
  and (select (length(s) - length(replace(s, $blk$  -- ★2026-10-29 旧客户端闸（迁移 20261029）：闯关赛改成在线排队后，0.22.3 起的客户端走 gauntlet_queue_join、不再调本函数；
  --   低于 gauntlet_queue_min_client() 的客户端在这里停下 —— 不建任务、不重交失败的那一场，回 update_required。
  --   回包补到 600 字以上（pad）：0.22.2 把「≤512 字且含 "update_required"」的回包当成整个版本停服，弹整屏「需要更新」墙
  --   （它的 version_gate.gd is_update_required_response），可它平日积分赛照常能打；补长之后它只在匹配屏写一行
  --   「版本过旧，请更新」，左上「←」能回主菜单。放在「在算的那场 / 账本对齐」之后：切换前交上去的那一场照样能查到、补记。
  if coalesce(public.semver_arr(p_client_version), array[0, 0, 0, 0]) < public.semver_arr(public.gauntlet_queue_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required', 'min_version', public.gauntlet_queue_min_client(),
      'pad', repeat('-', 600));
  end if;
$blk$, ''))) = length($blk$  -- ★2026-10-29 旧客户端闸（迁移 20261029）：闯关赛改成在线排队后，0.22.3 起的客户端走 gauntlet_queue_join、不再调本函数；
  --   低于 gauntlet_queue_min_client() 的客户端在这里停下 —— 不建任务、不重交失败的那一场，回 update_required。
  --   回包补到 600 字以上（pad）：0.22.2 把「≤512 字且含 "update_required"」的回包当成整个版本停服，弹整屏「需要更新」墙
  --   （它的 version_gate.gd is_update_required_response），可它平日积分赛照常能打；补长之后它只在匹配屏写一行
  --   「版本过旧，请更新」，左上「←」能回主菜单。放在「在算的那场 / 账本对齐」之后：切换前交上去的那一场照样能查到、补记。
  if coalesce(public.semver_arr(p_client_version), array[0, 0, 0, 0]) < public.semver_arr(public.gauntlet_queue_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required', 'min_version', public.gauntlet_queue_min_client(),
      'pad', repeat('-', 600));
  end if;
$blk$) from _src),
  (select length(s)::text || ' 字' from _src));
select pg_temp.ck('S2 权限：authenticated 能调 referee_gauntlet_start、anon 不能；gauntlet_queue_min_client 两个都不能',
  has_function_privilege('authenticated', 'public.referee_gauntlet_start(bigint, jsonb, int, text, int)', 'execute')
  and not has_function_privilege('anon', 'public.referee_gauntlet_start(bigint, jsonb, int, text, int)', 'execute')
  and not has_function_privilege('authenticated', 'public.gauntlet_queue_min_client()', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_min_client()', 'execute'));
select pg_temp.ck('分母: 本脚本里 referee_gauntlet_start 新建的任务恰好 2 条（G5 / G6）',
  (select count(*) from public.referee_jobs where job_id > (select j from _j0)
     and a_account in (select id from _u where k <> 'fail') and match_key like 'gauntlet:%') = 2,
  (select count(*)::text from public.referee_jobs where job_id > (select j from _j0) and a_account in (select id from _u)));

-- ★红的那几条排在最前面（每条截 600 字）：Management API 回的报错只有约 3600 字
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
