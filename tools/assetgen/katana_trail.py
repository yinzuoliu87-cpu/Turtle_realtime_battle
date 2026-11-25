# -*- coding: utf-8 -*-
"""katana_trail.py —— 107 武士刀小将横斩的【刀光拖尾】, 按每帧真实的刀尖 / 刀柄位置画进动作帧(2026-11-25)。

由来: 用户 11-25「这个普攻的特效，你这次怎么给的呢？我不太懂」—— 上一版是两样东西叠的: 生成器在过渡帧里自己画的一道青色刀风
  + 命中时在小将前方播一张现成「刀光」部件(特效工作台 slash_trail 压扁), 两样都没照刀实际走的路线(身后 → 正前 → 绕到另一侧)。
做法(如实, 商业游戏的武器拖尾思路, 像素画版本): 不是手画, 是脚本按几何算 ——
  ① 逐帧找刀身(亮、低饱和的钢色像素最大连通块), 两头靠金色护手的是刀柄、另一头是刀尖(同 tools/oneoff/blade_track.py);
  ② 相邻两帧之间把刀「扫过的那片扇面」补出来: 刀柄位置线性插值、刀的朝向按较短方向转角插值、长度插值, 每段切 10 小步;
     只画刀身外侧 45%~100% 那一段(拖尾贴着刀尖走, 不糊在手上);
  ③ 第 k 帧画两段: 上一帧 → 这一帧(亮: 白芯 + 淡青边) 与 再上一帧 → 上一帧(淡: 只剩淡青); 硬边、三档色, 不做半透明渐变糊边;
  ④ 拖尾画在角色上面, 再把这一帧的刀身像素原样盖回去(刀在拖尾前面);
  ⑤ 生成器在过渡帧里自带的那道青色刀风擦掉(颜色 = 高绿高蓝低红的青色), 由这条拖尾代替。
确定性: 纯几何 + 固定参数, 输入帧不变则逐字节相同。被 pack_bomb_vfx.py 调用(KATANA_TRAIL)。
"""
import math

from PIL import Image, ImageDraw

C_CORE = (255, 255, 255, 255)      # 白芯(刀尖一侧)
C_EDGE = (176, 230, 250, 235)      # 淡青边
C_OLD = (130, 205, 240, 150)       # 上上段: 只剩淡青、半透明一档


def blade_pixels(im):
    px = im.load()
    pts = set()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 128 and min(r, g, b) >= 150 and max(r, g, b) - min(r, g, b) <= 45:
                pts.add((x, y))
    best, seen = [], set()
    for p in sorted(pts):
        if p in seen:
            continue
        comp, st = [], [p]
        seen.add(p)
        while st:
            q = st.pop()
            comp.append(q)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (q[0] + dx, q[1] + dy)
                    if n in pts and n not in seen:
                        seen.add(n)
                        st.append(n)
        if len(comp) > len(best):
            best = comp
    return best


def gold_pixels(im):
    px = im.load()
    return [(x, y) for y in range(im.height) for x in range(im.width)
            if px[x, y][3] > 128 and px[x, y][0] > 170 and px[x, y][1] > 120 and px[x, y][2] < 90]


def blade_seg(im):
    """→ (刀尖, 刀柄, 刀身像素) 或 None"""
    bl = blade_pixels(im)
    if len(bl) < 6:
        return None
    a = max(bl, key=lambda p: (p[0], p[1]))
    e1 = max(bl, key=lambda p: ((p[0] - a[0]) ** 2 + (p[1] - a[1]) ** 2, p))
    e2 = max(bl, key=lambda p: ((p[0] - e1[0]) ** 2 + (p[1] - e1[1]) ** 2, p))
    gold = gold_pixels(im)

    def near_gold(e):
        return min([(g[0] - e[0]) ** 2 + (g[1] - e[1]) ** 2 for g in gold] or [10 ** 9])
    hilt, tip = (e1, e2) if near_gold(e1) <= near_gold(e2) else (e2, e1)
    return tip, hilt, bl


def _sweep_polys(sa, sb, t0, t1, steps=10):
    """刀从 sa 扫到 sb 时, 刀身 [t0, t1] 段扫过的面 → 四边形列表。
    刀尖 / 刀柄按位置插值(不按转角: 刀从指左水平绕身扫到指右, 转角正好差 180°, 按转角插会画成从头顶翻过去的半圆);
    刀尖横向走得多的那段 = 刀在胸口高度水平绕身, 镜头俯视 ⇒ 近身那一侧往下沉一点(沉 = 横向位移 × 0.15)。"""
    (tipA, hiltA), (tipB, hiltB) = sa, sb
    sag = abs(tipB[0] - tipA[0]) * 0.15 if abs(tipB[0] - tipA[0]) > 40 else 0.0

    def seg(s):
        bow = sag * math.sin(math.pi * s)
        h = (hiltA[0] + (hiltB[0] - hiltA[0]) * s, hiltA[1] + (hiltB[1] - hiltA[1]) * s + bow * 0.4)
        tp = (tipA[0] + (tipB[0] - tipA[0]) * s, tipA[1] + (tipB[1] - tipA[1]) * s + bow)
        return [(h[0] + (tp[0] - h[0]) * t, h[1] + (tp[1] - h[1]) * t) for t in (t0, t1)]
    polys = []
    prev = seg(0.0)
    for i in range(1, steps + 1):
        cur = seg(i / float(steps))
        polys.append([prev[0], prev[1], cur[1], cur[0]])
        prev = cur
    return polys


def _erase_cyan(im):
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 0 and g > 170 and b > 150 and r < 150:
                px[x, y] = (0, 0, 0, 0)
    return im


def apply(frames, first, last):
    """frames: 整段横斩帧(RGBA, 同尺寸); 在第 first..last 帧画拖尾(含两端)。返回新帧列表 + 每帧(刀尖, 刀柄)。"""
    frames = [_erase_cyan(f) for f in frames]
    segs = []
    for f in frames:
        s = blade_seg(f)
        segs.append((s[0], s[1]) if s else None)
    ## 刀柄连续性: 刀柄握在手里, 相邻两帧的刀柄挨着; 按护手判断偶尔标反(刀竖着、护手被手挡住时), 离上一帧刀柄更近的那头才是刀柄
    for k in range(1, len(segs)):
        if segs[k] and segs[k - 1]:
            tip, hilt = segs[k]
            ph = segs[k - 1][1]
            if (tip[0] - ph[0]) ** 2 + (tip[1] - ph[1]) ** 2 < (hilt[0] - ph[0]) ** 2 + (hilt[1] - ph[1]) ** 2:
                segs[k] = (hilt, tip)
    out = []
    for k, f in enumerate(frames):
        if k < first or k > last:
            out.append(f)
            continue
        layer = Image.new("RGBA", f.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        if k >= 2 and segs[k - 2] and segs[k - 1]:
            for poly in _sweep_polys(segs[k - 2], segs[k - 1], 0.6, 1.0):
                d.polygon(poly, fill=C_OLD)
        if k >= 1 and segs[k - 1] and segs[k]:
            for poly in _sweep_polys(segs[k - 1], segs[k], 0.45, 1.0):
                d.polygon(poly, fill=C_EDGE)
            for poly in _sweep_polys(segs[k - 1], segs[k], 0.78, 1.0):
                d.polygon(poly, fill=C_CORE)
        g = f.copy()
        g.alpha_composite(layer)
        ## 刀身盖回拖尾上面(刀在前)
        s = blade_seg(f)
        if s:
            gp, fp = g.load(), f.load()
            for (x, y) in s[2]:
                gp[x, y] = fp[x, y]
        out.append(g)
    return out, segs
