extends Node
## verify_gold_shield.gd — 财神·金盾必须走得通实战路径(用户 2026-07-31)
##
## 用户原话:「财神龟的金盾压根没生效吗」「实战里面金盾就是没生效」
##
## ★★根因(探针实证, 不是读代码猜的): `_cast_skill` 里这一段
##     if stype == "fortuneAllIn" and u.get("allin_used", false):
##         return int(u.get("gold", 0)) > 0
##   本意是"0 金币不空放"的【前置检查】, 却写成了 return ——
##   于是梭哈用过之后【整个 _do_skill 都跑不到】, 金盾从来没生效过。
##   更糟: 它返回 true, 调用方照样扣冷却 → 80 龟能白花, 表现是"放了但什么都没发生"。
##   探针实测: 走 _cast_skill 护盾=0 / gold_shield_until=0;
##            直接调 _sk_fortune_goldshield 则 40 / 4.37 —— 效果函数本身一直是好的。
##
## ★所以这条门禁【必须走 _cast_skill】而不是直接调效果函数 ——
##   直接调的话这个 bug 一辈子测不出来(这正是它能活到今天的原因)。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_gold_shield.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 财神·金盾(梭哈用过后该技变金盾) ===")
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame

	var u = s._spawn._make_unit("fortune", "left", Vector2(700.0, 470.0))
	var e = s._spawn._make_unit("basic", "right", Vector2(760.0, 470.0))
	s._units.append(u)
	s._units.append(e)
	_ok("① ★分母: 造出财神龟与靶子", u != null and e != null)

	# ── ② 梭哈还没用过时, 放的是梭哈(不是金盾) ──
	u["gold"] = 40.0
	u["allin_used"] = false
	u["shield"] = 0.0
	var ok1: bool = s._cast_skill(u, e, "fortuneAllIn")
	_ok("② 梭哈未用过 → 放得出梭哈, 并标记 allin_used",
		ok1 and bool(u.get("allin_used", false)), "返回=%s allin_used=%s" % [ok1, u.get("allin_used", false)])

	# ── ③ ★★核心: 梭哈用过后, 走【实战路径 _cast_skill】必须真的上盾 ──
	u["allin_used"] = true
	u["gold"] = 40.0
	u["shield"] = 0.0
	u["gold_shield_until"] = 0.0
	var t0: float = s._t
	var ok2: bool = s._cast_skill(u, e, "fortuneAllIn")
	_ok("③ ★★经 _cast_skill 真的上了护盾(不是只返回 true 就完事)",
		float(u.get("shield", 0.0)) > 0.0,
		"护盾 = %.0f (期望 = 金币数40 × 5 = 200)" % float(u.get("shield", 0.0)))
	# ★需求字面值写在这里(不引用 GOLD_SHIELD_MULT) —— 引用常量就是拿代码跟它自己比。
	#   用户 2026-08-01:「盾量改为金币数乘5」⇒ 40 金 × 5 = 200。
	_ok("③ ★护盾量 = 金币数 × 5(需求字面值)", absf(float(u.get("shield", 0.0)) - 200.0) < 0.5,
		"%.0f vs 200" % float(u.get("shield", 0.0)))
	_ok("③ ★持盾期已开(gold_shield_until > 当前时钟) —— 持盾锁龟能靠它判",
		float(u.get("gold_shield_until", 0.0)) > t0,
		"until=%.2f  _t=%.2f" % [float(u.get("gold_shield_until", 0.0)), t0])
	_ok("③ 返回 true(调用方据此扣冷却)", ok2)

	# ── ④ 0 金币时不空放: 返回 false 且不上盾(否则 80 龟能白花) ──
	u["allin_used"] = true
	u["gold"] = 0.0
	u["shield"] = 0.0
	u["gold_shield_until"] = 0.0
	var ok3: bool = s._cast_skill(u, e, "fortuneAllIn")
	_ok("④ ★0 金币不空放: 返回 false", not ok3)
	_ok("④ ★0 金币时也没上盾", float(u.get("shield", 0.0)) <= 0.0,
		"护盾 = %.0f" % float(u.get("shield", 0.0)))

	# ── ⑤ 分母: 效果函数本身是好的(证明 ③ 测的是【接线】不是效果) ──
	u["shield"] = 0.0
	u["gold_shield_until"] = 0.0
	u["gold"] = 25.0
	s._fortune_sys._sk_fortune_goldshield(u)
	_ok("⑤ ★分母: 直接调效果函数也能上盾(③ 若红说明是【接线】断了, 不是效果坏了)",
		absf(float(u.get("shield", 0.0)) - 125.0) < 0.5,
		"护盾 = %.0f" % float(u.get("shield", 0.0)))

	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条)" % _n)
	print("ALL PASS — 财神金盾走得通实战路径" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
