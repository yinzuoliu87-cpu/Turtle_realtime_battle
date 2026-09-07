# -*- coding: utf-8 -*-
"""blender_sword.py — 006 千刃风暴的【立着的剑】, 单帧正面像, 逐件几何搭出来。

跑法(无窗口):
  blender --background --python tools/blender_sword.py -- --out C:/tmp/sword_up

★★为什么重做(2026-09-07 实拍 48 帧后量出来的两个硬伤):
  ① **旧的四方向表四个方向的剑尖全被画布切掉了**。逐行量 `eq006-sword-dir4.png` 第 1 格:
       第 0~17 行宽度**恒为 6 像素**, 到第 18 行才是护手 —— 也就是刃根本没有收尖,
       它是被画布边缘**平切**的一根等宽棍。四格都一样(0 格 x 2..39 贴右边,
       2 格 x 0..37 贴左边, 1/3 格贴上下边)。⇒ 上屏读作"一根棍/一道划痕", 不是剑。
     ⇒ 这一版把整把剑压进画幅 90%, 上下各留 5% 余量, 刃尖用最上 14% 收成尖。
  ② **旧的剑是 `axis = AXIS_Y` 贴地平放的**。战斗相机俯角 ≈51°, 平放的长条被压掉
     37% 且与地面同平面 ⇒ 实拍里七把剑是七条几乎看不出是剑的斜杠。
     而这个技能的因果链是"从地缝里升起来" —— **从地里升起来的剑当然是立着的**。
     ⇒ 改成 `BILLBOARD_ENABLED` 立起来(与全项目单位立绘同一套), 于是**四个方向表也不需要了**:
       立着的剑正对相机, 朝向由"剑阵往哪推"表达, 不由贴图表达。这张图只要一帧。

★尺寸口径: 画布 512² → 缩到 48² 单元格。剑高 = 画幅 90% ≈ 43 像素。
  游戏里 `pixel_size = 0.040` ⇒ 剑高 1.72 米。龟立绘 `TARGET_BODY_H = 2.0` 米,
  所以剑略矮于龟 —— 大得有分量, 又不至于盖住龟。

★配色走 tools/pixelize_sheet.py 的 steel 板(亮度 247/213/178/128/83/44),
  UV 的 u 横跨宽度做金属剖面: 偏左 30% 是高光, 右侧收暗 —— 光从左上, 与全项目一致。

★★两种姿态, 分别出一张图(2026-09-08 用户实拍后拍板):
  · `--dirs 1`  → 立姿(剑尖朝上): 从地缝里升起来那一段用
  · `--dirs 8`  → **飞行姿态方向表**: 冲刺那一段用
  由来: 第一版整段冲刺剑都是**立着平移**过去的, 用户当场问「剑飞的时候是竖着的？」。
  一把在空中平移的剑没有任何理由保持刃朝上 —— 与「不能凭空没有逻辑出现」是同一类问题。
  ⇒ 立起来那一下改成蓄力, 发射瞬间**转成刃朝前**再射出去。
  ★为什么是方向表而不是运行时旋转: 像素风只能 90° 无损旋转, 45° 一转就糊
  (与 001 飞斩 / 004 毒牙同一条)。这里由 Blender 在**渲染时**转, 每个角度都是干净像素。
  ★角度是【屏幕投影角】不是场地角: 战斗相机俯角 ≈51°, 场地 y 轴投到屏幕要乘 cos51°≈0.63。
    选帧公式见 equip_system._sword_fly_frame()。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402


## 全部尺寸相对画布 1.0(画幅 -0.5..0.5)
BLADE_TIP_Y = 0.450       # 刃尖
GUARD_Y = -0.050          # 护手上沿(= 刃根)
GUARD_BOT_Y = -0.098      # 护手下沿
GRIP_BOT_Y = -0.352       # 握柄下沿
POMMEL_BOT_Y = -0.450     # 柄头底
BLADE_W = 0.100           # 刃最宽(护手处)
BLADE_TIP_FRAC = 0.14     # 最上 14% 收尖
GUARD_W = 0.340           # 护手全长
GRIP_W = 0.046
POMMEL_W = 0.104
SEG = 64

## 金属剖面: u=0 左缘 → u=1 右缘。光从左上 ⇒ 高光偏左 30%。
RAMP = [
    (0.00, ( 74,  86, 110)),   # 亮度  83  左暗边
    (0.10, (168, 182, 204)),   # 亮度 178
    (0.26, (246, 248, 252)),   # 亮度 247  高光(最亮的一条·偏左)
    (0.44, (206, 216, 232)),   # 亮度 213
    (0.62, (118, 132, 158)),   # 亮度 128
    (0.84, ( 74,  86, 110)),   # 亮度  83
    (0.94, ( 38,  46,  64)),   # 亮度  44  右暗边
]
## 握柄单独一条(皮革·整体压暗): 把 u 映到 RAMP 的暗半段
GRIP_RAMP = [
    (0.00, ( 38,  46,  64)),
    (0.18, (118, 132, 158)),
    (0.48, ( 74,  86, 110)),
    (0.80, ( 38,  46,  64)),
]


def srgb_to_linear(c):
    """★Blender 颜色输入吃线性色, 调色板是 sRGB ⇒ 直接喂会整体提亮一整档
    (实测见 tools/blender_slash.py 头注)。"""
    v = c / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_taper(name, y_top, y_bot, hw_fn, seg=SEG):
    """竖着的带状体。UV 的 u 横跨宽度(0=左缘 1=右缘), 用来做金属剖面。"""
    verts, faces, uvs = [], [], []
    for i in range(seg + 1):
        t = i / float(seg)                  # 0 = 顶
        y = y_top + (y_bot - y_top) * t
        hw = max(hw_fn(t), 1e-5)
        verts.append((-hw, y, 0.0))
        verts.append((hw, y, 0.0))
        uvs.append((0.0, t))
        uvs.append((1.0, t))
    for i in range(seg):
        a0, b0, a1, b1 = i * 2, i * 2 + 1, (i + 1) * 2, (i + 1) * 2 + 1
        faces.append((a0, b0, b1, a1))
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


def build_material(name, ramp_def):
    mat = bpy.data.materials.new(name)
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
    ramp.color_ramp.elements[0].position = ramp_def[0][0]
    ramp.color_ramp.elements[0].color = (*[srgb_to_linear(v) for v in ramp_def[0][1]], 1.0)
    for pos, col in ramp_def[1:]:
        e = ramp.color_ramp.elements.new(pos)
        e.color = (*[srgb_to_linear(v) for v in col], 1.0)
    nt.links.new(tex.outputs["UV"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["X"], ramp.inputs["Fac"])   # ★横跨宽度, 不是纵向
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
    cam.rotation_euler = (0.0, 0.0, 0.0)   # ★正面直视
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=512)
    ap.add_argument("--dirs", type=int, default=1,
                    help="1 = 立姿(尖朝上); N>1 = 飞行姿态方向表, 第 k 帧剑尖指向屏幕角 k*360/N")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    steel = build_material("steel", RAMP)
    leather = build_material("leather", GRIP_RAMP)

    ## 刃: 最上 BLADE_TIP_FRAC 收成尖, 往下略微加宽(真刀就是根部最宽)
    def blade_hw(t):
        tip = min(1.0, t / BLADE_TIP_FRAC)
        return (BLADE_W * 0.5) * (0.78 + 0.22 * t) * tip

    ## 护手: 两端略收, 中间最厚
    def guard_hw(t):
        return (GUARD_W * 0.5) * (0.62 + 0.38 * math.sin(math.pi * min(1.0, 0.15 + t * 0.85)))

    ## 柄头: 菱形
    def pommel_hw(t):
        return (POMMEL_W * 0.5) * math.sin(math.pi * t) ** 0.7

    n = max(1, a.dirs)
    for k in range(n):
        parts = [
            (build_taper("blade_%d" % k, BLADE_TIP_Y, GUARD_Y, blade_hw), steel),
            (build_taper("guard_%d" % k, GUARD_Y, GUARD_BOT_Y, guard_hw), steel),
            (build_taper("grip_%d" % k, GUARD_BOT_Y, GRIP_BOT_Y, lambda t: GRIP_W * 0.5), leather),
            (build_taper("pommel_%d" % k, GRIP_BOT_Y, POMMEL_BOT_Y, pommel_hw), steel),
        ]
        ## ★整把剑本来就以世界原点为中心(y 从 -0.45 到 +0.45), 所以逐件绕自身原点转
        ##   = 整体绕中心转, 不需要先平移再转(那正是 tools/blender_slash.py 头注那个坑)。
        ## 立姿时剑尖朝 +Y(屏幕 90°), 所以要指向角 θ 就转 θ-90°。
        if n > 1:
            theta = math.tau * k / float(n)
            for ob, _m in parts:
                ob.rotation_euler = (0.0, 0.0, theta - math.pi * 0.5)
        for ob, mat in parts:
            ob.data.materials.append(mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob, _m in parts:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_sword] 渲出 %d 帧 → %s" % (n, a.out))


if __name__ == "__main__":
    main()
