"""equip_icon_candidates_1124.py —— 下载 PixelLab 候选并排成候选表(装备图标去 AI 味, 方案书 20261124c)

  python tools/oneoff/equip_icon_candidates_1124.py <标签> <job_id> [张数=16]
    ⇒ .out/equip_icons/<标签>/cand_<i>.png + .out/equip_icons/<标签>_sheet.png(4×4, 每张 2 倍 + 编号, 旁边放一张现有图标作尺子)
"""
import os, sys, urllib.request
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, ".out", "equip_icons")
RULER = os.path.join(ROOT, "assets", "sprites", "equip", "p2eq_060.png")   # 水母伞: 现有干净 64px 图标


def fetch(job, i, dst):
    url = "https://api.pixellab.ai/mcp/images/%s/download?index=%d" % (job, i)
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with op.open(url, timeout=60) as r:
        open(dst, "wb").write(r.read())


def main():
    tag, job = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    ims = []
    for i in range(n):
        p = os.path.join(d, "cand_%d.png" % i)
        if not os.path.exists(p):
            fetch(job, i, p)
        ims.append(Image.open(p).convert("RGBA"))
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
    S = 128
    cols = 4
    rows = (n + cols - 1) // cols
    W = Image.new("RGBA", (cols * (S + 10) + S + 30, rows * (S + 24) + 10), (34, 38, 46, 255))
    dr = ImageDraw.Draw(W)
    for i, im in enumerate(ims):
        x, y = 10 + (i % cols) * (S + 10), 10 + (i // cols) * (S + 24)
        b = im.resize((S, S), Image.NEAREST)
        W.paste(b, (x, y), b)
        dr.text((x + 4, y + S), str(i), fill=(255, 214, 90), font=f)
    r = Image.open(RULER).convert("RGBA").resize((S, S), Image.NEAREST)
    W.paste(r, (10 + cols * (S + 10) + 10, 10), r)
    dr.text((10 + cols * (S + 10) + 10, 10 + S), "尺子:水母伞", fill=(150, 160, 175), font=f)
    p = os.path.join(OUT, tag + "_sheet.png")
    W.save(p)
    print(p)


if __name__ == "__main__":
    main()
