class_name EqWaveAmulet
extends RefCounted
## 043 海浪护符(四费)的【双抗增减 · 一场对局内跨路保留】(2026-11-14)。
## 用户原话:「现在这个海浪护符…施加的这个护甲和减免的护甲，需要是在一个对局里面的生效，也就是说上路你给队友加的护甲，
##   那么终极战场，那么这个队友还是有这个护甲加成，就是相当于跨路保留，但是一场对局之后就重置」。
## 浪墙本体(护盾 / 魔伤 / 击飞 / 演出)仍在 equip_system.gd `_eq_water_wave`; 本文件只管双抗那一笔怎么记、怎么带过路。
##
## ★为什么要单独记账: 换路时单位字典整个重建(dual_lane_flow `_dl_clear_units` → `_make_unit`),
##   写在单位上的 base_def / base_mr 改动换路就没了(食物成长文件头那段探针结论同理)。
##   ⇒ 把【实际】增减量记在本对象上(本对象随战斗场景活过换路), 每一路建场后 `restore()` 补回去。
## ★键 = 阵营|龟id|同名序号, 直接用 `dual_lane_flow._eq_carry_key`(竹弓 / 哑铃 / 温泉蛋跨路同一口径, 不另抄一份)。
## ★记【实际】增减而不是「打了几下 × 每下几点」: 敌人减到 0 就不再往下减(原规则), 只有记实际量补回去才和上一路结束时一样。
## ★召唤物不记: 每一路重新召唤, 新召唤出来的不该带上一路那一只吃到的双抗。
## ★整场结束清空: `EquipTickSystem.reset_match()`(与 035 齿轮本场铸币同一个「整场结束」钩子)。

var battle
## 键 → [累计实际护甲增减, 累计实际魔抗增减]
var _carry: Dictionary = {}


func _init(b) -> void:
	battle = b


## 浪墙打到一只单位: 双抗各 += d(友军为正、敌人为负; 不低于 0), 并把实际增减量记进跨路账。
func add_resist(o: Dictionary, d: float) -> void:
	var d0: float = float(o["base_def"])
	var m0: float = float(o["base_mr"])
	o["base_def"] = maxf(0.0, d0 + d)
	o["base_mr"] = maxf(0.0, m0 + d)
	battle._recalc_stats(o)
	var k: String = str(o.get("_wave_key", ""))
	if k == "":
		return
	var rec: Array = _carry.get(k, [0.0, 0.0])
	_carry[k] = [float(rec[0]) + float(o["base_def"]) - d0, float(rec[1]) + float(o["base_mr"]) - m0]


## 每一路建场、装备管线跑完之后调(dual_lane_flow `_dl_build_lane_field` 末尾): 贴身份键 + 补回前面几路攒下的双抗增减。
func restore() -> void:
	var seen: Dictionary = {}
	for u in battle._units:
		if not (u is Dictionary) or u.get("_isEgg", false) or u.get("is_trainer", false) or u.get("is_summon", false):
			continue
		var k: String = battle._dl_sys._eq_carry_key(u, seen)
		u["_wave_key"] = k
		var rec = _carry.get(k, null)
		if not (rec is Array):
			continue
		u["base_def"] = maxf(0.0, float(u["base_def"]) + float(rec[0]))
		u["base_mr"] = maxf(0.0, float(u["base_mr"]) + float(rec[1]))
		battle._recalc_stats(u)


## 整场结束(不是换路): 清空, 下一场从零开始。
func reset_match() -> void:
	_carry.clear()
