-- 20261121 种子行按数比 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta|prod --rehearse 20261121_econ_seed_numeric
-- 造人：一个新号（本事务内），以它的身份调 econ_commit。
-- 判据：
--   S1 服务器发了种子（种子行），客户端把这一条传上来、种子写成浮点 N.0 ⇒ ok，行数不变、那一行换成客户端那份（补上 bt）
--   S2 种子写错（N+1）⇒ mismatch / at = 那一行
--   S3 种类不对（buy 冒充 refresh）⇒ mismatch
--   S4 econ_num_same：数按数比；非数照旧按字面；null 对 null 相同
--   B  bt 守卫照旧：本周 0 场，新流水 bt = 1 ⇒ mismatch / bt_over
--   P  权限不变：authenticated 能调 econ_commit，anon 不能；econ_num_same 只给内部
begin;
create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (id uuid);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.uid() returns uuid language sql as $$ select id from _u limit 1 $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.rows() returns int language sql as $$
  select count(*)::int from public.econ_ops where account_id = pg_temp.uid() and week = public.econ_week_now() $$;

insert into _u values (gen_random_uuid());
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
select pg_temp.as_user(pg_temp.uid());

-- 第 0 条: 普通流水; 要一个 refresh 种子(服务器写下第 1 条种子行)
create temp table _s0 as select public.econ_commit(public.econ_week_now(), 0, '[{"op": "leaders", "bt": 0, "seq": 0}]'::jsonb, 'refresh') as r;
select pg_temp.ck('S0 分母: 拿到种子、库里 2 行(第 1 行是服务器种子行)',
  (select (r ->> 'ok')::boolean and (r ->> 'seq')::int = 1 from _s0) and pg_temp.rows() = 2
  and (select src = 'server' from public.econ_ops where account_id = pg_temp.uid() and week = public.econ_week_now() and seq = 1),
  (select r::text from _s0));

-- S2 种子写错
create temp table _s2 as select public.econ_commit(public.econ_week_now(), 1,
  jsonb_build_array(jsonb_build_object('op', 'refresh', 'bt', 0, 'seq', 1, 'seed', ((select r ->> 'seed' from _s0)::numeric + 1))), null) as r;
select pg_temp.ck('S2 种子写错 ⇒ mismatch / at = 1', (select r ->> 'reason' = 'mismatch' and (r ->> 'at')::int = 1 from _s2), (select r::text from _s2));

-- S3 种类不对
create temp table _s3 as select public.econ_commit(public.econ_week_now(), 1,
  jsonb_build_array(jsonb_build_object('op', 'buy', 'bt', 0, 'seq', 1, 'seed', (select (r ->> 'seed')::numeric from _s0))), null) as r;
select pg_temp.ck('S3 种类不对 ⇒ mismatch', (select r ->> 'reason' = 'mismatch' from _s3), (select r::text from _s3));

-- S1 种子写成浮点 N.0(客户端存档读回来的样子)
create temp table _s1 as select public.econ_commit(public.econ_week_now(), 1,
  ('[{"op": "refresh", "bt": 0, "seq": 1, "seed": ' || (select r ->> 'seed' from _s0) || '.0}]')::jsonb, null) as r;
select pg_temp.ck('S1 种子写成 N.0 ⇒ ok、行数不变、那一行换成客户端那份(带 bt)',
  (select (r ->> 'ok')::boolean and (r ->> 'next')::int = 2 from _s1) and pg_temp.rows() = 2
  and (select op ? 'bt' from public.econ_ops where account_id = pg_temp.uid() and week = public.econ_week_now() and seq = 1),
  (select r::text from _s1));

-- S4 econ_num_same
select pg_temp.ck('S4 econ_num_same: 583806406.0 = 583806406', public.econ_num_same('583806406.0', '583806406'));
select pg_temp.ck('S4 econ_num_same: 1 ≠ 2', not public.econ_num_same('1', '2'));
select pg_temp.ck('S4 econ_num_same: 非数按字面', public.econ_num_same('abc', 'abc') and not public.econ_num_same('abc', 'abd'));
select pg_temp.ck('S4 econ_num_same: null 对 null 相同、null 对数不同', public.econ_num_same(null, null) and not public.econ_num_same(null, '1'));

-- B bt 守卫照旧
create temp table _b as select public.econ_commit(public.econ_week_now(), 2, '[{"op": "income", "bt": 1, "seq": 2}]'::jsonb, null) as r;
select pg_temp.ck('B bt 守卫照旧: 本周 0 场 bt = 1 ⇒ mismatch / bt_over', (select r ->> 'why' = 'bt_over' from _b), (select r::text from _b));

-- P 权限
select pg_temp.ck('P authenticated 能调 econ_commit', has_function_privilege('authenticated', 'public.econ_commit(bigint, int, jsonb, text)', 'execute'));
select pg_temp.ck('P anon 不能调 econ_commit', not has_function_privilege('anon', 'public.econ_commit(bigint, int, jsonb, text)', 'execute'));
select pg_temp.ck('P econ_num_same 不给 anon / authenticated',
  not has_function_privilege('anon', 'public.econ_num_same(text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_num_same(text, text)', 'execute'));

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
