# -*- coding: utf-8 -*-
"""blender_bindbead.py — 021 守护贝母【绑定绳】上的圆珠(4 帧呼吸)。

跑法(无窗口):
  blender --background --python tools/blender_bindbead.py -- --out C:/tmp/bb --frames 4 --px 96
  python tools/pixelize_sheet.py C:/tmp/bb --dirs 4 --frames 1 --cell 4 --art-h 4 \
      --palette pearl -o assets/sprites/vfx/bind-bead.png   # ★--cell 20 见下
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-12)
════════════════════════════════════════════════════════════════════════
用户看 021 的窗口:「**这个线感觉生硬啊**」

他是对的, 而且根因在代码里一眼可见 —— 原来的 `_update_barnacle_line` 是:
  · `PRIMITIVE_LINES` 画 **5 条平行的 1 像素裸 GPU 线**(无贴图)
  · **完全笔直**, 两端钉死在固定高度 2.05 m
  · 除了 alpha 脉动之外**一帧都不动**
⇒ 那是一根绷直的杆, 不是「绑定」。

★这与 v0.19.361 修过的 `_bolt_line` 是**同一个毛病**(1px 裸线), 021 这一处当时没被扫到。
  (memory [[fb-fix-the-shared-primitive-not-one-instance]] 的镜像: 修原语时要把同形状的
   其它实现一起找出来 —— `_update_barnacle_line` 是它自己的一份手抄实现, 不走 bolt_line。)

★★尺寸/结构**全部来自 LoL 卡尔玛【灵魂链接】的逐帧实测**, 不是我挑的:
    直不直 : 峰值行离首尾直线最大偏离 6.6px / 132px = **5.0%** ⇒ 直的
    粗细   : 半高全宽 11px(芯) / 四分之一高全宽 19px(含晕) ⇒ 长:粗 = 7.4:1
    横截面 : 白热芯(亮度 186) → 主体(173) → 外晕(105~130)
    相对角色: 角色高 ~40px ⇒ **线粗 ≈ 角色高的 47%**
  我第一版是 8px 的小珠子 + 我自己加的垂坠与摆动 ——
  **粗细只有龟高的 2%(差 20 倍), 而垂坠和摆动参考里根本没有**。
  用户:「不要用什么规则图案敷衍我」「这个线感觉生硬啊」—— 生硬不是因为它直,
  是因为它**细、没厚度、没层次**。

★为什么片是【圆】的, 不是顺着绳向的短杆:
  像素风三条硬约束之一是**不许自由旋转**(battle_ballistics.gd:675)。
  绳的角度每帧都在变, 短杆要跟着转 = 自由旋转 = 像素网格被打烂。
  **圆是旋转不变的** —— 这是形状被约束逼出来的, 不是随手挑的。

★和 019 的圆药滴怎么分开(「不要复用」是铁律 [[fb-no-asset-reuse-unless-told]]):
  · 019 药滴 = 10px · `heal` 板海葵绿 · **孤立几粒往上飘**
  · 021 绳片 = 20px · `pearl` 板珠白绿 · **密排成一条粗光带、沿带流动**
  尺寸/色相/运动三条都拉开。

★尺寸按【屏幕像素】反算: 实测 1 屏幕像素 = 0.0426 m ⇒ 20×20 一格 = 0.852 m
  (龟高 ≈45 屏幕像素 ⇒ 线粗占 44%, 对上实测的 47%), pixel_size 0.0426 = **1 texel : 1 屏幕像素**。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

## ★★★量错过一次基准, 记在这里: 我第一次量的是 **2013-03-29** 上传的英雄聚焦
##   (用户:「拿10年前的干嘛啊，今年都2026了」)。那一版的线是**粗光束**:
##   四分高全宽 19px / 角色高 40px ⇒ 粗细占角色高 **47%**。
## ★现版(2026-07-25 · S16 补丁 · 08N5yDWo930 f13 t=33.48s)扣掉背景后重量:
##     背景亮度 ≈73, 峰值 146(正好 2 倍背景)
##     半高(背景+一半) 以上只有 **3 px**; 四分高以上 **4 px**
##     角色高 ≈45px ⇒ 粗细只占角色高 **约 8%** —— Riot 这些年把它**改细了 5 倍**
##     结构: **近白的芯 1~2px + 上下各一道蓝边**, 直的
## ⇒ 三层半径按 4px 总径反推: 芯 2px、主体 3px、外晕 4px
## ★★又量了一轮才收敛(扣背景、同一把尺子量两边):
##   6px 一格那版 ⇒ 我们半高宽 8px, 参考 4px —— **还粗一倍**(泛光会把实体再撑开一圈)。
##   而且峰色我们是饱和青绿 (35,181,182)、参考是淡蓝灰 (103,138,157) ⇒ **芯不够大**。
## ⇒ 格收到 4px, 且把芯放大到占一半以上, 让中心那一行读成近白。
R_GLOW = 1.00                          # 外边 = 总径 4px
R_BODY = 0.78                          # 主体
## ★★4px 一格已经到**量化极限**: 芯半径 0.52 ⇒ 半高宽 3px, 0.62 ⇒ 直接跳到 8px。
##   中间没有档可选(一个纹素就是一档), 再加泛光放大 ⇒ ±1px 就是像素风能做到的精度。
##   参考是 4px, 取更接近的 0.52(3px), 不再磨。
R_CORE = 0.52                          # 芯半径
## 4 帧呼吸只动 ±6% —— 参考里这条线的粗细是稳的, 不是一闪一闪的
BREATHE = [1.00, 0.94, 0.99, 0.95]
NSEG = 24


def _srgb(r, g, b):
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


## ★直接取 pixelize_sheet 的 'pearl' 板上的色(重索引是最近邻, 随手配色会串档)
## 三层的**亮度关系**照实测搬(186 : 173 : 118 ≈ 1 : 0.93 : 0.63), 色相保持 021 的绿
## (学结构不学颜色 —— 021 的身份是绿色绑定线, 不改成 LoL 的青)。
## 现版实测: 芯近白、边是饱和色, 峰值只有背景的 2 倍(不是刺眼的过曝)。
## 色相保持 021 的绿(学结构不学颜色)。
## ★★第三轮收数(扣背景、同一把尺子): 粗细对上之后还剩两条 ——
##   我们 峰/背 3.40 vs 参考 2.01(太亮)、四分宽 8 vs 5(外晕太散)。
##   泛光会把亮边再撑开一圈 ⇒ **把整条阶梯往下压一档**, 让泛光之后落回参考那个比值。
C_GLOW = _srgb(24, 62, 52)       # pearl[5] 亮度  53  外边(压暗一档 ⇒ 外晕收窄)
C_BODY = _srgb(86, 166, 132)     # pearl[3] 亮度 144  主体(压暗一档)
C_CORE = _srgb(198, 238, 212)    # pearl[1] 亮度 226  芯(不再用最白的 250 ⇒ 峰/背降下来)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for it in list(blk):
            blk.remove(it)


def setup_render(px):
    sc = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    ## ★色彩管线显式钉死(默认 AgX 会把饱和色压白; 标定过 Standard+look=None 才是恒等)
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def flat(name, rgba):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Color"].default_value = rgba
    emi.inputs["Strength"].default_value = 1.0
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    return mat


def disc(name, cx, cy, r, mat, z):
    pts = [(cx + r * math.cos(math.tau * i / NSEG), cy + r * math.sin(math.tau * i / NSEG))
           for i in range(NSEG)]
    me = bpy.data.meshes.new(name)
    me.from_pydata([[p[0], p[1], z] for p in pts], [], [tuple(range(NSEG))])
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def build(k, m_glow, m_body, m_core):
    b = BREATHE[k % len(BREATHE)]
    return [
        disc("glow%d" % k, 0.0, 0.0, R_GLOW * b, m_glow, 0.00),
        disc("body%d" % k, 0.0, 0.0, R_BODY * b, m_body, 0.01),
        disc("core%d" % k, 0.0, 0.0, R_CORE * b, m_core, 0.02),
    ]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=96)
    ap.add_argument("--frames", type=int, default=4)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    m_glow = flat("glow", C_GLOW)
    m_body = flat("body", C_BODY)
    m_core = flat("core", C_CORE)
    for k in range(a.frames):
        obs = build(k, m_glow, m_body, m_core)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob in obs:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_bindbead] 渲出 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
