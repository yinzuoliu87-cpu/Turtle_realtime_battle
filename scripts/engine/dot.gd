class_name Dot extends RefCounted

## Dot — 灼烧/中毒/流血/诅咒 层数模型 (1:1 PoC src/engine/dot.ts + BattleScene.tickDoTs)
##
## 层数模型:
##   buff.value = 层数 (无"持续 N 回合"概念)
##   buff.duration = 999 占位
##   寿命 = 每 tick 衰减: burn 1/3, poison/bleed 1/4, curse turns--
##   多次施加同类 → 累加层数
##
## Buff Dict shape: { type: "burn"/"poison"/"bleed"/"curse", value: int, duration: int }

const DOT_SENTINEL_DURATION: int = 999


## 累加 type 层数到 target (PoC dot.ts:13 applyDotStacks 1:1)
static func apply_stacks(target: Dictionary, type: String, stacks: int) -> void:
	if target == null or not target.get("alive", false) or stacks <= 0:
		return

	# burn 检免疫
	if type == "burn":
		if target.get("_burnImmune", false):
			return
		var passive = target.get("passive", null)
		if passive is Dictionary and passive.get("burnImmune", false):
			return

	# 找已有同类 buff, 累加
	var buffs: Array = target.get("buffs", [])
	if not target.has("buffs"):
		target["buffs"] = buffs
	for b in buffs:
		if b is Dictionary and b.get("type", "") == type:
			b["value"] = b.get("value", 0) + stacks
			b["duration"] = DOT_SENTINEL_DURATION
			return
	# 新建
	buffs.append({
		"type": type,
		"value": stacks,
		"duration": DOT_SENTINEL_DURATION,
	})
	target["buffs"] = buffs


## 灼烧默认层数 = max(1, round(attacker.atk × 0.67))  (PoC dot.ts:34 1:1)
static func default_burn_stacks(attacker: Dictionary) -> int:
	var atk_v: float = attacker.get("atk", 0)
	return maxi(1, roundi(atk_v * 0.67))


## 给 fighter 跑一次 DoT tick (回合末调用), 返 effects 数组让 BattleScene 飘字
## PoC BattleScene.tickDoTs:8078 1:1
##   burn:   dmg = value + maxHp × 0.001 × value,  decay 1/3,  dmg_type=magic, cls=dot-dmg
##   poison: dmg = value,                          decay 1/4,  dmg_type=magic, cls=dot-poison
##   bleed:  dmg = value,                          decay 1/4,  dmg_type=physical, cls=dot-bleed
##   curse:  dmg = value,                          duration-1, dmg_type=true, cls=dot-curse
##
## tick 后:
##   层数衰减 (value 乘 (1 - decay), round, max 0)
##   value <= 0 → 移除 buff
##
## 返回:
##   Array of {kind:"damage", value:int, dmg_type:String, cls:String, source:"dot"}
static func tick(fighter: Dictionary, elem_boost: float = 0.0) -> Array:
	var effects: Array = []
	if not fighter.get("alive", false):
		return effects
	var buffs: Array = fighter.get("buffs", [])
	if buffs.is_empty():
		return effects

	var max_hp_v: float = fighter.get("maxHp", 0)
	var to_remove: Array = []

	# 多 DoT 固定结算顺序: 点燃 → 中毒 → 流血 → 诅咒 (同目标多条 DoT 不再按 buff 数组的随机
	#   append 顺序乱序出伤; BattleScene 据此顺序逐条错开飘字)。非 DoT buff 不在此列, 跳过。
	var dot_order: Array = ["burn", "poison", "bleed", "curse"]
	var ordered: Array = []
	for _t in dot_order:
		for b in buffs:
			if b is Dictionary and b.get("type", "") == _t:
				ordered.append(b)

	for b in ordered:
		if not (b is Dictionary):
			continue
		var btype: String = b.get("type", "")
		var bval: int = b.get("value", 0)
		var dmg: int = 0
		var decay_rate: float = 0.0
		var dmg_type: String = "magic"
		var cls: String = "dot-dmg"

		match btype:
			"burn":
				dmg = bval + roundi(max_hp_v * bval * 0.001)
				decay_rate = 1.0 / 3.0
				dmg_type = "magic"
				cls = "dot-dmg"
				# 022余烬燃油瓶「真火」: 持有 trueFire 状态时, 灼烧伤害转真实 — 飘字色(cls)与统计(dmg_type)
				#   都跟真实类型走 (原只切 dmg_type, cls 仍 dot-dmg 魔蓝 → 真火显蓝/算魔法是错的, 现一并切真白).
				for _tf in fighter.get("buffs", []):
					if _tf is Dictionary and _tf.get("type", "") == "trueFire":
						dmg_type = "true"
						cls = "dot-curse"   # 真伤白 (≠ dot-dmg 魔蓝); 与 dmg_type=true 一致
						break
			"poison":
				dmg = bval
				decay_rate = 1.0 / 4.0
				dmg_type = "magic"
				cls = "dot-poison"
			"bleed":
				dmg = bval
				decay_rate = 1.0 / 4.0
				dmg_type = "physical"
				cls = "dot-bleed"
			"curse":
				dmg = bval
				decay_rate = 0.0    # curse 走 turns--
				dmg_type = "true"
				cls = "dot-curse"
			_:
				continue

		# 元素羁绊: DoT 整体 ×(1+boost) (PoC tickDoTs P65, boost=对面队伍最大 _synergyElemDmgBoost)
		if elem_boost > 0.0 and dmg > 0:
			dmg = maxi(1, roundi(dmg * (1.0 + elem_boost)))

		if dmg > 0:
			# 用 Damage.apply_raw_damage 落伤害 (走护盾 + 减伤)
			var r: Dictionary = Damage.apply_raw_damage(fighter, dmg, dmg_type)
			var shown: int = r["hpLoss"] + r["shieldAbs"]
			if shown > 0:
				effects.append({
					"kind": "damage",
					"value": shown,
					"dmg_type": dmg_type,
					"cls": cls,
					"source": "dot",
					"is_crit": false,
					"_src": b.get("_src", null),   # DoT 施加者 (供 battleStats 归功; 可能为 null)
				})

		# 衰减
		if decay_rate > 0:
			var new_val: int = floori(bval * (1.0 - decay_rate))  # PoC tickDoTs:8138 用 Math.floor 非 round
			b["value"] = maxi(0, new_val)
			if b["value"] <= 0:
				to_remove.append(b)
		# curse decayRate=0: tick 不动 curse value/duration; turns-- 由 StatsRecalc.tick_buffs_duration 统一管
		# (PoC tickDoTs:8144-8147 filter 对 curse 返 true, 永不在 tick 里衰减/移除 — 自减会与 buff 系统双减)

	# 移除归 0 的 DoT
	for b in to_remove:
		buffs.erase(b)

	return effects
