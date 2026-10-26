-- 20261026b 闯关赛截止改到周日 17:30 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261026b_gauntlet_sunday_close
--   ★最后一句一定抛异常（全过也抛 'ALL PASS'）⇒ 造的号、改的开关、删的约束、插的行一个都不留。
-- 假时间的做法照 20261021 检查脚本：本事务里删掉 server_clock_prod_zero、env 切 beta、写偏移（回滚即还原）。
-- 判据：
--   W1 假周日 12:00 ⇒ referee_gauntlet_start 过了时间闸（回 bad_snapshot，不是 closed）
--   W2 假周日 17:29 ⇒ 过闸；假周日 17:31 ⇒ closed（边界两侧）
--   W3 对照：假周六 12:00 ⇒ 过闸；假周五 12:00 ⇒ closed
--   W4 旧路 referee_submit_gauntlet（server_pick 关）：假周日 12:00 过闸、假周日 17:31 ⇒ closed
--   F1 闯关结果把战绩打到 4 胜 ⇒ finals_pending 出现这个人（gw=4，名字取快照里的）
--   F2 对照：只打到 3 胜 ⇒ 不登记
--   F3 已经分组（finals_buckets 有这一周）⇒ 第 4 胜也不登记
--   F4 客户端先报过名 ⇒ 服务端那一笔不覆盖（名字保持客户端报的）
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
create temp table _ctx as select gen_random_uuid() as u, gen_random_uuid() as u2, gen_random_uuid() as u3, gen_random_uuid() as u4;
grant all on _chk to public;
grant all on _chk_n_seq to public;
grant select on _ctx to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 假时间 = 真实时间所在那一周的第 wd 天（ISO 1~7）h:m（UTC）；向上取整同 20261021
create or replace function pg_temp.set_fake(wd int, h int, m int default 0) returns void language plpgsql as $$
declare wk timestamptz := date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (wk + make_interval(days => wd - 1, hours => h, mins => m)) - now()))::bigint where id = 1;
end $$;
create or replace function pg_temp.fake_week() returns bigint language sql as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
create or replace function pg_temp.start_reason() returns text language sql as $$
  select public.referee_gauntlet_start(pg_temp.fake_week(), null, 0, '9.9.9', 1) ->> 'reason'
$$;
create or replace function pg_temp.submit_reason() returns text language sql as $$
  select public.referee_submit_gauntlet(pg_temp.fake_week(), null, null, '9.9.9') ->> 'reason'
$$;

-- 内测服口径（本事务里）：能写假时间
alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;

insert into auth.users (id, aud, role, is_anonymous, created_at)
  select x, 'authenticated', 'authenticated', true, now() from _ctx, unnest(array[u, u2, u3, u4]) x;
update public.referee_config set gauntlet_on = true, gauntlet_any_day = false, gauntlet_server_pick = true where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('9.9.9', true, 1)
  on conflict (client_version) do update set enabled = true, rules_ver = 1;

-- ── W1 / W2 / W3 新开打闸 ──
select pg_temp.as_user((select u from _ctx));
select pg_temp.set_fake(7, 12);
select pg_temp.ck('W1 假周日 12:00 ⇒ 过了时间闸（bad_snapshot）', pg_temp.start_reason() = 'bad_snapshot', pg_temp.start_reason());
select pg_temp.set_fake(7, 17, 29);
select pg_temp.ck('W2 假周日 17:29 ⇒ 过闸', pg_temp.start_reason() = 'bad_snapshot', pg_temp.start_reason());
select pg_temp.set_fake(7, 17, 31);
select pg_temp.ck('W2 假周日 17:31 ⇒ closed', pg_temp.start_reason() = 'closed', pg_temp.start_reason());
select pg_temp.set_fake(6, 12);
select pg_temp.ck('W3 对照: 假周六 12:00 ⇒ 过闸', pg_temp.start_reason() = 'bad_snapshot', pg_temp.start_reason());
select pg_temp.set_fake(5, 12);
select pg_temp.ck('W3 对照: 假周五 12:00 ⇒ closed', pg_temp.start_reason() = 'closed', pg_temp.start_reason());

-- ── W4 旧路 ──
update public.referee_config set gauntlet_server_pick = false where id = 1;
select pg_temp.set_fake(7, 12);
select pg_temp.ck('W4 旧路 假周日 12:00 ⇒ 过了时间闸（不是 closed）', pg_temp.submit_reason() is distinct from 'closed', pg_temp.submit_reason());
select pg_temp.set_fake(7, 17, 31);
select pg_temp.ck('W4 旧路 假周日 17:31 ⇒ closed', pg_temp.submit_reason() = 'closed', pg_temp.submit_reason());
update public.referee_config set gauntlet_server_pick = true where id = 1;
select pg_temp.as_user(null);

-- ── F 第 4 胜由服务端登记报名 ──
-- 造一局「已领走」的闯关任务, 再用裁判身份交结果。fk = 一个不会撞真实周的假周号（2100 年）。
create temp table _fw as select 4102444800::bigint as wk;
grant select on _fw to public;
create or replace function pg_temp.job_for(p_acc uuid, p_key text) returns bigint language plpgsql as $$
declare jid bigint;
begin
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot,
                                   meta, status, claimed_by, claimed_at)
    values ('gauntlet', p_key, (select wk from _fw), '9.9.9', 12345, p_acc,
            '{"profile":{"name":"检查甲"},"leaders":["basic"]}'::jsonb, '{"is_bot":true}'::jsonb,
            '{"rules_ver":1}'::jsonb, 'claimed', 'chk-worker', now())
    returning job_id into jid;
  return jid;
end $$;
create or replace function pg_temp.win(p_job bigint) returns jsonb language sql as $$
  select public.referee_complete(p_job, 'chk-worker', jsonb_build_object(
    'ok', true, 'match_id', (select match_id::text from public.referee_jobs where job_id = p_job),
    'seed', 12345, 'client_version', '9.9.9', 'winner', 'a', 'steps', 100, 'replay_b64', 'QUJD'))
$$;

-- F1: 3-1 → 4-1
insert into public.gauntlet_records (season_week, account_id, gw, gl) select (select wk from _fw), u, 3, 1 from _ctx;
select pg_temp.ck('F1 分母: 结果交上去了', (pg_temp.win(pg_temp.job_for((select u from _ctx), 'chk:f1')) ->> 'ok') = 'true');
select pg_temp.ck('F1 第 4 胜 ⇒ finals_pending 有这个人（gw=4, 名字取快照）',
  exists (select 1 from public.finals_pending p, _ctx where p.season_week = (select wk from _fw) and p.account_id = _ctx.u
          and p.gw = 4 and p.gl = 1 and p.name = '检查甲'),
  coalesce((select row_to_json(p)::text from public.finals_pending p, _ctx where p.account_id = _ctx.u), '无'));

-- F2: 2-1 → 3-1 不登记
insert into public.gauntlet_records (season_week, account_id, gw, gl) select (select wk from _fw), u2, 2, 1 from _ctx;
select pg_temp.win(pg_temp.job_for((select u2 from _ctx), 'chk:f2'));
select pg_temp.ck('F2 对照: 只到 3 胜 ⇒ 不登记',
  not exists (select 1 from public.finals_pending p, _ctx where p.account_id = _ctx.u2));

-- F4: 客户端先报过名（名字「客户端报的」）⇒ 不覆盖
insert into public.gauntlet_records (season_week, account_id, gw, gl) select (select wk from _fw), u4, 3, 0 from _ctx;
insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
  select (select wk from _fw), u4, '客户端报的', '{}'::jsonb, 4, 0 from _ctx;
select pg_temp.win(pg_temp.job_for((select u4 from _ctx), 'chk:f4'));
select pg_temp.ck('F4 客户端先报过 ⇒ 服务端不覆盖',
  (select name from public.finals_pending p, _ctx where p.account_id = _ctx.u4) = '客户端报的');

-- F3: 已分组 ⇒ 不登记
insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
  values ((select wk from _fw), 1, 2, 1, now(), false);
insert into public.gauntlet_records (season_week, account_id, gw, gl) select (select wk from _fw), u3, 3, 2 from _ctx;
select pg_temp.win(pg_temp.job_for((select u3 from _ctx), 'chk:f3'));
select pg_temp.ck('F3 已分组 ⇒ 第 4 胜也不登记',
  not exists (select 1 from public.finals_pending p, _ctx where p.account_id = _ctx.u3)
  and (select gw from public.gauntlet_records r, _ctx where r.account_id = _ctx.u3) = 4);

do $$
declare nf int; nt int; msg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
