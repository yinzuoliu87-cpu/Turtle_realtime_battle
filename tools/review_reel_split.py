# -*- coding: utf-8 -*-
"""tools/review_reel_split.py — 审核片切成 N 份(单份 ≈ 26 MB, 手机上好收) + 分份时间表(2026-11-05)。
读 tools/review_reel.py 的产物目录: seg_000.mp4 … 与 时间表_<标签>.md; 每份 = 连续的若干段拼起来重编码(CRF 26, 单份 ≈ 25 MB)。
用法: python tools/review_reel_split.py <审核片目录> [份数=4] [标题]
产物: <目录>/审核片_第k份.mp4 · <目录>/审核片时间表_分N份.md
"""
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
FF = "D:/oopz/ffmpeg.exe"
D = os.path.abspath(sys.argv[1])
N = int(sys.argv[2]) if len(sys.argv) > 2 else 4
TITLE = sys.argv[3] if len(sys.argv) > 3 else "审核片时间表"
SEG = 6.0
tbl = [f for f in os.listdir(D) if f.startswith("时间表_") and f.endswith(".md")][0]
rows = [l for l in open(os.path.join(D, tbl), encoding="utf-8").read().splitlines()
	if l.startswith("| ") and not l.startswith("| 片内") and not l.startswith("|---")]
segs = sorted(f for f in os.listdir(D) if f.startswith("seg_") and f.endswith(".mp4"))
assert len(segs) == len(rows), (len(segs), len(rows))
per = -(-len(segs) // N)
out = ["# %s" % TITLE, "",
	"整场画面、正常速度、带声音。每只龟依次：普攻 → 技能 1 → 技能 2 → 技能 3，每段 6 秒（放技能前 1 秒到放技能后 5 秒）。",
	"熔岩龟两种形态各一套（普通 / 火山形态）。共 %d 段、%d 份，每份最多 %d 段。" % (len(segs), N, per), ""]
for k in range(N):
	part = segs[k * per:(k + 1) * per]
	if not part:
		continue
	lst = os.path.join(D, "_part_%d.txt" % k)
	open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % os.path.join(D, s).replace("\\", "/") for s in part))
	mp4 = os.path.join(D, "审核片_第%d份.mp4" % (k + 1))
	subprocess.run([FF, "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
		"-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", mp4], check=True)   # 重编码压到单份 ≈ 25 MB(直接拼 ≈ 44 MB)
	out += ["", "## 第 %d 份" % (k + 1), "", "| 份内时间 | 龟 | 段 | 备注 |", "|---|---|---|---|"]
	for i, s in enumerate(part):
		cells = [c.strip() for c in rows[k * per + i].strip("|").split("|")]
		t = i * SEG
		out.append("| %d:%02d | %s | %s | %s |" % (int(t // 60), int(t % 60), cells[1], cells[2], cells[3] if len(cells) > 3 else ""))
	print("第 %d 份: %d 段 · %.1f MB" % (k + 1, len(part), os.path.getsize(mp4) / 1e6))
open(os.path.join(D, "审核片时间表_分%d份.md" % N), "w", encoding="utf-8").write("\n".join(out) + "\n")
