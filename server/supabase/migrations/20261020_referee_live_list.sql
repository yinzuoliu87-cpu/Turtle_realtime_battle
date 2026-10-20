-- >>> BEGIN referee_live_list 20261020 >>>
-- ─────────────────────────────────────────────────────────────
-- 逐帧直播 · 周六观赛「正在算」的裁判局 + 旧裁判局按需补流（2026-10-20 · 方案书 docs/plans/20261019-服务器逐帧直播.md §4.1 / §5）
--   ★只写文件、未上生产。前提：20261019_referee_jobs.sql（referee_jobs / referee_config / referee_versions）已执行。
--
-- 本段内容（全是添加，或给只读函数多回一个键；执行本段不改变任何现行行为）：
--   ① referee_live_gauntlet()               本周周六正在算（status = claimed、租期内）的闯关裁判任务（赛况板「观赛」）。
--      只回 match_id / 开始时刻 / 版本 / 种子 / 双方 profile 的名字·头像·#ID；★不回快照（阵容 / 装备）。
--      anon 不可，authenticated 可。种子只用来让手机选同一张地图（结果由服务器算，手机不算）。
--   ② referee_restream（表）+ referee_request_restream(p_match_id)（authenticated）：
--      开流之前算的裁判局（或录流失败过的）没有状态流 ⇒ 客户端请求补流：裁判机按原任务的快照 + 种子再算一遍，**只产出流**，
--      不写回结果、不改账（不调 referee_complete）。同一场只排一次（match_id 主键）；排队上限 50；
--      done / failed 超过 10 分钟的可以重排（流被清掉了 / 上次失败了）。
--      referee_claim_restream(...) / referee_restream_done(...)：只有 service_role（裁判机轮询器，server/referee/referee_poller.py）。
--      任务单形状 = referee_claim 的那一份 + task = 'restream' + expect_winner / expect_digest（原结果；重算对不上 ⇒ 撤流、判失败）。
--   ③ finals_replay() 多回一个键 referee（这一行是不是裁判写回的：matches.result->>'referee'），正文其余逐字照抄 schema.sql 现行版。
--      客户端（scripts/net/match_fetch.gd）认出裁判局 ⇒ 没有流时请求补流，永不本机重算。
--   客户端：scripts/net/referee_net.gd（live_gauntlet_async / request_restream_async）、scripts/systems/replay/stream_watch.gd。
--   客户端读不到（本段没上 = 404）⇒ 赛况板照旧只有直播行；补流请求 404 ⇒ 屏上「画面无法播放」（与改之前相同）。
-- ★重复执行安全（create if not exists / create or replace / unschedule 再 schedule）。
-- ─────────────────────────────────────────────────────────────

-- ① 周六正在算的裁判局 ─────────────────────────────────────
create or replace function public.referee_live_gauntlet()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg record; wk bigint; v jsonb;
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;
  select * into cfg from public.referee_config where id = 1;
  wk := extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
  select coalesce(jsonb_agg(jsonb_build_object(
           'match_id', j.match_id, 'started_at', j.claimed_at, 'updated_at', now(),
           'client_version', j.client_version, 'seed', j.seed,
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

-- ② 按需补流 ─────────────────────────────────────────────────
create table if not exists public.referee_restream (
  match_id       uuid        primary key,                 -- = 原任务 / 录像 / 状态流目录的 match_id
  job_id         bigint      not null,                    -- 原任务（快照 / 种子 / 等级 / 版本都从它取）
  client_version text        not null,
  status         text        not null default 'pending' check (status in ('pending', 'claimed', 'done', 'failed')),
  attempts       int         not null default 0,
  claimed_by     text,
  claimed_at     timestamptz,
  error          text,
  requested_by   uuid,
  created_at     timestamptz not null default now(),
  done_at        timestamptz
);
create index if not exists referee_restream_queue_idx on public.referee_restream (status, created_at)
  where status in ('pending', 'claimed');
alter table public.referee_restream enable row level security;
-- 没有任何策略 ⇒ 客户端直连读写都不行；只有下面的 security definer 函数碰得到

create or replace function public.referee_request_restream(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m record; j record; ex record; n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select match_id, result into m from public.matches where match_id = p_match_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_match');
  end if;
  if coalesce(m.result->>'referee', 'false') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', 'not_referee');     -- 本机局：手机重算那条路，不归裁判机
  end if;
  select * into ex from public.referee_restream where match_id = p_match_id;
  if found and not (ex.status in ('done', 'failed') and ex.done_at < now() - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'status', ex.status);
  end if;
  select job_id, client_version into j from public.referee_jobs
   where match_id = p_match_id and status = 'done' and kind in ('gauntlet', 'finals')
   order by job_id desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');          -- 原任务已清（14 天）
  end if;
  if not exists (select 1 from public.referee_versions where client_version = j.client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'no_version');      -- 裁判机已不装那个版本
  end if;
  select count(*) into n from public.referee_restream where status in ('pending', 'claimed');
  if n >= 50 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;
  insert into public.referee_restream (match_id, job_id, client_version, requested_by)
    values (p_match_id, j.job_id, j.client_version, uid)
    on conflict (match_id) do update
      set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
          job_id = excluded.job_id, client_version = excluded.client_version,
          requested_by = excluded.requested_by, created_at = now()
      where public.referee_restream.status in ('done', 'failed');
  return jsonb_build_object('ok', true, 'status', 'pending');
end $$;
revoke all on function public.referee_request_restream(uuid) from public, anon;
grant execute on function public.referee_request_restream(uuid) to authenticated;

-- 裁判机领补流任务（正常任务领不到时才来领：轮询器先 referee_claim，空了才 referee_claim_restream）。
create or replace function public.referee_claim_restream(p_worker text, p_versions text[], p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_out jsonb;
begin
  select * into cfg from public.referee_config where id = 1;
  update public.referee_restream
     set status = 'failed', error = coalesce(error, 'lease_expired'), done_at = now()
   where status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)
     and attempts >= cfg.max_attempts;
  with c as (
    select r.match_id from public.referee_restream r
     where r.client_version = any(coalesce(p_versions, '{}'))
       and (r.status = 'pending'
            or (r.status = 'claimed' and r.claimed_at < now() - make_interval(secs => cfg.lease_sec)))
     order by r.created_at, r.match_id
     limit greatest(1, least(coalesce(p_limit, 1), 8))
     for update skip locked
  ), u as (
    update public.referee_restream r
       set status = 'claimed', claimed_by = p_worker, claimed_at = now(), attempts = r.attempts + 1
      from c where r.match_id = c.match_id
    returning r.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'v', 1, 'task', 'restream', 'job_id', j.job_id, 'match_id', j.match_id, 'mode', j.kind,
           'key', j.meta || jsonb_build_object('week', j.season_week, 'match_key', j.match_key),
           'seed', j.seed, 'client_version', j.client_version, 'level', j.level,
           'a', j.a_snapshot, 'b', j.b_snapshot,
           'expect_winner', j.result->>'winner', 'expect_digest', j.result->>'digest') order by u.created_at), '[]'::jsonb)
    into v_out
    from u join public.referee_jobs j on j.job_id = u.job_id;
  return v_out;
end $$;
revoke all on function public.referee_claim_restream(text, text[], int) from public, anon, authenticated;
grant execute on function public.referee_claim_restream(text, text[], int) to service_role;

-- 补流写回：只记状态（流本身已由轮询器发布到裁判机的对外目录）。★不碰 matches / 赛果 / 账本。
create or replace function public.referee_restream_done(p_match_id uuid, p_worker text, p_ok boolean,
    p_error text default null, p_permanent boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; n int;
begin
  select * into cfg from public.referee_config where id = 1;
  update public.referee_restream
     set status = case when coalesce(p_ok, false) then 'done'
                       when coalesce(p_permanent, false) or attempts >= cfg.max_attempts then 'failed'
                       else 'pending' end,
         done_at = case when coalesce(p_ok, false) or coalesce(p_permanent, false) or attempts >= cfg.max_attempts
                        then now() end,
         error = case when coalesce(p_ok, false) then null else left(coalesce(p_error, '?'), 500) end,
         claimed_by = null, claimed_at = null
   where match_id = p_match_id and status = 'claimed' and claimed_by = p_worker;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;
revoke all on function public.referee_restream_done(uuid, text, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.referee_restream_done(uuid, text, boolean, text, boolean) to service_role;

-- 清理：结束超过 14 天的补流记录（与 referee_purge 同口径）。每天 04:45 UTC。
create or replace function public.referee_restream_purge() returns void
language sql security definer as $$
  delete from public.referee_restream where status in ('done', 'failed') and done_at < now() - interval '14 days';
$$;
revoke all on function public.referee_restream_purge() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'referee_restream_purge';
select cron.schedule('referee_restream_purge', '45 4 * * *', 'select public.referee_restream_purge()');

-- ③ finals_replay 多回 referee（正文照抄 schema.sql 现行版，只改了 select 多取 result 与最后一行回包）─────
create or replace function public.finals_replay(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b record; sd bigint; mid uuid; rp text; res jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if not (b.closed or p_round < b.round) then
    return jsonb_build_object('ok', false, 'reason', 'not_revealed');
  end if;
  select r.seed_used into sd from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and r.round = p_round and r.match_no = p_match;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_result');
  end if;
  if coalesce(sd, 0) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'no_replay');
  end if;
  select m.match_id, m.replay, m.result into mid, rp, res from public.matches m
   where m.season_week = p_week and m.phase = 'finals' and m.seed = sd
     and m.replay is not null
     and m.result->>'fb' = p_bucket::text
     and m.result->>'fr' = p_round::text
     and m.result->>'fm' = p_match::text
     and exists (select 1 from public.finals_entrants e
                  where e.season_week = p_week and e.bucket_no = p_bucket
                    and e.account_id = m.left_account)
   order by m.created_at
   limit 1;
  if mid is null then
    return jsonb_build_object('ok', false, 'reason', 'no_replay');
  end if;
  return jsonb_build_object('ok', true, 'match_id', mid, 'replay', rp,
                            'referee', coalesce(res->>'referee', 'false') = 'true');
end $$;

revoke all on function public.finals_replay(bigint, int, int, int) from public;
revoke execute on function public.finals_replay(bigint, int, int, int) from anon;
grant execute on function public.finals_replay(bigint, int, int, int) to authenticated;
-- <<< END referee_live_list 20261020 <<<
