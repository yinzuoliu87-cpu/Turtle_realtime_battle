# -*- coding: utf-8 -*-
"""gen_shell_and_spike.py —— 018 守护贝壳的半壳。

★ 2026-09-12: 【013 的放射刺已从这里删掉】 —— 改走 `tools/blender_urchinspike.py`。
  用户:「**你不是接了blender吗**」; 而且手写生成器画出来的是 2.3:1 的楞子不是刺。
  半壳还留在这里(尚未重烤, 仍在 vfx_discipline B 条台账里)。

跑法(本文件自带下采样+锁板, 不经 pixelize_sheet —— 这两张都**不是方的**,
而 pixelize_sheet 的格子必须是方的(它要支持 90° 旋转)):
  python tools/gen_shell_and_spike.py --what shell -o assets/sprites/vfx/shell-guard.png
  (013 的刺已移走: blender --background --python tools/blender_urchinspike.py -- --dirs 16)

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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--what", choices=["shell"], default="shell")
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()
    W, H = 76, 42          # ★与原 _make_shellhalf_texture 逐字相同, 调用点换算不用改
    im = shell(W, H)
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
