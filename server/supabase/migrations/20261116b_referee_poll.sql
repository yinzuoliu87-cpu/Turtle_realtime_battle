-- >>> BEGIN referee_poll 20261116b >>>
-- ─────────────────────────────────────────────────────────────
-- 裁判机一次请求问完所有活（2026-11-16 · #23 Supabase 出站流量第三步）
--   用户 11-16「你要合并什么，今天都搞好」。
--   11-10 第二步之后，正式服裁判机空转时仍有三条线程各问各的：比赛线程 referee_claim（6 秒）+ 补流（60 秒）、
--   经济线程 econ_replay_claim（econ_on 开着 6 秒）、发件箱 mainsite_outbox_claim（30 秒）、开关 referee_flags（60 秒）
--   ⇒ 约 3.5 万次 / 天；每次响应头约 900 字节，空转本身就是出站流量的大头。
--
--   referee_poll(工人, 版本, 要不要补流) → {v, jobs, flags, econ, outbox}：
--     · jobs   = referee_claim(工人, 版本, 1)（照旧记心跳、收过期租约）；空了且 p_restream ⇒ 再领一份补流（task = restream）
--     · flags  = referee_flags()（轮询器拿它刷新开关缓存，不再单独读）
--     · econ   = 本周有没有待重放的号（econ_state.dirty）；outbox = 有没有到点该发的龟投消息
--   经济线程 / 发件箱线程看到最近一次合并轮询说「没有」就不自己去问；消息过期（比赛线程都在算长局）才照旧自己问。
--   领活本身仍走原来的 econ_replay_claim / mainsite_outbox_claim（这里只回「有没有」，不领、不改它们的表）。
-- 旧的 referee_claim / referee_claim_restream / referee_flags 不动：旧轮询器照用；新轮询器遇到 404（库里没这个函数）退回分开问。
-- 回滚：drop function public.referee_poll(text, text[], boolean)。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.referee_poll(p_worker text, p_versions text[], p_restream boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_jobs jsonb; v_econ boolean := false; v_outbox boolean := false;
begin
  v_jobs := public.referee_claim(p_worker, p_versions, 1);
  if coalesce(p_restream, false) and jsonb_array_length(v_jobs) = 0 then
    v_jobs := public.referee_claim_restream(p_worker, p_versions, 1);
  end if;
  if to_regclass('public.econ_state') is not null then
    select exists (select 1 from public.econ_state s where s.week = public.econ_week_now() and s.dirty) into v_econ;
  end if;
  if to_regclass('public.mainsite_outbox') is not null then
    select exists (select 1 from public.mainsite_outbox o where o.done_at is null and o.next_at <= now()) into v_outbox;
  end if;
  return jsonb_build_object('v', 1, 'jobs', v_jobs, 'flags', public.referee_flags(), 'econ', v_econ, 'outbox', v_outbox);
end $$;
revoke all on function public.referee_poll(text, text[], boolean) from public, anon, authenticated;
grant execute on function public.referee_poll(text, text[], boolean) to service_role;
-- <<< END referee_poll 20261116b <<<
