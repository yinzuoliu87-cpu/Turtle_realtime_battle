extends Node
## verify_knock_paths_agree.gd — 让单位飞起来的【所有路径都必须尊重免击飞】
##
## ══════════════════════════════════════════════════════════════════
##  ★这条有前科：同一个坑已经漏过一次
## ══════════════════════════════════════════════════════════════════
## 用户 2026-07-19：「说好的免疫呢」——017 不沉之锚的免击飞失效。
## 当时的修法是**在 `_knock_up` 上又抄了一遍守卫**（那行注释还在：
## 「直接设 airborne 会绕过 `_knockback` 的守卫」），而**不是收口**。
##
## 2026-09-04 彻查扫出来：让单位飞起来的地方一共 **七处**
##   函数两个：`_knockback`(28 次调用) · `_knock_up`(7 次)
##   直接写字段五处：`eq_arcane_batch:577` · `headless_system:209` ·
##                   `ice_system:34` · `lava_system:302` · `lava_system:649`
##
## 当前七处**都是对的**（六处「被击飞」有守卫，一处「自己起跳」不该有），
## 但**七份副本再漂一次只是时间问题** —— 上次就漏了。本文件是那道闸。
##
## ══════════════════════════════════════════════════════════════════
##  ★★一处**故意**不设守卫，别把它当 bug 修
## ══════════════════════════════════════════════════════════════════
## `eq_arcane_batch.gd:577` 是 **090 镇海杵的「自己起跳」**（携带者跳起来再砸下去），
## 不是被别人击飞。免击飞的语义是「不被别人击飞」，**不该阻止自己跳**。
## ⇒ 本文件只验「被击飞」那几条路。写在这里是为了下一个人不会顺手"统一"掉它。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _mk(side: String, at: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, at)
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["active_skills"] = []
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	u["airborne"] = false
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 击飞: 所有【被击飞】路径都必须尊重免击飞 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var by: Dictionary = _mk("left", c + Vector2(-200, 0))

	# ── ① 免击飞：两条函数路都不该让它飞 ──
	print("── ① _knock_immune ──")
	for path in ["_knockback", "_knock_up"]:
		var v: Dictionary = _mk("right", c + Vector2(100, 0))
		## ★分母：**同一个单位**先在没有免疫时试一次，必须真的飞起来 ——
		##   否则下面的"没飞"是因为这条路本来就不生效（空检查）。
		if path == "_knockback":
			_s._damage._knockback(by, v, 40.0, 1.0, 1.0)
		else:
			_s._knock_up(v, by["pos"], 6.0)
		var base_air: bool = bool(v.get("airborne", false))
		_ok("★分母[%s]: 没有免疫时**确实飞了**" % path, base_air,
			"没飞 ⇒ 这条路压根没生效，下面是空检查")

		# 落回地面 + 上免疫，再试一次
		v["airborne"] = false
		v["vy"] = 0.0
		v["_knock_immune"] = true
		if path == "_knockback":
			_s._damage._knockback(by, v, 40.0, 1.0, 1.0)
		else:
			_s._knock_up(v, by["pos"], 6.0)
		_ok("①[%s] 带免击飞(017 不沉之锚)时**没被飞起来**" % path,
			not bool(v.get("airborne", false)),
			"飞起来了 ⇒ 免击飞对这条路无效（2026-07-19 那次漏的就是这个形状）")
		v["alive"] = false

	# ── ② 已阵亡：不该击飞尸体 ──
	## `_knock_up` 查了 `alive`，`_knockback` **没查** —— 而调用点常常是
	## 「先 `_apply_damage_from` 再 `_knockback`」，那一发要是打死了目标，
	## 就会作用在尸体上。这条断言把两条路拉到同一个标准。
	print("── ② 已阵亡不该被击飞 ──")
	for path in ["_knockback", "_knock_up"]:
		var d: Dictionary = _mk("right", c + Vector2(160, 0))
		if path == "_knockback":
			_s._damage._knockback(by, d, 40.0, 1.0, 1.0)
		else:
			_s._knock_up(d, by["pos"], 6.0)
		_ok("★分母[%s]: 活着时确实飞了" % path, bool(d.get("airborne", false)),
			"没飞 ⇒ 下面是空检查")
		d["airborne"] = false
		d["vy"] = 0.0
		d["alive"] = false                     # ★死了
		if path == "_knockback":
			_s._damage._knockback(by, d, 40.0, 1.0, 1.0)
		else:
			_s._knock_up(d, by["pos"], 6.0)
		_ok("②[%s] 已阵亡的单位**不被击飞**" % path,
			not bool(d.get("airborne", false)),
			"尸体被击飞 ⇒ 两条路的守卫不一致")

	# ── ③ 已在空中：不该二次击飞（两条路都有这条守卫，钉住它） ──
	print("── ③ 已在空中不该二次击飞 ──")
	var a2: Dictionary = _mk("right", c + Vector2(220, 0))
	_s._damage._knockback(by, a2, 40.0, 1.0, 1.0)
	_ok("★分母: 第一次确实飞了", bool(a2.get("airborne", false)))
	var vy1: float = float(a2.get("vy", 0.0))
	_s._damage._knockback(by, a2, 40.0, 3.0, 1.0)      # 用大得多的 vy 再来一次
	_ok("③ 空中不被二次击飞(vy 没被改写: %.2f)" % float(a2.get("vy", 0.0)),
		is_equal_approx(float(a2.get("vy", 0.0)), vy1),
		"vy 被改写 ⇒ 空中能被反复顶，滞空时间会叠加")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
