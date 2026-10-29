-- >>> BEGIN gauntlet_fallback_real_first 20261029b >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛在线排队的兜底改「先真人快照、再机器人池」+ 等 3 分钟（2026-10-29 · 接 20261027 / 20261027b / 20261029 ·
--   方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2）
--   用户 10-29「等满 90 秒没人就退回机器人阵容快照？也不应该是优先真人的快照吗，但可以多等啊，3分钟？」
--   ① gauntlet_queue_fallback_sec 90 → 180（调度器 / 状态回包 fallback_sec 跟着变；客户端没有写死这个数）
--   ② gauntlet_queue_advance 以 20261027b 版为底，只改兜底那一段：先挑同格子真人闯关快照（真人号先于陪练号，30 分钟内先），
--      没有再机器人池；挑到真人快照时 b_account = 快照主人（同旧路），meta 不带 pair ⇒ 只记真人一边。配对那一段逐字不动。
--   ★20261027 / 27b 检查脚本里「90 秒兜底」「兜底 = 机器人池」那几条只对它们那一刻成立；本段之后以本段检查脚本为准。
-- ─────────────────────────────────────────────────────────────
create or replace function public.gauntlet_queue_fallback_sec() returns int
language sql immutable as $$ select 180 $$;
revoke all on function public.gauntlet_queue_fallback_sec() from public, anon, authenticated;

-- 推一条 waiting 往前走（以 20261027b 版为底；★20261029b 只改兜底：先真人快照、再机器人池，b_account = 快照主人）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int; g record;
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
  -- 兜底：真人等满 gauntlet_queue_fallback_sec（★20261029b 起 180 秒）⇒ 先同格子真人快照、没有再机器人池；只记真人一边。陪练号不走兜底。
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
                         'queue_a', me.id))
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_fallback_real_first 20261029b <<<
