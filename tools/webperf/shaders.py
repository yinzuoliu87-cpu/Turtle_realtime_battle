"""从 gputrace.json 里挑出最慢的着色器编译, 把 ANGLE 翻出来的 HLSL 原文存盘, 并按特征词猜是哪类 Godot 着色器。

用法: python tools/webperf/shaders.py <gputrace.json> [最少毫秒=300] [输出目录=.out/webperf/shaders]
  · 只看名字带 compile 的完整事件(X)或 B/E 配对; 源码取事件 args 里最长的那个字符串(ANGLE 把 HLSL 挂在 args 上)
  · 「@秒」= 相对追踪开始; 对应播放器里的对局时刻要拿 perf=1 读数里的长帧时刻去对(两者差一个固定的载入耗时)
  · 类别是按 HLSL 里 Godot 的 uniform / 结构名猜的: 粒子运算(_sAttractor / _emission_) / 画布(_ucanvas / batch) / 场景(_uscene_data / _umaterial) / 天空(_usky)
"""
import collections
import json
import os
import re
import sys

src = sys.argv[1]
min_ms = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(src)), "shaders")
os.makedirs(out, exist_ok=True)
ev = json.load(open(src, encoding="utf-8"))
t0 = min(e["ts"] for e in ev if "ts" in e)
KINDS = [("粒子运算", re.compile(r"_sAttractor|_uemission|_emission_|_ulifetime|_ucollision")),
         ("粒子绘制", re.compile(r"_uparticle|INSTANCE_CUSTOM|_uinstance_custom")),
         ("天空", re.compile(r"_usky|_uradiance")),
         ("画布", re.compile(r"_ucanvas|_ubatch|_uDrawData|_ucanvas_transform|_uscreen_pixel_size")),
         ("场景", re.compile(r"_uscene_data|_umaterial|_uworld_transform|_uSceneData|_uomni|_uspot"))]


def longest_str(o, best=""):
    if isinstance(o, str):
        return o if len(o) > len(best) else best
    if isinstance(o, dict):
        for v in o.values():
            best = longest_str(v, best)
    elif isinstance(o, list):
        for v in o:
            best = longest_str(v, best)
    return best


stack = collections.defaultdict(list)
hits = []
for e in ev:
    ph = e.get("ph")
    if ph == "B":
        stack[(e["pid"], e["tid"])].append(e)
        continue
    if ph == "E":
        st = stack[(e["pid"], e["tid"])]
        if not st:
            continue
        b = st.pop()
        e = dict(b, dur=e["ts"] - b["ts"], args=dict(b.get("args") or {}, **(e.get("args") or {})))
    elif ph != "X" or "dur" not in e:
        continue
    if "compile" not in e.get("name", "").lower():
        continue
    ms = e["dur"] / 1000.0
    if ms >= min_ms:
        hits.append((ms, (e["ts"] - t0) / 1e6, e["name"], longest_str(e.get("args") or {})))
print("编译事件 ≥ %.0f ms: %d 个" % (min_ms, len(hits)))
for i, (ms, at, name, code) in enumerate(sorted(hits, key=lambda h: h[1])):
    kind = next((k for k, p in KINDS if p.search(code)), "?") if code else "(无源码)"
    fn = ""
    if code:
        fn = os.path.join(out, "%02d_@%06.1fs_%dms.hlsl" % (i, at, ms))
        open(fn, "w", encoding="utf-8").write(code)
    print("  @%7.2fs %7.0f ms  %-26s %-8s %s" % (at, ms, name[:26], kind, os.path.basename(fn)))
