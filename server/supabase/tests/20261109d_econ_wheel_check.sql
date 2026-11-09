-- 20261109d 命运之轮跨场层数进记账 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261109d_econ_wheel
-- 判据：
--   W1 ★合计 = A 方积分赛 + B 方闯关配对局 + B 方决赛（♠2 + ♥1 + ♣3）
--   W2 ★不算：积分赛的 B（别人的快照）、偷袭局、别的周、没算完的、不认识的花色 / 不是数
--   W3 账号为空 ⇒ {}；没打过 ⇒ {}
--   T1 ★econ_on 开：变成 claimed ⇒ meta 带 a_wheel / b_wheel = 双方合计；pet_stamp_on_claim 盖的 a_lv 仍在（两个触发器不互相顶掉）
--   T2 ★econ_on 关：不盖（行为一字不变）
--   T3 b_account 为空（机器人池）⇒ 只盖 a_wheel
--   T4 重领（failed → claimed）⇒ 按最新合计重盖，不残留旧值
--   T5 快照一个字不改
--   P1 权限：anon / authenticated 都不能直接调 econ_wheel_sum
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
create or replace function pg_temp.job(p_kind text, p_key text, p_week bigint, p_a text, p_b text, p_status text, p_meta jsonb, p_res jsonb)
returns bigint language sql as $$
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, b_account, a_snapshot, b_snapshot, status, meta, result)
    values (p_kind, p_key, p_week, '0.23.0', 1, pg_temp.u(p_a), pg_temp.u(p_b),
            '{"leaders":["gambler","stone","bamboo"],"wheel_stacks":{"spade":9}}', '{"wheel_stacks":{"club":9}}', p_status, p_meta, p_res)
  returning job_id
$$;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;

-- 本周 1793577600，a 的账：
select pg_temp.job('ranked', 'chk:w:r1', 1793577600, 'a', 'b', 'done', '{}', '{"wheel_new":{"spade":2},"wheel_new_b":{"heart":7}}');
select pg_temp.job('gauntlet', 'chk:w:p1', 1793577600, 'c', 'a', 'done', '{"pair":"true"}', '{"wheel_new":{"diamond":4},"wheel_new_b":{"heart":1}}');
select pg_temp.job('finals', 'chk:w:f1', 1793577600, 'c', 'a', 'done', '{}', '{"wheel_new":{"spade":5},"wheel_new_b":{"club":3}}');
-- 不该算进 a 的：
select pg_temp.job('ranked', 'chk:w:r2', 1793577600, 'c', 'a', 'done', '{}', '{"wheel_new":{"spade":1},"wheel_new_b":{"diamond":6}}');   -- a 是积分赛的 B（快照）
select pg_temp.job('raid', 'chk:w:x1', 1793577600, 'a', 'c', 'done', '{}', '{"wheel_new":{"diamond":8}}');                              -- 偷袭
select pg_temp.job('ranked', 'chk:w:o1', 1792972800, 'a', 'b', 'done', '{}', '{"wheel_new":{"diamond":8}}');                            -- 上一周
select pg_temp.job('ranked', 'chk:w:n1', 1793577600, 'a', 'b', 'claimed', '{}', '{"wheel_new":{"diamond":8}}');                         -- 没算完
select pg_temp.job('ranked', 'chk:w:j1', 1793577600, 'a', 'b', 'done', '{}', '{"wheel_new":{"gift":5,"heart":"9"}}');                   -- 不认识 / 不是数

select pg_temp.ck('W1 ★合计 = A 方积分赛 ♠2 + 配对局 B 方 ♥1 + 决赛 B 方 ♣3',
  public.econ_wheel_sum(pg_temp.u('a'), 1793577600) = '{"spade":2,"heart":1,"club":3}'::jsonb,
  public.econ_wheel_sum(pg_temp.u('a'), 1793577600)::text);
select pg_temp.ck('W2 ★积分赛的 B / 偷袭 / 别的周 / 没算完 / 不认识的都不算(没有 ♦)',
  not (public.econ_wheel_sum(pg_temp.u('a'), 1793577600) ? 'diamond'), public.econ_wheel_sum(pg_temp.u('a'), 1793577600)::text);
select pg_temp.ck('W3 账号为空 ⇒ {}；b 只当过积分赛的 B ⇒ {}',
  public.econ_wheel_sum(null, 1793577600) = '{}'::jsonb and public.econ_wheel_sum(pg_temp.u('b'), 1793577600) = '{}'::jsonb,
  public.econ_wheel_sum(pg_temp.u('b'), 1793577600)::text);

-- 盖章
update public.referee_config set econ_on = true where id = 1;
create temp table _j (k text primary key, id bigint);
grant select on _j to public;
insert into _j values
  ('on',  pg_temp.job('gauntlet', 'chk:w:s1', 1793577600, 'a', 'c', 'pending', '{"pair":"true"}', null)),
  ('bot', pg_temp.job('ranked', 'chk:w:s2', 1793577600, 'a', null, 'pending', '{}', null)),
  ('off', pg_temp.job('ranked', 'chk:w:s3', 1793577600, 'a', 'b', 'pending', '{}', null));
update public.referee_jobs set status = 'claimed' where job_id in ((select id from _j where k = 'on'), (select id from _j where k = 'bot'));
select pg_temp.ck('T1 ★开着: a_wheel = a 的合计、b_wheel = c 的合计(c 本周 A 方: 配对局 ♦4 + 决赛 ♠5 + 积分赛 ♠1)',
  (select meta -> 'a_wheel' = '{"spade":2,"heart":1,"club":3}'::jsonb and meta -> 'b_wheel' = '{"diamond":4,"spade":6}'::jsonb
     from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.ck('T1 ★pet_stamp_on_claim 的 a_lv / a_account 仍在、pair 原样',
  (select meta ? 'a_lv' and meta ? 'a_account' and meta ->> 'pair' = 'true' from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
select pg_temp.ck('T3 b_account 为空(机器人池) ⇒ 只有 a_wheel',
  (select meta ? 'a_wheel' and not (meta ? 'b_wheel') from public.referee_jobs where job_id = (select id from _j where k = 'bot')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'bot')));
select pg_temp.ck('T5 快照一个字不改',
  (select a_snapshot = '{"leaders":["gambler","stone","bamboo"],"wheel_stacks":{"spade":9}}'::jsonb and b_snapshot = '{"wheel_stacks":{"club":9}}'::jsonb
     from public.referee_jobs where job_id = (select id from _j where k = 'on')));
-- 重领: a 又多算完一局 ♠1 ⇒ 重盖成 ♠3
select pg_temp.job('ranked', 'chk:w:r3', 1793577600, 'a', 'b', 'done', '{}', '{"wheel_new":{"spade":1}}');
update public.referee_jobs set status = 'failed' where job_id = (select id from _j where k = 'on');
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'on');
select pg_temp.ck('T4 重领按最新合计重盖(♠2 → ♠3)',
  (select (meta -> 'a_wheel' ->> 'spade')::int = 3 from public.referee_jobs where job_id = (select id from _j where k = 'on')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'on')));
update public.referee_config set econ_on = false where id = 1;
update public.referee_jobs set status = 'claimed' where job_id = (select id from _j where k = 'off');
select pg_temp.ck('T2 ★关着: 不盖',
  (select not (meta ? 'a_wheel') and not (meta ? 'b_wheel') from public.referee_jobs where job_id = (select id from _j where k = 'off')),
  (select meta::text from public.referee_jobs where job_id = (select id from _j where k = 'off')));

select pg_temp.ck('P1 权限: anon / authenticated 都不能直接调',
  not has_function_privilege('anon', 'public.econ_wheel_sum(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.econ_wheel_sum(uuid,bigint)', 'execute'));

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
