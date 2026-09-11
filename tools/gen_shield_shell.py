# -*- coding: utf-8 -*-
"""gen_shield_shell.py —— 通用「获得护盾」的**单位身上**护罩(12 帧像素动画)。

跑法:
  python tools/gen_shield_shell.py -o assets/sprites/vfx/shield-shell.png

════════════════════════════════════════════════════════════════════════
 ★由来
════════════════════════════════════════════════════════════════════════
用户 2026-09-11:「**我不明白lol里获得护盾都是你这样在地上搞一下的吗**」
—— 被否的是 `_grant_shield` 末尾那行 `_skill_ring`(在**地上**画金圈, 封着 44 个给盾点)。

════════════════════════════════════════════════════════════════════════
 ★v2: 照 Dead Cells 实测结构重做
════════════════════════════════════════════════════════════════════════
v1 是我**凭空想的六棱格**, 用户看完:「特效完全不够商业游戏」。
v2 的参考源: Dead Cells 格挡护罩, t=143.0~145.5s @30fps **逐帧看过并量过**。

**四条实测结论, 每条 v1 都做反了:**

| 项 | Dead Cells 实测 | v1(凭空想的) |
|---|---|---|
| 填充 | **实心半透明圆盘** —— 平台/锁链/背景全透过来 | 空心六棱格, 靠镂空露人 |
| 出现 | **瞬间到最大** | 逐格合拢(多余的动作) |
| 层次 | 白热核 → 中间调 → **亮边环** 三层 | 只有格线一种明度 |
| 消散 | **碎成颗粒向外飞** | 格子逐个熄灭 |

★★最关键的一条: 它**靠半透明**才能"罩住但不遮住"。
  而"半透明像素必须是 0"这条规矩**是我自己定的**(`pixelize_sheet.py:171`
  「硬边: 半透的边缘直接切掉, 像素画不要羽化」, 然后被我抄进每一个生成器), 用户从没定过。
  那条规矩把**两件不同的事**混成了一条:
    · **羽化的边缘**(抗锯齿软边) —— 像素风确实不该有, 切掉是对的
    · **整片刻意的半透明填充** —— 这是"罩住但不遮住"的唯一手段, 与羽化无关
  混在一起的后果: 罩子只能做成空心格线, 而那正是被否掉的东西。
⇒ v2 用**统一 alpha 的半透明填充**: 边缘仍是硬的(不羽化), 内部透。
  alpha 只取少数几档(A_* × FADE, 共 ≤ 16 档), **不是连续渐变**。
  门禁判据相应从"必须全不透明"改成"**alpha 档数有上限**" —— 收得更准, 不是放松。

★源分辨率只有 640×360(1080p 全部 403) ⇒ **结构/节奏/遮不遮是量出来的,
  配色是按三层结构自己定的**, 不声称照它逐像素量过。

★仍然保持: 纯灰度(颜色由 44 个调用点各自 modulate) · pixel_size 固定只切帧(不连续缩放)。
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

CELL = 64
FRAMES = 12
FPS_NOTE = 24.0        # 12 帧 / 24fps = 0.50 秒(参考实测: 满态 0.33 + 消散 ≈ 0.55 秒)

## 灰度阶(纯灰 R=G=B; 颜色由调用点 modulate 决定)
C_FILL, C_SPEC, C_RIM = 235, 255, 255

## alpha 阶梯 —— 只有这几档, 不许连续渐变(那就是羽化)
## ★★ 1:1 实拍改过一次: 原来是「白热核/中间调/盘面」三段填充(照 Dead Cells 的三层),
##   但参考里那个渐变铺在 **350px** 上; 压到本项目的 **50px** 盘径后三条硬边同心环
##   读成**靶心/飞镖盘**, 而且盘面太实把龟染成黄绿。
##   ⇒ 只留**一层很淡的罩** + **亮边环** + **左上一道高光弧**(球面感靠它, 不靠同心环)。
##   教训: **参考的层次不能按个数搬, 要按它占多少像素搬** —— 尺寸不同, 能塞下的层数不同。
## ★ 1:1 实拍又改一次: A_SPEC=150 时高光弧在深底上被压成**暗褐色**
##   (金色 59% 叠暗底 = 发闷; 不用 blend_add 是既定决定 ⇒ 只能括 alpha)。
##   罩面 46 又几乎看不见 ⇒ 罩子退化成光一圈环, 跟地上那个圈只差位置。
## ★★用户 2026-09-11 拍板开 additive 后又调一次: additive 下 alpha 只决定**加多少光**,
##   **不遮挡** ⇒ 可以调得比 alpha 混合时高得多。留在 64 时: 淡金×0.25 叠黑底
##   = (64,59,40) 暗橄榄灰 —— 开了 additive 看着像没开。不是混合模式没生效, 是 alpha 太低。
A_RIM, A_SPEC, A_FILL = 255, 255, 150

DISC_R = 0.78          # ★盘面只占格子的 78% —— 剩下的留给碎屑飞出去。
#   第一版盘面填到 r=1.0, 碎屑一开始就飞出格子外 ⇒ f7 之后只剩 25/9/3/1/0 个像素(空帧)。
SHELL_H = 0.94         # 竖向略压扁
RIM_W = 0.075          # 亮边环带宽(占半径)
SPEC_A0, SPEC_HALF = 2.45, 0.62   # 高光弧: 中心角(弧度) 与半张角

## 每帧: 盘面在不在 / alpha 降到第几档 / 碎屑飞出多远(占半径)
##   f0..f4 满态(**瞬间到最大, 不合拢**) · f5..f6 盘面开始退 · f7.. 只剩碎屑外飞
DISC = [1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
ASTEP = [0, 0, 0, 0, 0, 1, 2, 2, 3, 3, 3, 3]
SHARD = [0.00, 0.00, 0.00, 0.02, 0.05, 0.10, 0.18, 0.30, 0.44, 0.58, 0.72, 0.88]
FADE = [1.00, 0.72, 0.45, 0.22]     # 4 档硬阶梯


def _hash01(i, j):
    h = (i * 73856093) ^ (j * 19349663)
    h = (h ^ (h >> 13)) & 0x7FFFFFFF
    return ((h * 1103515245 + 12345) & 0x7FFFFFFF) / float(0x7FFFFFFF)


def _a(base, step):
    return max(0, min(255, int(round(base * FADE[step]))))


def frame(k):
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    ld = img.load()
    c = (CELL - 1) / 2.0
    disc, st, sh = DISC[k], ASTEP[k], SHARD[k]

    if disc:
        for py in range(CELL):
            for px in range(CELL):
                u = (px - c) / (CELL * 0.5 - 1.0)
                v = (py - c) / (CELL * 0.5 - 1.0) / SHELL_H
                r = math.hypot(u, v) / DISC_R
                if r > 1.0:
                    continue
                ## ① 亮边环(不透明) —— 罩子最强的读数, 50px 下只有它能保证读得出
                if r > 1.0 - RIM_W:
                    ld[px, py] = (C_RIM, C_RIM, C_RIM, _a(A_RIM, st))
                    continue
                ## ② 左上一道高光弧(贴着内缘) —— 球面感靠这一道, 不靠同心环
                ang = math.atan2(-v, u)
                if r > 0.72 and abs((ang - SPEC_A0 + math.pi) % math.tau - math.pi) < SPEC_HALF:
                    ld[px, py] = (C_SPEC, C_SPEC, C_SPEC, _a(A_SPEC, st))
                    continue
                ## ③ 盘面: **单一很淡的 alpha**, 让龟保住自己的颜色
                ld[px, py] = (C_FILL, C_FILL, C_FILL, _a(A_FILL, st))

    ## ③ 碎屑: 边环碎成小方块向外飞(Dead Cells 的消散就是这个, 不是格子熄灭)
    if sh > 0.0:
        n = 40          # ★ 26 颗在 1:1(盘径 50px) 下稀得读不出是一圈碎屑
        for i in range(n):
            ang = math.tau * (i + 0.5) / n + _hash01(i, 7) * 0.22
            rr = DISC_R * (1.0 - RIM_W * 0.5) + sh * (0.26 + 0.22 * _hash01(i, 13))
            sx = int(round(c + math.cos(ang) * rr * (CELL * 0.5 - 1.0)))
            sy = int(round(c + math.sin(ang) * rr * (CELL * 0.5 - 1.0) * SHELL_H))
            sz = 3 if _hash01(i, 3) > 0.66 else 2      # 碎屑放大: 1px 在实战镜头下等于没画
            al = _a(A_RIM, min(3, st + (1 if sh > 0.45 else 0)))
            for dy in range(sz):
                for dx in range(sz):
                    x, y = sx + dx, sy + dy
                    if 0 <= x < CELL and 0 <= y < CELL:
                        ld[x, y] = (C_RIM, C_RIM, C_RIM, al)
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
    cols, alphas, per = set(), set(), [0] * FRAMES
    for y in range(CELL):
        for x in range(CELL * FRAMES):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            cols.add((r, g, b))
            alphas.add(al)
            per[x // CELL] += 1
    print("  %s  %dx%d (%d 帧 @%.0ffps = %.2f 秒)"
          % (a.out, CELL * FRAMES, CELL, FRAMES, FPS_NOTE, FRAMES / FPS_NOTE))
    print("  色数 %d   alpha 档数 %d -> %s" % (len(cols), len(alphas), sorted(alphas)))
    print("  每帧像素: %s" % per)
    return 0


if __name__ == "__main__":
    sys.exit(main())
