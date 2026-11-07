"""批量排帧共用: 取帧 / 去碎点 / 舞台 / 程序特效(像素风, 无半透明)"""
import math
import os
from collections import deque

from PIL import Image

BARE = os.environ.get("ACT_BARE")
PAD, TOP = 56, 44
STAGE = (128 + PAD * 2, 128 + TOP + 8)
GROUND = 123 + TOP
OX = PAD


def L(D, seg, i):
    return Image.open("%s%s/f_%02d.png" % (D, seg, i)).convert("RGBA")


def despeck(im, smin=16):
    im = im.copy()
    px = im.load()
    W, H = im.size
    seen = set()
    for y in range(H):
        for x in range(W):
            if px[x, y][3] and (x, y) not in seen:
                comp = [(x, y)]
                seen.add((x, y))
                q = deque(comp)
                while q:
                    cx, cy = q.popleft()
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            p = (cx + dx, cy + dy)
                            if 0 <= p[0] < W and 0 <= p[1] < H and p not in seen and px[p][3]:
                                seen.add(p)
                                comp.append(p)
                                q.append(p)
                if len(comp) < smin:
                    for p in comp:
                        px[p] = (0, 0, 0, 0)
    return im


def stage():
    return Image.new("RGBA", STAGE, (0, 0, 0, 0))


def onstage(im, dx=0, dy=0, back=None, front=None):
    if BARE:
        back = front = None
    st = stage()
    if back:
        back(st)
    st.alpha_composite(im, (PAD + dx, TOP + dy))
    if front:
        front(st)
    return st


def puff(st, x, y, r, c, density=1.0):
    px = st.load()
    for yy in range(int(y - r), int(y + r) + 1):
        for xx in range(int(x - r), int(x + r) + 1):
            if 0 <= xx < st.width and 0 <= yy < st.height and math.hypot(xx - x, yy - y) <= r:
                if density >= 1.0 or (xx * 3 + yy * 5) % 7 < density * 7:
                    px[xx, yy] = tuple(c) + (255,)


def star(st, x, y, r, cols, k=0):
    px = st.load()
    for yy in range(int(y - r), int(y + r) + 1):
        for xx in range(int(x - r), int(x + r) + 1):
            if not (0 <= xx < st.width and 0 <= yy < st.height):
                continue
            d = math.hypot(xx - x, yy - y)
            a = math.atan2(yy - y, xx - x)
            edge = r * (0.5 + 0.5 * abs(math.cos(3 * a + k)))
            if d <= edge:
                f = d / edge
                c = cols[3] if f < 0.35 else (cols[2] if f < 0.6 else (cols[1] if f < 0.85 else cols[0]))
                px[xx, yy] = tuple(c) + (255,)


def shard(st, x, y, s, c, edge):
    """菱形碎片"""
    px = st.load()
    for yy in range(int(y - s), int(y + s) + 1):
        for xx in range(int(x - s), int(x + s) + 1):
            if 0 <= xx < st.width and 0 <= yy < st.height:
                d = abs(xx - x) / max(1, s * 0.7) + abs(yy - y) / s
                if d <= 1:
                    px[xx, yy] = (tuple(edge) if d > 0.72 else tuple(c)) + (255,)


def ring(st, x, y, rx, ry, c, w=2.0):
    px = st.load()
    for k in range(int(rx * 8)):
        a = 2 * math.pi * k / (rx * 8)
        for t in range(int(w * 2)):
            xx = int(x + (rx - t * 0.5) * math.cos(a))
            yy = int(y + (ry - t * 0.25) * math.sin(a))
            if 0 <= xx < st.width and 0 <= yy < st.height:
                px[xx, yy] = tuple(c) + (255,)


def lines(st, x0, y0, x1, n, c, seed=0):
    """速度线"""
    px = st.load()
    for k in range(n):
        y = y0 + (k * 7 + seed * 5) % 40
        a = x0 + (k * 13 + seed * 9) % 30
        b = a + (x1 - x0) * (0.4 + 0.6 * ((k + seed) % 3) / 2)
        for x in range(int(min(a, b)), int(max(a, b))):
            if 0 <= x < st.width and 0 <= y < st.height:
                px[x, y] = tuple(c) + (255,)
