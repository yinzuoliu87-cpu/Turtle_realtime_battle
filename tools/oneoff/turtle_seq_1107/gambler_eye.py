"""赌神眼神(用户 11-06「不要限制他的眼神」): 把定稿上的新眼睛贴回 pet_seq/gambler 每一帧。

做法: 旧定稿 old 与新定稿 new 只有眼睛那一小块不同(Pro Flash 只改眼睛), 差异块 = 要贴的补丁。
每帧在 ±10 像素内找旧眼周的位置, 像素相符率 ≥ MATCH 才贴; 头转开的过渡帧找不到就不动。
对已经贴过的帧跑第二遍: 旧眼周匹配不上, 不会重复贴。
用法: python gambler_eye.py <旧定稿.png> <新定稿.png> <pet_seq/gambler 目录>
"""
import glob
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
OLD, NEW, ROOT = sys.argv[1:4]
MATCH = 0.72
old = Image.open(OLD).convert("RGBA")
new = Image.open(NEW).convert("RGBA")
op, np_ = old.load(), new.load()
## 只认脸上的差异(帽子以下、下巴以上), 别把 AI 顺手改的衣服带进来
FACE = (50, 56, 86, 78)
diff = [(x, y) for y in range(FACE[1], FACE[3]) for x in range(FACE[0], FACE[2]) if sum(abs(op[x, y][k] - np_[x, y][k]) for k in range(4)) > 30]
x0, x1 = min(p[0] for p in diff), max(p[0] for p in diff)
y0, y1 = min(p[1] for p in diff), max(p[1] for p in diff)
print("补丁 %d 像素, 外框 x%d~%d y%d~%d" % (len(diff), x0, x1, y0, y1))
PAD = 3
tmpl = [(x, y) for y in range(y0 - PAD, y1 + PAD + 1) for x in range(x0 - PAD, x1 + PAD + 1) if op[x, y][3]]


def find(px, W, H):
    best, at = 0.0, None
    for dy in range(-8, 9):
        for dx in range(-10, 11):
            ok = 0
            for x, y in tmpl:
                X, Y = x + dx, y + dy
                if 0 <= X < W and 0 <= Y < H:
                    p = px[X, Y]
                    q = op[x, y]
                    if p[3] and abs(p[0] - q[0]) + abs(p[1] - q[1]) + abs(p[2] - q[2]) < 36:
                        ok += 1
            r = ok / float(len(tmpl))
            if r > best:
                best, at = r, (dx, dy)
    return best, at


tot = hit = 0
for d in sorted(glob.glob(os.path.join(ROOT, "*"))):
    if not os.path.isdir(d):
        continue
    fs = sorted(glob.glob(os.path.join(d, "f_*.png")))
    n = 0
    for f in fs:
        im = Image.open(f).convert("RGBA")
        px = im.load()
        r, at = find(px, im.width, im.height)
        tot += 1
        if r < MATCH:
            continue
        for x, y in diff:
            px[x + at[0], y + at[1]] = np_[x, y]
        im.save(f, optimize=False)
        n += 1
        hit += 1
    print("%-24s %2d/%2d" % (os.path.basename(d), n, len(fs)))
print("合计 %d/%d 帧" % (hit, tot))
