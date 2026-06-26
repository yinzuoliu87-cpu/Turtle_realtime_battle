class_name FighterFactory extends RefCounted

## FighterFactory — 从 pet 数据 + 等级 → 运行时 Fighter Dictionary
## (从 Phaser PoC src/engine/fighter.ts 翻译)
##
## 用法:
##   var basic = FighterFactory.create("basic", "left")          # Lv1 默认
##   var v3 = FighterFactory.create("ghost", "right", {"level": 3})
##   var with_eq = FighterFactory.create("phoenix", "left", {"level": 5, "equipped_idxs": [0,1,2]})
##
## Fighter 用 Dictionary 表达 (不用 Custom Resource, 跟 JSON 数据结构同, 易序列化):
##   {
##     id, name, emoji, rarity, side, img, _level,
##     maxHp, hp, shield,
##     baseAtk, baseDef, baseMr, atk, def, mr,
##     crit, armorPen/Pct, magicPen/Pct,
##     passive (Dict or null), skills (Array[Dict]), _passiveSkills (Array[Dict]),
##     alive, buffs (Array), tags (Array), equipment (Array),
##     _position, _statsDirty,
##   }
##
## 不挂载装备的 apply() 逻辑 — 装备的 apply 是 W6-W8 才翻译的内容。


## 等级缩放: Lv1=1.0, Lv10=1.45 (跟 JS fighter.js getLevelMult 1:1)
static func get_level_mult(level: int) -> float:
	return 1.0 + (level - 1) * 0.05


## 技能解锁等级 (1:1 PoC pet-level.ts:32): idx3 需 Lv4, idx4 需 Lv7, 其余 Lv1
static func skill_unlock_level(skill_idx: int) -> int:
	if skill_idx == 3:
		return 4
	if skill_idx == 4:
		return 7
	return 1


## 按等级返回可用技能 idx (1:1 PoC getAvailableSkillIndices, pet-level.ts:40): idx0/1/2 始终; 3 需 lv≥4; 4 需 lv≥7
static func available_skill_indices(pool_len: int, lv: int) -> Array:
	var out: Array = []
	for i in range(pool_len):
		if i <= 2:
			out.append(i)
		elif i == 3 and lv >= 4:
			out.append(i)
		elif i == 4 and lv >= 7:
			out.append(i)
	return out


## AI 抽 3 技能 (1:1 PoC aiPickSkills, pet-level.ts:60-89): 必含 idx0(基础) + 1 active伤害技 +
##   凑满3(30%概率含1被动); 互斥对 fortuneGainCoins↔fortuneBuyEquip; 池≤3 返 null(调用方用 defaultSkills)。
const _AI_SKILL_EXCLUSIVE_PAIRS := [["fortuneGainCoins", "fortuneBuyEquip"]]
static func ai_pick_skills(pool: Array, lv: int):
	if pool == null or pool.size() <= 3:
		return null
	var unlocked: Array = available_skill_indices(pool.size(), lv)
	var indices: Array = [0]   # 必含基础技
	var available: Array = []
	for i in unlocked:
		if i != 0:
			available.append(i)
	var actives: Array = []
	var passives: Array = []
	for i in available:
		if bool(pool[i].get("passiveSkill", false)):
			passives.append(i)
		else:
			actives.append(i)
	# 1 active 伤害技 (非 isAlly, 非 heal/shield)
	var dmg_idxs: Array = []
	for i in actives:
		var t: String = str(pool[i].get("type", ""))
		if not bool(pool[i].get("isAlly", false)) and t != "heal" and t != "shield":
			dmg_idxs.append(i)
	if dmg_idxs.size() > 0:
		indices.append(dmg_idxs[randi() % dmg_idxs.size()])
	# 凑满 3 (30% 被动 + 互斥对)
	while indices.size() < 3:
		var has_passive := false
		for i in indices:
			if bool(pool[i].get("passiveSkill", false)):
				has_passive = true
		var use_passive: bool = passives.size() > 0 and randf() < 0.3 and not has_passive
		var src: Array = passives if use_passive else actives
		var pick_from: Array = _ai_filter_pickable(pool, indices, src)
		if pick_from.is_empty():
			pick_from = _ai_filter_pickable(pool, indices, available)   # fallback: 任意未选可用
		if pick_from.is_empty():
			break
		indices.append(pick_from[randi() % pick_from.size()])
	indices.sort()
	return indices


static func _ai_filter_pickable(pool: Array, indices: Array, src: Array) -> Array:
	var out: Array = []
	for i in src:
		if not indices.has(i) and not _ai_mutex_blocked(pool, indices, i):
			out.append(i)
	return out


static func _ai_mutex_blocked(pool: Array, indices: Array, idx: int) -> bool:
	for pair in _AI_SKILL_EXCLUSIVE_PAIRS:
		if pair.has(str(pool[idx].get("type", ""))):
			for i in indices:
				if i != idx and pair.has(str(pool[i].get("type", ""))):
					return true
	return false


## 创建 fighter
##   pet_id: pets.json 里的 id (e.g. "basic", "phoenix")
##   side:   "left" / "right"
##   opts:   {"level": int=1, "equipped_idxs": Array[int]=null, "equipment": Array[Dict]=[]}
static func create(pet_id: String, side: String, opts: Dictionary = {}) -> Dictionary:
	var pet: Dictionary = DataRegistry.pet_by_id.get(pet_id, {})
	if pet.is_empty():
		push_error("[FighterFactory] unknown pet id: " + pet_id)
		return {}

	var lv: int = opts.get("level", 1)
	var lv_mult := get_level_mult(lv)
	var rarity_str: String = pet.get("rarity", "C")
	var rarity_mult: float = DataRegistry.rarity_mult.get(rarity_str, 1.0)
	var m := lv_mult * rarity_mult

	# 4.6 类型推断: Dictionary.get() 返回 Variant, 先显式 float 化再 roundi 推 int。
	var hp_base: float = pet.get("hp", 0)
	var atk_base: float = pet.get("atk", 0)
	var def_base: float = pet.get("def", 0)
	var mr_base: float = pet.get("mr", pet.get("def", 0))
	# [补丁] 双路所有乌龟 1 级基础血量翻倍 (=各等级按比例 ×2, 因 m 含 lv_mult).
	#   只翻经 FighterFactory.create 建的乌龟 (玩家+AI 统领); 龟蛋/触手/小将/水晶球/熊/中立
	#   各走独立 plain-dict 构造器, 不经此处. 召唤物虽经此处但其 maxHp 在 spawn 后被 hpPct 覆盖.
	#   翻在源头基础血 (recalc 不动 maxHp, 装备只 += flat) → survive recalc.
	var max_hp := roundi(hp_base * m) * 2
	var atk := roundi(atk_base * m)
	var def_ := roundi(def_base * m)
	var mr := roundi(mr_base * m)

	# 选技能: equipped_idxs 默认 pet.defaultSkills 或 [0,1,2]
	var equipped_idxs: Array = opts.get("equipped_idxs", pet.get("defaultSkills", [0, 1, 2]))
	var pool: Array = pet.get("skillPool", [])
	var skills: Array[Dictionary] = []
	var passive_skills: Array[Dictionary] = []
	for i in equipped_idxs:
		if i < 0 or i >= pool.size():
			continue
		var s: Dictionary = pool[i]
		var s_copy := s.duplicate(true)
		if s.get("passiveSkill", false):
			passive_skills.append(s_copy)
		else:
			s_copy["cdLeft"] = 0
			skills.append(s_copy)

	var passive_raw = pet.get("passive", null)
	var passive_obj = (passive_raw.duplicate(true) if passive_raw is Dictionary else null)

	var f := {
		"id": pet.get("id", ""),
		"name": pet.get("name", ""),
		"emoji": pet.get("emoji", ""),
		"rarity": rarity_str,
		"side": side,
		"img": pet.get("img", ""),
		"sprite": pet.get("sprite", null),

		"_level": lv,
		# 龟能 (=蓝量): 不随等级/稀有变. maxEnergy 0 = 无龟能宠物(技能全免费). 开局=initEnergy.
		"_maxEnergy": int(pet.get("maxEnergy", 0)),
		"_energy": clampi(int(pet.get("initEnergy", 0)), 0, int(pet.get("maxEnergy", 0))),
		"_equippedIdxs": equipped_idxs,
		"_meleeSkills": pet.get("meleeSkills", []),  # 双头龟换形用 (近战形态技能池, 见 twoHeadSwitch)
		"_volcanoSkills": pet.get("volcanoSkills", []),  # 熔岩龟变身用 (火山形态技能池, 见 processLavaRage)

		"maxHp": max_hp,
		"hp": max_hp,
		"shield": 0,
		"baseAtk": atk, "baseDef": def_, "baseMr": mr,
		"atk": atk, "def": def_, "mr": mr,
		"crit": pet.get("crit", 0.08),
		"armorPen": 0, "armorPenPct": 0.0,
		"magicPen": 0, "magicPenPct": 0.0,

		"passive": passive_obj,
		"passiveUsedThisTurn": false,
		"skills": skills,
		"_passiveSkills": passive_skills,

		"alive": true,
		"buffs": [],
		"tags": (pet.get("tags", []) as Array).duplicate(),
		"_position": "front",
		"_slotKey": "front-0",  # 默认前排首槽; BattleScene 布阵时按真实站位覆盖 (PoC slot system)
		"_statsDirty": true,
		"equipment": [],
	}

	# 磐石之躯门控: 仅装备 rockShockwave 技能时, 受击叠岩层。
	f["_hasRockArmor"] = skills.any(func(s): return s.get("type", "") == "rockShockwave")
	f["_rockLayers"] = 0

	# W3 简版: 不挂装备。W6-W8 等装备 apply() 翻译完再启用。
	# var eq_list: Array = opts.get("equipment", [])
	# for eq in eq_list: attach_equipment(f, eq)

	return f


## 拷贝 init 快照 (UI 显示 stat-up/down 用)
static func snapshot_init_stats(f: Dictionary) -> void:
	f["_initHp"] = f.get("maxHp", 0)
	f["_initAtk"] = f.get("atk", 0)
	f["_initDef"] = f.get("def", 0)
	f["_initMr"] = f.get("mr", 0)
	f["_initCrit"] = f.get("crit", 0.0)
	f["_initArmorPen"] = f.get("armorPen", 0)
	f["_initMagicPen"] = f.get("magicPen", 0)
	f["_initLifesteal"] = f.get("_lifestealPct", 0)
