# CLAUDE.md — 项目工作约定

斗龟场·实时版。Godot **4.6.3** / GDScript。2.5D（3D 场景 + Sprite3D 公告板）自走棋，28 只龟 × 59 件装备，双路对战。

> 本文件只写**现行规则**。每条规则的来历、踩坑经过、当时的实测数字在
> [docs/archive/CLAUDE-旧版全文-20261102.md](docs/archive/CLAUDE-旧版全文-20261102.md)（2026-11-02 重整前的逐字原文）。
> 规则改了就改这里；新规则写明它**取代哪一条**，别在别处（技能、memory）再抄一份数字。

---

## 1. 事实源（谁说了算）

冲突时一律以上位者为准，**不要反过来「按文档改代码」**。

| 级别 | 位置 | 说明 |
|---|---|---|
| **1. 代码** | `scripts/` `autoload/` | 最终事实。数值问题的终审 |
| **2. 数据** | `data/*.json` | `DataRegistry` 载入：28 龟、59 装备、状态、规则 |
| **3. 权威文档** | `docs/design/28龟技能设计-权威.md`<br>`docs/design/实时版-系统机制权威.md`<br>`docs/实时版-路线图与待办.md` | **只有这三份**（`tools/docs_authority_lint.py` 守） |

`docs/` 其余文档是历史记录 / 方案书 / 账本，**默认不可信**。标题写着「权威」也不算。

- 装备属性的事实源是 `EquipStats.STATS`（`scripts/gamedata/equip_stats.gd`），龟属性是 `turtle_stats.gd` 的 `STATS`。`data/phase2-equipment.json` 的 `baseStats1` 只是展示用的手写镜像。
- 版本号的事实源是 `project.godot` `config/version`。

---

## 2. 门禁

```bash
bash run-tests.sh                 # 全套：自证测试(自动发现) + 冒烟 + 审计器，约 700 项，JOBS=16 本机约 15 分钟（11-04 实测 903 秒）
JOBS=8 bash run-tests.sh          # 保守一点（审计器池与测试池各占一份 JOBS）
SHARD=k/8 SHARD_LIST_ONLY=1 bash run-tests.sh   # 只看第 k 片分到哪几条
```

- **改动经 CI 把关进 main，不直接 push main**（用户 11-05「肯定是要改呀…这个做法效率太低了呀…你按最好的做法来呀」，取代 10-31「推送前本机跑完整门禁」）：提交后 `python tools/ship.py <主题> [--wait]` 推到 `wip/<主题>` → `tests.yml` 八片跑全套（约 10 分钟，公开仓库不计费）→ 全绿由 `promote` 自动**快进** main（不是 main 的后代就失败，不硬塞）。本机只跑与改动直接相关的测试 + 审计器；本机全套 `bash run-tests.sh` 只在要 Windows 侧证据（生成金标等）或 CI 不可用时跑。由来：10-31 那条占满用户电脑约 15 分钟、跑的期间不能改仓库 / 开录制，而它跑的是和 CI 同一套测试、并不多抓问题（11-05 分析：CI 中位 10 分钟、最近 30 次 29 绿）。
- **推之前先过本机预检，CI 不是用来找小错的**（用户 11-06「每次跑个十分钟 CI，然后找个小问题，然后又跑个十分钟 CI…我不觉得这是很好的呀」，修订上一条的「本机只跑相关测试」）：`python tools/precheck.py` 跑全部审计器 + 全仓扫描类测试 + 碰到改动文件的测试，过了 `ship.py` 才放行（`--list` 看要跑哪些）。CI 红了不整轮重来：本机 `SHARD=k/8 bash run-tests.sh` 只跑红的那片，修好确认再推；攒齐一批再推，不是修一个推一个。
- **美术迭代没被用户认可前不推、不跑预检 / CI**（用户 11-11「走了六遍，没有一遍合格的，你走 CI 走预检有啥意义」，补充上两条）：动作帧 / 特效 / 形象在本机改、出图或录像给用户看，只单跑直接相关的几条测试；用户点头后才提交，跑一次预检 + `ship.py`。预检和 CI 判断不了好不好看。
- **只改文档 ⇒ 复用上次全绿**（用户 11-04「改」，修订上一条）：`run-tests.sh` 开头用 `tools/gate_input_key.py` 算测试输入哈希（docs/ 与根目录 .md 以外的全部文件 + 被 Godot 侧 `res://` 点名的文档 + Godot 可执行文件）；与 12 小时内上次全绿相同 ⇒ 自证测试 + 冒烟复用、不起 Godot，三方对账与审计器照跑，结尾打「其中 N 项复用」。输入变一个字节就跑全套。`GATE_NO_REUSE=1` 强制全套，`GATE_REUSE_CHECK=1` 只看判定。**不许扩大成「只跑相关测试」**（用户没同意）。（本机跑全套时才用得上；11-05 起常规流程走 CI，见上一条）
- 手动跑单条测试一律隔离存档：`APPDATA=$U XDG_DATA_HOME=$U`（Windows 看 `APPDATA`，Linux/CI 看 `XDG_DATA_HOME`，两个都设；`verify_gate_isolation` 守）。并设 `TURTLE_SUPABASE=" "` 不连服务器。兜底：测试 / 台子进程在默认目录上 `save()` 一律拒写（`scripts/util/save_iso.gd`，11-13 起）。**测试里绝不在进程内把 `APPDATA` / `XDG_DATA_HOME` 改成真目录**：Godot 按当时的值实时解析 `user://`，会真写进玩家存档（11-13 出过事，靠卷影副本救回）。
- 判定 = 退出码 0 + 不命中 `run-tests.sh` 顶部 `FATAL` 致命报错正则 + 日志里有 `ALL PASS`。**新报错形态往 `FATAL` 里加**，漏一个模式就等于把 bug 判绿。
- 测试**自动发现** `tests/verify_*.gd`（配好 `.tscn` 即纳入，无需登记）。慢测试在 `frames_for()` 登记帧预算 —— `--quit-after` 单位是**帧**；帧数不够表现为「没打 ALL PASS」，不是某条断言 FAIL。
- 审计器（`tools/*.py`）登记方式：在 `run-tests.sh` 加一行 `run_audit "tools/x.py" "ALL OK" "说明"`，清单从这些行自动扫出来。
- 失败日志留在 `.out/gate/<测试名>.log`，转绿自动删；CI 失败时同名日志推到 `ci-logs` 分支（`git fetch origin ci-logs`）。
- **CI**：`tests.yml` 8 片并行（`SHARD=k/8`）+ 汇总；分片按 `tests/golden/test_seconds.tsv` 最长优先，每轮把实测秒数推到 `ci-timings` 分支。刷新本机这份表：
  `git fetch -f origin +refs/heads/ci-timings:refs/remotes/origin/ci-timings && git show origin/ci-timings:test_seconds.tsv > tests/golden/test_seconds.tsv`
- **本地绿 ≠ CI 绿**，推完自己去看 CI（API 见 §6）。CI 偶发红、本地复现不出 ⇒ `--max-fps 15` 把帧变慢重跑；最省事的修法是测试里 `_s._deterministic = true`（每帧恰一步 sim）。判据别跟机器快慢挂钩：绝对时间阈值改成相对同进程参照、采样条数改成采样覆盖范围、「变大」改成「变了」、帧内跃迁改成一步一采。⚠ 别整套门禁跑 15fps（帧预算会集体撞顶）。
- 机器有蓝屏史：出事先把 JOBS 调回 4，跑大批前先提交。**别把默认 JOBS 往上提**：11-04 试 24 路墙钟 730 秒（−19%），但内存最低剩 3.2 GB、`verify_exact_match` 段错误一次（单跑复现不出）。
- 门禁慢的地方（11-04 分段实测）：超过 60 秒的 37 条占总核秒一半，主要是逐帧直播（同两局 `mirror` / `heavy` 被 16 条测试各录一遍）与确定性一族（15 个调试场景被 b / cross / parity 各跑一遍）；按真实时间硬等的只有 `verify_gauntlet_online_queue`。新写测试别「真打一整局」去量开场就能比的东西（例：`verify_arena_theme_pick` 改成比开打第一帧的障碍物 / 单位 / 随机流，162 → 26 秒）。

只读审计器（可反复跑）：

```bash
python tools/data_integrity.py         # json 交叉引用 / 资源路径 / 孤儿字段
python tools/tri_audit.py              # pets.json ↔ 活代码 ↔ 权威文档
python tools/tooltip_number_audit.py   # 装备文案数值 ↔ 代码
python tools/docs_authority_lint.py    # 三份权威在位 / 消费链活 / 无冒名
python tools/repo_hygiene_audit.py     # 仓库文件卫生（§8）
```

（本机 python 一律写全路径 `C:/Users/Louis/AppData/Local/Python/pythoncore-3.14-64/python.exe`，不用商店别名。）

**特效「到底画了什么」只能用染色法核实**：`python tools/vfx_dye_probe.py <装备id> <文件> '<颜色表达式>'`。看缩略图写问题清单不可靠；A/B 差分只在「同一件改前 vs 改后」时可靠。

---

## 3. 发版流水（每次玩家可感知的改动版本号 +1）

`大版本.功能版本.改动序号`；第 3 位每次 +1，加新玩法第 2 位 +1。游戏内显示从 `ProjectSettings` 读，不许写死。

```bash
python tools/release.py bump <版本> --rules same|changed   # 五处版本号 + CHANGELOG 骨架 + 路线图一行；--rules 必填
python tools/release.py checklist <版本>                    # 生成 docs/releases/<版本>.md 发版清单，逐步勾
python tools/ship.py <主题> --wait                         # 推 wip/<主题> → CI 全绿自动快进 main（11-05 起，取代本机全套 + 直接 push）
python tools/release.py tag <版本>                          # 前置检查(干净/已推/CI 绿/五处一致) 后只推这一个 tag
# 推 tag ⇒ testflight.yml 自动签名、核 tag=版本号、上传
python tools/asc.py submit <版本>                           # 进公开测试组 + 说明(取 CHANGELOG) + 作废同版本在审旧构建 + 提审
python tools/deploy.py <版本>                               # 裁判机 + 陪练号：暂存目录 → 导入 → 两条一致性门禁 → 原子切换 → 对手池 → 回读
python tools/prod_flags.py force-update <版本> --yes-prod   # 苹果 Beta 审核通过后才放行，抬 min_client_version
```

- **五处版本号**：`project.godot` / `CHANGELOG.md` 顶部 / `export_presets.cfg` 的 iOS `short_version` 与 Android `version/name` / `docs/实时版-路线图与待办.md`。`verify_version` 管前四处，路线图那处在 `tools/docs_authority_lint.py`。用 `release.py bump` 就不会漏。
- **`RULES_VER`**（`scripts/gamedata/phase2_config.gd`）：**这一版改了对局结果就 +1**（数值、技能、装备效果、sim 路径任何改动）。快照池 / 对手池按它分桶；漏升 ⇒ 新旧规则的快照混进同一个池。0.22.7 就漏过一次（tag 挪位、TestFlight 重出、裁判机重装）。
  - 门禁 `verify_rules_fingerprint`（裁判真入口跑 5 局，覆盖 28 龟 / 全部装备 / 顶档羁绊 / 训龟大师）：对局结果与金标 `tests/golden/rules_fingerprint.json` 不同就红。金标是另一个进程生成的，所以它同时守**跨进程确定性**（11-03 抓到血条写回圣盾值 ⇒ 同一局三种结局）。
  - 改了结果：当场把 `RULES_VER` 升到比上个 `v*` tag 大（上方一行带日期注释），再 `python tools/rules_fingerprint.py --update`（不满足就拒写）。一周内升过一次就够，发版时 `release.py bump --rules changed` 看到已经升过不会再 +1；`--rules same` 遇到已升会拒。
- **tag 不可变**：一次只推一个 tag（两个同推会互相覆盖产物）；推错了不挪 tag，出下一个版本号。
- **正式服写入**（迁移、开关、强制更新、`referee_versions`）每次都要用户点头；`--yes-prod` 不是授权，用户的话才是。
- 周末（周六闯关赛、周日决赛日）不动生产库与裁判机，除非用户明说。
- 不要求装机就不出包；攒批合并发（用户 10-23）。

---

## 4. 本项目特有的地雷（都踩过）

### 4.1 `HP_MULT` 只用于召唤物 raw 值
`RealtimeBattle3DScene.gd` 的 `HP_MULT = 3.0` 只能乘召唤物 raw 值（现状全仓无人用）。**装备 / 羁绊的「X% 最大生命值」一律按真实 `maxHp` 算，不除 `HP_MULT`**（用户 10-04 拍板；`verify_eq_maxhp_pct_basis` 守，静态扫 `/ HP_MULT`）。龟和装备的 `hp` 已是最终值，不要再乘。

### 4.2 单位字典不能做 key / 不能用 `==`
单位字典互相引用成环，Godot 递归哈希会卡死。比较用 `is_same(a, b)`，判存在用 `_arr_has_unit()`，绝不拿单位字典当 Dictionary 的键。

### 4.3 两条独立的伤害路径
`_apply_damage(u, dmg, ...)`（DoT / 真伤）与 `_apply_damage_from(src, u, dmg, ...)`（普攻 / 技能）**各自扣盾扣血**，改伤害逻辑两条都改。

### 4.4 `_t` 跨路累加，永不重置
全局时钟 `_t` 跨上路 → 下路 → 决胜一直累加。按本场计时的机制自己存 `t0`（见 `_sd_t0`）。

### 4.5 测试等游戏内效果
- 数值测试**不依赖动画 tween 跑完**：把结算从演出里抽成函数，演出末尾调、测试也直接调（例：`_pirate_grapple_hit`）。无头 CI 下 tween 链推进不稳。
- 等效果用轮询 + 上限，不用 `create_timer`（它走未钳制 delta，战斗时钟走 `minf(delta, 0.1)`）；也别拿游戏时钟 `_t` 当尺子（结束后冻结）。最稳是 `_deterministic = true`。
- 拿随机 spawn 单位测精确数值会偶发红，用干净合成单位。

### 4.6 改 CI 工作流后必须验 YAML
`python tools/workflow_lint.py`（进门禁）。工作流里不写含转义换行的单行命令。YAML 坏掉的表现是 run 失败但 jobs 列表为空、name 变成文件路径 —— 门禁从那次起根本没运行。

### 4.7 脚本批量改代码
替换串里不带 `#`（行内注释会吃掉同行后续内容），说明单独占一行放上方；按标记删多行块时每行都打标记；改完 `.gd` 立刻编译验证。含反斜杠的改文件脚本用 Write 写成 `.py` 再跑，**别用 heredoc**（会吞反斜杠）。仓库行尾 CRLF / LF 混用：改文件用 Python 二进制读写、保留原行尾。

---

## 5. 测试与调试开关（环境变量）

| 开关 | 用途 |
|---|---|
| `SHIP=1` | 关掉 demo 劫持。**冒烟测试必须带**（否则假人永不死、结算路径没测到） |
| `REVIEW=1 REVIEW_TURTLE=<id> REVIEW_SKILL=<idx>` | 单技能审阅台 |
| `EQDEMO_*` + `EQDEMO_ATTACKER=1` | 装备演示。靠命中 / 充能触发的装备必须带 ATTACKER |
| `DUALLANE=1 STRESS=1 DL_AUTOFIGHT=1 AUDIT=1` | 双路压测 + 自动巡检 |
| `MAPEDIT=1` / `DEBUG_EDIT` | 地图编辑器 / 调试场 |
| `SELFSHOT` `SHOT_BURST` `SHOT_STEP` `SHOT_OUT` | 自截图；`SHOT_OUT` 一律指到 `res://.out/shots/…` |
| `VFXLAB=1 VFXLAB_CASE=<id>` | 特效实验台；默认输出 `res://.out/vfxlab/<case>_<i>.png`；不能加 `--headless` |

---

## 6. 代码风格与放哪

- 缩进 tab；函数 snake_case；`class_name` PascalCase；新代码标注返回值类型。
- **判据只有一条：不在 `_sim_step` 调用链上的，不进主文件 `RealtimeBattle3DScene.gd`**（用户 08-02「可以涨行数，但不能乱」）。单文件上限 3000 行（`tools/arch_budget.py`）。

| 要写的 | 去哪 |
|---|---|
| UI / 面板 / 结算 | `scripts/scenes/battle/battle_hud.gd` 或对应 Scene |
| 特效演出 | `scripts/scenes/battle/battle_vfx.gd` 等 `*_vfx.gd` |
| 单龟技能 | `scripts/systems/skills/<x>_system.gd`（入口 `_sk_*`） |
| 装备效果 | `scripts/systems/equip/` |
| 纯数据 / 常量表 | `scripts/gamedata/` |
| 通用工具 | `scripts/util/` |
| 云后端 / 匹配 | `scripts/net/` |
| 每帧耦合的核心 sim | 才留主文件 |

拆分模板：`scripts/scenes/battle/dmg_stats_panel.gd`（`RefCounted` + 构造注入 + `Callable` 取只读数据）。sim 路径用 `DetMath`；tween 捕获节点要 `bind_node`；`await lane_step()` 之后判 `is_instance_valid(battle)`。

---

## 7. 构建、平台与服务器

| 目标 | 怎么做 |
|---|---|
| **iOS / iPad** | **TestFlight**：推 `v*` tag 自动跑 `testflight.yml`（App「斗龟场」Apple ID 6826108891，公开测试组 + 内部测试组自动分发）。不升版本只重传：推 `ci/testflight-*` 分支。侧载线 `ios-build.yml` 已停用 |
| 提交门禁 | push 自动跑 `tests.yml` |
| Web | `SHIP=1 bash build-web.sh` → `build/turtle-realtime-web.zip` |
| Android | 见 [docs/实时版APK打包.md](docs/实时版APK打包.md) |
| Mac | `<godot> --headless --path . --export-release "MacDist" "build/macdist/斗龟场.zip"`（未公证；重新打包保留 Unix 权限位） |
| 数据库迁移 | `tools/sb_migrate.py`：sandbox → beta `--rehearse --apply` → prod `--precheck` → prod `--rehearse --apply --yes-prod`；只读查正式服 `tools/sb_ro.py prod` |
| 裁判机 / 陪练号 | Hetzner 49.13.166.188（`ssh -i ~/.ssh/turtle_referee root@…`）；手册 `server/referee/README.md`，发版部署用 `tools/deploy.py`（`server/deploy/`） |

- **iOS 硬事实**：Windows 出不了 `.ipa`（只能 macOS runner）；`targeted_device_family` 是枚举下标不是设备号（`2` = 通用），改完回读导出工程里的 `TARGETED_DEVICE_FAMILY`；导出版命令行给场景路径会 Abort。
- **GitHub API**：本机没装 `gh`，令牌在 Git 凭据管理器里：`printf "protocol=https\nhost=github.com\n\n" | GCM_INTERACTIVE=Never git credential fill`（取出不打印）。Git Bash 里以 `/` 开头的路径参数加 `MSYS_NO_PATHCONV=1`；本机代理会改写 POST body，脚本里用 `ProxyHandler({})` 绕开。
- **SSH 长任务**：服务器上 `nohup … > log 2>&1 < /dev/null &` 起，另发 `timeout 20 ssh …` 短命令看日志；同一条 ssh 里起后台又等结果会挂住。
- 凭据一律在 `~/.config/turtle/secrets/` 等本机目录：不打印、不提交、不进 memory。

---

## 8. 文件放哪

| 东西 | 放哪 | 备注 |
|---|---|---|
| 开发产物（截图、实验台帧、对比图、门禁失败日志） | `/.out/` | 点目录，Godot 不导入、`.gitignore` 管住。代码里用 `DevOut.path()` / `DevOut.prep()`（`scripts/util/dev_out.gd`）。**不许再写根目录 `res://_…`**（`repo_hygiene_audit` 守） |
| 清理 | `python tools/clean.py`（只列）/ `--apply` | 删旧日志与无源 `.import`，旧截图挪进 `.out/legacy/`；不碰 `build/`、`.godot/`、worktree |
| 方案书 | `docs/plans/YYYYMMDD-<简称>.md` | 七节、状态行、完成后回填（`docs/plans/README.md`；`plans_lint` / `plan_stale_audit` 守）；在 `docs/README.md` 登记一行 |
| 方案书配图 | `docs/plans/img-<日期>-<主题>/` | 单张 ≤ 2 MB（录屏放仓库外只留链接）；`docs/` 有 `.gdignore`，图不会被 Godot 导入 |
| 发版清单 | `docs/releases/<版本>.md` | `release.py checklist` 生成 |
| 历史 / 作废文档 | `docs/archive/` | |
| 发版 / 部署 / 运维脚本 | `tools/`（本机）、`server/`（服务器端） | **进仓库**，不留在会话临时目录（临时目录里的脚本换个会话就找不到；0.22.x 那 30 多份按版本复制的脚本就是这么来的） |
| 一次性脚本 | `tools/oneoff/` | |
| 素材生成脚本 | `tools/assetgen/` | 生成结果确定性、重跑逐字节相同；脚本里算仓库根目录是往上三层（`tools/README.md`） |
| 探针 / 一次性诊断场景 | `tests/probes/` | 门禁只自动发现 `tests/verify_*.gd`；夹具与截图脚本（`_shot*` 等）仍在 `tests/` |

根目录只许白名单里的那十几个文件（`repo_hygiene_audit` ①）。

---

## 9. 工作方式

- **新需求先写方案书再动手**：必含「验收清单」（子需求一次列全）与「已知风险与未决点」。标准流水：`需求 → 方案书 → 用户拍板未决点 → 实现 → 门禁 → 版本号 + tag + CHANGELOG（玩家可感知才升）→ push → TestFlight → 反馈`。
- **push**：普通改动随时交（用户 10-22），走 `tools/ship.py` → CI 全绿自动进 main（11-05 取代 10-31「本机完整门禁全过」）。发版要用户认可。
- 报「做完了」之前，**先证明检查本身会 FAIL**：故意改坏一处、确认变红、逐字节还原；打印分母，`N=0` 是空检查不是通过。
- 断根因**先写探针打具体数值**；推理出来的不算根因。
- 动手造轮子前先搜仓库：`ls .github/workflows/ tools/ server/`、`docs/README.md`。
- 重定向写 `> log 2>&1`（顺序反了日志是空的）。**别用 `git checkout -- <file>` 清临时改动**（会连未提交的真实工作一起回滚）。
- 测试者拿包 / 装机 / 报 bug：[docs/测试指南-取包与报bug.md](docs/测试指南-取包与报bug.md)。
