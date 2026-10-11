-- 2026-10-11 全项目通读(赛制第 2 条): finals_report 不校验场号 / 轮空场能被抢
--
-- ① 原来只校验「当前轮 + 我在这个桶里 + side ∈ {0,1}」, 不校验 p_match 的范围。
--    finals_advance 按【结果行数】判本轮是否打完 ⇒ 组里任何人报几个越界的假场号, 行数就凑够了,
--    本轮在 480 秒到点时提前收盘, 没报的真场次被补判 side 0 晋级。
-- ② 第 1 轮的轮空场(side 1 是空座)本该由 finals_advance 补 side 0 让真人晋级;
--    但补判用的是 on conflict do nothing ⇒ 组里任何人先报一个 winner_side = 1(空座赢), 真人就被淘汰。
--
-- 修: 场号必须落在本轮真实场次范围 [0, slots / 2^round) 内; 第 1 轮 side 1 是空座的场一律不收(由推进器补)。
-- ★座次表用已有的 finals_seed_at_seat(与客户端 bracket.gd 同构, verify_champion_cup 对过账), 不新写第二份。
-- 正文照抄 schema.sql 现行版, 只加标了「2026-10-11」的两段。

create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; slots int := 1; n_match int; bye_seed int;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  -- ★只收当前轮: 收旧轮的等于允许改已经翻过面的结果; 收未来轮等于提前定胜负
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  -- ★报的人必须是这个桶里的人。**"是不是这一场的人"客户端说了不算**, 但
  --   "在不在这个桶里"服务端查得到; 精确到"这一场"需要服务端自己推对阵树,
  --   那就是把对阵规则在 SQL 里写第二遍了 ⇒ 这里只挡到桶级, 差额记在下面的注释里。
  -- ⚠ 已知缺口: 同桶的旁观者能替别人报一场。与排行榜/快照池同一个信任模型,
  --   服务端复算是 B 阶段第二步的事 —— 不假装它不存在。
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_winner_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'bad_side');
  end if;
  -- ★2026-10-11 ①: 场号必须是本轮真实存在的场(否则越界假场号会凑够行数、提前收盘)
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  n_match := greatest(1, slots / (2 ^ p_round)::int);
  if p_match < 0 or p_match >= n_match then
    return jsonb_build_object('ok', false, 'reason', 'bad_match', 'n_match', n_match);
  end if;
  -- ★2026-10-11 ②: 第 1 轮的轮空场(side 1 坐的是空座)不收任何上报 —— 由 finals_advance 补 side 0
  if p_round = 1 then
    bye_seed := public.finals_seed_at_seat(slots, 2 * p_match + 1);
    if bye_seed < 0 or bye_seed >= b.n then
      return jsonb_build_object('ok', false, 'reason', 'bye');
    end if;
  end if;
  insert into public.finals_results
    (season_week, bucket_no, round, match_no, winner_side, seed_used)
    values (p_week, p_bucket, p_round, p_match, p_winner_side, coalesce(p_seed, 0))
    on conflict (season_week, bucket_no, round, match_no) do nothing;
  return jsonb_build_object('ok', true);
end $$;
