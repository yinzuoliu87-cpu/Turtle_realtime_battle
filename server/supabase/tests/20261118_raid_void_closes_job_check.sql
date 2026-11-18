-- 20261118 作废偷袭时顺手关掉它的裁判任务 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261118_raid_void_closes_job
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261118_raid_void_closes_job
-- 造数：一个真库里没有的版本号 9.9.7-void；四场偷袭（raid_id 用负数，真库不会有），各配一条裁判任务。
-- 判据：
--   V1 任务 pending ⇒ 作废后任务 failed、error = raid_void:<原因>、done_at 有值；偷袭 void；发件箱恰好一条 settle void
--   V2 任务 claimed（正在算）⇒ 同样 failed
--   V3 任务已 done ⇒ 作废（bad_result 那条路）不动任务，★settle 照发（关任务那句 update 会改写 FOUND，不许吞掉 settle）
--   V4 同一场再作废一次 ⇒ 什么都不变（发件箱不多一条、任务不变）
--   V5 p_send = false ⇒ 任务照样关、发件箱不写
--   V6 作废后领活领不到它、积压里没有它
--   P  权限不变：anon / authenticated 都不能调 raid_void
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;

-- 造一场偷袭 + 它的裁判任务（任务状态 p_status）；回偷袭的 id
create or replace function pg_temp.mk(p_raid bigint, p_status text) returns bigint language plpgsql as $$
declare v_job bigint; v_id bigint;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_snapshot, b_snapshot, status,
                                   claimed_by, claimed_at, result, done_at)
  values ('raid', 'chk-void:' || p_raid, 1, '9.9.7-void', 7, '{}'::jsonb, '{}'::jsonb, p_status,
          case when p_status = 'claimed' then 'chk-w' end, case when p_status = 'claimed' then now() end,
          case when p_status = 'done' then '{"winner": "a"}'::jsonb end, case when p_status = 'done' then now() end)
  returning job_id into v_job;
  insert into public.raid_jobs (raid_id, attacker, defender, expire_at, season_week, status, referee_job_id)
  values (p_raid, 'chkAtk' || abs(p_raid), 'chkDef' || abs(p_raid), now() + interval '1 hour', 1,
          case when p_status = 'claimed' then 'started' else 'queued' end, v_job)
  returning id into v_id;
  return v_id;
end $$;
create or replace function pg_temp.jst(p_raid bigint) returns text language sql as $$
  select j.status from public.referee_jobs j join public.raid_jobs r on r.referee_job_id = j.job_id where r.raid_id = p_raid $$;
create or replace function pg_temp.settles(p_raid bigint) returns int language sql as $$
  select count(*)::int from public.mainsite_outbox where topic = 'settle' and idem_key = p_raid::text $$;

-- V1 pending
select public.raid_void(pg_temp.mk(-9101, 'pending'), 'chk_manual');
select pg_temp.ck('V1 pending ⇒ 任务 failed、error = raid_void:chk_manual、有 done_at',
  exists (select 1 from public.referee_jobs j join public.raid_jobs r on r.referee_job_id = j.job_id
          where r.raid_id = -9101 and j.status = 'failed' and j.error = 'raid_void:chk_manual' and j.done_at is not null),
  coalesce(pg_temp.jst(-9101), 'null'));
select pg_temp.ck('V1 偷袭 void、发件箱恰好一条 settle void',
  exists (select 1 from public.raid_jobs where raid_id = -9101 and status = 'void' and result = 'void')
  and pg_temp.settles(-9101) = 1
  and exists (select 1 from public.mainsite_outbox where topic = 'settle' and idem_key = '-9101' and body ->> 'result' = 'void'),
  'settles=' || pg_temp.settles(-9101));

-- V2 claimed
select public.raid_void(pg_temp.mk(-9102, 'claimed'), 'chk_manual');
select pg_temp.ck('V2 claimed（正在算）⇒ 任务 failed', pg_temp.jst(-9102) = 'failed', coalesce(pg_temp.jst(-9102), 'null'));

-- V3 done（bad_result 那条路：任务已写回）
select public.raid_void(pg_temp.mk(-9103, 'done'), 'bad_result');
select pg_temp.ck('V3 任务已 done ⇒ 不动任务', pg_temp.jst(-9103) = 'done', coalesce(pg_temp.jst(-9103), 'null'));
select pg_temp.ck('V3 ★任务不用关的那几条路照样发 settle void（关任务那句 update 不许吞掉 settle）', pg_temp.settles(-9103) = 1,
  'settles=' || pg_temp.settles(-9103));

-- V4 再作废一次
select public.raid_void((select id from public.raid_jobs where raid_id = -9101), 'again');
select pg_temp.ck('V4 同一场再作废 ⇒ 发件箱不多一条、error 不变',
  pg_temp.settles(-9101) = 1
  and exists (select 1 from public.referee_jobs j join public.raid_jobs r on r.referee_job_id = j.job_id
              where r.raid_id = -9101 and j.error = 'raid_void:chk_manual'),
  'settles=' || pg_temp.settles(-9101));

-- V5 p_send = false
select public.raid_void(pg_temp.mk(-9105, 'pending'), 'raid_expired', false);
select pg_temp.ck('V5 p_send = false ⇒ 任务照样关、发件箱不写', pg_temp.jst(-9105) = 'failed' and pg_temp.settles(-9105) = 0,
  coalesce(pg_temp.jst(-9105), 'null') || ' settles=' || pg_temp.settles(-9105));

-- V6 领活 / 积压
select pg_temp.ck('V6 作废后领活领不到它们',
  public.referee_claim('chk-void-w', array['9.9.7-void'], 8) = '[]'::jsonb);
select pg_temp.ck('V6 没有一条 9.9.7-void 的任务还 pending / claimed',
  not exists (select 1 from public.referee_jobs where client_version = '9.9.7-void' and status in ('pending', 'claimed')
              and match_key <> 'chk-void:-9103'));

-- P
select pg_temp.ck('P anon / authenticated 都不能调 raid_void',
  not has_function_privilege('anon', 'public.raid_void(bigint, text, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.raid_void(bigint, text, boolean)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 10 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
