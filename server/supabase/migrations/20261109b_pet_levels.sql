-- >>> BEGIN pet_levels 20261109b >>>
-- ─────────────────────────────────────────────────────────────
-- 龟等级与经验 + 开算盖章（2026-11-09 · 主站对接工作线 C）
--   方案书 docs/plans/20261107b-龟等级与经验.md（已拍板：1 ~ 10 级；周赛每局上场的自己的龟赢 +8、输 +6；
--   N 级升 N+1 级要 50 + 20N，满级累计 1350；限免龟固定 1 级、不涨、不可升级）、20261107-龟战主站对接.md §4.3 / §4.9、
--   20261105c-主站对接偷袭.md §4.2（按龟等级 R1、等级盖章：裁判开算时按服务器等级表覆盖快照里的 lv）。
--   接口契约（主会话 11-08）：§1 本迁移名、§4 限免与校验。
-- ★依赖 20261109a_mainsite_core（工作线 A1）：mainsite_accounts / mainsite_pets / mainsite_outbox_put（pet-level 只在已绑定、
--   主站返回过这只龟、等级 1 ~ 10 时才真写，由它统一挡）。与 20261109c_raid 互不依赖、先后都行（本段不改 referee_claim）。
--   本段里碰它们的函数一律 plpgsql（建函数时不查表在不在）；运行时缺表 ⇒ 当作「没绑定 / 没拥有」（undefined_table 兜住），
--   不让主站那几张表的上线先后卡住裁判领活或结算。
--
--   ① pet_levels（账号 × 龟：累计经验、等级）/ pet_xp_log（幂等键 = 对局 match_id + 账号 + 龟）：只由本段的函数写，客户端读不到表。
--   ② 曲线：pet_xp_to_reach(等级) / pet_level_for_xp(经验) —— 与客户端 TurtleLevel 同一条（门禁 verify_pet_level_r1 对一遍）。
--   ③ pet_owned(账号)：拥有 = mainsite_pets（主站 /player 的缓存）里、且是我们 28 只之一的龟。没绑定 / 缺表 ⇒ 空。
--   ④ pet_stamp_snapshot(快照, 账号)：开算盖章 —— lv = 三只统领各自的等级（拥有的按 pet_levels，其余 1），快照自报的 lv 作废。
--      没有账号（机器人池）⇒ 全 1 级。
--   ⑤ 触发器 pet_stamp_on_claim（BEFORE：任务变成 claimed 的那一句 update）：两侧快照盖章并**写回任务行**；任务 meta 记
--      a_account / b_account / a_owned / b_owned（这一刻的账号与拥有）⇒ 领活 / 补流回的任务单 key 里都有，裁判按它们算
--      这一侧本周的「拥有 ∪ 限免」（WeeklyFree，种子 = 账号 + 周锚点 key.week）。
--      ★账号和拥有只进 meta、不进快照：matches.left/right_snapshot 所有登录用户都读得到 —— 拥有放进去 = 谁都看得到别人在主站
--        有哪些龟；账号放进去 = 机器人池那一侧没有账号、一眼看出是机器人（用户 10-04「不能让玩家知道是机器人」）。
--      ★「周赛任务的 owned 字段」在这里统一填（积分赛 / 闯关 / 决赛 / 偷袭都经领活这一步），不去改五六个建任务函数。
--   ⑥ pet_xp_grant(对局, 种类, 账号, 快照, 开算时的拥有, 赢了吗)：给这一侧上场的三只统领里「开算时就拥有（meta 里记的）且现在还拥有」
--      的龟发经验；限免龟不发。同一 (match_id, 账号, 龟) 只发一次。升了级且已绑定（mainsite_accounts 有行）⇒ 同一事务写一条
--      pet-level 发件箱（{userId, petKey, level}，幂等键 = 主站用户 + 龟 + 新等级）。
--   ⑦ 触发器 pet_xp_on_job_done：referee_jobs 变成 done（= referee_complete 的那一句 update，同一个事务）且种类是
--      ranked / gauntlet / finals、结果没被顶掉（superseded）⇒ 发经验：A 方一律；B 方只在 B 也是在场真人那几种（决赛、闯关配对局），
--      积分赛的 B 是别人的快照、不是在场的人，不发。偷袭（raid）、切磋、教程都不经这里 ⇒ 不发。
--      ★用触发器而不是改 referee_complete：那个函数 170 多行，偷袭线（20261109c）也要改它；整段重定义会互相顶掉。
--      ★发经验出错只记 warning、不回滚结算（经验晚一点补得上，结算回滚了这一局就要重算）。
--   ⑧ pet_levels_me()（authenticated）：mainsite_me() 那一份（拥有 / 是否绑定）+ levels: {pet_key: {lv, xp}} —— 客户端 PetLevelsNet 一次拿齐。
-- 回滚：drop trigger pet_xp_on_job_done / pet_stamp_on_claim；表与其余函数留着不影响（referee_claim 本段不改）。
-- ★重复执行安全（create if not exists / create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 表
create table if not exists public.pet_levels (
  account_id uuid        not null references public.accounts(account_id) on delete cascade,
  pet_key    text        not null,
  xp         int         not null default 0 check (xp between 0 and 1350),
  level      int         not null default 1 check (level between 1 and 10),
  updated_at timestamptz not null default now(),
  primary key (account_id, pet_key)
);
alter table public.pet_levels enable row level security;
-- 没有任何策略 ⇒ 客户端直连读写都不行；读自己的走 pet_levels_me()

create table if not exists public.pet_xp_log (
  match_id     uuid        not null,
  account_id   uuid        not null references public.accounts(account_id) on delete cascade,
  pet_key      text        not null,
  kind         text        not null,
  won          boolean     not null,
  xp           int         not null,                 -- 这一局实际加了多少（满级封顶后可能是 0）
  level_before int         not null,
  level_after  int         not null,
  created_at   timestamptz not null default now(),
  primary key (match_id, account_id, pet_key)
);
alter table public.pet_xp_log enable row level security;

-- ② 曲线（= TurtleLevel.xp_to_reach / level_for_xp）
create or replace function public.pet_xp_to_reach(p_lv int) returns int
language sql immutable as $$
  select (least(greatest(coalesce(p_lv, 1), 1), 10) - 1) * (50 + 10 * least(greatest(coalesce(p_lv, 1), 1), 10))
$$;
create or replace function public.pet_level_for_xp(p_xp int) returns int
language sql immutable as $$
  select coalesce(max(l), 1)::int from generate_series(1, 10) l
   where public.pet_xp_to_reach(l) <= greatest(coalesce(p_xp, 0), 0)
$$;
revoke all on function public.pet_xp_to_reach(int) from public, anon, authenticated;
revoke all on function public.pet_level_for_xp(int) from public, anon, authenticated;

-- 28 只（= WeeklyFree.ALL = data/pets.json；门禁 verify_pet_level_r1 逐只比）
create or replace function public.pet_all_ids() returns text[]
language sql immutable as $$
  select array['basic', 'stone', 'bamboo', 'angel', 'ice', 'ninja', 'two_head', 'ghost', 'diamond',
               'fortune', 'dice', 'rainbow', 'gambler', 'hunter', 'pirate', 'candy', 'bubble', 'line', 'lightning', 'phoenix',
               'lava', 'cyber', 'crystal', 'chest', 'space', 'hiding', 'headless', 'shell']
$$;
revoke all on function public.pet_all_ids() from public, anon, authenticated;

-- ③ 拥有
create or replace function public.pet_owned(p_account uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare own text[];
begin
  if p_account is null then
    return '{}';
  end if;
  begin
    select coalesce(array_agg(distinct p.pet_key order by p.pet_key), '{}') into own
      from public.mainsite_pets p
     where p.account_id = p_account and p.pet_key = any(public.pet_all_ids());
  exception when undefined_table then
    own := '{}';                       -- 20261109a 还没上 ⇒ 谁都没绑定
  end;
  return coalesce(own, '{}');
end $$;
revoke all on function public.pet_owned(uuid) from public, anon, authenticated;

-- ④ 开算盖章（快照只改 lv；拥有记在任务 meta，见 ⑤）
create or replace function public.pet_stamp_snapshot(p_snap jsonb, p_account uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare own text[]; lv jsonb := '{}'::jsonb; x text; l int;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' then
    return p_snap;
  end if;
  own := public.pet_owned(p_account);
  if jsonb_typeof(p_snap -> 'leaders') = 'array' then
    for x in select distinct e from jsonb_array_elements_text(p_snap -> 'leaders') e where e <> '' loop
      l := 1;
      if x = any(own) then
        select pl.level into l from public.pet_levels pl where pl.account_id = p_account and pl.pet_key = x;
        l := coalesce(l, 1);
      end if;
      lv := lv || jsonb_build_object(x, l);
    end loop;
  end if;
  return p_snap || jsonb_build_object('lv', lv);
end $$;
revoke all on function public.pet_stamp_snapshot(jsonb, uuid) from public, anon, authenticated;

-- ⑤ 领活那一刻盖章（BEFORE 触发器：referee_claim 把任务改成 claimed 的那一句 update，同一行、同一个事务）
--   · 两侧快照的 lv 按服务器等级表重写（盖过章的这一份写回任务行 ⇒ 补流重算 / 录像 matches / 快照池用的都是它，结果可复现）；
--   · 任务 meta 记 a_account / b_account（账号，没有 = null）和 a_owned / b_owned（这一刻的拥有）。领活回的任务单 key = meta ∪ {week, match_key}
--     ⇒ 裁判从 key 里读（RefereeJob.pets_allowed）；补流任务单的 key 同样来自 meta ⇒ 补流重验用的是原来那一刻的。
--   ★用触发器而不是重写 referee_claim：偷袭线（20261109c）也重写了 referee_claim；两份整段重定义谁后执行谁算数，
--     触发器与哪一版 referee_claim 都能一起用，也不改领活的排序 / 过滤。重领（租期过了）会按那一刻的服务器数据再盖一次。
create or replace function public.pet_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.a_snapshot := public.pet_stamp_snapshot(new.a_snapshot, new.a_account);
  new.b_snapshot := public.pet_stamp_snapshot(new.b_snapshot, new.b_account);
  new.meta := coalesce(new.meta, '{}'::jsonb) || jsonb_build_object(
    'a_account', new.a_account, 'b_account', new.b_account,
    'a_owned', to_jsonb(public.pet_owned(new.a_account)), 'b_owned', to_jsonb(public.pet_owned(new.b_account)));
  return new;
end $$;
revoke all on function public.pet_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists pet_stamp_on_claim on public.referee_jobs;
create trigger pet_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.pet_stamp_on_claim();

-- ⑥ 发经验
create or replace function public.pet_xp_grant(p_match uuid, p_kind text, p_account uuid, p_snap jsonb,
    p_owned_then jsonb, p_won boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare own text[]; x text; v_gain int; r record; n int; v_xp int; v_new int; v_uid text; v_out jsonb := '[]'::jsonb;
begin
  if p_match is null or p_account is null or p_won is null or coalesce(p_kind, '') not in ('ranked', 'gauntlet', 'finals') then
    return v_out;                      -- 偷袭 / 切磋 / 教程 / 不认识的种类：不发
  end if;
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' or jsonb_typeof(p_snap -> 'leaders') <> 'array'
     or jsonb_typeof(p_owned_then) is distinct from 'array' then
    return v_out;                      -- 没盖过章（开算时谁拥有不知道）⇒ 一只都不当拥有
  end if;
  v_gain := case when p_won then 8 else 6 end;
  own := public.pet_owned(p_account);
  begin
    select m.mainsite_user_id into v_uid from public.mainsite_accounts m where m.account_id = p_account;
  exception when undefined_table then
    v_uid := null;
  end;
  for x in select distinct e from jsonb_array_elements_text(p_snap -> 'leaders') e where e <> '' order by 1 loop
    -- 限免龟不发：开算时拥有（领活时记进 meta 的）且现在还拥有（mainsite_pets）
    continue when not (x = any(own)) or not (p_owned_then ? x);
    insert into public.pet_levels (account_id, pet_key) values (p_account, x) on conflict do nothing;
    select * into r from public.pet_levels where account_id = p_account and pet_key = x for update;
    v_xp := least(r.xp + v_gain, public.pet_xp_to_reach(10));
    v_new := public.pet_level_for_xp(v_xp);
    insert into public.pet_xp_log (match_id, account_id, pet_key, kind, won, xp, level_before, level_after)
      values (p_match, p_account, x, p_kind, p_won, v_xp - r.xp, r.level, v_new)
      on conflict (match_id, account_id, pet_key) do nothing;
    get diagnostics n = row_count;
    continue when n = 0;               -- 这一局这只龟发过了（幂等）
    update public.pet_levels set xp = v_xp, level = v_new, updated_at = now()
     where account_id = p_account and pet_key = x;
    if v_new > r.level and v_uid is not null then
      perform public.mainsite_outbox_put('pet-level', format('%s:%s:%s', v_uid, x, v_new),
        jsonb_build_object('userId', v_uid, 'petKey', x, 'level', v_new));
    end if;
    v_out := v_out || jsonb_build_object('pet', x, 'xp', v_xp, 'lv', v_new, 'up', v_new > r.level);
  end loop;
  return v_out;
end $$;
revoke all on function public.pet_xp_grant(uuid, text, uuid, jsonb, jsonb, boolean) from public, anon, authenticated;

-- ⑦ 结算即发（referee_complete 那一句 update 同一个事务）
create or replace function public.pet_xp_on_job_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare a_won boolean;
begin
  if new.status <> 'done' or old.status = 'done' or new.kind not in ('ranked', 'gauntlet', 'finals')
     or new.error is not distinct from 'superseded' or coalesce(new.result ->> 'winner', '') not in ('a', 'b') then
    return null;
  end if;
  a_won := new.result ->> 'winner' = 'a';
  begin
    perform public.pet_xp_grant(new.match_id, new.kind, new.a_account, new.a_snapshot, new.meta -> 'a_owned', a_won);
  exception when others then
    raise warning 'pet_xp_grant a job % : %', new.job_id, sqlerrm;
  end;
  if new.b_account is not null
     and (new.kind = 'finals' or (new.kind = 'gauntlet' and coalesce(new.meta ->> 'pair', '') = 'true')) then
    begin
      perform public.pet_xp_grant(new.match_id, new.kind, new.b_account, new.b_snapshot, new.meta -> 'b_owned', not a_won);
    exception when others then
      raise warning 'pet_xp_grant b job % : %', new.job_id, sqlerrm;
    end;
  end if;
  return null;
end $$;
revoke all on function public.pet_xp_on_job_done() from public, anon, authenticated;
drop trigger if exists pet_xp_on_job_done on public.referee_jobs;
create trigger pet_xp_on_job_done after update of status on public.referee_jobs
  for each row when (new.status = 'done' and old.status is distinct from 'done')
  execute function public.pet_xp_on_job_done();

-- ⑧ 客户端读自己的：mainsite_me() 那一份（A1 的 mainsite_status：{ok, linked, user_id, owned, fetched_at}，同一个函数）+ levels。
--   一次请求把「拥有」和「等级」都带回去（Supabase 出站流量 #23）。
create or replace function public.pet_levels_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); st jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  begin
    st := public.mainsite_status(uid);
  exception when undefined_function or undefined_table then
    st := jsonb_build_object('ok', true, 'linked', false, 'user_id', null, 'owned', '[]'::jsonb, 'fetched_at', null);
  end;
  return st || jsonb_build_object('levels', coalesce((select jsonb_object_agg(l.pet_key, jsonb_build_object('lv', l.level, 'xp', l.xp))
                                                        from public.pet_levels l where l.account_id = uid), '{}'::jsonb));
end $$;
revoke all on function public.pet_levels_me() from public, anon;
grant execute on function public.pet_levels_me() to authenticated;
-- <<< END pet_levels 20261109b <<<
