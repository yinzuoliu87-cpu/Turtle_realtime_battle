# -*- coding: utf-8 -*-
"""tools/sfx_r5_describe.py — 第五轮: 技能放出 / 命中里与「参考的那个英雄技能原声」最不像的那批, 反听原声定描述(2026-11-05)。
由来: 用户认可音效 v2 出版合格后的优化第 1 项。挑选尺子对准具体技能(tools/sfx_skill_refs.py)后, 只重挑已有候选几乎不涨
  (放出声对参考技能 0.428 → 0.430), 说明候选本身不像 ⇒ 照第四轮全局声的做法(复活 0.24 → 0.68): 先用 CLAP 反听那条原声,
  按「听起来像什么」的词与原声时长重写描述再生成。
产物: tools/assetgen/sfx_r5_texts.json(进仓库; sfx_v2_table.round5 读它, 表本身不依赖仓库外的原声)。
用法: D:/turtle_audio_src/clapenv/Scripts/python.exe tools/sfx_r5_describe.py [阈值 0.45]
"""
import glob
import json
import os
import re
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import sfx_clap  # noqa: E402
import sfx_skill_refs  # noqa: E402
from sfx_measure import measure  # noqa: E402

PICKS = os.path.join(ROOT, ".out", "sfx_v2", "picks.json")
TAB = os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json")
OUT = os.path.join(ROOT, "tools", "assetgen", "sfx_r5_texts.json")
## 反听用的词表: 技能声会出现的质感(去掉界面 / 金币 / 升级 / 胜负这些不属于技能的)
VOCAB = [
	"a deep boom", "a heavy thud", "a punchy impact", "a crunchy hit", "a metal clang", "a glass shatter", "a bell chime",
	"a bright sparkle", "a magical shimmer", "a rising magical swell", "a descending magical tone", "a whoosh", "a reverse whoosh",
	"a wind gust", "an electric zap", "a fire burst", "a water splash", "a choir pad", "an orchestral hit", "a harp gliss",
	"a heartbeat pulse", "a low drone", "a dark rumble", "a ghostly wail", "a monster growl", "a pop", "a crystal ring",
	"a wooden knock", "a stone crack", "a shield block", "a healing spell", "a power up sound", "a power down sound",
	"a synth pluck", "a gong", "a drum hit", "a cymbal crash", "a magical dust sprinkle", "a dark magic pulse",
	"an explosion", "a gunshot", "a laser blast", "a sword slash", "an arrow release", "a card shuffle", "a bubbling liquid",
	"a sizzling hiss", "a crackling fire", "a cloth flap", "a chain rattle", "a mechanical whir", "a spring boing",
]


def main() -> int:
	thr = float(sys.argv[1]) if len(sys.argv) > 1 else 0.45
	picks = json.load(open(PICKS, encoding="utf-8"))
	tab = json.load(open(TAB, encoding="utf-8"))
	items = {it["key"]: it for it in tab["batches"]["v2"]}
	allf = sorted(glob.glob(os.path.join(ROOT, ".out", "riot_audio", "champ", "*", "*.wav")) + glob.glob(os.path.join(ROOT, ".out", "riot_audio", "chogath", "*.wav")))
	T = sfx_clap.embed_text(VOCAB)
	## 相对基线: 直接取最高的词几乎条条都是「挥砍 / 射箭 / 治疗法术 / 电击」(CLAP 对 Riot 技能声的偏好, 不是这条的特点)。
	##   ⇒ 先算全部对上具体技能的原声中心, 每个词按「这条比全体平均高几个标准差」排, 取最突出的 3 个
	cents = {}
	for key in sorted(picks):
		if not key.startswith(("sk_", "skh_")) or key not in items:
			continue
		rx = sfx_skill_refs.ref_rx_for(re.sub(r" (OnCast|hit)$", "", items[key]["ref"]), "cast" if key.startswith("sk_") else "hit")
		fs = [f for f in allf if rx and re.search(rx, os.path.basename(f).lower())][:20]
		if fs:
			c = sfx_clap.embed_audio(fs).mean(axis=0)
			cents[key] = (c / np.linalg.norm(c), fs)
	S_all = np.array([T @ c for c, _ in cents.values()])
	mu, sd = S_all.mean(axis=0), S_all.std(axis=0) + 1e-6
	print("基线: %d 条参考技能原声" % len(cents))
	out = {}
	rows = []
	for key in sorted(picks):
		if not key.startswith(("sk_", "skh_")) or key not in items:
			continue
		it = items[key]
		kind = "cast" if key.startswith("sk_") else "hit"
		rx = sfx_skill_refs.ref_rx_for(re.sub(r" (OnCast|hit)$", "", it["ref"]), kind)
		if not rx:
			continue
		fs = [f for f in allf if re.search(rx, os.path.basename(f).lower())][:20]
		if not fs:
			continue
		p = picks[key]
		sim = {os.path.basename(s["file"]): s["riot"] for s in p["all"]}
		now = float(np.mean([sim[x] for x in p["sel"]])) if p["sel"] else 0.0
		if now >= thr:
			continue
		c = cents[key][0]
		z = (T @ c - mu) / sd
		top = [VOCAB[i] for i in np.argsort(-z)[:3]]
		durs = [m["dur"] for m in (measure(f) for f in fs) if m]
		d = float(np.clip(np.median(durs) if durs else 1.5, 0.8, 3.0))
		out[key] = {"words": top, "dur": round(d, 2), "sim_before": round(now, 3), "ref_files": [os.path.basename(f) for f in fs[:6]], "ref_n": len(fs)}
		rows.append("%-26s %.2f  %4.1f 秒  %s" % (key, now, d, " · ".join(top)))
	json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
	print("\n".join(rows))
	print("分母: 对上具体技能且 < %.2f 的 %d 条 → %s" % (thr, len(out), OUT))
	return 0


if __name__ == "__main__":
	sys.exit(main())
