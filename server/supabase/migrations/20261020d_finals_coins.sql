-- >>> BEGIN finals_coins 20261020d >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛（小组赛 + 冠军杯赛）服务器算的局照常发战斗内铸币（2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md
--   R8「周日服务器局不发局内金币」那一条）—— ★只写文件、未上生产。
--   前提：20261019_referee_jobs.sql / 20261020c_gauntlet_server_pick_and_coins.sql 已执行（本段重定义的 referee_complete 以 20261020c 版为底）。
--
-- 缺口：本机打（老路）时 `_settle_season` 把奇械羁绊铸币 + 035 黄铜齿轮加进奖励；服务器算的周日局一枚都没发：
--   ① 结果单只带左方（A = 上侧 side 0）的 `coins`，右方（B）没人算；
--   ② 周日客户端不查任务（没有 referee_job_status 那一步，结果等对阵图揭晓），连 A 的那一份也没有人去取。
-- 改法：
--   Ⅰ 裁判结果单多一个 `coins_b`（右方 B 的铸币，`EquipTickSystem.match_minted(battle, "right")`，与 `coins` 同一个出口同一刻读）；
--     referee_complete 把它夹到 0..999 记进账本 `ledger.coins_b`（只有周日任务记；周六的对手可能是机器人，不记）。
--     老裁判程序（v0.21.2 及以前）的结果单没有 coins_b ⇒ 0。
--   Ⅱ 新只读接口 referee_finals_coins(p_week, p_bucket, p_round, p_match)：查「我在这一场的战斗内铸币」。
--     · 我是哪一侧由服务端按 auth.uid() 对任务行的 a_account / b_account 认（客户端不报侧、不报数）；
--     · 不剧透：结果没翻面（与 finals_view 同一条 `b.closed or round < b.round`）⇒ status = pending、不回数；
--     · 翻面了但这一场没有裁判局（轮空 / 3 倍时长兜底判的 / 裁判结果被兜底抢先 superseded / 任务失败）⇒ done、coins = 0；
--     · 我不在这一场 ⇒ not_in_match。
--   客户端：点开自己那一场时（`RefereeWatch.finals_seal`）记一张「待取铸币」单（存档），翻面后查一次、按回包发（出局那一局不发，
--     与 `_settle_season` 同一条），发完销单 —— 同一场只发一次。
-- 本段内容：① 重定义 referee_complete（多记 coins_b；其余逐字照抄 20261020c 版，只在标了「2026-10-20d」的地方改）
--           ② referee_finals_coins（authenticated）
-- ★重复执行安全（create or replace）。不改任何表、不改任何开关 ⇒ 执行本段不改变现行客户端的行为。
-- ─────────────────────────────────────────────────────────────

-- ① 写回：多记右方铸币
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
begin
  select * into j from public.referee_jobs where job_id = p_job_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  if j.status = 'done' then
    return jsonb_build_object('ok', true, 'reason', 'already_done');
  end if;
  if j.status <> 'claimed' or j.claimed_by is distinct from p_worker then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or coalesce(p_result->>'ok', 'false') <> 'true'
     or p_result->>'match_id' is distinct from j.match_id::text
     or jsonb_typeof(p_result->'seed') <> 'number' or (p_result->>'seed')::numeric <> j.seed
     or p_result->>'client_version' is distinct from j.client_version
     or coalesce(p_result->>'winner', '') not in ('a', 'b')
     or jsonb_typeof(p_result->'steps') <> 'number' or (p_result->>'steps')::numeric <= 0
     or jsonb_typeof(p_result->'replay_b64') <> 'string'
     or octet_length(p_result->>'replay_b64') not between 1 and 65536      -- = matches_replay_size = 客户端 REPLAY_MAX_B64
     or (p_result->>'replay_b64') !~ '^[A-Za-z0-9+/]+={0,2}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_result');
  end if;
  won := p_result->>'winner' = 'a';
  sc := case when jsonb_typeof(p_result->'score_code') = 'number' then (p_result->>'score_code')::numeric::int else -1 end;
  -- ★2026-10-20 战斗内铸币（缺 / 不是数 / 越界 ⇒ 0；不是整数 ⇒ 向下取整）
  if jsonb_typeof(p_result->'coins') = 'number' and (p_result->>'coins')::numeric between 0 and 999 then
    v_coins := floor((p_result->>'coins')::numeric)::int;
  end if;
  -- ★2026-10-20d 右方（B）的战斗内铸币：周日决赛两边都是真人，各按自己那一侧发（同一道夹：缺 / 不是数 / 越界 ⇒ 0）
  if jsonb_typeof(p_result->'coins_b') = 'number' and (p_result->>'coins_b')::numeric between 0 and 999 then
    v_coins_b := floor((p_result->>'coins_b')::numeric)::int;
  end if;
  res := jsonb_build_object('won', won, 'steps', (p_result->>'steps')::numeric::int, 'surrendered', false,
                            'referee', true, 'score', sc);
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.a_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.a_account, case when won then 1 else 0 end, case when won then 0 else 1 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw, v_gl;
    res := res || jsonb_build_object('gw', v_gw, 'gl', v_gl);
    -- ★2026-10-20 规则版本：任务里记的那个（服务端挑对手时定的）> 裁判版本登记的 > 0（老任务、老口径）
    v_rv := coalesce(case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    -- 以打完这一场的新战绩标签挂进快照池（同 E-A4：下一场要找的是「跟我现在同样几胜几负」的人）
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.a_account, j.season_week, v_gw, v_gl, j.a_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  -- ★2026-10-20d 周日任务的账本多一个 coins_b（右方 B 的战斗内铸币；周六不记）
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins)
                  || case when j.kind = 'finals' then jsonb_build_object('coins_b', v_coins_b) else '{}'::jsonb end)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;


-- ② 周日：查我在这一场的战斗内铸币（只读；翻面之前不回数）
create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0;
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
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c);
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;

-- 上线步骤（内测服先走一遍，每步回读；正式服同样顺序。★全程不需要停服）：
--   1. 执行本文件（检查脚本 server/supabase/tests/20261020d_finals_coins_check.sql 先在回滚事务里跑过）。
--      回读：select has_function_privilege('authenticated', 'public.referee_finals_coins(bigint, int, int, int)', 'execute');  -- true
--   2. 裁判机装带 coins_b 的新客户端版本（RefereeRunner 写 coins_b），登记 referee_versions，finals_version 抬到它。
--      在那之前周日任务的 coins_b 一律 0（A 的 coins 老裁判程序本来就写了）。
--   3. 新客户端上架。旧包（0.21.2）不调本接口 ⇒ 周日照旧不发战斗内铸币（不出错）。
--   兼容：新包碰到没执行本文件的服务端 ⇒ referee_finals_coins 404 ⇒ 待取单留着、不发（下次再问），不出本地数。
--   回滚：drop function public.referee_finals_coins(bigint, int, int, int); referee_complete 换回 20261020c 版（多记的 coins_b 留在账本里无害）。
-- <<< END finals_coins 20261020d <<<
