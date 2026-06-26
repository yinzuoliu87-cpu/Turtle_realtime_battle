# 斗龟场 v2 — Godot 4

> 龟龟对战的 Godot 实现，从 Phaser 3 PoC（`../turtle-battle-poc/`）迁移而来。
> 2026-05-30 启动，目标海外 App Store + Steam Web。

## 📁 文档 (`docs/`)

迁移规格 / 审计账本 / 待办都在 [`docs/`](docs/)：
- `MIGRATION-SPEC.md` / `MIGRATION-PLAN.md` — 迁移权威规格与计划
- `BATTLE-FIDELITY-AUDIT.md` — 战斗场景逐模块 cited 保真审计 (F/G 修复清单)
- `OTHER-SCENES-AUDIT.md` — Codex/主菜单/结算/菜单场景审计
- `PRESENTATION-SCENES-SPEC.md` / `MENU-SCENES-SPEC.md` / `C-GROUP-SPEC.md` — 各场景/系统规格
- `BATTLE-ANIM-TODO.md` / `COMPLETION-BACKLOG.md` — 动画与收尾待办

---

## 怎么打开

1. 装 [**Godot 4.3 Standard**](https://godotengine.org/download/windows/)（**不要 .NET 版**，本工程用 GDScript）
2. 打开 Godot → `Project Manager` → `Import` → 选这个文件夹（认到 `project.godot`）
3. 点 `Edit`
4. 按 **F5**（或顶部 ▶️）跑起来，应该看到一个深海蓝背景 + "斗龟场 v2 — Godot 起点" 字样

如果看到字 = 你装对了。

### ⚠️ git pull 后报 "Identifier ... not declared" 怎么办

如果 pull 完跑出来报 `Identifier "StatsRecalc"/"Buffs"/"GameState" not declared` 或 `Compilation failed`：
这是 **Godot class_name 缓存没刷新**（`.godot/` 不入 git，新增的 `class_name` 脚本你的编辑器还没扫描）。

修复（任选）：
1. **完全关闭 Godot 再重开项目**（最可靠，开项目时会重扫所有脚本注册 class）
2. 菜单 **项目 → 重新加载当前项目**（不是右上弹窗的"从磁盘重载"）
3. 还不行 → 关 Godot，删 `.godot/` 文件夹，重开（全量重建）

**只有 pull 到新增 `*.gd` class 文件那次需要**；改已有文件不用。这是 Godot 固有行为，非 bug。

---

## 当前状态

| 内容 | 状态 |
|---|---|
| 项目骨架 | ✅ 2026-05-30 |
| 数据层迁移（28 龟 / 100+ 装备 / 10 羁绊 / 50 成就） | ⏳ 待做（脚本化批量转 JSON） |
| 战斗算法（damage / dealPhysical / dealMagic / dealRaw） | ⏳ 待翻译 GDScript |
| 100+ 技能 handler | ⏳ 大头工作 |
| Scene / UI | ⏳ 全新做（Godot 节点编辑器） |
| 美术资源（28 龟 + 装备图 + 技能图 + BGM） | ✅ 已有，待导入 |

详细路线图见 [MIGRATION-PLAN.md](MIGRATION-PLAN.md)。

---

## 目录约定

```
games/turtle-battle-godot/
├── project.godot          ← Godot 项目配置（双击此文件可在 Godot Manager 里打开）
├── icon.svg               ← 项目图标
├── scenes/                ← Scene 文件 (.tscn)
│   └── Main.tscn          (起点)
├── scripts/               ← GDScript 脚本 (.gd), 跟 Scene 配对挂载
├── autoload/              ← 全局单例 (类似 Phaser 的 systems/)
├── data/                  ← JSON 数据文件 (从 PoC TS 自动转)
├── assets/
│   ├── sprites/           ← PNG / 精灵表 / 头像
│   ├── audio/             ← BGM / SFX
│   └── fonts/             ← 字体
└── addons/                ← 第三方插件（暂空）
```

---

## 学习路径（如果你是新 Godot 用户）

1. **官方教程**（4 小时）：[GDQuest "Getting Started"](https://www.gdquest.com/tutorial/godot/learning-paths/getting-started-in-2023/)
2. **YouTube**（45 分钟）：[Brackeys "How to make a Video Game"](https://www.youtube.com/watch?v=LOhfqjmasi0)
3. **GDScript 语法**（1 小时）：[官方文档（中文）](https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/gdscript/gdscript_basics.html)

---

## 历史

- Phaser PoC 在 [`../turtle-battle-poc/`](../turtle-battle-poc/)，已冻结见 [NOTICE.md](../turtle-battle-poc/NOTICE.md)
- 旧版 JS 全套（PoC 的 1:1 对照源）在 [`../../_reference/turtle-battle-js/`](../../_reference/turtle-battle-js/)
- 美术原稿（.aseprite / .psd）在 [`../../_assets-source/`](../../_assets-source/)
