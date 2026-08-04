# -*- coding: utf-8 -*-
"""逐帧形状对照工具 —— 官方 vs 我的，**自动裁到触手包围盒 + 归一化尺寸**。
★为什么要归一化裁切：两边相机角度/距离/取景都不同，直接并排比"大小和位置"没意义，
  能比的是【形状】。裁到各自的触手包围盒再统一缩放，形状差异才暴露出来。
用法: python framecmp.py <scratchpad> <mine_dir> <mine_zero> <lo> <hi> <out.png>
      mine_zero = 我的 WARN 起始帧号（对齐官方 f009）
"""
import sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
from PIL import Image, ImageDraw, ImageFont
import numpy as np
from scipy import ndimage

S, MD, MZ, LO, HI, OUT = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
OFF_ZERO = 9          # 官方 f009 = 预警起

def crop_tent(path, prefer_lower_left):
    """裁到触手包围盒。prefer_lower_left: 官方图里要挑左下角那根。"""
    im = Image.open(path).convert('RGB'); W, H = im.size
    a = np.asarray(im).astype(int); r, g, b = a[:,:,0], a[:,:,1], a[:,:,2]
    m = (g > 60) & (b > 60) & (g > r + 28) & (b > r + 18)
    m[:int(H * 0.16)] = False                      # 砍掉顶部 HUD/血条
    lab, n = ndimage.label(m)
    if n == 0:
        return None
    best, bestscore = None, -1e9
    for i in range(1, n + 1):
        c = (lab == i)
        if c.sum() < 60: continue
        ys, xs = np.nonzero(c)
        cx, cy = xs.mean() / W, ys.mean() / H
        # 官方：挑左下角那根；我的：挑面积最大的
        sc = (c.sum() / 1000.0) + (60.0 * (cy - cx) if prefer_lower_left else 0.0)
        if sc > bestscore: bestscore, best = sc, c
    if best is None: return None
    ys, xs = np.nonzero(best)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    pad = int(max(x1 - x0, y1 - y0) * 0.22) + 6
    box = (max(0, x0 - pad), max(0, y0 - pad), min(W, x1 + pad), min(H, y1 + pad))
    # 摆正成正方形，避免拉伸变形
    bw, bh = box[2] - box[0], box[3] - box[1]
    side = max(bw, bh)
    cx0 = (box[0] + box[2]) // 2; cy0 = (box[1] + box[3]) // 2
    sq = (max(0, cx0 - side // 2), max(0, cy0 - side // 2),
          min(W, cx0 + side // 2), min(H, cy0 + side // 2))
    return im.crop(sq)

try: F = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
except Exception: F = ImageFont.load_default()
T = 190
ks = list(range(LO, HI + 1))
C = 10; R = (len(ks) + C - 1) // C
c = Image.new('RGB', (C * (T + 4) + 4, R * (2 * T + 26) + 4), (10, 10, 14))
d = ImageDraw.Draw(c)
made = 0
for i, k in enumerate(ks):
    po = os.path.join(S, 'vid', 'wfull', '%03d.png' % (OFF_ZERO + k))
    pm = os.path.join(S, 'tt', MD, 'f_%d.png' % (MZ + k))
    if not (os.path.exists(po) and os.path.exists(pm)): continue
    o = crop_tent(po, True); m = crop_tent(pm, False)
    if o is None or m is None: continue
    x = 4 + (i % C) * (T + 4); y = 4 + (i // C) * (2 * T + 26)
    c.paste(o.resize((T, T)), (x, y))
    c.paste(m.resize((T, T)), (x, y + T))
    d.text((x + 2, y + 2 * T + 3), "+%d f%03d" % (k, OFF_ZERO + k), font=F, fill=(200, 232, 240))
    made += 1
c.save(OUT)
print("%s  %d 帧 (上=官方 下=我的, 各自裁到触手包围盒并归一化)" % (os.path.basename(OUT), made))
