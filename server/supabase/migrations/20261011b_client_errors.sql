-- >>> BEGIN client_errors 20261011 >>>
-- ─────────────────────────────────────────────────────────────
-- 客户端报错上报（2026-10-11 · 方案书 docs/plans/20261011-客户端报错上报.md）
--   用户原话：「你有后台能够收集任何问题和反馈吗」「做，今晚你自己安排时间做」
--
-- 一张表 + 一个写入函数：
--   · 主键 (account_id, day, sig) ⇒ 同一人同一天同一错误只占一行，count 累加。
--   · 只能经 report_client_error 写（security definer，主人 = auth.uid()）；
--     表上不给 anon / authenticated 任何直接读写（只有管理员通道看）。
--   · 每人每天最多 200 行，超了静默丢；字段服务端再截断一次（客户端截过也不信）。
-- ★本文件只建表 / 建函数，不动任何已有数据。重复执行安全。
-- ─────────────────────────────────────────────────────────────

create table if not exists public.client_errors (
  account_id   uuid        not null references auth.users(id) on delete cascade,
  day          date        not null,
  sig          text        not null,
  kind         text        not null,
  version      text        not null default '',
  platform     text        not null default '',
  scene        text        not null default '',
  message      text        not null default '',
  detail       text        not null default '',
  count        int         not null default 1,
  first_at     timestamptz not null default now(),
  last_at      timestamptz not null default now(),
  primary key (account_id, day, sig)
);

create index if not exists client_errors_day_idx on public.client_errors (day, sig);

alter table public.client_errors enable row level security;
-- 不建任何 policy ⇒ anon / authenticated 直接读写一律被拒；收回默认表权限做第二道。
revoke all on public.client_errors from anon, authenticated, public;

create or replace function public.report_client_error(
  p_sig text, p_kind text, p_version text, p_platform text,
  p_scene text, p_message text, p_detail text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  d   date := (now() at time zone 'UTC')::date;
  n   int;
begin
  if uid is null or coalesce(p_sig, '') = '' then
    return false;
  end if;
  select count(*) into n from public.client_errors where account_id = uid and day = d;
  if n >= 200 and not exists (select 1 from public.client_errors
                              where account_id = uid and day = d and sig = left(p_sig, 64)) then
    return false;
  end if;
  insert into public.client_errors as c
    (account_id, day, sig, kind, version, platform, scene, message, detail)
  values (uid, d, left(p_sig, 64), left(coalesce(p_kind, ''), 32), left(coalesce(p_version, ''), 32),
          left(coalesce(p_platform, ''), 32), left(coalesce(p_scene, ''), 128),
          left(coalesce(p_message, ''), 1000), left(coalesce(p_detail, ''), 4000))
  on conflict (account_id, day, sig) do update
    set count = c.count + 1, last_at = now(),
        version = excluded.version, scene = excluded.scene;
  return true;
end $$;

revoke all on function public.report_client_error(text, text, text, text, text, text, text) from public, anon;
grant execute on function public.report_client_error(text, text, text, text, text, text, text) to authenticated;
-- <<< END client_errors 20261011 <<<
