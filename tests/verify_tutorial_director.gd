extends Node

## verify_tutorial_director.gd — 教程导演状态机(2026-10-07 重做: 一把战斗、删图鉴站)
##
## 用户「缩」: 选龟 → 战斗(三路) → 商店 → 背包 → 结束。没有第二把、没有图鉴站。
## 本门禁量:
##   ① 站间推进: team_select → 战斗(并武装弱对手) → 商店 → 背包 →(背包里「完成教程」走 end_tutorial)
##   ② 每个阶段挂哪套引导(steps_key_for), 非教程一律不挂
##   ③ 弱对手 / 固定阵容
##   ④ 旧版残留文件(≤0.19.559 教程中途被杀留下的真币/背包/统领): 启动时还回去并删掉; 新版进教程**不再写**它
##   ⑤ 沙盒「进」是幂等的: 连进两次, 第二次不会把教学币当成账号余额存进沙盒
## (隔离沙盒 / 三条出口逐字节相同 / 看门狗中途离开 —— 见 verify_tutorial_skip; 整条真场景 —— 见 verify_tutorial_flow_v2)

var _fail: int = 0
var _n: int = 0
const MIN_ASSERTS := 34


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	_ok("TutorialDirector autoload 在", td != null)
	if td == null:
		_done()
		return
	GameState.test_mode = true
	## 当前场景 = 主菜单替身(出口切回主菜单时不会把测试自己 free 掉)
	var menu := Node.new()
	menu.name = "MainMenu"
	menu.scene_file_path = "res://scenes/MainMenu.tscn"
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu

	# ② 非教程: 什么都不挂
	GameState.tutorial_active = false
	for sc in ["team_select", "battle", "settle", "shop", "inventory"]:
		_ok("非教程: %s 不挂引导" % sc, td.steps_key_for(sc) == "")
	_ok("非教程: next_scene_after 一律回主菜单", td.next_scene_after("shop").ends_with("MainMenu.tscn"))

	# ① 进教程 + 站间推进
	GameState.meta_deepsea_coins = 4321
	td.enter(null)
	## v5(2026-10-21 分镜 B): 进教程先到选龟屏(stage=team_select), 还没武装战斗、阵容是空的(由玩家在选龟屏点); 开局配置背包预放 2 件同名。
	_ok("★进教程: tutorial_active / stage=team_select(先选龟)", td.is_active() and td.stage() == "team_select", td.stage())
	_ok("★进教程: 阵容还空着(不预配, 选龟屏让玩家点)", GameState.left_team.is_empty() and GameState.season_leaders.is_empty(), str(GameState.left_team))
	_ok("★进教程: 还没武装教学战斗(选完龟才武装)", (GameState.dual_ghost as Dictionary).is_empty())
	_ok("★进教程: 教学币 %d" % td.TUT_COINS, int(GameState.meta_deepsea_coins) == int(td.TUT_COINS))
	var pre := 0
	for it in GameState.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == str(td.TUT_MERGE_ITEM) and int(it.get("star", 1)) == 1:
			pre += 1
	_ok("★★F3 开局配置: 沙盒背包预放 %d 件 1 星 %s" % [int(td.TUT_MERGE_PRESET), td.TUT_MERGE_ITEM], pre == int(td.TUT_MERGE_PRESET) and GameState.persistent_bench.size() == pre, "%d 件 / 背包 %d" % [pre, GameState.persistent_bench.size()])
	var coins_in: int = int(GameState.meta_deepsea_coins)
	td.enter(null)
	_ok("★⑤ 连进两次: 币仍是教学币(没把教学币当账号余额存进沙盒)", int(GameState.meta_deepsea_coins) == coins_in)
	_ok("★⑤ 连进两次: 预放件不翻倍", GameState.persistent_bench.size() == int(td.TUT_MERGE_PRESET), "%d" % GameState.persistent_bench.size())
	_ok("★v5: 选龟屏挂 team_select 那套引导", td.steps_key_for("team_select") == "team_select")
	_ok("v5: 选龟阶段战斗 / 商店不挂引导", td.steps_key_for("battle") == "" and td.steps_key_for("shop") == "")
	var d1: String = td.next_scene_after("team_select")
	_ok("★选龟确认 → 战斗", d1.ends_with("RealtimeBattle3D.tscn"), d1)
	_ok("★推进到 match1", td.stage() == "match1")
	_ok("★进战斗置 dual_active", bool(GameState.dual_active))
	var ghost: Dictionary = GameState.dual_ghost
	var la = ghost.get("lane_assign", {})
	_ok("★弱 ghost 有合法分路(上/下路非空)", la is Dictionary and not (la.get("top", []) as Array).is_empty()
		and not (la.get("bottom", []) as Array).is_empty(), str(la))
	_ok("★弱 ghost 无装备(必赢沙包)", (ghost.get("equipped", {}) as Dictionary).is_empty())
	## 2026-10-19 对局里没有摆位环节(站位在背包里摆); v3(2026-10-20) 战斗里只挂两句不阻塞提示(battle), 结算挂 settle。
	_ok("战斗阶段: 战斗挂不阻塞提示 battle, 结算挂 settle", td.steps_key_for("battle") == "battle" and td.steps_key_for("settle") == "settle")
	var d2: String = td.next_scene_after("battle")
	_ok("★★战斗打完 → 商店(只有一把, 不再有第二把)", d2.ends_with("Shop.tscn"), d2)
	_ok("推进到 shop, 挂 shop 那套", td.stage() == "shop" and td.steps_key_for("shop") == "shop")
	var offer: Array = GameState.meta_shop_offer
	_ok("★★F3 开局配置: 教程货架第 1 格 = 预放的同一件(买下凑 3 件)", not offer.is_empty() and offer[0] is Dictionary
		and str(offer[0].get("id", "")) == str(td.TUT_MERGE_ITEM), str(offer.slice(0, 2)))
	_ok("★教程货架是「本场次的货架」(商店恢复它, 不重新掷)", int(GameState.meta_shop_battles) == int(GameState.season_total_battles) and offer.size() == 10, "%d 格" % offer.size())
	_ok("商店阶段的战斗场不挂引导(不会第二次进战斗)", td.steps_key_for("battle") == "")
	var d3: String = td.next_scene_after("shop")
	_ok("★商店 → 背包", d3.ends_with("Inventory.tscn"), d3)
	_ok("推进到 inventory, 挂 inventory 那套", td.stage() == "inventory" and td.steps_key_for("inventory") == "inventory")
	_ok("★★没有图鉴站(背包之后不去图鉴)", not td.next_scene_after("inventory").ends_with("Codex.tscn"))
	var src := FileAccess.get_file_as_string("res://autoload/tutorial_director.gd")
	_ok("★导演源码里不再有图鉴站 / 第二把", not src.contains("CODEX") and not src.contains("match2"))
	td.end_tutorial("completed")
	_ok("★end_tutorial: 关沙盒 / onboarded / stage=done", not td.is_active() and bool(GameState.onboarded)
		and td.stage() == "done" and not td.in_sandbox())
	_ok("★end_tutorial: 账号币原样回来(4321)", int(GameState.meta_deepsea_coins) == 4321)

	# ③ 固定阵容 + 弱对手
	_ok("★固定阵容 3 只", td.FIXED_TEAM.size() == 3)
	_ok("★弱对手比玩家少(必赢)", td.WEAK_FOE.size() < td.FIXED_TEAM.size())

	# ④ 旧版残留
	td._residue_path = "user://__gate_tutorial_residue.dat"    # ★绝不碰玩家 user:// 里那一份
	GameState.meta_deepsea_coins = 20
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	var f := FileAccess.open(td._residue_path, FileAccess.WRITE)
	f.store_string(var_to_str({"coins": 292, "bench": [{"id": "__real__", "star": 3}], "leaders": ["candy", "ghost", "pirate"]}))
	f.close()
	_ok("分母④: 旧版残留文件造出来了", FileAccess.file_exists(td._residue_path))
	var did: bool = td.restore_residue_if_any()
	_ok("★★④ 发现旧版残留 ⇒ 还回真币 292 / 真统领", did and int(GameState.meta_deepsea_coins) == 292
		and Array(GameState.season_leaders) == ["candy", "ghost", "pirate"])
	_ok("★④ 还完就删(不会每次启动都还一遍)", not FileAccess.file_exists(td._residue_path))
	_ok("★④ 幂等: 没残留时再调不动", td.restore_residue_if_any() == false)
	GameState.test_mode = false
	td.enter(null)
	_ok("★★④ 新版进教程不写残留文件(账号存档从没被碰, 不需要它)", not FileAccess.file_exists(td._residue_path))
	td.end_tutorial("skipped")
	GameState.test_mode = true
	td._residue_path = td.SANDBOX_RESIDUE
	get_tree().current_scene = null
	menu.queue_free()
	_done()


func _done() -> void:
	GameState.tutorial_active = false
	GameState.tutorial_stage = ""
	print("  (共 %d 条断言)" % _n)
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d)" % [_n, MIN_ASSERTS])
	print("ALL PASS — 教学导演状态机" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
