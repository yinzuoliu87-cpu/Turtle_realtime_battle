-- >>> BEGIN referee_client_flags 20261019b >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判 · 客户端读开关（2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §3 ①②）—— ★只写文件、未上生产
--   前提：20261019_referee_jobs.sql 已执行（referee_config / referee_finals_on / referee_gauntlet_on）。
--
-- 为什么要它：开关 referee_config.finals_on / gauntlet_on 在服务端，而客户端要据它决定
--   「周日点开自己那一场 = 看还是打」「周六点开战 = 交给服务器还是本机打」。referee_config 开了 RLS 且没有任何策略
--   （客户端读不到），referee_finals_on() / referee_gauntlet_on() 也收回了执行权 ⇒ 加一个只读、只回两个布尔的函数。
--   客户端：scripts/net/referee_net.gd（refresh_flags_async；问到就落进本机存档，断网冷启动也知道上次是开是关）。
--
-- ★只读、不回别的（版本号 / 租期 / 积压都不回）；anon 也能调（与 service_status 同一口径：未登录时也该知道）。
-- ★客户端认 404（本函数没部署）= 两个开关都关 ⇒ 执行之前与之后，开关关着时行为完全一样。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on())
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END referee_client_flags 20261019b <<<
