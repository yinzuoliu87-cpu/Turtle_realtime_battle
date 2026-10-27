-- >>> BEGIN gauntlet_live_paired 20261027b >>>
-- ─────────────────────────────────────────────────────────────
-- 两件小事（2026-10-27 · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md · 接 20261027_gauntlet_online_queue）
-- 一、赛况板直播签也标配对局的 B
--   在线排队配上的那一局两边都是在场打的账号，但 referee_live_gauntlet 的行里看不出这一点 ⇒ 赛况板只给左边（A）亮「直播」。
--   本段只重定义 referee_live_gauntlet（以 20261021 版为底，其余逐字照抄）：每行多一个 `paired`（布尔，= 任务 meta.pair）。
--   B 那一侧的标识不另加：行里的 `rp` 本来就是 b_snapshot.profile 的 name / avatar / id / tag，
--     客户端 gauntlet_board.gd 的 mark_live 按 tag_of(rp)（= Backend.profile_tag，#ID 优先、退回 id）认人；
--     不回账号 uuid（客户端不用，也不多给所有登录用户一个字段）。
--   ★只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人（不在场），机器人池局 b_account 空 —— 两种都是 false。
--   ★老客户端不认识 `paired`，多一个键无害（parse_live 原样透传、live_games 只读它认识的键）。
-- 二、收盘前 11 分钟当场兜底（调度器推演发现）
--   陪练号客户端起一个要 40~60 秒 ⇒ 调度器 17:19 起不再拉号；17:19 之后才进队的真人配不到陪练号，只能等 90 秒兜底，
--   而 17:30 一到排队行就 expired（closed）⇒ 17:28 进来的人白等、再被告知「不在闯关赛时段」。
--   改：重定义 gauntlet_queue_advance（以 20261027 版为底，只改兜底那个 if）：离收盘 ≤ 11 分钟（app_now，与收盘闸同一把钟）时，
--     没配上同格子的在线对手（真人或陪练号，配对那一步照旧在前）⇒ 当场退回机器人池，不等 90 秒。陪练号照旧不兜底。
--   11 分钟 = gauntlet_queue_close_rush_sec()（660）；收盘时刻与 gauntlet_window_open / referee_gauntlet_start 同一个式子。
--   ★内测服开着 gauntlet_any_day 时，周日 17:19 之后到周一前整段都算「收盘前」⇒ 一律当场兜底（只影响内测服彩排）。
-- 上线步骤（tools/sb_migrate.py 标准路径；必须排在 20261027_gauntlet_online_queue 之后——它才有排队表 / meta.pair 的任务）：
--   sandbox → beta --rehearse → beta --apply → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
-- 回滚：referee_live_gauntlet 换回 20261021 版（客户端读不到 paired ⇒ 当 false）；
--   gauntlet_queue_advance 换回 20261027 版（回到一律等 90 秒）。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_live_gauntlet()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg record; wk bigint; v jsonb;
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;
  select * into cfg from public.referee_config where id = 1;
  wk := extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint;
  select coalesce(jsonb_agg(jsonb_build_object(
           'match_id', j.match_id, 'started_at', j.claimed_at, 'updated_at', now(),
           'client_version', j.client_version, 'seed', j.seed,
           -- 2026-10-27b：在线排队配上的那一局（meta.pair）右边也是在场打的人 ⇒ 赛况板直播签两边都标（B 那一侧按 rp 里的 #ID 认）
           'paired', coalesce(j.meta->>'pair', '') = 'true',
           'lp', jsonb_build_object('name', coalesce(j.a_snapshot->'profile'->>'name', ''),
                                   'avatar', coalesce(j.a_snapshot->'profile'->>'avatar', ''),
                                   'id', coalesce(j.a_snapshot->'profile'->>'id', ''),
                                   'tag', coalesce(j.a_snapshot->'profile'->>'tag', '')),
           'rp', jsonb_build_object('name', coalesce(j.b_snapshot->'profile'->>'name', ''),
                                   'avatar', coalesce(j.b_snapshot->'profile'->>'avatar', ''),
                                   'id', coalesce(j.b_snapshot->'profile'->>'id', ''),
                                   'tag', coalesce(j.b_snapshot->'profile'->>'tag', '')))
         order by j.claimed_at desc), '[]'::jsonb)
    into v
    from (select * from public.referee_jobs
           where kind = 'gauntlet' and season_week = wk and status = 'claimed'
             and claimed_at > now() - make_interval(secs => coalesce(cfg.lease_sec, 180))
           order by claimed_at desc
           limit 50) j;
  return v;
end $$;
revoke all on function public.referee_live_gauntlet() from public, anon;
grant execute on function public.referee_live_gauntlet() to authenticated;

-- 离收盘多少秒以内「没配上就当场兜底」（= 调度器停止拉新号的提前量：收盘前 10 分钟停 + 起号 40~60 秒）
create or replace function public.gauntlet_queue_close_rush_sec() returns int
language sql immutable as $$ select 660 $$;
revoke all on function public.gauntlet_queue_close_rush_sec() from public, anon, authenticated;

-- 推一条 waiting 往前走（以 20261027 版为底；★2026-10-27b 只改兜底那个 if：收盘前 11 分钟起没配上就当场兜底）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int;
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
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
   order by x.joined_at, x.id
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
  -- 兜底：真人等满 90 秒 ⇒ 机器人池快照，b_account 空、只记真人一边（= 旧路机器人局同一种任务）。陪练号不走兜底。
  --   ★2026-10-27b 收盘前 11 分钟起（陪练号客户端起一个要 40~60 秒，调度器 17:19 起不再拉号）：上面没配上同格子的
  --     在线对手 ⇒ 当场兜底、不等 90 秒（否则 17:28 进来的人等不满 90 秒就到 17:30 收盘，白等一场还被告知不在时段）。
  if (now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
      and public.app_now() < to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                             - make_interval(secs => public.gauntlet_queue_close_rush_sec()))
     or exists (select 1 from public.bot_accounts b where b.account_id = me.account_id) then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      public.referee_new_seed(), me.account_id, null, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id))
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_live_paired 20261027b <<<
