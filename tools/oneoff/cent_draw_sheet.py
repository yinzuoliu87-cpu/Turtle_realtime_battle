"""cent_draw_sheet.py —— 百夫长手画过程图拼一张(剪影 → 平涂 → 暗部 → 亮部 → 细节 → 描边, 3 倍) + 成品放大 4 倍(自查用)。
    python tools/oneoff/cent_draw_sheet.py <过程图目录>
"""
import sys
from PIL import Image

d = sys.argv[1]
names = ["1_剪影", "2_平涂", "3_暗部", "4_亮部", "5_细节", "6_描边"]
ims = [Image.open("%s/%s.png" % (d, n)).convert("RGBA") for n in names]
out = Image.new("RGBA", (128 * 6, 128), (70, 78, 52, 255))
for i, im in enumerate(ims):
    out.alpha_composite(im, (i * 128, 0))
out.resize((out.width * 3, out.height * 3), Image.NEAREST).save("%s/process.png" % d)
big = Image.new("RGBA", (128, 128), (70, 78, 52, 255))
big.alpha_composite(ims[-1])
big.resize((512, 512), Image.NEAREST).save("%s/final_big.png" % d)
print("ok")
