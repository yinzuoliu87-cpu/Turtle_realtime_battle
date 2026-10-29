-- 20261029b 闯关赛兜底「先真人快照、再机器人池」+ 等 3 分钟 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261029b_gauntlet_fallback_real_first
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
-- 假时间照 20261027b 检查脚本（本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原）。
-- 全部用 rules_ver = 99 / 版本 9.9.9：与库里真实的闯关快照、机器人池（rules_ver 1）不相交 ⇒ 挑到谁完全由本脚本造的数据决定。
-- 判据（假周六 12:00；每个真人各占一个格子）：
--   F0 gauntlet_queue_fallback_sec() = 180
--   F1 等 179 秒 ⇒ 照常等（同格子有真人快照也不提前兜底）
--   F2 等 181 秒 ⇒ 兜底挑真人快照：同格子有「自己的快照（新）/ 陪练号快照（新）/ 真人快照（旧）」⇒ 挑真人（旧）那份；
--      b_account = 快照主人、meta.fallback、pick = stale、opp = 主人、不带 pair；b_snapshot = 那份快照（去掉 origin）
--   F3 同格子只有陪练号快照 ⇒ 挑陪练号那份（pick = fresh）
--   F4 同格子两份真人快照（2 小时前 / 5 分钟前）⇒ 挑 5 分钟前那份（pick = fresh）
--   F5 同格子没有快照 ⇒ 机器人池（b_account 空、opp = bot:99:…、pick = bot）
--   F6 同格子唯一一份真人快照的主人本周和我交过手 ⇒ 不挑他，退机器人池
--   F7 同格子只有别的 rules_ver 的快照 ⇒ 不挑，退机器人池
--   F8 陪练号等 200 秒 ⇒ 照常等（陪练号不兜底）
--   F9 收盘前 11 分钟当场兜底照旧（假周日 17:20 进队）且也先挑真人快照
--   F10 只记真人一边：真人快照局对快照主人不算「在算」（gauntlet_in_job = false）
--   S1 权限：两个函数 anon / authenticated 都调不了
--   分母：本脚本建出的兜底任务恰好 7 条（F2 ~ F7 + F9）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'h7', 'cb',
                                       'g1', 'b1', 'b3', 'g4o', 'g4n', 'g6', 'g7', 'g9']);
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
create or replace function pg_temp.ghost(p_k text, gw int, gl int, p_ago interval, p_rv int default 99) returns void language sql as $$
  insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver, uploaded_at)
    values (pg_temp.u(p_k), pg_temp.fake_week(), gw, gl, pg_temp.snap(p_k) || jsonb_build_object('origin', 'chk'), '9.9.9', p_rv,
            now() - p_ago)
$$;
create or replace function pg_temp.fbjobs() returns bigint language sql as $$
  select count(*) from public.referee_jobs where season_week = pg_temp.fake_week() and kind = 'gauntlet'
     and meta->>'fallback' = 'true' and a_account in (select id from _u)
$$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 99)
  on conflict (client_version) do update set enabled = true, rules_ver = 99;
insert into public.bot_accounts (account_id) values (pg_temp.u('cb')), (pg_temp.u('b1')), (pg_temp.u('b3'));
select pg_temp.set_fake(6, 12);

-- 账本格子：h1 1-0 / h2 2-0 / h3 0-1 / h4 2-1 / h5 1-1 / h6 3-0 / h7 0-2 / cb 3-1
insert into public.gauntlet_records (season_week, account_id, gw, gl)
  select pg_temp.fake_week(), pg_temp.u(k), gw, gl
    from (values ('h1', 1, 0), ('h2', 2, 0), ('h3', 0, 1), ('h4', 2, 1), ('h5', 1, 1), ('h6', 3, 0), ('h7', 0, 2), ('cb', 3, 1)) v(k, gw, gl);
-- 机器人池：每个格子都放一份（证明挑到真人快照不是因为池子空）
insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
  select 99, gw + gl, gw, gl, 99, pg_temp.snap('池子'), '9.9.9'
    from (values (1, 0), (2, 0), (0, 1), (2, 1), (1, 1), (3, 0), (0, 2), (3, 1)) v(gw, gl)
  on conflict (rules_ver, battles, gw, gl, variant) do nothing;
-- 快照
select pg_temp.ghost('h1', 1, 0, interval '1 minute');      -- 自己（新）⇒ 不许挑自己
select pg_temp.ghost('b1', 1, 0, interval '2 minutes');     -- 陪练号（新）
select pg_temp.ghost('g1', 1, 0, interval '2 hours');       -- 真人（旧）⇒ F2 应挑它
select pg_temp.ghost('b3', 2, 0, interval '3 minutes');     -- h2 那格只有陪练号
select pg_temp.ghost('g4o', 3, 0, interval '2 hours');      -- h6 那格：真人旧
select pg_temp.ghost('g4n', 3, 0, interval '5 minutes');    -- h6 那格：真人新 ⇒ F4 应挑它
select pg_temp.ghost('g6', 2, 1, interval '4 minutes');     -- h4 那格：唯一真人快照, 但本周交过手
select pg_temp.ghost('g7', 1, 1, interval '4 minutes', 98); -- h5 那格：只有别的 rules_ver
select pg_temp.ghost('g9', 0, 2, interval '6 minutes');     -- h7 那格（F9）
-- h4 本周打过 g6（一条算完的旧路任务, meta.opp = g6）
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta, status)
  values ('gauntlet', 'chk20261029b:faced:' || pg_temp.u('h4'), pg_temp.fake_week(), '9.9.9', 4249, pg_temp.u('h4'), pg_temp.u('g6'),
          pg_temp.snap('h4'), pg_temp.snap('g6'), jsonb_build_object('opp', pg_temp.u('g6')::text, 'pick', 'fresh'), 'done');

select pg_temp.ck('F0 兜底线 = 180 秒', public.gauntlet_queue_fallback_sec() = 180, public.gauntlet_queue_fallback_sec()::text);

-- F1 / F2
select pg_temp.keep('h1j', pg_temp.qj('h1'));
select pg_temp.age('h1', 179);
select pg_temp.keep('h1a', pg_temp.qp('h1'));
select pg_temp.ck('F1 等 179 秒 ⇒ 照常等（同格子有真人快照也不提前兜底）',
  pg_temp.r('h1j')->>'ok' = 'true' and pg_temp.r('h1a')->>'status' = 'waiting', pg_temp.r('h1a')::text);
select pg_temp.age('h1', 181);
select pg_temp.keep('h1b', pg_temp.qp('h1'));
select pg_temp.ck('F2 等 181 秒 ⇒ 兜底挑真人快照（不挑自己、真人先于陪练号）：b_account = 主人 / fallback / pick stale / 不带 pair',
  pg_temp.r('h1b')->>'status' = 'paired' and pg_temp.r('h1b')->>'side' = 'a'
  and (pg_temp.jobof(pg_temp.r('h1b'))).b_account = pg_temp.u('g1')
  and (pg_temp.jobof(pg_temp.r('h1b'))).meta->>'opp' = pg_temp.u('g1')::text
  and (pg_temp.jobof(pg_temp.r('h1b'))).meta->>'fallback' = 'true'
  and (pg_temp.jobof(pg_temp.r('h1b'))).meta->>'pick' = 'stale'
  and not ((pg_temp.jobof(pg_temp.r('h1b'))).meta ? 'pair'), pg_temp.r('h1b')::text);
select pg_temp.ck('F2 b_snapshot = 那份快照（去掉 origin）、对手卡是 g1',
  (pg_temp.jobof(pg_temp.r('h1b'))).b_snapshot = pg_temp.snap('g1')
  and pg_temp.r('h1b')->'opp'->'profile'->>'name' = 'g1', (pg_temp.jobof(pg_temp.r('h1b'))).b_snapshot::text);

-- F3 只有陪练号快照
select pg_temp.keep('h2j', pg_temp.qj('h2'));
select pg_temp.age('h2', 181);
select pg_temp.keep('h2b', pg_temp.qp('h2'));
select pg_temp.ck('F3 同格子只有陪练号快照 ⇒ 挑它（pick fresh、b_account = 陪练号）',
  pg_temp.r('h2b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h2b'))).b_account = pg_temp.u('b3')
  and (pg_temp.jobof(pg_temp.r('h2b'))).meta->>'pick' = 'fresh', pg_temp.r('h2b')::text);

-- F4 两份真人：新的先
select pg_temp.keep('h6j', pg_temp.qj('h6'));
select pg_temp.age('h6', 181);
select pg_temp.keep('h6b', pg_temp.qp('h6'));
select pg_temp.ck('F4 两份真人快照 ⇒ 挑 30 分钟内那份（g4n、pick fresh）',
  pg_temp.r('h6b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h6b'))).b_account = pg_temp.u('g4n')
  and (pg_temp.jobof(pg_temp.r('h6b'))).meta->>'pick' = 'fresh', pg_temp.r('h6b')::text);

-- F5 没有快照 ⇒ 机器人池
select pg_temp.keep('h3j', pg_temp.qj('h3'));
select pg_temp.age('h3', 181);
select pg_temp.keep('h3b', pg_temp.qp('h3'));
select pg_temp.ck('F5 同格子没有快照 ⇒ 机器人池（b_account 空、opp = bot:99:…、pick bot）',
  pg_temp.r('h3b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h3b'))).b_account is null
  and (pg_temp.jobof(pg_temp.r('h3b'))).meta->>'opp' like 'bot:99:%'
  and (pg_temp.jobof(pg_temp.r('h3b'))).meta->>'pick' = 'bot', pg_temp.r('h3b')::text);

-- F6 交过手的不挑
select pg_temp.keep('h4j', pg_temp.qj('h4'));
select pg_temp.age('h4', 181);
select pg_temp.keep('h4b', pg_temp.qp('h4'));
select pg_temp.ck('F6 唯一真人快照的主人本周交过手 ⇒ 不挑他、退机器人池',
  pg_temp.r('h4b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h4b'))).b_account is null
  and (pg_temp.jobof(pg_temp.r('h4b'))).meta->>'pick' = 'bot', pg_temp.r('h4b')::text);

-- F7 别的 rules_ver 不挑
select pg_temp.keep('h5j', pg_temp.qj('h5'));
select pg_temp.age('h5', 181);
select pg_temp.keep('h5b', pg_temp.qp('h5'));
select pg_temp.ck('F7 同格子只有别的 rules_ver 的快照 ⇒ 不挑、退机器人池',
  pg_temp.r('h5b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('h5b'))).b_account is null
  and (pg_temp.jobof(pg_temp.r('h5b'))).meta->>'pick' = 'bot', pg_temp.r('h5b')::text);

-- F8 陪练号不兜底
select pg_temp.keep('cbj', pg_temp.qj('cb'));
select pg_temp.age('cb', 200);
select pg_temp.keep('cbb', pg_temp.qp('cb'));
select pg_temp.ck('F8 陪练号等 200 秒 ⇒ 照常等（陪练号不兜底）', pg_temp.r('cbb')->>'status' = 'waiting', pg_temp.r('cbb')::text);

-- F10 只记真人一边
select pg_temp.ck('F10 真人快照局对快照主人不算「在算」（只记真人一边）',
  not public.gauntlet_in_job(pg_temp.fake_week(), pg_temp.u('g1')) and not public.gauntlet_in_job(pg_temp.fake_week(), pg_temp.u('g4n')));

-- F9 收盘前 11 分钟当场兜底照旧, 也先挑真人
select pg_temp.set_fake(7, 17, 20);
select pg_temp.keep('h7b', pg_temp.qj('h7'));
select pg_temp.ck('F9 周日 17:20 进队 ⇒ 当场兜底（不等 180 秒）且挑真人快照 g9',
  pg_temp.r('h7b')->>'status' = 'paired' and (pg_temp.r('h7b')->>'waited_sec')::int = 0
  and (pg_temp.jobof(pg_temp.r('h7b'))).b_account = pg_temp.u('g9')
  and (pg_temp.jobof(pg_temp.r('h7b'))).meta->>'fallback' = 'true', pg_temp.r('h7b')::text);

select pg_temp.as_user(null);
select pg_temp.ck('S1 权限: gauntlet_queue_advance / gauntlet_queue_fallback_sec 客户端两个角色都调不了',
  not has_function_privilege('authenticated', 'public.gauntlet_queue_advance(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_advance(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.gauntlet_queue_fallback_sec()', 'execute')
  and not has_function_privilege('anon', 'public.gauntlet_queue_fallback_sec()', 'execute'));
select pg_temp.ck('分母: 本脚本建出的兜底任务恰好 7 条（F2 ~ F7 + F9）', pg_temp.fbjobs() = 7, pg_temp.fbjobs()::text);

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
