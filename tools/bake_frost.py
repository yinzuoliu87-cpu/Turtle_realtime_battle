# -*- coding: utf-8 -*-
"""烘 028 冰霜冻露瓶的两张霜雾贴图。

★为什么要烘(实测, 不是观感):
  ① `_frost_puff` 用的是 `VfxTex._make_fire_glow_tex()` —— **程序生成的光球**,
     实拍(7.40 秒那帧)量出来是一团 **144×100 屏幕像素、亮度中位 41** 的暗斑,
     而龟只有 45 像素高 ⇒ **3.2 个龟宽的一坨暗色油污糊在地上**, 读不出"霜"。
     CLAUDE.md 明令不许拿程序生成的圆环白球敷衍。
  ② 文案写「施加冰寒 5 秒(移速 -20% / 攻速 -10%)」—— 这是个**持续 5 秒的状态**,
     而画面上从砸中到结束**零提示**。文案写了画面读不出, 也是缺陷。

形状怎么来的: 霜的形态是**冰晶**(菱形 + 十字枝), 不是圆球。
  · frost-mist  : 砸中那一下炸开的霜雾 —— 一圈冰晶由内向外飞散并变稀
  · frost-chill : 冰寒持续期挂在身上的霜 —— 三四粒冰晶, 缓慢明暗呼吸
调色板四色, 全不透明或全透明, 深蓝描边(亮青龟身上要看得见), 不羽化。
"""
import math
import os
import random

from PIL import Image

W = (255, 255, 255)      # 芯
L = (191, 233, 255)      # 亮(与伤害飘字的 #bfe9ff 同族)
M = (108, 186, 240)      # 中
D = ( 18,  52, 104)      # 描边


def _px(im):
    return im.load()


def _dot(px, size, x, y, col):
    if 0 <= x < size and 0 <= y < size:
        px[x, y] = col + (255,)


def _crystal(px, size, cx, cy, r, bright):
    """一粒冰晶: 菱形芯 + 三向枝, 外面包一圈描边。r 是半径(像素)。"""
    cells = []
    r = max(1, int(round(r)))
    for dy in range(-r, r + 1):                      # 菱形
        for dx in range(-r, r + 1):
            if abs(dx) + abs(dy) <= r:
                cells.append((cx + dx, cy + dy))
    ## ★形状换过一版: 第一版用 90/210/330 三向枝(照六方对称取三枝), 渲出来是一排
    ##   **倒三角带个把儿的"T"** —— r=2 时枝只有 2~4 像素, 三向的不对称在这个尺寸下
    ##   根本读不成冰晶。四向枝(上下左右)是像素画里"冰晶/闪光"的通用符号, 小到 5×5 也成立。
    for (dx, dy) in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        for k in range(r, r + 2):
            cells.append((cx + dx * k, cy + dy * k))
    # 描边先铺(八向膨胀), 芯后盖 —— 顺序保证芯永远在最上面
    for (x, y) in cells:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                _dot(px, size, x + ox, y + oy, D)
    core = W if bright else L
    for (x, y) in cells:
        _dot(px, size, x, y, M)
    for (x, y) in cells[: max(1, len(cells) // 3)]:
        _dot(px, size, x, y, core)


def bake_mist(path, size=32, frames=6, seed=280913):
    """砸中那一下的霜雾: 一圈冰晶由内向外飞散, 粒子逐帧变小变少。"""
    rnd = random.Random(seed)
    n_seed = 8
    dirs = [(rnd.uniform(0, math.tau), rnd.uniform(0.6, 1.0)) for _ in range(n_seed)]
    sheet = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
    for f in range(frames):
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        px = _px(im)
        t = f / float(frames - 1)                    # 0 → 1
        alive = max(1, int(round(n_seed * (1.0 - 0.62 * t))))
        for k in range(alive):
            ang, spd = dirs[k]
            dist = size * 0.46 * spd * (0.18 + 0.82 * t)
            cx = int(round(size * 0.5 + math.cos(ang) * dist))
            cy = int(round(size * 0.55 + math.sin(ang) * dist * 0.62))   # 压扁: 贴地铺开
            _crystal(px, size, cx, cy, 2.0 * (1.0 - 0.5 * t), bright=(t < 0.5))
        sheet.paste(im, (f * size, 0))
    sheet.save(path)


def bake_chill(path, size=40, frames=6, seed=1128):
    """冰寒持续期挂在身上的霜。

    ★用户 2026-09-13 看过第一版之后:「感觉不是这样放大, 而是**加更多例子**」——
      第一版是 20 格 3 粒, 我按他前一句「大 2 倍」把整张贴图放到 2×,
      结果变成**三粒巨大的冰晶**, 不是他要的。
      现在改成: 格子扩到 40 texel(覆盖面与 2× 时一样大), 里面塞 **9 粒小冰晶**铺开 ——
      单粒还是原来那么小, 但数量多、散在整个身子上, 读成"结了一层霜"而不是"贴了三块冰"。
    ★位置固定、只有明暗与大小在呼吸(不乱跳, 免得像噪点); 相位错开让它看着在此起彼伏。
    """
    rnd = random.Random(seed)
    # 九个点铺满身子(躲开正中心, 免得糊住脸), 相对坐标
    spots = [
        (0.20, 0.24), (0.52, 0.16), (0.80, 0.28),
        (0.14, 0.52), (0.86, 0.56), (0.36, 0.46),
        (0.26, 0.80), (0.60, 0.74), (0.88, 0.84),
    ]
    sheet = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
    for f in range(frames):
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        px = _px(im)
        for i, (sx, sy) in enumerate(spots):
            phase = ((f + i * 3) % frames) / float(frames)
            r = 1.3 + 0.6 * math.sin(phase * math.tau)     # 单粒保持小: 半径 0.7~1.9
            _crystal(px, size, int(round(sx * size)), int(round(sy * size)), r,
                bright=(phase < 0.5))
        sheet.paste(im, (f * size, 0))
    sheet.save(path)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    a = os.path.join(root, "assets", "sprites", "vfx", "frost-mist.png")
    b = os.path.join(root, "assets", "sprites", "vfx", "frost-chill.png")
    bake_mist(a)
    bake_chill(b)
    print("baked:", a)
    print("baked:", b)
