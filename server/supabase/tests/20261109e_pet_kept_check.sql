-- 20261109e 本周已上场过的统领整周都认 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261109e_pet_kept
-- 判据：
--   K1 ★合计 = A 方积分赛 + B 方闯关配对局 + B 方决赛 的统领，去重排序
--   K2 ★不算：没盖过拥有章的局（20261109b 之前）、积分赛的 B（别人的快照）、偷袭、别的周、没算完的、不像龟 id 的
--   K3 账号为空 ⇒ []
--   T1 ★变成 claimed ⇒ meta 带 a_kept / b_kept；20261109b 的 a_owned / a_lv 仍在（两个触发器不互相顶掉）
--   T2 b_account 为空（机器人池）⇒ 只盖 a_kept
--   T3 重领 ⇒ 按最新重盖
--   T4 快照一个字不改
--   P1 权限：anon / authenticated 都不能直接调 pet_kept_leaders
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create temp table _u (k text primary key, id uuid not null default gen_random_uuid());
insert into _u (k) values ('a'), ('b'), ('c');
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.u(p_k text) returns uuid language sql as $$ select id from _u where k = p_k $$;
create or replace function pg_temp.job(p_kind text, p_key text, p_week bigint, p_a text, p_b text, p_status text, p_meta jsonb,
    p_al text[], p_bl text[]) returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, status, meta, result)
    values (p_kind, p_key, p_week, '0.23.0', 1, pg_temp.u(p_a), pg_temp.u(p_b),
            jsonb_build_object('leaders', to_jsonb(p_al)), jsonb_build_object('leaders', to_jsonb(p_bl)), p_status, p_meta,
            case when p_status = 'done' then '{"ledger":{"won":true}}'::jsonb end)
  returning job_id
$$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

-- 本周 1793577600。a 上场过的（都盖过章）：
select pg_temp.job('ranked', 'chk:k:r1', 1793577600, 'a', 'b', 'done', '{"a_owned":[],"b_owned":[]}', array['stone','bamboo','gambler'], array['ghost','ninja','candy']);
select pg_temp.job('gauntlet', 'chk:k:p1', 1793577600, 'c', 'a', 'done', '{"pair":"true","a_owned":[],"b_owned":[]}', array['lava','hunter','shell'], array['stone','hiding','gambler']);
select pg_temp.job('finals', 'chk:k:f1', 1793577600, 'c', 'a', 'done', '{"a_owned":[],"b_owned":[]}', array['lava','hunter','shell'], array['angel','bamboo','stone']);
-- 不该算进 a 的：
select pg_temp.job('ranked', 'chk:k:o0', 1793577600, 'a', 'b', 'done', '{}', array['pirate','pirate','pirate'], array['x','y','z']);                 -- 没盖过章
select pg_temp.job('ranked', 'chk:k:r2', 1793577600, 'c', 'a', 'done', '{"a_owned":[],"b_owned":[]}', array['lava','hunter','shell'], array['diver','diver','diver']);   -- a 是积分赛的 B
select pg_temp.job('raid', 'chk:k:x1', 1793577600, 'a', 'c', 'done', '{"a_owned":[],"b_owned":[]}', array['crystal','crystal','crystal'], array['lava','hunter','shell']);   -- 偷袭
select pg_temp.job('ranked', 'chk:k:w1', 1792972800, 'a', 'b', 'done', '{"a_owned":[]}', array['phoenix','phoenix','phoenix'], array['x','y','z']);   -- 上一周
select pg_temp.job('ranked', 'chk:k:n1', 1793577600, 'a', 'b', 'claimed', '{"a_owned":[]}', array['star','star','star'], array['x','y','z']);        -- 没算完
select pg_temp.job('ranked', 'chk:k:j1', 1793577600, 'a', 'b', 'done', '{"a_owned":[]}', array['Bad Id!','stone','bamboo'], array['x','y','z']);     -- 不像龟 id

select pg_temp.ck('K1 ★a 本周上场过的统领 = 积分赛 A + 配对局 B + 决赛 B, 去重排序',
  public.pet_kept_leaders(pg_temp.u('a'), 1793577600) = '["angel","bamboo","gambler","hiding","stone"]'::jsonb,
  public.pet_kept_leaders(pg_temp.u('a'), 1793577600)::text);
select pg_temp.ck('K2 ★没盖章 / 积分赛的 B / 偷袭 / 上一周 / 没算完 / 不像 id 的都不算',
  not (public.pet_kept_leaders(pg_temp.u('a'), 1793577600) ?| array['pirate','diver','crystal','phoenix','star','Bad Id!']),
  public.pet_kept_leaders(pg_temp.u('a'), 1793577600)::text);
select pg_temp.ck('K3 账号为空 ⇒ []；b 只当过积分赛的 B ⇒ []',
  public.pet_kept_leaders(null, 1793577600) = '[]'::jsonb and public.pet_kept_leaders(pg_temp.u('b'), 1793577600) = '[]'::jsonb,
  public.pet_kept_leaders(pg_temp.u('b'), 1793577600)::text);

create temp table _j (k text primary key, id bigint);
grant select on _j to public;
insert into _j values
  ('on',  pg_temp.job('gauntlet', 'chk:k:s1', 1793577600, 'a', 'c', 'pending', '{"pair":"true"}', array['stone','bamboo','gambler'], array['lava','hunter','shell'])),
  ('bot', pg_temp.job('ranked', 'chk:k:s2', 1793577600, 'a', null, 'pending', '{}', array['stone','bamboo','gambler'], array['x','y','z']));
update public.referee_jobs set status = 'claimed' where job_id in ((select id from _j where k = 'on'), (select id from _j where k = 'bot'));
select pg_temp.ck('T1 ★a_kept = a 上场过的、b_kept = c 上场过的(c 本周 A 方: 配对局 / 决赛 / 积分赛同一组)',
  (select meta -> 'a_kept' = '["angel","bamboo","gambler","hiding","stone"]'::jsonb and meta -> 'b_kept' = '["hunter","lava","shell"]'::jsonb
     from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.ck('T1 ★20261109b 盖的 a_owned / a_lv / a_account 仍在、pair 原样',
  (select meta ? 'a_owned' and meta ? 'a_lv' and meta ? 'a_account' and meta ->> 'pair' = 'true' from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.ck('T2 b_account 为空(机器人池) ⇒ 只有 a_kept',
  (select meta ? 'a_kept' and not (meta ? 'b_kept') from public.referee_jobs where job_id = (select id from _j where k = 'bot')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'bot')));
select pg_temp.ck('T4 快照一个字不改',
  (select a_snapshot = '{"leaders":["stone","bamboo","gambler"]}'::jsonb and b_snapshot = '{"leaders":["lava","hunter","shell"]}'::jsonb
     from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.job('ranked', 'chk:k:r3', 1793577600, 'a', 'b', 'done', '{"a_owned":[]}', array['angel','candy','stone'], array['x','y','z']);
update public.referee_jobs set status = 'failed' where job_id = (select id from _j where k = 'on');
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'on');
select pg_temp.ck('T3 重领按最新重盖(多了 candy)',
  (select meta -> 'a_kept' ? 'candy' from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));

select pg_temp.ck('P1 权限: anon / authenticated 都不能直接调',
  not has_function_privilege('anon', 'public.pet_kept_leaders(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.pet_kept_leaders(uuid,bigint)', 'execute'));

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
