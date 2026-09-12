# -*- coding: utf-8 -*-
"""blender_lifemote.py — 014 深海堡垒甲【汲取生命】的绿色生命粒子(4 帧闪烁)。

跑法(无窗口):
  blender --background --python tools/blender_lifemote.py -- --out C:/tmp/lm --frames 4 --px 96
  python tools/pixelize_sheet.py C:/tmp/lm --dirs 4 --frames 1 --cell 12 --art-h 12 \
      --palette life -o assets/sprites/vfx/life-mote.png
  "<godot>" --headless --path . --import        # ★换了 png 必须 import, 否则游戏读旧图

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-12)
════════════════════════════════════════════════════════════════════════
用户看 014 的汲取:「**为什么又用什么长方形来敷衍**」「**你怎么能这样敷衍我呢**」

被否的是我拿 `_bolt_line`(一条直线排一串方块)当"汲取"用。
**一串静止的方块不是特效, 是几何占位** —— 与他先前否掉的「程序生成的圆环白球」同一类。

他给的四拍(逐字钉住, 不许漂):
  ① 一道**绿色粒子波纹**从**目标身上抽取出来**
  ② 在**空中飘舞**(飘动的曲线, 不是直线)
  ③ **飞到携带者身上**
  ④ 携带者身上**绿色粒子爆发**

这一张是那四拍里的"粒子"本体。

★为什么单独烤而不复用 `ms-mote.png` / `bamboo-charge-orb.png`:
  铁律 [[fb-no-asset-reuse-unless-told]]「新内容一律新素材, 别拿别的顶替」。
  而且那两张一个是训龟大师的光尘、一个是竹龟蓄力球, 都是别件的招牌。

★形态: 菱形亮芯 + 四角短芒(生命/治疗的通用读法), **不是圆点**——
  圆点在 6px 下和"一坨"没区别; 菱形+芒才读得出"这是一粒能量"。
  4 帧做**呼吸闪烁**(芒长短交替), 让一串粒子在空中不是死的。

★★尺寸: **贴图的一个像素要落在屏幕的一个像素上**, 不是「世界里多少米」。
  2026-09-12 染色实测(品红 + 关泛光, 见 CLAUDE.md「染色法」):
    · 一粒在屏幕上只有 **7×7 像素**, 而贴图格是 **24×24**
    · ⇒ 被**压了 3.4 倍**。像素画一旦非整数倍缩放, 网格就被打烂
      (这条是本项目像素风三条硬约束的头一条, battle_ballistics.gd:675)
    · 实拍读出来的就是「一坨白亮点」, 看不出是菱形、更看不出是绿的
  同一帧里量到的标尺: 一只龟 ≈45 屏幕像素高 / 立绘帧高 = TARGET_BODY_H = 2.0 m
  ⇒ **≈23.5 屏幕像素/米**(≈0.56 px/码)。
  (代码里旧注释写的 0.69 px/码 是别处抄来的、量的不是这个镜头, 已按实测改。)
  ⇒ 本图定为 **12×12 一格**(4 帧横排 48×12), 调用点 21.3 码 = 0.511 m
    ⇒ pixel_size = 0.0426 m/texel ≈ **1 texel : 1 屏幕像素**。
    0.511 m 也正好是**四分之一个龟高** —— 这个比例与分辨率无关, 换屏幕也不漂。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

CELL = 24                  # 每帧边长(最终像素)
## ★ 1:1 实拍调过一次: CORE_R=0.30 时白芯在 12px 下占满,
##   绿边只剩 1px ⇒ 一串粒子读成**白色亮片**而不是「绿色粒子波纹」。
##   用户要的是**绿色** ⇒ 缩芯、加绿。
CORE_R = 0.16              # 菱形亮芯半径(占半格)
RAY_LEN = [0.92, 0.74, 0.86, 0.66]    # 4 帧的芒长(呼吸)
## 12×12 一格时, 半宽 0.115 = 1.4 个像素 ⇒ BOX 缩小 + 重索引之后芒会被吃掉大半。
## 加到 0.15(≈1.8px) 让每根芒在最终图里至少留得住 1 个实心像素。
RAY_W = 0.15               # 芒根部半宽


def _srgb(r, g, b):
    """sRGB 0-255 → 线性(Blender 的 emission 吃线性; 09-12 在半壳上栽过一次)。"""
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


## ★★三个颜色【直接取 pixelize_sheet 的 'life' 板】, 不另配 ——
##   后一步要把渲染图重索引到那块板(最近邻), 这里随手配的色会被映射到**别的档**上。
##   上一版就是这么串的: 我配 (160,240,130) 想要主绿, 落到了 jade 板的 2 号档
##   (110,200,148) 也就是**薄荷青** ⇒ 屏幕上和青色龟同色系, 泛光一糊读成白片。
##   ⇒ 想要哪一档就写哪一档的原值, 映射才是恒等的。
C_CORE = _srgb(238, 255, 232)     # life[0] 芯高光
C_MID = _srgb(104, 244, 112)      # life[2] 主绿 ← 粒子主体, 屏上要一眼是绿的
C_EDGE = _srgb(66, 188, 80)       # life[3] 暗绿(四根芒)


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
    ## ★★色彩管线必须【显式钉死】才是恒等的。Blender 5.2 默认 view_transform = AgX,
    ##   AgX 会把饱和色往白里压 —— 烤出来的绿根本不是我写的那个绿。
    ##   标定过(烤五块纯色量回来): Standard + look=None ⇒ 输入输出**逐字节相同**;
    ##   少设 look 那一项就不保证。
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0        # x,y ∈ [-1,1]
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


def poly(name, pts, mat):
    verts = [Vector((p[0], p[1], 0.0)) for p in pts]
    faces = [tuple(range(len(pts)))]
    me = bpy.data.meshes.new(name)
    me.from_pydata([list(v) for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def build(k, m_core, m_mid, m_edge):
    """一粒: 四根芒(翠绿) + 中层菱形(黄绿) + 亮芯(近白)。"""
    obs = []
    L = RAY_LEN[k % len(RAY_LEN)]
    ## ① 四根芒 —— 上下左右各一根细长三角
    for ang in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        ca, sa = math.cos(ang), math.sin(ang)

        def rot(x, y):
            return (x * ca - y * sa, x * sa + y * ca)
        obs.append(poly("ray%d_%d" % (k, int(math.degrees(ang))),
                        [rot(0.0, RAY_W), rot(L, 0.0), rot(0.0, -RAY_W)], m_edge))
    ## ② 中层菱形
    r2 = CORE_R * 3.4        # 中层绿菱形: 芯缩小后这一层要接上, 否则粒子整体变小
    obs.append(poly("mid%d" % k, [(0, r2), (r2, 0), (0, -r2), (-r2, 0)], m_mid))
    ## ③ 亮芯
    obs.append(poly("core%d" % k, [(0, CORE_R), (CORE_R, 0), (0, -CORE_R), (-CORE_R, 0)], m_core))
    return obs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=96)
    ap.add_argument("--frames", type=int, default=4)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    m_core = flat("core", C_CORE)
    m_mid = flat("mid", C_MID)
    m_edge = flat("edge", C_EDGE)
    for k in range(a.frames):
        obs = build(k, m_core, m_mid, m_edge)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob in obs:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_lifemote] 渲出 %d 帧 → %s" % (a.frames, a.out))


if __name__ == "__main__":
    main()
