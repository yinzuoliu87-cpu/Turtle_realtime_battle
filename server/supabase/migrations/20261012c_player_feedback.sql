-- >>> BEGIN player_feedback 20261012 >>>
-- ─────────────────────────────────────────────────────────────
-- 玩家主动提交的问题反馈（2026-10-12）
--   用户原话：「人家如果遇到问题还要按你这个模版填？游戏内没有直接上传bug信息？」
--   客户端：设置 →「问题反馈」（scripts/scenes/feedback_panel.gd · scripts/net/feedback_net.gd）
--
-- 一张表 + 一个写入函数（写法同 20261011b_client_errors.sql）：
--   · 只能经 submit_feedback 写（security definer，主人 = auth.uid()）；
--     表上不给 anon / authenticated 任何直接读写（只有管理员通道看，tools/beta_daily.py ⑦）。
--   · 每人每天（UTC）最多 20 条，超了返回 false。
--   · 字段服务端再截断一次（客户端截过也不信）：kind 32 / message 1000 / meta 序列化后 ≤ 8000 字节，
--     超了只留基本项（版本 / 平台 / 设备 / 系统版本 / 账号 / 对局编号），丢掉最近报错等大字段。
--   · 随账号删除而删除（on delete cascade）—— 隐私政策 1.7b。
-- ★本文件只建表 / 建函数，不动任何已有数据。重复执行安全。
-- ─────────────────────────────────────────────────────────────

create table if not exists public.player_feedback (
  id          bigserial   primary key,
  account_id  uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  kind        text        not null default '',
  message     text        not null default '',
  meta        jsonb       not null default '{}'::jsonb
);

create index if not exists player_feedback_acct_idx on public.player_feedback (account_id, created_at);
create index if not exists player_feedback_day_idx on public.player_feedback (created_at);

alter table public.player_feedback enable row level security;
-- 不建任何 policy ⇒ anon / authenticated 直接读写一律被拒；收回默认表权限做第二道。
revoke all on public.player_feedback from anon, authenticated, public;
revoke all on sequence public.player_feedback_id_seq from anon, authenticated, public;

create or replace function public.submit_feedback(
  p_kind text, p_message text, p_meta jsonb
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  uid  uuid := auth.uid();
  d0   timestamptz := ((now() at time zone 'UTC')::date)::timestamp at time zone 'UTC';
  n    int;
  msg  text := left(btrim(coalesce(p_message, '')), 1000);
  meta jsonb := case when jsonb_typeof(p_meta) = 'object' then p_meta else '{}'::jsonb end;
begin
  if uid is null or msg = '' then
    return false;
  end if;
  select count(*) into n from public.player_feedback where account_id = uid and created_at >= d0;
  if n >= 20 then
    return false;
  end if;
  if octet_length(meta::text) > 8000 then
    meta := jsonb_build_object(
      'version',    left(coalesce(meta->>'version', ''), 32),
      'platform',   left(coalesce(meta->>'platform', ''), 32),
      'model',      left(coalesce(meta->>'model', ''), 64),
      'os_version', left(coalesce(meta->>'os_version', ''), 64),
      'account',    left(coalesce(meta->>'account', ''), 64),
      'replays',    case when jsonb_typeof(meta->'replays') = 'array'
                          and octet_length((meta->'replays')::text) <= 400
                         then meta->'replays' else '[]'::jsonb end,
      'truncated',  true);
  end if;
  insert into public.player_feedback (account_id, kind, message, meta)
  values (uid, left(coalesce(p_kind, ''), 32), msg, meta);
  return true;
end $$;

revoke all on function public.submit_feedback(text, text, jsonb) from public, anon;
grant execute on function public.submit_feedback(text, text, jsonb) to authenticated;
-- <<< END player_feedback 20261012 <<<
