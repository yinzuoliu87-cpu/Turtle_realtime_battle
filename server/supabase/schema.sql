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
-- 2b. gauntlet_ghosts —— 周六闯关赛的快照池（E-A4, 2026-09-22）
--
--    ★★为什么**另起一张表**而不是给 ghosts 加两列：
--      · ghosts 的主键是 (account_id, season_week, battles)，里面已经有真数据 —— 换主键要迁移；
--      · 两张表的**匹配维度本来就不是一回事**：
--          ghosts          按【总场次】撮合（D5：积分赛硬条件「双方总场次相同」）
--          gauntlet_ghosts 按【战绩标签】撮合（原稿：3-1 只碰 3-1，**永不跨标签**）
--      硬塞进一张表，两个维度就会互相污染（按场次查会捞到周六的行，反之亦然）。
--
--    ★主键含 (gw, gl)：同一个人周六会**连续产出多条**（0-0 → 1-0 → 2-0 …），
--      每条都得留着 —— 后来者要按自己那一格找对手，不能只剩最新一份
--      （这正是 A6 给 ghosts 加 battles 那一维的同一个理由）。
--
--    ★保留期：与重放同一条线（U7：只活到周一），由 §5 的定时任务按 season_week 清。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.gauntlet_ghosts (
  account_id   uuid        not null references auth.users(id) on delete cascade,
  season_week  bigint      not null,
  gw           int         not null,        -- 闯关赛胜场（战绩标签的前半）
  gl           int         not null,        -- 闯关赛负场（战绩标签的后半）
  snapshot     jsonb       not null,        -- 与 ghosts 同一个 build_ghost_snapshot() 产物
  client_version text      not null,
  uploaded_at  timestamptz not null default now(),
  primary key (account_id, season_week, gw, gl)
);

-- 匹配查询：同一周 + **完全相同的标签**，按上传时刻倒序（新鲜度在客户端按 30 分钟窗口过滤，
-- 见 phase2_config.FRESH_SNAPSHOT_SEC —— 周六的窗口是**过滤**不是排序，与积分赛 D10 相反）。
create index if not exists gauntlet_match_idx
  on public.gauntlet_ghosts (season_week, gw, gl, uploaded_at desc);

alter table public.gauntlet_ghosts enable row level security;

-- 读：所有登录用户都能读（匹配要在别人的快照里挑对手）
drop policy if exists gauntlet_read_all on public.gauntlet_ghosts;
create policy gauntlet_read_all on public.gauntlet_ghosts
  for select using (auth.uid() is not null);

-- 写：只能写自己的那一行
drop policy if exists gauntlet_write_own on public.gauntlet_ghosts;
create policy gauntlet_write_own on public.gauntlet_ghosts
  for insert with check (account_id = auth.uid());

drop policy if exists gauntlet_update_own on public.gauntlet_ghosts;
create policy gauntlet_update_own on public.gauntlet_ghosts
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
-- 3b. matches.replay —— 跨设备回放 S2（2026-10-04，方案书 docs/plans/20261003-跨设备回放.md §4.6）
--    内容：一局「重算所需的全部输入」—— Godot `var_to_bytes` + deflate 的二进制，再 base64。
--      ★不用 jsonb：JSON 往返会改浮点末位（实测 0.30000000000000004 → 0.3），站位差一位第一步就分叉。
--      ★不用 bytea：PostgREST 写 bytea 要 `\x` 十六进制，体积翻倍；base64 文本最省事。
--    ★录像里有什么（2026-10-04 瘦身，方案书 docs/plans/20261003-跨设备回放.md §9.5）：matches 任何登录用户都读得到，
--      所以录像只装**重放这一场必需的**：v / client_version / seed / events（开打站位·点幕布·认输，按 sim 步号）/
--      cps（每 60 步一个 16 位校验摘要）/ end，以及 state = 开局那一刻 GameState 的 16 个变量（`ReplayRecorder.STATE_KEYS`）：
--      分路与三统领、**上场统领的**持久装备、技能选择、等级 / 糖果临时等级 / debug_level、大师技能与形象、
--      赌神命运之轮层数、宝箱财宝值与已开战利品、093 香火石刻痕与充能、dual_active、对手快照 dual_ghost（摘掉 is_bot / ghost_id）。
--      **不含**：币、邮箱、令牌、安装 id、昵称、背包 / 装备池、未上场统领的装备、赛季战绩、补报单（瘦身前这些全在里面）。
--      为什么是这 16 个：运行时量「回放那一遍读了 GameState 哪些变量」(24 个) + 逐字段变异（拿掉 ⇒ 重放分叉的才进），
--      门禁 verify_replay_roundtrip V3 / V3b / V3c 每次重新量。left_snapshot / right_snapshot 两列是对战快照（ghosts 表同一形状）。
--    一局实测：瘦身前约 2.5~2.8 KB、瘦身后约 1.6 KB（deflate 后；base64 再乘 4/3）。上限 64 KB 是二十倍以上余量，
--      ★必须与客户端 `replay_uploader.gd` 的 `REPLAY_MAX_B64` 同一个数（门禁 verify_replay_upload_retry 逐字对）。
--    客户端写法：POST 时自带 `match_id`（uuid v4，= 本地录像 id），写完**按 match_id 回读、逐字比对 replay**
--      才算传成（插入回 201 不算）——所以这张表的读策略（matches_read_all）是 S2 的前提，别收窄成「只读别人的」。
--    `right_account` 客户端恒写 null：对手是机器人时那一列没法填，填了就等于告诉所有人「这是机器人」。
--    ★没有 update / delete 策略（同上）：一场录像一旦写进去就不可改；重复 POST 撞主键回 409，客户端靠回读裁决。
-- ─────────────────────────────────────────────────────────────
alter table public.matches add column if not exists replay text;

alter table public.matches drop constraint if exists matches_replay_size;
alter table public.matches add constraint matches_replay_size
  check (replay is null
         or (octet_length(replay) between 1 and 65536
             and replay ~ '^[A-Za-z0-9+/]+={0,2}$'));

-- ─────────────────────────────────────────────────────────────
-- 3c. 周末看回放（2026-10-04，方案书 docs/plans/20261004-周末看回放.md）—— ★待用户审后上线
--    · 周六赛况板**不需要新 SQL**：客户端直接读 phase='gauntlet' 的行（只取 profile 与战绩标签，
--      见 supabase.gd `gauntlet_board_query`），走上面的 matches_read_all。
--    · 周日的录像（phase='finals'）不能让人直连读：`result.won` 就是这一场的胜负，
--      当前轮还没揭晓时读得到 = 剧透（与 finals_results「客户端一律不给直接读」同一条规矩）。
--      ⇒ 读策略收窄：决赛那几行**只有上传者自己**读得到（S2 上传后要按 match_id 回读自己那一行）；
--        别人看决赛录像只走下面的 `finals_replay()`（只给已揭晓的场次）。
--    · 客户端另有一道闸：决赛录像在那一场揭晓之前**根本不上传**（replay_uploader.finals_upload_ready），
--      所以这条策略上线之前也不剧透；它是数据层的第二道锁。
-- ─────────────────────────────────────────────────────────────
drop policy if exists matches_read_all on public.matches;
create policy matches_read_all on public.matches
  for select using (auth.uid() is not null and (phase <> 'finals' or left_account = auth.uid()));

-- 决赛录像按 (周, 种子) 找（finals_replay 用；部分索引只管决赛那几行）
create index if not exists matches_finals_idx on public.matches (season_week, seed) where phase = 'finals';

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
  title       text,                          -- D12 头衔：冠军 / 亚军(2026-10-04 加) / 四强 / 进决赛日 / 积分赛满配额。自由文本无约束、现无人写 ⇒ 加档不需迁移
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
-- 6. 重放到期自动删（U7：「周一过完就没了」，到期自动删，不靠手动）
--    口径：每周二 00:00 UTC 删掉「本周一 00:00 UTC 之前」的全部对局
--    （用户 2026-10-04：「照你原来定的，周二 0 点删」）。
--    ⇒ 服务端任何时刻留着的只有「本周的」+「（还没到本周二时）上周的」：
--      上周六/周日/周一打的，周一一整天还看得到，周二 0 点一起清掉。
--    `date_trunc('week', …)` 在 Postgres 里是 ISO 周 = 周一 00:00；先转成 UTC 再截，
--      截完再标回 UTC ⇒ 与库的时区设置无关。
--    客户端同一条口径：`scripts/systems/replay/replay_fetcher.gd` `server_keeps()`
--      （本机没有录像时，服务端已清掉的那一场不出「回放」按钮）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;
-- 2026-10-04 已上生产：cron jobid 11 'purge_old_matches' '0 0 * * 2'

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

-- ─────────────────────────────────────────────────────────────
-- 周日决赛日 (E-B3, 2026-09-23)
--
-- ★★**对阵规则不在这里写第二遍。**
--   「谁打谁 / 谁轮空 / 打几轮」的事实源是 `scripts/gamedata/bracket.gd`，
--   客户端拿「这个桶几个人」就能自己算出整张图。服务端只存三件事：
--     ① 桶里有谁（按种子）  ② 现在第几轮  ③ 哪一场谁赢了
--   —— 在 SQL 里再实现一遍座次表，就是同一判据存两份，必然漂
--   （本仓刚因为「同一判据五份副本」付过代价）。
--
-- ★★**不剧透靠"客户端拿不到"，不靠"拿到了不显示"**：
--   读接口 `finals_view()` **只返回 round < 当前轮 的结果**。
--   后者一个渲染 bug 就漏，而且没人会发现漏了。
-- ─────────────────────────────────────────────────────────────

-- 一个桶
create table if not exists public.finals_buckets (
  season_week  bigint      not null,
  bucket_no    int         not null,
  n            int         not null,          -- 桶里几个人（客户端据此算出整张图）
  round        int         not null default 1,-- 现在进行到第几轮（1 起）
  round_at     timestamptz not null default now(),  -- 本轮开始时刻
  closed       boolean     not null default false,
  primary key (season_week, bucket_no)
);

-- 桶里的人（按种子号）
create table if not exists public.finals_entrants (
  season_week  bigint      not null,
  bucket_no    int         not null,
  seed         int         not null,          -- 0 起，0 = 最高种子
  account_id   uuid        not null references auth.users(id) on delete cascade,
  name         text        not null,
  snapshot     jsonb       not null,          -- 快照代打用的阵容（D8）
  primary key (season_week, bucket_no, seed)
);

-- 每一场的结果
create table if not exists public.finals_results (
  season_week  bigint      not null,
  bucket_no    int         not null,
  round        int         not null,
  match_no     int         not null,
  winner_side  int         not null,          -- 0 = 上侧, 1 = 下侧
  seed_used    bigint      not null,          -- 确定性重算用的种子（B 阶段）
  decided_at   timestamptz not null default now(),
  primary key (season_week, bucket_no, round, match_no)
);

create index if not exists finals_ent_idx on public.finals_entrants (season_week, bucket_no);
create index if not exists finals_res_idx on public.finals_results (season_week, bucket_no, round);

alter table public.finals_buckets  enable row level security;
alter table public.finals_entrants enable row level security;
alter table public.finals_results  enable row level security;

-- 读：登录用户都能读桶与参赛者（观赛是公开的，原稿：重放全公开）
drop policy if exists finals_b_read on public.finals_buckets;
create policy finals_b_read on public.finals_buckets for select using (auth.uid() is not null);
-- ★★2026-09-25 收掉了 `finals_e_read`(原来是 `select using (auth.uid() is not null)`):
--   它把 **snapshot 列一起放出去了** ⇒ 任何登录用户直连 `/rest/v1/finals_entrants`
--   就能拿到全桶所有人的阵容 ⇒ E-B4 那套「每人每轮只能问一个对手」当场作废
--   (绕开 `finals_opponent` 直接读表就行), 连带 E-B2 定的「不剧透做在数据层」也破了。
-- ★这不是「收紧」, 是本来就不该开: 客户端**零个地方**直连读这张表 ——
--   全走 `finals_view`(security definer, 绕 RLS, 只下发 seed/name/account_id)。
-- ★抓到它的是 `probe_finals_server.py` ⑱ 的最后一条判据(我为这套限流专门配的
--   「绕不绕得过去」那一条), 它当场红了。判据要刚好卡住那个形状, 这就是一例。
-- ⚠ RLS 是**行**级的, 挡不住「只想藏一列」—— 所以只能整条收掉, 或者改成列级 grant。
--   这里选整条收掉: 没有任何消费者, 列级 grant 反而多一份要维护的名单。
drop policy if exists finals_e_read on public.finals_entrants;

-- ★★结果表**客户端一律不给直接读**（只有 select 策略缺席 = 读不到）——
--   要读只能走 `finals_view()`，那里会把当前轮挡掉。
--   给了直接读的口子，"不剧透"就只剩一层渲染侧的自觉。
-- ★三张表都**不给客户端写**：只有下面的 security definer 函数能动它们。

-- ─────────────────────────────────────────────────────────────
-- ★「一轮多长」= 3 分钟购物 + 结算 + 4 分钟重放 ≈ 8 分钟。
--   **这个数只在这里有一份**：读接口把 `next_at`（下一轮开始时刻）算好一起下发，
--   客户端不存副本 —— 它要显示「下一轮 3:42 后开始」，拿 `next_at` 减一下就行。
--   （同一个数存两份必然漂；**消掉重复比再写一条同步门禁好**。）
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_round_sec()
returns int language sql immutable as $$ select 480 $$;
grant execute on function public.finals_round_sec() to authenticated, anon;

-- ─────────────────────────────────────────────────────────────
-- 读接口：只给**已翻面**的结果
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_view(p_week bigint, p_bucket int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; ents jsonb; res jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★p_bucket < 0 = 「我那个桶」。客户端并不知道自己被分到哪个桶(分桶是服务端做的),
  --   分成两次往返去问会出现「查到桶号、桶却没了」的中间态, 所以并到这一次里。
  if p_bucket < 0 then
    select e.bucket_no into p_bucket from public.finals_entrants e
     where e.season_week = p_week and e.account_id = auth.uid()
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
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★下一轮开始时刻: 客户端拿这个倒计时, 不必知道「一轮多长」
    'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
    'now', extract(epoch from now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res);
end $$;

revoke all on function public.finals_view(bigint, int) from public;
revoke execute on function public.finals_view(bigint, int) from anon;
grant execute on function public.finals_view(bigint, int) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 观赛读接口 (2026-10-04)：本周**所有组**的对阵与【已翻面】结果，任何登录用户都能读
--
-- ★为什么要有它：`finals_view(week, -1)` 只回「我那个组」，没晋级的人拿到 `not_entered`，
--   整个周日只看得到一把锁。原案 D13「观赛四块全做」；`finals_buckets` 的读策略本来就写着
--   「观赛是公开的」。冠军页也要它：各组冠军汇总，客户端原来只有自己那一组。
-- ★★不剧透与 `finals_view` 同一条规矩、一字不差：`b.closed or r.round < b.round`。
--   当前轮的胜负**根本不下发**（客户端 `_bucket_from` 照同一条再筛一遍，第二道锁）。
-- ★只下发 名字 / account_id（客户端据此现算 #玩家ID，算法只在 phase2_config.player_tag 一份）/ 结果。
--   **不碰 `snapshot` 列**（阵容只能经 `finals_opponent` 每人每轮问一次，见 2026-09-25 收掉 finals_e_read 那段）。
--   account_id 的暴露面与 `finals_view(week, <任意组号>)` 现状相同，没有新增。
-- ★没部署之前客户端拿到 404，按「这条路暂时没有」处理，屏幕退回「未晋级」，不报错。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_week_view(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare bs jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           'entrants', (select coalesce(jsonb_agg(jsonb_build_object(
                           'seed', e.seed, 'name', e.name, 'account_id', e.account_id)
                         order by e.seed), '[]'::jsonb)
                          from public.finals_entrants e
                         where e.season_week = p_week and e.bucket_no = b.bucket_no),
           'done', (select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
                      from public.finals_results r
                     where r.season_week = p_week and r.bucket_no = b.bucket_no
                       and (b.closed or r.round < b.round)))
         order by b.bucket_no), '[]'::jsonb)
    into bs from public.finals_buckets b
   where b.season_week = p_week;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from now())::bigint, 'buckets', bs);
end $$;

revoke all on function public.finals_week_view(bigint) from public;
revoke execute on function public.finals_week_view(bigint) from anon;
grant execute on function public.finals_week_view(bigint) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 赛程推进器：本轮时间到了 **且** 本轮该打的都打完了 → 进下一轮
-- ★由 pg_cron 每分钟叫一次。离线版没有"收盘"这个事件，
--   而 pg_cron 就是把"到点了"这件事做成真事件的最便宜办法。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_advance(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; moved int := 0; want int; got int; slots int; total int;
        real_want int;
begin
  for b in select * from public.finals_buckets
            where season_week = p_week and not closed loop
    -- 本轮时间还没到就跳过（3 分钟购物 + 结算 + 4 分钟重放 ≈ 8 分钟）
    if now() < b.round_at + make_interval(secs => public.finals_round_sec()) then
      continue;
    end if;
    -- 补到 2 的幂 → 总轮数 / 本轮该有几场
    slots := 1; total := 0;
    while slots < b.n loop slots := slots * 2; total := total + 1; end loop;
    want := slots / (2 ^ b.round)::int;
    select count(*) into got from public.finals_results
     where season_week = p_week and bucket_no = b.bucket_no and round = b.round;
    -- ★没打完就不推 —— 宁可晚一分钟, 也不能把没结果的一轮翻面
    -- ★★但「不推」不能没有上限(2026-09-25 查出来的死锁): 原来这里是无条件 continue,
    --   于是**只要有一场没人报结果, 那个桶就永远不动**。注释当时写的是「宁可晚一分钟」,
    --   实际是永远。而测试期人数个位数, 周日晚上「双方都不在线」几乎是常态。
    -- ★★★2026-09-26: 只等【真的有人打的那几场】, 不等轮空。
    --   轮空那几场**没有任何客户端会报结果** —— 客户端只在打完一局后报, 轮空没有局。
    --   原来把它们也算进 `want` ⇒ 只要本轮有轮空, `got < want` 恒成立 ⇒ **必等满
    --   960 秒宽限**, 而客户端倒计时是 `round_at + finals_round_sec()`(480)
    --   ⇒ 第 8 分钟起屏幕显示「下一轮 0:00 后开播」并冻住整整 8 分钟, 然后突然跳轮。
    --   10 人规模实测形状: slots=16、第 1 轮 8 场里**只有 2 场是真的**
    --   ⇒ 10 个人里 6 个人第一轮什么都不打, 干等 16 分钟。
    -- ★算轮空场数**不需要**知道座次表(那是 E-B3 定在客户端的规则, SQL 里不写第二遍):
    --   第 1 轮有 `slots - n` 个空位, 每个空位让它那一场变成轮空
    --   ⇒ 真实场次 = `n - slots/2`。(n=10,slots=16 ⇒ 2; n=3,slots=4 ⇒ 1, 与手算一致。)
    --   第 2 轮起所有席位都被上一轮的晋级者填满(轮空者也晋级) ⇒ 全是真实场次。
    real_want := want;
    if b.round = 1 then
      real_want := greatest(0, b.n - slots / 2);
    end if;
    if got < real_want then
      -- 宽限期内: 真的等一等。★取 2 倍而不是 1 倍 —— 本函数每分钟才叫一次,
      --   且真有人在打时最后一场可能压着点报上来; 1 倍会把**正在打的比赛**判掉。
      if now() < b.round_at + make_interval(secs => public.finals_round_sec() * 2) then
        continue;
      end if;
      -- ★过了宽限期还缺 ⇒ 补判: 缺哪场补哪场, 一律 **side 0(上半区)晋级**。
      -- ★为什么是「上半区」不是「高种子」: 服务端**算不出**第 N 轮某一场里是谁 ——
      --   算得出就等于在 SQL 里写了第二遍对阵规则(E-B3 定的那条)。
      --   而 side 0 不需要知道任何对阵规则: 缺哪个 match_no 就补哪个。
      --   第一轮里上半区恰好就是高种子(座次表 [0,7,3,4,1,6,2,5] ⇒ 0vs7/3vs4/1vs6/2vs5),
      --   后续轮它是上半区那条路径, **不保证**是当时的高种子 —— 照实说, 不吹成「高种子晋级」。
      -- ★`do nothing` 保证**已经打完的那几场一个字都不动**。
      null;   -- 补判由下面那条无条件的 insert 做(见它的注释)
    end if;
    -- ★★这条 insert **无条件**跑, 而不是只在"过了宽限期"时跑:
    --   它要补的有两类, 而 `do nothing` 保证**已经打完的一场都不动**:
    --     ① 轮空 —— 本来就没人会报, 真实场次一打完就该补上, 不该拖到宽限期
    --     ② 过了宽限期还没人报的真实场次 —— 原来的用途
    insert into public.finals_results
      (season_week, bucket_no, round, match_no, winner_side, seed_used)
      select p_week, b.bucket_no, b.round, g.m, 0, 0
        from generate_series(0, want - 1) as g(m)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    if b.round >= total then
      update public.finals_buckets set closed = true
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;

revoke all on function public.finals_advance(bigint) from public;
revoke execute on function public.finals_advance(bigint) from anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 周日决赛日的【写入】(E-B3 下半, 2026-09-23)
--
-- ★★切桶的规则**只有这一份在执行**。客户端的 `bracket.gd` 里那三个同名函数
--   (`bucket_size_for` / `bucket_count` / `bucket_of_seed`)在产品代码里零个调用者 ——
--   它们是**规格**, 有 41 条门禁守着; 这里是**实现**。
--   两边由 `tools/probe_finals_server.py` 的 ⑮ 段逐个人数比对钉在一起。
--   （客户端从回包里只拿「这个桶几个人」, 整张图按它自己算 ⇒ 不需要知道怎么切的。）
-- ─────────────────────────────────────────────────────────────

-- 报名台: 周六闯关赛晋级的人自己报到
create table if not exists public.finals_pending (
  season_week  bigint      not null,
  account_id   uuid        not null references auth.users(id) on delete cascade,
  name         text        not null,
  snapshot     jsonb       not null,       -- 快照代打用的阵容（D8）
  gw           int         not null,       -- 闯关赛战绩（种子排序用）
  gl           int         not null,
  entered_at   timestamptz not null default now(),
  primary key (season_week, account_id)
);
alter table public.finals_pending enable row level security;
-- ★只能看见自己那一行: 「谁报名了」本身就是情报(能数出今晚有多少人、谁在)
drop policy if exists finals_p_self on public.finals_pending;
create policy finals_p_self on public.finals_pending for select
  using (auth.uid() = account_id);
-- 写一律走下面的函数（表上不给 insert/update 策略）

-- ─────────────────────────────────────────────────────────────
-- ① 报到
-- ★晋级线在服务端判(`p_gw >= 线`), 不信客户端说的"我晋级了"这句话本身;
--   但 gw/gl 这两个数现在仍是客户端报的 —— 与排行榜、快照池同一个信任模型,
--   服务端复算是 B 阶段第二步的事。**这一点是已知缺口, 不假装它不存在。**
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_enter(p_week bigint, p_name text,
    p_snapshot jsonb, p_gw int, p_gl int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare floor_wins int := 4;   -- = phase2_config.GAUNTLET_WINS_IN(周六 4 胜晋级)
  -- ★★2026-09-25 修: 原来写的是 5, 注释说「与 PROMOTE_WINS_FLOOR 同值」——
  --   但 `p_gw` 传进来的是 **gauntlet_wins(周六胜场)**, 而 PROMOTE_WINS_FLOOR 是
  --   **积分赛→周六**那条线(比的是 season_wins)。**两个不同的量被当成了同一个。**
  --   后果: 周六 4 胜晋级的人 gauntlet_wins=4 < 5 ⇒ 被拒;
  --   而 4 胜之后 `gauntlet_state()` 就返回「晋级」、开局闸不让再打 ⇒ 永远到不了 5
  --   ⇒ **没有任何人进得了周日**。正确的线就是周六那条: 4 胜。
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if coalesce(p_gw, 0) < floor_wins then
    return jsonb_build_object('ok', false, 'reason', 'not_qualified', 'need', floor_wins);
  end if;
  -- ★已经开赛就不收了: 桶已经坐定, 这时塞人会让别人的对阵图当场变形
  if exists (select 1 from public.finals_buckets where season_week = p_week) then
    return jsonb_build_object('ok', false, 'reason', 'already_seated');
  end if;
  insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
    values (p_week, auth.uid(), coalesce(p_name, '?'), coalesce(p_snapshot, '{}'::jsonb),
            p_gw, coalesce(p_gl, 0))
    on conflict (season_week, account_id) do update
      set name = excluded.name, snapshot = excluded.snapshot,
          gw = excluded.gw, gl = excluded.gl;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.finals_enter(bigint, text, jsonb, int, int) from public;
revoke execute on function public.finals_enter(bigint, text, jsonb, int, int) from anon;
grant execute on function public.finals_enter(bigint, text, jsonb, int, int) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 切桶规则（规格在 scripts/gamedata/bracket.gd，探针逐个人数比对）
-- ─────────────────────────────────────────────────────────────
-- 一个桶装多少: >16 → 32；≤16 → 16；依次减半到 4。
-- ⚠ 人数比 4 还少时**不再减半**，直接返回人数本身 ——
--   2 个人分成两个「1 人桶」会造出一个没有对手的冠军，那不是比赛。
create or replace function public.finals_bucket_size(n int)
returns int language sql immutable as $$
  select case
    when n <= 0 then 0
    when n < 4  then n
    when n > 16 then 32
    when n > 8  then 16
    when n > 4  then 8
    else 4
  end
$$;

-- 分几个桶：向上取整（剩下的人不能没地方去）
create or replace function public.finals_bucket_count(n int)
returns int language sql immutable as $$
  select case when public.finals_bucket_size(n) <= 0 then 0
              else ceil(n::numeric / public.finals_bucket_size(n))::int end
$$;

-- 蛇形切桶：第 i 号种子（0 = 最高）进哪个桶。1,2,3,4 / 4,3,2,1 / 1,2,3,4 …… 来回走。
-- ★目的是强度均匀 —— 顺序切（前 32 名全进 1 号桶）会造出一个死亡之桶。
create or replace function public.finals_bucket_of(seed_idx int, n_buckets int)
returns int language sql immutable as $$
  select case
    when n_buckets <= 1 or seed_idx < 0 then 0
    when (seed_idx / n_buckets) % 2 = 0 then seed_idx % n_buckets
    else n_buckets - 1 - (seed_idx % n_buckets)
  end
$$;

-- ─────────────────────────────────────────────────────────────
-- ② 坐下: 周日开赛前一次性切桶。★幂等 —— 已经坐过就不动
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare total int; nb int; r record; i int := 0; seats int[] := '{}'; b int;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week) then
    return 0;                      -- 已经坐定了, 再叫一次什么都不做
  end if;
  select count(*) into total from public.finals_pending where season_week = p_week;
  if total < 2 then
    return 0;                      -- 一个人不成比赛
  end if;
  nb := public.finals_bucket_count(total);
  -- 每个桶下一个空位的序号
  for i in 1..nb loop seats := array_append(seats, 0); end loop;
  i := 0;
  -- ★排序 = 种子顺序: 胜场多的在前, 同胜场负场少的在前, 再同就按 account_id 定死
  --   (**必须有一个确定性的最后一项**, 否则同分的人每次查出来的顺序都不同)
  for r in select * from public.finals_pending
            where season_week = p_week
            order by gw desc, gl asc, account_id loop
    b := public.finals_bucket_of(i, nb);
    insert into public.finals_entrants
      (season_week, bucket_no, seed, account_id, name, snapshot)
      values (p_week, b, seats[b + 1], r.account_id, r.name, r.snapshot);
    seats[b + 1] := seats[b + 1] + 1;
    i := i + 1;
  end loop;
  -- 桶本身（n = 这个桶真实坐了几个人，可能比容量少）
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
    select p_week, bucket_no, count(*)::int, 1, now(), false
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;

revoke all on function public.finals_seat(bigint) from public;
revoke execute on function public.finals_seat(bigint) from anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- ③ 报结果。★只有**这一场的参赛者**报得了, 而且只能报**当前轮**
-- ★幂等: 同一场重复报不覆盖(先到先得) —— 两边都会报, 谁先到都一样
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  -- ★只收当前轮: 收旧轮的等于允许改已经翻过面的结果; 收未来轮等于提前定胜负
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  -- ★报的人必须是这个桶里的人。**"是不是这一场的人"客户端说了不算**, 但
  --   "在不在这个桶里"服务端查得到; 精确到"这一场"需要服务端自己推对阵树,
  --   那就是把对阵规则在 SQL 里写第二遍了 ⇒ 这里只挡到桶级, 差额记在下面的注释里。
  -- ⚠ 已知缺口: 同桶的旁观者能替别人报一场。与排行榜/快照池同一个信任模型,
  --   服务端复算是 B 阶段第二步的事 —— 不假装它不存在。
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_winner_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'bad_side');
  end if;
  insert into public.finals_results
    (season_week, bucket_no, round, match_no, winner_side, seed_used)
    values (p_week, p_bucket, p_round, p_match, p_winner_side, coalesce(p_seed, 0))
    on conflict (season_week, bucket_no, round, match_no) do nothing;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.finals_report(bigint, int, int, int, int, bigint) from public;
revoke execute on function public.finals_report(bigint, int, int, int, int, bigint) from anon;
grant execute on function public.finals_report(bigint, int, int, int, int, bigint) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- ③b 看回放（周末看回放 2026-10-04, docs/plans/20261004-周末看回放.md）—— ★待用户审后上线
--
-- ★给谁：任何登录用户（观赛是公开的；没晋级的人也能点已揭晓的格子）。
-- ★只给**已揭晓**的场次：与 `finals_view` 同一条规矩、一字不差 —— `b.closed or p_round < b.round`。
-- ★只给**裁判采纳的那一份**：周日一场双方各在本机打对方的快照, 两边都可能上传录像；
--   `finals_report` 先到先得, 存下的 `seed_used` 就是**先报那一方**那一局的种子
--   （客户端报的是 `GameState.battle_seed`, 录像里的 `seed` 是同一个数, 门禁 verify_weekend_replay 核过）。
--   ⇒ 按 (周, 组, 轮, 场) + `seed = seed_used` 认出来, 不必给 finals_results 加「谁报的」列。
--   超时补判(finals_advance)的场次 seed_used 可能是 0 ⇒ 没有录像, 回 no_replay。
-- ★上传者必须真是这个组的人（防有人往 matches 里塞一行同坐标同种子的假录像来冒充）。
-- ★没部署之前客户端拿到 404 ⇒ 那一格点了说「这场的回放还没开放」, 不报错。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_replay(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b record; sd bigint; mid uuid; rp text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if not (b.closed or p_round < b.round) then
    return jsonb_build_object('ok', false, 'reason', 'not_revealed');
  end if;
  select r.seed_used into sd from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and r.round = p_round and r.match_no = p_match;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_result');
  end if;
  if coalesce(sd, 0) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'no_replay');
  end if;
  select m.match_id, m.replay into mid, rp from public.matches m
   where m.season_week = p_week and m.phase = 'finals' and m.seed = sd
     and m.replay is not null
     and m.result->>'fb' = p_bucket::text
     and m.result->>'fr' = p_round::text
     and m.result->>'fm' = p_match::text
     and exists (select 1 from public.finals_entrants e
                  where e.season_week = p_week and e.bucket_no = p_bucket
                    and e.account_id = m.left_account)
   order by m.created_at
   limit 1;
  if mid is null then
    return jsonb_build_object('ok', false, 'reason', 'no_replay');
  end if;
  return jsonb_build_object('ok', true, 'match_id', mid, 'replay', rp);
end $$;

revoke all on function public.finals_replay(bigint, int, int, int) from public;
revoke execute on function public.finals_replay(bigint, int, int, int) from anon;
grant execute on function public.finals_replay(bigint, int, int, int) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- ④ 对手快照（E-B4 快照代打, 2026-09-25）
--
-- ★★为什么不是把 snapshot 塞进 `finals_view`:
--   那等于把**全桶所有人的阵容**发给所有人 —— 既是剧透, 也是侦察优势,
--   与 E-B2 定的「不剧透做在数据层」直接冲突。
--
-- ★★为什么服务端不自己算「你的对手是谁」:
--   算得出就等于把对阵规则在 SQL 里写第二遍(E-B3 定死的那条)。
--   ⇒ 改成客户端说「我认为本轮对手是几号种子」, 服务端只校验**它查得到的部分**。
--
-- ★★那怎么防「把全桶挨个问一遍」:
--   **每人每轮只能问一个种子**(下面这张表, 主键到 account_id, 先到先得)。
--   问错了只是浪费掉自己这一轮唯一一次机会 —— **骗人只坑自己**。
--   这样既不泄露别人的阵容, 又不需要服务端知道谁打谁。
-- ─────────────────────────────────────────────────────────────
create table if not exists public.finals_scout (
  season_week  bigint      not null,
  bucket_no    int         not null,
  round        int         not null,
  account_id   uuid        not null references auth.users(id) on delete cascade,
  seed         int         not null,          -- 这一轮问过的那一个种子
  asked_at     timestamptz not null default now(),
  primary key (season_week, bucket_no, round, account_id)
);
alter table public.finals_scout enable row level security;
-- ★一条客户端策略都不给: 只有下面这个 security definer 函数碰得到它。
--   「谁问过谁」本身就是情报(能看出别人算出的对手是谁)。

create or replace function public.finals_opponent(p_week bigint, p_bucket int,
    p_round int, p_seed int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; asked int; snap jsonb; nm text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  -- ★只给当前轮: 问旧轮没意义(打完了), 问未来轮等于提前侦察
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_seed = mine then
    return jsonb_build_object('ok', false, 'reason', 'thats_you');
  end if;
  -- ★先确认这个种子真的存在, **再**记账 —— 反过来的话, 问一个不存在的号
  --   会白白烧掉自己这一轮唯一的机会。存不存在不算情报(桶里几个人 finals_view 本来就给)。
  select snapshot, name into snap, nm from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and seed = p_seed;
  if snap is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_seed');
  end if;
  -- ★每人每轮只能问一个: 先到先得
  insert into public.finals_scout (season_week, bucket_no, round, account_id, seed)
    values (p_week, p_bucket, p_round, auth.uid(), p_seed)
    on conflict (season_week, bucket_no, round, account_id) do nothing;
  select seed into asked from public.finals_scout
   where season_week = p_week and bucket_no = p_bucket
     and round = p_round and account_id = auth.uid();
  if asked <> p_seed then
    -- ★把第一次问的那个号告诉它 —— 不然客户端只知道"拿不到", 不知道为什么,
    --   也没法把"我算出来的对手"和"我实际问过的"对上
    return jsonb_build_object('ok', false, 'reason', 'already_asked', 'seed', asked);
  end if;
  return jsonb_build_object('ok', true, 'seed', p_seed, 'name', nm, 'snapshot', snap);
end $$;

revoke all on function public.finals_opponent(bigint, int, int, int) from public;
revoke execute on function public.finals_opponent(bigint, int, int, int) from anon;
grant execute on function public.finals_opponent(bigint, int, int, int) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 线上 pg_cron 任务（2026-10-04 从真库 `cron.job` 只读抄来；原来仓库里没有记录）
--   jobid 1  '* * * * 0'          select public.finals_advance(<本周一 00:00 UTC 的 epoch>)   周日每分钟推进轮次/补判
--   jobid 5  '*/10 8-23 * * 0'    select public.finals_seat(<同上>)                          周日 08:00 起每 10 分钟分桶
--   周号写法: (extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint) —— 与客户端 week_anchor_ts 一致(已核)。
--   ★客户端 phase2_config.FINALS_SEAT_HOUR_UTC 必须等于 jobid 5 的首个小时(8)。
-- ─────────────────────────────────────────────────────────────

-- ═══ 垃圾匿名账号清理(2026-10-04 已上生产·cron jobid 9·每天 04:30 UTC) ═══
-- 当天先手工删了 585 个(测试机/CI/探针脚本造的, 零真人; 保留手机上建的那 1 个)。根因是门禁冒烟没关后端(v0.19.533 已修)。
-- 2026-10-04 用户「删，想办法处理，未来也可能有」:
-- 每天清一次「匿名、没绑邮箱、14 天没登录、在任何数据表里都没有一行」的账号。
-- 客户端拿到 user_not_found / refresh 失效会自动重新匿名注册(supabase.gd DEAD_REFRESH_CODES), 没数据的号删了不丢东西。
create or replace function public.purge_junk_anon_users() returns integer
language plpgsql security definer set search_path = public, auth as $$
declare n integer;
begin
  delete from auth.users u
  where u.is_anonymous and coalesce(u.email, '') = ''
    and coalesce(u.last_sign_in_at, u.created_at) < now() - interval '14 days'
    and not exists (select 1 from public.ghosts x where x.account_id = u.id)
    and not exists (select 1 from public.gauntlet_ghosts x where x.account_id = u.id)
    and not exists (select 1 from public.saves x where x.account_id = u.id)
    and not exists (select 1 from public.standings x where x.account_id = u.id)
    and not exists (select 1 from public.matches x where x.left_account = u.id or x.right_account = u.id)
    and not exists (select 1 from public.finals_entrants x where x.account_id = u.id)
    and not exists (select 1 from public.finals_pending x where x.account_id = u.id)
    and not exists (select 1 from public.finals_scout x where x.account_id = u.id)
    and not exists (select 1 from public.accounts x where x.account_id = u.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.purge_junk_anon_users() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'purge_junk_anon_users';
select cron.schedule('purge_junk_anon_users', '30 4 * * *', 'select public.purge_junk_anon_users()');

-- >>> BEGIN week_leaderboard 20261006-A2 >>>
-- ─────────────────────────────────────────────────────────────
-- 本周排行榜（2026-10-06 · 60 人实操严重项 A2）—— ★待用户审后上线
--
-- ★为什么要有它：客户端原来拿**本机的对手快照池**拼排行榜（`Backend.leaderboard`）。
--   新玩家只拉过场次 N / N+1 的快照（PULL_BATTLES_AHEAD），于是榜上每个人都冻在
--   「1 胜 · 6 命」—— 实操截图前 9 行全是 1 胜，而那几个号几小时前已经打到 9-6 / 10-6。
--   那是「我碰巧拉到过的那一份」，不是排行榜。
-- ★`standings` 表从来没人写过，不能当数据源 ⇒ 直接从 `ghosts` 算。
--
-- ★口径（与客户端本地榜同一套，不另立）：
--   · 本周 = `season_week = p_week`（周锚点，与上传那一侧 `GameState.week_anchor_ts` 同一个数）
--   · 每个账号只取**最新**那一行：场次最大的那份（同场次取上传最晚）。
--     ★按场次而不按上传时刻：上传队列会重试，晚到的可能是旧场次；场次才是单调的进度。
--   · 排序 = 胜场 → 余命 → 横扫（`Backend.leaderboard` 的 `cmp`，A8 定的字典序）；
--     全平再按先到者在前（`uploaded_at`），最后按 account_id 定死次序。
--   · 不上榜：陪练（`ghost_id` 以 `seed_` 开头 —— `Backend.is_sparring` 的唯一判据）
--     与机器人（`is_bot = true` —— `make_bot` 盖的章）。正常客户端两种都不上传，这两条是防线。
--     「自己」不排除：服务端榜上的我就是我上传的最新一份，客户端按 account_id 认出来钉住。
-- ★只读：不建表、不改表、不写任何一行。只加一个函数 + 授权。
-- ★下发 名字 / 玩家 ID（快照 profile.tag）/ account_id / 三个成绩 / 名次。**不碰阵容**。
--   account_id 的暴露面与现状相同（`ghosts_read_all` 本来就对登录用户整表可读）。
-- ★`me` = 我自己那一行（不在前 N 名里也给，名次是全榜真名次）；本周没传过 ⇒ null。
-- ★没部署之前客户端拿到 404 ⇒ 退回本机榜并标「本机记录」，不报错。
-- ★性能：`ghosts_match_idx (season_week, battles, uploaded_at desc)` 的首列就是 season_week。
-- ─────────────────────────────────────────────────────────────
create or replace function public.week_leaderboard(p_week bigint, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; tot int; top jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 30), 1), 100);
  with latest as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), ranked as (
    select l.*, row_number() over (
             order by l.season_wins desc, l.hearts desc, l.season_sweeps desc,
                      l.uploaded_at asc, l.account_id) as rk
      from latest l
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps) order by r.rk) filter (where r.rk <= lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps)) filter (where r.account_id = auth.uid())) -> 0
    into tot, top, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot,
    'rows', top, 'me', mine);
end $$;

revoke all on function public.week_leaderboard(bigint, int) from public;
revoke execute on function public.week_leaderboard(bigint, int) from anon;
grant execute on function public.week_leaderboard(bigint, int) to authenticated;
-- <<< END week_leaderboard 20261006-A2 <<<

-- >>> BEGIN week_leaderboard_v2 20261006b >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜 v2（2026-10-06 · 用户「积分赛写上名字，剩余生命，胜场，总场次啊，都给我做」）—— ★待主会话审后上线
--
-- ★相对 v1（20261006_week_leaderboard.sql）只**加两个下发字段**，口径一个字没动：
--   · `battles` —— 总场次 = 该账号本周**最新那一行**的 `ghosts.battles`
--     （每账号取最新一行本来就是按 battles desc 取的 ⇒ 它就是本周打到第几场）。
--   · `title`   —— `standings.title`（D12 头衔那一列）。⚠ **现在没有任何人写这一列**
--     （schema.sql §4 原注「自由文本无约束、现无人写」）⇒ 上线后恒为 null；
--     留着是为了 D7 写入端落地那天客户端不用再发版。
--     冠军 / 亚军 / 四强 / 进决赛日 现在由客户端从 `finals_week_view(p_week)` 现算
--     （座次表只在客户端 `bracket.gd` 一份，SQL 不写第二遍 —— 见 finals 段头注）。
-- ★排序不变：胜场 → 余命 → 横扫（横扫不上屏，但仍参与同分排序）→ 先到者 → account_id。
-- ★签名不变（p_week bigint, p_limit int）⇒ `create or replace` 原地换函数体，授权照旧。
-- ★周一看「上周终榜」= 客户端传上周的周锚点。`ghosts` 没有任何定时清理
--   （全库 cron 只有 purge_old_matches 删 matches、purge_junk_anon_users 删「在任何表里都没有一行」的匿名号），
--   ⇒ 上周的行周一照样在。
-- ★只读：不建表、不改表、不写任何一行。
-- ─────────────────────────────────────────────────────────────
create or replace function public.week_leaderboard(p_week bigint, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; tot int; top jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 30), 1), 100);
  with latest as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), ranked as (
    select l.*, s.title, row_number() over (
             order by l.season_wins desc, l.hearts desc, l.season_sweeps desc,
                      l.uploaded_at asc, l.account_id) as rk
      from latest l
      left join public.standings s
        on s.season_week = p_week and s.account_id = l.account_id
  )
  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, '')) order by r.rk) filter (where r.rk <= lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, top, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot,
    'rows', top, 'me', mine);
end $$;

revoke all on function public.week_leaderboard(bigint, int) from public;
revoke execute on function public.week_leaderboard(bigint, int) from anon;
grant execute on function public.week_leaderboard(bigint, int) to authenticated;
-- <<< END week_leaderboard_v2 20261006b <<<
