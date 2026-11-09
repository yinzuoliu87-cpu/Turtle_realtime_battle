-- >>> BEGIN econ_wheel 20261109d >>>
-- ─────────────────────────────────────────────────────────────
-- 赌神命运之轮跨场层数进记账（2026-11-09 · 方案书 20261107-龟战主站对接 §4.6「补命运之轮记账」、
--   20261106-装备与深海币服务器记账 状态行待办「gambler_wheel_stacks 是快照自报、不经记账口」）
--   现状：一大轮内累积的花色只在快照里自报（Backend.build_ghost_snapshot 的 wheel_stacks），裁判照单全收 ⇒ 改存档就能多拿层数；
--   偷袭押的是龟币，固定阵容的强弱直接决定输赢（§4.9）。
--   做法：服务器本来就有每一局的结果单（0.22.8 起带 wheel_new / wheel_new_b，20261106h），累加就是这个号本周应有的层数，
--   不另开一条流水（同一件事记两份必然漂移）：
--   ① econ_wheel_sum(账号, 周)：本周已算完的周赛局里这个号自己抽到的花色合计。口径同 econ_facts：A 方一律算；B 方只在
--      B 是在场真人那几种（决赛、闯关配对局）算 —— 积分赛的 B 是别人的快照，那一局抽到的不归快照主人。偷袭局不算
--      （偷袭不发任何东西，20261109c）。
--   ② 触发器 econ_wheel_stamp_on_claim（BEFORE：任务变成 claimed 的那一句 update，同 20261109b pet_stamp_on_claim）：
--      记账开关 econ_on 开着时，任务 meta 记 a_wheel / b_wheel = 双方的 econ_wheel_sum；裁判（referee_job.gd state_for）
--      拿它给快照自报的层数**封顶**（每种花色取较小值）。封顶而不是覆盖：积分赛的 B 是旧快照，快照之后快照主人又抽到的不该算进去；
--      本人没收到某局结果（关了 App）时自报偏少，与现状一样、不会因此变多。
--      账号为空（机器人池）那一侧不盖 ⇒ 快照原样（服务器自己造的快照）。
--   开关 econ_on 关着 ⇒ 不盖章，开局行为一字不变；偷袭只在 econ_on 开着时开（raid_enabled），所以偷袭局一定有章。
--   快照本身一个字不改（决赛坏快照回退拿任务快照逐字比，见 20261109b ⑤）。
-- 回滚：drop trigger econ_wheel_stamp_on_claim on public.referee_jobs（裁判见不到 a_wheel / b_wheel ⇒ 照快照）。
-- ★重复执行安全（create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.econ_wheel_sum(p_uid uuid, p_week bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(t.k, t.n), '{}'::jsonb)
    from (
      select e.key as k, sum(least(greatest(round((e.value #>> '{}')::numeric), 0), 99))::int as n
        from public.referee_jobs j
        cross join lateral jsonb_each(
          case when jsonb_typeof(j.result -> case when j.a_account = p_uid then 'wheel_new' else 'wheel_new_b' end) = 'object'
               then j.result -> case when j.a_account = p_uid then 'wheel_new' else 'wheel_new_b' end
               else '{}'::jsonb end) e
       where p_uid is not null and j.season_week = p_week and j.status = 'done' and j.result is not null
         and j.kind in ('ranked', 'gauntlet', 'finals')
         and (j.a_account = p_uid or (j.b_account = p_uid and (j.kind = 'finals' or j.meta ->> 'pair' = 'true')))
         and e.key in ('spade', 'heart', 'diamond', 'club') and jsonb_typeof(e.value) = 'number'
       group by e.key
    ) t
   where t.n > 0
$$;
revoke all on function public.econ_wheel_sum(uuid, bigint) from public, anon, authenticated;

create or replace function public.econ_wheel_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.referee_econ_on() then
    new.meta := coalesce(new.meta, '{}'::jsonb) - 'a_wheel' - 'b_wheel';
    if new.a_account is not null then
      new.meta := new.meta || jsonb_build_object('a_wheel', public.econ_wheel_sum(new.a_account, new.season_week));
    end if;
    if new.b_account is not null then
      new.meta := new.meta || jsonb_build_object('b_wheel', public.econ_wheel_sum(new.b_account, new.season_week));
    end if;
  end if;
  return new;
end $$;
revoke all on function public.econ_wheel_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists econ_wheel_stamp_on_claim on public.referee_jobs;
create trigger econ_wheel_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.econ_wheel_stamp_on_claim();
-- <<< END econ_wheel 20261109d <<<
