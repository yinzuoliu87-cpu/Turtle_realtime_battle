"""下载 PixelLab 动画段: fetch_seg.py <段名=job_id> ...  存到 .out/review/hunter_sample/<段名>/f_NN.png, 并拼一张放大对照表"""
import os
import subprocess
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/" + __import__("os").environ.get("SAMPLE", "hunter_sample") + "/"
SCALE = 3
rows = []
for arg in sys.argv[1:]:
    name, job = arg.split("=")
    d = ROOT + name + "/"
    os.makedirs(d, exist_ok=True)
    frames = []
    for i in range(0, 12):
        p = d + "f_%02d.png" % i
        r = subprocess.run(["curl", "-sS", "--noproxy", "*", "-o", p, "-w", "%{http_code}",
                            "https://api.pixellab.ai/mcp/images/%s/download?index=%d" % (job, i)],
                           capture_output=True, text=True)
        if r.stdout.strip() != "200":
            if os.path.exists(p):
                os.remove(p)
            break
        try:
            frames.append(Image.open(p).convert("RGBA"))
        except Exception:
            os.remove(p)
            break
    print(name, len(frames), "帧", frames[0].size if frames else "-")
    rows.append((name, frames))

cols = max(len(f) for _, f in rows)
fw = max(f[0].width for _, f in rows if f)
fh = max(f[0].height for _, f in rows if f)
sheet = Image.new("RGB", (cols * fw * 2, len(rows) * fh * 2), (66, 84, 70))
for y, (_, fr) in enumerate(rows):
    for x, im in enumerate(fr):
        a = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        sheet.paste(a, (x * fw * 2, y * fh * 2), a)
out = ROOT + "sheet_%s.png" % rows[0][0]
sheet.save(out)
print(out, sheet.size)
