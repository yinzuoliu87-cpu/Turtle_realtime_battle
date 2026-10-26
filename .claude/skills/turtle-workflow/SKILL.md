---
name: turtle-workflow
description: 斗龟场（turtle-realtime-godot）整个项目的工作方式 —— 沟通铁律、需求→方案书→实现→门禁→发版→上服务器的完整流水、测试与反向验证、美术交付、服务器运维、本机工具坑。在这个仓库里接任何需求、改代码、出包发版、动正式服 / 裁判机之前先读。细节以 CLAUDE.md 与 memory 为准，本文件是把它们串成一条线的总纲。
---

# 斗龟场 · 工作方式

> 总纲。细节的事实源：仓库 `CLAUDE.md`（代码 / 门禁 / 地雷）、memory 索引 `MEMORY.md`（用户偏好与拍板）、`docs/plans/README.md`（方案书制度）。三者冲突时：**代码 > 数据 > 三份权威文档 > 其余文档**（CLAUDE.md §1）。

## 0. 七条铁律（每次都适用）

1. **给用户的文字一律中文**，包括工具调用之间的过程说明。
2. **不许轻易说「做不了 / 没权限 / 填不了」**（用户强调过无数遍）。先当场把能走的路试完：工具在不在、凭据在不在、接口通不通。真不行，说清卡在哪一步、缺什么、为什么缺，再给用户最短的那一步。文档里的旧结论不算查证（10-26 照 CLAUDE.md 旧记录说「没 token」，实际 Git 凭据管理器里一直有）。
3. **报「做完了 / 没问题」之前先证明检查本身会 FAIL**：故意改坏一处，确认测试变红，再逐字节还原。打印分母，`N=0` 是空检查不是通过。
4. **断根因先写探针打数值**，推理出来的不算根因；量尺先标定（例：无头模式下 `screen_get_orientation()` 恒为 0，量不出东西）。
5. **钉住用户原话**：方案书第 1 节逐字引用；绝不把我的提议标成用户原话；用户拍板当场写进 memory（`fb-record-user-decisions-as-memory`）。
6. **花钱 / 正式服写入 / 生产 SQL 先说一声**，用户点头才做；本机只读查询（`tools/sb_ro.py prod`）用户已放行。授权只管那一次，不顺延到下一件事。
7. **不浪费用户的时间**：后台任务不要用会挂住的写法（见 §8 SSH）；能并行就并行；有时间就别往后推（`fb-dont-defer-when-time-remains`）。

## 1. 一条需求的标准流水

```
需求 → 方案书（含验收清单 + 已知风险/未决点）→ 用户拍板未决点 → 实现
     → 相关测试 + 反向验证 → 提交 push → 看 CI → （用户认可 / 说出包才）发版 → TestFlight → 裁判机跟版本
```

- **方案书**：`docs/plans/YYYYMMDD-<简称>.md`，七节缺一不可（需求原文 / 调查结论带 `文件:行号` / 需求↔代码出入 / 方案穷举清单 / **已知风险与未决点** / 验收标准且说明怎么证明会 FAIL / 决策记录），完成后回填。状态行五选一。写完在 `docs/README.md` 索引登记一行。门禁：`tools/plans_lint.py`、`tools/plan_stale_audit.py`（未完成项要带 `★done-when`）。
- **需求一次摊开**：子需求列全再动手；先实玩 / 截图走一遍现状。
- 小改不必写方案书，但用户的拍板仍要进 memory。

## 2. 代码放哪（CLAUDE.md §5）

判据只有一条：**不在 `_sim_step` 调用链上的，不进主文件 `RealtimeBattle3DScene.gd`**。

| 要写的 | 去哪 |
|---|---|
| UI / 面板 / 结算 | `scripts/scenes/battle/battle_hud.gd` 或对应 Scene |
| 特效演出 | `scripts/scenes/battle/battle_vfx.gd` |
| 单龟技能 | `scripts/systems/skills/<x>_system.gd`（入口函数名要 `_sk_*`） |
| 装备效果 | `scripts/systems/equip/` |
| 纯数据 / 常量 | `scripts/gamedata/` |
| 通用工具 | `scripts/util/` |
| 每帧耦合的核心 sim | 才留主文件 |

风格：tab 缩进、snake_case、返回值写类型。地雷见 CLAUDE.md §3（单位字典不能当键 / 两条伤害路径都要改 / `_t` 跨路不重置 / 数值测试不依赖动画 tween / 脚本改代码注释不插行中间）。sim 路径用 `DetMath`，tween 捕获节点要 `bind_node`，`await lane_step()` 之后判 `is_instance_valid(battle)`。

## 3. 测试与门禁

- **全量门禁**：`bash run-tests.sh`（自动发现 `tests/verify_*.gd` + 冒烟 + 审计器，约 3～6 分钟）。CI 拆 4 片并行。**改动小时只跑相关测试**，全量交给 push 后的 CI（用户 10-22 放宽）。门禁在跑时不改仓库。
- **跑单个 / 几个测试**：`--headless --audio-driver Dummy` 并设 `TURTLE_SUPABASE=" "`；窗口要开就走 `godot-quiet.sh`（强制静音），放右边 `--position 2000,80`。
- **审计器**：`tools/*.py`，登记在 `run-tests.sh` 的 `run_audit` 行（不带参数调用，只认「ALL OK」）。
- **CI 偶发红、本地复现不了**：`--max-fps 15`，或 `_s._deterministic = true`；判据别跟机器快慢挂钩。
- **本地绿 ≠ CI 绿**：push 后自己去看 CI（见 §6 GitHub 接口），哪片红看哪片注解，失败日志在 `ci-logs` 分支。
- **反向验证模板**：改坏一处 → 跑 → 看红在哪条 → 逐字节还原并 `assert` 字节相同。变异打不红 = 判据有洞或那段是死代码，先查清再报。
- **门禁会把 bug 钉住**：旧判据把错误写法当标准时（例：方向设置判「字符串含 landscape」），要改判据去量需求本身。

## 4. 美术 / 特效 / 界面交付

- **素材不复用**，除非用户点名；同一只龟的技能和普攻也不共用。跨屏同义要登记理由。
- 研究参考要**逐帧**看（写 `docs/studies/` 研究记录，`frame_study_audit` 守格式）；特效"到底画了什么"用染色法核实。
- **像素画**：硬边、零半透明、小尺寸（`tools/pixel_art_audit.py`）；生成脚本确定性、重跑逐字节相同（例：`tools/build_lb_heart.py`、`tools/build_basic_slam_vfx.py`）。
- **实拍验收**：两个比例（1560×720 手机 / 960×720 iPad）、等动画落位再拍；发给用户前**自己先挑完一整类毛病**；只交最终成果，不给对比草稿。动作类交视频（Movie Maker 60fps → ffmpeg）。
- 卡片 / 弹框里的按钮一律 `UISkin.card_button`，不用木牌按钮。文案不口语化，技能文案照 LoL 体例（`copy_lol_style_lint`）。

## 5. 发版（用户说「出包 / 可以出」才做）

1. **版本号五处一起改**：`project.godot` `config/version` / `CHANGELOG.md` 顶部 / `export_presets.cfg` 的 iOS `short_version` 与 Android `version/name` / `docs/实时版-路线图与待办.md`。第 3 位每次 +1，加新玩法第 2 位 +1。至少一份方案书要提到新版本号（`plans_lint` 版本留痕）。门禁：`verify_version` + `docs_authority_lint`。
2. 提交 push → **等 CI 绿** → 打 tag `git tag -a vX.Y.Z <提交>`，**一次只推一个 tag**（`git push origin refs/tags/vX.Y.Z`）。
3. 推 tag 自动跑 `testflight.yml`：签名、拆包核对（版本 / 构建号 / 最低系统 / 屏幕方向两横向等）、上传。确认「Upload to TestFlight」那步成功，别只看绿勾。
4. **外部测试**：等构建 VALID → 加进「公开测试」组 → 填本版说明（中文）→ 提交 Beta 审核（约 1 天）。脚本模板 scratchpad `asc_submit_*.py`；公开链接 `https://testflight.apple.com/join/tx8zK2Gu`。说明文字含换行时别用 heredoc 写脚本。
5. **裁判机跟版本**（否则新版本服务器局回 `update_required`）：暂存目录装新版本 → `--import` → `verify_determinism_cross` + `verify_referee_job_roundtrip` 全过才挪进 `/opt/turtle/` → 正式服 `referee_versions` 登记 → `referee_poller.py --bot-pool --version X` → 非周日才改 `finals_version`。步骤见 `server/referee/README.md`「发版时」。
6. 不要求装机就不出包；攒批合并发（用户 10-23「攒多点再出包」）。

## 6. 服务器与平台（运维）

| 东西 | 在哪 | 怎么动 |
|---|---|---|
| 正式服数据库 | Supabase `turtle-realtime`（伦敦，免费档） | 只读：`python tools/sb_ro.py prod "select …"`；写：`sb_common.query(…, prod_write_ok=True)`，先问用户 |
| 内测服数据库 | Supabase `turtle-beta`（伦敦，免费档） | `tools/beta_ops.py` |
| 迁移 | `server/supabase/migrations/<名>.sql` + `tests/<名>_check.sql` + `schema.sql` 末尾同段 | `tools/sb_migrate.py`：sandbox → beta `--rehearse --apply` → prod `--precheck` → prod `--rehearse --apply --yes-prod`（正式服要用户点头）；`diff` / `status` 只读 |
| 裁判机 | Hetzner `turtle-referee-1`，纽伦堡，IP 49.13.166.188 | `ssh -i ~/.ssh/turtle_referee root@…`；Hetzner API 令牌 `~/.config/turtle/hcloud_token` |
| 直播 / 大陆中转 | 同一台裁判机上的 Caddy：`stream.turtlearena.xyz` / `cn.turtlearena.xyz` | 域名在 Porkbun |
| 外部监控 | `.github/workflows/referee-watch.yml` 每 10 分钟 → `tools/referee_watch.py` | 整机失联（两信号 + 3 分钟复查）才软重启，60 分钟限频；其余只发邮件 |
| GitHub 接口 | 本机没装 `gh`，但 **Git 凭据管理器里有用户的令牌**（repo / workflow） | `printf "protocol=https\nhost=github.com\n\n" \| GCM_INTERACTIVE=Never git credential fill` 取出（不打印）；Git Bash 里路径参数加 `MSYS_NO_PATHCONV=1` |

- **凭据**一律在 `~/.config/turtle/secrets/` 等本机目录：不打印、不提交、不进 memory。
- 周末（周六闯关赛、周日小组赛 19:00 英国时间）不动生产库，除非用户明说。
- 故障排查顺序：外部探活 → `referee_health()` / `referee_backlog()` 心跳 → Hetzner metrics → SSH 上去 `journalctl -b -1` 看上一次开机。

## 7. 机器与窗口

- 跑测试会蓝屏的机器史：出事先把 `JOBS` 调回 4，跑大批前先提交。
- 窗口只开右屏、不抢焦点、必须静音；不要 `taskkill /IM`。
- 用户在打游戏时，模拟号无头起。

## 8. 本机工具的坑（都踩过）

- **heredoc 会吞反斜杠**：含 `\n` 的改文件脚本一律用 Write / Edit 写成 `.py` 再跑。
- **命令行里的中文**传给 Python 会乱码（GBK）：SQL / 查询带中文就写进 UTF-8 文件再执行；Python 输出设 `PYTHONIOENCODING=utf-8` 或 `sys.stdout.reconfigure(encoding="utf-8")`。
- **PowerShell 5.1 改中文文件必乱码**：用 Python 二进制读写，保留原行尾。仓库行尾 CRLF / LF 混用，查行尾只用 Python 二进制读。
- **Git Bash 改写以 `/` 开头的参数**成 `C:/Program Files/Git/...`：加 `MSYS_NO_PATHCONV=1`。
- **本机代理会改写 POST body**：脚本里用 `urllib.request.build_opener(ProxyHandler({}))` 绕开。
- **SSH 别同时「起后台进程又等它」**：会挂住、白等十几分钟（10-26 测速时连踩两次）。长任务在服务器上 `nohup … > log 2>&1 < /dev/null &` 起，然后**另发短命令（`timeout 20 ssh …`）**看 log。
- 重定向写 `> log 2>&1`（顺序反了日志是空的）；别用 `git checkout -- <file>` 清临时改动（会连真实工作一起回滚）。
- Godot `-s` 跑脚本时 autoload 全局名还没注册：要用 GameState 等就做成临时场景 `.tscn` 跑，跑完删掉。

## 9. 汇报

- 分清**实测**和**推断**；数字给来源（哪条命令、哪次运行）。
- 没跑的说没跑，失败的贴失败输出；不确定就说不确定、说缺什么才能确定。
- 结尾不复述过程，只说结果、要用户定的事（选项 + 我的建议）。
