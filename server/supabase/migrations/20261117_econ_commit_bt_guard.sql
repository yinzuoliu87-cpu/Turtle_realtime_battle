-- >>> BEGIN econ_commit_bt_guard 20261117 >>>
-- ─────────────────────────────────────────────────────────────
-- 收流水时拒收「场次戳超过本周服务器总场次」的流水（2026-11-17 · 用户「这肯定 bug 呀！…赶紧解决呀」）
--   现象：iPad 号这周一场没打，一开战就「装备已同步，请重新开战」，背包冒出 4 件装备 + 6 深海币，再开战又同步、又没了，循环。
--   查实：客户端开着跨了周一 0 点，周一 15:48 把上周 339 条（bt 1~22）按本周周号补传（EconNet.week() 取现在的周）；
--     服务器收进本周 ⇒ 重放第 0 条 bt:over ⇒ 整周作废；客户端对齐（econ_truncate 没生效）又拿回这批旧流水在本机重放 ⇒ 循环。
--   本段：econ_commit 原样照抄（以 20261106 版为底），只在第一遍校验里加一道：新流水的 bt > 本周总场次 ⇒ 回 mismatch（why = bt_over）。
--     客户端对 mismatch 本来就「按服务器那份账对齐」（referee_run.gd _econ_then → EconNet.adopt_async(-1)）⇒ 旧客户端不用改就能自己恢复。
--   客户端根因（EconNet.week() 用流水所属的周）随下一版修。
-- 回滚：换回 20261106 版 econ_commit（schema.sql 里 BEGIN econ_ops 20261106 那段）。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.econ_commit(p_week bigint, p_from int, p_ops jsonb, p_kind text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_wk   bigint := public.econ_week_now();
  v_next int;
  v_n    int;
  v_i    int;
  v_op   jsonb;
  v_row  public.econ_ops%rowtype;
  v_at   int;
  v_seed bigint;
  v_cap  numeric;   -- 2026-11-17: 本周服务器记的总场次(积分赛 + 闯关 + 决赛); 新流水的 bt 不许超过它
  v_f    jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  if p_week is distinct from v_wk then
    return jsonb_build_object('ok', false, 'reason', 'week', 'week', v_wk);
  end if;
  if p_ops is null or jsonb_typeof(p_ops) <> 'array' or p_from is null then
    return jsonb_build_object('ok', false, 'reason', 'bad_ops');
  end if;
  v_n := jsonb_array_length(p_ops);
  if v_n > 500 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;
  if p_kind is not null and p_kind not in ('roll', 'refresh', 'candy') then
    return jsonb_build_object('ok', false, 'reason', 'bad_kind');
  end if;
  perform pg_advisory_xact_lock(hashtext('econ_commit:' || v_uid::text));   -- 同一个号的提交排队(两台设备同时传)
  select coalesce(max(seq) + 1, 0) into v_next from public.econ_ops where account_id = v_uid and week = v_wk;
  if p_from < 0 or p_from > v_next then
    return jsonb_build_object('ok', false, 'reason', 'gap', 'next', v_next);
  end if;
  if p_from + v_n >= 50000 then
    return jsonb_build_object('ok', false, 'reason', 'full', 'next', v_next);
  end if;
  -- a. 上传。★两遍: 先全部校验 / 比对(一个字不写), 全过才写 —— 返回错误不会回滚已经插进去的行(检查脚本 A6 抓到过「整批不落」被破)
  for v_i in 0 .. v_n - 1 loop
    v_op := p_ops -> v_i;
    v_at := p_from + v_i;
    if jsonb_typeof(v_op) <> 'object' or length(v_op::text) > 4000 or coalesce(v_op ->> 'op', '') = '' then
      return jsonb_build_object('ok', false, 'reason', 'bad_op', 'at', v_at, 'next', v_next);
    end if;
    -- 2026-11-17: 新流水的场次戳超过服务器本周记的总场次 ⇒ 不收(回 mismatch: 客户端按服务器那份账对齐、丢掉本机这批)。
    --   起因: 客户端开着跨了周一 0 点, 把上周没传完的流水按新一周的周号补传(EconNet.week() 取的是现在的周),
    --   服务器收进本周 ⇒ 重放第一条就 bt:over ⇒ 整周作废; 客户端对齐时又拿回那批旧流水 ⇒ 每次开战都「装备已同步」(11-17 iPad 号)。
    --   重放本来就判这种流水不合法(econ_replay.gd check_facts bt:over), 这里只是提前到收的时候拒, 不让它进账。
    if v_at >= v_next and coalesce((v_op ->> 'bt')::numeric, 0) > 0 then
      if v_cap is null then
        v_f := public.econ_facts(v_uid, v_wk);
        v_cap := coalesce((v_f -> 'ranked' ->> 'n')::numeric, 0) + coalesce((v_f -> 'gauntlet' ->> 'n')::numeric, 0)
               + coalesce((v_f -> 'finals' ->> 'n')::numeric, 0);
      end if;
      if (v_op ->> 'bt')::numeric > v_cap then
        return jsonb_build_object('ok', false, 'reason', 'mismatch', 'why', 'bt_over', 'at', v_at, 'next', v_next);
      end if;
    end if;
    if v_at < v_next then
      select * into v_row from public.econ_ops where account_id = v_uid and week = v_wk and seq = v_at;
      if v_row.src = 'server' then
        if (v_op ->> 'op') is distinct from (v_row.op ->> 'op') or (v_op ->> 'seed') is distinct from (v_row.op ->> 'seed') then
          return jsonb_build_object('ok', false, 'reason', 'mismatch', 'at', v_at, 'next', v_next);
        end if;
      elsif v_row.op is distinct from v_op then
        return jsonb_build_object('ok', false, 'reason', 'mismatch', 'at', v_at, 'next', v_next);
      end if;
    end if;
  end loop;
  for v_i in 0 .. v_n - 1 loop
    v_op := p_ops -> v_i;
    v_at := p_from + v_i;
    if v_at < v_next then
      -- 服务器写下的种子行: 种类与种子已核对过 ⇒ 换成客户端那一份(补齐 bt 等), 仍记 server
      update public.econ_ops set op = v_op
        where account_id = v_uid and week = v_wk and seq = v_at and src = 'server' and op is distinct from v_op;
    else
      insert into public.econ_ops (account_id, week, seq, op, src) values (v_uid, v_wk, v_at, v_op, 'client');
    end if;
  end loop;
  v_next := greatest(v_next, p_from + v_n);
  if p_kind is null then
    return jsonb_build_object('ok', true, 'next', v_next);
  end if;
  -- b. 要种子: 发在客户端眼里的「下一条」(= p_from + v_n)
  v_at := p_from + v_n;
  if v_at < v_next then
    -- 这个序号已经有了: 是我先前发给这一种的种子(请求超时重试)⇒ 原样再回; 否则这个位置已经是别的操作
    select * into v_row from public.econ_ops where account_id = v_uid and week = v_wk and seq = v_at;
    if v_row.src = 'server' and (v_row.op ->> 'op') = p_kind then
      return jsonb_build_object('ok', true, 'seq', v_at, 'seed', (v_row.op ->> 'seed')::bigint, 'again', true, 'next', v_next);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'taken', 'at', v_at, 'next', v_next);
  end if;
  v_seed := ('x' || lpad(substr(md5(gen_random_uuid()::text), 1, 8), 16, '0'))::bit(64)::bigint;   -- 0 .. 2^32-1
  insert into public.econ_ops (account_id, week, seq, op, src)
    values (v_uid, v_wk, v_at, jsonb_build_object('op', p_kind, 'seed', v_seed), 'server');
  return jsonb_build_object('ok', true, 'seq', v_at, 'seed', v_seed, 'next', v_at + 1);
end $$;
revoke all on function public.econ_commit(bigint, int, jsonb, text) from public, anon;
grant execute on function public.econ_commit(bigint, int, jsonb, text) to authenticated;
-- <<< END econ_commit_bt_guard 20261117 <<<
