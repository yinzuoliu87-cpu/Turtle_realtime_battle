-- >>> BEGIN week_leaderboard_v2 20261006b >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜 v2（2026-10-06 · 用户「积分赛写上名字，剩余生命，胜场，总场次啊，都给我做」）—— ★待主会话审后上线
--
-- ★相对 v1（20261006_week_leaderboard.sql）只**加两个下发字段**，口径一个字没动：
--   · `battles` —— 总场次 = 该账号本周**最新那一行**的 `ghosts.battles`
--     （每账号取最新一行本来就是按 battles desc 取的 ⇒ 它就是本周打到第几场）。
--   · `title`   —— `standings.title`（D12 头衔那一列）。⚠ **现在没有任何人写这一列**
--     （schema.sql §4 原注「自由文本无约束、现无人写」）⇒ 上线后恒为 null；
--     留着是为了 D7 写入端落地那天客户端不用再发版。
--     冠军 / 亚军 / 四强 / 进决赛日 现在由客户端从 `finals_week_view(p_week)` 现算
--     （座次表只在客户端 `bracket.gd` 一份，SQL 不写第二遍 —— 见 finals 段头注）。
-- ★排序不变：胜场 → 余命 → 横扫（横扫不上屏，但仍参与同分排序）→ 先到者 → account_id。
-- ★签名不变（p_week bigint, p_limit int）⇒ `create or replace` 原地换函数体，授权照旧。
-- ★周一看「上周终榜」= 客户端传上周的周锚点。`ghosts` 没有任何定时清理
--   （全库 cron 只有 purge_old_matches 删 matches、purge_junk_anon_users 删「在任何表里都没有一行」的匿名号），
--   ⇒ 上周的行周一照样在。
-- ★只读：不建表、不改表、不写任何一行。
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
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
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
             'title', coalesce(r.title, '')) order by r.rk) filter (where r.rk <= lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, top, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot,
    'rows', top, 'me', mine);
end $$;

revoke all on function public.week_leaderboard(bigint, int) from public;
revoke execute on function public.week_leaderboard(bigint, int) from anon;
grant execute on function public.week_leaderboard(bigint, int) to authenticated;
-- <<< END week_leaderboard_v2 20261006b <<<
