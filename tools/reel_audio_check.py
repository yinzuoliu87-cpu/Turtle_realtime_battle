# -*- coding: utf-8 -*-
"""tools/reel_audio_check.py — 审核片里每个技能放出那一刻有没有声、比普攻响多少(2026-11-05)。
由来: 11-05 每个技能加了一条专属放技能声(cast_<技能类型>, 87 条)。我听不见, 只能量: 用审核片(tools/review_reel.py 的产物,
  录制时游戏真实出声)逐段量 ——
  · 技能段: 片内第 1 秒放技能(剪辑就是从放技能前 1 秒开始), 量 [0.95, 1.7] 秒的峰值
  · 普攻段: 量整段 6 秒的峰值中位(按 0.5 秒一窗)
  判据: 技能峰值比同一只龟普攻窗口中位高 ≥ 3 dB 记「明显」, 0~3 dB 记「略高」, 更低记「不高于普攻」。
用法: python tools/reel_audio_check.py <审核片目录(含 seg_*.mp4 与 时间表_*.md)>
"""
import os
import re
import statistics
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
FF = "D:/oopz/ffmpeg.exe"
D = sys.argv[1]


def peak(path: str, ss: float, t: float) -> float:
	r = subprocess.run([FF, "-v", "info", "-ss", "%.2f" % ss, "-t", "%.2f" % t, "-i", path, "-af", "volumedetect", "-vn", "-f", "null", "-"],
		capture_output=True, text=True, encoding="utf-8", errors="replace")
	m = re.search(r"max_volume: (-?[\d.]+|-inf) dB", r.stderr)
	return -99.0 if (m is None or m.group(1) == "-inf") else float(m.group(1))


tbl = [f for f in os.listdir(D) if f.startswith("时间表_") and f.endswith(".md") and "分4份" not in f][0]
rows = [l for l in open(os.path.join(D, tbl), encoding="utf-8").read().splitlines() if l.startswith("| ") and not l.startswith("| 片内") and not l.startswith("|---")]
base = {}
out = []
n_ok = n_low = n_none = 0
for k, r in enumerate(rows):
	cells = [c.strip() for c in r.strip("|").split("|")]
	name, seg = cells[1], cells[2]
	key = name + ("·火山" if "火山形态" in seg else "")
	path = os.path.join(D, "seg_%03d.mp4" % k)
	if "普攻" in seg:
		ws = [peak(path, s * 0.5, 0.5) for s in range(12)]
		base[key] = statistics.median(ws)
		continue
	p = peak(path, 0.95, 0.75)
	b = base.get(key, -99.0)
	d = p - b
	tag = "明显" if d >= 3.0 else ("略高" if d >= 0.0 else "不高于普攻")
	if p <= -60.0:
		tag = "没声"
	n_ok += tag == "明显"
	n_low += tag in ("略高", "不高于普攻")
	n_none += tag == "没声"
	out.append("| %s | %s | %.1f | %.1f | %+.1f | %s |" % (name, seg, p, b, d, tag))
print("| 龟 | 技能段 | 放出峰值 dB | 普攻窗口中位 dB | 差 | 判定 |")
print("|---|---|---|---|---|---|")
print("\n".join(out))
print("\n分母: %d 个技能段 · 明显高于普攻 %d · 略高或不高 %d · 没声 %d" % (len(out), n_ok, n_low, n_none))
