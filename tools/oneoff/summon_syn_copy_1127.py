# -*- coding: utf-8 -*-
"""一次性: 灵物 / 长矛羁绊文案里的召唤物属性搬去图鉴「角色」页(亡魂 / 百夫长), 同 summon_copy_1127.py(方案书 20261127d U3)。
TIER_TABLE(图鉴 / 背包现在显示的那份)与 TIER_DESCS(旧逐档文案, 仍是部分门禁的分母)两处一起改; en.po 同一条原地换。
"""
import io, os, re, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SS = "SpiritSynergySystem"
SP = "SpearSynergySystem"

## 旧中文 → (新中文, 新英文)
SUBS = [
	# 灵物 TIER_TABLE
	("【亡灵】友方单位阵亡时原地召唤 1 只亡魂，继承其部分攻击力与生命值，自动攻击最近的敌人。亡魂阵亡后可再次召唤，每次继承的属性为上一次的 {C:%s.WRAITH_DECAY%%}%%。" % SS,
	 "【亡灵】友方单位阵亡时原地召唤 1 只【亡魂】，继承其部分攻击力与生命值，自动攻击最近的敌人。",
	 "[Undeath] When an allied unit dies, 1 [Wraith] rises in its place, inheriting part of its Attack and health, and attacks the nearest enemy."),
	("每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[0]} 根触手，亡魂继承 {C:%s.WRAITH_INHERIT[0]%%}%%" % (SS, SS),
	 "每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[0]} 根触手，召唤亡魂" % SS,
	 "+{STAT:dodgePct}%% Dodge each, {C:%s.TENTACLES[0]} tentacle(s), summons Wraiths" % SS),
	("每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[1]} 根触手，闪避蓄能，亡魂继承 {C:%s.WRAITH_INHERIT[1]%%}%%，可再召唤 {C:%s.WRAITH_LOOPS[1]} 次" % (SS, SS, SS),
	 "每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[1]} 根触手，闪避蓄能，亡魂继承更多属性，阵亡后可再化为亡魂" % SS,
	 "+{STAT:dodgePct}%% Dodge each, {C:%s.TENTACLES[1]} tentacles, Dodge Charge, Wraiths inherit more and can rise again after dying" % SS),
	("每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[2]} 根触手，拍击伤害变为原来的 {C:%s.HIT_MULT[2]%%}%%，亡魂继承 {C:%s.WRAITH_INHERIT[2]%%}%%，可再召唤 {C:%s.WRAITH_LOOPS[2]} 次" % (SS, SS, SS, SS),
	 "每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[2]} 根触手，拍击伤害变为原来的 {C:%s.HIT_MULT[2]%%}%%，亡魂继承更多属性，可多次再化为亡魂" % (SS, SS),
	 "+{STAT:dodgePct}%% Dodge each, {C:%s.TENTACLES[2]} tentacles, slam damage becomes {C:%s.HIT_MULT[2]%%}%%, Wraiths inherit more and can rise again several times" % (SS, SS)),
	("每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[3]} 根触手，拍击伤害变为原来的 {C:%s.HIT_MULT[3]%%}%%，亡魂继承 {C:%s.WRAITH_INHERIT[3]%%}%%，可再召唤 {C:%s.WRAITH_LOOPS[3]} 次" % (SS, SS, SS, SS),
	 "每件 +{STAT:dodgePct}%% 闪避，{C:%s.TENTACLES[3]} 根触手，拍击伤害变为原来的 {C:%s.HIT_MULT[3]%%}%%，亡魂继承阵亡单位全部的生命值与攻击力" % (SS, SS),
	 "+{STAT:dodgePct}%% Dodge each, {C:%s.TENTACLES[3]} tentacles, slam damage becomes {C:%s.HIT_MULT[3]%%}%%, Wraiths inherit all of the fallen unit's health and Attack" % (SS, SS)),
]


def po_esc(s):
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")


def main():
	p = os.path.join(ROOT, "scripts/gamedata/phase2_types.gd")
	raw = io.open(p, "rb").read().decode("utf-8")
	crlf = "\r\n" in raw
	s = raw.replace("\r\n", "\n")
	pp = os.path.join(ROOT, "locale/en.po")
	praw = io.open(pp, "rb").read().decode("utf-8")
	pcrlf = "\r\n" in praw
	po = praw.replace("\r\n", "\n")
	todo = list(SUBS)
	## TIER_DESCS: 长矛 / 灵物 整组替换(逐档召唤物数值去掉)
	m = re.search(r'\t"长矛": \[\n(\t\t".*",\n){4}\t\],\n', s)
	assert m, "TIER_DESCS 长矛"
	olds = re.findall(r'\t\t"(.*)",\n', m.group(0))
	news = [
		("每件长矛为携带者提供 +5%% 龟能回复速率 · 【百夫长】每个战场开始 {C:%s.SUMMON_AT} 秒后或我方生命值低于 {C:%s.TEAM_HP_LINE%%}%% 时召唤百夫长，每个战场一次。我方每有一件不同的长矛，按其星级每星使百夫长生命值与攻击力提高 {C:%s.STAR_PCT%%}%%" % (SP, SP, SP),
		 "Each Spear gives its holder +5%% Energy Regen · [Centurion] summoned {C:%s.SUMMON_AT} seconds into each battle or when your team drops below {C:%s.TEAM_HP_LINE%%}%% health, once per battle. For each different Spear you have, the Centurion gains {C:%s.STAR_PCT%%}%% health and Attack per star" % (SP, SP, SP)),
		("每件长矛为携带者提供 +10% 龟能回复速率 · 百夫长的突刺贯穿直线，放下盾时横扫周围敌人",
		 "Each Spear gives its holder +10% Energy Regen · the Centurion's thrust pierces in a line and it sweeps nearby enemies when lowering its shield"),
		("每件长矛为携带者提供 +16% 龟能回复速率 · 百夫长每次刺中削弱敌人的护甲和魔抗，举盾时持续刺击周围敌人",
		 "Each Spear gives its holder +16% Energy Regen · each Centurion hit shreds enemy Armor and Magic Resist, and it keeps stabbing nearby enemies while its shield is up"),
		("每件长矛为携带者提供 +24%% 龟能回复速率 · 百夫长每第 {C:%s.THROW_EVERY} 次攻击掷出长矛，横扫后召来持矛骑兵冲锋" % SP,
		 "Each Spear gives its holder +24%% Energy Regen · every {C:%s.THROW_EVERY}th Centurion attack throws its spear, and its sweep calls in charging spear cavalry" % SP),
	]
	for o, (cn, en) in zip(olds, news):
		todo.append((o, cn, en))
	m = re.search(r'\t"灵物": \[\n(\t\t".*",\n){4}\t\],\n', s)
	assert m, "TIER_DESCS 灵物"
	olds = re.findall(r'\t\t"(.*)",\n', m.group(0))
	keep_tent = olds[0].split(" · 【亡灵】")[0]
	news = [
		(keep_tent + " · 【亡灵】友方单位阵亡时原地召唤 1 只【亡魂】，自动攻击最近的敌人", None),
		(olds[1].split(" · 【亡灵】")[0] + " · 【亡灵】亡魂继承更多属性，阵亡后可再化为亡魂", None),
		(olds[2].split(" · 【亡灵】")[0] + " · 【亡灵】亡魂继承更多属性，可多次再化为亡魂", None),
		(olds[3].split(" · 【亡灵】")[0] + " · 【亡灵】亡魂继承阵亡单位全部的生命值与攻击力", None),
	]
	en_tail = [" · [Undeath] when an allied unit dies, 1 [Wraith] rises in its place and attacks the nearest enemy",
		" · [Undeath] Wraiths inherit more and can rise again after dying",
		" · [Undeath] Wraiths inherit more and can rise again several times",
		" · [Undeath] Wraiths inherit all of the fallen unit's health and Attack"]
	for i, o in enumerate(olds):
		pat = re.compile(r'^msgid "%s"\nmsgstr "(.*)"$' % re.escape(po_esc(o)), re.M)
		mm = pat.search(po)
		assert mm, ("灵物 en", i)
		en_old = mm.group(1).replace("\\\"", "\"")
		k = en_old.find(" · [")
		k2 = en_old.rfind(" · ")
		en_head = en_old[:k2] if k2 > 0 else en_old
		todo.append((o, news[i][0], en_head + en_tail[i]))
	n_po = 0
	for old, cn, en in todo:
		assert s.count('"%s"' % old) == 1, ("gd", s.count('"%s"' % old), old[:40])
		s = s.replace('"%s"' % old, '"%s"' % cn)
		pat = re.compile(r'^msgid "%s"\nmsgstr "(.*)"$' % re.escape(po_esc(old)), re.M)
		mm = pat.search(po)
		if mm:
			po = po[:mm.start()] + 'msgid "%s"\nmsgstr "%s"' % (po_esc(cn), po_esc(en)) + po[mm.end():]
			n_po += 1
		else:
			po += '\nmsgid "%s"\nmsgstr "%s"\n' % (po_esc(cn), po_esc(en))
	if crlf:
		s = s.replace("\n", "\r\n")
	io.open(p, "wb").write(s.encode("utf-8"))
	if pcrlf:
		po = po.replace("\n", "\r\n")
	io.open(pp, "wb").write(po.encode("utf-8"))
	print("ok", len(todo), "po 原地换", n_po)


if __name__ == "__main__":
	main()
