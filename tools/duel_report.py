# -*- coding: utf-8 -*-
"""duel_report.py — 把 tests/_duel.gd 产出的逐场 CSV 汇总成【龟×技能 胜率排行榜】。

用户 2026-07-28:「把这个技能胜率统计器做成好的工具，方便未来改技能后也能统计新的排行情况」

★报表与对局分离：本脚本只读 CSV，不跑任何战斗。
  换排序、加列、改阈值都不需要重跑那 3 小时 —— 改技能数值后才需要重跑 _duel.gd。

跑法:
    python tools/duel_report.py                      # 读 tools/duel/*.csv 出表
    python tools/duel_report.py --dir tools/duel2    # 指定目录(比如换种子跑的第二轮)
    python tools/duel_report.py --by-turtle          # 额外按龟分组, 看"这只龟该带哪个技能"
    python tools/duel_report.py --compare tools/duel2 # 与另一轮对比(检验结论对 RNG 是否稳健)

自带体检(每次都打, 不用另外记得跑):
    · 左侧总胜率 —— 应 ≈50%，偏离说明位置/先手偏差没消干净，整份数据要打问号
    · 每个组合的场次是否都等于 83（全循环应当人人满勤）
    · 技能释放为 0 的组合 —— 它的胜率量的是"白板身体"不是技能
    · 超时未分胜负的场次
"""
import argparse
import collections
import csv
import glob
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(dirpath):
    """读一个目录下所有分片 CSV → 逐场记录列表。"""
    rows = []
    files = sorted(glob.glob(os.path.join(dirpath, "duel-*.csv")))
    for fp in files:
        with io.open(fp, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                rows.append(r)
    return rows, files


def tally(rows):
    """一场记两笔：左赢=左组合+1胜、右组合+1负。"""
    st = collections.defaultdict(lambda: {"w": 0, "n": 0, "casts": 0, "frames": 0})
    left_wins = 0
    decided = 0
    timeouts = 0
    for r in rows:
        L = (r["左龟"], int(r["左技能idx"]), r["左技能"])
        R = (r["右龟"], int(r["右技能idx"]), r["右技能"])
        win = r["胜方"]
        if win == "timeout":
            timeouts += 1
            continue
        decided += 1
        if win == "L":
            left_wins += 1
        for key, is_win, casts in ((L, win == "L", int(r["左释放"])), (R, win == "R", int(r["右释放"]))):
            s = st[key]
            s["n"] += 1
            s["w"] += 1 if is_win else 0
            s["casts"] += casts
            s["frames"] += int(r["帧数"])
    return st, left_wins, decided, timeouts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "tools", "duel"))
    ap.add_argument("--by-turtle", action="store_true", help="额外按龟分组输出")
    ap.add_argument("--compare", default="", help="与另一轮结果对比(检验 RNG 稳健性)")
    ap.add_argument("--out", default="", help="同时写出 markdown 文件")
    args = ap.parse_args()

    rows, files = load(args.dir)
    if not rows:
        print("★ %s 下没有 duel-*.csv —— 先跑 tests/_duel.gd" % args.dir)
        return 1
    st, left_wins, decided, timeouts = tally(rows)

    lines = []

    def P(s=""):
        print(s)
        lines.append(s)

    P("=== 龟 × 技能 胜率排行榜 ===")
    P("  来源: %d 个分片 / %d 场实战 / %d 个组合" % (len(files), len(rows), len(st)))

    # ── 体检(先打，出问题就别看排名了) ──
    P("")
    P("  ── 体检 ──")
    lw = 100.0 * left_wins / max(1, decided)
    flag = "" if 45.0 <= lw <= 55.0 else "  ★偏离 50% 过大：位置/先手偏差没消干净，排名要打问号"
    P("  左侧总胜率 %.1f%% (%d/%d)%s" % (lw, left_wins, decided, flag))
    ns = collections.Counter(v["n"] for v in st.values())
    P("  每组合场次分布: %s %s" % (dict(ns), "" if len(ns) == 1 else "★不齐 —— 有分片没跑完或对子重叠"))
    P("  超时未分胜负: %d 场 %s" % (timeouts, "" if timeouts == 0 else "★需查"))
    zero = [k for k, v in st.items() if v["casts"] == 0]
    P("  技能释放恒为 0 的组合: %d 个 %s" % (len(zero), ("→ " + ", ".join("%s/%s" % (k[0], k[2]) for k in zero[:6])) if zero else ""))
    P("  ★分母: %d 场 (0 = 空跑，整表无意义)" % len(rows))

    # ── 主表 ──
    P("")
    P("  ── 84 行排行榜（按胜率降序）──")
    P("  %-4s %-10s %-14s %7s %6s %8s %8s" % ("#", "龟", "技能", "胜率", "场次", "技能释放/场", "均时长(秒)"))
    order = sorted(st.items(), key=lambda kv: -kv[1]["w"] / max(1, kv[1]["n"]))
    for i, (k, v) in enumerate(order, 1):
        wr = 100.0 * v["w"] / max(1, v["n"])
        cps = v["casts"] / max(1, v["n"])
        secs = v["frames"] / max(1, v["n"]) / 60.0
        star = "  ★释放≈0" if cps < 0.5 else ""
        P("  %-4d %-10s %-14s %6.1f%% %6d %8.2f %8.1f%s" % (i, k[0], k[2], wr, v["n"], cps, secs, star))

    # ── 按龟分组(这只龟该带哪个技能) ──
    if args.by_turtle:
        P("")
        P("  ── 按龟分组：同一只龟三个技能的差距 ──")
        by_t = collections.defaultdict(list)
        for k, v in st.items():
            by_t[k[0]].append((k[2], 100.0 * v["w"] / max(1, v["n"]), v["casts"] / max(1, v["n"])))
        spread = []
        for t, lst in by_t.items():
            lst.sort(key=lambda x: -x[1])
            spread.append((max(x[1] for x in lst) - min(x[1] for x in lst), t, lst))
        spread.sort(reverse=True)
        P("  (按【三技能胜率极差】降序 —— 极差大 = 该龟内部严重不平衡，有技能没人会选)")
        for gap, t, lst in spread:
            P("  %-10s 极差 %5.1fpp   %s" % (t, gap, "  ".join("%s %.1f%%" % (n, w) for n, w, _ in lst)))

    # ── 两轮对比(RNG 稳健性) ──
    if args.compare:
        rows2, _ = load(args.compare)
        if rows2:
            st2, _, _, _ = tally(rows2)
            P("")
            P("  ── 与 %s 对比（同一结论在不同种子下稳不稳）──" % args.compare)
            diffs = []
            for k, v in st.items():
                if k in st2:
                    a = 100.0 * v["w"] / max(1, v["n"])
                    b = 100.0 * st2[k]["w"] / max(1, st2[k]["n"])
                    diffs.append((abs(a - b), k, a, b))
            diffs.sort(reverse=True)
            avg = sum(d[0] for d in diffs) / max(1, len(diffs))
            P("  平均胜率差 %.1fpp（越小越说明排名不是 RNG 抖出来的）" % avg)
            P("  差得最多的 5 个:")
            for d, k, a, b in diffs[:5]:
                P("    %-10s %-14s %.1f%% vs %.1f%%  (差 %.1fpp)" % (k[0], k[2], a, b, d))

    if args.out:
        io.open(args.out, "w", encoding="utf-8").write("```\n" + "\n".join(lines) + "\n```\n")
        print("\n  已写出 %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
