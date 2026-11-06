-- 20261106d 积分赛账本周六周日不回给客户端 —— 上线前验证（整段一个事务，结尾必抛异常 ⇒ 回滚）
-- 用法：python tools/sb_migrate.py sandbox|beta --rehearse|prod --rehearse 20261106d_ranked_ledger_weekend
-- 假时间：本事务里删 server_clock_prod_zero、env 切 beta、写偏移，回滚即还原。
-- 判据：
--   W1 周五 22:59 ⇒ 照回账本（场次 / 胜场 = 服务端那一行）
--   W2 ★周六 00:00 ⇒ {ok:false, reason:weekend}，回包里没有 ledger 键（分界恰在周六零点）
--   W3 周五 23:59 ⇒ 还回账本（分界没有提前）
--   W4 ★周日 ⇒ weekend
--   W5 下一周周二查下一周 ⇒ 回账本（周界重新开始）
--   W6 ranked_any_day 开（内测服彩排）⇒ 周六也回
--   W7 未登录 ⇒ not_signed_in（先于周末判定）
--   P1 权限：anon 没有 execute，authenticated 有
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create temp table _u (id uuid primary key default gen_random_uuid());
insert into _u default values;
grant select on _u to public;

create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;
create or replace function pg_temp.me() returns uuid language sql as $$ select id from _u limit 1 $$;
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid::text, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
end $$;
-- 把 app_now 拨到「真实这一周 + p_wk 周」的星期 wd（1 = 周一）h:m；返回那一周的周锚点。向上取整秒：防一次调用内跨秒把时刻落到分界之前
create or replace function pg_temp.at(p_wk int, wd int, h int, m int default 0) returns bigint language plpgsql as $$
declare wk timestamptz := date_trunc('week', now() at time zone 'UTC') at time zone 'UTC' + make_interval(days => 7 * p_wk);
begin
  update public.server_clock set offset_sec =
    ceil(extract(epoch from (wk + make_interval(days => wd - 1, hours => h, mins => m)) - now()))::bigint where id = 1;
  return extract(epoch from wk)::bigint;
end $$;

alter table public.server_clock drop constraint if exists server_clock_prod_zero;
update public.service_env set env = 'beta' where id = 1;
update public.referee_config set ranked_any_day = false where id = 1;
insert into auth.users (id, aud, role, is_anonymous, created_at)
  select id, 'authenticated', 'authenticated', true, now() from _u;
insert into public.ranked_records (season_week, account_id, battles, wins, hearts, used)
  values (pg_temp.at(1, 2, 12), pg_temp.me(), 16, 11, 3, 16);

select pg_temp.as_user(pg_temp.me());
do $$
declare r jsonb; v_wk bigint;
begin
  v_wk := pg_temp.at(1, 5, 22, 59);
  r := public.referee_ranked_ledger(v_wk);
  perform pg_temp.ck('W1 周五 22:59 照回账本(16 场 11 胜)', (r ->> 'ok')::boolean and (r -> 'ledger' ->> 'battles')::int = 16
    and (r -> 'ledger' ->> 'wins')::int = 11, r::text);
  v_wk := pg_temp.at(1, 5, 23, 59);
  r := public.referee_ranked_ledger(v_wk);
  perform pg_temp.ck('W3 周五 23:59 还回账本(分界没有提前)', (r ->> 'ok')::boolean, r::text);
  v_wk := pg_temp.at(1, 6, 0);
  r := public.referee_ranked_ledger(v_wk);
  perform pg_temp.ck('W2 ★周六零点 ⇒ weekend、回包没有 ledger', not (r ->> 'ok')::boolean and r ->> 'reason' = 'weekend' and not (r ? 'ledger'), r::text);
  v_wk := pg_temp.at(1, 7, 12);
  r := public.referee_ranked_ledger(v_wk);
  perform pg_temp.ck('W4 ★周日 ⇒ weekend', not (r ->> 'ok')::boolean and r ->> 'reason' = 'weekend', r::text);
  v_wk := pg_temp.at(2, 2, 12);
  r := public.referee_ranked_ledger(v_wk);
  perform pg_temp.ck('W5 下一周周二 ⇒ 回账本(周界重新开始)', (r ->> 'ok')::boolean and (r -> 'ledger' ->> 'battles')::int = 0, r::text);
  v_wk := pg_temp.at(1, 6, 12);
  update public.referee_config set ranked_any_day = true where id = 1;
  r := public.referee_ranked_ledger(v_wk);
  perform pg_temp.ck('W6 ranked_any_day 开 ⇒ 周六也回', (r ->> 'ok')::boolean and (r -> 'ledger' ->> 'battles')::int = 16, r::text);
  update public.referee_config set ranked_any_day = false where id = 1;
end $$;
select pg_temp.as_user(null);
select pg_temp.ck('W7 未登录 ⇒ not_signed_in(先于周末判定)',
  public.referee_ranked_ledger(pg_temp.at(1, 6, 12)) ->> 'reason' = 'not_signed_in');
select pg_temp.ck('P1 权限: anon 没有、authenticated 有',
  not has_function_privilege('anon', 'public.referee_ranked_ledger(bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.referee_ranked_ledger(bigint)', 'execute'));

do $$
declare nf int; nt int; msg text; fmsg text;
begin
  select count(*) filter (where not pass), count(*) into nf, nt from _chk;
  select string_agg(format('[%s] %s %s', case when pass then 'PASS' else 'FAIL' end, name, info), E'\n' order by n) into msg from _chk;
  select string_agg(left(format('[FAIL] %s %s', name, info), 600), E'\n' order by n) into fmsg from _chk where not pass;
  raise notice '%', msg;
  if nf > 0 then
    raise exception 'FAIL % / % —— 已回滚%', nf, nt, E'\n' || fmsg || E'\n──── 全部 ────\n' || msg;
  end if;
  raise exception 'ALL PASS (% 条) —— 已回滚, 测试数据未留下', nt;
end $$;
rollback;
