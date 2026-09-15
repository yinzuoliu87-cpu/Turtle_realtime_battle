# -*- coding: utf-8 -*-
"""blender_axe_holo.py — 096 小木斧【全息斧】造物的八张演出帧表。

跑法(无窗口, 一次渲全部或挑几张):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_axe_holo.py -- --out C:/tmp/holo --sheets field,deploy,pulse,bit,shield,boost,haste,guard
  python tools/pixelize_sheet.py C:/tmp/holo/field  --dirs 8 --frames 1 --cell 384 --art-h 384 --palette holo -o assets/sprites/vfx/eq096-holo-field.png
  python tools/pixelize_sheet.py C:/tmp/holo/deploy --dirs 8 --frames 1 --cell 384 --art-h 384 --palette holo -o assets/sprites/vfx/eq096-holo-deploy.png
  python tools/pixelize_sheet.py C:/tmp/holo/pulse  --dirs 8 --frames 1 --cell 384 --art-h 384 --palette holo -o assets/sprites/vfx/eq096-holo-pulse.png
  python tools/pixelize_sheet.py C:/tmp/holo/bit    --dirs 8 --frames 1 --cell 12  --art-h 12  --palette holo -o assets/sprites/vfx/eq096-holo-bit.png
  python tools/pixelize_sheet.py C:/tmp/holo/shield --dirs 8 --frames 1 --cell 64  --art-h 64  --palette holo -o assets/sprites/vfx/eq096-holo-shield.png
  python tools/pixelize_sheet.py C:/tmp/holo/boost  --dirs 8 --frames 1 --cell 48  --art-h 48  --palette holo -o assets/sprites/vfx/eq096-holo-boost.png
  python tools/pixelize_sheet.py C:/tmp/holo/haste  --dirs 8 --frames 1 --cell 40  --art-h 40  --palette holo -o assets/sprites/vfx/eq096-holo-haste.png
  python tools/pixelize_sheet.py C:/tmp/holo/guard  --dirs 8 --frames 1 --cell 64  --art-h 64  --palette holo -o assets/sprites/vfx/eq096-holo-guard.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-15)
════════════════════════════════════════════════════════════════════════
用户看完九段形态视频:「8/9也是，完全没达标」。当时全息斧的演出是 `axe_final_vfx.gd` 里:
  两圈程序细环 + 一根 BoxMesh 竖条当「插地的斧头」(法阵) / 把这几个网格透明度闪一下(每 0.5 秒一跳) /
  普攻给友军盾**零演出**。
他同一段对别的形态说的尺子: **演出读得出机制 · 范围 = 判定 · 每个效果有自己的画面 · 生效有反馈**。

文案(p2eq_096 effectDesc3)逐条对应:
  「普攻为血量最低的友军提供 60 护盾与 5 龟能」     → bit(数据流) + shield(护盾展开 + 头顶龟能箭头)
  「主动改为插地 4 秒(30% 减伤)」                   → guard(六角护罩); 插地本体帧在 eq096-axe-holo-plant.png
  「600 码内友军每 0.5 秒回复 100 生命与 5 龟能」   → deploy(展开/倒放收拢) + field(循环) + pulse(每跳一道波) + boost(每个被治疗友军)
  「并 +30% 攻击速度」                               → haste(脚下箭头转圈)

★几何口径与 blender_axe_undead.py 相同: 画布 [-1,1], 正交 ortho_scale = 2;
  贴地的图(field / deploy / pulse / haste)**画布边 = 判定半径**, 外圈亮线外缘 0.994。
★颜色直接用 `holo` 调色板的八个色, 像素化时逐色命中。
★线条一律按【像素化后 ≥ 1 texel】给宽度(384 格时 1 texel = 0.0052 画布单位), 否则缩小后断成点。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402

PAL = {
    "core": (238, 254, 255),
    "bright": (156, 238, 255),
    "cyan": (72, 202, 244),
    "dim": (34, 136, 196),
    "grid": (20, 78, 128),
    "black": (10, 36, 64),
    "heal": (170, 255, 190),
    "healdim": (64, 206, 120),
}

TAU = math.tau
SQ3 = math.sqrt(3.0)
_MATS = {}
_BATCH = {}


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
    _BATCH.clear()


# ── 合批: 同色同层的面攒成一个网格(六角网格一帧上千条边, 一条一个物体太慢) ──
def add_face(key, layer, pts):
    if len(pts) < 3:
        return
    _BATCH.setdefault((layer, key), []).append(pts)


def flush():
    for (layer, key), polys in sorted(_BATCH.items()):
        verts, faces = [], []
        z = layer * 0.01
        for pts in polys:
            i0 = len(verts)
            verts.extend([(x, y, z) for (x, y) in pts])
            faces.append(list(range(i0, i0 + len(pts))))
        me = bpy.data.meshes.new("b")
        me.from_pydata(verts, [], faces)
        me.update()
        ob = bpy.data.objects.new("b", me)
        bpy.context.collection.objects.link(ob)
        me.materials.append(mat(key))
    _BATCH.clear()


# ───────────────────────────────────────────────────────────── 形状 ──
def seg(p0, p1, w, key, layer):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / L * w * 0.5, dx / L * w * 0.5
    add_face(key, layer, [(p0[0] + nx, p0[1] + ny), (p1[0] + nx, p1[1] + ny),
                          (p1[0] - nx, p1[1] - ny), (p0[0] - nx, p0[1] - ny)])


def arc(r_in, r_out, a0, a1, key, layer, cx=0.0, cy=0.0, ry_k=1.0, step_deg=2.0):
    n = max(1, int(abs(a1 - a0) / math.radians(step_deg)))
    for i in range(n):
        t0 = a0 + (a1 - a0) * i / n
        t1 = a0 + (a1 - a0) * (i + 1) / n
        add_face(key, layer, [
            (cx + math.cos(t0) * r_out, cy + math.sin(t0) * r_out * ry_k),
            (cx + math.cos(t1) * r_out, cy + math.sin(t1) * r_out * ry_k),
            (cx + math.cos(t1) * r_in, cy + math.sin(t1) * r_in * ry_k),
            (cx + math.cos(t0) * r_in, cy + math.sin(t0) * r_in * ry_k)])


def ring(r_in, r_out, key, layer, cx=0.0, cy=0.0, ry_k=1.0):
    arc(r_in, r_out, 0.0, TAU, key, layer, cx, cy, ry_k)


def disc(cx, cy, r, key, layer, n=32, ry=None):
    ry = r if ry is None else ry
    add_face(key, layer, [(cx + math.cos(TAU * i / n) * r, cy + math.sin(TAU * i / n) * ry) for i in range(n)])


def hex_pts(cx, cy, s, rot=0.0):
    return [(cx + math.cos(rot + TAU * i / 6) * s, cy + math.sin(rot + TAU * i / 6) * s) for i in range(6)]


def hex_centers(s, extent, sy=1.0):
    """平顶六边形网格的中心(外接圆半径 s)。sy 把网格纵向压扁(公告板上的"罩子"要有透视感)。"""
    out = []
    nx = int(extent / (1.5 * s)) + 2
    ny = int(extent / (SQ3 * s * sy)) + 2
    for i in range(-nx, nx + 1):
        for j in range(-ny, ny + 1):
            x = 1.5 * s * i
            y = SQ3 * s * (j + 0.5 * (i % 2)) * sy
            out.append((x, y))
    return out


def hex_outline(cx, cy, s, w, key, layer, sy=1.0):
    pts = [(cx + math.cos(TAU * i / 6) * s, cy + math.sin(TAU * i / 6) * s * sy) for i in range(6)]
    for i in range(6):
        seg(pts[i], pts[(i + 1) % 6], w, key, layer)


def chevron(cx, cy, size, ang, w, key, layer):
    """「^」形箭头, 尖朝 ang。"""
    tx, ty = cx + math.cos(ang) * size * 0.5, cy + math.sin(ang) * size * 0.5
    for d in (2.4, -2.4):
        ex, ey = tx + math.cos(ang + d) * size, ty + math.sin(ang + d) * size
        seg((ex, ey), (tx, ty), w, key, layer)


def cross(cx, cy, size, w, key, layer):
    add_face(key, layer, [(cx - size, cy - w), (cx + size, cy - w), (cx + size, cy + w), (cx - size, cy + w)])
    add_face(key, layer, [(cx - w, cy - size), (cx + w, cy - size), (cx + w, cy + size), (cx - w, cy + size)])


def _n(i, k):
    v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)


# ───────────────────────────────────────────────────── 法阵(贴地) ──
T1 = 1.0 / 384.0 * 2.0          # 384 格时 1 texel 的画布宽度
HEX_S = 0.070                    # 法阵六角格外接圆半径(画布单位) ≈ 21 码


def _ground_array(R, p, lit_band=None, sweep=True, full=True):
    """法阵的全部静态结构画到半径 R 为止(展开/收拢时 R < 1)。p = 循环相位 0..1。
    lit_band = (r0, r1): 这一段半径内的六角格点亮(脉冲波扫过)。"""
    ## ① 六角格(很淡) —— 扫描线扫过的格子亮一档
    sweeps = [p * (TAU / 4.0) + TAU * k / 4.0 for k in range(4)] if sweep else []
    for (x, y) in hex_centers(HEX_S, 1.0):
        r = math.hypot(x, y)
        if r > min(R, 0.90) - HEX_S or r < 0.14:
            continue
        key = "grid"
        if lit_band and lit_band[0] <= r <= lit_band[1]:
            key = "cyan"
        elif sweeps:
            a = math.atan2(y, x)
            for sa in sweeps:
                d = (sa - a) % TAU
                if d < 0.30:
                    key = "dim"
                    break
        hex_outline(x, y, HEX_S * 0.90, T1 * 1.4, key, 0)
    ## ② 辐条: 12 条内段 + 12 条外段(错开 15°)
    for k in range(12):
        a = TAU * k / 12.0
        if R > 0.34:
            seg((0.30 * math.cos(a), 0.30 * math.sin(a)),
                (min(R, 0.60) * math.cos(a), min(R, 0.60) * math.sin(a)), T1 * 1.6, "dim", 1)
        if R > 0.66:
            b = a + TAU / 24.0
            seg((0.64 * math.cos(b), 0.64 * math.sin(b)),
                (min(R, 0.90) * math.cos(b), min(R, 0.90) * math.sin(b)), T1 * 1.6, "dim", 1)
    ## ③ 扫描线(4 条, 每圈转 90° ⇒ 无缝)
    for sa in sweeps:
        seg((0.30 * math.cos(sa), 0.30 * math.sin(sa)),
            (min(R, 0.92) * math.cos(sa), min(R, 0.92) * math.sin(sa)), T1 * 2.4, "cyan", 2)
    ## ④ 内圈: 实线 + 8 个方块字符转圈(每圈 45° ⇒ 无缝)
    ring(0.285, 0.300, "cyan", 3)
    for k in range(8):
        a = TAU * k / 8.0 + p * TAU / 8.0
        cx, cy = 0.34 * math.cos(a), 0.34 * math.sin(a)
        add_face("bright", 4, hex_pts(cx, cy, 0.022, a))
    ## ⑤ 中圈虚线(36 段, 每圈反转一个段距 10° ⇒ 无缝)
    if R > 0.64:
        for k in range(36):
            a0 = TAU * k / 36.0 - p * TAU / 36.0
            arc(0.612, 0.628, a0, a0 + math.radians(5.5), "cyan", 3)
    ## ⑥ 刻度盘: 72 格(每 5°), 每 30° 一条长刻度 —— 静止, 由 ⑦ 的追光段表达"在转"
    if R > 0.93:
        for k in range(72):
            a = TAU * k / 72.0
            r0 = 0.868 if k % 6 == 0 else 0.900
            seg((r0 * math.cos(a), r0 * math.sin(a)), (0.930 * math.cos(a), 0.930 * math.sin(a)),
                T1 * (2.2 if k % 6 == 0 else 1.4), "bright" if k % 6 == 0 else "dim", 3)
        ring(0.930, 0.944, "cyan", 4)
    ## ⑦ 外圈 = 判定边: 描边 + 亮线 + 芯线, 3 段追光(每圈 120° ⇒ 无缝)
    if full:
        rr = min(R, 0.994)
        ring(max(0.0, rr - 0.022), rr, "bright", 5)
        ring(max(0.0, rr - 0.016), rr - 0.006, "core", 6)
        ring(rr, min(0.999, rr + 0.005), "black", 5)
        for k in range(3):
            a0 = TAU * k / 3.0 + p * TAU / 3.0
            arc(max(0.0, rr - 0.050), rr - 0.022, a0, a0 + math.radians(22.0), "cyan", 5)
    ## ⑧ 插点
    ring(0.050, 0.072, "bright", 6)
    disc(0.0, 0.0, 0.028, "core", 7, n=16)


def draw_field(f, n):
    """H2b 法阵循环(贴地, 8 帧)。外圈亮线外缘 0.994 = 判定圆 600 码。"""
    _ground_array(1.0, f / float(n))


def draw_deploy(f, n):
    """H2a 展开(贴地, 8 帧): 前沿从插点推到判定圆; 游戏里倒放 = H2c 收拢。"""
    x = f / float(n - 1)
    R = 0.12 + (0.994 - 0.12) * (1.0 - (1.0 - x) ** 2)
    _ground_array(R, 0.0, sweep=False)
    ## 前沿: 比常驻外圈更粗更亮 —— "边推到哪, 阵就铺到哪"
    ring(max(0.0, R - 0.045), R - 0.018, "cyan", 8)
    for k in range(24):
        a = TAU * k / 24.0
        seg(((R - 0.07) * math.cos(a), (R - 0.07) * math.sin(a)),
            ((R - 0.01) * math.cos(a), (R - 0.01) * math.sin(a)), T1 * 2.0, "core", 9)


def draw_pulse(f, n):
    """H3a 每 0.5 秒一跳(贴地, 8 帧): 波环从插点推到判定圆, 第 6 帧碰边一亮, 第 7 帧暗。"""
    if f <= 6:
        r = 0.10 + (0.975 - 0.10) * (f / 6.0)
        ring(max(0.0, r - 0.090), r - 0.030, "dim", 0)
        ring(max(0.0, r - 0.030), r - 0.010, "bright", 1)
        ring(max(0.0, r - 0.010), r, "core", 2)
        for (x, y) in hex_centers(HEX_S, 1.0):
            rr = math.hypot(x, y)
            if r - 0.16 <= rr <= r - 0.02 and rr < 0.92:
                hex_outline(x, y, HEX_S * 0.90, T1 * 1.8, "cyan", 3)
        if f == 6:
            ring(0.930, 0.999, "bright", 4)
            ring(0.955, 0.985, "core", 5)
            for k in range(36):
                a = TAU * k / 36.0
                seg((0.90 * math.cos(a), 0.90 * math.sin(a)), (0.999 * math.cos(a), 0.999 * math.sin(a)),
                    T1 * 2.0, "core", 6)
    else:
        ## ★第 7 帧不许是一圈光秃秃的细环(第一版就是, 那正是被否的形状):
        ##   留在判定边上的是**碎成段的边光 + 零散的六角格余光**
        for (x, y) in hex_centers(HEX_S, 1.0):
            rr = math.hypot(x, y)
            if 0.80 <= rr <= 0.92 and _n(int(x * 97), int(y * 89)) < 0.55:
                hex_outline(x, y, HEX_S * 0.90, T1 * 1.6, "dim", 0)
        for k in range(24):
            a0 = TAU * k / 24.0
            arc(0.955, 0.994, a0, a0 + math.radians(7.0), "dim", 1)


# ─────────────────────────────────────────────────── 公告板 / 小件 ──
def draw_bit(f, n):
    """H1a 数据块(公告板 12 格, 8 帧循环): 一块实心全息方块绕竖轴转 90°(方块对称 ⇒ 无缝)。"""
    yaw = (f / float(n)) * (math.pi / 2.0) + math.radians(20.0)
    tilt = math.radians(28.0)
    s = 0.46
    V = []
    for (x, y, z) in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]:
        xr = x * math.cos(yaw) - z * math.sin(yaw)
        zr = x * math.sin(yaw) + z * math.cos(yaw)
        yr = y * math.cos(tilt) - zr * math.sin(tilt)
        zt = y * math.sin(tilt) + zr * math.cos(tilt)
        V.append((xr * s, yr * s, zt))
    faces = [((0, 1, 2, 3), "dim"), ((4, 5, 6, 7), "dim"), ((0, 1, 5, 4), "cyan"),
             ((2, 3, 7, 6), "core"), ((1, 2, 6, 5), "bright"), ((0, 3, 7, 4), "cyan")]
    ## 描边: 整块外轮廓先铺一层暗色(略放大)
    cx = sum(v[0] for v in V) / 8.0
    cy = sum(v[1] for v in V) / 8.0
    for (idx, key) in faces:
        pts = [V[i] for i in idx]
        add_face("black", 0, [(cx + (p[0] - cx) * 1.28, cy + (p[1] - cy) * 1.28) for p in pts])
    order = sorted(faces, key=lambda fk: sum(V[i][2] for i in fk[0]))
    for li, (idx, key) in enumerate(order):
        add_face(key, 1 + li, [(V[i][0], V[i][1]) for i in idx])


def _dome_inside(x, y, base_y, rx, ry):
    if y < base_y:
        return False
    return (x / rx) ** 2 + ((y - base_y) / ry) ** 2 <= 1.0


def draw_shield(f, n):
    """H1b 护盾展开 + 龟能入账(公告板 64 格, 8 帧)。"""
    ## ★罩顶 0.40(第一版 0.60): 第一版龟能箭头叠在罩顶上, 看图读成「钟罩上的提手」, 不是往上升的箭头
    base_y, rx, ry = -0.62, 0.80, 1.02
    T = 2.0 / 64.0
    scan = [-0.62, -0.36, -0.08, 0.20, 0.40, 0.40, 0.40, 0.40][f]
    if f <= 4:
        cell_key, out_key = "cyan", "bright"
    elif f == 5:
        cell_key, out_key = "dim", "cyan"
    elif f == 6:
        cell_key, out_key = "grid", "dim"
    else:
        cell_key, out_key = None, "grid"
    ## 地面基圈
    ring(0.70, 0.80, out_key if f >= 1 else "core", 0, cy=base_y, ry_k=0.24)
    ## 六角格(纵向压扁, 有穹顶的透视感)
    if cell_key:
        for (x, y) in hex_centers(0.13, 1.0, sy=0.80):
            yy = y + base_y + 0.40
            if not _dome_inside(x, yy, base_y, rx - 0.10, ry - 0.12):
                continue
            if yy > scan + (0.0 if f <= 3 else 9.0):
                continue
            if f == 6 and _n(int(x * 100), int(yy * 100)) < 0.5:
                continue
            hex_outline(x, yy, 0.13 * 0.86, T * 1.2, cell_key, 1, sy=0.80)
    ## 穹顶轮廓
    top = min(scan, base_y + ry) if f <= 3 else base_y + ry
    steps = 40
    for side in (-1, 1):
        prev = None
        for i in range(steps + 1):
            t = i / float(steps) * (math.pi / 2)
            x = side * rx * math.cos(t)
            y = base_y + ry * math.sin(t)
            if y > top:
                break
            if prev:
                seg(prev, (x, y), T * 1.9, out_key, 2)
            prev = (x, y)
    ## 扫描线
    if f <= 3:
        half = rx * math.sqrt(max(0.0, 1.0 - ((scan - base_y) / ry) ** 2))
        seg((-half, scan), (half, scan), T * 2.2, "core", 3)
    if f == 4:
        disc(0.0, base_y + ry * 0.55, 0.10, "core", 3, n=16)
    ## 龟能箭头(+5): 第 5 帧起从罩顶往上升
    if f >= 5:
        y0 = [0.66, 0.76, 0.86][f - 5]
        key = ["bright", "cyan", "dim"][f - 5]
        chevron(0.0, y0, 0.16, math.pi / 2, T * 2.2, key, 4)
        chevron(0.0, y0 - 0.16, 0.16, math.pi / 2, T * 2.2, key, 4)


def draw_boost(f, n):
    """H3b 治疗/龟能反馈(公告板 48 格, 8 帧): 绿十字(+血)与青箭头(+龟能)从脚下升到头顶。"""
    T = 2.0 / 48.0
    dim = f >= 6
    if f == 0:
        ## 脚下一圈治疗光(第一版两圈叠在第一个十字上, 看图读成一只青色眼睛)
        ring(0.46, 0.58, "healdim", 0, cy=-0.88, ry_k=0.20)
    items = [(-0.42, 0.00, "x"), (0.40, 0.12, "x"), (0.02, 0.30, "x"), (-0.12, 0.50, "v"), (0.22, 0.62, "v")]
    for (x0, lag, kind) in items:
        y = -0.78 + 0.28 * f - lag
        if y < -0.85 or y > 0.90:
            continue
        if kind == "x":
            s = 0.15
            ## ★暗帧描边换近黑蓝: 第一版描边与填充同为治疗绿, 第 6~7 帧十字糊成一块绿方块
            cross(x0, y, s + T * 0.9, 0.055 + T * 0.9, "black" if dim else "healdim", 2)
            cross(x0, y, s, 0.055, "healdim" if dim else "heal", 3)
        else:
            chevron(x0, y, 0.15, math.pi / 2, T * 2.4, "black", 2)
            chevron(x0, y, 0.15, math.pi / 2, T * 1.3, "dim" if dim else "bright", 3)


def draw_haste(f, n):
    """H3c 加速标记(贴地 40 格, 8 帧循环): 一圈 6 个箭头顺时针快转(每圈转一个箭头距 60° ⇒ 无缝)。"""
    T = 2.0 / 40.0
    ring(0.88, 0.95, "dim", 0)
    ring(0.50, 0.55, "grid", 0)
    for k in range(6):
        a = -TAU * k / 6.0 - (f / float(n)) * (TAU / 6.0)
        r = 0.72
        cx, cy = r * math.cos(a), r * math.sin(a)
        tang = a - math.pi / 2
        bx, by = r * math.cos(a + 0.28), r * math.sin(a + 0.28)
        chevron(bx, by, 0.20, tang, T * 1.2, "grid", 1)
        chevron(cx, cy, 0.24, tang, T * 2.4, "black", 2)
        chevron(cx, cy, 0.24, tang, T * 1.3, "bright", 3)


def draw_guard(f, n):
    """H2d 插地减伤护罩(公告板 64 格, 8 帧循环): 六角格护罩 + 扫描带自下而上走一趟。"""
    T = 2.0 / 64.0
    rx, ry = 0.78, 0.92
    band = -0.95 + 1.90 * (f / float(n))
    for (x, y) in hex_centers(0.15, 1.0, sy=0.85):
        if (x / (rx - 0.08)) ** 2 + (y / (ry - 0.08)) ** 2 > 1.0:
            continue
        key = "grid"
        if abs(y - band) < 0.14:
            key = "bright" if abs(y - band) < 0.06 else "cyan"
        hex_outline(x, y, 0.15 * 0.84, T * 1.2, key, 1, sy=0.85)
    ## 三块"装甲片"交替亮(每 2 帧换一块)
    lit = (f // 2) % 3
    for k, (x, y) in enumerate([(-0.36, 0.26), (0.36, 0.26), (0.0, -0.40)]):
        if k == lit:
            add_face("dim", 0, hex_pts(x, y * 0.85 / 0.85, 0.15 * 0.80))
    ## 外轮廓双线
    steps = 72
    prev = None
    for i in range(steps + 1):
        t = TAU * i / steps
        p = (rx * math.cos(t), ry * math.sin(t))
        if prev:
            seg(prev, p, T * 2.0, "bright", 3)
        prev = p
    prev = None
    for i in range(steps + 1):
        t = TAU * i / steps
        p = ((rx + 0.07) * math.cos(t), (ry + 0.07) * math.sin(t))
        if prev:
            seg(prev, p, T * 1.2, "dim", 2)
        prev = p


SHEETS = {
    "field": (8, draw_field, 1536),
    "deploy": (8, draw_deploy, 1536),
    "pulse": (8, draw_pulse, 1536),
    "bit": (8, draw_bit, 96),
    "shield": (8, draw_shield, 512),
    "boost": (8, draw_boost, 384),
    "haste": (8, draw_haste, 320),
    "guard": (8, draw_guard, 512),
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
            flush()
            bpy.context.scene.render.filepath = os.path.join(d, "d%d_f0.png" % f)
            bpy.ops.render.render(write_still=True)
            done += 1
        print("[blender_axe_holo] %s: %d 帧 → %s" % (name, nfr, d))
    print("[blender_axe_holo] 分母: 共渲 %d 帧" % done)
    return 0 if done > 0 else 1


if __name__ == "__main__":
    main()
