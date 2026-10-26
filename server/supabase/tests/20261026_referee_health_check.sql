-- 20261026 裁判机外部探活口 referee_health() —— 上线前验证（整段一个事务，结尾必回滚）
-- ─────────────────────────────────────────────────────────────
-- 用法：python tools/sb_migrate.py sandbox 20261026_referee_health（内测服 / 生产同 sb_migrate 流程）
--   ★本文件最后一句一定抛异常 ⇒ 整个事务回滚（下面删心跳行、插假行都不会留下）。
-- 判据：
--   H1 anon 有执行权，而且真的以 anon 身份调得到（不只查权限表）
--   H2 回包只有四个键（不多吐线程名 / 版本 / 玩家数据）
--   H3 有一个刚报过的心跳 ⇒ freshest_sec = 0、fresh_workers ≥ 1
--   H4 只剩一个 700 秒前的旧心跳 ⇒ freshest_sec = 700、fresh_workers = 0（「最新」取 max(seen_at)，不被旧行拖住）
--   H5 一行心跳都没有 ⇒ freshest_sec 为 null
--   H6 对照：referee_backlog 仍然不给 anon
-- ─────────────────────────────────────────────────────────────
begin;

create temp table _chk (n serial, name text, pass boolean, info text);
grant all on _chk to public;
grant all on _chk_n_seq to public;
create or replace function pg_temp.ck(p_name text, p_pass boolean, p_info text default '') returns void
language sql as $$ insert into _chk (name, pass, info) values (p_name, coalesce(p_pass, false), coalesce(p_info, '')) $$;

-- ── H1 anon ──
select pg_temp.ck('H1 anon 有执行权', has_function_privilege('anon', 'public.referee_health()', 'execute'));
set local role anon;
select set_config('chk.h_anon', public.referee_health()::text, true);
reset role;
select pg_temp.ck('H1 以 anon 身份真的调得到', current_setting('chk.h_anon', true) like '{%', current_setting('chk.h_anon', true));

-- ── H2 键 ──
select pg_temp.ck('H2 回包只有四个键',
  (select array_agg(k order by k) from jsonb_object_keys(public.referee_health()) k)
    = array['fresh_workers', 'freshest_sec', 'oldest_pending_sec', 'pending'],
  public.referee_health()::text);

-- ── H3 新鲜心跳 ──
insert into public.referee_workers (worker, versions, seen_at) values ('chk-fresh', '{}', now())
  on conflict (worker) do update set seen_at = now();
select pg_temp.ck('H3 刚报过的心跳 ⇒ freshest_sec = 0、fresh_workers ≥ 1',
  (public.referee_health()->>'freshest_sec')::int = 0 and (public.referee_health()->>'fresh_workers')::int >= 1,
  public.referee_health()::text);

-- ── H4 只剩旧心跳 ──
delete from public.referee_workers;
insert into public.referee_workers (worker, versions, seen_at) values ('chk-old', '{}', now() - interval '700 seconds');
select pg_temp.ck('H4 只剩 700 秒前的心跳 ⇒ freshest_sec = 700、fresh_workers = 0',
  (public.referee_health()->>'freshest_sec')::int = 700 and (public.referee_health()->>'fresh_workers')::int = 0,
  public.referee_health()::text);
insert into public.referee_workers (worker, versions, seen_at) values ('chk-new', '{}', now() - interval '30 seconds');
select pg_temp.ck('H4 再来一个 30 秒前的 ⇒ freshest_sec 取最新那个 = 30（不被 700 秒的旧行拖住）',
  (public.referee_health()->>'freshest_sec')::int = 30 and (public.referee_health()->>'fresh_workers')::int = 1,
  public.referee_health()::text);

-- ── H5 空表 ──
delete from public.referee_workers;
select pg_temp.ck('H5 一行心跳都没有 ⇒ freshest_sec 为 null',
  public.referee_health()->'freshest_sec' = 'null'::jsonb, public.referee_health()::text);

-- ── H6 对照 ──
select pg_temp.ck('H6 referee_backlog 仍然不给 anon', not has_function_privilege('anon', 'public.referee_backlog()', 'execute'));

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
