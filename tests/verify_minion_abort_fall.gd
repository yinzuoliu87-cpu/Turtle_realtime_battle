extends Node
## verify_minion_abort_fall.gd — 人体浪板中途夭折, 小将必须落回地面
##
## 由来(2026-08-21, 用户报):「还有小将如果跳起时敌人死亡小将会飞到天上」。
##
## 根因(读代码确诊, 带行号): `hiding_system._sk_minion_bodysurf` 的起跳 tween 把
## `height` 抬到 5.76 后【故意悬停不落】(注释原文"到顶悬停(不落)"), 等 `_minion_bodysurf_ride`
## 把它拉下来。而 0.68s / 1.28s 两个 `_pending_shots` 的提前返回分支只写了
## `uu["_slam"] = false; return` —— **height 一个字没碰**。
## 全局那个 `if u["height"] <= 0.0: u["height"] = 0.0` 只在【击飞路径】(airborne)里跑,
## 本技能不走击飞 ⇒ 没有任何人会把它放下来 ⇒ 永远挂在天上。
##
## ★判据不数"我有没有调 _minion_abort_fall", 而是**量产品自己的账**: 直接读 `height`。
##   (铁律: 断言自己插的触发标记 = 插一行数一行必绿。)
## ★等效果用**游戏时钟推进的帧**, 不等 tween —— 归零走的是 `_pending_shots`(sim 驱动),
##   正是为了让这条测试不依赖 tween(CLAUDE.md §3.5: 无头 CI 下 tween 推进不稳)。

const HS := preload("res://scripts/systems/skills/hiding_system.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _done(scn) -> void:
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 人体浪板夭折落地" if _fail == 0 else "FAIL")
	if scn != null:
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	print("=== 人体浪板中途夭折 → 小将必须落地 ===")

	var hs = scn._hiding_sys
	_ok("★分母: hiding_system 在场", hs != null)
	if hs == null:
		_done(scn)
		return

	# 干净合成单位(不用随机 spawn 的真单位: CI 会因队伍未播种 RNG 偶发红)
	var mn := {
		"id": "__minion__", "side": "left", "alive": true, "pos": Vector2(400, 300),
		"hp": 750.0, "maxHp": 750.0, "atk": 42.0, "height": 0.0,
		"buffs": [], "dots": [], "equips": [], "eq_state": {},
	}
	var foe := {
		"id": "basic", "side": "right", "alive": true, "pos": Vector2(700, 300),
		"hp": 500.0, "maxHp": 500.0, "atk": 30.0, "height": 0.0,
		"buffs": [], "dots": [], "equips": [], "eq_state": {},
	}
	## ★不要 append 进 `scn._units`: 那会让每帧的 tick/渲染去读这两个字典, 而合成单位
	##   缺 `untargetable_until`/`sprite`/`stun_until` 等键 ⇒ 每帧刷报错(实测 411 条,
	##   门禁的致命正则会命中 ⇒ rc=0 却判 FAIL)。
	##   本技能全程只操作传进去的字典本身, **不需要它们在 _units 里**, 所以不塞。

	hs._sk_minion_bodysurf(mn, foe)

	# ① 等它真的跳起来(量产品自己的 height, 不数标记)
	var w := 0
	while w < 900 and float(mn.get("height", 0.0)) <= 0.5:
		await get_tree().process_frame
		w += 1
	var h_apex: float = float(mn.get("height", 0.0))
	_ok("★分母: 小将确实跳到了空中(height > 0.5)", h_apex > 0.5, "height=%.2f" % h_apex)
	if h_apex <= 0.5:
		_done(scn)
		return

	# ② 半空中把目标弄死 —— 用户描述的那一刻
	foe["alive"] = false
	foe["hp"] = 0.0

	# ③ 等落地。上限给足(0.68s 那一支之后还有 1.28s 那一支, 再加 FALL_T)
	w = 0
	while w < 1800 and float(mn.get("height", 0.0)) > 0.01:
		await get_tree().process_frame
		w += 1
	var h_end: float = float(mn.get("height", 0.0))
	print("     跳到 %.2f → 目标死亡 → 等了 %d 帧 → height=%.3f" % [h_apex, w, h_end])
	_ok("★★目标半空死亡后, 小将落回地面(height 归零)", h_end <= 0.01, "height=%.3f" % h_end)
	_ok("★夭折后解锁 AI(_slam 已清)", not bool(mn.get("_slam", false)))

	_done(scn)
