# -*- coding: utf-8 -*-
"""cohort_strategy_report.py — 新快照池的【流派与构筑】验收报告（方案书 20260902 前置 P-A）

════════════════════════════════════════════════════════════════════════
 ★为什么不做成 run-tests.sh 里的门禁
════════════════════════════════════════════════════════════════════════
它要判的是「**真跑出来的 800 支队伍长什么样**」，而跑一场要 37.5 秒（§4 实测）——
门禁里跑不起。所以它是**跑完之后的验收工具**，在执行手册 §7.5 里被显式调用。

════════════════════════════════════════════════════════════════════════
 ★它怎么证明自己会 FAIL（这是本项目的铁律）
════════════════════════════════════════════════════════════════════════
**拿旧池当反向验证**：旧池（184 条 / 那四种蠢 AI 跑出来的）实测
  · 33% 的队伍**一个羁绊都没有**
  · 最高档位全池最大 **2**，没有一支打到过 3 档（顶档）
  · 只有 4 个流派

⇒ `python tools/cohort_strategy_report.py --pool data/ghost_seed.json`
   在**旧池上必须 FAIL**。它在旧池上过了，就说明判据是假的。

跑法:
    python tools/cohort_strategy_report.py                       # 默认读合并后的快照
    python tools/cohort_strategy_report.py --pool data/ghost_seed.json
    python tools/cohort_strategy_report.py --baseline docs/plans/attic/ghost_seed-旧池基线-20260902.json
"""
import argparse
import collections
import io
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## ★档位阈值**不写死**：从 phase2_types.gd 现读。手抄的副本必然落后。
TYPES_GD = os.path.join(ROOT, "scripts", "gamedata", "phase2_types.gd")

## 新池的期望（方案书 §9.5「新池的期望」那张表；改这里要同步改方案书）
EXPECT_MIN_ARCH = 12          # 14 个锚点里至少出现这么多（允许 2 个活不下来，但要在报告里点名）
EXPECT_MAX_ZERO_SYN_PCT = 20.0  # 「零羁绊」占比要显著低于旧池的 33%
EXPECT_TOP_TIER = 3           # 至少要有队伍打到 3 档（顶档）
EXPECT_HI_COST_GAP = 5.0      # hi_cost 组的 4~5 费占比 - random 组，至少高这么多个百分点


def read_tiers():
    """从 phase2_types.gd 现读 TYPES 的 tiers。读不到就退出 —— 不猜默认值。"""
    if not os.path.exists(TYPES_GD):
        print("  [FAIL] 读不到 %s —— 档位阈值无处可取, 这是空检查不是通过" % TYPES_GD)
        sys.exit(1)
    src = io.open(TYPES_GD, encoding="utf-8", errors="replace").read()
    i = src.find("const TYPES")
    j = src.find("\n}", i)
    seg = src[i:j] if i >= 0 else ""
    out = {}
    import re
    for m in re.finditer(r'"([^"]+)":\s*\{"tiers":\s*\[([0-9,\s]+)\]', seg):
        out[m.group(1)] = [int(x) for x in m.group(2).split(",") if x.strip()]
    if len(out) < 8:
        print("  [FAIL] 只解析到 %d 个类型的 tiers(<8) —— 解析失效, 下面全是空数" % len(out))
        sys.exit(1)
    return out


def load_types_map():
    p = os.path.join(ROOT, "data", "p2eq-types.json")
    raw = json.load(io.open(p, encoding="utf-8"))
    out = {}
    for k, v in raw.items():
        out[str(k)] = [str(x) for x in v] if isinstance(v, list) else [str(v)]
    return out


def load_equip():
    p = os.path.join(ROOT, "data", "phase2-equipment.json")
    raw = json.load(io.open(p, encoding="utf-8"))
    items = raw if isinstance(raw, list) else raw.get("equipment", raw.get("items", []))
    return {str(e.get("id")): e for e in items}


def snap_ids(sn, eqs):
    """把一条快照里所有装备 id 掏出来。★递归找 `id` 字段 ——
    快照的形状是 {equipped:{pid:[...]}, minions:{top:[...],bottom:[...]}, loadouts:{...}},
    结构化遍历会漏(memory fb-recursive-scan-not-structured-walk: 结构化遍历=赌数据长什么样)。"""
    out = []

    def walk(n):
        if isinstance(n, dict):
            if "id" in n and str(n["id"]) in eqs:
                out.append(str(n["id"]))
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)
        elif isinstance(n, str) and n in eqs:
            out.append(n)

    for k in ("equipped", "minions", "loadouts"):
        walk(sn.get(k))
    return out


def analyse(snaps, tiers, tmap, eqs):
    arch = collections.Counter()
    cost_by_arch = collections.defaultdict(collections.Counter)
    zero_syn = 0
    max_tier_hist = collections.Counter()
    act_counts = []
    n_items = []
    for sn in snaps:
        a = str(sn.get("_strategy", "(无)"))
        arch[a] += 1
        ids = snap_ids(sn, eqs)
        n_items.append(len(ids))
        for i in ids:
            c = eqs.get(i, {}).get("cost")
            if c:
                cost_by_arch[a][int(c)] += 1
        tc = collections.Counter()
        for i in set(ids):
            for ty in tmap.get(i, []):
                tc[ty] += 1
        act, mx = 0, 0
        for ty, n in tc.items():
            lv = sum(1 for th in tiers.get(ty, []) if n >= th)
            if lv > 0:
                act += 1
            mx = max(mx, lv)
        act_counts.append(act)
        if act == 0:
            zero_syn += 1
        max_tier_hist[mx] += 1
    return {
        "n": len(snaps), "arch": arch, "cost_by_arch": cost_by_arch,
        "zero_syn_pct": 100.0 * zero_syn / max(1, len(snaps)),
        "act_avg": sum(act_counts) / max(1, len(act_counts)),
        "max_tier": max(max_tier_hist) if max_tier_hist else 0,
        "max_tier_hist": max_tier_hist,
        "items_avg": sum(n_items) / max(1, len(n_items)),
    }


def hi_pct(counter):
    tot = sum(counter.values())
    if tot == 0:
        return None
    return 100.0 * (counter.get(4, 0) + counter.get(5, 0)) / tot


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pool", default=os.path.join(ROOT, "tools", "autoplay", "cohort-snapshots.json"))
    ap.add_argument("--baseline", default=os.path.join(
        ROOT, "docs", "plans", "attic", "ghost_seed-旧池基线-20260902.json"))
    a = ap.parse_args()

    if not os.path.exists(a.pool):
        print("  [FAIL] 池子不存在: %s" % a.pool)
        return 1
    d = json.load(io.open(a.pool, encoding="utf-8"))
    if not isinstance(d, dict) or "brackets" not in d:
        print("  [FAIL] 结构不对(应是 {_note, brackets}): %s" % a.pool)
        return 1
    snaps = [s for k in d["brackets"] for s in d["brackets"][k]]
    tiers = read_tiers()
    tmap = load_types_map()
    eqs = load_equip()
    r = analyse(snaps, tiers, tmap, eqs)

    print("=== 快照池流派与构筑报告 ===")
    print("  池子: %s" % a.pool)
    print("  [分母] %d 条快照 · %d 档 · 装备件数均值 %.2f(为 0 = 没解析到, 下面全是空数)"
          % (r["n"], len(d["brackets"]), r["items_avg"]))
    if r["n"] == 0 or r["items_avg"] == 0:
        print("  [FAIL] 分母为 0 —— 这是空检查不是通过")
        return 1

    print("")
    print("  流派覆盖 %d 种:" % len(r["arch"]))
    for k, v in r["arch"].most_common():
        hp = hi_pct(r["cost_by_arch"][k])
        print("     %-12s %4d 条   4~5费占比 %s"
              % (k, v, ("%.0f%%" % hp) if hp is not None else "—"))
    print("")
    print("  同时激活的羁绊类型数: 均值 %.2f" % r["act_avg"])
    print("  零羁绊队伍占比: %.1f%%" % r["zero_syn_pct"])
    print("  最高档位分布: %s  (全池最大 %d)"
          % (dict(sorted(r["max_tier_hist"].items())), r["max_tier"]))

    base = None
    if os.path.exists(a.baseline):
        base = json.load(io.open(a.baseline, encoding="utf-8"))
        print("")
        print("  ── 对照旧池基线 ──")
        print("     零羁绊占比  旧 %.1f%%  →  新 %.1f%%"
              % (float(base.get("零羁绊占比pct", 0)), r["zero_syn_pct"]))
        print("     最高档位    旧 %d      →  新 %d"
              % (int(base.get("最高档位最大", 0)), r["max_tier"]))
        print("     流派数      旧 %d      →  新 %d"
              % (len(base.get("流派", {})), len(r["arch"])))

    print("")
    fails = []
    if len(r["arch"]) < EXPECT_MIN_ARCH:
        fails.append("流派只出现 %d 种(期望 ≥ %d) —— 没出现的那些要点名并写明为什么活不下来"
                     % (len(r["arch"]), EXPECT_MIN_ARCH))
    if r["zero_syn_pct"] > EXPECT_MAX_ZERO_SYN_PCT:
        fails.append("零羁绊队伍占 %.1f%%(期望 ≤ %.0f%%) —— 羁绊类流派没起作用"
                     % (r["zero_syn_pct"], EXPECT_MAX_ZERO_SYN_PCT))
    if r["max_tier"] < EXPECT_TOP_TIER:
        fails.append("全池最高才 %d 档(期望至少有队伍到 %d 档) —— 单线顶档流没走通"
                     % (r["max_tier"], EXPECT_TOP_TIER))
    hp_hi = hi_pct(r["cost_by_arch"].get("hi_cost", collections.Counter()))
    hp_rnd = hi_pct(r["cost_by_arch"].get("random", collections.Counter()))
    if hp_hi is None or hp_rnd is None:
        fails.append("拿不到 hi_cost 或 random 组的费用分布(hi_cost=%s random=%s) —— "
                     "没有对照组就说不清高费流有没有用" % (hp_hi, hp_rnd))
    elif hp_hi - hp_rnd < EXPECT_HI_COST_GAP:
        fails.append("高费流的 4~5 费占比只比随机组高 %.1f 个点(期望 ≥ %.0f) —— 高费流没起作用"
                     % (hp_hi - hp_rnd, EXPECT_HI_COST_GAP))

    if fails:
        print("[FAIL] %d 条不达标:" % len(fails))
        for f in fails:
            print("   · " + f)
        print("")
        print("  (在**旧池**上跑这个脚本本来就该 FAIL —— 那是它的反向验证。")
        print("   在**新池**上 FAIL 才是真问题。)")
        return 1
    print("ALL OK — 新池达到方案书 §9.5 的四条期望")
    return 0


if __name__ == "__main__":
    sys.exit(main())
