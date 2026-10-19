-- >>> BEGIN week_leaderboard_page 20261019 >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜按名次区间取（2026-10-19 · 用户「排行榜你学一下其他游戏的，开放所有排名」）—— ★待主会话审后上线
--
-- ★为什么：`week_leaderboard(p_week, p_limit)` 只回前 N 名（limit 夹在 1..100）+ 我那一行，
--   客户端只画得出前 30 名 + 钉住的我。所有名次都要能翻到 ⇒ 按名次区间分页取。
-- ★新函数，不改旧函数：老包照旧调 `week_leaderboard`，一个字不动；新包先调本函数，404（没部署）再退回旧函数。
-- ★口径与 v3（20261010_week_leaderboard_v3.sql）逐字相同：`latest` / `ranked` 两段原样照抄
--   （本周 / 每账号最新一行 / 滤陪练 seed_ / 滤 is_bot / 滤周六非 0-0 行 / 胜场 → 余命 → 横扫 → 先到者 → account_id），
--   只把「rk <= lim」换成「p_offset < rk <= p_offset + lim」。
-- ★回包形状 = 旧函数的形状 + `offset`：{ok, week, total, offset, rows:[名次 offset+1 .. offset+lim], me}。
-- ★每页上限 100（与旧函数同一个上限）；offset 负数当 0。
-- ★只读：不建表、不改表、不写任何一行。
-- ─────────────────────────────────────────────────────────────
create or replace function public.week_leaderboard_page(p_week bigint, p_offset int default 0, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; off int; tot int; page jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  off := greatest(coalesce(p_offset, 0), 0);
  with latest as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), ranked as (
    select l.*, s.title, row_number() over (
             order by l.season_wins desc, l.hearts desc, l.season_sweeps desc,
                      l.uploaded_at asc, l.account_id) as rk
      from latest l
      left join public.standings s
        on s.season_week = p_week and s.account_id = l.account_id
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, '')) order by r.rk) filter (where r.rk > off and r.rk <= off + lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, page, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'offset', off,
    'rows', page, 'me', mine);
end $$;

revoke all on function public.week_leaderboard_page(bigint, int, int) from public;
revoke execute on function public.week_leaderboard_page(bigint, int, int) from anon;
grant execute on function public.week_leaderboard_page(bigint, int, int) to authenticated;
-- <<< END week_leaderboard_page 20261019 <<<
