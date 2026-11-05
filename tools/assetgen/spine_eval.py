# -*- coding: utf-8 -*-
"""tools/assetgen/spine_eval.py — Spine 4.3 JSON 求值 + 1:1 像素渲染(离线, 确定性)。2026-11-05。

由来: 方案书 docs/plans/20261105b-龟美术统一与动作补全.md(用户 11-05「我们可以想办法把它转变为这个像素序列帧嘛…待机的时候只能用这一十一只这个原画」)。
  主站时期外包的 11 只龟是 Spine 4.3 导出(json + atlas + png), 只有一个 3.33 秒待机; 游戏里不装 Spine 运行库(直播录流只认序列帧),
  ⇒ 离线把它渲成像素序列帧。只实现这 11 只真用到的那一套(11-05 逐只统计, 方案书 §2.1):
  骨骼(平移 / 旋转 / 缩放 / 错切, 继承 normal)· 贝塞尔 / 阶梯 / 线性曲线 · 区域 / 带权网格 / 网格变形 · 插槽颜色 / 换图 ·
  逐帧序列(sequence)· 混合 normal / additive(贴图透明度预乘)· 裁切蒙版(clipping)。没有 IK / transform / path / physics 约束。
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
	"""控制点是绝对的(时间, 值)。先二分求参数 s 使 x(s)=t, 再算 y(s)。"""
	lo, hi = 0.0, 1.0
	for _ in range(40):
		s = (lo + hi) * 0.5
		x = (1 - s) ** 3 * t0 + 3 * (1 - s) ** 2 * s * cx1 + 3 * (1 - s) * s * s * cx2 + s ** 3 * t1
		if x < t:
			lo = s
		else:
			hi = s
	s = (lo + hi) * 0.5
	return (1 - s) ** 3 * v0 + 3 * (1 - s) ** 2 * s * cy1 + 3 * (1 - s) * s * s * cy2 + s ** 3 * v1


def sample(keys: list, t: float, fields: list, defaults: list) -> list:
	"""关键帧列表在时刻 t 的值。fields = 这条时间轴的通道名(rotate: ["value"], translate: ["x","y"] …)。"""
	if not keys:
		return list(defaults)
	vals = lambda k: [float(k.get(f, d)) for f, d in zip(fields, defaults)]
	times = [float(k.get("time", 0.0)) for k in keys]
	if t <= times[0]:
		return vals(keys[0])
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
	if not keys:
		return None
	conv = [dict(k, r=_hex_rgba(k.get("color"))[0], g=_hex_rgba(k.get("color"))[1], b=_hex_rgba(k.get("color"))[2], a=_hex_rgba(k.get("color"))[3]) for k in keys]
	return np.array(sample(conv, t, ["r", "g", "b", "a"], [1, 1, 1, 1]), dtype=np.float32)


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
		for i, b in enumerate(self.bones):
			L = local[i]
			rx = math.radians(L["rotation"] + L["shearX"])
			ry = math.radians(L["rotation"] + 90 + L["shearY"])
			la, lb = math.cos(rx) * L["scaleX"], math.cos(ry) * L["scaleY"]
			lc, ld = math.sin(rx) * L["scaleX"], math.sin(ry) * L["scaleY"]
			p = b.get("parent")
			if p is None:
				world.append((la, lb, lc, ld, L["x"], L["y"]))
			else:
				pa, pb, pc, pd, px, py = world[self.bone_index[p]]
				world.append((pa * la + pb * lc, pa * lb + pb * ld, pc * la + pd * lc, pc * lb + pd * ld,
					pa * L["x"] + pb * L["y"] + px, pc * L["x"] + pd * L["y"] + py))
		# 插槽: 颜色 / 当前部件 / 部件时间轴(变形、序列)
		slots = []
		for s in self.slots:
			color = _hex_rgba(s.get("color"))
			att = s.get("attachment")
			stl = an.get("slots", {}).get(s["name"], {})
			if "rgba" in stl:
				color = sample_color(stl["rgba"], t)
			if "alpha" in stl:
				color = color.copy()
				color[3] = sample(stl["alpha"], t, ["value"], [1])[0]
			if "attachment" in stl:
				ks = stl["attachment"]
				cur = None
				for k in ks:
					if float(k.get("time", 0.0)) <= t + 1e-9:
						cur = k
				if cur is not None:
					att = cur.get("name")
			slots.append({"slot": s, "color": color, "att": att})
		return {"world": world, "slots": slots, "anim": an, "t": t}

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
		times = [float(k.get("time", 0.0)) for k in keys]
		if t <= times[0]:
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
		count = int(seqdef.get("count", 1))
		keys = an.get("attachments", {}).get("default", {}).get(slot, {}).get(att, {}).get("sequence")
		if not keys:
			return int(seqdef.get("setup", 0))
		cur = None
		for k in keys:
			if float(k.get("time", 0.0)) <= t + 1e-9:
				cur = k
		if cur is None:
			return int(seqdef.get("setup", 0))
		mode = cur.get("mode", "hold")
		idx = int(cur.get("index", 0))
		delay = float(cur.get("delay", 0.0))
		if mode == "hold" or delay <= 0:
			return min(idx, count - 1)
		idx += int((t - float(cur.get("time", 0.0))) / delay + 0.0001)
		if mode == "once":
			return min(count - 1, idx)
		if mode == "loop":
			return idx % count
		if mode == "pingpong":
			n = (count << 1) - 2
			idx = 0 if n == 0 else idx % n
			return n - idx if idx >= count else idx
		if mode == "onceReverse":
			return max(count - 1 - idx, 0)
		if mode == "loopReverse":
			return count - 1 - (idx % count)
		return idx % count

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
				wv = self._mesh_world(a, bone, world, None, int(a.get("vertexCount", 0)))
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
				"blend": s.get("blend", "normal"), "slot": s["name"]}

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
