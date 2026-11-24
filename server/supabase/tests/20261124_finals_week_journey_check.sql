-- 20261124 夺冠之路一整周 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta|prod --rehearse 20261124_finals_week_journey
-- 造数（周锚点 4102444800 = 2100-01-04，没人用）：号 0 = 决赛日参赛者，号 1 = 没进决赛日，号 2 = 对手
--   ① ranked   a=号0 b=号2  done  两路都左    ⇒ 进、2:0 胜
--   ② ranked   a=号2 b=号0  done              ⇒ 不进（别人拿他快照打的）
--   ③ gauntlet a=号2 b=号0  done  上左 下右 终右 winner b ⇒ 进、号 0 在 b 方：top foe / bottom me / final me、胜
--   ④ finals   a=号0 b=号2  done  meta bucket/round/match ⇒ 进、带 finals
--   ⑤ ranked   a=号0        pending           ⇒ 不进
--   ⑥ ranked   a=号0        done、别的周      ⇒ 不进
-- 判据：
--   J1 没登录 ⇒ bad；号 1（不是参赛者）⇒ not_entrant
--   J2 号 0 ⇒ ok、3 行、顺序 ranked / gauntlet / finals
--   J3 ① 路况 me/me、final null、won
--   J4 ③ b 方翻面：top foe / bottom me / final me、won
--   J5 对手名字 / 头像 / 三统领取自对手快照 profile / leaders；不回快照与装备
--   J6 ④ finals {bucket, round, match}
--   P  anon 不能调、authenticated 能调；journey_lane 两者都不能调
begin;
create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k int, id uuid);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k int) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;

insert into _u select g, gen_random_uuid() from generate_series(0, 2) g;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

insert into public.finals_buckets (season_week, bucket_no, n, round, closed) values (4102444800, 9900011, 2, 1, false);
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  values (4102444800, 9900011, 0, pg_temp.u(0), 'u0', '{}'::jsonb), (4102444800, 9900011, 1, pg_temp.u(2), 'u2', '{}'::jsonb);

create temp table _snap as select
  '{"profile": {"name": "号0", "avatar": "basic"}, "leaders": ["basic", "stone", "ninja"], "equipped": {"basic": [{"id": "x"}]}}'::jsonb as s0,
  '{"profile": {"name": "对手二", "avatar": "angel"}, "leaders": ["angel", "dice", "line"], "equipped": {"angel": [{"id": "y"}]}}'::jsonb as s2;

insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot,
                                 status, result, meta, created_at, done_at)
select v.kind, 'chk20261124:' || v.k, v.wk, '0.0.0', 1, pg_temp.u(v.a), pg_temp.u(v.b),
       case v.a when 0 then (select s0 from _snap) else (select s2 from _snap) end,
       case v.b when 0 then (select s0 from _snap) else (select s2 from _snap) end,
       v.st, v.res::jsonb, v.meta::jsonb, now() - (v.k || ' minutes')::interval * -1, now()
  from (values
    (1, 'ranked',   4102444800, 0, 2, 'done',    '{"winner": "a", "lane_results": {"top": "left", "bottom": "left"}}', '{}'),
    (2, 'ranked',   4102444800, 2, 0, 'done',    '{"winner": "a", "lane_results": {"top": "left", "bottom": "left"}}', '{}'),
    (3, 'gauntlet', 4102444800, 2, 0, 'done',    '{"winner": "b", "lane_results": {"top": "left", "bottom": "right", "final": "right"}}', '{}'),
    (4, 'finals',   4102444800, 0, 2, 'done',    '{"winner": "a", "lane_results": {"top": "left", "bottom": "right", "final": "left"}}',
                                                 '{"bucket": 9900011, "round": 1, "match": 0}'),
    (5, 'ranked',   4102444800, 0, 2, 'pending', null, '{}'),
    (6, 'ranked',   4102444800 - 604800, 0, 2, 'done', '{"winner": "a", "lane_results": {"top": "left", "bottom": "left"}}', '{}')
  ) as v(k, kind, wk, a, b, st, res, meta)
 order by v.k;

-- J1
select pg_temp.as_user(null);
select pg_temp.ck('J1 没登录 ⇒ bad', public.finals_week_journey(4102444800, pg_temp.u(0)) ->> 'reason' = 'bad');
select pg_temp.as_user(pg_temp.u(1));
select pg_temp.ck('J1 号 1 不是参赛者 ⇒ not_entrant', public.finals_week_journey(4102444800, pg_temp.u(1)) ->> 'reason' = 'not_entrant');

-- J2 ~ J6（号 1 来看号 0：看的人不必是本人）
create temp table _r as select public.finals_week_journey(4102444800, pg_temp.u(0)) as j;
grant select on _r to public;
select pg_temp.ck('J2 ok、3 行、顺序 ranked / gauntlet / finals',
  (select (j ->> 'ok')::boolean and jsonb_array_length(j -> 'rows') = 3
          and j -> 'rows' -> 0 ->> 'kind' = 'ranked' and j -> 'rows' -> 1 ->> 'kind' = 'gauntlet' and j -> 'rows' -> 2 ->> 'kind' = 'finals'
     from _r), (select j::text from _r));
select pg_temp.ck('J3 ranked 两路都赢: me/me、final null、won',
  (select j -> 'rows' -> 0 -> 'lanes' ->> 'top' = 'me' and j -> 'rows' -> 0 -> 'lanes' ->> 'bottom' = 'me'
          and (j -> 'rows' -> 0 -> 'lanes' ->> 'final') is null and (j -> 'rows' -> 0 ->> 'won')::boolean from _r));
select pg_temp.ck('J4 gauntlet b 方翻面: top foe / bottom me / final me、won',
  (select j -> 'rows' -> 1 -> 'lanes' ->> 'top' = 'foe' and j -> 'rows' -> 1 -> 'lanes' ->> 'bottom' = 'me'
          and j -> 'rows' -> 1 -> 'lanes' ->> 'final' = 'me' and (j -> 'rows' -> 1 ->> 'won')::boolean from _r),
  (select (j -> 'rows' -> 1)::text from _r));
select pg_temp.ck('J5 对手 = 对手快照 profile / leaders; 不回快照与装备',
  (select j -> 'rows' -> 1 -> 'foe' ->> 'name' = '对手二' and j -> 'rows' -> 1 -> 'foe' ->> 'avatar' = 'angel'
          and j -> 'rows' -> 1 -> 'foe' -> 'leaders' = '["angel", "dice", "line"]'::jsonb
          and not (j -> 'rows' -> 1 -> 'foe') ? 'equipped' and position('"y"' in j::text) = 0 from _r));
select pg_temp.ck('J6 finals {bucket, round, match}',
  (select (j -> 'rows' -> 2 -> 'finals' ->> 'bucket')::int = 9900011 and (j -> 'rows' -> 2 -> 'finals' ->> 'round')::int = 1
          and (j -> 'rows' -> 2 -> 'finals' ->> 'match')::int = 0 and (j -> 'rows' -> 0 -> 'finals') = 'null'::jsonb from _r));

-- P
select pg_temp.ck('P anon 不能调、authenticated 能调; journey_lane 都不能调',
  not has_function_privilege('anon', 'public.finals_week_journey(bigint, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.finals_week_journey(bigint, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.journey_lane(jsonb, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.journey_lane(jsonb, text, text)', 'execute'));

do $$
declare v_fail int; v_n int; v_msg text;
begin
  select count(*) filter (where not pass), count(*) into v_fail, v_n from _chk;
  select string_agg(name || ' :: ' || info, ' | ') into v_msg from _chk where not pass;
  if v_fail = 0 then
    raise exception 'ALL PASS (% 条)', v_n;
  else
    raise exception 'FAIL % / %: %', v_fail, v_n, v_msg;
  end if;
end $$;
