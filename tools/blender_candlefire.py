# -*- coding: utf-8 -*-
"""blender_candlefire.py — 037 蛋糕蜡烛【燃烧阶段】的两段火, 用 Blender 体积火渲染。

跑法(无窗口):
  blender --background --python tools/blender_candlefire.py -- --out C:/tmp/cfire --px 288
  python tools/pixelize_sheet.py C:/tmp/cfire/burst  --dirs 10 --frames 1 --cell 96 --art-h 92 \
      --palette truefire -o assets/sprites/vfx/candle-fire-burst.png
  python tools/pixelize_sheet.py C:/tmp/cfire/ignite --dirs 8  --frames 1 --cell 28 --art-h 26 \
      --palette truefire -o assets/sprites/vfx/candle-ignite.png
  "<godot>" --headless --path . --import        # 换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 由来 (2026-09-13)
════════════════════════════════════════════════════════════════════════
用户第一轮:「燃烧阶段不合适, 应该是**有火炎从中间爆开**, 有命中特效,
          **像烟雾那种感觉但是火焰**」
用户第二轮:「额, **没用 blender ?** **没符合实际爆炸范围?**
          **爆炸和命中是一回事吗我问你, 为什么用相同特效?**」

三条都接了:
 ① **没用 Blender** —— 上一版是自己写 Python 逐像素画的(圆团拼轮廓)。
    项目里**早有**这条管线(`blender_truefire.py` + `pixelize_sheet.py`),
    而他第一次提 035 金币时就说过「搜搜网上 blender 有没有例子, 照着做一板板」。
    这一版走真管线: Cycles 体积火渲大图 → BOX 缩小 → 重索引到锁定调色板。
 ② **没符合实际爆炸范围** —— 判定是 `CANDLE_BURN_R` = **500 码半径**,
    而上一版把爆炸画成了 255.6 码宽。美术的**外缘半径就按 500 码定**,
    但外圈做成**散开的火舌**而不是实心球(否则整屏糊成一片橙)。
 ③ **爆炸和命中不是一回事** —— 上一版两处用了同一张表只换缩放。
    爆炸 = 蜡烛自己炸开(球状、从中心向外);
    命中 = 那个敌人**被点燃**(火焰贴着他往上舔 + 火星), 两段各渲各的。

为什么 Cycles 不是 EEVEE: 亮度要由**体积厚度**产生(照 022 真火那次的结论)。
色彩管线钉死 Standard + look=None (Blender 5.2 默认 AgX 会把饱和色压白)。
"""
import argparse
import math
import os
import sys

import bpy

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
AP = argparse.ArgumentParser()
AP.add_argument("--out", required=True)
AP.add_argument("--px", type=int, default=288)
AP.add_argument("--dens", type=float, default=0.85)
AP.add_argument("--strength", type=float, default=7.0)
AP.add_argument("--only", type=int, default=-1, help="只渲某一帧的爆炸(标定用)")
A = AP.parse_args(ARGV)

BURST_N = 10
IGNITE_N = 8


def clear_scene():
    _MBOBJ.clear()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras,
                bpy.data.lights, bpy.data.curves, bpy.data.metaballs):
        for it in list(blk):
            blk.remove(it)


def setup_render(px, ortho):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 2
    sc.cycles.volume_bounces = 1
    sc.cycles.volume_step_rate = 0.30
    sc.cycles.volume_max_steps = 1024
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    sc.world = w
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cd)
    cam.location = (0.0, 0.0, 6.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


## ★★这一段的参数**不是我拍的** —— 直接照 022 真火(`blender_truefire.py`)标定过的那套:
##   三层**嵌套壳**, 每层常量发光, 强度分别 0.45 / 3.0 / 4.6, 密度都 2.0,
##   标定目标是让三层各自落到 truefire 调色板的暗红 / 主火色 / 橙白三档上。
## ★我自己试过两条歪路, 都量出来是死的(记在这防止下次再走):
##   · 单材质 + 噪声驱动密度: 噪声经 ColorRamp 后近乎二值 ⇒ 发光色恒取最亮端, 整团一个色;
##   · 把强度调到 7~30: **Principled Volume 的 Emission 与 Density 无关**, 是体积内均匀发光,
##     强度一大整条光线直接积到 255。实测 dens/strength 扫了 6 组, 亮度跨度全是 0~8 级。
##   结论: 颜色层次靠**嵌套壳 + 低强度**, 不靠噪声也不靠调密度。
DENSITY = 2.0
OUTER_COLOR = (1.0, 0.22, 0.05); OUTER_EMIT = 0.45     # 暗红外幔
BODY_COLOR = (1.0, 0.30, 0.09); BODY_EMIT = 3.0        # 主火色
CORE_COLOR = (1.0, 0.72, 0.52); CORE_EMIT = 4.6        # 橙白芯


def volume_mat(name, density, emit_color, emit_strength):
    """纯体积发光材质: Surface 不接, 只给 Volume。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    out = nt.nodes["Material Output"]
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)   # 不散射, 只吸收
    pv.inputs["Density"].default_value = density
    pv.inputs["Emission Color"].default_value = (emit_color[0], emit_color[1], emit_color[2], 1.0)
    pv.inputs["Emission Strength"].default_value = emit_strength
    nt.links.new(pv.outputs["Volume"], out.inputs["Volume"])
    return m


_MBOBJ = {}


def ball(name, loc, r, mat, squash=1.0):
    """同一材质的球进同一个 metaball 对象 —— 同层内融合成一坨有机的团;
    三层之间**本来就不该融合**(它们是嵌套的壳, 里层透过外层显出来)。"""
    key = mat.name
    if key not in _MBOBJ:
        mb = bpy.data.metaballs.new("mb_" + key)
        mb.resolution = 0.010
        mb.render_resolution = 0.007
        ob = bpy.data.objects.new("mbo_" + key, mb)
        bpy.context.collection.objects.link(ob)
        ob.data.materials.append(mat)
        _MBOBJ[key] = ob
    ob = _MBOBJ[key]
    el = ob.data.elements.new()
    el.co = (loc[0], loc[1], loc[2])
    el.radius = r * 1.32
    el.stiffness = 2.0
    return ob


def cluster(scale, rad, brk, t, mat, lobes=9, embers=0):
    """一团火的几何: 中心一个 + 内圈 6 个 + 外圈 lobes 个火舌, 整体按 scale 缩。"""
    ball("c", (0, 0, 0), rad * 0.44 * scale, mat)
    ## ★内圈 6 个等大 ⇒ 后几帧读成一个**六边形**(并排渲出来看到的)。改 11 个且大小错开。
    for i in range(11):
        a = i * math.tau / 11.0 + t * 0.8
        d = rad * (0.30 + 0.07 * math.sin(i * 2.3 + t)) * scale
        rr = rad * (0.30 + 0.08 * math.sin(i * 1.7 - t * 0.6)) * scale
        ball("m%d" % i, (math.cos(a) * d, math.sin(a) * d * 0.94, 0.0), rr, mat)
    for i in range(lobes):
        a = i * math.tau / lobes + t * 1.4 + 0.3
        d = rad * (0.62 + 0.30 * brk) * scale
        rr = rad * (0.30 - 0.17 * brk) * (0.8 + 0.4 * ((i * 3 % 5) / 4.0)) * scale
        if rr <= 0.02:
            continue
        ball("o%d" % i, (math.cos(a) * d, math.sin(a) * d * 0.94, 0.0), rr, mat)
    for i in range(embers):
        a = i * math.tau / max(1, embers) + t * 2.1
        d = rad * (1.02 + 0.16 * t) * scale
        ball("e%d" % i, (math.cos(a) * d, math.sin(a) * d * 0.94, 0.0), 0.012, mat)   # 火星 ≈3 texel, 不是 8


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ══════════════════════════════════════════════════════════════════════
#  ① 爆炸: 从中心炸开的火球
#     外缘半径 = 画布边(游戏里按 CANDLE_BURN_R 500 码贴), 但外圈是**散开的火舌**,
#     中心才是实心白热 —— 既够到真实判定范围, 又不至于把整屏糊成一片橙。
# ══════════════════════════════════════════════════════════════════════
BURST_R = [0.16, 0.38, 0.60, 0.76, 0.88, 0.96, 1.00, 1.00, 0.98, 0.94]
BURST_CORE = [0.88, 0.80, 0.70, 0.60, 0.50, 0.41, 0.32, 0.22, 0.12, 0.04]   # 芯留久一点: 原来 f5 就没了, 中段整片平橙
BURST_BREAK = [0.0, 0.0, 0.05, 0.14, 0.26, 0.40, 0.55, 0.70, 0.82, 0.92]
N_LOBE = 9


def build_burst(k):
    t = k / float(BURST_N - 1)
    rad = BURST_R[k]
    core = BURST_CORE[k]
    brk = BURST_BREAK[k]
    m_out = volume_mat("outer", DENSITY, OUTER_COLOR, OUTER_EMIT)
    m_bod = volume_mat("body", DENSITY, BODY_COLOR, BODY_EMIT)
    m_cor = volume_mat("core", DENSITY, CORE_COLOR, CORE_EMIT)
    cluster(1.00, rad, brk, t, m_out, lobes=9, embers=7 if k >= 4 else 0)
    cluster(0.74, rad, brk, t, m_bod, lobes=7)
    if core > 0.04:
        cluster(max(0.10, core * 0.95), rad, brk * 0.3, t, m_cor, lobes=5)


# ══════════════════════════════════════════════════════════════════════
#  ② 命中: 那个敌人**被点燃** —— 火贴着他往上舔, 不是又一次爆炸
# ══════════════════════════════════════════════════════════════════════
IGNITE_H = [0.30, 0.62, 0.88, 1.00, 0.92, 0.74, 0.52, 0.30]
IGNITE_W = [0.55, 0.72, 0.80, 0.76, 0.66, 0.56, 0.44, 0.30]


def build_ignite(k):
    t = k / float(IGNITE_N - 1)
    h = IGNITE_H[k]
    w = IGNITE_W[k]
    m_out = volume_mat("outer", DENSITY, OUTER_COLOR, OUTER_EMIT)
    m_bod = volume_mat("body", DENSITY, BODY_COLOR, BODY_EMIT)
    m_cor = volume_mat("core", DENSITY, CORE_COLOR, CORE_EMIT)
    for mat, sc_all, top in ((m_out, 1.00, 1.00), (m_bod, 0.72, 0.92), (m_cor, 0.34, 0.62)):
        for i, (xo, sc) in enumerate([(-0.34, 0.62), (0.0, 1.0), (0.36, 0.55)]):
            n = 5
            for j in range(n):
                u = j / float(n - 1)
                if u > top:
                    continue
                y = -0.75 + h * 1.5 * u * sc
                rr = w * 0.30 * sc * (1.0 - 0.62 * u) * sc_all
                if rr <= 0.02:
                    continue
                wob = math.sin(u * 3.1 + t * 4.0 + i) * 0.10 * u
                ball("fl%s%d_%d" % (mat.name, i, j), (xo + wob, y, 0.0), rr, mat)
    for i in range(4):
        u = (t + i * 0.25) % 1.0
        ball("sp%d" % i, (-0.3 + 0.2 * i + math.sin(u * 6.0) * 0.08,
                          -0.2 + h * 1.6 * u, 0.0), 0.026, m_bod)


def main():
    os.makedirs(os.path.join(A.out, "burst"), exist_ok=True)
    os.makedirs(os.path.join(A.out, "ignite"), exist_ok=True)
    ks = [A.only] if A.only >= 0 else list(range(BURST_N))
    for k in ks:
        clear_scene()
        setup_render(A.px, 2.06)
        build_burst(k)
        render_to(os.path.join(A.out, "burst", "d%d_f0.png" % k))
        print("  burst f%d ok" % k)
    if A.only >= 0:
        print("DONE %s" % A.out)
        return
    for k in range(IGNITE_N):
        clear_scene()
        setup_render(max(96, A.px // 3), 2.06)
        build_ignite(k)
        render_to(os.path.join(A.out, "ignite", "d%d_f0.png" % k))
        print("  ignite f%d ok" % k)
    print("DONE %s" % A.out)


main()
