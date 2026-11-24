# -*- coding: utf-8 -*-
"""blender_chest_fx.py —— 宝箱龟普攻【宝箱砸击】特效序列帧(2026-11-20)。

跑法(无窗口; 段 = slam / pop / pop2 / hit / wave, 遍 = up(立着) / gnd(贴地); wave 只有 gnd):
  blender --background --python tools/assetgen/blender_chest_fx.py -- --which slam --pass up  --out .out/chest_blend/slam_up
  blender --background --python tools/assetgen/blender_chest_fx.py -- --which slam --pass gnd --out .out/chest_blend/slam_gnd
  (其余同理)
一次全渲 + 拼成精灵表进 assets/sprites/vfx/: `python tools/assetgen/build_chest_sheets.py`。

由来: 用户 11-20「它的普攻特效…需要去重做吧…不是普通普攻动画，是普攻特效」(方案书 docs/plans/20261120-宝箱龟图鉴战利品与普攻特效.md)。
  原来是通用火焰光晕 + 通用能量光带 + 一张爆闪图, 实拍几乎看不见、也看不出是宝箱。
参考(逐帧, 外部商业游戏): 奥恩 Q「火山裂隙」docs/studies/20261120-宝箱砸击参考-奥恩Q逐帧.md ——
  砸地爆闪 → 碎石崩飞 → 一道亮裂缝带着亮头沿地面推到目标 → 裂缝身后烟尘 → 尽头炸开 → 0.55 秒收干净。
  宝箱主题的换法: 碎石 → 金币 + 宝石(物理抛出、落地弹跳); 岩浆裂缝 → 金色裂光(推进到头后冷却成焦痕); 尽头 / 命中 → 金币溅开。
做法(如实): 与糖果龟第二版同一条路(blender_candy_fx.py, 用户 11-15 认可) —— Blender 里建模(金币 = 倒角圆柱, 宝石 = 刻面宝石),
  卡通分层着色(复用 blender_candy_fx.toon_mat), 运动是脚本按物理逐步算再写关键帧(复用 key_ballistic), 尘团是云噪声球团 + 侵蚀溶解;
  裂光是一条锯齿带网格, 发光颜色 / 生长 / 冷却全在着色器里按「出生时刻 = 0.18 秒 × 沿线位置」算。
  镜头 = 游戏镜头俯角 40°(BattleCam.PITCH_DEG)的正交相机; 贴地那遍从正上方渲。Cycles CPU、固定种子 ⇒ 重跑同一结果。
时间对齐: 帧 0 = `ChestSystem._chest_basic` 被调用那一刻(宝箱砸到地); 波头 0.18 秒走完(= 结算排程 wave_t), 序列 30 帧/秒。
"""
import argparse
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_candy_fx as bc   # noqa: E402  复用: toon_mat / key_ballistic / key_puff / mesh_puff / mesh_dust_ring / setup / render

bc.ELEV = math.radians(40.0)     # 11-16 起游戏镜头俯角 40°(糖果龟那版渲于 51° 时代)
FPS = bc.FPS
WAVE_SEC = 0.18                  # 波头从宝箱龟脚下走到射程尽头(ChestSystem.BASIC_WAVE_SEC)
WAVE_LEN = 124.0 * 0.024         # 砸点(46 码)→ 尽头(170 码) = 124 码 × WS = 2.976 米
## 裂光从砸点画起: 波头到砸点的时刻 = 0.18 × 46 / 170; 到裂光上沿线位置 U(0~1)的时刻 = HEAD_T0 + HEAD_SPAN × U(与结算排程同一个公式)
HEAD_T0 = WAVE_SEC * 46.0 / 170.0
HEAD_SPAN = WAVE_SEC - HEAD_T0

## 颜色(sRGB): 金币取自宝箱龟立绘的金饰(亮 #f6d36b、中 #d79a2b、暗 #8a5212)
C_GOLD = [(0.54, 0.32, 0.07), (0.86, 0.60, 0.17), (1.0, 0.88, 0.45)]
C_RUBY = [(0.45, 0.04, 0.10), (0.85, 0.15, 0.22), (1.0, 0.55, 0.55)]
C_EMER = [(0.04, 0.32, 0.18), (0.12, 0.70, 0.38), (0.60, 1.0, 0.70)]
C_SAPH = [(0.06, 0.16, 0.48), (0.20, 0.45, 0.92), (0.65, 0.85, 1.0)]
C_SAND = [(0.46, 0.35, 0.22), (0.70, 0.57, 0.38), (0.90, 0.80, 0.58)]
OUTLINE = (0.24, 0.13, 0.04)


# ─────────────────────────────── 网格 ───────────────────────────────
def mesh_coin(name, r=0.18, h=0.068):
	"""金币: 16 边圆柱 + 边倒角(侧面一圈暗、两面亮; 翻转时一闪一闪)。厚度约半径的 0.4 倍(卡通比例: 侧立时仍读得出是一枚币, 不是一根棍)。
	直径 0.36 米(按游戏镜头约 12 像素; 0.22 米那版实拍只有 6~7 像素, 读成金粉不是金币)。"""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r, radius2=r, depth=h)
	bmesh.ops.bevel(bm, geom=[e for e in bm.edges if not e.is_boundary], offset=h * 0.3, segments=1, affect='EDGES')
	return bc._obj(name, bm)


def mesh_gem(name, r=0.12):
	"""宝石: 八边刻面 —— 上面一圈冠部斜面 + 平台面, 下面尖底。"""
	bm = bmesh.new()
	n = 8
	top = [bm.verts.new((r * 0.55 * math.cos(2 * math.pi * k / n), r * 0.55 * math.sin(2 * math.pi * k / n), r * 0.45)) for k in range(n)]
	mid = [bm.verts.new((r * math.cos(2 * math.pi * (k + 0.5) / n), r * math.sin(2 * math.pi * (k + 0.5) / n), r * 0.12)) for k in range(n)]
	tip = bm.verts.new((0.0, 0.0, -r * 0.95))
	bm.faces.new(top)
	for k in range(n):
		j = (k + 1) % n
		bm.faces.new((top[k], mid[k], top[j]))
		bm.faces.new((mid[k], mid[j], top[j]))
		bm.faces.new((mid[j], mid[k], tip))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bc._obj(name, bm)


def crack_mesh(name, rnd, L, w0=0.17):   # 0.10 → 0.17(11-20 用户「特效还不够明显」: 整场画面里两三像素宽看不出)
	"""金色裂光: 沿 +X 从 -L/2 到 +L/2 的一条锯齿带(UV.x = 沿线 0→1, UV.y = 横跨), 末端收细; 外加 7 条短支裂(UV.x = 分叉处的沿线位置)。"""
	bm = bmesh.new()
	uv = bm.loops.layers.uv.new()
	x0 = -L / 2.0

	def strip(pts, ws, us):
		rows = []
		for i, (p, w, u) in enumerate(zip(pts, ws, us)):
			if i + 1 < len(pts):
				d = (pts[i + 1] - p)
			else:
				d = (p - pts[i - 1])
			d = d.normalized()
			nrm = Vector((-d.y, d.x, 0.0))
			rows.append((bm.verts.new(p - nrm * w / 2), bm.verts.new(p + nrm * w / 2), u))
		for i in range(len(rows) - 1):
			(a, b, ua), (c, d2, ub) = rows[i], rows[i + 1]
			f = bm.faces.new((a, c, d2, b))
			for lp, (uu, vv) in zip(f.loops, ((ua, 0.0), (ub, 0.0), (ub, 1.0), (ua, 1.0))):
				lp[uv].uv = (uu, vv)

	n = 40
	pts, ws, us = [], [], []
	y = 0.0
	sgn = 1.0
	for i in range(n + 1):
		t = i / n
		if 0 < i < n:
			## 锯齿: 多数段往反方向折、偶尔连着往同一侧(大小随机), 折点前后错开 ⇒ 读成裂开的缝, 不是锯条也不是树枝
			if rnd.random() < 0.72:
				sgn = -sgn
			y = max(-0.08, min(0.08, y * 0.6 + sgn * rnd.uniform(0.008, 0.045)))
			t = t + rnd.uniform(-0.35, 0.35) / n
		pts.append(Vector((x0 + L * t, y if 0 < i < n else 0.0, 0.004)))
		ws.append(w0 * (1.15 - 0.75 * t) * rnd.uniform(0.8, 1.2) if i < n else 0.01)
		us.append(t)
	strip(pts, ws, us)
	for k in range(9):
		t = 0.06 + 0.88 * (k + rnd.uniform(0.2, 0.8)) / 9.0
		i = int(t * n)
		base = pts[i]
		ang = (1 if k % 2 == 0 else -1) * rnd.uniform(0.6, 1.3)
		ln = rnd.uniform(0.06, 0.16) * (1.2 - 0.6 * t)
		m = 3
		bp, bw, bu = [], [], []
		for j in range(m + 1):
			s = j / m
			bp.append(base + Vector((math.cos(ang) * ln * s, math.sin(ang) * ln * s + rnd.uniform(-0.012, 0.012) * (0 < j < m), 0.003)))
			bw.append(ws[i] * 0.55 * (1.0 - 0.85 * s))
			bu.append(us[i] + 0.02 * s)     # 支裂比主裂晚一点点亮
		strip(bp, bw, bu)
	ob = bc._obj(name, bm)
	ob.visible_shadow = False
	return ob


def crack_mat(name):
	"""裂光着色: 每个像素的「年龄」= 物体属性 t − 波头扫到它的时刻(HEAD_T0 + HEAD_SPAN × UV.x)。
	年龄 < 0 不画; 0 → 0.06 秒白金(波头) → 0.3 秒金 → 橙 → 0.5 秒焦褐; 0.32 秒起噪声侵蚀, 0.55 秒吃光。横向两边暗一档(裂缝边)。"""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	N = nt.nodes.new
	out = N("ShaderNodeOutputMaterial")
	tc = N("ShaderNodeTexCoord")
	sep = N("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["UV"], sep.inputs["Vector"])
	attr = N("ShaderNodeAttribute")
	attr.attribute_type = 'OBJECT'
	attr.attribute_name = "t"
	born = N("ShaderNodeMath")
	born.operation = 'MULTIPLY_ADD'
	born.inputs[1].default_value = HEAD_SPAN
	born.inputs[2].default_value = HEAD_T0
	nt.links.new(sep.outputs["X"], born.inputs[0])
	age = N("ShaderNodeMath")
	age.operation = 'SUBTRACT'
	nt.links.new(attr.outputs["Fac"], age.inputs[0])
	nt.links.new(born.outputs["Value"], age.inputs[1])
	## 颜色: 年龄 0 → 0.5 秒映到 0 → 1 的色带(常量分档, 卡通)
	mr = N("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = 0.0
	mr.inputs["From Max"].default_value = 0.5
	nt.links.new(age.outputs["Value"], mr.inputs["Value"])
	ramp = N("ShaderNodeValToRGB")
	ramp.color_ramp.interpolation = 'CONSTANT'
	els = ramp.color_ramp.elements
	els[0].position = 0.0
	els[0].color = (*bc.lin((1.0, 0.98, 0.85)), 1.0)
	els[1].position = 0.12
	els[1].color = (*bc.lin((1.0, 0.86, 0.35)), 1.0)
	for pos, c in ((0.45, (0.98, 0.62, 0.16)), (0.72, (0.70, 0.36, 0.10)), (0.9, (0.36, 0.22, 0.10))):
		e = els.new(pos)
		e.color = (*bc.lin(c), 1.0)
	nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
	## 横向: 离中线越远越暗(裂缝边一圈暗金, 读得出是一道缝)
	vc = N("ShaderNodeMath")
	vc.operation = 'SUBTRACT'
	vc.inputs[1].default_value = 0.5
	nt.links.new(sep.outputs["Y"], vc.inputs[0])
	va = N("ShaderNodeMath")
	va.operation = 'ABSOLUTE'
	nt.links.new(vc.outputs["Value"], va.inputs[0])
	edge = N("ShaderNodeMath")
	edge.operation = 'GREATER_THAN'
	edge.inputs[1].default_value = 0.32
	nt.links.new(va.outputs["Value"], edge.inputs[0])
	dk = N("ShaderNodeMix")
	dk.data_type = 'RGBA'
	nt.links.new(edge.outputs["Value"], dk.inputs["Factor"])
	nt.links.new(ramp.outputs["Color"], dk.inputs[6])
	dk.inputs[7].default_value = (*bc.lin((0.42, 0.24, 0.06)), 1.0)
	em = N("ShaderNodeEmission")
	nt.links.new(dk.outputs[2], em.inputs["Color"])
	## 透明度: (年龄 ≥ 0) × (噪声 > 侵蚀量); 侵蚀量 = (年龄 − 0.32) / 0.23
	ge = N("ShaderNodeMath")
	ge.operation = 'GREATER_THAN'
	ge.inputs[1].default_value = -0.0001
	nt.links.new(age.outputs["Value"], ge.inputs[0])
	er = N("ShaderNodeMapRange")
	er.inputs["From Min"].default_value = 0.32
	er.inputs["From Max"].default_value = 0.55
	nt.links.new(age.outputs["Value"], er.inputs["Value"])
	nz = N("ShaderNodeTexNoise")
	nz.inputs["Scale"].default_value = 9.0
	nz.inputs["Detail"].default_value = 1.0
	tc2 = N("ShaderNodeTexCoord")
	nt.links.new(tc2.outputs["Object"], nz.inputs["Vector"])
	st = N("ShaderNodeMapRange")
	st.inputs["From Min"].default_value = 0.3
	st.inputs["From Max"].default_value = 0.7
	nt.links.new(nz.outputs["Fac"], st.inputs["Value"])
	keep = N("ShaderNodeMath")
	keep.operation = 'GREATER_THAN'
	nt.links.new(st.outputs["Result"], keep.inputs[0])
	nt.links.new(er.outputs["Result"], keep.inputs[1])
	al = N("ShaderNodeMath")
	al.operation = 'MULTIPLY'
	nt.links.new(ge.outputs["Value"], al.inputs[0])
	nt.links.new(keep.outputs["Value"], al.inputs[1])
	tr = N("ShaderNodeBsdfTransparent")
	ms = N("ShaderNodeMixShader")
	nt.links.new(al.outputs["Value"], ms.inputs[0])
	nt.links.new(tr.outputs["BSDF"], ms.inputs[1])
	nt.links.new(em.outputs["Emission"], ms.inputs[2])
	nt.links.new(ms.outputs["Shader"], out.inputs["Surface"])
	return m


# ─────────────────────────────── 素材组 ───────────────────────────────
def make_mats():
	return {
		"gold": bc.toon_mat("gold", C_GOLD, spec=1.0),
		"ruby": bc.toon_mat("ruby", C_RUBY, spec=1.0),
		"emer": bc.toon_mat("emer", C_EMER, spec=1.0),
		"saph": bc.toon_mat("saph", C_SAPH, spec=1.0),
		"sand": bc.toon_mat("sand", C_SAND, erode=True, spec=0.0),
	}


def loot_set(rnd, n_coin, n_gem, prefix, mats, scale=1.0):
	"""n_coin 枚金币 + n_gem 颗宝石(红 / 绿 / 蓝轮流), 进描边集合。"""
	obs = []
	gems = ["ruby", "emer", "saph"]
	for i in range(n_coin):
		ob = mesh_coin("%s_c%d" % (prefix, i), r=0.18 * scale * rnd.uniform(0.88, 1.12), h=0.068 * scale)
		ob.data.materials.append(mats["gold"])
		bc._to_outline(ob)
		obs.append(ob)
	for i in range(n_gem):
		ob = mesh_gem("%s_g%d" % (prefix, i), r=0.13 * scale * rnd.uniform(0.9, 1.15))
		ob.data.materials.append(mats[gems[(i + rnd.randint(0, 2)) % 3]])
		bc._to_outline(ob)
		obs.append(ob)
	rnd.shuffle(obs)
	return obs


def gnd_ring(rnd, mats, r0, r1, t_end, frames, minor=0.1):
	"""贴地沙尘环: 半径 r0 → r1(先快后慢), 越推越矮, 后半段侵蚀掉。名字带 gnd_ ⇒ 只进贴地那遍。"""
	dr = bc.mesh_dust_ring("gnd_ring", rnd, minor=minor)
	dr.data.materials.append(mats["sand"])
	for f in range(frames):
		t = min(1.0, f / float(t_end))
		e = 1.0 - (1.0 - t) ** 3
		R = r0 + (r1 - r0) * e
		dr.scale = (R, R * 0.92, 1.3 - 0.8 * e)
		dr.location = (0.0, 0.0, 0.04)
		dr["erode"] = 0.0 if t < 0.25 else min(1.0, (t - 0.25) / 0.75) * 0.95 + 0.02
		dr.keyframe_insert("scale", frame=f)
		dr.keyframe_insert("location", frame=f)
		dr.keyframe_insert('["erode"]', frame=f)


def sand_puffs(rnd, mats, n, at_z, reach, size, f_end, frames, prefix):
	for i in range(n):
		a = 2 * math.pi * i / n + rnd.uniform(-0.4, 0.4)
		ob = bc.mesh_puff("%s%d" % (prefix, i), rnd)
		ob.data.materials.append(mats["sand"])
		r1 = reach * rnd.uniform(0.7, 1.1)
		bc.key_puff(ob, (0, 0, at_z), (math.cos(a) * r1, math.sin(a) * r1 * 0.8, at_z + rnd.uniform(0.15, 0.35)), 0.04,
			size * rnd.uniform(0.85, 1.15), rnd.randint(0, 1), f_end + rnd.randint(-2, 2), 0.35, frames)


# ─────────────────────────────── 五段 ───────────────────────────────
def build_slam(rnd, frames):
	"""砸点(帧 0 = 宝箱着地; 参考奥恩 Q 第 6~8 帧): 7 枚金币 + 2 颗宝石往上往外崩、落地弹跳; 3 团沙尘; 贴地沙尘环。
	件数是普攻的量(每 1.4 秒一下, 第一版 12 件 + 沿线 15 件 + 每个命中 6 件, 实拍满屏碎金太乱)。"""
	mats = make_mats()
	obs = loot_set(rnd, 7, 2, "sl", mats, 1.15)
	for i, ob in enumerate(obs):
		a = 2 * math.pi * i / len(obs) + rnd.uniform(-0.25, 0.25)
		hs = rnd.uniform(0.9, 2.2)
		v0 = (math.cos(a) * hs, math.sin(a) * hs * 0.8, rnd.uniform(3.4, 5.4))
		w0 = (rnd.uniform(-22, 22), rnd.uniform(-22, 22), rnd.uniform(-10, 10))
		bc.key_ballistic(ob, (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.12), v0, w0, frames, rnd, settle_from=frames - 6, r_ground=0.03)
	sand_puffs(rnd, mats, 3, 0.15, 0.45, 0.2, 13, frames, "sp")
	gnd_ring(rnd, mats, 0.2, 0.95, 12, frames)


def build_pop(rnd, frames):
	"""沿线迸出(帧 0 = 波头扫到这一处; 参考奥恩 Q 第 9~11 帧裂缝经过处碎石往上蹦): 3 枚金币 + 1 颗宝石从地里蹦出、落地; 2 团沙尘。"""
	mats = make_mats()
	obs = loot_set(rnd, 3, 1, "po", mats, 1.0)
	for i, ob in enumerate(obs):
		a = 2 * math.pi * i / len(obs) + rnd.uniform(-0.4, 0.4)
		hs = rnd.uniform(0.3, 1.0)
		bc.key_ballistic(ob, (math.cos(a) * 0.06, math.sin(a) * 0.06, 0.04), (math.cos(a) * hs, math.sin(a) * hs * 0.8, rnd.uniform(2.6, 4.0)),
			(rnd.uniform(-20, 20), rnd.uniform(-20, 20), rnd.uniform(-8, 8)), frames, rnd, settle_from=frames - 5, r_ground=0.03)
	sand_puffs(rnd, mats, 2, 0.06, 0.3, 0.14, 10, frames, "pp")
	gnd_ring(rnd, mats, 0.08, 0.45, 9, frames, minor=0.08)


def build_hit(rnd, frames):
	"""命中(帧 0 = 波头扫到这个敌人; 参考奥恩 Q 第 16~18 帧尽头炸开): 3 枚金币 + 1 颗宝石从身上溅开往外落。"""
	mats = make_mats()
	obs = loot_set(rnd, 3, 1, "hi", mats, 0.9)
	for i, ob in enumerate(obs):
		a = 2 * math.pi * i / len(obs) + rnd.uniform(-0.3, 0.3)
		hs = rnd.uniform(1.4, 2.6)
		bc.key_ballistic(ob, (0.0, 0.0, 0.45), (math.cos(a) * hs, math.sin(a) * hs * 0.8, rnd.uniform(1.6, 3.0)),
			(rnd.uniform(-24, 24), rnd.uniform(-24, 24), rnd.uniform(-10, 10)), frames, rnd, settle_from=frames - 5, r_ground=0.03)


def build_wave(rnd, frames):
	"""金色裂光(只有贴地那遍; 正上方渲, 沿 +X = 砸出去的方向): 帧 0 起波头 0.18 秒从左端推到右端, 身后由白金冷却成金 → 橙 → 焦褐, 0.55 秒侵蚀掉。"""
	cr = crack_mesh("gnd_crack", rnd, WAVE_LEN)
	cr.data.materials.append(crack_mat("crack"))
	for f in range(frames):
		cr["t"] = f / float(FPS)
		cr.keyframe_insert('["t"]', frame=f)


SPECS = {
	## which: (帧数, 每帧像素(宽, 高), 正交宽度(米), 画面中心离地高度(米), 构建函数, 随机种子, 贴地那遍的正交宽度(米))
	"slam": (18, (192, 192), 3.0, 0.4, build_slam, 2011, 3.0),
	"pop": (15, (128, 128), 2.0, 0.3, build_pop, 2012, 2.0),
	"pop2": (15, (128, 128), 2.0, 0.3, build_pop, 2013, 2.0),
	"hit": (14, (128, 128), 2.4, 0.45, build_hit, 2014, 2.4),
	"wave": (22, (256, 48), 3.2, 0.0, build_wave, 2015, 3.2),
}


def apply_pass(pas):
	"""立着那遍: 金币 / 宝石 / 沙尘团(公告板, 画在龟前面); 贴地那遍: 名字带 gnd_ 的(沙尘环 / 裂光)+ 金币宝石的影子(压在龟脚下)。"""
	outlined = bpy.data.collections.get("outlined")
	loot = set(outlined.objects) if outlined else set()
	for ob in bpy.data.objects:
		if ob.type != 'MESH' or ob.name == "ground":
			continue
		g = ob.name.startswith("gnd_")
		if pas == "up":
			if g:
				ob.hide_render = True
		elif ob in loot:
			ob.visible_camera = False      # 看不见, 照样投影子
		elif not g:
			ob.hide_render = True


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	ap = argparse.ArgumentParser()
	ap.add_argument("--which", required=True, choices=sorted(SPECS.keys()))
	ap.add_argument("--out", required=True)
	ap.add_argument("--pass", dest="pas", default="up", choices=["up", "gnd"])
	ap.add_argument("--only", type=int, default=-1, help="只渲这一帧(调试)")
	a = ap.parse_args(argv)
	frames, (pw, ph), ortho, tz, fn, seed, ortho_g = SPECS[a.which]
	bc.clear_scene()
	bc.setup(max(pw, ph), ortho_g if a.pas == "gnd" else ortho, tz, frames, a.pas)
	sc = bpy.context.scene
	if os.environ.get("CHEST_THREADS"):
		sc.render.threads_mode = 'FIXED'
		sc.render.threads = int(os.environ["CHEST_THREADS"])
	sc.render.resolution_x = pw
	sc.render.resolution_y = ph
	ls = bpy.data.linestyles.get("candy_line")
	if ls is not None:
		ls.color = bc.lin(OUTLINE)
		ls.thickness = 1.2          # 金币比糖块小, 1.6 像素的描边会把侧立的币吃成一根深色棍
	sc.render.line_thickness = 1.2
	fn(random.Random(seed), frames)
	apply_pass(a.pas)
	if a.only >= 0:
		sc.frame_set(a.only)
		os.makedirs(a.out, exist_ok=True)
		sc.render.filepath = os.path.join(a.out, "only_%02d.png" % a.only)
		bpy.ops.render.render(write_still=True)
	else:
		bc.render(a.out, frames)
	print("[blender_chest_fx] %s/%s 渲出 %d 帧 → %s" % (a.which, a.pas, frames if a.only < 0 else 1, a.out))


if __name__ == "__main__":
	main()
