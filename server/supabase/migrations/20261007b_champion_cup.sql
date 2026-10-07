-- >>> BEGIN champion_cup 20261007b >>>
-- ─────────────────────────────────────────────────────────────
-- 冠军杯赛（2026-10-07 · 方案书 docs/plans/20261007-冠军杯赛.md）—— ★待主会话审后上线
--   用户原话：「那么上午就叫小组赛啊，晚上叫冠军杯赛」
--   原稿 §四：「20:00 开赛：全部桶冠军补轮空进最近的 2 的幂签表，单败打到决赛」
--
-- ★★冠军杯赛 = `finals_buckets` 里一个**保留组号**（`finals_cup_no()` = 1000000）的单败图。
--   为什么不另建表：报结果 `finals_report` / 问对手 `finals_opponent` / 推进 `finals_advance` /
--   开播 `revealed_at` / 回放 `finals_replay` 全部按 (周, 组号) 工作 ⇒ 杯就是「又一个组」，
--   这五个函数**一行都不用改**。另建表就得把五个函数各抄一份 = 同一套规则存两份。
--   负数不行：`finals_view` 的 `p_bucket < 0` 已经表示「我那个组」。1000000 组 = 3200 万人，真组号到不了。
-- ★★本段第一次在 SQL 里写座次表（`finals_seed_at_seat`）—— 选组冠军必须顺着结果追到第 1 轮的座位。
--   构造与 `scripts/gamedata/bracket.gd` `_seat_table()` 逐步相同（镜像展开），
--   门禁 `verify_champion_cup` 逐字对构造公式、逐坑对结果。改一边必须改另一边。
-- ★重新定义的两个已有函数（finals_view / finals_week_view）正文照抄 20261007_live_matches.sql 版，
--   只改标了「冠军杯赛」的那几行。⚠ 生产库函数体可能与 schema.sql 不同，上线前先拿生产版对一遍。
-- ★本文件只加函数 / 换函数体 / 加一个 cron，不建表、不改表、不删任何一行。重复执行安全。
-- ─────────────────────────────────────────────────────────────

-- ═══ 分组容量（用户 2026-10-07 改规则）═══
-- 用户原话：「仔细思考，人少的时候桶能不能就1，2个人打出杯赛参赛者，然后多人开始在9点打杯赛？」
--           「8 人或更少时直接杯赛，不用门槛」
-- ★新规则：每组人数 s = {1,2,4,8,16,32} 里**最小**的那个、使组数 ceil(N/s) ≤ 8；32 封顶（再多人组数超过 8，
--   与原稿「桶数随人数线性伸缩」一致）。⇔ N≤8 → 1 / ≤16 → 2 / ≤32 → 4 / ≤64 → 8 / ≤128 → 16 / 其余 → 32。
--   冠军杯赛人数 = 组数（≤8 人时人人直接进冠军杯赛，上午没有对局）。
-- ★1 人组**合法**：没有对局、坐下即收盘，他就是那组的冠军（真正的冠军在冠军杯赛决出 ——
--   原来「1 人一组 = 没有对手的冠军，不是比赛」那条由此作废）。全周只有 1 人仍不开赛（finals_seat 的 total < 2）。
-- ★规格在 scripts/gamedata/bracket.gd `bucket_size_for`；门禁 verify_champion_cup 把下面这几行 `when n <= X then Y`
--   逐个人数（1..1000）与规格对；探针 tools/probe_finals_server.py ⑮ 上线后在真库再对一遍。
-- ⚠ 重新定义 finals_bucket_size / finals_seat（正文照抄 schema.sql 现行版，只改标了「2026-10-07」的行）。
--   生产库函数体可能与 schema.sql 不同，上线前先拿生产版对一遍。
create or replace function public.finals_bucket_size(n int)
returns int language sql immutable as $$
  select case
    when n <= 0 then 0
    when n <= 8 then 1
    when n <= 16 then 2
    when n <= 32 then 4
    when n <= 64 then 8
    when n <= 128 then 16
    else 32
  end
$$;

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
  --   (**必须有一个确定性的最后一项**, 否则同分的人每次查出来的顺序都不同)
  for r in select * from public.finals_pending
            where season_week = p_week
            order by gw desc, gl asc, account_id loop
    b := public.finals_bucket_of(i, nb);
    insert into public.finals_entrants
      (season_week, bucket_no, seed, account_id, name, snapshot)
      values (p_week, b, seats[b + 1], r.account_id, r.name, r.snapshot);
    seats[b + 1] := seats[b + 1] + 1;
    i := i + 1;
  end loop;
  -- 桶本身（n = 这个桶真实坐了几个人，可能比容量少）
  -- ★2026-10-07: 1 人组坐下即收盘（没有对局；finals_advance 只推没收盘的组, 冠军杯赛成表只等没收盘的组）。
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    select p_week, bucket_no, count(*)::int, 1, now(), count(*) = 1,
           case when count(*) = 1 then now() else null end
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;

revoke all on function public.finals_seat(bigint) from public;
revoke execute on function public.finals_seat(bigint) from anon, authenticated;

-- 保留组号 / 开赛钟点（UTC，E2 拍板赛程一律 UTC）/ 20:00 还有组没打完时最多再等多久。
-- ★前两个必须与客户端 phase2_config.FINALS_CUP_BUCKET / FINALS_START_HOUR_UTC 相等（门禁逐字对）。
create or replace function public.finals_cup_no()
returns int language sql immutable as $$ select 1000000 $$;
create or replace function public.finals_cup_hour()
returns int language sql immutable as $$ select 20 $$;
create or replace function public.finals_cup_wait_sec()
returns int language sql immutable as $$ select 3600 $$;

-- 标准单败座次：slots 个坑里第 pos 个坑坐的是几号种子（0 起）。越界 = -1。
-- 构造 = bracket.gd `_seat_table`：seats=[0]；每轮 seats = 交错(x, 2·size−1−x)。8 坑 = [0,7,3,4,1,6,2,5]。
create or replace function public.finals_seed_at_seat(p_slots int, p_pos int)
returns int language plpgsql immutable as $$
declare seats int[] := array[0]; nxt int[]; sz int := 1; x int;
begin
  if p_slots < 1 or p_pos < 0 or p_pos >= p_slots then
    return -1;
  end if;
  while sz < p_slots loop
    nxt := '{}';
    foreach x in array seats loop
      nxt := array_append(nxt, x);
      nxt := array_append(nxt, sz * 2 - 1 - x);
    end loop;
    seats := nxt;
    sz := sz * 2;
  end loop;
  return seats[p_pos + 1];
end $$;

-- 一个**已收盘**的组的冠军是几号种子；没收盘 / 缺结果 = null。
-- ★从决赛往下追：第 r 轮第 m 场赢的是 side s ⇒ 他来自第 r−1 轮第 2m+s 场；追到第 1 轮 ⇒ 座位 2m+s。
--   与客户端 `bracket.occupant_seed` 的 `src_m = m * 2 + side` 同一条口径。
-- ★轮空：`finals_advance` 给第 1 轮的轮空场补 winner_side = 0，而标准座次里轮空永远坐 side 1
--   ⇒ 补 0 = 真人晋级；收盘的组每一轮每一场都有行。
create or replace function public.finals_champion_seed(p_week bigint, p_bucket int)
returns int language plpgsql stable security definer set search_path = public as $$
declare b record; slots int := 1; total int := 0; r int; m int := 0; s int; sd int;
begin
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or not b.closed then
    return null;
  end if;
  if b.n = 1 then
    return 0;                            -- 1 人表（1 人组 / 只有 1 名组冠军的冠军杯赛）：他就是冠军
  end if;
  while slots < b.n loop slots := slots * 2; total := total + 1; end loop;
  r := total;
  while r >= 1 loop
    select winner_side into s from public.finals_results
     where season_week = p_week and bucket_no = p_bucket and round = r and match_no = m;
    if not found or s not in (0, 1) then
      return null;
    end if;
    if r = 1 then
      sd := public.finals_seed_at_seat(slots, m * 2 + s);
      if sd < 0 or sd >= b.n then
        return null;                     -- 追到空位 = 结果表坏了，宁可不认冠军
      end if;
      return sd;
    end if;
    m := m * 2 + s;
    r := r - 1;
  end loop;
  return null;
end $$;

revoke all on function public.finals_champion_seed(bigint, int) from public;
revoke execute on function public.finals_champion_seed(bigint, int) from anon, authenticated;

-- 冠军杯赛成表。★幂等 —— 已经建过就不动。由 pg_cron 周日 20:00 起每 5 分钟叫一次。
-- 条件：现在 ≥ 周日 finals_cup_hour() UTC 且 本周有组 且（全部组已收盘 或 已过等待上限）。
-- ★只收**已收盘**组的冠军；种子按周六战绩（gw desc, gl asc, account_id）—— 与 finals_seat 分组同一条排序
--   ⇒ 人数不整时高种子轮空（座次表天然给高种子配空位）。
-- ★阵容用他组赛那一份快照（原稿「签表掉线兜底：沿用上一轮阵容」；周日 finals_enter 已拒收）。
-- ★只有 1 名组冠军 ⇒ 建 1 人表并直接收盘：没有对局，他就是冠军（客户端据此发「冠军」）。
-- ★1 人组（2026-10-07 新分组规则）坐下即收盘 ⇒ ≤8 人时 20:00 人人进冠军杯赛。
create or replace function public.finals_cup_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare cup int := public.finals_cup_no(); start_at timestamptz; ngroups int; nopen int;
        r record; i int := 0;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    return 0;
  end if;
  start_at := to_timestamp(p_week + 6 * 86400 + public.finals_cup_hour() * 3600);
  if now() < start_at then
    return 0;
  end if;
  select count(*), count(*) filter (where not closed) into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
    return 0;                            -- 还有组没打完：等它（最多等 finals_cup_wait_sec）
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
    values (p_week, cup, i, 1, now(), i <= 1, case when i <= 1 then now() else null end);
  return i;
end $$;

revoke all on function public.finals_cup_seat(bigint) from public;
revoke execute on function public.finals_cup_seat(bigint) from anon, authenticated;

-- 读接口：「我那个组」不许查到冠军杯赛（组冠军在 finals_entrants 里有两行：组 + 杯）。
-- 其余逐字照抄 20261007_live_matches.sql 版。
create or replace function public.finals_view(p_week bigint, p_bucket int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; ents jsonb; res jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★p_bucket < 0 = 「我那个桶」。客户端并不知道自己被分到哪个桶(分桶是服务端做的),
  --   分成两次往返去问会出现「查到桶号、桶却没了」的中间态, 所以并到这一次里。
  if p_bucket < 0 then
    select e.bucket_no into p_bucket from public.finals_entrants e
     where e.season_week = p_week and e.account_id = auth.uid()
       and e.bucket_no <> public.finals_cup_no()   -- ★冠军杯赛 2026-10-07: 「我那个组」只认小组赛
     limit 1;
    if p_bucket is null then
      -- ★★2026-09-25: 「没资格」与「有资格但人不够、赛没开起来」**必须分开说**。
      --   `finals_seat` 对 1 个人会**故意不建桶**(一人一桶 = 没有对手的冠军, 那不是比赛),
      --   于是那个人在 `finals_pending` 里有行、在 `finals_entrants` 里没有 ⇒ 原来一律
      --   返回 `not_entered`, 客户端照它说「周六闯关赛晋级才进得来」——
      --   **而他明明晋级了**(周六 4 胜), 屏幕在告诉他一件假事, 他会以为胜场没算。
      --   10 个人规模下这不是假想: 晋级率约 34% ⇒ 只有 0~1 人晋级的概率约 10%。
      --   ⇒ 报过名就回 `too_few` 并带上**本周报名人数**, 让客户端能说人话。
      if exists (select 1 from public.finals_pending
                  where season_week = p_week and account_id = auth.uid()) then
        -- ★2026-10-04: 本周还一个桶都没有 = 还没到分组时间(finals_seat 周日 08:00 UTC 起跑), 不是人太少。
        --   原来这里一律回 too_few ⇒ 周日早上每个晋级的人都被劝「人太少、下周再来」。
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
  -- ★★只取 round < 当前轮 —— 当前轮的结果**根本不下发**。
  -- ★但桶**收盘之后就没有「当前轮」了**: round 停在最后一轮, 于是 `r.round < b.round`
  --   会把决赛结果自己永久挡掉 ⇒ **冠军永远不公布**。收盘了就全给。
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
    into res from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)。客户端按它算开播窗口。
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻: 客户端拿这个倒计时, 不必知道「一轮多长」
    'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
    'now', extract(epoch from now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res);
end $$;

revoke all on function public.finals_view(bigint, int) from public;
revoke execute on function public.finals_view(bigint, int) from anon;
grant execute on function public.finals_view(bigint, int) to authenticated;

-- 观赛读接口：组列表**不含**冠军杯赛（老客户端会把它画成第 1000001 组）；
-- 冠军杯赛另放回包顶层 `cup`（同一形状 + next_at；没成表 = null；老客户端忽略未知键）。
-- 不剧透同一条 `b.closed or r.round < b.round`。其余逐字照抄 20261007_live_matches.sql 版。
create or replace function public.finals_week_view(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare bs jsonb; cp jsonb; cup int := public.finals_cup_no();
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           -- ★2026-10-07 实时观赛: 开播窗口要两个时刻(没收盘: round_at = 上一轮翻面; 收盘: 只有 revealed_at)
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
                       and (b.closed or r.round < b.round)))
         order by b.bucket_no), '[]'::jsonb)
    into bs from public.finals_buckets b
   where b.season_week = p_week
     and b.bucket_no <> cup;               -- ★冠军杯赛 2026-10-07: 杯不进组列表
  -- ★冠军杯赛 2026-10-07: 杯那一张(多一个 next_at, 选手在杯里打要倒计时)。
  select jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           'round_at', extract(epoch from b.round_at)::bigint,
           'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
           'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
           'entrants', (select coalesce(jsonb_agg(jsonb_build_object(
                           'seed', e.seed, 'name', e.name, 'account_id', e.account_id)
                         order by e.seed), '[]'::jsonb)
                          from public.finals_entrants e
                         where e.season_week = p_week and e.bucket_no = b.bucket_no),
           'done', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)))
    into cp from public.finals_buckets b
   where b.season_week = p_week and b.bucket_no = cup;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from now())::bigint, 'buckets', bs, 'cup', cp);
end $$;

revoke all on function public.finals_week_view(bigint) from public;
revoke execute on function public.finals_week_view(bigint) from anon;
grant execute on function public.finals_week_view(bigint) to authenticated;

-- 定时：周日 20:00~23:55 UTC 每 5 分钟试一次成表（幂等；成表之后 finals_advance 的 jobid 1 接着推轮次）。
-- 周号写法与 jobid 1 / 5 相同（本周一 00:00 UTC 的 epoch = 客户端 week_anchor_ts）。
select cron.unschedule(jobid) from cron.job where jobname = 'finals_cup_seat';
select cron.schedule('finals_cup_seat', '*/5 20-23 * * 0',
  $c$select public.finals_cup_seat(extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint)$c$);
-- <<< END champion_cup 20261007b <<<
