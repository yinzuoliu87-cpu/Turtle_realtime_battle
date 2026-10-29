-- >>> BEGIN gauntlet_old_client_gate 20261029 >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛旧客户端闸（2026-10-29 · 接 20261027_gauntlet_online_queue / 20261027b · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2「版本」）
--   用户 10-29 选方案 ②（「行」）：周六只收在线排队的新客户端，旧客户端给一句明确的「需要更新」，平日照常。
--   内测服 10-29 实测（0.22.2 客户端，假周六）：
--     · 不加闸：旧入口 referee_gauntlet_start 照旧当场配一份快照、只记旧客户端这一边 —— 不进在线排队，「两边各算各的」照旧；
--     · 关掉 referee_versions 里的 0.22.2：回 39 字的 update_required ⇒ 0.22.2 弹整屏墙「需要更新 / 当前版本已停止服务……
--       当前版本 0.22.2 · 最低版本 0.21.3」，挡住匹配屏的「←」，要重开 App 才撤；还连带挡掉它旧录像的补流。
--   本段：只改 referee_gauntlet_start 一处 —— 过了「时段 / 阵容 / 已打完 / 在算的那场 / 账本对齐」之后、建任务之前，
--     客户端版本 < gauntlet_queue_min_client()（0.22.3，在线排队的第一个客户端版本）⇒ 回 update_required（补到 600 字以上）。
--     版本比较用现成的 semver_arr（数字逐段比，0.22.10 > 0.22.3）。其余逐字照抄 20261027 版。
--   不动：referee_versions（0.22.2 的旧录像补流照常）、min_client_version（平日照常）、积分赛与在线排队的任何函数。
--   ★0.22.3 起的客户端不调本函数（客户端线 10-27 删掉了旧入口调用）⇒ 对它们没有可见变化。
-- 上线步骤（tools/sb_migrate.py 标准路径；必须排在 20261027_gauntlet_online_queue 之后 —— 本段以它的 referee_gauntlet_start 为底）：
--   sandbox → beta --rehearse → beta --apply → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
-- 回滚：referee_gauntlet_start 换回 20261027 版（gauntlet_queue_min_client 留着无害）。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

-- 在线排队协议的第一个客户端版本（= CHANGELOG 0.22.3「闯关赛改为在线匹配」）。低于它的客户端周六不再开新局。
create or replace function public.gauntlet_queue_min_client() returns text
language sql immutable as $$ select '0.22.3' $$;
revoke all on function public.gauntlet_queue_min_client() from public, anon, authenticated;

-- 旧路开打（以 20261027 版为底；★2026-10-29 只加「旧客户端闸」一段，见函数体里 ★2026-10-29 那几行）
create or replace function public.referee_gauntlet_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text, p_rules_ver int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text; v_rv int;
        v_b int; pk jsonb; jid bigint; mid uuid; st text; v_snap_b jsonb; v_meta jsonb; v_found boolean;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = p_client_version and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is distinct from v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 00:00 ~ 周日 17:30（周锚点 + 5 天 ~ + 6 天 17:30；2026-10-26 起，原为周六一整天；UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or octet_length(p_snapshot::text) > 65536 or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- ★2026-10-27 在线瑞士轮：配对局（meta.pair）里我是 B 也算「在算的那场」，对手卡给 A 那一侧。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人，不是在场的人。
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end),
      'gw', v_gw, 'gl', v_gl);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- ★2026-10-29 旧客户端闸（迁移 20261029）：闯关赛改成在线排队后，0.22.3 起的客户端走 gauntlet_queue_join、不再调本函数；
  --   低于 gauntlet_queue_min_client() 的客户端在这里停下 —— 不建任务、不重交失败的那一场，回 update_required。
  --   回包补到 600 字以上（pad）：0.22.2 把「≤512 字且含 "update_required"」的回包当成整个版本停服，弹整屏「需要更新」墙
  --   （它的 version_gate.gd is_update_required_response），可它平日积分赛照常能打；补长之后它只在匹配屏写一行
  --   「版本过旧，请更新」，左上「←」能回主菜单。放在「在算的那场 / 账本对齐」之后：切换前交上去的那一场照样能查到、补记。
  if coalesce(public.semver_arr(p_client_version), array[0, 0, 0, 0]) < public.semver_arr(public.gauntlet_queue_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required', 'min_version', public.gauntlet_queue_min_client(),
      'pad', repeat('-', 600));
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'gw', v_gw, 'gl', v_gl);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta->'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta->>'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_gauntlet_pick(uid, p_week, v_gw, v_gl, v_rv,
              coalesce((v_meta->>'battles')::int, v_gw + v_gl));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'gw', v_gw, 'gl', v_gl);
      end if;
      v_snap_b := pk->'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk->>'opp', 'pick', pk->>'pick');
      update public.referee_jobs set b_account = (pk->>'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = p_client_version,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then p_snapshot else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(p_snapshot) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'gw', v_gw, 'gl', v_gl);
  end if;
  -- 机器人强度 = 我的本周场次（客户端 gauntlet_bot_battles = max(本大轮场次, gw + gl)）。
  --   快照自报的 season_total_battles 只能往上抬（报高了 = 自己打更强的机器人）；地板 = 服务端看得到的积分赛场次 + 周六已打场次。
  v_b := greatest(
    case when jsonb_typeof(p_snapshot->'season_total_battles') = 'number'
         then least((p_snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = uid and season_week = p_week), 0) + v_gw + v_gl,
    v_gw + v_gl);
  pk := public.referee_gauntlet_pick(uid, p_week, v_gw, v_gl, v_rv, v_b);
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'gw', v_gw, 'gl', v_gl);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, (pk->>'account')::uuid,
      p_snapshot, pk->'snap', public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', v_rv, 'battles', v_b, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'gw', v_gw, 'gl', v_gl);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk->'snap'), 'gw', v_gw, 'gl', v_gl);
end $$;
revoke all on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) to authenticated;
-- <<< END gauntlet_old_client_gate 20261029 <<<
