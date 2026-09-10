# -*- coding: utf-8 -*-
"""gen_skillring.py —— 共享技能环 `_skill_ring` 的像素素材。

跑法(两步, 与 006~011 同一条流水):
  python tools/gen_skillring.py --out C:/tmp/ring_big --px 96
  python tools/pixelize_sheet.py C:/tmp/ring_big --dirs 1 --frames 1 --cell 96 --art-h 96 \
      --palette ring -o assets/sprites/vfx/skill-ring.png

★★为什么要烤这一张(用户 2026-08-09 原话, 抄在 battle_damage.gd:662 那条注释里):
  「**又是程序生成的环？哪个商业游戏是你这么做啊**」

  被否掉的那个东西就是 `VfxTex._make_ring_texture`: 96×96 逐像素现算
  (`a = clamp(1 - |d-0.82|/0.18) * 0.6`)。按它的公式复算出来的规格是:
    · RGB 1 色(纯白, 全靠 modulate 上色)
    · **半透明像素 4184 个 / 全不透明像素 0 个**
    · alpha **148 种连续斜坡**, 峰值只有 **153/255**(公式里那个 ×0.6 封的顶)
  —— 同时踩了「不是像素画」和「淡出病」两条, 而它封着全游戏 **187 处调用**,
  任何来源给盾/放技能, 脚下都糊同一个软边圆。

★三条硬约束(每条都有由来):
  ① **必须是纯灰度**。环的颜色是各调用点用 `modulate` 决定的(金盾环/绿治疗环/蓝法环…),
     素材里带一丁点色相都会串到那 187 处上去。⇒ `--palette ring` 是 R=G=B 的板。
  ② **硬 alpha**(0/255), 靠 `pixelize_sheet.quantize_to` 在 24 处切。
     软边(反锯齿)正是被否掉的那个观感, 不许用半透明去"让它顺眼"。
  ③ **几何一字不动**: 带心仍在 d=0.82、半宽仍是 0.18。
     换的是"怎么画", 不是"画在哪" —— 187 个调用点的尺寸/位置一个都不能变。

★抖动(dither)必须按【最终像素】算 —— 与 009/010/011 同一条:
  `pixelize_sheet` 用 BOX(面积平均)缩小, 超采样分辨率上的点画会被平均成一片均匀灰,
  再被 alpha 阈值切掉。⇒ 本文件的点画用 `x // SS, y // SS` 定位, 整个 SS×SS 块同开同关。
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

SS = 6            # 超采样倍数
BAND_C = 0.82     # 环带中心(占半径的比例) —— 与旧公式逐字相同
BAND_W = 0.18     # 环带半宽             —— 与旧公式逐字相同

## ring 板(与 tools/pixelize_sheet.py 的 PALETTES["ring"] 一致, 索引 0 最亮)
P = [
    (255, 255, 255),
    (214, 214, 214),
    (170, 170, 170),
    (124, 124, 124),
]

## Bayer 4×4 有序抖动(0..15 / 16)
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def _dither(px, py, t):
    """按【最终像素】给 0..1 的阈值判据: t 越大越容易点亮。"""
    return t * 16.0 > BAYER[py % 4][px % 4]


## ★★形状上也不能是"画圆命令"。用户 2026-08-09 否的那句「又是程序生成的环」,
##   否的不只是软边 —— memory `fb-vfx-defect-families` 把「**无含义圆环与白球**」单列成一类毛病。
##   一个完美的 O 就算硬边了, 读起来还是机器画的。⇒ 加两样**手画感**:
##     ① SEG_N 个断口: 环不是连续闭合的, 是几段能量弧拼出来的;
##     ② 厚度随角度起伏: 弧段中间厚、接近断口变薄, 像笔画收尾。
##   两样都是**角度的函数**, 不带随机 —— 素材是烤死的, 每次生成逐字一样(可复现)。
SEG_N = 6          # 断口个数
SEG_GAP = 0.055    # 每个断口占多大(占一个分段的比例)
SEG_SWELL = 0.30   # 弧段中间比断口处厚多少(占带宽的比例)


def _seg_profile(ang):
    """返回这个角度上的厚度系数 0..1(0 = 断口, 1 = 弧段最厚处)。"""
    seg = math.tau / float(SEG_N)
    ph = math.fmod(ang, seg) / seg          # 0..1 在本段内的位置
    if ph < SEG_GAP or ph > 1.0 - SEG_GAP:  # 断口: 直接不画
        return 0.0
    ## 段内归一到 0..1, 用 sin 做"中间厚两头薄"
    u = (ph - SEG_GAP) / (1.0 - 2.0 * SEG_GAP)
    return 1.0 - SEG_SWELL * (1.0 - math.sin(math.pi * u))


def render(px_final):
    n = px_final * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    c = float(n - 1) / 2.0
    for y in range(n):
        for x in range(n):
            fx = float(x) - c
            fy = float(y) - c
            d = math.hypot(fx, fy) / c
            if d >= 1.0:
                continue
            prof = _seg_profile(math.atan2(fy, fx) + math.pi)
            if prof <= 0.0:
                continue                      # 断口
            t = abs(d - BAND_C) / (BAND_W * prof)   # 0 = 带心, 1 = 带边(带宽随角度起伏)
            if t >= 1.0:
                continue
            qx, qy = x // SS, y // SS
            ## 明度阶梯: 带心最亮, 往两边一档一档暗下去(**不是**连续渐变)
            if t < 0.30:
                col = P[0]
            elif t < 0.58:
                col = P[1]
            elif t < 0.80:
                col = P[2]
            else:
                ## 最外一圈用抖动打散 —— 让边缘读成"像素颗粒"而不是又一条平滑轮廓线。
                ## 越靠外越稀疏(t=0.80 几乎全亮, t→1.0 基本灭)。
                if not _dither(qx, qy, (1.0 - t) / 0.20):
                    continue
                col = P[3]
            ld[x, y] = col + (255,)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="大图输出目录(d0_f0.png)")
    ap.add_argument("--px", type=int, default=96, help="**最终**边长; 实际渲 px*SS")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    im = render(a.px)
    im.save(os.path.join(a.out, "d0_f0.png"))
    print("  ring: 渲了 1 张大图 (%dpx, 最终 %dpx)" % (a.px * SS, a.px))
    return 0


if __name__ == "__main__":
    sys.exit(main())
