extends Node
## 自动跑一遍完整新手教学, 每站截图。给用户看"流程跑通"的工具(非门禁)。
## 跑法: SHIP=1 ONBOARD=1 godot --path . res://tests/_tutorial_playthrough.tscn --quit-after 30000
##
## ★用真的 change_scene_to_file(不手动 add_child 3D 场景 —— 那样没有正确的渲染 world)。
## 本节点用 PROCESS_MODE_ALWAYS 常驻, 靠 tree_changed 感知场景切换, 每换一站截图并驱动下一步。

var _shot := 0
var _log: Array = []
var _phase := 0        # 0未开始 1战斗1 2商店 3背包 4图鉴 5战斗2 6菜单 7完成
var _t_enter := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 常驻(不随场景切换销毁): reparent 到 root, 但 root 的 current_scene 会换
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	if td == null:
		print("  ★ 没有 TutorialDirector"); get_tree().quit(1); return
	# 开教学
	GameState.mode = "single"
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1"
	GameState.tutorial_mandatory = true
	GameState.onboarded = false
	GameState.clear_team()
	print("  [导演] 开教学 stage=%s" % td.stage())
	_phase = 1
	_t_enter = Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "C:/tmp/tut_flow_%d_%s.png" % [_shot, tag]
	img.save_png(path)
	_log.append("%d. %s" % [_shot, tag])
	print("  [截图] %s" % path)
	_shot += 1


func _cur():
	return get_tree().current_scene


func _process(_dt: float) -> void:
	var td = get_node_or_null("/root/TutorialDirector")
	if td == null:
		return
	var cur = _cur()
	if cur == null:
		return
	var elapsed := Time.get_ticks_msec() - _t_enter

	match _phase:
		1:  # 战斗1: 等它加载好截图, 再等打完
			if elapsed == 0:
				return
			if elapsed > 1500 and _shot == 0:
				_shoot("1_battle1")
			# 打完(或超时) → 去下一站
			if (cur.get("_over") == true and elapsed > 2500) or elapsed > 12000:
				var dest = td.next_scene_after("battle")
				print("  [导演] 战斗1(_over=%s) → %s" % [cur.get("_over"), dest])
				_goto(dest, 2)
		2:  # 商店
			if elapsed > 1800:
				_shoot("2_shop")
				var dest = td.next_scene_after("shop")
				print("  [导演] 商店 → %s" % dest)
				_goto(dest, 3)
		3:  # 背包
			if elapsed > 1800:
				_shoot("3_inventory")
				var dest = td.next_scene_after("inventory")
				print("  [导演] 背包 → %s" % dest)
				_goto(dest, 4)
		4:  # 图鉴
			if elapsed > 1800:
				_shoot("4_codex")
				var dest = td.next_scene_after("codex")
				print("  [导演] 图鉴 → %s (stage=%s)" % [dest, td.stage()])
				_goto(dest, 5)
		5:  # 战斗2
			if elapsed > 1500 and _shot == 4:
				_shoot("5_battle2")
			if (cur.get("_over") == true and elapsed > 2500) or elapsed > 12000:
				var dest = td.next_scene_after("battle")
				print("  [导演] 战斗2(_over=%s) → %s ; onboarded=%s active=%s" % [cur.get("_over"), dest, GameState.onboarded, GameState.tutorial_active])
				_goto(dest, 6)
		6:  # 菜单
			if elapsed > 1800:
				_shoot("6_back_to_menu")
				_phase = 7
				_finish()


func _goto(path: String, next_phase: int) -> void:
	_phase = next_phase
	_t_enter = Time.get_ticks_msec()
	get_tree().change_scene_to_file(path)


func _finish() -> void:
	print("")
	print("  ═══ 完整流程 ═══")
	for l in _log: print("    " + str(l))
	print("  收尾: onboarded=%s(应true) tutorial_active=%s(应false)" % [GameState.onboarded, GameState.tutorial_active])
	print("  PLAYTHROUGH DONE")
	get_tree().quit(0)
