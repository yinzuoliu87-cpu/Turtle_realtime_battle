-- >>> BEGIN leaderboard_lead 20261024b >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜每行多下发「头像」= 这个人第一只统领（2026-10-24 · 方案书 docs/plans/20261023-排行榜重做.md）
--   用户 2026-10-23 只选了「看着像网页，没有游戏味」⇒ 重做以视觉质感为主：每行加头像（第一只统领立绘）。
--   原来每行只有 名次 / 昵称 / ID / 胜 / 余命 / 横扫 / 总场次 / 头衔，快照里有统领但服务端没下发。
-- ★只改 week_leaderboard_page：每行多一个键 `lead`（snapshot_lead：leaders[0]，老快照退回 profile.avatar）。
--   其余逐字照抄 20261019（口径 / 排序 / 分页 / 权限一个字不动）。老包不认这个键 ⇒ 照旧画字。
-- ★依赖 20261024_friends 里的 public.snapshot_lead —— 两份迁移按序上。
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
           g.snapshot -> 'profile' ->> 'tag'  as tag,
           public.snapshot_lead(g.snapshot)   as lead
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
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, '')) order by r.rk) filter (where r.rk > off and r.rk <= off + lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, page, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'offset', off,
    'rows', page, 'me', mine);
end $$;

revoke all on function public.week_leaderboard_page(bigint, int, int) from public;
revoke execute on function public.week_leaderboard_page(bigint, int, int) from anon;
grant execute on function public.week_leaderboard_page(bigint, int, int) to authenticated;
-- <<< END leaderboard_lead 20261024b <<<
