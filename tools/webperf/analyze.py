"""分析 gputrace.json: 按事件名汇总时长(只看 X 完整事件与 B/E 配对), 列出与着色器 / 贴图 / 程序相关的最长事件。"""
import collections
import json
import re
import sys

ev = json.load(open(sys.argv[1]))
pn = {}
tn = {}
for e in ev:
    if e.get("ph") == "M" and e.get("name") == "process_name":
        pn[e["pid"]] = e["args"]["name"]
    if e.get("ph") == "M" and e.get("name") == "thread_name":
        tn[(e["pid"], e["tid"])] = e["args"]["name"]
dur = collections.defaultdict(float)
cnt = collections.Counter()
mx = collections.defaultdict(float)
longest = []
stack = collections.defaultdict(list)
for e in ev:
    ph = e.get("ph")
    if ph == "X" and "dur" in e:
        d = e["dur"] / 1000.0
    elif ph == "B":
        stack[(e["pid"], e["tid"])].append(e)
        continue
    elif ph == "E":
        st = stack[(e["pid"], e["tid"])]
        if not st:
            continue
        b = st.pop()
        d = (e["ts"] - b["ts"]) / 1000.0
        e = dict(b, dur=d * 1000)
    else:
        continue
    key = (pn.get(e["pid"], str(e["pid"])), e["name"])
    dur[key] += d
    cnt[key] += 1
    mx[key] = max(mx[key], d)
    longest.append((d, e["ts"], pn.get(e["pid"], "?"), tn.get((e["pid"], e["tid"]), "?"), e["name"]))
pat = re.compile(r"(?i)shader|program|compile|link|teximage|texsubimage|texstorage|upload|translat|hlsl|d3dcompile|blob|cache")
print("== 名字里带 shader / program / compile / link / teximage 等的事件, 按总时长排 ==")
rows = [(dur[k], cnt[k], mx[k], k) for k in dur if pat.search(k[1])]
for tot, c, m, k in sorted(rows, reverse=True)[:30]:
    print("%9.1f ms 总 · %6d 次 · 最长 %7.1f ms · %s · %s" % (tot, c, m, k[0][:18], k[1][:70]))
print("\n== GPU 进程里最长的 25 个事件 ==")
gl = sorted([x for x in longest if "GPU" in x[2] or "Gpu" in x[2]], reverse=True)[:25]
t0 = min(e["ts"] for e in ev if "ts" in e)
for d, ts, p, t, n in gl:
    print("%8.1f ms @%7.2fs %-14s %-22s %s" % (d, (ts - t0) / 1e6, p[:14], t[:22], n[:80]))
