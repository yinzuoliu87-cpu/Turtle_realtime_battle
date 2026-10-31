-- >>> BEGIN finals_sequential_premiere 20261101 >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛日：冠军杯赛一场接一场 / 小组赛同轮同时（2026-11-01 · 方案书 docs/plans/20261101-决赛日开播一场接一场.md）
--   用户 10-31「有任何商业游戏会同时播两个半决赛吗」；随后纠正「桶内的话…十六场同时开打，然后到第二轮八场同时开打，
--   第三轮四场同时开打…最多就是五轮」「桶内就是这样子同时跑，但是决赛里面就一定是一场场跑」。
--   原来 finals_advance 每组每轮固定 480 秒、到点整轮翻面；下一轮的 3 分钟备战也从翻面那一刻起算
--   ⇒ 下一轮对手在上一轮还在开播时就写出来了（剧透）。
--
-- 新规则（只在 finals_sequential_on() 时生效 = 裁判出结果 且 referee_config.finals_sequential，默认开）：
--   ① 翻面提前：备战结束 + finals_settle_sec()（60 秒）之后、本轮真实场次的裁判结果都齐了就翻（finals_advance 每分钟一次）；
--      原来固定等到 round_at + 480（备战结束后干等 5 分钟）。宽限（2 倍）与兜底（3 倍）仍按 finals_round_sec() 算，逐条不变。
--      倒计时 next_at = 最早翻面时刻（round_at + 180 + 60）；seq.settle_at = 备战结束时刻（客户端据此说「结算中 · 即将开播」）。
--   ② 翻面时给这一轮【有裁判录像的真实场次】排开播档期（finals_premiere_plan）；每场时长 = ceil(steps / 60) +
--      finals_premiere_intro_sec()（开场 VS ~6 秒 + 开场与路间幕布 ~25 秒，取 30）：
--        · 小组赛各桶：同一轮所有场次都 = 翻面时刻（同时开播）；本轮档期结束 = 翻面 + 最长那一场 + finals_premiere_gap_sec()。
--        · 冠军杯赛（finals_cup_no()）：按 match_no 一场接一场 —— 第 1 场 = 翻面时刻，下一场 = 上一场结束 + 间隔（25 秒：结束仪式最长 ~10 秒 + 余量）。
--        轮空 / 兜底判 / 坏快照判负（seed_used = 0，没有录像）不排档期 ⇒ 翻面即揭晓。
--   ③ 下一轮的 round_at（= 3 分钟备战开始）= 本轮档期结束（含最后一个间隔）⇒ 一轮全部播完才开下一轮备战，
--      下一轮对手在备战开始时才揭晓。round_at 在开播期间是「将来」的时刻 —— 购物窗 / 对手快照 / 建裁判任务
--      本来就按 round_at + finals_shop_sec() 判，未来的 round_at 让它们自然地「还没开始」。
--   ④ finals_buckets.premiere_until = 本次翻面排出来的档期整段结束（含最后一个间隔；没有档期 = 翻面时刻）；
--      非空 ⇔ 这一组最近一次翻面按新规则排了档期（客户端据此认新规则，空 ⇒ 老规则）。
--      冠军杯赛成表（finals_cup_seat）把「收盘了但组内决赛还在开播」的组也当没打完（否则组冠军的名字剧透决赛）。
--   ⑤ finals_view / finals_week_view 多回一个键 seq = {v: 1, until: unix, settle_at: unix, p: {"轮-场": [开播, 揭晓]}}
--      （p 只含已翻面的轮次，与 done 同一道可见性）；开关关且这一组没排过档期 ⇒ seq = null。老客户端只读具名键，多一个键不影响。
--   ⑥ 不同组之间照常并行（各组各自翻面、各自排档期）。
-- 开关：update referee_config set finals_sequential = false ⇒ 下一次翻面起回到老规则（480 秒翻面、同一轮同时开播、翻面即开下一轮备战）；
--   已排的档期不动（客户端按 seq 播完这一轮）。
-- 回滚：finals_advance / finals_cup_seat / finals_view / finals_week_view 换回 20261021_beta_server_clock 版；新列 / 新函数留着不影响。
-- ★重复执行安全（if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ① 列
alter table public.finals_results add column if not exists premiere_at timestamptz;   -- 这一场开播时刻（null = 不开播：轮空 / 兜底判 / 老规则）
alter table public.finals_results add column if not exists premiere_sec int;          -- 开播到揭晓几秒（= ceil(steps/60) + intro）
alter table public.finals_buckets add column if not exists premiere_until timestamptz; -- 最近一次翻面的档期整段结束（null = 老规则）
alter table public.referee_config add column if not exists finals_sequential boolean not null default true;

-- ② 常量（只在这里有一份；客户端不存副本，按 seq 里的时刻走）
create or replace function public.finals_premiere_intro_sec() returns int
language sql immutable as $$ select 30 $$;      -- 开场 VS ~6 秒 + 开场与路间幕布 ~25 秒（10-31 彩排实测）
create or replace function public.finals_premiere_gap_sec() returns int
language sql immutable as $$ select 25 $$;      -- 场间：结束仪式 看别人 ~4 / 自己赢 ~7 / 输 ~6 / 组冠军 ~10 秒 + 余量
create or replace function public.finals_settle_sec() returns int
language sql immutable as $$ select 60 $$;      -- 备战结束后至少等多久才翻面（内测服 10-31：裁判领取→写回中位 27 秒、建任务→领取中位 60 秒）
create or replace function public.finals_premiere_cap_sec() returns int
language sql immutable as $$ select 600 $$;     -- 一场对局时长上限（steps 异常大时不让一场占满整晚；正式服 14 天最长 171 秒）

create or replace function public.finals_sequential_on() returns boolean
language sql stable security definer set search_path = public as $$
  select public.referee_finals_on()
     and coalesce((select finals_sequential from public.referee_config where id = 1), true)
$$;
revoke all on function public.finals_sequential_on() from public, anon, authenticated;

-- ③ 排档期：给 (组, 轮) 有裁判录像的真实场次写 premiere_at / premiere_sec；返回本轮档期结束（含最后一个间隔）。
--   小组赛各桶 = 同时（都从翻面开始，结束 = 最长那场 + 间隔）；冠军杯赛 = 按 match_no 一场接一场（用户 10-31「决赛里面就一定是一场场跑」）。
--   ★只认「这一行结果就是这份裁判任务写的」（任务 done 且 seed_used = 任务种子；兜底判 = 0、被抢先写过的 superseded ≠ 任务种子）——
--     兜底判的那一场没有录像，排了档期观众只能对着「画面无法播放」干等。
create or replace function public.finals_premiere_plan(p_week bigint, p_bucket int, p_round int, p_flip timestamptz)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare s record; t timestamptz := p_flip; len int; v_cup boolean := p_bucket = public.finals_cup_no(); v_max int := -1;
begin
  for s in
    select r.match_no,
           case when jsonb_typeof(j.result->'steps') = 'number' then (j.result->>'steps')::numeric end as steps
      from public.finals_results r
      join public.referee_jobs j
        on j.match_key = format('finals:%s:%s:%s:%s', p_week, p_bucket, p_round, r.match_no)
     where r.season_week = p_week and r.bucket_no = p_bucket and r.round = p_round
       and j.kind = 'finals' and j.status = 'done'
       and r.seed_used = j.seed      -- 这一行结果就是这份任务写的（兜底判 seed_used = 0、被抢先写过的 superseded 都不是）
     order by r.match_no
  loop
    if s.steps is null or s.steps <= 0 then
      continue;
    end if;
    len := least(ceil(s.steps / 60.0)::int, public.finals_premiere_cap_sec()) + public.finals_premiere_intro_sec();
    if v_cup then
      update public.finals_results set premiere_at = t, premiere_sec = len
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = s.match_no;
      t := t + make_interval(secs => len + public.finals_premiere_gap_sec());
    else
      update public.finals_results set premiere_at = p_flip, premiere_sec = len
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = s.match_no;
      v_max := greatest(v_max, len);
    end if;
  end loop;
  if not v_cup and v_max >= 0 then
    t := p_flip + make_interval(secs => v_max + public.finals_premiere_gap_sec());
  end if;
  return t;
end $$;
revoke all on function public.finals_premiere_plan(bigint, int, int, timestamptz) from public, anon, authenticated;

-- ④ 读接口共用的 seq 段（finals_view / finals_week_view 的组与杯都走这一份）。可见性与 done 同一条：收盘 或 round < 当前轮。
--   开关开 ⇒ 每组都回（第 1 轮翻面之前 p 为空）；开关关 ⇒ 只有排过档期的组回（老档期照播完）。
--   settle_at = 本轮备战结束时刻（开关开、没收盘时；否则 0）。
drop function if exists public.finals_seq_json(bigint, int, int, boolean, timestamptz);
create or replace function public.finals_seq_json(p_week bigint, p_bucket int, p_round int, p_closed boolean,
    p_until timestamptz, p_round_at timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when p_until is null and not public.finals_sequential_on() then null else jsonb_build_object(
    'v', 1,
    'until', coalesce(extract(epoch from p_until)::bigint, 0),
    'settle_at', case when public.finals_sequential_on() and not p_closed
                      then extract(epoch from p_round_at)::bigint + public.finals_shop_sec() else 0 end,
    'p', coalesce((select jsonb_object_agg(r.round || '-' || r.match_no,
                     jsonb_build_array(extract(epoch from r.premiere_at)::bigint,
                                       extract(epoch from r.premiere_at)::bigint + r.premiere_sec))
                     from public.finals_results r
                    where r.season_week = p_week and r.bucket_no = p_bucket
                      and r.premiere_at is not null and r.premiere_sec is not null
                      and (p_closed or r.round < p_round)), '{}'::jsonb)) end
$$;
revoke all on function public.finals_seq_json(bigint, int, int, boolean, timestamptz, timestamptz) from public, anon, authenticated;
-- 倒计时（next_at）= 下一次最早翻面时刻：新规则 备战结束 + settle；老规则 round_at + 480
create or replace function public.finals_next_at(p_round_at timestamptz) returns bigint
language sql stable security definer set search_path = public as $$
  select extract(epoch from p_round_at)::bigint + case when public.finals_sequential_on()
           then public.finals_shop_sec() + public.finals_settle_sec() else public.finals_round_sec() end
$$;
revoke all on function public.finals_next_at(timestamptz) from public, anon, authenticated;

-- ⑤ finals_advance（以 20261021_beta_server_clock 版为底；★改两处：新规则下翻面闸 = 备战结束 + settle（结果齐才翻）；
--   翻面那一段排档期、下一轮 round_at = 档期结束、记 premiere_until）
create or replace function public.finals_advance(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; moved int := 0; want int; got int; slots int; total int;
        real_want int;
        v_seq boolean; v_flip timestamptz; v_next timestamptz;   -- 20261101 一场接一场
begin
  -- ★2026-10-19 服务器裁判: 购物窗一关就给本轮每一场真实对局建裁判任务(幂等; 开关关着时什么都不做)
  if public.referee_finals_on() then
    perform public.referee_enqueue_finals(p_week);
  end if;
  v_seq := public.finals_sequential_on();
  for b in select * from public.finals_buckets
            where season_week = p_week and not closed loop
    -- 本轮时间还没到就跳过。老规则：3 分钟购物 + 结算 ≈ 8 分钟（480）。
    -- ★20261101 新规则：备战结束 + finals_settle_sec() 之后就能翻（下面照旧要求真实场次的结果都齐了）；
    --   round_at 可能在将来（上一轮还在开播），这一条照样挡住。宽限 / 兜底仍按 finals_round_sec() 的 2 倍 / 3 倍。
    if public.app_now() < b.round_at + make_interval(secs => case when v_seq
         then public.finals_shop_sec() + public.finals_settle_sec() else public.finals_round_sec() end) then
      continue;
    end if;
    -- 补到 2 的幂 → 总轮数 / 本轮该有几场
    slots := 1; total := 0;
    while slots < b.n loop slots := slots * 2; total := total + 1; end loop;
    want := slots / (2 ^ b.round)::int;
    select count(*) into got from public.finals_results
     where season_week = p_week and bucket_no = b.bucket_no and round = b.round;
    -- ★没打完就不推 —— 宁可晚一分钟, 也不能把没结果的一轮翻面
    -- ★★★2026-09-26: 只等【真的有人打的那几场】, 不等轮空（第 1 轮真实场次 = n - slots/2）。
    real_want := want;
    if b.round = 1 then
      real_want := greatest(0, b.n - slots / 2);
    end if;
    if got < real_want then
      -- 宽限期内: 真的等一等（2 倍本轮时长）
      if public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 2) then
        continue;
      end if;
      null;   -- 补判由下面那条 insert 做
    end if;
    if public.referee_finals_on()
       and public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 3) then
      -- ★2026-10-19 服务器裁判: 真实场次只认裁判写回的结果, 这里只补轮空; 硬上限 3 倍本轮时长后走 else 兜底
      insert into public.finals_results
        (season_week, bucket_no, round, match_no, winner_side, seed_used)
        select p_week, b.bucket_no, b.round, g.m, 0, 0
          from generate_series(0, want - 1) as g(m)
         where b.round = 1
           and not (public.finals_seed_at_seat(slots, 2 * g.m + 1) between 0 and b.n - 1)
        on conflict (season_week, bucket_no, round, match_no) do nothing;
      select count(*) into got from public.finals_results
       where season_week = p_week and bucket_no = b.bucket_no and round = b.round;
      if got < want then
        continue;                        -- 还有真实场次在等裁判
      end if;
    else
      insert into public.finals_results
        (season_week, bucket_no, round, match_no, winner_side, seed_used)
        select p_week, b.bucket_no, b.round, g.m, 0, 0
          from generate_series(0, want - 1) as g(m)
        on conflict (season_week, bucket_no, round, match_no) do nothing;
    end if;
    -- ★20261101 翻面: 一场接一场 ⇒ 排档期, 下一轮备战从档期结束起算; 老规则 ⇒ 与原来逐值相同（round_at = 翻面时刻、premiere_until = null）
    v_flip := public.app_now();
    v_next := v_flip;
    if v_seq then
      v_next := public.finals_premiere_plan(p_week, b.bucket_no, b.round, v_flip);
    end if;
    if b.round >= total then
      update public.finals_buckets set closed = true, revealed_at = v_flip,
             premiere_until = case when v_seq then v_next end
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = v_next, revealed_at = v_flip,
             premiere_until = case when v_seq then v_next end
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;
revoke all on function public.finals_advance(bigint) from public;
revoke execute on function public.finals_advance(bigint) from anon, authenticated;

-- ⑥ finals_cup_seat（以 20261021_beta_server_clock 版为底；★只改「还有组没打完」的口径：收盘了但档期没播完的组也算没打完）
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
      values (p_week, cup, i, r.account_id, r.name, r.snapshot);
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

-- ⑦ finals_view（以 20261021_beta_server_clock 版为底；★多回一个键 seq、next_at 按新规则）
CREATE OR REPLACE FUNCTION public.finals_view(p_week bigint, p_bucket integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b record; ents jsonb; res jsonb; sc jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★p_bucket < 0 = 「我那个桶」（分桶是服务端做的，并进这一次往返）
  if p_bucket < 0 then
    select e.bucket_no into p_bucket from public.finals_entrants e
     where e.season_week = p_week and e.account_id = auth.uid()
       and e.bucket_no <> public.finals_cup_no()   -- ★冠军杯赛 2026-10-07: 「我那个组」只认小组赛
     limit 1;
    if p_bucket is null then
      -- ★2026-09-25: 「没资格」与「有资格但人不够、赛没开起来」分开说
      if exists (select 1 from public.finals_pending
                  where season_week = p_week and account_id = auth.uid()) then
        -- ★2026-10-04: 本周还一个桶都没有 = 还没到分组时间, 不是人太少
        if not exists (select 1 from public.finals_buckets where season_week = p_week) then
          return jsonb_build_object('ok', false, 'reason', 'not_seated',
            'entered', (select count(*) from public.finals_pending where season_week = p_week));
        end if;
        return jsonb_build_object('ok', false, 'reason', 'too_few',
          'entered', (select count(*) from public.finals_pending where season_week = p_week));
      end if;
      return jsonb_build_object('ok', false, 'reason', 'not_entered');
    end if;
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('seed', seed, 'name', name,
           'account_id', account_id) order by seed), '[]'::jsonb)
    into ents from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket;
  -- ★★只取 round < 当前轮 —— 当前轮的结果根本不下发；收盘了就全给
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
    into res from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  -- ★2026-10-12 比分: 与 done 同一道可见性
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes)
           filter (where r.loser_lanes is not null), '{}'::jsonb)
    into sc from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻（= 本轮最早翻面时刻；20261101 新规则 备战结束 + 60 秒）
    'next_at', public.finals_next_at(b.round_at),
    'now', extract(epoch from public.app_now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res, 'scores', sc,
    -- ★20261101 一场接一场: 每场开播 / 揭晓时刻（老规则 = null）
    'seq', public.finals_seq_json(p_week, p_bucket, b.round, b.closed, b.premiere_until, b.round_at));
end $function$;

-- ⑧ finals_week_view（以 20261021_beta_server_clock 版为底；★组与杯各多回一个键 seq、杯的 next_at 按新规则）
CREATE OR REPLACE FUNCTION public.finals_week_view(p_week bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bs jsonb; cp jsonb; cup int := public.finals_cup_no();
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           'round_at', extract(epoch from b.round_at)::bigint,
           'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
           'entrants', (select coalesce(jsonb_agg(jsonb_build_object(
                           'seed', e.seed, 'name', e.name, 'account_id', e.account_id)
                         order by e.seed), '[]'::jsonb)
                          from public.finals_entrants e
                         where e.season_week = p_week and e.bucket_no = b.bucket_no),
           'done', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)),
           'scores', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes) filter (where r.loser_lanes is not null), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)),
           'seq', public.finals_seq_json(p_week, b.bucket_no, b.round, b.closed, b.premiere_until, b.round_at))   -- 20261101
         order by b.bucket_no), '[]'::jsonb)
    into bs from public.finals_buckets b
   where b.season_week = p_week
     and b.bucket_no <> cup;               -- ★冠军杯赛 2026-10-07: 杯不进组列表
  select jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           'round_at', extract(epoch from b.round_at)::bigint,
           'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
           'next_at', public.finals_next_at(b.round_at),   -- 20261101
           'entrants', (select coalesce(jsonb_agg(jsonb_build_object(
                           'seed', e.seed, 'name', e.name, 'account_id', e.account_id)
                         order by e.seed), '[]'::jsonb)
                          from public.finals_entrants e
                         where e.season_week = p_week and e.bucket_no = b.bucket_no),
           'done', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)),
           'scores', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes) filter (where r.loser_lanes is not null), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)),
           'seq', public.finals_seq_json(p_week, b.bucket_no, b.round, b.closed, b.premiere_until, b.round_at))   -- 20261101
    into cp from public.finals_buckets b
   where b.season_week = p_week and b.bucket_no = cup;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from public.app_now())::bigint, 'buckets', bs, 'cup', cp);
end $function$;
-- <<< END finals_sequential_premiere 20261101 <<<
