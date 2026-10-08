-- >>> BEGIN purge_ghosts 20261008 >>>
-- ─────────────────────────────────────────────────────────────
-- 周清并进对手快照（2026-10-08 · 用户「每周快照会刷掉对吧」「改」）
--   客户端拉对手本来就只拉本周（season_week=eq.本周锚点），旧周的行不会被匹配到，但一直留在库里。
--   ⇒ 并进现有 purge_old_matches（cron jobid 11 '0 0 * * 2'，不新增任务），口径与 matches 一致：
--     删掉 season_week 早于本周一 00:00 UTC 的快照。season_week = 周一 00:00 UTC 的 epoch 秒。
--   ★重新定义的函数体 = 生产现行版（含 live_matches 那行，20261007 已上）+ 下面两行。
-- ─────────────────────────────────────────────────────────────
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.live_matches where started_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
  delete from public.gauntlet_ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;
-- <<< END purge_ghosts 20261008 <<<
