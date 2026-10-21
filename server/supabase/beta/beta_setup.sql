-- server/supabase/beta/beta_setup.sql —— 【只在内测服 turtle-beta 上】执行的那几处不同（2026-10-21 · 方案书 docs/plans/20261020-内测服.md §2）
-- ─────────────────────────────────────────────────────────────
-- 谁执行：tools/beta_ops.py bootstrap / tools/sb_migrate.py beta --apply（每次上完迁移都重跑一遍 ⇒ 幂等）。
--   两个工具都写死只认内测服 ref，并在同一请求里先 set_config('turtle.beta_ref', <内测服 ref>)；
--   下面第一句没看到这个值就整段报错 ⇒ 粘到正式服的 SQL 编辑器里也执行不了。
-- 做什么：
--   ① service_env = 'beta' ⇒ app_now() 开始加偏移、beta_tick() 开始干活
--   ② 删掉 server_clock_prod_zero（「偏移恒 0」约束只给正式服）
--   ③ cron：周日三条（finals_seat / finals_cup_seat / finals_advance，按真实星期几）卸掉，
--      换成每分钟一次 beta_tick()（按 app_now() 判星期几与周号）；其余 cron（清理类）与正式服相同、照真实时间走
-- ─────────────────────────────────────────────────────────────
do $$
begin
  if coalesce(current_setting('turtle.beta_ref', true), '') <> 'twxkroptuqbfhmlojjgl' then
    raise exception 'beta_setup.sql 只许 tools/beta_ops.py / tools/sb_migrate.py 对内测服执行（没看到 turtle.beta_ref）';
  end if;
end $$;

update public.service_env set env = 'beta' where id = 1;
alter table public.server_clock drop constraint if exists server_clock_prod_zero;

select cron.unschedule(jobid) from cron.job where jobname in ('finals_seat', 'finals_cup_seat', 'finals_advance');
select cron.unschedule(jobid) from cron.job where jobname = 'beta_tick';
select cron.schedule('beta_tick', '* * * * *', 'select public.beta_tick()');
