# -*- coding: utf-8 -*-
"""blender_bladder_fx.py — 064 溺者的浮囊【触发 / 破裂】两段: 浮起、炸开、诅咒水波。

跑法(无窗口):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_bladder_fx.py -- --out C:/tmp/bladder_fx
  python tools/pixelize_sheet.py C:/tmp/bladder_fx/rise --dirs 8 --frames 1 --cell 72 --art-h 72 --palette drown_curse -o assets/sprites/vfx/eq064-bladder-rise.png
  python tools/pixelize_sheet.py C:/tmp/bladder_fx/pop  --dirs 8 --frames 1 --cell 72 --art-h 72 --palette drown_curse -o assets/sprites/vfx/eq064-bladder-pop.png
  python tools/pixelize_sheet.py C:/tmp/bladder_fx/wave --dirs 6 --frames 1 --cell 96 --art-h 96 --palette drown_curse -o assets/sprites/vfx/eq064-curse-wave.png

════════════════════════════════════════════════════════════════════════
 ★由来 (2026-09-15)
════════════════════════════════════════════════════════════════════════
用户看 064 验收视频:「不太行，得思考重做，**思考怎么贴合装备效果**」。
持有态(套在腰上、一格格瘪下去)已在 v0.19.392 换成烘焙浮囊(tools/blender_bladder.py);
触发与破裂两段还是程序图形(破裂 = `bladder_burst` 的程序圆盘 + 圆环)。方案书 20260915f「064 分段表」:
  ① 触发: 残血那一刻, 一只旧浮囊从脚下的暗水里浮上来套住龟   —— 本脚本 rise(8 帧)
  ③ 破裂: 浮囊炸开, 暗水向外涌到 300 码, 圈内敌人中咒         —— 本脚本 pop(8 帧) + wave(6 帧)

★第一版试渲作废(我自己逐帧看的): 浮起第 2~3 帧浮囊与水面被帧底硬切(读成裁剪不是出水);
  炸开只剩一圈细椭圆线 + 一块平涂紫椭圆(= 被否过的「纯色圆盘」); 水波是实心平涂 + 完美同心圆(= 靶心 / 程序环)。
  ⇒ 第二版: 水与雾一律着色器出层次(径向渐变 + 两层噪波, 泡沫边碎开、水面有流纹); 浮起整体上移留帧底余量,
    前半片水面挡在浮囊前面(读成从水里冒出来); 炸开碎片放大加多 + 水花 + 噪波雾团。
★第二版贴边(逐帧量离格边距离): 48 格里浮囊本体就占 46 像素, 出水那几帧浮囊与水面被帧底切、水花与碎片出左右边;
  炸开第 0 / 2 帧的白芯是一块平涂白椭圆(= 白球)。⇒ 第三版浮起 / 炸开改 72 格(texel 不变, 只是留边)+ 相机上移, 白芯换八角星芒。

★三张图与持有态共用同一套几何与尺子(import tools/blender_bladder.py):
  rise / pop: 相机正交 3.0、720 像素渲、72 格 ⇒ 每格 1/24 单位, texel 与持有态(2.0 / 480 / 48 格)相同。
    相机上移: 帧 y ∈ [FEET_Y − 0.45, FEET_Y + 2.55] ⇒ 脚底离帧底 0.45 单位, 帧中心在脚底上方 1.05 单位;
    浮囊中心在脚底上方 0.78(= 引擎 BLADDER_UP 0.80 米)。引擎按「帧中心 = 脚底沿相机上方向 +1.05 单位」摆。
  wave: 正俯视贴地圈, 泡沫外沿到半径 0.96 ⇒ 96 格里外径约 92 像素, 引擎按外径 = 2 × 300 码设 pixel_size。
★诅咒水波第 0 帧就画到外沿: 结算(`_ghost_break` 给 300 码内敌人上诅咒)发生在破裂那一步,
  演出到边那一帧必须就是这一步 —— 不做「0.75 秒扩散到边」(那是演出到达晚于结算, 缺陷家族之一)。
"""
import argparse
import math
import os
import sys

import bpy   # noqa: E402
from mathutils import Vector   # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_bladder as bb   # noqa: E402

FEET_Y = -0.72           # 脚底(正交 2.0 ⇒ 帧 y ∈ [−1, 1]; 下面留 0.28 给水面椭圆, 不贴帧底)
HOLD_Y = FEET_Y + 0.78   # 持有态浮囊中心(与引擎 BLADDER_UP 同一个高度)
WATER_SQ = 0.32          # 脚下水面椭圆纵横比

## sRGB 0-255 调色(pixelize 锁到 drown_curse)
C_FOAM = (232, 250, 244)
C_WATER_HI = (96, 170, 176)
C_DARK = (24, 44, 52)
C_CURSE_HI = (196, 170, 240)
C_CURSE = (128, 96, 190)
C_CURSE_DK = (78, 56, 124)


class Shade:
    """一个发光材质: 渐变因子 → 颜色带(含透明度) → 自发光 × 透明混合(同 blender_ember_laser 的做法)。"""

    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        if hasattr(self.m, "surface_render_method"):
            self.m.surface_render_method = "BLENDED"
        self.m.use_backface_culling = False
        self.nt = self.m.node_tree
        for n in list(self.nt.nodes):
            self.nt.nodes.remove(n)
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        tc = self.nt.nodes.new("ShaderNodeTexCoord")
        self.sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(tc.outputs["Generated"], self.sep.inputs["Vector"])
        self.gen = tc.outputs["Generated"]

    def math(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = float(v)
            else:
                self.nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    def noise(self, scale, loc, detail=5.0):
        mp = self.nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = scale
        mp.inputs["Location"].default_value = loc
        self.nt.links.new(self.gen, mp.inputs["Vector"])
        nz = self.nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = detail
        self.nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
        return nz.outputs["Fac"]

    def radial(self):
        dx = self.math("MULTIPLY", self.math("SUBTRACT", self.sep.outputs["X"], 0.5), 2.0)
        dy = self.math("MULTIPLY", self.math("SUBTRACT", self.sep.outputs["Y"], 0.5), 2.0)
        return self.math("SQRT", self.math("ADD", self.math("MULTIPLY", dx, dx), self.math("MULTIPLY", dy, dy)))

    def finish(self, fac, stops, strength=1.0):
        """stops = [(位置, (r,g,b), 不透明度), ...]"""
        ramp = self.nt.nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.interpolation = "LINEAR"
        els = cr.elements
        while len(els) > 1:
            els.remove(els[-1])
        els[0].position = stops[0][0]
        els[0].color = bb._srgb(*stops[0][1], stops[0][2])
        for pos, col, a in stops[1:]:
            e = els.new(min(max(pos, 0.0), 1.0))
            e.color = bb._srgb(*col, a)
        self.nt.links.new(fac, ramp.inputs["Fac"])
        em = self.nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = strength
        self.nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
        tr = self.nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = self.nt.nodes.new("ShaderNodeMixShader")
        self.nt.links.new(ramp.outputs["Alpha"], mix.inputs["Fac"])
        self.nt.links.new(tr.outputs[0], mix.inputs[1])
        self.nt.links.new(em.outputs[0], mix.inputs[2])
        self.nt.links.new(mix.outputs[0], self.out.inputs["Surface"])
        return self.m


def flat_emit(name, col, strength=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Color"].default_value = bb._srgb(*col)
    emi.inputs["Strength"].default_value = strength
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    return mat


def ellipse(name, radius, squash, cy, mat, z=0.0, a0=0.0, a1=2.0 * math.pi, segs=48):
    """屏幕平面(或贴地俯视)里的椭圆扇面; a0..a1 只画一段角度(前半片水面用)。
    ★顶点 UV/Generated 按包围盒归一 ⇒ 着色器里 radial() 在外沿 = 1。整圆时包围盒对称; 半片时我们仍按整圆建顶点再删面, 保证归一一致。"""
    verts = [(0.0, cy, z)]
    for i in range(segs + 1):
        a = 2.0 * math.pi * i / segs
        verts.append((math.cos(a) * radius, cy + math.sin(a) * radius * squash, z))
    faces = []
    for i in range(segs):
        am = 2.0 * math.pi * (i + 0.5) / segs
        if a0 <= am <= a1:
            faces.append((0, 1 + i, 2 + i))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.context.collection.objects.link(ob)
    return ob


def water_mat(name, phase, rim_hi=True):
    """脚下暗水面: 中间深、边上一圈亮涟漪, 噪波让边碎开。"""
    s = Shade(name)
    r = s.radial()
    nz = s.noise((6.0, 6.0 / WATER_SQ, 1.0), (phase, phase * 0.7, 0.0))
    fac = s.math("ADD", r, s.math("MULTIPLY", s.math("SUBTRACT", nz, 0.5), 0.22))
    stops = [(0.0, C_DARK, 1.0), (0.62, C_DARK, 1.0), (0.74, C_CURSE_DK, 1.0)]
    if rim_hi:
        stops += [(0.84, C_WATER_HI, 1.0), (0.93, C_FOAM, 1.0)]
    stops += [(1.0, C_WATER_HI, 0.0)]
    return s.finish(fac, stops)


def droplet(name, x, y, r, mat, z=0.5):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=r, location=(x, y, z))
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.append(mat)
    return ob


def star(name, cx, cy, r_out, r_in, n, mat, z=0.0):
    """八角星芒(闪光): 外尖内凹交替, 读成「炸开的一闪」而不是一颗白球。"""
    verts = [(cx, cy, z)]
    for i in range(n * 2):
        a = math.pi * i / n + math.pi * 0.5
        rr = r_out if i % 2 == 0 else r_in
        verts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.75, z))
    faces = [(0, 1 + i, 1 + (i + 1) % (n * 2)) for i in range(n * 2)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.context.collection.objects.link(ob)
    return ob


def bladder_at(y, level, m_teal, m_coral, m_line, scale=1.0):
    """持有态整圈(前后两半都画)挪到屏幕高度 y。"""
    parts = bb.build(level, None, m_teal, m_coral, m_line)
    for p in parts:
        p.location = Vector((0.0, y, 0.0))
        p.scale = (scale, scale, scale)
    return parts


# ─────────────────────────── rise: 从暗水里浮起 ───────────────────────────
## 帧: 0 脚下冒出暗水 · 1 水面扩开 · 2 浮囊顶从水里冒头(下半截被前半片水面挡住) · 3~4 上浮出水 + 水花
##     5 出水、水花落 · 6 到位闪一下 · 7 回到持有态亮度, 水面收小
RISE_Y = [None, None, FEET_Y + 0.16, FEET_Y + 0.26, FEET_Y + 0.52, FEET_Y + 0.70, HOLD_Y, HOLD_Y]
WATER_R = [0.34, 0.66, 0.86, 0.90, 0.86, 0.74, 0.56, 0.36]
GLOW = [0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 1.30, 0.35]


def build_rise(j):
    m_teal = bb.lit_material("teal", bb.GHOST_TEAL, GLOW[j])
    m_coral = bb.lit_material("coral", bb.FADED_CORAL, GLOW[j] * 0.7)
    m_line = bb.outline_material()
    wy = FEET_Y + 0.02
    wr = WATER_R[j]
    ## 后半片水面(浮囊后面)
    ellipse("water_back", wr, WATER_SQ, wy, water_mat("wb", j * 0.3), z=-0.6)
    if RISE_Y[j] is not None:
        bladder_at(RISE_Y[j], 0, m_teal, m_coral, m_line)
    ## 前半片水面挡在浮囊前面(画面上的下半个椭圆): 浮囊没出水的那截被水盖住
    if 2 <= j <= 4:
        ellipse("water_front", wr, WATER_SQ, wy, water_mat("wf", j * 0.3), z=0.9, a0=math.pi, a1=2.0 * math.pi)
    if 3 <= j <= 5:
        m_drop = flat_emit("drop", C_WATER_HI if j < 5 else C_FOAM)
        for k in range(8):
            a = math.pi * (0.08 + 0.84 * k / 7.0)
            rr = 0.46 + 0.20 * (j - 3)
            fall = 0.10 * (j - 3) * (j - 3)
            droplet("drop%d" % k, math.cos(a) * rr * 1.5, wy + 0.10 + math.sin(a) * rr * 0.75 - fall, 0.05, m_drop, z=1.0)


# ─────────────────────────── pop: 浮囊炸开 ───────────────────────────
## 帧: 0 满气 + 白闪 · 1 鼓胀出裂纹(最瘪那档的褶皱) · 2 炸开: 碎片 + 水花冠 + 白芯 · 3~4 碎片飞散、诅咒雾涌出
##     5~6 碎片落、雾团扩散变淡碎开 · 7 残雾几缕
def mist_mat(name, j):
    s = Shade(name)
    r = s.radial()
    n1 = s.noise((4.0, 4.0, 1.0), (j * 0.37, 0.0, 0.0))
    n2 = s.noise((11.0, 11.0, 1.0), (0.0, j * 0.53, 0.0), detail=3.0)
    fac = s.math("ADD", r, s.math("ADD", s.math("MULTIPLY", s.math("SUBTRACT", n1, 0.5), 0.45),
                                  s.math("MULTIPLY", s.math("SUBTRACT", n2, 0.5), 0.25)))
    k = [0, 0, 1.0, 0.95, 0.85, 0.72, 0.58, 0.44][j]
    stops = [(0.0, C_CURSE_HI, 1.0), (0.30 * k, C_CURSE, 1.0), (0.62 * k, C_CURSE_DK, 1.0), (0.78 * k, C_CURSE_DK, 0.0)]
    return s.finish(fac, stops)


def build_pop(j):
    m_teal = bb.lit_material("teal", bb.GHOST_TEAL, 0.5)
    m_coral = bb.lit_material("coral", bb.FADED_CORAL, 0.35)
    m_line = bb.outline_material()
    m_flash = flat_emit("flash", C_FOAM, 2.0)
    if j == 0:
        bladder_at(HOLD_Y, 0, m_teal, m_coral, m_line)
        star("flash_core", 0.0, HOLD_Y, 0.30, 0.07, 8, m_flash, z=0.8)
        return
    if j == 1:
        bladder_at(HOLD_Y, 3, m_teal, m_coral, m_line, scale=1.12)
        return
    t = (j - 2) / 5.0
    ## 诅咒雾团(噪波碎边, 不是平涂盘)
    mist_r = 0.42 + 0.50 * t
    ellipse("mist", mist_r, 0.62, HOLD_Y - 0.04 * t, mist_mat("mist", j), z=-0.3)
    if j == 2:
        star("flash_core", 0.0, HOLD_Y, 0.62, 0.12, 8, m_flash, z=0.8)
    ## 救生圈碎片: 16 片弧形残片沿圈向外飞, 越飞越往下掉
    for k in range(16):
        a = 2.0 * math.pi * (k + 0.3) / 16.0
        rr = 0.80 + 1.10 * t + 0.08 * (k % 3)
        x = math.cos(a) * rr
        y = HOLD_Y + math.sin(a) * rr * 0.42 - 0.55 * t * t
        if abs(x) < 1.35 and FEET_Y - 0.35 < y < FEET_Y + 2.40:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.4))
            ob = bpy.context.active_object
            ob.rotation_euler = (0.0, 0.0, a + math.pi * 0.5 + 0.8 * j * (1 if k % 2 else -1))
            sz = 1.0 - 0.45 * t
            ob.scale = (0.16 * sz, 0.055 * sz, 0.05)
            ob.data.materials.append(m_teal if k % 2 == 0 else m_coral)
    ## 水花冠: 炸开那两帧往上溅
    if 2 <= j <= 4:
        m_drop = flat_emit("drop", C_WATER_HI if j > 2 else C_FOAM)
        for k in range(10):
            a = math.pi * (0.05 + 0.9 * k / 9.0)
            rr = 0.55 + 0.55 * t
            droplet("spray%d" % k, math.cos(a) * rr * 1.2, HOLD_Y + math.sin(a) * rr * 0.9 - 0.4 * t * t, 0.05, m_drop, z=0.9)


# ─────────────────────────── wave: 诅咒水波(贴地, 正俯视) ───────────────────────────
## 帧: 0 泡沫外沿已到 300 码 + 沿外沿一圈暗水 · 1 暗水往里涌 · 2 圈内满是暗水与诅咒紫流纹 · 3 外沿泡沫变暗
##     4 暗水碎成水斑往外退 · 5 只剩外沿几段碎泡沫
WAVE_R = 0.96
WAVE_STOPS = [
    [(0.0, C_DARK, 0.0), (0.66, C_DARK, 0.0), (0.72, C_DARK, 1.0), (0.82, C_CURSE_DK, 1.0), (0.88, C_CURSE_HI, 1.0), (0.94, C_FOAM, 1.0), (1.0, C_FOAM, 0.0)],
    [(0.0, C_DARK, 0.0), (0.36, C_DARK, 0.0), (0.44, C_DARK, 1.0), (0.62, C_CURSE_DK, 1.0), (0.76, C_DARK, 1.0), (0.87, C_CURSE_HI, 1.0), (0.94, C_FOAM, 1.0), (1.0, C_FOAM, 0.0)],
    [(0.0, C_DARK, 1.0), (0.24, C_CURSE_DK, 1.0), (0.40, C_DARK, 1.0), (0.58, C_CURSE, 1.0), (0.70, C_DARK, 1.0), (0.86, C_CURSE_HI, 1.0), (0.93, C_FOAM, 1.0), (0.99, C_FOAM, 0.0)],
    [(0.0, C_DARK, 1.0), (0.30, C_CURSE_DK, 1.0), (0.52, C_DARK, 1.0), (0.72, C_CURSE_DK, 1.0), (0.88, C_CURSE, 1.0), (0.96, C_CURSE_HI, 0.0)],
    [(0.0, C_DARK, 0.0), (0.30, C_DARK, 0.0), (0.38, C_DARK, 1.0), (0.54, C_CURSE_DK, 1.0), (0.60, C_CURSE_DK, 0.0), (0.82, C_CURSE, 0.0), (0.88, C_CURSE, 1.0), (0.94, C_CURSE, 0.0)],
    [(0.0, C_DARK, 0.0), (0.80, C_CURSE_DK, 0.0), (0.88, C_CURSE_DK, 1.0), (0.92, C_CURSE, 1.0), (0.95, C_CURSE, 0.0)],
]
WAVE_NOISE = [0.12, 0.18, 0.22, 0.24, 0.42, 0.50]


def build_wave(j):
    s = Shade("wave")
    r = s.radial()
    n1 = s.noise((5.0, 5.0, 1.0), (j * 0.21, j * 0.13, 0.0))
    n2 = s.noise((16.0, 16.0, 1.0), (0.4, j * 0.31, 0.0), detail=2.0)
    amp = WAVE_NOISE[j]
    fac = s.math("ADD", r, s.math("ADD", s.math("MULTIPLY", s.math("SUBTRACT", n1, 0.5), amp),
                                  s.math("MULTIPLY", s.math("SUBTRACT", n2, 0.5), amp * 0.45)))
    ## ★外沿收边: 半径过 1.0 一律推到透明, 泡沫不会被方形面片切角(余烬地光那一版的教训)
    fac = s.math("MAXIMUM", fac, s.math("MULTIPLY", s.math("SUBTRACT", r, 0.94), 20.0))
    ellipse("wave", WAVE_R, 1.0, 0.0, s.finish(fac, WAVE_STOPS[j]), z=0.0, segs=96)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=int, default=480)
    ap.add_argument("--only", default="", help="rise,pop,wave 里挑几组")
    a = ap.parse_args(argv)
    jobs = [("rise", 8, build_rise), ("pop", 8, build_pop), ("wave", 6, build_wave)]
    only = [x for x in a.only.split(",") if x]
    n = 0
    for sub, count, fn in jobs:
        if only and sub not in only:
            continue
        os.makedirs(os.path.join(a.out, sub), exist_ok=True)
        for j in range(count):
            bb.clear_scene()
            if sub == "wave":
                bb.setup_render(a.px)
            else:
                ## 72 格: 3.0 单位 / 720 像素 ⇒ texel 与持有态相同; 相机上移让脚底离帧底 0.45
                bb.setup_render(int(a.px * 1.5))
                cam = bpy.context.scene.camera
                cam.data.ortho_scale = 3.0
                cam.location.y = FEET_Y - 0.45 + 1.5
            fn(j)
            bpy.context.scene.render.filepath = os.path.join(a.out, sub, "d%d_f0.png" % j)
            bpy.ops.render.render(write_still=True)
            n += 1
    print("[blender_bladder_fx] 渲出 %d 张 → %s" % (n, a.out), flush=True)


if __name__ == "__main__":
    main()
