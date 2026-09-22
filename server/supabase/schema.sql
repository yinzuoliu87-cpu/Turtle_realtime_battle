-- 斗龟场·实时版 —— Supabase 表结构（D 阶段）
-- 方案书：docs/plans/20260920-D阶段后端与账号.md §D-2
--
-- 怎么用：Supabase Dashboard → SQL Editor → 整份粘贴执行（可重复执行，全部带 IF NOT EXISTS）。
--
-- ★★这份 schema 的两个要害，都是本项目踩过的坑：
--   ① **主键必须含 account_id**。单机够用的 id（赛季+三龟）一接共享服务器就塌：
--      两个人同 id 会在服务端互相覆盖，而且是**静默**的数据丢失。
--      （memory fb-id-without-owner-dimension；A6/U11 已经给 ghost_id 加了「场次」这一维，
--        这里补的是「谁」这一维。）
--   ② **RLS 必须开且策略要写对**。anon key 是**公开值**（要嵌进客户端），
--      没有 RLS 等于把整个数据库公开可写。默认拒绝、逐表放行。

-- ─────────────────────────────────────────────────────────────
-- 1. accounts —— 账号（匿名起步，可补绑邮箱）
--    account_id 直接用 Supabase Auth 的 uid：匿名登录也会发一个，
--    补绑邮箱是**升级同一个 uid**（不新建），所以换设备取回的是同一份档。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.accounts (
  account_id  uuid primary key references auth.users(id) on delete cascade,
  display_name text,                       -- 玩家昵称（自取）；政策里已提醒勿填真名
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

alter table public.accounts enable row level security;

drop policy if exists accounts_self_select on public.accounts;
create policy accounts_self_select on public.accounts
  for select using (account_id = auth.uid());

drop policy if exists accounts_self_upsert on public.accounts;
create policy accounts_self_upsert on public.accounts
  for insert with check (account_id = auth.uid());

drop policy if exists accounts_self_update on public.accounts;
create policy accounts_self_update on public.accounts
  for update using (account_id = auth.uid()) with check (account_id = auth.uid());

-- ─────────────────────────────────────────────────────────────
-- 2. ghosts —— 阵容快照（每场都传，同键覆盖）
--    ★主键 (account_id, season_week, battles)：
--      · account_id —— 「谁」，少了它两人互相覆盖
--      · season_week —— 「哪一周」，周锚点（UTC 周一 00:00 的 unix 秒），与客户端
--        _P2.week_anchor_utc() 同一口径
--      · battles —— 「第几场」，匹配硬条件是**双方总场次相同**（D5，不再按 9 档分档）
-- ─────────────────────────────────────────────────────────────
create table if not exists public.ghosts (
  account_id   uuid        not null references auth.users(id) on delete cascade,
  season_week  bigint      not null,
  battles      int         not null,
  snapshot     jsonb       not null,        -- build_ghost_snapshot() 的产物
  season_wins  int         not null default 0,
  hearts       int         not null default 8,
  season_sweeps int        not null default 0,
  client_version text      not null,
  uploaded_at  timestamptz not null default now(),
  primary key (account_id, season_week, battles)
);

-- 匹配查询：同一周 + 同场次，**按上传时刻倒序取最新**（D10：新鲜度是排序不是过滤）
create index if not exists ghosts_match_idx
  on public.ghosts (season_week, battles, uploaded_at desc);

alter table public.ghosts enable row level security;

-- 读：所有登录用户都能读（匹配要在别人的快照里挑对手）
drop policy if exists ghosts_read_all on public.ghosts;
create policy ghosts_read_all on public.ghosts
  for select using (auth.uid() is not null);

-- 写：只能写自己的那一行
drop policy if exists ghosts_write_own on public.ghosts;
create policy ghosts_write_own on public.ghosts
  for insert with check (account_id = auth.uid());

drop policy if exists ghosts_update_own on public.ghosts;
create policy ghosts_update_own on public.ghosts
  for update using (account_id = auth.uid()) with check (account_id = auth.uid());

-- ─────────────────────────────────────────────────────────────
-- 3. matches —— 对局记录（观战与重放用）
--    ★保留期：最多到下一个周一，由 §5 的定时任务自动删（U7 拍板：不靠手动）。
--    ★带 client_version：播放前比对，不一致直接不给播（4.7 实现要求①）。
--      版本维护期放在周一休赛，而重放最长只活到周一 ⇒ 跨版本重放根本不存在。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.matches (
  match_id     uuid        primary key default gen_random_uuid(),
  season_week  bigint      not null,
  phase        text        not null,        -- rest / ranked / gauntlet / finals
  left_account  uuid       references auth.users(id) on delete set null,
  right_account uuid       references auth.users(id) on delete set null,
  seed         bigint      not null,        -- 确定性重算的种子（B 阶段：同种子逐步 0 分叉）
  left_snapshot  jsonb     not null,
  right_snapshot jsonb     not null,
  result       jsonb       not null,        -- 结果摘要（胜负 / 两路 / 时长）
  client_version text      not null,
  created_at   timestamptz not null default now()
);

create index if not exists matches_week_idx on public.matches (season_week, created_at desc);

alter table public.matches enable row level security;

-- 读：所有登录用户（D13 观赛四块都要读它）
drop policy if exists matches_read_all on public.matches;
create policy matches_read_all on public.matches
  for select using (auth.uid() is not null);

-- 写：只能写自己参与的对局
drop policy if exists matches_write_own on public.matches;
create policy matches_write_own on public.matches
  for insert with check (left_account = auth.uid() or right_account = auth.uid());

-- ─────────────────────────────────────────────────────────────
-- 4. standings —— 周榜与头衔
--    ★**客户端不许直接写**：排名与头衔是可作弊的。写入走 Edge Function（service_role），
--      它复用 server/rules.mjs 做账目校验（D7 第一步：客户端算 + 服务端校验与抽检）。
--    ⚠ 这里只放「默认拒绝」的读策略 —— 没有任何 insert/update 策略 = 客户端写不进来。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.standings (
  season_week bigint not null,
  account_id  uuid   not null references auth.users(id) on delete cascade,
  wins        int    not null default 0,
  hearts      int    not null default 8,
  sweeps      int    not null default 0,
  promoted    boolean not null default false,
  title       text,                          -- D12 四档：冠军 / 四强 / 进决赛日 / 积分赛满配额
  updated_at  timestamptz not null default now(),
  primary key (season_week, account_id)
);

create index if not exists standings_rank_idx
  on public.standings (season_week, wins desc, hearts desc, sweeps desc);

alter table public.standings enable row level security;

drop policy if exists standings_read_all on public.standings;
create policy standings_read_all on public.standings
  for select using (auth.uid() is not null);
-- ★故意没有 insert / update 策略：RLS 默认拒绝 ⇒ 只有 service_role 写得进来。

-- ─────────────────────────────────────────────────────────────
-- 5. service_status —— 停服开关（D-1）
--    ★为什么要它：客户端现在连不上只会**静默回落到本地池**，平时是对的，
--      但周一维护期会让玩家以为游戏坏了。⇒ 要能区分「没配后端」与「后端主动停服」。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_status (
  id          int primary key default 1,
  maintenance boolean not null default false,
  notice      text    not null default '',
  min_client_version text not null default '0.0.0',
  updated_at  timestamptz not null default now(),
  constraint service_status_single_row check (id = 1)
);

insert into public.service_status (id) values (1) on conflict (id) do nothing;

alter table public.service_status enable row level security;

-- 读：**不要求登录** —— 停服公告必须在登录失败时也读得到，否则就没意义了
drop policy if exists status_read_anon on public.service_status;
create policy status_read_anon on public.service_status
  for select using (true);
-- 写：同样只留给 service_role（没有 insert/update 策略）

-- ─────────────────────────────────────────────────────────────
-- 6. 重放到期自动删（U7：到期自动删，不靠手动）
--    ⚠ pg_cron 要先在 Dashboard → Database → Extensions 里启用。
--    口径：只保留**本周与上周**的对局。重放只在周六/周日/周一可看，
--    而周一过完就该没了 —— 留两周是给时区与边界留余量，不是放宽策略。
-- ─────────────────────────────────────────────────────────────
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < now() - interval '14 days';
$$;

-- 在 Dashboard 里执行一次（本文件不自动建任务，免得重复执行时报错）：
--   select cron.schedule('purge-matches', '0 1 * * 1', 'select public.purge_old_matches()');
-- 周一 01:00 UTC 跑 —— 在换轮（周一 00:00 UTC）之后。

-- ═════════════════════════════════════════════════════════════════════
-- D-7 存档同步（2026-09-21 用户拍板「需要存档同步的」）
-- ═════════════════════════════════════════════════════════════════════
-- 为什么要有这张表: 原来五张表没有一张存玩家存档 ⇒ 绑邮箱只能找回账号,
--   找不回龟和装备。玩家说「绑定邮箱」时期待的是后者。
--
-- ★判新旧**只看版本号 save_rev，不看时间戳**: 设备时钟不可信。
-- ★写入**只能**经 push_save() —— 没有 insert/update 策略给客户端直接写,
--   否则客户端可以绕过「比较并交换」直接覆盖别的设备的进度。
-- ★没有 delete 策略: 删号走 auth.users 的 on delete cascade。
create table if not exists public.saves (
  account_id     uuid        primary key references auth.users(id) on delete cascade,
  payload        jsonb       not null,
  save_rev       bigint      not null default 0,
  client_version text        not null,
  updated_at     timestamptz not null default now()
);

alter table public.saves enable row level security;

-- 读: 只能读自己的
drop policy if exists saves_self_select on public.saves;
create policy saves_self_select on public.saves
  for select using (account_id = auth.uid());

-- 写: 故意不给 insert / update 策略 —— 只能走下面那个函数

-- 比较并交换。返回 {"ok": bool, "rev": 当前版本, "reason": "..."}。
--   · 云端还没有这一行 ⇒ 仅当 expected_rev = 0 时建行(rev=1)
--   · 云端版本 = expected_rev ⇒ 覆盖, rev+1
--   · 否则 ⇒ 拒绝, 返回 conflict + 云端当前版本(客户端据此让玩家二选一)
-- ★security definer + 函数体内自己用 auth.uid() 定位行 —— 调用方**只能**改自己的那一行,
--   传不进别人的 account_id(参数里根本没有这一项)。
-- ★payload 大小上限 256 KB: 真实存档 ~10 KB(2026-09-21 实测), 留 25 倍余量;
--   挡的是有人拿这个接口当网盘。
create or replace function public.push_save(p_payload jsonb, p_expected_rev bigint, p_client_version text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cur bigint;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in', 'rev', 0);
  end if;
  if pg_column_size(p_payload) > 262144 then
    return jsonb_build_object('ok', false, 'reason', 'too_large', 'rev', 0);
  end if;
  select save_rev into cur from public.saves where account_id = uid for update;
  if cur is null then
    if p_expected_rev <> 0 then
      return jsonb_build_object('ok', false, 'reason', 'conflict', 'rev', 0);
    end if;
    insert into public.saves(account_id, payload, save_rev, client_version)
      values (uid, p_payload, 1, p_client_version);
    return jsonb_build_object('ok', true, 'rev', 1);
  end if;
  if cur <> p_expected_rev then
    return jsonb_build_object('ok', false, 'reason', 'conflict', 'rev', cur);
  end if;
  update public.saves
     set payload = p_payload, save_rev = cur + 1,
         client_version = p_client_version, updated_at = now()
   where account_id = uid;
  return jsonb_build_object('ok', true, 'rev', cur + 1);
end
$$;

-- 只有登录用户能调(匿名登录也算登录; 客户端自己只在绑了邮箱之后才调)
revoke all on function public.push_save(jsonb, bigint, text) from public;
-- ★★2026-09-22 执行后回读才发现: 上一行**收不掉 anon 的执行权** ——
--   Supabase 在 public schema 上有默认授权, 会单独给 anon / authenticated / service_role 各一份,
--   `revoke from public` 管不到它们。实际危害很小(anon 调进来 auth.uid() 为空, 第一行就返回),
--   但意图是「只有登录用户能调」, 实测结果与意图不符就得改。
revoke execute on function public.push_save(jsonb, bigint, text) from anon;
grant execute on function public.push_save(jsonb, bigint, text) to authenticated;
