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

echo "── tools/ 里每个脚本都还能解析吗(毫秒级) ──"
## ★为什么要有这一条: 我删 `codex_text_lint.py` 里一条烂掉的豁免时**按行删 ——
##   把字典的键删了、值那行留下**, 语法当场炸。而当时 preflight **一声不吭**,
##   因为清单里只有八个审计器, 它不在内。
##   (那正是我前一刻还在警告 agent 的「块删法」: 按函数名/键名整条删, 不许按行切。)
## ★为什么不是"把那三个审计器加进下面的清单": 实测 `write_orphan_audit` **65 秒**、
##   `zero_caller_audit` 11.7 秒 —— 加进去 preflight 从 22 秒涨到 98 秒,
##   而它的全部价值就在于**便宜到随时能跑**。贵了就没人跑, 等于没有。
## ⇒ 改成只问「**能不能解析**」: 毫秒级, 而且覆盖 tools/ **全部**脚本, 不只那三个。
##   能不能跑出正确结果由全量门禁判; 这里只保证**不会因为我手抖而整个审计器哑掉**。
BADPY=0
for f in tools/*.py; do
  if ! python -c "import ast,io,sys; ast.parse(io.open(sys.argv[1],encoding='utf-8').read())" "$f" 2>/dev/null; then
    echo "  FAIL  $f 解析不了"; BADPY=$((BADPY+1)); FAIL=$((FAIL+1))
  fi
done
[ "$BADPY" = "0" ] && echo "  ok    $(ls tools/*.py | wc -l) 个脚本全部可解析"

echo "── 审计器(只收便宜的) ──"
## ★2026-09-28 加了两样东西, 各自堵一个真踩过的坑:
##   我删 GD_WHY 里一条烂掉的豁免时**按行删、把键删了值那行留下**, 字典语法当场炸 ——
##   而 preflight 当时**一声不吭**, 因为这三个审计器不在清单里。
##   (正是我前一刻还在警告 agent 的「块删法」: 按函数名/键名整条删, 不许按行切。)
##   ⇒ 判据: **能跑起来**本身就是一层检查。三个都是秒级, 收进来不影响 25 秒预算。
for a in workflow_lint plans_lint plan_stale_audit docs_authority_lint \
         type_tables_audit arch_budget data_integrity style_lint codex_text_lint; do
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
