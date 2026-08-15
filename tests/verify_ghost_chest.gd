extends Node
## verify_ghost_chest.gd — 敌方宝箱进度进快照 (用户 2026-08-14 拍板 A)
##
## ★查清楚的事实(这条门禁守的就是它):
##   敌方 = `backend.find_opponent()` 找**真人玩家的 ghost 快照**。
##   快照原来带 leaders / lane_assign / minions / equipped / pet_levels,
##   **唯独宝箱进度一件不带** —— `backend.gd` 全文只出现过 1 次 "chest", 还在无关注释里。
##   于是敌方宝箱龟走一套单场旧制阈值 `[80,130,240,360,590]`, 比我方低 12~50 倍,
##   一场就能开满 5 件传说。那不是真人打出来的进度, 是代码凭空编的对手。
##
## ★用户拍板 A: 把进度加进快照 / 老快照全清 / 重新制作 / 删掉单场旧制。
##   ⚠ 清空快照 = 池子空一阵, 所有人下一局先遇 bot —— 这是明知的代价, 不是 bug。

const Backend := preload("res://scripts/net/backend.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	if gs == null:
		print("✗ GameState autoload 缺失"); get_tree().quit(1); return
	gs.test_mode = true   # ★不写盘: 否则本测试会覆盖玩家的 user://savegame.json

	print("=== 敌方宝箱进度进快照 ===")

	# ── ① 快照真的带上了进度 ────────────────────────────────────────────
	var won_bak: Array = (gs.chest_treasures_won as Array).duplicate()
	var val_bak: float = float(gs.chest_treasure_value)
	gs.chest_treasures_won = ["rum", "gem_armor", "flint"]
	gs.chest_treasure_value = 12345.0
	var snap: Dictionary = Backend.build_ghost_snapshot("probe_ghost", {"name": "探针"})
	_ok("★★★① 快照带 chest_treasures_won", snap.has("chest_treasures_won"),
		"实得 %s" % str(snap.get("chest_treasures_won", null)))
	_ok("★★★① 快照带 chest_treasure_value", snap.has("chest_treasure_value"),
		"实得 %s" % str(snap.get("chest_treasure_value", null)))
	_ok("★★① 带的是【真实进度】不是空壳",
		(snap.get("chest_treasures_won", []) as Array).size() == 3
		and absf(float(snap.get("chest_treasure_value", 0.0)) - 12345.0) < 0.01)
	## ★快照必须是【副本】—— 直接塞引用的话, 上传后玩家再开一件箱子会把已上传的快照也改了。
	gs.chest_treasures_won.append("poison")
	_ok("★★① 快照存的是副本(玩家后续开箱不会倒灌进已建好的快照)",
		(snap.get("chest_treasures_won", []) as Array).size() == 3,
		"玩家现有 %d 件, 快照仍 %d 件" % [(gs.chest_treasures_won as Array).size(),
			(snap.get("chest_treasures_won", []) as Array).size()])

	# ── ② schema 升版 + 老快照被丢掉 ────────────────────────────────────
	_ok("★★② schema_ver 已升到 2", int(snap.get("schema_ver", 0)) == 2,
		"实得 %d" % int(snap.get("schema_ver", 0)))
	var pool := {"brackets": {"1": [
		{"ghost_id": "old_a", "schema_ver": 1},                    # 老的 → 该丢
		{"ghost_id": "old_b"},                                     # 连字段都没有 → 该丢
		{"ghost_id": "new_a", "schema_ver": Backend.SCHEMA_VER},   # 新的 → 该留
	]}}
	var dropped: int = Backend._drop_stale_schema(pool)
	var left: Array = (pool["brackets"] as Dictionary)["1"]
	_ok("★★★② 老版本快照【整批丢掉】(不做向后兼容)", dropped == 2 and left.size() == 1,
		"丢 %d 条, 剩 %d 条" % [dropped, left.size()])
	_ok("★★② 留下来的正是新版那条",
		left.size() == 1 and str((left[0] as Dictionary).get("ghost_id", "")) == "new_a")
	## ★反面分母: 全是新版时一条都不许丢(否则上一条可能只是"无差别清空")
	var pool2 := {"brackets": {"1": [
		{"ghost_id": "n1", "schema_ver": Backend.SCHEMA_VER},
		{"ghost_id": "n2", "schema_ver": Backend.SCHEMA_VER},
	]}}
	_ok("★★② 反面分母: 全新版 ⇒ 一条不丢(证明不是无差别清空)",
		Backend._drop_stale_schema(pool2) == 0
		and ((pool2["brackets"] as Dictionary)["1"] as Array).size() == 2)

	# ── ③ 内置种子队也升了版(否则一载入就被自己丢光) ──────────────────────
	var seed_txt := FileAccess.get_file_as_string("res://data/ghost_seed.json")
	var seed = JSON.parse_string(seed_txt)
	var seed_n := 0
	var seed_ok := 0
	if seed is Dictionary and (seed as Dictionary).has("brackets"):
		for b in ((seed as Dictionary)["brackets"] as Dictionary).keys():
			for g in ((seed as Dictionary)["brackets"] as Dictionary)[b]:
				seed_n += 1
				if int((g as Dictionary).get("schema_ver", 0)) >= Backend.SCHEMA_VER:
					seed_ok += 1
	_ok("★分母: 种子池里有队伍", seed_n > 0, "%d 支" % seed_n)
	_ok("★★★③ 内置种子队全部升到 schema %d(不升的话一载入就被 _drop_stale_schema 清光)" % Backend.SCHEMA_VER,
		seed_n > 0 and seed_ok == seed_n, "%d/%d 支合规" % [seed_ok, seed_n])

	# ── ④ 单场旧制那套低阈值【已删净】────────────────────────────────────
	var src := FileAccess.get_file_as_string("res://scripts/systems/skills/chest_system.gd")
	_ok("★★★④ `[80,130,240,360,590]` 这套低阈值已从代码里删净",
		src.find("80.0, 130.0, 240.0, 360.0, 590.0") < 0 and src.find("80,130,240,360,590") < 0)
	_ok("★★④ 敌方走的是与我方【同一张】阈值表 battle._CHEST_THRESH",
		src.count("battle._CHEST_THRESH[opened]") >= 3,
		"引用 %d 处(我方/敌方/评审台)" % src.count("battle._CHEST_THRESH[opened]"))
	## ★关键: 敌方分支必须【读快照的累积值】, 不是只看本场伤害。
	_ok("★★★④ 敌方起点 = 快照累积值 + 本场伤害",
		src.find('var base: float = float(u.get("_chest_ghost_value", 0.0))') >= 0
		and src.find('base + float(u.get("dmg_dealt", 0.0))') >= 0)
	var src_sp := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_spawn.gd")
	_ok("★★★④ 敌方登场时把对手【已开出的那几件】装上",
		src_sp.find('_gh.get("chest_treasures_won", [])') >= 0
		and src_sp.find('battle._chest_sys._chest_apply_treasure(u, str(_tw1))') >= 0)
	_ok("★★④ 敌方 chest_opened 从快照件数起算(不是从 0 重开)",
		src_sp.find('u["chest_opened"] = _gw.size()') >= 0)

	# ── ⑥ 玩家手打录入多套阵容: id 要按【阵容】区分, 不是按赛季 ──────────────
	##   用户 2026-08-15「我手打」。原来 `g_<赛季>` 一个大轮只有一个 id, 而 pool_add 按 id 去重
	##   ⇒ 录第二套会把第一套顶掉。改成 `g_<赛季>_<排序后的三龟>`。
	## ★判据量【函数返回值】不是源码字符串 —— 规则搬了家(战斗场 → backend)也不该红。
	var id_a: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"])
	var id_b: String = Backend.player_ghost_id(1, ["candy", "lava", "star"])
	var id_c: String = Backend.player_ghost_id(1, ["stone", "basic", "ninja"])   # 同三龟, 换顺序
	var id_d: String = Backend.player_ghost_id(2, ["basic", "ninja", "stone"])   # 换赛季
	_ok("★★★⑥ 两套【不同】阵容 ⇒ 两个不同 id", id_a != id_b, "%s vs %s" % [id_a, id_b])
	_ok("★★★⑥ 同三龟【换上场顺序】⇒ 同一个 id(不该算两套)", id_a == id_c, "%s vs %s" % [id_a, id_c])
	_ok("★★⑥ 换赛季 ⇒ 另一个 id(大轮之间不串)", id_a != id_d, "%s vs %s" % [id_a, id_d])
	var src_rb := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★★⑥ 战斗场真的调它(不是写了函数没人用)",
		src_rb.find("Backend.player_ghost_id(int(gs.season_id), gs.season_leaders)") >= 0
		and src_rb.find('var _gid := "g_%d" % int(gs.season_id)') < 0)
	## ★真的会去重/不去重 —— 量 pool_add 自己的账, 不是数源码。
	var pool_id := {"brackets": {}}
	var mk := func(gid: String) -> Dictionary:
		return {"ghost_id": gid, "bracket": 3, "schema_ver": Backend.SCHEMA_VER,
			"profile": {"name": "玩家阵容"}}
	Backend.pool_add(pool_id, mk.call(id_a))
	Backend.pool_add(pool_id, mk.call(id_b))
	var n_two: int = ((pool_id["brackets"] as Dictionary).get("3", []) as Array).size()
	_ok("★★★⑥ 两套【不同】阵容并存(录第二套不会顶掉第一套)", n_two == 2, "池里 %d 条" % n_two)
	Backend.pool_add(pool_id, mk.call(id_c))   # 同一套(换了上场顺序)重打
	var n_again: int = ((pool_id["brackets"] as Dictionary).get("3", []) as Array).size()
	_ok("★★★⑥ 同一套重打仍是【一条】(更新不堆积, 守住 2026-07-18 那条修复)",
		n_again == 2, "池里 %d 条" % n_again)

	# ── ⑦ 自测开关: 默认跳过自己的 ghost, SELF_GHOST=1 才允许匹配到 ────────────
	var self_g := {"ghost_id": "g_1_x", "profile": {"name": "玩家阵容"}}
	_ok("★★⑦ 默认仍然跳过自己录的阵容(单机撞上自己是穿帮)",
		Backend._is_self_ghost(self_g) == true)
	var src_bk := FileAccess.get_file_as_string("res://scripts/net/backend.gd")
	_ok("★⑦ 有 SELF_GHOST 开关可放开(要自测录进去的阵容)",
		src_bk.find('if OS.has_environment("SELF_GHOST"):') >= 0)

	gs.chest_treasures_won = won_bak
	gs.chest_treasure_value = val_bak
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 敌方宝箱进度进快照")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
