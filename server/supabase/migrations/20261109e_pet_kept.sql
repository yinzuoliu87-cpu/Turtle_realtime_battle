-- >>> BEGIN pet_kept 20261109e >>>
-- ─────────────────────────────────────────────────────────────
-- 本周已上场过的统领整周都认（2026-11-09 · 方案书 20261107-龟战主站对接 §4.9「周赛也要服务器把关拥有 ∪ 限免」的漏洞）
--   现状（20261109b + referee_job.gd pets_allowed）：三只统领有一只不在「开算那一刻的拥有 ∪ 本周限免」⇒ 这一方的快照整个不认。
--   统领每周第一次开打就锁死、整周不能换 ⇒ 周中在主站卖掉 / 转走一只拥有的龟，这一周剩下的局全被拒。
--   还有一种更隐蔽：限免 = 固定排序里跳过拥有的前 7 只（weekly_free.gd）⇒ 少了一只拥有的龟，它可能插进限免前 7，
--   把原来第 7 只限免挤出去 —— 那只若是锁定的统领，同样整周被拒（玩家什么都没做错）。
--   做法：本周**已经算完、且当时验过拥有**的周赛局里这个号上场过的统领，本周剩下的局都认（锁定那一刻合法 ⇒ 整周合法）。
--   ① pet_kept_leaders(账号, 周)：本周 done 的周赛局（积分赛 / 闯关 / 决赛；A 方一律，B 方只在决赛与闯关配对局 = 在场真人）
--      里这个号快照的三只统领，去重排序。★只认 meta 里带 <方>_owned 的局（= 20261109b 领活盖过章、裁判按拥有验过），
--      20261109b 之前算的局当时不验拥有（28 只任选），不能当证据。偷袭局不算（阵容就是周赛那一份，偷袭本身不是证据）。
--   ② 触发器 pet_kept_stamp_on_claim（BEFORE：变成 claimed 的那一句 update，同 20261109b ⑤）：meta 记 a_kept / b_kept；
--      账号为空（机器人池）那一侧不盖。裁判 pets_allowed：拥有 ∪ 限免 ∪ kept。
--   不改的：经验仍只发「开算时拥有且现在还拥有」的龟（pet_xp_grant）；等级表仍是拥有的按 pet_levels、其余 1 级（pet_lv_table）
--   ⇒ 卖掉的龟这周照样能上场，按 1 级、不涨经验（与没拥有的限免龟同一个规矩）。
-- 回滚：drop trigger pet_kept_stamp_on_claim on public.referee_jobs（裁判见不到 kept ⇒ 与改之前相同）。
-- ★重复执行安全（create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.pet_kept_leaders(p_uid uuid, p_week bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(t.pid order by t.pid), '[]'::jsonb)
    from (
      select distinct x as pid
        from public.referee_jobs j
        cross join lateral jsonb_array_elements_text(
          case when jsonb_typeof((case when j.a_account = p_uid then j.a_snapshot else j.b_snapshot end) -> 'leaders') = 'array'
               then (case when j.a_account = p_uid then j.a_snapshot else j.b_snapshot end) -> 'leaders'
               else '[]'::jsonb end) x
       where p_uid is not null and j.season_week = p_week and j.status = 'done'
         and j.kind in ('ranked', 'gauntlet', 'finals')
         and ((j.a_account = p_uid and j.meta ? 'a_owned')
              or (j.b_account = p_uid and (j.kind = 'finals' or j.meta ->> 'pair' = 'true') and j.meta ? 'b_owned'))
         and x ~ '^[a-z0-9_]{1,32}$'
    ) t
$$;
revoke all on function public.pet_kept_leaders(uuid, bigint) from public, anon, authenticated;

create or replace function public.pet_kept_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.meta := coalesce(new.meta, '{}'::jsonb) - 'a_kept' - 'b_kept';
  if new.a_account is not null then
    new.meta := new.meta || jsonb_build_object('a_kept', public.pet_kept_leaders(new.a_account, new.season_week));
  end if;
  if new.b_account is not null then
    new.meta := new.meta || jsonb_build_object('b_kept', public.pet_kept_leaders(new.b_account, new.season_week));
  end if;
  return new;
end $$;
revoke all on function public.pet_kept_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists pet_kept_stamp_on_claim on public.referee_jobs;
create trigger pet_kept_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.pet_kept_stamp_on_claim();
-- <<< END pet_kept 20261109e <<<
