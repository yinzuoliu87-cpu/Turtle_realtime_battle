#!/usr/bin/env bash
# tools/sim_op.sh —— 操控 tools/sim10.sh 起的那些游戏窗口: 置顶 / 截图 / 真鼠标点击
#
#   bash tools/sim_op.sh focus <slot>
#   bash tools/sim_op.sh shot  <slot>          # → C:/tmp/s<slot>.png (1280x720)
#   bash tools/sim_op.sh click <slot> <x> <y>  # 坐标 = 窗口内原生 1280x720 坐标
#   bash tools/sim_op.sh selftest              # 自检: 工具本身还能用吗
#
# ══════════════════════════════════════════════════════════════════════════
#  ★★2026-09-29 这一天踩过的六个坑，全部写在这里。别再踩一遍。
# ══════════════════════════════════════════════════════════════════════════
#
#  ① **pids.txt 记的 pid 不是拥有窗口的那个**
#     Start-Process 回的 Id 很快就不存在了 —— Godot 起来之后换进程。
#     实测: 记的 42608 已不在, 窗口在 47464 手里 ⇒ focus/click 全部找不到窗口。
#     ⇒ sim10.sh 现在等 2.5 秒后取「带窗口句柄的、最新的那个 Godot 进程」。
#
#  ② **桌面窗口会抢走 (0,0) 那个槽位的点击**
#     早期按「窗口左上角」找窗口, 而 p01 的期望原点正好是 (0,0) ——
#     **桌面(Program Manager)的原点也是 (0,0), 距离 0 永远赢** ⇒ p01 连点七次纹丝不动,
#     其余九个都正常。⇒ 只在 Godot 进程的窗口里找。
#
#  ③ **Windows 前台锁**
#     SetForegroundWindow 在快速切换时被系统静默拒绝 ⇒ 点击落在**上一个还占焦点的窗口**上。
#     十个窗口界面一样, **点错了看不出来**。⇒ AttachThreadInput 借输入队列 + **点完验证焦点真换了**,
#     抢不到就 **exit 2 并打印**, 绝不瞎点。
#
#  ④ **`SetProcessDPIAware()` 不够**
#     那只是【系统级】DPI 感知。第二块屏 DPI 不同时(实测 150%), Windows 把坐标与尺寸虚拟化
#     ⇒ 截图截到窗口左上角一块、点击偏 1.5 倍, 而主屏六个完全正常。
#     ⇒ 必须 **PER_MONITOR_AWARE_V2**(context = -4), 且**问系统要真实客户区**, 别拿算出来的几何当真值。
#
#  ⑤ **像素画糊 = 非整数倍缩放**
#     窗口 624x351 对 1280x720 是 0.4875 倍 ⇒ 像素画必糊(用户当场看出来)。
#     ⇒ 现在**叠放**, 每个窗口开原生 1280x720 = 1:1。平铺十个都糊, 不如一个清楚的。
#
#  ⑥ **别吞掉 click 的输出**
#     `click ... >/dev/null` 会把「抢不到焦点」那条提示一起吞掉 ⇒
#     「我根本没点出去」被当成「点了游戏没反应」, 立成一条假 bug(真事)。
#     要静默就只静默 shot。
#
# ★鼠标是【单一共享资源】: 锁做在这个脚本里, 调用方绕不过去。多 agent 并行必须走这里。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PS="powershell -NoProfile -ExecutionPolicy Bypass -File $ROOT/tools/sim_op.ps1"
SIM_ROOT="${SIM_ROOT:-/c/tmp/turtle-sim10}"
PIDFILE="$SIM_ROOT/pids.txt"
LOCK="${SIM_LOCK:-/c/tmp/turtle-sim-mouse.lock}"

geom() { bash -c "source <(sed -n '/^STACK_X=/,/^}/p' '$ROOT/tools/sim10.sh'); slot_geom"; }
pidof_slot() { awk -v s="$1" '$1==s{print $2}' "$PIDFILE" 2>/dev/null; }

take_lock() {
  local i=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    i=$((i+1))
    if [ "$i" -gt 900 ]; then echo "[sim_op] 等锁 90 秒超时, 强行接管(上一个持有者可能已死)" >&2; rm -rf "$LOCK"; continue; fi
    sleep 0.1
  done
  trap 'rm -rf "$LOCK"' EXIT INT TERM
}

CMD="${1:-}"
if [ "$CMD" = "selftest" ]; then
  echo "=== sim_op 自检 ==="
  [ -f "$PIDFILE" ] && echo "  pids.txt: $(wc -l < "$PIDFILE") 个槽位" || { echo "  ✗ 没有 pids.txt —— 先 bash tools/sim10.sh start N"; exit 1; }
  live=$(powershell -NoProfile -Command "(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Count" 2>/dev/null | tr -d '\r')
  echo "  活着的 Godot 进程: ${live:-0}"
  # ★别用 `kill -0` —— Git Bash 有自己的 PID 空间, 对 Windows pid 一律判"不存在",
  #   于是自检会**全部假红**(2026-09-29 我自己就这么栽了一次: 十个全报死而 agent 正点得好好的)。
  #   ⇒ 查 Windows 进程只能问 PowerShell。
  alive="$(powershell -NoProfile -Command "(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Id -join ','" 2>/dev/null | tr -d '')"
  bad=0
  while read -r slot pid; do
    case ",$alive," in *",$pid,"*) : ;; *) echo "  ✗ p$slot 的 pid=$pid 不在活进程里(坑①)"; bad=$((bad+1)) ;; esac
  done < "$PIDFILE"
  read -r gx gy gw gh <<< "$(geom)"
  echo "  槽位几何: ($gx,$gy) ${gw}x${gh}"
  [ "$gw" = "1280" ] && echo "  ✓ 原生 1:1(坑⑤)" || echo "  ✗ 不是 1280 宽 —— 像素会糊(坑⑤)"
  [ "$bad" = "0" ] && echo "ALL OK — 工具可用" || { echo "FAILED: $bad 个槽位 pid 失效"; exit 1; }
  exit 0
fi

take_lock
read -r GX GY GW GH <<< "$(geom)"
P="$(pidof_slot "${2:-0}")"
case "$CMD" in
  shot)  $PS -Cmd focus -TargetPid "$P" >/dev/null 2>&1; sleep 0.35
         $PS -Cmd shot -X "$GX" -Y "$GY" -W "$GW" -H "$GH" -Out "C:/tmp/s$2.png" >/dev/null
         echo "shot p$2 -> C:/tmp/s$2.png" ;;
  click) $PS -Cmd click -X $(( GX + $3 )) -Y $(( GY + $4 )) -TargetPid "$P" ;;
  focus) $PS -Cmd focus -TargetPid "$P" ;;
  *) sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
