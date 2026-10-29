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

## ★默认整层停用后端(2026-10-21: 单跑测试没带 TURTLE_BACKEND / TURTLE_SUPABASE ⇒ 默认连正式服, 一晚上 4 个匿名号进了正式库)。
##   调用方自己给了值就用调用方的(测试接假服务器等); 真要连服务器看效果: ONLINE=1。
if [ -z "${ONLINE:-}" ]; then export TURTLE_BACKEND="${TURTLE_BACKEND- }" TURTLE_SUPABASE="${TURTLE_SUPABASE- }"; fi

## ★默认给一份临时 user://(2026-10-29): 有 26 个测试会自己把 test_mode 关掉再 save(它们以为跑在隔离目录里),
##   在本机真实目录里单跑 ⇒ verify_tutorial_flow_v3 把假账号 gate-acc-tut 写进了用户的真存档,
##   桌面 exe 开局拿着这个账号去刷新令牌, 刷回来是别的号 ⇒ 好友页「网络异常」。run-tests.sh 每个测试各给一份, 这里原来没给。
##   调用方自己给了 APPDATA / XDG_DATA_HOME(不是本机默认那个)就用调用方的; 真要用本机真实存档: REALUSER=1。
##   Windows 的 user:// 看 APPDATA, Linux 看 XDG_DATA_HOME —— 两个都设(只设一个只在一个平台上算数)。
##   不删目录(exec 之后 PID 就是 Godot, 按 PID 杀得到它); 每次顺手清掉一天前的旧目录。
if [ -z "${REALUSER:-}" ]; then
  _norm () { cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; }
  _custom=""
  [ -n "${APPDATA:-}" ] && [ "$(_norm "$APPDATA")" != "$(_norm "${USERPROFILE:-$HOME}/AppData/Roaming")" ] && _custom=1
  [ -n "${XDG_DATA_HOME:-}" ] && [ "$(_norm "$XDG_DATA_HOME")" != "$(_norm "$HOME/.local/share")" ] && _custom=1
  if [ -z "$_custom" ]; then
    _tmp="${TMPDIR:-/tmp}"
    find "$_tmp" -maxdepth 1 -name 'godot-quiet-ud.*' -mtime +1 -exec rm -rf {} + 2>/dev/null
    _ud="$(mktemp -d "$_tmp/godot-quiet-ud.XXXXXX")"
    export XDG_DATA_HOME="$_ud" APPDATA="$(cygpath -w "$_ud" 2>/dev/null || printf '%s' "$_ud")"
    echo "[godot-quiet] user:// 用临时目录 $APPDATA (要用本机真实存档: REALUSER=1)" >&2
  fi
fi
exec env QUIET=1 "$GODOT" $HEADLESS --audio-driver Dummy --path "$DIR" "$@"
