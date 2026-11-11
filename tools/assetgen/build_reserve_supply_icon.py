"""tools/assetgen/build_reserve_supply_icon.py —— 援军小将第二个被动「随身装备」的图标(2026-11-11)。

用户 11-11:「再一个被动呢就是。会携带一件在背包里未被装备的装备，就是随机携带」。
画面: 一只皮背包, 剑柄从背包口斜着露出来(= 从背包里带一件装备), 剑柄旁一颗小闪光(= 随机抽到的那一件)。
规格照同一只小将的第一个被动图标 assets/sprites/passive/reserve-reinforce-icon.png: 64×64 原生像素、透明度只有 0 / 255、
暗棕描边 + 橙棕皮革(取自那面旗子的调色), 底下一块暗色地影。
确定性: 只用整数坐标画矩形 / 多边形, 不抗锯齿、不读随机数 ⇒ 重跑逐字节相同(tools/README.md 素材脚本规矩)。
仓库根目录 = 本文件往上三层。
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "passive", "reserve-supply-icon.png")

# 调色(前四个取自旗子图标)
OUTLINE = (27, 23, 20, 255)
LEATHER = (138, 60, 27, 255)
LEATHER_HI = (194, 101, 56, 255)
LEATHER_LO = (101, 36, 17, 255)
STRAP = (77, 52, 36, 255)
STITCH = (215, 131, 69, 255)
BUCKLE = (226, 182, 84, 255)
BUCKLE_LO = (160, 118, 44, 255)
STEEL = (196, 204, 214, 255)
STEEL_LO = (128, 138, 152, 255)
GRIP = (58, 40, 30, 255)
SPARK = (255, 236, 150, 255)
SHADOW = (49, 46, 43, 255)


def rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def build() -> Image.Image:
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 地影
    rect(d, 14, 57, 50, 59, SHADOW)
    rect(d, 18, 60, 46, 60, SHADOW)
    # 剑(先画, 背包盖在剑身下半截上): 剑身从背包口往右上斜出
    blade = [(36, 26), (50, 8), (53, 8), (53, 11), (39, 29)]
    d.polygon(blade, fill=STEEL, outline=OUTLINE)
    d.line([(38, 26), (51, 10)], fill=STEEL_LO)
    # 护手(金) + 握柄 + 柄头 —— 剑尖朝下插在包里, 露在外面的是柄; 这里把柄画在右上端
    d.polygon([(46, 6), (49, 3), (58, 12), (55, 15)], fill=BUCKLE, outline=OUTLINE)
    rect(d, 54, 2, 58, 6, GRIP)
    d.rectangle([54, 2, 58, 6], outline=OUTLINE)
    rect(d, 58, 0, 61, 3, BUCKLE)
    d.rectangle([58, 0, 61, 3], outline=OUTLINE)
    # 提手
    d.rectangle([24, 12, 40, 15], fill=STRAP, outline=OUTLINE)
    rect(d, 27, 15, 37, 19, (0, 0, 0, 0))
    d.rectangle([24, 15, 27, 21], fill=STRAP, outline=OUTLINE)
    d.rectangle([37, 15, 40, 21], fill=STRAP, outline=OUTLINE)
    # 包身(圆角: 四角各削一格)
    d.polygon([(13, 22), (51, 22), (53, 24), (53, 54), (51, 56), (13, 56), (11, 54), (11, 24)], fill=LEATHER, outline=OUTLINE)
    rect(d, 12, 25, 13, 53, LEATHER_HI)            # 左侧高光
    rect(d, 49, 26, 52, 54, LEATHER_LO)            # 右侧暗面
    rect(d, 13, 54, 51, 55, LEATHER_LO)            # 底边暗面
    # 包盖
    d.polygon([(12, 22), (52, 22), (52, 33), (46, 38), (18, 38), (12, 33)], fill=LEATHER_LO, outline=OUTLINE)
    rect(d, 14, 24, 50, 25, LEATHER)               # 包盖上沿一道亮边
    for x in range(16, 49, 3):                     # 包盖缝线
        d.point((x, 34), fill=STITCH)
    # 扣带 + 金扣
    rect(d, 29, 36, 35, 47, STRAP)
    d.rectangle([29, 36, 35, 47], outline=OUTLINE)
    d.rectangle([27, 40, 37, 45], fill=BUCKLE, outline=OUTLINE)
    rect(d, 30, 42, 34, 43, BUCKLE_LO)
    # 前袋
    d.rectangle([16, 46, 26, 53], fill=LEATHER_HI, outline=OUTLINE)
    d.rectangle([38, 46, 48, 53], fill=LEATHER_HI, outline=OUTLINE)
    for x in range(18, 26, 2):
        d.point((x, 48), fill=STITCH)
    for x in range(40, 48, 2):
        d.point((x, 48), fill=STITCH)
    # 闪光(四芒星, 包的左上方空处 = 随机抽到的那一件)
    cx, cy = 15, 14
    rect(d, cx, cy - 4, cx, cy + 4, SPARK)
    rect(d, cx - 4, cy, cx + 4, cy, SPARK)
    rect(d, cx - 1, cy - 1, cx + 1, cy + 1, SPARK)
    return im


if __name__ == "__main__":
    img = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, optimize=False)
    print("wrote", OUT)
