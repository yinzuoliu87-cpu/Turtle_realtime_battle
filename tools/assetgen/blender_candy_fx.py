# -*- coding: utf-8 -*-
"""blender_candy_fx.py —— 糖果龟【糖果锤】砸地 / 沿线迸发、【横扫大锤】命中的序列帧(2026-11-15 第二版)。

跑法(无窗口, 每段 × 两遍单独渲; 段 = slam / erupt / erupt2 / sweep, 遍 = up(立着) / gnd(贴地)):
  blender --background --python tools/assetgen/blender_candy_fx.py -- --which slam --pass up  --out .out/candy_blend/slam_up
  blender --background --python tools/assetgen/blender_candy_fx.py -- --which slam --pass gnd --out .out/candy_blend/slam_gnd
  (其余三段同理)
然后 `python tools/assetgen/build_candy_sheets.py` 把帧拼成精灵表进 assets/sprites/vfx/。

由来: 用户 11-15 看了第一版(脚本画的平面小图 × 引擎粒子):「整个观感看上去给人就很假，给人就像一个图片贴在那儿，
  感觉不到任何…某种质量的存在…你需要去用他们那些工具，然后去做一版」。
做法(如实): 特效师那条路 —— Blender 里建模(糖块碎片: 薄荷楔块 / 硬糖碎块 / 糖晶 / 彩针糖; 糖云: 带云噪声置换的球团),
  材质是卡通分层着色(法线 · 光向 → 三档色带)+ 高光点, 糖云消失用噪声侵蚀(从薄处先缺, 不是整体变淡);
  地面是只接影子的透明平面(碎块落地有影子)。碎块运动是脚本按物理逐步算的(抛出 + 重力 + 落地弹跳 + 摩擦 + 自转衰减),
  写成关键帧(不是 Blender 刚体解算器); 糖云的长大 / 上升 / 侵蚀也是关键帧。镜头 = 游戏镜头俯角 51° 的正交相机,
  渲出的每帧在游戏里当公告板放(公告板正对相机 ⇒ 与渲染角度一致)。Cycles CPU、固定种子 ⇒ 重跑同一结果。
参考: docs/studies/20261115-糖果锤参考-波比咖啡甜心Q逐帧.md、20261115b-横扫大锤参考-波比咖啡甜心普攻逐帧.md
  (Q 第 7~11 帧: 亮芯 → 奶油色蓬松云 + 碎屑往外飞 + 框边扬尘; 普攻第 2~6 帧: 闪光 → 圆罩 + 烟顺挥动方向飘 + 碎屑崩出)。
"""
import argparse
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

FPS = 30
ELEV = math.radians(51.0)            # 游戏镜头俯角(battle_world_builder: pos(0,28,22) look_at(0,0.6,0))
LIGHT = Vector((-0.45, -0.55, 0.70)).normalized()   # 光从左上前方来(画面左上亮)

## 颜色(sRGB, 取自糖果龟动作帧: 锤头红 #ba4149、奶白 #e4dbd0、身体粉 #dc909a、深粉 #a4567b)
C_RED = [(0.47, 0.13, 0.20), (0.73, 0.25, 0.29), (0.93, 0.45, 0.47)]
C_WHITE = [(0.80, 0.70, 0.74), (0.96, 0.92, 0.88), (1.0, 1.0, 0.98)]
C_PINK = [(0.62, 0.30, 0.45), (0.88, 0.52, 0.62), (1.0, 0.78, 0.84)]
C_BLUE = [(0.36, 0.52, 0.72), (0.62, 0.84, 0.95), (0.92, 0.98, 1.0)]
C_YEL = [(0.80, 0.55, 0.28), (1.0, 0.84, 0.48), (1.0, 0.96, 0.80)]
C_CREAM = [(0.62, 0.34, 0.50), (0.88, 0.58, 0.68), (0.98, 0.84, 0.86)]
C_DUST = [(0.50, 0.38, 0.42), (0.70, 0.56, 0.56), (0.88, 0.76, 0.74)]


def lin(c):
	return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def clear_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)


# ─────────────────────────────── 材质 ───────────────────────────────
def toon_mat(name, ramp3, stripes=None, erode=False, spec=0.6, alpha_scale=1.0):
	"""卡通分层: dot(法线, 光向) → 暗 / 中 / 亮 三档(硬边) → 自发光; + 一个小高光点(半程向量)。
	stripes = (另一组三档色, 条纹频率): 薄荷糖的红白条纹(按物体坐标的角度分区)。
	erode = True: 物体自定义属性 erode(0~1)越大, 噪声低于它的地方越先变透明(侵蚀溶解)。"""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	N = nt.nodes.new
	out = N("ShaderNodeOutputMaterial")
	geo = N("ShaderNodeNewGeometry")
	dot = N("ShaderNodeVectorMath")
	dot.operation = 'DOT_PRODUCT'
	dot.inputs[1].default_value = LIGHT
	nt.links.new(geo.outputs["Normal"], dot.inputs[0])
	mr = N("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = -1.0
	mr.inputs["From Max"].default_value = 1.0
	nt.links.new(dot.outputs["Value"], mr.inputs["Value"])

	def ramp(cols):
		r = N("ShaderNodeValToRGB")
		r.color_ramp.interpolation = 'CONSTANT'
		els = r.color_ramp.elements
		els[0].position = 0.0
		els[0].color = (*lin(cols[0]), 1.0)
		els[1].position = 0.55
		els[1].color = (*lin(cols[1]), 1.0)
		e = els.new(0.82)
		e.color = (*lin(cols[2]), 1.0)
		nt.links.new(mr.outputs["Result"], r.inputs["Fac"])
		return r

	ra = ramp(ramp3)
	col_out = ra.outputs["Color"]
	if stripes is not None:
		rb = ramp(stripes[0])
		tc = N("ShaderNodeTexCoord")
		sep = N("ShaderNodeSeparateXYZ")
		nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
		at = N("ShaderNodeMath")
		at.operation = 'ARCTAN2'
		nt.links.new(sep.outputs["Y"], at.inputs[0])
		nt.links.new(sep.outputs["X"], at.inputs[1])
		mul = N("ShaderNodeMath")
		mul.operation = 'MULTIPLY'
		mul.inputs[1].default_value = float(stripes[1])
		nt.links.new(at.outputs["Value"], mul.inputs[0])
		sn = N("ShaderNodeMath")
		sn.operation = 'SINE'
		nt.links.new(mul.outputs["Value"], sn.inputs[0])
		gt = N("ShaderNodeMath")
		gt.operation = 'GREATER_THAN'
		gt.inputs[1].default_value = 0.0
		nt.links.new(sn.outputs["Value"], gt.inputs[0])
		mx = N("ShaderNodeMix")
		mx.data_type = 'RGBA'
		nt.links.new(gt.outputs["Value"], mx.inputs["Factor"])
		nt.links.new(rb.outputs["Color"], mx.inputs[6])
		nt.links.new(ra.outputs["Color"], mx.inputs[7])
		col_out = mx.outputs[2]
	## 高光点: dot(法线, 半程向量)^n 过阈值 → 加白
	if spec > 0.0:
		view = Vector((0.0, -math.cos(ELEV), math.sin(ELEV)))
		half = (LIGHT + view).normalized()
		d2 = N("ShaderNodeVectorMath")
		d2.operation = 'DOT_PRODUCT'
		d2.inputs[1].default_value = half
		nt.links.new(geo.outputs["Normal"], d2.inputs[0])
		g2 = N("ShaderNodeMath")
		g2.operation = 'GREATER_THAN'
		g2.inputs[1].default_value = 0.93
		nt.links.new(d2.outputs["Value"], g2.inputs[0])
		sm = N("ShaderNodeMath")
		sm.operation = 'MULTIPLY'
		sm.inputs[1].default_value = spec
		nt.links.new(g2.outputs["Value"], sm.inputs[0])
		mx2 = N("ShaderNodeMix")
		mx2.data_type = 'RGBA'
		nt.links.new(sm.outputs["Value"], mx2.inputs["Factor"])
		nt.links.new(col_out, mx2.inputs[6])
		mx2.inputs[7].default_value = (1.0, 1.0, 1.0, 1.0)
		col_out = mx2.outputs[2]
	em = N("ShaderNodeEmission")
	nt.links.new(col_out, em.inputs["Color"])
	em.inputs["Strength"].default_value = 1.0
	if not erode:
		nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
		return m
	## 侵蚀: 噪声(物体坐标)< 物体属性 erode ⇒ 透明
	tc2 = N("ShaderNodeTexCoord")
	nz = N("ShaderNodeTexNoise")
	nz.inputs["Scale"].default_value = 1.6
	nz.inputs["Detail"].default_value = 0.5
	nt.links.new(tc2.outputs["Object"], nz.inputs["Vector"])
	attr = N("ShaderNodeAttribute")
	attr.attribute_type = 'OBJECT'
	attr.attribute_name = "erode"
	## 噪声先拉开到 0~1 满幅(原值集中在 0.3~0.7), 再减 erode
	st = N("ShaderNodeMapRange")
	st.inputs["From Min"].default_value = 0.3
	st.inputs["From Max"].default_value = 0.7
	nt.links.new(nz.outputs["Fac"], st.inputs["Value"])
	sb = N("ShaderNodeMath")
	sb.operation = 'SUBTRACT'
	nt.links.new(st.outputs["Result"], sb.inputs[0])
	nt.links.new(attr.outputs["Fac"], sb.inputs[1])
	op = N("ShaderNodeMath")
	op.operation = 'MULTIPLY'
	op.use_clamp = True
	op.inputs[1].default_value = 7.0
	nt.links.new(sb.outputs["Value"], op.inputs[0])
	## 背面一律透明: 侵蚀出的洞直接透到底, 不露出团的内壁(否则像空心壳)
	bf = N("ShaderNodeNewGeometry")
	inv = N("ShaderNodeMath")
	inv.operation = 'SUBTRACT'
	inv.inputs[0].default_value = 1.0
	nt.links.new(bf.outputs["Backfacing"], inv.inputs[1])
	op2 = N("ShaderNodeMath")
	op2.operation = 'MULTIPLY'
	nt.links.new(op.outputs["Value"], op2.inputs[0])
	nt.links.new(inv.outputs["Value"], op2.inputs[1])
	op = op2
	tr = N("ShaderNodeBsdfTransparent")
	ms = N("ShaderNodeMixShader")
	nt.links.new(op.outputs["Value"], ms.inputs[0])
	nt.links.new(tr.outputs["BSDF"], ms.inputs[1])
	nt.links.new(em.outputs["Emission"], ms.inputs[2])
	nt.links.new(ms.outputs["Shader"], out.inputs["Surface"])
	return m


def ribbon_mat(name):
	"""横扫拖影: 自发光, 沿 U(尾 0 → 头 1)由透明粉到奶白; 物体属性 erode 从尾往头吃掉。"""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	N = nt.nodes.new
	out = N("ShaderNodeOutputMaterial")
	tc = N("ShaderNodeTexCoord")
	sep = N("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["UV"], sep.inputs["Vector"])
	r = N("ShaderNodeValToRGB")
	els = r.color_ramp.elements
	els[0].position = 0.0
	els[0].color = (*lin((0.88, 0.40, 0.55)), 1.0)
	els[1].position = 1.0
	els[1].color = (*lin((1.0, 0.97, 0.92)), 1.0)
	nt.links.new(sep.outputs["X"], r.inputs["Fac"])
	em = N("ShaderNodeEmission")
	nt.links.new(r.outputs["Color"], em.inputs["Color"])
	## 透明度 = U^1.5 × 横向中间亮(V 两边淡) × (U > erode)
	pw = N("ShaderNodeMath")
	pw.operation = 'POWER'
	pw.inputs[1].default_value = 1.5
	nt.links.new(sep.outputs["X"], pw.inputs[0])
	vc = N("ShaderNodeMath")
	vc.operation = 'SUBTRACT'
	vc.inputs[1].default_value = 0.5
	nt.links.new(sep.outputs["Y"], vc.inputs[0])
	va = N("ShaderNodeMath")
	va.operation = 'ABSOLUTE'
	nt.links.new(vc.outputs["Value"], va.inputs[0])
	vm = N("ShaderNodeMapRange")
	vm.inputs["From Min"].default_value = 0.5
	vm.inputs["From Max"].default_value = 0.15
	nt.links.new(va.outputs["Value"], vm.inputs["Value"])
	a1 = N("ShaderNodeMath")
	a1.operation = 'MULTIPLY'
	nt.links.new(pw.outputs["Value"], a1.inputs[0])
	nt.links.new(vm.outputs["Result"], a1.inputs[1])
	attr = N("ShaderNodeAttribute")
	attr.attribute_type = 'OBJECT'
	attr.attribute_name = "erode"
	gt = N("ShaderNodeMath")
	gt.operation = 'GREATER_THAN'
	nt.links.new(sep.outputs["X"], gt.inputs[0])
	nt.links.new(attr.outputs["Fac"], gt.inputs[1])
	a2 = N("ShaderNodeMath")
	a2.operation = 'MULTIPLY'
	nt.links.new(a1.outputs["Value"], a2.inputs[0])
	nt.links.new(gt.outputs["Value"], a2.inputs[1])
	tr = N("ShaderNodeBsdfTransparent")
	ms = N("ShaderNodeMixShader")
	nt.links.new(a2.outputs["Value"], ms.inputs[0])
	nt.links.new(tr.outputs["BSDF"], ms.inputs[1])
	nt.links.new(em.outputs["Emission"], ms.inputs[2])
	nt.links.new(ms.outputs["Shader"], out.inputs["Surface"])
	return m


# ─────────────────────────────── 网格 ───────────────────────────────
def _obj(name, bm):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(ob)
	return ob


def mesh_wedge(name, r=0.13, h=0.07, ang=0.9):
	"""薄荷楔块: 一块扇形(像从薄荷圆糖上崩下来的一角), 倒角。"""
	bm = bmesh.new()
	n = 6
	top, bot = [], []
	pts = [(0.0, 0.0)] + [(r * math.cos(-ang / 2 + ang * k / n), r * math.sin(-ang / 2 + ang * k / n)) for k in range(n + 1)]
	for (x, y) in pts:
		bot.append(bm.verts.new((x - r * 0.45, y, -h / 2)))
		top.append(bm.verts.new((x - r * 0.45, y, h / 2)))
	bm.faces.new(list(reversed(bot)))
	bm.faces.new(top)
	for i in range(len(pts)):
		j = (i + 1) % len(pts)
		bm.faces.new((bot[i], bot[j], top[j], top[i]))
	bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.012, segments=2, affect='EDGES')
	return _obj(name, bm)


def mesh_shard(name, rnd, r=0.09):
	"""硬糖碎块: 二十面体压扁拉长 + 顶点随机推拉(碎得不规则)。"""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
	sx, sy, sz = rnd.uniform(0.8, 1.5), rnd.uniform(0.6, 1.0), rnd.uniform(0.45, 0.8)
	for v in bm.verts:
		k = rnd.uniform(0.82, 1.18)
		v.co = Vector((v.co.x * sx * k, v.co.y * sy * k, v.co.z * sz * k))
	return _obj(name, bm)


def mesh_crystal(name, r=0.07):
	"""糖晶: 拉长的八面体。"""
	bm = bmesh.new()
	vs = [bm.verts.new(p) for p in ((r, 0, 0), (-r, 0, 0), (0, r, 0), (0, -r, 0), (0, 0, r * 1.8), (0, 0, -r * 1.8))]
	for a, b, c in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
		bm.faces.new((vs[a], vs[b], vs[c]))
	return _obj(name, bm)


def mesh_sprinkle(name, L=0.11, r=0.022):
	"""彩针糖: 两头圆的短棍。"""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=r, radius2=r, depth=L)
	for z in (L / 2, -L / 2):
		b2 = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=r)
		for v in b2["verts"]:
			v.co.z += z
	return _obj(name, bm)


def mesh_puff(name, rnd, r=1.0):
	"""糖云团: 细分二十面体 + 云噪声置换(鼓包)。半径 1, 由缩放决定大小。"""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
	ob = _obj(name, bm)
	tex = bpy.data.textures.new(name + "_n", 'CLOUDS')
	tex.noise_scale = 0.42
	tex.noise_depth = 1
	md = ob.modifiers.new("disp", 'DISPLACE')
	md.texture = tex
	md.strength = 1.1
	md.mid_level = 0.5
	md.texture_coords = 'OBJECT'
	## 每团噪声取不同的地方: 用一个空物体当纹理坐标
	emp = bpy.data.objects.new(name + "_c", None)
	bpy.context.collection.objects.link(emp)
	emp.location = (rnd.uniform(-20, 20), rnd.uniform(-20, 20), rnd.uniform(-20, 20))
	md.texture_coords_object = emp
	for p in ob.data.polygons:
		p.use_smooth = True
	ob.visible_shadow = False
	return ob


def mesh_dust_ring(name, rnd, minor=0.12):
	"""贴地尘浪: 环面(大半径 1, 小半径 minor)+ 云噪声置换(一圈鼓包), 压扁; 由 x/y 缩放决定往外推多远。"""
	bm = bmesh.new()
	seg_u, seg_v = 64, 10
	rings = []
	for i in range(seg_u):
		a = 2 * math.pi * i / seg_u
		row = []
		for j in range(seg_v):
			b = 2 * math.pi * j / seg_v
			r = 1.0 + minor * math.cos(b)
			row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
		rings.append(row)
	for i in range(seg_u):
		for j in range(seg_v):
			a, b = rings[i][j], rings[(i + 1) % seg_u][j]
			c, d = rings[(i + 1) % seg_u][(j + 1) % seg_v], rings[i][(j + 1) % seg_v]
			bm.faces.new((a, b, c, d))
	ob = _obj(name, bm)
	tex = bpy.data.textures.new(name + "_n", 'CLOUDS')
	tex.noise_scale = 0.16
	tex.noise_depth = 1
	md = ob.modifiers.new("disp", 'DISPLACE')
	md.texture = tex
	md.strength = 0.22
	md.mid_level = 0.45
	md.texture_coords = 'OBJECT'
	emp = bpy.data.objects.new(name + "_c", None)
	bpy.context.collection.objects.link(emp)
	emp.location = (rnd.uniform(-20, 20), rnd.uniform(-20, 20), rnd.uniform(-20, 20))
	md.texture_coords_object = emp
	for p in ob.data.polygons:
		p.use_smooth = True
	ob.visible_shadow = False
	return ob


def mesh_ribbon(name, center, R, a0, a1, w0, w1, n=28):
	"""横扫拖影: 竖直平面(x-z)里的一段圆弧带, U 沿弧(尾 0 → 头 1), V 横跨带宽; 宽度从尾 w0 到头 w1。"""
	bm = bmesh.new()
	uv = bm.loops.layers.uv.new()
	rows = []
	for k in range(n + 1):
		t = k / n
		a = a0 + (a1 - a0) * t
		w = w0 + (w1 - w0) * t
		cx, cz = center[0] + R * math.cos(a), center[1] + R * math.sin(a)
		ox, oz = math.cos(a) * w * 0.5, math.sin(a) * w * 0.5
		rows.append((bm.verts.new((cx - ox, 0.0, cz - oz)), bm.verts.new((cx + ox, 0.0, cz + oz)), t))
	for k in range(n):
		(a, b, ta), (c, d, tb) = rows[k], rows[k + 1]
		f = bm.faces.new((a, c, d, b))
		for lp, (u, v) in zip(f.loops, ((ta, 0.0), (tb, 0.0), (tb, 1.0), (ta, 1.0))):
			lp[uv].uv = (u, v)
	return _obj(name, bm)


# ─────────────────────────────── 运动 ───────────────────────────────
def key_ballistic(ob, p0, v0, w0, frames, rnd, g=15.0, rest=0.32, fric=0.55, settle_from=None, r_ground=0.04):
	"""逐步物理: 重力 + 落地弹跳(恢复系数 rest、水平摩擦 fric)+ 自转(落地时衰减)。每个输出帧打位置 / 旋转关键帧。
	settle_from: 从第几帧起往地里缩(落地停住后慢慢化掉)。"""
	p = Vector(p0)
	v = Vector(v0)
	rot = Vector((rnd.uniform(0, 6.28), rnd.uniform(0, 6.28), rnd.uniform(0, 6.28)))
	w = Vector(w0)
	sub = 8
	dt = 1.0 / (FPS * sub)
	base = ob.scale.copy()
	for f in range(frames):
		ob.location = p
		ob.rotation_euler = rot
		ob.keyframe_insert("location", frame=f)
		ob.keyframe_insert("rotation_euler", frame=f)
		if settle_from is not None:
			k = 0.0 if f < settle_from else min(1.0, (f - settle_from) / max(1.0, frames - 1 - settle_from))
			ob.scale = base * (1.0 - k)
			ob.keyframe_insert("scale", frame=f)
		for _ in range(sub):
			v.z -= g * dt
			p += v * dt
			rot += w * dt
			if p.z < r_ground:
				p.z = r_ground
				if v.z < 0.0:
					v.z = -v.z * rest
					v.x *= (1.0 - fric)
					v.y *= (1.0 - fric)
					w *= 0.5
					if v.z < 0.4:
						v.z = 0.0


def key_puff(ob, p0, p1, s0, s1, f0, f1, erode_from, frames):
	"""糖云团: f0 出现, 位置 p0 → p1、尺寸 s0 → s1(先快后慢); 从 erode_from(0~1, 寿命比例)起侵蚀到 1。"""
	for f in range(frames):
		if f < f0:
			t = 0.0
			vis = False
		else:
			t = min(1.0, (f - f0) / max(1.0, f1 - f0))
			vis = f <= f1
		e = 1.0 - (1.0 - t) ** 3
		ob.location = Vector(p0).lerp(Vector(p1), e)
		s = (s0 + (s1 - s0) * e) if vis else 0.0001
		ob.scale = (s, s, s * float(ob.get("flat", 0.85)))
		ob["erode"] = 0.0 if t < erode_from else min(1.0, (t - erode_from) / max(0.01, 1.0 - erode_from)) * 0.95 + 0.02
		ob.keyframe_insert("location", frame=f)
		ob.keyframe_insert("scale", frame=f)
		ob.keyframe_insert('["erode"]', frame=f)


# ─────────────────────────────── 场景 ───────────────────────────────
def setup(px, ortho, target_z, frames, pas="up"):
	"""pas = "up": 立着的那遍(游戏镜头俯角 51° 正交, 糖块描边, 不要地面); "gnd": 贴地的那遍(正上方往下看, 只接影子的地面)。"""
	sc = bpy.context.scene
	## 关键帧之间线性插值(每个输出帧都打了帧, 线性 = 不在帧之间另造曲线); Blender 5 的动作是分层的, 改默认值最稳
	bpy.context.preferences.edit.keyframe_new_interpolation_type = 'LINEAR'
	sc.render.engine = 'CYCLES'
	sc.cycles.device = 'CPU'
	sc.cycles.samples = 32
	sc.cycles.use_denoising = True
	sc.cycles.seed = 7
	sc.cycles.use_animated_seed = False
	sc.cycles.max_bounces = 2
	sc.render.resolution_x = px
	sc.render.resolution_y = px
	sc.render.resolution_percentage = 100
	sc.render.film_transparent = True
	sc.render.image_settings.file_format = 'PNG'
	sc.render.image_settings.color_mode = 'RGBA'
	sc.view_settings.view_transform = 'Standard'
	sc.render.fps = FPS
	sc.frame_start = 0
	sc.frame_end = frames - 1
	sc.world = bpy.data.worlds.new("w")
	sc.world.use_nodes = True
	sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
	cd = bpy.data.cameras.new("cam")
	cd.type = 'ORTHO'
	cd.ortho_scale = ortho
	cam = bpy.data.objects.new("cam", cd)
	d = 30.0
	if pas == "gnd":
		## 正上方往下看: 画面上方 = Blender +Y = 离游戏镜头远的一侧(游戏 −Z), 与 Godot 贴地精灵(axis Y)贴图上方同向
		cam.location = Vector((0.0, 0.0, d))
		cam.rotation_euler = (0.0, 0.0, 0.0)
	else:
		cam.location = Vector((0.0, -d * math.cos(ELEV), target_z + d * math.sin(ELEV)))
		cam.rotation_euler = (math.pi / 2 - ELEV, 0.0, 0.0)
	bpy.context.collection.objects.link(cam)
	sc.camera = cam
	## 太阳光(只为投影子; 物体颜色是自发光卡通分层, 不吃光)
	ld = bpy.data.lights.new("sun", 'SUN')
	ld.energy = 3.0
	ld.angle = math.radians(8.0)
	sun = bpy.data.objects.new("sun", ld)
	sun.rotation_euler = Vector((0, 0, 1)).rotation_difference(LIGHT).to_euler()
	bpy.context.collection.objects.link(sun)
	if pas == "gnd":
		## 只接影子的地面(贴地那遍才要; 立着那遍没有地面, 影子不再画在龟身上)
		bm = bmesh.new()
		bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=20.0)
		g = _obj("ground", bm)
		g.is_shadow_catcher = True
		return
	## 描边: 只描「outlined」集合(糖块), 深紫 1.6 像素
	sc.render.use_freestyle = True
	sc.render.line_thickness_mode = 'ABSOLUTE'
	sc.render.line_thickness = 1.6
	vl = sc.view_layers[0]
	vl.use_freestyle = True
	fs = vl.freestyle_settings
	ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("ls")
	ls.select_by_collection = True
	ls.collection = bpy.data.collections.get("outlined") or bpy.data.collections.new("outlined")
	if ls.collection.name not in sc.collection.children:
		sc.collection.children.link(ls.collection)
	ls.select_silhouette = True
	ls.select_border = True
	ls.select_crease = False
	if ls.linestyle is None:
		ls.linestyle = bpy.data.linestyles.new("candy_line")
	ls.linestyle.color = lin((0.30, 0.14, 0.24))
	ls.linestyle.thickness = 1.6


def apply_pass(pas):
	"""分层(2.5D): 立着那遍 = 飞起来的糖块 + 糖云 + 拖影(公告板, 画在龟前面); 贴地那遍 = 尘浪 + 糖块影子(平铺在地上, 压在龟脚下)。
	用户 11-15 定「修层次，画风不变」: 原来尘浪和影子渲在立着的图里, 盖在站在里面的龟身上。"""
	outlined = bpy.data.collections.get("outlined")
	chunks = set(outlined.objects) if outlined else set()
	for ob in bpy.data.objects:
		if ob.type != 'MESH' or ob.name == "ground":
			continue
		is_ring = ob.name.startswith("dring")
		if pas == "up":
			if is_ring:
				ob.hide_render = True
		else:
			if ob in chunks:
				ob.visible_camera = False      # 看不见, 但照样投影子
			elif not is_ring:
				ob.hide_render = True          # 糖云 / 拖影不进贴地层


def render(out, frames):
	sc = bpy.context.scene
	os.makedirs(out, exist_ok=True)
	for f in range(frames):
		sc.frame_set(f)
		sc.render.filepath = os.path.join(out, "f_%02d.png" % f)
		bpy.ops.render.render(write_still=True)


def chunk_set(rnd, n, prefix, mats, scale=1.0):
	"""造 n 块糖块(四种轮流, 每块随机大小)。"""
	obs = []
	for i in range(n):
		kind = i % 4
		if kind == 0:
			ob = mesh_wedge("%s_w%d" % (prefix, i), r=0.13 * scale * rnd.uniform(0.8, 1.2))
			ob.data.materials.append(mats["mint"])
		elif kind == 1:
			ob = mesh_shard("%s_s%d" % (prefix, i), rnd, r=0.09 * scale * rnd.uniform(0.8, 1.25))
			ob.data.materials.append(mats["pink"])
		elif kind == 2:
			ob = mesh_crystal("%s_c%d" % (prefix, i), r=0.06 * scale * rnd.uniform(0.85, 1.2))
			ob.data.materials.append(mats["blue"])
		else:
			ob = mesh_sprinkle("%s_p%d" % (prefix, i), L=0.11 * scale, r=0.022 * scale)
			ob.data.materials.append(mats["yel"] if (i // 4) % 2 == 0 else mats["red"])
		_to_outline(ob)
		obs.append(ob)
	return obs


def _to_outline(ob):
	"""糖块进「描边」集合: 渲染时 Freestyle 只给它们描一圈深色轮廓(同游戏里龟立绘的深色描边, 在草地上读得出)。"""
	col = bpy.data.collections.get("outlined")
	if col is None:
		col = bpy.data.collections.new("outlined")
		bpy.context.scene.collection.children.link(col)
	for c in list(ob.users_collection):
		c.objects.unlink(ob)
	col.objects.link(ob)


def make_mats():
	return {
		"mint": toon_mat("mint", C_WHITE, stripes=(C_RED, 6.0)),
		"pink": toon_mat("pink", C_PINK, spec=0.9),
		"blue": toon_mat("blue", C_BLUE, spec=0.9),
		"yel": toon_mat("yel", C_YEL, spec=0.5),
		"red": toon_mat("red", C_RED, spec=0.5),
		"cream": toon_mat("cream", C_CREAM, erode=True, spec=0.0),
		"dust": toon_mat("dust", C_DUST, erode=True, spec=0.0),
	}


# ─────────────────────────────── 三段 ───────────────────────────────
def build_slam(rnd, frames):
	"""糖果锤落点(帧 0 = 锤头着地): 14 块糖块往上往外崩、落地弹跳; 7 团奶油糖云往上鼓; 12 团贴地尘往外推成一圈。"""
	mats = make_mats()
	for i, ob in enumerate(chunk_set(rnd, 14, "sl", mats, 2.1)):
		a = 2 * math.pi * i / 14 + rnd.uniform(-0.25, 0.25)
		hs = rnd.uniform(1.2, 3.0)
		v0 = (math.cos(a) * hs, math.sin(a) * hs * 0.8, rnd.uniform(3.6, 6.2))
		w0 = (rnd.uniform(-14, 14), rnd.uniform(-14, 14), rnd.uniform(-8, 8))
		key_ballistic(ob, (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.15), v0, w0, frames, rnd, settle_from=frames - 9)
	for i in range(7):
		a = 2 * math.pi * i / 7 + rnd.uniform(-0.3, 0.3)
		ob = mesh_puff("cl%d" % i, rnd)
		ob.data.materials.append(mats["cream"])
		r0, r1 = rnd.uniform(0.1, 0.2), rnd.uniform(0.45, 0.8)
		p0 = (math.cos(a) * r0, math.sin(a) * r0 * 0.8, 0.22)
		p1 = (math.cos(a) * r1, math.sin(a) * r1 * 0.8, rnd.uniform(0.5, 0.9))
		key_puff(ob, p0, p1, 0.06, rnd.uniform(0.2, 0.3), rnd.randint(0, 2), rnd.randint(17, 22), 0.45, frames)
	## 贴地尘浪: 一整圈从锤头往外推(半径 0.3 → 1.6 米, 先快后慢), 越推越矮越薄, 后半段侵蚀掉
	dr = mesh_dust_ring("dring", rnd)
	dr.data.materials.append(mats["dust"])
	for f in range(frames):
		t = min(1.0, f / 16.0)
		e = 1.0 - (1.0 - t) ** 3
		R = 0.3 + 1.15 * e
		dr.scale = (R, R * 0.92, 1.4 - 0.8 * e)
		dr.location = (0.0, 0.0, 0.05)
		dr["erode"] = 0.0 if t < 0.3 else min(1.0, (t - 0.3) / 0.7) * 0.95 + 0.02
		dr.keyframe_insert("scale", frame=f)
		dr.keyframe_insert("location", frame=f)
		dr.keyframe_insert('["erode"]', frame=f)


def build_erupt(rnd, frames):
	"""沿线迸发(判定区里另外两处; 帧 0 = 同一刻): 6 块糖块从地里蹦出来、4 团尘。"""
	mats = make_mats()
	for i, ob in enumerate(chunk_set(rnd, 6, "er", mats, 1.8)):
		a = 2 * math.pi * i / 6 + rnd.uniform(-0.4, 0.4)
		hs = rnd.uniform(0.5, 1.4)
		key_ballistic(ob, (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.06), (math.cos(a) * hs, math.sin(a) * hs * 0.8, rnd.uniform(3.2, 5.0)),
			(rnd.uniform(-12, 12), rnd.uniform(-12, 12), rnd.uniform(-6, 6)), frames, rnd, settle_from=frames - 7)
	for i in range(4):
		a = 2 * math.pi * i / 4 + rnd.uniform(-0.4, 0.4)
		ob = mesh_puff("eu%d" % i, rnd)
		ob.data.materials.append(mats["dust"])
		r1 = rnd.uniform(0.35, 0.6)
		key_puff(ob, (0, 0, 0.08), (math.cos(a) * r1, math.sin(a) * r1 * 0.8, rnd.uniform(0.25, 0.45)), 0.05,
			rnd.uniform(0.17, 0.24), rnd.randint(0, 1), rnd.randint(13, 17), 0.3, frames)


def build_sweep(rnd, frames):
	"""横扫命中(帧 0 = 锤头扫到目标; 挥向画面右): 一道粉白弧形拖影从尾往头化掉; 7 块糖块顺挥动方向崩出; 3 团糖云往右上飘。"""
	mats = make_mats()
	rb = mesh_ribbon("sw", (-0.55, 0.95), 0.85, math.radians(200.0), math.radians(322.0), 0.05, 0.5)
	rb.data.materials.append(ribbon_mat("rib"))
	rb.visible_shadow = False
	## 弧带所在的竖直面绕 x 轴往后仰 39°(= 90° − 镜头俯角), 正对镜头 ⇒ 画面上是一整道月牙, 不是侧面一条线
	rb.rotation_euler = (math.radians(-(90.0 - 51.0)), 0.0, 0.0)
	for f in range(frames):
		rb["erode"] = min(1.05, f / 5.0)
		rb.keyframe_insert('["erode"]', frame=f)
	for i, ob in enumerate(chunk_set(rnd, 7, "sw", mats, 1.6)):
		a = -0.8 + 1.6 * (i + rnd.uniform(0.1, 0.9)) / 7.0
		hs = rnd.uniform(2.8, 4.6)
		key_ballistic(ob, (0.05, 0.0, 0.45), (math.cos(a) * hs, math.sin(a) * hs * 0.7, rnd.uniform(2.6, 4.6)),
			(rnd.uniform(-16, 16), rnd.uniform(-16, 16), rnd.uniform(-8, 8)), frames, rnd, settle_from=frames - 5)
	for i in range(3):
		ob = mesh_puff("sp%d" % i, rnd)
		ob.data.materials.append(mats["cream"])
		key_puff(ob, (0.0, 0.0, 0.45), (rnd.uniform(0.4, 0.8), rnd.uniform(-0.2, 0.2), rnd.uniform(0.6, 0.9)), 0.05,
			rnd.uniform(0.16, 0.22), i, rnd.randint(10, 13), 0.3, frames)


SPECS = {
	## which: (帧数, 每帧像素, 正交宽度(米), 画面中心离地高度(米), 构建函数, 随机种子, 贴地那遍的正交宽度(米))
	"slam": (27, 256, 4.6, 0.45, build_slam, 1511, 5.0),
	"erupt": (21, 160, 2.6, 0.35, build_erupt, 1512, 3.0),
	"erupt2": (21, 160, 2.6, 0.35, build_erupt, 1513, 3.0),
	"sweep": (16, 192, 3.0, 0.55, build_sweep, 1514, 4.4),
}


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	ap = argparse.ArgumentParser()
	ap.add_argument("--which", required=True, choices=sorted(SPECS.keys()))
	ap.add_argument("--out", required=True)
	ap.add_argument("--pass", dest="pas", default="up", choices=["up", "gnd"])
	ap.add_argument("--only", type=int, default=-1, help="只渲这一帧(调试)")
	a = ap.parse_args(argv)
	frames, px, ortho, tz, fn, seed, ortho_g = SPECS[a.which]
	clear_scene()
	setup(px, ortho_g if a.pas == "gnd" else ortho, tz, frames, a.pas)
	fn(random.Random(seed), frames)
	apply_pass(a.pas)
	if a.only >= 0:
		sc = bpy.context.scene
		sc.frame_set(a.only)
		os.makedirs(a.out, exist_ok=True)
		sc.render.filepath = os.path.join(a.out, "only_%02d.png" % a.only)
		bpy.ops.render.render(write_still=True)
	else:
		render(a.out, frames)
	print("[blender_candy_fx] %s/%s 渲出 %d 帧 → %s" % (a.which, a.pas, frames if a.only < 0 else 1, a.out))


if __name__ == "__main__":
	main()
