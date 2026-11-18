-- >>> BEGIN raid_void_closes_job 20261118 >>>
-- ─────────────────────────────────────────────────────────────
-- 作废偷袭时顺手关掉它的裁判任务（2026-11-18 · 用户「偷袭作废后裁判任务关不关掉？嗯，也行啊…你看着来呗」）
--   现象：内测服 11-11 手动作废的偷袭（raid_void 'manual_test_void'），对应的裁判任务 job 1203 一直 pending，
--     health 检查「积压：最老的任务等了 433721 秒」天天报警（11-16 已手工标 failed）。
--   查实：raid_void 只改 raid_jobs；referee_claim 只领 queued / started 的偷袭局，raid_sweep 也只收这两种 ⇒
--     直接作废一场还没算完的偷袭（运维手动作废）时，那条裁判任务永远 pending。
--     其余几条作废路径不会留下它：raid_create 判无效时还没建任务；bad_result 时任务已 done；裁判失败时任务已 failed。
--   本段：raid_void 原样照抄（以 20261109c 版为底），只多一句：作废成功 ⇒ 它的裁判任务若还在 pending / claimed，标 failed
--     （error = raid_void:<原因>）。改任务会触发 raid_job_status_hook → raid_on_job，那边看到偷袭已 void 直接返回，不会再发一次 settle。
-- 回滚：换回 20261109c 版 raid_void（schema.sql 里 BEGIN raid 20261109c 那段）。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.raid_void(p_id bigint, p_reason text, p_send boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_hit boolean;
begin
  update public.raid_jobs
     set status = 'void', result = 'void', reason = left(coalesce(p_reason, '?'), 200), settled_at = now()
   where id = p_id and status in ('queued', 'started')
  returning * into r;
  v_hit := found;   -- ★下面那句 update 会改写 found，先存下来
  if v_hit then
    -- 2026-11-18：裁判任务还没算完 ⇒ 一起关掉（否则没人领、也没人收，永远 pending）
    update public.referee_jobs
       set status = 'failed', error = left('raid_void:' || coalesce(p_reason, '?'), 200), done_at = now()
     where job_id = r.referee_job_id and kind = 'raid' and status in ('pending', 'claimed');
  end if;
  if v_hit and coalesce(p_send, true) then
    perform public.mainsite_outbox_put('settle', r.raid_id::text,
      jsonb_build_object('raidId', r.raid_id, 'result', 'void', 'matchId', ''));
  end if;
end $$;
revoke all on function public.raid_void(bigint, text, boolean) from public, anon, authenticated;
-- <<< END raid_void_closes_job 20261118 <<<
