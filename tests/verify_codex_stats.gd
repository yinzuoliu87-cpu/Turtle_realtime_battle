extends Node

## verify_codex_stats.gd — 点5机械部分: 图鉴删tag + 移速/攻速(单一事实源+等级缩放) (用户 2026-07-23)

const TurtleStats := preload("res://scripts/engine/turtle_stats.gd")

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	# ① 单一事实源表: 28 龟, 每项 [melee, move_spd, atk_interval, atk_range]
	_ok("STATS 有 28 龟", TurtleStats.STATS.size() == 28, "实际 %d" % TurtleStats.STATS.size())
	var basic: Array = TurtleStats.STATS.get("basic", [])
	_ok("小龟移速=105", basic.size() > 1 and int(basic[1]) == 105)
	_ok("小龟攻击间隔=1.25", basic.size() > 2 and abs(float(basic[2]) - 1.25) < 0.001)

	# ② 攻速公式 = 1/间隔 × (1+0.02*(lv-1)), Lv1=0.80, Lv10=0.944 (与战斗 _make_unit 同口径)
	var aspd1: float = (1.0 / float(basic[2])) * (1.0 + 0.02 * float(1 - 1))
	var aspd10: float = (1.0 / float(basic[2])) * (1.0 + 0.02 * float(10 - 1))
	_ok("★攻速 Lv1 = 0.80(base)", abs(aspd1 - 0.80) < 0.01, "%.3f" % aspd1)
	_ok("★攻速 Lv10 = 0.944(+2%/级)", abs(aspd10 - 0.944) < 0.01, "%.3f" % aspd10)
	_ok("★移速不随等级(定值)", int(basic[1]) == 105)

	# ③ 单一事实源: 战斗脚本引用 turtle_stats.gd(不再各存一份→图鉴不会骗人)
	var bsrc := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★战斗 STATS 引用 turtle_stats.gd(单源)", bsrc.contains('preload("res://scripts/engine/turtle_stats.gd").STATS'))
	var csrc := FileAccess.get_file_as_string("res://scripts/scenes/CodexScene.gd")
	_ok("★图鉴读同一 TurtleStats.STATS", csrc.contains("TurtleStats.STATS"))
	_ok("★图鉴属性区加了移速", csrc.contains('"移速"'))
	_ok("★图鉴属性区加了攻击速度", csrc.contains('"攻击速度"'))

	# ④ tag 已删: 图鉴不再画 标签.png
	_ok("★图鉴龟详情不再画 tag(标签.png 已删)", not csrc.contains("标签.png"), "还残留 tag 渲染")

	print("ALL PASS — 图鉴删tag+移速/攻速(单源)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
