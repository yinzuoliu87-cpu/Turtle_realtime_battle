# -*- coding: utf-8 -*-
"""tools/assetgen/spine_eval.py — Spine 4.3 JSON 求值 + 1:1 像素渲染(离线, 确定性)。2026-11-05。

由来: 方案书 docs/plans/20261105b-龟美术统一与动作补全.md(用户 11-05「我们可以想办法把它转变为这个像素序列帧嘛…待机的时候只能用这一十一只这个原画」)。
  主站时期外包的 11 只龟是 Spine 4.3 导出(json + atlas + png), 只有一个 3.33 秒待机; 游戏里不装 Spine 运行库(直播录流只认序列帧),
  ⇒ 离线把它渲成像素序列帧。只实现这 11 只真用到的那一套(11-05 逐只统计, 方案书 §2.1):
  骨骼(平移 / 旋转 / 缩放 / 错切, 继承 normal)· 贝塞尔 / 阶梯 / 线性曲线 · 区域 / 带权网格 / 网格变形 · 插槽颜色 / 换图 ·
  逐帧序列(sequence)· 混合 normal / additive(贴图透明度预乘)· 裁切蒙版(clipping)· IK 约束(单骨 / 双骨, mix / compress)·
  transform 约束(世界坐标 x / y)。path / physics 约束与 IK stretch / softness 没用到, 遇到就报错。
  对账: tools/assetgen/spine_ref_check.py 拿 Spine 官方运行库逐帧比骨骼与顶点(11-05 起; 之前只比静态原画, 漏了 IK)。
  公式照 spine-ts 4.x(Bone.updateWorldTransform / RegionAttachment.updateRegion / MeshAttachment.updateRegion / SequenceTimeline)。
渲染: 三角形光栅化, 像素中心取样, **最近邻**取贴图(像素画不糊), 输出 RGBA(非预乘)。
用法:
  python tools/assetgen/spine_eval.py <turtleNN.json> --t 0 --out a.png          # 渲一帧
  python tools/assetgen/spine_eval.py <turtleNN.json> --sheet out_dir --fps 30    # 整段待机逐帧
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

EPS = 0.00001   # spine-core MathUtils.epsilon


# ══════════════════════════════ atlas ══════════════════════════════

def load_atlas(path: str) -> dict:
	"""libGDX / Spine 4 atlas → {region_name: dict(page, x, y, w, h, ox, oy, ow, oh, rot)}; 页图读成 float32 RGBA(预乘)。"""
	regions = {}
	pages = {}
	lines = open(path, encoding="utf-8").read().splitlines()
	i = 0
	page = None
	pma = False
	base = os.path.dirname(path)
	while i < len(lines):
		ln = lines[i].strip()
		i += 1
		if ln == "":
			page = None
			continue
		if page is None:
			page = ln
			im = Image.open(os.path.join(base, page)).convert("RGBA")
			pma = False
			# 页属性
			while i < len(lines) and ":" in lines[i]:
				k, v = lines[i].split(":", 1)
				if k.strip() == "pma":
					pma = v.strip() == "true"
				i += 1
			arr = np.asarray(im, dtype=np.float32) / 255.0
			if not pma:   # 统一成预乘
				arr[..., :3] *= arr[..., 3:4]
			pages[page] = arr
			continue
		name = ln
		r = {"page": page, "rot": 0, "ox": 0.0, "oy": 0.0}
		while i < len(lines) and ":" in lines[i]:
			k, v = lines[i].split(":", 1)
			k = k.strip()
			vals = [x.strip() for x in v.split(",")]
			if k == "bounds":
				r["x"], r["y"], r["w"], r["h"] = [int(x) for x in vals]
			elif k == "offsets":
				r["ox"], r["oy"], r["ow"], r["oh"] = [float(x) for x in vals]
			elif k == "rotate":
				r["rot"] = 90 if vals[0] == "true" else int(vals[0])
			i += 1
		if "ow" not in r:
			r["ow"], r["oh"] = float(r["w"]), float(r["h"])
		regions[name] = r
	return {"regions": regions, "pages": pages}


# ══════════════════════════════ 曲线 / 时间轴 ══════════════════════════════

def _bezier_y(t: float, t0: float, v0: float, cx1: float, cy1: float, cx2: float, cy2: float, t1: float, v1: float) -> float:
	"""控制点是绝对的(时间, 值)。照 spine-core CurveTimeline.setBezier / getBezierValue: 不精确解曲线,
	而是前向差分出 9 个点, 段内按 (t0,v0)–9 点–(t1,v1) 折线线性插值。11-05 对账前用的是精确解(二分求参数),
	与官方差到 1.4 单位(face-f 平移幅度 210 的那段)。"""
	tmpx = (t0 - cx1 * 2 + cx2) * 0.03
	tmpy = (v0 - cy1 * 2 + cy2) * 0.03
	dddx = ((cx1 - cx2) * 3 - t0 + t1) * 0.006
	dddy = ((cy1 - cy2) * 3 - v0 + v1) * 0.006
	ddx, ddy = tmpx * 2 + dddx, tmpy * 2 + dddy
	dx = (cx1 - t0) * 0.3 + tmpx + dddx * 0.16666667
	dy = (cy1 - v0) * 0.3 + tmpy + dddy * 0.16666667
	x, y = t0 + dx, v0 + dy
	pts = []
	for _ in range(9):
		pts.append((x, y))
		dx += ddx
		dy += ddy
		ddx += dddx
		ddy += dddy
		x += dx
		y += dy
	if pts[0][0] > t:
		return v0 + (t - t0) / (pts[0][0] - t0) * (pts[0][1] - v0)
	for k in range(1, 9):
		if pts[k][0] >= t:
			px, py = pts[k - 1]
			return py + (t - px) / (pts[k][0] - px) * (pts[k][1] - py)
	px, py = pts[8]
	return py + (t - px) / (t1 - px) * (v1 - py)


def _kt(k: dict) -> float:
	"""关键帧时间, 按 32 位浮点取(官方 spine-core 的 frames 是 Float32Array: 0.6 存成 0.60000002,
	t = 0.6 时官方还算「首帧之前」。11-05 对账财神龟 coin1 在 t=0.6 差 0.9 才查出来)。"""
	return float(np.float32(k.get("time", 0.0)))


def sample(keys: list, t: float, fields: list, defaults: list) -> list:
	"""关键帧列表在时刻 t 的值。fields = 这条时间轴的通道名(rotate: ["value"], translate: ["x","y"] …)。"""
	if not keys:
		return list(defaults)
	vals = lambda k: [float(k.get(f, d)) for f, d in zip(fields, defaults)]
	times = [_kt(k) for k in keys]
	if t < times[0]:
		return list(defaults)      # 首个关键帧之前 = setup 姿势(官方 MixBlend.first)
	if t >= times[-1]:
		return vals(keys[-1])
	i = max(j for j in range(len(times)) if times[j] <= t)
	k0, k1 = keys[i], keys[i + 1]
	t0, t1 = times[i], times[i + 1]
	a, b = vals(k0), vals(k1)
	c = k0.get("curve")
	if c == "stepped":
		return a
	out = []
	for ch in range(len(fields)):
		if isinstance(c, list) and len(c) >= 4 * (ch + 1):
			cx1, cy1, cx2, cy2 = c[4 * ch: 4 * ch + 4]
			out.append(_bezier_y(t, t0, a[ch], cx1, cy1, cx2, cy2, t1, b[ch]))
		else:
			u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
			out.append(a[ch] + (b[ch] - a[ch]) * u)
	return out


def _hex_rgba(h: str) -> np.ndarray:
	h = (h or "ffffffff").ljust(8, "f")
	return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4, 6)], dtype=np.float32)


def sample_color(keys: list, t: float) -> np.ndarray:
	"""rgba 时间轴(颜色写成 rrggbbaa 字符串; 曲线 4 通道)。"""
	if not keys or t < _kt(keys[0]):
		return None                # 首个关键帧之前 = 插槽 setup 颜色(调用方保留)
	conv = [dict(k, r=_hex_rgba(k.get("color"))[0], g=_hex_rgba(k.get("color"))[1], b=_hex_rgba(k.get("color"))[2], a=_hex_rgba(k.get("color"))[3]) for k in keys]
	## 官方 Color.set 会夹到 [0, 1](财神龟 coin1 的透明度曲线控制点 1.67, 不夹会冲到 1.10; 11-05 对账查出)
	return np.clip(np.array(sample(conv, t, ["r", "g", "b", "a"], [1, 1, 1, 1]), dtype=np.float32), 0.0, 1.0)


# ══════════════════════════════ 骨骼 ══════════════════════════════

class Skeleton:
	def __init__(self, data: dict, atlas: dict):
		self.data = data
		self.atlas = atlas
		self.bones = data["bones"]
		self.bone_index = {b["name"]: i for i, b in enumerate(self.bones)}
		self.slots = data["slots"]
		self.skin = {}
		for s in data.get("skins", []):
			if s.get("name", "default") == "default":
				self.skin = s.get("attachments", {})
		self.sk = data.get("skeleton", {})

	# ── 某时刻的姿势 ──
	def pose(self, anim_name: str, t: float) -> dict:
		an = self.data.get("animations", {}).get(anim_name, {})
		local = []
		for b in self.bones:
			L = {k: float(b.get(k, d)) for k, d in (("x", 0), ("y", 0), ("rotation", 0), ("scaleX", 1), ("scaleY", 1), ("shearX", 0), ("shearY", 0))}
			tl = an.get("bones", {}).get(b["name"], {})
			if "rotate" in tl:
				L["rotation"] += sample(tl["rotate"], t, ["value"], [0])[0]
			if "translate" in tl:
				x, y = sample(tl["translate"], t, ["x", "y"], [0, 0])
				L["x"] += x
				L["y"] += y
			if "translatex" in tl:
				L["x"] += sample(tl["translatex"], t, ["value"], [0])[0]
			if "translatey" in tl:
				L["y"] += sample(tl["translatey"], t, ["value"], [0])[0]
			if "scale" in tl:
				sx, sy = sample(tl["scale"], t, ["x", "y"], [1, 1])
				L["scaleX"] *= sx
				L["scaleY"] *= sy
			if "scalex" in tl:
				L["scaleX"] *= sample(tl["scalex"], t, ["value"], [1])[0]
			if "scaley" in tl:
				L["scaleY"] *= sample(tl["scaley"], t, ["value"], [1])[0]
			if "shear" in tl:
				hx, hy = sample(tl["shear"], t, ["x", "y"], [0, 0])
				L["shearX"] += hx
				L["shearY"] += hy
			local.append(L)
		world = []
		for i in range(len(self.bones)):
			world.append(self._bone_world(i, local, world))
		self._apply_constraints(local, world)
		# 插槽: 颜色 / 当前部件 / 部件时间轴(变形、序列)
		slots = []
		for s in self.slots:
			color = _hex_rgba(s.get("color"))
			att = s.get("attachment")
			stl = an.get("slots", {}).get(s["name"], {})
			if "rgba" in stl:
				sc = sample_color(stl["rgba"], t)
				if sc is not None:
					color = sc
			if "alpha" in stl and t >= _kt(stl["alpha"][0]):
				color = color.copy()
				color[3] = min(1.0, max(0.0, sample(stl["alpha"], t, ["value"], [1])[0]))
			if "attachment" in stl:
				ks = stl["attachment"]
				cur = None
				for k in ks:
					if _kt(k) <= t:
						cur = k
				if cur is not None:
					att = cur.get("name")
			slots.append({"slot": s, "color": color, "att": att})
		return {"world": world, "slots": slots, "anim": an, "t": t}

	# ── 骨骼世界变换(BonePose.updateWorldTransform, inherit = normal) ──
	def _bone_world(self, i: int, local: list, world: list) -> tuple:
		L = local[i]
		rx = math.radians(L["rotation"] + L["shearX"])
		ry = math.radians(L["rotation"] + 90 + L["shearY"])
		la, lb = math.cos(rx) * L["scaleX"], math.cos(ry) * L["scaleY"]
		lc, ld = math.sin(rx) * L["scaleX"], math.sin(ry) * L["scaleY"]
		p = self.bones[i].get("parent")
		if p is None:
			return (la, lb, lc, ld, L["x"], L["y"])
		pa, pb, pc, pd, px, py = world[self.bone_index[p]]
		return (pa * la + pb * lc, pa * lb + pb * ld, pc * la + pd * lc, pc * lb + pd * ld,
			pa * L["x"] + pb * L["y"] + px, pc * L["x"] + pd * L["y"] + py)

	def _descendants(self, i: int) -> list:
		"""i 及其全部子孙, 按骨骼表顺序(父在子前)。"""
		if not hasattr(self, "_desc_cache"):
			self._desc_cache = {}
		if i not in self._desc_cache:
			names = {self.bones[i]["name"]}
			out = [i]
			for j in range(i + 1, len(self.bones)):
				if self.bones[j].get("parent") in names:
					names.add(self.bones[j]["name"])
					out.append(j)
			self._desc_cache[i] = out
		return self._desc_cache[i]

	def _refresh(self, idxs: list, local: list, world: list) -> None:
		"""这些骨的局部变换改了 ⇒ 重算它们和全部子孙的世界变换。"""
		todo = sorted({j for i in idxs for j in self._descendants(i)})
		for j in todo:
			world[j] = self._bone_world(j, local, world)

	# ── 约束(Spine 4.3 的 constraints 数组, 按数组顺序应用; 照 spine-core 4.3.13 移植) ──
	#   11-05 用官方运行库逐帧对账(tools/assetgen/spine_ref_check.py)才发现: 10 只都有 8 条腿部 IK + 1 条 transform,
	#   之前没实现 ⇒ 待机里四肢差 2–4 像素(IK 目标骨在动, 腿不跟)。这 11 只用不到的模式一律报错, 不悄悄忽略。
	def _apply_constraints(self, local: list, world: list) -> None:
		cons = list(self.data.get("constraints", []))
		for k in ("ik", "transform", "path", "physics"):   # 4.2 及以前的分表写法
			for c in self.data.get(k, []):
				cons.append(dict(c, type=k))
		for c in cons:
			typ = c.get("type")
			if typ == "ik":
				self._ik(c, local, world)
			elif typ == "transform":
				self._transform(c, local, world)
			else:
				raise NotImplementedError("约束类型 %s 未实现(%s)" % (typ, c.get("name")))

	def _ik(self, c: dict, local: list, world: list) -> None:
		mix = float(c.get("mix", 1))
		if mix == 0:
			return
		if c.get("stretch", False) or float(c.get("softness", 0)) != 0 or "scaleY" in c:
			raise NotImplementedError("IK stretch / softness / scaleY 未实现(%s)" % c.get("name"))
		tw = world[self.bone_index[c["target"]]]
		bi = [self.bone_index[n] for n in c["bones"]]
		if len(bi) == 1:
			self._ik1(bi[0], local, world, tw[4], tw[5], bool(c.get("compress", False)), mix)
			self._refresh(bi, local, world)
		else:
			bend = 1 if c.get("bendPositive", True) else -1
			self._ik2(bi[0], bi[1], local, world, tw[4], tw[5], bend, mix)
			self._refresh(bi, local, world)

	def _ik1(self, i: int, local: list, world: list, target_x: float, target_y: float, compress: bool, mix: float) -> None:
		L = local[i]
		pa, pb, pc, pd, pwx, pwy = world[self.bone_index[self.bones[i]["parent"]]]
		rot_ik = -L["shearX"] - L["rotation"]
		x, y = target_x - pwx, target_y - pwy
		d = pa * pd - pb * pc
		if abs(d) <= EPS:
			tx = ty = 0.0
		else:
			tx = (x * pd - y * pb) / d - L["x"]
			ty = (y * pa - x * pc) / d - L["y"]
		rot_ik += math.degrees(math.atan2(ty, tx))
		if L["scaleX"] < 0:
			rot_ik += 180
		if rot_ik > 180:
			rot_ik -= 360
		elif rot_ik <= -180:
			rot_ik += 360
		L["rotation"] += rot_ik * mix
		if compress:
			blen = float(self.bones[i].get("length", 0)) * L["scaleX"]
			if blen > EPS:
				dd = tx * tx + ty * ty
				if dd < blen * blen:
					L["scaleX"] *= (math.sqrt(dd) / blen - 1) * mix + 1

	def _ik2(self, ip: int, ic: int, local: list, world: list, target_x: float, target_y: float, bend: int, mix: float) -> None:
		P, C = local[ip], local[ic]
		px, py, psx, psy, csx = P["x"], P["y"], P["scaleX"], P["scaleY"], C["scaleX"]
		if psx < 0:
			psx, os1, s2 = -psx, 180.0, -1
		else:
			os1, s2 = 0.0, 1
		if psy < 0:
			psy, s2 = -psy, -s2
		if csx < 0:
			csx, os2 = -csx, 180.0
		else:
			os2 = 0.0
		a, b, c, d, pwx, pwy = world[ip]
		u = abs(psx - psy) <= EPS
		if not u:
			C["y"] = 0.0
			cwx, cwy = a * C["x"] + pwx, c * C["x"] + pwy
		else:
			cwx, cwy = a * C["x"] + b * C["y"] + pwx, c * C["x"] + d * C["y"] + pwy
		a, b, c, d, ppx, ppy = world[self.bone_index[self.bones[ip]["parent"]]]
		idet = a * d - b * c
		x, y = cwx - ppx, cwy - ppy
		idet = 0.0 if abs(idet) <= EPS else 1.0 / idet
		dx, dy = (x * d - y * b) * idet - px, (y * a - x * c) * idet - py
		l1 = math.sqrt(dx * dx + dy * dy)
		l2 = float(self.bones[ic].get("length", 0)) * csx
		if l1 < EPS:
			self._ik1(ip, local, world, target_x, target_y, False, mix)
			C["rotation"] = 0.0
			return
		x, y = target_x - ppx, target_y - ppy
		tx, ty = (x * d - y * b) * idet - px, (y * a - x * c) * idet - py
		dd = tx * tx + ty * ty
		if u:
			l2 *= psx
			cos = (dd - l1 * l1 - l2 * l2) / (2 * l1 * l2)
			if cos < -1:
				cos, a2 = -1.0, math.pi * bend
			elif cos > 1:
				cos, a2 = 1.0, 0.0
			else:
				a2 = math.acos(cos) * bend
			a = l1 + l2 * cos
			b = l2 * math.sin(a2)
			a1 = math.atan2(ty * a - tx * b, tx * a + ty * b)
		else:
			a, b = psx * l2, psy * l2
			aa, bb, ta = a * a, b * b, math.atan2(ty, tx)
			c = bb * l1 * l1 + aa * dd - aa * bb
			c1, c2 = -2 * bb * l1, bb - aa
			d = c1 * c1 - 4 * c2 * c
			done = False
			if d >= 0:
				q = math.sqrt(d)
				if c1 < 0:
					q = -q
				q = -(c1 + q) * 0.5
				r0, r1 = q / c2, c / q
				r = r0 if abs(r0) < abs(r1) else r1
				r0 = dd - r * r
				if r0 >= 0:
					y = math.sqrt(r0) * bend
					a1 = ta - math.atan2(y, r)
					a2 = math.atan2(y / psy, (r - l1) / psx)
					done = True
			if not done:
				min_a, min_x, min_y = math.pi, l1 - a, 0.0
				min_d = min_x * min_x
				max_a, max_x, max_y = 0.0, l1 + a, 0.0
				max_d = max_x * max_x
				c = -a * l1 / (aa - bb)
				if -1 <= c <= 1:
					c = math.acos(c)
					x = a * math.cos(c) + l1
					y = b * math.sin(c)
					d = x * x + y * y
					if d < min_d:
						min_a, min_d, min_x, min_y = c, d, x, y
					if d > max_d:
						max_a, max_d, max_x, max_y = c, d, x, y
				if dd <= (min_d + max_d) * 0.5:
					a1 = ta - math.atan2(min_y * bend, min_x)
					a2 = min_a * bend
				else:
					a1 = ta - math.atan2(max_y * bend, max_x)
					a2 = max_a * bend
		os_ = math.atan2(C["y"], C["x"]) * s2
		a1 = math.degrees(a1 - os_) + os1 - P["rotation"]
		if a1 > 180:
			a1 -= 360
		elif a1 <= -180:
			a1 += 360
		P["rotation"] += a1 * mix
		a2 = (math.degrees(a2 + os_) - C["shearX"]) * s2 + os2 - C["rotation"]
		if a2 > 180:
			a2 -= 360
		elif a2 <= -180:
			a2 += 360
		C["rotation"] += a2 * mix

	def _transform(self, c: dict, local: list, world: list) -> None:
		"""世界坐标模式的 x / y 传递(本批 10 只只用到 face-f → face-b, 而且没有网格挂在这两根骨上, 画面不受影响; 照实现以便逐帧对账)。"""
		if c.get("localSource", False) or c.get("localTarget", False) or c.get("clamp", False):
			raise NotImplementedError("transform 约束 local / clamp 未实现(%s)" % c.get("name"))
		props = c.get("properties", {})
		mix_x = float(c.get("mixX", 1))
		mix_y = float(c.get("mixY", mix_x))
		off_x, off_y = float(c.get("x", 0)), float(c.get("y", 0))
		additive = bool(c.get("additive", False))
		sa, sb, sc, sd, swx, swy = world[self.bone_index[c["source"]]]
		for name in c["bones"]:
			bi = self.bone_index[name]
			for fname, fe in props.items():
				if fname == "x":
					value = off_x * sa + off_y * sb + swx
				elif fname == "y":
					value = off_x * sc + off_y * sd + swy
				else:
					raise NotImplementedError("transform 约束 from %s 未实现(%s)" % (fname, c.get("name")))
				value -= float(fe.get("offset", 0))
				for tname, te in fe.get("to", {}).items():
					m = mix_x if tname == "x" else mix_y if tname == "y" else None
					if m is None:
						raise NotImplementedError("transform 约束 to %s 未实现(%s)" % (tname, c.get("name")))
					if m == 0:
						continue
					v = float(te.get("offset", 0)) + value * float(te.get("scale", 1))
					a, b, cc, d, wx, wy = world[bi]
					if tname == "x":
						if not additive:
							v -= wx
						world[bi] = (a, b, cc, d, wx + v * m, wy)
					else:
						if not additive:
							v -= wy
						world[bi] = (a, b, cc, d, wx, wy + v * m)
			## 世界坐标直接改了 ⇒ 子孙从它的新世界变换重算
			for j in self._descendants(bi)[1:]:
				world[j] = self._bone_world(j, local, world)

	# ── 部件在世界坐标里的三角形 ──
	def _deform(self, an: dict, slot: str, att: str, t: float, n: int):
		keys = an.get("attachments", {}).get("default", {}).get(slot, {}).get(att, {}).get("deform")
		if not keys:
			return None
		frames = []
		for k in keys:
			v = np.zeros(n, dtype=np.float64)
			arr = k.get("vertices", [])
			off = int(k.get("offset", 0))
			v[off:off + len(arr)] = arr
			frames.append(v)
		times = [_kt(k) for k in keys]
		if t < times[0]:
			return None            # 首个关键帧之前 = setup 顶点
		if t == times[0] and len(times) == 1:
			return frames[0]
		if t >= times[-1]:
			return frames[-1]
		i = max(j for j in range(len(times)) if times[j] <= t)
		c = keys[i].get("curve")
		if c == "stepped":
			return frames[i]
		t0, t1 = times[i], times[i + 1]
		if isinstance(c, list) and len(c) >= 4:
			u = _bezier_y(t, t0, 0.0, c[0], c[1], c[2], c[3], t1, 1.0)
		else:
			u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
		return frames[i] + (frames[i + 1] - frames[i]) * u

	def _seq_index(self, an: dict, slot: str, att: str, seqdef: dict, t: float) -> int:
		"""逐帧序列当前第几张。照 spine-core 4.3.13: 关键帧没写 delay 就沿用上一个关键帧的 delay(SkeletonJson 的 lastDelay);
		取帧 index += trunc((t - 关键帧时刻) / delay + 0.00001); 结果超出张数按 resolveIndex 夹到最后一张。
		(11-05 对账才查出: 天使龟 / 财神龟壳光 1.73 秒那个关键帧没写 delay, 之前当 0 ⇒ 一直停在第 01 张。)"""
		count = int(seqdef.get("count", 1))
		setup = int(seqdef.get("setup", 0))
		keys = an.get("attachments", {}).get("default", {}).get(slot, {}).get(att, {}).get("sequence")
		if not keys or t < _kt(keys[0]):
			return setup
		cur = None
		last_delay = 0.0
		cur_delay = 0.0
		for k in keys:
			d = float(k.get("delay", last_delay))
			last_delay = d
			if _kt(k) <= t:
				cur = k
				cur_delay = d
		mode = cur.get("mode", "hold")
		idx = int(cur.get("index", 0))
		if mode != "hold":
			step = (t - _kt(cur)) / cur_delay + 0.00001 if cur_delay > 0 else 0.0
			idx += int(step)
			if mode == "once":
				idx = min(count - 1, idx)
			elif mode == "loop":
				idx %= count
			elif mode == "pingpong":
				n = (count << 1) - 2
				idx = 0 if n == 0 else idx % n
				if idx >= count:
					idx = n - idx
			elif mode == "onceReverse":
				idx = max(count - 1 - idx, 0)
			elif mode == "loopReverse":
				idx = count - 1 - (idx % count)
			elif mode == "pingpongReverse":
				n = (count << 1) - 2
				idx = 0 if n == 0 else (idx + count - 1) % n
				if idx >= count:
					idx = n - idx
			else:
				raise NotImplementedError("序列模式 %s" % mode)
		return min(idx, count - 1)

	def _region(self, name: str):
		r = self.atlas["regions"].get(name)
		if r is None:
			raise KeyError("atlas 里没有区域 %s" % name)
		return r

	def _uvs_for(self, r: dict, region_uvs: np.ndarray, tw: int, th: int) -> np.ndarray:
		"""MeshAttachment.updateRegion: 部件 UV(0~1, 相对未裁留白的原图)→ 贴图像素坐标。"""
		ru, rv = r["x"] / tw, r["y"] / th
		out = np.empty_like(region_uvs)
		if r["rot"] == 90:
			u = ru - (r["oh"] - r["oy"] - r["h"]) / tw
			v = rv - (r["ow"] - r["ox"] - r["w"]) / th
			w, h = r["oh"] / tw, r["ow"] / th
			out[0::2] = u + region_uvs[1::2] * w
			out[1::2] = v + (1 - region_uvs[0::2]) * h
		else:
			u = ru - r["ox"] / tw
			v = rv - (r["oh"] - r["oy"] - r["h"]) / th
			w, h = r["ow"] / tw, r["oh"] / th
			out[0::2] = u + region_uvs[0::2] * w
			out[1::2] = v + region_uvs[1::2] * h
		out[0::2] *= tw
		out[1::2] *= th
		return out

	def triangles(self, ps: dict):
		"""按绘制顺序产出 (世界顶点 N×2, 贴图像素 UV N×2, 三角形索引, 页名, 颜色 rgba, 混合, 是不是裁切)。"""
		world = ps["world"]
		an = ps["anim"]
		t = ps["t"]
		for si, st in enumerate(ps["slots"]):
			s = st["slot"]
			name = st["att"]
			if not name:
				continue
			a = self.skin.get(s["name"], {}).get(name)
			if a is None:
				continue
			typ = a.get("type", "region")
			bone = world[self.bone_index[s["bone"]]]
			if typ == "clipping":
				## 裁切多边形也可能带变形时间轴(冰龟 shellmask; 11-05 对账前漏了, 差 20 单位)
				nvc = int(a.get("vertexCount", 0))
				dv = self._deform(an, s["name"], name, t, len(a["vertices"]) if len(a["vertices"]) > nvc * 2 else nvc * 2)
				wv = self._mesh_world(a, bone, world, dv, nvc)
				yield {"clip": True, "verts": wv, "end": a.get("end"), "slot": s["name"]}
				continue
			path = a.get("path", name)
			seq = a.get("sequence")
			if seq is not None:
				idx = self._seq_index(an, s["name"], name, seq, t)
				path = "%s%s" % (path, str(int(seq.get("start", 1)) + idx).zfill(int(seq.get("digits", 0))))
			r = self._region(path)
			page = self.atlas["pages"][r["page"]]
			th, tw = page.shape[0], page.shape[1]
			color = st["color"] * _hex_rgba(a.get("color"))
			if typ == "region":
				verts, uvs = self._region_quad(a, r, bone, tw, th)
				tris = np.array([0, 1, 2, 2, 3, 0])
			elif typ == "mesh":
				n_uv = len(a["uvs"])
				dv = self._deform(an, s["name"], name, t, len(a["vertices"]) if len(a["vertices"]) > n_uv else n_uv)
				verts = self._mesh_world(a, bone, world, dv, n_uv // 2)
				uvs = self._uvs_for(r, np.array(a["uvs"], dtype=np.float64), tw, th).reshape(-1, 2)
				tris = np.array(a["triangles"])
			else:
				continue
			yield {"clip": False, "verts": verts, "uvs": uvs, "tris": tris, "page": r["page"], "color": color,
				"blend": s.get("blend", "normal"), "slot": s["name"], "region": path}

	def _mesh_world(self, a: dict, bone, world, deform, nverts: int) -> np.ndarray:
		v = a["vertices"]
		out = np.zeros((nverts, 2), dtype=np.float64)
		if len(v) == nverts * 2:   # 不带权: 相对插槽骨骼
			arr = np.array(v, dtype=np.float64)
			if deform is not None:
				arr = arr + deform
			ba, bb, bc, bd, bx, by = bone
			out[:, 0] = ba * arr[0::2] + bb * arr[1::2] + bx
			out[:, 1] = bc * arr[0::2] + bd * arr[1::2] + by
			return out
		i = 0
		f = 0
		for vi in range(nverts):
			n = int(v[i])
			i += 1
			wx = wy = 0.0
			for _ in range(n):
				bi = int(v[i])
				vx, vy, w = v[i + 1], v[i + 2], v[i + 3]
				if deform is not None:
					vx += deform[f]
					vy += deform[f + 1]
				ba, bb, bc, bd, bx, by = world[bi]
				wx += (ba * vx + bb * vy + bx) * w
				wy += (bc * vx + bd * vy + by) * w
				i += 4
				f += 2
			out[vi] = (wx, wy)
		return out

	def _region_quad(self, a: dict, r: dict, bone, tw: int, th: int):
		"""RegionAttachment.updateRegion + computeWorldVertices。顶点顺序 BL, UL, UR, BR。"""
		width, height = float(a.get("width", r["ow"])), float(a.get("height", r["oh"]))
		sx, sy = float(a.get("scaleX", 1)), float(a.get("scaleY", 1))
		rot = math.radians(float(a.get("rotation", 0)))
		x, y = float(a.get("x", 0)), float(a.get("y", 0))
		rsx = width / r["ow"] * sx
		rsy = height / r["oh"] * sy
		lx = -width / 2 * sx + r["ox"] * rsx
		ly = -height / 2 * sy + r["oy"] * rsy
		lx2 = lx + r["w"] * rsx
		ly2 = ly + r["h"] * rsy
		c, s_ = math.cos(rot), math.sin(rot)
		corners = []
		for px, py in ((lx, ly), (lx, ly2), (lx2, ly2), (lx2, ly)):
			corners.append((px * c - py * s_ + x, px * s_ + py * c + y))
		ba, bb, bc, bd, bx, by = bone
		verts = np.array([(ba * px + bb * py + bx, bc * px + bd * py + by) for px, py in corners])
		u0, v0 = r["x"], r["y"]
		if r["rot"] == 90:
			u1, v1 = r["x"] + r["h"], r["y"] + r["w"]
			uvs = np.array([(u1, v1), (u0, v1), (u0, v0), (u1, v0)], dtype=np.float64)
		else:
			u1, v1 = r["x"] + r["w"], r["y"] + r["h"]
			uvs = np.array([(u0, v1), (u0, v0), (u1, v0), (u1, v1)], dtype=np.float64)
		return verts, uvs


# ══════════════════════════════ 光栅化 ══════════════════════════════

def _raster_tri(dst: np.ndarray, mask, p, uv, tex: np.ndarray, color: np.ndarray, blend: str) -> None:
	H, W = dst.shape[0], dst.shape[1]
	x0 = max(int(math.floor(min(p[:, 0]))), 0)
	x1 = min(int(math.ceil(max(p[:, 0]))), W - 1)
	y0 = max(int(math.floor(min(p[:, 1]))), 0)
	y1 = min(int(math.ceil(max(p[:, 1]))), H - 1)
	if x1 < x0 or y1 < y0:
		return
	ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
	cx = xs + 0.5
	cy = ys + 0.5
	(ax, ay), (bx, by), (qx, qy) = p
	den = (by - qy) * (ax - qx) + (qx - bx) * (ay - qy)
	if abs(den) < 1e-12:
		return
	w0 = ((by - qy) * (cx - qx) + (qx - bx) * (cy - qy)) / den
	w1 = ((qy - ay) * (cx - qx) + (ax - qx) * (cy - qy)) / den
	w2 = 1.0 - w0 - w1
	eps = -1e-7
	inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
	if not inside.any():
		return
	u = w0 * uv[0, 0] + w1 * uv[1, 0] + w2 * uv[2, 0]
	v = w0 * uv[0, 1] + w1 * uv[1, 1] + w2 * uv[2, 1]
	ti = np.clip(np.floor(u).astype(int), 0, tex.shape[1] - 1)   # 最近邻
	tj = np.clip(np.floor(v).astype(int), 0, tex.shape[0] - 1)
	src = tex[tj, ti].copy()   # 预乘 RGBA
	src[..., :3] *= color[:3] * color[3]
	src[..., 3] *= color[3]
	m = inside
	if mask is not None:
		m = m & mask[y0:y1 + 1, x0:x1 + 1]
	reg = dst[y0:y1 + 1, x0:x1 + 1]
	sa = src[..., 3:4]
	if blend == "additive":
		out_rgb = reg[..., :3] + src[..., :3]
		out_a = reg[..., 3:4]
	else:
		out_rgb = src[..., :3] + reg[..., :3] * (1.0 - sa)
		out_a = sa + reg[..., 3:4] * (1.0 - sa)
	reg[m, :3] = out_rgb[m]
	reg[m, 3:4] = out_a[m]


def _poly_mask(H: int, W: int, poly: np.ndarray) -> np.ndarray:
	"""奇偶规则多边形掩膜(像素中心)。"""
	ys, xs = np.mgrid[0:H, 0:W]
	cx, cy = xs + 0.5, ys + 0.5
	inside = np.zeros((H, W), dtype=bool)
	n = len(poly)
	for i in range(n):
		xa, ya = poly[i]
		xb, yb = poly[(i + 1) % n]
		cond = ((ya > cy) != (yb > cy))
		xint = (xb - xa) * (cy - ya) / ((yb - ya) if yb != ya else 1e-12) + xa
		inside ^= cond & (cx < xint)
	return inside


def render(sk: Skeleton, anim: str, t: float, size: tuple = (256, 256), origin: tuple = None, only_slots=None) -> np.ndarray:
	"""渲一帧 → float32 预乘 RGBA (H, W, 4)。origin = 世界坐标里画布左下角(默认取 skeleton.x / y)。
	only_slots: 插槽名集合 —— 只画这些插槽(裁切照常生效); None = 全画。头像裁切用它求头部范围。"""
	W, H = size
	ox, oy = origin if origin is not None else (float(sk.sk.get("x", 0)), float(sk.sk.get("y", 0)))
	dst = np.zeros((H, W, 4), dtype=np.float32)
	ps = sk.pose(anim, t)
	clip_mask = None
	clip_end = None
	for item in sk.triangles(ps):
		if item["clip"]:
			pv = item["verts"].copy()
			pv[:, 0] -= ox
			pv[:, 1] = H - (pv[:, 1] - oy)
			clip_mask = _poly_mask(H, W, pv)
			clip_end = item["end"]
			continue
		if only_slots is not None and item["slot"] not in only_slots:
			if clip_end is not None and item["slot"] == clip_end:
				clip_mask = None
				clip_end = None
			continue
		tex = sk.atlas["pages"][item["page"]]
		pv = item["verts"].copy()
		pv[:, 0] -= ox
		pv[:, 1] = H - (pv[:, 1] - oy)
		tris = item["tris"].reshape(-1, 3)
		for tri in tris:
			_raster_tri(dst, clip_mask, pv[tri], item["uvs"][tri], tex, item["color"], item["blend"])
		if clip_end is not None and item["slot"] == clip_end:
			clip_mask = None
			clip_end = None
	return dst


def to_rgba8(premul: np.ndarray) -> Image.Image:
	a = np.clip(premul[..., 3:4], 0.0, 1.0)
	rgb = np.where(a > 1e-6, premul[..., :3] / np.maximum(a, 1e-6), 0.0)
	out = np.concatenate([np.clip(rgb, 0, 1), a], axis=-1)
	return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def load(json_path: str) -> Skeleton:
	d = json.load(open(json_path, encoding="utf-8"))
	atlas = load_atlas(os.path.splitext(json_path)[0] + ".atlas")
	return Skeleton(d, atlas)


def anim_length(sk: Skeleton, anim: str) -> float:
	an = sk.data.get("animations", {}).get(anim, {})
	tmax = 0.0
	def walk(o):
		nonlocal tmax
		if isinstance(o, dict):
			if "time" in o:
				tmax = max(tmax, float(o["time"]))
			for v in o.values():
				walk(v)
		elif isinstance(o, list):
			for v in o:
				walk(v)
	walk(an)
	return tmax


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	ap = argparse.ArgumentParser()
	ap.add_argument("json")
	ap.add_argument("--anim", default="animation")
	ap.add_argument("--t", type=float, default=0.0)
	ap.add_argument("--out", default="")
	ap.add_argument("--sheet", default="")
	ap.add_argument("--fps", type=float, default=30.0)
	ap.add_argument("--size", default="256x256")
	a = ap.parse_args()
	sk = load(a.json)
	W, H = [int(x) for x in a.size.split("x")]
	if a.sheet:
		os.makedirs(a.sheet, exist_ok=True)
		L = anim_length(sk, a.anim)
		n = max(1, int(round(L * a.fps)))
		for k in range(n):
			to_rgba8(render(sk, a.anim, k / a.fps, (W, H))).save(os.path.join(a.sheet, "f%03d.png" % k))
		print("写出 %d 帧(%.2f 秒 × %g fps) → %s" % (n, L, a.fps, a.sheet))
	else:
		to_rgba8(render(sk, a.anim, a.t, (W, H))).save(a.out or "spine_frame.png")
		print("写出", a.out or "spine_frame.png")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
