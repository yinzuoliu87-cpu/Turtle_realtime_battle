-- >>> BEGIN econ_facts 20261106e >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账 · 收入核服务器账本 + 标脏领活（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 · S4b）
--   用户 11-06「装备要改成伏击机装了，这个要做。」（伏击机装 = 服务器记账）
--   20261106c 已上内测服，本段是它之后的改动：
--   ① econ_state 加 dirty：有新流水没重放（领活只看它，不每 2 秒聚合全表）
--   ② econ_prefix：可重放的前缀 = 到第一条「服务器发了种子、客户端还没传回带 bt」之前；econ_check 比到它（闪退留下的尾部种子行不再卡开局）
--   ③ econ_facts：本周服务器账本的事实（只汇总、不含游戏规则；规则常量全在 EconReplay.check_income，服务器不抄第二份），领活时带上；
--      收入超过账本 ⇒ 重放当场判那一条不合法（从那条起作废），走 econ_invalid，不另设拒收原因
--   ④ econ_check 多比统领、宝箱值允许 0.01 误差（小数经 JSON 往返末位会变）
--   开关 econ_on 关着 ⇒ econ_check 恒回 null，开局行为一字不变。
-- ─────────────────────────────────────────────────────────────
alter table public.econ_state add column if not exists dirty boolean not null default false;   -- 有新流水没重放
create index if not exists econ_state_dirty_idx on public.econ_state (week, updated_at) where dirty;

-- ② 可重放的前缀 = 到第一条「服务器写下的种子行、客户端还没传回」之前（那一条缺 bt，重放时场次戳是错的）。种子行只可能在尾部：
--   服务器只给紧接着的下一条发种子，客户端不传回它就传不了后面的。
create or replace function public.econ_prefix(p_uid uuid, p_week bigint) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(min(seq) filter (where src = 'server' and not (op ? 'bt')), count(*))::int
    from public.econ_ops where account_id = p_uid and week = p_week
$$;
revoke all on function public.econ_prefix(uuid, bigint) from public, anon, authenticated;

-- 流水一动就标脏（econ_commit 不用改；领活不扫全表）
create or replace function public.econ_ops_touch() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.econ_state (account_id, week, dirty)
    select distinct account_id, week, true from new_rows
    on conflict (account_id, week) do update set dirty = true;
  return null;
end $$;
revoke all on function public.econ_ops_touch() from public, anon, authenticated;
drop trigger if exists econ_ops_touch_ins on public.econ_ops;
create trigger econ_ops_touch_ins after insert on public.econ_ops
  referencing new table as new_rows for each statement execute function public.econ_ops_touch();
drop trigger if exists econ_ops_touch_upd on public.econ_ops;
create trigger econ_ops_touch_upd after update on public.econ_ops
  referencing new table as new_rows for each statement execute function public.econ_ops_touch();

-- 本周服务器账本的事实，重放（EconReplay.check_income）拿它核流水里的收入。★只汇总，不含游戏规则。
--   ranked：ranked_records 那一行。gauntlet / finals：这个号算完的裁判局（配对局 B 方取 coins_b / chest_b / incense_b、胜负取反；
--   旧路任务的 b_account 是被打的那份快照的主人，不是在场的人 ⇒ 不算）。chest / incense：每一局结束时的结果单。
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
           result -> case when is_a then 'incense' else 'incense_b' end as incense
      from j
  )
  select jsonb_build_object(
    'ranked', coalesce((select jsonb_build_object('n', r.battles, 'w', r.wins, 'coins', r.coins, 'used', r.used)
                          from public.ranked_records r where r.season_week = p_week and r.account_id = p_uid),
                       '{"n":0,"w":0,"coins":0,"used":0}'::jsonb),
    'gauntlet', jsonb_build_object('n', count(*) filter (where kind = 'gauntlet'),
                                   'w', count(*) filter (where kind = 'gauntlet' and won),
                                   'minted', coalesce(sum(minted) filter (where kind = 'gauntlet'), 0)),
    'finals', jsonb_build_object('n', count(*) filter (where kind = 'finals'),
                                 'w', count(*) filter (where kind = 'finals' and won),
                                 'minted', coalesce(sum(minted) filter (where kind = 'finals'), 0)),
    'chest', coalesce(jsonb_agg(chest) filter (where jsonb_typeof(chest) = 'object'), '[]'::jsonb),
    'incense', coalesce(jsonb_agg(incense) filter (where jsonb_typeof(incense) = 'object'), '[]'::jsonb))
    from m
$$;
revoke all on function public.econ_facts(uuid, bigint) from public, anon, authenticated;

-- 领活：只看标脏的号。每次给整份前缀 + 事实（一周几百条，纯计算）。领走时碰一下 updated_at：算不出来的号排到后面，不堵别人。
create or replace function public.econ_replay_claim(p_limit int default 20) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_wk bigint := public.econ_week_now(); v_out jsonb := '[]'::jsonb; r record; v_pre int;
        v_lim int := greatest(1, least(coalesce(p_limit, 20), 200));
begin
  for r in
    select s.account_id, s.seen from public.econ_state s
     where s.week = v_wk and s.dirty order by s.updated_at
  loop
    v_pre := public.econ_prefix(r.account_id, v_wk);
    if v_pre <= r.seen then
      update public.econ_state set dirty = false where account_id = r.account_id and week = v_wk;   -- 只多了一条没传回的种子行
      continue;
    end if;
    update public.econ_state set updated_at = now() where account_id = r.account_id and week = v_wk;
    v_out := v_out || jsonb_build_array(jsonb_build_object('account_id', r.account_id, 'week', v_wk, 'seen', v_pre,
      'facts', public.econ_facts(r.account_id, v_wk),
      'rows', coalesce((select jsonb_agg(op || jsonb_build_object('seq', seq) order by seq) from public.econ_ops
                         where account_id = r.account_id and week = v_wk and seq < v_pre), '[]'::jsonb)));
    exit when jsonb_array_length(v_out) >= v_lim;
  end loop;
  return v_out;
end $$;
revoke all on function public.econ_replay_claim(int) from public, anon, authenticated;
grant execute on function public.econ_replay_claim(int) to service_role;

-- 回写：[{account_id, week, seen, result:{upto, bad_at, why, assets, progress, income, fp}}]。只往前走（seen 不倒退）；
--   算的时候又来了新流水 ⇒ 仍是脏的，下一轮再领。
create or replace function public.econ_replay_done(p_items jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare it jsonb; r jsonb; n int := 0; v_uid uuid; v_wk bigint; v_seen int;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_items');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := it -> 'result';
    continue when jsonb_typeof(r) <> 'object' or (it ->> 'account_id') is null;
    v_uid := (it ->> 'account_id')::uuid;
    v_wk := (it ->> 'week')::bigint;
    v_seen := (it ->> 'seen')::int;
    insert into public.econ_state as s (account_id, week, seen, upto, bad_at, why, assets, progress, income, fp, dirty, updated_at)
      values (v_uid, v_wk, v_seen,
              coalesce((r ->> 'upto')::int, 0), coalesce((r ->> 'bad_at')::int, -1), coalesce(r ->> 'why', ''),
              coalesce(r -> 'assets', '{}'), coalesce(r -> 'progress', '{}'), coalesce(r -> 'income', '{}'),
              coalesce(r ->> 'fp', ''), public.econ_prefix(v_uid, v_wk) > v_seen, now())
      on conflict (account_id, week) do update
        set seen = excluded.seen, upto = excluded.upto, bad_at = excluded.bad_at, why = excluded.why,
            assets = excluded.assets, progress = excluded.progress, income = excluded.income, fp = excluded.fp,
            dirty = excluded.dirty, updated_at = now()
        where s.seen <= excluded.seen;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;
revoke all on function public.econ_replay_done(jsonb) from public, anon, authenticated;
grant execute on function public.econ_replay_done(jsonb) to service_role;

-- ③ 开局比对。null = 对得上（或开关关着）；否则回拒收原因（客户端：pending ⇒ 先传流水再自动重交；mismatch / invalid ⇒ 按服务器流水对齐）
create or replace function public.econ_check(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pre int; s public.econ_state%rowtype; v_found boolean; v_a jsonb; v_p jsonb; v_pid text; v_what text := '';
begin
  if not public.referee_econ_on() then
    return null;
  end if;
  -- ★比到「可重放的前缀」：尾部那条没传回的种子行（闪退，方案书 R9）不算没追上，否则客户端传无可传、永远 pending
  v_pre := public.econ_prefix(p_uid, p_week);
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  v_found := found;
  if v_pre > 0 and (not v_found or s.seen < v_pre) then
    return jsonb_build_object('ok', false, 'reason', 'econ_pending', 'have', case when v_found then s.seen else 0 end, 'need', v_pre);
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
  elsif abs(coalesce((p_snap ->> 'chest_treasure_value')::numeric, 0) - coalesce((v_p ->> 'cv')::numeric, 0)) > 0.01   -- 小数经 JSON 往返末位会变
     or coalesce(p_snap -> 'chest_treasures_won', '[]'::jsonb) <> coalesce(v_p -> 'cw', '[]'::jsonb) then
    v_what := 'chest';
  elsif coalesce(round((p_snap ->> 'incense_marks')::numeric)::int, 0) <> coalesce(round((v_p ->> 'im')::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'incense_charge')::numeric)::int, 0) <> coalesce(round((v_p ->> 'ic')::numeric)::int, 0) then
    v_what := 'incense';
  elsif public.econ_snapshot_minions_key(p_snap) <> public.econ_state_minions_key(v_a) then
    v_what := 'minions';
  else
    for v_pid in select jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' else '[]'::jsonb end) loop
      if not coalesce(v_a -> 'leaders', '[]'::jsonb) ? v_pid then
        v_what := 'leader:' || v_pid;     -- 本大轮锁定的统领里没有它
        exit;
      end if;
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
  update public.econ_state set seen = p_at, bad_at = -1, why = '', dirty = false, updated_at = now() where account_id = uid and week = p_week;
  return jsonb_build_object('ok', true, 'next', p_at);
end $$;
revoke all on function public.econ_truncate(bigint, int) from public, anon;
grant execute on function public.econ_truncate(bigint, int) to authenticated;
-- <<< END econ_facts 20261106e <<<
