-- >>> BEGIN referee_incense 20261023 >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判局的 093 香火石刻痕 / 充能回写存档（2026-10-23 · 方案书 docs/plans/20261023-香火石四个问题.md 的 3）
--   现状：裁判机上我方的刻痕 / 充能写死 0（周末服务器局里刻痕不生效），结果单也不带香火
--     ⇒ 这些局里攒的充能 / 刻痕永远进不了存档（用户「香火石有bug啊」→「这是个问题」）。
--   做法：照宝箱龟 chest / chest_b 的通路（20261022b）：
--     裁判结果单多带 `incense`（左方 A 本局结束时 {marks, charge}）与 `incense_b`（右方 B，周日）。
--     referee_complete 存的是整份结果单（去掉录像）⇒ **不用改**，两个字段自然在 referee_jobs.result 顶层。
--     本段只重定义两个读取接口（以 20261022b 版为底，宝箱那一段逐字保留），多回一个 `incense`：
--       ① referee_job_status：多回 `incense`（只给 A 自己）
--       ② referee_finals_coins：多回 `incense`（A 取 incense、B 取 incense_b；翻面之前照旧不回）
--   ★只在结果单里真有香火（是 JSON 对象）时才多一个键 ⇒ 老裁判程序 / 老客户端不受影响。
--   ★不在这里校验 marks / charge 的形状：结果单只能由裁判机（service_role）写；客户端记账时再夹一遍（RefereeNet.parse_incense）。
-- 上线步骤（tools/sb_migrate.py 标准路径；内测服先走一遍；**必须排在 20261022b 之后**）：
--   sandbox → beta --rehearse → beta --apply → 内测服冒烟 → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
--   之后：裁判机装带 `incense` 的新客户端版本（RefereeRunner 写 incense / incense_b）、登记 referee_versions。
--   在那之前结果单没有 incense ⇒ 两个接口与 20261022b 逐字相同的回包。
-- 回滚：把两个函数换回 20261022b 版（结果单里多存的 incense 无害）。
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
            then jsonb_build_object('chest', j.result->'chest') else '{}'::jsonb end
    -- 2026-10-23：这一局结束时我方 093 香火石的刻痕 + 充能
    || case when j.status = 'done' and jsonb_typeof(j.result->'incense') = 'object'
            then jsonb_build_object('incense', j.result->'incense') else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ② 周日：查我在这一场的战斗内铸币 + 宝箱进度 + 香火（只读；翻面之前不回数）
create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null; inc jsonb := null;
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
    -- 2026-10-23：A 取 incense、B 取 incense_b（同上）
    inc := j.result->(case when j.a_account = uid then 'incense' else 'incense_b' end);
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end
    || case when jsonb_typeof(inc) = 'object' then jsonb_build_object('incense', inc) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;
-- <<< END referee_incense 20261023 <<<
