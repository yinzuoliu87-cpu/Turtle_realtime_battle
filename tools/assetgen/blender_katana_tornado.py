# -*- coding: utf-8 -*-
"""blender_katana_tornado.py —— 107 武士刀小将第 4 下甩出的【龙卷风】循环序列帧(2026-11-25)。

跑法(无窗口):
  blender --background --python tools/assetgen/blender_katana_tornado.py -- --out .out/katana_blend/tornado
然后 `python tools/assetgen/build_katana_sheets.py` 拼成 assets/sprites/vfx/katana-tornado.png。

由来: 用户 11-25 看武士刀录像:「这个龙卷风做的也不好，你得想办法。这个完全这个程序做的呀，太敷衍了」——
  原来是 VfxTex 细圆环 9 层叠起来、代码里转圈(bomb_eq_vfx.gd `_tornado`)。
参考(只当尺子): 英雄联盟亚索 Q3 官方技能演示(ability_0157_Q1.mp4 第 5.9~7.0 秒逐帧):
  漏斗 = 几圈很粗、半透明的青色风带一层层叠起来(底窄顶宽), 风带中段亮、边缘化开; 中心一根偏白的芯;
  底部卷起一圈深色尘土和碎屑, 跟着风转; 整体转得很快。
做法(如实): Blender 里建模 —— 风带 = 脚本生成的螺旋带状网格(每条约 0.8 圈, 底窄顶宽的漏斗半径),
  材质是自发光 + 透明混合, 透明度按「带宽中线最亮、两边化开」×「沿带长两头渐隐」× 一层沿带长的条纹噪声(风丝);
  芯 = 一个开口锥面 + 竖向条纹; 尘 = 卡通分层着色的小球团绕底部转、边转边升边缩; 碎屑 = 小石块绕中段转。
  所有运动是关键帧(按帧号算的周期函数, 首尾无缝循环), 不是物理解算。镜头 = 游戏镜头俯角 51° 的正交相机,
  游戏里当公告板放(正对相机 ⇒ 与渲染角度一致)。Cycles CPU、固定种子 ⇒ 重跑同一结果。
"""
import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

ELEV = math.radians(51.0)            # 游戏镜头俯角(battle_world_builder: pos(0,28,22) look_at(0,0.6,0))
H = 3.0                              # 漏斗高(米)
R_BASE = 0.32                        # 底部半径
R_TOP = 1.25                         # 顶部半径
FRAMES = 16                          # 一个循环的帧数(游戏里 16 帧/秒 ⇒ 风带一秒转一圈, 芯两圈)

## 颜色(sRGB): 风 = 淡青 → 白; 尘 = 灰褐三档
C_WIND_EDGE = (0.42, 0.78, 0.92)
C_WIND_MID = (0.70, 0.93, 1.00)
C_WIND_HOT = (0.96, 1.00, 1.00)
C_DUST = [(0.22, 0.20, 0.18), (0.34, 0.30, 0.27), (0.48, 0.43, 0.38)]
C_ROCK = [(0.20, 0.18, 0.17), (0.34, 0.31, 0.28), (0.50, 0.46, 0.41)]
LIGHT = Vector((-0.45, -0.55, 0.70)).normalized()


def lin(c):
	return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def radius_at(h):
	k = max(0.0, min(1.0, h / H))
	return R_BASE + (R_TOP - R_BASE) * (k ** 1.35)


# ─────────────────────────────── 材质 ───────────────────────────────
def wind_mat(name, alpha_k, streak_scale, hot=False):
	"""风带: UV.u 沿带长(0..1), UV.v 跨带宽(0..1)。
	alpha = 带宽中线最亮(1 - |2v-1|)^1.6 × 两头渐隐 sin(πu)^0.7 × 风丝条纹(沿 u 拉长的噪声) × alpha_k。
	颜色: alpha 越高越偏白(中线亮, 边缘青)。"""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	m.blend_method = 'BLEND' if hasattr(m, "blend_method") else None
	nt = m.node_tree
	nt.nodes.clear()
	N = nt.nodes.new
	L = nt.links.new
	tc = N("ShaderNodeTexCoord")
	sep = N("ShaderNodeSeparateXYZ")
	L(tc.outputs["UV"], sep.inputs["Vector"])
	## 跨带宽: 1 - |2v - 1|
	m2 = N("ShaderNodeMath"); m2.operation = 'MULTIPLY_ADD'; m2.inputs[1].default_value = 2.0; m2.inputs[2].default_value = -1.0
	L(sep.outputs["Y"], m2.inputs[0])
	ab = N("ShaderNodeMath"); ab.operation = 'ABSOLUTE'
	L(m2.outputs[0], ab.inputs[0])
	inv = N("ShaderNodeMath"); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
	L(ab.outputs[0], inv.inputs[1])
	pw = N("ShaderNodeMath"); pw.operation = 'POWER'; pw.inputs[1].default_value = 1.6
	L(inv.outputs[0], pw.inputs[0])
	## 沿带长: sin(πu)^0.7
	mu = N("ShaderNodeMath"); mu.operation = 'MULTIPLY'; mu.inputs[1].default_value = math.pi
	L(sep.outputs["X"], mu.inputs[0])
	sn = N("ShaderNodeMath"); sn.operation = 'SINE'
	L(mu.outputs[0], sn.inputs[0])
	sp = N("ShaderNodeMath"); sp.operation = 'POWER'; sp.inputs[1].default_value = 0.7
	L(sn.outputs[0], sp.inputs[0])
	## 风丝: 噪声贴图, 坐标 (u * streak_scale, v * 18) ⇒ 沿带长拉得很长的条纹
	cmb = N("ShaderNodeCombineXYZ")
	su = N("ShaderNodeMath"); su.operation = 'MULTIPLY'; su.inputs[1].default_value = streak_scale
	L(sep.outputs["X"], su.inputs[0])
	sv = N("ShaderNodeMath"); sv.operation = 'MULTIPLY'; sv.inputs[1].default_value = 18.0
	L(sep.outputs["Y"], sv.inputs[0])
	L(su.outputs[0], cmb.inputs[0]); L(sv.outputs[0], cmb.inputs[1])
	nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 1.0; nz.inputs["Detail"].default_value = 3.0
	L(cmb.outputs[0], nz.inputs["Vector"])
	nr = N("ShaderNodeMapRange"); nr.inputs[1].default_value = 0.35; nr.inputs[2].default_value = 0.65
	nr.inputs[3].default_value = 0.35; nr.inputs[4].default_value = 1.0
	L(nz.outputs["Fac"], nr.inputs[0])
	a1 = N("ShaderNodeMath"); a1.operation = 'MULTIPLY'
	L(pw.outputs[0], a1.inputs[0]); L(sp.outputs[0], a1.inputs[1])
	a2 = N("ShaderNodeMath"); a2.operation = 'MULTIPLY'
	L(a1.outputs[0], a2.inputs[0]); L(nr.outputs[0], a2.inputs[1])
	a3 = N("ShaderNodeMath"); a3.operation = 'MULTIPLY'; a3.inputs[1].default_value = alpha_k; a3.use_clamp = True
	L(a2.outputs[0], a3.inputs[0])
	## 颜色: alpha → 青 / 淡青 / 白
	ramp = N("ShaderNodeValToRGB")
	cr = ramp.color_ramp
	cr.interpolation = 'LINEAR'
	cr.elements[0].position = 0.0; cr.elements[0].color = (*lin(C_WIND_EDGE), 1.0)
	cr.elements[1].position = 1.0 if not hot else 0.6; cr.elements[1].color = (*lin(C_WIND_HOT), 1.0)
	e = cr.elements.new(0.45 if not hot else 0.25); e.color = (*lin(C_WIND_MID), 1.0)
	L(a3.outputs[0], ramp.inputs["Fac"])
	em = N("ShaderNodeEmission"); em.inputs["Strength"].default_value = 1.0
	L(ramp.outputs["Color"], em.inputs["Color"])
	tr = N("ShaderNodeBsdfTransparent")
	mix = N("ShaderNodeMixShader")
	L(a3.outputs[0], mix.inputs["Fac"])
	L(tr.outputs[0], mix.inputs[1]); L(em.outputs[0], mix.inputs[2])
	out = N("ShaderNodeOutputMaterial")
	L(mix.outputs[0], out.inputs["Surface"])
	return m


def puff_mat(name, col, alpha_k):
	"""烟团: 自发光单色(按朝向分两档明暗) + 透明度 = (1 - 掠射)^2 × 噪声 ⇒ 中心实、边缘化开, 不是一颗硬球。"""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	N = nt.nodes.new
	L = nt.links.new
	lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
	inv = N("ShaderNodeMath"); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
	L(lw.outputs["Facing"], inv.inputs[1])
	sq = N("ShaderNodeMath"); sq.operation = 'POWER'; sq.inputs[1].default_value = 2.2
	L(inv.outputs[0], sq.inputs[0])
	tc = N("ShaderNodeTexCoord")
	nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.5; nz.inputs["Detail"].default_value = 4.0
	L(tc.outputs["Object"], nz.inputs["Vector"])
	nr = N("ShaderNodeMapRange"); nr.inputs[1].default_value = 0.3; nr.inputs[2].default_value = 0.7
	nr.inputs[3].default_value = 0.2; nr.inputs[4].default_value = 1.0
	L(nz.outputs["Fac"], nr.inputs[0])
	a1 = N("ShaderNodeMath"); a1.operation = 'MULTIPLY'
	L(sq.outputs[0], a1.inputs[0]); L(nr.outputs[0], a1.inputs[1])
	a2 = N("ShaderNodeMath"); a2.operation = 'MULTIPLY'; a2.inputs[1].default_value = alpha_k; a2.use_clamp = True
	L(a1.outputs[0], a2.inputs[0])
	geo = N("ShaderNodeNewGeometry")
	dp = N("ShaderNodeVectorMath"); dp.operation = 'DOT_PRODUCT'; dp.inputs[1].default_value = tuple(LIGHT)
	L(geo.outputs["Normal"], dp.inputs[0])
	ramp = N("ShaderNodeValToRGB")
	cr = ramp.color_ramp
	cr.interpolation = 'CONSTANT'
	cr.elements[0].position = 0.0; cr.elements[0].color = (*lin(col[0]), 1.0)
	cr.elements[1].position = 0.35; cr.elements[1].color = (*lin(col[2]), 1.0)
	e = cr.elements.new(0.0); e.color = (*lin(col[1]), 1.0)
	L(dp.outputs["Value"], ramp.inputs["Fac"])
	em = N("ShaderNodeEmission")
	L(ramp.outputs["Color"], em.inputs["Color"])
	tr = N("ShaderNodeBsdfTransparent")
	mix = N("ShaderNodeMixShader")
	L(a2.outputs[0], mix.inputs["Fac"])
	L(tr.outputs[0], mix.inputs[1]); L(em.outputs[0], mix.inputs[2])
	out = N("ShaderNodeOutputMaterial")
	L(mix.outputs[0], out.inputs["Surface"])
	return m


def toon_mat(name, ramp3):
	"""卡通三档: dot(法线, 光向) 硬边分档 → 自发光(不吃场景光, 与像素龟同一路)。"""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	N = nt.nodes.new
	L = nt.links.new
	geo = N("ShaderNodeNewGeometry")
	dp = N("ShaderNodeVectorMath"); dp.operation = 'DOT_PRODUCT'
	dp.inputs[1].default_value = tuple(LIGHT)
	L(geo.outputs["Normal"], dp.inputs[0])
	ramp = N("ShaderNodeValToRGB")
	cr = ramp.color_ramp
	cr.interpolation = 'CONSTANT'
	cr.elements[0].position = 0.0; cr.elements[0].color = (*lin(ramp3[0]), 1.0)
	cr.elements[1].position = 0.55; cr.elements[1].color = (*lin(ramp3[2]), 1.0)
	e = cr.elements.new(0.12); e.color = (*lin(ramp3[1]), 1.0)
	L(dp.outputs["Value"], ramp.inputs["Fac"])
	em = N("ShaderNodeEmission")
	L(ramp.outputs["Color"], em.inputs["Color"])
	out = N("ShaderNodeOutputMaterial")
	L(em.outputs[0], out.inputs["Surface"])
	return m


def sway(h, t):
	"""漏斗轴的摆动: 底部不动, 越往上摆得越大; 一个循环摆一圈(首尾无缝)。"""
	k = (h / H) ** 1.5 * 0.16
	ph = math.tau * t + h * 1.1
	return (k * math.cos(ph), k * 0.6 * math.sin(ph), 0.0)


# ─────────────────────────────── 网格 ───────────────────────────────
def build_band(name, h0, rise, a0, turns, width, seg=72, rk=1.0):
	"""螺旋风带: 中心线从 (h0, a0) 绕 turns 圈升 rise 米; 带宽方向 = 竖直 + 略向外张(贴着漏斗壁)。"""
	verts, faces, uvs = [], [], []
	for i in range(seg + 1):
		u = i / float(seg)
		h = h0 + rise * u
		a = a0 + turns * math.tau * u
		ca, sa = math.cos(a), math.sin(a)
		for v in (0.0, 1.0):
			hh = h + (v - 0.5) * width
			r = radius_at(hh) * rk * (1.0 + 0.04 * math.sin(u * math.pi))
			verts.append((ca * r, sa * r, hh))
			uvs.append((u, v))
	for i in range(seg):
		a, b, c, d = i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2
		faces.append((a, d, c, b))
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


def build_core(name, seg=48, rings=16):
	"""中心的芯: 开口锥面(比外壁细一圈), UV.u 绕一圈, UV.v 自下而上。"""
	verts, faces, uvs = [], [], []
	for j in range(rings + 1):
		v = j / float(rings)
		h = 0.05 + (H * 0.92) * v
		r = radius_at(h) * 0.42
		for i in range(seg + 1):
			a = math.tau * i / float(seg)
			verts.append((math.cos(a) * r, math.sin(a) * r, h))
			uvs.append((i / float(seg), v))
	for j in range(rings):
		for i in range(seg):
			a = j * (seg + 1) + i
			b = a + 1
			c = a + (seg + 1) + 1
			d = a + (seg + 1)
			faces.append((a, b, c, d))
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


def add_blob(name, radius, mat, subdiv=2):
	bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius)
	ob = bpy.context.active_object
	ob.name = name
	ob.data.materials.append(mat)
	bpy.ops.object.shade_flat() if subdiv <= 1 else bpy.ops.object.shade_smooth()
	return ob


# ─────────────────────────────── 场景 ───────────────────────────────
def setup_render(px, ortho):
	sc = bpy.context.scene
	sc.render.engine = 'CYCLES'
	sc.cycles.device = 'CPU'
	sc.cycles.samples = 48
	sc.cycles.seed = 7
	sc.cycles.transparent_max_bounces = 64
	sc.cycles.max_bounces = 64
	sc.render.resolution_x = px
	sc.render.resolution_y = px
	sc.render.resolution_percentage = 100
	sc.render.film_transparent = True
	sc.render.filter_size = 0.8
	sc.render.image_settings.file_format = 'PNG'
	sc.render.image_settings.color_mode = 'RGBA'
	sc.view_settings.view_transform = 'Standard'
	cd = bpy.data.cameras.new("cam")
	cd.type = 'ORTHO'
	cd.ortho_scale = ortho
	cam = bpy.data.objects.new("cam", cd)
	target_z = H * 0.42
	d = 20.0
	cam.location = Vector((0.0, -d * math.cos(ELEV), target_z + d * math.sin(ELEV)))
	cam.rotation_euler = (math.pi / 2 - ELEV, 0.0, 0.0)
	bpy.context.collection.objects.link(cam)
	sc.camera = cam


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	ap = argparse.ArgumentParser()
	ap.add_argument("--out", required=True)
	ap.add_argument("--px", type=int, default=192)
	ap.add_argument("--ortho", type=float, default=4.4)
	ap.add_argument("--only", type=int, default=-1, help="只渲这一帧(调试)")
	a = ap.parse_args(argv)
	if not os.path.isabs(a.out):
		a.out = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), a.out)
	os.makedirs(a.out, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_render(a.px, a.ortho)
	rng = random.Random(1107)

	## 风带: 外层 9 条(粗、半透明) + 内层 5 条(细、更亮); 每条 = (起始高, 升高, 起始角, 圈数, 带宽, 材质, 每循环转几圈)
	m_outer = wind_mat("wind_outer", 1.5, 5.0)
	m_inner = wind_mat("wind_inner", 1.9, 7.0, hot=True)
	bands = []
	for i in range(12):
		h0 = 0.02 + i * 0.235 + rng.uniform(-0.04, 0.04)
		w = 0.34 + 0.26 * (h0 / H) + rng.uniform(-0.04, 0.04)
		bands.append((h0, 0.18 + rng.uniform(0.0, 0.12), rng.uniform(0, math.tau), rng.uniform(0.55, 1.1), w, m_outer, 1, rng.uniform(0.9, 1.1)))
	for i in range(7):
		h0 = 0.10 + i * 0.40 + rng.uniform(-0.05, 0.05)
		bands.append((h0, 0.25, rng.uniform(0, math.tau), rng.uniform(0.5, 0.8), 0.16 + 0.08 * (h0 / H), m_inner, 2, rng.uniform(0.82, 0.95)))
	band_obs = []
	for k, (h0, rise, a0, turns, w, mat, spin, rk) in enumerate(bands):
		ob = build_band("band_%d" % k, h0, rise, a0, turns, w, rk=rk)
		ob.data.materials.append(mat)
		band_obs.append((ob, spin, h0 + rise * 0.5))

	## 芯
	m_core = wind_mat("wind_core", 0.9, 3.0, hot=True)
	core = build_core("core")
	core.data.materials.append(m_core)

	## 尘(底部一圈): 18 团, 每团有自己的相位; 一个循环里绕一圈、从地面升到 0.6 米、边升边缩
	m_dust = puff_mat("dust", C_DUST, 1.1)
	dust = []
	for i in range(26):
		r0 = rng.uniform(0.30, 0.70)
		ob = add_blob("dust_%d" % i, 1.0, m_dust, subdiv=3)
		dust.append((ob, r0, rng.uniform(0, 1.0), rng.uniform(0.16, 0.26), rng.uniform(0, math.tau)))
	## 碎屑: 8 块绕中段转
	m_rock = toon_mat("rock", C_ROCK)
	rocks = []
	for i in range(8):
		ob = add_blob("rock_%d" % i, 1.0, m_rock, subdiv=1)
		rocks.append((ob, rng.uniform(0.35, 1.9), rng.uniform(0, math.tau), rng.uniform(0.06, 0.09),
		              (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6))))

	frames = [a.only] if a.only >= 0 else list(range(FRAMES))
	for f in frames:
		t = f / float(FRAMES)          # 0..1 一个循环(第 FRAMES 帧 = 第 0 帧)
		for ob, spin, hm in band_obs:
			ob.rotation_euler = (0.0, 0.0, -spin * math.tau * t)
			ob.location = sway(hm, t)
		core.rotation_euler = (0.0, 0.0, -2.0 * math.tau * t)
		core.location = sway(H * 0.5, t)
		for ob, r0, ph, size, a0 in dust:
			q = (t + ph) % 1.0
			ang = a0 - math.tau * q * 1.0 - math.tau * t
			h = 0.04 + 0.70 * q
			r = r0 + 0.35 * q
			s = size * (0.55 + 0.45 * math.sin(math.pi * min(1.0, q * 1.4)))
			ob.location = (math.cos(ang) * r, math.sin(ang) * r, h)
			ob.scale = (s * 1.4, s * 1.4, s)
		for ob, h, a0, size, rot in rocks:
			ang = a0 - math.tau * t
			r = radius_at(h) * 0.85
			ob.location = (math.cos(ang) * r, math.sin(ang) * r, h + 0.06 * math.sin(math.tau * t + a0))
			ob.scale = (size, size * 0.8, size * 0.7)
			ob.rotation_euler = (rot[0] + math.tau * t, rot[1] + math.tau * t, rot[2])
		bpy.context.scene.render.filepath = os.path.join(a.out, "f_%02d.png" % f)
		bpy.ops.render.render(write_still=True)
	print("[katana_tornado] 渲出 %d 帧 → %s" % (len(frames), a.out))


if __name__ == "__main__":
	main()
