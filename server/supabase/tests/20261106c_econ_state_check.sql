-- 20261106c 局外经济记账 · 服务器重放结果 + 开局比对 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261106c_econ_state
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、插的行一个都不留。
-- 假时间照 20261101d 检查脚本（本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原）。
-- 判据：
--   E 开关：econ_on 关 ⇒ econ_check 恒 null、积分赛开局照旧走到下一道（no_opponent）；开 ⇒ 一条流水都没有 = 本周开局（全空）
--   P 追没追上：有流水没重放 ⇒ econ_pending（回 have / need）、开局不建任务；领活只给「到第一条没传回的种子行之前」那一截、每条带序号
--   M 比对：重放结果对得上 ⇒ 开局走到下一道；身上装备（星级 / 件数）/ 大轮等级 / 小木斧 / 宝箱 / 香火 / 小将装备 任一对不上 ⇒ econ_mismatch（what 说是哪一块）；
--     装备实例上的 chg、星级写成 1.0 不算不同
--   W 回写只往前走（seen 小的不覆盖大的）
--   I 不合法：重放判第 N 条不合法 ⇒ econ_invalid（at N）；只能截在 N（别的序号 / 别人 ⇒ not_invalid）；截了之后流水剩 N 条、状态清掉不合法标记
--   B 两个开局函数里比对的位置：场次核对之后、建任务 / 进队列之前
--   R 行级策略 / 权限：别人读不到我的 econ_state；领活 / 回写只给 service_role；econ_check 不对外；截断只给 authenticated
--   D 标脏：流水一动就脏；回写追上就干净；算的时候又来了新流水仍是脏的；领活不扫干净的号
--   T 尾部种子行没传回（闪退，R9）⇒ 不算没追上，能开局
--   F 事实：ranked_records 那一行；裁判局 A 方 / 配对局 B 方（胜负取反、取 coins_b / chest_b）；旧路任务的 b_account 不算；没完成的不算；别周不算；领活带上
--   C ★真快照契约：verify_econ_server_check 用真结算入口走出来的快照 + 重放结果（样本嵌在本文件里，门禁比它 = 现在代码算的）⇒ 对得上；改一件就拒
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('me'), ('other'), ('real');
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
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
create or replace function pg_temp.wk() returns bigint language sql as $$ select public.econ_week_now() $$;
-- 合法阵容快照（同 20261101d：三统领、分路齐；ninja 身上一件 p2eq_001★1；大轮 3 级）
create or replace function pg_temp.snap(p_name text, p_battles int default 0) returns jsonb language sql as $$
  select jsonb_build_object('schema_ver', 2, 'ghost_id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
    'profile', jsonb_build_object('name', p_name, 'avatar', 'ninja', 'id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
                                  'tag', 'chk-' || p_name),
    'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')),
    'equipped', jsonb_build_object('ninja', jsonb_build_array(jsonb_build_object('id', 'p2eq_001', 'star', 1))),
    'pet_levels', jsonb_build_object('ninja', 1, 'dice', 1, 'pirate', 1),
    'season_total_battles', p_battles, 'season_level', 3, 'season_wins', 0, 'hearts', 6, 'season_sweeps', 0,
    'season_eggs_killed', 0)
$$;
create or replace function pg_temp.start(p_k text, p_snap jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.as_user(pg_temp.u(p_k));
  r := public.referee_ranked_start(pg_temp.wk(), p_snap, 0, '0.22.7', 1);
  perform pg_temp.as_user(null);
  return r;
end $$;
create or replace function pg_temp.jobs_of(p_k text) returns int language sql as $$
  select count(*)::int from public.referee_jobs where a_account = pg_temp.u(p_k) and kind = 'ranked'
$$;
-- 重放结果(与 EconReplay.run 同形): 大轮 3 级、ninja 身上 p2eq_001★1、斧头 / 宝箱 / 香火全 0
create or replace function pg_temp.result(p_bad int default -1) returns jsonb language sql as $$
  select jsonb_build_object('upto', 4, 'bad_at', p_bad, 'why', case when p_bad >= 0 then 'apply:buy:empty' else '' end,
    'assets', jsonb_build_object('lv', 3, 'worn', jsonb_build_object('ninja', jsonb_build_array(jsonb_build_object('id', 'p2eq_001', 'star', 1))),
                                 'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
                                 'minions', '[]'::jsonb, 'axe', jsonb_build_array(0, 0, 0, '', 0)),
    'progress', jsonb_build_object('cv', 0, 'cw', '[]'::jsonb, 'im', 0, 'ic', 0), 'income', '{}'::jsonb, 'fp', 'x')
$$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
update public.service_status set min_client_version = '0.0.0' where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
update public.referee_config set ranked_on = true, ranked_any_day = false, econ_on = false where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('0.22.7', true, 1)
  on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;
select pg_temp.set_fake(2, 12);   -- 假周二 12:00(积分赛开着)
-- 积分赛池子清空(本事务内)⇒ 过了比对的开局一律走到 no_opponent(不建任务), 拿它当「比对这一关过了」的信号
delete from public.ghosts where season_week = pg_temp.wk();

-- ── E 开关 ──
select pg_temp.ck('E1 开关关 ⇒ econ_check 恒 null(快照大轮 3 级、本周一条流水都没有也不管)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) is null);
select pg_temp.ck('E2 开关关 ⇒ 积分赛开局照旧走到下一道(no_opponent)', pg_temp.start('me', pg_temp.snap('me')) ->> 'reason' = 'no_opponent',
  pg_temp.start('me', pg_temp.snap('me'))::text);
update public.referee_config set econ_on = true where id = 1;
select pg_temp.ck('E3 开着、一条流水都没有 = 本周开局: 快照报 3 级 ⇒ econ_mismatch(lv)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) ->> 'what' = 'lv');
select pg_temp.ck('E4 开着、一条流水都没有: 快照也是全空(1 级、身上没东西、没统领)⇒ null',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), jsonb_set(jsonb_set(pg_temp.snap('me'), '{season_level}', '1'), '{leaders}', '[]') - 'equipped') is null);
select pg_temp.ck('E5 开着、一条流水都没有却带统领(真客户端「开始」就记 leaders)⇒ econ_mismatch(leader:ninja)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), jsonb_set(pg_temp.snap('me'), '{season_level}', '1') - 'equipped') ->> 'what' = 'leader:ninja');

-- ── P 追没追上 ──
insert into public.econ_ops (account_id, week, seq, op, src) values
  (pg_temp.u('me'), pg_temp.wk(), 0, '{"op":"leaders","ids":["ninja","dice","pirate"],"seq":0,"bt":0}', 'client'),
  (pg_temp.u('me'), pg_temp.wk(), 1, '{"op":"income","src":"ranked_ref","coins":20,"xp":2,"axe":true,"candy":2,"seq":1,"bt":1}', 'client'),
  (pg_temp.u('me'), pg_temp.wk(), 2, '{"op":"buy_xp","seq":2,"bt":1}', 'client');
select pg_temp.ck('P1 有 3 条流水、还没重放 ⇒ econ_pending(have 0 / need 3)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) @> '{"reason":"econ_pending","have":0,"need":3}');
select pg_temp.ck('P2 积分赛开局回 econ_pending(带账本)、一条任务都没建',
  pg_temp.start('me', pg_temp.snap('me')) ->> 'reason' = 'econ_pending' and pg_temp.start('me', pg_temp.snap('me')) ? 'ledger'
  and pg_temp.jobs_of('me') = 0);
select pg_temp.ck('D1 流水一动就标脏', (select dirty from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk()));
select pg_temp.ck('P3 领活: 我在里面, seen 3, 每条都带序号',
  exists (select 1 from jsonb_array_elements(public.econ_replay_claim(50)) x
           where x ->> 'account_id' = pg_temp.u('me')::text and (x ->> 'seen')::int = 3
             and (x -> 'rows' -> 2 ->> 'seq')::int = 2 and x -> 'rows' -> 0 ->> 'op' = 'leaders'));
insert into public.econ_ops (account_id, week, seq, op, src) values
  (pg_temp.u('me'), pg_temp.wk(), 3, '{"op":"refresh","seed":12345}', 'server');   -- 服务器刚发的种子, 客户端还没传回(缺 bt)
select pg_temp.ck('P4 第 3 条是没传回的种子行 ⇒ 领活只给前 3 条(seen 仍 3)',
  exists (select 1 from jsonb_array_elements(public.econ_replay_claim(50)) x
           where x ->> 'account_id' = pg_temp.u('me')::text and (x ->> 'seen')::int = 3 and jsonb_array_length(x -> 'rows') = 3));
update public.econ_ops set op = '{"op":"refresh","seed":12345,"seq":3,"bt":1}' where account_id = pg_temp.u('me') and seq = 3;
select pg_temp.ck('P5 客户端传回(带 bt)之后 ⇒ 领到 4 条',
  exists (select 1 from jsonb_array_elements(public.econ_replay_claim(50)) x
           where x ->> 'account_id' = pg_temp.u('me')::text and (x ->> 'seen')::int = 4));

-- ── M 比对 ──
select public.econ_replay_done(jsonb_build_array(jsonb_build_object('account_id', pg_temp.u('me'), 'week', pg_temp.wk(),
  'seen', 4, 'result', pg_temp.result())));
select pg_temp.ck('M1 回写之后对得上 ⇒ econ_check null', public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) is null);
select pg_temp.ck('D2 回写追上 ⇒ 不脏了', (select not dirty from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk()));
select pg_temp.ck('M2 对得上 ⇒ 积分赛开局走到下一道(no_opponent)', pg_temp.start('me', pg_temp.snap('me')) ->> 'reason' = 'no_opponent');
select pg_temp.ck('M3 领活不再给我(已追上)', not exists (select 1 from jsonb_array_elements(public.econ_replay_claim(50)) x
  where x ->> 'account_id' = pg_temp.u('me')::text));
select pg_temp.ck('M4 ★改存档: ninja 那件改成 3★ ⇒ econ_mismatch(worn:ninja)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), jsonb_set(pg_temp.snap('me'), '{equipped,ninja,0,star}', '3')) ->> 'what' = 'worn:ninja');
select pg_temp.ck('M5 ★改存档: dice 多塞一件 ⇒ econ_mismatch(worn:dice)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), jsonb_set(pg_temp.snap('me'), '{equipped,dice}',
    '[{"id":"p2eq_050","star":3}]')) ->> 'what' = 'worn:dice');
select pg_temp.ck('M6 ★积分赛开局拿改过的快照 ⇒ econ_mismatch、不建任务',
  pg_temp.start('me', jsonb_set(pg_temp.snap('me'), '{equipped,dice}', '[{"id":"p2eq_050","star":3}]')) ->> 'reason' = 'econ_mismatch'
  and pg_temp.jobs_of('me') = 0);
select pg_temp.ck('M7 装备实例带 chg、星级写成 1.0 ⇒ 不算不同',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), jsonb_set(pg_temp.snap('me'), '{equipped,ninja}',
    '[{"id":"p2eq_001","star":1.0,"chg":777}]')) is null);
select pg_temp.ck('M8 大轮等级报高 ⇒ econ_mismatch(lv)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), jsonb_set(pg_temp.snap('me'), '{season_level}', '9')) ->> 'what' = 'lv');
select pg_temp.ck('M9 小木斧累计经验报高 ⇒ econ_mismatch(axe)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"axe_exp_total":400}') ->> 'what' = 'axe');
select pg_temp.ck('M10 宝箱财宝值报高 ⇒ econ_mismatch(chest)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"chest_treasure_value":5000}') ->> 'what' = 'chest');
select pg_temp.ck('M11 香火刻痕报高 ⇒ econ_mismatch(incense)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"incense_marks":12}') ->> 'what' = 'incense');
select pg_temp.ck('M10b 宝箱值小数末位不同(JSON 往返)⇒ 不算不同',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"chest_treasure_value":0.0000000001}') is null);
select pg_temp.ck('M14 统领不在本大轮锁定的三只里 ⇒ econ_mismatch(leader:ice)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"leaders":["ninja","dice","ice"]}') ->> 'what' = 'leader:ice');
select pg_temp.ck('M12 小将身上报了装备(重放里没有)⇒ econ_mismatch(minions)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"minions":{"top":[{"role":"front","equips":[{"id":"p2eq_010","star":2}]}],"bottom":[]}}')
    ->> 'what' = 'minions');
update public.econ_state set assets = jsonb_set(assets, '{minions}', '["{\"eq\":[{\"id\":\"p2eq_010\",\"star\":2}],\"lv\":0}"]')
 where account_id = pg_temp.u('me') and week = pg_temp.wk();
select pg_temp.ck('M13 重放里小将有同一件(EconLedger 存的是 JSON 串)⇒ 对得上',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"minions":{"top":[],"bottom":[{"role":"back","equips":[{"id":"p2eq_010","star":2.0}]}]}}')
    is null);
update public.econ_state set assets = jsonb_set(assets, '{minions}', '[]') where account_id = pg_temp.u('me') and week = pg_temp.wk();

-- ── T 尾部种子行没传回(闪退) ──
insert into public.econ_ops (account_id, week, seq, op, src) values
  (pg_temp.u('me'), pg_temp.wk(), 4, '{"op":"roll","seed":777}', 'server');
select pg_temp.ck('T1 ★尾部种子行没传回 ⇒ 不算没追上, 照常比对(能开局)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) is null);
select pg_temp.ck('D3 只多了一条没传回的种子行: 领活不给',
  not exists (select 1 from jsonb_array_elements(public.econ_replay_claim(50)) x where x ->> 'account_id' = pg_temp.u('me')::text));
select pg_temp.ck('D3b 领活顺手清掉脏标记', (select not dirty from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk()));
update public.econ_ops set op = '{"op":"roll","seed":777,"seq":4,"bt":1}' where account_id = pg_temp.u('me') and seq = 4;
select pg_temp.ck('T2 传回之后 = 新流水 ⇒ 脏、econ_pending', (select dirty from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk())
  and public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) ->> 'reason' = 'econ_pending');
select public.econ_replay_done(jsonb_build_array(jsonb_build_object('account_id', pg_temp.u('me'), 'week', pg_temp.wk(), 'seen', 4, 'result', pg_temp.result())));
select pg_temp.ck('D4 算的时候又来了新流水 ⇒ 回写之后仍是脏的', (select dirty and seen = 4 from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk()));
delete from public.econ_ops where account_id = pg_temp.u('me') and seq = 4;
select public.econ_replay_done(jsonb_build_array(jsonb_build_object('account_id', pg_temp.u('me'), 'week', pg_temp.wk(), 'seen', 4, 'result', pg_temp.result())));

-- ── F 事实 ──
insert into public.ranked_records (season_week, account_id, battles, wins, hearts, used, coins)
  values (pg_temp.wk(), pg_temp.u('other'), 5, 3, 4, 5, 90);
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, status, meta, result) values
  ('gauntlet', 'chk:g1', pg_temp.wk(), '0.22.7', 1, pg_temp.u('other'), pg_temp.u('me'), '{}', '{}', 'done', '{"pair":"true"}',
   '{"ledger":{"won":true,"coins":4,"coins_b":9},"chest":{"value":10,"won":["a"]},"chest_b":{"value":20,"won":["b"]},"incense_b":{"marks":2,"charge":1}}'),
  ('gauntlet', 'chk:g2', pg_temp.wk(), '0.22.7', 2, pg_temp.u('other'), pg_temp.u('me'), '{}', '{}', 'done', '{}', '{"ledger":{"won":false,"coins":5}}'),
  ('gauntlet', 'chk:g3', pg_temp.wk(), '0.22.7', 3, pg_temp.u('other'), null, '{}', '{}', 'pending', '{}', null),
  ('gauntlet', 'chk:g4', pg_temp.wk() - 604800, '0.22.7', 4, pg_temp.u('other'), null, '{}', '{}', 'done', '{}', '{"ledger":{"won":true,"coins":99}}'),
  ('finals', 'chk:f1', pg_temp.wk(), '0.22.7', 5, pg_temp.u('me'), pg_temp.u('other'), '{}', '{}', 'done', '{}', '{"ledger":{"won":false,"coins":1,"coins_b":6}}'),
  ('ranked', 'chk:r1', pg_temp.wk(), '0.22.7', 6, pg_temp.u('other'), null, '{}', '{}', 'done', '{}', '{"ledger":{"won":true,"coins":2},"incense":{"marks":1,"charge":3}}');
select pg_temp.ck('F1 ranked = ranked_records 那一行', public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'ranked' = '{"n":5,"w":3,"coins":90,"used":5}'::jsonb,
  (public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'ranked')::text);
select pg_temp.ck('F2 A 方闯关: 2 局算完的(没完成 / 别周不算)、胜 1、铸币 4 + 5',
  public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'gauntlet' = '{"n":2,"w":1,"minted":9}'::jsonb, (public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'gauntlet')::text);
select pg_temp.ck('F3 ★配对局 B 方: 胜负取反、取 coins_b; 旧路任务的 b_account 不算',
  public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'gauntlet' = '{"n":1,"w":0,"minted":9}'::jsonb, (public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'gauntlet')::text);
select pg_temp.ck('F4 决赛 A / B 两边都算(A 输、B 赢)',
  public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'finals' = '{"n":1,"w":0,"minted":1}'::jsonb
  and public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'finals' = '{"n":1,"w":1,"minted":6}'::jsonb);
select pg_temp.ck('F5 ★宝箱 / 香火取各自那一侧的结果单',
  public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'chest' = '[{"value":20,"won":["b"]}]'::jsonb
  and public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'incense' = '[{"marks":2,"charge":1}]'::jsonb
  and public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'chest' = '[{"value":10,"won":["a"]}]'::jsonb
  and public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'incense' = '[{"marks":1,"charge":3}]'::jsonb);
select pg_temp.ck('F6 没有账的号 ⇒ 全 0(不是 null)',
  public.econ_facts(pg_temp.u('real'), pg_temp.wk()) @> '{"ranked":{"n":0,"coins":0},"gauntlet":{"n":0},"finals":{"n":0},"chest":[],"incense":[]}'::jsonb);
insert into public.econ_ops (account_id, week, seq, op, src) values
  (pg_temp.u('other'), pg_temp.wk(), 0, '{"op":"leaders","ids":["ninja"],"seq":0,"bt":0}', 'client');
select pg_temp.ck('F7 ★领活带上这个号的事实', exists (select 1 from jsonb_array_elements(public.econ_replay_claim(50)) x
  where x ->> 'account_id' = pg_temp.u('other')::text and (x -> 'facts' -> 'ranked' ->> 'coins')::int = 90));
delete from public.econ_ops where account_id = pg_temp.u('other');
delete from public.econ_state where account_id = pg_temp.u('other');

-- ── C ★真快照契约 ──
-- >>> 契约样本(verify_econ_server_check 生成; 手改无效)
create or replace function pg_temp.contract() returns jsonb language sql as $c$ select $j${"assets":{"axe":[0,0,0,"",0],"leaders":["candy","stone","ice"],"lv":5,"minions":["{\"eq\":[{\"id\":\"p2eq_047\",\"star\":1}],\"lv\":0}"],"worn":{"candy":[{"id":"p2eq_085","star":1}]}},"progress":{"cv":120.5,"cw":["t1"],"ic":2,"im":1},"snap":{"axe_exp_total":0.0,"axe_final":"","axe_stage":0.0,"chest_treasure_value":120.5,"chest_treasures_won":["t1"],"equipped":{"candy":[{"id":"p2eq_085","star":1.0}]},"incense_charge":2.0,"incense_marks":1.0,"leaders":["candy","stone","ice"],"minions":{"bottom":[{"elite":false,"role":"front"},{"elite":false,"role":"back"}],"top":[{"elite":false,"equips":[{"id":"p2eq_047","star":1.0}],"role":"front"}]},"season_level":5.0}}$j$::jsonb $c$;
-- <<< 契约样本
insert into public.econ_state (account_id, week, seen, upto, assets, progress)
  values (pg_temp.u('real'), pg_temp.wk(), 0, 0, pg_temp.contract() -> 'assets', pg_temp.contract() -> 'progress');
select pg_temp.ck('C1 ★真快照 + 真重放结果 ⇒ 对得上(老实玩家不被拒)', public.econ_check(pg_temp.u('real'), pg_temp.wk(), pg_temp.contract() -> 'snap') is null,
  coalesce(public.econ_check(pg_temp.u('real'), pg_temp.wk(), pg_temp.contract() -> 'snap')::text, ''));
select pg_temp.ck('C2 分母: 样本里统领身上真有装备、小将真有装备', (select count(*) from jsonb_each(pg_temp.contract() -> 'snap' -> 'equipped')) >= 1
  and public.econ_snapshot_minions_key(pg_temp.contract() -> 'snap') <> '');
select pg_temp.ck('C3 ★改存档: 统领第一件改成 3★ ⇒ 拒',
  public.econ_check(pg_temp.u('real'), pg_temp.wk(),
    jsonb_set(pg_temp.contract() -> 'snap', array['equipped', (select k from jsonb_object_keys(pg_temp.contract() -> 'snap' -> 'equipped') k limit 1), '0', 'star'], '3'))
    ->> 'reason' = 'econ_mismatch');
select pg_temp.ck('C4 ★改存档: 小将多一件 ⇒ econ_mismatch(minions)',
  public.econ_check(pg_temp.u('real'), pg_temp.wk(),
    (pg_temp.contract() -> 'snap') || '{"minions":{"top":[{"equips":[{"id":"p2eq_050","star":3}]}],"bottom":[]}}') ->> 'what' = 'minions');
delete from public.econ_state where account_id = pg_temp.u('real');

-- ── W 回写只往前走 ──
select public.econ_replay_done(jsonb_build_array(jsonb_build_object('account_id', pg_temp.u('me'), 'week', pg_temp.wk(),
  'seen', 2, 'result', pg_temp.result() || '{"fp":"old"}')));
select pg_temp.ck('W1 seen 小的回写不覆盖(仍 4 条、fp 没变)',
  (select seen = 4 and fp = 'x' from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk()));

-- ── I 不合法 ──
select public.econ_replay_done(jsonb_build_array(jsonb_build_object('account_id', pg_temp.u('me'), 'week', pg_temp.wk(),
  'seen', 4, 'result', pg_temp.result(2))));
select pg_temp.ck('I1 重放判第 2 条不合法 ⇒ econ_invalid(at 2)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me')) @> '{"reason":"econ_invalid","at":2}');
do $$
declare r1 jsonb; r2 jsonb; r3 jsonb;
begin
  perform pg_temp.as_user(pg_temp.u('me'));
  r1 := public.econ_truncate(pg_temp.wk(), 1);
  perform pg_temp.as_user(pg_temp.u('other'));
  r2 := public.econ_truncate(pg_temp.wk(), 2);
  perform pg_temp.as_user(pg_temp.u('me'));
  r3 := public.econ_truncate(pg_temp.wk(), 2);
  perform pg_temp.as_user(null);
  perform pg_temp.ck('I2 截在别的序号(1)⇒ not_invalid', r1 ->> 'reason' = 'not_invalid', r1::text);
  perform pg_temp.ck('I3 别人来截 ⇒ not_invalid', r2 ->> 'reason' = 'not_invalid', r2::text);
  perform pg_temp.ck('I4 截在 2 ⇒ ok next 2; 流水剩 2 条; 状态 seen 2、不合法标记清掉', (r3 ->> 'ok')::boolean and (r3 ->> 'next')::int = 2
    and (select count(*) from public.econ_ops where account_id = pg_temp.u('me') and week = pg_temp.wk()) = 2
    and (select seen = 2 and bad_at = -1 and why = '' from public.econ_state where account_id = pg_temp.u('me') and week = pg_temp.wk()),
    r3::text);
end $$;

-- ── B 比对的位置 ──
select pg_temp.ck('B1 积分赛开局: 比对在场次核对之后、账本落行之前',
  position('''stale''' in pg_get_functiondef('public.referee_ranked_start(bigint,jsonb,int,text,int)'::regprocedure))
    < position('econ_check(uid, p_week, p_snapshot)' in pg_get_functiondef('public.referee_ranked_start(bigint,jsonb,int,text,int)'::regprocedure))
  and position('econ_check(uid, p_week, p_snapshot)' in pg_get_functiondef('public.referee_ranked_start(bigint,jsonb,int,text,int)'::regprocedure))
    < position('insert into public.ranked_records' in pg_get_functiondef('public.referee_ranked_start(bigint,jsonb,int,text,int)'::regprocedure)));
select pg_temp.ck('B2 周六进队: 比对在场次核对之后、进队列之前',
  position('''stale''' in pg_get_functiondef('public.gauntlet_queue_join(bigint,jsonb,int,text,int)'::regprocedure))
    < position('econ_check(uid, p_week, p_snapshot)' in pg_get_functiondef('public.gauntlet_queue_join(bigint,jsonb,int,text,int)'::regprocedure))
  and position('econ_check(uid, p_week, p_snapshot)' in pg_get_functiondef('public.gauntlet_queue_join(bigint,jsonb,int,text,int)'::regprocedure))
    < position('insert into public.gauntlet_queue' in pg_get_functiondef('public.gauntlet_queue_join(bigint,jsonb,int,text,int)'::regprocedure)));

-- ── R 行级策略 / 权限 ──
grant select on public.econ_state to authenticated;
do $$
declare n_other int; n_me int;
begin
  perform pg_temp.as_user(pg_temp.u('other'));
  set local role authenticated;
  select count(*) into n_other from public.econ_state where account_id = pg_temp.u('me');
  reset role;
  perform pg_temp.as_user(pg_temp.u('me'));
  set local role authenticated;
  select count(*) into n_me from public.econ_state where account_id = pg_temp.u('me');
  reset role;
  perform pg_temp.as_user(null);
  perform pg_temp.ck('R1 别人读不到我的 econ_state, 我读得到', n_other = 0 and n_me = 1, n_other || '/' || n_me);
end $$;
select pg_temp.ck('R2 领活 / 回写只给 service_role',
  has_function_privilege('service_role', 'public.econ_replay_claim(int)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_replay_claim(int)', 'execute')
  and not has_function_privilege('anon', 'public.econ_replay_claim(int)', 'execute')
  and has_function_privilege('service_role', 'public.econ_replay_done(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_replay_done(jsonb)', 'execute'));
select pg_temp.ck('R3 econ_check 不对外; econ_truncate 只给 authenticated',
  not has_function_privilege('authenticated', 'public.econ_check(uuid, bigint, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.econ_check(uuid, bigint, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.econ_truncate(bigint, int)', 'execute')
  and not has_function_privilege('anon', 'public.econ_truncate(bigint, int)', 'execute'));

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
