-- 20261020c 周六对手由服务端挑 + 服务器局发战斗内铸币 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：node tools/sql_sandbox.mjs server/supabase/migrations/20261020c_gauntlet_server_pick_and_coins.sql \
--             server/supabase/tests/20261020c_gauntlet_server_pick_and_coins_check.sql
--   · 内测服 / 生产（迁移执行之后；生产要用户同意）：SQL 编辑器整段粘贴运行。
--     ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 整个事务回滚，造的账号 / 配置改动 / 任务 / 池子一个都不留。
-- 判据（每条配对照组）：
--   P1 挑不到任何对手 ⇒ no_opponent（不建任务）
--   P2 池子上传：合法行入池、坏行（统领两路各一次）拒收；版本登记上 rules_ver；只有 service_role 能调
--   P3 没有同标签真人 ⇒ 机器人：任务建好、b_account 空、种子合法、快照去掉 origin、gl_ts 落在「现在往前 60~1500 秒」、
--      卡片 = profile{name, avatar, id, tag} + 三统领（不带其他键）、回包里没有任何「机器人」字样
--   P4 在算的那一场再点 ⇒ 同一任务、同一对手（不重挑）
--   C1 写回 coins = 7 ⇒ 账本 7、job_status 回 7；matches.result 里没有 coins；gauntlet_ghosts 那一行 rules_ver = 1
--   C2 coins 越界 / 负数 / 字符串 ⇒ 0；小数 ⇒ 向下取整
--   P5 第几场对不上 ⇒ stale + 账本 gw / gl（不建任务）
--   P6 同标签真人：30 分钟内的优先于隔夜的；本周碰过的不再挑；规则版本不同 / 标签不同 / 自己 / 分路坏的永远不挑；
--      真人快照去掉 origin；b_account = 真人账号
--   P7 机器人强度：积分赛场次地板（ghosts 里的场次 + 周六已打）、快照自报只能往上抬；超过 30 场用 30 那一格且 season_total_battles = 真实场次
--   P8 失败重交：种子 / 对手 / 我的阵容都不换；对手快照坏了（b_bad_snapshot）才重挑、旧的进 opp_prev
--   P9 旧接口：开关关 ⇒ 照旧收（对照）；开 ⇒ update_required
--   P10 规则版本对不上 / 版本没登记 ⇒ update_required；阵容坏 ⇒ bad_snapshot；打满 ⇒ finished
--   G  权限：referee_gauntlet_start 只给 authenticated；pick / 池子上传 / 卡片函数客户端调不了
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as h, gen_random_uuid() as h2, gen_random_uuid() as x,
         extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint as wk;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ids to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 一份快照（与 build_ghost_snapshot 同形的最小子集）。l3 在下路，l1 / l2 在上路。
create or replace function pg_temp.snap(p_name text, l1 text, l2 text, l3 text, p_battles int default 13) returns jsonb
language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array(l1, l2, l3),
    'lane_assign', jsonb_build_object('top', jsonb_build_array(l1, l2), 'bottom', jsonb_build_array(l3)),
    'profile', jsonb_build_object('name', p_name, 'avatar', l1, 'id', 'g_' || p_name, 'tag', '#' || upper(p_name), 'extra', 'x'),
    'season_total_battles', p_battles, 'origin', 'local', 'season_level', 5)
$$;
create or replace function pg_temp.start(p_snap jsonb, p_no int, p_ver text default '9.9.9', p_rv int default 1) returns jsonb
language sql as $$
  select public.referee_gauntlet_start((select wk from _ids), p_snap, p_no, p_ver, p_rv)
$$;

-- ── 造数据 ──
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select a, 'authenticated', 'authenticated', true, now() from _ids
  union all select h, 'authenticated', 'authenticated', false, now() from _ids
  union all select h2, 'authenticated', 'authenticated', false, now() from _ids
  union all select x, 'authenticated', 'authenticated', false, now() from _ids;
update public.referee_config set gauntlet_on = true, gauntlet_any_day = true, gauntlet_server_pick = false where id = 1;
insert into public.referee_versions (client_version, enabled) values ('9.9.9', true)
  on conflict (client_version) do update set enabled = true, rules_ver = null;
delete from public.gauntlet_bot_pool;

-- P1 ─ 没有池子、没有真人 ⇒ no_opponent
select pg_temp.as_user((select a from _ids));
select pg_temp.ck('P1 什么都挑不到 ⇒ no_opponent',
  (pg_temp.start(pg_temp.snap('amy', 'basic', 'stone', 'bamboo'), 0))->>'reason' = 'no_opponent');
select pg_temp.ck('P1 没建任务', (select count(*) from public.referee_jobs where a_account = (select a from _ids)) = 0);

-- P2 ─ 上传池子（service_role 的函数；这里直接调 = 运维 / 轮询器那一侧）
create temp table _pool as
  select b, gw, gl, v from generate_series(0, 30) b, generate_series(0, 3) gw, generate_series(0, 2) gl, generate_series(0, 2) v
   where gw + gl <= b;
create temp table _load as
  select public.referee_bot_pool_load('9.9.9', 1,
    (select jsonb_agg(jsonb_build_object('battles', b, 'gw', gw, 'gl', gl, 'variant', v,
       'snapshot', pg_temp.snap(format('bot%s_%s_%s_%s', b, gw, gl, v), 'ninja', 'dice', 'pirate', b)
                   || jsonb_build_object('is_bot', true, 'ghost_id', format('bot_%s_%s', b, v), 'gl_ts', 1, 'origin', 'remote')))
       from _pool)
    || jsonb_build_array(jsonb_build_object('battles', 1, 'gw', 0, 'gl', 0, 'variant', 9,
         'snapshot', jsonb_build_object('leaders', jsonb_build_array('a', 'b', 'c'),
           'lane_assign', jsonb_build_object('top', jsonb_build_array('a', 'b'), 'bottom', jsonb_build_array('a'))))),
    true) as r;
select pg_temp.ck('P2 合法行全部入池、坏行（a 两路各一次）拒收',
  ((select r from _load)->>'loaded')::int = (select count(*) from _pool) and ((select r from _load)->>'rejected')::int = 1,
  (select r::text from _load));
select pg_temp.ck('P2 版本登记上 rules_ver = 1', (select rules_ver from public.referee_versions where client_version = '9.9.9') = 1);
select pg_temp.ck('P2 入池时去掉 origin / gl_ts', not exists (select 1 from public.gauntlet_bot_pool where snapshot ? 'origin' or snapshot ? 'gl_ts'));

-- P3 ─ 机器人
select pg_temp.as_user((select a from _ids));
create temp table _s1 as select pg_temp.start(pg_temp.snap('amy', 'basic', 'stone', 'bamboo'), 0) as r;
create temp table _j1 as select * from public.referee_jobs where job_id = ((select r from _s1)->>'job_id')::bigint;
select pg_temp.ck('P3 建了任务（ok + 任务号 + 录像号）', ((select r from _s1)->>'ok')::boolean and (select count(*) from _j1) = 1,
  (select r::text from _s1));
select pg_temp.ck('P3 挑的是机器人、b_account 空', (select meta->>'pick' from _j1) = 'bot' and (select b_account from _j1) is null
  and (select meta->>'opp' from _j1) like 'bot:1:%:0:0:%');
select pg_temp.ck('P3 种子由服务端定、在 1..2^53-1', (select seed from _j1) between 1 and 9007199254740991);
select pg_temp.ck('P3 对手快照去掉 origin、带 is_bot / ghost_id（只在任务行；出站两条路照旧摘掉）',
  not ((select b_snapshot from _j1) ? 'origin') and (select b_snapshot from _j1) ? 'is_bot');
select pg_temp.ck('P3 gl_ts = 现在往前 60~1500 秒（真人口径）',
  ((select b_snapshot->>'gl_ts' from _j1)::bigint between extract(epoch from now())::bigint - 1500 and extract(epoch from now())::bigint - 60),
  (select b_snapshot->>'gl_ts' from _j1));
select pg_temp.ck('P3 卡片 = profile{name, avatar, id, tag} + 三统领',
  (select jsonb_object_keys_agg from (select jsonb_agg(k order by k) as jsonb_object_keys_agg
     from jsonb_object_keys((select r->'opp'->'profile' from _s1)) k) t) = '["avatar", "id", "name", "tag"]'::jsonb
  and jsonb_array_length((select r->'opp'->'leaders' from _s1)) = 3
  and (select jsonb_agg(k order by k) from jsonb_object_keys((select r->'opp' from _s1)) k) = '["leaders", "profile"]'::jsonb,
  (select (r->'opp')::text from _s1));
select pg_temp.ck('P3 回包里没有「机器人」的痕迹（is_bot / ghost_id / pick / bot:）',
  position('is_bot' in (select r::text from _s1)) = 0 and position('ghost_id' in (select r::text from _s1)) = 0
  and position('"pick"' in (select r::text from _s1)) = 0 and position('bot:' in (select r::text from _s1)) = 0,
  (select r::text from _s1));
select pg_temp.ck('P3 账本上的 gw / gl 一并回（0-0）', ((select r from _s1)->>'gw')::int = 0 and ((select r from _s1)->>'gl')::int = 0);
select pg_temp.ck('P3 任务行记下 rules_ver / battles / server_pick',
  (select (meta->>'rules_ver')::int = 1 and (meta->>'battles')::int = 13 and (meta->>'server_pick')::boolean from _j1));

-- P4 ─ 在算的那一场再点
create temp table _s1b as select pg_temp.start(pg_temp.snap('amy', 'ice', 'stone', 'bamboo'), 0) as r;
select pg_temp.ck('P4 在算 ⇒ 同一任务、同一对手、in_flight',
  ((select r from _s1b)->>'job_id') = ((select r from _s1)->>'job_id') and ((select r from _s1b)->>'in_flight')::boolean
  and (select r->'opp' from _s1b) = (select r->'opp' from _s1));
select pg_temp.ck('P4 阵容没被换掉', (select a_snapshot->'leaders'->>0 from public.referee_jobs where job_id = (select job_id from _j1)) = 'basic');

-- C1 ─ 写回带 coins
create temp table _cl as select public.referee_claim('w1', array['9.9.9'], 5) as r;
select pg_temp.ck('C1 分母: 裁判领到这一份', jsonb_array_length((select r from _cl)) = 1
  and ((select r from _cl)->0->>'job_id')::bigint = (select job_id from _j1));
create or replace function pg_temp.result(p_job bigint, p_coins jsonb) returns jsonb language sql as $$
  select jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', j.seed, 'client_version', j.client_version,
    'winner', 'a', 'steps', 4000, 'score_code', 0, 'replay_b64', 'QUJD') || case when p_coins is null then '{}'::jsonb
      else jsonb_build_object('coins', p_coins) end
  from public.referee_jobs j where j.job_id = p_job
$$;
create temp table _cp1 as select public.referee_complete((select job_id from _j1), 'w1', pg_temp.result((select job_id from _j1), '7'::jsonb)) as r;
select pg_temp.ck('C1 写回成功', ((select r from _cp1)->>'ok')::boolean, (select r::text from _cp1));
select pg_temp.ck('C1 账本 coins = 7', (select (result->'ledger'->>'coins')::int from public.referee_jobs where job_id = (select job_id from _j1)) = 7);
select pg_temp.as_user((select a from _ids));
create temp table _st1 as select public.referee_job_status((select job_id from _j1)) as r;
select pg_temp.ck('C1 job_status 回 coins 7 / 胜 / 1-0', ((select r from _st1)->>'coins')::int = 7
  and ((select r from _st1)->>'won')::boolean and ((select r from _st1)->>'gw')::int = 1 and ((select r from _st1)->>'gl')::int = 0,
  (select r::text from _st1));
select pg_temp.ck('C1 matches.result 里没有 coins（所有登录用户读得到那一行）',
  not ((select result from public.matches where match_id = (select match_id from _j1)) ? 'coins'));
select pg_temp.ck('C1 挂进 gauntlet_ghosts 那一份 rules_ver = 1（原来漏写 = 0）',
  (select rules_ver from public.gauntlet_ghosts where account_id = (select a from _ids) and gw = 1 and gl = 0) = 1);

-- C2 ─ coins 不可信的形状（裁判机的结果单也夹一道）
create or replace function pg_temp.coins_of(p_coins jsonb) returns int language plpgsql as $$
declare jid bigint; mk text := 'chk:' || gen_random_uuid()::text; v int;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, status, claimed_by, claimed_at, meta)
    values ('gauntlet', mk, (select wk from _ids), '9.9.9', 77, null, '{}'::jsonb, '{}'::jsonb, 'claimed', 'w9', now(), '{}'::jsonb)
    returning job_id into jid;
  perform public.referee_complete(jid, 'w9', pg_temp.result(jid, p_coins));
  select (result->'ledger'->>'coins')::int into v from public.referee_jobs where job_id = jid;
  return v;
end $$;
select pg_temp.ck('C2 coins 5000 ⇒ 0', pg_temp.coins_of('5000'::jsonb) = 0);
select pg_temp.ck('C2 coins -3 ⇒ 0', pg_temp.coins_of('-3'::jsonb) = 0);
select pg_temp.ck('C2 coins "7"(字符串) ⇒ 0', pg_temp.coins_of('"7"'::jsonb) = 0);
select pg_temp.ck('C2 coins 3.9 ⇒ 3', pg_temp.coins_of('3.9'::jsonb) = 3);
select pg_temp.ck('C2 没有 coins（老裁判程序）⇒ 0', pg_temp.coins_of(null) = 0);
select pg_temp.ck('C2 对照: coins 12 ⇒ 12', pg_temp.coins_of('12'::jsonb) = 12);

-- P5 ─ 第几场对不上
select pg_temp.as_user((select a from _ids));
create temp table _s5 as select pg_temp.start(pg_temp.snap('amy', 'basic', 'stone', 'bamboo'), 0) as r;
select pg_temp.ck('P5 报第 0 场而账本是 1-0 ⇒ stale + gw 1 / gl 0', (select r->>'reason' from _s5) = 'stale'
  and ((select r from _s5)->>'gw')::int = 1 and ((select r from _s5)->>'gl')::int = 0, (select r::text from _s5));
select pg_temp.ck('P5 没多建任务', (select count(*) from public.referee_jobs where a_account = (select a from _ids)) = 1);

-- P6 ─ 同标签真人（A 现在 1-0）
insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver, uploaded_at) values
  ((select h from _ids), (select wk from _ids), 1, 0, pg_temp.snap('hana', 'angel', 'ice', 'ninja'), '9.9.9', 1, now() - interval '5 minutes'),
  ((select h2 from _ids), (select wk from _ids), 1, 0, pg_temp.snap('hugo', 'angel', 'ice', 'dice'), '9.9.9', 1, now() - interval '3 hours'),
  ((select x from _ids), (select wk from _ids), 1, 0, pg_temp.snap('xold', 'angel', 'ice', 'stone'), '9.9.9', 0, now()),
  ((select x from _ids), (select wk from _ids), 2, 0, pg_temp.snap('xtwo', 'angel', 'ice', 'stone'), '9.9.9', 1, now()),
  ((select x from _ids), (select wk from _ids), 0, 1, jsonb_build_object('leaders', '["a","b","c"]'::jsonb,
     'lane_assign', '{"top":[],"bottom":[]}'::jsonb), '9.9.9', 1, now());
create temp table _picks as
  select public.referee_gauntlet_pick((select a from _ids), (select wk from _ids), 1, 0, 1, 14) as r from generate_series(1, 20);
select pg_temp.ck('P6 30 分钟内的真人优先（20 次全是 hana）', (select count(*) from _picks where r->>'opp' = (select h::text from _ids)) = 20,
  (select string_agg(r->>'opp', ',') from _picks));
select pg_temp.ck('P6 新鲜 ⇒ pick fresh、带 account、去掉 origin',
  (select bool_and(r->>'pick' = 'fresh' and (r->>'account')::uuid = (select h from _ids) and not (r->'snap' ? 'origin')) from _picks));
create temp table _s6 as select pg_temp.start(pg_temp.snap('amy', 'basic', 'stone', 'bamboo'), 1) as r;
create temp table _j6 as select * from public.referee_jobs where job_id = ((select r from _s6)->>'job_id')::bigint;
select pg_temp.ck('P6 开战挑到 hana、b_account = hana、卡片名字 hana', (select b_account from _j6) = (select h from _ids)
  and (select r->'opp'->'profile'->>'name' from _s6) = 'hana' and (select meta->>'pick' from _j6) = 'fresh', (select r::text from _s6));
select pg_temp.ck('P6 卡片不带 profile 里的其他键（extra）', not ((select r->'opp'->'profile' from _s6) ? 'extra'));
create temp table _p6b as select public.referee_gauntlet_pick((select a from _ids), (select wk from _ids), 1, 0, 1, 14) as r;
select pg_temp.ck('P6 本周碰过 hana ⇒ 退到隔夜的 hugo（stale）', (select r->>'opp' from _p6b) = (select h2::text from _ids)
  and (select r->>'pick' from _p6b) = 'stale', (select r::text from _p6b));
select pg_temp.ck('P6 规则版本 0 / 标签 2-0 的 x 永远不挑', not exists (select 1 from _picks where r->>'opp' = (select x::text from _ids))
  and (select r->>'opp' from _p6b) <> (select x::text from _ids));
create temp table _p6c as select public.referee_gauntlet_pick((select a from _ids), (select wk from _ids), 0, 1, 1, 14) as r;
select pg_temp.ck('P6 分路坏的真人（0-1 那一份）不挑 ⇒ 落到机器人', (select r->>'pick' from _p6c) = 'bot', (select r::text from _p6c));
create temp table _p6d as select public.referee_gauntlet_pick((select h from _ids), (select wk from _ids), 1, 0, 1, 14) as r;
select pg_temp.ck('P6 不挑自己（hana 自己找 1-0 ⇒ 不是 hana）', (select r->>'opp' from _p6d) <> (select h::text from _ids));

-- P7 ─ 机器人强度
insert into public.ghosts (account_id, season_week, battles, snapshot, client_version)
  values ((select h2 from _ids), (select wk from _ids), 16, '{}'::jsonb, '9.9.9');
select pg_temp.as_user((select h2 from _ids));
create temp table _s7 as select pg_temp.start(pg_temp.snap('hugo', 'angel', 'ice', 'dice', 3), 0) as r;
select pg_temp.ck('P7 快照自报 3 场、服务端看得到积分赛 16 场 ⇒ 按 16 场挑（不信低报）',
  (select (meta->>'battles')::int from public.referee_jobs where job_id = ((select r from _s7)->>'job_id')::bigint) = 16
  and (select meta->>'opp' from public.referee_jobs where job_id = ((select r from _s7)->>'job_id')::bigint) like 'bot:1:16:0:0:%',
  (select r::text from _s7));
create temp table _p7 as select public.referee_gauntlet_pick((select h2 from _ids), (select wk from _ids), 2, 1, 1, 37) as r;
select pg_temp.ck('P7 37 场 ⇒ 用 30 那一格、season_total_battles 改成 37', (select r->>'opp' from _p7) like 'bot:1:30:2:1:%'
  and ((select r->'snap'->>'season_total_battles' from _p7))::int = 37, (select r::text from _p7));
create temp table _p7b as select public.referee_gauntlet_pick((select h2 from _ids), (select wk from _ids), 2, 1, 1, 22) as r;
select pg_temp.ck('P7 对照: 22 场 ⇒ 22 那一格、season_total_battles 原样 22', (select r->>'opp' from _p7b) like 'bot:1:22:2:1:%'
  and ((select r->'snap'->>'season_total_battles' from _p7b))::int = 22);

-- P8 ─ 失败重交
create temp table _j8 as select * from public.referee_jobs where job_id = ((select r from _s7)->>'job_id')::bigint;
update public.referee_jobs set status = 'failed', error = 'step_cap' where job_id = (select job_id from _j8);
create temp table _s8 as select pg_temp.start(pg_temp.snap('hugo', 'pirate', 'ice', 'dice', 3), 0) as r;
select pg_temp.ck('P8 失败后重交 ⇒ 同一任务、retry、回到 pending', ((select r from _s8)->>'job_id')::bigint = (select job_id from _j8)
  and ((select r from _s8)->>'retry')::boolean and (select status from public.referee_jobs where job_id = (select job_id from _j8)) = 'pending');
select pg_temp.ck('P8 种子 / 对手 / 我的阵容都不换', (select seed = (select seed from _j8) and b_snapshot = (select b_snapshot from _j8)
  and a_snapshot = (select a_snapshot from _j8) from public.referee_jobs where job_id = (select job_id from _j8)));
update public.referee_jobs set status = 'failed', error = 'b_bad_snapshot' where job_id = (select job_id from _j8);
create temp table _s8b as select pg_temp.start(pg_temp.snap('hugo', 'pirate', 'ice', 'dice', 3), 0) as r;
create temp table _j8b as select * from public.referee_jobs where job_id = (select job_id from _j8);
select pg_temp.ck('P8 对手快照坏了 ⇒ 重挑（换了一份）、旧的进 opp_prev、种子不换',
  (select meta->>'opp' from _j8b) <> (select meta->>'opp' from _j8) and (select meta->'opp_prev' from _j8b) ? (select meta->>'opp' from _j8)
  and (select seed from _j8b) = (select seed from _j8), (select meta::text from _j8b));
update public.referee_jobs set status = 'failed', error = 'a_bad_snapshot' where job_id = (select job_id from _j8);
create temp table _s8c as select pg_temp.start(pg_temp.snap('hugo', 'pirate', 'ice', 'dice', 3), 0) as r;
select pg_temp.ck('P8 我的阵容坏了 ⇒ 换成新交的那份（pirate）',
  (select a_snapshot->'leaders'->>0 from public.referee_jobs where job_id = (select job_id from _j8)) = 'pirate');

-- P9 ─ 旧接口
select pg_temp.as_user((select x from _ids));
create temp table _l1 as select public.referee_submit_gauntlet((select wk from _ids), pg_temp.snap('xena', 'basic', 'stone', 'bamboo'),
  pg_temp.snap('weak', 'basic', 'stone', 'bamboo'), '9.9.9') as r;
select pg_temp.ck('P9 对照: 开关关 ⇒ 旧接口照旧收', ((select r from _l1)->>'ok')::boolean, (select r::text from _l1));
update public.referee_config set gauntlet_server_pick = true where id = 1;
delete from public.referee_jobs where a_account = (select x from _ids);
create temp table _l2 as select public.referee_submit_gauntlet((select wk from _ids), pg_temp.snap('xena', 'basic', 'stone', 'bamboo'),
  pg_temp.snap('weak', 'basic', 'stone', 'bamboo'), '9.9.9') as r;
select pg_temp.ck('P9 开关开 ⇒ 旧接口 update_required、不建任务', (select r->>'reason' from _l2) = 'update_required'
  and (select count(*) from public.referee_jobs where a_account = (select x from _ids)) = 0, (select r::text from _l2));
create temp table _l3 as select pg_temp.start(pg_temp.snap('xena', 'basic', 'stone', 'bamboo'), 0) as r;
select pg_temp.ck('P9 开关开 ⇒ 新接口照常', ((select r from _l3)->>'ok')::boolean, (select r::text from _l3));

-- P10 ─ 拒收
select pg_temp.as_user((select h from _ids));
select pg_temp.ck('P10 规则版本 2 ≠ 登记的 1 ⇒ update_required',
  (pg_temp.start(pg_temp.snap('hana', 'angel', 'ice', 'ninja'), 0, '9.9.9', 2))->>'reason' = 'update_required');
select pg_temp.ck('P10 版本没登记 ⇒ update_required',
  (pg_temp.start(pg_temp.snap('hana', 'angel', 'ice', 'ninja'), 0, '0.0.1', 1))->>'reason' = 'update_required');
select pg_temp.ck('P10 统领两路各一次 ⇒ bad_snapshot', (pg_temp.start(jsonb_build_object('leaders', '["a","b","c"]'::jsonb,
  'lane_assign', '{"top":["a","b"],"bottom":["a"]}'::jsonb), 0))->>'reason' = 'bad_snapshot');
select pg_temp.ck('P10 统领重复 ⇒ bad_snapshot', (pg_temp.start(jsonb_build_object('leaders', '["a","a","c"]'::jsonb,
  'lane_assign', '{"top":["a"],"bottom":["c"]}'::jsonb), 0))->>'reason' = 'bad_snapshot');
insert into public.gauntlet_records (season_week, account_id, gw, gl) values ((select wk from _ids), (select h from _ids), 4, 1)
  on conflict (season_week, account_id) do update set gw = 4, gl = 1;
select pg_temp.ck('P10 4 胜 ⇒ finished', (pg_temp.start(pg_temp.snap('hana', 'angel', 'ice', 'ninja'), 5))->>'reason' = 'finished');
select pg_temp.as_user(null);
select pg_temp.ck('P10 没登录 ⇒ not_signed_in', (pg_temp.start(pg_temp.snap('hana', 'angel', 'ice', 'ninja'), 0))->>'reason' = 'not_signed_in');

-- G ─ 权限
select pg_temp.ck('G 新接口: authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.referee_gauntlet_start(bigint, jsonb, int, text, int)', 'execute')
  and not has_function_privilege('anon', 'public.referee_gauntlet_start(bigint, jsonb, int, text, int)', 'execute'));
select pg_temp.ck('G 挑对手 / 卡片 / 阵容判据: 客户端调不了',
  not has_function_privilege('authenticated', 'public.referee_gauntlet_pick(uuid, bigint, int, int, int, int)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_opp_card(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_lineup_ok(jsonb)', 'execute'));
select pg_temp.ck('G 池子上传只有 service_role',
  has_function_privilege('service_role', 'public.referee_bot_pool_load(text, int, jsonb, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_bot_pool_load(text, int, jsonb, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.referee_bot_pool_load(text, int, jsonb, boolean)', 'execute'));
select pg_temp.ck('G 机器人池表客户端读不到（开了 RLS、没有策略）',
  (select relrowsecurity from pg_class where oid = 'public.gauntlet_bot_pool'::regclass)
  and not exists (select 1 from pg_policies where tablename = 'gauntlet_bot_pool'));
select pg_temp.ck('G 监控回机器人池行数', exists (select 1 from jsonb_array_elements(public.referee_backlog()->'bot_pool') e
  where e->>'client_version' = '9.9.9' and (e->>'rows')::int = (select count(*) from _pool)));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 45 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
