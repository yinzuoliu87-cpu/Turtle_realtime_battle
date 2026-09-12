# -*- coding: utf-8 -*-
"""blender_healdrop.py — 【治疗绿粒子】: 往上飘的圆药滴(4 帧)。

跑法(无窗口):
  blender --background --python tools/blender_healdrop.py -- --out C:/tmp/hd --frames 4 --px 96
  python tools/pixelize_sheet.py C:/tmp/hd --dirs 4 --frames 1 --cell 10 --art-h 10 \
      --palette heal -o assets/sprites/vfx/heal-drop.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-12)
════════════════════════════════════════════════════════════════════════
用户看 019 海葵药膏:「**应该要身上冒绿光和绿粒子，但不要复用**」

**「不要复用」是铁律**(memory [[fb-no-asset-reuse-unless-told]]) ——
所以这一张不是 014 那颗 `life-mote.png`:
  · 014 汲取生命 = **四芒星**(尖锐, 抽取/夺取的读法) · `life` 板正绿
  · 019 治疗     = **圆药滴**(圆润, 药膏/海葵的读法) · `heal` 板海葵绿
形状和色相都拉开, 同屏也分得出是两件事。

★为什么是圆的: 抽取是「夺」—— 尖的; 治疗是「给」—— 圆的。
  形状本身要带含义, 不能两件事共用一个形。

★尺寸按【屏幕像素】反算(今天已经栽过六次):
  实测 1 屏幕像素 = 0.0426 m。一粒要小于光束、又要看得清 ⇒ **10×10 一格**
  ⇒ 世界 10×0.0426 = 0.426 m ≈ 1/5 个龟高, 且 pixel_size 0.0426 = **1 texel : 1 屏幕像素**。

★4 帧是**呼吸**(大小 + 高光位置交替), 不是旋转 —— 像素风不许自由旋转。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

R_BODY = [0.74, 0.62, 0.70, 0.56]     # 4 帧的滴身半径(呼吸)
R_RIM = 0.92                          # 描边圈相对滴身的倍数
HL_R = 0.30                           # 高光半径(相对滴身)
HL_OFF = [(-0.28, 0.30), (-0.22, 0.34), (-0.32, 0.26), (-0.26, 0.32)]   # 高光偏移
NSEG = 20                             # 圆的分段(20 段在 10px 下已经是圆的)


def _srgb(r, g, b):
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


## ★直接取 pixelize_sheet 的 'heal' 板上的色(重索引是最近邻, 随手配色会串档)
C_RIM = _srgb(12, 74, 50)       # heal[4] 深绿描边 —— 有描边才不会被泛光糊成白点
C_BODY = _srgb(36, 178, 112)    # heal[2] 主绿
C_HL = _srgb(168, 255, 214)     # heal[0] 高光(药滴不是加色层, 可以亮)


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
    ## ★色彩管线显式钉死(默认 AgX 会把饱和色压白, 标定过 Standard+look=None 才是恒等)
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


def build(k, m_rim, m_body, m_hl):
    r = R_BODY[k % len(R_BODY)]
    ox, oy = HL_OFF[k % len(HL_OFF)]
    return [
        disc("rim%d" % k, 0.0, 0.0, r, m_rim, 0.00),            # 描边(最大)
        disc("body%d" % k, 0.0, 0.0, r * R_RIM, m_body, 0.01),  # 主色
        disc("hl%d" % k, ox * r, oy * r, r * HL_R, m_hl, 0.02),  # 高光(偏左上)
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
    m_rim = flat("rim", C_RIM)
    m_body = flat("body", C_BODY)
    m_hl = flat("hl", C_HL)
    for k in range(a.frames):
        obs = build(k, m_rim, m_body, m_hl)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob in obs:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_healdrop] 渲出 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
