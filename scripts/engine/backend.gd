extends RefCounted

## Backend — V2 异步 ghost 匹配 / bot 兜底 / 排行榜 的【本地实现】(阶段4/5 MVP).
##
## 用 preload 引 (不用 class_name):
##   const Backend = preload("res://scripts/engine/backend.gd")
##
## MVP 全本地: ghost 池存 user://ghost_pool.json (按进度档分桶). 接口稳定,
## 以后换 RemoteBackend(Supabase) 不动调用方. 设计见 docs/design/V2模式策划 §十三.
##
## 纯逻辑(分档/快照/池增删/bot/榜) 操作内存 Dictionary → 可单测;
## 文件 I/O (load_pool/save_pool) 是薄包装; rng 由调用方传入 → 确定可测.

const POOL_PATH := "user://ghost_pool.json"
const SEED_PATH := "res://data/ghost_seed.json"   # 内置 10 支策划队(按档分桶), 冷启动/老档无种子时并入
const BUCKET_CAP := 50          # 每档桶封顶 (防无限增长, 旧的挤出)
const _P2 = preload("res://scripts/engine/phase2_config.gd")

# ─── 进度档 (设计§十三): 总战斗数 → 匹配档 0-8. 低档窄(对齐槽断点)/高档宽(保池子有人) ───
static func bracket_for_battles(total: int) -> int:
	if total <= 1: return 0
	if total <= 3: return 1
	if total <= 5: return 2
	if total <= 8: return 3
	if total <= 14: return 4
	if total <= 20: return 5
	if total <= 30: return 6
	if total <= 40: return 7
	return 8

## 某档"代表总战斗数"(给 bot 配槽位/等级; 取档上界). 大致反 bracket_for_battles.
static func battles_for_bracket(bracket: int) -> int:
	match bracket:
		0: return 1
		1: return 3
		2: return 5
		3: return 8
		4: return 14
		5: return 20
		6: return 30
		7: return 40
		_: return 45

# ─── ghost 池 (内存 Dictionary, 结构 {brackets:{"档":[snapshot...]}}) ───
## 把 snapshot 加进对应档桶 (新的在前, 封顶挤旧).
static func pool_add(pool: Dictionary, snapshot: Dictionary) -> void:
	if not pool.has("brackets"):
		pool["brackets"] = {}
	var b := str(int(snapshot.get("bracket", 0)))
	if not pool["brackets"].has(b):
		pool["brackets"][b] = []
	var bucket: Array = pool["brackets"][b]
	bucket.push_front(snapshot)
	while bucket.size() > BUCKET_CAP:
		bucket.pop_back()

## 从池抽一个同档对手 (排除 exclude_ids). 桶空/全排除 → null (调用方 make_bot 兜底).
static func pool_find(pool: Dictionary, bracket: int, exclude_ids: Array, rng: RandomNumberGenerator):
	var brackets: Dictionary = pool.get("brackets", {})
	var b := str(bracket)
	if not brackets.has(b):
		return null
	var candidates: Array = []
	for g in brackets[b]:
		if not exclude_ids.has(str((g as Dictionary).get("ghost_id", ""))):
			candidates.append(g)
	if candidates.is_empty():
		return null
	return candidates[rng.randi() % candidates.size()]

# ─── bot 生成 (池空/冷启动兜底 = 永久安全网, 设计§十三) ───
## 按档配资源(槽位/等级)随机一支队. rng 决定随机 → 确定可测. is_bot=true.
static func make_bot(bracket: int, rng: RandomNumberGenerator) -> Dictionary:
	var battles := battles_for_bracket(bracket)
	var slots := _P2.equip_slots_for_battles(battles)
	var bot_lv := clampi(2 + bracket, 1, 10)   # 档越高 bot 等级越高
	# 随机 3 龟
	var all_ids: Array = []
	for p in DataRegistry.launch_pets:
		all_ids.append(str((p as Dictionary)["id"]))
	_shuffle(all_ids, rng)
	var leaders: Array = all_ids.slice(0, 3) if all_ids.size() >= 3 else all_ids
	# 分路: 前2上 / 后1下 (= auto_split 2/1)
	var lane_assign := {"top": [], "bottom": []}
	for i in range(leaders.size()):
		(lane_assign["bottom"] if i >= 2 else lane_assign["top"]).append(leaders[i])
	# 装备: 每龟随机 slots 件 shopAvailable 装备
	var shop_ids: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop_ids.append(str((e as Dictionary)["id"]))
	var equipped := {}
	var levels := {}
	for pid in leaders:
		levels[pid] = bot_lv
		var eqs: Array = []
		for _i in range(slots):
			if shop_ids.size() > 0:
				eqs.append({"id": shop_ids[rng.randi() % shop_ids.size()], "star": 1})
		if eqs.size() > 0:
			equipped[pid] = eqs
	return {
		"schema_ver": 1,
		"ghost_id": "bot_%d_%d" % [bracket, rng.randi() % 1000000],
		"is_bot": true,
		"bracket": bracket,
		"profile": {"name": "海域守卫", "avatar": str(leaders[0]) if leaders.size() > 0 else "basic", "id": "BOT"},
		"leaders": leaders,
		"lane_assign": lane_assign,
		"loadouts": {},
		"equipped": equipped,
		"pet_levels": levels,
		"season_total_battles": battles,
		"season_eggs_killed": 0,
	}

## Fisher-Yates 洗牌 (rng 确定).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]; arr[i] = arr[j]; arr[j] = t

# ─── 排行榜 (MVP: 信任本地 season_eggs_killed, 不复算; 防作弊=上线后端的事, 设计§十五#3) ───
## 池里所有 ghost 按击杀蛋数降序 + 插入自己; 返回前 limit 行 [{name,eggs,is_self}].
static func leaderboard(pool: Dictionary, self_name: String, self_eggs: int, limit: int) -> Array:
	var rows: Array = [{"name": self_name, "eggs": self_eggs, "is_self": true}]
	var brackets: Dictionary = pool.get("brackets", {})
	for b in brackets.keys():
		for g in brackets[b]:
			var gd := g as Dictionary
			rows.append({"name": str(gd.get("profile", {}).get("name", "?")), "eggs": int(gd.get("season_eggs_killed", 0)), "is_self": false})
	rows.sort_custom(func(a, c): return int(a["eggs"]) > int(c["eggs"]))
	return rows.slice(0, limit) if rows.size() > limit else rows

# ─── 文件 I/O (薄包装, user://ghost_pool.json) ───
static func load_pool(path: String = POOL_PATH) -> Dictionary:
	var pool: Dictionary = {"brackets": {}}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text(); f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				pool = parsed
	if not pool.has("brackets"):
		pool["brackets"] = {}
	_ensure_seeded(pool)   # 冷启动/老档无种子 → 并入内置策划队(幂等, 已并过不重复); 下次 upload_ghost 落盘
	return pool

## 内置种子池 (res:// 只读, 导出包里也在). 解析失败=空.
static func _load_seed() -> Dictionary:
	if not FileAccess.file_exists(SEED_PATH):
		return {"brackets": {}}
	var f := FileAccess.open(SEED_PATH, FileAccess.READ)
	if f == null:
		return {"brackets": {}}
	var parsed = JSON.parse_string(f.get_as_text()); f.close()
	if parsed is Dictionary and (parsed as Dictionary).has("brackets"):
		return parsed
	return {"brackets": {}}

const SEED_VER := 2   # 种子池版本(2026-07-15: 49→70支+loadouts+档8); 升版→老档清旧seed_并入新种子(玩家上传的真ghost保留)
## 种子并入(版本化): 无seed_ 或 池版本<SEED_VER → 清旧seed_+并入新种子+落盘. 修真机bug"老池挡住新种子永不升级"(用户2026-07-15).
static func _ensure_seeded(pool: Dictionary) -> void:
	var brackets: Dictionary = pool.get("brackets", {})
	var have_seed := false
	for b in brackets.keys():
		for g in brackets[b]:
			if str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				have_seed = true
				break
		if have_seed: break
	if have_seed and int(pool.get("_seed_ver", 0)) >= SEED_VER:
		return
	for b in brackets.keys():                       # 清旧版seed_(玩家真ghost保留)
		var keep: Array = []
		for g in brackets[b]:
			if not str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				keep.append(g)
		brackets[b] = keep
	var seed := _load_seed()
	for b in seed.get("brackets", {}).keys():
		for g in seed["brackets"][b]:
			pool_add(pool, g)
	pool["_seed_ver"] = SEED_VER
	save_pool(pool)                                 # 升级立即落盘(否则要等下次upload才存)

static func save_pool(pool: Dictionary, path: String = POOL_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(pool, "  ")); f.close()

# ─── 高层 orchestration (gameplay 调这俩) ───
## 抽对手: 同档 ghost, 没有就 bot. 永远返回一个可打的对手 (永久安全网).
static func find_opponent(bracket: int, exclude_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := load_pool()
	for b in range(bracket, -1, -1):                # 本档没人(被排除/池洞)→就近低档回落, 全空才bot(修真机"高档空池永远同一支/bot")
		var g = pool_find(pool, b, exclude_ids, rng)
		if g != null: return g
	return make_bot(bracket, rng)

## 上传自己阵容快照进池 (玩家配好 build / 赢一场后).
static func upload_ghost(snapshot: Dictionary) -> void:
	var pool := load_pool()
	pool_add(pool, snapshot)
	save_pool(pool)

## 从玩家刚打的这局 (left 侧) 序列化成 ghost 快照 (上传自己用). ghost_id/profile 调用方给.
static func build_ghost_snapshot(ghost_id: String, profile: Dictionary) -> Dictionary:
	var leaders: Array = GameState.left_team.duplicate() if GameState.left_team is Array else []
	var lane_assign: Dictionary = GameState.lane_assign.duplicate(true) if GameState.lane_assign is Dictionary else {}
	var equipped := {}
	var levels := {}
	for pid in leaders:
		var p := str(pid)
		var eqs: Array = GameState.equipped_p2.get(p, [])   # left 侧裸 pet_id (无 right:: 前缀)
		if not eqs.is_empty():
			equipped[p] = eqs.duplicate(true)
		levels[p] = GameState.get_pet_level(p)
	return {
		"schema_ver": 1,
		"ghost_id": ghost_id,
		"is_bot": false,
		"bracket": bracket_for_battles(int(GameState.season_total_battles)),
		"profile": profile,
		"leaders": leaders,
		"lane_assign": lane_assign,
		"loadouts": {},
		"equipped": equipped,
		"pet_levels": levels,
		"season_total_battles": int(GameState.season_total_battles),
		"season_eggs_killed": int(GameState.season_eggs_killed),
	}
