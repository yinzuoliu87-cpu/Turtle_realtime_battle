"""pack_holy_spear_art.py —— 146 圣枪重做(方案书 docs/plans/20261126c-圣枪重做.md 附录 A)的特效打包

来源(如实):
  · 全部是 PixelLab 特效工作台(vfx_workbench)出的, 不是手画、没有 AI 生图:
    holy-orb      光球(循环 8 帧): 现成部件 magic_orb 改金色 + 自己加的两层(头上四芒十字星 holy_cross 一闪一闪、外圈细光环 holy_halo 呼吸)
    holy-ally     砸中友方(9 帧): 现成部件 level_up 改金色、缩到 0.65 秒 + 自己加的两层(光柱顶端十字星 top_cross / top_glow)
    holy-guard-up / holy-guard-ground  圣枪护盾触发(各 12 帧, 同一时间轴): 全部自己写的图层(*.recipe.json)。
                  用户 11-26「不应该说插在人的位置吗？」⇒ 拆两层: 立着的(一支自己逐行画像素的金色长枪从画面上方加速落下、刃尖插进地面 + 天光 + 火星 + 上飘光点;
                  引擎里开深度测试立在角色身后, 被身体挡住) / 贴地的(镜头正上方俯视渲染: 白金闪光 + 冲击环 + 金色十字; 引擎里平铺在角色脚下)。
    holy-channel  引导(循环 12 帧): 全部自己写的图层: 头顶细金环 + 十字星 + 转动的刻度 + 往环里汇聚的光点 + 脚下淡光环
  · 145 永恒之枪(11-26 重做, 参考 docs/studies/20261126-参考-薇恩E恶魔审判.md), 同样是特效工作台全部自己写的图层:
    eternal-impact 插中(9 帧): 白金闪光 + 四芒大星 + 斜向小星 + 外扩金环 + 外散碎光条
    (11-26 晚用户「145 火圈应该是在携带者身上的，火圈特效不行，仔细以美术师的角度思考」⇒ 原 eternal-burn 作废, 按分层重做:)
    (11-26 深夜用户「相当于携带者周围一个力场一样的东西」⇒ 地面环 / 光波两张作废, 力场改 3D 网格 + 着色器 assets/shaders/eternal_field.gdshader)
    eternal-flame-tongue 火舌(循环 8 帧; 力场版贴在携带者身上往上窜): **Aseprite 后台逐笔画**(tools/assetgen/ase/eternal_flame_tongue.lua: 轮廓工具画剪影 / 平涂 / 亮部 / 高光, 铅笔点火星, Outline 描边), 引擎里沿圈立起一圈
  · 参考研究: docs/studies/20261126-参考-娜美W冲击之潮.md(同一飞行物砸友方 / 敌方靠落点颜色与形状区分)。
  · 砸中敌方用的是旧圣枪自己的两套(spear-holy-burst 十字星爆 / spear-holy-mark 圣痕印记), 同一件装备里换用途, 不算借别人的。
工作台导出的是网格帧表 + JSON(每帧位置 / 锚点); 本脚本按 JSON 拆帧, 把锚点摆到每帧水平正中, 拼成横排帧条。
  · 光球: 锚点(球心)摆到帧正中(引擎里按飞行方向转, 绕中心转)。
  · 其余: 锚点(脚底)摆到水平正中, 锚点下面留的像素数写进 BELOW(引擎里按它往下挪, 让脚底对上地面)。
重跑逐字节相同。

    python tools/assetgen/pack_holy_spear_art.py
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "holy")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")

## 名字 → (锚点居中方式) ; center = 锚点在帧正中, feet = 锚点水平居中、底边留 BELOW
JOBS = {"holy-orb": "center", "holy-ally": "feet", "holy-guard-up": "feet", "holy-guard-ground": "center", "holy-channel": "feet",
        "eternal-impact": "center"}
## 不走工作台 JSON 的: Aseprite 画的火舌(工作流②), 源文件 tools/assetgen/ase/eternal_flame_tongue.aseprite, 导出的横排帧条原样拷过去
COPY = {"eternal-flame-tongue-sheet": "eternal-flame-tongue"}


def frames_of(name):
    meta = json.load(open(os.path.join(SRC, name + ".json"), encoding="utf-8"))
    sheet = Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")
    out = []
    for f in meta["frames"]:
        r = f["frame"]
        im = sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]))
        piv = f.get("pivot", {"x": 0.5, "y": 0.5})
        out.append((im, int(round(piv["x"] * r["w"])), int(round(piv["y"] * r["h"]))))
    return out


def main():
    for name, mode in JOBS.items():
        fr = frames_of(name)
        w, h = fr[0][0].size
        ax, ay = fr[0][1], fr[0][2]
        half_w = max(ax, w - ax)
        if mode == "center":
            half_h = max(ay, h - ay)
            fw, fh, ox, oy = half_w * 2, half_h * 2, half_w - ax, half_h - ay
        else:
            fw, fh, ox, oy = half_w * 2, h, half_w - ax, 0
        strip = Image.new("RGBA", (fw * len(fr), fh), (0, 0, 0, 0))
        for i, (im, _x, _y) in enumerate(fr):
            strip.paste(im, (i * fw + ox, oy), im)
        strip.save(os.path.join(VFX, name + ".png"), optimize=False)
        below = fh - (oy + ay) if mode == "feet" else 0
        print("%-13s %d 帧 · 每帧 %dx%d · 锚点下方 %d 像素" % (name, len(fr), fw, fh, below))
    for src, dst in COPY.items():
        im = Image.open(os.path.join(SRC, src + ".png")).convert("RGBA")
        im.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print("%-13s 拷贝 %dx%d" % (dst, im.width, im.height))


if __name__ == "__main__":
    main()
