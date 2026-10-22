extends RefCounted
## 阵容里一只单位的六项基础属性(生命值 / 攻击力 / 护甲 / 魔抗 / 暴击率 / 暴击伤害) —— 背包点龟卡弹的属性小卡用。
## (用户 2026-10-22「点击龟得有龟的属性显示吧，基本的就好，生命值，攻击力，护甲魔抗，暴击和暴击伤害」
##  「因为是被装备施加了属性的」⇒ 数值含身上装备, 装备加的那部分单独返回、小卡上另标。)
##
## 与战斗同一套取法, 不另抄一份:
##   统领 = pets 数据(缺省值照搬 battle_spawn._make_unit) × UnitScaling.level_multiplier(开战等级)
##   小将 = MinionCodex.base_stats(精英?, 前排?, 等级)  —— _make_unit 也读它
##   装备 = EquipStats.STATS 逐星属性, 在等级缩放之后平加 —— 同 equip_stats_apply.apply_stat_dict
## 不含: 羁绊、被动(如忍术的暴击)、开局触发的效果 —— 那些是战斗里的事。
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")

const KEYS := ["hp", "atk", "def", "mr", "crit", "critDmg"]
const BASE_CRIT_DMG := 1.5   # = _make_unit 的 "crit_dmg": 1.5


## 返回 {"base": {六键}, "equip": {六键}}; crit / critDmg 是小数(0.25 = 25%, 1.5 = 150%)。
static func leader(pid: String, level: int, equips: Array) -> Dictionary:
	var d: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	var m: float = UnitScaling.level_multiplier(level) if level > 1 else 1.0
	var base := {
		"hp": float(d.get("hp", 1350)) * m, "atk": float(d.get("atk", 40)) * m,
		"def": float(d.get("def", 12)) * m, "mr": float(d.get("mr", 12)) * m,
		"crit": float(d.get("crit", 0.25)), "critDmg": BASE_CRIT_DMG,
	}
	return {"base": base, "equip": equip_sum(equips)}


static func minion(elite: bool, front: bool, level: int, equips: Array) -> Dictionary:
	var d: Dictionary = MinionCodex.base_stats(elite, front, level)
	var base := {
		"hp": float(d["hp"]), "atk": float(d["atk"]), "def": float(d["def"]), "mr": float(d["mr"]),
		"crit": float(d["crit"]), "critDmg": BASE_CRIT_DMG,
	}
	return {"base": base, "equip": equip_sum(equips)}


## 身上每件装备按星级把六项加起来(只认这六项; 穿透 / 生命偷取等不在这张小卡上)。
static func equip_sum(equips: Array) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = 0.0
	for e in equips:
		if not (e is Dictionary):
			continue
		var arr: Array = EquipStats.STATS.get(str((e as Dictionary).get("id", "")), [])
		var i: int = clampi(int((e as Dictionary).get("star", 1)), 1, 3) - 1
		if i >= arr.size():
			continue
		var st: Dictionary = arr[i]
		for k in KEYS:
			if st.has(k):
				out[k] = float(out[k]) + float(st[k])
	return out
