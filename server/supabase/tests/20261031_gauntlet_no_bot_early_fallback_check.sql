-- 20261031 闯关赛在线排队：确定没有陪练号能来 ⇒ 真人进队满 1 分钟就兜底 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261031_gauntlet_no_bot_early_fallback
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行、调度器心跳一个都不留。
-- 假时间照 20261029c 检查脚本；全部用 rules_ver = 99 / 版本 9.9.9（与库里真实排队、快照、机器人池不相交）。
-- 判据（假周六 12:00；每组各占一个格子）：
--   E0 新件在位：gauntlet_planner_stale_sec() = 60；gauntlet_queue.no_bot_at 列在
--   E1 调度器从没报过到（心跳表空）：真人独自等 61 秒 ⇒ 照旧等（与 20261029c 相同 —— 迁移先于新调度器上线时不变）
--   E2 调度器把他报成没号：等 61 秒 ⇒ 当场兜底，meta.early = 'no_bot'
--   E3 报成没号但只等了 59 秒 ⇒ 仍等（前 1 分钟只配真人不变）
--   E4 下一拍名单里没有他了 ⇒ no_bot_at 清掉；等 61 秒 ⇒ 照旧等
--   E5 调度器心跳新鲜、没报他：等 61 秒 ⇒ 照旧等
--   E6 照旧的 180 秒兜底不变：等 181 秒 ⇒ 兜底，meta 里没有 early
--   E7 被报成没号，但同格子正好有陪练号在等 ⇒ 配上陪练号（配对局），不兜底
--   E8 调度器报过到、心跳断了 61 秒：没被报的真人等 61 秒 ⇒ 兜底，meta.early = 'planner_gone'
--   E9 陪练号：名单里有它也不置 no_bot_at；心跳断了、等 200 秒也照旧不兜底
--   S1 权限：gauntlet_planner_mark 客户端两个角色都调不了、service_role 能调；心跳表客户端读不到
--   分母：本脚本建出的任务恰好 4 条（E2 / E6 / E8 兜底 3 + E7 配对 1）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'h7', 'b7', 'h8', 'b9']);
create temp table _r (k text primary key, r jsonb);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
grant all on _r to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.keep(p_k text, p_r jsonb) returns jsonb language sql as $$
  insert into _r (k, r) values (p_k, p_r) on conflict (k) do update set r = excluded.r returning r
$$;
create or replace function pg_temp.r(p_k text) returns jsonb language sql as $$ select r from _r where k = p_k $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.set_fake(wd int, h int, m int default 0) returns void language plpgsql as $$
declare wk timestamptz := date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (wk + make_interval(days => wd - 1, hours => h, mins => m)) - now()))::bigint where id = 1;
end $$;
create or replace function pg_temp.fake_week() returns bigint language sql as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
create or replace function pg_temp.snap(p_name text) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name, 'tag', 'chk-' || p_name),
    'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')))
$$;
create or replace function pg_temp.qj(p_k text) returns jsonb language plpgsql as $$
declare w int[];
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  w := public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u(p_k));
  return public.gauntlet_queue_join(pg_temp.fake_week(), pg_temp.snap(p_k), w[1] + w[2], '9.9.9', 99);
end $$;
create or replace function pg_temp.qp(p_k text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  return public.gauntlet_queue_poll(pg_temp.fake_week());
end $$;
-- 把 p_k 那条 waiting 的进队时刻往前拨 p_sec 秒（心跳仍新鲜）
create or replace function pg_temp.age(p_k text, p_sec int) returns void language sql as $$
  update public.gauntlet_queue set joined_at = now() - make_interval(secs => p_sec), last_seen = now()
   where account_id = pg_temp.u(p_k) and status = 'waiting'
$$;
create or replace function pg_temp.jobof(p_r jsonb) returns public.referee_jobs language sql as $$
  select * from public.referee_jobs where job_id = (p_r->>'job_id')::bigint
$$;
create or replace function pg_temp.sides(p_r jsonb) returns uuid[] language sql as $$
  select array[(pg_temp.jobof(p_r)).a_account, (pg_temp.jobof(p_r)).b_account]
$$;
create or replace function pg_temp.nb(p_k text) returns timestamptz language sql as $$
  select no_bot_at from public.gauntlet_queue where account_id = pg_temp.u(p_k) and status = 'waiting'
$$;
-- 调度器那一拍（service_role 调；这里直接调）
create or replace function pg_temp.mark(p_ks text[]) returns jsonb language sql as $$
  select public.gauntlet_planner_mark(pg_temp.fake_week(), array(select pg_temp.u(k) from unnest(p_ks) k), '9.9.9')
$$;
create or replace function pg_temp.njobs() returns bigint language sql as $$
  select count(*) from public.referee_jobs where season_week = pg_temp.fake_week() and kind = 'gauntlet'
     and a_account in (select id from _u)
$$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 99)
  on conflict (client_version) do update set enabled = true, rules_ver = 99;
insert into public.bot_accounts (account_id) select id from _u where k like 'b%';
delete from public.gauntlet_planner_beat;
select pg_temp.set_fake(6, 12);
-- 格子：h1 1-0 / h2 2-0 / h3 0-1 / h4 2-1 / h5 0-2 / h6 1-2 / h7 + b7 3-1 / h8 1-1 / b9 3-0
insert into public.gauntlet_records (season_week, account_id, gw, gl)
  select pg_temp.fake_week(), pg_temp.u(k), gw, gl
    from (values ('h1', 1, 0), ('h2', 2, 0), ('h3', 0, 1), ('h4', 2, 1), ('h5', 0, 2), ('h6', 1, 2),
                 ('h7', 3, 1), ('b7', 3, 1), ('h8', 1, 1), ('b9', 3, 0)) v(k, gw, gl);
-- 兜底要用的机器人池（场次 = 胜 + 负）：E2 2-0 / E6 1-2 / E8 1-1
insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
  values (99, 2, 2, 0, 99, pg_temp.snap('池子20'), '9.9.9'), (99, 3, 1, 2, 99, pg_temp.snap('池子12'), '9.9.9'),
         (99, 2, 1, 1, 99, pg_temp.snap('池子11'), '9.9.9')
  on conflict (rules_ver, battles, gw, gl, variant) do nothing;

select pg_temp.ck('E0 新件在位: gauntlet_planner_stale_sec() = 60、gauntlet_queue.no_bot_at 列在',
  public.gauntlet_planner_stale_sec() = 60
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'gauntlet_queue'
               and column_name = 'no_bot_at'), public.gauntlet_planner_stale_sec()::text);

-- E1 调度器从没报过到
select pg_temp.keep('h1', pg_temp.qj('h1'));
select pg_temp.age('h1', 61);
select pg_temp.keep('h1b', pg_temp.qp('h1'));
select pg_temp.ck('E1 调度器从没报过到: 真人独自等 61 秒 ⇒ 照旧等', pg_temp.r('h1b')->>'status' = 'waiting'
  and not public.gauntlet_planner_gone(), pg_temp.r('h1b')::text);

-- 这一拍报 h2 / h3 / h4 / h7 / b7 没号（b7 是陪练号 ⇒ 不置）
select pg_temp.keep('h2', pg_temp.qj('h2'));
select pg_temp.keep('h3', pg_temp.qj('h3'));
select pg_temp.keep('h4', pg_temp.qj('h4'));
select pg_temp.keep('b7', pg_temp.qj('b7'));
select pg_temp.age('b7', 120);
select pg_temp.keep('h7', pg_temp.qj('h7'));
select pg_temp.keep('b9', pg_temp.qj('b9'));
select pg_temp.keep('m1', pg_temp.mark(array['h2', 'h3', 'h4', 'h7', 'b7', 'b9']));
select pg_temp.ck('E9 陪练号: 名单里有它也不置 no_bot_at（b7 / b9）; 真人置上 4 条',
  pg_temp.nb('b9') is null and (pg_temp.r('m1')->>'set')::int = 4 and pg_temp.nb('h2') is not null, pg_temp.r('m1')::text);

-- E2
select pg_temp.age('h2', 61);
select pg_temp.keep('h2b', pg_temp.qp('h2'));
select pg_temp.ck('E2 被报成没号、等 61 秒 ⇒ 当场兜底（meta.early = no_bot）',
  pg_temp.r('h2b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h2b'))).meta->>'fallback' = 'true'
  and (pg_temp.jobof(pg_temp.r('h2b'))).meta->>'early' = 'no_bot', pg_temp.r('h2b')::text);

-- E3
select pg_temp.age('h3', 59);
select pg_temp.keep('h3b', pg_temp.qp('h3'));
select pg_temp.ck('E3 被报成没号但只等了 59 秒 ⇒ 仍等', pg_temp.r('h3b')->>'status' = 'waiting', pg_temp.r('h3b')::text);

-- E7 被报成没号、但同格子有陪练号在等 ⇒ 配上陪练号
select pg_temp.age('h7', 61);
select pg_temp.age('b7', 180);
select pg_temp.keep('h7b', pg_temp.qp('h7'));
select pg_temp.ck('E7 被报成没号、同格子正好有陪练号在等 ⇒ 配上陪练号（配对局，不是兜底）',
  pg_temp.r('h7b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h7b'))).meta->>'pair' = 'true'
  and pg_temp.sides(pg_temp.r('h7b')) @> array[pg_temp.u('h7'), pg_temp.u('b7')], pg_temp.r('h7b')::text);

-- E4 下一拍名单里只剩 h3 ⇒ h4 清掉
select pg_temp.keep('m2', pg_temp.mark(array['h3']));
select pg_temp.age('h4', 61);
select pg_temp.keep('h4b', pg_temp.qp('h4'));
select pg_temp.ck('E4 下一拍名单里没有他 ⇒ no_bot_at 清掉、等 61 秒照旧等; h3 还在',
  pg_temp.r('h4b')->>'status' = 'waiting' and pg_temp.nb('h4') is null and pg_temp.nb('h3') is not null,
  pg_temp.r('m2')::text || ' ' || pg_temp.r('h4b')::text);

-- E5 心跳新鲜、没报他
select pg_temp.keep('h5', pg_temp.qj('h5'));
select pg_temp.age('h5', 61);
select pg_temp.keep('h5b', pg_temp.qp('h5'));
select pg_temp.ck('E5 调度器心跳新鲜、没报他: 等 61 秒 ⇒ 照旧等', pg_temp.r('h5b')->>'status' = 'waiting', pg_temp.r('h5b')::text);

-- E6 180 秒兜底不变
select pg_temp.keep('h6', pg_temp.qj('h6'));
select pg_temp.age('h6', 181);
select pg_temp.keep('h6b', pg_temp.qp('h6'));
select pg_temp.ck('E6 照旧的 180 秒兜底不变: 等 181 秒 ⇒ 兜底, meta 里没有 early',
  pg_temp.r('h6b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h6b'))).meta->>'fallback' = 'true'
  and not ((pg_temp.jobof(pg_temp.r('h6b'))).meta ? 'early'), pg_temp.r('h6b')::text);

-- E8 心跳断了 61 秒
update public.gauntlet_planner_beat set seen_at = now() - make_interval(secs => 61);
select pg_temp.keep('h8', pg_temp.qj('h8'));
select pg_temp.age('h8', 61);
select pg_temp.keep('h8b', pg_temp.qp('h8'));
select pg_temp.ck('E8 调度器报过到、心跳断了 61 秒: 没被报的真人等 61 秒 ⇒ 兜底（meta.early = planner_gone）',
  public.gauntlet_planner_gone() and pg_temp.r('h8b')->>'status' = 'paired'
  and (pg_temp.jobof(pg_temp.r('h8b'))).meta->>'early' = 'planner_gone', pg_temp.r('h8b')::text);

-- E9 陪练号心跳断了、等 200 秒也不兜底
select pg_temp.age('b9', 200);
select pg_temp.keep('b9b', pg_temp.qp('b9'));
select pg_temp.ck('E9 陪练号: 调度器心跳断了、等 200 秒 ⇒ 照旧不兜底', pg_temp.r('b9b')->>'status' = 'waiting', pg_temp.r('b9b')::text);

select pg_temp.as_user(null);
select pg_temp.ck('S1 权限: gauntlet_planner_mark 客户端两个角色都调不了、service_role 能调; 心跳表客户端读不到',
  not has_function_privilege('authenticated', 'public.gauntlet_planner_mark(bigint, uuid[], text)', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_planner_mark(bigint, uuid[], text)', 'execute')
  and has_function_privilege('service_role', 'public.gauntlet_planner_mark(bigint, uuid[], text)', 'execute')
  and not has_table_privilege('authenticated', 'public.gauntlet_planner_beat', 'select')
  and not has_table_privilege('anon', 'public.gauntlet_planner_beat', 'select')
  and not has_function_privilege('authenticated', 'public.gauntlet_planner_gone()', 'execute'));
select pg_temp.ck('分母: 本脚本建出的任务恰好 4 条（E2 / E6 / E8 兜底 3 + E7 配对 1）', pg_temp.njobs() = 4, pg_temp.njobs()::text);

-- ★红的那几条排在最前面（每条截 600 字）：Management API 回的报错只有约 3600 字
do $$
declare nf int; nt int; msg text; fmsg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  select string_agg(left(format('[FAIL] %s %s', name, info), 600), E'\n' order by n) into fmsg from _chk where not pass;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || fmsg || E'\n──── 全部 ────\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
