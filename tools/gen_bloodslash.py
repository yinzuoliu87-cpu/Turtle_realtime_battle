# -*- coding: utf-8 -*-
"""gen_bloodslash.py — 011「饮血护符坠」的两件素材: 连斩斩痕 / 图标。

跑法(两步, 与 006/007/008/009/010 同一条流水):
  python tools/gen_bloodslash.py --out C:/tmp/bs_slash --mode slash --vars 4 --frames 5 --px 64
  python tools/pixelize_sheet.py C:/tmp/bs_slash --dirs 4 --frames 5 --cell 64 --art-h 64 \
      --palette blood -o assets/sprites/vfx/eq011-slash.png
  python tools/gen_bloodslash.py --out C:/tmp/bs_icon --mode icon --px 32
  python tools/pixelize_sheet.py C:/tmp/bs_icon --dirs 1 --frames 1 --cell 32 --art-h 32 \
      --palette blood -o assets/sprites/equip/eq011-icon.png

★★这一版是**照着现状实拍 100 帧逐帧重写的**(见 docs/studies/20260910c-011饮血连斩现状逐帧.md)。
  旧斩痕是 `VfxTex._make_slash_sheet` 程序生成的 220×44, **92 色 / 1938 个半透像素**;
  旧图标 `blood-amulet.png` 64×64 / **71 色 / 3721 半透**。两张都不是像素画。

★旧演出逐帧看出来的三条素材侧真毛病(每条对应下面一处):
  1. **淡出病** —— 逐帧含 alpha 平均亮度 49.5 / 81.6 / 81.6 / 49.4 / **24.8**,
     末帧只有峰值的 30%、最大 alpha 只有 71/255 ⇒ 黑地上读成一抹暗棕。
     ⇒ 本版消散**靠碎不靠淡**: 颜色阶梯五帧不变, 靠格子开洞退场(010 同一条)。
  2. **5 帧只有 4 帧不同** —— 帧 1 与帧 2 **逐像素相同**(`env` 两帧同为 1.0,
     而断裂判据 `tt > 0.5` 对两帧都不成立)。⇒ 本版五帧是**画进去的五个阶段**:
     切入 → 拉长 → 满弧 → 咬缺口 → 只剩碎片, 任意两帧都不相同。
  3. **一张图闪八次** —— 连斩 8 刀用的是同一张贴图(只随机翻转)。
     ⇒ 本版烤 **4 个刀路变体**, 连斩时按刀序轮换, 读起来才是「一刀接一刀」。

★抖动(dither)必须按【最终像素】算, 不能按超采样像素算 —— 与 009/010 同一条:
  `pixelize_sheet` 用 BOX(面积平均)缩小, 超采样分辨率上的点画会被平均成一片均匀灰。
  ⇒ 本文件所有点画都用 `x // SS, y // SS` 定位, 让整个 SS×SS 块同开同关。
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

CELL = 64          # 最终格边长
SS = 6             # 超采样倍数
FRAMES = 5
VARIANTS = 4

## blood 板(与 tools/pixelize_sheet.py 的 PALETTES["blood"] 一致, 索引 0 最亮)
P = [
    (255, 214, 208),   # 0 亮度 219  刃芯高光
    (255, 150, 140),   # 1 亮度 190  浅血
    (232,  70,  62),   # 2 亮度 118  主血色
    (176,  34,  34),   # 3 亮度  75  暗血
    (110,  20,  24),   # 4 亮度  47  深红
    ( 62,  12,  16),   # 5 亮度  27  近黑红
]

## Bayer 4×4 有序抖动(0..15 / 16)
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

## 四个刀路(屏幕空间角度, 度)。四条角度**互相差得足够开**, 连着放才读得出是四刀不同的路。
VAR_ANG = [-45.0, -138.0, -12.0, -74.0]
BOW = 0.20         # 弧弯(占半格的比例) —— sabre 那种外凸
TH = 0.115         # 满弧时的最大半厚(占半格的比例)
## 每一帧画到 along 的哪里 / 用多厚 / 断裂到什么程度
FR_END = [0.38, 0.68, 1.00, 1.00, 1.00]
FR_TH = [0.72, 0.92, 1.00, 0.94, 0.80]
FR_BREAK = [None, None, None, 0.15, -0.45]   # None = 不断; 数值越小碎得越狠


def _dither(px, py, t):
    """按【最终像素】给一个 0..1 的阈值判据: t 越大越容易点亮。"""
    return t * 16.0 > BAYER[py % 4][px % 4]


def render_cell(vi, f, px):
    """渲一格(变体 vi, 帧 f)的大图。"""
    n = px * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    ang = math.radians(VAR_ANG[vi])
    ca, sa = math.cos(ang), math.sin(ang)
    end = FR_END[f]
    thm = FR_TH[f]
    brk = FR_BREAK[f]
    half = n * 0.5
    for y in range(n):
        for x in range(n):
            u = (x + 0.5 - half) / half
            v = (y + 0.5 - half) / half
            s = u * ca + v * sa
            p = -u * sa + v * ca
            along = (s + 1.0) * 0.5
            if along < 0.05 or along > 0.95:
                continue
            if along > end:
                continue
            ## 断裂: 后两帧沿弧长开洞。★用 along 定位 ⇒ 洞是**沿刀路**的, 读成"斩痕断开"
            ##   而不是"随机噪点"。
            if brk is not None and math.sin(along * 29.0 + 1.7) > brk:
                continue
            bow = BOW * math.sin(math.pi * along)
            d = p - bow
            th = TH * thm * pow(max(1e-6, math.sin(math.pi * along)), 0.55)
            ad = abs(d)
            if ad > th * 1.45:
                continue
            px_q, py_q = x // SS, y // SS
            if ad <= th:
                r = ad / th
                if r < 0.24:
                    col = P[0]
                elif r < 0.46:
                    col = P[1]
                elif r < 0.72:
                    col = P[2]
                else:
                    col = P[3]
            else:
                ## 外圈红晕: 一格宽的抖动 halo, 让它读成"发光"而不是"贴纸"
                g = 1.0 - (ad - th) / (th * 0.45)
                if not _dither(px_q, py_q, g * 0.85):
                    continue
                col = P[4]
            ld[x, y] = col + (255,)
    return img


def render_icon(px):
    """32×32 血滴吊坠: 顶上一个链环, 下面一颗水滴形血石。"""
    n = px * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    for y in range(n):
        for x in range(n):
            u = (x + 0.5) / n * 2.0 - 1.0      # -1..1
            v = (y + 0.5) / n * 2.0 - 1.0
            col = None
            ## 链环: 圆心 (0, -0.66), 外径 0.20 内径 0.11
            rr = math.hypot(u, v + 0.66)
            if 0.11 <= rr <= 0.20:
                col = P[4] if rr > 0.175 or rr < 0.125 else P[3]
            ## 水滴血石: **上尖下圆**(挂在链环上的一滴血)。
            ## ★第一版写成 `w = sin(pi*(0.18+0.82t))^0.85`, 渲出来最宽处在 39% 然后收成**下尖** ——
            ##   那是个倒过来的水滴, 读作"宝石"不是"血滴"。⇒ 拆成两段:
            ##   下 38% 是个**圆**(半径 R, 圆心 t=0.62), 上面一段是从尖到圆最宽处的**直锥**。
            if col is None:
                t = (v + 0.42) / 1.24            # 0 在石头顶尖, 1 在底
                if 0.0 <= t <= 1.0:
                    R = 0.42
                    if t >= 0.62:
                        k = (t - 0.62) / 0.38
                        w = R * math.sqrt(max(0.0, 1.0 - k * k))
                    else:
                        w = R * (t / 0.62)
                    au = abs(u)
                    if au <= w:
                        e = au / max(1e-6, w)
                        if e > 0.86:
                            col = P[5]           # 描边
                        elif u < -w * 0.30 and t < 0.55:
                            col = P[0] if (u < -w * 0.62 and t < 0.40) else P[1]  # 左上高光
                        elif e > 0.58:
                            col = P[4]
                        else:
                            col = P[2] if t < 0.72 else P[3]
            if col is not None:
                ld[x, y] = col + (255,)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="大图输出目录(d{i}_f{j}.png)")
    ap.add_argument("--mode", choices=["slash", "icon"], required=True)
    ap.add_argument("--vars", type=int, default=VARIANTS)
    ap.add_argument("--frames", type=int, default=FRAMES)
    ap.add_argument("--px", type=int, default=CELL,
                    help="**最终**格边长; 实际渲 px*SS 再交给 pixelize_sheet")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    n = 0
    if a.mode == "icon":
        render_icon(a.px).save(os.path.join(a.out, "d0_f0.png"))
        n = 1
        print("  icon: 渲了 1 张大图 (%dpx)" % (a.px * SS))
    else:
        for vi in range(a.vars):
            for f in range(a.frames):
                render_cell(vi, f, a.px).save(os.path.join(a.out, "d%d_f%d.png" % (vi, f)))
                n += 1
        print("  slash: 渲了 %d 张大图 (%d 变体 x %d 帧, 每张 %dpx)"
              % (n, a.vars, a.frames, a.px * SS))
    if n == 0:
        print("[FAIL] 一张都没渲 —— 空目录不是通过")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
