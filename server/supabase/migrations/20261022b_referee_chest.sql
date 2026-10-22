-- >>> BEGIN referee_chest 20261022b >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判局的宝箱龟进度回写存档（2026-10-22 · 方案书 docs/plans/20261022-宝箱龟整条链路修复.md 的 A）
--   现状：周六闯关 / 周日决赛由裁判机算，裁判机上宝箱龟照样攒财宝值、开箱，但结果单不带宝箱、
--     客户端记账也不碰 ⇒ 这些局的宝箱进度永远进不了存档，下一场又从旧值起算（用户「宝箱整个是不是有bug啊」）。
--   做法：照战斗内铸币 coins / coins_b 的通路（20261020c / 20261020d）：
--     裁判结果单多带 `chest`（左方 A 本局结束时 {value, won}）与 `chest_b`（右方 B，周日）。
--     referee_complete 存的是整份结果单（去掉录像）⇒ **不用改**，两个字段自然在 referee_jobs.result 顶层。
--     本段只重定义两个读取接口，把它回给客户端：
--       ① referee_job_status（以 20261020c 版为底）：多回 `chest`（只给 A 自己）
--       ② referee_finals_coins（以 20261020d 版为底）：多回 `chest`（A 取 chest、B 取 chest_b；翻面之前照旧不回）
--   ★只在结果单里真有宝箱（是 JSON 对象）时才多一个键 ⇒ 老裁判程序 / 老客户端 / 20261020c、d 的检查脚本都不受影响。
--   ★不在这里校验 value / won 的形状：结果单只能由裁判机（service_role）写；客户端记账时再夹一遍。
-- 上线步骤（tools/sb_migrate.py 标准路径；内测服先走一遍）：
--   sandbox → beta --rehearse → beta --apply → 内测服冒烟 → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
--   之后：裁判机装带 `chest` 的新客户端版本（RefereeRunner 写 chest / chest_b）、登记 referee_versions。
--   在那之前结果单没有 chest ⇒ 两个接口与本段之前逐字相同的回包。
-- 回滚：把两个函数换回 20261020c / 20261020d 版（结果单里多存的 chest 无害）。
-- ─────────────────────────────────────────────────────────────

-- ① 周六：查自己那一场算完没有（只认 a_account = 自己；不回快照）
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
    'won', j.result->'ledger'->'won', 'score', j.result->'ledger'->'score',
    'gw', j.result->'ledger'->'gw', 'gl', j.result->'ledger'->'gl',
    'coins', j.result->'ledger'->'coins',
    'error', case when j.status = 'failed' then j.error end)
    -- 2026-10-22b：这一局结束时我方宝箱龟的进度（财宝值 + 已开战利品）
    || case when j.status = 'done' and jsonb_typeof(j.result->'chest') = 'object'
            then jsonb_build_object('chest', j.result->'chest') else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ② 周日：查我在这一场的战斗内铸币 + 宝箱进度（只读；翻面之前不回数）
create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  -- 不剧透：与 finals_view 同一条（结果行在、且那一轮已翻面）
  if not exists (select 1 from public.finals_results r
                  where r.season_week = p_week and r.bucket_no = p_bucket and r.round = p_round and r.match_no = p_match)
     or not (b.closed or p_round < b.round) then
    return jsonb_build_object('ok', true, 'status', 'pending');
  end if;
  select * into j from public.referee_jobs
   where match_key = format('finals:%s:%s:%s:%s', p_week, p_bucket, p_round, p_match);
  if not found then
    return jsonb_build_object('ok', true, 'status', 'done', 'coins', 0);    -- 没有裁判局（轮空 / 兜底判）
  end if;
  if j.a_account is distinct from uid and j.b_account is distinct from uid then
    return jsonb_build_object('ok', false, 'reason', 'not_in_match');
  end if;
  if j.status = 'done' and j.error is null then          -- superseded = 结果被兜底抢先写了，这一局不是正式那一局
    v := j.result->'ledger'->(case when j.a_account = uid then 'coins' else 'coins_b' end);
    if jsonb_typeof(v) = 'number' and (v #>> '{}')::numeric between 0 and 999 then
      c := floor((v #>> '{}')::numeric)::int;
    end if;
    -- 2026-10-22b：A 取 chest、B 取 chest_b（侧由服务端认，不是客户端报）
    ch := j.result->(case when j.a_account = uid then 'chest' else 'chest_b' end);
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;
-- <<< END referee_chest 20261022b <<<
