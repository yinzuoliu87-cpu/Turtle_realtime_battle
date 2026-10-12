-- >>> BEGIN finals_seat_1800 20261012 >>>
-- 周日小组赛开赛时刻 08:00 UTC → 18:00 UTC（用户 2026-10-12「晚上 19 点」, 英国夏令时 = UTC+1）。
-- 只改定时任务的触发小时; finals_seat 函数本身不看钟点。客户端常量 FINALS_SEAT_HOUR_UTC 同步改 18。
-- 冠军杯赛 finals_cup_seat 仍 20:00 UTC 起每 5 分钟(组没打完它会等)。重复执行安全。
select cron.unschedule(jobid) from cron.job where jobname = 'finals_seat';
select cron.schedule('finals_seat', '*/10 18-23 * * 0',
  $$select public.finals_seat((extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint))$$);
-- <<< END finals_seat_1800 20261012 <<<
