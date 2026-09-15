# -*- coding: utf-8 -*-
"""blender_bladder.py — 064 溺者的浮囊【持有态】: 套在龟腰上的幽灵浮囊, 4 档瘪度 × 前后两半。

跑法(无窗口):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_bladder.py -- --out C:/tmp/bladder --px 480
  python tools/pixelize_sheet.py C:/tmp/bladder --dirs 2 --frames 4 --cell 48 --art-h 48 --palette drown \
      -o assets/sprites/vfx/eq064-bladder.png

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-15)
════════════════════════════════════════════════════════════════════════
用户看 064 验收视频:「不太行，得思考重做，**思考怎么贴合装备效果**」
                  「特效有盾的为什么角色动了盾没动」
旧演出是 `spirit_eq_vfx.float_bladder` 的一颗**程序加色球** —— 名字叫「浮囊」, 画面是「身上一个蓝球」,
文案里的「残血套上 / 20 秒衰减 / 破了炸开」画面上一样都读不出。

════════════════════════════════════════════════════════════════════════
 ★这张图说的事: 「幽灵护盾在一格格瘪下去」
════════════════════════════════════════════════════════════════════════
- 形态 = **套在腰上的救生浮囊**(溺者的浮囊), 半透幽灵青 + 褪色珊瑚条纹(救生圈的识别特征)。
- 行 f0~f3 = 余额 满 / 75% / 50% / 25%: 管径变细 + 截面压扁 + 出褶皱。**按余额选帧, 不缩放像素图**
  (`tools/vfx_discipline_audit.py` A 条: 硬边像素图不许连续缩放)。
- 列 d0 = 后半圈(远离镜头, 画面上半), d1 = 前半圈(靠近镜头, 画面下半)。
  ★为什么拆两半: 龟立绘 shader 是 `depth_prepass_alpha`(写深度) ⇒ 后半圈放在龟身后会被身体挡住,
    前半圈放在身前压在肚子上 —— 这样才读得出「套在身上」, 一整张贴在身前只会读成「挡在前面的一个圈」。

★尺子(实测 basic 立绘): 身宽 40 屏幕像素 / 身高 39 屏幕像素(zoom 1.0)。
  cell 48 ⇒ 浮囊外径约 46 像素, 比身体宽一圈才读得出「套着」。1 texel = 1.775 码 ⇒ 48 × 1.775 = 85.2 码。
★俯仰: 画面上椭圆纵横比取 0.40(物体绕 X 轴 −66.4°)。战斗相机俯角约 51°, 但立绘是直立 billboard,
  套在直立角色身上的圈按「卡通泳圈」读法压扁才自然; 0.78(真实地面透视)会遮住半个身体。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

RING_R = 0.79             # 主半径(占半幅宽)
TUBE_R = 0.146            # 管半径(满气) ⇒ 管径约 7 屏幕像素
OUTLINE_T = 0.040         # 描边厚度(约 1 屏幕像素)
TILT_DEG = -66.4          # cos(66.4°) = 0.40 ⇒ 椭圆纵横比 0.40
STRIPES = 8               # 救生圈条纹段数(4 青 4 珊瑚)

## 四档瘪度: (管径系数, 截面纵向压扁, 褶皱振幅)
DEFLATE = [
    (1.00, 1.00, 0.00),   # f0 满
    (0.84, 0.86, 0.05),   # f1 75%
    (0.68, 0.72, 0.10),   # f2 50%
    (0.52, 0.58, 0.16),   # f3 25%
]


def _srgb(r, g, b, a=1.0):
    """sRGB 0-255 → 线性 0-1(Blender 颜色吃线性)。"""
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), a)


GHOST_TEAL = _srgb(150, 214, 206)
FADED_CORAL = _srgb(214, 128, 118)
OUTLINE = _srgb(24, 44, 52)


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
    sc.view_settings.view_transform = "Standard"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    ## 左上方来光(与项目其它像素素材同一受光方向)
    ld = bpy.data.lights.new("sun", type="SUN")
    ld.energy = 3.2
    sun = bpy.data.objects.new("sun", ld)
    sun.rotation_euler = (math.radians(38.0), math.radians(-32.0), math.radians(20.0))
    bpy.context.collection.objects.link(sun)
    world = bpy.data.worlds.new("w") if not bpy.context.scene.world else bpy.context.scene.world
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs["Color"].default_value = (0.35, 0.40, 0.42, 1.0)
        bg.inputs["Strength"].default_value = 0.55


def lit_material(name, rgba, glow):
    """受光材质 + 一点自发光(幽灵感)。明暗交给光照, 再由 pixelize 锁到调色板。"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = 0.55
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = rgba
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = glow
    return mat


def outline_material():
    """反壳描边: 只画朝里的面(背面剔除打开)⇒ 从镜头看是一圈轮廓。"""
    mat = bpy.data.materials.new("outline")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Color"].default_value = OUTLINE
    emi.inputs["Strength"].default_value = 1.0
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def torus_mesh(name, tube_k, squash, wrinkle, extra, keep_back):
    """建一圈管子: 主半径 RING_R, 管径 TUBE_R×tube_k(+extra 给描边), 截面纵向压扁 squash, 沿主圈的褶皱 wrinkle。
    keep_back=True 只留局部 +Y 那半(倾斜后远离镜头 = 画面上半)。"""
    maj_n, min_n = 64, 16
    r = TUBE_R * tube_k + extra
    verts = []
    for i in range(maj_n):
        u = 2.0 * math.pi * i / maj_n
        cu, su = math.cos(u), math.sin(u)
        wr = 1.0 - wrinkle * (0.5 + 0.5 * math.sin(7.0 * u + 0.6))
        for j in range(min_n):
            v = 2.0 * math.pi * j / min_n
            rr = r * wr
            ## 截面: 径向分量 cos(v), 纵向分量 sin(v) × squash; 瘪下去时底面更平(下半截面再压一半)
            zc = math.sin(v) * rr * squash
            if zc < 0.0:
                zc *= (1.0 - 0.5 * wrinkle / 0.16) if wrinkle > 0.0 else 1.0
            d = RING_R + math.cos(v) * rr
            verts.append((cu * d, su * d, zc))
    faces = []
    mats = []
    for i in range(maj_n):
        for j in range(min_n):
            a = i * min_n + j
            b = ((i + 1) % maj_n) * min_n + j
            c = ((i + 1) % maj_n) * min_n + (j + 1) % min_n
            dd = i * min_n + (j + 1) % min_n
            um = 2.0 * math.pi * (i + 0.5) / maj_n
            if keep_back is not None:
                back = math.sin(um) > 0.0
                if back != keep_back:
                    continue
            faces.append((a, b, c, dd))
            mats.append(int(um / (2.0 * math.pi) * STRIPES) % 2)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    for k, poly in enumerate(me.polygons):
        poly.material_index = mats[k]
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(TILT_DEG), 0.0, 0.0)
    return ob


def build(level, keep_back, m_teal, m_coral, m_line):
    tube_k, squash, wrinkle = DEFLATE[level]
    body = torus_mesh("body", tube_k, squash, wrinkle, 0.0, keep_back)
    body.data.materials.append(m_teal)
    body.data.materials.append(m_coral)
    hull = torus_mesh("hull", tube_k, squash, wrinkle, OUTLINE_T, keep_back)
    hull.data.materials.append(m_line)
    hull.data.materials.append(m_line)
    ## 反壳: 翻法线, 背面剔除 ⇒ 只剩轮廓
    for poly in hull.data.polygons:
        poly.flip()
    hull.data.update()
    return [body, hull]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=480)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    n = 0
    for d, keep_back in enumerate([True, False]):
        for f in range(len(DEFLATE)):
            clear_scene()
            setup_render(a.px)
            m_teal = lit_material("teal", GHOST_TEAL, 0.35)
            m_coral = lit_material("coral", FADED_CORAL, 0.25)
            m_line = outline_material()
            build(f, keep_back, m_teal, m_coral, m_line)
            bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f%d.png" % (d, f))
            bpy.ops.render.render(write_still=True)
            n += 1
    print("[blender_bladder] 渲出 %d 张(2 半 × %d 档) → %s" % (n, len(DEFLATE), a.out))


if __name__ == "__main__":
    main()
