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
# ★★★2026-09-29 起【默认走游客, 不用邮箱】 —— 上面那条理由已经作废
#   原文写的是「为什么必须绑邮箱(不是可选)」: 因为 `login_wall_on()` 后端配着而邮箱为空就挡住,
#   一局都开不了。**那堵墙 2026-09-29 拆了**(用户「那就不用必须绑定吧」, `WALL_BLOCKS := false`)。
#
#   ★查实过的三道闸(别再重查, 但复核便宜):
#     · 排位/报名/看桶/周赛事/传鬼魂 → 「服务端认得出你是谁」⇒ **匿名号就够**
#     · 云存档同步 → `sync_allowed() = id!="" and email!="" and token!=""` ⇒ 这条才要邮箱
#   ⇒ 十个槽位**要的是能打排位**, 不是要云存档 ⇒ **游客足够**, 省掉发码/限流/回填一整套。
#
#   MODE=mail 仍然保留(要验绑定流程本身时用), 下面那套 + 别名的办法照旧有效。
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
#   bash tools/sim10.sh start [N]     # 起 N 个窗口(默认 10) · 默认游客, 跨两块屏
#   AUTOPILOT=1 bash tools/sim10.sh start 10   # ★自动驾驶: 自己选技能/打/每轮买装备
#   MODE=mail bash tools/sim10.sh mails 10     # 要验绑定流程时才用邮箱那套
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
# ★★★2026-09-29 二改: 窗口尺寸必须是设计分辨率的【整数分之一】, 否则像素画糊。
#   用户当场看出来:「这个像素跟糊的一样」。查实:
#     · 设置本身是对的 —— default_texture_filter=0(Nearest) / stretch=canvas_items
#     · 真机 iPhone 横屏视口 1560x720 对基准 1280x720, 缩放因子**正好 1.0** ⇒ 1:1 清晰
#     · 而我把窗口开成 624x351 ⇒ 因子 0.4875, **非整数倍缩小像素画必糊**。是我的错不是产品的。
#   ⇒ 一律用 640x360 = **正好 1/2**。3 列 x 640 = 1920 严丝合缝铺满主屏宽; 2 行 x 360 = 720。
#   ⚠ 想更清楚就少开几个窗口用 1280x720(1:1), 屏幕只放得下 2 个。清晰度和窗口数是**换的**。
#
# ★★2026-09-29 改成【跨两块屏】—— 用户「我有两块屏你都可以用」。
#   实测(System.Windows.Forms.Screen): DISPLAY2 1920x1080 @(0,0) 主屏 / DISPLAY1 1707x1067 @(1920,0)
#   ⇒ 桌面总宽 3627。**不让任何窗口跨屏边界 1920**(骑在两块屏中间没法看)。
#   主屏 6 个(3 列 x 2 行, 格 640x540), 副屏 4 个(2 列 x 2 行, 格 853x533), 窗口按 16:9 塞进格子。
# ★★★2026-09-29 三改: 【叠放】而不是平铺 —— 用户「就是太糊了啊，这窗口」「叠放不行吗」。
#   平铺的代价是缩放: 10 个窗口摆得下就只能 640x360(0.5 倍)甚至更小, 而副屏 150% 缩放
#   还会变成 0.75 倍 —— **非整数倍缩小像素画必糊**, 这是物理上躲不掉的。
#   ⇒ 叠放, 每个窗口都开**原生 1280x720 = 1:1**, 像素彻底清晰。
#   反正鼠标一次只能操作一个窗口, 平铺看得见十个但十个都糊, 不如一个清楚的。
#   ★全部放【主屏】(1920x1080, 100% 缩放) —— 副屏 150% 会把 1280x720 撑成 1920x1080 放不下。
#   ★十个窗口同一个位置, 靠 **pid** 区分(pids.txt 记的是真 pid, 已修), 不靠位置。
STACK_X=320
STACK_Y=100
WIN_CW=1280
WIN_CH=720

slot_geom() {
  printf "%d %d %d %d" "$STACK_X" "$STACK_Y" "$WIN_CW" "$WIN_CH"
}

# 旧的单屏 4 列摆位(SIM_LAYOUT=grid1 可回到它)
COLS=4
WIN_W=460
WIN_H=258
PITCH_X=421
PITCH_Y=315

# 槽位 → 位置与尺寸。回显 "x y w h"。

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
    local d x y w h
    d="$(slot_dir "$i")"
    mkdir -p "$d"
    read -r x y w h <<< "$(slot_geom "$i")"
    WIN_W="$w"; WIN_H="$h"
    # ★用 PowerShell 的 Start-Process 起 —— 直接 `&` 起的进程会跟着这个 shell 一起被收掉
    #   (memory fb-vfxlab-window-must-be-muted 里同一个坑)。
    # ★--audio-driver Dummy: 十个窗口同时出声没法用。
    # ★SHIP=1: 关掉 demo 劫持 —— 不带的话假人永不死、战斗永不结束(CLAUDE.md §4)。
    APPDATA="$d" SHIP=1 powershell -NoProfile -Command "
      \$env:APPDATA='$(cygpath -w "$d" 2>/dev/null || echo "$d")';
      \$env:SHIP='1';
      ## ★自动驾驶(选技能/打/每轮买装备)。AUTOPILOT=1 bash tools/sim10.sh start 10
      ##   不带就是普通实例, 人自己玩 —— 默认必须彻底关掉, 这是它的硬约束之一。
      if ('${AUTOPILOT:-}' -ne '') { \$env:SIM_AUTOPILOT='1' };
      \$p = Start-Process -FilePath '$(cygpath -w "$GODOT" 2>/dev/null || echo "$GODOT")' \
        -ArgumentList '--path','$(cygpath -w "$PROJ_DIR" 2>/dev/null || echo "$PROJ_DIR")', \
                      '--audio-driver','Dummy', \
                      '--resolution','${WIN_W}x${WIN_H}','--position','$x,$y' \
        -PassThru;
      ## ★★别用 Start-Process 回的那个 Id —— Godot 起来之后**换进程**, 那个 Id 很快就不存在了,
      ##   于是 focus/click 全部找不到窗口(2026-09-29 实测: 记的 42608 已不在, 窗口在 47464 手里)。
      ##   ⇒ 等它把真进程拉起来, 取**带窗口的、最新的那个 Godot 进程**。
      Start-Sleep -Milliseconds 2500;
      \$g = Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue |
            Where-Object { \$_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime -Descending | Select-Object -First 1;
      if (\$null -ne \$g) { Write-Output \$g.Id } else { Write-Output \$p.Id }" 2>/dev/null | tr -d '\r' | while read -r pid; do
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
  echo "★下一步: 什么都不用做 —— 2026-09-29 起【默认游客】, 墙已拆, 全新安装直接进教学的选龟屏。
  (要验绑定流程本身才走邮箱: MODE=mail, 填上面那个邮箱 → 发送 → 等 ≥60 秒再做下一个窗口"
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
