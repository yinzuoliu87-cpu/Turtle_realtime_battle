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
    python tools/duel_report.py --by-role            # 按【定位】聚合(近战坦克/远程法师…) — 验移速定位化有没有兑现
                                                     #   配 --compare 时同时给出两轮的每档差值

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

# ★不可用行 —— 跨【大轮】累积的技能, 单场从零开始测不到它们的真实价值, 胜率被严重低估。
#   用户 2026-07-28:「命运之轮其实应该不参与测试的，这个技能是全大轮成长的」
#   这类行会在排行榜里标 ⊘ 并【从所有聚合口径里剔除】(平均偏离/按龟/按定位),
#   否则它们会把所属龟和所属定位一起拖下水 —— 赌神的档次就是这么被拉低的。
#   ★靠人记住"这几行别看"是不可靠的(2026-07-28 我出报表时就忘了), 所以焊进工具。
EXCLUDED = {
    ("gambler", "命运之轮"): "抽中花色本大轮永久叠, 登场套用",
    ("chest", "清点财宝"): "chest_treasure_value 随大轮累积",
    ("chest", "财宝风暴"): "大轮已开战利品开局回装",
}


def is_excluded(key):
    """key = (龟id, 技能名) 或 tally 出来的三元组 (龟id, idx, 技能名)"""
    if len(key) == 3:
        return (key[0], key[2]) in EXCLUDED
    return (key[0], key[1]) in EXCLUDED


def load_roles():
    """从 scripts/gamedata/turtle_stats.gd 读 ROLE —— 它是定位的【权威事实源】。
    ★不在本文件里再抄一份名单: 抄一份就是又一个会漂的镜像(本项目栽过很多次)。"""
    import re
    fp = os.path.join(ROOT, "scripts", "gamedata", "turtle_stats.gd")
    src = io.open(fp, encoding="utf-8").read()
    m = re.search(r"const ROLE := \{(.*?)\}", src, re.S)
    if not m:
        return {}
    return dict(re.findall(r'"([a-z_]+)":\s*"([^"]+)"', m.group(1)))


def load_role_spec():
    """档位 → [移速, 攻速]"""
    import re
    fp = os.path.join(ROOT, "scripts", "gamedata", "turtle_stats.gd")
    src = io.open(fp, encoding="utf-8").read()
    m = re.search(r"const ROLE_SPEC := \{(.*?)\}", src, re.S)
    if not m:
        return {}
    out = {}
    for name, a, b in re.findall(r'"([^"]+)":\s*\[([\d.]+),\s*([\d.]+)\]', m.group(1)):
        out[name] = (float(a), float(b))
    return out


def name_to_id(rows):
    """CSV 里存的是龟【中文名】, 定位表用的是 id → 从 pets.json 建映射。"""
    import json
    fp = os.path.join(ROOT, "data", "pets.json")
    d = json.load(io.open(fp, encoding="utf-8"))
    pets = d if isinstance(d, list) else d["pets"]
    return {str(p.get("name", p["id"])): p["id"] for p in pets}


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
    ap.add_argument("--by-role", action="store_true", help="额外按【定位】聚合(读 turtle_stats.ROLE)")
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
        if is_excluded(k):
            star = "  ⊘ 不可用(%s)" % EXCLUDED[(k[0], k[2])]
        P("  %-4d %-10s %-14s %6.1f%% %6d %8.2f %8.1f%s" % (i, k[0], k[2], wr, v["n"], cps, secs, star))

    # ── 不可用行 + 剔除后的平衡度 ──
    P("")
    P("  ── 不可用行(跨大轮累积技能·已从下面所有聚合里剔除) ──")
    for (tid, nm), why in EXCLUDED.items():
        hit = [v for k, v in st.items() if k[0] == tid and k[2] == nm]
        got = ("%.1f%%" % (100.0 * hit[0]["w"] / max(1, hit[0]["n"]))) if hit else "(本轮无此行)"
        P("  ⊘ %-9s %-8s %7s   %s" % (tid, nm, got, why))
    usable = {k: v for k, v in st.items() if not is_excluded(k)}
    def dev(d):
        xs = [abs(100.0 * v["w"] / max(1, v["n"]) - 50.0) for v in d.values()]
        return sum(xs) / max(1, len(xs))
    P("  平均偏离 50%%: 全部 %d 行 = %.1fpp  |  剔除后 %d 行 = %.1fpp  (越小越平衡)"
      % (len(st), dev(st), len(usable), dev(usable)))

    # ── 按龟分组(这只龟该带哪个技能) ──
    if args.by_turtle:
        P("")
        P("  ── 按龟分组：同一只龟三个技能的差距 ──")
        by_t = collections.defaultdict(list)
        for k, v in usable.items():                       # ⊘ 行已剔除
            by_t[k[0]].append((k[2], 100.0 * v["w"] / max(1, v["n"]), v["casts"] / max(1, v["n"])))
        spread = []
        for t, lst in by_t.items():
            lst.sort(key=lambda x: -x[1])
            spread.append((max(x[1] for x in lst) - min(x[1] for x in lst), t, lst))
        spread.sort(reverse=True)
        P("  (按【三技能胜率极差】降序 —— 极差大 = 该龟内部严重不平衡，有技能没人会选)")
        for gap, t, lst in spread:
            P("  %-10s 极差 %5.1fpp   %s" % (t, gap, "  ".join("%s %.1f%%" % (n, w) for n, w, _ in lst)))

    # ── 按定位聚合 (2026-07-28 移速定位化后加): 验"近战该回升/远程法师该降"有没有兑现 ──
    if args.by_role:
        roles = load_roles()
        spec = load_role_spec()
        n2i = name_to_id(rows)
        P("")
        P("  ── 按定位聚合（定位表读自 scripts/gamedata/turtle_stats.gd 的 ROLE）──")
        if not roles:
            P("  ★读不到 ROLE 表 —— 定位可能还没建, 或格式变了")
        else:
            def agg(st_):
                acc = collections.defaultdict(lambda: [0, 0, set()])
                unknown = set()
                for k, v in st_.items():
                    if is_excluded(k):                    # ⊘ 行不进定位聚合
                        continue
                    # CSV 的「左龟/右龟」列存的是 id(排行榜里显示 line/angel/hiding 即为证);
                    # 兼容万一将来改存中文名 → 先直接当 id 用, 不中再过中文名映射。
                    tid = k[0] if k[0] in roles else n2i.get(k[0])
                    r = roles.get(tid) if tid else None
                    if r is None:
                        unknown.add(k[0]); continue
                    a = acc[r]
                    a[0] += v["w"]; a[1] += v["n"]; a[2].add(k[0])
                return acc, unknown
            acc, unknown = agg(st)
            acc2 = None
            if args.compare:
                rows2c, _ = load(args.compare)
                if rows2c:
                    st2c, _, _, _ = tally(rows2c)
                    acc2, _ = agg(st2c)
            hdr = "  %-10s %5s %5s %6s %7s" % ("定位", "移速", "攻速", "龟数", "胜率")
            if acc2 is not None:
                hdr += " %9s %8s" % ("对比轮", "差值")
            P(hdr)
            order = sorted(acc.keys(), key=lambda r: (-spec.get(r, (0, 0))[0], r))
            for r in order:
                w, n, ids = acc[r]
                wr = 100.0 * w / max(1, n)
                sp = spec.get(r, (0, 0))
                line = "  %-10s %5.0f %5.2f %6d %6.1f%%" % (r, sp[0], sp[1], len(ids), wr)
                if acc2 is not None and r in acc2:
                    w2, n2, _ = acc2[r]
                    wr2 = 100.0 * w2 / max(1, n2)
                    line += " %8.1f%% %+7.1fpp" % (wr2, wr - wr2)
                P(line)
                P("       %s" % "、".join(sorted(ids)))
            if unknown:
                P("  ★这些龟名在 ROLE 表里找不到(名字对不上?): %s" % ", ".join(sorted(unknown)))
            P("  ★分母: 每档的场次 = 该档所有龟×所有技能的总场次(不是龟数)")

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
