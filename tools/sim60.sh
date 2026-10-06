#!/usr/bin/env bash
# tools/sim60.sh —— 60 个模拟玩家, 分 6 批 × 10 个跑积分赛(每批跑完自己退出, 再起下一批)
#
# ══════════════════════════════════════════════════════════════════════
#  用户 2026-10-06:「开 60 个窗口(或者依次)模拟 60 个真实用户打积分赛, 记录不合理的地方,
#   每个界面都要检查」「晋级的存档要留到周六」「买装备…换不同的龟、不同的技能」「训龟大师也要点」
# ══════════════════════════════════════════════════════════════════════
#
# ★为什么分批: 60 个 Godot 窗口同时开, 这台机器会卡死/蓝屏(memory project-machine-bsod-during-tests)。
#   ⇒ 一批 10 个(与上周 sim10 同一个量级), 批与批之间串行。
#
# ★与 sim10.sh 的区别(其余照抄它踩过的坑):
#   · 存档根 /c/tmp/turtle-sim60/p01..p60 —— **不碰**上周的 /c/tmp/turtle-sim10。
#   · 每个窗口带 SIM_DRIVER=1(scripts/systems/sim/sim_driver.gd): 自己走 教学→选龟/选招→打→
#     结算→商店买→背包装→下一局, 第一次还会把每个界面逛一遍截图。不需要任何人点鼠标。
#   · 窗口叠放在【右屏】(用户 2026-10-03「整个右屏现在都是你的，我在用左屏」),
#     不抢焦点(驱动给窗口挂了 FLAG_NO_FOCUS), 静音(QUIET=1 + --audio-driver Dummy)。
#   · pid 用命令行里的 `--sim-slot=NN` 认(Win32_Process.CommandLine), 不靠「最新的 Godot」去猜。
#   · 游客(匿名号), 与上周一样 —— 墙已拆(phase2_config.WALL_BLOCKS=false), 打排位不要邮箱。
#
# 跑法:
#   bash tools/sim60.sh start <批号1..6>     # 起这一批 10 个(槽位 (批-1)*10+1 .. 批*10)
#   bash tools/sim60.sh wait  <批号>         # 等这一批全部自己退出(打到配额满/没命)
#   bash tools/sim60.sh stop                 # 只关本脚本记下的 pid
#   bash tools/sim60.sh status [批号]        # 每个槽位: 进程/账号/场次/胜/命/配额
#   bash tools/sim60.sh roster               # 打印 60 个槽位的龟/招分配表(跑的是驱动用的同一个函数)
#   bash tools/sim60.sh scan [批号]          # 汇总事件日志 + godot.log 里的报错(python tools/sim60_scan.py)
#   SLOTS="3" bash tools/sim60.sh start 1    # 只起某几个槽位(冒烟用), 空格分隔
#
# 可调:
#   SIM_X/SIM_Y   窗口左上角(默认 2000,80 = 右屏)    PER_BATCH 每批几个(默认 10)
#   SIM_ROUNDS    每个窗口最多开几局积分赛(默认不限 = 打到被拦)
#   SIM_QUIT_WHEN_DONE  默认 1(打完自己退出, 批量必需); 想留着窗口看就设空
set -u

GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ROOT="${SIM_ROOT:-/c/tmp/turtle-sim60}"
PIDFILE="$SIM_ROOT/pids.txt"
PER_BATCH="${PER_BATCH:-10}"
WX="${SIM_X:-2000}"
WY="${SIM_Y:-80}"
QWD="${SIM_QUIT_WHEN_DONE-1}"

slot_dir() { printf "%s/p%02d" "$SIM_ROOT" "$1"; }
slot_save() { printf "%s/Godot/app_userdata/斗龟场 实时版/savegame.json" "$(slot_dir "$1")"; }
win() { cygpath -w "$1" 2>/dev/null || echo "$1"; }

batch_slots() {
  local b="$1"
  if [ -n "${SLOTS:-}" ]; then echo "$SLOTS"; return; fi
  seq $(( (b - 1) * PER_BATCH + 1 )) $(( b * PER_BATCH ))
}

## 槽位 → 进程 pid(按命令行里的 --sim-slot=NN 认)。没有就空。
slot_pid() {
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'Godot%'\" | Where-Object { \$_.CommandLine -match '--sim-slot=$(printf '%02d' "$1")( |\$)' -and \$_.CommandLine -match 'turtle-sim60' } | Select-Object -First 1 -ExpandProperty ProcessId" 2>/dev/null | tr -d '\r'
}

cmd_start() {
  local b="${1:-}"
  case "$b" in ''|*[!0-9]*) echo "用法: bash tools/sim60.sh start <批号1..6>"; exit 1;; esac
  [ -f "$GODOT" ] || { echo "★找不到 Godot: $GODOT"; exit 1; }
  mkdir -p "$SIM_ROOT"
  touch "$PIDFILE"
  echo "第 $b 批: 槽位 $(batch_slots "$b" | tr '\n' ' ')· 右屏叠放($WX,$WY) · 静音 · 不抢焦点 · 自动驾驶"
  local i
  for i in $(batch_slots "$b"); do
    local d; d="$(slot_dir "$i")"
    mkdir -p "$d/shots"
    if [ -n "$(slot_pid "$i")" ]; then
      printf "  p%02d 已经在跑, 跳过\n" "$i"; continue
    fi
    ## ★必须用 Start-Process 起(Bash 的 & 起的会跟着 shell 被收掉 —— memory fb-vfxlab-window-must-be-muted)
    ## ★TURTLE_BACKEND 不清空: 这些是真用户, 要打真后端。
    powershell -NoProfile -Command "
      \$env:APPDATA='$(win "$d")';
      \$env:SHIP='1'; \$env:QUIET='1';
      \$env:SIM_AUTOPILOT='1'; \$env:SIM_DRIVER='1';
      \$env:SIM_SLOT='$i';
      \$env:SIM_SHOT_DIR='$(win "$d")\\shots';
      \$env:SIM_ROUNDS='${SIM_ROUNDS:-}';
      \$env:SIM_QUIT_WHEN_DONE='$QWD';
      \$env:SIM_TOUR='${SIM_TOUR:-}';
      Start-Process -FilePath '$(win "$GODOT")' \
        -ArgumentList '--path','$(win "$PROJ_DIR")','--audio-driver','Dummy', \
                      '--resolution','1280x720','--position','$WX,$WY', \
                      '--','--sim-slot=$(printf '%02d' "$i")','--sim-root=turtle-sim60' | Out-Null" 2>/dev/null
    sleep 4
    local pid; pid="$(slot_pid "$i")"
    printf "%d %s %s\n" "$i" "${pid:-?}" "$(date -u +%FT%TZ)" >> "$PIDFILE"
    printf "  p%02d  pid=%-7s 目录=%s\n" "$i" "${pid:-没找到}" "$d"
    sleep 4    # 错开启动: 十个 Godot 同时初始化渲染会互相拖慢, 也错开匿名注册
  done
  echo "看画面: $SIM_ROOT/pNN/shots/latest.png(每 5 秒自拍) · 命名截图同目录 *.jpg"
  echo "事件: $SIM_ROOT/pNN/Godot/app_userdata/斗龟场 实时版/sim_events.jsonl"
}

cmd_wait() {
  local b="${1:-}" left i
  case "$b" in ''|*[!0-9]*) echo "用法: bash tools/sim60.sh wait <批号>"; exit 1;; esac
  while :; do
    left=""
    for i in $(batch_slots "$b"); do
      [ -n "$(slot_pid "$i")" ] && left="$left p$(printf '%02d' "$i")"
    done
    [ -z "$left" ] && { echo "第 $b 批全部退出 $(date -u +%T)Z"; return 0; }
    echo "$(date -u +%T)Z 还在跑:$left"
    sleep 60
  done
}

cmd_stop() {
  local n=0 i pid
  for i in $(seq 1 60); do
    pid="$(slot_pid "$i")"
    if [ -n "$pid" ]; then
      powershell -NoProfile -Command "Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue" 2>/dev/null
      printf "  关掉 p%02d (pid=%s)\n" "$i" "$pid"; n=$((n+1))
    fi
  done
  echo "共关掉 $n 个(只认命令行带 --sim-slot 且属于 turtle-sim60 的 Godot)。"
}

cmd_status() {
  local b="${1:-}" i list
  if [ -n "$b" ]; then list="$(batch_slots "$b")"; else list="$(seq 1 60)"; fi
  printf "%-5s %-7s %s\n" "槽位" "进程" "账号 / 场次 / 胜 / 命 / 配额 / 龟"
  for i in $list; do
    local sv pid; sv="$(slot_save "$i")"; pid="$(slot_pid "$i")"
    [ -f "$sv" ] || continue
    printf "p%02d   %-7s " "$i" "${pid:--}"
    python - "$sv" <<'PY'
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("<读不出: %s>" % e); raise SystemExit
print("%s %s/%s/%s/%s %s" % (str(d.get("account_id", ""))[:8] or "<未建号>",
    d.get("season_total_battles", "?"), d.get("season_wins", "?"), d.get("hearts", "?"),
    d.get("ranked_used", "?"), ",".join(map(str, d.get("season_leaders", []) or []))))
PY
  done
}

cmd_roster() {
  QUIET=1 TURTLE_BACKEND=" " TURTLE_SUPABASE=" " "$GODOT" --headless --audio-driver Dummy --path "$PROJ_DIR" \
    -s tools/sim60_roster.gd 2>&1 | grep -E '^\||^COVER|^DUP'
}

case "${1:-}" in
  start)  cmd_start "${2:-}" ;;
  wait)   cmd_wait "${2:-}" ;;
  stop)   cmd_stop ;;
  status) cmd_status "${2:-}" ;;
  roster) cmd_roster ;;
  scan)   python "$PROJ_DIR/tools/sim60_scan.py" "$SIM_ROOT" ${2:+$(batch_slots "$2" | tr '\n' ' ')} ;;
  *)      sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
