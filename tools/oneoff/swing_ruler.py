# -*- coding: utf-8 -*-
"""量尺: 拍下那一段(离贴地 0.20 秒 → 贴地后 0.05 秒)逐帧(60fps)抠中心线, 画回原图 + 梢端轨迹(2026-11-13)。

用户 11-13「下则是贴地从侧面横扫再甩出？？？哪里学的 / 不是让你看多根吗」: 那个结论只来自 31.1 s 一击的几帧目测 ⇒
  这里 4 击逐帧量, 看梢端是从根部上方翻过来还是从下方(靠镜头那侧)绕过来。只做量尺, 输出 .out/ref_illaoi/。
用法: python tools/oneoff/swing_ruler.py   (击次与根部取 strike_ruler.json)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strike_ruler import OUTD, centerline, to_plane  # noqa: E402

FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)


def main():
    d = json.load(open(os.path.join(OUTD, "strike_ruler.json"), encoding="utf-8"))
    allp = {}
    for T_s, s in d.items():
        T = float(T_s)
        root = tuple(s["root"])
        box = (max(root[0] - 450, 0), max(root[1] - 380, 0), 900, 620)
        box = (box[0], box[1], min(900, 1920 - box[0]), min(620, 1080 - box[1]))
        taus = [round(0.20 - k / 60.0, 4) for k in range(16)]
        tips, frames, lines = [], [], []
        for tau in taus:
            f, pl = centerline(T - tau, root, box)
            im = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8))
            dd = ImageDraw.Draw(im)
            if pl is not None and len(pl) > 8:
                q = [(x - box[0], y - box[1]) for x, y in pl]
                dd.line(q, fill=(0, 255, 60), width=4)
                dd.ellipse((q[-1][0] - 7, q[-1][1] - 7, q[-1][0] + 7, q[-1][1] + 7), outline=(255, 255, 0), width=3)
                tips.append((tau, q[-1]))
                lines.append((tau, q))
            rr = (root[0] - box[0], root[1] - box[1])
            dd.ellipse((rr[0] - 7, rr[1] - 7, rr[0] + 7, rr[1] + 7), outline=(255, 40, 40), width=3)
            dd.text((8, 6), "%s  离贴地 %+.3f 秒" % (T_s, tau), fill=(255, 255, 0), font=FONT)
            frames.append(im)
        ## 逐帧条
        w, h = 300, int(300 * box[3] / box[2])
        sh = Image.new("RGB", (w * 8, h * 2))
        for i, im in enumerate(frames):
            sh.paste(im.resize((w, h)), ((i % 8) * w, (i // 8) * h))
        sh.save(os.path.join(OUTD, "swing_%s_strip.png" % T_s))
        ## 梢端轨迹: 画在第一帧上, 按时间编号
        base = frames[0].copy()
        dd = ImageDraw.Draw(base)
        for k, (tau, p) in enumerate(tips):
            c = (int(255 * k / max(len(tips) - 1, 1)), 80, 255 - int(255 * k / max(len(tips) - 1, 1)))
            dd.ellipse((p[0] - 8, p[1] - 8, p[0] + 8, p[1] + 8), fill=c)
            dd.text((p[0] + 9, p[1] - 12), "%.2f" % tau, fill=(255, 255, 255), font=FONT)
        for k in range(len(tips) - 1):
            dd.line([tips[k][1], tips[k + 1][1]], fill=(255, 255, 255), width=2)
        rr = (root[0] - box[0], root[1] - box[1])
        dd.ellipse((rr[0] - 9, rr[1] - 9, rr[0] + 9, rr[1] + 9), outline=(255, 40, 40), width=4)
        base.save(os.path.join(OUTD, "swing_%s_path.png" % T_s))
        print(T_s, "梢端", [(t, (int(p[0] - rr[0]), int(p[1] - rr[1]))) for t, p in tips])
        ## 每帧姿势(俯仰角): 按本击「梢端甩到目标」那一帧对齐(各击贴地时刻的估计差 1–2 帧)
        g = s["fwd_ground"]
        ## 「甩到目标」= 梢端第一次到了根部朝目标那一侧、且够远(沿出手方向的投影 > 最大值的 60%)
        fs = np.array([g[0], -g[1] * 0.829])
        fs /= np.linalg.norm(fs)
        prj = [(t, (p[0] - rr[0]) * fs[0] + (p[1] - rr[1]) * fs[1]) for t, p in tips]
        mx = max(v for _, v in prj)
        lash = next(t for t, v in prj if v > 0.6 * mx)
        poses = {}
        for tau, q in lines:
            pl = np.array([(x + box[0], y + box[1]) for x, y in q])
            ang, L = to_plane(pl, g)
            poses["%.3f" % round(tau - lash, 3)] = {"pitch": [round(a, 1) for a in ang], "len_px": round(L, 1)}
        allp[T_s] = {"lash_tau": lash, "poses": poses}
    json.dump(allp, open(os.path.join(OUTD, "swing_ruler.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
