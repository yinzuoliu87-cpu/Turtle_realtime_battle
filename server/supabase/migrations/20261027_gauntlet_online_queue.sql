-- >>> BEGIN gauntlet_online_queue 20261027 >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛改在线瑞士轮（2026-10-27 · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2）
--   用户 10-27「一定是要我这边匹配之后，我这个阵容处于锁定状态……等到了另外一个对手也锁定了他的这个阵容……才互相匹配」
--   「周六周日我们讲究是在线啊」。
--   现状：referee_gauntlet_start 当场配一份对方快照、只记我这一边 ⇒ 两边各打对方快照、可能互相都赢。
--   改成：锁阵容进队列 → 等同战绩格子里另一个也在线锁定的人 → 只建一条任务、裁判算一次、两边都记。
--
-- 本段内容：
--   ① 表：gauntlet_queue（排队行）、bot_accounts（陪练号名单，只有 service_role 碰得到）；referee_jobs 加 b_account 索引。
--      ★b_account 列 20261019 就有：旧路真人快照对手填账号、机器人池 null。
--        ⇒「两边都记」不能按 b_account 非空判（那会把被打的那份快照的主人也记一场），只认 meta.pair = true。
--   ② 客户端 RPC（authenticated）：gauntlet_queue_join / gauntlet_queue_poll / gauntlet_queue_cancel
--      配对 = 同周、同格子（gw / gl）、同客户端版本、同规则版本、15 秒内有心跳、本周没交手过、都没有在算的局；
--        先来先配，先来的当 A。真人和陪练号一视同仁（陪练号周末是真客户端，走同一套接口）。
--      真人等满 90 秒还没配上 ⇒ 退回机器人池快照（referee_gauntlet_pick 的机器人那一支），建一条 b_account 为空、
--        只记真人一边的任务（与旧路同一种）。陪练号（bot_accounts）不走兜底：等不到人由它自己取消。
--   ③ 服务 RPC（service_role）：gauntlet_service_state（陪练号调度器看排队 / 在打 / 每个陪练号的格子、忙不忙、打完没有、交过手的人）
--   ④ 重定义：
--      referee_complete（配对局两边都记：战绩互反 / 快照池 / 第 4 胜报名 / 账本 coins_b / matches.right_account = B）
--      referee_job_status（配对局的 B 也能查，回包按 B 的视角）
--      referee_gauntlet_start（「在算的那场」认配对局里的 B；其余逐字照抄 20261026b）
--      referee_gauntlet_pick（对手排除表多看配对局里我当 B 的那一侧；排除表与机器人那一支抽成函数，兜底共用）
--   ★旧路任务（meta 没有 pair）写回 / 查询与本段之前逐字相同 —— 检查脚本拿改前函数体对同一输入比结果。
--   ★幂等键：配对局 gpair:<周>:<A 排队行>:<B 排队行>、兜底局 gfallback:<周>:<排队行>（一条排队行最多配一次）；
--     B 的防重交靠排队行状态 + 「有在算的局就不排」。
--   ★算失败的配对局（referee_fail 次数用尽 / 删号作废）：两边的排队行在下次 join / poll / cancel 时作废（cancelled，
--     job_id 留着），各自重新排队；种子 / 对手不沿用（旧路「重交同一场」那套只对 gauntlet:<周>:<账号>:<场> 的任务）。
--     两人本周不再互配（交手判定按任务行，不分成败 —— 与 referee_gauntlet_pick 的排除表同一口径）。
-- 上线步骤（tools/sb_migrate.py 标准路径）：sandbox → beta --rehearse → beta --apply → 内测服彩排 → prod --precheck → prod --rehearse → prod --apply。
--   新客户端（走队列）上架前执行本段无害：没人调三个新接口；旧接口 referee_gauntlet_start 只多认了配对局里的 B。
-- 回滚：三个被重定义的函数换回各自上一版（referee_complete / referee_gauntlet_start ← 20261026b、referee_job_status ← 20261023、
--   referee_gauntlet_pick ← 20261020c）；新表 / 新函数留着不影响旧包。
-- ★重复执行安全（if not exists / create or replace / 先 unschedule 再 schedule）。
-- ─────────────────────────────────────────────────────────────

-- ① 表 ──────────────────────────────────────────────────────
create table if not exists public.gauntlet_queue (
  id             bigint      generated always as identity primary key,
  season_week    bigint      not null,
  account_id     uuid        not null references auth.users(id) on delete cascade,
  gw             int         not null check (gw between 0 and 9),     -- 排队那一刻账本上的战绩 = 格子
  gl             int         not null check (gl between 0 and 9),
  rules_ver      int         not null,
  client_version text        not null,
  snapshot       jsonb       not null,                                -- 锁定的阵容（配上后原样进任务）
  joined_at      timestamptz not null default now(),
  last_seen      timestamptz not null default now(),                  -- 心跳（客户端每 2 秒 poll 一次）
  paired_at      timestamptz,
  status         text        not null default 'waiting'
                 check (status in ('waiting', 'paired', 'cancelled', 'expired', 'done')),
  job_id         bigint      references public.referee_jobs(job_id) on delete set null,
  side           text        check (side in ('a', 'b')),
  updated_at     timestamptz not null default now()
);
-- 同一周同一账号最多一条 waiting
create unique index if not exists gauntlet_queue_one_waiting
  on public.gauntlet_queue (season_week, account_id) where status = 'waiting';
create index if not exists gauntlet_queue_cell_idx
  on public.gauntlet_queue (season_week, gw, gl, joined_at) where status = 'waiting';
create index if not exists gauntlet_queue_acc_idx on public.gauntlet_queue (season_week, account_id, id);
create index if not exists gauntlet_queue_job_idx on public.gauntlet_queue (job_id) where job_id is not null;
alter table public.gauntlet_queue enable row level security;
revoke all on table public.gauntlet_queue from anon, authenticated;
grant all on table public.gauntlet_queue to service_role;
-- 没有任何策略 ⇒ 客户端直连读不到（快照 = 阵容情报）；只经下面的函数。

-- 陪练号名单（裁判机上的调度器写；客户端看不到 ⇒ 排行榜 / 赛况板不区分真人与陪练号）
create table if not exists public.bot_accounts (
  account_id uuid        primary key references auth.users(id) on delete cascade,
  added_at   timestamptz not null default now()
);
alter table public.bot_accounts enable row level security;
revoke all on table public.bot_accounts from anon, authenticated;
grant all on table public.bot_accounts to service_role;

-- 配对局里 B 那一侧的查找（referee_job_status / 在算的那场 / 交手排除表）
create index if not exists referee_jobs_b_acc_idx on public.referee_jobs (season_week, b_account);

-- ② 小工具（内部，不授权给客户端）───────────────────────────────
-- 心跳多久没刷新算离开 / 真人等多久退回机器人池（秒）。客户端每 2 秒 poll。
create or replace function public.gauntlet_queue_ttl_sec() returns int
language sql immutable as $$ select 15 $$;
create or replace function public.gauntlet_queue_fallback_sec() returns int
language sql immutable as $$ select 90 $$;
revoke all on function public.gauntlet_queue_ttl_sec() from public, anon, authenticated;
revoke all on function public.gauntlet_queue_fallback_sec() from public, anon, authenticated;

-- 闯关赛开着没有：周六 00:00 ~ 周日 17:30 UTC（= referee_gauntlet_start 的 closed 闸；内测服 gauntlet_any_day 放开）
create or replace function public.gauntlet_window_open(p_week bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.gauntlet_any_day from public.referee_config c where c.id = 1), false)
      or (public.app_now() >= to_timestamp(p_week + 5 * 86400)
          and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800))
$$;
revoke all on function public.gauntlet_window_open(bigint) from public, anon, authenticated;

-- 账本上的 [胜, 负]（没有行 = [0, 0]）
create or replace function public.gauntlet_wl(p_week bigint, p_uid uuid) returns int[]
language sql stable security definer set search_path = public as $$
  select array[coalesce(max(r.gw), 0), coalesce(max(r.gl), 0)]
    from public.gauntlet_records r where r.season_week = p_week and r.account_id = p_uid
$$;
revoke all on function public.gauntlet_wl(bigint, uuid) from public, anon, authenticated;

-- 有没有一场闯关在算（旧路 / 兜底局里我是 A；配对局里我是 A 或 B）
create or replace function public.gauntlet_in_job(p_week bigint, p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.referee_jobs j
                  where j.kind = 'gauntlet' and j.season_week = p_week and j.status in ('pending', 'claimed')
                    and (j.a_account = p_uid or (j.b_account = p_uid and j.meta->>'pair' = 'true')))
$$;
revoke all on function public.gauntlet_in_job(bigint, uuid) from public, anon, authenticated;

-- 本周已经碰过的对手（账号 uuid 文本 / 'bot:…'）。原样抽自 20261020c referee_gauntlet_pick 的 v_ex，
--   ★2026-10-27 多一支：配对局里我是 B ⇒ 对手是 A（A 那一侧本来就记在 meta.opp 里）。
create or replace function public.referee_gauntlet_opp_ex(p_uid uuid, p_week bigint) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x), '{}')
    from (select j.meta->>'opp' as x from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid and j.meta ? 'opp'
          union all
          select jsonb_array_elements_text(j.meta->'opp_prev') from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid
             and jsonb_typeof(j.meta->'opp_prev') = 'array'
          union all
          select j.a_account::text from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.b_account = p_uid and j.meta->>'pair' = 'true') e
   where x is not null
$$;
revoke all on function public.referee_gauntlet_opp_ex(uuid, bigint) from public, anon, authenticated;

-- 机器人池挑一份（原样抽自 20261020c referee_gauntlet_pick 的「② 机器人」那一支；p_ex = 上面的排除表）。
--   排队兜底只用这一支（不挑真人快照 ⇒ 不会再出现「两边各打对方快照」）。
create or replace function public.referee_gauntlet_pick_bot(p_gw int, p_gl int, p_rules_ver int, p_battles int,
    p_ex text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare bp record; bk int; snap jsonb;
begin
  -- ② 机器人：池子按场次存到 30（= bot_pool.gd MAX_BATTLES；装备曲线 28 场封顶），超出的用 30 那一格
  bk := least(greatest(coalesce(p_battles, 0), p_gw + p_gl, 0), 30);
  select b.* into bp
    from public.gauntlet_bot_pool b
   where b.rules_ver = p_rules_ver and b.battles = bk and b.gw = p_gw and b.gl = p_gl
   order by (format('bot:%s:%s:%s:%s:%s', b.rules_ver, b.battles, b.gw, b.gl, b.variant) = any(p_ex)), random()
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
revoke all on function public.referee_gauntlet_pick_bot(int, int, int, int, text[]) from public, anon, authenticated;

-- 挑一个对手（旧路 referee_gauntlet_start 用）。以 20261020c 版为底：① 同标签真人那一段逐字不变；
--   ★2026-10-27 只改两处：排除表改调 referee_gauntlet_opp_ex（多看配对局里我当 B 的那一侧）、② 机器人那一支改调 referee_gauntlet_pick_bot。
create or replace function public.referee_gauntlet_pick(p_uid uuid, p_week bigint, p_gw int, p_gl int,
    p_rules_ver int, p_battles int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_ex text[]; g record;
begin
  v_ex := public.referee_gauntlet_opp_ex(p_uid, p_week);
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
  -- ② 机器人
  return public.referee_gauntlet_pick_bot(p_gw, p_gl, p_rules_ver, p_battles, v_ex);
end $$;
revoke all on function public.referee_gauntlet_pick(uuid, bigint, int, int, int, int) from public, anon, authenticated;

-- 我那几条「已配上、但那一局算失败了 / 任务行没了」的排队行 ⇒ 作废（cancelled，job_id 留着），好重新排队
create or replace function public.gauntlet_queue_void_failed(p_week bigint, p_uid uuid) returns void
language sql security definer set search_path = public as $$
  update public.gauntlet_queue q set status = 'cancelled', updated_at = now()
   where q.season_week = p_week and q.account_id = p_uid and q.status = 'paired'
     and not exists (select 1 from public.referee_jobs j where j.job_id = q.job_id and j.status <> 'failed')
$$;
revoke all on function public.gauntlet_queue_void_failed(bigint, uuid) from public, anon, authenticated;

-- 一条排队行 → 客户端回包。
--   waiting ⇒ {ok, status:'waiting', gw, gl, waited_sec}
--   paired / done ⇒ {ok, status:'paired', gw, gl, waited_sec, job_id, match_id, side, job_status, opp:对手卡}
--     （done 也回 paired：配上之后客户端照现有流程按 job_id 查结果；job_status 告诉它这一局算完没有）
--   expired ⇒ {ok, status:'expired', gw, gl}；cancelled / 没有 ⇒ {ok, status:'none'}（算失败作废的多带 reason:'job_failed' + job_id）
create or replace function public.gauntlet_queue_view(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.gauntlet_queue%rowtype; j record;
begin
  select * into q from public.gauntlet_queue where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'status', 'none');
  end if;
  if q.status = 'waiting' then
    return jsonb_build_object('ok', true, 'status', 'waiting', 'gw', q.gw, 'gl', q.gl,
      'waited_sec', greatest(0, floor(extract(epoch from now() - q.joined_at)))::int);
  end if;
  if q.status in ('paired', 'done') then
    select * into j from public.referee_jobs where job_id = q.job_id;
    return jsonb_build_object('ok', true, 'status', 'paired', 'gw', q.gw, 'gl', q.gl,
      'waited_sec', greatest(0, floor(extract(epoch from coalesce(q.paired_at, now()) - q.joined_at)))::int,
      'job_id', q.job_id, 'match_id', j.match_id, 'side', q.side, 'job_status', j.status,
      'opp', public.referee_opp_card(case when q.side = 'a' then j.b_snapshot else j.a_snapshot end));
  end if;
  if q.status = 'expired' then
    return jsonb_build_object('ok', true, 'status', 'expired', 'gw', q.gw, 'gl', q.gl);
  end if;
  return jsonb_build_object('ok', true, 'status', 'none', 'gw', q.gw, 'gl', q.gl)
    || case when q.job_id is not null then jsonb_build_object('reason', 'job_failed', 'job_id', q.job_id) else '{}'::jsonb end;
end $$;
revoke all on function public.gauntlet_queue_view(bigint) from public, anon, authenticated;

-- 推一条 waiting 往前走：先找同格子的在线对手配成一局；没有、而且是真人、已经等满 90 秒 ⇒ 退回机器人池。
--   ★每个格子一把事务级 advisory 锁（同周同 gw / gl）：同一格子里的配对一个一个来 ⇒ 两个人同时进来也只建一条任务；
--     候选行再加 for update skip locked（正被它自己的 poll / cancel 改的那一行这一轮不碰，不互等）。
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
  if now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
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

-- ③ 客户端 RPC ──────────────────────────────────────────────
-- 锁阵容排队。闸与 referee_gauntlet_start 同一组、同一顺序、同一组 reason：
--   not_signed_in / off / update_required / wrong_week / closed / bad_snapshot / finished(gw, gl) / stale(gw, gl)。
--   版本：p_client_version 缺省取请求头 X-Client-Version；规则版本以 referee_versions 登记的为准（p_rules_ver 给了就必须相等）。
-- 有一场在算（配对局里我是 A 或 B / 兜底局 / 旧路）⇒ 回那一场（status 'paired' + in_flight），不再排。
-- 写或刷新我的 waiting（刷新不重新计时），然后当场找对手；回包见 gauntlet_queue_view。
create or replace function public.gauntlet_queue_join(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; v_gw int := 0; v_gl int := 0;
        ex record; v_id bigint;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.gauntlet_window_open(p_week) then
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
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    select id into v_id from public.gauntlet_queue where job_id = ex.job_id and account_id = uid order by id desc limit 1;
    if v_id is not null then
      return public.gauntlet_queue_view(v_id) || jsonb_build_object('in_flight', true);
    end if;
    return jsonb_build_object('ok', true, 'status', 'paired', 'in_flight', true, 'gw', v_gw, 'gl', v_gl,
      'waited_sec', 0, 'job_id', ex.job_id, 'match_id', ex.match_id, 'job_status', ex.status,
      'side', case when ex.a_account = uid then 'a' else 'b' end,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end));
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- 我自己那条心跳断了的旧 waiting ⇒ expired（重新排、重新计时）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where season_week = p_week and account_id = uid and status = 'waiting'
     and last_seen < now() - make_interval(secs => public.gauntlet_queue_ttl_sec());
  insert into public.gauntlet_queue (season_week, account_id, gw, gl, rules_ver, client_version, snapshot)
    values (p_week, uid, v_gw, v_gl, v_rv, v_cv, p_snapshot)
    on conflict (season_week, account_id) where status = 'waiting' do update
      set gw = excluded.gw, gl = excluded.gl, rules_ver = excluded.rules_ver, client_version = excluded.client_version,
          snapshot = excluded.snapshot, last_seen = now(), updated_at = now()
    returning id into v_id;
  perform public.gauntlet_queue_advance(v_id);
  return public.gauntlet_queue_view(v_id);
end $$;
revoke all on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) to authenticated;

-- 心跳 + 查状态（客户端每 2 秒一次）。看的是我本周最新的那一条排队行：
--   waiting：心跳断了超过 15 秒 ⇒ expired；闯关赛关了 ⇒ expired（reason 'closed'）；否则刷新心跳、再试着配一次（含 90 秒兜底）。
--   回包见 gauntlet_queue_view；一条都没有 ⇒ {ok, status:'none', gw, gl}（账本上的数）。
create or replace function public.gauntlet_queue_poll(p_week bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q public.gauntlet_queue%rowtype; w int[];
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into q from public.gauntlet_queue where season_week = p_week and account_id = uid order by id desc limit 1;
  if not found then
    w := public.gauntlet_wl(p_week, uid);
    return jsonb_build_object('ok', true, 'status', 'none', 'gw', w[1], 'gl', w[2]);
  end if;
  if q.status = 'waiting' then
    if q.last_seen < now() - make_interval(secs => public.gauntlet_queue_ttl_sec()) then
      update public.gauntlet_queue set status = 'expired', updated_at = now() where id = q.id and status = 'waiting';
      return public.gauntlet_queue_view(q.id);
    end if;
    if not public.referee_gauntlet_on() or not public.gauntlet_window_open(p_week)
       or p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
      update public.gauntlet_queue set status = 'expired', updated_at = now() where id = q.id and status = 'waiting';
      return public.gauntlet_queue_view(q.id) || jsonb_build_object('reason', 'closed');
    end if;
    update public.gauntlet_queue set last_seen = now() where id = q.id and status = 'waiting';
    perform public.gauntlet_queue_advance(q.id);
  end if;
  return public.gauntlet_queue_view(q.id);
end $$;
revoke all on function public.gauntlet_queue_poll(bigint) from public, anon;
grant execute on function public.gauntlet_queue_poll(bigint) to authenticated;

-- 取消排队：waiting ⇒ cancelled（阵容解锁）。已经配上（paired / done）⇒ {ok:false, reason:'paired', job_id, side, match_id}
--   （那一局照样算、照样记，与「杀进程不作废」一致）。没有在排 ⇒ {ok:true, status:'none'}。
create or replace function public.gauntlet_queue_cancel(p_week bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_id bigint; q public.gauntlet_queue%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  update public.gauntlet_queue set status = 'cancelled', updated_at = now()
   where season_week = p_week and account_id = uid and status = 'waiting'
  returning id into v_id;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'status', 'cancelled');
  end if;
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into q from public.gauntlet_queue where season_week = p_week and account_id = uid order by id desc limit 1;
  if found and q.status in ('paired', 'done') then
    return jsonb_build_object('ok', false, 'reason', 'paired', 'job_id', q.job_id, 'side', q.side,
      'match_id', (select j.match_id from public.referee_jobs j where j.job_id = q.job_id));
  end if;
  return jsonb_build_object('ok', true, 'status', 'none');
end $$;
revoke all on function public.gauntlet_queue_cancel(bigint) from public, anon;
grant execute on function public.gauntlet_queue_cancel(bigint) to authenticated;

-- ④ 服务 RPC（service_role：裁判机上的陪练号调度器）──────────────────
-- 本周交过手的账号（uuid 文本；不含机器人池 'bot:…'）。两个方向都算：我打过的（排除表）+ 打过我快照的（旧路）。
create or replace function public.gauntlet_opponents(p_week bigint, p_uid uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x order by x), '{}')
    from (select unnest(public.referee_gauntlet_opp_ex(p_uid, p_week)) as x
          union all
          select j.a_account::text from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.meta->>'opp' = p_uid::text) e
   where x is not null and x !~ '^bot:'
$$;
revoke all on function public.gauntlet_opponents(bigint, uuid) from public, anon, authenticated;

-- 回 {ok, now, close_at, open_at, now_ts, close_ts, gauntlet_on, any_day, ttl_sec, fallback_sec, waiting, playing, bots}
--   waiting：排队里 15 秒内有心跳的条目，真人和陪练号都在（is_bot 标出；调度器按 bots 名单也认得出）
--            [{account_id, gw, gl, waited_sec, seen_sec, client_version, is_bot, opponents}]
--   playing：已配上、那一局还在算的排队行 [{account_id, gw, gl, job_id, side, is_bot}]
--   bots：bot_accounts 里每个号 [{account_id, gw, gl, in_job, waiting, busy, finished, promoted, last_played_at, opponents}]
--     in_job = 有一场闯关在算；waiting = 正在排队（15 秒内有心跳）；busy = in_job 或 waiting；
--     finished = 4 胜 / 3 负 / 满 6 场；promoted = 本周 battles 最大那份积分赛快照（ghosts）的 season_wins ≥ 11（= PROMOTE_WINS）；
--     last_played_at = 本周最近一局闯关结果写回（status done）的 epoch 秒（没打过 = null）。
--   opponents = gauntlet_opponents（本周交过手的账号）。时刻：now / close_at / open_at 是 timestamptz，另给 now_ts / close_ts epoch 秒。
-- ★读之前先把本周心跳断了的 waiting 置 expired（与 poll 同一条线）。
create or replace function public.gauntlet_service_state(p_week bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_ttl interval; v_now timestamptz; v_close timestamptz;
begin
  select * into cfg from public.referee_config where id = 1;
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = p_week and x.status = 'waiting' and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_now := public.app_now();
  v_close := to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800);
  return jsonb_build_object('ok', true, 'now', v_now, 'close_at', v_close,
    'open_at', to_timestamp(p_week + 5 * 86400),
    'now_ts', floor(extract(epoch from v_now))::bigint, 'close_ts', floor(extract(epoch from v_close))::bigint,
    'gauntlet_on', coalesce(cfg.gauntlet_on, false), 'any_day', coalesce(cfg.gauntlet_any_day, false),
    'ttl_sec', public.gauntlet_queue_ttl_sec(), 'fallback_sec', public.gauntlet_queue_fallback_sec(),
    'waiting', (select coalesce(jsonb_agg(jsonb_build_object(
                  'account_id', q.account_id, 'gw', q.gw, 'gl', q.gl,
                  'waited_sec', greatest(0, floor(extract(epoch from now() - q.joined_at)))::int,
                  'seen_sec', greatest(0, floor(extract(epoch from now() - q.last_seen)))::int,
                  'client_version', q.client_version,
                  'is_bot', exists (select 1 from public.bot_accounts b where b.account_id = q.account_id),
                  'opponents', to_jsonb(public.gauntlet_opponents(p_week, q.account_id))) order by q.joined_at, q.id), '[]'::jsonb)
                  from public.gauntlet_queue q
                 where q.season_week = p_week and q.status = 'waiting' and q.last_seen >= now() - v_ttl),
    'playing', (select coalesce(jsonb_agg(jsonb_build_object(
                  'account_id', q.account_id, 'gw', q.gw, 'gl', q.gl, 'job_id', q.job_id, 'side', q.side,
                  'is_bot', exists (select 1 from public.bot_accounts b where b.account_id = q.account_id))
                  order by q.paired_at, q.id), '[]'::jsonb)
                  from public.gauntlet_queue q join public.referee_jobs j on j.job_id = q.job_id
                 where q.season_week = p_week and q.status = 'paired' and j.status in ('pending', 'claimed')),
    'bots', (select coalesce(jsonb_agg(jsonb_build_object(
               'account_id', s.account_id, 'gw', s.w[1], 'gl', s.w[2],
               'in_job', s.ij, 'waiting', s.wt, 'busy', s.ij or s.wt,
               'finished', s.w[1] >= 4 or s.w[2] >= 3 or s.w[1] + s.w[2] >= 6,
               'promoted', coalesce(s.sw, 0) >= 11,
               'last_played_at', floor(extract(epoch from s.lp))::bigint,
               'opponents', to_jsonb(public.gauntlet_opponents(p_week, s.account_id))) order by s.account_id), '[]'::jsonb)
               from (select b.account_id,
                            public.gauntlet_wl(p_week, b.account_id) as w,
                            public.gauntlet_in_job(p_week, b.account_id) as ij,
                            exists (select 1 from public.gauntlet_queue q
                                     where q.season_week = p_week and q.account_id = b.account_id
                                       and q.status = 'waiting' and q.last_seen >= now() - v_ttl) as wt,
                            (select g.season_wins from public.ghosts g
                              where g.account_id = b.account_id and g.season_week = p_week
                              order by g.battles desc, g.uploaded_at desc limit 1) as sw,
                            (select max(j.done_at) from public.referee_jobs j
                              where j.kind = 'gauntlet' and j.season_week = p_week and j.status = 'done'
                                and (j.a_account = b.account_id
                                     or (j.b_account = b.account_id and j.meta->>'pair' = 'true'))) as lp
                       from public.bot_accounts b) s));
end $$;
revoke all on function public.gauntlet_service_state(bigint) from public, anon, authenticated;
grant execute on function public.gauntlet_service_state(bigint) to service_role;

-- ⑤ 重定义的现行函数 ───────────────────────────────────────

-- 旧路开打（以 20261026b 版为底；★2026-10-27 只改「在算的那场」那一段：配对局里我是 B 也算，对手卡给 A 那一侧）
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
end $$;
revoke all on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) to authenticated;

-- 写回（以 20261026b 版为底；★2026-10-27 改四处，旧路任务逐字不变）：
--   ① 配对局（meta.pair）B 那一边照 A 的写法记：战绩互反 / 快照池 / 第 4 胜报名；账本多 gw_b / gl_b（res，也进 matches.result）
--   ② matches.right_account：配对局填 B（真人或陪练号都是真账号，填了不露馅；机器人池对手仍是 null）
--   ③ 账本 coins_b：周日决赛 + 配对局
--   ④ 这一局配出来的排队行 ⇒ done（旧路任务没有排队行）
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
        v_pair boolean; v_gw_b int; v_gl_b int;           -- 2026-10-27 在线瑞士轮
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

-- 查一局算完没有（以 20261023 版为底；★2026-10-27 配对局的 B 也能查，回包按 B 的视角；A 的回包对旧路任务逐字不变）
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
    || case when j.kind = 'gauntlet' and j.meta->>'pair' = 'true' then jsonb_build_object('side', 'a') else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ⑥ 清理：排队行留 14 天（任务行 referee_purge 也是 14 天）。每天 04:45 UTC。
select cron.unschedule(jobid) from cron.job where jobname = 'gauntlet_queue_purge';
select cron.schedule('gauntlet_queue_purge', '45 4 * * *',
  'delete from public.gauntlet_queue where joined_at < now() - interval ''14 days''');
-- <<< END gauntlet_online_queue 20261027 <<<
