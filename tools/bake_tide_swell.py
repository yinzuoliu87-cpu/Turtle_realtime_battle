# -*- coding: utf-8 -*-
"""041 退潮浊液【涨潮 / 退潮】的新素材 (2026-09-13)。

实拍(13 帧逐帧看过)读出来的毛病:
  ① 两圈**程序生成的圆环**(`_skill_ring` + `_splash_ring_bold`)罩在龟身上 = 无含义圆环(禁区)
  ② 11 颗 `VfxTex._make_fire_glow_tex()` **白球**四散上浮 = 白球(禁区)
  ③ 那 11 颗还写着 `TEXTURE_FILTER_LINEAR` —— **连像素风都不是**, 实拍是一团糊
  ④ 文案的「体积 +30%」在一团糊里读不出来

⇒ 换成【水柱】: 一根一根从脚下窜起来的水柱(涨潮) / 沉下去的水柱(退潮)。
  12 帧一张表: 0~5 = 涨(窜起→散成水花), 6~11 = 退(水面下沉→留一摊)。
  两段是**同一件效果的两个方向**, 不是"拿别的图顶替"。

★尺子: 1 texel = 0.0426 m = 1.775 码。水柱 20×28 texel = 35.5 × 49.7 码。
"""
import os, math
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

D = (10, 48, 62, 255)      # 暗水(描边/根部)
M = (38, 150, 160, 255)    # 水体
L = (110, 224, 214, 255)   # 受光面
W = (226, 255, 250, 255)   # 水花高光
CLR = (0, 0, 0, 0)

CW, CH = 20, 28
RISE, SINK = 6, 6
CN = RISE + SINK
GROUND = CH - 1
CX = CW // 2

# 涨潮: 水柱高度逐帧(相对全高) —— 窜得快、顶到最高后散开
RISE_ENV = [0.18, 0.52, 0.84, 1.00, 0.86, 0.55]
# 退潮: 水面从高处沉下去, 最后只剩地上一摊
SINK_ENV = [0.92, 0.70, 0.48, 0.30, 0.16, 0.06]


def _px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def _column(im, ox, h, f, spread):
    """画一根水柱: 高 h(texel), spread = 顶端碎裂程度(0~1)。
    ★第一版把 spread 加进了半宽 ⇒ 上粗下细, 并排渲出来是**一排试管**。
      水柱应该是**上细下粗 + 沿高度摆动 + 顶端碎成水花**, spread 只管碎不管粗。"""
    if h < 1.0:
        return
    top = int(round(GROUND - h))
    for y in range(top, CH):
        d = (GROUND - y) / max(1.0, h)                 # 0 根部 → 1 顶端
        half = max(1, int(round(3.3 * (1.0 - 0.66 * d))))
        cx = CX + int(round(math.sin(d * 4.2 + f * 0.8) * 1.3))   # 沿高度摆动, 不是直筒
        for x in range(cx - half, cx + half + 1):
            if d > 0.68 and (x * 3 + y * 2 + f) % max(2, int(5 - spread * 3)) == 0:
                continue                               # 顶端碎成水花
            edge = abs(x - cx) >= half
            if edge:
                c = D
            elif abs(x - cx) >= half - 1:
                c = M
            elif d > 0.72:
                c = W if (x + y + f) % 3 else L
            else:
                c = L if (x + y * 2 + f) % 5 == 0 else M
            _px(im, ox + x, y, c)
    for x in range(CX - 4, CX + 5):                    # 脚下那一摊
        _px(im, ox + x, GROUND, D)


def _droplets(im, ox, h, f, n):
    for k in range(n):
        a = (k / float(max(1, n))) * math.tau + f * 0.4
        r = 3 + (f % 3) + k
        x = CX + int(round(math.cos(a) * r))
        y = int(round(GROUND - h - 2 - math.sin(a) * 3 - k))
        _px(im, ox + x, y, W if k % 2 else L)
        _px(im, ox + x, y + 1, D)


def bake():
    im = Image.new("RGBA", (CW * CN, CH), CLR)
    peak = CH - 3
    for f in range(RISE):
        ox = f * CW
        h = peak * RISE_ENV[f]
        _column(im, ox, h, f, spread=max(0.0, (f - 1) / 4.0))
        if f >= 2:
            _droplets(im, ox, h, f, 4)
    for f in range(SINK):
        ox = (RISE + f) * CW
        h = peak * SINK_ENV[f]
        _column(im, ox, h, f, spread=max(0.0, 0.45 - f * 0.12))
        if f <= 2:
            _droplets(im, ox, h, f, 2)
    p = os.path.join(OUT, "tide-swell.png")
    im.save(p)
    return p, im


if __name__ == "__main__":
    p, im = bake()
    print("  tide-swell.png  %dx%d = %d 帧 × %dx%d (0~5 涨 / 6~11 退)"
          % (im.width, im.height, CN, CW, CH))
    for f in range(CN):
        cell = im.crop((f * CW, 0, (f + 1) * CW, CH))
        px = list(cell.get_flattened_data()) if hasattr(cell, "get_flattened_data") else list(cell.getdata())
        op = [q for q in px if q[3] > 0]
        br = [q for q in op if (q[0] + q[1] + q[2]) / 3.0 >= 110]
        print("    f%-2d 不透明 %3d (%.0f%%)  亮/不透明 = %.2f"
              % (f, len(op), 100.0 * len(op) / len(px), (len(br) / len(op)) if op else 0.0))
    print("→", p)
