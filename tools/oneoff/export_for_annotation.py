# -*- coding: utf-8 -*-
"""导出给用户手标中线的帧(2026-11-13)。

用户 11-13:「参考这类图片所使用的过滤器或者过滤算法也是有问题…把这些图片放到一个文件夹放我桌面, 我来对每个图片进行中线的标注…
  我标注可能会因为手抖有些歪, 需要你来防止这种过拟合」。
输出: 桌面/触手中线标注/<击>/<序号>_离贴地<τ>秒.png(原画面像素, 只圈出根部) + 说明.txt;
  原图另存 .out/ref_illaoi/annot_src/(读回标注时逐像素比对, 改过的像素 = 用户画的线, 不挑颜色) + manifest.json。
"""
import json
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
SRC = os.path.join(OUTD, "annot_src")
DESK = os.path.join(os.path.expanduser("~"), "Desktop", "触手中线标注")
FF = "D:/oopz/ffmpeg.exe"
VID = os.path.join(OUTD, "illaoi_2.mkv")
TAUS = [0.80, 0.72, 0.60, 0.50, 0.40, 0.33, 0.26, 0.20,
        0.150, 0.133, 0.117, 0.100, 0.083, 0.067, 0.050, 0.033, 0.017, 0.000]
## --after: 刀光之后(贴地 → 趴着 → 抬起卷回, LoL 约 +0.33 s 开始抬、+0.65 s 回到待机)
TAUS_AFTER = [-0.017, -0.033, -0.050, -0.083, -0.117, -0.150, -0.200, -0.250, -0.300, -0.350, -0.400, -0.450, -0.500, -0.550, -0.600, -0.650]

README = """触手中线标注 —— 说明

每个子文件夹是 LoL 录屏里的一次拍击(文件夹名 = 录屏里第几秒), 里面按时间顺序排好:
  前 8 张 = 蓄力(离贴地 0.80 → 0.20 秒), 后 10 张 = 甩下(离贴地 0.15 → 0 秒, 每帧 1/60 秒)。

怎么画:
1. 每张图画【一条线】: 从白圈(触手根部)开始, 沿触手【身子的正中】一直画到梢头的尖上。
2. 鳍不用管, 只画身子的中线。一笔画完最好, 断开几段也没关系。
3. 颜色随便(建议纯红), 线宽 3~6 像素就行。
4. 不要裁剪、不要改图片大小。画完直接保存覆盖原文件(文件名不变)。
   (要是用 iPad / 手机标, 存回来尺寸变了也没关系, 我会按比例对回去。)
5. 看不清身子的(被特效挡住 / 甩得太快糊成一片 / 出了画面)就别画, 原样留着, 我会当作「这一帧没标」。

我这边读回来的方法: 跟我留的原图逐像素比, 你改过的像素就是你画的线(所以颜色不限)。
手抖我来处理: 每条线先用平滑曲线拟合抹掉抖动, 4 次拍击同一时刻取中位数, 再按时间前后顺一遍;
  哪一张和其他三击差得特别多, 我会单独拿出来给你看, 不会直接用。
"""


def grab(t):
    r = subprocess.run([FF, "-loglevel", "error", "-ss", "%.4f" % t, "-i", VID, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                       capture_output=True)
    return np.frombuffer(r.stdout, np.uint8)[: 1920 * 1080 * 3].reshape(1080, 1920, 3)


## --idle: 待机(录屏 73–91 s 镜头固定, 三根各每秒一帧); 原画面像素, 只圈根部
IDLE_TENTS = [("左上", (240, 0, 760, 420), (458, 194)),
              ("中间", (800, 100, 1300, 600), (1013, 458)),
              ("右边", (1400, 380, 1920, 880), (1696, 821))]   # 右边那根根部被小地图挡住, 白圈是估的; 读线时不硬连到白圈


def export_idle():
    raw = np.memmap(os.path.join(OUTD, "idle_full30.rgb"), dtype=np.uint8, mode="r").reshape(-1, 1080, 1920, 3)
    man = []
    for name, (x0, y0, x1, y1), (rx, ry) in IDLE_TENTS:
        sub = "待机_%s那根" % name
        os.makedirs(os.path.join(DESK, sub), exist_ok=True)
        os.makedirs(os.path.join(SRC, sub), exist_ok=True)
        for i, t in enumerate(range(73, 92)):
            f = raw[int(round((t - 68.5) * 30)), y0:y1, x0:x1]
            im = Image.fromarray(np.ascontiguousarray(f))
            dd = ImageDraw.Draw(im)
            lr = (rx - x0, ry - y0)
            dd.ellipse((lr[0] - 9, lr[1] - 9, lr[0] + 9, lr[1] + 9), outline=(255, 255, 255), width=2)
            name_f = "%02d_录屏%d秒.png" % (i + 1, t)
            im.save(os.path.join(SRC, sub, name_f))
            shutil.copyfile(os.path.join(SRC, sub, name_f), os.path.join(DESK, sub, name_f))
            man.append({"strike": "idle_" + name, "tau": float(t), "t": float(t), "box": [x0, y0, x1 - x0, y1 - y0], "root": [rx, ry],
                        "fwd_ground": None, "file": os.path.join(sub, name_f)})
    json.dump(man, open(os.path.join(SRC, "manifest_idle.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("待机导出", len(man), "张")


## --idle2: 全片其余待机(11-13 用户「再找别的生成触手待机，我视频里有多个吧」): 扫全片根部青色标记 + 镜头固定 + 那根没在出手
##   (名字, 根部画面坐标, 起, 止); 每 0.5 秒一张
IDLE2 = [("12.5-17秒_右上那根", (1550, 348), 13.0, 17.0),
         ("12.5-17秒_左边那根", (749, 439), 13.0, 17.0),
         ("22-30秒_墙根那根", (953, 730), 22.0, 30.0),
         ("33-36秒_墙根那根", (613, 730), 33.0, 36.0),
         ("42-45秒_上面那根", (1340, 306), 42.0, 45.0),
         ("47-51秒_上面那根", (1284, 339), 47.0, 51.5)]


def export_idle2():
    man = []
    for name, (rx, ry), t0, t1 in IDLE2:
        x0 = min(max(rx - 300, 0), 1920 - 600)
        y0 = min(max(ry - 380, 0), 1080 - 520)
        sub = "待机_" + name
        os.makedirs(os.path.join(DESK, sub), exist_ok=True)
        os.makedirs(os.path.join(SRC, sub), exist_ok=True)
        ts = [round(t0 + 0.5 * k, 1) for k in range(int(round((t1 - t0) / 0.5)) + 1)]
        for i, t in enumerate(ts):
            f = grab(t)[y0:y0 + 520, x0:x0 + 600]
            im = Image.fromarray(f.copy())
            dd = ImageDraw.Draw(im)
            lr = (rx - x0, ry - y0)
            dd.ellipse((lr[0] - 9, lr[1] - 9, lr[0] + 9, lr[1] + 9), outline=(255, 255, 255), width=2)
            name_f = "%02d_录屏%.1f秒.png" % (i + 1, t)
            im.save(os.path.join(SRC, sub, name_f))
            shutil.copyfile(os.path.join(SRC, sub, name_f), os.path.join(DESK, sub, name_f))
            man.append({"strike": "idle_" + name, "tau": t, "t": t, "box": [x0, y0, 600, 520], "root": [rx, ry],
                        "fwd_ground": None, "file": os.path.join(sub, name_f)})
    json.dump(man, open(os.path.join(SRC, "manifest_idle2.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("其余待机导出", len(man), "张")


def main():
    if "--idle2" in sys.argv:
        export_idle2()
        return
    if "--idle" in sys.argv:
        export_idle()
        return
    d = json.load(open(os.path.join(OUTD, "strike_ruler.json"), encoding="utf-8"))
    after = "--after" in sys.argv
    taus = TAUS_AFTER if after else TAUS
    suffix = "_刀光之后" if after else ""
    if not after and os.path.isdir(DESK) and os.listdir(DESK) and "--force" not in sys.argv:
        print("桌面文件夹已存在且非空, 不覆盖(加 --force)"); return
    os.makedirs(DESK, exist_ok=True)
    os.makedirs(SRC, exist_ok=True)
    man = []
    for T_s, s in d.items():
        T = float(T_s)
        rx, ry = s["root"]
        x0 = min(max(rx - 560, 0), 1920 - 1000)
        y0 = min(max(ry - 430, 0), 1080 - 760)
        sub = "%.1f秒那一击%s" % (T, suffix)
        os.makedirs(os.path.join(DESK, sub), exist_ok=True)
        os.makedirs(os.path.join(SRC, sub), exist_ok=True)
        for i, tau in enumerate(taus):
            f = grab(T - tau)[y0:y0 + 760, x0:x0 + 1000]
            im = Image.fromarray(f.copy())
            dd = ImageDraw.Draw(im)
            lr = (rx - x0, ry - y0)
            dd.ellipse((lr[0] - 11, lr[1] - 11, lr[0] + 11, lr[1] + 11), outline=(255, 255, 255), width=2)
            name = ("%02d_刀光后%.3f秒.png" % (i + 1, -tau)) if after else ("%02d_离贴地%.3f秒.png" % (i + 1, tau))
            im.save(os.path.join(SRC, sub, name))
            shutil.copyfile(os.path.join(SRC, sub, name), os.path.join(DESK, sub, name))
            man.append({"strike": T_s, "tau": tau, "t": round(T - tau, 4), "box": [x0, y0, 1000, 760], "root": [rx, ry],
                        "fwd_ground": s["fwd_ground"], "file": os.path.join(sub, name)})
    if not after:
        open(os.path.join(DESK, "说明.txt"), "w", encoding="utf-8-sig").write(README)
    json.dump(man, open(os.path.join(SRC, "manifest_after.json" if after else "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("导出", len(man), "张 →", DESK)


if __name__ == "__main__":
    main()
