-- >>> BEGIN finals_cup_1900 20261101c >>>
-- ─────────────────────────────────────────────────────────────
-- 冠军杯赛开赛 20:00 → 19:00 UTC（2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md 决策记录）。
--   用户原话：「所以小组赛其实六点开打，差不多六点半之前就可以结束吧。那么冠军杯赛我们直接挪到七点钟开始吧，不用八点钟。」
--   （小组赛 18:00 开打；桶内同一轮同时开播后约 24 人 18:17 左右收盘。）
-- 改两处，其余不动：
--   ① finals_cup_hour() 20 → 19（finals_cup_seat 的成表闸 / start_at、beta_tick、客户端常量 FINALS_START_HOUR_UTC 都读它；
--      门禁 tests/verify_champion_cup.gd 逐字对「最后一份定义 = 客户端常量」）。
--   ② cron finals_cup_seat 的小时段 20-23 → 19-23（命令文本与 20261007b 逐字相同）。
--   finals_cup_wait_sec()（开赛时还有组没打完最多再等 3600 秒）不动 ⇒ 最晚 20:00 成表。
-- 生效时机：随客户端 0.22.7（FINALS_START_HOUR_UTC = 19）强制更新之后、工作日上正式服；旧客户端 0.22.6 写死 20，
--   在正式服先改会让旧客户端倒计时说 20:00 而 19:00 就成表。
-- 回滚：finals_cup_hour() 改回 select 20、cron 小时段改回 20-23。★重复执行安全。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_cup_hour()
returns int language sql immutable as $$ select 19 $$;

select cron.unschedule(jobid) from cron.job where jobname = 'finals_cup_seat';
select cron.schedule('finals_cup_seat', '*/5 19-23 * * 0',
  $c$select public.finals_cup_seat(extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint)$c$);
-- <<< END finals_cup_1900 20261101c <<<
