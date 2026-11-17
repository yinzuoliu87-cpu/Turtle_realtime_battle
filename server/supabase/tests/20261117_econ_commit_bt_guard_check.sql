-- 20261117 收流水拒收「场次戳超过本周总场次」—— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261117_econ_commit_bt_guard
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261117_econ_commit_bt_guard
-- 造人：一个新号（本事务内），以它的身份调 econ_commit。
-- 判据：
--   G1 本周 0 场：bt = 0 的流水照收
--   G2 本周 0 场：bt = 1 的新流水 ⇒ mismatch / why bt_over / at = 它的序号，一行都不落
--   G3 一批里前一条合法、后一条超 ⇒ 整批不落（两遍：先全校验再写）
--   G4 已经在库里的序号重发（v_at < next）不看 bt（只比对内容）⇒ 照旧 ok
--   G5 ranked_records 记了 2 场 ⇒ bt = 2 收、bt = 3 拒
--   G6 bt 写成 2.0（客户端 JSON 浮点）照样按数比；没有 bt 的流水照收
--   P  权限不变：authenticated 能调，anon 不能
-- ─────────────────────────────────────────────────────────────
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
create or replace function pg_temp.commit(p_from int, p_ops jsonb) returns jsonb language sql as $$
  select public.econ_commit(public.econ_week_now(), p_from, p_ops, null) $$;
create or replace function pg_temp.rows() returns int language sql as $$
  select count(*)::int from public.econ_ops where account_id = pg_temp.uid() and week = public.econ_week_now() $$;

insert into _u values (gen_random_uuid());
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
select pg_temp.as_user(pg_temp.uid());

-- G1
create temp table _g1 as select pg_temp.commit(0, '[{"op": "buy", "bt": 0, "seq": 0}]'::jsonb) as r;
select pg_temp.ck('G1 本周 0 场: bt = 0 照收', (select (r ->> 'ok')::boolean and (r ->> 'next')::int = 1 from _g1) and pg_temp.rows() = 1,
  (select r::text from _g1));

-- G2
create temp table _g2 as select pg_temp.commit(1, '[{"op": "income", "bt": 1, "seq": 1}]'::jsonb) as r;
select pg_temp.ck('G2 本周 0 场: bt = 1 ⇒ mismatch / bt_over / at = 1、一行不落',
  (select r ->> 'reason' = 'mismatch' and r ->> 'why' = 'bt_over' and (r ->> 'at')::int = 1 and (r ->> 'next')::int = 1 from _g2)
  and pg_temp.rows() = 1, (select r::text from _g2));

-- G3
create temp table _g3 as select pg_temp.commit(1, '[{"op": "buy", "bt": 0, "seq": 1}, {"op": "buy", "bt": 3, "seq": 2}]'::jsonb) as r;
select pg_temp.ck('G3 一批里后一条超 ⇒ 整批不落（at = 2）',
  (select r ->> 'reason' = 'mismatch' and (r ->> 'at')::int = 2 from _g3) and pg_temp.rows() = 1, (select r::text from _g3));

-- G4
create temp table _g4 as select pg_temp.commit(0, '[{"op": "buy", "bt": 0, "seq": 0}]'::jsonb) as r;
select pg_temp.ck('G4 已在库里的序号重发 ⇒ ok', (select (r ->> 'ok')::boolean from _g4) and pg_temp.rows() = 1, (select r::text from _g4));

-- G5 / G6
insert into public.ranked_records (season_week, account_id, battles) values (public.econ_week_now(), pg_temp.uid(), 2);
create temp table _g5 as select pg_temp.commit(1, '[{"op": "income", "bt": 2, "seq": 1}]'::jsonb) as a,
                                pg_temp.commit(2, '[{"op": "buy", "bt": 3, "seq": 2}]'::jsonb) as b;
select pg_temp.ck('G5 记了 2 场: bt = 2 收', (select (a ->> 'ok')::boolean from _g5), (select a::text from _g5));
select pg_temp.ck('G5 记了 2 场: bt = 3 拒（bt_over）', (select b ->> 'why' = 'bt_over' from _g5) and pg_temp.rows() = 2, (select b::text from _g5));
create temp table _g6 as select pg_temp.commit(2, '[{"op": "buy", "bt": 2.0, "seq": 2}, {"op": "equip", "seq": 3}]'::jsonb) as r;
select pg_temp.ck('G6 bt = 2.0 按数比、没有 bt 的照收', (select (r ->> 'ok')::boolean and (r ->> 'next')::int = 4 from _g6) and pg_temp.rows() = 4,
  (select r::text from _g6));

-- P
select pg_temp.as_user(null);
select pg_temp.ck('P authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.econ_commit(bigint, int, jsonb, text)', 'execute')
  and not has_function_privilege('anon', 'public.econ_commit(bigint, int, jsonb, text)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 8 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
