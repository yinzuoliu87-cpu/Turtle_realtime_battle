-- 20261021 内测服时钟缝 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261021_beta_server_clock
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261021_beta_server_clock
--     ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、删的约束一个都不留。
-- 同一份脚本在三种库上都跑：沙盒（新建、prod 口径）/ 内测服（service_env = 'beta'、约束已删）/ 正式服。
--   分支只有一处：「server_clock_prod_zero 约束在不在」⇔「这台是不是内测服」（K1 断言两者一致）。
-- 判据（每条配对照组）：
--   K1 约束缺失 ⇔ service_env = 'beta'（正式服 / 沙盒约束在、env = prod；内测服约束不在、env = beta）
--   P1 env = prod ⇒ app_now() = now()（逐值相等）；P2 约束在 ⇒ 写偏移被拒（check_violation）
--   P3 env = prod 而偏移被强行写成非 0（本事务里先删约束造出来）⇒ app_now() 仍 = now()（双保险的第二道）
--   B1 env = beta + 偏移 ⇒ app_now() = now() + 偏移；service_status.clock_offset_sec 跟着变（镜像）
--   B2 周六闸：假时间 = 本周六 12:00 ⇒ referee_gauntlet_start 过了闸（回 bad_snapshot，不是 closed）
--   B3 对照：假时间 = 本周五 12:00 ⇒ closed；B3b 周号按假时间算：拿真实周号去交 ⇒ wrong_week（假时间在下周时）
--   B4 finals_view 回给客户端的 'now' = app_now()
--   B5 beta_tick：假周五 ⇒ 不碰赛程；假周日 18:30 ⇒ finals_seat 分组、round_at = 假时间（不是 now()）
--   B6 beta_tick 在 env = prod 时 ⇒ skipped
--   G  权限：anon 调不了 app_now / beta_tick；authenticated 调不了 beta_tick；三张内部表客户端读不到
--   C  cron：内测服 = beta_tick 在、三条周日任务不在；其余库 = finals_advance / purge_old_matches 真的在
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ctx as
  select (select env from public.service_env where id = 1) as env0,
         exists (select 1 from pg_constraint where conname = 'server_clock_prod_zero') as has_zero,
         gen_random_uuid() as u;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ctx to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 假时间 = 「真实时间所在那一周」的第 wd 天（ISO 1~7）h 点（UTC），+ k 周
-- ★向上取整：now() 带小数秒, 截断会落在目标前 1 秒内（18:00 变 17:59:59.97 ⇒ 第一次实跑 B5 就是这么红的）
create or replace function pg_temp.set_fake(wd int, h int, k int default 0) returns void language plpgsql as $$
declare wk timestamptz := date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (wk + make_interval(days => (wd - 1) + 7 * k, hours => h)) - now()))::bigint where id = 1;
end $$;
create or replace function pg_temp.fake_week() returns bigint language sql as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;

-- K1
select pg_temp.ck('K1 约束缺失 ⇔ 内测服', (select (not has_zero) = (env0 = 'beta') from _ctx),
  (select format('env=%s has_zero=%s', env0, has_zero) from _ctx));

-- P1 / P2 / P3 ─ 正式服口径
update public.service_env set env = 'prod' where id = 1;
select pg_temp.ck('P1 env=prod ⇒ app_now() = now()', public.app_now() = now(),
  format('%s vs %s', public.app_now(), now()));
do $$
declare blocked boolean := false;
begin
  if (select has_zero from _ctx) then
    begin
      update public.server_clock set offset_sec = 3600 where id = 1;
    exception when check_violation then
      blocked := true;
    end;
    perform pg_temp.ck('P2 约束在 ⇒ 写偏移被拒', blocked);
  else
    perform pg_temp.ck('P2 (内测服: 约束已删, 此条改验 K1 已覆盖)', true);
  end if;
end $$;
-- P3 双保险的第二道：本事务里先把约束删掉（回滚即还原），强行写非 0 偏移，env 仍是 prod
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.server_clock set offset_sec = 3600 where id = 1;
select pg_temp.ck('P3 env=prod 而偏移非 0 ⇒ app_now() 仍 = now()', public.app_now() = now(),
  format('%s', public.app_now() - now()));
select pg_temp.ck('P3 分母: 偏移真的写进去了', (select offset_sec from public.server_clock where id = 1) = 3600);

-- 从这里起按内测服口径：env = beta、约束删掉（都在本事务里，回滚即还原）
update public.service_env set env = 'beta' where id = 1;
alter table public.server_clock drop constraint if exists server_clock_prod_zero;

-- B1
update public.server_clock set offset_sec = 86400 where id = 1;
select pg_temp.ck('B1 app_now() = now() + 偏移', public.app_now() = now() + interval '86400 seconds',
  format('%s', public.app_now() - now()));
select pg_temp.ck('B1 service_status.clock_offset_sec 跟着变（镜像）',
  (select clock_offset_sec from public.service_status where id = 1) = 86400);

-- B2 / B3 ─ 周六闸
insert into auth.users (id, aud, role, is_anonymous, created_at)
  values ((select u from _ctx), 'authenticated', 'authenticated', true, now());
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false, gauntlet_server_pick = true where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 1)
  on conflict (client_version) do update set enabled = true, rules_ver = 1;
select pg_temp.set_fake(6, 12);
select pg_temp.as_user((select u from _ctx));
select pg_temp.ck('B2 假周六 ⇒ 过了周六闸（bad_snapshot）',
  (select public.referee_gauntlet_start(pg_temp.fake_week(), null, 0, '9.9.9', 1) ->> 'reason') = 'bad_snapshot',
  (select public.referee_gauntlet_start(pg_temp.fake_week(), null, 0, '9.9.9', 1)::text));
select pg_temp.set_fake(5, 12);
select pg_temp.ck('B3 对照: 假周五 ⇒ closed',
  (select public.referee_gauntlet_start(pg_temp.fake_week(), null, 0, '9.9.9', 1) ->> 'reason') = 'closed');
select pg_temp.set_fake(6, 12, 1);
select pg_temp.ck('B3b 假时间在下周六 ⇒ 拿真实周号交是 wrong_week、拿假周号交过闸',
  (select public.referee_gauntlet_start(extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint, null, 0, '9.9.9', 1) ->> 'reason') = 'wrong_week'
  and (select public.referee_gauntlet_start(pg_temp.fake_week(), null, 0, '9.9.9', 1) ->> 'reason') = 'bad_snapshot');
select pg_temp.as_user(null);

-- B4 ─ finals_view 的 'now'
select pg_temp.set_fake(7, 18);
insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
  values (pg_temp.fake_week(), 77, 2, 1, public.app_now(), false);
select pg_temp.as_user((select u from _ctx));
select pg_temp.ck('B4 finals_view.now = app_now()',
  ((public.finals_view(pg_temp.fake_week(), 77) ->> 'now')::bigint) = extract(epoch from public.app_now())::bigint,
  coalesce(public.finals_view(pg_temp.fake_week(), 77) ->> 'now', 'null'));
select pg_temp.as_user(null);
delete from public.finals_buckets where season_week = pg_temp.fake_week() and bucket_no = 77;

-- B5 ─ beta_tick
select pg_temp.set_fake(5, 12, 2);
select pg_temp.ck('B5 假周五: beta_tick 不碰赛程',
  (select not (r ? 'finals_seat') and not (r ? 'finals_advance') and (r ->> 'isodow')::int = 5
     from (select public.beta_tick() as r) x));
select pg_temp.set_fake(7, 18, 2);
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select gen_random_uuid(), 'authenticated', 'authenticated', true, now() from generate_series(1, 2);
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
  select pg_temp.fake_week(), id, 'p' || row_number() over (), '{}'::jsonb, 4, 1
    from auth.users where id <> (select u from _ctx) order by created_at desc limit 2;
select pg_temp.ck('B5 分母: 假周号下有 2 个报名', (select count(*) from public.finals_pending where season_week = pg_temp.fake_week()) = 2);
select pg_temp.ck('B5 假周日 18:00: beta_tick 分了组',
  (select (r ->> 'finals_seat')::int >= 1 and (r ->> 'isodow')::int = 7 from (select public.beta_tick() as r) x),
  (select last_result::text from public.beta_tick_state where id = 1));
select pg_temp.ck('B5 round_at = 假时间（不是 now()）',
  (select bool_and(round_at = public.app_now()) and bool_and(round_at <> now()) from public.finals_buckets where season_week = pg_temp.fake_week()),
  (select string_agg(round_at::text, ',') from public.finals_buckets where season_week = pg_temp.fake_week()));
select pg_temp.ck('B5 beta_tick_state 记了假时间',
  (select last_fake = public.app_now() from public.beta_tick_state where id = 1));

-- B6
update public.service_env set env = 'prod' where id = 1;
select pg_temp.ck('B6 env=prod ⇒ beta_tick skipped', (public.beta_tick() ->> 'skipped') = 'not_beta');

-- G ─ 权限
select pg_temp.ck('G anon 调不了 app_now / beta_tick',
  not has_function_privilege('anon', 'public.app_now()', 'execute')
  and not has_function_privilege('anon', 'public.beta_tick()', 'execute'));
select pg_temp.ck('G authenticated 调得了 app_now、调不了 beta_tick',
  has_function_privilege('authenticated', 'public.app_now()', 'execute')
  and not has_function_privilege('authenticated', 'public.beta_tick()', 'execute'));
select pg_temp.ck('G 内部表客户端读不到',
  not has_table_privilege('anon', 'public.server_clock', 'select')
  and not has_table_privilege('authenticated', 'public.server_clock', 'select')
  and not has_table_privilege('authenticated', 'public.service_env', 'select')
  and not has_table_privilege('authenticated', 'public.schema_migrations', 'select')
  and not has_table_privilege('authenticated', 'public.beta_tick_state', 'select'));
select pg_temp.ck('G 分母: service_status 照常读得到（客户端拿偏移的那一列）',
  exists (select 1 from pg_policies where tablename = 'service_status' and policyname = 'status_read_anon' and cmd = 'SELECT')
  and exists (select 1 from information_schema.columns where table_name = 'service_status' and column_name = 'clock_offset_sec'));

-- C ─ cron
select pg_temp.ck('C cron: 内测服 = beta_tick 在且周日三条不在; 其余 = finals_advance / purge_old_matches 在',
  case when (select env0 from _ctx) = 'beta' then
    exists (select 1 from cron.job where jobname = 'beta_tick')
    and not exists (select 1 from cron.job where jobname in ('finals_seat', 'finals_cup_seat', 'finals_advance'))
  else
    exists (select 1 from cron.job where jobname = 'finals_advance' and schedule = '* * * * 0')
    and exists (select 1 from cron.job where jobname = 'purge_old_matches' and schedule = '0 0 * * 2')
  end,
  (select string_agg(jobname || ' ' || schedule, '; ' order by jobname) from cron.job));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 20 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
