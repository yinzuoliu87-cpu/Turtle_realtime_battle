# 裁判机部署 · `tools/deploy.py` + `deploy_version.sh`

> 方案书：[docs/plans/20261102-文件管理与发版流程重整.md](../../docs/plans/20261102-文件管理与发版流程重整.md) §4.2 P3
> 手工步骤的出处（各目录、env、陪练号、内测服）：[server/referee/README.md](../referee/README.md)「发版时」「常驻陪练号」「内测服第二套」

把「新版本装上裁判机」从临时目录里的 `referee_install_*.sh` / `deploy0227(b).sh` 变成一条命令：
本机前置检查 → 服务器上**暂存目录**装 tag 那一提交 → 导入两次 → 两条一致性门禁 → **过了才原子换入** → 两个对手池 + 回读 →
陪练号工程 → 改 `BOT_GAME_DIR` → 重启调度器 → 读进程环境确认。任何一步不过就停；换入之前停下 = 线上什么都没变。

## 用法（本机仓库根目录）

```bash
python tools/deploy.py 0.22.8 --dry-run            # 先演练：本机检查 + 服务器只读演练（打印每一步会做什么）+ 现状回读
python tools/deploy.py 0.22.8                      # 正式服部署；服务器上 nohup 起，本机每 15 秒一条短 ssh 跟日志
python tools/deploy.py 0.22.8 --status             # 断开后接着看（读 /root/deploy/logs/last-<env>-v<版本>.log），结束后回读
python tools/deploy.py 0.22.8 --only bots-switch   # 登记 referee_versions 之后再切陪练号
python tools/deploy.py 0.22.8 --only pools         # 只重跑两个对手池 + 回读
python tools/deploy.py 0.22.8 --env beta           # 内测服（/opt/turtle-beta；bots-beta-off 在时自动不碰陪练号）
```

其余开关：`--skip-bots`（只装裁判）、`--no-bots-switch`、`--no-pools`、`--no-drain`、`--bots-drain-sec N`、
`--sim-overlay origin/main`、`--allow-weekend`、`--no-follow`、`--sha <核对用>`、`--skip-ci`（紧急修复，打印警告）。

本机前置检查：tag `v<版本>` 在本机且已推、与远端一致；那一提交的 `project.godot` 版本对、读出 `RULES_VER`；
裁判入口 / 两条门禁场景 / 积分赛池生成器都在；CI `tests.yml` 在那一提交上绿；库里（只读）这个版本登记没有；服务器连得上、没有别的部署在跑。

## 服务器上做什么（`deploy_version.sh <prod|beta> <版本> <sha>`）

| 步骤 | 做什么 |
|---|---|
| preflight | 只读：Godot 4.6.3、目录、`/opt` 可用 ≥ 3 GB、同一文件系统、锁空闲、正式服周末拒绝（`--allow-weekend` 放行）、远端 tag = sha、登记状态（`referee_poller.py --health`） |
| drain | `touch <bots-*-off>`（本来就在的不动）并等在跑的陪练号退完（默认最多 7800 秒）；可用内存 < 1 GiB 不导入 |
| ref-stage / ref-import | `/opt/turtle-staging/<env>-ref-v<版本>-<短sha>`：从现有工程 `cp -a` → `git fetch --depth 1 <sha>` → `checkout -f` → 核 HEAD / 版本 / `RULES_VER` → 导入两次（第二次 rc=0 且无 `SCRIPT ERROR` / `Parse Error`） |
| bots-stage | 从裁判暂存拷一份（同一 sha、已导入）→ 可选 `--sim-overlay` → 核 `sim_driver` → 导入两次 |
| ref-gates | `verify_determinism_cross`（40000 帧）与 `verify_referee_job_roundtrip`（60000 帧）并行，两条都要 `ALL PASS` |
| swap | `mv -T` 原子换入 `<根>/v<版本>`；同名目录已存在 ⇒ 先等用它的进程跑完（≤ 15 分钟），挪到 `/opt/turtle-prev/<env>-ref-v<版本>.prev-<时间>` |
| release-off | 删掉本脚本建的 off 开关（换入之后才删：同版本重装时目标目录就是陪练号在用的那个） |
| pools | `referee_poller.py --bot-pool --version <版本>`；回读上传后的 total：闯关机器人池 2052、积分赛 seed 396 / bot 186、rules_ver = 工程的；再用 `--health` 核登记里的 rules_ver |
| bots-switch | 备份 env 到 `/root/deploy/backup/` → 改 `BOT_GAME_DIR` → `systemctl restart turtle-gauntlet-planner-prod` → `/proc/<MainPID>/environ` 必须是新目录（不对就还原 env 并重启） |

日志：主日志 `/root/deploy/logs/<env>-v<版本>-<短sha>-<时间>[-dry].log`（最后一行 `DEPLOY OK` / `DEPLOY FAILED: <步骤>`）；
各 Godot 日志 `/root/deploy/runs/<同名>/`。

**本工具不写库。** 唯一碰库的是 `--bot-pool`（上传两个对手池，顺带 `update referee_versions set rules_ver`）与只读的 `--health`。
要写库的两件打印 SQL 给人（正式服写入要用户点头）：

```sql
-- 登记（--bot-pool 只 update 不 insert ⇒ 没登记时 rules_ver 写不上，所以这里带上）
insert into public.referee_versions (client_version, rules_ver) values ('<版本>', <RULES_VER>)
  on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;
-- 周日用的版本：非周日才改（= 当周锁定的客户端版本，必须已登记且 enabled）
update public.referee_config set finals_version = '<版本>', updated_at = now() where id = 1;
```

**顺序**：没登记时 `deploy.py` 自动加 `--no-bots-switch`（陪练号切到没登记的版本会开不了积分赛）⇒ 装完 → 人登记 → `--only bots-switch`。

### 几处取舍

- 暂存 / 旧目录**不放在 `/opt/turtle*/` 下**：`referee_poller.py` 的 `discover_versions` 把那一层每个带 `project.godot` 的子目录都当版本（点目录也算，同版本两份时用排序靠前的 —— `.staging-…` 会排在 `v…` 前面被拿去算局）。
- `scripts/systems/sim/` 覆盖：裁判机 README（CPX22 时期那段）写着「陪练号工程的 `scripts/systems/sim/` 要是 main 版，发新版重建时一并覆盖」；
  0.22.5 / 0.22.6 / 0.22.7 实际都是按 tag 原样装的。⇒ 做成显式开关 `--sim-overlay <提交>`，**默认关**；本机检查发现 main 的 sim 比 tag 新时提示一行。只覆盖这一个目录，战斗代码保持 tag 原样。
- 内测服裁判：README 写了装完 `systemctl restart turtle-referee-beta`；轮询器每轮重扫目录，不需要，脚本不重启（周末 peak guard 停着时重启会把它拉起来）。

## 回退

| 情况 | 怎么回 |
|---|---|
| `DEPLOY FAILED` 在 swap 之前 | 线上没变。暂存目录留在 `/opt/turtle-staging/<env>-{ref,bots}-v<版本>-<短sha>` 看原因，看完 `rm -rf`。脚本被杀 / 意外退出时它建的 `bots-*-off` 不自动删：`pgrep -fa '[g]odot.*--import'` 为空、负载回落后手动 `rm` |
| 同版本重装后要回到旧目录 | 先等没人用：`pgrep -fa -- '--path /opt/turtle/v<版本> '` 为空；`mv -T /opt/turtle/v<版本> /opt/turtle-prev/<env>-ref-v<版本>.bad-<时间> && mv -T /opt/turtle-prev/<env>-ref-v<版本>.prev-<时间> /opt/turtle/v<版本>`；陪练号目录同样换回。旧代码的池子与 rules_ver 要重来：`bash /root/deploy/deploy_version.sh <env> <版本> <旧 sha> --only pools` |
| 新版本整个撤掉 | 库里 `update public.referee_versions set enabled = false where client_version = '<版本>';`（人做）→ 陪练号切回（下一行）→ 该版本 pending / claimed 任务清空后 `mv -T /opt/turtle/v<版本> /opt/turtle-prev/…` |
| 陪练号切回旧版本 | `cp -a /root/deploy/backup/env-bots-<env>.bak-<时间> /etc/turtle-referee/env-bots-<env>` → `systemctl restart turtle-gauntlet-planner-prod` → `tr '\0' '\n' < /proc/$(systemctl show -p MainPID --value turtle-gauntlet-planner-prod)/environ \| grep BOT_GAME_DIR`（或直接 `deploy_version.sh <env> <旧版本> <旧 sha> --only bots-switch`） |

## 已知风险与未决点

- 同版本重装时「等目标目录没人用」到「rename」之间有毫秒级窗口，轮询器恰好在这时领到该版本的任务会读到新目录（只在替换已存在目录时；新版本没有这个问题）。
- 周六 / 周日正式服默认拒绝：调度器不认 off 开关，周末导入会与在线陪练号抢内存。真要装加 `--allow-weekend`。
- 平日陪练号是 queue 模式持续在打，`drain` 可能等到会话上限（2 小时）。内存够时（CPX32 空载约 7 GB 可用）可 `--no-drain`，自己判断。
- 对手池按 `rules_ver` 存：上传会整套替换同一 `rules_ver` 下的池子（别的启用版本若 `rules_ver` 相同，也用这一套）。
- 期望行数 2052 / 396 / 186 写在 `tools/deploy.py` 的 `EXPECT_POOLS`（传给服务器）；生成器改了池子大小要一起改。
- `/opt/turtle-prev/` 不自动清，攒多了手动删。
