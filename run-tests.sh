#!/bin/bash
# run-tests.sh — headless 跑全部自证测试 + 全流程闪退冒烟 (不依赖编辑器)
# 用法:  bash run-tests.sh
# 输出:  每个测试 PASS/FAIL + 末尾汇总
#
# 找不到 Godot 时改 GODOT 变量。--import 首次或新增 class_name 后需先跑 (注册全局 class)。

GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$GODOT" ]; then
  echo "Godot not found at: $GODOT  (set GODOT env var)"
  exit 1
fi

# ★致命报错模式 —— 2026-07-10 血的教训:
#   我原来的 sim 过滤器里【没有 Max recursion】, 于是 24 组 sim 全报「0 errors」,
#   而真实对局里 _eq_chain_lightning 正在每秒刷几百条 "ERROR: Max recursion reached"
#   (拿单位字典当 Dictionary 的 key → recursive_hash 无限递归), 60 秒战斗刷了 26564 条,
#   并且把帧率拖到 60 秒战斗跑不完。过滤器漏一个模式, 就等于把 bug 判成绿灯。新增模式往这里加。
FATAL='Infinite loop detected|SCRIPT ERROR|Parse Error|Max recursion|freed instance|null instance|Cannot call|Invalid (get|set|call|index)|Trying to (assign|call)|Nonexistent'

PASS=0; FAIL=0

# 帧预算 (--quit-after 的单位是【帧】不是毫秒)。默认 500 帧 ≈ 8 秒。
# 需要更多的测试在此登记 —— 帧数不够会让测试【跑到一半被掐断】,
# 表现为"没打 ALL PASS"而不是"某条断言 FAIL", 极易被误读成真失败。
frames_for () {
  case "$1" in
    verify_ios_ui) echo 4000 ;;   # 逐个进出 9 个菜单场景, 500 帧只够跑完 2 个
    *)             echo 500  ;;
  esac
}

run_test () {  # $1 = 测试名
  local name="$1"
  if [ ! -f "$DIR/tests/$name.tscn" ]; then
    echo "  SKIP  $name (无 .tscn)"; return
  fi
  local out rc fatal
  out="$("$GODOT" --headless --path "$DIR" "res://tests/$name.tscn" --quit-after "$(frames_for "$name")" 2>&1)"
  rc=$?
  fatal="$(echo "$out" | grep -cE "$FATAL")"
  if [ "$rc" -eq 0 ] && [ "$fatal" -eq 0 ] && { echo "$out" | grep -q "ALL PASS" || echo "$out" | grep -q "自证完成"; }; then
    PASS=$((PASS+1)); echo "  PASS  $name"
  else
    FAIL=$((FAIL+1)); echo "  FAIL  $name  (rc=$rc, 致命报错=$fatal)"
    echo "$out" | grep -E "\[FAIL\]|✗|$FATAL" | head -5 | sed 's/^/        /'
  fi
}

# ★自动发现, 不用硬编码名单 —— 2026-07-20 的教训:
#   原来这里是手写的 28 个名字, 而 tests/ 下实际有 36 个 verify_*.gd。
#   漏登记的 8 个【从来没被执行过】, 其中 verify_ios_ui 早就因帧数不足跑不完, 无人知晓。
#   写测试的人不会记得回来改名单, 所以名单这种形式本身就是错的 —— 改成扫目录。
#   新增测试只要放进 tests/ 并配好 .tscn 就自动纳入, 无需任何登记动作。
echo "=== 自证测试 (自动发现 tests/verify_*.gd) ==="
DISCOVERED=0
for f in "$DIR"/tests/verify_*.gd; do
  [ -e "$f" ] || continue
  t="$(basename "$f" .gd)"
  DISCOVERED=$((DISCOVERED+1))
  run_test "$t"
done
echo "  (发现 $DISCOVERED 个测试)"

# ── 全流程闪退冒烟 ────────────────────────────────────────────────────────────
#   必须用 SHIP=1 跑: 否则 _review_demo() 为真 → 假人永不死 → 战斗永不结束 → 结算路径根本没测到。
echo "=== 全流程闪退冒烟 (SHIP=1 真实对局) ==="
SMOKE_OUT="$(SHIP=1 "$GODOT" --headless --path "$DIR" res://tests/smoke_scenes.tscn --quit-after 40000 2>&1)"
SMOKE_RC=$?
SMOKE_FATAL="$(echo "$SMOKE_OUT" | grep -cE "$FATAL")"
if [ "$SMOKE_RC" -eq 0 ] && [ "$SMOKE_FATAL" -eq 0 ] && echo "$SMOKE_OUT" | grep -q "SMOKE DONE"; then
  PASS=$((PASS+1)); echo "  PASS  smoke_scenes (9场景进出×4 + 战斗中途硬释放×3 + 60秒完整战斗)"
else
  FAIL=$((FAIL+1)); echo "  FAIL  smoke_scenes  (rc=$SMOKE_RC, 致命报错=$SMOKE_FATAL)"
  echo "$SMOKE_OUT" | grep -E "$FATAL" | sort | uniq -c | sort -rn | head -5 | sed 's/^/        /'
fi


# ── 三方一致性对账 (pets.json ↔ 活代码 ↔ 权威文档) ──────────────────────────
echo "=== 三方一致性对账 ==="
TRI="$(cd "$DIR" && TRI_OUT="$DIR/tri_audit_report.txt" python tools/tri_audit.py 2>&1)"
# C 段(icon 索引错位)是已知待用户拍板项, 不算失败; 其余段(A/B/D/E/F)必须 0
if echo "$TRI" | grep -q "selftest OK"; then
  PASS=$((PASS+1)); echo "  PASS  tri_audit ($(echo "$TRI" | grep -oE '差异 [0-9]+ 处'))"
else
  FAIL=$((FAIL+1)); echo "  FAIL  tri_audit"; echo "$TRI" | tail -3 | sed 's/^/        /'
fi

# ── 只读数据审计器 ──────────────────────────────────────────────────────────
#   ★这些以前只能【手动跑】, 于是"改了没人拦" —— 装备文案与代码分歧就是这么攒出来的
#   (2026-07-19 那轮花了近 30 个来回逐条人工核对)。现在进门禁, 分歧当场报。
run_audit () {   # $1=脚本 $2=判定通过的关键字 $3=显示名
  local out
  out="$(cd "$DIR" && python "$1" 2>&1)"
  if echo "$out" | grep -q "$2"; then
    PASS=$((PASS+1)); echo "  PASS  $3"
  else
    FAIL=$((FAIL+1)); echo "  FAIL  $3"; echo "$out" | tail -6 | sed 's/^/        /'
  fi
}

echo "=== 只读数据审计 ==="
run_audit "tools/data_integrity.py"       "ALL OK" "data_integrity (json交叉引用/资源路径/孤儿字段)"
run_audit "tools/tooltip_number_audit.py" "ALL OK" "tooltip_number_audit (装备文案数值 ↔ 代码)"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS/$PASS)"
  exit 0
else
  echo "FAIL x$FAIL  (PASS $PASS)"
  exit 1
fi
