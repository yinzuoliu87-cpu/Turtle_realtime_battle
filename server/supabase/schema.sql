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
-- 2026-10-04 已上生产：cron jobid 11 'purge_old_matches' '0 0 * * 2'（2026-10-21 起真语句在文件末尾 beta_server_clock 20261021 段）

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
--   ★2026-10-21 更正：这段注释曾过期（finals_seat 写着 8-23，实际 20261012b 已改 18-23、jobid 也变了）。
--     现在 cron 全部是真语句、不再靠注释：finals_seat 见 finals_seat_1800 20261012 段；
--     finals_advance（'* * * * 0'）与 purge_old_matches（'0 0 * * 2'）见文件末尾 beta_server_clock 20261021 段。
--   周号写法: (extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint) —— 与客户端 week_anchor_ts 一致(已核)。
--   ★客户端 phase2_config.FINALS_SEAT_HOUR_UTC 必须等于 finals_seat 任务的首个小时(18)。
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

-- >>> BEGIN beta_server_clock 20261021 >>>
-- ─────────────────────────────────────────────────────────────
-- 内测服的服务端时钟缝 + 迁移账本 + 两条只在注释里的 cron 补成真语句
--   （2026-10-21 · 方案书 docs/plans/20261020-内测服.md §2 / §5）
--   ★正式服【还没执行】。上正式服只走 tools/sb_migrate.py 全流程（sandbox → beta → prod 演练 → prod 上线），
--     内测服 turtle-beta 已按本段建过（见方案书实施回填）。
--
-- 为什么：周六闯关「只有周六能交」、周日分组 / 冠军杯赛 / 推进、购物窗 —— 全是服务端直接比 now()。
--   客户端时间穿越骗不过它们；假周号只骗得过 finals_seat 一个函数（方案书调查 C、出入 2）。
--   ⇒ 服务端也要一条时钟缝：app_now() = now() + 偏移（只有内测服能设偏移）。
--
-- ① service_env：这台是哪台（单行，默认 'prod'）。只有 beta_setup.sql（tools/beta_ops.py / sb_migrate.py，
--    写死只认内测服 ref）会把它改成 'beta'。
-- ② server_clock：偏移秒数（单行）。★表上带 `server_clock_prod_zero check (offset_sec = 0)` ——
--    正式服即使误执行「设偏移」也写不进去；内测服的 beta_setup.sql 把这条约束删掉。
-- ③ app_now()：service_env = 'beta' 才加偏移，否则恒等于 now()（双保险：约束 + 判台）。
--    ★同一事务里 now() 是事务开始时刻 ⇒ 正式服上 app_now() 与 now() 逐值相等（检查脚本 P1 断言）。
-- ④ now() 只换「赛程闸」那一类（现在是不是周六 / 本周是哪周 / 购物窗开没开 / 这一轮该不该推进 /
--    轮次开始时刻 round_at / 回给客户端倒计时用的 'now'）；「这一行什么时候写的」（created_at / updated_at /
--    租约 / 清理年龄 / 限流窗口）保持 now()。逐条分类清单见方案书实施回填「now() 分类」。
-- ⑤ service_status.clock_offset_sec：客户端读服务状态时顺手拿到偏移（内测服包把它叠到 now_utc() 上，
--    正式包不读）。由 server_clock 上的触发器镜像过去 ⇒ 只有一份事实源。
-- ⑥ schema_migrations：迁移账本（name / sha256 / 何时 / 谁）。tools/sb_migrate.py 写；
--    「正式服只收内测服上过、同一 sha256 的迁移」靠它。
-- ⑦ beta_tick()：内测服每分钟一次（pg_cron 只在内测服装，见 beta_setup.sql），按 app_now() 判该不该调
--    finals_seat / finals_cup_seat / finals_advance，周号也按 app_now() 算。正式服上调它直接返回 skipped。
-- ⑧ 两条线上一直在跑、仓库里只有注释的 cron（finals_advance / purge_old_matches）写成真语句，
--    命令文本逐字照抄正式服 cron.job（2026-10-21 只读回读）。
-- ★重复执行安全（if not exists / create or replace / on conflict do nothing / 先 unschedule 再 schedule）。
-- ─────────────────────────────────────────────────────────────

-- ① 这台是哪台
create table if not exists public.service_env (
  id   int  primary key default 1,
  env  text not null default 'prod',
  constraint service_env_single_row check (id = 1),
  constraint service_env_known check (env in ('prod', 'beta'))
);
insert into public.service_env (id, env) values (1, 'prod') on conflict (id) do nothing;
alter table public.service_env enable row level security;
revoke all on table public.service_env from anon, authenticated;

-- ② 偏移（正式服约束恒 0）
create table if not exists public.server_clock (
  id         int         primary key default 1,
  offset_sec bigint      not null default 0,
  updated_at timestamptz not null default now(),
  constraint server_clock_single_row check (id = 1),
  constraint server_clock_prod_zero check (offset_sec = 0)
);
insert into public.server_clock (id) values (1) on conflict (id) do nothing;
alter table public.server_clock enable row level security;
revoke all on table public.server_clock from anon, authenticated;

-- ③ 时钟缝
create or replace function public.app_now()
returns timestamptz language sql stable security definer set search_path = public as $$
  select case
    when coalesce((select e.env from public.service_env e where e.id = 1), 'prod') = 'beta'
      then now() + make_interval(secs => coalesce((select c.offset_sec from public.server_clock c where c.id = 1), 0))
    else now()
  end
$$;
revoke all on function public.app_now() from public, anon;
grant execute on function public.app_now() to authenticated, service_role;

-- ⑤ 客户端读得到的偏移（镜像，不是第二份事实源）
alter table public.service_status add column if not exists clock_offset_sec bigint not null default 0;
create or replace function public.server_clock_mirror() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.service_status set clock_offset_sec = new.offset_sec where id = 1;
  return new;
end $$;
revoke all on function public.server_clock_mirror() from public, anon, authenticated;
drop trigger if exists server_clock_mirror on public.server_clock;
create trigger server_clock_mirror after insert or update on public.server_clock
  for each row execute function public.server_clock_mirror();

-- ⑥ 迁移账本
create table if not exists public.schema_migrations (
  name       text        primary key,
  sha256     text        not null,
  applied_at timestamptz not null default now(),
  applied_by text        not null default '',
  note       text        not null default ''
);
alter table public.schema_migrations enable row level security;
revoke all on table public.schema_migrations from anon, authenticated;

-- ⑦ 内测服赛程推进器
create table if not exists public.beta_tick_state (
  id          int         primary key default 1,
  last_fake   timestamptz,
  last_real   timestamptz,
  last_result jsonb,
  constraint beta_tick_state_single_row check (id = 1)
);
alter table public.beta_tick_state enable row level security;
revoke all on table public.beta_tick_state from anon, authenticated;

-- 与正式服 cron 的对应（正式服：finals_seat '*/10 18-23 * * 0' / finals_cup_seat '*/5 20-23 * * 0' /
--   finals_advance '* * * * 0'）。三个函数都幂等（已坐定 / 已成表就返回 0），所以每分钟叫一次与
--   每 10 / 5 分钟叫一次结果相同；差别只在冠军杯赛「等组打完」那段可能早几分钟成表（内测服可接受）。
create or replace function public.beta_tick()
returns jsonb language plpgsql security definer set search_path = public as $$
declare t timestamptz; u timestamp; wk bigint; dow int; hr int; n int; res jsonb := '{}'::jsonb;
begin
  if coalesce((select e.env from public.service_env e where e.id = 1), 'prod') <> 'beta' then
    return jsonb_build_object('skipped', 'not_beta');
  end if;
  t := public.app_now();
  u := t at time zone 'UTC';
  wk := extract(epoch from date_trunc('week', u))::bigint;   -- = 客户端 week_anchor_utc（周一 00:00 UTC）
  dow := extract(isodow from u)::int;
  hr := extract(hour from u)::int;
  if dow = 7 and hr >= 18 then
    n := public.finals_seat(wk);
    res := res || jsonb_build_object('finals_seat', n);
  end if;
  if dow = 7 and hr >= public.finals_cup_hour() then
    n := public.finals_cup_seat(wk);
    res := res || jsonb_build_object('finals_cup_seat', n);
  end if;
  if dow = 7 then
    n := public.finals_advance(wk);
    res := res || jsonb_build_object('finals_advance', n);
  end if;
  res := res || jsonb_build_object('fake', t, 'week', wk, 'isodow', dow, 'hour', hr);
  insert into public.beta_tick_state (id, last_fake, last_real, last_result) values (1, t, now(), res)
    on conflict (id) do update set last_fake = excluded.last_fake, last_real = excluded.last_real,
                                   last_result = excluded.last_result;
  return res;
end $$;
revoke all on function public.beta_tick() from public, anon, authenticated;

-- ⑧ 线上一直在跑、仓库里原来只有注释的两条 cron（命令文本逐字照抄正式服 cron.job，2026-10-21 只读回读）
select cron.unschedule(jobid) from cron.job where jobname = 'finals_advance';
select cron.schedule('finals_advance', '* * * * 0', 'select public.finals_advance(
      (extract(epoch from date_trunc(''week'', now() at time zone ''UTC''))::bigint))');
select cron.unschedule(jobid) from cron.job where jobname = 'purge_old_matches';
select cron.schedule('purge_old_matches', '0 0 * * 2', 'select public.purge_old_matches()');

-- ④ 赛程闸改调 app_now()（12 个函数）。正文逐字照抄 schema.sql 现行版，只改 now() → public.app_now() 的那几行。

-- finals_seat（照抄 schema.sql 第 1456~1490 行现行版; 只改标了 app_now 的行）
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
    select p_week, bucket_no, count(*)::int, 1, public.app_now(), count(*) = 1,
           case when count(*) = 1 then public.app_now() else null end
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;

-- finals_cup_seat（照抄 schema.sql 第 1573~1614 行现行版; 只改标了 app_now 的行）
create or replace function public.finals_cup_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare cup int := public.finals_cup_no(); start_at timestamptz; ngroups int; nopen int;
        r record; i int := 0;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    return 0;
  end if;
  start_at := to_timestamp(p_week + 6 * 86400 + public.finals_cup_hour() * 3600);
  if public.app_now() < start_at then
    return 0;
  end if;
  select count(*), count(*) filter (where not closed) into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and public.app_now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
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
    values (p_week, cup, i, 1, public.app_now(), i <= 1, case when i <= 1 then public.app_now() else null end);
  return i;
end $$;

-- finals_view（照抄 schema.sql 第 2021~2091 行现行版; 只改标了 app_now 的行）
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
    'now', extract(epoch from public.app_now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res, 'scores', sc);
end $function$;

-- finals_week_view（照抄 schema.sql 第 2093~2149 行现行版; 只改标了 app_now 的行）
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
    'now', extract(epoch from public.app_now())::bigint, 'buckets', bs, 'cup', cp);
end $function$;

-- finals_update_snapshot（照抄 schema.sql 第 2261~2282 行现行版; 只改标了 app_now 的行）
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
  if public.app_now() >= b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return false;                       -- 购物结束 = 本轮阵容锁定
  end if;
  update public.finals_entrants set snapshot = p_snapshot
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- finals_opponent（照抄 schema.sql 第 2288~2340 行现行版; 只改标了 app_now 的行）
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
  if public.app_now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
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

-- referee_enqueue_finals（照抄 schema.sql 第 2813~2865 行现行版; 只改标了 app_now 的行）
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
    if public.app_now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
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

-- finals_advance（照抄 schema.sql 第 3125~3218 行现行版; 只改标了 app_now 的行）
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
    if public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec()) then
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
      if public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 2) then
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
       and public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 3) then
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
      update public.finals_buckets set closed = true, revealed_at = public.app_now()
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = public.app_now(), revealed_at = public.app_now()
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;

-- finals_report（照抄 schema.sql 第 3223~3282 行现行版; 只改标了 app_now 的行）
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
  if public.app_now() < open_at then
    return jsonb_build_object('ok', false, 'reason', 'shop_open');
  end if;
  if p_reporter_side = 1 and public.app_now() < open_at + make_interval(secs => public.finals_lower_grace_sec()) then
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

-- referee_live_gauntlet（照抄 schema.sql 第 3409~3437 行现行版; 只改标了 app_now 的行）
create or replace function public.referee_live_gauntlet()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg record; wk bigint; v jsonb;
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;
  select * into cfg from public.referee_config where id = 1;
  wk := extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint;
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

-- referee_gauntlet_start（照抄 schema.sql 第 4202~4313 行现行版; 只改标了 app_now 的行）
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
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400)) then
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

-- referee_submit_gauntlet（照抄 schema.sql 第 4320~4386 行现行版; 只改标了 app_now 的行）
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
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 = 周锚点 + 5 天（UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400)) then
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

-- 上线步骤（★正式服还没执行；只走 tools/sb_migrate.py，每步不过就停）：
--   1. python tools/sb_migrate.py sandbox 20261021_beta_server_clock          ⇒ ALL PASS
--   2. python tools/sb_migrate.py beta --rehearse / --apply                   ⇒ 内测服已上（2026-10-21）
--   3. python tools/sb_migrate.py prod --rehearse                              ⇒ 生产回滚事务里「本段 + 检查脚本」ALL PASS
--   4. python tools/sb_migrate.py prod --apply（要用户点头）                   ⇒ 回读 12 个函数体与仓库逐字相同
--   正式服回读：select public.app_now() = now();  -- true（同一事务）
--             update public.server_clock set offset_sec = 60;  -- 被 server_clock_prod_zero 拒
--   回滚：12 个函数换回 git tag v0.21.4 的 schema.sql 版本；新表 / app_now / beta_tick 留着无害（正式服 beta_tick 恒 skipped）。
-- <<< END beta_server_clock 20261021 <<<
-- beta_server_clock 20261021 已上生产 2026-10-24（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同、正式服账本 schema_migrations 有这一行）

-- >>> BEGIN referee_lease_660 20261022 >>>
-- ─────────────────────────────────────────────────────────────
-- 裁判任务租期 180 → 660 秒（2026-10-22 · docs/plans/ref/内测服整周彩排台账.md 六 ③ 的连带发现）
--   租期 = 任务被领走后多久没写回就收回重领（次数用尽判 lease_expired 失败）。
--   原值 180 是按「一局 ≤ 15 秒」定的；而裁判机单局上限 JOB_TIMEOUT_SEC = 600
--   （10-19 CX33 实测满装备三路打满约 150 秒）⇒ 算超过 180 秒的重局会被别的线程重领重算，次数用尽判失败。
--   660 = 单局上限 600 + Godot 启动 / 回传余量。
--   ★正式服 / 内测服的配置行 10-22 已按用户批准（「你不能现在做吗」）直接改成 660；
--     本段幂等（再跑一遍不改任何东西），负责 ① 新建库的列默认值 ② 两边迁移账本记账。
-- ★重复执行安全。不动函数、不动开关。
-- ─────────────────────────────────────────────────────────────
alter table public.referee_config alter column lease_sec set default 660;
update public.referee_config set lease_sec = 660, updated_at = now() where id = 1 and lease_sec = 180;
-- <<< END referee_lease_660 20261022 <<<
-- referee_lease_660 20261022 已上生产 2026-10-24（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同、正式服账本 schema_migrations 有这一行）
-- >>> BEGIN referee_chest 20261022b >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判局的宝箱龟进度回写存档（2026-10-22 · 方案书 docs/plans/20261022-宝箱龟整条链路修复.md 的 A）
--   现状：周六闯关 / 周日决赛由裁判机算，裁判机上宝箱龟照样攒财宝值、开箱，但结果单不带宝箱、
--     客户端记账也不碰 ⇒ 这些局的宝箱进度永远进不了存档，下一场又从旧值起算（用户「宝箱整个是不是有bug啊」）。
--   做法：照战斗内铸币 coins / coins_b 的通路（20261020c / 20261020d）：
--     裁判结果单多带 `chest`（左方 A 本局结束时 {value, won}）与 `chest_b`（右方 B，周日）。
--     referee_complete 存的是整份结果单（去掉录像）⇒ **不用改**，两个字段自然在 referee_jobs.result 顶层。
--     本段只重定义两个读取接口，把它回给客户端：
--       ① referee_job_status（以 20261020c 版为底）：多回 `chest`（只给 A 自己）
--       ② referee_finals_coins（以 20261020d 版为底）：多回 `chest`（A 取 chest、B 取 chest_b；翻面之前照旧不回）
--   ★只在结果单里真有宝箱（是 JSON 对象）时才多一个键 ⇒ 老裁判程序 / 老客户端 / 20261020c、d 的检查脚本都不受影响。
--   ★不在这里校验 value / won 的形状：结果单只能由裁判机（service_role）写；客户端记账时再夹一遍。
-- 上线步骤（tools/sb_migrate.py 标准路径；内测服先走一遍）：
--   sandbox → beta --rehearse → beta --apply → 内测服冒烟 → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
--   之后：裁判机装带 `chest` 的新客户端版本（RefereeRunner 写 chest / chest_b）、登记 referee_versions。
--   在那之前结果单没有 chest ⇒ 两个接口与本段之前逐字相同的回包。
-- 回滚：把两个函数换回 20261020c / 20261020d 版（结果单里多存的 chest 无害）。
-- ─────────────────────────────────────────────────────────────

-- ① 周六：查自己那一场算完没有（只认 a_account = 自己；不回快照）
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
    'error', case when j.status = 'failed' then j.error end)
    -- 2026-10-22b：这一局结束时我方宝箱龟的进度（财宝值 + 已开战利品）
    || case when j.status = 'done' and jsonb_typeof(j.result->'chest') = 'object'
            then jsonb_build_object('chest', j.result->'chest') else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ② 周日：查我在这一场的战斗内铸币 + 宝箱进度（只读；翻面之前不回数）
create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null;
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
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;
-- <<< END referee_chest 20261022b <<<
-- referee_chest 20261022b 已上生产 2026-10-24（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同、正式服账本 schema_migrations 有这一行）

-- >>> BEGIN referee_incense 20261023 >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器裁判局的 093 香火石刻痕 / 充能回写存档（2026-10-23 · 方案书 docs/plans/20261023-香火石四个问题.md 的 3）
--   现状：裁判机上我方的刻痕 / 充能写死 0（周末服务器局里刻痕不生效），结果单也不带香火
--     ⇒ 这些局里攒的充能 / 刻痕永远进不了存档（用户「香火石有bug啊」→「这是个问题」）。
--   做法：照宝箱龟 chest / chest_b 的通路（20261022b）：
--     裁判结果单多带 `incense`（左方 A 本局结束时 {marks, charge}）与 `incense_b`（右方 B，周日）。
--     referee_complete 存的是整份结果单（去掉录像）⇒ **不用改**，两个字段自然在 referee_jobs.result 顶层。
--     本段只重定义两个读取接口（以 20261022b 版为底，宝箱那一段逐字保留），多回一个 `incense`：
--       ① referee_job_status：多回 `incense`（只给 A 自己）
--       ② referee_finals_coins：多回 `incense`（A 取 incense、B 取 incense_b；翻面之前照旧不回）
--   ★只在结果单里真有香火（是 JSON 对象）时才多一个键 ⇒ 老裁判程序 / 老客户端不受影响。
--   ★不在这里校验 marks / charge 的形状：结果单只能由裁判机（service_role）写；客户端记账时再夹一遍（RefereeNet.parse_incense）。
-- 上线步骤（tools/sb_migrate.py 标准路径；内测服先走一遍；**必须排在 20261022b 之后**）：
--   sandbox → beta --rehearse → beta --apply → 内测服冒烟 → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
--   之后：裁判机装带 `incense` 的新客户端版本（RefereeRunner 写 incense / incense_b）、登记 referee_versions。
--   在那之前结果单没有 incense ⇒ 两个接口与 20261022b 逐字相同的回包。
-- 回滚：把两个函数换回 20261022b 版（结果单里多存的 incense 无害）。
-- ─────────────────────────────────────────────────────────────

-- ① 周六：查自己那一场算完没有（只认 a_account = 自己；不回快照）
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
    'error', case when j.status = 'failed' then j.error end)
    -- 2026-10-22b：这一局结束时我方宝箱龟的进度（财宝值 + 已开战利品）
    || case when j.status = 'done' and jsonb_typeof(j.result->'chest') = 'object'
            then jsonb_build_object('chest', j.result->'chest') else '{}'::jsonb end
    -- 2026-10-23：这一局结束时我方 093 香火石的刻痕 + 充能
    || case when j.status = 'done' and jsonb_typeof(j.result->'incense') = 'object'
            then jsonb_build_object('incense', j.result->'incense') else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ② 周日：查我在这一场的战斗内铸币 + 宝箱进度 + 香火（只读；翻面之前不回数）
create or replace function public.referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null; inc jsonb := null;
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
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end
    || case when jsonb_typeof(inc) = 'object' then jsonb_build_object('incense', inc) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;
-- <<< END referee_incense 20261023 <<<
-- referee_incense 20261023 已上生产 2026-10-24（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同、正式服账本 schema_migrations 有这一行）

-- >>> BEGIN friends 20261024 >>>
-- ─────────────────────────────────────────────────────────────
-- 好友 + 切磋（2026-10-24 · 方案书 docs/plans/20261023-好友切磋.md §4.1）
--   用户 2026-10-23「接下来新任务，好友系统，主要实现切磋 … 切磋是当前的背包阵容vs好友的最新背包阵容」
--   用户拍板：加好友 = 双方同意；好友上限 100；切磋不进战绩（切磋本身不碰服务端，见 scripts/systems/social/spar.gd）。
--   客户端：scripts/net/friends_net.gd（调下面这几个 RPC）· scripts/scenes/FriendsScene.gd（好友页）。
--
-- 本文件做四件事：
--   ① lineups：每人一行「最新背包阵容」+ 服务端算的玩家 ID（按 ID 找人只查这张表）
--      ★为什么另建表：ghosts 只在积分赛结算那一刻传、每周二清，没有「最新背包阵容」（方案书 §2.2）
--      ★为什么不在 accounts 上加 tag：开机就写 accounts 会让所有号都「有数据」，垃圾匿名号清理（purge_junk_anon_users）
--        就再也清不掉测试机造的号 —— lineups 只在玩家真的配过阵容 / 打开过好友页时才有
--   ② friendships：好友关系（a < b 一行；pending / accepted / declined）
--   ③ RPC：put_lineup / friend_lookup / friend_request / friend_respond / friend_remove / friend_list / friend_lineup
--   ④ 垃圾匿名号清理 / 昵称举报处理补上新表（删号不用改：两张表都随 auth.users on delete cascade）
--
-- ★两张表都开 RLS、不建 policy、revoke ⇒ 客户端直连读写一律被拒，只走 security definer 函数。
-- ★好友的阵容只对好友可读（friend_lineup 先验关系是 accepted）。按 ID 查人只回昵称 + 头像，不回阵容。
-- ★被拒的申请不删、记成 declined：同一个人 30 天内再申请 ⇒ 回「已申请」但什么都不发（防反复骚扰；对方看不到）。
--   对方之后主动来申请 ⇒ 照常成立。
-- ★本文件只建表 / 建函数 / 重定义两个函数，不删任何已有数据。重复执行安全。
-- ★上线前先跑 server/supabase/tests/20261024_friends_check.sql（整段一个事务，结尾一定抛异常 ⇒ 回滚）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 最新阵容 ═══
create table if not exists public.lineups (
  account_id     uuid        primary key references auth.users(id) on delete cascade,
  tag            text        not null,                       -- player_tag_of(account_id)：服务端算，不信客户端
  name           text        not null default '' check (char_length(name) <= 40),
  snapshot       jsonb       not null default '{}'::jsonb,  -- Backend.build_ghost_snapshot() 的产物；{} = 还没配阵容
  rules_ver      int         not null default 0,
  client_version text        not null default '' check (char_length(client_version) <= 32),
  updated_at     timestamptz not null default now()
);
create index if not exists lineups_tag_idx on public.lineups (tag);
alter table public.lineups enable row level security;
revoke all on public.lineups from anon, authenticated, public;

-- ═══ ② 好友关系 ═══
create table if not exists public.friendships (
  a           uuid        not null references auth.users(id) on delete cascade,
  b           uuid        not null references auth.users(id) on delete cascade,
  requester   uuid        not null,
  status      text        not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (a, b),
  check (a < b),
  check (requester = a or requester = b)
);
create index if not exists friendships_b_idx on public.friendships (b);
alter table public.friendships enable row level security;
revoke all on public.friendships from anon, authenticated, public;

-- 一份快照的头像 = 第一只统领；老快照 / 空快照退回 profile.avatar；都没有 ⇒ ''。
create or replace function public.snapshot_lead(p_snap jsonb) returns text
language sql immutable as $$
  select coalesce(nullif(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' ->> 0 end, ''),
                  nullif(p_snap -> 'profile' ->> 'avatar', ''), '')
$$;
revoke all on function public.snapshot_lead(jsonb) from public, anon, authenticated;

-- 一行好友 / 申请给客户端看的样子（对方那一侧）。
create or replace function public.friend_card(p_other uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'account', p_other,
    'tag', public.player_tag_of(p_other::text),
    'name', coalesce(l.name, ''),
    'lead', coalesce(public.snapshot_lead(l.snapshot), ''),
    'has_lineup', coalesce(l.snapshot ? 'leaders', false),
    'updated_at', l.updated_at)
  from (select 1) one left join public.lineups l on l.account_id = p_other
$$;
revoke all on function public.friend_card(uuid) from public, anon, authenticated;

-- ═══ ③ RPC ═══

-- 传我的最新阵容（离开背包 / 打开好友页 / 出战时；客户端只在阵容有变化时传）。
-- p_snapshot = {} 也收（还没配阵容的人也要能被按 ID 找到）。上限 64 KB（真实快照约 5~15 KB）。
-- 返回 {ok:true, tag} 或 {ok:false, reason: not_signed_in | bad_snapshot | too_big}。
create or replace function public.put_lineup(p_name text, p_snapshot jsonb, p_rules_ver int, p_client_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); tg text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  if octet_length(p_snapshot::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'too_big');
  end if;
  tg := public.player_tag_of(uid::text);
  insert into public.lineups as t (account_id, tag, name, snapshot, rules_ver, client_version, updated_at)
    values (uid, tg, left(btrim(coalesce(p_name, '')), 40), p_snapshot, coalesce(p_rules_ver, 0),
            left(coalesce(p_client_version, ''), 32), now())
  on conflict (account_id) do update
    set tag = excluded.tag, name = excluded.name, snapshot = excluded.snapshot,
        rules_ver = excluded.rules_ver, client_version = excluded.client_version, updated_at = now();
  return jsonb_build_object('ok', true, 'tag', tg);
end $$;

-- 按玩家 ID 找人（玩家 ID 不唯一：1 万人约 0.1 对撞号 ⇒ 可能回多个，客户端让玩家按昵称挑）。最多 5 个，不含自己。
-- 返回 {ok:true, people:[friend_card…]} 或 {ok:false, reason: not_signed_in | bad_tag | self | not_found}。
create or replace function public.friend_lookup(p_tag text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); ppl jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_tag is null or p_tag !~ '^#[23456789BCDFGHJKMNPQRSTVWXYZ]{6}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_tag');
  end if;
  select coalesce(jsonb_agg(public.friend_card(x.account_id) order by x.updated_at desc), '[]'::jsonb) into ppl
    from (select account_id, updated_at from public.lineups
           where tag = p_tag and account_id <> uid order by updated_at desc limit 5) x;
  if jsonb_array_length(ppl) = 0 then
    return jsonb_build_object('ok', false,
      'reason', case when p_tag = public.player_tag_of(uid::text) then 'self' else 'not_found' end);
  end if;
  return jsonb_build_object('ok', true, 'people', ppl);
end $$;

-- 申请加好友（p_other 来自 friend_lookup 的 account）。对方已经申请过我 ⇒ 直接成为好友。
-- 返回 {ok:true, status: pending | accepted} 或
--   {ok:false, reason: not_signed_in | self | not_found | already | full | their_full | limit}。
create or replace function public.friend_request(p_other uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  lo uuid; hi uuid;
  fr public.friendships%rowtype;
  had boolean;
  n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_other is null or p_other = uid then
    return jsonb_build_object('ok', false, 'reason', 'self');
  end if;
  if not exists (select 1 from public.lineups where account_id = p_other) then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  lo := least(uid, p_other); hi := greatest(uid, p_other);
  perform pg_advisory_xact_lock(hashtext('friend:' || lo::text || hi::text));
  select * into fr from public.friendships where a = lo and b = hi;
  had := found;                 -- ★下面的 select count(*) into 会把 found 重置成真, 先存下来
  if had and fr.status = 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'already');
  end if;
  if had and fr.requester = uid then
    return jsonb_build_object('ok', true, 'status', 'pending');   -- 已申请过（含被拒：对方看不到, 不再打扰）
  end if;
  -- 好友上限 100（双方各自数 accepted）
  select count(*) into n from public.friendships where (a = uid or b = uid) and status = 'accepted';
  if n >= 100 then
    return jsonb_build_object('ok', false, 'reason', 'full');
  end if;
  if had and fr.status = 'pending' then
    -- 对方已经申请过我 ⇒ 这次申请就是同意
    select count(*) into n from public.friendships where (a = p_other or b = p_other) and status = 'accepted';
    if n >= 100 then
      return jsonb_build_object('ok', false, 'reason', 'their_full');
    end if;
    update public.friendships set status = 'accepted', accepted_at = now() where a = lo and b = hi;
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  -- 每人 24 小时最多发 30 个申请
  select count(*) into n from public.friendships where requester = uid and created_at > now() - interval '24 hours';
  if n >= 30 then
    return jsonb_build_object('ok', false, 'reason', 'limit');
  end if;
  if had then
    -- 走到这里 = 对方以前申请过我、被我拒了（fr.requester = 对方, declined），现在我主动来加 ⇒ 改成我发出的申请
    update public.friendships set requester = uid, status = 'pending', created_at = now(), accepted_at = null
     where a = lo and b = hi;
  else
    insert into public.friendships (a, b, requester) values (lo, hi, uid);
  end if;
  return jsonb_build_object('ok', true, 'status', 'pending');
end $$;

-- 回应别人发给我的申请：同意 ⇒ accepted；拒绝 ⇒ declined（对方看到的仍是「等待对方同意」）。
-- 返回 {ok:true, status: accepted | declined} 或 {ok:false, reason: not_signed_in | not_found | full | their_full}。
create or replace function public.friend_respond(p_other uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); lo uuid; hi uuid; n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_other is null or p_other = uid then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  lo := least(uid, p_other); hi := greatest(uid, p_other);
  perform pg_advisory_xact_lock(hashtext('friend:' || lo::text || hi::text));
  if not exists (select 1 from public.friendships
                  where a = lo and b = hi and requester = p_other and status = 'pending') then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if not coalesce(p_accept, false) then
    update public.friendships set status = 'declined' where a = lo and b = hi;
    return jsonb_build_object('ok', true, 'status', 'declined');
  end if;
  select count(*) into n from public.friendships where (a = uid or b = uid) and status = 'accepted';
  if n >= 100 then
    return jsonb_build_object('ok', false, 'reason', 'full');
  end if;
  select count(*) into n from public.friendships where (a = p_other or b = p_other) and status = 'accepted';
  if n >= 100 then
    return jsonb_build_object('ok', false, 'reason', 'their_full');
  end if;
  update public.friendships set status = 'accepted', accepted_at = now() where a = lo and b = hi;
  return jsonb_build_object('ok', true, 'status', 'accepted');
end $$;

-- 删好友 / 撤回我发出的申请。拒绝过的那一行（对方发给我、我拒了）不删 —— 删了对方就能立刻再发。
-- 返回 {ok:true} 或 {ok:false, reason: not_signed_in | not_found}。
create or replace function public.friend_remove(p_other uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  delete from public.friendships
   where a = least(uid, p_other) and b = greatest(uid, p_other)
     and (status = 'accepted' or (requester = uid and status = 'pending'));
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 好友页一次拿全：我的玩家 ID、好友、别人发给我的申请、我发出的申请（被拒的也照样显示「等待对方同意」）。
create or replace function public.friend_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); fr jsonb; inc jsonb; outg jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select coalesce(jsonb_agg(public.friend_card(case when f.a = uid then f.b else f.a end) order by f.accepted_at desc), '[]'::jsonb)
    into fr from public.friendships f where (f.a = uid or f.b = uid) and f.status = 'accepted';
  select coalesce(jsonb_agg(public.friend_card(f.requester) order by f.created_at desc), '[]'::jsonb)
    into inc from public.friendships f where (f.a = uid or f.b = uid) and f.status = 'pending' and f.requester <> uid;
  select coalesce(jsonb_agg(public.friend_card(case when f.a = uid then f.b else f.a end) order by f.created_at desc), '[]'::jsonb)
    into outg from public.friendships f where f.requester = uid and f.status in ('pending', 'declined');
  return jsonb_build_object('ok', true, 'tag', public.player_tag_of(uid::text),
    'friends', fr, 'incoming', inc, 'outgoing', outg, 'cap', 100);
end $$;

-- 切磋：取好友的最新阵容。★先验双方是好友（accepted）。
-- lineups 里还没有阵容（{}）⇒ 退回对方最新一行积分赛快照（ghosts）；都没有 ⇒ no_lineup。
-- 返回 {ok:true, name, tag, snapshot, rules_ver, client_version, updated_at, source: lineup | ghost}
--   或 {ok:false, reason: not_signed_in | not_friends | no_lineup}。
create or replace function public.friend_lineup(p_other uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); l public.lineups%rowtype; g record;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if p_other is null or not exists (select 1 from public.friendships
       where a = least(uid, p_other) and b = greatest(uid, p_other) and status = 'accepted') then
    return jsonb_build_object('ok', false, 'reason', 'not_friends');
  end if;
  select * into l from public.lineups where account_id = p_other;
  if found and l.snapshot ? 'leaders' then
    return jsonb_build_object('ok', true, 'source', 'lineup', 'name', l.name, 'tag', l.tag,
      'snapshot', l.snapshot, 'rules_ver', l.rules_ver, 'client_version', l.client_version, 'updated_at', l.updated_at);
  end if;
  select snapshot, rules_ver, client_version, uploaded_at into g from public.ghosts
   where account_id = p_other order by uploaded_at desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_lineup');
  end if;
  return jsonb_build_object('ok', true, 'source', 'ghost',
    'name', coalesce(nullif(l.name, ''), g.snapshot -> 'profile' ->> 'name', ''),
    'tag', public.player_tag_of(p_other::text),
    'snapshot', g.snapshot, 'rules_ver', g.rules_ver, 'client_version', g.client_version, 'updated_at', g.uploaded_at);
end $$;

revoke all on function public.put_lineup(text, jsonb, int, text) from public;
revoke all on function public.friend_lookup(text) from public;
revoke all on function public.friend_request(uuid) from public;
revoke all on function public.friend_respond(uuid, boolean) from public;
revoke all on function public.friend_remove(uuid) from public;
revoke all on function public.friend_list() from public;
revoke all on function public.friend_lineup(uuid) from public;
revoke execute on function public.put_lineup(text, jsonb, int, text) from anon;
revoke execute on function public.friend_lookup(text) from anon;
revoke execute on function public.friend_request(uuid) from anon;
revoke execute on function public.friend_respond(uuid, boolean) from anon;
revoke execute on function public.friend_remove(uuid) from anon;
revoke execute on function public.friend_list() from anon;
revoke execute on function public.friend_lineup(uuid) from anon;
grant execute on function public.put_lineup(text, jsonb, int, text) to authenticated;
grant execute on function public.friend_lookup(text) to authenticated;
grant execute on function public.friend_request(uuid) to authenticated;
grant execute on function public.friend_respond(uuid, boolean) to authenticated;
grant execute on function public.friend_remove(uuid) to authenticated;
grant execute on function public.friend_list() to authenticated;
grant execute on function public.friend_lineup(uuid) to authenticated;

-- ═══ ④ 补新表 ═══
-- 垃圾匿名号清理：有阵容行 / 有好友关系的号不算「没数据」（只打切磋、不打积分赛的人也是真人）。
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
    and not exists (select 1 from public.accounts x where x.account_id = u.id)
    and not exists (select 1 from public.lineups x where x.account_id = u.id)
    and not exists (select 1 from public.friendships x where x.a = u.id or x.b = u.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.purge_junk_anon_users() from public, anon, authenticated;

-- 昵称举报处理：重置时阵容行里的名字也换成占位（否则好友列表 / 按 ID 查人还显示原名，直到对方下次传阵容）。
--   其余与 20261020b 逐字相同（只在 accounts 那一句之前插了 lineups 两句）。
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
  update public.lineups set name = ph where account_id = acc and name = any(names);
  get diagnostics tmp_n = row_count; n := n + tmp_n;
  update public.lineups set snapshot = jsonb_set(snapshot, '{profile,name}', to_jsonb(ph))
   where account_id = acc and snapshot->'profile'->>'name' = any(names);
  update public.accounts set display_name = ph where account_id = acc and display_name = any(names);
  update public.nickname_reports set status = 'reset', handled_at = now()
   where reported_tag = p_tag and status = 'pending';
  return jsonb_build_object('ok', true, 'action', 'reset', 'account', acc, 'names', to_jsonb(names), 'scrubbed', n);
end $$;
revoke all on function public.nickname_report_resolve(text, text) from public, anon, authenticated;
grant execute on function public.nickname_report_resolve(text, text) to service_role;

-- 上线后回读（memory：`revoke from public` 收不掉 anon 的默认授权，必须逐个看）：
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute')
--     from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('put_lineup', 'friend_lookup', 'friend_request', 'friend_respond', 'friend_remove',
--                        'friend_list', 'friend_lineup', 'friend_card', 'snapshot_lead');
--   期望：anon 全 false；authenticated 前七个 true、friend_card / snapshot_lead false。
-- <<< END friends 20261024 <<<
-- friends 20261024 已上生产 2026-10-24（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同、正式服账本 schema_migrations 有这一行）

-- >>> BEGIN leaderboard_lead 20261024b >>>
-- ─────────────────────────────────────────────────────────────
-- 周榜每行多下发「头像」= 这个人第一只统领（2026-10-24 · 方案书 docs/plans/20261023-排行榜重做.md）
--   用户 2026-10-23 只选了「看着像网页，没有游戏味」⇒ 重做以视觉质感为主：每行加头像（第一只统领立绘）。
--   原来每行只有 名次 / 昵称 / ID / 胜 / 余命 / 横扫 / 总场次 / 头衔，快照里有统领但服务端没下发。
-- ★只改 week_leaderboard_page：每行多一个键 `lead`（snapshot_lead：leaders[0]，老快照退回 profile.avatar）。
--   其余逐字照抄 20261019（口径 / 排序 / 分页 / 权限一个字不动）。老包不认这个键 ⇒ 照旧画字。
-- ★依赖 20261024_friends 里的 public.snapshot_lead —— 两份迁移按序上。
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
           g.snapshot -> 'profile' ->> 'tag'  as tag,
           public.snapshot_lead(g.snapshot)   as lead
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
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, '')) order by r.rk) filter (where r.rk > off and r.rk <= off + lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, page, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'offset', off,
    'rows', page, 'me', mine);
end $$;

revoke all on function public.week_leaderboard_page(bigint, int, int) from public;
revoke execute on function public.week_leaderboard_page(bigint, int, int) from anon;
grant execute on function public.week_leaderboard_page(bigint, int, int) to authenticated;
-- <<< END leaderboard_lead 20261024b <<<
-- leaderboard_lead 20261024b 已上生产 2026-10-24（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同、正式服账本 schema_migrations 有这一行）

-- >>> BEGIN referee_health 20261026 >>>
-- ─────────────────────────────────────────────────────────────
-- 裁判机外部探活口（2026-10-26 · 方案书 docs/plans/20261026-裁判机外部监控.md）
--   10-25 裁判机整机断网约 79 分钟没人知道：机器上的健康检查连不上库、也没有任何对外通知。
--   外部（GitHub Actions `referee-watch.yml` → tools/referee_watch.py）要一个【匿名能调】、只回几个数的探活口 ——
--   referee_backlog() 只授权 service_role，外部拿不到。
-- ★只读：不建表、不改表、不写任何一行。不暴露玩家数据 / 线程名 / 版本列表，只回四个数。
-- ★「最新」一次心跳（max seen_at）：心跳表里可能留着换过名的历史线程行，取最旧会被旧行拖住。
--   没有任何心跳行 ⇒ freshest_sec = null（探活脚本当成失联）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_health()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'freshest_sec', (select extract(epoch from now() - max(seen_at))::int from public.referee_workers),
    'fresh_workers', (select count(*) from public.referee_workers where seen_at > now() - interval '180 seconds'),
    'pending', (select count(*) from public.referee_jobs where status = 'pending'),
    'oldest_pending_sec', (select coalesce(extract(epoch from now() - min(created_at))::int, 0)
                             from public.referee_jobs where status = 'pending'))
$$;

revoke all on function public.referee_health() from public;
grant execute on function public.referee_health() to anon, authenticated, service_role;
-- <<< END referee_health 20261026 <<<
-- referee_health 20261026 已上生产 2026-10-26（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同）

-- >>> BEGIN gauntlet_sunday_close 20261026b >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛截止从周六 23:00 改到周日 17:30 UTC（2026-10-26 · 方案书 docs/plans/20261026b-周六流程.md §4 G3）
--   用户「截止时间不如改到周日桶赛之前呢」→ 选周日 17:30（分桶 finals_seat 18:00 前半小时）。
-- ★改三个函数，其余逐字照抄各自最新那份（referee_gauntlet_start / referee_submit_gauntlet ← 20261021；
--   referee_complete ← 20261020d）：
--   ① 两个开打闸的上界 p_week + 6*86400（周日 00:00）→ p_week + 6*86400 + 17*3600 + 1800（周日 17:30），仍走 app_now()
--   ② referee_complete 闯关那一支：战绩到 4 胜 ⇒ 直接插 finals_pending（客户端报名留作兜底）
-- ★老客户端无害：多一段可开打的时间（老客户端自己按周六判，不会在周日来开）；多登记一次报名是幂等的。
-- ─────────────────────────────────────────────────────────────
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
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 00:00 ~ 周日 17:30（周锚点 + 5 天 ~ + 6 天 17:30；2026-10-26 起，原为周六一整天；UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800)) then
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
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 00:00 ~ 周日 17:30（周锚点 + 5 天 ~ + 6 天 17:30；2026-10-26 起，原为周六一整天；UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800)) then
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
    -- ★2026-10-26 第 4 胜由服务端直接登记决赛报名（= phase2_config.GAUNTLET_WINS_IN；同 finals_enter 的 floor_wins）。
    --   闯关赛延到周日 17:30、分桶 18:00 只剩 30 分钟；原来只靠客户端结算后 / 开主菜单时报名，第 4 胜结算晚或玩家关了游戏
    --   ⇒ 18:00 后才报 ⇒ already_seated，错过决赛。客户端那两条留作兜底（finals_enter 同一张表、幂等 upsert）。
    --   已经有人报过（客户端先到）就不动它；桶已坐定就不再塞人（与 finals_enter 同一条）。
    if v_gw >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.a_account, coalesce(nullif(j.a_snapshot->'profile'->>'name', ''), '?'), j.a_snapshot, v_gw, v_gl)
        on conflict (season_week, account_id) do nothing;
    end if;
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

-- <<< END gauntlet_sunday_close 20261026b <<<
-- gauntlet_sunday_close 20261026b 已上生产 2026-10-26（tools/sb_migrate.py prod --rehearse --apply，演练 ALL PASS、回读函数体逐字相同）

-- >>> BEGIN gauntlet_online_queue 20261027 >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛改在线瑞士轮（2026-10-27 · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2）
--   用户 10-27「一定是要我这边匹配之后，我这个阵容处于锁定状态……等到了另外一个对手也锁定了他的这个阵容……才互相匹配」
--   「周六周日我们讲究是在线啊」。
--   现状：referee_gauntlet_start 当场配一份对方快照、只记我这一边 ⇒ 两边各打对方快照、可能互相都赢。
--   改成：锁阵容进队列 → 等同战绩格子里另一个也在线锁定的人 → 只建一条任务、裁判算一次、两边都记。
--
-- 本段内容：
--   ① 表：gauntlet_queue（排队行）、bot_accounts（陪练号名单，只有 service_role 碰得到）；referee_jobs 加 b_account 索引。
--      ★b_account 列 20261019 就有：旧路真人快照对手填账号、机器人池 null。
--        ⇒「两边都记」不能按 b_account 非空判（那会把被打的那份快照的主人也记一场），只认 meta.pair = true。
--   ② 客户端 RPC（authenticated）：gauntlet_queue_join / gauntlet_queue_poll / gauntlet_queue_cancel
--      配对 = 同周、同格子（gw / gl）、同客户端版本、同规则版本、15 秒内有心跳、本周没交手过、都没有在算的局；
--        先来先配，先来的当 A。真人和陪练号一视同仁（陪练号周末是真客户端，走同一套接口）。
--      真人等满 90 秒还没配上 ⇒ 退回机器人池快照（referee_gauntlet_pick 的机器人那一支），建一条 b_account 为空、
--        只记真人一边的任务（与旧路同一种）。陪练号（bot_accounts）不走兜底：等不到人由它自己取消。
--   ③ 服务 RPC（service_role）：gauntlet_service_state（陪练号调度器看排队 / 在打 / 每个陪练号的格子、忙不忙、打完没有、交过手的人）
--   ④ 重定义：
--      referee_complete（配对局两边都记：战绩互反 / 快照池 / 第 4 胜报名 / 账本 coins_b / matches.right_account = B）
--      referee_job_status（配对局的 B 也能查，回包按 B 的视角）
--      referee_gauntlet_start（「在算的那场」认配对局里的 B；其余逐字照抄 20261026b）
--      referee_gauntlet_pick（对手排除表多看配对局里我当 B 的那一侧；排除表与机器人那一支抽成函数，兜底共用）
--   ★旧路任务（meta 没有 pair）写回 / 查询与本段之前逐字相同 —— 检查脚本拿改前函数体对同一输入比结果。
--   ★幂等键：配对局 gpair:<周>:<A 排队行>:<B 排队行>、兜底局 gfallback:<周>:<排队行>（一条排队行最多配一次）；
--     B 的防重交靠排队行状态 + 「有在算的局就不排」。
--   ★算失败的配对局（referee_fail 次数用尽 / 删号作废）：两边的排队行在下次 join / poll / cancel 时作废（cancelled，
--     job_id 留着），各自重新排队；种子 / 对手不沿用（旧路「重交同一场」那套只对 gauntlet:<周>:<账号>:<场> 的任务）。
--     两人本周不再互配（交手判定按任务行，不分成败 —— 与 referee_gauntlet_pick 的排除表同一口径）。
-- 上线步骤（tools/sb_migrate.py 标准路径）：sandbox → beta --rehearse → beta --apply → 内测服彩排 → prod --precheck → prod --rehearse → prod --apply。
--   新客户端（走队列）上架前执行本段无害：没人调三个新接口；旧接口 referee_gauntlet_start 只多认了配对局里的 B。
-- 回滚：三个被重定义的函数换回各自上一版（referee_complete / referee_gauntlet_start ← 20261026b、referee_job_status ← 20261023、
--   referee_gauntlet_pick ← 20261020c）；新表 / 新函数留着不影响旧包。
-- ★重复执行安全（if not exists / create or replace / 先 unschedule 再 schedule）。
-- ─────────────────────────────────────────────────────────────

-- ① 表 ──────────────────────────────────────────────────────
create table if not exists public.gauntlet_queue (
  id             bigint      generated always as identity primary key,
  season_week    bigint      not null,
  account_id     uuid        not null references auth.users(id) on delete cascade,
  gw             int         not null check (gw between 0 and 9),     -- 排队那一刻账本上的战绩 = 格子
  gl             int         not null check (gl between 0 and 9),
  rules_ver      int         not null,
  client_version text        not null,
  snapshot       jsonb       not null,                                -- 锁定的阵容（配上后原样进任务）
  joined_at      timestamptz not null default now(),
  last_seen      timestamptz not null default now(),                  -- 心跳（客户端每 2 秒 poll 一次）
  paired_at      timestamptz,
  status         text        not null default 'waiting'
                 check (status in ('waiting', 'paired', 'cancelled', 'expired', 'done')),
  job_id         bigint      references public.referee_jobs(job_id) on delete set null,
  side           text        check (side in ('a', 'b')),
  updated_at     timestamptz not null default now()
);
-- 同一周同一账号最多一条 waiting
create unique index if not exists gauntlet_queue_one_waiting
  on public.gauntlet_queue (season_week, account_id) where status = 'waiting';
create index if not exists gauntlet_queue_cell_idx
  on public.gauntlet_queue (season_week, gw, gl, joined_at) where status = 'waiting';
create index if not exists gauntlet_queue_acc_idx on public.gauntlet_queue (season_week, account_id, id);
create index if not exists gauntlet_queue_job_idx on public.gauntlet_queue (job_id) where job_id is not null;
alter table public.gauntlet_queue enable row level security;
revoke all on table public.gauntlet_queue from anon, authenticated;
grant all on table public.gauntlet_queue to service_role;
-- 没有任何策略 ⇒ 客户端直连读不到（快照 = 阵容情报）；只经下面的函数。

-- 陪练号名单（裁判机上的调度器写；客户端看不到 ⇒ 排行榜 / 赛况板不区分真人与陪练号）
create table if not exists public.bot_accounts (
  account_id uuid        primary key references auth.users(id) on delete cascade,
  added_at   timestamptz not null default now()
);
alter table public.bot_accounts enable row level security;
revoke all on table public.bot_accounts from anon, authenticated;
grant all on table public.bot_accounts to service_role;

-- 配对局里 B 那一侧的查找（referee_job_status / 在算的那场 / 交手排除表）
create index if not exists referee_jobs_b_acc_idx on public.referee_jobs (season_week, b_account);

-- ② 小工具（内部，不授权给客户端）───────────────────────────────
-- 心跳多久没刷新算离开 / 真人等多久退回机器人池（秒）。客户端每 2 秒 poll。
create or replace function public.gauntlet_queue_ttl_sec() returns int
language sql immutable as $$ select 15 $$;
create or replace function public.gauntlet_queue_fallback_sec() returns int
language sql immutable as $$ select 90 $$;
revoke all on function public.gauntlet_queue_ttl_sec() from public, anon, authenticated;
revoke all on function public.gauntlet_queue_fallback_sec() from public, anon, authenticated;

-- 闯关赛开着没有：周六 00:00 ~ 周日 17:30 UTC（= referee_gauntlet_start 的 closed 闸；内测服 gauntlet_any_day 放开）
create or replace function public.gauntlet_window_open(p_week bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.gauntlet_any_day from public.referee_config c where c.id = 1), false)
      or (public.app_now() >= to_timestamp(p_week + 5 * 86400)
          and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800))
$$;
revoke all on function public.gauntlet_window_open(bigint) from public, anon, authenticated;

-- 账本上的 [胜, 负]（没有行 = [0, 0]）
create or replace function public.gauntlet_wl(p_week bigint, p_uid uuid) returns int[]
language sql stable security definer set search_path = public as $$
  select array[coalesce(max(r.gw), 0), coalesce(max(r.gl), 0)]
    from public.gauntlet_records r where r.season_week = p_week and r.account_id = p_uid
$$;
revoke all on function public.gauntlet_wl(bigint, uuid) from public, anon, authenticated;

-- 有没有一场闯关在算（旧路 / 兜底局里我是 A；配对局里我是 A 或 B）
create or replace function public.gauntlet_in_job(p_week bigint, p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.referee_jobs j
                  where j.kind = 'gauntlet' and j.season_week = p_week and j.status in ('pending', 'claimed')
                    and (j.a_account = p_uid or (j.b_account = p_uid and j.meta->>'pair' = 'true')))
$$;
revoke all on function public.gauntlet_in_job(bigint, uuid) from public, anon, authenticated;

-- 本周已经碰过的对手（账号 uuid 文本 / 'bot:…'）。原样抽自 20261020c referee_gauntlet_pick 的 v_ex，
--   ★2026-10-27 多一支：配对局里我是 B ⇒ 对手是 A（A 那一侧本来就记在 meta.opp 里）。
create or replace function public.referee_gauntlet_opp_ex(p_uid uuid, p_week bigint) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x), '{}')
    from (select j.meta->>'opp' as x from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid and j.meta ? 'opp'
          union all
          select jsonb_array_elements_text(j.meta->'opp_prev') from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.a_account = p_uid
             and jsonb_typeof(j.meta->'opp_prev') = 'array'
          union all
          select j.a_account::text from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.b_account = p_uid and j.meta->>'pair' = 'true') e
   where x is not null
$$;
revoke all on function public.referee_gauntlet_opp_ex(uuid, bigint) from public, anon, authenticated;

-- 机器人池挑一份（原样抽自 20261020c referee_gauntlet_pick 的「② 机器人」那一支；p_ex = 上面的排除表）。
--   排队兜底只用这一支（不挑真人快照 ⇒ 不会再出现「两边各打对方快照」）。
create or replace function public.referee_gauntlet_pick_bot(p_gw int, p_gl int, p_rules_ver int, p_battles int,
    p_ex text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare bp record; bk int; snap jsonb;
begin
  -- ② 机器人：池子按场次存到 30（= bot_pool.gd MAX_BATTLES；装备曲线 28 场封顶），超出的用 30 那一格
  bk := least(greatest(coalesce(p_battles, 0), p_gw + p_gl, 0), 30);
  select b.* into bp
    from public.gauntlet_bot_pool b
   where b.rules_ver = p_rules_ver and b.battles = bk and b.gw = p_gw and b.gl = p_gl
   order by (format('bot:%s:%s:%s:%s:%s', b.rules_ver, b.battles, b.gw, b.gl, b.variant) = any(p_ex)), random()
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
revoke all on function public.referee_gauntlet_pick_bot(int, int, int, int, text[]) from public, anon, authenticated;

-- 挑一个对手（旧路 referee_gauntlet_start 用）。以 20261020c 版为底：① 同标签真人那一段逐字不变；
--   ★2026-10-27 只改两处：排除表改调 referee_gauntlet_opp_ex（多看配对局里我当 B 的那一侧）、② 机器人那一支改调 referee_gauntlet_pick_bot。
create or replace function public.referee_gauntlet_pick(p_uid uuid, p_week bigint, p_gw int, p_gl int,
    p_rules_ver int, p_battles int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_ex text[]; g record;
begin
  v_ex := public.referee_gauntlet_opp_ex(p_uid, p_week);
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
  -- ② 机器人
  return public.referee_gauntlet_pick_bot(p_gw, p_gl, p_rules_ver, p_battles, v_ex);
end $$;
revoke all on function public.referee_gauntlet_pick(uuid, bigint, int, int, int, int) from public, anon, authenticated;

-- 我那几条「已配上、但那一局算失败了 / 任务行没了」的排队行 ⇒ 作废（cancelled，job_id 留着），好重新排队
create or replace function public.gauntlet_queue_void_failed(p_week bigint, p_uid uuid) returns void
language sql security definer set search_path = public as $$
  update public.gauntlet_queue q set status = 'cancelled', updated_at = now()
   where q.season_week = p_week and q.account_id = p_uid and q.status = 'paired'
     and not exists (select 1 from public.referee_jobs j where j.job_id = q.job_id and j.status <> 'failed')
$$;
revoke all on function public.gauntlet_queue_void_failed(bigint, uuid) from public, anon, authenticated;

-- 一条排队行 → 客户端回包。
--   waiting ⇒ {ok, status:'waiting', gw, gl, waited_sec}
--   paired / done ⇒ {ok, status:'paired', gw, gl, waited_sec, job_id, match_id, side, job_status, opp:对手卡}
--     （done 也回 paired：配上之后客户端照现有流程按 job_id 查结果；job_status 告诉它这一局算完没有）
--   expired ⇒ {ok, status:'expired', gw, gl}；cancelled / 没有 ⇒ {ok, status:'none'}（算失败作废的多带 reason:'job_failed' + job_id）
create or replace function public.gauntlet_queue_view(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.gauntlet_queue%rowtype; j record;
begin
  select * into q from public.gauntlet_queue where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'status', 'none');
  end if;
  if q.status = 'waiting' then
    return jsonb_build_object('ok', true, 'status', 'waiting', 'gw', q.gw, 'gl', q.gl,
      'waited_sec', greatest(0, floor(extract(epoch from now() - q.joined_at)))::int);
  end if;
  if q.status in ('paired', 'done') then
    select * into j from public.referee_jobs where job_id = q.job_id;
    return jsonb_build_object('ok', true, 'status', 'paired', 'gw', q.gw, 'gl', q.gl,
      'waited_sec', greatest(0, floor(extract(epoch from coalesce(q.paired_at, now()) - q.joined_at)))::int,
      'job_id', q.job_id, 'match_id', j.match_id, 'side', q.side, 'job_status', j.status,
      'opp', public.referee_opp_card(case when q.side = 'a' then j.b_snapshot else j.a_snapshot end));
  end if;
  if q.status = 'expired' then
    return jsonb_build_object('ok', true, 'status', 'expired', 'gw', q.gw, 'gl', q.gl);
  end if;
  return jsonb_build_object('ok', true, 'status', 'none', 'gw', q.gw, 'gl', q.gl)
    || case when q.job_id is not null then jsonb_build_object('reason', 'job_failed', 'job_id', q.job_id) else '{}'::jsonb end;
end $$;
revoke all on function public.gauntlet_queue_view(bigint) from public, anon, authenticated;

-- 推一条 waiting 往前走：先找同格子的在线对手配成一局；没有、而且是真人、已经等满 90 秒 ⇒ 退回机器人池。
--   ★每个格子一把事务级 advisory 锁（同周同 gw / gl）：同一格子里的配对一个一个来 ⇒ 两个人同时进来也只建一条任务；
--     候选行再加 for update skip locked（正被它自己的 poll / cancel 改的那一行这一轮不碰，不互等）。
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int;
begin
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  select * into me from public.gauntlet_queue where id = p_id;
  if not found or me.status <> 'waiting' then
    return;
  end if;
  perform pg_advisory_xact_lock(20261027, hashtext(format('gauntlet_cell:%s:%s:%s', me.season_week, me.gw, me.gl)));
  select * into me from public.gauntlet_queue where id = p_id for update;
  if me.status <> 'waiting' or me.last_seen < now() - v_ttl then
    return;                                   -- 锁到手时已经被别人配走 / 自己心跳断了
  end if;
  if public.gauntlet_in_job(me.season_week, me.account_id) then
    return;                                   -- 还有一场在算 ⇒ 先不配
  end if;
  if public.gauntlet_wl(me.season_week, me.account_id) <> array[me.gw, me.gl] then
    update public.gauntlet_queue set status = 'expired', updated_at = now() where id = me.id;
    return;                                   -- 账本变了（这一行的格子过时了）⇒ 让客户端按新战绩重新排
  end if;
  -- 本格子里心跳断了的 ⇒ expired（skip locked：正被它自己的 poll 刷新的那一行不碰，免得互等）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
                   and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_ex := public.referee_gauntlet_opp_ex(me.account_id, me.season_week);
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
   order by x.joined_at, x.id
   limit 1
   for update skip locked;
  if found then
    -- 先来的当 A（左方）
    if (o.joined_at, o.id) < (me.joined_at, me.id) then
      qa := o; qb := me;
    else
      qa := me; qb := o;
    end if;
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
        a_account, b_account, a_snapshot, b_snapshot, level, meta)
      values ('gauntlet', format('gpair:%s:%s:%s', me.season_week, qa.id, qb.id), me.season_week, qa.client_version,
        public.referee_new_seed(), qa.account_id, qb.account_id, qa.snapshot, qb.snapshot,
        public.referee_level_of(qa.snapshot),
        jsonb_build_object('pair', true, 'account', qa.account_id, 'gw0', qa.gw, 'gl0', qa.gl,
                           'opp', qb.account_id::text, 'pick', 'pair', 'rules_ver', qa.rules_ver,
                           'queue_a', qa.id, 'queue_b', qb.id))
      returning job_id into jid;
    update public.gauntlet_queue
       set status = 'paired', job_id = jid, side = case when id = qa.id then 'a' else 'b' end,
           paired_at = now(), updated_at = now()
     where id in (qa.id, qb.id);
    return;
  end if;
  -- 兜底：真人等满 90 秒 ⇒ 机器人池快照，b_account 空、只记真人一边（= 旧路机器人局同一种任务）。陪练号不走兜底。
  if now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
     or exists (select 1 from public.bot_accounts b where b.account_id = me.account_id) then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      public.referee_new_seed(), me.account_id, null, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id))
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;

-- ③ 客户端 RPC ──────────────────────────────────────────────
-- 锁阵容排队。闸与 referee_gauntlet_start 同一组、同一顺序、同一组 reason：
--   not_signed_in / off / update_required / wrong_week / closed / bad_snapshot / finished(gw, gl) / stale(gw, gl)。
--   版本：p_client_version 缺省取请求头 X-Client-Version；规则版本以 referee_versions 登记的为准（p_rules_ver 给了就必须相等）。
-- 有一场在算（配对局里我是 A 或 B / 兜底局 / 旧路）⇒ 回那一场（status 'paired' + in_flight），不再排。
-- 写或刷新我的 waiting（刷新不重新计时），然后当场找对手；回包见 gauntlet_queue_view。
create or replace function public.gauntlet_queue_join(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; v_gw int := 0; v_gl int := 0;
        ex record; v_id bigint;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.gauntlet_window_open(p_week) then
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
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    select id into v_id from public.gauntlet_queue where job_id = ex.job_id and account_id = uid order by id desc limit 1;
    if v_id is not null then
      return public.gauntlet_queue_view(v_id) || jsonb_build_object('in_flight', true);
    end if;
    return jsonb_build_object('ok', true, 'status', 'paired', 'in_flight', true, 'gw', v_gw, 'gl', v_gl,
      'waited_sec', 0, 'job_id', ex.job_id, 'match_id', ex.match_id, 'job_status', ex.status,
      'side', case when ex.a_account = uid then 'a' else 'b' end,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end));
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- 我自己那条心跳断了的旧 waiting ⇒ expired（重新排、重新计时）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where season_week = p_week and account_id = uid and status = 'waiting'
     and last_seen < now() - make_interval(secs => public.gauntlet_queue_ttl_sec());
  insert into public.gauntlet_queue (season_week, account_id, gw, gl, rules_ver, client_version, snapshot)
    values (p_week, uid, v_gw, v_gl, v_rv, v_cv, p_snapshot)
    on conflict (season_week, account_id) where status = 'waiting' do update
      set gw = excluded.gw, gl = excluded.gl, rules_ver = excluded.rules_ver, client_version = excluded.client_version,
          snapshot = excluded.snapshot, last_seen = now(), updated_at = now()
    returning id into v_id;
  perform public.gauntlet_queue_advance(v_id);
  return public.gauntlet_queue_view(v_id);
end $$;
revoke all on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) to authenticated;

-- 心跳 + 查状态（客户端每 2 秒一次）。看的是我本周最新的那一条排队行：
--   waiting：心跳断了超过 15 秒 ⇒ expired；闯关赛关了 ⇒ expired（reason 'closed'）；否则刷新心跳、再试着配一次（含 90 秒兜底）。
--   回包见 gauntlet_queue_view；一条都没有 ⇒ {ok, status:'none', gw, gl}（账本上的数）。
create or replace function public.gauntlet_queue_poll(p_week bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q public.gauntlet_queue%rowtype; w int[];
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into q from public.gauntlet_queue where season_week = p_week and account_id = uid order by id desc limit 1;
  if not found then
    w := public.gauntlet_wl(p_week, uid);
    return jsonb_build_object('ok', true, 'status', 'none', 'gw', w[1], 'gl', w[2]);
  end if;
  if q.status = 'waiting' then
    if q.last_seen < now() - make_interval(secs => public.gauntlet_queue_ttl_sec()) then
      update public.gauntlet_queue set status = 'expired', updated_at = now() where id = q.id and status = 'waiting';
      return public.gauntlet_queue_view(q.id);
    end if;
    if not public.referee_gauntlet_on() or not public.gauntlet_window_open(p_week)
       or p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
      update public.gauntlet_queue set status = 'expired', updated_at = now() where id = q.id and status = 'waiting';
      return public.gauntlet_queue_view(q.id) || jsonb_build_object('reason', 'closed');
    end if;
    update public.gauntlet_queue set last_seen = now() where id = q.id and status = 'waiting';
    perform public.gauntlet_queue_advance(q.id);
  end if;
  return public.gauntlet_queue_view(q.id);
end $$;
revoke all on function public.gauntlet_queue_poll(bigint) from public, anon;
grant execute on function public.gauntlet_queue_poll(bigint) to authenticated;

-- 取消排队：waiting ⇒ cancelled（阵容解锁）。已经配上（paired / done）⇒ {ok:false, reason:'paired', job_id, side, match_id}
--   （那一局照样算、照样记，与「杀进程不作废」一致）。没有在排 ⇒ {ok:true, status:'none'}。
create or replace function public.gauntlet_queue_cancel(p_week bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_id bigint; q public.gauntlet_queue%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  update public.gauntlet_queue set status = 'cancelled', updated_at = now()
   where season_week = p_week and account_id = uid and status = 'waiting'
  returning id into v_id;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'status', 'cancelled');
  end if;
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into q from public.gauntlet_queue where season_week = p_week and account_id = uid order by id desc limit 1;
  if found and q.status in ('paired', 'done') then
    return jsonb_build_object('ok', false, 'reason', 'paired', 'job_id', q.job_id, 'side', q.side,
      'match_id', (select j.match_id from public.referee_jobs j where j.job_id = q.job_id));
  end if;
  return jsonb_build_object('ok', true, 'status', 'none');
end $$;
revoke all on function public.gauntlet_queue_cancel(bigint) from public, anon;
grant execute on function public.gauntlet_queue_cancel(bigint) to authenticated;

-- ④ 服务 RPC（service_role：裁判机上的陪练号调度器）──────────────────
-- 本周交过手的账号（uuid 文本；不含机器人池 'bot:…'）。两个方向都算：我打过的（排除表）+ 打过我快照的（旧路）。
create or replace function public.gauntlet_opponents(p_week bigint, p_uid uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x order by x), '{}')
    from (select unnest(public.referee_gauntlet_opp_ex(p_uid, p_week)) as x
          union all
          select j.a_account::text from public.referee_jobs j
           where j.kind = 'gauntlet' and j.season_week = p_week and j.meta->>'opp' = p_uid::text) e
   where x is not null and x !~ '^bot:'
$$;
revoke all on function public.gauntlet_opponents(bigint, uuid) from public, anon, authenticated;

-- 回 {ok, now, close_at, open_at, now_ts, close_ts, gauntlet_on, any_day, ttl_sec, fallback_sec, waiting, playing, bots}
--   waiting：排队里 15 秒内有心跳的条目，真人和陪练号都在（is_bot 标出；调度器按 bots 名单也认得出）
--            [{account_id, gw, gl, waited_sec, seen_sec, client_version, is_bot, opponents}]
--   playing：已配上、那一局还在算的排队行 [{account_id, gw, gl, job_id, side, is_bot}]
--   bots：bot_accounts 里每个号 [{account_id, gw, gl, in_job, waiting, busy, finished, promoted, last_played_at, opponents}]
--     in_job = 有一场闯关在算；waiting = 正在排队（15 秒内有心跳）；busy = in_job 或 waiting；
--     finished = 4 胜 / 3 负 / 满 6 场；promoted = 本周 battles 最大那份积分赛快照（ghosts）的 season_wins ≥ 11（= PROMOTE_WINS）；
--     last_played_at = 本周最近一局闯关结果写回（status done）的 epoch 秒（没打过 = null）。
--   opponents = gauntlet_opponents（本周交过手的账号）。时刻：now / close_at / open_at 是 timestamptz，另给 now_ts / close_ts epoch 秒。
-- ★读之前先把本周心跳断了的 waiting 置 expired（与 poll 同一条线）。
create or replace function public.gauntlet_service_state(p_week bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cfg record; v_ttl interval; v_now timestamptz; v_close timestamptz;
begin
  select * into cfg from public.referee_config where id = 1;
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = p_week and x.status = 'waiting' and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_now := public.app_now();
  v_close := to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800);
  return jsonb_build_object('ok', true, 'now', v_now, 'close_at', v_close,
    'open_at', to_timestamp(p_week + 5 * 86400),
    'now_ts', floor(extract(epoch from v_now))::bigint, 'close_ts', floor(extract(epoch from v_close))::bigint,
    'gauntlet_on', coalesce(cfg.gauntlet_on, false), 'any_day', coalesce(cfg.gauntlet_any_day, false),
    'ttl_sec', public.gauntlet_queue_ttl_sec(), 'fallback_sec', public.gauntlet_queue_fallback_sec(),
    'waiting', (select coalesce(jsonb_agg(jsonb_build_object(
                  'account_id', q.account_id, 'gw', q.gw, 'gl', q.gl,
                  'waited_sec', greatest(0, floor(extract(epoch from now() - q.joined_at)))::int,
                  'seen_sec', greatest(0, floor(extract(epoch from now() - q.last_seen)))::int,
                  'client_version', q.client_version,
                  'is_bot', exists (select 1 from public.bot_accounts b where b.account_id = q.account_id),
                  'opponents', to_jsonb(public.gauntlet_opponents(p_week, q.account_id))) order by q.joined_at, q.id), '[]'::jsonb)
                  from public.gauntlet_queue q
                 where q.season_week = p_week and q.status = 'waiting' and q.last_seen >= now() - v_ttl),
    'playing', (select coalesce(jsonb_agg(jsonb_build_object(
                  'account_id', q.account_id, 'gw', q.gw, 'gl', q.gl, 'job_id', q.job_id, 'side', q.side,
                  'is_bot', exists (select 1 from public.bot_accounts b where b.account_id = q.account_id))
                  order by q.paired_at, q.id), '[]'::jsonb)
                  from public.gauntlet_queue q join public.referee_jobs j on j.job_id = q.job_id
                 where q.season_week = p_week and q.status = 'paired' and j.status in ('pending', 'claimed')),
    'bots', (select coalesce(jsonb_agg(jsonb_build_object(
               'account_id', s.account_id, 'gw', s.w[1], 'gl', s.w[2],
               'in_job', s.ij, 'waiting', s.wt, 'busy', s.ij or s.wt,
               'finished', s.w[1] >= 4 or s.w[2] >= 3 or s.w[1] + s.w[2] >= 6,
               'promoted', coalesce(s.sw, 0) >= 11,
               'last_played_at', floor(extract(epoch from s.lp))::bigint,
               'opponents', to_jsonb(public.gauntlet_opponents(p_week, s.account_id))) order by s.account_id), '[]'::jsonb)
               from (select b.account_id,
                            public.gauntlet_wl(p_week, b.account_id) as w,
                            public.gauntlet_in_job(p_week, b.account_id) as ij,
                            exists (select 1 from public.gauntlet_queue q
                                     where q.season_week = p_week and q.account_id = b.account_id
                                       and q.status = 'waiting' and q.last_seen >= now() - v_ttl) as wt,
                            (select g.season_wins from public.ghosts g
                              where g.account_id = b.account_id and g.season_week = p_week
                              order by g.battles desc, g.uploaded_at desc limit 1) as sw,
                            (select max(j.done_at) from public.referee_jobs j
                              where j.kind = 'gauntlet' and j.season_week = p_week and j.status = 'done'
                                and (j.a_account = b.account_id
                                     or (j.b_account = b.account_id and j.meta->>'pair' = 'true'))) as lp
                       from public.bot_accounts b) s));
end $$;
revoke all on function public.gauntlet_service_state(bigint) from public, anon, authenticated;
grant execute on function public.gauntlet_service_state(bigint) to service_role;

-- ⑤ 重定义的现行函数 ───────────────────────────────────────

-- 旧路开打（以 20261026b 版为底；★2026-10-27 只改「在算的那场」那一段：配对局里我是 B 也算，对手卡给 A 那一侧）
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
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 00:00 ~ 周日 17:30（周锚点 + 5 天 ~ + 6 天 17:30；2026-10-26 起，原为周六一整天；UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800)) then
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
  -- ★2026-10-27 在线瑞士轮：配对局（meta.pair）里我是 B 也算「在算的那场」，对手卡给 A 那一侧。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人，不是在场的人。
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end),
      'gw', v_gw, 'gl', v_gl);
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

-- 写回（以 20261026b 版为底；★2026-10-27 改四处，旧路任务逐字不变）：
--   ① 配对局（meta.pair）B 那一边照 A 的写法记：战绩互反 / 快照池 / 第 4 胜报名；账本多 gw_b / gl_b（res，也进 matches.result）
--   ② matches.right_account：配对局填 B（真人或陪练号都是真账号，填了不露馅；机器人池对手仍是 null）
--   ③ 账本 coins_b：周日决赛 + 配对局
--   ④ 这一局配出来的排队行 ⇒ done（旧路任务没有排队行）
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
        v_pair boolean; v_gw_b int; v_gl_b int;           -- 2026-10-27 在线瑞士轮
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
  -- ★2026-10-27 在线瑞士轮：配对局（gauntlet_queue 配出来的，meta.pair）两边都是在场的账号 ⇒ 两边都记。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人（20261020c 起真人快照填账号），不是在场的人。
  v_pair := j.kind = 'gauntlet' and coalesce(j.meta->>'pair', '') = 'true';
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
    -- ★2026-10-26 第 4 胜由服务端直接登记决赛报名（= phase2_config.GAUNTLET_WINS_IN；同 finals_enter 的 floor_wins）。
    --   闯关赛延到周日 17:30、分桶 18:00 只剩 30 分钟；原来只靠客户端结算后 / 开主菜单时报名，第 4 胜结算晚或玩家关了游戏
    --   ⇒ 18:00 后才报 ⇒ already_seated，错过决赛。客户端那两条留作兜底（finals_enter 同一张表、幂等 upsert）。
    --   已经有人报过（客户端先到）就不动它；桶已坐定就不再塞人（与 finals_enter 同一条）。
    if v_gw >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.a_account, coalesce(nullif(j.a_snapshot->'profile'->>'name', ''), '?'), j.a_snapshot, v_gw, v_gl)
        on conflict (season_week, account_id) do nothing;
    end if;
  end if;
  -- ★2026-10-27 配对局 B 那一边（胜负与 A 互反）：战绩账本 / 快照池 / 第 4 胜报名，与上面 A 的写法逐条相同。
  --   B 删号了（b_account 随删号断开）⇒ 只记 A。
  if v_pair and j.b_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.b_account, case when won then 0 else 1 end, case when won then 1 else 0 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw_b, v_gl_b;
    res := res || jsonb_build_object('gw_b', v_gw_b, 'gl_b', v_gl_b);
    v_rv := coalesce(v_rv,
                     case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.b_account, j.season_week, v_gw_b, v_gl_b, j.b_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
    if v_gw_b >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.b_account, coalesce(nullif(j.b_snapshot->'profile'->>'name', ''), '?'), j.b_snapshot, v_gw_b, v_gl_b)
        on conflict (season_week, account_id) do nothing;
    end if;
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  -- ★2026-10-27 配对局 right_account = B（真人或陪练号，都是真账号，填了不露馅）；旧路 / 机器人池兜底仍是 null
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' or v_pair then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  -- ★2026-10-27 这一局配出来的排队行（配对局两行 / 兜底局一行）⇒ done。旧路任务没有排队行，这一句什么都不改。
  update public.gauntlet_queue set status = 'done', updated_at = now() where job_id = p_job_id and status = 'paired';
  -- ★2026-10-20d 周日任务的账本多一个 coins_b（右方 B 的战斗内铸币；周六不记）
  --   ★2026-10-27 配对局也记（B 的战斗内铸币，B 查 referee_job_status 时回给它）
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins)
                  || case when j.kind = 'finals' or v_pair then jsonb_build_object('coins_b', v_coins_b) else '{}'::jsonb end)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- 查一局算完没有（以 20261023 版为底；★2026-10-27 配对局的 B 也能查，回包按 B 的视角；A 的回包对旧路任务逐字不变）
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
              then jsonb_build_object('incense', j.result->'incense_b') else '{}'::jsonb end;
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
    -- 2026-10-27：配对局多回一个 side（旧路任务一个键都不多）
    || case when j.kind = 'gauntlet' and j.meta->>'pair' = 'true' then jsonb_build_object('side', 'a') else '{}'::jsonb end;
end $$;
revoke all on function public.referee_job_status(bigint) from public, anon;
grant execute on function public.referee_job_status(bigint) to authenticated;

-- ⑥ 清理：排队行留 14 天（任务行 referee_purge 也是 14 天）。每天 04:45 UTC。
select cron.unschedule(jobid) from cron.job where jobname = 'gauntlet_queue_purge';
select cron.schedule('gauntlet_queue_purge', '45 4 * * *',
  'delete from public.gauntlet_queue where joined_at < now() - interval ''14 days''');
-- <<< END gauntlet_online_queue 20261027 <<<

-- >>> BEGIN gauntlet_live_paired 20261027b >>>
-- ─────────────────────────────────────────────────────────────
-- 两件小事（2026-10-27 · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md · 接 20261027_gauntlet_online_queue）
-- 一、赛况板直播签也标配对局的 B
--   在线排队配上的那一局两边都是在场打的账号，但 referee_live_gauntlet 的行里看不出这一点 ⇒ 赛况板只给左边（A）亮「直播」。
--   本段只重定义 referee_live_gauntlet（以 20261021 版为底，其余逐字照抄）：每行多一个 `paired`（布尔，= 任务 meta.pair）。
--   B 那一侧的标识不另加：行里的 `rp` 本来就是 b_snapshot.profile 的 name / avatar / id / tag，
--     客户端 gauntlet_board.gd 的 mark_live 按 tag_of(rp)（= Backend.profile_tag，#ID 优先、退回 id）认人；
--     不回账号 uuid（客户端不用，也不多给所有登录用户一个字段）。
--   ★只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人（不在场），机器人池局 b_account 空 —— 两种都是 false。
--   ★老客户端不认识 `paired`，多一个键无害（parse_live 原样透传、live_games 只读它认识的键）。
-- 二、收盘前 11 分钟当场兜底（调度器推演发现）
--   陪练号客户端起一个要 40~60 秒 ⇒ 调度器 17:19 起不再拉号；17:19 之后才进队的真人配不到陪练号，只能等 90 秒兜底，
--   而 17:30 一到排队行就 expired（closed）⇒ 17:28 进来的人白等、再被告知「不在闯关赛时段」。
--   改：重定义 gauntlet_queue_advance（以 20261027 版为底，只改兜底那个 if）：离收盘 ≤ 11 分钟（app_now，与收盘闸同一把钟）时，
--     没配上同格子的在线对手（真人或陪练号，配对那一步照旧在前）⇒ 当场退回机器人池，不等 90 秒。陪练号照旧不兜底。
--   11 分钟 = gauntlet_queue_close_rush_sec()（660）；收盘时刻与 gauntlet_window_open / referee_gauntlet_start 同一个式子。
--   ★内测服开着 gauntlet_any_day 时，周日 17:19 之后到周一前整段都算「收盘前」⇒ 一律当场兜底（只影响内测服彩排）。
-- 上线步骤（tools/sb_migrate.py 标准路径；必须排在 20261027_gauntlet_online_queue 之后——它才有排队表 / meta.pair 的任务）：
--   sandbox → beta --rehearse → beta --apply → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
-- 回滚：referee_live_gauntlet 换回 20261021 版（客户端读不到 paired ⇒ 当 false）；
--   gauntlet_queue_advance 换回 20261027 版（回到一律等 90 秒）。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_live_gauntlet()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg record; wk bigint; v jsonb;
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;
  select * into cfg from public.referee_config where id = 1;
  wk := extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint;
  select coalesce(jsonb_agg(jsonb_build_object(
           'match_id', j.match_id, 'started_at', j.claimed_at, 'updated_at', now(),
           'client_version', j.client_version, 'seed', j.seed,
           -- 2026-10-27b：在线排队配上的那一局（meta.pair）右边也是在场打的人 ⇒ 赛况板直播签两边都标（B 那一侧按 rp 里的 #ID 认）
           'paired', coalesce(j.meta->>'pair', '') = 'true',
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

-- 离收盘多少秒以内「没配上就当场兜底」（= 调度器停止拉新号的提前量：收盘前 10 分钟停 + 起号 40~60 秒）
create or replace function public.gauntlet_queue_close_rush_sec() returns int
language sql immutable as $$ select 660 $$;
revoke all on function public.gauntlet_queue_close_rush_sec() from public, anon, authenticated;

-- 推一条 waiting 往前走（以 20261027 版为底；★2026-10-27b 只改兜底那个 if：收盘前 11 分钟起没配上就当场兜底）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int;
begin
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  select * into me from public.gauntlet_queue where id = p_id;
  if not found or me.status <> 'waiting' then
    return;
  end if;
  perform pg_advisory_xact_lock(20261027, hashtext(format('gauntlet_cell:%s:%s:%s', me.season_week, me.gw, me.gl)));
  select * into me from public.gauntlet_queue where id = p_id for update;
  if me.status <> 'waiting' or me.last_seen < now() - v_ttl then
    return;                                   -- 锁到手时已经被别人配走 / 自己心跳断了
  end if;
  if public.gauntlet_in_job(me.season_week, me.account_id) then
    return;                                   -- 还有一场在算 ⇒ 先不配
  end if;
  if public.gauntlet_wl(me.season_week, me.account_id) <> array[me.gw, me.gl] then
    update public.gauntlet_queue set status = 'expired', updated_at = now() where id = me.id;
    return;                                   -- 账本变了（这一行的格子过时了）⇒ 让客户端按新战绩重新排
  end if;
  -- 本格子里心跳断了的 ⇒ expired（skip locked：正被它自己的 poll 刷新的那一行不碰，免得互等）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
                   and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_ex := public.referee_gauntlet_opp_ex(me.account_id, me.season_week);
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
   order by x.joined_at, x.id
   limit 1
   for update skip locked;
  if found then
    -- 先来的当 A（左方）
    if (o.joined_at, o.id) < (me.joined_at, me.id) then
      qa := o; qb := me;
    else
      qa := me; qb := o;
    end if;
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
        a_account, b_account, a_snapshot, b_snapshot, level, meta)
      values ('gauntlet', format('gpair:%s:%s:%s', me.season_week, qa.id, qb.id), me.season_week, qa.client_version,
        public.referee_new_seed(), qa.account_id, qb.account_id, qa.snapshot, qb.snapshot,
        public.referee_level_of(qa.snapshot),
        jsonb_build_object('pair', true, 'account', qa.account_id, 'gw0', qa.gw, 'gl0', qa.gl,
                           'opp', qb.account_id::text, 'pick', 'pair', 'rules_ver', qa.rules_ver,
                           'queue_a', qa.id, 'queue_b', qb.id))
      returning job_id into jid;
    update public.gauntlet_queue
       set status = 'paired', job_id = jid, side = case when id = qa.id then 'a' else 'b' end,
           paired_at = now(), updated_at = now()
     where id in (qa.id, qb.id);
    return;
  end if;
  -- 兜底：真人等满 90 秒 ⇒ 机器人池快照，b_account 空、只记真人一边（= 旧路机器人局同一种任务）。陪练号不走兜底。
  --   ★2026-10-27b 收盘前 11 分钟起（陪练号客户端起一个要 40~60 秒，调度器 17:19 起不再拉号）：上面没配上同格子的
  --     在线对手 ⇒ 当场兜底、不等 90 秒（否则 17:28 进来的人等不满 90 秒就到 17:30 收盘，白等一场还被告知不在时段）。
  if (now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
      and public.app_now() < to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                             - make_interval(secs => public.gauntlet_queue_close_rush_sec()))
     or exists (select 1 from public.bot_accounts b where b.account_id = me.account_id) then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      public.referee_new_seed(), me.account_id, null, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id))
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_live_paired 20261027b <<<
-- >>> BEGIN gauntlet_old_client_gate 20261029 >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛旧客户端闸（2026-10-29 · 接 20261027_gauntlet_online_queue / 20261027b · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2「版本」）
--   用户 10-29 选方案 ②（「行」）：周六只收在线排队的新客户端，旧客户端给一句明确的「需要更新」，平日照常。
--   内测服 10-29 实测（0.22.2 客户端，假周六）：
--     · 不加闸：旧入口 referee_gauntlet_start 照旧当场配一份快照、只记旧客户端这一边 —— 不进在线排队，「两边各算各的」照旧；
--     · 关掉 referee_versions 里的 0.22.2：回 39 字的 update_required ⇒ 0.22.2 弹整屏墙「需要更新 / 当前版本已停止服务……
--       当前版本 0.22.2 · 最低版本 0.21.3」，挡住匹配屏的「←」，要重开 App 才撤；还连带挡掉它旧录像的补流。
--   本段：只改 referee_gauntlet_start 一处 —— 过了「时段 / 阵容 / 已打完 / 在算的那场 / 账本对齐」之后、建任务之前，
--     客户端版本 < gauntlet_queue_min_client()（0.22.3，在线排队的第一个客户端版本）⇒ 回 update_required（补到 600 字以上）。
--     版本比较用现成的 semver_arr（数字逐段比，0.22.10 > 0.22.3）。其余逐字照抄 20261027 版。
--   不动：referee_versions（0.22.2 的旧录像补流照常）、min_client_version（平日照常）、积分赛与在线排队的任何函数。
--   ★0.22.3 起的客户端不调本函数（客户端线 10-27 删掉了旧入口调用）⇒ 对它们没有可见变化。
-- 上线步骤（tools/sb_migrate.py 标准路径；必须排在 20261027_gauntlet_online_queue 之后 —— 本段以它的 referee_gauntlet_start 为底）：
--   sandbox → beta --rehearse → beta --apply → prod --precheck → prod --rehearse → prod --apply（要 --yes-prod）
-- 回滚：referee_gauntlet_start 换回 20261027 版（gauntlet_queue_min_client 留着无害）。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

-- 在线排队协议的第一个客户端版本（= CHANGELOG 0.22.3「闯关赛改为在线匹配」）。低于它的客户端周六不再开新局。
create or replace function public.gauntlet_queue_min_client() returns text
language sql immutable as $$ select '0.22.3' $$;
revoke all on function public.gauntlet_queue_min_client() from public, anon, authenticated;

-- 旧路开打（以 20261027 版为底；★2026-10-29 只加「旧客户端闸」一段，见函数体里 ★2026-10-29 那几行）
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
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  -- 周六 00:00 ~ 周日 17:30（周锚点 + 5 天 ~ + 6 天 17:30；2026-10-26 起，原为周六一整天；UTC，E2 拍板赛程一律 UTC）
  if not cfg.gauntlet_any_day and not (public.app_now() >= to_timestamp(p_week + 5 * 86400) and public.app_now() < to_timestamp(p_week + 6 * 86400 + 17 * 3600 + 1800)) then
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
  -- ★2026-10-27 在线瑞士轮：配对局（meta.pair）里我是 B 也算「在算的那场」，对手卡给 A 那一侧。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人，不是在场的人。
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end),
      'gw', v_gw, 'gl', v_gl);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- ★2026-10-29 旧客户端闸（迁移 20261029）：闯关赛改成在线排队后，0.22.3 起的客户端走 gauntlet_queue_join、不再调本函数；
  --   低于 gauntlet_queue_min_client() 的客户端在这里停下 —— 不建任务、不重交失败的那一场，回 update_required。
  --   回包补到 600 字以上（pad）：0.22.2 把「≤512 字且含 "update_required"」的回包当成整个版本停服，弹整屏「需要更新」墙
  --   （它的 version_gate.gd is_update_required_response），可它平日积分赛照常能打；补长之后它只在匹配屏写一行
  --   「版本过旧，请更新」，左上「←」能回主菜单。放在「在算的那场 / 账本对齐」之后：切换前交上去的那一场照样能查到、补记。
  if coalesce(public.semver_arr(p_client_version), array[0, 0, 0, 0]) < public.semver_arr(public.gauntlet_queue_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required', 'min_version', public.gauntlet_queue_min_client(),
      'pad', repeat('-', 600));
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
-- <<< END gauntlet_old_client_gate 20261029 <<<

-- >>> BEGIN gauntlet_fallback_real_first 20261029b >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛在线排队的兜底改「先真人快照、再机器人池」+ 等 3 分钟（2026-10-29 · 接 20261027 / 20261027b / 20261029 ·
--   方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2）
--   用户 10-29「等满 90 秒没人就退回机器人阵容快照？也不应该是优先真人的快照吗，但可以多等啊，3分钟？」
--   ① gauntlet_queue_fallback_sec 90 → 180（调度器 / 状态回包 fallback_sec 跟着变；客户端没有写死这个数）
--   ② gauntlet_queue_advance 以 20261027b 版为底，只改兜底那一段：先挑同格子真人闯关快照（真人号先于陪练号，30 分钟内先），
--      没有再机器人池；挑到真人快照时 b_account = 快照主人（同旧路），meta 不带 pair ⇒ 只记真人一边。配对那一段逐字不动。
--   ★20261027 / 27b 检查脚本里「90 秒兜底」「兜底 = 机器人池」那几条只对它们那一刻成立；本段之后以本段检查脚本为准。
-- ─────────────────────────────────────────────────────────────
create or replace function public.gauntlet_queue_fallback_sec() returns int
language sql immutable as $$ select 180 $$;
revoke all on function public.gauntlet_queue_fallback_sec() from public, anon, authenticated;

-- 推一条 waiting 往前走（以 20261027b 版为底；★20261029b 只改兜底：先真人快照、再机器人池，b_account = 快照主人）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int; g record;
begin
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  select * into me from public.gauntlet_queue where id = p_id;
  if not found or me.status <> 'waiting' then
    return;
  end if;
  perform pg_advisory_xact_lock(20261027, hashtext(format('gauntlet_cell:%s:%s:%s', me.season_week, me.gw, me.gl)));
  select * into me from public.gauntlet_queue where id = p_id for update;
  if me.status <> 'waiting' or me.last_seen < now() - v_ttl then
    return;                                   -- 锁到手时已经被别人配走 / 自己心跳断了
  end if;
  if public.gauntlet_in_job(me.season_week, me.account_id) then
    return;                                   -- 还有一场在算 ⇒ 先不配
  end if;
  if public.gauntlet_wl(me.season_week, me.account_id) <> array[me.gw, me.gl] then
    update public.gauntlet_queue set status = 'expired', updated_at = now() where id = me.id;
    return;                                   -- 账本变了（这一行的格子过时了）⇒ 让客户端按新战绩重新排
  end if;
  -- 本格子里心跳断了的 ⇒ expired（skip locked：正被它自己的 poll 刷新的那一行不碰，免得互等）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
                   and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_ex := public.referee_gauntlet_opp_ex(me.account_id, me.season_week);
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
   order by x.joined_at, x.id
   limit 1
   for update skip locked;
  if found then
    -- 先来的当 A（左方）
    if (o.joined_at, o.id) < (me.joined_at, me.id) then
      qa := o; qb := me;
    else
      qa := me; qb := o;
    end if;
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
        a_account, b_account, a_snapshot, b_snapshot, level, meta)
      values ('gauntlet', format('gpair:%s:%s:%s', me.season_week, qa.id, qb.id), me.season_week, qa.client_version,
        public.referee_new_seed(), qa.account_id, qb.account_id, qa.snapshot, qb.snapshot,
        public.referee_level_of(qa.snapshot),
        jsonb_build_object('pair', true, 'account', qa.account_id, 'gw0', qa.gw, 'gl0', qa.gl,
                           'opp', qb.account_id::text, 'pick', 'pair', 'rules_ver', qa.rules_ver,
                           'queue_a', qa.id, 'queue_b', qb.id))
      returning job_id into jid;
    update public.gauntlet_queue
       set status = 'paired', job_id = jid, side = case when id = qa.id then 'a' else 'b' end,
           paired_at = now(), updated_at = now()
     where id in (qa.id, qb.id);
    return;
  end if;
  -- 兜底：真人等满 gauntlet_queue_fallback_sec（★20261029b 起 180 秒）⇒ 先同格子真人快照、没有再机器人池；只记真人一边。陪练号不走兜底。
  --   ★2026-10-27b 收盘前 11 分钟起（陪练号客户端起一个要 40~60 秒，调度器 17:19 起不再拉号）：上面没配上同格子的
  --     在线对手 ⇒ 当场兜底、不等 90 秒（否则 17:28 进来的人等不满 90 秒就到 17:30 收盘，白等一场还被告知不在时段）。
  if (now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
      and public.app_now() < to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                             - make_interval(secs => public.gauntlet_queue_close_rush_sec()))
     or exists (select 1 from public.bot_accounts b where b.account_id = me.account_id) then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  -- ★20261029b ① 同格子真人快照（本周闯关上传的、同战绩、同 rules_ver、跑得起来；排除自己与本周交过手的）：
  --   真人号优先于陪练号（bot_accounts），30 分钟内上传的优先（= referee_gauntlet_pick 的 FRESH 窗口），再随机。
  --   用户 10-29「也不应该是优先真人的快照吗，但可以多等啊，3分钟？」
  select gg.account_id, gg.snapshot, gg.uploaded_at into g
    from public.gauntlet_ghosts gg
   where gg.season_week = me.season_week and gg.gw = me.gw and gg.gl = me.gl and gg.rules_ver = me.rules_ver
     and gg.account_id <> me.account_id and not (gg.account_id::text = any(v_ex))
     and public.referee_lanes_ok(gg.snapshot)
   order by (not exists (select 1 from public.bot_accounts b where b.account_id = gg.account_id)) desc,
            (gg.uploaded_at > now() - make_interval(secs => 1800)) desc, random()
   limit 1;
  if found then
    pk := jsonb_build_object('snap', g.snapshot - 'origin', 'opp', g.account_id::text, 'account', g.account_id,
      'pick', case when g.uploaded_at > now() - make_interval(secs => 1800) then 'fresh' else 'stale' end);
  else
    -- ② 机器人池（原样）
    pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  end if;
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      -- b_account = 被打的那份快照的主人（同旧路 referee_gauntlet_start；不在场、meta 不带 pair ⇒ 只记真人一边）；机器人池 = 空
      public.referee_new_seed(), me.account_id, (pk->>'account')::uuid, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id))
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_fallback_real_first 20261029b <<<

-- >>> BEGIN gauntlet_human_first_minute 20261029c >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛在线排队：真人进队前 1 分钟只配在线真人（2026-10-29 · 接 20261029b · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.2）
--   用户 10-29 看了三种顺序后选 C：「前 1 分钟只配在线真人；1 分钟后拉陪练号；陪练号也没有再拿真人快照，最后是系统阵容」
--   ① gauntlet_queue_human_only_sec() = 60
--   ② gauntlet_queue_advance 以 20261029b 版为底，只改「找同格子在线对手」那一段（规则见函数里注释）；配上之后建任务、兜底两段逐字不动。
--   调度器（gauntlet_bot_planner.py）照旧真人一在等就拉号（起号 40~60 秒 ⇒ 正好 1 分钟前后到）；推演门禁 tools/gauntlet_planner_audit.py 同口径建模。
-- ─────────────────────────────────────────────────────────────
create or replace function public.gauntlet_queue_human_only_sec() returns int
language sql immutable as $$ select 60 $$;
revoke all on function public.gauntlet_queue_human_only_sec() from public, anon, authenticated;

-- 推一条 waiting 往前走（以 20261029b 版为底；★20261029c 只改找在线对手：前 1 分钟只配真人、陪练号先留给真人、真人先于陪练号）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int; g record;
        v_rush boolean; v_me_bot boolean; v_fresh int; v_nbot int; v_hold interval;
begin
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  select * into me from public.gauntlet_queue where id = p_id;
  if not found or me.status <> 'waiting' then
    return;
  end if;
  perform pg_advisory_xact_lock(20261027, hashtext(format('gauntlet_cell:%s:%s:%s', me.season_week, me.gw, me.gl)));
  select * into me from public.gauntlet_queue where id = p_id for update;
  if me.status <> 'waiting' or me.last_seen < now() - v_ttl then
    return;                                   -- 锁到手时已经被别人配走 / 自己心跳断了
  end if;
  if public.gauntlet_in_job(me.season_week, me.account_id) then
    return;                                   -- 还有一场在算 ⇒ 先不配
  end if;
  if public.gauntlet_wl(me.season_week, me.account_id) <> array[me.gw, me.gl] then
    update public.gauntlet_queue set status = 'expired', updated_at = now() where id = me.id;
    return;                                   -- 账本变了（这一行的格子过时了）⇒ 让客户端按新战绩重新排
  end if;
  -- 本格子里心跳断了的 ⇒ expired（skip locked：正被它自己的 poll 刷新的那一行不碰，免得互等）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
                   and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_ex := public.referee_gauntlet_opp_ex(me.account_id, me.season_week);
  -- ★20261029c 前 1 分钟只配在线真人（用户 10-29 选 C「前 1 分钟只配在线真人；1 分钟后拉陪练号；陪练号也没有再拿真人快照，最后是系统阵容」）：
  --   真人 × 真人：随时配；真人 × 陪练号：真人那一边进队满 gauntlet_queue_human_only_sec（60 秒）才配；
  --   陪练号 × 陪练号：互配之后这一格剩下的在线陪练号仍 ≥ 还没满 60 秒的在线真人数才配（陪练号先留给他们）；
  --   收盘前 11 分钟起（close_rush）不设这一分钟。挑对手：真人先于陪练号，再先来先配。
  v_rush := public.app_now() >= to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                                 - make_interval(secs => public.gauntlet_queue_close_rush_sec());
  v_hold := make_interval(secs => public.gauntlet_queue_human_only_sec());
  v_me_bot := exists (select 1 from public.bot_accounts b where b.account_id = me.account_id);
  select count(*) filter (where not exists (select 1 from public.bot_accounts b where b.account_id = x.account_id)
                           and x.joined_at > now() - v_hold and not v_rush),
         count(*) filter (where exists (select 1 from public.bot_accounts b where b.account_id = x.account_id) and x.id <> me.id)
    into v_fresh, v_nbot
    from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.last_seen >= now() - v_ttl;
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
     and case
           when v_me_bot = exists (select 1 from public.bot_accounts b where b.account_id = x.account_id) then
             not v_me_bot or v_nbot - 1 >= v_fresh                       -- 真人 × 真人随时；陪练号 × 陪练号要留够给真人
           else
             v_rush or (case when v_me_bot then x.joined_at else me.joined_at end) <= now() - v_hold   -- 真人 × 陪练号
         end
   order by exists (select 1 from public.bot_accounts b where b.account_id = x.account_id), x.joined_at, x.id
   limit 1
   for update skip locked;
  if found then
    -- 先来的当 A（左方）
    if (o.joined_at, o.id) < (me.joined_at, me.id) then
      qa := o; qb := me;
    else
      qa := me; qb := o;
    end if;
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
        a_account, b_account, a_snapshot, b_snapshot, level, meta)
      values ('gauntlet', format('gpair:%s:%s:%s', me.season_week, qa.id, qb.id), me.season_week, qa.client_version,
        public.referee_new_seed(), qa.account_id, qb.account_id, qa.snapshot, qb.snapshot,
        public.referee_level_of(qa.snapshot),
        jsonb_build_object('pair', true, 'account', qa.account_id, 'gw0', qa.gw, 'gl0', qa.gl,
                           'opp', qb.account_id::text, 'pick', 'pair', 'rules_ver', qa.rules_ver,
                           'queue_a', qa.id, 'queue_b', qb.id))
      returning job_id into jid;
    update public.gauntlet_queue
       set status = 'paired', job_id = jid, side = case when id = qa.id then 'a' else 'b' end,
           paired_at = now(), updated_at = now()
     where id in (qa.id, qb.id);
    return;
  end if;
  -- 兜底：真人等满 gauntlet_queue_fallback_sec（★20261029b 起 180 秒）⇒ 先同格子真人快照、没有再机器人池；只记真人一边。陪练号不走兜底。
  --   ★2026-10-27b 收盘前 11 分钟起（陪练号客户端起一个要 40~60 秒，调度器 17:19 起不再拉号）：上面没配上同格子的
  --     在线对手 ⇒ 当场兜底、不等 90 秒（否则 17:28 进来的人等不满 90 秒就到 17:30 收盘，白等一场还被告知不在时段）。
  if (now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
      and public.app_now() < to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                             - make_interval(secs => public.gauntlet_queue_close_rush_sec()))
     or exists (select 1 from public.bot_accounts b where b.account_id = me.account_id) then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  -- ★20261029b ① 同格子真人快照（本周闯关上传的、同战绩、同 rules_ver、跑得起来；排除自己与本周交过手的）：
  --   真人号优先于陪练号（bot_accounts），30 分钟内上传的优先（= referee_gauntlet_pick 的 FRESH 窗口），再随机。
  --   用户 10-29「也不应该是优先真人的快照吗，但可以多等啊，3分钟？」
  select gg.account_id, gg.snapshot, gg.uploaded_at into g
    from public.gauntlet_ghosts gg
   where gg.season_week = me.season_week and gg.gw = me.gw and gg.gl = me.gl and gg.rules_ver = me.rules_ver
     and gg.account_id <> me.account_id and not (gg.account_id::text = any(v_ex))
     and public.referee_lanes_ok(gg.snapshot)
   order by (not exists (select 1 from public.bot_accounts b where b.account_id = gg.account_id)) desc,
            (gg.uploaded_at > now() - make_interval(secs => 1800)) desc, random()
   limit 1;
  if found then
    pk := jsonb_build_object('snap', g.snapshot - 'origin', 'opp', g.account_id::text, 'account', g.account_id,
      'pick', case when g.uploaded_at > now() - make_interval(secs => 1800) then 'fresh' else 'stale' end);
  else
    -- ② 机器人池（原样）
    pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  end if;
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      -- b_account = 被打的那份快照的主人（同旧路 referee_gauntlet_start；不在场、meta 不带 pair ⇒ 只记真人一边）；机器人池 = 空
      public.referee_new_seed(), me.account_id, (pk->>'account')::uuid, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id))
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_human_first_minute 20261029c <<<

-- >>> BEGIN gauntlet_no_bot_early_fallback 20261031 >>>
-- ─────────────────────────────────────────────────────────────
-- 闯关赛在线排队：确定没有陪练号能来 ⇒ 真人进队满 1 分钟就兜底，不再干等 3 分钟
--   （2026-10-31 · 接 20261029c · 方案书 docs/plans/20261031b-闯关赛开局铺号与早兜底.md）
--   用户 10-31「这个匹配不到玩家是什么情况，一分钟之后匹配不到，直到三分钟才匹配到」。
--   正式服实测（周六 00:02 ~ 00:48）：测试号 7 局全部等满 180 秒兜底 —— 那时陪练号全是 0.22.5、真人是 0.22.6，
--   服务端只配同版本 ⇒ 这 7 次从第 1 秒起就注定没有陪练号能来，前 1 分钟（只配真人）之后的 2 分钟是白等。
--   用户 10-29 定的顺序不变：前 1 分钟只配在线真人 → 1 分钟后陪练号 → 再没有才拿真人快照 / 机器人池。本迁移只把
--   「陪练号这一步确定落空」的那种情况的兜底提前到 1 分钟。
--   ① gauntlet_queue.no_bot_at：调度器（gauntlet_bot_planner.py）判「这一条排队没有陪练号能来」的时刻；每拍按它当时的判断置上 / 清掉
--   ② gauntlet_planner_beat：调度器心跳（每拍一次）+ 它拉的陪练号客户端版本
--   ③ gauntlet_planner_mark(p_week, p_no_bot uuid[], p_bot_version)：service_role；写心跳；本周 waiting 的真人条目
--      名单里的置 no_bot_at（已有的不改）、名单外的清掉；陪练号的条目一律不置
--   ④ gauntlet_queue_advance：以 20261029c 版为底，只改兜底的进门条件 —— 真人进队满 gauntlet_queue_human_only_sec（60 秒）且
--      （no_bot_at 有值 或 调度器报过到、但心跳断了 gauntlet_planner_stale_sec 秒）⇒ 当场兜底；其余照旧（180 秒 / 收盘前 11 分钟）。
--      配对一段、兜底取对手一段逐字不动；兜底任务的 meta 多一个 early（'no_bot' / 'planner_gone' / 没有 = 照旧那条线）。陪练号照旧不走兜底。
--   ★心跳那一条只在调度器报过到之后生效（gauntlet_planner_beat 一行都没有 ⇒ 不算断）⇒ 迁移先于新调度器上线时，行为与 20261029c 逐条相同。
-- 回滚：gauntlet_queue_advance 换回 20261029c 版；新列 / 新表 / 新函数留着不影响（没人置 no_bot_at、advance 不读）。
-- ★重复执行安全（if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────
alter table public.gauntlet_queue add column if not exists no_bot_at timestamptz;

create table if not exists public.gauntlet_planner_beat (
  id          int         primary key default 1 check (id = 1),
  seen_at     timestamptz not null default now(),
  bot_version text
);
alter table public.gauntlet_planner_beat enable row level security;
revoke all on table public.gauntlet_planner_beat from anon, authenticated;
grant all on table public.gauntlet_planner_beat to service_role;

-- 调度器心跳断了多久算它不在（秒）。调度器每 10 秒一拍；60 秒 = 连丢 6 拍（重启调度器约 10 秒，不会误判）。
create or replace function public.gauntlet_planner_stale_sec() returns int
language sql immutable as $$ select 60 $$;
revoke all on function public.gauntlet_planner_stale_sec() from public, anon, authenticated;

-- 调度器报过到、但心跳断了 ⇒ 不会再有陪练号被拉来
create or replace function public.gauntlet_planner_gone() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.gauntlet_planner_beat)
     and not exists (select 1 from public.gauntlet_planner_beat
                      where seen_at >= now() - make_interval(secs => public.gauntlet_planner_stale_sec()))
$$;
revoke all on function public.gauntlet_planner_gone() from public, anon, authenticated;

-- 调度器每拍调一次：写心跳；p_no_bot = 它此刻判定「没有陪练号能来」的真人账号（空数组 = 一个都没有 ⇒ 全部清掉）
create or replace function public.gauntlet_planner_mark(p_week bigint, p_no_bot uuid[], p_bot_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n_set int; n_clr int;
begin
  insert into public.gauntlet_planner_beat (id, seen_at, bot_version) values (1, now(), p_bot_version)
    on conflict (id) do update set seen_at = excluded.seen_at, bot_version = excluded.bot_version;
  update public.gauntlet_queue q set no_bot_at = now()
   where q.season_week = p_week and q.status = 'waiting' and q.no_bot_at is null
     and q.account_id = any(coalesce(p_no_bot, '{}'::uuid[]))
     and not exists (select 1 from public.bot_accounts b where b.account_id = q.account_id);
  get diagnostics n_set = row_count;
  update public.gauntlet_queue q set no_bot_at = null
   where q.season_week = p_week and q.status = 'waiting' and q.no_bot_at is not null
     and not (q.account_id = any(coalesce(p_no_bot, '{}'::uuid[])));
  get diagnostics n_clr = row_count;
  return jsonb_build_object('ok', true, 'set', n_set, 'cleared', n_clr);
end $$;
revoke all on function public.gauntlet_planner_mark(bigint, uuid[], text) from public, anon, authenticated;
grant execute on function public.gauntlet_planner_mark(bigint, uuid[], text) to service_role;

-- 推一条 waiting 往前走（以 20261029c 版为底；★20261031 只改兜底的进门条件，见文件头 ④）
create or replace function public.gauntlet_queue_advance(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare me public.gauntlet_queue%rowtype; o public.gauntlet_queue%rowtype; qa public.gauntlet_queue%rowtype;
        qb public.gauntlet_queue%rowtype; v_ttl interval; v_ex text[]; jid bigint; pk jsonb; v_b int; g record;
        v_rush boolean; v_me_bot boolean; v_fresh int; v_nbot int; v_hold interval; v_early text;
begin
  v_ttl := make_interval(secs => public.gauntlet_queue_ttl_sec());
  select * into me from public.gauntlet_queue where id = p_id;
  if not found or me.status <> 'waiting' then
    return;
  end if;
  perform pg_advisory_xact_lock(20261027, hashtext(format('gauntlet_cell:%s:%s:%s', me.season_week, me.gw, me.gl)));
  select * into me from public.gauntlet_queue where id = p_id for update;
  if me.status <> 'waiting' or me.last_seen < now() - v_ttl then
    return;                                   -- 锁到手时已经被别人配走 / 自己心跳断了
  end if;
  if public.gauntlet_in_job(me.season_week, me.account_id) then
    return;                                   -- 还有一场在算 ⇒ 先不配
  end if;
  if public.gauntlet_wl(me.season_week, me.account_id) <> array[me.gw, me.gl] then
    update public.gauntlet_queue set status = 'expired', updated_at = now() where id = me.id;
    return;                                   -- 账本变了（这一行的格子过时了）⇒ 让客户端按新战绩重新排
  end if;
  -- 本格子里心跳断了的 ⇒ expired（skip locked：正被它自己的 poll 刷新的那一行不碰，免得互等）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where id in (select x.id from public.gauntlet_queue x
                 where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
                   and x.last_seen < now() - v_ttl
                   for update skip locked);
  v_ex := public.referee_gauntlet_opp_ex(me.account_id, me.season_week);
  -- ★20261029c 前 1 分钟只配在线真人（用户 10-29 选 C「前 1 分钟只配在线真人；1 分钟后拉陪练号；陪练号也没有再拿真人快照，最后是系统阵容」）：
  --   真人 × 真人：随时配；真人 × 陪练号：真人那一边进队满 gauntlet_queue_human_only_sec（60 秒）才配；
  --   陪练号 × 陪练号：互配之后这一格剩下的在线陪练号仍 ≥ 还没满 60 秒的在线真人数才配（陪练号先留给他们）；
  --   收盘前 11 分钟起（close_rush）不设这一分钟。挑对手：真人先于陪练号，再先来先配。
  v_rush := public.app_now() >= to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                                 - make_interval(secs => public.gauntlet_queue_close_rush_sec());
  v_hold := make_interval(secs => public.gauntlet_queue_human_only_sec());
  v_me_bot := exists (select 1 from public.bot_accounts b where b.account_id = me.account_id);
  select count(*) filter (where not exists (select 1 from public.bot_accounts b where b.account_id = x.account_id)
                           and x.joined_at > now() - v_hold and not v_rush),
         count(*) filter (where exists (select 1 from public.bot_accounts b where b.account_id = x.account_id) and x.id <> me.id)
    into v_fresh, v_nbot
    from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.last_seen >= now() - v_ttl;
  select * into o from public.gauntlet_queue x
   where x.season_week = me.season_week and x.gw = me.gw and x.gl = me.gl and x.status = 'waiting'
     and x.id <> me.id and x.account_id <> me.account_id
     and x.last_seen >= now() - v_ttl
     and x.client_version = me.client_version and x.rules_ver = me.rules_ver     -- 一条任务只有一个版本；两边都要看得了这一局的录像
     and not (x.account_id::text = any(v_ex))
     and not (me.account_id::text = any(public.referee_gauntlet_opp_ex(x.account_id, x.season_week)))
     and not public.gauntlet_in_job(x.season_week, x.account_id)
     and public.gauntlet_wl(x.season_week, x.account_id) = array[x.gw, x.gl]
     and case
           when v_me_bot = exists (select 1 from public.bot_accounts b where b.account_id = x.account_id) then
             not v_me_bot or v_nbot - 1 >= v_fresh                       -- 真人 × 真人随时；陪练号 × 陪练号要留够给真人
           else
             v_rush or (case when v_me_bot then x.joined_at else me.joined_at end) <= now() - v_hold   -- 真人 × 陪练号
         end
   order by exists (select 1 from public.bot_accounts b where b.account_id = x.account_id), x.joined_at, x.id
   limit 1
   for update skip locked;
  if found then
    -- 先来的当 A（左方）
    if (o.joined_at, o.id) < (me.joined_at, me.id) then
      qa := o; qb := me;
    else
      qa := me; qb := o;
    end if;
    insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
        a_account, b_account, a_snapshot, b_snapshot, level, meta)
      values ('gauntlet', format('gpair:%s:%s:%s', me.season_week, qa.id, qb.id), me.season_week, qa.client_version,
        public.referee_new_seed(), qa.account_id, qb.account_id, qa.snapshot, qb.snapshot,
        public.referee_level_of(qa.snapshot),
        jsonb_build_object('pair', true, 'account', qa.account_id, 'gw0', qa.gw, 'gl0', qa.gl,
                           'opp', qb.account_id::text, 'pick', 'pair', 'rules_ver', qa.rules_ver,
                           'queue_a', qa.id, 'queue_b', qb.id))
      returning job_id into jid;
    update public.gauntlet_queue
       set status = 'paired', job_id = jid, side = case when id = qa.id then 'a' else 'b' end,
           paired_at = now(), updated_at = now()
     where id in (qa.id, qb.id);
    return;
  end if;
  -- 兜底：真人等满 gauntlet_queue_fallback_sec（★20261029b 起 180 秒）⇒ 先同格子真人快照、没有再机器人池；只记真人一边。陪练号不走兜底。
  --   ★2026-10-27b 收盘前 11 分钟起（陪练号客户端起一个要 40~60 秒，调度器 17:19 起不再拉号）：上面没配上同格子的
  --     在线对手 ⇒ 当场兜底、不等 90 秒（否则 17:28 进来的人等不满 90 秒就到 17:30 收盘，白等一场还被告知不在时段）。
  --   ★20261031 确定没有陪练号能来 ⇒ 等满只配真人的那 1 分钟就兜底（用户 10-31「一分钟之后匹配不到，直到三分钟才匹配到」）：
  --     调度器把这一条判成没号（no_bot_at）—— 陪练号版本与真人不同 / 这一格和上一级都没有没交过手的号；或调度器报过到、心跳却断了。
  v_early := case
               when v_me_bot or now() - me.joined_at < v_hold then null
               when me.no_bot_at is not null then 'no_bot'
               when public.gauntlet_planner_gone() then 'planner_gone'
             end;
  if (v_early is null
      and now() - me.joined_at < make_interval(secs => public.gauntlet_queue_fallback_sec())
      and public.app_now() < to_timestamp(me.season_week + 6 * 86400 + 17 * 3600 + 1800)
                             - make_interval(secs => public.gauntlet_queue_close_rush_sec()))
     or v_me_bot then
    return;
  end if;
  -- 机器人强度 = 我的本周场次（与 referee_gauntlet_start 同一个算法）
  v_b := greatest(
    case when jsonb_typeof(me.snapshot->'season_total_battles') = 'number'
         then least((me.snapshot->>'season_total_battles')::numeric, 1000)::int else 0 end,
    coalesce((select max(battles) from public.ghosts where account_id = me.account_id and season_week = me.season_week), 0)
      + me.gw + me.gl,
    me.gw + me.gl);
  -- ★20261029b ① 同格子真人快照（本周闯关上传的、同战绩、同 rules_ver、跑得起来；排除自己与本周交过手的）：
  --   真人号优先于陪练号（bot_accounts），30 分钟内上传的优先（= referee_gauntlet_pick 的 FRESH 窗口），再随机。
  --   用户 10-29「也不应该是优先真人的快照吗，但可以多等啊，3分钟？」
  select gg.account_id, gg.snapshot, gg.uploaded_at into g
    from public.gauntlet_ghosts gg
   where gg.season_week = me.season_week and gg.gw = me.gw and gg.gl = me.gl and gg.rules_ver = me.rules_ver
     and gg.account_id <> me.account_id and not (gg.account_id::text = any(v_ex))
     and public.referee_lanes_ok(gg.snapshot)
   order by (not exists (select 1 from public.bot_accounts b where b.account_id = gg.account_id)) desc,
            (gg.uploaded_at > now() - make_interval(secs => 1800)) desc, random()
   limit 1;
  if found then
    pk := jsonb_build_object('snap', g.snapshot - 'origin', 'opp', g.account_id::text, 'account', g.account_id,
      'pick', case when g.uploaded_at > now() - make_interval(secs => 1800) then 'fresh' else 'stale' end);
  else
    -- ② 机器人池（原样）
    pk := public.referee_gauntlet_pick_bot(me.gw, me.gl, me.rules_ver, v_b, v_ex);
  end if;
  if pk is null then
    return;                                   -- 池子里没有这一格 ⇒ 接着等
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('gauntlet', format('gfallback:%s:%s', me.season_week, me.id), me.season_week, me.client_version,
      -- b_account = 被打的那份快照的主人（同旧路 referee_gauntlet_start；不在场、meta 不带 pair ⇒ 只记真人一边）；机器人池 = 空
      public.referee_new_seed(), me.account_id, (pk->>'account')::uuid, me.snapshot, pk->'snap', public.referee_level_of(me.snapshot),
      jsonb_build_object('account', me.account_id, 'gw0', me.gw, 'gl0', me.gl, 'opp', pk->>'opp', 'pick', pk->>'pick',
                         'rules_ver', me.rules_ver, 'battles', v_b, 'server_pick', true, 'fallback', true,
                         'queue_a', me.id)
      || case when v_early is null then '{}'::jsonb else jsonb_build_object('early', v_early) end)
    returning job_id into jid;
  update public.gauntlet_queue
     set status = 'paired', job_id = jid, side = 'a', paired_at = now(), updated_at = now()
   where id = me.id;
end $$;
revoke all on function public.gauntlet_queue_advance(bigint) from public, anon, authenticated;
-- <<< END gauntlet_no_bot_early_fallback 20261031 <<<

-- >>> BEGIN finals_sequential_premiere 20261101 >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛日：冠军杯赛一场接一场 / 小组赛同轮同时（2026-11-01 · 方案书 docs/plans/20261101-决赛日开播一场接一场.md）
--   用户 10-31「有任何商业游戏会同时播两个半决赛吗」；随后纠正「桶内的话…十六场同时开打，然后到第二轮八场同时开打，
--   第三轮四场同时开打…最多就是五轮」「桶内就是这样子同时跑，但是决赛里面就一定是一场场跑」。
--   原来 finals_advance 每组每轮固定 480 秒、到点整轮翻面；下一轮的 3 分钟备战也从翻面那一刻起算
--   ⇒ 下一轮对手在上一轮还在开播时就写出来了（剧透）。
--
-- 新规则（只在 finals_sequential_on() 时生效 = 裁判出结果 且 referee_config.finals_sequential，默认开）：
--   ① 翻面提前：备战结束 + finals_settle_sec()（60 秒）之后、本轮真实场次的裁判结果都齐了就翻（finals_advance 每分钟一次）；
--      原来固定等到 round_at + 480（备战结束后干等 5 分钟）。宽限（2 倍）与兜底（3 倍）仍按 finals_round_sec() 算，逐条不变。
--      倒计时 next_at = 最早翻面时刻（round_at + 180 + 60）；seq.settle_at = 备战结束时刻（客户端据此说「结算中 · 即将开播」）。
--   ② 翻面时给这一轮【有裁判录像的真实场次】排开播档期（finals_premiere_plan）；每场时长 = ceil(steps / 60) +
--      finals_premiere_intro_sec()（开场 VS ~6 秒 + 开场与路间幕布 ~25 秒，取 30）：
--        · 小组赛各桶：同一轮所有场次都 = 翻面时刻（同时开播）；本轮档期结束 = 翻面 + 最长那一场 + finals_premiere_gap_sec()。
--        · 冠军杯赛（finals_cup_no()）：按 match_no 一场接一场 —— 第 1 场 = 翻面时刻，下一场 = 上一场结束 + 间隔（25 秒：结束仪式最长 ~10 秒 + 余量）。
--        轮空 / 兜底判 / 坏快照判负（seed_used = 0，没有录像）不排档期 ⇒ 翻面即揭晓。
--   ③ 下一轮的 round_at（= 3 分钟备战开始）= 本轮档期结束（含最后一个间隔）⇒ 一轮全部播完才开下一轮备战，
--      下一轮对手在备战开始时才揭晓。round_at 在开播期间是「将来」的时刻 —— 购物窗 / 对手快照 / 建裁判任务
--      本来就按 round_at + finals_shop_sec() 判，未来的 round_at 让它们自然地「还没开始」。
--   ④ finals_buckets.premiere_until = 本次翻面排出来的档期整段结束（含最后一个间隔；没有档期 = 翻面时刻）；
--      非空 ⇔ 这一组最近一次翻面按新规则排了档期（客户端据此认新规则，空 ⇒ 老规则）。
--      冠军杯赛成表（finals_cup_seat）把「收盘了但组内决赛还在开播」的组也当没打完（否则组冠军的名字剧透决赛）。
--   ⑤ finals_view / finals_week_view 多回一个键 seq = {v: 1, until: unix, settle_at: unix, p: {"轮-场": [开播, 揭晓]}}
--      （p 只含已翻面的轮次，与 done 同一道可见性）；开关关且这一组没排过档期 ⇒ seq = null。老客户端只读具名键，多一个键不影响。
--   ⑥ 不同组之间照常并行（各组各自翻面、各自排档期）。
-- 开关：update referee_config set finals_sequential = false ⇒ 下一次翻面起回到老规则（480 秒翻面、同一轮同时开播、翻面即开下一轮备战）；
--   已排的档期不动（客户端按 seq 播完这一轮）。
-- 回滚：finals_advance / finals_cup_seat / finals_view / finals_week_view 换回 20261021_beta_server_clock 版；新列 / 新函数留着不影响。
-- ★重复执行安全（if not exists / create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ① 列
alter table public.finals_results add column if not exists premiere_at timestamptz;   -- 这一场开播时刻（null = 不开播：轮空 / 兜底判 / 老规则）
alter table public.finals_results add column if not exists premiere_sec int;          -- 开播到揭晓几秒（= ceil(steps/60) + intro）
alter table public.finals_buckets add column if not exists premiere_until timestamptz; -- 最近一次翻面的档期整段结束（null = 老规则）
alter table public.referee_config add column if not exists finals_sequential boolean not null default true;

-- ② 常量（只在这里有一份；客户端不存副本，按 seq 里的时刻走）
create or replace function public.finals_premiere_intro_sec() returns int
language sql immutable as $$ select 30 $$;      -- 开场 VS ~6 秒 + 开场与路间幕布 ~25 秒（10-31 彩排实测）
create or replace function public.finals_premiere_gap_sec() returns int
language sql immutable as $$ select 25 $$;      -- 场间：结束仪式 看别人 ~4 / 自己赢 ~7 / 输 ~6 / 组冠军 ~10 秒 + 余量
create or replace function public.finals_settle_sec() returns int
language sql immutable as $$ select 60 $$;      -- 备战结束后至少等多久才翻面（内测服 10-31：裁判领取→写回中位 27 秒、建任务→领取中位 60 秒）
create or replace function public.finals_premiere_cap_sec() returns int
language sql immutable as $$ select 600 $$;     -- 一场对局时长上限（steps 异常大时不让一场占满整晚；正式服 14 天最长 171 秒）

create or replace function public.finals_sequential_on() returns boolean
language sql stable security definer set search_path = public as $$
  select public.referee_finals_on()
     and coalesce((select finals_sequential from public.referee_config where id = 1), true)
$$;
revoke all on function public.finals_sequential_on() from public, anon, authenticated;

-- ③ 排档期：给 (组, 轮) 有裁判录像的真实场次写 premiere_at / premiere_sec；返回本轮档期结束（含最后一个间隔）。
--   小组赛各桶 = 同时（都从翻面开始，结束 = 最长那场 + 间隔）；冠军杯赛 = 按 match_no 一场接一场（用户 10-31「决赛里面就一定是一场场跑」）。
--   ★只认「这一行结果就是这份裁判任务写的」（任务 done 且 seed_used = 任务种子；兜底判 = 0、被抢先写过的 superseded ≠ 任务种子）——
--     兜底判的那一场没有录像，排了档期观众只能对着「画面无法播放」干等。
create or replace function public.finals_premiere_plan(p_week bigint, p_bucket int, p_round int, p_flip timestamptz)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare s record; t timestamptz := p_flip; len int; v_cup boolean := p_bucket = public.finals_cup_no(); v_max int := -1;
begin
  for s in
    select r.match_no,
           case when jsonb_typeof(j.result->'steps') = 'number' then (j.result->>'steps')::numeric end as steps
      from public.finals_results r
      join public.referee_jobs j
        on j.match_key = format('finals:%s:%s:%s:%s', p_week, p_bucket, p_round, r.match_no)
     where r.season_week = p_week and r.bucket_no = p_bucket and r.round = p_round
       and j.kind = 'finals' and j.status = 'done'
       and r.seed_used = j.seed      -- 这一行结果就是这份任务写的（兜底判 seed_used = 0、被抢先写过的 superseded 都不是）
     order by r.match_no
  loop
    if s.steps is null or s.steps <= 0 then
      continue;
    end if;
    len := least(ceil(s.steps / 60.0)::int, public.finals_premiere_cap_sec()) + public.finals_premiere_intro_sec();
    if v_cup then
      update public.finals_results set premiere_at = t, premiere_sec = len
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = s.match_no;
      t := t + make_interval(secs => len + public.finals_premiere_gap_sec());
    else
      update public.finals_results set premiere_at = p_flip, premiere_sec = len
       where season_week = p_week and bucket_no = p_bucket and round = p_round and match_no = s.match_no;
      v_max := greatest(v_max, len);
    end if;
  end loop;
  if not v_cup and v_max >= 0 then
    t := p_flip + make_interval(secs => v_max + public.finals_premiere_gap_sec());
  end if;
  return t;
end $$;
revoke all on function public.finals_premiere_plan(bigint, int, int, timestamptz) from public, anon, authenticated;

-- ④ 读接口共用的 seq 段（finals_view / finals_week_view 的组与杯都走这一份）。可见性与 done 同一条：收盘 或 round < 当前轮。
--   开关开 ⇒ 每组都回（第 1 轮翻面之前 p 为空）；开关关 ⇒ 只有排过档期的组回（老档期照播完）。
--   settle_at = 本轮备战结束时刻（开关开、没收盘时；否则 0）。
drop function if exists public.finals_seq_json(bigint, int, int, boolean, timestamptz);
create or replace function public.finals_seq_json(p_week bigint, p_bucket int, p_round int, p_closed boolean,
    p_until timestamptz, p_round_at timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when p_until is null and not public.finals_sequential_on() then null else jsonb_build_object(
    'v', 1,
    'until', coalesce(extract(epoch from p_until)::bigint, 0),
    'settle_at', case when public.finals_sequential_on() and not p_closed
                      then extract(epoch from p_round_at)::bigint + public.finals_shop_sec() else 0 end,
    'p', coalesce((select jsonb_object_agg(r.round || '-' || r.match_no,
                     jsonb_build_array(extract(epoch from r.premiere_at)::bigint,
                                       extract(epoch from r.premiere_at)::bigint + r.premiere_sec))
                     from public.finals_results r
                    where r.season_week = p_week and r.bucket_no = p_bucket
                      and r.premiere_at is not null and r.premiere_sec is not null
                      and (p_closed or r.round < p_round)), '{}'::jsonb)) end
$$;
revoke all on function public.finals_seq_json(bigint, int, int, boolean, timestamptz, timestamptz) from public, anon, authenticated;
-- 倒计时（next_at）= 下一次最早翻面时刻：新规则 备战结束 + settle；老规则 round_at + 480
create or replace function public.finals_next_at(p_round_at timestamptz) returns bigint
language sql stable security definer set search_path = public as $$
  select extract(epoch from p_round_at)::bigint + case when public.finals_sequential_on()
           then public.finals_shop_sec() + public.finals_settle_sec() else public.finals_round_sec() end
$$;
revoke all on function public.finals_next_at(timestamptz) from public, anon, authenticated;

-- ⑤ finals_advance（以 20261021_beta_server_clock 版为底；★改两处：新规则下翻面闸 = 备战结束 + settle（结果齐才翻）；
--   翻面那一段排档期、下一轮 round_at = 档期结束、记 premiere_until）
create or replace function public.finals_advance(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; moved int := 0; want int; got int; slots int; total int;
        real_want int;
        v_seq boolean; v_flip timestamptz; v_next timestamptz;   -- 20261101 一场接一场
begin
  -- ★2026-10-19 服务器裁判: 购物窗一关就给本轮每一场真实对局建裁判任务(幂等; 开关关着时什么都不做)
  if public.referee_finals_on() then
    perform public.referee_enqueue_finals(p_week);
  end if;
  v_seq := public.finals_sequential_on();
  for b in select * from public.finals_buckets
            where season_week = p_week and not closed loop
    -- 本轮时间还没到就跳过。老规则：3 分钟购物 + 结算 ≈ 8 分钟（480）。
    -- ★20261101 新规则：备战结束 + finals_settle_sec() 之后就能翻（下面照旧要求真实场次的结果都齐了）；
    --   round_at 可能在将来（上一轮还在开播），这一条照样挡住。宽限 / 兜底仍按 finals_round_sec() 的 2 倍 / 3 倍。
    if public.app_now() < b.round_at + make_interval(secs => case when v_seq
         then public.finals_shop_sec() + public.finals_settle_sec() else public.finals_round_sec() end) then
      continue;
    end if;
    -- 补到 2 的幂 → 总轮数 / 本轮该有几场
    slots := 1; total := 0;
    while slots < b.n loop slots := slots * 2; total := total + 1; end loop;
    want := slots / (2 ^ b.round)::int;
    select count(*) into got from public.finals_results
     where season_week = p_week and bucket_no = b.bucket_no and round = b.round;
    -- ★没打完就不推 —— 宁可晚一分钟, 也不能把没结果的一轮翻面
    -- ★★★2026-09-26: 只等【真的有人打的那几场】, 不等轮空（第 1 轮真实场次 = n - slots/2）。
    real_want := want;
    if b.round = 1 then
      real_want := greatest(0, b.n - slots / 2);
    end if;
    if got < real_want then
      -- 宽限期内: 真的等一等（2 倍本轮时长）
      if public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 2) then
        continue;
      end if;
      null;   -- 补判由下面那条 insert 做
    end if;
    if public.referee_finals_on()
       and public.app_now() < b.round_at + make_interval(secs => public.finals_round_sec() * 3) then
      -- ★2026-10-19 服务器裁判: 真实场次只认裁判写回的结果, 这里只补轮空; 硬上限 3 倍本轮时长后走 else 兜底
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
    -- ★20261101 翻面: 一场接一场 ⇒ 排档期, 下一轮备战从档期结束起算; 老规则 ⇒ 与原来逐值相同（round_at = 翻面时刻、premiere_until = null）
    v_flip := public.app_now();
    v_next := v_flip;
    if v_seq then
      v_next := public.finals_premiere_plan(p_week, b.bucket_no, b.round, v_flip);
    end if;
    if b.round >= total then
      update public.finals_buckets set closed = true, revealed_at = v_flip,
             premiere_until = case when v_seq then v_next end
       where season_week = p_week and bucket_no = b.bucket_no;
    else
      update public.finals_buckets set round = b.round + 1, round_at = v_next, revealed_at = v_flip,
             premiere_until = case when v_seq then v_next end
       where season_week = p_week and bucket_no = b.bucket_no;
    end if;
    moved := moved + 1;
  end loop;
  return moved;
end $$;
revoke all on function public.finals_advance(bigint) from public;
revoke execute on function public.finals_advance(bigint) from anon, authenticated;

-- ⑥ finals_cup_seat（以 20261021_beta_server_clock 版为底；★只改「还有组没打完」的口径：收盘了但档期没播完的组也算没打完）
create or replace function public.finals_cup_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare cup int := public.finals_cup_no(); start_at timestamptz; ngroups int; nopen int;
        r record; i int := 0;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    return 0;
  end if;
  start_at := to_timestamp(p_week + 6 * 86400 + public.finals_cup_hour() * 3600);
  if public.app_now() < start_at then
    return 0;
  end if;
  select count(*),
         count(*) filter (where not closed or coalesce(premiere_until > public.app_now(), false))   -- 20261101
    into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and public.app_now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
    return 0;                            -- 还有组没打完（或组内决赛还在开播）：等它（最多等 finals_cup_wait_sec）
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
    values (p_week, cup, i, 1, public.app_now(), i <= 1, case when i <= 1 then public.app_now() else null end);
  return i;
end $$;
revoke all on function public.finals_cup_seat(bigint) from public;
revoke execute on function public.finals_cup_seat(bigint) from anon, authenticated;

-- ⑦ finals_view（以 20261021_beta_server_clock 版为底；★多回一个键 seq、next_at 按新规则）
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
  -- ★p_bucket < 0 = 「我那个桶」（分桶是服务端做的，并进这一次往返）
  if p_bucket < 0 then
    select e.bucket_no into p_bucket from public.finals_entrants e
     where e.season_week = p_week and e.account_id = auth.uid()
       and e.bucket_no <> public.finals_cup_no()   -- ★冠军杯赛 2026-10-07: 「我那个组」只认小组赛
     limit 1;
    if p_bucket is null then
      -- ★2026-09-25: 「没资格」与「有资格但人不够、赛没开起来」分开说
      if exists (select 1 from public.finals_pending
                  where season_week = p_week and account_id = auth.uid()) then
        -- ★2026-10-04: 本周还一个桶都没有 = 还没到分组时间, 不是人太少
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
  -- ★★只取 round < 当前轮 —— 当前轮的结果根本不下发；收盘了就全给
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.winner_side), '{}'::jsonb)
    into res from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  -- ★2026-10-12 比分: 与 done 同一道可见性
  select coalesce(jsonb_object_agg(r.round || '-' || r.match_no, r.loser_lanes)
           filter (where r.loser_lanes is not null), '{}'::jsonb)
    into sc from public.finals_results r
   where r.season_week = p_week and r.bucket_no = p_bucket
     and (b.closed or r.round < b.round);
  return jsonb_build_object('ok', true, 'bucket', p_bucket, 'n', b.n, 'round', b.round,
    'round_at', extract(epoch from b.round_at)::bigint,
    -- ★2026-10-07 实时观赛: 最近一次翻面的时刻(没有 = 0)
    'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
    -- ★下一轮开始时刻（= 本轮最早翻面时刻；20261101 新规则 备战结束 + 60 秒）
    'next_at', public.finals_next_at(b.round_at),
    'now', extract(epoch from public.app_now())::bigint,
    'closed', b.closed, 'entrants', ents, 'done', res, 'scores', sc,
    -- ★20261101 一场接一场: 每场开播 / 揭晓时刻（老规则 = null）
    'seq', public.finals_seq_json(p_week, p_bucket, b.round, b.closed, b.premiere_until, b.round_at));
end $function$;

-- ⑧ finals_week_view（以 20261021_beta_server_clock 版为底；★组与杯各多回一个键 seq、杯的 next_at 按新规则）
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
                       and (b.closed or r.round < b.round)),
           'seq', public.finals_seq_json(p_week, b.bucket_no, b.round, b.closed, b.premiere_until, b.round_at))   -- 20261101
         order by b.bucket_no), '[]'::jsonb)
    into bs from public.finals_buckets b
   where b.season_week = p_week
     and b.bucket_no <> cup;               -- ★冠军杯赛 2026-10-07: 杯不进组列表
  select jsonb_build_object(
           'bucket', b.bucket_no, 'n', b.n, 'round', b.round, 'closed', b.closed,
           'round_at', extract(epoch from b.round_at)::bigint,
           'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0),
           'next_at', public.finals_next_at(b.round_at),   -- 20261101
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
                       and (b.closed or r.round < b.round)),
           'seq', public.finals_seq_json(p_week, b.bucket_no, b.round, b.closed, b.premiere_until, b.round_at))   -- 20261101
    into cp from public.finals_buckets b
   where b.season_week = p_week and b.bucket_no = cup;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from public.app_now())::bigint, 'buckets', bs, 'cup', cp);
end $function$;
-- <<< END finals_sequential_premiere 20261101 <<<

-- >>> BEGIN finals_snapshot_guard 20261101b >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛日：服务端快照校验 + 坏快照回退（2026-11-01 · 方案书 docs/plans/20261101-决赛日开播一场接一场.md §4.5 · 上级 20261031c 块 V / P21）
--   10-31 彩排 P21：快照不验（0 统领也收）；裁判判 a_bad_snapshot（永久失败）后 finals_advance 只能等满 3 倍本轮时长（24 分钟）
--   再按「缺哪场补哪场 side 0」兜底 ⇒ 整组干等 24 分钟，而交了坏阵容的上半区反而晋级。
-- ★必须在 20261101_finals_sequential_premiere 之后执行（finals_cup_seat 以那一版为底）；20261101 若重跑，要再跑一次本段。
--
-- 判据 = public.referee_lineup_ok（20261020c；与裁判 RefereeJob.validate + _state_from_snapshot 同一组条件：
--   三只不同的统领、lane_assign 的 top / bottom 都是数组、每只统领在两路里恰好出现一次）。周日两侧都可能当左方（A），一律用它。
--
--   ① finals_good_snapshot(周, 账号, 现在这份)：第一份能开打的 —— 现在这份 → 入座时那份（finals_pending）→ 本周闯关赛上传过的
--      （gauntlet_ghosts，最新的在前）；都不行 ⇒ null。
--   ② finals_update_snapshot：备战时推上来的快照不能开打 ⇒ 拒收（原来只看「统领 ≥ 3 只」）；旧的那份（入座时验过的）留着。
--   ③ finals_seat / ④ finals_cup_seat：入座时就换成能开打的那份；一份都没有 ⇒ 照原样坐下（到建任务时判他负）。
--   ⑤ referee_enqueue_finals：建任务前两侧各取一份能开打的（取到了而与现在那份不同 ⇒ 顺手写回参赛者，下一轮也用它）；
--      · 某一侧一份都没有 ⇒ 当场判这一场：没有的那一侧负（两侧都没有 ⇒ 上半区 side 0 晋级）；不建任务、不等。
--      · 裁判已经判过 a_bad_snapshot / b_bad_snapshot（永久失败）：两侧回退后的快照与任务里的不同 ⇒ 换上、任务退回 pending 重算；
--        相同（裁判与本函数判据不一致，或回退不出别的）⇒ 当场判坏的那一侧负。
--      判出来的结果 seed_used = 0（没有录像）⇒ 不排开播档期、翻面即揭晓；本轮其余场次一齐 ⇒ 按 20261101 的翻面闸（备战结束 + 60 秒）翻面。
-- 回滚：四个函数换回 20261101（finals_cup_seat）/ 20261021（另三个）版；finals_good_snapshot 留着不影响。
-- ★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────

-- ① 一份能开打的快照
create or replace function public.finals_good_snapshot(p_week bigint, p_account uuid, p_cur jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb;
begin
  if public.referee_lineup_ok(p_cur) then
    return p_cur;
  end if;
  select p.snapshot into s from public.finals_pending p
   where p.season_week = p_week and p.account_id = p_account;
  if found and public.referee_lineup_ok(s) then
    return s;
  end if;
  for s in select g.snapshot from public.gauntlet_ghosts g
            where g.season_week = p_week and g.account_id = p_account
            order by g.uploaded_at desc, g.gw desc, g.gl asc loop
    if public.referee_lineup_ok(s) then
      return s - 'origin';            -- 同 gauntlet_queue_advance 取快照池那一份的写法
    end if;
  end loop;
  return null;
end $$;
revoke all on function public.finals_good_snapshot(bigint, uuid, jsonb) from public, anon, authenticated;

-- ② finals_update_snapshot（以 20261021_beta_server_clock 版为底；★只换第一道闸：能不能开打用 referee_lineup_ok）
create or replace function public.finals_update_snapshot(p_week bigint, p_bucket int, p_snapshot jsonb)
returns boolean
language plpgsql security definer set search_path = public as $$
declare b record; n int;
begin
  if auth.uid() is null or p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
     or octet_length(p_snapshot::text) > 65536
     or not public.referee_lineup_ok(p_snapshot) then
    return false;                       -- 开不了打的快照不收（20261101b；原来只看统领 ≥ 3 只）—— 旧的那份留着
  end if;
  select * into b from public.finals_buckets where season_week = p_week and bucket_no = p_bucket;
  if not found or b.closed then
    return false;
  end if;
  if public.app_now() >= b.round_at + make_interval(secs => public.finals_shop_sec()) then
    return false;                       -- 购物结束 = 本轮阵容锁定
  end if;
  update public.finals_entrants set snapshot = p_snapshot
   where season_week = p_week and bucket_no = p_bucket and account_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.finals_update_snapshot(bigint, int, jsonb) from public, anon;
grant execute on function public.finals_update_snapshot(bigint, int, jsonb) to authenticated;

-- ③ finals_seat（以 20261021_beta_server_clock 版为底；★只改入座那一行的快照：换成能开打的那份）
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
  for r in select * from public.finals_pending
            where season_week = p_week
            order by gw desc, gl asc, account_id loop
    b := public.finals_bucket_of(i, nb);
    insert into public.finals_entrants
      (season_week, bucket_no, seed, account_id, name, snapshot)
      values (p_week, b, seats[b + 1], r.account_id, r.name,
              coalesce(public.finals_good_snapshot(p_week, r.account_id, r.snapshot), r.snapshot));   -- 20261101b
    seats[b + 1] := seats[b + 1] + 1;
    i := i + 1;
  end loop;
  -- 桶本身（n = 这个桶真实坐了几个人，可能比容量少）；1 人组坐下即收盘
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    select p_week, bucket_no, count(*)::int, 1, public.app_now(), count(*) = 1,
           case when count(*) = 1 then public.app_now() else null end
      from public.finals_entrants where season_week = p_week group by bucket_no;
  return nb;
end $$;
revoke all on function public.finals_seat(bigint) from public;
revoke execute on function public.finals_seat(bigint) from anon, authenticated;

-- ④ finals_cup_seat（以 20261101_finals_sequential_premiere 版为底；★只改入座那一行的快照：换成能开打的那份）
create or replace function public.finals_cup_seat(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare cup int := public.finals_cup_no(); start_at timestamptz; ngroups int; nopen int;
        r record; i int := 0;
begin
  if exists (select 1 from public.finals_buckets where season_week = p_week and bucket_no = cup) then
    return 0;
  end if;
  start_at := to_timestamp(p_week + 6 * 86400 + public.finals_cup_hour() * 3600);
  if public.app_now() < start_at then
    return 0;
  end if;
  select count(*),
         count(*) filter (where not closed or coalesce(premiere_until > public.app_now(), false))   -- 20261101
    into ngroups, nopen
    from public.finals_buckets where season_week = p_week and bucket_no <> cup;
  if ngroups = 0 then
    return 0;                            -- 本周没有小组赛（人不够 / 没分组）
  end if;
  if nopen > 0 and public.app_now() < start_at + make_interval(secs => public.finals_cup_wait_sec()) then
    return 0;                            -- 还有组没打完（或组内决赛还在开播）：等它（最多等 finals_cup_wait_sec）
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
      values (p_week, cup, i, r.account_id, r.name,
              coalesce(public.finals_good_snapshot(p_week, r.account_id, r.snapshot), r.snapshot));   -- 20261101b
    i := i + 1;
  end loop;
  if i = 0 then
    return 0;
  end if;
  insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed, revealed_at)
    values (p_week, cup, i, 1, public.app_now(), i <= 1, case when i <= 1 then public.app_now() else null end);
  return i;
end $$;
revoke all on function public.finals_cup_seat(bigint) from public;
revoke execute on function public.finals_cup_seat(bigint) from anon, authenticated;

-- ⑤ referee_enqueue_finals（以 20261021_beta_server_clock 版为底；★建任务前两侧各取一份能开打的；取不到 / 裁判判过坏快照 ⇒ 当场判）
create or replace function public.referee_enqueue_finals(p_week bigint)
returns int language plpgsql security definer set search_path = public as $$
declare b record; ea record; eb record; slots int; n_match int; m int; s0 int; s1 int;
        ver text; added int := 0; k int;
        sa jsonb; sb jsonb; jb record; mk text;              -- 20261101b
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
    if public.app_now() < b.round_at + make_interval(secs => public.finals_shop_sec()) then
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
      -- ★20261101b 两侧各取一份能开打的；取到了而与现在那份不同 ⇒ 写回参赛者（之后几轮也用它）
      sa := public.finals_good_snapshot(p_week, ea.account_id, ea.snapshot);
      sb := public.finals_good_snapshot(p_week, eb.account_id, eb.snapshot);
      if sa is not null and sa is distinct from ea.snapshot then
        update public.finals_entrants set snapshot = sa
         where season_week = p_week and bucket_no = b.bucket_no and seed = s0;
      end if;
      if sb is not null and sb is distinct from eb.snapshot then
        update public.finals_entrants set snapshot = sb
         where season_week = p_week and bucket_no = b.bucket_no and seed = s1;
      end if;
      mk := format('finals:%s:%s:%s:%s', p_week, b.bucket_no, b.round, m);
      select * into jb from public.referee_jobs where match_key = mk;
      if found and jb.status = 'failed' and jb.error in ('a_bad_snapshot', 'b_bad_snapshot') then
        if sa is not null and sb is not null
           and (sa is distinct from jb.a_snapshot or sb is distinct from jb.b_snapshot) then
          -- 回退出了与任务里不同的快照 ⇒ 换上、退回 pending 重算
          update public.referee_jobs
             set a_snapshot = sa, b_snapshot = sb, level = public.referee_level_of(sa),
                 status = 'pending', attempts = 0, error = null, done_at = null, claimed_by = null, claimed_at = null
           where job_id = jb.job_id;
          added := added + 1;
        else
          -- 裁判说坏、回退不出别的 ⇒ 坏的那一侧负（不等 3 倍时长、不再按 side 0 兜底）
          insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
            values (p_week, b.bucket_no, b.round, m, case when jb.error = 'a_bad_snapshot' then 1 else 0 end, 0)
            on conflict (season_week, bucket_no, round, match_no) do nothing;
        end if;
        continue;
      end if;
      if sa is null or sb is null then
        -- 一份能开打的都没有 ⇒ 当场判：没有的那一侧负；两侧都没有 ⇒ 上半区（side 0）晋级
        insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used)
          values (p_week, b.bucket_no, b.round, m, case when sa is null and sb is not null then 1 else 0 end, 0)
          on conflict (season_week, bucket_no, round, match_no) do nothing;
        continue;
      end if;
      insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
          a_account, b_account, a_snapshot, b_snapshot, level, meta)
        values ('finals', mk, p_week, ver,
          public.referee_new_seed(), ea.account_id, eb.account_id, sa, sb,
          public.referee_level_of(sa),
          jsonb_build_object('bucket', b.bucket_no, 'round', b.round, 'match', m, 'seed0', s0, 'seed1', s1))
        on conflict (match_key) do nothing;
      get diagnostics k = row_count;
      added := added + k;
    end loop;
  end loop;
  return added;
end $$;
revoke all on function public.referee_enqueue_finals(bigint) from public, anon, authenticated;
-- <<< END finals_snapshot_guard 20261101b <<<

-- >>> BEGIN finals_cup_1900 20261101c >>>
-- ─────────────────────────────────────────────────────────────
-- 冠军杯赛开赛 20:00 → 19:00 UTC（2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md 决策记录）。
--   用户原话：「所以小组赛其实六点开打，差不多六点半之前就可以结束吧。那么冠军杯赛我们直接挪到七点钟开始吧，不用八点钟。」
--   （小组赛 18:00 开打；桶内同一轮同时开播后约 24 人 18:17 左右收盘。）
-- 改两处，其余不动：
--   ① finals_cup_hour() 20 → 19（finals_cup_seat 的成表闸 / start_at、beta_tick、客户端常量 FINALS_START_HOUR_UTC 都读它；
--      门禁 tests/verify_champion_cup.gd 逐字对「最后一份定义 = 客户端常量」）。
--   ② cron finals_cup_seat 的小时段 20-23 → 19-23（命令文本与 20261007b 逐字相同）。
--   finals_cup_wait_sec()（开赛时还有组没打完最多再等 3600 秒）不动 ⇒ 最晚 20:00 成表。
-- 生效时机：随客户端 0.22.7（FINALS_START_HOUR_UTC = 19）强制更新之后、工作日上正式服；旧客户端 0.22.6 写死 20，
--   在正式服先改会让旧客户端倒计时说 20:00 而 19:00 就成表。
-- 回滚：finals_cup_hour() 改回 select 20、cron 小时段改回 20-23。★重复执行安全。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_cup_hour()
returns int language sql immutable as $$ select 19 $$;

select cron.unschedule(jobid) from cron.job where jobname = 'finals_cup_seat';
select cron.schedule('finals_cup_seat', '*/5 19-23 * * 0',
  $c$select public.finals_cup_seat(extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint)$c$);
-- <<< END finals_cup_1900 20261101c <<<

-- >>> BEGIN finals_qualified_list 20261101e >>>
-- ─────────────────────────────────────────────────────────────
-- 周日决赛日：观众看「本周晋级名单」（2026-11-01 · 方案书 docs/plans/20261031c-周日赛事界面重做.md G14「绝不放锁住的按钮」）
--   18:00 UTC finals_seat 把 finals_pending 分组成 finals_entrants 之前，没晋级的观众进对阵图只看到一把锁：
--   finals_view 对没报名的人只回 {ok:false, reason:'not_entered'}（不带人数）、finals_week_view 18:00 前 buckets = []、
--   finals_pending 的 RLS 只许看自己那行 ⇒ 客户端拿不到「几个人晋级、都是谁」。
-- 新增一个只读 RPC（★契约定死，客户端照它写）：
--   finals_qualified_list(p_week) →
--     未登录 ⇒ {ok:false, reason:'not_signed_in'}
--     否则   ⇒ {ok:true, week, now, seated, n, list:[{name, tag, avatar, gw, gl, me}, ...]}
--   · now    = public.app_now() 的 epoch 秒（与现行 finals_view / finals_week_view 同一个钟；内测服假时钟见 20261021）
--   · seated = 本周 finals_buckets 已有行（18:00 已分组 ⇒ 客户端改看 finals_week_view）
--   · n      = 本周 finals_pending 行数（不受下面 256 行上限影响）
--   · list   = 本周 finals_pending，排序与 finals_seat 定种子同一条：gw desc, gl asc, account_id（只排序、不下发）；最多 256 行
--              name = finals_pending.name（改名 / 举报占位会改这一列）；tag / avatar = snapshot.profile 里的，没有给 ''；
--              me = 这一行是不是调用者自己
-- ★取舍（设计原则变更，用户要的观众页内容）：finals_pending 的 RLS 注释写着
--   「只能看见自己那一行: 『谁报名了』本身就是情报」。这次让观众在分组前就看到名单；18:00 之后 finals_week_view
--   本来就把全部组员公开 ⇒ 名单本身只是提前到分组之前可见。
--   只下发 名字 / 玩家 ID（tag）/ 头像 / 闯关战绩；★绝不下发阵容（snapshot —— 周日对手的阵容才是真情报）与 account_id。
--   表上的 RLS 策略不动（直接查表仍只看得到自己那行）；只有本函数（security definer）越过它，且只吐上面这几列。
-- 依赖：finals_pending / finals_buckets（schema.sql 本体 · E-B3 2026-09-23）、app_now（20261021_beta_server_clock）。
--   不改任何已有函数 / 表 / 策略；与 20261101 / 20261101b / 20261101c 互不依赖，先后随意。
-- 回滚：drop function public.finals_qualified_list(bigint);（客户端读不到就照旧显示锁）。★重复执行安全（create or replace）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.finals_qualified_list(p_week bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_n int; v_list jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  select count(*) into v_n from public.finals_pending where season_week = p_week;
  -- ★只挑这几列：snapshot / account_id 不出这个函数
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', q.name,
           'tag', coalesce(q.snapshot->'profile'->>'tag', ''),
           'avatar', coalesce(q.snapshot->'profile'->>'avatar', ''),
           'gw', q.gw, 'gl', q.gl,
           'me', q.account_id = v_uid)
         order by q.gw desc, q.gl asc, q.account_id), '[]'::jsonb)
    into v_list
    from (select p.name, p.snapshot, p.gw, p.gl, p.account_id
            from public.finals_pending p
           where p.season_week = p_week
           order by p.gw desc, p.gl asc, p.account_id      -- = finals_seat 的种子顺序
           limit 256) q;
  return jsonb_build_object('ok', true, 'week', p_week,
    'now', extract(epoch from public.app_now())::bigint,
    'seated', exists (select 1 from public.finals_buckets where season_week = p_week),
    'n', v_n, 'list', v_list);
end $$;
revoke all on function public.finals_qualified_list(bigint) from public;
revoke execute on function public.finals_qualified_list(bigint) from anon;
grant execute on function public.finals_qualified_list(bigint) to authenticated;
-- <<< END finals_qualified_list 20261101e <<<

-- >>> BEGIN ranked_referee 20261101d >>>
-- ─────────────────────────────────────────────────────────────
-- 积分赛交给服务器：服务端挑对手 + 裁判机算 + 服务端记账（2026-11-01 · 方案书 docs/plans/20261101c-积分赛服务器裁判.md ·
--   母方案书 docs/plans/20261019-服务器裁判.md §3 ③）
--   用户 10-19「我们的所有对局不应该在本机上吧，应该放服务器上吧，其他游戏怎么做的」；
--   用户 11-01「我就问你一句话：哪个商业游戏是这么本地做的？你见过吗？」
--   改之前：积分赛本机挑对手（Backend.find_opponent）、本机算、本机结算（RealtimeBattle3DScene._settle_season），
--     再由客户端直接写 ghosts（带自报的 season_wins / hearts）与 matches；周榜直接读快照自报 ⇒ 改客户端就能改成绩。
-- 本段（★全部有开关，开关默认关 ⇒ 执行本段不改变任何现行行为）：
--   ① referee_jobs.kind 多一个 'ranked'；referee_config 多三个开关：
--      ranked_on（默认关：服务端收不收积分赛裁判局）/ ranked_any_day（内测服彩排：不限周二~周五）/
--      ranked_client_write（默认开：客户端还能不能直接写积分赛 ghosts / matches —— 切换的最后一步才关）
--   ② ranked_records：服务端积分赛账本（每人每周一行：场次 / 胜 / 余命 / 横扫 / 碎蛋 / 配额 / 累计发币），客户端只能读自己那一行
--   ③ ranked_pool：内置陪练（data/ghost_seed.json，客户端池子里那 396 份）+ 兜底机器人（Backend.make_bot 同一个函数离线生成），
--      按规则版本存；只有 service_role 写（轮询器 referee_poller.py --bot-pool）
--   ④ referee_ranked_pick：挑对手 —— 规则原样搬自客户端 Backend.find_opponent / pool_find_battles：
--      本周同规则版本、**场次完全相同**（D5，没有 ±N）、不是自己、分路没坏、以快照自报的场次为准、排除本周已碰过的那一份；
--      真人快照与内置陪练放在一起**等概率**抽一份（用户 10-08「抽签范围扩大到全部同场次」）；一份都没有 ⇒ 机器人（D5 唯一的回落）
--   ⑤ referee_ranked_start（客户端开战）：交「我的阵容 + 我要打第 N 场」；对手、种子都由服务端定；
--      闸 = 客户端开局闸（主菜单 _battle_block_msg + 选龟 can_start_match_utc）在服务端的同一份：
--      积分赛时段（周二 00:00 ~ 周五 23:00 − 600 秒封盘，UTC）/ 没出局（余命 > 0）/ 配额没满（< 16）
--   ⑥ referee_complete 多一支 'ranked'：结算规则原样搬自 _settle_season 积分赛那一支（输 −1 命；
--      币 = 8 + 余命 + 2×已失命 + 胜 6 + 战斗内铸币；出局那一局 0 币；场次 +1、配额 +1；赢 ⇒ 胜 +1、碎蛋 +1、2-0 ⇒ 横扫 +1），
--      记账本 + 以服务端的数写 ghosts（快照池 / 周榜 / 闯关资格都读它）+ 落 matches（录像）
--   ⑦ referee_job_status 积分赛局多回 kind / ranked（账本快照）/ seed（开算后，跟播用）；referee_ranked_ledger 读自己的账
--   ⑧ week_leaderboard / week_leaderboard_page：有账本的人一律按账本排（不再信快照自报）；没账本的（切换之前的自报）照旧
--   ⑨ ghosts 写策略、matches 写策略（phase = 'ranked'）加 ranked_client_write 闸 —— 关掉它 = 客户端再也写不进积分赛成绩
--   ⑩ referee_claim：真人的积分赛局先算，陪练号的积分赛局排在后面（周末没有积分赛局 ⇒ 周六周日顺序逐字不变）
--   ⑪ referee_flags 多回 ranked_on
-- 上线顺序（每一步不过就停；方案书 §4.7）：迁移（开关全关）→ 裁判机装新版本 + --bot-pool（含积分赛池）→ 新客户端发出 →
--   min_client_version 抬到新版本 → 周一（休赛日）ranked_on = true → 观察一周期 → ranked_client_write = false
-- 回滚：ranked_on = false（客户端回本机那一路）；ranked_client_write = true；函数换回 20261027 / 20261024b 版；新表留着无害。
-- ★重复执行安全（if not exists / create or replace / drop constraint if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 任务种类 / 开关 ─────────────────────────────────────────
alter table public.referee_jobs drop constraint if exists referee_jobs_kind_check;
alter table public.referee_jobs add constraint referee_jobs_kind_check
  check (kind in ('gauntlet', 'finals', 'ranked'));

alter table public.referee_config add column if not exists ranked_on boolean not null default false;
alter table public.referee_config add column if not exists ranked_any_day boolean not null default false;
alter table public.referee_config add column if not exists ranked_client_write boolean not null default true;

create or replace function public.referee_ranked_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ranked_on from public.referee_config where id = 1), false)
$$;
revoke all on function public.referee_ranked_on() from public, anon, authenticated;

-- 客户端还能不能直接写积分赛成绩（ghosts / matches phase = 'ranked'）。缺行 / 缺列 ⇒ 能（与改之前一样）。
create or replace function public.ranked_client_write_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ranked_client_write from public.referee_config where id = 1), true)
$$;
revoke all on function public.ranked_client_write_ok() from public;
grant execute on function public.ranked_client_write_ok() to anon, authenticated, service_role;

-- 积分赛服务器局的第一个客户端版本（带 referee_ranked_start 的那一版；裁判程序从这一版起认 mode = 'ranked'）。
create or replace function public.ranked_min_client() returns text
language sql immutable as $$ select '0.22.7' $$;
revoke all on function public.ranked_min_client() from public, anon, authenticated;

-- 常量（= scripts/gamedata/phase2_config.gd；门禁 verify_ranked_server_rules 逐个对账）
create or replace function public.ranked_hearts_max() returns int language sql immutable as $$ select 6 $$;     -- HEARTS_MAX
create or replace function public.ranked_quota() returns int language sql immutable as $$ select 16 $$;        -- RANKED_QUOTA
create or replace function public.ranked_lockout_sec() returns int language sql immutable as $$ select 600 $$; -- CLOSE_LOCKOUT_SEC
revoke all on function public.ranked_hearts_max() from public, anon, authenticated;
revoke all on function public.ranked_quota() from public, anon, authenticated;
revoke all on function public.ranked_lockout_sec() from public, anon, authenticated;

-- 积分赛开着没有：周二 00:00 ~ 周五 23:00 − 封盘 600 秒（UTC；= phase_at_utc 周二~周五 + can_start_match_utc）。
--   ranked_any_day（内测服彩排）放开星期几；封盘那 10 分钟照样关。
create or replace function public.ranked_window_open(p_week bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.app_now() < to_timestamp(p_week + 4 * 86400 + 23 * 3600 - public.ranked_lockout_sec())
     and (coalesce((select c.ranked_any_day from public.referee_config c where c.id = 1), false)
          or public.app_now() >= to_timestamp(p_week + 86400))
$$;
revoke all on function public.ranked_window_open(bigint) from public, anon, authenticated;

-- ② 积分赛账本 ───────────────────────────────────────────────
-- 每人每周一行 = 客户端 GameState 里那几项（season_total_battles / season_wins / hearts / season_sweeps / season_eggs_killed /
--   ranked_used）的服务端那一份。只有 referee_complete（与切换周的第一次开战补种）写；客户端只读自己那一行。
create table if not exists public.ranked_records (
  season_week  bigint      not null,
  account_id   uuid        not null references auth.users(id) on delete cascade,
  battles      int         not null default 0,     -- 本周积分赛场次（= season_total_battles）
  wins         int         not null default 0,     -- 胜场（= season_wins）
  hearts       int         not null default 6,     -- 余命（= hearts；0 = 出局）
  sweeps       int         not null default 0,     -- 横扫 2-0（= season_sweeps）
  eggs         int         not null default 0,     -- 碎蛋（= season_eggs_killed）
  used         int         not null default 0,     -- 配额已用（= ranked_used）
  coins        int         not null default 0,     -- 本周积分赛服务器局一共发了多少深海币（对账用）
  seeded       text,                               -- 'ghosts' = 切换那一周从旧自报快照补种的（之后的每一场都是服务端记的）
  updated_at   timestamptz not null default now(),
  primary key (season_week, account_id)
);
alter table public.ranked_records enable row level security;
drop policy if exists ranked_records_self on public.ranked_records;
create policy ranked_records_self on public.ranked_records for select using (auth.uid() = account_id);
-- 写只有 security definer 函数（没有 insert / update 策略）

-- 这个人本周的账（没有行 ⇒ 切换之前的旧自报快照里最后一份；都没有 ⇒ 新的一周：0 场 / 满命）。只读、不建行。
create or replace function public.ranked_ledger_peek(p_uid uuid, p_week bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; g record;
begin
  select * into r from public.ranked_records where season_week = p_week and account_id = p_uid;
  if found then
    return jsonb_build_object('battles', r.battles, 'wins', r.wins, 'hearts', r.hearts, 'sweeps', r.sweeps,
      'eggs', r.eggs, 'used', r.used, 'seeded', r.seeded, 'row', true);
  end if;
  select gg.battles, gg.season_wins, gg.hearts, gg.season_sweeps, gg.snapshot into g
    from public.ghosts gg
   where gg.account_id = p_uid and gg.season_week = p_week
     and coalesce(gg.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
     and coalesce(gg.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
   order by gg.battles desc, gg.uploaded_at desc limit 1;
  if found then
    return jsonb_build_object('battles', greatest(g.battles, 0), 'wins', greatest(g.season_wins, 0),
      'hearts', least(greatest(g.hearts, 0), public.ranked_hearts_max()), 'sweeps', greatest(g.season_sweeps, 0),
      'eggs', case when jsonb_typeof(g.snapshot -> 'season_eggs_killed') = 'number'
                   then greatest((g.snapshot ->> 'season_eggs_killed')::numeric::int, 0) else greatest(g.season_wins, 0) end,
      'used', greatest(g.battles, 0), 'seeded', 'ghosts', 'row', false);
  end if;
  return jsonb_build_object('battles', 0, 'wins', 0, 'hearts', public.ranked_hearts_max(), 'sweeps', 0, 'eggs', 0,
    'used', 0, 'seeded', null, 'row', false);
end $$;
revoke all on function public.ranked_ledger_peek(uuid, bigint) from public, anon, authenticated;

-- 客户端读自己本周的账（主菜单对账 / 开战前）。不建行。
create or replace function public.referee_ranked_ledger(p_week bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  return jsonb_build_object('ok', true, 'week', p_week, 'ledger', public.ranked_ledger_peek(auth.uid(), p_week));
end $$;
revoke all on function public.referee_ranked_ledger(bigint) from public, anon;
grant execute on function public.referee_ranked_ledger(bigint) to authenticated;

-- ③ 积分赛对手池（内置陪练 + 兜底机器人）─────────────────────
create table if not exists public.ranked_pool (
  rules_ver      int         not null,
  kind           text        not null check (kind in ('seed', 'bot')),
  battles        int         not null check (battles between 0 and 1000),
  variant        int         not null check (variant between 0 and 9999),
  snapshot       jsonb       not null,
  client_version text        not null,              -- 哪个版本的代码生成的（只作记录；挑的时候按 rules_ver）
  created_at     timestamptz not null default now(),
  primary key (rules_ver, kind, battles, variant)
);
alter table public.ranked_pool enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行（池子本身就是「哪些是陪练 / 机器人」的答案）

-- 真人快照能不能当积分赛对手 —— 客户端 RemotePool.snapshot_valid（入池那一道）+ pool_find_battles（选靶那一道）在服务端的同一份：
--   schema_ver = Backend.SCHEMA_VER(2)、有 ghost_id 且不是冒烟数据（'__smoke__'）、快照自报的场次 = 要找的场次、
--   统领 1~3 只、pet_levels 在 1..10、每只装备 ≤ UNIT_EQUIP_CAP(3)、分路没坏（referee_lanes_ok = ghost_lanes_broken 取反）。
--   ★龟 id 白名单（_TS.STATS）不在这里：裁判程序算之前照样校验 B 方快照，不认识的龟 ⇒ b_bad_snapshot ⇒ 重交时换一个对手。
create or replace function public.referee_ranked_ghost_ok(p_snap jsonb, p_battles int) returns boolean
language plpgsql immutable as $$
declare k text; v jsonb;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'schema_ver') <> 'number' or (p_snap ->> 'schema_ver')::numeric <> 2 then
    return false;
  end if;
  if coalesce(p_snap ->> 'ghost_id', '') = '' or left(p_snap ->> 'ghost_id', 9) = '__smoke__' then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'season_total_battles') <> 'number'
     or (p_snap ->> 'season_total_battles')::numeric <> p_battles then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'leaders') <> 'array' or jsonb_array_length(p_snap -> 'leaders') not between 1 and 3 then
    return false;
  end if;
  if jsonb_typeof(p_snap -> 'pet_levels') = 'object' then
    for k, v in select * from jsonb_each(p_snap -> 'pet_levels') loop
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not between 1 and 10 then
        return false;
      end if;
    end loop;
  end if;
  if jsonb_typeof(p_snap -> 'equipped') = 'object' then
    for k, v in select * from jsonb_each(p_snap -> 'equipped') loop
      if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) > 3 then
        return false;
      end if;
    end loop;
  end if;
  return public.referee_lanes_ok(p_snap);
end $$;
revoke all on function public.referee_ranked_ghost_ok(jsonb, int) from public, anon, authenticated;

-- 上传积分赛池（只有 service_role：轮询器 referee_poller.py --bot-pool）。按 (规则版本, 种类) 分批调：第一批 p_replace = true 先清旧的。
--   每行 {battles, variant, snapshot}。陪练（seed）：分路没坏、自报场次 = battles；机器人（bot）：能当左方开打（referee_lineup_ok）。
--   不合格的计入 rejected、不入池。存之前摘掉 origin（服务端直接取的真人快照没有这个键；不摘 = 录像里一眼分得出）。
create or replace function public.referee_ranked_pool_load(p_client_version text, p_rules_ver int, p_kind text,
    p_rows jsonb, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; bad int := 0; total int; b int;
begin
  if p_rules_ver is null or p_rules_ver < 1 or p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or coalesce(p_client_version, '') = '' or coalesce(p_kind, '') not in ('seed', 'bot') then
    return jsonb_build_object('ok', false, 'reason', 'bad_args');
  end if;
  if coalesce(p_replace, false) then
    delete from public.ranked_pool where rules_ver = p_rules_ver and kind = p_kind;
  end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r) <> 'object' or jsonb_typeof(r -> 'battles') <> 'number' or jsonb_typeof(r -> 'variant') <> 'number'
       or jsonb_typeof(r -> 'snapshot') <> 'object' or octet_length((r -> 'snapshot')::text) > 65536 then
      bad := bad + 1;
      continue;
    end if;
    b := (r ->> 'battles')::numeric::int;
    if (p_kind = 'seed' and not (public.referee_lanes_ok(r -> 'snapshot')
          and jsonb_typeof(r -> 'snapshot' -> 'season_total_battles') = 'number'
          and (r -> 'snapshot' ->> 'season_total_battles')::numeric = b))
       or (p_kind = 'bot' and not public.referee_lineup_ok(r -> 'snapshot')) then
      bad := bad + 1;
      continue;
    end if;
    insert into public.ranked_pool (rules_ver, kind, battles, variant, snapshot, client_version)
      values (p_rules_ver, p_kind, b, (r ->> 'variant')::numeric::int, (r -> 'snapshot') - 'origin', p_client_version)
      on conflict (rules_ver, kind, battles, variant) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, created_at = now();
    n := n + 1;
  end loop;
  select count(*) into total from public.ranked_pool where rules_ver = p_rules_ver and kind = p_kind;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'loaded', n, 'rejected', bad, 'total', total);
end $$;
revoke all on function public.referee_ranked_pool_load(text, int, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.referee_ranked_pool_load(text, int, text, jsonb, boolean) to service_role;

-- ④ 挑对手 ─────────────────────────────────────────────────
-- 本周我碰过的积分赛对手（opp 键：真人 'acct:<uuid>:b<场次>' / 陪练 'seed:<规则>:<场次>:<序号>' / 机器人 'bot:…'）。
--   = 客户端匹配屏的 exclude（自己的 ghost_id + 最近 8 个对手的 ghost_id）：ghost_id 带场次（_b<N>），
--   所以排除的是「这个人在这个场次的那一份」—— 换了场次就不是同一份（与客户端同一口径）。
create or replace function public.referee_ranked_opp_ex(p_uid uuid, p_week bigint) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x), '{}')
    from (select j.meta ->> 'opp' as x from public.referee_jobs j
           where j.kind = 'ranked' and j.season_week = p_week and j.a_account = p_uid and j.meta ? 'opp'
          union all
          select jsonb_array_elements_text(j.meta -> 'opp_prev') from public.referee_jobs j
           where j.kind = 'ranked' and j.season_week = p_week and j.a_account = p_uid
             and jsonb_typeof(j.meta -> 'opp_prev') = 'array') e
   where x is not null
$$;
revoke all on function public.referee_ranked_opp_ex(uuid, bigint) from public, anon, authenticated;

-- 挑一个对手。返回 {snap, opp, pick, account?}；pick = human / seed / bot；一个都挑不到（池子没上传）⇒ null。
--   ① 场次完全相同（D5）：本周、同规则版本、不是自己、合格（referee_ranked_ghost_ok）的真人快照 ∪ 同场次的内置陪练，
--      排除本周碰过的那一份，**等概率**抽一份（= pool_find_battles 的 randi_range；用户 10-08「从全部同场次快照里等概率抽」）
--   ② 机器人（= make_bot(场次)）：池子按场次存到 30；超出的用最大那一格、只把 season_total_battles 改成真实场次（同 referee_gauntlet_pick_bot）。
create or replace function public.referee_ranked_pick(p_uid uuid, p_week bigint, p_battles int, p_rules_ver int,
    p_ex text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare c record; bp record; bk int; snap jsonb;
begin
  select * into c from (
    select format('acct:%s:b%s', g.account_id, g.battles) as opp, g.account_id as account, g.snapshot as snap, 'human' as pick
      from public.ghosts g
     where g.season_week = p_week and g.battles = p_battles and g.rules_ver = p_rules_ver
       and g.account_id <> p_uid and public.referee_ranked_ghost_ok(g.snapshot, p_battles)
    union all
    select format('seed:%s:%s:%s', p.rules_ver, p.battles, p.variant), null::uuid, p.snapshot, 'seed'
      from public.ranked_pool p
     where p.rules_ver = p_rules_ver and p.kind = 'seed' and p.battles = p_battles
       and public.referee_lanes_ok(p.snapshot)
       and jsonb_typeof(p.snapshot -> 'season_total_battles') = 'number'
       and (p.snapshot ->> 'season_total_battles')::numeric = p_battles
  ) cand
  where not (cand.opp = any(coalesce(p_ex, '{}')))
  order by random()
  limit 1;
  if found then
    return jsonb_build_object('snap', c.snap - 'origin', 'opp', c.opp, 'pick', c.pick)
      || case when c.account is not null then jsonb_build_object('account', c.account) else '{}'::jsonb end;
  end if;
  select max(battles) into bk from public.ranked_pool where rules_ver = p_rules_ver and kind = 'bot';
  if bk is null then
    return null;
  end if;
  bk := least(greatest(coalesce(p_battles, 0), 0), bk);
  select p.* into bp from public.ranked_pool p
   where p.rules_ver = p_rules_ver and p.kind = 'bot' and p.battles = bk
   order by (format('bot:%s:%s:%s', p.rules_ver, p.battles, p.variant) = any(coalesce(p_ex, '{}'))), random()
   limit 1;
  if not found then
    return null;
  end if;
  snap := bp.snapshot - 'origin';
  if coalesce(p_battles, 0) > bk then
    snap := jsonb_set(snap, '{season_total_battles}', to_jsonb(p_battles));   -- 场次标签与玩家相同（用户 10-04「场次一定要相同」）
  end if;
  return jsonb_build_object('snap', snap, 'opp', format('bot:%s:%s:%s', bp.rules_ver, bp.battles, bp.variant), 'pick', 'bot');
end $$;
revoke all on function public.referee_ranked_pick(uuid, bigint, int, int, text[]) from public, anon, authenticated;

-- 开战交上去的阵容：快照里那几个账本数改成服务端的（裁判按快照的场次算援军小将的成长，必须是服务端的场次）。
create or replace function public.ranked_stamp_snapshot(p_snap jsonb, p_led jsonb, p_battles int) returns jsonb
language plpgsql immutable as $$
declare s jsonb := p_snap; gid text;
begin
  s := jsonb_set(s, '{season_total_battles}', to_jsonb(p_battles));
  s := jsonb_set(s, '{season_wins}', p_led -> 'wins');
  s := jsonb_set(s, '{hearts}', p_led -> 'hearts');
  s := jsonb_set(s, '{season_sweeps}', p_led -> 'sweeps');
  s := jsonb_set(s, '{season_eggs_killed}', p_led -> 'eggs');
  gid := coalesce(s ->> 'ghost_id', '');
  if gid ~ '_b[0-9]+$' then
    s := jsonb_set(s, '{ghost_id}', to_jsonb(regexp_replace(gid, '_b[0-9]+$', '_b' || p_battles)));
  end if;
  if jsonb_typeof(s -> 'profile') = 'object' and coalesce(s -> 'profile' ->> 'id', '') ~ '_b[0-9]+$' then
    s := jsonb_set(s, '{profile,id}', to_jsonb(regexp_replace(s -> 'profile' ->> 'id', '_b[0-9]+$', '_b' || p_battles)));
  end if;
  return s;
end $$;
revoke all on function public.ranked_stamp_snapshot(jsonb, jsonb, int) from public, anon, authenticated;

-- ⑤ 客户端开战 ─────────────────────────────────────────────
-- 交「我的阵容 + 我要打第 N 场」（N = 本机的 season_total_battles）。回 {ok, job_id, match_id, opp(卡片), ledger}；
--   拒收 {ok:false, reason, ledger?}：not_signed_in / off / update_required / wrong_week / closed / bad_snapshot /
--   eliminated(余命 0) / quota_full(配额满) / stale(第 N 场与账本对不上 ⇒ 客户端以 ledger 为准) / no_opponent。
-- 有一场在算 ⇒ 回那一场（in_flight）。只有「上一次算失败了」才允许同一场重交，种子不换；
--   失败原因是对手快照坏了（b_bad_snapshot）⇒ 记下旧的、重挑；是我的阵容坏了（a_bad_snapshot）⇒ 收新的阵容。
create or replace function public.referee_ranked_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; led jsonb; v_b int; ex record; v_key text;
        pk jsonb; jid bigint; mid uuid; st text; v_snap_a jsonb; v_snap_b jsonb; v_meta jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_ranked_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false)
     or coalesce(public.semver_arr(v_cv), array[0, 0, 0, 0]) < public.semver_arr(public.ranked_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week is distinct from extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.ranked_window_open(p_week) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  -- 有一场在算 ⇒ 回那一场（不再建）
  select * into ex from public.referee_jobs
   where kind = 'ranked' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', public.ranked_ledger_peek(uid, p_week));
  end if;
  led := public.ranked_ledger_peek(uid, p_week);
  v_b := (led ->> 'battles')::int;
  -- = 主菜单 _battle_block_msg：出局（0 命）/ 配额满；回账本让客户端对齐
  if (led ->> 'hearts')::int <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'eliminated', 'ledger', led);
  end if;
  if (led ->> 'used')::int >= public.ranked_quota() then
    return jsonb_build_object('ok', false, 'reason', 'quota_full', 'ledger', led);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机账与服务端对不上 ⇒ 回账本，客户端以它为准）
  if p_match_no is distinct from v_b then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'ledger', led);
  end if;
  -- 账本落行（切换那一周第一次开战：从旧自报快照补种；新的一周：0 场满命）
  insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used, seeded)
    values (p_week, uid, v_b, (led ->> 'wins')::int, (led ->> 'hearts')::int, (led ->> 'sweeps')::int,
            (led ->> 'eggs')::int, (led ->> 'used')::int, led ->> 'seeded')
    on conflict (season_week, account_id) do nothing;
  v_snap_a := public.ranked_stamp_snapshot(p_snapshot, led, v_b);
  v_key := format('ranked:%s:%s:%s', p_week, uid, v_b);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', led);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta -> 'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta ->> 'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
      end if;
      v_snap_b := pk -> 'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk ->> 'opp', 'pick', pk ->> 'pick');
      update public.referee_jobs set b_account = (pk ->> 'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = v_cv,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then v_snap_a else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(v_snap_a) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('ranked', v_key, p_week, v_cv, public.referee_new_seed(), uid, (pk ->> 'account')::uuid,
      v_snap_a, pk -> 'snap', public.referee_level_of(v_snap_a),
      jsonb_build_object('account', uid, 'battles0', v_b, 'opp', pk ->> 'opp', 'pick', pk ->> 'pick',
                         'rules_ver', v_rv, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk -> 'snap'), 'ledger', led);
end $$;
revoke all on function public.referee_ranked_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_ranked_start(bigint, jsonb, int, text, int) to authenticated;

-- ⑥ 写回（以 20261027 版为底；★2026-11-01 只改两处，周六 / 周日逐字不变）：
--   ① 周六那一支的条件从 `elsif j.a_account is not null` 收紧成 `elsif j.kind = 'gauntlet' and j.a_account is not null`
--      （原来的写法会把积分赛局当成闯关局记进 gauntlet_records）
--   ② 多一支 'ranked'：_settle_season 积分赛那一支原样（见下面逐行注释）+ 以服务端的数写 ghosts
create or replace function public.referee_complete(p_job_id bigint, p_worker text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; won boolean; sc int; ll smallint; res jsonb; v_gw int; v_gl int; n int; superseded boolean := false;
        v_coins int := 0; v_rv int; v_coins_b int := 0;   -- 2026-10-20d
        v_pair boolean; v_gw_b int; v_gl_b int;           -- 2026-10-27 在线瑞士轮
        rr record; v_hearts int; v_lost int; v_reward int; v_sweep boolean; v_led jsonb; v_snap jsonb;   -- 2026-11-01 积分赛
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
  -- ★2026-10-27 在线瑞士轮：配对局（gauntlet_queue 配出来的，meta.pair）两边都是在场的账号 ⇒ 两边都记。
  --   只认 meta.pair：旧路任务的 b_account 是被打的那份快照的主人（20261020c 起真人快照填账号），不是在场的人。
  v_pair := j.kind = 'gauntlet' and coalesce(j.meta->>'pair', '') = 'true';
  if j.kind = 'finals' then
    res := res || jsonb_build_object('fb', (j.meta->>'bucket')::int, 'fr', (j.meta->>'round')::int, 'fm', (j.meta->>'match')::int);
    ll := case when sc in (0, 1, -10, -11) then sc end;      -- = finals_results_loser_lanes 约束
    insert into public.finals_results (season_week, bucket_no, round, match_no, winner_side, seed_used, loser_lanes)
      values (j.season_week, (j.meta->>'bucket')::int, (j.meta->>'round')::int, (j.meta->>'match')::int,
              case when won then 0 else 1 end, j.seed, ll)
      on conflict (season_week, bucket_no, round, match_no) do nothing;
    get diagnostics n = row_count;
    superseded := n = 0;
  elsif j.kind = 'gauntlet' and j.a_account is not null then
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
    -- ★2026-10-26 第 4 胜由服务端直接登记决赛报名（= phase2_config.GAUNTLET_WINS_IN；同 finals_enter 的 floor_wins）。
    --   闯关赛延到周日 17:30、分桶 18:00 只剩 30 分钟；原来只靠客户端结算后 / 开主菜单时报名，第 4 胜结算晚或玩家关了游戏
    --   ⇒ 18:00 后才报 ⇒ already_seated，错过决赛。客户端那两条留作兜底（finals_enter 同一张表、幂等 upsert）。
    --   已经有人报过（客户端先到）就不动它；桶已坐定就不再塞人（与 finals_enter 同一条）。
    if v_gw >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.a_account, coalesce(nullif(j.a_snapshot->'profile'->>'name', ''), '?'), j.a_snapshot, v_gw, v_gl)
        on conflict (season_week, account_id) do nothing;
    end if;
  elsif j.kind = 'ranked' and j.a_account is not null then
    -- ★2026-11-01 积分赛（= RealtimeBattle3DScene._settle_season 积分赛那一支，逐行对照；门禁 verify_ranked_server_rules 同输入同输出）
    insert into public.ranked_records (season_week, account_id, hearts)
      values (j.season_week, j.a_account, public.ranked_hearts_max())
      on conflict (season_week, account_id) do nothing;
    select * into rr from public.ranked_records where season_week = j.season_week and account_id = j.a_account for update;
    v_hearts := rr.hearts;
    if not won then
      v_hearts := greatest(0, v_hearts - 1);                               -- gs.lose_heart()：clamp ≥ 0
    end if;
    v_lost := greatest(0, public.ranked_hearts_max() - v_hearts);          -- maxi(0, HEARTS_MAX − hearts)
    v_reward := 8 + v_hearts + 2 * v_lost + case when won then 6 else 0 end;   -- 8 + 余命 + 2×已失命 + 胜 6
    -- 横扫 = GameState.dual_lane_was_sweep()：两路都打完且同一方全胜、那一方是左（A）
    v_sweep := won and coalesce(p_result->'lane_results'->>'top', '') = 'left'
               and coalesce(p_result->'lane_results'->>'bottom', '') = 'left';
    v_reward := v_reward + v_coins;                                        -- + EquipTickSystem.match_minted（裁判写的 coins）
    if v_hearts <= 0 then
      v_reward := 0;                                                       -- 出局那一局不发币（含战斗内铸币）
    end if;
    update public.ranked_records
       set hearts = v_hearts,
           battles = rr.battles + 1,                                       -- season_total_battles += 1
           used = rr.used + 1,                                             -- consume_ranked_quota()
           wins = rr.wins + case when won then 1 else 0 end,               -- season_wins += 1
           eggs = rr.eggs + case when won then 1 else 0 end,               -- season_eggs_killed += 1
           sweeps = rr.sweeps + case when v_sweep then 1 else 0 end,       -- season_sweeps += 1
           coins = rr.coins + v_reward, updated_at = now()
     where season_week = j.season_week and account_id = j.a_account
     returning jsonb_build_object('battles', battles, 'wins', wins, 'hearts', hearts, 'sweeps', sweeps, 'eggs', eggs,
                                  'used', used) into v_led;
    v_led := v_led || jsonb_build_object('reward', v_reward, 'sweep', v_sweep);
    res := res || jsonb_build_object('ranked', v_led);
    v_rv := coalesce(case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    -- 快照池 / 周榜：以打完这一场的服务端账写一份（= 客户端每场都传的那一份，只是数由服务端填；E18「每场都传」）。
    --   阵容 = 开战时交的那一份；宝箱 / 香火石取这一局结束时的（裁判结果单）。
    v_snap := public.ranked_stamp_snapshot(j.a_snapshot, v_led, (v_led ->> 'battles')::int);
    if jsonb_typeof(p_result->'chest') = 'object' then
      v_snap := v_snap || jsonb_build_object('chest_treasure_value', coalesce(p_result->'chest'->'value', '0'::jsonb),
                                             'chest_treasures_won', coalesce(p_result->'chest'->'won', '[]'::jsonb));
    end if;
    if jsonb_typeof(p_result->'incense') = 'object' then
      v_snap := v_snap || jsonb_build_object('incense_marks', coalesce(p_result->'incense'->'marks', '0'::jsonb),
                                             'incense_charge', coalesce(p_result->'incense'->'charge', '0'::jsonb));
    end if;
    insert into public.ghosts (account_id, season_week, battles, snapshot, season_wins, hearts, season_sweeps,
        client_version, rules_ver)
      values (j.a_account, j.season_week, (v_led ->> 'battles')::int, v_snap, (v_led ->> 'wins')::int,
              (v_led ->> 'hearts')::int, (v_led ->> 'sweeps')::int, j.client_version, v_rv)
      on conflict (account_id, season_week, battles) do update
        set snapshot = excluded.snapshot, season_wins = excluded.season_wins, hearts = excluded.hearts,
            season_sweeps = excluded.season_sweeps, client_version = excluded.client_version,
            rules_ver = excluded.rules_ver, uploaded_at = now();
  end if;
  -- ★2026-10-27 配对局 B 那一边（胜负与 A 互反）：战绩账本 / 快照池 / 第 4 胜报名，与上面 A 的写法逐条相同。
  --   B 删号了（b_account 随删号断开）⇒ 只记 A。
  if v_pair and j.b_account is not null then
    insert into public.gauntlet_records (season_week, account_id, gw, gl)
      values (j.season_week, j.b_account, case when won then 0 else 1 end, case when won then 1 else 0 end)
      on conflict (season_week, account_id) do update
        set gw = public.gauntlet_records.gw + excluded.gw, gl = public.gauntlet_records.gl + excluded.gl, updated_at = now()
      returning gw, gl into v_gw_b, v_gl_b;
    res := res || jsonb_build_object('gw_b', v_gw_b, 'gl_b', v_gl_b);
    v_rv := coalesce(v_rv,
                     case when jsonb_typeof(j.meta->'rules_ver') = 'number' then (j.meta->>'rules_ver')::numeric::int end,
                     (select rv.rules_ver from public.referee_versions rv where rv.client_version = j.client_version), 0);
    insert into public.gauntlet_ghosts (account_id, season_week, gw, gl, snapshot, client_version, rules_ver)
      values (j.b_account, j.season_week, v_gw_b, v_gl_b, j.b_snapshot, j.client_version, v_rv)
      on conflict (account_id, season_week, gw, gl) do update
        set snapshot = excluded.snapshot, client_version = excluded.client_version, rules_ver = excluded.rules_ver,
            uploaded_at = now();
    if v_gw_b >= 4 and not exists (select 1 from public.finals_buckets fb where fb.season_week = j.season_week) then
      insert into public.finals_pending (season_week, account_id, name, snapshot, gw, gl)
        values (j.season_week, j.b_account, coalesce(nullif(j.b_snapshot->'profile'->>'name', ''), '?'), j.b_snapshot, v_gw_b, v_gl_b)
        on conflict (season_week, account_id) do nothing;
    end if;
  end if;
  -- 录像：与客户端上传同一行形状（replay_uploader.build_row）；right_account 周六恒 null（对手可能是机器人，同客户端口径）
  -- ★2026-10-27 配对局 right_account = B（真人或陪练号，都是真账号，填了不露馅）；旧路 / 机器人池兜底仍是 null
  -- ★2026-11-01 积分赛 right_account = null（同客户端：对手可能是陪练 / 机器人）
  insert into public.matches (match_id, season_week, phase, left_account, right_account, seed,
      left_snapshot, right_snapshot, result, client_version, replay)
    values (j.match_id, j.season_week, j.kind, j.a_account,
            case when j.kind = 'finals' or v_pair then j.b_account end, j.seed,
            j.a_snapshot - 'is_bot' - 'ghost_id', j.b_snapshot - 'is_bot' - 'ghost_id',
            res, j.client_version, p_result->>'replay_b64')
    on conflict (match_id) do nothing;
  -- ★2026-10-27 这一局配出来的排队行（配对局两行 / 兜底局一行）⇒ done。旧路任务没有排队行，这一句什么都不改。
  update public.gauntlet_queue set status = 'done', updated_at = now() where job_id = p_job_id and status = 'paired';
  -- ★2026-10-20d 周日任务的账本多一个 coins_b（右方 B 的战斗内铸币；周六不记）
  --   ★2026-10-27 配对局也记（B 的战斗内铸币，B 查 referee_job_status 时回给它）
  update public.referee_jobs
     set status = 'done', done_at = now(), error = case when superseded then 'superseded' end,
         result = (p_result - 'replay_b64') || jsonb_build_object('ledger', res || jsonb_build_object('coins', v_coins)
                  || case when j.kind = 'finals' or v_pair then jsonb_build_object('coins_b', v_coins_b) else '{}'::jsonb end)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'superseded', superseded);
end $$;
revoke all on function public.referee_complete(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;

-- ⑦ 查一局算完没有（以 20261027 版为底；★2026-11-01 只在 A 的回包尾巴上多一段：积分赛局回 kind / ranked（账本）/ seed（开算后））
--   seed：裁判一开算，结果已由任务（双方快照 + 种子）定死；给自己那一局的种子只用来跟播（手机按种子选同一张地图，不算）。
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
              then jsonb_build_object('incense', j.result->'incense_b') else '{}'::jsonb end;
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

-- ⑧ 周榜：有账本的人按账本（服务端记的）排，没账本的（切换之前的自报快照）照旧。
--   以 20261024b（page）/ 20261010（v3）版为底：筛快照那一段逐字不动（latest → gh），多一层 left join ranked_records，
--   胜 / 余命 / 横扫 / 场次 = coalesce(账本, 快照)；排序 / 分页 / 权限 / 键名一个字不动。
create or replace function public.week_leaderboard_page(p_week bigint, p_offset int default 0, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; off int; tot int; page jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  off := greatest(coalesce(p_offset, 0), 0);
  with gh as (
    select distinct on (g.account_id)
           g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles, g.uploaded_at,
           g.snapshot -> 'profile' ->> 'name' as name,
           g.snapshot -> 'profile' ->> 'tag'  as tag,
           public.snapshot_lead(g.snapshot)   as lead
      from public.ghosts g
     where g.season_week = p_week
       and left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'
       and coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'
       and coalesce(g.snapshot -> 'gl_w', '0'::jsonb) = '0'::jsonb
       and coalesce(g.snapshot -> 'gl_l', '0'::jsonb) = '0'::jsonb
     order by g.account_id, g.battles desc, g.uploaded_at desc
  ), latest as (
    select gh.account_id, coalesce(rr.wins, gh.season_wins) as season_wins, coalesce(rr.hearts, gh.hearts) as hearts,
           coalesce(rr.sweeps, gh.season_sweeps) as season_sweeps, coalesce(rr.battles, gh.battles) as battles,
           gh.uploaded_at, gh.name, gh.tag, gh.lead
      from gh
      left join public.ranked_records rr on rr.season_week = p_week and rr.account_id = gh.account_id
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
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, '')) order by r.rk) filter (where r.rk > off and r.rk <= off + lim), '[]'::jsonb),
         (jsonb_agg(jsonb_build_object(
             'rank', r.rk, 'name', coalesce(r.name, '?'), 'tag', coalesce(r.tag, ''),
             'account_id', r.account_id, 'wins', r.season_wins, 'hearts', r.hearts,
             'sweeps', r.season_sweeps, 'battles', r.battles,
             'title', coalesce(r.title, ''), 'lead', coalesce(r.lead, ''))) filter (where r.account_id = auth.uid())) -> 0
    into tot, page, mine
    from ranked r;
  return jsonb_build_object('ok', true, 'week', p_week, 'total', tot, 'offset', off,
    'rows', page, 'me', mine);
end $$;

revoke all on function public.week_leaderboard_page(bigint, int, int) from public;
revoke execute on function public.week_leaderboard_page(bigint, int, int) from anon;
grant execute on function public.week_leaderboard_page(bigint, int, int) to authenticated;

create or replace function public.week_leaderboard(p_week bigint, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int; tot int; top jsonb; mine jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  lim := least(greatest(coalesce(p_limit, 30), 1), 100);
  with gh as (
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
  ), latest as (
    select gh.account_id, coalesce(rr.wins, gh.season_wins) as season_wins, coalesce(rr.hearts, gh.hearts) as hearts,
           coalesce(rr.sweeps, gh.season_sweeps) as season_sweeps, coalesce(rr.battles, gh.battles) as battles,
           gh.uploaded_at, gh.name, gh.tag
      from gh
      left join public.ranked_records rr on rr.season_week = p_week and rr.account_id = gh.account_id
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

-- ⑨ 收回客户端写积分赛成绩：ghosts 两条写策略、matches 写策略（phase = 'ranked'）加 ranked_client_write 闸。
--   开关开着（默认）⇒ 与改之前逐字等价；关掉 ⇒ 客户端 insert / update ghosts、insert 积分赛 matches 一律被行级策略拒绝，
--   只剩 referee_complete（security definer）写得进。
drop policy if exists ghosts_write_own on public.ghosts;
create policy ghosts_write_own on public.ghosts
  for insert with check (account_id = auth.uid() and public.client_version_ok(client_version)
                         and public.ranked_client_write_ok());

drop policy if exists ghosts_update_own on public.ghosts;
create policy ghosts_update_own on public.ghosts
  for update using (account_id = auth.uid())
  with check (account_id = auth.uid() and public.client_version_ok(client_version) and public.ranked_client_write_ok());

drop policy if exists matches_write_own on public.matches;
create policy matches_write_own on public.matches
  for insert with check ((left_account = auth.uid() or right_account = auth.uid())
                         and (phase <> 'ranked' or public.ranked_client_write_ok()));

-- ⑩ 领活：真人的积分赛局先算（以 20261019 版为底，只改 order by 那一行）。
--   陪练号（bot_accounts）平日 6 个同时打、一局只要几十秒，全进 FIFO 会把真人排在一串陪练号后面；
--   周末没有积分赛局 ⇒ 这一行对周六 / 周日的排序结果没有任何影响（false 恒在前，退化成原来的 created_at, job_id）。
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
     order by (kind = 'ranked' and exists (select 1 from public.bot_accounts b where b.account_id = a_account)),
              created_at, job_id
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

-- ⑪ 开关下发（以 20261019c 版为底，只多一个键 ranked_on；老客户端不认这个键 ⇒ 无害）
create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on(),
                            'stream_on', coalesce((select c.stream_on from public.referee_config c where c.id = 1), false),
                            'stream_version', coalesce((select c.stream_version from public.referee_config c where c.id = 1), ''),
                            'ranked_on', public.referee_ranked_on())
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END ranked_referee 20261101d <<<

-- >>> BEGIN econ_ops 20261106 >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济流水上服务器（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.2 / §4.4 · S3）
--   用户 11-06「装备要改成伏击机装了，这个要做。」（伏击机装 = 服务器记账）
--   改之前：深海币 / 背包 / 身上装备 / 货架 / 卡池 / 大轮等级 / 小木斧 / 糖果罐全在客户端存档里，快照自报 ⇒ 改存档 = 直接抢钱
--     （擂台赛押的是主站真币、严格零和）。客户端 S1 / S2 已把每一笔都记成流水（scripts/gamedata/econ_ledger.gd）。
-- 本段（★纯新增：新表 + 两个新函数，不改任何现行函数 / 表 ⇒ 执行本段不改变任何现行行为）：
--   ① econ_ops：每人每周的流水，(账号, 周, 序号) 为主键、只能追加。src = client（客户端传上来的）/ server（服务器发种子时写下的那一条）。
--     客户端只读自己的行；写只经 econ_commit（security definer），没有 insert / update 策略。
--   ② econ_commit(周, 起始序号, 操作数组, 种类)：一次往返做两件事 ——
--     a. 上传：起始序号必须接在已有的后面（拒断号）；已有的那几条（重传）必须与原来一致；服务器写下的种子行 ⇒ 种类与种子必须一致
--        （一致就把客户端那一份整条换上去：多出来的 bt 等字段补齐，src 仍记 server）。
--     b. 要种子（种类 = roll / refresh / candy）：只发在「紧接着已上传流水的下一条」，发的同时把这一条写进流水 ⇒ 这一笔就算发生了。
--        ★防「挑种子」：每个序号只有一个种子（同一序号再要 ⇒ 回原来那个，重试幂等）；不能预先要后面的种子再倒过来安排前面的操作。
--        ★拿到种子却没用上（闪退）⇒ 服务器账上照样发生，本机下次对齐时按服务器的来（S4）。
--   周 = 服务器当下这一周（app_now 的周一 00:00 UTC，与客户端 week_anchor_utc 同一个口径）；不是这一周的一律 'week'（回服务器的周）。
-- ─────────────────────────────────────────────────────────────

create table if not exists public.econ_ops (
  account_id  uuid        not null references auth.users(id) on delete cascade,
  week        bigint      not null,
  seq         int         not null check (seq >= 0 and seq < 50000),
  op          jsonb       not null,
  src         text        not null default 'client' check (src in ('client', 'server')),
  created_at  timestamptz not null default now(),
  primary key (account_id, week, seq)
);
alter table public.econ_ops enable row level security;
drop policy if exists econ_ops_self on public.econ_ops;
create policy econ_ops_self on public.econ_ops for select using (auth.uid() = account_id);
-- 写只有 econ_commit（security definer），没有 insert / update / delete 策略

-- 服务器当下这一周（周一 00:00 UTC 的 unix 秒）
create or replace function public.econ_week_now() returns bigint
language sql stable security definer set search_path = public as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
revoke all on function public.econ_week_now() from public, anon, authenticated;

create or replace function public.econ_commit(p_week bigint, p_from int, p_ops jsonb, p_kind text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_wk   bigint := public.econ_week_now();
  v_next int;
  v_n    int;
  v_i    int;
  v_op   jsonb;
  v_row  public.econ_ops%rowtype;
  v_at   int;
  v_seed bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  if p_week is distinct from v_wk then
    return jsonb_build_object('ok', false, 'reason', 'week', 'week', v_wk);
  end if;
  if p_ops is null or jsonb_typeof(p_ops) <> 'array' or p_from is null then
    return jsonb_build_object('ok', false, 'reason', 'bad_ops');
  end if;
  v_n := jsonb_array_length(p_ops);
  if v_n > 500 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;
  if p_kind is not null and p_kind not in ('roll', 'refresh', 'candy') then
    return jsonb_build_object('ok', false, 'reason', 'bad_kind');
  end if;
  perform pg_advisory_xact_lock(hashtext('econ_commit:' || v_uid::text));   -- 同一个号的提交排队(两台设备同时传)
  select coalesce(max(seq) + 1, 0) into v_next from public.econ_ops where account_id = v_uid and week = v_wk;
  if p_from < 0 or p_from > v_next then
    return jsonb_build_object('ok', false, 'reason', 'gap', 'next', v_next);
  end if;
  if p_from + v_n >= 50000 then
    return jsonb_build_object('ok', false, 'reason', 'full', 'next', v_next);
  end if;
  -- a. 上传。★两遍: 先全部校验 / 比对(一个字不写), 全过才写 —— 返回错误不会回滚已经插进去的行(检查脚本 A6 抓到过「整批不落」被破)
  for v_i in 0 .. v_n - 1 loop
    v_op := p_ops -> v_i;
    v_at := p_from + v_i;
    if jsonb_typeof(v_op) <> 'object' or length(v_op::text) > 4000 or coalesce(v_op ->> 'op', '') = '' then
      return jsonb_build_object('ok', false, 'reason', 'bad_op', 'at', v_at, 'next', v_next);
    end if;
    if v_at < v_next then
      select * into v_row from public.econ_ops where account_id = v_uid and week = v_wk and seq = v_at;
      if v_row.src = 'server' then
        if (v_op ->> 'op') is distinct from (v_row.op ->> 'op') or (v_op ->> 'seed') is distinct from (v_row.op ->> 'seed') then
          return jsonb_build_object('ok', false, 'reason', 'mismatch', 'at', v_at, 'next', v_next);
        end if;
      elsif v_row.op is distinct from v_op then
        return jsonb_build_object('ok', false, 'reason', 'mismatch', 'at', v_at, 'next', v_next);
      end if;
    end if;
  end loop;
  for v_i in 0 .. v_n - 1 loop
    v_op := p_ops -> v_i;
    v_at := p_from + v_i;
    if v_at < v_next then
      -- 服务器写下的种子行: 种类与种子已核对过 ⇒ 换成客户端那一份(补齐 bt 等), 仍记 server
      update public.econ_ops set op = v_op
        where account_id = v_uid and week = v_wk and seq = v_at and src = 'server' and op is distinct from v_op;
    else
      insert into public.econ_ops (account_id, week, seq, op, src) values (v_uid, v_wk, v_at, v_op, 'client');
    end if;
  end loop;
  v_next := greatest(v_next, p_from + v_n);
  if p_kind is null then
    return jsonb_build_object('ok', true, 'next', v_next);
  end if;
  -- b. 要种子: 发在客户端眼里的「下一条」(= p_from + v_n)
  v_at := p_from + v_n;
  if v_at < v_next then
    -- 这个序号已经有了: 是我先前发给这一种的种子(请求超时重试)⇒ 原样再回; 否则这个位置已经是别的操作
    select * into v_row from public.econ_ops where account_id = v_uid and week = v_wk and seq = v_at;
    if v_row.src = 'server' and (v_row.op ->> 'op') = p_kind then
      return jsonb_build_object('ok', true, 'seq', v_at, 'seed', (v_row.op ->> 'seed')::bigint, 'again', true, 'next', v_next);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'taken', 'at', v_at, 'next', v_next);
  end if;
  v_seed := ('x' || lpad(substr(md5(gen_random_uuid()::text), 1, 8), 16, '0'))::bit(64)::bigint;   -- 0 .. 2^32-1
  insert into public.econ_ops (account_id, week, seq, op, src)
    values (v_uid, v_wk, v_at, jsonb_build_object('op', p_kind, 'seed', v_seed), 'server');
  return jsonb_build_object('ok', true, 'seq', v_at, 'seed', v_seed, 'next', v_at + 1);
end $$;
revoke all on function public.econ_commit(bigint, int, jsonb, text) from public, anon;
grant execute on function public.econ_commit(bigint, int, jsonb, text) to authenticated;
-- <<< END econ_ops 20261106 <<<

-- >>> BEGIN econ_flag 20261106b >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账的总开关 econ_on（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.6 · S3）
--   同 ranked_on 的做法：开关默认关 ⇒ 执行本段不改变任何现行行为。客户端见 referee_flags().econ_on 开着，
--   掷货 / 刷新 / 开糖果罐才向服务器要种子（econ_commit）、流水才往上传；关着 ⇒ 本机种子、不上传（与 0.22.8 一字不差）。
--   方案书 §4.6：在周一换周时打开（那一刻所有人清零，正好是重放起点）；内测服先开一整周对账（S5），正式服开要用户点头。
-- 本段：① referee_config 多一列 econ_on（默认 false）② referee_econ_on() ③ referee_flags() 多回 econ_on（其余五项原样）
-- ─────────────────────────────────────────────────────────────
alter table public.referee_config add column if not exists econ_on boolean not null default false;

create or replace function public.referee_econ_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select econ_on from public.referee_config where id = 1), false)
$$;
revoke all on function public.referee_econ_on() from public, anon, authenticated;

create or replace function public.referee_flags()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('finals_on', public.referee_finals_on(),
                            'gauntlet_on', public.referee_gauntlet_on(),
                            'stream_on', coalesce((select c.stream_on from public.referee_config c where c.id = 1), false),
                            'stream_version', coalesce((select c.stream_version from public.referee_config c where c.id = 1), ''),
                            'ranked_on', public.referee_ranked_on(),
                            'econ_on', public.referee_econ_on())
$$;
revoke all on function public.referee_flags() from public;
grant execute on function public.referee_flags() to anon, authenticated;
-- <<< END econ_flag 20261106b <<<

-- >>> BEGIN econ_state 20261106c >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账 · 服务器重放结果 + 开局比对（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 · S4b）
--   用户 11-06「装备要改成伏击机装了，这个要做。」（伏击机装 = 服务器记账）
--   S3 起流水在 econ_ops 里；裁判机（轮询器 + 无头 Godot `--econ-replay`，同一份 EconLedger.apply）从本周开局重放出权威状态，写进这里；
--   积分赛开局 / 周六进队时拿快照比 —— 改存档多塞一件装备、自报大轮等级 / 小木斧 / 宝箱 / 香火 ⇒ 拒。
-- 本段（★开关 econ_on 关着 ⇒ econ_check 恒回 null ⇒ 两个开局函数行为一字不变）：
--   ① econ_state：每人每周一行 = 重放到第几条（seen）/ 成交几条 / 第一条不合法的序号与原因 / 资产与宝箱香火的规整结果 / 按来源汇总的收入
--   ② econ_replay_claim / econ_replay_done：只给 service_role（裁判机轮询器）。只重放到「服务器发了种子、客户端还没传回带 bt 的那一条」之前
--   ③ econ_check(号, 周, 快照)：null = 对得上；否则 {ok:false, reason: econ_pending / econ_invalid / econ_mismatch, …}
--   ④ econ_truncate(周, 序号)：重放判了第 N 条不合法 ⇒ 客户端认了服务器那一份（本机按服务器流水重放对齐）之后，把第 N 条起作废
--   ⑤ referee_ranked_start / gauntlet_queue_join：以现行版为底逐字照抄，只在标了「2026-11-06」的地方插 econ_check
-- ─────────────────────────────────────────────────────────────

create table if not exists public.econ_state (
  account_id  uuid        not null references auth.users(id) on delete cascade,
  week        bigint      not null,
  seen        int         not null default 0,       -- 重放时用了这一周的前几条流水
  upto        int         not null default 0,       -- 其中成交了几条
  bad_at      int         not null default -1,      -- 第一条不合法 / 不成交的序号（-1 = 全过）
  why         text        not null default '',
  assets      jsonb       not null default '{}',    -- EconLedger.assets_of 的结果（与客户端同一把尺子）
  progress    jsonb       not null default '{}',    -- EconLedger.progress_of（宝箱 / 香火）
  income      jsonb       not null default '{}',    -- 按来源汇总的收入 {src: {coins, xp, n}}（S4b-2 对服务器自己的账）
  fp          text        not null default '',
  updated_at  timestamptz not null default now(),
  primary key (account_id, week)
);
alter table public.econ_state enable row level security;
drop policy if exists econ_state_self on public.econ_state;
create policy econ_state_self on public.econ_state for select using (auth.uid() = account_id);
create index if not exists econ_ops_week_idx on public.econ_ops (week, account_id);

-- ② 领活：本周「可重放的前缀」比 econ_state.seen 长的号。前缀 = 按序号到第一条「服务器写下的种子行、客户端还没传回」之前
--   （那一条缺 bt，重放时场次戳是错的）。每次给整份前缀（一周几百条，纯计算）。
create or replace function public.econ_replay_claim(p_limit int default 20) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_wk bigint := public.econ_week_now(); v_out jsonb := '[]'::jsonb; r record; v_pre int;
        v_lim int := greatest(1, least(coalesce(p_limit, 20), 200));
begin
  for r in
    select o.account_id, count(*)::int as n,
           min(o.seq) filter (where o.src = 'server' and not (o.op ? 'bt')) as cut,
           coalesce(max(s.seen), -1) as seen
      from public.econ_ops o
      left join public.econ_state s on s.account_id = o.account_id and s.week = o.week
     where o.week = v_wk
     group by o.account_id
  loop
    v_pre := coalesce(r.cut, r.n);
    continue when v_pre <= r.seen;
    v_out := v_out || jsonb_build_array(jsonb_build_object('account_id', r.account_id, 'week', v_wk, 'seen', v_pre,
      'rows', coalesce((select jsonb_agg(op || jsonb_build_object('seq', seq) order by seq) from public.econ_ops
                         where account_id = r.account_id and week = v_wk and seq < v_pre), '[]'::jsonb)));
    exit when jsonb_array_length(v_out) >= v_lim;
  end loop;
  return v_out;
end $$;
revoke all on function public.econ_replay_claim(int) from public, anon, authenticated;
grant execute on function public.econ_replay_claim(int) to service_role;

-- 回写：[{account_id, week, seen, result:{upto, bad_at, why, assets, progress, income, fp}}]。只往前走（seen 不倒退）。
create or replace function public.econ_replay_done(p_items jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare it jsonb; r jsonb; n int := 0;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_items');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := it -> 'result';
    continue when jsonb_typeof(r) <> 'object' or (it ->> 'account_id') is null;
    insert into public.econ_state as s (account_id, week, seen, upto, bad_at, why, assets, progress, income, fp, updated_at)
      values ((it ->> 'account_id')::uuid, (it ->> 'week')::bigint, (it ->> 'seen')::int,
              coalesce((r ->> 'upto')::int, 0), coalesce((r ->> 'bad_at')::int, -1), coalesce(r ->> 'why', ''),
              coalesce(r -> 'assets', '{}'), coalesce(r -> 'progress', '{}'), coalesce(r -> 'income', '{}'),
              coalesce(r ->> 'fp', ''), now())
      on conflict (account_id, week) do update
        set seen = excluded.seen, upto = excluded.upto, bad_at = excluded.bad_at, why = excluded.why,
            assets = excluded.assets, progress = excluded.progress, income = excluded.income, fp = excluded.fp,
            updated_at = now()
        where s.seen <= excluded.seen;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;
revoke all on function public.econ_replay_done(jsonb) from public, anon, authenticated;
grant execute on function public.econ_replay_done(jsonb) to service_role;

-- 一组装备的规整串：每件「id|星」排序后逗号连（不看 chg 等其它键；星 1.0 与 1 同一个）
create or replace function public.econ_items_key(p_items jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ',' order by k), '')
    from (select (x ->> 'id') || '|' || coalesce(round((x ->> 'star')::numeric)::int, 1)::text as k
            from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) x
           where jsonb_typeof(x) = 'object') t
$$;
-- 快照里小将身上的装备（top / bottom 两路全部小将；空的不算）⇒ 每只一串、排序后分号连
create or replace function public.econ_snapshot_minions_key(p_snap jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(m -> 'equips') as k
            from jsonb_each(case when jsonb_typeof(p_snap -> 'minions') = 'object' then p_snap -> 'minions' else '{}'::jsonb end) l,
                 jsonb_array_elements(case when jsonb_typeof(l.value) = 'array' then l.value else '[]'::jsonb end) m) t
   where k <> ''
$$;
-- 重放结果里小将那一份（assets.minions = 每只一个 JSON 串 {"eq": [...], "lv": n}）⇒ 同一种规整串
create or replace function public.econ_state_minions_key(p_assets jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(case when jsonb_typeof(m) = 'string' then (m #>> '{}')::jsonb else m end -> 'eq') as k
            from jsonb_array_elements(case when jsonb_typeof(p_assets -> 'minions') = 'array' then p_assets -> 'minions' else '[]'::jsonb end) m) t
   where k <> ''
$$;

-- ③ 开局比对。null = 对得上（或开关关着）；否则回拒收原因（客户端：pending ⇒ 先传流水再自动重交；mismatch / invalid ⇒ 按服务器流水对齐）
create or replace function public.econ_check(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_n int; s public.econ_state%rowtype; v_found boolean; v_a jsonb; v_p jsonb; v_pid text; v_what text := '';
begin
  if not public.referee_econ_on() then
    return null;
  end if;
  select count(*)::int into v_n from public.econ_ops where account_id = p_uid and week = p_week;
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  v_found := found;
  if v_n > 0 and (not v_found or s.seen < v_n) then
    return jsonb_build_object('ok', false, 'reason', 'econ_pending', 'have', case when v_found then s.seen else 0 end, 'need', v_n);
  end if;
  if v_found and s.bad_at >= 0 then
    return jsonb_build_object('ok', false, 'reason', 'econ_invalid', 'at', s.bad_at, 'why', s.why);
  end if;
  v_a := case when v_found then s.assets else '{}'::jsonb end;     -- 一条流水都没有 = 本周开局(全空)
  v_p := case when v_found then s.progress else '{}'::jsonb end;
  if coalesce(round((p_snap ->> 'season_level')::numeric)::int, 1) <> coalesce(round((v_a ->> 'lv')::numeric)::int, 1) then
    v_what := 'lv';
  elsif coalesce(round((p_snap ->> 'axe_exp_total')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 1)::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'axe_stage')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 2)::numeric)::int, 0)
     or coalesce(p_snap ->> 'axe_final', '') <> coalesce(v_a -> 'axe' ->> 3, '') then
    v_what := 'axe';
  elsif coalesce((p_snap ->> 'chest_treasure_value')::numeric, 0) <> coalesce((v_p ->> 'cv')::numeric, 0)
     or coalesce(p_snap -> 'chest_treasures_won', '[]'::jsonb) <> coalesce(v_p -> 'cw', '[]'::jsonb) then
    v_what := 'chest';
  elsif coalesce(round((p_snap ->> 'incense_marks')::numeric)::int, 0) <> coalesce(round((v_p ->> 'im')::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'incense_charge')::numeric)::int, 0) <> coalesce(round((v_p ->> 'ic')::numeric)::int, 0) then
    v_what := 'incense';
  elsif public.econ_snapshot_minions_key(p_snap) <> public.econ_state_minions_key(v_a) then
    v_what := 'minions';
  else
    for v_pid in select jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' else '[]'::jsonb end) loop
      if public.econ_items_key(p_snap -> 'equipped' -> v_pid) <> public.econ_items_key(v_a -> 'worn' -> v_pid) then
        v_what := 'worn:' || v_pid;
        exit;
      end if;
    end loop;
  end if;
  if v_what <> '' then
    return jsonb_build_object('ok', false, 'reason', 'econ_mismatch', 'what', v_what);
  end if;
  return null;
end $$;
revoke all on function public.econ_check(uuid, bigint, jsonb) from public, anon, authenticated;

-- ④ 认了服务器那一份之后把第 N 条起作废（只能截在服务器判出来的那一条上）
create or replace function public.econ_truncate(p_week bigint, p_at int) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid := auth.uid(); s public.econ_state%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  select * into s from public.econ_state where account_id = uid and week = p_week for update;
  if not found or s.bad_at < 0 or s.bad_at is distinct from p_at then
    return jsonb_build_object('ok', false, 'reason', 'not_invalid');
  end if;
  delete from public.econ_ops where account_id = uid and week = p_week and seq >= p_at;
  update public.econ_state set seen = p_at, bad_at = -1, why = '', updated_at = now() where account_id = uid and week = p_week;
  return jsonb_build_object('ok', true, 'next', p_at);
end $$;
revoke all on function public.econ_truncate(bigint, int) from public, anon;
grant execute on function public.econ_truncate(bigint, int) to authenticated;

-- ⑤ 积分赛开局（以 20261101d 版为底逐字照抄，只改标了 2026-11-06 的两处）
create or replace function public.referee_ranked_start(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; led jsonb; v_b int; ex record; v_key text;
        pk jsonb; jid bigint; mid uuid; st text; v_snap_a jsonb; v_snap_b jsonb; v_meta jsonb;
        v_econ jsonb;   -- 2026-11-06 局外经济记账
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_ranked_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false)
     or coalesce(public.semver_arr(v_cv), array[0, 0, 0, 0]) < public.semver_arr(public.ranked_min_client()) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week is distinct from extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.ranked_window_open(p_week) then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536
     or not public.referee_lineup_ok(p_snapshot) then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot');
  end if;
  -- 有一场在算 ⇒ 回那一场（不再建）
  select * into ex from public.referee_jobs
   where kind = 'ranked' and season_week = p_week and a_account = uid and status in ('pending', 'claimed')
   order by job_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'in_flight', true,
      'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', public.ranked_ledger_peek(uid, p_week));
  end if;
  led := public.ranked_ledger_peek(uid, p_week);
  v_b := (led ->> 'battles')::int;
  -- = 主菜单 _battle_block_msg：出局（0 命）/ 配额满；回账本让客户端对齐
  if (led ->> 'hearts')::int <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'eliminated', 'ledger', led);
  end if;
  if (led ->> 'used')::int >= public.ranked_quota() then
    return jsonb_build_object('ok', false, 'reason', 'quota_full', 'ledger', led);
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机账与服务端对不上 ⇒ 回账本，客户端以它为准）
  if p_match_no is distinct from v_b then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'ledger', led);
  end if;
  -- ★2026-11-06 局外经济记账(方案书 20261106 §4.5 S4b; 开关 econ_on 关着 ⇒ econ_check 回 null, 这里一字不变):
  --   快照里的身上装备 / 大轮等级 / 小木斧 / 宝箱 / 香火必须 = 服务器按流水重放的结果; 回账本让客户端照旧对齐
  v_econ := public.econ_check(uid, p_week, p_snapshot);
  if v_econ is not null then
    return v_econ || jsonb_build_object('ledger', led);
  end if;
  -- 账本落行（切换那一周第一次开战：从旧自报快照补种；新的一周：0 场满命）
  insert into public.ranked_records (season_week, account_id, battles, wins, hearts, sweeps, eggs, used, seeded)
    values (p_week, uid, v_b, (led ->> 'wins')::int, (led ->> 'hearts')::int, (led ->> 'sweeps')::int,
            (led ->> 'eggs')::int, (led ->> 'used')::int, led ->> 'seeded')
    on conflict (season_week, account_id) do nothing;
  v_snap_a := public.ranked_stamp_snapshot(p_snapshot, led, v_b);
  v_key := format('ranked:%s:%s:%s', p_week, uid, v_b);
  select * into ex from public.referee_jobs where match_key = v_key for update;
  if found then
    if ex.status <> 'failed' then
      return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'status', ex.status,
        'opp', public.referee_opp_card(ex.b_snapshot), 'ledger', led);
    end if;
    v_snap_b := ex.b_snapshot;
    v_meta := ex.meta;
    if ex.error = 'b_bad_snapshot' then
      v_meta := v_meta || jsonb_build_object('opp_prev',
        coalesce(v_meta -> 'opp_prev', '[]'::jsonb) || to_jsonb(coalesce(v_meta ->> 'opp', '')));
      update public.referee_jobs set meta = v_meta where job_id = ex.job_id;   -- 先记下坏的那个, 重挑时排除
      pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
      if pk is null then
        return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
      end if;
      v_snap_b := pk -> 'snap';
      v_meta := v_meta || jsonb_build_object('opp', pk ->> 'opp', 'pick', pk ->> 'pick');
      update public.referee_jobs set b_account = (pk ->> 'account')::uuid where job_id = ex.job_id;
    end if;
    update public.referee_jobs
       set status = 'pending', attempts = 0, error = null, claimed_by = null, claimed_at = null, done_at = null,
           client_version = v_cv,
           a_snapshot = case when ex.error = 'a_bad_snapshot' then v_snap_a else a_snapshot end,
           level = case when ex.error = 'a_bad_snapshot' then public.referee_level_of(v_snap_a) else level end,
           b_snapshot = v_snap_b, meta = v_meta || jsonb_build_object('rules_ver', v_rv), created_at = now()
     where job_id = ex.job_id;
    return jsonb_build_object('ok', true, 'job_id', ex.job_id, 'match_id', ex.match_id, 'retry', true,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  pk := public.referee_ranked_pick(uid, p_week, v_b, v_rv, public.referee_ranked_opp_ex(uid, p_week));
  if pk is null then
    return jsonb_build_object('ok', false, 'reason', 'no_opponent', 'ledger', led);
  end if;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('ranked', v_key, p_week, v_cv, public.referee_new_seed(), uid, (pk ->> 'account')::uuid,
      v_snap_a, pk -> 'snap', public.referee_level_of(v_snap_a),
      jsonb_build_object('account', uid, 'battles0', v_b, 'opp', pk ->> 'opp', 'pick', pk ->> 'pick',
                         'rules_ver', v_rv, 'server_pick', true))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    -- 同一刻另一个请求先建了（双击）：把那一场还给他
    select job_id, match_id, status, b_snapshot into jid, mid, st, v_snap_b from public.referee_jobs where match_key = v_key;
    return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid, 'status', st,
      'opp', public.referee_opp_card(v_snap_b), 'ledger', led);
  end if;
  return jsonb_build_object('ok', true, 'job_id', jid, 'match_id', mid,
    'opp', public.referee_opp_card(pk -> 'snap'), 'ledger', led);
end $$;
revoke all on function public.referee_ranked_start(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.referee_ranked_start(bigint, jsonb, int, text, int) to authenticated;

-- ⑤ 周六进队（以 20261027 版为底逐字照抄，只改标了 2026-11-06 的两处）
create or replace function public.gauntlet_queue_join(p_week bigint, p_snapshot jsonb, p_match_no int,
    p_client_version text default null, p_rules_ver int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cv text; v_rv int; v_found boolean; v_gw int := 0; v_gl int := 0;
        ex record; v_id bigint;
        v_econ jsonb;   -- 2026-11-06 局外经济记账
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if not public.referee_gauntlet_on() then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  v_cv := coalesce(nullif(p_client_version, ''), public.request_client_version());
  select rules_ver, true into v_rv, v_found from public.referee_versions where client_version = v_cv and enabled;
  if not coalesce(v_found, false) then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if v_rv is not null and p_rules_ver is not null and p_rules_ver <> v_rv then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  v_rv := coalesce(v_rv, p_rules_ver);
  if v_rv is null or v_rv < 1 then
    return jsonb_build_object('ok', false, 'reason', 'update_required');
  end if;
  if p_week <> extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week');
  end if;
  if not public.gauntlet_window_open(p_week) then
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
  perform public.gauntlet_queue_void_failed(p_week, uid);
  select * into ex from public.referee_jobs
   where kind = 'gauntlet' and season_week = p_week and status in ('pending', 'claimed')
     and (a_account = uid or (b_account = uid and meta->>'pair' = 'true'))
   order by job_id limit 1;
  if found then
    select id into v_id from public.gauntlet_queue where job_id = ex.job_id and account_id = uid order by id desc limit 1;
    if v_id is not null then
      return public.gauntlet_queue_view(v_id) || jsonb_build_object('in_flight', true);
    end if;
    return jsonb_build_object('ok', true, 'status', 'paired', 'in_flight', true, 'gw', v_gw, 'gl', v_gl,
      'waited_sec', 0, 'job_id', ex.job_id, 'match_id', ex.match_id, 'job_status', ex.status,
      'side', case when ex.a_account = uid then 'a' else 'b' end,
      'opp', public.referee_opp_card(case when ex.a_account = uid then ex.b_snapshot else ex.a_snapshot end));
  end if;
  -- 我要打的第 N 场必须正好是账本上的下一场（本机战绩落后 = 上一场的账没补上 ⇒ 回账本上的数）
  if p_match_no is distinct from v_gw + v_gl then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'gw', v_gw, 'gl', v_gl);
  end if;
  -- ★2026-11-06 局外经济记账(同 referee_ranked_start 那一处)
  v_econ := public.econ_check(uid, p_week, p_snapshot);
  if v_econ is not null then
    return v_econ || jsonb_build_object('gw', v_gw, 'gl', v_gl);
  end if;
  -- 我自己那条心跳断了的旧 waiting ⇒ expired（重新排、重新计时）
  update public.gauntlet_queue set status = 'expired', updated_at = now()
   where season_week = p_week and account_id = uid and status = 'waiting'
     and last_seen < now() - make_interval(secs => public.gauntlet_queue_ttl_sec());
  insert into public.gauntlet_queue (season_week, account_id, gw, gl, rules_ver, client_version, snapshot)
    values (p_week, uid, v_gw, v_gl, v_rv, v_cv, p_snapshot)
    on conflict (season_week, account_id) where status = 'waiting' do update
      set gw = excluded.gw, gl = excluded.gl, rules_ver = excluded.rules_ver, client_version = excluded.client_version,
          snapshot = excluded.snapshot, last_seen = now(), updated_at = now()
    returning id into v_id;
  perform public.gauntlet_queue_advance(v_id);
  return public.gauntlet_queue_view(v_id);
end $$;
revoke all on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) from public, anon;
grant execute on function public.gauntlet_queue_join(bigint, jsonb, int, text, int) to authenticated;
-- <<< END econ_state 20261106c <<<
-- >>> BEGIN ranked_ledger_weekend 20261106d >>>
-- ─────────────────────────────────────────────────────────────
-- 积分赛账本周六周日不回给客户端（2026-11-06）
--   服务端账本只有积分赛那几场；周六 / 周日客户端的场次与胜场还含闯关 / 决赛。
--   现行客户端（0.22.7）每次回主菜单都拿账本覆盖本机 ⇒ 探针：周六 17 场 12 胜 → 16 场 11 胜（货架不换货、援军小将场次加成少算）。
--   客户端 0.22.8 起自己不在周末问；本段管 0.22.7（周六 00:00 UTC 起回 {ok:false, reason:weekend}，客户端见 err 什么都不动）。
--   ranked_any_day（内测服彩排）放开星期几，这里同样放开。开战 / 结算自带的账本（referee_ranked_start / referee_complete）不受影响。
-- ─────────────────────────────────────────────────────────────
create or replace function public.referee_ranked_ledger(p_week bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  if public.app_now() >= to_timestamp(p_week + 5 * 86400)
     and not coalesce((select c.ranked_any_day from public.referee_config c where c.id = 1), false) then
    return jsonb_build_object('ok', false, 'reason', 'weekend');
  end if;
  return jsonb_build_object('ok', true, 'week', p_week, 'ledger', public.ranked_ledger_peek(auth.uid(), p_week));
end $$;
revoke all on function public.referee_ranked_ledger(bigint) from public, anon;
grant execute on function public.referee_ranked_ledger(bigint) to authenticated;
-- <<< END ranked_ledger_weekend 20261106d <<<
-- >>> BEGIN econ_facts 20261106e >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账 · 收入核服务器账本 + 标脏领活（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 · S4b）
--   用户 11-06「装备要改成伏击机装了，这个要做。」（伏击机装 = 服务器记账）
--   20261106c 已上内测服，本段是它之后的改动：
--   ① econ_state 加 dirty：有新流水没重放（领活只看它，不每 2 秒聚合全表）
--   ② econ_prefix：可重放的前缀 = 到第一条「服务器发了种子、客户端还没传回带 bt」之前；econ_check 比到它（闪退留下的尾部种子行不再卡开局）
--   ③ econ_facts：本周服务器账本的事实（只汇总、不含游戏规则；规则常量全在 EconReplay.check_income，服务器不抄第二份），领活时带上；
--      收入超过账本 ⇒ 重放当场判那一条不合法（从那条起作废），走 econ_invalid，不另设拒收原因
--   ④ econ_check 多比统领、宝箱值允许 0.01 误差（小数经 JSON 往返末位会变）
--   开关 econ_on 关着 ⇒ econ_check 恒回 null，开局行为一字不变。
-- ─────────────────────────────────────────────────────────────
alter table public.econ_state add column if not exists dirty boolean not null default false;   -- 有新流水没重放
create index if not exists econ_state_dirty_idx on public.econ_state (week, updated_at) where dirty;

-- ② 可重放的前缀 = 到第一条「服务器写下的种子行、客户端还没传回」之前（那一条缺 bt，重放时场次戳是错的）。种子行只可能在尾部：
--   服务器只给紧接着的下一条发种子，客户端不传回它就传不了后面的。
create or replace function public.econ_prefix(p_uid uuid, p_week bigint) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(min(seq) filter (where src = 'server' and not (op ? 'bt')), count(*))::int
    from public.econ_ops where account_id = p_uid and week = p_week
$$;
revoke all on function public.econ_prefix(uuid, bigint) from public, anon, authenticated;

-- 流水一动就标脏（econ_commit 不用改；领活不扫全表）
create or replace function public.econ_ops_touch() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.econ_state (account_id, week, dirty)
    select distinct account_id, week, true from new_rows
    on conflict (account_id, week) do update set dirty = true;
  return null;
end $$;
revoke all on function public.econ_ops_touch() from public, anon, authenticated;
drop trigger if exists econ_ops_touch_ins on public.econ_ops;
create trigger econ_ops_touch_ins after insert on public.econ_ops
  referencing new table as new_rows for each statement execute function public.econ_ops_touch();
drop trigger if exists econ_ops_touch_upd on public.econ_ops;
create trigger econ_ops_touch_upd after update on public.econ_ops
  referencing new table as new_rows for each statement execute function public.econ_ops_touch();

-- 本周服务器账本的事实，重放（EconReplay.check_income）拿它核流水里的收入。★只汇总，不含游戏规则。
--   ranked：ranked_records 那一行。gauntlet / finals：这个号算完的裁判局（配对局 B 方取 coins_b / chest_b / incense_b、胜负取反；
--   旧路任务的 b_account 是被打的那份快照的主人，不是在场的人 ⇒ 不算）。chest / incense：每一局结束时的结果单。
create or replace function public.econ_facts(p_uid uuid, p_week bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  with j as (
    select kind, a_account = p_uid as is_a, result
      from public.referee_jobs
     where season_week = p_week and status = 'done' and result is not null
       and (a_account = p_uid or (b_account = p_uid and (kind = 'finals' or meta ->> 'pair' = 'true')))
  ), m as (
    select kind,
           (coalesce((result -> 'ledger' ->> 'won')::boolean, false) = is_a) as won,
           coalesce((result -> 'ledger' ->> case when is_a then 'coins' else 'coins_b' end)::numeric, 0)::int as minted,
           result -> case when is_a then 'chest' else 'chest_b' end as chest,
           result -> case when is_a then 'incense' else 'incense_b' end as incense
      from j
  )
  select jsonb_build_object(
    'ranked', coalesce((select jsonb_build_object('n', r.battles, 'w', r.wins, 'coins', r.coins, 'used', r.used)
                          from public.ranked_records r where r.season_week = p_week and r.account_id = p_uid),
                       '{"n":0,"w":0,"coins":0,"used":0}'::jsonb),
    'gauntlet', jsonb_build_object('n', count(*) filter (where kind = 'gauntlet'),
                                   'w', count(*) filter (where kind = 'gauntlet' and won),
                                   'minted', coalesce(sum(minted) filter (where kind = 'gauntlet'), 0)),
    'finals', jsonb_build_object('n', count(*) filter (where kind = 'finals'),
                                 'w', count(*) filter (where kind = 'finals' and won),
                                 'minted', coalesce(sum(minted) filter (where kind = 'finals'), 0)),
    'chest', coalesce(jsonb_agg(chest) filter (where jsonb_typeof(chest) = 'object'), '[]'::jsonb),
    'incense', coalesce(jsonb_agg(incense) filter (where jsonb_typeof(incense) = 'object'), '[]'::jsonb))
    from m
$$;
revoke all on function public.econ_facts(uuid, bigint) from public, anon, authenticated;

-- 领活：只看标脏的号。每次给整份前缀 + 事实（一周几百条，纯计算）。领走时碰一下 updated_at：算不出来的号排到后面，不堵别人。
create or replace function public.econ_replay_claim(p_limit int default 20) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_wk bigint := public.econ_week_now(); v_out jsonb := '[]'::jsonb; r record; v_pre int;
        v_lim int := greatest(1, least(coalesce(p_limit, 20), 200));
begin
  for r in
    select s.account_id, s.seen from public.econ_state s
     where s.week = v_wk and s.dirty order by s.updated_at
  loop
    v_pre := public.econ_prefix(r.account_id, v_wk);
    if v_pre <= r.seen then
      update public.econ_state set dirty = false where account_id = r.account_id and week = v_wk;   -- 只多了一条没传回的种子行
      continue;
    end if;
    update public.econ_state set updated_at = now() where account_id = r.account_id and week = v_wk;
    v_out := v_out || jsonb_build_array(jsonb_build_object('account_id', r.account_id, 'week', v_wk, 'seen', v_pre,
      'facts', public.econ_facts(r.account_id, v_wk),
      'rows', coalesce((select jsonb_agg(op || jsonb_build_object('seq', seq) order by seq) from public.econ_ops
                         where account_id = r.account_id and week = v_wk and seq < v_pre), '[]'::jsonb)));
    exit when jsonb_array_length(v_out) >= v_lim;
  end loop;
  return v_out;
end $$;
revoke all on function public.econ_replay_claim(int) from public, anon, authenticated;
grant execute on function public.econ_replay_claim(int) to service_role;

-- 回写：[{account_id, week, seen, result:{upto, bad_at, why, assets, progress, income, fp}}]。只往前走（seen 不倒退）；
--   算的时候又来了新流水 ⇒ 仍是脏的，下一轮再领。
create or replace function public.econ_replay_done(p_items jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare it jsonb; r jsonb; n int := 0; v_uid uuid; v_wk bigint; v_seen int;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_items');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := it -> 'result';
    continue when jsonb_typeof(r) <> 'object' or (it ->> 'account_id') is null;
    v_uid := (it ->> 'account_id')::uuid;
    v_wk := (it ->> 'week')::bigint;
    v_seen := (it ->> 'seen')::int;
    insert into public.econ_state as s (account_id, week, seen, upto, bad_at, why, assets, progress, income, fp, dirty, updated_at)
      values (v_uid, v_wk, v_seen,
              coalesce((r ->> 'upto')::int, 0), coalesce((r ->> 'bad_at')::int, -1), coalesce(r ->> 'why', ''),
              coalesce(r -> 'assets', '{}'), coalesce(r -> 'progress', '{}'), coalesce(r -> 'income', '{}'),
              coalesce(r ->> 'fp', ''), public.econ_prefix(v_uid, v_wk) > v_seen, now())
      on conflict (account_id, week) do update
        set seen = excluded.seen, upto = excluded.upto, bad_at = excluded.bad_at, why = excluded.why,
            assets = excluded.assets, progress = excluded.progress, income = excluded.income, fp = excluded.fp,
            dirty = excluded.dirty, updated_at = now()
        where s.seen <= excluded.seen;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;
revoke all on function public.econ_replay_done(jsonb) from public, anon, authenticated;
grant execute on function public.econ_replay_done(jsonb) to service_role;

-- ③ 开局比对。null = 对得上（或开关关着）；否则回拒收原因（客户端：pending ⇒ 先传流水再自动重交；mismatch / invalid ⇒ 按服务器流水对齐）
create or replace function public.econ_check(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pre int; s public.econ_state%rowtype; v_found boolean; v_a jsonb; v_p jsonb; v_pid text; v_what text := '';
begin
  if not public.referee_econ_on() then
    return null;
  end if;
  -- ★比到「可重放的前缀」：尾部那条没传回的种子行（闪退，方案书 R9）不算没追上，否则客户端传无可传、永远 pending
  v_pre := public.econ_prefix(p_uid, p_week);
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  v_found := found;
  if v_pre > 0 and (not v_found or s.seen < v_pre) then
    return jsonb_build_object('ok', false, 'reason', 'econ_pending', 'have', case when v_found then s.seen else 0 end, 'need', v_pre);
  end if;
  if v_found and s.bad_at >= 0 then
    return jsonb_build_object('ok', false, 'reason', 'econ_invalid', 'at', s.bad_at, 'why', s.why);
  end if;
  v_a := case when v_found then s.assets else '{}'::jsonb end;     -- 一条流水都没有 = 本周开局(全空)
  v_p := case when v_found then s.progress else '{}'::jsonb end;
  if coalesce(round((p_snap ->> 'season_level')::numeric)::int, 1) <> coalesce(round((v_a ->> 'lv')::numeric)::int, 1) then
    v_what := 'lv';
  elsif coalesce(round((p_snap ->> 'axe_exp_total')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 1)::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'axe_stage')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 2)::numeric)::int, 0)
     or coalesce(p_snap ->> 'axe_final', '') <> coalesce(v_a -> 'axe' ->> 3, '') then
    v_what := 'axe';
  elsif abs(coalesce((p_snap ->> 'chest_treasure_value')::numeric, 0) - coalesce((v_p ->> 'cv')::numeric, 0)) > 0.01   -- 小数经 JSON 往返末位会变
     or coalesce(p_snap -> 'chest_treasures_won', '[]'::jsonb) <> coalesce(v_p -> 'cw', '[]'::jsonb) then
    v_what := 'chest';
  elsif coalesce(round((p_snap ->> 'incense_marks')::numeric)::int, 0) <> coalesce(round((v_p ->> 'im')::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'incense_charge')::numeric)::int, 0) <> coalesce(round((v_p ->> 'ic')::numeric)::int, 0) then
    v_what := 'incense';
  elsif public.econ_snapshot_minions_key(p_snap) <> public.econ_state_minions_key(v_a) then
    v_what := 'minions';
  else
    for v_pid in select jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' else '[]'::jsonb end) loop
      if not coalesce(v_a -> 'leaders', '[]'::jsonb) ? v_pid then
        v_what := 'leader:' || v_pid;     -- 本大轮锁定的统领里没有它
        exit;
      end if;
      if public.econ_items_key(p_snap -> 'equipped' -> v_pid) <> public.econ_items_key(v_a -> 'worn' -> v_pid) then
        v_what := 'worn:' || v_pid;
        exit;
      end if;
    end loop;
  end if;
  if v_what <> '' then
    return jsonb_build_object('ok', false, 'reason', 'econ_mismatch', 'what', v_what);
  end if;
  return null;
end $$;
revoke all on function public.econ_check(uuid, bigint, jsonb) from public, anon, authenticated;

-- ④ 认了服务器那一份之后把第 N 条起作废（只能截在服务器判出来的那一条上）
create or replace function public.econ_truncate(p_week bigint, p_at int) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid := auth.uid(); s public.econ_state%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;
  select * into s from public.econ_state where account_id = uid and week = p_week for update;
  if not found or s.bad_at < 0 or s.bad_at is distinct from p_at then
    return jsonb_build_object('ok', false, 'reason', 'not_invalid');
  end if;
  delete from public.econ_ops where account_id = uid and week = p_week and seq >= p_at;
  update public.econ_state set seen = p_at, bad_at = -1, why = '', dirty = false, updated_at = now() where account_id = uid and week = p_week;
  return jsonb_build_object('ok', true, 'next', p_at);
end $$;
revoke all on function public.econ_truncate(bigint, int) from public, anon;
grant execute on function public.econ_truncate(bigint, int) to authenticated;
-- <<< END econ_facts 20261106e <<<
-- >>> BEGIN axe_kills_status 20261106f >>>
-- ─────────────────────────────────────────────────────────────
-- 服务器局的小木斧击杀经验带回客户端（2026-11-06）
--   用户 10-22 定「买 22 / 打完一局 10 / 击杀 6」。积分赛上裁判机后击杀经验只在裁判机的工作副本上涨，结果单不带 ⇒ 没了
--   （正式服 527 个相邻两局经验增量里 0 个带 +6；探针重跑真任务 1122：340 → 352，结果单 33 个键里没有斧头）。
--   裁判结果单 0.22.8 起带 axe_kills / axe_kills_b；本段把它回给客户端（referee_complete 存整份结果单，不用改）。
--   以现行版为底逐字照抄，只改标了 2026-11-06 的地方；结果单没这个键（老裁判）⇒ 回包一个键都不多。
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
              then jsonb_build_object('axe_kills', j.result->'axe_kills_b') else '{}'::jsonb end;
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
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null; inc jsonb := null; ak jsonb := null;
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
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end
    || case when jsonb_typeof(inc) = 'object' then jsonb_build_object('incense', inc) else '{}'::jsonb end
    || case when jsonb_typeof(ak) = 'number' then jsonb_build_object('axe_kills', ak) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;
-- <<< END axe_kills_status 20261106f <<<
-- >>> BEGIN econ_axe_temp 20261106g >>>
-- ─────────────────────────────────────────────────────────────
-- 局外经济记账 · 认识服务器局的斧头经验与临时等级（2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md）
--   今天查出的两个服务器局缺口修好之后，记账要跟上：
--   ① econ_facts 多回 axe.kills（结果单 axe_kills / axe_kills_b 的合计）：流水里的 axe_exp 按它核，不再一律不认
--   ② econ_check 多比临时等级器：统领 temp_levels、小将 temp_lv（快照现在带这两样，裁判会用）
--   开关 econ_on 关着 ⇒ econ_check 恒回 null，开局行为一字不变。
-- ─────────────────────────────────────────────────────────────
create or replace function public.econ_facts(p_uid uuid, p_week bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  with j as (
    select kind, a_account = p_uid as is_a, result
      from public.referee_jobs
     where season_week = p_week and status = 'done' and result is not null
       and (a_account = p_uid or (b_account = p_uid and (kind = 'finals' or meta ->> 'pair' = 'true')))
  ), m as (
    select kind,
           (coalesce((result -> 'ledger' ->> 'won')::boolean, false) = is_a) as won,
           coalesce((result -> 'ledger' ->> case when is_a then 'coins' else 'coins_b' end)::numeric, 0)::int as minted,
           result -> case when is_a then 'chest' else 'chest_b' end as chest,
           result -> case when is_a then 'incense' else 'incense_b' end as incense,
           coalesce((result ->> case when is_a then 'axe_kills' else 'axe_kills_b' end)::numeric, 0)::int as axe_kills
      from j
  )
  select jsonb_build_object(
    'ranked', coalesce((select jsonb_build_object('n', r.battles, 'w', r.wins, 'coins', r.coins, 'used', r.used)
                          from public.ranked_records r where r.season_week = p_week and r.account_id = p_uid),
                       '{"n":0,"w":0,"coins":0,"used":0}'::jsonb),
    'gauntlet', jsonb_build_object('n', count(*) filter (where kind = 'gauntlet'),
                                   'w', count(*) filter (where kind = 'gauntlet' and won),
                                   'minted', coalesce(sum(minted) filter (where kind = 'gauntlet'), 0)),
    'finals', jsonb_build_object('n', count(*) filter (where kind = 'finals'),
                                 'w', count(*) filter (where kind = 'finals' and won),
                                 'minted', coalesce(sum(minted) filter (where kind = 'finals'), 0)),
    'axe', jsonb_build_object('kills', coalesce(sum(axe_kills), 0)),
    'chest', coalesce(jsonb_agg(chest) filter (where jsonb_typeof(chest) = 'object'), '[]'::jsonb),
    'incense', coalesce(jsonb_agg(incense) filter (where jsonb_typeof(incense) = 'object'), '[]'::jsonb))
    from m
$$;
revoke all on function public.econ_facts(uuid, bigint) from public, anon, authenticated;

-- 小将那一份的规整串多带临时等级（装备串 @ 等级）：临时等级器用在小将身上也要比
create or replace function public.econ_snapshot_minions_key(p_snap jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(m -> 'equips') || '@' || coalesce(round((m ->> 'temp_lv')::numeric)::int, 0)::text as k
            from jsonb_each(case when jsonb_typeof(p_snap -> 'minions') = 'object' then p_snap -> 'minions' else '{}'::jsonb end) l,
                 jsonb_array_elements(case when jsonb_typeof(l.value) = 'array' then l.value else '[]'::jsonb end) m) t
   where k <> '@0'
$$;
create or replace function public.econ_state_minions_key(p_assets jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ';' order by k), '')
    from (select public.econ_items_key(j -> 'eq') || '@' || coalesce(round((j ->> 'lv')::numeric)::int, 0)::text as k
            from (select case when jsonb_typeof(m) = 'string' then (m #>> '{}')::jsonb else m end as j
                    from jsonb_array_elements(case when jsonb_typeof(p_assets -> 'minions') = 'array' then p_assets -> 'minions' else '[]'::jsonb end) m) s) t
   where k <> '@0'
$$;

-- ③ 开局比对。null = 对得上（或开关关着）；否则回拒收原因（客户端：pending ⇒ 先传流水再自动重交；mismatch / invalid ⇒ 按服务器流水对齐）
create or replace function public.econ_check(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pre int; s public.econ_state%rowtype; v_found boolean; v_a jsonb; v_p jsonb; v_pid text; v_what text := '';
begin
  if not public.referee_econ_on() then
    return null;
  end if;
  -- ★比到「可重放的前缀」：尾部那条没传回的种子行（闪退，方案书 R9）不算没追上，否则客户端传无可传、永远 pending
  v_pre := public.econ_prefix(p_uid, p_week);
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  v_found := found;
  if v_pre > 0 and (not v_found or s.seen < v_pre) then
    return jsonb_build_object('ok', false, 'reason', 'econ_pending', 'have', case when v_found then s.seen else 0 end, 'need', v_pre);
  end if;
  if v_found and s.bad_at >= 0 then
    return jsonb_build_object('ok', false, 'reason', 'econ_invalid', 'at', s.bad_at, 'why', s.why);
  end if;
  v_a := case when v_found then s.assets else '{}'::jsonb end;     -- 一条流水都没有 = 本周开局(全空)
  v_p := case when v_found then s.progress else '{}'::jsonb end;
  if coalesce(round((p_snap ->> 'season_level')::numeric)::int, 1) <> coalesce(round((v_a ->> 'lv')::numeric)::int, 1) then
    v_what := 'lv';
  elsif coalesce(round((p_snap ->> 'axe_exp_total')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 1)::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'axe_stage')::numeric)::int, 0) <> coalesce(round((v_a -> 'axe' ->> 2)::numeric)::int, 0)
     or coalesce(p_snap ->> 'axe_final', '') <> coalesce(v_a -> 'axe' ->> 3, '') then
    v_what := 'axe';
  elsif abs(coalesce((p_snap ->> 'chest_treasure_value')::numeric, 0) - coalesce((v_p ->> 'cv')::numeric, 0)) > 0.01   -- 小数经 JSON 往返末位会变
     or coalesce(p_snap -> 'chest_treasures_won', '[]'::jsonb) <> coalesce(v_p -> 'cw', '[]'::jsonb) then
    v_what := 'chest';
  elsif coalesce(round((p_snap ->> 'incense_marks')::numeric)::int, 0) <> coalesce(round((v_p ->> 'im')::numeric)::int, 0)
     or coalesce(round((p_snap ->> 'incense_charge')::numeric)::int, 0) <> coalesce(round((v_p ->> 'ic')::numeric)::int, 0) then
    v_what := 'incense';
  elsif public.econ_snapshot_minions_key(p_snap) <> public.econ_state_minions_key(v_a) then
    v_what := 'minions';
  else
    for v_pid in select jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array' then p_snap -> 'leaders' else '[]'::jsonb end) loop
      if not coalesce(v_a -> 'leaders', '[]'::jsonb) ? v_pid then
        v_what := 'leader:' || v_pid;     -- 本大轮锁定的统领里没有它
        exit;
      end if;
      if coalesce(round((p_snap -> 'temp_levels' ->> v_pid)::numeric)::int, 0) <> coalesce(round((v_a -> 'tl' ->> v_pid)::numeric)::int, 0) then
        v_what := 'temp:' || v_pid;       -- 临时等级器: 报的和流水不一样
        exit;
      end if;
      if public.econ_items_key(p_snap -> 'equipped' -> v_pid) <> public.econ_items_key(v_a -> 'worn' -> v_pid) then
        v_what := 'worn:' || v_pid;
        exit;
      end if;
    end loop;
  end if;
  if v_what <> '' then
    return jsonb_build_object('ok', false, 'reason', 'econ_mismatch', 'what', v_what);
  end if;
  return null;
end $$;
revoke all on function public.econ_check(uuid, bigint, jsonb) from public, anon, authenticated;
-- <<< END econ_axe_temp 20261106g <<<
-- >>> BEGIN wheel_status 20261106h >>>
-- ─────────────────────────────────────────────────────────────
-- 赌神命运之轮一大轮内累积（2026-11-06）
--   设计：一大轮内逐渐成长、换轮清零。积分赛上裁判机后两头都断了：快照不带、裁判开局恒空；结果单不带、客户端存档不涨 ⇒ 每局从 0 开始。
--   裁判结果单 0.22.8 起带 wheel_new / wheel_new_b；本段把它回给客户端（referee_complete 存整份结果单，不用改）。
--   以 20261106f 版为底逐字照抄，只改标了 2026-11-06 命运之轮的地方；结果单没这个键（老裁判）⇒ 回包一个键都不多。
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
              then jsonb_build_object('wheel_new', j.result->'wheel_new_b') else '{}'::jsonb end;
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
declare uid uuid := auth.uid(); b record; j record; v jsonb; c int := 0; ch jsonb := null; inc jsonb := null; ak jsonb := null; wn jsonb := null;
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
  end if;
  return jsonb_build_object('ok', true, 'status', 'done', 'coins', c)
    || case when jsonb_typeof(ch) = 'object' then jsonb_build_object('chest', ch) else '{}'::jsonb end
    || case when jsonb_typeof(inc) = 'object' then jsonb_build_object('incense', inc) else '{}'::jsonb end
    || case when jsonb_typeof(ak) = 'number' then jsonb_build_object('axe_kills', ak) else '{}'::jsonb end
    || case when jsonb_typeof(wn) = 'object' then jsonb_build_object('wheel_new', wn) else '{}'::jsonb end;
end $$;
revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;
grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;
-- <<< END wheel_status 20261106h <<<

-- >>> BEGIN mainsite_core 20261109a >>>
-- ─────────────────────────────────────────────────────────────
-- 龟投账号绑定 + 拥有龟缓存 + 发件箱（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.1 / §4.3 / §4.8；
--   网关与发件箱的原始设计 docs/plans/20261105c-主站对接偷袭.md §4.1 / §4.6 D38；主站接口 docs/specs/龟战主站整体方案.md §6）
--
-- 本文件做六件事：
--   ① mainsite_accounts：账号 ↔ 主站用户（主站对外编码 ID，如 GEACjjPJERy）。一个号最多绑一个主站用户，一个主站用户最多绑一个号。
--   ② mainsite_codes：App 登录码（5 分钟、一次性，带设备型号给主站确认页显示）。
--      mainsite_link_start / mainsite_link_info / mainsite_link_confirm / mainsite_link_poll —— 网关调（service_role）。
--   ③ mainsite_pets：主站 /player 返回的拥有龟缓存。mainsite_pets_put（网关调）/ mainsite_status（网关调）/ mainsite_me()（App 调）。
--   ④ mainsite_outbox：所有「我们调主站」的写请求先进这里，referee_poller.py 的 outbox_loop 发。
--      mainsite_outbox_put（其他 security definer 函数内部调）/ mainsite_outbox_claim / mainsite_outbox_mark（outbox_loop 调）。
--      发送顺序：按 id；同一 raidId 的 started / settle 一条道、同一 userId 的 defense / pet-level / unlinked 一条道，
--      道里前一条没完成（done_at 为空）后一条不发；settle 另外要等同 raidId 的 started 完成（不论谁的 id 小）。
--      重试（方案书 §4.8）：只对连不上、5xx、401 退避重试；HTTP 200 + ok:false 记下 last_status 后停（done_at 也写上 = 终态）。
--   ⑤ 换绑与删号：已绑在别的号上的主站用户来确认 ⇒ result = switched（网关给 App 签那个号的登录态）；
--      这个号原先绑着另一个主站用户 ⇒ 改绑（rebound），给旧的那个发 unlinked、清掉拥有龟缓存；
--      主站用户重新绑上时，他还没发出去的 unlinked 作废（superseded），免得晚到的解绑把新绑定冲掉。
--   ⑥ account_delete_self()：以 20261020b 版为底，删号前已绑定 ⇒ 写一条 unlinked 发件箱（没绑 ⇒ 不写）。其余一字不动。
--
-- ★表一律开 RLS、不建 policy、revoke 掉 anon / authenticated：客户端读不到也写不进，只经下面的函数。
--   App 只有 mainsite_me() 一个入口（authenticated）；其余全是 service_role（网关 / 裁判轮询器）。
-- ★本文件只建表 / 建函数 / 改写一个函数，不删任何已有数据。重复执行安全（沙盒里 schema.sql 末尾同段会先跑一遍）。
-- ★上线前跑 server/supabase/tests/20261109a_mainsite_core_check.sql（整段一个事务，结尾必回滚）。
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 绑定 ═══
create table if not exists public.mainsite_accounts (
  account_id       uuid        primary key references public.accounts(account_id) on delete cascade,
  mainsite_user_id text        not null unique
                               check (mainsite_user_id ~ '^[0-9A-Za-z]{4,32}$' and mainsite_user_id !~ '^[0-9]+$'),
  is_bot           boolean     not null default false,
  linked_at        timestamptz not null default now(),
  pets_fetched_at  timestamptz            -- 上次成功从主站 /player 取到拥有龟的时刻（一只都没有时也记）
);
alter table public.mainsite_accounts enable row level security;
revoke all on public.mainsite_accounts from anon, authenticated, public;

-- ═══ ② 登录码 ═══
create table if not exists public.mainsite_codes (
  code             text        primary key check (code ~ '^[A-Za-z0-9_-]{4,64}$'),
  account_id       uuid        not null references auth.users(id) on delete cascade,
  device           text        not null default '' check (char_length(device) <= 128),
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null,
  mainsite_user_id text,
  confirmed_at     timestamptz,
  result           text        check (result in ('bound', 'same', 'switched', 'rebound')),
  target_account   uuid        references auth.users(id) on delete set null
);
create index if not exists mainsite_codes_account_idx on public.mainsite_codes (account_id, created_at desc);
alter table public.mainsite_codes enable row level security;
revoke all on public.mainsite_codes from anon, authenticated, public;

-- ═══ ③ 拥有龟缓存 ═══
create table if not exists public.mainsite_pets (
  account_id uuid        not null references public.mainsite_accounts(account_id) on delete cascade,
  pet_key    text        not null check (pet_key ~ '^[a-z0-9_]{1,32}$'),
  fetched_at timestamptz not null default now(),
  primary key (account_id, pet_key)
);
alter table public.mainsite_pets enable row level security;
revoke all on public.mainsite_pets from anon, authenticated, public;

-- ═══ ④ 发件箱 ═══
create table if not exists public.mainsite_outbox (
  id          bigserial   primary key,
  topic       text        not null check (topic in ('defense', 'pet-level', 'started', 'settle', 'unlinked')),
  idem_key    text        not null check (idem_key <> ''),
  body        jsonb       not null check (jsonb_typeof(body) = 'object'),
  attempts    int         not null default 0,
  next_at     timestamptz not null default now(),
  done_at     timestamptz,
  last_status text,
  reply       jsonb,
  created_at  timestamptz not null default now(),
  unique (topic, idem_key)
);
create index if not exists mainsite_outbox_open_idx on public.mainsite_outbox (id) where done_at is null;
alter table public.mainsite_outbox enable row level security;
revoke all on public.mainsite_outbox from anon, authenticated, public;

-- 一条发件属于哪条「道」（道内按 id 顺序、前一条完成才发后一条）。
create or replace function public.mainsite_outbox_lane(p_topic text, p_body jsonb) returns text
language sql immutable as $$
  select case when p_topic in ('started', 'settle') then 'raid:' || coalesce(p_body->>'raidId', '')
              else 'user:' || coalesce(p_body->>'userId', '') end
$$;
revoke all on function public.mainsite_outbox_lane(text, jsonb) from public, anon, authenticated;

-- 写一条发件。同 (topic, idem_key) 重复写 = 不动。
--   ★业务规矩在这里统一挡（调用方不用各自再判）：defense / pet-level 只在这个 userId 已绑定时写；
--     pet-level 只写主站 /player 返回过的龟（mainsite_pets 里有）、等级 1 ~ 10。不满足 ⇒ 静默不写。
--   ★调用写错（主题不认识 / 幂等键空 / 缺 raidId 或 userId）⇒ 抛异常（门禁里当场红，不悄悄吞掉）。
create or replace function public.mainsite_outbox_put(p_topic text, p_key text, p_body jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare lv text;
begin
  if p_topic is null or p_topic not in ('defense', 'pet-level', 'started', 'settle', 'unlinked') then
    raise exception 'mainsite_outbox_put: bad topic %', p_topic;
  end if;
  if coalesce(p_key, '') = '' or p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'mainsite_outbox_put: empty key or body is not an object (topic %)', p_topic;
  end if;
  if p_topic in ('started', 'settle') and coalesce(p_body->>'raidId', '') = '' then
    raise exception 'mainsite_outbox_put: % without raidId', p_topic;
  end if;
  if p_topic in ('defense', 'pet-level', 'unlinked') and coalesce(p_body->>'userId', '') = '' then
    raise exception 'mainsite_outbox_put: % without userId', p_topic;
  end if;
  if p_topic in ('defense', 'pet-level')
     and not exists (select 1 from public.mainsite_accounts where mainsite_user_id = p_body->>'userId') then
    return;
  end if;
  if p_topic = 'pet-level' then
    lv := p_body->>'level';
    if lv is null or lv !~ '^[0-9]{1,3}$' or lv::int not between 1 and 10 then
      return;
    end if;
    if not exists (select 1 from public.mainsite_accounts a
                     join public.mainsite_pets p on p.account_id = a.account_id
                    where a.mainsite_user_id = p_body->>'userId' and p.pet_key = p_body->>'petKey') then
      return;
    end if;
  end if;
  insert into public.mainsite_outbox (topic, idem_key, body) values (p_topic, p_key, p_body)
    on conflict (topic, idem_key) do nothing;
end $$;
revoke all on function public.mainsite_outbox_put(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.mainsite_outbox_put(text, text, jsonb) to service_role;

-- 领一批该发的（outbox_loop 调）：没完成、到点、道里前面没有没完成的、settle 的 started 已完成。
--   ★settle 比 started 先写（id 更小）时 started 不被它挡（否则两条互等，谁也发不出去）。
--   领到的 next_at 推后 p_lease_sec 秒当租期（发送方中途挂了 ⇒ 租期过后重发；主站各接口按 raidId / userId 幂等）。
--   返回 jsonb 数组，按 id 升序。
create or replace function public.mainsite_outbox_claim(p_limit int default 20, p_lease_sec int default 120)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_out jsonb;
begin
  with c as (
    select o.id from public.mainsite_outbox o
     where o.done_at is null and o.next_at <= now()
       and not exists (select 1 from public.mainsite_outbox e
                        where e.done_at is null and e.id < o.id
                          and public.mainsite_outbox_lane(e.topic, e.body) = public.mainsite_outbox_lane(o.topic, o.body)
                          and not (o.topic = 'started' and e.topic = 'settle'))
       and not (o.topic = 'settle' and exists (select 1 from public.mainsite_outbox s
                        where s.topic = 'started' and s.done_at is null and s.body->>'raidId' = o.body->>'raidId'))
     order by o.id
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), u as (
    update public.mainsite_outbox o
       set next_at = now() + make_interval(secs => greatest(10, coalesce(p_lease_sec, 120)))
      from c where o.id = c.id
    returning o.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'topic', u.topic, 'idem_key', u.idem_key,
                                               'body', u.body, 'attempts', u.attempts) order by u.id), '[]'::jsonb)
    into v_out from u;
  return v_out;
end $$;
revoke all on function public.mainsite_outbox_claim(int, int) from public, anon, authenticated;
grant execute on function public.mainsite_outbox_claim(int, int) to service_role;

-- 记一次发送结果（outbox_loop 调）。p_retry_sec 为空 ⇒ 终态（成功，或 HTTP 200 + ok:false）：done_at = now()；
--   否则（连不上 / 5xx / 401）attempts + 1、next_at = now() + p_retry_sec。回包整个存进 reply（started 的回包带新 expireAt）。
create or replace function public.mainsite_outbox_mark(p_id bigint, p_status text, p_reply jsonb, p_retry_sec int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.mainsite_outbox
     set attempts = attempts + 1,
         last_status = left(coalesce(p_status, ''), 300),
         reply = coalesce(p_reply, reply),
         done_at = case when p_retry_sec is null then now() else null end,
         next_at = case when p_retry_sec is null then next_at
                        else now() + make_interval(secs => greatest(1, least(p_retry_sec, 3600))) end
   where id = p_id and done_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n = 1, 'done', p_retry_sec is null);
end $$;
revoke all on function public.mainsite_outbox_mark(bigint, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.mainsite_outbox_mark(bigint, text, jsonb, int) to service_role;

-- ═══ ② 登录码（网关调）═══
-- App 点「龟投账号登录」→ 网关生成随机码（Python secrets）→ 本函数登记。同一个号同时只有一个有效码（新码作废旧码）；
--   每号每小时最多 30 个（防刷）。码 5 分钟过期。
create or replace function public.mainsite_link_start(p_account uuid, p_code text, p_device text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_account is null or not exists (select 1 from auth.users where id = p_account) then
    return jsonb_build_object('ok', false, 'error', 'no_account');
  end if;
  if p_code is null or p_code !~ '^[A-Za-z0-9_-]{4,64}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  perform pg_advisory_xact_lock(hashtext('mainsite_link_start:' || p_account::text));
  delete from public.mainsite_codes where created_at < now() - interval '1 day';
  select count(*) into n from public.mainsite_codes where account_id = p_account and created_at > now() - interval '1 hour';
  if n >= 30 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  update public.mainsite_codes set expires_at = now()
   where account_id = p_account and confirmed_at is null and expires_at > now();
  insert into public.mainsite_codes (code, account_id, device, expires_at)
    values (p_code, p_account, left(btrim(coalesce(p_device, '')), 128), now() + interval '5 minutes')
    on conflict (code) do nothing;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'code_taken');
  end if;
  return jsonb_build_object('ok', true, 'code', p_code, 'expires_in', 300);
end $$;
revoke all on function public.mainsite_link_start(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mainsite_link_start(uuid, text, text) to service_role;

-- 主站确认页查设备型号（主站 GET /mainsite/link/info）。码不对 / 过期 / 已用 ⇒ ok:false（主站一律当「登录码无效」）。
create or replace function public.mainsite_link_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d text;
begin
  select device into d from public.mainsite_codes
   where code = p_code and confirmed_at is null and expires_at > now();
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  return jsonb_build_object('ok', true, 'device', d);
end $$;
revoke all on function public.mainsite_link_info(text) from public, anon, authenticated;
grant execute on function public.mainsite_link_info(text) to service_role;

-- 主站确认登录（主站 POST /mainsite/link/confirm {code, user_id}）。
--   这个主站用户已绑在这个号上 ⇒ same；绑在别的号上 ⇒ switched（App 轮询时网关签那个号的登录态）；
--   还没绑 ⇒ 绑到这个号（bound）；这个号原先绑着另一个主站用户 ⇒ 改绑（rebound，旧的那个发 unlinked）。
--   ★一次性：同一个码只能确认一次；主站重试（同一个 user_id 再来一次）回同一个结果，换个 user_id ⇒ ok:false。
create or replace function public.mainsite_link_confirm(p_code text, p_user_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; tgt uuid; cur text; res text;
begin
  if p_user_id is null or p_user_id !~ '^[0-9A-Za-z]{4,32}$' or p_user_id ~ '^[0-9]+$' then
    return jsonb_build_object('ok', false, 'error', 'bad userId');
  end if;
  select * into c from public.mainsite_codes where code = p_code for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  if c.confirmed_at is not null then
    if c.mainsite_user_id = p_user_id then
      return jsonb_build_object('ok', true, 'result', c.result, 'account', c.target_account::text);
    end if;
    return jsonb_build_object('ok', false, 'error', 'code_used');
  end if;
  if c.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired');
  end if;
  -- 同一个主站用户 / 同一个号的并发确认串行化
  perform pg_advisory_xact_lock(hashtext('mainsite_user:' || p_user_id));
  perform pg_advisory_xact_lock(hashtext('mainsite_account:' || c.account_id::text));
  select account_id into tgt from public.mainsite_accounts where mainsite_user_id = p_user_id;
  if tgt is not null and tgt = c.account_id then
    res := 'same';
  elsif tgt is not null then
    res := 'switched';
  else
    insert into public.accounts (account_id) values (c.account_id) on conflict (account_id) do nothing;
    select mainsite_user_id into cur from public.mainsite_accounts where account_id = c.account_id;
    if cur is not null then
      update public.mainsite_accounts set mainsite_user_id = p_user_id, linked_at = now(), pets_fetched_at = null
       where account_id = c.account_id;
      delete from public.mainsite_pets where account_id = c.account_id;
      perform public.mainsite_outbox_put('unlinked', 'rebind:' || c.account_id::text || ':' || cur || ':' || p_code,
                                         jsonb_build_object('userId', cur));
      res := 'rebound';
    else
      insert into public.mainsite_accounts (account_id, mainsite_user_id) values (c.account_id, p_user_id);
      res := 'bound';
    end if;
    tgt := c.account_id;
    -- 他刚又绑上了：之前删号留下的、还没发出去的 unlinked 作废
    update public.mainsite_outbox set done_at = now(), last_status = 'superseded'
     where topic = 'unlinked' and done_at is null and body->>'userId' = p_user_id;
  end if;
  update public.mainsite_codes
     set confirmed_at = now(), mainsite_user_id = p_user_id, result = res, target_account = tgt
   where code = p_code;
  -- 'account' = 绑到 / 切到的那个号(11-08 A1×A2 接线: 网关据此在新绑定后拉龟、报防守状态; 网关回主站时不带它)。
  --   原样重放走上面那条早返回, 同样带 ⇒ 函数幂等; 网关重复报用的是非强制模式, 状态没变不会多发。
  return jsonb_build_object('ok', true, 'result', res, 'account', tgt::text);
end $$;
revoke all on function public.mainsite_link_confirm(text, text) from public, anon, authenticated;
grant execute on function public.mainsite_link_confirm(text, text) to service_role;

-- App 轮询（网关 POST /app/link/poll 调）：只有发起这个码的号能查。
--   status：pending（等确认）/ confirmed / expired（没确认就过了 5 分钟，或确认后又过了 5 分钟还没来取）。
--   switched = true 时带 target_account（网关拿它签登录态，不原样转给 App）。
create or replace function public.mainsite_link_poll(p_account uuid, p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.mainsite_codes where code = p_code and account_id = p_account;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  if c.confirmed_at is null then
    return jsonb_build_object('ok', true, 'status', case when c.expires_at <= now() then 'expired' else 'pending' end,
                              'switched', false);
  end if;
  if c.confirmed_at <= now() - interval '5 minutes' then
    return jsonb_build_object('ok', true, 'status', 'expired', 'switched', false);
  end if;
  if c.result = 'switched' and c.target_account is null then
    return jsonb_build_object('ok', false, 'error', 'target_gone');
  end if;
  return jsonb_build_object('ok', true, 'status', 'confirmed', 'switched', c.result = 'switched', 'result', c.result,
                            'user_id', c.mainsite_user_id)
      || case when c.result = 'switched' then jsonb_build_object('target_account', c.target_account) else '{}'::jsonb end;
end $$;
revoke all on function public.mainsite_link_poll(uuid, text) from public, anon, authenticated;
grant execute on function public.mainsite_link_poll(uuid, text) to service_role;

-- ═══ ③ 拥有龟（网关 / App）═══
-- {ok, linked, user_id, owned: [pet_key…], fetched_at}。没绑 ⇒ linked:false、owned:[]。
create or replace function public.mainsite_status(p_account uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a record; ow jsonb;
begin
  select * into a from public.mainsite_accounts where account_id = p_account;
  if not found then
    return jsonb_build_object('ok', true, 'linked', false, 'user_id', null, 'owned', '[]'::jsonb, 'fetched_at', null);
  end if;
  select coalesce(jsonb_agg(pet_key order by pet_key), '[]'::jsonb) into ow from public.mainsite_pets where account_id = p_account;
  return jsonb_build_object('ok', true, 'linked', true, 'user_id', a.mainsite_user_id, 'owned', ow,
                            'fetched_at', a.pets_fetched_at);
end $$;
revoke all on function public.mainsite_status(uuid) from public, anon, authenticated;
grant execute on function public.mainsite_status(uuid) to service_role;

-- App 用：查自己（auth.uid()）。
create or replace function public.mainsite_me()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in', 'linked', false, 'user_id', null,
                              'owned', '[]'::jsonb, 'fetched_at', null);
  end if;
  return public.mainsite_status(uid);
end $$;
revoke all on function public.mainsite_me() from public;
revoke execute on function public.mainsite_me() from anon;
grant execute on function public.mainsite_me() to authenticated;

-- 网关刷新拥有龟（主站 /player 成功之后）：整份替换。p_user_id = 网关调 /player 时用的主站用户；
--   这期间改绑了（绑定的已不是他）⇒ 不写，回 relinked。不合格式的 pet_key 跳过。
create or replace function public.mainsite_pets_put(p_account uuid, p_user_id text, p_keys jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare keys text[];
begin
  if not exists (select 1 from public.mainsite_accounts where account_id = p_account) then
    return jsonb_build_object('ok', false, 'error', 'not_linked');
  end if;
  if not exists (select 1 from public.mainsite_accounts where account_id = p_account and mainsite_user_id = p_user_id) then
    return jsonb_build_object('ok', false, 'error', 'relinked');
  end if;
  if p_keys is null or jsonb_typeof(p_keys) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'bad_keys');
  end if;
  select coalesce(array_agg(distinct k), '{}') into keys
    from jsonb_array_elements_text(p_keys) k where k ~ '^[a-z0-9_]{1,32}$';
  delete from public.mainsite_pets where account_id = p_account and pet_key <> all(keys);
  insert into public.mainsite_pets (account_id, pet_key, fetched_at)
    select p_account, k, now() from unnest(keys) k
    on conflict (account_id, pet_key) do update set fetched_at = excluded.fetched_at;
  update public.mainsite_accounts set pets_fetched_at = now() where account_id = p_account;
  return public.mainsite_status(p_account);
end $$;
revoke all on function public.mainsite_pets_put(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.mainsite_pets_put(uuid, text, jsonb) to service_role;

-- ═══ ⑥ 删号（以 20261020b 版为底；只多「已绑定 ⇒ 写 unlinked 发件箱」一段，在删 auth.users 之前）═══
create or replace function public.account_delete_self() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid   uuid := auth.uid();
  tags  text[];
  ph    jsonb;
  n_m   int := 0; n_l int := 0; n_j int := 0; n_f int := 0; tmp_n int;
  ms_uid text;
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

  -- 2026-11-09a：绑过龟投账号 ⇒ 发件箱写 unlinked（主站解绑、停止推荐；主站账号和金库保留）。没绑 ⇒ 不写。
  --   mainsite_accounts / mainsite_pets 随下面删 auth.users 一路 cascade 掉。
  select mainsite_user_id into ms_uid from public.mainsite_accounts where account_id = uid;
  if ms_uid is not null then
    perform public.mainsite_outbox_put('unlinked', 'del:' || uid::text, jsonb_build_object('userId', ms_uid));
  end if;

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

-- 上线后回读（memory：`revoke from public` 收不掉 anon 的默认授权，必须逐个看）：
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute')
--     from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
--    where p.pronamespace = 'public'::regnamespace and p.proname like 'mainsite%';
--   期望：anon 全 false；authenticated 只有 mainsite_me true；service_role 除 mainsite_me / mainsite_outbox_lane 外全 true。
-- <<< END mainsite_core 20261109a <<<

-- >>> BEGIN raid 20261109c >>>
-- ─────────────────────────────────────────────────────────────
-- 偷袭任务（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.2 / §4.4 / §4.8 / §4.9 ·
--   主站方案 docs/specs/龟战主站整体方案.md §4 ~ §6 · 工作线 A2）
--   主站网页发起偷袭 → POST gameServerURL（server/referee/raid_intake.py → raid_create）→ 锁定双方本周阵容建裁判任务 →
--   裁判领到 ⇒ 发件箱 started → 算完 ⇒ 发件箱 settle（attacker / defender）；算不出 / 超时 / 没有阵容 ⇒ settle void。
-- 前提：20261109a_mainsite_core.sql（A1：mainsite_accounts / mainsite_pets / mainsite_outbox / mainsite_outbox_put）已执行。
--   ★本段只在函数体（plpgsql，执行时才解析表名）里用到那几样 ⇒ 建函数不依赖它们；周赛写回那条路另有异常兜底（见 ⑦）。
-- 本段（★总开关 raid_on 默认关、且只有 econ_on 也开着才生效 ⇒ 执行本段不改变任何现行行为）：
--   ① referee_jobs.kind 多一个 'raid'；referee_config 多一个 raid_on；raid_enabled() = raid_on 且 econ_on（§4.9）
--   ② raid_defense：每个号一行 = 本周最新的阵容快照（形状 = Backend.build_ghost_snapshot）+ 上次报给主站的状态
--      raid_defense_put（App）：只有本周已开轮（三统领齐、分路合法、p_week = 本周锚点）才存、才算 has_defense
--   ③ raid_rating = 本大轮已打场数（服务器记录：积分赛账本 + 闯关账本 + 周日决赛局），= pool_find_battles 用的那个数（§4.9）
--      raid_defense_report：已绑定的号状态变了（有没有阵容 / rating / 设备号）⇒ 发件箱 defense
--      raid_week_rollover：换周 ⇒ 上周报过「有阵容」的已绑定号一律报 hasDefense:false（pg_cron 每小时第 3 分钟，周一 00:03 UTC 起）
--   ④ raid_jobs + raid_create（主站建任务，只给 service_role）：raidId 幂等回同一 jobId；没绑定 / 没有本周阵容 / 阵容不合法 ⇒
--      不排裁判、直接 settle void；否则锁定双方快照建 kind = 'raid' 的裁判任务：
--      ★本周等级与装备以服务器记账为准（raid_lock_snapshot，§4.9「背包里没有的件、超上限的件这场不认」）：
--        等级 = econ_state 重放出的本周等级（没有这一行 = 1）；每件装备必须在账本里同一只身上（小将合在一起算），
--        单只 ≤ 3、全队 ≤ (等级 − 1) × 2（= phase2_config.gd UNIT_EQUIP_CAP / team_equip_cap），多出来的按顺序不认；
--        场次 = raid_rating；小木斧 / 宝箱 / 香火起点 = 重放结果（同 econ_check 比的那几样）
--      ★服务器的 owned（mainsite_pets）与账号只进任务 meta（a_owned / b_owned / a_account / b_account，裁判从任务单 key 读，
--        = 20261109b 领活盖章同一组键），不盖进快照 ⇒ 不跟着快照进 matches / 录像 / 直播
--   ⑨ matches 写入前摘掉快照里的 owned / account_id（兜底：任何一条路带进来都不外泄；matches 任何登录用户都读得到）
--   ⑤ referee_jobs 状态钩子（触发器）：raid 领到 ⇒ started；写回 ⇒ settle（a 赢 = attacker、b 赢 = defender）；
--      失败（拒算 / 次数用尽 / 超时）⇒ settle void；周赛局（积分赛 / 闯关 / 决赛）写回 ⇒ 双方 rating 重算、变了就报 defense
--   ⑥ raid_sweep：排队过了 expireAt 还没开算 ⇒ 不再算；开算 30 分钟没结果 ⇒ void。pg_cron 每分钟（领活本身也不领这两种）
--   ⑦ referee_claim：偷袭局排在闯关 / 决赛 / 积分赛后面领；过期的不领
--   ⑧ purge_old_matches：偷袭局录像留 30 天（周清跳过它）；raid_jobs 同样留 30 天
-- ★偷袭局不发任何东西：referee_complete 只有 finals / gauntlet / ranked 三支落账，raid 一支都不进 ⇒
--   不发深海币 / 宝箱 / 香火 / 小木斧经验 / 命运之轮 / 龟经验，不计本大轮场数（raid_rating 不数 raid 局），不进快照池（ghosts /
--   gauntlet_ghosts 不写）；只落一行 matches（phase = 'raid'，录像）。referee_complete 本身不改。
-- ★时间：周锚点按 app_now()（与积分赛同一口径，内测服假时钟跟着走）；expireAt / 30 分钟按真时间 now()（主站的钟）。
-- 回滚：raid_on = false；trigger raid_job_status / matches_strip_private 可 drop；referee_claim / purge_old_matches 换回 20261101d / 20261008 版。
-- ★重复执行安全（if not exists / create or replace / drop ... if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 任务种类 / 开关 ─────────────────────────────────────────
alter table public.referee_jobs drop constraint if exists referee_jobs_kind_check;
alter table public.referee_jobs add constraint referee_jobs_kind_check
  check (kind in ('gauntlet', 'finals', 'ranked', 'raid'));

alter table public.referee_config add column if not exists raid_on boolean not null default false;

-- 偷袭开着没有。★§4.9：押的是龟币，本周等级与装备必须以服务器记账为准 ⇒ raid_on 只有在 econ_on（记账总开关，
--   20261106b referee_econ_on()）也开着时才生效。判断只在这一处。
create or replace function public.raid_enabled() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.raid_on from public.referee_config c where c.id = 1), false) and public.referee_econ_on()
$$;
revoke all on function public.raid_enabled() from public, anon, authenticated;

-- 常量：开算后多久没结果就作废（= 主站 arena.raidTimeoutMinutes 默认 30）
create or replace function public.raid_compute_sec() returns int language sql immutable as $$ select 1800 $$;
revoke all on function public.raid_compute_sec() from public, anon, authenticated;

-- 本周锚点（周一 00:00 UTC 的 epoch 秒 = 客户端 week_anchor_ts；内测服跟假时钟）
create or replace function public.raid_week() returns bigint
language sql stable security definer set search_path = public as $$
  select extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint
$$;
revoke all on function public.raid_week() from public, anon, authenticated;

-- 阵容能不能拿去偷袭 / 防守：本周已开轮 = 三统领齐、每只在两路里恰好一次（= 裁判左方的开打条件 referee_lineup_ok）。
--   ★两方都按左方的标准查（守方也必须已开轮，用户 11-08「对面也要是开轮状态才行吧」）。判断只在这一处。
create or replace function public.raid_snapshot_ok(p_snap jsonb) returns boolean
language plpgsql immutable as $$
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' or octet_length(p_snap::text) > 65536 then
    return false;
  end if;
  return public.referee_lineup_ok(p_snap);
end $$;
revoke all on function public.raid_snapshot_ok(jsonb) from public, anon, authenticated;

-- 主站用户 ID（对外编码：base62 字母数字串）；纯数字 = 内部 ID ⇒ 不收（主站方案 §6「纯数字或格式不对的一律 bad userId」）
create or replace function public.raid_user_ok(p text) returns boolean
language sql immutable as $$
  select p is not null and p ~ '^[A-Za-z0-9_-]{1,64}$' and p !~ '^[0-9]+$'
$$;
revoke all on function public.raid_user_ok(text) from public, anon, authenticated;

-- ② 防守阵容 ─────────────────────────────────────────────────
create table if not exists public.raid_defense (
  account_id   uuid        primary key references auth.users(id) on delete cascade,
  season_week  bigint      not null,                -- 这份快照是哪一周的（≠ 本周 ⇒ 没有阵容）
  snapshot     jsonb       not null,                -- Backend.build_ghost_snapshot 的产物（摘掉了客户端自带的 owned / account_id）
  device       text,                                -- 设备号（≤ 128；空 = 沿用上一次的）
  updated_at   timestamptz not null default now(),
  -- 上次报给主站（发件箱 defense）的状态：变了才再报；换周判据也看它
  rep_user     text,                                -- 报给的是哪个主站用户
  rep_has      boolean,
  rep_rating   int,
  rep_device   text,
  rep_seq      int         not null default 0,      -- 发件箱幂等键的序号（<主站用户>:<账号>:<序号>）
  rep_at       timestamptz
);
alter table public.raid_defense enable row level security;
-- 没有任何策略 ⇒ 客户端直连读写都不行（阵容 = 情报）；只走 raid_defense_put

-- 这个号本周有没有能用的阵容
create or replace function public.raid_has_defense(p_uid uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.raid_defense where account_id = p_uid;
  return found and d.season_week = public.raid_week() and public.raid_snapshot_ok(d.snapshot);
end $$;
revoke all on function public.raid_has_defense(uuid) from public, anon, authenticated;

-- ③ rating = 本大轮已打场数（服务器记录；§4.9 / 20261105c D17 的口径 = backend.gd pool_find_battles 的 season_total_battles）
--   = 积分赛（ranked_ledger_peek：有服务端账本读账本，没有读切换之前的最后一份）+ 闯关（gauntlet_records 胜 + 负）
--   + 周日决赛（本周算完的 finals 裁判局，我在任一侧）。★偷袭局不在里面（不计场数）。客户端 GameState.season_total_battles
--   在 _settle_season 的积分赛 / gauntlet_settle / finals_settle_sealed 三处 +1，与这三项一一对应。
create or replace function public.raid_rating(p_uid uuid, p_week bigint) returns int
language plpgsql stable security definer set search_path = public as $$
declare v_r int; v_g int; v_f int;
begin
  v_r := coalesce((public.ranked_ledger_peek(p_uid, p_week) ->> 'battles')::int, 0);
  select gw + gl into v_g from public.gauntlet_records where season_week = p_week and account_id = p_uid;
  select count(*)::int into v_f from public.referee_jobs
   where kind = 'finals' and season_week = p_week and status = 'done' and (a_account = p_uid or b_account = p_uid);
  return greatest(v_r, 0) + greatest(coalesce(v_g, 0), 0) + coalesce(v_f, 0);
end $$;
revoke all on function public.raid_rating(uuid, bigint) from public, anon, authenticated;

-- 把这个号现在的状态报给主站（发件箱 defense {userId, hasDefense, rating, device}）：已绑定 + 与上次报的不同才写。
--   p_force：不比较、直接报一次（A1 绑定成功后调，让主站拿到当前状态）。
--   ★从没存过阵容的号不报（主站那边默认就是没有阵容；删号时主站 unlinked 也会清掉）。
--   ★没部署 A1（没有 mainsite_accounts）⇒ 回 no_mainsite、什么都不写。
create or replace function public.raid_defense_report(p_uid uuid, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d record; wk bigint := public.raid_week(); v_msu text; v_has boolean; v_rating int; v_seq int;
begin
  if p_uid is null or to_regclass('public.mainsite_accounts') is null then
    return jsonb_build_object('ok', false, 'reason', 'no_mainsite', 'sent', false);
  end if;
  select * into d from public.raid_defense where account_id = p_uid for update;
  if not found then
    return jsonb_build_object('ok', true, 'has_defense', false, 'rating', 0, 'sent', false);
  end if;
  v_has := d.season_week = wk and public.raid_snapshot_ok(d.snapshot);
  v_rating := case when v_has then public.raid_rating(p_uid, wk) else 0 end;
  select m.mainsite_user_id into v_msu from public.mainsite_accounts m where m.account_id = p_uid;
  if v_msu is null then
    -- 解绑了（主站 unlinked 会清掉那边的阵容）⇒ 上次报的状态作废：以后重新绑定从头报，换周也不再挑它
    if d.rep_user is not null then
      update public.raid_defense set rep_user = null, rep_has = null, rep_rating = null, rep_device = null
       where account_id = p_uid;
    end if;
    return jsonb_build_object('ok', true, 'linked', false, 'has_defense', v_has, 'rating', v_rating, 'sent', false);
  end if;
  if not (coalesce(p_force, false)
          or (d.rep_user is not null and d.rep_user <> v_msu)
          or coalesce(d.rep_has, false) <> v_has
          or coalesce(d.rep_rating, 0) <> v_rating
          or (v_has and d.device is not null and d.device is distinct from d.rep_device)) then
    return jsonb_build_object('ok', true, 'linked', true, 'has_defense', v_has, 'rating', v_rating, 'sent', false);
  end if;
  v_seq := d.rep_seq + 1;
  perform public.mainsite_outbox_put('defense', format('%s:%s:%s', v_msu, p_uid, v_seq),
    jsonb_build_object('userId', v_msu, 'hasDefense', v_has, 'rating', v_rating, 'device', coalesce(d.device, '')));
  update public.raid_defense
     set rep_user = v_msu, rep_has = v_has, rep_rating = v_rating, rep_device = d.device, rep_seq = v_seq, rep_at = now()
   where account_id = p_uid;
  return jsonb_build_object('ok', true, 'linked', true, 'has_defense', v_has, 'rating', v_rating, 'sent', true);
end $$;
revoke all on function public.raid_defense_report(uuid, boolean) from public, anon, authenticated;
grant execute on function public.raid_defense_report(uuid, boolean) to service_role;

-- App 存当前号这一周的最新阵容（B：离开背包 / 选龟页、每打完一局上传快照时）。回 {ok, has_defense}。
--   ★只有本周已开轮才存：p_week ≠ 本周锚点 ⇒ wrong_week；三统领不齐 / 分路坏 ⇒ 不存、不动已存的那份（stored:false）。
--   ★客户端快照里自带的 owned / account_id 一律摘掉（拥有以服务器 mainsite_pets 为准，建任务时由服务端盖上）。
--   ★报给主站那一步出错不影响存阵容（异常兜住，下一次存 / 下一局写回会再报）。
create or replace function public.raid_defense_put(p_week bigint, p_snapshot jsonb, p_device text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); wk bigint := public.raid_week(); v_dev text; v_snap jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in', 'has_defense', false);
  end if;
  if p_week is distinct from wk then
    return jsonb_build_object('ok', false, 'reason', 'wrong_week', 'has_defense', public.raid_has_defense(uid));
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'bad_snapshot', 'has_defense', public.raid_has_defense(uid));
  end if;
  v_snap := p_snapshot - 'owned' - 'account_id';
  if not public.raid_snapshot_ok(v_snap) then
    return jsonb_build_object('ok', true, 'stored', false, 'reason', 'not_open', 'has_defense', public.raid_has_defense(uid));
  end if;
  v_dev := nullif(left(btrim(coalesce(p_device, '')), 128), '');
  insert into public.raid_defense (account_id, season_week, snapshot, device, updated_at)
    values (uid, wk, v_snap, v_dev, now())
    on conflict (account_id) do update
      set season_week = excluded.season_week, snapshot = excluded.snapshot,
          device = coalesce(excluded.device, public.raid_defense.device), updated_at = now();
  begin
    perform public.raid_defense_report(uid);
  exception when others then
    raise warning 'raid_defense_put: 报主站失败（阵容已存）: %', sqlerrm;
  end;
  return jsonb_build_object('ok', true, 'stored', true, 'has_defense', true);
end $$;
revoke all on function public.raid_defense_put(bigint, jsonb, text) from public, anon;
grant execute on function public.raid_defense_put(bigint, jsonb, text) to authenticated;

-- 换周：上周报过「有阵容」（或 rating 不是 0）的号重报一次 —— 快照不是本周的 ⇒ hasDefense:false、rating 0。
--   §4.2「周一 00:00 UTC 换周时给所有已绑定玩家经发件箱报 hasDefense:false」：从没报过有阵容的号主站那边本来就是 false，
--   不重复报；本周第一次开打（App 存阵容）后由 raid_defense_put 报回 true。
--   触发：pg_cron 'raid_week_rollover' 每小时第 3 分钟（周一 00:03 UTC 第一次生效；之后每小时一次是兜底 / 内测服假时钟）。幂等。
create or replace function public.raid_week_rollover() returns int
language plpgsql security definer set search_path = public as $$
declare wk bigint := public.raid_week(); r record; n int := 0; x jsonb;
begin
  for r in select d.account_id from public.raid_defense d
            where d.season_week < wk and (coalesce(d.rep_has, false) or coalesce(d.rep_rating, 0) <> 0)
            order by d.account_id loop
    x := public.raid_defense_report(r.account_id);
    if coalesce((x ->> 'sent')::boolean, false) then
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.raid_week_rollover() from public, anon, authenticated;
grant execute on function public.raid_week_rollover() to service_role;
select cron.unschedule(jobid) from cron.job where jobname = 'raid_week_rollover';
select cron.schedule('raid_week_rollover', '3 * * * *', 'select public.raid_week_rollover()');

-- ④ 偷袭任务 ─────────────────────────────────────────────────
create table if not exists public.raid_jobs (
  id               bigint      generated always as identity primary key,   -- = 回给主站的 jobId（字符串）
  raid_id          bigint      not null unique,                            -- 主站 raidId（幂等键）
  attacker         text        not null,                                   -- 主站用户 ID（对外编码）
  defender         text        not null,
  attacker_account uuid        references auth.users(id) on delete set null,
  defender_account uuid        references auth.users(id) on delete set null,
  seed             bigint      not null default 0,                         -- 主站给的原值（裁判实际用的在 referee_jobs.seed）
  stake            bigint      not null default 0,                         -- 只记录（App 里不显示任何金额）
  is_revenge       boolean     not null default false,                     -- 只记录（不做复仇，用户 11-08）
  expire_at        timestamptz not null,                                   -- 主站 expireAt：过了还没开算就不再算
  season_week      bigint      not null,
  status           text        not null default 'queued' check (status in ('queued', 'started', 'done', 'void')),
  reason           text,                                                   -- void 的原因（attacker_unlinked / defender_no_defense / raid_timeout …）
  a_snapshot       jsonb,                                                  -- 建任务那一刻锁定的攻方阵容（= 裁判任务的 a：已按记账改写，不含 owned）
  b_snapshot       jsonb,                                                  -- 守方（= b）
  a_owned          jsonb,                                                  -- 攻方拥有的龟（mainsite_pets 的 pet_key）
  b_owned          jsonb,
  referee_job_id   bigint      references public.referee_jobs(job_id) on delete set null,
  match_id         uuid,                                                   -- = 录像 id = settle 的 matchId
  result           text        check (result in ('attacker', 'defender', 'void')),
  created_at       timestamptz not null default now(),
  started_at       timestamptz,                                            -- 裁判第一次领到（= 发 started 的那一刻）
  settled_at       timestamptz
);
create index if not exists raid_jobs_job_idx on public.raid_jobs (referee_job_id);
create index if not exists raid_jobs_open_idx on public.raid_jobs (status) where status in ('queued', 'started');
alter table public.raid_jobs enable row level security;
-- 没有任何策略 ⇒ 客户端读写都不行

-- 偷袭用哪个版本算：裁判机装了、开着的最新版本（两边快照都是数据，规则以算它的版本为准；同周赛 referee_versions 那张表）
create or replace function public.raid_pick_version() returns text
language sql stable security definer set search_path = public as $$
  select v.client_version from public.referee_versions v
   where v.enabled and public.semver_arr(v.client_version) is not null
   order by public.semver_arr(v.client_version) desc limit 1
$$;
revoke all on function public.raid_pick_version() from public, anon, authenticated;

-- 作废一场：记 void；p_send ⇒ 发件箱 settle {raidId, result:'void', matchId:''}
create or replace function public.raid_void(p_id bigint, p_reason text, p_send boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  update public.raid_jobs
     set status = 'void', result = 'void', reason = left(coalesce(p_reason, '?'), 200), settled_at = now()
   where id = p_id and status in ('queued', 'started')
  returning * into r;
  if found and coalesce(p_send, true) then
    perform public.mainsite_outbox_put('settle', r.raid_id::text,
      jsonb_build_object('raidId', r.raid_id, 'result', 'void', 'matchId', ''));
  end if;
end $$;
revoke all on function public.raid_void(bigint, text, boolean) from public, anon, authenticated;

-- 装备上限（= phase2_config.gd：UNIT_EQUIP_CAP 3；team_equip_cap(等级) = (clamp(等级, 1, MAX_LEVEL 10) − 1) × 2）。
--   ★两边各一份 ⇒ 检查脚本 L0 把这里的 0 ~ 11 级钉成一张字面表，tests/verify_raid_private_fields.gd 拿同一张表对 GDScript。
create or replace function public.raid_unit_equip_cap() returns int language sql immutable as $$ select 3 $$;
revoke all on function public.raid_unit_equip_cap() from public, anon, authenticated;
create or replace function public.raid_team_equip_cap(p_lv int) returns int language sql immutable as $$
  select greatest(0, (least(greatest(coalesce(p_lv, 1), 1), 10) - 1) * 2)
$$;
revoke all on function public.raid_team_equip_cap(int) from public, anon, authenticated;

-- 一件装备的比对键「id|星」（= econ_items_key 的口径：星缺 = 1、按整数比）；不是对象 / 没有 id / 星不是数 ⇒ null（这件不认）
create or replace function public.raid_item_key(p_it jsonb) returns text language sql immutable as $$
  select case when jsonb_typeof(p_it) = 'object' and coalesce(p_it ->> 'id', '') <> ''
                   and (not (p_it ? 'star') or jsonb_typeof(p_it -> 'star') = 'number')
              then (p_it ->> 'id') || '|' || coalesce(round((p_it ->> 'star')::numeric)::int, 1)::text end
$$;
revoke all on function public.raid_item_key(jsonb) from public, anon, authenticated;

-- 一组装备 ⇒ {键: 件数}
create or replace function public.raid_item_counts(p_items jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
    from (select public.raid_item_key(x) as k, count(*)::int as n
            from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) x
           group by 1) t
   where k is not null
$$;
revoke all on function public.raid_item_counts(jsonb) from public, anon, authenticated;

-- ★锁定快照：本周等级与装备改成服务器记账（econ_state，裁判机按流水重放的结果；§4.9 / 20261106 §4.5）。
--   等级：econ_state.assets.lv（没有这一行 = 本周还没有任何流水 = 1；快照自报的不认）
--   装备：统领每件必须在账本里这只身上（assets.worn[龟]，按件数扣）；小将每件必须在账本里某只小将身上（assets.minions 合起来按件数扣，
--         小将之间换位不算错）；单只 ≤ raid_unit_equip_cap、全队 ≤ raid_team_equip_cap(等级)；
--         不认的件直接拿掉；超上限按「统领按 leaders 顺序 → 上路小将 → 下路小将、每只按快照里的顺序」先到先留
--   场次：season_total_battles = raid_rating（援军小将按场次成长，同 ranked_stamp_snapshot）
--   小木斧 / 宝箱 / 香火：= 重放结果（同 econ_check 比的键；没有这一行 = 本周起点 0 / 空）
--   其余（阵容、站位、技能、大师、头像名字）原样；owned / account_id 摘掉。
--   ★不看 econ_on（开关在 raid_enabled 一处）；econ_state 有不合法的一条（bad_at ≥ 0）时 assets 是合法前缀的结果，照用。
create or replace function public.raid_lock_snapshot(p_uid uuid, p_week bigint, p_snap jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.econ_state%rowtype; v_a jsonb := '{}'::jsonb; v_p jsonb := '{}'::jsonb; v_lv int; v_cap int;
        v_unit int := public.raid_unit_equip_cap(); v_used int := 0; v_out jsonb; v_pid text; v_avail jsonb; v_pool jsonb;
        v_kept jsonb; v_eq jsonb := '{}'::jsonb; v_it jsonb; v_k text; v_lane text; v_m jsonb; v_new jsonb; v_mins jsonb := '{}'::jsonb;
        v_mlist jsonb := '[]'::jsonb;
begin
  select * into s from public.econ_state where account_id = p_uid and week = p_week;
  if found then
    v_a := case when jsonb_typeof(s.assets) = 'object' then s.assets else '{}'::jsonb end;
    v_p := case when jsonb_typeof(s.progress) = 'object' then s.progress else '{}'::jsonb end;
  end if;
  v_lv := least(greatest(coalesce(case when jsonb_typeof(v_a -> 'lv') = 'number' then round((v_a ->> 'lv')::numeric)::int end, 1), 1), 10);
  v_cap := public.raid_team_equip_cap(v_lv);
  v_out := (p_snap - 'owned' - 'account_id') || jsonb_build_object('season_level', v_lv,
    'season_total_battles', public.raid_rating(p_uid, p_week),
    'axe_exp_total', coalesce(case when jsonb_typeof(v_a -> 'axe' -> 1) = 'number' then round((v_a -> 'axe' ->> 1)::numeric)::int end, 0),
    'axe_stage', coalesce(case when jsonb_typeof(v_a -> 'axe' -> 2) = 'number' then round((v_a -> 'axe' ->> 2)::numeric)::int end, 0),
    'axe_final', coalesce(v_a -> 'axe' ->> 3, ''),
    'chest_treasure_value', coalesce(case when jsonb_typeof(v_p -> 'cv') = 'number' then v_p -> 'cv' end, '0'::jsonb),
    'chest_treasures_won', coalesce(case when jsonb_typeof(v_p -> 'cw') = 'array' then v_p -> 'cw' end, '[]'::jsonb),
    'incense_marks', coalesce(case when jsonb_typeof(v_p -> 'im') = 'number' then round((v_p ->> 'im')::numeric)::int end, 0),
    'incense_charge', coalesce(case when jsonb_typeof(v_p -> 'ic') = 'number' then round((v_p ->> 'ic')::numeric)::int end, 0));
  -- 统领
  for v_pid in select x from jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'leaders') = 'array'
                                                            then p_snap -> 'leaders' else '[]'::jsonb end) with ordinality t(x, i)
                order by i loop
    continue when v_eq ? v_pid;
    v_avail := public.raid_item_counts(v_a -> 'worn' -> v_pid);
    v_kept := '[]'::jsonb;
    for v_it in select x from jsonb_array_elements(case when jsonb_typeof(p_snap -> 'equipped' -> v_pid) = 'array'
                                                        then p_snap -> 'equipped' -> v_pid else '[]'::jsonb end) with ordinality t(x, i)
                 order by i loop
      v_k := public.raid_item_key(v_it);
      if v_k is not null and coalesce((v_avail ->> v_k)::int, 0) > 0 and jsonb_array_length(v_kept) < v_unit and v_used < v_cap then
        v_kept := v_kept || jsonb_build_array(v_it || jsonb_build_object('star', (regexp_match(v_k, '[|](-?[0-9]+)$'))[1]::int));
        v_avail := v_avail || jsonb_build_object(v_k, (v_avail ->> v_k)::int - 1);
        v_used := v_used + 1;
      end if;
    end loop;
    if jsonb_array_length(v_kept) > 0 then
      v_eq := v_eq || jsonb_build_object(v_pid, v_kept);
    end if;
  end loop;
  v_out := v_out || jsonb_build_object('equipped', v_eq);
  -- 小将：账本里全部小将身上的件合成一个池（assets.minions = 每只一个 JSON 串 {"eq": [...], "lv": n}）
  for v_m in select case when jsonb_typeof(x) = 'string' then (x #>> '{}')::jsonb else x end
               from jsonb_array_elements(case when jsonb_typeof(v_a -> 'minions') = 'array' then v_a -> 'minions' else '[]'::jsonb end) x loop
    if jsonb_typeof(v_m) = 'object' and jsonb_typeof(v_m -> 'eq') = 'array' then
      v_mlist := v_mlist || (v_m -> 'eq');
    end if;
  end loop;
  v_pool := public.raid_item_counts(v_mlist);
  if jsonb_typeof(p_snap -> 'minions') = 'object' then
    for v_lane in select key from jsonb_each(p_snap -> 'minions') order by (key <> 'top'), (key <> 'bottom'), key loop
      v_new := '[]'::jsonb;
      for v_m in select x from jsonb_array_elements(case when jsonb_typeof(p_snap -> 'minions' -> v_lane) = 'array'
                                                         then p_snap -> 'minions' -> v_lane else '[]'::jsonb end) with ordinality t(x, i)
                  order by i loop
        if jsonb_typeof(v_m) = 'object' and v_m ? 'equips' then
          v_kept := '[]'::jsonb;
          for v_it in select x from jsonb_array_elements(case when jsonb_typeof(v_m -> 'equips') = 'array'
                                                              then v_m -> 'equips' else '[]'::jsonb end) with ordinality t(x, i)
                       order by i loop
            v_k := public.raid_item_key(v_it);
            if v_k is not null and coalesce((v_pool ->> v_k)::int, 0) > 0 and jsonb_array_length(v_kept) < v_unit and v_used < v_cap then
              v_kept := v_kept || jsonb_build_array(v_it || jsonb_build_object('star', (regexp_match(v_k, '[|](-?[0-9]+)$'))[1]::int));
              v_pool := v_pool || jsonb_build_object(v_k, (v_pool ->> v_k)::int - 1);
              v_used := v_used + 1;
            end if;
          end loop;
          v_m := v_m || jsonb_build_object('equips', v_kept);
        end if;
        v_new := v_new || jsonb_build_array(v_m);
      end loop;
      v_mins := v_mins || jsonb_build_object(v_lane, v_new);
    end loop;
    v_out := v_out || jsonb_build_object('minions', v_mins);
  end if;
  return v_out;
end $$;
revoke all on function public.raid_lock_snapshot(uuid, bigint, jsonb) from public, anon, authenticated;

-- 主站建任务（raid_intake.handle_create 调；只给 service_role）。回 {ok:true, jobId} / {ok:false, error}。
--   ok:false（主站立即作废退回）：bad_raidId / bad_userId / same_user / raid_conflict（同 raidId 双方不同）/ raid_off / expired / no_referee
--   ok:true 但直接 void（不排裁判，settle void 入发件箱）：attacker_unlinked / defender_unlinked /
--     attacker_no_defense / defender_no_defense（没有本周阵容 = 没开轮 / 快照是上周的 / 阵容不合法）
--   ★同 raidId 重发：不看开关、不看过期，直接回同一个 jobId（主站重发的是同一场）。
--   ★种子：主站给的 1 ~ 2^53-1 原样用（两边都能复算）；0 / 超界 ⇒ 服务端生成。
create or replace function public.raid_create(p_raid_id bigint, p_attacker text, p_defender text, p_seed bigint,
    p_stake bigint, p_is_revenge boolean, p_expire_at bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ex record; v_id bigint; wk bigint; v_now_ms bigint; ua uuid; ud uuid; da record; dd record; v_reason text;
        v_ver text; v_own_a jsonb; v_own_b jsonb; v_snap_a jsonb; v_snap_b jsonb; jid bigint; mid uuid; v_seed bigint;
begin
  if p_raid_id is null or p_raid_id <= 0 then
    return jsonb_build_object('ok', false, 'error', 'bad_raidId');
  end if;
  if not public.raid_user_ok(p_attacker) or not public.raid_user_ok(p_defender) then
    return jsonb_build_object('ok', false, 'error', 'bad_userId');
  end if;
  if p_attacker = p_defender then
    return jsonb_build_object('ok', false, 'error', 'same_user');
  end if;
  select * into ex from public.raid_jobs where raid_id = p_raid_id;
  if found then
    if ex.attacker <> p_attacker or ex.defender <> p_defender then
      return jsonb_build_object('ok', false, 'error', 'raid_conflict');
    end if;
    return jsonb_build_object('ok', true, 'jobId', ex.id::text);
  end if;
  if not public.raid_enabled() then
    return jsonb_build_object('ok', false, 'error', 'raid_off');
  end if;
  v_now_ms := floor(extract(epoch from now()) * 1000)::bigint;
  if p_expire_at is null or p_expire_at <= v_now_ms then
    return jsonb_build_object('ok', false, 'error', 'expired');
  end if;
  v_ver := public.raid_pick_version();
  if v_ver is null then
    return jsonb_build_object('ok', false, 'error', 'no_referee');
  end if;
  wk := public.raid_week();
  select m.account_id into ua from public.mainsite_accounts m where m.mainsite_user_id = p_attacker;
  select m.account_id into ud from public.mainsite_accounts m where m.mainsite_user_id = p_defender;
  if ua is null then
    v_reason := 'attacker_unlinked';
  elsif ud is null then
    v_reason := 'defender_unlinked';
  else
    select * into da from public.raid_defense where account_id = ua;
    select * into dd from public.raid_defense where account_id = ud;
    if da.account_id is null or da.season_week <> wk or not public.raid_snapshot_ok(da.snapshot) then
      v_reason := 'attacker_no_defense';
    elsif dd.account_id is null or dd.season_week <> wk or not public.raid_snapshot_ok(dd.snapshot) then
      v_reason := 'defender_no_defense';
    end if;
  end if;
  insert into public.raid_jobs (raid_id, attacker, defender, attacker_account, defender_account, seed, stake, is_revenge,
      expire_at, season_week)
    values (p_raid_id, p_attacker, p_defender, ua, ud, coalesce(p_seed, 0), coalesce(p_stake, 0), coalesce(p_is_revenge, false),
      to_timestamp(p_expire_at / 1000.0), wk)
    on conflict (raid_id) do nothing
    returning id into v_id;
  if v_id is null then
    -- 同一刻另一个请求先建了（主站超时重发）：回先到的那一个
    select * into ex from public.raid_jobs where raid_id = p_raid_id;
    if ex.attacker <> p_attacker or ex.defender <> p_defender then
      return jsonb_build_object('ok', false, 'error', 'raid_conflict');
    end if;
    return jsonb_build_object('ok', true, 'jobId', ex.id::text);
  end if;
  if v_reason is not null then
    perform public.raid_void(v_id, v_reason);
    return jsonb_build_object('ok', true, 'jobId', v_id::text);
  end if;
  select coalesce(jsonb_agg(p.pet_key order by p.pet_key), '[]'::jsonb) into v_own_a from public.mainsite_pets p where p.account_id = ua;
  select coalesce(jsonb_agg(p.pet_key order by p.pet_key), '[]'::jsonb) into v_own_b from public.mainsite_pets p where p.account_id = ud;
  -- 锁定：本周那份快照，等级 / 装备 / 场次 / 小木斧宝箱香火改成服务器记账（raid_lock_snapshot）。
  --   服务器的 owned / 账号只进 meta（= 20261109b 领活盖章的 a_owned / b_owned / a_account / b_account；裁判从 key 读），
  --   ★不盖进快照：快照会原样进 matches 与录像（任何登录用户都读得到）。
  v_snap_a := public.raid_lock_snapshot(ua, wk, da.snapshot);
  v_snap_b := public.raid_lock_snapshot(ud, wk, dd.snapshot);
  v_seed := case when p_seed between 1 and 9007199254740991 then p_seed else public.referee_new_seed() end;
  insert into public.referee_jobs (kind, match_key, season_week, client_version, seed,
      a_account, b_account, a_snapshot, b_snapshot, level, meta)
    values ('raid', format('raid:%s', p_raid_id), wk, v_ver, v_seed, ua, ud, v_snap_a, v_snap_b,
      public.referee_level_of(v_snap_a),
      jsonb_build_object('raid_id', p_raid_id, 'attacker', p_attacker, 'defender', p_defender,
                         'account', ua, 'b_account', ud, 'expire_ms', p_expire_at,
                         'a_account', ua, 'a_owned', v_own_a, 'b_owned', v_own_b))
    on conflict (match_key) do nothing
    returning job_id, match_id into jid, mid;
  if jid is null then
    select job_id, match_id into jid, mid from public.referee_jobs where match_key = format('raid:%s', p_raid_id);
  end if;
  update public.raid_jobs
     set referee_job_id = jid, match_id = mid, a_snapshot = v_snap_a, b_snapshot = v_snap_b, a_owned = v_own_a, b_owned = v_own_b
   where id = v_id;
  return jsonb_build_object('ok', true, 'jobId', v_id::text);
end $$;
revoke all on function public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint) from public, anon, authenticated;
grant execute on function public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint) to service_role;

-- ⑤ 裁判任务状态变了 ⇒ 偷袭的 started / settle、周赛的 rating ─────────
-- 一场偷袭对应的裁判任务：领到（claimed）⇒ started（只第一次；重领不再发）；写回（done）⇒ settle attacker / defender；
--   失败（failed）⇒ void（排队过期 raid_expired 不发 settle：主站到点自己作废退回，迟到的 settle 主站也不认）。
--   ★结果单的 winner 是唯一依据（a = 攻方 = attacker）；裁判另带的 raid_result 与它对不上 ⇒ void（不赌哪一个对）。
create or replace function public.raid_on_job(p_job_id bigint, p_status text, p_error text, p_result jsonb, p_match_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_res text;
begin
  select * into r from public.raid_jobs where referee_job_id = p_job_id for update;
  if not found or r.status in ('done', 'void') then
    return;
  end if;
  if p_status = 'claimed' then
    if r.status = 'queued' then
      update public.raid_jobs set status = 'started', started_at = now() where id = r.id;
      perform public.mainsite_outbox_put('started', r.raid_id::text, jsonb_build_object('raidId', r.raid_id));
    end if;
  elsif p_status = 'done' then
    v_res := case p_result ->> 'winner' when 'a' then 'attacker' when 'b' then 'defender' end;
    if v_res is null or (p_result ? 'raid_result' and p_result ->> 'raid_result' is distinct from v_res) then
      perform public.raid_void(r.id, 'bad_result');
      return;
    end if;
    update public.raid_jobs set status = 'done', result = v_res, match_id = p_match_id, settled_at = now() where id = r.id;
    perform public.mainsite_outbox_put('settle', r.raid_id::text,
      jsonb_build_object('raidId', r.raid_id, 'result', v_res, 'matchId', p_match_id::text));
  elsif p_status = 'failed' then
    perform public.raid_void(r.id, coalesce(p_error, 'failed'), coalesce(p_error, '') <> 'raid_expired');
  end if;
end $$;
revoke all on function public.raid_on_job(bigint, text, text, jsonb, uuid) from public, anon, authenticated;

-- 触发器本体。两支都兜在异常里：
--   周赛那一支：报主站出任何问题都不许拖垮周赛记账（referee_complete 的事务）。
--   偷袭那一支：发件箱写不进（A1 那边出问题）不许拖垮领活 —— referee_claim 的租期回收会一次改多行（含周赛局），
--     这里一抛异常整个领活就失败、周赛局也领不走。丢的那一条 started / settle 由主站超时作废兜底（各退各的，钱不会错）。
create or replace function public.raid_job_status_hook() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'raid' then
    begin
      perform public.raid_on_job(new.job_id, new.status, new.error, new.result, new.match_id);
    exception when others then
      raise warning 'raid_job_status_hook: 偷袭 job=% status=% 没记上（主站会超时作废）: %', new.job_id, new.status, sqlerrm;
    end;
  elsif new.status = 'done' and new.kind in ('ranked', 'gauntlet', 'finals') then
    begin
      if new.a_account is not null then
        perform public.raid_defense_report(new.a_account);
      end if;
      if new.b_account is not null and (new.kind = 'finals' or coalesce(new.meta ->> 'pair', '') = 'true') then
        perform public.raid_defense_report(new.b_account);
      end if;
    exception when others then
      raise warning 'raid_job_status_hook: rating 没报出去（不影响周赛记账）: %', sqlerrm;
    end;
  end if;
  return null;
end $$;
revoke all on function public.raid_job_status_hook() from public, anon, authenticated;
drop trigger if exists raid_job_status on public.referee_jobs;
create trigger raid_job_status after update of status on public.referee_jobs
  for each row when (old.status is distinct from new.status) execute function public.raid_job_status_hook();

-- ⑥ 过期 / 超时 ─────────────────────────────────────────────
-- ① 还没开算（queued）就过了 expireAt ⇒ 任务记 failed raid_expired（不再算；钩子记 void、不发 settle）
-- ② 开算后 raid_compute_sec（30 分钟）还没写回 ⇒ failed raid_timeout（钩子记 void、发 settle void）；迟到的写回 not_owner 被拒
create or replace function public.raid_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare n1 int; n2 int;
begin
  update public.referee_jobs j
     set status = 'failed', error = 'raid_expired', done_at = now(), claimed_by = null, claimed_at = null
    from public.raid_jobs r
   where r.referee_job_id = j.job_id and r.status = 'queued' and r.expire_at <= now()
     and j.kind = 'raid' and j.status = 'pending';
  get diagnostics n1 = row_count;
  update public.referee_jobs j
     set status = 'failed', error = 'raid_timeout', done_at = now(), claimed_by = null, claimed_at = null
    from public.raid_jobs r
   where r.referee_job_id = j.job_id and r.status = 'started'
     and r.started_at <= now() - make_interval(secs => public.raid_compute_sec())
     and j.kind = 'raid' and j.status in ('pending', 'claimed');
  get diagnostics n2 = row_count;
  return n1 + n2;
end $$;
revoke all on function public.raid_sweep() from public, anon, authenticated;
grant execute on function public.raid_sweep() to service_role;
select cron.unschedule(jobid) from cron.job where jobname = 'raid_sweep';
select cron.schedule('raid_sweep', '* * * * *', 'select public.raid_sweep()');

-- ⑦ 领活（以 20261101d 版为底，只改两处，标了「2026-11-09 偷袭」）：
--   ① 偷袭局：还在排队且没过 expireAt，或已开算且没满 30 分钟，才领（过期 / 超时的由 raid_sweep 每分钟收成 failed）
--   ② order by 最前面多一项 (kind = 'raid')：偷袭排在闯关 / 决赛 / 积分赛后面（false 在前；没有偷袭局时排序结果逐字不变）
--   ★领活这条热路径上不加写（raid_sweep 不在这里跑）：多个裁判并发领活时不多一处行锁。
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
       -- 2026-11-09 偷袭 ①
       and (kind <> 'raid' or exists (select 1 from public.raid_jobs r where r.referee_job_id = referee_jobs.job_id
              and ((r.status = 'queued' and r.expire_at > now())
                   or (r.status = 'started' and r.started_at > now() - make_interval(secs => public.raid_compute_sec())))))
     order by (kind = 'raid'),   -- 2026-11-09 偷袭 ②
              (kind = 'ranked' and exists (select 1 from public.bot_accounts b where b.account_id = a_account)),
              created_at, job_id
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

-- ⑧ 周清（以 20261008 版为底）：偷袭局录像留 30 天（主站「看录像」要用；20261107 §4.5），不随周清删；raid_jobs 同样留 30 天。
--   其余三行逐字不动（cron 'purge_old_matches' '0 0 * * 2' 不变）。
create or replace function public.purge_old_matches() returns void
language sql security definer as $$
  delete from public.matches where created_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC'
    and phase <> 'raid';
  delete from public.matches where phase = 'raid' and created_at < now() - interval '30 days';
  delete from public.raid_jobs where created_at < now() - interval '30 days';
  delete from public.live_matches where started_at < date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
  delete from public.ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
  delete from public.gauntlet_ghosts where season_week < extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint;
$$;
revoke all on function public.purge_old_matches() from public, anon, authenticated;

-- ⑨ matches 写入前摘私有字段（兜底）：快照里的 owned（拥有的龟）/ account_id 不进 matches。
--   matches 任何登录用户都读得到（matches_read_all）；偷袭局的拥有与账号只该在任务单里（raid_create 已不往快照里盖，
--   这一道管的是任何别的路 —— 旧任务、以后谁又往快照里塞 —— 带进来的）。客户端快照本来就没有这两个键 ⇒ 对它们一字不变。
create or replace function public.matches_strip_private() returns trigger
language plpgsql as $$
begin
  if jsonb_typeof(new.left_snapshot) = 'object' then
    new.left_snapshot := new.left_snapshot - 'owned' - 'account_id';
  end if;
  if jsonb_typeof(new.right_snapshot) = 'object' then
    new.right_snapshot := new.right_snapshot - 'owned' - 'account_id';
  end if;
  return new;
end $$;
revoke all on function public.matches_strip_private() from public, anon, authenticated;
drop trigger if exists matches_strip_private on public.matches;
create trigger matches_strip_private before insert or update of left_snapshot, right_snapshot on public.matches
  for each row execute function public.matches_strip_private();
-- <<< END raid 20261109c <<<
-- >>> BEGIN pet_levels 20261109b >>>
-- ─────────────────────────────────────────────────────────────
-- 龟等级与经验 + 开算盖章（2026-11-09 · 主站对接工作线 C）
--   方案书 docs/plans/20261107b-龟等级与经验.md（已拍板：1 ~ 10 级；周赛每局上场的自己的龟赢 +8、输 +6；
--   N 级升 N+1 级要 50 + 20N，满级累计 1350；限免龟固定 1 级、不涨、不可升级）、20261107-龟战主站对接.md §4.3 / §4.9、
--   20261105c-主站对接偷袭.md §4.2（按龟等级 R1、等级盖章：裁判开算时按服务器等级表覆盖快照里的 lv）。
--   接口契约（主会话 11-08）：§1 本迁移名、§4 限免与校验。
-- ★依赖 20261109a_mainsite_core（工作线 A1）：mainsite_accounts / mainsite_pets / mainsite_outbox_put（pet-level 只在已绑定、
--   主站返回过这只龟、等级 1 ~ 10 时才真写，由它统一挡）。与 20261109c_raid 互不依赖、先后都行（本段不改 referee_claim）。
--   本段里碰它们的函数一律 plpgsql（建函数时不查表在不在）；运行时缺表 ⇒ 当作「没绑定 / 没拥有」（undefined_table 兜住），
--   不让主站那几张表的上线先后卡住裁判领活或结算。
--
--   ① pet_levels（账号 × 龟：累计经验、等级）/ pet_xp_log（幂等键 = 对局 match_id + 账号 + 龟）：只由本段的函数写，客户端读不到表。
--   ② 曲线：pet_xp_to_reach(等级) / pet_level_for_xp(经验) —— 与客户端 TurtleLevel 同一条（门禁 verify_pet_level_r1 对一遍）。
--   ③ pet_owned(账号)：拥有 = mainsite_pets（主站 /player 的缓存）里、且是我们 28 只之一的龟。没绑定 / 缺表 ⇒ 空。
--   ④ pet_lv_table(快照, 账号)：开算盖章用的等级表 —— 三只统领各自的等级（拥有的按 pet_levels，其余 1）。没有账号（机器人池）⇒ 全 1 级。
--   ⑤ 触发器 pet_stamp_on_claim（BEFORE：任务变成 claimed 的那一句 update）：任务 meta 记 a_account / b_account /
--      a_owned / b_owned（这一刻的账号与拥有）和 a_lv / b_lv（这一刻的等级表）并**写回任务行** ⇒ 领活 / 补流回的任务单 key 里都有：
--      裁判按账号 + 拥有算这一侧本周的「拥有 ∪ 限免」（WeeklyFree，种子 = 账号 + 周锚点 key.week），按 a_lv / b_lv 覆盖快照自报的 lv。
--      ★快照本身一个字不改：决赛的坏快照回退（20261101b finals_advance）拿任务里的快照与参赛者那份逐字比，改了快照就永远「不同」⇒
--        拒算的那一局会被反复退回重算（第一版直接改快照，20261101b 的检查脚本 E3 / R1 当场红）。
--      ★账号和拥有只进 meta、不进快照：matches.left/right_snapshot 所有登录用户都读得到 —— 拥有放进去 = 谁都看得到别人在主站
--        有哪些龟；账号放进去 = 机器人池那一侧没有账号、一眼看出是机器人（用户 10-04「不能让玩家知道是机器人」）。
--      ★「周赛任务的 owned 字段」在这里统一填（积分赛 / 闯关 / 决赛 / 偷袭都经领活这一步），不去改五六个建任务函数。
--   ⑥ pet_xp_grant(对局, 种类, 账号, 快照, 开算时的拥有, 赢了吗)：给这一侧上场的三只统领里「开算时就拥有（meta 里记的）且现在还拥有」
--      的龟发经验；限免龟不发。同一 (match_id, 账号, 龟) 只发一次。升了级且已绑定（mainsite_accounts 有行）⇒ 同一事务写一条
--      pet-level 发件箱（{userId, petKey, level}，幂等键 = 主站用户 + 龟 + 新等级）。
--   ⑦ 触发器 pet_xp_on_job_done：referee_jobs 变成 done（= referee_complete 的那一句 update，同一个事务）且种类是
--      ranked / gauntlet / finals、结果没被顶掉（superseded）⇒ 发经验：A 方一律；B 方只在 B 也是在场真人那几种（决赛、闯关配对局），
--      积分赛的 B 是别人的快照、不是在场的人，不发。偷袭（raid）、切磋、教程都不经这里 ⇒ 不发。
--      ★用触发器而不是改 referee_complete：那个函数 170 多行，偷袭线（20261109c）也要改它；整段重定义会互相顶掉。
--      ★发经验出错只记 warning、不回滚结算（经验晚一点补得上，结算回滚了这一局就要重算）。
--   ⑧ pet_levels_me()（authenticated）：mainsite_me() 那一份（拥有 / 是否绑定）+ levels: {pet_key: {lv, xp}} —— 客户端 PetLevelsNet 一次拿齐。
-- 回滚：drop trigger pet_xp_on_job_done / pet_stamp_on_claim；表与其余函数留着不影响（referee_claim / 快照本段都不改）。
-- ★重复执行安全（create if not exists / create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────

-- ① 表
create table if not exists public.pet_levels (
  account_id uuid        not null references public.accounts(account_id) on delete cascade,
  pet_key    text        not null,
  xp         int         not null default 0 check (xp between 0 and 1350),
  level      int         not null default 1 check (level between 1 and 10),
  updated_at timestamptz not null default now(),
  primary key (account_id, pet_key)
);
alter table public.pet_levels enable row level security;
-- 没有任何策略 ⇒ 客户端直连读写都不行；读自己的走 pet_levels_me()

create table if not exists public.pet_xp_log (
  match_id     uuid        not null,
  account_id   uuid        not null references public.accounts(account_id) on delete cascade,
  pet_key      text        not null,
  kind         text        not null,
  won          boolean     not null,
  xp           int         not null,                 -- 这一局实际加了多少（满级封顶后可能是 0）
  level_before int         not null,
  level_after  int         not null,
  created_at   timestamptz not null default now(),
  primary key (match_id, account_id, pet_key)
);
alter table public.pet_xp_log enable row level security;

-- ② 曲线（= TurtleLevel.xp_to_reach / level_for_xp）
create or replace function public.pet_xp_to_reach(p_lv int) returns int
language sql immutable as $$
  select (least(greatest(coalesce(p_lv, 1), 1), 10) - 1) * (50 + 10 * least(greatest(coalesce(p_lv, 1), 1), 10))
$$;
create or replace function public.pet_level_for_xp(p_xp int) returns int
language sql immutable as $$
  select coalesce(max(l), 1)::int from generate_series(1, 10) l
   where public.pet_xp_to_reach(l) <= greatest(coalesce(p_xp, 0), 0)
$$;
revoke all on function public.pet_xp_to_reach(int) from public, anon, authenticated;
revoke all on function public.pet_level_for_xp(int) from public, anon, authenticated;

-- 28 只（= WeeklyFree.ALL = data/pets.json；门禁 verify_pet_level_r1 逐只比）
create or replace function public.pet_all_ids() returns text[]
language sql immutable as $$
  select array['basic', 'stone', 'bamboo', 'angel', 'ice', 'ninja', 'two_head', 'ghost', 'diamond',
               'fortune', 'dice', 'rainbow', 'gambler', 'hunter', 'pirate', 'candy', 'bubble', 'line', 'lightning', 'phoenix',
               'lava', 'cyber', 'crystal', 'chest', 'space', 'hiding', 'headless', 'shell']
$$;
revoke all on function public.pet_all_ids() from public, anon, authenticated;

-- ③ 拥有
create or replace function public.pet_owned(p_account uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare own text[];
begin
  if p_account is null then
    return '{}';
  end if;
  begin
    select coalesce(array_agg(distinct p.pet_key order by p.pet_key), '{}') into own
      from public.mainsite_pets p
     where p.account_id = p_account and p.pet_key = any(public.pet_all_ids());
  exception when undefined_table then
    own := '{}';                       -- 20261109a 还没上 ⇒ 谁都没绑定
  end;
  return coalesce(own, '{}');
end $$;
revoke all on function public.pet_owned(uuid) from public, anon, authenticated;

-- ④ 开算盖章用的等级表（只算、不改快照；记在任务 meta，见 ⑤）
create or replace function public.pet_lv_table(p_snap jsonb, p_account uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare own text[]; lv jsonb := '{}'::jsonb; x text; l int;
begin
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' then
    return lv;
  end if;
  own := public.pet_owned(p_account);
  if jsonb_typeof(p_snap -> 'leaders') = 'array' then
    for x in select distinct e from jsonb_array_elements_text(p_snap -> 'leaders') e where e <> '' loop
      l := 1;
      if x = any(own) then
        select pl.level into l from public.pet_levels pl where pl.account_id = p_account and pl.pet_key = x;
        l := coalesce(l, 1);
      end if;
      lv := lv || jsonb_build_object(x, l);
    end loop;
  end if;
  return lv;
end $$;
revoke all on function public.pet_lv_table(jsonb, uuid) from public, anon, authenticated;

-- ⑤ 领活那一刻盖章（BEFORE 触发器：referee_claim 把任务改成 claimed 的那一句 update，同一行、同一个事务）
--   · 任务 meta 记 a_account / b_account（账号，没有 = null）、a_owned / b_owned（这一刻的拥有）、a_lv / b_lv（这一刻的等级表）。
--     领活回的任务单 key = meta ∪ {week, match_key} ⇒ 裁判从 key 里读（RefereeJob.pets_allowed / state_for）；
--     补流任务单的 key 同样来自 meta ⇒ 补流重算用的是原来那一刻的，结果可复现。快照本身不动（见文件头 ⑤）。
--   ★用触发器而不是重写 referee_claim：偷袭线（20261109c）也重写了 referee_claim；两份整段重定义谁后执行谁算数，
--     触发器与哪一版 referee_claim 都能一起用，也不改领活的排序 / 过滤。重领（租期过了）会按那一刻的服务器数据再盖一次。
create or replace function public.pet_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.meta := coalesce(new.meta, '{}'::jsonb) || jsonb_build_object(
    'a_account', new.a_account, 'b_account', new.b_account,
    'a_owned', to_jsonb(public.pet_owned(new.a_account)), 'b_owned', to_jsonb(public.pet_owned(new.b_account)),
    'a_lv', public.pet_lv_table(new.a_snapshot, new.a_account), 'b_lv', public.pet_lv_table(new.b_snapshot, new.b_account));
  return new;
end $$;
revoke all on function public.pet_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists pet_stamp_on_claim on public.referee_jobs;
create trigger pet_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.pet_stamp_on_claim();

-- ⑥ 发经验
create or replace function public.pet_xp_grant(p_match uuid, p_kind text, p_account uuid, p_snap jsonb,
    p_owned_then jsonb, p_won boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare own text[]; x text; v_gain int; r record; n int; v_xp int; v_new int; v_uid text; v_out jsonb := '[]'::jsonb;
begin
  if p_match is null or p_account is null or p_won is null or coalesce(p_kind, '') not in ('ranked', 'gauntlet', 'finals') then
    return v_out;                      -- 偷袭 / 切磋 / 教程 / 不认识的种类：不发
  end if;
  if p_snap is null or jsonb_typeof(p_snap) <> 'object' or jsonb_typeof(p_snap -> 'leaders') <> 'array'
     or jsonb_typeof(p_owned_then) is distinct from 'array' then
    return v_out;                      -- 没盖过章（开算时谁拥有不知道）⇒ 一只都不当拥有
  end if;
  v_gain := case when p_won then 8 else 6 end;
  own := public.pet_owned(p_account);
  begin
    select m.mainsite_user_id into v_uid from public.mainsite_accounts m where m.account_id = p_account;
  exception when undefined_table then
    v_uid := null;
  end;
  for x in select distinct e from jsonb_array_elements_text(p_snap -> 'leaders') e where e <> '' order by 1 loop
    -- 限免龟不发：开算时拥有（领活时记进 meta 的）且现在还拥有（mainsite_pets）
    continue when not (x = any(own)) or not (p_owned_then ? x);
    insert into public.pet_levels (account_id, pet_key) values (p_account, x) on conflict do nothing;
    select * into r from public.pet_levels where account_id = p_account and pet_key = x for update;
    v_xp := least(r.xp + v_gain, public.pet_xp_to_reach(10));
    v_new := public.pet_level_for_xp(v_xp);
    insert into public.pet_xp_log (match_id, account_id, pet_key, kind, won, xp, level_before, level_after)
      values (p_match, p_account, x, p_kind, p_won, v_xp - r.xp, r.level, v_new)
      on conflict (match_id, account_id, pet_key) do nothing;
    get diagnostics n = row_count;
    continue when n = 0;               -- 这一局这只龟发过了（幂等）
    update public.pet_levels set xp = v_xp, level = v_new, updated_at = now()
     where account_id = p_account and pet_key = x;
    if v_new > r.level and v_uid is not null then
      perform public.mainsite_outbox_put('pet-level', format('%s:%s:%s', v_uid, x, v_new),
        jsonb_build_object('userId', v_uid, 'petKey', x, 'level', v_new));
    end if;
    v_out := v_out || jsonb_build_object('pet', x, 'xp', v_xp, 'lv', v_new, 'up', v_new > r.level);
  end loop;
  return v_out;
end $$;
revoke all on function public.pet_xp_grant(uuid, text, uuid, jsonb, jsonb, boolean) from public, anon, authenticated;

-- ⑦ 结算即发（referee_complete 那一句 update 同一个事务）
create or replace function public.pet_xp_on_job_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare a_won boolean;
begin
  if new.status <> 'done' or old.status = 'done' or new.kind not in ('ranked', 'gauntlet', 'finals')
     or new.error is not distinct from 'superseded' or coalesce(new.result ->> 'winner', '') not in ('a', 'b') then
    return null;
  end if;
  a_won := new.result ->> 'winner' = 'a';
  begin
    perform public.pet_xp_grant(new.match_id, new.kind, new.a_account, new.a_snapshot, new.meta -> 'a_owned', a_won);
  exception when others then
    raise warning 'pet_xp_grant a job % : %', new.job_id, sqlerrm;
  end;
  if new.b_account is not null
     and (new.kind = 'finals' or (new.kind = 'gauntlet' and coalesce(new.meta ->> 'pair', '') = 'true')) then
    begin
      perform public.pet_xp_grant(new.match_id, new.kind, new.b_account, new.b_snapshot, new.meta -> 'b_owned', not a_won);
    exception when others then
      raise warning 'pet_xp_grant b job % : %', new.job_id, sqlerrm;
    end;
  end if;
  return null;
end $$;
revoke all on function public.pet_xp_on_job_done() from public, anon, authenticated;
drop trigger if exists pet_xp_on_job_done on public.referee_jobs;
create trigger pet_xp_on_job_done after update of status on public.referee_jobs
  for each row when (new.status = 'done' and old.status is distinct from 'done')
  execute function public.pet_xp_on_job_done();

-- ⑧ 客户端读自己的：mainsite_me() 那一份（A1 的 mainsite_status：{ok, linked, user_id, owned, fetched_at}，同一个函数）+ levels。
--   一次请求把「拥有」和「等级」都带回去（Supabase 出站流量 #23）。
create or replace function public.pet_levels_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); st jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signed_in');
  end if;
  begin
    st := public.mainsite_status(uid);
  exception when undefined_function or undefined_table then
    st := jsonb_build_object('ok', true, 'linked', false, 'user_id', null, 'owned', '[]'::jsonb, 'fetched_at', null);
  end;
  return st || jsonb_build_object('levels', coalesce((select jsonb_object_agg(l.pet_key, jsonb_build_object('lv', l.level, 'xp', l.xp))
                                                        from public.pet_levels l where l.account_id = uid), '{}'::jsonb));
end $$;
revoke all on function public.pet_levels_me() from public, anon;
grant execute on function public.pet_levels_me() to authenticated;
-- <<< END pet_levels 20261109b <<<
-- >>> BEGIN econ_wheel 20261109d >>>
-- ─────────────────────────────────────────────────────────────
-- 赌神命运之轮跨场层数进记账（2026-11-09 · 方案书 20261107-龟战主站对接 §4.6「补命运之轮记账」、
--   20261106-装备与深海币服务器记账 状态行待办「gambler_wheel_stacks 是快照自报、不经记账口」）
--   现状：一大轮内累积的花色只在快照里自报（Backend.build_ghost_snapshot 的 wheel_stacks），裁判照单全收 ⇒ 改存档就能多拿层数；
--   偷袭押的是龟币，固定阵容的强弱直接决定输赢（§4.9）。
--   做法：服务器本来就有每一局的结果单（0.22.8 起带 wheel_new / wheel_new_b，20261106h），累加就是这个号本周应有的层数，
--   不另开一条流水（同一件事记两份必然漂移）：
--   ① econ_wheel_sum(账号, 周)：本周已算完的周赛局里这个号自己抽到的花色合计。口径同 econ_facts：A 方一律算；B 方只在
--      B 是在场真人那几种（决赛、闯关配对局）算 —— 积分赛的 B 是别人的快照，那一局抽到的不归快照主人。偷袭局不算
--      （偷袭不发任何东西，20261109c）。
--   ② 触发器 econ_wheel_stamp_on_claim（BEFORE：任务变成 claimed 的那一句 update，同 20261109b pet_stamp_on_claim）：
--      记账开关 econ_on 开着时，任务 meta 记 a_wheel / b_wheel = 双方的 econ_wheel_sum；裁判（referee_job.gd state_for）
--      拿它给快照自报的层数**封顶**（每种花色取较小值）。封顶而不是覆盖：积分赛的 B 是旧快照，快照之后快照主人又抽到的不该算进去；
--      本人没收到某局结果（关了 App）时自报偏少，与现状一样、不会因此变多。
--      账号为空（机器人池）那一侧不盖 ⇒ 快照原样（服务器自己造的快照）。
--   开关 econ_on 关着 ⇒ 不盖章，开局行为一字不变；偷袭只在 econ_on 开着时开（raid_enabled），所以偷袭局一定有章。
--   快照本身一个字不改（决赛坏快照回退拿任务快照逐字比，见 20261109b ⑤）。
-- 回滚：drop trigger econ_wheel_stamp_on_claim on public.referee_jobs（裁判见不到 a_wheel / b_wheel ⇒ 照快照）。
-- ★重复执行安全（create or replace / drop trigger if exists）。
-- ─────────────────────────────────────────────────────────────
create or replace function public.econ_wheel_sum(p_uid uuid, p_week bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(t.k, t.n), '{}'::jsonb)
    from (
      select e.key as k, sum(least(greatest(round((e.value #>> '{}')::numeric), 0), 99))::int as n
        from public.referee_jobs j
        cross join lateral jsonb_each(
          case when jsonb_typeof(j.result -> case when j.a_account = p_uid then 'wheel_new' else 'wheel_new_b' end) = 'object'
               then j.result -> case when j.a_account = p_uid then 'wheel_new' else 'wheel_new_b' end
               else '{}'::jsonb end) e
       where p_uid is not null and j.season_week = p_week and j.status = 'done' and j.result is not null
         and j.kind in ('ranked', 'gauntlet', 'finals')
         and (j.a_account = p_uid or (j.b_account = p_uid and (j.kind = 'finals' or j.meta ->> 'pair' = 'true')))
         and e.key in ('spade', 'heart', 'diamond', 'club') and jsonb_typeof(e.value) = 'number'
       group by e.key
    ) t
   where t.n > 0
$$;
revoke all on function public.econ_wheel_sum(uuid, bigint) from public, anon, authenticated;

create or replace function public.econ_wheel_stamp_on_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.referee_econ_on() then
    new.meta := coalesce(new.meta, '{}'::jsonb) - 'a_wheel' - 'b_wheel';
    if new.a_account is not null then
      new.meta := new.meta || jsonb_build_object('a_wheel', public.econ_wheel_sum(new.a_account, new.season_week));
    end if;
    if new.b_account is not null then
      new.meta := new.meta || jsonb_build_object('b_wheel', public.econ_wheel_sum(new.b_account, new.season_week));
    end if;
  end if;
  return new;
end $$;
revoke all on function public.econ_wheel_stamp_on_claim() from public, anon, authenticated;
drop trigger if exists econ_wheel_stamp_on_claim on public.referee_jobs;
create trigger econ_wheel_stamp_on_claim before update of status on public.referee_jobs
  for each row when (new.status = 'claimed') execute function public.econ_wheel_stamp_on_claim();
-- <<< END econ_wheel 20261109d <<<
