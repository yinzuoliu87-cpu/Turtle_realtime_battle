# 服务器裁判 · 部署与运维

> 方案书：[docs/plans/20261019-服务器裁判.md](../../docs/plans/20261019-服务器裁判.md)（§1 裁判机 / §3 ①② 周日、周六）
> 裁判程序（Godot 侧）：[scripts/referee/](../../scripts/referee/) · 入口场景 `res://scenes/Referee.tscn`
> 表与 RPC：[server/supabase/migrations/20261019_referee_jobs.sql](../supabase/migrations/20261019_referee_jobs.sql)（已同步到 `schema.sql` 末尾，逐字相同）
> 门禁：`tests/verify_referee_job_roundtrip.gd`
>
> **本目录的东西都还没部署、迁移也没上生产。** 下面是上线时照着做的步骤。

## 它是什么

```
客户端 / pg_cron ──建任务──► referee_jobs(pending)
                                 │  referee_claim(service key, for update skip locked)
                    裁判机 ◄─────┘
   referee_poller.py ×N 线程 ──► godot --headless … res://scenes/Referee.tscn -- --job=… --out=…
                                 │  左 = A 快照、右 = B 快照、种子来自任务单；没有人的输入；跑完整一局双路
                                 ▼
                         结果单(胜方 / 比分码 / 步数 / 终局指纹 / 录像 base64)
   referee_complete ──► 一个事务：matches(录像, 与客户端上传同一格式) + 赛果
                          周日 finals_results(winner_side + loser_lanes 比分码)
                          闯关赛 gauntlet_records(服务端战绩账本) + gauntlet_ghosts(新战绩标签) + 第 4 胜登记 finals_pending(20261026b)
```

- 一局多快（本机 Windows x86_64 实测，Godot 4.6.3 无头）：三路打满 10469 步 ≈ **10~15 秒**墙钟（含 Godot 启动 ~1 秒）；两路 4300 步 ≈ 5.5 秒；一边倒上路碎蛋 1115 步 ≈ 1 秒。约 0.9~1.3 ms / sim 步。
- CX33 4 核：`WORKERS=4` ⇒ 每分钟约 16~40 局。闯关赛 140 人 × 6 场 ≈ 840 局（2026-10-26 起摊在周六 00:00 ~ 周日 17:30 UTC 一天半里），周日决赛日一轮最多几十场，都够。
- **现状（2026-10-26 起）：CPX22 2 核 / 4 GB，正式服 `WORKERS=2`**（核数 = 线程数，多开会抢核、单局变慢）。同一探针录流 149 步/秒 = 2.5 倍实时，与原 CPX32 持平。人多了换回 CPX32 + `WORKERS=4`（关机换型约 36 秒）。
- 结果只在**同一个客户端版本**里成立：`VERSIONS_DIR` 下一个版本一份工程，轮询器只领本机装了的版本。

## 文件

| 文件 | 去哪 |
|---|---|
| `referee_poller.py` | `/opt/turtle/referee/referee_poller.py`（只用标准库） |
| `turtle-referee.service` | `/etc/systemd/system/` |
| `turtle-referee-health.service` + `.timer` | `/etc/systemd/system/`（每分钟查一次积压 / 心跳，失败进 journald） |
| （逐帧直播）`STREAM_ROOT` 环境变量 | 设了就边算边把状态流块发布到该目录，由 Caddy 分发；默认不设 = 不录。见 [server/stream/README.md](../stream/README.md) |
| 每个版本的游戏工程 | `/opt/turtle/v<版本>/`（整个仓库那一版的 checkout；**必须含 `scenes/Referee.tscn`**，即本功能合入之后的版本 —— 现在机器上的 v571 没有，轮询器会跳过它） |

## 部署步骤（第一次）

0. 前提：Godot 4.6.3 已在 `/opt/godot/godot`（与客户端同一个引擎版本；`godot --version` 核对）。

1. 用户与目录
   ```bash
   sudo useradd --system --home /var/lib/turtle-referee --shell /usr/sbin/nologin turtle-referee
   sudo mkdir -p /var/lib/turtle-referee /opt/turtle/referee /etc/turtle-referee
   sudo chown -R turtle-referee: /var/lib/turtle-referee /opt/turtle
   ```

2. 放一个版本的工程（以合入本功能后的第一个版本 `0.19.5xx` 为例）
   ```bash
   sudo -u turtle-referee git clone --depth 1 --branch v0.19.5xx <仓库地址> /opt/turtle/v0.19.5xx
   # 导入一次(生成 .godot/ 缓存; 不做这步第一次跑会边导入边跑, 慢且日志一堆 ERROR)
   sudo -u turtle-referee HOME=/var/lib/turtle-referee XDG_DATA_HOME=/var/lib/turtle-referee/import-ud \
     /opt/godot/godot --headless --path /opt/turtle/v0.19.5xx --import
   ```
   ★`.uid` / `.import` 文件导入后可能被改写行尾，属正常；不要拿这份工程做别的。

3. 先在这台机器上验一遍确定性（与 CI 金标对得上，才算这台机器能当裁判）
   ```bash
   cd /opt/turtle/v0.19.5xx
   sudo -u turtle-referee XDG_DATA_HOME=/tmp/rv TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' \
     /opt/godot/godot --headless --audio-driver Dummy --path . res://tests/verify_determinism_cross.tscn --quit-after 40000
   sudo -u turtle-referee XDG_DATA_HOME=/tmp/rv2 TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' \
     /opt/godot/godot --headless --audio-driver Dummy --path . res://tests/verify_referee_job_roundtrip.tscn --quit-after 60000
   ```
   两个都要打出 `ALL PASS`。

4. 轮询器与密钥
   ```bash
   sudo cp server/referee/referee_poller.py /opt/turtle/referee/
   sudo tee /etc/turtle-referee/env >/dev/null <<'EOF'
   SUPABASE_URL=https://<项目>.supabase.co
   SUPABASE_SERVICE_KEY=<service_role 密钥>
   GODOT_BIN=/opt/godot/godot
   VERSIONS_DIR=/opt/turtle
   WORK_DIR=/var/lib/turtle-referee
   WORKERS=4
   EOF
   sudo chown root:turtle-referee /etc/turtle-referee/env && sudo chmod 640 /etc/turtle-referee/env
   sudo -u turtle-referee env $(sudo cat /etc/turtle-referee/env | xargs) python3 /opt/turtle/referee/referee_poller.py --versions
   ```
   ★service key 只在这个文件里（不进仓库、不进 Godot 进程的环境：轮询器调 Godot 前会把它从环境里删掉）。

5. 不连库先跑一份本地任务单（门禁可以吐一份：`REFEREE_DUMP_DIR=/tmp/dump` 跑第 3 步那个门禁 ⇒ `/tmp/dump/job1.json`）
   ```bash
   sudo -u turtle-referee env $(sudo cat /etc/turtle-referee/env | xargs) \
     python3 /opt/turtle/referee/referee_poller.py --local /tmp/dump/job1.json --out /tmp/dump/srv_result.json
   ```
   `digest` / `replay_b64` 要与 `/tmp/dump/result1.json`（同一台机器上门禁那一遍）逐字相同；
   再拿 Windows 上门禁吐的那份比一次 = 跨平台对账（本机 Windows 实测：三路 10469 步 `digest=5777c9a28381e5cc`，任务单见门禁 R1 第一个候选种子 2000023）。

6. 上迁移（★先只上内测服；正式服等客户端那一侧接好）
   - 把 `server/supabase/migrations/20261019_referee_jobs.sql` 在 SQL Editor 里整段执行。两个开关默认关 ⇒ **执行本身不改变任何现行行为**
     （`finals_advance` / `finals_report` / `finals_enter` 三个被重定义的函数在开关关着时逐字等于原版）。
   - ⚠ 生产库的函数体可能与 `schema.sql` 不同（过去上线是手工截段），执行前拿生产版 `pg_get_functiondef` 对一遍这三个。
   - 登记版本：`insert into public.referee_versions (client_version) values ('0.19.5xx');`

7. 起服务
   ```bash
   sudo cp server/referee/turtle-referee*.service server/referee/turtle-referee-health.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now turtle-referee turtle-referee-health.timer
   journalctl -u turtle-referee -f
   ```

8. 冒烟（内测服）：手工插一份任务 ⇒ 看它被领、被写回
   ```sql
   insert into public.referee_jobs (kind, match_key, season_week, client_version, seed, a_account, a_snapshot, b_snapshot, level)
   select 'gauntlet', 'smoke:' || now(), extract(epoch from date_trunc('week', now() at time zone 'UTC'))::bigint,
          '0.19.5xx', public.referee_new_seed(), null, snapshot, snapshot, 6
     from public.ghosts limit 1;
   select job_id, status, attempts, error, result->'ledger' from public.referee_jobs order by job_id desc limit 3;
   select public.referee_backlog();
   ```
   （`a_account` 为 null 时只落 `matches`、不记周六账本；冒烟完删掉这一行与对应 matches 行。）

9. 翻开关（客户端那一侧做完、内测服彩排过之后）
   ★先上 `server/supabase/migrations/20261019b_referee_client_flags.sql`（`referee_flags()`, 只读两个布尔）: 客户端靠它知道开关开没开;
     没上之前客户端问到 404 = 两个开关都关 ⇒ 开关在库里翻开了客户端也照走老路(周日本机打 / 周六本机记)。
     客户端: `scripts/net/referee_net.gd` / `scripts/systems/replay/referee_watch.gd` / `referee_run.gd`(门禁 verify_finals_watch_only / verify_gauntlet_via_referee / verify_offline_no_local_result)。
   ```sql
   -- 周日: 先定这周用哪个版本算(= 当周锁定的客户端版本, 且已在 referee_versions)
   update public.referee_config set finals_version = '0.19.5xx', finals_on = true, updated_at = now() where id = 1;
   -- 闯关赛(周六 00:00 ~ 周日 17:30 UTC)
   update public.referee_config set gauntlet_on = true, updated_at = now() where id = 1;
   ```
   回滚 = 把开关翻回 false（任务表留着无害；已写的赛果不动）。

## 发版时（每个新版本）

1. `/opt/turtle/v<新版本>/` 放工程 + `--import` + 第 3 步两个门禁；
2. `insert into referee_versions …`；轮询器每轮自动重扫目录，**不用重启**；
3. 周日用的版本改 `referee_config.finals_version`；
4. **闯关赛机器人池**（20261020c 起；闯关赛对手由服务端挑，挑不到同标签真人就从池里取机器人）：
   `referee_poller.py --bot-pool --version <新版本>`（调这个版本的 Godot 生成 2052 份 = `Backend.make_bot` 同一个函数，分批上传，
   同时把 `referee_versions.rules_ver` 登记上）。回读 `select public.referee_backlog()->'bot_pool';` 新版本 `rows` = 2052。
   ★忘了这一步：那个版本的玩家挑不到机器人 ⇒ 开战回 `no_opponent`（屏上「匹配失败，请稍后重试」）；`--health` 在闯关赛开着时报警。
5. 旧版本的任务清空之后（`select client_version, count(*) from referee_jobs where status in ('pending','claimed') group by 1`）再删旧目录、`update referee_versions set enabled = false`。

## 运维

- 积压 / 心跳：`select public.referee_backlog();`；timer 每分钟跑 `referee_poller.py --health`，`oldest_pending_sec > 120` 或任何一个裁判 120 秒没心跳 ⇒ 退出码 1（`systemctl status turtle-referee-health`）。
- 失败的任务：`select job_id, kind, match_key, attempts, error from referee_jobs where status = 'failed' order by job_id desc;`
  `error` 是裁判程序的短码（`wrong_version` / `a_bad_snapshot` / `b_bad_snapshot` / `bad_seed` / `step_cap` / `frame_cap` / `rc=… <日志尾>`）。
  非永久错误放回 pending 重领，最多 `max_attempts`（默认 3）次。
- 领了没写回（裁判机挂了 / 断网）：租期 `lease_sec`（默认 180 秒）一过别的线程重领。
- 周日兜底：开关开着时真实场次只等裁判；**超过 3 倍本轮时长（24 分钟）仍没结果**才退回原来的 side 0 代判（防整组卡死）。
- 每局的日志在 `/var/lib/turtle-referee/w<线程号>/godot.log`（只留最近一局）。

## 内测服第二套（2026-10-21 部署 · 方案书 [docs/plans/20261020-内测服.md](../../docs/plans/20261020-内测服.md) §6）

同机两套轮询器，**正式服那套（`turtle-referee.service` / `/etc/turtle-referee/env` / `/opt/turtle/`）一个字不动**。

| 项 | 内测服那套 |
|---|---|
| unit | `turtle-referee-beta.service`（不 enable；由高峰停起 timer 起停）· `Nice=15` · `CPUQuota=100%` · `IOSchedulingClass=idle` |
| env | `/etc/turtle-referee/env-beta`（root:turtle-referee 640）：`SUPABASE_URL` = turtle-beta、`SUPABASE_SERVICE_KEY` = 内测服 secret key（本机副本 `~/.supabase/beta-service-key`）、`VERSIONS_DIR=/opt/turtle-beta`、`WORK_DIR=/var/lib/turtle-referee-beta`、`WORKERS=1`、`STREAM_ROOT=/var/lib/turtle-referee-beta/streams`、`WORKER_NAME=beta` |
| 代码 | `/opt/turtle-beta/referee/referee_poller.py`（自己一份，root 644；内测服先试新轮询器）· `/opt/turtle-beta/stream/stream_ops.py` |
| 工程版本 | `/opt/turtle-beta/v<版本>/`（2026-10-21：v0.21.3 = 正式那份的拷贝、v0.21.4 = 拷贝后 checkout tag 再 `--import`；det_cross 37/37、job_roundtrip 65 ALL PASS）|
| 高峰停起 | `turtle-referee-beta-peak.timer`（每 5 分钟）→ `beta_peak_guard.sh`：周六、周日全天 UTC（2026-10-26 起；原为周日 17:30 起） 停，其余起；`/etc/turtle-referee/beta-off` 存在 ⇒ 一直停 |
| 健康检查 | `turtle-referee-beta-health.timer`（每 5 分钟，只进 journald，不进正式服报警口径）|
| 直播 | Caddy 同一站点 `/beta/streams/*` → `/var/lib/turtle-referee-beta/streams`；版本闸片段 `/etc/caddy/turtle-min-version-beta.caddy`（`turtle-stream-minver-beta.timer`，匹配器 `@stream_old_beta`）；清理 `turtle-stream-purge-beta.timer`（每小时 :07）|
| 机器人池 | `python tools/beta_ops.py seed-bots`（ssh 跑内测服那份 `--bot-pool`）|

装新版本（内测服）：`cp -a /opt/turtle-beta/v<旧> /opt/turtle-beta/v<新>` → 以 turtle-referee 身份 `git fetch --depth 1 origin tag v<新> && git checkout -f v<新>` →
`--import`（`XDG_DATA_HOME=/var/lib/turtle-referee-beta/import-ud`）→ 跑 det_cross / job_roundtrip → 内测服 `referee_versions` 登记 → `systemctl restart turtle-referee-beta`。
回滚 / 拆除：`systemctl disable --now turtle-referee-beta-peak.timer turtle-referee-beta-health.timer turtle-stream-minver-beta.timer turtle-stream-purge-beta.timer; systemctl stop turtle-referee-beta`；
Caddy 拷回 `/root/betadeploy/Caddyfile.bak-20261021` → `caddy validate` → `systemctl reload caddy`。部署前正式服文件的 sha256 在 `/root/betadeploy/prod_before.sha256`。

## 常驻陪练号（2026-10-26 · 方案书 [docs/plans/20261026d-服务器常驻陪练号.md](../../docs/plans/20261026d-服务器常驻陪练号.md)）

用户 10-26「去服务器安排机器人，每个时段都去分布」「号就跟真人一样」。把内测时本机跑的模拟号（`SIM_DRIVER=1` 真账号）搬到这台机器，按时段排班。

| 件 | 位置 |
|---|---|
| 排班 | `bot_schedule.py`：每周一 00:05 UTC 由 `turtle-bot-schedule-beta.timer` 生成本周时间表（陪练号数 = clamp(100 − 上周真人, 30, 90)） |
| 拉起 | `bot_runner.py`：`turtle-bot-runner-beta.timer` 每 5 分钟起到点的上线（无头客户端，打完自己退），同时最多 `MAX_PAR` 个；晚到超过 `STALE_MIN` 分钟的作废、不补打 |
| env | `/etc/turtle-referee/env-bots-beta`：`GODOT_BIN` / `BOT_GAME_DIR`（**= 玩家手机上的发布版**）/ `BOT_ROOT=/var/lib/turtle-bots-beta` / `BOT_SCHEDULE=$BOT_ROOT/schedule.json` / `MAX_PAR=1` / `REAL_LAST_WEEK` / 内测服后端配置 |
| 账号 | 每个号的存档在 `$BOT_ROOT/pNN/`（user:// = `XDG_DATA_HOME`），跨周保留战绩 |

⚠ **同机还有正式服裁判**：`MAX_PAR` 先给 1，量完 CPU（每局陪练客户端占多少核秒、高峰时裁判排不排队）再调；不够就换机器配置（花钱，先问用户）。
⚠ 发新版后要重建 `BOT_GAME_DIR`（同裁判「发版时」那一节：拷目录 → checkout 新 tag → `--import`）。

### 常驻陪练号 · 内测服首次部署步骤

> 2026-10-26 照仓库代码写成，**还没在机器上执行过**；执行时有出入以机器上的实际情况为准，回填这里。
> 只管内测服；正式服那套（`turtle-referee.service` / `/etc/turtle-referee/env` / `/opt/turtle/`）一个字不动。
> 「`<ver>`」= TestFlight 上玩家手机里那一版（tag 名 `v<ver>`；写这节时是 `0.22.1`）。

0. 前提与拷文件
   - 内测服第二套已在跑（上一节）；`/opt/godot/godot` 是 4.6.3 **编辑器版**（能 `--import` 的那个）——`TURTLE_SERVER=beta` 只在 debug 构建里认（`scripts/net/server_env.gd:29-30`），换成 release 导出模板会**悄悄连到正式服**。
   - 陪练号的文件都在 main、不在 v0.22.1 tag 里 ⇒ 从本机仓库拷：
   ```bash
   # 本机仓库根目录
   ssh -i ~/.ssh/turtle_referee root@<裁判机> mkdir -p /root/botdeploy
   scp -i ~/.ssh/turtle_referee server/referee/bot_runner.py server/referee/bot_schedule.py \
     server/referee/turtle-bot-*.service server/referee/turtle-bot-*.timer root@<裁判机>:/root/botdeploy/
   ```
   ```bash
   # 裁判机上（仓库文件可能是 CRLF，装时一律 tr -d '\r'）
   for f in bot_runner.py bot_schedule.py; do
     tr -d '\r' < /root/botdeploy/$f | sudo tee /opt/turtle-beta/referee/$f >/dev/null
     sudo chmod 644 /opt/turtle-beta/referee/$f; python3 -m py_compile /opt/turtle-beta/referee/$f
   done
   sudo mkdir -p /opt/turtle-bots-beta /var/lib/turtle-bots-beta
   sudo chown turtle-referee: /opt/turtle-bots-beta /var/lib/turtle-bots-beta
   ```

1. 陪练号跑的工程 `BOT_GAME_DIR = /opt/turtle-bots-beta/v<ver>`（memory「模拟号必须跑发布版代码」）
   - ★**不许放在 `/opt/turtle-beta/` 或 `/opt/turtle/` 下面**：`referee_poller.py` 的 `discover_versions` 把那一层每个带 `project.godot` 的子目录都当成裁判版本。
   - ★不与内测服裁判共用 `/opt/turtle-beta/v<ver>`（本 README 第 2 步：那份工程不拿来做别的）。
   ```bash
   VER=0.22.1
   # A. 内测服裁判已装这一版（ls /opt/turtle-beta/）⇒ 拷一份（已导入，最快）
   sudo -u turtle-referee cp -a /opt/turtle-beta/v$VER /opt/turtle-bots-beta/v$VER
   # B. 没装 ⇒ tag 克隆
   sudo -u turtle-referee git clone --depth 1 --branch v$VER <仓库地址> /opt/turtle-bots-beta/v$VER
   # A / B 都要：核对是那个 tag、驱动认 bot_runner 给的参数，再导入一次
   cd /opt/turtle-bots-beta/v$VER
   sudo -u turtle-referee git describe --tags --exact-match          # 必须打出 v$VER
   grep -c 'SIM_ROUNDS\|SIM_QUIT_WHEN_DONE' scripts/systems/sim/sim_driver.gd   # > 0
   sudo -u turtle-referee HOME=/var/lib/turtle-referee XDG_DATA_HOME=/var/lib/turtle-bots-beta/import-ud \
     /opt/godot/godot --headless --path /opt/turtle-bots-beta/v$VER --import
   ```
   - main 的 `scripts/systems/sim/` 比 tag 新时（本机 `git diff --stat v$VER origin/main -- scripts/systems/sim`；v0.22.1 → main 为空）：只把这一个目录覆盖进去、再 `--import` 一次（目录里有 `class_name`）。战斗代码一律保持 tag 原样。
   - 内测服 `service_status.min_client_version` 必须 ≤ `<ver>`，否则号一进主菜单就被版本墙拦下、立刻退出；周六闯关要内测服裁判也装了 `<ver>`（上一节「装新版本」）。
   - 发新版：照这一步建 `v<新>` → 改 env 里的 `BOT_GAME_DIR`（runner 每次由 timer 新起、重读 env，不用重启）→ `pgrep -af "turtle-bots-beta/v<旧>"` 为空后删旧目录。

2. env 与启动包装
   ```bash
   sudo tee /etc/turtle-referee/env-bots-beta >/dev/null <<'EOF'
   GODOT_BIN=/opt/turtle-bots-beta/godot-bot.sh
   BOT_GAME_DIR=/opt/turtle-bots-beta/v0.22.1
   BOT_ROOT=/var/lib/turtle-bots-beta
   BOT_SCHEDULE=/var/lib/turtle-bots-beta/schedule.json
   MAX_PAR=1
   STALE_MIN=30
   REAL_LAST_WEEK=0
   BOT_SESSION_CAP_SEC=3600
   TURTLE_SERVER=beta
   TURTLE_SUPABASE=https://<内测服 ref>.supabase.co
   EOF
   sudo chown root:turtle-referee /etc/turtle-referee/env-bots-beta && sudo chmod 640 /etc/turtle-referee/env-bots-beta
   ```
   - **后端只靠 `TURTLE_SERVER=beta`**：地址、公开 key、直播地址、内测服时钟偏移一起换（`server_env.gd` → `net_route.gd:79-99` / `supabase.gd:79-81`），内测服不走大陆中转。公开 key 已在 `project.godot` 的 `turtle/supabase_anon_key.beta_server`，**env 里不放任何 key**。
   - `TURTLE_SUPABASE` 填 `project.godot` 里 `turtle/supabase_url.beta_server` 那个地址，是**防连错服的保险**：万一 `TURTLE_SERVER` 没生效，地址仍是内测服、key 却是正式服的 ⇒ 401 什么都写不进去，而不是悄悄在正式库里建 90 个号。
   - 一律**不写**：`SUPABASE_SERVICE_KEY` / `SUPABASE_URL`（`bot_runner.py:81` 把整份环境原样传给客户端）、`TURTLE_RELAY`、`TURTLE_BACKEND`、`SIM_CLOCK_OFFSET`、`TURTLE_FAKE_NOW`、`TURTLE_SEED`（会切成确定性每帧一步）、`ONBOARD`、`SIM_ACCOUNT_ONLY`、`SIM_TUTORIAL`（默认 play = 像新玩家一样走教程）。
   - 每个值不含空格、不引用别的变量：同一份文件既给 systemd `EnvironmentFile` 读，也给下面的 `botenv` 用 bash 读。
   - 启动包装（`GODOT_BIN` 指向它）：单次上线墙钟上限 + 记每次上线的 CPU 秒（U3 要的数）。`bot_runner.py` 自己没有超时，卡住的号会一直占着 `MAX_PAR=1`（见文末「部署前已知阻塞」①）。
   ```bash
   sudo tee /opt/turtle-bots-beta/godot-bot.sh >/dev/null <<'EOF'
   #!/bin/bash
   t0=$(date +%s)
   timeout --kill-after=60 "${BOT_SESSION_CAP_SEC:-3600}" /opt/godot/godot ${BOT_MAX_FPS:+--max-fps $BOT_MAX_FPS} "$@"
   rc=$?
   echo "$(date -u +%FT%TZ) rc=$rc wall=$(( $(date +%s) - t0 ))s cpu_user_sys=$(times | tail -n 1)" >> "${XDG_DATA_HOME:-/tmp}/sessions.log"
   exit $rc
   EOF
   sudo chmod 755 /opt/turtle-bots-beta/godot-bot.sh
   # 之后的手动命令都用它：以 turtle-referee 身份、带上 env-bots-beta
   botenv() { sudo -u turtle-referee bash -c 'set -a; . /etc/turtle-referee/env-bots-beta; set +a; exec "$@"' _ "$@"; }
   ```
   `rc=124/137` = 到上限被杀（对局中被杀走产品自己「杀进程不作废、下次补打完」那条路）。

3. 账号
   - 新槽位第一次上线自己建号：主菜单 `_ready` 的 `ensure_signed_in_async()` 匿名注册 → 首启流程（`sim_driver.gd:311-329`：介绍按「跳过」→ 选择框按 `SIM_TUTORIAL`，默认「开始教程」→ 起名框按「确认」）→ 教程不计入 `SIM_ROUNDS`。
   - `SIM_DRIVER` 必须**恰好是 `1`**：无头且不是 `1` ⇒ `GameState.gd:1491` 进 test_mode，不写存档、不推云存档。
   - 预建 N 个号、不打（`SIM_ACCOUNT_ONLY=1` + `ONBOARD=0`，同 `tools/sim60.sh` 的 `ACCOUNT_ONLY`；拿到 `account_id` 写盘就退，`sim_driver.gd:184-195`）。`ONBOARD=0` 只管这一次：号还是 0 场，第一次正式上线照样走首启 + 教程。
   - ★先只建 p01 验证连的是内测服：本机 `python tools/beta_ops.py status --no-ssh` 前后各跑一次，`auth.users` 要 +1。之后再建其余的。
   - 所有号同一个出口 IP：Supabase 匿名注册有按 IP 的每小时上限（默认值以 Supabase 后台 Auth → Rate Limits 为准）⇒ 下面每个号间隔 150 秒（≈ 每小时 24 个）。
   ```bash
   acct() { sudo python3 -c 'import glob,json,sys; f=glob.glob(sys.argv[1]+"/*/app_userdata/*/savegame.json"); print(json.load(open(f[0])).get("account_id","") if f else "")' "$1"; }
   N=90
   for n in $(seq 1 $N); do
     d=$(printf /var/lib/turtle-bots-beta/p%02d $n)
     [ -n "$(acct $d)" ] && continue
     sudo -u turtle-referee mkdir -p $d
     botenv env XDG_DATA_HOME=$d APPDATA=$d SHIP=1 QUIET=1 SIM_AUTOPILOT=1 SIM_DRIVER=1 \
       SIM_SLOT=$n SIM_ACCOUNT_ONLY=1 ONBOARD=0 \
       sh -c 'exec timeout 180 "$GODOT_BIN" --headless --audio-driver Dummy --path "$BOT_GAME_DIR" -- --sim-slot=$SIM_SLOT --sim-root=turtle-bots > "$XDG_DATA_HOME/account.log" 2>&1'
     printf 'p%02d %s\n' $n "$(acct $d)"
     sleep 150
   done
   ```
   空账号的号重跑这段即可（已有号的跳过）；原因看 `$d/account.log` 与 `$d/*/app_userdata/*/sim_events.jsonl` 最后一行 `"kind":"account"`。

4. 装 unit、试跑、开定时器
   ```bash
   for f in /root/botdeploy/turtle-bot-*.service /root/botdeploy/turtle-bot-*.timer; do
     tr -d '\r' < $f | sudo tee /etc/systemd/system/$(basename $f) >/dev/null
   done
   # 限资源 + 停用开关 + 周末不起（理由见第 5 步）。cgroup v2 下跨服务按 CPUWeight 分核，光 Nice 护不住正式服裁判
   sudo mkdir -p /etc/systemd/system/turtle-bot-runner-beta.service.d
   sudo tee /etc/systemd/system/turtle-bot-runner-beta.service.d/limits.conf >/dev/null <<'EOF'
   [Service]
   CPUWeight=10
   CPUQuota=50%
   Nice=19
   IOSchedulingClass=idle
   ExecCondition=/bin/sh -c 'test ! -e /etc/turtle-referee/bots-beta-off && test "$$(date -u +%%u)" -le 5'
   EOF
   sudo systemctl daemon-reload
   systemd-analyze verify /etc/systemd/system/turtle-bot-*.service

   # 本周时间表（定时器每周一 00:05 才跑；第一次手动生成，--week 必须是本周一）
   MON=$(date -u -d "-$(( $(date -u +%u) - 1 )) days" +%F)
   botenv python3 /opt/turtle-beta/referee/bot_schedule.py --week $MON --real-last-week 0 --out /var/lib/turtle-bots-beta/schedule.json
   botenv python3 /opt/turtle-beta/referee/bot_schedule.py --week $MON --real-last-week 0 --summary | head -12
   botenv python3 /opt/turtle-beta/referee/bot_runner.py --status   # 共 / 已起 / 作废 / 在跑
   botenv python3 /opt/turtle-beta/referee/bot_runner.py --dry      # 只打印「会起 pNN …」；此刻没到点的不打印

   # 冒烟：手造一份「此刻 p01 打 1 局」的表，真起一个（不经 systemd ⇒ 不受上面的限额，只此一次）
   NOW=$(date -u +%FT%T+00:00)
   echo "{\"week\":\"smoke\",\"plan\":[{\"slot\":1,\"sessions\":[{\"at\":\"$NOW\",\"mode\":\"ranked\",\"rounds\":1}]}]}" \
     | sudo -u turtle-referee tee /var/lib/turtle-bots-beta/smoke.json >/dev/null
   botenv env BOT_SCHEDULE=/var/lib/turtle-bots-beta/smoke.json python3 /opt/turtle-beta/referee/bot_runner.py
   while pgrep -u turtle-referee -f 'sim-slot=01 ' >/dev/null; do sleep 15; done
   sudo tail -n 3 /var/lib/turtle-bots-beta/p01/sessions.log          # rc=0、wall、CPU 秒
   sudo grep -h '"kind":"\(done\|STUCK\|ANOMALY\|blocked\)"' /var/lib/turtle-bots-beta/p01/*/app_userdata/*/sim_events.jsonl | tail -5
   sudo grep -c 'SCRIPT ERROR\|^ERROR' /var/lib/turtle-bots-beta/p01/last.log
   ```
   期望：周一 = 走完教程后 `blocked`「今日休赛」→ `done` → 退出；周二~周五 = 打 1 局 → `rounds_cap` → 退出。这是 `sim_driver` **第一次在 Linux 上整条跑**（之前只在 Windows 跑过 `HEADLESS=1`），过了再开定时器：
   ```bash
   sudo systemctl enable --now turtle-bot-schedule-beta.timer turtle-bot-runner-beta.timer
   systemctl list-timers 'turtle-bot-*'
   journalctl -u turtle-bot-runner-beta -f                 # 每 5 分钟一行「本轮: 起 / 作废 / 在跑」
   journalctl -u turtle-bot-schedule-beta -n 20
   systemd-cgls -u turtle-bot-runner-beta.service          # 在跑的客户端都挂在这个 cgroup 里
   cat /sys/fs/cgroup/system.slice/turtle-bot-runner-beta.service/cpu.weight \
       /sys/fs/cgroup/system.slice/turtle-bot-runner-beta.service/cpu.max   # 有号在跑时应为 10 与 50000 100000
   sudo tail -f /var/lib/turtle-bots-beta/pNN/last.log     # 某个号这次上线的客户端输出（每次上线覆盖）
   ```
   - oneshot runner 退出后客户端留在它的 cgroup 里继续打（`KillMode=process`）；下一轮 journald 里的「left-over process」提示属正常。
   - `REAL_LAST_WEEK` 还没有自动统计：每周一 00:05 之前手动改 env（内测服没有真人 ⇒ 0 ⇒ 90 个号）。

5. 安全：与正式服裁判抢 CPU
   - 量：
   ```bash
   sudo -u turtle-referee env $(sudo cat /etc/turtle-referee/env | xargs) \
     python3 /opt/turtle/referee/referee_poller.py --health; echo rc=$?    # oldest_pending_sec、各裁判 seen_sec；rc=1 = 积压 > 120 秒或没心跳
   journalctl -u turtle-referee-health --since -2h | grep HEALTH
   uptime; systemd-cgtop -b -n 2 -d 5 | grep -E 'turtle-(referee|bot)'
   sudo tail -qn 1 /var/lib/turtle-bots-beta/p*/sessions.log | sort | tail -20                      # 每次上线 CPU 秒（U3）
   sudo grep -h 'rc=12[4-9]\|rc=137' /var/lib/turtle-bots-beta/p*/sessions.log | wc -l             # 到上限被杀的次数
   botenv python3 /opt/turtle-beta/referee/bot_runner.py --status                                   # 作废数 = MAX_PAR=1 排不过来的
   ```
   一个号在菜单里空等时若就占满一核（无头帧率没量过），在 env 里加 `BOT_MAX_FPS=60`（包装脚本转成 `--max-fps 60`）。
   - 正式服排队时按这个顺序停，每停一步看一次 `--health`：
     ① `sudo touch /etc/turtle-referee/bots-beta-off`（runner 不再起新的）→
     ② `sudo pkill -TERM -u turtle-referee -f 'sim-root=turtle-bots'`（在跑的陪练客户端；裁判的 Godot 命令行里没有这个串）→
     ③ `sudo touch /etc/turtle-referee/beta-off && sudo systemctl stop turtle-referee-beta`（内测服裁判，高峰停起 timer 会一直停着）→
     ④ 还排 = 正式服自身算力（`WORKERS` / 换机型，花钱先问用户）。恢复时反序删两个 off 文件。
   - 周末不起（drop-in 里 `date -u +%u ≤ 5`）：内测服裁判周六、周日全天被 `beta_peak_guard.sh` 停着，内测服的闯关局在周末结不了算；周末又是正式服高峰。要在内测服试闯关，先把这一条和 peak guard 一起改。
   - 彻底停用（号与存档留着，下次接着用）：
   ```bash
   sudo systemctl disable --now turtle-bot-runner-beta.timer turtle-bot-schedule-beta.timer
   sudo pkill -TERM -u turtle-referee -f 'sim-root=turtle-bots'
   ```
   拆除再加：删 `/etc/systemd/system/turtle-bot-*` 与 drop-in 目录 → `daemon-reload`；`/var/lib/turtle-bots-beta/pNN` 删了 = 号的登录凭据没了（内测服上那些号就成了孤号）。

6. 时钟
   - 陪练号用真实时钟：`now_utc()` = 本机时间 + 服务器 `Date` 头偏移 + **内测服假时间偏移**（`phase2_config.gd:553-562`、`:626-631`，只在内测服叠）。排班表按**真实 UTC** 起号 ⇒ 内测服偏移必须是 0，否则号上线时客户端以为是另一天。部署前、之后每周一：本机 `python tools/beta_ops.py status --no-ssh` 看「偏移 = 0」，不是就 `python tools/beta_ops.py clock reset`。陪练号开着时**不要** `beta_ops clock set`（要彩排先 `touch bots-beta-off`）。
   - `SIM_CLOCK_OFFSET`（`sim_driver.gd:76-77`、`:101-115`）是测试用的，把赛程钟钉在「真实 + 偏移」；`TURTLE_FAKE_NOW` 同理（`SHIP=1` 下本来就失效）。两个都**不许**进 `env-bots-beta`，正式服那份也一样。

**部署前已知阻塞（照代码读出来的，未在机器上实测）**

① **卡住的号永远不退、占死唯一的并发位**：`bot_runner.py` 起完不管（`:78-94`，没有超时）；`sim_driver` 只在被拦 / 到局数时退（`:271-285` → `_finish` `:351-356`），STUCK 只记一行（`:155-158`）。最确定的一条：周日是决赛日阶段时 `_do_menu` 直接 return、不 `_finish`（`:265-270`），而 v0.22.1 整个周日都是决赛日（tag 里 `phase_at_utc` = 按星期几；周日 17:30 前算闯关是 10-26 才改的），`bot_schedule.py:43` 却在周日 0~17 点排了 15% 的闯关上线；新版里 17:30 跨进决赛日的那一局也一样。⇒ 本节用包装脚本 `timeout` + 周末不起兜住；该修的是 runner（超时杀）或驱动（决赛日且 `SIM_QUIT_WHEN_DONE` 时也 `_finish`）。
② `turtle-bot-runner-beta.service` 没有任何 CPU 限制，客户端默认 nice 0，比正式服裁判（`Nice=5`）还高 ⇒ 本节 drop-in 补上（`CPUWeight` / `CPUQuota` 对 oneshot 退出后留在 cgroup 里的进程是否一直生效，要按第 4 步读 `cpu.weight` / `cpu.max` 确认）。
③ `MAX_PAR=1` 排不完 90 个号的周二：方案书 §4.2 周二约 520 场；三路打满 10469 步 ÷ 60 步/秒（`RealtimeBattle3DScene.gd:792` `SIM_DT`）≈ 2.9 分钟真实时间一局，加匹配 / 商店，串行一天约排得下 300~400 场（推算）⇒ 周二会有一批作废，这正是内测周要量的数。
④ 连错服：见第 0、2 步（`TURTLE_SERVER` 只在 debug 构建认；`bot_runner` 把整份环境传给客户端）。
⑤ `turtle-bot-schedule-beta.service` 用 `--week "$(date -u +%F)"` 配 `Persistent=true`：机器在周一 00:05 宕着、周二以后才补跑时，`bot_schedule.py:144-145` 拒绝非周一 ⇒ 这周没有表，runner 读上周的表、全部作废。补救 = 手动跑第 4 步那两行。
⑥ 不是阻塞（已查）：无头截图两处都先判 `headless` 跳过（`sim_driver.gd:1611`、`sim_shot.gd:25`）；`scripts/systems/sim/` 里没有 Windows 路径或 Windows 专用 API；Linux 上 user:// = `$XDG_DATA_HOME/godot/app_userdata/斗龟场 实时版/`，`bot_runner` 已按槽位设 `XDG_DATA_HOME`。

## 已知风险与未决点

- **R1 真机确定性**：服务器（Linux x86）算的录像要在 iPhone（ARM）上逐步重算。x86↔x86 已逐位一致（金标 + 本门禁），ARM 没验过（方案书 §0，`verify_referee_device_parity` 未做）。不一致时手机播放会在第一个对不上的校验点停下并上报（不会默默播错的），但玩家就看不了那一场。
- **等级**（用户 10-19「赛季等级」已拍板）：快照带 `season_level`（`Backend.build_ghost_snapshot` / 机器人 `make_bot` = 按场次曲线 / 陪练 = 种子文件里的真实等级），战斗里**双方各用各的**：左方 = A 快照的等级（裁判 `level_for`；任务单 `level` 只在 A 没带时用，都没有才按 A 的场次估），右方 = 战斗场直接读 B 快照。B 是没带等级的旧快照 ⇒ 右方退回与左方同级（老口径）。
- **左方从快照推出来的状态**与 A 自己手机上打会有差：快照里没有的（糖果临时等级、赌神命运之轮层数、093 香火刻痕 / 充能、斧头进度条、大师形象）按右方的口径取 0 / 空。要「本地先播、服务器落账」逐步一致，客户端得把开局 `capture_state()` 一起交上来（任务单已留 `a_state` 字段，表里还没有这一列）。
- ~~**周六对手是客户端挑的**（`referee_submit_gauntlet` 的 `p_opponent`）：能挑弱对手。~~
  ⇒ 2026-10-20 已改（迁移 `20261020c_gauntlet_server_pick_and_coins.sql`，只写文件未上生产）：客户端调 `referee_gauntlet_start`，
  只交「我的阵容 + 第几场」，对手（同标签真人 30 分钟内优先 → 隔夜 → 机器人池）与种子都由服务端定；
  机器人快照池离线生成（`scripts/referee/bot_pool.gd`）、`--bot-pool` 上传。旧接口在 `referee_config.gauntlet_server_pick = true` 后一律回 `update_required`。
  上线顺序见迁移文件末尾；行为检查 `server/supabase/tests/20261020c_…_check.sql`（`node tools/sql_sandbox.mjs` 本机 PGlite 59 条全过）。
- **闯关赛战斗内铸币**（奇械羁绊 / 035 齿轮）：2026-10-20 起裁判结果单带 `coins`（`EquipTickSystem.match_minted`，与本机结算同一个出口），
  `referee_complete` 记进 `ledger.coins`、`referee_job_status` 回给客户端。
- **周日战斗内铸币**（2026-10-20 · 迁移 `20261020d_finals_coins.sql`，只写文件未上生产）：结果单多 `coins_b`（右方 B，同一个出口
  `EquipTickSystem.match_minted(battle, "right")`），周日任务记进 `ledger.coins_b`；双方客户端翻面后调 `referee_finals_coins`（服务端按账号认侧）取自己那一份。
  轮询器不用改（结果单原样转交 `referee_complete`）；裁判机要装带 `coins_b` 的客户端版本，之前 B 一律 0。检查脚本 `server/supabase/tests/20261020d_finals_coins_check.sql`。
- **投降**（方案书 U4，用户 10-19「投降不要了」）：整个功能已从客户端删掉；裁判局里本来就没有投降事件。
- **告警通道**没定（现在只进 journald）。
- SQL 只做了语法核对（libpg_query 解析 + plpgsql 解析通过），**没在真库上跑过**；上线前在内测服按第 8 步冒烟。
