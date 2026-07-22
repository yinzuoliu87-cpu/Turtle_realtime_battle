# CLAUDE.md — 项目工作约定

斗龟场·实时版。Godot **4.6.3** / GDScript。2.5D（3D 场景 + Sprite3D 公告板）自走棋，28 只龟 × 59 件装备，双路对战。

---

## 1. 事实源（谁说了算）

按可信度排序。**冲突时一律以上位者为准，不要反过来"按文档改代码"。**

| 级别 | 位置 | 说明 |
|---|---|---|
| **1. 代码** | `scripts/` `autoload/` | 最终事实。任何数值问题的终审 |
| **2. 数据** | `data/*.json` | 由 `DataRegistry` 载入：28 龟、59 装备、状态、规则 |
| **3. 权威文档** | `docs/design/28龟技能设计-权威.md`<br>`docs/design/实时版-系统机制权威.md`<br>`docs/实时版-路线图与待办.md` | **只有这三份**。它们被同步工具当事实源用 |

`docs/` 下其余 90+ 篇是历史记录/草案/账本，**默认不可信**，多数带 ⛔/⚠ 横幅。不要因为标题写着"权威""焊死""单一事实源"就当真——曾同时有 4 份文件自称唯一事实源。

**装备属性的真事实源是 `P2RT.STATS`**（`scripts/engine/phase2_equip_runtime.gd`），战斗与背包 UI 都从它取值。`data/phase2-equipment.json` 里的 `baseStats1` 是它的手写镜像，仅供展示。

---

## 2. 提交前门禁

```bash
bash run-tests.sh          # 自证测试(自动发现) + 全流程冒烟 + 三方对账
```

- 测试**自动发现** `tests/verify_*.gd`，新增测试放进去配好 `.tscn` 即自动纳入，**无需登记**。
  （2026-07-20 之前是硬编码名单，导致 8 个测试从没被执行过。）
- 判定不只看退出码，还过一条**致命报错正则**（`run-tests.sh` 顶部 `FATAL`）。
  **漏一个模式就等于把 bug 判成绿灯** —— 历史上 `Max recursion` 曾不在名单里，24 组压测全报"0 errors"，而真实对局每秒刷几百条错误。新报错形态往这条正则里加。
- 慢测试的帧预算在 `frames_for()` 里登记。`--quit-after` 单位是**帧**不是毫秒；帧数不够会让测试跑到一半被掐断，表现为"没打 ALL PASS"而**不是**某条断言 FAIL —— 极易误判成真失败。

只读审计器（可反复跑）：

```bash
python tools/data_integrity.py         # json 交叉引用 / 资源路径 / 孤儿字段
python tools/tri_audit.py              # pets.json ↔ 活代码 ↔ 权威文档
python tools/tooltip_number_audit.py   # 装备文案数值 ↔ 代码
python tools/hp_staleness_check.py     # 云端同步新鲜度
```

---

## 2.5 版本号（每次玩家可感知的改动都要 +1）

`大版本.功能版本.改动序号`，当前 `0.10.2`。第 3 位每次改动 +1；第 2 位加新玩法时 +1。

**改版本号要同时改四处**，漏一处 `verify_version` 直接红：

| 处 | 位置 |
|---|---|
| ① 事实源 | `project.godot` → `config/version` |
| ② 记账 | `CHANGELOG.md` 顶部新增 `## x.y.z — YYYY-MM-DD` |
| ③ iOS 包 | `export_presets.cfg` → `application/short_version` |
| ④ Android 包 | `export_presets.cfg` → `version/name` |

游戏内显示（主菜单右下角）**从 `ProjectSettings` 读**，不许写死 —— 门禁会扫硬编码字面量。
版本号的全部价值在于**测试者报 bug 时能说清是哪个版本**，四处不一致就说不清了。

---

## 3. 本项目特有的地雷

**这些都是踩过的，不是假想。**

### 3.1 `HP_MULT` 只用于两处
`RealtimeBattle3DScene.gd` 顶部的 `HP_MULT = 3.0` **只能**用于：召唤物 raw 值（`×`）、装备百分比回收（`maxHp /`）。

**龟和装备的 `hp` 数值本身已是最终值，不要再乘。** 曾因此让哑铃实发 330 而非文案的 110，且同一盲区污染了文案核对——只读数组字面量漏掉尾部的 `* HP_MULT`，导致文案和代码各错各的、还互相印证。

### 3.2 单位字典不能做 key / 不能用 `==`
Godot 会**递归哈希**整个 Dictionary，而单位字典之间互相引用成环 → 无限递归 → 卡死。

- 比较用 `is_same(a, b)`，不要 `==`
- 判断存在用 `_arr_has_unit()`，不要 `in` / `.has()`
- 绝不拿单位字典当 Dictionary 的键

### 3.3 两条独立的伤害路径
`_apply_damage(u, dmg, ...)`（DoT/真伤）和 `_apply_damage_from(src, u, dmg, ...)`（普攻/技能）**各自扣盾扣血**。改伤害逻辑必须**两条都改**，只改一条会产生只在某类伤害下出现的诡异行为。

### 3.4 `_t` 跨路累加，永不重置
全局时钟 `_t` 会跨上路→下路→决胜一直累加。任何**按本场战斗**计时的机制都必须自己存 `t0`（见 `_sd_t0`），直接用 `_t` 会让下路一开场就触发。

### 3.5 脚本批量改代码：注释绝不插进行中间
行内注释会**静默吃掉同行后续内容**。一天之内踩过三次：吃掉 `if` 行尾的 `:`（跑了 40 分钟的批次全废）、吃掉同行后续 6 个 dict 项。

- 替换串里**不要带 `#`**；要加说明就单独占一行放目标行**上方**
- 按标记删多行块时**每行都要打标记**，否则删掉 `func`/`if` 头会留下孤儿函数体
- **每次脚本改完 `.gd` 立刻编译验证**，别等跑完测试才发现

---

## 4. 测试与调试开关（环境变量）

| 开关 | 用途 |
|---|---|
| `SHIP=1` | 关掉 demo 劫持。**冒烟测试必须带** —— 否则假人永不死、战斗永不结束、结算路径根本没测到 |
| `REVIEW=1 REVIEW_TURTLE=<id> REVIEW_SKILL=<idx>` | 单技能审阅台 |
| `EQDEMO_*` + `EQDEMO_ATTACKER=1` | 装备演示。**靠命中/充能触发的装备必须带 ATTACKER**，否则不会触发却看着像"没生效" |
| `DUALLANE=1 STRESS=1 DL_AUTOFIGHT=1 AUDIT=1` | 双路压测 + 自动巡检 |
| `MAPEDIT=1` / `DEBUG_EDIT` | 地图编辑器 / 调试场 |
| `SELFSHOT` `SHOT_BURST` `SHOT_STEP` `SHOT_OUT` | 自截图 |

---

## 5. 代码风格

实测已高度统一，跟着现状写即可：

- 缩进 **tab**（80/80 文件，零空格缩进、零混用）
- 函数名 **snake_case**（1375 个函数零例外）；`class_name` **PascalCase**
- 类型标注：返回值 **98.4%**、变量 **93.3%** —— 新代码请标注
- 拆分模板照抄 [`scripts/scenes/dmg_stats_panel.gd`](scripts/scenes/dmg_stats_panel.gd)：`RefCounted` + 构造注入 `CanvasLayer` + `Callable` 取只读数据，主场景侧只剩 3 行

> `scripts/engine/` **不是**已拆出去的行为层，是**回合制旧版引擎**。实时版只借用了它的 `STATS` 表，其余全是平行重写，**不要当拆分模板**。

---

## 6. 构建与发布

**动手做包之前先看这张表。** 2026-07-22 我在 Windows 上折腾了半天 iOS 出包（导 Xcode 工程、实测能不能直接出 ipa、退而求其次构建 Web），而 `.github/workflows/ios-build.yml` **一直就在仓库里**——只是我没查。

| 目标 | 怎么做 | 产物 |
|---|---|---|
| **iOS 装机包** | push 到 `main`（或手动 dispatch）→ **`.github/workflows/ios-build.yml`** | Actions artifact `turtle-ios-unsigned`（unsigned .ipa，留 14 天） |
| 提交门禁 | push 自动跑 `.github/workflows/tests.yml` | 47 项，ubuntu |
| Web（手机浏览器直接玩） | `SHIP=1 bash build-web.sh` | `build/turtle-realtime-web.zip` |
| Android APK | 见 [实时版APK打包.md](docs/实时版APK打包.md) | `build/android/*.apk` |

**iOS 的硬事实（实测，别再试）：**

- **Windows 出不了 `.ipa`**。打 ipa 要 `xcodebuild` + `codesign`，只存在于 macOS。把 `export_project_only` 改成 `false` 也没用——Godot 照样只吐 Xcode 工程，**退出码 0、不报错**，得自己发现产物里没有 ipa。所以只能走 macOS runner。
- 装机流程（工作流注释里也有）：下载 artifact → Windows 装 **Sideloadly** → iPhone USB 连电脑 → 拖入 IPA 用 Apple ID 签名 → 手机「设置→通用→VPN与设备管理」信任证书。免费证书 **7 天**过期，重签即可，存档不丢。
- `export_presets.cfg` 的 **`application/targeted_device_family` 是枚举下标不是设备号**：
  `0`→`"1"` iPhone ／ `1`→`"2"` iPad ／ `2`→`"1,2"` 通用。
  按字面读会改反（我把"通用"改成了"仅 iPad"）。**改完要回读导出后 `turtle.xcodeproj/project.pbxproj` 里的 `TARGETED_DEVICE_FAMILY` 确认**，光看 cfg 看不出来。
- 只验"导出没报错"不够。导出版**禁用了 `disable_path_overrides`**，命令行给场景路径会直接 Abort，所以打包版默认只能启动 `run/main_scene`。想验打包后的真实对局：临时把 `run/main_scene` 改成 `res://tests/smoke_scenes.tscn`，导一个一次性包跑完再还原。
- 本地无 `gh`、无 token，读不了 Actions API。**工作流失败会把日志推到 `ci-logs` 分支**，`git fetch origin ci-logs` 即可看——这是设计好的逃生口。

---

## 7. 工作方式

- **新需求先写方案书再动手**（用户 2026-07-22 定）：`docs/plans/YYYYMMDD-<简称>.md`，
  格式与理由见 [docs/plans/README.md](docs/plans/README.md)。**必含「已知风险与未决点」一节** ——
  不写这节就等于在宣称"无漏洞"，而那从来不成立。
  三类真实教训催生了这条：①需求描述与代码事实相反（侵入那次方向是反的）
  ②改动面被低估 3 倍（写"改 6 处"，穷举后是 20 处）③方案前提到实施才发现不成立
- **本地 commit 不 push**，除非用户点名要推
- 报"做完了/没问题/对齐了"之前，**先证明检查本身会 FAIL**：故意改坏一个值，确认脚本报错。打印分母——`N=0` 是空检查不是通过
- 断根因**先写探针打具体数值**，推理出来的不算根因
- 巡检记账放在**事件发生处且无条件**；采样看不见缝隙，会造出假现象
- **动手造轮子前先搜仓库**：`ls .github/workflows/`、`ls *.sh`、`ls tools/`、`docs/README.md`。已经有的东西比现搭的更贴合项目（含踩过的坑与逃生口）——iOS 工作流那次就是没搜
- 重定向写 **`> log 2>&1`**，不是 `2>&1 > log`。后者顺序反了，stderr 去了终端、日志只剩 stdout，于是"致命 0 条"是对着空日志数出来的假绿灯
- **别用 `git checkout -- <file>` 清理临时改动**——它会连同**未提交的真实工作一起回滚**。只想删刚追加的几行就用 `sed -i '$d'`（我刚因此丢了一整节，重写了一遍）
