-- >>> BEGIN referee_health 20261026 >>>
-- ─────────────────────────────────────────────────────────────
-- 裁判机外部探活口（2026-10-26 · 方案书 docs/plans/20261026-裁判机外部监控.md）
--   10-25 裁判机整机断网约 79 分钟没人知道：机器上的健康检查连不上库、也没有任何对外通知。
--   外部（GitHub Actions `referee-watch.yml` → tools/referee_watch.py）要一个【匿名能调】、只回几个数的探活口 ——
--   referee_backlog() 只授权 service_role，外部拿不到。
-- ★只读：不建表、不改表、不写任何一行。不暴露玩家数据 / 线程名 / 版本列表，只回四个数。
-- ★「最新」一次心跳（max seen_at）：心跳表里可能留着换过名的历史线程行，取最旧会被旧行拖住。
--   没有任何心跳行 ⇒ freshest_sec = null（探活脚本当成失联）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_health()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'freshest_sec', (select extract(epoch from now() - max(seen_at))::int from public.referee_workers),
    'fresh_workers', (select count(*) from public.referee_workers where seen_at > now() - interval '180 seconds'),
    'pending', (select count(*) from public.referee_jobs where status = 'pending'),
    'oldest_pending_sec', (select coalesce(extract(epoch from now() - min(created_at))::int, 0)
                             from public.referee_jobs where status = 'pending'))
$$;

revoke all on function public.referee_health() from public;
grant execute on function public.referee_health() to anon, authenticated, service_role;
-- <<< END referee_health 20261026 <<<
