extends RefCounted

## Backend — V2 异步 ghost 匹配 / bot 兜底 / 排行榜 的【本地实现】(阶段4/5 MVP).
##
## 用 preload 引 (不用 class_name):
##   const Backend = preload("res://scripts/net/backend.gd")
##
## MVP 全本地: ghost 池存 user://ghost_pool.json (按进度档分桶). 接口稳定,
## 以后换 RemoteBackend(Supabase) 不动调用方. 设计见 docs/design/V2模式策划 §十三.
##
## 纯逻辑(分档/快照/池增删/bot/榜) 操作内存 Dictionary → 可单测;
## 文件 I/O (load_pool/save_pool) 是薄包装; rng 由调用方传入 → 确定可测.

const POOL_PATH := "user://ghost_pool.json"
const SEED_PATH := "res://data/ghost_seed.json"   # 内置 10 支策划队(按档分桶), 冷启动/老档无种子时并入
const BUCKET_CAP := 50          # 每档桶封顶 (防无限增长, 旧的挤出)
const _P2 = preload("res://scripts/gamedata/phase2_config.gd")

# ─── 进度档 (设计§十三): 总战斗数 → 匹配档 0-8. 低档窄(对齐槽断点)/高档宽(保池子有人) ───
## ★2026-07-27 用户拍板: 档0 严格 = 【人生第一把】(total==0), 后面各档整体顺延一格。
##   起因: 原来 total<=1 让档0 同时装下两种人 —— 打过 0 场的(一分钱没有·全裸) 和
##   打过 1 场的(已逛过一次商店·约 6 件)。于是「档0 无装备」这条锚点与档0 的真实人口自相矛盾
##   (队列模拟直接暴露: 档0 快照平均 7.5 件装备)。
##   现在档0 只有真·第一把的人, 双方全裸 = 纯阵容/技能对决。各档宽度不变, 只是断点 -1。
## ★2026-07-27 二次调整(用户选「微调B」): 把高档间距拉近, 让档7/8 变成【真有人到得了】的档位。
##   起因(概率+实测双证): 8 条命 + 50% 胜率下, 打满 N 场的概率 = P(前 N-1 场里输 ≤7 次)。
##   旧断点(档7=30场 / 档8=40场) 下 1000 个玩家里只有 4 人到档7、0 人到档8 ——
##   档8 要约 28000 个玩家才期望出现 1 个, 而每档池子能装 50 支队。
##   首轮 32 只队列实测印证: 最远只打到第 29 场, 档7/8 产出快照 0 条。
##   新断点(档7=22场 / 档8=28场) → 1000 人里档7 有 95 人、档8 有 9.6 人, 池子填得起来。
##   (备选: 轻=24/31 档8仅2.6人; 再近些=20/25 档8 32人。用户取中档。)
static func bracket_for_battles(total: int) -> int:
	if total <= 0: return 0
	if total <= 2: return 1
	if total <= 4: return 2
	if total <= 7: return 3
	if total <= 11: return 4
	if total <= 16: return 5
	if total <= 21: return 6
	if total <= 27: return 7
	return 8

## 某档"代表总战斗数"(给 bot 配槽位/等级; 取档上界). 大致反 bracket_for_battles.
static func battles_for_bracket(bracket: int) -> int:
	match bracket:      # 与 bracket_for_battles 互逆(取档上界); 2026-07-27 随「微调B」同步
		0: return 0
		1: return 2
		2: return 4
		3: return 7
		4: return 11
		5: return 16
		6: return 21
		7: return 27
		_: return 33

# ─── ghost 池 (内存 Dictionary, 结构 {brackets:{"档":[snapshot...]}}) ───
## 把 snapshot 加进对应档桶 (新的在前, 封顶挤旧).
static func pool_add(pool: Dictionary, snapshot: Dictionary) -> void:
	if not pool.has("brackets"):
		pool["brackets"] = {}
	var b := str(int(snapshot.get("bracket", 0)))
	if not pool["brackets"].has(b):
		pool["brackets"][b] = []
	var bucket: Array = pool["brackets"][b]
	var new_id := str(snapshot.get("ghost_id", ""))   # ★去重(用户2026-07-18): 同ghost_id(同一玩家阵容跨场重传)先删旧再入→池里一个逻辑对手=一条, 排除最近3场才真挡得住
	if new_id != "":
		for i in range(bucket.size() - 1, -1, -1):
			if str((bucket[i] as Dictionary).get("ghost_id", "")) == new_id:
				bucket.remove_at(i)
	bucket.push_front(snapshot)
	while bucket.size() > BUCKET_CAP:
		bucket.pop_back()

## 玩家自己上传的快照? 本地池里 profile 名恒为"玩家阵容"(单机没别的真人)→匹配一律跳过, 防撞自己阵容(用户2026-07-18: 只按id排除挡不住修复前遗留的旧volatile id自传·按名一网打尽).
static func _is_self_ghost(g) -> bool:
	return g is Dictionary and str(((g as Dictionary).get("profile", {}) as Dictionary).get("name", "")) == "玩家阵容"

## 从池抽一个同档对手 (排除 exclude_ids). 桶空/全排除 → null (调用方 make_bot 兜底).
static func pool_find(pool: Dictionary, bracket: int, exclude_ids: Array, rng: RandomNumberGenerator):
	var brackets: Dictionary = pool.get("brackets", {})
	var b := str(bracket)
	if not brackets.has(b):
		return null
	var candidates: Array = []
	for g in brackets[b]:
		if _is_self_ghost(g): continue
		if not exclude_ids.has(str((g as Dictionary).get("ghost_id", ""))):
			candidates.append(g)
	if candidates.is_empty():
		return null
	return candidates[rng.randi() % candidates.size()]

# ─── bot 生成 (池空/冷启动兜底 = 永久安全网, 设计§十三) ───
## 按档配资源(槽位/等级)随机一支队. rng 决定随机 → 确定可测. is_bot=true.
static func make_bot(bracket: int, rng: RandomNumberGenerator) -> Dictionary:
	var battles := battles_for_bracket(bracket)
	var bot_lv := clampi(2 + bracket, 1, 10)   # 档越高 bot 等级越高
	# ★装备容量统一规则(2026-07-27): 与玩家同一套 —— 全队合计 team_equip_cap(等级), 单只 ≤ UNIT_EQUIP_CAP。
	#   原来这里走 equip_slots_for_battles(每只固定N件) = 敌我两把尺子, 已废。
	var budget := _P2.team_equip_cap(bot_lv)
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
	# 先给统领分, 每只最多 UNIT_EQUIP_CAP; 分完剩下的留给小将(下面)。总数受 budget 硬约束。
	for pid in leaders:
		levels[pid] = bot_lv
		var eqs: Array = []
		while eqs.size() < _P2.UNIT_EQUIP_CAP and budget > 0 and shop_ids.size() > 0:
			eqs.append({"id": shop_ids[rng.randi() % shop_ids.size()], "star": 1})
			budget -= 1
		if eqs.size() > 0:
			equipped[pid] = eqs
	# 小将补位到每路3单位 + 随机装备(用户2026-07-18「快照里对面小将没有装备」根因: make_bot原来根本没minions字段→bot小将全裸; 镜像build_ghost_snapshot补上)
	var minions := {"top": [], "bottom": []}
	for lk in ["top", "bottom"]:
		var lead_cnt: int = (lane_assign[lk] as Array).size()
		var want: int = clampi(3 - lead_cnt, 0, 3)
		for mi in range(want):
			var meqs: Array = []
			while meqs.size() < _P2.UNIT_EQUIP_CAP and budget > 0 and shop_ids.size() > 0:
				meqs.append({"id": shop_ids[rng.randi() % shop_ids.size()], "star": 1})
				budget -= 1
			var m := {"role": "front" if mi == 0 else "back", "elite": (lead_cnt == 0 and mi == 0)}
			if meqs.size() > 0:
				m["equips"] = meqs
			(minions[lk] as Array).append(m)
	return {
		"schema_ver": 1,
		"ghost_id": "bot_%d_%d" % [bracket, rng.randi() % 1000000],
		"is_bot": true,
		"bracket": bracket,
		"profile": {"name": "海域守卫", "avatar": str(leaders[0]) if leaders.size() > 0 else "basic", "id": "BOT"},
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
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

const SEED_VER := 6   # 2026-07-27 v6: 队列模拟(160只机器人从0起互打·8命淘汰)产出的【真实玩家快照】180支/9档各20; 装备是真背包历史(1~5费混搭·便宜的星高贵的星低), 非按目标强度反推。升版→老档清旧seed_并入新种子(玩家上传的真ghost保留)
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

## ★headless(测试/仿真/导出) 绝不写玩家真实池 —— 与 GameState.test_mode 同一条纪律(GameState.gd:570)。
## 起因(2026-07-27): GameState.save() 早有这个守卫, save_pool 一直没有 → 任何跑战斗的测试赢一把就
## upload_ghost 污染 user://ghost_pool.json; 更隐蔽的是 load_pool→_ensure_seeded→save_pool(L211),
## 【光是读池就会写盘】。存档目录里那个 savegame.json.bak-被测试污染 就是同类事故的遗迹。
## 只挡默认的 user:// 真实池; 显式传 path(自举仿真/离线产池) 照写不误。
static func save_pool(pool: Dictionary, path: String = POOL_PATH) -> void:
	if path == POOL_PATH and GameState != null and bool(GameState.test_mode):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(pool, "  ")); f.close()

# ─── 高层 orchestration (gameplay 调这俩) ───
## 在 [lo,hi] 档窗口内汇总所有候选(排除exclude)随机抽一个. 空→null.
static func pool_find_window(pool: Dictionary, lo: int, hi: int, exclude_ids: Array, rng: RandomNumberGenerator):
	var brackets: Dictionary = pool.get("brackets", {})
	var candidates: Array = []
	for bi in range(maxi(0, lo), hi + 1):
		var b := str(bi)
		if not brackets.has(b):
			continue
		for g in brackets[b]:
			if _is_self_ghost(g): continue   # 跳过自己上传的快照(防撞自己·新旧id一网打尽)
			if not exclude_ids.has(str((g as Dictionary).get("ghost_id", ""))):
				candidates.append(g)
	if candidates.is_empty():
		return null
	return candidates[rng.randi() % candidates.size()]

## 匹配用的【单一受控 PRNG】(Riot 确定性做法: 一个隔离的、可种子化的随机源)。
## 默认 randomize() —— 与线上行为字节一致, 玩家侧永远随机。
## 仅当环境变量 TURTLE_SEED=<整数> 时改用固定种子 → 同种子必得同对手 → 测试/复现可确定。
## 这是"结构治理·切片1": 把匹配随机收束到一个入口, 后续战斗 RNG 也走同一模式。
static func make_match_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	var s := OS.get_environment("TURTLE_SEED")
	if s != "" and s.is_valid_int():
		r.seed = int(s)
	else:
		r.randomize()
	return r

## 抽对手: 同档 ghost, 没有就 bot. 永远返回一个可打的对手 (永久安全网).
##
## ★2026-07-27 用户「±1 这东西去掉」: 改回【只抽本档, 空了只往【低】档回落, 绝不往上】。
##   废掉的是 2026-07-18 的 [档-1, 档+1] 窗口 —— 它当初是为了治"匹配多了总撞同一阵容"
##   (那时单档只~7 支种子)。但自动玩家 30 把实测它的代价远大于收益:
##     · 第 2 把(档0·自己 0 件装备) 撞到档1 带 3 件的队
##     · 第 7 把 我方强度 43.0 撞到 99.0 (2.3 倍)
##     · 第 10 把 45.8 撞到 118.6 (2.6 倍)
##   而多样性问题现在已不成立: 种子池 146 支, 单档 12~20 支, 再排除最近 3 个 → 9~17 个候选够用。
##   ★不许往上回落是硬约束: "档N 的玩家绝不该遇到 >N 档的对手"(verify_bracket_gear 新增断言守这条)。
static func find_opponent(bracket: int, exclude_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := load_pool()
	for b in range(bracket, -1, -1):                # 本档优先; 本档空/全排除 → 就近【低】档回落, 全空才 bot
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
	# 小将(dual_lineup)配置+装备也存进快照(用户2026-07-18"快照里小将也应该有装备")→对手小将不再裸装
	var minions := {}
	if GameState.dual_lineup is Dictionary:
		for lk in ["top", "bottom"]:
			var arr: Array = (GameState.dual_lineup as Dictionary).get(lk, [])
			var mlist: Array = []
			for uu in arr:
				if uu is Dictionary and str((uu as Dictionary).get("kind", "")) == "minion":
					var m := {"role": str((uu as Dictionary).get("role", "front")), "elite": bool((uu as Dictionary).get("elite", false))}
					var meq = (uu as Dictionary).get("equips", null)
					if meq is Array and not (meq as Array).is_empty():
						m["equips"] = (meq as Array).duplicate(true)
					mlist.append(m)
			minions[lk] = mlist
	return {
		"schema_ver": 1,
		"ghost_id": ghost_id,
		"is_bot": false,
		"bracket": bracket_for_battles(int(GameState.season_total_battles)),
		"profile": profile,
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
		"loadouts": {},
		"equipped": equipped,
		"pet_levels": levels,
		"season_total_battles": int(GameState.season_total_battles),
		"season_eggs_killed": int(GameState.season_eggs_killed),
	}
