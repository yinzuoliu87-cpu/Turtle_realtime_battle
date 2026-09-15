# -*- coding: utf-8 -*-
"""blender_axe_undead.py — 096 小木斧【亡灵之斧】造物的七张演出帧表。

跑法(无窗口, 一次渲全部或挑几张):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_axe_undead.py -- --out C:/tmp/undead --sheets field,pulse,soul,drink,shatter,wake,rise
  python tools/pixelize_sheet.py C:/tmp/undead/field   --dirs 8  --frames 1 --cell 320 --art-h 320 --palette undead -o assets/sprites/vfx/eq096-undead-field.png
  python tools/pixelize_sheet.py C:/tmp/undead/pulse   --dirs 8  --frames 1 --cell 320 --art-h 320 --palette undead -o assets/sprites/vfx/eq096-undead-pulse.png
  python tools/pixelize_sheet.py C:/tmp/undead/soul    --dirs 8  --frames 1 --cell 24  --art-h 24  --palette undead -o assets/sprites/vfx/eq096-undead-soul.png
  python tools/pixelize_sheet.py C:/tmp/undead/drink   --dirs 8  --frames 1 --cell 48  --art-h 48  --palette undead -o assets/sprites/vfx/eq096-undead-drink.png
  python tools/pixelize_sheet.py C:/tmp/undead/shatter --dirs 8  --frames 1 --cell 64  --art-h 64  --palette undead -o assets/sprites/vfx/eq096-undead-shatter.png
  python tools/pixelize_sheet.py C:/tmp/undead/wake    --dirs 16 --frames 1 --cell 96  --art-h 96  --palette undead -o assets/sprites/vfx/eq096-undead-wake.png
  python tools/pixelize_sheet.py C:/tmp/undead/rise    --dirs 8  --frames 1 --cell 72  --art-h 72  --palette undead -o assets/sprites/vfx/eq096-undead-rise.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-15)
════════════════════════════════════════════════════════════════════════
用户看完九段形态视频:「6/9亡灵斧你这是在敷衍我啊，完全没按标准来」。
当时的亡灵之斧演出是 `axe_final_vfx.gd` 里三样代码现算的图形:
  一圈程序细环(环) / 一根 ImmediateMesh 绿线(吸取) / 六根 BoxMesh 小方块聚拢(复活)。
他同一段对别的形态说的话就是尺子: **演出读得出机制 · 范围 = 判定 · 每个效果有自己的画面 · 生效有反馈**。

文案(p2eq_096 effectDesc3)逐条对应一张图:
  「300 码环内敌人每秒失去 1% 最大生命值魔法伤害」 → field(常驻领域) + pulse(每跳内收一次) + soul(每个挨扣的敌人抽一缕魂)
  「每秒每有一个环内敌人回复 0.3% 最大生命值」    → drink(斧头吸到了)
  「死亡 2.5 秒后以 40% 最大生命值复活」          → shatter(崩散) + wake(倒计时) + rise(复活)

★几何口径:
  · 画布 [-1, 1], 正交相机 ortho_scale = 2, 正上方直视(贴地的图)或正前方(公告板的图)。
  · 贴地的图(field / pulse / wake): **画布边 = 判定半径** —— 游戏里 pixel_size = 2×R×WS ÷ 格宽,
    所以最外一圈亮边的外缘必须贴着 r = 1(field 的亮边外缘 0.992, 描边到 0.999)。
  · 颜色直接用 `undead` 调色板里的九个色(sRGB → 线性后喂发射着色器, Standard 视图不做色调映射),
    像素化时重索引是**逐色命中**, 不会被挤到相邻档。
  · 所有起伏都是 sin(2π·(帧/8)·整数 + 相位) ⇒ 循环帧表(field)第 8 帧严格接回第 0 帧。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402

PAL = {
    "core": (232, 255, 220),
    "bright": (160, 250, 150),
    "ghost": (90, 216, 118),
    "deep": (44, 150, 84),
    "mist": (24, 92, 58),
    "black": (12, 48, 36),
    "bone": (222, 214, 186),
    "boneshade": (150, 140, 114),
    "ash": (74, 78, 70),
}

TAU = math.tau
_MATS = {}
_Z = [0.0]


# ───────────────────────────────────────────────────────────── 场景 ──
def srgb_to_linear(c):
    v = c / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()


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
    sc.view_settings.look = 'None'
    cd = bpy.data.cameras.new("cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = 2.0
    cd.clip_start = 0.1
    cd.clip_end = 20.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = (0.0, 0.0, 5.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def mat(key):
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("m_" + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    c = PAL[key]
    em.inputs["Color"].default_value = (srgb_to_linear(c[0]), srgb_to_linear(c[1]), srgb_to_linear(c[2]), 1.0)
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    _MATS[key] = m
    return m


def clear_objects():
    for ob in list(bpy.data.objects):
        if ob.type == 'MESH':
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    _Z[0] = 0.0


def _next_z(layer):
    _Z[0] += 1e-5
    return layer * 0.01 + _Z[0]


def mesh(verts2d, faces, key, layer):
    if not verts2d:
        return None
    z = _next_z(layer)
    me = bpy.data.meshes.new("s")
    me.from_pydata([(x, y, z) for (x, y) in verts2d], [], faces)
    me.update()
    ob = bpy.data.objects.new("s", me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(mat(key))
    return ob


def poly(pts, key, layer):
    if len(pts) < 3:
        return None
    return mesh(pts, [list(range(len(pts)))], key, layer)


# ───────────────────────────────────────────────────────────── 形状 ──
def circle_pts(cx, cy, r, seg=40, ry=None, rot=0.0):
    ry = r if ry is None else ry
    out = []
    for i in range(seg):
        a = TAU * i / seg
        x, y = math.cos(a) * r, math.sin(a) * ry
        out.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return out


def disc(cx, cy, r, key, layer, seg=40, ry=None, rot=0.0):
    return poly(circle_pts(cx, cy, r, seg, ry, rot), key, layer)


def annulus(r_in, r_out, key, layer, seg=160, cx=0.0, cy=0.0):
    verts, faces = [], []
    for i in range(seg):
        a = TAU * i / seg
        verts.append((cx + math.cos(a) * r_out, cy + math.sin(a) * r_out))
        verts.append((cx + math.cos(a) * r_in, cy + math.sin(a) * r_in))
    for i in range(seg):
        j = (i + 1) % seg
        faces.append([i * 2, j * 2, j * 2 + 1, i * 2 + 1])
    return mesh(verts, faces, key, layer)


def strip(pts, widths, key, layer):
    """粗折线 → 多边形(带宽度, 两端收尖由 widths 决定)。"""
    n = len(pts)
    if n < 2:
        return None
    left, right = [], []
    for i in range(n):
        x0, y0 = pts[max(0, i - 1)]
        x1, y1 = pts[min(n - 1, i + 1)]
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / L, dx / L
        w = widths[i] * 0.5
        left.append((pts[i][0] + nx * w, pts[i][1] + ny * w))
        right.append((pts[i][0] - nx * w, pts[i][1] - ny * w))
    verts = left + right
    faces = []
    for i in range(n - 1):
        faces.append([i, i + 1, n + i + 1, n + i])
    return mesh(verts, faces, key, layer)


def tongue(bx, by, ang, length, base_w, bend, key, layer, seg=10):
    """火舌: 底边中点 (bx,by) 朝 ang 伸出 length, 底宽 base_w, 侧弯 bend。"""
    dx, dy = math.cos(ang), math.sin(ang)
    nx, ny = -dy, dx
    left, right = [], []
    for i in range(seg + 1):
        s = i / seg
        w = base_w * 0.5 * (1.0 - s) ** 0.85 * (1.0 + 0.25 * math.sin(math.pi * s))
        off = bend * math.sin(math.pi * s) * s
        cx = bx + dx * length * s + nx * off
        cy = by + dy * length * s + ny * off
        left.append((cx + nx * w, cy + ny * w))
        right.append((cx - nx * w, cy - ny * w))
    pts = left + list(reversed(right[:-1]))
    return poly(pts, key, layer)


def teardrop(cx, cy, r, ang, tail, key, layer, seg=24):
    """圆头 + 朝 ang 方向拖出的尖尾(尾长 tail)。圆头中心在 (cx,cy)。"""
    pts = []
    for i in range(seg):
        t = TAU * i / seg
        x = math.cos(t)
        y = math.sin(t)
        if x > 0.0:
            ## 朝尾巴那一侧拉长成尖
            k = x ** 2
            px = x * (r + tail * k)
            py = y * r * (1.0 - 0.85 * k)
        else:
            px, py = x * r, y * r
        pts.append((cx + px * math.cos(ang) - py * math.sin(ang), cy + px * math.sin(ang) + py * math.cos(ang)))
    return poly(pts, key, layer)


def star(cx, cy, r_out, r_in, n, rot, key, layer):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + math.pi * i / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return poly(pts, key, layer)


def rect(cx, cy, w, h, rot, key, layer):
    c, s = math.cos(rot), math.sin(rot)
    pts = []
    for (x, y) in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return poly(pts, key, layer)


def _n(i, k):
    v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)


def skull(cx, cy, s, up_ang, key, dark, layer):
    """俯视/正视都读得出的骷髅纹: 头骨圆 + 下颌 + 两个眼窝 + 鼻孔。s = 头骨半径。"""
    ux, uy = math.cos(up_ang), math.sin(up_ang)
    rx, ry = uy, -ux
    disc(cx + ux * s * 0.15, cy + uy * s * 0.15, s, key, layer, seg=20)
    rect(cx - ux * s * 0.75, cy - uy * s * 0.75, s * 1.05, s * 0.8, up_ang - math.pi / 2, key, layer)
    for side in (-1, 1):
        disc(cx + rx * side * s * 0.42 + ux * s * 0.05, cy + ry * side * s * 0.42 + uy * s * 0.05,
             s * 0.28, dark, layer + 1, seg=12)
    disc(cx - ux * s * 0.45, cy - uy * s * 0.45, s * 0.12, dark, layer + 1, seg=8)


def crossbones(cx, cy, L, w, rot, key, shade, layer):
    for d in (math.pi / 4, -math.pi / 4):
        a = rot + d
        rect(cx, cy, L, w, a, key, layer)
        for e in (-1, 1):
            ex, ey = cx + math.cos(a) * L * 0.5 * e, cy + math.sin(a) * L * 0.5 * e
            nx, ny = -math.sin(a), math.cos(a)
            disc(ex + nx * w * 0.45, ey + ny * w * 0.45, w * 0.62, key, layer, seg=10)
            disc(ex - nx * w * 0.45, ey - ny * w * 0.45, w * 0.62, shade, layer, seg=10)


def undead_axe(ox, oy, sc, key_blade, key_edge, key_bone, key_dark, layer, crack_key=None):
    """亡灵之斧的侧影(骨柄 + 锯齿绿刃), 与 eq096-axe-undead-* 本体同一个识别特征。"""
    def T(p):
        return (ox + p[0] * sc, oy + p[1] * sc)
    ## 骨柄
    poly([T(p) for p in [(-0.05, -0.66), (0.05, -0.66), (0.06, 0.58), (-0.06, 0.58)]], key_dark, layer)
    poly([T(p) for p in [(-0.035, -0.64), (0.035, -0.64), (0.04, 0.56), (-0.04, 0.56)]], key_bone, layer + 1)
    for yy in (-0.66, 0.56):
        disc(*T((0.0, yy)), 0.07 * sc, key_bone, layer + 1, seg=12)
    ## 锯齿刃
    blade = [(0.04, 0.60), (0.30, 0.74), (0.46, 0.58), (0.38, 0.50), (0.50, 0.40), (0.40, 0.32),
             (0.48, 0.22), (0.30, 0.10), (0.04, 0.18)]
    poly([T(p) for p in blade], key_dark, layer + 2)
    inner = [(0.07, 0.56), (0.28, 0.67), (0.40, 0.56), (0.33, 0.49), (0.43, 0.40), (0.35, 0.33),
             (0.41, 0.24), (0.28, 0.15), (0.07, 0.22)]
    poly([T(p) for p in inner], key_blade, layer + 3)
    edge = [(0.26, 0.64), (0.38, 0.56), (0.31, 0.49), (0.40, 0.40), (0.33, 0.33), (0.38, 0.25), (0.30, 0.19),
            (0.34, 0.26), (0.28, 0.33), (0.35, 0.40), (0.27, 0.49), (0.33, 0.56)]
    poly([T(p) for p in edge], key_edge, layer + 4)
    if crack_key:
        for (a, b) in [((0.10, 0.45), (0.30, 0.30)), ((0.16, 0.62), (0.22, 0.20)), ((0.0, 0.30), (0.0, -0.40))]:
            strip([T(a), T(b)], [0.022 * sc, 0.022 * sc], crack_key, layer + 5)


# ───────────────────────────────────────────────────────── 七张图 ──
def draw_field(f, n):
    """U1 常驻亡灵领域(贴地, 8 帧循环)。外缘亮边 = 判定圆。"""
    p = f / float(n)
    ## ① 墓雾旋臂: 5 条暗绿带从边缘往中心卷(吸), 每圈转过一个臂距 ⇒ 无缝循环
    for a in range(5):
        base = TAU * a / 5.0 - p * TAU / 5.0
        pts, ws = [], []
        for i in range(44):
            s = i / 43.0
            r = 0.90 - 0.66 * s
            ang = base + s * 2.3
            pts.append((r * math.cos(ang), r * math.sin(ang)))
            ws.append(0.060 * (1.0 - s) ** 0.7 + 0.010)
        strip(pts, ws, "mist", 0)
        strip(pts, [w * 0.32 for w in ws], "deep", 1)
    ## ② 骨纹符文环: 暗带 + 24 个骷髅 / 交叉骨交替, 每圈转过一个纹距(30°)
    annulus(0.742, 0.782, "black", 2)
    for k in range(24):
        a = TAU * k / 24.0 + p * TAU / 12.0
        cx, cy = 0.762 * math.cos(a), 0.762 * math.sin(a)
        if k % 2 == 0:
            skull(cx, cy, 0.030, a, "bone", "black", 3)
        else:
            crossbones(cx, cy, 0.064, 0.014, a, "bone", "boneshade", 3)
    ## ③ 被吸走的魂点: 沿螺线往里走, 一圈走完一趟 ⇒ 无缝
    for k in range(12):
        u = (p + k / 12.0) % 1.0
        r = 0.90 - 0.60 * u
        ang = TAU * k / 12.0 + u * 1.4
        key = "bright" if u < 0.75 else "ghost"
        teardrop(r * math.cos(ang), r * math.sin(ang), 0.020, ang + 0.35, 0.05, key, 5)
        disc(r * math.cos(ang), r * math.sin(ang), 0.009, "core", 6, seg=8)
    ## ④ 边缘冥火: 36 条往里舔的火舌(不越过判定圆) + 亮边 + 外描边
    for k in range(36):
        a = TAU * k / 36.0
        m = 1 + (k % 2)
        L = 0.075 + 0.070 * (0.5 + 0.5 * math.sin(TAU * p * m + _n(k, 3) * TAU))
        bend = 0.025 * math.sin(TAU * p + _n(k, 7) * TAU)
        bx, by = 0.965 * math.cos(a), 0.965 * math.sin(a)
        tongue(bx, by, a + math.pi, L, 0.075, bend, "ghost", 7)
        tongue(bx, by, a + math.pi, L * 0.62, 0.042, bend * 0.6, "bright", 8)
        if k % 3 == 0:
            tongue(bx, by, a + math.pi, L * 0.30, 0.020, 0.0, "core", 9)
    annulus(0.950, 0.992, "bright", 10)
    annulus(0.962, 0.980, "core", 11)
    annulus(0.992, 0.999, "black", 10)


def draw_pulse(f, n):
    """U2a 这一跳的内收波(贴地, 一次性 8 帧): 一圈亡魂从判定圆边缘收向斧头。

    ★第一版是「一圈连续细亮环 + 环外一圈小尖刺」—— 看图读成**带刺的圆环**, 不是魂在往里冲,
      而且连续细环正是被否的那个形状。⇒ 去掉连续环: 一圈**断开的墓雾弧** + 16 缕带眼窝的魂,
      尾巴朝外(= 正在往里冲), 魂头比第一版大一倍多(0.030 → 0.052)。
    """
    q = f / float(n - 1)
    r = 0.90 - 0.76 * (q ** 0.85)
    if f <= 5:
        body, inner, band = "ghost", "bright", "mist"
    elif f == 6:
        body, inner, band = "deep", "ghost", "mist"
    else:
        body, inner, band = "mist", "deep", "black"
    ## ① 断开的墓雾弧(在魂的外侧 = 魂刚冲过的地方), 每段长短不一
    wide = 0.075 * (1.0 - 0.5 * q)
    for k in range(18):
        a0 = TAU * k / 18.0 + f * math.radians(4.0) + 0.10 * _n(k, 2)
        span = math.radians(10.0 + 7.0 * _n(k, 4))
        outer, inner_pts = [], []
        for i in range(9):
            a = a0 + span * i / 8.0
            outer.append(((r + wide) * math.cos(a), (r + wide) * math.sin(a)))
            inner_pts.append(((r + 0.012) * math.cos(a), (r + 0.012) * math.sin(a)))
        poly(outer + list(reversed(inner_pts)), band, 0)
    ## ② 16 缕魂: 头在 r, 尾巴朝外; 脸朝里(两个眼窝)
    hr = 0.052 * (1.0 - 0.45 * q)
    for k in range(16):
        a = TAU * k / 16.0 + f * math.radians(4.0) + 0.08 * _n(k, 9)
        rr = r + 0.02 * (_n(k, 13) - 0.5)
        cx, cy = rr * math.cos(a), rr * math.sin(a)
        teardrop(cx, cy, hr * 1.25, a, hr * 3.4, "black", 1)
        teardrop(cx, cy, hr, a, hr * 3.0, body, 2)
        teardrop(cx, cy, hr * 0.55, a, hr * 1.2, inner, 3)
        fx, fy = -math.cos(a), -math.sin(a)
        px, py = -fy, fx
        for side in (-1, 1):
            disc(cx + fx * hr * 0.25 + px * side * hr * 0.42, cy + fy * hr * 0.25 + py * side * hr * 0.42,
                 hr * 0.22, "black", 4, seg=8)


def _soul_head(cx, cy, r, sway, f, layer, dim=False):
    body = "ghost" if not dim else "deep"
    inner = "bright" if not dim else "ghost"
    ## 尾巴: S 形往下, 相位随帧走
    pts, ws = [], []
    for i in range(14):
        s = i / 13.0
        pts.append((cx + math.sin(s * 2.6 + f * 0.9) * 0.16 * s + sway * s, cy - r * 0.4 - s * (0.95 + cy - r * 0.4 + 0.0)))
        ws.append(r * 1.25 * (1.0 - s) + 0.03)
    strip(pts, [w * 1.35 for w in ws], "black", layer)
    teardrop(cx, cy, r * 1.18, math.pi / 2, r * 1.15, "black", layer)
    strip(pts, ws, body, layer + 1)
    teardrop(cx, cy, r, math.pi / 2, r * 0.95, body, layer + 1)
    teardrop(cx, cy - r * 0.1, r * 0.62, math.pi / 2, r * 0.55, inner, layer + 2)
    for side in (-1, 1):
        disc(cx + side * r * 0.36, cy + r * 0.05, r * 0.19, "black", layer + 3, seg=10, ry=r * 0.25)
    disc(cx, cy - r * 0.42, r * 0.13, "black", layer + 3, seg=8)


def draw_soul(f, n):
    """U2b 被抽出的一缕魂(公告板, 8 帧): 0~2 从身上钻出, 3~7 拖尾飞行。"""
    if f == 0:
        disc(0.0, -0.55, 0.26, "black", 0)
        disc(0.0, -0.55, 0.19, "ghost", 1)
        disc(0.0, -0.55, 0.09, "core", 2)
        for k in range(4):
            a = TAU * k / 4.0 + 0.4
            disc(0.38 * math.cos(a), -0.55 + 0.30 * math.sin(a), 0.06, "bright", 1, seg=8)
    elif f == 1:
        _soul_head(0.0, -0.30, 0.26, 0.0, f, 0)
    elif f == 2:
        _soul_head(0.0, -0.05, 0.33, 0.04, f, 0)
    else:
        bob = 0.05 * math.sin(f * 1.6)
        _soul_head(0.0, 0.22 + bob, 0.36, 0.10 * math.sin(f * 1.1), f, 0)
        ## ★高光用亮冥火不用芯色: 24 格缩小后芯色与绿混出来落到「骨白」档, 第一版头顶冒出一颗米色像素
        disc(0.0, 0.33 + bob, 0.07, "bright", 9, seg=8)


def draw_drink(f, n):
    """U2c 斧头吸到了(公告板, 8 帧): 魂点汇入 → 一亮 → 冒回血魂火与十字。"""
    if f <= 2:
        r = [0.82, 0.52, 0.24][f]
        for k in range(5):
            a = TAU * k / 5.0 + 0.3 + f * 0.25
            cx, cy = r * math.cos(a), r * math.sin(a)
            ## ★尾巴短: 第一版尾长 0.20~0.40, 第 2 帧五条尾巴在中心汇成一颗五角星, 读不出「汇入」
            teardrop(cx, cy, 0.075, a, 0.12 + 0.03 * f, "ghost", 0)
            disc(cx, cy, 0.035, "bright", 1, seg=10)
        disc(0.0, 0.0, 0.10 + 0.05 * f, "deep", 0)
        disc(0.0, 0.0, 0.05 + 0.03 * f, "bright", 1)
    elif f == 3:
        star(0.0, 0.0, 0.62, 0.20, 8, 0.2, "ghost", 0)
        star(0.0, 0.0, 0.44, 0.14, 8, 0.2, "bright", 1)
        disc(0.0, 0.0, 0.14, "core", 2)
    else:
        k2 = f - 4
        dim = f >= 6
        for j, (x0, ph) in enumerate(((-0.34, 0.0), (0.02, 0.35), (0.36, 0.15))):
            y = -0.45 + 0.36 * k2 + ph * 0.5
            if y > 0.9:
                continue
            teardrop(x0, y, 0.10 - 0.012 * k2, math.pi / 2, 0.16, "deep" if dim else "ghost", 0)
            teardrop(x0, y - 0.01, 0.055, math.pi / 2, 0.08, "ghost" if dim else "bright", 1)
        for (x0, y0) in ((-0.12, -0.05), (0.20, 0.20)):
            y = y0 + 0.28 * k2
            if y > 0.85:
                continue
            key = "deep" if dim else "core"
            rect(x0, y, 0.20, 0.06, 0.0, key, 2)
            rect(x0, y, 0.06, 0.20, 0.0, key, 2)


def draw_shatter(f, n):
    """U3a 崩散(公告板, 8 帧): 斧头裂开 → 碎骨下落、魂火外散 → 沉到地面成一团。"""
    if f == 0:
        undead_axe(0.0, -0.05, 1.0, "ghost", "bright", "bone", "black", 0, crack_key="core")
        star(0.12, 0.30, 0.30, 0.08, 6, 0.1, "bright", 7)
        disc(0.12, 0.30, 0.07, "core", 8)
        return
    q = f / 7.0
    ## 碎骨: 7 片, 先外飞后落地
    for k in range(7):
        a = TAU * k / 7.0 + 0.5
        spd = 0.55 + 0.25 * _n(k, 11)
        x = math.cos(a) * spd * min(1.0, q * 1.8)
        y = 0.2 + math.sin(a) * spd * min(1.0, q * 1.8) * 0.6 - 1.5 * q * q
        y = max(-0.86, y)
        key = "bone" if f <= 4 else "boneshade"
        rect(x, y, 0.11, 0.045, a + q * 5.0, key, 2)
        disc(x + 0.05 * math.cos(a + q * 5.0), y + 0.05 * math.sin(a + q * 5.0), 0.032, key, 2, seg=8)
    ## 魂火: 8 缕, 1~4 往外往上散, 5~7 下沉到地面盘成一团
    ## ★第一版 8 缕等角、等速、等大、尾巴正对圆心 ⇒ 看图是一朵**八瓣花**, 读不出「魂散开」。
    ##   ⇒ 角度 / 速度 / 大小各自带噪声, 尾巴随帧摆, 头上点两个眼窝(脸朝飞出的方向)。
    for k in range(8):
        a = TAU * k / 8.0
        if f <= 4:
            a1 = a + 0.7 * (_n(k, 21) - 0.5)
            spd = 0.75 + 0.55 * _n(k, 23)
            rr = (0.16 + 0.17 * f) * spd
            x, y = math.cos(a1) * rr, 0.15 + math.sin(a1) * rr * 0.8 + 0.07 * f
            size = (0.070 + 0.030 * _n(k, 25)) * (1.0 + 0.10 * f)
            back = a1 + math.pi + 0.35 * math.sin(f * 1.3 + k)
            teardrop(x, y, size * 1.25, back, size * 2.2, "black", 3)
            teardrop(x, y, size, back, size * 1.9, "ghost", 4)
            teardrop(x, y, size * 0.5, back, size * 0.7, "bright" if f <= 3 else "ghost", 5)
            ex, ey = math.cos(a1), math.sin(a1)
            for side in (-1, 1):
                disc(x + ex * size * 0.2 - ey * side * size * 0.4, y + ey * size * 0.2 + ex * side * size * 0.4,
                     size * 0.2, "black", 6, seg=8)
        else:
            rr = 0.62 - 0.08 * (f - 5)
            aa = a + (f - 5) * 0.5
            x, y = math.cos(aa) * rr, -0.72 + math.sin(aa) * rr * 0.22
            key = "ghost" if f == 5 else ("deep" if f == 6 else "mist")
            teardrop(x, y, 0.07, aa + math.pi / 2, 0.14, key, 3)
    if f == 1:
        star(0.0, 0.2, 0.55, 0.16, 8, 0.0, "ghost", 1)
        disc(0.0, 0.2, 0.16, "core", 6)
    if f >= 5:
        disc(0.0, -0.74, 0.55 - 0.05 * (f - 5), "black", 0, ry=0.10)


def draw_wake(f, n):
    """U3b 倒计时(贴地, 16 帧按进度切): 8 支魂烛逐支点亮 + 骨灰旋涡收紧 + 魂火汇向中心骷髅。"""
    q = f / float(n - 1)
    annulus(0.93, 0.975, "black", 0, seg=96)
    annulus(0.945, 0.962, "mist" if q < 0.5 else "deep", 1, seg=96)
    ## 骨灰旋涡: 4 条臂, 半径随进度收紧、角度随进度转
    sc = 0.95 - 0.50 * q
    for a in range(4):
        base = TAU * a / 4.0 + q * math.pi
        pts, ws = [], []
        for i in range(30):
            s = i / 29.0
            r = sc * (0.80 - 0.70 * s)
            ang = base + s * 2.8
            pts.append((r * math.cos(ang), r * math.sin(ang)))
            ws.append(0.08 * (1.0 - s) + 0.015)
        strip(pts, ws, "ash", 2)
        strip(pts, [w * 0.35 for w in ws], "mist" if q < 0.6 else "deep", 3)
    ## 魂烛: 从正上方起顺时针, 每 2 帧点亮一支(第 15 帧 8 支全亮)
    lit = (f + 1) // 2
    for k in range(8):
        a = math.pi / 2 - TAU * k / 8.0
        cx, cy = 0.80 * math.cos(a), 0.80 * math.sin(a)
        disc(cx, cy, 0.075, "black", 4, seg=16)
        disc(cx, cy, 0.055, "boneshade", 5, seg=16)
        if k < lit:
            star(cx, cy, 0.13, 0.05, 6, a, "ghost", 6)
            disc(cx, cy, 0.05, "bright", 7, seg=12)
            disc(cx, cy, 0.022, "core", 8, seg=8)
        else:
            disc(cx, cy, 0.022, "black", 6, seg=8)
    ## 汇向中心的魂火
    for k in range(6):
        a = TAU * k / 6.0 + q * 2.2
        r = 0.66 * (1.0 - q) + 0.10
        key = "deep" if q < 0.35 else ("ghost" if q < 0.7 else "bright")
        teardrop(r * math.cos(a), r * math.sin(a), 0.045, a + 0.5, 0.10, key, 9)
    ## 中心骷髅: 越接近复活越亮
    sk = "boneshade" if q < 0.45 else "bone"
    skull(0.0, 0.0, 0.14, math.pi / 2, sk, "black", 10)
    if q > 0.75:
        for side in (-1, 1):
            disc(side * 0.14 * 0.42, 0.14 * 0.05, 0.03, "bright", 12, seg=8)


def draw_rise(f, n):
    """U3c 复活(公告板, 8 帧): 地面一闪起柱 → 魂火盘旋上升 → 斧头轮廓一亮 → 散。"""
    gy = -0.80
    if f <= 2:
        top = [-0.20, 0.92, 0.92][f]
        w = [0.10, 0.30, 0.26][f]
        disc(0.0, gy, 0.78, "black", 0, ry=0.20)
        disc(0.0, gy, 0.70, "ghost" if f == 0 else "deep", 1, ry=0.16)
        disc(0.0, gy, 0.44, "bright" if f == 0 else "ghost", 2, ry=0.10)
        poly([(-w, gy), (w, gy), (w * 0.55, top), (0.0, top + 0.08), (-w * 0.55, top)], "ghost", 3)
        poly([(-w * 0.45, gy), (w * 0.45, gy), (w * 0.25, top - 0.05), (-w * 0.25, top - 0.05)], "bright", 4)
        poly([(-w * 0.15, gy), (w * 0.15, gy), (0.0, top - 0.1)], "core", 5)
        for k in range(5):
            a = TAU * k / 5.0 + f * 0.9
            yy = gy + 0.25 + (0.30 + 0.20 * f) * (0.4 + k / 5.0)
            x = math.cos(a) * (0.55 - 0.10 * f)
            teardrop(x, yy, 0.06, -math.pi / 2, 0.16, "ghost", 6)
            disc(x, yy, 0.028, "core", 7, seg=8)
    elif f == 3:
        star(0.0, 0.05, 0.95, 0.22, 10, 0.1, "ghost", 0)
        star(0.0, 0.05, 0.70, 0.16, 10, 0.1, "bright", 1)
        undead_axe(-0.08, -0.02, 0.95, "core", "core", "core", "bright", 2)
    else:
        k2 = f - 4
        dim = f >= 6
        w = 0.12 - 0.03 * k2
        bot = gy + 0.45 * k2
        if w > 0.02 and bot < 0.8:
            poly([(-w, bot), (w, bot), (0.0, 0.92)], "deep" if dim else "ghost", 0)
            poly([(-w * 0.4, bot + 0.1), (w * 0.4, bot + 0.1), (0.0, 0.85)], "ghost" if dim else "bright", 1)
        for k in range(7):
            a = TAU * k / 7.0 + f
            x = math.cos(a) * (0.30 + 0.12 * k2)
            y = -0.30 + 0.28 * k2 + 0.30 * _n(k, 5)
            if y > 0.92:
                continue
            teardrop(x, y, 0.05, -math.pi / 2, 0.12, "mist" if dim else "ghost", 2)
            disc(x, y, 0.022, "deep" if dim else "core", 3, seg=8)


SHEETS = {
    "field": (8, draw_field, 1280),
    "pulse": (8, draw_pulse, 1280),
    "soul": (8, draw_soul, 192),
    "drink": (8, draw_drink, 384),
    "shatter": (8, draw_shatter, 512),
    "wake": (16, draw_wake, 768),
    "rise": (8, draw_rise, 576),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--sheets", default=",".join(SHEETS.keys()))
    a = ap.parse_args(argv)
    clear_scene()
    setup_render(512)
    done = 0
    for name in a.sheets.split(","):
        name = name.strip()
        if name not in SHEETS:
            print("[FAIL] 没有这张图: %s" % name)
            return 1
        nfr, fn, px = SHEETS[name]
        bpy.context.scene.render.resolution_x = px
        bpy.context.scene.render.resolution_y = px
        d = os.path.join(a.out, name)
        os.makedirs(d, exist_ok=True)
        for f in range(nfr):
            clear_objects()
            fn(f, nfr)
            bpy.context.scene.render.filepath = os.path.join(d, "d%d_f0.png" % f)
            bpy.ops.render.render(write_still=True)
            done += 1
        print("[blender_axe_undead] %s: %d 帧 → %s" % (name, nfr, d))
    print("[blender_axe_undead] 分母: 共渲 %d 帧" % done)
    return 0 if done > 0 else 1


if __name__ == "__main__":
    main()
