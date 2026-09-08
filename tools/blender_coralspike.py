# -*- coding: utf-8 -*-
"""blender_coralspike.py — 008 双穿珊瑚刺的三件素材: 珊瑚刺弹 / 命中碎裂 / 图标。

跑法(无窗口):
  blender --background --python tools/blender_coralspike.py -- --out C:/tmp/cs --mode spike --dirs 8
  blender --background --python tools/blender_coralspike.py -- --out C:/tmp/ci --mode icon
  blender --background --python tools/blender_coralspike.py -- --out C:/tmp/cb --mode shatter --frames 5

★★由来(2026-09-08 实拍 008): 又是 001/003/004/007 那三件同族老毛病 ——
  ① `VfxTex._make_coralspike_texture()` **程序生成**
  ② `TEXTURE_FILTER_LINEAR` ⇒ 实拍是**一团模糊的粉红雾**飞过去, 完全读不出是"刺"
  ③ `wisp_dir: true` **手动 basis 自由旋转贴图**
  外加图标是全仓最糟的一张: **509x490 / 37566 色 / 3357 半透**(一张全彩绘图缩进图标框)。

★怎么让它读成【珊瑚】而不是【箭/矛】—— 这是本件的关键, 光"做成尖的"不够:
  ① **刺身有节**: 珊瑚是一节一节长出来的, 轮廓上有规律的鼓包(不是光滑锥体)
  ② **两根侧枝**: 珊瑚会分叉。箭有尾羽而珊瑚有枝, 这一条最能分开二者
  ③ **尖是骨白、身是橘红**: 珊瑚骨骼露在尖上(见 pixelize_sheet 的 coral 板)
  没有 ①② 的话, 缩到 40 像素就是一根普通的尖条。

★弹体接现成的 `dirsel` 通道(battle_ballistics._step_projectiles 的 ①),
  **按飞行角度选方向帧、贴图永不旋转** —— 不再手抄一份朝向逻辑。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402


## ── 珊瑚刺(相对画布 1.0, 画幅 -0.5..0.5) ──
SPIKE_LEN = 0.86         # 全长
SPIKE_W = 0.15           # 最粗处
## ★骨白段的长度与它的**横向占比**要一起调, 单调一个都不对:
##   0.26 + 窄带(u 0.14~0.52) ⇒ 只剩 5 个骨白像素, 读不出骨尖;
##   0.34 + 宽带(u 0.16~0.74) ⇒ 骨白变成刺尖那半截的**一道中央亮条**, 读成"带高光的针"。
##   0.22 + 宽带 ⇒ 是个**帽**, 才读作"骨质的尖"。
SPIKE_TIP = 0.22
SEG = 96
## 节: 沿刺身的鼓包频率与幅度。★频率按【缩完每节几像素】定 —— 40 像素长的刺,
##   4 节 = 每节 10 像素, 缩完还看得出"一节一节"; 8 节就糊成锯齿。
KNOT_FREQ = 4.0
KNOT_AMP = 0.22
## 侧枝: (沿刺身位置 t, 角度°, 长度占全长, 粗细占刺身)
## ★侧枝加粗加长一档: 上一版缩完只剩两个小疙瘩, 而"会分叉"正是把珊瑚和箭分开的那一条。
BRANCHES = [
    (0.46,  54.0, 0.30, 0.62),
    (0.68, -46.0, 0.24, 0.52),
]

## 剖面(u 横跨宽度): 光从左上。★色带只给 5 档 —— 刺身缩完只有 7 像素宽,
##   007 那次摆 7 档(每档 1.4px)实拍读成木纹, 同一个教训不再犯。
## ★★描边的宽度要按【缩完剩几像素】算, 不能按"看着细一点好看"定:
##   刺身缩完只有 7 像素宽。0.12/0.90 那版两侧描边各占 0.8 像素 ⇒ **缩完基本没有轮廓**,
##   实拍是一根粉红棍, 贴到花地图上会糊掉。0.20/0.82 ⇒ 各 1.4 像素, 立得住。
RAMP = [
    (0.00, ( 78,  28,  38)),   # 亮度  44  左描边(1.4px)
    (0.20, (255, 198, 176)),   # 亮度 213  受光面
    (0.38, (250, 138, 106)),   # 亮度 168  主珊瑚橘红
    (0.70, (206,  82,  74)),   # 亮度 118  背光
    (0.82, ( 78,  28,  38)),   # 亮度  44  右描边(1.3px)
]
## 尖那一段单独一条: 骨白(珊瑚骨骼露出来)
## ★骨白必须占满尖那一段的**大部分宽度**: 第一版只给 u 0.14~0.52,
##   而尖本身是收窄的 ⇒ 实测整根刺只有 **5 个骨白像素**, 读不出"骨尖"。
TIP_RAMP = [
    (0.00, ( 78,  28,  38)),   # 描边
    (0.16, (250, 240, 230)),   # 亮度 242  骨白(占大部分)
    (0.74, (255, 198, 176)),
    (0.86, ( 78,  28,  38)),   # 描边
]

## 命中碎裂: 一圈飞散的珊瑚碎块
SHARD_N = 9
SHARD_RAMP = [
    (0.00, (250, 240, 230)),
    (0.26, (250, 138, 106)),
    (0.62, (206,  82,  74)),
    (0.88, ( 78,  28,  38)),
]


def srgb_to_linear(c):
    """★Blender 颜色输入吃线性色, 调色板是 sRGB ⇒ 直接喂会整体提亮一整档
    (实测见 tools/blender_slash.py 头注)。"""
    v = c / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_strip(name, y_top, y_bot, hw_l, hw_r, seg=SEG):
    """竖着的带状体, 左右半宽可不同。UV 的 u 横跨宽度(0=左缘 1=右缘)。"""
    verts, faces, uvs = [], [], []
    for i in range(seg + 1):
        t = i / float(seg)
        y = y_top + (y_bot - y_top) * t
        wl = max(hw_l(t), 1e-5)
        wr = max(hw_r(t), 1e-5)
        verts.append((-wl, y, 0.0))
        verts.append((wr, y, 0.0))
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
    nt.links.new(sep.outputs["X"], ramp.inputs["Fac"])
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
    sc.view_settings.view_transform = 'Standard'
    cd = bpy.data.cameras.new("cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = 1.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def _shaft_hw(t):
    """刺身半宽。t=0 是尖。★节: 低频鼓包 —— 珊瑚是一节一节长的, 不是光滑锥体。"""
    tip = min(1.0, t / SPIKE_TIP)
    knot = 1.0 + KNOT_AMP * math.sin(math.tau * KNOT_FREQ * t)
    return (SPIKE_W * 0.5) * (0.62 + 0.38 * t) * tip * knot


def build_spike(body_mat, tip_mat):
    """整根珊瑚刺: 主干(尖朝 +Y) + 两根侧枝。"""
    parts = []
    ## 尖那一段单独一件, 用骨白的 ramp
    parts.append((build_strip("tip", SPIKE_LEN * 0.5, SPIKE_LEN * 0.5 - SPIKE_LEN * SPIKE_TIP,
                              lambda t: _shaft_hw(t * SPIKE_TIP),
                              lambda t: _shaft_hw(t * SPIKE_TIP)), tip_mat))
    parts.append((build_strip("shaft", SPIKE_LEN * 0.5 - SPIKE_LEN * SPIKE_TIP, -SPIKE_LEN * 0.5,
                              lambda t: _shaft_hw(SPIKE_TIP + t * (1.0 - SPIKE_TIP)),
                              lambda t: _shaft_hw(SPIKE_TIP + t * (1.0 - SPIKE_TIP))), body_mat))
    for bi, (bpos, bang, blen, bwid) in enumerate(BRANCHES):
        L = SPIKE_LEN * blen
        W = SPIKE_W * bwid
        ob = build_strip("br%d" % bi, L * 0.5, -L * 0.5,
                         lambda t: (W * 0.5) * (0.30 + 0.70 * t) * min(1.0, t / 0.30),
                         lambda t: (W * 0.5) * (0.30 + 0.70 * t) * min(1.0, t / 0.30))
        ## ★先旋转再平移(几何本来就以自身中心建的) —— 见 tools/blender_slash.py 头注
        ob.rotation_euler = (0.0, 0.0, math.radians(bang))
        ## 侧枝根部接在主干上: 沿主干位置 bpos(0=尖)
        ay = SPIKE_LEN * 0.5 - SPIKE_LEN * bpos
        ob.location = Vector((0.0, ay, 0.0)) + Vector((math.sin(math.radians(bang)) * -L * 0.5,
                                                       math.cos(math.radians(bang)) * L * 0.5, 0.0))
        parts.append((ob, body_mat))
    return parts


def build_shatter(mat, grow):
    """命中碎裂: 一圈飞散的珊瑚碎块。grow ∈ (0,1] 控制飞散半径与碎块缩小。
    ★★碎块必须**大小不一、角度不匀、飞得不一样远**。第一版 9 片等长等角均匀发散,
      实拍读成【烟花】—— 规律的放射就是通用爆炸, 说明不了"珊瑚碎了"。
      用确定性的伪随机(sin 组合)给每片自己的长度/粗细/角度偏移/速度。"""
    obs = []
    for k in range(SHARD_N):
        j1 = math.sin(k * 12.9898) * 43758.5453
        j1 -= math.floor(j1)                      # 0..1 确定性伪随机
        j2 = math.sin(k * 78.233) * 12345.6789
        j2 -= math.floor(j2)
        j3 = math.sin(k * 39.425) * 24691.3578
        j3 -= math.floor(j3)
        a = math.tau * k / float(SHARD_N) + 0.4 + (j1 - 0.5) * 0.55   # 角度不匀
        r = (0.10 + 0.34 * grow) * (0.62 + 0.76 * j2)                 # 飞得不一样远
        ln = 0.20 * (1.0 - 0.55 * grow) * (0.55 + 0.90 * j3)          # 长短不一
        w = 0.055 * (1.0 - 0.45 * grow) * (0.70 + 0.60 * j1)
        ob = build_strip("shard%d" % k, ln * 0.5, -ln * 0.5,
                         lambda t: (w * 0.5) * math.sin(math.pi * min(1.0, 0.15 + t)) ,
                         lambda t: (w * 0.5) * math.sin(math.pi * min(1.0, 0.15 + t)),
                         seg=24)
        ob.rotation_euler = (0.0, 0.0, a - math.pi * 0.5)
        ob.location = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
        ob.data.materials.append(mat)
        obs.append(ob)
    return obs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=512)
    ap.add_argument("--mode", choices=["spike", "icon", "shatter"], default="spike")
    ap.add_argument("--dirs", type=int, default=1)
    ap.add_argument("--frames", type=int, default=1)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    body = build_material("coral", RAMP)
    tip = build_material("coraltip", TIP_RAMP)
    shard = build_material("shard", SHARD_RAMP)

    if a.mode == "shatter":
        nf = max(1, a.frames)
        for f in range(nf):
            obs = build_shatter(shard, (f + 1) / float(nf))
            bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % f)
            bpy.ops.render.render(write_still=True)
            for ob in obs:
                bpy.data.objects.remove(ob, do_unlink=True)
        print("[blender_coralspike] 碎裂 渲出 %d 帧 → %s" % (nf, a.out))
        return

    n = 1 if a.mode == "icon" else max(1, a.dirs)
    for k in range(n):
        parts = build_spike(body, tip)
        ## 刺尖建在 +Y(屏幕 90°)。要指向角 θ 就转 θ-90°; 图标斜 -35° 填满方格。
        rot = math.radians(-35.0) if a.mode == "icon" else (math.tau * k / float(n) - math.pi * 0.5)
        if a.mode == "icon" or n > 1:
            for ob, _m in parts:
                ob.rotation_euler = (ob.rotation_euler[0], ob.rotation_euler[1],
                                     ob.rotation_euler[2] + rot)
                ob.location = ob.location.copy()
                x, y = ob.location.x, ob.location.y
                ob.location = Vector((x * math.cos(rot) - y * math.sin(rot),
                                      x * math.sin(rot) + y * math.cos(rot), 0.0))
        for ob, mat in parts:
            ob.data.materials.append(mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob, _m in parts:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_coralspike] %s 渲出 %d 帧 → %s" % (a.mode, n, a.out))


if __name__ == "__main__":
    main()
