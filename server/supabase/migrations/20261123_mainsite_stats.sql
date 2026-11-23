-- >>> BEGIN mainsite_stats 20261123 >>>
-- ─────────────────────────────────────────────────────────────
-- 给龟投（主站）的运营数字接口（2026-11-23 · 方案书 docs/plans/20261123-主站数据接口.md）
--   Tom 11-22：「每日数据我们用接口来拉…地址、鉴权方式、返回字段（每日新增、日活、每周排行榜的昵称和数值），
--     「一天」按哪个时区，以及调用频率限制」。用户 11-22 拍板「每天自动给新增 / 日活，每周一给排行榜（只给数字和昵称）」。
--   入口在裁判机网关（server/referee/mainsite_gateway.py，HMAC 验签）；本迁移只给它两个 service_role 函数 + 一张每日数字表。
--
--   一天 = UTC 0 点切（与游戏赛程同一时区）。
--   新增 new_*  = 当天新建的 auth.users（首次打开游戏即匿名建号）。
--   日活 dau_*  = 当天「续期过登录令牌（auth.refresh_tokens 新发一张）∪ 当天新建 ∪ 当天打过裁判局（referee_jobs 两侧）」的账号去重。
--     实测（11-16~11-22 正式服只读）：去掉陪练号后 4–6 人 / 天；不去掉 ≈ 100（陪练号 296 个，bot_accounts）。
--   *_human = 去掉陪练号（bot_accounts）；*_all = 含陪练号。两套都存：陪练号算不算由主站选（11-23 问 Tom），网关按配置挑一套回，库不用再改。
--   过去的某一天第一次被问到（或每天 00:10 UTC 定时任务）时算一次、写进 mainsite_daily_stats，之后固定不变：
--     auth.refresh_tokens 会随会话清理、purge_junk_anon_users（04:30 UTC）会删没留下任何数据的匿名号 ⇒ 事后再算会变少。
--   当天（UTC 今天）现算、不落表（final=false）。
--   每周排行榜 = 游戏内 week_leaderboard 同一套排序与过滤（不要求登录；按 p_humans 决定去不去陪练号）；只回名次、昵称、胜场、剩余生命、总场次。
-- 回滚：drop function public.mainsite_stats_daily(date, boolean); drop function public.mainsite_stats_leaderboard(bigint, int, boolean);
--   drop function public._mainsite_stats_compute(date); select cron.unschedule('mainsite_stats_freeze'); drop table public.mainsite_daily_stats;
-- ★不改任何已有表 / 函数。重复执行安全。
-- ─────────────────────────────────────────────────────────────

create table if not exists public.mainsite_daily_stats (
  day          date        primary key,
  new_human    int         not null,
  dau_human    int         not null,
  new_all      int         not null,
  dau_all      int         not null,
  computed_at  timestamptz not null default now()
);
alter table public.mainsite_daily_stats enable row level security;
revoke all on table public.mainsite_daily_stats from anon, authenticated;
grant all on table public.mainsite_daily_stats to service_role;

-- 现算某一天（UTC）的四个数。内部函数，不授权。
create or replace function public._mainsite_stats_compute(p_day date) returns jsonb
language sql stable security definer set search_path = public, auth as $$
  with b as (select (p_day::timestamp at time zone 'UTC') as t0, ((p_day + 1)::timestamp at time zone 'UTC') as t1),
  newu as (
    select u.id from auth.users u, b where u.created_at >= b.t0 and u.created_at < b.t1
  ), act as (
    select t.user_id::uuid as id from auth.refresh_tokens t, b
     where t.created_at >= b.t0 and t.created_at < b.t1 and t.user_id ~ '^[0-9a-f-]{36}$'
    union select id from newu
    union select j.a_account from public.referee_jobs j, b where j.created_at >= b.t0 and j.created_at < b.t1 and j.a_account is not null
    union select j.b_account from public.referee_jobs j, b where j.created_at >= b.t0 and j.created_at < b.t1 and j.b_account is not null
  )
  select jsonb_build_object(
    'new_all',   (select count(*) from newu)::int,
    'new_human', (select count(*) from newu n where not exists (select 1 from public.bot_accounts x where x.account_id = n.id))::int,
    'dau_all',   (select count(*) from act)::int,
    'dau_human', (select count(*) from act a where not exists (select 1 from public.bot_accounts x where x.account_id = a.id))::int)
$$;
revoke all on function public._mainsite_stats_compute(date) from public, anon, authenticated;

-- 某一天的数字。p_day 为空 = 昨天（UTC）。过去的日子：表里有就回表里的，没有就算一次写进去（final=true）；今天：现算（final=false）；将来：not_yet。
create or replace function public.mainsite_stats_daily(p_day date default null, p_humans boolean default true) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_day   date := coalesce(p_day, v_today - 1);
  c jsonb; r public.mainsite_daily_stats;
begin
  if v_day > v_today then
    return jsonb_build_object('ok', false, 'error', 'not_yet');
  end if;
  if v_day < date '2026-10-01' then
    return jsonb_build_object('ok', false, 'error', 'too_old');
  end if;
  if v_day = v_today then
    c := public._mainsite_stats_compute(v_day);
    return jsonb_build_object('ok', true, 'day', v_day, 'tz', 'UTC', 'final', false,
      'new_players', (c ->> case when p_humans then 'new_human' else 'new_all' end)::int,
      'dau',         (c ->> case when p_humans then 'dau_human' else 'dau_all' end)::int);
  end if;
  select * into r from public.mainsite_daily_stats where day = v_day;
  if not found then
    c := public._mainsite_stats_compute(v_day);
    insert into public.mainsite_daily_stats (day, new_human, dau_human, new_all, dau_all)
      values (v_day, (c ->> 'new_human')::int, (c ->> 'dau_human')::int, (c ->> 'new_all')::int, (c ->> 'dau_all')::int)
      on conflict (day) do nothing;
    select * into r from public.mainsite_daily_stats where day = v_day;
  end if;
  return jsonb_build_object('ok', true, 'day', v_day, 'tz', 'UTC', 'final', true,
    'new_players', case when p_humans then r.new_human else r.new_all end,
    'dau',         case when p_humans then r.dau_human else r.dau_all end);
end $$;
revoke all on function public.mainsite_stats_daily(date, boolean) from public, anon, authenticated;
grant execute on function public.mainsite_stats_daily(date, boolean) to service_role;

-- 某一周的积分赛排行榜（p_week = 那周周一 00:00 UTC 的 epoch 秒，与 season_week 同一个数）。
--   排序 / 过滤与 week_leaderboard 逐条一致（快照池 seed_ / is_bot / 闯关快照不算；ranked_records 优先）；不要求登录。
--   p_humans = true ⇒ 再去掉陪练号（bot_accounts）。名次在过滤之后重排。
create or replace function public.mainsite_stats_leaderboard(p_week bigint, p_limit int default 100, p_humans boolean default true)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 100), 1), 500); tot int; top jsonb;
begin
  with gh as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
       and (not p_humans or not exists (select 1 from public.bot_accounts x where x.account_id = g.account_id))
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), latest as (
    select gh.account_id, coalesce(rr.wins, gh.season_wins) as wins, coalesce(rr.hearts, gh.hearts) as hearts,
           coalesce(rr.sweeps, gh.season_sweeps) as sweeps, coalesce(rr.battles, gh.battles) as battles,
           gh.uploaded_at, gh.name
      from gh
      left join public.ranked_records rr on rr.season_week = p_week and rr.account_id = gh.account_id
  ), ranked as (
    select l.*, row_number() over (order by l.wins desc, l.hearts desc, l.sweeps desc, l.uploaded_at asc, l.account_id) as rk
      from latest l
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object('rank', r.rk, 'nickname', coalesce(r.name, '?'),
                  'wins', r.wins, 'hearts', r.hearts, 'battles', r.battles) order by r.rk) filter (where r.rk <= lim), '[]'::jsonb)
    into tot, top
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'rows', top);
end $$;
revoke all on function public.mainsite_stats_leaderboard(bigint, int, boolean) from public, anon, authenticated;
grant execute on function public.mainsite_stats_leaderboard(bigint, int, boolean) to service_role;

-- 每天 00:10 UTC 把昨天固定下来（主站没来拉也照样固定，之后再问同一天数字不变）。
select cron.unschedule(jobid) from cron.job where jobname = 'mainsite_stats_freeze';
select cron.schedule('mainsite_stats_freeze', '10 0 * * *', 'select public.mainsite_stats_daily(null, true)');
-- <<< END mainsite_stats 20261123 <<<
