"""cent_anim_preview.py —— 百夫长逐帧动作自查: 六步帧表竖着拼一张(3 倍) + 成品帧表放大 + 动图(按帧率)。
    python tools/oneoff/cent_anim_preview.py <目录> <动作名> <帧率>
"""
import sys
from PIL import Image

d, anim, fps = sys.argv[1], sys.argv[2], float(sys.argv[3])
rows = [Image.open("%s/%s_%d.png" % (d, anim, k)).convert("RGBA") for k in range(1, 7)]
w, h = rows[0].size
bg = (70, 78, 52, 255)
out = Image.new("RGBA", (w, h * 6), bg)
for i, r in enumerate(rows):
    out.alpha_composite(r, (0, i * h))
out.resize((w * 2, h * 12), Image.NEAREST).save("%s/%s_process.png" % (d, anim))
fin = rows[-1]
n = w // 128
big = Image.new("RGBA", (w, h), bg)
big.alpha_composite(fin)
big.resize((w * 3, h * 3), Image.NEAREST).save("%s/%s_final.png" % (d, anim))
frames = []
for i in range(n):
    f = Image.new("RGBA", (128, 128), bg)
    f.alpha_composite(fin.crop((i * 128, 0, (i + 1) * 128, 128)))
    frames.append(f.resize((384, 384), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
frames[0].save("%s/%s.gif" % (d, anim), save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0)
print("ok", n)
