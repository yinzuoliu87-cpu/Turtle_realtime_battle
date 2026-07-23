extends Node
## 自动跑一遍完整新手教学, 每站截图。给用户看"流程跑通"的工具(非门禁)。
## 跑法: SHIP=1 ONBOARD=1 DL_AUTOFIGHT=1 godot --path . res://tests/_tutorial_playthrough.tscn --quit-after 60000
##
## ★流程(用户2026-07-23定): 选龟(TeamSelect,只3只教学龟) → 双路战斗1(含摆位) → 商店 → 背包 → 图鉴 → 双路战斗2 → 菜单。
## ★战斗走 DL_AUTOFIGHT(跳摆位直接打) —— 自动播放器做不了拖拽摆位, 那课留给真玩家。此工具只验【流程跑通+每站不报错】。
## ★用真的 change_scene_to_file(不手动 add_child 3D 场景 —— 那样没有正确的渲染 world)。
## 本节点用 PROCESS_MODE_ALWAYS 常驻, 每换一站截图并驱动下一步。

var _shot := 0
var _log: Array = []
var _phase := 0        # 0未开始 1选龟 2战斗1 3商店 4背包 5图鉴 6战斗2 7菜单 8完成
var _t_enter := 0
var _busy := false     # ★重入锁: 截图是异步的(await frame_post_draw), 必须等它落盘再切场景, 否则拍到的是下一站(竞态)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	# ★关键: 我本身是 main scene(=current_scene), change_scene_to_file 会 free current_scene → 把我一起销毁,
	#   第一次切场景后 _process 就再不跑了(老版注释写了"reparent 到 root"却没实现 → 从没真跑通)。
	#   放弃 current_scene 身份 → 我仍是 root 的常驻子节点(PROCESS_MODE_ALWAYS), change_scene 换的是 current_scene, 不动我。
	var tree := get_tree()
	if tree.current_scene == self:
		tree.current_scene = null
	var td = get_node_or_null("/root/TutorialDirector")
	if td == null:
		print("  ★ 没有 TutorialDirector"); get_tree().quit(1); return
	# 开教学: 从【选龟界面】起步(第一把教选龟+站位)
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.dual_active = true
	GameState.tutorial_stage = "match1_pick"
	GameState.tutorial_mandatory = true
	GameState.onboarded = false
	GameState.dungeon_stage = 1
	GameState.dungeon_carry_hp = {}
	GameState.dungeon_dead_ids = []
	GameState.clear_team()
	td.begin_sandbox()    # 快照真经济+发教学币(供商店课, 结束还原)
	print("  [导演] 开教学 stage=%s coins=%d" % [td.stage(), GameState.meta_deepsea_coins])
	_phase = 1
	_t_enter = Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/TeamSelect.tscn")


func _shoot(tag: String) -> void:
	# ★headless 无渲染 → frame_post_draw 永不触发 → 会卡死协程且 get_image 为空。
	#   只有真窗口才截图; headless 下只记流程、不截图(否则 _shot 永不自增, 阶段门控失效)。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "C:/tmp/tut_flow_%d_%s.png" % [_shot, tag]
		img.save_png(path)
		print("  [截图] %s" % path)
	_log.append("%d. %s" % [_shot, tag])
	_shot += 1


func _cur():
	return get_tree().current_scene


func _process(_dt: float) -> void:
	if _busy:
		return          # ★正在截图/切场景(异步), 别让下一帧重入 → 否则截图和切场景抢跑
	var td = get_node_or_null("/root/TutorialDirector")
	if td == null:
		return
	var cur = _cur()
	if cur == null:
		return
	var elapsed := Time.get_ticks_msec() - _t_enter

	match _phase:
		1:  # 选龟界面: 先【等】截图落盘(拍到的确实是选龟界面), 再确认进战斗
			if elapsed > 1800:
				_busy = true
				await _shoot("1_team_select")
				# 模拟"确认": 写教学固定阵容 → 走导演进战斗1
				# ★left_team 是 Array[String] 类型属性, 必须喂 typed 数组(喂无类型 Array 会崩→函数中断→卡死)
				var lt: Array[String] = []
				for id in td.FIXED_TEAM:
					lt.append(str(id))
				GameState.left_team = lt
				GameState.season_leaders = lt.duplicate()
				GameState.dual_lineup = {}    # 清空 → 从 season_leaders 重派生
				var dest = td.next_scene_after("team_select")
				print("  [导演] 选龟确认(阵容=%s) → %s (stage=%s)" % [td.FIXED_TEAM, dest, td.stage()])
				_goto(dest, 2)
				_busy = false
		2:  # 战斗1(DL_AUTOFIGHT 自动打)
			if elapsed > 2500 and _shot == 1:
				_busy = true
				await _shoot("2_battle1")
				_busy = false
			elif (cur.get("_over") == true and elapsed > 3500) or elapsed > 9000:
				_busy = true
				var dest = td.next_scene_after("battle")
				print("  [导演] 战斗1(_over=%s) → %s (stage=%s)" % [cur.get("_over"), dest, td.stage()])
				_goto(dest, 3)
				_busy = false
		3:  # 商店
			if elapsed > 1800:
				_busy = true
				await _shoot("3_shop")
				var dest = td.next_scene_after("shop")
				print("  [导演] 商店 → %s" % dest)
				_goto(dest, 4)
				_busy = false
		4:  # 背包
			if elapsed > 1800:
				_busy = true
				await _shoot("4_inventory")
				var dest = td.next_scene_after("inventory")
				print("  [导演] 背包 → %s" % dest)
				_goto(dest, 5)
				_busy = false
		5:  # 图鉴
			if elapsed > 1800:
				_busy = true
				await _shoot("5_codex")
				var dest = td.next_scene_after("codex")
				print("  [导演] 图鉴 → %s (stage=%s)" % [dest, td.stage()])
				_goto(dest, 6)
				_busy = false
		6:  # 战斗2
			if elapsed > 2500 and _shot == 5:
				_busy = true
				await _shoot("6_battle2")
				_busy = false
			elif (cur.get("_over") == true and elapsed > 3500) or elapsed > 9000:
				_busy = true
				var dest = td.next_scene_after("battle")
				print("  [导演] 战斗2(_over=%s) → %s ; onboarded=%s active=%s" % [cur.get("_over"), dest, GameState.onboarded, GameState.tutorial_active])
				_goto(dest, 7)
				_busy = false
		7:  # 菜单
			if elapsed > 1800:
				_busy = true
				await _shoot("7_back_to_menu")
				_phase = 8
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
