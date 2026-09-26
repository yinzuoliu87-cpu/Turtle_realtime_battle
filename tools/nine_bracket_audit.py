# -*- coding: utf-8 -*-
"""nine_bracket_audit.py — 守住「9 档进度档已彻底删除」这件事。

【为什么要有它】
用户 2026-09-26:「别再按9档, 给我彻底删掉」。上游 D5(2026-09-16) 早就定了
「硬条件是双方总场次相同(不再按 9 档)」, 而 9 档在仓库里活到了 2026-09-26 ——
因为它当时被留成了「池子的索引」。留着索引的直接后果:
**选靶那一侧顺手拿它当尺子**, 5 场次的人照旧打 7 场次的, 而且门禁全绿。

⇒ 所以这条审计器不是查"符号还在不在", 是查**那个概念的所有载体**都没了:
   ① 两个函数名 `bracket_for_battles` / `battles_for_bracket`
   ② 三个带窗口的选靶原语 `pool_find` / `pool_find_near` / `pool_find_window`
   ③ 池子的旧分桶键字面量 `"brackets"`
   ④ 匹配侧的窗口宽度常量 `MATCH_BATTLES_SPAN`
   ⑤ 快照里的 `bracket` 镜像字段
   ⑥ 拉取窗口常量**不许**被选靶那一侧读到(那正是 09-25 栽的那个坑)

【同名但无关的东西, 一个字都不许动】
`scripts/gamedata/bracket.gd` / `bracket_layout.gd` / `BracketMapScene` / `finals_*`
= **周日单败淘汰对阵图**。它跟进度档只是撞名字。本审计器**按符号**判, 不按文件名,
所以不会误伤 —— 而且下面专门有一条反向断言: 对阵图那三个文件必须还在。

跑法: python tools/nine_bracket_audit.py     (只读; 进 run-tests.sh 门禁)
"""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── 被删的符号: 出现在**代码行**(非注释)里就是红 ──────────────────────────
DEAD_SYMBOLS = [
    ("bracket_for_battles", "9 档函数(场次 → 0..8)"),
    ("battles_for_bracket", "9 档反函数(档 → 场次上界)"),
    ("pool_find_near", "±N 窗口选靶(D5 不允许有窗口)"),
    ("pool_find_window", "档区间选靶"),
    ("MATCH_BATTLES_SPAN", "匹配侧窗口宽度常量(拉取侧改名 PULL_BATTLES_AHEAD)"),
]

# ── 旧分桶键字面量 ────────────────────────────────────────────────────────
DEAD_LITERAL = '"brackets"'

# ★两类允许保留的例外, 都很窄:
#   ① 迁移函数必须读旧键才能搬家 —— 函数名出现在前 25 行内就放过。
#   ② **向后兼容读**: 同一行里也出现了新键 `by_battles`, 形如
#      `for _k in ("by_battles", "brackets")` / `... if "by_battles" in d else "brackets"`。
#      这类是「新键优先、老数据照吃」, 是对的; 而单独出现的 `"brackets"` 一定是漏改。
#      ⇒ 判据卡在「有没有同时提到新键」上, 不是白名单文件名
#        (memory fb-recursive-scan-not-structured-walk: 白名单天生会漏)。
MIGRATION_MARKER = "_migrate_brackets_to_battles"
NEW_KEY = "by_battles"

# ── 扫哪些文件 ────────────────────────────────────────────────────────────
SCAN_DIRS = ["scripts", "autoload", "tests", "tools"]
SCAN_EXT = (".gd", ".py")
SKIP_PARTS = (
    os.sep + "oneoff" + os.sep,        # 一次性脚本(已加硬拦, 跑不起来)
    os.sep + "autoplay" + os.sep,      # 队列原料 json 的目录
    os.sep + "attic" + os.sep,
)


def is_comment(line: str, ext: str) -> bool:
    t = line.lstrip()
    if ext == ".gd":
        return t.startswith("#")
    return t.startswith("#")


def iter_files():
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        for dirpath, _dirs, files in os.walk(base):
            if any(p in dirpath + os.sep for p in SKIP_PARTS):
                continue
            for fn in files:
                if fn.endswith(SCAN_EXT):
                    yield os.path.join(dirpath, fn)


def rel(p: str) -> str:
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def main() -> int:
    fails = []
    scanned = 0
    code_lines = 0

    for path in iter_files():
        ext = os.path.splitext(path)[1]
        try:
            with io.open(path, encoding="utf-8", newline="") as f:
                lines = f.readlines()
        except (OSError, UnicodeDecodeError) as e:
            fails.append("%s 读不了: %s" % (rel(path), e))
            continue
        scanned += 1
        # 本审计器自己不算(它必须把这些符号写出来才能查)
        if rel(path) == "tools/nine_bracket_audit.py":
            continue
        for i, line in enumerate(lines, 1):
            if is_comment(line, ext):
                continue
            code_lines += 1
            for sym, why in DEAD_SYMBOLS:
                if re.search(r"\b%s\b" % re.escape(sym), line):
                    fails.append("%s:%d  `%s` —— %s" % (rel(path), i, sym, why))
            if (DEAD_LITERAL in line
                    and NEW_KEY not in line
                    and MIGRATION_MARKER not in "".join(lines[max(0, i - 25):i])):
                fails.append("%s:%d  旧分桶键字面量 %s (池子现在按【场次】分桶, 用 Backend.POOL_KEY)"
                             % (rel(path), i, DEAD_LITERAL))

    print("=== 9 档彻底删除·审计 ===")
    print("  [分母] 扫了 %d 个文件 / %d 行代码(注释行不算)" % (scanned, code_lines))
    if scanned < 200:
        fails.append("分母太小(%d 个文件) —— 扫描路径可能写错了, 这种审计器空跑必绿" % scanned)

    # ── 反向断言 ①: 周日对阵图那套必须还在(证明本审计器没误伤同名的东西)────
    keep = [
        "scripts/gamedata/bracket.gd",
        "scripts/gamedata/bracket_layout.gd",
        "scripts/scenes/BracketMapScene.gd",
        "tests/verify_bracket.gd",
    ]
    missing = [k for k in keep if not os.path.exists(os.path.join(ROOT, k.replace("/", os.sep)))]
    if missing:
        fails.append("★★误伤: 周日【对阵图】那套被删了 —— 它和进度档只是撞名字: %s" % missing)
    else:
        print("  [OK] 反向: 周日对阵图那套 %d 个文件都在(同名不同物, 不许误伤)" % len(keep))

    # ── 反向断言 ②: 新原语与新键必须真的存在(不然"0 引用"只是因为整块代码没了)──
    be = os.path.join(ROOT, "scripts", "net", "backend.gd")
    be_src = io.open(be, encoding="utf-8", newline="").read()
    for need, why in (
        ("static func pool_find_battles(", "按场次选靶的唯一原语"),
        ('const POOL_KEY := "by_battles"', "池子的新分桶键"),
        ("static func find_opponent(battles: int", "匹配入口收的是场次"),
        ("static func make_bot(battles: int", "bot 按场次配强度"),
    ):
        if need not in be_src:
            fails.append("★★backend.gd 少了 `%s` —— %s" % (need, why))
    print("  [OK] 反向: backend.gd 里新原语/新键都在(否则「0 引用」只是代码整块没了)")

    # ── 反向断言 ③: 选靶那一侧不许读【拉取】窗口常量 ───────────────────────
    #   这正是 2026-09-25 栽的那个坑: 常量本身没错, 错在被拿去当匹配判据。
    m = re.search(r"static func find_opponent\(.*?(?=\nstatic func |\Z)", be_src, re.S)
    if not m:
        fails.append("★★找不到 find_opponent 的函数体 —— 下面那条判据会恒真")
    else:
        body = "\n".join(l for l in m.group(0).split("\n") if not l.lstrip().startswith("#"))
        for bad in ("PULL_BATTLES_AHEAD", "MATCH_BATTLES_SPAN", "span", "AHEAD"):
            if bad in body:
                fails.append("★★★find_opponent 里出现了 `%s` —— 拉取窗口**不许**当匹配判据"
                             "(2026-09-25 就是这么把 ±1 带进选靶的)" % bad)
        print("  [OK] 反向: find_opponent 函数体里没有任何窗口/span(量了 %d 行函数体)"
              % len(body.split("\n")))

    # ── 反向断言 ④: bot 等级曲线的两份镜像必须逐格相同 ─────────────────────
    def read_curve(path, pat):
        src = io.open(os.path.join(ROOT, path), encoding="utf-8", newline="").read()
        mm = re.search(pat, src)
        if not mm:
            return None
        return [int(x) for x in re.findall(r"\d+", mm.group(1))]

    gd = read_curve("scripts/gamedata/phase2_config.gd",
                    r"BOT_LV_MIN_BATTLES\s*:=\s*\[([^\]]*)\]")
    py = read_curve("tools/cohort_to_seed.py",
                    r"BOT_LV_MIN_BATTLES\s*=\s*\[([^\]]*)\]")
    if gd is None or py is None:
        fails.append("★★读不到 BOT_LV_MIN_BATTLES(gd=%s py=%s) —— 手抄的镜像没人看着就会漂"
                     % (gd, py))
    elif gd != py:
        fails.append("★★★bot 等级曲线两份镜像不一致: phase2_config=%s / cohort_to_seed=%s" % (gd, py))
    else:
        print("  [OK] 反向: bot 等级曲线两份镜像逐格相同 %s" % gd)

    print("")
    if fails:
        print("[FAIL] %d 处 —— 9 档没删干净(或误伤了同名的对阵图):" % len(fails))
        for x in fails[:40]:
            print("   · %s" % x)
        if len(fails) > 40:
            print("   … 还有 %d 处" % (len(fails) - 40))
        print("")
        print("方案书: docs/plans/20260926-删掉9档进度档.md")
        return 1
    print("ALL PASS — 9 档已彻底删除, 且同名的周日对阵图没被误伤")
    return 0


if __name__ == "__main__":
    sys.exit(main())
