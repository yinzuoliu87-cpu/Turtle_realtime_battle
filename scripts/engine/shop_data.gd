class_name ShopData
extends RefCounted
# ══════════════════════════════════════════════════════════
# shop_data.gd — 战中商店数据 (1:1 PoC shop-quick.ts)
# 触发 turn%4==0 (4/8/12), shopIndex=turn/4-1. 6格 A-E 随机+F重投.
# ══════════════════════════════════════════════════════════

const BASE_PRICE := {"buff": 16, "consumable": 24, "normal": 32, "unique": 41}
const RARITY_LABEL := {"buff": "增益", "consumable": "消耗品", "normal": "普通装备", "unique": "独特装备"}   # 1:1 PoC shop-quick.ts:108-110
const SLOT_DIST := {
	"A": {"buff": 40, "consumable": 25, "normal": 20, "unique": 15},
	"B": {"buff": 30, "consumable": 30, "normal": 25, "unique": 15},
	"C": {"buff": 30, "consumable": 25, "normal": 30, "unique": 15},
	"D": {"buff": 25, "consumable": 20, "normal": 35, "unique": 20},
	"E": {"buff": 15, "consumable": 15, "normal": 30, "unique": 40},
}
const SLOT_ORDER := ["A", "B", "C", "D", "E"]

# 12 增益 (7 全队 team + 5 单体 single) — PoC BUFF_POOL
const BUFF_POOL := [
	{"id": "q_blade", "name": "🗡 锋利之刃", "desc": "全队 +10% ATK / 3回合", "kind": "team", "type": "atkUp", "value": 10, "duration": 3},
	{"id": "q_shield", "name": "🛡 灵龟之盾", "desc": "全队 +15% DEF/MR / 3回合", "kind": "team", "type": "defUp", "value": 15, "duration": 3},
	{"id": "q_lifesteal", "name": "🩸 嗜血药剂", "desc": "全队 +15% 生命偷取 / 3回合", "kind": "team", "type": "lifesteal", "value": 15, "duration": 3},
	{"id": "q_swift", "name": "💨 疾风之策", "desc": "全队下回合 CD -1", "kind": "team", "type": "cdDown", "value": 1, "duration": 1},
	{"id": "q_hawk", "name": "👁 鹰眼", "desc": "全队 +15% 暴击 / 2回合", "kind": "team", "type": "critUp", "value": 15, "duration": 2},
	{"id": "q_critdmg", "name": "💥 致命一击", "desc": "全队 +25% 暴击伤害 / 2回合", "kind": "team", "type": "critDmgUp", "value": 25, "duration": 2},
	{"id": "q_dodge", "name": "🍃 闪避之灵", "desc": "全队 +10% 闪避 / 2回合", "kind": "team", "type": "dodge", "value": 10, "duration": 2},
	{"id": "q_rage", "name": "🔥 怒火药水", "desc": "单龟 +25% ATK / 3回合", "kind": "single", "type": "atkUp", "value": 25, "duration": 3},
	{"id": "q_emergency", "name": "⛑ 应急护盾", "desc": "单龟 +80 护盾", "kind": "single", "type": "shield", "value": 80, "duration": 0},
	{"id": "q_firstaid", "name": "🌿 急救包", "desc": "单龟回 15% maxHp", "kind": "single", "type": "heal", "value": 15, "duration": 0},
	{"id": "q_cleanse", "name": "✨ 净化", "desc": "单龟移除全部负面", "kind": "single", "type": "cleanse", "value": 0, "duration": 0},
	{"id": "q_mark", "name": "🎯 必中标记", "desc": "敌单 受伤 +20% / 2回合", "kind": "single", "type": "markedDmg", "value": 20, "duration": 2, "wantsEnemy": true},
]


## 生成 6 格商品 (A-E 随机 + F重投). 返回 [{slot,rarity,name,desc,price,buff?,equipId?}].
static func roll(shop_index: int) -> Array:
	var items: Array = []
	for slot in SLOT_ORDER:
		var rarity := _pick_rarity(SLOT_DIST[slot])
		var price := int(round(BASE_PRICE[rarity] * pow(1.25, shop_index) * (0.9 + randf() * 0.2)))
		price = maxi(1, price)
		var it := {"slot": slot, "rarity": rarity, "price": price}
		if rarity == "buff":
			var b: Dictionary = BUFF_POOL[randi() % BUFF_POOL.size()]
			it["name"] = b["name"]; it["desc"] = b["desc"]; it["buff"] = b
		else:
			var pool: Array = []
			for e in DataRegistry.all_equipment:
				if e.get("category", "") == rarity:
					pool.append(e)
			if pool.is_empty():
				it["name"] = "—"; it["desc"] = "(无)"; it["price"] = 999999
			else:
				var eq: Dictionary = pool[randi() % pool.size()]
				# 1:1 PoC shop-quick.ts:127 `${name} · ${RARITY_LABEL}` (normal=普通装备/unique=独特装备/consumable=消耗品)
				it["name"] = str(eq.get("name", "?")) + " · " + RARITY_LABEL.get(rarity, "")
				it["desc"] = str(eq.get("desc", "")).split("\n")[0].strip_edges()   # 首行 + trim (PoC shortDesc)
				it["equipId"] = eq.get("id", ""); it["rarity"] = rarity
		items.append(it)
	# F = 重投
	items.append({"slot": "F", "rarity": "reroll", "name": "🎲 重置骰子", "desc": "刷新本商店全部商品 (每次重投费用 +1)", "price": 0})
	return items


## 财富羁绊 tier3 折扣: 扫 allies 取首个 _synergyWealthShopDiscount (>0), 没有返 0.
## (PoC ShopOverlay.open: playerFighters.map(_synergyWealthShopDiscount).find(v=>v) ?? 0)
static func team_wealth_discount(allies: Array) -> float:
	for a in allies:
		if a is Dictionary:
			var d: float = float(a.get("_synergyWealthShopDiscount", 0.0))
			if d > 0.0:
				return d
	return 0.0


## 对货架套用财富折扣: 非重投格 price = max(1, round(price×(1-disc))). 原地改 items 并返回.
## (PoC ShopOverlay applyWealthDisc — 作用装备/消耗/增益价, 不动重投费 F 格)
static func apply_wealth_discount(items: Array, discount: float) -> Array:
	if discount <= 0.0:
		return items
	for it in items:
		if it is Dictionary and it.get("rarity", "") != "reroll":
			it["price"] = maxi(1, roundi(int(it.get("price", 0)) * (1.0 - discount)))
	return items


## 野生敌方 AI 购买决策 (1:1 PoC planAiShop, 纯函数无副作用; 副作用由 BattleScene 按 buys 施加).
## 贪心: 反复扫货架买得起就买; 一轮没买动且余币够重投费(首次2/每次+1, 上限3次)则重投继续.
## 返回 {buys: Array[Dictionary], spent: int, coins_left: int}; buys 是被买的格子 (不含重投/F).
static func plan_ai_shop(coins: int, shop_index: int) -> Dictionary:
	var slots: Array = []
	for s in roll(shop_index):
		if s is Dictionary and s.get("rarity", "") != "reroll":
			slots.append(s)
	var buys: Array = []
	var left: int = coins
	var spent: int = 0
	var rerolls: int = 0
	var reroll_cost: int = 2
	var progressed: bool = true
	var purchased: Dictionary = {}   # slot 字母 → true
	while progressed and left > 0:
		progressed = false
		for slot in slots:
			var key: String = slot.get("slot", "")
			if purchased.has(key):
				continue
			var price: int = int(slot.get("price", 0))
			if left < price:
				continue
			left -= price
			spent += price
			purchased[key] = true
			buys.append(slot)
			progressed = true
		if not progressed and rerolls < 3 and left >= reroll_cost:
			left -= reroll_cost
			spent += reroll_cost
			reroll_cost += 1
			rerolls += 1
			slots = []
			for s in roll(shop_index):
				if s is Dictionary and s.get("rarity", "") != "reroll":
					slots.append(s)
			purchased = {}
			progressed = true
	return {"buys": buys, "spent": spent, "coins_left": left}


static func _pick_rarity(dist: Dictionary) -> String:
	var r := randf() * 100.0
	for t in ["buff", "consumable", "normal", "unique"]:
		r -= float(dist.get(t, 0))
		if r < 0:
			return t
	return "unique"


## 应用全队 buff (PoC applyTeamBuff). allies = 同侧存活. cdDown 立即扣 cdLeft, 其余 push+recalc.
static func apply_team_buff(buff: Dictionary, allies: Array) -> void:
	var t: String = buff["type"]
	for a in allies:
		if t == "cdDown":
			for s in a.get("skills", []):
				if s is Dictionary:
					s["cdLeft"] = maxi(0, int(s.get("cdLeft", 0)) - int(buff["value"]))
			continue
		var val: int = int(buff["value"])
		if t == "atkUp":
			val = roundi(a.get("baseAtk", 0) * buff["value"] / 100.0)
		elif t == "defUp":
			val = roundi(a.get("baseDef", 0) * buff["value"] / 100.0)
			# 1:1 PoC applyTeamBuff(shop-quick.ts:168): defUp 只推单条 defUp (无额外 mrUp); 时长=tb.duration (无+1).
			#   q_shield 描述写"DEF/MR"但 PoC 只给 DEF — 保留 PoC 这一 quirk. (原 Godot 自加 mrUp + 时长+1 = 自创偏差)
		elif t == "critUp":
			(a["buffs"] as Array).append({"type": "critUp", "value": buff["value"], "duration": int(buff["duration"])})
			continue
		(a["buffs"] as Array).append({"type": t, "value": val, "duration": int(buff["duration"])})
	StatsRecalc.recalc_all(allies)


## 应用单体 buff (PoC single-buff). target = 选中的龟.
static func apply_single_buff(buff: Dictionary, target: Dictionary) -> void:
	match buff["type"]:
		"atkUp":
			(target["buffs"] as Array).append({"type": "atkUp", "value": roundi(target.get("baseAtk", 0) * buff["value"] / 100.0), "duration": int(buff["duration"]) + 1})
		"shield":
			Buffs.grant_shield(target, int(buff["value"]))
		"heal":
			target["hp"] = mini(int(target.get("maxHp", 0)), int(target.get("hp", 0)) + Buffs.fatigue_amt(target, roundi(target.get("maxHp", 0) * buff["value"] / 100.0)))   # PoC Math.round 非 ceil
		"cleanse":
			var deb := ["dot", "curse", "burn", "poison", "bleed", "chilled", "atkDown", "defDown", "mrDown", "armorBreak", "healReduce", "markedDmg", "bubbleBind", "fear", "stun"]
			var kept: Array = []
			for b in target.get("buffs", []):
				if not (b is Dictionary and b.get("type", "") in deb):
					kept.append(b)
			target["buffs"] = kept
		"markedDmg":
			(target["buffs"] as Array).append({"type": "markedDmg", "value": int(buff["value"]), "duration": int(buff["duration"]) + 1})
