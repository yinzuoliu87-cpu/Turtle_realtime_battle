class_name Synergies
extends RefCounted
# ══════════════════════════════════════════════════════════
# synergies.gd — 协同/羁绊系统 (1:1 PoC src/data/synergies.ts)
# 10 标签 × tier2(2只)/tier3(3只), 战斗开始按阵容 tags 应用.
# 纯属性效果(ATK/法穿/暴击/穿甲/闪避/护盾)立即生效;
# flag 效果(_synergy*)由各 consumer 读取 (dot/damage/_take_turn/spawn_summons).
# ══════════════════════════════════════════════════════════

const SYNERGY_TAGS := ["物理", "法术", "守护", "元素", "刺杀", "运气", "召唤", "财富", "换形", "再生"]


## 统计阵容 tags → 激活协同 [{tag, count, tier}]
static func calc_active(team: Array) -> Array:
	var counts := {}
	for f in team:
		for t in f.get("tags", []):
			counts[t] = int(counts.get(t, 0)) + 1
	var active: Array = []
	for tag in counts:
		if not SYNERGY_TAGS.has(tag):
			continue
		var n: int = counts[tag]
		if n >= 3:
			active.append({"tag": tag, "count": n, "tier": 3})
		elif n >= 2:
			active.append({"tag": tag, "count": n, "tier": 2})
	return active


## 战斗开始应用所有激活协同 (team 受益, enemies 用于登场 debuff)
static func apply_team(team: Array, enemies: Array) -> Array:
	var active := calc_active(team)
	for a in active:
		_apply(a["tag"], a["tier"], team, enemies)
	return active


static func _apply(tag: String, tier: int, team: Array, enemies: Array) -> void:
	match tag:
		"物理":
			var mult: float = 1.08 if tier == 3 else 1.04
			for f in team:
				f["baseAtk"] = roundi(f.get("baseAtk", 0) * mult); f["atk"] = f["baseAtk"]
				if tier == 3:
					f["_synergyPhysBleed"] = true
		"法术":
			var pen: int = 5 if tier == 3 else 2
			for f in team:
				f["magicPen"] = f.get("magicPen", 0) + pen
			if tier == 3:
				for e in enemies:
					e["baseMr"] = maxi(0, e.get("baseMr", 0) - 4); e["mr"] = e["baseMr"]
		"守护":
			var amp: float = 0.10 if tier == 3 else 0.05
			var sh: int = 30 if tier == 3 else 15
			for f in team:
				f["_synergyGuardAmp"] = amp; Buffs.grant_shield(f, sh)
		"元素":
			var b: float = 0.10 if tier == 3 else 0.05
			for f in team:
				f["_synergyElemDmgBoost"] = b
			if tier == 3 and team.size() > 0:
				team[0]["_synergyElemBurnTick"] = true
		"刺杀":
			var cr: float = 0.10 if tier == 3 else 0.05
			var ap: int = 3 if tier == 3 else 2
			for f in team:
				f["crit"] = f.get("crit", 0.0) + cr
				f["armorPen"] = f.get("armorPen", 0) + ap
				f["_synergyAssassinKillBonus"] = true
				if tier == 3:
					f["_synergyAssassinExecute"] = true
		"运气":
			var dv: int = 10 if tier == 3 else 5
			for f in team:
				if not f.has("buffs"):
					f["buffs"] = []
				f["buffs"].append({"type": "dodge", "value": dv, "duration": 999, "_synergyLuck": true})
			if team.size() > 0:
				team[0]["_synergyLuckGrantConsumable"] = 1
				if tier == 3:
					team[0]["_synergyLuckGrantEquip"] = 1
		"召唤":
			var hb: float = 0.15 if tier == 3 else 0.10
			var af: int = 10 if tier == 3 else 5
			for f in team:
				f["_synergySummonHpBoost"] = hb; f["_synergySummonAtkFlat"] = af
		"财富":
			for f in team:
				f["_synergyWealthCoinPerTurn"] = 4
				if tier == 3:
					f["_synergyWealthShopDiscount"] = 0.25
		"换形":
			var sp: float = 0.10 if tier == 3 else 0.05
			for f in team:
				f["_synergyShiftShieldPct"] = sp
				if tier == 3:
					f["_synergyShiftFirstAtkBonus"] = 0.08
		"再生":
			var rb: float = 0.25 if tier == 3 else 0.15
			for f in team:
				f["_synergyRegenReviveBonus"] = rb
				if tier == 3:
					f["_synergyRegenReviveAttack"] = true


## 元素羁绊 tier3: 每回合随机灼烧一名敌人 (1:1 PoC processSynergyElemBurnTick / turn.js:71-83).
## 对每一侧: 若该侧有存活的 _synergyElemBurnTick 持有者(tagger), 则随机选一名存活敌方,
## 叠 stacks = round(max(1, round(target.maxHp×0.02)) × burn_mult) 层 burn.
## 返回 [{target, tagger, stacks}] 供调用方飘字/日志 (本函数不依赖 BattleScene).
static func process_elem_burn_tick(fighters: Array, burn_mult: float = 1.0) -> Array:
	var out: Array = []
	for side in ["left", "right"]:
		var tagger = null
		for f in fighters:
			if f.get("side", "") == side and f.get("alive", false) and f.get("_synergyElemBurnTick", false):
				tagger = f
				break
		if tagger == null:
			continue
		var enemies: Array = []
		for e in fighters:
			if e.get("side", "") != side and e.get("alive", false):
				enemies.append(e)
		if enemies.is_empty():
			continue
		var target: Dictionary = enemies[randi() % enemies.size()]
		var base_stacks: int = maxi(1, roundi(target.get("maxHp", 0) * 0.02))
		var stacks: int = roundi(base_stacks * burn_mult)
		Dot.apply_stacks(target, "burn", stacks)
		out.append({"target": target, "tagger": tagger, "stacks": stacks})
	return out


## 刺杀羁绊 (tier2/3) 击杀奖励: 攻击者击杀敌方时, 整队存活成员 +5% baseAtk 永久.
## (1:1 PoC passive-triggers.ts:282-290 — 是整队不止攻击者). 入参 = 攻击者侧的存活成员列表.
## 返回是否实际加成 (供调用方决定是否飘日志).
static func apply_assassin_kill_bonus(allies: Array) -> bool:
	if allies.is_empty():
		return false
	for f in allies:
		if not f.get("alive", false):
			continue
		f["baseAtk"] = roundi(f.get("baseAtk", 0) * 1.05)
		f["atk"] = f["baseAtk"]
	return true


## 换形羁绊结算: 一只龟换形/变身/机甲完成时调用. tier2/3 给 maxHp×pct 护盾;
## tier3 首次换形额外 +baseAtk×8% 永久. 返回 {shieldAdded, atkAdded} 供飘字.
static func apply_shift(f: Dictionary) -> Dictionary:
	var shield_added: int = 0
	var atk_added: int = 0
	if f.get("_synergyShiftShieldPct", 0.0) > 0 and f.get("alive", false):
		shield_added = roundi(f.get("maxHp", 0) * f["_synergyShiftShieldPct"])
		shield_added = Buffs.grant_shield(f, shield_added)
	if f.get("_synergyShiftFirstAtkBonus", 0.0) > 0 and not f.get("_synergyShiftedOnce", false):
		f["_synergyShiftedOnce"] = true
		atk_added = roundi(f.get("baseAtk", 0) * f["_synergyShiftFirstAtkBonus"])
		f["baseAtk"] = f.get("baseAtk", 0) + atk_added; f["atk"] = f["baseAtk"]
	return {"shieldAdded": shield_added, "atkAdded": atk_added}
