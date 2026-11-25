"""pack_dagger_art.py —— 匕首羁绊(2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md)的全部美术打包

来源(如实, 没有一张是手画的):
  · 装备图标 108–116 / 类型标签: PixelLab create_image_pro_flash(风格锚 = 107 武士刀图标 / tag-sword), 原图在 ai_src/dagger/icon*.png / tag*.png
  · 暗影忍者: 待机原画 = create_image_pro_flash(风格锚 = 107 武士刀小将待机原画) → edit_image_pro_flash 去掉脚下的紫烟(ninja_0.png);
    关键姿势 nkey_wind / nkey_slash / nkey_stab / nkey_throw = edit_image_pro_flash 从 ninja_0 改出来(写明严格侧面朝左);
    关键姿势之间 = animate_image 首尾钉住两张关键姿势生成(序号 0 = 输入原画, 不取); 待机 / 走路 = animate_image 首尾都钉 ninja_0
  · 特效: PixelLab 特效工作台(vfx_workbench)的部件改配色后导出的网格表 + 逐帧坐标 json, 在 ai_src/dagger_vfx/
  · 苦无飞行物: 从 110 图标(三把苦无)裁出中间那一把的刀身 + 握柄
本脚本只做裁切 / 拼接 / 拷贝, 重跑逐字节相同。

    python tools/assetgen/pack_dagger_art.py
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AI = os.path.join(ROOT, "tools", "assetgen", "ai_src", "dagger")
AIV = os.path.join(ROOT, "tools", "assetgen", "ai_src", "dagger_vfx")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
EQ = os.path.join(ROOT, "assets", "sprites", "equip")
TAGS = os.path.join(ROOT, "assets", "sprites", "tags")

ICONS = {"icon%d" % i: "p2eq_%d" % i for i in range(108, 117)}
TAG = {"tagdagger": "tag-dagger", "tagritual2": "tag-ritual"}

## 特效表(源名 = 产出名); 一次性的去掉末尾全透明帧, 循环的原样保留
VFX_SHEETS = ["dagger-fang-bite", "dagger-ninja-smoke", "dagger-ninja-strike", "dagger-assassin-strike", "dagger-assassin-mark",
              "dagger-ritual-exec", "dagger-ritual-mark", "dagger-kris-rush", "dagger-fold-cut", "dagger-knife-hit",
              "dagger-obs-pull", "dagger-shade-cut", "dagger-shuriken-spin", "dagger-kunai-hit", "dagger-kunai-heal", "dagger-shuriken-hit"]
LOOPS = {"dagger-kris-rush", "dagger-shuriken-spin"}

## 暗影忍者动作(序号 0 = animate_image 的输入原画; 段与段首尾相接处只取一次)
##   普攻(横斩): 站 → 蓄力(刀收到肩后) → 横斩出手(刀从肩后经胸前扫到正前方, 平指敌人 = 命中帧) → 收势回站姿
##   影袭背刺: 现身后跃起举双刀 → 往下插(命中帧) → 拔刀回站姿
##   掷手里剑: 手往后引 → 甩出(出手帧) → 收手
NINJA_SEQ = {
    "eq-ninja-idle": ["nidle_%d" % i for i in range(0, 6)],                         # 6 帧循环(第 6 张 = 原画, 与第 0 张重复不取)
    "eq-ninja-walk": ["nwalk_%d" % i for i in range(1, 9)],                         # 8 帧循环
    "eq-ninja-attack": ["ninja_0", "nwind_1", "nwind_2", "nwind_3", "nkey_wind", "nslash_1", "nslash_2", "nslash_3", "nkey_slash",
                        "nrec_1", "nrec_2", "nrec_3"],
    "eq-ninja-stab": ["nstab_1", "nstab_2", "nstab_3", "nkey_stab", "nkey_stab", "nstabrec_1", "nstabrec_2", "nstabrec_3"],
    "eq-ninja-throw": ["nthrow_1", "nthrow_2", "nthrow_3", "nkey_throw", "nthrowrec_1", "nthrowrec_2", "nthrowrec_3"],
}
## 命中 / 出手帧下标(从 0 数; 演出层与 AttackHits 照抄这几个数)
NINJA_HIT = {"eq-ninja-attack": 8, "eq-ninja-stab": 3, "eq-ninja-throw": 3}


def _strip(frames):
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def main() -> None:
    out = []
    for src, dst in ICONS.items():
        Image.open(os.path.join(AI, src + ".png")).convert("RGBA").save(os.path.join(EQ, dst + ".png"), optimize=False)
    for src, dst in TAG.items():
        Image.open(os.path.join(AI, src + ".png")).convert("RGBA").save(os.path.join(TAGS, dst + ".png"), optimize=False)
    out.append("图标 %d 张 + 标签 %d 张" % (len(ICONS), len(TAG)))
    for name in VFX_SHEETS:
        sheet = Image.open(os.path.join(AIV, name + ".png")).convert("RGBA")
        meta = json.load(open(os.path.join(AIV, name + ".json"), encoding="utf-8"))
        frames = []
        for f in meta["frames"]:
            r = f["frame"]
            frames.append(sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
        if name not in LOOPS:
            while len(frames) > 1 and frames[-1].getbbox() is None:
                frames.pop()
        _strip(frames).save(os.path.join(VFX, name + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (name, frames[0].width, frames[0].height, len(frames)))
    ## 苦无飞行物: 110 图标中间那一把(x 24..39, 刀尖到握柄 y 0..39; 再往下是三把的环叠在一起 + 两侧那两把的刀柄边, 不取)
    k = Image.open(os.path.join(AI, "icon110.png")).convert("RGBA").crop((24, 0, 40, 40))
    k.save(os.path.join(VFX, "dagger-kunai.png"), optimize=False)
    out.append("dagger-kunai %dx%d" % k.size)
    ## 暗影忍者: 所有帧同一个下移量(按待机原画最低一行贴到帧底), 换表不跳
    base = Image.open(os.path.join(AI, "ninja_0.png")).convert("RGBA")
    dy = base.height - base.getbbox()[3]
    for dst, names in NINJA_SEQ.items():
        frames = []
        for nm in names:
            f = Image.open(os.path.join(AI, nm + ".png")).convert("RGBA")
            g = Image.new("RGBA", f.size, (0, 0, 0, 0))
            g.paste(f, (0, dy))
            frames.append(g)
        _strip(frames).save(os.path.join(VFX, dst + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (dst, frames[0].width, frames[0].height, len(frames)))
    print("\n".join(out))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
