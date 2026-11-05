# -*- coding: utf-8 -*-
"""tools/sfx_skill_refs.py — 每个技能 / 装备对准它参考的那个英雄技能的原声文件(2026-11-05)。
由来: 11-05 用户「云顶音效怎么做的？每个技能怎么做的这个音效？」+ 用户认可音效 v2 出版合格后的优化第 1 项: 技能放出挑选时比的是参考英雄的
  全部声音(普攻 / 走路 / 回城混一起), 不是参考的那个技能。这里把描述表里的「Malphite R」翻成原声文件名里的事件名(UFSlash), 产出正则。
  英雄技能编号取自 Riot Data Dragon(.out/ddragon/spells.json, 由本脚本 --fetch 拉取; 只当对照表, 不进游戏)。
用法: python tools/sfx_skill_refs.py [--fetch] [--report]   (sfx_v2_table 导入 ref_rx_for)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIOT = os.path.join(ROOT, ".out", "riot_audio")
SPELLS = os.path.join(ROOT, ".out", "ddragon", "spells.json")
CAST_STRICT = r"(oncast|_cast|missilelaunch)"   # 真正的施放声; 有就只用它(11-05: 塔里克 W 匹配到 7 秒的牵引警示循环, 当放出声尺子不对)
CAST_W = r"(oncast|_cast|missilelaunch|onbuffactivate|buffactivate|charge|into|transform)"
HIT_W = r"(hit|onhitlocation|land|explode|impact|slam)"
ALIAS = {"LeBlanc": "Leblanc", "AurelionSol": "AurelionSol"}


def _spells() -> dict:
	return json.load(open(SPELLS, encoding="utf-8")) if os.path.exists(SPELLS) else {}


def _files_of(champ: str) -> list:
	d = os.path.join(RIOT, "chogath") if champ.lower() == "chogath" else os.path.join(RIOT, "champ", champ)
	return sorted(f for f in os.listdir(d) if f.endswith(".wav")) if os.path.isdir(d) else []


def ref_rx_for(ref: str, kind: str) -> str:
	"""ref = 描述表参考栏(「Malphite R」「Lux R/Seraphine R」「Jayce Q / Jayce hammer Q」); kind = cast / hit。
	返回能匹配到原声文件名(小写)的正则; 参考栏没写技能键或英雄没解出来 ⇒ 空串(挑选退回整只英雄 / 整类)。"""
	sp = _spells()
	alts = []
	for part in re.split(r"\s*/\s*", ref.strip()):
		m = re.match(r"([A-Za-z]+)\s+(Q|W|E|R)\b", part)
		if not m:
			continue
		champ = ALIAS.get(m.group(1), m.group(1))
		key = m.group(2)
		if not _files_of(champ):
			continue
		ids = {(champ + key).lower()}
		sid = sp.get(champ, {}).get(key)
		if sid:
			ids.add(sid.lower())
		head = "%s_(%s)[a-z0-9]*_" % (champ.lower(), "|".join(sorted(re.escape(i) for i in ids)))
		if kind == "cast":
			fl = [f.lower() for f in _files_of(champ)]
			alts.append(head + (CAST_STRICT if any(re.search(head + CAST_STRICT, f) for f in fl) else CAST_W))
		else:
			alts.append(head + HIT_W)
	return ("(" + "|".join(alts) + ")") if alts else ""


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	if "--fetch" in sys.argv:
		import urllib.request
		v = json.load(urllib.request.urlopen("https://ddragon.leagueoflegends.com/api/versions.json", timeout=20))[0]
		champs = sorted(set(os.listdir(os.path.join(RIOT, "champ"))) | {"Chogath"})
		out = {}
		for c in champs:
			d = json.load(urllib.request.urlopen("https://ddragon.leagueoflegends.com/cdn/%s/data/en_US/champion/%s.json" % (v, c), timeout=20))["data"]
			k = list(d)[0]
			out[k] = {"QWER"[i]: s["id"] for i, s in enumerate(d[k]["spells"])}
		os.makedirs(os.path.dirname(SPELLS), exist_ok=True)
		json.dump(out, open(SPELLS, "w", encoding="utf-8"), indent=1)
		print("Data Dragon %s · %d 个英雄" % (v, len(out)))
	if "--report" in sys.argv:
		sys.path.insert(0, os.path.join(ROOT, "tools", "assetgen"))
		import sfx_v2_table as t
		allf = [f.lower() for c in os.listdir(os.path.join(RIOT, "champ")) for f in _files_of(c)] + [f.lower() for f in _files_of("Chogath")]
		n_c = n_h = n_hk = 0
		for row in t.S:
			rc, rh = ref_rx_for(row[3], "cast"), ref_rx_for(row[3], "hit")
			fc = [f for f in allf if rc and re.search(rc, f)]
			fh = [f for f in allf if rh and re.search(rh, f)] if row[5] else []
			n_c += bool(fc)
			n_hk += bool(row[5])
			n_h += bool(fh)
			print("%-22s %-28s 放出 %2d 命中 %2d  %s" % (row[0], row[3], len(fc), len(fh), (fc[:1] or [""])[0]))
		print("分母 %d 个技能: 放出对上 %d · 命中(有命中声的 %d 个)对上 %d" % (len(t.S), n_c, n_hk, n_h))
	return 0


if __name__ == "__main__":
	sys.exit(main())
