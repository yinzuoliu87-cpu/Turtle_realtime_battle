# -*- coding: utf-8 -*-
"""gen_shield_shell.py —— 通用「获得护盾」的**单位身上**六棱护罩(8 帧像素动画)。

跑法(本文件自己下采样+锁板, 不经 pixelize_sheet —— 理由见下面"为什么直接按最终分辨率画"):
  python tools/gen_shield_shell.py -o assets/sprites/vfx/shield-shell.png

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-11)
════════════════════════════════════════════════════════════════════════
用户看 012 的护盾演出:

    「**我不明白lol里获得护盾都是你这样在地上搞一下的吗**」

被否的是 `battle_damage._grant_shield` 末尾那一行:

    battle._skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)

—— 在**地上**画一个金色圆环。而它封着全游戏 44 个给盾点, 于是任何来源给盾
(装备/技能/羁绊)都是"脚底下闪一下"。LoL 的 Barrier / Shield 一律是**罩在角色身上**。

★为什么不拿现成的顶替: 仓库里确实已有两张罩子 —— `shield-dome.png`(046 幽灵墨鱼
  闪避得盾)与 `fx-hex-bubble.png`(石龟岩石护盾常驻罩)。但它们**各自是那两件的招牌**,
  铁律 [[fb-no-asset-reuse-unless-told]]:「新内容一律新素材……别拿别的顶替」。
  ⇒ 通用给盾要有自己的一张。

════════════════════════════════════════════════════════════════════════
 ★为什么直接按【最终分辨率】画, 不走"超采样 + BOX 下采样"
════════════════════════════════════════════════════════════════════════
006~011 那条流水(渲 6× → BOX 缩 → alpha 阈值 → 吸回锁板)是给**有曲面/渐变**的
形体准备的。这张护罩是**纯格线**: 六棱格的棱边宽度就是 1 个最终像素。
BOX 是面积平均 —— 1 像素宽的线在 6× 图上是 6 像素, 缩回来会被邻域摊薄,
再被 alpha 24 的阈值切掉一部分 ⇒ 格线断断续续。直接在 64×64 上按
"到格边的距离 < 半像素"判, 线才是干净的 1px。

轮廓的锯齿是**要的**(像素画的硬边), 不是缺陷。

════════════════════════════════════════════════════════════════════════
 ★三条硬约束
════════════════════════════════════════════════════════════════════════
① **纯灰度**。罩子的颜色由调用点 `modulate` 决定(通用给盾=金、013海胆=紫、
   治疗盾=绿…), 素材带色相会串到每一处 —— 与 `skill-ring.png` 同一条理由。
② **硬 alpha(0/255)**, 且**格子内部是空的**。罩子必须能看见里面的龟 ——
   用半透明做"透"是被否掉的那种观感; 像素画的做法是只画棱边、内部留空。
③ **明暗只有 4 档**(ring 板)。"变暗"靠往下走一档, 不靠 alpha 渐变 —— 否则
   又是 memory `fb-vfx-defect-families` 里的【淡出病】。

★8 帧在讲什么(不是随便闪):
    f0 f1  贴着罩壳外缘的格子先亮 —— 罩子"从外面合拢"
    f2     合拢完成: 满格 + 外缘最亮(峰值)
    f3 f4  一道高光斜扫过罩面(左下 → 右上), 罩子读起来是**一个曲面**而不是一张贴纸
    f5 f6 f7  格子按同一套确定性顺序掉落, 外缘逐档变暗 —— 散开
  ⇒ 每一帧都有**内容变化**, 不是同一张图改 alpha。
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

CELL = 64          # 每帧边长(最终像素)
FRAMES = 8

## ring 板(与 tools/pixelize_sheet.PALETTES["ring"] 逐字一致, 索引 0 最亮)
P = [
    (255, 255, 255),
    (214, 214, 214),
    (170, 170, 170),
    (124, 124, 124),
]

HEX_S = 0.40       # 六棱格中心间距(归一化到罩半径 1.0)
EDGE_W = 0.020     # 棱边半宽(归一化) —— 约 1 个最终像素
RIM_W = 0.060      # 罩壳外缘环带宽度
SHELL_H = 0.92     # 罩子竖向压扁(宽 1.0 高 0.92) —— 罩住龟身而不是一个正球
CORE_R = 0.44      # ★这个半径以内**不画格线**: 罩子中间必须是空的, 否则把龟盖住了
FADE_R = 0.66      # CORE_R~FADE_R 是过渡带: 格子按确定性哈希稀疏掉落


def _centers():
    """三角点阵的中心表(六棱格 = 三角点阵的 Voronoi 图)。"""
    out = []
    n = int(2.4 / HEX_S) + 2
    for j in range(-n, n + 1):
        for i in range(-n, n + 1):
            cx = HEX_S * (i + 0.5 * j)
            cy = HEX_S * (math.sqrt(3.0) / 2.0) * j
            if abs(cx) < 1.8 and abs(cy) < 1.8:
                out.append((cx, cy, i, j))
    return out


CENTERS = _centers()


def _hash01(i, j):
    """确定性伪随机 0..1 —— 素材是烤死的, 每次生成逐字一样(可复现)。"""
    h = (i * 73856093) ^ (j * 19349663)
    h = (h ^ (h >> 13)) & 0x7FFFFFFF
    return ((h * 1103515245 + 12345) & 0x7FFFFFFF) / float(0x7FFFFFFF)


def _hex_at(u, v):
    """返回 (到格边的距离, 拥有这个点的格子 i, j, 该格子**中心**的半径)。

    ★为什么要返回中心半径: 第一版用**像素自己的半径**去判"这条棱边画不画",
      结果同一条棱边一半在里一半在外 ⇒ 画出一堆**朝内扎的 1px 断桩**(渲出来看得很清楚,
      像噪点)。改成按**格子**判 ⇒ 格子要么整个在要么整个不在, 内边界干净。"""
    best_d = 1e9
    best = None
    for (cx, cy, i, j) in CENTERS:
        d = (u - cx) ** 2 + (v - cy) ** 2
        if d < best_d:
            best_d = d
            best = (cx, cy, i, j)
    cx, cy, i, j = best
    d0 = math.hypot(u - cx, v - cy)
    edge = 1e9
    for (nx, ny, _i, _j) in CENTERS:
        if nx == cx and ny == cy:
            continue
        if math.hypot(nx - cx, ny - cy) > HEX_S * 1.2:     # 只看六个直接邻居
            continue
        edge = min(edge, (math.hypot(u - nx, v - ny) - d0) * 0.5)
    return edge, i, j, math.hypot(cx, cy)


## 每帧: 格子亮到多少 / 外缘走到第几档(0 最亮) / 高光弧在哪个角度(弧度, None=无)
FILL  = [0.34, 0.72, 1.00, 1.00, 1.00, 0.84, 0.52, 0.24]
RIMST = [1,    0,    0,    0,    0,    1,    2,    3]
SPEC  = [None, 2.45, 2.30, 2.10, 1.90, 1.72, None, None]
SPEC_HALF = 0.44   # 高光弧半张角(弧度)


def frame(k):
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    ld = img.load()
    c = (CELL - 1) / 2.0
    fill, rim_step, spec = FILL[k], RIMST[k], SPEC[k]

    for py in range(CELL):
        for px in range(CELL):
            u = (px - c) / (CELL * 0.5 - 1.0)
            v = (py - c) / (CELL * 0.5 - 1.0) / SHELL_H
            r = math.hypot(u, v)
            if r > 1.0:
                continue
            ang = math.atan2(-v, u)                       # 屏幕坐标 y 向下 ⇒ 取负号后是数学角
            ## ① 罩壳外缘: 一圈硬边 —— 罩子最强的读数就是这条轮廓
            if r > 1.0 - RIM_W:
                st = rim_step
                if spec is not None:
                    ## 高光弧: 沿着外缘跑一圈 —— 让罩子读成**球面**而不是一个圆圈
                    dphi = abs((ang - spec + math.pi) % math.tau - math.pi)
                    if dphi < SPEC_HALF:
                        st = 0
                    elif dphi < SPEC_HALF * 1.8:
                        st = min(st, 1)
                ld[px, py] = P[st] + (255,)
                continue
            ## ② 六棱格线 —— 只长在外圈, 中间留空让龟露出来
            edge, i, j, rc = _hex_at(u, v)
            if edge > EDGE_W:
                continue
            if rc < CORE_R:
                continue                                   # 整格在中间 ⇒ 不画
            if rc < FADE_R and _hash01(i, j) > (rc - CORE_R) / (FADE_R - CORE_R):
                continue                                   # 过渡带: 整格稀疏掉落
            ## 亮起顺序: 靠外缘的先亮(罩子从外面合拢), 同层用确定性哈希打散
            if (1.0 - rc) * 0.62 + _hash01(j, i) * 0.38 > fill:
                continue
            st = 2 if rc < 0.80 else 1
            if spec is not None and abs((ang - spec + math.pi) % math.tau - math.pi) < SPEC_HALF:
                st = max(0, st - 1)                        # 高光扫到的格线也亮一档
            ld[px, py] = P[st] + (255,)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()
    sheet = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
    for k in range(FRAMES):
        sheet.paste(frame(k), (k * CELL, 0))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    sheet.save(a.out)

    px = sheet.load()
    cols, semi, op = set(), 0, 0
    per = [0] * FRAMES
    for y in range(CELL):
        for x in range(CELL * FRAMES):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            if al < 255:
                semi += 1
            else:
                op += 1
                per[x // CELL] += 1
            cols.add((r, g, b))
    print("  %s  %dx%d (%d 帧)  色数 %d  半透 %d  不透明 %d"
          % (a.out, CELL * FRAMES, CELL, FRAMES, len(cols), semi, op))
    print("  每帧不透明像素: %s" % per)
    return 0


if __name__ == "__main__":
    sys.exit(main())
