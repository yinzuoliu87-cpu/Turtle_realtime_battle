extends Node
## verify_readouts_d7.gd — 080 直升机龟能 / 079 炮台金弹进度 / 086 浮游炮攻击计数进装备图标框(第九批 D7)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来 (2026-09-15, 077~086 调查)
## ══════════════════════════════════════════════════════════════════
## 这三件的核心进度在 `EquipReadouts` 两张表里一个字都没有 ⇒ 局内图标框零读数,
## 玩家看不到直升机攒了多少龟能、炮台离下一发金弹还差几发、浮游炮离终极射线还差几次。
## (用户 2026-08-08 铁律:「充能条和层数不要放头顶, 在装备图标框里」)
##
## ★判据: 【每一步】核对「携带者身上的镜像 == 源头真实值」, 不只看最后一眼
##   (只看最后一眼的话, 中途一直错、最后一刻碰巧对也会绿)。
## ★全部走真入口: 登场钩子 `_b4_on_spawn_all` 生成召唤物, `tick_global` 推在途表,
##   `_eq_tick` 推逐单位钩子, `_step_pending_shots` 推排队的弹。
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


func _mk(id: String, side: String, off: Vector2, hp: float = 900000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["dodge_bonus"] = 0.0
	_s._units.append(u)
	return u


func _mirror(u: Dictionary, eid: String, field: String) -> float:
	return float(((u.get("eq_state", {}) as Dictionary).get(eid, {}) as Dictionary).get(field, 0.0))


func _reset_field() -> void:
	if _s._equip_sys._gun_sys.has_method("clear_all"):
		_s._equip_sys._gun_sys.clear_all()
	_s._units.clear()
	_s._synergy._by_side = {"left": {}, "right": {}}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 装备图标框读数: 080 直升机龟能 / 079 炮台金弹进度 / 086 浮游炮攻击计数 (第九批 D7) ===")
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	var gun = _s._equip_sys._gun_sys

	# ── ① 读数表 ──
	var want := {"p2eq_080": "heli_en", "p2eq_079": "gold_pct", "p2eq_086": "shots_pct"}
	for eid in want.keys():
		var row: Array = EquipReadouts.CHARGE.get(eid, [])
		_ok("① 充能条表里有 %s → %s / 分母 100(实测 %s)" % [eid, want[eid], str(row)],
			row.size() >= 2 and str(row[0]) == str(want[eid]) and absf(float(row[1]) - 100.0) < 0.01,
			"表里没有 ⇒ 图标框零读数")

	# ── ② 080 直升机龟能 ──
	_reset_field()
	var o80: Dictionary = _mk("basic", "left", Vector2(-120.0, 0.0))
	_mk("green", "right", Vector2(160.0, 0.0))
	o80["equips"] = [{"id": "p2eq_080", "star": 3}]
	o80["eq_state"] = {}
	_s._equip_sys._stats._b4_on_spawn_all()
	var helis: Array = gun._helis
	_ok("★分母②: 登场钩子真的生成了直升机(%d 架)" % helis.size(), helis.size() >= 1, "")
	var bad80 := 0
	var max_en := 0.0
	var saw_reset := false
	var prev_en := 0.0
	if helis.size() >= 1:
		var h: Dictionary = helis[helis.size() - 1]
		for _k in range(160):
			_s._equip_sys.tick_global(0.05)
			_s._ballistics._step_pending_shots(0.05)
			var en: float = float(h.get("energy", 0.0))
			max_en = maxf(max_en, en)
			if prev_en >= 90.0 and en < 1.0:
				saw_reset = true
			prev_en = en
			if absf(_mirror(o80, "p2eq_080", "heli_en") - en) > 0.01:
				bad80 += 1
	_ok("★分母②: 龟能真的在涨(最高 %.0f)· 真的满过一次又清零(%s)" % [max_en, str(saw_reset)],
		max_en >= 50.0 and saw_reset, "没涨/没清零 ⇒ 下面只验到了 0 == 0")
	_ok("② 080 160 步里每一步: 携带者身上的读数 == 直升机龟能(对不上 %d 步)" % bad80, bad80 == 0, "")

	# ── ③ 079 炮台金弹进度 ──
	for tier in [1, 0]:
		_reset_field()
		gun._towers.clear()
		var o79: Dictionary = _mk("basic", "left", Vector2(-120.0, 0.0))
		var e79: Dictionary = _mk("green", "right", Vector2(260.0, 0.0))
		_s._synergy._by_side = {"left": {"枪": tier} if tier > 0 else {}, "right": {}}
		o79["equips"] = [{"id": "p2eq_079", "star": 3}]
		o79["eq_state"] = {}
		_s._equip_sys._stats._b4_on_spawn_all()
		var tws: Array = gun._towers
		var tu: Dictionary = (tws[tws.size() - 1] as Dictionary)["u"] if tws.size() > 0 else {}
		var hp0: float = float(e79["hp"])
		var max_ct := 0
		var saw_zero_after := false
		for _k in range(120):
			_s._equip_sys.tick_global(0.05)
			_s._ballistics._step_pending_shots(0.05)
			var ct: int = int((tu.get("_gun_shot_ct", {}) as Dictionary).get("p2eq_079", 0))
			if max_ct > 0 and ct == 0:
				saw_zero_after = true
			max_ct = maxi(max_ct, ct)
		## ★★第一版推完 6 秒直接排空, 计数正好回到 0 ⇒ 判的是「读数 0 == 0 ÷ 4 × 100」——
		##   不写镜像读数默认也是 0, 恒真式。⇒ 先把计数推到【正好停在 2】(不是 0, 也没到出金弹的 4)再停手排空。
		var guard := 0
		while tier == 1 and int((tu.get("_gun_shot_ct", {}) as Dictionary).get("p2eq_079", 0)) != 2 and guard < 200:
			guard += 1
			_s._equip_sys.tick_global(0.05)
			_s._ballistics._step_pending_shots(0.05)
		for _k in range(40):                           # 停止开火, 把在途的弹排空(镜像在弹落地时写)
			_s._ballistics._step_pending_shots(0.05)
		var ct_end: int = int((tu.get("_gun_shot_ct", {}) as Dictionary).get("p2eq_079", 0))
		var mir: float = _mirror(o79, "p2eq_079", "gold_pct")
		if tier == 1:
			_ok("★分母③: 炮台在场、打出去了(目标掉血 %.0f)· 计数攒过(最高 %d)又清零过(%s)· 停在 %d" % [hp0 - float(e79["hp"]), max_ct, str(saw_zero_after), ct_end],
				tws.size() >= 1 and hp0 - float(e79["hp"]) > 0.0 and max_ct >= 1 and saw_zero_after and ct_end == 2,
				"计数没停在 2 ⇒ 下面又变回 0 == 0")
			_ok("③ 079 枪羁绊 1 档: 计数停在 2 ⇒ 读数 %.1f 应为 50(= 2 ÷ 4 × 100)" % mir,
				absf(mir - 50.0) < 0.01, "")
		else:
			_ok("③ 079 反证: 枪羁绊没激活时炮台照样开火(目标掉血 %.0f), 读数恒 0(实测 %.1f)" % [hp0 - float(e79["hp"]), mir],
				hp0 - float(e79["hp"]) > 0.0 and absf(mir) < 0.01, "兑不了现的进度不给玩家看")

	# ── ④ 086 浮游炮攻击计数 ──
	_reset_field()
	var o86: Dictionary = _mk("basic", "left", Vector2(-120.0, 0.0))
	_mk("green", "right", Vector2(200.0, 0.0))
	o86["equips"] = [{"id": "p2eq_086", "star": 3}]
	o86["eq_state"] = {}
	_s._equip_sys._stats._b4_on_spawn_all()
	var bad86 := 0
	var max_shots := 0
	for _k in range(240):
		_s._equip_sys._eq_tick(o86, 0.05)
		_s._ballistics._step_pending_shots(0.05)
		var shots: int = int(((o86.get("eq_state", {}) as Dictionary).get("p2eq_086", {}) as Dictionary).get("shots", 0))
		max_shots = maxi(max_shots, shots)
		if absf(_mirror(o86, "p2eq_086", "shots_pct") - float(shots) / 20.0 * 100.0) > 0.01:
			bad86 += 1
	_ok("★分母④: 浮游炮真的在打(计数最高 %d)" % max_shots, max_shots >= 3, "没打 ⇒ ④ 只验到了 0 == 0")
	_ok("④ 086 3★ 240 步里每一步: 读数 == 计数 ÷ 20 × 100(对不上 %d 步)" % bad86, bad86 == 0, "")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
