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

-- >>> BEGIN live_matches 20261007 >>>
-- ─────────────────────────────────────────────────────────────
-- 实时观赛（2026-10-07 · 方案书 docs/plans/20261007-实时观赛.md）—— ★待主会话审后上线
--   用户原话：「观赛和回放是两码事明白吗」「周六即有回放也有正在打的啊」
--
-- 两件事：
--   ① 周六·正在打的（真直播）：新表 `live_matches`。打的人开打（第一路 fight）就建一行，
--      之后每出现一个事件、以及每 3 秒心跳一次，**整行覆盖**（upsert）成「到目前为止的录像」+
--      「已推进到的 sim 步号 horizon」；打完写 ended = true。观众按 match_id 每 2~3 秒读一次，
--      本机重算追到 horizon 之前（录像格式与 matches.replay 完全相同）。
--   ② 周日·逐轮开播：`finals_buckets` 补一列 `revealed_at`（最近一次翻面的时刻）。
--      原来只有 `round_at`（本轮开始时刻）：没收盘时它恰好等于上一轮的翻面时刻，
--      但**收盘那一下不改 round_at** ⇒ 决赛那一轮翻面的时刻没有任何地方记着。
--      `finals_advance` 两条 update 都写 revealed_at = now()；`finals_view` / `finals_week_view`
--      下发 revealed_at（周视图另补 round_at）。客户端按「翻面时刻 + 一场时长 + 缓冲」算开播窗口，
--      窗口内对阵图不显示胜负。没上线时客户端退回 round_at（没收盘的组照样有开播窗口；
--      收盘的组没有 revealed_at ⇒ 不开播、直接显示结果），不报错。
--
-- ★本文件只建表 / 加列 / 换函数体，不删任何数据。重复执行安全（if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① live_matches ═══
create table if not exists public.live_matches (
  match_id       uuid        primary key,               -- = 打完之后 matches.match_id（同一个 uuid，客户端开打时就定下）
  season_week    bigint      not null,
  account_id     uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  phase          text        not null default 'gauntlet',
  left_snapshot  jsonb       not null,                  -- 只放 {profile, leaders}（名字 / 头像 / #ID / 三统领），不放阵容装备
  right_snapshot jsonb       not null,                  -- 同上；客户端上传前摘掉 is_bot / ghost_id
  replay         text        not null,                  -- 到目前为止的录像（var_to_bytes + deflate + base64，同 matches.replay）
  horizon        int         not null default 0,        -- 打的人已推进到的 sim 步号：观众只许重算到这一步
  ended          boolean     not null default false,
  client_version text        not null,
  started_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.live_matches drop constraint if exists live_matches_phase;
alter table public.live_matches add constraint live_matches_phase check (phase = 'gauntlet');
-- ★上限与 matches_replay_size 同一个数（客户端 replay_uploader.REPLAY_MAX_B64；门禁 verify_live_spectate 逐字对）。
alter table public.live_matches drop constraint if exists live_matches_replay_size;
alter table public.live_matches add constraint live_matches_replay_size
  check (octet_length(replay) between 1 and 65536 and replay ~ '^[A-Za-z0-9+/]+={0,2}$');
alter table public.live_matches drop constraint if exists live_matches_horizon;
alter table public.live_matches add constraint live_matches_horizon check (horizon between 0 and 1000000);

create index if not exists live_matches_week_idx on public.live_matches (season_week, updated_at desc);

-- ★时间戳由服务端定：客户端写不了 started_at / updated_at（赛况板按 updated_at 判「还在打吗」，
--   客户端能写就能把一场断线的直播挂在板上一整天）。顺带：主人、周、开打时刻不许改；ended 只能 false → true。
create or replace function public.live_matches_stamp() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.started_at := now();
    new.updated_at := now();
    return new;
  end if;
  new.account_id  := old.account_id;
  new.season_week := old.season_week;
  new.started_at  := old.started_at;
  new.ended       := old.ended or new.ended;
  new.updated_at  := now();
  return new;
end $$;

drop trigger if exists live_matches_stamp on public.live_matches;
create trigger live_matches_stamp before insert or update on public.live_matches
  for each row execute function public.live_matches_stamp();

alter table public.live_matches enable row level security;

-- 读：登录用户，只读**本周**开打的（周界 = 周一 00:00 UTC，与 purge_old_matches / 客户端 week_anchor_ts 同一条口径）。
drop policy if exists live_read_week on public.live_matches;
create policy live_read_week on public.live_matches
  for select using (auth.uid() is not null
                    and started_at >= date_trunc('week', now() at time zone 'UTC') at time zone 'UTC');
-- 写：只能写自己的行（客户端 upsert = POST + Prefer: resolution=merge-duplicates ⇒ insert 与 update 两条都要）。
drop policy if exists live_insert_own on public.live_matches;
create policy live_insert_own on public.live_matches
  for insert with check (account_id = auth.uid());
drop policy if exists live_update_own on public.live_matches;
create policy live_update_own on public.live_matches
  for update using (account_id = auth.uid()) with check (account_id = auth.uid());
-- ★没有 delete 策略：删只走下面的周清。

-- 周清：并进现有的 purge_old_matches（cron jobid 11 '0 0 * * 2' 已在跑，不新增任务）。
--   口径一字不差：删掉「本周一 00:00 UTC 之前」开打的。直播行打完就没用了（正式录像在 matches），
--   留到周清只是省一条任务；它们本来就只对本周可读。
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.live_matches where started_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;

-- ═══ ② finals_buckets.revealed_at ═══
alter table public.finals_buckets add column if not exists revealed_at timestamptz;
-- 已在进行中的组：没收盘时上一轮的翻面时刻 = 本轮的 round_at（finals_advance 同一条 update 写的）。
update public.finals_buckets set revealed_at = round_at
 where revealed_at is null and round > 1 and not closed;

-- 推进器：两条 update 都记下翻面时刻（其余逐字照抄 schema.sql 原函数）。
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
      update public.finals_buckets set closed = true, revealed_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = now(), revealed_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;

revoke all on function public.finals_advance(bigint) from public;
revoke execute on function public.finals_advance(bigint) from anon, authenticated;

-- 读接口：多下发 revealed_at（其余逐字照抄）。
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
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)。客户端按它算开播窗口。
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻: 客户端拿这个倒计时, 不必知道「一轮多长」
    'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
    'now', extract(epoch from now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res);
end $$;

revoke all on function public.finals_view(bigint, int) from public;
revoke execute on function public.finals_view(bigint, int) from anon;
grant execute on function public.finals_view(bigint, int) to authenticated;

-- 观赛读接口：多下发 round_at / revealed_at（其余逐字照抄）。
create or replace function public.finals_week_view(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare bs jsonb;
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
-- <<< END live_matches 20261007 <<<
-- live_matches 20261007 已上生产（2026-10-07 · 回读：表+3 条策略+触发器在；finals_view/finals_advance/purge_old_matches 已含新行）

-- >>> BEGIN champion_cup 20261007b >>>
-- ─────────────────────────────────────────────────────────────
-- 冠军杯赛（2026-10-07 · 方案书 docs/plans/20261007-冠军杯赛.md）—— ★待主会话审后上线
--   用户原话：「那么上午就叫小组赛啊，晚上叫冠军杯赛」
--   原稿 §四：「20:00 开赛：全部桶冠军补轮空进最近的 2 的幂签表，单败打到决赛」
--
-- ★★冠军杯赛 = `finals_buckets` 里一个**保留组号**（`finals_cup_no()` = 1000000）的单败图。
--   为什么不另建表：报结果 `finals_report` / 问对手 `finals_opponent` / 推进 `finals_advance` /
--   开播 `revealed_at` / 回放 `finals_replay` 全部按 (周, 组号) 工作 ⇒ 杯就是「又一个组」，
--   这五个函数**一行都不用改**。另建表就得把五个函数各抄一份 = 同一套规则存两份。
--   负数不行：`finals_view` 的 `p_bucket < 0` 已经表示「我那个组」。1000000 组 = 3200 万人，真组号到不了。
-- ★★本段第一次在 SQL 里写座次表（`finals_seed_at_seat`）—— 选组冠军必须顺着结果追到第 1 轮的座位。
--   构造与 `scripts/gamedata/bracket.gd` `_seat_table()` 逐步相同（镜像展开），
--   门禁 `verify_champion_cup` 逐字对构造公式、逐坑对结果。改一边必须改另一边。
-- ★重新定义的两个已有函数（finals_view / finals_week_view）正文照抄 20261007_live_matches.sql 版，
--   只改标了「冠军杯赛」的那几行。⚠ 生产库函数体可能与 schema.sql 不同，上线前先拿生产版对一遍。
-- ★本文件只加函数 / 换函数体 / 加一个 cron，不建表、不改表、不删任何一行。重复执行安全。
-- ─────────────────────────────────────────────────────────────

-- ═══ 分组容量（用户 2026-10-07 改规则）═══
-- 用户原话：「仔细思考，人少的时候桶能不能就1，2个人打出杯赛参赛者，然后多人开始在9点打杯赛？」
--           「8 人或更少时直接杯赛，不用门槛」
-- ★新规则：每组人数 s = {1,2,4,8,16,32} 里**最小**的那个、使组数 ceil(N/s) ≤ 8；32 封顶（再多人组数超过 8，
--   与原稿「桶数随人数线性伸缩」一致）。⇔ N≤8 → 1 / ≤16 → 2 / ≤32 → 4 / ≤64 → 8 / ≤128 → 16 / 其余 → 32。
--   冠军杯赛人数 = 组数（≤8 人时人人直接进冠军杯赛，上午没有对局）。
-- ★1 人组**合法**：没有对局、坐下即收盘，他就是那组的冠军（真正的冠军在冠军杯赛决出 ——
--   原来「1 人一组 = 没有对手的冠军，不是比赛」那条由此作废）。全周只有 1 人仍不开赛（finals_seat 的 total < 2）。
-- ★规格在 scripts/gamedata/bracket.gd `bucket_size_for`；门禁 verify_champion_cup 把下面这几行 `when n <= X then Y`
--   逐个人数（1..1000）与规格对；探针 tools/probe_finals_server.py ⑮ 上线后在真库再对一遍。
-- ⚠ 重新定义 finals_bucket_size / finals_seat（正文照抄 schema.sql 现行版，只改标了「2026-10-07」的行）。
--   生产库函数体可能与 schema.sql 不同，上线前先拿生产版对一遍。
create or replace function public.finals_bucket_size(n int)
returns int language sql immutable as $$
  select case
    when n <= 0 then 0
    when n <= 8 then 1
    when n <= 16 then 2
    when n <= 32 then 4
    when n <= 64 then 8
    when n <= 128 then 16
    else 32
  end
$$;

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
  -- ★2026-10-07: 1 人组坐下即收盘（没有对局；finals_advance 只推没收盘的组, 冠军杯赛成表只等没收盘的组）。
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    select p_week, bucket_no, count(*)::int, 1, now(), count(*) = 1,
           case when count(*) = 1 then now() else null end
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;

revoke all on function public.finals_seat(bigint) from public;
revoke execute on function public.finals_seat(bigint) from anon, authenticated;

-- 保留组号 / 开赛钟点（UTC，E2 拍板赛程一律 UTC）/ 20:00 还有组没打完时最多再等多久。
-- ★前两个必须与客户端 phase2_config.FINALS_CUP_BUCKET / FINALS_START_HOUR_UTC 相等（门禁逐字对）。
create or replace function public.finals_cup_no()
returns int language sql immutable as $$ select 1000000 $$;
create or replace function public.finals_cup_hour()
returns int language sql immutable as $$ select 20 $$;
create or replace function public.finals_cup_wait_sec()
returns int language sql immutable as $$ select 3600 $$;

-- 标准单败座次：slots 个坑里第 pos 个坑坐的是几号种子（0 起）。越界 = -1。
-- 构造 = bracket.gd `_seat_table`：seats=[0]；每轮 seats = 交错(x, 2·size−1−x)。8 坑 = [0,7,3,4,1,6,2,5]。
create or replace function public.finals_seed_at_seat(p_slots int, p_pos int)
returns int language plpgsql immutable as $$
declare seats int[] := array[0]; nxt int[]; sz int := 1; x int;
begin
  if p_slots < 1 or p_pos < 0 or p_pos >= p_slots then
    return -1;
  end if;
  while sz < p_slots loop
    nxt := '{}';
    foreach x in array seats loop
      nxt := array_append(nxt, x);
      nxt := array_append(nxt, sz * 2 - 1 - x);
    end loop;
    seats := nxt;
    sz := sz * 2;
  end loop;
  return seats[p_pos + 1];
end $$;

-- 一个**已收盘**的组的冠军是几号种子；没收盘 / 缺结果 = null。
-- ★从决赛往下追：第 r 轮第 m 场赢的是 side s ⇒ 他来自第 r−1 轮第 2m+s 场；追到第 1 轮 ⇒ 座位 2m+s。
--   与客户端 `bracket.occupant_seed` 的 `src_m = m * 2 + side` 同一条口径。
-- ★轮空：`finals_advance` 给第 1 轮的轮空场补 winner_side = 0，而标准座次里轮空永远坐 side 1
--   ⇒ 补 0 = 真人晋级；收盘的组每一轮每一场都有行。
create or replace function public.finals_champion_seed(p_week bigint, p_bucket int)
returns int language plpgsql stable security definer set search_path = public as $$
declare b record; slots int := 1; total int := 0; r int; m int := 0; s int; sd int;
begin
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or not b.closed then
    return null;
  end if;
  if b.n = 1 then
    return 0;                            -- 1 人表（1 人组 / 只有 1 名组冠军的冠军杯赛）：他就是冠军
  end if;
  while slots < b.n loop slots := slots * 2; total := total + 1; end loop;
  r := total;
  while r >= 1 loop
    select winner_side into s from public.finals_results
     where season_week = p_week and bucket_no = p_bucket and round = r and match_no = m;
    if not found or s not in (0, 1) then
      return null;
    end if;
    if r = 1 then
      sd := public.finals_seed_at_seat(slots, m * 2 + s);
      if sd < 0 or sd >= b.n then
        return null;                     -- 追到空位 = 结果表坏了，宁可不认冠军
      end if;
      return sd;
    end if;
    m := m * 2 + s;
    r := r - 1;
  end loop;
  return null;
end $$;

revoke all on function public.finals_champion_seed(bigint, int) from public;
revoke execute on function public.finals_champion_seed(bigint, int) from anon, authenticated;

-- 冠军杯赛成表。★幂等 —— 已经建过就不动。由 pg_cron 周日 20:00 起每 5 分钟叫一次。
-- 条件：现在 ≥ 周日 finals_cup_hour() UTC 且 本周有组 且（全部组已收盘 或 已过等待上限）。
-- ★只收**已收盘**组的冠军；种子按周六战绩（gw desc, gl asc, account_id）—— 与 finals_seat 分组同一条排序
--   ⇒ 人数不整时高种子轮空（座次表天然给高种子配空位）。
-- ★阵容用他组赛那一份快照（原稿「签表掉线兜底：沿用上一轮阵容」；周日 finals_enter 已拒收）。
-- ★只有 1 名组冠军 ⇒ 建 1 人表并直接收盘：没有对局，他就是冠军（客户端据此发「冠军」）。
-- ★1 人组（2026-10-07 新分组规则）坐下即收盘 ⇒ ≤8 人时 20:00 人人进冠军杯赛。
create or replace function public.finals_cup_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare cup int := public.finals_cup_no(); start_at timestamptz; ngroups int; nopen int;
        r record; i int := 0;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    return 0;
  end if;
  start_at := to_timestamp(p_week + 6 * 86400 + public.finals_cup_hour() * 3600);
  if now() < start_at then
    return 0;
  end if;
  select count(*), count(*) filter (where not closed) into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
    return 0;                            -- 还有组没打完：等它（最多等 finals_cup_wait_sec）
  end if;
  for r in
    select e.account_id, e.name, e.snapshot, coalesce(p.gw, 0) as gw, coalesce(p.gl, 0) as gl
      from (select b.bucket_no, public.finals_champion_seed(p_week, b.bucket_no) as cs
              from public.finals_buckets b
             where b.season_week = p_week and b.bucket_no <> cup and b.closed) c
      join public.finals_entrants e
        on e.season_week = p_week and e.bucket_no = c.bucket_no and e.seed = c.cs
      left join public.finals_pending p
        on p.season_week = p_week and p.account_id = e.account_id
     order by gw desc, gl asc, e.account_id
  loop
    insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
      values (p_week, cup, i, r.account_id, r.name, r.snapshot);
    i := i + 1;
  end loop;
  if i = 0 then
    return 0;
  end if;
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    values (p_week, cup, i, 1, now(), i <= 1, case when i <= 1 then now() else null end);
  return i;
end $$;

revoke all on function public.finals_cup_seat(bigint) from public;
revoke execute on function public.finals_cup_seat(bigint) from anon, authenticated;

-- 读接口：「我那个组」不许查到冠军杯赛（组冠军在 finals_entrants 里有两行：组 + 杯）。
-- 其余逐字照抄 20261007_live_matches.sql 版。
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
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)。客户端按它算开播窗口。
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻: 客户端拿这个倒计时, 不必知道「一轮多长」
    'next_at', extract(epoch from b.round_at)::bigint + public.finals_round_sec(),
    'now', extract(epoch from now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res);
end $$;

revoke all on function public.finals_view(bigint, int) from public;
revoke execute on function public.finals_view(bigint, int) from anon;
grant execute on function public.finals_view(bigint, int) to authenticated;

-- 观赛读接口：组列表**不含**冠军杯赛（老客户端会把它画成第 1000001 组）；
-- 冠军杯赛另放回包顶层 `cup`（同一形状 + next_at；没成表 = null；老客户端忽略未知键）。
-- 不剧透同一条 `b.closed or r.round < b.round`。其余逐字照抄 20261007_live_matches.sql 版。
create or replace function public.finals_week_view(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
                       and (b.closed or r.round < b.round)))
    into cp from public.finals_buckets b
   where b.season_week = p_week and b.bucket_no = cup;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from now())::bigint, 'buckets', bs, 'cup', cp);
end $$;

revoke all on function public.finals_week_view(bigint) from public;
revoke execute on function public.finals_week_view(bigint) from anon;
grant execute on function public.finals_week_view(bigint) to authenticated;

-- 定时：周日 20:00~23:55 UTC 每 5 分钟试一次成表（幂等；成表之后 finals_advance 的 jobid 1 接着推轮次）。
-- 周号写法与 jobid 1 / 5 相同（本周一 00:00 UTC 的 epoch = 客户端 week_anchor_ts）。
select cron.unschedule(jobid) from cron.job where jobname = 'finals_cup_seat';
select cron.schedule('finals_cup_seat', '*/5 20-23 * * 0',
  $c$select public.finals_cup_seat(extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint)$c$);
-- <<< END champion_cup 20261007b <<<
-- champion_cup 20261007b 已上生产（2026-10-07 · 回读：6 个新函数 + cron jobid 13 + finals_view/finals_week_view 含杯 + bucket_size 抽查一致）

-- >>> BEGIN purge_ghosts 20261008 >>>
-- ─────────────────────────────────────────────────────────────
-- 周清并进对手快照（2026-10-08 · 用户「每周快照会刷掉对吧」「改」）
--   客户端拉对手本来就只拉本周（season_week=eq.本周锚点），旧周的行不会被匹配到，但一直留在库里。
--   ⇒ 并进现有 purge_old_matches（cron jobid 11 '0 0 * * 2'，不新增任务），口径与 matches 一致：
--     删掉 season_week 早于本周一 00:00 UTC 的快照。season_week = 周一 00:00 UTC 的 epoch 秒。
--   ★重新定义的函数体 = 生产现行版（含 live_matches 那行，20261007 已上）+ 下面两行。
-- ─────────────────────────────────────────────────────────────
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.live_matches where started_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
  delete from public.gauntlet_ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;
-- <<< END purge_ghosts 20261008 <<<
-- purge_ghosts 20261008 已上生产（2026-10-08 · 回读：purge_old_matches 含 ghosts / gauntlet_ghosts 两行，cron jobid 11 不变）

-- >>> BEGIN week_leaderboard_v3 20261010 >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜 v3（2026-10-10 · 周六闯关赛实操查实：「积分赛终榜」周六还在变、总场次 20、名次被改写）—— ★待主会话审后上线
--
-- ★病根（客户端，65760c25 已修新包；旧包还在外面照写）：
--   `Backend.upload_gauntlet_ghost` 把周六那份快照也排进了积分赛 `ghosts` 的上传队列，
--   `battles` = `season_total_battles`（周六每场 +1 ⇒ 17、18…），`season_wins` 含周六胜场。
--   v2 每账号取 `battles desc` 最新一行 ⇒ 取到的是周六那一行。
--
-- ★相对 v2（20261006b_week_leaderboard_v2.sql）只在 `latest` 里多两行过滤，其余一个字没动：
--   签名 / 下发字段 / 排序（胜场 → 余命 → 横扫 → 先到者 → account_id）/ 授权全同。
--
-- ★判据 = 快照里的周六战绩标签 `gl_w` / `gl_l`（只有 `upload_gauntlet_ghost` 与 `make_bot` 写它们，
--   积分赛快照 `build_ghost_snapshot` 不写；上传路 `ghost_row_from_snapshot` 原样放进 jsonb，
--   `ReplayUploader.GHOST_STRIP` 只管录像那条路、不碰 `ghosts`）。
--   ★★不是「有 gl_w 就扔」，而是「战绩不是 0-0 就扔」—— 0-0 那一份要留：
--     `ensure_gauntlet_entry_snapshot` 周六进场先传一份 0-0，它的 `battles` = 积分赛收官那一场的场次，
--     与积分赛最后一行【主键相同】，而上传是 upsert（`Prefer: resolution=merge-duplicates`）⇒
--     它原地盖掉了积分赛最后一行（胜场/余命/横扫与收官时一字不差，`uploaded_at` 不在上传体里 ⇒ 不变）。
--     「有 gl_w 就扔」会把这些人的收官行扔掉、退回倒数第二场 —— 正好少算一场。
--   ★比的是 jsonb 值不是文本：快照过一次落盘队列（JSON 存档）数字可能变成 0.0，`'0'::jsonb = '0.0'::jsonb` 为真，
--     而 `->> 'gl_w' = '0'` 对 0.0 为假。没有这个键（积分赛快照）⇒ coalesce 成 0 ⇒ 保留。
--   ★不按 `battles <= 16` 截：提前晋级的人（11 胜 1 负只打 12 场）周六的行是 13、14…，照样在 16 以内。
-- ★只读：不建表、不改表、不写任何一行；库里那些周六行原样留着（周二 00:00 UTC purge_old_matches 随周清掉）。
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
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
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
-- <<< END week_leaderboard_v3 20261010 <<<
-- week_leaderboard_v3 20261010 已上生产(2026-10-10 Management API 回 201; 回读 pg_get_functiondef 含 gl_w = true;
--   只读重算本周榜: 73 人不变, 最高场次 22 → 16, 超 16 场 21 → 0)

-- >>> BEGIN finals_report_guard 20261011 >>>
-- 2026-10-11 全项目通读(赛制第 2 条): finals_report 不校验场号 / 轮空场能被抢
--
-- ① 原来只校验「当前轮 + 我在这个桶里 + side ∈ {0,1}」, 不校验 p_match 的范围。
--    finals_advance 按【结果行数】判本轮是否打完 ⇒ 组里任何人报几个越界的假场号, 行数就凑够了,
--    本轮在 480 秒到点时提前收盘, 没报的真场次被补判 side 0 晋级。
-- ② 第 1 轮的轮空场(side 1 是空座)本该由 finals_advance 补 side 0 让真人晋级;
--    但补判用的是 on conflict do nothing ⇒ 组里任何人先报一个 winner_side = 1(空座赢), 真人就被淘汰。
--
-- 修: 场号必须落在本轮真实场次范围 [0, slots / 2^round) 内; 第 1 轮 side 1 是空座的场一律不收(由推进器补)。
-- ★座次表用已有的 finals_seed_at_seat(与客户端 bracket.gd 同构, verify_champion_cup 对过账), 不新写第二份。
-- 正文照抄 schema.sql 现行版, 只加标了「2026-10-11」的两段。

create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; slots int := 1; n_match int; bye_seed int;
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
  -- ★2026-10-11 ①: 场号必须是本轮真实存在的场(否则越界假场号会凑够行数、提前收盘)
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  n_match := greatest(1, slots / (2 ^ p_round)::int);
  if p_match < 0 or p_match >= n_match then
    return jsonb_build_object('ok', false, 'reason', 'bad_match', 'n_match', n_match);
  end if;
  -- ★2026-10-11 ②: 第 1 轮的轮空场(side 1 坐的是空座)不收任何上报 —— 由 finals_advance 补 side 0
  if p_round = 1 then
    bye_seed := public.finals_seed_at_seat(slots, 2 * p_match + 1);
    if bye_seed < 0 or bye_seed >= b.n then
      return jsonb_build_object('ok', false, 'reason', 'bye');
    end if;
  end if;
  insert into public.finals_results
    (season_week, bucket_no, round, match_no, winner_side, seed_used)
    values (p_week, p_bucket, p_round, p_match, p_winner_side, coalesce(p_seed, 0))
    on conflict (season_week, bucket_no, round, match_no) do nothing;
  return jsonb_build_object('ok', true);
end $$;
-- <<< END finals_report_guard 20261011 <<<
-- ⚠ finals_report_guard 20261011 尚未上生产(等用户点头)

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
-- client_errors 20261011 已上生产(2026-10-11 ~18:15 UTC, 用户「做」); 回读: RLS 开 / anon 无表权限无执行权 / authenticated 只有执行权

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
-- finals_scores 20261012 已上生产(2026-10-12, 用户「要做」); 回读: 事务内补报 ok / 重报拒 / 错 seed 拒 / 非参赛者拒 / anon 无执行权 / 视图带出 scores

-- >>> BEGIN finals_seat_1800 20261012 >>>
-- 周日小组赛开赛时刻 08:00 UTC → 18:00 UTC（用户 2026-10-12「晚上 19 点」, 英国夏令时 = UTC+1）。
-- 只改定时任务的触发小时; finals_seat 函数本身不看钟点。客户端常量 FINALS_SEAT_HOUR_UTC 同步改 18。
-- 冠军杯赛 finals_cup_seat 仍 20:00 UTC 起每 5 分钟(组没打完它会等)。重复执行安全。
select cron.unschedule(jobid) from cron.job where jobname = 'finals_seat';
select cron.schedule('finals_seat', '*/10 18-23 * * 0',
  $$select public.finals_seat((extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint))$$);
-- <<< END finals_seat_1800 20261012 <<<
-- finals_seat_1800 20261012 已上生产(2026-10-12, 用户「晚上 19 点」); 回读 cron.job finals_seat = */10 18-23 * * 0

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
-- player_feedback 20261012 已上生产(2026-10-12); 回读: anon 无执行权 / authenticated 无表读权

-- >>> BEGIN finals_settle_once 20261012 >>>
-- ─────────────────────────────────────────────────────────────
-- 周日「购物结束后统一结算、每场只算一次」（2026-10-12 · 方案书 docs/plans/20261012-周日统一结算.md）
--   用户：「那怎么搞啊」「今天末必须发新包」「做」。原稿 §四：「3 分钟备战购物 → 系统瞬间结算 → 全桶观看重放」；
--   §五.2「共享种子结算一次 → 双方各自观看同一份重放」；§四「不在线 = 快照代打」。
-- 修的两个实操问题：
--   S4 对局用的是周六晋级那一刻的快照、谁先点开谁打、购物窗内就能开打；
--   S6 两边各打各的（种子 / 输入都不同）⇒ 两边都算出自己赢，服务端采纳先到的那份。
-- 做法（全是添加或收紧，不删数据）：
--   ① finals_update_snapshot：购物窗内，组里的人可以更新自己这一份快照（= 购物后的阵容）。
--   ② finals_opponent：购物窗内不给对手快照（reason shop_open）；带上场号时，已有结果回 settled。
--   ③ finals_report：购物窗内拒收；必须带 p_reporter_side ——
--        上半区(0) 购物结束即可报；下半区(1) 要等本轮标准时长走完（购物 + 300 秒）还没结果才收（= 替不在线的上半区快照代打）；
--        不带侧别（旧客户端）拒收 update_required。
--      并入 20261011_finals_report_guard（未上过生产）的两条：场号越界拒收、第 1 轮轮空场拒收。
-- ⇒ 每场只有一份输入（上半区锁定的阵容 × 下半区购物后的快照）、只算一次、大家看同一份录像。
-- ★重复执行安全（create or replace / drop if exists）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.finals_shop_sec() returns int
language sql immutable as $$ select 180 $$;      -- = 客户端 Phase2Config.FINALS_SHOP_SEC
create or replace function public.finals_lower_grace_sec() returns int
language sql immutable as $$ select 300 $$;      -- 购物结束后给上半区的时间; = 客户端 Phase2Config.FINALS_LOWER_GRACE_SEC

-- ① 购物窗内更新自己的快照
create or replace function public.finals_update_snapshot(p_week bigint, p_bucket int, p_snapshot jsonb)
returns boolean
language plpgsql security definer set search_path = public as $$
declare b record; n int;
begin
  if auth.uid() is null or p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
     or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') < 3 then
    return false;                       -- 没有 3 只统领的快照不收(防空阵容覆盖周六那份正式阵容)
  end if;
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return false;
  end if;
  if now() >= b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return false;                       -- 购物结束 = 本轮阵容锁定
  end if;
  update public.finals_entrants set snapshot = p_snapshot
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.finals_update_snapshot(bigint, int, jsonb) from public, anon;
grant execute on function public.finals_update_snapshot(bigint, int, jsonb) to authenticated;

-- ② 对手快照：购物窗内不给；带场号时已结算回 settled
drop function if exists public.finals_opponent(bigint, int, int, int);
create or replace function public.finals_opponent(p_week bigint, p_bucket integer, p_round integer, p_seed integer,
    p_match integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  -- ★2026-10-12: 购物窗内不给对手快照 —— 对手还在购物, 给出去的是他购物前的阵容(S4)
  if now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  -- ★2026-10-12: 这一场已经有结果 ⇒ 不再给(每场只算一次; 不泄露胜负, 只说已结算)
  if p_match is not null and exists (select 1 from public.finals_results
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = p_match) then
    return jsonb_build_object('ok', false, 'reason', 'settled');
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_seed = mine then
    return jsonb_build_object('ok', false, 'reason', 'thats_you');
  end if;
  select snapshot, name into snap, nm from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and seed = p_seed;
  if snap is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_seed');
  end if;
  insert into public.finals_scout (season_week, bucket_no, round, account_id, seed)
    values (p_week, p_bucket, p_round, auth.uid(), p_seed)
    on conflict (season_week, bucket_no, round, account_id) do nothing;
  select seed into asked from public.finals_scout
   where season_week = p_week and bucket_no = p_bucket
     and round = p_round and account_id = auth.uid();
  if asked <> p_seed then
    return jsonb_build_object('ok', false, 'reason', 'already_asked', 'seed', asked);
  end if;
  return jsonb_build_object('ok', true, 'seed', p_seed, 'name', nm, 'snapshot', snap);
end $function$;
revoke all on function public.finals_opponent(bigint, int, int, int, int) from public, anon;
grant execute on function public.finals_opponent(bigint, int, int, int, int) to authenticated;

-- ③ 上报：购物窗内拒收; 必须带侧别; 下半区等宽限; 场号 / 轮空校验
drop function if exists public.finals_report(bigint, int, int, int, int, bigint);
create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint, p_reporter_side int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; slots int := 1; n_match int; bye_seed int; open_at timestamptz;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_winner_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'bad_side');
  end if;
  -- ★2026-10-12: 旧客户端(不带侧别)按旧规矩各打各的 ⇒ 不收
  if p_reporter_side is null or p_reporter_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  open_at := b.round_at + make_interval(secs => public.finals_shop_sec());
  if now() < open_at then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  if p_reporter_side = 1 and now() < open_at + make_interval(secs => public.finals_lower_grace_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'upper_first');
  end if;
  -- 场号必须是本轮真实存在的场(20261011_finals_report_guard ①)
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  n_match := greatest(1, slots / (2 ^ p_round)::int);
  if p_match < 0 or p_match >= n_match then
    return jsonb_build_object('ok', false, 'reason', 'bad_match', 'n_match', n_match);
  end if;
  -- 第 1 轮轮空场不收(20261011_finals_report_guard ②)
  if p_round = 1 then
    bye_seed := public.finals_seed_at_seat(slots, 2 * p_match + 1);
    if bye_seed < 0 or bye_seed >= b.n then
      return jsonb_build_object('ok', false, 'reason', 'bye');
    end if;
  end if;
  insert into public.finals_results
    (season_week, bucket_no, round, match_no, winner_side, seed_used)
    values (p_week, p_bucket, p_round, p_match, p_winner_side, coalesce(p_seed, 0))
    on conflict (season_week, bucket_no, round, match_no) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.finals_report(bigint, int, int, int, int, bigint, int) from public, anon;
grant execute on function public.finals_report(bigint, int, int, int, int, bigint, int) to authenticated;
-- <<< END finals_settle_once 20261012 <<<
-- finals_settle_once 20261012 已上生产(2026-10-12, 用户「做」「今天末必须发新包」); 事务回读: 购物窗内 opponent/report=shop_open、快照可改; 购物后上半区 ok、下半区 upper_first、无侧别 update_required、快照锁定; 宽限后下半区 ok、opponent settled; 全部回滚
-- finals_update_snapshot 2026-10-12 实跑后加: 没有 3 只统领的快照拒收(已上生产)

-- >>> finals_score_one_lane 20261018 >>>
-- 2026-10-18 周日比分: 一路碎蛋 = 1:0(用户原话「一路碎蛋不就是1：0」)
--
-- 碎蛋 = 整场当场结束(用户 2026-07-12), 胜方不一定拿满 2 路。原来 loser_lanes 只能存 0/1
-- (= 2:0 / 2:1), 一路碎蛋的场次客户端算出 -1 就不报 ⇒ 对阵图上那场没有比分。
-- 比分代码(客户端 phase2_duallane.gd 的 SCORE_* 与 score_pair 是同一张表):
--    0 = 2:0    1 = 2:1    -10 = 1:0(上路碎蛋)    -11 = 1:1(下路碎蛋)
-- ★取负数: v0.19.570 及更早的客户端只画 >=0 的比分 ⇒ 老包看到新码是「不画」, 不会画出假的 2:x。
alter table public.finals_results drop constraint if exists finals_results_loser_lanes;
alter table public.finals_results add constraint finals_results_loser_lanes
  check (loser_lanes is null or loser_lanes in (0, 1, -10, -11));

create or replace function public.finals_report_score(p_week bigint, p_bucket int, p_round int,
    p_match int, p_seed bigint, p_loser_lanes int)
returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null or p_loser_lanes not in (0, 1, -10, -11) or coalesce(p_seed, 0) = 0 then
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
-- <<< END finals_score_one_lane 20261018 <<<

-- >>> min_version_gate 20261019 >>>
-- 2026-10-19 强制最低版本(用户「需要强制最低版本」· 方案书 docs/plans/20261019-服务器裁判.md §4)
--
-- ★★未执行。上生产前先在内测服跑一遍并回读(见文末「上线步骤」)。
--
-- 三件事:
--   ① 服务端版本闸: 每个 PostgREST 请求(表的读写 + 全部 RPC)先过 pre-request 钩子
--      `check_client_version()`: 请求头 `X-Client-Version`(客户端 supabase.gd `_headers` 每条都带)
--      低于 `service_status.min_client_version` ⇒ 拒, HTTP 426, message = 'update_required'。
--      ★为什么用钩子而不是给每个 RPC 加 `p_client_version` 参数:
--        快照/录像/直播是**直接写表**(REST insert/upsert), 拉对手是**直接 GET 表** —— 那些请求没有参数位;
--        而 RPC 加参数要改签名(旧签名留着 = 旧包照调不误, 删掉 = 改一处漏一处)。
--        请求头是唯一跟着**每一个**请求走的位置, 一个函数管全部入口, 新加的 RPC 也自动在闸后面。
--      ★缺头 / 看不懂 ⇒ 按 0.0.0 算 ⇒ 只要最低版本 > 0.0.0 就拒。
--        ⇒ 0.19.571 及更早的包(不带这个头)在运维抬高最低版本的那一刻起全部被拒;
--          最低版本保持默认 '0.0.0' 时谁都不拒 —— 本迁移可以提前上, 不影响在跑的内测。
--      白名单(旧包也放行): 读 service_status(旧包要读到最低版本才知道该更新) /
--        report_client_error / submit_feedback(诊断)。service_role(裁判机 / 运维)不过闸。
--   ② 行级兜底: ghosts / gauntlet_ghosts 的写策略再加一条「行里的 client_version 不低于最低版本」
--      —— 钩子万一没配上(见风险), 旧包上传的快照照样进不了池子;
--      也挡住「新包把旧版本打出来的排队快照补传上来」(客户端 ghost_uploader 也会按版本销单)。
--   ③ 战斗规则版本 `rules_ver`: ghosts / gauntlet_ghosts 加一列, 客户端上传时写
--      `phase2_config.RULES_VER`, 拉对手只拉 `rules_ver = 本机值`(opponents_query / gauntlet_query)。
--      ★旧数据: 已有的行一律是默认值 0 ⇒ 新客户端(RULES_VER = 1)**永远拉不到**。
--        这是有意的: 那些快照是旧规则下打出来的, 在新规则下算不出同一局。
--        两张表都按 season_week 分周(周一清), 新版本在周一维护期上线时, 新的一周本来就从空池子开始。
--        不回填: 没有办法事后证明某一行是在哪套规则下打的(client_version 列能近似, 但规则版本与客户端版本不是一一对应)。
--      ★客户端在 0.19.571 及更早不写这一列 ⇒ 它们上传的行也是 0 ⇒ 新旧两代池子天然隔开。
--
-- ★发版流程加一步(方案书 §4): 这一版改了任何会改变对局结果的东西 ⇒ 客户端 RULES_VER +1,
--   并在新包上架后执行:
--     update public.service_status set min_client_version = '<新版本>', updated_at = now() where id = 1;

-- ── 版本串 → 整数数组(补齐 4 段; 看不懂 ⇒ null) ──
create or replace function public.semver_arr(v text)
returns int[]
language plpgsql immutable as $$
declare
  s text := btrim(coalesce(v, ''));
  a int[];
begin
  if s !~ '^[0-9]{1,6}(\.[0-9]{1,6}){0,3}$' then
    return null;
  end if;
  a := string_to_array(s, '.')::int[];
  while coalesce(array_length(a, 1), 0) < 4 loop
    a := a || 0;
  end loop;
  return a;
end $$;

-- ── 这个版本够不够(低于最低版本 ⇒ false; 缺 / 看不懂 ⇒ 按 0.0.0 算) ──
-- ★最低版本本身看不懂(运维填错)⇒ 放行 —— 填错一个字不该把所有人关在门外。
create or replace function public.client_version_ok(v text)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  m int[];
begin
  select public.semver_arr(min_client_version) into m from public.service_status where id = 1;
  if m is null then
    return true;
  end if;
  return coalesce(public.semver_arr(v), array[0, 0, 0, 0]) >= m;
end $$;
revoke all on function public.client_version_ok(text) from public;
grant execute on function public.client_version_ok(text) to anon, authenticated, service_role;

-- ── 请求头里的客户端版本(PostgREST 把请求头放在 request.headers, 键一律小写) ──
create or replace function public.request_client_version()
returns text
language sql stable as $$
  select nullif(current_setting('request.headers', true), '')::json ->> 'x-client-version'
$$;
grant execute on function public.request_client_version() to anon, authenticated, service_role;

-- ── ① pre-request 钩子 ──
create or replace function public.check_client_version()
returns void
language plpgsql stable security definer set search_path = public as $$
declare
  p text := coalesce(current_setting('request.path', true), '');
  role_claim text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '');
  cv text := public.request_client_version();
begin
  if role_claim = 'service_role' then
    return;
  end if;
  if p ~ '/(service_status|rpc/report_client_error|rpc/submit_feedback)/?$' then
    return;
  end if;
  if not public.client_version_ok(cv) then
    raise sqlstate 'PT426' using
      message = 'update_required',
      detail = format('client %s is below min_client_version', coalesce(cv, '(none)'));
  end if;
end $$;
revoke all on function public.check_client_version() from public;
grant execute on function public.check_client_version() to anon, authenticated, service_role;

-- 挂上钩子(PostgREST 读 authenticator 角色上的 pgrst.* 配置), 然后让它重读配置。
alter role authenticator set pgrst.db_pre_request = 'public.check_client_version';
notify pgrst, 'reload config';

-- ── ③ 战斗规则版本列 ──
alter table public.ghosts add column if not exists rules_ver int not null default 0;
alter table public.gauntlet_ghosts add column if not exists rules_ver int not null default 0;
-- 拉对手的过滤多了一维: 积分赛 (周, 场次, 规则) / 周六 (周, 标签, 规则), 都按上传时刻倒序。
create index if not exists ghosts_match_rv_idx
  on public.ghosts (season_week, battles, rules_ver, uploaded_at desc);
create index if not exists gauntlet_match_rv_idx
  on public.gauntlet_ghosts (season_week, gw, gl, rules_ver, uploaded_at desc);

-- ── ② 行级兜底: 写快照的行版本不低于最低版本 ──
drop policy if exists ghosts_write_own on public.ghosts;
create policy ghosts_write_own on public.ghosts
  for insert with check (account_id = auth.uid() and public.client_version_ok(client_version));

drop policy if exists ghosts_update_own on public.ghosts;
create policy ghosts_update_own on public.ghosts
  for update using (account_id = auth.uid())
  with check (account_id = auth.uid() and public.client_version_ok(client_version));

drop policy if exists gauntlet_write_own on public.gauntlet_ghosts;
create policy gauntlet_write_own on public.gauntlet_ghosts
  for insert with check (account_id = auth.uid() and public.client_version_ok(client_version));

drop policy if exists gauntlet_update_own on public.gauntlet_ghosts;
create policy gauntlet_update_own on public.gauntlet_ghosts
  for update using (account_id = auth.uid())
  with check (account_id = auth.uid() and public.client_version_ok(client_version));

-- 上线步骤(内测服先走一遍, 回读每一条):
--   1. 执行本文件。回读: select public.semver_arr('0.19.10') > public.semver_arr('0.19.9');  -- 应为 true
--   2. 最低版本仍是 0.0.0 时: 0.19.571 的包照常能拉对手 / 传快照(谁都不拒)。
--   3. update service_status set min_client_version = '0.19.999' ⇒
--      不带头的 curl GET /rest/v1/ghosts 回 426 {"message":"update_required"};
--      GET /rest/v1/service_status 照常 200; 带 `X-Client-Version: 0.19.999` 的 GET 200。
--      ⚠ 若 GET ghosts 仍 200: 钩子没生效(见风险 R-钩子), 此时只有②行级兜底在挡写, 读不挡。
--   4. 改回最低版本。
-- 风险:
--   R-钩子: Supabase 托管的 PostgREST 是否接受 `alter role authenticator set pgrst.db_pre_request`
--     本仓从没实测过(官方文档有 pre-request 的说明, 但托管实例的角色权限没验)。不接受 ⇒ 换成在每个 RPC 开头
--     `if not public.client_version_ok(public.request_client_version()) then return ...update_required` + 表的读策略加同一条。
--   R-网页包: 浏览器跨域时自定义头要过网关的 CORS 预检; Supabase 网关目前放行任意请求头, 但没在网页包上实测。
-- <<< END min_version_gate 20261019 <<<
-- >>> BEGIN week_leaderboard_page 20261019 >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜按名次区间取（2026-10-19 · 用户「排行榜你学一下其他游戏的，开放所有排名」）—— ★待主会话审后上线
--
-- ★为什么：`week_leaderboard(p_week, p_limit)` 只回前 N 名（limit 夹在 1..100）+ 我那一行，
--   客户端只画得出前 30 名 + 钉住的我。所有名次都要能翻到 ⇒ 按名次区间分页取。
-- ★新函数，不改旧函数：老包照旧调 `week_leaderboard`，一个字不动；新包先调本函数，404（没部署）再退回旧函数。
-- ★口径与 v3（20261010_week_leaderboard_v3.sql）逐字相同：`latest` / `ranked` 两段原样照抄
--   （本周 / 每账号最新一行 / 滤陪练 seed_ / 滤 is_bot / 滤周六非 0-0 行 / 胜场 → 余命 → 横扫 → 先到者 → account_id），
--   只把「rk <= lim」换成「p_offset < rk <= p_offset + lim」。
-- ★回包形状 = 旧函数的形状 + `offset`：{ok, week, total, offset, rows:[名次 offset+1 .. offset+lim], me}。
-- ★每页上限 100（与旧函数同一个上限）；offset 负数当 0。
-- ★只读：不建表、不改表、不写任何一行。
-- ─────────────────────────────────────────────────────────────
create or replace function public.week_leaderboard_page(p_week bigint, p_offset int default 0, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; off int; tot int; page jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  off := greatest(coalesce(p_offset, 0), 0);
  with latest as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
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
             'title', coalesce(r.title, '')) order by r.rk) filter (where r.rk > off and r.rk <= off + lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, page, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'offset', off,
    'rows', page, 'me', mine);
end $$;

revoke all on function public.week_leaderboard_page(bigint, int, int) from public;
revoke execute on function public.week_leaderboard_page(bigint, int, int) from anon;
grant execute on function public.week_leaderboard_page(bigint, int, int) to authenticated;
-- <<< END week_leaderboard_page 20261019 <<<

-- >>> BEGIN referee_jobs 20261019 >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判（2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §1 / §3 ①②）—— ★只写文件、未上生产
--   上线步骤 / 回滚 / 监控见 server/referee/README.md。
--
-- 用户 10-19「我们的所有对局不应该在本机上吧，应该放服务器上吧」「周六周日让服务器记」。
-- 做法：对局结果 = f(双方快照, 种子)，由裁判机（欧洲 x86 服务器上的无头 Godot，与客户端同版本）算，
--   算完写回录像（matches.replay，与客户端上传同一格式，手机直接播）与赛果。
--
-- 本段内容（全是添加，或在两个开关后面加一条分支；★两个开关默认关 ⇒ 执行本段不改变任何现行行为）：
--   ① referee_config（开关 finals_on / gauntlet_on、领活租期、重试次数、周日任务用的版本）、referee_versions（裁判机装了哪些版本）
--   ② referee_jobs：待算 pending → 领取 claimed → 完成 done / 失败 failed；领了超过租期没写回 ⇒ 别的裁判重领
--   ③ RPC（只有 service_role 能调）：referee_claim 领活 / referee_complete 写回 / referee_fail 报错 / referee_backlog 监控
--   ④ 周日：referee_enqueue_finals —— 购物窗一关就给本轮每一场真实对局建任务（A = 上侧 side 0、B = 下侧 side 1）；
--      finals_advance（开关开着时）不再给真实场次补判 side 0，只补轮空；超过 3 倍本轮时长仍没结果才退回 side 0 兜底；
--      finals_report（开关开着时）不再收客户端上报（reason = referee）。结果由 referee_complete 写 finals_results（含比分码）。
--   ⑤ 周六：referee_submit_gauntlet（客户端交阵容 + 对手快照 → 建任务，种子服务端生成）/ referee_job_status（查自己那一场）；
--      写回时记账到 gauntlet_records（服务端战绩账本），并把阵容按新战绩标签挂进 gauntlet_ghosts；
--      finals_enter（开关开着时）的晋级线与种子排序改用账本上的 gw / gl，不再信客户端报的数。
-- ★客户端一行不改也不受影响：开关关着时三个被重定义的函数（finals_advance / finals_report / finals_enter）逐字等于原版。
-- ★重复执行安全（create if not exists / create or replace / on conflict do nothing / drop if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 开关 / 版本 ─────────────────────────────────────────────
create table if not exists public.referee_config (
  id            int primary key default 1,
  finals_on     boolean not null default false,   -- 周日结果由裁判出
  gauntlet_on   boolean not null default false,   -- 周六闯关由裁判出、服务端记账
  gauntlet_any_day boolean not null default false,-- 内测服 / 彩排: 不限周六也能交（正式服保持 false）
  finals_version text not null default '',        -- 周日任务按哪个客户端版本算（= 当周锁定的版本；必须在 referee_versions 里且 enabled）
  lease_sec     int not null default 180,         -- 领了多久没写回 ⇒ 收回重领（一局实测 ≤ 15 秒；含 Godot 启动）
  max_attempts  int not null default 3,           -- 同一份任务最多领几次（每次领 +1；用尽 ⇒ failed）
  updated_at    timestamptz not null default now(),
  constraint referee_config_single_row check (id = 1)
);
insert into public.referee_config (id) values (1) on conflict (id) do nothing;
alter table public.referee_config enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行；只有 service_role / 下面的 security definer 函数碰得到

-- 裁判机上装了哪些客户端版本（结果只在同版本里成立：每个版本一套无头 Godot 工程）。
create table if not exists public.referee_versions (
  client_version text primary key,
  enabled        boolean not null default true,
  added_at       timestamptz not null default now()
);
alter table public.referee_versions enable row level security;

create or replace function public.referee_finals_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select finals_on from public.referee_config where id = 1), false)
$$;
create or replace function public.referee_gauntlet_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select gauntlet_on from public.referee_config where id = 1), false)
$$;
revoke all on function public.referee_finals_on() from public, anon, authenticated;
revoke all on function public.referee_gauntlet_on() from public, anon, authenticated;

-- ② 任务表 ─────────────────────────────────────────────────
-- 一行 = 一场要算的对局。形状与裁判程序的任务单一一对应（scripts/referee/referee_job.gd 头注）：
--   v / job_id / match_id / mode(=kind) / key(=meta + week + match_key) / seed / client_version / level / a / b。
create table if not exists public.referee_jobs (
  job_id         bigint generated always as identity primary key,
  kind           text        not null check (kind in ('gauntlet', 'finals')),
  match_key      text        not null unique,     -- 幂等键：finals:<周>:<组>:<轮>:<场> / gauntlet:<周>:<账号>:<第几场>
  season_week    bigint      not null,
  client_version text        not null,
  seed           bigint      not null check (seed between 1 and 9007199254740991),   -- 2^53-1：JSON 往返不掉位
  match_id       uuid        not null default gen_random_uuid(),                    -- = 录像 id = matches.match_id
  a_account      uuid        references auth.users(id) on delete set null,          -- 左方（周日 = 上侧 side 0）
  b_account      uuid        references auth.users(id) on delete set null,          -- 右方（周六 = null：对手可能是机器人）
  a_snapshot     jsonb       not null,
  b_snapshot     jsonb       not null,
  level          int,                                                               -- 双方共用等级（null ⇒ 裁判按 A 的快照推）
  meta           jsonb       not null default '{}'::jsonb,                          -- 周日 {bucket, round, match}；周六 {account, gw0, gl0}
  status         text        not null default 'pending' check (status in ('pending', 'claimed', 'done', 'failed')),
  attempts       int         not null default 0,
  claimed_by     text,
  claimed_at     timestamptz,
  result         jsonb,                                                             -- 结果单（去掉录像本体）+ 落账摘要
  error          text,
  created_at     timestamptz not null default now(),
  done_at        timestamptz
);
create index if not exists referee_jobs_queue_idx on public.referee_jobs (status, created_at)
  where status in ('pending', 'claimed');
create index if not exists referee_jobs_acc_idx on public.referee_jobs (season_week, a_account);
alter table public.referee_jobs enable row level security;
-- 没有任何策略 ⇒ 客户端直连读不到（快照 = 阵容情报）；玩家查自己那一场走 referee_job_status

-- 裁判机心跳（监控 R3：挂了要知道）。referee_claim 每叫一次就记一笔。
create table if not exists public.referee_workers (
  worker     text primary key,
  versions   text[] not null default '{}',
  seen_at    timestamptz not null default now()
);
alter table public.referee_workers enable row level security;

-- ③ 小工具 ─────────────────────────────────────────────────
-- 服务端种子：1 ~ 2^53-1。★种子永远由服务端给，不收客户端的（否则可以换种子刷结果）。
create or replace function public.referee_new_seed() returns bigint
language plpgsql volatile as $$
declare v bigint;
begin
  v := ('x' || substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 14))::bit(56)::bigint
       & 9007199254740991;
  if v = 0 then
    v := 1;
  end if;
  return v;
end $$;
revoke all on function public.referee_new_seed() from public, anon, authenticated;

-- 快照里的等级（1~10；没有 / 不合法 = null ⇒ 裁判按 A 的场次推算）。任务单 level = A（左方）的等级。
-- 2026-10-19 起客户端 build_ghost_snapshot 带 season_level；右方（B）的等级由裁判里的战斗场直接读 B 快照（双方各用各的）。
create or replace function public.referee_level_of(p_snap jsonb) returns int
language sql immutable as $$
  select case when jsonb_typeof(p_snap->'season_level') = 'number'
               and (p_snap->>'season_level')::numeric between 1 and 10
              then (p_snap->>'season_level')::numeric::int end
$$;
revoke all on function public.referee_level_of(jsonb) from public, anon, authenticated;

-- 周日某轮某场某一侧坐的是几号种子；空位 / 上一轮还没结果 = null。
-- ★与 finals_champion_seed 同一条口径：第 r 轮第 m 场的 side s 来自第 r−1 轮第 2m+s 场的胜者；追到第 1 轮 ⇒ 座位 2m+s。
create or replace function public.referee_finals_occupant(p_week bigint, p_bucket int, p_round int,
    p_match int, p_side int)
returns int language plpgsql stable security definer set search_path = public as $$
declare b record; slots int := 1; r int := p_round; m int := p_match; s int := p_side; w int; sd int;
begin
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found or p_side not in (0, 1) or p_round < 1 then
    return null;
  end if;
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  while r > 1 loop
    select winner_side into w from public.finals_results
     where season_week = p_week and bucket_no = p_bucket and round = r - 1 and match_no = 2 * m + s;
    if not found or w not in (0, 1) then
      return null;
    end if;
    m := 2 * m + s;
    s := w;
    r := r - 1;
  end loop;
  sd := public.finals_seed_at_seat(slots, 2 * m + s);
  if sd < 0 or sd >= b.n then
    return null;
  end if;
  return sd;
end $$;
revoke all on function public.referee_finals_occupant(bigint, int, int, int, int) from public, anon, authenticated;

-- ④ 周日：建任务 ───────────────────────────────────────────
-- 购物窗关了（round_at + finals_shop_sec）⇒ 本轮每一场两侧都有人的对局建一份任务（幂等：match_key 唯一）。
-- 快照取 finals_entrants 当前那份（购物窗内 finals_update_snapshot 改过的就是购物后的阵容，购物窗一关就锁定）。
-- 由 finals_advance 开头调（pg_cron 每分钟一次，jobid 1）；也可以单独调。
create or replace function public.referee_enqueue_finals(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; ea record; eb record; slots int; n_match int; m int; s0 int; s1 int;
        ver text; added int := 0; k int;
begin
  if not public.referee_finals_on() then
    return 0;
  end if;
  select finals_version into ver from public.referee_config where id = 1;
  if coalesce(ver, '') = '' or not exists (select 1 from public.referee_versions
                                            where client_version = ver and enabled) then
    return 0;                            -- 没定版本 / 裁判机没装这个版本 ⇒ 不建（finals_advance 的 3 倍时长兜底照样在）
  end if;
  for b in select * from public.finals_buckets where season_week = p_week and not closed loop
    if now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
      continue;                          -- 还在购物
    end if;
    slots := 1;
    while slots < greatest(b.n, 1) loop
      slots := slots * 2;
    end loop;
    n_match := greatest(1, slots / (2 ^ b.round)::int);
    for m in 0 .. n_match - 1 loop
      if exists (select 1 from public.finals_results
                  where season_week = p_week and bucket_no = b.bucket_no and round = b.round and match_no = m) then
        continue;
      end if;
      s0 := public.referee_finals_occupant(p_week, b.bucket_no, b.round, m, 0);
      s1 := public.referee_finals_occupant(p_week, b.bucket_no, b.round, m, 1);
      if s0 is null or s1 is null then
        continue;                        -- 轮空（finals_advance 补 side 0）/ 上一轮还没出结果
      end if;
      select * into ea from public.finals_entrants where season_week = p_week and bucket_no = b.bucket_no and seed = s0;
      if not found then
        continue;
      end if;
      select * into eb from public.finals_entrants where season_week = p_week and bucket_no = b.bucket_no and seed = s1;
      if not found then
        continue;
      end if;
      insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
          a_account, b_account, a_snapshot, b_snapshot, level, meta)
        values ('finals', format('finals:%s:%s:%s:%s', p_week, b.bucket_no, b.round, m), p_week, ver,
          public.referee_new_seed(), ea.account_id, eb.account_id, ea.snapshot, eb.snapshot,
          public.referee_level_of(ea.snapshot),
          jsonb_build_object('bucket', b.bucket_no, 'round', b.round, 'match', m, 'seed0', s0, 'seed1', s1))
        on conflict (match_key) do nothing;
      get diagnostics k = row_count;
      added := added + k;
    end loop;
  end loop;
  return added;
end $$;
revoke all on function public.referee_enqueue_finals(bigint) from public, anon, authenticated;

-- ⑤ 周六：服务端战绩账本 + 交阵容 / 查结果 ─────────────────
create table if not exists public.gauntlet_records (
  season_week  bigint      not null,
  account_id   uuid        not null references auth.users(id) on delete cascade,
  gw           int         not null default 0,
  gl           int         not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (season_week, account_id)
);
alter table public.gauntlet_records enable row level security;
drop policy if exists gauntlet_records_self on public.gauntlet_records;
create policy gauntlet_records_self on public.gauntlet_records for select using (auth.uid() = account_id);
-- 写只有 referee_complete（没有 insert / update 策略）

-- 客户端点「开战」：交自己的阵容快照 + 对手快照（对手照旧由客户端从 gauntlet_ghosts / 机器人里挑 —— 未决点见 README）。
-- 种子服务端生成；同一个人同一时刻只有一场在算（在算的那场直接把号还给他）；
-- 只有「上一次算失败了」才允许同一场重交，且种子不换（不许换种子刷结果）。
create or replace function public.referee_submit_gauntlet(p_week bigint, p_snapshot jsonb, p_opponent jsonb,
    p_client_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text;
        jid bigint; mid uuid; st text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  if not exists (select 1 from public.referee_versions where client_version = p_client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (now() >= to_timestamp(p_week + 5 * 86400) and now() < to_timestamp(p_week + 6 * 86400)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') <> 3
     or jsonb_typeof(p_snapshot->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  if p_opponent is null or jsonb_typeof(p_opponent) <> 'object' or octet_length(p_opponent::text) > 65536
     or jsonb_typeof(p_opponent->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_opponent');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true);
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, null,
      p_snapshot, p_opponent, public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl))
    on conflict (match_key) do update
      set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null,
          a_snapshot = excluded.a_snapshot, b_snapshot = excluded.b_snapshot,
          client_version = excluded.client_version, level = excluded.level, created_at = now()
      where public.referee_jobs.status = 'failed'
    returning job_id, match_id into jid, mid;
  if jid is null then
    select job_id, match_id, status into jid, mid, st from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid);
end $$;
revoke all on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) from public, anon;
grant execute on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) to authenticated;

-- 查自己那一场算完没有（只认 a_account = 自己；不回快照）。录像本体在 matches（按 match_id 读）。
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
    'won', j.result->'ledger'->'won', 'score', j.result->'ledger'->'score',
    'gw', j.result->'ledger'->'gw', 'gl', j.result->'ledger'->'gl',
    'error', case when j.status = 'failed' then j.error end);
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ⑥ 裁判机 RPC（只有 service_role）─────────────────────────
-- 领活：只领自己装了的版本；租期过了没写回的一并收回重领；次数用尽的判 failed。返回任务单数组（jsonb）。
-- ★for update skip locked：N 个裁判进程并发领不会领到同一份。
create or replace function public.referee_claim(p_worker text, p_versions text[], p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_out jsonb;
begin
  select * into cfg from public.referee_config where id = 1;
  insert into public.referee_workers (worker, versions, seen_at) values (p_worker, coalesce(p_versions, '{}'), now())
    on conflict (worker) do update set versions = excluded.versions, seen_at = now();
  update public.referee_jobs
     set status = 'failed', error = coalesce(error, 'lease_expired'), done_at = now()
   where status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)
     and attempts >= cfg.max_attempts;
  with c as (
    select job_id from public.referee_jobs
     where client_version = any(coalesce(p_versions, '{}'))
       and (status = 'pending'
            or (status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)))
     order by created_at, job_id
     limit greatest(1, least(coalesce(p_limit, 1), 32))
     for update skip locked
  ), u as (
    update public.referee_jobs j
       set status = 'claimed', claimed_by = p_worker, claimed_at = now(), attempts = j.attempts + 1
      from c where j.job_id = c.job_id
    returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'v', 1, 'job_id', u.job_id, 'match_id', u.match_id, 'mode', u.kind,
           'key', u.meta || jsonb_build_object('week', u.season_week, 'match_key', u.match_key),
           'seed', u.seed, 'client_version', u.client_version, 'level', u.level,
           'a', u.a_snapshot, 'b', u.b_snapshot) order by u.job_id), '[]'::jsonb)
    into v_out from u;
  return v_out;
end $$;
revoke all on function public.referee_claim(text, text[], int) from public, anon, authenticated;
grant execute on function public.referee_claim(text, text[], int) to service_role;

-- 写回：校验结果单与任务单一致 ⇒ 一个事务里落 matches（录像）+ 赛果（周日 finals_results / 周六 gauntlet_records + gauntlet_ghosts）。
-- ★幂等：已 done 的再写回一次直接回 ok（网络重试）；只有当前持有者能写（租期过了被别人重领 ⇒ 旧持有者写不进）。
-- ★周日那一场若已经有结果（开关打开之前客户端报过 / 3 倍时长兜底补判过）⇒ 不改，任务记 superseded（录像照样落）。
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
begin
  select * into j from public.referee_jobs where job_id = p_job_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  if j.status = 'done' then
    return jsonb_build_object('ok', true, 'reason', 'already_done');
  end if;
  if j.status <> 'claimed' or j.claimed_by is distinct from p_worker then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or coalesce(p_result->>'ok', 'false') <> 'true'
     or p_result->>'match_id' is distinct from j.match_id::text
     or jsonb_typeof(p_result->'seed') <> 'number' or (p_result->>'seed')::numeric <> j.seed
     or p_result->>'client_version' is distinct from j.client_version
     or coalesce(p_result->>'winner', '') not in ('a', 'b')
     or jsonb_typeof(p_result->'steps') <> 'number' or (p_result->>'steps')::numeric <= 0
     or jsonb_typeof(p_result->'replay_b64') <> 'string'
     or octet_length(p_result->>'replay_b64') not between 1 and 65536      -- = matches_replay_size = 客户端 REPLAY_MAX_B64
     or (p_result->>'replay_b64') !~ '^[A-Za-z0-9+/]+={0,2}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_result');
  end if;
  won := p_result->>'winner' = 'a';
  sc := case when jsonb_typeof(p_result->'score_code') = 'number' then (p_result->>'score_code')::numeric::int else -1 end;
  res := jsonb_build_object('won', won, 'steps', (p_result->>'steps')::numeric::int, 'surrendered', false,
                            'referee', true, 'score', sc);
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.a_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.a_account, case when won then 1 else 0 end, case when won then 0 else 1 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw, v_gl;
    res := res || jsonb_build_object('gw', v_gw, 'gl', v_gl);
    -- 以打完这一场的新战绩标签挂进快照池（同 E-A4：下一场要找的是「跟我现在同样几胜几负」的人）
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version)
      values (j.a_account, j.season_week, v_gw, v_gl, j.a_snapshot, j.client_version)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, uploaded_at = now();
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- 报错：permanent（任务单本身不对，重算也一样）或次数用尽 ⇒ failed；否则放回 pending 给下一个裁判。
create or replace function public.referee_fail(p_job_id bigint, p_worker text, p_error text, p_permanent boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; n int;
begin
  select * into cfg from public.referee_config where id = 1;
  update public.referee_jobs
     set status = case when coalesce(p_permanent, false) or attempts >= cfg.max_attempts then 'failed' else 'pending' end,
         done_at = case when coalesce(p_permanent, false) or attempts >= cfg.max_attempts then now() end,
         error = left(coalesce(p_error, '?'), 500), claimed_by = null, claimed_at = null
   where job_id = p_job_id and status = 'claimed' and claimed_by = p_worker;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;
revoke all on function public.referee_fail(bigint, text, text, boolean) from public, anon, authenticated;
grant execute on function public.referee_fail(bigint, text, text, boolean) to service_role;

-- 监控：积压多少、最老的等了多久、裁判机最后一次心跳。告警阈值见 README（例：pending 最老 > 120 秒 或 心跳 > 120 秒）。
create or replace function public.referee_backlog()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pending', (select count(*) from public.referee_jobs where status = 'pending'),
    'claimed', (select count(*) from public.referee_jobs where status = 'claimed'),
    'failed_24h', (select count(*) from public.referee_jobs where status = 'failed' and done_at > now() - interval '24 hours'),
    'oldest_pending_sec', (select coalesce(extract(epoch from now() - min(created_at))::int, 0)
                             from public.referee_jobs where status = 'pending'),
    'workers', (select coalesce(jsonb_agg(jsonb_build_object('worker', worker, 'versions', versions,
                  'seen_sec', extract(epoch from now() - seen_at)::int)), '[]'::jsonb) from public.referee_workers))
$$;
revoke all on function public.referee_backlog() from public, anon, authenticated;
grant execute on function public.referee_backlog() to service_role;

-- 清理：已结束（done / failed）超过 14 天的任务（录像本体在 matches，按它自己的周清走）。每天 04:40 UTC。
create or replace function public.referee_purge() returns void
language sql security definer as $$
  delete from public.referee_jobs where status in ('done', 'failed') and done_at < now() - interval '14 days';
$$;
revoke all on function public.referee_purge() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'referee_purge';
select cron.schedule('referee_purge', '40 4 * * *', 'select public.referee_purge()');

-- ⑦ 三个现行函数加开关分支（正文照抄 schema.sql 现行最后一版，只在标了「2026-10-19 服务器裁判」的地方加了分支）──

create or replace function public.finals_advance(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; moved int := 0; want int; got int; slots int; total int;
        real_want int;
begin
  -- ★2026-10-19 服务器裁判: 购物窗一关就给本轮每一场真实对局建裁判任务(幂等; 开关关着时什么都不做)
  if public.referee_finals_on() then
    perform public.referee_enqueue_finals(p_week);
  end if;
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
    if public.referee_finals_on()
       and now() < b.round_at + make_interval(secs => public.finals_round_sec() * 3) then
      -- ★2026-10-19 服务器裁判: 真实场次只认裁判写回的结果(referee_complete), 这里只补轮空
      --   (第 1 轮下侧座位空着 = 真人晋级, 与原来补 side 0 同一个结果)。
      --   硬上限 3 倍本轮时长: 过了还没结果(裁判机挂了 / 任务失败)才走下面 else —— 原来那条 side 0 兜底。
      insert into public.finals_results
        (season_week, bucket_no, round, match_no, winner_side, seed_used)
        select p_week, b.bucket_no, b.round, g.m, 0, 0
          from generate_series(0, want - 1) as g(m)
         where b.round = 1
           and not (public.finals_seed_at_seat(slots, 2 * g.m + 1) between 0 and b.n - 1)
        on conflict (season_week, bucket_no, round, match_no) do nothing;
      select count(*) into got from public.finals_results
       where season_week = p_week and bucket_no = b.bucket_no and round = b.round;
      if got < want then
        continue;                        -- 还有真实场次在等裁判
      end if;
    else
      insert into public.finals_results
        (season_week, bucket_no, round, match_no, winner_side, seed_used)
        select p_week, b.bucket_no, b.round, g.m, 0, 0
          from generate_series(0, want - 1) as g(m)
        on conflict (season_week, bucket_no, round, match_no) do nothing;
    end if;
    if b.round >= total then
      update public.finals_buckets set closed = true, revealed_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = now(), revealed_at = now()
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;

revoke all on function public.finals_advance(bigint) from public;
revoke execute on function public.finals_advance(bigint) from anon, authenticated;

create or replace function public.finals_report(p_week bigint, p_bucket int,
    p_round int, p_match int, p_winner_side int, p_seed bigint, p_reporter_side int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; mine int; slots int := 1; n_match int; bye_seed int; open_at timestamptz;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- ★2026-10-19 服务器裁判: 开关开着时结果只由裁判机写(referee_complete), 客户端上报一律不收
  if public.referee_finals_on() then
    return jsonb_build_object('ok', false, 'reason', 'referee');
  end if;
  select * into b from public.finals_buckets
   where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return jsonb_build_object('ok', false, 'reason', 'no_bucket');
  end if;
  if p_round <> b.round then
    return jsonb_build_object('ok', false, 'reason', 'wrong_round', 'round', b.round);
  end if;
  select seed into mine from public.finals_entrants
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  if mine is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_bucket');
  end if;
  if p_winner_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'bad_side');
  end if;
  -- ★2026-10-12: 旧客户端(不带侧别)按旧规矩各打各的 ⇒ 不收
  if p_reporter_side is null or p_reporter_side not in (0, 1) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  open_at := b.round_at + make_interval(secs => public.finals_shop_sec());
  if now() < open_at then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  if p_reporter_side = 1 and now() < open_at + make_interval(secs => public.finals_lower_grace_sec()) then
    return jsonb_build_object('ok', false, 'reason', 'upper_first');
  end if;
  -- 场号必须是本轮真实存在的场(20261011_finals_report_guard ①)
  while slots < greatest(b.n, 1) loop
    slots := slots * 2;
  end loop;
  n_match := greatest(1, slots / (2 ^ p_round)::int);
  if p_match < 0 or p_match >= n_match then
    return jsonb_build_object('ok', false, 'reason', 'bad_match', 'n_match', n_match);
  end if;
  -- 第 1 轮轮空场不收(20261011_finals_report_guard ②)
  if p_round = 1 then
    bye_seed := public.finals_seed_at_seat(slots, 2 * p_match + 1);
    if bye_seed < 0 or bye_seed >= b.n then
      return jsonb_build_object('ok', false, 'reason', 'bye');
    end if;
  end if;
  insert into public.finals_results
    (season_week, bucket_no, round, match_no, winner_side, seed_used)
    values (p_week, p_bucket, p_round, p_match, p_winner_side, coalesce(p_seed, 0))
    on conflict (season_week, bucket_no, round, match_no) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.finals_report(bigint, int, int, int, int, bigint, int) from public, anon;
grant execute on function public.finals_report(bigint, int, int, int, int, bigint, int) to authenticated;

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
  -- ★2026-10-19 服务器裁判: 周六战绩由裁判记账(gauntlet_records)之后, 晋级线与种子排序都用账本上的数,
  --   不再信客户端报的 p_gw / p_gl(原来那条「已知缺口」由此补上)。
  if public.referee_gauntlet_on() then
    select coalesce(max(r.gw), 0), coalesce(max(r.gl), 0) into p_gw, p_gl
      from public.gauntlet_records r where r.season_week = p_week and r.account_id = auth.uid();
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
-- <<< END referee_jobs 20261019 <<<

-- >>> BEGIN referee_client_flags 20261019b >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判 · 客户端读开关（2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §3 ①②）—— ★只写文件、未上生产
--   前提：20261019_referee_jobs.sql 已执行（referee_config / referee_finals_on / referee_gauntlet_on）。
--
-- 为什么要它：开关 referee_config.finals_on / gauntlet_on 在服务端，而客户端要据它决定
--   「周日点开自己那一场 = 看还是打」「周六点开战 = 交给服务器还是本机打」。referee_config 开了 RLS 且没有任何策略
--   （客户端读不到），referee_finals_on() / referee_gauntlet_on() 也收回了执行权 ⇒ 加一个只读、只回两个布尔的函数。
--   客户端：scripts/net/referee_net.gd（refresh_flags_async；问到就落进本机存档，断网冷启动也知道上次是开是关）。
--
-- ★只读、不回别的（版本号 / 租期 / 积压都不回）；anon 也能调（与 service_status 同一口径：未登录时也该知道）。
-- ★客户端认 404（本函数没部署）= 两个开关都关 ⇒ 执行之前与之后，开关关着时行为完全一样。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on())
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END referee_client_flags 20261019b <<<
-- >>> BEGIN referee_stream_flag 20261019c >>>
-- ─────────────────────────────────────────────────────────────
-- 逐帧直播 S5 · 客户端开关（2026-10-19 · 方案书 docs/plans/20261019-服务器逐帧直播.md §4 接线 / §5 录像）—— ★只写文件、未上生产
--   前提：20261019_referee_jobs.sql（referee_config）与 20261019b_referee_client_flags.sql（referee_flags）已执行。
--
-- 为什么要它：周六闯关 / 周日决赛 / 赛况板 / 对阵图 / 赛后回放要从「拿录像本机重算」改成「播服务器的状态流」，
--   而服务器要先装上带录流代码的版本、轮询器设好 STREAM_ROOT（server/stream/README.md「打开录流」）才有流可播。
--   在那之前客户端必须照老路走 ⇒ 由服务端下发一个开关，客户端读到「开」才播流。
--     stream_on       开 ⇒ 看服务器算的局一律播状态流（手机一步 sim 都不跑）；关 ⇒ 现行行为（录像本机重算），一字不变
--     stream_version  裁判机从哪个客户端版本起才录流（'' = 不限）。客户端版本低于它 ⇒ 当作关
--   客户端：scripts/net/referee_net.gd（parse_flags / stream_on），scripts/systems/replay/stream_watch.gd（各入口的分流）。
--
-- ★只读函数照旧只回布尔 + 一个版本串，不回租期 / 积压等。anon 也能调（与 20261019b 同一口径）。
-- ★客户端读不到这两个键（本迁移没上 / 回包是 20261019b 那一版）⇒ 当作关；referee_flags 本身 404 ⇒ 全关。
--   ⇒ 执行本迁移本身不改变任何现行行为（两列默认 false / ''）。
-- ★打开顺序（反过来会让手机去拉一份不存在的流，只能显示「画面无法播放」）：
--   ① 裁判机装上新版本工程 + `STREAM_ROOT` 写进 /etc/turtle-referee/env 并重启轮询器（server/stream/README.md）
--   ② 冒烟：内测服跑一局，确认 https://stream.turtlearena.xyz/streams/<match_id>/end.json 带新版本头能拿到 200
--   ③ update public.referee_config set stream_on = true, stream_version = '<①那个版本>', updated_at = now() where id = 1;
--   回滚 = stream_on 翻回 false（客户端下次问到开关即回到老路；已经在看的那一场照常播完）。
-- ★重复执行安全（add column if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

alter table public.referee_config add column if not exists stream_on boolean not null default false;
alter table public.referee_config add column if not exists stream_version text not null default '';

create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on(),
                            'stream_on', coalesce((select c.stream_on from public.referee_config c where c.id = 1), false),
                            'stream_version', coalesce((select c.stream_version from public.referee_config c where c.id = 1), ''))
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END referee_stream_flag 20261019c <<<
-- >>> BEGIN referee_live_list 20261020 >>>
-- ─────────────────────────────────────────────────────────────
-- 逐帧直播 · 周六观赛「正在算」的裁判局 + 旧裁判局按需补流（2026-10-20 · 方案书 docs/plans/20261019-服务器逐帧直播.md §4.1 / §5）
--   ★只写文件、未上生产。前提：20261019_referee_jobs.sql（referee_jobs / referee_config / referee_versions）已执行。
--
-- 本段内容（全是添加，或给只读函数多回一个键；执行本段不改变任何现行行为）：
--   ① referee_live_gauntlet()               本周周六正在算（status = claimed、租期内）的闯关裁判任务（赛况板「观赛」）。
--      只回 match_id / 开始时刻 / 版本 / 种子 / 双方 profile 的名字·头像·#ID；★不回快照（阵容 / 装备）。
--      anon 不可，authenticated 可。种子只用来让手机选同一张地图（结果由服务器算，手机不算）。
--   ② referee_restream（表）+ referee_request_restream(p_match_id)（authenticated）：
--      开流之前算的裁判局（或录流失败过的）没有状态流 ⇒ 客户端请求补流：裁判机按原任务的快照 + 种子再算一遍，**只产出流**，
--      不写回结果、不改账（不调 referee_complete）。同一场只排一次（match_id 主键）；排队上限 50；
--      done / failed 超过 10 分钟的可以重排（流被清掉了 / 上次失败了）。
--      referee_claim_restream(...) / referee_restream_done(...)：只有 service_role（裁判机轮询器，server/referee/referee_poller.py）。
--      任务单形状 = referee_claim 的那一份 + task = 'restream' + expect_winner / expect_digest（原结果；重算对不上 ⇒ 撤流、判失败）。
--   ③ finals_replay() 多回一个键 referee（这一行是不是裁判写回的：matches.result->>'referee'），正文其余逐字照抄 schema.sql 现行版。
--      客户端（scripts/net/match_fetch.gd）认出裁判局 ⇒ 没有流时请求补流，永不本机重算。
--   客户端：scripts/net/referee_net.gd（live_gauntlet_async / request_restream_async）、scripts/systems/replay/stream_watch.gd。
--   客户端读不到（本段没上 = 404）⇒ 赛况板照旧只有直播行；补流请求 404 ⇒ 屏上「画面无法播放」（与改之前相同）。
-- ★重复执行安全（create if not exists / create or replace / unschedule 再 schedule）。
-- ─────────────────────────────────────────────────────────────

-- ① 周六正在算的裁判局 ─────────────────────────────────────
create or replace function public.referee_live_gauntlet()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg record; wk bigint; v jsonb;
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;
  select * into cfg from public.referee_config where id = 1;
  wk := extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
  select coalesce(jsonb_agg(jsonb_build_object(
           'match_id', j.match_id, 'started_at', j.claimed_at, 'updated_at', now(),
           'client_version', j.client_version, 'seed', j.seed,
           'lp', jsonb_build_object('name', coalesce(j.a_snapshot->'profile'->>'name', ''),
                                   'avatar', coalesce(j.a_snapshot->'profile'->>'avatar', ''),
                                   'id', coalesce(j.a_snapshot->'profile'->>'id', ''),
                                   'tag', coalesce(j.a_snapshot->'profile'->>'tag', '')),
           'rp', jsonb_build_object('name', coalesce(j.b_snapshot->'profile'->>'name', ''),
                                   'avatar', coalesce(j.b_snapshot->'profile'->>'avatar', ''),
                                   'id', coalesce(j.b_snapshot->'profile'->>'id', ''),
                                   'tag', coalesce(j.b_snapshot->'profile'->>'tag', '')))
         order by j.claimed_at desc), '[]'::jsonb)
    into v
    from (select * from public.referee_jobs
           where kind = 'gauntlet' and season_week = wk and status = 'claimed'
             and claimed_at > now() - make_interval(secs => coalesce(cfg.lease_sec, 180))
           order by claimed_at desc
           limit 50) j;
  return v;
end $$;
revoke all on function public.referee_live_gauntlet() from public, anon;
grant execute on function public.referee_live_gauntlet() to authenticated;

-- ② 按需补流 ─────────────────────────────────────────────────
create table if not exists public.referee_restream (
  match_id       uuid        primary key,                 -- = 原任务 / 录像 / 状态流目录的 match_id
  job_id         bigint      not null,                    -- 原任务（快照 / 种子 / 等级 / 版本都从它取）
  client_version text        not null,
  status         text        not null default 'pending' check (status in ('pending', 'claimed', 'done', 'failed')),
  attempts       int         not null default 0,
  claimed_by     text,
  claimed_at     timestamptz,
  error          text,
  requested_by   uuid,
  created_at     timestamptz not null default now(),
  done_at        timestamptz
);
create index if not exists referee_restream_queue_idx on public.referee_restream (status, created_at)
  where status in ('pending', 'claimed');
alter table public.referee_restream enable row level security;
-- 没有任何策略 ⇒ 客户端直连读写都不行；只有下面的 security definer 函数碰得到

create or replace function public.referee_request_restream(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m record; j record; ex record; n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select match_id, result into m from public.matches where match_id = p_match_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_match');
  end if;
  if coalesce(m.result->>'referee', 'false') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', 'not_referee');     -- 本机局：手机重算那条路，不归裁判机
  end if;
  select * into ex from public.referee_restream where match_id = p_match_id;
  if found and not (ex.status in ('done', 'failed') and ex.done_at < now() - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'status', ex.status);
  end if;
  select job_id, client_version into j from public.referee_jobs
   where match_id = p_match_id and status = 'done' and kind in ('gauntlet', 'finals')
   order by job_id desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');          -- 原任务已清（14 天）
  end if;
  if not exists (select 1 from public.referee_versions where client_version = j.client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'no_version');      -- 裁判机已不装那个版本
  end if;
  select count(*) into n from public.referee_restream where status in ('pending', 'claimed');
  if n >= 50 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;
  insert into public.referee_restream (match_id, job_id, client_version, requested_by)
    values (p_match_id, j.job_id, j.client_version, uid)
    on conflict (match_id) do update
      set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
          job_id = excluded.job_id, client_version = excluded.client_version,
          requested_by = excluded.requested_by, created_at = now()
      where public.referee_restream.status in ('done', 'failed');
  return jsonb_build_object('ok', true, 'status', 'pending');
end $$;
revoke all on function public.referee_request_restream(uuid) from public, anon;
grant execute on function public.referee_request_restream(uuid) to authenticated;

-- 裁判机领补流任务（正常任务领不到时才来领：轮询器先 referee_claim，空了才 referee_claim_restream）。
create or replace function public.referee_claim_restream(p_worker text, p_versions text[], p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_out jsonb;
begin
  select * into cfg from public.referee_config where id = 1;
  update public.referee_restream
     set status = 'failed', error = coalesce(error, 'lease_expired'), done_at = now()
   where status = 'claimed' and claimed_at < now() - make_interval(secs => cfg.lease_sec)
     and attempts >= cfg.max_attempts;
  with c as (
    select r.match_id from public.referee_restream r
     where r.client_version = any(coalesce(p_versions, '{}'))
       and (r.status = 'pending'
            or (r.status = 'claimed' and r.claimed_at < now() - make_interval(secs => cfg.lease_sec)))
     order by r.created_at, r.match_id
     limit greatest(1, least(coalesce(p_limit, 1), 8))
     for update skip locked
  ), u as (
    update public.referee_restream r
       set status = 'claimed', claimed_by = p_worker, claimed_at = now(), attempts = r.attempts + 1
      from c where r.match_id = c.match_id
    returning r.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'v', 1, 'task', 'restream', 'job_id', j.job_id, 'match_id', j.match_id, 'mode', j.kind,
           'key', j.meta || jsonb_build_object('week', j.season_week, 'match_key', j.match_key),
           'seed', j.seed, 'client_version', j.client_version, 'level', j.level,
           'a', j.a_snapshot, 'b', j.b_snapshot,
           'expect_winner', j.result->>'winner', 'expect_digest', j.result->>'digest') order by u.created_at), '[]'::jsonb)
    into v_out
    from u join public.referee_jobs j on j.job_id = u.job_id;
  return v_out;
end $$;
revoke all on function public.referee_claim_restream(text, text[], int) from public, anon, authenticated;
grant execute on function public.referee_claim_restream(text, text[], int) to service_role;

-- 补流写回：只记状态（流本身已由轮询器发布到裁判机的对外目录）。★不碰 matches / 赛果 / 账本。
create or replace function public.referee_restream_done(p_match_id uuid, p_worker text, p_ok boolean,
    p_error text default null, p_permanent boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; n int;
begin
  select * into cfg from public.referee_config where id = 1;
  update public.referee_restream
     set status = case when coalesce(p_ok, false) then 'done'
                       when coalesce(p_permanent, false) or attempts >= cfg.max_attempts then 'failed'
                       else 'pending' end,
         done_at = case when coalesce(p_ok, false) or coalesce(p_permanent, false) or attempts >= cfg.max_attempts
                        then now() end,
         error = case when coalesce(p_ok, false) then null else left(coalesce(p_error, '?'), 500) end,
         claimed_by = null, claimed_at = null
   where match_id = p_match_id and status = 'claimed' and claimed_by = p_worker;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;
revoke all on function public.referee_restream_done(uuid, text, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.referee_restream_done(uuid, text, boolean, text, boolean) to service_role;

-- 清理：结束超过 14 天的补流记录（与 referee_purge 同口径）。每天 04:45 UTC。
create or replace function public.referee_restream_purge() returns void
language sql security definer as $$
  delete from public.referee_restream where status in ('done', 'failed') and done_at < now() - interval '14 days';
$$;
revoke all on function public.referee_restream_purge() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'referee_restream_purge';
select cron.schedule('referee_restream_purge', '45 4 * * *', 'select public.referee_restream_purge()');

-- ③ finals_replay 多回 referee（正文照抄 schema.sql 现行版，只改了 select 多取 result 与最后一行回包）─────
create or replace function public.finals_replay(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b record; sd bigint; mid uuid; rp text; res jsonb;
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
  select m.match_id, m.replay, m.result into mid, rp, res from public.matches m
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
  return jsonb_build_object('ok', true, 'match_id', mid, 'replay', rp,
                            'referee', coalesce(res->>'referee', 'false') = 'true');
end $$;

revoke all on function public.finals_replay(bigint, int, int, int) from public;
revoke execute on function public.finals_replay(bigint, int, int, int) from anon;
grant execute on function public.finals_replay(bigint, int, int, int) to authenticated;
-- <<< END referee_live_list 20261020 <<<

-- >>> BEGIN account_delete_and_reports 20261020b >>>
-- ─────────────────────────────────────────────────────────────
-- 应用内删除账号 + 昵称举报（2026-10-20 · 方案书 docs/plans/20261020-AppStore上架.md §4.2 / D8）
--   上架硬要求：App Store 审核指南 5.1.1(v)「支持建号就必须能在 App 内删号」（游客号同样适用）；
--   1.2「用户生成内容」要有举报 + 屏蔽。屏蔽（拉黑）只存在玩家本机，服务端不参与。
--   客户端：设置 → 账号 →「删除账号」（scripts/net/account_delete.gd · scripts/scenes/settings/account_delete_dialog.gd）；
--           排行榜 / 赛况板 / 对阵图 / 对局顶栏 → 玩家菜单「举报昵称」（scripts/net/report_net.gd · scripts/scenes/social/player_menu.gd）。
--
-- 本文件做五件事：
--   ① player_tag_of(text)：玩家 ID（#XXXXXX）的服务端算法，与客户端 phase2_config.player_tag 逐位相同
--   ② finals_entrants.account_id 改成 on delete set null：周日组里有人删号，那个种子位与快照保留（匿名），
--      别人的对阵图 / 代打 / 录像不坏（原来是 cascade：删号会在组里挖掉一个种子）
--   ③ account_delete_self()：只删调用者本人（auth.uid()），先把留在别人可见处的昵称 / 头像 / 玩家 ID 抹成占位，
--      再删 auth.users（其余表靠 on delete cascade / set null）
--   ④ nickname_reports + report_nickname()：举报一条昵称（同一人对同一玩家 ID 24 小时一次，每人每天最多 20 条）
--   ⑤ 管理侧：视图 nickname_reports_pending（待处理，只读）+ nickname_report_resolve()（重置为默认昵称 / 驳回）
--      + nickname_resets + my_nickname_reset()（客户端开机查一次，自己的昵称被重置过就换回默认昵称）
--
-- ★本文件只建表 / 建函数 / 改一条外键，不删任何已有数据。重复执行安全。
-- ★上生产前先跑 server/supabase/tests/20261020b_account_delete_and_reports_check.sql（整段在一个事务里，结尾 rollback）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 玩家 ID ═══
-- 客户端（phase2_config.gd player_tag）：sha256("turtle-id:" + 身份串) 取前 12 位十六进制 → 48 位整数 →
--   连除 28 取 6 位（低位在右），字母表 23456789BCDFGHJKMNPQRSTVWXYZ，前面加 #。身份串 = account_id（小写带横线的 uuid）。
-- 门禁 tests/verify_account_delete.gd 用客户端算出的几组号与本函数的写法逐字对账（测试脚本里也逐条比）。
create or replace function public.player_tag_of(p_identity text) returns text
language plpgsql immutable set search_path = public as $$
declare h text; v bigint; alpha text := '23456789BCDFGHJKMNPQRSTVWXYZ'; o text := ''; i int;
begin
  if p_identity is null or p_identity = '' then
    return '';
  end if;
  h := encode(sha256(convert_to('turtle-id:' || p_identity, 'UTF8')), 'hex');
  v := ('x' || substr(h, 1, 12))::bit(48)::bigint;
  for i in 1..6 loop
    o := substr(alpha, (v % 28)::int + 1, 1) || o;
    v := v / 28;
  end loop;
  return '#' || o;
end $$;
revoke all on function public.player_tag_of(text) from public, anon, authenticated;

-- 一份快照里的 profile 换成占位（快照没有 profile 就原样返回）。
create or replace function public.profile_scrub(p_snap jsonb, p_profile jsonb) returns jsonb
language sql immutable as $$
  select case when jsonb_typeof(p_snap) = 'object' and jsonb_typeof(p_snap->'profile') = 'object'
              then jsonb_set(p_snap, '{profile}', (p_snap->'profile') || p_profile)
              else p_snap end
$$;
revoke all on function public.profile_scrub(jsonb, jsonb) from public, anon, authenticated;

-- ═══ ② finals_entrants：删号不挖掉种子位 ═══
alter table public.finals_entrants alter column account_id drop not null;
do $$
declare c text;
begin
  for c in
    select con.conname from pg_constraint con
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
     where con.conrelid = 'public.finals_entrants'::regclass and con.contype = 'f' and a.attname = 'account_id'
  loop
    execute format('alter table public.finals_entrants drop constraint %I', c);
  end loop;
end $$;
alter table public.finals_entrants
  add constraint finals_entrants_account_id_fkey
  foreign key (account_id) references auth.users(id) on delete set null;

-- ═══ ④ 举报表（③ 要删它的行，所以先建）═══
create table if not exists public.nickname_reports (
  report_id        bigint      generated always as identity primary key,
  reporter         uuid        not null references auth.users(id) on delete cascade,
  reported_tag     text        not null check (reported_tag ~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$'),
  reported_account uuid        references auth.users(id) on delete cascade,   -- 服务端按玩家 ID 反查；null = 查不到（机器人 / 已删号）
  name_snapshot    text        not null check (char_length(name_snapshot) between 1 and 40),
  context          text        not null default '' check (char_length(context) <= 24),
  status           text        not null default 'pending' check (status in ('pending', 'reset', 'dismissed')),
  created_at       timestamptz not null default now(),
  handled_at       timestamptz
);
create index if not exists nickname_reports_dedupe_idx on public.nickname_reports (reporter, reported_tag, created_at desc);
create index if not exists nickname_reports_pending_idx on public.nickname_reports (status, created_at) where status = 'pending';
alter table public.nickname_reports enable row level security;
-- 不建任何 policy ⇒ 客户端直连读写一律被拒；只经下面的 security definer 函数。
revoke all on public.nickname_reports from anon, authenticated, public;

-- 被重置过的昵称（管理员处理举报时写）。客户端开机经 my_nickname_reset() 查自己的。
create table if not exists public.nickname_resets (
  account_id   uuid        not null references auth.users(id) on delete cascade,
  banned_name  text        not null,
  created_at   timestamptz not null default now(),
  primary key (account_id, banned_name)
);
alter table public.nickname_resets enable row level security;
revoke all on public.nickname_resets from anon, authenticated, public;

-- ═══ ③ 删除账号 ═══
-- ★只删 auth.uid() 本人：函数不收任何参数，没有「删别人」的写法。
-- ★别人看得见的地方先抹名字再删号：
--   · matches（录像行）：自己那一侧（left_account = 我）+ 任一侧快照里玩家 ID 是我的（我当别人对手的那些场）
--   · live_matches 别人的直播行里我当对手的那一侧（我自己的行随 cascade 删掉）
--   · referee_jobs 双方快照（a_account / b_account = 我，或快照里玩家 ID 是我）；我自己还没算的周六任务直接作废
--   · finals_entrants 名字 + 快照（行保留，account_id 随 ② 变 null）
--   · referee_restream.requested_by
--   · nickname_reports 里与我有关的举报（我举报的 / 举报我的）
-- ★占位：名字「已注销玩家」，头像 basic，id deleted，玩家 ID 换成一串随机号（同一次删号的各行一致，
--   赛况板按玩家 ID 归并成一个人；与原号无关，反推不回去）。
-- ★录像本体（matches.replay，客户端二进制）里记着对手的快照，SQL 改不了 —— 它随 purge_old_matches 每周一清空；
--   隐私政策 §1.9 写明了这一条。
create or replace function public.account_delete_self() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid   uuid := auth.uid();
  tags  text[];
  ph    jsonb;
  n_m   int := 0; n_l int := 0; n_j int := 0; n_f int := 0; tmp_n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  -- 我用过的玩家 ID：按账号算的那一个 + 我上传过的快照里实际带着的（老客户端曾按安装号算）
  select coalesce(array_agg(distinct t), '{}') into tags from (
    select public.player_tag_of(uid::text) as t
    union select snapshot->'profile'->>'tag' from public.ghosts where account_id = uid
    union select snapshot->'profile'->>'tag' from public.gauntlet_ghosts where account_id = uid
    union select left_snapshot->'profile'->>'tag' from public.matches where left_account = uid
    union select left_snapshot->'profile'->>'tag' from public.live_matches where account_id = uid
    union select snapshot->'profile'->>'tag' from public.finals_entrants where account_id = uid
    union select snapshot->'profile'->>'tag' from public.finals_pending where account_id = uid
    union select a_snapshot->'profile'->>'tag' from public.referee_jobs where a_account = uid
    union select b_snapshot->'profile'->>'tag' from public.referee_jobs where b_account = uid
  ) s where t is not null and t <> '';

  ph := jsonb_build_object('name', '已注销玩家', 'avatar', 'basic', 'id', 'deleted',
                           'tag', public.player_tag_of(gen_random_uuid()::text));

  update public.matches set left_snapshot = public.profile_scrub(left_snapshot, ph)
   where left_account = uid or left_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_m := n_m + tmp_n;
  update public.matches set right_snapshot = public.profile_scrub(right_snapshot, ph)
   where right_account = uid or right_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_m := n_m + tmp_n;

  update public.live_matches set left_snapshot = public.profile_scrub(left_snapshot, ph)
   where account_id <> uid and left_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_l := n_l + tmp_n;
  update public.live_matches set right_snapshot = public.profile_scrub(right_snapshot, ph)
   where account_id <> uid and right_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_l := n_l + tmp_n;

  -- 我自己还没算完的周六任务：作废（只有我一个人在等它的结果）
  update public.referee_jobs set status = 'failed', error = 'account_deleted', done_at = now(),
         claimed_by = null, claimed_at = null
   where kind = 'gauntlet' and a_account = uid and status in ('pending', 'claimed');
  update public.referee_jobs set a_snapshot = public.profile_scrub(a_snapshot, ph), meta = meta - 'account'
   where a_account = uid or a_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_j := n_j + tmp_n;
  update public.referee_jobs set b_snapshot = public.profile_scrub(b_snapshot, ph)
   where b_account = uid or b_snapshot->'profile'->>'tag' = any(tags);
  get diagnostics tmp_n = row_count; n_j := n_j + tmp_n;

  update public.finals_entrants set name = ph->>'name', snapshot = public.profile_scrub(snapshot, ph)
   where account_id = uid;
  get diagnostics n_f = row_count;

  update public.referee_restream set requested_by = null where requested_by = uid;

  delete from public.nickname_reports
   where reporter = uid or reported_account = uid or reported_tag = any(tags);

  -- 其余表（accounts / ghosts / gauntlet_ghosts / saves / standings / finals_pending / finals_scout /
  --   live_matches 我自己的行 / gauntlet_records / client_errors / player_feedback / nickname_resets）随 cascade 删；
  --   matches.left/right_account、referee_jobs.a/b_account、finals_entrants.account_id 随 set null 断开。
  delete from auth.users where id = uid;

  return jsonb_build_object('ok', true, 'scrubbed',
    jsonb_build_object('matches', n_m, 'live', n_l, 'jobs', n_j, 'finals', n_f));
end $$;
revoke all on function public.account_delete_self() from public;
revoke execute on function public.account_delete_self() from anon;
grant execute on function public.account_delete_self() to authenticated;

-- ═══ ④ 举报一条昵称 ═══
-- p_tag：被举报者的玩家 ID（屏幕上那串 #XXXXXX）；p_name：举报时看到的昵称（存快照，对方之后改名也查得到）；
-- p_context：在哪一屏举报的（leaderboard / gauntlet_board / bracket / battle），只做统计。
-- 返回 {ok:true} 或 {ok:false, reason: not_signed_in | bad_tag | bad_name | self | duplicate | limit}。
create or replace function public.report_nickname(p_tag text, p_name text, p_context text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid  uuid := auth.uid();
  nm   text := left(btrim(coalesce(p_name, '')), 40);
  ctx  text := coalesce(p_context, '');
  acc  uuid;
  n    int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_tag is null or p_tag !~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_tag');
  end if;
  if nm = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_name');
  end if;
  if ctx not in ('leaderboard', 'gauntlet_board', 'bracket', 'battle') then
    ctx := '';
  end if;
  -- 同一人对同一玩家 ID 并发两次：串行化，第二次看得见第一次
  perform pg_advisory_xact_lock(hashtext(uid::text || p_tag));
  if exists (select 1 from public.nickname_reports
              where reporter = uid and reported_tag = p_tag and created_at > now() - interval '24 hours') then
    return jsonb_build_object('ok', false, 'reason', 'duplicate');
  end if;
  select count(*) into n from public.nickname_reports
   where reporter = uid and created_at > now() - interval '24 hours';
  if n >= 20 then
    return jsonb_build_object('ok', false, 'reason', 'limit');
  end if;
  -- 玩家 ID → 账号：在快照池里找最近一份带这个号的（机器人 / 已删号 ⇒ null，举报照收）
  select account_id into acc from public.ghosts
   where snapshot->'profile'->>'tag' = p_tag order by uploaded_at desc limit 1;
  if acc is null then
    select account_id into acc from public.gauntlet_ghosts
     where snapshot->'profile'->>'tag' = p_tag order by uploaded_at desc limit 1;
  end if;
  if acc = uid or p_tag = public.player_tag_of(uid::text) then
    return jsonb_build_object('ok', false, 'reason', 'self');
  end if;
  insert into public.nickname_reports (reporter, reported_tag, reported_account, name_snapshot, context)
    values (uid, p_tag, acc, nm, ctx);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.report_nickname(text, text, text) from public;
revoke execute on function public.report_nickname(text, text, text) from anon;
grant execute on function public.report_nickname(text, text, text) to authenticated;

-- ═══ ⑤ 管理侧 ═══
-- 待处理举报：按「玩家 ID + 账号」归并，举报人数多的排前面。只读；只有 service_role / SQL 编辑器看得到。
-- 用法（Supabase SQL 编辑器）：select * from public.nickname_reports_pending;
create or replace view public.nickname_reports_pending with (security_invoker = true) as
  select r.reported_tag,
         r.reported_account,
         (array_agg(r.name_snapshot order by r.created_at desc))[1] as latest_name,
         array_agg(distinct r.name_snapshot) as names,
         count(*)::int as reports,
         count(distinct r.reporter)::int as reporters,
         array_agg(distinct r.context) as contexts,
         min(r.created_at) as first_at,
         max(r.created_at) as last_at
    from public.nickname_reports r
   where r.status = 'pending'
   group by r.reported_tag, r.reported_account
   order by count(distinct r.reporter) desc, max(r.created_at) desc;
revoke all on public.nickname_reports_pending from public, anon, authenticated;
grant select on public.nickname_reports_pending to service_role;

-- 处理一个玩家 ID 的全部待处理举报。
--   p_action = 'reset'   ⇒ 记进 nickname_resets（客户端下次开机把这个名字换回默认昵称），
--                          并把服务端已存的这些名字换成占位「玩家 + 玩家 ID」（排行榜 / 赛况板 / 对阵图立刻不再显示原名）
--   p_action = 'dismiss' ⇒ 只标记已处理，不动昵称
-- 返回 {ok, account, names, scrubbed}。查不到账号（机器人 / 已删号）时 reset 退化成 dismiss（reason = no_account）。
create or replace function public.nickname_report_resolve(p_tag text, p_action text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  acc    uuid;
  names  text[];
  ph     text := '玩家' || substr(coalesce(p_tag, ''), 2);
  n      int := 0; tmp_n int;
begin
  if p_action not in ('reset', 'dismiss') then
    return jsonb_build_object('ok', false, 'reason', 'bad_action');
  end if;
  select coalesce(array_agg(distinct name_snapshot), '{}'),
         (array_agg(reported_account) filter (where reported_account is not null))[1]
    into names, acc
    from public.nickname_reports where reported_tag = p_tag and status = 'pending';
  if cardinality(names) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'nothing_pending');
  end if;
  if acc is null then
    select account_id into acc from public.ghosts
     where snapshot->'profile'->>'tag' = p_tag order by uploaded_at desc limit 1;
  end if;
  if p_action = 'dismiss' or acc is null then
    update public.nickname_reports set status = 'dismissed', handled_at = now()
     where reported_tag = p_tag and status = 'pending';
    return jsonb_build_object('ok', true, 'action', 'dismiss',
      'reason', case when acc is null and p_action = 'reset' then 'no_account' end, 'names', to_jsonb(names));
  end if;
  insert into public.nickname_resets (account_id, banned_name)
    select acc, x from unnest(names) x on conflict do nothing;
  -- 服务端已存的名字换成占位（只换 profile.name 恰好是被举报的那几个的行；之后上传的是客户端换好的默认昵称）
  update public.ghosts set snapshot = jsonb_set(snapshot, '{profile,name}', to_jsonb(ph))
   where account_id = acc and snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.gauntlet_ghosts set snapshot = jsonb_set(snapshot, '{profile,name}', to_jsonb(ph))
   where account_id = acc and snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.matches set left_snapshot = jsonb_set(left_snapshot, '{profile,name}', to_jsonb(ph))
   where left_snapshot->'profile'->>'tag' = p_tag and left_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.matches set right_snapshot = jsonb_set(right_snapshot, '{profile,name}', to_jsonb(ph))
   where right_snapshot->'profile'->>'tag' = p_tag and right_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.live_matches set left_snapshot = jsonb_set(left_snapshot, '{profile,name}', to_jsonb(ph))
   where left_snapshot->'profile'->>'tag' = p_tag and left_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.live_matches set right_snapshot = jsonb_set(right_snapshot, '{profile,name}', to_jsonb(ph))
   where right_snapshot->'profile'->>'tag' = p_tag and right_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.referee_jobs set a_snapshot = jsonb_set(a_snapshot, '{profile,name}', to_jsonb(ph))
   where a_snapshot->'profile'->>'tag' = p_tag and a_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.referee_jobs set b_snapshot = jsonb_set(b_snapshot, '{profile,name}', to_jsonb(ph))
   where b_snapshot->'profile'->>'tag' = p_tag and b_snapshot->'profile'->>'name' = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.finals_entrants set name = ph,
         snapshot = case when snapshot->'profile'->>'name' = any(names)
                         then jsonb_set(snapshot, '{profile,name}', to_jsonb(ph)) else snapshot end
   where account_id = acc and name = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.finals_pending set name = ph,
         snapshot = case when snapshot->'profile'->>'name' = any(names)
                         then jsonb_set(snapshot, '{profile,name}', to_jsonb(ph)) else snapshot end
   where account_id = acc and name = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.accounts set display_name = ph where account_id = acc and display_name = any(names);
  update public.nickname_reports set status = 'reset', handled_at = now()
   where reported_tag = p_tag and status = 'pending';
  return jsonb_build_object('ok', true, 'action', 'reset', 'account', acc, 'names', to_jsonb(names), 'scrubbed', n);
end $$;
revoke all on function public.nickname_report_resolve(text, text) from public, anon, authenticated;
grant execute on function public.nickname_report_resolve(text, text) to service_role;

-- 客户端开机查一次：我有没有被重置过的昵称。返回 {ok:true, names:[...]}（没有 ⇒ 空数组）。只读。
create or replace function public.my_nickname_reset() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); ns jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(banned_name order by created_at), '[]'::jsonb) into ns
    from public.nickname_resets where account_id = uid;
  return jsonb_build_object('ok', true, 'names', ns);
end $$;
revoke all on function public.my_nickname_reset() from public;
revoke execute on function public.my_nickname_reset() from anon;
grant execute on function public.my_nickname_reset() to authenticated;

-- 上线后回读（memory：`revoke from public` 收不掉 anon 的默认授权，必须逐个看）：
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute')
--     from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('account_delete_self', 'report_nickname', 'my_nickname_reset', 'nickname_report_resolve',
--                        'player_tag_of', 'profile_scrub');
--   期望：anon 全 false；authenticated 只有前三个 true；service_role 有 nickname_report_resolve。
-- <<< END account_delete_and_reports 20261020b <<<

-- >>> BEGIN gauntlet_server_pick_and_coins 20261020c >>>
-- ─────────────────────────────────────────────────────────────
-- 周六闯关 · 对手由服务端挑 + 服务器局发战斗内铸币（2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md
--   决策记录「10-20 用户授权自定：周六对手改服务器挑」）—— ★只写文件、未上生产。
--   前提：20261019_referee_jobs.sql / 20261019_min_version_gate.sql（gauntlet_ghosts.rules_ver）/ 20261020_referee_live_list.sql 已执行。
--
-- 两件事：
--   Ⅰ 战斗内铸币（奇械羁绊铸币 + 035 黄铜齿轮）：本机打完由 `_settle_season` 加进奖励，而服务器算的周六局一枚都没发
--     （客户端记账在播之前，拿不到本机重算的数）。⇒ 裁判结果单多一个 `coins`（左方 A 的铸币，`EquipTickSystem.match_minted`，
--     与本机结算读同一个函数），referee_complete 记进账本 `ledger.coins`，referee_job_status 回给客户端，客户端按它发币。
--     ★客户端没有任何参数位能报币数；`coins` 只从裁判机（service_role）的结果单来，夹在 0..999。
--   Ⅱ 周六对手由服务端挑：原来客户端挑好对手快照、连同自己的阵容一起交（referee_submit_gauntlet 的 p_opponent）⇒ 能挑弱对手。
--     新接口 referee_gauntlet_start(p_week, p_snapshot, p_match_no, p_client_version, p_rules_ver)：客户端只交「我的阵容 + 我要打第 N 场」，
--     服务端按现行匹配规则挑对手、生成种子、建任务，回任务号 + 对手卡片（名字 / 头像 / 号 / 三统领；真人与机器人同一形状）。
--       匹配规则（= 客户端 Backend.find_gauntlet_opponent / gauntlet_pool_find，原稿兜底链）：
--         ① 同标签真人（gauntlet_ghosts：同周、gw / gl 完全相同、同 rules_ver、不是自己、本周没碰过）——
--            30 分钟内上传的优先（新鲜度用服务端的 uploaded_at，不信快照自报的 gl_ts），没有新鲜的才用隔夜的；
--         ② 机器人（gauntlet_bot_pool：同 rules_ver、同标签、场次 = 我的本周场次，夹到池子上限 30；本周碰过的那几份排后）。
--         **永不跨标签。** 机器人不露馅：快照与真人同形（摘 origin、按真人口径重写 gl_ts），卡片同形，任务行 / 录像 / 直播行都看不出。
--       机器人快照池由客户端代码离线生成（scripts/referee/bot_pool.gd = Backend.make_bot 同一个函数），
--         轮询器 `referee_poller.py --bot-pool` 对每个装了的版本生成并调 referee_bot_pool_load 上传（只有 service_role）。
--         ★为什么不在裁判机领活时现场生成：快照是数据 ⇒ 任务从建立那一刻起就是完整的（直播行 / 录像行 / 补流都照旧读 b_snapshot），
--           裁判程序一行不改、对确定性零影响；现场生成要多一次「领活 → 生成 → 回写 b_snapshot → 再算」的状态机，
--           而生成失败 / 回写失败都会卡住一场。代价：池子要随版本上传（发版步骤多一步；忘了 ⇒ 挑不到机器人回 no_opponent，健康检查报警）。
--     旧接口 referee_submit_gauntlet：referee_config.gauntlet_server_pick 打开后一律回 update_required（旧包整屏「请更新」）；
--       没打开时逐字照旧（上线顺序见文末）。
--
-- 本段内容（全是添加，或在既有函数里加分支 / 多回键；★gauntlet_server_pick 默认关 ⇒ 执行本段不改变任何现行客户端的行为）：
--   ① referee_config.gauntlet_server_pick、referee_versions.rules_ver
--   ② gauntlet_bot_pool（表）+ referee_bot_pool_load（service_role）
--   ③ referee_lineup_ok / referee_lanes_ok / referee_opp_card / referee_gauntlet_pick（内部，不授权给客户端）
--   ④ referee_gauntlet_start（authenticated）
--   ⑤ 重定义 referee_submit_gauntlet（开关后面加一条拒收）/ referee_job_status（多回 coins）/
--      referee_complete（记 coins；挂进快照池时写 rules_ver —— 原来漏写 = 0，新客户端永远拉不到裁判挂的那份）/
--      referee_backlog（多回机器人池行数，给 --health）
--   正文其余逐字照抄 20261019_referee_jobs.sql 现行版，只在标了「2026-10-20」的地方改。
-- ★重复执行安全（add column if not exists / create if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ① 开关 / 版本的规则号 ─────────────────────────────────────
alter table public.referee_config add column if not exists gauntlet_server_pick boolean not null default false;
-- 每个裁判版本对应的战斗规则版本（phase2_config.RULES_VER）；referee_bot_pool_load 上传时写。null = 还没上传过池子。
alter table public.referee_versions add column if not exists rules_ver int;

-- ② 机器人快照池 ─────────────────────────────────────────────
-- 一行 = 一份机器人快照（Backend.make_bot(场次, rng, gw, gl) 的产物，摘掉 origin / gl_ts）。
create table if not exists public.gauntlet_bot_pool (
  rules_ver      int         not null,
  battles        int         not null check (battles between 0 and 1000),
  gw             int         not null check (gw between 0 and 9),
  gl             int         not null check (gl between 0 and 9),
  variant        int         not null check (variant between 0 and 99),
  snapshot       jsonb       not null,
  client_version text        not null,              -- 哪个版本的代码生成的（只作记录；挑的时候按 rules_ver）
  created_at     timestamptz not null default now(),
  primary key (rules_ver, battles, gw, gl, variant)
);
alter table public.gauntlet_bot_pool enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行（机器人池本身就是「哪些是机器人」的答案）

-- 快照能不能当左方（A）开打 —— 与裁判 RefereeJob.validate + _state_from_snapshot 同一组条件：
--   三统领（去空去重后恰好 3 只）、分路 top / bottom 都是数组、每只统领在两路里恰好出现一次。
-- ★写成 plpgsql 逐条 if：SQL 的 and 不保证求值顺序，jsonb_array_elements 碰到非数组会直接报错。
create or replace function public.referee_lineup_ok(p_snap jsonb) returns boolean
language plpgsql immutable as $$
declare n int; bad int;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' then
    return false;
  end if;
  if jsonb_typeof(p_snap->'leaders') <> 'array' or jsonb_array_length(p_snap->'leaders') <> 3 then
    return false;
  end if;
  if jsonb_typeof(p_snap->'lane_assign') <> 'object'
     or jsonb_typeof(p_snap->'lane_assign'->'top') is distinct from 'array'
     or jsonb_typeof(p_snap->'lane_assign'->'bottom') is distinct from 'array' then
    return false;
  end if;
  select count(distinct x) into n from jsonb_array_elements_text(p_snap->'leaders') x where x <> '';
  if n <> 3 then
    return false;
  end if;
  select count(*) into bad
    from (select distinct x as l from jsonb_array_elements_text(p_snap->'leaders') x where x <> '') d
   where (select count(*)
            from (select jsonb_array_elements_text(p_snap->'lane_assign'->'top') as y
                  union all
                  select jsonb_array_elements_text(p_snap->'lane_assign'->'bottom')) z
           where z.y = d.l) <> 1;
  return bad = 0;
end $$;
revoke all on function public.referee_lineup_ok(jsonb) from public, anon, authenticated;

-- 快照能不能当右方（B）开打 —— 与裁判 _lanes_ok（= Backend.ghost_lanes_broken 取反）同一组条件：
--   分路 top / bottom 都是数组，且至少一路有统领。
create or replace function public.referee_lanes_ok(p_snap jsonb) returns boolean
language plpgsql immutable as $$
declare n int;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' or jsonb_typeof(p_snap->'lane_assign') <> 'object'
     or jsonb_typeof(p_snap->'lane_assign'->'top') is distinct from 'array'
     or jsonb_typeof(p_snap->'lane_assign'->'bottom') is distinct from 'array' then
    return false;
  end if;
  select count(*) into n
    from (select jsonb_array_elements_text(p_snap->'lane_assign'->'top') as y
          union all
          select jsonb_array_elements_text(p_snap->'lane_assign'->'bottom')) z
   where z.y <> '';
  return n > 0;
end $$;
revoke all on function public.referee_lanes_ok(jsonb) from public, anon, authenticated;

-- 上传机器人池（只有 service_role：轮询器 referee_poller.py --bot-pool）。分批调：第一批 p_replace = true 先清掉这个规则版本的旧池。
-- 每行 {battles, gw, gl, variant, snapshot}；快照必须能开打（referee_lineup_ok），否则计入 rejected、不入池。
create or replace function public.referee_bot_pool_load(p_client_version text, p_rules_ver int, p_rows jsonb,
    p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; bad int := 0; total int;
begin
  if p_rules_ver is null or p_rules_ver < 1 or p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or coalesce(p_client_version, '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_args');
  end if;
  if coalesce(p_replace, false) then
    delete from public.gauntlet_bot_pool where rules_ver = p_rules_ver;
  end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r) <> 'object'
       or jsonb_typeof(r->'battles') <> 'number' or jsonb_typeof(r->'gw') <> 'number'
       or jsonb_typeof(r->'gl') <> 'number' or jsonb_typeof(r->'variant') <> 'number'
       or not public.referee_lineup_ok(r->'snapshot') or octet_length((r->'snapshot')::text) > 65536 then
      bad := bad + 1;
      continue;
    end if;
    insert into public.gauntlet_bot_pool (rules_ver, battles, gw, gl, variant, snapshot, client_version)
      values (p_rules_ver, (r->>'battles')::numeric::int, (r->>'gw')::numeric::int, (r->>'gl')::numeric::int,
              (r->>'variant')::numeric::int, (r->'snapshot') - 'origin' - 'gl_ts', p_client_version)
      on conflict (rules_ver, battles, gw, gl, variant) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, created_at = now();
    n := n + 1;
  end loop;
  update public.referee_versions set rules_ver = p_rules_ver where client_version = p_client_version;
  select count(*) into total from public.gauntlet_bot_pool where rules_ver = p_rules_ver;
  return jsonb_build_object('ok', true, 'loaded', n, 'rejected', bad, 'total', total);
end $$;
revoke all on function public.referee_bot_pool_load(text, int, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.referee_bot_pool_load(text, int, jsonb, boolean) to service_role;

-- ③ 对手卡片 / 挑对手 ─────────────────────────────────────────
-- 回给客户端画 VS 卡的那一份：profile 只留 name / avatar / id / tag，外加三统领。真人与机器人同一形状、同一组键。
create or replace function public.referee_opp_card(p_snap jsonb) returns jsonb
language plpgsql immutable as $$
declare pf jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_snap->'profile') = 'object' then
    select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into pf
      from jsonb_each(p_snap->'profile') e
     where e.key in ('name', 'avatar', 'id', 'tag');
  end if;
  return jsonb_build_object('profile', pf,
    'leaders', case when jsonb_typeof(p_snap->'leaders') = 'array' then p_snap->'leaders' else '[]'::jsonb end);
end $$;
revoke all on function public.referee_opp_card(jsonb) from public, anon, authenticated;

-- 挑一个对手。返回 {snap, opp, pick, account}（opp = 真人账号 uuid / 'bot:<规则>:<场次>:<胜>:<负>:<序号>'；pick = fresh / stale / bot；
--   account = 真人对手的账号，机器人没有这个键 ⇒ 任务行 b_account 真人填、机器人 null；20261020b 的删号 / 改名按它找得到）；
-- 一个都挑不到 ⇒ null。p_battles = 我的本周场次（机器人强度的唯一输入，= 客户端 gauntlet_bot_battles）。
-- ★排除：本周已经碰过的对手（这个人本周所有闯关任务 meta.opp / meta.opp_prev）—— 与客户端「最近 8 个对手」同一用意，
--   周六一个人最多 6 场 ⇒ 排除本周全部。真人排除了就不挑；机器人池排除了只是排后（池子每格 6 份，够一周不重样）。
create or replace function public.referee_gauntlet_pick(p_uid uuid, p_week bigint, p_gw int, p_gl int,
    p_rules_ver int, p_battles int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_ex text[]; g record; bp record; bk int; snap jsonb;
begin
  select coalesce(array_agg(x), '{}') into v_ex
    from (select j.meta->>'opp' as x from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid and j.meta ? 'opp'
          union all
          select jsonb_array_elements_text(j.meta->'opp_prev') from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid
             and jsonb_typeof(j.meta->'opp_prev') = 'array') e
   where x is not null;
  -- ① 同标签真人：30 分钟内的优先（= phase2_config.FRESH_SNAPSHOT_SEC 1800），再随机
  select gg.account_id, gg.snapshot, gg.uploaded_at into g
    from public.gauntlet_ghosts gg
   where gg.season_week = p_week and gg.gw = p_gw and gg.gl = p_gl and gg.rules_ver = p_rules_ver
     and gg.account_id <> p_uid and not (gg.account_id::text = any(v_ex))
     and public.referee_lanes_ok(gg.snapshot)
   order by (gg.uploaded_at > now() - make_interval(secs => 1800)) desc, random()
   limit 1;
  if found then
    return jsonb_build_object('snap', g.snapshot - 'origin', 'opp', g.account_id::text, 'account', g.account_id,
      'pick', case when g.uploaded_at > now() - make_interval(secs => 1800) then 'fresh' else 'stale' end);
  end if;
  -- ② 机器人：池子按场次存到 30（= bot_pool.gd MAX_BATTLES；装备曲线 28 场封顶），超出的用 30 那一格
  bk := least(greatest(coalesce(p_battles, 0), p_gw + p_gl, 0), 30);
  select b.* into bp
    from public.gauntlet_bot_pool b
   where b.rules_ver = p_rules_ver and b.battles = bk and b.gw = p_gw and b.gl = p_gl
   order by (format('bot:%s:%s:%s:%s:%s', b.rules_ver, b.battles, b.gw, b.gl, b.variant) = any(v_ex)), random()
   limit 1;
  if not found then
    return null;
  end if;
  -- 真人口径的上传时刻：现在往前 60~1500 秒（= Backend.make_bot 的 gl_ts，落在 30 分钟新鲜窗里）
  snap := jsonb_set(bp.snapshot - 'origin', '{gl_ts}',
                    to_jsonb(extract(epoch from now())::bigint - (60 + floor(random() * 1441))::bigint));
  if coalesce(p_battles, 0) > bk then
    snap := jsonb_set(snap, '{season_total_battles}', to_jsonb(p_battles));   -- 场次标签与玩家相同（用户 10-04「场次一定要相同」）
  end if;
  return jsonb_build_object('snap', snap,
    'opp', format('bot:%s:%s:%s:%s:%s', bp.rules_ver, bp.battles, bp.gw, bp.gl, bp.variant), 'pick', 'bot');
end $$;
revoke all on function public.referee_gauntlet_pick(uuid, bigint, int, int, int, int) from public, anon, authenticated;

-- ④ 周六开战（客户端）─────────────────────────────────────────
-- 客户端只交：本周 / 我的阵容 / 我要打第几场（0 起 = gw + gl）/ 版本 / 规则版本。对手与种子都在这里定，客户端改不了。
-- 回包：{ok, job_id, match_id, opp: {profile, leaders}, gw, gl}（gw / gl = 账本上这一场之前的数）。
--   reason：not_signed_in / off / update_required / wrong_week / closed / bad_snapshot / finished / stale / no_opponent。
-- ★同一个人同一时刻只有一场在算（在算的那场直接把号和对手还给他）。
-- ★只有「上一次算失败了」才允许同一场重交：种子不换；对手不换（除非失败原因是对手快照坏了 b_bad_snapshot ⇒ 重挑，旧的进 opp_prev 排除）；
--   阵容不换（除非失败原因是我的阵容坏了 a_bad_snapshot）—— 否则「看到对手 → 故意交坏 → 改阵容针对」就成了。
create or replace function public.referee_gauntlet_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text, p_rules_ver int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text; v_rv int;
        v_b int; pk jsonb; jid bigint; mid uuid; st text; v_snap_b jsonb; v_meta jsonb; v_found boolean;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = p_client_version and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is distinct from v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (now() >= to_timestamp(p_week + 5 * 86400) and now() < to_timestamp(p_week + 6 * 86400)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or octet_length(p_snapshot::text) > 65536 or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'gw', v_gw, 'gl', v_gl);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'gw', v_gw, 'gl', v_gl);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta->'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta->>'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_gauntlet_pick(uid, p_week, v_gw, v_gl, v_rv,
              coalesce((v_meta->>'battles')::int, v_gw + v_gl));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'gw', v_gw, 'gl', v_gl);
      end if;
      v_snap_b := pk->'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk->>'opp', 'pick', pk->>'pick');
      update public.referee_jobs set b_account = (pk->>'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = p_client_version,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then p_snapshot else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(p_snapshot) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'gw', v_gw, 'gl', v_gl);
  end if;
  -- 机器人强度 = 我的本周场次（客户端 gauntlet_bot_battles = max(本大轮场次, gw + gl)）。
  --   快照自报的 season_total_battles 只能往上抬（报高了 = 自己打更强的机器人）；地板 = 服务端看得到的积分赛场次 + 周六已打场次。
  v_b := greatest(
    case when jsonb_typeof(p_snapshot->'season_total_battles') = 'number'
         then least((p_snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = uid and season_week = p_week), 0) + v_gw + v_gl,
    v_gw + v_gl);
  pk := public.referee_gauntlet_pick(uid, p_week, v_gw, v_gl, v_rv, v_b);
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'gw', v_gw, 'gl', v_gl);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, (pk->>'account')::uuid,
      p_snapshot, pk->'snap', public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', v_rv, 'battles', v_b, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'gw', v_gw, 'gl', v_gl);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk->'snap'), 'gw', v_gw, 'gl', v_gl);
end $$;
revoke all on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_gauntlet_start(bigint, jsonb, int, text, int) to authenticated;

-- ⑤ 重定义的现行函数 ───────────────────────────────────────

-- 旧接口：客户端交对手快照。★2026-10-20：gauntlet_server_pick 打开后一律拒（旧包看到「请更新」）；没打开时下面逐字照旧。
create or replace function public.referee_submit_gauntlet(p_week bigint, p_snapshot jsonb, p_opponent jsonb,
    p_client_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg record; v_gw int := 0; v_gl int := 0; ex record; v_key text;
        jid bigint; mid uuid; st text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  select * into cfg from public.referee_config where id = 1;
  -- ★2026-10-20 周六对手改服务器挑: 开关开着时不再收客户端挑的对手(新客户端走 referee_gauntlet_start)
  if coalesce(cfg.gauntlet_server_pick, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if not exists (select 1 from public.referee_versions where client_version = p_client_version and enabled) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (now() >= to_timestamp(p_week + 5 * 86400) and now() < to_timestamp(p_week + 6 * 86400)) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or jsonb_typeof(p_snapshot->'leaders') <> 'array' or jsonb_array_length(p_snapshot->'leaders') <> 3
     or jsonb_typeof(p_snapshot->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  if p_opponent is null or jsonb_typeof(p_opponent) <> 'object' or octet_length(p_opponent::text) > 65536
     or jsonb_typeof(p_opponent->'lane_assign') <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_opponent');
  end if;
  select gw, gl into v_gw, v_gl from public.gauntlet_records where season_week = p_week and account_id = uid;
  v_gw := coalesce(v_gw, 0);
  v_gl := coalesce(v_gl, 0);
  -- = phase2_config GAUNTLET_WINS_IN 4 / GAUNTLET_LOSSES_OUT 3 / GAUNTLET_QUOTA 6
  if v_gw >= 4 or v_gl >= 3 or v_gw + v_gl >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'finished', 'gw', v_gw, 'gl', v_gl);
  end if;
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true);
  end if;
  v_key := format('gauntlet:%s:%s:%s', p_week, uid, v_gw + v_gl);
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', v_key, p_week, p_client_version, public.referee_new_seed(), uid, null,
      p_snapshot, p_opponent, public.referee_level_of(p_snapshot),
      jsonb_build_object('account', uid, 'gw0', v_gw, 'gl0', v_gl))
    on conflict (match_key) do update
      set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null,
          a_snapshot = excluded.a_snapshot, b_snapshot = excluded.b_snapshot,
          client_version = excluded.client_version, level = excluded.level, created_at = now()
      where public.referee_jobs.status = 'failed'
    returning job_id, match_id into jid, mid;
  if jid is null then
    select job_id, match_id, status into jid, mid, st from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid);
end $$;
revoke all on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) from public, anon;
grant execute on function public.referee_submit_gauntlet(bigint, jsonb, jsonb, text) to authenticated;

-- 查自己那一场算完没有（只认 a_account = 自己；不回快照）。★2026-10-20 多回 coins（这一局我方的战斗内铸币；旧任务没有 ⇒ null ⇒ 客户端当 0）。
create or replace function public.referee_job_status(p_job_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select * into j from public.referee_jobs where job_id = p_job_id and a_account = auth.uid();
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  return jsonb_build_object('ok', true, 'status', j.status, 'match_id', j.match_id,
    'won', j.result->'ledger'->'won', 'score', j.result->'ledger'->'score',
    'gw', j.result->'ledger'->'gw', 'gl', j.result->'ledger'->'gl',
    'coins', j.result->'ledger'->'coins',
    'error', case when j.status = 'failed' then j.error end);
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- 写回。★2026-10-20 两处：① 结果单的 coins（A 的战斗内铸币，裁判 EquipTickSystem.match_minted）夹到 0..999 记进账本 ledger.coins
--   （只进任务行，不进 matches.result —— 那一行所有登录用户都读得到）；② 挂进 gauntlet_ghosts 时写 rules_ver
--   （原来漏写 = 默认 0 ⇒ 新客户端按 rules_ver 拉对手 / 服务端按 rules_ver 挑对手都永远碰不到这一份）。
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int;
begin
  select * into j from public.referee_jobs where job_id = p_job_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  if j.status = 'done' then
    return jsonb_build_object('ok', true, 'reason', 'already_done');
  end if;
  if j.status <> 'claimed' or j.claimed_by is distinct from p_worker then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or coalesce(p_result->>'ok', 'false') <> 'true'
     or p_result->>'match_id' is distinct from j.match_id::text
     or jsonb_typeof(p_result->'seed') <> 'number' or (p_result->>'seed')::numeric <> j.seed
     or p_result->>'client_version' is distinct from j.client_version
     or coalesce(p_result->>'winner', '') not in ('a', 'b')
     or jsonb_typeof(p_result->'steps') <> 'number' or (p_result->>'steps')::numeric <= 0
     or jsonb_typeof(p_result->'replay_b64') <> 'string'
     or octet_length(p_result->>'replay_b64') not between 1 and 65536      -- = matches_replay_size = 客户端 REPLAY_MAX_B64
     or (p_result->>'replay_b64') !~ '^[A-Za-z0-9+/]+={0,2}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_result');
  end if;
  won := p_result->>'winner' = 'a';
  sc := case when jsonb_typeof(p_result->'score_code') = 'number' then (p_result->>'score_code')::numeric::int else -1 end;
  -- ★2026-10-20 战斗内铸币（缺 / 不是数 / 越界 ⇒ 0；不是整数 ⇒ 向下取整）
  if jsonb_typeof(p_result->'coins') = 'number' and (p_result->>'coins')::numeric between 0 and 999 then
    v_coins := floor((p_result->>'coins')::numeric)::int;
  end if;
  res := jsonb_build_object('won', won, 'steps', (p_result->>'steps')::numeric::int, 'surrendered', false,
                            'referee', true, 'score', sc);
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.a_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.a_account, case when won then 1 else 0 end, case when won then 0 else 1 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw, v_gl;
    res := res || jsonb_build_object('gw', v_gw, 'gl', v_gl);
    -- ★2026-10-20 规则版本：任务里记的那个（服务端挑对手时定的）> 裁判版本登记的 > 0（老任务、老口径）
    v_rv := coalesce(case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    -- 以打完这一场的新战绩标签挂进快照池（同 E-A4：下一场要找的是「跟我现在同样几胜几负」的人）
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.a_account, j.season_week, v_gw, v_gl, j.a_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins))
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- 监控。★2026-10-20 多回：周六开关 / 服务端挑对手开关 / 每个启用版本的机器人池行数（--health：周六开着而某个启用版本池子是空的 ⇒ 报警）。
create or replace function public.referee_backlog()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pending', (select count(*) from public.referee_jobs where status = 'pending'),
    'claimed', (select count(*) from public.referee_jobs where status = 'claimed'),
    'failed_24h', (select count(*) from public.referee_jobs where status = 'failed' and done_at > now() - interval '24 hours'),
    'oldest_pending_sec', (select coalesce(extract(epoch from now() - min(created_at))::int, 0)
                             from public.referee_jobs where status = 'pending'),
    'workers', (select coalesce(jsonb_agg(jsonb_build_object('worker', worker, 'versions', versions,
                  'seen_sec', extract(epoch from now() - seen_at)::int)), '[]'::jsonb) from public.referee_workers),
    'gauntlet_on', public.referee_gauntlet_on(),
    'server_pick', coalesce((select gauntlet_server_pick from public.referee_config where id = 1), false),
    'bot_pool', (select coalesce(jsonb_agg(jsonb_build_object('client_version', v.client_version, 'rules_ver', v.rules_ver,
                  'rows', (select count(*) from public.gauntlet_bot_pool b where b.rules_ver = v.rules_ver))
                  order by v.client_version), '[]'::jsonb)
                   from public.referee_versions v where v.enabled))
$$;
revoke all on function public.referee_backlog() from public, anon, authenticated;
grant execute on function public.referee_backlog() to service_role;

-- 上线步骤（内测服先走一遍，每步回读；正式服同样顺序。★全程不需要停服）：
--   1. 执行本文件。回读：select gauntlet_server_pick from referee_config;  -- false
--      select public.referee_lineup_ok('{"leaders":["a","b","c"],"lane_assign":{"top":["a","b"],"bottom":["c"]}}');  -- true
--      select public.referee_lineup_ok('{"leaders":["a","b","c"],"lane_assign":{"top":["a","b"],"bottom":["a"]}}');  -- false
--   2. 裁判机：每个装了的版本 `referee_poller.py --bot-pool`（生成 + 上传），回读 select public.referee_backlog()->'bot_pool';
--      每个启用版本 rows = 2052（31 个场次 × 可开打标签 × 6 份）、rules_ver 非 null。
--   3. 裁判机装新客户端版本（含 referee_gauntlet_start 的那一版）+ insert into referee_versions + 第 2 步给它传池子。
--   4. 新客户端上架、`min_client_version` 抬到它（版本闸让旧包整屏「请更新」）之后：
--      update referee_config set gauntlet_server_pick = true, updated_at = now() where id = 1;
--      回读：旧接口 referee_submit_gauntlet 回 {"ok":false,"reason":"update_required"}。
--   兼容：第 4 步之前旧包照旧走 referee_submit_gauntlet（客户端挑对手，原有缺口仍在）；新包任何时候都走新接口。
--         新包碰到没执行本文件的服务端 ⇒ referee_gauntlet_start 404 ⇒ 屏上「连接服务器后才能比赛」，不出本地成绩
--         （所以本文件必须先于新客户端上线）。
--   回滚：update referee_config set gauntlet_server_pick = false（旧接口恢复）；其余对象留着不影响旧包。
-- <<< END gauntlet_server_pick_and_coins 20261020c <<<

-- >>> BEGIN finals_coins 20261020d >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛（小组赛 + 冠军杯赛）服务器算的局照常发战斗内铸币（2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md
--   R8「周日服务器局不发局内金币」那一条）—— ★只写文件、未上生产。
--   前提：20261019_referee_jobs.sql / 20261020c_gauntlet_server_pick_and_coins.sql 已执行（本段重定义的 referee_complete 以 20261020c 版为底）。
--
-- 缺口：本机打（老路）时 `_settle_season` 把奇械羁绊铸币 + 035 黄铜齿轮加进奖励；服务器算的周日局一枚都没发：
--   ① 结果单只带左方（A = 上侧 side 0）的 `coins`，右方（B）没人算；
--   ② 周日客户端不查任务（没有 referee_job_status 那一步，结果等对阵图揭晓），连 A 的那一份也没有人去取。
-- 改法：
--   Ⅰ 裁判结果单多一个 `coins_b`（右方 B 的铸币，`EquipTickSystem.match_minted(battle, "right")`，与 `coins` 同一个出口同一刻读）；
--     referee_complete 把它夹到 0..999 记进账本 `ledger.coins_b`（只有周日任务记；周六的对手可能是机器人，不记）。
--     老裁判程序（v0.21.2 及以前）的结果单没有 coins_b ⇒ 0。
--   Ⅱ 新只读接口 referee_finals_coins(p_week, p_bucket, p_round, p_match)：查「我在这一场的战斗内铸币」。
--     · 我是哪一侧由服务端按 auth.uid() 对任务行的 a_account / b_account 认（客户端不报侧、不报数）；
--     · 不剧透：结果没翻面（与 finals_view 同一条 `b.closed or round < b.round`）⇒ status = pending、不回数；
--     · 翻面了但这一场没有裁判局（轮空 / 3 倍时长兜底判的 / 裁判结果被兜底抢先 superseded / 任务失败）⇒ done、coins = 0；
--     · 我不在这一场 ⇒ not_in_match。
--   客户端：点开自己那一场时（`RefereeWatch.finals_seal`）记一张「待取铸币」单（存档），翻面后查一次、按回包发（出局那一局不发，
--     与 `_settle_season` 同一条），发完销单 —— 同一场只发一次。
-- 本段内容：① 重定义 referee_complete（多记 coins_b；其余逐字照抄 20261020c 版，只在标了「2026-10-20d」的地方改）
--           ② referee_finals_coins（authenticated）
-- ★重复执行安全（create or replace）。不改任何表、不改任何开关 ⇒ 执行本段不改变现行客户端的行为。
-- ─────────────────────────────────────────────────────────────

-- ① 写回：多记右方铸币
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
begin
  select * into j from public.referee_jobs where job_id = p_job_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_job');
  end if;
  if j.status = 'done' then
    return jsonb_build_object('ok', true, 'reason', 'already_done');
  end if;
  if j.status <> 'claimed' or j.claimed_by is distinct from p_worker then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or coalesce(p_result->>'ok', 'false') <> 'true'
     or p_result->>'match_id' is distinct from j.match_id::text
     or jsonb_typeof(p_result->'seed') <> 'number' or (p_result->>'seed')::numeric <> j.seed
     or p_result->>'client_version' is distinct from j.client_version
     or coalesce(p_result->>'winner', '') not in ('a', 'b')
     or jsonb_typeof(p_result->'steps') <> 'number' or (p_result->>'steps')::numeric <= 0
     or jsonb_typeof(p_result->'replay_b64') <> 'string'
     or octet_length(p_result->>'replay_b64') not between 1 and 65536      -- = matches_replay_size = 客户端 REPLAY_MAX_B64
     or (p_result->>'replay_b64') !~ '^[A-Za-z0-9+/]+={0,2}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_result');
  end if;
  won := p_result->>'winner' = 'a';
  sc := case when jsonb_typeof(p_result->'score_code') = 'number' then (p_result->>'score_code')::numeric::int else -1 end;
  -- ★2026-10-20 战斗内铸币（缺 / 不是数 / 越界 ⇒ 0；不是整数 ⇒ 向下取整）
  if jsonb_typeof(p_result->'coins') = 'number' and (p_result->>'coins')::numeric between 0 and 999 then
    v_coins := floor((p_result->>'coins')::numeric)::int;
  end if;
  -- ★2026-10-20d 右方（B）的战斗内铸币：周日决赛两边都是真人，各按自己那一侧发（同一道夹：缺 / 不是数 / 越界 ⇒ 0）
  if jsonb_typeof(p_result->'coins_b') = 'number' and (p_result->>'coins_b')::numeric between 0 and 999 then
    v_coins_b := floor((p_result->>'coins_b')::numeric)::int;
  end if;
  res := jsonb_build_object('won', won, 'steps', (p_result->>'steps')::numeric::int, 'surrendered', false,
                            'referee', true, 'score', sc);
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.a_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.a_account, case when won then 1 else 0 end, case when won then 0 else 1 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw, v_gl;
    res := res || jsonb_build_object('gw', v_gw, 'gl', v_gl);
    -- ★2026-10-20 规则版本：任务里记的那个（服务端挑对手时定的）> 裁判版本登记的 > 0（老任务、老口径）
    v_rv := coalesce(case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    -- 以打完这一场的新战绩标签挂进快照池（同 E-A4：下一场要找的是「跟我现在同样几胜几负」的人）
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.a_account, j.season_week, v_gw, v_gl, j.a_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  -- ★2026-10-20d 周日任务的账本多一个 coins_b（右方 B 的战斗内铸币；周六不记）
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins)
                  || case when j.kind = 'finals' then jsonb_build_object('coins_b', v_coins_b) else '{}'::jsonb end)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;


-- ② 周日：查我在这一场的战斗内铸币（只读；翻面之前不回数）
create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0;
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
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c);
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;

-- 上线步骤（内测服先走一遍，每步回读；正式服同样顺序。★全程不需要停服）：
--   1. 执行本文件（检查脚本 server/supabase/tests/20261020d_finals_coins_check.sql 先在回滚事务里跑过）。
--      回读：select has_function_privilege('authenticated', 'public.referee_finals_coins(bigint, int, int, int)', 'execute');  -- true
--   2. 裁判机装带 coins_b 的新客户端版本（RefereeRunner 写 coins_b），登记 referee_versions，finals_version 抬到它。
--      在那之前周日任务的 coins_b 一律 0（A 的 coins 老裁判程序本来就写了）。
--   3. 新客户端上架。旧包（0.21.2）不调本接口 ⇒ 周日照旧不发战斗内铸币（不出错）。
--   兼容：新包碰到没执行本文件的服务端 ⇒ referee_finals_coins 404 ⇒ 待取单留着、不发（下次再问），不出本地数。
--   回滚：drop function public.referee_finals_coins(bigint, int, int, int); referee_complete 换回 20261020c 版（多记的 coins_b 留在账本里无害）。
-- <<< END finals_coins 20261020d <<<
