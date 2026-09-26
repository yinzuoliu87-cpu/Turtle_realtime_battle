#!/usr/bin/env bash
# tools/sim10.sh —— 10 个玩家同机模拟: 起 N 个独立窗口 / 关掉 / 看状态
#
# ══════════════════════════════════════════════════════════════════════
#  用户 2026-09-26:「你试着创建10个简单邮箱，然后准备10个窗口，下一周我们模拟跑一遍看有什么问题」
# ══════════════════════════════════════════════════════════════════════
#
# ★★★为什么必须一窗一个 APPDATA
#   Godot 的 `user://` 在 Windows 上解析到 `%APPDATA%/Godot/app_userdata/<项目名>`。
#   十个窗口共用一个 APPDATA ⇒ **共用同一份存档 + 同一个 ghost 池 + 同一个账号**,
#   那不是 10 个玩家, 是 10 个窗口在互相踩。
#   (这条不是推测: 2026-09-23 门禁并行跑时就是这么串味的 —— 332 个进程共用一个目录,
#    当场照出三条一直靠运气绿的竞态。CLAUDE.md §2 记着。)
#   ⇒ 每个槽位一个目录: $SIM_ROOT/p01 … p10
#
# ★★★为什么必须绑邮箱(不是可选)
#   `phase2_config.login_wall_on(后端已配, account_email)` —— 后端配着而邮箱为空就**挡住**,
#   一局都开不了。所以 10 个槽位各要一个邮箱。
#
# ★★★邮箱用 Gmail 的 `+` 别名, 不用真去注册 10 个
#   `turtlesupport32+t01@gmail.com` … `+t10@gmail.com`
#   · Gmail 把 `+` 后缀的信全投到 turtlesupport32@gmail.com **同一个收件箱**
#   · Supabase 把每个别名当**全新地址** ⇒ 不撞 email_exists
#   这条做法 `tools/probe_email_e2e.py` 已经用过并跑通(2026-09-22 首跑全链路)。
#
# ★★线上邮件限流(2026-09-26 从 Management API 读的真值, 不是估的)
#   · smtp_max_frequency = 60   ⇒ 两封验证码之间至少隔 60 秒
#   · mailer_otp_exp    = 3600  ⇒ 码 1 小时内有效
#   · rate_limit_email_sent = 30/小时, rate_limit_anonymous_users = 30/小时 ⇒ 10 个够用
#   ⇒ **建议流程**: 十个窗口挨个填邮箱点发送(每个间隔 ≥60 秒), 全发完再统一去收件箱
#     读码、统一回填 —— 码有一小时, 不用发一个读一个。
#
# 跑法:
#   bash tools/sim10.sh start [N]     # 起 N 个窗口(默认 10)
#   bash tools/sim10.sh stop          # 只关本脚本起的那些(**不用 taskkill /IM**)
#   bash tools/sim10.sh status        # 每个槽位: 进程活着吗 / 账号 / 邮箱 / 场次
#   bash tools/sim10.sh mails [N]     # 打印槽位 ↔ 邮箱 ↔ 昵称对照表
#   bash tools/sim10.sh focus <n>     # 把第 n 个窗口提到最前(十个标题一样, 靠它认)
#   bash tools/sim10.sh reset [N]     # ★清掉槽位存档(重新来一遍绑定); 会先问
set -u

GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ROOT="${SIM_ROOT:-/c/tmp/turtle-sim10}"
PIDFILE="$SIM_ROOT/pids.txt"
MAIL_BASE="${MAIL_BASE:-turtlesupport32}"
MAIL_DOMAIN="${MAIL_DOMAIN:-gmail.com}"

# ══════════════════════════════════════════════════════════════════════
#  窗口布局: **实测出来的**, 不是按 --resolution 想当然
# ══════════════════════════════════════════════════════════════════════
# ★★★`--resolution 460x258` 给出去, 实际窗口是 **656x399** —— Godot 有最小窗口尺寸,
#   小于它的请求被顶上去。这是 GetWindowRect 量的(10 个窗口全是 656x399), 不是估的。
#   ⇒ 1920x1080 上最多排得下 **2 列 × 2 行 = 4 个**不重叠。**10 个必然重叠。**
#
# ★所以改成「左上角错开」: 步距 < 窗口宽高, 每个窗口露出左上角一条
#   421x315 的可视区(够看清整个界面), 而且**每个标题栏都露着、都点得到**。
#   4 列: 左边界 0/421/842/1263, 最右一个 1263+656=1919 ✓ 正好不出屏
#   3 行: 上边界 0/315/630,      最下一个 630+399=1029 ✓ 正好在任务栏之上
#
# ★★十个窗口**标题完全一样**(都叫「斗龟场 实时版」), 光看标题分不出哪个是 p03。
#   ⇒ 用 `bash tools/sim10.sh focus 3` 把 p03 提到最前; 位置本身也是身份(见下面的地图)。
COLS=4
WIN_W=460
WIN_H=258
PITCH_X=421
PITCH_Y=315

N_DEFAULT=10

slot_dir() { printf "%s/p%02d" "$SIM_ROOT" "$1"; }
slot_mail() { printf "%s+t%02d@%s" "$MAIL_BASE" "$1" "$MAIL_DOMAIN"; }

# 存档路径。★项目名带空格("斗龟场 实时版"), 所以到处都要加引号。
slot_save() { printf "%s/Godot/app_userdata/斗龟场 实时版/savegame.json" "$(slot_dir "$1")"; }

usage() {
  sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

cmd_mails() {
  local n="${1:-$N_DEFAULT}" i
  echo "槽位 ↔ 邮箱(Gmail + 别名, 全部投到 ${MAIL_BASE}@${MAIL_DOMAIN} 同一个收件箱):"
  for i in $(seq 1 "$n"); do
    printf "  p%02d   %s\n" "$i" "$(slot_mail "$i")"
  done
  echo ""
  echo "昵称建议(登录墙第一格「你的名字」, 排行榜与对阵图上显示的就是它):"
  for i in $(seq 1 "$n"); do printf "  p%02d   测试%02d\n" "$i" "$i"; done
  echo ""
  echo "★发码节奏: 两封之间 ≥60 秒(smtp_max_frequency=60); 码 1 小时内有效(mailer_otp_exp=3600)。"
  echo "  ⇒ 十个窗口挨个填邮箱点发送, 全发完再统一读码回填。"
}

cmd_start() {
  local n="${1:-$N_DEFAULT}" i
  if [ ! -f "$GODOT" ]; then
    echo "★找不到 Godot: $GODOT   (用 GODOT=<路径> 覆盖)"; exit 1
  fi
  mkdir -p "$SIM_ROOT"
  : > "$PIDFILE"
  echo "起 $n 个窗口 · 每个独立存档 · 静音 · 4 列网格"
  echo "  项目: $PROJ_DIR"
  echo "  存档根: $SIM_ROOT"
  for i in $(seq 1 "$n"); do
    local d x y
    d="$(slot_dir "$i")"
    mkdir -p "$d"
    x=$(( ( (i - 1) % COLS ) * PITCH_X ))
    y=$(( ( (i - 1) / COLS ) * PITCH_Y ))
    # ★用 PowerShell 的 Start-Process 起 —— 直接 `&` 起的进程会跟着这个 shell 一起被收掉
    #   (memory fb-vfxlab-window-must-be-muted 里同一个坑)。
    # ★--audio-driver Dummy: 十个窗口同时出声没法用。
    # ★SHIP=1: 关掉 demo 劫持 —— 不带的话假人永不死、战斗永不结束(CLAUDE.md §4)。
    APPDATA="$d" SHIP=1 powershell -NoProfile -Command "
      \$env:APPDATA='$(cygpath -w "$d" 2>/dev/null || echo "$d")';
      \$env:SHIP='1';
      \$p = Start-Process -FilePath '$(cygpath -w "$GODOT" 2>/dev/null || echo "$GODOT")' \
        -ArgumentList '--path','$(cygpath -w "$PROJ_DIR" 2>/dev/null || echo "$PROJ_DIR")', \
                      '--audio-driver','Dummy', \
                      '--resolution','${WIN_W}x${WIN_H}','--position','$x,$y' \
        -PassThru;
      Write-Output \$p.Id" 2>/dev/null | tr -d '\r' | while read -r pid; do
        case "$pid" in
          [0-9]*) printf "%d %s\n" "$i" "$pid" >> "$PIDFILE"
                  printf "  p%02d  pid=%-7s 位置=(%4d,%4d)  邮箱=%s\n" "$i" "$pid" "$x" "$y" "$(slot_mail "$i")" ;;
        esac
      done
    sleep 2      # 错开启动 —— 十个 Godot 同时初始化渲染会互相拖慢
  done
  echo ""
  printf "★位置就是身份(十个窗口标题一样): 左上角起, 从左到右、从上到下 = p01…p%02d
" "$n"
  echo "  要把某一个提到最前: bash tools/sim10.sh focus <槽位号>"
  echo ""
  echo "★下一步(每个窗口): 登录墙里填上面那个邮箱 → 发送 → 等 ≥60 秒再做下一个窗口"
  echo "  全发完后去 ${MAIL_BASE}@${MAIL_DOMAIN} 读 10 个码, 再逐个回填。"
  echo "  关掉: bash tools/sim10.sh stop"
}

cmd_stop() {
  if [ ! -f "$PIDFILE" ]; then echo "没有 $PIDFILE, 没什么可关的"; exit 0; fi
  local n=0
  while read -r slot pid; do
    case "$pid" in
      [0-9]*) if powershell -NoProfile -Command "Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; if (\$?) { 'ok' }" 2>/dev/null | grep -q ok; then
                n=$((n+1)); printf "  关掉 p%s (pid=%s)\n" "$slot" "$pid"
              fi ;;
    esac
  done < "$PIDFILE"
  echo "共关掉 $n 个。★只关本脚本记下的 pid —— 不用 taskkill /IM, 那会连你自己开的 Godot 一起杀。"
  : > "$PIDFILE"
}

cmd_status() {
  local n="${1:-$N_DEFAULT}" i
  printf "%-5s %-9s %-40s %-34s %s\n" "槽位" "进程" "账号 id" "邮箱" "本周场次/胜场/命"
  for i in $(seq 1 "$n"); do
    local pid="-" alive="-" sv
    if [ -f "$PIDFILE" ]; then
      pid="$(awk -v s="$i" '$1==s {print $2}' "$PIDFILE" | tail -1)"
      [ -z "$pid" ] && pid="-"
    fi
    if [ "$pid" != "-" ]; then
      if powershell -NoProfile -Command "if (Get-Process -Id $pid -ErrorAction SilentlyContinue) { 'y' }" 2>/dev/null | grep -q y; then
        alive="活着"
      else
        alive="已退出"
      fi
    fi
    sv="$(slot_save "$i")"
    if [ -f "$sv" ]; then
      python - "$sv" <<'PY'
import io, json, sys
p = sys.argv[1]
try:
    d = json.load(io.open(p, encoding="utf-8"))
except Exception as e:
    print("  <读不出: %s>" % e); raise SystemExit
print("%-40s %-34s %s/%s/%s" % (
    str(d.get("account_id", ""))[:38] or "<未建号>",
    str(d.get("account_email", "")) or "<未绑定>",
    d.get("season_total_battles", "?"), d.get("season_wins", "?"), d.get("hearts", "?")))
PY
    else
      printf "%-40s %-34s %s\n" "<还没存档>" "-" "-"
    fi | sed "s/^/$(printf '%-5s %-9s ' "p$(printf '%02d' "$i")" "$alive")/"
  done
}

## 把某个槽位的窗口提到最前 —— 十个窗口标题一模一样, 没有这个就只能靠位置猜。
cmd_focus() {
  local i="${1:-}" pid
  case "$i" in ''|*[!0-9]*) echo "用法: bash tools/sim10.sh focus <槽位号 1..10>"; exit 1;; esac
  [ -f "$PIDFILE" ] || { echo "没有 $PIDFILE —— 先 start"; exit 1; }
  pid="$(awk -v s="$((10#$i))" '$1==s {print $2}' "$PIDFILE" | tail -1)"
  [ -n "$pid" ] || { echo "槽位 p$i 没有记录的 pid"; exit 1; }
  powershell -NoProfile -Command "
    Add-Type @'
using System;using System.Runtime.InteropServices;
public class F {
  [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h, int n);
}
'@
    \$p = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if (\$p) { [void][F]::ShowWindow(\$p.MainWindowHandle, 9); [void][F]::SetForegroundWindow(\$p.MainWindowHandle); 'ok' }
    else { 'gone' }" 2>/dev/null | tr -d '\r' | while read -r r; do
      case "$r" in
        ok)   printf "  p%02d (pid=%s) 已提到最前\n" "$((10#$i))" "$pid" ;;
        gone) printf "  p%02d (pid=%s) 进程已经不在了\n" "$((10#$i))" "$pid" ;;
      esac
    done
}


cmd_reset() {
  local n="${1:-$N_DEFAULT}"
  echo "★这会删掉 $SIM_ROOT 下 p01..p$(printf '%02d' "$n") 的**全部存档**(账号/邮箱绑定/进度都没了)。"
  echo "  邮箱别名本身是 Supabase 上的账号, 删存档之后那些邮箱**不能再绑第二次**"
  echo "  (会撞 email_exists) ⇒ 重来要换一批别名, 比如 MAIL_BASE 不变但 +t11..+t20。"
  printf "  确定? 打 yes 回车: "
  read -r ans
  [ "$ans" = "yes" ] || { echo "取消"; exit 0; }
  local i
  for i in $(seq 1 "$n"); do rm -rf "$(slot_dir "$i")"; done
  : > "$PIDFILE" 2>/dev/null || true
  echo "已清。"
}

case "${1:-}" in
  start)  cmd_start "${2:-}" ;;
  stop)   cmd_stop ;;
  status) cmd_status "${2:-}" ;;
  mails)  cmd_mails "${2:-}" ;;
  focus)  cmd_focus "${2:-}" ;;
  reset)  cmd_reset "${2:-}" ;;
  *)      usage ;;
esac
