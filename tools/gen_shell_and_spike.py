# -*- coding: utf-8 -*-
"""gen_shell_and_spike.py —— 018 守护贝壳的半壳 / 013 炙烤海胆的放射刺。

跑法(本文件自带下采样+锁板, 不经 pixelize_sheet —— 这两张都**不是方的**,
而 pixelize_sheet 的格子必须是方的(它要支持 90° 旋转)):
  python tools/gen_shell_and_spike.py --what shell -o assets/sprites/vfx/shell-guard.png
  python tools/gen_shell_and_spike.py --what spike -o assets/sprites/vfx/urchin-spike.png

★为什么重烤这两张(2026-09-11 从 Godot 里**导出真产物**逐像素量的, 不是读源码猜):

  | 贴图                              | 尺寸  | 色数 | 半透 | 不透明 |
  |-----------------------------------|------|-----|------|-------|
  | `VfxTex._make_glow_texture`(013刺) | 96×96|   1 | 7004 |     0 |
  | `VfxTex._make_shellhalf_texture`(018) | 76×42| 706 |  159 |  2693 |

  · **glow**: 纯白 + 连续 alpha 衰减, 一个不透明像素都没有 —— 就是 memory
    `fb-vfx-defect-families` 里「无含义圆环与**白球**」那一类。
    而且 013 要射的是**海胆刺**, 拿一颗圆光球当刺, 形状本身就不对。
  · **shellhalf**: 形状是认真画的(半穹顶 + 放射壳沟 + 奶金壳缘 + 深描边, 保留),
    坏在**颜色是连续插值出来的** ⇒ 706 色。

★两张都保持**原尺寸**(76×42 / 刺 28×10), 调用点的 `pixel_size` 换算一个字都不用改。
★抖动按最终像素算(`x // SS`), 与 009/010/011/环 同一条。
"""
import argparse
import math
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

SS = 6

## 玉青板(与 pixelize_sheet.PALETTES["jade"] 一致) + 奶金壳缘
JADE = [(238, 250, 240), (184, 232, 200), (110, 200, 148), (58, 150, 104), (32, 96, 72), (16, 54, 44)]
RIM = (255, 235, 174)      # 奶金壳缘 —— 原实现的 rim 色, 保留
## 海胆紫(与 013 的 Color(0.80,0.32,0.94) 同色系; 刺自己带色, 不靠 modulate)
VIOLET = [(245, 232, 255), (214, 170, 250), (176, 108, 232), (128, 60, 190), (74, 28, 118)]

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def _dither(px, py, t):
    return t * 16.0 > BAYER[py % 4][px % 4]


def _finish(big, W, H, pal):
    """BOX 缩到最终尺寸 + 硬 alpha + **最近邻吸回锁定调色板**。

    ★三步缺一不可。第一版我只做了前两步(切 alpha), 结果 BOX 的面积平均把颜色
      插成了中间色 —— 壳 **355 色**、刺 **75 色**, 离"≤8 色"差着两个数量级。
      `pixelize_sheet.quantize_to` 之所以能出 ≤8 色, 靠的正是第三步。
    """
    small = big.resize((W, H), Image.BOX)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sp, op = small.load(), out.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = sp[x, y]
            if a < 24:
                continue
            best, bd = pal[0], 1 << 30
            for c in pal:
                d = (r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2
                if d < bd:
                    bd, best = d, c
            op[x, y] = (best[0], best[1], best[2], 255)
    return out


# ── 018 守护贝壳: 扇贝半壳(铰链在下缘, 穹顶朝上) ──────────────────────
## 形状**照搬原实现的设计**(半穹顶 / 横向压扁 / 放射壳沟 / 奶金壳缘 / 深描边),
## 只把"连续插值的颜色"换成锁定色阶。
def shell(W, H):
    n_w, n_h = W * SS, H * SS
    img = Image.new("RGBA", (n_w, n_h), (0, 0, 0, 0))
    ld = img.load()
    cx = float(n_w) * 0.5
    hy = float(n_h) - 1.0
    rad = float(n_h) - 2.0 * SS
    for y in range(n_h):
        for x in range(n_w):
            dx = float(x) - cx
            dy = hy - float(y)
            if dy < 0.0:
                continue
            d = math.sqrt(dx * dx * 0.30 + dy * dy)
            if d > rad:
                continue
            ang = math.atan2(dy, dx * 0.55)
            t = d / rad                       # 0=铰链 1=外缘
            edge = max(0.0, min(1.0, math.sin(ang) * 2.6))
            if edge <= 0.02:
                continue
            qx, qy = x // SS, y // SS
            ## 外缘: 一圈奶金 + 描边
            if t > 0.94:
                ld[x, y] = JADE[5] + (255,)
                continue
            if t > 0.84:
                ld[x, y] = RIM + (255,)
                continue
            ## 放射壳沟: 9 条, 沟里暗一档
            rib = math.cos(9.0 * ang)
            if rib > 0.72:
                col = JADE[1] if t < 0.55 else JADE[2]      # 沟脊(亮)
            elif rib < -0.72:
                col = JADE[4]                                # 沟底(暗)
            else:
                col = JADE[2] if t < 0.62 else JADE[3]
            ## 顶部一条高光(壳的受光面)
            if 0.30 < t < 0.62 and abs(ang - math.pi * 0.5) < 0.42 and rib > 0.0:
                col = JADE[0]
            ## 铰链附近压暗, 让"合拢处"读得出来
            if t < 0.16:
                col = JADE[5]
            ## 最外那一圈用抖动收边, 避免又是一条平滑轮廓
            if t > 0.80 and not _dither(qx, qy, (0.94 - t) / 0.14):
                continue
            ld[x, y] = col + (255,)
    return _finish(img, W, H, JADE + [RIM])


# ── 013 炙烤海胆: 放射刺(预烤 16 个方向, 尖朝外) ────────────────────
## ★原来这里用的是 `_make_glow_texture` —— 一颗**圆光球**。
##   013 的效果是「满层时放射 12 根海胆刺」, 拿圆球当刺, 形状本身就不对。
## ★★为什么要**预烤方向**而不是运行时转: 刺是贴地精灵(axis=AXIS_Y),
##   被任意角旋转会重采样, 像素网格当场碎 —— 010 激光长刃那一轮就是栽在
##   `rotation = Vector3(0, -ang, 0)` 上。⇒ 16 向烤进素材, 运行时 `rotation` 恒 0,
##   只选帧。方向由 `_ground_dir_frame(dir, 16)` 决定, 与判定/移动方向同一套口径。
SPIKE_LEN = 0.86      # 刺长(占半格)
SPIKE_HALF = 0.17     # 根部半宽(占半格)


def spike_cell(px_final, ang):
    n = px_final * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    ca, sa = math.cos(ang), math.sin(ang)
    for y in range(n):
        for x in range(n):
            ux = (x + 0.5) / n * 2.0 - 1.0
            vy = (y + 0.5) / n * 2.0 - 1.0
            ## 转到刺的局部坐标: s 沿刺(0=根 1=尖), p 垂直于刺
            s_ = (ux * ca + vy * sa) / SPIKE_LEN
            p_ = (-ux * sa + vy * ca)
            if s_ < 0.0 or s_ > 1.0:
                continue
            half = SPIKE_HALF * (1.0 - s_) ** 0.72
            if half <= 0.0 or abs(p_) > half:
                continue
            qx, qy = x // SS, y // SS
            t = abs(p_) / max(1e-6, half)
            if s_ > 0.90:
                col = VIOLET[0]
            elif t < 0.28:
                col = VIOLET[1]
            elif t < 0.66:
                col = VIOLET[2]
            elif t < 0.90:
                col = VIOLET[3]
            else:
                if not _dither(qx, qy, (1.0 - t) / 0.10):
                    continue
                col = VIOLET[4]
            ld[x, y] = col + (255,)
    return _finish(img, px_final, px_final, VIOLET)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--what", choices=["shell", "spike"], required=True)
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()
    if a.what == "shell":
        W, H = 76, 42          # ★与原 _make_shellhalf_texture 逐字相同, 调用点换算不用改
        im = shell(W, H)
    else:
        CELL, DIRS = 32, 16
        W, H = CELL * DIRS, CELL
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for k in range(DIRS):
            im.paste(spike_cell(CELL, math.tau * k / DIRS), (k * CELL, 0))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    im.save(a.out)
    px = im.load()
    cols, semi, op = set(), 0, 0
    for y in range(H):
        for x in range(W):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            if al < 255:
                semi += 1
            else:
                op += 1
            cols.add((r, g, b))
    print("  %s  %dx%d  色数 %d  半透 %d  不透明 %d" % (a.out, W, H, len(cols), semi, op))
    return 0


if __name__ == "__main__":
    sys.exit(main())
