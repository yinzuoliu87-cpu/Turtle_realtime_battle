-- >>> BEGIN raid 20261109c >>>
-- ─────────────────────────────────────────────────────────────
-- 偷袭任务（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.2 / §4.4 / §4.8 / §4.9 ·
--   主站方案 docs/specs/龟战主站整体方案.md §4 ~ §6 · 工作线 A2）
--   主站网页发起偷袭 → POST gameServerURL（server/referee/raid_intake.py → raid_create）→ 锁定双方本周阵容建裁判任务 →
--   裁判领到 ⇒ 发件箱 started → 算完 ⇒ 发件箱 settle（attacker / defender）；算不出 / 超时 / 没有阵容 ⇒ settle void。
-- 前提：20261109a_mainsite_core.sql（A1：mainsite_accounts / mainsite_pets / mainsite_outbox / mainsite_outbox_put）已执行。
--   ★本段只在函数体（plpgsql，执行时才解析表名）里用到那几样 ⇒ 建函数不依赖它们；周赛写回那条路另有异常兜底（见 ⑦）。
-- 本段（★总开关 raid_on 默认关、且只有 econ_on 也开着才生效 ⇒ 执行本段不改变任何现行行为）：
--   ① referee_jobs.kind 多一个 'raid'；referee_config 多一个 raid_on；raid_enabled() = raid_on 且 econ_on（§4.9）
--   ② raid_defense：每个号一行 = 本周最新的阵容快照（形状 = Backend.build_ghost_snapshot）+ 上次报给主站的状态
--      raid_defense_put（App）：只有本周已开轮（三统领齐、分路合法、p_week = 本周锚点）才存、才算 has_defense
--   ③ raid_rating = 本大轮已打场数（服务器记录：积分赛账本 + 闯关账本 + 周日决赛局），= pool_find_battles 用的那个数（§4.9）
--      raid_defense_report：已绑定的号状态变了（有没有阵容 / rating / 设备号）⇒ 发件箱 defense
--      raid_week_rollover：换周 ⇒ 上周报过「有阵容」的已绑定号一律报 hasDefense:false（pg_cron 每小时第 3 分钟，周一 00:03 UTC 起）
--   ④ raid_jobs + raid_create（主站建任务，只给 service_role）：raidId 幂等回同一 jobId；没绑定 / 没有本周阵容 / 阵容不合法 ⇒
--      不排裁判、直接 settle void；否则锁定双方快照建 kind = 'raid' 的裁判任务：
--      ★本周等级与装备以服务器记账为准（raid_lock_snapshot，§4.9「背包里没有的件、超上限的件这场不认」）：
--        等级 = econ_state 重放出的本周等级（没有这一行 = 1）；每件装备必须在账本里同一只身上（小将合在一起算），
--        单只 ≤ 3、全队 ≤ (等级 − 1) × 2（= phase2_config.gd UNIT_EQUIP_CAP / team_equip_cap），多出来的按顺序不认；
--        场次 = raid_rating；小木斧 / 宝箱 / 香火起点 = 重放结果（同 econ_check 比的那几样）
--      ★服务器的 owned（mainsite_pets）与账号只进任务 meta（a_owned / b_owned / a_account / b_account，裁判从任务单 key 读，
--        = 20261109b 领活盖章同一组键），不盖进快照 ⇒ 不跟着快照进 matches / 录像 / 直播
--   ⑨ matches 写入前摘掉快照里的 owned / account_id（兜底：任何一条路带进来都不外泄；matches 任何登录用户都读得到）
--   ⑤ referee_jobs 状态钩子（触发器）：raid 领到 ⇒ started；写回 ⇒ settle（a 赢 = attacker、b 赢 = defender）；
--      失败（拒算 / 次数用尽 / 超时）⇒ settle void；周赛局（积分赛 / 闯关 / 决赛）写回 ⇒ 双方 rating 重算、变了就报 defense
--   ⑥ raid_sweep：排队过了 expireAt 还没开算 ⇒ 不再算；开算 30 分钟没结果 ⇒ void。pg_cron 每分钟（领活本身也不领这两种）
--   ⑦ referee_claim：偷袭局排在闯关 / 决赛 / 积分赛后面领；过期的不领
--   ⑧ purge_old_matches：偷袭局录像留 30 天（周清跳过它）；raid_jobs 同样留 30 天
-- ★偷袭局不发任何东西：referee_complete 只有 finals / gauntlet / ranked 三支落账，raid 一支都不进 ⇒
--   不发深海币 / 宝箱 / 香火 / 小木斧经验 / 命运之轮 / 龟经验，不计本大轮场数（raid_rating 不数 raid 局），不进快照池（ghosts /
--   gauntlet_ghosts 不写）；只落一行 matches（phase = 'raid'，录像）。referee_complete 本身不改。
-- ★时间：周锚点按 app_now()（与积分赛同一口径，内测服假时钟跟着走）；expireAt / 30 分钟按真时间 now()（主站的钟）。
-- 回滚：raid_on = false；trigger raid_job_status / matches_strip_private 可 drop；referee_claim / purge_old_matches 换回 20261101d / 20261008 版。
-- ★重复执行安全（if not exists / create or replace / drop ... if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 任务种类 / 开关 ─────────────────────────────────────────
alter table public.referee_jobs drop constraint if exists referee_jobs_kind_check;
alter table public.referee_jobs add constraint referee_jobs_kind_check
  check (kind in ('gauntlet', 'finals', 'ranked', 'raid'));

alter table public.referee_config add column if not exists raid_on boolean not null default false;

-- 偷袭开着没有。★§4.9：押的是龟币，本周等级与装备必须以服务器记账为准 ⇒ raid_on 只有在 econ_on（记账总开关，
--   20261106b referee_econ_on()）也开着时才生效。判断只在这一处。
create or replace function public.raid_enabled() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.raid_on from public.referee_config c where c.id = 1), false) and public.referee_econ_on()
$$;
revoke all on function public.raid_enabled() from public, anon, authenticated;

-- 常量：开算后多久没结果就作废（= 主站 arena.raidTimeoutMinutes 默认 30）
create or replace function public.raid_compute_sec() returns int language sql immutable as $$ select 1800 $$;
revoke all on function public.raid_compute_sec() from public, anon, authenticated;

-- 本周锚点（周一 00:00 UTC 的 epoch 秒 = 客户端 week_anchor_ts；内测服跟假时钟）
create or replace function public.raid_week() returns bigint
language sql stable security definer set search_path = public as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
revoke all on function public.raid_week() from public, anon, authenticated;

-- 阵容能不能拿去偷袭 / 防守：本周已开轮 = 三统领齐、每只在两路里恰好一次（= 裁判左方的开打条件 referee_lineup_ok）。
--   ★两方都按左方的标准查（守方也必须已开轮，用户 11-08「对面也要是开轮状态才行吧」）。判断只在这一处。
create or replace function public.raid_snapshot_ok(p_snap jsonb) returns boolean
language plpgsql immutable as $$
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' or octet_length(p_snap::text) > 65536 then
    return false;
  end if;
  return public.referee_lineup_ok(p_snap);
end $$;
revoke all on function public.raid_snapshot_ok(jsonb) from public, anon, authenticated;

-- 主站用户 ID（对外编码：base62 字母数字串）；纯数字 = 内部 ID ⇒ 不收（主站方案 §6「纯数字或格式不对的一律 bad userId」）
create or replace function public.raid_user_ok(p text) returns boolean
language sql immutable as $$
  select p is not null and p ~ '^[A-Za-z0-9_-]{1,64}$' and p !~ '^[0-9]+$'
$$;
revoke all on function public.raid_user_ok(text) from public, anon, authenticated;

-- ② 防守阵容 ─────────────────────────────────────────────────
create table if not exists public.raid_defense (
  account_id   uuid        primary key references auth.users(id) on delete cascade,
  season_week  bigint      not null,                -- 这份快照是哪一周的（≠ 本周 ⇒ 没有阵容）
  snapshot     jsonb       not null,                -- Backend.build_ghost_snapshot 的产物（摘掉了客户端自带的 owned / account_id）
  device       text,                                -- 设备号（≤ 128；空 = 沿用上一次的）
  updated_at   timestamptz not null default now(),
  -- 上次报给主站（发件箱 defense）的状态：变了才再报；换周判据也看它
  rep_user     text,                                -- 报给的是哪个主站用户
  rep_has      boolean,
  rep_rating   int,
  rep_device   text,
  rep_seq      int         not null default 0,      -- 发件箱幂等键的序号（<主站用户>:<账号>:<序号>）
  rep_at       timestamptz
);
alter table public.raid_defense enable row level security;
-- 没有任何策略 ⇒ 客户端直连读写都不行（阵容 = 情报）；只走 raid_defense_put

-- 这个号本周有没有能用的阵容
create or replace function public.raid_has_defense(p_uid uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.raid_defense where account_id = p_uid;
  return found and d.season_week = public.raid_week() and public.raid_snapshot_ok(d.snapshot);
end $$;
revoke all on function public.raid_has_defense(uuid) from public, anon, authenticated;

-- ③ rating = 本大轮已打场数（服务器记录；§4.9 / 20261105c D17 的口径 = backend.gd pool_find_battles 的 season_total_battles）
--   = 积分赛（ranked_ledger_peek：有服务端账本读账本，没有读切换之前的最后一份）+ 闯关（gauntlet_records 胜 + 负）
--   + 周日决赛（本周算完的 finals 裁判局，我在任一侧）。★偷袭局不在里面（不计场数）。客户端 GameState.season_total_battles
--   在 _settle_season 的积分赛 / gauntlet_settle / finals_settle_sealed 三处 +1，与这三项一一对应。
create or replace function public.raid_rating(p_uid uuid, p_week bigint) returns int
language plpgsql stable security definer set search_path = public as $$
declare v_r int; v_g int; v_f int;
begin
  v_r := coalesce((public.ranked_ledger_peek(p_uid, p_week) ->> 'battles')::int, 0);
  select gw + gl into v_g from public.gauntlet_records where season_week = p_week and account_id = p_uid;
  select count(*)::int into v_f from public.referee_jobs
   where kind = 'finals' and season_week = p_week and status = 'done' and (a_account = p_uid or b_account = p_uid);
  return greatest(v_r, 0) + greatest(coalesce(v_g, 0), 0) + coalesce(v_f, 0);
end $$;
revoke all on function public.raid_rating(uuid, bigint) from public, anon, authenticated;

-- 把这个号现在的状态报给主站（发件箱 defense {userId, hasDefense, rating, device}）：已绑定 + 与上次报的不同才写。
--   p_force：不比较、直接报一次（A1 绑定成功后调，让主站拿到当前状态）。
--   ★从没存过阵容的号不报（主站那边默认就是没有阵容；删号时主站 unlinked 也会清掉）。
--   ★没部署 A1（没有 mainsite_accounts）⇒ 回 no_mainsite、什么都不写。
create or replace function public.raid_defense_report(p_uid uuid, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d record; wk bigint := public.raid_week(); v_msu text; v_has boolean; v_rating int; v_seq int;
begin
  if p_uid is null or to_regclass('public.mainsite_accounts') is null then
    return jsonb_build_object('ok', false, 'reason', 'no_mainsite', 'sent', false);
  end if;
  select * into d from public.raid_defense where account_id = p_uid for update;
  if not found then
    return jsonb_build_object('ok', true, 'has_defense', false, 'rating', 0, 'sent', false);
  end if;
  v_has := d.season_week = wk and public.raid_snapshot_ok(d.snapshot);
  v_rating := case when v_has then public.raid_rating(p_uid, wk) else 0 end;
  select m.mainsite_user_id into v_msu from public.mainsite_accounts m where m.account_id = p_uid;
  if v_msu is null then
    -- 解绑了（主站 unlinked 会清掉那边的阵容）⇒ 上次报的状态作废：以后重新绑定从头报，换周也不再挑它
    if d.rep_user is not null then
      update public.raid_defense set rep_user = null, rep_has = null, rep_rating = null, rep_device = null
       where account_id = p_uid;
    end if;
    return jsonb_build_object('ok', true, 'linked', false, 'has_defense', v_has, 'rating', v_rating, 'sent', false);
  end if;
  if not (coalesce(p_force, false)
          or (d.rep_user is not null and d.rep_user <> v_msu)
          or coalesce(d.rep_has, false) <> v_has
          or coalesce(d.rep_rating, 0) <> v_rating
          or (v_has and d.device is not null and d.device is distinct from d.rep_device)) then
    return jsonb_build_object('ok', true, 'linked', true, 'has_defense', v_has, 'rating', v_rating, 'sent', false);
  end if;
  v_seq := d.rep_seq + 1;
  perform public.mainsite_outbox_put('defense', format('%s:%s:%s', v_msu, p_uid, v_seq),
    jsonb_build_object('userId', v_msu, 'hasDefense', v_has, 'rating', v_rating, 'device', coalesce(d.device, '')));
  update public.raid_defense
     set rep_user = v_msu, rep_has = v_has, rep_rating = v_rating, rep_device = d.device, rep_seq = v_seq, rep_at = now()
   where account_id = p_uid;
  return jsonb_build_object('ok', true, 'linked', true, 'has_defense', v_has, 'rating', v_rating, 'sent', true);
end $$;
revoke all on function public.raid_defense_report(uuid, boolean) from public, anon, authenticated;
grant execute on function public.raid_defense_report(uuid, boolean) to service_role;

-- App 存当前号这一周的最新阵容（B：离开背包 / 选龟页、每打完一局上传快照时）。回 {ok, has_defense}。
--   ★只有本周已开轮才存：p_week ≠ 本周锚点 ⇒ wrong_week；三统领不齐 / 分路坏 ⇒ 不存、不动已存的那份（stored:false）。
--   ★客户端快照里自带的 owned / account_id 一律摘掉（拥有以服务器 mainsite_pets 为准，建任务时由服务端盖上）。
--   ★报给主站那一步出错不影响存阵容（异常兜住，下一次存 / 下一局写回会再报）。
create or replace function public.raid_defense_put(p_week bigint, p_snapshot jsonb, p_device text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); wk bigint := public.raid_week(); v_dev text; v_snap jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in', 'has_defense', false);
  end if;
  if p_week is distinct from wk then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week', 'has_defense', public.raid_has_defense(uid));
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot', 'has_defense', public.raid_has_defense(uid));
  end if;
  v_snap := p_snapshot - 'owned' - 'account_id';
  if not public.raid_snapshot_ok(v_snap) then
    return jsonb_build_object('ok', true, 'stored', false, 'reason', 'not_open', 'has_defense', public.raid_has_defense(uid));
  end if;
  v_dev := nullif(left(btrim(coalesce(p_device, '')), 128), '');
  insert into public.raid_defense (account_id, season_week, snapshot, device, updated_at)
    values (uid, wk, v_snap, v_dev, now())
    on conflict (account_id) do update
      set season_week = excluded.season_week, snapshot = excluded.snapshot,
          device = coalesce(excluded.device, public.raid_defense.device), updated_at = now();
  begin
    perform public.raid_defense_report(uid);
  exception when others then
    raise warning 'raid_defense_put: 报主站失败（阵容已存）: %', sqlerrm;
  end;
  return jsonb_build_object('ok', true, 'stored', true, 'has_defense', true);
end $$;
revoke all on function public.raid_defense_put(bigint, jsonb, text) from public, anon;
grant execute on function public.raid_defense_put(bigint, jsonb, text) to authenticated;

-- 换周：上周报过「有阵容」（或 rating 不是 0）的号重报一次 —— 快照不是本周的 ⇒ hasDefense:false、rating 0。
--   §4.2「周一 00:00 UTC 换周时给所有已绑定玩家经发件箱报 hasDefense:false」：从没报过有阵容的号主站那边本来就是 false，
--   不重复报；本周第一次开打（App 存阵容）后由 raid_defense_put 报回 true。
--   触发：pg_cron 'raid_week_rollover' 每小时第 3 分钟（周一 00:03 UTC 第一次生效；之后每小时一次是兜底 / 内测服假时钟）。幂等。
create or replace function public.raid_week_rollover() returns int
language plpgsql security definer set search_path = public as $$
declare wk bigint := public.raid_week(); r record; n int := 0; x jsonb;
begin
  for r in select d.account_id from public.raid_defense d
            where d.season_week < wk and (coalesce(d.rep_has, false) or coalesce(d.rep_rating, 0) <> 0)
            order by d.account_id loop
    x := public.raid_defense_report(r.account_id);
    if coalesce((x ->> 'sent')::boolean, false) then
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.raid_week_rollover() from public, anon, authenticated;
grant execute on function public.raid_week_rollover() to service_role;
select cron.unschedule(jobid) from cron.job where jobname = 'raid_week_rollover';
select cron.schedule('raid_week_rollover', '3 * * * *', 'select public.raid_week_rollover()');

-- ④ 偷袭任务 ─────────────────────────────────────────────────
create table if not exists public.raid_jobs (
  id               bigint      generated always as identity primary key,   -- = 回给主站的 jobId（字符串）
  raid_id          bigint      not null unique,                            -- 主站 raidId（幂等键）
  attacker         text        not null,                                   -- 主站用户 ID（对外编码）
  defender         text        not null,
  attacker_account uuid        references auth.users(id) on delete set null,
  defender_account uuid        references auth.users(id) on delete set null,
  seed             bigint      not null default 0,                         -- 主站给的原值（裁判实际用的在 referee_jobs.seed）
  stake            bigint      not null default 0,                         -- 只记录（App 里不显示任何金额）
  is_revenge       boolean     not null default false,                     -- 只记录（不做复仇，用户 11-08）
  expire_at        timestamptz not null,                                   -- 主站 expireAt：过了还没开算就不再算
  season_week      bigint      not null,
  status           text        not null default 'queued' check (status in ('queued', 'started', 'done', 'void')),
  reason           text,                                                   -- void 的原因（attacker_unlinked / defender_no_defense / raid_timeout …）
  a_snapshot       jsonb,                                                  -- 建任务那一刻锁定的攻方阵容（= 裁判任务的 a：已按记账改写，不含 owned）
  b_snapshot       jsonb,                                                  -- 守方（= b）
  a_owned          jsonb,                                                  -- 攻方拥有的龟（mainsite_pets 的 pet_key）
  b_owned          jsonb,
  referee_job_id   bigint      references public.referee_jobs(job_id) on delete set null,
  match_id         uuid,                                                   -- = 录像 id = settle 的 matchId
  result           text        check (result in ('attacker', 'defender', 'void')),
  created_at       timestamptz not null default now(),
  started_at       timestamptz,                                            -- 裁判第一次领到（= 发 started 的那一刻）
  settled_at       timestamptz
);
create index if not exists raid_jobs_job_idx on public.raid_jobs (referee_job_id);
create index if not exists raid_jobs_open_idx on public.raid_jobs (status) where status in ('queued', 'started');
alter table public.raid_jobs enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行

-- 偷袭用哪个版本算：裁判机装了、开着的最新版本（两边快照都是数据，规则以算它的版本为准；同周赛 referee_versions 那张表）
create or replace function public.raid_pick_version() returns text
language sql stable security definer set search_path = public as $$
  select v.client_version from public.referee_versions v
   where v.enabled and public.semver_arr(v.client_version) is not null
   order by public.semver_arr(v.client_version) desc limit 1
$$;
revoke all on function public.raid_pick_version() from public, anon, authenticated;

-- 作废一场：记 void；p_send ⇒ 发件箱 settle {raidId, result:'void', matchId:''}
create or replace function public.raid_void(p_id bigint, p_reason text, p_send boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  update public.raid_jobs
     set status = 'void', result = 'void', reason = left(coalesce(p_reason, '?'), 200), settled_at = now()
   where id = p_id and status in ('queued', 'started')
  returning * into r;
  if found and coalesce(p_send, true) then
    perform public.mainsite_outbox_put('settle', r.raid_id::text,
      jsonb_build_object('raidId', r.raid_id, 'result', 'void', 'matchId', ''));
  end if;
end $$;
revoke all on function public.raid_void(bigint, text, boolean) from public, anon, authenticated;

-- 装备上限（= phase2_config.gd：UNIT_EQUIP_CAP 3；team_equip_cap(等级) = (clamp(等级, 1, MAX_LEVEL 10) − 1) × 2）。
--   ★两边各一份 ⇒ 检查脚本 L0 把这里的 0 ~ 11 级钉成一张字面表，tests/verify_raid_private_fields.gd 拿同一张表对 GDScript。
create or replace function public.raid_unit_equip_cap() returns int language sql immutable as $$ select 3 $$;
revoke all on function public.raid_unit_equip_cap() from public, anon, authenticated;
create or replace function public.raid_team_equip_cap(p_lv int) returns int language sql immutable as $$
  select greatest(0, (least(greatest(coalesce(p_lv, 1), 1), 10) - 1) * 2)
$$;
revoke all on function public.raid_team_equip_cap(int) from public, anon, authenticated;

-- 一件装备的比对键「id|星」（= econ_items_key 的口径：星缺 = 1、按整数比）；不是对象 / 没有 id / 星不是数 ⇒ null（这件不认）
create or replace function public.raid_item_key(p_it jsonb) returns text language sql immutable as $$
  select case when jsonb_typeof(p_it) = 'object' and coalesce(p_it ->> 'id', '') <> ''
                   and (not (p_it ? 'star') or jsonb_typeof(p_it -> 'star') = 'number')
              then (p_it ->> 'id') || '|' || coalesce(round((p_it ->> 'star')::numeric)::int, 1)::text end
$$;
revoke all on function public.raid_item_key(jsonb) from public, anon, authenticated;

-- 一组装备 ⇒ {键: 件数}
create or replace function public.raid_item_counts(p_items jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
    from (select public.raid_item_key(x) as k, count(*)::int as n
            from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) x
           group by 1) t
   where k is not null
$$;
revoke all on function public.raid_item_counts(jsonb) from public, anon, authenticated;

-- ★锁定快照：本周等级与装备改成服务器记账（econ_state，裁判机按流水重放的结果；§4.9 / 20261106 §4.5）。
--   等级：econ_state.assets.lv（没有这一行 = 本周还没有任何流水 = 1；快照自报的不认）
--   装备：统领每件必须在账本里这只身上（assets.worn[龟]，按件数扣）；小将每件必须在账本里某只小将身上（assets.minions 合起来按件数扣，
--         小将之间换位不算错）；单只 ≤ raid_unit_equip_cap、全队 ≤ raid_team_equip_cap(等级)；
--         不认的件直接拿掉；超上限按「统领按 leaders 顺序 → 上路小将 → 下路小将、每只按快照里的顺序」先到先留
--   场次：season_total_battles = raid_rating（援军小将按场次成长，同 ranked_stamp_snapshot）
--   小木斧 / 宝箱 / 香火：= 重放结果（同 econ_check 比的键；没有这一行 = 本周起点 0 / 空）
--   其余（阵容、站位、技能、大师、头像名字）原样；owned / account_id 摘掉。
--   ★不看 econ_on（开关在 raid_enabled 一处）；econ_state 有不合法的一条（bad_at ≥ 0）时 assets 是合法前缀的结果，照用。
create or replace function public.raid_lock_snapshot(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.econ_state%rowtype; v_a jsonb := '{}'::jsonb; v_p jsonb := '{}'::jsonb; v_lv int; v_cap int;
        v_unit int := public.raid_unit_equip_cap(); v_used int := 0; v_out jsonb; v_pid text; v_avail jsonb; v_pool jsonb;
        v_kept jsonb; v_eq jsonb := '{}'::jsonb; v_it jsonb; v_k text; v_lane text; v_m jsonb; v_new jsonb; v_mins jsonb := '{}'::jsonb;
        v_mlist jsonb := '[]'::jsonb;
begin
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  if found then
    v_a := case when jsonb_typeof(s.assets) = 'object' then s.assets else '{}'::jsonb end;
    v_p := case when jsonb_typeof(s.progress) = 'object' then s.progress else '{}'::jsonb end;
  end if;
  v_lv := least(greatest(coalesce(case when jsonb_typeof(v_a -> 'lv') = 'number' then round((v_a ->> 'lv')::numeric)::int end, 1), 1), 10);
  v_cap := public.raid_team_equip_cap(v_lv);
  v_out := (p_snap - 'owned' - 'account_id') || jsonb_build_object('season_level', v_lv,
    'season_total_battles', public.raid_rating(p_uid, p_week),
    'axe_exp_total', coalesce(case when jsonb_typeof(v_a -> 'axe' -> 1) = 'number' then round((v_a -> 'axe' ->> 1)::numeric)::int end, 0),
    'axe_stage', coalesce(case when jsonb_typeof(v_a -> 'axe' -> 2) = 'number' then round((v_a -> 'axe' ->> 2)::numeric)::int end, 0),
    'axe_final', coalesce(v_a -> 'axe' ->> 3, ''),
    'chest_treasure_value', coalesce(case when jsonb_typeof(v_p -> 'cv') = 'number' then v_p -> 'cv' end, '0'::jsonb),
    'chest_treasures_won', coalesce(case when jsonb_typeof(v_p -> 'cw') = 'array' then v_p -> 'cw' end, '[]'::jsonb),
    'incense_marks', coalesce(case when jsonb_typeof(v_p -> 'im') = 'number' then round((v_p ->> 'im')::numeric)::int end, 0),
    'incense_charge', coalesce(case when jsonb_typeof(v_p -> 'ic') = 'number' then round((v_p ->> 'ic')::numeric)::int end, 0));
  -- 统领
  for v_pid in select x from jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array'
                                                            then p_snap -> 'leaders' else '[]'::jsonb end) with ordinality t(x, i)
                order by i loop
    continue when v_eq ? v_pid;
    v_avail := public.raid_item_counts(v_a -> 'worn' -> v_pid);
    v_kept := '[]'::jsonb;
    for v_it in select x from jsonb_array_elements(case when jsonb_typeof(p_snap -> 'equipped' -> v_pid) = 'array'
                                                        then p_snap -> 'equipped' -> v_pid else '[]'::jsonb end) with ordinality t(x, i)
                 order by i loop
      v_k := public.raid_item_key(v_it);
      if v_k is not null and coalesce((v_avail ->> v_k)::int, 0) > 0 and jsonb_array_length(v_kept) < v_unit and v_used < v_cap then
        v_kept := v_kept || jsonb_build_array(v_it || jsonb_build_object('star', (regexp_match(v_k, '[|](-?[0-9]+)$'))[1]::int));
        v_avail := v_avail || jsonb_build_object(v_k, (v_avail ->> v_k)::int - 1);
        v_used := v_used + 1;
      end if;
    end loop;
    if jsonb_array_length(v_kept) > 0 then
      v_eq := v_eq || jsonb_build_object(v_pid, v_kept);
    end if;
  end loop;
  v_out := v_out || jsonb_build_object('equipped', v_eq);
  -- 小将：账本里全部小将身上的件合成一个池（assets.minions = 每只一个 JSON 串 {"eq": [...], "lv": n}）
  for v_m in select case when jsonb_typeof(x) = 'string' then (x #>> '{}')::jsonb else x end
               from jsonb_array_elements(case when jsonb_typeof(v_a -> 'minions') = 'array' then v_a -> 'minions' else '[]'::jsonb end) x loop
    if jsonb_typeof(v_m) = 'object' and jsonb_typeof(v_m -> 'eq') = 'array' then
      v_mlist := v_mlist || (v_m -> 'eq');
    end if;
  end loop;
  v_pool := public.raid_item_counts(v_mlist);
  if jsonb_typeof(p_snap -> 'minions') = 'object' then
    for v_lane in select key from jsonb_each(p_snap -> 'minions') order by (key <> 'top'), (key <> 'bottom'), key loop
      v_new := '[]'::jsonb;
      for v_m in select x from jsonb_array_elements(case when jsonb_typeof(p_snap -> 'minions' -> v_lane) = 'array'
                                                         then p_snap -> 'minions' -> v_lane else '[]'::jsonb end) with ordinality t(x, i)
                  order by i loop
        if jsonb_typeof(v_m) = 'object' and v_m ? 'equips' then
          v_kept := '[]'::jsonb;
          for v_it in select x from jsonb_array_elements(case when jsonb_typeof(v_m -> 'equips') = 'array'
                                                              then v_m -> 'equips' else '[]'::jsonb end) with ordinality t(x, i)
                       order by i loop
            v_k := public.raid_item_key(v_it);
            if v_k is not null and coalesce((v_pool ->> v_k)::int, 0) > 0 and jsonb_array_length(v_kept) < v_unit and v_used < v_cap then
              v_kept := v_kept || jsonb_build_array(v_it || jsonb_build_object('star', (regexp_match(v_k, '[|](-?[0-9]+)$'))[1]::int));
              v_pool := v_pool || jsonb_build_object(v_k, (v_pool ->> v_k)::int - 1);
              v_used := v_used + 1;
            end if;
          end loop;
          v_m := v_m || jsonb_build_object('equips', v_kept);
        end if;
        v_new := v_new || jsonb_build_array(v_m);
      end loop;
      v_mins := v_mins || jsonb_build_object(v_lane, v_new);
    end loop;
    v_out := v_out || jsonb_build_object('minions', v_mins);
  end if;
  return v_out;
end $$;
revoke all on function public.raid_lock_snapshot(uuid, bigint, jsonb) from public, anon, authenticated;

-- 主站建任务（raid_intake.handle_create 调；只给 service_role）。回 {ok:true, jobId} / {ok:false, error}。
--   ok:false（主站立即作废退回）：bad_raidId / bad_userId / same_user / raid_conflict（同 raidId 双方不同）/ raid_off / expired / no_referee
--   ok:true 但直接 void（不排裁判，settle void 入发件箱）：attacker_unlinked / defender_unlinked /
--     attacker_no_defense / defender_no_defense（没有本周阵容 = 没开轮 / 快照是上周的 / 阵容不合法）
--   ★同 raidId 重发：不看开关、不看过期，直接回同一个 jobId（主站重发的是同一场）。
--   ★种子：主站给的 1 ~ 2^53-1 原样用（两边都能复算）；0 / 超界 ⇒ 服务端生成。
create or replace function public.raid_create(p_raid_id bigint, p_attacker text, p_defender text, p_seed bigint,
    p_stake bigint, p_is_revenge boolean, p_expire_at bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ex record; v_id bigint; wk bigint; v_now_ms bigint; ua uuid; ud uuid; da record; dd record; v_reason text;
        v_ver text; v_own_a jsonb; v_own_b jsonb; v_snap_a jsonb; v_snap_b jsonb; jid bigint; mid uuid; v_seed bigint;
begin
  if p_raid_id is null or p_raid_id <= 0 then
    return jsonb_build_object('ok', false, 'error', 'bad_raidId');
  end if;
  if not public.raid_user_ok(p_attacker) or not public.raid_user_ok(p_defender) then
    return jsonb_build_object('ok', false, 'error', 'bad_userId');
  end if;
  if p_attacker = p_defender then
    return jsonb_build_object('ok', false, 'error', 'same_user');
  end if;
  select * into ex from public.raid_jobs where raid_id = p_raid_id;
  if found then
    if ex.attacker <> p_attacker or ex.defender <> p_defender then
      return jsonb_build_object('ok', false, 'error', 'raid_conflict');
    end if;
    return jsonb_build_object('ok', true, 'jobId', ex.id::text);
  end if;
  if not public.raid_enabled() then
    return jsonb_build_object('ok', false, 'error', 'raid_off');
  end if;
  v_now_ms := floor(extract(epoch from now()) * 1000)::bigint;
  if p_expire_at is null or p_expire_at <= v_now_ms then
    return jsonb_build_object('ok', false, 'error', 'expired');
  end if;
  v_ver := public.raid_pick_version();
  if v_ver is null then
    return jsonb_build_object('ok', false, 'error', 'no_referee');
  end if;
  wk := public.raid_week();
  select m.account_id into ua from public.mainsite_accounts m where m.mainsite_user_id = p_attacker;
  select m.account_id into ud from public.mainsite_accounts m where m.mainsite_user_id = p_defender;
  if ua is null then
    v_reason := 'attacker_unlinked';
  elsif ud is null then
    v_reason := 'defender_unlinked';
  else
    select * into da from public.raid_defense where account_id = ua;
    select * into dd from public.raid_defense where account_id = ud;
    if da.account_id is null or da.season_week <> wk or not public.raid_snapshot_ok(da.snapshot) then
      v_reason := 'attacker_no_defense';
    elsif dd.account_id is null or dd.season_week <> wk or not public.raid_snapshot_ok(dd.snapshot) then
      v_reason := 'defender_no_defense';
    end if;
  end if;
  insert into public.raid_jobs (raid_id, attacker, defender, attacker_account, defender_account, seed, stake, is_revenge,
      expire_at, season_week)
    values (p_raid_id, p_attacker, p_defender, ua, ud, coalesce(p_seed, 0), coalesce(p_stake, 0), coalesce(p_is_revenge, false),
      to_timestamp(p_expire_at / 1000.0), wk)
    on conflict (raid_id) do nothing
    returning id into v_id;
  if v_id is null then
    -- 同一刻另一个请求先建了（主站超时重发）：回先到的那一个
    select * into ex from public.raid_jobs where raid_id = p_raid_id;
    if ex.attacker <> p_attacker or ex.defender <> p_defender then
      return jsonb_build_object('ok', false, 'error', 'raid_conflict');
    end if;
    return jsonb_build_object('ok', true, 'jobId', ex.id::text);
  end if;
  if v_reason is not null then
    perform public.raid_void(v_id, v_reason);
    return jsonb_build_object('ok', true, 'jobId', v_id::text);
  end if;
  select coalesce(jsonb_agg(p.pet_key order by p.pet_key), '[]'::jsonb) into v_own_a from public.mainsite_pets p where p.account_id = ua;
  select coalesce(jsonb_agg(p.pet_key order by p.pet_key), '[]'::jsonb) into v_own_b from public.mainsite_pets p where p.account_id = ud;
  -- 锁定：本周那份快照，等级 / 装备 / 场次 / 小木斧宝箱香火改成服务器记账（raid_lock_snapshot）。
  --   服务器的 owned / 账号只进 meta（= 20261109b 领活盖章的 a_owned / b_owned / a_account / b_account；裁判从 key 读），
  --   ★不盖进快照：快照会原样进 matches 与录像（任何登录用户都读得到）。
  v_snap_a := public.raid_lock_snapshot(ua, wk, da.snapshot);
  v_snap_b := public.raid_lock_snapshot(ud, wk, dd.snapshot);
  v_seed := case when p_seed between 1 and 9007199254740991 then p_seed else public.referee_new_seed() end;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('raid', format('raid:%s', p_raid_id), wk, v_ver, v_seed, ua, ud, v_snap_a, v_snap_b,
      public.referee_level_of(v_snap_a),
      jsonb_build_object('raid_id', p_raid_id, 'attacker', p_attacker, 'defender', p_defender,
                         'account', ua, 'b_account', ud, 'expire_ms', p_expire_at,
                         'a_account', ua, 'a_owned', v_own_a, 'b_owned', v_own_b))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    select job_id, match_id into jid, mid from public.referee_jobs where match_key = format('raid:%s', p_raid_id);
  end if;
  update public.raid_jobs
     set referee_job_id = jid, match_id = mid, a_snapshot = v_snap_a, b_snapshot = v_snap_b, a_owned = v_own_a, b_owned = v_own_b
   where id = v_id;
  return jsonb_build_object('ok', true, 'jobId', v_id::text);
end $$;
revoke all on function public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint) from public, anon, authenticated;
grant execute on function public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint) to service_role;

-- ⑤ 裁判任务状态变了 ⇒ 偷袭的 started / settle、周赛的 rating ─────────
-- 一场偷袭对应的裁判任务：领到（claimed）⇒ started（只第一次；重领不再发）；写回（done）⇒ settle attacker / defender；
--   失败（failed）⇒ void（排队过期 raid_expired 不发 settle：主站到点自己作废退回，迟到的 settle 主站也不认）。
--   ★结果单的 winner 是唯一依据（a = 攻方 = attacker）；裁判另带的 raid_result 与它对不上 ⇒ void（不赌哪一个对）。
create or replace function public.raid_on_job(p_job_id bigint, p_status text, p_error text, p_result jsonb, p_match_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_res text;
begin
  select * into r from public.raid_jobs where referee_job_id = p_job_id for update;
  if not found or r.status in ('done', 'void') then
    return;
  end if;
  if p_status = 'claimed' then
    if r.status = 'queued' then
      update public.raid_jobs set status = 'started', started_at = now() where id = r.id;
      perform public.mainsite_outbox_put('started', r.raid_id::text, jsonb_build_object('raidId', r.raid_id));
    end if;
  elsif p_status = 'done' then
    v_res := case p_result ->> 'winner' when 'a' then 'attacker' when 'b' then 'defender' end;
    if v_res is null or (p_result ? 'raid_result' and p_result ->> 'raid_result' is distinct from v_res) then
      perform public.raid_void(r.id, 'bad_result');
      return;
    end if;
    update public.raid_jobs set status = 'done', result = v_res, match_id = p_match_id, settled_at = now() where id = r.id;
    perform public.mainsite_outbox_put('settle', r.raid_id::text,
      jsonb_build_object('raidId', r.raid_id, 'result', v_res, 'matchId', p_match_id::text));
  elsif p_status = 'failed' then
    perform public.raid_void(r.id, coalesce(p_error, 'failed'), coalesce(p_error, '') <> 'raid_expired');
  end if;
end $$;
revoke all on function public.raid_on_job(bigint, text, text, jsonb, uuid) from public, anon, authenticated;

-- 触发器本体。两支都兜在异常里：
--   周赛那一支：报主站出任何问题都不许拖垮周赛记账（referee_complete 的事务）。
--   偷袭那一支：发件箱写不进（A1 那边出问题）不许拖垮领活 —— referee_claim 的租期回收会一次改多行（含周赛局），
--     这里一抛异常整个领活就失败、周赛局也领不走。丢的那一条 started / settle 由主站超时作废兜底（各退各的，钱不会错）。
create or replace function public.raid_job_status_hook() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'raid' then
    begin
      perform public.raid_on_job(new.job_id, new.status, new.error, new.result, new.match_id);
    exception when others then
      raise warning 'raid_job_status_hook: 偷袭 job=% status=% 没记上（主站会超时作废）: %', new.job_id, new.status, sqlerrm;
    end;
  elsif new.status = 'done' and new.kind in ('ranked', 'gauntlet', 'finals') then
    begin
      if new.a_account is not null then
        perform public.raid_defense_report(new.a_account);
      end if;
      if new.b_account is not null and (new.kind = 'finals' or coalesce(new.meta ->> 'pair', '') = 'true') then
        perform public.raid_defense_report(new.b_account);
      end if;
    exception when others then
      raise warning 'raid_job_status_hook: rating 没报出去（不影响周赛记账）: %', sqlerrm;
    end;
  end if;
  return null;
end $$;
revoke all on function public.raid_job_status_hook() from public, anon, authenticated;
drop trigger if exists raid_job_status on public.referee_jobs;
create trigger raid_job_status after update of status on public.referee_jobs
  for each row when (old.status is distinct from new.status) execute function public.raid_job_status_hook();

-- ⑥ 过期 / 超时 ─────────────────────────────────────────────
-- ① 还没开算（queued）就过了 expireAt ⇒ 任务记 failed raid_expired（不再算；钩子记 void、不发 settle）
-- ② 开算后 raid_compute_sec（30 分钟）还没写回 ⇒ failed raid_timeout（钩子记 void、发 settle void）；迟到的写回 not_owner 被拒
create or replace function public.raid_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare n1 int; n2 int;
begin
  update public.referee_jobs j
     set status = 'failed', error = 'raid_expired', done_at = now(), claimed_by = null, claimed_at = null
    from public.raid_jobs r
   where r.referee_job_id = j.job_id and r.status = 'queued' and r.expire_at <= now()
     and j.kind = 'raid' and j.status = 'pending';
  get diagnostics n1 = row_count;
  update public.referee_jobs j
     set status = 'failed', error = 'raid_timeout', done_at = now(), claimed_by = null, claimed_at = null
    from public.raid_jobs r
   where r.referee_job_id = j.job_id and r.status = 'started'
     and r.started_at <= now() - make_interval(secs => public.raid_compute_sec())
     and j.kind = 'raid' and j.status in ('pending', 'claimed');
  get diagnostics n2 = row_count;
  return n1 + n2;
end $$;
revoke all on function public.raid_sweep() from public, anon, authenticated;
grant execute on function public.raid_sweep() to service_role;
select cron.unschedule(jobid) from cron.job where jobname = 'raid_sweep';
select cron.schedule('raid_sweep', '* * * * *', 'select public.raid_sweep()');

-- ⑦ 领活（以 20261101d 版为底，只改两处，标了「2026-11-09 偷袭」）：
--   ① 偷袭局：还在排队且没过 expireAt，或已开算且没满 30 分钟，才领（过期 / 超时的由 raid_sweep 每分钟收成 failed）
--   ② order by 最前面多一项 (kind = 'raid')：偷袭排在闯关 / 决赛 / 积分赛后面（false 在前；没有偷袭局时排序结果逐字不变）
--   ★领活这条热路径上不加写（raid_sweep 不在这里跑）：多个裁判并发领活时不多一处行锁。
create or replace function public.referee_claim(p_worker text, p_versions text[], p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_out jsonb;
begin
  select * into cfg from public.referee_config where id = 1;
  insert into public.referee_workers (worker, versions, seen_at) values (p_worker, coalesce(p_versions, '{}'), now())
    on conflict (worker) do update set versions = excluded.versions, seen_at = now();
  update public.referee_jobs
     set status = 'failed', error = coalesce(error, 'lease_expired'), done_at = now()
   where status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)
     and attempts >= cfg.max_attempts;
  with c as (
    select job_id from public.referee_jobs
     where client_version = any(coalesce(p_versions, '{}'))
       and (status = 'pending'
            or (status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)))
       -- 2026-11-09 偷袭 ①
       and (kind <> 'raid' or exists (select 1 from public.raid_jobs r where r.referee_job_id = referee_jobs.job_id
              and ((r.status = 'queued' and r.expire_at > now())
                   or (r.status = 'started' and r.started_at > now() - make_interval(secs => public.raid_compute_sec())))))
     order by (kind = 'raid'),   -- 2026-11-09 偷袭 ②
              (kind = 'ranked' and exists (select 1 from public.bot_accounts b where b.account_id = a_account)),
              created_at, job_id
     limit greatest(1, least(coalesce(p_limit, 1), 32))
     for update skip locked
  ), u as (
    update public.referee_jobs j
       set status = 'claimed', claimed_by = p_worker, claimed_at = now(), attempts = j.attempts + 1
      from c where j.job_id = c.job_id
    returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'v', 1, 'job_id', u.job_id, 'match_id', u.match_id, 'mode', u.kind,
           'key', u.meta || jsonb_build_object('week', u.season_week, 'match_key', u.match_key),
           'seed', u.seed, 'client_version', u.client_version, 'level', u.level,
           'a', u.a_snapshot, 'b', u.b_snapshot) order by u.job_id), '[]'::jsonb)
    into v_out from u;
  return v_out;
end $$;
revoke all on function public.referee_claim(text, text[], int) from public, anon, authenticated;
grant execute on function public.referee_claim(text, text[], int) to service_role;

-- ⑧ 周清（以 20261008 版为底）：偷袭局录像留 30 天（主站「看录像」要用；20261107 §4.5），不随周清删；raid_jobs 同样留 30 天。
--   其余三行逐字不动（cron 'purge_old_matches' '0 0 * * 2' 不变）。
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC'
    and phase <> 'raid';
  delete from public.matches where phase = 'raid' and created_at < now() - interval '30 days';
  delete from public.raid_jobs where created_at < now() - interval '30 days';
  delete from public.live_matches where started_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
  delete from public.gauntlet_ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;

-- ⑨ matches 写入前摘私有字段（兜底）：快照里的 owned（拥有的龟）/ account_id 不进 matches。
--   matches 任何登录用户都读得到（matches_read_all）；偷袭局的拥有与账号只该在任务单里（raid_create 已不往快照里盖，
--   这一道管的是任何别的路 —— 旧任务、以后谁又往快照里塞 —— 带进来的）。客户端快照本来就没有这两个键 ⇒ 对它们一字不变。
create or replace function public.matches_strip_private() returns trigger
language plpgsql as $$
begin
  if jsonb_typeof(new.left_snapshot) = 'object' then
    new.left_snapshot := new.left_snapshot - 'owned' - 'account_id';
  end if;
  if jsonb_typeof(new.right_snapshot) = 'object' then
    new.right_snapshot := new.right_snapshot - 'owned' - 'account_id';
  end if;
  return new;
end $$;
revoke all on function public.matches_strip_private() from public, anon, authenticated;
drop trigger if exists matches_strip_private on public.matches;
create trigger matches_strip_private before insert or update of left_snapshot, right_snapshot on public.matches
  for each row execute function public.matches_strip_private();
-- <<< END raid 20261109c <<<
