-- >>> BEGIN finals_settle_once 20261012 >>>
-- ─────────────────────────────────────────────────────────────
-- 周日「购物结束后统一结算、每场只算一次」（2026-10-12 · 方案书 docs/plans/20261012-周日统一结算.md）
--   用户：「那怎么搞啊」「今天末必须发新包」「做」。原稿 §四：「3 分钟备战购物 → 系统瞬间结算 → 全桶观看重放」；
--   §五.2「共享种子结算一次 → 双方各自观看同一份重放」；§四「不在线 = 快照代打」。
-- 修的两个实操问题：
--   S4 对局用的是周六晋级那一刻的快照、谁先点开谁打、购物窗内就能开打；
--   S6 两边各打各的（种子 / 输入都不同）⇒ 两边都算出自己赢，服务端采纳先到的那份。
-- 做法（全是添加或收紧，不删数据）：
--   ① finals_update_snapshot：购物窗内，组里的人可以更新自己这一份快照（= 购物后的阵容）。
--   ② finals_opponent：购物窗内不给对手快照（reason shop_open）；带上场号时，已有结果回 settled。
--   ③ finals_report：购物窗内拒收；必须带 p_reporter_side ——
--        上半区(0) 购物结束即可报；下半区(1) 要等本轮标准时长走完（购物 + 300 秒）还没结果才收（= 替不在线的上半区快照代打）；
--        不带侧别（旧客户端）拒收 update_required。
--      并入 20261011_finals_report_guard（未上过生产）的两条：场号越界拒收、第 1 轮轮空场拒收。
-- ⇒ 每场只有一份输入（上半区锁定的阵容 × 下半区购物后的快照）、只算一次、大家看同一份录像。
-- ★重复执行安全（create or replace / drop if exists）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.finals_shop_sec() returns int
language sql immutable as $$ select 180 $$;      -- = 客户端 Phase2Config.FINALS_SHOP_SEC
create or replace function public.finals_lower_grace_sec() returns int
language sql immutable as $$ select 300 $$;      -- 购物结束后给上半区的时间; = 客户端 Phase2Config.FINALS_LOWER_GRACE_SEC

-- ① 购物窗内更新自己的快照
create or replace function public.finals_update_snapshot(p_week bigint, p_bucket int, p_snapshot jsonb)
returns boolean
language plpgsql security definer set search_path = public as $$
declare b record; n int;
begin
  if auth.uid() is null or p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
     or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') < 3 then
    return false;                       -- 没有 3 只统领的快照不收(防空阵容覆盖周六那份正式阵容)
  end if;
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return false;
  end if;
  if now() >= b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return false;                       -- 购物结束 = 本轮阵容锁定
  end if;
  update public.finals_entrants set snapshot = p_snapshot
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.finals_update_snapshot(bigint, int, jsonb) from public, anon;
grant execute on function public.finals_update_snapshot(bigint, int, jsonb) to authenticated;

-- ② 对手快照：购物窗内不给；带场号时已结算回 settled
drop function if exists public.finals_opponent(bigint, int, int, int);
create or replace function public.finals_opponent(p_week bigint, p_bucket integer, p_round integer, p_seed integer,
    p_match integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare b record; mine int; asked int; snap jsonb; nm text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  -- ★2026-10-12: 购物窗内不给对手快照 —— 对手还在购物, 给出去的是他购物前的阵容(S4)
  if now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  -- ★2026-10-12: 这一场已经有结果 ⇒ 不再给(每场只算一次; 不泄露胜负, 只说已结算)
  if p_match is not null and exists (select 1 from public.finals_results
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = p_match) then
    return jsonb_build_object('ok', false, 'reason', 'settled');
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_seed = mine then
    return jsonb_build_object('ok', false, 'reason', 'thats_you');
  end if;
  select snapshot, name into snap, nm from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and seed = p_seed;
  if snap is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_seed');
  end if;
  insert into public.finals_scout (season_week, bucket_no, round, account_id, seed)
    values (p_week, p_bucket, p_round, auth.uid(), p_seed)
    on conflict (season_week, bucket_no, round, account_id) do nothing;
  select seed into asked from public.finals_scout
   where season_week = p_week and bucket_no = p_bucket
     and round = p_round and account_id = auth.uid();
  if asked <> p_seed then
    return jsonb_build_object('ok', false, 'reason', 'already_asked', 'seed', asked);
  end if;
  return jsonb_build_object('ok', true, 'seed', p_seed, 'name', nm, 'snapshot', snap);
end $function$;
revoke all on function public.finals_opponent(bigint, int, int, int, int) from public, anon;
grant execute on function public.finals_opponent(bigint, int, int, int, int) to authenticated;

-- ③ 上报：购物窗内拒收; 必须带侧别; 下半区等宽限; 场号 / 轮空校验
drop function if exists public.finals_report(bigint, int, int, int, int, bigint);
create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint, p_reporter_side int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; slots int := 1; n_match int; bye_seed int; open_at timestamptz;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_winner_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'bad_side');
  end if;
  -- ★2026-10-12: 旧客户端(不带侧别)按旧规矩各打各的 ⇒ 不收
  if p_reporter_side is null or p_reporter_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  open_at := b.round_at + make_interval(secs => public.finals_shop_sec());
  if now() < open_at then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  if p_reporter_side = 1 and now() < open_at + make_interval(secs => public.finals_lower_grace_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'upper_first');
  end if;
  -- 场号必须是本轮真实存在的场(20261011_finals_report_guard ①)
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  n_match := greatest(1, slots / (2 ^ p_round)::int);
  if p_match < 0 or p_match >= n_match then
    return jsonb_build_object('ok', false, 'reason', 'bad_match', 'n_match', n_match);
  end if;
  -- 第 1 轮轮空场不收(20261011_finals_report_guard ②)
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
revoke all on function public.finals_report(bigint, int, int, int, int, bigint, int) from public, anon;
grant execute on function public.finals_report(bigint, int, int, int, int, bigint, int) to authenticated;
-- <<< END finals_settle_once 20261012 <<<
