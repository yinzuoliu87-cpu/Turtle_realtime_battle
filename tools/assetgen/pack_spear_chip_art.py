"""pack_spear_chip_art.py —— 长矛羁绊(方案书 20261126)与筹码(20261126b)的美术打包

来源(如实, 没有一张是手画的; 也没有照任何参考 —— 百夫长 / 骑兵形象按「罗马百夫长」通用印象写进提示词):
  · 图标: 长矛 137–146 / 筹码 147–156 = PixelLab create_image_pro_flash 64×64, 风格锚 = 110 苦无图标;
    筹码 148–156 再以 147 白色筹码为风格锚(同一枚筹码只换颜色); 149 红 / 150 绿 / 152 紫第一版整面是白的、只有边条带色, 重出(icon149/150/152 已覆盖)。
    标签 tag-spear / tag-chip = 32×32, 风格锚 = 魔法书标签。
  · 百夫长: 原画 cent_0(create_image_pro_flash 112×112)朝向不清(刺击往右捅、掷矛往左扔)⇒ 左右翻转成 centL_0(朝左、盾在前),
    两套各自 animate_image(待机 / 走路 / 刺 / 掷 首尾钉原画, 举盾只钉首帧); 最后怎么拼见下面 STRIPS 上方的注释(两套朝向都不严格)。
  · 骑兵: cav_0(128×112)+ animate_image 首尾钉原画 8 帧奔跑。
  · 飞行物: pilum(百夫长掷矛)/ javelin(139 标枪)/ dart(144 投矛器)/ gungnir(145 永恒之枪)各一张, 朝右; 引擎里按方向转。
本脚本只做拷贝 / 拼接 / 量化, 重跑逐字节相同。

    python tools/assetgen/pack_spear_chip_art.py
"""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SP = os.path.join(ROOT, "tools", "assetgen", "ai_src", "spear")
CH = os.path.join(ROOT, "tools", "assetgen", "ai_src", "chip")
EQ = os.path.join(ROOT, "assets", "sprites", "equip")
TAGS = os.path.join(ROOT, "assets", "sprites", "tags")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")

## 11-26 夜自查(如实): PixelLab 出的是半侧身姿势, 两版的朝向都不严格 —— cent_0 一套里待机 / 走路 / 掷矛朝左、刺击往右捅;
##   左右翻转的 centL_0 一套里刺击往右捅、掷矛朝左。按「整套朝左」拼: 待机 / 走路 / 掷矛 = cent_0 那套, 刺击 = centL_0 那套再翻回来(往左捅),
##   举盾两套都没把盾举起来(cent_0 那套是压低长矛、盾在身侧), 先用 cshd, 待重做。第三个元素 True = 左右翻转。
STRIPS = {
    "eq-centurion-idle": [(SP, "cidle_%d" % i, False) for i in range(0, 6)],
    "eq-centurion-walk": [(SP, "cwalk_%d" % i, False) for i in range(1, 9)],
    "eq-centurion-attack": [(SP, "latk_%d" % i, True) for i in range(1, 11)],
    "eq-centurion-throw": [(SP, "cthr_%d" % i, False) for i in range(1, 11)],
    "eq-centurion-shield": [(SP, "cshd_%d" % i, False) for i in range(1, 7)],
    "eq-cavalry-run": [(SP, "cav_%d" % i, False) for i in range(0, 8)],
}


def _icon(src, dst, maxc=64):
    im = Image.open(src).convert("RGBA")
    if len({p[:3] for p in im.getdata() if p[3] > 0}) <= maxc:
        im.save(dst, optimize=False)
        return
    a = im.getchannel("A")
    q = im.convert("RGB").quantize(colors=maxc, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = q.convert("RGBA")
    out.putalpha(a)
    out.save(dst, optimize=False)


def main():
    for i in range(137, 147):
        _icon(os.path.join(SP, "icon%d.png" % i), os.path.join(EQ, "p2eq_%d.png" % i))
    for i in range(147, 157):
        _icon(os.path.join(CH, "icon%d.png" % i), os.path.join(EQ, "p2eq_%d.png" % i))
    _icon(os.path.join(SP, "tagspear.png"), os.path.join(TAGS, "tag-spear.png"))
    _icon(os.path.join(SP, "tagchip.png"), os.path.join(TAGS, "tag-chip.png"))
    for n in ["pilum", "javelin", "dart", "gungnir"]:
        p = os.path.join(SP, n + ".png")
        if os.path.exists(p):
            _icon(p, os.path.join(VFX, "spear-%s.png" % n))
    for dst, srcs in STRIPS.items():
        ims = []
        for d, n, flip in srcs:
            p = os.path.join(d, n + ".png")
            if not os.path.exists(p):
                ims = []
                break
            im = Image.open(p).convert("RGBA")
            ims.append(im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if flip else im)
        if not ims:
            print("缺帧, 跳过", dst)
            continue
        fw, fh = ims[0].size
        out = Image.new("RGBA", (fw * len(ims), fh), (0, 0, 0, 0))
        for i, im in enumerate(ims):
            assert im.size == (fw, fh), (dst, i, im.size)
            out.paste(im, (i * fw, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(ims), "帧", fw, "×", fh)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
