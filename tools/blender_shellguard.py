# -*- coding: utf-8 -*-
"""blender_shellguard.py — 018 守护贝壳的【半壳】。

跑法(无窗口):
  blender --background --python tools/blender_shellguard.py -- --out C:/tmp/sg --px 456

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-12)
════════════════════════════════════════════════════════════════════════
用户 2026-09-11:「**你不是接了blender吗**」

`tools/gen_shell_and_spike.py` 是**手写 PIL 生成器**逐像素算半壳，
而 Blender 5.2 装着、`tools/blender_*.py` 已有 7 个在用。
`tools/vfx_discipline_audit.py` 的 B 条把它冻在台账里 —— 这一版还这笔债。
（013 的刺 v0.19.359 已经还过，半壳是这一对里剩下的那张。）

════════════════════════════════════════════════════════════════════════
 ★形态: 扇贝半壳(不是龟壳、不是碗)
════════════════════════════════════════════════════════════════════════
018 的演出是**双半壳张开 → 咬合 → 再张开消散**（`shell_system._shell_guard_fx`），
上半壳穹顶朝上、下半壳 `flip_v` 翻转 —— 所以这一张只需要**上半壳**，另一半靠翻转。

三条识别特征（缺了就读成"一个碗"）：
  ① **放射壳沟**：扇贝壳面从铰链呈放射状的粗沟
  ② **扇形轮廓**：从铰链张开成扇面，不是半圆
  ③ **奶金壳缘**：外缘一圈更亮的壳缘

★★**壳沟只做 5 条，不是 9 条**（旧生成器是 9 条）：
  这张图在游戏里 `pixel_size = 0.0145` ⇒ 屏幕上约 **31px 宽**。
  9 条沟铺在 31px 上 ≈ 每条 3.4px —— 会读成噪点，不是壳沟。
  这正是 2026-09-12 同一天连犯三次的那条（012 海藻 / 护盾罩三段填充 / 013 的刺）：
  **参考的层次不能按个数搬，要按它在屏幕上占多少像素搬。**

★尺寸保持 **76×42**（与 `_make_shellhalf_texture` 逐字相同）⇒ 调用点的换算一个字不用改。
★输出 `d0_f0.png`，再走
  `tools/pixelize_sheet.py --dirs 1 --frames 1 --cell 76 --art-h 42 --palette jade`。
  ⚠ pixelize 的格子要求是方的（它要支持 90° 旋转），而这张**不是方的** ——
  所以这里**自带下采样**，不经 pixelize（与旧生成器同一个理由）。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

W_PX, H_PX = 76, 42        # 最终尺寸(与原实现逐字相同)

RIB_N = 5                  # ★放射壳沟条数 —— 见头注: 31px 宽塞不下 9 条
FAN_DEG = 178.0            # 扇面张角(度) —— ★第一版 150° 只占 72×31, 旧的是 76×40; 填满
SQUASH = 1.00              # (保留: 竖向跨度现在由 VSPAN 管)
RIM_T = 0.14               # 奶金壳缘占外缘多厚(占半径)
HINGE_W = 0.22             # 铰链块半宽(占半径)
HINGE_H = 0.10             # 铰链块高

## 玉青板 —— 直接写**锁定调色板的 sRGB 0-255**, 再转线性给 Blender。
## ★★第一版把 sRGB 数当线性值填进 emission ⇒ 渲出来**整片发白**
##   (色数只剩 3, 960 个像素是最亮那一档), 壳缘/铰链/暗沟全没了。
##   并排渲出来一看就知道比旧的差 —— memory `fb-my-thresholds-degrade-good-assets`:
##   **改素材前先并排渲出来自己看**。
def _srgb(r, g, b):
    """sRGB 0-255 → 线性 0-1(Blender 的 emission 吃线性)。"""
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


JADE_HI = _srgb(184, 232, 200)
JADE_MID = _srgb(110, 200, 148)
JADE_LO = _srgb(58, 150, 104)
JADE_DARK = _srgb(16, 54, 44)
RIM = _srgb(255, 235, 174)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for it in list(blk):
            blk.remove(it)


def setup_render(px_w, px_h):
    sc = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    sc.render.resolution_x = px_w
    sc.render.resolution_y = px_h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.0          # x 方向 -1..1
    cam = bpy.data.objects.new("cam", cd)
    cam.location = Vector((0.0, 0.0, 5.0))
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam


def flat_material(name, rgba):
    """纯自发光平涂 —— 像素风要的是锁定色阶, 不是真实光照的连续渐变。"""
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


## ★★相机口径: ortho_scale=2.0 刷的是**长边**(x ∈ [-1,1]),
##   竖直只覆盖 y ∈ [-0.553, 0.553](按 76:42 的画幅比)。
##   第一/二版我把壳建在 y ∈ [-1, 0] ⇒ **一半在画面外**, 所以越调越小
##   (68×21, 而旧的是 76×40)。这不是形状问题是**取景问题** ——
##   把“做得不好看”和“没取对景”分开(memory `fb-clean-vfx-stage-not-squint` 同族)。
Y0 = -0.50                 # 铰链所在的底线(画面底部)
VSPAN = 1.00               # 穹顶往上的跨度 ⇒ 顶部落在 +0.50


def _pt(ang, r):
    """扇面上的一点。铰链在下缘中点(0, Y0), 穹顶朝上。"""
    return Vector((math.cos(ang) * r, Y0 + math.sin(ang) * r * VSPAN, 0.0))


def wedge(name, a0, a1, r0, r1, mat, seg=10):
    """一段环形扇块(a0..a1 角, r0..r1 半径)。"""
    verts, faces = [], []
    for i in range(seg + 1):
        a = a0 + (a1 - a0) * i / float(seg)
        verts.append(_pt(a, r0))
        verts.append(_pt(a, r1))
    for i in range(seg):
        k = 2 * i
        faces.append((k, k + 1, k + 3, k + 2))
    me = bpy.data.meshes.new(name)
    me.from_pydata([list(v) for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def build_shell():
    """整片半壳: 放射壳沟(明暗交替) + 奶金壳缘 + 深壳底 + 铰链块。"""
    obs = []
    half = math.radians(FAN_DEG) * 0.5
    a_lo = math.pi * 0.5 - half
    a_hi = math.pi * 0.5 + half
    step = (a_hi - a_lo) / float(RIB_N * 2)     # 每条沟 = 一亮一暗两片
    r_rim = 1.0
    r_body = 1.0 - RIM_T

    ## ① 壳身: 放射沟 —— 亮片/暗片交替, **硬边**(各自是独立多边形, 不是渐变)
    m_hi = flat_material("jade_hi", JADE_HI)
    m_mid = flat_material("jade_mid", JADE_MID)
    m_lo = flat_material("jade_lo", JADE_LO)
    for i in range(RIB_N * 2):
        a0 = a_lo + step * i
        a1 = a0 + step
        m = m_hi if i % 2 == 0 else m_lo
        obs.append(wedge("rib%d" % i, a0, a1, 0.0, r_body, m))

    ## ② 中段带一圈中间调 —— 让壳面不是只有两档(但只加一档, 31px 塞不下更多)
    obs.append(wedge("band", a_lo, a_hi, r_body * 0.42, r_body * 0.60, m_mid, seg=26))

    ## ③ 奶金壳缘
    obs.append(wedge("rim", a_lo, a_hi, r_body, r_rim, flat_material("rim", RIM), seg=30))

    ## ④ 铰链块(壳底那一小段) —— 有它才读得出"这是壳的合拢边"
    m_dark = flat_material("jade_dark", JADE_DARK)
    verts = [Vector((-HINGE_W, Y0, 0.0)), Vector((HINGE_W, Y0, 0.0)),
             Vector((HINGE_W, Y0 + HINGE_H, 0.0)), Vector((-HINGE_W, Y0 + HINGE_H, 0.0))]
    me = bpy.data.meshes.new("hinge")
    me.from_pydata([list(v) for v in verts], [], [(0, 1, 2, 3)])
    me.update()
    ob = bpy.data.objects.new("hinge", me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(m_dark)
    obs.append(ob)
    return obs


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=456, help="渲染宽(高按 76:42 等比)")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)

    clear_scene()
    setup_render(a.px, int(round(a.px * H_PX / float(W_PX))))
    for _ob in build_shell():
        pass
    bpy.context.scene.render.filepath = os.path.join(a.out, "d0_f0.png")
    bpy.ops.render.render(write_still=True)
    print("[blender_shellguard] 渲出半壳 → %s" % a.out)


if __name__ == "__main__":
    main()
