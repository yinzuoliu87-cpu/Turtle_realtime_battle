# -*- coding: utf-8 -*-
"""sfx_bar.py — 成品音效对黑箱标准逐项量（2026-11-04 · A5; 用户「你自己看看有没有达到那个黑箱的标准」）。

标准 = 黑箱 Demo 同一类原声整组(tools/sfx_pick.py CAT_REFS)的实际范围, 两头各放宽 30%:
  有效时长 / 起音 / 衰减(峰值降 20 dB) / 亮度(频谱质心)。响度与峰值由 build_sfx 按黑箱类间差统一, 这里只复核。
另量两项黑箱做到了的「整体」指标:
  · 同类响度一致: 普攻成品的有效段响度极差(黑箱 5 个命中变体差 ≤ 1.7 dB)
  · 区分度(用户要的, 黑箱没有): 普攻成品两两 CLAP 声音向量余弦(在 .out/sfx_rank/<批次>/ 里取定选候选的向量)
★量不出来的(要照实告诉用户): 好不好听、像不像那只龟的那个动作 —— 我听不见, CLAP 分不细(标定 10/20)。
用法: python tools/sfx_bar.py   → 打印每个事件过 / 不过哪几项, 写 .out/sfx_rank/bar.tsv
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_rank as R  # noqa: E402
import sfx_pick as P  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
ROOT = R.ROOT
OUT = os.path.join(ROOT, "assets", "audio", "sfx", "ev")
TOL = 0.3
METRICS = ("dur", "attack", "decay", "cent")
NAMES = {"dur": "时长", "attack": "起音", "decay": "衰减", "cent": "亮度", "rms": "响度"}
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "assetgen"))
import build_sfx as BUILD  # noqa: E402
ATK_TARGET = BUILD.ANCHOR   # 命中锚点(L100)
GR_MAX = 6.0   # 限幅最大压缩量上限(挑选时才量得到, 要源文件)


SINGLE_DUR = (0.5, 1.6)
_RNG = {}


def ranges() -> dict:
	"""类 → 各项合格区间。参照 ≥ 2 条的类: 四项都按整组实际范围 ± 30%; 只有 1 条参照的类: 只卡时长(参照的 0.5~1.6 倍)。"""
	if not _RNG:
		for c, names in P.CAT_REFS.items():
			fs = [R.feats(R.decode(os.path.join(R.REF_DIR, n + ".wav"))) for n in names]
			if len(fs) >= 2:
				_RNG[c] = {m: (min(f[m] for f in fs) * (1 - TOL), max(f[m] for f in fs) * (1 + TOL) + (0.01 if m == "attack" else 0.0)) for m in METRICS}
			else:
				_RNG[c] = {"dur": (fs[0]["dur"] * SINGLE_DUR[0], fs[0]["dur"] * SINGLE_DUR[1])}
	return _RNG


def check(f: dict, cat: str) -> list:
	bad = []
	## 普攻之间响度要一致(黑箱命中变体 ≤ 1.7 dB): 成品有效段响度偏离锚点 > 1 dB 也算不达标(限幅压不住的尖瞬态声音会掉队)
	if "gr" in f and f["gr"] > GR_MAX:
		bad.append("响度 靠限幅压了 %.1f dB(> %.0f)" % (f["gr"], GR_MAX))
	if cat == "atk" and "l100" in f and abs(f["l100"] - ATK_TARGET) > 1.0:
		bad.append("响度 L100 %.1f 偏离 %.1f" % (f["l100"], ATK_TARGET))
	for m, (lo, hi) in ranges()[cat].items():
		if not (lo <= f[m] <= hi):
			bad.append("%s %.3g 不在 [%.3g, %.3g]" % (NAMES[m], f[m], lo, hi))
	return bad


def main() -> int:
	pj = json.load(open(os.path.join(ROOT, "tools", "assetgen", "sfx_picks.json"), encoding="utf-8"))
	rows = ["event\tcat\t" + "\t".join(METRICS) + "\trms\tpeak\tfail"]
	n_pass = 0
	atk_rms = []
	fails_by = {}
	for k, v in sorted(pj["picks"].items()):
		x = R.decode(os.path.join(OUT, k + ".wav"))
		f = R.feats(x)
		f["l100"] = BUILD.l100(x)
		bad = check(f, v["cat"])
		for b in bad:
			m = [q for q in NAMES if b.startswith(NAMES[q])][0]
			fails_by[m] = fails_by.get(m, 0) + 1
		if v["cat"] == "atk":
			atk_rms.append(f["l100"])
		n_pass += 0 if bad else 1
		rows.append("%s\t%s\t%s\t%.1f\t%.1f\t%s" % (k, v["cat"], "\t".join("%.3f" % f[m] for m in METRICS), f["rms"], f["peak"], "; ".join(bad)))
		print(("✓ " if not bad else "✗ ") + "%-14s %s" % (k, "; ".join(bad)))
	open(os.path.join(ROOT, ".out", "sfx_rank", "bar.tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
	spread = (max(atk_rms) - min(atk_rms)) if atk_rms else 0.0
	print("分母: %d 个事件 · 四项全过 %d · 不过按项: %s" % (len(pj["picks"]), n_pass, {NAMES[m]: n for m, n in fails_by.items()}))
	print("普攻响度(L100)极差 %.1f LU(黑箱同一声音 5 变体 1.6; 线 2.0) · 普攻两两最像 %.3f(线 %.2f)" % (spread, max(v.get("max_sim_other_atk", 0) for v in pj["picks"].values()), P.SIM_MAX))
	return 0


if __name__ == "__main__":
	sys.exit(main())
