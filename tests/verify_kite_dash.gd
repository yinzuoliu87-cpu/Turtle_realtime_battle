extends Node
## verify_kite_dash.gd —— 猎人龟翻滚 / 赛博龟智能AI 的冲刺落点(KiteDash, 2026-11-15)。
##
## 用户 11-15:「猎人龟…闪避…赛博龟…智能 AI，他们这个位移你都是一个劲的往后退…感觉不是很合理」
##   「如果你碰到一个那种远程的，别人朝你跑，那不应该就追上去吗？」「走位的话你按你思路做吧。」
## 判据(规则见 scripts/systems/skills/kite_dash.gd 头注):
##   A 目标(远程)在射程外 ⇒ 朝它冲(追上去), 冲完离它更近
##   B 近战贴脸 ⇒ 拉开距离, 但目标仍在 0.95 × 射程以内
##   C 目标恰在理想距离(远程, 没有近战威胁) ⇒ 侧移(横向位移大于纵向), 连续两次左右交替
##   D 背靠墙被近战贴脸 ⇒ 不往墙里挤: 真走出去至少半个冲刺距离
##   E 残血(retreat) ⇒ 落点比起点更接近最近队友的身后
##   F 走真入口: 猎人龟【翻滚】(`_sk_hunter_hide`)遇射程外的远程目标 ⇒ 翻滚落点朝它(原来背离它滚 ⇒ 反向验证会红)
##   G 智能AI 被动只躲近战: 远程贴近不算、近战贴近算(KiteDash.melee_within)
##   H 走真入口: 赛博龟【智能AI】(`_sk_cyber_smart`)遇射程外的远程目标 ⇒ 冲完离它更近

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _mk(id: String, side: String, p: Vector2, melee: bool) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, p)
	u["maxHp"] = 90000.0
	u["hp"] = 90000.0
	u["melee"] = melee
	u["no_move"] = true
	u["no_basic"] = true
	return u


func _reset(units: Array) -> void:
	_s._units.clear()
	for u in units:
		_s._units.append(u)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 猎人翻滚 / 赛博智能AI 冲刺落点 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var ar: Rect2 = _s.ARENA
	var cy: float = ar.position.y + ar.size.y * 0.5
	var x0: float = ar.position.x + 300.0

	# ── A 追上去 ──
	var h: Dictionary = _mk("hunter", "left", Vector2(x0, cy), false)
	var far: Dictionary = _mk("hunter", "right", Vector2(x0 + 650.0, cy), false)
	_reset([h, far])
	var rng: float = _s._eff_range(h)
	_ok("A 分母: 猎人射程 %.0f, 目标在 %.0f 码(射程外)" % [rng, 650.0], rng < 650.0)
	var dA: Vector2 = KiteDash.pick(_s, h, 250.0)
	_ok("A ★★目标在射程外 ⇒ 朝它冲(离它 %.0f → %.0f)" % [650.0, DetMath.dist(dA, far["pos"])], DetMath.dist(dA, far["pos"]) < 650.0 - 150.0)

	# ── B 近战贴脸: 拉开但不出射程 ──
	h["pos"] = Vector2(x0 + 300.0, cy)
	var mel: Dictionary = _mk("basic", "right", Vector2(x0 + 380.0, cy), true)
	_reset([h, mel])
	var dB: Vector2 = KiteDash.pick(_s, h, 250.0)
	var dbm: float = DetMath.dist(dB, mel["pos"])
	_ok("B ★★近战贴脸(80 码) ⇒ 拉开到 %.0f 码" % dbm, dbm > 80.0 + 120.0)
	_ok("B ★★拉开后目标仍在射程内(%.0f ≤ %.0f)" % [dbm, rng * KiteDash.IN_RANGE], dbm <= rng * KiteDash.IN_RANGE + 0.5)

	# ── C 理想距离 ⇒ 侧移、左右交替 ──
	h["pos"] = Vector2(x0 + 100.0, cy)
	var rgd: Dictionary = _mk("hunter", "right", Vector2(x0 + 100.0 + rng * KiteDash.IDEAL, cy), false)
	_reset([h, rgd])
	var dC1: Vector2 = KiteDash.pick(_s, h, 250.0)
	var m1: Vector2 = dC1 - (h["pos"] as Vector2)
	var dC2: Vector2 = KiteDash.pick(_s, h, 250.0)
	var m2: Vector2 = dC2 - (h["pos"] as Vector2)
	_ok("C ★★远程目标在理想距离 ⇒ 侧移(横 %.0f · 纵 %.0f)" % [absf(m1.y), absf(m1.x)], absf(m1.y) > absf(m1.x))
	_ok("C ★连续两次左右交替(%.0f / %.0f)" % [m1.y, m2.y], signf(m1.y) != signf(m2.y) and absf(m2.y) > 1.0)

	# ── D 背靠墙被近战贴脸: 不往墙里挤 ──
	h["pos"] = Vector2(ar.position.x + 70.0, cy)
	var mel2: Dictionary = _mk("basic", "right", Vector2(ar.position.x + 150.0, cy), true)
	_reset([h, mel2])
	var dD: Vector2 = KiteDash.pick(_s, h, 250.0)
	_ok("D ★★背靠墙 ⇒ 真走出去(%.0f 码 ≥ 125)" % DetMath.dist(dD, h["pos"]), DetMath.dist(dD, h["pos"]) >= 125.0)
	_ok("D 落点在场内", ar.grow(-1.0).has_point(dD))

	# ── E 残血撤到队友身后 ──
	h["pos"] = Vector2(x0, cy - 150.0)
	var ally: Dictionary = _mk("stone", "left", Vector2(x0 + 150.0, cy + 100.0), true)
	var e1: Dictionary = _mk("basic", "right", Vector2(x0 + 450.0, cy), true)
	_reset([h, ally, e1])
	var away: Vector2 = DetMath.norm((ally["pos"] as Vector2) - (e1["pos"] as Vector2))
	var behind: Vector2 = (ally["pos"] as Vector2) + away * KiteDash.BEHIND
	var dE: Vector2 = KiteDash.pick(_s, h, 250.0, {"retreat": true})
	_ok("E ★★残血 ⇒ 更接近队友身后(%.0f → %.0f)" % [DetMath.dist(h["pos"], behind), DetMath.dist(dE, behind)],
		DetMath.dist(dE, behind) < DetMath.dist(h["pos"], behind) - 60.0)

	# ── F 真入口: 猎人龟【翻滚】遇射程外的远程目标 ⇒ 朝它滚 ──
	h["pos"] = Vector2(x0, cy)
	var far2: Dictionary = _mk("hunter", "right", Vector2(x0 + 650.0, cy), false)
	_reset([h, far2])
	_s._hunter_sys._sk_hunter_hide(h)
	var rd: Vector2 = h.get("_roll_dest", h["pos"])
	_ok("F ★★★【翻滚】真入口: 射程外的远程目标 ⇒ 朝它滚(离它 650 → %.0f)" % DetMath.dist(rd, far2["pos"]), DetMath.dist(rd, far2["pos"]) < 650.0 - 150.0,
		"原来背离最近的敌人滚 ⇒ 越滚越远")

	# ── G 智能AI 被动只躲近战 ──
	var cyb: Dictionary = _mk("cyber", "left", Vector2(x0 + 200.0, cy), false)
	var rclose: Dictionary = _mk("hunter", "right", Vector2(x0 + 300.0, cy), false)
	_reset([cyb, rclose])
	_ok("G ★★远程贴近(100 码)不算威胁", not KiteDash.melee_within(_s, cyb, 130.0))
	var mclose: Dictionary = _mk("basic", "right", Vector2(x0 + 300.0, cy + 20.0), true)
	_reset([cyb, rclose, mclose])
	_ok("G ★近战贴近(102 码)算威胁", KiteDash.melee_within(_s, cyb, 130.0))

	# ── H 真入口: 赛博龟【智能AI】遇射程外的远程目标 ⇒ 冲完离它更近 ──
	cyb["pos"] = Vector2(x0, cy)
	## 目标在 500 码(赛博射程 450 之外一点): 旧打分「离最近敌人越远越好(封顶 420)」会停在 420 码以外; 目标放 700 码时旧打分对前后无所谓、碰巧也往前 ⇒ 测不出来(11-15 反向验证发现)
	var far3: Dictionary = _mk("hunter", "right", Vector2(x0 + 500.0, cy), false)
	_reset([cyb, far3])
	_s._edit_mode = false
	_s._over = false
	_s._cyber_sys._sk_cyber_smart(cyb)
	for _k in range(30):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("H ★★★【智能AI】真入口: 射程外(500 码)的远程目标 ⇒ 追进射程(500 → %.0f < 400)" % DetMath.dist(cyb["pos"], far3["pos"]),
		DetMath.dist(cyb["pos"], far3["pos"]) < 400.0, "原来只按「离最近敌人越远越好」⇒ 停在 420 码以外")

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
