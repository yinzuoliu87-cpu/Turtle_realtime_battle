-- >>> BEGIN ranked_ledger_weekend 20261106d >>>
-- ─────────────────────────────────────────────────────────────
-- 积分赛账本周六周日不回给客户端（2026-11-06）
--   服务端账本只有积分赛那几场；周六 / 周日客户端的场次与胜场还含闯关 / 决赛。
--   现行客户端（0.22.7）每次回主菜单都拿账本覆盖本机 ⇒ 探针：周六 17 场 12 胜 → 16 场 11 胜（货架不换货、援军小将场次加成少算）。
--   客户端 0.22.8 起自己不在周末问；本段管 0.22.7（周六 00:00 UTC 起回 {ok:false, reason:weekend}，客户端见 err 什么都不动）。
--   ranked_any_day（内测服彩排）放开星期几，这里同样放开。开战 / 结算自带的账本（referee_ranked_start / referee_complete）不受影响。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_ranked_ledger(p_week bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if public.app_now() >= to_timestamp(p_week + 5 * 86400)
     and not coalesce((select c.ranked_any_day from public.referee_config c where c.id = 1), false) then
    return jsonb_build_object('ok', false, 'reason', 'weekend');
  end if;
  return jsonb_build_object('ok', true, 'week', p_week, 'ledger', public.ranked_ledger_peek(auth.uid(), p_week));
end $$;
revoke all on function public.referee_ranked_ledger(bigint) from public, anon;
grant execute on function public.referee_ranked_ledger(bigint) to authenticated;
-- <<< END ranked_ledger_weekend 20261106d <<<
