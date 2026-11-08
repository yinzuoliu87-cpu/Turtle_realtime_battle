# tools/ — 本机工具

2026-11-02 重整（方案书 [docs/plans/20261102-文件管理与发版流程重整.md](../docs/plans/20261102-文件管理与发版流程重整.md)）。
本目录有 `.gdignore`：Godot 不把这里的东西当素材导入（测试里读这里的文件一律用 `FileAccess` / `Image.load_from_file`）。

| 位置 | 是什么 | 能不能随便跑 |
|---|---|---|
| `tools/*_audit.py` `*_lint.py` 等 | **门禁审计器**。进门禁的那些以 `run-tests.sh` 里的 `run_audit` 行为准（清单从那里自动扫出来，这里不另抄） | 只读，可反复跑 |
| `tools/release.py` `asc.py` `deploy.py` `prod_flags.py` | **发版流水**（CLAUDE.md §3）。每条都有 `--dry-run` / 只读子命令 | 真跑会打 tag / 提审 / 部署 / 写正式服 —— 照 CLAUDE.md §3 的顺序 |
| `tools/mainsite_deploy.py` `mainsite_beta_smoke.py` | **龟投网关内测环境**：一条命令部署（内测服迁移 → 裁判机网关 / env / Caddy → 回读）、一条命令联调冒烟（扮演主站 + App）。用法见 `server/referee/README.md`「内测环境部署与联调」 | 部署默认只演练、`--apply` 才动（周末另要 `--weekend-ok`）；冒烟会在内测服建 / 删测试号，`--mock` 只在本机 |
| `tools/sb_migrate.py` `sb_ro.py` `sb_common.py` `beta_ops.py` | **数据库**：迁移（沙盒 → 内测 → 正式）、正式服只读查询 | `sb_ro.py` 只读；迁移写库要用户点头 |
| `tools/clean.py` | 清本机开发产物（默认只列，`--apply` 才动） | 安全 |
| `tools/assetgen/` | **素材生成脚本**（`blender_*` `build_*` `bake_*` `gen_*` 等）：重跑会覆盖 `assets/` 里的成品。生成结果要确定性、重跑逐字节相同 | 会写素材文件 |
| `tools/oneoff/` | **一次性脚本**：为某次迁移 / 同步写的，多数已完成使命，留作记录 | 别随便跑（可能改文件或写云端） |
| `tools/art_src/` | 素材生成脚本读的原图 | —— |
| 其余 `tools/*.py` | 手动诊断工具与被别的脚本 import 的库 | 看各自头注 |

新工具放哪：进门禁的审计器放根目录并在 `run-tests.sh` 加一行 `run_audit`；生成素材的放 `assetgen/`；只用一次的放 `oneoff/`。
**发版 / 部署 / 运维用的脚本进仓库**，不留在会话临时目录（CLAUDE.md §8）。
