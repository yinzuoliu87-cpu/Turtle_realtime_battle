class_name StatsRecalc extends RefCounted

## StatsRecalc — Fighter atk/def/mr/crit/armorPen/lifesteal 基于 buffs 重算
## 1:1 移植 PoC src/engine/stats-recalc.ts (JS turn.js:1008-1060 recalcStats)
##
## 调用时机:
##   - 每回合开始 (所有 fighter)
##   - 每次 add_buff 后 (该 fighter)
##   - buff push 后需立即生效的技能 (basicChiWave/iceFrost) push 完手动调
##
## 字段约定 (PoC 同款, Fighter Dictionary):
##   base: baseAtk/baseDef/baseMr (不变, 装备/羁绊永久加成改这个)
##   live: atk/def/mr (= base + buffs, recalc 每次从 base 重算)
##   snapshot: _baseCrit/_baseArmorPen/_baseLifesteal (recalc 走这些 base + buff 加成)
##   装备: _equipHammer (ATK += 4%maxHp×count)
##   输出: _buffCritDmg (calc_crit_mult 读), lifestealPct (on-hit 吸血读)


## 重算单个 fighter。allies 传同侧友军 (含自己), 用于 diamondStructure defAmp 跨队检测。
static func recalc(f: Dictionary, allies: Array = []) -> void:
	# 重置到 base
	f["atk"] = f.get("baseAtk", 0)
	f["def"] = f.get("baseDef", 0)
	f["mr"] = f.get("baseMr", f.get("baseDef", 0))

	# diamondStructure: 放大全队 def/mr buff (W7 暂无 diamond passive, 保留逻辑)
	var def_amp: float = 1.0
	if not allies.is_empty():
		for t in allies:
			var passive = t.get("passive", null)
			if t.get("alive", false) and passive is Dictionary and passive.get("type", "") == "diamondStructure":
				var is_self: bool = (t == f)
				var amp_pct: float
				if is_self and t.get("_diamondEnhanced", false):
					amp_pct = 100.0
				else:
					amp_pct = passive.get("defBuffAmp", 50)
				def_amp = 1.0 + amp_pct / 100.0
				break

	var buffs: Array = f.get("buffs", [])

	# chilled: ATK -20% (只检 type 存在, 不读 value)
	for b in buffs:
		if b is Dictionary and b.get("type", "") == "chilled":
			f["atk"] = roundi(f["atk"] * 0.8)
			break

	var crit_add: float = 0.0
	var armor_pen_add: int = 0
	var lifesteal_add: float = 0.0
	var crit_dmg_add: float = 0.0

	for b in buffs:
		if not (b is Dictionary):
			continue
		var btype: String = b.get("type", "")
		var bval: float = b.get("value", 0)
		match btype:
			# 百分比减 (乘)
			"atkDown":
				f["atk"] = roundi(f["atk"] * (1.0 - bval / 100.0))
			"defDown", "armorBreak":
				f["def"] = roundi(f["def"] * (1.0 - bval / 100.0))
			"mrDown":
				f["mr"] = roundi(f["mr"] * (1.0 - bval / 100.0))
			# 绝对值加 (flat); defUp/mrUp 受 defAmp
			"defUp":
				f["def"] = f["def"] + roundi(bval * def_amp)
			"mrUp":
				f["mr"] = f["mr"] + roundi(bval * def_amp)
			"atkUp":
				f["atk"] = f["atk"] + roundi(bval)
			# 暴击加成 (小数)
			"diceFateCrit", "critUp":
				crit_add += bval / 100.0
			"critDmgUp":
				crit_dmg_add += bval / 100.0
			"armorPen":
				armor_pen_add += roundi(bval)
			"lifesteal":
				lifesteal_add += bval / 100.0
			# 龟派气波: 单 buff 含 4 项加成 (extras 里带 critGain/critDmgGain/lifestealGain/armorPenDelta)
			"chiWaveActive":
				crit_add += float(b.get("critGain", 0)) / 100.0
				crit_dmg_add += float(b.get("critDmgGain", 0)) / 100.0
				lifesteal_add += float(b.get("lifestealGain", 0)) / 100.0
				armor_pen_add += int(b.get("armorPenDelta", 0))

	# 重击锤 e_hammer: ATK += 4% maxHp × 件数 (flat, 与 buff 正确叠加)
	var hammer_count: int = f.get("_equipHammer", 0)
	if hammer_count > 0:
		f["atk"] = f["atk"] + roundi(f.get("maxHp", 0) * 0.04 * hammer_count)
	# 二阶段重击锤 p2eq_047: ATK += maxHp × _p2HammerAtkPct (随 maxHp 成长动态, 同 e_hammer 口径)
	var p2_hammer_pct: float = f.get("_p2HammerAtkPct", 0.0)
	if p2_hammer_pct > 0.0:
		f["atk"] = f["atk"] + roundi(f.get("maxHp", 0) * p2_hammer_pct)

	# 血牙帮[血祭]学派: 按已损失生命 +ATK (每损 1% 最大生命 +_bloodFangFactor). 动态随当前HP, 同重击锤口径。
	var blood_fang: float = f.get("_bloodFangFactor", 0.0)
	if blood_fang > 0.0:
		var lost_pct: float = (1.0 - float(f.get("hp", 0)) / maxf(1.0, float(f.get("maxHp", 1)))) * 100.0
		f["atk"] = f["atk"] + roundi(maxf(0.0, lost_pct) * blood_fang)

	# 遗物[古物]类型羁绊: 生命 >50% 时额外 +_relicHealthAtkPct × atk (健康时强化进攻). 动态随当前HP。
	var relic_atk_pct: float = f.get("_relicHealthAtkPct", 0.0)
	if relic_atk_pct > 0.0 and float(f.get("hp", 0)) > float(f.get("maxHp", 1)) * 0.5:
		f["atk"] = f["atk"] + roundi(float(f["atk"]) * relic_atk_pct)

	# 极地小队 6档僵硬: 每层 -2% 攻 (max 20 层 = -40%; 被极地队攻击叠加, 见 _on_hit_chain)
	var stiff: int = mini(20, int(f.get("_stiffnessStacks", 0)))
	if stiff > 0:
		f["atk"] = roundi(f["atk"] * (1.0 - stiff * 0.02))

	f["atk"] = maxi(0, f["atk"])
	f["def"] = maxi(0, f["def"])
	f["mr"] = maxi(0, f["mr"])

	# crit: base + buff 加成
	var base_crit: float = f.get("_baseCrit", f.get("crit", 0.0))
	f["crit"] = maxf(0.0, base_crit + crit_add)

	# armorPen: base + buff
	var base_ap: int = f.get("_baseArmorPen", f.get("armorPen", 0))
	f["armorPen"] = base_ap + armor_pen_add
	f["_buffArmorPen"] = armor_pen_add

	# lifesteal: base + buff + 永久/装备类 _lifestealPct (百分点 ÷100)
	var base_ls: float = f.get("_baseLifesteal", 0.0)
	var equip_ls: float = float(f.get("_lifestealPct", 0)) / 100.0
	f["lifestealPct"] = base_ls + lifesteal_add + equip_ls

	# critDmg: chiWaveActive 爆伤加成存 _buffCritDmg, calc_crit_mult 读
	f["_buffCritDmg"] = crit_dmg_add
	f["_statsDirty"] = false


## snapshot 当前 crit/armorPen/lifesteal 为 base (recalc 之后走 base + buffs)
## 战斗开始建完 fighter + 装备 apply 后调一次。
static func snapshot_base(f: Dictionary) -> void:
	f["_baseCrit"] = f.get("crit", 0.0)
	# _baseLifesteal 排除 _lifestealPct 折入部分 (recalc 会再加一遍), 防双计
	var cur_ls: float = f.get("lifestealPct", 0.0)
	var equip_ls: float = float(f.get("_lifestealPct", 0)) / 100.0
	f["_baseLifesteal"] = cur_ls - equip_ls
	f["_baseArmorPen"] = f.get("armorPen", 0)


## 给所有 fighter 重算 (传同侧友军给 recalc 用于 diamond defAmp)
static func recalc_all(fighters: Array) -> void:
	for f in fighters:
		var allies: Array = []
		for x in fighters:
			if x.get("side", "") == f.get("side", ""):
				allies.append(x)
		recalc(f, allies)


## 回合末: 所有 buff duration--, 移除到期的。DoT 层数 buff (duration 999) 跳过。
## 返 expired 数组让 caller 飘"buff 到期"。
static func tick_buffs_duration(f: Dictionary) -> Array:
	var expired: Array = []
	var buffs: Array = f.get("buffs", [])
	for b in buffs:
		if not (b is Dictionary):
			continue
		var dur: int = b.get("duration", 0)
		# DoT 层数模型 (999 哨兵) 不走 duration 衰减, 由 Dot.tick 处理
		if dur >= 999:
			continue
		b["duration"] = dur - 1
		if b["duration"] <= 0:
			expired.append(b)
	for b in expired:
		buffs.erase(b)
	return expired
