# -*- coding: utf-8 -*-
"""vfx_contact_sheet.py — 把一批候选帧铺成【接触印相】给人看。

★由来(2026-09-06)：用户「我服了你说对齐lol呢？这么差质量」。
  根因不是某个数算错了，是**我只用数值筛选素材，从没问过一句"它看起来像剑气吗"**。
  随后实测三个数值判据(细长比/黑描边占比/弧包角)**全都分不开**"剑气"和"月亮"
  —— 详见 tools/vfx_sheet_audit.py 头注那张表。
  ⇒ 形状好不好看只能人看。既然必须人看，这一步就要有工具，别每次现写。

跑法:
  python tools/vfx_contact_sheet.py <目录或文件...> -o out.png [--scale 4] [--cols 8] [--grid 8x4]
"""
import argparse
import glob
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("[SKIP] 没装 Pillow")
    sys.exit(0)

## 深灰底 —— 特效素材几乎都是亮色, 白底上看不清边缘, 黑底上看不清暗部。
BG = (34, 34, 40)
LABEL = (210, 210, 130)


_OUT = [""]


def expand(paths, grid=None):
    """目录 → 里面的 png; 精灵表 → 逐帧切开。

    ★格数默认按宽高比推 —— 那**只对横条带管用**。8×4 的方向表(256×160)会被推成 2 格,
      印相只剩两张宽图, 等于没看。多行表必须显式 `--grid 8x4`。
    """
    out = []
    for p in paths:
        for f in (sorted(glob.glob(os.path.join(p, "*.png"))) if os.path.isdir(p) else [p]):
            if f.endswith(".import"):
                continue
            if os.path.abspath(f) == _OUT[0]:
                continue          # 跳过自己的输出
            im = Image.open(f).convert("RGBA")
            base = os.path.splitext(os.path.basename(f))[0]
            if grid:
                gc, gr = grid
            else:
                gc = max(1, round(im.width / im.height)) if im.width > im.height else 1
                gr = 1
            if gc == 1 and gr == 1:
                out.append((base, im))
                continue
            fw, fh = im.width // gc, im.height // gr
            for r in range(gr):
                for c in range(gc):
                    lab = ("%s c%d" % (base, c)) if gr == 1 else ("c%d f%d" % (c, r))
                    out.append((lab, im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("-o", "--out", default="contact.png")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--grid", default=None,
                    help="精灵表的格数, 形如 8x4(横8方向 × 纵4帧)。多行表必须给, 否则按宽高比推会推错")
    a = ap.parse_args()

    g = None
    if a.grid:
        gc, gr = a.grid.lower().split("x")
        g = (int(gc), int(gr))
    ## ★输出别落在输入目录里: 我把 contact.png 写进候选目录, 下一次跑它被当成候选读进来,
    ##   再拼 → 4 亿像素, PIL 直接当解压炸弹拒了。工具自己挡掉。
    _OUT[0] = os.path.abspath(a.out)
    items = [(n, im) for n, im in expand(a.paths, g)]
    if not items:
        print("[FAIL] 一张图都没收到 —— 空印相不是通过")   # ★分母
        return 1

    S, C = a.scale, a.cols
    cw = max(im.width for _, im in items) * S
    ch = max(im.height for _, im in items) * S + 12
    rows = (len(items) + C - 1) // C
    sheet = Image.new("RGB", (cw * C, ch * rows), BG)
    d = ImageDraw.Draw(sheet)
    for k, (nm, im) in enumerate(items):
        r = im.resize((im.width * S, im.height * S), Image.NEAREST)
        x, y = (k % C) * cw, (k // C) * ch
        sheet.paste(r, (x + (cw - r.width) // 2, y + 12), r)
        d.text((x + 2, y + 1), nm[:16], fill=LABEL)
    sheet.save(a.out)
    print("  %s  %dx%d  —— %d 格(分母), 每格放大 %dx" % (a.out, sheet.width, sheet.height, len(items), S))
    print("  ★这是给【人】看的。别拿数值筛完就当选好了。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
