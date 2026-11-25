"""rec_sheet.py —— 从录像台的 mp4 里按时间段抽帧拼成一张看图(2026-11-25 匕首批自查)

    python tools/oneoff/rec_sheet.py <case> <起秒> <时长> [每秒几帧=10] [裁切 x,y,w,h=320,160,640,400] [放大=1]
输出 .out/dagger_rec/sheet_<case>_<起秒>.png
"""
import glob, os, subprocess, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FF = os.environ.get("FF", "D:/oopz/ffmpeg.exe")


def main():
    case, t0, dur = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    fps = float(sys.argv[4]) if len(sys.argv) > 4 else 10.0
    x, y, w, h = [int(v) for v in (sys.argv[5] if len(sys.argv) > 5 else "320,160,640,400").split(",")]
    k = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0
    d = os.path.join(ROOT, ".out", "dagger_rec", "f_" + case)
    os.makedirs(d, exist_ok=True)
    for f in glob.glob(os.path.join(d, "*.png")):
        os.remove(f)
    subprocess.run([FF, "-loglevel", "error", "-ss", str(t0), "-t", str(dur), "-i", os.path.join(ROOT, ".out", "dagger_rec", case + ".mp4"),
                    "-vf", "fps=%g" % fps, os.path.join(d, "%03d.png")], check=True)
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    cw, ch = int(w * k), int(h * k)
    cols = 4 if cw <= 700 else 2
    rows = (len(fs) + cols - 1) // cols
    sheet = Image.new("RGB", (cw * cols, ch * rows), (0, 0, 0))
    for i, f in enumerate(fs):
        im = Image.open(f).crop((x, y, x + w, y + h)).resize((cw, ch), Image.NEAREST)
        sheet.paste(im, ((i % cols) * cw, (i // cols) * ch))
    out = os.path.join(ROOT, ".out", "dagger_rec", "sheet_%s_%g.png" % (case, t0))
    sheet.save(out)
    print(out, len(fs))


if __name__ == "__main__":
    main()
