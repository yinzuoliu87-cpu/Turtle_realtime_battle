-- 20261024b 周榜每行头像（lead）—— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox 20261024b_leaderboard_lead（内测服 / 生产同 sb_migrate 流程）
--   ★本文件最后一句一定抛异常 ⇒ 整个事务回滚。
-- 判据：
--   W1 每行带 lead = 第一只统领；老快照（没有 leaders）退回 profile.avatar；都没有 ⇒ ''
--   W2 「我」那一行也带 lead
--   W3 对照：名次 / 胜场 / 分页 与改之前同一口径（胜场多的在前）；回包键只多了 lead
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ids as
  select gen_random_uuid() as a, gen_random_uuid() as b, gen_random_uuid() as c, 4102444800::bigint as wk;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ids to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;

insert into auth.users (id, aud, role, is_anonymous)
  select x, 'authenticated', 'authenticated', true from _ids, unnest(array[a, b, c]) x;
insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, client_version)
  select a, wk, 5, '{"leaders":["phoenix","stone","basic"],"profile":{"name":"甲","avatar":"basic","tag":"#222222"}}'::jsonb, 4, 6, 't' from _ids
  union all select b, wk, 5, '{"profile":{"name":"乙","avatar":"ninja","tag":"#333333"}}'::jsonb, 3, 6, 't' from _ids
  union all select c, wk, 5, '{"profile":{"name":"丙","tag":"#444444"}}'::jsonb, 2, 6, 't' from _ids;

select set_config('request.jwt.claims', json_build_object('sub', (select b from _ids)::text, 'role', 'authenticated')::text, true);
create temp table _p as select public.week_leaderboard_page((select wk from _ids), 0, 50) as r;
select set_config('request.jwt.claims', '', true);

select pg_temp.ck('W1 第一名（有 leaders）lead = 第一只统领 phoenix',
  (select r->'rows'->0->>'name' = '甲' and r->'rows'->0->>'lead' = 'phoenix' from _p), (select r::text from _p));
select pg_temp.ck('W1 老快照（没有 leaders）退回 profile.avatar',
  (select r->'rows'->1->>'name' = '乙' and r->'rows'->1->>'lead' = 'ninja' from _p));
select pg_temp.ck('W1 都没有 ⇒ 空串（不是 null）',
  (select r->'rows'->2->>'name' = '丙' and r->'rows'->2->'lead' = '""'::jsonb from _p));
select pg_temp.ck('W2 「我」那一行也带 lead',
  (select r->'me'->>'name' = '乙' and r->'me'->>'lead' = 'ninja' from _p));
select pg_temp.ck('W3 对照：排序口径不变（胜场 4 > 3 > 2）、总数 3、只多了 lead 一个键',
  (select (r->>'total')::int = 3 and (r->'rows'->0->>'wins')::int = 4 and (r->'rows'->2->>'wins')::int = 2
          and (select array_agg(k order by k) from jsonb_object_keys(r->'rows'->0) k)
              = array['account_id', 'battles', 'hearts', 'lead', 'name', 'rank', 'sweeps', 'tag', 'title', 'wins']
     from _p));

do $$
declare nf int; nt int; msg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
