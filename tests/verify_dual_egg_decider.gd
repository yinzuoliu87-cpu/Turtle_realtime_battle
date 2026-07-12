extends Node
## verify_dual_egg_decider.gd — 双路定局判定 + 蛋跨路掉血可见(用户2026-07-12)
##   ① _dl_is_decider: 定局路=终极路 或 横扫定胜负那一路(此路胜方=已赢另一路) → 挂终极buff+无限窗口, 打碎蛋才结束
##   ② 蛋 maxHp=原始满血 / 当前hp=跨路累积受损值 → 血条显 1800/2500 而非满条
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n, c, d=""):
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)

	# ── ① _dl_is_decider ──
	gs.current_lane = "final"; gs.lane_results = {"top": "left", "bottom": "right"}
	_ok("终极路 wiped=left → 定局", sc._dl_is_decider("left") == true)
	_ok("终极路 wiped=right → 定局", sc._dl_is_decider("right") == true)

	gs.current_lane = "top"; gs.lane_results = {}
	_ok("上路 wiped=left → 非定局", sc._dl_is_decider("left") == false)
	_ok("上路 wiped=right → 非定局", sc._dl_is_decider("right") == false)

	# 下路: 横扫 = 本路胜方(wiped的对手) 上路也赢
	gs.current_lane = "bottom"; gs.lane_results = {"top": "left"}
	_ok("下路 上路left赢·wiped=right(本路left赢) → 横扫定局(2-0)", sc._dl_is_decider("right") == true)
	_ok("下路 上路left赢·wiped=left(本路right赢) → 非定局(1-1)", sc._dl_is_decider("left") == false)

	gs.current_lane = "bottom"; gs.lane_results = {"top": "right"}
	_ok("下路 上路right赢·wiped=left(本路right赢) → 横扫定局(0-2)", sc._dl_is_decider("left") == true)
	_ok("下路 上路right赢·wiped=right(本路left赢) → 非定局(1-1)", sc._dl_is_decider("right") == false)

	# ── ② 蛋 maxHp=满血 / hp=累积受损值 ──
	var egg: Dictionary = sc._make_unit("__egg__", "left", Vector2(140, 400), {"egg": true, "egg_side": "left", "hp": 1800.0, "hp_max": 2500.0})
	_ok("蛋 maxHp=原始满血(2500)", is_equal_approx(float(egg["maxHp"]), 2500.0), "maxHp=%d" % int(egg["maxHp"]))
	_ok("蛋 当前hp=累积受损值(1800)", is_equal_approx(float(egg["hp"]), 1800.0), "hp=%d" % int(egg["hp"]))
	_ok("蛋血条比例<满(掉血可见)", float(egg["hp"]) < float(egg["maxHp"]))
	# hp 超出 hp_max 时 clamp 到 maxHp (满血起手不会溢出)
	var egg2: Dictionary = sc._make_unit("__egg__", "right", Vector2(1600, 400), {"egg": true, "egg_side": "right", "hp": 9999.0, "hp_max": 2500.0})
	_ok("蛋 hp 溢出被 clamp 到 maxHp", is_equal_approx(float(egg2["hp"]), 2500.0), "hp=%d" % int(egg2["hp"]))

	# ── ③ 结算比分带本路待记结果(赢上路即显1-0, record在5秒后lane_over才调) ──
	gs.lane_results = {}
	_ok("赢上路(lane_results空)+待记top=left → 显1-0", sc._dl_record_line("top", "left") == "本场比分   我方 1 - 0 对方", sc._dl_record_line("top", "left"))
	gs.lane_results = {"top": "left"}
	_ok("已记top=left + 下路待记left → 2-0", sc._dl_record_line("bottom", "left") == "本场比分   我方 2 - 0 对方")
	_ok("已记top=left, 待记又传top(不重复计) → 仍1-0", sc._dl_record_line("top", "left") == "本场比分   我方 1 - 0 对方")
	_ok("无待记(结束横幅口径)读纯lane_results → 1-0", sc._dl_record_line() == "本场比分   我方 1 - 0 对方")

	print("")
	print(("ALL PASS — 定局判定(终极/横扫) + 蛋跨路掉血可见" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
