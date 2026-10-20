-- 20261020b 账号删除 + 昵称举报 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：node tools/sql_sandbox.mjs（PGlite 起一个空库 → 桩 auth/cron → schema.sql → 迁移 → 本文件）
--   · 生产（上线迁移之后、宣布可用之前；需用户同意）：Supabase SQL 编辑器整段粘贴运行。
--     ★本文件**最后一句一定抛异常**（全过也抛 'ALL PASS'）⇒ 不管在哪个执行器里，整个事务都回滚，
--       造的 3 个测试账号与全部测试行一个都不会留下。结果就在那条异常信息里。
-- 判据（每条都配了对照组：被删的人变了、没被删的人一字不动）：
--   D1 只删调用者本人：A 没了，B / C 还在；匿名号（is_anonymous）照样能删
--   D2 cascade 表：A 的 ghosts / gauntlet_ghosts / saves / accounts / finals_pending / client_errors /
--      player_feedback / gauntlet_records / finals_scout / live_matches(自己的) 全 0 行；B 的同表行还在
--   D3 对局结构保留：matches / finals_entrants / referee_jobs 行数不变；A 那一侧的名字 / 头像 / 玩家 ID 变成占位，
--      另一侧一字不动；全库再也搜不到 A 的昵称原文与 A 的玩家 ID
--   D4 A 还没算的周六任务作废（failed / account_deleted），meta 里不再有账号
--   D5 与 A 有关的举报全删，别人之间的举报不动
--   D6 没登录 ⇒ not_signed_in；anon 角色没有执行权
--   R1~R8 举报：成功 / 24 小时重复 / 举报自己 / 坏 ID / 空名字 / 每日上限 / 账号反查 / 管理侧视图与处理
--   T1 player_tag_of 与客户端 phase2_config.player_tag 同一组向量（tests/verify_account_delete.gd 读本文件这三行逐个对）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as b, gen_random_uuid() as c, 4102444800::bigint as wk;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ids to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
-- 以某个账号的身份调用：只设 claims（auth.uid() 读它）。被测函数全是 security definer, 执行时的角色不影响结果;
--   「哪个角色有执行权」由 D6 那几条 has_function_privilege 单独量。p_uid = null ⇒ 清掉 claims。
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;

-- T1 ─ 玩家 ID 向量（★改这三行要同时改 tests/verify_account_delete.gd 的读法；它按「TAGVEC」前缀找）
-- TAGVEC 00000000-0000-0000-0000-000000000001 #4PT53K
-- TAGVEC f47ac10b-58cc-4372-a567-0e02b2c3d479 #XHVRJV
-- TAGVEC 9b2e6c1e-3f4a-4d55-8a7b-0c1d2e3f4a5b #VK7GGP
select pg_temp.ck('T1 player_tag_of 向量 1', public.player_tag_of('00000000-0000-0000-0000-000000000001') = '#4PT53K',
                  public.player_tag_of('00000000-0000-0000-0000-000000000001'));
select pg_temp.ck('T1 player_tag_of 向量 2', public.player_tag_of('f47ac10b-58cc-4372-a567-0e02b2c3d479') = '#XHVRJV',
                  public.player_tag_of('f47ac10b-58cc-4372-a567-0e02b2c3d479'));
select pg_temp.ck('T1 player_tag_of 向量 3', public.player_tag_of('9b2e6c1e-3f4a-4d55-8a7b-0c1d2e3f4a5b') = '#VK7GGP',
                  public.player_tag_of('9b2e6c1e-3f4a-4d55-8a7b-0c1d2e3f4a5b'));
select pg_temp.ck('T1 空身份 ⇒ 空串', public.player_tag_of('') = '');

-- ── 造数据：A（匿名，要删的）/ B / C ──
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select a, 'authenticated', 'authenticated', true, now() from _ids
  union all select b, 'authenticated', 'authenticated', false, now() from _ids
  union all select c, 'authenticated', 'authenticated', true, now() from _ids;

create temp table _p as
  select jsonb_build_object('name', 'A昵称探针', 'avatar', 'ninja', 'id', 'g_aaaaaaaaaaaa_1_x', 'tag', public.player_tag_of(a::text)) as pa,
         jsonb_build_object('name', 'B昵称探针', 'avatar', 'basic', 'id', 'g_bbbbbbbbbbbb_1_x', 'tag', public.player_tag_of(b::text)) as pb,
         jsonb_build_object('name', 'C昵称探针', 'avatar', 'basic', 'id', 'g_cccccccccccc_1_x', 'tag', public.player_tag_of(c::text)) as pc
    from _ids;
grant select on _p to public;

insert into public.accounts (account_id, display_name) select a, 'A昵称探针' from _ids union all select b, 'B昵称探针' from _ids;
insert into public.ghosts (account_id, season_week, battles, snapshot, client_version)
  select a, wk, 1, jsonb_build_object('profile', pa, 'leaders', '[]'::jsonb), 't' from _ids, _p
  union all select b, wk, 1, jsonb_build_object('profile', pb, 'leaders', '[]'::jsonb), 't' from _ids, _p
  union all select c, wk, 1, jsonb_build_object('profile', pc, 'leaders', '[]'::jsonb), 't' from _ids, _p;
insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version)
  select a, wk, 0, 0, jsonb_build_object('profile', pa), 't' from _ids, _p
  union all select b, wk, 0, 0, jsonb_build_object('profile', pb), 't' from _ids, _p;
insert into public.saves (account_id, payload, client_version) select a, '{}'::jsonb, 't' from _ids union all select b, '{}'::jsonb, 't' from _ids;
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
  select wk, a, 'A昵称探针', jsonb_build_object('profile', pa), 7, 0 from _ids, _p
  union all select wk, b, 'B昵称探针', jsonb_build_object('profile', pb), 7, 1 from _ids, _p;
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  select wk, 0, 0, a, 'A昵称探针', jsonb_build_object('profile', pa) from _ids, _p
  union all select wk, 0, 1, b, 'B昵称探针', jsonb_build_object('profile', pb) from _ids, _p;
insert into public.finals_scout (season_week, bucket_no, round, account_id, seed) select wk, 0, 1, a, 1 from _ids;
insert into public.client_errors (account_id, day, sig, kind) select a, current_date, 'probe', 'script' from _ids
  union all select b, current_date, 'probe', 'script' from _ids;
insert into public.player_feedback (account_id, kind, message) select a, 'other', 'probe' from _ids;
insert into public.gauntlet_records (season_week, account_id, gw, gl) select wk, a, 1, 0 from _ids;
-- 录像：m1 = A 自己打的（A 在左）；m2 = B 打的、A 是对手（右，right_account 恒 null）；m3 = B 对 C（对照）
insert into public.matches (match_id, season_week, phase, left_account, right_account, seed, left_snapshot, right_snapshot, result, client_version)
  select '00000000-0000-4000-8000-0000000000a1'::uuid, wk, 'gauntlet', a, null::uuid, 1, jsonb_build_object('profile', pa), jsonb_build_object('profile', pb), '{}'::jsonb, 't' from _ids, _p
  union all select '00000000-0000-4000-8000-0000000000a2'::uuid, wk, 'gauntlet', b, null, 2, jsonb_build_object('profile', pb), jsonb_build_object('profile', pa), '{}'::jsonb, 't' from _ids, _p
  union all select '00000000-0000-4000-8000-0000000000a3'::uuid, wk, 'gauntlet', b, null, 3, jsonb_build_object('profile', pb), jsonb_build_object('profile', pc), '{}'::jsonb, 't' from _ids, _p;
-- 直播：L1 = B 正在打 A 的快照；L2 = A 自己正在打
insert into public.live_matches (match_id, season_week, account_id, phase, left_snapshot, right_snapshot, replay, client_version)
  select '00000000-0000-4000-8000-0000000000b1'::uuid, wk, b, 'gauntlet', jsonb_build_object('profile', pb), jsonb_build_object('profile', pa), 'AAAA', 't' from _ids, _p
  union all select '00000000-0000-4000-8000-0000000000b2'::uuid, wk, a, 'gauntlet', jsonb_build_object('profile', pa), jsonb_build_object('profile', pb), 'AAAA', 't' from _ids, _p;
-- 裁判任务：J1 = A 的周六任务（待算）；J2 = 周日 B 对 A；J3 = B 的周六任务、对手快照是 A；J4 = B 对 C（对照）
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, meta, status)
  select 'gauntlet', 'probe20261020b:j1:' || a, wk, 't', 11, a, null::uuid, jsonb_build_object('profile', pa), jsonb_build_object('profile', pc), jsonb_build_object('account', a::text), 'pending' from _ids, _p
  union all select 'finals', 'probe20261020b:j2:' || a, wk, 't', 12, b, a, jsonb_build_object('profile', pb), jsonb_build_object('profile', pa), '{}'::jsonb, 'pending' from _ids, _p
  union all select 'gauntlet', 'probe20261020b:j3:' || a, wk, 't', 13, b, null, jsonb_build_object('profile', pb), jsonb_build_object('profile', pa), jsonb_build_object('account', b::text), 'pending' from _ids, _p
  union all select 'gauntlet', 'probe20261020b:j4:' || a, wk, 't', 14, b, null, jsonb_build_object('profile', pb), jsonb_build_object('profile', pc), jsonb_build_object('account', b::text), 'pending' from _ids, _p;
insert into public.referee_restream (match_id, job_id, client_version, requested_by)
  select '00000000-0000-4000-8000-0000000000c1'::uuid, (select job_id from public.referee_jobs where match_key = 'probe20261020b:j2:' || a), 't', a from _ids;
-- 举报：A→B、B→A、C→A（都与 A 有关，删号后应消失）；C→B（对照，保留）
insert into public.nickname_reports (reporter, reported_tag, reported_account, name_snapshot)
  select a, pb->>'tag', b, 'B昵称探针' from _ids, _p
  union all select b, pa->>'tag', a, 'A昵称探针' from _ids, _p
  union all select c, pa->>'tag', null::uuid, 'A昵称探针' from _ids, _p
  union all select c, pb->>'tag', b, 'B昵称探针' from _ids, _p;

create temp table _before as
  select (select count(*) from public.matches where season_week = (select wk from _ids)) as m,
         (select count(*) from public.finals_entrants where season_week = (select wk from _ids)) as fe,
         (select count(*) from public.referee_jobs where season_week = (select wk from _ids)) as rj;

-- ── D6 没登录 / anon ──
select pg_temp.as_user(null);
create temp table _r0 as select public.account_delete_self() as r;
select pg_temp.ck('D6 没登录 ⇒ not_signed_in', (select r->>'reason' from _r0) = 'not_signed_in', (select r::text from _r0));
select pg_temp.ck('D6 anon 没有执行权', not has_function_privilege('anon', 'public.account_delete_self()', 'execute'));
select pg_temp.ck('D6 authenticated 有执行权', has_function_privilege('authenticated', 'public.account_delete_self()', 'execute'));
select pg_temp.ck('D6 anon 不能举报', not has_function_privilege('anon', 'public.report_nickname(text, text, text)', 'execute'));
select pg_temp.ck('D6 authenticated 不能处理举报', not has_function_privilege('authenticated', 'public.nickname_report_resolve(text, text)', 'execute'));
select pg_temp.ck('D6 authenticated 不能读待处理视图', not has_table_privilege('authenticated', 'public.nickname_reports_pending', 'select'));
select pg_temp.ck('D6 authenticated 不能直读举报表', not has_table_privilege('authenticated', 'public.nickname_reports', 'select'));

-- ── 以 A 的身份删号 ──
select pg_temp.as_user((select a from _ids));
create temp table _r1 as select public.account_delete_self() as r;
select pg_temp.as_user(null);

select pg_temp.ck('D1 回 ok', (select (r->>'ok')::boolean from _r1), (select r::text from _r1));
select pg_temp.ck('D1 A 的 auth 用户没了', not exists (select 1 from auth.users where id = (select a from _ids)));
select pg_temp.ck('D1 对照: B / C 还在', (select count(*) from auth.users where id in ((select b from _ids), (select c from _ids))) = 2);

select pg_temp.ck('D2 ghosts: A 0 行 / B 还在',
  not exists (select 1 from public.ghosts where account_id = (select a from _ids))
  and exists (select 1 from public.ghosts where account_id = (select b from _ids)));
select pg_temp.ck('D2 gauntlet_ghosts / saves / accounts / finals_pending / client_errors: A 全 0 行',
  not exists (select 1 from public.gauntlet_ghosts where account_id = (select a from _ids))
  and not exists (select 1 from public.saves where account_id = (select a from _ids))
  and not exists (select 1 from public.accounts where account_id = (select a from _ids))
  and not exists (select 1 from public.finals_pending where account_id = (select a from _ids))
  and not exists (select 1 from public.client_errors where account_id = (select a from _ids)));
select pg_temp.ck('D2 player_feedback / gauntlet_records / finals_scout: A 全 0 行',
  not exists (select 1 from public.player_feedback where account_id = (select a from _ids))
  and not exists (select 1 from public.gauntlet_records where account_id = (select a from _ids))
  and not exists (select 1 from public.finals_scout where account_id = (select a from _ids)));
select pg_temp.ck('D2 对照: B 的 saves / finals_pending / client_errors 还在',
  exists (select 1 from public.saves where account_id = (select b from _ids))
  and exists (select 1 from public.finals_pending where account_id = (select b from _ids))
  and exists (select 1 from public.client_errors where account_id = (select b from _ids)));
select pg_temp.ck('D2 A 自己的直播行没了 / B 的还在',
  not exists (select 1 from public.live_matches where match_id = '00000000-0000-4000-8000-0000000000b2')
  and exists (select 1 from public.live_matches where match_id = '00000000-0000-4000-8000-0000000000b1'));

select pg_temp.ck('D3 matches / finals_entrants / referee_jobs 行数不变',
  (select count(*) from public.matches where season_week = (select wk from _ids)) = (select m from _before)
  and (select count(*) from public.finals_entrants where season_week = (select wk from _ids)) = (select fe from _before)
  and (select count(*) from public.referee_jobs where season_week = (select wk from _ids)) = (select rj from _before));
select pg_temp.ck('D3 m1 左方(A) 换成占位、left_account 断开',
  (select left_snapshot->'profile'->>'name' = '已注销玩家' and left_snapshot->'profile'->>'avatar' = 'basic'
          and left_account is null from public.matches where match_id = '00000000-0000-4000-8000-0000000000a1'));
select pg_temp.ck('D3 m1 右方(B) 一字不动',
  (select right_snapshot->'profile' = (select pb from _p) from public.matches where match_id = '00000000-0000-4000-8000-0000000000a1'));
select pg_temp.ck('D3 m2 右方(A 当对手) 换成占位、左方(B) 一字不动',
  (select right_snapshot->'profile'->>'name' = '已注销玩家' and left_snapshot->'profile' = (select pb from _p)
     from public.matches where match_id = '00000000-0000-4000-8000-0000000000a2'));
select pg_temp.ck('D3 m3(B 对 C) 一字不动',
  (select left_snapshot->'profile' = (select pb from _p) and right_snapshot->'profile' = (select pc from _p)
     from public.matches where match_id = '00000000-0000-4000-8000-0000000000a3'));
select pg_temp.ck('D3 占位玩家 ID: 格式合法、不是 A 原来的号、同一次删号各行一致',
  (select count(distinct t) = 1 and bool_and(t ~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$') and bool_and(t <> (select pa->>'tag' from _p))
     from (select left_snapshot->'profile'->>'tag' as t from public.matches where match_id = '00000000-0000-4000-8000-0000000000a1'
           union all select right_snapshot->'profile'->>'tag' from public.matches where match_id = '00000000-0000-4000-8000-0000000000a2'
           union all select right_snapshot->'profile'->>'tag' from public.live_matches where match_id = '00000000-0000-4000-8000-0000000000b1') s));
select pg_temp.ck('D3 L1(B 在打 A 的快照) 右方换成占位、左方不动',
  (select right_snapshot->'profile'->>'name' = '已注销玩家' and left_snapshot->'profile' = (select pb from _p)
     from public.live_matches where match_id = '00000000-0000-4000-8000-0000000000b1'));
select pg_temp.ck('D3 finals_entrants: A 的种子位还在、名字与快照换成占位、账号断开',
  (select account_id is null and name = '已注销玩家' and snapshot->'profile'->>'name' = '已注销玩家'
     from public.finals_entrants where season_week = (select wk from _ids) and seed = 0));
select pg_temp.ck('D3 finals_entrants 对照: B 一字不动',
  (select account_id = (select b from _ids) and name = 'B昵称探针' and snapshot->'profile' = (select pb from _p)
     from public.finals_entrants where season_week = (select wk from _ids) and seed = 1));
select pg_temp.ck('D3 J2(周日 B 对 A): b 方换成占位、b_account 断开、a 方不动',
  (select b_account is null and b_snapshot->'profile'->>'name' = '已注销玩家' and a_snapshot->'profile' = (select pb from _p)
     from public.referee_jobs where match_key = 'probe20261020b:j2:' || (select a from _ids)));
select pg_temp.ck('D3 J3(B 的周六局、对手快照是 A): b 方换成占位, 任务照常 pending',
  (select b_snapshot->'profile'->>'name' = '已注销玩家' and status = 'pending'
     from public.referee_jobs where match_key = 'probe20261020b:j3:' || (select a from _ids)));
select pg_temp.ck('D3 J4(B 对 C) 一字不动',
  (select a_snapshot->'profile' = (select pb from _p) and b_snapshot->'profile' = (select pc from _p) and status = 'pending'
     from public.referee_jobs where match_key = 'probe20261020b:j4:' || (select a from _ids)));
select pg_temp.ck('D3 全库搜不到 A 的昵称原文',
  not exists (select 1 from public.matches where (left_snapshot::text || right_snapshot::text) like '%A昵称探针%')
  and not exists (select 1 from public.live_matches where (left_snapshot::text || right_snapshot::text) like '%A昵称探针%')
  and not exists (select 1 from public.referee_jobs where (a_snapshot::text || b_snapshot::text) like '%A昵称探针%')
  and not exists (select 1 from public.finals_entrants where name = 'A昵称探针' or snapshot::text like '%A昵称探针%')
  and not exists (select 1 from public.finals_pending where name = 'A昵称探针')
  and not exists (select 1 from public.nickname_reports where name_snapshot = 'A昵称探针'));
select pg_temp.ck('D3 全库搜不到 A 的玩家 ID',
  not exists (select 1 from public.matches where (left_snapshot::text || right_snapshot::text) like '%' || (select pa->>'tag' from _p) || '%')
  and not exists (select 1 from public.live_matches where (left_snapshot::text || right_snapshot::text) like '%' || (select pa->>'tag' from _p) || '%')
  and not exists (select 1 from public.referee_jobs where (a_snapshot::text || b_snapshot::text) like '%' || (select pa->>'tag' from _p) || '%'));
select pg_temp.ck('D3 分母: 占位真的写进去了(不是因为行没了才搜不到)',
  (select count(*) from public.matches where (left_snapshot::text || right_snapshot::text) like '%已注销玩家%' and season_week = (select wk from _ids)) = 2);
select pg_temp.ck('D4 A 的周六任务作废、meta 不再带账号',
  (select status = 'failed' and error = 'account_deleted' and a_account is null and not (meta ? 'account')
     from public.referee_jobs where match_key = 'probe20261020b:j1:' || (select a from _ids)));
select pg_temp.ck('D4 补流请求人断开', (select requested_by is null from public.referee_restream where match_id = '00000000-0000-4000-8000-0000000000c1'));
select pg_temp.ck('D5 与 A 有关的举报全删、C→B 保留',
  (select count(*) from public.nickname_reports where reporter in ((select a from _ids), (select b from _ids), (select c from _ids))) = 1
  and exists (select 1 from public.nickname_reports where reporter = (select c from _ids) and reported_tag = (select pb->>'tag' from _p)));

-- ── 举报 ──
select pg_temp.as_user((select b from _ids));
create temp table _rr as
  select 1 as k, public.report_nickname((select pc->>'tag' from _p), 'C昵称探针', 'leaderboard') as r
  union all select 2, public.report_nickname((select pc->>'tag' from _p), 'C昵称探针', 'battle')
  union all select 3, public.report_nickname((select pb->>'tag' from _p), 'B昵称探针', 'bracket')
  union all select 4, public.report_nickname('#AAAAAA', 'x', 'bracket')
  union all select 5, public.report_nickname('#2345678', 'x', 'bracket')
  union all select 6, public.report_nickname((select pa->>'tag' from _p), '   ', 'bracket');
select pg_temp.ck('R1 第一次举报成功', (select (r->>'ok')::boolean from _rr where k = 1), (select r::text from _rr where k = 1));
select pg_temp.ck('R2 24 小时内重复 ⇒ duplicate', (select r->>'reason' from _rr where k = 2) = 'duplicate', (select r::text from _rr where k = 2));
select pg_temp.ck('R3 举报自己 ⇒ self', (select r->>'reason' from _rr where k = 3) = 'self', (select r::text from _rr where k = 3));
select pg_temp.ck('R4 ID 含字母表外的字 / 长度不对 ⇒ bad_tag',
  (select r->>'reason' from _rr where k = 4) = 'bad_tag' and (select r->>'reason' from _rr where k = 5) = 'bad_tag');
select pg_temp.ck('R5 空名字 ⇒ bad_name', (select r->>'reason' from _rr where k = 6) = 'bad_name');
select pg_temp.ck('R6 账号反查到 C、昵称快照与场景记下了',
  (select reported_account = (select c from _ids) and name_snapshot = 'C昵称探针' and context = 'leaderboard' and status = 'pending'
     from public.nickname_reports where reporter = (select b from _ids) and reported_tag = (select pc->>'tag' from _p)));
select pg_temp.ck('R6 分母: B 只写进去 1 行', (select count(*) from public.nickname_reports where reporter = (select b from _ids)) = 1);
-- R7 每日上限：B 再举报 19 个不同的号（共 20），第 21 个被拒
select pg_temp.as_user((select b from _ids));
create temp table _rl as
  select g, public.report_nickname(public.player_tag_of('probe-limit-' || g), '名' || g, '') as r from generate_series(1, 20) g;
select pg_temp.ck('R7 第 2~20 条成功、第 21 条 ⇒ limit',
  (select count(*) from _rl where (r->>'ok')::boolean) = 19 and (select r->>'reason' from _rl where g = 20) = 'limit',
  (select string_agg(coalesce(r->>'reason', 'ok'), ',' order by g) from _rl));
-- R8 管理侧
select pg_temp.ck('R8 待处理视图里有 C 那一条(1 人举报)',
  (select reporters = 1 and latest_name = 'C昵称探针' and reported_account = (select c from _ids)
     from public.nickname_reports_pending where reported_tag = (select pc->>'tag' from _p)));
create temp table _rs as select public.nickname_report_resolve((select pc->>'tag' from _p), 'reset') as r;
select pg_temp.ck('R8 处理 reset 回 ok', (select (r->>'ok')::boolean from _rs), (select r::text from _rs));
select pg_temp.ck('R8 nickname_resets 记下 (C, 原名)',
  exists (select 1 from public.nickname_resets where account_id = (select c from _ids) and banned_name = 'C昵称探针'));
select pg_temp.ck('R8 C 的快照名字换成「玩家 + ID」、m3 右方也换了',
  (select snapshot->'profile'->>'name' from public.ghosts where account_id = (select c from _ids)) = '玩家' || substr((select pc->>'tag' from _p), 2)
  and (select right_snapshot->'profile'->>'name' from public.matches where match_id = '00000000-0000-4000-8000-0000000000a3') = '玩家' || substr((select pc->>'tag' from _p), 2));
select pg_temp.ck('R8 对照: B 的快照名字没动',
  (select snapshot->'profile'->>'name' from public.ghosts where account_id = (select b from _ids)) = 'B昵称探针');
select pg_temp.ck('R8 举报标成 reset、视图里不再有它',
  (select status from public.nickname_reports where reporter = (select b from _ids) and reported_tag = (select pc->>'tag' from _p)) = 'reset'
  and not exists (select 1 from public.nickname_reports_pending where reported_tag = (select pc->>'tag' from _p)));
select pg_temp.as_user((select c from _ids));
create temp table _mr as select public.my_nickname_reset() as r;
select pg_temp.as_user(null);
select pg_temp.ck('R8 C 开机查得到自己被重置的名字', (select r->'names' = '["C昵称探针"]'::jsonb from _mr), (select r::text from _mr));
create temp table _rd as select public.nickname_report_resolve(public.player_tag_of('probe-limit-1'), 'dismiss') as r;
select pg_temp.ck('R8 dismiss: 只标记、不记重置',
  (select r->>'action' from _rd) = 'dismiss'
  and (select status from public.nickname_reports where reported_tag = public.player_tag_of('probe-limit-1')) = 'dismissed');

-- ── 结论：一定抛异常 ⇒ 整个事务回滚 ──
do $$
declare nf int; nt int; msg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
