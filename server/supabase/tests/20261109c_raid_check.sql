-- 20261109c 偷袭任务 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse 20261109c_raid
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
--   ★A1（20261109a）还没合进来时，本脚本开头按契约 §1 的形状补上 mainsite_accounts / mainsite_pets / mainsite_outbox /
--     mainsite_outbox_put（只在它们不存在时建；同一事务里回滚）；A1 上了以后用的就是 A1 的真东西。
-- 假时间照 20261101d 检查脚本（本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原）。
-- 判据：
--   D 防守阵容 raid_defense_put：not_signed_in / wrong_week / bad_snapshot / 没开轮不存（stored:false）；开轮 ⇒ has_defense；
--     已绑定 ⇒ 发件箱 defense {userId, hasDefense, rating = 服务器场数, device}；没变化不重报；设备号变了重报、空串沿用；
--     客户端自带的 owned / account_id 摘掉；没绑定的号存但不报
--   R rating = 积分赛账本 + 闯关账本 + 周日决赛局；周赛局写回（真 referee_complete）⇒ 重报新 rating；报主站出错不拖垮周赛记账
--   C 建任务 raid_create：raid_off（raid_on 关 / econ_on 关）/ bad_raidId / same_user / bad_userId / expired / no_referee；
--     正常 ⇒ 锁定双方本周快照 + 服务器 owned、kind = raid、种子用主站的；★同 raidId 幂等回同一 jobId（只一行、只一个裁判任务）；
--     raid_conflict；没绑定 / 没有本周阵容 / 阵容不合法 ⇒ ok + jobId，但不排裁判、直接 settle void（没有 started）
--   K 领活与结算：偷袭排在闯关后面；领到 ⇒ started（重领不重发）；a 赢 ⇒ attacker、b 赢 ⇒ defender、matchId = 录像 id；
--     ★偷袭局不计场数、不进快照池、不进任何账本、不触发 defense；raid_result 对不上 ⇒ void；拒算 ⇒ void；
--     ★过了 expireAt 还没开算 ⇒ 不领、记 void 不发 settle；开算 30 分钟没结果 ⇒ void，迟到的写回被拒
--   P 周清：偷袭局录像留 30 天（10 天的留着、31 天的删），其余照旧按周删；raid_jobs 31 天的删
--   W 换周：上周报过有阵容的已绑定号 ⇒ hasDefense:false / rating 0；重跑不重报；新的一周没开轮 ⇒ 建任务 void；开轮后报回 true
--   F 权限 / 结构：put 只给 authenticated；建任务 / 报主站只给 service_role；两张表开 RLS 无策略；kind 认 raid；两条 cron 在
-- ─────────────────────────────────────────────────────────────
begin;

-- A1 那几样（契约 §1 原样；已存在就不动）
do $do$ begin
  if to_regclass('public.mainsite_accounts') is null then
    create table public.mainsite_accounts (account_id uuid primary key, mainsite_user_id text unique not null,
      is_bot boolean not null default false, linked_at timestamptz not null default now());
  end if;
  if to_regclass('public.mainsite_pets') is null then
    create table public.mainsite_pets (account_id uuid, pet_key text, fetched_at timestamptz, primary key (account_id, pet_key));
  end if;
  if to_regclass('public.mainsite_outbox') is null then
    create table public.mainsite_outbox (id bigserial primary key, topic text not null, idem_key text not null,
      body jsonb not null, attempts int not null default 0, next_at timestamptz not null default now(),
      done_at timestamptz, last_status text, reply jsonb, unique (topic, idem_key));
  end if;
  if to_regprocedure('public.mainsite_outbox_put(text,text,jsonb)') is null then
    execute $f$create function public.mainsite_outbox_put(p_topic text, p_key text, p_body jsonb) returns void
      language sql security definer set search_path = public as $g$
        insert into public.mainsite_outbox (topic, idem_key, body) values (p_topic, p_key, p_body)
          on conflict (topic, idem_key) do nothing
      $g$ $f$;
  end if;
end $do$;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid(), msu text);
insert into _u (k, msu) values ('att', 'ChkAtt01'), ('def', 'ChkDef01'), ('nolink', null), ('stale', 'ChkStale1'),
  ('bad', 'ChkBad01'), ('cnt', 'ChkCnt01');
create temp table _r (k text primary key, r jsonb);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
grant all on _r to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.msu(p_k text) returns text language sql as $$ select msu from _u where k = p_k $$;
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
-- 合法阵容快照（三统领、分路齐；= build_ghost_snapshot 的那几个键）。p_open = false ⇒ 只有两只统领（本周没开轮）
create or replace function pg_temp.snap(p_name text, p_a text, p_b text, p_c text, p_open boolean default true) returns jsonb
language sql as $$
  select jsonb_build_object('schema_ver', 2, 'ghost_id', 'g_' || p_name, 'is_bot', false,
    'profile', jsonb_build_object('name', p_name, 'avatar', p_a, 'id', 'g_' || p_name, 'tag', 'chk-' || p_name),
    'leaders', case when p_open then jsonb_build_array(p_a, p_b, p_c) else jsonb_build_array(p_a, p_b) end,
    'lane_assign', case when p_open then jsonb_build_object('top', jsonb_build_array(p_a), 'bottom', jsonb_build_array(p_b, p_c))
                        else jsonb_build_object('top', jsonb_build_array(p_a), 'bottom', jsonb_build_array(p_b)) end,
    'minions', jsonb_build_object('top', jsonb_build_array(), 'bottom', jsonb_build_array()),
    'equipped', jsonb_build_object(p_a, jsonb_build_array(jsonb_build_object('id', 'p2eq_001', 'star', 1))),
    'pet_levels', jsonb_build_object(p_a, 1, p_b, 1, p_c, 1),
    'season_total_battles', 99, 'season_level', 4, 'season_wins', 0, 'hearts', 6, 'season_sweeps', 0)
$$;
create or replace function pg_temp.put(p_k text, p_week bigint, p_snap jsonb, p_dev text default null) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  r := public.raid_defense_put(p_week, p_snap, p_dev);
  perform pg_temp.as_user(null);
  return pg_temp.keep(p_k, r);
end $$;
-- 发件箱：某个主站用户的 defense 条数 / 最新一条；某个 raidId 的 started / settle
create or replace function pg_temp.def_n(p_k text) returns int language sql as $$
  select count(*)::int from public.mainsite_outbox where topic = 'defense' and body ->> 'userId' = pg_temp.msu(p_k)
$$;
create or replace function pg_temp.def_last(p_k text) returns jsonb language sql as $$
  select body from public.mainsite_outbox where topic = 'defense' and body ->> 'userId' = pg_temp.msu(p_k)
   order by id desc limit 1
$$;
create or replace function pg_temp.ob(p_topic text, p_raid bigint) returns jsonb language sql as $$
  select body from public.mainsite_outbox where topic = p_topic and idem_key = p_raid::text
$$;
create or replace function pg_temp.ob_n(p_topic text, p_raid bigint) returns int language sql as $$
  select count(*)::int from public.mainsite_outbox where topic = p_topic and idem_key = p_raid::text
$$;
create or replace function pg_temp.now_ms() returns bigint language sql as $$
  select floor(extract(epoch from now()) * 1000)::bigint
$$;
create or replace function pg_temp.raid(p_id bigint, p_att text, p_def text, p_seed bigint default 777) returns jsonb
language sql as $$
  select public.raid_create(p_id, p_att, p_def, p_seed, 50, false, pg_temp.now_ms() + 6 * 3600 * 1000)
$$;
create or replace function pg_temp.rj(p_id bigint) returns public.raid_jobs language sql as $$
  select * from public.raid_jobs where raid_id = p_id
$$;
create or replace function pg_temp.job_of(p_id bigint) returns public.referee_jobs language sql as $$
  select j.* from public.referee_jobs j join public.raid_jobs r on r.referee_job_id = j.job_id where r.raid_id = p_id
$$;
-- 一份裁判结果单（与 RefereeJob.ok_result 同形）
create or replace function pg_temp.result(p_job bigint, p_winner text, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql as $$
  select jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', j.seed, 'client_version', j.client_version,
    'winner', p_winner, 'steps', 1234, 'replay_b64', 'QUJDRA==', 'score_code', 0, 'coins', 7, 'coins_b', 5,
    'lane_results', jsonb_build_object('top', 'left', 'bottom', 'left'),
    'chest', jsonb_build_object('value', 41.5, 'won', jsonb_build_array('p2eq_201')),
    'incense', jsonb_build_object('marks', 2, 'charge', 3)) || p_extra
    from public.referee_jobs j where j.job_id = p_job
$$;
-- 领一份（只领检查脚本自己的版本 ⇒ 内测服真任务不受影响）
create or replace function pg_temp.claim(p_worker text default 'chk-w1') returns jsonb language sql as $$
  select public.referee_claim(p_worker, array['9.9.10'], 1)
$$;
-- 「不发任何东西」的分母：两个人在各账本 / 快照池里的行数
create or replace function pg_temp.ledgers() returns text language sql as $$
  select format('ranked=%s gauntlet=%s ghosts=%s gghosts=%s pending=%s',
    (select coalesce(sum(battles), 0) from public.ranked_records where account_id in (pg_temp.u('att'), pg_temp.u('def'))),
    (select coalesce(sum(gw + gl), 0) from public.gauntlet_records where account_id in (pg_temp.u('att'), pg_temp.u('def'))),
    (select count(*) from public.ghosts where account_id in (pg_temp.u('att'), pg_temp.u('def'))),
    (select count(*) from public.gauntlet_ghosts where account_id in (pg_temp.u('att'), pg_temp.u('def'))),
    (select count(*) from public.finals_pending where account_id in (pg_temp.u('att'), pg_temp.u('def'))))
$$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
insert into public.accounts (account_id) select id from _u on conflict do nothing;
insert into public.mainsite_accounts (account_id, mainsite_user_id)
  select id, msu from _u where msu is not null and k <> 'cnt';
insert into public.mainsite_pets (account_id, pet_key, fetched_at) values
  (pg_temp.u('att'), 'stone', now()), (pg_temp.u('att'), 'basic', now()), (pg_temp.u('def'), 'ninja', now());
update public.referee_config set raid_on = false where id = 1;
alter table public.referee_config add column if not exists econ_on boolean not null default false;   -- econ/ledger 的那一列（没合进来时补上）
update public.referee_config set econ_on = false where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 4), ('9.9.10', true, 4)
  on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;
select pg_temp.set_fake(3, 12);   -- 假周三 12:00

-- ═══ D 防守阵容 ═══
select pg_temp.ck('D1 不带登录 ⇒ not_signed_in',
  public.raid_defense_put(pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), 'dev-A') ->> 'reason' = 'not_signed_in');
-- ★动作与断言分两句：同一句里的子查询用的是语句开始时的快照，看不到 put 刚写的行（那样断言恒真）
select pg_temp.keep('d2', pg_temp.put('att', pg_temp.fake_week() - 604800, pg_temp.snap('att', 'basic', 'stone', 'bamboo')));
select pg_temp.ck('D2 上一周的周号 ⇒ wrong_week、不存',
  pg_temp.r('d2') ->> 'reason' = 'wrong_week'
  and not exists (select 1 from public.raid_defense where account_id = pg_temp.u('att')), pg_temp.r('d2')::text);
select pg_temp.keep('d3', pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo', false)));
select pg_temp.ck('D3 ★本周没开轮（只有两只统领）⇒ 不存、has_defense = false',
  (pg_temp.r('d3') ->> 'has_defense')::boolean = false and pg_temp.r('d3') ->> 'stored' = 'false'
  and not exists (select 1 from public.raid_defense where account_id = pg_temp.u('att')), pg_temp.r('d3')::text);
select pg_temp.ck('D4 快照不是对象 ⇒ bad_snapshot',
  pg_temp.put('att', pg_temp.fake_week(), '[1,2]'::jsonb) ->> 'reason' = 'bad_snapshot');
select pg_temp.ck('D5 快照超过 64 KB ⇒ bad_snapshot',
  pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo')
    || jsonb_build_object('pad', repeat('x', 70000))) ->> 'reason' = 'bad_snapshot');
-- 服务器记录的本大轮场数：积分赛账本 5 场
insert into public.ranked_records (season_week, account_id, battles, wins, hearts, used)
  values (pg_temp.fake_week(), pg_temp.u('att'), 5, 3, 4, 5);
select pg_temp.ck('D6 ★开轮 + 已绑定 ⇒ has_defense；发件箱 defense 一条 {hasDefense:true, rating:5(服务器账本, 不是快照自报的 99), device}',
  (pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), 'dev-A') ->> 'has_defense')::boolean
  and pg_temp.def_n('att') = 1
  and pg_temp.def_last('att') = jsonb_build_object('userId', 'ChkAtt01', 'hasDefense', true, 'rating', 5, 'device', 'dev-A'),
  coalesce(pg_temp.def_last('att')::text, 'null'));
select pg_temp.ck('D7 同一份再存一次（没变化）⇒ 不重报',
  (pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), 'dev-A') ->> 'has_defense')::boolean
  and pg_temp.def_n('att') = 1, pg_temp.def_n('att')::text);
select pg_temp.keep('d8', pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo')
  || jsonb_build_object('owned', jsonb_build_array('phoenix', 'lava'), 'account_id', gen_random_uuid()::text), 'dev-A'));
select pg_temp.ck('D8 ★客户端快照里自带的 owned / account_id 摘掉（拥有以服务器为准）',
  (pg_temp.r('d8') ->> 'stored')::boolean
  and (select snapshot from public.raid_defense where account_id = pg_temp.u('att')) ? 'leaders'
  and not ((select snapshot from public.raid_defense where account_id = pg_temp.u('att')) ? 'owned')
  and not ((select snapshot from public.raid_defense where account_id = pg_temp.u('att')) ? 'account_id')
  and pg_temp.def_n('att') = 1);
select pg_temp.ck('D9 设备号变了 ⇒ 重报（device = dev-B）',
  (pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), 'dev-B') ->> 'ok')::boolean
  and pg_temp.def_n('att') = 2 and pg_temp.def_last('att') ->> 'device' = 'dev-B', coalesce(pg_temp.def_last('att')::text, 'null'));
select pg_temp.keep('d10', pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), ''));
select pg_temp.ck('D10 设备号空串 ⇒ 沿用上一次的、不重报',
  (pg_temp.r('d10') ->> 'stored')::boolean
  and pg_temp.def_n('att') = 2 and (select device from public.raid_defense where account_id = pg_temp.u('att')) = 'dev-B');
select pg_temp.keep('d11', pg_temp.put('nolink', pg_temp.fake_week(), pg_temp.snap('nolink', 'basic', 'stone', 'bamboo'), 'dev-N'));
select pg_temp.ck('D11 没绑定的号：存（has_defense）但发件箱一条都没有',
  (pg_temp.r('d11') ->> 'has_defense')::boolean
  and exists (select 1 from public.raid_defense where account_id = pg_temp.u('nolink') and device = 'dev-N')
  and not exists (select 1 from public.mainsite_outbox where idem_key like '%' || pg_temp.u('nolink')::text || '%'));
select pg_temp.ck('D12 守方开轮 ⇒ 报 has_defense（rating 0：本周没打过）',
  (pg_temp.put('def', pg_temp.fake_week(), pg_temp.snap('def', 'ninja', 'dice', 'pirate'), 'dev-D') ->> 'has_defense')::boolean
  and pg_temp.def_last('def') = jsonb_build_object('userId', 'ChkDef01', 'hasDefense', true, 'rating', 0, 'device', 'dev-D'),
  coalesce(pg_temp.def_last('def')::text, 'null'));

-- ═══ R rating ═══
insert into public.gauntlet_records (season_week, account_id, gw, gl) values (pg_temp.fake_week(), pg_temp.u('att'), 2, 1);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account,
    a_snapshot, b_snapshot, status, done_at)
  values ('finals', 'chk-raid-finals-1', pg_temp.fake_week(), '9.9.9', 5, pg_temp.u('cnt'), pg_temp.u('att'),
    pg_temp.snap('cnt', 'basic', 'stone', 'bamboo'), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), 'done', now());
select pg_temp.ck('R1 ★rating = 积分赛 5 + 闯关 2 胜 1 负 + 周日决赛 1 局（我在 B 侧）= 9',
  public.raid_rating(pg_temp.u('att'), pg_temp.fake_week()) = 9, public.raid_rating(pg_temp.u('att'), pg_temp.fake_week())::text);
select pg_temp.ck('R2 别的周的账不算（上一周 0）', public.raid_rating(pg_temp.u('att'), pg_temp.fake_week() - 604800) = 0);
-- 一局积分赛走真写回（referee_complete）⇒ 账本 +1 ⇒ 钩子重报
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
    status, claimed_by, claimed_at, attempts, meta)
  values ('ranked', 'chk-raid-ranked-1', pg_temp.fake_week(), '9.9.10', 11, pg_temp.u('att'),
    pg_temp.snap('att', 'basic', 'stone', 'bamboo'), pg_temp.snap('x', 'ninja', 'dice', 'pirate'),
    'claimed', 'chk-w0', now(), 1, jsonb_build_object('rules_ver', 4, 'account', pg_temp.u('att')));
select pg_temp.keep('rc1', public.referee_complete((select job_id from public.referee_jobs where match_key = 'chk-raid-ranked-1'),
  'chk-w0', pg_temp.result((select job_id from public.referee_jobs where match_key = 'chk-raid-ranked-1'), 'a')));
select pg_temp.ck('R3 ★打完一局积分赛（真 referee_complete）⇒ 发件箱 defense 重报 rating 10（= 9 + 1）',
  (pg_temp.r('rc1') ->> 'ok')::boolean and pg_temp.def_n('att') = 3
  and (pg_temp.def_last('att') ->> 'rating')::int = 10
  and (pg_temp.def_last('att') ->> 'rating')::int = public.raid_rating(pg_temp.u('att'), pg_temp.fake_week()),
  pg_temp.r('rc1')::text || ' / ' || coalesce(pg_temp.def_last('att')::text, 'null'));
-- 报主站那一步出错（发件箱函数不在）⇒ 周赛记账照样成功
alter function public.mainsite_outbox_put(text, text, jsonb) rename to mainsite_outbox_put_chk_gone;
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
    status, claimed_by, claimed_at, attempts, meta)
  values ('ranked', 'chk-raid-ranked-2', pg_temp.fake_week(), '9.9.10', 12, pg_temp.u('att'),
    pg_temp.snap('att', 'basic', 'stone', 'bamboo'), pg_temp.snap('x', 'ninja', 'dice', 'pirate'),
    'claimed', 'chk-w0', now(), 1, jsonb_build_object('rules_ver', 4, 'account', pg_temp.u('att')));
select pg_temp.keep('rc2', public.referee_complete((select job_id from public.referee_jobs where match_key = 'chk-raid-ranked-2'),
  'chk-w0', pg_temp.result((select job_id from public.referee_jobs where match_key = 'chk-raid-ranked-2'), 'b')));
alter function public.mainsite_outbox_put_chk_gone(text, text, jsonb) rename to mainsite_outbox_put;
select pg_temp.ck('R4 ★报主站出错不拖垮周赛记账：referee_complete ok、账本 +1（7 场）、任务 done、没有报出去',
  (pg_temp.r('rc2') ->> 'ok')::boolean
  and (select battles from public.ranked_records where season_week = pg_temp.fake_week() and account_id = pg_temp.u('att')) = 7
  and (select status from public.referee_jobs where match_key = 'chk-raid-ranked-2') = 'done' and pg_temp.def_n('att') = 3,
  pg_temp.r('rc2')::text);
select pg_temp.ck('R5 下一次报（存阵容 / 下一局）补上：rating 11',
  (public.raid_defense_report(pg_temp.u('att')) ->> 'sent')::boolean and (pg_temp.def_last('att') ->> 'rating')::int = 11);

-- ═══ C 建任务 ═══
-- 守方「过期阵容」（上周的）/ 「阵容不合法」（本周但只有两只）直接造行
insert into public.raid_defense (account_id, season_week, snapshot, device)
  values (pg_temp.u('stale'), pg_temp.fake_week() - 604800, pg_temp.snap('stale', 'basic', 'stone', 'bamboo'), 'dev-S'),
         (pg_temp.u('bad'), pg_temp.fake_week(), pg_temp.snap('bad', 'basic', 'stone', 'bamboo', false), 'dev-X');
select pg_temp.ck('C1 raid_on 关 ⇒ raid_off（迁移刚上、开关关 ⇒ 不收任务）',
  pg_temp.raid(9001, 'ChkAtt01', 'ChkDef01') ->> 'error' = 'raid_off' and pg_temp.rj(9001) is null);
update public.referee_config set raid_on = true where id = 1;
select pg_temp.ck('C2 ★raid_on 开但 econ_on 关 ⇒ 仍是 raid_off（§4.9 记账没开不许偷袭）',
  pg_temp.raid(9001, 'ChkAtt01', 'ChkDef01') ->> 'error' = 'raid_off' and not public.raid_enabled());
update public.referee_config set econ_on = true where id = 1;
select pg_temp.ck('C3 参数：raidId 0 ⇒ bad_raidId / 攻守同一人 ⇒ same_user / 纯数字 ID ⇒ bad_userId / expireAt 已过 ⇒ expired',
  pg_temp.raid(0, 'ChkAtt01', 'ChkDef01') ->> 'error' = 'bad_raidId'
  and pg_temp.raid(9001, 'ChkAtt01', 'ChkAtt01') ->> 'error' = 'same_user'
  and pg_temp.raid(9001, '12345', 'ChkDef01') ->> 'error' = 'bad_userId'
  and public.raid_create(9001, 'ChkAtt01', 'ChkDef01', 1, 1, false, pg_temp.now_ms() - 1000) ->> 'error' = 'expired'
  and pg_temp.rj(9001) is null);
update public.referee_versions set enabled = false where enabled;
select pg_temp.ck('C4 裁判机没有开着的版本 ⇒ no_referee（主站立即退回，不挂单）',
  pg_temp.raid(9001, 'ChkAtt01', 'ChkDef01') ->> 'error' = 'no_referee' and pg_temp.rj(9001) is null);
update public.referee_versions set enabled = true where client_version in ('9.9.9', '9.9.10');
select pg_temp.keep('c5', pg_temp.raid(9001, 'ChkAtt01', 'ChkDef01'));
select pg_temp.ck('C5 ★正常：ok + jobId；raid_jobs 排队；裁判任务 kind = raid、a = 攻方、b = 守方、版本 = 最新开着的（9.9.10 > 9.9.9）、种子 = 主站的 777',
  (pg_temp.r('c5') ->> 'ok')::boolean and pg_temp.r('c5') ->> 'jobId' = (pg_temp.rj(9001)).id::text
  and (pg_temp.rj(9001)).status = 'queued'
  and (pg_temp.job_of(9001)).kind = 'raid' and (pg_temp.job_of(9001)).status = 'pending'
  and (pg_temp.job_of(9001)).a_account = pg_temp.u('att') and (pg_temp.job_of(9001)).b_account = pg_temp.u('def')
  and (pg_temp.job_of(9001)).client_version = '9.9.10' and (pg_temp.job_of(9001)).seed = 777
  and (pg_temp.job_of(9001)).match_key = 'raid:9001' and (pg_temp.rj(9001)).match_id = (pg_temp.job_of(9001)).match_id,
  pg_temp.r('c5')::text);
select pg_temp.ck('C6 ★锁定的快照 = 双方本周那一份 + 服务器 owned（mainsite_pets，排好序）+ account_id；快照里的阵容原样',
  (pg_temp.job_of(9001)).a_snapshot -> 'owned' = '["basic", "stone"]'::jsonb
  and (pg_temp.job_of(9001)).b_snapshot -> 'owned' = '["ninja"]'::jsonb
  and (pg_temp.job_of(9001)).a_snapshot ->> 'account_id' = pg_temp.u('att')::text
  and (pg_temp.job_of(9001)).b_snapshot ->> 'account_id' = pg_temp.u('def')::text
  and (pg_temp.job_of(9001)).a_snapshot -> 'leaders' = '["basic", "stone", "bamboo"]'::jsonb
  and (pg_temp.job_of(9001)).b_snapshot -> 'leaders' = '["ninja", "dice", "pirate"]'::jsonb
  and (pg_temp.rj(9001)).a_owned = '["basic", "stone"]'::jsonb and (pg_temp.rj(9001)).b_snapshot = (pg_temp.job_of(9001)).b_snapshot
  and (pg_temp.rj(9001)).stake = 50,
  ((pg_temp.job_of(9001)).a_snapshot -> 'owned')::text);
select pg_temp.ck('C7 ★同 raidId 重发 ⇒ 回同一个 jobId；raid_jobs 一行、裁判任务一个；还没 started / settle',
  pg_temp.raid(9001, 'ChkAtt01', 'ChkDef01') ->> 'jobId' = pg_temp.r('c5') ->> 'jobId'
  and (select count(*) from public.raid_jobs where raid_id = 9001) = 1
  and (select count(*) from public.referee_jobs where match_key = 'raid:9001') = 1
  and pg_temp.ob_n('started', 9001) = 0 and pg_temp.ob_n('settle', 9001) = 0);
select pg_temp.ck('C8 同 raidId 换了守方 ⇒ raid_conflict', pg_temp.raid(9001, 'ChkAtt01', 'ChkStale1') ->> 'error' = 'raid_conflict');
select pg_temp.keep('c9', pg_temp.raid(9002, 'ChkAtt01', 'ChkStale1'));
select pg_temp.ck('C9 ★守方阵容是上周的（没开本大轮）⇒ ok + jobId，但不排裁判、直接 settle void；没有 started',
  (pg_temp.r('c9') ->> 'ok')::boolean and (pg_temp.rj(9002)).status = 'void' and (pg_temp.rj(9002)).reason = 'defender_no_defense'
  and (pg_temp.rj(9002)).referee_job_id is null and not exists (select 1 from public.referee_jobs where match_key = 'raid:9002')
  and pg_temp.ob('settle', 9002) = jsonb_build_object('raidId', 9002, 'result', 'void', 'matchId', '')
  and pg_temp.ob_n('started', 9002) = 0, coalesce(pg_temp.ob('settle', 9002)::text, 'null'));
select pg_temp.ck('C10 守方没绑定 ⇒ void defender_unlinked / 攻方没绑定 ⇒ void attacker_unlinked',
  (pg_temp.raid(9003, 'ChkAtt01', 'ChkNobody1') ->> 'ok')::boolean and (pg_temp.rj(9003)).reason = 'defender_unlinked'
  and (pg_temp.raid(9004, 'ChkNobody1', 'ChkDef01') ->> 'ok')::boolean and (pg_temp.rj(9004)).reason = 'attacker_unlinked'
  and pg_temp.ob('settle', 9003) ->> 'result' = 'void' and pg_temp.ob('settle', 9004) ->> 'result' = 'void');
select pg_temp.ck('C11 守方本周阵容不合法（两只统领）⇒ void defender_no_defense',
  (pg_temp.raid(9005, 'ChkAtt01', 'ChkBad01') ->> 'ok')::boolean and (pg_temp.rj(9005)).reason = 'defender_no_defense');
select pg_temp.ck('C12 攻方阵容是上周的 ⇒ void attacker_no_defense',
  (pg_temp.raid(9007, 'ChkStale1', 'ChkDef01') ->> 'ok')::boolean and (pg_temp.rj(9007)).reason = 'attacker_no_defense');
select pg_temp.keep('c13', pg_temp.raid(9006, 'ChkAtt01', 'ChkDef01', 0));
select pg_temp.ck('C13 主站种子 0 ⇒ 服务端生成（1 ~ 2^53-1）',
  (pg_temp.r('c13') ->> 'ok')::boolean and (pg_temp.job_of(9006)).seed between 1 and 9007199254740991
  and (pg_temp.rj(9006)).seed = 0);

-- ═══ K 领活与结算 ═══
select pg_temp.keep('led0', to_jsonb(pg_temp.ledgers()));
select pg_temp.keep('rat0', to_jsonb(public.raid_rating(pg_temp.u('att'), pg_temp.fake_week())));
select pg_temp.keep('defn0', to_jsonb(pg_temp.def_n('att') + pg_temp.def_n('def')));
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, created_at)
  values ('gauntlet', 'chk-raid-g-1', pg_temp.fake_week(), '9.9.10', 3, pg_temp.u('cnt'),
    pg_temp.snap('cnt', 'basic', 'stone', 'bamboo'), pg_temp.snap('x', 'ninja', 'dice', 'pirate'), now() + interval '1 hour');
select pg_temp.keep('k1', pg_temp.claim());
select pg_temp.ck('K1 ★偷袭排在闯关后面：闯关局晚建一小时也先领',
  pg_temp.r('k1') -> 0 ->> 'mode' = 'gauntlet', left(pg_temp.r('k1')::text, 200));
update public.referee_jobs set status = 'failed', error = 'chk' where match_key = 'chk-raid-g-1';
select pg_temp.keep('k2', pg_temp.claim());
select pg_temp.ck('K2 ★领到偷袭：任务单 mode = raid、a 带 owned、key 带 raid_id；raid_jobs started；发件箱 started {raidId}',
  pg_temp.r('k2') -> 0 ->> 'mode' = 'raid' and (pg_temp.r('k2') -> 0 ->> 'job_id')::bigint = (pg_temp.rj(9001)).referee_job_id
  and pg_temp.r('k2') -> 0 -> 'a' -> 'owned' = '["basic", "stone"]'::jsonb
  and (pg_temp.r('k2') -> 0 -> 'key' ->> 'raid_id')::bigint = 9001
  and (pg_temp.rj(9001)).status = 'started' and (pg_temp.rj(9001)).started_at is not null
  and pg_temp.ob('started', 9001) = jsonb_build_object('raidId', 9001) and pg_temp.ob_n('settle', 9001) = 0,
  left(pg_temp.r('k2')::text, 300));
select public.referee_fail((pg_temp.rj(9001)).referee_job_id, 'chk-w1', 'rc=3 transient', false);
select pg_temp.keep('k3', pg_temp.claim('chk-w2'));
select pg_temp.ck('K3 算失败放回重领 ⇒ 还是这一场；started 不重发（只 1 条）',
  (pg_temp.r('k3') -> 0 ->> 'job_id')::bigint = (pg_temp.rj(9001)).referee_job_id and pg_temp.ob_n('started', 9001) = 1
  and (pg_temp.rj(9001)).status = 'started');
select pg_temp.keep('k4', public.referee_complete((pg_temp.rj(9001)).referee_job_id, 'chk-w2',
  pg_temp.result((pg_temp.rj(9001)).referee_job_id, 'a', jsonb_build_object('raid_result', 'attacker'))));
select pg_temp.ck('K4 ★a（攻方）赢 ⇒ settle {raidId, result:attacker, matchId = 录像 id}；raid_jobs done',
  (pg_temp.r('k4') ->> 'ok')::boolean and (pg_temp.rj(9001)).status = 'done' and (pg_temp.rj(9001)).result = 'attacker'
  and pg_temp.ob('settle', 9001) = jsonb_build_object('raidId', 9001, 'result', 'attacker',
                                                      'matchId', (pg_temp.job_of(9001)).match_id::text),
  coalesce(pg_temp.ob('settle', 9001)::text, 'null') || ' ' || pg_temp.r('k4')::text);
select pg_temp.ck('K5 ★偷袭局不发任何东西：积分赛 / 闯关账本、快照池、决赛报名一行不变；rating 不变；不触发 defense',
  pg_temp.ledgers() = pg_temp.r('led0') #>> '{}'
  and public.raid_rating(pg_temp.u('att'), pg_temp.fake_week()) = (pg_temp.r('rat0') #>> '{}')::int
  and pg_temp.def_n('att') + pg_temp.def_n('def') = (pg_temp.r('defn0') #>> '{}')::int,
  pg_temp.ledgers() || ' / ' || (pg_temp.r('led0') #>> '{}'));
select pg_temp.ck('K6 录像落 matches（phase = raid、左 = 攻方）',
  exists (select 1 from public.matches where match_id = (pg_temp.job_of(9001)).match_id and phase = 'raid'
          and left_account = pg_temp.u('att')));
select pg_temp.ck('K7 同一局重复写回 ⇒ already_done、settle 仍只 1 条',
  public.referee_complete((pg_temp.rj(9001)).referee_job_id, 'chk-w2',
    pg_temp.result((pg_temp.rj(9001)).referee_job_id, 'a')) ->> 'reason' = 'already_done'
  and pg_temp.ob_n('settle', 9001) = 1);
select pg_temp.keep('k8', pg_temp.claim());
select public.referee_complete((pg_temp.rj(9006)).referee_job_id, 'chk-w1', pg_temp.result((pg_temp.rj(9006)).referee_job_id, 'b'));
select pg_temp.ck('K8 ★b（守方）赢 ⇒ settle defender',
  (pg_temp.r('k8') -> 0 ->> 'job_id')::bigint = (pg_temp.rj(9006)).referee_job_id
  and (pg_temp.rj(9006)).result = 'defender' and pg_temp.ob('settle', 9006) ->> 'result' = 'defender');
select pg_temp.raid(9010, 'ChkAtt01', 'ChkDef01');
select pg_temp.claim();
select public.referee_complete((pg_temp.rj(9010)).referee_job_id, 'chk-w1',
  pg_temp.result((pg_temp.rj(9010)).referee_job_id, 'a', jsonb_build_object('raid_result', 'defender')));
select pg_temp.ck('K9 裁判带的 raid_result 与 winner 对不上 ⇒ void bad_result',
  (pg_temp.rj(9010)).status = 'void' and (pg_temp.rj(9010)).reason = 'bad_result' and pg_temp.ob('settle', 9010) ->> 'result' = 'void');
select pg_temp.raid(9011, 'ChkAtt01', 'ChkDef01');
select pg_temp.claim();
select public.referee_fail((pg_temp.rj(9011)).referee_job_id, 'chk-w1', 'a_bad_snapshot', true);
select pg_temp.ck('K10 ★裁判拒算（permanent）⇒ void、settle void、原因记下',
  (pg_temp.rj(9011)).status = 'void' and (pg_temp.rj(9011)).reason = 'a_bad_snapshot'
  and pg_temp.ob('settle', 9011) = jsonb_build_object('raidId', 9011, 'result', 'void', 'matchId', ''));
select pg_temp.raid(9012, 'ChkAtt01', 'ChkDef01');
update public.raid_jobs set expire_at = now() - interval '1 second' where raid_id = 9012;
select pg_temp.keep('k11', pg_temp.claim());
select pg_temp.ck('K11 ★过了 expireAt 还没开算 ⇒ 不领', jsonb_array_length(pg_temp.r('k11')) = 0
  and (pg_temp.job_of(9012)).status = 'pending', pg_temp.r('k11')::text);
select pg_temp.keep('k12', to_jsonb(public.raid_sweep()));
select pg_temp.ck('K12 ★raid_sweep 收掉：任务 failed raid_expired、raid void、不发 started / settle（主站到点自己退）',
  (pg_temp.r('k12') #>> '{}')::int = 1 and (pg_temp.job_of(9012)).status = 'failed' and (pg_temp.job_of(9012)).error = 'raid_expired'
  and (pg_temp.rj(9012)).status = 'void' and (pg_temp.rj(9012)).reason = 'raid_expired'
  and pg_temp.ob_n('settle', 9012) = 0 and pg_temp.ob_n('started', 9012) = 0, pg_temp.r('k12')::text);
select pg_temp.raid(9013, 'ChkAtt01', 'ChkDef01');
select pg_temp.claim();
update public.raid_jobs set started_at = now() - interval '29 minutes' where raid_id = 9013;
select pg_temp.ck('K13 开算 29 分钟 ⇒ 还不作废', public.raid_sweep() = 0 and (pg_temp.rj(9013)).status = 'started');
update public.raid_jobs set started_at = now() - interval '31 minutes' where raid_id = 9013;
update public.referee_jobs set claimed_at = now() - interval '1 hour' where job_id = (pg_temp.rj(9013)).referee_job_id;
select pg_temp.keep('k14', pg_temp.claim('chk-w3'));
select pg_temp.ck('K14 ★开算 31 分钟（租期也过了）⇒ 别的裁判也不重领', jsonb_array_length(pg_temp.r('k14')) = 0, pg_temp.r('k14')::text);
select pg_temp.ck('K15 ★raid_sweep ⇒ failed raid_timeout、void、settle void；迟到的写回 not_owner',
  public.raid_sweep() = 1 and (pg_temp.rj(9013)).status = 'void' and (pg_temp.rj(9013)).reason = 'raid_timeout'
  and pg_temp.ob('settle', 9013) ->> 'result' = 'void'
  and public.referee_complete((pg_temp.rj(9013)).referee_job_id, 'chk-w1',
        pg_temp.result((pg_temp.rj(9013)).referee_job_id, 'a')) ->> 'reason' = 'not_owner'
  and pg_temp.ob_n('settle', 9013) = 1);
select pg_temp.ck('K16 ★全部偷袭结算完：周赛账本 / 快照池 / rating 仍一行不变',
  pg_temp.ledgers() = pg_temp.r('led0') #>> '{}'
  and public.raid_rating(pg_temp.u('att'), pg_temp.fake_week()) = (pg_temp.r('rat0') #>> '{}')::int,
  pg_temp.ledgers());

-- 发件箱写不进（A1 出问题）：领活 / 租期回收不许跟着失败（那会把周赛局也卡住）
select pg_temp.raid(9020, 'ChkAtt01', 'ChkDef01');
select pg_temp.raid(9021, 'ChkAtt01', 'ChkDef01');
select pg_temp.claim('chk-w5');
update public.referee_jobs set claimed_at = now() - interval '1 hour', attempts = 3
 where job_id = (pg_temp.rj(9020)).referee_job_id;
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot)
  values ('gauntlet', 'chk-raid-g-2', pg_temp.fake_week(), '9.9.10', 4, pg_temp.u('cnt'),
    pg_temp.snap('cnt', 'basic', 'stone', 'bamboo'), pg_temp.snap('x', 'ninja', 'dice', 'pirate'));
alter function public.mainsite_outbox_put(text, text, jsonb) rename to mainsite_outbox_put_chk_gone;
select pg_temp.keep('k17', pg_temp.claim('chk-w6'));
select pg_temp.keep('k17b', pg_temp.claim('chk-w6'));
alter function public.mainsite_outbox_put_chk_gone(text, text, jsonb) rename to mainsite_outbox_put;
select pg_temp.ck('K17 ★发件箱写不进时领活照常：租期回收把次数用尽的偷袭记 failed、周赛局照领、下一个偷袭也领得走',
  pg_temp.r('k17') -> 0 ->> 'mode' = 'gauntlet' and pg_temp.r('k17b') -> 0 ->> 'mode' = 'raid'
  and (pg_temp.r('k17b') -> 0 ->> 'job_id')::bigint = (pg_temp.rj(9021)).referee_job_id
  and (pg_temp.job_of(9020)).status = 'failed' and pg_temp.ob_n('settle', 9020) = 0 and pg_temp.ob_n('started', 9021) = 0,
  left(pg_temp.r('k17')::text, 120) || ' / ' || left(pg_temp.r('k17b')::text, 120));
select public.referee_complete((pg_temp.rj(9021)).referee_job_id, 'chk-w6', pg_temp.result((pg_temp.rj(9021)).referee_job_id, 'a'));
select pg_temp.ck('K18 丢了 started 的那一场写回照样 settle（主站那边没延期就按它自己的超时作废，钱不会错）',
  (pg_temp.rj(9021)).status = 'done' and pg_temp.ob('settle', 9021) ->> 'result' = 'attacker');

-- ═══ P 周清 ═══
insert into public.matches (match_id, season_week, phase, seed, left_snapshot, right_snapshot, result, client_version, created_at)
  values ('11111111-1111-4111-8111-000000000010', 1, 'raid', 1, '{}', '{}', '{}', '9.9.10', now() - interval '10 days'),
         ('11111111-1111-4111-8111-000000000031', 1, 'raid', 1, '{}', '{}', '{}', '9.9.10', now() - interval '31 days'),
         ('11111111-1111-4111-8111-000000000008', 1, 'ranked', 1, '{}', '{}', '{}', '9.9.10', now() - interval '8 days');
update public.raid_jobs set created_at = now() - interval '31 days' where raid_id = 9002;
select public.purge_old_matches();
select pg_temp.ck('P1 ★偷袭录像 10 天的留着（周清不删）、31 天的删；积分赛上周的照旧删；31 天的 raid_jobs 删、新的留',
  exists (select 1 from public.matches where match_id = '11111111-1111-4111-8111-000000000010')
  and not exists (select 1 from public.matches where match_id = '11111111-1111-4111-8111-000000000031')
  and not exists (select 1 from public.matches where match_id = '11111111-1111-4111-8111-000000000008')
  and (pg_temp.rj(9002)).id is null and (pg_temp.rj(9001)).id is not null);

-- ═══ F 权限 / 结构 ═══
select pg_temp.ck('F1 存阵容只给 authenticated（anon 调不了）',
  has_function_privilege('authenticated', 'public.raid_defense_put(bigint, jsonb, text)', 'execute')
  and not has_function_privilege('anon', 'public.raid_defense_put(bigint, jsonb, text)', 'execute'));
select pg_temp.ck('F2 建任务 / 报主站 / 换周 / 清扫只给 service_role（客户端两个角色都调不了）',
  has_function_privilege('service_role', 'public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint)', 'execute')
  and not has_function_privilege('anon', 'public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint)', 'execute')
  and has_function_privilege('service_role', 'public.raid_defense_report(uuid, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.raid_defense_report(uuid, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.raid_week_rollover()', 'execute')
  and not has_function_privilege('authenticated', 'public.raid_sweep()', 'execute')
  and not has_function_privilege('authenticated', 'public.raid_on_job(bigint, text, text, jsonb, uuid)', 'execute'));
select pg_temp.ck('F3 raid_defense / raid_jobs 开了行级安全、没有任何策略',
  (select relrowsecurity from pg_class where oid = 'public.raid_defense'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.raid_jobs'::regclass)
  and (select count(*) from pg_policies where schemaname = 'public' and tablename in ('raid_defense', 'raid_jobs')) = 0);
do $$ declare ok boolean := false; begin
  begin
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_snapshot, b_snapshot)
      values ('raidx', 'chk-raidx', 1, '9.9.10', 1, '{}', '{}');
    ok := true;
  exception when check_violation then ok := false;
  end;
  perform pg_temp.ck('F4 referee_jobs.kind 认 raid（C5 建得出来）、不认 raidx', not ok);
end $$;
select pg_temp.ck('F5 两条 cron：raid_week_rollover 每小时第 3 分钟、raid_sweep 每分钟',
  exists (select 1 from cron.job where jobname = 'raid_week_rollover' and schedule = '3 * * * *')
  and exists (select 1 from cron.job where jobname = 'raid_sweep' and schedule = '* * * * *'));
select pg_temp.ck('F6 状态钩子挂在 referee_jobs 上', exists (select 1 from pg_trigger
  where tgrelid = 'public.referee_jobs'::regclass and tgname = 'raid_job_status' and not tgisinternal));

-- ═══ W 换周（放在最后：改了假时钟）═══
select pg_temp.keep('w_att0', to_jsonb(pg_temp.def_n('att')));
select pg_temp.keep('w_def0', to_jsonb(pg_temp.def_n('def')));
select pg_temp.set_fake(8, 0, 30);   -- 下一个周一 00:30
select pg_temp.ck('W0 分母：周锚点换了、旧阵容不再算数', not public.raid_has_defense(pg_temp.u('att')));
select pg_temp.keep('w1', to_jsonb(public.raid_week_rollover()));
select pg_temp.ck('W1 ★换周：上周报过有阵容的两个已绑定号各报一次 {hasDefense:false, rating:0}；没绑定的、从没报过的不报',
  (pg_temp.r('w1') #>> '{}')::int = 2
  and pg_temp.def_n('att') = (pg_temp.r('w_att0') #>> '{}')::int + 1
  and pg_temp.def_last('att') = jsonb_build_object('userId', 'ChkAtt01', 'hasDefense', false, 'rating', 0, 'device', 'dev-B')
  and pg_temp.def_last('def') ->> 'hasDefense' = 'false' and pg_temp.def_n('stale') = 0
  and not exists (select 1 from public.mainsite_outbox where idem_key like '%' || pg_temp.u('nolink')::text || '%'),
  pg_temp.r('w1')::text || ' ' || coalesce(pg_temp.def_last('att')::text, 'null'));
select pg_temp.ck('W2 重跑（每小时一次）⇒ 不重报', public.raid_week_rollover() = 0
  and pg_temp.def_n('att') = (pg_temp.r('w_att0') #>> '{}')::int + 1);
select pg_temp.ck('W3 ★新的一周双方都还没开轮 ⇒ 建任务 void attacker_no_defense（周一没有可偷的对手）',
  (pg_temp.raid(9100, 'ChkAtt01', 'ChkDef01') ->> 'ok')::boolean and (pg_temp.rj(9100)).reason = 'attacker_no_defense');
select pg_temp.ck('W4 本周第一次开打存阵容 ⇒ 报回 hasDefense:true（rating = 新一周的 0）',
  (pg_temp.put('att', pg_temp.fake_week(), pg_temp.snap('att', 'basic', 'stone', 'bamboo'), 'dev-B') ->> 'has_defense')::boolean
  and pg_temp.def_last('att') = jsonb_build_object('userId', 'ChkAtt01', 'hasDefense', true, 'rating', 0, 'device', 'dev-B'));
delete from public.mainsite_accounts where account_id = pg_temp.u('att');
select pg_temp.keep('u1', public.raid_defense_report(pg_temp.u('att')));
select pg_temp.ck('U1 解绑了 ⇒ 不报、上次报的状态清掉（换周不再挑它；重新绑定从头报）',
  pg_temp.r('u1') ->> 'linked' = 'false' and pg_temp.r('u1') ->> 'sent' = 'false'
  and (select rep_user is null and rep_has is null from public.raid_defense where account_id = pg_temp.u('att')),
  pg_temp.r('u1')::text);

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
