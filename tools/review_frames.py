"""tools/review_frames.py — 从审核片原始录像抽帧拼图, 镜头跟着受审龟(2026-11-05)。
录像里龟会冲到场边(稳定骰子 / 熔岩冲刺), 固定裁切拍不到; 外壳场景 tests/probes/review_rec_probe.gd 每帧打印 [POS] 帧号 屏幕x 屏幕y,
这里按它把每帧裁成以龟为中心的 W×H(贴边时夹回画面内), 再拼成一张。帧号相对放技能那一帧([CAST] 第一条)。
用法: python tools/review_frames.py <raw.avi> <输出.png> <起(相对)> <止(相对)> [步长=1] [W=480] [H=300] [列=4] [第几次放技能=1]
"""
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
FF = "D:/oopz/ffmpeg.exe"
raw, out = sys.argv[1], sys.argv[2]
a, b = int(sys.argv[3]), int(sys.argv[4])
step = int(sys.argv[5]) if len(sys.argv) > 5 else 1
W = int(sys.argv[6]) if len(sys.argv) > 6 else 480
H = int(sys.argv[7]) if len(sys.argv) > 7 else 300
COLS = int(sys.argv[8]) if len(sys.argv) > 8 else 4
nth = int(sys.argv[9]) if len(sys.argv) > 9 else 1
log = open(raw + ".log", encoding="utf-8", errors="replace").read()
casts = [int(x) for x in re.findall(r"\[CAST\] frame=(\d+)", log)]
base = casts[nth - 1] if len(casts) >= nth else 0
pos = {int(f): (int(x), int(y)) for f, x, y in re.findall(r"\[POS\] (\d+) (-?\d+) (-?\d+)", log)}
frames = list(range(base + a, base + b + 1, step))
tmp = os.path.join(os.path.dirname(os.path.abspath(out)), "_rf")
os.makedirs(tmp, exist_ok=True)
paths = []
for i, f in enumerate(frames):
	x, y = pos.get(f, pos.get(f - 1, (640, 360)))
	cx = min(max(x - W // 2, 0), 1280 - W)
	cy = min(max(y - int(H * 0.55), 0), 720 - H)
	p = os.path.join(tmp, "%03d.png" % i)
	## Movie Maker 第 N 帧 = 外壳场景 _process 第 N 次 ⇒ avi 下标 N-1
	subprocess.run([FF, "-v", "quiet", "-y", "-i", raw, "-vf",
		r"select='eq(n\,%d)',crop=%d:%d:%d:%d,drawtext=fontfile=C\\:/Windows/Fonts/arial.ttf:text='%+d':x=4:y=4:fontsize=18:fontcolor=yellow:box=1:boxcolor=black@0.6" % (f - 1, W, H, cx, cy, f - base),
		"-frames:v", "1", p], check=True)
	paths.append(p)
rows = (len(paths) + COLS - 1) // COLS
inputs = []
for p in paths:
	inputs += ["-i", p]
lay = "|".join("%d_%d" % ((i % COLS) * W, (i // COLS) * H) for i in range(len(paths)))
subprocess.run([FF, "-v", "error", "-y", *inputs, "-filter_complex", "xstack=inputs=%d:layout=%s:fill=black" % (len(paths), lay) if len(paths) > 1 else "null", "-frames:v", "1", out], check=True)
print("放技能帧 %d · 抽 %d 帧 → %s" % (base, len(paths), out))
