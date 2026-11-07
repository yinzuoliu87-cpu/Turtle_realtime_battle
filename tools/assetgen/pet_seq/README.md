# pet_seq — 14 只新形象龟的动作源帧

`build_turtle_seq.py` 的输入。每只龟一个目录：

| 文件 | 内容 |
|---|---|
| `seq.json` | 每段的 `ox` / `ground`（这段帧里 art 原点在哪）、`rel`（命中帧或释放帧）、`fps`（只有 form / state 段用；普攻与技能的帧率由游戏按前摇现算） |
| `avatar.png` | 头像源图 128×128，PixelLab Pro Flash 编辑出的头部特写 |
| `idle/` `run/` `attack/` `death/` | 待机、走路、普攻、阵亡 |
| `cast_<技能类型>/` | 技能释放动作，技能类型与 `data/pets.json` 一致 |
| `form_<段名>/` | 一次性段：被动、两段式技能的后半段、`<状态名>_end` 收招段 |
| `state_<状态名>/` | 持续状态循环，判据在 `AttackRhythm.state_active` |

帧都是**裸帧**，不含演示特效；AI 素材自带的飞行道具已擦掉，因为这些都由游戏特效画。

改动流程：改源帧或 `seq.json` → `python tools/assetgen/build_turtle_seq.py [龟id]` → `python tools/assetgen/build_spine_actions.py --gd-only` → Godot `--import`。

排帧脚本（从 PixelLab 原始段排成这里的裸帧）在 `tools/oneoff/turtle_seq_1107/`。
