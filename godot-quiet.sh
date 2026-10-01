#!/usr/bin/env bash
# godot-quiet.sh — 跑单个测试/场景用的 Godot 包装器, **强制静音**。
#
# 由来: 用户 2026-10-01「一定要静音，确保这一点好吗」→ 我答了"headless 就没窗口"
# 就以为完事, 结果他接着说「你这没静音啊」。查下来: `run-tests.sh` 里三处调用都带着
# `--audio-driver Dummy`, 而**我手敲的单测运行一处都没带** —— 而 run-tests.sh 自己
# 390 行的注释早就写着「`--headless` 不包含静音, 它只关渲染, 音频驱动照旧初始化并出声」。
# 规矩写在那儿, 只有脚本在遵守, 人不遵守。⇒ 把它做成**不用想起来**的东西。
#
# 用法: bash godot-quiet.sh res://tests/verify_xxx.tscn --quit-after 600
#       bash godot-quiet.sh --max-fps 15 res://tests/verify_xxx.tscn --quit-after 4000
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ★--headless 也一起带上: 没有窗口 + 没有声音, 两件事要一起保证。
#   要截图(必须开真窗口)的场合【不要用这个脚本】, 那是另一回事, 而且得先问用户。
exec "$GODOT" --headless --audio-driver Dummy --path "$DIR" "$@"
