# -*- coding: utf-8 -*-
"""工作室开场「灯鱼 Lampfish」素材 + 音效(2026-10-29, 方案书 docs/plans/20261029-工作室开场动画.md)。确定性生成, 重跑逐字节相同。

★为什么这样画: 用户看了 Gemini 出的插画式开场说「ai味太重」。7 家商业开场真图(Supercell / 拳头 / Team Cherry / Klei /
  凉屋 / Mojang / ConcernedApe)的工作室标志全是「单色、扁平、粗体」, 字为主, 图形顶多一个简单小图标, 没有一家用立体光影插画。
  ⇒ 这里画的是「标志」不是「插画」: 奶油色单色像素小鱼剪影(眼睛 / 嘴 / 鳃是镂空), 只有灯是暖黄; 字是自绘的 2 像素笔画粗像素字。
  全部逐像素写在这份脚本里, 0 次生成模型。

  输出(1 倍源图; 游戏里整数倍最近邻放大, 见 scripts/scenes/studio_intro.gd):
    assets/sprites/ui/studio_intro/
      fish_on.png / fish_off.png / fish_blink.png / fish_flash.png   小鱼四个状态(同尺寸, 同原点)
      ticks_0.png / ticks_1.png                                      灯周围的短光线(两套交替 = 灯火微闪)
      ring_0.png … ring_3.png                                        点灯那一下往外扩的细光环(4 档, 由内到外渐暗)
      rays.png                                                       点灯那一下的像素光芒
      letter_0.png … letter_7.png                                    L A M P F I S H(逐个弹出)
      zh.png                                                         「灯鱼游戏」(融合像素 12 号, 字距拉开)
    assets/audio/sfx/studio_intro.wav                                点灯「叮」+ 字弹出时的上行琶音(合成, 方波 / 三角波)

  硬边、零半透明(alpha 只有 0 / 255)。

  python tools/build_studio_intro.py            生成全部
"""
import io
import math
import os
import struct
import sys
import wave

from PIL import Image, ImageDraw, ImageFont

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "assets", "sprites", "ui", "studio_intro")
WAV = os.path.join(ROOT, "assets", "audio", "sfx", "studio_intro.wav")
F_ZH = os.path.join(ROOT, "assets", "fonts", "fusion-pixel-12px-zh_hans.otf")

T = (0, 0, 0, 0)
BG = (10, 14, 24)                      # = project.godot boot_splash/bg_color, iPhone 启动屏同色
CREAM = (246, 238, 214)
ZH_COL = (176, 184, 200)               # 中文副标: 冷灰, 比主标退一档(凉屋「凉屋游戏」同一层级)
GOLD_HOT = (255, 250, 214)
GOLD_HI = (255, 226, 120)
GOLD = (255, 196, 54)
GOLD_SH = (226, 140, 30)
GLASS_OFF = (58, 64, 80)
GLASS_OFF_HI = (86, 94, 112)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# ═══════════════════════════════ 小鱼(29 × 19) ═══════════════════════════════
FW, FH = 29, 19
LANTERN = (3, 5)                       # 灯玻璃中心(光晕与光芒的圆心, 游戏里按它对齐)
EYE = (10, 7)                          # 眼睛(2×2 镂空)左上角


def fish_mask():
    """小鱼剪影的实心像素: 横椭圆身体 + 分叉尾 + 沿背低鳍 + 钓竿 + 灯框。"""
    m = set()
    cx, cy, rx, ry = 15.0, 10.0, 8.5, 6.4
    for y in range(FH):
        for x in range(FW):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                m.add((x, y))
    # 尾: x 23..27, 外沿越往外越张开, 中间 V 形缺口(分叉)
    for x in range(23, 28):
        k = x - 23
        outer, notch = 2.2 + 1.2 * k, max(0.0, 0.9 * k - 1.4)
        for y in range(FH):
            dy = abs(y - cy)
            if dy <= outer and dy > notch - 0.01 and not (notch > 0 and dy < notch):
                m.add((x, y))
    # 背鳍: 背上一道低鳍(身体上沿再加一格), 中间一个小尖
    for x in range(13, 20):
        top = min(y for (xx, y) in m if xx == x)
        m.add((x, top - 1))
    m.add((16, min(y for (xx, y) in m if xx == 16) - 1))
    m.add((17, min(y for (xx, y) in m if xx == 17) - 1))
    # 钓竿: 额头往上往前弯, 落到灯顶钮
    for (x, y) in [(11, 4), (10, 3), (9, 2), (8, 1), (7, 1), (6, 1), (5, 1), (4, 1), (3, 2)]:
        m.add((x, y))
    # 灯框: 顶盖 / 两侧 / 底座(玻璃 3×3 另上色)
    lx, ly = LANTERN
    for x in range(lx - 1, lx + 2):
        m.add((x, ly - 2))
    for y in range(ly - 1, ly + 2):
        m.add((lx - 2, y)); m.add((lx + 2, y))
    for x in range(lx - 2, lx + 3):
        m.add((x, ly + 2))
    for x in range(lx - 1, lx + 2):
        m.add((x, ly + 3))
    return m


def glass_cells():
    lx, ly = LANTERN
    return [(x, y) for y in range(ly - 1, ly + 2) for x in range(lx - 1, lx + 2)]


def draw_fish(state):
    """state: on / off(睡着、灯灭) / blink(眨眼) / flash(点灯那一下, 眼睛瞪大)"""
    im = Image.new("RGBA", (FW, FH), T)
    px = im.load()
    for (x, y) in fish_mask():
        px[x, y] = CREAM + (255,)
    ex, ey = EYE
    if state in ("off", "blink"):
        px[ex, ey + 1] = T; px[ex + 1, ey + 1] = T                      # 闭眼: 一条线
    elif state == "flash":
        for (x, y) in [(ex, ey - 1), (ex + 1, ey - 1), (ex, ey), (ex + 1, ey), (ex, ey + 1), (ex + 1, ey + 1)]:
            px[x, y] = T                                                # 瞪大: 2×3
    else:
        for (x, y) in [(ex, ey), (ex + 1, ey), (ex, ey + 1), (ex + 1, ey + 1)]:
            px[x, y] = T                                                # 圆点眼 2×2
    # 嘴: 前缘一道往上翘的缺口(笑); 睡着时只剩一个点
    mouth = [(7, 12), (8, 12)] if state == "off" else [(7, 11), (7, 12), (8, 12), (9, 12), (10, 11)]
    for (x, y) in mouth:
        px[x, y] = T
    # 灯玻璃
    lx, ly = LANTERN
    for (x, y) in glass_cells():
        if state == "off":
            c = GLASS_OFF_HI if (x, y) == (lx - 1, ly - 1) else GLASS_OFF
        elif state == "flash":
            c = GOLD_HOT
        else:
            c = GOLD_HOT if (x, y) == (lx, ly) else (GOLD_HI if y < ly + 1 else GOLD)
        px[x, y] = c + (255,)
    return im


# ═══════════════════════════════ 光晕 / 光芒 ═══════════════════════════════
def ticks_img(phase, size=17):
    """灯周围的短光线(平时): 8 个方向各一道 2 格短线, phase 0 / 1 两套长短交替 —— 扁平图标表现「亮着」的画法, 不画实心光晕。"""
    im = Image.new("RGBA", (size, size), T)
    px = im.load()
    c = size // 2
    for i, (dx, dy) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))):
        diag = i >= 4
        r0 = 5 if not diag else 4
        n = (2 if (i + phase) % 2 == 0 else 1) if not diag else 1
        for k in range(r0, r0 + n):
            px[c + dx * k, c + dy * k] = (GOLD if not diag else GOLD_SH) + (255,)
    return im


def ring_img(r, col, size):
    """点灯那一下往外扩的细光环(1 格粗)。"""
    im = Image.new("RGBA", (size, size), T)
    px = im.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            if r - 0.5 <= d < r + 0.5:
                px[x, y] = col + (255,)
    return im


def rays_img(size=33):
    im = Image.new("RGBA", (size, size), T)
    px = im.load()
    c = size // 2
    for k in range(5, c + 1):
        col = (GOLD_HI if k < c - 3 else GOLD) + (255,)
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px[c + dx * k, c + dy * k] = col
    for k in range(4, c - 5):
        for (dx, dy) in ((1, 1), (-1, -1), (1, -1), (-1, 1)):
            px[c + dx * k, c + dy * k] = (GOLD + (255,)) if k % 2 == 0 else (GOLD_SH + (255,))
    return im


# ═══════════════════════════════ 字 ═══════════════════════════════
LETTERS = {
    "L": ["##....", "##....", "##....", "##....", "##....", "##....", "##....", "######", "######"],
    "A": [".####.", "######", "##..##", "##..##", "######", "######", "##..##", "##..##", "##..##"],
    "M": ["##....##", "###..###", "########", "##.##.##", "##....##", "##....##", "##....##", "##....##", "##....##"],
    "P": ["#####.", "######", "##..##", "##..##", "######", "#####.", "##....", "##....", "##...."],
    "F": ["######", "######", "##....", "##....", "#####.", "#####.", "##....", "##....", "##...."],
    "I": ["##"] * 9,
    "S": [".#####", "######", "##....", "#####.", ".#####", "....##", "....##", "######", "#####."],
    "H": ["##..##", "##..##", "##..##", "######", "######", "##..##", "##..##", "##..##", "##..##"],
}
WORD = "LAMPFISH"
LETTER_GAP = 2


def letter_img(ch):
    rows = LETTERS[ch]
    w, h = len(rows[0]), len(rows)
    im = Image.new("RGBA", (w, h), T)
    px = im.load()
    for y, r in enumerate(rows):
        assert len(r) == w, ch
        for x, c in enumerate(r):
            if c == "#":
                px[x, y] = CREAM + (255,)
    return im


def word_layout():
    """每个字母在整条字标里的 x 偏移(1 倍像素)与整条宽度。"""
    xs, x = [], 0
    for ch in WORD:
        xs.append(x)
        x += len(LETTERS[ch][0]) + LETTER_GAP
    return xs, x - LETTER_GAP


def zh_img(text="灯鱼游戏", spacing=6):
    f = ImageFont.truetype(F_ZH, 12)
    parts = []
    for ch in text:
        m = Image.new("L", (16, 16), 0)
        d = ImageDraw.Draw(m)
        d.fontmode = "1"
        d.text((0, 0), ch, font=f, fill=255)
        parts.append(m)
    w = 12 * len(text) + spacing * (len(text) - 1)
    im = Image.new("RGBA", (w, 13), T)
    px = im.load()
    for i, m in enumerate(parts):
        mp = m.load()
        for y in range(13):
            for x in range(12):
                if mp[x, y] > 127:
                    px[i * (12 + spacing) + x, y] = ZH_COL + (255,)
    return im


# ═══════════════════════════════ 音效 ═══════════════════════════════
SR = 44100
TIMING = {                 # 秒; 游戏脚本 scripts/scenes/studio_intro.gd 用同一组数(门禁对账)
    "spark1": 0.05, "spark2": 0.13, "ignite": 0.22,
    "letters": 0.52, "letter_step": 0.045, "zh": 0.98, "blink": 1.45,
    "fade": 2.2, "end": 2.5,
}
NOTES = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3, 2637.0]   # C6 D6 E6 G6 A6 C7 D7 E7(五声上行)


def synth():
    n = int(SR * TIMING["end"])
    buf = [0.0] * n

    def add(t0, freq, dur, vol, wave_kind="square", decay=12.0):
        i0 = int(t0 * SR)
        for i in range(int(dur * SR)):
            if i0 + i >= n:
                break
            t = i / SR
            ph = (freq * t) % 1.0
            if wave_kind == "square":
                s = 1.0 if ph < 0.5 else -1.0
            elif wave_kind == "tri":
                s = 4 * abs(ph - 0.5) - 1
            else:
                s = math.sin(2 * math.pi * ph)
            env = math.exp(-decay * t) * min(1.0, t / 0.004)
            buf[i0 + i] += s * env * vol

    # 两下火星(很轻的短促方波)
    add(TIMING["spark1"], 1975.5, 0.04, 0.10, "square", 60)
    add(TIMING["spark2"], 2217.5, 0.04, 0.10, "square", 60)
    # 点灯「叮」: 三角波主音 + 高八度方波泛音, 长尾
    add(TIMING["ignite"], 1568.0, 0.9, 0.42, "tri", 4.5)
    add(TIMING["ignite"], 3136.0, 0.5, 0.10, "square", 9.0)
    add(TIMING["ignite"], 784.0, 0.35, 0.18, "sine", 8.0)
    # 字母逐个弹出: 上行五声琶音(每个字母一个音)
    for i, f in enumerate(NOTES):
        add(TIMING["letters"] + i * TIMING["letter_step"], f, 0.22, 0.16, "square", 16.0)
    # 中文副标落定: 低一点的和音
    add(TIMING["zh"], 1046.5, 0.6, 0.14, "tri", 5.0)
    add(TIMING["zh"], 1568.0, 0.6, 0.10, "tri", 5.0)
    # 收尾淡出
    f0, f1 = int(TIMING["fade"] * SR), n
    for i in range(f0, f1):
        buf[i] *= 1.0 - (i - f0) / (f1 - f0)
    peak = max(abs(v) for v in buf) or 1.0
    return [v / peak * 0.80 for v in buf]


def write_wav(samples, path):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))
    data = bio.getvalue()
    if not (os.path.exists(path) and open(path, "rb").read() == data):
        open(path, "wb").write(data)


def save(im, name):
    p = os.path.join(DIR, name)
    bio = io.BytesIO()
    im.save(bio, "PNG", optimize=False)
    data = bio.getvalue()
    if not (os.path.exists(p) and open(p, "rb").read() == data):
        open(p, "wb").write(data)
    # 零半透明
    a = im.getchannel("A") if im.mode == "RGBA" else None
    if a is not None:
        assert set(a.getdata()) <= {0, 255}, name


def build():
    os.makedirs(DIR, exist_ok=True)
    for st in ("on", "off", "blink", "flash"):
        save(draw_fish(st), "fish_%s.png" % st)
    save(ticks_img(0), "ticks_0.png")
    save(ticks_img(1), "ticks_1.png")
    for i, (r, col) in enumerate([(6, GOLD_HI), (9, GOLD), (12, GOLD_SH), (15, mix(BG, GOLD_SH, 0.5))]):
        save(ring_img(r, col, 33), "ring_%d.png" % i)
    save(rays_img(), "rays.png")
    for i, ch in enumerate(WORD):
        save(letter_img(ch), "letter_%d.png" % i)
    save(zh_img(), "zh.png")
    write_wav(synth(), WAV)
    print("ok", DIR, WAV)


if __name__ == "__main__":
    build()
