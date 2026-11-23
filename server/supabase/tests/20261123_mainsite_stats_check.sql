-- 20261123 主站数据接口 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta|prod --rehearse 20261123_mainsite_stats
-- ★内测服 / 正式服上已有真数据 ⇒ 日活 / 新增一律量「造数前后的差」（_mainsite_stats_compute 现算），不量绝对值。
-- 造人（D = UTC 今天）：
--   u0 真人  D-1 新建                                  ⇒ 新增、日活
--   u1 真人  D-9 新建，D-1 续期令牌                      ⇒ 日活
--   u2 真人  D-9 新建，D-3 续期令牌                      ⇒ D-1 不算
--   u3 真人  D-9 新建，D-1 打了一场裁判局（a 侧）          ⇒ 日活
--   b0 陪练  D-1 新建                                  ⇒ 只进 *_all
--   b1 陪练  D-9 新建，D-1 裁判局 b 侧 + 同一天续期令牌两次 ⇒ 只进 *_all，且只算 1 次
-- 判据：
--   M1 D-1 差值：new_human +1 / new_all +2 / dau_human +3 / dau_all +5
--   M2 固定：D-2 第一次问 ⇒ 写表、final=true；之后再造一个 D-2 新号，再问 ⇒ 数字不变（现算会 +1）
--   M3 不带日期 = 昨天；今天 final=false；明天 not_yet；2026-09-30 too_old
--   M4 p_humans=false 回 *_all
--   L1 排行榜（造一个没人用的周 2100-01-04）：真人两个 + 陪练一个 + seed_ 快照一个；
--      p_humans=true ⇒ total 2、名次按胜场；p_humans=false ⇒ total 3；seed_ 永远不算；字段只有 rank/nickname/wins/hearts/battles
--   L2 同一个号同一周多份快照 ⇒ 取场次最多那份；ranked_records 有就以它为准
--   P  权限：三个函数 / 表都不给 anon / authenticated；定时任务 mainsite_stats_freeze 在
begin;
create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.d(p_off int) returns timestamptz language sql as $$
  select ((((now() at time zone 'UTC')::date + p_off)::timestamp + interval '12 hours') at time zone 'UTC') $$;
create or replace function pg_temp.dd(p_off int) returns date language sql as $$ select (now() at time zone 'UTC')::date + p_off $$;

-- 造数前的基线
create temp table _b0 as select public._mainsite_stats_compute(pg_temp.dd(-1)) as c;

insert into _u values ('u0', gen_random_uuid()), ('u1', gen_random_uuid()), ('u2', gen_random_uuid()), ('u3', gen_random_uuid()),
                      ('b0', gen_random_uuid()), ('b1', gen_random_uuid()), ('late', gen_random_uuid()),
                      ('L1', gen_random_uuid()), ('L2', gen_random_uuid()), ('LB', gen_random_uuid()), ('LS', gen_random_uuid());
insert into auth.users (id, aud, role, is_anonymous, created_at) values
  (pg_temp.u('u0'), 'authenticated', 'authenticated', true, pg_temp.d(-1)),
  (pg_temp.u('u1'), 'authenticated', 'authenticated', true, pg_temp.d(-9)),
  (pg_temp.u('u2'), 'authenticated', 'authenticated', true, pg_temp.d(-9)),
  (pg_temp.u('u3'), 'authenticated', 'authenticated', true, pg_temp.d(-9)),
  (pg_temp.u('b0'), 'authenticated', 'authenticated', true, pg_temp.d(-1)),
  (pg_temp.u('b1'), 'authenticated', 'authenticated', true, pg_temp.d(-9)),
  (pg_temp.u('L1'), 'authenticated', 'authenticated', true, pg_temp.d(-20)),
  (pg_temp.u('L2'), 'authenticated', 'authenticated', true, pg_temp.d(-20)),
  (pg_temp.u('LB'), 'authenticated', 'authenticated', true, pg_temp.d(-20)),
  (pg_temp.u('LS'), 'authenticated', 'authenticated', true, pg_temp.d(-20));
insert into public.bot_accounts (account_id) values (pg_temp.u('b0')), (pg_temp.u('b1')), (pg_temp.u('LB'));
insert into auth.refresh_tokens (token, user_id, revoked, created_at) values
  ('t-u1', pg_temp.u('u1')::text, false, pg_temp.d(-1)),
  ('t-u2', pg_temp.u('u2')::text, false, pg_temp.d(-3)),
  ('t-b1a', pg_temp.u('b1')::text, false, pg_temp.d(-1)),
  ('t-b1b', pg_temp.u('b1')::text, false, pg_temp.d(-1) + interval '1 hour');
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, created_at)
  values ('gauntlet', 'chk20261123:' || gen_random_uuid(), 4102444800, '0.0.0', 1, pg_temp.u('u3'), pg_temp.u('b1'), '{}'::jsonb, '{}'::jsonb, pg_temp.d(-1));

create temp table _b1 as select public._mainsite_stats_compute(pg_temp.dd(-1)) as c;
select pg_temp.ck('M1 D-1 差值: new_human +1 / new_all +2 / dau_human +3 / dau_all +5',
  (select (b1.c->>'new_human')::int - (b0.c->>'new_human')::int = 1
      and (b1.c->>'new_all')::int   - (b0.c->>'new_all')::int   = 2
      and (b1.c->>'dau_human')::int - (b0.c->>'dau_human')::int = 3
      and (b1.c->>'dau_all')::int   - (b0.c->>'dau_all')::int   = 5 from _b0 b0, _b1 b1),
  (select format('前 %s 后 %s', b0.c, b1.c) from _b0 b0, _b1 b1));

-- M2 固定
create temp table _f1 as select public.mainsite_stats_daily(pg_temp.dd(-2), true) as r;
insert into auth.users (id, aud, role, is_anonymous, created_at) values (pg_temp.u('late'), 'authenticated', 'authenticated', true, pg_temp.d(-2));
create temp table _f2 as select public.mainsite_stats_daily(pg_temp.dd(-2), true) as r;
select pg_temp.ck('M2 D-2 第一次问写表 final=true; 再造一个 D-2 新号后再问, 数字不变',
  (select (f1.r->>'final')::boolean and (f2.r->>'final')::boolean
      and f1.r->>'new_players' = f2.r->>'new_players' and f1.r->>'dau' = f2.r->>'dau'
      and exists (select 1 from public.mainsite_daily_stats where day = pg_temp.dd(-2)) from _f1 f1, _f2 f2),
  (select format('%s / %s', f1.r, f2.r) from _f1 f1, _f2 f2));
select pg_temp.ck('M2b 现算(不固定)确实会多 1 —— 证明 M2 的「不变」是固定住的, 不是本来就没变',
  (select (public._mainsite_stats_compute(pg_temp.dd(-2))->>'new_human')::int = (f1.r->>'new_players')::int + 1 from _f1 f1),
  (select format('现算 %s / 固定 %s', public._mainsite_stats_compute(pg_temp.dd(-2)), f1.r) from _f1 f1));

-- M3 日期
select pg_temp.ck('M3 不带日期 = 昨天; 今天 final=false; 明天 not_yet; 2026-09-30 too_old',
  (public.mainsite_stats_daily(null, true)->>'day')::date = pg_temp.dd(-1)
  and (public.mainsite_stats_daily(pg_temp.dd(0), true)->>'final')::boolean = false
  and public.mainsite_stats_daily(pg_temp.dd(1), true)->>'error' = 'not_yet'
  and public.mainsite_stats_daily(date '2026-09-30', true)->>'error' = 'too_old',
  format('%s | %s | %s', public.mainsite_stats_daily(null, true), public.mainsite_stats_daily(pg_temp.dd(0), true),
         public.mainsite_stats_daily(pg_temp.dd(1), true)));

-- M4 含陪练号那一套
select pg_temp.ck('M4 p_humans=false 回 *_all(D-1 新增比真人多 ≥ 1: 造了一个陪练新号)',
  (public.mainsite_stats_daily(pg_temp.dd(-1), false)->>'new_players')::int
    >= (public.mainsite_stats_daily(pg_temp.dd(-1), true)->>'new_players')::int + 1,
  format('%s / %s', public.mainsite_stats_daily(pg_temp.dd(-1), false), public.mainsite_stats_daily(pg_temp.dd(-1), true)));

-- L 排行榜（周 4102444800 = 2100-01-04 周一，库里不会有真数据）
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, client_version, uploaded_at) values
  (pg_temp.u('L1'), 4102444800, 3, '{"profile":{"name":"甲"}}', 2, 5, '0.0.0', now()),
  (pg_temp.u('L1'), 4102444800, 6, '{"profile":{"name":"甲"}}', 4, 4, '0.0.0', now()),
  (pg_temp.u('L2'), 4102444800, 5, '{"profile":{"name":"乙"}}', 5, 3, '0.0.0', now()),
  (pg_temp.u('LB'), 4102444800, 5, '{"profile":{"name":"陪"}}', 9, 6, '0.0.0', now()),
  (pg_temp.u('LS'), 4102444800, 5, '{"profile":{"name":"种"},"ghost_id":"seed_x"}', 9, 6, '0.0.0', now());
insert into public.ranked_records (season_week, account_id, battles, wins, hearts)
  values (4102444800, pg_temp.u('L1'), 7, 6, 4);
create temp table _l1 as select public.mainsite_stats_leaderboard(4102444800, 100, true) as r;
create temp table _l2 as select public.mainsite_stats_leaderboard(4102444800, 100, false) as r;
select pg_temp.ck('L1 真人榜: total 2, 第 1 名 甲(ranked_records 6 胜 > 乙 5 胜), 字段只有 rank/nickname/wins/hearts/battles',
  (select (r->>'total')::int = 2 and r->'rows'->0->>'nickname' = '甲' and (r->'rows'->0->>'wins')::int = 6
      and (r->'rows'->0->>'battles')::int = 7 and r->'rows'->1->>'nickname' = '乙'
      and (select array_agg(k order by k) from jsonb_object_keys(r->'rows'->0) k) = array['battles','hearts','nickname','rank','wins']
     from _l1), (select r::text from _l1));
select pg_temp.ck('L1b 含陪练号: total 3, 陪练号 9 胜排第 1; seed_ 快照两边都不算',
  (select (r->>'total')::int = 3 and r->'rows'->0->>'nickname' = '陪'
      and not exists (select 1 from jsonb_array_elements(r->'rows') e where e->>'nickname' = '种') from _l2),
  (select r::text from _l2));

-- P 权限 + 定时任务
select pg_temp.ck('P 函数 / 表不给 anon / authenticated; mainsite_stats_freeze 定时任务在',
  not has_function_privilege('anon', 'public.mainsite_stats_daily(date, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.mainsite_stats_daily(date, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.mainsite_stats_leaderboard(bigint, int, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public._mainsite_stats_compute(date)', 'execute')
  and has_function_privilege('service_role', 'public.mainsite_stats_daily(date, boolean)', 'execute')
  and not has_table_privilege('authenticated', 'public.mainsite_daily_stats', 'select')
  and exists (select 1 from cron.job where jobname = 'mainsite_stats_freeze' and schedule = '10 0 * * *'));

do $$
declare v_fail int; v_n int; v_msg text;
begin
  select count(*) filter (where not pass), count(*) into v_fail, v_n from _chk;
  select string_agg(name || ' :: ' || info, ' | ') into v_msg from _chk where not pass;
  if v_fail = 0 then
    raise exception 'ALL PASS (% 条)', v_n;
  else
    raise exception 'FAIL % / %: %', v_fail, v_n, v_msg;
  end if;
end $$;
