-- 20261101e 观众看「本周晋级名单」 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261101e_finals_qualified_list
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261101e_finals_qualified_list
-- 时间：本事务内 env = beta、删「正式服偏移恒 0」约束、偏移拨 +3 周 ⇒ app_now() 与 now() 差 3 周，分得清回包的 now 用的是哪个钟。
-- 周：W =「真实那一周 + 3 周」；W+1 周放一个别周的报名；W+2 周放 300 人验上限。三周都是空周（生产演练不碰真数据）。
-- 造人（W 周）：p1 Alpha 5 胜 1 负（tag #CHKA01）/ p2 Bravo 6 胜 2 负（快照里还是旧名字）/ p3 Charlie 5 胜 0 负（快照没有 tag）
--   ⇒ 种子顺序 Bravo, Charlie, Alpha（与报名先后 / 名字字母序 / 只看负场 都不同）；
--   p6 Delta 5 胜 1 负（与 Alpha 同胜同负、报名更晚、account_id 最小）后加，验平手怎么排；
--   p4 Echo 只在 W+1 周（9 胜：混进来就排第一）；p5 观众（没报名）。
-- 判据：
--   A1 未登录 ⇒ 恰好 {ok:false, reason:not_signed_in}
--   A2 分母: ok、week = W、n = 3、list 3 行
--   A3 ★顺序 = gw desc, gl asc（Bravo, Charlie, Alpha）
--   A4 ★me 只在自己那一行为 true（p1 看：只有 Alpha；观众 p5 看：全 false）
--   A5 ★键集：顶层恰好 {ok, week, now, seated, n, list}、每行恰好 {name, tag, avatar, gw, gl, me}；
--      回包文本里没有任何人的 account_id、没有 snapshot / leaders / lane_assign
--   A6 name 取 finals_pending.name（不是快照里的旧名）；tag / avatar 取快照 profile，没有 tag 给 ''
--   A7 now = app_now() 的 epoch 秒（不是 now()）；各键的 json 类型
--   W1 ★别周的报名不混进来；查别周只看到别周那一个、seated 按周算
--   L2 ★同胜同负按 account_id：Delta 排在 Alpha 前（报名更晚 ⇒ 若按 entered_at 会反过来）
--   S1 ★seated：finals_seat 之前 false、之后 true（n 仍 4）；名单顺序 = finals_seat 实际排出的种子顺序（≤ 8 人一人一组 ⇒ 组号 = 名次）
--   L1 上限 256 行：W+2 周 300 人 ⇒ n = 300、list 256 行、是排在最前的那 256 个
--   P1 ★权限：anon 没有 execute（以 anon 身份真调被拒）、public 没有、authenticated 有
--   P2 以 authenticated 身份真调：直接查表看不到别人（RLS / 没授权），函数照样数到全部人、不下发阵容
--   P3 security definer / stable / search_path = public / 返回 jsonb
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ppl (i int primary key, id uuid not null);
create temp table _r (k text primary key, v jsonb);
create temp table _big (i int primary key, id uuid not null);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant all on _ppl to public;
grant all on _r to public;
grant all on _big to public;
select set_config('chk.wk', (extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint + 3 * 604800)::text, true);

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.wk() returns bigint language sql as $$ select current_setting('chk.wk')::bigint $$;
create or replace function pg_temp.uid(p_i int) returns uuid language sql as $$ select id from _ppl where i = p_i $$;
create or replace function pg_temp.snap(p_name text, p_tag text, p_avatar text) returns jsonb language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array('basic', 'stone', 'bamboo'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('basic', 'stone'), 'bottom', jsonb_build_array('bamboo')),
    'profile', jsonb_strip_nulls(jsonb_build_object('name', p_name, 'avatar', p_avatar, 'tag', p_tag)), 'season_level', 5)
$$;
-- 以 p_uid 的身份调一次（null = 未登录），回包记进 _r
create or replace function pg_temp.call(p_key text, p_uid uuid, p_week bigint) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user(p_uid);
  v := public.finals_qualified_list(p_week);
  perform pg_temp.as_user(null);
  insert into _r (k, v) values (p_key, v) on conflict (k) do update set v = excluded.v;
  return v;
end $$;
create or replace function pg_temp.r(p_key text) returns jsonb language sql as $$ select v from _r where k = p_key $$;
create or replace function pg_temp.names(p jsonb) returns text language sql as $$
  select coalesce(string_agg(e->>'name', ',' order by o), '')
    from jsonb_array_elements(coalesce(p->'list', '[]'::jsonb)) with ordinality t(e, o)
$$;
create or replace function pg_temp.row_of(p jsonb, p_name text) returns jsonb language sql as $$
  select e from jsonb_array_elements(coalesce(p->'list', '[]'::jsonb)) e where e->>'name' = p_name limit 1
$$;

-- ── 造数据 ──
update public.service_env set env = 'beta' where id = 1;
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.server_clock set offset_sec = 3 * 604800 where id = 1;
insert into _ppl (i, id) select g, gen_random_uuid() from generate_series(1, 5) g;
-- p6 的 account_id 定死成最小 ⇒ 与 Alpha 平手时按 account_id 必排在前
insert into _ppl (i, id) values (6, '00000000-0000-4000-8000-0000000000e1');
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _ppl;
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl, entered_at) values
  (pg_temp.wk(), pg_temp.uid(1), 'Alpha', pg_temp.snap('Alpha', '#CHKA01', 'basic'), 5, 1, now() - interval '3 hours'),
  (pg_temp.wk(), pg_temp.uid(2), 'Bravo', pg_temp.snap('OldBravo', '#CHKB02', 'stone'), 6, 2, now() - interval '1 hour'),
  (pg_temp.wk(), pg_temp.uid(3), 'Charlie', pg_temp.snap('Charlie', null, 'bamboo'), 5, 0, now() - interval '2 hours');
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl, entered_at) values
  (pg_temp.wk() + 604800, pg_temp.uid(4), 'Echo', pg_temp.snap('Echo', '#CHKE04', 'basic'), 9, 0, now() - interval '4 hours');

-- ── A 报名 3 人、还没分组 ──
select pg_temp.call('anon_user', null, pg_temp.wk());
select pg_temp.call('p1', pg_temp.uid(1), pg_temp.wk());
select pg_temp.call('p5', pg_temp.uid(5), pg_temp.wk());

select pg_temp.ck('A1 未登录 ⇒ 恰好 {ok:false, reason:not_signed_in}',
  pg_temp.r('anon_user') = '{"ok": false, "reason": "not_signed_in"}'::jsonb, pg_temp.r('anon_user')::text);
select pg_temp.ck('A2 分母: ok、week = W、n = 3、list 3 行（p1 看 / 观众 p5 看都一样）',
  (pg_temp.r('p1')->>'ok')::boolean and (pg_temp.r('p1')->>'week')::bigint = pg_temp.wk()
  and (pg_temp.r('p1')->>'n')::int = 3 and jsonb_array_length(pg_temp.r('p1')->'list') = 3
  and (pg_temp.r('p5')->>'ok')::boolean and (pg_temp.r('p5')->>'n')::int = 3 and jsonb_array_length(pg_temp.r('p5')->'list') = 3,
  pg_temp.r('p1')::text);
select pg_temp.ck('A3 ★顺序 = gw desc, gl asc: Bravo(6-2), Charlie(5-0), Alpha(5-1)',
  pg_temp.names(pg_temp.r('p1')) = 'Bravo,Charlie,Alpha' and pg_temp.names(pg_temp.r('p5')) = 'Bravo,Charlie,Alpha',
  pg_temp.names(pg_temp.r('p1')));
select pg_temp.ck('A4 ★me: p1 看只有 Alpha 那行为 true',
  (select string_agg(e->>'name', ',') from jsonb_array_elements(pg_temp.r('p1')->'list') e where (e->>'me')::boolean) = 'Alpha'
  and (select count(*) from jsonb_array_elements(pg_temp.r('p1')->'list') e where e->'me' = 'false'::jsonb) = 2,
  pg_temp.r('p1')->>'list');
select pg_temp.ck('A4 ★me: 观众 p5（没报名）看全是 false',
  (select count(*) from jsonb_array_elements(pg_temp.r('p5')->'list') e where e->'me' = 'false'::jsonb) = 3);
select pg_temp.ck('A5 ★顶层键恰好 {ok, week, now, seated, n, list}',
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('p1')) k) = array['list', 'n', 'now', 'ok', 'seated', 'week'],
  (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.r('p1')) k));
select pg_temp.ck('A5 ★每行键恰好 {name, tag, avatar, gw, gl, me}（没有 snapshot / account_id）',
  not exists (select 1 from jsonb_array_elements(pg_temp.r('p1')->'list') e
               where (select array_agg(k order by k) from jsonb_object_keys(e) k) is distinct from array['avatar', 'gl', 'gw', 'me', 'name', 'tag'])
  and jsonb_array_length(pg_temp.r('p1')->'list') = 3,
  (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.r('p1')->'list'->0) k));
select pg_temp.ck('A5 ★回包文本里没有任何人的 account_id、没有阵容字段',
  not exists (select 1 from _ppl where position(id::text in pg_temp.r('p1')::text) > 0 or position(id::text in pg_temp.r('p5')::text) > 0)
  and pg_temp.r('p1')::text not like '%snapshot%' and pg_temp.r('p1')::text not like '%account_id%'
  and pg_temp.r('p1')::text not like '%leaders%' and pg_temp.r('p1')::text not like '%lane_assign%');
select pg_temp.ck('A6 name 取 finals_pending.name（Bravo 快照里还是 OldBravo）',
  pg_temp.row_of(pg_temp.r('p1'), 'Bravo') is not null and pg_temp.r('p1')::text not like '%OldBravo%');
select pg_temp.ck('A6 tag / avatar 取快照 profile；Charlie 没有 tag ⇒ ''''',
  pg_temp.row_of(pg_temp.r('p1'), 'Alpha') = '{"name": "Alpha", "tag": "#CHKA01", "avatar": "basic", "gw": 5, "gl": 1, "me": true}'::jsonb
  and pg_temp.row_of(pg_temp.r('p1'), 'Bravo') = '{"name": "Bravo", "tag": "#CHKB02", "avatar": "stone", "gw": 6, "gl": 2, "me": false}'::jsonb
  and pg_temp.row_of(pg_temp.r('p1'), 'Charlie') = '{"name": "Charlie", "tag": "", "avatar": "bamboo", "gw": 5, "gl": 0, "me": false}'::jsonb,
  pg_temp.r('p1')->>'list');
select pg_temp.ck('A7 now = app_now() 的 epoch 秒（偏移 +3 周 ⇒ 与 now() 差得远）',
  abs((pg_temp.r('p1')->>'now')::bigint - extract(epoch from public.app_now())::bigint) <= 1
  and abs((pg_temp.r('p1')->>'now')::bigint - extract(epoch from now())::bigint) > 86400,
  format('now=%s app_now=%s', pg_temp.r('p1')->>'now', extract(epoch from public.app_now())::bigint));
select pg_temp.ck('A7 json 类型: week/now/n 数字、seated 布尔、list 数组；行内 gw/gl 数字、me 布尔、name/tag/avatar 字符串',
  jsonb_typeof(pg_temp.r('p1')->'week') = 'number' and jsonb_typeof(pg_temp.r('p1')->'now') = 'number'
  and jsonb_typeof(pg_temp.r('p1')->'n') = 'number' and jsonb_typeof(pg_temp.r('p1')->'seated') = 'boolean'
  and jsonb_typeof(pg_temp.r('p1')->'list') = 'array'
  and not exists (select 1 from jsonb_array_elements(pg_temp.r('p1')->'list') e
                   where jsonb_typeof(e->'gw') <> 'number' or jsonb_typeof(e->'gl') <> 'number' or jsonb_typeof(e->'me') <> 'boolean'
                      or jsonb_typeof(e->'name') <> 'string' or jsonb_typeof(e->'tag') <> 'string' or jsonb_typeof(e->'avatar') <> 'string'));
select pg_temp.ck('S1 分母: 分组前 seated = false', pg_temp.r('p1')->'seated' = 'false'::jsonb);

-- ── W 别周 ──
select pg_temp.call('w1', pg_temp.uid(4), pg_temp.wk() + 604800);
select pg_temp.ck('W1 ★别周的 Echo（9 胜）没混进 W 周',
  position('Echo' in pg_temp.r('p1')::text) = 0 and position('Echo' in pg_temp.r('p5')::text) = 0);
select pg_temp.ck('W1 查 W+1 周只看到 Echo、n = 1、me = true',
  (pg_temp.r('w1')->>'n')::int = 1 and pg_temp.names(pg_temp.r('w1')) = 'Echo'
  and (pg_temp.r('w1')->'list'->0->>'me')::boolean and (pg_temp.r('w1')->>'week')::bigint = pg_temp.wk() + 604800,
  pg_temp.r('w1')::text);

-- ── L2 平手 ──
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl, entered_at) values
  (pg_temp.wk(), pg_temp.uid(6), 'Delta', pg_temp.snap('Delta', '#CHKD06', 'basic'), 5, 1, now() - interval '30 minutes');
select pg_temp.call('l2', pg_temp.uid(5), pg_temp.wk());
select pg_temp.ck('L2 ★同胜同负按 account_id: Delta 排在 Alpha 前（Delta 报名更晚）',
  pg_temp.names(pg_temp.r('l2')) = 'Bravo,Charlie,Delta,Alpha' and (pg_temp.r('l2')->>'n')::int = 4,
  pg_temp.names(pg_temp.r('l2')));

-- ── S1 分组（finals_seat）前后 ──
select pg_temp.ck('S1 分母: finals_seat 坐下 4 组（≤ 8 人一人一组）', public.finals_seat(pg_temp.wk()) = 4);
select pg_temp.call('s1', pg_temp.uid(5), pg_temp.wk());
select pg_temp.ck('S1 ★分组后 seated = true、n 仍 4',
  pg_temp.r('s1')->'seated' = 'true'::jsonb and (pg_temp.r('s1')->>'n')::int = 4 and jsonb_array_length(pg_temp.r('s1')->'list') = 4,
  pg_temp.r('s1')::text);
select pg_temp.ck('S1 ★名单顺序 = finals_seat 实际排出的种子顺序（组号 = 名次）',
  pg_temp.names(pg_temp.r('s1')) = (select string_agg(name, ',' order by bucket_no) from public.finals_entrants
                                     where season_week = pg_temp.wk() and bucket_no <> public.finals_cup_no()),
  (select string_agg(name, ',' order by bucket_no) from public.finals_entrants where season_week = pg_temp.wk()));
select pg_temp.call('w1b', pg_temp.uid(4), pg_temp.wk() + 604800);
select pg_temp.ck('W1 seated 按周算: W 周分了组，W+1 周仍 false', pg_temp.r('w1b')->'seated' = 'false'::jsonb);

-- ── L1 上限 256 行 ──
insert into _big (i, id) select g, gen_random_uuid() from generate_series(1, 300) g;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _big;
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
  select pg_temp.wk() + 2 * 604800, id, 'L' || lpad(i::text, 3, '0'), pg_temp.snap('L' || i, null, 'basic'), 4 + i % 5, i % 3
    from _big;
select pg_temp.call('l1', pg_temp.uid(5), pg_temp.wk() + 2 * 604800);
select pg_temp.ck('L1 ★300 人 ⇒ n = 300、list 256 行、是排在最前的那 256 个',
  (pg_temp.r('l1')->>'n')::int = 300 and jsonb_array_length(pg_temp.r('l1')->'list') = 256
  and pg_temp.names(pg_temp.r('l1')) = (select string_agg(name, ',' order by gw desc, gl asc, account_id)
                                         from (select name, gw, gl, account_id from public.finals_pending
                                                where season_week = pg_temp.wk() + 2 * 604800
                                                order by gw desc, gl asc, account_id limit 256) x),
  format('n=%s len=%s', pg_temp.r('l1')->>'n', jsonb_array_length(pg_temp.r('l1')->'list')));

-- ── P 权限 ──
select pg_temp.ck('P1 ★anon 没有 execute、public 没有、authenticated 有',
  not has_function_privilege('anon', 'public.finals_qualified_list(bigint)', 'execute')
  and not has_function_privilege('public', 'public.finals_qualified_list(bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.finals_qualified_list(bigint)', 'execute'),
  format('anon=%s public=%s authenticated=%s',
    has_function_privilege('anon', 'public.finals_qualified_list(bigint)', 'execute'),
    has_function_privilege('public', 'public.finals_qualified_list(bigint)', 'execute'),
    has_function_privilege('authenticated', 'public.finals_qualified_list(bigint)', 'execute')));
select set_config('chk.anon_call', '', true);
set local role anon;
do $$
begin
  perform public.finals_qualified_list(current_setting('chk.wk')::bigint);
  perform set_config('chk.anon_call', 'called', true);
exception when insufficient_privilege then
  perform set_config('chk.anon_call', 'denied', true);
end $$;
reset role;
select pg_temp.ck('P1 ★以 anon 身份真调被拒（insufficient_privilege）', current_setting('chk.anon_call', true) = 'denied',
  current_setting('chk.anon_call', true));

select pg_temp.as_user(pg_temp.uid(5));
select set_config('chk.direct', '', true);
select set_config('chk.auth_call', '', true);
set local role authenticated;
do $$
begin
  perform set_config('chk.direct', (select count(*) from public.finals_pending
                                     where season_week = current_setting('chk.wk')::bigint)::text, true);
exception when insufficient_privilege then
  perform set_config('chk.direct', 'denied', true);
end $$;
select set_config('chk.auth_call', public.finals_qualified_list(current_setting('chk.wk')::bigint)::text, true);
reset role;
select pg_temp.as_user(null);
select pg_temp.ck('P2 分母: authenticated 直接查表看不到别人（RLS 0 行 / 没授权）',
  current_setting('chk.direct', true) in ('0', 'denied'), current_setting('chk.direct', true));
select pg_temp.ck('P2 ★以 authenticated 身份真调: 照样数到 4 人、4 行、不带阵容',
  (current_setting('chk.auth_call', true)::jsonb->>'n')::int = 4
  and jsonb_array_length(current_setting('chk.auth_call', true)::jsonb->'list') = 4
  and current_setting('chk.auth_call', true) not like '%leaders%',
  left(current_setting('chk.auth_call', true), 200));

select pg_temp.ck('P3 security definer / stable / search_path = public / 返回 jsonb',
  (select p.prosecdef and p.provolatile = 's' and p.prorettype = 'jsonb'::regtype
          and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
     from pg_proc p where p.oid = 'public.finals_qualified_list(bigint)'::regprocedure),
  (select format('secdef=%s vol=%s cfg=%s', p.prosecdef, p.provolatile, p.proconfig)
     from pg_proc p where p.oid = 'public.finals_qualified_list(bigint)'::regprocedure));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 26 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
