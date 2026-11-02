extends Node
## 探针: **周内积分赛** 10 个人一周下来, 多少局是机器人?
##
## ★为什么问: v0.19.449 修的是**周六闯关赛**的 93% 机器人率, 而周内积分赛占一周 5/7,
##   从来没量过。周内是**严格同场次**(v0.19.447) ⇒ 没人和你同场次就回落机器人。
## ★用真原语: `Backend.pool_add` 灌池 / `Backend.find_opponent` 选靶 —— 不自己造一套。
const BE := preload("res://scripts/net/backend.gd")

const N_PLAYERS := 10
const N_MATCHES := 24          ## 一周配额


func _snap(pid: int, battles: int) -> Dictionary:
	return {
		"schema_ver": BE.SCHEMA_VER,
		"ghost_id": "p%d_b%d" % [pid, battles],     ## 与产品一样: id 带**场次**这一维
		"is_bot": false,
		"origin": BE.ORIGIN_REMOTE,
		"profile": {"name": "玩家%d" % pid},
		"season_wins": battles / 2,
		"hearts": 3,
		"season_sweeps": 0,
		"season_total_battles": battles,
	}


func _run(order_desc: String, interleave: bool) -> void:
	var pool: Dictionary = {BE.POOL_KEY: {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var bots := 0
	var total := 0
	var battles: Array = []
	for _p in range(N_PLAYERS):
		battles.append(0)
	## 每一步: 挑一个玩家打一局。interleave=true → 轮流; false → 一个人打完再下一个
	for step in range(N_PLAYERS * N_MATCHES):
		var pid: int = (step % N_PLAYERS) if interleave else (step / N_MATCHES)
		var b: int = int(battles[pid])
		## 先把**自己这一场次的快照**放进池(产品是打完上传, 这里同序: 选靶时自己那份还不在)
		## ★★这里**不能**调 `BE.find_opponent` —— 它内部读 `Backend.load_pool()`,
		##   而 `load_pool` 会 `_ensure_seeded()` 灌进 396 条内置种子 ⇒ 量的是种子池,
		##   不是我这 10 个人(第一版就是这样得出「0% 机器人」的假答案:
		##   memory `fb-gate-subject-never-constructed`)。
		## ⇒ 直接调选靶原语 `pool_find_battles`, 池子由我给。
		var ge = BE.pool_find_battles(pool, b, [ "p%d_b%d" % [pid, b] ], rng)
		total += 1
		if ge == null:
			bots += 1
		BE.pool_add(pool, _snap(pid, b))
		battles[pid] = b + 1
	print("  %-22s 共 %d 局 · 机器人 %d 局 = **%.1f%%**" % [order_desc, total, bots, 100.0 * float(bots) / float(total)])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 周内积分赛 10 人 × 24 场: 机器人占比 ===")
	_run("轮流打(最理想)", true)
	_run("一个接一个打完", false)
	print("")
	print("=== 真池(含 396 条内置种子)下: 对手是谁 ===")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20260927
	var real_pool: Dictionary = BE.load_pool()
	var seeds := 0
	var humans := 0
	var nulls := 0
	for b in range(25):
		for _k in range(8):
			var g = BE.pool_find_battles(real_pool, b, [], rng2)
			if g == null:
				nulls += 1
			elif str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				seeds += 1
			else:
				humans += 1
	var tot: int = seeds + humans + nulls
	print("  场次 0~24 各抽 8 次 · 共 %d 次: 种子陪练 %d (%.0f%%) / 真人 %d / 配不到 %d" % [
		tot, seeds, 100.0 * float(seeds) / float(tot), humans, nulls])
	## ── 逐场次: 种子有多少支? 加上 k 个真人测试者, 配到真人的概率是多少? ──
	print("")
	print("=== 每个场次的池子成分(内置种子) + 10 人测试时配到真人的概率 ===")
	var buckets: Dictionary = real_pool.get(BE.POOL_KEY, {})
	var tot_seed := 0
	var shown := 0
	for b2 in range(25):
		var arr: Array = buckets.get(str(b2), []) as Array
		var ns := 0
		for g2 in arr:
			if str((g2 as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				ns += 1
		tot_seed += ns
		if b2 <= 8 or b2 == 24:
			## 10 人测试: 同场次最多另外 9 个真人(全都到过这一格才成立)
			var p: float = 9.0 / float(ns + 9) * 100.0 if ns + 9 > 0 else 0.0
			print("  场次 %-2d  种子 %-3d 支  ⇒ 配到真人概率 ≤ %.0f%%" % [b2, ns, p])
			shown += 1
	print("  ---- 0~24 种子合计 %d 支 ----" % tot_seed)
	get_tree().quit(0)
