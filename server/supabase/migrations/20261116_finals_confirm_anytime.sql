-- >>> BEGIN finals_confirm_anytime 20261116 >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛：背包「确定阵容」什么时候交都算（2026-11-16 · 方案书 docs/plans/20261116b-周末确定阵容按钮.md §4.2）
--   用户 11-16「加个按钮，就加在背包里面…点确定阵容的时候，就顺便把那个选择技能…跳出来让玩家选择」。
--   原来（20261101b）只在每一轮开打后 180 秒（备战窗）里收；窗外交的一律拒 ⇒ 背包里提前调好的阵容不算（11-15 LouisT01）。
--
--   ① finals_entrants 加两列 pending_snapshot / pending_at：备战窗外交的先存「待生效」。
--   ② finals_confirm_snapshot(周, 快照) → {ok, applies} / {ok:false, reason}（新客户端只调它；旧的 finals_update_snapshot 不动，0.23.4 照用）：
--      · 校验同 finals_update_snapshot：≤ 64 KB、referee_lineup_ok（开得了打）—— 不过 ⇒ reason too_big / bad_lineup，什么都不写
--      · 还没分组（本周没有 finals_buckets）⇒ 写进 finals_pending（finals_seat 入座时取它）⇒ applies 'seat'；没晋级 ⇒ not_entered
--      · 已分组、我在一张没收盘的表里（冠军杯优先）：
--          备战窗内 ⇒ 直接写 snapshot（本轮就用）⇒ 'now'；窗外 ⇒ 写 pending_snapshot / pending_at ⇒ 'next'
--      · 小组已收盘、我是组冠军、冠军杯还没成表 ⇒ 写组里那一行的 pending（finals_cup_seat 成表时带上）⇒ 'cup'
--      · 别的（已被淘汰 / 没参赛）⇒ closed
--   ③ referee_enqueue_finals：每张表建本轮任务之前，把「锁定（round_at + 备战秒数）之前」交的 pending 换上；锁定之后交的留给下一轮
--      ⇒「每轮锁定前最后一次为准」按服务端时钟判，跟玩家什么时候在线无关。
--   ④ finals_cup_seat：组冠军进杯时优先用他组里那一行的 pending。
-- 以 20261101b 版为底（③④ 两个函数整体重定义，只加标 20261116 的几行）。
-- 回滚：③④ 换回 20261101b 版；drop function finals_confirm_snapshot；两列留着不影响。
-- ★重复执行安全（add column if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

alter table public.finals_entrants add column if not exists pending_snapshot jsonb;
alter table public.finals_entrants add column if not exists pending_at timestamptz;

-- ② 确定阵容
create or replace function public.finals_confirm_snapshot(p_week bigint, p_snapshot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cup int := public.finals_cup_no(); e record; n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'too_big');
  end if;
  if not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_lineup');
  end if;
  -- 还没分组：写进晋级那一行（finals_seat 入座时取它）
  if not exists (select 1 from public.finals_buckets where season_week = p_week) then
    update public.finals_pending set snapshot = p_snapshot where season_week = p_week and account_id = uid;
    get diagnostics n = row_count;
    if n > 0 then
      return jsonb_build_object('ok', true, 'applies', 'seat');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'not_entered');
  end if;
  -- 我此刻在打的那一张：冠军杯里有我且没收盘 ⇒ 杯；否则我那一组且没收盘
  select en.bucket_no, bu.round_at into e
    from public.finals_entrants en
    join public.finals_buckets bu on bu.season_week = en.season_week and bu.bucket_no = en.bucket_no
   where en.season_week = p_week and en.account_id = uid and not bu.closed
   order by (en.bucket_no = cup) desc
   limit 1;
  if found then
    if public.app_now() < e.round_at + make_interval(secs => public.finals_shop_sec()) then
      update public.finals_entrants set snapshot = p_snapshot, pending_snapshot = null, pending_at = null
       where season_week = p_week and bucket_no = e.bucket_no and account_id = uid;
      return jsonb_build_object('ok', true, 'applies', 'now');
    end if;
    update public.finals_entrants set pending_snapshot = p_snapshot, pending_at = public.app_now()
     where season_week = p_week and bucket_no = e.bucket_no and account_id = uid;
    return jsonb_build_object('ok', true, 'applies', 'next');
  end if;
  -- 小组已收盘、我是组冠军、冠军杯还没成表 ⇒ 存组里那一行的待生效（finals_cup_seat 成表时带上）
  if not exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    update public.finals_entrants en set pending_snapshot = p_snapshot, pending_at = public.app_now()
     where en.season_week = p_week and en.account_id = uid and en.bucket_no <> cup
       and en.seed = public.finals_champion_seed(p_week, en.bucket_no);
    get diagnostics n = row_count;
    if n > 0 then
      return jsonb_build_object('ok', true, 'applies', 'cup');
    end if;
  end if;
  return jsonb_build_object('ok', false, 'reason', 'closed');
end $$;
revoke all on function public.finals_confirm_snapshot(bigint, jsonb) from public, anon;
grant execute on function public.finals_confirm_snapshot(bigint, jsonb) to authenticated;

-- ④ finals_cup_seat（以 20261101b 版为底；★20261116：组冠军进杯优先用组里那一行的待生效阵容）
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
    select e.account_id, e.name, coalesce(e.pending_snapshot, e.snapshot) as snapshot,   -- 20261116
           coalesce(p.gw, 0) as gw, coalesce(p.gl, 0) as gl
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

-- ③ referee_enqueue_finals（以 20261101b 版为底；★20261116：建本轮任务前，把锁定前交的待生效阵容换上）
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
    -- ★20261116 本轮锁定（round_at + 备战秒数）之前交的待生效阵容，建任务前换上；锁定之后交的留给下一轮
    update public.finals_entrants
       set snapshot = pending_snapshot, pending_snapshot = null, pending_at = null
     where season_week = p_week and bucket_no = b.bucket_no and pending_snapshot is not null
       and pending_at < b.round_at + make_interval(secs => public.finals_shop_sec());
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
-- <<< END finals_confirm_anytime 20261116 <<<
