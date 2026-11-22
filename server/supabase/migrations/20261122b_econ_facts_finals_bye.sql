-- >>> BEGIN econ_facts_finals_bye 20261122b >>>
-- ─────────────────────────────────────────────────────────────
-- 周日轮空算一轮（2026-11-22 · 用户拍板「算一轮，改服务器」）
--   现象：测试号 LouisT01 冠军杯第 1 轮轮空晋级后，商店「换一批」没反应、之后的流水一条都传不上。
--   查实：客户端把轮空那一场当作出了结果的一轮（BracketMapScene._grant_decided_from → finals_grant_round：+8 币 +2 经验 +1 场、揭晓为胜）；
--     服务器这一场没有裁判任务 ⇒ econ_facts 的 finals n 不加 ⇒ 本周总场次少 1 ⇒ econ_commit 场次闸（迁移 20261117 bt_over）
--     把轮空之后的每一条流水整批拒收（种子也拿不到）；重放 check_facts 同理判 bt:over / over:finals_*。
--   用户 11-22：轮空算一轮（与 11-08「每轮每轮就应该发」一致）⇒ 服务器认轮空：econ_facts 的 finals n / w 各加上这个号本周第 1 轮轮空的场数。
--     n 加了 ⇒ 场次闸、finals / finals_ref（每轮 8 币 2 经验）上限跟着放宽；w 加了 ⇒ finals_reveal 揭晓为胜认得上。
--     铸币（minted）不加 —— 轮空没有对局、没有战斗内铸币。
--   轮空的判据与 finals_champion_seed 同一条口径：finals_advance 给第 1 轮轮空场写 winner_side = 0（标准座次里空座永远在 side 1）；
--     第 1 轮第 m 场的 side 1 座位（2m+1）上的种子号 ≥ 本组人数 ⇒ 空座 ⇒ side 0 座位（2m）上的那个种子轮空晋级。
--   老客户端（0.23.4 / 0.23.5）不用改：它们本来就按一轮发、按一场记。
-- 回滚：econ_facts 换回 20261106 版（schema.sql 里本段之前最后一份 econ_facts）；finals_byes 留着无害。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.finals_byes(p_uid uuid, p_week bigint) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
    from public.finals_buckets b
    join public.finals_entrants e
      on e.season_week = b.season_week and e.bucket_no = b.bucket_no and e.account_id = p_uid
    cross join lateral (select min(x.p)::int as slots
                          from (select (2 ^ g)::int as p from generate_series(0, 14) g) x
                         where x.p >= b.n) s
    join public.finals_results r
      on r.season_week = b.season_week and r.bucket_no = b.bucket_no and r.round = 1 and r.winner_side = 0
   where b.season_week = p_week and b.n > 1
     and public.finals_seed_at_seat(s.slots, r.match_no * 2) = e.seed
     and public.finals_seed_at_seat(s.slots, r.match_no * 2 + 1) >= b.n
$$;
revoke all on function public.finals_byes(uuid, bigint) from public, anon, authenticated;

create or replace function public.econ_facts(p_uid uuid, p_week bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  with j as (
    select kind, a_account = p_uid as is_a, result
      from public.referee_jobs
     where season_week = p_week and status = 'done' and result is not null
       and (a_account = p_uid or (b_account = p_uid and (kind = 'finals' or meta ->> 'pair' = 'true')))
  ), m as (
    select kind,
           (coalesce((result -> 'ledger' ->> 'won')::boolean, false) = is_a) as won,
           coalesce((result -> 'ledger' ->> case when is_a then 'coins' else 'coins_b' end)::numeric, 0)::int as minted,
           result -> case when is_a then 'chest' else 'chest_b' end as chest,
           result -> case when is_a then 'incense' else 'incense_b' end as incense,
           coalesce((result ->> case when is_a then 'axe_kills' else 'axe_kills_b' end)::numeric, 0)::int as axe_kills
      from j
  )
  select jsonb_build_object(
    'ranked', coalesce((select jsonb_build_object('n', r.battles, 'w', r.wins, 'coins', r.coins, 'used', r.used)
                          from public.ranked_records r where r.season_week = p_week and r.account_id = p_uid),
                       '{"n":0,"w":0,"coins":0,"used":0}'::jsonb),
    'gauntlet', jsonb_build_object('n', count(*) filter (where kind = 'gauntlet'),
                                   'w', count(*) filter (where kind = 'gauntlet' and won),
                                   'minted', coalesce(sum(minted) filter (where kind = 'gauntlet'), 0)),
    -- 2026-11-22: 轮空算一轮(1 场 1 胜, 不铸币)
    'finals', jsonb_build_object('n', count(*) filter (where kind = 'finals') + (select public.finals_byes(p_uid, p_week)),
                                 'w', count(*) filter (where kind = 'finals' and won) + (select public.finals_byes(p_uid, p_week)),
                                 'minted', coalesce(sum(minted) filter (where kind = 'finals'), 0)),
    'axe', jsonb_build_object('kills', coalesce(sum(axe_kills), 0)),
    'chest', coalesce(jsonb_agg(chest) filter (where jsonb_typeof(chest) = 'object'), '[]'::jsonb),
    'incense', coalesce(jsonb_agg(incense) filter (where jsonb_typeof(incense) = 'object'), '[]'::jsonb))
    from m
$$;
revoke all on function public.econ_facts(uuid, bigint) from public, anon, authenticated;
-- <<< END econ_facts_finals_bye 20261122b <<<
