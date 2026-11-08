-- 20261109b 龟等级与经验 + 开算盖章 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261109b_pet_levels
-- ★要先有 20261109a_mainsite_core（mainsite_accounts / mainsite_pets / mainsite_outbox_put）；与 20261109c_raid 先后都行。
-- 判据（门禁名 = 本文件；方案书 20261107b §6 verify_pet_xp 那几条在这里）：
--   C1 曲线：70 升 2 级、160 升 3 级、1350 满 10 级；69 还是 1 级、1349 还是 9 级
--   C2 28 只齐（= WeeklyFree.ALL），不重复
--   S1 ★等级表：拥有的按 pet_levels（stone 4 级）、拥有但没记录的 1 级（lava）、没拥有的 1 级（basic，快照自报 10 级不认）
--   S2 没有账号（机器人池）⇒ 全 1 级
--   K1 ★领活（BEFORE 触发器）：任务单 key 带 a_account / b_account / a_owned / b_owned / a_lv / b_lv，meta 写回任务行；
--      ★快照一个字不改（决赛坏快照回退逐字比快照；也不在快照里放账号与拥有 —— matches 所有人读得到）
--   K2 补流任务单的 key 同样带四个键（拥有取任务行里记的，不重算）
--   K3 没账号那一侧（机器人池）：key.b_account = null、b_owned = []、全 1 级
--   X1 ★真结算（referee_complete，闯关配对局，A 赢）：A 拥有的 stone / lava 各 +8，限免的 basic 不发；B（输）拥有的 bamboo +6
--   X2 ★幂等：同一局再发一次一只都不加
--   X3 ★升级那一刻写一条 pet-level（{userId, petKey, level}）；没升级的不写；开算后解绑（拥有清空）⇒ 这一局不发、不写
--   X4 ★输 +6；满级封顶 1350、10 级；封顶后再打记 0
--   X5 ★积分赛只给 A（B 是别人的快照）；决赛两边都给；结果被顶掉（superseded）不给
--   X6 偷袭 / 其他种类不给；没盖过章（meta 里没有开算时的拥有）不给
--   X7 发经验出错不回滚结算（缺 mainsite_outbox_put 时任务照样 done）
--   M1 pet_levels_me：= mainsite_me() 那一份 + levels；未登录 not_signed_in
--   P1 权限：pet_levels_me 只给 authenticated；内部函数 authenticated 调不了；两张表客户端读不到
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('a'), ('b'), ('c'), ('d');
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
create or replace function pg_temp.lv(p_k text, p_pet text) returns int language sql as $$
  select level from public.pet_levels where account_id = pg_temp.u(p_k) and pet_key = p_pet $$;
create or replace function pg_temp.xp(p_k text, p_pet text) returns int language sql as $$
  select xp from public.pet_levels where account_id = pg_temp.u(p_k) and pet_key = p_pet $$;
create or replace function pg_temp.snap(p_l text[]) returns jsonb language sql as $$
  select jsonb_build_object('leaders', to_jsonb(p_l), 'lane_assign', jsonb_build_object('top', to_jsonb(p_l[1:2]), 'bottom', to_jsonb(p_l[3:3])),
                            'owned', '["basic"]'::jsonb, 'lv', jsonb_build_object(p_l[1], 10, p_l[2], 10, p_l[3], 10)) $$;
create or replace function pg_temp.job(p_kind text, p_key text, p_a uuid, p_b uuid, p_sa jsonb, p_sb jsonb, p_meta jsonb default '{}')
returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta)
  values (p_kind, p_key, 1762732800, 'tv-c', 4242, p_a, p_b, p_sa, p_sb, p_meta) returning job_id $$;
create or replace function pg_temp.outbox_n(p_pet text) returns int language sql as $$
  select count(*)::int from public.mainsite_outbox where topic = 'pet-level' and body ->> 'petKey' = p_pet $$;

insert into auth.users (id, aud, role, is_anonymous, created_at) select id, 'authenticated', 'authenticated', true, now() from _u;
insert into public.accounts (account_id) select id from _u;
-- A 绑定了主站、拥有 stone / lava；B 绑定、拥有 bamboo；C 绑定、拥有 stone（X3 里开算后解绑）；D 没绑定
insert into public.mainsite_accounts (account_id, mainsite_user_id)
  values (pg_temp.u('a'), 'GEAcTestA'), (pg_temp.u('b'), 'GEAcTestB'), (pg_temp.u('c'), 'GEAcTestC');
insert into public.mainsite_pets (account_id, pet_key, fetched_at)
  values (pg_temp.u('a'), 'stone', now()), (pg_temp.u('a'), 'lava', now()), (pg_temp.u('a'), 'not_a_turtle', now()),
         (pg_temp.u('b'), 'bamboo', now()), (pg_temp.u('c'), 'stone', now());
insert into public.pet_levels (account_id, pet_key, xp, level) values (pg_temp.u('a'), 'stone', 300, 4);
insert into public.referee_versions (client_version, enabled) values ('tv-c', true) on conflict do nothing;
update public.referee_config set lease_sec = 180, max_attempts = 3 where id = 1;

-- C1 / C2
select pg_temp.ck('C1 曲线: 69→1 70→2 159→2 160→3 1349→9 1350→10 99999→10; 要 70/160/1350',
  public.pet_level_for_xp(69) = 1 and public.pet_level_for_xp(70) = 2 and public.pet_level_for_xp(159) = 2
  and public.pet_level_for_xp(160) = 3 and public.pet_level_for_xp(1349) = 9 and public.pet_level_for_xp(1350) = 10
  and public.pet_level_for_xp(99999) = 10 and public.pet_xp_to_reach(2) = 70 and public.pet_xp_to_reach(3) = 160
  and public.pet_xp_to_reach(10) = 1350 and public.pet_xp_to_reach(1) = 0,
  format('%s/%s/%s', public.pet_xp_to_reach(2), public.pet_xp_to_reach(3), public.pet_xp_to_reach(10)));
select pg_temp.ck('C2 28 只齐、不重复', cardinality(public.pet_all_ids()) = 28
  and (select count(distinct x) from unnest(public.pet_all_ids()) x) = 28, cardinality(public.pet_all_ids())::text);

-- S1 / S2
do $$
declare s jsonb;
begin
  s := public.pet_lv_table(pg_temp.snap(array['stone', 'basic', 'lava']), pg_temp.u('a'));
  perform pg_temp.ck('S1 ★等级表: stone=4(服务器) basic=1(没拥有, 自报 10 不认) lava=1(拥有没记录), 恰好三只',
    (s ->> 'stone')::int = 4 and (s ->> 'basic')::int = 1 and (s ->> 'lava')::int = 1
    and (select count(*) from jsonb_object_keys(s)) = 3, s::text);
  s := public.pet_lv_table(pg_temp.snap(array['stone', 'basic', 'lava']), null);
  perform pg_temp.ck('S2 没有账号 ⇒ 全 1 级', (s ->> 'stone')::int = 1 and (s ->> 'basic')::int = 1, s::text);
  perform pg_temp.ck('S3 拥有只认 28 只(not_a_turtle 不算)、按名字排',
    public.pet_owned(pg_temp.u('a')) = array['lava', 'stone'], public.pet_owned(pg_temp.u('a'))::text);
end $$;

-- K1 / K2 / X1 / X2 / X3：闯关配对局 A(拥有 stone/lava, 上场 stone/basic/lava) vs B(拥有 bamboo, 上场 bamboo/ice/ninja)
update public.pet_levels set xp = 65, level = 1 where account_id = pg_temp.u('a') and pet_key = 'stone';   -- 再 +8 ⇒ 73 ⇒ 2 级
do $$
declare jid bigint; c jsonb; j record; r jsonb; jj record;
begin
  jid := pg_temp.job('gauntlet', 'c:pair:1', pg_temp.u('a'), pg_temp.u('b'),
    pg_temp.snap(array['stone', 'basic', 'lava']), pg_temp.snap(array['bamboo', 'ice', 'ninja']), '{"pair": "true"}');
  c := public.referee_claim('w-test', array['tv-c'], 1);
  perform pg_temp.ck('K1 ★领活: 任务单 key 带 a_account / b_account / a_owned / b_owned',
    jsonb_array_length(c) = 1 and c -> 0 -> 'key' ->> 'a_account' = pg_temp.u('a')::text
    and c -> 0 -> 'key' ->> 'b_account' = pg_temp.u('b')::text
    and c -> 0 -> 'key' -> 'a_owned' = '["lava", "stone"]'::jsonb and c -> 0 -> 'key' -> 'b_owned' = '["bamboo"]'::jsonb,
    left(c::text, 700));
  perform pg_temp.ck('K1 ★key 带等级表(A stone=1 那时 1 级, basic 自报 10 ⇒ 1; B bamboo=1)',
    (c -> 0 -> 'key' -> 'a_lv' ->> 'basic')::int = 1 and (c -> 0 -> 'key' -> 'a_lv' ->> 'stone')::int = 1
    and (c -> 0 -> 'key' -> 'b_lv' ->> 'bamboo')::int = 1 and (select count(*) from jsonb_object_keys(c -> 0 -> 'key' -> 'a_lv')) = 3,
    (c -> 0 -> 'key')::text);
  select * into j from public.referee_jobs where job_id = jid;
  perform pg_temp.ck('K1 ★快照一个字不改(任务行 / 任务单里的都 = 建任务时那份), 也不放账号',
    j.a_snapshot = pg_temp.snap(array['stone', 'basic', 'lava']) and j.b_snapshot = pg_temp.snap(array['bamboo', 'ice', 'ninja'])
    and c -> 0 -> 'a' = pg_temp.snap(array['stone', 'basic', 'lava']) and not (c -> 0 -> 'a' ? 'account_id'), (c -> 0 -> 'a')::text);
  perform pg_temp.ck('K1 ★拥有 / 等级表写回了任务行 meta(补流 / 发经验用同一份)',
    j.meta -> 'a_owned' = '["lava", "stone"]'::jsonb and j.meta -> 'b_owned' = '["bamboo"]'::jsonb
    and j.meta -> 'a_lv' = c -> 0 -> 'key' -> 'a_lv' and j.meta ->> 'pair' = 'true', j.meta::text);
  -- 真结算
  r := public.referee_complete(jid, 'w-test', jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', 4242,
    'client_version', 'tv-c', 'winner', 'a', 'steps', 100, 'replay_b64', 'QUJD', 'score_code', 1,
    'lane_results', jsonb_build_object('top', 'left', 'bottom', 'left')));
  select * into jj from public.referee_jobs where job_id = jid;
  perform pg_temp.ck('X1 分母: referee_complete 写回成功、任务 done', (r ->> 'ok')::boolean and jj.status = 'done', r::text);
  perform pg_temp.ck('X1 ★A 赢: 拥有的 stone 65→73(2 级)、lava 0→8; 限免 basic 没有记录',
    pg_temp.xp('a', 'stone') = 73 and pg_temp.lv('a', 'stone') = 2 and pg_temp.xp('a', 'lava') = 8
    and pg_temp.xp('a', 'basic') is null,
    format('stone %s/%s lava %s basic %s', pg_temp.xp('a', 'stone'), pg_temp.lv('a', 'stone'), pg_temp.xp('a', 'lava'), pg_temp.xp('a', 'basic')));
  perform pg_temp.ck('X1 ★B 输(配对局 B 在场): 拥有的 bamboo +6; 限免 ice / ninja 不发',
    pg_temp.xp('b', 'bamboo') = 6 and pg_temp.xp('b', 'ice') is null and pg_temp.xp('b', 'ninja') is null,
    format('bamboo %s', pg_temp.xp('b', 'bamboo')));
  perform pg_temp.ck('X1 记账: 这一局 3 条经验记录(A 2 + B 1)、幂等键带账号',
    (select count(*) from public.pet_xp_log where match_id = j.match_id) = 3);
  perform pg_temp.ck('X3 ★升级那一刻写一条 pet-level {userId, petKey, level}; lava / bamboo 没升级不写',
    pg_temp.outbox_n('stone') = 1 and pg_temp.outbox_n('lava') = 0 and pg_temp.outbox_n('bamboo') = 0
    and (select body from public.mainsite_outbox where topic = 'pet-level' and body ->> 'petKey' = 'stone')
        = '{"userId": "GEAcTestA", "petKey": "stone", "level": 2}'::jsonb,
    (select string_agg(body::text, ' ') from public.mainsite_outbox where topic = 'pet-level'));
  -- X2 幂等：同一局再发一次（触发器不会再响 —— 直接调发经验函数）
  perform public.pet_xp_grant(j.match_id, 'gauntlet', pg_temp.u('a'), jj.a_snapshot, jj.meta -> 'a_owned', true);
  perform pg_temp.ck('X2 ★同一局再发一次: 一只都不加、发件箱不多', pg_temp.xp('a', 'stone') = 73 and pg_temp.xp('a', 'lava') = 8
    and pg_temp.outbox_n('stone') = 1 and (select count(*) from public.pet_xp_log where match_id = j.match_id) = 3);
  -- K2 补流
  insert into public.referee_restream (match_id, job_id, client_version) values (j.match_id, jid, 'tv-c');
  c := public.referee_claim_restream('w-test', array['tv-c'], 1);
  perform pg_temp.ck('K2 补流任务单 key 带同一份账号 / 拥有 / 等级表(任务行里记的, 不重算)',
    jsonb_array_length(c) = 1 and c -> 0 -> 'key' ->> 'a_account' = pg_temp.u('a')::text
    and c -> 0 -> 'key' -> 'b_owned' = '["bamboo"]'::jsonb and c -> 0 -> 'key' -> 'a_lv' = jj.meta -> 'a_lv', left(c::text, 400));
  -- K3 没账号那一侧(机器人池): key.b_account = null、b_owned = []、lv 全 1
  jid := pg_temp.job('ranked', 'c:ranked:bot', pg_temp.u('a'), null,
    pg_temp.snap(array['stone', 'basic', 'lava']), pg_temp.snap(array['bamboo', 'ice', 'ninja']));
  c := public.referee_claim('w-test', array['tv-c'], 1);
  perform pg_temp.ck('K3 没账号那一侧: key.b_account = null、b_owned = []、lv 全 1(A 那一侧 stone 已是 2 级)',
    jsonb_array_length(c) = 1 and jsonb_typeof(c -> 0 -> 'key' -> 'b_account') = 'null' and c -> 0 -> 'key' -> 'b_owned' = '[]'::jsonb
    and (c -> 0 -> 'key' -> 'b_lv' ->> 'bamboo')::int = 1 and (c -> 0 -> 'key' -> 'a_lv' ->> 'stone')::int = 2, left(c::text, 500));
  update public.referee_jobs set status = 'failed' where job_id = jid;
end $$;

-- X4 输 +6；满级封顶；X3 没绑定的号；X6 不给的几种
do $$
declare s jsonb := pg_temp.snap(array['stone', 'basic', 'lava']);
        m uuid; x0 int; ob0 int;
begin
  perform public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('a'), s, '["lava", "stone"]', false);
  perform pg_temp.ck('X4 ★输 +6(stone 73→79, lava 8→14)', pg_temp.xp('a', 'stone') = 79 and pg_temp.xp('a', 'lava') = 14,
    format('%s / %s', pg_temp.xp('a', 'stone'), pg_temp.xp('a', 'lava')));
  update public.pet_levels set xp = 1345, level = 9 where account_id = pg_temp.u('a') and pet_key = 'lava';
  perform public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('a'), s, '["lava", "stone"]', true);
  perform pg_temp.ck('X4 ★满级封顶: 1345 + 8 ⇒ 1350、10 级; 写一条 lava 10 级', pg_temp.xp('a', 'lava') = 1350 and pg_temp.lv('a', 'lava') = 10
    and (select count(*) from public.mainsite_outbox where topic = 'pet-level'
          and body = '{"userId": "GEAcTestA", "petKey": "lava", "level": 10}'::jsonb) = 1,
    format('%s / %s', pg_temp.xp('a', 'lava'), pg_temp.lv('a', 'lava')));
  m := gen_random_uuid();
  perform public.pet_xp_grant(m, 'ranked', pg_temp.u('a'), s, '["lava", "stone"]', true);
  perform pg_temp.ck('X4 封顶后再打: 还是 1350、这一局记录加 0、不再写发件箱', pg_temp.xp('a', 'lava') = 1350
    and (select xp from public.pet_xp_log where match_id = m and account_id = pg_temp.u('a') and pet_key = 'lava') = 0
    and (select count(*) from public.mainsite_outbox where body ->> 'petKey' = 'lava') = 1);
  -- X3 开算后解绑(C: 领活时拥有 stone, 结算前解绑 ⇒ mainsite_pets 跟着删): 这一局不发、发件箱一条不写
  ob0 := (select count(*) from public.mainsite_outbox);
  insert into public.pet_levels (account_id, pet_key, xp, level) values (pg_temp.u('c'), 'stone', 66, 1);
  m := gen_random_uuid();
  delete from public.mainsite_accounts where account_id = pg_temp.u('c');
  perform public.pet_xp_grant(m, 'ranked', pg_temp.u('c'),
    pg_temp.snap(array['stone', 'ice', 'ninja']), '["stone"]', true);
  perform pg_temp.ck('X3 ★开算后解绑 ⇒ 这一局不发(66 不动)、发件箱一条不写', pg_temp.xp('c', 'stone') = 66
    and (select count(*) from public.mainsite_outbox) = ob0, format('xp %s outbox %s→%s', pg_temp.xp('c', 'stone'), ob0,
      (select count(*) from public.mainsite_outbox)));
  -- X6 偷袭 / 别的种类不给; 没盖过章不给; 开算时还没拥有的不给
  x0 := pg_temp.xp('a', 'stone');
  perform public.pet_xp_grant(gen_random_uuid(), 'raid', pg_temp.u('a'), s, '["lava", "stone"]', true);
  perform public.pet_xp_grant(gen_random_uuid(), 'friendly', pg_temp.u('a'), s, '["lava", "stone"]', true);
  perform pg_temp.ck('X6 ★偷袭 / 切磋不给', pg_temp.xp('a', 'stone') = x0, format('%s → %s', x0, pg_temp.xp('a', 'stone')));
  perform public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('a'), s, null, true);
  perform pg_temp.ck('X6 没有开算时的拥有(没盖过章) ⇒ 不给', pg_temp.xp('a', 'stone') = x0);
  perform public.pet_xp_grant(gen_random_uuid(), 'ranked', pg_temp.u('a'), s, '["lava"]', true);
  perform pg_temp.ck('X6 ★开算时还没拥有的(stone 那时是限免) ⇒ 这一局不给它', pg_temp.xp('a', 'stone') = x0);
end $$;

-- X5 积分赛只给 A；决赛两边；superseded 不给（直接把任务改成 done，走触发器）
do $$
declare jid bigint; s_a jsonb; s_b jsonb; x0 int; b0 int;
begin
  s_a := pg_temp.snap(array['stone', 'basic', 'lava']);
  s_b := pg_temp.snap(array['bamboo', 'ice', 'ninja']);
  x0 := pg_temp.xp('a', 'stone');
  b0 := pg_temp.xp('b', 'bamboo');
  jid := pg_temp.job('ranked', 'c:ranked:1', pg_temp.u('a'), pg_temp.u('b'), s_a, s_b,
    '{"a_owned": ["lava", "stone"], "b_owned": ["bamboo"]}');
  update public.referee_jobs set status = 'done', result = '{"winner": "b"}' where job_id = jid;
  perform pg_temp.ck('X5 ★积分赛: A 输 +6; B(别人的快照)不给', pg_temp.xp('a', 'stone') = x0 + 6 and pg_temp.xp('b', 'bamboo') = b0,
    format('a %s→%s b %s→%s', x0, pg_temp.xp('a', 'stone'), b0, pg_temp.xp('b', 'bamboo')));
  jid := pg_temp.job('finals', 'c:finals:1', pg_temp.u('a'), pg_temp.u('b'), s_a, s_b,
    '{"a_owned": ["lava", "stone"], "b_owned": ["bamboo"]}');
  update public.referee_jobs set status = 'done', result = '{"winner": "b"}' where job_id = jid;
  perform pg_temp.ck('X5 ★决赛: 两边都给(A 输 +6、B 赢 +8)', pg_temp.xp('a', 'stone') = x0 + 12 and pg_temp.xp('b', 'bamboo') = b0 + 8,
    format('a %s b %s', pg_temp.xp('a', 'stone'), pg_temp.xp('b', 'bamboo')));
  jid := pg_temp.job('finals', 'c:finals:2', pg_temp.u('a'), pg_temp.u('b'), s_a, s_b,
    '{"a_owned": ["lava", "stone"], "b_owned": ["bamboo"]}');
  update public.referee_jobs set status = 'done', error = 'superseded', result = '{"winner": "a"}' where job_id = jid;
  perform pg_temp.ck('X5 ★结果被顶掉(superseded) ⇒ 不给', pg_temp.xp('a', 'stone') = x0 + 12 and pg_temp.xp('b', 'bamboo') = b0 + 8);
  jid := pg_temp.job('gauntlet', 'c:solo:1', pg_temp.u('a'), pg_temp.u('b'), s_a, s_b,
    '{"a_owned": ["lava", "stone"], "b_owned": ["bamboo"]}');
  update public.referee_jobs set status = 'done', result = '{"winner": "a"}' where job_id = jid;
  perform pg_temp.ck('X5 闯关旧路(不是配对局): 只给 A', pg_temp.xp('a', 'stone') = x0 + 20 and pg_temp.xp('b', 'bamboo') = b0 + 8);
end $$;

-- X7 发经验出错不回滚结算
do $$
declare jid bigint; st text;
begin
  alter function public.mainsite_outbox_put(text, text, jsonb) rename to mainsite_outbox_put_x;
  update public.pet_levels set xp = 69 where account_id = pg_temp.u('a') and pet_key = 'stone';
  update public.pet_levels set level = 1 where account_id = pg_temp.u('a') and pet_key = 'stone';
  jid := pg_temp.job('ranked', 'c:ranked:err', pg_temp.u('a'), null,
    pg_temp.snap(array['stone', 'basic', 'lava']),
    pg_temp.snap(array['bamboo', 'ice', 'ninja']), '{"a_owned": ["lava", "stone"], "b_owned": []}');
  update public.referee_jobs set status = 'done', result = '{"winner": "a"}' where job_id = jid;
  select status into st from public.referee_jobs where job_id = jid;
  perform pg_temp.ck('X7 ★发件箱函数不在(升级要写发件箱时出错) ⇒ 任务照样 done(经验这一侧整段回退)',
    st = 'done' and pg_temp.xp('a', 'stone') = 69, format('%s xp %s', st, pg_temp.xp('a', 'stone')));
  alter function public.mainsite_outbox_put_x(text, text, jsonb) rename to mainsite_outbox_put;
end $$;

-- M1 / P1
select pg_temp.as_user(pg_temp.u('a'));
do $$
declare r jsonb := public.pet_levels_me();
begin
  perform pg_temp.ck('M1 ★pet_levels_me: = mainsite_me() 那一份(ok / linked / owned 逐字相同) + levels 带 lv / xp',
    (r ->> 'ok')::boolean and (r ->> 'linked')::boolean and r - 'levels' = public.mainsite_me()
    and r -> 'owned' = '["lava", "not_a_turtle", "stone"]'::jsonb
    and (r -> 'levels' -> 'stone' ->> 'lv')::int = 1 and (r -> 'levels' -> 'lava' ->> 'lv')::int = 10
    and (r -> 'levels' -> 'lava' ->> 'xp')::int = 1350, r::text);
end $$;
select pg_temp.as_user(pg_temp.u('d'));
select pg_temp.ck('M1 没绑定的号: linked=false、owned = []、levels = {}', not (public.pet_levels_me() ->> 'linked')::boolean
  and public.pet_levels_me() -> 'owned' = '[]'::jsonb and public.pet_levels_me() -> 'levels' = '{}'::jsonb, public.pet_levels_me()::text);
select pg_temp.as_user(null);
select pg_temp.ck('M1 未登录 ⇒ not_signed_in', public.pet_levels_me() ->> 'reason' = 'not_signed_in');
select pg_temp.ck('P1 权限: pet_levels_me 只给 authenticated',
  not has_function_privilege('anon', 'public.pet_levels_me()', 'execute')
  and has_function_privilege('authenticated', 'public.pet_levels_me()', 'execute'));
select pg_temp.ck('P1 内部函数 authenticated 调不了(发经验 / 盖章 / 拥有)',
  not has_function_privilege('authenticated', 'public.pet_xp_grant(uuid, text, uuid, jsonb, jsonb, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.pet_lv_table(jsonb, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.pet_owned(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.pet_xp_grant(uuid, text, uuid, jsonb, jsonb, boolean)', 'execute'));
select pg_temp.ck('P1 两张表开了行级安全且没有策略(客户端直连读不到)',
  (select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.pet_levels'::regclass, 'public.pet_xp_log'::regclass))
  and not exists (select 1 from pg_policies where tablename in ('pet_levels', 'pet_xp_log')));
select pg_temp.ck('T1 两个触发器挂在 referee_jobs 上(领活盖章 BEFORE、结算发经验 AFTER)',
  exists (select 1 from pg_trigger where tgname = 'pet_xp_on_job_done' and tgrelid = 'public.referee_jobs'::regclass)
  and exists (select 1 from pg_trigger where tgname = 'pet_stamp_on_claim' and tgrelid = 'public.referee_jobs'::regclass));

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
