-- >>> BEGIN week_leaderboard_v3 20261010 >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜 v3（2026-10-10 · 周六闯关赛实操查实：「积分赛终榜」周六还在变、总场次 20、名次被改写）—— ★待主会话审后上线
--
-- ★病根（客户端，65760c25 已修新包；旧包还在外面照写）：
--   `Backend.upload_gauntlet_ghost` 把周六那份快照也排进了积分赛 `ghosts` 的上传队列，
--   `battles` = `season_total_battles`（周六每场 +1 ⇒ 17、18…），`season_wins` 含周六胜场。
--   v2 每账号取 `battles desc` 最新一行 ⇒ 取到的是周六那一行。
--
-- ★相对 v2（20261006b_week_leaderboard_v2.sql）只在 `latest` 里多两行过滤，其余一个字没动：
--   签名 / 下发字段 / 排序（胜场 → 余命 → 横扫 → 先到者 → account_id）/ 授权全同。
--
-- ★判据 = 快照里的周六战绩标签 `gl_w` / `gl_l`（只有 `upload_gauntlet_ghost` 与 `make_bot` 写它们，
--   积分赛快照 `build_ghost_snapshot` 不写；上传路 `ghost_row_from_snapshot` 原样放进 jsonb，
--   `ReplayUploader.GHOST_STRIP` 只管录像那条路、不碰 `ghosts`）。
--   ★★不是「有 gl_w 就扔」，而是「战绩不是 0-0 就扔」—— 0-0 那一份要留：
--     `ensure_gauntlet_entry_snapshot` 周六进场先传一份 0-0，它的 `battles` = 积分赛收官那一场的场次，
--     与积分赛最后一行【主键相同】，而上传是 upsert（`Prefer: resolution=merge-duplicates`）⇒
--     它原地盖掉了积分赛最后一行（胜场/余命/横扫与收官时一字不差，`uploaded_at` 不在上传体里 ⇒ 不变）。
--     「有 gl_w 就扔」会把这些人的收官行扔掉、退回倒数第二场 —— 正好少算一场。
--   ★比的是 jsonb 值不是文本：快照过一次落盘队列（JSON 存档）数字可能变成 0.0，`'0'::jsonb = '0.0'::jsonb` 为真，
--     而 `->> 'gl_w' = '0'` 对 0.0 为假。没有这个键（积分赛快照）⇒ coalesce 成 0 ⇒ 保留。
--   ★不按 `battles <= 16` 截：提前晋级的人（11 胜 1 负只打 12 场）周六的行是 13、14…，照样在 16 以内。
-- ★只读：不建表、不改表、不写任何一行；库里那些周六行原样留着（周二 00:00 UTC purge_old_matches 随周清掉）。
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
-- <<< END week_leaderboard_v3 20261010 <<<
