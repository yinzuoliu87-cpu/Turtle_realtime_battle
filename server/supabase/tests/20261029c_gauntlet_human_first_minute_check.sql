-- 20261029c 闯关赛在线排队：真人进队前 1 分钟只配在线真人 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261029c_gauntlet_human_first_minute
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
-- 假时间照 20261029b 检查脚本；全部用 rules_ver = 99 / 版本 9.9.9（与库里真实排队、快照、机器人池不相交）。
-- 判据（假周六 12:00；每组各占一个格子）：
--   H0 gauntlet_queue_human_only_sec() = 60
--   H1 格子里有陪练号在等，真人刚进队 ⇒ 不配（照常等）；H2 真人等 59 秒 poll ⇒ 仍等；H3 等 61 秒 poll ⇒ 配上那个陪练号（配对局）
--   H4 真人在等 30 秒，陪练号进队 ⇒ 陪练号也不配他（照常等）
--   H5 两个真人：第二个进队当场配上第一个（真人 × 真人不受这一分钟限制）
--   H6 格子里有更早的陪练号 + 一个等了 61 秒的真人，新来的陪练号 ⇒ 配真人（真人先于陪练号）
--   H7 陪练号留给真人：格子里有一个刚进队的真人 + 一个陪练号；第 2 个陪练号进队 ⇒ 不互配（照常等）；
--      第 3 个陪练号进队 ⇒ 和最早那个陪练号互配，剩下一个留给真人
--   H8 收盘前 11 分钟起不设这一分钟：假周日 17:20 真人进队，格子里有陪练号 ⇒ 当场配上陪练号（不是兜底）
--   H9 兜底不变：真人独自等 181 秒 ⇒ 兜底（同格子没有快照 ⇒ 机器人池）
--   S1 权限：gauntlet_queue_human_only_sec 客户端两个角色都调不了；gauntlet_queue_advance 同
--   分母：本脚本建出的任务恰好 6 条（H3 / H5 / H6 / H7 / H8 四条配对 + H9 兜底 —— 共 5 条配对 + 1 条兜底）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['h1', 'b1', 'h2', 'b2', 'h3', 'h4', 'b5', 'h5', 'b6',
                                       'h7', 'b7a', 'b7b', 'b7c', 'h8', 'b8', 'h9']);
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
-- 这一局的两边（不分 A / B）
create or replace function pg_temp.sides(p_r jsonb) returns uuid[] language sql as $$
  select array[(pg_temp.jobof(p_r)).a_account, (pg_temp.jobof(p_r)).b_account]
$$;
create or replace function pg_temp.st(p_k text) returns text language sql as $$
  select status from public.gauntlet_queue where account_id = pg_temp.u(p_k) order by id desc limit 1
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
select pg_temp.set_fake(6, 12);
-- 格子：组1 1-0 / 组2 2-0 / 组3 0-1 / 组4 2-1 / 组5 1-1 / 组6 3-0 / 组7 0-2（假周日）/ 组8 3-1
insert into public.gauntlet_records (season_week, account_id, gw, gl)
  select pg_temp.fake_week(), pg_temp.u(k), gw, gl
    from (values ('h1', 1, 0), ('b1', 1, 0), ('h2', 2, 0), ('b2', 2, 0), ('h3', 0, 1), ('h4', 0, 1),
                 ('b5', 2, 1), ('h5', 2, 1), ('b6', 2, 1),
                 ('h7', 1, 1), ('b7a', 1, 1), ('b7b', 1, 1), ('b7c', 1, 1),
                 ('h8', 0, 2), ('b8', 0, 2), ('h9', 3, 1)) v(k, gw, gl);
insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
  values (99, 4, 3, 1, 99, pg_temp.snap('池子'), '9.9.9')
  on conflict (rules_ver, battles, gw, gl, variant) do nothing;

select pg_temp.ck('H0 只配真人的时长 = 60 秒', public.gauntlet_queue_human_only_sec() = 60, public.gauntlet_queue_human_only_sec()::text);

-- H1 ~ H3
select pg_temp.keep('b1', pg_temp.qj('b1'));
select pg_temp.age('b1', 120);
select pg_temp.keep('h1', pg_temp.qj('h1'));
select pg_temp.ck('H1 格子里有陪练号在等，真人刚进队 ⇒ 不配', pg_temp.r('b1')->>'status' = 'waiting' and pg_temp.r('h1')->>'status' = 'waiting',
  pg_temp.r('h1')::text);
select pg_temp.age('h1', 59);
select pg_temp.age('b1', 180);
select pg_temp.keep('h1b', pg_temp.qp('h1'));
select pg_temp.ck('H2 真人等 59 秒 ⇒ 仍等', pg_temp.r('h1b')->>'status' = 'waiting', pg_temp.r('h1b')::text);
select pg_temp.age('h1', 61);
select pg_temp.age('b1', 182);
select pg_temp.keep('h1c', pg_temp.qp('h1'));
select pg_temp.ck('H3 真人等 61 秒 ⇒ 配上那个陪练号（配对局，两边是 h1 / b1）',
  pg_temp.r('h1c')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h1c'))).meta->>'pair' = 'true'
  and pg_temp.sides(pg_temp.r('h1c')) @> array[pg_temp.u('h1'), pg_temp.u('b1')], pg_temp.r('h1c')::text);

-- H4
select pg_temp.keep('h2', pg_temp.qj('h2'));
select pg_temp.age('h2', 30);
select pg_temp.keep('b2', pg_temp.qj('b2'));
select pg_temp.ck('H4 真人等了 30 秒，陪练号进队 ⇒ 陪练号也不配他', pg_temp.r('b2')->>'status' = 'waiting' and pg_temp.st('h2') = 'waiting',
  pg_temp.r('b2')::text);

-- H5
select pg_temp.keep('h3', pg_temp.qj('h3'));
select pg_temp.keep('h4', pg_temp.qj('h4'));
select pg_temp.ck('H5 两个真人：第二个进队当场配上第一个',
  pg_temp.r('h3')->>'status' = 'waiting' and pg_temp.r('h4')->>'status' = 'paired'
  and pg_temp.sides(pg_temp.r('h4')) @> array[pg_temp.u('h3'), pg_temp.u('h4')], pg_temp.r('h4')::text);

-- H6 真人先于陪练号：更早的陪练号 b5 + 等了 61 秒的真人 h5（他自己还没 poll），新来的陪练号 b6 ⇒ 配 h5
select pg_temp.keep('b5', pg_temp.qj('b5'));
select pg_temp.age('b5', 300);
select pg_temp.keep('h5', pg_temp.qj('h5'));
select pg_temp.age('h5', 61);
select pg_temp.keep('b6', pg_temp.qj('b6'));
select pg_temp.ck('H6 更早的陪练号在等、真人等了 61 秒，新来的陪练号 ⇒ 配真人',
  pg_temp.r('h5')->>'status' = 'waiting' and pg_temp.r('b6')->>'status' = 'paired'
  and pg_temp.sides(pg_temp.r('b6')) @> array[pg_temp.u('h5'), pg_temp.u('b6')] and pg_temp.st('b5') = 'waiting',
  pg_temp.r('b6')::text);

-- H7 陪练号留给真人
select pg_temp.keep('b7a', pg_temp.qj('b7a'));
select pg_temp.age('b7a', 200);
select pg_temp.keep('h7', pg_temp.qj('h7'));
select pg_temp.keep('b7b', pg_temp.qj('b7b'));
select pg_temp.ck('H7 刚进队的真人 + 一个陪练号；第 2 个陪练号进队 ⇒ 不互配（留给真人）',
  pg_temp.r('h7')->>'status' = 'waiting' and pg_temp.r('b7b')->>'status' = 'waiting' and pg_temp.st('b7a') = 'waiting',
  pg_temp.r('b7b')::text);
select pg_temp.keep('b7c', pg_temp.qj('b7c'));
select pg_temp.ck('H7 第 3 个陪练号进队 ⇒ 和最早的陪练号互配，剩一个留给真人',
  pg_temp.r('b7c')->>'status' = 'paired' and pg_temp.sides(pg_temp.r('b7c')) @> array[pg_temp.u('b7a'), pg_temp.u('b7c')]
  and pg_temp.st('b7b') = 'waiting' and pg_temp.st('h7') = 'waiting', pg_temp.r('b7c')::text);

-- H9 兜底不变（假周六）
select pg_temp.keep('h9', pg_temp.qj('h9'));
select pg_temp.age('h9', 181);
select pg_temp.keep('h9b', pg_temp.qp('h9'));
select pg_temp.ck('H9 真人独自等 181 秒 ⇒ 兜底（同格子没有快照 ⇒ 机器人池）',
  pg_temp.r('h9b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h9b'))).meta->>'fallback' = 'true'
  and (pg_temp.jobof(pg_temp.r('h9b'))).b_account is null, pg_temp.r('h9b')::text);

-- H8 收盘前 11 分钟起不设这一分钟
select pg_temp.set_fake(7, 17, 20);
select pg_temp.keep('b8', pg_temp.qj('b8'));
select pg_temp.keep('h8', pg_temp.qj('h8'));
select pg_temp.ck('H8 周日 17:20 真人进队、格子里有陪练号 ⇒ 当场配上陪练号（配对局，不是兜底）',
  pg_temp.r('h8')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h8'))).meta->>'pair' = 'true'
  and pg_temp.sides(pg_temp.r('h8')) @> array[pg_temp.u('h8'), pg_temp.u('b8')], pg_temp.r('h8')::text);

select pg_temp.as_user(null);
select pg_temp.ck('S1 权限: gauntlet_queue_human_only_sec / gauntlet_queue_advance 客户端两个角色都调不了',
  not has_function_privilege('authenticated', 'public.gauntlet_queue_human_only_sec()', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_human_only_sec()', 'execute')
  and not has_function_privilege('authenticated', 'public.gauntlet_queue_advance(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_advance(bigint)', 'execute'));
select pg_temp.ck('分母: 本脚本建出的任务恰好 6 条（H3 / H5 / H6 / H7 / H8 配对 5 + H9 兜底 1）', pg_temp.njobs() = 6, pg_temp.njobs()::text);

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
