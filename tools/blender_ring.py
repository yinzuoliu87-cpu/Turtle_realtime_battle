# -*- coding: utf-8 -*-
"""blender_ring.py — 在 Blender 里造【冲击环】, 逐帧烤出扩散动画。

跑法(无窗口):
  blender --background --python tools/blender_ring.py -- --out C:/tmp/ring --frames 8

★★为什么这个必须逐帧烤, 不能靠代码缩放(2026-09-06 审 003 锋利鲨齿时发现)
  改造前 `_splash_ring_bold` 是:
      r.texture = VfxTex._make_ring_texture(col)        # 程序生成的软圆环
      tw.tween_property(r, "pixel_size", target_ps, dur) # 【连续放大】
  两个问题:
    ① 贴图是程序画的软辉光, 与项目的硬边像素风不是一路(用户:「最好不要程序弄吧」)
    ② **连续缩放像素贴图 = 非整数倍缩放 = 像素网格被打烂**, 这是像素风的头号禁忌
       (与 CLAUDE.md 记的"像素风只能整数倍缩放"同一条)
  ⇒ 正确做法: **把扩散烤成 N 帧**, 画布尺寸恒定, 游戏里 pixel_size 固定不动、只切帧。

★为什么用 Blender 而不是生成器: 环要【几何精确】——
  它的外径就是伤害判定半径(SHARKTOOTH_SPLASH_R), 玩家靠它判断"谁会被溅到"。
  生成器画不出精确的圆, 更画不出逐帧半径严格递增的一组。代码画的才对。
  (对比: 扁弧那种"要看着像光"的形状程序造不出来, 见 tools/blender_slash.py 头注。)


★★几何对账【只能算, 不能量像素】(2026-09-06 我在这里栽过一次)
  旧贴图 `_make_ring_texture` N=96、环带中心 d=0.82 半宽 0.18 ⇒ 外缘正好在 d=1.0(填满 96px),
  旧公式 ps=(radius*2*WS)/96 ⇒ 世界直径 = 2·radius·WS = 2×200×0.024 = 9.6 m ✓ **旧公式是对的**。
  新贴图 64px 格内环外径 31×2=62px ⇒ 分母换成 62, 世界直径不变。
  ★我先拿实拍量"环外径"得出「大了整整一倍」并改掉了那个 *2.0 —— **错的**。
    那个量法用一个金色掩膜框住整片战场, 把伤害飘字 / 命中火花 / 多个重叠的环全算进去了,
    量的根本不是单个环(证据: 改前改后测出来都是 535px, 一模一样)。
  ⇒ 这类"视觉尺寸 == 判定尺寸"的对账, 用贴图几何 + 公式算; 像素量法在多物体同框时不可信。

★渲的是【俯视正交】: 游戏里这张图是 `axis = AXIS_Y` 贴地放的,
  透视由引擎的战斗相机(俯角 ≈51°)自己处理 —— 所以这里必须正上方直视, 不能自带角度。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402


## 环的形状(相对画布半径 1.0)
R_START = 0.30       # 首帧外径
R_END = 0.96         # 末帧外径(留一点边, 别贴画布边缘被裁)
BAND_START = 0.22    # 首帧环带厚度(相对外径)
BAND_END = 0.055     # 末帧变薄(冲击波扩散时会变细)
SEG = 128            # 圆周分段(够密才不会看出多边形)

## 径向配色: 0 = 外缘(前锋) → 1 = 内缘(尾)。
## ★★渲成【灰阶】不是金色 —— `_splash_ring_bold` 有 16 个调用点, 各处传的颜色不同
##   (蓝/红/绿/橙/青)。灰阶 + `modulate = col` 才能让 16 处都用对自己的色。
##   亮度阶梯仍照 LoL 参考实测的那组(237/210/189/140/95), 只是去掉色相 ——
##   这样上色之后内部的明暗层级与 gold 板是一致的。
RAMP = [
    (0.00, (237, 237, 237)),
    (0.16, (210, 210, 210)),
    (0.42, (189, 189, 189)),
    (0.70, (140, 140, 140)),
    (1.00, (95, 95, 95)),
]


def srgb_to_linear(c):
    """★Blender 的颜色输入吃【线性】色, 我们的调色板是 sRGB 数值。
    直接喂会整体提亮一整档(见 tools/blender_slash.py 头注的实测)。"""
    v = c / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_ring(name, r_out, band):
    """造一个环带(annulus)。UV 的 v 跨环带: 0 = 外缘, 1 = 内缘。"""
    r_in = max(0.02, r_out - band)
    verts, faces, uvs = [], [], []
    for i in range(SEG + 1):
        a = math.tau * i / float(SEG)
        ca, sa = math.cos(a), math.sin(a)
        verts.append((ca * r_out, sa * r_out, 0.0))
        verts.append((ca * r_in, sa * r_in, 0.0))
        uvs.append((i / float(SEG), 0.0))
        uvs.append((i / float(SEG), 1.0))
    for i in range(SEG):
        a0, b0, a1, b1 = i * 2, i * 2 + 1, (i + 1) * 2, (i + 1) * 2 + 1
        faces.append((a0, a1, b1, b0))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def build_material():
    mat = bpy.data.materials.new("ring_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    emis = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    ramp.color_ramp.interpolation = 'CONSTANT'   # 硬边色带 = 像素画要的分层
    while len(ramp.color_ramp.elements) > 1:
        ramp.color_ramp.elements.remove(ramp.color_ramp.elements[-1])
    ramp.color_ramp.elements[0].position = RAMP[0][0]
    ramp.color_ramp.elements[0].color = (*[srgb_to_linear(v) for v in RAMP[0][1]], 1.0)
    for pos, col in RAMP[1:]:
        e = ramp.color_ramp.elements.new(pos)
        e.color = (*[srgb_to_linear(v) for v in col], 1.0)
    nt.links.new(tex.outputs["UV"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Y"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emis.inputs["Color"])
    emis.inputs["Strength"].default_value = 1.0
    nt.links.new(emis.outputs["Emission"], out.inputs["Surface"])
    return mat


def setup_render(px):
    sc = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in ids else 'BLENDER_EEVEE'
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'   # 不要色调映射
    cd = bpy.data.cameras.new("cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = 2.0            # 画布覆盖 -1..1, 与形状参数同一口径
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)   # ★正上方直视: 透视交给游戏相机
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--px", type=int, default=512)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    mat = build_material()
    for f in range(a.frames):
        t = f / float(max(1, a.frames - 1))
        ## 扩散: 外径线性推进, 环带同时变薄(冲击波的物理特征)
        r_out = R_START + (R_END - R_START) * t
        band = (BAND_START + (BAND_END - BAND_START) * t) * r_out
        ob = build_ring("ring_%d" % f, r_out, band)
        ob.data.materials.append(mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d0_f%d.png" % f)
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_ring] 渲出 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
