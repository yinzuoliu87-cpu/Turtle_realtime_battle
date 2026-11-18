-- 20261118b 战绩页数据源 my_battle_log —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261118b_battle_log
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261118b_battle_log
-- 造人：我 / 对手 / 路人三个号；造六局（版本 9.9.6-log，真库里没有）：
--   ① 积分赛 我在 a 赢   ② 积分赛 我在 b（别人拿我快照打的）③ 闯关赛 我在 b 输   ④ 决赛 我在 a 赢（带 meta）
--   ⑤ 偷袭 我在 b（被偷）⑥ 路人的积分赛   另有 ⑦ 我在 a 但还 pending
-- 判据：
--   B1 只回我的四场（①③④⑤），不回 ② ⑥ ⑦；倒序
--   B2 side / won / lanes(me|foe) 按我这一边换算对
--   B3 me / foe 名字、三统领、equipped 只留三统领（快照里多的那只不回）、装备 {id, star} 原样
--   B4 secs = steps / 60；决赛带 finals {bucket, round, match}；偷袭带 raid_role
--   B5 不回整份快照（没有 minions / loadouts / hearts 等键）
--   B6 分页：limit 2 ⇒ 前两场；p_before = 第二场的 id ⇒ 后两场；不重不漏
--   B7 没登录 ⇒ []；P anon 调不了、authenticated 能调
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p text) returns uuid language sql as $$ select id from _u where k = p $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.snap(p_name text, p_leaders text[], p_extra text default null) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('name', p_name, 'tag', '#' || upper(p_name), 'avatar', p_leaders[1]),
    'leaders', to_jsonb(p_leaders),
    'equipped', (select jsonb_object_agg(l, jsonb_build_array(jsonb_build_object('id', 'p2eq_00' || i, 'star', i)))
                   from unnest(p_leaders || (case when p_extra is null then '{}'::text[] else array[p_extra] end)) with ordinality t(l, i)),
    'lane_assign', jsonb_build_object('top', to_jsonb(p_leaders[1:2]), 'bottom', to_jsonb(p_leaders[3:3])),
    'minions', '{"top": []}'::jsonb, 'loadouts', '{}'::jsonb, 'hearts', 6)
$$;
create or replace function pg_temp.job(p_kind text, p_key text, p_a uuid, p_b uuid, p_as jsonb, p_bs jsonb, p_winner text,
                                       p_top text, p_bottom text, p_steps int, p_meta jsonb default '{}'::jsonb,
                                       p_status text default 'done') returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot,
                                   meta, status, result, done_at)
  values (p_kind, 'chk-log:' || p_key, 1, '9.9.6-log', 9, p_a, p_b, p_as, p_bs, p_meta, p_status,
          case when p_status = 'done' then jsonb_build_object('winner', p_winner, 'steps', p_steps,
               'lane_results', jsonb_build_object('top', p_top, 'bottom', p_bottom)) end,
          case when p_status = 'done' then now() end)
  returning job_id $$;

insert into _u values ('me', gen_random_uuid()), ('foe', gen_random_uuid()), ('x', gen_random_uuid());
insert into auth.users (id, aud, role, is_anonymous, created_at) select id, 'authenticated', 'authenticated', true, now() from _u;

create temp table _j (k text primary key, id bigint);
grant select on _j to public;
insert into _j values ('r_a', pg_temp.job('ranked', 'r_a', pg_temp.u('me'), null,
  pg_temp.snap('me', array['lava', 'ice', 'stone'], 'candy'), pg_temp.snap('bot', array['ghost', 'pirate', 'ninja']), 'a', 'left', 'right', 3600));
insert into _j values ('r_b', pg_temp.job('ranked', 'r_b', pg_temp.u('x'), pg_temp.u('me'),
  pg_temp.snap('x', array['ghost', 'pirate', 'ninja']), pg_temp.snap('me', array['lava', 'ice', 'stone']), 'a', 'left', 'left', 1200));
insert into _j values ('g_b', pg_temp.job('gauntlet', 'g_b', pg_temp.u('foe'), pg_temp.u('me'),
  pg_temp.snap('foe', array['crystal', 'dice', 'chest']), pg_temp.snap('me', array['lava', 'ice', 'stone']), 'a', 'left', 'right', 6000));
insert into _j values ('f_a', pg_temp.job('finals', 'f_a', pg_temp.u('me'), pg_temp.u('foe'),
  pg_temp.snap('me', array['lava', 'ice', 'stone']), pg_temp.snap('foe', array['crystal', 'dice', 'chest']), 'a', 'left', 'left', 4074,
  '{"bucket": 3, "round": 2, "match": 1}'::jsonb));
insert into _j values ('d_b', pg_temp.job('raid', 'd_b', pg_temp.u('foe'), pg_temp.u('me'),
  pg_temp.snap('foe', array['crystal', 'dice', 'chest']), pg_temp.snap('me', array['lava', 'ice', 'stone']), 'b', 'right', null, 6707));
insert into _j values ('x_a', pg_temp.job('ranked', 'x_a', pg_temp.u('x'), null,
  pg_temp.snap('x', array['ghost', 'pirate', 'ninja']), pg_temp.snap('bot', array['lava', 'ice', 'stone']), 'b', 'right', 'right', 900));
insert into _j values ('p_a', pg_temp.job('ranked', 'p_a', pg_temp.u('me'), null,
  pg_temp.snap('me', array['lava', 'ice', 'stone']), pg_temp.snap('bot', array['ghost', 'pirate', 'ninja']), 'a', 'left', 'left', 1,
  '{}'::jsonb, 'pending'));

select pg_temp.as_user(pg_temp.u('me'));
create temp table _all as select public.my_battle_log(20, null) as v;
grant select on _all to public;
create or replace function pg_temp.row(p_k text) returns jsonb language sql as $$
  select e from _all, jsonb_array_elements(v) e where (e ->> 'id')::bigint = (select id from _j where k = p_k) $$;

-- B1
select pg_temp.ck('B1 只回我的四场（积分赛 a / 闯关 b / 决赛 a / 偷袭 b），倒序',
  (select jsonb_agg((e ->> 'id')::bigint) from _all, jsonb_array_elements(v) e)
    = (select jsonb_agg(id order by id desc) from _j where k in ('r_a', 'g_b', 'f_a', 'd_b')),
  (select v::text from _all));

-- B2
select pg_temp.ck('B2 积分赛 a 赢：side a / won / 上路 me 下路 foe',
  pg_temp.row('r_a') ->> 'side' = 'a' and (pg_temp.row('r_a') ->> 'won')::boolean
  and pg_temp.row('r_a') -> 'lanes' = '{"top": "me", "bottom": "foe"}'::jsonb, pg_temp.row('r_a')::text);
select pg_temp.ck('B2 闯关 b 输：side b / not won / 上路 foe 下路 me',
  pg_temp.row('g_b') ->> 'side' = 'b' and not (pg_temp.row('g_b') ->> 'won')::boolean
  and pg_temp.row('g_b') -> 'lanes' = '{"top": "foe", "bottom": "me"}'::jsonb, (pg_temp.row('g_b') -> 'lanes')::text);
select pg_temp.ck('B2 偷袭 b 守住：won / raid_role defend / 下路没结果 ⇒ null',
  (pg_temp.row('d_b') ->> 'won')::boolean and pg_temp.row('d_b') ->> 'raid_role' = 'defend'
  and pg_temp.row('d_b') -> 'lanes' ->> 'top' = 'me' and pg_temp.row('d_b') -> 'lanes' -> 'bottom' = 'null'::jsonb,
  pg_temp.row('d_b')::text);

-- B3
select pg_temp.ck('B3 我 / 对手：名字、三统领对得上（闯关我在 b ⇒ me 取 b 快照）',
  pg_temp.row('g_b') -> 'me' ->> 'name' = 'me' and pg_temp.row('g_b') -> 'foe' ->> 'name' = 'foe'
  and pg_temp.row('g_b') -> 'foe' -> 'leaders' = '["crystal", "dice", "chest"]'::jsonb
  and pg_temp.row('g_b') -> 'me' ->> 'tag' = '#ME', (pg_temp.row('g_b') -> 'me')::text);
select pg_temp.ck('B3 equipped 只留三统领（快照里多带的 candy 不回）、装备 {id, star} 原样',
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.row('r_a') -> 'me' -> 'equipped') k) = array['ice', 'lava', 'stone']
  and pg_temp.row('r_a') -> 'me' -> 'equipped' -> 'ice' = '[{"id": "p2eq_002", "star": 2}]'::jsonb,
  (pg_temp.row('r_a') -> 'me' -> 'equipped')::text);
select pg_temp.ck('B3 lanes = lane_assign',
  pg_temp.row('r_a') -> 'me' -> 'lanes' = '{"top": ["lava", "ice"], "bottom": ["stone"]}'::jsonb, (pg_temp.row('r_a') -> 'me' -> 'lanes')::text);

-- B4
select pg_temp.ck('B4 secs = steps / 60（6707 ⇒ 112、4074 ⇒ 68）',
  (pg_temp.row('d_b') ->> 'secs')::int = 112 and (pg_temp.row('f_a') ->> 'secs')::int = 68,
  pg_temp.row('d_b') ->> 'secs' || ' / ' || (pg_temp.row('f_a') ->> 'secs'));
select pg_temp.ck('B4 决赛带 finals {bucket 3, round 2, match 1}；非决赛 finals = null',
  pg_temp.row('f_a') -> 'finals' = '{"bucket": 3, "round": 2, "match": 1}'::jsonb and pg_temp.row('r_a') -> 'finals' = 'null'::jsonb,
  (pg_temp.row('f_a') -> 'finals')::text);

-- B5
select pg_temp.ck('B5 不回整份快照（me 里没有 minions / loadouts / hearts）',
  not (pg_temp.row('r_a') -> 'me' ?| array['minions', 'loadouts', 'hearts', 'equipped_all'])
  and (select count(*) from jsonb_object_keys(pg_temp.row('r_a') -> 'me')) = 6,
  (select string_agg(k, ',') from jsonb_object_keys(pg_temp.row('r_a') -> 'me') k));

-- B6
create temp table _p1 as select public.my_battle_log(2, null) as v;
create temp table _p2 as select public.my_battle_log(2, ((select v from _p1) -> 1 ->> 'id')::bigint) as v;
select pg_temp.ck('B6 分页：两页拼起来 = 全部四场、不重不漏',
  jsonb_array_length((select v from _p1)) = 2 and jsonb_array_length((select v from _p2)) = 2
  and ((select v from _p1) || (select v from _p2)) = (select v from _all), (select v::text from _p2));

-- B7 / P
select pg_temp.as_user(null);
select pg_temp.ck('B7 没登录 ⇒ []', public.my_battle_log(20, null) = '[]'::jsonb);
select pg_temp.ck('P anon 调不了、authenticated 能调',
  not has_function_privilege('anon', 'public.my_battle_log(int, bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.my_battle_log(int, bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.battle_log_side(jsonb)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 13 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
