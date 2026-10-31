-- >>> BEGIN finals_snapshot_guard 20261101b >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛日：服务端快照校验 + 坏快照回退（2026-11-01 · 方案书 docs/plans/20261101-决赛日开播一场接一场.md §4.5 · 上级 20261031c 块 V / P21）
--   10-31 彩排 P21：快照不验（0 统领也收）；裁判判 a_bad_snapshot（永久失败）后 finals_advance 只能等满 3 倍本轮时长（24 分钟）
--   再按「缺哪场补哪场 side 0」兜底 ⇒ 整组干等 24 分钟，而交了坏阵容的上半区反而晋级。
-- ★必须在 20261101_finals_sequential_premiere 之后执行（finals_cup_seat 以那一版为底）；20261101 若重跑，要再跑一次本段。
--
-- 判据 = public.referee_lineup_ok（20261020c；与裁判 RefereeJob.validate + _state_from_snapshot 同一组条件：
--   三只不同的统领、lane_assign 的 top / bottom 都是数组、每只统领在两路里恰好出现一次）。周日两侧都可能当左方（A），一律用它。
--
--   ① finals_good_snapshot(周, 账号, 现在这份)：第一份能开打的 —— 现在这份 → 入座时那份（finals_pending）→ 本周闯关赛上传过的
--      （gauntlet_ghosts，最新的在前）；都不行 ⇒ null。
--   ② finals_update_snapshot：备战时推上来的快照不能开打 ⇒ 拒收（原来只看「统领 ≥ 3 只」）；旧的那份（入座时验过的）留着。
--   ③ finals_seat / ④ finals_cup_seat：入座时就换成能开打的那份；一份都没有 ⇒ 照原样坐下（到建任务时判他负）。
--   ⑤ referee_enqueue_finals：建任务前两侧各取一份能开打的（取到了而与现在那份不同 ⇒ 顺手写回参赛者，下一轮也用它）；
--      · 某一侧一份都没有 ⇒ 当场判这一场：没有的那一侧负（两侧都没有 ⇒ 上半区 side 0 晋级）；不建任务、不等。
--      · 裁判已经判过 a_bad_snapshot / b_bad_snapshot（永久失败）：两侧回退后的快照与任务里的不同 ⇒ 换上、任务退回 pending 重算；
--        相同（裁判与本函数判据不一致，或回退不出别的）⇒ 当场判坏的那一侧负。
--      判出来的结果 seed_used = 0（没有录像）⇒ 不排开播档期、翻面即揭晓；本轮其余场次一齐 ⇒ 按 20261101 的翻面闸（备战结束 + 60 秒）翻面。
-- 回滚：四个函数换回 20261101（finals_cup_seat）/ 20261021（另三个）版；finals_good_snapshot 留着不影响。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ① 一份能开打的快照
create or replace function public.finals_good_snapshot(p_week bigint, p_account uuid, p_cur jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb;
begin
  if public.referee_lineup_ok(p_cur) then
    return p_cur;
  end if;
  select p.snapshot into s from public.finals_pending p
   where p.season_week = p_week and p.account_id = p_account;
  if found and public.referee_lineup_ok(s) then
    return s;
  end if;
  for s in select g.snapshot from public.gauntlet_ghosts g
            where g.season_week = p_week and g.account_id = p_account
            order by g.uploaded_at desc, g.gw desc, g.gl asc loop
    if public.referee_lineup_ok(s) then
      return s - 'origin';            -- 同 gauntlet_queue_advance 取快照池那一份的写法
    end if;
  end loop;
  return null;
end $$;
revoke all on function public.finals_good_snapshot(bigint, uuid, jsonb) from public, anon, authenticated;

-- ② finals_update_snapshot（以 20261021_beta_server_clock 版为底；★只换第一道闸：能不能开打用 referee_lineup_ok）
create or replace function public.finals_update_snapshot(p_week bigint, p_bucket int, p_snapshot jsonb)
returns boolean
language plpgsql security definer set search_path = public as $$
declare b record; n int;
begin
  if auth.uid() is null or p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
     or octet_length(p_snapshot::text) > 65536
     or not public.referee_lineup_ok(p_snapshot) then
    return false;                       -- 开不了打的快照不收（20261101b；原来只看统领 ≥ 3 只）—— 旧的那份留着
  end if;
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return false;
  end if;
  if public.app_now() >= b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return false;                       -- 购物结束 = 本轮阵容锁定
  end if;
  update public.finals_entrants set snapshot = p_snapshot
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.finals_update_snapshot(bigint, int, jsonb) from public, anon;
grant execute on function public.finals_update_snapshot(bigint, int, jsonb) to authenticated;

-- ③ finals_seat（以 20261021_beta_server_clock 版为底；★只改入座那一行的快照：换成能开打的那份）
create or replace function public.finals_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare total int; nb int; r record; i int := 0; seats int[] := '{}'; b int;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week) then
    return 0;                      -- 已经坐定了, 再叫一次什么都不做
  end if;
  select count(*) into total from public.finals_pending where season_week = p_week;
  if total < 2 then
    return 0;                      -- 一个人不成比赛
  end if;
  nb := public.finals_bucket_count(total);
  -- 每个桶下一个空位的序号
  for i in 1..nb loop seats := array_append(seats, 0); end loop;
  i := 0;
  -- ★排序 = 种子顺序: 胜场多的在前, 同胜场负场少的在前, 再同就按 account_id 定死
  for r in select * from public.finals_pending
            where season_week = p_week
            order by gw desc, gl asc, account_id loop
    b := public.finals_bucket_of(i, nb);
    insert into public.finals_entrants
      (season_week, bucket_no, seed, account_id, name, snapshot)
      values (p_week, b, seats[b + 1], r.account_id, r.name,
              coalesce(public.finals_good_snapshot(p_week, r.account_id, r.snapshot), r.snapshot));   -- 20261101b
    seats[b + 1] := seats[b + 1] + 1;
    i := i + 1;
  end loop;
  -- 桶本身（n = 这个桶真实坐了几个人，可能比容量少）；1 人组坐下即收盘
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    select p_week, bucket_no, count(*)::int, 1, public.app_now(), count(*) = 1,
           case when count(*) = 1 then public.app_now() else null end
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;
revoke all on function public.finals_seat(bigint) from public;
revoke execute on function public.finals_seat(bigint) from anon, authenticated;

-- ④ finals_cup_seat（以 20261101_finals_sequential_premiere 版为底；★只改入座那一行的快照：换成能开打的那份）
create or replace function public.finals_cup_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare cup int := public.finals_cup_no(); start_at timestamptz; ngroups int; nopen int;
        r record; i int := 0;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    return 0;
  end if;
  start_at := to_timestamp(p_week + 6 * 86400 + public.finals_cup_hour() * 3600);
  if public.app_now() < start_at then
    return 0;
  end if;
  select count(*),
         count(*) filter (where not closed or coalesce(premiere_until > public.app_now(), false))   -- 20261101
    into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and public.app_now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
    return 0;                            -- 还有组没打完（或组内决赛还在开播）：等它（最多等 finals_cup_wait_sec）
  end if;
  for r in
    select e.account_id, e.name, e.snapshot, coalesce(p.gw, 0) as gw, coalesce(p.gl, 0) as gl
      from (select b.bucket_no, public.finals_champion_seed(p_week, b.bucket_no) as cs
              from public.finals_buckets b
             where b.season_week = p_week and b.bucket_no <> cup and b.closed) c
      join public.finals_entrants e
        on e.season_week = p_week and e.bucket_no = c.bucket_no and e.seed = c.cs
      left join public.finals_pending p
        on p.season_week = p_week and p.account_id = e.account_id
     order by gw desc, gl asc, e.account_id
  loop
    insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
      values (p_week, cup, i, r.account_id, r.name,
              coalesce(public.finals_good_snapshot(p_week, r.account_id, r.snapshot), r.snapshot));   -- 20261101b
    i := i + 1;
  end loop;
  if i = 0 then
    return 0;
  end if;
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    values (p_week, cup, i, 1, public.app_now(), i <= 1, case when i <= 1 then public.app_now() else null end);
  return i;
end $$;
revoke all on function public.finals_cup_seat(bigint) from public;
revoke execute on function public.finals_cup_seat(bigint) from anon, authenticated;

-- ⑤ referee_enqueue_finals（以 20261021_beta_server_clock 版为底；★建任务前两侧各取一份能开打的；取不到 / 裁判判过坏快照 ⇒ 当场判）
create or replace function public.referee_enqueue_finals(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; ea record; eb record; slots int; n_match int; m int; s0 int; s1 int;
        ver text; added int := 0; k int;
        sa jsonb; sb jsonb; jb record; mk text;              -- 20261101b
begin
  if not public.referee_finals_on() then
    return 0;
  end if;
  select finals_version into ver from public.referee_config where id = 1;
  if coalesce(ver, '') = '' or not exists (select 1 from public.referee_versions
                                            where client_version = ver and enabled) then
    return 0;                            -- 没定版本 / 裁判机没装这个版本 ⇒ 不建（finals_advance 的 3 倍时长兜底照样在）
  end if;
  for b in select * from public.finals_buckets where season_week = p_week and not closed loop
    if public.app_now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
      continue;                          -- 还在购物
    end if;
    slots := 1;
    while slots < greatest(b.n, 1) loop
      slots := slots * 2;
    end loop;
    n_match := greatest(1, slots / (2 ^ b.round)::int);
    for m in 0 .. n_match - 1 loop
      if exists (select 1 from public.finals_results
                  where season_week = p_week and bucket_no = b.bucket_no and round = b.round and match_no = m) then
        continue;
      end if;
      s0 := public.referee_finals_occupant(p_week, b.bucket_no, b.round, m, 0);
      s1 := public.referee_finals_occupant(p_week, b.bucket_no, b.round, m, 1);
      if s0 is null or s1 is null then
        continue;                        -- 轮空（finals_advance 补 side 0）/ 上一轮还没出结果
      end if;
      select * into ea from public.finals_entrants where season_week = p_week and bucket_no = b.bucket_no and seed = s0;
      if not found then
        continue;
      end if;
      select * into eb from public.finals_entrants where season_week = p_week and bucket_no = b.bucket_no and seed = s1;
      if not found then
        continue;
      end if;
      -- ★20261101b 两侧各取一份能开打的；取到了而与现在那份不同 ⇒ 写回参赛者（之后几轮也用它）
      sa := public.finals_good_snapshot(p_week, ea.account_id, ea.snapshot);
      sb := public.finals_good_snapshot(p_week, eb.account_id, eb.snapshot);
      if sa is not null and sa is distinct from ea.snapshot then
        update public.finals_entrants set snapshot = sa
         where season_week = p_week and bucket_no = b.bucket_no and seed = s0;
      end if;
      if sb is not null and sb is distinct from eb.snapshot then
        update public.finals_entrants set snapshot = sb
         where season_week = p_week and bucket_no = b.bucket_no and seed = s1;
      end if;
      mk := format('finals:%s:%s:%s:%s', p_week, b.bucket_no, b.round, m);
      select * into jb from public.referee_jobs where match_key = mk;
      if found and jb.status = 'failed' and jb.error in ('a_bad_snapshot', 'b_bad_snapshot') then
        if sa is not null and sb is not null
           and (sa is distinct from jb.a_snapshot or sb is distinct from jb.b_snapshot) then
          -- 回退出了与任务里不同的快照 ⇒ 换上、退回 pending 重算
          update public.referee_jobs
             set a_snapshot = sa, b_snapshot = sb, level = public.referee_level_of(sa),
                 status = 'pending', attempts = 0, error = null, done_at = null, claimed_by = null, claimed_at = null
           where job_id = jb.job_id;
          added := added + 1;
        else
          -- 裁判说坏、回退不出别的 ⇒ 坏的那一侧负（不等 3 倍时长、不再按 side 0 兜底）
          insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
            values (p_week, b.bucket_no, b.round, m, case when jb.error = 'a_bad_snapshot' then 1 else 0 end, 0)
            on conflict (season_week, bucket_no, round, match_no) do nothing;
        end if;
        continue;
      end if;
      if sa is null or sb is null then
        -- 一份能开打的都没有 ⇒ 当场判：没有的那一侧负；两侧都没有 ⇒ 上半区（side 0）晋级
        insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
          values (p_week, b.bucket_no, b.round, m, case when sa is null and sb is not null then 1 else 0 end, 0)
          on conflict (season_week, bucket_no, round, match_no) do nothing;
        continue;
      end if;
      insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
          a_account, b_account, a_snapshot, b_snapshot, level, meta)
        values ('finals', mk, p_week, ver,
          public.referee_new_seed(), ea.account_id, eb.account_id, sa, sb,
          public.referee_level_of(sa),
          jsonb_build_object('bucket', b.bucket_no, 'round', b.round, 'match', m, 'seed0', s0, 'seed1', s1))
        on conflict (match_key) do nothing;
      get diagnostics k = row_count;
      added := added + k;
    end loop;
  end loop;
  return added;
end $$;
revoke all on function public.referee_enqueue_finals(bigint) from public, anon, authenticated;
-- <<< END finals_snapshot_guard 20261101b <<<
