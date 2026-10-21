-- >>> BEGIN beta_server_clock 20261021 >>>
-- ─────────────────────────────────────────────────────────────
-- 内测服的服务端时钟缝 + 迁移账本 + 两条只在注释里的 cron 补成真语句
--   （2026-10-21 · 方案书 docs/plans/20261020-内测服.md §2 / §5）
--   ★正式服【还没执行】。上正式服只走 tools/sb_migrate.py 全流程（sandbox → beta → prod 演练 → prod 上线），
--     内测服 turtle-beta 已按本段建过（见方案书实施回填）。
--
-- 为什么：周六闯关「只有周六能交」、周日分组 / 冠军杯赛 / 推进、购物窗 —— 全是服务端直接比 now()。
--   客户端时间穿越骗不过它们；假周号只骗得过 finals_seat 一个函数（方案书调查 C、出入 2）。
--   ⇒ 服务端也要一条时钟缝：app_now() = now() + 偏移（只有内测服能设偏移）。
--
-- ① service_env：这台是哪台（单行，默认 'prod'）。只有 beta_setup.sql（tools/beta_ops.py / sb_migrate.py，
--    写死只认内测服 ref）会把它改成 'beta'。
-- ② server_clock：偏移秒数（单行）。★表上带 `server_clock_prod_zero check (offset_sec = 0)` ——
--    正式服即使误执行「设偏移」也写不进去；内测服的 beta_setup.sql 把这条约束删掉。
-- ③ app_now()：service_env = 'beta' 才加偏移，否则恒等于 now()（双保险：约束 + 判台）。
--    ★同一事务里 now() 是事务开始时刻 ⇒ 正式服上 app_now() 与 now() 逐值相等（检查脚本 P1 断言）。
-- ④ now() 只换「赛程闸」那一类（现在是不是周六 / 本周是哪周 / 购物窗开没开 / 这一轮该不该推进 /
--    轮次开始时刻 round_at / 回给客户端倒计时用的 'now'）；「这一行什么时候写的」（created_at / updated_at /
--    租约 / 清理年龄 / 限流窗口）保持 now()。逐条分类清单见方案书实施回填「now() 分类」。
-- ⑤ service_status.clock_offset_sec：客户端读服务状态时顺手拿到偏移（内测服包把它叠到 now_utc() 上，
--    正式包不读）。由 server_clock 上的触发器镜像过去 ⇒ 只有一份事实源。
-- ⑥ schema_migrations：迁移账本（name / sha256 / 何时 / 谁）。tools/sb_migrate.py 写；
--    「正式服只收内测服上过、同一 sha256 的迁移」靠它。
-- ⑦ beta_tick()：内测服每分钟一次（pg_cron 只在内测服装，见 beta_setup.sql），按 app_now() 判该不该调
--    finals_seat / finals_cup_seat / finals_advance，周号也按 app_now() 算。正式服上调它直接返回 skipped。
-- ⑧ 两条线上一直在跑、仓库里只有注释的 cron（finals_advance / purge_old_matches）写成真语句，
--    命令文本逐字照抄正式服 cron.job（2026-10-21 只读回读）。
-- ★重复执行安全（if not exists / create or replace / on conflict do nothing / 先 unschedule 再 schedule）。
-- ─────────────────────────────────────────────────────────────

-- ① 这台是哪台
create table if not exists public.service_env (
  id   int  primary key default 1,
  env  text not null default 'prod',
  constraint service_env_single_row check (id = 1),
  constraint service_env_known check (env in ('prod', 'beta'))
);
insert into public.service_env (id, env) values (1, 'prod') on conflict (id) do nothing;
alter table public.service_env enable row level security;
revoke all on table public.service_env from anon, authenticated;

-- ② 偏移（正式服约束恒 0）
create table if not exists public.server_clock (
  id         int         primary key default 1,
  offset_sec bigint      not null default 0,
  updated_at timestamptz not null default now(),
  constraint server_clock_single_row check (id = 1),
  constraint server_clock_prod_zero check (offset_sec = 0)
);
insert into public.server_clock (id) values (1) on conflict (id) do nothing;
alter table public.server_clock enable row level security;
revoke all on table public.server_clock from anon, authenticated;

-- ③ 时钟缝
create or replace function public.app_now()
returns timestamptz language sql stable security definer set search_path = public as $$
  select case
    when coalesce((select e.env from public.service_env e where e.id = 1), 'prod') = 'beta'
      then now() + make_interval(secs => coalesce((select c.offset_sec from public.server_clock c where c.id = 1), 0))
    else now()
  end
$$;
revoke all on function public.app_now() from public, anon;
grant execute on function public.app_now() to authenticated, service_role;

-- ⑤ 客户端读得到的偏移（镜像，不是第二份事实源）
alter table public.service_status add column if not exists clock_offset_sec bigint not null default 0;
create or replace function public.server_clock_mirror() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.service_status set clock_offset_sec = new.offset_sec where id = 1;
  return new;
end $$;
revoke all on function public.server_clock_mirror() from public, anon, authenticated;
drop trigger if exists server_clock_mirror on public.server_clock;
create trigger server_clock_mirror after insert or update on public.server_clock
  for each row execute function public.server_clock_mirror();

-- ⑥ 迁移账本
create table if not exists public.schema_migrations (
  name       text        primary key,
  sha256     text        not null,
  applied_at timestamptz not null default now(),
  applied_by text        not null default '',
  note       text        not null default ''
);
alter table public.schema_migrations enable row level security;
revoke all on table public.schema_migrations from anon, authenticated;

-- ⑦ 内测服赛程推进器
create table if not exists public.beta_tick_state (
  id          int         primary key default 1,
  last_fake   timestamptz,
  last_real   timestamptz,
  last_result jsonb,
  constraint beta_tick_state_single_row check (id = 1)
);
alter table public.beta_tick_state enable row level security;
revoke all on table public.beta_tick_state from anon, authenticated;

-- 与正式服 cron 的对应（正式服：finals_seat '*/10 18-23 * * 0' / finals_cup_seat '*/5 20-23 * * 0' /
--   finals_advance '* * * * 0'）。三个函数都幂等（已坐定 / 已成表就返回 0），所以每分钟叫一次与
--   每 10 / 5 分钟叫一次结果相同；差别只在冠军杯赛「等组打完」那段可能早几分钟成表（内测服可接受）。
create or replace function public.beta_tick()
returns jsonb language plpgsql security definer set search_path = public as $$
declare t timestamptz; u timestamp; wk bigint; dow int; hr int; n int; res jsonb := '{}'::jsonb;
begin
  if coalesce((select e.env from public.service_env e where e.id = 1), 'prod') <> 'beta' then
    return jsonb_build_object('skipped', 'not_beta');
  end if;
  t := public.app_now();
  u := t at time zone 'UTC';
  wk := extract(epoch from date_trunc('week', u))::bigint;   -- = 客户端 week_anchor_utc（周一 00:00 UTC）
  dow := extract(isodow from u)::int;
  hr := extract(hour from u)::int;
  if dow = 7 and hr >= 18 then
    n := public.finals_seat(wk);
    res := res || jsonb_build_object('finals_seat', n);
  end if;
  if dow = 7 and hr >= public.finals_cup_hour() then
    n := public.finals_cup_seat(wk);
    res := res || jsonb_build_object('finals_cup_seat', n);
  end if;
  if dow = 7 then
    n := public.finals_advance(wk);
    res := res || jsonb_build_object('finals_advance', n);
  end if;
  res := res || jsonb_build_object('fake', t, 'week', wk, 'isodow', dow, 'hour', hr);
  insert into public.beta_tick_state (id, last_fake, last_real, last_result) values (1, t, now(), res)
    on conflict (id) do update set last_fake = excluded.last_fake, last_real = excluded.last_real,
                                   last_result = excluded.last_result;
  return res;
end $$;
revoke all on function public.beta_tick() from public, anon, authenticated;

-- ⑧ 线上一直在跑、仓库里原来只有注释的两条 cron（命令文本逐字照抄正式服 cron.job，2026-10-21 只读回读）
select cron.unschedule(jobid) from cron.job where jobname = 'finals_advance';
select cron.schedule('finals_advance', '* * * * 0', 'select public.finals_advance(
      (extract(epoch from date_trunc(''week'', now() at time zone ''UTC''))::bigint))');
select cron.unschedule(jobid) from cron.job where jobname = 'purge_old_matches';
select cron.schedule('purge_old_matches', '0 0 * * 2', 'select public.purge_old_matches()');

-- ④ 赛程闸改调 app_now()（12 个函数）。正文逐字照抄 schema.sql 现行版，只改 now() → public.app_now() 的那几行。

-- finals_seat（照抄 schema.sql 第 1456~1490 行现行版; 只改标了 app_now 的行）
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
    select p_week, bucket_no, count(*)::int, 1, public.app_now(), count(*) = 1,
           case when count(*) = 1 then public.app_now() else null end
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;

-- finals_cup_seat（照抄 schema.sql 第 1573~1614 行现行版; 只改标了 app_now 的行）
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
  select count(*), count(*) filter (where not closed) into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and public.app_now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
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
    values (p_week, cup, i, 1, public.app_now(), i <= 1, case when i <= 1 then public.app_now() else null end);
  return i;
end $$;

-- finals_view（照抄 schema.sql 第 2021~2091 行现行版; 只改标了 app_now 的行）
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
  -- ★2026-10-12 比分(败方赢了几路 0/1 ⇒ 2:0 / 2:1): 与 done 同一道可见性(当前轮不下发)
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes)
           filter (where r.loser_lanes is not null), '{}'::jsonb)
    into sc from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)。客户端按它算开播窗口。
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻: 客户端拿这个倒计时, 不必知道「一轮多长」
    'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
    'now', extract(epoch from public.app_now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res, 'scores', sc);
end $function$;

-- finals_week_view（照抄 schema.sql 第 2093~2149 行现行版; 只改标了 app_now 的行）
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
                       and (b.closed or r.round < b.round)),
           'scores', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes) filter (where r.loser_lanes is not null), '{}'::jsonb)
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
                       and (b.closed or r.round < b.round)),
           'scores', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes) filter (where r.loser_lanes is not null), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)))
    into cp from public.finals_buckets b
   where b.season_week = p_week and b.bucket_no = cup;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from public.app_now())::bigint, 'buckets', bs, 'cup', cp);
end $function$;

-- finals_update_snapshot（照抄 schema.sql 第 2261~2282 行现行版; 只改标了 app_now 的行）
create or replace function public.finals_update_snapshot(p_week bigint, p_bucket int, p_snapshot jsonb)
returns boolean
language plpgsql security definer set search_path = public as $$
declare b record; n int;
begin
  if auth.uid() is null or p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
     or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') < 3 then
    return false;                       -- 没有 3 只统领的快照不收(防空阵容覆盖周六那份正式阵容)
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

-- finals_opponent（照抄 schema.sql 第 2288~2340 行现行版; 只改标了 app_now 的行）
create or replace function public.finals_opponent(p_week bigint, p_bucket integer, p_round integer, p_seed integer,
    p_match integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare b record; mine int; asked int; snap jsonb; nm text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  -- ★2026-10-12: 购物窗内不给对手快照 —— 对手还在购物, 给出去的是他购物前的阵容(S4)
  if public.app_now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  -- ★2026-10-12: 这一场已经有结果 ⇒ 不再给(每场只算一次; 不泄露胜负, 只说已结算)
  if p_match is not null and exists (select 1 from public.finals_results
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = p_match) then
    return jsonb_build_object('ok', false, 'reason', 'settled');
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_seed = mine then
    return jsonb_build_object('ok', false, 'reason', 'thats_you');
  end if;
  select snapshot, name into snap, nm from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and seed = p_seed;
  if snap is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_seed');
  end if;
  insert into public.finals_scout (season_week, bucket_no, round, account_id, seed)
    values (p_week, p_bucket, p_round, auth.uid(), p_seed)
    on conflict (season_week, bucket_no, round, account_id) do nothing;
  select seed into asked from public.finals_scout
   where season_week = p_week and bucket_no = p_bucket
     and round = p_round and account_id = auth.uid();
  if asked <> p_seed then
    return jsonb_build_object('ok', false, 'reason', 'already_asked', 'seed', asked);
  end if;
  return jsonb_build_object('ok', true, 'seed', p_seed, 'name', nm, 'snapshot', snap);
end $function$;

-- referee_enqueue_finals（照抄 schema.sql 第 2813~2865 行现行版; 只改标了 app_now 的行）
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

-- finals_advance（照抄 schema.sql 第 3125~3218 行现行版; 只改标了 app_now 的行）
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
    if public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec()) then
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
      if public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 2) then
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
       and public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 3) then
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
      update public.finals_buckets set closed = true, revealed_at = public.app_now()
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = public.app_now(), revealed_at = public.app_now()
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;

-- finals_report（照抄 schema.sql 第 3223~3282 行现行版; 只改标了 app_now 的行）
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
  if public.app_now() < open_at then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  if p_reporter_side = 1 and public.app_now() < open_at + make_interval(secs => public.finals_lower_grace_sec()) then
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

-- referee_live_gauntlet（照抄 schema.sql 第 3409~3437 行现行版; 只改标了 app_now 的行）
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

-- referee_gauntlet_start（照抄 schema.sql 第 4202~4313 行现行版; 只改标了 app_now 的行）
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
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400)) then
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
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'gw', v_gw, 'gl', v_gl);
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

-- referee_submit_gauntlet（照抄 schema.sql 第 4320~4386 行现行版; 只改标了 app_now 的行）
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
  -- ★2026-10-20 周六对手改服务器挑: 开关开着时不再收客户端挑的对手(新客户端走 referee_gauntlet_start)
  if coalesce(cfg.gauntlet_server_pick, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if not exists (select 1 from public.referee_versions where client_version = p_client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400)) then
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

-- 上线步骤（★正式服还没执行；只走 tools/sb_migrate.py，每步不过就停）：
--   1. python tools/sb_migrate.py sandbox 20261021_beta_server_clock          ⇒ ALL PASS
--   2. python tools/sb_migrate.py beta --rehearse / --apply                   ⇒ 内测服已上（2026-10-21）
--   3. python tools/sb_migrate.py prod --rehearse                              ⇒ 生产回滚事务里「本段 + 检查脚本」ALL PASS
--   4. python tools/sb_migrate.py prod --apply（要用户点头）                   ⇒ 回读 12 个函数体与仓库逐字相同
--   正式服回读：select public.app_now() = now();  -- true（同一事务）
--             update public.server_clock set offset_sec = 60;  -- 被 server_clock_prod_zero 拒
--   回滚：12 个函数换回 git tag v0.21.4 的 schema.sql 版本；新表 / app_now / beta_tick 留着无害（正式服 beta_tick 恒 skipped）。
-- <<< END beta_server_clock 20261021 <<<
