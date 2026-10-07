-- >>> BEGIN live_matches 20261007 >>>
-- ─────────────────────────────────────────────────────────────
-- 实时观赛（2026-10-07 · 方案书 docs/plans/20261007-实时观赛.md）—— ★待主会话审后上线
--   用户原话：「观赛和回放是两码事明白吗」「周六即有回放也有正在打的啊」
--
-- 两件事：
--   ① 周六·正在打的（真直播）：新表 `live_matches`。打的人开打（第一路 fight）就建一行，
--      之后每出现一个事件、以及每 3 秒心跳一次，**整行覆盖**（upsert）成「到目前为止的录像」+
--      「已推进到的 sim 步号 horizon」；打完写 ended = true。观众按 match_id 每 2~3 秒读一次，
--      本机重算追到 horizon 之前（录像格式与 matches.replay 完全相同）。
--   ② 周日·逐轮开播：`finals_buckets` 补一列 `revealed_at`（最近一次翻面的时刻）。
--      原来只有 `round_at`（本轮开始时刻）：没收盘时它恰好等于上一轮的翻面时刻，
--      但**收盘那一下不改 round_at** ⇒ 决赛那一轮翻面的时刻没有任何地方记着。
--      `finals_advance` 两条 update 都写 revealed_at = now()；`finals_view` / `finals_week_view`
--      下发 revealed_at（周视图另补 round_at）。客户端按「翻面时刻 + 一场时长 + 缓冲」算开播窗口，
--      窗口内对阵图不显示胜负。没上线时客户端退回 round_at（没收盘的组照样有开播窗口；
--      收盘的组没有 revealed_at ⇒ 不开播、直接显示结果），不报错。
--
-- ★本文件只建表 / 加列 / 换函数体，不删任何数据。重复执行安全（if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① live_matches ═══
create table if not exists public.live_matches (
  match_id       uuid        primary key,               -- = 打完之后 matches.match_id（同一个 uuid，客户端开打时就定下）
  season_week    bigint      not null,
  account_id     uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  phase          text        not null default 'gauntlet',
  left_snapshot  jsonb       not null,                  -- 只放 {profile, leaders}（名字 / 头像 / #ID / 三统领），不放阵容装备
  right_snapshot jsonb       not null,                  -- 同上；客户端上传前摘掉 is_bot / ghost_id
  replay         text        not null,                  -- 到目前为止的录像（var_to_bytes + deflate + base64，同 matches.replay）
  horizon        int         not null default 0,        -- 打的人已推进到的 sim 步号：观众只许重算到这一步
  ended          boolean     not null default false,
  client_version text        not null,
  started_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.live_matches drop constraint if exists live_matches_phase;
alter table public.live_matches add constraint live_matches_phase check (phase = 'gauntlet');
-- ★上限与 matches_replay_size 同一个数（客户端 replay_uploader.REPLAY_MAX_B64；门禁 verify_live_spectate 逐字对）。
alter table public.live_matches drop constraint if exists live_matches_replay_size;
alter table public.live_matches add constraint live_matches_replay_size
  check (octet_length(replay) between 1 and 65536 and replay ~ '^[A-Za-z0-9+/]+={0,2}$');
alter table public.live_matches drop constraint if exists live_matches_horizon;
alter table public.live_matches add constraint live_matches_horizon check (horizon between 0 and 1000000);

create index if not exists live_matches_week_idx on public.live_matches (season_week, updated_at desc);

-- ★时间戳由服务端定：客户端写不了 started_at / updated_at（赛况板按 updated_at 判「还在打吗」，
--   客户端能写就能把一场断线的直播挂在板上一整天）。顺带：主人、周、开打时刻不许改；ended 只能 false → true。
create or replace function public.live_matches_stamp() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.started_at := now();
    new.updated_at := now();
    return new;
  end if;
  new.account_id  := old.account_id;
  new.season_week := old.season_week;
  new.started_at  := old.started_at;
  new.ended       := old.ended or new.ended;
  new.updated_at  := now();
  return new;
end $$;

drop trigger if exists live_matches_stamp on public.live_matches;
create trigger live_matches_stamp before insert or update on public.live_matches
  for each row execute function public.live_matches_stamp();

alter table public.live_matches enable row level security;

-- 读：登录用户，只读**本周**开打的（周界 = 周一 00:00 UTC，与 purge_old_matches / 客户端 week_anchor_ts 同一条口径）。
drop policy if exists live_read_week on public.live_matches;
create policy live_read_week on public.live_matches
  for select using (auth.uid() is not null
                    and started_at >= date_trunc('week', now() at time zone 'UTC') at time zone 'UTC');
-- 写：只能写自己的行（客户端 upsert = POST + Prefer: resolution=merge-duplicates ⇒ insert 与 update 两条都要）。
drop policy if exists live_insert_own on public.live_matches;
create policy live_insert_own on public.live_matches
  for insert with check (account_id = auth.uid());
drop policy if exists live_update_own on public.live_matches;
create policy live_update_own on public.live_matches
  for update using (account_id = auth.uid()) with check (account_id = auth.uid());
-- ★没有 delete 策略：删只走下面的周清。

-- 周清：并进现有的 purge_old_matches（cron jobid 11 '0 0 * * 2' 已在跑，不新增任务）。
--   口径一字不差：删掉「本周一 00:00 UTC 之前」开打的。直播行打完就没用了（正式录像在 matches），
--   留到周清只是省一条任务；它们本来就只对本周可读。
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.live_matches where started_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;

-- ═══ ② finals_buckets.revealed_at ═══
alter table public.finals_buckets add column if not exists revealed_at timestamptz;
-- 已在进行中的组：没收盘时上一轮的翻面时刻 = 本轮的 round_at（finals_advance 同一条 update 写的）。
update public.finals_buckets set revealed_at = round_at
 where revealed_at is null and round > 1 and not closed;

-- 推进器：两条 update 都记下翻面时刻（其余逐字照抄 schema.sql 原函数）。
create or replace function public.finals_advance(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; moved int := 0; want int; got int; slots int; total int;
        real_want int;
begin
  for b in select * from public.finals_buckets
            where season_week = p_week and not closed loop
    -- 本轮时间还没到就跳过（3 分钟购物 + 结算 + 4 分钟重放 ≈ 8 分钟）
    if now() < b.round_at + make_interval(secs => public.finals_round_sec()) then
      continue;
    end if;
    -- 补到 2 的幂 → 总轮数 / 本轮该有几场
    slots := 1; total := 0;
    while slots < b.n loop slots := slots * 2; total := total + 1; end loop;
    want := slots / (2 ^ b.round)::int;
    select count(*) into got from public.finals_results
     where season_week = p_week and bucket_no = b.bucket_no and round = b.round;
    -- ★没打完就不推 —— 宁可晚一分钟, 也不能把没结果的一轮翻面
    -- ★★但「不推」不能没有上限(2026-09-25 查出来的死锁): 原来这里是无条件 continue,
    --   于是**只要有一场没人报结果, 那个桶就永远不动**。注释当时写的是「宁可晚一分钟」,
    --   实际是永远。而测试期人数个位数, 周日晚上「双方都不在线」几乎是常态。
    -- ★★★2026-09-26: 只等【真的有人打的那几场】, 不等轮空。
    --   轮空那几场**没有任何客户端会报结果** —— 客户端只在打完一局后报, 轮空没有局。
    --   原来把它们也算进 `want` ⇒ 只要本轮有轮空, `got < want` 恒成立 ⇒ **必等满
    --   960 秒宽限**, 而客户端倒计时是 `round_at + finals_round_sec()`(480)
    --   ⇒ 第 8 分钟起屏幕显示「下一轮 0:00 后开播」并冻住整整 8 分钟, 然后突然跳轮。
    --   10 人规模实测形状: slots=16、第 1 轮 8 场里**只有 2 场是真的**
    --   ⇒ 10 个人里 6 个人第一轮什么都不打, 干等 16 分钟。
    -- ★算轮空场数**不需要**知道座次表(那是 E-B3 定在客户端的规则, SQL 里不写第二遍):
    --   第 1 轮有 `slots - n` 个空位, 每个空位让它那一场变成轮空
    --   ⇒ 真实场次 = `n - slots/2`。(n=10,slots=16 ⇒ 2; n=3,slots=4 ⇒ 1, 与手算一致。)
    --   第 2 轮起所有席位都被上一轮的晋级者填满(轮空者也晋级) ⇒ 全是真实场次。
    real_want := want;
    if b.round = 1 then
      real_want := greatest(0, b.n - slots / 2);
    end if;
    if got < real_want then
      -- 宽限期内: 真的等一等。★取 2 倍而不是 1 倍 —— 本函数每分钟才叫一次,
      --   且真有人在打时最后一场可能压着点报上来; 1 倍会把**正在打的比赛**判掉。
      if now() < b.round_at + make_interval(secs => public.finals_round_sec() * 2) then
        continue;
      end if;
      -- ★过了宽限期还缺 ⇒ 补判: 缺哪场补哪场, 一律 **side 0(上半区)晋级**。
      -- ★为什么是「上半区」不是「高种子」: 服务端**算不出**第 N 轮某一场里是谁 ——
      --   算得出就等于在 SQL 里写了第二遍对阵规则(E-B3 定的那条)。
      --   而 side 0 不需要知道任何对阵规则: 缺哪个 match_no 就补哪个。
      --   第一轮里上半区恰好就是高种子(座次表 [0,7,3,4,1,6,2,5] ⇒ 0vs7/3vs4/1vs6/2vs5),
      --   后续轮它是上半区那条路径, **不保证**是当时的高种子 —— 照实说, 不吹成「高种子晋级」。
      -- ★`do nothing` 保证**已经打完的那几场一个字都不动**。
      null;   -- 补判由下面那条无条件的 insert 做(见它的注释)
    end if;
    -- ★★这条 insert **无条件**跑, 而不是只在"过了宽限期"时跑:
    --   它要补的有两类, 而 `do nothing` 保证**已经打完的一场都不动**:
    --     ① 轮空 —— 本来就没人会报, 真实场次一打完就该补上, 不该拖到宽限期
    --     ② 过了宽限期还没人报的真实场次 —— 原来的用途
    insert into public.finals_results
      (season_week, bucket_no, round, match_no, winner_side, seed_used)
      select p_week, b.bucket_no, b.round, g.m, 0, 0
        from generate_series(0, want - 1) as g(m)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    if b.round >= total then
      update public.finals_buckets set closed = true, revealed_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = now(), revealed_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;

revoke all on function public.finals_advance(bigint) from public;
revoke execute on function public.finals_advance(bigint) from anon, authenticated;

-- 读接口：多下发 revealed_at（其余逐字照抄）。
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

-- 观赛读接口：多下发 round_at / revealed_at（其余逐字照抄）。
create or replace function public.finals_week_view(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare bs jsonb;
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
   where b.season_week = p_week;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from now())::bigint, 'buckets', bs);
end $$;

revoke all on function public.finals_week_view(bigint) from public;
revoke execute on function public.finals_week_view(bigint) from anon;
grant execute on function public.finals_week_view(bigint) to authenticated;
-- <<< END live_matches 20261007 <<<
