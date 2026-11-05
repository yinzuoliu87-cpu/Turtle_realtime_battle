# -*- coding: utf-8 -*-
"""tools/assetgen/spine_ref_check.py — 自写求值器 spine_eval.py 对 Spine 官方运行库逐帧对账(2026-11-05)。

尺子: tools/assetgen/spine_ref_dump.mjs(官方 spine-core 算的骨骼世界变换 + 插槽世界顶点)。
判据: 每帧每根骨 6 个数、每个插槽每个顶点, 与官方差 ≤ TOL(世界单位 = 原画像素); 可见插槽集合相同;
  每个插槽取的贴图(逐帧序列第几张)相同、颜色(插槽色 × 部件色, 含透明度)差 ≤ CTOL。打印最差的一项。
用法: python tools/assetgen/spine_ref_check.py <spine-core 包目录> [龟目录名 ...]     (不给 = 11 只全对)
  spine-core 装法见 spine_ref_dump.mjs 文件头。需要 node。
"""
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import spine_eval as S  # noqa: E402

SRC = os.path.join(HERE, "spine_src")
OUT = os.path.join(ROOT, ".out", "spineref")
TOL = 0.05     # 世界单位(原画 1 像素 = 1 单位); 浮点累积误差远小于它, 算法错了远大于它
CTOL = 0.002   # 颜色通道(0–1); 官方存 32 位浮点


def py_frame(sk, t: float) -> tuple:
	ps = sk.pose("animation", t)
	bones = {b["name"]: ps["world"][i] for i, b in enumerate(sk.bones)}
	slots = {}
	for it in sk.triangles(ps):
		slots[it["slot"]] = it
	return bones, slots


def check(pkg: str, d: str) -> tuple:
	nn = d.split("_")[0][len("turtle"):]
	jp = os.path.join(SRC, d, "turtle%s.json" % nn)
	os.makedirs(OUT, exist_ok=True)
	ref_p = os.path.join(OUT, "%s.json" % d)
	subprocess.run(["node", os.path.join(HERE, "spine_ref_dump.mjs"), pkg, jp, ref_p], check=True, capture_output=True)
	ref = json.load(open(ref_p, encoding="utf-8"))
	sk = S.load(jp)
	worst_b = (0.0, "")
	worst_v = (0.0, "")
	nb = nv = nc = 0
	for fr in ref["frames"]:
		t = fr["t"]
		pb, pv = py_frame(sk, t)
		for name, rb in fr["bones"].items():
			e = float(np.max(np.abs(np.array(pb[name]) - np.array(rb))))
			nb += 1
			if e > worst_b[0]:
				worst_b = (e, "t=%.3f 骨 %s" % (t, name))
		## 可见插槽集合要一样(只比有顶点的: 区域 / 网格 / 裁切)
		ref_vis = {n for n, rs in fr["slots"].items() if rs["verts"] is not None}
		if ref_vis != set(pv):
			worst_v = (1e9, "t=%.3f 可见插槽不同: 只官方有 %s · 只我们有 %s" % (t, sorted(ref_vis - set(pv)), sorted(set(pv) - ref_vis)))
		for name, rs in fr["slots"].items():
			if rs["verts"] is None or name not in pv:
				continue
			it = pv[name]
			r = np.array(rs["verts"], dtype=np.float64).reshape(-1, 2)
			p = np.asarray(it["verts"], dtype=np.float64)
			if r.shape != p.shape:
				worst_v = (1e9, "t=%.3f 插槽 %s 顶点数不同 %s vs %s" % (t, name, p.shape, r.shape))
				continue
			e = float(np.max(np.abs(p - r)))
			if not it["clip"]:
				## 取的是哪张图(逐帧序列选第几张)、颜色(插槽色 × 部件色, 含透明度时间轴)
				if it["region"] != rs["region"]:
					worst_v = (1e9, "t=%.3f 插槽 %s 贴图 %s vs 官方 %s" % (t, name, it["region"], rs["region"]))
				ce = float(np.max(np.abs(np.asarray(it["color"], dtype=np.float64) - np.array(rs["color"]))))
				if ce > CTOL:
					worst_v = (1e9, "t=%.3f 插槽 %s 颜色差 %.4f" % (t, name, ce))
				nc += 1
			nv += 1
			if e > worst_v[0]:
				worst_v = (e, "t=%.3f 插槽 %s" % (t, name))
	return worst_b, worst_v, nb, nv, nc, len(ref["frames"])


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	if len(sys.argv) < 2:
		print(__doc__)
		return 2
	pkg = sys.argv[1]
	ds = sys.argv[2:] or sorted(x for x in os.listdir(SRC) if x.startswith("turtle") and os.path.isdir(os.path.join(SRC, x)))
	bad = 0
	for d in ds:
		wb, wv, nb, nv, nc, nf = check(pkg, d)
		ok = wb[0] <= TOL and wv[0] <= TOL
		bad += 0 if ok else 1
		print("%s %-20s 帧 %d · 骨 %d 项 最差 %.4f (%s) · 插槽 %d 项(其中贴图+颜色 %d) 最差 %.4f (%s)" % ("✓" if ok else "✗", d, nf, nb, wb[0], wb[1], nv, nc, wv[0], wv[1]))
	print("ALL OK — 求值器与官方运行库逐帧一致" if bad == 0 else "FAIL — %d 只对不上" % bad)
	return 0 if bad == 0 else 1


if __name__ == "__main__":
	raise SystemExit(main())
