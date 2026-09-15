# -*- coding: utf-8 -*-
"""blender_seraph_boomerang.py — 096 炽天使主动【回旋镖】: 俯视旋转的羽翼 V 形回旋镖 + 命中火花。

跑法(无窗口):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_seraph_boomerang.py -- \
      --out C:/tmp/seraph_boom [--only boom|hit]
  产物: <out>/boom/d{j}_f0.png(8 帧, 俯视, 转一整圈) + <out>/hit/d{j}_f0.png(6 帧, 侧视公告板)
  再: pixelize_sheet.py <out>/boom --dirs 8 --frames 1 --cell 192 --art-h 192 --palette seraph
          -o assets/sprites/vfx/eq096-seraph-boomerang.png
      pixelize_sheet.py <out>/hit --dirs 6 --frames 1 --cell 64 --art-h 64 --palette seraph
          -o assets/sprites/vfx/eq096-seraph-boom-hit.png

★由来 (2026-09-15)
  用户:「7/9的回旋镖同样是在敷衍我啊，回旋镖是什么？以及特效和实际伤害范围完全不一样啊，也没有命中特效」
  旧演出: 一根 0.55×0.10×0.16 米的橙色 BoxMesh 直线飞过去不回来, 判定却是半宽 300 码的带, 没有命中特效。

★这张图说的事
  - 「回旋镖」: V 形两翼(炽天使 ⇒ 白金羽翼), 俯视贴地旋转, 飞出去再回来(路径由代码走, 图只管转)。
  - 「特效 = 伤害范围」: 相机正交宽度 = 2R ⇒ **格子边缘就是判定半径 R**。引擎按「帧宽 = 2 × SERAPH_BOOM_R」
    摆 pixel_size, 翼尖画到 0.94R、翼尖后的弧形流光外沿画到 0.97R ⇒ 转起来扫出的那一圈 = 判定圈
    (门禁 verify_axe_finals 量不透明像素离帧心的最远距离 ≥ 0.9 × 半格)。
  - 流光三段由亮到暗(halo → gold_lt → orange)、由粗到细: 像素画没有半透明(pixelize 把 alpha<24 切掉、
    其余全置不透明), "越往后越淡"只能靠**颜色阶梯 + 变细**表达, 不能靠透明度。
  - 命中火花: 被镖扫到的那个人身上一闪(白金四角星芯 + 八道放射 + 几片羽毛飘开)。
    ★芯是**四角星**不是圆盘 —— 实心白圆盘就是被点名否掉的「白球」那一类。
"""
import argparse
import math
import os
import sys

import bpy      # noqa: E402
import bmesh    # noqa: E402
from mathutils import Vector   # noqa: E402

C = {
    "white": (255, 252, 235), "pearl": (247, 246, 238), "halo": (250, 230, 150), "gold_lt": (240, 215, 130),
    "feather": (224, 217, 179), "gold": (208, 191, 115), "gold_dk": (191, 163, 52), "bronze": (133, 110, 29),
    "shadow": (80, 64, 16), "orange": (255, 179, 71), "line": (40, 33, 9),
}


def srgb(c, a=1.0):
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), a)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup(px, ortho, cam_loc, cam_rot):
    sc = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    sc.render.resolution_x = px
    sc.render.resolution_y = px
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
    ld = bpy.data.lights.new("key", type="SUN")
    ld.energy = 3.0
    key = bpy.data.objects.new("key", ld)
    key.rotation_euler = (math.radians(35.0), math.radians(-25.0), math.radians(30.0))
    sc.collection.objects.link(key)
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs["Color"].default_value = (0.5, 0.5, 0.5, 1.0)
        bg.inputs["Strength"].default_value = 0.6


def mat_lit(name, key, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = srgb(C[key])
    b.inputs["Roughness"].default_value = 0.35
    if emit > 0.0:
        if "Emission Color" in b.inputs:
            b.inputs["Emission Color"].default_value = srgb(C[key])
        if "Emission Strength" in b.inputs:
            b.inputs["Emission Strength"].default_value = emit
    return m


def mat_emit(name, key):
    """纯自发光(不受光照): 流光 / 火花。像素化后不留半透明, 所以不做透明混合。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = False
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(C[key])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def mat_outline():
    m = bpy.data.materials.new("outline")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(C["line"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True
    return m


def prism_xy(name, pts, thick, z=0.0):
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z - thick * 0.5)) for x, y in pts]
    top = [bm.verts.new((x, y, z + thick * 0.5)) for x, y in pts]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def add_outline(ob, m_line, t=0.022):
    ob.data.materials.append(m_line)
    mod = ob.modifiers.new("ol", "SOLIDIFY")
    mod.thickness = t
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.material_offset = len(ob.data.materials) - 1


def _v(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s)


def _norm(v):
    L = math.hypot(v[0], v[1])
    return (v[0] / L, v[1] / L) if L > 1e-9 else (1.0, 0.0)


def _rot(p, deg):
    a = math.radians(deg)
    return (p[0] * math.cos(a) - p[1] * math.sin(a), p[0] * math.sin(a) + p[1] * math.cos(a))


## 回旋镖的几何(俯视, R=1 的局部坐标, 旋转中心 = 原点 = 判定圆心):
##   · 肘部 ELBOW 不在圆心: 真回旋镖绕的是 V 口里的质心转, 肘部偏在一侧 ——
##     这样转起来是"一把 V 在甩", 不是"两根针绕钉子转"(第一版就是那样, 读成钟表指针)。
##   · 两臂翼尖到圆心 TIP_R, 夹角 ±TIP_DEG; 臂身是一条外凸的二次曲线, 肘部宽、翼尖尖。
##   · 外侧 = 前缘(白亮边), 内侧 = 一排羽毛(羽白 / 金交替)。
ELBOW = (-0.34, 0.0)
TIP_R = 0.92
TIP_DEG = 55.0


def arm_geometry(k, R):
    """一条臂(k=+1 上臂 / -1 下臂)。返回 (中线点, 外侧法线, 切线, 宽度) 各 N+1 个采样。"""
    E = (ELBOW[0] * R, ELBOW[1] * R)
    T = (TIP_R * R * math.cos(math.radians(TIP_DEG)), k * TIP_R * R * math.sin(math.radians(TIP_DEG)))
    d = _norm((T[0] - E[0], T[1] - E[1]))
    n_out = (-d[1], d[0]) if k > 0 else (d[1], -d[0])          # 背离 V 口的一侧
    P = ((E[0] + T[0]) * 0.5 + n_out[0] * 0.12 * R, (E[1] + T[1]) * 0.5 + n_out[1] * 0.12 * R)
    cs, ns, ts, ws = [], [], [], []
    N = 16
    for i in range(N + 1):
        u = i / N
        c = ((1 - u) ** 2 * E[0] + 2 * (1 - u) * u * P[0] + u * u * T[0],
             (1 - u) ** 2 * E[1] + 2 * (1 - u) * u * P[1] + u * u * T[1])
        t = _norm((2 * (1 - u) * (P[0] - E[0]) + 2 * u * (T[0] - P[0]),
                   2 * (1 - u) * (P[1] - E[1]) + 2 * u * (T[1] - P[1])))
        no = (-t[1], t[0]) if k > 0 else (t[1], -t[0])
        cs.append(c)
        ns.append(no)
        ts.append(t)
        ws.append((0.25 + (0.045 - 0.25) * (u ** 0.9)) * R)
    return cs, ns, ts, ws, T


def _tapered_arc(name, a0_deg, a1_deg, r_out, w0, w1, z, mat, segs=10):
    """一段【由粗到细】的贴地弧带(俯视): 角度 a0→a1, 外沿 r_out, 径向宽度 w0→w1。"""
    bm = bmesh.new()
    outer, inner = [], []
    for i in range(segs + 1):
        f = i / segs
        aa = math.radians(a0_deg + (a1_deg - a0_deg) * f)
        w = w0 + (w1 - w0) * f
        outer.append(bm.verts.new((r_out * math.cos(aa), r_out * math.sin(aa), z)))
        inner.append(bm.verts.new(((r_out - w) * math.cos(aa), (r_out - w) * math.sin(aa), z)))
    for i in range(segs):
        bm.faces.new((outer[i], outer[i + 1], inner[i + 1], inner[i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_boomerang(angle_deg, R):
    m_line = mat_outline()
    ## ★全部走纯自发光(平涂): 第二版臂身用受光材质, 太阳从一侧打 ⇒ 下臂的羽毛整排发灰,
    ##   转到不同帧时同一片羽毛忽亮忽暗(俯视旋转的东西不该带固定光向)。
    ## ★配色(第三版试渲后改): 臂身羽色(224,217,179)在俯视里是一片卡其, 读不出「白金羽翼」 ⇒
    ##   臂身珍珠白、前缘一道光晕金镶边、覆羽羽白 / 浅金交替。
    m_body = mat_emit("body", "pearl")
    m_fe_a = mat_emit("fe_a", "feather")
    m_fe_b = mat_emit("fe_b", "gold_lt")
    m_gem = mat_emit("gem", "orange")
    m_edge = mat_emit("edge", "halo")
    parts = []
    for k in (1, -1):
        cs, ns, ts, ws, T = arm_geometry(k, R)
        outer = [_v(c, n, 0.40 * w) for c, n, w in zip(cs, ns, ws)]
        inner = [_v(c, n, -0.60 * w) for c, n, w in zip(cs, ns, ws)]
        tip = _v(T, ts[-1], 0.035 * R)
        body = outer + [tip] + list(reversed(inner))
        ob = prism_xy("arm%d" % k, [_rot(p, angle_deg) for p in body], 0.05 * R)
        ob.data.materials.append(m_body)
        parts.append(ob)
        ## 前缘亮边: 外沿往里 0.045R 的一条带, 高出臂身一点
        edge_in = [_v(o, n, -min(0.045 * R, 0.8 * w)) for o, n, w in zip(outer, ns, ws)]
        band = outer + [tip] + list(reversed(edge_in))
        ob = prism_xy("edge%d" % k, [_rot(p, angle_deg) for p in band], 0.05 * R, z=0.006)
        ob.data.materials.append(m_edge)
        parts.append(ob)
        ## 内侧一排覆羽: 圆头、彼此叠压、朝翼尖方向斜伸, 越靠翼尖越小; 羽白 / 金交替。
        ##   ★第二版是尖头 + 间隙、垂直于臂伸出 ⇒ 读成一排獠牙(整把镖像张开的兽嘴)。
        ##   现在根部埋进臂身、只露圆头那一截, 一片压一片 ⇒ 读成"一层层羽毛"。
        for i in range(7):
            j = 1 + i * 2                                       # 采样号 1,3,...,13
            b = inner[j]
            t, n = ts[j], ns[j]
            f = _norm((-n[0] * 0.55 + t[0] * 0.83, -n[1] * 0.55 + t[1] * 0.83))
            fp = (-f[1], f[0])
            L = (0.17 - 0.012 * i) * R
            W = (0.15 - 0.011 * i) * R
            root = _v(b, f, -0.06 * R)
            leaf = [_v(root, fp, -0.5 * W)]
            for s in range(9):                                  # 圆头: 半个椭圆
                ang = math.pi * s / 8.0
                leaf.append(_v(_v(b, f, L * 0.55 + L * 0.45 * math.sin(ang)), fp, -0.5 * W * math.cos(ang)))
            leaf.append(_v(root, fp, 0.5 * W))
            ob = prism_xy("fe%d_%d" % (k, i), [_rot(p, angle_deg) for p in leaf], 0.04 * R,
                          z=-0.012 - 0.002 * i)
            ob.data.materials.append(m_fe_a if i % 2 == 0 else m_fe_b)
            parts.append(ob)
    ## 肘部宝石(炽天使橙)
    ex, ey = _rot((ELBOW[0] * R, ELBOW[1] * R), angle_deg)
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.075 * R, depth=0.06 * R, location=(ex, ey, 0.03 * R))
    gem = bpy.context.active_object
    gem.data.materials.append(m_gem)
    parts.append(gem)
    for p in parts:
        add_outline(p, m_line, 0.016 * R)
    ## 翼尖流光: 每个翼尖后面一段由粗到细的弧(外沿 0.965R), 往回扫 78°。
    ##   三段由亮到暗(halo → gold_lt → orange), 见头注: 像素画没有半透明, 只能靠颜色阶梯 + 变细表达"淡去"。
    ##   旋转方向: 帧序 angle = -45°×j ⇒ 俯视顺时针 ⇒ 翼尖朝 -角度 走, 流光拖在 +角度 一侧。
    for k in (1, -1):
        a_tip = angle_deg + k * TIP_DEG + 3.0
        segs = ((0.0, 24.0, 0.13, 0.095, "halo"), (24.0, 50.0, 0.095, 0.055, "gold_lt"),
                (50.0, 78.0, 0.055, 0.015, "orange"))
        for s, (a0, a1, w0, w1, key) in enumerate(segs):
            _tapered_arc("trail%d_%d" % (k, s), a_tip + a0, a_tip + a1, 0.965 * R, w0 * R, w1 * R,
                         -0.03 * R, mat_emit("trail%d_%d" % (k, s), key))


def _flat_poly_xz(name, pts, mat):
    bm = bmesh.new()
    vs = [bm.verts.new((x, 0.0, z)) for x, z in pts]
    bm.faces.new(vs)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_hit(j):
    """命中火花(侧视公告板): 0 小亮点 → 1 最大放射 → 2–3 光芒外伸变细 → 4–5 羽毛飘开。
    ★尺寸按 64 格定: 384 渲染 / 正交 3.0 ⇒ 1 个成品像素 = 0.047。第一版光芒宽 0.05、羽毛长 0.13,
      缩到 64 格只剩不到 1 / 3 个像素(看渲染图就知道会消失), 这里全部加粗到 ≥ 3 像素并给羽毛描边。"""
    rays = [(0.0, 1.0), (45.0, 0.75), (90.0, 1.1), (135.0, 0.75), (180.0, 1.0), (225.0, 0.75), (270.0, 0.9), (315.0, 0.75)]
    grow = [0.35, 0.95, 1.20, 1.30, 1.0, 0.6][j]
    width = [0.12, 0.17, 0.13, 0.09, 0.0, 0.0][j]
    m_core = mat_emit("core", "white")
    m_ray = mat_emit("ray", "halo")
    if width > 0.0:
        for k, (ang, ln) in enumerate(rays):
            a = math.radians(ang + 10.0)
            L = ln * grow
            ca, sa = math.cos(a), math.sin(a)
            pts = [(0.0, -width), (L, 0.0), (0.0, width)]
            pts = [(x * ca - y * sa, x * sa + y * ca) for x, y in pts]
            _flat_poly_xz("ray%d" % k, pts, m_ray if k % 2 else m_core)
    ## 芯: 四角星(不是圆盘 —— 实心白圆盘 = 被否掉的「白球」)
    if j <= 2:
        r = [0.20, 0.36, 0.22][j]
        w = r * 0.28
        ## 顶点按角度排好(尖/腰交替), 放在 y=-0.05(离相机更近)挡住放射根部
        star_pts = []
        for i in range(8):
            ang = math.radians(45.0 * i)
            rr = r if i % 2 == 0 else w
            star_pts.append((rr * math.cos(ang), rr * math.sin(ang)))
        bm = bmesh.new()
        vs = [bm.verts.new((x, -0.05, z)) for x, z in star_pts]
        bm.faces.new(vs)
        me = bpy.data.meshes.new("core_star")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("core_star", me)
        ob.data.materials.append(m_core)
        bpy.context.scene.collection.objects.link(ob)
    if j >= 2:
        ## 羽毛: 长 0.34 × 宽 0.13(≈ 7 × 3 成品像素), 羽白身 + 金羽轴, 深色描边(侧视板子是平的,
        ##   描边用"放大一圈的深色底片垫在后面"做, 与 solidify 同一个意思)。
        m_fe = mat_emit("fe", "feather" if j < 5 else "gold")
        m_q = mat_emit("fq", "gold_dk")
        m_ol = mat_emit("fol", "line")
        ## ★飘散距离第一版是 0.42 + 0.26×(j−2)、下坠 0.10×(j−2): 像素化后第 5 帧最下面那片羽毛
        ##   离帧心 104% 半格、贴着格子底边被切掉(sheet_stats 量出来的)。收到 0.40 + 0.20×(j−2)、下坠 0.06。
        for k in range(5):
            a = math.radians(30.0 + 72.0 * k)
            d = 0.40 + 0.20 * (j - 2)
            x, z = d * math.cos(a), d * math.sin(a) - 0.06 * (j - 2)
            sc = 1.0 if j < 5 else 0.8
            leaf = [(-0.065, 0.0), (-0.05, 0.16), (0.0, 0.27), (0.05, 0.16), (0.065, 0.0), (0.0, -0.07)]
            ca, sa = math.cos(a + 1.2 * j), math.sin(a + 1.2 * j)

            def tr(pts, s, y):
                return [(x + (px * s) * ca - (pz * s) * sa, z + (px * s) * sa + (pz * s) * ca) for px, pz in pts], y
            pts_ol, _ = tr(leaf, sc * 1.35, 0.0)
            bm = bmesh.new()
            vs = [bm.verts.new((px, 0.02, pz)) for px, pz in pts_ol]
            bm.faces.new(vs)
            me = bpy.data.meshes.new("fol%d" % k)
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new("fol%d" % k, me)
            ob.data.materials.append(m_ol)
            bpy.context.scene.collection.objects.link(ob)
            pts_fe, _ = tr(leaf, sc, 0.0)
            _flat_poly_xz("fe%d" % k, pts_fe, m_fe)
            quill = [(-0.012, -0.05), (-0.012, 0.22), (0.012, 0.22), (0.012, -0.05)]
            pts_q, _ = tr(quill, sc, 0.0)
            bm = bmesh.new()
            vs = [bm.verts.new((px, -0.02, pz)) for px, pz in pts_q]
            bm.faces.new(vs)
            me = bpy.data.meshes.new("fq%d" % k)
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new("fq%d" % k, me)
            ob.data.materials.append(m_q)
            bpy.context.scene.collection.objects.link(ob)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    R = 1.0
    if a.only in ("", "boom"):
        os.makedirs(os.path.join(a.out, "boom"), exist_ok=True)
        for j in range(8):
            clear_scene()
            ## ★正交宽度 = 2R ⇒ 格子边缘 = 判定半径(见头注「特效 = 伤害范围」)
            setup(768, 2.0 * R, (0.0, 0.0, 10.0), (0.0, 0.0, 0.0))
            build_boomerang(-45.0 * j, R)
            bpy.context.scene.render.filepath = os.path.join(a.out, "boom", "d%d_f0.png" % j)
            bpy.ops.render.render(write_still=True)
    if a.only in ("", "hit"):
        os.makedirs(os.path.join(a.out, "hit"), exist_ok=True)
        for j in range(6):
            clear_scene()
            setup(384, 3.0, (0.0, -10.0, 0.0), (math.radians(90.0), 0.0, 0.0))
            build_hit(j)
            bpy.context.scene.render.filepath = os.path.join(a.out, "hit", "d%d_f0.png" % j)
            bpy.ops.render.render(write_still=True)
    print("[blender_seraph_boomerang] done → %s" % a.out, flush=True)


if __name__ == "__main__":
    main()
