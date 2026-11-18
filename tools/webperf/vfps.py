"""录右屏一块区域(60 fps 无损) → 每帧 md5 → 每秒「画面真变了」的帧数; 另报默认 mpdecimate 留下的帧数做对照。
用法: python vfps.py <输出前缀> [秒数=12] [x y w h(物理像素, 默认右屏战场中部 1280x720)]"""
import collections
import os
import subprocess
import sys

FF = r"C:\Users\Louis\AppData\Local\Python\pythoncore-3.14-64\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
pre = sys.argv[1]
sec = int(sys.argv[2]) if len(sys.argv) > 2 else 12
x, y, w, h = [int(v) for v in sys.argv[3:7]] if len(sys.argv) > 6 else (1920 + 640, 440, 1280, 720)
mkv = pre + ".mkv"
subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "gdigrab", "-framerate", "60", "-offset_x", str(x), "-offset_y", str(y),
                "-video_size", "%dx%d" % (w, h), "-draw_mouse", "0", "-t", str(sec), "-i", "desktop", "-c:v", "ffv1", mkv], check=True)
r = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-i", mkv, "-f", "framemd5", "-"], capture_output=True, text=True, check=True)
rows = [ln.split(",") for ln in r.stdout.splitlines() if ln and not ln.startswith("#")]
pts = [int(c[2]) for c in rows]
md5 = [c[5].strip() for c in rows]
tb = 1.0 / 60.0
per = collections.Counter()
tot = collections.Counter()
prev = None
gaps = []
last_change = None
for p, m in zip(pts, md5):
    s = int(p * tb)
    tot[s] += 1
    if m != prev:
        per[s] += 1
        if last_change is not None:
            gaps.append((p - last_change) * tb * 1000.0)
        last_change = p
    prev = m
r2 = subprocess.run([FF, "-hide_banner", "-i", mkv, "-vf", "mpdecimate", "-f", "null", "-"], capture_output=True, text=True)
kept = [ln for ln in r2.stderr.splitlines() if "frame=" in ln]
print("录到 %d 帧 / %d 秒" % (len(pts), sec))
print("每秒画面真变了的帧数:", [per[s] for s in sorted(tot)])
print("每秒录到的帧数    :", [tot[s] for s in sorted(tot)])
gaps.sort()
if gaps:
    print("两次画面变化间隔 ms: 中位 %.1f · 95%% %.1f · 最长 %.1f" % (gaps[len(gaps) // 2], gaps[int(len(gaps) * 0.95)], gaps[-1]))
print("默认 mpdecimate 留下:", kept[-1].strip()[:80] if kept else "?")
