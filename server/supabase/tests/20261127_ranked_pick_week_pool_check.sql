-- 20261127 积分赛种子 / 机器人对手按本周羁绊池过滤 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261127_ranked_pick_week_pool
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 插的行一个都不留。
--   ★规则版本用 9001（不会撞上真快照、真池子）。
-- 判据：
--   W1 SQL 算的本周 10 个 == 游戏代码金标(tests/golden/weekly_synergy.json 前三周, 含 11-30 上线保底周), 顺序也相同
--   W2 周锚点 0 ⇒ 16 个全在; FNV-1a 两个已知值
--   P1 单份快照判定: 剑 + 小木斧 ⇒ 过; 面具(已穿)/ 遗物+香火(多类型, 遗物不在)/ 小将身上的面具 / 援军清单里的长矛 ⇒ 不过; 上线周面具 ⇒ 过
--   R1 只有种子时: 装备全在本周池的那份 200 次全中, 带面具的一次都不出
--   R2 种子都不合格 ⇒ 机器人里本周池的那份 200 次全中
--   R3 机器人也都不合格 ⇒ 仍然挑得到(退回任意一份, 不让人匹配不到)
--   R4 真人快照不过滤(带面具的真账号照样挑到)
--   R5 权限: public / anon / authenticated 都不能调新函数和挑对手
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['self', 'hm']);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.wk() returns bigint language sql as $$ select 1796601600::bigint $$;   -- 2026-12-07(本周没有面具 / 长矛 / 遗物)
create or replace function pg_temp.snap(p_name text, p_eq text, p_battles int default 3) returns jsonb language sql as $$
  select jsonb_build_object('schema_ver', 2, 'ghost_id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
    'profile', jsonb_build_object('name', p_name, 'avatar', 'ninja', 'id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
                                  'tag', 'chk-' || p_name),
    'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')),
    'equipped', jsonb_build_object('ninja', jsonb_build_array(jsonb_build_object('id', 'p2eq_001', 'star', 1),
                                                              jsonb_build_object('id', p_eq, 'star', 1))),
    'pet_levels', jsonb_build_object('ninja', 1, 'dice', 1, 'pirate', 1),
    'season_total_battles', p_battles, 'season_level', 3, 'season_wins', 1, 'hearts', 6, 'season_sweeps', 0,
    'season_eggs_killed', 0)
$$;

-- ── W 本周 10 个 ──
select pg_temp.ck('W1 上线周 11-30 保底', public.weekly_synergy_of(1795996800)
  = array['匕首', '魔法书', '面具', '筹码', '炸弹', '长矛', '灵物', '剑', '奇械', '遗物'], public.weekly_synergy_of(1795996800)::text);
select pg_temp.ck('W1 第二周 12-07', public.weekly_synergy_of(1796601600)
  = array['奇械', '枪', '法器', '魔法书', '筹码', '剑', '灵物', '匕首', '弓箭', '药水'], public.weekly_synergy_of(1796601600)::text);
select pg_temp.ck('W1 第三周 12-14', public.weekly_synergy_of(1797206400)
  = array['剑', '枪', '灵物', '食物', '匕首', '弓箭', '魔法书', '筹码', '药水', '长矛'], public.weekly_synergy_of(1797206400)::text);
select pg_temp.ck('W2 周锚点 0 ⇒ 16 个', cardinality(public.weekly_synergy_of(0)) = 16);
select pg_temp.ck('W2 FNV-1a 已知值', public.fnv1a32('') = 2166136261 and public.fnv1a32('a') = 3826002220,
  public.fnv1a32('a')::text);

-- ── P 单份快照 ──
select pg_temp.ck('P1 剑 + 小木斧 ⇒ 过', public.snap_week_pool_ok(pg_temp.snap('a', 'p2eq_096'), pg_temp.wk()));
select pg_temp.ck('P1 已穿面具 ⇒ 不过', not public.snap_week_pool_ok(pg_temp.snap('b', 'p2eq_127'), pg_temp.wk()));
select pg_temp.ck('P1 遗物+香火(遗物不在) ⇒ 不过', not public.snap_week_pool_ok(pg_temp.snap('c', 'p2eq_093'), pg_temp.wk()));
select pg_temp.ck('P1 小将身上的面具 ⇒ 不过', not public.snap_week_pool_ok(pg_temp.snap('d', 'p2eq_096')
  || jsonb_build_object('minions', jsonb_build_array(jsonb_build_object('role', 'front', 'equips',
       jsonb_build_array(jsonb_build_object('id', 'p2eq_127', 'star', 1))))), pg_temp.wk()));
select pg_temp.ck('P1 援军清单里的长矛 ⇒ 不过', not public.snap_week_pool_ok(pg_temp.snap('e', 'p2eq_096')
  || jsonb_build_object('reserve_pool', jsonb_build_array(jsonb_build_object('id', 'p2eq_137', 'star', 1))), pg_temp.wk()));
select pg_temp.ck('P1 上线周带面具 ⇒ 过', public.snap_week_pool_ok(pg_temp.snap('f', 'p2eq_127'), 1795996800));

-- ── R 挑对手 ──
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
insert into public.ranked_pool (rules_ver, kind, battles, variant, snapshot, client_version)
values
  (9001, 'seed', 3, 0, pg_temp.snap('seedIn', 'p2eq_096') || jsonb_build_object('ghost_id', 'seed_in'), '0.23.6'),
  (9001, 'seed', 3, 1, pg_temp.snap('seedOut', 'p2eq_127') || jsonb_build_object('ghost_id', 'seed_out'), '0.23.6'),
  (9001, 'bot', 3, 0, pg_temp.snap('botIn', 'p2eq_001') || jsonb_build_object('is_bot', true), '0.23.6'),
  (9001, 'bot', 3, 1, pg_temp.snap('botOut', 'p2eq_137') || jsonb_build_object('is_bot', true), '0.23.6');

do $$
declare i int; pk jsonb; n_in int := 0; n_bad int := 0;
begin
  for i in 1..200 loop
    pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, '{}');
    if pk ->> 'opp' = 'seed:9001:3:0' then n_in := n_in + 1; else n_bad := n_bad + 1; end if;
  end loop;
  perform pg_temp.ck('R1 种子: 本周池那份 200/200, 带面具那份 0', n_in = 200 and n_bad = 0, format('%s / %s', n_in, n_bad));

  n_in := 0; n_bad := 0;
  for i in 1..200 loop
    pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, array['seed:9001:3:0']);
    if pk ->> 'opp' = 'bot:9001:3:0' then n_in := n_in + 1; else n_bad := n_bad + 1; end if;
  end loop;
  perform pg_temp.ck('R2 合格种子排除后 ⇒ 机器人里本周池那份 200/200', n_in = 200 and n_bad = 0, format('%s / %s', n_in, n_bad));

  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, array['seed:9001:3:0', 'bot:9001:3:0']);
  perform pg_temp.ck('R3 机器人都不合格也挑得到(退回任意一份)', pk ->> 'pick' = 'bot', coalesce(pk::text, 'null'));
end $$;

insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps, client_version, rules_ver)
values (pg_temp.u('hm'), pg_temp.wk(), 3, pg_temp.snap('hm', 'p2eq_127'), 1, 6, 0, '0.23.6', 9001);
do $$
declare pk jsonb;
begin
  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, '{}');
  perform pg_temp.ck('R4 真人快照不过滤(带面具的真账号照样挑到)', pk ->> 'pick' = 'human', coalesce(pk::text, 'null'));
end $$;

-- ── R5 权限 ──
select pg_temp.ck('R5 ' || f || ' ' || r || ' 不能调', not has_function_privilege(r, f, 'execute'))
  from unnest(array['public.referee_ranked_pick(uuid, bigint, int, int, text[])', 'public.weekly_synergy_of(bigint)',
                    'public.snap_week_pool_ok(jsonb, bigint)', 'public.p2eq_big_types(text)', 'public.fnv1a32(text)']) f,
       unnest(array['anon', 'authenticated']) r;

do $$
declare nt int; nf int; msg text; fmsg text;
begin
  select count(*), count(*) filter (where not pass) into nt, nf from _chk;
  select string_agg(format('%s %s  %s', case when pass then '[PASS]' else '[FAIL]' end, name, info), E'
' order by n) into msg from _chk;
  select string_agg(format('[FAIL] %s  %s', name, info), E'
' order by n) into fmsg from _chk where not pass;
  if nf > 0 or nt < 20 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'
' || coalesce(fmsg, '(条数不够)') || E'
──── 全部 ────
' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
