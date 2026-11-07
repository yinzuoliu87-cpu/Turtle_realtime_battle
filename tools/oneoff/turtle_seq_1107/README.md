# turtle_seq_1107 — 14 只新形象龟的排帧脚本

一次性脚本，留档用。流程：PixelLab 原始段（`.out/review/<龟>_sample/`，不进仓库）→ `auto_build.py` / `bubble_build.py` / `diamond_build.py` / `three_bare.py` 按游戏节奏排帧 → `seq_export.py` 落到 `tools/assetgen/pet_seq/` → `tools/assetgen/build_turtle_seq.py` 打包。

- 设 `ACT_BARE=<龟id>` 时不画演示特效、不出视频，只导裸帧。不设时出验收成片。
- `seq_export.py` 里的 `HOLD` 和各分支写的是每个技能的真实时间线（放技能后几秒才生效、哪些要拆段），依据是对应 `_system.gd` 的代码。
- 路径是 2026-11-07 那次会话的绝对路径，重跑前先改。
