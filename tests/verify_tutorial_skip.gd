extends Node

## verify_tutorial_skip.gd — 教程 = 完全隔离的沙盒; 完成 / 跳过 / 中途离开 三条出口拿到的东西完全相同
##
## 用户 2026-10-07:「教程里的商店怎么能够和账号的商店互通呢，你懂什么叫教程吗，整个教程都不应该有当前存档的东西啊」
## 方向 2(用户「行」):「跳过」= 拿到与走完教程**完全相同**的东西。
##
## ★量的是**真存档文件**(user://savegame.json 的字节), 不是内存里的某个字段:
##   ① 进教程前存一次档 → 字节 A
##   ② 教程里: GameState 必须是一份全新的教程状态(教学币/1 级/空背包/没统领), 账号的东西一样都不在
##   ③ 教程里随便改 + 显式 save() ⇒ 盘上仍是 A(一个字节都没写, 也没有 .tmp/.bak 冒出来)
##   ④ end_tutorial("completed" / "skipped" / "abandoned") ⇒ 盘上 = A 只把 onboarded 从 false 改成 true
##   ⑤ 三条出口的结果逐字节相同; 连调两次结果不变(幂等)
##   ⑥ 进程被杀(不走任何出口)⇒ 盘上仍是 A, onboarded 仍为 false(下次启动再弹选择框)
##   ⑦ 关窗(WM_CLOSE)⇒ 盘上仍是 A, 内存换回账号原状态
##   ⑧ 账号规则不变: 场次没变(商店首战后解锁那条只看它) —— 新号教程后仍是 0 场
##   ⑨ 云端: 教程期间拉回的存档不落到沙盒, 结束后落到账号上

const SAVE := "user://savegame.json"

var _fail := 0
var _menu: Node = null
var _n := 0
const MIN_ASSERTS := 40


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	_ok("★分母: TutorialDirector autoload 在", td != null)
	if td == null:
		_end()
		return
	## ★当前场景 = 一个「主菜单」替身: 出口会切回主菜单, 而当前场景若是测试自己就会被 free 掉
	##   (协程就地中止、后面的断言一条都不跑)。替身在主菜单上 ⇒ 出口不换场。
	_menu = _fake_scene("res://scenes/MainMenu.tscn")
	get_tree().current_scene = _menu
	## ★真写盘: 这一节要量的就是存档文件(独立 user://, run-tests 每测试一份)。
	GameState.test_mode = false
	_rich_account()
	GameState.onboarded = false
	GameState.save()
	## ★基线 = 「读档后再存」的那一份。JSON 读回来整数一律变 float(2 → 2.0), 所以第一次存的 2 与
	##   读档后再存的 2.0 本来就差字节 —— 那是存档格式的老样子, 与教程无关(真机上的存档也早就是这一形)。
	##   不对齐基线的话, 下面的「只差 onboarded」会被这批 .0 冒充成教程污染。
	GameState._load()
	GameState.save()
	var a := _bytes()
	_ok("★分母: 进教程前存档真的写出来了", a.size() > 200, "%d 字节" % a.size())
	var a_json: Dictionary = JSON.parse_string(a.get_string_from_utf8())
	_ok("★分母: 那份存档里 onboarded=false", a_json.get("onboarded") == false)

	var results := {}
	for reason in ["completed", "skipped", "abandoned"]:
		_restore_file(a)
		GameState._load()
		_ok("[%s] 分母: 每轮从同一份账号开始(深海币 292)" % reason, int(GameState.meta_deepsea_coins) == 292)
		if reason == "skipped":
			## 首启选择框「跳过」: 不进沙盒, 直接走出口
			td.end_tutorial("skipped")
		else:
			td.enter(null)
			_check_fresh(td, reason)
			_mutate_in_sandbox()
			GameState.save()
			_ok("★★[%s] 教程里改了一堆再 save() ⇒ 盘上一个字节都没变" % reason, _bytes() == a)
			_ok("[%s] 教程里没有冒出 .tmp" % reason, not FileAccess.file_exists(SAVE + ".tmp"))
			if reason == "abandoned":
				await _walk_away_and_back(td)
			else:
				td.end_tutorial(reason)
		results[reason] = _bytes()
		_ok("[%s] 出口理由记到了" % reason, str(td.last_end_reason) == reason, str(td.last_end_reason))
		_check_after(a, results[reason], reason)

	_ok("★★★完成 == 跳过(逐字节)", results["completed"] == results["skipped"])
	_ok("★★★完成 == 中途离开(逐字节)", results["completed"] == results["abandoned"])
	td.end_tutorial("skipped")
	_ok("★幂等: 再调一次出口, 盘上不变", _bytes() == results["skipped"])

	await _check_killed(td, a)
	_check_wm_close(td, a)
	_check_new_account_rule(td)
	_check_cloud_deferred(td)

	GameState.test_mode = true
	_end()


func _end() -> void:
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断" % [_n, MIN_ASSERTS])
	print("ALL PASS — 教程沙盒: 账号存档逐字节不变, 三条出口相同" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 一个"打过几场、有钱有装备有等级"的账号。
func _rich_account() -> void:
	GameState.meta_deepsea_coins = 292
	GameState.season_level = 5
	GameState.season_xp = 7
	GameState.season_total_battles = 3
	GameState.season_wins = 2
	GameState.hearts = 5
	GameState.season_leaders = ["candy", "ghost", "pirate"]
	GameState.persistent_bench = [{"id": "p2eq_001", "star": 2}]
	GameState.persistent_equipped = {"candy": [{"id": "p2eq_005", "star": 1}]}
	GameState.loadouts = {"candy": 1}
	GameState.dual_lineup = GameState.default_dual_lineup()
	GameState.meta_shop_offer = ["p2eq_009", "p2eq_011"]
	GameState.match_history = [{"result": "win", "lineup": ["candy"], "mode": "dual", "turn": 1}]


## ② 进来之后是一份全新的教程状态
func _check_fresh(td, tag: String) -> void:
	_ok("[%s] ★教程里: 深海币 = 教学币 %d(不是账号的 292)" % [tag, td.TUT_COINS], int(GameState.meta_deepsea_coins) == int(td.TUT_COINS))
	_ok("[%s] ★教程里: 1 级 0 经验" % tag, int(GameState.season_level) == 1 and int(GameState.season_xp) == 0)
	_ok("[%s] ★教程里: 背包 / 龟身装备是空的" % tag, GameState.persistent_bench.is_empty() and GameState.persistent_equipped.is_empty())
	_ok("[%s] ★教程里: 没有账号的统领 / 货架 / 战绩" % tag,
		(GameState.season_leaders as Array).is_empty() and GameState.meta_shop_offer.is_empty() and GameState.match_history.is_empty())
	_ok("[%s] ★教程里: 0 场(新号)" % tag, int(GameState.season_total_battles) == 0)
	_ok("[%s] 沙盒标记开着" % tag, bool(GameState.tutorial_active) and td.in_sandbox())


## 教程里会发生的事: 买经验、买装备、装上、选阵容
func _mutate_in_sandbox() -> void:
	GameState.buy_season_xp()
	GameState.persistent_bench.append({"id": "p2eq_096", "star": 1})
	GameState.persistent_equipped["basic"] = [{"id": "p2eq_004", "star": 1}]
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.loadouts = {"basic": 0}
	GameState.dual_lineup = {}


## ④ 出口之后
func _check_after(a: PackedByteArray, b: PackedByteArray, tag: String) -> void:
	var at := a.get_string_from_utf8()
	var bt := b.get_string_from_utf8()
	if bt != at.replace("\"onboarded\": false", "\"onboarded\": true"):
		var al := at.split("\n")
		var bl := bt.split("\n")
		for i in range(mini(al.size(), bl.size())):
			if al[i] != bl[i]:
				print("    [差异] 第 %d 行: A=%s | B=%s" % [i, al[i].strip_edges(), bl[i].strip_edges()])
	_ok("[%s] ★★★盘上 = 进教程前那份, 只有 onboarded false→true" % tag,
		bt == at.replace("\"onboarded\": false", "\"onboarded\": true") and bt != at,
		"A %d 字节 / B %d 字节" % [a.size(), b.size()])
	_ok("[%s] 内存: 账号原状态换回来了(292 币 / 5 级 / 原统领 / 原背包)" % tag,
		int(GameState.meta_deepsea_coins) == 292 and int(GameState.season_level) == 5
		and Array(GameState.season_leaders) == ["candy", "ghost", "pirate"]
		and GameState.persistent_bench.size() == 1)
	_ok("[%s] 内存: 教程标记收干净(tutorial_active=false / stage=done / onboarded=true / 无弱 ghost)" % tag,
		not bool(GameState.tutorial_active) and str(GameState.tutorial_stage) == "done"
		and bool(GameState.onboarded) and (GameState.dual_ghost as Dictionary).is_empty())


## 中途离开: 看门狗从真 current_scene 上看见「走出主菜单 → 回到主菜单」
func _walk_away_and_back(td) -> void:
	var keep: Node = _menu
	var shop := _fake_scene("res://scenes/Shop.tscn")
	var blank := _fake_scene("")
	var menu := _fake_scene("res://scenes/MainMenu.tscn")
	get_tree().current_scene = shop
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("[abandoned] 分母: 人在教程里那一屏时还没收(沙盒仍在)", td.in_sandbox())
	get_tree().current_scene = blank
	await get_tree().process_frame
	get_tree().current_scene = menu
	await get_tree().process_frame
	get_tree().current_scene = keep
	_ok("[abandoned] ★看门狗收了沙盒", not td.in_sandbox())
	for n in [shop, blank, menu]:
		n.queue_free()
	await get_tree().process_frame


## ⑥ 进程被杀: 不走出口 ⇒ 盘上仍是 A(onboarded=false)
func _check_killed(td, a: PackedByteArray) -> void:
	_restore_file(a)
	GameState._load()
	td.enter(null)
	_mutate_in_sandbox()
	GameState.save()
	await get_tree().process_frame
	_ok("★★进程被杀(不走出口): 盘上仍是进教程前那份, onboarded 仍为 false ⇒ 下次启动再弹框", _bytes() == a)
	td.end_tutorial("skipped")   # 收尾(本进程还活着)


## ⑦ 关窗
func _check_wm_close(td, a: PackedByteArray) -> void:
	_restore_file(a)
	GameState._load()
	td.enter(null)
	_mutate_in_sandbox()
	td._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_ok("★关窗: 盘上不变(不置 onboarded)", _bytes() == a)
	_ok("★关窗: 内存换回账号原状态, 沙盒关了", int(GameState.meta_deepsea_coins) == 292 and not td.in_sandbox()
		and not bool(GameState.tutorial_active))


## ⑧ 新号: 教程后场次仍是 0(商店「首战后解锁」那条锁只看它, 教程改不动)
func _check_new_account_rule(td) -> void:
	GameState.reset_save()
	GameState.onboarded = false
	GameState.save()
	var b0 := int(GameState.season_total_battles)
	td.enter(null)
	GameState.season_total_battles = 9   # 教程里就算有人动了它
	td.end_tutorial("completed")
	_ok("★★新号走完教程: 场次仍是 %d(账号规则不变)" % b0, int(GameState.season_total_battles) == b0 and b0 == 0)
	var mm = load("res://scripts/scenes/MainMenuScene.gd")
	_ok("分母: 主菜单商店锁判据在(_shop_block_kind)", mm != null and (mm as GDScript).source_code.contains("func _shop_block_kind"))


## ⑨ 云端拉回的存档: 教程期间不落到沙盒, 结束后落到账号上
func _check_cloud_deferred(td) -> void:
	GameState.reset_save()
	GameState.meta_deepsea_coins = 50
	GameState.save()
	td.enter(null)
	var p := GameState.cloud_payload()
	p["meta_deepsea_coins"] = 777
	GameState.apply_cloud_payload(p, 3)
	_ok("★教程期间拉回云存档: 沙盒里的币没被改(仍是教学币)", int(GameState.meta_deepsea_coins) == int(td.TUT_COINS))
	td.end_tutorial("completed")
	_ok("★结束后云存档落到账号上(777)", int(GameState.meta_deepsea_coins) == 777, "实测 %d" % int(GameState.meta_deepsea_coins))


func _bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(SAVE)


func _restore_file(a: PackedByteArray) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_buffer(a)
	f.close()


func _fake_scene(path: String) -> Node:
	var n := Node.new()
	n.name = path.get_file().get_basename() if path != "" else "Blank"
	n.scene_file_path = path
	get_tree().root.add_child(n)
	return n
