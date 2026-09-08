# -*- coding: utf-8 -*-
"""blender_broadsword.py — 007 锈蚀阔剑的两件素材: 阔剑本体 + 剑气墙。

跑法(无窗口):
  blender --background --python tools/blender_broadsword.py -- --out C:/tmp/bs --mode sword
  blender --background --python tools/blender_broadsword.py -- --out C:/tmp/bw --mode wall --dirs 8

★★由来(2026-09-08 实拍 007): 三个毛病和 001/003/004 完全同族, 外加一个新的 ——
  ① 起手那把"高举的阔剑"是 `VfxTex._make_vblade_texture()` **程序生成**的,
     上屏是贴在龟身上的一道**白划痕**, 完全看不出是剑;
  ② 剑气墙是 `VfxTex._make_bladewall_texture()` 程序生成 + `TEXTURE_FILTER_LINEAR`,
     上屏是一道**模糊的橙褐弧**, 像喷枪抹出来的;
  ③ 两者都靠 `rotation.z` / `camera_basis × roll` **自由旋转贴图**(像素风禁忌);
  ④ **新的一条: 名实不符** —— 它叫「锈蚀阔剑」, 而整套演出是炽焰赤金
     (`_make_bladewall_texture(1.0, 0.36, 0.18)`)。名字说锈, 画面说火。
     ⇒ 全部改走 tools/pixelize_sheet.py 新加的 `rust` 板: 暗红褐为主,
       高光是**被磨出来的裸铁白**(锈刃只有刃缘还亮), 不是火光。

★与 006 那把剑必须**看得出是两把不同的剑**(素材不复用铁律的另一面: 也不许两件长一样):
  006 = 细长骑士剑(刃宽 0.10 · 尖收成针);
  007 = 阔剑(刃宽 0.26 = 2.6 倍 · 斜切尖 · 刃缘带缺口 · 锈斑)。

★渲【正面正交】: 游戏里两件都是 `BILLBOARD_ENABLED` 立着的, 透视交给战斗相机。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402


## ── 阔剑尺寸(相对画布 1.0, 画幅 -0.5..0.5) ──
BLADE_TIP_Y = 0.450
GUARD_Y = -0.080
GUARD_BOT_Y = -0.132
GRIP_BOT_Y = -0.352
POMMEL_BOT_Y = -0.450
## ★★宽长比是**阔剑读不读得出来**的全部: 0.26 那版刃身 12.5x21 像素 = 1.7:1,
##   上屏读成一根棒冰不是剑。0.20 ⇒ 刃身 9.6x25 = 2.6:1, 仍明显阔于 006 的 6px 刃, 但还是剑。
BLADE_W = 0.185
## 斜切尖: 两条刃缘各自收敛的长度(占刃长)。差得越多尖越斜。
BLADE_TIP_L = 0.34       # 左缘收得慢
BLADE_TIP_R = 0.14       # 右缘收得快 ⇒ 尖偏右
GUARD_W = 0.400
GRIP_W = 0.060
POMMEL_W = 0.130
SEG = 96

## 刃缘缺口(位置 t, 深度占半宽, 半宽度)。★阔剑的性格全在这几个豁口上。
## ★★三个等深等距的缺口实拍读成**锯齿/面包刀**。磕出来的豁口是不规则的:
##   一个大的 + 一个小的, 位置不匀, 深度差一倍。规律性 = 人造 = 锯。
NICKS = [(0.29, 0.66, 0.075), (0.64, 0.30, 0.045)]

## 金属剖面(u 横跨宽度): 光从左上 ⇒ 磨亮的刃缘偏左。
## ★锈刃与新刃的差别在**亮的那一条有多窄**: 锈刃只有刃缘还亮, 刃身大片是锈。
## ★★色带数必须按【缩完还剩几像素】定, 不是按好看定:
##   刃身缩到 48px 只有 9~10 像素宽。第一版摆了 7 档 ⇒ 每档 1.4 像素,
##   再叠上锈斑摆动, 实拍读成**木纹棒冰**。5 档 ⇒ 每档 2 像素, 才立得住。
RAMP = [
    (0.00, ( 48,  28,  22)),   # 亮度  31  左描边(1px)
    (0.10, (238, 232, 220)),   # 亮度 233  磨亮的刃缘(2px·锈刃只剩这一条还亮)
    (0.30, (176, 116,  62)),   # 亮度 128  锈橙(4px·主色)
    (0.70, (132,  74,  40)),   # 亮度  88  深锈(2px)
    (0.90, ( 48,  28,  22)),   # 亮度  31  右描边(1px)
]
GRIP_RAMP = [
    (0.00, ( 48,  28,  22)),
    (0.20, (132,  74,  40)),
    (0.50, ( 88,  48,  30)),
    (0.82, ( 48,  28,  22)),
]

## ── 剑气墙: 一道【立起来的宽刃气墙】, 不是弧不是球 ──
## ★实拍里旧的读作"模糊的橙褐弧"。要读成"墙", 靠的是:
##   ① 竖直方向是**一条有厚度的带**(上下收尖, 中段满高)
##   ② 前缘有一条**极亮的硬边**(那是刃), 往后迅速衰成暗锈(那是被带起来的气)
##   ③ 后缘做成**参差的齿**, 不是平滑收口 —— 平滑收口读作"喷枪"
WALL_H = 0.88            # 墙高(相对画幅)
WALL_W = 0.30            # 墙厚(前缘到后缘)
WALL_SEG = 96
WALL_RAMP = [
    (0.00, (238, 232, 220)),   # 亮度 233  前刃(最细·最亮)
    (0.10, (206, 186, 158)),   # 亮度 190
    (0.24, (176, 116,  62)),   # 亮度 128  锈橙
    (0.52, (132,  74,  40)),   # 亮度  88
    (0.78, ( 88,  48,  30)),   # 亮度  58
    (0.92, ( 48,  28,  22)),   # 亮度  31  尾
]



## ── 地面刮痕: 剑气墙擦地拖出来的一道沟 ──
## ★★由来: 旧版沿途撒的是 `_splash_ring_bold` 的**一串橙色圆环** ——
##   正是我记过的通病「无含义圆环与白球」。一道剑气扫过去, 地上该是**被犁开的一条沟**,
##   不是一串圈。圈说明不了任何事, 沟说明"这里被扫过了"。
## ★与 006 地缝的区别(不许两件长一样): 006 是**裂开**(暗心 + 上缘亮棱, 看进地下);
##   007 是**刮痕**(浅、擦出来的铁锈屑、没有深度), 色也不同(crack 板 vs rust 板)。
SCRAPE_LEN = 0.90
SCRAPE_W = 0.16
SCRAPE_SEG = 96
SCRAPE_RAMP = [
    (0.00, ( 88,  48,  30)),   # 亮度  58  下缘
    (0.34, (132,  74,  40)),   # 亮度  88  沟底(浅·不像地缝那么黑)
    (0.70, (176, 116,  62)),   # 亮度 128  锈屑
    (0.88, (206, 186, 158)),   # 亮度 190  上缘被擦亮的一条
]


def build_scrape(mat, grow, phase):
    """一道刮痕。grow ∈ (0,1] 控制长度/宽度 —— 逐帧展开。
    UV 的 v: 0=下缘 1=上缘(亮), 与 006 地缝同一套"只亮一侧"的道理。"""
    length = SCRAPE_LEN * (0.45 + 0.55 * grow)
    width = SCRAPE_W * (0.35 + 0.65 * grow)
    verts, faces, uvs = [], [], []
    for i in range(SCRAPE_SEG + 1):
        t = i / float(SCRAPE_SEG)
        x = (t - 0.5) * length
        env = math.sin(math.pi * t) ** 0.5
        ## 断续: 刮痕不是连续一条, 中间会断 —— 连续一条读作"画上去的线"
        gap = 0.30 + 0.70 * abs(math.sin(math.tau * 4.0 * t + phase))
        hw = max((width * 0.5) * env * gap, width * 0.02)
        cy = width * 0.10 * env * math.sin(math.tau * 2.0 * t + phase * 1.3)
        verts.append((x, cy + hw, 0.0))
        verts.append((x, cy, 0.0))
        verts.append((x, cy - hw, 0.0))
        uvs.append((t, 1.0)); uvs.append((t, 0.5)); uvs.append((t, 0.0))
    for i in range(SCRAPE_SEG):
        r0, r1 = i * 3, (i + 1) * 3
        faces.append((r0 + 0, r0 + 1, r1 + 1, r1 + 0))
        faces.append((r0 + 1, r0 + 2, r1 + 2, r1 + 1))
    me = bpy.data.meshes.new("scrape")
    me.from_pydata(verts, [], faces)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    ob = bpy.data.objects.new("scrape", me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob

def srgb_to_linear(c):
    """★Blender 颜色输入吃线性色, 调色板是 sRGB ⇒ 直接喂会整体提亮一整档
    (实测见 tools/blender_slash.py 头注)。"""
    v = c / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_strip(name, y_top, y_bot, hw_left, hw_right, seg=SEG, uv_along=False):
    """竖着的带状体, 左右半宽可以不同(斜切尖 / 单边缺口都靠这个)。
    UV: u 横跨宽度(0=左缘 1=右缘); uv_along=True 时 v 也跟着长度走(给锈斑用)。"""
    verts, faces, uvs = [], [], []
    for i in range(seg + 1):
        t = i / float(seg)                  # 0 = 顶
        y = y_top + (y_bot - y_top) * t
        wl = max(hw_left(t), 1e-5)
        wr = max(hw_right(t), 1e-5)
        verts.append((-wl, y, 0.0))
        verts.append((wr, y, 0.0))
        uvs.append((0.0, t if uv_along else 0.0))
        uvs.append((1.0, t if uv_along else 0.0))
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


def build_material(name, ramp_def, rust_freq=0.0):
    """u 横跨宽度做金属剖面。rust_freq>0 时把剖面沿长度**推来推去**做锈斑 ——
    ★锈斑不能用噪声贴图: 缩到 32~48 像素后噪声全被平均掉只剩糊。
      把剖面本身沿长度低频摆动, 缩小后仍然是"这一段亮、那一段锈"的块状结构。"""
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
    src = sep.outputs["X"]
    if rust_freq > 0.0:
        sw = nt.nodes.new("ShaderNodeMath"); sw.operation = 'MULTIPLY'
        sw.inputs[1].default_value = math.tau * rust_freq
        nt.links.new(sep.outputs["Y"], sw.inputs[0])
        sn = nt.nodes.new("ShaderNodeMath"); sn.operation = 'SINE'
        nt.links.new(sw.outputs[0], sn.inputs[0])
        am = nt.nodes.new("ShaderNodeMath"); am.operation = 'MULTIPLY'
        am.inputs[1].default_value = 0.05
        nt.links.new(sn.outputs[0], am.inputs[0])
        ad = nt.nodes.new("ShaderNodeMath"); ad.operation = 'ADD'
        nt.links.new(sep.outputs["X"], ad.inputs[0])
        nt.links.new(am.outputs[0], ad.inputs[1])
        src = ad.outputs[0]
    nt.links.new(src, ramp.inputs["Fac"])
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
    cd.ortho_scale = 1.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def _nick(t):
    """刃缘缺口: 落在某个 NICK 附近就把半宽掐掉一截。"""
    cut = 0.0
    for pos, depth, half in NICKS:
        d = abs(t - pos)
        if d < half:
            cut = max(cut, depth * (1.0 - d / half))
    return cut


def build_sword(steel, leather):
    """一把阔剑。刃宽是 006 那把的 2.6 倍, 尖是斜切的, 右刃缘带三个缺口。"""
    ## ★★阔剑的两条刃缘【大部分是平行的】, 只有尖那一小段收。
    ##   第一版让左缘的收敛跨了刃长 63% ⇒ 整片刃身是个三角形, 读成矛头/胡萝卜。
    ##   ⇒ 两条缘各自只在**自己那一段**收: 右缘 14%、左缘 34% ⇒ 尖明显偏右 = 斜切尖,
    ##     而 t>0.34 以下两缘都是满宽 = 平行刃身。
    def edge(t, frac):
        return (BLADE_W * 0.5) * (0.92 + 0.08 * t) * min(1.0, t / frac)

    def blade_l(t):
        return edge(t, BLADE_TIP_L)

    def blade_r(t):
        return edge(t, BLADE_TIP_R) * (1.0 - _nick(t))

    parts = [
        (build_strip("blade", BLADE_TIP_Y, GUARD_Y, blade_l, blade_r, uv_along=True), steel),
        (build_strip("guard", GUARD_Y, GUARD_BOT_Y,
                     lambda t: (GUARD_W * 0.5) * (0.66 + 0.34 * math.sin(math.pi * min(1.0, 0.2 + t * 0.8))),
                     lambda t: (GUARD_W * 0.5) * (0.66 + 0.34 * math.sin(math.pi * min(1.0, 0.2 + t * 0.8))),
                     uv_along=True), steel),
        (build_strip("grip", GUARD_BOT_Y, GRIP_BOT_Y,
                     lambda t: GRIP_W * 0.5, lambda t: GRIP_W * 0.5), leather),
        (build_strip("pommel", GRIP_BOT_Y, POMMEL_BOT_Y,
                     lambda t: (POMMEL_W * 0.5) * math.sin(math.pi * t) ** 0.6,
                     lambda t: (POMMEL_W * 0.5) * math.sin(math.pi * t) ** 0.6,
                     uv_along=True), steel),
    ]
    return parts


def build_wall(mat, phase):
    """剑气墙: 竖直一道带。前缘(u=0)是刃, 后缘参差成齿。
    ★整体在画幅里【横躺】—— 因为它是"沿行进方向推过去的一堵墙", 竖直方向是墙高。
      所以这里 y 跨墙高、x 跨墙厚, 与剑同一套 build_strip。"""
    def env(t):
        ## 上下收尖但中段满高: 上下各 18% 是收口
        return math.sin(math.pi * min(1.0, max(0.0, t))) ** 0.35

    def front(t):
        return (WALL_W * 0.5) * env(t) * 0.42          # 前缘: 光滑(那是刃)

    def back(t):
        ## 后缘参差。★齿的频率按【缩完每颗几像素】定: 墙高缩到 42 像素, 3 个周期 = 每颗 14 像素, 实拍读成梳子/毛毛虫。5.5 + 13 两层 ⇒ 每颗 7 像素再叠碎 3 像素 = 参差的气。
        j = (0.66 + 0.34 * abs(math.sin(math.tau * 5.5 * t + phase))) \
            * (0.82 + 0.18 * math.sin(math.tau * 13.0 * t + phase * 1.7))
        return (WALL_W * 0.5) * env(t) * 1.58 * j

    ob = build_strip("wall", WALL_H * 0.5, -WALL_H * 0.5, front, back, seg=WALL_SEG)
    ob.data.materials.append(mat)
    return ob


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=512)
    ap.add_argument("--mode", choices=["sword", "wall", "icon", "scrape"], default="sword")
    ap.add_argument("--dirs", type=int, default=1)
    ap.add_argument("--frames", type=int, default=1)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    ## ★★锈斑摆动**整个去掉**(0.16 → 0.05 → 0)。两版都读成木纹:
    ##   刃身只有 9 像素宽, 任何沿长度的连续摆动缩完都是"竖条纹" = 木头。
    ##   锈的性格改由【色相 + 缺口】给 —— 前者是 rust 板本身, 后者是刃缘那三个豁口。
    ##   ★通用: 尺寸小到某个程度, "加细节"只会变噪点; 性格得靠**轮廓**给, 不是靠纹理。
    steel = build_material("rustblade", RAMP)
    leather = build_material("grip", GRIP_RAMP)
    wallmat = build_material("wall", WALL_RAMP)

    if a.mode == "scrape":
        scrapemat = build_material("scrape", SCRAPE_RAMP)
        nf = max(1, a.frames)
        for f in range(nf):
            ob = build_scrape(scrapemat, grow=(f + 1) / float(nf), phase=1.9)
            bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % f)
            bpy.ops.render.render(write_still=True)
            bpy.data.objects.remove(ob, do_unlink=True)
        print("[blender_broadsword] 刮痕 渲出 %d 帧 → %s" % (nf, a.out))
    elif a.mode == "icon":
        ## 图标: 整把剑斜过来填满方格。★竖着放的话 32x32 里刃只有 6 像素宽、两侧全是空,
        ##   斜 35° 才占满对角线。**旋转在 Blender 里做**(渲染时转), 不是把像素图转过去。
        parts = build_sword(steel, leather)
        for ob, _m in parts:
            ob.rotation_euler = (0.0, 0.0, math.radians(-35.0))
        for ob, mat in parts:
            ob.data.materials.append(mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d0_f0.png")
        bpy.ops.render.render(write_still=True)
        print("[blender_broadsword] 图标 渲出 1 帧 → %s" % a.out)
    elif a.mode == "sword":
        n = max(1, a.dirs)
        for k in range(n):
            parts = build_sword(steel, leather)
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
        print("[blender_broadsword] 阔剑 渲出 %d 帧 → %s" % (n, a.out))
    else:
        ## 方向表 × 动画帧: 后缘的参差每帧换相位 ⇒ 气墙在"翻涌"而不是一张死图
        nd = max(1, a.dirs)
        nf = max(1, a.frames)
        for k in range(nd):
            for f in range(nf):
                ob = build_wall(wallmat, phase=1.3 + 2.1 * f)
                if nd > 1:
                    ## 墙面朝行进方向 ⇒ 第 k 格的行进方向是屏幕角 k*360/nd。
                    ## ★★必须 +π: 亮刃缘建在局部 -x 侧(WALL_RAMP 的 u=0), 只转 θ 的话 -x 指向 θ+180° ⇒ 亮缘朝后。逐格量出八格一致偏 175° 才发现(量法: 亮缘像素质心相对整体质心的方向, 拿 d0 已知朝右自证)。
                    ob.rotation_euler = (0.0, 0.0, math.tau * k / float(nd) + math.pi)
                bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f%d.png" % (k, f))
                bpy.ops.render.render(write_still=True)
                bpy.data.objects.remove(ob, do_unlink=True)
        print("[blender_broadsword] 剑气墙 渲出 %d 向 × %d 帧 → %s" % (nd, nf, a.out))


if __name__ == "__main__":
    main()
