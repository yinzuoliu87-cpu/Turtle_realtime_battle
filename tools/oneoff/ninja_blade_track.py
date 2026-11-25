"""ninja_blade_track.py —— 暗影忍者动作条逐帧标刀尖 / 刀柄并画路径(2026-11-25 自查, memory fb-mark-weapon-path-before-showing)

刀身 = 亮度 >= 60、低饱和(衣服 27~51)的钢灰像素(忍者衣服是近黑、皮肤是绿, 都不算); 每帧取最大的两块(两把刀)。
每块: 离身体中心最远的点 = 刀尖, 最近的点 = 刀柄。输出放大 4 倍的叠图: 红点 = 前手刀尖、黄 = 后手刀尖, 连线 = 刀尖逐帧路径。

    python tools/oneoff/ninja_blade_track.py eq-ninja-attack
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def blades(im):
    px = im.load()
    pts = set()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 128 and max(r, g, b) >= 60 and max(r, g, b) - min(r, g, b) <= 22:
                pts.add((x, y))
    comps, seen = [], set()
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
        if len(comp) >= 6:
            comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps[:2]


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "eq-ninja-attack"
    strip = Image.open(os.path.join(ROOT, "assets", "sprites", "vfx", name + ".png")).convert("RGBA")
    n = strip.width // strip.height
    fs = [strip.crop((i * strip.height, 0, (i + 1) * strip.height, strip.height)) for i in range(n)]
    S = 4
    out = Image.new("RGBA", (strip.height * S * n, strip.height * S), (60, 60, 70, 255))
    d = ImageDraw.Draw(out)
    tips = []
    for i, f in enumerate(fs):
        out.alpha_composite(f.resize((f.width * S, f.height * S), Image.NEAREST), (i * f.width * S, 0))
        bb = f.getbbox()
        cx, cy = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2
        row = []
        for comp in blades(f):
            tip = max(comp, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
            hilt = min(comp, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
            row.append((tip, hilt, len(comp)))
        row.sort(key=lambda t: t[0][0])   # 左边(朝敌人那侧)的算前手
        tips.append(row)
        for k, (tip, hilt, sz) in enumerate(row):
            col = (255, 40, 40, 255) if k == 0 else (255, 220, 0, 255)
            ox = i * f.width * S
            d.line([(ox + hilt[0] * S, hilt[1] * S), (ox + tip[0] * S, tip[1] * S)], fill=col, width=2)
            d.ellipse([ox + tip[0] * S - 5, tip[1] * S - 5, ox + tip[0] * S + 5, tip[1] * S + 5], outline=col, width=2)
        d.text((i * f.width * S + 6, 6), str(i), fill=(255, 255, 255, 255))
    p = os.path.join(ROOT, ".out", "shots", "ninja_track_%s.png" % name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    out.save(p)
    for i, row in enumerate(tips):
        print(i, " | ".join("刀尖(%d,%d) 柄(%d,%d) %d像素" % (t[0][0], t[0][1], t[1][0], t[1][1], t[2]) for t in row))
    print(p)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
