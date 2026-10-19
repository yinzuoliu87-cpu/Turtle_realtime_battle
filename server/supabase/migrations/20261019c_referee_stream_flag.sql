-- >>> BEGIN referee_stream_flag 20261019c >>>
-- ─────────────────────────────────────────────────────────────
-- 逐帧直播 S5 · 客户端开关（2026-10-19 · 方案书 docs/plans/20261019-服务器逐帧直播.md §4 接线 / §5 录像）—— ★只写文件、未上生产
--   前提：20261019_referee_jobs.sql（referee_config）与 20261019b_referee_client_flags.sql（referee_flags）已执行。
--
-- 为什么要它：周六闯关 / 周日决赛 / 赛况板 / 对阵图 / 赛后回放要从「拿录像本机重算」改成「播服务器的状态流」，
--   而服务器要先装上带录流代码的版本、轮询器设好 STREAM_ROOT（server/stream/README.md「打开录流」）才有流可播。
--   在那之前客户端必须照老路走 ⇒ 由服务端下发一个开关，客户端读到「开」才播流。
--     stream_on       开 ⇒ 看服务器算的局一律播状态流（手机一步 sim 都不跑）；关 ⇒ 现行行为（录像本机重算），一字不变
--     stream_version  裁判机从哪个客户端版本起才录流（'' = 不限）。客户端版本低于它 ⇒ 当作关
--   客户端：scripts/net/referee_net.gd（parse_flags / stream_on），scripts/systems/replay/stream_watch.gd（各入口的分流）。
--
-- ★只读函数照旧只回布尔 + 一个版本串，不回租期 / 积压等。anon 也能调（与 20261019b 同一口径）。
-- ★客户端读不到这两个键（本迁移没上 / 回包是 20261019b 那一版）⇒ 当作关；referee_flags 本身 404 ⇒ 全关。
--   ⇒ 执行本迁移本身不改变任何现行行为（两列默认 false / ''）。
-- ★打开顺序（反过来会让手机去拉一份不存在的流，只能显示「画面无法播放」）：
--   ① 裁判机装上新版本工程 + `STREAM_ROOT` 写进 /etc/turtle-referee/env 并重启轮询器（server/stream/README.md）
--   ② 冒烟：内测服跑一局，确认 https://stream.turtlearena.xyz/streams/<match_id>/end.json 带新版本头能拿到 200
--   ③ update public.referee_config set stream_on = true, stream_version = '<①那个版本>', updated_at = now() where id = 1;
--   回滚 = stream_on 翻回 false（客户端下次问到开关即回到老路；已经在看的那一场照常播完）。
-- ★重复执行安全（add column if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

alter table public.referee_config add column if not exists stream_on boolean not null default false;
alter table public.referee_config add column if not exists stream_version text not null default '';

create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on(),
                            'stream_on', coalesce((select c.stream_on from public.referee_config c where c.id = 1), false),
                            'stream_version', coalesce((select c.stream_version from public.referee_config c where c.id = 1), ''))
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END referee_stream_flag 20261019c <<<
