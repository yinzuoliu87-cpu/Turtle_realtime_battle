-- >>> BEGIN ranked_referee 20261101d >>>
-- ─────────────────────────────────────────────────────────────
-- 积分赛交给服务器：服务端挑对手 + 裁判机算 + 服务端记账（2026-11-01 · 方案书 docs/plans/20261101c-积分赛服务器裁判.md ·
--   母方案书 docs/plans/20261019-服务器裁判.md §3 ③）
--   用户 10-19「我们的所有对局不应该在本机上吧，应该放服务器上吧，其他游戏怎么做的」；
--   用户 11-01「我就问你一句话：哪个商业游戏是这么本地做的？你见过吗？」
--   改之前：积分赛本机挑对手（Backend.find_opponent）、本机算、本机结算（RealtimeBattle3DScene._settle_season），
--     再由客户端直接写 ghosts（带自报的 season_wins / hearts）与 matches；周榜直接读快照自报 ⇒ 改客户端就能改成绩。
-- 本段（★全部有开关，开关默认关 ⇒ 执行本段不改变任何现行行为）：
--   ① referee_jobs.kind 多一个 'ranked'；referee_config 多三个开关：
--      ranked_on（默认关：服务端收不收积分赛裁判局）/ ranked_any_day（内测服彩排：不限周二~周五）/
--      ranked_client_write（默认开：客户端还能不能直接写积分赛 ghosts / matches —— 切换的最后一步才关）
--   ② ranked_records：服务端积分赛账本（每人每周一行：场次 / 胜 / 余命 / 横扫 / 碎蛋 / 配额 / 累计发币），客户端只能读自己那一行
--   ③ ranked_pool：内置陪练（data/ghost_seed.json，客户端池子里那 396 份）+ 兜底机器人（Backend.make_bot 同一个函数离线生成），
--      按规则版本存；只有 service_role 写（轮询器 referee_poller.py --bot-pool）
--   ④ referee_ranked_pick：挑对手 —— 规则原样搬自客户端 Backend.find_opponent / pool_find_battles：
--      本周同规则版本、**场次完全相同**（D5，没有 ±N）、不是自己、分路没坏、以快照自报的场次为准、排除本周已碰过的那一份；
--      真人快照与内置陪练放在一起**等概率**抽一份（用户 10-08「抽签范围扩大到全部同场次」）；一份都没有 ⇒ 机器人（D5 唯一的回落）
--   ⑤ referee_ranked_start（客户端开战）：交「我的阵容 + 我要打第 N 场」；对手、种子都由服务端定；
--      闸 = 客户端开局闸（主菜单 _battle_block_msg + 选龟 can_start_match_utc）在服务端的同一份：
--      积分赛时段（周二 00:00 ~ 周五 23:00 − 600 秒封盘，UTC）/ 没出局（余命 > 0）/ 配额没满（< 16）
--   ⑥ referee_complete 多一支 'ranked'：结算规则原样搬自 _settle_season 积分赛那一支（输 −1 命；
--      币 = 8 + 余命 + 2×已失命 + 胜 6 + 战斗内铸币；出局那一局 0 币；场次 +1、配额 +1；赢 ⇒ 胜 +1、碎蛋 +1、2-0 ⇒ 横扫 +1），
--      记账本 + 以服务端的数写 ghosts（快照池 / 周榜 / 闯关资格都读它）+ 落 matches（录像）
--   ⑦ referee_job_status 积分赛局多回 kind / ranked（账本快照）/ seed（开算后，跟播用）；referee_ranked_ledger 读自己的账
--   ⑧ week_leaderboard / week_leaderboard_page：有账本的人一律按账本排（不再信快照自报）；没账本的（切换之前的自报）照旧
--   ⑨ ghosts 写策略、matches 写策略（phase = 'ranked'）加 ranked_client_write 闸 —— 关掉它 = 客户端再也写不进积分赛成绩
--   ⑩ referee_claim：真人的积分赛局先算，陪练号的积分赛局排在后面（周末没有积分赛局 ⇒ 周六周日顺序逐字不变）
--   ⑪ referee_flags 多回 ranked_on
-- 上线顺序（每一步不过就停；方案书 §4.7）：迁移（开关全关）→ 裁判机装新版本 + --bot-pool（含积分赛池）→ 新客户端发出 →
--   min_client_version 抬到新版本 → 周一（休赛日）ranked_on = true → 观察一周期 → ranked_client_write = false
-- 回滚：ranked_on = false（客户端回本机那一路）；ranked_client_write = true；函数换回 20261027 / 20261024b 版；新表留着无害。
-- ★重复执行安全（if not exists / create or replace / drop constraint if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 任务种类 / 开关 ─────────────────────────────────────────
alter table public.referee_jobs drop constraint if exists referee_jobs_kind_check;
alter table public.referee_jobs add constraint referee_jobs_kind_check
  check (kind in ('gauntlet', 'finals', 'ranked'));

alter table public.referee_config add column if not exists ranked_on boolean not null default false;
alter table public.referee_config add column if not exists ranked_any_day boolean not null default false;
alter table public.referee_config add column if not exists ranked_client_write boolean not null default true;

create or replace function public.referee_ranked_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ranked_on from public.referee_config where id = 1), false)
$$;
revoke all on function public.referee_ranked_on() from public, anon, authenticated;

-- 客户端还能不能直接写积分赛成绩（ghosts / matches phase = 'ranked'）。缺行 / 缺列 ⇒ 能（与改之前一样）。
create or replace function public.ranked_client_write_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ranked_client_write from public.referee_config where id = 1), true)
$$;
revoke all on function public.ranked_client_write_ok() from public;
grant execute on function public.ranked_client_write_ok() to anon, authenticated, service_role;

-- 积分赛服务器局的第一个客户端版本（带 referee_ranked_start 的那一版；裁判程序从这一版起认 mode = 'ranked'）。
create or replace function public.ranked_min_client() returns text
language sql immutable as $$ select '0.22.7' $$;
revoke all on function public.ranked_min_client() from public, anon, authenticated;

-- 常量（= scripts/gamedata/phase2_config.gd；门禁 verify_ranked_server_rules 逐个对账）
create or replace function public.ranked_hearts_max() returns int language sql immutable as $$ select 6 $$;     -- HEARTS_MAX
create or replace function public.ranked_quota() returns int language sql immutable as $$ select 16 $$;        -- RANKED_QUOTA
create or replace function public.ranked_lockout_sec() returns int language sql immutable as $$ select 600 $$; -- CLOSE_LOCKOUT_SEC
revoke all on function public.ranked_hearts_max() from public, anon, authenticated;
revoke all on function public.ranked_quota() from public, anon, authenticated;
revoke all on function public.ranked_lockout_sec() from public, anon, authenticated;

-- 积分赛开着没有：周二 00:00 ~ 周五 23:00 − 封盘 600 秒（UTC；= phase_at_utc 周二~周五 + can_start_match_utc）。
--   ranked_any_day（内测服彩排）放开星期几；封盘那 10 分钟照样关。
create or replace function public.ranked_window_open(p_week bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.app_now() < to_timestamp(p_week + 4 * 86400 + 23 * 3600 - public.ranked_lockout_sec())
     and (coalesce((select c.ranked_any_day from public.referee_config c where c.id = 1), false)
          or public.app_now() >= to_timestamp(p_week + 86400))
$$;
revoke all on function public.ranked_window_open(bigint) from public, anon, authenticated;

-- ② 积分赛账本 ───────────────────────────────────────────────
-- 每人每周一行 = 客户端 GameState 里那几项（season_total_battles / season_wins / hearts / season_sweeps / season_eggs_killed /
--   ranked_used）的服务端那一份。只有 referee_complete（与切换周的第一次开战补种）写；客户端只读自己那一行。
create table if not exists public.ranked_records (
  season_week  bigint      not null,
  account_id   uuid        not null references auth.users(id) on delete cascade,
  battles      int         not null default 0,     -- 本周积分赛场次（= season_total_battles）
  wins         int         not null default 0,     -- 胜场（= season_wins）
  hearts       int         not null default 6,     -- 余命（= hearts；0 = 出局）
  sweeps       int         not null default 0,     -- 横扫 2-0（= season_sweeps）
  eggs         int         not null default 0,     -- 碎蛋（= season_eggs_killed）
  used         int         not null default 0,     -- 配额已用（= ranked_used）
  coins        int         not null default 0,     -- 本周积分赛服务器局一共发了多少深海币（对账用）
  seeded       text,                               -- 'ghosts' = 切换那一周从旧自报快照补种的（之后的每一场都是服务端记的）
  updated_at   timestamptz not null default now(),
  primary key (season_week, account_id)
);
alter table public.ranked_records enable row level security;
drop policy if exists ranked_records_self on public.ranked_records;
create policy ranked_records_self on public.ranked_records for select using (auth.uid() = account_id);
-- 写只有 security definer 函数（没有 insert / update 策略）

-- 这个人本周的账（没有行 ⇒ 切换之前的旧自报快照里最后一份；都没有 ⇒ 新的一周：0 场 / 满命）。只读、不建行。
create or replace function public.ranked_ledger_peek(p_uid uuid, p_week bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; g record;
begin
  select * into r from public.ranked_records where season_week = p_week and account_id = p_uid;
  if found then
    return jsonb_build_object('battles', r.battles, 'wins', r.wins, 'hearts', r.hearts, 'sweeps', r.sweeps,
      'eggs', r.eggs, 'used', r.used, 'seeded', r.seeded, 'row', true);
  end if;
  select gg.battles, gg.season_wins, gg.hearts, gg.season_sweeps, gg.snapshot into g
    from public.ghosts gg
   where gg.account_id = p_uid and gg.season_week = p_week
     and coalesce(gg.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
     and coalesce(gg.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
   order by gg.battles desc, gg.uploaded_at desc limit 1;
  if found then
    return jsonb_build_object('battles', greatest(g.battles, 0), 'wins', greatest(g.season_wins, 0),
      'hearts', least(greatest(g.hearts, 0), public.ranked_hearts_max()), 'sweeps', greatest(g.season_sweeps, 0),
      'eggs', case when jsonb_typeof(g.snapshot -> 'season_eggs_killed') = 'number'
                   then greatest((g.snapshot ->> 'season_eggs_killed')::numeric::int, 0) else greatest(g.season_wins, 0) end,
      'used', greatest(g.battles, 0), 'seeded', 'ghosts', 'row', false);
  end if;
  return jsonb_build_object('battles', 0, 'wins', 0, 'hearts', public.ranked_hearts_max(), 'sweeps', 0, 'eggs', 0,
    'used', 0, 'seeded', null, 'row', false);
end $$;
revoke all on function public.ranked_ledger_peek(uuid, bigint) from public, anon, authenticated;

-- 客户端读自己本周的账（主菜单对账 / 开战前）。不建行。
create or replace function public.referee_ranked_ledger(p_week bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  return jsonb_build_object('ok', true, 'week', p_week, 'ledger', public.ranked_ledger_peek(auth.uid(), p_week));
end $$;
revoke all on function public.referee_ranked_ledger(bigint) from public, anon;
grant execute on function public.referee_ranked_ledger(bigint) to authenticated;

-- ③ 积分赛对手池（内置陪练 + 兜底机器人）─────────────────────
create table if not exists public.ranked_pool (
  rules_ver      int         not null,
  kind           text        not null check (kind in ('seed', 'bot')),
  battles        int         not null check (battles between 0 and 1000),
  variant        int         not null check (variant between 0 and 9999),
  snapshot       jsonb       not null,
  client_version text        not null,              -- 哪个版本的代码生成的（只作记录；挑的时候按 rules_ver）
  created_at     timestamptz not null default now(),
  primary key (rules_ver, kind, battles, variant)
);
alter table public.ranked_pool enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行（池子本身就是「哪些是陪练 / 机器人」的答案）

-- 真人快照能不能当积分赛对手 —— 客户端 RemotePool.snapshot_valid（入池那一道）+ pool_find_battles（选靶那一道）在服务端的同一份：
--   schema_ver = Backend.SCHEMA_VER(2)、有 ghost_id 且不是冒烟数据（'__smoke__'）、快照自报的场次 = 要找的场次、
--   统领 1~3 只、pet_levels 在 1..10、每只装备 ≤ UNIT_EQUIP_CAP(3)、分路没坏（referee_lanes_ok = ghost_lanes_broken 取反）。
--   ★龟 id 白名单（_TS.STATS）不在这里：裁判程序算之前照样校验 B 方快照，不认识的龟 ⇒ b_bad_snapshot ⇒ 重交时换一个对手。
create or replace function public.referee_ranked_ghost_ok(p_snap jsonb, p_battles int) returns boolean
language plpgsql immutable as $$
declare k text; v jsonb;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'schema_ver') <> 'number' or (p_snap ->> 'schema_ver')::numeric <> 2 then
    return false;
  end if;
  if coalesce(p_snap ->> 'ghost_id', '') = '' or left(p_snap ->> 'ghost_id', 9) = '__smoke__' then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'season_total_battles') <> 'number'
     or (p_snap ->> 'season_total_battles')::numeric <> p_battles then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'leaders') <> 'array' or jsonb_array_length(p_snap -> 'leaders') not between 1 and 3 then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'pet_levels') = 'object' then
    for k, v in select * from jsonb_each(p_snap -> 'pet_levels') loop
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not between 1 and 10 then
        return false;
      end if;
    end loop;
  end if;
  if jsonb_typeof(p_snap -> 'equipped') = 'object' then
    for k, v in select * from jsonb_each(p_snap -> 'equipped') loop
      if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) > 3 then
        return false;
      end if;
    end loop;
  end if;
  return public.referee_lanes_ok(p_snap);
end $$;
revoke all on function public.referee_ranked_ghost_ok(jsonb, int) from public, anon, authenticated;

-- 上传积分赛池（只有 service_role：轮询器 referee_poller.py --bot-pool）。按 (规则版本, 种类) 分批调：第一批 p_replace = true 先清旧的。
--   每行 {battles, variant, snapshot}。陪练（seed）：分路没坏、自报场次 = battles；机器人（bot）：能当左方开打（referee_lineup_ok）。
--   不合格的计入 rejected、不入池。存之前摘掉 origin（服务端直接取的真人快照没有这个键；不摘 = 录像里一眼分得出）。
create or replace function public.referee_ranked_pool_load(p_client_version text, p_rules_ver int, p_kind text,
    p_rows jsonb, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; bad int := 0; total int; b int;
begin
  if p_rules_ver is null or p_rules_ver < 1 or p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or coalesce(p_client_version, '') = '' or coalesce(p_kind, '') not in ('seed', 'bot') then
    return jsonb_build_object('ok', false, 'reason', 'bad_args');
  end if;
  if coalesce(p_replace, false) then
    delete from public.ranked_pool where rules_ver = p_rules_ver and kind = p_kind;
  end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r) <> 'object' or jsonb_typeof(r -> 'battles') <> 'number' or jsonb_typeof(r -> 'variant') <> 'number'
       or jsonb_typeof(r -> 'snapshot') <> 'object' or octet_length((r -> 'snapshot')::text) > 65536 then
      bad := bad + 1;
      continue;
    end if;
    b := (r ->> 'battles')::numeric::int;
    if (p_kind = 'seed' and not (public.referee_lanes_ok(r -> 'snapshot')
          and jsonb_typeof(r -> 'snapshot' -> 'season_total_battles') = 'number'
          and (r -> 'snapshot' ->> 'season_total_battles')::numeric = b))
       or (p_kind = 'bot' and not public.referee_lineup_ok(r -> 'snapshot')) then
      bad := bad + 1;
      continue;
    end if;
    insert into public.ranked_pool (rules_ver, kind, battles, variant, snapshot, client_version)
      values (p_rules_ver, p_kind, b, (r ->> 'variant')::numeric::int, (r -> 'snapshot') - 'origin', p_client_version)
      on conflict (rules_ver, kind, battles, variant) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, created_at = now();
    n := n + 1;
  end loop;
  select count(*) into total from public.ranked_pool where rules_ver = p_rules_ver and kind = p_kind;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'loaded', n, 'rejected', bad, 'total', total);
end $$;
revoke all on function public.referee_ranked_pool_load(text, int, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.referee_ranked_pool_load(text, int, text, jsonb, boolean) to service_role;

-- ④ 挑对手 ─────────────────────────────────────────────────
-- 本周我碰过的积分赛对手（opp 键：真人 'acct:<uuid>:b<场次>' / 陪练 'seed:<规则>:<场次>:<序号>' / 机器人 'bot:…'）。
--   = 客户端匹配屏的 exclude（自己的 ghost_id + 最近 8 个对手的 ghost_id）：ghost_id 带场次（_b<N>），
--   所以排除的是「这个人在这个场次的那一份」—— 换了场次就不是同一份（与客户端同一口径）。
create or replace function public.referee_ranked_opp_ex(p_uid uuid, p_week bigint) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x), '{}')
    from (select j.meta ->> 'opp' as x from public.referee_jobs j
           where j.kind = 'ranked' and j.season_week = p_week and j.a_account = p_uid and j.meta ? 'opp'
          union all
          select jsonb_array_elements_text(j.meta -> 'opp_prev') from public.referee_jobs j
           where j.kind = 'ranked' and j.season_week = p_week and j.a_account = p_uid
             and jsonb_typeof(j.meta -> 'opp_prev') = 'array') e
   where x is not null
$$;
revoke all on function public.referee_ranked_opp_ex(uuid, bigint) from public, anon, authenticated;

-- 挑一个对手。返回 {snap, opp, pick, account?}；pick = human / seed / bot；一个都挑不到（池子没上传）⇒ null。
--   ① 场次完全相同（D5）：本周、同规则版本、不是自己、合格（referee_ranked_ghost_ok）的真人快照 ∪ 同场次的内置陪练，
--      排除本周碰过的那一份，**等概率**抽一份（= pool_find_battles 的 randi_range；用户 10-08「从全部同场次快照里等概率抽」）
--   ② 机器人（= make_bot(场次)）：池子按场次存到 30；超出的用最大那一格、只把 season_total_battles 改成真实场次（同 referee_gauntlet_pick_bot）。
create or replace function public.referee_ranked_pick(p_uid uuid, p_week bigint, p_battles int, p_rules_ver int,
    p_ex text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare c record; bp record; bk int; snap jsonb;
begin
  select * into c from (
    select format('acct:%s:b%s', g.account_id, g.battles) as opp, g.account_id as account, g.snapshot as snap, 'human' as pick
      from public.ghosts g
     where g.season_week = p_week and g.battles = p_battles and g.rules_ver = p_rules_ver
       and g.account_id <> p_uid and public.referee_ranked_ghost_ok(g.snapshot, p_battles)
    union all
    select format('seed:%s:%s:%s', p.rules_ver, p.battles, p.variant), null::uuid, p.snapshot, 'seed'
      from public.ranked_pool p
     where p.rules_ver = p_rules_ver and p.kind = 'seed' and p.battles = p_battles
       and public.referee_lanes_ok(p.snapshot)
       and jsonb_typeof(p.snapshot -> 'season_total_battles') = 'number'
       and (p.snapshot ->> 'season_total_battles')::numeric = p_battles
  ) cand
  where not (cand.opp = any(coalesce(p_ex, '{}')))
  order by random()
  limit 1;
  if found then
    return jsonb_build_object('snap', c.snap - 'origin', 'opp', c.opp, 'pick', c.pick)
      || case when c.account is not null then jsonb_build_object('account', c.account) else '{}'::jsonb end;
  end if;
  select max(battles) into bk from public.ranked_pool where rules_ver = p_rules_ver and kind = 'bot';
  if bk is null then
    return null;
  end if;
  bk := least(greatest(coalesce(p_battles, 0), 0), bk);
  select p.* into bp from public.ranked_pool p
   where p.rules_ver = p_rules_ver and p.kind = 'bot' and p.battles = bk
   order by (format('bot:%s:%s:%s', p.rules_ver, p.battles, p.variant) = any(coalesce(p_ex, '{}'))), random()
   limit 1;
  if not found then
    return null;
  end if;
  snap := bp.snapshot - 'origin';
  if coalesce(p_battles, 0) > bk then
    snap := jsonb_set(snap, '{season_total_battles}', to_jsonb(p_battles));   -- 场次标签与玩家相同（用户 10-04「场次一定要相同」）
  end if;
  return jsonb_build_object('snap', snap, 'opp', format('bot:%s:%s:%s', bp.rules_ver, bp.battles, bp.variant), 'pick', 'bot');
end $$;
revoke all on function public.referee_ranked_pick(uuid, bigint, int, int, text[]) from public, anon, authenticated;

-- 开战交上去的阵容：快照里那几个账本数改成服务端的（裁判按快照的场次算援军小将的成长，必须是服务端的场次）。
create or replace function public.ranked_stamp_snapshot(p_snap jsonb, p_led jsonb, p_battles int) returns jsonb
language plpgsql immutable as $$
declare s jsonb := p_snap; gid text;
begin
  s := jsonb_set(s, '{season_total_battles}', to_jsonb(p_battles));
  s := jsonb_set(s, '{season_wins}', p_led -> 'wins');
  s := jsonb_set(s, '{hearts}', p_led -> 'hearts');
  s := jsonb_set(s, '{season_sweeps}', p_led -> 'sweeps');
  s := jsonb_set(s, '{season_eggs_killed}', p_led -> 'eggs');
  gid := coalesce(s ->> 'ghost_id', '');
  if gid ~ '_b[0-9]+$' then
    s := jsonb_set(s, '{ghost_id}', to_jsonb(regexp_replace(gid, '_b[0-9]+$', '_b' || p_battles)));
  end if;
  if jsonb_typeof(s -> 'profile') = 'object' and coalesce(s -> 'profile' ->> 'id', '') ~ '_b[0-9]+$' then
    s := jsonb_set(s, '{profile,id}', to_jsonb(regexp_replace(s -> 'profile' ->> 'id', '_b[0-9]+$', '_b' || p_battles)));
  end if;
  return s;
end $$;
revoke all on function public.ranked_stamp_snapshot(jsonb, jsonb, int) from public, anon, authenticated;

-- ⑤ 客户端开战 ─────────────────────────────────────────────
-- 交「我的阵容 + 我要打第 N 场」（N = 本机的 season_total_battles）。回 {ok, job_id, match_id, opp(卡片), ledger}；
--   拒收 {ok:false, reason, ledger?}：not_signed_in / off / update_required / wrong_week / closed / bad_snapshot /
--   eliminated(余命 0) / quota_full(配额满) / stale(第 N 场与账本对不上 ⇒ 客户端以 ledger 为准) / no_opponent。
-- 有一场在算 ⇒ 回那一场（in_flight）。只有「上一次算失败了」才允许同一场重交，种子不换；
--   失败原因是对手快照坏了（b_bad_snapshot）⇒ 记下旧的、重挑；是我的阵容坏了（a_bad_snapshot）⇒ 收新的阵容。
create or replace function public.referee_ranked_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; led jsonb; v_b int; ex record; v_key text;
        pk jsonb; jid bigint; mid uuid; st text; v_snap_a jsonb; v_snap_b jsonb; v_meta jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_ranked_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false)
     or coalesce(public.semver_arr(v_cv), array[0, 0, 0, 0]) < public.semver_arr(public.ranked_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week is distinct from extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.ranked_window_open(p_week) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  -- 有一场在算 ⇒ 回那一场（不再建）
  select * into ex from public.referee_jobs
   where kind = 'ranked' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', public.ranked_ledger_peek(uid, p_week));
  end if;
  led := public.ranked_ledger_peek(uid, p_week);
  v_b := (led ->> 'battles')::int;
  -- = 主菜单 _battle_block_msg：出局（0 命）/ 配额满；回账本让客户端对齐
  if (led ->> 'hearts')::int <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'eliminated', 'ledger', led);
  end if;
  if (led ->> 'used')::int >= public.ranked_quota() then
    return jsonb_build_object('ok', false, 'reason', 'quota_full', 'ledger', led);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机账与服务端对不上 ⇒ 回账本，客户端以它为准）
  if p_match_no is distinct from v_b then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'ledger', led);
  end if;
  -- 账本落行（切换那一周第一次开战：从旧自报快照补种；新的一周：0 场满命）
  insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used, seeded)
    values (p_week, uid, v_b, (led ->> 'wins')::int, (led ->> 'hearts')::int, (led ->> 'sweeps')::int,
            (led ->> 'eggs')::int, (led ->> 'used')::int, led ->> 'seeded')
    on conflict (season_week, account_id) do nothing;
  v_snap_a := public.ranked_stamp_snapshot(p_snapshot, led, v_b);
  v_key := format('ranked:%s:%s:%s', p_week, uid, v_b);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', led);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta -> 'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta ->> 'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
      end if;
      v_snap_b := pk -> 'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk ->> 'opp', 'pick', pk ->> 'pick');
      update public.referee_jobs set b_account = (pk ->> 'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = v_cv,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then v_snap_a else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(v_snap_a) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('ranked', v_key, p_week, v_cv, public.referee_new_seed(), uid, (pk ->> 'account')::uuid,
      v_snap_a, pk -> 'snap', public.referee_level_of(v_snap_a),
      jsonb_build_object('account', uid, 'battles0', v_b, 'opp', pk ->> 'opp', 'pick', pk ->> 'pick',
                         'rules_ver', v_rv, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk -> 'snap'), 'ledger', led);
end $$;
revoke all on function public.referee_ranked_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_ranked_start(bigint, jsonb, int, text, int) to authenticated;

-- ⑥ 写回（以 20261027 版为底；★2026-11-01 只改两处，周六 / 周日逐字不变）：
--   ① 周六那一支的条件从 `elsif j.a_account is not null` 收紧成 `elsif j.kind = 'gauntlet' and j.a_account is not null`
--      （原来的写法会把积分赛局当成闯关局记进 gauntlet_records）
--   ② 多一支 'ranked'：_settle_season 积分赛那一支原样（见下面逐行注释）+ 以服务端的数写 ghosts
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
        v_pair boolean; v_gw_b int; v_gl_b int;           -- 2026-10-27 在线瑞士轮
        rr record; v_hearts int; v_lost int; v_reward int; v_sweep boolean; v_led jsonb; v_snap jsonb;   -- 2026-11-01 积分赛
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
  -- ★2026-10-27 在线瑞士轮：配对局（gauntlet_queue 配出来的，meta.pair）两边都是在场的账号 ⇒ 两边都记。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人（20261020c 起真人快照填账号），不是在场的人。
  v_pair := j.kind = 'gauntlet' and coalesce(j.meta->>'pair', '') = 'true';
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.kind = 'gauntlet' and j.a_account is not null then
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
  elsif j.kind = 'ranked' and j.a_account is not null then
    -- ★2026-11-01 积分赛（= RealtimeBattle3DScene._settle_season 积分赛那一支，逐行对照；门禁 verify_ranked_server_rules 同输入同输出）
    insert into public.ranked_records (season_week, account_id, hearts)
      values (j.season_week, j.a_account, public.ranked_hearts_max())
      on conflict (season_week, account_id) do nothing;
    select * into rr from public.ranked_records where season_week = j.season_week and account_id = j.a_account for update;
    v_hearts := rr.hearts;
    if not won then
      v_hearts := greatest(0, v_hearts - 1);                               -- gs.lose_heart()：clamp ≥ 0
    end if;
    v_lost := greatest(0, public.ranked_hearts_max() - v_hearts);          -- maxi(0, HEARTS_MAX − hearts)
    v_reward := 8 + v_hearts + 2 * v_lost + case when won then 6 else 0 end;   -- 8 + 余命 + 2×已失命 + 胜 6
    -- 横扫 = GameState.dual_lane_was_sweep()：两路都打完且同一方全胜、那一方是左（A）
    v_sweep := won and coalesce(p_result->'lane_results'->>'top', '') = 'left'
               and coalesce(p_result->'lane_results'->>'bottom', '') = 'left';
    v_reward := v_reward + v_coins;                                        -- + EquipTickSystem.match_minted（裁判写的 coins）
    if v_hearts <= 0 then
      v_reward := 0;                                                       -- 出局那一局不发币（含战斗内铸币）
    end if;
    update public.ranked_records
       set hearts = v_hearts,
           battles = rr.battles + 1,                                       -- season_total_battles += 1
           used = rr.used + 1,                                             -- consume_ranked_quota()
           wins = rr.wins + case when won then 1 else 0 end,               -- season_wins += 1
           eggs = rr.eggs + case when won then 1 else 0 end,               -- season_eggs_killed += 1
           sweeps = rr.sweeps + case when v_sweep then 1 else 0 end,       -- season_sweeps += 1
           coins = rr.coins + v_reward, updated_at = now()
     where season_week = j.season_week and account_id = j.a_account
     returning jsonb_build_object('battles', battles, 'wins', wins, 'hearts', hearts, 'sweeps', sweeps, 'eggs', eggs,
                                  'used', used) into v_led;
    v_led := v_led || jsonb_build_object('reward', v_reward, 'sweep', v_sweep);
    res := res || jsonb_build_object('ranked', v_led);
    v_rv := coalesce(case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    -- 快照池 / 周榜：以打完这一场的服务端账写一份（= 客户端每场都传的那一份，只是数由服务端填；E18「每场都传」）。
    --   阵容 = 开战时交的那一份；宝箱 / 香火石取这一局结束时的（裁判结果单）。
    v_snap := public.ranked_stamp_snapshot(j.a_snapshot, v_led, (v_led ->> 'battles')::int);
    if jsonb_typeof(p_result->'chest') = 'object' then
      v_snap := v_snap || jsonb_build_object('chest_treasure_value', coalesce(p_result->'chest'->'value', '0'::jsonb),
                                             'chest_treasures_won', coalesce(p_result->'chest'->'won', '[]'::jsonb));
    end if;
    if jsonb_typeof(p_result->'incense') = 'object' then
      v_snap := v_snap || jsonb_build_object('incense_marks', coalesce(p_result->'incense'->'marks', '0'::jsonb),
                                             'incense_charge', coalesce(p_result->'incense'->'charge', '0'::jsonb));
    end if;
    insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps,
        client_version, rules_ver)
      values (j.a_account, j.season_week, (v_led ->> 'battles')::int, v_snap, (v_led ->> 'wins')::int,
              (v_led ->> 'hearts')::int, (v_led ->> 'sweeps')::int, j.client_version, v_rv)
      on conflict (account_id, season_week, battles) do update
        set snapshot = excluded.snapshot, season_wins = excluded.season_wins, hearts = excluded.hearts,
            season_sweeps = excluded.season_sweeps, client_version = excluded.client_version,
            rules_ver = excluded.rules_ver, uploaded_at = now();
  end if;
  -- ★2026-10-27 配对局 B 那一边（胜负与 A 互反）：战绩账本 / 快照池 / 第 4 胜报名，与上面 A 的写法逐条相同。
  --   B 删号了（b_account 随删号断开）⇒ 只记 A。
  if v_pair and j.b_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.b_account, case when won then 0 else 1 end, case when won then 1 else 0 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw_b, v_gl_b;
    res := res || jsonb_build_object('gw_b', v_gw_b, 'gl_b', v_gl_b);
    v_rv := coalesce(v_rv,
                     case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.b_account, j.season_week, v_gw_b, v_gl_b, j.b_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
    if v_gw_b >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.b_account, coalesce(nullif(j.b_snapshot->'profile'->>'name', ''), '?'), j.b_snapshot, v_gw_b, v_gl_b)
        on conflict (season_week, account_id) do nothing;
    end if;
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  -- ★2026-10-27 配对局 right_account = B（真人或陪练号，都是真账号，填了不露馅）；旧路 / 机器人池兜底仍是 null
  -- ★2026-11-01 积分赛 right_account = null（同客户端：对手可能是陪练 / 机器人）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' or v_pair then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  -- ★2026-10-27 这一局配出来的排队行（配对局两行 / 兜底局一行）⇒ done。旧路任务没有排队行，这一句什么都不改。
  update public.gauntlet_queue set status = 'done', updated_at = now() where job_id = p_job_id and status = 'paired';
  -- ★2026-10-20d 周日任务的账本多一个 coins_b（右方 B 的战斗内铸币；周六不记）
  --   ★2026-10-27 配对局也记（B 的战斗内铸币，B 查 referee_job_status 时回给它）
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins)
                  || case when j.kind = 'finals' or v_pair then jsonb_build_object('coins_b', v_coins_b) else '{}'::jsonb end)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- ⑦ 查一局算完没有（以 20261027 版为底；★2026-11-01 只在 A 的回包尾巴上多一段：积分赛局回 kind / ranked（账本）/ seed（开算后））
--   seed：裁判一开算，结果已由任务（双方快照 + 种子）定死；给自己那一局的种子只用来跟播（手机按种子选同一张地图，不算）。
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record; v_won jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    -- ★2026-10-27 在线瑞士轮：配对局里的 B 也能查（只认 meta.pair）。回包按 B 的视角：
    --   胜负取反、战绩取 gw_b / gl_b、铸币取 coins_b、宝箱 / 香火取 chest_b / incense_b ⇒ 客户端记账一行不用改。
    select * into j from public.referee_jobs
     where job_id = p_job_id and b_account = auth.uid() and kind = 'gauntlet' and meta->>'pair' = 'true';
    if not found then
      return jsonb_build_object('ok', false, 'reason', 'no_job');
    end if;
    v_won := j.result->'ledger'->'won';
    return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
      'won', case when jsonb_typeof(v_won) = 'boolean' then to_jsonb(not (v_won #>> '{}')::boolean) end,
      'score', j.result->'ledger'->'score',
      'gw', j.result->'ledger'->'gw_b', 'gl', j.result->'ledger'->'gl_b',
      'coins', j.result->'ledger'->'coins_b',
      'error', case when j.status = 'failed' then j.error end, 'side', 'b')
      || case when j.status = 'done' and jsonb_typeof(j.result->'chest_b') = 'object'
              then jsonb_build_object('chest', j.result->'chest_b') else '{}'::jsonb end
      || case when j.status = 'done' and jsonb_typeof(j.result->'incense_b') = 'object'
              then jsonb_build_object('incense', j.result->'incense_b') else '{}'::jsonb end;
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
            then jsonb_build_object('incense', j.result->'incense') else '{}'::jsonb end
    -- 2026-10-27：配对局多回一个 side（旧路任务一个键都不多）
    || case when j.kind = 'gauntlet' and j.meta->>'pair' = 'true' then jsonb_build_object('side', 'a') else '{}'::jsonb end
    -- 2026-11-01：积分赛局（周六 / 周日的回包一个键都不多）
    || case when j.kind = 'ranked' then jsonb_build_object('kind', 'ranked')
              || case when j.status = 'done' and jsonb_typeof(j.result->'ledger'->'ranked') = 'object'
                      then jsonb_build_object('ranked', j.result->'ledger'->'ranked') else '{}'::jsonb end
              || case when j.status in ('claimed', 'done') then jsonb_build_object('seed', j.seed) else '{}'::jsonb end
            else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ⑧ 周榜：有账本的人按账本（服务端记的）排，没账本的（切换之前的自报快照）照旧。
--   以 20261024b（page）/ 20261010（v3）版为底：筛快照那一段逐字不动（latest → gh），多一层 left join ranked_records，
--   胜 / 余命 / 横扫 / 场次 = coalesce(账本, 快照)；排序 / 分页 / 权限 / 键名一个字不动。
create or replace function public.week_leaderboard_page(p_week bigint, p_offset int default 0, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; off int; tot int; page jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  off := greatest(coalesce(p_offset, 0), 0);
  with gh as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag,
           public.snapshot_lead(g.snapshot)   as lead
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), latest as (
    select gh.account_id, coalesce(rr.wins, gh.season_wins) as season_wins, coalesce(rr.hearts, gh.hearts) as hearts,
           coalesce(rr.sweeps, gh.season_sweeps) as season_sweeps, coalesce(rr.battles, gh.battles) as battles,
           gh.uploaded_at, gh.name, gh.tag, gh.lead
      from gh
      left join public.ranked_records rr on rr.season_week = p_week and rr.account_id = gh.account_id
  ), ranked as (
    select l.*, s.title, row_number() over (
             order by l.season_wins desc, l.hearts desc, l.season_sweeps desc,
                      l.uploaded_at asc, l.account_id) as rk
      from latest l
      left join public.standings s
        on s.season_week = p_week and s.account_id = l.account_id
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, '')) order by r.rk) filter (where r.rk > off and r.rk <= off + lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, page, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'offset', off,
    'rows', page, 'me', mine);
end $$;

revoke all on function public.week_leaderboard_page(bigint, int, int) from public;
revoke execute on function public.week_leaderboard_page(bigint, int, int) from anon;
grant execute on function public.week_leaderboard_page(bigint, int, int) to authenticated;

create or replace function public.week_leaderboard(p_week bigint, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; tot int; top jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 30), 1), 100);
  with gh as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), latest as (
    select gh.account_id, coalesce(rr.wins, gh.season_wins) as season_wins, coalesce(rr.hearts, gh.hearts) as hearts,
           coalesce(rr.sweeps, gh.season_sweeps) as season_sweeps, coalesce(rr.battles, gh.battles) as battles,
           gh.uploaded_at, gh.name, gh.tag
      from gh
      left join public.ranked_records rr on rr.season_week = p_week and rr.account_id = gh.account_id
  ), ranked as (
    select l.*, s.title, row_number() over (
             order by l.season_wins desc, l.hearts desc, l.season_sweeps desc,
                      l.uploaded_at asc, l.account_id) as rk
      from latest l
      left join public.standings s
        on s.season_week = p_week and s.account_id = l.account_id
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, '')) order by r.rk) filter (where r.rk <= lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, top, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot,
    'rows', top, 'me', mine);
end $$;

revoke all on function public.week_leaderboard(bigint, int) from public;
revoke execute on function public.week_leaderboard(bigint, int) from anon;
grant execute on function public.week_leaderboard(bigint, int) to authenticated;

-- ⑨ 收回客户端写积分赛成绩：ghosts 两条写策略、matches 写策略（phase = 'ranked'）加 ranked_client_write 闸。
--   开关开着（默认）⇒ 与改之前逐字等价；关掉 ⇒ 客户端 insert / update ghosts、insert 积分赛 matches 一律被行级策略拒绝，
--   只剩 referee_complete（security definer）写得进。
drop policy if exists ghosts_write_own on public.ghosts;
create policy ghosts_write_own on public.ghosts
  for insert with check (account_id = auth.uid() and public.client_version_ok(client_version)
                         and public.ranked_client_write_ok());

drop policy if exists ghosts_update_own on public.ghosts;
create policy ghosts_update_own on public.ghosts
  for update using (account_id = auth.uid())
  with check (account_id = auth.uid() and public.client_version_ok(client_version) and public.ranked_client_write_ok());

drop policy if exists matches_write_own on public.matches;
create policy matches_write_own on public.matches
  for insert with check ((left_account = auth.uid() or right_account = auth.uid())
                         and (phase <> 'ranked' or public.ranked_client_write_ok()));

-- ⑩ 领活：真人的积分赛局先算（以 20261019 版为底，只改 order by 那一行）。
--   陪练号（bot_accounts）平日 6 个同时打、一局只要几十秒，全进 FIFO 会把真人排在一串陪练号后面；
--   周末没有积分赛局 ⇒ 这一行对周六 / 周日的排序结果没有任何影响（false 恒在前，退化成原来的 created_at, job_id）。
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
     order by (kind = 'ranked' and exists (select 1 from public.bot_accounts b where b.account_id = a_account)),
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

-- ⑪ 开关下发（以 20261019c 版为底，只多一个键 ranked_on；老客户端不认这个键 ⇒ 无害）
create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on(),
                            'stream_on', coalesce((select c.stream_on from public.referee_config c where c.id = 1), false),
                            'stream_version', coalesce((select c.stream_version from public.referee_config c where c.id = 1), ''),
                            'ranked_on', public.referee_ranked_on())
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END ranked_referee 20261101d <<<
