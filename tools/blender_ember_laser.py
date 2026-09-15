# -*- coding: utf-8 -*-
"""blender_ember_laser.py — 096 余烬【处决】: 天降轨道激光(照 LoL 无限火力「轨道激光」终结特效逐帧研究)。

跑法(无窗口):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_ember_laser.py -- \
      --out C:/tmp/ember_laser [--frames 0,7,12]
  产物: <out>/beam/d{j}_f0.png(光柱层, 侧视 340×2660 = 26.6 m) + <out>/dome/d{j}_f0.png(穹顶层, 侧视 340×850 = 8.5 m)
        + <out>/ground/d{j}_f0.png(贴地层, 俯视 340×340 = 3.4 m); 三层都是 0.01 m/像素
  再: pixelize_sheet.py <out>/beam --dirs 32 --frames 1 --cell 626 --cell-w 80 --art-h 626 --palette orbital
      pixelize_sheet.py <out>/dome --dirs 32 --frames 1 --cell 200 --cell-w 80 --art-h 200 --palette orbital
      pixelize_sheet.py <out>/ground --dirs 32 --frames 1 --cell 80 --art-h 80 --palette orbital

★由来 (2026-09-15)
  用户:「9/9处决没余烬的专属特效啊，还是这个特效不明显？我需要你参考lol比较新版本的无限火力里击杀敌人时一道激光从天击中敌人的那种处决」
  旧演出是 `AxeFinalVfx.ember_execute` 的一根 0.34×2.6×0.34 米红色 BoxMesh, 0.35 秒。
  参考: LoL 无限火力终结特效头像「轨道激光」(Orbital Laser), 1080p 60fps 实拍逐帧 135 帧。

★第一版(纯色平面)试渲作废: 击杀闪光是一颗实心白椭圆(= 被否过的「白球」)、脉冲是一颗平涂黄蛋、
  光柱是几条匀色直条、穹顶是一根细弧线、地面是硬边星形 —— 参考里全是【发光 + 分层 + 流纹】。
  ⇒ 第二版一律靠着色器出层次: 横向 / 径向渐变决定颜色带与透明度, 噪波给流纹和碎边;
    像素化锁调色板时渐变会被量化成像素风色阶。

★分段(参考 2.13 秒; 这里 20fps × 32 帧 = 1.6 秒, 只压缩「持续灼烧」段: 7 次脉冲 → 5 次, 间隔仍递减):
  帧 0      击杀闪光: 目标身上白芯青边的放射光芒
  帧 1–2    上行信号: 青色细线从天连到目标(带一点波浪) · 脚下小红盘
  帧 3–4    蓄力细光柱: 粉白细芯 + 红辉光, 红色火舌亮段沿柱下移
  帧 5      展开(半宽)
  帧 6      全宽 + 第 1 次黄色脉冲在柱顶
  帧 7      第 1 次脉冲到目标 ⇒ 地面橙光炸开、穹顶出现、碎石飞起
  帧 8–19   持续: 三色带光柱 + 竖向流纹下滚; 脉冲到底帧 12 / 15 / 17 / 19(间隔 5→3→2→2); 碎石升起回落
  帧 20–24  收窄: 宽度 1.0 → 0.35, 偏暗红, 穹顶与地面光淡出
  帧 25–28  细线: 红橙细线 + 淡黄芯, 渐暗
  帧 29–31  断开消散: 下半段先没, 上段从上往下擦除

★尺寸(与龟立绘同一个像素尺寸 0.0425 m/像素; 龟身高 H = 2.0 m):
  光柱主体全宽 0.45H = 0.9 m(外晕含在渐变里, 总宽 1.4 m) · 脉冲 0.7H · 穹顶宽 1.5H 高 1.0H
"""
import argparse
import math
import os
import random
import sys

import bpy      # noqa: E402
import bmesh    # noqa: E402
from mathutils import Vector   # noqa: E402

N_FRAMES = 32
H = 2.0
BODY_W = 0.45 * H
BEAM_W = 1.4                 # 渐变层总宽(含外晕)
BEAM_TOP = 26.0
## ★光柱层拉高到 26.6 米帧(2026-09-15 门禁量出来): 原来 8.5 米帧、柱顶 7.9 米, 战斗镜头里投影在
##   屏幕 y=407/1280(脚在 696)—— 平切的柱顶落在屏幕中上部, 读成一根悬空的柱子而不是从天而降。
ZK = BEAM_TOP / 8.2          # 纵向噪波 / 波浪按原 8.2 米的密度折算, 拉高后流纹不被拉长
BEAM_ORTHO = 26.6            # 光柱层正交高度(米); 帧底仍在地下 0.6 米
PULSE_BOTTOM = [7, 12, 15, 17, 19]


def srgb(c, a=1.0):
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), a)


C = {
    "white": (255, 254, 240), "core": (253, 248, 211), "pulse": (251, 233, 93), "pulse_hi": (253, 249, 140),
    "bright": (251, 207, 135), "body": (239, 143, 90), "salmon": (216, 135, 107), "edge": (185, 47, 25),
    "dark": (120, 30, 20), "ground": (248, 158, 60), "ground_hi": (251, 193, 68), "cyan_hi": (138, 240, 233),
    "cyan": (98, 181, 214), "rock": (40, 32, 30), "pink": (250, 214, 214),
}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup(px_w, px_h, ortho, cam_loc, cam_rot):
    sc = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    sc.render.resolution_x = px_w
    sc.render.resolution_y = px_h
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector(cam_loc)
    cam.rotation_euler = cam_rot
    sc.collection.objects.link(cam)
    sc.camera = cam


# ─────────────────────────── 着色器工具 ───────────────────────────

class NT:
    """一个材质的节点树小工具: 渐变 → 颜色带(含透明度) → 自发光 × 透明混合。"""

    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        if hasattr(self.m, "surface_render_method"):
            self.m.surface_render_method = "BLENDED"
        self.m.use_backface_culling = False
        self.nt = self.m.node_tree
        for n in list(self.nt.nodes):
            self.nt.nodes.remove(n)
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        tc = self.nt.nodes.new("ShaderNodeTexCoord")
        self.sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(tc.outputs["Generated"], self.sep.inputs["Vector"])
        self.gen = tc.outputs["Generated"]

    def math(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = float(v)
            else:
                self.nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    def noise(self, scale_xyz, loc_xyz, detail=4.0):
        mp = self.nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = scale_xyz
        mp.inputs["Location"].default_value = loc_xyz
        self.nt.links.new(self.gen, mp.inputs["Vector"])
        nz = self.nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = detail
        self.nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
        return nz.outputs["Fac"]

    def finish(self, fac, stops, strength=1.0):
        """stops = [(位置, 颜色键, 不透明度), ...] 位置 0 = 最亮处。"""
        ramp = self.nt.nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.interpolation = "LINEAR"
        els = cr.elements
        while len(els) > 1:
            els.remove(els[-1])
        els[0].position = stops[0][0]
        els[0].color = srgb(C[stops[0][1]], stops[0][2])
        for pos, key, a in stops[1:]:
            e = els.new(pos)
            e.color = srgb(C[key], a)
        self.nt.links.new(fac, ramp.inputs["Fac"])
        em = self.nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = strength
        self.nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
        tr = self.nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = self.nt.nodes.new("ShaderNodeMixShader")
        self.nt.links.new(ramp.outputs["Alpha"], mix.inputs["Fac"])
        self.nt.links.new(tr.outputs[0], mix.inputs[1])
        self.nt.links.new(em.outputs[0], mix.inputs[2])
        self.nt.links.new(mix.outputs[0], self.out.inputs["Surface"])
        return self.m


def across(t):
    """横向渐变: 中轴 0 → 两边 1。"""
    return t.math("MULTIPLY", t.math("ABSOLUTE", t.math("SUBTRACT", t.sep.outputs["X"], 0.5)), 2.0)


def radial(t, sx=1.0, sz=1.0, use_y=False):
    """径向渐变: 中心 0 → 边 1(按包围盒归一)。use_y: 贴地层用 XY。"""
    ax2 = t.sep.outputs["Y"] if use_y else t.sep.outputs["Z"]
    dx = t.math("MULTIPLY", t.math("SUBTRACT", t.sep.outputs["X"], 0.5), 2.0 * sx)
    dz = t.math("MULTIPLY", t.math("SUBTRACT", ax2, 0.5), 2.0 * sz)
    r2 = t.math("ADD", t.math("MULTIPLY", dx, dx), t.math("MULTIPLY", dz, dz))
    return t.math("SQRT", r2), dx, dz


def rays(t, dx, dz, n, sharp=6.0, phase=0.0):
    """放射光芒: 0..1, 沿 n 个方向的尖角。"""
    ang = t.math("ARCTAN2", dz, dx)
    s = t.math("SINE", t.math("ADD", t.math("MULTIPLY", ang, float(n)), phase))
    s = t.math("MAXIMUM", s, 0.0)
    return t.math("POWER", s, sharp)


# ─────────────────────────── 几何 ───────────────────────────

def quad_xz(name, x0, x1, z0, z1, material, y=0.0, wave=0.0, segs=1, phase=0.0):
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        z = z0 + (z1 - z0) * i / segs
        xo = wave * math.sin(i * 1.3 + phase)
        rows.append((bm.verts.new((x0 + xo, y, z)), bm.verts.new((x1 + xo, y, z))))
    for i in range(segs):
        bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(material)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def quad_xy(name, half, material, z=0.0):
    bm = bmesh.new()
    vs = [bm.verts.new((-half, -half, z)), bm.verts.new((half, -half, z)), bm.verts.new((half, half, z)),
          bm.verts.new((-half, half, z))]
    bm.faces.new(vs)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(material)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ─────────────────────────── 材质 ───────────────────────────

def m_beam(phase, redder, k):
    t = NT("beam")
    ac = across(t)
    nz = t.noise((7.0, 1.0, 0.55 * ZK), (0.0, 0.0, phase))
    fac = t.math("ADD", ac, t.math("MULTIPLY", t.math("SUBTRACT", nz, 0.5), 0.45))
    if redder:
        stops = [(0.0, "bright", 1.0), (0.16, "salmon", 1.0), (0.45, "edge", 1.0), (0.75, "dark", 0.7), (1.0, "dark", 0.0)]
    else:
        stops = [(0.0, "core", 1.0), (0.13, "bright", 1.0), (0.34, "body", 1.0), (0.62, "edge", 1.0),
                 (0.82, "dark", 0.65), (1.0, "dark", 0.0)]
    return t.finish(fac, stops, 1.0)


def m_signal(level):
    t = NT("signal")
    ac = across(t)
    return t.finish(ac, [(0.0, "white" if level == 0 else "cyan_hi", 1.0), (0.4, "cyan_hi", 1.0),
                         (0.8, "cyan", 0.6), (1.0, "cyan", 0.0)])


def m_charge():
    t = NT("charge")
    ac = across(t)
    nz = t.noise((5.0, 1.0, 0.8 * ZK), (0.0, 0.0, 0.3))
    fac = t.math("ADD", ac, t.math("MULTIPLY", t.math("SUBTRACT", nz, 0.5), 0.3))
    return t.finish(fac, [(0.0, "pink", 1.0), (0.18, "white", 1.0), (0.3, "edge", 1.0), (0.7, "dark", 0.55),
                          (1.0, "dark", 0.0)])


def m_blob(kind, seed):
    """脉冲火团 / 火舌: 径向渐变 + 噪波碎边。"""
    t = NT("blob")
    r, dx, dz = radial(t)
    nz = t.noise((3.0, 3.0, 3.0), (seed, seed * 0.7, 0.0))
    fac = t.math("ADD", r, t.math("MULTIPLY", t.math("SUBTRACT", nz, 0.5), 0.5))
    if kind == "pulse":
        stops = [(0.0, "white", 1.0), (0.2, "pulse_hi", 1.0), (0.45, "pulse", 1.0), (0.7, "ground", 1.0),
                 (0.88, "edge", 0.6), (1.0, "edge", 0.0)]
    else:
        stops = [(0.0, "bright", 1.0), (0.35, "body", 1.0), (0.75, "edge", 0.7), (1.0, "edge", 0.0)]
    return t.finish(fac, stops)


def m_flash(level):
    t = NT("flash")
    r, dx, dz = radial(t)
    ry = rays(t, dx, dz, 7, 8.0, 0.4)
    fac = t.math("SUBTRACT", r, t.math("MULTIPLY", ry, 0.55 if level == 0 else 0.35))
    if level == 0:
        stops = [(0.0, "white", 1.0), (0.32, "white", 1.0), (0.5, "cyan_hi", 1.0), (0.7, "cyan", 0.7), (0.9, "cyan", 0.0)]
    else:
        stops = [(0.0, "white", 1.0), (0.2, "cyan_hi", 1.0), (0.45, "cyan", 0.6), (0.7, "cyan", 0.0)]
    return t.finish(fac, stops)


def m_dome(fade):
    """穹顶: 单独一层【实心】渐变 —— 轮廓(掠射)亮橙黄, 正对镜头的中间暗橙。
    ★第二版试渲它只剩一根细弧线: 半透明像素在像素化锁色板时被硬切(alpha < 24 全透、否则全实),
      光罩的"半透明"烤不进图里。⇒ 拆成独立一层实心烤, 进引擎整层 modulate 透明度叠在光柱后面。"""
    t = NT("dome")
    lw = t.nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    fac = t.math("SUBTRACT", 1.0, lw.outputs["Facing"])
    a = 1.0 if fade >= 0.5 else 0.0
    return t.finish(fac, [(0.0, "ground_hi", a), (0.2, "ground", a), (0.55, "body", a), (0.8, "edge", a), (1.0, "dark", a)])


def m_ground(g, star, phase):
    t = NT("ground")
    r, dx, dz = radial(t, use_y=True)
    ry = rays(t, dx, dz, 11, 10.0, phase)
    nz = t.noise((4.0, 4.0, 1.0), (phase, 0.0, 0.0))
    fac = t.math("SUBTRACT", r, t.math("MULTIPLY", ry, 0.35 if star else 0.12))
    fac = t.math("ADD", fac, t.math("MULTIPLY", t.math("SUBTRACT", nz, 0.5), 0.2))
    ## ★圆形收边: 光芒把 fac 往下压 0.35, 不收的话沿光芒方向到 r≈1.35 还不透明 ⇒ 撞到方形面片的边,
    ##   像素化后脉冲帧包围盒是满格 (0,0)-(127,127), 光芒被切成方角(2026-09-15 逐帧量出来的)。
    ##   ⇒ r 从 0.80 起强制往 1 推, r ≥ 0.90 一律透明(离格边留 ≥ 6 像素)。
    ##   第二版从 0.90 起推, 包围盒仍到 (0,0)-(126,126): 圆刚好内切, 四个边中点还是贴着(门禁「不贴边」红)。
    fac = t.math("MAXIMUM", fac, t.math("MULTIPLY", t.math("SUBTRACT", r, 0.80), 10.0))
    s = max(0.2, g)
    return t.finish(fac, [(0.0, "core", 1.0), (0.1 * s, "ground_hi", 1.0), (0.32 * s, "ground", 1.0),
                          (0.62 * s + 0.05, "edge", 0.8), (0.85 * s + 0.1, "dark", 0.35), (min(1.0, s + 0.12), "dark", 0.0)])


def m_red_disc():
    t = NT("reddisc")
    r, dx, dz = radial(t, use_y=True)
    return t.finish(r, [(0.0, "body", 1.0), (0.45, "edge", 1.0), (0.8, "dark", 0.5), (1.0, "dark", 0.0)])


def m_rock():
    t = NT("rock")
    lw = t.nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.4
    return t.finish(lw.outputs["Facing"], [(0.0, "rock", 1.0), (0.7, "rock", 1.0), (1.0, "body", 1.0)])


# ─────────────────────────── 时间轴 ───────────────────────────

def beam_width_k(j):
    if j <= 4:
        return 0.0
    if j == 5:
        return 0.5
    if j <= 19:
        return 1.0 + (0.14 if (j in PULSE_BOTTOM or j + 1 in PULSE_BOTTOM) else 0.0)
    if j <= 24:
        return 1.0 - 0.65 * (j - 19) / 5.0
    return 0.0


def pulse_z(j):
    for b in PULSE_BOTTOM:
        if j == b:
            return 0.9
        if j == b - 1:
            return 4.2
        if j == b - 2 and b - 2 >= 6:
            return 7.2
    return None


def ground_flash(j):
    if j < 7 or j > 24:
        return 0.0
    base = 0.55
    for b in PULSE_BOTTOM:
        if 0 <= j - b <= 1:
            base = max(base, 1.0 - 0.35 * (j - b))
    if j >= 20:
        base *= 1.0 - (j - 19) / 5.0
    return base


def build_beam(j):
    if j in (0, 1):
        s = 2.7 if j == 0 else 1.9
        quad_xz("flash", -s * 0.5, s * 0.5, 1.0 - s * 0.5, 1.0 + s * 0.5, m_flash(j), y=-0.02)
    if j in (1, 2):
        quad_xz("signal", -0.07, 0.07, 0.4, BEAM_TOP, m_signal(j - 1), y=-0.05, wave=0.05, segs=int(18 * ZK), phase=j)
    if j in (3, 4):
        quad_xz("charge", -0.28, 0.28, 0.0, BEAM_TOP, m_charge(), y=0.0)
        tz = BEAM_TOP * (0.7 if j == 3 else 0.32)
        quad_xz("tongue", -0.36, 0.36, tz - 0.9, tz + 0.9, m_blob("tongue", j), y=-0.05)
    k = beam_width_k(j)
    if k > 0.0:
        w = BEAM_W * k
        quad_xz("beam", -w * 0.5, w * 0.5, 0.0, BEAM_TOP, m_beam(j * 0.35, j >= 20, k), y=0.0)
    pz = pulse_z(j)
    if pz is not None and k > 0.0:
        pw = 0.7 * H
        quad_xz("pulse", -pw * 0.5, pw * 0.5, pz - 1.2, pz + 1.2, m_blob("pulse", j * 1.7), y=-0.15)
    if 7 <= j <= 19:
        for i in range(9):
            r2 = random.Random(77 + i)
            vx = r2.uniform(-1.6, 1.6)
            vz = r2.uniform(3.0, 5.2)
            tt = (j - 7) * 0.08
            x = vx * tt
            z = 0.15 + vz * tt - 0.5 * 5.4 * tt * tt
            if z < 0.05:
                continue
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r2.uniform(0.08, 0.16), location=(x, -0.35, z))
            rock = bpy.context.active_object
            rock.rotation_euler = (r2.uniform(0, 3), r2.uniform(0, 3), r2.uniform(0, 3))
            rock.scale = (1.0, r2.uniform(0.6, 1.0), r2.uniform(0.6, 1.2))
            rock.data.materials.append(m_rock())
    if 25 <= j <= 28:
        w = 0.1 if j < 27 else 0.07
        quad_xz("thin", -w, w, 0.0, BEAM_TOP, m_beam(j * 0.35, True, 0.2), y=0.0)
    if 29 <= j <= 31:
        top_cut = BEAM_TOP * (1.0 - 0.22 * (j - 29))
        quad_xz("remnant", -0.07, 0.07, BEAM_TOP * 0.5, top_cut, m_beam(j * 0.35, True, 0.1), y=0.0)


def build_dome(j):
    """穹顶层(帧 7–22): 半球光罩; 收窄期(帧 20–22)整体缩小后消失。"""
    if not (7 <= j <= 22):
        return
    shrink = 1.0 if j < 20 else max(0.35, 1.0 - (j - 19) * 0.22)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0.0, 0.3, 0.0))
    dome = bpy.context.active_object
    dome.scale = (1.5 * shrink, 1.0 * shrink, 2.0 * shrink)
    me = dome.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m_dome(1.0))


def build_ground(j):
    if 1 <= j <= 4:
        quad_xy("red_disc", 0.55, m_red_disc(), z=0.0)
    g = ground_flash(j)
    if g > 0.0:
        ## ★半边长 2.7 → 1.6 米(可见直径 4.8 → 2.9 米): 2026-09-15 台子录像 18.9 秒, 4.8 米一炸把左右两只龟都盖住;
        ##   台子里相邻两只龟中心距 ≈ 2.9 米。
        quad_xy("glow", 1.6, m_ground(g, j in PULSE_BOTTOM, j * 0.4), z=0.0)
    if 5 <= j <= 24:
        quad_xy("hit", BODY_W * 0.6 * max(0.35, beam_width_k(j)), m_red_disc(), z=0.02)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", default="")
    a = ap.parse_args(argv)
    only = [int(x) for x in a.frames.split(",") if x != ""]
    for sub in ("beam", "dome", "ground"):
        os.makedirs(os.path.join(a.out, sub), exist_ok=True)
    n = 0
    for j in range(N_FRAMES):
        if only and j not in only:
            continue
        clear_scene()
        setup(340, 2660, BEAM_ORTHO, (0.0, -10.0, BEAM_ORTHO * 0.5 - 0.6), (math.radians(90.0), 0.0, 0.0))
        build_beam(j)
        bpy.context.scene.render.filepath = os.path.join(a.out, "beam", "d%d_f0.png" % j)
        bpy.ops.render.render(write_still=True)
        clear_scene()
        setup(340, 850, 8.5, (0.0, -10.0, 8.5 * 0.5 - 0.6), (math.radians(90.0), 0.0, 0.0))
        build_dome(j)
        bpy.context.scene.render.filepath = os.path.join(a.out, "dome", "d%d_f0.png" % j)
        bpy.ops.render.render(write_still=True)
        clear_scene()
        setup(340, 340, 3.4, (0.0, 0.0, 10.0), (0.0, 0.0, 0.0))
        build_ground(j)
        bpy.context.scene.render.filepath = os.path.join(a.out, "ground", "d%d_f0.png" % j)
        bpy.ops.render.render(write_still=True)
        n += 1
    print("[blender_ember_laser] 渲 %d 帧 × 3 层 → %s" % (n, a.out), flush=True)


if __name__ == "__main__":
    main()
