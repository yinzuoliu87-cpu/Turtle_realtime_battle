# -*- coding: utf-8 -*-
"""pixelize_sheet.py — 大图渲染 → 缩小 → 重索引到【锁定调色板】→ 拼成方向表。

跑法:
  python tools/pixelize_sheet.py C:/tmp/slash_blender --dirs 4 --frames 3 \
      --cell 64 --art-h 24 --palette gold -o assets/sprites/vfx/xxx.png

★这是 2026 行业流水里最被强调、而我们**一直缺的那一步**:
    "generate large, downscale, re-index, and hand-clean"
  ——AI/渲染出来的图**从不直接进游戏**。
  (来源: 2026 年多份像素美术流水指南; 另一句是"先锁死光照方向和描边规则再批量生成"。)

★为什么必须锁调色板(2026-09-06 实测):
  全项目用色量出来是这样的 ——
    龟立绘   单帧 11,698 色   (247x199, 游程长度 99% 为 1 = 完全没有色块结构)
    技能图标 中位 56,270 色
    装备图标 中位     44 色
    特效     中位     57 色
  ⇒ **两种美术混在同一个画面里**: 全彩绘制的龟 + 真像素画的图标/特效。
    这不是"某个素材做得不好", 是**风格根本不统一** —— 特效做得再准也贴不上去。
  成熟像素项目的做法是**全项目共用一套受限调色板**, 而且**带索引顺序**
  (index 0 = 描边, index 1 = 主色 …), 这样运行时换索引就能出配色变体。
"""
import argparse
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

## ── 锁定调色板 ─────────────────────────────────────────────
## ★索引有意义, 别乱调顺序: 0=最亮的刃缘 … 末尾=最暗的尾 wash。
##   数值取自 LoL 参考帧实测的横截面分层(见 tools/vfx_lol_profile.py 头注),
##   换成本项目的暖金色相。
PALETTES = {
    "gold": [
        ## ★★亮度阶梯照抄 LoL 参考帧实测: 237 / 210 / 189 / 140 / 95 / 65。
        ##   第一版我随手配了 (255,224,140) 当 1 号色, 它亮度 225 —— **判据里"白"是亮度>215**,
        ##   于是六色里有两色被算成白, white_pct 卡在 32% 下不来(参考 12.4%)。
        ##   ⇒ 配色不能只看"好不好看", 要卡在判据用的那个量上。
        (245, 238, 205),   # 亮度 236.8  ← LoL 档 237
        (250, 208, 110),   # 亮度 210.8  ← LoL 档 210
        (240, 185,  80),   # 亮度 191.0  ← LoL 档 189
        (195, 128,  40),   # 亮度 139.3  ← LoL 档 140
        (150,  85,  28),   # 亮度  98.8  ← LoL 档 95
        (110,  58,  18),   # 亮度  69.6  ← LoL 档 65
    ],
    ## 血色: 给流血/出血类效果。亮度阶梯与 gold 同口径(237/210/189/140/95/65 的相对关系),
    ## 只换色相 —— 这样两套板放同一画面里明暗层级是一致的。
    "blood": [
        (255, 214, 208),   # 亮度 219  溅点高光
        (255, 150, 140),   # 亮度 190  浅血
        (232,  70,  62),   # 亮度 118  主血色
        (176,  34,  34),   # 亮度  75  暗血
        (110,  20,  24),   # 亮度  47  深红
        ( 62,  12,  16),   # 亮度  27  近黑红
    ],
}


def quantize_to(im, pal):
    """重索引到给定调色板。**保留 alpha**, 只对彩色通道做最近邻映射。"""
    im = im.convert("RGBA")
    px = im.load()
    W, H = im.size
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    op = out.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a < 24:
                continue                      # 硬边: 半透的边缘直接切掉, 像素画不要羽化
            best, bd = pal[0], 1 << 30
            for c in pal:
                d = (r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2
                if d < bd:
                    bd, best = d, c
            op[x, y] = (best[0], best[1], best[2], 255)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="Blender 渲出来的大图目录(d{i}_f{j}.png)")
    ap.add_argument("--dirs", type=int, default=4)
    ap.add_argument("--frames", type=int, default=3)
    ap.add_argument("--cell", type=int, default=64, help="方格边长(为 90° 旋转必须是方的)")
    ap.add_argument("--art-h", type=int, default=24, help="本体缩到多高(不是格高)")
    ap.add_argument("--palette", default="gold")
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()

    pal = PALETTES[a.palette]
    sheet = Image.new("RGBA", (a.cell * a.dirs, a.cell * a.frames), (0, 0, 0, 0))
    n = 0
    for d in range(a.dirs):
        for f in range(a.frames):
            p = os.path.join(a.src, "d%d_f%d.png" % (d, f))
            if not os.path.exists(p):
                print("[FAIL] 缺帧: %s" % p)
                return 1
            big = Image.open(p).convert("RGBA")
            ## ① 缩小: 用 BOX(面积平均), 不是 NEAREST —— 大图缩小时 NEAREST 会丢细节、抖动。
            ##    抗锯齿留下的中间色随后由 ② 重索引吃掉, 所以不会糊。
            small = big.resize((max(1, int(big.width * a.art_h / big.height)), a.art_h), Image.BOX)
            ## ② 重索引到锁定调色板 + 硬边
            small = quantize_to(small, pal)
            ## ③ 垫进方格(90° 旋转要方的)
            cell = Image.new("RGBA", (a.cell, a.cell), (0, 0, 0, 0))
            cell.paste(small, ((a.cell - small.width) // 2, (a.cell - small.height) // 2))
            sheet.paste(cell, (d * a.cell, f * a.cell))
            n += 1
    if n == 0:
        print("[FAIL] 一帧都没处理 —— 空表不是通过")
        return 1
    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    sheet.save(a.out)
    print("  %s  %dx%d = %d 方向 × %d 帧 (分母: 处理了 %d 帧)"
          % (a.out, sheet.width, sheet.height, a.dirs, a.frames, n))
    print("  调色板 '%s' 共 %d 色(锁定·索引有序)" % (a.palette, len(pal)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
