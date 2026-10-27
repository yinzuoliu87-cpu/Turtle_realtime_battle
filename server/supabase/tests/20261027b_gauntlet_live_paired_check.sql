-- 20261027b 赛况板直播签标配对局的 B + 收盘前 11 分钟当场兜底 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261027b_gauntlet_live_paired
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
-- 假时间照 20261026b / 20261027 检查脚本（本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原）。
-- 判据：
--   L0 分母：本脚本造的 4 局里，正在算的 3 局都在直播列表里；还没领走的 / 租期过了的不在
--   L1 配对局（meta.pair）⇒ paired = true；rp 是 B 自己锁定的那份 profile（#ID / 名字），lp 是 A 的
--   L2 旧路真人快照局（b_account = 被打的快照主人，不在场）⇒ paired = false
--   L3 机器人池局（b_account 空）⇒ paired = false
--   L4 列表里每一行（含内测服 / 正式服上别人的行）都有 paired 且是布尔
--   L5 除 paired 之外与改前（20261021 版，函数体原样抄成 pg_temp 函数）逐字相同（按 match_id 一行一行比、行数相同）
--   L6 没登录 ⇒ []；权限：authenticated 能调、anon 不能
--   C  收盘前 11 分钟当场兜底（假周日；收盘 17:30，11 分钟线 = 17:19）：
--      C1 17:20 真人进队、同格子没人 ⇒ 当场兜底（机器人池局，b_account 空）；C2 17:18 进队 ⇒ 照常等；
--      C3 17:18 进队等着的真人 + 17:20 同格子再来一个 ⇒ 两人配对（不兜底）；C4 17:20 陪练号 ⇒ 照常等（陪练号不兜底）；
--      C5 边界 17:19 整 ⇒ 当场兜底；C6 17:18 进队的人 17:20 poll ⇒ 当场兜底；C7 17:18 等满 91 秒 ⇒ 照常 90 秒兜底；
--      分母：本组建出的任务恰好 5 条（4 条兜底 + 1 条配对）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['a1', 'b1', 'a2', 'b2', 'a3', 'a4', 'b4', 'a5', 'v',
                                       'c1', 'c2', 'c3', 'c4', 'c5', 'c7', 'cb']);
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
-- 造一局：A / B（可空）/ meta / 状态 / 领走多久了。
--   ★建任务时刻（created_at）故意比领走时刻早 5 分钟：两个时刻相同的话，L5 看不出「把哪一列当开打时刻」被换了。
create or replace function pg_temp.job(p_key text, p_a text, p_b text, p_bsnap text, p_meta jsonb, p_status text,
    p_claimed_ago interval default interval '0 seconds') returns uuid language plpgsql as $$
declare mid uuid;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account,
      a_snapshot, b_snapshot, meta, status, claimed_by, claimed_at, attempts, created_at)
    values ('gauntlet', 'chk20261027b:' || p_key || ':' || pg_temp.u('v'), pg_temp.fake_week(), '9.9.9', 4243,
            pg_temp.u(p_a), pg_temp.u(p_b), pg_temp.snap(p_a), pg_temp.snap(p_bsnap), p_meta, p_status,
            case when p_status = 'claimed' then 'chk-worker' end,
            case when p_status = 'claimed' then now() - p_claimed_ago end, 1,
            now() - p_claimed_ago - interval '5 minutes')
    returning match_id into mid;
  return mid;
end $$;

-- referee_live_gauntlet 改前 = 20261021 版（schema.sql 里本段之前最后一份），由生成脚本逐字抄入：
create or replace function pg_temp.live_old() returns jsonb language plpgsql stable as $old$
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
end $old$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
select pg_temp.set_fake(6, 12);

create temp table _m (k text primary key, mid uuid);
grant all on _m to public;
insert into _m values
  ('pair', pg_temp.job('pair', 'a1', 'b1', 'b1', jsonb_build_object('pair', true, 'opp', pg_temp.u('b1')::text, 'pick', 'pair'), 'claimed')),
  ('old', pg_temp.job('old', 'a2', 'b2', 'b2', jsonb_build_object('opp', pg_temp.u('b2')::text, 'pick', 'fresh'), 'claimed')),
  ('bot', pg_temp.job('bot', 'a3', null, '池子', jsonb_build_object('opp', 'bot:1:0:0:0:1', 'pick', 'bot'), 'claimed')),
  ('pend', pg_temp.job('pend', 'a4', 'b4', 'b4', jsonb_build_object('pair', true), 'pending')),
  ('stale', pg_temp.job('stale', 'a5', null, '池子', '{}'::jsonb, 'claimed', interval '3 hours'));
create or replace function pg_temp.mid(p_k text) returns uuid language sql as $$ select mid from _m where k = p_k $$;

select pg_temp.as_user(pg_temp.u('v'));
select pg_temp.keep('new', public.referee_live_gauntlet());
select pg_temp.keep('old', pg_temp.live_old());
create or replace function pg_temp.row_of(p_which text, p_k text) returns jsonb language sql as $$
  select e from jsonb_array_elements(pg_temp.r(p_which)) e where e->>'match_id' = pg_temp.mid(p_k)::text
$$;

select pg_temp.ck('L0 分母: 正在算的 3 局（配对 / 旧路快照 / 机器人池）都在列表里',
  pg_temp.row_of('new', 'pair') is not null and pg_temp.row_of('new', 'old') is not null and pg_temp.row_of('new', 'bot') is not null,
  format('列表 %s 行', jsonb_array_length(pg_temp.r('new'))));
select pg_temp.ck('L0 对照: 还没领走的 / 租期过了的不在', pg_temp.row_of('new', 'pend') is null and pg_temp.row_of('new', 'stale') is null);
select pg_temp.ck('L1 配对局 ⇒ paired = true；rp 是 B（b1）自己的 #ID / 名字，lp 是 A（a1）',
  pg_temp.row_of('new', 'pair')->'paired' = 'true'::jsonb
  and pg_temp.row_of('new', 'pair')->'rp'->>'tag' = 'chk-b1' and pg_temp.row_of('new', 'pair')->'rp'->>'name' = 'b1'
  and pg_temp.row_of('new', 'pair')->'rp'->>'id' = 'g_b1' and pg_temp.row_of('new', 'pair')->'lp'->>'tag' = 'chk-a1',
  pg_temp.row_of('new', 'pair')::text);
select pg_temp.ck('L2 旧路真人快照局（b_account 有值、不在场）⇒ paired = false',
  pg_temp.row_of('new', 'old')->'paired' = 'false'::jsonb, pg_temp.row_of('new', 'old')::text);
select pg_temp.ck('L3 机器人池局（b_account 空）⇒ paired = false',
  pg_temp.row_of('new', 'bot')->'paired' = 'false'::jsonb, pg_temp.row_of('new', 'bot')::text);
select pg_temp.ck('L4 每一行都有 paired 且是布尔（含别人的行）',
  (select bool_and(jsonb_typeof(e->'paired') = 'boolean') and count(*) >= 3 from jsonb_array_elements(pg_temp.r('new')) e),
  format('%s 行', jsonb_array_length(pg_temp.r('new'))));
select pg_temp.ck('L5 除 paired 之外与改前逐字相同（按 match_id 一行一行比、行数相同）',
  jsonb_array_length(pg_temp.r('new')) = jsonb_array_length(pg_temp.r('old'))
  and not exists (select 1 from jsonb_array_elements(pg_temp.r('new')) n
                   where (n - 'paired') is distinct from
                         (select o from jsonb_array_elements(pg_temp.r('old')) o where o->>'match_id' = n->>'match_id')),
  format('新 %s 行 / 旧 %s 行', jsonb_array_length(pg_temp.r('new')), jsonb_array_length(pg_temp.r('old'))));
select pg_temp.ck('L5 分母: 改前那一份里也有这 3 局（比的不是空对空）',
  (select count(*) from jsonb_array_elements(pg_temp.r('old')) o
    where o->>'match_id' in (pg_temp.mid('pair')::text, pg_temp.mid('old')::text, pg_temp.mid('bot')::text)) = 3);
select pg_temp.as_user(null);
select pg_temp.ck('L6 没登录 ⇒ []', public.referee_live_gauntlet() = '[]'::jsonb);
select pg_temp.ck('L6 权限: authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.referee_live_gauntlet()', 'execute')
  and not has_function_privilege('anon', 'public.referee_live_gauntlet()', 'execute'));

-- ── C 收盘前 11 分钟当场兜底 ──
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 1)
  on conflict (client_version) do update set enabled = true, rules_ver = 1;
insert into public.bot_accounts (account_id) values (pg_temp.u('cb'));
-- 账本格子（场次 = gw + gl ⇒ 机器人池的场次格 = gw + gl）；每个格子池子里都放一份，证明「没兜底」不是因为池子空
insert into public.gauntlet_records (season_week, account_id, gw, gl)
  select pg_temp.fake_week(), pg_temp.u(k), gw, gl
    from (values ('c1', 0, 0), ('c2', 1, 0), ('c3', 0, 1), ('c4', 0, 1), ('c5', 2, 0), ('c7', 2, 1), ('cb', 1, 1)) v(k, gw, gl);
insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
  select 1, gw + gl, gw, gl, 99, pg_temp.snap('池子'), '9.9.9'
    from (values (0, 0), (1, 0), (0, 1), (2, 0), (2, 1), (1, 1)) v(gw, gl)
  on conflict (rules_ver, battles, gw, gl, variant) do nothing;
create or replace function pg_temp.qj(p_k text) returns jsonb language plpgsql as $$
declare w int[];
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  w := public.gauntlet_wl(pg_temp.fake_week(), pg_temp.u(p_k));
  return public.gauntlet_queue_join(pg_temp.fake_week(), pg_temp.snap(p_k), w[1] + w[2], '9.9.9', 1);
end $$;
create or replace function pg_temp.qp(p_k text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  return public.gauntlet_queue_poll(pg_temp.fake_week());
end $$;
create or replace function pg_temp.jobof(p_r jsonb) returns public.referee_jobs language sql as $$
  select * from public.referee_jobs where job_id = (p_r->>'job_id')::bigint
$$;
create or replace function pg_temp.cjobs() returns bigint language sql as $$
  select count(*) from public.referee_jobs where season_week = pg_temp.fake_week() and kind = 'gauntlet'
     and (a_account in (select id from _u where k like 'c%') or b_account in (select id from _u where k like 'c%'))
$$;

select pg_temp.set_fake(7, 17, 18);
select pg_temp.keep('c2', pg_temp.qj('c2'));
select pg_temp.keep('c3', pg_temp.qj('c3'));
select pg_temp.keep('c7a', pg_temp.qj('c7'));
update public.gauntlet_queue set joined_at = now() - interval '91 seconds'
 where account_id = pg_temp.u('c7') and status = 'waiting';
select pg_temp.keep('c7', pg_temp.qp('c7'));
select pg_temp.ck('C2 周日 17:18（离收盘 12 分钟）进队 ⇒ 照常等（池子里有货也不兜底）',
  pg_temp.r('c2')->>'status' = 'waiting' and pg_temp.r('c3')->>'status' = 'waiting', pg_temp.r('c2')::text);
select pg_temp.ck('C7 17:18 等满 91 秒 ⇒ 照常 90 秒兜底',
  pg_temp.r('c7a')->>'status' = 'waiting' and pg_temp.r('c7')->>'status' = 'paired'
  and (pg_temp.jobof(pg_temp.r('c7'))).meta->>'fallback' = 'true', pg_temp.r('c7')::text);

select pg_temp.set_fake(7, 17, 19);
select pg_temp.keep('c5', pg_temp.qj('c5'));
select pg_temp.ck('C5 边界: 17:19 整（离收盘正好 11 分钟）进队 ⇒ 当场兜底',
  pg_temp.r('c5')->>'status' = 'paired' and (pg_temp.r('c5')->>'waited_sec')::int = 0
  and (pg_temp.jobof(pg_temp.r('c5'))).meta->>'fallback' = 'true', pg_temp.r('c5')::text);

select pg_temp.set_fake(7, 17, 20);
select pg_temp.keep('c1', pg_temp.qj('c1'));
select pg_temp.keep('c4', pg_temp.qj('c4'));
select pg_temp.keep('cb', pg_temp.qj('cb'));
select pg_temp.keep('c2b', pg_temp.qp('c2'));
select pg_temp.ck('C1 17:20 真人进队、同格子没人 ⇒ 当场兜底（paired / side a / 机器人池局 b_account 空、不是配对局）',
  pg_temp.r('c1')->>'status' = 'paired' and pg_temp.r('c1')->>'side' = 'a' and (pg_temp.r('c1')->>'waited_sec')::int = 0
  and (pg_temp.jobof(pg_temp.r('c1'))).b_account is null and (pg_temp.jobof(pg_temp.r('c1'))).meta->>'fallback' = 'true'
  and not ((pg_temp.jobof(pg_temp.r('c1'))).meta ? 'pair') and (pg_temp.jobof(pg_temp.r('c1'))).meta->>'opp' like 'bot:1:0:0:0:%',
  pg_temp.r('c1')::text);
select pg_temp.ck('C3 17:20 同格子有 17:18 起在等的真人 ⇒ 先配人（配对局 A = c3 / B = c4），不兜底',
  pg_temp.r('c4')->>'status' = 'paired' and pg_temp.r('c4')->>'side' = 'b'
  and (pg_temp.jobof(pg_temp.r('c4'))).meta->>'pair' = 'true' and (pg_temp.jobof(pg_temp.r('c4'))).a_account = pg_temp.u('c3')
  and not ((pg_temp.jobof(pg_temp.r('c4'))).meta ? 'fallback'), pg_temp.r('c4')::text);
select pg_temp.ck('C4 17:20 陪练号进队 ⇒ 照常等（陪练号不兜底）', pg_temp.r('cb')->>'status' = 'waiting', pg_temp.r('cb')::text);
select pg_temp.ck('C6 17:18 进队的 c2 到 17:20 poll ⇒ 当场兜底',
  pg_temp.r('c2b')->>'status' = 'paired' and (pg_temp.jobof(pg_temp.r('c2b'))).meta->>'fallback' = 'true'
  and (pg_temp.jobof(pg_temp.r('c2b'))).a_account = pg_temp.u('c2'), pg_temp.r('c2b')::text);
select pg_temp.ck('C 分母: 本组建出的任务恰好 5 条（c7 / c5 / c1 / c2 兜底 4 + c3-c4 配对 1）', pg_temp.cjobs() = 5,
  pg_temp.cjobs()::text);

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
