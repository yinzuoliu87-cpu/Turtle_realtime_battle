#!/usr/bin/env python3
"""tools/sim60_scan.py — 汇总 60 人模拟的每个槽位: 事件日志(sim_events.jsonl) + godot.log 里的报错。

只读。用法: python tools/sim60_scan.py [SIM_ROOT] [槽位号 ...]
  默认 SIM_ROOT = C:/tmp/turtle-sim60, 默认扫全部 p01..p60 里存在的。

★报错按「去掉数字之后的那一行」归并计数(同一个错每帧刷几千条只算一种, 但条数照实打)。
★分母都打出来: 读到几个槽位、每个槽位读到几行事件 —— 0 行是「没跑」不是「没问题」。
"""
import io
import json
import os
import re
import sys
from collections import Counter

ROOT = sys.argv[1] if len(sys.argv) > 1 else "C:/tmp/turtle-sim60"
ROOT = re.sub(r"^/([a-zA-Z])/", lambda m: m.group(1).upper() + ":/", ROOT)
WANT = [int(x) for x in sys.argv[2:]] or list(range(1, 61))
UD = "Godot/app_userdata/斗龟场 实时版"
ERR = re.compile(r"^(ERROR|SCRIPT ERROR|WARNING|USER ERROR|USER WARNING)")


def norm(line):
    return re.sub(r"\d+", "#", line.strip())[:180]


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")   # Windows 控制台默认 GBK, 中文会乱码
    except Exception:
        pass
    seen = 0
    for i in WANT:
        d = os.path.join(ROOT, "p%02d" % i)
        if not os.path.isdir(d):
            continue
        seen += 1
        evp = os.path.join(d, UD, "sim_events.jsonl")
        evs = []
        if os.path.exists(evp):
            for ln in io.open(evp, encoding="utf-8", errors="replace"):
                try:
                    evs.append(json.loads(ln))
                except Exception:
                    pass
        kinds = Counter(e.get("kind") for e in evs)
        results = [e for e in evs if e.get("kind") == "result"]
        last = results[-1]["data"]["stats"] if results else {}
        print("== p%02d  事件 %d 行 | 局 %d(教学 %d) | 最后 %s" % (
            i, len(evs), len(results), sum(1 for r in results if r["data"].get("tutorial")),
            json.dumps({k: last.get(k) for k in ("battles", "wins", "hearts", "ranked_used", "coins", "level")},
                       ensure_ascii=False) if last else "-"))
        roster = next((e["data"] for e in evs if e.get("kind") == "roster"), None)
        if roster:
            print("   龟/招: %s / %s" % (roster.get("pets"), roster.get("skills")))
        for e in evs:
            k = e.get("kind")
            if k in ("ANOMALY", "STUCK", "blocked", "done", "tour_end", "trainer", "replay", "record"):
                print("   %s %-9s %s" % (e.get("t", "")[11:19], k, json.dumps(e.get("data"), ensure_ascii=False)[:300]))
        bots = [e["data"] for e in evs if e.get("kind") == "battle_enter" and not e["data"].get("tutorial")]
        if bots:
            nb = sum(1 for b in bots if b.get("opp_is_bot"))
            same = sum(1 for b in bots if b.get("opp_battles") is not None and int(b["opp_battles"]) == int(b["my_battles"]))
            print("   对手: %d 局, 机器人 %d / 真人快照 %d · 对手场次==我 %d/%d · 名字 %s" % (
                len(bots), nb, len(bots) - nb, same, len(bots), sorted({b.get("opp_name") for b in bots})[:8]))
        logd = os.path.join(d, UD, "logs")
        errs = Counter()
        ## ★每次启动 Godot 都把上一份 godot.log 轮转成 godot<时刻>.log ⇒ 全部读, 不然只看得到最后一次启动
        for fn in (sorted(os.listdir(logd)) if os.path.isdir(logd) else []):
            if not (fn.startswith("godot") and fn.endswith(".log")):
                continue
            lines = io.open(os.path.join(logd, fn), encoding="utf-8", errors="replace").read().splitlines()
            for n, ln in enumerate(lines):
                if ERR.match(ln):
                    at = lines[n + 1].strip() if n + 1 < len(lines) and lines[n + 1].strip().startswith("at:") else ""
                    errs[norm(ln) + ("  " + norm(at) if at else "")] += 1
        if errs:
            print("   godot.log 报错 %d 条 / %d 种:" % (sum(errs.values()), len(errs)))
            for msg, c in errs.most_common(8):
                print("     %5d  %s" % (c, msg))
    print("\n分母: 扫到 %d 个槽位目录 (要的 %d 个)" % (seen, len(WANT)))


if __name__ == "__main__":
    main()
