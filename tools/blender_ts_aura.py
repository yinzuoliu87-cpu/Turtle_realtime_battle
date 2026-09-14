# -*- coding: utf-8 -*-
"""blender_ts_aura.py — 059 沙漏【蓄力段】携带者身上的金色战斗气(8 帧循环)。

跑法(无窗口):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_ts_aura.py -- --out C:/tmp/tsaura --frames 8 --px 288
  python tools/pixelize_sheet.py C:/tmp/tsaura --dirs 8 --frames 1 --cell 72 --art-h 72 --palette tsaura -o assets/sprites/vfx/ts-aura.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-15)
════════════════════════════════════════════════════════════════════════
用户 2026-09-14:「**直接是人物冒战斗特效**，能量波几道？从人物中间爆开，中间是什么颜色特效，
  然后能量波再从全世界收回人物中心…」—— 第一步就是人物身上冒战斗特效。
而我前四版的蓄力段是 10 颗 `_make_fire_glow_tex` 软光球螺旋汇入 + 脚下一道 `_skill_ring` 金环:
  两个都是点名过的禁区形状(无含义白球/圆环), **参考里也根本没有**。

★参考(他点的「11 秒到 15 秒」往前 1 秒, 蓄力正好是这一段 —— TS_CHARGE = 1.0):
  clip.mp4 10.00~10.80 秒(#000~#024, 30fps 每帧看过):
  DIO 喊「The World!」, **整个人被金色火焰包着**, 火苗一直往上窜; 火舌之间是黑色剪影缝。
  10.83~10.97 秒(#025~#029)胸口亮起白金光点再爆开 —— 那是 `tools/bake_ts_core.py`, 不在这张图里。

★量出来的(脚本在 scratchpad, 数字抄在这):
  火像素 46 万个(色相 20~60°、饱和 > 0.35), k-means 6 档:
    (251,232,133) 17.2% · (238,196,93) 17.7% · (208,158,64) 18.6% ·
    (168,119,43) 15.9% · (131,85,26) 15.8% · (84,55,19) 14.9%
  ⇒ **六档几乎等占比**: 金火是整片明暗交错, 不是一小团白芯(022 真火是芯亮边暗、亮档只占一小片)。
  黑剪影缝占画面 8.1%。
  ⇒ 调色板 `tsaura` 就是这 6 档; 烤完回量每档占比, 任何一档 < 5% 或 > 40% 都算没烤对。

★形状(定稿·第九轮): **一排从脚下往上窜的粗火舌**(底部 12 条横跨龟宽 + 身侧 + 肩膀 + 头顶), 根部融成一片、
  往上分开 ⇒ 明暗交错的竖条纹 + 舌间黑缝, 游戏里渲染在龟【身后】。
  九轮各自错在哪见 docs/studies/20260915a「金火气烤了几轮」表(门框 / 树枝 / 两根金柱子 / 方蛋糕 /
  砖墙 / 亮圆斑 / 亮圆盘 / 平的金箱子 —— 除第三、八轮是游戏实拍抓到的, 其余是 4 倍放大图)。
  059 的时之砂当初就是因为白球「**把龟整只盖没了**」才换的 —— 战斗气自己再盖住龟就白换了。
  ★★前两版为了不盖住龟把身体那块**挖空**, 游戏里实拍(录屏 #308~#337)是「**龟左右各立一根金柱子**」
    (012 海藻「龟身前戳着两根绿柱子」同一个毛病)。参考 DIO 是整团火在身后、身体挡在火前面 ——
    不盖住龟的办法是【画在后面】, 不是【在前面挖洞】。
  ⇒ 游戏侧 `_ts_aura_spawn`: `render_priority = -1`(先于立绘画) + 不做深度测试(底边不被地板吃掉)。

★尺寸: cell 72 texel, 1 texel = 0.0426 m ⇒ 3.07 m; 龟 ≈ 45 texel 高
  ⇒ 火顶 ≈ 1.6 龟高(DIO 那几帧火顶到头上方约半个身高)。
★8 帧循环: 所有起伏都是 sin(2π·frame/8 + 相位) ⇒ 第 8 帧接回第 1 帧。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402

## ── 画布(渲 288px ⇒ 缩到 72 texel; 画布 [-1,1], 1 texel = 2/72 = 0.0278) ─────
Y0 = -0.98                 # 脚下
TOP_Y = 0.94               # 火顶不许顶满画布
## 身体椭圆: 龟 45 texel 高 ≈ 1.25 画布单位(脚 -0.98 → 头 0.27), 宽 ≈ 36 texel
BODY_C = (0.0, -0.36)
BODY_R = (0.50, 0.64)
## ★★第三版不再挖空(BODY_KEEP = 0): 前两版挖空身体, 游戏里实拍是「龟左右各立一根金柱子」
##   (012 海藻「龟身前戳着两根绿柱子」同一个毛病)。参考 DIO 是**整团火在身后、身体挡在火前面** ⇒
##   火做成实心一整团, 游戏里放到龟身后渲染(timestop_system `_ts_aura_spawn`), 龟自己把中间挡住。
BODY_KEEP = 0.0

SIDE_JETS = 7              # 每侧往上窜的火舌
TOP_JETS = 8               # 头顶一排(横跨整个火丘)
JET_SEGS = 48
## ★★第二版烤出来火舌细、互相分开、带深色描边 ⇒ 放大看是**树枝 / 爪子**(022 真火第 2 版栽过同一个坑)。
##   参考 DIO 那几帧火是**连成一整团的火体**, 顶上才分出火舌, 舌间是黑缝。
##   ⇒ ①先在身侧与头顶铺一层大元球当火体(MASS) ②火舌加粗、根部更胖(R_BLOB↑ R_TAPER↑) ③肩膀外甩减半
R_BLOB = 0.115             # 单颗球半径 ≈ 4 texel ⇒ 火舌根部 8~10 texel 宽
R_TAPER = 0.85
## ★★火丘烤了五次(轮次与现象都记在 docs/studies/20260915a 「金火气烤了几轮」表里):
##   小球网格 ⇒ 点阵 / 砖墙; 大球 ⇒ 亮圆斑 / 亮圆盘(白球); 大球 + 芯层不放 ⇒ **游戏里读成一块平的金箱子**
##   (中间那档占 39.4%, 一大片同一个颜色)。参考 DIO 的火每一处都是明暗交错的竖条纹、舌间有黑缝(8.1%)。
##   ⇒ 火丘不填球, 改成**一排从脚下往上窜的粗火舌**: 根部挨得近自动融成一片, 往上自然分开 ⇒ 竖条纹 + 黑缝。
##   芯层跟着火舌走 ⇒ 亮的是每条火舌的中轴(同 022 真火「底座 + 火舌」那个结构)。
BASE_JETS = 12            # 横跨龟宽度的底部火舌
BASE_HALF = 0.62          # 根部横跨的半宽(龟半宽 ≈ 0.50)
LUMP = 0.40
WOBBLE = 0.18
EMBERS = 12
EMBER_R = (0.012, 0.022)

## ── 体积发光(同 022 真火的三层做法: 外幔暗 / 体 / 芯亮) ──────────────
## ★★这五个数是**扫出来的**, 判据是 6 档金色的占比对上参考(每档 14.9~18.6%):
##   初值 体 2.6 / 外幔 0.55×1.30 / 芯 3.2×0.48 ⇒ 16.8/46.8/23.2/12.7/0.4/0.0 —— 两档最暗几乎没有, 整团发亮
##   A~C 三组只动体与外幔 ⇒ 量化后永远只落进相邻三四档(体积火单像素的亮度范围太窄)
##   ⇒ 两头一起拉开: 芯小而很亮(6.5)、外幔厚而很暗(0.24×1.65)
##   E(外幔 0.20) 13.2/13.6/13.1/17.6/16.8/25.7 → 外幔 0.24 时 8 帧 14.5/13.5/13.3/19.0/19.4/20.2(最大偏离 3.5)
##   ★但那一版形状是「树枝」; 加火体(MASS)、火舌加粗之后同一组数重烤 8 帧:
##     16.6/13.3/11.4/20.2/15.0/23.6, 最大偏离 6.9 个百分点(那一版还是挖空身体的「两根金柱子」)
##   ★定稿(第九轮·底部火舌, 同一组数): 8 帧 20.2/14.8/13.2/20.7/15.9/15.3, 最大偏离 4.0 个百分点 —— 这是现在的 ts-aura.png
DENSITY = 2.0
EMIT_COLOR = (1.0, 0.70, 0.22)
EMIT_STRENGTH = 1.3
OUTER_SCALE = 1.65
OUTER_COLOR = (1.0, 0.50, 0.10)
OUTER_EMIT = 0.24
CORE_SCALE = 0.55
CORE_COLOR = (1.0, 0.93, 0.60)
CORE_EMIT = 6.5
EMBER_DENSITY = 20.0
EMBER_EMIT = 14.0


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras,
                bpy.data.lights, bpy.data.curves, bpy.data.metaballs):
        for it in list(blk):
            blk.remove(it)


def setup_render(px):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"           # 亮度要由体积厚度产生(同 022)
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 2
    sc.cycles.volume_bounces = 1
    sc.cycles.volume_step_rate = 0.25
    sc.cycles.volume_max_steps = 2048
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"   # AgX 会把饱和色压白(022 标定过)
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    sc.world = w
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = (0.0, 0.0, 5.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def volume_mat(name, density, emit_color, emit_strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    out = nt.nodes["Material Output"]
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    pv.inputs["Density"].default_value = density
    pv.inputs["Emission Color"].default_value = (emit_color[0], emit_color[1], emit_color[2], 1.0)
    pv.inputs["Emission Strength"].default_value = emit_strength
    nt.links.new(pv.outputs["Volume"], out.inputs["Volume"])
    return m


def _n(i, k):
    """确定性伪噪声(0..1) —— 同样的输入必须烤出同样的图。"""
    v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)


def body_d(x, y):
    return math.sqrt((x / BODY_R[0]) ** 2 + ((y - BODY_C[1]) / BODY_R[1]) ** 2)


SHOULDER_LICKS = 3         # 每侧肩膀往外斜舔的短火舌


def jet_roots():
    """(x0, y0, 高, 外倾方向, 相位, 外甩量) —— 身侧两排从脚往上 + 肩膀外舔 + 头顶一排。

    ★第一版烤出来是**两根笔直的竖火柱 + 一排火冠**, 放大看像个着火的门框。
      参考 DIO 那几帧(#005~#020)火是**往外、往上甩**的: 每条外倾不一样、根粗梢细,
      肩膀那里还有横着往外舔的短火舌。⇒ 每条火舌自己的外甩量 + 肩膀一排短舌。"""
    out = []
    ## 底部一排: 从脚下往上窜, 中间高两边矮; 两侧的往外甩、中间的往中轴收一点
    for k in range(BASE_JETS):
        u = k / float(BASE_JETS - 1) * 2.0 - 1.0
        x0 = u * BASE_HALF + 0.05 * (_n(k, 83) - 0.5)
        h = (1.10 + 0.55 * _n(k, 89)) * (1.0 - 0.35 * abs(u))
        side = 0.0 if abs(u) < 0.3 else (1.0 if u > 0.0 else -1.0)
        out.append((x0, Y0 + 0.02, h, side, k * 2.3 + 0.4, 0.10 + 0.15 * _n(k, 97)))
    for si, side in enumerate((-1.0, 1.0)):
        for k in range(SIDE_JETS):
            u = k / float(SIDE_JETS - 1)
            y0 = Y0 + 0.02 + u * 0.95
            x0 = side * (0.54 + 0.08 * _n(k, 3 + si * 4) - 0.06 * u)
            h = (0.55 + 0.35 * _n(k, 5 + si * 4)) * (1.0 - 0.30 * u)
            lean = 0.10 + 0.25 * _n(k, 19 + si * 4)
            out.append((x0, y0, h, side, k * 1.9 + si * 2.2, lean))
        for k in range(SHOULDER_LICKS):
            y0 = -0.30 + 0.20 * k + 0.08 * (_n(k, 29 + si) - 0.5)
            x0 = side * (0.62 + 0.10 * _n(k, 31 + si))
            h = 0.26 + 0.20 * _n(k, 37 + si)
            out.append((x0, y0, h, side, k * 3.1 + 0.7 + si, 0.45 + 0.25 * _n(k, 41 + si)))
    for k in range(TOP_JETS):
        u = k / float(TOP_JETS - 1)
        x0 = -0.52 + 1.04 * u + 0.06 * (_n(k, 11) - 0.5)
        y0 = -0.05 + 0.15 * _n(k, 13)
        h = 0.55 + 0.32 * _n(k, 17)
        out.append((x0, y0, h, 0.0, k * 2.7 + 1.1, 0.25))
    return out


def build_flame(ph, mat, scale=1.0, name="fire"):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 0.010
    mb.render_resolution = 0.008
    ob = bpy.data.objects.new(name, mb)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    placed = 0
    ## 火舌(底部一排 + 身侧 + 肩膀 + 头顶, 见 jet_roots)
    for j, (x0, y0, h, side, jp, lean) in enumerate(jet_roots()):
        hh = h * (1.0 - WOBBLE + WOBBLE * (1.0 + math.sin(ph + jp)))
        for s_i in range(JET_SEGS):
            t = s_i / float(JET_SEGS - 1)
            y = y0 + hh * t
            if y > TOP_Y:
                break
            ## 往上窜: 身侧的按各自外甩量往外弯(根直梢弯), 头顶的往中间收一点; 加沿流线推移的行波(火在飘)
            flare = (side * lean * hh * pow(t, 1.3)) if side != 0.0 else (-x0 * lean * t)
            x = x0 + flare + 0.06 * math.sin(ph * 1.6 + t * 4.5 + jp)
            if abs(x) > 0.96 or body_d(x, y) < BODY_KEEP:
                continue
            lump = 1.0 + LUMP * (math.sin(t * 11.0 + ph * 2.0 + jp * 2.3) * 0.6 + (_n(j * 31 + s_i, 5) - 0.5))
            r = R_BLOB * pow(max(0.02, 1.0 - t), R_TAPER) * max(0.15, lump)
            e = mb.elements.new()        # ★先判后建: 建了再跳过会留下默认半径 2.0 的球填满画布(022 踩过)
            e.co = (x, y, 0.0)
            e.radius = r * scale
            placed += 1
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return placed


def add_embers(ph, mat):
    for k in range(EMBERS):
        a = (k * 0.61803398875 + ph / (2.0 * math.pi)) % 1.0
        side = -1.0 if k % 2 == 0 else 1.0
        x = side * (0.45 + 0.45 * _n(k, 21))
        y = Y0 + 0.40 + a * 1.30
        if y > TOP_Y or body_d(x, y) < BODY_KEEP:
            continue
        r = (EMBER_R[0] + (EMBER_R[1] - EMBER_R[0]) * _n(k, 23)) * (1.0 - 0.5 * a)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=(x, y, 0.0))
        ob = bpy.context.object
        ob.scale = (0.75, 1.0 + 1.1 * a, 0.75)
        ob.data.materials.append(mat)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--px", type=int, default=288)
    ap.add_argument("--emit", type=float, default=EMIT_STRENGTH)
    ap.add_argument("--only", type=int, default=-1)
    ## ★调色板占比要对上参考(六档各 15~19%) —— 调的是这四个, 先单帧试再烤全套
    ap.add_argument("--oemit", type=float, default=OUTER_EMIT)
    ap.add_argument("--oscale", type=float, default=OUTER_SCALE)
    ap.add_argument("--cemit", type=float, default=CORE_EMIT)
    ap.add_argument("--cscale", type=float, default=CORE_SCALE)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    todo = range(a.frames) if a.only < 0 else [a.only]
    for f in todo:
        ph = 2.0 * math.pi * f / float(a.frames)
        clear_scene()
        setup_render(a.px)
        outer = volume_mat("outer", DENSITY, OUTER_COLOR, a.oemit)
        body = volume_mat("fire", DENSITY, EMIT_COLOR, a.emit)
        core = volume_mat("core", DENSITY, CORE_COLOR, a.cemit)
        emb = volume_mat("ember", EMBER_DENSITY, (1.0, 0.86, 0.50), EMBER_EMIT)
        n = build_flame(ph, outer, a.oscale, "outer")
        build_flame(ph, body, 1.0, "fire")
        build_flame(ph, core, a.cscale, "core")   # 芯层跟着火舌走 ⇒ 亮在每条火舌中轴
        add_embers(ph, emb)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % f)
        bpy.ops.render.render(write_still=True)
        print("[tsaura] 帧 %d/%d 烤好(元球 %d 颗)" % (f + 1, a.frames, n))
    print("[tsaura] 全部 → %s" % a.out)


if __name__ == "__main__":
    main()
