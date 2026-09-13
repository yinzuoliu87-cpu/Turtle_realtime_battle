# -*- coding: utf-8 -*-
"""037 蛋糕蜡烛【燃烧阶段】的爆炸 —— 照真参考逐帧量出来的包络做 (2026-09-13)。

════════════════════════════════════════════════════════════════════════
 三轮返工的账
════════════════════════════════════════════════════════════════════════
用户①:「燃烧阶段不合适, 应该是**有火炎从中间爆开**, 有命中特效, 像烟雾那种感觉但是火焰」
用户②:「额, **没用 blender ?** **没符合实际爆炸范围?** **爆炸和命中是一回事吗**」
用户③:「？这就是你的结果？很差啊, **爆炸特效都不会做吗, 网上也不会看吗**」

③ 之后才去找了真参考并**逐帧量**(OpenGameArt CC0 `explosion1_6.png`, 100×100 × 50 帧,
BenHickling, **只量不用**)。量完才知道我前面几版错在哪 —— 不是"手艺差", 是**做反了**:

| 阶段          | 参考帧 | 亮像素(≥200) | 暗像素(≤60) | 半径        |
|---------------|--------|--------------|-------------|-------------|
| 纯白闪        | 0–2    | **99%**      | 0%          | 20          |
| 辐射尖刺      | 3–6    | 82%          | 15%         | **冲到 47 又缩回 31** |
| 二次点火      | 7–9    | 94%          | 2%          | 收回 24     |
| 火球长大      | 10–22  | 76→34%       | 8→24%       | 24→34       |
| 转烟          | 23–31  | 27→2%        | 30→**79%**  | 不再扩      |
| 纯烟碎裂      | 32–45  | 0%           | **100%**    | 半径不动, **靠像素数掉** |

⇒ 三条硬事实:
  A. 开头是**一记纯白闪 + 辐射尖刺**, 不是慢慢长大的橙球;
  B. 半径**先冲后缩**(f4 到 47, f8 回到 26), 不是单调增;
  C. **后 40% 的帧全是烟**(暗像素 100%), 而且消散靠**像素碎裂**(面积掉)不是半径扩大。
  参考全表只有 **8 色**, **44% 的像素亮度 ≤ 40**(烟 + 暗红), 亮度分布是**双峰**
  (p25=35 / p75=245)——硬对比, 不是渐变。我前面几版的板子里**一个烟色都没有**,
  整团全是亮橙 ⇒ 这就是"很差""平"的根源。

★为什么这一版不走 Blender(前一版走了): 体积渲染 + 6 色量化出来是**软的一坨**,
  量过 —— 亮度跨度能拉到 85~125 级, 但形状永远是"球的并集", 给不出
  白闪/辐射尖刺/硬边烟团这三样。参考本身就是**手绘像素画**, 不是渲染图。
  (Blender 那条管线留着, `tools/blender_candlefire.py` 没删 —— 它做**点燃**那段仍然好用。)

★尺子: 1 texel = 0.0426 m = 1.775 码。判定 `CANDLE_BURN_R` = 500 码半径
  ⇒ 画面直径 1001 码 = 188 texel × **3 倍整数缩放**。
"""
import math
import os

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

# ── 调色板: 结构照参考量出来的(白/亮黄/黄橙/橙/暗红/深暗红/暗烟/近黑烟),
#    色相挪到本项目的暖金家族; **亮度阶梯与双峰结构保持参考的量**。
W = (255, 252, 240, 255)   # 亮度 252  闪
Y = (255, 238, 150, 255)   # 亮度 232  亮黄
O = (255, 178, 56, 255)    # 亮度 190  黄橙
R = (238, 96, 34, 255)     # 亮度 132  橙
DR = (126, 34, 18, 255)    # 亮度  61  暗红
DD = (68, 20, 14, 255)     # 亮度  35  深暗红
SM = (58, 50, 47, 255)     # 亮度  51  烟
                           # ★第一版给 66, 正卡在「暗像素 ≤ 60」判据上方
                           #   ⇒ 纯烟那几帧量出来烟占比恒为 0%
SD = (34, 30, 30, 255)     # 亮度  31  暗烟
CLR = (0, 0, 0, 0)

CW = CH = 188
CN = 8
CX = CY = CW // 2
RMAX = 90.0

## ★★用户 2026-09-13 第四轮:「**为什么燃烧爆发的时间要这么久**, 特效应该就是
##   **火焰从中间爆开一下子的事**啊」—— 对。我把参考那条**电影级 50 帧**整条照搬了,
##   里面有「炸开 → 收缩 → 二次点火」一整段(参考 f3~f9), 做成游戏里每 15 秒一次的
##   特效就拖沓: 14 帧 / 15fps = **0.93 秒**。
## ⇒ 砍掉中间那段回缩与二次点火, **只留 炸开(3 帧) + 散烟(5 帧)** = 8 帧 / 22fps
##   = **0.36 秒**。参考量出来的**比例关系**照旧用(烟占后 60%、亮暗双峰、半径不再扩),
##   砍的是**时长**不是结构。
PH_R = [0.26, 0.62, 0.92, 1.00, 1.00, 1.00, 0.98, 0.96]
PH_BRIGHT = [0.99, 0.88, 0.62, 0.34, 0.10, 0.02, 0.00, 0.00]
PH_DARK = [0.00, 0.08, 0.20, 0.44, 0.72, 0.90, 1.00, 1.00]
PH_AREA = [0.46, 0.72, 0.94, 1.00, 0.92, 0.74, 0.48, 0.24]
SPIKES = [0.85, 1.00, 0.35, 0.0, 0.0, 0.0, 0.0, 0.0]


def _px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def _hash(x, y, f):
    h = (x * 73856093) ^ (y * 19349663) ^ ((f + 3) * 83492791)
    return ((h >> 7) & 1023) / 1023.0


def _lobes(rad, f, n):
    """火球的瓣: 每瓣一个圆, 半径/距离各不相同, 整圈随帧转。"""
    out = [(0.0, 0.0, rad * 0.58)]
    for i in range(n):
        a = i * math.tau / n + f * 0.21
        d = rad * (0.44 + 0.16 * math.sin(i * 2.3 + f * 0.4))
        rr = rad * (0.34 + 0.12 * math.sin(i * 1.7 - f * 0.5))
        out.append((math.cos(a) * d, math.sin(a) * d * 0.94, rr))
    return out


def _in_lobes(dx, dy, lobes):
    best = None
    for lx, ly, lr in lobes:
        d = math.hypot(dx - lx, dy - ly)
        if d <= lr:
            t = d / max(1e-6, lr)
            if best is None or t < best:
                best = t
    return best


def bake():
    im = Image.new("RGBA", (CW * CN, CH), CLR)
    for f in range(CN):
        ox = f * CW
        rad = RMAX * PH_R[f]
        bright = PH_BRIGHT[f]
        dark = PH_DARK[f]
        area = PH_AREA[f]
        lobes = _lobes(rad, f, 9)
        for y in range(CH):
            for x in range(CW):
                dx = x - CX
                dy = y - CY
                t = _in_lobes(dx, dy, lobes)
                if t is None:
                    continue
                ## 碎裂: 后段靠**挖空**掉面积(参考是半径不动、像素数掉)
                if _hash(x, y, f) > area + (1.0 - t) * 0.35:
                    continue
                ## 径向位置 rr: 0 芯 → 1 边。亮/暗的分界线由 bright/dark 两条曲线定,
                ## 中间留一段火色 —— 这就是参考那个**双峰**分布的来源。
                rr = min(1.0, math.hypot(dx, dy) / max(1e-6, rad))
                ## ★第一版是**全身**按 hash 抖 ±0.09 ⇒ 整团一片椒盐噪点(并排看出来的)。
                ##   像素画的抖动只发生在**色带交界**上, 而且用有序图案(Bayer 4×4), 不是随机。
                n = (BAYER[y & 3][x & 3] / 16.0 - 0.5) * 0.085
                v = rr + n
                ## ★第一版火色带写成 `v < 1.0 - dark*0.80` —— dark=1.0 时它**还占着内圈 20%**,
                ##   于是「纯烟」那几帧量出来仍有大片橙。改成显式 fire_end: 烟满了火一点不剩。
                fire_end = max(bright, 1.0 - dark)
                if v < bright * 0.55:
                    c = W
                elif v < bright * 0.85:
                    c = Y
                elif v < bright:
                    c = O
                elif v < fire_end:
                    c = R
                elif v < fire_end + (1.0 - fire_end) * 0.42:
                    c = SM if dark > 0.45 else DR
                elif v < fire_end + (1.0 - fire_end) * 0.76:
                    c = SM if dark > 0.30 else DD
                else:
                    c = SD
                _px(im, ox + x, y, c)
        ## 辐射尖刺: 只在 f1~f4(参考 f3~f6 半径冲到 47 又缩回来的那一段)
        sp = SPIKES[f]
        if sp > 0.0:
            ## ★第一版 16 根等长等角 ⇒ 并排看是**一个卡通太阳**。参考里的尖刺是**少而不齐**的。
            for i in range(7):
                a = i * math.tau / 7.0 + f * 0.13 + math.sin(i * 2.7) * 0.35
                l0 = rad * 0.75
                ## ★钳在格子里: 不钳的话 f1 的刺长 143 > 半格 94, 被切在边上读成「一道白光束」
                l1 = min(CW * 0.46, rad * (1.0 + (1.55 if i % 3 == 0 else 0.85) * sp))
                steps = int(l1 - l0)
                for s in range(max(0, steps)):
                    u = s / max(1.0, float(steps))
                    d = l0 + s
                    wdt = max(0, int(round((3.0 if i % 3 == 0 else 1.8) * (1.0 - u) * sp)))
                    px_ = CX + math.cos(a) * d
                    py_ = CY + math.sin(a) * d * 0.94
                    for k in range(-wdt, wdt + 1):
                        c = W if u < 0.5 else (Y if u < 0.8 else O)
                        _px(im, ox + int(round(px_ - math.sin(a) * k)),
                            int(round(py_ + math.cos(a) * k)), c)
        ## 火星 / 余烬: 中后段从团里崩出去, 落在烟外面
        if 2 <= f <= 6:
            for i in range(10):
                a = i * math.tau / 10.0 + f * 0.37
                d = rad * (1.04 + 0.07 * (f - 2))
                sx = CX + int(round(math.cos(a) * d))
                sy = CY + int(round(math.sin(a) * d * 0.94))
                col = Y if f <= 4 else DR
                _px(im, ox + sx, sy, col)
                if i % 2 == 0:
                    _px(im, ox + sx + 1, sy, col)
    p = os.path.join(OUT, "candle-fire-burst.png")
    im.save(p)
    return p, im


if __name__ == "__main__":
    p, im = bake()
    print("  candle-fire-burst.png  %dx%d = %d 帧 × %dx%d" % (im.width, im.height, CN, CW, CH))
    print("  帧  不透明px   亮像素(>=200)  暗像素(<=60)   ← 目标(参考量出来的)")
    for f in range(CN):
        cell = im.crop((f * CW, 0, (f + 1) * CW, CH))
        px = [q for q in cell.getdata() if q[3] > 0]
        if not px:
            print("   f%-2d 空" % f)
            continue
        lum = [q[0] * 0.3 + q[1] * 0.6 + q[2] * 0.1 for q in px]
        b = sum(1 for q in lum if q >= 200) / len(lum)
        d = sum(1 for q in lum if q <= 60) / len(lum)
        print("   f%-2d %7d   %5.0f%% (%3.0f%%)   %5.0f%% (%3.0f%%)"
              % (f, len(px), 100 * b, 100 * PH_BRIGHT[f], 100 * d, 100 * PH_DARK[f]))
    print("→", p)
