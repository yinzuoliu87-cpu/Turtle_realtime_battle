-- >>> BEGIN gauntlet_server_pick_and_coins 20261020c >>>
-- ─────────────────────────────────────────────────────────────
-- 周六闯关 · 对手由服务端挑 + 服务器局发战斗内铸币（2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md
--   决策记录「10-20 用户授权自定：周六对手改服务器挑」）—— ★只写文件、未上生产。
--   前提：20261019_referee_jobs.sql / 20261019_min_version_gate.sql（gauntlet_ghosts.rules_ver）/ 20261020_referee_live_list.sql 已执行。
--
-- 两件事：
--   Ⅰ 战斗内铸币（奇械羁绊铸币 + 035 黄铜齿轮）：本机打完由 `_settle_season` 加进奖励，而服务器算的周六局一枚都没发
--     （客户端记账在播之前，拿不到本机重算的数）。⇒ 裁判结果单多一个 `coins`（左方 A 的铸币，`EquipTickSystem.match_minted`，
--     与本机结算读同一个函数），referee_complete 记进账本 `ledger.coins`，referee_job_status 回给客户端，客户端按它发币。
--     ★客户端没有任何参数位能报币数；`coins` 只从裁判机（service_role）的结果单来，夹在 0..999。
--   Ⅱ 周六对手由服务端挑：原来客户端挑好对手快照、连同自己的阵容一起交（referee_submit_gauntlet 的 p_opponent）⇒ 能挑弱对手。
--     新接口 referee_gauntlet_start(p_week, p_snapshot, p_match_no, p_client_version, p_rules_ver)：客户端只交「我的阵容 + 我要打第 N 场」，
--     服务端按现行匹配规则挑对手、生成种子、建任务，回任务号 + 对手卡片（名字 / 头像 / 号 / 三统领；真人与机器人同一形状）。
--       匹配规则（= 客户端 Backend.find_gauntlet_opponent / gauntlet_pool_find，原稿兜底链）：
--         ① 同标签真人（gauntlet_ghosts：同周、gw / gl 完全相同、同 rules_ver、不是自己、本周没碰过）——
--            30 分钟内上传的优先（新鲜度用服务端的 uploaded_at，不信快照自报的 gl_ts），没有新鲜的才用隔夜的；
--         ② 机器人（gauntlet_bot_pool：同 rules_ver、同标签、场次 = 我的本周场次，夹到池子上限 30；本周碰过的那几份排后）。
--         **永不跨标签。** 机器人不露馅：快照与真人同形（摘 origin、按真人口径重写 gl_ts），卡片同形，任务行 / 录像 / 直播行都看不出。
--       机器人快照池由客户端代码离线生成（scripts/referee/bot_pool.gd = Backend.make_bot 同一个函数），
--         轮询器 `referee_poller.py --bot-pool` 对每个装了的版本生成并调 referee_bot_pool_load 上传（只有 service_role）。
--         ★为什么不在裁判机领活时现场生成：快照是数据 ⇒ 任务从建立那一刻起就是完整的（直播行 / 录像行 / 补流都照旧读 b_snapshot），
--           裁判程序一行不改、对确定性零影响；现场生成要多一次「领活 → 生成 → 回写 b_snapshot → 再算」的状态机，
--           而生成失败 / 回写失败都会卡住一场。代价：池子要随版本上传（发版步骤多一步；忘了 ⇒ 挑不到机器人回 no_opponent，健康检查报警）。
--     旧接口 referee_submit_gauntlet：referee_config.gauntlet_server_pick 打开后一律回 update_required（旧包整屏「请更新」）；
--       没打开时逐字照旧（上线顺序见文末）。
--
-- 本段内容（全是添加，或在既有函数里加分支 / 多回键；★gauntlet_server_pick 默认关 ⇒ 执行本段不改变任何现行客户端的行为）：
--   ① referee_config.gauntlet_server_pick、referee_versions.rules_ver
--   ② gauntlet_bot_pool（表）+ referee_bot_pool_load（service_role）
--   ③ referee_lineup_ok / referee_lanes_ok / referee_opp_card / referee_gauntlet_pick（内部，不授权给客户端）
--   ④ referee_gauntlet_start（authenticated）
--   ⑤ 重定义 referee_submit_gauntlet（开关后面加一条拒收）/ referee_job_status（多回 coins）/
--      referee_complete（记 coins；挂进快照池时写 rules_ver —— 原来漏写 = 0，新客户端永远拉不到裁判挂的那份）/
--      referee_backlog（多回机器人池行数，给 --health）
--   正文其余逐字照抄 20261019_referee_jobs.sql 现行版，只在标了「2026-10-20」的地方改。
-- ★重复执行安全（add column if not exists / create if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ① 开关 / 版本的规则号 ─────────────────────────────────────
alter table public.referee_config add column if not exists gauntlet_server_pick boolean not null default false;
-- 每个裁判版本对应的战斗规则版本（phase2_config.RULES_VER）；referee_bot_pool_load 上传时写。null = 还没上传过池子。
alter table public.referee_versions add column if not exists rules_ver int;

-- ② 机器人快照池 ─────────────────────────────────────────────
-- 一行 = 一份机器人快照（Backend.make_bot(场次, rng, gw, gl) 的产物，摘掉 origin / gl_ts）。
create table if not exists public.gauntlet_bot_pool (
  rules_ver      int         not null,
  battles        int         not null check (battles between 0 and 1000),
  gw             int         not null check (gw between 0 and 9),
  gl             int         not null check (gl between 0 and 9),
  variant        int         not null check (variant between 0 and 99),
  snapshot       jsonb       not null,
  client_version text        not null,              -- 哪个版本的代码生成的（只作记录；挑的时候按 rules_ver）
  created_at     timestamptz not null default now(),
  primary key (rules_ver, battles, gw, gl, variant)
);
alter table public.gauntlet_bot_pool enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行（机器人池本身就是「哪些是机器人」的答案）

-- 快照能不能当左方（A）开打 —— 与裁判 RefereeJob.validate + _state_from_snapshot 同一组条件：
--   三统领（去空去重后恰好 3 只）、分路 top / bottom 都是数组、每只统领在两路里恰好出现一次。
-- ★写成 plpgsql 逐条 if：SQL 的 and 不保证求值顺序，jsonb_array_elements 碰到非数组会直接报错。
create or replace function public.referee_lineup_ok(p_snap jsonb) returns boolean
language plpgsql immutable as $$
declare n int; bad int;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' then
    return false;
  end if;
  if jsonb_typeof(p_snap->'leaders') <> 'array' or jsonb_array_length(p_snap->'leaders') <> 3 then
    return false;
  end if;
  if jsonb_typeof(p_snap->'lane_assign') <> 'object'
     or jsonb_typeof(p_snap->'lane_assign'->'top') is distinct from 'array'
     or jsonb_typeof(p_snap->'lane_assign'->'bottom') is distinct from 'array' then
    return false;
  end if;
  select count(distinct x) into n from jsonb_array_elements_text(p_snap->'leaders') x where x <> '';
  if n <> 3 then
    return false;
  end if;
  select count(*) into bad
    from (select distinct x as l from jsonb_array_elements_text(p_snap->'leaders') x where x <> '') d
   where (select count(*)
            from (select jsonb_array_elements_text(p_snap->'lane_assign'->'top') as y
                  union all
                  select jsonb_array_elements_text(p_snap->'lane_assign'->'bottom')) z
           where z.y = d.l) <> 1;
  return bad = 0;
end $$;
revoke all on function public.referee_lineup_ok(jsonb) from public, anon, authenticated;

-- 快照能不能当右方（B）开打 —— 与裁判 _lanes_ok（= Backend.ghost_lanes_broken 取反）同一组条件：
--   分路 top / bottom 都是数组，且至少一路有统领。
create or replace function public.referee_lanes_ok(p_snap jsonb) returns boolean
language plpgsql immutable as $$
declare n int;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' or jsonb_typeof(p_snap->'lane_assign') <> 'object'
     or jsonb_typeof(p_snap->'lane_assign'->'top') is distinct from 'array'
     or jsonb_typeof(p_snap->'lane_assign'->'bottom') is distinct from 'array' then
    return false;
  end if;
  select count(*) into n
    from (select jsonb_array_elements_text(p_snap->'lane_assign'->'top') as y
          union all
          select jsonb_array_elements_text(p_snap->'lane_assign'->'bottom')) z
   where z.y <> '';
  return n > 0;
end $$;
revoke all on function public.referee_lanes_ok(jsonb) from public, anon, authenticated;

-- 上传机器人池（只有 service_role：轮询器 referee_poller.py --bot-pool）。分批调：第一批 p_replace = true 先清掉这个规则版本的旧池。
-- 每行 {battles, gw, gl, variant, snapshot}；快照必须能开打（referee_lineup_ok），否则计入 rejected、不入池。
create or replace function public.referee_bot_pool_load(p_client_version text, p_rules_ver int, p_rows jsonb,
    p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; bad int := 0; total int;
begin
  if p_rules_ver is null or p_rules_ver < 1 or p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or coalesce(p_client_version, '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_args');
  end if;
  if coalesce(p_replace, false) then
    delete from public.gauntlet_bot_pool where rules_ver = p_rules_ver;
  end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r) <> 'object'
       or jsonb_typeof(r->'battles') <> 'number' or jsonb_typeof(r->'gw') <> 'number'
       or jsonb_typeof(r->'gl') <> 'number' or jsonb_typeof(r->'variant') <> 'number'
       or not public.referee_lineup_ok(r->'snapshot') or octet_length((r->'snapshot')::text) > 65536 then
      bad := bad + 1;
      continue;
    end if;
    insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
      values (p_rules_ver, (r->>'battles')::numeric::int, (r->>'gw')::numeric::int, (r->>'gl')::numeric::int,
              (r->>'variant')::numeric::int, (r->'snapshot') - 'origin' - 'gl_ts', p_client_version)
      on conflict (rules_ver, battles, gw, gl, variant) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, created_at = now();
    n := n + 1;
  end loop;
  update public.referee_versions set rules_ver = p_rules_ver where client_version = p_client_version;
  select count(*) into total from public.gauntlet_bot_pool where rules_ver = p_rules_ver;
  return jsonb_build_object('ok', true, 'loaded', n, 'rejected', bad, 'total', total);
end $$;
revoke all on function public.referee_bot_pool_load(text, int, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.referee_bot_pool_load(text, int, jsonb, boolean) to service_role;

-- ③ 对手卡片 / 挑对手 ─────────────────────────────────────────
-- 回给客户端画 VS 卡的那一份：profile 只留 name / avatar / id / tag，外加三统领。真人与机器人同一形状、同一组键。
create or replace function public.referee_opp_card(p_snap jsonb) returns jsonb
language plpgsql immutable as $$
declare pf jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_snap->'profile') = 'object' then
    select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into pf
      from jsonb_each(p_snap->'profile') e
     where e.key in ('name', 'avatar', 'id', 'tag');
  end if;
  return jsonb_build_object('profile', pf,
    'leaders', case when jsonb_typeof(p_snap->'leaders') = 'array' then p_snap->'leaders' else '[]'::jsonb end);
end $$;
revoke all on function public.referee_opp_card(jsonb) from public, anon, authenticated;

-- 挑一个对手。返回 {snap, opp, pick, account}（opp = 真人账号 uuid / 'bot:<规则>:<场次>:<胜>:<负>:<序号>'；pick = fresh / stale / bot；
--   account = 真人对手的账号，机器人没有这个键 ⇒ 任务行 b_account 真人填、机器人 null；20261020b 的删号 / 改名按它找得到）；
-- 一个都挑不到 ⇒ null。p_battles = 我的本周场次（机器人强度的唯一输入，= 客户端 gauntlet_bot_battles）。
-- ★排除：本周已经碰过的对手（这个人本周所有闯关任务 meta.opp / meta.opp_prev）—— 与客户端「最近 8 个对手」同一用意，
--   周六一个人最多 6 场 ⇒ 排除本周全部。真人排除了就不挑；机器人池排除了只是排后（池子每格 6 份，够一周不重样）。
create or replace function public.referee_gauntlet_pick(p_uid uuid, p_week bigint, p_gw int, p_gl int,
    p_rules_ver int, p_battles int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_ex text[]; g record; bp record; bk int; snap jsonb;
begin
  select coalesce(array_agg(x), '{}') into v_ex
    from (select j.meta->>'opp' as x from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid and j.meta ? 'opp'
          union all
          select jsonb_array_elements_text(j.meta->'opp_prev') from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid
             and jsonb_typeof(j.meta->'opp_prev') = 'array') e
   where x is not null;
  -- ① 同标签真人：30 分钟内的优先（= phase2_config.FRESH_SNAPSHOT_SEC 1800），再随机
  select gg.account_id, gg.snapshot, gg.uploaded_at into g
    from public.gauntlet_ghosts gg
   where gg.season_week = p_week and gg.gw = p_gw and gg.gl = p_gl and gg.rules_ver = p_rules_ver
     and gg.account_id <> p_uid and not (gg.account_id::text = any(v_ex))
     and public.referee_lanes_ok(gg.snapshot)
   order by (gg.uploaded_at > now() - make_interval(secs => 1800)) desc, random()
   limit 1;
  if found then
    return jsonb_build_object('snap', g.snapshot - 'origin', 'opp', g.account_id::text, 'account', g.account_id,
      'pick', case when g.uploaded_at > now() - make_interval(secs => 1800) then 'fresh' else 'stale' end);
  end if;
  -- ② 机器人：池子按场次存到 30（= bot_pool.gd MAX_BATTLES；装备曲线 28 场封顶），超出的用 30 那一格
  bk := least(greatest(coalesce(p_battles, 0), p_gw + p_gl, 0), 30);
  select b.* into bp
    from public.gauntlet_bot_pool b
   where b.rules_ver = p_rules_ver and b.battles = bk and b.gw = p_gw and b.gl = p_gl
   order by (format('bot:%s:%s:%s:%s:%s', b.rules_ver, b.battles, b.gw, b.gl, b.variant) = any(v_ex)), random()
   limit 1;
  if not found then
    return null;
  end if;
  -- 真人口径的上传时刻：现在往前 60~1500 秒（= Backend.make_bot 的 gl_ts，落在 30 分钟新鲜窗里）
  snap := jsonb_set(bp.snapshot - 'origin', '{gl_ts}',
                    to_jsonb(extract(epoch from now())::bigint - (60 + floor(random() * 1441))::bigint));
  if coalesce(p_battles, 0) > bk then
    snap := jsonb_set(snap, '{season_total_battles}', to_jsonb(p_battles));   -- 场次标签与玩家相同（用户 10-04「场次一定要相同」）
  end if;
  return jsonb_build_object('snap', snap,
    'opp', format('bot:%s:%s:%s:%s:%s', bp.rules_ver, bp.battles, bp.gw, bp.gl, bp.variant), 'pick', 'bot');
end $$;
revoke all on function public.referee_gauntlet_pick(uuid, bigint, int, int, int, int) from public, anon, authenticated;

-- ④ 周六开战（客户端）─────────────────────────────────────────
-- 客户端只交：本周 / 我的阵容 / 我要打第几场（0 起 = gw + gl）/ 版本 / 规则版本。对手与种子都在这里定，客户端改不了。
-- 回包：{ok, job_id, match_id, opp: {profile, leaders}, gw, gl}（gw / gl = 账本上这一场之前的数）。
--   reason：not_signed_in / off / update_required / wrong_week / closed / bad_snapshot / finished / stale / no_opponent。
-- ★同一个人同一时刻只有一场在算（在算的那场直接把号和对手还给他）。
-- ★只有「上一次算失败了」才允许同一场重交：种子不换；对手不换（除非失败原因是对手快照坏了 b_bad_snapshot ⇒ 重挑，旧的进 opp_prev 排除）；
--   阵容不换（除非失败原因是我的阵容坏了 a_bad_snapshot）—— 否则「看到对手 → 故意交坏 → 改阵容针对」就成了。
create or replace function public.referee_gauntlet_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text, p_rules_ver int)
returns jsonb language plpgsql security definer set search_path = public as $$
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
  if p_week <> extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (now() >= to_timestamp(p_week + 5 * 86400) and now() < to_timestamp(p_week + 6 * 86400)) then
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
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'gw', v_gw, 'gl', v_gl);
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
end $$;
revoke all on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) to authenticated;

-- ⑤ 重定义的现行函数 ───────────────────────────────────────

-- 旧接口：客户端交对手快照。★2026-10-20：gauntlet_server_pick 打开后一律拒（旧包看到「请更新」）；没打开时下面逐字照旧。
create or replace function public.referee_submit_gauntlet(p_week bigint, p_snapshot jsonb, p_opponent jsonb,
    p_client_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text;
        jid bigint; mid uuid; st text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  -- ★2026-10-20 周六对手改服务器挑: 开关开着时不再收客户端挑的对手(新客户端走 referee_gauntlet_start)
  if coalesce(cfg.gauntlet_server_pick, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if not exists (select 1 from public.referee_versions where client_version = p_client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (now() >= to_timestamp(p_week + 5 * 86400) and now() < to_timestamp(p_week + 6 * 86400)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') <> 3
     or jsonb_typeof(p_snapshot->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  if p_opponent is null or jsonb_typeof(p_opponent) <> 'object' or octet_length(p_opponent::text) > 65536
     or jsonb_typeof(p_opponent->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_opponent');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true);
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, null,
      p_snapshot, p_opponent, public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl))
    on conflict (match_key) do update
      set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null,
          a_snapshot = excluded.a_snapshot, b_snapshot = excluded.b_snapshot,
          client_version = excluded.client_version, level = excluded.level, created_at = now()
      where public.referee_jobs.status = 'failed'
    returning job_id, match_id into jid, mid;
  if jid is null then
    select job_id, match_id, status into jid, mid, st from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid);
end $$;
revoke all on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) from public, anon;
grant execute on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) to authenticated;

-- 查自己那一场算完没有（只认 a_account = 自己；不回快照）。★2026-10-20 多回 coins（这一局我方的战斗内铸币；旧任务没有 ⇒ null ⇒ 客户端当 0）。
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
    'error', case when j.status = 'failed' then j.error end);
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- 写回。★2026-10-20 两处：① 结果单的 coins（A 的战斗内铸币，裁判 EquipTickSystem.match_minted）夹到 0..999 记进账本 ledger.coins
--   （只进任务行，不进 matches.result —— 那一行所有登录用户都读得到）；② 挂进 gauntlet_ghosts 时写 rules_ver
--   （原来漏写 = 默认 0 ⇒ 新客户端按 rules_ver 拉对手 / 服务端按 rules_ver 挑对手都永远碰不到这一份）。
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int;
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
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins))
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- 监控。★2026-10-20 多回：周六开关 / 服务端挑对手开关 / 每个启用版本的机器人池行数（--health：周六开着而某个启用版本池子是空的 ⇒ 报警）。
create or replace function public.referee_backlog()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pending', (select count(*) from public.referee_jobs where status = 'pending'),
    'claimed', (select count(*) from public.referee_jobs where status = 'claimed'),
    'failed_24h', (select count(*) from public.referee_jobs where status = 'failed' and done_at > now() - interval '24 hours'),
    'oldest_pending_sec', (select coalesce(extract(epoch from now() - min(created_at))::int, 0)
                             from public.referee_jobs where status = 'pending'),
    'workers', (select coalesce(jsonb_agg(jsonb_build_object('worker', worker, 'versions', versions,
                  'seen_sec', extract(epoch from now() - seen_at)::int)), '[]'::jsonb) from public.referee_workers),
    'gauntlet_on', public.referee_gauntlet_on(),
    'server_pick', coalesce((select gauntlet_server_pick from public.referee_config where id = 1), false),
    'bot_pool', (select coalesce(jsonb_agg(jsonb_build_object('client_version', v.client_version, 'rules_ver', v.rules_ver,
                  'rows', (select count(*) from public.gauntlet_bot_pool b where b.rules_ver = v.rules_ver))
                  order by v.client_version), '[]'::jsonb)
                   from public.referee_versions v where v.enabled))
$$;
revoke all on function public.referee_backlog() from public, anon, authenticated;
grant execute on function public.referee_backlog() to service_role;

-- 上线步骤（内测服先走一遍，每步回读；正式服同样顺序。★全程不需要停服）：
--   1. 执行本文件。回读：select gauntlet_server_pick from referee_config;  -- false
--      select public.referee_lineup_ok('{"leaders":["a","b","c"],"lane_assign":{"top":["a","b"],"bottom":["c"]}}');  -- true
--      select public.referee_lineup_ok('{"leaders":["a","b","c"],"lane_assign":{"top":["a","b"],"bottom":["a"]}}');  -- false
--   2. 裁判机：每个装了的版本 `referee_poller.py --bot-pool`（生成 + 上传），回读 select public.referee_backlog()->'bot_pool';
--      每个启用版本 rows = 2052（31 个场次 × 可开打标签 × 6 份）、rules_ver 非 null。
--   3. 裁判机装新客户端版本（含 referee_gauntlet_start 的那一版）+ insert into referee_versions + 第 2 步给它传池子。
--   4. 新客户端上架、`min_client_version` 抬到它（版本闸让旧包整屏「请更新」）之后：
--      update referee_config set gauntlet_server_pick = true, updated_at = now() where id = 1;
--      回读：旧接口 referee_submit_gauntlet 回 {"ok":false,"reason":"update_required"}。
--   兼容：第 4 步之前旧包照旧走 referee_submit_gauntlet（客户端挑对手，原有缺口仍在）；新包任何时候都走新接口。
--         新包碰到没执行本文件的服务端 ⇒ referee_gauntlet_start 404 ⇒ 屏上「连接服务器后才能比赛」，不出本地成绩
--         （所以本文件必须先于新客户端上线）。
--   回滚：update referee_config set gauntlet_server_pick = false（旧接口恢复）；其余对象留着不影响旧包。
-- <<< END gauntlet_server_pick_and_coins 20261020c <<<
