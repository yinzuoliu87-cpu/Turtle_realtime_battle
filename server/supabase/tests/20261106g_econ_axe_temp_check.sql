-- 20261106g 局外经济记账 · 认识服务器局的斧头经验与临时等级 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261106g_econ_axe_temp
-- 判据：
--   X 事实：axe.kills = 算完的裁判局里我这一侧的击杀合计（A 取 axe_kills、配对局 B 取 axe_kills_b、旧路 b_account 不算）；领活带上
--   T 临时等级：统领 temp_levels / 小将 temp_lv 与重放对得上 ⇒ null；报高 / 少报 ⇒ econ_mismatch
--   C ★真快照契约：verify_econ_server_check 用真结算入口走出来的快照 + 重放结果（门禁比「样本 = 现在代码算的」）⇒ 对得上；改一件就拒
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

update public.referee_config set econ_on = true where id = 1;

-- ── X 事实 ──
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, status, meta, result) values
  ('gauntlet', 'chk:g1', pg_temp.wk(), '0.22.7', 1, pg_temp.u('other'), pg_temp.u('me'), '{}', '{}', 'done', '{"pair":"true"}', '{"ledger":{"won":true,"coins":4,"coins_b":9},"axe_kills":3,"axe_kills_b":2}'),
  ('gauntlet', 'chk:g2', pg_temp.wk(), '0.22.7', 2, pg_temp.u('other'), pg_temp.u('me'), '{}', '{}', 'done', '{}', '{"ledger":{"won":false,"coins":5},"axe_kills":1,"axe_kills_b":7}'),
  ('ranked', 'chk:r1', pg_temp.wk(), '0.22.7', 3, pg_temp.u('other'), null, '{}', '{}', 'done', '{}', '{"ledger":{"won":true,"coins":2}}');
select pg_temp.ck('X1 A 方: 3 + 1 + 没这个键算 0', (public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'axe' ->> 'kills')::int = 4, (public.econ_facts(pg_temp.u('other'), pg_temp.wk()) -> 'axe')::text);
select pg_temp.ck('X2 ★配对局 B 方取 axe_kills_b; 旧路 b_account 不算', (public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'axe' ->> 'kills')::int = 2, (public.econ_facts(pg_temp.u('me'), pg_temp.wk()) -> 'axe')::text);
select pg_temp.ck('X3 没有账的号 ⇒ 0', (public.econ_facts(pg_temp.u('real'), pg_temp.wk()) -> 'axe' ->> 'kills')::int = 0);

-- ── T 临时等级 ──
insert into public.econ_state (account_id, week, seen, upto, assets, progress) values (pg_temp.u('me'), pg_temp.wk(), 0, 0,
  '{"lv":3,"leaders":["ninja","dice","pirate"],"worn":{"ninja":[{"id":"p2eq_001","star":1}]},"tl":{"ninja":2},"minions":["{\"eq\":[],\"lv\":1}"],"axe":[0,0,0,"",0]}', '{"cv":0,"cw":[],"im":0,"ic":0}');
select pg_temp.ck('T1 统领 + 小将临时等级都对得上 ⇒ null',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"temp_levels":{"ninja":2},"minions":{"top":[{"role":"back","temp_lv":1}],"bottom":[]}}') is null,
  coalesce(public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"temp_levels":{"ninja":2},"minions":{"top":[{"role":"back","temp_lv":1}],"bottom":[]}}')::text, ''));
select pg_temp.ck('T2 ★统领临时等级报高 ⇒ econ_mismatch(temp:ninja)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"temp_levels":{"ninja":3},"minions":{"top":[{"role":"back","temp_lv":1}],"bottom":[]}}') ->> 'what' = 'temp:ninja');
select pg_temp.ck('T3 ★没带 temp_levels 但流水里有 ⇒ econ_mismatch',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"minions":{"top":[{"role":"back","temp_lv":1}],"bottom":[]}}') ->> 'what' = 'temp:ninja');
select pg_temp.ck('T4 ★小将临时等级报高 ⇒ econ_mismatch(minions)',
  public.econ_check(pg_temp.u('me'), pg_temp.wk(), pg_temp.snap('me') || '{"temp_levels":{"ninja":2},"minions":{"top":[{"role":"back","temp_lv":5}],"bottom":[]}}') ->> 'what' = 'minions');
delete from public.econ_state where account_id = pg_temp.u('me');

-- ── C ★真快照契约 ──
-- >>> 契约样本(verify_econ_server_check 生成; 手改无效)
create or replace function pg_temp.contract() returns jsonb language sql as $c$ select $j${"assets":{"axe":[12,12,0,"",0],"leaders":["candy","stone","ice"],"lv":5,"minions":["{\"eq\":[{\"id\":\"p2eq_047\",\"star\":1}],\"lv\":0}"],"worn":{"candy":[{"id":"p2eq_085","star":1}]}},"progress":{"cv":120.5,"cw":["t1"],"ic":2,"im":1},"snap":{"axe_exp_total":12.0,"axe_final":"","axe_stage":0.0,"chest_treasure_value":120.5,"chest_treasures_won":["t1"],"equipped":{"candy":[{"id":"p2eq_085","star":1.0}]},"incense_charge":2.0,"incense_marks":1.0,"leaders":["candy","stone","ice"],"minions":{"bottom":[{"elite":false,"role":"front"},{"elite":false,"role":"back"}],"top":[{"elite":false,"equips":[{"id":"p2eq_047","star":1.0}],"role":"front"}]},"season_level":5.0}}$j$::jsonb $c$;
-- <<< 契约样本
insert into public.econ_state (account_id, week, seen, upto, assets, progress)
  values (pg_temp.u('real'), pg_temp.wk(), 0, 0, pg_temp.contract() -> 'assets', pg_temp.contract() -> 'progress');
select pg_temp.ck('C1 ★真快照 + 真重放结果 ⇒ 对得上(老实玩家不被拒)', public.econ_check(pg_temp.u('real'), pg_temp.wk(), pg_temp.contract() -> 'snap') is null,
  coalesce(public.econ_check(pg_temp.u('real'), pg_temp.wk(), pg_temp.contract() -> 'snap')::text, ''));
select pg_temp.ck('C2 分母: 样本里统领身上真有装备、小将真有装备', (select count(*) from jsonb_each(pg_temp.contract() -> 'snap' -> 'equipped')) >= 1
  and public.econ_snapshot_minions_key(pg_temp.contract() -> 'snap') not in ('', '@0'));
select pg_temp.ck('C3 ★改存档: 统领第一件改成 3★ ⇒ 拒',
  public.econ_check(pg_temp.u('real'), pg_temp.wk(),
    jsonb_set(pg_temp.contract() -> 'snap', array['equipped', (select k from jsonb_object_keys(pg_temp.contract() -> 'snap' -> 'equipped') k limit 1), '0', 'star'], '3'))
    ->> 'reason' = 'econ_mismatch');
delete from public.econ_state where account_id = pg_temp.u('real');

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
