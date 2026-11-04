# -*- coding: utf-8 -*-
"""sfx_pick.py — 音效候选自动定选（2026-11-04 · A5; 用户「中间过程都不需要我来…你自己看看有没有达到黑箱的标准」）。

我听不见, 定选全靠三样量出来的东西(各管一块, 标定见各自脚本头注):
  ① 坏样本淘汰(可靠): 能量太低 / CLAP 判成人声·静音·底噪(> 0.10; 黑箱 20 条原声最高 −0.04 / 0.001)/
     不该有旋律的(普攻 / 按钮)判成音乐(> 0.15; 黑箱只有胜利小曲到 0.159)。
  ② 形状对标黑箱【同一类整组】的中位数(时长 / 起音 / 衰减 / 亮度, sfx_rank.dist; 黑箱同类互比 0.9、跨类 2.4~5)。
  ③ CLAP 与自己那句描述的相似度, 只在同一条的候选之间比(在 38 条描述里认出自己那条的中位排名 9/38, 信号弱 ⇒ 权重低)。
  另查「不同来源选中的声音互相太像」(CLAP 声音向量余弦 > 0.93 ⇒ 换次优), 保证每只龟听得出区别(用户要的就是这个)。
输入: <SFX_SRC>/eleven/<批次>/ + .out/sfx_rank/<批次>/clap.tsv · clap_emb.npy(先跑 tools/sfx_clap.py)
输出: tools/assetgen/sfx_picks.json(定选结果, 进仓库, build_sfx 读它) + .out/sfx_rank/<批次>/pick_report.tsv
用法: python tools/sfx_pick.py b1
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_rank as R  # noqa: E402
import sfx_bar as BAR  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "assetgen"))
import build_sfx as BUILD  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
ROOT = R.ROOT
PICKS = os.path.join(ROOT, "tools", "assetgen", "sfx_picks.json")
## 黑箱同类整组(.out/blackbox/sfx/ 里的原声名; 归类依据 = 拆包名 + 方案书 20261102b §8.3 ①)
CAT_REFS = {
	"atk": ["hit8", "sfx_boss_skill_orb_hit_1", "sfx_boss_skill_orb_hit_2", "sfx_boss_skill_orb_hit_3",
		"sfx_boss_skill_laser_hit_1", "sfx_boss_skill_laser_hit_2", "player_shoot", "sfx_shoot",
		"magnetcrossbow_single_004", "hammer_c", "etfx_explosion_gas", "etfx_explosion_sparkle2", "etfx_explosion_sparkle3"],
	"click": ["sfx_ui_click", "sfx_ui_click_2", "pickclick"],
	"confirm": ["sfx_pick_reward", "sfx_build_done"],
	"win": ["sfx_level_clear"],
	"lose": ["sfx_game_over"],
	"reward_normal": ["sfx_canteen_reward_normal"],
	"reward_rare": ["sfx_canteen_reward_rare"],
	"levelup": ["player_levelup", "sfx_ui_levelup"],
	"coin": ["coin_bag_reward", "pick_up_jewlery_d"],
	"popup": ["sfx_ui_popup"],
}
KEY_CAT = {"ui_click": "click", "ui_back": "click", "ui_confirm": "confirm", "victory": "win", "defeat": "lose",
	"reward_normal": "reward_normal", "reward_rare": "reward_rare", "level_up": "levelup", "coin_buy": "coin",
	"match_found": "popup"}
NO_MELODY = {"atk", "click"}
SIM_MAX = 0.93


def cat_of(key: str) -> str:
	return "atk" if key.startswith("atk_") else KEY_CAT[key]


def median_feats(names: list) -> dict:
	fs = [R.feats(R.decode(os.path.join(R.REF_DIR, n + ".wav"))) for n in names]
	return {k: float(np.median([f[k] for f in fs])) for k in ("dur", "attack", "decay", "cent")}


def main() -> int:
	batch = sys.argv[1] if len(sys.argv) > 1 else "b1"
	cdir = os.path.join(R.SRC, "eleven", batch)
	odir = os.path.join(ROOT, ".out", "sfx_rank", batch)
	man = json.load(open(os.path.join(cdir, "manifest.json"), encoding="utf-8"))
	clap = {}
	for ln in open(os.path.join(odir, "clap.tsv"), encoding="utf-8").read().splitlines()[1:]:
		c = ln.split("\t")
		clap[c[0]] = {"match": float(c[2]), "bad_kind": c[5], "bad": float(c[6])}
	emb_names = open(os.path.join(odir, "clap_emb.txt"), encoding="utf-8").read().split()
	emb = dict(zip(emb_names, np.load(os.path.join(odir, "clap_emb.npy"))))
	prof = {c: median_feats(v) for c, v in CAT_REFS.items()}
	by_key = {}
	for fn, rec in man.items():
		if os.path.exists(os.path.join(cdir, fn)) and fn in clap:
			by_key.setdefault(rec["key"], []).append(fn)
	report = ["key\tcand\tverdict\tscore\tdist\tclap\tclap_z\tbad\twhy"]
	ranked = {}
	for k, fns in sorted(by_key.items()):
		cat = cat_of(k)
		ms = np.array([clap[f]["match"] for f in fns])
		mu, sd = float(ms.mean()), float(ms.std() + 1e-6)
		ok = []
		for f in fns:
			x = R.decode(os.path.join(cdir, f))
			ft = R.feats(x)
			cl = clap[f]
			why = []
			if ft["rms"] < -38 or ft["peak"] < -14:
				why.append("能量太低(RMS %.0f dB)" % ft["rms"])
			if cl["bad_kind"] in ("speech", "silence", "hiss") and cl["bad"] > 0.10:
				why.append("像%s %.2f" % (cl["bad_kind"], cl["bad"]))
			if cat in NO_MELODY and cl["bad_kind"] == "music" and cl["bad"] > 0.15:
				why.append("像音乐 %.2f" % cl["bad"])
			## ★量的是【做成成品之后】的样子(build_sfx 同一套裁剪 / 淡出 / 响度 / 限幅), 对黑箱标准(sfx_bar)逐项判;
			##   哪项不达标罚 10 分 ⇒ 达标的候选一定排在前面, 都不达标时才在不达标里挑最近的。
			xp = BUILD.process(x.copy(), cat)
			fp = R.feats(xp)
			fp["l100"] = BUILD.l100(xp)
			fp["gr"] = BUILD.LAST_GR
			miss = BAR.check(fp, cat)
			d = R.dist(fp, prof[cat])
			z = (cl["match"] - mu) / sd
			score = 10 * len(miss) + d - 0.3 * z
			if miss:
				why_soft = "成品不达标: " + "; ".join(miss)
			else:
				why_soft = ""
			report.append("%s\t%s\t%s\t%.3f\t%.3f\t%.4f\t%.2f\t%s %.3f\t%s" % (k, f, "淘汰" if why else "可用", score, d, cl["match"], z,
				cl["bad_kind"], cl["bad"], "; ".join(why + ([why_soft] if why_soft else []))))
			if not why:
				ok.append((score, f, d, cl["match"], len(miss)))
		ranked[k] = sorted(ok)
	## 定选 + 区分度: 普攻之间 CLAP 声音向量太像 ⇒ 分数差得少的那条换次优
	pick = {k: 0 for k in ranked if ranked[k]}
	atk = [k for k in pick if k.startswith("atk_")]
	for _ in range(20):
		worst = None
		for i, a in enumerate(atk):
			for b in atk[i + 1:]:
				s = float(emb[ranked[a][pick[a]][1]] @ emb[ranked[b][pick[b]][1]])
				if s > SIM_MAX and (worst is None or s > worst[0]):
					worst = (s, a, b)
		if worst is None:
			break
		_, a, b = worst
		cand = [x for x in (a, b) if pick[x] + 1 < len(ranked[x])]
		if not cand:
			break
		x = min(cand, key=lambda q: ranked[q][pick[q] + 1][0] - ranked[q][pick[q]][0])
		pick[x] += 1
	maxsim = {}
	for a in atk:
		maxsim[a] = max([float(emb[ranked[a][pick[a]][1]] @ emb[ranked[b][pick[b]][1]]) for b in atk if b != a] or [0.0])
	out = {"_doc": "sfx_pick.py 自动定选(批次 %s)。每条: 选中的候选文件(相对 <SFX_SRC>/eleven/<批次>/) + 量化依据。build_sfx.py 读这份。" % batch,
		"batch": batch, "picks": {}}
	missing = [k for k in by_key if k not in pick]
	for k in sorted(pick):
		s, f, d, m, nm = ranked[k][pick[k]]
		out["picks"][k] = {"file": f, "cat": cat_of(k), "score": round(s, 3), "dist_to_blackbox": round(d, 3), "clap": round(m, 4),
			"rank_used": pick[k] + 1, "bar_misses": nm, "usable": len(ranked[k]), "of": len(by_key[k]),
			"max_sim_other_atk": round(maxsim.get(k, 0.0), 3)}
	json.dump(out, open(PICKS, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
	open(os.path.join(odir, "pick_report.tsv"), "w", encoding="utf-8").write("\n".join(report) + "\n")
	n_rej = sum(1 for r in report[1:] if "\t淘汰\t" in r)
	short = sorted(k for k in pick if ranked[k][pick[k]][4] > 0)
	print("分母: %d 条 · 候选 %d · 淘汰 %d · 定选 %d · 一个能用的都没有: %s" % (len(by_key), len(report) - 1, n_rej, len(pick), missing or "无"))
	print("定选里成品仍不达标(要重新出): %s" % (short or "无"))
	print("普攻之间最像的一对: %.3f(线 %.2f)" % (max(maxsim.values()) if maxsim else 0, SIM_MAX))
	return 1 if missing else 0


if __name__ == "__main__":
	sys.exit(main())
