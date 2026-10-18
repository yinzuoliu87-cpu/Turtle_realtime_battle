-- 2026-10-18 周日比分: 一路碎蛋 = 1:0(用户原话「一路碎蛋不就是1：0」)
--
-- 碎蛋 = 整场当场结束(用户 2026-07-12), 胜方不一定拿满 2 路。原来 loser_lanes 只能存 0/1
-- (= 2:0 / 2:1), 一路碎蛋的场次客户端算出 -1 就不报 ⇒ 对阵图上那场没有比分。
-- 比分代码(客户端 phase2_duallane.gd 的 SCORE_* 与 score_pair 是同一张表):
--    0 = 2:0    1 = 2:1    -10 = 1:0(上路碎蛋)    -11 = 1:1(下路碎蛋)
-- ★取负数: v0.19.570 及更早的客户端只画 >=0 的比分 ⇒ 老包看到新码是「不画」, 不会画出假的 2:x。
alter table public.finals_results drop constraint if exists finals_results_loser_lanes;
alter table public.finals_results add constraint finals_results_loser_lanes
  check (loser_lanes is null or loser_lanes in (0, 1, -10, -11));

create or replace function public.finals_report_score(p_week bigint, p_bucket int, p_round int,
    p_match int, p_seed bigint, p_loser_lanes int)
returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null or p_loser_lanes not in (0, 1, -10, -11) or coalesce(p_seed, 0) = 0 then
    return false;
  end if;
  if not exists (select 1 from public.finals_entrants
                  where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid()) then
    return false;
  end if;
  update public.finals_results set loser_lanes = p_loser_lanes
   where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = p_match
     and seed_used = p_seed and loser_lanes is null;
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.finals_report_score(bigint, int, int, int, bigint, int) from public, anon;
grant execute on function public.finals_report_score(bigint, int, int, int, bigint, int) to authenticated;
