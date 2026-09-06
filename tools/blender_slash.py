# -*- coding: utf-8 -*-
"""blender_slash.py — 在 Blender 里【用代码造】剑气, 渲成方向精灵表。

跑法(无窗口):
  blender --background --python tools/blender_slash.py -- --out C:/tmp/slash_blender

★★为什么要走 Blender(2026-09-06)
  用户：「我最在意的就是对齐 lol，但你就是不会去抄」「人家用blender呢」。
  查 OpenAI 官方页面的原话, 机制是这样的:
    · "GPT-6 Astra also brings stronger **visual judgment** to the websites, games,
       applications, and **renderings it builds**."
    · "models a house in **Blender** and turns it into a walkable scene in Unreal Engine 5"
    · "BenchCAD tests whether models can reconstruct 3D objects from multi-view renders
       **by generating CAD code**."
  ⇒ 模型**不画图**, 它**写代码驱动 DCC 工具造几何**, 再**看渲染结果**改。
    美术是"程序造出来 + 盯着渲染反复改"的, 不是"求它给一张图"。

★这条路解决的、生成器解决不了的三件事:
  ① **横截面剖面可以直接写进材质**。LoL 参考实测(见 tools/vfx_lol_profile.py 头注):
     内侧深绿 65 → 亮绿 189 → 转青 210 → 外缘近白 237, 白只占 12.4%。
     求 PixelLab 出这个我花了七轮; 在这里它就是一条 ColorRamp, 一次写死。
  ② **8/4 方向是原生渲染, 零重采样**。今天卡了半天的
     「45° 旋转对像素有损 ⇒ 需要第二张基准帧 ⇒ 两条路都拿不到」在这里根本不存在。
  ③ **确定、可复现、可进门禁**。同一份脚本永远出同一张图, 不看运气。

★流水按 2026 行业做法: **generate large → downscale → re-index → hand-clean**。
  这里负责前两步(大图渲染 + 缩小), 减色/重索引在 tools/pixelize_sheet.py。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402  (只有 Blender 内部跑得到)
from mathutils import Vector   # noqa: E402


# ── 形状参数(全部来自实测, 不是拍的) ─────────────────────────────
ARC_DEG = 104.0      # 弧包角。LoL 参考帧实测 ~120°(见 vfx_sheet_audit 头注的量法)
ARC_R = 1.00         # 弧半径
W_MAX = 0.30         # 最肥处的带宽(相对半径)
TAPER = 0.62         # 收尖指数: w = W_MAX * sin(pi*t)^TAPER —— 越小越"两头拖得长"
SEG = 96             # 沿弧的分段数(够密才不会看出折线)

## 横截面配色(v: 0=外缘/前导 → 1=内侧/尾)。
## ★★颜色必须照 LoL 参考帧实测的【亮度阶梯】: 237 / 210 / 189 / 140 / 95 / 65,
##   而且要和 tools/pixelize_sheet.py 的锁定调色板是同一组 —— 后面那步要重索引到它。
##   我第一版随手配了 (1.00,0.88,0.55)=(255,224,140) 当 1 号色, 它亮度 225,
##   而判据里"白"是 亮度>215 ⇒ 两色被算成白, white_pct 卡在 38% 下不来(参考 12.4%)。
RAMP = [
    (0.000, (245 / 255.0, 238 / 255.0, 205 / 255.0)),   # 亮度 237 最外缘
    (0.130, (250 / 255.0, 208 / 255.0, 110 / 255.0)),   # 亮度 211
    (0.320, (240 / 255.0, 185 / 255.0, 80 / 255.0)),    # 亮度 191
    (0.560, (195 / 255.0, 128 / 255.0, 40 / 255.0)),    # 亮度 139
    (0.790, (150 / 255.0, 85 / 255.0, 28 / 255.0)),     # 亮度  99
    (1.000, (110 / 255.0, 58 / 255.0, 18 / 255.0)),     # 亮度  70 内侧尾
]

## ★白边是【恒定世界粗细】的一条线, 不是"宽度的百分之几"。
##   按比例算的话弧收尖处宽度只剩几像素, 11% 取整就成了 50% ⇒ 白占比爆掉。
##   实现: UV 的 v 不再用 0..1 归一, 而是直接存【离外缘的世界距离 / RIM_ABS】,
##   于是 ramp 的第一档就是恒定粗细的那条线。
RIM_ABS = 0.026


def srgb_to_linear(c):
    """sRGB(0..1) → 线性。

    ★★Blender 的 ColorRamp / 各种颜色输入吃的是【线性】色, 而我们的调色板是 sRGB 数值。
      直接喂 sRGB 会在渲染保存时再做一次 gamma 编码 ⇒ **整体提亮一整档**。
      实测: 设 (250,208,110) 渲出 (253,233,176)、设 (195,128,40) 渲出 (226,188,110),
      于是 white_pct 卡在 42~58% 下不来(参考 12.4%)。探针打出来才看见, 光看图看不出。
    """
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_arc(name="slash"):
    """造一条【沿圆弧的带】, 两端收成尖。

    ★三排顶点(不是两排): 外缘 / 白边内侧(离外缘恒 RIM_ABS) / 带内侧。
      UV 的 v 因此是**分段线性**: 0 → 0.130 → 1.0。
      ⇒ ramp 的首档(白)在世界里恒为 RIM_ABS 粗, **与该处带宽无关**。
      两排的写法会让白边变成"宽度的 13%", 弧收尖处宽度只剩几像素时白就占了一半,
      实测 white_pct 卡在 38%(参考 12.4%) —— 同一个坑我在光栅化原型里踩过一次。
    """
    verts, faces, uvs = [], [], []
    half = math.radians(ARC_DEG) * 0.5
    V_RIM = RAMP[1][0]                    # 白边在 ramp 空间的结束位置
    for i in range(SEG + 1):
        t = i / float(SEG)
        a = -half + math.radians(ARC_DEG) * t
        cx, cy = math.sin(a) * ARC_R, math.cos(a) * ARC_R
        nx, ny = math.sin(a), math.cos(a)
        w = W_MAX * (math.sin(math.pi * t) ** TAPER)
        rim = min(RIM_ABS, w * 0.9)       # 尖端处带宽不足时按比例退让, 不许翻转
        verts.append((cx, cy, 0.0))                                   # 外缘
        verts.append((cx - nx * rim, cy - ny * rim, 0.0))             # 白边内侧
        verts.append((cx - nx * w, cy - ny * w, 0.0))                 # 带内侧
        uvs.append((t, 0.0))
        uvs.append((t, V_RIM))
        uvs.append((t, 1.0))
    for i in range(SEG):
        r0, r1 = i * 3, (i + 1) * 3
        faces.append((r0 + 0, r0 + 1, r1 + 1, r1 + 0))
        faces.append((r0 + 1, r0 + 2, r1 + 2, r1 + 1))

    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    ## ★★把几何平移到【自己的包围盒中心】再返回。
    ##   不这么做的话 rotation_euler 是绕物体原点(0,0,0)转, 而弧的重心在 y≈0.8,
    ##   一转就荡出相机画面 —— 实测 c1 整格是空的、c2/c3 只剩一条竖线。
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    ox = (min(xs) + max(xs)) * 0.5
    oy = (min(ys) + max(ys)) * 0.5
    for v in me.vertices:
        v.co.x -= ox
        v.co.y -= oy
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob["_span"] = max(max(xs) - min(xs), max(ys) - min(ys))
    return ob


def build_material(ob):
    """纯自发光 + 跨带宽的 ColorRamp。★这就是把 LoL 实测剖面直接焊进素材的地方。

    ★★**不许用 alpha 做衰减。** 我第一版拿 MixShader(Transparent, Emission) 让内侧变透,
      结果 white_pct 爆到 58.7% —— 探针量出来: 我设 ramp 是 (250,208,110),
      渲出来却是 (253,233,176)。原因是 **Blender 存 PNG 用直通(非预乘)alpha**,
      颜色通道会被 alpha 除回去 ⇒ **alpha 越低颜色越亮**, "内侧变透"变成了"内侧变白"。
      像素画这一步本来就要硬边 + 重索引, 衰减只该走颜色, 不该走 alpha。
    """
    mat = bpy.data.materials.new("slash_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    emis = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")

    ramp.color_ramp.interpolation = 'CONSTANT'      # ★硬边色带 = 像素画要的分层, 不要渐变
    while len(ramp.color_ramp.elements) > 1:
        ramp.color_ramp.elements.remove(ramp.color_ramp.elements[-1])
    ramp.color_ramp.elements[0].position = RAMP[0][0]
    ramp.color_ramp.elements[0].color = (*[srgb_to_linear(v) for v in RAMP[0][1]], 1.0)
    for pos, col in RAMP[1:]:
        e = ramp.color_ramp.elements.new(pos)
        e.color = (*[srgb_to_linear(v) for v in col], 1.0)

    nt.links.new(tex.outputs["UV"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Y"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emis.inputs["Color"])
    emis.inputs["Strength"].default_value = 1.0
    nt.links.new(emis.outputs["Emission"], out.inputs["Surface"])
    ob.data.materials.append(mat)
    return mat


def setup_render(w, h, span):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in \
        [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True            # 透明底
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'  # ★不要 Filmic/AgX, 否则颜色被色调映射改掉
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = span * 1.12            # ★视野按几何包围盒定, 不写死(写死会裁掉两端)
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = Vector((0.0, 0.0, 6.0))        # 几何已居中 ⇒ 相机在原点
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    return cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--w", type=int, default=512)     # ★方形画布: 4 个方向共用同一视野
    ap.add_argument("--h", type=int, default=512)
    ap.add_argument("--dirs", type=int, default=4)
    ap.add_argument("--frames", type=int, default=3)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    ob = build_arc()
    mat = build_material(ob)
    setup_render(a.w, a.h, float(ob["_span"]))

    sc = bpy.context.scene
    emis = [n for n in mat.node_tree.nodes if n.type == 'EMISSION'][0]
    ## 动画帧 = 自发光强度脉动(形状一动不动)。
    ## ★形状不许动是硬要求: 上一版 animate_image 让 4 帧的轴向摆了 75°,
    ##   实拍读出来就是"特效在自转"(门禁 ⑤ 抓的就是这条)。这里形状由几何定, 天生不会摆。
    PULSE = [1.00, 1.35, 0.78]
    for d in range(a.dirs):
        ob.rotation_euler = (0.0, 0.0, -math.radians(360.0 / a.dirs) * d)
        for f in range(a.frames):
            emis.inputs["Strength"].default_value = PULSE[f % len(PULSE)]
            sc.render.filepath = os.path.join(a.out, "d%d_f%d.png" % (d, f))
            bpy.ops.render.render(write_still=True)
    print("[blender_slash] 渲出 %d 方向 × %d 帧 → %s" % (a.dirs, a.frames, a.out))


if __name__ == "__main__":
    main()
