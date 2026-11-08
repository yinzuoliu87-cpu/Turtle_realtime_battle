-- >>> BEGIN econ_ops 20261106 >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济流水上服务器（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.2 / §4.4 · S3）
--   用户 11-06「装备要改成伏击机装了，这个要做。」（伏击机装 = 服务器记账）
--   改之前：深海币 / 背包 / 身上装备 / 货架 / 卡池 / 大轮等级 / 小木斧 / 糖果罐全在客户端存档里，快照自报 ⇒ 改存档 = 直接抢钱
--     （擂台赛押的是主站真币、严格零和）。客户端 S1 / S2 已把每一笔都记成流水（scripts/gamedata/econ_ledger.gd）。
-- 本段（★纯新增：新表 + 两个新函数，不改任何现行函数 / 表 ⇒ 执行本段不改变任何现行行为）：
--   ① econ_ops：每人每周的流水，(账号, 周, 序号) 为主键、只能追加。src = client（客户端传上来的）/ server（服务器发种子时写下的那一条）。
--     客户端只读自己的行；写只经 econ_commit（security definer），没有 insert / update 策略。
--   ② econ_commit(周, 起始序号, 操作数组, 种类)：一次往返做两件事 ——
--     a. 上传：起始序号必须接在已有的后面（拒断号）；已有的那几条（重传）必须与原来一致；服务器写下的种子行 ⇒ 种类与种子必须一致
--        （一致就把客户端那一份整条换上去：多出来的 bt 等字段补齐，src 仍记 server）。
--     b. 要种子（种类 = roll / refresh / candy）：只发在「紧接着已上传流水的下一条」，发的同时把这一条写进流水 ⇒ 这一笔就算发生了。
--        ★防「挑种子」：每个序号只有一个种子（同一序号再要 ⇒ 回原来那个，重试幂等）；不能预先要后面的种子再倒过来安排前面的操作。
--        ★拿到种子却没用上（闪退）⇒ 服务器账上照样发生，本机下次对齐时按服务器的来（S4）。
--   周 = 服务器当下这一周（app_now 的周一 00:00 UTC，与客户端 week_anchor_utc 同一个口径）；不是这一周的一律 'week'（回服务器的周）。
-- ─────────────────────────────────────────────────────────────

create table if not exists public.econ_ops (
  account_id  uuid        not null references auth.users(id) on delete cascade,
  week        bigint      not null,
  seq         int         not null check (seq >= 0 and seq < 50000),
  op          jsonb       not null,
  src         text        not null default 'client' check (src in ('client', 'server')),
  created_at  timestamptz not null default now(),
  primary key (account_id, week, seq)
);
alter table public.econ_ops enable row level security;
drop policy if exists econ_ops_self on public.econ_ops;
create policy econ_ops_self on public.econ_ops for select using (auth.uid() = account_id);
-- 写只有 econ_commit（security definer），没有 insert / update / delete 策略

-- 服务器当下这一周（周一 00:00 UTC 的 unix 秒）
create or replace function public.econ_week_now() returns bigint
language sql stable security definer set search_path = public as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
revoke all on function public.econ_week_now() from public, anon, authenticated;

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
-- <<< END econ_ops 20261106 <<<
