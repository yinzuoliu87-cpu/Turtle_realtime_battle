-- >>> BEGIN referee_jobs 20261019 >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判（2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §1 / §3 ①②）—— ★只写文件、未上生产
--   上线步骤 / 回滚 / 监控见 server/referee/README.md。
--
-- 用户 10-19「我们的所有对局不应该在本机上吧，应该放服务器上吧」「周六周日让服务器记」。
-- 做法：对局结果 = f(双方快照, 种子)，由裁判机（欧洲 x86 服务器上的无头 Godot，与客户端同版本）算，
--   算完写回录像（matches.replay，与客户端上传同一格式，手机直接播）与赛果。
--
-- 本段内容（全是添加，或在两个开关后面加一条分支；★两个开关默认关 ⇒ 执行本段不改变任何现行行为）：
--   ① referee_config（开关 finals_on / gauntlet_on、领活租期、重试次数、周日任务用的版本）、referee_versions（裁判机装了哪些版本）
--   ② referee_jobs：待算 pending → 领取 claimed → 完成 done / 失败 failed；领了超过租期没写回 ⇒ 别的裁判重领
--   ③ RPC（只有 service_role 能调）：referee_claim 领活 / referee_complete 写回 / referee_fail 报错 / referee_backlog 监控
--   ④ 周日：referee_enqueue_finals —— 购物窗一关就给本轮每一场真实对局建任务（A = 上侧 side 0、B = 下侧 side 1）；
--      finals_advance（开关开着时）不再给真实场次补判 side 0，只补轮空；超过 3 倍本轮时长仍没结果才退回 side 0 兜底；
--      finals_report（开关开着时）不再收客户端上报（reason = referee）。结果由 referee_complete 写 finals_results（含比分码）。
--   ⑤ 周六：referee_submit_gauntlet（客户端交阵容 + 对手快照 → 建任务，种子服务端生成）/ referee_job_status（查自己那一场）；
--      写回时记账到 gauntlet_records（服务端战绩账本），并把阵容按新战绩标签挂进 gauntlet_ghosts；
--      finals_enter（开关开着时）的晋级线与种子排序改用账本上的 gw / gl，不再信客户端报的数。
-- ★客户端一行不改也不受影响：开关关着时三个被重定义的函数（finals_advance / finals_report / finals_enter）逐字等于原版。
-- ★重复执行安全（create if not exists / create or replace / on conflict do nothing / drop if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 开关 / 版本 ─────────────────────────────────────────────
create table if not exists public.referee_config (
  id            int primary key default 1,
  finals_on     boolean not null default false,   -- 周日结果由裁判出
  gauntlet_on   boolean not null default false,   -- 周六闯关由裁判出、服务端记账
  gauntlet_any_day boolean not null default false,-- 内测服 / 彩排: 不限周六也能交（正式服保持 false）
  finals_version text not null default '',        -- 周日任务按哪个客户端版本算（= 当周锁定的版本；必须在 referee_versions 里且 enabled）
  lease_sec     int not null default 180,         -- 领了多久没写回 ⇒ 收回重领（一局实测 ≤ 15 秒；含 Godot 启动）
  max_attempts  int not null default 3,           -- 同一份任务最多领几次（每次领 +1；用尽 ⇒ failed）
  updated_at    timestamptz not null default now(),
  constraint referee_config_single_row check (id = 1)
);
insert into public.referee_config (id) values (1) on conflict (id) do nothing;
alter table public.referee_config enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行；只有 service_role / 下面的 security definer 函数碰得到

-- 裁判机上装了哪些客户端版本（结果只在同版本里成立：每个版本一套无头 Godot 工程）。
create table if not exists public.referee_versions (
  client_version text primary key,
  enabled        boolean not null default true,
  added_at       timestamptz not null default now()
);
alter table public.referee_versions enable row level security;

create or replace function public.referee_finals_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select finals_on from public.referee_config where id = 1), false)
$$;
create or replace function public.referee_gauntlet_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select gauntlet_on from public.referee_config where id = 1), false)
$$;
revoke all on function public.referee_finals_on() from public, anon, authenticated;
revoke all on function public.referee_gauntlet_on() from public, anon, authenticated;

-- ② 任务表 ─────────────────────────────────────────────────
-- 一行 = 一场要算的对局。形状与裁判程序的任务单一一对应（scripts/referee/referee_job.gd 头注）：
--   v / job_id / match_id / mode(=kind) / key(=meta + week + match_key) / seed / client_version / level / a / b。
create table if not exists public.referee_jobs (
  job_id         bigint generated always as identity primary key,
  kind           text        not null check (kind in ('gauntlet', 'finals')),
  match_key      text        not null unique,     -- 幂等键：finals:<周>:<组>:<轮>:<场> / gauntlet:<周>:<账号>:<第几场>
  season_week    bigint      not null,
  client_version text        not null,
  seed           bigint      not null check (seed between 1 and 9007199254740991),   -- 2^53-1：JSON 往返不掉位
  match_id       uuid        not null default gen_random_uuid(),                    -- = 录像 id = matches.match_id
  a_account      uuid        references auth.users(id) on delete set null,          -- 左方（周日 = 上侧 side 0）
  b_account      uuid        references auth.users(id) on delete set null,          -- 右方（周六 = null：对手可能是机器人）
  a_snapshot     jsonb       not null,
  b_snapshot     jsonb       not null,
  level          int,                                                               -- 双方共用等级（null ⇒ 裁判按 A 的快照推）
  meta           jsonb       not null default '{}'::jsonb,                          -- 周日 {bucket, round, match}；周六 {account, gw0, gl0}
  status         text        not null default 'pending' check (status in ('pending', 'claimed', 'done', 'failed')),
  attempts       int         not null default 0,
  claimed_by     text,
  claimed_at     timestamptz,
  result         jsonb,                                                             -- 结果单（去掉录像本体）+ 落账摘要
  error          text,
  created_at     timestamptz not null default now(),
  done_at        timestamptz
);
create index if not exists referee_jobs_queue_idx on public.referee_jobs (status, created_at)
  where status in ('pending', 'claimed');
create index if not exists referee_jobs_acc_idx on public.referee_jobs (season_week, a_account);
alter table public.referee_jobs enable row level security;
-- 没有任何策略 ⇒ 客户端直连读不到（快照 = 阵容情报）；玩家查自己那一场走 referee_job_status

-- 裁判机心跳（监控 R3：挂了要知道）。referee_claim 每叫一次就记一笔。
create table if not exists public.referee_workers (
  worker     text primary key,
  versions   text[] not null default '{}',
  seen_at    timestamptz not null default now()
);
alter table public.referee_workers enable row level security;

-- ③ 小工具 ─────────────────────────────────────────────────
-- 服务端种子：1 ~ 2^53-1。★种子永远由服务端给，不收客户端的（否则可以换种子刷结果）。
create or replace function public.referee_new_seed() returns bigint
language plpgsql volatile as $$
declare v bigint;
begin
  v := ('x' || substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 14))::bit(56)::bigint
       & 9007199254740991;
  if v = 0 then
    v := 1;
  end if;
  return v;
end $$;
revoke all on function public.referee_new_seed() from public, anon, authenticated;

-- 快照里的等级（1~10；没有 / 不合法 = null ⇒ 裁判按 A 的场次推算）。
-- ⚠ 客户端 build_ghost_snapshot 现在不带 season_level（未决点，见 README）。
create or replace function public.referee_level_of(p_snap jsonb) returns int
language sql immutable as $$
  select case when jsonb_typeof(p_snap->'season_level') = 'number'
               and (p_snap->>'season_level')::numeric between 1 and 10
              then (p_snap->>'season_level')::numeric::int end
$$;
revoke all on function public.referee_level_of(jsonb) from public, anon, authenticated;

-- 周日某轮某场某一侧坐的是几号种子；空位 / 上一轮还没结果 = null。
-- ★与 finals_champion_seed 同一条口径：第 r 轮第 m 场的 side s 来自第 r−1 轮第 2m+s 场的胜者；追到第 1 轮 ⇒ 座位 2m+s。
create or replace function public.referee_finals_occupant(p_week bigint, p_bucket int, p_round int,
    p_match int, p_side int)
returns int language plpgsql stable security definer set search_path = public as $$
declare b record; slots int := 1; r int := p_round; m int := p_match; s int := p_side; w int; sd int;
begin
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found or p_side not in (0, 1) or p_round < 1 then
    return null;
  end if;
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  while r > 1 loop
    select winner_side into w from public.finals_results
     where season_week = p_week and bucket_no = p_bucket and round = r - 1 and match_no = 2 * m + s;
    if not found or w not in (0, 1) then
      return null;
    end if;
    m := 2 * m + s;
    s := w;
    r := r - 1;
  end loop;
  sd := public.finals_seed_at_seat(slots, 2 * m + s);
  if sd < 0 or sd >= b.n then
    return null;
  end if;
  return sd;
end $$;
revoke all on function public.referee_finals_occupant(bigint, int, int, int, int) from public, anon, authenticated;

-- ④ 周日：建任务 ───────────────────────────────────────────
-- 购物窗关了（round_at + finals_shop_sec）⇒ 本轮每一场两侧都有人的对局建一份任务（幂等：match_key 唯一）。
-- 快照取 finals_entrants 当前那份（购物窗内 finals_update_snapshot 改过的就是购物后的阵容，购物窗一关就锁定）。
-- 由 finals_advance 开头调（pg_cron 每分钟一次，jobid 1）；也可以单独调。
create or replace function public.referee_enqueue_finals(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; ea record; eb record; slots int; n_match int; m int; s0 int; s1 int;
        ver text; added int := 0; k int;
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
    if now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
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
      insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
          a_account, b_account, a_snapshot, b_snapshot, level, meta)
        values ('finals', format('finals:%s:%s:%s:%s', p_week, b.bucket_no, b.round, m), p_week, ver,
          public.referee_new_seed(), ea.account_id, eb.account_id, ea.snapshot, eb.snapshot,
          public.referee_level_of(ea.snapshot),
          jsonb_build_object('bucket', b.bucket_no, 'round', b.round, 'match', m, 'seed0', s0, 'seed1', s1))
        on conflict (match_key) do nothing;
      get diagnostics k = row_count;
      added := added + k;
    end loop;
  end loop;
  return added;
end $$;
revoke all on function public.referee_enqueue_finals(bigint) from public, anon, authenticated;

-- ⑤ 周六：服务端战绩账本 + 交阵容 / 查结果 ─────────────────
create table if not exists public.gauntlet_records (
  season_week  bigint      not null,
  account_id   uuid        not null references auth.users(id) on delete cascade,
  gw           int         not null default 0,
  gl           int         not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (season_week, account_id)
);
alter table public.gauntlet_records enable row level security;
drop policy if exists gauntlet_records_self on public.gauntlet_records;
create policy gauntlet_records_self on public.gauntlet_records for select using (auth.uid() = account_id);
-- 写只有 referee_complete（没有 insert / update 策略）

-- 客户端点「开战」：交自己的阵容快照 + 对手快照（对手照旧由客户端从 gauntlet_ghosts / 机器人里挑 —— 未决点见 README）。
-- 种子服务端生成；同一个人同一时刻只有一场在算（在算的那场直接把号还给他）；
-- 只有「上一次算失败了」才允许同一场重交，且种子不换（不许换种子刷结果）。
create or replace function public.referee_submit_gauntlet(p_week bigint, p_snapshot jsonb, p_opponent jsonb,
    p_client_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text;
        jid bigint; mid uuid; st text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  if not exists (select 1 from public.referee_versions where client_version = p_client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (now() >= to_timestamp(p_week + 5 * 86400) and now() < to_timestamp(p_week + 6 * 86400)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') <> 3
     or jsonb_typeof(p_snapshot->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  if p_opponent is null or jsonb_typeof(p_opponent) <> 'object' or octet_length(p_opponent::text) > 65536
     or jsonb_typeof(p_opponent->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_opponent');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true);
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, null,
      p_snapshot, p_opponent, public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl))
    on conflict (match_key) do update
      set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null,
          a_snapshot = excluded.a_snapshot, b_snapshot = excluded.b_snapshot,
          client_version = excluded.client_version, level = excluded.level, created_at = now()
      where public.referee_jobs.status = 'failed'
    returning job_id, match_id into jid, mid;
  if jid is null then
    select job_id, match_id, status into jid, mid, st from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid);
end $$;
revoke all on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) from public, anon;
grant execute on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) to authenticated;

-- 查自己那一场算完没有（只认 a_account = 自己；不回快照）。录像本体在 matches（按 match_id 读）。
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
    'won', j.result->'ledger'->'won', 'score', j.result->'ledger'->'score',
    'gw', j.result->'ledger'->'gw', 'gl', j.result->'ledger'->'gl',
    'error', case when j.status = 'failed' then j.error end);
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ⑥ 裁判机 RPC（只有 service_role）─────────────────────────
-- 领活：只领自己装了的版本；租期过了没写回的一并收回重领；次数用尽的判 failed。返回任务单数组（jsonb）。
-- ★for update skip locked：N 个裁判进程并发领不会领到同一份。
create or replace function public.referee_claim(p_worker text, p_versions text[], p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_out jsonb;
begin
  select * into cfg from public.referee_config where id = 1;
  insert into public.referee_workers (worker, versions, seen_at) values (p_worker, coalesce(p_versions, '{}'), now())
    on conflict (worker) do update set versions = excluded.versions, seen_at = now();
  update public.referee_jobs
     set status = 'failed', error = coalesce(error, 'lease_expired'), done_at = now()
   where status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)
     and attempts >= cfg.max_attempts;
  with c as (
    select job_id from public.referee_jobs
     where client_version = any(coalesce(p_versions, '{}'))
       and (status = 'pending'
            or (status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)))
     order by created_at, job_id
     limit greatest(1, least(coalesce(p_limit, 1), 32))
     for update skip locked
  ), u as (
    update public.referee_jobs j
       set status = 'claimed', claimed_by = p_worker, claimed_at = now(), attempts = j.attempts + 1
      from c where j.job_id = c.job_id
    returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'v', 1, 'job_id', u.job_id, 'match_id', u.match_id, 'mode', u.kind,
           'key', u.meta || jsonb_build_object('week', u.season_week, 'match_key', u.match_key),
           'seed', u.seed, 'client_version', u.client_version, 'level', u.level,
           'a', u.a_snapshot, 'b', u.b_snapshot) order by u.job_id), '[]'::jsonb)
    into v_out from u;
  return v_out;
end $$;
revoke all on function public.referee_claim(text, text[], int) from public, anon, authenticated;
grant execute on function public.referee_claim(text, text[], int) to service_role;

-- 写回：校验结果单与任务单一致 ⇒ 一个事务里落 matches（录像）+ 赛果（周日 finals_results / 周六 gauntlet_records + gauntlet_ghosts）。
-- ★幂等：已 done 的再写回一次直接回 ok（网络重试）；只有当前持有者能写（租期过了被别人重领 ⇒ 旧持有者写不进）。
-- ★周日那一场若已经有结果（开关打开之前客户端报过 / 3 倍时长兜底补判过）⇒ 不改，任务记 superseded（录像照样落）。
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
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
  res := jsonb_build_object('won', won, 'steps', (p_result->>'steps')::numeric::int, 'surrendered', false,
                            'referee', true, 'score', sc);
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
    -- 以打完这一场的新战绩标签挂进快照池（同 E-A4：下一场要找的是「跟我现在同样几胜几负」的人）
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version)
      values (j.a_account, j.season_week, v_gw, v_gl, j.a_snapshot, j.client_version)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, uploaded_at = now();
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- 报错：permanent（任务单本身不对，重算也一样）或次数用尽 ⇒ failed；否则放回 pending 给下一个裁判。
create or replace function public.referee_fail(p_job_id bigint, p_worker text, p_error text, p_permanent boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; n int;
begin
  select * into cfg from public.referee_config where id = 1;
  update public.referee_jobs
     set status = case when coalesce(p_permanent, false) or attempts >= cfg.max_attempts then 'failed' else 'pending' end,
         done_at = case when coalesce(p_permanent, false) or attempts >= cfg.max_attempts then now() end,
         error = left(coalesce(p_error, '?'), 500), claimed_by = null, claimed_at = null
   where job_id = p_job_id and status = 'claimed' and claimed_by = p_worker;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;
revoke all on function public.referee_fail(bigint, text, text, boolean) from public, anon, authenticated;
grant execute on function public.referee_fail(bigint, text, text, boolean) to service_role;

-- 监控：积压多少、最老的等了多久、裁判机最后一次心跳。告警阈值见 README（例：pending 最老 > 120 秒 或 心跳 > 120 秒）。
create or replace function public.referee_backlog()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pending', (select count(*) from public.referee_jobs where status = 'pending'),
    'claimed', (select count(*) from public.referee_jobs where status = 'claimed'),
    'failed_24h', (select count(*) from public.referee_jobs where status = 'failed' and done_at > now() - interval '24 hours'),
    'oldest_pending_sec', (select coalesce(extract(epoch from now() - min(created_at))::int, 0)
                             from public.referee_jobs where status = 'pending'),
    'workers', (select coalesce(jsonb_agg(jsonb_build_object('worker', worker, 'versions', versions,
                  'seen_sec', extract(epoch from now() - seen_at)::int)), '[]'::jsonb) from public.referee_workers))
$$;
revoke all on function public.referee_backlog() from public, anon, authenticated;
grant execute on function public.referee_backlog() to service_role;

-- 清理：已结束（done / failed）超过 14 天的任务（录像本体在 matches，按它自己的周清走）。每天 04:40 UTC。
create or replace function public.referee_purge() returns void
language sql security definer as $$
  delete from public.referee_jobs where status in ('done', 'failed') and done_at < now() - interval '14 days';
$$;
revoke all on function public.referee_purge() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'referee_purge';
select cron.schedule('referee_purge', '40 4 * * *', 'select public.referee_purge()');

-- ⑦ 三个现行函数加开关分支（正文照抄 schema.sql 现行最后一版，只在标了「2026-10-19 服务器裁判」的地方加了分支）──

create or replace function public.finals_advance(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; moved int := 0; want int; got int; slots int; total int;
        real_want int;
begin
  -- ★2026-10-19 服务器裁判: 购物窗一关就给本轮每一场真实对局建裁判任务(幂等; 开关关着时什么都不做)
  if public.referee_finals_on() then
    perform public.referee_enqueue_finals(p_week);
  end if;
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
    if public.referee_finals_on()
       and now() < b.round_at + make_interval(secs => public.finals_round_sec() * 3) then
      -- ★2026-10-19 服务器裁判: 真实场次只认裁判写回的结果(referee_complete), 这里只补轮空
      --   (第 1 轮下侧座位空着 = 真人晋级, 与原来补 side 0 同一个结果)。
      --   硬上限 3 倍本轮时长: 过了还没结果(裁判机挂了 / 任务失败)才走下面 else —— 原来那条 side 0 兜底。
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

create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint, p_reporter_side int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; slots int := 1; n_match int; bye_seed int; open_at timestamptz;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★2026-10-19 服务器裁判: 开关开着时结果只由裁判机写(referee_complete), 客户端上报一律不收
  if public.referee_finals_on() then
    return jsonb_build_object('ok', false, 'reason', 'referee');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_winner_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'bad_side');
  end if;
  -- ★2026-10-12: 旧客户端(不带侧别)按旧规矩各打各的 ⇒ 不收
  if p_reporter_side is null or p_reporter_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  open_at := b.round_at + make_interval(secs => public.finals_shop_sec());
  if now() < open_at then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  if p_reporter_side = 1 and now() < open_at + make_interval(secs => public.finals_lower_grace_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'upper_first');
  end if;
  -- 场号必须是本轮真实存在的场(20261011_finals_report_guard ①)
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  n_match := greatest(1, slots / (2 ^ p_round)::int);
  if p_match < 0 or p_match >= n_match then
    return jsonb_build_object('ok', false, 'reason', 'bad_match', 'n_match', n_match);
  end if;
  -- 第 1 轮轮空场不收(20261011_finals_report_guard ②)
  if p_round = 1 then
    bye_seed := public.finals_seed_at_seat(slots, 2 * p_match + 1);
    if bye_seed < 0 or bye_seed >= b.n then
      return jsonb_build_object('ok', false, 'reason', 'bye');
    end if;
  end if;
  insert into public.finals_results
    (season_week, bucket_no, round, match_no, winner_side, seed_used)
    values (p_week, p_bucket, p_round, p_match, p_winner_side, coalesce(p_seed, 0))
    on conflict (season_week, bucket_no, round, match_no) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.finals_report(bigint, int, int, int, int, bigint, int) from public, anon;
grant execute on function public.finals_report(bigint, int, int, int, int, bigint, int) to authenticated;

create or replace function public.finals_enter(p_week bigint, p_name text,
    p_snapshot jsonb, p_gw int, p_gl int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare floor_wins int := 4;   -- = phase2_config.GAUNTLET_WINS_IN(周六 4 胜晋级)
  -- ★★2026-09-25 修: 原来写的是 5, 注释说「与 PROMOTE_WINS_FLOOR 同值」——
  --   但 `p_gw` 传进来的是 **gauntlet_wins(周六胜场)**, 而 PROMOTE_WINS_FLOOR 是
  --   **积分赛→周六**那条线(比的是 season_wins)。**两个不同的量被当成了同一个。**
  --   后果: 周六 4 胜晋级的人 gauntlet_wins=4 < 5 ⇒ 被拒;
  --   而 4 胜之后 `gauntlet_state()` 就返回「晋级」、开局闸不让再打 ⇒ 永远到不了 5
  --   ⇒ **没有任何人进得了周日**。正确的线就是周六那条: 4 胜。
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★2026-10-19 服务器裁判: 周六战绩由裁判记账(gauntlet_records)之后, 晋级线与种子排序都用账本上的数,
  --   不再信客户端报的 p_gw / p_gl(原来那条「已知缺口」由此补上)。
  if public.referee_gauntlet_on() then
    select coalesce(max(r.gw), 0), coalesce(max(r.gl), 0) into p_gw, p_gl
      from public.gauntlet_records r where r.season_week = p_week and r.account_id = auth.uid();
  end if;
  if coalesce(p_gw, 0) < floor_wins then
    return jsonb_build_object('ok', false, 'reason', 'not_qualified', 'need', floor_wins);
  end if;
  -- ★已经开赛就不收了: 桶已经坐定, 这时塞人会让别人的对阵图当场变形
  if exists (select 1 from public.finals_buckets where season_week = p_week) then
    return jsonb_build_object('ok', false, 'reason', 'already_seated');
  end if;
  insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
    values (p_week, auth.uid(), coalesce(p_name, '?'), coalesce(p_snapshot, '{}'::jsonb),
            p_gw, coalesce(p_gl, 0))
    on conflict (season_week, account_id) do update
      set name = excluded.name, snapshot = excluded.snapshot,
          gw = excluded.gw, gl = excluded.gl;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.finals_enter(bigint, text, jsonb, int, int) from public;
revoke execute on function public.finals_enter(bigint, text, jsonb, int, int) from anon;
grant execute on function public.finals_enter(bigint, text, jsonb, int, int) to authenticated;
-- <<< END referee_jobs 20261019 <<<
