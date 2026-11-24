-- >>> BEGIN finals_week_journey 20261124 >>>
-- ─────────────────────────────────────────────────────────────
-- 夺冠之路一整周的数据源（2026-11-24 · 方案书 docs/plans/20261124-夺冠之路一整周.md §4）
--   用户 11-24「不是人家打的积分赛那十六场啊，然后…瑞士轮那几场，然后…小组赛几场，冠军几场。那比分你都不展示吗？」
--   冠军收盘多半是别人在看 ⇒ my_battle_log（只回自己）不够；这里按「这一周 + 这个人」取，只对这一周决赛日的参赛者开放。
--
--   finals_week_journey(p_week, p_account) → {ok, rows:[…]} / {ok:false, reason: bad|not_entrant}
--     · 取 status = done、season_week = p_week；ranked 只取 a 方（b 方是别人拿他快照打的，不算他打的，同 my_battle_log）；
--       gauntlet / finals 两方都取。按 job_id 正序，最多 80 行。
--     · 每行：id, kind, at(结束时刻，秒), won, lanes {top, bottom, final: me|foe|null},
--             finals {bucket, round, match}（决赛）, foe {name, avatar, leaders}
--     · 不回快照、装备、对手账号。
-- ★只读；authenticated 才能调。不改表、不改现有函数。
-- 回滚：drop function public.finals_week_journey(bigint, uuid); drop function public.journey_lane(jsonb, text, text);
-- ★重复执行安全。
-- ─────────────────────────────────────────────────────────────

create or replace function public.journey_lane(p_lr jsonb, p_lane text, p_side text) returns text
language sql immutable as $$
  select case p_lr ->> p_lane
           when (case p_side when 'a' then 'left' else 'right' end) then 'me'
           when (case p_side when 'a' then 'right' else 'left' end) then 'foe' end
$$;
revoke all on function public.journey_lane(jsonb, text, text) from public, anon, authenticated;

create or replace function public.finals_week_journey(p_week bigint, p_account uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if auth.uid() is null or p_week is null or p_account is null then
    return jsonb_build_object('ok', false, 'reason', 'bad');
  end if;
  if not exists (select 1 from public.finals_entrants e where e.season_week = p_week and e.account_id = p_account) then
    return jsonb_build_object('ok', false, 'reason', 'not_entrant');
  end if;
  with j as (
    select r.job_id, r.kind, r.done_at, r.created_at, r.result, r.meta,
           case when r.a_account = p_account then 'a' else 'b' end as side,
           case when r.a_account = p_account then r.b_snapshot else r.a_snapshot end as foe_snap
      from public.referee_jobs r
     where r.status = 'done' and r.season_week = p_week
       and ((r.kind = 'ranked' and r.a_account = p_account)
         or (r.kind in ('gauntlet', 'finals') and (r.a_account = p_account or r.b_account = p_account)))
     order by r.job_id
     limit 80
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', j.job_id,
      'kind', j.kind,
      'at', extract(epoch from coalesce(j.done_at, j.created_at))::bigint,
      'won', (j.result ->> 'winner') = j.side,
      'lanes', jsonb_build_object(
          'top', public.journey_lane(j.result -> 'lane_results', 'top', j.side),
          'bottom', public.journey_lane(j.result -> 'lane_results', 'bottom', j.side),
          'final', public.journey_lane(j.result -> 'lane_results', 'final', j.side)),
      'finals', case when j.kind = 'finals' then jsonb_build_object(
          'bucket', j.meta -> 'bucket', 'round', j.meta -> 'round', 'match', j.meta -> 'match') end,
      'foe', jsonb_build_object(
          'name', coalesce(j.foe_snap -> 'profile' ->> 'name', ''),
          'avatar', coalesce(j.foe_snap -> 'profile' ->> 'avatar', ''),
          'leaders', case when jsonb_typeof(j.foe_snap -> 'leaders') = 'array' then j.foe_snap -> 'leaders' else '[]'::jsonb end)
    ) order by j.job_id), '[]'::jsonb)
    into v_rows from j;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end $$;
revoke all on function public.finals_week_journey(bigint, uuid) from public, anon;
grant execute on function public.finals_week_journey(bigint, uuid) to authenticated;
-- <<< END finals_week_journey 20261124 <<<
