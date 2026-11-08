# -*- coding: utf-8 -*-
"""tools/assetgen/build_melee_attack.py — 近战小将普攻重做成三段(2026-11-05)。

用户 11-05:「近战小将…站位待机动画，然后突然戳一下…又回到待机动画」—— 原帧条只有 4 帧, 前摇 1 帧, 再怎么对齐时机也是「举一下就戳」。
做法: 第 0 帧保留原帧(中性站姿, ANIM_NORM / verify_elite_anim 按它对账) + PixelLab animate_image 8 帧
  (「往后拉三叉戟蓄力 → 朝左刺到底 → 定住 → 收回」, 原始帧在 tools/assetgen/ai_src/melee_attack/), 锁回小将原调色板。
命中帧 = 伸出量第一次达到最大值 85% 的那一帧(刚刺到), 打印出来抄进 scripts/gamedata/attack_hits.gd。
输出: tools/assetgen/ai_src/attack_rhythm/melee/orig.png(9 帧 × 88)—— 11-08 起是中间产物, 再由 build_attack_rhythm.py 重排成
  「蓄力 → 挥动 → 命中 → 停 2 → 收回 4」写进游戏帧条(命中帧以那边为准)。确定性: 重跑逐字节相同。
用法: python tools/assetgen/build_melee_attack.py
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_spine_actions as A  # noqa: E402

SHEET = os.path.join(HERE, "ai_src", "attack_rhythm", "melee", "orig.png")   # 11-08 起: 中间产物, 游戏帧条由 build_attack_rhythm.py 写
SRC = os.path.join(HERE, "ai_src", "melee_attack")
PAL_FROM = [os.path.join(ROOT, "assets", "sprites", "pets", "animations", "melee", p) for p in ("idle.png", "run.png", "leap.png")]
ORIG_F0 = os.path.join(SRC, "orig_f0.png")   # 原帧条第 0 帧(第一次运行时从旧帧条存下; 之后帧条已被覆盖, 以它为准)


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	if not os.path.exists(ORIG_F0):
		old = np.asarray(Image.open(SHEET).convert("RGBA"))
		h = old.shape[0]
		Image.fromarray(old[:, :h]).save(ORIG_F0, optimize=False)
	f0 = np.asarray(Image.open(ORIG_F0).convert("RGBA"))
	h = f0.shape[0]
	cols = [f0[f0[..., 3] > 0][:, :3]]
	for p in PAL_FROM:
		if os.path.exists(p):
			a = np.asarray(Image.open(p).convert("RGBA"))
			cols.append(a[a[..., 3] > 0][:, :3])
	pal = np.unique(np.concatenate(cols), axis=0)
	frames = [f0]
	n = len([f for f in os.listdir(SRC) if f.startswith("ai_") and f.endswith(".png")])
	for k in range(1, n + 1):
		ai = np.asarray(Image.open(os.path.join(SRC, "ai_%d.png" % k)).convert("RGBA"))
		if ai.shape[:2] != (h, h):
			raise SystemExit("AI 第 %d 帧尺寸 %s ≠ %d" % (k, ai.shape[:2], h))
		frames.append(A._palette_lock(ai, pal))
	lefts = []
	for fr in frames:
		xs = np.where((fr[..., 3] > 16).any(axis=0))[0]
		lefts.append(int(xs.min()) if len(xs) else 999)
	## 命中帧 = 伸出量第一次达到最大伸出量 85% 的那一帧(刚刺到; 不取伸得最远那帧 —— AI 出的刺击会定住 3 帧, 取最远会让结算落在定住的末尾)
	ext = [lefts[0] - x for x in lefts]
	hit = next(i for i, e in enumerate(ext) if e >= 0.85 * max(ext))
	Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(SHEET, optimize=False)
	print("近战小将普攻 %d 帧 · 各帧左缘 %s · 命中帧 %d(抄进 attack_hits.gd)" % (len(frames), lefts, hit))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
