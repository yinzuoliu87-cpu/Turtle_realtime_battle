#!/usr/bin/env bash
# tools/beta_daily.sh —— 内测周每天自动跑一轮 120 个模拟选手。由 Windows 计划任务「TurtleSimDaily」在周二、周四 01:00(英国夏令时 = 00:00 UTC) 起。
#
# 用户 2026-10-06:「下周你这里要准备大概120个选手装作玩家来战斗」; 10-12「我们不是也排了120个账号吧」。
# 排法(用户 2026-10-12 改):「周二0点开始跑80个号，周四跑40个号，周三不要跑因为我有重要东西要做」
#   周二 00:00 UTC 起 p01~p80(第 1~8 批); 周四 00:00 UTC 起 p81~p120(第 9~12 批); 每号打到被拦(没命出局或 16 场打满)。
#   其余日子不跑。22:40 UTC 前收工(积分赛 22:50 起封盘)。
# 一次只跑一批 10 个(机器蓝屏史)。开窗口跑(用户 2026-10-12「内测得话别用无头模式」): 窗口叠在右屏、静音、不抢焦点(sim60.sh 默认)。
#
# 跑法:  bash tools/beta_daily.sh            # 按今天星期几自动定局数
#        DRY=1 bash tools/beta_daily.sh      # 只打印要做什么, 不起进程
set -u
cd "$(dirname "$0")/.."

ROOT=/c/tmp/turtle-sim60
LOG="$ROOT/daily-$(date -u +%Y%m%d).log"
mkdir -p "$ROOT"
exec >>"$LOG" 2>&1

DOW=${FORCE_DOW:-$(date -u +%u)}         # 1=周一 … 7=周日
case "$DOW" in
  2) BATCHES="1 2 3 4 5 6 7 8" ;;
  4) BATCHES="9 10 11 12" ;;
  *) echo "$(date -u +%FT%TZ) 今天(星期 $DOW)不排模拟号, 不跑"; exit 0 ;;
esac
ROUNDS=""                   # 不设上限: 打到被拦
STOP_AT=2240                # UTC HHMM: 到点不再起新批, 在跑的关掉(22:50 封盘)
BATCH_CAP=5400              # 一批最多等 90 分钟, 超时关掉这一批(实测一批 45~50 分钟)

echo "════ $(date -u +%FT%TZ) 开跑 · 星期 $DOW · 批次 $BATCHES · 每号打到被拦 · 版本 $(grep -o 'config/version="[^"]*"' project.godot) · $(git rev-parse --short HEAD)"
for b in $BATCHES; do
  now=$(date -u +%H%M)
  if [ "$((10#$now))" -ge "$STOP_AT" ]; then
    echo "$(date -u +%T)Z 已到 ${STOP_AT} UTC, 第 $b 批起不再跑"; break
  fi
  if [ -n "${DRY:-}" ]; then
    echo "[DRY] SIM_ROUNDS=$ROUNDS bash tools/sim60.sh start $b && wait $b"; continue
  fi
  SIM_ROUNDS="$ROUNDS" bash tools/sim60.sh start "$b"
  ## 等这一批退出; 超时或撞上收工时间就关掉
  t0=$(date +%s)
  while :; do
    left=$(bash tools/sim60.sh status "$b" 2>/dev/null | awk 'NR>1 && $2 != "-"' | wc -l)
    [ "$left" -eq 0 ] && { echo "$(date -u +%T)Z 第 $b 批全部退出"; break; }
    if [ $(( $(date +%s) - t0 )) -ge "$BATCH_CAP" ] || [ "$((10#$(date -u +%H%M)))" -ge "$STOP_AT" ]; then
      echo "$(date -u +%T)Z 第 $b 批超时或到收工时间, 关掉剩下 $left 个"; bash tools/sim60.sh stop; break
    fi
    sleep 60
  done
  bash tools/sim60.sh status "$b"
  bash tools/sim60.sh scan "$b" | tail -25
done
echo "════ $(date -u +%FT%TZ) 今日结束"
