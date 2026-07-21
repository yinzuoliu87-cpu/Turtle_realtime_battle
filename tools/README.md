# tools/ — 常备工具 vs 一次性脚本

**2026-07-21 分家。** 以前 20 个脚本混在一起，分不清哪个能随便跑、哪个跑了会改文件。

---

## `tools/` 根目录 = **常备**（只读，可反复跑，跑多少次都安全）

| 脚本 | 干什么 | 进门禁了吗 |
|---|---|---|
| `data_integrity.py` | json 交叉引用 / 资源路径 / 孤儿字段 | ✅ `run-tests.sh` |
| `tooltip_number_audit.py` | 装备文案数值 ↔ 代码（带就近约束 + 反向验证） | ✅ `run-tests.sh` |
| `tri_audit.py` | pets.json ↔ 活代码 ↔ 权威文档 三方对账 | ✅ `run-tests.sh` |
| `codex_audit.py` | 图鉴文案 ↔ 活代码 ↔ 权威文档 | 手动 |
| `asset_audit.py` | 素材引用普查（保守判定，宁漏删不错删） | 手动 |
| `deadcode_audit.py` | 静态可达性死代码勘察 | 手动 |
| `hp_staleness_check.py` | 云端同步新鲜度（只读，不连网） | 手动 |
| `hp_survey.py` | 拉 HacknPlan 全树结构清单（只读） | 手动 |
| `hacknplan_sync.py` | 云端同步**基础库**（被 oneoff/ 里的批次脚本复用） | 库，不单独跑 |

---

## `tools/oneoff/` = **一次性**（为某次迁移/同步写的，会改文件或连网写云端）

**不要随便跑。** 它们是历史批次的留痕，多数已完成使命：

- `hp_s8_systems.py` … `hp_s13_resync.py` — 2026-07 那轮 HacknPlan 云端同步的分批脚本，各自配一份 `*_report.txt`
- `hp_minion_sync.py` — 补推小将三节
- `sync_systems.py` — 已被 `hp_s8_systems.py` 取代
- `dedupe_assets.py` — 按 md5 去重**删文件**
- `repack_sheets.py` — 超 4096 的横条 sheet **重排成网格**
- `reseed_bracket_gear.py` — 快照档位装备重排（2026-07-21 用过一次）

`*_report.txt` 是这些脚本运行时写出的产物，**有意跟踪进 git**：
`hp_staleness_check.py` 靠它们的 mtime 判断云端是否落后，删了会误报"从没同步过"。

---

## 踩过的坑

**搬家必须逐个跑一遍。** 这次分家时 `hp_staleness_check.py` 里写死了
`tools/hp_s*_report.txt` 路径，搬完立刻报 3 条 "从没同步过" —— 是路径坏了，不是真落后。
只看"目录变整齐了"不算验证。
