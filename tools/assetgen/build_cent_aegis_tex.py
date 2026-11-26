"""build_cent_aegis_tex.py —— 百夫长龟甲阵分层特效用的灰度贴图(11-27 方案书 20261126 附录 D)
特效师的做法: 贴图只画灰度(形状 / 明暗), 颜色在引擎着色器里按渐变调。这里每张都是脚本按参数生成(如实: 不是手画), 种子固定, 重跑逐字节相同。
    python tools/assetgen/build_cent_aegis_tex.py
输出 assets/sprites/vfx/cent_aegis/:
  energy.png  256²  可平铺分形噪声(盾面里流动的能量, 着色器里两张交叉滚动)
  erode.png   128²  可平铺云状噪声(侵蚀: 张开 / 放盾时按它一块块烧出来、烧掉)
  flame.png    64×256 竖向火舌(上下可平铺; 两侧翼焰往上卷)
  sigil.png   256²  盾心徽记: 外环 + 内环 + 两侧月桂叶 + 中间朝上的矛尖(柔光)
  ray.png      64×256 穿盾矛光: 中线最亮、两侧柔散、前端一颗星芒
  mote.png     32²  上飘光点 / 碎光片: 软圆点 + 十字闪
  xstar.png   128²  普攻冲击罩最前端的十字星芒(RGBA 白 + 透明度, 立绘式面片直接用)
  glow.png     64²  矛头光晕(RGBA 白 + 透明度)
  rock.png     32²  登场砸地迸出的碎石(RGBA 彩色: 不规则多边形 + 亮面 / 暗面 + 深色描边)
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "cent_aegis")


def tile_noise(n, cells, rng):
    """可平铺的值噪声: cells×cells 格随机值, 余弦插值, 边界环绕"""
    g = rng.random((cells, cells))
    xs = np.arange(n) * cells / n
    i0 = np.floor(xs).astype(int)
    f = xs - i0
    f = (1 - np.cos(f * math.pi)) * 0.5
    i1 = (i0 + 1) % cells
    a = g[np.ix_(i0, i0)]; b = g[np.ix_(i0, i1)]; c = g[np.ix_(i1, i0)]; d = g[np.ix_(i1, i1)]
    fx = f[None, :]; fy = f[:, None]
    top = a * (1 - fx) + b * fx
    bot = c * (1 - fx) + d * fx
    return top * (1 - fy) + bot * fy


def fbm(n, base, octaves, seed, gain=0.5):
    rng = np.random.default_rng(seed)
    acc = np.zeros((n, n)); amp = 1.0; tot = 0.0; cells = base
    for _ in range(octaves):
        acc += tile_noise(n, cells, rng) * amp
        tot += amp; amp *= gain; cells *= 2
    return acc / tot


def norm(a):
    a = a - a.min()
    return a / max(1e-9, a.max())


def save_rgba(a, name):
    os.makedirs(OUT, exist_ok=True)
    al = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    rgba = np.dstack([np.full_like(al, 255)] * 3 + [al])
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name), optimize=False)
    print(name, a.shape[::-1])


def save(a, name):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, name), optimize=False)
    print(name, a.shape[::-1])


def energy():
    a = norm(fbm(256, 4, 5, 11))
    ridge = 1.0 - np.abs(a * 2.0 - 1.0)          # 脊线化: 中间值变亮 ⇒ 一条条流动的能量丝
    return norm(ridge ** 2.2 * 0.75 + a * 0.25)


def erode():
    return norm(fbm(128, 3, 5, 23, 0.55))


def flame():
    w, h = 64, 256
    n = fbm(256, 4, 4, 37)[:, :]                  # 先 256² 再沿竖向拉长取 64 宽 ⇒ 竖着的火舌
    n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)) / 255.0
    x = (np.arange(w) + 0.5) / w
    core = np.exp(-((x - 0.5) / 0.28) ** 2)[None, :]
    return norm(np.clip(n * 1.6 - 0.35, 0, 1) * core)


def sigil():
    S = 256; im = Image.new("L", (S, S), 0); d = ImageDraw.Draw(im)
    c = S / 2
    d.ellipse([c - 112, c - 112, c + 112, c + 112], outline=235, width=7)     # 外环
    d.ellipse([c - 92, c - 92, c + 92, c + 92], outline=150, width=3)         # 内环
    r = 70                                                                   # 两侧月桂叶: 沿内环从下往上排, 叶尖朝上
    for a_deg in [78, 58, 38, 18, -2, -22]:
        for side in (1, -1):
            ang = math.radians(a_deg if side > 0 else 180 - a_deg)
            px, py = c + math.cos(ang) * r, c + math.sin(ang) * r
            leaf = Image.new("L", (36, 14), 0)
            ImageDraw.Draw(leaf).ellipse([0, 0, 35, 13], fill=210)
            tang = math.degrees(ang) + (90 if side > 0 else -90)           # 沿圆往上的切线方向
            rot = leaf.rotate(-tang + side * 25, expand=True, resample=Image.BICUBIC)
            im.paste(255, (int(px - rot.width / 2), int(py - rot.height / 2)), rot)
    tip = [(c, c - 80), (c + 26, c - 18), (c + 9, c - 24), (c + 9, c + 62), (c - 9, c + 62), (c - 9, c - 24), (c - 26, c - 18)]
    d.polygon(tip, fill=255)                                                 # 中间朝上的矛尖 + 矛杆
    d.rectangle([c - 30, c + 30, c + 30, c + 38], fill=230)                  # 护手横档
    glow = im.filter(ImageFilter.GaussianBlur(7))
    a = np.maximum(np.array(im) / 255.0, np.array(glow) / 255.0 * 0.8)
    return a


def ray():
    w, h = 64, 256
    x = (np.arange(w) + 0.5) / w - 0.5
    y = (np.arange(h) + 0.5) / h
    core = np.exp(-(x / 0.035) ** 2)[None, :] + 0.45 * np.exp(-(x / 0.14) ** 2)[None, :]
    taper = (np.clip(y, 0, 1) ** 0.6)[:, None] * (1 - np.clip((y - 0.85) / 0.15, 0, 1)[:, None] * 0.0)
    a = core * taper
    sy = int(h * 0.1)                                                        # 前端(上)星芒
    star = np.zeros((h, w))
    for yy in range(h):
        for xx in range(w):
            dx = (xx + 0.5 - w / 2) / (w / 2); dy = (yy + 0.5 - sy) / 24.0
            star[yy, xx] = max(math.exp(-(dx / 0.06) ** 2 - (dy / 1.0) ** 2), math.exp(-(dx / 0.9) ** 2 - (dy / 0.05) ** 2) * 0.8)
    return norm(np.maximum(a[::-1], star))


def mote():
    S = 32; yy, xx = np.mgrid[0:S, 0:S]
    dx = (xx + 0.5 - S / 2) / (S / 2); dy = (yy + 0.5 - S / 2) / (S / 2)
    r = np.sqrt(dx * dx + dy * dy)
    a = np.exp(-(r / 0.28) ** 2) + 0.5 * np.exp(-(dx / 0.06) ** 2 - (dy / 0.8) ** 2) + 0.5 * np.exp(-(dy / 0.06) ** 2 - (dx / 0.8) ** 2)
    return np.clip(a, 0, 1)


def xstar():
    S = 128; yy, xx = np.mgrid[0:S, 0:S]
    dx = (xx + 0.5 - S / 2) / (S / 2); dy = (yy + 0.5 - S / 2) / (S / 2)
    r = np.sqrt(dx * dx + dy * dy)
    arms = np.exp(-(dx / 0.035) ** 2) * np.clip(1 - np.abs(dy), 0, 1) ** 2.5 + np.exp(-(dy / 0.035) ** 2) * np.clip(1 - np.abs(dx), 0, 1) ** 2.5
    d1 = (dx + dy) / math.sqrt(2); d2 = (dx - dy) / math.sqrt(2)
    diag = 0.45 * (np.exp(-(d1 / 0.03) ** 2) + np.exp(-(d2 / 0.03) ** 2)) * np.clip(1 - r / 0.55, 0, 1) ** 2
    core = np.exp(-(r / 0.09) ** 2)
    return np.clip(arms + diag + core, 0, 1)


def glow():
    S = 64; yy, xx = np.mgrid[0:S, 0:S]
    r = np.sqrt(((xx + 0.5 - S / 2) / (S / 2)) ** 2 + ((yy + 0.5 - S / 2) / (S / 2)) ** 2)
    return np.clip(np.exp(-(r / 0.42) ** 2) * 1.05 - 0.02, 0, 1)


def rock():
    S = 32; im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    rng = np.random.default_rng(57)
    pts = []
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.uniform(-0.25, 0.25)
        r = rng.uniform(9, 14)
        pts.append((16 + math.cos(a) * r, 16 + math.sin(a) * r))
    d.polygon(pts, fill=(112, 84, 58, 255), outline=(52, 36, 24, 255))
    d.polygon([pts[4], pts[5], pts[6], (16, 16)], fill=(150, 118, 84, 255))     # 亮面(左上受光)
    d.polygon([pts[1], pts[2], (16, 16)], fill=(78, 56, 38, 255))               # 暗面
    return im


if __name__ == "__main__":
    save(energy(), "energy.png")
    save(erode(), "erode.png")
    save(flame(), "flame.png")
    save(sigil(), "sigil.png")
    save(ray(), "ray.png")
    save(mote(), "mote.png")
    save_rgba(xstar(), "xstar.png")
    save_rgba(glow(), "glow.png")
    rock().save(os.path.join(OUT, "rock.png"), optimize=False)
    print("rock.png (32, 32)")
