-- 20261106 局外经济流水上服务器 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261106_econ_ops
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、插的行一个都不留。
-- 判据：
--   A 身份 / 周 / 参数：没登录 ⇒ auth；不是服务器这一周 ⇒ week（回服务器的周）；不是数组 ⇒ bad_ops；超过 500 条 ⇒ too_many；
--     种类不认识 ⇒ bad_kind；某条不是对象 / 没有 op ⇒ bad_op 且整批不落
--   U 上传：从 0 传两条 ⇒ next 2、两行 src=client；断号（从 3 起）⇒ gap 回 next 2；原样重传 ⇒ ok 不多行；重传内容变了 ⇒ mismatch
--   S 种子：接着要 refresh ⇒ 发在第 2 条（= 已上传的下一条）、0 ≤ 种子 < 2^32、第 2 条落一行 src=server；
--     同一请求重试 ⇒ 回同一个种子（again）、不多行；带着第 2 条（种类 / 种子对）+ 第 3 条一起传 ⇒ 第 2 条补上 bt、仍是 server、第 3 条落；
--     第 2 条种子对不上 / 种类对不上 ⇒ mismatch；那个位置已经是别的操作时再要种子 ⇒ taken；
--     再要一个 candy ⇒ 发在下一条、和上一个种子不同
--   R 行级策略：别人读不到我的行；我读得到；客户端直接 insert / update 一律写不进
--   P 权限：econ_commit 只给 authenticated；econ_week_now 不对外
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('me'), ('other');
create temp table _r (k text primary key, r jsonb);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _u to public;
grant all on _r to public;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.rows(p_k text) returns int language sql as $$
  select count(*)::int from public.econ_ops where account_id = pg_temp.u(p_k)
$$;

-- ── A 身份 / 周 / 参数 ──
do $$
declare r jsonb; wk bigint := public.econ_week_now();
begin
  perform pg_temp.as_user(null);
  r := public.econ_commit(wk, 0, '[]'::jsonb, null);
  perform pg_temp.ck('A1 没登录 ⇒ auth', r ->> 'reason' = 'auth', r::text);
  perform pg_temp.as_user(pg_temp.u('me'));
  r := public.econ_commit(wk - 604800, 0, '[]'::jsonb, null);
  perform pg_temp.ck('A2 不是服务器这一周 ⇒ week, 并回服务器的周', r ->> 'reason' = 'week' and (r ->> 'week')::bigint = wk, r::text);
  r := public.econ_commit(wk, 0, '{"op":"buy"}'::jsonb, null);
  perform pg_temp.ck('A3 不是数组 ⇒ bad_ops', r ->> 'reason' = 'bad_ops', r::text);
  r := public.econ_commit(wk, 0, (select jsonb_agg(jsonb_build_object('op', 'lock', 'on', true)) from generate_series(1, 501)), null);
  perform pg_temp.ck('A4 一批超过 500 条 ⇒ too_many', r ->> 'reason' = 'too_many', r::text);
  r := public.econ_commit(wk, 0, '[]'::jsonb, 'buy');
  perform pg_temp.ck('A5 要种子的种类不认识 ⇒ bad_kind', r ->> 'reason' = 'bad_kind', r::text);
  r := public.econ_commit(wk, 0, '[{"op":"lock","on":true},{"on":false}]'::jsonb, null);
  perform pg_temp.ck('A6 有一条没有 op ⇒ bad_op(at 1)且整批不落', r ->> 'reason' = 'bad_op' and (r ->> 'at')::int = 1
    and pg_temp.rows('me') = 0, r::text || ' rows=' || pg_temp.rows('me'));
  perform pg_temp.as_user(null);
end $$;

-- ── U 上传 ──
do $$
declare r jsonb; wk bigint := public.econ_week_now();
  o0 jsonb := '{"op":"buy","slot":1,"seq":0,"bt":3}'; o1 jsonb := '{"op":"lock","on":true,"seq":1,"bt":3}';
begin
  perform pg_temp.as_user(pg_temp.u('me'));
  r := public.econ_commit(wk, 0, jsonb_build_array(o0, o1), null);
  perform pg_temp.ck('U1 从 0 传两条 ⇒ ok, next 2, 两行都是 client', (r ->> 'ok')::boolean and (r ->> 'next')::int = 2
    and (select count(*) from public.econ_ops where account_id = pg_temp.u('me') and src = 'client') = 2, r::text);
  r := public.econ_commit(wk, 3, jsonb_build_array(o0), null);
  perform pg_temp.ck('U2 断号(从 3 起)⇒ gap, 回 next 2', r ->> 'reason' = 'gap' and (r ->> 'next')::int = 2, r::text);
  r := public.econ_commit(wk, 0, jsonb_build_array(o0, o1), null);
  perform pg_temp.ck('U3 原样重传 ⇒ ok, 不多行', (r ->> 'ok')::boolean and pg_temp.rows('me') = 2, r::text);
  r := public.econ_commit(wk, 1, jsonb_build_array('{"op":"lock","on":false,"seq":1,"bt":3}'::jsonb), null);
  perform pg_temp.ck('U4 重传内容变了(第 1 条)⇒ mismatch at 1', r ->> 'reason' = 'mismatch' and (r ->> 'at')::int = 1, r::text);
  perform pg_temp.as_user(null);
end $$;

-- ── S 种子 ──
do $$
declare r jsonb; r2 jsonb; s1 bigint; wk bigint := public.econ_week_now();
  o0 jsonb := '{"op":"buy","slot":1,"seq":0,"bt":3}'; o1 jsonb := '{"op":"lock","on":true,"seq":1,"bt":3}';
begin
  perform pg_temp.as_user(pg_temp.u('me'));
  r := public.econ_commit(wk, 2, '[]'::jsonb, 'refresh');
  s1 := (r ->> 'seed')::bigint;
  perform pg_temp.ck('S1 接着要 refresh ⇒ 发在第 2 条, 0 ≤ 种子 < 2^32, next 3', (r ->> 'ok')::boolean and (r ->> 'seq')::int = 2
    and s1 >= 0 and s1 < 4294967296 and (r ->> 'next')::int = 3, r::text);
  perform pg_temp.ck('S2 第 2 条落一行 src=server, 内容 = {op: refresh, seed}',
    (select src = 'server' and op ->> 'op' = 'refresh' and (op ->> 'seed')::bigint = s1
      from public.econ_ops where account_id = pg_temp.u('me') and week = wk and seq = 2), r::text);
  r2 := public.econ_commit(wk, 2, '[]'::jsonb, 'refresh');
  perform pg_temp.ck('S3 同一请求重试 ⇒ 回同一个种子(again), 不多行', (r2 ->> 'again')::boolean and (r2 ->> 'seed')::bigint = s1
    and pg_temp.rows('me') = 3, r2::text);
  r2 := public.econ_commit(wk, 0, jsonb_build_array(o0, o1), 'refresh');
  perform pg_temp.ck('S4 带着前两条一起重试 ⇒ 仍是同一个种子', (r2 ->> 'seed')::bigint = s1 and pg_temp.rows('me') = 3, r2::text);
  r2 := public.econ_commit(wk, 2, jsonb_build_array(jsonb_build_object('op', 'refresh', 'seed', s1 + 1, 'seq', 2, 'bt', 3)), null);
  perform pg_temp.ck('S5 第 2 条种子对不上 ⇒ mismatch', r2 ->> 'reason' = 'mismatch' and (r2 ->> 'at')::int = 2, r2::text);
  r2 := public.econ_commit(wk, 2, jsonb_build_array(jsonb_build_object('op', 'roll', 'seed', s1, 'seq', 2, 'bt', 3)), null);
  perform pg_temp.ck('S6 第 2 条种类对不上(拿 refresh 的种子冒充 roll)⇒ mismatch', r2 ->> 'reason' = 'mismatch', r2::text);
  r2 := public.econ_commit(wk, 2, jsonb_build_array(jsonb_build_object('op', 'refresh', 'seed', s1, 'seq', 2, 'bt', 3),
    '{"op":"buy","slot":4,"seq":3,"bt":3}'::jsonb), null);
  perform pg_temp.ck('S7 第 2 条对上 + 第 3 条 ⇒ ok next 4; 第 2 条补上 bt 且仍是 server', (r2 ->> 'next')::int = 4
    and (select src = 'server' and (op ->> 'bt')::int = 3 from public.econ_ops where account_id = pg_temp.u('me') and week = wk and seq = 2),
    r2::text);
  r2 := public.econ_commit(wk, 3, '[]'::jsonb, 'roll');
  perform pg_temp.ck('S8 那个位置(第 3 条)已经是别的操作时要种子 ⇒ taken', r2 ->> 'reason' = 'taken' and (r2 ->> 'at')::int = 3, r2::text);
  r2 := public.econ_commit(wk, 4, '[]'::jsonb, 'candy');
  perform pg_temp.ck('S9 再要 candy ⇒ 发在第 4 条, 与上一个种子不同', (r2 ->> 'seq')::int = 4 and (r2 ->> 'seed')::bigint <> s1, r2::text);
  perform pg_temp.as_user(null);
end $$;

-- ── R 行级策略 ──
grant select, insert, update on public.econ_ops to authenticated;   -- = Supabase 默认给 authenticated 的表权限; 挡人的只该是行级策略
do $$
declare n_other int; n_me int; ok_i boolean := false; ok_u boolean := false; e text := ''; wk bigint := public.econ_week_now();
begin
  perform pg_temp.as_user(pg_temp.u('other'));
  set local role authenticated;
  select count(*) into n_other from public.econ_ops where account_id = pg_temp.u('me');
  begin
    insert into public.econ_ops (account_id, week, seq, op) values (pg_temp.u('other'), wk, 0, '{"op":"income","coins":999}');
    ok_i := true;
  exception when others then e := sqlerrm;
  end;
  reset role;
  perform pg_temp.as_user(pg_temp.u('me'));
  set local role authenticated;
  select count(*) into n_me from public.econ_ops where account_id = pg_temp.u('me');
  begin
    update public.econ_ops set op = '{"op":"income","coins":999}' where account_id = pg_temp.u('me') and seq = 0;
    if found then ok_u := true; end if;
  exception when others then e := e || ' / ' || sqlerrm;
  end;
  reset role;
  perform pg_temp.as_user(null);
  perform pg_temp.ck('R1 别人读不到我的流水', n_other = 0, n_other::text);
  perform pg_temp.ck('R2 我读得到自己的(5 条)', n_me = 5, n_me::text);
  perform pg_temp.ck('R3 客户端直接 insert 写不进(只能经 econ_commit)', not ok_i, e);
  perform pg_temp.ck('R4 客户端直接 update 改不了已有的', not ok_u
    and (select op ->> 'op' from public.econ_ops where account_id = pg_temp.u('me') and seq = 0) = 'buy', e);
end $$;

-- ── P 权限 ──
select pg_temp.ck('P1 econ_commit 只给 authenticated(anon 不行)',
  has_function_privilege('authenticated', 'public.econ_commit(bigint, int, jsonb, text)', 'execute')
  and not has_function_privilege('anon', 'public.econ_commit(bigint, int, jsonb, text)', 'execute'));
select pg_temp.ck('P2 econ_week_now 不对外',
  not has_function_privilege('anon', 'public.econ_week_now()', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_week_now()', 'execute'));

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
