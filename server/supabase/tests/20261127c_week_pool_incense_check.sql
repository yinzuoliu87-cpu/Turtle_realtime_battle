-- 20261127c 香火石 / 小木斧不参与每周轮换 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261127c_week_pool_incense
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 什么都不留。
-- 判据（2026-12-07 那周: 没有面具 / 长矛 / 遗物）：
--   I1 香火石(遗物 + 香火)⇒ 类型表里没有它 ⇒ 遗物不在的周也放行(原 20261127 是「不过」)
--   I2 小木斧照旧放行; 遗物件(p2eq_004)遗物不在的周照旧不过; 面具照旧不过; 仪式匕首(匕首 + 仪式)跟着匕首(12-07 有匕首 ⇒ 过)
--   I3 类型表其余件与 20261127 逐件相同: 抽查剑 / 长矛 / 筹码 / 仪式匕首
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.wk() returns bigint language sql as $$ select 1796601600::bigint $$;   -- 2026-12-07
create or replace function pg_temp.snap(p_eq text) returns jsonb language sql as $$
  select jsonb_build_object('equipped', jsonb_build_object('ninja', jsonb_build_array(
    jsonb_build_object('id', 'p2eq_001', 'star', 1), jsonb_build_object('id', p_eq, 'star', 1))))
$$;

select pg_temp.ck('I0 12-07 这周没有遗物、有剑和匕首', not ('遗物' = any(public.weekly_synergy_of(pg_temp.wk())))
  and '剑' = any(public.weekly_synergy_of(pg_temp.wk())) and '匕首' = any(public.weekly_synergy_of(pg_temp.wk())),
  public.weekly_synergy_of(pg_temp.wk())::text);
select pg_temp.ck('I1 香火石不在类型表里', cardinality(public.p2eq_big_types('p2eq_093')) = 0, public.p2eq_big_types('p2eq_093')::text);
select pg_temp.ck('I1 遗物不在的周, 带香火石 ⇒ 过', public.snap_week_pool_ok(pg_temp.snap('p2eq_093'), pg_temp.wk()));
select pg_temp.ck('I2 小木斧 ⇒ 过', public.snap_week_pool_ok(pg_temp.snap('p2eq_096'), pg_temp.wk()));
select pg_temp.ck('I2 遗物件 p2eq_004 ⇒ 不过', not public.snap_week_pool_ok(pg_temp.snap('p2eq_004'), pg_temp.wk()));
select pg_temp.ck('I2 面具 ⇒ 不过', not public.snap_week_pool_ok(pg_temp.snap('p2eq_127'), pg_temp.wk()));
select pg_temp.ck('I2 仪式匕首跟着匕首 ⇒ 过', public.snap_week_pool_ok(pg_temp.snap('p2eq_114'), pg_temp.wk()));
select pg_temp.ck('I3 抽查类型', public.p2eq_big_types('p2eq_001') = array['剑'] and public.p2eq_big_types('p2eq_137') = array['长矛']
  and public.p2eq_big_types('p2eq_147') = array['筹码'] and public.p2eq_big_types('p2eq_114') = array['匕首'],
  public.p2eq_big_types('p2eq_114')::text);
select pg_temp.ck('I3 权限: anon / authenticated 不能调 p2eq_big_types',
  not has_function_privilege('anon', 'public.p2eq_big_types(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.p2eq_big_types(text)', 'execute'));

do $$
declare nt int; nf int; msg text; fmsg text;
begin
  select count(*), count(*) filter (where not pass) into nt, nf from _chk;
  select string_agg(format('%s %s  %s', case when pass then '[PASS]' else '[FAIL]' end, name, info), E'
' order by n) into msg from _chk;
  select string_agg(format('[FAIL] %s  %s', name, info), E'
' order by n) into fmsg from _chk where not pass;
  if nf > 0 or nt < 9 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'
' || coalesce(fmsg, '(条数不够)') || E'
──── 全部 ────
' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
