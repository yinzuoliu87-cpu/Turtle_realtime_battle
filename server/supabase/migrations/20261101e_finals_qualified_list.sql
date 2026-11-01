-- >>> BEGIN finals_qualified_list 20261101e >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛日：观众看「本周晋级名单」（2026-11-01 · 方案书 docs/plans/20261031c-周日赛事界面重做.md G14「绝不放锁住的按钮」）
--   18:00 UTC finals_seat 把 finals_pending 分组成 finals_entrants 之前，没晋级的观众进对阵图只看到一把锁：
--   finals_view 对没报名的人只回 {ok:false, reason:'not_entered'}（不带人数）、finals_week_view 18:00 前 buckets = []、
--   finals_pending 的 RLS 只许看自己那行 ⇒ 客户端拿不到「几个人晋级、都是谁」。
-- 新增一个只读 RPC（★契约定死，客户端照它写）：
--   finals_qualified_list(p_week) →
--     未登录 ⇒ {ok:false, reason:'not_signed_in'}
--     否则   ⇒ {ok:true, week, now, seated, n, list:[{name, tag, avatar, gw, gl, me}, ...]}
--   · now    = public.app_now() 的 epoch 秒（与现行 finals_view / finals_week_view 同一个钟；内测服假时钟见 20261021）
--   · seated = 本周 finals_buckets 已有行（18:00 已分组 ⇒ 客户端改看 finals_week_view）
--   · n      = 本周 finals_pending 行数（不受下面 256 行上限影响）
--   · list   = 本周 finals_pending，排序与 finals_seat 定种子同一条：gw desc, gl asc, account_id（只排序、不下发）；最多 256 行
--              name = finals_pending.name（改名 / 举报占位会改这一列）；tag / avatar = snapshot.profile 里的，没有给 ''；
--              me = 这一行是不是调用者自己
-- ★取舍（设计原则变更，用户要的观众页内容）：finals_pending 的 RLS 注释写着
--   「只能看见自己那一行: 『谁报名了』本身就是情报」。这次让观众在分组前就看到名单；18:00 之后 finals_week_view
--   本来就把全部组员公开 ⇒ 名单本身只是提前到分组之前可见。
--   只下发 名字 / 玩家 ID（tag）/ 头像 / 闯关战绩；★绝不下发阵容（snapshot —— 周日对手的阵容才是真情报）与 account_id。
--   表上的 RLS 策略不动（直接查表仍只看得到自己那行）；只有本函数（security definer）越过它，且只吐上面这几列。
-- 依赖：finals_pending / finals_buckets（schema.sql 本体 · E-B3 2026-09-23）、app_now（20261021_beta_server_clock）。
--   不改任何已有函数 / 表 / 策略；与 20261101 / 20261101b / 20261101c 互不依赖，先后随意。
-- 回滚：drop function public.finals_qualified_list(bigint);（客户端读不到就照旧显示锁）。★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_qualified_list(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_n int; v_list jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select count(*) into v_n from public.finals_pending where season_week = p_week;
  -- ★只挑这几列：snapshot / account_id 不出这个函数
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', q.name,
           'tag', coalesce(q.snapshot->'profile'->>'tag', ''),
           'avatar', coalesce(q.snapshot->'profile'->>'avatar', ''),
           'gw', q.gw, 'gl', q.gl,
           'me', q.account_id = v_uid)
         order by q.gw desc, q.gl asc, q.account_id), '[]'::jsonb)
    into v_list
    from (select p.name, p.snapshot, p.gw, p.gl, p.account_id
            from public.finals_pending p
           where p.season_week = p_week
           order by p.gw desc, p.gl asc, p.account_id      -- = finals_seat 的种子顺序
           limit 256) q;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from public.app_now())::bigint,
    'seated', exists (select 1 from public.finals_buckets where season_week = p_week),
    'n', v_n, 'list', v_list);
end $$;
revoke all on function public.finals_qualified_list(bigint) from public;
revoke execute on function public.finals_qualified_list(bigint) from anon;
grant execute on function public.finals_qualified_list(bigint) to authenticated;
-- <<< END finals_qualified_list 20261101e <<<
