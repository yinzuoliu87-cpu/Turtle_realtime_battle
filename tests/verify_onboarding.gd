extends Node

## verify_onboarding.gd — 首次强制新手教学: 骨架 + 沙盒 (用户 2026-07-23)
##
## 用户:「第一次打开这个游戏现在是没有任何引导的」+「打两把…之后教学结束回主菜单, 不获得任何奖励」。
## 本测试守【阶段 A】: 首次检测触发 + 沙盒不给奖励。高亮/两把序列在后续阶段的门禁里。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	_test_flags_exist()
	await _test_sandbox_no_reward()
	_test_menu_wiring()
	print("ALL PASS — 首次教学骨架+沙盒" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 三个状态字段存在, onboarded 进存档
func _test_flags_exist() -> void:
	_ok("GameState 有 onboarded", "onboarded" in GameState)
	_ok("GameState 有 tutorial_stage", "tutorial_stage" in GameState)
	_ok("GameState 有 tutorial_active(沙盒开关)", "tutorial_active" in GameState)
	_ok("GameState 有 tutorial_mandatory(能否跳过)", "tutorial_mandatory" in GameState)
	var gs_src := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	# onboarded 必须进 save() 和 _load(), 否则重启又触发教学
	_ok("★onboarded 进了存档(save 表里有)", gs_src.contains("\"onboarded\": onboarded"))
	_ok("★onboarded 从存档读(_load 里有)", gs_src.contains("onboarded = data.get(\"onboarded\""))


## ② 沙盒: tutorial_active 为真时, 结算不给奖励(不加币不计战)
func _test_sandbox_no_reward() -> void:
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for i in 8:
		await get_tree().process_frame
	# 造一个"有赛季"的状态, 让正常情况【会】给奖励
	GameState.season_leaders = ["basic", "stone", "ninja"]
	var coins0: int = int(GameState.meta_deepsea_coins)
	var battles0: int = int(GameState.season_total_battles)

	# 先证明【非沙盒】时结算确实会动数据(否则下面"沙盒不动"是空检查)
	GameState.tutorial_active = false
	s._settle_season(true)
	var moved_normal: bool = int(GameState.season_total_battles) > battles0
	print("  [对照] 非沙盒结算: season_total_battles %d → %d" % [battles0, int(GameState.season_total_battles)])
	_ok("对照组: 非沙盒结算确实会计战(否则下条是空检查)", moved_normal)

	# 沙盒: 再结算一次, 数据不该再动
	var coins1: int = int(GameState.meta_deepsea_coins)
	var battles1: int = int(GameState.season_total_battles)
	GameState.tutorial_active = true
	s._settle_season(true)
	print("  [沙盒] 结算后: coins %d→%d, battles %d→%d" % [
		coins1, int(GameState.meta_deepsea_coins), battles1, int(GameState.season_total_battles)])
	_ok("★★沙盒结算不加深海币", int(GameState.meta_deepsea_coins) == coins1)
	_ok("★★沙盒结算不计战场数", int(GameState.season_total_battles) == battles1)

	# 复原
	GameState.tutorial_active = false
	GameState.season_leaders = []
	s.queue_free()
	await get_tree().process_frame


## ③ 主菜单接线: 首次检测 + 统一启动
func _test_menu_wiring() -> void:
	var src := _code_only(FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd"))
	_ok("★主菜单 _ready 挂了首次检测", src.contains("_maybe_first_launch_tutorial()"))
	_ok("★首次检测按 onboarded 判断(走完就不再触发)", src.contains("GameState.onboarded"))
	_ok("★启动教学时开沙盒(tutorial_active=true)", src.contains("GameState.tutorial_active = true"))
	_ok("★首次是强制的(mandatory=true)", src.contains("_begin_tutorial(true)"))
	_ok("★❓ 重玩是可跳的(mandatory=false)", src.contains("_begin_tutorial(false)"))
	# ONBOARD 开发开关(否则本机跑一次 onboarded=true 就再也测不到)
	_ok("★有 ONBOARD 环境开关(强制开/关, 供测试)", src.contains("ONBOARD"))


func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out
