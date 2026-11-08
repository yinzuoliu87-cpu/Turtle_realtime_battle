-- 20261106b 局外经济记账总开关 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261106b_econ_flag
-- 判据：
--   F1 默认关：referee_flags().econ_on = false（迁移上了行为不变）
--   F2 其余五项原样还在（finals_on / gauntlet_on / stream_on / stream_version / ranked_on 都有、类型对）
--   F3 打开 ⇒ econ_on = true；F4 关回去 ⇒ false
--   P  referee_flags 照旧 anon / authenticated 都能调；referee_econ_on 不对外
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;

-- 先把开关摆成「关」(内测服 / 正式服上已经开着的话, 本事务里临时关, 回滚即还原)
update public.referee_config set econ_on = false where id = 1;
select pg_temp.ck('F1 默认关: referee_flags().econ_on = false', (public.referee_flags() ->> 'econ_on')::boolean = false,
  public.referee_flags()::text);
select pg_temp.ck('F2 其余五项原样还在',
  public.referee_flags() ?& array['finals_on', 'gauntlet_on', 'stream_on', 'stream_version', 'ranked_on']
  and jsonb_typeof(public.referee_flags() -> 'finals_on') = 'boolean'
  and jsonb_typeof(public.referee_flags() -> 'ranked_on') = 'boolean'
  and jsonb_typeof(public.referee_flags() -> 'stream_version') = 'string', public.referee_flags()::text);
update public.referee_config set econ_on = true where id = 1;
select pg_temp.ck('F3 打开 ⇒ econ_on = true', (public.referee_flags() ->> 'econ_on')::boolean = true, public.referee_flags()::text);
update public.referee_config set econ_on = false where id = 1;
select pg_temp.ck('F4 关回去 ⇒ false', (public.referee_flags() ->> 'econ_on')::boolean = false, public.referee_flags()::text);
select pg_temp.ck('P1 referee_flags 照旧 anon / authenticated 都能调',
  has_function_privilege('anon', 'public.referee_flags()', 'execute')
  and has_function_privilege('authenticated', 'public.referee_flags()', 'execute'));
select pg_temp.ck('P2 referee_econ_on 不对外',
  not has_function_privilege('anon', 'public.referee_econ_on()', 'execute')
  and not has_function_privilege('authenticated', 'public.referee_econ_on()', 'execute'));

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
