"""cent_char_sheets.py —— 下载 PixelLab 百夫长角色包, 每个动作拼一行帧表(自查用)。
    python tools/oneoff/cent_char_sheets.py <角色 id> <输出目录>
"""
import sys, os, glob, zipfile, urllib.request
from PIL import Image

cid, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
zp = os.path.join(out, "char.zip")
urllib.request.urlretrieve("https://api.pixellab.ai/mcp/characters/%s/download" % cid, zp)
x = os.path.join(out, "x")
zipfile.ZipFile(zp).extractall(x)
anims = sorted(os.listdir(os.path.join(x, "Idle", "animations")))
for a in anims:
    fs = sorted(glob.glob(os.path.join(x, "Idle", "animations", a, "south-west", "*.png")))
    if not fs:
        continue
    fr = [Image.open(f).convert("RGBA") for f in fs]
    w, h = fr[0].size
    sheet = Image.new("RGBA", (w * len(fr), h), (70, 78, 52, 255))
    for i, f in enumerate(fr):
        sheet.alpha_composite(f, (i * w, 0))
    sheet.save(os.path.join(out, "sheet_%s.png" % a))
    print(a, len(fr), (w, h))
