"""rec_pick.py —— 录像按【指定时间点】抽帧拼一张图(自查用, 11-26; 按时间段均匀抽帧用 rec_sheet.py)
    python tools/oneoff/rec_pick.py <mp4> <输出png> <crop w:h:x:y 或 full> <放大倍数> t1 t2 ...
"""
import subprocess, sys, os, tempfile
from PIL import Image

FF = "D:/oopz/ffmpeg.exe"
mp4, out, crop, sc = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
ts = sys.argv[5:]
tmp = tempfile.mkdtemp()
ims = []
for i, t in enumerate(ts):
    p = os.path.join(tmp, "%d.png" % i)
    vf = [] if crop == "full" else ["-vf", "crop=" + crop]
    subprocess.run([FF, "-loglevel", "error", "-y", "-ss", t, "-i", mp4, "-frames:v", "1"] + vf + [p], check=True)
    im = Image.open(p).convert("RGB")
    im = im.resize((int(im.width * sc), int(im.height * sc)), Image.NEAREST)
    ims.append(im)
cols = min(4, len(ims))
rows = (len(ims) + cols - 1) // cols
w, h = ims[0].size
o = Image.new("RGB", (cols * w, rows * h))
for i, im in enumerate(ims):
    o.paste(im, ((i % cols) * w, (i // cols) * h))
o.save(out)
