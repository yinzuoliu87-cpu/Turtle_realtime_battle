# -*- coding: utf-8 -*-
"""blender_healplume.py — 【治疗绿光】: 从脚下升起、裹住单位的一束绿光(6 帧)。

跑法(无窗口):
  blender --background --python tools/blender_healplume.py -- --out C:/tmp/hp --frames 6 --px 192
  python tools/pixelize_sheet.py C:/tmp/hp --dirs 6 --frames 1 --cell 48 --art-h 48 \
      --palette heal -o assets/sprites/vfx/heal-plume.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-12)
════════════════════════════════════════════════════════════════════════
用户看 019 海葵药膏的窗口后:「**应该要身上冒绿光和绿粒子，但不要复用**」

被否的是「治疗只有脚下一圈淡绿地环 + 一个飘字」——
**治疗这个动作在画面上读不出来**, 和 015 的反伤是同一类(文案写了、画面读不出)。

★挂在哪: **只有 019**(`equip_tick_system._tick_anemone`) —— 携带者自己 + 被奶的那只友军。
  我一度挂到 `battle_damage._heal_flush()`(`_heal` 全仓 **80 个调用点**的中央收口),
  等于全游戏所有治疗一起换演出。用户当场否:
    「**我只让你对019做这次的绿光和绿粒子，你不对把其他的也全用了吧**」
  ⇒ 已收回。**范围由需求定, 不由我推广。**

★为什么是【光束】不是圆环/光球:
  用户先后否过两次「程序生成的圆环白球」。一团球没有含义;
  **从脚下升起的光**有方向、有因果(治疗从下往上把单位裹住), 读得出「这只龟正在被治」。

★为什么用 additive(加色):
  加色下**暗像素等于不贡献**, 所以这束光叠在龟身上 = 龟被照亮,
  而黑背景仍是黑的 —— 这正是「身上冒绿光」的物理读法。
  (护盾罩那一层的 additive 是用户 2026-09-12 亲口拍的「开」。)

★尺寸按【屏幕像素】反算(今天已经栽过六次):
  实测 1 屏幕像素 = 0.0426 m(染色法量的: 一粒 7×7 px / 一只龟 ≈45 px 高而帧高 2.0 m)。
  一束光要**裹住整只龟** ⇒ 48×48 一格 ⇒ 世界 48×0.0426 = 2.04 m ≈ 正好一个龟高,
  且 pixel_size 0.0426 = **1 texel : 1 屏幕像素**(不缩放, 像素网格不被打烂)。

★形态改过一版(1:1 看了实图才定的):
  第一版是「5 条竖直的舌分三层」—— 烤出来 **读成城市天际线/柱状图**(方顶、等宽、
  白色占 32.7% 压过绿色)。那是形状的错, 不是参数的错。
  现版 = **脚下一条亮带(光源) + 7 根细的上升光丝**:
    · 亮带只占底部两三个像素高, 是「光从这里冒出来」的因
    · 光丝 1~3 px 宽、正弦微弯、越往上越细越暗, 高度逐帧起伏
  细而弯 ⇒ 读成「冒出来的光」; 粗而直 ⇒ 读成「立着的物体」。
  6 帧只改光丝的高度与相位, **画布尺寸恒定**(缩放会打烂像素网格)。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

## x 是 [-1,1] 归一, y 从 -0.95 起(脚下)。
Y0 = -0.95
BASE_W = 0.80          # 脚下亮带半宽
BASE_H = 0.14          # 脚下亮带高(只有两三个像素 —— 它是「光源」不是底座)
WISPS = 11             # 上升光丝根数(7 → 11: 太稀会读成几根针, 要密到成「一团光」)
W_HALF = 0.075         # 光丝根部半宽(0.052 → 0.075: 太细在 48px 下读成针)
W_SPREAD = 0.80        # 光丝铺开的半宽
W_HI = [0.95, 0.62, 1.10, 0.48, 1.02, 0.72, 0.86, 0.56, 1.05, 0.66, 0.90]   # 每根的基准高(参差)
W_PHASE = [0.00, 0.55, 0.20, 0.80, 0.35, 0.65, 0.10, 0.45, 0.90, 0.25, 0.70]  # 每根的相位
W_WOBBLE = 0.30        # 高度随帧起伏(相对基准高)
W_BEND = 0.11          # 光丝的横向弯曲幅度(正弦) —— 直的读成柱子, 弯的才读成光
SEGS = 9               # 每根光丝分几段(段越多越顺, 但 48px 下 9 段够)


def _srgb(r, g, b):
    """sRGB 0-255 → 线性。Blender 的 emission 吃线性(09-12 在半壳上栽过一次)。"""
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


## ★直接取 pixelize_sheet 的 'heal' 板上的色 —— 后一步要重索引到那块板(最近邻),
##   这里随手配的色会被映射到别的档上(014 就是这么把主绿串成薄荷青的)。
C = {
    "core": _srgb(92, 226, 160),    # heal[1] 亮绿 —— 加色下**不能用近白**, 会直接冲成白
    "mid": _srgb(36, 178, 112),     # heal[2] 主绿
    "edge": _srgb(22, 122, 78),     # heal[3] 暗绿
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for it in list(blk):
            blk.remove(it)


def setup_render(px):
    sc = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    ## ★★色彩管线必须显式钉死才是恒等的。Blender 5.2 默认 view_transform = AgX,
    ##   AgX 把饱和色往白里压 —— 烤出来的绿不是我写的那个绿。
    ##   标定过(烤五块纯色量回来): Standard + look=None ⇒ 输入输出逐字节相同。
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def flat(name, rgba):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Color"].default_value = rgba
    emi.inputs["Strength"].default_value = 1.0
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    return mat


def poly(name, pts, mat, z):
    me = bpy.data.meshes.new(name)
    me.from_pydata([[p[0], p[1], z] for p in pts], [], [tuple(range(len(pts)))])
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def build(k, frames, mats):
    """一帧 = 脚下亮带 + WISPS 根上升光丝。光丝按段画: 越往上越细、越暗。"""
    obs = []
    ## ① 脚下亮带 —— 光从这里冒出来(因), 上面的光丝是果
    obs.append(poly("base%d" % k, [
        (-BASE_W, Y0), (BASE_W, Y0),
        (BASE_W * 0.72, Y0 + BASE_H), (-BASE_W * 0.72, Y0 + BASE_H),
    ], mats["core"], 0.00))
    ## ② 上升光丝
    for t in range(WISPS):
        cx0 = -W_SPREAD + 2.0 * W_SPREAD * (float(t) + 0.5) / float(WISPS)
        ph = (float(k) / float(frames) + W_PHASE[t % len(W_PHASE)]) * math.tau
        h = W_HI[t % len(W_HI)] * (1.0 - W_WOBBLE * 0.5 + W_WOBBLE * 0.5 * (1.0 + math.sin(ph)))
        for sgi in range(SEGS):
            u0 = float(sgi) / float(SEGS)
            u1 = float(sgi + 1) / float(SEGS)
            y_a = Y0 + h * u0
            y_b = Y0 + h * u1
            ## 横向弯曲: 正弦, 越往上摆得越开
            bx_a = cx0 + W_BEND * u0 * math.sin(ph + u0 * 3.1)
            bx_b = cx0 + W_BEND * u1 * math.sin(ph + u1 * 3.1)
            ## 越往上越细(线性收到 0.25)
            w_a = W_HALF * (1.0 - 0.75 * u0)
            w_b = W_HALF * (1.0 - 0.75 * u1)
            ## 越往上越暗: 下 1/3 主色, 中 1/3 主色, 上 1/3 暗绿(加色下 = 越淡)
            slot = "mid" if u0 < 0.62 else "edge"
            obs.append(poly("w%d_%d_%d" % (t, sgi, k), [
                (bx_a - w_a, y_a), (bx_a + w_a, y_a),
                (bx_b + w_b, y_b), (bx_b - w_b, y_b),
            ], mats[slot], 0.01 + 0.0001 * sgi))
    return obs

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=192)
    ap.add_argument("--frames", type=int, default=6)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    mats = {k: flat(k, v) for k, v in C.items()}
    for k in range(a.frames):
        obs = build(k, a.frames, mats)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob in obs:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_healplume] 渲出 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
