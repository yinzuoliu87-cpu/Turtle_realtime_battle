"""study_sheets_1127.py —— 面具 / 长矛 / 筹码批 96 张特效素材逐帧研究用的看图表(产物在 .out/study/, 不进仓库)
每张素材按帧切开、每帧放大到最长边约 112 像素、左上角标帧号, 6 张素材一页。帧数来自打包脚本输出 + 代码里的 hframes。
    python tools/oneoff/study_sheets_1127.py
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
OUT = os.path.join(ROOT, ".out", "study")

## 名字 → 帧数(单行横排); 两行的另记
NF = {
    "mask-gold-beam-anim": 6, "mask-gold-splash": 6, "mask-gold-smoke": 6, "ow-hand": 9, "ow-mist": 9, "ow-rift": 4, "ow-pillar2": 6,
    "ow-wisp": 4, "ow-aura": 8, "ow-sigil": 4, "mask-venice-mask": 8, "mask-venice-halo": 8, "mask-venice-burst": 9, "mask-copy-spirit": 4,
    "mask-gift-orb": 4, "mask-face-rk": 4, "mask-face-kw": 7, "mask-face-wr": 7, "mask-face-redhit": 7, "mask-clown-jeer": 4,
    "mask-paper-blade": 4, "mask-ghost-puff": 9, "mask-gas-block": 7, "mask-lion-pop": 9, "mask-lion-hit": 9, "mask-lion-ribbon": 6,
    "mask-lion-bite": 8, "mask-clown-burst": 9, "mask-lion-gather": 7, "mask-lion-speed": 4, "mask-lion-shock": 11,
    "eq-masklion-charge-fire": 8, "mask-fox-fire": 7, "eq-masklion-idle": 6, "eq-masklion-charge": 8, "eq-masklion-windup": 7,
    "eq-masklion-attack": 13, "eq-masklion-walk": 8, "eq-masklion-death": 12,
    "spear-cent-crack": 8, "spear-cent-marker": 8, "spear-cent-trail": 6, "eq-centurion-idle": 4, "eq-centurion-walk": 6,
    "eq-centurion-attack": 10, "eq-centurion-attack-glow": 10, "eq-centurion-throw": 15, "eq-centurion-rise": 12,
    "eq-centurion-brace": 42, "eq-centurion-shield": 42, "eq-centurion-sweep": 12, "eq-centurion-death": 12, "eq-cavalry-run": 8,
    "spear-lance-hit": 7, "spear-halb-sweep": 7, "spear-ftj-ring": 6, "spear-holy-mark": 4, "spear-holy-burst": 9,
    "chip-spin-black": 6, "chip-spin-purple": 6, "chip-grey-flare": 7, "chip-spin-brown": 6, "chip-spin-yellow": 6, "chip-gold-dome": 6,
    "spear-bamboo-spike": 13, "spear-lance-ready": 4, "spear-scutum": 4, "spear-shsp-wave": 7, "spear-ftj-charge": 6, "spear-ftj-crater": 9,
    "spear-atl-stuck": 7, "spear-cent-impact": 8, "spear-hit-spark": 6, "spear-harpoon-splash": 9, "spear-cent-sweep": 9,
    "spear-atl-target": 4, "spear-javelin-blood": 7, "chip-brown-rise": 7, "chip-shield-glint": 7, "spear-cav-speed": 4,
    "spear-cav-dustbow": 6, "spear-cent-thrust": 7,
    "ow-brazier": 8, "ow-maskA": 8, "ow-maskB": 8, "mask-gold-ring": 1,
    "ow-circle": 1, "ow-pillar": 1, "ow-tile": 1, "spear-atl-fall": 1, "spear-cent-plant": 1, "spear-gungnir": 1, "spear-harpoon": 1,
    "spear-javelin": 1, "spear-pilum": 1, "spear-rope": 1,
}
TWO_ROW = {"eq-centurion-brace": 21, "eq-centurion-shield": 21}   # 每行 21 帧
CELL = 112


def frames_of(name):
    im = Image.open(os.path.join(VFX, name + ".png")).convert("RGBA")
    n = NF[name]
    if name in TWO_ROW:
        cols = TWO_ROW[name]
        fw = im.width // cols
        fh = im.height // 2
        return [im.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh)) for i in range(n)]
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sorted(NF)
    want = [l.strip() for l in open(os.path.join(ROOT, ".out", "pc", "vfx_need2.txt"), encoding="utf-8") if l.strip()]
    missing = [w for w in want if w[:-4] not in NF]
    assert not missing, missing
    total = 0
    page, rows = 0, []
    for nm in names:
        fr = frames_of(nm)
        total += len(fr)
        per = 14
        for start in range(0, len(fr), per):
            rows.append((nm, start, fr[start:start + per]))
    ## 每页 6 行
    for p in range(0, len(rows), 6):
        chunk = rows[p:p + 6]
        sheet = Image.new("RGBA", (CELL * 14 + 10, (CELL + 18) * len(chunk)), (58, 66, 54, 255))
        d = ImageDraw.Draw(sheet)
        for r, (nm, start, fr) in enumerate(chunk):
            y = r * (CELL + 18)
            d.text((4, y + 2), "%s  (frames %d..%d)" % (nm, start, start + len(fr) - 1), fill=(255, 240, 120, 255))
            for i, f in enumerate(fr):
                k = min(CELL / f.width, CELL / f.height)
                g = f.resize((max(1, int(f.width * k)), max(1, int(f.height * k))), Image.NEAREST)
                x = i * CELL + 5
                sheet.alpha_composite(g, (x + (CELL - g.width) // 2, y + 16 + (CELL - g.height) // 2))
                d.rectangle([x, y + 16, x + CELL - 1, y + 16 + CELL - 1], outline=(30, 30, 30, 255))
                d.text((x + 2, y + 17), str(start + i), fill=(255, 255, 255, 255))
        sheet.save(os.path.join(OUT, "sheet_%02d.png" % page))
        page += 1
    print("素材", len(names), "张 · 帧", total, "· 页", page)


if __name__ == "__main__":
    main()
