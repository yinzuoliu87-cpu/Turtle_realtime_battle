extends Node

## verify_trainer_place.gd — 点6: 训龟大师摆位阶段不可拖 + 不投掷 (用户 2026-07-23)
## 直接 .new() 战斗脚本, 测两个抽出的纯函数(不起 3D 场景):
##   _trainer_ticks_active()   — 大师的移动/攻击 tick 现在该不该跑

const Battle := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	var b = Battle.new()   # 裸实例, 不加进树 → 不跑 _ready(不 spawn)

	# (原 ① `_can_place_drag`: 2026-10-19 对局里没有拖动站位了(站位在背包里摆, 背包只列阵容格子, 大师不在里面),
	#   那个函数随之删除。)
	# ② _trainer_ticks_active: 战斗中才跑, 摆位/呈现/编辑/结束都停
	b._over = false; b._edit_mode = false
	b._dl_state = "fight"
	_ok("战斗中大师 tick 跑", b._trainer_sys._trainer_ticks_active() == true)
	b._dl_state = "place"
	_ok("★摆位期大师不 tick(不投掷不移动·点6核心)", b._trainer_sys._trainer_ticks_active() == false)
	b._dl_state = "overview"
	_ok("呈现(总览)期不 tick", b._trainer_sys._trainer_ticks_active() == false)
	b._dl_state = "preview"
	_ok("呈现(预览)期不 tick", b._trainer_sys._trainer_ticks_active() == false)
	b._dl_state = "fight"; b._over = true
	_ok("战斗结束不 tick", b._trainer_sys._trainer_ticks_active() == false)
	b._over = false; b._edit_mode = true
	_ok("编辑期不 tick", b._trainer_sys._trainer_ticks_active() == false)

	b.free()
	print("ALL PASS — 训龟大师摆位(不可拖+不投掷)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
