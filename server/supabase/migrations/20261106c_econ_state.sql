-- >>> BEGIN econ_state 20261106c >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账 · 服务器重放结果 + 开局比对（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 · S4b）
--   用户 11-06「装备要改成伏击机装了，这个要做。」（伏击机装 = 服务器记账）
--   S3 起流水在 econ_ops 里；裁判机（轮询器 + 无头 Godot `--econ-replay`，同一份 EconLedger.apply）从本周开局重放出权威状态，写进这里；
--   积分赛开局 / 周六进队时拿快照比 —— 改存档多塞一件装备、自报大轮等级 / 小木斧 / 宝箱 / 香火 ⇒ 拒。
-- 本段（★开关 econ_on 关着 ⇒ econ_check 恒回 null ⇒ 两个开局函数行为一字不变）：
--   ① econ_state：每人每周一行 = 重放到第几条（seen）/ 成交几条 / 第一条不合法的序号与原因 / 资产与宝箱香火的规整结果 / 按来源汇总的收入
--   ② econ_replay_claim / econ_replay_done：只给 service_role（裁判机轮询器）。只重放到「服务器发了种子、客户端还没传回带 bt 的那一条」之前
--   ③ econ_check(号, 周, 快照)：null = 对得上；否则 {ok:false, reason: econ_pending / econ_invalid / econ_mismatch, …}
--   ④ econ_truncate(周, 序号)：重放判了第 N 条不合法 ⇒ 客户端认了服务器那一份（本机按服务器流水重放对齐）之后，把第 N 条起作废
--   ⑤ referee_ranked_start / gauntlet_queue_join：以现行版为底逐字照抄，只在标了「2026-11-06」的地方插 econ_check
-- ─────────────────────────────────────────────────────────────

create table if not exists public.econ_state (
  account_id  uuid        not null references auth.users(id) on delete cascade,
  week        bigint      not null,
  seen        int         not null default 0,       -- 重放时用了这一周的前几条流水
  upto        int         not null default 0,       -- 其中成交了几条
  bad_at      int         not null default -1,      -- 第一条不合法 / 不成交的序号（-1 = 全过）
  why         text        not null default '',
  assets      jsonb       not null default '{}',    -- EconLedger.assets_of 的结果（与客户端同一把尺子）
  progress    jsonb       not null default '{}',    -- EconLedger.progress_of（宝箱 / 香火）
  income      jsonb       not null default '{}',    -- 按来源汇总的收入 {src: {coins, xp, n}}（S4b-2 对服务器自己的账）
  fp          text        not null default '',
  updated_at  timestamptz not null default now(),
  primary key (account_id, week)
);
alter table public.econ_state enable row level security;
drop policy if exists econ_state_self on public.econ_state;
create policy econ_state_self on public.econ_state for select using (auth.uid() = account_id);
create index if not exists econ_ops_week_idx on public.econ_ops (week, account_id);

-- ② 领活：本周「可重放的前缀」比 econ_state.seen 长的号。前缀 = 按序号到第一条「服务器写下的种子行、客户端还没传回」之前
--   （那一条缺 bt，重放时场次戳是错的）。每次给整份前缀（一周几百条，纯计算）。
create or replace function public.econ_replay_claim(p_limit int default 20) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_wk bigint := public.econ_week_now(); v_out jsonb := '[]'::jsonb; r record; v_pre int;
        v_lim int := greatest(1, least(coalesce(p_limit, 20), 200));
begin
  for r in
    select o.account_id, count(*)::int as n,
           min(o.seq) filter (where o.src = 'server' and not (o.op ? 'bt')) as cut,
           coalesce(max(s.seen), -1) as seen
      from public.econ_ops o
      left join public.econ_state s on s.account_id = o.account_id and s.week = o.week
     where o.week = v_wk
     group by o.account_id
  loop
    v_pre := coalesce(r.cut, r.n);
    continue when v_pre <= r.seen;
    v_out := v_out || jsonb_build_array(jsonb_build_object('account_id', r.account_id, 'week', v_wk, 'seen', v_pre,
      'rows', coalesce((select jsonb_agg(op || jsonb_build_object('seq', seq) order by seq) from public.econ_ops
                         where account_id = r.account_id and week = v_wk and seq < v_pre), '[]'::jsonb)));
    exit when jsonb_array_length(v_out) >= v_lim;
  end loop;
  return v_out;
end $$;
revoke all on function public.econ_replay_claim(int) from public, anon, authenticated;
grant execute on function public.econ_replay_claim(int) to service_role;

-- 回写：[{account_id, week, seen, result:{upto, bad_at, why, assets, progress, income, fp}}]。只往前走（seen 不倒退）。
create or replace function public.econ_replay_done(p_items jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare it jsonb; r jsonb; n int := 0;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_items');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := it -> 'result';
    continue when jsonb_typeof(r) <> 'object' or (it ->> 'account_id') is null;
    insert into public.econ_state as s (account_id, week, seen, upto, bad_at, why, assets, progress, income, fp, updated_at)
      values ((it ->> 'account_id')::uuid, (it ->> 'week')::bigint, (it ->> 'seen')::int,
              coalesce((r ->> 'upto')::int, 0), coalesce((r ->> 'bad_at')::int, -1), coalesce(r ->> 'why', ''),
              coalesce(r -> 'assets', '{}'), coalesce(r -> 'progress', '{}'), coalesce(r -> 'income', '{}'),
              coalesce(r ->> 'fp', ''), now())
      on conflict (account_id, week) do update
        set seen = excluded.seen, upto = excluded.upto, bad_at = excluded.bad_at, why = excluded.why,
            assets = excluded.assets, progress = excluded.progress, income = excluded.income, fp = excluded.fp,
            updated_at = now()
        where s.seen <= excluded.seen;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;
revoke all on function public.econ_replay_done(jsonb) from public, anon, authenticated;
grant execute on function public.econ_replay_done(jsonb) to service_role;

-- 一组装备的规整串：每件「id|星」排序后逗号连（不看 chg 等其它键；星 1.0 与 1 同一个）
create or replace function public.econ_items_key(p_items jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ',' order by k), '')
    from (select (x ->> 'id') || '|' || coalesce(round((x ->> 'star')::numeric)::int, 1)::text as k
            from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) x
           where jsonb_typeof(x) = 'object') t
$$;
-- 快照里小将身上的装备（top / bottom 两路全部小将；空的不算）⇒ 每只一串、排序后分号连
create or replace function public.econ_snapshot_minions_key(p_snap jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(m -> 'equips') as k
            from jsonb_each(case when jsonb_typeof(p_snap -> 'minions') = 'object' then p_snap -> 'minions' else '{}'::jsonb end) l,
                 jsonb_array_elements(case when jsonb_typeof(l.value) = 'array' then l.value else '[]'::jsonb end) m) t
   where k <> ''
$$;
-- 重放结果里小将那一份（assets.minions = 每只一个 JSON 串 {"eq": [...], "lv": n}）⇒ 同一种规整串
create or replace function public.econ_state_minions_key(p_assets jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(case when jsonb_typeof(m) = 'string' then (m #>> '{}')::jsonb else m end -> 'eq') as k
            from jsonb_array_elements(case when jsonb_typeof(p_assets -> 'minions') = 'array' then p_assets -> 'minions' else '[]'::jsonb end) m) t
   where k <> ''
$$;

-- ③ 开局比对。null = 对得上（或开关关着）；否则回拒收原因（客户端：pending ⇒ 先传流水再自动重交；mismatch / invalid ⇒ 按服务器流水对齐）
create or replace function public.econ_check(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_n int; s public.econ_state%rowtype; v_found boolean; v_a jsonb; v_p jsonb; v_pid text; v_what text := '';
begin
  if not public.referee_econ_on() then
    return null;
  end if;
  select count(*)::int into v_n from public.econ_ops where account_id = p_uid and week = p_week;
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  v_found := found;
  if v_n > 0 and (not v_found or s.seen < v_n) then
    return jsonb_build_object('ok', false, 'reason', 'econ_pending', 'have', case when v_found then s.seen else 0 end, 'need', v_n);
  end if;
  if v_found and s.bad_at >= 0 then
    return jsonb_build_object('ok', false, 'reason', 'econ_invalid', 'at', s.bad_at, 'why', s.why);
  end if;
  v_a := case when v_found then s.assets else '{}'::jsonb end;     -- 一条流水都没有 = 本周开局(全空)
  v_p := case when v_found then s.progress else '{}'::jsonb end;
  if coalesce(round((p_snap ->> 'season_level')::numeric)::int, 1) <> coalesce(round((v_a ->> 'lv')::numeric)::int, 1) then
    v_what := 'lv';
  elsif coalesce(round((p_snap ->> 'axe_exp_total')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 1)::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'axe_stage')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 2)::numeric)::int, 0)
     or coalesce(p_snap ->> 'axe_final', '') <> coalesce(v_a -> 'axe' ->> 3, '') then
    v_what := 'axe';
  elsif coalesce((p_snap ->> 'chest_treasure_value')::numeric, 0) <> coalesce((v_p ->> 'cv')::numeric, 0)
     or coalesce(p_snap -> 'chest_treasures_won', '[]'::jsonb) <> coalesce(v_p -> 'cw', '[]'::jsonb) then
    v_what := 'chest';
  elsif coalesce(round((p_snap ->> 'incense_marks')::numeric)::int, 0) <> coalesce(round((v_p ->> 'im')::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'incense_charge')::numeric)::int, 0) <> coalesce(round((v_p ->> 'ic')::numeric)::int, 0) then
    v_what := 'incense';
  elsif public.econ_snapshot_minions_key(p_snap) <> public.econ_state_minions_key(v_a) then
    v_what := 'minions';
  else
    for v_pid in select jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' else '[]'::jsonb end) loop
      if public.econ_items_key(p_snap -> 'equipped' -> v_pid) <> public.econ_items_key(v_a -> 'worn' -> v_pid) then
        v_what := 'worn:' || v_pid;
        exit;
      end if;
    end loop;
  end if;
  if v_what <> '' then
    return jsonb_build_object('ok', false, 'reason', 'econ_mismatch', 'what', v_what);
  end if;
  return null;
end $$;
revoke all on function public.econ_check(uuid, bigint, jsonb) from public, anon, authenticated;

-- ④ 认了服务器那一份之后把第 N 条起作废（只能截在服务器判出来的那一条上）
create or replace function public.econ_truncate(p_week bigint, p_at int) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid := auth.uid(); s public.econ_state%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  select * into s from public.econ_state where account_id = uid and week = p_week for update;
  if not found or s.bad_at < 0 or s.bad_at is distinct from p_at then
    return jsonb_build_object('ok', false, 'reason', 'not_invalid');
  end if;
  delete from public.econ_ops where account_id = uid and week = p_week and seq >= p_at;
  update public.econ_state set seen = p_at, bad_at = -1, why = '', updated_at = now() where account_id = uid and week = p_week;
  return jsonb_build_object('ok', true, 'next', p_at);
end $$;
revoke all on function public.econ_truncate(bigint, int) from public, anon;
grant execute on function public.econ_truncate(bigint, int) to authenticated;

-- ⑤ 积分赛开局（以 20261101d 版为底逐字照抄，只改标了 2026-11-06 的两处）
create or replace function public.referee_ranked_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; led jsonb; v_b int; ex record; v_key text;
        pk jsonb; jid bigint; mid uuid; st text; v_snap_a jsonb; v_snap_b jsonb; v_meta jsonb;
        v_econ jsonb;   -- 2026-11-06 局外经济记账
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_ranked_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false)
     or coalesce(public.semver_arr(v_cv), array[0, 0, 0, 0]) < public.semver_arr(public.ranked_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week is distinct from extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.ranked_window_open(p_week) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  -- 有一场在算 ⇒ 回那一场（不再建）
  select * into ex from public.referee_jobs
   where kind = 'ranked' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', public.ranked_ledger_peek(uid, p_week));
  end if;
  led := public.ranked_ledger_peek(uid, p_week);
  v_b := (led ->> 'battles')::int;
  -- = 主菜单 _battle_block_msg：出局（0 命）/ 配额满；回账本让客户端对齐
  if (led ->> 'hearts')::int <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'eliminated', 'ledger', led);
  end if;
  if (led ->> 'used')::int >= public.ranked_quota() then
    return jsonb_build_object('ok', false, 'reason', 'quota_full', 'ledger', led);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机账与服务端对不上 ⇒ 回账本，客户端以它为准）
  if p_match_no is distinct from v_b then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'ledger', led);
  end if;
  -- ★2026-11-06 局外经济记账(方案书 20261106 §4.5 S4b; 开关 econ_on 关着 ⇒ econ_check 回 null, 这里一字不变):
  --   快照里的身上装备 / 大轮等级 / 小木斧 / 宝箱 / 香火必须 = 服务器按流水重放的结果; 回账本让客户端照旧对齐
  v_econ := public.econ_check(uid, p_week, p_snapshot);
  if v_econ is not null then
    return v_econ || jsonb_build_object('ledger', led);
  end if;
  -- 账本落行（切换那一周第一次开战：从旧自报快照补种；新的一周：0 场满命）
  insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used, seeded)
    values (p_week, uid, v_b, (led ->> 'wins')::int, (led ->> 'hearts')::int, (led ->> 'sweeps')::int,
            (led ->> 'eggs')::int, (led ->> 'used')::int, led ->> 'seeded')
    on conflict (season_week, account_id) do nothing;
  v_snap_a := public.ranked_stamp_snapshot(p_snapshot, led, v_b);
  v_key := format('ranked:%s:%s:%s', p_week, uid, v_b);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', led);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta -> 'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta ->> 'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
      end if;
      v_snap_b := pk -> 'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk ->> 'opp', 'pick', pk ->> 'pick');
      update public.referee_jobs set b_account = (pk ->> 'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = v_cv,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then v_snap_a else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(v_snap_a) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('ranked', v_key, p_week, v_cv, public.referee_new_seed(), uid, (pk ->> 'account')::uuid,
      v_snap_a, pk -> 'snap', public.referee_level_of(v_snap_a),
      jsonb_build_object('account', uid, 'battles0', v_b, 'opp', pk ->> 'opp', 'pick', pk ->> 'pick',
                         'rules_ver', v_rv, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk -> 'snap'), 'ledger', led);
end $$;
revoke all on function public.referee_ranked_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_ranked_start(bigint, jsonb, int, text, int) to authenticated;

-- ⑤ 周六进队（以 20261027 版为底逐字照抄，只改标了 2026-11-06 的两处）
create or replace function public.gauntlet_queue_join(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; v_gw int := 0; v_gl int := 0;
        ex record; v_id bigint;
        v_econ jsonb;   -- 2026-11-06 局外经济记账
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.gauntlet_window_open(p_week) then
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
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    select id into v_id from public.gauntlet_queue where job_id = ex.job_id and account_id = uid order by id desc limit 1;
    if v_id is not null then
      return public.gauntlet_queue_view(v_id) || jsonb_build_object('in_flight', true);
    end if;
    return jsonb_build_object('ok', true, 'status', 'paired', 'in_flight', true, 'gw', v_gw, 'gl', v_gl,
      'waited_sec', 0, 'job_id', ex.job_id, 'match_id', ex.match_id, 'job_status', ex.status,
      'side', case when ex.a_account = uid then 'a' else 'b' end,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end));
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- ★2026-11-06 局外经济记账(同 referee_ranked_start 那一处)
  v_econ := public.econ_check(uid, p_week, p_snapshot);
  if v_econ is not null then
    return v_econ || jsonb_build_object('gw', v_gw, 'gl', v_gl);
  end if;
  -- 我自己那条心跳断了的旧 waiting ⇒ expired（重新排、重新计时）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where season_week = p_week and account_id = uid and status = 'waiting'
     and last_seen < now() - make_interval(secs => public.gauntlet_queue_ttl_sec());
  insert into public.gauntlet_queue (season_week, account_id, gw, gl, rules_ver, client_version, snapshot)
    values (p_week, uid, v_gw, v_gl, v_rv, v_cv, p_snapshot)
    on conflict (season_week, account_id) where status = 'waiting' do update
      set gw = excluded.gw, gl = excluded.gl, rules_ver = excluded.rules_ver, client_version = excluded.client_version,
          snapshot = excluded.snapshot, last_seen = now(), updated_at = now()
    returning id into v_id;
  perform public.gauntlet_queue_advance(v_id);
  return public.gauntlet_queue_view(v_id);
end $$;
revoke all on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) to authenticated;
-- <<< END econ_state 20261106c <<<
