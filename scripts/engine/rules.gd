class_name Rules
extends RefCounted
# ══════════════════════════════════════════════════════════
# rules.gd — 7 战斗规则系统 (1:1 PoC src/engine/rule-effects.ts + src/data/rules.ts)
# 规则名对齐 data/battle-rules.json (DataRegistry.battle_rules, 7 项, 无自创 '深海之日'):
#   烈焰之日(fire) / 雷暴之日(thunder) / 铁壁之日(shield) / 狂暴之日(rage)
#   / 装备之日(equip) / 下雨天(rain) / 正常对局(normal)
# 风格同 synergies.gd: 全 static, fighter 是 Dictionary 用 .get("key", default).
# ══════════════════════════════════════════════════════════

# 全局当前规则 (供 skill_handlers 等读取) — 对齐 PoC rule-effects.ts:13 export let currentRule
static var current_rule: String = ""


## 设置当前规则 (PoC rule-effects.ts:14 setCurrentRule)
static func set_current_rule(rule: String) -> void:
	current_rule = rule


# ── ruleModifiers 等价 (PoC rule-effects.ts:20-31) ────────────
# 给 skill_handlers / equipment 使用. 默认读 static current_rule;
# 也可显式传 rule (留空 "" = 用 current_rule).

## 魔法伤害倍率 — PoC:22 BATTLE_RULES 不修改 magic dmg (烈焰只附带 burn DoT, 雷暴只 +20% crit) → 恒 1.0
static func magic_mult(rule: String = "") -> float:
	return 1.0


## 灼烧 buff 值倍率 (烈焰之日 ×1.5) — PoC rule-effects.ts:24
static func burn_mult(rule: String = "") -> float:
	var r := rule if rule != "" else current_rule
	return 1.5 if r == "烈焰之日" else 1.0


## 护盾值倍率 (铁壁之日 ×1.3) — PoC rule-effects.ts:26
static func shield_mult(rule: String = "") -> float:
	var r := rule if rule != "" else current_rule
	return 1.3 if r == "铁壁之日" else 1.0


## 受治疗倍率 (铁壁之日 +30%, 与护盾同口径) — PoC rule-effects.ts:28
static func heal_mult(rule: String = "") -> float:
	var r := rule if rule != "" else current_rule
	return 1.3 if r == "铁壁之日" else 1.0


## 全体暴击加成 (雷暴之日 +20%) — PoC rule-effects.ts:30
static func global_crit_bonus(rule: String = "") -> float:
	var r := rule if rule != "" else current_rule
	return 0.20 if r == "雷暴之日" else 0.0


# ── applyRuleStart (PoC rule-effects.ts:34-62) ────────────────

## 战斗开始时应用一次性规则 (狂暴 stat / 装备日发装 / 雷暴 crit).
## left_team / right_team 为 Fighter Dictionary 数组.
static func apply_rule_start(rule: String, left_team: Array, right_team: Array) -> void:
	set_current_rule(rule)
	if rule == "" or rule == "正常对局":
		return

	# 狂暴之日: 全体 +20% atk, -15% def/mr (PoC rule-effects.ts:38-47)
	if rule == "狂暴之日":
		for f in _both(left_team, right_team):
			f["baseAtk"] = roundi(f.get("baseAtk", 0) * 1.2)
			f["atk"] = f["baseAtk"]
			f["baseDef"] = roundi(f.get("baseDef", 0) * 0.85)
			f["def"] = f["baseDef"]
			f["baseMr"] = roundi(f.get("baseMr", f.get("def", 0)) * 0.85)
			f["mr"] = f["baseMr"]

	# 装备之日: 开局每队选 1 件非消耗/非宝箱装备起步 (PoC rule-effects.ts:48-56)
	if rule == "装备之日":
		var eligible: Array = []
		for e in DataRegistry.all_equipment:
			var cat: String = e.get("category", "")
			if cat != "consumable" and cat != "chest":
				eligible.append(e)
		for team in [left_team, right_team]:
			var target = _first_alive(team)
			if target != null and eligible.size() > 0:
				var eq = eligible[randi() % eligible.size()]
				EquipmentRuntime.on_attach(target, eq.get("id", ""))

	# 雷暴之日: 全体 +20% 暴击 (PoC rule-effects.ts:57-61)
	if rule == "雷暴之日":
		var bonus := global_crit_bonus(rule)
		for f in _both(left_team, right_team):
			f["crit"] = f.get("crit", 0.0) + bonus


# ── applyRulePerTurn (PoC rule-effects.ts:67-85) ──────────────

## 每回合开始执行 (JS turn.js:48-70 对齐).
## 下雨天: 对所有存活单位 5×N 魔法伤害 + 永久 -N 甲/抗 (N = 当前回合数).
## 受击单位写 _rainDmg (hpLoss + shieldAbs) 供 BattleScene 飘字/死亡检查.
static func apply_rule_per_turn(rule: String, all_fighters: Array, turn_num: int = 1) -> void:
	if rule == "":
		return
	if rule == "下雨天":
		var n := turn_num
		var dmg := 5 * n
		for f in all_fighters:
			if not f.get("alive", false):
				continue
			# 永久 -N 甲/抗 (PoC rule-effects.ts:75-77)
			f["baseDef"] = maxi(0, f.get("baseDef", 0) - n)
			f["baseMr"] = maxi(0, f.get("baseMr", f.get("baseDef", 0)) - n)
			f["def"] = f["baseDef"]
			f["mr"] = f["baseMr"]
			# 5×N 魔法 (mr 减免, 无穿透) — PoC rule-effects.ts:78-82
			var atk_copy: Dictionary = f.duplicate()
			atk_copy["magicPen"] = 0
			atk_copy["magicPenPct"] = 0
			var eff := Damage.calc_eff_mr(atk_copy, f)
			var final_dmg := maxi(1, roundi(dmg * Damage.calc_dmg_mult(eff)))
			var r := Damage.apply_raw_damage(f, final_dmg, "magic", false)
			f["_rainDmg"] = int(r.get("hpLoss", 0)) + int(r.get("shieldAbs", 0))


# ── helpers ───────────────────────────────────────────────────

static func _both(left_team: Array, right_team: Array) -> Array:
	var out: Array = []
	out.append_array(left_team)
	out.append_array(right_team)
	return out


static func _first_alive(team: Array):
	for f in team:
		if f.get("alive", false):
			return f
	return null
