# -*- coding: utf-8 -*-
"""blender_cake_field.py — 072 铁皮蛋糕盒【蛋糕法阵】: 贴地蛋糕盘(俯视) + 8 根立着的生日蜡烛(公告板)。

跑法(无窗口):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_cake_field.py -- --out C:/tmp/cake
  python tools/pixelize_sheet.py C:/tmp/cake/plate  --dirs 19 --frames 1 --cell 192 --art-h 192 --palette cake -o assets/sprites/vfx/eq072-cake-plate.png
  python tools/pixelize_sheet.py C:/tmp/cake/candle --dirs 18 --frames 1 --cell 64 --cell-w 32 --art-h 64 --palette cake -o assets/sprites/vfx/eq072-cake-candle.png

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-15)
════════════════════════════════════════════════════════════════════════
用户:「072的粉色蛋糕法阵太敷衍了，需要重做」。2026-08-11 已否过一次素圈(「很敷衍」), 二轮加了辐条与 8 颗奶糕又被否
⇒ 否的是「程序图形」这一整类(程序波浪环 + 程序辐条 + 程序奶糕), 不是某个参数。
文案: 礼盒技能召唤 300 码蛋糕法阵 5 秒, 每秒为法阵内友军回复生命与龟能; 法阵跟着礼盒走(2026-08-11 用户拍板「是要跟随的」)。

★第一版试渲作废(我自己逐帧看的): 96 格里 300 码 ⇒ 一个 texel 15 厘米 = 龟身 texel 的 5 倍, 裱花奶油球只剩圆点;
  盘面满铺高频噪波糖霜 = 一片粉色雪花噪点; 蜡烛贴地俯视只是 2 像素黄方块(读不出蜡烛);
  展开前两帧是一圈细棕环(= 被否过的素圈); 循环 / 脉动帧裱花边离格边 1 像素。
  ⇒ 第二版: 盘 192 格(texel 7.8 厘米); 蜡烛改立着的公告板单独一张表, texel = 龟身 texel;
    展开 = 裱花袋沿盘边挤一圈(扇区扫过去, 挤到哪画到哪); 糖霜只撒在内圈环带、是长条米粒糖不是噪点;
    脉动 = 裱花边一亮 + 一圈小星光往圈里飘(「给圈里的友军」)。

帧表(与引擎 food_eq_vfx 常量逐一对应):
  plate 19 帧: 展开 0~5 / 常态 6 / 脉动 7~12 / 收盘 13~18
  candle 18 帧: 冒出 0~3 / 燃烧循环 4~7 / 脉动火苗窜高 8~11 / 吹灭冒烟下沉 12~17

★尺子:
  plate: 正俯视、正交 2.0、960 像素渲 ⇒ 192 格每单位 96 像素; 裱花边外沿半径 RIM_R(= 判定半径)。
    引擎按「外沿直径 = 2 × 300 码」设 pixel_size(同 064 诅咒水波)。
  candle: 相机仰角 35°、正交高 2.0 米、256×512 渲 ⇒ 64 格高每像素 3.125 厘米 ≈ 龟身 texel(1.40 m / 45 px)。
    蜡烛底(z = 0)投到帧 y = −0.72 ⇒ 格里第 55 行(引擎按这一行立在地上)。
"""
import argparse
import math
import os
import random
import sys

import bpy   # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import blender_bladder as bb        # noqa: E402
import blender_bladder_fx as bfx    # noqa: E402

## ── 盘(俯视, 单位 = 帧半宽) ──
RIM_R = 0.942         # 裱花边外沿(描边外缘) = 判定半径
ROSETTE_RING = 0.87   # 裱花奶油花中心所在半径
ROSETTE_R = 0.072     # 奶油花描边半径
N_ROSETTE = 20
BAND_OUT = 0.885      # 草莓糖霜带外沿(压在奶油花下面)
BAND_IN = 0.74        # 糖霜带内沿(淋面往里滴)
BERRY_R = 0.64        # 草莓半颗所在半径
N_BERRY = 8
SPRINKLE_IN, SPRINKLE_OUT, N_SPRINKLE = 0.46, 0.72, 70

## ── 蜡烛(侧仰视, 单位 = 米) ──
CAM_ELEV = 35.0
CANDLE_H = 0.62
CANDLE_RAD = 0.07
BASE_SCREEN_Y = -0.72

C_CREAM = (250, 240, 222)
C_CREAM_SH = (222, 196, 170)
C_PINK = (240, 150, 176)
C_PINK_DK = (190, 96, 128)
C_CHOC_DK = (70, 40, 32)
C_WAX = (246, 230, 150)
C_FLAME = (255, 214, 100)
C_FLAME_OR = (244, 150, 62)
C_FLAME_HI = (255, 250, 214)
C_SMOKE = (150, 146, 150)
C_BERRY = (214, 58, 72)
C_BERRY_DK = (140, 30, 50)
C_LEAF = (110, 170, 80)


# ══════════════════════════════════════════════════════════════════
#  通用几何
# ══════════════════════════════════════════════════════════════════

def _link(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.context.collection.objects.link(ob)
    return ob


def disc(name, cx, cy, r, mat, z, sx=1.0, sy=1.0, segs=24):
    verts = [(cx, cy, z)] + [(cx + math.cos(2 * math.pi * i / segs) * r * sx, cy + math.sin(2 * math.pi * i / segs) * r * sy, z)
                             for i in range(segs)]
    return _link(name, verts, [(0, 1 + i, 1 + (i + 1) % segs) for i in range(segs)], mat)


def star2(name, cx, cy, r_out, r_in, n, mat, z, rot=0.0):
    """不压扁的 n 角星(俯视贴地用; bfx.star 会把 y 压到 0.75)。"""
    verts = [(cx, cy, z)]
    for i in range(n * 2):
        a = math.pi * i / n + rot
        rr = r_out if i % 2 == 0 else r_in
        verts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z))
    return _link(name, verts, [(0, 1 + i, 1 + (i + 1) % (n * 2)) for i in range(n * 2)], mat)


def ring_sector(name, r, mat, z, keep, segs=120):
    """整圆顶点(包围盒对称 ⇒ 着色器 radial() 外沿 = 1)只留 keep(角度) 为真的扇面。"""
    verts = [(0.0, 0.0, z)] + [(math.cos(2 * math.pi * i / segs) * r, math.sin(2 * math.pi * i / segs) * r, z) for i in range(segs + 1)]
    faces = [(0, 1 + i, 2 + i) for i in range(segs) if keep(2 * math.pi * (i + 0.5) / segs)]
    return _link(name, verts, faces, mat)


def sweep_keep(frac):
    """从正上方(90°)顺时针扫 frac 圈: 裱花袋挤到哪, 画到哪。"""
    if frac >= 0.999:
        return lambda a: True
    span = frac * 2 * math.pi

    def keep(a):
        d = (math.pi * 0.5 - a) % (2 * math.pi)
        return d <= span
    return keep


# ══════════════════════════════════════════════════════════════════
#  ① 盘(俯视)
# ══════════════════════════════════════════════════════════════════

def band_mat(name, phase):
    """草莓糖霜带: 外沿整齐(压在奶油花下), 内沿按噪波往里滴, 滴痕内沿一道暗粉 + 巧克力描边。"""
    s = bfx.Shade(name)
    r = s.radial()
    nz = s.noise((7.0, 7.0, 1.0), (phase, 0.0, 0.0), detail=2.0)
    fac = s.math("ADD", r, s.math("MULTIPLY", s.math("SUBTRACT", nz, 0.5), 0.16))
    k = BAND_OUT
    stops = [(0.0, C_PINK, 0.0), (BAND_IN / k - 0.035, C_PINK, 0.0), (BAND_IN / k - 0.02, C_CHOC_DK, 1.0),
             (BAND_IN / k, C_PINK_DK, 1.0), (BAND_IN / k + 0.04, C_PINK, 1.0), (0.93, C_PINK, 1.0),
             (0.97, C_PINK_DK, 1.0), (1.0, C_CHOC_DK, 1.0)]
    return s.finish(fac, stops)


def rosette(k, x, y, scale, mats, z=0.3):
    m_out, m_sh, m_cr, m_hi = mats
    rr = ROSETTE_R * scale
    disc("ro%d" % k, x, y, rr, m_out, z)
    star2("rs%d" % k, x, y, rr * 0.92, rr * 0.70, 8, m_sh, z + 0.01, rot=0.2)
    star2("rc%d" % k, x - rr * 0.10, y + rr * 0.10, rr * 0.74, rr * 0.52, 8, m_cr, z + 0.02, rot=0.2 + math.pi / 8)
    disc("rd%d" % k, x + rr * 0.04, y - rr * 0.04, rr * 0.20, m_sh, z + 0.03, segs=12)
    disc("rh%d" % k, x - rr * 0.30, y + rr * 0.30, rr * 0.17, m_hi, z + 0.04, segs=12)


def rosette_mats(flash):
    if flash:
        ## 一亮 = 金色描边 + 蜡黄阴影 + 亮芯: 保留星形裱花纹路(第二版全换成奶油白 ⇒ 20 颗白球)
        return (bfx.flat_emit("r_out", C_FLAME), bfx.flat_emit("r_sh", C_WAX),
                bfx.flat_emit("r_cr", C_FLAME_HI), bfx.flat_emit("r_hi", C_FLAME_HI))
    return (bfx.flat_emit("r_out", C_CHOC_DK), bfx.flat_emit("r_sh", C_CREAM_SH),
            bfx.flat_emit("r_cr", C_CREAM), bfx.flat_emit("r_hi", C_FLAME_HI))


def berries(s):
    m_dk = bfx.flat_emit("b_dk", C_BERRY_DK)
    m_b = bfx.flat_emit("b", C_BERRY)
    m_fl = bfx.flat_emit("b_fl", C_PINK)
    m_seed = bfx.flat_emit("b_seed", C_WAX)
    m_leaf = bfx.flat_emit("b_leaf", C_LEAF)
    for i in range(N_BERRY):
        a = 2 * math.pi * i / N_BERRY + math.pi * 0.5
        cx, cy = math.cos(a) * BERRY_R * s, math.sin(a) * BERRY_R * s
        ux, uy = math.cos(a), math.sin(a)        # 尖朝外
        e = max(s, 0.55)
        disc("bo%d" % i, cx, cy, 0.056 * e, m_dk, 0.20, sx=1.0, sy=1.0)
        disc("bb%d" % i, cx - ux * 0.004 * e, cy - uy * 0.004 * e, 0.047 * e, m_b, 0.21)
        disc("bf%d" % i, cx - ux * 0.010 * e, cy - uy * 0.010 * e, 0.026 * e, m_fl, 0.22)
        for j, (sx_, sy_) in enumerate(((0.030, 0.012), (0.030, -0.012), (0.012, 0.028))):
            px_ = cx + (ux * sx_ - uy * sy_) * e
            py_ = cy + (uy * sx_ + ux * sy_) * e
            disc("bs%d_%d" % (i, j), px_, py_, 0.007 * e, m_seed, 0.23, segs=8)
        star2("bl%d" % i, cx - ux * 0.050 * e, cy - uy * 0.050 * e, 0.030 * e, 0.012 * e, 4, m_leaf, 0.24, rot=a)


def sprinkles(s):
    rng = random.Random(72)
    cols = [bfx.flat_emit("sp%d" % i, c) for i, c in enumerate((C_CREAM, C_PINK, C_WAX, C_PINK_DK, C_LEAF))]
    for i in range(N_SPRINKLE):
        a = rng.uniform(0, 2 * math.pi)
        r = math.sqrt(rng.uniform(SPRINKLE_IN ** 2, SPRINKLE_OUT ** 2)) * s
        th = rng.uniform(0, math.pi)
        cx, cy = math.cos(a) * r, math.sin(a) * r
        hl, hw = 0.022, 0.009
        dx, dy = math.cos(th), math.sin(th)
        v = [(cx - dx * hl - dy * hw, cy - dy * hl + dx * hw, 0.15), (cx + dx * hl - dy * hw, cy + dy * hl + dx * hw, 0.15),
             (cx + dx * hl + dy * hw, cy + dy * hl - dx * hw, 0.15), (cx - dx * hl + dy * hw, cy - dy * hl - dx * hw, 0.15)]
        _link("spr%d" % i, v, [(0, 1, 2, 3)], cols[rng.randrange(len(cols))])


def plate(s=1.0, frac=1.0, flash=False, berries_on=True, sprinkles_on=True, head=False, phase=0.0):
    keep = sweep_keep(frac)
    band = ring_sector("band", BAND_OUT * s, band_mat("band", phase), 0.0, keep)
    del band
    mats = rosette_mats(flash)
    for k in range(N_ROSETTE):
        a = math.pi * 0.5 - 2 * math.pi * k / N_ROSETTE
        d = (math.pi * 0.5 - a) % (2 * math.pi)
        if d > frac * 2 * math.pi + 1e-6:
            continue
        rosette(k, math.cos(a) * ROSETTE_RING * s, math.sin(a) * ROSETTE_RING * s, max(s, 0.5) ** 0.5, mats)
    if head and frac < 0.999:
        ## 裱花袋口正在挤的那一朵: 大一号
        a = math.pi * 0.5 - frac * 2 * math.pi
        rosette(99, math.cos(a) * ROSETTE_RING, math.sin(a) * ROSETTE_RING, 1.22, rosette_mats(False), z=0.5)
    if berries_on:
        berries(s)
    if sprinkles_on:
        sprinkles(s)


def sparkles(r, size, n=N_ROSETTE):
    m_o = bfx.flat_emit("sk_o", C_PINK)
    m_c = bfx.flat_emit("sk_c", C_FLAME_HI)
    for k in range(n):
        a = math.pi * 0.5 - 2 * math.pi * (k + 0.5) / n
        x, y = math.cos(a) * r, math.sin(a) * r
        star2("sko%d" % k, x, y, size, size * 0.30, 4, m_o, 0.6)
        star2("skc%d" % k, x, y, size * 0.55, size * 0.18, 4, m_c, 0.61)


OPEN_FRAC = [0.17, 0.36, 0.55, 0.74, 0.92, 1.0]
PULSE_SPARK = [None, (0.80, 0.085), (0.68, 0.072), (0.57, 0.058), (0.47, 0.044), None]
CLOSE_S = [0.92, 0.80, 0.64, 0.48, 0.33, 0.20]


def build_plate(j):
    if j <= 5:                        # 展开: 挤一圈
        plate(frac=OPEN_FRAC[j], flash=(j == 5), berries_on=j >= 4, sprinkles_on=j >= 5, head=True)
    elif j == 6:                      # 常态
        plate()
    elif j <= 12:                     # 脉动
        p = j - 7
        plate(flash=p <= 1)
        if PULSE_SPARK[p] is not None:
            sparkles(*PULSE_SPARK[p])
    else:                             # 收盘: 缩回礼盒
        plate(s=CLOSE_S[j - 13], sprinkles_on=j - 13 <= 3)


# ══════════════════════════════════════════════════════════════════
#  ② 蜡烛(侧仰视公告板)
# ══════════════════════════════════════════════════════════════════

def candle_camera():
    cam = bpy.data.objects["cam"]
    e = math.radians(CAM_ELEV)
    tz = -BASE_SCREEN_Y / math.cos(e)
    d = (0.0, math.cos(e), -math.sin(e))
    cam.location = (-d[0] * 10.0, -d[1] * 10.0, tz - d[2] * 10.0)
    cam.rotation_euler = (math.radians(90.0 - CAM_ELEV), 0.0, 0.0)
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y // 2


def stripe_mat(name):
    """螺旋条纹蜡: Generated 坐标 → 角度 + 高度 → FRACT → 常数色带(粉 / 奶油), 受光出圆柱明暗。"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])

    def m(op, a, b=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = float(v)
            else:
                nt.links.new(v, n.inputs[i])
        return n.outputs[0]
    ang = m("ARCTAN2", m("SUBTRACT", sep.outputs["Y"], 0.5), m("SUBTRACT", sep.outputs["X"], 0.5))
    f = m("FRACT", m("ADD", m("MULTIPLY", sep.outputs["Z"], 2.6), m("DIVIDE", ang, 2 * math.pi)))
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = bb._srgb(*C_PINK)
    e2 = ramp.color_ramp.elements[1]
    e2.position = 0.5
    e2.color = bb._srgb(*C_CREAM)
    nt.links.new(f, ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    for key in ("Emission Color", "Emission"):
        if key in bsdf.inputs:
            nt.links.new(ramp.outputs["Color"], bsdf.inputs[key])
            break
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 0.35
    return mat


def cream_lit(name):
    return bb.lit_material(name, bb._srgb(*C_CREAM), 0.35)


def candle(h_k=1.0, dollop_k=1.0, flame_k=0.0, lean=0.0, sink=0.0, sparks=None, smoke=None, j=0):
    ## 奶油底座(蜡烛插在糖霜里)
    m_cr = cream_lit("dollop")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=1.0, location=(0.0, 0.0, 0.02))
    dl = bpy.context.active_object
    dl.scale = (0.13 * dollop_k, 0.13 * dollop_k, 0.06 * dollop_k)
    dl.data.materials.append(m_cr)
    for i in range(6):
        a = 2 * math.pi * i / 6
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.045 * dollop_k,
                                             location=(math.cos(a) * 0.11 * dollop_k, math.sin(a) * 0.11 * dollop_k, 0.03))
        bpy.context.active_object.data.materials.append(m_cr)
    h = CANDLE_H * h_k
    top = h - sink
    if top > 0.02:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=CANDLE_RAD, depth=top, location=(0.0, 0.0, top * 0.5))
        bpy.context.active_object.data.materials.append(stripe_mat("wax"))
    if top <= 0.0:
        return
    ## 烛芯
    bfx.droplet("wick", 0.0, 0.0, 0.012, bfx.flat_emit("wick_m", C_CHOC_DK), z=top + 0.02)
    if flame_k > 0.0:
        ## 三层火苗(外焰橙 / 黄 / 白芯), 每层 = 圆底 + 圆锥尖(第二版单个椭球 ⇒ 像素化后一块黄方块)
        fz = top + 0.05 + 0.06 * flame_k
        for i, (col, r, dy) in enumerate(((C_FLAME_OR, 0.060, 0.0), (C_FLAME, 0.050, -0.02), (C_FLAME_HI, 0.032, -0.04))):
            m_f = bfx.flat_emit("fl%d" % i, col, 1.0)
            rr = r * flame_k
            zc = fz - 0.025 * flame_k * i
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=rr, location=(lean * 0.5, dy, zc))
            bpy.context.active_object.data.materials.append(m_f)
            bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=rr, radius2=0.0, depth=rr * 2.6,
                                            location=(lean * 1.2, dy, zc + rr * 1.3))
            bpy.context.active_object.data.materials.append(m_f)
    if sparks:
        m_o = bfx.flat_emit("spk_o", C_FLAME)
        m_c = bfx.flat_emit("spk_c", C_FLAME_HI)
        for i, (x, z, r) in enumerate(sparks):
            so = bfx.star("spk%d" % i, 0.0, 0.0, r, r * 0.3, 4, m_o)
            so.location = (x, -0.05, top + z)
            so.rotation_euler = (math.radians(90.0 - CAM_ELEV), 0.0, 0.0)
            sc_ = bfx.star("spkc%d" % i, 0.0, 0.0, r * 0.5, r * 0.16, 4, m_c)
            sc_.location = (x, -0.06, top + z)
            sc_.rotation_euler = (math.radians(90.0 - CAM_ELEV), 0.0, 0.0)
    if smoke:
        ## 一缕连续卷曲的烟(第二版几颗散球 ⇒ 像素化后几块灰方块)
        m_s = bfx.flat_emit("smoke", C_SMOKE)
        for wi, (z0, ln, ph, r0) in enumerate(smoke):
            for i in range(7):
                f = i / 6.0
                bfx.droplet("smk%d_%d" % (wi, i), 0.040 * math.sin(ph + f * 5.0), -0.02, r0 * (1.0 - 0.5 * f), m_s, z=z0 + f * ln)


FLICK = [(1.00, 0.000), (1.12, 0.012), (0.92, -0.010), (1.05, 0.006)]
FLARE = [(1.55, [(-0.12, 0.30, 0.060), (0.11, 0.24, 0.052)]),
         (1.90, [(-0.17, 0.40, 0.078), (0.15, 0.36, 0.070), (0.02, 0.54, 0.062)]),
         (1.50, [(-0.19, 0.52, 0.062), (0.17, 0.48, 0.056), (0.03, 0.68, 0.050)]),
         (1.15, [(-0.20, 0.62, 0.042), (0.03, 0.78, 0.036)])]
OUT = [dict(flame_k=0.55, lean=-0.02),
       dict(flame_k=0.22, lean=-0.03, smoke=[(CANDLE_H + 0.07, 0.10, 0.0, 0.034)]),
       dict(smoke=[(CANDLE_H + 0.06, 0.24, 0.8, 0.038)]),
       dict(smoke=[(CANDLE_H + 0.14, 0.34, 1.6, 0.040)]),
       dict(sink=0.24, smoke=[(CANDLE_H + 0.24, 0.30, 2.4, 0.036)]),
       dict(sink=0.52, dollop_k=0.85, smoke=[(CANDLE_H + 0.42, 0.20, 3.2, 0.030)])]


def build_candle(j):
    candle_camera()
    if j <= 3:                      # 冒出
        hk = [0.18, 0.62, 1.08, 1.0][j]
        candle(h_k=hk, dollop_k=[0.7, 1.0, 1.0, 1.0][j], flame_k=0.55 if j == 3 else 0.0)
    elif j <= 7:                    # 燃烧循环
        k, ln = FLICK[j - 4]
        candle(flame_k=k, lean=ln)
    elif j <= 11:                   # 脉动火苗窜高
        k, sp = FLARE[j - 8]
        candle(flame_k=k, sparks=sp)
    else:                           # 吹灭 → 冒烟 → 沉回糖霜
        candle(**OUT[j - 12])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    jobs = [("plate", 19, build_plate, 960), ("candle", 18, build_candle, 512)]
    only = [x for x in a.only.split(",") if x]
    n = 0
    for sub, count, fn, px in jobs:
        if only and sub not in only:
            continue
        os.makedirs(os.path.join(a.out, sub), exist_ok=True)
        for j in range(count):
            bb.clear_scene()
            bb.setup_render(px)
            fn(j)
            bpy.context.scene.render.filepath = os.path.join(a.out, sub, "d%d_f0.png" % j)
            bpy.ops.render.render(write_still=True)
            n += 1
    print("[blender_cake_field] rendered %d frames -> %s" % (n, a.out), flush=True)


if __name__ == "__main__":
    main()
