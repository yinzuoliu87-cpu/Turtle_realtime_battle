extends Node
## verify_tentacle_relocate.gd — 灵物触手【转移阵地】（2026-08-04）
##
## 用户 2026-08-04：「触手攻击范围内没有敌人持续一秒后，触手会钻入地下消失，
##   然后从可攻击的目标附近再重新破土而出」。
##
## ★为什么单独一条：这个机制我**先写了 `relocate()` 却零调用者** ——
##   典型的"写进去了没人读"（memory [[fb-write-without-reader-and-fake-gates]]）。
##   `verify_tentacle_vfx` 全绿，因为它只测状态机、不测"有没有人触发它"。
##   ⇒ 本文件的判据全部落在**真实位置变化**上，不是"函数存在"。
##     memory [[fb-verify-must-run-the-real-path]]：断言函数存在守不住"还有没有人调"。
##
## 守五条（四条各自反向验证过，见每条注释）：
##   ① ★射程内【有】敌人时【不搬】——搬了就是乱搬
##   ② ★射程内【没】敌人满 1 秒 → 真的搬（`root_pos` 变了，不是只改了个标志）
##   ③ ★搬完之后【够得着】那个敌人（否则搬了个寂寞）
##   ④ ★全场没有敌人时【不搬】（没目标就没有"可攻击目标附近"这个概念）
##   ⑤ ★搬家走的是【钻地 → 重新破土】，不是瞬移（中途会经过撤场/出土态）
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_relocate.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")
const SP := preload("res://scripts/systems/equip/spirit_synergy_system.gd")

var _n := 0
var _fail := 0
var _s
var _v
var _sp


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 造一个不会动、不还手、打不死的靶子，放在指定位置
func _dummy(side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, pos)
	u["maxHp"] = 999999.0
	u["hp"] = 999999.0
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	_s._units.append(u)
	return u


## 让本方灵物档位 > 0。
## ⚠ `_side_tier` 是**遍历本方单位**算出来的（`tier_for(u, "灵物")`）——
##   我第一版直接写 `_synergy._by_side`，本方一个单位都没有 ⇒ 档位恒 0 ⇒
##   `_reloc_tick` 一进来就 `continue`，**`relocate()` 一次都没被调用**，
##   而 ⑤ 那条却"PASS"了（它看到的撤场其实是 `ensure(side, 0)` 掉档造成的）——
##   典型的**假 PASS**。所以这里必须造真正的携带者，走真实档位链路。
func _carrier() -> Dictionary:
	var eq: Array = []
	for e in DataRegistry.phase2_equipment:
		if _s.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "灵物":
			eq.append({"id": str((e as Dictionary)["id"]), "star": 1})
		if eq.size() >= 5:
			break
	var u: Dictionary = _dummy("left", Vector2(_s.ARENA.position.x + 120.0,
		_s.ARENA.position.y + _s.ARENA.size.y * 0.5))
	u["equips"] = eq
	u["eq_state"] = {}
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 转移阵地 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_v = _s._tentacle_vfx
	_sp = _s._synergy_spirit if "_synergy_spirit" in _s else null
	if _sp == null:
		for prop in _s.get_property_list():
			var pn: String = str(prop.get("name", ""))
			if pn.find("spirit") >= 0:
				_sp = _s.get(pn)
				break
	_ok("★分母: 拿到 spirit 系统与触手系统", _sp != null and _v != null,
		"spirit=%s" % str(_sp))
	if _sp == null:
		get_tree().quit(1)
		return

	# ══ ① 射程内有敌人 → 不搬 ══════════════════════════════
	_s._units.clear()
	_v.clear()
	_v.ensure("left", 1)
	_v.tick(2.2)                                      # 走完出土 → 待机
	var rng: float = float(_v.attack_range_2d)
	var r0: Vector2 = _v.root_pos("left", 0)
	var near: Dictionary = _dummy("right", r0 + Vector2(rng * 0.6, 0.0))
	_carrier()
	for i in range(40):
		_sp.tick(0.05)                                # 累计 2 秒 > 1 秒阈值
	var r1: Vector2 = _v.root_pos("left", 0)
	# ★反向验证：把 `_reloc_tick` 里的"有敌人就清零"删掉后本条 FAIL（实测）
	_ok("① ★射程内有敌人时【不搬】(乱搬 = 触手到处乱跑)",
		r1.distance_to(r0) < 1.0, "位移 %.0f 码" % r1.distance_to(r0))

	# ══ ② 射程内没敌人满 1 秒 → 真的搬 ══════════════════════
	# 把靶子挪到射程外（但场上仍有敌人 —— 这是"够不着"不是"没有"）
	near["pos"] = r0 + Vector2(rng * 2.1, 0.0)
	var before: Vector2 = _v.root_pos("left", 0)
	for i in range(10):
		_sp.tick(0.05)                                # 0.5 秒 < 阈值
	_ok("② ★不到 1 秒【先不搬】(阈值是 %.1f 秒)" % SP.RELOC_IDLE_T,
		_v.root_pos("left", 0).distance_to(before) < 1.0)
	for i in range(20):
		_sp.tick(0.05)                                # 累计 1.5 秒 > 阈值
	# ⚠ `relocate()` 只设标记；**位置要等钻地演出结束才写进 `root`**。
	#   不喂完动画就量，量到的还是旧位置（第一版就是这么误报的）。
	_v.tick(TV.T_RETRACT + 0.05)
	var moved: Vector2 = _v.root_pos("left", 0)
	# ★反向验证：把 `tv.relocate(...)` 那行注释掉后本条 FAIL（实测）
	_ok("② ★空转满 %.1f 秒 → 真的搬了(根部位置变了)" % SP.RELOC_IDLE_T,
		moved.distance_to(before) > 50.0,
		"只挪了 %.0f 码" % moved.distance_to(before))

	# ══ ③ 搬完够得着 ═══════════════════════════════════════
	# ⚠ `relocate` 走的是【钻地→破土】，位置在撤场结束那一刻才写进去。
	#   所以要把动画喂完再量（不喂完量到的还是旧位置）。
	_v.tick(TV.T_EMERGE_MOVE + 0.05)
	var dest: Vector2 = _v.root_pos("left", 0)
	var d2f: float = dest.distance_to(Vector2(near["pos"]))
	# ★反向验证：把 RELOC_NEAR 改成 3.0（搬到射程外）后本条 FAIL
	_ok("③ ★搬完之后【够得着】那个敌人(距离 %.0f ≤ 射程 %.0f)" % [d2f, rng],
		d2f <= rng * 1.02, "距离 %.0f / 射程 %.0f" % [d2f, rng])

	# ══ ④ 全场没敌人 → 不搬 ════════════════════════════════
	# ⚠ 只杀【敌人】，本方携带者必须活着 ——
	#   第一版把所有单位都设成死的，本方携带者一死档位就归 0，
	#   `_reloc_tick` 一进来就 `continue`，**根本没走到"没敌人"这条判断** ⇒
	#   反向验证实测 0 FAIL = 恒真式。
	for u in _s._units:
		if u is Dictionary and str((u as Dictionary).get("side", "")) == "right":
			(u as Dictionary)["alive"] = false
	var b4: Vector2 = _v.root_pos("left", 0)
	for i in range(40):
		_sp.tick(0.05)
	# ★反向验证：把 `if best == null: continue` 删掉后本条 FAIL（会搬到 NaN/原点）
	# ★★判据用【有没有下达搬家指令】(`relocate_to` 键)，不是【位置有没有变】——
	#   位置要等钻地演出结束才写入，而这里只喂了 `_sp.tick`（不推进 `_v` 的动画），
	#   所以"位置没变"是必然的 ⇒ 反向验证实测 0 FAIL = 恒真式。
	#   探针确认过：这一刻确实走到了"到点要搬 敌数=0"，拦截点就是 `best == null`。
	var t4: Dictionary = _v._tents.get("left|0", {})
	_ok("④ ★全场没有敌人时【不下搬家指令】(没目标就没有'目标附近'这回事)",
		not t4.has("relocate_to") and _v.state_of("left", 0) == 1,
		"has_relocate_to=%s 状态=%d" % [t4.has("relocate_to"), _v.state_of("left", 0)])

	# ══ ⑤ 搬家是【钻地→破土】不是瞬移 ══════════════════════
	_s._units.clear()
	_v.clear()
	_v.ensure("left", 1)
	_v.tick(2.2)
	var far: Dictionary = _dummy("right", _v.root_pos("left", 0) + Vector2(rng * 2.1, 0.0))
	_carrier()
	for i in range(30):
		_sp.tick(0.05)
	# 刚下达搬家指令 → 应该在【撤场】态(5)，而不是已经站在新位置
	# ★★这条第一版是【假 PASS】：只看"状态==5(撤场)"，而掉档 `ensure(side,0)`
	#   也会把触手打进撤场态 —— 探针实测 `relocate()` 一次都没被调用，它照样绿。
	#   ⇒ 必须同时断言 `relocate_to` 这个键在（只有搬家才会设它）。
	var t5: Dictionary = _v._tents.get("left|0", {})
	_ok("⑤ ★搬家走【钻地】演出，且确实是【搬家】不是掉档撤场",
		_v.state_of("left", 0) == 5 and t5.has("relocate_to"),
		"状态 %d / has_relocate_to=%s" % [_v.state_of("left", 0), t5.has("relocate_to")])
	_v.tick(TV.T_RETRACT + 0.02)
	_ok("⑤ ★钻完地【重新破土】(出土态)", _v.state_of("left", 0) == 0,
		"状态 %d(期望 0=出土)" % _v.state_of("left", 0))
	_ok("⑤ ★搬家的破土比【登场】快(%.1fs vs %.1fs)" % [TV.T_EMERGE_MOVE, TV.T_EMERGE],
		TV.T_EMERGE_MOVE < TV.T_EMERGE)

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 触手转移阵地" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
