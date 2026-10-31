-- >>> BEGIN gauntlet_no_bot_early_fallback 20261031 >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛在线排队：确定没有陪练号能来 ⇒ 真人进队满 1 分钟就兜底，不再干等 3 分钟
--   （2026-10-31 · 接 20261029c · 方案书 docs/plans/20261031b-闯关赛开局铺号与早兜底.md）
--   用户 10-31「这个匹配不到玩家是什么情况，一分钟之后匹配不到，直到三分钟才匹配到」。
--   正式服实测（周六 00:02 ~ 00:48）：测试号 7 局全部等满 180 秒兜底 —— 那时陪练号全是 0.22.5、真人是 0.22.6，
--   服务端只配同版本 ⇒ 这 7 次从第 1 秒起就注定没有陪练号能来，前 1 分钟（只配真人）之后的 2 分钟是白等。
--   用户 10-29 定的顺序不变：前 1 分钟只配在线真人 → 1 分钟后陪练号 → 再没有才拿真人快照 / 机器人池。本迁移只把
--   「陪练号这一步确定落空」的那种情况的兜底提前到 1 分钟。
--   ① gauntlet_queue.no_bot_at：调度器（gauntlet_bot_planner.py）判「这一条排队没有陪练号能来」的时刻；每拍按它当时的判断置上 / 清掉
--   ② gauntlet_planner_beat：调度器心跳（每拍一次）+ 它拉的陪练号客户端版本
--   ③ gauntlet_planner_mark(p_week, p_no_bot uuid[], p_bot_version)：service_role；写心跳；本周 waiting 的真人条目
--      名单里的置 no_bot_at（已有的不改）、名单外的清掉；陪练号的条目一律不置
--   ④ gauntlet_queue_advance：以 20261029c 版为底，只改兜底的进门条件 —— 真人进队满 gauntlet_queue_human_only_sec（60 秒）且
--      （no_bot_at 有值 或 调度器报过到、但心跳断了 gauntlet_planner_stale_sec 秒）⇒ 当场兜底；其余照旧（180 秒 / 收盘前 11 分钟）。
--      配对一段、兜底取对手一段逐字不动；兜底任务的 meta 多一个 early（'no_bot' / 'planner_gone' / 没有 = 照旧那条线）。陪练号照旧不走兜底。
--   ★心跳那一条只在调度器报过到之后生效（gauntlet_planner_beat 一行都没有 ⇒ 不算断）⇒ 迁移先于新调度器上线时，行为与 20261029c 逐条相同。
-- 回滚：gauntlet_queue_advance 换回 20261029c 版；新列 / 新表 / 新函数留着不影响（没人置 no_bot_at、advance 不读）。
-- ★重复执行安全（if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────
alter table public.gauntlet_queue add column if not exists no_bot_at timestamptz;

create table if not exists public.gauntlet_planner_beat (
  id          int         primary key default 1 check (id = 1),
  seen_at     timestamptz not null default now(),
  bot_version text
);
alter table public.gauntlet_planner_beat enable row level security;
revoke all on table public.gauntlet_planner_beat from anon, authenticated;
grant all on table public.gauntlet_planner_beat to service_role;

-- 调度器心跳断了多久算它不在（秒）。调度器每 10 秒一拍；60 秒 = 连丢 6 拍（重启调度器约 10 秒，不会误判）。
create or replace function public.gauntlet_planner_stale_sec() returns int
language sql immutable as $$ select 60 $$;
revoke all on function public.gauntlet_planner_stale_sec() from public, anon, authenticated;

-- 调度器报过到、但心跳断了 ⇒ 不会再有陪练号被拉来
create or replace function public.gauntlet_planner_gone() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.gauntlet_planner_beat)
     and not exists (select 1 from public.gauntlet_planner_beat
                      where seen_at >= now() - make_interval(secs => public.gauntlet_planner_stale_sec()))
$$;
revoke all on function public.gauntlet_planner_gone() from public, anon, authenticated;

-- 调度器每拍调一次：写心跳；p_no_bot = 它此刻判定「没有陪练号能来」的真人账号（空数组 = 一个都没有 ⇒ 全部清掉）
create or replace function public.gauntlet_planner_mark(p_week bigint, p_no_bot uuid[], p_bot_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n_set int; n_clr int;
begin
  insert into public.gauntlet_planner_beat (id, seen_at, bot_version) values (1, now(), p_bot_version)
    on conflict (id) do update set seen_at = excluded.seen_at, bot_version = excluded.bot_version;
  update public.gauntlet_queue q set no_bot_at = now()
   where q.season_week = p_week and q.status = 'waiting' and q.no_bot_at is null
     and q.account_id = any(coalesce(p_no_bot, '{}'::uuid[]))
     and not exists (select 1 from public.bot_accounts b where b.account_id = q.account_id);
  get diagnostics n_set = row_count;
  update public.gauntlet_queue q set no_bot_at = null
   where q.season_week = p_week and q.status = 'waiting' and q.no_bot_at is not null
     and not (q.account_id = any(coalesce(p_no_bot, '{}'::uuid[])));
  get diagnostics n_clr = row_count;
  return jsonb_build_object('ok', true, 'set', n_set, 'cleared', n_clr);
end $$;
revoke all on function public.gauntlet_planner_mark(bigint, uuid[], text) from public, anon, authenticated;
grant execute on function public.gauntlet_planner_mark(bigint, uuid[], text) to service_role;

-- 推一条 waiting 往前走（以 20261029c 版为底；★20261031 只改兜底的进门条件，见文件头 ④）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int; g record;
        v_rush boolean; v_me_bot boolean; v_fresh int; v_nbot int; v_hold interval; v_early text;
begin
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  select * into me from public.gauntlet_queue where id = p_id;
  if not found or me.status <> 'waiting' then
    return;
  end if;
  perform pg_advisory_xact_lock(20261027, hashtext(format('gauntlet_cell:%s:%s:%s', me.season_week, me.gw, me.gl)));
  select * into me from public.gauntlet_queue where id = p_id for update;
  if me.status <> 'waiting' or me.last_seen < now() - v_ttl then
    return;                                   -- 锁到手时已经被别人配走 / 自己心跳断了
  end if;
  if public.gauntlet_in_job(me.season_week, me.account_id) then
    return;                                   -- 还有一场在算 ⇒ 先不配
  end if;
  if public.gauntlet_wl(me.season_week, me.account_id) <> array[me.gw, me.gl] then
    update public.gauntlet_queue set status = 'expired', updated_at = now() where id = me.id;
    return;                                   -- 账本变了（这一行的格子过时了）⇒ 让客户端按新战绩重新排
  end if;
  -- 本格子里心跳断了的 ⇒ expired（skip locked：正被它自己的 poll 刷新的那一行不碰，免得互等）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
                   and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_ex := public.referee_gauntlet_opp_ex(me.account_id, me.season_week);
  -- ★20261029c 前 1 分钟只配在线真人（用户 10-29 选 C「前 1 分钟只配在线真人；1 分钟后拉陪练号；陪练号也没有再拿真人快照，最后是系统阵容」）：
  --   真人 × 真人：随时配；真人 × 陪练号：真人那一边进队满 gauntlet_queue_human_only_sec（60 秒）才配；
  --   陪练号 × 陪练号：互配之后这一格剩下的在线陪练号仍 ≥ 还没满 60 秒的在线真人数才配（陪练号先留给他们）；
  --   收盘前 11 分钟起（close_rush）不设这一分钟。挑对手：真人先于陪练号，再先来先配。
  v_rush := public.app_now() >= to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                                 - make_interval(secs => public.gauntlet_queue_close_rush_sec());
  v_hold := make_interval(secs => public.gauntlet_queue_human_only_sec());
  v_me_bot := exists (select 1 from public.bot_accounts b where b.account_id = me.account_id);
  select count(*) filter (where not exists (select 1 from public.bot_accounts b where b.account_id = x.account_id)
                           and x.joined_at > now() - v_hold and not v_rush),
         count(*) filter (where exists (select 1 from public.bot_accounts b where b.account_id = x.account_id) and x.id <> me.id)
    into v_fresh, v_nbot
    from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.last_seen >= now() - v_ttl;
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
     and case
           when v_me_bot = exists (select 1 from public.bot_accounts b where b.account_id = x.account_id) then
             not v_me_bot or v_nbot - 1 >= v_fresh                       -- 真人 × 真人随时；陪练号 × 陪练号要留够给真人
           else
             v_rush or (case when v_me_bot then x.joined_at else me.joined_at end) <= now() - v_hold   -- 真人 × 陪练号
         end
   order by exists (select 1 from public.bot_accounts b where b.account_id = x.account_id), x.joined_at, x.id
   limit 1
   for update skip locked;
  if found then
    -- 先来的当 A（左方）
    if (o.joined_at, o.id) < (me.joined_at, me.id) then
      qa := o; qb := me;
    else
      qa := me; qb := o;
    end if;
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
        a_account, b_account, a_snapshot, b_snapshot, level, meta)
      values ('gauntlet', format('gpair:%s:%s:%s', me.season_week, qa.id, qb.id), me.season_week, qa.client_version,
        public.referee_new_seed(), qa.account_id, qb.account_id, qa.snapshot, qb.snapshot,
        public.referee_level_of(qa.snapshot),
        jsonb_build_object('pair', true, 'account', qa.account_id, 'gw0', qa.gw, 'gl0', qa.gl,
                           'opp', qb.account_id::text, 'pick', 'pair', 'rules_ver', qa.rules_ver,
                           'queue_a', qa.id, 'queue_b', qb.id))
      returning job_id into jid;
    update public.gauntlet_queue
       set status = 'paired', job_id = jid, side = case when id = qa.id then 'a' else 'b' end,
           paired_at = now(), updated_at = now()
     where id in (qa.id, qb.id);
    return;
  end if;
  -- 兜底：真人等满 gauntlet_queue_fallback_sec（★20261029b 起 180 秒）⇒ 先同格子真人快照、没有再机器人池；只记真人一边。陪练号不走兜底。
  --   ★2026-10-27b 收盘前 11 分钟起（陪练号客户端起一个要 40~60 秒，调度器 17:19 起不再拉号）：上面没配上同格子的
  --     在线对手 ⇒ 当场兜底、不等 90 秒（否则 17:28 进来的人等不满 90 秒就到 17:30 收盘，白等一场还被告知不在时段）。
  --   ★20261031 确定没有陪练号能来 ⇒ 等满只配真人的那 1 分钟就兜底（用户 10-31「一分钟之后匹配不到，直到三分钟才匹配到」）：
  --     调度器把这一条判成没号（no_bot_at）—— 陪练号版本与真人不同 / 这一格和上一级都没有没交过手的号；或调度器报过到、心跳却断了。
  v_early := case
               when v_me_bot or now() - me.joined_at < v_hold then null
               when me.no_bot_at is not null then 'no_bot'
               when public.gauntlet_planner_gone() then 'planner_gone'
             end;
  if (v_early is null
      and now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
      and public.app_now() < to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                             - make_interval(secs => public.gauntlet_queue_close_rush_sec()))
     or v_me_bot then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  -- ★20261029b ① 同格子真人快照（本周闯关上传的、同战绩、同 rules_ver、跑得起来；排除自己与本周交过手的）：
  --   真人号优先于陪练号（bot_accounts），30 分钟内上传的优先（= referee_gauntlet_pick 的 FRESH 窗口），再随机。
  --   用户 10-29「也不应该是优先真人的快照吗，但可以多等啊，3分钟？」
  select gg.account_id, gg.snapshot, gg.uploaded_at into g
    from public.gauntlet_ghosts gg
   where gg.season_week = me.season_week and gg.gw = me.gw and gg.gl = me.gl and gg.rules_ver = me.rules_ver
     and gg.account_id <> me.account_id and not (gg.account_id::text = any(v_ex))
     and public.referee_lanes_ok(gg.snapshot)
   order by (not exists (select 1 from public.bot_accounts b where b.account_id = gg.account_id)) desc,
            (gg.uploaded_at > now() - make_interval(secs => 1800)) desc, random()
   limit 1;
  if found then
    pk := jsonb_build_object('snap', g.snapshot - 'origin', 'opp', g.account_id::text, 'account', g.account_id,
      'pick', case when g.uploaded_at > now() - make_interval(secs => 1800) then 'fresh' else 'stale' end);
  else
    -- ② 机器人池（原样）
    pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  end if;
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      -- b_account = 被打的那份快照的主人（同旧路 referee_gauntlet_start；不在场、meta 不带 pair ⇒ 只记真人一边）；机器人池 = 空
      public.referee_new_seed(), me.account_id, (pk->>'account')::uuid, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id)
      || case when v_early is null then '{}'::jsonb else jsonb_build_object('early', v_early) end)
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_no_bot_early_fallback 20261031 <<<
