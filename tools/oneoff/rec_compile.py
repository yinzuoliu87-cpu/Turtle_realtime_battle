"""rec_compile.py —— 把演示台录像按羁绊拼成一条带字幕的视频(11-27 自查交付用: 用户「后面的东西你都让我一个个看，很浪费我时间」)
    python tools/oneoff/rec_compile.py <录像目录> <输出 mp4> <段名>=<字幕> ...
每段左上角压一行字幕(装备名 + 这段在看什么), 段与段之间不加转场。
"""
import os, subprocess, sys, tempfile

FF = "D:/oopz/ffmpeg.exe"
FONT = "C\\:/Windows/Fonts/simhei.ttf"
src, out = sys.argv[1], sys.argv[2]
segs = [a.split("=", 1) for a in sys.argv[3:]]
tmp = tempfile.mkdtemp()
parts = []
for i, (name, cap) in enumerate(segs):
    capf = os.path.join(tmp, "cap%d.txt" % i)
    with open(capf, "w", encoding="utf-8") as f:
        f.write(cap)
    p = os.path.join(tmp, "p%d.mp4" % i)
    vf = ("drawbox=x=0:y=0:w=iw:h=44:color=black@0.55:t=fill,"
          "drawtext=fontfile='%s':textfile='%s':x=14:y=10:fontsize=24:fontcolor=white:expansion=none" % (FONT, capf.replace("\\", "/").replace(":", "\\:")))
    subprocess.run([FF, "-loglevel", "error", "-y", "-i", os.path.join(src, name + ".mp4"), "-vf", vf,
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "24", "-r", "30", "-an", p], check=True)
    parts.append(p)
lst = os.path.join(tmp, "list.txt")
with open(lst, "w", encoding="utf-8") as f:
    for p in parts:
        f.write("file '%s'\n" % p.replace("\\", "/"))
subprocess.run([FF, "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out], check=True)
print(out, os.path.getsize(out) // 1024, "KB")
