# -*- coding: utf-8 -*-
"""blender_urchinspike.py — 013 炙烤海胆的【放射刺】(16 向预烤)。

跑法(无窗口):
  blender --background --python tools/blender_urchinspike.py -- --out C:/tmp/us --dirs 16 --px 384

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-11)
════════════════════════════════════════════════════════════════════════
用户:「**你不是接了blender吗**」

v0.19.355 那轮我给 013 重做刺时, 用的是**手写 PIL 生成器**(`tools/gen_shell_and_spike.py`)
逐像素算锥形 —— 而 Blender 5.2 装着、6 个 `tools/blender_*.py` 在用(003 冲击环、008 珊瑚刺
都是它烤的)。memory `fb-search-repo-before-building` 说的就是这个, 我又犯了一次。
现在 `tools/vfx_discipline_audit.py` 的 B 条把它冻在台账里, 这次是来还这笔债。

★为什么不直接用 `blender_coralspike.py`: 那是 **008 的招牌** ——
  珊瑚刺的识别特征是「一节一节的鼓包 + 两根侧枝 + 骨白尖」。
  海胆刺是**完全不同的东西**: 细长、光滑、带**纵向棱**、根粗尖极细、通体紫。
  铁律 [[fb-no-asset-reuse-unless-told]]:「新内容一律新素材, 别拿别的顶替」。
  ⇒ 流水线(相机/方向烘焙/输出命名)照抄那份, **形态与材质是 013 自己的**。

★怎么让它读成【海胆刺】而不是【箭/针】(40 像素下能不能分开, 全看这三条):
  ① **纵向棱**: 海胆刺表面有细密的纵沟, 侧影上是规律的窄条明暗 —— 这是最强的识别特征
  ② **根部有环座**: 刺是长在壳上的, 根部有一小圈鼓起的关节座; 箭没有
  ③ **尖极细**: 长宽比拉到 ~9:1, 比珊瑚刺瘦得多

★★为什么要**预烤 16 个方向**而不是运行时旋转:
  刺是贴地精灵(`axis = AXIS_Y`), 被任意角旋转会重采样, 像素网格当场碎
  —— 010 激光长刃那一轮就是栽在 `rotation = Vector3(0, -ang, 0)` 上。
  ⇒ 方向烤进素材, 运行时 `rotation` 恒 0, 只选帧。
  方向由 `_ground_dir_frame(dir, 16)` 决定, 与判定/移动方向同一套口径。

★输出 `d{k}_f0.png`(横排), 再走
  `tools/pixelize_sheet.py --dirs 16 --frames 1 --cell 32 --art-h 32 --palette venom`。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

## ── 形态参数(海胆刺, 不是珊瑚刺) ──────────────────────────────────
## ★★ 1:1 对照改过一次(2026-09-12)。第一版 RIDGE_AMP=0.16 / BASE_KNOB_AMP=0.55,
##   并排一看: 7 道棱铺在 **27 像素**上 ≈ 每道 4px ⇒ 轮廓读成**一节节的疙瘯**(毛毛虫),
##   根部环座鼓成一颗珠子 ⇒ 读成「棍子上串了个球」。
##   —— 这正是 `gen_shield_shell.py` 里我前一天刚写下的那条:
##   **参考的层次不能按个数搬, 要按它占多少像素搬**。
## ⇒ 棱不再改**轮廓**(那个尺寸下只会变疙瘯), 改靠材质的横向 ramp 做**亮芯线**;
##   环座压成一圈薄领。轮廓只管一件事: 干净的针形收尖。
## ★★第三版(2026-09-12, 1:1 真场景实拍后): 6.2:1 的针形在游戏里**太细了** ——
##   屏幕上刺才 26px 长、根部 3px、尖端 1px ⇒ 读成几根**须**, 不是刺。
##   而且一半被护盾罩挡住、紫环又比它抢眼。
## ★这是同一天第三次犯同一条(海藻 / 护罩三段填充 / 这根刺):
##   **参考的比例不能按解剖学搬, 要按它在屏幕上占多少像素搬**。
##   真海胆刺是 9:1, 但 26px 的预算里 9:1 等于一条线。往粗短调到 ~4:1。
SPIKE_LEN = 0.72        # 刺全长(占画布)
SPIKE_W = 0.165         # 根部最宽处 —— 加粗, 保证屏幕上根部 ≥ 4px
TIP_FRAC = 0.16         # 尖段占比(这一段用更亮的材质)
RIDGE_N = 7             # (保留参数但 AMP=0: 棱不进轮廓)
RIDGE_AMP = 0.0         # ★ 32px 下轮廓起伏一律读成疙瘯, 归零
BASE_KNOB = 0.22        # 根部薄领(刺长在壳上, 根部略粗)
BASE_KNOB_AMP = 0.20
SEG = 46                # 沿刺长的分段数(够密才不露多边形)

## 紫(与 pixelize_sheet.PALETTES["venom"] 同色系; 刺自带色, 不靠 modulate)
RAMP = [(0.29, 0.11, 0.46, 1.0), (0.50, 0.24, 0.75, 1.0), (0.69, 0.42, 0.91, 1.0)]
TIP_RAMP = [(0.69, 0.42, 0.91, 1.0), (0.84, 0.67, 0.98, 1.0), (0.96, 0.91, 1.0, 1.0)]


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
    sc.view_settings.view_transform = "Standard"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 1.0
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def build_material(name, ramp):
    """自发光渐变材质: 沿物体 X(横向)取色 ⇒ 棱的明暗就是这条 ramp 在起作用。"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Strength"].default_value = 1.0
    cr = nt.nodes.new("ShaderNodeValToRGB")
    for i, c in enumerate(ramp):
        pos = i / float(len(ramp) - 1)
        if i < len(cr.color_ramp.elements):
            cr.color_ramp.elements[i].position = pos
            cr.color_ramp.elements[i].color = c
        else:
            e = cr.color_ramp.elements.new(pos)
            e.color = c
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    tex = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["X"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], emi.inputs["Color"])
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    return mat


def _half_w(t):
    """刺身半宽。t=0 尖 → t=1 根。

    ★三条识别特征都在这里:
      · 极细的尖(t^0.62 收得快)
      · 纵向棱 → 用 RIDGE 在**轮廓**上做规律起伏(侧影上读成细密纵沟)
      · 根部环座 → 最后一段鼓起来
    """
    base = (SPIKE_W * 0.5) * (t ** 0.62)
    ridge = 1.0 + RIDGE_AMP * math.sin(math.tau * RIDGE_N * t)
    knob = 1.0
    if t > 1.0 - BASE_KNOB:
        u = (t - (1.0 - BASE_KNOB)) / BASE_KNOB
        knob = 1.0 + BASE_KNOB_AMP * math.sin(math.pi * u)
    return base * ridge * knob


def build_spike(body_mat, tip_mat):
    """一根海胆刺: 尖朝 +Y。返回 [(obj, mat)]。"""
    parts = []
    for seg_name, t0, t1, mat in (("tip", 0.0, TIP_FRAC, tip_mat),
                                  ("shaft", TIP_FRAC, 1.0, body_mat)):
        verts, faces = [], []
        n = max(4, int(SEG * (t1 - t0)))
        for i in range(n + 1):
            t = t0 + (t1 - t0) * i / float(n)
            y = SPIKE_LEN * (0.5 - t)          # t=0 在 +Y(尖)
            w = _half_w(t)
            verts.append(Vector((-w, y, 0.0)))
            verts.append(Vector((w, y, 0.0)))
        for i in range(n):
            a, b = 2 * i, 2 * i + 1
            faces.append((a, b, b + 2, a + 2))
        me = bpy.data.meshes.new(seg_name)
        me.from_pydata([list(v) for v in verts], [], faces)
        me.update()
        ob = bpy.data.objects.new(seg_name, me)
        bpy.context.collection.objects.link(ob)
        parts.append((ob, mat))
    return parts


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=384)
    ap.add_argument("--dirs", type=int, default=16)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px)
    body = build_material("urchin", RAMP)
    tip = build_material("urchintip", TIP_RAMP)

    n = max(1, a.dirs)
    for k in range(n):
        parts = build_spike(body, tip)
        ## 刺尖建在 +Y(屏幕 90°)。要指向角 θ 就转 θ-90°。
        rot = math.tau * k / float(n) - math.pi * 0.5
        for ob, _m in parts:
            ob.rotation_euler = (0.0, 0.0, rot)
        for ob, mat in parts:
            ob.data.materials.append(mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, "d%d_f0.png" % k)
        bpy.ops.render.render(write_still=True)
        for ob, _m in parts:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("[blender_urchinspike] 渲出 %d 向 → %s" % (n, a.out))


if __name__ == "__main__":
    main()
