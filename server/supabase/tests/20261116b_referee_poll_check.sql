-- 20261116b 裁判机一次请求问完所有活 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261116b_referee_poll
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261116b_referee_poll
-- 隔离：只用一个真库里没有的版本号 9.9.8-poll（真任务一份都领不到）；本事务内把现有的待重放 / 待发标成「不急」，
--       好量「没有」那一档（事务回滚，真数据不动）。
-- 判据：
--   R1 什么都没有：jobs = []、econ = false、outbox = false、v = 1；flags 与 referee_flags() 逐字相同
--   R2 照旧记心跳（referee_workers 有这个工人、seen_at = 本事务时刻）
--   R3 有正常任务也有补流：先给正常任务（没有 task 键、状态 claimed、claimed_by = 工人），补流还在 pending
--   R4 p_restream = false：正常任务空了也不领补流
--   R5 p_restream = true 且正常任务空了：领到补流（task = restream、带 expect_winner），补流行 claimed
--   R6 本周有 dirty 的号 ⇒ econ = true；领活不改 econ_state（dirty 还在）
--   R7 发件箱：只有没到点的 ⇒ false；有到点的 ⇒ true；领活不改 next_at
--   P  只给 service_role（anon / authenticated 都不行）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.poll(p_restream boolean) returns jsonb language sql as $$
  select public.referee_poll('chk-poll-0', array['9.9.8-poll'], p_restream) $$;

-- ── 隔离：现有的待重放 / 待发在本事务里先标成不急 ──
update public.econ_state set dirty = false where dirty;
update public.mainsite_outbox set next_at = now() + interval '1 hour' where done_at is null and next_at <= now();

-- R1 / R2
create temp table _r1 as select pg_temp.poll(true) as a;
select pg_temp.ck('R1 什么都没有: jobs = []、econ / outbox = false、v = 1',
  (select a->'jobs' = '[]'::jsonb and a->'econ' = 'false'::jsonb and a->'outbox' = 'false'::jsonb and a->'v' = '1'::jsonb from _r1),
  (select a::text from _r1));
select pg_temp.ck('R1 flags 与 referee_flags() 逐字相同',
  (select a->'flags' = public.referee_flags() from _r1), (select (a->'flags')::text from _r1));
select pg_temp.ck('R2 照旧记心跳',
  exists (select 1 from public.referee_workers where worker = 'chk-poll-0' and seen_at = now()
          and versions = array['9.9.8-poll']));

-- ── 造任务：一份正常任务 + 一份补流（补流的原任务已 done）──
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_snapshot, b_snapshot, status, result, done_at)
values ('gauntlet', 'chk-poll:done', 1, '9.9.8-poll', 11, '{}'::jsonb, '{}'::jsonb, 'done',
        '{"winner": "a", "digest": "d1"}'::jsonb, now());
insert into public.referee_restream (match_id, job_id, client_version)
  select match_id, job_id, client_version from public.referee_jobs where match_key = 'chk-poll:done';
insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_snapshot, b_snapshot)
values ('gauntlet', 'chk-poll:new', 1, '9.9.8-poll', 22, '{}'::jsonb, '{}'::jsonb);

-- R3
create temp table _r3 as select pg_temp.poll(true) as a;
select pg_temp.ck('R3 先给正常任务（没有 task 键）',
  (select jsonb_array_length(a->'jobs') = 1 and not ((a->'jobs'->0) ? 'task')
          and (a->'jobs'->0->>'job_id')::bigint = (select job_id from public.referee_jobs where match_key = 'chk-poll:new') from _r3),
  (select a::text from _r3));
select pg_temp.ck('R3 正常任务 claimed、claimed_by = 工人；补流还在 pending',
  exists (select 1 from public.referee_jobs where match_key = 'chk-poll:new' and status = 'claimed' and claimed_by = 'chk-poll-0')
  and exists (select 1 from public.referee_restream r join public.referee_jobs j on j.job_id = r.job_id
              where j.match_key = 'chk-poll:done' and r.status = 'pending'));

-- R4
create temp table _r4 as select pg_temp.poll(false) as a;
select pg_temp.ck('R4 p_restream = false ⇒ 不领补流',
  (select a->'jobs' = '[]'::jsonb from _r4)
  and exists (select 1 from public.referee_restream r join public.referee_jobs j on j.job_id = r.job_id
              where j.match_key = 'chk-poll:done' and r.status = 'pending'),
  (select a::text from _r4));

-- R5
create temp table _r5 as select pg_temp.poll(true) as a;
select pg_temp.ck('R5 正常任务空了 ⇒ 领到补流（task = restream、expect_winner = a）',
  (select jsonb_array_length(a->'jobs') = 1 and a->'jobs'->0->>'task' = 'restream' and a->'jobs'->0->>'expect_winner' = 'a' from _r5),
  (select a::text from _r5));
select pg_temp.ck('R5 补流行 claimed、claimed_by = 工人',
  exists (select 1 from public.referee_restream r join public.referee_jobs j on j.job_id = r.job_id
          where j.match_key = 'chk-poll:done' and r.status = 'claimed' and r.claimed_by = 'chk-poll-0'));

-- R6 econ
insert into auth.users (id, aud, role, is_anonymous, created_at)
  values ('00000000-0000-4000-8000-00000000c0de', 'authenticated', 'authenticated', true, now());
insert into public.econ_state (account_id, week, dirty)
  values ('00000000-0000-4000-8000-00000000c0de', public.econ_week_now(), true);
create temp table _r6 as select pg_temp.poll(false) as a;
select pg_temp.ck('R6 本周有 dirty 的号 ⇒ econ = true',
  (select a->'econ' = 'true'::jsonb from _r6), (select a::text from _r6));
select pg_temp.ck('R6 领活不改 econ_state（dirty 还在）',
  exists (select 1 from public.econ_state where account_id = '00000000-0000-4000-8000-00000000c0de' and dirty));
update public.econ_state set week = public.econ_week_now() - 604800
 where account_id = '00000000-0000-4000-8000-00000000c0de';
select pg_temp.ck('R6 上周的 dirty 不算 ⇒ econ = false', pg_temp.poll(false)->'econ' = 'false'::jsonb);

-- R7 outbox
insert into public.mainsite_outbox (topic, idem_key, body, next_at)
  values ('defense', 'chk-poll:later', '{"x": 1}'::jsonb, now() + interval '10 minutes');
select pg_temp.ck('R7 只有没到点的 ⇒ outbox = false', pg_temp.poll(false)->'outbox' = 'false'::jsonb);
insert into public.mainsite_outbox (topic, idem_key, body, next_at)
  values ('defense', 'chk-poll:due', '{"x": 2}'::jsonb, now() - interval '1 second');
select pg_temp.ck('R7 有到点的 ⇒ outbox = true', pg_temp.poll(false)->'outbox' = 'true'::jsonb);
select pg_temp.ck('R7 领活不改发件箱（next_at 没被挪）',
  exists (select 1 from public.mainsite_outbox where idem_key = 'chk-poll:due' and next_at <= now() and attempts = 0));

-- P 权限
select pg_temp.ck('P 只给 service_role',
  has_function_privilege('service_role', 'public.referee_poll(text, text[], boolean)', 'execute')
  and not has_function_privilege('anon', 'public.referee_poll(text, text[], boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_poll(text, text[], boolean)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 14 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
