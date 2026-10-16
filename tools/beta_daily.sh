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

## ★模拟号必须跑【玩家手机上那个版本】的战斗代码(用户 2026-10-17「肯定要版本匹配啊」)。
##   观赛 / 回放是在手机上按手机的规则重算再比校验点; 版本号相同而战斗代码不同 ⇒ 第一处差异就对不上、画面停住。
##   发布版工作树 = tag(当前 v0.19.570) + 本仓库的 scripts/systems/sim/(模拟号购物 / 布阵逻辑) + tools/sim60.sh。
##   发新版后要重建这棵树(git worktree add 新 tag → 拷 sim 目录与 sim60.sh → 拷 .godot 导入缓存)。
SIM60="${SIM_TREE:-/c/tmp/turtle-v570}/tools/sim60.sh"
if [ ! -f "$SIM60" ]; then echo "$(date -u +%FT%TZ) 发布版工作树不在($SIM60), 不跑 —— 不许退回用开发版代码跑"; exit 1; fi

DOW=${FORCE_DOW:-$(date -u +%u)}         # 1=周一 … 7=周日
case "$DOW" in
  2) BATCHES="1 2 3 4 5 6 7 8" ;;
  4) BATCHES="9 10 11 12"         # 用户 10-14「那就改为40个号吧，开始跑」: 只跑 p81~p120, p131~p140 本周四不跑
     ## 同一周只跑一次: 10-14 23:10 手动提前开跑了, 00:00 的定时任务看到标记就退出(否则同一批号跑两遍)
     WEEK_MARK="/c/tmp/turtle-sim60/thu-done-$(date -u +%G-W%V)"
     if [ -f "$WEEK_MARK" ]; then echo "$(date -u +%FT%TZ) 本周周四批次已跑过($WEEK_MARK), 不再跑"; exit 0; fi
     touch "$WEEK_MARK" ;;
  6) BATCHES="SAT" ;;
  7) BATCHES="SUN" ;;
  *) echo "$(date -u +%FT%TZ) 今天(星期 $DOW)不排模拟号, 不跑"; exit 0 ;;
esac

## ★周日决赛(用户 2026-10-12「周日也要跑」): 17:50 UTC 起「闯关赛打满 4 胜 = 进了决赛日」的号, 全部同时在线
##   (小组赛 18:00、冠军杯赛 20:00, 每轮备战 3 分钟; 不在线的号只能被快照代打 / 服务端兜底判, 没有录像)。
##   窗口打完不退(SIM_QUIT_WHEN_DONE 空): 驱动在备战窗里进商店买, 其余由 SimFinalsPilot 一轮一轮点开战; 23:30 UTC 统一关掉。
if [ "$BATCHES" = "SUN" ]; then
  ELIG=$(python - <<'PYEOF'
import json
out = []
for i in range(1, 141):
    try:
        d = json.load(open(rf'C:\tmp\turtle-sim60\p{i:02d}\Godot\app_userdata\斗龟场 实时版\savegame.json', encoding='utf-8'))
    except Exception:
        continue
    if int(d.get('gauntlet_wins', 0)) >= 4:
        out.append(str(i))
print(' '.join(out))
PYEOF
)
  echo "════ $(date -u +%FT%TZ) 周日决赛 · 进决赛日的槽位: ${ELIG:-无} · $(git -C "${SIM_TREE:-/c/tmp/turtle-v570}" describe --tags --always 2>/dev/null)(发布版工作树)"
  [ -z "$ELIG" ] && exit 0
  if [ -n "${DRY:-}" ]; then echo "[DRY] SIM_QUIT_WHEN_DONE= SLOTS=\"$ELIG\" sim60.sh start"; exit 0; fi
  SIM_QUIT_WHEN_DONE="" SLOTS="$ELIG" bash "$SIM60" start 1
  until [ "$((10#$(date -u +%H%M)))" -ge 2330 ]; do sleep 300; done
  echo "$(date -u +%T)Z 决赛日收工, 关掉全部窗口"
  bash "$SIM60" stop
  for s in $ELIG; do bash "$SIM60" status 2>/dev/null | awk -v p="$(printf 'p%02d' "$s")" '$1==p'; done
  echo "════ $(date -u +%FT%TZ) 周日结束"
  exit 0
fi

## ★周六闯关赛(用户 2026-10-12「周六我们这样，0点跑部分，早上9点跑部分，中午12点后每一小时跑部分直到下午6点」):
##   只起「积分赛已晋级、闯关赛还没打完(<4 胜且 <3 负)」的号; 按 (槽位-1) mod 17 分成 17 组(10-17 改, 见下方 case),
##   UTC 00~16 点(英国 01~17 点)每小时一组, 每组一次 ≤10 个窗口, 打到底(闯关赛 23:00 截止)。
if [ "$BATCHES" = "SAT" ]; then
  HOUR=$((10#${FORCE_HOUR:-$(date -u +%H)}))
  case "$HOUR" in
    ## 用户 2026-10-17「从1点到17点，每小时跑一些」(英国夏令时) = UTC 00~16 点, 共 17 组, 原 9 组排法作废
    [0-9]|1[0-6]) G=$HOUR ;;
    *) echo "$(date -u +%FT%TZ) 周六 ${HOUR} 点不是排定时段, 不跑"; exit 0 ;;
  esac
  ELIG=$(python - "$G" <<'PYEOF'
import json, sys, re
g = int(sys.argv[1])
## ★晋级线照游戏自己的判据算(GameState.gauntlet_line_reached: 胜场 >= PROMOTE_WINS 且没出局)。
##   存档里的 promoted 要等积分赛收盘后号第一次开游戏才写入 ⇒ 周六第一批之前全是 false(10-16 实测 140/140),
##   只认它的话 9 组一个号都起不来。PROMOTE_WINS = RANKED_QUOTA - (HEARTS_MAX - 1), 从配置文件读, 不另抄数字。
_cfg = open(r'scripts/gamedata/phase2_config.gd', encoding='utf-8').read()
PW = int(re.search(r'const RANKED_QUOTA := (\d+)', _cfg).group(1)) - (int(re.search(r'const HEARTS_MAX := (\d+)', _cfg).group(1)) - 1)
out = []
for i in range(1, 141):
    if (i - 1) % 17 != g:
        continue
    try:
        d = json.load(open(rf'C:\tmp\turtle-sim60\p{i:02d}\Godot\app_userdata\斗龟场 实时版\savegame.json', encoding='utf-8'))
    except Exception:
        continue
    line = d.get('promoted') or (int(d.get('season_wins', 0)) >= PW and int(d.get('hearts', 1)) > 0)
    if line and int(d.get('gauntlet_wins', 0)) < 4 and int(d.get('gauntlet_losses', 0)) < 3:
        out.append(str(i))
print(' '.join(out))
PYEOF
)
  echo "════ $(date -u +%FT%TZ) 周六第 $((G+1))/17 组 · 晋级且没打完的槽位: ${ELIG:-无} · $(git -C "${SIM_TREE:-/c/tmp/turtle-v570}" describe --tags --always 2>/dev/null)(发布版工作树)"
  set -- $ELIG
  while [ $# -gt 0 ]; do
    CHUNK=""
    for _k in 1 2 3 4 5 6 7 8 9 10; do [ $# -gt 0 ] && { CHUNK="$CHUNK $1"; shift; }; done
    if [ -n "${DRY:-}" ]; then echo "[DRY] SLOTS=\"$CHUNK\" sim60.sh start"; continue; fi
    SLOTS="$CHUNK" bash "$SIM60" start 1
    t0=$(date +%s)
    while :; do
      left=0
      for s in $CHUNK; do [ -n "$(bash "$SIM60" status 2>/dev/null | awk -v p="$(printf 'p%02d' "$s")" '$1==p && $2!="-"')" ] && left=$((left+1)); done
      [ "$left" -eq 0 ] && break
      if [ $(( $(date +%s) - t0 )) -ge 5400 ] || [ "$((10#$(date -u +%H%M)))" -ge 2240 ]; then
        echo "$(date -u +%T)Z 超时或到收工时间, 关掉剩下 $left 个"; bash "$SIM60" stop; break
      fi
      sleep 60
    done
    for s in $CHUNK; do bash "$SIM60" status 2>/dev/null | awk -v p="$(printf 'p%02d' "$s")" '$1==p'; done
  done
  echo "════ $(date -u +%FT%TZ) 周六本组结束"
  exit 0
fi
ROUNDS=""                   # 不设上限: 打到被拦
STOP_AT=${STOP_AT:-2240}    # UTC HHMM: 到点不再起新批, 在跑的关掉(22:50 封盘); 手动提前开跑时可用环境变量覆盖
BATCH_CAP=5400              # 一批最多等 90 分钟, 超时关掉这一批(实测一批 45~50 分钟)

echo "════ $(date -u +%FT%TZ) 开跑 · 星期 $DOW · 批次 $BATCHES · 每号打到被拦 · 版本 $(grep -o 'config/version="[^"]*"' project.godot) · $(git -C "${SIM_TREE:-/c/tmp/turtle-v570}" describe --tags --always 2>/dev/null)(发布版工作树)"
for b in $BATCHES; do
  now=$(date -u +%H%M)
  if [ "$((10#$now))" -ge "$STOP_AT" ]; then
    echo "$(date -u +%T)Z 已到 ${STOP_AT} UTC, 第 $b 批起不再跑"; break
  fi
  if [ -n "${DRY:-}" ]; then
    echo "[DRY] SIM_ROUNDS=$ROUNDS bash "$SIM60" start $b && wait $b"; continue
  fi
  SIM_ROUNDS="$ROUNDS" bash "$SIM60" start "$b"
  ## 等这一批退出; 超时或撞上收工时间就关掉
  t0=$(date +%s)
  while :; do
    left=$(bash "$SIM60" status "$b" 2>/dev/null | awk 'NR>1 && $2 != "-"' | wc -l)
    [ "$left" -eq 0 ] && { echo "$(date -u +%T)Z 第 $b 批全部退出"; break; }
    if [ $(( $(date +%s) - t0 )) -ge "$BATCH_CAP" ] || [ "$((10#$(date -u +%H%M)))" -ge "$STOP_AT" ]; then
      echo "$(date -u +%T)Z 第 $b 批超时或到收工时间, 关掉剩下 $left 个"; bash "$SIM60" stop; break
    fi
    sleep 60
  done
  bash "$SIM60" status "$b"
  bash "$SIM60" scan "$b" | tail -25
done
echo "════ $(date -u +%FT%TZ) 今日结束"
