# -*- coding: utf-8 -*-
"""变脸龟界面待机帧表(2026-11-09 用户「变脸龟没有待机动画吗」)。确定性生成, 重跑逐字节相同。

28 只龟里只有变脸龟在 pets.json 没登记逐帧待机图(sprite{}), 选龟页 / 图鉴 / 统领卡 / 冠军页这些界面只能退回
「整张轻轻缩放呼吸」, 看上去像不动。战斗里它其实有两套 8 帧待机(TwoHeadArt: pets/animations/two_head/<形态>_idle.png,
128×128 方帧, 立绘 80×80 贴在 (24,48))。这里把同一套帧裁成立绘那一格, 给界面用(scripts/gamedata/pet_ui_idle.gd):

  assets/sprites/pets/animations/two_head/ui_ranged_idle.png   远程(术士)8 帧, 每帧 80×81
  assets/sprites/pets/animations/two_head/ui_melee_idle.png    近战(战士)8 帧, 每帧 80×81

裁框 = (24, 47) 起 80×81: 立绘那一格再往上多一行(近战待机举锤时最高到第 47 行, 远程最高第 49 行),
⇒ 两套 8 帧的不透明像素一个都不丢(脚本里断言), 第 0 帧的不透明部分逐像素等于界面原来那张静态立绘(断言)。
★不进 pets.json: 战斗出生立绘 / 换形态 / 门禁 verify_two_head_form_art 都钉在 pets/two_head.png 这张静态图上。

  python tools/assetgen/build_two_head_ui_idle.py
"""
import os
import sys

from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "sprites", "pets", "animations", "two_head")
PETS = os.path.join(ROOT, "assets", "sprites", "pets")
FRAME = 128
BOX = (24, 47, 104, 128)   # 裁框(左, 上, 右, 下) ⇒ 80×81
FORMS = {"ranged": "two_head.png", "melee": "two_head_melee.png"}


def build(form: str) -> Image.Image:
    sheet = Image.open(os.path.join(SRC, "%s_idle.png" % form)).convert("RGBA")
    n = sheet.width // FRAME
    assert n == 8, (form, n)
    bw, bh = BOX[2] - BOX[0], BOX[3] - BOX[1]
    out = Image.new("RGBA", (bw * n, bh), (0, 0, 0, 0))
    for i in range(n):
        fr = sheet.crop((i * FRAME, 0, i * FRAME + FRAME, FRAME))
        bb = fr.getbbox()
        assert bb is not None and bb[0] >= BOX[0] and bb[1] >= BOX[1] and bb[2] <= BOX[2] and bb[3] <= BOX[3], (form, i, bb)
        out.paste(fr.crop(BOX), (i * bw, 0))
    ## 第 0 帧 = 静态立绘(80×80 贴在格子里第 48 行起 ⇒ 裁出来的第 1 行起)
    still = Image.open(os.path.join(PETS, FORMS[form])).convert("RGBA")
    f0 = out.crop((0, 1, bw, 1 + still.height))
    assert ImageChops.difference(f0, still).getbbox() is None, (form, "第 0 帧不等于静态立绘")
    return out


def main() -> int:
    for form in FORMS:
        p = os.path.join(SRC, "ui_%s_idle.png" % form)
        build(form).save(p, optimize=False)
        print("wrote", os.path.relpath(p, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
