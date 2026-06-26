class_name AchievementTracker
extends RefCounted
# ══════════════════════════════════════════════════════════
# achievement_tracker.gd — 解锁追踪 + 累计存档 + 检查解锁
#   1:1 PoC src/systems/achievement-tracker.ts
#
# ── 持久化方案 (与 PoC 不同点) ────────────────────────────────────────────
# PoC 用 localStorage 两个 key (LS_UNLOCKED / LS_STATS) + 一个进程内单例对象。
# Godot 把存储落到 GameState 存档:
#   解锁 id → GameState.achievements_unlocked (Array, 已存在已存盘)
#   累计统计 → GameState.ach_stats (Dictionary, 本批新增, 加入 save/load)
# 所以本类是 *无状态静态类* (RefCounted + 全 static), 真状态在 GameState (= PoC 单例的存档替身)。
# 每次写完即 GameState.save() (= PoC saveStats/saveUnlocked 落 localStorage)。
#
# ── AchStats 字段 (1:1 PoC achievement-tracker.ts:9-20) ────────────────────
#   battles/wins/crits/totalDmg/totalEquipsBought/totalCoinsEarned : int
#   petsUsed/rulesSeen : Dictionary {id→true} (模拟 PoC Record<string,true> / Set)
#   bestDungeon : int
# ══════════════════════════════════════════════════════════


## 取/初始化 AchStats (1:1 PoC loadStats() 默认值, ts:27-31). 直接返回 GameState.ach_stats 引用。
static func _stats() -> Dictionary:
	var s: Dictionary = GameState.ach_stats
	# 缺字段补默认 (旧存档/首次)
	if not s.has("battles"): s["battles"] = 0
	if not s.has("wins"): s["wins"] = 0
	if not s.has("crits"): s["crits"] = 0
	if not s.has("totalDmg"): s["totalDmg"] = 0
	if not s.has("totalEquipsBought"): s["totalEquipsBought"] = 0
	if not s.has("totalCoinsEarned"): s["totalCoinsEarned"] = 0
	if not s.has("petsUsed"): s["petsUsed"] = {}
	if not s.has("rulesSeen"): s["rulesSeen"] = {}
	if not s.has("bestDungeon"): s["bestDungeon"] = 0
	return s


static func _save() -> void:
	GameState.save()


static func get_stats() -> Dictionary:
	return _stats()


static func get_unlocked() -> Array:
	return GameState.achievements_unlocked


## 直接解锁 (id 已检查), 已解锁的不重复. 返回是否本次新解锁. 1:1 PoC unlock() (ts:57-63).
static func unlock(id: String) -> bool:
	if id in GameState.achievements_unlocked:
		return false
	if not DataRegistry.achievements_by_id.has(id):
		return false
	GameState.achievements_unlocked.append(id)
	_save()
	return true


## 注册玩家使用过的龟 (1:1 PoC markPetUsed, ts:79-82).
static func mark_pet_used(id: String) -> void:
	var s := _stats()
	(s["petsUsed"] as Dictionary)[id] = true
	_save()


## 注册玩家见过的规则 (1:1 PoC markRuleSeen, ts:85-88).
static func mark_rule_seen(rule: String) -> void:
	var s := _stats()
	(s["rulesSeen"] as Dictionary)[rule] = true
	_save()


## 记最佳通关层数 (1:1 PoC setBestDungeon, ts:91-96).
static func set_best_dungeon(stage: int) -> void:
	var s := _stats()
	if stage > int(s["bestDungeon"]):
		s["bestDungeon"] = stage
		_save()


## 检查所有阈值类成就 (累积统计驱动), 返回本次新解锁的 id 列表.
## 1:1 PoC checkAll() (ts:99-127), 阈值逐条对齐。
static func check_all() -> Array:
	var newly: Array = []
	var s := _stats()
	var pets_n: int = (s["petsUsed"] as Dictionary).size()
	var rules_n: int = (s["rulesSeen"] as Dictionary).size()
	var try_unlock := func(id: String, cond: bool) -> void:
		if cond and unlock(id): newly.append(id)
	# 战斗类
	try_unlock.call("first_win", int(s["wins"]) >= 1)
	try_unlock.call("win_10", int(s["wins"]) >= 10)
	try_unlock.call("win_50", int(s["wins"]) >= 50)
	try_unlock.call("win_100", int(s["wins"]) >= 100)
	try_unlock.call("battle_3", int(s["battles"]) >= 3)
	try_unlock.call("battle_25", int(s["battles"]) >= 25)
	try_unlock.call("crit_100", int(s["crits"]) >= 100)
	# 收集
	try_unlock.call("equip_5", int(s["totalEquipsBought"]) >= 5)
	try_unlock.call("equip_25", int(s["totalEquipsBought"]) >= 25)
	try_unlock.call("try_5_pets", pets_n >= 5)
	try_unlock.call("try_15_pets", pets_n >= 15)
	try_unlock.call("try_28_pets", pets_n >= 28)
	try_unlock.call("coins_500", int(s["totalCoinsEarned"]) >= 500)
	try_unlock.call("coins_5000", int(s["totalCoinsEarned"]) >= 5000)
	try_unlock.call("all_rules", rules_n >= 7)
	# 进度
	try_unlock.call("dungeon_1", int(s["bestDungeon"]) >= 1)
	try_unlock.call("dungeon_2", int(s["bestDungeon"]) >= 2)
	try_unlock.call("dungeon_3", int(s["bestDungeon"]) >= 3)
	try_unlock.call("dungeon_4", int(s["bestDungeon"]) >= 4)
	try_unlock.call("dungeon_5", int(s["bestDungeon"]) >= 5)
	return newly


## 战斗结束结算钩子 (1:1 PoC onBattleEnd, ts:130-149).
## 累计本局统计 + 查单局类成就 + check_all, 返回本次新解锁 id (去重)。
## 注: Godot battle_stats 不记暴击 → 调用方 per_battle_crits 传 0 (见 BattleEndScene 注释);
##     故 crits 永不累积 → crit_100 不会解锁 (统计字段缺, 如实跳过, 非 1:1 偏差)。
static func on_battle_end(result: String, pets_used: Array, rule, per_battle_dmg: int, per_battle_crits: int, per_battle_kills: int, all_alive: bool) -> Array:
	var s := _stats()
	s["battles"] = int(s["battles"]) + 1
	if result == "win":
		s["wins"] = int(s["wins"]) + 1
	s["crits"] = int(s["crits"]) + per_battle_crits
	s["totalDmg"] = int(s["totalDmg"]) + per_battle_dmg
	for p in pets_used:
		(s["petsUsed"] as Dictionary)[p] = true
	if rule != null and str(rule) != "":
		(s["rulesSeen"] as Dictionary)[str(rule)] = true
	_save()

	var newly: Array = []
	var try_unlock := func(id: String, cond: bool) -> void:
		if cond and unlock(id): newly.append(id)
	try_unlock.call("dmg_5k_battle", per_battle_dmg >= 5000)
	try_unlock.call("dmg_10k_battle", per_battle_dmg >= 10000)
	try_unlock.call("kills_5_battle", per_battle_kills >= 5)
	if result == "win" and all_alive: try_unlock.call("no_loss_battle", true)
	if result == "win" and all_alive: try_unlock.call("six_alive", true)
	if rule != null and str(rule) != "": try_unlock.call("custom_battle", true)
	for id in check_all():
		if not (id in newly):
			newly.append(id)
	return newly


## 买装备钩子 (1:1 PoC onEquipBought, ts:151-159). 累计 + first_equip/shop_buy + check_all.
static func on_equip_bought() -> Array:
	var s := _stats()
	s["totalEquipsBought"] = int(s["totalEquipsBought"]) + 1
	_save()
	var newly: Array = []
	if unlock("first_equip"): newly.append("first_equip")
	if unlock("shop_buy"): newly.append("shop_buy")
	for id in check_all():
		if not (id in newly):
			newly.append(id)
	return newly


## 赚币钩子 (1:1 PoC onCoinsEarned, ts:161-165). 累计 + check_all.
static func on_coins_earned(amount: int) -> Array:
	var s := _stats()
	s["totalCoinsEarned"] = int(s["totalCoinsEarned"]) + amount
	_save()
	return check_all()


## 翻图鉴钩子 (1:1 PoC onCodexOpen, ts:167).
static func on_codex_open() -> bool:
	return unlock("codex_open")


## 看完引导钩子 (1:1 PoC onTutorialDone, ts:168).
static func on_tutorial_done() -> bool:
	return unlock("tutorial_done")
