-- >>> BEGIN week_leaderboard 20261006-A2 >>>
-- ─────────────────────────────────────────────────────────────
-- 本周排行榜（2026-10-06 · 60 人实操严重项 A2）—— ★待用户审后上线
--
-- ★为什么要有它：客户端原来拿**本机的对手快照池**拼排行榜（`Backend.leaderboard`）。
--   新玩家只拉过场次 N / N+1 的快照（PULL_BATTLES_AHEAD），于是榜上每个人都冻在
--   「1 胜 · 6 命」—— 实操截图前 9 行全是 1 胜，而那几个号几小时前已经打到 9-6 / 10-6。
--   那是「我碰巧拉到过的那一份」，不是排行榜。
-- ★`standings` 表从来没人写过，不能当数据源 ⇒ 直接从 `ghosts` 算。
--
-- ★口径（与客户端本地榜同一套，不另立）：
--   · 本周 = `season_week = p_week`（周锚点，与上传那一侧 `GameState.week_anchor_ts` 同一个数）
--   · 每个账号只取**最新**那一行：场次最大的那份（同场次取上传最晚）。
--     ★按场次而不按上传时刻：上传队列会重试，晚到的可能是旧场次；场次才是单调的进度。
--   · 排序 = 胜场 → 余命 → 横扫（`Backend.leaderboard` 的 `cmp`，A8 定的字典序）；
--     全平再按先到者在前（`uploaded_at`），最后按 account_id 定死次序。
--   · 不上榜：陪练（`ghost_id` 以 `seed_` 开头 —— `Backend.is_sparring` 的唯一判据）
--     与机器人（`is_bot = true` —— `make_bot` 盖的章）。正常客户端两种都不上传，这两条是防线。
--     「自己」不排除：服务端榜上的我就是我上传的最新一份，客户端按 account_id 认出来钉住。
-- ★只读：不建表、不改表、不写任何一行。只加一个函数 + 授权。
-- ★下发 名字 / 玩家 ID（快照 profile.tag）/ account_id / 三个成绩 / 名次。**不碰阵容**。
--   account_id 的暴露面与现状相同（`ghosts_read_all` 本来就对登录用户整表可读）。
-- ★`me` = 我自己那一行（不在前 N 名里也给，名次是全榜真名次）；本周没传过 ⇒ null。
-- ★没部署之前客户端拿到 404 ⇒ 退回本机榜并标「本机记录」，不报错。
-- ★性能：`ghosts_match_idx (season_week, battles, uploaded_at desc)` 的首列就是 season_week。
-- ─────────────────────────────────────────────────────────────
create or replace function public.week_leaderboard(p_week bigint, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; tot int; top jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 30), 1), 100);
  with latest as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), ranked as (
    select l.*, row_number() over (
             order by l.season_wins desc, l.hearts desc, l.season_sweeps desc,
                      l.uploaded_at asc, l.account_id) as rk
      from latest l
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps) order by r.rk) filter (where r.rk <= lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps)) filter (where r.account_id = auth.uid())) -> 0
    into tot, top, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot,
    'rows', top, 'me', mine);
end $$;

revoke all on function public.week_leaderboard(bigint, int) from public;
revoke execute on function public.week_leaderboard(bigint, int) from anon;
grant execute on function public.week_leaderboard(bigint, int) to authenticated;
-- <<< END week_leaderboard 20261006-A2 <<<
