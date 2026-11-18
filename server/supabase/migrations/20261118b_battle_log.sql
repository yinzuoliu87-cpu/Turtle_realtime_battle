-- >>> BEGIN battle_log 20261118b >>>
-- ─────────────────────────────────────────────────────────────
-- 战绩页的数据源：我自己的服务器对局（2026-11-18 · 方案书 docs/plans/20261118-对局记录重做.md §4.1）
--   用户 11-18「对局记录现在就只有…积分赛…周周日是不是没有啊？然后偷袭的是不是也没有啊？…时间双方的装备也没有。」
--   原来战绩页只读本机 50 条（只记这台设备打的积分赛 / 周六裁判局，没装备、没时间）。服务器 referee_jobs 里四种都有，
--   但它开着 RLS 没有策略（快照 = 阵容情报）⇒ 这里给一个只读 RPC，只回展示要用的字段，不回整份快照。
--
--   my_battle_log(p_limit = 20, p_before = null) → [{...}, …]（按 job_id 倒序；p_before = 上一页最后一行的 id）
--     · 取 status = done，且「a 方是我」或「b 方是我且是 闯关 / 决赛 / 偷袭」——积分赛的 b 方是别人拿我的快照打的，不算我打的
--     · 每行：id, kind, week, at(结束时刻，秒), side(a|b), won, secs(时长秒，60 步 = 1 秒), lanes {top, bottom: me|foe|null},
--             match_id, replay(matches 里有录像), finals {bucket, round, match}(决赛), raid_role(偷袭：attack|defend),
--             me / foe = {name, tag, avatar, leaders, equipped(只留三统领), lanes(lane_assign)}
-- ★只读；authenticated 才能调。
-- 回滚：drop function public.my_battle_log(int, bigint)；两条索引留着无害。
-- ★重复执行安全。
-- ─────────────────────────────────────────────────────────────

create index if not exists referee_jobs_a_acc_job_idx on public.referee_jobs (a_account, job_id desc) where status = 'done';
create index if not exists referee_jobs_b_acc_job_idx on public.referee_jobs (b_account, job_id desc) where status = 'done';

create or replace function public.battle_log_side(p_snap jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'name', coalesce(p_snap -> 'profile' ->> 'name', ''),
    'tag', coalesce(p_snap -> 'profile' ->> 'tag', ''),
    'avatar', coalesce(p_snap -> 'profile' ->> 'avatar', ''),
    'leaders', case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' else '[]'::jsonb end,
    'equipped', coalesce((select jsonb_object_agg(l, coalesce(p_snap -> 'equipped' -> l, '[]'::jsonb))
                            from jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array'
                                                                then p_snap -> 'leaders' else '[]'::jsonb end) l), '{}'::jsonb),
    'lanes', case when jsonb_typeof(p_snap -> 'lane_assign') = 'object' then p_snap -> 'lane_assign' else '{}'::jsonb end)
$$;
revoke all on function public.battle_log_side(jsonb) from public, anon, authenticated;

create or replace function public.my_battle_log(p_limit int default 20, p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_out jsonb;
begin
  if uid is null then
    return '[]'::jsonb;
  end if;
  with mine as (
    select j.*, case when j.a_account = uid then 'a' else 'b' end as side
      from public.referee_jobs j
     where j.status = 'done'
       and (p_before is null or j.job_id < p_before)
       and (j.a_account = uid or (j.b_account = uid and j.kind in ('gauntlet', 'finals', 'raid')))
     order by j.job_id desc
     limit greatest(1, least(coalesce(p_limit, 20), 50))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.job_id,
      'kind', m.kind,
      'week', m.season_week,
      'at', extract(epoch from coalesce(m.done_at, m.created_at))::bigint,
      'side', m.side,
      'won', (m.result ->> 'winner') = m.side,
      'secs', round(coalesce((m.result ->> 'steps')::numeric, 0) / 60.0)::int,
      'lanes', jsonb_build_object(
          'top', case m.result -> 'lane_results' ->> 'top'
                   when (case m.side when 'a' then 'left' else 'right' end) then 'me'
                   when (case m.side when 'a' then 'right' else 'left' end) then 'foe' end,
          'bottom', case m.result -> 'lane_results' ->> 'bottom'
                   when (case m.side when 'a' then 'left' else 'right' end) then 'me'
                   when (case m.side when 'a' then 'right' else 'left' end) then 'foe' end),
      'match_id', m.match_id,
      'replay', exists (select 1 from public.matches x where x.match_id = m.match_id and x.replay is not null),
      'finals', case when m.kind = 'finals' then jsonb_build_object(
          'bucket', m.meta -> 'bucket', 'round', m.meta -> 'round', 'match', m.meta -> 'match') end,
      'raid_role', case when m.kind = 'raid' then (case m.side when 'a' then 'attack' else 'defend' end) end,
      'me', public.battle_log_side(case m.side when 'a' then m.a_snapshot else m.b_snapshot end),
      'foe', public.battle_log_side(case m.side when 'a' then m.b_snapshot else m.a_snapshot end)
    ) order by m.job_id desc), '[]'::jsonb)
    into v_out from mine m;
  return v_out;
end $$;
revoke all on function public.my_battle_log(int, bigint) from public, anon;
grant execute on function public.my_battle_log(int, bigint) to authenticated;
-- <<< END battle_log 20261118b <<<
