-- >>> BEGIN finals_scores 20261012 >>>
-- ─────────────────────────────────────────────────────────────
-- 周日对阵图比分（2026-10-12 · 方案书 docs/plans/20261012-对阵图对照参考改版.md §二）
--   用户：「要做」（比分）。参考 01 VALORANT / 07 Brawlhalla 每条名字旁都有比分。
--   一场 = 上路 + 下路(1:1 再打终极) ⇒ 比分只有 2:0 / 2:1 ⇒ 只存「败方赢了几路」(0/1)。
-- 三件事，全是添加：
--   ① finals_results 加列 loser_lanes（null = 没报 / 轮空 / 旧数据）
--   ② finals_report_score：补报比分。只认 seed 与已采纳的那份(seed_used)相同的报 ——
--      周日两边各打各的（P9「两边都赢」），另一份的比分对不上采纳的胜负，不许写进来。
--   ③ finals_view / finals_week_view 多下发 'scores'（与 done 同一道可见性：当前轮不下发）。
--      ③ 的函数体取自生产库 pg_get_functiondef（2026-10-12），只在原样基础上加 'scores'。
-- ★重复执行安全（if not exists / create or replace）。不删任何数据。
-- ─────────────────────────────────────────────────────────────

alter table public.finals_results add column if not exists loser_lanes smallint;
alter table public.finals_results drop constraint if exists finals_results_loser_lanes;
alter table public.finals_results add constraint finals_results_loser_lanes
  check (loser_lanes is null or loser_lanes in (0, 1));

create or replace function public.finals_report_score(p_week bigint, p_bucket int, p_round int,
    p_match int, p_seed bigint, p_loser_lanes int)
returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null or p_loser_lanes not in (0, 1) or coalesce(p_seed, 0) = 0 then
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

CREATE OR REPLACE FUNCTION public.finals_view(p_week bigint, p_bucket integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b record; ents jsonb; res jsonb; sc jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★p_bucket < 0 = 「我那个桶」。客户端并不知道自己被分到哪个桶(分桶是服务端做的),
  --   分成两次往返去问会出现「查到桶号、桶却没了」的中间态, 所以并到这一次里。
  if p_bucket < 0 then
    select e.bucket_no into p_bucket from public.finals_entrants e
     where e.season_week = p_week and e.account_id = auth.uid()
       and e.bucket_no <> public.finals_cup_no()   -- ★冠军杯赛 2026-10-07: 「我那个组」只认小组赛
     limit 1;
    if p_bucket is null then
      -- ★★2026-09-25: 「没资格」与「有资格但人不够、赛没开起来」**必须分开说**。
      --   `finals_seat` 对 1 个人会**故意不建桶**(一人一桶 = 没有对手的冠军, 那不是比赛),
      --   于是那个人在 `finals_pending` 里有行、在 `finals_entrants` 里没有 ⇒ 原来一律
      --   返回 `not_entered`, 客户端照它说「周六闯关赛晋级才进得来」——
      --   **而他明明晋级了**(周六 4 胜), 屏幕在告诉他一件假事, 他会以为胜场没算。
      --   10 个人规模下这不是假想: 晋级率约 34% ⇒ 只有 0~1 人晋级的概率约 10%。
      --   ⇒ 报过名就回 `too_few` 并带上**本周报名人数**, 让客户端能说人话。
      if exists (select 1 from public.finals_pending
                  where season_week = p_week and account_id = auth.uid()) then
        -- ★2026-10-04: 本周还一个桶都没有 = 还没到分组时间(finals_seat 周日 08:00 UTC 起跑), 不是人太少。
        --   原来这里一律回 too_few ⇒ 周日早上每个晋级的人都被劝「人太少、下周再来」。
        if not exists (select 1 from public.finals_buckets where season_week = p_week) then
          return jsonb_build_object('ok', false, 'reason', 'not_seated',
            'entered', (select count(*) from public.finals_pending where season_week = p_week));
        end if;
        return jsonb_build_object('ok', false, 'reason', 'too_few',
          'entered', (select count(*) from public.finals_pending where season_week = p_week));
      end if;
      return jsonb_build_object('ok', false, 'reason', 'not_entered');
    end if;
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('seed', seed, 'name', name,
           'account_id', account_id) order by seed), '[]'::jsonb)
    into ents from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket;
  -- ★★只取 round < 当前轮 —— 当前轮的结果**根本不下发**。
  -- ★但桶**收盘之后就没有「当前轮」了**: round 停在最后一轮, 于是 `r.round < b.round`
  --   会把决赛结果自己永久挡掉 ⇒ **冠军永远不公布**。收盘了就全给。
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
    into res from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  -- ★2026-10-12 比分(败方赢了几路 0/1 ⇒ 2:0 / 2:1): 与 done 同一道可见性(当前轮不下发)
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes)
           filter (where r.loser_lanes is not null), '{}'::jsonb)
    into sc from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)。客户端按它算开播窗口。
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻: 客户端拿这个倒计时, 不必知道「一轮多长」
    'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
    'now', extract(epoch from now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res, 'scores', sc);
end $function$;

CREATE OR REPLACE FUNCTION public.finals_week_view(p_week bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bs jsonb; cp jsonb; cup int := public.finals_cup_no();
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           -- ★2026-10-07 实时观赛: 开播窗口要两个时刻(没收盘: round_at = 上一轮翻面; 收盘: 只有 revealed_at)
           'round_at', extract(epoch from b.round_at)::bigint,
           'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
           'entrants', (select coalesce(jsonb_agg(jsonb_build_object(
                           'seed', e.seed, 'name', e.name, 'account_id', e.account_id)
                         order by e.seed), '[]'::jsonb)
                          from public.finals_entrants e
                         where e.season_week = p_week and e.bucket_no = b.bucket_no),
           'done', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)),
           'scores', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes) filter (where r.loser_lanes is not null), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)))
         order by b.bucket_no), '[]'::jsonb)
    into bs from public.finals_buckets b
   where b.season_week = p_week
     and b.bucket_no <> cup;               -- ★冠军杯赛 2026-10-07: 杯不进组列表
  -- ★冠军杯赛 2026-10-07: 杯那一张(多一个 next_at, 选手在杯里打要倒计时)。
  select jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           'round_at', extract(epoch from b.round_at)::bigint,
           'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
           'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
           'entrants', (select coalesce(jsonb_agg(jsonb_build_object(
                           'seed', e.seed, 'name', e.name, 'account_id', e.account_id)
                         order by e.seed), '[]'::jsonb)
                          from public.finals_entrants e
                         where e.season_week = p_week and e.bucket_no = b.bucket_no),
           'done', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)),
           'scores', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes) filter (where r.loser_lanes is not null), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)))
    into cp from public.finals_buckets b
   where b.season_week = p_week and b.bucket_no = cup;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from now())::bigint, 'buckets', bs, 'cup', cp);
end $function$;
-- <<< END finals_scores 20261012 <<<
