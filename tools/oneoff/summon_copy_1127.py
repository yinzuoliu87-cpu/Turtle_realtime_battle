# -*- coding: utf-8 -*-
"""一次性: 装备 / 羁绊文案里的召唤物属性搬去图鉴「角色」页(方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md §4 三、U3)。

用户 11-27「对于羁绊里的召唤去描述可以换种方式」「全部都搞好吧」。新写法: 只写「召唤【谁】、什么时候、它会做什么」,
召唤物的生命 / 攻击 / 护甲与逐项数值都在它的角色页; 【名字】在图鉴与商店说明卡里能点(SummonCodex.linkify)。
例外: 096 小木斧的形态 / 造物 / 主动 / 被动仍写在装备里(局内斧头面板按行读这份文案, 商店进化条也读), 只删掉「【斧头】拥有」那段属性。
改动: data/phase2-equipment.json(按 JSON 转义串原地替换, 不重排文件) / locale/en.po(同一条 msgid 原地换中英) /
      scripts/gamedata/phase2_types.gd(灵物 TIER_TABLE, 长矛 / 灵物 TIER_DESCS) / scripts/gamedata/equip_tier_labels.gd(分星短标签跟着正文)。
"""
import io, json, os, re, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def rd(rel):
	raw = io.open(os.path.join(ROOT, rel), "rb").read().decode("utf-8")
	return raw.replace("\r\n", "\n"), ("\r\n" in raw)


def wr(rel, s, crlf):
	if crlf:
		s = s.replace("\n", "\r\n")
	io.open(os.path.join(ROOT, rel), "wb").write(s.encode("utf-8"))


## (装备, 字段) → (新中文, 新英文)
NEW = {
	("p2eq_032", "effectDesc1"): ("登场时召唤一只【亡灵骷髅】。亡灵骷髅受到的任何伤害都只有 1 点，真实伤害也一样，阵亡或存在一段时间后爆炸，对周围的敌人造成真实伤害。",
		"On spawn, summons an [Undead Skeleton]. It takes only 1 damage from anything, true damage included, and explodes when it dies or after a while, dealing true damage to nearby enemies."),
	("p2eq_032", "effectBrief"): ("登场时召唤一只【亡灵骷髅】，其受到的任何攻击均只造成 1 点伤害。",
		"On spawn, summons an [Undead Skeleton] that takes only 1 damage from any attack."),
	("p2eq_033", "effectDesc1"): ("所有复活机会用尽、彻底阵亡时，在原位变形为一只【海螺虫】。海螺虫诞生时随机携带 3 件 1/2/3 星的 {C:EquipSystem.CONCH_COST_MIN} 费或 {C:EquipSystem.CONCH_COST_MAX} 费装备。",
		"When all revives are used up and the holder dies for good, it turns into a [Conch Bug] in place. The bug is born carrying 3 random 1/2/3-star {C:EquipSystem.CONCH_COST_MIN}- or {C:EquipSystem.CONCH_COST_MAX}-cost items."),
	("p2eq_033", "effectDesc3"): ("3 星：【海螺虫】会不断分裂出新的海螺虫。", "3-star: the [Conch Bug] keeps splitting off new bugs."),
	("p2eq_033", "effectBrief"): ("彻底阵亡时在原位变为一只【海螺虫】继续战斗，并随机携带 3 件装备。",
		"When the holder dies for good, it turns into a [Conch Bug] that fights on, carrying 3 random items."),
	("p2eq_034", "effectDesc1"): ("每 {C:EquipTickSystem.DOLL_IV} 秒向最近敌人派出小熊，造成（100/200/500% 攻击力+100/210/1000）物理伤害并将其击飞，携带者获得 1 层大熊层数。达到 5/3/1 层时装备销毁，携带者蓄力 {C:EquipTickSystem.DOLL_CHARGE_SEC} 秒后在空位召唤一只【大熊】。若无空位，继续派出小熊直至有空位。",
		"Every {C:EquipTickSystem.DOLL_IV} seconds, sends a little bear at the nearest enemy, dealing (100/200/500% Attack + 100/210/1000) physical damage and knocking it up; the holder gains 1 Bear stack. At 5/3/1 stacks the item is destroyed, and after channeling for {C:EquipTickSystem.DOLL_CHARGE_SEC} seconds the holder summons a [Big Bear] in an empty spot. If there's no empty spot, it keeps sending little bears until there is."),
	("p2eq_034", "effectBrief"): ("每 {C:EquipTickSystem.DOLL_IV} 秒派出小熊撞击最近的敌人。达到 5/3/1 层后召唤一只【大熊】。",
		"Every {C:EquipTickSystem.DOLL_IV} seconds, sends a little bear to ram the nearest enemy. At 5/3/1 stacks, summons a [Big Bear]."),
	("p2eq_058", "effectDesc1"): ("登场时召唤一座不可移动的【炮台】。\n携带者位于炮台附近时，获得 {C:EquipSystem.TURRET_BUFF_ASPD%}% 攻击速度。",
		"On spawn, summons an immobile [Turret].\nWhile the wearer is near the Turret, the wearer gains {C:EquipSystem.TURRET_BUFF_ASPD%}% attack speed."),
	("p2eq_058", "effectBrief"): ("登场时召唤一座不可移动的【炮台】，携带者在炮台附近时获得攻击速度。",
		"On spawn, summons an immobile [Turret]. The wearer gains attack speed while near it."),
	("p2eq_072", "effectDesc1"): ("获得最大生命值 50/80/120% 的永久【终极护盾】。\n护盾存在时，携带者化为蛋糕礼盒：属性不变，射程变为近战，攻击与技能替换为礼盒效果。\n礼盒嘲讽附近所有敌人，每有一个敌人以携带者为目标，获得 {C:EqFoodBatch.BOX_RES_PER_LOCKER} 双抗。攻击造成 {C:EqFoodBatch.BOX_HIT_COEF%}% 攻击力物理伤害。技能召唤蛋糕法阵，持续 {C:EqFoodBatch.BOX_FIELD_SEC} 秒，每秒为其中友军回复 {C:EqFoodBatch.BOX_FIELD_HEAL} 生命值与 {C:EqFoodBatch.BOX_FIELD_ENERGY} 龟能。\n终极护盾破碎时，携带者脱离礼盒。\n携带者阵亡时分裂出两个【蛋糕礼盒】。",
		"Gains a permanent [Ultimate Shield] equal to 50/80/120% of max health.\nWhile it holds, the holder becomes a Cake Box: stats unchanged, range becomes melee, and attacks and abilities are replaced by Cake Box effects.\nThe Cake Box taunts all nearby enemies and gains {C:EqFoodBatch.BOX_RES_PER_LOCKER} Armor and Magic Resist for each enemy targeting it. Attacks deal {C:EqFoodBatch.BOX_HIT_COEF%}% Attack as physical damage. Its ability summons a cake circle for {C:EqFoodBatch.BOX_FIELD_SEC} seconds that heals allies inside for {C:EqFoodBatch.BOX_FIELD_HEAL} and gives {C:EqFoodBatch.BOX_FIELD_ENERGY} Energy per second.\nWhen the Ultimate Shield breaks, the holder leaves the Cake Box.\nWhen the holder dies, it splits into two [Cake Box] summons."),
	("p2eq_077", "effectDesc1"): ("生成一把【小手枪】协同攻击，其受到的所有伤害降为 {C:EqGunBatch.PISTOL_DMG_CAP} 点。\n小手枪的攻击会触发枪羁绊【金弹】。",
		"Creates a [Little Pistol] that attacks alongside. All damage it takes is reduced to {C:EqGunBatch.PISTOL_DMG_CAP}.\nThe pistol's attacks trigger the Gun synergy's [Golden Bullet]."),
	("p2eq_077", "effectBrief"): ("生成一把【小手枪】协同攻击，其受到的所有伤害降为 {C:EqGunBatch.PISTOL_DMG_CAP} 点。",
		"Creates a [Little Pistol] that attacks alongside. All damage it takes is reduced to {C:EqGunBatch.PISTOL_DMG_CAP}."),
	("p2eq_079", "effectDesc1"): ("在携带者后方生成一座【急救塔】，攻击敌人，并为生命百分比最低的友军回复生命值。\n急救塔拥有独立的金弹计数，随枪羁绊件数射出金弹。",
		"Creates an [Aid Tower] behind the holder that attacks enemies and heals the ally with the lowest health percentage.\nThe tower has its own Golden Bullet counter, which scales with Gun count."),
	("p2eq_079", "effectBrief"): ("在身后生成一座【急救塔】，攻击对敌人造成伤害，并为生命百分比最低的友军回复生命值。",
		"Creates an [Aid Tower] behind it. Its attacks damage enemies and heal the ally with the lowest health percentage."),
	("p2eq_105", "effectDesc1"): ("登场时在己方后方召唤一门【炮筒】。炮筒龟能满时进入重炮状态，炮弹沿直线飞过整个战场，击退直线上的敌人并施加流血。",
		"On spawn, summons a [Cannon] behind your side. When its Energy is full it enters Heavy Shot mode: shells fly in a straight line across the whole battlefield, knocking back enemies in the line and applying Bleed."),
	("p2eq_105", "effectBrief"): ("召唤一门高血量【炮筒】，龟能满时进入重炮状态，直线击退并流血。",
		"Summons a high-health [Cannon]. When its Energy is full it enters Heavy Shot mode, knocking back and bleeding enemies in a line."),
	("p2eq_106", "effectDesc1"): ("登场时在己方前排召唤一枚【遥控炸弹】。遥控炸弹追着一个敌人移动，不攻击，生命值耗尽时大范围爆炸，造成物理伤害和基于携带者最大生命值的真实伤害，并施加流血。",
		"On spawn, summons a [Remote Bomb] in your front line. It chases an enemy without attacking and, when its health runs out, explodes over a large area, dealing physical damage plus true damage based on the holder's max health, and applying Bleed."),
	("p2eq_106", "effectBrief"): ("召唤一枚追着敌人跑的【遥控炸弹】，生命耗尽时大范围爆炸。",
		"Summons a [Remote Bomb] that chases enemies and explodes over a large area when its health runs out."),
	("p2eq_107", "effectDesc1"): ("登场时召唤一名【武士刀小将】。武士刀小将龟能满时释放技能，四次一循环：前三次向前方挥出一道剑气波，第四次蓄力并回复自身生命值，随后向前方吹出龙卷风，击飞敌人。",
		"On spawn, summons a [Katana Minion]. When its Energy is full it casts its ability in a 4-cast cycle: the first three send a sword wave forward, and the fourth charges up while healing itself, then blows tornadoes forward that knock enemies up."),
	("p2eq_107", "effectBrief"): ("召唤一名【武士刀小将】，前三次技能挥剑气波，第四次蓄力回血后吹出龙卷风。",
		"Summons a [Katana Minion]. Its first three casts swing sword waves, and the fourth charges up to heal, then blows tornadoes."),
	("p2eq_115", "effectDesc1"): ("登场时召唤一名【暗影忍者】。暗影忍者登场时隐身，龟能满时化为黑烟，背刺生命值比例最低的敌人并掷出手里剑。暗影忍者的生命值首次低于一半时，分出一名影子忍者。",
		"On spawn, summons a [Shadow Ninja]. It enters stealthed, and when its Energy is full it vanishes into black smoke, backstabs the enemy with the lowest health ratio and throws a shuriken. The first time it drops below half health, it splits off a shadow clone."),
	("p2eq_115", "effectBrief"): ("召唤【暗影忍者】，影袭背刺生命值最低的敌人，半血时分出影子一起掷出手里剑。",
		"Summons a [Shadow Ninja] that backstabs the lowest-health enemy. At half health it splits off a shadow, and both throw shurikens."),
	("p2eq_123", "effectDesc1"): ("释放技能后随机召唤一具【骷髅战士】、【骷髅法师】或【骷髅祭司】，存在时间等于这次消耗的龟能 × {C:EqMagicBatch.SKEL_SEC_PER_EN} 秒。",
		"After casting an ability, summons a random [Skeleton Warrior], [Skeleton Mage] or [Skeleton Priest] that lasts for the Energy spent × {C:EqMagicBatch.SKEL_SEC_PER_EN} seconds."),
	("p2eq_123", "effectBrief"): ("释放技能后召唤一具随机的【骷髅战士】、【骷髅法师】或【骷髅祭司】。",
		"After casting an ability, summons a random [Skeleton Warrior], [Skeleton Mage] or [Skeleton Priest]."),
	("p2eq_130", "effectDesc1"): ("登场时召唤一头【舞狮】。舞狮龟能满时朝前方冲撞，撞退并眩晕途经的敌人。",
		"On spawn, summons a [Lion Dancer]. When its Energy is full it charges forward, knocking back and stunning enemies in its path."),
	("p2eq_130", "effectBrief"): ("召唤一头【舞狮】，龟能满时冲撞途经的敌人，撞退并眩晕。",
		"Summons a [Lion Dancer] that charges through enemies when its Energy is full, knocking them back and stunning them."),
}

## 分星短标签: 正文里还剩哪几组 a/b/c 就留哪几条; 一组都不剩的整条删
LABELS = {
	"p2eq_032": None, "p2eq_033": ["装备星级 # 星"],
	"p2eq_034": ["小熊伤害 #% 攻击力", "小熊基础伤害 #", "召唤所需层数 # 层"],
	"p2eq_058": None, "p2eq_072": ["终极护盾 #% 最大生命值", "双抗 +#", "每秒回复 #", "每秒龟能 #"],
	"p2eq_077": None, "p2eq_079": None, "p2eq_105": None, "p2eq_106": None, "p2eq_107": None,
	"p2eq_115": None, "p2eq_123": None, "p2eq_130": None,
}


def po_esc(s):
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")


def main():
	## ① 装备 JSON: 取旧值 → 按 JSON 转义串原地换
	js, js_crlf = rd("data/phase2-equipment.json")
	data = json.loads(js)
	items = data if isinstance(data, list) else data.get("equipment", [])
	by_id = {e.get("id"): e for e in items}
	old_new = []   # (旧中文, 新中文, 新英文)
	for (eid, field), (cn, en) in NEW.items():
		old = by_id[eid].get(field, "")
		assert old, (eid, field)
		a = json.dumps(old, ensure_ascii=False)
		assert js.count(a) == 1, (eid, field, js.count(a))
		js = js.replace(a, json.dumps(cn, ensure_ascii=False))
		old_new.append((old, cn, en))
	## 096: 删「【斧头】拥有」那段(灰字 span 里最后几行)
	d1 = by_id["p2eq_096"]["effectDesc1"]
	cut = d1.index("\n【斧头】拥有：</span>")
	new96 = d1[:cut] + "</span>"
	a = json.dumps(d1, ensure_ascii=False)
	assert js.count(a) == 1
	js = js.replace(a, json.dumps(new96, ensure_ascii=False))
	wr("data/phase2-equipment.json", js, js_crlf)
	print("json ok", len(old_new) + 1)

	## ② en.po: 同一条 msgid 原地换(中 + 英); 096 英文同样切掉「[Axe] has:」段
	po, po_crlf = rd("locale/en.po")
	miss = []
	for old, cn, en in old_new:
		pat = re.compile(r'^msgid "%s"\nmsgstr "(.*)"$' % re.escape(po_esc(old)), re.M)
		m = pat.search(po)
		if not m:
			miss.append((cn, en))
			continue
		po = po[:m.start()] + 'msgid "%s"\nmsgstr "%s"' % (po_esc(cn), po_esc(en)) + po[m.end():]
	pat = re.compile(r'^msgid "%s"\nmsgstr "(.*)"$' % re.escape(po_esc(d1)), re.M)
	m = pat.search(po)
	assert m, "096 en"
	en96 = m.group(1)
	k = en96.index("\\n[Axe] has:</span>")
	po = po[:m.start()] + 'msgid "%s"\nmsgstr "%s"' % (po_esc(new96), en96[:k] + "</span>") + po[m.end():]
	wr("locale/en.po", po, po_crlf)
	print("po ok; 原来没有英文的:", len(miss))
	for cn, en in miss:
		print("  MISS", cn[:30])

	## ③ 分星短标签
	tl, tl_crlf = rd("scripts/gamedata/equip_tier_labels.gd")
	for eid, labels in LABELS.items():
		m = re.search(r'^\t"%s": \[.*?\],\n' % eid, tl, re.M | re.S)
		assert m, eid
		if labels is None:
			tl = tl[:m.start()] + tl[m.end():]
		else:
			tl = tl[:m.start()] + '\t"%s": [%s],\n' % (eid, ", ".join('"%s"' % x for x in labels)) + tl[m.end():]
	wr("scripts/gamedata/equip_tier_labels.gd", tl, tl_crlf)
	print("labels ok")


if __name__ == "__main__":
	main()
