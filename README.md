# 斗龟场 · 实时版

> 2.5D 自走棋（3D 场景 + Sprite3D 公告板）。**28 只龟 × 95 件装备**，双路对战。
> Godot **4.6.3** / GDScript。目标：iOS + PC/Web。

当前版本见 `project.godot` 的 `config/version`（改动记录在 [CHANGELOG.md](CHANGELOG.md)）。

---

## 怎么跑起来

1. 装 **Godot 4.6.3 Standard**（**不要 .NET 版**，本工程纯 GDScript）
2. Godot → `Import` → 选这个文件夹（认 `project.godot`）→ `Edit`
3. **F5** 开跑

### pull 之后报 `Identifier "XXX" not declared` 怎么办

这是 **Godot 的 class_name 缓存没刷新**（`.godot/` 不入 git，新增的 `class_name` 脚本你的编辑器还没扫到）。
按顺序试：① 完全关掉 Godot 再开项目 ② 菜单「项目 → 重新加载当前项目」 ③ 关 Godot、删 `.godot/`、重开。
**只有 pull 到新增 `class_name` 文件那次需要**，改已有文件不用。Godot 固有行为，不是 bug。

---

## 提交前要跑的

```bash
bash run-tests.sh          # 全套门禁：自证测试(自动发现) + 全流程冒烟 + 审计器
JOBS=8 bash run-tests.sh   # 想更快（默认 JOBS=2，见下）
```

**约 5.5 分钟**（213 项）。耗时几乎全在 Godot 进程启动，不在测试逻辑本身——所以是**有界并行**跑的。
默认 `JOBS=2` 是因为这台开发机 CPU 有确诊硬件故障（多进程编译最容易触发），**换机器后调回 4 或更高**。

**日常改动不必每次跑全套**：改哪块就跑那一个测试（约 1 秒）或那一个审计器（不到 1 秒），**提交前再跑一次全套**。

```bash
# 单个测试
<godot> --headless --path . res://tests/verify_codex_desc.tscn --quit-after 12000
# 只读审计器（可反复跑）
python tools/data_integrity.py        # json 交叉引用 / 资源路径 / 孤儿字段
python tools/tri_audit.py             # pets.json ↔ 活代码 ↔ 权威文档
python tools/text_claim_audit.py      # 文案声称的「每几秒/打谁/作用范围」↔ 代码实际
python tools/text_formula_audit.py    # 文案文字 ↔ 它自己的占位符公式
python tools/codex_text_lint.py       # 图鉴文案体检（不许有教学味/自夸/开发备注/漏讲机制）
```

门禁判定不只看退出码，还要过一条**致命报错正则**并要求打出 `ALL PASS`——
漏一个报错模式就等于把 bug 判成绿灯（历史上 `Max recursion` 曾不在名单里，24 组压测全报"0 errors"）。

---

## 事实源（谁说了算）

冲突时**一律以上位者为准**，不要反过来"按文档改代码"。

| 级别 | 位置 |
|---|---|
| 1. 代码 | `scripts/` `autoload/` —— 任何数值问题的终审 |
| 2. 数据 | `data/*.json`（由 `DataRegistry` 载入） |
| 3. 权威文档 | `docs/design/28龟技能设计-权威.md`、`docs/design/实时版-系统机制权威.md`、`docs/实时版-路线图与待办.md` —— **只有这三份** |

`docs/` 下其余近百篇是历史记录/草案/账本，**默认不可信**。别因为标题写着"权威"就当真——
曾同时有 4 份文件自称唯一事实源，现已由 `tools/docs_authority_lint.py` 焊死（进门禁）。

装备属性的真事实源是 `scripts/gamedata/equip_stats.gd` 的 `STATS`，龟属性是 `turtle_stats.gd`。

---

## 目录

```
project.godot        项目配置（版本号在这里）
scenes/              11 个场景（主菜单/选龟/战斗/背包/商店/图鉴/结算…）
scripts/             150 个 GDScript
  ├─ scenes/         各屏逻辑；battle/ 是拆分后的战斗子系统
  ├─ systems/        技能(skills/)、装备(equip/) 的效果实现
  ├─ gamedata/       属性表与配置（装备/龟/羁绊）
  ├─ util/           共享工具（UISkin 皮肤层 / SkillText 文案 / SafeArea…）
  └─ net/            云后端与匹配
data/                28 龟 / 95 装备 / 状态 / 规则（JSON）
tests/               197 个自证测试（verify_*.gd 自动发现，无需登记）
tools/               16 个审计器（数据/文案/架构/风格/CI）
assets/              精灵图、特效、字体、音频
docs/                方案书(plans/)、权威文档(design/)、路线图
```

---

## 出包

| 目标 | 怎么做 | 产物 |
|---|---|---|
| **iOS 装机包** | push 到 `main` 或手动 dispatch → `.github/workflows/ios-build.yml` | Actions artifact（unsigned `.ipa`，留 14 天） |
| 提交门禁 | push 自动跑 `.github/workflows/tests.yml` | 213 项，ubuntu |
| Web | `SHIP=1 bash build-web.sh` | `build/turtle-realtime-web.zip` |
| Android | 见 [docs/实时版APK打包.md](docs/实时版APK打包.md) | `build/android/*.apk` |

**Windows 上做不出 `.ipa`**（打包要 `xcodebuild` + `codesign`，只有 macOS 有），所以走 macOS runner。
装机：下载 artifact → Windows 装 Sideloadly → iPhone USB 连接 → 拖入 IPA 用 Apple ID 签名 →
手机「设置 → 通用 → VPN 与设备管理」信任证书。免费证书 **7 天**过期，重签即可，存档不丢。

CI 失败时日志会推到 `ci-logs` 分支（`git fetch origin ci-logs` 即可看）。

---

## 调试开关（环境变量）

| 开关 | 用途 |
|---|---|
| `SHIP=1` | 关掉 demo 劫持。**冒烟测试必须带**，否则假人永不死、结算路径根本没测到 |
| `REVIEW=1 REVIEW_TURTLE=<id> REVIEW_SKILL=<idx>` | 单技能审阅台 |
| `EQDEMO_* + EQDEMO_ATTACKER=1` | 装备演示（靠命中/充能触发的装备**必须带 ATTACKER**） |
| `DUALLANE=1 STRESS=1 DL_AUTOFIGHT=1 AUDIT=1` | 双路压测 + 自动巡检 |
| `MAPEDIT=1` / `DEBUG_EDIT` | 地图编辑器 / 调试场 |
| `SELFSHOT` `SHOT_OUT` | 自截图 |

---

## 给协作者 / AI 的约定

工作约定写在 [CLAUDE.md](CLAUDE.md)，含本项目**踩过的地雷**（不是假想的）：
单位字典不能做 key、两条独立的伤害路径、`_t` 跨路累加不重置、测试等效果要用墙钟不能用帧数等。
动手前先读它，能省掉一整轮返工。
