#!/usr/bin/env bash
# server/deploy/deploy_version.sh —— 在裁判机上装一个客户端版本：裁判工程 + 陪练号工程 + 两个对手池 + 切陪练号。
#
# 方案书 docs/plans/20261102-文件管理与发版流程重整.md §4.2 P3；手册 server/referee/README.md「发版时」「常驻陪练号」「内测服第二套」；
# 用法与回退见同目录 README.md。平时由本机 `python tools/deploy.py <版本>` 上传、nohup 起、短命令轮询；也可以在机器上直接跑：
#
#   bash deploy_version.sh <prod|beta> <版本> <40 位 sha> [选项]
#
#   --dry-run              只做只读检查，把每一步要做的事打印出来，什么都不改
#   --skip-bots            不碰陪练号（工程 / env / 调度器）
#   --no-bots-switch       陪练号工程照装，但不改 env、不重启调度器（版本还没登记进 referee_versions 时用）
#   --no-pools             不生成 / 上传对手池
#   --no-drain             导入前不停陪练号（默认：touch <off 开关> 并等在跑的号退完 —— README「先停陪练号再 --import」）
#   --bots-drain-sec N     等陪练号退完最多几秒（默认 7800 = BOT_SESSION_CAP_SEC 7200 + 10 分钟）
#   --sim-overlay SHA      陪练号工程的 scripts/systems/sim/ 换成 SHA 那一版（README「常驻陪练号」第 1 步；默认关）
#   --allow-weekend        正式服周末（UTC 周六、周日）也照装（默认拒绝：周末是正式服高峰、调度器不认 off 开关）
#   --rules-ver N          期望的 RULES_VER（tools/deploy.py 从 tag 那一提交读出来传进来；装好后核对）
#   --expect-pools G,S,B   对手池应有行数（默认 2052,396,186 = 闯关机器人池 / 积分赛内置陪练 / 积分赛机器人）
#   --only pools           只重跑对手池 + 回读（工程已经在 <根>/v<版本>）
#   --only bots-switch     只切陪练号（改 env + 重启调度器 + 读进程环境确认）
#
# 流程（每一步不过就停；「切换」之前任何一步失败 = 线上什么都没变）：
#   preflight → lock → drain（停陪练号）→ ref-stage（暂存目录取 sha）→ ref-import ×2 → bots-stage（拷 + 导 ×2）
#   → ref-gates（两条一致性门禁并行，都要 ALL PASS）
#   → swap（原子 rename 进 <根>/v<版本>；已有同名目录先挪到 /opt/turtle-prev/）→ release-off（放开陪练号）
#   → pools（--bot-pool + 回读）→ bots-switch（改 BOT_GAME_DIR → 重启调度器 → /proc/<MainPID>/environ 确认）→ DEPLOY OK
#   （off 开关在换入之后才放：同版本重装时目标目录就是陪练号正在用的那个，放早了新起的号会占住它、换不进去。
#     本脚本自己 fail 时子进程都已退完 ⇒ 顺手删掉自己建的开关；被信号杀掉 / 意外退出时不删 —— README「别用 trap 自动删」）
#
# ★不做任何数据库写：登记 referee_versions、改 finals_version 只打印 SQL 给人（正式服写入要用户点头）。
#   唯一碰数据库的是 `referee_poller.py --bot-pool`（README「发版时」第 4 步：生成并上传两个对手池，顺带把
#   referee_versions.rules_ver 写上 —— 只 update，行不存在时写不上）与 `--health`（只读 referee_backlog）。
# ★暂存 / 旧目录一律不放在 /opt/turtle*/ 下：referee_poller.py discover_versions 把那一层每个带 project.godot 的
#   子目录都当版本（点目录也算；同版本两份时用排序靠前的那个 —— 「.staging-…」会排在「v…」前面被拿去算局）。
# 最后一行固定是 `DEPLOY OK` / `DEPLOY OK (dry-run)` / `DEPLOY FAILED: <步骤>`；退出码 0 / 1。

set -uo pipefail
umask 022
export LC_ALL=C.UTF-8 PYTHONIOENCODING=utf-8
cd / || exit 1

# ─────────────────────────────── 输出 ───────────────────────────────
log()  { echo "$(date -u +%FT%TZ) $*"; }
STEP=args
step() { STEP=$1; echo; log "==== [$1] ${2:-}"; }
FINAL=0
DRY=0
CREATED_OFF=0      # off 开关是不是本脚本建的（是才由本脚本删）
OFF_RELEASED=0

release_off() {    # 本脚本建的 off 开关 ⇒ 删掉（陪练号恢复）；不是本脚本建的不动
  if [ "$CREATED_OFF" = 1 ] && [ "$OFF_RELEASED" = 0 ]; then
    rm -f "$BOTS_OFF" && log "已删 $BOTS_OFF（本脚本建的；陪练号恢复起号）"
    OFF_RELEASED=1
  fi
}

fail() {
  log "✗ $*"
  [ "$DRY" = 1 ] || release_off
  if [ -n "${STAGE:-}" ] && [ -d "${STAGE:-/nonexistent}" ] && [ "$DRY" = 0 ]; then
    log "暂存目录留着看：$STAGE${BSTAGE:+ / $BSTAGE}（看完 rm -rf；线上目录没动）"
  fi
  FINAL=1
  echo "DEPLOY FAILED: $STEP"
  exit 1
}

on_exit() {
  local rc=$?
  if [ "$FINAL" = 0 ]; then
    log "✗ 意外退出（rc=$rc）"
    if [ "$CREATED_OFF" = 1 ] && [ "$OFF_RELEASED" = 0 ]; then
      log "⚠ $BOTS_OFF 是本脚本建的、没删（可能还有导入进程在跑）：pgrep -fa '[g]odot.*--import' 为空、负载回落后手动 rm"
    fi
    echo "DEPLOY FAILED: $STEP"
  fi
}
trap on_exit EXIT
trap 'log "收到信号, 停"; exit 1' TERM INT HUP

# ─────────────────────────────── 参数 ───────────────────────────────
usage() { sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; }
[ $# -ge 3 ] || { usage; FINAL=1; echo "DEPLOY FAILED: args"; exit 1; }
ENVN=$1; VER=$2; SHA=$3; shift 3
SKIP_BOTS=0; NO_SWITCH=0; NO_POOLS=0; NO_DRAIN=0; DRAIN_SEC=7800; OVERLAY=""; ALLOW_WEEKEND=0
WANT_RV=""; EXPECT="2052,396,186"; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --skip-bots) SKIP_BOTS=1 ;;
    --no-bots-switch) NO_SWITCH=1 ;;
    --no-pools) NO_POOLS=1 ;;
    --no-drain) NO_DRAIN=1 ;;
    --bots-drain-sec) DRAIN_SEC=${2:-}; shift ;;
    --sim-overlay) OVERLAY=${2:-}; shift ;;
    --allow-weekend) ALLOW_WEEKEND=1 ;;
    --rules-ver) WANT_RV=${2:-}; shift ;;
    --expect-pools) EXPECT=${2:-}; shift ;;
    --only) ONLY=${2:-}; shift ;;
    *) fail "不认识的参数: $1" ;;
  esac
  shift
done

[[ "$ENVN" =~ ^(prod|beta)$ ]] || fail "环境只认 prod / beta: $ENVN"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版本号格式不对: $VER"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || fail "sha 要 40 位小写十六进制: $SHA"
[ -z "$OVERLAY" ] || [[ "$OVERLAY" =~ ^[0-9a-f]{40}$ ]] || fail "--sim-overlay 要 40 位 sha: $OVERLAY"
[[ "$DRAIN_SEC" =~ ^[0-9]+$ ]] || fail "--bots-drain-sec 要整数: $DRAIN_SEC"
[ -z "$WANT_RV" ] || [[ "$WANT_RV" =~ ^[0-9]+$ ]] || fail "--rules-ver 要整数: $WANT_RV"
[[ "$EXPECT" =~ ^[0-9]+,[0-9]+,[0-9]+$ ]] || fail "--expect-pools 要 G,S,B: $EXPECT"
[[ "$ONLY" =~ ^(|pools|bots-switch)$ ]] || fail "--only 只认 pools / bots-switch: $ONLY"
IFS=, read -r EXP_G EXP_S EXP_B <<< "$EXPECT"
SHORT=${SHA:0:8}

# ─────────────────────────────── 两套环境 ───────────────────────────────
U=turtle-referee
GODOT=/opt/godot/godot
GODOT_WANT=4.6.3
STAGE_ROOT=/opt/turtle-staging           # 与 /opt/turtle* 同一文件系统（preflight 核）⇒ rename 是原子的
PREV_ROOT=/opt/turtle-prev               # 被替换下来的旧目录（回退 = rename 回去）
LOCK=/run/lock/turtle-deploy.lock
TS=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR=/root/deploy/runs/$ENVN-v$VER-$SHORT-$TS     # 本次各 Godot 日志
BACKUP_DIR=/root/deploy/backup
WORK=/var/tmp/turtle-deploy/$ENVN-v$VER-$SHORT-$TS  # 导入 / 门禁用的 user://（turtle-referee 可写；跑完删）
MIN_DISK=$((3 * 1024 * 1024 * 1024))
MIN_MEM_KB=$((1024 * 1024))                         # 导入前可用内存至少 1 GiB（memory「同机留余量」）
case "$ENVN" in
  prod)
    REF_ROOT=/opt/turtle; REF_ENV=/etc/turtle-referee/env; POLLER=/opt/turtle/referee/referee_poller.py
    BOTS_ROOT=/opt/turtle-bots-prod; BOTS_ENV=/etc/turtle-referee/env-bots-prod; BOTS_OFF=/etc/turtle-referee/bots-prod-off
    PLANNER_UNIT=turtle-gauntlet-planner-prod ;;
  beta)
    REF_ROOT=/opt/turtle-beta; REF_ENV=/etc/turtle-referee/env-beta; POLLER=/opt/turtle-beta/referee/referee_poller.py
    BOTS_ROOT=/opt/turtle-bots-beta; BOTS_ENV=/etc/turtle-referee/env-bots-beta; BOTS_OFF=/etc/turtle-referee/bots-beta-off
    PLANNER_UNIT="" ;;            # 内测服没有调度器；runner 每次由 timer 新起、重读 env
esac
BOTS_PAT="[t]urtle-bots-$ENVN/v"         # 陪练客户端（包装脚本 + godot）命令行里都有 --path <BOTS_ROOT>/v…
DST=$REF_ROOT/v$VER
BDST=$BOTS_ROOT/v$VER
STAGE=""; BSTAGE=""
STAGE_NAME=$STAGE_ROOT/$ENVN-ref-v$VER-$SHORT
BSTAGE_NAME=$STAGE_ROOT/$ENVN-bots-v$VER-$SHORT

TR() { sudo -u "$U" "$@"; }
## 以 turtle-referee 身份、带上某份 env 跑命令；钥匙不上命令行（README「运维」那条：别用 env $(cat … | xargs)）
as_env() { local f=$1; shift; sudo -u "$U" bash -c 'set -a; . "$0"; set +a; exec "$@"' "$f" "$@"; }
## 改动类命令：dry-run 只打印
act() { if [ "$DRY" = 1 ]; then log "[dry-run] 会执行: $*"; return 0; fi; log "+ $*"; "$@"; }
re_escape() { printf '%s' "$1" | sed 's/[.[\*^$()+?{}|]/\\&/g'; }
head_of() { [ -f "$1/.git/HEAD" ] && tr -d '\n' < "$1/.git/HEAD" || echo "?"; }      # 不跑 git（root 在别人的仓库里会撞 safe.directory）
ver_of() { grep -m1 -oE '^config/version="[^"]+"' "$1/project.godot" 2>/dev/null | sed 's/.*="\(.*\)"/\1/'; }
rv_of() { grep -m1 -oE 'const RULES_VER *:?= *[0-9]+' "$1/scripts/gamedata/phase2_config.gd" 2>/dev/null | grep -oE '[0-9]+$'; }
bad_lines() { grep -c -E 'SCRIPT ERROR|Parse Error' "$1" 2>/dev/null || true; }
weekend_now() { [ "$(date -u +%u)" -ge 6 ]; }
latest_ver_dir() {  # <根> 下版本号最大、带 .git 的 v<x.y.z> 目录（v571 这类老目录名不算）
  local d best=""
  for d in $(ls -1d "$1"/v* 2>/dev/null | grep -E '/v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V); do [ -d "$d/.git" ] && best=$d; done
  echo "$best"
}
procs_on() { pgrep -fc -- "[-]-path $(re_escape "$1")( |\$)" || true; }   # 有多少进程在用这个工程目录

## 已登记且 enabled 的版本才出现在 referee_backlog().bot_pool 里 ⇒ 打印 "<rules_ver> <池行数>" / none / error（只读）
reg_status() {
  as_env "$REF_ENV" python3 "$POLLER" --health 2>/dev/null | python3 -c '
import json, sys
ver = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if line.startswith("{"):
        try:
            b = json.loads(line)
        except ValueError:
            break
        for p in b.get("bot_pool") or []:
            if str(p.get("client_version")) == ver:
                print("%s %s" % (p.get("rules_ver"), p.get("rows")))
                sys.exit(0)
        print("none")
        sys.exit(0)
print("error")' "$VER"
}

godot_import() {   # $1 目录 $2 日志 $3 user:// ；rc 原样返回
  TR env HOME="$WORK/home" XDG_DATA_HOME="$3" TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' \
    nice -n 10 timeout 1200 "$GODOT" --headless --audio-driver Dummy --path "$1" --import > "$2" 2>&1
}

import_twice() {   # $1 目录 $2 日志前缀 $3 user://；第二次 rc=0 且没有 SCRIPT ERROR / Parse Error 才算过（README：导两次、以第二次为准）
  local i rc
  for i in 1 2; do
    local t0=$SECONDS
    godot_import "$1" "$2$i.log" "$3"; rc=$?
    log "import #$i rc=$rc $((SECONDS - t0))s  ERROR 行=$(grep -c 'ERROR' "$2$i.log" || true)  SCRIPT ERROR/Parse Error=$(bad_lines "$2$i.log")"
  done
  [ "$rc" = 0 ] || return 1
  [ "$(bad_lines "$2"2.log)" = 0 ] || return 1
  return 0
}

swap_in() {        # $1 暂存 $2 目标 $3 旧目录挪去哪；原子 rename；目标在用就等（最多 15 分钟）
  local src=$1 dst=$2 prev=$3 n w=0
  if [ -e "$dst" ] && [ "$DRY" = 1 ]; then
    log "[dry-run] $dst 已存在、现在有 $(procs_on "$dst") 个进程在用 ⇒ 会等它们跑完（最多 900s）再换"
  fi
  if [ -e "$dst" ]; then
    while [ "$DRY" = 0 ]; do
      n=$(procs_on "$dst")
      [ "$n" = 0 ] && break
      [ $w -ge 900 ] && { log "目标 $dst 还有 $n 个进程在用（等了 ${w}s）"; return 1; }
      [ $((w % 60)) = 0 ] && log "等 $dst 上的 $n 个进程跑完（一局 ≤ 10 分钟）…"
      sleep 10; w=$((w + 10))
    done
    act mkdir -p "$PREV_ROOT" || return 1
    act mv -T "$dst" "$prev" || return 1
    if ! act mv -T "$src" "$dst"; then
      log "换入失败 ⇒ 把旧目录挪回去"
      act mv -T "$prev" "$dst"
      return 1
    fi
    log "旧目录 → $prev（回退: mv -T $dst <别处> && mv -T $prev $dst）"
  else
    act mv -T "$src" "$dst" || return 1
  fi
  [ "$DRY" = 1 ] && return 0
  [ "$(head_of "$dst")" = "$SHA" ] || { log "换入后 $dst HEAD=$(head_of "$dst") ≠ $SHA"; return 1; }
  log "换入 $dst  HEAD=$(head_of "$dst")  非 $U 属主文件 $(find "$dst" ! -user "$U" | wc -l) 个"
}

pools_and_readback() {
  step pools "生成并上传两个对手池（referee_poller.py --bot-pool --version $VER；README「发版时」第 4 步）"
  local rv=$RULES_VER
  if [ "$DRY" = 1 ]; then
    log "[dry-run] 会执行: as_env $REF_ENV nice -n 10 python3 $POLLER --bot-pool --version $VER > $RUN_DIR/pools.log"
    log "[dry-run] 然后核: 闯关机器人池 total=$EXP_G、积分赛 seed=$EXP_S / bot=$EXP_B、rules_ver=${rv:-?}；--health 里 $VER 的 rules_ver / rows"
    return 0
  fi
  as_env "$REF_ENV" nice -n 10 python3 "$POLLER" --bot-pool --version "$VER" > "$RUN_DIR/pools.log" 2>&1
  local rc=$?
  grep -v 'WARN .*没有 scenes/Referee.tscn' "$RUN_DIR/pools.log" | tail -n 20
  [ "$rc" = 0 ] || fail "referee_poller.py --bot-pool rc=$rc（日志 $RUN_DIR/pools.log）"
  python3 - "$VER" "$rv" "$EXP_G" "$EXP_S" "$EXP_B" "$RUN_DIR/pools.log" <<'PY' || fail "对手池回读对不上"
import json, re, sys
ver, rv, eg, es, eb, path = sys.argv[1:7]
txt = open(path, encoding="utf-8", errors="replace").read().splitlines()

def grab(prefix):
    for line in txt:
        if line.find(prefix + " " + ver + ":") >= 0 and "上传完" in line and "→" in line:
            m = re.search(r"rules_ver=(\d+)", line)
            return (m.group(1) if m else ""), json.loads(line.split("→", 1)[1].strip())
    return None, None

bad = []
r1, g = grab("bot-pool")
r2, k = grab("ranked-pool")
if g is None:
    bad.append("没找到 bot-pool %s 上传完那一行" % ver)
else:
    print("回读 闯关机器人池: rules_ver=%s total=%s（要 %s）" % (r1, g.get("total"), eg))
    if str(g.get("total")) != eg:
        bad.append("闯关机器人池 total=%s ≠ %s" % (g.get("total"), eg))
if k is None:
    bad.append("没找到 ranked-pool %s 上传完那一行（这一版工程没有 generate_ranked？）" % ver)
else:
    s, b = (k.get("seed") or {}).get("total"), (k.get("bot") or {}).get("total")
    print("回读 积分赛池: rules_ver=%s seed=%s（要 %s）bot=%s（要 %s）" % (r2, s, es, b, eb))
    if str(s) != es or str(b) != eb:
        bad.append("积分赛池 seed=%s bot=%s ≠ %s / %s" % (s, b, es, eb))
for r in (r1, r2):
    if rv and r is not None and r != rv:
        bad.append("池子 rules_ver=%s ≠ 工程 RULES_VER %s" % (r, rv))
for x in bad:
    print("✗ " + x)
sys.exit(1 if bad else 0)
PY
  local st; st=$(reg_status)
  case "$st" in
    none)  REGISTERED=0; log "referee_versions 里还没有 $VER（或 enabled=false）⇒ rules_ver 这次没写上（--bot-pool 只 update 不 insert）；登记时带上 rules_ver=$rv" ;;
    error) REGISTERED=""; log "⚠ --health 读不到（网络 / 钥匙）⇒ 登记状态不明" ;;
    *)     REGISTERED=1; set -- $st
           log "回读 --health: $VER 已登记 rules_ver=$1 闯关机器人池 rows=$2"
           [ "$1" = "$rv" ] || fail "referee_versions.rules_ver=$1 ≠ 工程 RULES_VER $rv"
           [ "$2" = "$EXP_G" ] || fail "--health 回读池行数 $2 ≠ $EXP_G" ;;
  esac
}

bots_switch() {
  step bots-switch "BOT_GAME_DIR → $BDST；${PLANNER_UNIT:-（内测服无调度器）} 重启并读进程环境确认"
  [ -d "$BDST" ] || { [ "$DRY" = 1 ] && log "[dry-run] $BDST 由本次装上"; } || fail "$BDST 不存在"
  if [ -d "$BDST" ]; then
    [ "$(ver_of "$BDST")" = "$VER" ] || fail "$BDST 的 project.godot 版本 $(ver_of "$BDST") ≠ $VER"
    [ "$DRY" = 1 ] || [ "$(head_of "$BDST")" = "$SHA" ] || fail "$BDST HEAD=$(head_of "$BDST") ≠ $SHA"
  fi
  if [ "$REGISTERED" != 1 ]; then
    local st; st=$(reg_status)
    case "$st" in none|error|"") ;; *) REGISTERED=1 ;; esac
    [ "$REGISTERED" = 1 ] || fail "referee_versions 里没有 $VER（--health: $st）⇒ 陪练号切过去会开不了积分赛；先登记再 --only bots-switch"
  fi
  local n; n=$(grep -c '^BOT_GAME_DIR=' "$BOTS_ENV" || true)
  [ "$n" = 1 ] || fail "$BOTS_ENV 里 BOT_GAME_DIR= 有 $n 行（要恰好 1 行）"
  local cur; cur=$(grep -m1 '^BOT_GAME_DIR=' "$BOTS_ENV" | cut -d= -f2-)
  log "env 现在 BOT_GAME_DIR=$cur"
  act mkdir -p "$BACKUP_DIR" || fail "建备份目录"
  local bak=$BACKUP_DIR/$(basename "$BOTS_ENV").bak-$TS
  act cp -a "$BOTS_ENV" "$bak" || fail "备份 env"
  act sed -i "s#^BOT_GAME_DIR=.*#BOT_GAME_DIR=$BDST#" "$BOTS_ENV" || fail "改 env"
  if [ "$DRY" = 0 ]; then
    [ "$(grep -m1 '^BOT_GAME_DIR=' "$BOTS_ENV" | cut -d= -f2-)" = "$BDST" ] || fail "改完 env 回读不对"
    log "env 回读 BOT_GAME_DIR=$BDST（备份 $bak）"
  fi
  if [ -z "$PLANNER_UNIT" ]; then
    log "内测服：runner 每次由 timer 新起、重读 env ⇒ 不用重启"
    return 0
  fi
  local old; old=$(systemctl show -p MainPID --value "$PLANNER_UNIT")
  act systemctl restart "$PLANNER_UNIT" || { [ "$DRY" = 1 ] || { cp -a "$bak" "$BOTS_ENV"; fail "systemctl restart $PLANNER_UNIT 失败（env 已还原）"; }; }
  if [ "$DRY" = 1 ]; then
    log "[dry-run] 然后核: $PLANNER_UNIT active、MainPID ≠ $old、/proc/<MainPID>/environ 里 BOT_GAME_DIR=$BDST"
    return 0
  fi
  local pid=0 i
  for i in $(seq 1 30); do
    pid=$(systemctl show -p MainPID --value "$PLANNER_UNIT")
    [ "$(systemctl is-active "$PLANNER_UNIT")" = active ] && [ "$pid" != 0 ] && [ "$pid" != "$old" ] && break
    sleep 1
  done
  local got; got=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -m1 '^BOT_GAME_DIR=' | cut -d= -f2-)
  log "$PLANNER_UNIT: MainPID $old → $pid  is-active=$(systemctl is-active "$PLANNER_UNIT")  进程环境 BOT_GAME_DIR=$got"
  if [ "$got" != "$BDST" ]; then
    cp -a "$bak" "$BOTS_ENV"; systemctl restart "$PLANNER_UNIT"
    fail "调度器进程环境 BOT_GAME_DIR=$got ≠ $BDST（env 已还原并重启）"
  fi
}

print_next_steps() {
  echo
  log "==== 剩下要人做的（$ENVN 库；正式服写入要用户点头；本脚本不写库）"
  local rv=${RULES_VER:-<RULES_VER>}
  if [ "${REGISTERED:-}" != 1 ]; then
    echo "  · 登记版本："
    echo "      insert into public.referee_versions (client_version, rules_ver) values ('$VER', $rv)"
    echo "        on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;"
    [ "$SKIP_BOTS" = 1 ] || echo "    登记后切陪练号: python tools/deploy.py $VER --env $ENVN --only bots-switch"
  fi
  echo "  · 周日用的版本（非周日才改；= 当周锁定的客户端版本，必须已登记且 enabled；现值看 tools/deploy.py 的回读）："
  echo "      update public.referee_config set finals_version = '$VER', updated_at = now() where id = 1;"
  echo "  · 旧版本任务清空后再删旧目录、update referee_versions set enabled = false（server/referee/README.md「发版时」第 5 步）"
}

# ═══════════════════════════════ 开始 ═══════════════════════════════
log "deploy_version.sh env=$ENVN ver=$VER sha=$SHA dry=$DRY only=${ONLY:-全流程} skip_bots=$SKIP_BOTS no_switch=$NO_SWITCH no_pools=$NO_POOLS no_drain=$NO_DRAIN overlay=${OVERLAY:-关}"
REGISTERED=""
RULES_VER=$WANT_RV

# ─────────────────────────────── preflight（只读） ───────────────────────────────
step preflight "只读检查"
[ "$(id -u)" = 0 ] || fail "要以 root 跑"
id "$U" >/dev/null 2>&1 || fail "没有用户 $U"
[ -x "$GODOT" ] || fail "没有 $GODOT"
GV=$("$GODOT" --version 2>/dev/null | tail -n 1)
[[ "$GV" == "$GODOT_WANT".* ]] || fail "Godot 版本 $GV ≠ $GODOT_WANT"
log "godot $GV"
[ -d "$REF_ROOT" ] || fail "没有目录 $REF_ROOT"
[ -f "$REF_ENV" ] || fail "没有 $REF_ENV"
[ -f "$POLLER" ] || fail "没有 $POLLER"
DEV_REF=$(stat -c %d "$REF_ROOT"); DEV_OPT=$(stat -c %d /opt)
[ "$DEV_REF" = "$DEV_OPT" ] || fail "$REF_ROOT 与 /opt 不在同一文件系统（暂存 → 换入不是原子 rename）"
AVAIL=$(df -B1 --output=avail /opt | tail -n 1 | tr -d ' ')
log "磁盘 /opt 可用 $((AVAIL / 1024 / 1024)) MiB（要 ≥ $((MIN_DISK / 1024 / 1024))）"
[ "$AVAIL" -ge "$MIN_DISK" ] || fail "磁盘不够"
MEMKB=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
log "内存可用 $((MEMKB / 1024)) MiB；负载 $(cut -d' ' -f1-3 /proc/loadavg)；裁判 Godot 在跑 $(pgrep -fc -- '[s]cenes/Referee.tscn' || true) 局"
if [ -e "$LOCK" ] && ! flock -n "$LOCK" true; then fail "另一次部署正在跑（$LOCK 被占）"; fi
log "锁 $LOCK 空闲"

if [ "$SKIP_BOTS" = 0 ] && [ "$ENVN" = beta ] && [ -e "$BOTS_OFF" ] && [ -z "$ONLY" ]; then
  SKIP_BOTS=1
  log "内测服陪练号停用中（$BOTS_OFF 在）⇒ 这次不碰陪练号（要装先删开关）"
fi
if [ "$SKIP_BOTS" = 0 ]; then
  [ -d "$BOTS_ROOT" ] || fail "没有 $BOTS_ROOT"
  [ -f "$BOTS_ENV" ] || fail "没有 $BOTS_ENV"
  [ "$(stat -c %d "$BOTS_ROOT")" = "$DEV_OPT" ] || fail "$BOTS_ROOT 与 /opt 不在同一文件系统"
  log "陪练号 env BOT_GAME_DIR=$(grep -m1 '^BOT_GAME_DIR=' "$BOTS_ENV" | cut -d= -f2-)；off 开关 $([ -e "$BOTS_OFF" ] && echo 在 || echo 不在)；在跑 $(pgrep -fc -- "$BOTS_PAT" || true) 个"
  if [ -n "$PLANNER_UNIT" ]; then
    PP=$(systemctl show -p MainPID --value "$PLANNER_UNIT")
    log "$PLANNER_UNIT $(systemctl is-active "$PLANNER_UNIT") MainPID=$PP 进程环境 BOT_GAME_DIR=$(tr '\0' '\n' < "/proc/$PP/environ" 2>/dev/null | grep -m1 '^BOT_GAME_DIR=' | cut -d= -f2-)"
  fi
fi
if [ "$ENVN" = prod ] && weekend_now && [ "$ALLOW_WEEKEND" = 0 ] && [ "$ONLY" != pools ]; then
  fail "现在是 UTC 周末（周六闯关 / 周日决赛，调度器不认 off 开关）⇒ 默认不装；真要装加 --allow-weekend"
fi

ST=$(reg_status)
case "$ST" in
  none)  REGISTERED=0; log "referee_versions: $VER 还没登记（或 enabled=false）" ;;
  error) REGISTERED=""; log "⚠ referee_versions: --health 读不到，登记状态不明" ;;
  *)     REGISTERED=1; log "referee_versions: $VER 已登记（rules_ver / 池行数 = $ST）" ;;
esac

if [ -d "$DST" ]; then
  log "目标 $DST 已存在: HEAD=$(head_of "$DST") 版本=$(ver_of "$DST") ⇒ $([ "$(head_of "$DST")" = "$SHA" ] && echo '已经是这个 sha（照样重装）' || echo '会被替换，旧的挪到 '"$PREV_ROOT")"
fi
SRC=""
if [ -z "$ONLY" ]; then
  if [ -d "$DST/.git" ]; then SRC=$DST; else SRC=$(latest_ver_dir "$REF_ROOT"); fi
  if [ -n "$SRC" ]; then
    URL=$(TR git -C "$SRC" remote get-url origin 2>/dev/null)
    log "暂存从 $SRC 拷（已导入过，最快）；origin=$URL"
  else
    URL=https://github.com/yinzuoliu87-cpu/Turtle_realtime_battle.git
    log "$REF_ROOT 下没有现成工程 ⇒ 暂存用 git clone $URL"
  fi
  TAGLINE=$(TR git -C "${SRC:-/tmp}" ls-remote "$URL" "refs/tags/v$VER*" 2>/dev/null)
  TAG_SHA=$(echo "$TAGLINE" | awk -v t="refs/tags/v$VER^{}" '$2==t{print $1}')
  [ -n "$TAG_SHA" ] || TAG_SHA=$(echo "$TAGLINE" | awk -v t="refs/tags/v$VER" '$2==t{print $1}')
  if [ -z "$TAGLINE" ]; then log "⚠ 远端没有 tag v$VER（或 ls-remote 失败）—— 照 sha 取"
  elif [ "$TAG_SHA" != "$SHA" ]; then fail "远端 tag v$VER → $TAG_SHA ≠ 给的 $SHA"
  else log "远端 tag v$VER → $SHA ✓"; fi
fi

# ─────────────────────────────── --only 分支 ───────────────────────────────
if [ "$ONLY" = pools ]; then
  [ -d "$DST" ] || fail "$DST 不存在（先装工程）"
  [ "$(ver_of "$DST")" = "$VER" ] || fail "$DST 版本 $(ver_of "$DST") ≠ $VER"
  [ "$(head_of "$DST")" = "$SHA" ] || fail "$DST HEAD=$(head_of "$DST") ≠ $SHA"
  [ -n "$RULES_VER" ] || RULES_VER=$(rv_of "$DST")
  [ "$(rv_of "$DST")" = "$RULES_VER" ] || fail "$DST RULES_VER=$(rv_of "$DST") ≠ 期望 $RULES_VER"
  [ "$DRY" = 1 ] || { mkdir -p "$RUN_DIR"; exec 9>>"$LOCK"; flock -n 9 || fail "拿不到锁"; }
  pools_and_readback
  print_next_steps
  FINAL=1; [ "$DRY" = 1 ] && echo "DEPLOY OK (dry-run)" || echo "DEPLOY OK"; exit 0
fi
if [ "$ONLY" = bots-switch ]; then
  [ "$SKIP_BOTS" = 0 ] || fail "--only bots-switch 与 --skip-bots 冲突"
  [ -d "$BDST" ] || fail "$BDST 不存在（先装工程）"
  [ -n "$RULES_VER" ] || RULES_VER=$(rv_of "$BDST")
  [ "$DRY" = 1 ] || { exec 9>>"$LOCK"; flock -n 9 || fail "拿不到锁"; }
  bots_switch
  print_next_steps
  FINAL=1; [ "$DRY" = 1 ] && echo "DEPLOY OK (dry-run)" || echo "DEPLOY OK"; exit 0
fi

# 全流程：切陪练号前提 = 版本已登记（否则陪练号开不了积分赛）
if [ "$SKIP_BOTS" = 0 ] && [ "$NO_SWITCH" = 0 ] && [ "$REGISTERED" != 1 ]; then
  fail "referee_versions 里还没有 $VER ⇒ 不能切陪练号。二选一：先登记；或加 --no-bots-switch（装完、登记后再 --only bots-switch）"
fi

# ─────────────────────────────── lock ───────────────────────────────
step lock
if [ "$DRY" = 1 ]; then
  log "[dry-run] 会拿锁 $LOCK；会建 $RUN_DIR、$WORK（$U 可写）"
else
  exec 9>>"$LOCK"
  flock -n 9 || fail "另一次部署正在跑（$LOCK）"
  mkdir -p "$RUN_DIR" "$WORK/home" && chown -R "$U": "$WORK" && chown "$U": "$(dirname "$WORK")" || fail "建工作目录"
  [ -d "$STAGE_ROOT" ] || { mkdir -p "$STAGE_ROOT" && chown "$U": "$STAGE_ROOT"; } || fail "建 $STAGE_ROOT"
  log "锁已拿；日志 $RUN_DIR"
fi

# ─────────────────────────────── drain：导入前停陪练号 ───────────────────────────────
step drain "导入前停陪练号（README：先 touch off 开关并等在跑的陪练号退完；别用 trap 自动删）"
if [ "$NO_DRAIN" = 1 ]; then
  log "⚠ --no-drain：不停陪练号（在跑 $(pgrep -fc -- "$BOTS_PAT" || true) 个）"
else
  if [ -e "$BOTS_OFF" ]; then
    log "$BOTS_OFF 本来就在 ⇒ 不是本脚本建的，结束时不删"
  else
    act touch "$BOTS_OFF" || fail "touch $BOTS_OFF"
    [ "$DRY" = 1 ] || CREATED_OFF=1
  fi
  if [ "$DRY" = 1 ]; then
    log "[dry-run] 会等 $BOTS_PAT 的进程退完（现在 $(pgrep -fc -- "$BOTS_PAT" || true) 个，最多 ${DRAIN_SEC}s）"
  else
    W=0
    while :; do
      N=$(pgrep -fc -- "$BOTS_PAT" || true)
      [ "$N" = 0 ] && break
      [ $W -ge "$DRAIN_SEC" ] && { release_off; fail "等了 ${W}s 还有 $N 个陪练号在跑"; }
      [ $((W % 300)) = 0 ] && log "等陪练号退完: 还有 $N 个（已等 ${W}s）"
      sleep 30; W=$((W + 30))
    done
    log "陪练号已退完（等了 ${W}s）"
  fi
fi
MEMKB=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
log "导入前内存可用 $((MEMKB / 1024)) MiB"
[ "$MEMKB" -ge "$MIN_MEM_KB" ] || [ "$DRY" = 1 ] || fail "可用内存 < 1 GiB，不导入"

# ─────────────────────────────── ref-stage ───────────────────────────────
step ref-stage "暂存目录取 $SHA"
STAGE=$STAGE_NAME
if [ "$DRY" = 1 ]; then
  [ -e "$STAGE" ] && log "[dry-run] 会先删上次留下的 $STAGE"
  if [ -n "$SRC" ]; then log "[dry-run] 会执行: TR cp -a $SRC $STAGE"
  else log "[dry-run] 会执行: TR git clone --depth 1 $URL $STAGE"; fi
  log "[dry-run] 会执行: TR git -C $STAGE fetch -q --depth 1 origin $SHA && TR git -C $STAGE checkout -q -f $SHA"
  log "[dry-run] 然后核: HEAD = $SHA、project.godot 版本 = $VER、scenes/Referee.tscn 在、RULES_VER = ${WANT_RV:-（读工程）}"
else
  rm -rf "$STAGE"
  if [ -n "$SRC" ]; then
    log "+ cp -a $SRC $STAGE"; TR cp -a "$SRC" "$STAGE" || fail "cp -a $SRC"
  else
    log "+ git clone $URL"; TR git clone -q --depth 1 "$URL" "$STAGE" || fail "git clone"
  fi
  TR git -C "$STAGE" fetch -q --depth 1 origin "$SHA" || fail "git fetch $SHA"
  TR git -C "$STAGE" checkout -q -f "$SHA" || fail "git checkout $SHA"
  [ "$(TR git -C "$STAGE" rev-parse HEAD)" = "$SHA" ] || fail "HEAD 不是 $SHA"
  log "HEAD $(TR git -C "$STAGE" log -1 --format='%h %s')"
  log "改动行数(已跟踪) $(TR git -C "$STAGE" status --porcelain --untracked-files=no | wc -l)"
  [ "$(ver_of "$STAGE")" = "$VER" ] || fail "project.godot 版本 $(ver_of "$STAGE") ≠ $VER"
  for f in scenes/Referee.tscn tests/verify_determinism_cross.tscn tests/verify_referee_job_roundtrip.tscn; do
    [ -f "$STAGE/$f" ] || fail "没有 $f"
  done
  RV=$(rv_of "$STAGE")
  log "RULES_VER = $RV"
  if [ -n "$WANT_RV" ] && [ "$RV" != "$WANT_RV" ]; then fail "工程 RULES_VER $RV ≠ 期望 $WANT_RV"; fi
  RULES_VER=$RV
fi

# ─────────────────────────────── ref-import ───────────────────────────────
step ref-import "导入两次（以第二次为准）"
if [ "$DRY" = 1 ]; then
  log "[dry-run] 会执行 ×2: TR env HOME=$WORK/home XDG_DATA_HOME=$WORK/ud-import TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' nice -n 10 timeout 1200 $GODOT --headless --audio-driver Dummy --path $STAGE --import"
else
  import_twice "$STAGE" "$RUN_DIR/ref-import" "$WORK/ud-import" || fail "导入没过（看 $RUN_DIR/ref-import2.log）"
fi

# ─────────────────────────────── bots-stage ───────────────────────────────
if [ "$SKIP_BOTS" = 0 ]; then
  step bots-stage "陪练号工程（从裁判暂存拷：同一 sha、已导入）"
  BSTAGE=$BSTAGE_NAME
  if [ "$DRY" = 1 ]; then
    log "[dry-run] 会执行: TR cp -a $STAGE $BSTAGE"
    [ -n "$OVERLAY" ] && log "[dry-run] 会执行: git fetch $OVERLAY；git restore --source=$OVERLAY --staged --worktree -- scripts/systems/sim"
    log "[dry-run] 会执行 ×2: 导入（XDG_DATA_HOME=$WORK/ud-bots-import）；核 sim_driver 认 SIM_ROUNDS / SIM_QUIT_WHEN_DONE"
  else
    rm -rf "$BSTAGE"
    log "+ cp -a $STAGE $BSTAGE"; TR cp -a "$STAGE" "$BSTAGE" || fail "cp -a 裁判暂存"
    if [ -n "$OVERLAY" ]; then
      TR git -C "$BSTAGE" fetch -q --depth 1 origin "$OVERLAY" || fail "git fetch $OVERLAY"
      TR git -C "$BSTAGE" restore --source="$OVERLAY" --staged --worktree -- scripts/systems/sim || fail "覆盖 scripts/systems/sim"
      log "sim 覆盖成 ${OVERLAY:0:8}：$(TR git -C "$BSTAGE" diff --stat HEAD -- scripts/systems/sim | tail -n 1)（战斗代码保持 tag 原样）"
    fi
    [ "$(head_of "$BSTAGE")" = "$SHA" ] || fail "陪练号暂存 HEAD 不是 $SHA"
    NSIM=$(grep -c 'SIM_ROUNDS\|SIM_QUIT_WHEN_DONE' "$BSTAGE/scripts/systems/sim/sim_driver.gd" || true)
    log "sim_driver 认 SIM_ROUNDS / SIM_QUIT_WHEN_DONE: $NSIM 处"
    [ "$NSIM" -gt 0 ] || fail "sim_driver.gd 不认 bot_runner 给的参数"
    import_twice "$BSTAGE" "$RUN_DIR/bots-import" "$WORK/ud-bots-import" || fail "陪练号工程导入没过（看 $RUN_DIR/bots-import2.log）"
  fi
fi

# ─────────────────────────────── ref-gates ───────────────────────────────
step ref-gates "verify_determinism_cross（--quit-after 40000）+ verify_referee_job_roundtrip（60000）并行，都要 ALL PASS"
if [ "$DRY" = 1 ]; then
  log "[dry-run] 会执行: TR env XDG_DATA_HOME=$WORK/ud-det TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' timeout 1800 $GODOT --headless --audio-driver Dummy --path $STAGE res://tests/verify_determinism_cross.tscn --quit-after 40000 &"
  log "[dry-run] 会执行: TR env XDG_DATA_HOME=$WORK/ud-rt  TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' timeout 1800 $GODOT --headless --audio-driver Dummy --path $STAGE res://tests/verify_referee_job_roundtrip.tscn --quit-after 60000 &"
else
  T0=$SECONDS
  TR env HOME="$WORK/home" XDG_DATA_HOME="$WORK/ud-det" TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' \
    timeout 1800 "$GODOT" --headless --audio-driver Dummy --path "$STAGE" res://tests/verify_determinism_cross.tscn --quit-after 40000 \
    > "$RUN_DIR/gate-det.log" 2>&1 &
  P1=$!
  TR env HOME="$WORK/home" XDG_DATA_HOME="$WORK/ud-rt" TURTLE_BACKEND=' ' TURTLE_SUPABASE=' ' \
    timeout 1800 "$GODOT" --headless --audio-driver Dummy --path "$STAGE" res://tests/verify_referee_job_roundtrip.tscn --quit-after 60000 \
    > "$RUN_DIR/gate-rt.log" 2>&1 &
  P2=$!
  wait $P1; R1=$?
  wait $P2; R2=$?
  GOK=1
  for g in det rt; do
    f=$RUN_DIR/gate-$g.log
    rc=$([ $g = det ] && echo $R1 || echo $R2)
    log "gate $g rc=$rc  ALL PASS=$(grep -c 'ALL PASS' "$f" || true)  SCRIPT ERROR/Parse Error=$(bad_lines "$f")  $((SECONDS - T0))s"
    grep -E 'passed|ALL PASS|FAIL' "$f" | tail -n 3 | sed 's/^/    /'
    if ! grep -q 'ALL PASS' "$f" || [ "$(bad_lines "$f")" != 0 ]; then
      GOK=0; log "  ✗ $g 没过，日志尾："; tail -n 15 "$f" | sed 's/^/    /'
    fi
  done
  [ "$GOK" = 1 ] || fail "一致性门禁没过（不切换；线上目录没动）"
fi

# ─────────────────────────────── swap ───────────────────────────────
step swap "门禁过了 ⇒ 原子换入"
swap_in "$STAGE" "$DST" "$PREV_ROOT/$ENVN-ref-v$VER.prev-$TS" || fail "换入 $DST"
STAGE=""   # 已换入：失败时别再说「暂存目录留着」
if [ "$SKIP_BOTS" = 0 ]; then
  swap_in "$BSTAGE" "$BDST" "$PREV_ROOT/$ENVN-bots-v$VER.prev-$TS" || fail "换入 $BDST"
  BSTAGE=""
fi

# ─────────────────────────────── release-off ───────────────────────────────
step release-off "导入、门禁、换入都做完 ⇒ 放开陪练号（只删本脚本建的开关）"
if [ "$DRY" = 1 ]; then
  if [ "$NO_DRAIN" = 0 ] && [ ! -e "$BOTS_OFF" ]; then log "[dry-run] 会执行: rm -f $BOTS_OFF"; else log "[dry-run] 不动 $BOTS_OFF"; fi
else
  release_off
  [ "$CREATED_OFF" = 1 ] || log "$BOTS_OFF $([ -e "$BOTS_OFF" ] && echo '在（不是本脚本建的，不动）' || echo '不在')"
fi

# ─────────────────────────────── pools ───────────────────────────────
if [ "$NO_POOLS" = 1 ]; then
  log "--no-pools：不生成对手池（之后 --only pools）"
else
  pools_and_readback
fi

# ─────────────────────────────── bots-switch ───────────────────────────────
if [ "$SKIP_BOTS" = 0 ] && [ "$NO_SWITCH" = 0 ]; then
  bots_switch
else
  log "不切陪练号（skip_bots=$SKIP_BOTS no_switch=$NO_SWITCH）；env 仍是 BOT_GAME_DIR=$(grep -m1 '^BOT_GAME_DIR=' "$BOTS_ENV" 2>/dev/null | cut -d= -f2-)"
fi

# ─────────────────────────────── 收尾 ───────────────────────────────
step done
if [ "$DRY" = 0 ]; then
  rm -rf "$WORK"
  log "日志 $RUN_DIR；旧目录（若有）在 $PREV_ROOT"
fi
print_next_steps
FINAL=1
if [ "$DRY" = 1 ]; then log "dry-run：什么都没改"; echo "DEPLOY OK (dry-run)"; else echo "DEPLOY OK"; fi
exit 0
