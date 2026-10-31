-- 20261101c 冠军杯赛开赛 19:00 UTC —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261101c_finals_cup_1900
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261101c_finals_cup_1900
-- 判据：
--   H1 finals_cup_hour() = 19
--   H2 cron finals_cup_seat 只有一条、小时段 19-23、命令仍是「本周周号 → finals_cup_seat」
--   H3 等待上限 finals_cup_wait_sec() 仍 3600（没顺手改）
--   H4 保留组号 finals_cup_no() 仍 1000000（没顺手改）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;

select pg_temp.ck('H1 finals_cup_hour() = 19', public.finals_cup_hour() = 19, public.finals_cup_hour()::text);
select pg_temp.ck('H2 cron finals_cup_seat 只有一条、小时段 19-23、命令调 finals_cup_seat(本周周号)',
  (select count(*) from cron.job where jobname = 'finals_cup_seat') = 1
  and (select schedule from cron.job where jobname = 'finals_cup_seat') = '*/5 19-23 * * 0'
  and (select command from cron.job where jobname = 'finals_cup_seat') like '%public.finals_cup_seat(extract(epoch from date_trunc(''week''%',
  coalesce((select string_agg(schedule, ' | ') from cron.job where jobname = 'finals_cup_seat'), '(无)'));
select pg_temp.ck('H3 等待上限 finals_cup_wait_sec() 仍 3600', public.finals_cup_wait_sec() = 3600, public.finals_cup_wait_sec()::text);
select pg_temp.ck('H4 保留组号 finals_cup_no() 仍 1000000', public.finals_cup_no() = 1000000, public.finals_cup_no()::text);

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
