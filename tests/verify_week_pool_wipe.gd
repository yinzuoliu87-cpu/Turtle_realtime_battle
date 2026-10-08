extends Node
## verify_week_pool_wipe.gd — 换周时本机对手池清掉真人快照(2026-10-08)
##
## 用户原话:「每周快照会刷掉对吧」→(查实: 服务端只拉本周, 但本机池不按周清, 选靶也不看哪一周)→「改」。
## 判据走真入口 `GameState.start_new_season()`(换周就是它), 量真池子文件:
##   ① 换周前池里有真人快照(分母) ② 换周后真人快照一条不剩、陪练(seed_)原样保留
##   ③ 上周那份同场次快照再也抽不到(pool_find_battles 走的是产品自己的选靶)
## ★本门禁在隔离的 user:// 下跑(run-tests / run_some 每测试一份), 写 POOL_PATH 不碰玩家存档。

const Backend := preload("res://scripts/net/backend.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ghost(id: String, battles: int) -> Dictionary:
	return {
		"schema_ver": Backend.SCHEMA_VER,
		"ghost_id": id,
		"is_bot": false,
		"origin": Backend.ORIGIN_REMOTE,
		"profile": {"name": "上周%s" % id},
		"leaders": ["basic", "ninja", "stone"],
		"season_total_battles": battles,
	}


func _count(pool: Dictionary, seed: bool) -> int:
	var n := 0
	for b in (pool.get(Backend.POOL_KEY, {}) as Dictionary).keys():
		for g in (pool[Backend.POOL_KEY][b] as Array):
			var is_seed := str((g as Dictionary).get("ghost_id", "")).begins_with(Backend.SEED_ID_PREFIX)
			if is_seed == seed:
				n += 1
	return n


func _ready() -> void:
	await get_tree().process_frame
	print("=== 换周清本机对手池 ===")
	var was_test: bool = bool(GameState.test_mode)
	GameState.test_mode = false          # save_pool 在 test_mode 下不落盘; 本测试的 user:// 是隔离的
	var pool := Backend.load_pool()
	var seeds0 := _count(pool, true)
	Backend.pool_add(pool, _ghost("real_a", 7))
	Backend.pool_add(pool, _ghost("real_b", 7))
	Backend.pool_add(pool, _ghost("real_c", 3))
	Backend.save_pool(pool)
	var before := Backend.load_pool()
	_ok("★分母: 换周前池里有真人快照", _count(before, false) >= 3, "%d 条" % _count(before, false))
	_ok("★分母: 池里有内置陪练", seeds0 > 0, "%d 条" % seeds0)

	GameState.start_new_season()         # 真入口: 换周

	var after := Backend.load_pool()
	_ok("★★换周后真人快照一条不剩", _count(after, false) == 0, "剩 %d 条" % _count(after, false))
	_ok("★陪练原样保留(数量不变)", _count(after, true) == seeds0, "%d vs %d" % [_count(after, true), seeds0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hit := 0
	for _i in range(50):
		var g = Backend.pool_find_battles(after, 7, [], rng)
		if g != null and str((g as Dictionary).get("ghost_id", "")).begins_with("real_"):
			hit += 1
	_ok("★★上周那份同场次快照再也抽不到(50 次 0 次)", hit == 0, "抽到 %d 次" % hit)

	GameState.test_mode = was_test
	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
