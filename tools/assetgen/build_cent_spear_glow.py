"""build_cent_spear_glow.py —— 百夫长普攻「矛刃突刺光」叠加帧条(11-27 用户「矛刺出去…特效肯定是要贴着这个矛来做」)
和 assets/sprites/vfx/eq-centurion-attack.png 一一对应(同帧数、同 192 方帧): 引擎里与本体同帧号、同位置、同朝向叠着播 ⇒ 光永远贴在矛上。
做法(如实): 矛尖与矛杆方向是我逐帧看着普攻帧条量的坐标(下表), 脚本按坐标沿矛的前段画一道锥形光(外圈金、内圈浅金、芯白),
矛尖处最亮帧加一颗四角星闪; 每帧亮度按刺的节奏(4 起刺 → 5 刺到最远最亮 → 6 停住 → 7 收回渐灭)。重跑逐字节相同。
    python tools/assetgen/build_cent_spear_glow.py
"""
import math, os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "sprites", "vfx", "eq-centurion-attack.png")
DST = os.path.join(ROOT, "assets", "sprites", "vfx", "eq-centurion-attack-glow.png")
FW = 192
## 帧号: (矛尖, 矛杆上往后的一点, 光的长度(像素), 强度 0~1, 星闪)
SPEAR = {
    4: ((48, 136), (152, 116), 30, 0.55, False),
    5: ((21, 161), (68, 141), 50, 1.00, True),
    6: ((26, 155), (74, 136), 46, 0.75, True),
    7: ((42, 121), (147, 135), 30, 0.35, False),
}
GOLD = (246, 196, 74)
PALE = (255, 232, 154)
WHITE = (255, 255, 255)


def cone(d, tip, back, length, w_tip, w_back, col, a):
    dx, dy = back[0] - tip[0], back[1] - tip[1]
    n = math.hypot(dx, dy) or 1.0
    ux, uy = dx / n, dy / n
    px, py = -uy, ux
    ex, ey = tip[0] + ux * length, tip[1] + uy * length
    sx, sy = tip[0] - ux * 3, tip[1] - uy * 3   # 光往矛尖前面冒 3 像素
    pts = [(sx + px * w_tip, sy + py * w_tip), (ex + px * w_back, ey + py * w_back),
           (ex - px * w_back, ey - py * w_back), (sx - px * w_tip, sy - py * w_tip)]
    d.polygon([(round(x), round(y)) for x, y in pts], fill=col + (a,))


def main():
    src = Image.open(SRC)
    n = src.width // FW
    out = Image.new("RGBA", (FW * n, FW), (0, 0, 0, 0))
    for i in range(n):
        if i not in SPEAR:
            continue
        tip, back, length, k, star = SPEAR[i]
        f = Image.new("RGBA", (FW, FW), (0, 0, 0, 0))
        d = ImageDraw.Draw(f)
        cone(d, tip, back, length * 1.15, 7.0, 3.0, GOLD, int(90 * k))      # 外圈光晕(第一版只有 3.5 宽, 游戏里看不出)
        cone(d, tip, back, length, 5.0, 2.0, GOLD, int(200 * k))
        cone(d, tip, back, length * 0.8, 3.2, 1.2, PALE, int(240 * k))
        cone(d, tip, back, length * 0.55, 1.6, 0.6, WHITE, int(255 * k))
        if star:
            r = 11 if k >= 0.9 else 6
            x, y = tip
            for (ax, ay) in [(1, 0), (0, 1)]:
                d.line([(x - ax * r, y - ay * r), (x + ax * r, y + ay * r)], fill=WHITE + (255,), width=1)
            d.line([(x - r // 2, y - r // 2), (x + r // 2, y + r // 2)], fill=PALE + (200,), width=1)
            d.line([(x - r // 2, y + r // 2), (x + r // 2, y - r // 2)], fill=PALE + (200,), width=1)
            d.point((x, y), fill=WHITE + (255,))
        out.paste(f, (i * FW, 0))
    out.save(DST, optimize=False)
    print("ok", n, "帧 →", DST)


if __name__ == "__main__":
    main()
