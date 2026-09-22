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
	var t0 := _count_toasts(scene, "出局")
	scene._start_battle_flow()
	_ok("★淘汰→开始战斗被拦(dual_active 未被置 true·没进选龟)", not GameState.dual_active)
	_ok("★开始战斗拦截时弹出局 toast", _count_toasts(scene, "出局") == t0 + 1)

	var t1 := _count_toasts(scene, "出局")
	scene._open_shop()
	_ok("★淘汰→开店被拦(独立新增出局 toast·没导航去Shop)", _count_toasts(scene, "出局") == t1 + 1)

	# A4(2026-09-17): quota-full is a SECOND lock reason, separate from 0-heart.
	#   The toast keyword moved from the old one to a new one, so the counter above
	#   follows the product wording. Counting by wording is fragile by nature - that is
	#   exactly why this block also asserts dual_active stays false: wording can drift,
	#   but "the player must not get into a match" cannot.
	GameState.hearts = 8                 # not eliminated - isolate the quota reason
	GameState.season_total_battles = 5
	GameState.week_phase = "ranked"
	GameState.ranked_used = 0
	_ok("A4 denominator: quota not full yet", not GameState.ranked_quota_full())
	## The POSITIVE case cannot go through _start_battle_flow(): when the guard passes it
	## calls _go("TeamSelect") and CHANGES THE SCENE, which tears down this test tree
	## (first version of this block did exactly that - the file still printed ALL PASS but
	## left one SCRIPT ERROR "Cannot call method quit on a null value" at the very end).
	## So: assert the predicate for the allowed case, and reserve the real entry for the
	## BLOCKED cases below - those return early and never navigate, which is the half
	## that actually matters (a blocked player must not reach a match).
	_ok("A4 denominator: quota not full => guard says allowed", not GameState.ranked_quota_full())
	GameState.ranked_used = 999          # full
	_ok("A4 quota full is detected", GameState.ranked_quota_full())
	GameState.dual_active = false
	## ★ the needle comes from the product's own message builder, not a hardcoded
	##   substring: the wording already changed once (2026-09-22 - the toast used to
	##   promise "wait for Saturday's gauntlet", a mode that does not exist yet).
	##   A copy of the string kept here would have to be edited in lockstep forever
	##   (memory `fb-hand-rolled-copies-drift`).
	var needle: String = str(scene._msg_quota_full()).substr(2, 6)
	_ok("A4 denominator: needle from _msg_quota_full() is non-empty",
		needle.strip_edges() != "", "needle=[%s]" % needle)
	var q1 := _count_toasts(scene, needle)
	scene._start_battle_flow()
	_ok("A4 quota full => battle blocked (dual_active stays false)", not GameState.dual_active)
	_ok("A4 quota full => quota toast shown", _count_toasts(scene, needle) == q1 + 1)
	var q2 := _count_toasts(scene, needle)
	scene._open_shop()
	_ok("A4 quota full => shop blocked too (user decision)", _count_toasts(scene, needle) == q2 + 1)
	GameState.ranked_used = 0            # restore for the rest of this file

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
