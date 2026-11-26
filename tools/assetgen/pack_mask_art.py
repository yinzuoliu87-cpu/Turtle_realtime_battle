"""pack_mask_art.py —— 面具羁绊(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)的美术打包

来源(如实, 没有一张是手画的):
  · 装备图标 127–136: PixelLab create_image_pro_flash 64×64, 风格锚 = 110 苦无图标(与魔法书批同一锚); 类型标签 32×32, 风格锚 = 魔法书标签。
    原图在 ai_src/mask/icon*.png / tagmask.png。
  · 130 舞狮: 原画 = create_image_pro_flash 112×112(无锚, 写明严格侧面朝左) lion_0.png;
    待机 / 走路 / 咬 = animate_image 首尾都钉原画(序号 0 = 输入原画); 冲撞 = animate_image 只钉首帧。
  · 135 金光: 光柱 gold_beam.png = create_image_pro_flash 64×256(无锚); 落地光 gold_ground.png = create_image_pro_flash 96×64(无锚)。
    面具升空用的是 135 自己的图标; 光柱的伸缩 / 跟随 / 变亮是引擎里按时间摆(不是逐帧画的)。
  · 136 里世界场景: 地砖 ow_tile(64×64) / 法阵 ow_circle(256×256) / 断柱 ow_pillar / 巨面具两种 ow_maskA·B(128×128) / 鬼火灯台 ow_brazier(48×96)
    = create_image_pro_flash(无锚); 巨面具与鬼火 = animate_image 首尾钉原画 8 帧(owA_0..7 / owB_0..7 / owF_0..7, 序号 8 = 钉住的末帧不取)。
    平台椭圆裁切 / 边缘碎口 / 变暗是着色器(otherworld_ground.gdshader); 摆位见 OtherworldStage。
本脚本只做拷贝 / 拼接 / 量化, 重跑逐字节相同。

    python tools/assetgen/pack_mask_art.py
"""
import os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AI = os.path.join(ROOT, "tools", "assetgen", "ai_src", "mask")
EQ = os.path.join(ROOT, "assets", "sprites", "equip")
TAGS = os.path.join(ROOT, "assets", "sprites", "tags")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
FW = 112

ICONS = {"icon%d" % i: "p2eq_%d" % i for i in range(127, 137)}
TAG = {"tagmask": "tag-mask"}
## 舞狮帧条(源名)。咬的命中帧下标抄到 AttackHits
LION_SEQ = {
    "eq-masklion-idle": ["lidle_%d" % i for i in range(0, 6)],
    "eq-masklion-walk": ["lwalk_%d" % i for i in range(1, 9)],
    "eq-masklion-attack": ["latk_%d" % i for i in range(1, 11)],   # 下标 4 = 张嘴前扑到最前
    "eq-masklion-charge": ["lrun_%d" % i for i in range(1, 9)],
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
    for src, dst in ICONS.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(EQ, dst + ".png"))
    for src, dst in TAG.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(TAGS, dst + ".png"))
    for src, dst in {"gold_beam": "mask-gold-beam", "gold_ground": "mask-gold-ground"}.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(VFX, dst + ".png"))
    for src, dst in {"ow_tile": "ow-tile", "ow_circle": "ow-circle", "ow_pillar": "ow-pillar"}.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(VFX, dst + ".png"))
    for pre, dst, (fw, fh) in [("owA", "ow-maskA", (128, 128)), ("owB", "ow-maskB", (128, 128)), ("owF", "ow-brazier", (48, 96))]:
        out = Image.new("RGBA", (fw * 8, fh), (0, 0, 0, 0))
        for i in range(8):
            im = Image.open(os.path.join(AI, "%s_%d.png" % (pre, i))).convert("RGBA")
            assert im.size == (fw, fh), (pre, i, im.size)
            out.paste(im, (i * fw, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
    for dst, names in LION_SEQ.items():
        out = Image.new("RGBA", (FW * len(names), FW), (0, 0, 0, 0))
        for i, n in enumerate(names):
            im = Image.open(os.path.join(AI, n + ".png")).convert("RGBA")
            assert im.size == (FW, FW), (n, im.size)
            out.paste(im, (i * FW, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(names), "帧")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
