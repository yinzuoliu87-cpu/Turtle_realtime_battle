#!/usr/bin/env bash
# ── 飞行前检查 · 约 25 秒 ─────────────────────────────────────────────────
# 每改完一批文件就跑一次, **不是**提交门禁的替代品(那个要 4~5 分钟、398 项)。
#
# ★★★为什么有这个东西(2026-09-28 的账):
#   那天我插注释时把下一行多缩了一级 tab ⇒ `class_name CodexDetail` 整份编译不过
#   ⇒ **整个图鉴一个控件都没建**。而 `--import` 退出码 0、一条错都不报 ——
#   GDScript 的 class_name 解析失败是**运行期**才报的。
#   我因此:① 报了「compile clean」往下走 ② 5 条门禁同时红 ③ **连猜三次根因全错**。
#   同一天还把 CLAUDE.md §3.6 两条坑一次踩全(续行被吃 + \n 变真换行撑断 YAML),
#   而 `workflow_lint` 本来就在仓库里、跑一下就能拦住 —— 我没跑。
# ⇒ 这个脚本只做一件事: **把那几类"跑一下就能拦住"的错, 从 5 分钟后提前到 25 秒内**。
#
# 判据取舍(为什么是这几项):
#   · 三个场景测试 19s, 覆盖 7 屏 + 图鉴 —— 专抓"某个类没解析出来 ⇒ 整屏没建"
#     (那种错**长成一堆分母红**, 看着像五个互不相干的 UI 回归)
#   · 审计器只收 <300ms 的。`write_orphan_audit` 要 37s ⇒ 留给全量门禁
#   · `--import` **故意不算通过条件** —— 它对运行期 parse error 是瞎的, 见上
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
[ -f "$GODOT" ] || { echo "Godot not found: $GODOT (set GODOT env)"; exit 2; }
FAIL=0
T0=$(date +%s)

echo "── 场景(专抓 class_name 解析失败 ⇒ 整屏建不起来) ──"
for t in verify_top_bar verify_menu verify_codex_layout; do
  L="/c/tmp/preflight_$t.log"
  APPDATA="/c/tmp/preflight_ad/$t" TURTLE_BACKEND=" " TURTLE_SUPABASE=" " \
    "$GODOT" --headless --audio-driver Dummy --path . "res://tests/$t.tscn" \
    --quit-after 9000 > "$L" 2>&1
  RC=$?
  ERR=$(grep -cE "SCRIPT ERROR|Parse Error" "$L")
  PASS=$(grep -c "ALL PASS" "$L")
  # ★三条都要: rc / 报错数 / **打出了 ALL PASS**。
  #   只看 rc 会漏「帧数不够被 --quit-after 掐断」—— 那种 rc=0、0 报错、却少跑一半断言。
  if [ "$RC" != "0" ] || [ "$ERR" != "0" ] || [ "$PASS" = "0" ]; then
    echo "  FAIL  $t  (rc=$RC 报错=$ERR ALL_PASS=$PASS)  日志 $L"
    grep -E "SCRIPT ERROR|Parse Error|\[FAIL\]" "$L" | sort -u | head -4 | sed 's/^/        /'
    FAIL=$((FAIL+1))
  else
    echo "  ok    $t"
  fi
done

echo "── 审计器(只收便宜的) ──"
for a in workflow_lint plans_lint plan_stale_audit docs_authority_lint \
         type_tables_audit arch_budget data_integrity style_lint; do
  [ -f "tools/$a.py" ] || continue
  if OUT=$(python "tools/$a.py" 2>&1); then
    echo "  ok    $a"
  else
    echo "  FAIL  $a"
    echo "$OUT" | grep -E "FAIL|NEEDS FIX" | head -3 | sed 's/^/        /'
    FAIL=$((FAIL+1))
  fi
done

echo "────────────────────────────────────────────"
if [ "$FAIL" = "0" ]; then
  echo "PREFLIGHT_OK  ($(($(date +%s)-T0))s) —— 这不等于门禁绿, 提交前仍要 JOBS=8 bash run-tests.sh"
else
  echo "PREFLIGHT_FAIL x$FAIL  ($(($(date +%s)-T0))s)"
fi
exit "$FAIL"
