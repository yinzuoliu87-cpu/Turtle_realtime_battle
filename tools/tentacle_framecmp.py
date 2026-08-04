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

def crop_tent(path, prefer_lower_left, pick_upper=False):
    """裁到触手包围盒。
    prefer_lower_left: 官方图里挑左下角那根；pick_upper: 改挑【上方】那根。

    ★用户 2026-08-04：「最好上面的参考触手一起看，这样在下面触手以俯视角缩成一团时
      可以看上面吊顶」—— 对。官方画面里有两根：左下那根被俯角压扁成一团、看不出形状，
      **上面那根角度更立，形状读得清清楚楚**。所以对照图三行：官方下 / 官方上 / 我的。"""
    im = Image.open(path).convert('RGB'); W, H = im.size
    a = np.asarray(im).astype(int); r, g, b = a[:,:,0], a[:,:,1], a[:,:,2]
    lum = (g.astype(float) + b) / 2.0
    # ★★掩膜加【亮度下限】：拍击时触手过曝发白，纯"偏青"判据抓不住它，
    #   反而抓到背景里暗的草丛/苔石 ⇒ 裁出一片模糊背景（实测 f044~f054 全废）。
    #   两条路都认：① 明显偏青 ② 很亮且不偏暖（过曝的白光带）
    m = (((g > 60) & (b > 60) & (g > r + 28) & (b > r + 18) & (lum > 95))
         | ((lum > 175) & (b > r - 10)))
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
        if pick_upper:
            sc = (c.sum() / 1000.0) + 90.0 * (1.0 - cy)      # 越靠上越优先
        elif prefer_lower_left:
            sc = (c.sum() / 1000.0) + 60.0 * (cy - cx)
        else:
            sc = c.sum() / 1000.0
        if sc > bestscore: bestscore, best = sc, c
    if best is None: return None
    # ★没抓到够大的主体 ⇒ 退回整幅画面，而不是裁出一片背景冒充"触手"
    if best.sum() < (W * H) * 0.004:
        return im
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
T = 172
ks = list(range(LO, HI + 1))
C = 10; R = (len(ks) + C - 1) // C
c = Image.new('RGB', (C * (T + 4) + 4, R * (3 * T + 26) + 4), (10, 10, 14))
d = ImageDraw.Draw(c)
made = 0
for i, k in enumerate(ks):
    po = os.path.join(S, 'vid', 'wfull', '%03d.png' % (OFF_ZERO + k))
    pm = os.path.join(S, 'tt', MD, 'f_%d.png' % (MZ + k))
    if not (os.path.exists(po) and os.path.exists(pm)): continue
    lo_ = crop_tent(po, True)                  # 官方·下方那根（俯角压扁）
    up_ = crop_tent(po, False, True)           # 官方·上方那根（★形状看得清）
    me_ = crop_tent(pm, False)
    if lo_ is None or up_ is None or me_ is None: continue
    x = 4 + (i % C) * (T + 4); y = 4 + (i // C) * (3 * T + 26)
    c.paste(lo_.resize((T, T)), (x, y))
    c.paste(up_.resize((T, T)), (x, y + T))
    c.paste(me_.resize((T, T)), (x, y + 2 * T))
    d.text((x + 2, y + 3 * T + 3), "+%d f%03d" % (k, OFF_ZERO + k), font=F, fill=(200, 232, 240))
    made += 1
c.save(OUT)
print("%s  %d 帧 (行1=官方下方那根 行2=★官方上方那根(形状清楚) 行3=我的)" % (os.path.basename(OUT), made))
