# -*- coding: utf-8 -*-
"""036 温泉蛋【孵化升一级】的新素材 (2026-09-13)。

用户 2026-09-13:「你复用素材了, 你凭什么敢?」「你用素材的时候 036, 有没有直接拿旧素材做」。
—— 说中了。`_egg_level_up_vfx` 原来是三样现成货拼的:
  ① `_skill_ring(...)`                         程序生成的圆环(禁区)
  ② `VfxTex._make_fire_glow_tex()` 当"金光柱"   程序光球(禁区)
  ③ `_gold_chunk_erupt(...)` × 5               **直接拿 gold-chunk.png** —— 那是【034 大熊】的素材
而我上一轮做 036 时**根本没读这个函数**: 录制里没拍到升级, 就登记成"台子窗口不够长",
把一个真缺陷当成拍摄问题放过了。⇒ 这一张是 036 自己的素材。

★形状要说的是「**温泉蛋孵化**」而不是"又一次金光":
  蛋壳从中间裂开 → 壳片往两侧翻 → 里面涌出温泉的**热气柱** → 热气升腾散开。
  金色只用在裂缝透出的那一线(那是"孵化"这件事本身), 不做满屏金。
★尺子: 1 texel = 0.0426 m = 1.775 码。22×34 texel = 39 × 60 码。
"""
import os, math
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

OUTL = (58, 46, 38, 255)     # 描边
SH_D = (176, 152, 118, 255)  # 蛋壳暗面
SH_M = (222, 206, 172, 255)  # 蛋壳
SH_L = (248, 240, 216, 255)  # 蛋壳受光
ST_D = (120, 168, 186, 255)  # 蒸汽暗
ST_M = (186, 222, 232, 255)  # 蒸汽
ST_L = (236, 250, 252, 255)  # 蒸汽亮
GL = (255, 214, 120, 255)    # 裂缝金光
GW = (255, 248, 214, 255)    # 金光芯
CLR = (0, 0, 0, 0)

CW, CH, CN = 22, 34, 8
GROUND = CH - 1
CX = CW // 2
# 壳片往两侧翻开多少(texel) / 热气柱高度(相对全高)
OPEN = [0.0, 1.0, 2.5, 4.0, 5.0, 5.6, 6.0, 6.0]
STEAM = [0.00, 0.12, 0.38, 0.66, 0.86, 1.00, 0.92, 0.70]
FADE = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.85, 0.55]   # 只在最后两帧淡(不做"一出生就淡出")


def _px(im, x, y, c, a=1.0):
    if not (0 <= x < im.width and 0 <= y < im.height):
        return
    if a < 1.0:
        c = (c[0], c[1], c[2], int(c[3] * a))
    im.putpixel((x, y), c)


def _shell_half(im, ox, sgn, open_px, a):
    """半片蛋壳: 立在地上, 顶端往外翻 open_px。"""
    w = 6
    h = 9
    for k in range(h):
        lean = int(round(open_px * (k / float(h - 1))))
        y = GROUND - k
        x0 = CX + sgn * 2 + sgn * lean
        for j in range(w):
            x = x0 + sgn * j
            t = j / float(w - 1)
            c = SH_L if t < 0.3 else (SH_M if t < 0.72 else SH_D)
            if k >= h - 2 and (j + k) % 2 == 0:
                c = SH_D                       # 断口: 顶端啃出锯齿
            _px(im, ox + x, y, c, a)
        _px(im, ox + x0 - sgn, y, OUTL, a)
        _px(im, ox + x0 + sgn * w, y, OUTL, a)
    for j in range(w):                          # 壳口那一条断线
        _px(im, ox + CX + sgn * 2 + sgn * (open_px + j), GROUND - h, OUTL, a)


def bake():
    im = Image.new("RGBA", (CW * CN, CH), CLR)
    for f in range(CN):
        ox = f * CW
        a = FADE[f]
        open_px = int(round(OPEN[f]))
        st = STEAM[f]
        ## 热气: 一串**鼓起来的团**往上叠, 越高越大越散。
        ## ★第一版按"每行一个半宽 + 按行挖空"画, 并排渲出来是**一摞横条**(像个杯子) ——
        ##   挖空的图案沿 x 对齐了整行。改成叠圆团 + 不对齐行的噪声挖空。
        if st > 0.0:
            base_y = GROUND - 9
            n_puff = 4
            for pi in range(n_puff):
                frac = (pi + 1) / float(n_puff)
                if frac > st + 0.18:
                    break
                rise = (CH - 13) * st * frac
                pr = 2.2 + 2.6 * frac
                pcx = CX + int(round(math.sin(frac * 3.4 + f * 0.7) * 2.0))
                pcy = base_y - rise
                for y in range(int(pcy - pr) - 1, int(pcy + pr) + 2):
                    for x in range(int(pcx - pr) - 1, int(pcx + pr) + 2):
                        dx = (x - pcx) / pr
                        dy = (y - pcy) / (pr * 0.86)
                        d2 = dx * dx + dy * dy
                        if d2 > 1.0:
                            continue
                        if (x * 7 + y * 11 + f * 5) % (4 if frac > 0.6 else 9) == 0:
                            continue                  # 越高挖得越狠 = 越散
                        c = ST_L if d2 < 0.30 else (ST_M if d2 < 0.72 else ST_D)
                        _px(im, ox + x, y, c, a)
        ## 蛋壳两半
        _shell_half(im, ox, -1, open_px, a)
        _shell_half(im, ox, 1, open_px, a)
        ## 壳缝里透出的金光(只有一线, 不做满屏金)
        if f >= 1:
            gh = 3 + open_px
            for k in range(gh):
                y = GROUND - k
                _px(im, ox + CX, y, GW, a)
                _px(im, ox + CX - 1, y, GL, a)
                _px(im, ox + CX + 1, y, GL, a)
        ## 崩出去的壳片: 两小块往两侧上方飞
        if 1 <= f <= 5:
            age = (f - 1) / 4.0
            for sgn in (-1, 1):
                sx = CX + sgn * (5 + int(round(age * 6)))
                sy = GROUND - 10 - int(round(math.sin(age * math.pi) * 7))
                for j in range(2):
                    _px(im, ox + sx + sgn * j, sy, SH_M, a)
                    _px(im, ox + sx + sgn * j, sy + 1, SH_D, a)
                _px(im, ox + sx - sgn, sy, OUTL, a)
    p = os.path.join(OUT, "egg-hatch-levelup.png")
    im.save(p)
    return p, im


if __name__ == "__main__":
    p, im = bake()
    print("  egg-hatch-levelup.png  %dx%d = %d 帧 × %dx%d" % (im.width, im.height, CN, CW, CH))
    for f in range(CN):
        cell = im.crop((f * CW, 0, (f + 1) * CW, CH))
        px = list(cell.getdata())
        op = [q for q in px if q[3] > 0]
        br = [q for q in op if (q[0] + q[1] + q[2]) / 3.0 >= 110]
        print("    f%d 不透明 %3d (%.0f%%)  亮/不透明 = %.2f"
              % (f, len(op), 100.0 * len(op) / len(px), (len(br) / len(op)) if op else 0.0))
    print("→", p)
