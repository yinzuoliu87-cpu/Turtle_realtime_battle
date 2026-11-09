"""拼逐帧对照图(开发用, 输出到 .out/)。
用法: python tools/oneoff/contact_sheet.py <帧目录> <起帧> <止帧> <步长> <x0,y0,x1,y1> <输出png> [每行几张] [放大倍数]
帧文件名按 Godot --write-movie 的 f%08d.png。每格左上角标帧号。"""
import os
import sys

from PIL import Image, ImageDraw


def main() -> int:
    d, a, b, step, box, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6]
    cols = int(sys.argv[7]) if len(sys.argv) > 7 else 4
    scale = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
    x0, y0, x1, y1 = [int(v) for v in box.split(",")]
    tiles = []
    for i in range(a, b + 1, step):
        p = os.path.join(d, "f%08d.png" % i)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB").crop((x0, y0, x1, y1))
        if scale != 1.0:
            im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
        dr = ImageDraw.Draw(im)
        dr.rectangle((0, 0, 44, 16), fill=(0, 0, 0))
        dr.text((3, 2), str(i), fill=(255, 255, 0))
        tiles.append(im)
    if not tiles:
        print("no frames")
        return 1
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, h * rows), (20, 20, 20))
    for k, t in enumerate(tiles):
        sheet.paste(t, ((k % cols) * w, (k // cols) * h))
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    sheet.save(out)
    print("ok", len(tiles), sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
