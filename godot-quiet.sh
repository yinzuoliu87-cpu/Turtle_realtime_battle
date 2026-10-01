#!/usr/bin/env bash
# godot-quiet.sh — 跑测试 / 开窗口看效果用的 Godot 包装器，**强制静音**。
#
# 由来（2026-10-01，连着踩了三次）:
#   ① 用户:「一定要静音，确保这一点好吗」→ 我答「headless 就没窗口」
#      —— 答的不是他问的那一维（他问声音，我确认的是窗口）。
#   ② 他:「你这没静音啊」→ 查出 run-tests.sh 三处调用都带 `--audio-driver Dummy`，
#      而**我手敲的单测运行一处都没带**；那份脚本自己的注释早就写着
#      「`--headless` 不包含静音，它只关渲染，音频驱动照旧初始化并出声」。
#   ③ 他:「你一开窗口，就有声音啊」→ 于是不能再靠 `--audio-driver Dummy`：
#      **我拿不出它生效的证据**（`--verbose` 里引擎根本不打印选中了哪个音频驱动）。
#
# ⇒ 真正的静音是 `QUIET=1`：`autoload/Audio.gd::_apply_quiet_gate` 把**引擎主总线**
#   静音 + 压到 -80 dB。它与音频驱动无关，而且 `AudioServer.is_bus_mute(0)`
#   能被门禁直接量（`tests/verify_quiet_mute.gd`，正反两面都断言过）。
#   `--audio-driver Dummy` 保留，当第二道而不是唯一一道。
#
# 用法:
#   bash godot-quiet.sh res://tests/verify_xxx.tscn --quit-after 600      # 无头(默认)
#   WINDOW=1 bash godot-quiet.sh res://scenes/Codex.tscn                   # 开窗口, 同样静音
#   WINDOW=1 bash godot-quiet.sh --resolution 540x960 res://scenes/X.tscn
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ★WINDOW=1 才开真窗口；默认无头。开窗口也照样静音 —— 这正是用户要的那条:
#   「你开窗口没问题，但是我要静音」。
HEADLESS="--headless"
[ -n "${WINDOW:-}" ] && [ "${WINDOW}" != "0" ] && HEADLESS=""

exec env QUIET=1 "$GODOT" $HEADLESS --audio-driver Dummy --path "$DIR" "$@"
