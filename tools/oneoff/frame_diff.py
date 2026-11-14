# -*- coding: utf-8 -*-
"""单帧完整对比(2026-11-13 用户「拿一帧出来, 左图和右图之间差了哪些地方, 完完整整写出来, 相似度是多少」)。
左 = LoL 录屏, 右 = 我们(调试场录像), 同一时刻(按光柱对齐)。分别抠出触手轮廓 + 中心线, 按根部对齐、按中心线身长缩放到一样大, 量:
  ① 中心线相似度 = 1 − 平均点距 / 0.25 身长(0.25 = 两条完全不像的线的典型差距; 封底 0)
  ② 剪影重合度 IoU   ③ 粗细分布相关(从根到梢 20 处的宽度 / 身长)   ④ 高宽比
输出 .out/ref_illaoi/frame_diff_<秒>.png(原图 | 轮廓与中心线叠在一起)+ 打印分数。
"""
import io
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from my_annotate import tent_mask  # noqa: E402
from roto_tentacle import skel_paths  # noqa: E402
from idle_match import resample  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTD = os.path.join(ROOT, ".out", "ref_illaoi")
FF = "D:/oopz/ffmpeg.exe"


def grab(video, t, crop):
    x0, y0, w, h = crop
    r = subprocess.run([FF, "-loglevel", "error", "-ss", "%.3f" % t, "-i", video, "-frames:v", "1", "-vf", "crop=%d:%d:%d:%d" % (w, h, x0, y0),
                        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True)
    return np.frombuffer(r.stdout, np.uint8)[: w * h * 3].reshape(h, w, 3).astype(np.int16)


def ours_mask(f, bg, root):
    d = np.abs(f - bg).sum(-1)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    m = (d > 60) & (b > r + 10)
    m = ndimage.binary_opening(m, iterations=1)
    m = ndimage.binary_closing(m, iterations=4)
    m = ndimage.binary_fill_holes(m)
    lab, k = ndimage.label(m)
    if not k:
        return m
    yy, xx = np.ogrid[: m.shape[0], : m.shape[1]]
    near = (xx - root[0]) ** 2 + (yy - root[1]) ** 2 < 70 ** 2
    cand = sorted(set(np.unique(lab[near & m])) - {0})
    return (lab == cand[int(np.argmax(ndimage.sum(m, lab, cand)))]) if cand else np.zeros_like(m)


def analyse(mask, root):
    raw = skel_paths(mask, root, None)
    pl = np.asarray(raw, float)
    L = float(np.hypot(*np.diff(pl, axis=0).T).sum())
    q = resample(pl)
    ## 粗细: 每个中心线点到轮廓边缘的距离 × 2
    dt = ndimage.distance_transform_edt(mask)
    pts = q * L + pl[0]
    wid = np.array([2.0 * dt[int(np.clip(p[1], 0, mask.shape[0] - 1)), int(np.clip(p[0], 0, mask.shape[1] - 1))] for p in pts]) / L
    ys, xs = np.nonzero(mask)
    hw = (ys.max() - ys.min() + 1) / max(xs.max() - xs.min() + 1, 1)
    return {"line": q, "L": L, "width": wid, "hw": float(hw), "raw": pl}


def norm_mask(mask, root, L, mirror=False, size=240):
    ## 按根部平移、按身长缩放到 size 像素网格里(身长 = 0.8 × size)
    ys, xs = np.nonzero(mask)
    s = 0.8 * size / L
    X = (xs - root[0]) * s * (-1 if mirror else 1) + size / 2
    Y = (ys - root[1]) * s + size * 0.9
    out = np.zeros((size, size), bool)
    ok = (X >= 0) & (X < size) & (Y >= 0) & (Y < size)
    out[Y[ok].astype(int), X[ok].astype(int)] = True
    return ndimage.binary_closing(out, iterations=2)


def main():
    t_rel = float(sys.argv[1])
    lol_vid = os.path.join(OUTD, "illaoi_2.mkv")
    our_vid = os.path.join(ROOT, ".out", "tent_design", os.environ.get("OUR_VID", "spawn2.avi"))
    L_crop, L_root, L_beam, L_bg = (780, 100, 500, 500), (1013 - 780, 458 - 100), 72.35, 70.0
    O_crop, O_beam = (270, 100, 560, 560), 2.05
    fl = grab(lol_vid, L_beam + t_rel, L_crop)
    bl = grab(lol_vid, L_bg, L_crop)
    fo = grab(our_vid, O_beam + t_rel, O_crop)
    bo = grab(our_vid, 0.25, O_crop)
    ml = tent_mask(fl, bl, L_root)
    ## 我们的根部: 先粗定在画面里根部附近, 再取轮廓最低处
    o_root_guess = (280, 400)
    mo = ours_mask(fo, bo, o_root_guess)
    ys, xs = np.nonzero(mo)
    O_root = (int(np.median(xs[ys > ys.max() - 6])), int(ys.max()))
    al, ao = analyse(ml, L_root), analyse(mo, O_root)
    best = None
    for mir in (False, True):
        qo = ao["line"] * np.array([-1 if mir else 1, 1])
        d = float(np.mean(np.linalg.norm(qo - al["line"], axis=1)))
        if best is None or d < best[0]:
            best = (d, mir)
    d, mir = best
    nl = norm_mask(ml, L_root, al["L"])
    no = norm_mask(mo, O_root, ao["L"], mir)
    iou = float((nl & no).sum() / max((nl | no).sum(), 1))
    wc = float(np.corrcoef(al["width"][2:-2], ao["width"][2:-2])[0, 1])
    res = {"中心线平均差(身长比)": round(d, 3), "中心线相似度": round(max(0.0, 1 - d / 0.25), 2), "剪影重合度IoU": round(iou, 2),
           "粗细分布相关": round(wc, 2), "LoL平均粗细(身长比)": round(float(al["width"].mean()), 3), "我们平均粗细(身长比)": round(float(ao["width"].mean()), 3),
           "LoL最粗处(身长位置)": round(float(np.argmax(al["width"]) / 19), 2), "我们最粗处": round(float(np.argmax(ao["width"]) / 19), 2),
           "LoL高宽比": round(al["hw"], 2), "我们高宽比": round(ao["hw"], 2), "镜像": mir}
    print(json.dumps(res, ensure_ascii=False, indent=1))
    ## 图: 两张原图 + 叠图(红 = LoL 轮廓, 绿 = 我们轮廓, 黄 = 重叠)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    A = Image.fromarray(np.clip(fl, 0, 255).astype(np.uint8)).resize((420, 420))
    B = Image.fromarray(np.clip(fo, 0, 255).astype(np.uint8)).resize((420, 420))
    ov = np.zeros((240, 240, 3), np.uint8)
    ov[nl] = (255, 70, 70); ov[no] = (70, 255, 110); ov[nl & no] = (255, 230, 60)
    C = Image.fromarray(ov).resize((420, 420), Image.NEAREST)
    dc = ImageDraw.Draw(C)
    for q, col in ((al["line"], (255, 255, 255)), (ao["line"] * np.array([-1 if mir else 1, 1]), (40, 120, 255))):
        dc.line([(210 + p[0] * 0.8 * 420, 0.9 * 420 + p[1] * 0.8 * 420) for p in q], fill=col, width=3)
    sh = Image.new("RGB", (1260, 470), (15, 15, 22))
    for i, (im, lab) in enumerate(((A, "LoL 光柱后 %.2f 秒" % t_rel), (B, "我们 同一时刻"), (C, "叠图: 红 LoL 黄 重叠 绿 我们; 白线 LoL 蓝线 我们"))):
        sh.paste(im, (i * 420, 50))
        ImageDraw.Draw(sh).text((i * 420 + 6, 12), lab, fill=(255, 255, 0), font=font)
    sh.save(os.path.join(OUTD, "frame_diff_%.2f.png" % t_rel))


if __name__ == "__main__":
    main()
