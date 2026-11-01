-- 20261101d 积分赛交给服务器 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261101d_ranked_referee
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
-- 假时间照 20261029 检查脚本（本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原）。
-- 判据：
--   G 开战闸（= 客户端 _battle_block_msg + can_start_match_utc 的服务端那一份）：off / not_signed_in / update_required
--     （没登记 / 低于 0.22.7 / 规则版本不符）/ wrong_week / closed（周一、周六、周五 22:50 起封盘；周二 00:00 与周五 22:49 开；
--     ranked_any_day 只放开星期几、封盘照关）/ bad_snapshot / stale（回账本）/ eliminated / quota_full
--   P 挑对手（= Backend.find_opponent / pool_find_battles）：300 次只出现同场次、同周、同规则版本、合格、不是自己的那几份；
--     真人与陪练都抽得到（每一份都出现过 = 等概率抽、没有只取最新）；排除表生效；没有候选 ⇒ 机器人（同场次那一格；超出池子 ⇒
--     最大一格 + 场次改成玩家的）；池子也没有 ⇒ no_opponent
--   S 建任务：kind = ranked、A 快照的场次 / 胜 / 命 / 横扫 / 碎蛋 = 服务端账本、ghost_id 场次后缀跟着改；真人对手 b_account = 主人；
--     陪练 / 机器人 b_account 空；在算 ⇒ 回同一场；算失败重交种子不换；b_bad_snapshot ⇒ 换对手（排除旧的）
--   R 结算表（RANKED_SETTLE_CASES，门禁 verify_ranked_server_rules 拿同一张表跑本机 _settle_season）：命 / 胜 / 横扫 / 碎蛋 / 场次 /
--     配额 / 币逐格相等；结果单回 ranked；job_status 回 kind / ranked / seed
--   K 写回副作用：ghosts 一行（服务端的数、新场次、宝箱 / 香火取结果单）；matches 一行（phase ranked、right_account 空、
--     摘掉 ghost_id / is_bot）；积分赛局不进 gauntlet_records；闯关局照旧进
--   L 周榜：有账本的人按账本排（快照自报更高也不信）；没账本的按快照
--   W 写权限：ranked_client_write 开 ⇒ 客户端能写自己的 ghosts / 积分赛 matches；关 ⇒ 都被行级策略拒；周日 matches 不受影响
--   Q 领活：真人的积分赛局排在陪练号的积分赛局前面；闯关局之间仍按时间
--   M 切换那一周：没账本、有旧自报快照 ⇒ 账从快照接（seeded = ghosts）
--   F referee_flags 多回 ranked_on；权限：开战 / 读账只给 authenticated，池子上传只给 service_role
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['me', 'h1', 'h2', 'h3', 'old', 'self', 'bot1', 'leg', 'elim', 'full', 'q_h', 'q_b',
  'lb1', 'lb2', 'w', 'g', 'dirty', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9', 'c10', 'ret', 'nop']);
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
-- 合法阵容快照（三统领、分路齐、客户端 build_ghost_snapshot 的那几个键）
create or replace function pg_temp.snap(p_name text, p_battles int default 0) returns jsonb language sql as $$
  select jsonb_build_object('schema_ver', 2, 'ghost_id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
    'profile', jsonb_build_object('name', p_name, 'avatar', 'ninja', 'id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
                                  'tag', 'chk-' || p_name),
    'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')),
    'equipped', jsonb_build_object('ninja', jsonb_build_array(jsonb_build_object('id', 'p2eq_001', 'star', 1))),
    'pet_levels', jsonb_build_object('ninja', 1, 'dice', 1, 'pirate', 1),
    'season_total_battles', p_battles, 'season_level', 3, 'season_wins', 99, 'hearts', 6, 'season_sweeps', 99,
    'season_eggs_killed', 99)
$$;
-- 以 p_k 的身份开第 p_no 场
create or replace function pg_temp.start(p_k text, p_no int, p_ver text default '0.22.7', p_snap jsonb default null,
    p_rv int default 1) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  r := public.referee_ranked_start(pg_temp.fake_week(), coalesce(p_snap, pg_temp.snap(p_k, p_no)), p_no, p_ver, p_rv);
  perform pg_temp.as_user(null);
  return pg_temp.keep(p_k, r);
end $$;
create or replace function pg_temp.jobs_of(p_k text) returns int language sql as $$
  select count(*)::int from public.referee_jobs where a_account = pg_temp.u(p_k) and kind = 'ranked'
$$;
-- 一份裁判结果单（与 RefereeJob.ok_result 同形）
create or replace function pg_temp.result(p_job bigint, p_won boolean, p_top text, p_bottom text, p_final text, p_coins int)
returns jsonb language sql as $$
  select jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', j.seed, 'client_version', j.client_version,
    'winner', case when p_won then 'a' else 'b' end, 'steps', 1234, 'replay_b64', 'QUJDRA==', 'score_code', 0,
    'lane_results', (jsonb_build_object('top', p_top, 'bottom', p_bottom, 'final', p_final)
                     - case when p_top = '' then 'top' else '' end
                     - case when p_bottom = '' then 'bottom' else '' end
                     - case when p_final = '' then 'final' else '' end),
    'coins', p_coins, 'coins_b', 2,
    'chest', jsonb_build_object('value', 41.5, 'won', jsonb_build_array('p2eq_201')),
    'incense', jsonb_build_object('marks', 2, 'charge', 3))
    from public.referee_jobs j where j.job_id = p_job
$$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
update public.service_status set min_client_version = '0.0.0' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
insert into public.bot_accounts (account_id) values (pg_temp.u('bot1')), (pg_temp.u('q_b')) on conflict do nothing;
update public.referee_config set ranked_on = false, ranked_any_day = false, ranked_client_write = true where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver)
  values ('0.22.6', true, 1), ('0.22.7', true, 1), ('0.22.10', true, 1), ('0.22.8', true, 2)
  on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;
select pg_temp.set_fake(2, 12);   -- 假周二 12:00

-- ═══ G 开战闸 ═══
select pg_temp.ck('G1 ranked_on 关 ⇒ off（迁移刚上、开关全关 ⇒ 现行行为不变）',
  pg_temp.start('me', 0) ->> 'reason' = 'off', pg_temp.r('me')::text);
update public.referee_config set ranked_on = true where id = 1;
select pg_temp.ck('G2 不带登录 ⇒ not_signed_in',
  public.referee_ranked_start(pg_temp.fake_week(), pg_temp.snap('me'), 0, '0.22.7', 1) ->> 'reason' = 'not_signed_in');
select pg_temp.ck('G3 版本没登记 ⇒ update_required', pg_temp.start('me', 0, '0.22.99') ->> 'reason' = 'update_required');
select pg_temp.ck('G4 低于 ranked_min_client（0.22.6）⇒ update_required', pg_temp.start('me', 0, '0.22.6') ->> 'reason' = 'update_required');
select pg_temp.ck('G5 规则版本与登记不符 ⇒ update_required', pg_temp.start('me', 0, '0.22.7', null, 2) ->> 'reason' = 'update_required');
select pg_temp.ck('G6 数字比较：0.22.10 ≥ 0.22.7 ⇒ 过版本闸（走到下一道：池子空 ⇒ no_opponent）',
  pg_temp.start('me', 0, '0.22.10') ->> 'reason' = 'no_opponent', pg_temp.r('me')::text);
do $$ declare r jsonb; begin
  perform pg_temp.as_user(pg_temp.u('me'));
  r := public.referee_ranked_start(pg_temp.fake_week() - 604800, pg_temp.snap('me'), 0, '0.22.7', 1);
  perform pg_temp.as_user(null);
  perform pg_temp.ck('G7 上一周的周号 ⇒ wrong_week', r ->> 'reason' = 'wrong_week', r::text);
end $$;
select pg_temp.set_fake(1, 12);
select pg_temp.ck('G8 周一（休赛）⇒ closed', pg_temp.start('me', 0) ->> 'reason' = 'closed');
select pg_temp.set_fake(6, 12);
select pg_temp.ck('G9 周六（闯关赛）⇒ closed', pg_temp.start('me', 0) ->> 'reason' = 'closed');
select pg_temp.set_fake(7, 20);
select pg_temp.ck('G10 周日 ⇒ closed', pg_temp.start('me', 0) ->> 'reason' = 'closed');
select pg_temp.set_fake(5, 22, 50);
select pg_temp.ck('G11 周五 22:50（收盘前 600 秒封盘）⇒ closed', pg_temp.start('me', 0) ->> 'reason' = 'closed');
select pg_temp.set_fake(5, 22, 49);
select pg_temp.ck('G12 周五 22:49 ⇒ 开着（走到下一道）', pg_temp.start('me', 0) ->> 'reason' = 'no_opponent');
select pg_temp.set_fake(2, 0, 0);
update public.server_clock set offset_sec = offset_sec + 1 where id = 1;
select pg_temp.ck('G13 周二 00:00:01 ⇒ 开着', pg_temp.start('me', 0) ->> 'reason' = 'no_opponent');
update public.referee_config set ranked_any_day = true where id = 1;
select pg_temp.set_fake(1, 12);
select pg_temp.ck('G14 ranked_any_day ⇒ 周一也开', pg_temp.start('me', 0) ->> 'reason' = 'no_opponent');
select pg_temp.set_fake(5, 22, 55);
select pg_temp.ck('G15 ranked_any_day 不放开封盘（周五 22:55 仍 closed）', pg_temp.start('me', 0) ->> 'reason' = 'closed');
update public.referee_config set ranked_any_day = false where id = 1;
select pg_temp.set_fake(3, 12);   -- 假周三 12:00（下面都在这一刻）
select pg_temp.ck('G16 坏阵容（两只统领）⇒ bad_snapshot',
  pg_temp.start('me', 0, '0.22.7', pg_temp.snap('me') || jsonb_build_object('leaders', jsonb_build_array('ninja', 'dice'))) ->> 'reason'
  = 'bad_snapshot');
select pg_temp.ck('G17 第 N 场对不上（新的一周账本 0 场，报 3）⇒ stale + 账本（0 场 / 6 命）',
  pg_temp.start('me', 3) ->> 'reason' = 'stale' and (pg_temp.r('me') -> 'ledger' ->> 'battles')::int = 0
  and (pg_temp.r('me') -> 'ledger' ->> 'hearts')::int = 6, pg_temp.r('me')::text);
insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used)
  values (pg_temp.fake_week(), pg_temp.u('elim'), 9, 3, 0, 1, 3, 9),
         (pg_temp.fake_week(), pg_temp.u('full'), 16, 11, 1, 2, 11, 16);
select pg_temp.ck('G18 余命 0 ⇒ eliminated（不建任务）', pg_temp.start('elim', 9) ->> 'reason' = 'eliminated' and pg_temp.jobs_of('elim') = 0);
select pg_temp.ck('G19 配额 16 用满 ⇒ quota_full（不建任务）', pg_temp.start('full', 16) ->> 'reason' = 'quota_full' and pg_temp.jobs_of('full') = 0);
select pg_temp.ck('G20 被拒的几次一条任务都没建（me）', pg_temp.jobs_of('me') = 0);

-- ═══ P 挑对手 ═══
-- 本周真人快照：h1 / h2 / q_b（陪练号 = 真账号，与真人一样是候选）在 3 场（合格）；h3 在 3 场但分路坏了；old 在 3 场但是上一周；
--   self = 我自己 3 场；h1 另有一份 4 场、h2 一份 2 场（场次不同）；bot1 在 3 场但规则版本 2；一份冒烟数据；一份 schema_ver 1；
--   dirty 那一行列上写 3 场、快照自报 4 场（远端并入的脏数据）⇒ 以快照自己的账为准，不是 3 场的对手。
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps, client_version, rules_ver)
values
  (pg_temp.u('h1'), pg_temp.fake_week(), 3, pg_temp.snap('h1', 3), 2, 5, 0, '0.22.7', 1),
  (pg_temp.u('h2'), pg_temp.fake_week(), 3, pg_temp.snap('h2', 3), 1, 4, 0, '0.22.7', 1),
  (pg_temp.u('h1'), pg_temp.fake_week(), 4, pg_temp.snap('h1', 4), 3, 5, 0, '0.22.7', 1),
  (pg_temp.u('h2'), pg_temp.fake_week(), 2, pg_temp.snap('h2', 2), 1, 5, 0, '0.22.7', 1),
  (pg_temp.u('h3'), pg_temp.fake_week(), 3,
     pg_temp.snap('h3', 3) || jsonb_build_object('lane_assign', jsonb_build_object('top', '[]'::jsonb, 'bottom', '[]'::jsonb)), 0, 6, 0, '0.22.7', 1),
  (pg_temp.u('old'), pg_temp.fake_week() - 604800, 3, pg_temp.snap('old', 3), 0, 6, 0, '0.22.7', 1),
  (pg_temp.u('self'), pg_temp.fake_week(), 3, pg_temp.snap('self', 3), 0, 6, 0, '0.22.7', 1),
  (pg_temp.u('bot1'), pg_temp.fake_week(), 3, pg_temp.snap('bot1', 3), 0, 6, 0, '0.22.7', 2),
  (pg_temp.u('q_b'), pg_temp.fake_week(), 3, pg_temp.snap('q_b', 3), 1, 6, 0, '0.22.7', 1),
  (pg_temp.u('dirty'), pg_temp.fake_week(), 3, pg_temp.snap('dirty', 4), 0, 6, 0, '0.22.7', 1),
  (pg_temp.u('lb1'), pg_temp.fake_week(), 3, pg_temp.snap('lb1', 3) || jsonb_build_object('ghost_id', '__smoke__x'), 0, 6, 0, '0.22.7', 1),
  (pg_temp.u('lb2'), pg_temp.fake_week(), 3, pg_temp.snap('lb2', 3) || jsonb_build_object('schema_ver', 1), 0, 6, 0, '0.22.7', 1);
-- 陪练（内置种子）两份 3 场 + 一份 2 场；机器人 0 / 3 / 30 场各两份
-- ★先上传、再判（同一条语句里的子查询会先于函数调用求值 —— 判据必须在上传之后另起一句）
select pg_temp.keep('pool_seed', public.referee_ranked_pool_load('0.22.7', 1, 'seed', jsonb_build_array(
      jsonb_build_object('battles', 3, 'variant', 0, 'snapshot', pg_temp.snap('seedA', 3) || jsonb_build_object('ghost_id', 'seed_a', 'origin', 'remote')),
      jsonb_build_object('battles', 3, 'variant', 1, 'snapshot', pg_temp.snap('seedB', 3) || jsonb_build_object('ghost_id', 'seed_b')),
      jsonb_build_object('battles', 2, 'variant', 0, 'snapshot', pg_temp.snap('seedC', 2) || jsonb_build_object('ghost_id', 'seed_c')),
      jsonb_build_object('battles', 5, 'variant', 0, 'snapshot', pg_temp.snap('seedD', 3))), true));
select pg_temp.keep('pool_bot', public.referee_ranked_pool_load('0.22.7', 1, 'bot', jsonb_build_array(
      jsonb_build_object('battles', 0, 'variant', 0, 'snapshot', pg_temp.snap('botA', 0) || jsonb_build_object('is_bot', true, 'origin', 'remote')),
      jsonb_build_object('battles', 0, 'variant', 1, 'snapshot', pg_temp.snap('botB', 0) || jsonb_build_object('is_bot', true)),
      jsonb_build_object('battles', 3, 'variant', 0, 'snapshot', pg_temp.snap('botC', 3) || jsonb_build_object('is_bot', true)),
      jsonb_build_object('battles', 3, 'variant', 1, 'snapshot', pg_temp.snap('botD', 3) || jsonb_build_object('is_bot', true)),
      jsonb_build_object('battles', 5, 'variant', 0, 'snapshot', pg_temp.snap('botG', 5) || jsonb_build_object('is_bot', true)),
      jsonb_build_object('battles', 30, 'variant', 0, 'snapshot', pg_temp.snap('botE', 30) || jsonb_build_object('is_bot', true)),
      jsonb_build_object('battles', 30, 'variant', 1, 'snapshot', pg_temp.snap('botF', 30) || jsonb_build_object('is_bot', true))), true));
select pg_temp.ck('P0 池子上传：陪练 3 行收、场次对不上的 1 行拒收；机器人 7 行全收；origin 一律摘掉',
  (pg_temp.r('pool_seed') ->> 'rejected')::int = 1 and (pg_temp.r('pool_seed') ->> 'total')::int = 3
  and (pg_temp.r('pool_bot') ->> 'total')::int = 7 and (pg_temp.r('pool_bot') ->> 'rejected')::int = 0
  and (select count(*) from public.ranked_pool where kind = 'seed' and rules_ver = 1) = 3
  and not exists (select 1 from public.ranked_pool where snapshot ? 'origin'),
  pg_temp.r('pool_seed')::text || ' · ' || pg_temp.r('pool_bot')::text);
do $$
declare i int; pk jsonb; seen text[] := '{}'; bad text[] := '{}'; ok_set text[];
begin
  ok_set := array[format('acct:%s:b3', pg_temp.u('h1')), format('acct:%s:b3', pg_temp.u('h2')),
                   format('acct:%s:b3', pg_temp.u('q_b')), 'seed:1:3:0', 'seed:1:3:1'];
  for i in 1..300 loop
    pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 3, 1, '{}');
    if pk is null or not ((pk ->> 'opp') = any(ok_set)) then
      bad := bad || coalesce(pk ->> 'opp', 'null');
    elsif not ((pk ->> 'opp') = any(seen)) then
      seen := seen || (pk ->> 'opp');
    end if;
  end loop;
  perform pg_temp.ck('P1 300 次只挑到「同场次 3 / 本周 / 规则 1 / 合格 / 不是自己」的五份（分母 5 份候选）',
    coalesce(array_length(bad, 1), 0) = 0, array_to_string(bad, ','));
  perform pg_temp.ck('P2 五份候选每一份都被抽到过（真人、陪练号、内置陪练放一起等概率抽，没有只取最新一份）',
    coalesce(array_length(seen, 1), 0) = 5, array_to_string(seen, ','));
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 3, 1,
    array[format('acct:%s:b3', pg_temp.u('h1')), format('acct:%s:b3', pg_temp.u('h2')), format('acct:%s:b3', pg_temp.u('q_b')),
          'seed:1:3:0']);
  perform pg_temp.ck('P3 排除了四份 ⇒ 只剩内置陪练 seed:1:3:1', pk ->> 'opp' = 'seed:1:3:1' and pk ->> 'pick' = 'seed'
    and not (pk ? 'account') and not ((pk -> 'snap') ? 'origin'), pk::text);
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 3, 1,
    array[format('acct:%s:b3', pg_temp.u('h2')), format('acct:%s:b3', pg_temp.u('q_b')), 'seed:1:3:0', 'seed:1:3:1']);
  perform pg_temp.ck('P4 只剩真人 h1 ⇒ 挑到它、带 account', pk ->> 'opp' = format('acct:%s:b3', pg_temp.u('h1'))
    and pk ->> 'pick' = 'human' and (pk ->> 'account')::uuid = pg_temp.u('h1'), pk::text);
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 3, 1,
    array[format('acct:%s:b3', pg_temp.u('h1')), format('acct:%s:b3', pg_temp.u('h2')), format('acct:%s:b3', pg_temp.u('q_b')),
          'seed:1:3:0', 'seed:1:3:1']);
  perform pg_temp.ck('P5 同场次一份都不剩 ⇒ 机器人同场次那一格（bot:1:3:*，不跨场次、不拿 4 场的真人）',
    pk ->> 'pick' = 'bot' and pk ->> 'opp' like 'bot:1:3:%' and (pk -> 'snap' ->> 'season_total_battles')::int = 3
    and not ((pk -> 'snap') ? 'origin'), pk::text);
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 1, 1, '{}');
  perform pg_temp.ck('P6 机器人池缺这个场次那一格（本脚本只放了 0/3/5/30；正式池 0..30 每格都有）⇒ null ⇒ 开战回 no_opponent',
    pk is null, coalesce(pk::text, 'null'));
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 45, 1, '{}');
  perform pg_temp.ck('P7 45 场超出池子 ⇒ 用最大那一格（30）、场次改成 45', pk ->> 'opp' like 'bot:1:30:%'
    and (pk -> 'snap' ->> 'season_total_battles')::int = 45, coalesce(pk::text, 'null'));
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.fake_week(), 3, 3, '{}');
  perform pg_temp.ck('P8 规则版本 3 ⇒ 真人 / 陪练 / 机器人都没有 ⇒ null', pk is null, coalesce(pk::text, 'null'));
end $$;

-- ═══ S 建任务 ═══
-- me 本周第 0 场：0 场那一格没有真人也没有陪练 ⇒ 机器人 0 场。交上去的快照自报 9 场 / 99 胜（改过的客户端）⇒ 服务端改成账本的数
select pg_temp.ck('S1 第 0 场开战 ok、对手卡片只有 profile / leaders', (pg_temp.start('me', 0, '0.22.7', pg_temp.snap('me', 9)) ->> 'ok')::boolean
  and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('me') -> 'opp') k) = array['leaders', 'profile'], pg_temp.r('me')::text);
select pg_temp.ck('S2 任务 kind = ranked、match_key、种子在范围、b_account 空（机器人）、meta 记 opp / pick / battles0 / rules_ver',
  exists (select 1 from public.referee_jobs j where j.job_id = (pg_temp.r('me') ->> 'job_id')::bigint and j.kind = 'ranked'
    and j.match_key = format('ranked:%s:%s:0', pg_temp.fake_week(), pg_temp.u('me')) and j.seed between 1 and 9007199254740991
    and j.b_account is null and j.meta ->> 'pick' = 'bot' and j.meta ->> 'opp' like 'bot:1:0:%'
    and (j.meta ->> 'battles0')::int = 0 and (j.meta ->> 'rules_ver')::int = 1 and j.client_version = '0.22.7'));
select pg_temp.ck('S3 A 快照里的账本数 = 服务端的（快照自报 9 场 / 99 胜 / 99 横扫被改成 0）、ghost_id 场次后缀 _b9 → _b0',
  exists (select 1 from public.referee_jobs j where j.job_id = (pg_temp.r('me') ->> 'job_id')::bigint
    and (j.a_snapshot ->> 'season_total_battles')::int = 0 and (j.a_snapshot ->> 'season_wins')::int = 0
    and (j.a_snapshot ->> 'hearts')::int = 6 and (j.a_snapshot ->> 'season_sweeps')::int = 0
    and (j.a_snapshot ->> 'season_eggs_killed')::int = 0 and j.a_snapshot ->> 'ghost_id' like '%\_b0'));
select pg_temp.ck('S4 账本落了一行（0 场 / 6 命 / 不是补种的）', exists (select 1 from public.ranked_records r
  where r.season_week = pg_temp.fake_week() and r.account_id = pg_temp.u('me') and r.battles = 0 and r.hearts = 6 and r.seeded is null));
do $$ declare j1 bigint; r jsonb; begin
  j1 := (pg_temp.r('me') ->> 'job_id')::bigint;
  r := pg_temp.start('me', 0);
  perform pg_temp.ck('S5 有一场在算 ⇒ 回同一场（in_flight），不新建', (r ->> 'job_id')::bigint = j1 and (r ->> 'in_flight')::boolean
    and pg_temp.jobs_of('me') = 1, r::text);
  r := pg_temp.start('me', 5);
  perform pg_temp.ck('S6 在算时报别的场次也回那一场（不出 stale）', (r ->> 'job_id')::bigint = j1, r::text);
end $$;
-- 真人对手：ret 有账本 3 场（同 h1 / h2 / q_b / self / 内置陪练 那一格；self 对 ret 来说是别人）
insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used)
  values (pg_temp.fake_week(), pg_temp.u('ret'), 3, 2, 5, 1, 2, 3);
do $$ declare r jsonb; j record; seed0 bigint; opp0 text; r2 jsonb; begin
  r := pg_temp.start('ret', 3);
  select * into j from public.referee_jobs where job_id = (r ->> 'job_id')::bigint;
  perform pg_temp.ck('S7 第 3 场挑到同场次的一份（真人 ⇒ b_account = 主人；陪练 ⇒ 空）',
    (r ->> 'ok')::boolean and j.meta ->> 'opp' in (format('acct:%s:b3', pg_temp.u('h1')), format('acct:%s:b3', pg_temp.u('h2')),
                             format('acct:%s:b3', pg_temp.u('q_b')), format('acct:%s:b3', pg_temp.u('self')),
                             'seed:1:3:0', 'seed:1:3:1')
    and ((j.meta ->> 'pick' = 'human' and j.b_account is not null) or (j.meta ->> 'pick' = 'seed' and j.b_account is null)), r::text);
  -- 一般失败（裁判机超时之类）⇒ 重交：同一场、种子不换、对手不换
  seed0 := j.seed; opp0 := j.meta ->> 'opp';
  update public.referee_jobs set status = 'failed', error = 'rc=1 timeout' where job_id = j.job_id;
  r2 := pg_temp.start('ret', 3);
  select * into j from public.referee_jobs where job_id = j.job_id;
  perform pg_temp.ck('S8 算失败重交 ⇒ 同一场、retry、种子 / 对手不换、回到 pending', (r2 ->> 'job_id')::bigint = j.job_id
    and (r2 ->> 'retry')::boolean and j.seed = seed0 and j.meta ->> 'opp' = opp0 and j.status = 'pending', r2::text);
  -- 对手快照坏了 ⇒ 重交时换一个（排除旧的）
  update public.referee_jobs set status = 'failed', error = 'b_bad_snapshot' where job_id = j.job_id;
  r2 := pg_temp.start('ret', 3);
  select * into j from public.referee_jobs where job_id = j.job_id;
  perform pg_temp.ck('S9 b_bad_snapshot ⇒ 换对手（opp_prev 记着旧的、新的不等于旧的）、种子不换',
    j.meta ->> 'opp' <> opp0 and (j.meta -> 'opp_prev') ? opp0 and j.seed = seed0 and j.status = 'pending', j.meta::text);
end $$;

-- ═══ R 结算表 ═══
-- ★门禁 tests/verify_ranked_server_rules.gd 逐行读下面这张表（两条标记之间、每行一个括号），拿本机 RealtimeBattle3DScene._settle_season
--   真跑一遍、逐格对账；本段拿 referee_complete 跑同一张表。改这张表两边都要过 = 两边是同一套规则。
-- 列：id, 命0, 胜0, 横扫0, 碎蛋0, 场次0(= 配额0), 赢, 上路, 下路, 终极, 战斗内铸币 → 命, 胜, 横扫, 碎蛋, 场次, 配额, 这一局发的币
create temp table _cases (id text primary key, h0 int, w0 int, s0 int, e0 int, b0 int, won boolean, top text, bottom text,
  fin text, coins int, eh int, ew int, es int, ee int, eb int, eu int, er int);
-- >>> RANKED_SETTLE_CASES
insert into _cases values
  ('c1', 6, 0, 0, 0, 0, true, 'left', 'left', '', 0, 6, 1, 1, 1, 1, 1, 20),
  ('c2', 6, 0, 0, 0, 0, false, 'right', 'right', '', 0, 5, 0, 0, 0, 1, 1, 15),
  ('c3', 4, 3, 1, 3, 5, true, 'left', 'right', 'left', 0, 4, 4, 1, 4, 6, 6, 22),
  ('c4', 3, 5, 2, 5, 8, true, 'left', 'left', '', 7, 3, 6, 3, 6, 9, 9, 30),
  ('c5', 1, 9, 4, 9, 14, false, 'right', 'left', 'right', 5, 0, 9, 4, 9, 15, 15, 0),
  ('c6', 2, 7, 0, 7, 10, false, 'left', 'right', 'right', 4, 1, 7, 0, 7, 11, 11, 23),
  ('c7', 6, 2, 0, 2, 2, true, 'left', '', '', 0, 6, 3, 0, 3, 3, 3, 20),
  ('c8', 5, 4, 1, 6, 6, true, 'right', 'right', '', 0, 5, 5, 1, 7, 7, 7, 21),
  ('c9', 2, 10, 3, 10, 12, true, 'left', 'left', '', 12, 2, 11, 4, 11, 13, 13, 36),
  ('c10', 6, 0, 0, 0, 3, false, 'right', 'right', '', 3, 5, 0, 0, 0, 4, 4, 18);
-- <<< RANKED_SETTLE_CASES
do $$
declare c record; jid bigint; r jsonb; rr record; st jsonb; n int := 0; led jsonb;
begin
  for c in select * from _cases order by id loop
    insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used)
      values (pg_temp.fake_week(), pg_temp.u(c.id), c.b0, c.w0, c.h0, c.s0, c.e0, c.b0);
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
        meta, status, claimed_by, claimed_at, attempts)
      values ('ranked', format('ranked:%s:%s:%s', pg_temp.fake_week(), pg_temp.u(c.id), c.b0), pg_temp.fake_week(), '0.22.7',
              public.referee_new_seed(), pg_temp.u(c.id), pg_temp.snap(c.id, c.b0), pg_temp.snap('foe', c.b0),
              jsonb_build_object('rules_ver', 1, 'opp', 'bot:1:0:0'), 'claimed', 'chk', now(), 1)
      returning job_id into jid;
    r := public.referee_complete(jid, 'chk', pg_temp.result(jid, c.won, c.top, c.bottom, c.fin, c.coins));
    select * into rr from public.ranked_records where season_week = pg_temp.fake_week() and account_id = pg_temp.u(c.id);
    select result -> 'ledger' -> 'ranked' into led from public.referee_jobs where job_id = jid;
    perform pg_temp.ck(format('R %s 命 %s→%s 胜 %s→%s 横扫 %s→%s 碎蛋 %s→%s 场次 %s→%s 配额 →%s 币 %s', c.id, c.h0, c.eh, c.w0, c.ew,
        c.s0, c.es, c.e0, c.ee, c.b0, c.eb, c.eu, c.er),
      (r ->> 'ok')::boolean and rr.hearts = c.eh and rr.wins = c.ew and rr.sweeps = c.es and rr.eggs = c.ee and rr.battles = c.eb
      and rr.used = c.eu and rr.coins = c.er and (led ->> 'reward')::int = c.er and (led ->> 'hearts')::int = c.eh
      and (led ->> 'battles')::int = c.eb,
      format('账本 %s/%s/%s/%s/%s/%s/%s · 结果 %s · %s', rr.hearts, rr.wins, rr.sweeps, rr.eggs, rr.battles, rr.used, rr.coins, led, r));
    n := n + 1;
    -- 客户端查这一局：kind / ranked / seed
    perform pg_temp.as_user(pg_temp.u(c.id));
    st := public.referee_job_status(jid);
    perform pg_temp.as_user(null);
    if c.id = 'c4' then
      perform pg_temp.ck('R-status 算完的积分赛局回 kind = ranked、ranked（账本快照 + reward + sweep）、seed、coins = 结果单的铸币',
        st ->> 'kind' = 'ranked' and (st -> 'ranked' ->> 'reward')::int = c.er and (st -> 'ranked' ->> 'sweep')::boolean
        and (st ->> 'seed')::bigint > 0 and (st ->> 'coins')::int = c.coins and (st ->> 'won')::boolean = c.won
        and st ? 'chest' and st ? 'incense', st::text);
    end if;
  end loop;
  perform pg_temp.ck('R 分母：结算表 10 行都跑了', n = 10, n::text);
end $$;
do $$ declare st jsonb; begin
  perform pg_temp.as_user(pg_temp.u('ret'));
  st := public.referee_job_status((pg_temp.r('ret') ->> 'job_id')::bigint);
  perform pg_temp.as_user(null);
  perform pg_temp.ck('R-status2 pending ⇒ kind = ranked、没有 seed、没有 ranked', st ->> 'kind' = 'ranked' and not (st ? 'seed')
    and not (st ? 'ranked') and st ->> 'status' = 'pending', st::text);
end $$;

-- ═══ K 写回副作用 ═══
select pg_temp.ck('K1 ghosts：c4 那一局之后 9 场那一行，数是服务端的（6 胜 / 3 命 / 3 横扫），快照场次 9、ghost_id 后缀 _b9、宝箱 / 香火取结果单',
  exists (select 1 from public.ghosts g where g.account_id = pg_temp.u('c4') and g.season_week = pg_temp.fake_week() and g.battles = 9
    and g.season_wins = 6 and g.hearts = 3 and g.season_sweeps = 3 and (g.snapshot ->> 'season_total_battles')::int = 9
    and (g.snapshot ->> 'season_wins')::int = 6 and (g.snapshot ->> 'hearts')::int = 3 and (g.snapshot ->> 'season_eggs_killed')::int = 6
    and g.snapshot ->> 'ghost_id' like '%\_b9' and g.snapshot -> 'profile' ->> 'id' like '%\_b9'
    and (g.snapshot ->> 'chest_treasure_value')::numeric = 41.5 and (g.snapshot ->> 'incense_marks')::int = 2
    and g.rules_ver = 1 and g.client_version = '0.22.7'));
select pg_temp.ck('K2 matches：phase ranked、right_account 空、快照摘掉 ghost_id、result 有 ranked',
  exists (select 1 from public.matches m join public.referee_jobs j on j.match_id = m.match_id
    where j.a_account = pg_temp.u('c4') and m.phase = 'ranked' and m.right_account is null and m.left_account = pg_temp.u('c4')
      and not (m.left_snapshot ? 'ghost_id') and (m.result -> 'ranked' ->> 'battles')::int = 9 and m.replay = 'QUJDRA=='));
select pg_temp.ck('K3 积分赛局一条都没进 gauntlet_records（原来的 elsif a_account is not null 会把它当闯关局记）',
  not exists (select 1 from public.gauntlet_records r join _u on _u.id = r.account_id where _u.k like 'c%'));
do $$ declare jid bigint; r jsonb; begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
      meta, status, claimed_by, claimed_at, attempts)
    values ('gauntlet', 'chk-g', pg_temp.fake_week(), '0.22.7', 7, pg_temp.u('g'), pg_temp.snap('g'), pg_temp.snap('foe'),
            jsonb_build_object('rules_ver', 1), 'claimed', 'chk', now(), 1) returning job_id into jid;
  r := public.referee_complete(jid, 'chk', pg_temp.result(jid, true, 'left', 'left', '', 3));
  perform pg_temp.ck('K4 闯关局写回照旧：gauntlet_records 1-0、gauntlet_ghosts 一行、不进积分赛账本',
    (r ->> 'ok')::boolean and exists (select 1 from public.gauntlet_records where account_id = pg_temp.u('g') and gw = 1 and gl = 0)
    and exists (select 1 from public.gauntlet_ghosts where account_id = pg_temp.u('g'))
    and not exists (select 1 from public.ranked_records where account_id = pg_temp.u('g')), r::text);
end $$;

-- ═══ L 周榜 ═══
-- lb1：快照自报 15 胜，但账本只有 2 胜 ⇒ 按 2 胜；lb2：没账本，快照 5 胜 ⇒ 按 5 胜
delete from public.ghosts where account_id in (pg_temp.u('lb1'), pg_temp.u('lb2'));
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps, client_version, rules_ver)
values (pg_temp.u('lb1'), pg_temp.fake_week(), 12, pg_temp.snap('lb1', 12), 15, 6, 9, '0.22.7', 1),
       (pg_temp.u('lb2'), pg_temp.fake_week(), 8, pg_temp.snap('lb2', 8), 5, 3, 1, '0.22.7', 1);
insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used)
  values (pg_temp.fake_week(), pg_temp.u('lb1'), 12, 2, 1, 0, 2, 12);
do $$ declare p jsonb; a jsonb; b jsonb; r jsonb; begin
  perform pg_temp.as_user(pg_temp.u('lb1'));
  p := public.week_leaderboard_page(pg_temp.fake_week(), 0, 100);
  r := public.week_leaderboard(pg_temp.fake_week(), 100);
  perform pg_temp.as_user(null);
  select x into a from jsonb_array_elements(p -> 'rows') x where (x ->> 'account_id')::uuid = pg_temp.u('lb1');
  select x into b from jsonb_array_elements(p -> 'rows') x where (x ->> 'account_id')::uuid = pg_temp.u('lb2');
  perform pg_temp.ck('L1 有账本 ⇒ 按账本（2 胜 / 1 命 / 0 横扫 / 12 场），快照自报的 15 胜不算', (a ->> 'wins')::int = 2
    and (a ->> 'hearts')::int = 1 and (a ->> 'sweeps')::int = 0 and (a ->> 'battles')::int = 12 and (p -> 'me' ->> 'wins')::int = 2, a::text);
  perform pg_temp.ck('L2 没账本 ⇒ 照旧按快照（5 胜 / 3 命）', (b ->> 'wins')::int = 5 and (b ->> 'hearts')::int = 3, b::text);
  perform pg_temp.ck('L3 名次跟着账本走：lb2（5 胜）排在 lb1（2 胜）前面', (b ->> 'rank')::int < (a ->> 'rank')::int, p::text);
  select x into a from jsonb_array_elements(r -> 'rows') x where (x ->> 'account_id')::uuid = pg_temp.u('lb1');
  perform pg_temp.ck('L4 旧接口 week_leaderboard 同一口径', (a ->> 'wins')::int = 2 and (r -> 'me' ->> 'wins')::int = 2, r::text);
end $$;

-- ═══ M 切换那一周：账从旧自报快照接 ═══
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps, client_version, rules_ver)
values (pg_temp.u('leg'), pg_temp.fake_week(), 5, pg_temp.snap('leg', 5) || jsonb_build_object('season_eggs_killed', 4), 4, 4, 1, '0.22.6', 1),
       (pg_temp.u('leg'), pg_temp.fake_week(), 4, pg_temp.snap('leg', 4), 3, 4, 1, '0.22.6', 1);
select pg_temp.ck('M1 报 0 场 ⇒ stale，账本 = 旧快照最后一份（5 场 / 4 胜 / 4 命 / 1 横扫 / 4 碎蛋 / 配额 5）',
  pg_temp.start('leg', 0) ->> 'reason' = 'stale' and (pg_temp.r('leg') -> 'ledger' ->> 'battles')::int = 5
  and (pg_temp.r('leg') -> 'ledger' ->> 'wins')::int = 4 and (pg_temp.r('leg') -> 'ledger' ->> 'hearts')::int = 4
  and (pg_temp.r('leg') -> 'ledger' ->> 'eggs')::int = 4 and (pg_temp.r('leg') -> 'ledger' ->> 'used')::int = 5
  and not exists (select 1 from public.ranked_records where account_id = pg_temp.u('leg')), pg_temp.r('leg')::text);
select pg_temp.start('leg', 5);
select pg_temp.ck('M2 报 5 场 ⇒ 开战，账本落行 seeded = ghosts',
  (pg_temp.r('leg') ->> 'ok')::boolean and exists (select 1 from public.ranked_records
    where account_id = pg_temp.u('leg') and battles = 5 and wins = 4 and hearts = 4 and seeded = 'ghosts'), pg_temp.r('leg')::text);
do $$ declare r jsonb; begin
  perform pg_temp.as_user(pg_temp.u('leg'));
  r := public.referee_ranked_ledger(pg_temp.fake_week());
  perform pg_temp.as_user(null);
  perform pg_temp.ck('M3 referee_ranked_ledger 读自己的账（落了行之后 row = true）', (r ->> 'ok')::boolean
    and (r -> 'ledger' ->> 'battles')::int = 5 and (r -> 'ledger' ->> 'row')::boolean, r::text);
end $$;
select pg_temp.ck('M4 不登录读账 ⇒ not_signed_in', public.referee_ranked_ledger(pg_temp.fake_week()) ->> 'reason' = 'not_signed_in');

-- ═══ Q 领活顺序 ═══
update public.referee_jobs set status = 'done' where status in ('pending', 'claimed');
do $$ declare jb bigint; jh bigint; c jsonb; begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, meta, created_at)
    values ('ranked', 'chk-qb', pg_temp.fake_week(), '0.22.7', 11, pg_temp.u('q_b'), pg_temp.snap('q_b'), pg_temp.snap('foe'), '{}',
            now() - interval '30 seconds') returning job_id into jb;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, meta, created_at)
    values ('ranked', 'chk-qh', pg_temp.fake_week(), '0.22.7', 12, pg_temp.u('q_h'), pg_temp.snap('q_h'), pg_temp.snap('foe'), '{}',
            now() - interval '5 seconds') returning job_id into jh;
  c := public.referee_claim('chk-w', array['0.22.7'], 1);
  perform pg_temp.ck('Q1 陪练号的积分赛局早到 25 秒，仍先领真人那一局', (c -> 0 ->> 'job_id')::bigint = jh and c -> 0 ->> 'mode' = 'ranked', c::text);
  c := public.referee_claim('chk-w', array['0.22.7'], 1);
  perform pg_temp.ck('Q2 下一次领到陪练号那一局（不会饿死）', (c -> 0 ->> 'job_id')::bigint = jb, c::text);
end $$;
do $$ declare j1 bigint; j2 bigint; c jsonb; begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, meta, created_at)
    values ('gauntlet', 'chk-g1', pg_temp.fake_week(), '0.22.7', 13, pg_temp.u('q_b'), pg_temp.snap('q_b'), pg_temp.snap('foe'), '{}',
            now() - interval '20 seconds') returning job_id into j1;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, meta, created_at)
    values ('gauntlet', 'chk-g2', pg_temp.fake_week(), '0.22.7', 14, pg_temp.u('q_h'), pg_temp.snap('q_h'), pg_temp.snap('foe'), '{}',
            now() - interval '2 seconds') returning job_id into j2;
  c := public.referee_claim('chk-w', array['0.22.7'], 2);
  perform pg_temp.ck('Q3 闯关局（陪练号也一样）仍按时间先后领', (c -> 0 ->> 'job_id')::bigint = j1 and (c -> 1 ->> 'job_id')::bigint = j2, c::text);
end $$;

-- ═══ W 写权限 ═══
-- 沙盒没有 Supabase 的默认表授权（正式库 public 表对 anon / authenticated 默认全开、只靠行级策略拦）⇒ 这里补上同样的授权（随事务回滚）
grant select, insert, update on public.ghosts to authenticated;
grant select, insert on public.matches to authenticated;
do $$
declare ok_g boolean := false; ok_m boolean := false; ok_f boolean := false; e text := ''; uw uuid; wk bigint;
begin
  uw := pg_temp.u('w');
  wk := pg_temp.fake_week();
  -- 开关开（默认）⇒ 客户端能写自己的 ghosts、积分赛 matches（与改之前一样）
  perform pg_temp.as_user(uw);
  set local role authenticated;
  begin
    insert into public.ghosts (account_id, season_week, battles, snapshot, client_version)
      values (uw, wk, 1, '{}'::jsonb, '0.22.7');
    insert into public.matches (season_week, phase, left_account, seed, left_snapshot, right_snapshot, result, client_version)
      values (wk, 'ranked', uw, 5, '{}', '{}', '{}', '0.22.7');
    ok_g := true;
  exception when others then e := sqlerrm;
  end;
  reset role;
  perform pg_temp.as_user(null);
  perform pg_temp.ck('W1 ranked_client_write 开 ⇒ 客户端照旧写得进 ghosts / 积分赛 matches（迁移上了行为不变）', ok_g, e);
  update public.referee_config set ranked_client_write = false where id = 1;
  perform pg_temp.as_user(uw);
  set local role authenticated;
  ok_g := false;
  begin
    insert into public.ghosts (account_id, season_week, battles, snapshot, client_version)
      values (uw, wk, 2, '{}'::jsonb, '0.22.7');
    ok_g := true;
  exception when others then e := sqlerrm;
  end;
  begin
    update public.ghosts set season_wins = 16 where account_id = uw;
    if found then ok_g := true; end if;
  exception when others then e := e || ' / ' || sqlerrm;
  end;
  begin
    insert into public.matches (season_week, phase, left_account, seed, left_snapshot, right_snapshot, result, client_version)
      values (wk, 'ranked', uw, 6, '{}', '{}', '{"won": true}', '0.22.7');
    ok_m := true;
  exception when others then e := e || ' / ' || sqlerrm;
  end;
  begin
    insert into public.matches (season_week, phase, left_account, seed, left_snapshot, right_snapshot, result, client_version)
      values (wk, 'finals', uw, 7, '{}', '{}', '{}', '0.22.7');
    ok_f := true;
  exception when others then e := e || ' / ' || sqlerrm;
  end;
  reset role;
  perform pg_temp.as_user(null);
  perform pg_temp.ck('W2 关掉 ⇒ 客户端 insert / update ghosts 都写不进（自报 16 胜改不上去）', not ok_g
    and (select season_wins from public.ghosts where account_id = uw and battles = 1) = 0, e);
  perform pg_temp.ck('W3 关掉 ⇒ 客户端 insert 积分赛 matches 写不进', not ok_m, e);
  perform pg_temp.ck('W4 关掉 ⇒ 周日录像（phase finals）照旧写得进（只收积分赛）', ok_f, e);
  update public.referee_config set ranked_client_write = true where id = 1;
end $$;
-- 服务端照样写得进（security definer）：上面 R 段的 ghosts 写入就是在 ranked_client_write = true 时做的；关着时再写一次
update public.referee_config set ranked_client_write = false where id = 1;
do $$ declare jid bigint; r jsonb; begin
  insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used)
    values (pg_temp.fake_week(), pg_temp.u('nop'), 0, 0, 6, 0, 0, 0);
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
      meta, status, claimed_by, claimed_at, attempts)
    values ('ranked', 'chk-nop', pg_temp.fake_week(), '0.22.7', 21, pg_temp.u('nop'), pg_temp.snap('nop', 0), pg_temp.snap('foe'),
            jsonb_build_object('rules_ver', 1), 'claimed', 'chk', now(), 1) returning job_id into jid;
  r := public.referee_complete(jid, 'chk', pg_temp.result(jid, true, 'left', 'left', '', 0));
  perform pg_temp.ck('W5 客户端写权限关着，裁判写回照样落 ghosts / matches / 账本', (r ->> 'ok')::boolean
    and exists (select 1 from public.ghosts where account_id = pg_temp.u('nop') and battles = 1 and season_wins = 1)
    and exists (select 1 from public.matches where left_account = pg_temp.u('nop') and phase = 'ranked'), r::text);
end $$;
update public.referee_config set ranked_client_write = true where id = 1;

-- ═══ F 开关 / 权限 ═══
select pg_temp.ck('F1 referee_flags 多回 ranked_on（当前 true）且原四个键都在',
  (public.referee_flags() ->> 'ranked_on')::boolean and public.referee_flags() ?& array['finals_on', 'gauntlet_on', 'stream_on', 'stream_version']);
select pg_temp.ck('F2 开战 / 读账：authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.referee_ranked_start(bigint, jsonb, int, text, int)', 'execute')
  and not has_function_privilege('anon', 'public.referee_ranked_start(bigint, jsonb, int, text, int)', 'execute')
  and has_function_privilege('authenticated', 'public.referee_ranked_ledger(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.referee_ranked_ledger(bigint)', 'execute'));
select pg_temp.ck('F3 池子上传 / 挑对手 / 账本补种只给 service_role / 内部（客户端两个角色都调不了）',
  has_function_privilege('service_role', 'public.referee_ranked_pool_load(text, int, text, jsonb, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_ranked_pool_load(text, int, text, jsonb, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_ranked_pick(uuid, bigint, int, int, text[])', 'execute')
  and not has_function_privilege('anon', 'public.referee_ranked_pick(uuid, bigint, int, int, text[])', 'execute')
  and not has_function_privilege('authenticated', 'public.ranked_ledger_peek(uuid, bigint)', 'execute'));
select pg_temp.ck('F4 账本表 / 池子表开了行级安全；客户端只有账本「读自己」一条策略',
  (select relrowsecurity from pg_class where oid = 'public.ranked_records'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.ranked_pool'::regclass)
  and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'ranked_records') = 1
  and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'ranked_pool') = 0);
select pg_temp.ck('F5 referee_jobs.kind 认 ranked、不认别的', exists (select 1 from pg_constraint where conname = 'referee_jobs_kind_check'
  and pg_get_constraintdef(oid) like '%ranked%'));
do $$ declare ok boolean := false; begin
  begin
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_snapshot, b_snapshot)
      values ('casual', 'chk-casual', 1, '0.22.7', 1, '{}', '{}');
    ok := true;
  exception when check_violation then ok := false;
  end;
  perform pg_temp.ck('F6 kind = casual ⇒ 约束拒', not ok);
end $$;

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
