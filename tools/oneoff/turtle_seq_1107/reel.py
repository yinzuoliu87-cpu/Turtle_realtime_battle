"""成片合成: 一只龟一条视频, 所有动作按顺序播。
每段 = 原速循环 N 遍 + 0.5 倍慢放 1 遍, 左上角写动作名和实速。
clip = {"name", "note", "frames": [RGBA...], "fps", "ox", "ground", "idle_gap"(动作后站立秒), "loop"(循环动作)}
ox: 帧里本体 128 画布的左边距; ground: 帧里地面所在的行。"""
import os
import subprocess

from PIL import Image, ImageDraw, ImageFont

FF = "D:/oopz/ffmpeg.exe"
FONT = "C:/Windows/Fonts/msyh.ttc"
W, H, Z, GY = 1280, 720, 3, 650
CX = 640          # 本体 128 画布中心落在画面 x
BG = (66, 84, 70)


def dump_bare(clips, tid):
    import json, os
    root = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/seq_raw/%s/" % tid
    meta = {}
    for c in clips:
        n = c["name"].replace(" · ", "_").replace("（", "_").replace("）", "")
        os.makedirs(root + n, exist_ok=True)
        k = 0
        for im in c["frames"]:
            if c["name"] == "阵亡" and im.getchannel("A").getextrema()[1] < 255:
                continue
            im.save(root + n + "/f_%02d.png" % k)
            k += 1
        meta[n] = {"n": k, "fps": c["fps"], "ox": c.get("ox", 0), "ground": c.get("ground", 123), "rel": c.get("rel", -1)}
    json.dump(meta, open(root + "meta.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(tid, {k: v["n"] for k, v in meta.items()})


def render(clips, title, out, idle=None, idle_ox=0, idle_ground=123, idle_fps=8.0, repeats=2):
    import os as _o
    if _o.environ.get("ACT_BARE"):
        return dump_bare(clips, _o.environ["ACT_BARE"])
    f_t, f_n, f_s = ImageFont.truetype(FONT, 34), ImageFont.truetype(FONT, 44), ImageFont.truetype(FONT, 24)
    p = subprocess.Popen([FF, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", "30", "-i", "-",
                          "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)

    def base(c, speed):
        im = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(im)
        d.text((30, 14), title, font=f_t, fill=(205, 222, 208))
        d.text((30, 58), c["name"], font=f_n, fill=(255, 244, 214))
        d.text((30, 122), c.get("note", ""), font=f_s, fill=(205, 222, 208))
        d.text((W - 30, 22), speed, font=f_s, fill=(255, 225, 120), anchor="ra")
        d.line((0, GY, W, GY), fill=(46, 60, 50), width=4)
        return im

    def put(im, fr, ox, ground):
        a = fr.resize((fr.width * Z, fr.height * Z), Image.NEAREST)
        im.paste(a, (CX - (ox + 64) * Z, GY - ground * Z), a)

    n = 0
    for c in clips:
        frames, fps = c["frames"], float(c["fps"])
        dur = len(frames) / fps
        gap = float(c.get("idle_gap", 0.45))
        loop = bool(c.get("loop", False))
        cycle = dur if loop else dur + gap
        for speed, count, label in ((1.0, repeats if not loop else 3, "原速"), (0.5, 1, "0.5 倍慢放")):
            total = cycle * count / speed
            for k in range(int(total * 30)):
                t = (k / 30.0) * speed
                q = t % cycle
                bg = base(c, label)
                if q < dur:
                    put(bg, frames[min(len(frames) - 1, int(q * fps))], c.get("ox", 0), c.get("ground", 123))
                else:
                    extra = c.get("after")
                    if extra:
                        put(bg, extra, c.get("ox", 0), c.get("ground", 123))
                    if idle:
                        put(bg, idle[int(t * idle_fps) % len(idle)], idle_ox, idle_ground)
                p.stdin.write(bg.tobytes())
                n += 1
    p.stdin.close()
    p.wait()
    print(os.path.basename(out), round(n / 30.0, 1), "秒", round(os.path.getsize(out) / 1048576, 2), "MiB", p.returncode)
