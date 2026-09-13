# -*- coding: utf-8 -*-
"""041 退潮浊液【涨潮持续态】6 帧循环 (2026-09-14)。

用户 2026-09-14 看 041 窗口时:「最好做一个 buff 持续期间的特效, **整个身体**怎么样」。

现状(我实拍确认过): 041 涨潮只有 t=5 那一下 `tide_swell` 水柱 + 体型 +30%,
之后 ★3 整整 **15 秒**身上一点标记都没有 —— 画面读不出"它正处在涨潮里"。

★分段表(持续态是循环, 不是一次性; 见方案书 §041):
   循环一轮 6 帧 / 8fps = 0.75 秒
   ① 水体      : 下方约 70% 高度是浊液(半透青绿, 龟从水里透出来)
   ② 水线      : 顶面一条亮线, 逐帧上下起伏 ±2 texel —— **这就是"潮"这个字的全部**
   ③ 浪尖      : 水线上几个小尖峰逐帧横向游移, 免得读成一根直尺
   ④ 反光      : 水体里 2~3 颗亮点游移, 给"水在动"的证据
   ⑤ 底部滴落  : 下缘挂 1~2 滴, 位置逐帧换
  **不做整体淡入淡出** —— 持续态一淡就读成"要结束了"(淡出病, memory fb-vfx-defect-families)。

★为什么是半透: 它盖在龟身上。全不透 = 把龟涂没了(那就不是"裹住身体"是"换了个人");
  所以水体 alpha 约 0.42, 水线/反光才给到接近不透明 —— 亮的部分负责被看见,
  暗的部分负责不挡住龟。

★不许自由旋转 / NEAREST / 整数倍缩放: billboard 正面朝相机, 形状左右对称,
  转不转都一样(034 那次的教训: 对称就不需要旋转)。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = 1.775 码。
  cell 48×48 texel ⇒ TIDE_COAT_YARDS = 48 × 1.775 ≈ 85 码 ≈ 2.04 m,
  略大于一只龟(中位身高 1.40 m) ⇒ 刚好裹住整个身体还留一点边。
"""
import os
import math

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 48
FRAMES = 6

# 锁定调色板。青绿浊液 —— 跟 041 自己的「涨潮」飘字 #5fe0d0 同色系,
# 但形状是新画的(铁律管的是"别拿别人的图顶替", 不是"不许同色系")。
CLR = (0, 0, 0, 0)
DEEP = (26, 96, 104, 120)     # 水体最深(贴底)。★第一版 (18,68,78) 压在黑场上读成一团黑影,
                              #   实拍裁开看整个下半截化进背景 ⇒ 提亮一档
MID = (44, 134, 138, 112)     # 水体中段
SHAL = (66, 172, 164, 104)    # 水体近水面
LINE = (150, 236, 222, 236)   # 水线(亮)
CREST = (214, 255, 246, 250)  # 浪尖高光
GLINT = (196, 250, 240, 214)  # 水里的反光
DROP = (92, 190, 186, 200)    # 滴落


def _mask_halfwidth(y):
    """身体轮廓的半宽 —— 上窄下宽的胶囊形, 不是方框。

    方框会读成"一块玻璃挡在前面"; 椭圆读成"水裹着一个东西"。

    ★第一版我用的是"上端略收的近似方框", 渲出来读成**一缸水**(上缘是平的直角),
    完全不是"水裹着一个东西"。改成真椭圆 + 贴底压扁。

    ★第二版又调了一次: 椭圆中心放在 0.58 时下缘也是圆的 ⇒ 实拍读成"龟站在一颗蛋里"。
    水是**漫上来**的, 所以正确形状是**下宽上收**、底面近乎平的 —— 椭圆中心压到 0.72,
    可见的那一段(水面以下)正好落在椭圆最宽处附近。
    """
    cyb = CELL * 0.72        # 椭圆中心压到很低 ⇒ 水面那一段是收的, 贴地那一段是宽的
    ry = CELL * 0.62
    rx = CELL * 0.40
    q = (y - cyb) / ry
    if abs(q) >= 1.0:
        return 0.0
    hw = rx * math.sqrt(1.0 - q * q)
    if y > CELL - 3:         # 最后两行略收, 免得下缘切出一条硬直线
        hw *= max(0.0, 1.0 - (y - (CELL - 3)) * 0.18)
    return hw


def _waterline(f, x):
    """第 f 帧、第 x 列的水面高度(y 值, 越小越高)。"""
    base = CELL * 0.30                       # 水面大致在 30% 高度处 ⇒ 淹到胸口以上
    bob = 2.0 * math.sin(2.0 * math.pi * f / FRAMES)          # 整体潮涨潮落 ±2
    ripple = 1.3 * math.sin(x * 0.55 + f * 1.25)              # 浪尖横向游移
    return base + bob + ripple


def _draw_frame(im, f):
    ox = f * CELL
    for y in range(CELL):
        hw = _mask_halfwidth(y)
        if hw <= 0.0:
            continue
        for x in range(CELL):
            dx = abs(x - (CELL / 2.0 - 0.5))
            if dx > hw:
                continue
            wl = _waterline(f, x)
            if y < wl - 1.0:
                continue                       # 水面之上: 空的(龟头露在外面)
            if y < wl + 1.0:
                im.putpixel((ox + x, y), LINE)      # ② 水线
                continue
            d = (y - wl) / max(1.0, CELL - wl)      # 0(刚没过水面) → 1(贴底)
            if d < 0.30:
                c = SHAL
            elif d < 0.66:
                c = MID
            else:
                c = DEEP
            im.putpixel((ox + x, y), c)

    # ③ 浪尖: 水线上挑三个尖, 逐帧横向走
    for k in range(3):
        x = int((CELL * (0.22 + 0.28 * k) + f * 2.6)) % CELL
        hw = _mask_halfwidth(_waterline(f, x))
        if abs(x - (CELL / 2.0 - 0.5)) > hw:
            continue
        y = int(round(_waterline(f, x))) - 1
        if 0 <= y < CELL:
            im.putpixel((ox + x, y), CREST)
        if 0 <= y - 1 < CELL and k == f % 3:
            im.putpixel((ox + x, y - 1), CREST)

    # ④ 水体里的反光: 两颗, 逐帧游移
    for k in range(2):
        ang = 2.0 * math.pi * (f / FRAMES) + k * 2.1
        x = int(CELL / 2.0 + math.cos(ang) * CELL * 0.22)
        y = int(CELL * 0.58 + math.sin(ang) * CELL * 0.14)
        if 0 <= x < CELL and 0 <= y < CELL:
            if abs(x - (CELL / 2.0 - 0.5)) <= _mask_halfwidth(y):
                im.putpixel((ox + x, y), GLINT)
                if 0 <= x + 1 < CELL and abs(x + 1 - (CELL / 2.0 - 0.5)) <= _mask_halfwidth(y):
                    im.putpixel((ox + x + 1, y), GLINT)

    # ⑤ 底部滴落: 一滴, 逐帧换位置与长度
    dx = int(CELL * 0.5 + math.sin(f * 1.9) * CELL * 0.20)
    dy0 = CELL - 5 + (f % 3)
    for y in range(dy0, min(CELL, dy0 + 2)):
        if 0 <= dx < CELL:
            im.putpixel((ox + dx, y), DROP)


def main():
    im = Image.new("RGBA", (CELL * FRAMES, CELL), CLR)
    for f in range(FRAMES):
        _draw_frame(im, f)
    path = os.path.join(OUT, "tide-coat.png")
    im.save(path)

    # ── 自检: 烘完回量, 打印实测 vs 目标 ──
    px = im.load()
    print("写出 %s  %dx%d  %d 帧, cell %d  (TIDE_COAT_YARDS 应配 %.0f 码)"
          % (path, im.width, im.height, FRAMES, CELL, CELL * 1.775))
    cols = set()
    lines = []
    for f in range(FRAMES):
        n = 0
        opaque = 0
        top = CELL
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3] == 0:
                    continue
                n += 1
                cols.add(c)
                if c[3] >= 200:
                    opaque += 1
                top = min(top, y)
        lines.append(top)
        print("  f%d 覆盖 %4d px (%.0f%%), 其中 alpha≥200 的 %3d px (%.0f%%), 水面最高 y=%d"
              % (f, n, 100.0 * n / (CELL * CELL), opaque, 100.0 * opaque / max(1, n), top))
    print("  色数 %d" % len(cols))
    print("  ★水面在 6 帧里的最高点 %s —— 起伏幅度 %d texel(=0 就是根本没在动)"
          % (lines, max(lines) - min(lines)))
    assert max(lines) - min(lines) >= 2, "水面没起伏 —— 持续态会读成一张贴纸"
    assert len(cols) <= 10, "色数超了"


if __name__ == "__main__":
    main()
