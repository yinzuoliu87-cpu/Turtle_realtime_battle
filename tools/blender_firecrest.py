"""blender_firecrest.py — 023 灼热火珊瑚【火焰波】的一簇火冠(8 帧循环)。

跑法(无窗口):
  blender --background --python tools/blender_firecrest.py -- --out C:/tmp/fc --frames 8 --only <k> --px 256
  python tools/pixelize_sheet.py C:/tmp/fc --dirs 8 --frames 1 --cell 40 --art-h 40
      --palette truefire -o assets/sprites/vfx/fire-crest.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-13)
════════════════════════════════════════════════════════════════════════
023 文案:「主动(法力条集满时自动释放): 蓄力后朝敌方挥出一道**火焰波**,
  在 CORAL_ARC_DEG 度扇形内**缓慢移动** CORAL_TRAVEL 码, 对扫过的敌人各施加灼烧」。

★改之前那一版的三条硬伤(实拍 + 探针确诊):
  ① 波是 `VfxTex._make_qi_texture()` **程序生成的气波**染成橙色 —— 复用别件的原语
     (素材不复用铁律), 而且根本不是像素画;
  ② **没设 texture_filter** ⇒ 探针实测 Sprite3D 默认是 `LINEAR_WITH_MIPMAPS`(=3),
     硬边像素图被线性过滤 + mipmap; 而且每帧 `wave.scale = ...` **连续缩放**
     —— 像素风三条硬约束破了两条;
  ③ 伤害判定挂在演出的 `while` 循环里、推进用 `get_process_delta_time()`
     = **第二条钟**(CLAUDE.md §3.5 / memory [[fb-second-clock-drops-events]])。

★★为什么是「一排直立的火簇」而不是「一张弯月贴图」:
  像素风不许自由旋转, 而波的弧每帧角度都在变 —— 一张弯月贴图必须跟着转。
  **但火焰永远朝上**(浮力), 所以把波拆成沿弧摆放的**直立火簇**:
  贴片一次都不用转, 波变长就**多摆几个(整数个)**, 也不需要连续缩放。
  形状是被像素风约束逼出来的, 同时物理上正确。

════════════════════════════════════════════════════════════════════════
 ★参考实测 (YR0cpfWZVhY「Cartoon Fire Slash / Green Screen」, **上传 2026-01-15**)
════════════════════════════════════════════════════════════════════════
  绿幕背景 ⇒ 背景扣得干净, 不用估。量了 15 帧取中位:
    厚度 / 弦长      = **0.134**
    亮芯占火像素     = **0.03**(只有一丝芯, 绝大部分是外缘色)
    芯色 RGB (255,198,29) 金黄 · 缘色 RGB (248,15,0) 正红
  ★弧的曲率**不取参考**: 60° 扇形自己定死了 —— 矢高/弦 = (1-cos30°)/(2sin30°) = 0.134。
  ★调色板仍用 `truefire`(与 022 同一团火的材质), **素材是新烤的**
    —— 铁律禁的是「拿别的素材顶替」, 不是禁止共用调色板。

★尺寸: 一簇 40 texel × 0.0426 = **1.70 m**(龟高 2.0 m) ⇒ 火冠比龟略矮, 是「一道波」不是「一堵墙」。
★8 帧循环: 波在飞的整段都在烧, 必须无缝循环。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402

## ── 实测剖面(自**下**而上, 把上面那行倒过来) ──────────────────────
## 面积: 2775 / 4671 / 4375 / 3348 / 1578 / 25  ⇒ 归一到最大
AREA_PROFILE = [0.594, 1.000, 0.937, 0.717, 0.338, 0.005]

## ── 画布与整体尺度(画布 [-1,1] 的 XY 平面, 渲 320px ⇒ 缩到 80 texel) ──
Y0 = -0.98             # 火焰底(脚下)
H_ALL = 1.42           # 火冠总高(比 022 的体火矮一截 —— 它是波不是一身火)
W_MAX = 0.96           # 最宽那一带的半宽

## ── 羽流(元球堆) ───────────────────────────────────────────────
## ★★第 4 版初稿用「扫出来的管」做火舌 —— 烤出来是**一把光滑的面条 + 一个水洼**:
##   管子粗细沿长度几乎不变、边缘是软的、几根最高的还被包络夹到同一个顶点成了帐篷。
##   真火的轮廓是**湍流的**: 会鼓包、会掐细、会分叉, 边缘有高频起伏。
##   ⇒ 改用 **元球(metaball)**: 一串球沿流线堆上去, 靠近的自动融成一团、
##     远的自然断开成独立舌尖 —— 疙瘩轮廓是**融出来的**, 不是我画的规则图案。
JETS = 5               # 一簇里几条火舌
## 每条够到的相对高度 = 复现实测面积剖面(2 条 >0.85 / 4 条 >0.6 / 6 条 >0.4)
JET_H = [1.00, 0.62, 0.86, 0.48, 0.72]      # 矮而宽: 最高那条也只到本格高
JET_X = [-0.62, 0.30, -0.16, 0.66, 0.08]    # 根部横位(相对包络半宽)
## ★★取样必须**密于半径**, 否则元球不融 —— 初稿 22 颗(间距 0.086 > 半径 0.048)
##   烤出来是一串**珠子**。间距 ≈ 0.5 × 半径 才连成一条。
JET_SEGS = 64          # 每条流线上放几颗球
## ★单颗球半径: 实测单根舌宽/火高 = 0.060 ⇒ 80 格里 4.8 texel ⇒ 半径 2.4 texel
##   元球融合后会比单颗略胖, 所以取 0.85 折扣, 烤完量游程再回调。
## ★★宽度定标又改了一次: 中位段宽(9px)量的是**细舔**, 火的**面积**在宽段上
##   —— 面积加权平均段宽 38.2 px / 火高 149 = **0.256** ⇒ 80 格里 **20.5 texel**。
##   实测三档并排比填充率: rb 0.10→0.29 / 0.15→0.38 / **0.21→0.45**(参考 0.44)。
R_BLOB = 0.17
R_TAPER = 0.55         # 半径随高度收: r = R × (1-t)^R_TAPER
LUMP = 0.42            # 半径的高频起伏幅度(轮廓的疙瘩就是它)
## ★侧向漂移: 浮力上升 + 横向剪切 ⇒ 越高偏得越多, 且**不夹到同一个顶点**
CURL = 0.34
CURL_P = 1.6
WOBBLE = 0.16          # 每条流线的高度起伏(相对) —— 已扣掉, 保证不超出画布
## ── 底座: 贴地那一排大球, 融成面积剖面最宽的那一带 ──────────
BASE_BLOBS = 11
R_BASE = 0.26

## ── 火星: 实测 82% 的连通块是 ≤12px 的碎星 ─────────────────────
EMBERS = 10
EMBER_R = (0.009, 0.018)   # 半径 0.4~0.7 texel ⇒ 落到 1~2 texel 的碎星
## ── 体积发光参数 ────────────────────────────────────────────────
## 密度 = 吸收系数(Color 设黑 ⇒ 不散射, 场里也没灯)。alpha = 1-exp(-密度×路径)。
## 火舌截面是圆的 ⇒ 视线穿过的长度天然是「离中轴多远」的函数 ⇒ 芯亮边暗。
## ★★密度从 6 降到 2: 6 的时候光学厚度处处 >2 ⇒ **全部饱和** ⇒ 烤出来是一片死橙、
##   芯亮边暗那条梯度整个消失。降到 2 之后亮度才真的跟着穿透厚度走。
DENSITY = 2.0
## ★发光色压红: (1,0.42,0.16) 时 R 一饱和 G 就跟着上去 ⇒ 整团泛白发黄(实拍一眼假)。
##   压到 G=0.30 B=0.09 之后, 厚处 sRGB≈(255,184,106) 亮橙、薄处≈(148,84,47) 深橙。
EMIT_COLOR = (1.0, 0.30, 0.09)
## ★★实拍复核: 整团被洗成奶油色。**根因不是体亮度**(算出来体 = 外幔+体 = sRGB(233,129,74),
##   本来就落在 truefire[2] 主火色上) —— 是**芯铺得太大**(CORE_SCALE 0.60 ⇒ 亮档占 54%)。
##   收窄芯之后主火色到了 63%, 但**实拍还是奶油色** —— 台子泛光把 truefire[2](亮度 166)
##   也抬上去了。memory [[fb-vfx-defect-families]] 那条写的就是这个: **源色必须更暗**。
##   ⇒ 再压一档: 体落 truefire[3](196,96,40 · 亮度 119)、芯落 truefire[1]、
##     只有外幔的那一圈落 truefire[5](62,24,12) ⇒ 像素画自带深色描边。
EMIT_STRENGTH = 3.0
## ★★外幔: 只有「体 + 芯」两层时, 量化到 6 色板上**全部落进同一档**(实拍是一张纯橙剪影)。
##   火本来就有**外焰**: 最外圈温度最低、最暗最红。加上它之后一条视线上是
##   外幔 → 外幔+体 → 外幔+体+芯 三级, 量化才分得出档
##   (和 021 绳珠的三层同心是同一招: 横截面分层, 不是画渐变)。
OUTER_SCALE = 1.26                # 外焰厚 ≈2 texel(1.13 时只有 1 texel, 量下来暗边只占 4%)
OUTER_COLOR = (1.0, 0.22, 0.05)
OUTER_DENSITY = 2.0
OUTER_EMIT = 0.45                  # 渐近值 0.15 ⇒ sRGB≈(110,53,24) ≈ truefire[4] 暗红

## ★白热芯: 实测参考最亮处 RGB (231,164,138) 橙白, 位置在**密实的下中部**不是舌尖。
##   ⇒ 在火体里再套一层更小、更白的体积(火焰越靠近燃烧面温度越高 —— 物理上就该有这层)。
CORE_SCALE = 0.32                 # 芯相对本体的半径; 0.60 时亮档占 54% ⇒ 整团洗白
CORE_TOP = 0.78                   # 芯只到火高的这个比例(实测亮度剖面最亮在**中上部**: 自下而上 154/165/172/181/179/150)
CORE_COLOR = (1.0, 0.72, 0.52)
CORE_DENSITY = 2.0
CORE_EMIT = 4.6                   # +外幔+体 ⇒ sRGB≈(255,222,172) ≈ truefire[0] 橙白
EMBER_DENSITY = 20.0
EMBER_EMIT = 16.0


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras,
                bpy.data.lights, bpy.data.curves):
        for it in list(blk):
            blk.remove(it)


def setup_render(px):
    sc = bpy.context.scene
    ## ★★必须 Cycles: 亮度要由**体积厚度**产生(EEVEE 的体素体积在 80px 上糊成一坨)。
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 2
    sc.cycles.volume_bounces = 1
    sc.cycles.volume_step_rate = 0.25     # 细一点, 否则薄舌尖会被步长跨过去
    sc.cycles.volume_max_steps = 2048
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    ## ★色彩管线显式钉死(Blender 5.2 默认 AgX 会把饱和色压白; 标定过 Standard+look=None 才恒等)
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.0   # 全黑, 不给环境光
    sc.world = w
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0                  # 画布正好 [-1,1]
    cam = bpy.data.objects.new("cam", cd)
    cam.location = (0.0, 0.0, 5.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)  # 看向 -Z ⇒ 火在 XY 平面, 管子朝相机鼓出来
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def volume_mat(name, density, emit_color, emit_strength):
    """纯体积发光材质: Surface 不接(光线直接穿过表面), 只给 Volume。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    out = nt.nodes["Material Output"]
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)   # 不散射 ⇒ 只吸收
    pv.inputs["Density"].default_value = density
    pv.inputs["Emission Color"].default_value = (emit_color[0], emit_color[1], emit_color[2], 1.0)
    pv.inputs["Emission Strength"].default_value = emit_strength
    nt.links.new(pv.outputs["Volume"], out.inputs["Volume"])
    return m


def envelope(u):
    """实测面积剖面 ⇒ 该归一高度(0=底 1=顶)的包络半宽。"""
    n = len(AREA_PROFILE)
    x = max(0.0, min(0.999, u)) * (n - 1)
    i = min(n - 2, int(x))
    t = x - i
    return (AREA_PROFILE[i] * (1.0 - t) + AREA_PROFILE[i + 1] * t) * W_MAX


def _n(i, k):
    """确定性伪噪声(0..1) —— 不用 random: 同样的输入必须烤出同样的图。"""
    v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)


def build_flame(ph, mat, scale=1.0, top=1.0, name="fire"):
    """整团火 = 一个元球对象。球靠得近就融成一片, 远了自然断成独立舌尖。

    scale/top: 同一套几何缩一圈、只留下半段 ⇒ 复用它当**白热芯**(不是另画一个形状,
    芯与本体必须严丝合缝, 否则芯会探出火外)。"""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 0.010          # 渲染分辨率: 越小轮廓细节越多(也越慢)
    mb.render_resolution = 0.008
    ob = bpy.data.objects.new(name, mb)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)

    ## ① 底座: **土丘**不是横香肠 —— 实测每带总宽(自下而上) 0.59/1.00/0.90/0.68/0.55/0.25,
    ##    ⇒ 火在**下 40% 的高度上都很宽**, 底座必须撑到 0.35×H 而不是贴着地皮。
    ##    (初稿只堆到 0.13×H, 烤出来是一根横躺的香肠 + 几条树枝。)
    for i in range(BASE_BLOBS):
        row = i % 3
        k = i // 3
        cols = (BASE_BLOBS + 2) // 3
        u = -1.0 + 2.0 * k / float(max(1, cols - 1))
        u += (_n(i, 11) - 0.5) * 0.18                 # 错开, 不许排成整齐的格子
        yy = Y0 + (0.06 + 0.30 * row / 2.0 + 0.05 * _n(i, 13)) * H_ALL
        lim = envelope((yy - Y0) / H_ALL)
        rr = R_BASE * (0.78 + 0.40 * _n(i, 3)) * (1.0 - 0.22 * abs(u)) * (1.0 - 0.25 * row / 2.0)
        ## ★★判断要在 elements.new() **之前** —— 先建再 continue, 会留下一颗
        ##   **没赋半径的元球**, 而 Blender 的默认 radius 是 2.0, 在 [-1,1] 的画布里
        ##   一颗就把整幅图填满(实拍是一整块米色方块)。踩过一次, 钉在这。
        if yy - Y0 > top * H_ALL:
            continue
        e = mb.elements.new()
        e.co = (max(-lim + rr, min(lim - rr, u * lim * 0.52)) + 0.04 * math.sin(ph + i),
                yy, 0.0)
        e.radius = rr * scale

    ## ② 羽流: 每条流线一串球, 半径随高度收 + 高频起伏 ⇒ 轮廓自带疙瘩
    for j in range(JETS):
        hh = JET_H[j] * H_ALL * (1.0 - WOBBLE + WOBBLE * (1.0 + math.sin(ph + j * 1.7)))
        hh = min(hh, H_ALL)        # ★不许超出画布(初稿的 WOBBLE 把最高那条顶出去了)
        x0 = JET_X[j] * envelope(0.05) * 0.80
        side = 1.0 if x0 >= 0.0 else -1.0
        amp = CURL * hh * (0.40 + 0.60 * abs(JET_X[j])) * side
        for s_i in range(JET_SEGS):
            t = s_i / float(JET_SEGS - 1)
            y = Y0 + hh * t
            ## 侧向: 随高度增长的卷 + 沿流线推移的行波(火在飘, 不是直柱)
            x = x0 + amp * pow(t, CURL_P) + 0.13 * hh * math.sin(ph * 1.6 + t * 4.2 + j)
            ## 半径: 收尖 × 高频起伏(疙瘩) —— 起伏相位跟着帧走 ⇒ 火在翻腾
            lump = 1.0 + LUMP * (math.sin(t * 11.0 + ph * 2.0 + j * 2.3) * 0.6
                                 + (_n(j * 31 + s_i, 5) - 0.5))
            r = R_BLOB * pow(max(0.02, 1.0 - t), R_TAPER) * max(0.15, lump)
            ## 不许探出实测包络(宽度必须是量出来的)
            lim = envelope((y - Y0) / H_ALL)
            if abs(x) + r > lim:
                x = math.copysign(max(0.0, lim - r), x)
            if y - Y0 > top * H_ALL:
                continue
            e = mb.elements.new()
            e.co = (x, y, 0.0)
            e.radius = r * scale

    ## 转成网格: 体积材质要闭合网格(元球融出来的等值面天然闭合)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")


def add_embers(ph, mat, rng):
    """火星: 实测参考里 82% 的连通块是 ≤12px 的碎星。它们**脱离本体**往上飘。

    做成**竖向拉长**的小块(火星是在动的, 快门里是一道短划), 不是滚圆的珠子 ——
    初稿那版滚圆等亮的球读成了「泡泡」。"""
    for k in range(EMBERS):
        a = (k * 0.61803398875 + ph / (2.0 * math.pi)) % 1.0     # 沿帧循环往上走
        x = (rng[k % len(rng)] * 2.0 - 1.0) * W_MAX * 0.95
        y = Y0 + 0.30 * H_ALL + a * 0.66 * H_ALL
        x *= (1.0 - 0.30 * a)                                    # 越高越靠中(火柱收束)
        r = EMBER_R[0] + (EMBER_R[1] - EMBER_R[0]) * rng[(k * 3 + 1) % len(rng)]
        r *= (1.0 - 0.50 * a)                                    # 飘高了就烧小
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r,
                                              location=(x, y, 0.0))
        ob = bpy.context.object
        ob.scale = (0.75, 1.0 + 1.1 * a, 0.75)                   # 竖向拉长 = 运动划痕
        ob.data.materials.append(mat)

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--px", type=int, default=320)
    ap.add_argument("--emit", type=float, default=EMIT_STRENGTH)
    ap.add_argument("--rb", type=float, default=R_BLOB)
    ## ★并行用: 一个进程只烤一帧(相位仍按 --frames 总数算 ⇒ 8 个进程拼出来的循环与串行逐字相同)
    ap.add_argument("--only", type=int, default=-1)
    ## ★密度倍率: 密度一高, 光学厚度处处 >1 ⇒ (1-e^-τ) 处处 ≈1 ⇒ **亮度和厚度脱钩**
    ##   (实测渲染图亮度只在 152~181 之间, 内/外 1.08, 量化后全部落进同一档)。
    ##   ★★但**压薄是死路**: alpha = 1-exp(-τ) 与亮度同源, 一薄, 暗像素正好被
##   pixelize 的 alpha<24 切掉, 活下来的全是亮的 ⇒ 亮度分位 5/50/95 = 248/248/254, 更平。
##   ⇒ 三层都保持光学**厚**(剪影实), 分档交给**每层各自的发光强度**:
##     外幔 0.9 → 暗红边 / 体 4.0 → 主火色 / 芯 4.0(叠在前两层上) → 橙白。
##   这个默认值 1.0 留着是为了把上面这条结论能一条命令复现出来。
    ap.add_argument("--dens", type=float, default=1.0)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    ## 固定序列(不用 random: 同样的输入必须烤出同样的图)
    rng = [0.13, 0.77, 0.41, 0.92, 0.28, 0.65, 0.09, 0.54, 0.83, 0.36, 0.71, 0.22]
    globals()["R_BLOB"] = a.rb
    for k in ("DENSITY", "OUTER_DENSITY", "CORE_DENSITY"):
        globals()[k] = globals()[k] * a.dens

    todo = range(a.frames) if a.only < 0 else [a.only]
    for f in todo:
        ph = 2.0 * math.pi * f / float(a.frames)
        clear_scene()
        setup_render(a.px)
        mat = volume_mat("fire", DENSITY, EMIT_COLOR, a.emit)
        emb = volume_mat("ember", EMBER_DENSITY, (1.0, 0.72, 0.42), EMBER_EMIT)
        outer = volume_mat("outer", OUTER_DENSITY, OUTER_COLOR, OUTER_EMIT)
        build_flame(ph, outer, OUTER_SCALE, 1.0, "outer")
        build_flame(ph, mat)
        core = volume_mat("core", CORE_DENSITY, CORE_COLOR, CORE_EMIT)
        build_flame(ph, core, CORE_SCALE, CORE_TOP, "core")
        add_embers(ph, emb, rng)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % f)
        bpy.ops.render.render(write_still=True)
        print("[truefire] 帧 %d/%d 烤好" % (f + 1, a.frames))
    print("[truefire] 全部 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
