# -*- coding: utf-8 -*-
"""tools/assetgen/build_spine_idle.py — 外包 11 只龟的 Spine 待机 → 游戏用的像素序列帧(2026-11-05)。

方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.2(用户 11-05「待机的时候只能用这一十一只这个原画」「把它转变为这个像素序列帧」)。
输入: tools/assetgen/spine_src/turtleNN_<龟id>/turtleNN.{json,atlas,png}(画师交付的 Spine 4.3 导出, 原样)
渲染: tools/assetgen/spine_eval.py(1:1、最近邻)。每只按 FPS 抽 N 帧(3.33 秒待机 → 15 帧/秒 = 50 帧)。
后处理: 透明度二值(≥ 0.5 不透明, 否则全透明)—— 像素画硬边; 加色光效叠在龟身外的那一圈本来就不改透明度, 自然消失。
排版: 11 只共用同一个格子(宽 / 高取 11 只所有帧内容框的最大值), 脚底贴格子底边、水平居中 ⇒ 11 只之间保持画师设定的相对大小;
  横排 COLS 列, 多留 1 格空位(游戏 `_sprite_dict_from` 的 drop_last 会丢掉最后一格 ⇒ 声明帧数 = N、格子数 ≥ N + 1)。
输出: assets/sprites/pets/spine/<龟id>_idle.png + tools/assetgen/spine_src/idle_manifest.json({龟id: {frameW, frameH, frames, duration}})。
确定性: 渲染与排版都是纯数值, 重跑逐字节相同。仓库根目录 = 本文件往上三层。
用法: python tools/assetgen/build_spine_idle.py   (每次 11 只全渲: 共用格子由 11 只一起定, 单渲一只格子会变)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import spine_eval as S  # noqa: E402

SRC = os.path.join(HERE, "spine_src")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "pets", "spine")
MANIFEST = os.path.join(SRC, "idle_manifest.json")
FPS = 15
CANVAS = 400          # 渲染画布(足够大, 任何一帧都不被裁)
COLS = 10
ANIM = "animation"


def _dirs() -> list:
	return sorted(d for d in os.listdir(SRC) if os.path.isdir(os.path.join(SRC, d)) and d.startswith("turtle"))


def render_frames(d: str) -> tuple:
	nn = d.split("_")[0][len("turtle"):]
	sk = S.load(os.path.join(SRC, d, "turtle%s.json" % nn))
	sx, sy, sw, sh = [float(sk.sk.get(k, 0)) for k in ("x", "y", "width", "height")]
	origin = (sx + sw / 2 - CANVAS / 2, sy + sh / 2 - CANVAS / 2)
	L = S.anim_length(sk, ANIM)
	n = max(1, int(round(L * FPS)))
	frames = []
	for k in range(n):
		pm = S.render(sk, ANIM, k / float(FPS), (CANVAS, CANVAS), origin)
		a = pm[..., 3:4]
		rgb = np.where(a > 1e-6, pm[..., :3] / np.maximum(a, 1e-6), 0.0)
		opaque = (a[..., 0] >= 0.5)
		img = np.zeros((CANVAS, CANVAS, 4), dtype=np.uint8)
		img[..., :3] = (np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8)
		img[..., 3] = np.where(opaque, 255, 0).astype(np.uint8)
		img[~opaque, :3] = 0
		frames.append(img)
	return frames, L


def bbox_union(frames: list) -> tuple:
	ys = []
	xs = []
	for f in frames:
		m = f[..., 3] > 0
		if not m.any():
			continue
		yy = np.where(m.any(axis=1))[0]
		xx = np.where(m.any(axis=0))[0]
		ys += [yy[0], yy[-1]]
		xs += [xx[0], xx[-1]]
	return int(min(xs)), int(min(ys)), int(max(xs)) + 1, int(max(ys)) + 1


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	ds = _dirs()
	rendered = {}
	for d in ds:
		tid = d.split("_", 1)[1]
		frames, L = render_frames(d)
		rendered[tid] = (frames, L, bbox_union(frames))
		print("渲完 %-10s %d 帧 · 内容框 %s" % (tid, len(frames), rendered[tid][2]))
	## 共用格子: 宽 / 高 = 所有龟内容框的最大值(偶数, 方便居中)
	cw = int(max(b[2] - b[0] for _, _, b in rendered.values()))
	ch = int(max(b[3] - b[1] for _, _, b in rendered.values()))
	cw += cw % 2
	ch += ch % 2
	os.makedirs(OUT_DIR, exist_ok=True)
	man = {}
	for tid, (frames, L, (x0, y0, x1, y1)) in rendered.items():
		n = len(frames)
		cells = n + 1
		rows = int(math.ceil(cells / float(COLS)))
		sheet = np.zeros((rows * ch, COLS * cw, 4), dtype=np.uint8)
		bw = x1 - x0
		dx = (cw - bw) // 2
		dy = ch - (y1 - y0)          # 脚底贴格子底边
		for k, f in enumerate(frames):
			r, c = divmod(k, COLS)
			crop = f[y0:y1, x0:x1]
			sheet[r * ch + dy: r * ch + dy + crop.shape[0], c * cw + dx: c * cw + dx + crop.shape[1]] = crop
		Image.fromarray(sheet, "RGBA").save(os.path.join(OUT_DIR, "%s_idle.png" % tid), optimize=False)
		man[tid] = {"frameW": cw, "frameH": ch, "frames": n, "duration": int(round(L * 1000)), "fps": FPS,
			"content": [int(bw), int(y1 - y0)]}
		print("写出 %-10s %d×%d 格 × %d 帧(%d 行)" % (tid, cw, ch, n, rows))
	json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
	print("共用格子 %d×%d → %s" % (cw, ch, os.path.relpath(OUT_DIR, ROOT)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
