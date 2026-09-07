# -*- coding: utf-8 -*-
"""blender_groundslit.py — 地裂缝(剑要从这里升起来), 逐帧烤出"裂开"的过程。

跑法(无窗口):
  blender --background --python tools/blender_groundslit.py -- --out C:/tmp/slit --frames 6

★★由来(2026-09-07 用户):「我不知道，但你不能凭空没有逻辑出现」
  006 千刃风暴改造前后都有同一个毛病: **7 把剑是从空气里淡出来的, 没有来处**。
  我第一版把蓄力的软球换成了一颗八向星 —— 用户直接指出这没解决问题:
  星和球一样都是"通用闪光", 既不说明技能要干什么, 自己也照样是凭空出现的。
  ⇒ 正确的改法是给它一条【因果链】而不是换个更漂亮的预兆:
       地面裂开 7 道口子 → 剑从口子里升起来 → 剑阵向前推
     每一步都有因: 口子是剑要出来的地方, 剑是从口子长出来的。
     而且口子的位置和数量**就是**剑阵的位置和数量 —— 预兆自带信息量。

★★第一版(梭形 + 对称亮边)实拍读作【飞碟】不是【地缝】。三个都是几何错, 不是参数错:
  ① **UV 两边都是 0、中线是 1** ⇒ 亮色绕了一整圈 = 一个闭合的白轮廓。
     **闭合的亮轮廓永远读作"一个物体"**, 不可能读作"地面上的一道口子"。
     ⇒ 改成 v: 下缘 0.0 / 中线 0.5 / 上缘 1.0, 亮色**只给上缘**(被顶起来的土棱受光面),
       下缘留暗 —— 有受光面有背光面才是"地面被撑开", 不是"地上摆了个东西"。
  ② **形状是数学上光滑的梭形**(sin 包络), 而裂缝的特征恰恰是**不光滑**:
     宽度忽宽忽窄(掐点)、中线会歪、末端会分叉。光滑 = 人造物。
     ⇒ 中线与半宽都叠低频噪声(2/4/5 周期 —— 缩到 48px 后每个起伏还有 5~10 像素,
       活得下来), 另加 3 条分叉短缝。
  ③ 缝心用了 steel 板最暗的 (38,46,64) —— 那是**中灰蓝**, 在暗地面上根本不像"看进地下"。
     ⇒ 新开 crack 板, 最暗两档压到亮度 21 / 9(见 tools/pixelize_sheet.py)。

★为什么用 Blender: 缝要【贴地】且【精确对齐剑的出生点】, 是几何活。
  和 003 的冲击环同族(见 tools/blender_ring.py 头注) —— 生成器给不了精确对齐。

★渲【俯视正交】: 游戏里这张图 `axis = AXIS_Y` 贴地放, 透视交给战斗相机(俯角 ≈51°)。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402


## 裂缝形状(相对画布 1.0 = 整个画幅)
SLIT_LEN = 0.86      # 末帧长度
SLIT_W = 0.18        # 末帧最宽处
## ★★宽度改过三轮, 教训是【裂缝是一条线, 不是一个面】:
##   0.13 → 0.26 → 0.40 我一路加宽, 理由是"贴地会被相机压掉 37%, 得留够亮棱"。
##   0.40 缩到 48px 是 42×24 像素 —— **长宽比只有 1.75:1**, 那不是缝, 那是个块。
##   实拍(真实地图)七个一起读成**七只黑蝙蝠**: 黑色实心块 + 上缘一道白 = 一只鸟的剪影。
##   ⇒ 0.18 ⇒ 42×9 像素, 长宽比 4.7:1; 暗地面吃掉下半的暗色, 剩上缘 2~3 像素亮棱,
##     上屏就是一条会分叉的亮裂线 —— 这才是"地裂"该有的样子。
##   ★通用: 暗地面上"实心暗块"永远读作物体; 缝只能靠**受光的边**读出来。
SEG = 96

## 径向配色: v=0 下缘(背光·暗) → v≈0.5 缝心(最黑) → v=1.0 上缘(受光亮棱)
## ★★**只有上缘亮**。第一版两边都亮 = 闭合白轮廓 = 飞碟(见头注 ①)。
## ★只剩 9 像素可分, 所以配比按【像素数】定而不是按好看定:
##   下缘+缝心约 5~6 像素(暗地面上等于隐形, 只贡献一点厚度), 上缘 3 像素给亮棱。
RAMP = [
    (0.00, ( 24,  28,  38)),   # 亮度  28  下缘(背光)
    (0.22, (  8,   9,  13)),   # 亮度   9  缝心(看进地下)
    (0.58, ( 60,  68,  86)),   # 亮度  67  上缘根部
    (0.72, (150, 162, 186)),   # 亮度 162  上缘过渡
    (0.86, (232, 238, 248)),   # 亮度 237  受光亮棱(最上 2 像素)
]

## 分叉短缝: (沿主缝的位置 t, 角度°, 相对主缝的长度, 相对主缝的宽度, 噪声相位)
## ★分叉是"裂缝"和"椭圆"最省事的区分点 —— 一条闭合光滑的边界永远像个物体。
## ★第一版三条分叉里有一条 118°(近乎垂直)、且长度给到 0.26 —— 实拍在真实地图上
##   七个缝一起读成了**七只黑蝙蝠**(近垂直的那条当翅膀, 主缝当身子)。
##   ⇒ 分叉只保留两条斜的、缩短到 0.20/0.17: 够打破"闭合椭圆", 又不至于长出翅膀。
## ★缝变细之后分叉可以放长: 细线上的分叉才看得出是分叉(块上的分叉只是让块变胖)。
BRANCHES = [
    (0.34,  26.0, 0.30, 0.62, 2.1),
    (0.66, -31.0, 0.25, 0.55, 4.7),
]


def srgb_to_linear(c):
    """★Blender 颜色输入吃线性色, 调色板是 sRGB ⇒ 直接喂会整体提亮一整档
    (实测见 tools/blender_slash.py 头注)。"""
    v = c / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _noise(t, k, ph):
    """低频确定性噪声。★不能用高频: 缩到 48px 后高频会被 BOX 平均掉, 只剩糊边。"""
    return math.sin(math.tau * k * t + ph)


def build_strip(name, length, width, ph, seg=SEG):
    """一条裂缝。中线歪 + 半宽掐点, 都是低频噪声; 两端收尖。
    UV 的 v: 0=下缘 / 0.5=中线 / 1=上缘 —— 亮色只给上缘。"""
    verts, faces, uvs = [], [], []
    for i in range(seg + 1):
        t = i / float(seg)
        x = (t - 0.5) * length
        env = math.sin(math.pi * t) ** 0.55            # 两端收尖
        ## ★中线摆幅从 0.22 收到 0.14: 摆太大时上缘亮棱起伏过猛, 远看是"翅膀"不是"棱"
        cy = width * 0.14 * env * (_noise(t, 2.0, ph) * 0.6 + _noise(t, 5.0, ph * 1.7) * 0.4)
        hw = (width * 0.5) * env * (0.70 + 0.30 * abs(_noise(t, 4.0, ph + 0.9)))
        hw = max(hw, width * 0.02)
        verts.append((x, cy + hw, 0.0))
        verts.append((x, cy, 0.0))
        verts.append((x, cy - hw, 0.0))
        uvs.append((t, 1.0))
        uvs.append((t, 0.5))
        uvs.append((t, 0.0))
    for i in range(seg):
        r0, r1 = i * 3, (i + 1) * 3
        faces.append((r0 + 0, r0 + 1, r1 + 1, r1 + 0))
        faces.append((r0 + 1, r0 + 2, r1 + 2, r1 + 1))
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
    mat = bpy.data.materials.new("slit_mat")
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
    cd.ortho_scale = 1.0            # 画布覆盖 -0.5..0.5
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)   # ★正上方直视
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, default=6)
    ap.add_argument("--px", type=int, default=512)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    mat = build_material()
    for f in range(a.frames):
        t = (f + 1) / float(a.frames)
        ## 裂开的过程: 先出现一道细线, 再撑宽。长度也一起长(不是原地变胖)。
        ## ★首帧宽度要有下限(0.30) —— 纯 t**1.4 让 f0 只有 8.6% 宽,
        ##   缩到 48px 后 alpha 全在 127 以下, 被硬边化(alpha<128 切掉)整帧切光。
        ##   而且裂开这个动作本来就该有个看得见的起点, 不能从零开始。
        length = SLIT_LEN * (0.42 + 0.58 * t)
        width = SLIT_W * (0.30 + 0.70 * t ** 1.4)
        objs = [build_strip("slit_%d" % f, length, width, 1.3)]
        ## 分叉从第 3 帧才长出来 —— 先裂主缝, 再往两边撕开
        if f >= 2:
            bt = (f - 1) / float(max(1, a.frames - 2))
            for bi in range(len(BRANCHES)):
                bpos, bang, blen, bwid, bph = BRANCHES[bi]
                ob = build_strip("br_%d_%d" % (f, bi), length * blen * bt, width * bwid, bph)
                ## ★几何先居中(build_strip 已居中)再旋转, 位移最后加 ——
                ##   `rotation_euler` 绕物体原点转(见 tools/blender_slash.py 头注)
                ob.rotation_euler = (0.0, 0.0, math.radians(bang))
                ob.location = Vector(((bpos - 0.5) * length, 0.0, 0.0))
                objs.append(ob)
        for ob in objs:
            ob.data.materials.append(mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d0_f%d.png" % f)
        bpy.ops.render.render(write_still=True)
        for ob in objs:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_groundslit] 渲出 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
