-- 20261122b 轮空算一轮 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta|prod --rehearse 20261122b_econ_facts_finals_bye
-- 造人：本事务内新建 6 个号，在本周（econ_week_now）造两张表：
--   组 A（3 人, 4 座）：座次 [0,3,1,2] ⇒ 第 1 轮第 0 场 = 种子 0 对空座(3) ⇒ 种子 0 轮空；第 1 场 = 种子 1 对 种子 2(真打)
--   冠军杯 C（6 人, 8 座）：座次 [0,7,3,4,1,6,2,5] ⇒ 第 0 场 0 对 7(空)、第 2 场 1 对 6(空) ⇒ 种子 0、1 轮空
--   finals_results 照 finals_advance：轮空场 winner_side = 0；真打那一场再写一行(winner_side = 1, 但没有裁判任务)。
-- 判据：
--   Y1 finals_byes：组 A 种子 0 = 1；种子 1 / 种子 2 = 0(真打那场不算轮空)
--   Y2 冠军杯 C 种子 0、1 各 1 个轮空 ⇒ 同时在组 A 轮空又在冠军杯轮空的号 = 2
--   Y3 econ_facts finals：n / w 各加轮空数, minted 不加(仍 0)
--   Y4 econ_commit 场次闸：该号本周 0 场裁判局、2 次轮空 ⇒ bt = 2 的流水收、bt = 3 照旧 bt_over
--   Y5 没进任何表的号：finals_byes = 0, econ_facts finals n = 0
--   P  权限：finals_byes / econ_facts 不给 anon / authenticated
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

insert into _u select g, gen_random_uuid() from generate_series(0, 6) g;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

-- 组 A(编号 9900001, 3 人): 种子 0 = 号 0, 种子 1 = 号 1, 种子 2 = 号 2
insert into public.finals_buckets (season_week, bucket_no, n, round, closed)
  values (public.econ_week_now(), 9900001, 3, 1, false);
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  select public.econ_week_now(), 9900001, k, pg_temp.u(k), 'u' || k, '{}'::jsonb from generate_series(0, 2) k;
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
  values (public.econ_week_now(), 9900001, 1, 0, 0, 0),     -- 轮空(种子 0 对 空座 3)
         (public.econ_week_now(), 9900001, 1, 1, 1, 0);     -- 真打(种子 1 对 2, 下侧胜)

-- 冠军杯 C(编号 9900002, 6 人): 种子 0 = 号 0(同一个号又进了冠军杯), 种子 1..5 = 号 3,4,5,6,1
insert into public.finals_buckets (season_week, bucket_no, n, round, closed)
  values (public.econ_week_now(), 9900002, 6, 1, false);
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  values (public.econ_week_now(), 9900002, 0, pg_temp.u(0), 'c0', '{}'::jsonb),
         (public.econ_week_now(), 9900002, 1, pg_temp.u(3), 'c1', '{}'::jsonb),
         (public.econ_week_now(), 9900002, 2, pg_temp.u(4), 'c2', '{}'::jsonb),
         (public.econ_week_now(), 9900002, 3, pg_temp.u(5), 'c3', '{}'::jsonb),
         (public.econ_week_now(), 9900002, 4, pg_temp.u(6), 'c4', '{}'::jsonb),
         (public.econ_week_now(), 9900002, 5, pg_temp.u(1), 'c5', '{}'::jsonb);
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
  values (public.econ_week_now(), 9900002, 1, 0, 0, 0),     -- 种子 0 对 空座 7
         (public.econ_week_now(), 9900002, 1, 2, 0, 0);     -- 种子 1 对 空座 6

select pg_temp.ck('Y0 分母: 座次表与方案一致(4 座 [0,3,1,2] / 8 座 第 0 场 0-7、第 2 场 1-6)',
  public.finals_seed_at_seat(4, 1) = 3 and public.finals_seed_at_seat(8, 1) = 7
  and public.finals_seed_at_seat(8, 4) = 1 and public.finals_seed_at_seat(8, 5) = 6);

select pg_temp.ck('Y1 组 A: 种子 0(号 0)轮空 1 次; 真打那两人(号 1 / 号 2)只算组 A 的 0 次',
  public.finals_byes(pg_temp.u(2), public.econ_week_now()) = 0
  and public.finals_byes(pg_temp.u(0), public.econ_week_now()) >= 1,
  format('u0=%s u1=%s u2=%s', public.finals_byes(pg_temp.u(0), public.econ_week_now()),
         public.finals_byes(pg_temp.u(1), public.econ_week_now()), public.finals_byes(pg_temp.u(2), public.econ_week_now())));
select pg_temp.ck('Y2 号 0 组 A 轮空 + 冠军杯轮空 = 2; 冠军杯种子 1(号 3)= 1; 种子 5(号 1)真打 = 0',
  public.finals_byes(pg_temp.u(0), public.econ_week_now()) = 2
  and public.finals_byes(pg_temp.u(3), public.econ_week_now()) = 1
  and public.finals_byes(pg_temp.u(1), public.econ_week_now()) = 0,
  format('u0=%s u3=%s u1=%s', public.finals_byes(pg_temp.u(0), public.econ_week_now()),
         public.finals_byes(pg_temp.u(3), public.econ_week_now()), public.finals_byes(pg_temp.u(1), public.econ_week_now())));

create temp table _f as select public.econ_facts(pg_temp.u(0), public.econ_week_now()) as f;
select pg_temp.ck('Y3 econ_facts(号 0): finals n = 2, w = 2, minted = 0(轮空不铸币)',
  (select (f -> 'finals' ->> 'n')::int = 2 and (f -> 'finals' ->> 'w')::int = 2 and (f -> 'finals' ->> 'minted')::int = 0 from _f),
  (select (f -> 'finals')::text from _f));
select pg_temp.ck('Y5 没进任何表的号(号 6 只在冠军杯真打): finals n = 0',
  (select (public.econ_facts(pg_temp.u(6), public.econ_week_now()) -> 'finals' ->> 'n')::int = 0));

-- Y4 场次闸: 号 0 本周 0 场裁判局 + 2 次轮空 ⇒ 总场次 2
select pg_temp.as_user(pg_temp.u(0));
create temp table _c2 as select public.econ_commit(public.econ_week_now(), 0, '[{"op": "income", "src": "finals_reveal", "bt": 2, "seq": 0}]'::jsonb, null) as r;
select pg_temp.ck('Y4 号 0: bt = 2 的流水收下(原来 0 场 ⇒ bt_over)', (select (r ->> 'ok')::boolean from _c2), (select r::text from _c2));
create temp table _c3 as select public.econ_commit(public.econ_week_now(), 1, '[{"op": "income", "src": "finals_reveal", "bt": 3, "seq": 1}]'::jsonb, null) as r;
select pg_temp.ck('Y4 号 0: bt = 3 照旧 bt_over(只放宽轮空那几场)', (select r ->> 'why' = 'bt_over' from _c3), (select r::text from _c3));
select pg_temp.as_user(null);

select pg_temp.ck('P finals_byes / econ_facts 不给 anon / authenticated',
  not has_function_privilege('anon', 'public.finals_byes(uuid, bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.finals_byes(uuid, bigint)', 'execute')
  and not has_function_privilege('anon', 'public.econ_facts(uuid, bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_facts(uuid, bigint)', 'execute'));

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
