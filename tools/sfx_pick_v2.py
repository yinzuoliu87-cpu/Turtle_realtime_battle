# -*- coding: utf-8 -*-
"""tools/sfx_pick_v2.py — 音效 v2 定选: 拿云顶 / LoL 原声当尺子给候选打分, 每条事件挑出要进游戏的那几个变体(2026-11-05)。
由来: 用户 11-05「你自己想办法去认可，然后我只看结果」+「全部都要达到云顶的标准」。我听不见 ⇒ 判据全是量出来的:
  ① 像不像云顶: CLAP 声音嵌入与 Riot 同类原声(普攻出手 / 普攻命中 / 暴击 / 技能放出 / 技能命中 / 装备 / 公共)的中心的余弦;
     另加与该龟参考英雄全部原声中心的余弦(材质像不像那个英雄)。
  ② 是不是那个东西: CLAP 声音与它自己的描述(去掉统一风格前缀)的余弦。
  ③ 形状: sfx_measure 量的 时长 / 尾音 / 低频 / 高频 / 质心 / 平坦度 落在 Riot 同类 P10~P90 里, 出界按 IQR 计罚。
  ④ 一票否决: 质心 < 180 Hz(只剩一团低频轰鸣, 手机喇叭放不出) / 有声段 RMS < −40 dB(近乎无声) / 像素感(CLAP: 更像
     「8-bit chiptune」而不是「realistic cinematic」)。
  ⑤ 标定(先证明尺子会分): 同一把尺子量 Riot 留出样本、旧音效(assets/audio/sfx/ev)、新候选, 报三组均值 ——
     Riot 留出 > 新 > 旧 才算尺子有分辨力。
★依赖: D:/turtle_audio_src/clapenv(torch + transformers); 读 SFX_SRC/eleven/v2 候选与 .out/riot_audio 参考。
产物: .out/sfx_v2/picks.json(每条事件选中的候选与各项分) + .out/sfx_v2/pick_report.md(分母 / 标定 / 各类对 Riot)。
用法: D:/turtle_audio_src/clapenv/Scripts/python.exe tools/sfx_pick_v2.py
"""
import glob
import json
import os
import random
import re
import subprocess
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import sfx_clap  # noqa: E402
from sfx_measure import measure  # noqa: E402

SRC = os.environ.get("SFX_SRC", r"D:/turtle_audio_src")
FF = os.environ.get("FFMPEG", r"D:/oopz/ffmpeg.exe")
CAND = os.path.join(SRC, "eleven", "v2")
CAND_R2 = os.path.join(SRC, "eleven", "v2r2")   # 第二轮(去掉低频字眼, 见 sfx_v2_table.round2); 候选 wav 名前缀 r2__
CAND_R3 = os.path.join(SRC, "eleven", "v2r3")   # 第三轮(两轮全否决的 7 条, 见 sfx_v2_table.round3); 前缀 r3__
OUT = os.path.join(ROOT, ".out", "sfx_v2")
RIOT = os.path.join(ROOT, ".out", "riot_audio")
TAB = os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json")
CACHE = os.path.join(OUT, "emb_cache.npz")
## 每类留几个变体(云顶: 普攻出手 / 命中 3~4 个随机轮换, 技能命中 2~3, 放出 1)
KEEP = {"ba_cast": 3, "ba_hit": 3, "crit": 2, "sk_cast": 1, "sk_hit": 2, "equip": 1, "global": 1}
KEEP_KEY = {"g_hit": 3, "g_crit": 2, "g_skill_hit": 2, "g_shield_gain": 2, "g_shield_break": 2, "g_heal": 2, "g_death": 2, "g_dodge": 2, "ui_click": 2}
RIOT_RX = {
	"ba_cast": r"basicattack[0-9]?_(oncast|onmissilelaunch|cast)__",
	"ba_hit": r"basicattack[0-9]?_(onhit|hit)__",
	"crit": r"critattack[0-9]?_(onhit|hit)__",
	"sk_cast": r"_[a-z]+[qwer]_(oncast|cast|cast1|cast2|onbuffactivate|buffactivate)__",
	"sk_hit": r"_[a-z]+[qwer]_(onhit|hit|onhitlocation|hit_location|explode|oncollision)__",
}
FEATS = ["dur", "tail", "low", "high", "lcent", "flat"]
PIX_T = ["8-bit chiptune retro video game sound effect, square wave bleeps", "realistic high quality cinematic game sound effect, rich layered foley"]


def riot_sets() -> dict:
	allf = sorted(glob.glob(os.path.join(RIOT, "champ", "*", "*.wav")))
	sets = {k: [f for f in allf if re.search(rx, os.path.basename(f).lower())] for k, rx in RIOT_RX.items()}
	m22 = sorted(glob.glob(os.path.join(RIOT, "map22", "*.wav")))
	items = [f for f in m22 if re.search(r"item", os.path.basename(f).lower())]
	sets["equip"] = items if len(items) >= 20 else sets["sk_hit"] + sets["sk_cast"]
	sets["global"] = m22 if len(m22) >= 20 else sets["sk_hit"]
	rnd = random.Random(1105)
	out = {}
	for k, v in sets.items():
		v = list(v)
		rnd.shuffle(v)
		out[k] = v[:300]
	return out


def champ_of(f: str) -> str:
	"""分组键: 英雄目录; 云顶地图包(一个目录)里按事件名分(同一事件的变体在同一边)。"""
	d = os.path.basename(os.path.dirname(f))
	return os.path.basename(f).split("__")[0] if d == "map22" else d


def split_by_champ(v: list) -> tuple:
	"""按英雄切 8:2(同一英雄的所有变体只在一边), 留出分数才是「没见过的英雄」的分数。"""
	champs = sorted({champ_of(f) for f in v})
	random.Random(11).shuffle(champs)
	hold_c = set(champs[: max(1, len(champs) // 5)])
	return [f for f in v if champ_of(f) not in hold_c], [f for f in v if champ_of(f) in hold_c]


def champ_set(ref: str) -> list:
	fs = []
	for tok in re.split(r"[/ ]+", ref):
		d = os.path.join(RIOT, "champ", tok)
		if os.path.isdir(d):
			fs += sorted(glob.glob(os.path.join(d, "*.wav")))
	if not fs and "Chogath" in ref:
		fs = sorted(glob.glob(os.path.join(RIOT, "chogath", "*.wav")))
	random.Random(7).shuffle(fs)
	return fs[:60]


_cache = {}


def emb(paths: list) -> np.ndarray:
	need = [p for p in paths if p not in _cache]
	for i in range(0, len(need), 32):
		chunk = need[i:i + 32]
		E = sfx_clap.embed_audio(chunk)
		for p, e in zip(chunk, E):
			_cache[p] = e
	return np.array([_cache[p] for p in paths]) if paths else np.zeros((0, 512))


def to_wav(mp3: str, prefix: str = "") -> str:
	os.makedirs(os.path.join(OUT, "cand"), exist_ok=True)
	w = os.path.join(OUT, "cand", prefix + os.path.basename(mp3)[:-4] + ".wav")
	if not os.path.exists(w):
		subprocess.run([FF, "-v", "error", "-y", "-i", mp3, "-ac", "1", "-ar", "44100", w], check=True)
	return w


def feats(path: str):
	m = measure(path)
	if not m:
		return None
	m["lcent"] = float(np.log2(max(m["cent"], 1.0)))
	return m


def stats(ms: list) -> dict:
	st = {}
	for c in FEATS + ["rms", "cent"]:
		a = np.array([m[c] for m in ms])
		st[c] = (float(np.percentile(a, 10)), float(np.median(a)), float(np.percentile(a, 90)))
	return st


def penalty(m: dict, st: dict) -> float:
	p = 0.0
	for c in FEATS:
		lo, md, hi = st[c]
		w = max(hi - lo, 1e-6)
		if m[c] < lo:
			p += (lo - m[c]) / w
		elif m[c] > hi:
			p += (m[c] - hi) / w
	return p


def main() -> int:
	os.makedirs(OUT, exist_ok=True)
	if os.path.exists(CACHE):
		z = np.load(CACHE, allow_pickle=True)
		_cache.update(dict(zip(list(z["k"]), list(z["v"]))))
	tab = json.load(open(TAB, encoding="utf-8"))
	items = tab["batches"]["v2"]
	rs = riot_sets()
	print("Riot 参考: " + " · ".join("%s %d" % (k, len(v)) for k, v in rs.items()))
	cent, st = {}, {}
	hold = {}
	for k, v in rs.items():
		ref, hold[k] = split_by_champ(v)
		E = emb(ref)
		c = E.mean(axis=0)
		cent[k] = c / np.linalg.norm(c)
		st[k] = stats([m for m in (feats(f) for f in ref) if m])
	PT = sfx_clap.embed_text(PIX_T)
	report = ["# 音效 v2 定选报告(tools/sfx_pick_v2.py 生成)", ""]
	## ⑤ 标定: Riot 留出样本 / 旧音效 / 新候选 与 Riot 同类中心的相似度
	old = sorted(glob.glob(os.path.join(ROOT, "assets", "audio", "sfx", "ev", "*.wav")))
	old_cat = {"atk_": "ba_hit", "cast_": "sk_cast"}
	report.append("## 标定: 尺子分不分得出(与 Riot 同类中心的 CLAP 余弦, 越高越像云顶)")
	report.append("")
	report.append("| 类别 | Riot 留出样本 | 旧音效 | 新候选(全部) |")
	report.append("|---|---|---|---|")
	cand_files = {}
	for it in items:
		for i in range(1, 5):
			for d, pre in ((CAND, ""), (CAND_R2, "r2__"), (CAND_R3, "r3__")):
				mp = os.path.join(d, "%s_%d.mp3" % (it["key"], i))
				if os.path.exists(mp):
					cand_files.setdefault(it["key"], []).append(to_wav(mp, pre))
	allc = [f for v in cand_files.values() for f in v]
	emb(allc)
	cat_of = {it["key"]: it["cat"] for it in items}
	for k in ["ba_cast", "ba_hit", "crit", "sk_cast", "sk_hit", "equip", "global"]:
		h = emb(hold[k]) @ cent[k] if hold[k] else np.array([])
		ol = [f for f in old if any(os.path.basename(f).startswith(p) and old_cat[p] == k for p in old_cat)]
		o = emb(ol) @ cent[k] if ol else np.array([])
		nc = [f for key, fs in cand_files.items() if cat_of[key] == k for f in fs]
		n = emb(nc) @ cent[k] if nc else np.array([])
		f3 = lambda a: ("%.3f (n=%d)" % (float(a.mean()), len(a))) if len(a) else "—"
		report.append("| %s | %s | %s | %s |" % (k, f3(h), f3(o), f3(n)))
	pix_old = emb(old) @ PT.T if old else np.zeros((0, 2))
	pix_new = emb(allc) @ PT.T if allc else np.zeros((0, 2))
	report.append("")
	report.append("像素感(CLAP: 像「8-bit 芯片音」减 像「写实电影级」, >0 = 更像像素): 旧音效 %d 条中位 %+.3f(>0 占 %.0f%%) · 新候选 %d 条中位 %+.3f(>0 占 %.0f%%)" % (
		len(old), float(np.median(pix_old[:, 0] - pix_old[:, 1])) if len(old) else 0, 100.0 * float(np.mean((pix_old[:, 0] - pix_old[:, 1]) > 0)) if len(old) else 0,
		len(allc), float(np.median(pix_new[:, 0] - pix_new[:, 1])) if allc else 0, 100.0 * float(np.mean((pix_new[:, 0] - pix_new[:, 1]) > 0)) if allc else 0))
	report.append("")
	## 打分 + 定选
	TE = sfx_clap.embed_text([it["text"] for it in items])
	picks = {}
	rows = []
	n_rej = 0
	champ_cent = {}
	for idx, it in enumerate(items):
		key, cat = it["key"], it["cat"]
		fs = cand_files.get(key, [])
		if not fs:
			rows.append((key, "缺候选"))
			continue
		ref_champ = it["ref"].split(" ")[0]
		if ref_champ not in champ_cent:
			cf = champ_set(ref_champ)
			if cf:
				c = emb(cf).mean(axis=0)
				champ_cent[ref_champ] = c / np.linalg.norm(c)
			else:
				champ_cent[ref_champ] = None
		E = emb(fs)
		sc = []
		for j, f in enumerate(fs):
			m = feats(f)
			e = E[j]
			pix = float(e @ PT[0] - e @ PT[1])
			rej = []
			if m is None or m["rms"] < -40:
				rej.append("近乎无声")
			elif m["cent"] < 180:
				rej.append("只剩低频轰鸣(质心 %.0f Hz)" % m["cent"])
			if pix > 0.02:
				rej.append("像素感 %+.3f" % pix)
			t = float(e @ TE[idx])
			r = float(e @ cent[cat])
			h = float(e @ champ_cent[ref_champ]) if champ_cent.get(ref_champ) is not None else r
			pen = penalty(m, st[cat]) if m else 9.0
			s = 2.0 * t + 1.5 * r + 0.75 * h - 0.6 * pen   # 形状罚分 0.25 → 0.6(第一轮选中的命中 / 暴击太闷, 形状要更有分量)
			sc.append(dict(file=f, text=round(t, 4), riot=round(r, 4), champ=round(h, 4), pen=round(pen, 3), pix=round(pix, 4),
				score=round(s, 4), rej=rej, dur=round(m["dur"], 3) if m else 0, low=round(m["low"], 3) if m else 0, cent=round(m["cent"], 1) if m else 0))
		ok = sorted([s for s in sc if not s["rej"]], key=lambda s: -s["score"])
		n_rej += len(sc) - len(ok)
		keep = KEEP_KEY.get(key, KEEP[cat])
		sel = ok[:keep]
		if not sel:   # 全被否决 ⇒ 记下, 由补生成那一步重出
			rows.append((key, "全部否决: " + "; ".join(",".join(s["rej"]) for s in sc)))
			picks[key] = {"cat": cat, "zh": it["zh"], "sel": [], "all": sc}
			continue
		picks[key] = {"cat": cat, "zh": it["zh"], "sel": [os.path.basename(s["file"]) for s in sel], "all": sc}
	json.dump(picks, open(os.path.join(OUT, "picks.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
	np.savez(CACHE, k=np.array(list(_cache.keys()), dtype=object), v=np.array(list(_cache.values())))
	## 各类: 选中的 vs Riot
	report.append("## 选中的与 Riot 同类比(中位)")
	report.append("")
	report.append("| 类别 | 事件数 | 选中变体 | CLAP 像云顶 | 像描述 | 时长 秒(Riot) | 低频占比(Riot) | 质心 Hz(Riot) |")
	report.append("|---|---|---|---|---|---|---|---|")
	for k in ["ba_cast", "ba_hit", "crit", "sk_cast", "sk_hit", "equip", "global"]:
		ss = [s for key, p in picks.items() if p["cat"] == k for s in p["all"] if os.path.basename(s["file"]) in p["sel"]]
		ne = sum(1 for p in picks.values() if p["cat"] == k)
		if not ss:
			report.append("| %s | %d | 0 | — | — | — | — | — |" % (k, ne))
			continue
		md = lambda f: float(np.median([s[f] for s in ss]))
		report.append("| %s | %d | %d | %.3f | %.3f | %.2f (%.2f) | %.2f (%.2f) | %.0f (%.0f) |" % (
			k, ne, len(ss), md("riot"), md("text"), md("dur"), st[k]["dur"][1], md("low"), st[k]["low"][1], md("cent"), st[k]["cent"][1]))
	report.append("")
	report.append("否决候选 %d 个; 没有可用候选的事件 %d 条:" % (n_rej, sum(1 for p in picks.values() if not p["sel"])))
	for key, why in rows:
		report.append("- %s: %s" % (key, why))
	open(os.path.join(OUT, "pick_report.md"), "w", encoding="utf-8").write("\n".join(report) + "\n")
	print("\n".join(report))
	return 0


if __name__ == "__main__":
	sys.exit(main())
