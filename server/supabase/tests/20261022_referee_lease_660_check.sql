-- 20261022 裁判任务租期 660 —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 判据：
--   L1 配置行 lease_sec = 660
--   L2 列默认值 = 660（新建库也是 660）
--   L3 max_attempts 没被顺手改动（仍是 3）
--   L4 只有一行配置（单行约束还在）
-- ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 整个事务回滚。
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;

select pg_temp.ck('L1 配置行 lease_sec = 660',
  (select lease_sec from public.referee_config where id = 1) = 660,
  'lease_sec = ' || coalesce((select lease_sec::text from public.referee_config where id = 1), 'null'));
select pg_temp.ck('L2 列默认值 = 660',
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'referee_config' and column_name = 'lease_sec') = '660',
  'default = ' || coalesce((select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'referee_config' and column_name = 'lease_sec'), 'null'));
select pg_temp.ck('L3 max_attempts 仍是 3',
  (select max_attempts from public.referee_config where id = 1) = 3);
select pg_temp.ck('L4 只有一行配置',
  (select count(*) from public.referee_config) = 1);

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 4 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
