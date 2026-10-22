-- 20261022b 服务器裁判局的宝箱龟进度回写 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：tools/sb_migrate.py sandbox / beta --rehearse / prod --rehearse 20261022b_referee_chest
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 整个事务回滚，造的账号 / 组 / 任务一个都不留。
-- 判据（每条配对照组）：
--   S1 周六：referee_complete 写回带 chest 的结果单 ⇒ result 顶层存着 chest（referee_complete 本段没改，量它没丢）
--   S2 周六：A 自己查 referee_job_status ⇒ 多一个 chest，内容与结果单逐字相同
--   S3 周六对照：结果单没有 chest（老裁判程序）⇒ 回包没有 chest 这个键（与本段之前逐字相同）
--   S4 周六：任务还没算完（claimed）⇒ 不回 chest；别人的任务 ⇒ no_job
--   F1 周日：没翻面 ⇒ pending、不回 chest
--   F2 周日：翻面后 A 拿 chest、B 拿 chest_b（侧由服务端认）
--   F3 周日：老结果单没有 chest_b ⇒ B 的回包与本段之前逐字相同（{"ok","status","coins"}）
--   F4 周日：被兜底抢先（superseded）⇒ 两边都不回 chest
--   G  权限不变：两个接口只给 authenticated；referee_complete 只给 service_role
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as h, gen_random_uuid() as x,
         extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint + 6 * 86400 as wk;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ids to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.snap(p_name text) returns jsonb language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array('basic', 'stone', 'chest'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('basic', 'stone'), 'bottom', jsonb_build_array('chest')),
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name), 'season_level', 5)
$$;
create or replace function pg_temp.bucket(p_b int) returns void language sql as $$
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
    values ((select wk from _ids), p_b, 2, 1, now() - interval '1 hour', false);
  insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
    values ((select wk from _ids), p_b, 0, (select a from _ids), 'amy', pg_temp.snap('amy')),
           ((select wk from _ids), p_b, 1, (select h from _ids), 'hal', pg_temp.snap('hal'));
$$;
create or replace function pg_temp.fjob(p_b int) returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account,
      a_snapshot, b_snapshot, status, claimed_by, claimed_at, meta)
    values ('finals', format('finals:%s:%s:%s:%s', (select wk from _ids), p_b, 1, 0), (select wk from _ids), '9.9.9', 77,
      (select a from _ids), (select h from _ids), pg_temp.snap('amy'), pg_temp.snap('hal'), 'claimed', 'w1', now(),
      jsonb_build_object('bucket', p_b, 'round', 1, 'match', 0, 'seed0', 0, 'seed1', 1))
  returning job_id
$$;
create or replace function pg_temp.result(p_job bigint, p_extra jsonb) returns jsonb language sql as $$
  select jsonb_build_object('ok', true, 'match_id', j.match_id::text, 'seed', j.seed, 'client_version', j.client_version,
    'winner', 'b', 'steps', 4000, 'score_code', 1, 'replay_b64', 'QUJD') || coalesce(p_extra, '{}'::jsonb)
  from public.referee_jobs j where j.job_id = p_job
$$;
create or replace function pg_temp.fcoins(p_uid uuid, p_b int) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(p_uid);
  return public.referee_finals_coins((select wk from _ids), p_b, 1, 0);
end $$;
create or replace function pg_temp.status(p_uid uuid, p_job bigint) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(p_uid);
  return public.referee_job_status(p_job);
end $$;
-- 一份周六任务: 先以 a_account = null 走真写回(与 20261020d 的 C 段同一造法), 再把账号挂上去好让 A 查
create or replace function pg_temp.gjob(p_extra jsonb) returns bigint language plpgsql as $$
declare jid bigint;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
      status, claimed_by, claimed_at, meta)
    values ('gauntlet', 'chk:' || gen_random_uuid()::text, (select wk from _ids), '9.9.9', 77, null, '{}'::jsonb, '{}'::jsonb,
      'claimed', 'w1', now(), '{}'::jsonb) returning job_id into jid;
  if p_extra is not null then
    perform public.referee_complete(jid, 'w1', pg_temp.result(jid, p_extra));
  end if;
  update public.referee_jobs set a_account = (select a from _ids) where job_id = jid;
  return jid;
end $$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select a, 'authenticated', 'authenticated', false, now() from _ids
  union all select h, 'authenticated', 'authenticated', false, now() from _ids
  union all select x, 'authenticated', 'authenticated', false, now() from _ids;
update public.referee_config set finals_on = true, finals_version = '9.9.9' where id = 1;
insert into public.referee_versions (client_version, enabled) values ('9.9.9', true)
  on conflict (client_version) do update set enabled = true;

-- ── 周六 ──
create temp table _g1 as select pg_temp.gjob('{"coins": 2, "chest": {"value": 4521.0, "won": ["wood_shield"]}}'::jsonb) as id;
select pg_temp.ck('S1 写回后 result 顶层存着 chest',
  (select result->'chest' from public.referee_jobs where job_id = (select id from _g1)) = '{"value": 4521.0, "won": ["wood_shield"]}'::jsonb,
  (select coalesce(result->'chest', 'null'::jsonb)::text from public.referee_jobs where job_id = (select id from _g1)));
select pg_temp.ck('S1 分母: 任务确实写回成 done', (select status from public.referee_jobs where job_id = (select id from _g1)) = 'done');
select pg_temp.ck('S2 A 查 referee_job_status ⇒ 多一个 chest、与结果单逐字相同',
  pg_temp.status((select a from _ids), (select id from _g1))->'chest' = '{"value": 4521.0, "won": ["wood_shield"]}'::jsonb,
  pg_temp.status((select a from _ids), (select id from _g1))::text);
select pg_temp.ck('S2 对照: coins 照旧回 2', (pg_temp.status((select a from _ids), (select id from _g1))->>'coins')::int = 2);
create temp table _g0 as select pg_temp.gjob('{"coins": 1}'::jsonb) as id;
select pg_temp.ck('S3 老结果单没有 chest ⇒ 回包没有 chest 这个键',
  not (pg_temp.status((select a from _ids), (select id from _g0)) ? 'chest')
  and (pg_temp.status((select a from _ids), (select id from _g0))->>'ok')::boolean,
  pg_temp.status((select a from _ids), (select id from _g0))::text);
create temp table _gp as select pg_temp.gjob(null) as id;
update public.referee_jobs set result = '{"chest": {"value": 1.0, "won": []}}'::jsonb where job_id = (select id from _gp);
select pg_temp.ck('S4 还没算完(claimed)⇒ 不回 chest', not (pg_temp.status((select a from _ids), (select id from _gp)) ? 'chest')
  and pg_temp.status((select a from _ids), (select id from _gp))->>'status' = 'claimed');
select pg_temp.ck('S4 别人的任务 ⇒ no_job', pg_temp.status((select h from _ids), (select id from _g1))->>'reason' = 'no_job');

-- ── 周日 ──
select pg_temp.bucket(0);
create temp table _f0 as select pg_temp.fjob(0) as id;
select public.referee_complete((select id from _f0), 'w1', pg_temp.result((select id from _f0),
  '{"coins": 7, "coins_b": 4, "chest": {"value": 7003.0, "won": ["rum", "stone"]}, "chest_b": {"value": 6949.0, "won": ["chain", "blood_dice"]}}'::jsonb));
select pg_temp.ck('F1 没翻面 ⇒ pending、A 不回 chest', pg_temp.fcoins((select a from _ids), 0)->>'status' = 'pending'
  and not (pg_temp.fcoins((select a from _ids), 0) ? 'chest'));
select pg_temp.ck('F1 没翻面 ⇒ pending、B 不回 chest', not (pg_temp.fcoins((select h from _ids), 0) ? 'chest'));
update public.finals_buckets set round = 2 where season_week = (select wk from _ids) and bucket_no = 0;
select pg_temp.ck('F2 A（上侧）⇒ chest = 结果单的 chest',
  pg_temp.fcoins((select a from _ids), 0)->'chest' = '{"value": 7003.0, "won": ["rum", "stone"]}'::jsonb,
  pg_temp.fcoins((select a from _ids), 0)::text);
select pg_temp.ck('F2 B（下侧）⇒ chest = 结果单的 chest_b',
  pg_temp.fcoins((select h from _ids), 0)->'chest' = '{"value": 6949.0, "won": ["chain", "blood_dice"]}'::jsonb,
  pg_temp.fcoins((select h from _ids), 0)::text);
select pg_temp.ck('F2 对照: 币照旧 A 7 / B 4', (pg_temp.fcoins((select a from _ids), 0)->>'coins')::int = 7
  and (pg_temp.fcoins((select h from _ids), 0)->>'coins')::int = 4);
select pg_temp.bucket(1);
create temp table _f1 as select pg_temp.fjob(1) as id;
select public.referee_complete((select id from _f1), 'w1', pg_temp.result((select id from _f1),
  '{"coins": 5, "chest": {"value": 3000.0, "won": ["dagger"]}}'::jsonb));
update public.finals_buckets set closed = true where season_week = (select wk from _ids) and bucket_no = 1;
select pg_temp.ck('F3 老结果单没有 chest_b ⇒ B 回包与本段之前逐字相同',
  pg_temp.fcoins((select h from _ids), 1) = '{"ok": true, "status": "done", "coins": 0}'::jsonb,
  pg_temp.fcoins((select h from _ids), 1)::text);
select pg_temp.ck('F3 对照: A 照样拿 chest', pg_temp.fcoins((select a from _ids), 1) ? 'chest');
select pg_temp.bucket(2);
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
  values ((select wk from _ids), 2, 1, 0, 0, 1);
update public.finals_buckets set round = 2 where season_week = (select wk from _ids) and bucket_no = 2;
create temp table _f2 as select pg_temp.fjob(2) as id;
create temp table _cp2 as select public.referee_complete((select id from _f2), 'w1', pg_temp.result((select id from _f2),
  '{"coins": 9, "chest": {"value": 9.0, "won": []}, "chest_b": {"value": 9.0, "won": []}}'::jsonb)) as r;
select pg_temp.ck('F4 分母: 写回被记成 superseded', ((select r from _cp2)->>'superseded')::boolean);
select pg_temp.ck('F4 superseded ⇒ 两边都不回 chest', not (pg_temp.fcoins((select a from _ids), 2) ? 'chest')
  and not (pg_temp.fcoins((select h from _ids), 2) ? 'chest'));

-- ── 权限 ──
select pg_temp.ck('G referee_job_status: authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.referee_job_status(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.referee_job_status(bigint)', 'execute'));
select pg_temp.ck('G referee_finals_coins: authenticated 能调、anon 不能',
  has_function_privilege('authenticated', 'public.referee_finals_coins(bigint, int, int, int)', 'execute')
  and not has_function_privilege('anon', 'public.referee_finals_coins(bigint, int, int, int)', 'execute'));
select pg_temp.ck('G referee_complete 仍只给 service_role',
  has_function_privilege('service_role', 'public.referee_complete(bigint, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_complete(bigint, text, jsonb)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 18 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
