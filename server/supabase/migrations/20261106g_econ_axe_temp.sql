-- >>> BEGIN econ_axe_temp 20261106g >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账 · 认识服务器局的斧头经验与临时等级（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md）
--   今天查出的两个服务器局缺口修好之后，记账要跟上：
--   ① econ_facts 多回 axe.kills（结果单 axe_kills / axe_kills_b 的合计）：流水里的 axe_exp 按它核，不再一律不认
--   ② econ_check 多比临时等级器：统领 temp_levels、小将 temp_lv（快照现在带这两样，裁判会用）
--   开关 econ_on 关着 ⇒ econ_check 恒回 null，开局行为一字不变。
-- ─────────────────────────────────────────────────────────────
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
    'finals', jsonb_build_object('n', count(*) filter (where kind = 'finals'),
                                 'w', count(*) filter (where kind = 'finals' and won),
                                 'minted', coalesce(sum(minted) filter (where kind = 'finals'), 0)),
    'axe', jsonb_build_object('kills', coalesce(sum(axe_kills), 0)),
    'chest', coalesce(jsonb_agg(chest) filter (where jsonb_typeof(chest) = 'object'), '[]'::jsonb),
    'incense', coalesce(jsonb_agg(incense) filter (where jsonb_typeof(incense) = 'object'), '[]'::jsonb))
    from m
$$;
revoke all on function public.econ_facts(uuid, bigint) from public, anon, authenticated;

-- 小将那一份的规整串多带临时等级（装备串 @ 等级）：临时等级器用在小将身上也要比
create or replace function public.econ_snapshot_minions_key(p_snap jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(m -> 'equips') || '@' || coalesce(round((m ->> 'temp_lv')::numeric)::int, 0)::text as k
            from jsonb_each(case when jsonb_typeof(p_snap -> 'minions') = 'object' then p_snap -> 'minions' else '{}'::jsonb end) l,
                 jsonb_array_elements(case when jsonb_typeof(l.value) = 'array' then l.value else '[]'::jsonb end) m) t
   where k <> '@0'
$$;
create or replace function public.econ_state_minions_key(p_assets jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(j -> 'eq') || '@' || coalesce(round((j ->> 'lv')::numeric)::int, 0)::text as k
            from (select case when jsonb_typeof(m) = 'string' then (m #>> '{}')::jsonb else m end as j
                    from jsonb_array_elements(case when jsonb_typeof(p_assets -> 'minions') = 'array' then p_assets -> 'minions' else '[]'::jsonb end) m) s) t
   where k <> '@0'
$$;

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
      if coalesce(round((p_snap -> 'temp_levels' ->> v_pid)::numeric)::int, 0) <> coalesce(round((v_a -> 'tl' ->> v_pid)::numeric)::int, 0) then
        v_what := 'temp:' || v_pid;       -- 临时等级器: 报的和流水不一样
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
-- <<< END econ_axe_temp 20261106g <<<
