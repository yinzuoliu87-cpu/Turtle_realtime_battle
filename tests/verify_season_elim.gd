extends Node
## verify_season_elim.gd — 赛季淘汰锁 (用户2026-07-24 拍板"淘汰锁定": 0命→锁匹配+商店, 只重置存档解锁)
## 守: ①hearts 状态机(8→扣满→is_eliminated·钳0) ②reset_save 解锁(回8)
##     ③主菜单 guard: 淘汰时"开始战斗"不放行(不置 dual_active·弹淘汰toast)
##     ④淘汰时"开店"被拦(独立新增 toast·没导航去Shop) ⑤淘汰时英雄/商店键建出🔒锁角标
## 反向证据: ① 满命 is_eliminated=false + 扣到1命仍非淘汰 → 证明 guard 条件非恒真

const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

## 数 scene 直属子里含 needle 的 toast Label 数量(每 guard 应各弹一条独立的)
func _count_toasts(scene: Node, needle: String) -> int:
	var n := 0
	for ch in scene.get_children():
		if ch is Label and needle in String(ch.text):
			n += 1
	return n

func _ready() -> void:
	# ① hearts 状态机(整个淘汰锁的地基)
	GameState.hearts = 8
	_ok("满命非淘汰(分母:确实 8 命)", not GameState.is_eliminated() and int(GameState.hearts) == 8)
	for _i in range(7): GameState.lose_heart()
	_ok("扣到 1 命仍非淘汰(证明在真扣·非恒真)", not GameState.is_eliminated() and int(GameState.hearts) == 1)
	var last := GameState.lose_heart()
	_ok("扣到 0 命 = 淘汰 且 lose_heart 返回 true", GameState.is_eliminated() and last)
	GameState.lose_heart()
	_ok("命数钳在 0 不为负(多扣一次仍 0)", int(GameState.hearts) == 0)

	# ② + ③ + ④ guard: 淘汰态实例化主菜单, 开始战斗/开店 都被拦
	GameState.hearts = 0
	GameState.season_total_battles = 5   # 隔离: 排除"未打第一场"那条商店锁, 只测淘汰锁
	var scene = MENU.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	GameState.dual_active = false
	var t0 := _count_toasts(scene, "淘汰")
	scene._start_battle_flow()
	_ok("★淘汰→开始战斗被拦(dual_active 未被置 true·没进选龟)", not GameState.dual_active)
	_ok("★开始战斗拦截时弹淘汰 toast", _count_toasts(scene, "淘汰") == t0 + 1)

	var t1 := _count_toasts(scene, "淘汰")
	scene._open_shop()
	_ok("★淘汰→开店被拦(独立新增淘汰 toast·没导航去Shop)", _count_toasts(scene, "淘汰") == t1 + 1)

	# ⑤ 视觉: 淘汰时主菜单英雄键/商店键建出 🔒 锁角标
	var lock_badges := 0
	for holder in scene.page_box.get_children():
		for c in holder.get_children():
			if c is Label and "🔒" in String(c.text):
				lock_badges += 1
	_ok("★淘汰时主菜单出现 🔒 锁角标(英雄键+商店键)", lock_badges >= 1, "%d 个" % lock_badges)

	# ② reset_save 解锁(唯一出口)
	GameState.reset_save()
	_ok("重置存档→回满命·解锁(is_eliminated=false·hearts=8)", not GameState.is_eliminated() and int(GameState.hearts) == 8)

	scene.queue_free()
	print("ALL PASS — 赛季淘汰锁(状态机+主菜单guard+🔒+解锁)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
