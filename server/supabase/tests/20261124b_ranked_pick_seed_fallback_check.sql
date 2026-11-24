-- 20261124b 积分赛挑对手: 种子快照只在同场次没有真人 / 陪练账号快照时垫底 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261124b_ranked_pick_seed_fallback
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 插的行一个都不留。
--   ★用一个不会撞上真数据的规则版本（9001）和远期周（2100-01-04）⇒ 内测服 / 正式服演练时不碰真快照、真池子。
-- 判据：
--   S1 同场次有两份真账号快照 + 两份种子 ⇒ 300 次只挑到真账号、两份都挑到过（同一类里仍等概率）、种子一次没出现
--   S2 真账号都排除（本周碰过）⇒ 种子垫底、两份种子都挑到过
--   S3 真账号、种子都排除 ⇒ 机器人（同场次那一格），与改之前相同
--   S4 别的场次的真账号不算（4 场的真人不顶 3 场）⇒ 3 场只剩种子时挑种子
--   S5 权限不变：public / anon / authenticated 都不能直接调
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) select unnest(array['self', 'h1', 'h2', 'h4']);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.wk() returns bigint language sql as $$ select 4102444800::bigint $$;   -- 2100-01-04 周一
create or replace function pg_temp.snap(p_name text, p_battles int default 0) returns jsonb language sql as $$
  select jsonb_build_object('schema_ver', 2, 'ghost_id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
    'profile', jsonb_build_object('name', p_name, 'avatar', 'ninja', 'id', 'g_' || p_name || '_1_dice-ninja-pirate_b' || p_battles,
                                  'tag', 'chk-' || p_name),
    'leaders', jsonb_build_array('ninja', 'dice', 'pirate'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('ninja', 'dice'), 'bottom', jsonb_build_array('pirate')),
    'equipped', jsonb_build_object('ninja', jsonb_build_array(jsonb_build_object('id', 'p2eq_001', 'star', 1))),
    'pet_levels', jsonb_build_object('ninja', 1, 'dice', 1, 'pirate', 1),
    'season_total_battles', p_battles, 'season_level', 3, 'season_wins', 1, 'hearts', 6, 'season_sweeps', 0,
    'season_eggs_killed', 0)
$$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
-- 3 场：真账号 h1 / h2、种子 0 / 1；4 场：真账号 h4；机器人 3 场两份
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps, client_version, rules_ver)
values
  (pg_temp.u('h1'), pg_temp.wk(), 3, pg_temp.snap('h1', 3), 1, 6, 0, '0.23.6', 9001),
  (pg_temp.u('h2'), pg_temp.wk(), 3, pg_temp.snap('h2', 3), 1, 6, 0, '0.23.6', 9001),
  (pg_temp.u('h4'), pg_temp.wk(), 4, pg_temp.snap('h4', 4), 1, 6, 0, '0.23.6', 9001);
insert into public.ranked_pool (rules_ver, kind, battles, variant, snapshot, client_version)
values
  (9001, 'seed', 3, 0, pg_temp.snap('seedA', 3) || jsonb_build_object('ghost_id', 'seed_a'), '0.23.6'),
  (9001, 'seed', 3, 1, pg_temp.snap('seedB', 3) || jsonb_build_object('ghost_id', 'seed_b'), '0.23.6'),
  (9001, 'bot', 3, 0, pg_temp.snap('botA', 3) || jsonb_build_object('is_bot', true), '0.23.6'),
  (9001, 'bot', 3, 1, pg_temp.snap('botB', 3) || jsonb_build_object('is_bot', true), '0.23.6');

do $$
declare i int; pk jsonb; seen text[] := '{}'; seeds int := 0; other int := 0;
  a1 text := format('acct:%s:b3', pg_temp.u('h1'));
  a2 text := format('acct:%s:b3', pg_temp.u('h2'));
begin
  for i in 1..300 loop
    pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, '{}');
    if pk ->> 'pick' = 'seed' then
      seeds := seeds + 1;
    elsif (pk ->> 'opp') in (a1, a2) and pk ->> 'pick' = 'human' then
      if not ((pk ->> 'opp') = any(seen)) then seen := seen || (pk ->> 'opp'); end if;
    else
      other := other + 1;
    end if;
  end loop;
  perform pg_temp.ck('S1 ★有真账号 ⇒ 300 次种子 0 次、别的 0 次', seeds = 0 and other = 0, format('种子 %s 次 / 别的 %s 次', seeds, other));
  perform pg_temp.ck('S1 分母: 两份真账号都挑到过（同一类里仍等概率）', coalesce(array_length(seen, 1), 0) = 2, array_to_string(seen, ','));

  seen := '{}'; other := 0;
  for i in 1..100 loop
    pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, array[a1, a2]);
    if pk ->> 'pick' = 'seed' and (pk ->> 'opp') in ('seed:9001:3:0', 'seed:9001:3:1') then
      if not ((pk ->> 'opp') = any(seen)) then seen := seen || (pk ->> 'opp'); end if;
    else
      other := other + 1;
    end if;
  end loop;
  perform pg_temp.ck('S2 ★真账号都碰过 ⇒ 种子垫底, 两份都挑到过', other = 0 and coalesce(array_length(seen, 1), 0) = 2,
    format('非种子 %s 次 · %s', other, array_to_string(seen, ',')));

  pk := public.referee_ranked_pick(pg_temp.u('self'), pg_temp.wk(), 3, 9001, array[a1, a2, 'seed:9001:3:0', 'seed:9001:3:1']);
  perform pg_temp.ck('S3 真账号、种子都排除 ⇒ 机器人同场次那一格', pk ->> 'pick' = 'bot' and pk ->> 'opp' like 'bot:9001:3:%', coalesce(pk::text, 'null'));

  pk := public.referee_ranked_pick(pg_temp.u('h4'), pg_temp.wk(), 3, 9001, array[a1, a2]);
  perform pg_temp.ck('S4 别的场次的真账号不顶(4 场的 h4 不算 3 场)⇒ 种子', pk ->> 'pick' = 'seed', coalesce(pk::text, 'null'));
end $$;

select pg_temp.ck('S5 权限不变: authenticated / anon 都不能直接调',
  not has_function_privilege('authenticated', 'public.referee_ranked_pick(uuid, bigint, int, int, text[])', 'execute')
  and not has_function_privilege('anon', 'public.referee_ranked_pick(uuid, bigint, int, int, text[])', 'execute'));

do $$
declare nt int; nf int; msg text; fmsg text;
begin
  select count(*), count(*) filter (where not pass) into nt, nf from _chk;
  select string_agg(format('%s %s  %s', case when pass then '[PASS]' else '[FAIL]' end, name, info), E'\n' order by n) into msg from _chk;
  select string_agg(format('[FAIL] %s  %s', name, info), E'\n' order by n) into fmsg from _chk where not pass;
  if nf > 0 or nt < 6 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || coalesce(fmsg, '(条数不够)') || E'\n──── 全部 ────\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
