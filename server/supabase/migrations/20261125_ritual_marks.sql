-- >>> BEGIN ritual_marks 20261125 >>>
-- ─────────────────────────────────────────────────────────────
-- 114 仪式匕首【血契】一大轮内跨场累积（2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md §4.2c）
--   用户 11-24「仪式匕首可能要做一个专属的羁绊，就是类似于香火石一样…一个大轮去叠加」。
--   照竹叶龟【生长】（20261119_bamboo_growth）原样做一遍，口径是「这一局新刻了几道」（整数，增量）：
--   ① 回包：裁判结果单 0.23.7 起带 ritual_new / ritual_new_b（这一局双方各新刻了几道血契）；
--      referee_job_status / referee_finals_coins 回给客户端（按视角换好）。以 20261119 版为底逐字照抄，只加标了 2026-11-25 的几行；
--      结果单没这个键（老裁判）⇒ 回包一个键都不多。
--   ② 记账封顶：econ_ritual_sum(账号, 周) = 本周已算完的周赛局里这个号自己刻的合计（口径同 econ_bamboo_sum）；
--      触发器 econ_ritual_stamp_on_claim 在任务变成 claimed 时（econ_on 开着）把 a_ritual / b_ritual 盖进 meta，
--      裁判（referee_job.gd state_for · ritual_cap）给快照自报的封顶。
--   回滚：drop trigger econ_ritual_stamp_on_claim on public.referee_jobs；两个回包函数重跑 20261119_bamboo_growth。
-- ★重复执行安全（create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record; v_won jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    -- ★2026-10-27 在线瑞士轮：配对局里的 B 也能查（只认 meta.pair）。回包按 B 的视角：
    --   胜负取反、战绩取 gw_b / gl_b、铸币取 coins_b、宝箱 / 香火取 chest_b / incense_b ⇒ 客户端记账一行不用改。
    select * into j from public.referee_jobs
     where job_id = p_job_id and b_account = auth.uid() and kind = 'gauntlet' and meta->>'pair' = 'true';
    if not found then
      return jsonb_build_object('ok', false, 'reason', 'no_job');
    end if;
    v_won := j.result->'ledger'->'won';
    return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
      'won', case when jsonb_typeof(v_won) = 'boolean' then to_jsonb(not (v_won #>> '{}')::boolean) end,
      'score', j.result->'ledger'->'score',
      'gw', j.result->'ledger'->'gw_b', 'gl', j.result->'ledger'->'gl_b',
      'coins', j.result->'ledger'->'coins_b',
      'error', case when j.status = 'failed' then j.error end, 'side', 'b')
      || case when j.status = 'done' and jsonb_typeof(j.result->'chest_b') = 'object'
              then jsonb_build_object('chest', j.result->'chest_b') else '{}'::jsonb end
      || case when j.status = 'done' and jsonb_typeof(j.result->'incense_b') = 'object'
              then jsonb_build_object('incense', j.result->'incense_b') else '{}'::jsonb end
      -- ★2026-11-06 B 方斧头的击杀 + 助攻
      || case when j.status = 'done' and jsonb_typeof(j.result->'axe_kills_b') = 'number'
              then jsonb_build_object('axe_kills', j.result->'axe_kills_b') else '{}'::jsonb end
      -- ★2026-11-06 B 方命运之轮新抽到的花色
      || case when j.status = 'done' and jsonb_typeof(j.result->'wheel_new_b') = 'object'
              then jsonb_build_object('wheel_new', j.result->'wheel_new_b') else '{}'::jsonb end
      -- ★2026-11-19 B 方竹叶龟这一局长的最大生命
      || case when j.status = 'done' and jsonb_typeof(j.result->'bamboo_new_b') = 'number'
              then jsonb_build_object('bamboo_new', j.result->'bamboo_new_b') else '{}'::jsonb end
      -- ★2026-11-25 B 方仪式匕首这一局新刻的血契
      || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new_b') = 'number'
              then jsonb_build_object('ritual_new', j.result->'ritual_new_b') else '{}'::jsonb end;
  end if;
  return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
    'won', j.result->'ledger'->'won', 'score', j.result->'ledger'->'score',
    'gw', j.result->'ledger'->'gw', 'gl', j.result->'ledger'->'gl',
    'coins', j.result->'ledger'->'coins',
    'error', case when j.status = 'failed' then j.error end)
    -- 2026-10-22b：这一局结束时我方宝箱龟的进度（财宝值 + 已开战利品）
    || case when j.status = 'done' and jsonb_typeof(j.result->'chest') = 'object'
            then jsonb_build_object('chest', j.result->'chest') else '{}'::jsonb end
    -- 2026-10-23：这一局结束时我方 093 香火石的刻痕 + 充能
    || case when j.status = 'done' and jsonb_typeof(j.result->'incense') = 'object'
            then jsonb_build_object('incense', j.result->'incense') else '{}'::jsonb end
    -- ★2026-11-06：这一局我方斧头的击杀 + 助攻
    || case when j.status = 'done' and jsonb_typeof(j.result->'axe_kills') = 'number'
            then jsonb_build_object('axe_kills', j.result->'axe_kills') else '{}'::jsonb end
    -- ★2026-11-06：这一局我方命运之轮新抽到的花色
    || case when j.status = 'done' and jsonb_typeof(j.result->'wheel_new') = 'object'
            then jsonb_build_object('wheel_new', j.result->'wheel_new') else '{}'::jsonb end
    -- ★2026-11-19：这一局我方竹叶龟长的最大生命
    || case when j.status = 'done' and jsonb_typeof(j.result->'bamboo_new') = 'number'
            then jsonb_build_object('bamboo_new', j.result->'bamboo_new') else '{}'::jsonb end
    -- ★2026-11-25：这一局我方仪式匕首新刻的血契
    || case when j.status = 'done' and jsonb_typeof(j.result->'ritual_new') = 'number'
            then jsonb_build_object('ritual_new', j.result->'ritual_new') else '{}'::jsonb end
    -- 2026-10-27：配对局多回一个 side（旧路任务一个键都不多）
    || case when j.kind = 'gauntlet' and j.meta->>'pair' = 'true' then jsonb_build_object('side', 'a') else '{}'::jsonb end
    -- 2026-11-01：积分赛局（周六 / 周日的回包一个键都不多）
    || case when j.kind = 'ranked' then jsonb_build_object('kind', 'ranked')
              || case when j.status = 'done' and jsonb_typeof(j.result->'ledger'->'ranked') = 'object'
                      then jsonb_build_object('ranked', j.result->'ledger'->'ranked') else '{}'::jsonb end
              || case when j.status in ('claimed', 'done') then jsonb_build_object('seed', j.seed) else '{}'::jsonb end
            else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null; inc jsonb := null; ak jsonb := null; wn jsonb := null; bn jsonb := null; rn jsonb := null;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  -- 不剧透：与 finals_view 同一条（结果行在、且那一轮已翻面）
  if not exists (select 1 from public.finals_results r
                  where r.season_week = p_week and r.bucket_no = p_bucket and r.round = p_round and r.match_no = p_match)
     or not (b.closed or p_round < b.round) then
    return jsonb_build_object('ok', true, 'status', 'pending');
  end if;
  select * into j from public.referee_jobs
   where match_key = format('finals:%s:%s:%s:%s', p_week, p_bucket, p_round, p_match);
  if not found then
    return jsonb_build_object('ok', true, 'status', 'done', 'coins', 0);    -- 没有裁判局（轮空 / 兜底判）
  end if;
  if j.a_account is distinct from uid and j.b_account is distinct from uid then
    return jsonb_build_object('ok', false, 'reason', 'not_in_match');
  end if;
  if j.status = 'done' and j.error is null then          -- superseded = 结果被兜底抢先写了，这一局不是正式那一局
    v := j.result->'ledger'->(case when j.a_account = uid then 'coins' else 'coins_b' end);
    if jsonb_typeof(v) = 'number' and (v #>> '{}')::numeric between 0 and 999 then
      c := floor((v #>> '{}')::numeric)::int;
    end if;
    -- 2026-10-22b：A 取 chest、B 取 chest_b（侧由服务端认，不是客户端报）
    ch := j.result->(case when j.a_account = uid then 'chest' else 'chest_b' end);
    -- 2026-10-23：A 取 incense、B 取 incense_b（同上）
    inc := j.result->(case when j.a_account = uid then 'incense' else 'incense_b' end);
    -- ★2026-11-06：A 取 axe_kills、B 取 axe_kills_b（同上）
    ak := j.result->(case when j.a_account = uid then 'axe_kills' else 'axe_kills_b' end);
    -- ★2026-11-06：A 取 wheel_new、B 取 wheel_new_b（同上）
    wn := j.result->(case when j.a_account = uid then 'wheel_new' else 'wheel_new_b' end);
    -- ★2026-11-19：A 取 bamboo_new、B 取 bamboo_new_b（同上）
    bn := j.result->(case when j.a_account = uid then 'bamboo_new' else 'bamboo_new_b' end);
    -- ★2026-11-25：A 取 ritual_new、B 取 ritual_new_b（同上）
    rn := j.result->(case when j.a_account = uid then 'ritual_new' else 'ritual_new_b' end);
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end
    || case when jsonb_typeof(inc) = 'object' then jsonb_build_object('incense', inc) else '{}'::jsonb end
    || case when jsonb_typeof(ak) = 'number' then jsonb_build_object('axe_kills', ak) else '{}'::jsonb end
    || case when jsonb_typeof(wn) = 'object' then jsonb_build_object('wheel_new', wn) else '{}'::jsonb end
    || case when jsonb_typeof(bn) = 'number' then jsonb_build_object('bamboo_new', bn) else '{}'::jsonb end
    || case when jsonb_typeof(rn) = 'number' then jsonb_build_object('ritual_new', rn) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;

create or replace function public.econ_ritual_sum(p_uid uuid, p_week bigint) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(least(greatest(floor((j.result ->> t.k)::numeric), 0), 150)), 0)
    from public.referee_jobs j
    cross join lateral (select case when j.a_account = p_uid then 'ritual_new' else 'ritual_new_b' end as k) t
   where p_uid is not null and j.season_week = p_week and j.status = 'done' and j.result is not null
     and j.kind in ('ranked', 'gauntlet', 'finals')
     and (j.a_account = p_uid or (j.b_account = p_uid and (j.kind = 'finals' or j.meta ->> 'pair' = 'true')))
     and jsonb_typeof(j.result -> t.k) = 'number'
$$;
revoke all on function public.econ_ritual_sum(uuid, bigint) from public, anon, authenticated;

create or replace function public.econ_ritual_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.referee_econ_on() then
    new.meta := coalesce(new.meta, '{}'::jsonb) - 'a_ritual' - 'b_ritual';
    if new.a_account is not null then
      new.meta := new.meta || jsonb_build_object('a_ritual', public.econ_ritual_sum(new.a_account, new.season_week));
    end if;
    if new.b_account is not null then
      new.meta := new.meta || jsonb_build_object('b_ritual', public.econ_ritual_sum(new.b_account, new.season_week));
    end if;
  end if;
  return new;
end $$;
revoke all on function public.econ_ritual_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists econ_ritual_stamp_on_claim on public.referee_jobs;
create trigger econ_ritual_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.econ_ritual_stamp_on_claim();
-- <<< END ritual_marks 20261125 <<<
