-- >>> BEGIN ranked_pick_seed_fallback 20261124b >>>
-- ─────────────────────────────────────────────────────────────
-- 积分赛挑对手: 种子快照只在同场次没有真人 / 陪练账号快照时垫底（2026-11-24）
--   用户 11-24「陪练号没有自己的背包，为啥啊？什么叫陪练号？不都是真实的账号吗？…跟玩家一样的去购买…合成…装备」
--   → 选「只在没真账号时垫底」。取代 10-08「从全部同场次快照里等概率抽」里把内置种子(ranked_pool kind=seed)算进去那一半。
--   种子 = 事先模拟生成的阵容, 不是账号、没有背包(援军小将可抽装备是派生的); 296 个陪练账号铺满各场次后不再需要与真账号混抽。
--   这两周真人积分赛 73 局对真账号快照 / 53 局对种子。
-- 改动: referee_ranked_pick 第 ① 步排序 `random()` → `(pick = 'seed'), random()`; 其余逐字照 20261101d / 20261106c 版。
--   同场次有真人 / 陪练账号候选(排除本周碰过的之后)⇒ 只从它们里等概率抽; 一份都没有 ⇒ 种子里等概率抽; 再没有 ⇒ 机器人(不变)。
-- ★只改一个函数的排序; 不改表、不改签名、不改权限。重复执行安全。
-- 回滚: 重新执行 schema.sql 里上一版 referee_ranked_pick(20261106c 段)。
-- ─────────────────────────────────────────────────────────────

create or replace function public.referee_ranked_pick(p_uid uuid, p_week bigint, p_battles int, p_rules_ver int,
    p_ex text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare c record; bp record; bk int; snap jsonb;
begin
  select * into c from (
    select format('acct:%s:b%s', g.account_id, g.battles) as opp, g.account_id as account, g.snapshot as snap, 'human' as pick
      from public.ghosts g
     where g.season_week = p_week and g.battles = p_battles and g.rules_ver = p_rules_ver
       and g.account_id <> p_uid and public.referee_ranked_ghost_ok(g.snapshot, p_battles)
    union all
    select format('seed:%s:%s:%s', p.rules_ver, p.battles, p.variant), null::uuid, p.snapshot, 'seed'
      from public.ranked_pool p
     where p.rules_ver = p_rules_ver and p.kind = 'seed' and p.battles = p_battles
       and public.referee_lanes_ok(p.snapshot)
       and jsonb_typeof(p.snapshot -> 'season_total_battles') = 'number'
       and (p.snapshot ->> 'season_total_battles')::numeric = p_battles
  ) cand
  where not (cand.opp = any(coalesce(p_ex, '{}')))
  order by (cand.pick = 'seed'), random()   -- 20261124b: 真人 / 陪练账号在前, 种子只垫底(同一类里仍等概率)
  limit 1;
  if found then
    return jsonb_build_object('snap', c.snap - 'origin', 'opp', c.opp, 'pick', c.pick)
      || case when c.account is not null then jsonb_build_object('account', c.account) else '{}'::jsonb end;
  end if;
  select max(battles) into bk from public.ranked_pool where rules_ver = p_rules_ver and kind = 'bot';
  if bk is null then
    return null;
  end if;
  bk := least(greatest(coalesce(p_battles, 0), 0), bk);
  select p.* into bp from public.ranked_pool p
   where p.rules_ver = p_rules_ver and p.kind = 'bot' and p.battles = bk
   order by (format('bot:%s:%s:%s', p.rules_ver, p.battles, p.variant) = any(coalesce(p_ex, '{}'))), random()
   limit 1;
  if not found then
    return null;
  end if;
  snap := bp.snapshot - 'origin';
  if coalesce(p_battles, 0) > bk then
    snap := jsonb_set(snap, '{season_total_battles}', to_jsonb(p_battles));   -- 场次标签与玩家相同（用户 10-04「场次一定要相同」）
  end if;
  return jsonb_build_object('snap', snap, 'opp', format('bot:%s:%s:%s', bp.rules_ver, bp.battles, bp.variant), 'pick', 'bot');
end $$;
revoke all on function public.referee_ranked_pick(uuid, bigint, int, int, text[]) from public, anon, authenticated;
-- <<< END ranked_pick_seed_fallback 20261124b <<<
