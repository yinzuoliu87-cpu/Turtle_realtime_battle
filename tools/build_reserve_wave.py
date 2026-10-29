# -*- coding: utf-8 -*-
"""援军小将·四面合围 的气波弹体(2026-10-29, 方案书 docs/plans/20261029-终极战场援军小将.md)。确定性生成, 重跑逐字节相同。

输出 assets/sprites/vfx/reserve-wave.png: 4 帧横排(每帧 16×16, fire_skillshot 按宽 / 高自动切帧), 青蓝气团脉动 + 外圈两颗旋转火花。
硬边、零半透明。不借任何别的单位的素材(小龟·打击的 qibo-ball 是小龟的)。

  python tools/build_reserve_wave.py
"""
import io
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "reserve-wave.png")

T = (0, 0, 0, 0)
INK = (12, 30, 48, 255)
DEEP = (24, 112, 168, 255)
MID = (64, 186, 232, 255)
HI = (168, 236, 255, 255)
CORE = (250, 255, 255, 255)
S = 16
FRAMES = 4


def frame(k):
    im = Image.new("RGBA", (S, S), T)
    px = im.load()
    c = (S - 1) / 2.0
    pulse = [0.0, 0.5, 1.0, 0.5][k]
    r_out = 5.2 + pulse * 0.8
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - c, y - c)
            if d <= r_out + 1.0:
                px[x, y] = INK
            if d <= r_out:
                px[x, y] = DEEP
            if d <= r_out - 1.3:
                px[x, y] = MID
            if d <= r_out - 2.6:
                px[x, y] = HI
            if d <= 1.2:
                px[x, y] = CORE
    # 两颗外圈火花, 每帧转 45°
    for j in range(2):
        a = math.pi / 4 * k + math.pi * j
        x = int(round(c + math.cos(a) * 7.0))
        y = int(round(c + math.sin(a) * 7.0))
        if 0 <= x < S and 0 <= y < S:
            px[x, y] = HI
    return im


def build():
    strip = Image.new("RGBA", (S * FRAMES, S), T)
    for k in range(FRAMES):
        strip.paste(frame(k), (k * S, 0))
    assert set(strip.getchannel("A").tobytes()) <= {0, 255}
    bio = io.BytesIO()
    strip.save(bio, "PNG", optimize=False)
    data = bio.getvalue()
    if not (os.path.exists(OUT) and open(OUT, "rb").read() == data):
        open(OUT, "wb").write(data)
    print("ok", OUT)


if __name__ == "__main__":
    build()
