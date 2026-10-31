-- 20261101 决赛日开播一场接一场 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：
--   · 本机：python tools/sb_migrate.py sandbox 20261101_finals_sequential_premiere
--   · 内测服 / 正式服：python tools/sb_migrate.py beta|prod --rehearse 20261101_finals_sequential_premiere
--     ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、组、任务、改的开关与时钟一个都不留。
-- 时间：本事务里把 service_env 改成 beta、删掉 server_clock_prod_zero 约束（回滚即还原），用偏移把 app_now() 拨到
--   「真实时间所在那一周 + 3 周」的周日 18:00 起（那一周没有任何真实数据）。
-- 裁判结果走真路：referee_enqueue_finals 建任务 → 改成已领 → referee_complete 写回（steps 进 result，结果行 seed_used = 任务种子）。
-- 判据（每条配分母 / 对照）：
--   G0 分母：购物窗内不建任务；购物窗一关建出 3 份（组 0 两场、组 1 一场 + 一场轮空）
--   F1 翻面闸 = 备战结束 + 60 秒且真实场次结果齐：239 秒不翻；241 秒结果齐的组翻、没齐的组等；结果一到下一次推进就翻
--   S1 ★小组赛同一轮同时：组 0 两场开播都 = 翻面时刻、时长 ceil(steps/60)+30
--   S2 组 0：下一轮 round_at = 翻面 + 最长那场 + 25 = premiere_until；revealed_at = 翻面时刻
--   S3 组 1：轮空那一场不排档期；真实那一场 = 翻面时刻
--   N1 下一轮备战没开之前（round_at 在将来）：对手快照回 shop_open、不建下一轮的任务；到了 round_at + 180 才建
--   V1 finals_view.seq：v / until / p 两场的 [开播, 揭晓]；当前轮的档期不下发（插一行当前轮假档期也看不见）
--   V1 seq.settle_at = 备战结束时刻；V2 finals_week_view：每组都带 seq，组 1 只有一场；老键都还在，next_at = round_at + 240
--   C1 收盘那一轮：决赛也排档期、premiere_until = 决赛结束 + 25；seq.p 含决赛
--   K1 冠军杯赛成表：有组「收盘了但档期没播完」⇒ 等（对照：播完了 ⇒ 成表 4 人）；★杯内一场接一场（第 2 场 = 第 1 场结束 + 25）
--   O1 开关关（finals_sequential = false）⇒ 老规则：480 秒才翻、next_at = round_at + 480、round_at = 翻面时刻、premiere_until / premiere_at 都是 null、seq = null
--   O2 裁判关 ⇒ finals_sequential_on() = false（结果由客户端报的老路不排档期）
--   B1 兜底判（3 倍时长后 side 0、seed_used = 0）的那一场不排档期；steps 异常大 ⇒ 一场封顶 600 + 30
--   P  权限：三个内部函数客户端调不了；finals_view / finals_week_view 仍给 authenticated
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ctx as
  select extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint + 3 * 604800 as wk,
         gen_random_uuid() as viewer;
create temp table _t (k text primary key, ts timestamptz);
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ctx to public;
grant all on _t to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
create or replace function pg_temp.wk() returns bigint language sql as $$ select wk from _ctx $$;
-- 假时间 = 那一周周日 18:00 UTC + p_sec 秒（向上取整到整秒：now() 带小数秒）
create or replace function pg_temp.at(p_sec int) returns void language plpgsql as $$
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (to_timestamp(pg_temp.wk() + 6 * 86400 + 18 * 3600 + p_sec) - now())))::bigint where id = 1;
end $$;
-- 记一个时刻 / 取一个时刻
create or replace function pg_temp.mark(p_k text, p_ts timestamptz) returns void language sql as $$
  insert into _t (k, ts) values (p_k, p_ts) on conflict (k) do update set ts = excluded.ts
$$;
create or replace function pg_temp.t(p_k text) returns timestamptz language sql as $$ select ts from _t where k = p_k $$;
create or replace function pg_temp.e(p_ts timestamptz) returns bigint language sql as $$ select extract(epoch from p_ts)::bigint $$;
create or replace function pg_temp.snap(p_name text) returns jsonb language sql as $$
  select jsonb_build_object('leaders', jsonb_build_array('basic', 'stone', 'bamboo'),
    'lane_assign', jsonb_build_object('top', jsonb_build_array('basic', 'stone'), 'bottom', jsonb_build_array('bamboo')),
    'profile', jsonb_build_object('name', p_name, 'avatar', 'basic', 'id', 'g_' || p_name), 'season_level', 5)
$$;
-- 建一个 n 人组（第 1 轮，round_at = 此刻假时间）；人从 _ppl 里按顺序取
create temp table _ppl (i serial primary key, id uuid not null);
grant all on _ppl to public;
create or replace function pg_temp.bucket(p_b int, p_n int, p_first int) returns void language sql as $$
  insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
    select pg_temp.wk(), p_b, p.i - p_first, p.id, 'p' || p.i, pg_temp.snap('p' || p.i)
      from _ppl p where p.i between p_first and p_first + p_n - 1;
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
    values (pg_temp.wk(), p_b, p_n, 1, public.app_now(), false);
$$;
create or replace function pg_temp.key(p_b int, p_r int, p_m int) returns text language sql as $$
  select format('finals:%s:%s:%s:%s', pg_temp.wk(), p_b, p_r, p_m)
$$;
-- 裁判写回（真路：先改成已领，再 referee_complete）
create or replace function pg_temp.finish(p_b int, p_r int, p_m int, p_steps int) returns text language plpgsql as $$
declare j record; r jsonb;
begin
  update public.referee_jobs set status = 'claimed', claimed_by = 'chk', claimed_at = now()
   where match_key = pg_temp.key(p_b, p_r, p_m) returning * into j;
  if not found then
    return 'no_job';
  end if;
  r := public.referee_complete(j.job_id, 'chk', jsonb_build_object('ok', true, 'match_id', j.match_id::text,
         'seed', j.seed, 'client_version', j.client_version, 'winner', 'a', 'steps', p_steps,
         'score_code', 1, 'replay_b64', 'QUJD'));
  return coalesce(r->>'ok', 'null');
end $$;
create or replace function pg_temp.bk(p_b int) returns public.finals_buckets language sql as $$
  select * from public.finals_buckets where season_week = pg_temp.wk() and bucket_no = p_b
$$;
create or replace function pg_temp.res(p_b int, p_r int, p_m int) returns public.finals_results language sql as $$
  select * from public.finals_results where season_week = pg_temp.wk() and bucket_no = p_b and round = p_r and match_no = p_m
$$;
create or replace function pg_temp.jobs(p_round int) returns int language sql as $$
  select count(*)::int from public.referee_jobs where season_week = pg_temp.wk() and kind = 'finals'
     and (meta->>'round')::int = p_round
$$;
create or replace function pg_temp.view(p_b int) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user((select viewer from _ctx));
  v := public.finals_view(pg_temp.wk(), p_b);
  perform pg_temp.as_user(null);
  return v;
end $$;
create or replace function pg_temp.wview() returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user((select viewer from _ctx));
  v := public.finals_week_view(pg_temp.wk());
  perform pg_temp.as_user(null);
  return v;
end $$;

-- ── 造数据：内测服口径的时钟（本事务内）、裁判开、16 个号 + 1 个观众 ──
update public.service_env set env = 'beta' where id = 1;
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.referee_config set finals_on = true, finals_version = '9.9.9', finals_sequential = true where id = 1;
insert into public.referee_versions (client_version, enabled) values ('9.9.9', true)
  on conflict (client_version) do update set enabled = true;
insert into _ppl (id) select gen_random_uuid() from generate_series(1, 16);
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _ppl
  union all select viewer, 'authenticated', 'authenticated', true, now() from _ctx;

select pg_temp.ck('分母: finals_sequential_on() = true（裁判开 + 开关默认开）', public.finals_sequential_on());

-- ── 组 0（4 人）/ 组 1（3 人：第 1 轮一场轮空），周日 18:00 坐定 ──
select pg_temp.at(0);
select pg_temp.bucket(0, 4, 1);
select pg_temp.bucket(1, 3, 5);
select pg_temp.mark('T0', public.app_now());

-- G0
select pg_temp.at(100);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('G0 分母: 购物窗内不建任务', pg_temp.jobs(1) = 0, pg_temp.jobs(1)::text);
select pg_temp.at(200);
select pg_temp.ck('G0 分母: 购物窗一关 finals_advance 建任务、不推（没到备战结束 + 60）', public.finals_advance(pg_temp.wk()) = 0);
select pg_temp.ck('G0 分母: 建出 3 份任务（组 0 两场 + 组 1 一场；轮空不建）', pg_temp.jobs(1) = 3, pg_temp.jobs(1)::text);
select pg_temp.ck('G0 组 0 两份裁判写回 ok（组 1 那一份先不写回）',
  pg_temp.finish(0, 1, 0, 6000) = 'true' and pg_temp.finish(0, 1, 1, 7230) = 'true');

-- F1 翻面闸 = 备战结束 + 60 秒（240）且真实场次结果齐
select pg_temp.at(239);
select pg_temp.ck('F1 结果齐了但没到备战结束 + 60（239 秒）⇒ 不翻面', public.finals_advance(pg_temp.wk()) = 0
  and (pg_temp.bk(0)).round = 1 and (pg_temp.bk(1)).round = 1);
select pg_temp.at(241);
select pg_temp.ck('F1 ★241 秒: 组 0 结果齐 ⇒ 翻面（不再等到 480）; 组 1 结果没齐 ⇒ 不翻', public.finals_advance(pg_temp.wk()) = 1
  and (pg_temp.bk(0)).round = 2 and (pg_temp.bk(1)).round = 1);
select pg_temp.mark('T1', (pg_temp.bk(0)).revealed_at);
select pg_temp.ck('F1 组 1 写回 ok', pg_temp.finish(1, 1, 1, 5400) = 'true');
select pg_temp.at(260);
select pg_temp.ck('F1 对照: 组 1 结果到了 ⇒ 下一次推进就翻（260 秒）', public.finals_advance(pg_temp.wk()) = 1 and (pg_temp.bk(1)).round = 2);
select pg_temp.mark('T1b', (pg_temp.bk(1)).revealed_at);

-- S1 / S2 / S3（小组赛：同一轮同时开播）
select pg_temp.ck('S1 ★组 0 同一轮同时: 两场开播都 = 翻面时刻、时长 130 / 151',
  (pg_temp.res(0, 1, 0)).premiere_at = pg_temp.t('T1') and (pg_temp.res(0, 1, 0)).premiere_sec = 130
  and (pg_temp.res(0, 1, 1)).premiere_at = pg_temp.t('T1') and (pg_temp.res(0, 1, 1)).premiere_sec = 151,
  format('%s / %s · %s / %s', (pg_temp.res(0, 1, 0)).premiere_at - pg_temp.t('T1'), (pg_temp.res(0, 1, 0)).premiere_sec,
         (pg_temp.res(0, 1, 1)).premiere_at - pg_temp.t('T1'), (pg_temp.res(0, 1, 1)).premiere_sec));
select pg_temp.ck('S2 组 0: 下一轮 round_at = 翻面 + 最长那场 151 + 25 = 翻面 + 176 = premiere_until',
  (pg_temp.bk(0)).round = 2 and (pg_temp.bk(0)).round_at = pg_temp.t('T1') + interval '176 seconds'
  and (pg_temp.bk(0)).premiere_until = (pg_temp.bk(0)).round_at,
  format('round_at - T1 = %s', (pg_temp.bk(0)).round_at - pg_temp.t('T1')));
select pg_temp.ck('S2 组 0: revealed_at = 翻面时刻（round_at 已在将来）',
  (pg_temp.bk(0)).revealed_at = pg_temp.t('T1') and (pg_temp.bk(0)).round_at > public.app_now());
select pg_temp.ck('S3 组 1: 轮空那一场（seed_used = 0）不排档期; 真实那一场 = 它的翻面时刻、时长 120; round_at = 翻面 + 145',
  (pg_temp.res(1, 1, 0)).seed_used = 0 and (pg_temp.res(1, 1, 0)).premiere_at is null
  and (pg_temp.res(1, 1, 1)).premiere_at = pg_temp.t('T1b') and (pg_temp.res(1, 1, 1)).premiere_sec = 120
  and (pg_temp.bk(1)).round_at = pg_temp.t('T1b') + interval '145 seconds',
  format('bye=%s real=%s/%s round_at-T1b=%s', (pg_temp.res(1, 1, 0)).premiere_at, (pg_temp.res(1, 1, 1)).premiere_at,
         (pg_temp.res(1, 1, 1)).premiere_sec, (pg_temp.bk(1)).round_at - pg_temp.t('T1b')));

-- V1 / V2（组 0 翻面后 29 秒：两场都在开播）
select pg_temp.at(270);
create temp table _v0 as select pg_temp.view(0) as v;
select pg_temp.ck('V1 分母: finals_view ok、done 两场', ((select v from _v0)->>'ok')::boolean
  and (select count(*) from jsonb_object_keys((select v from _v0)->'done')) = 2, (select v::text from _v0));
select pg_temp.ck('V1 seq.v = 1 / until = round_at（epoch）/ settle_at = round_at + 180',
  ((select v from _v0)->'seq'->>'v')::int = 1
  and ((select v from _v0)->'seq'->>'until')::bigint = pg_temp.e(pg_temp.t('T1') + interval '176 seconds')
  and ((select v from _v0)->>'round_at')::bigint = pg_temp.e(pg_temp.t('T1') + interval '176 seconds')
  and ((select v from _v0)->'seq'->>'settle_at')::bigint = ((select v from _v0)->>'round_at')::bigint + 180,
  (select (v->'seq')::text from _v0));
select pg_temp.ck('V1 seq.p 两场 [开播, 揭晓] = [T1, T1+130] / [T1, T1+151]',
  (select v->'seq'->'p'->'1-0' from _v0) = jsonb_build_array(pg_temp.e(pg_temp.t('T1')), pg_temp.e(pg_temp.t('T1')) + 130)
  and (select v->'seq'->'p'->'1-1' from _v0) = jsonb_build_array(pg_temp.e(pg_temp.t('T1')), pg_temp.e(pg_temp.t('T1')) + 151)
  and (select count(*) from jsonb_object_keys((select v->'seq'->'p' from _v0))) = 2,
  (select (v->'seq'->'p')::text from _v0));
select pg_temp.ck('V2 老键都还在、next_at = round_at + 180 + 60（最早翻面时刻）',
  (select v ?& array['ok', 'bucket', 'n', 'round', 'round_at', 'revealed_at', 'next_at', 'now', 'closed', 'entrants', 'done', 'scores'] from _v0)
  and ((select v from _v0)->>'next_at')::bigint - ((select v from _v0)->>'round_at')::bigint = 240);
-- 当前轮的档期不下发（防哪天提前写了：插一行第 2 轮假档期，seq.p 里也不许有）
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, premiere_at, premiere_sec)
  values (pg_temp.wk(), 0, 2, 0, 1, 1, public.app_now(), 60);
select pg_temp.ck('V1 ★当前轮（第 2 轮）的档期与结果都不下发',
  not ((pg_temp.view(0))->'seq'->'p' ? '2-0') and not ((pg_temp.view(0))->'done' ? '2-0')
  and ((pg_temp.view(0))->'seq'->'p' ? '1-0'));
delete from public.finals_results where season_week = pg_temp.wk() and bucket_no = 0 and round = 2;
create temp table _w0 as select pg_temp.wview() as v;
select pg_temp.ck('V2 finals_week_view: 组 0 / 组 1 都带 seq；组 1 只有真实那一场 1-1',
  (select v->'buckets'->0->'seq'->'p' from _w0) = (select v->'seq'->'p' from _v0)
  and (select v->'buckets'->1->'seq'->'p' from _w0) ?& array['1-1']
  and (select count(*) from jsonb_object_keys((select v->'buckets'->1->'seq'->'p' from _w0))) = 1,
  (select v::text from _w0));

-- N1 下一轮备战没开（组 0 round_at = T1+176 ≈ 第 417 秒，在将来）
select pg_temp.as_user((select id from _ppl where i = 1));
select pg_temp.ck('N1 round_at 之前: 问下一轮对手快照 ⇒ shop_open',
  (public.finals_opponent(pg_temp.wk(), 0, 2, 2, 0) ->> 'reason') = 'shop_open');
select pg_temp.as_user(null);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('N1 round_at 之前: 不建下一轮的任务', pg_temp.jobs(2) = 0, pg_temp.jobs(2)::text);
-- 组 1（round_at = T1b+145 ≈ 405 ⇒ 备战到 585）、组 0（≈ 417 ⇒ 备战到 597）：第 590 秒组 1 关了、组 0 还开着
select pg_temp.at(590);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('N1 组 1 购物窗关了 ⇒ 建决赛任务; 组 0 还在备战 ⇒ 不建', pg_temp.jobs(2) = 1
  and exists (select 1 from public.referee_jobs where match_key = pg_temp.key(1, 2, 0))
  and not exists (select 1 from public.referee_jobs where match_key = pg_temp.key(0, 2, 0)));
select pg_temp.ck('N1 组 1 决赛写回 ok', pg_temp.finish(1, 2, 0, 9000) = 'true');
select pg_temp.at(600);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('N1 对照: 组 0 到 round_at + 180 ⇒ 建决赛任务', exists (select 1 from public.referee_jobs where match_key = pg_temp.key(0, 2, 0)));
select pg_temp.ck('N1 组 0 决赛写回 ok', pg_temp.finish(0, 2, 0, 9000) = 'true');

-- C1 收盘那一轮
-- 组 0 第 2 轮 round_at = 第 417 秒（+ 同一个小数秒）⇒ 第 657 秒才到 备战结束 + 60
select pg_temp.at(656);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('C1 分母: 组 0 第 2 轮结果齐了、到备战结束 + 60 前一秒不推', not (pg_temp.bk(0)).closed and (pg_temp.bk(0)).round = 2);
select pg_temp.at(657);
select public.finals_advance(pg_temp.wk());
select pg_temp.mark('T2', (pg_temp.bk(0)).revealed_at);
select pg_temp.ck('C1 组 0 收盘; 决赛开播 = 翻面、时长 180、premiere_until = 翻面 + 205',
  (pg_temp.bk(0)).closed and (pg_temp.res(0, 2, 0)).premiere_at = pg_temp.t('T2') and (pg_temp.res(0, 2, 0)).premiere_sec = 180
  and (pg_temp.bk(0)).premiere_until = pg_temp.t('T2') + interval '205 seconds',
  format('closed=%s until-T2=%s', (pg_temp.bk(0)).closed, (pg_temp.bk(0)).premiere_until - pg_temp.t('T2')));
select pg_temp.ck('C1 组 1 也收盘了（它更早）', (pg_temp.bk(1)).closed and (pg_temp.bk(1)).premiere_until is not null);
select pg_temp.ck('C1 收盘后 seq.p 含三场（决赛 [T2, T2+180]）、settle_at = 0（没有下一轮）',
  ((pg_temp.view(0))->'seq'->'p'->'2-0') = jsonb_build_array(pg_temp.e(pg_temp.t('T2')), pg_temp.e(pg_temp.t('T2')) + 180)
  and (select count(*) from jsonb_object_keys((pg_temp.view(0))->'seq'->'p')) = 3
  and ((pg_temp.view(0))->'seq'->>'settle_at')::bigint = 0);

-- K1 冠军杯赛成表（开赛钟点 + 30 秒；时刻一律从 finals_cup_hour() 推，10-31 冠军杯赛 20:00 → 19:00 时这里写死 2 小时出过错）。再加两个 1 人组（坐下即收盘）⇒ 杯 4 人、第 1 轮两场真实对局（验「杯内一场接一场」）
select pg_temp.at((public.finals_cup_hour() - 18) * 3600 + 30);
insert into _ppl (i, id) values (101, gen_random_uuid()), (102, gen_random_uuid());
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _ppl where i in (101, 102);
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  select pg_temp.wk(), 10 + (i - 101), 0, id, 'solo' || i, pg_temp.snap('solo' || i) from _ppl where i in (101, 102);
insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
  values (pg_temp.wk(), 10, 1, 1, public.app_now(), true, public.app_now()),
         (pg_temp.wk(), 11, 1, 1, public.app_now(), true, public.app_now());
update public.finals_buckets set premiere_until = public.app_now() + interval '5 minutes'
 where season_week = pg_temp.wk() and bucket_no = 0;
create temp table _k1 as select public.finals_cup_seat(pg_temp.wk()) as n;
select pg_temp.ck('K1 ★有组收盘了但组内决赛还在开播 ⇒ 冠军杯赛等它（不成表）', (select n from _k1) = 0
  and not exists (select 1 from public.finals_buckets where season_week = pg_temp.wk() and bucket_no = public.finals_cup_no()));
update public.finals_buckets set premiere_until = public.app_now() - interval '1 minute'
 where season_week = pg_temp.wk() and bucket_no = 0;
select pg_temp.ck('K1 对照: 播完了 ⇒ 成表 4 人（两个组冠军 + 两个 1 人组）', public.finals_cup_seat(pg_temp.wk()) = 4);
select pg_temp.at((public.finals_cup_hour() - 18) * 3600 + 30 + 200);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('K1 杯第 1 轮两场写回 ok',
  pg_temp.finish(public.finals_cup_no(), 1, 0, 3000) = 'true' and pg_temp.finish(public.finals_cup_no(), 1, 1, 4000) = 'true');
select pg_temp.at((public.finals_cup_hour() - 18) * 3600 + 30 + 241);
select public.finals_advance(pg_temp.wk());
select pg_temp.mark('TC', (pg_temp.bk(public.finals_cup_no())).revealed_at);
select pg_temp.ck('K1 ★杯内一场接一场: 第 1 场 = 翻面、时长 80; 第 2 场 = 第 1 场结束 + 25 = 翻面 + 105、时长 97; round_at = 翻面 + 227',
  (pg_temp.bk(public.finals_cup_no())).round = 2
  and (pg_temp.res(public.finals_cup_no(), 1, 0)).premiere_at = pg_temp.t('TC') and (pg_temp.res(public.finals_cup_no(), 1, 0)).premiere_sec = 80
  and (pg_temp.res(public.finals_cup_no(), 1, 1)).premiere_at = pg_temp.t('TC') + interval '105 seconds'
  and (pg_temp.res(public.finals_cup_no(), 1, 1)).premiere_sec = 97
  and (pg_temp.bk(public.finals_cup_no())).round_at = pg_temp.t('TC') + interval '227 seconds'
  and (pg_temp.bk(public.finals_cup_no())).premiere_until = (pg_temp.bk(public.finals_cup_no())).round_at,
  format('m1-TC=%s round_at-TC=%s', (pg_temp.res(public.finals_cup_no(), 1, 1)).premiere_at - pg_temp.t('TC'),
         (pg_temp.bk(public.finals_cup_no())).round_at - pg_temp.t('TC')));
select pg_temp.ck('K1 week_view.cup.seq.p = [TC, TC+80] / [TC+105, TC+202]',
  ((pg_temp.wview())->'cup'->'seq'->'p'->'1-0') = jsonb_build_array(pg_temp.e(pg_temp.t('TC')), pg_temp.e(pg_temp.t('TC')) + 80)
  and ((pg_temp.wview())->'cup'->'seq'->'p'->'1-1') = jsonb_build_array(pg_temp.e(pg_temp.t('TC')) + 105, pg_temp.e(pg_temp.t('TC')) + 202),
  (pg_temp.wview()->'cup'->'seq')::text);
-- 杯决赛（打完收盘，免得它在后面几段的推进里插一脚）
select pg_temp.at((public.finals_cup_hour() - 18) * 3600 + 30 + 241 + 227 + 200);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('K1 杯决赛写回 ok', pg_temp.finish(public.finals_cup_no(), 2, 0, 3000) = 'true');
select pg_temp.at((public.finals_cup_hour() - 18) * 3600 + 30 + 241 + 227 + 241);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('K1 杯收盘、决赛也排档期（时长 80）', (pg_temp.bk(public.finals_cup_no())).closed
  and (pg_temp.res(public.finals_cup_no(), 2, 0)).premiere_sec = 80);

-- O1 开关关 ⇒ 老规则
update public.referee_config set finals_sequential = false where id = 1;
select pg_temp.ck('O1 分母: finals_sequential_on() = false', not public.finals_sequential_on());
select pg_temp.at((public.finals_cup_hour() - 17) * 3600);
select pg_temp.bucket(2, 4, 9);
select pg_temp.at((public.finals_cup_hour() - 17) * 3600 + 200);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('O1 写回两场', pg_temp.finish(2, 1, 0, 6000) = 'true' and pg_temp.finish(2, 1, 1, 6000) = 'true');
select pg_temp.at((public.finals_cup_hour() - 17) * 3600 + 241);
select pg_temp.ck('O1 ★老规则: 结果齐了、过了备战结束 + 60 也不翻（要等 480）', public.finals_advance(pg_temp.wk()) = 0
  and (pg_temp.bk(2)).round = 1);
select pg_temp.ck('O1 老规则: next_at = round_at + 480、seq = null（这一组没排过档期）',
  ((pg_temp.view(2))->>'next_at')::bigint - ((pg_temp.view(2))->>'round_at')::bigint = 480
  and jsonb_typeof((pg_temp.view(2))->'seq') = 'null');
select pg_temp.at((public.finals_cup_hour() - 17) * 3600 + 481);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('O1 ★老规则: 翻面即开下一轮（round_at = revealed_at = 此刻）、premiere_until = null、两场都没有档期',
  (pg_temp.bk(2)).round = 2 and (pg_temp.bk(2)).round_at = public.app_now() and (pg_temp.bk(2)).revealed_at = public.app_now()
  and (pg_temp.bk(2)).premiere_until is null
  and (pg_temp.res(2, 1, 0)).premiere_at is null and (pg_temp.res(2, 1, 1)).premiere_at is null);
select pg_temp.ck('O1 老规则: finals_view.seq = null', jsonb_typeof((pg_temp.view(2))->'seq') = 'null',
  coalesce(((pg_temp.view(2))->'seq')::text, 'absent'));
update public.referee_config set finals_sequential = true where id = 1;

-- O2 裁判关
update public.referee_config set finals_on = false where id = 1;
select pg_temp.ck('O2 裁判关 ⇒ finals_sequential_on() = false（客户端报结果的老路不排档期）', not public.finals_sequential_on());
update public.referee_config set finals_on = true where id = 1;

-- B1 兜底判 + 时长封顶（组 3，4 人：第 1 场写回 steps 100000，第 2 场裁判一直没回）
select pg_temp.at(4 * 3600);
select pg_temp.bucket(3, 4, 13);
select pg_temp.at(4 * 3600 + 200);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('B1 写回第 1 场（steps 100000）', pg_temp.finish(3, 1, 0, 100000) = 'true');
select pg_temp.at(4 * 3600 + 481);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('B1 分母: 缺一场、宽限期内不翻', (pg_temp.bk(3)).round = 1);
select pg_temp.at(4 * 3600 + 3 * 480 + 1);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('B1 3 倍时长后翻面: 缺的那一场兜底 side 0 / seed_used 0 ⇒ 不排档期',
  (pg_temp.bk(3)).round = 2 and (pg_temp.res(3, 1, 1)).seed_used = 0 and (pg_temp.res(3, 1, 1)).premiere_at is null);
select pg_temp.ck('B1 steps 100000 ⇒ 时长封顶 600 + 30; 下一轮 round_at = 翻面 + 630 + 25',
  (pg_temp.res(3, 1, 0)).premiere_sec = 630
  and (pg_temp.bk(3)).round_at = (pg_temp.bk(3)).revealed_at + interval '655 seconds',
  format('%s / %s', (pg_temp.res(3, 1, 0)).premiere_sec, (pg_temp.bk(3)).round_at - (pg_temp.bk(3)).revealed_at));

-- B2 结果行不是这份任务写的（任务建好后结果先被别处写了 ⇒ 裁判写回 superseded）⇒ 不排档期（组 4，2 人）
insert into _ppl (id) select gen_random_uuid() from generate_series(1, 2);
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _ppl where i between 17 and 18;
select pg_temp.at(5 * 3600);
select pg_temp.bucket(4, 2, 17);
select pg_temp.at(5 * 3600 + 200);
select public.finals_advance(pg_temp.wk());
insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
  values (pg_temp.wk(), 4, 1, 0, 1, 424242);
create temp table _b2 as select pg_temp.finish(4, 1, 0, 6000) as ok;
select pg_temp.ck('B2 分母: 裁判写回被判 superseded（结果行先在）', (select ok from _b2) = 'true'
  and (select error from public.referee_jobs where match_key = pg_temp.key(4, 1, 0)) = 'superseded',
  (select format('jobs=%s status=%s error=%s', count(*), max(status), max(error)) from public.referee_jobs where match_key = pg_temp.key(4, 1, 0)));
select pg_temp.at(5 * 3600 + 481);
select public.finals_advance(pg_temp.wk());
select pg_temp.ck('B2 ★收盘了、但这一场不排档期（录像不是这一行结果的那一局）; premiere_until = 翻面时刻',
  (pg_temp.bk(4)).closed and (pg_temp.res(4, 1, 0)).premiere_at is null
  and (pg_temp.bk(4)).premiere_until = (pg_temp.bk(4)).revealed_at);

-- P 权限
select pg_temp.ck('P 内部函数 anon / authenticated 都调不了（排档期 / seq 段 / 开关 / 倒计时）',
  not has_function_privilege('authenticated', 'public.finals_premiere_plan(bigint, int, int, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.finals_premiere_plan(bigint, int, int, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.finals_seq_json(bigint, int, int, boolean, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.finals_seq_json(bigint, int, int, boolean, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.finals_sequential_on()', 'execute')
  and not has_function_privilege('authenticated', 'public.finals_next_at(timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.finals_advance(bigint)', 'execute'));
select pg_temp.ck('P 读接口仍给 authenticated、不给 anon',
  has_function_privilege('authenticated', 'public.finals_view(bigint, int)', 'execute')
  and has_function_privilege('authenticated', 'public.finals_week_view(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.finals_view(bigint, int)', 'execute'));

-- ── 结论（一定抛异常 ⇒ 回滚）──
do $$
declare bad text; v_n int; v_f int;
begin
  select count(*), count(*) filter (where not pass) into v_n, v_f from _chk;
  select string_agg(format('[FAIL] %s %s', c.name, c.info), E'\n' order by c.n) into bad from _chk c where not c.pass;
  if v_f = 0 and v_n >= 35 then
    raise exception 'ALL PASS (% 条)', v_n;
  end if;
  raise exception 'FAIL % / % 条%', v_f, v_n, E'\n' || coalesce(bad, '(条数不够)');
end $$;
