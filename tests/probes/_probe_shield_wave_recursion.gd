extends Node
## _probe_shield_wave_recursion.gd — 探针: 盾羁绊【怒气冲击波】双方互弹(只读, 不改产品代码)
##
## 用子类替换 `_s._shield_syn`, 在 on_damaged / _shockwave 两个入口记账(深度 / 谁打谁 / 怒气),
## 再用 Engine.capture_script_backtraces() 抓一次真栈。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_shield_wave_recursion.tscn --quit-after 3000
##   PROBE_BIG=1 额外跑 6 万血那组(原报告的栈溢出形态)

class ProbeShield extends ShieldSynergySystem:
	var depth := 0
	var max_depth := 0
	var waves := 0
	var lines: Array = []
	var bt_done := false

	func _nm(x) -> String:
		if not (x is Dictionary):
			return "-"
		return "%s%d" % ["L" if str((x as Dictionary).get("side", "")) == "left" else "R", int((x as Dictionary).get("_probe_i", -1))]

	func on_damaged(u: Dictionary, src, dmg: int) -> void:
		depth += 1
		max_depth = maxi(max_depth, depth)
		if lines.size() < 20:
			lines.append("%s[链深 %d] %s 受 %d 伤(来源 %s) · 怒气 %.0f → %.0f" % ["  ".repeat(mini(depth, 10)), depth, _nm(u), dmg, _nm(src),
				float(u.get("_shield_rage", 0.0)), float(u.get("_shield_rage", 0.0)) + float(dmg)])
		if depth == 3 and not bt_done:
			bt_done = true
			var bts: Array = Engine.capture_script_backtraces()
			print("  ── 链深 3 时的真栈(Engine.capture_script_backtraces) ──")
			for bt in bts:
				print(bt.format())
		super.on_damaged(u, src, dmg)
		depth -= 1

	func _shockwave(u: Dictionary, tier: int):
		waves += 1
		var t = battle._targeting._nearest_enemy(u)
		if lines.size() < 20:
			lines.append("%s[链深 %d] %s 放冲击波 → %s(%d 真伤 = 最大生命 %.0f × %.0f%%)" % ["  ".repeat(mini(depth, 10)), depth, _nm(u), _nm(t),
				maxi(1, int(float(u.get("maxHp", 0.0)) * float(WAVE_PCT[clampi(tier - 1, 0, 2)]))), float(u.get("maxHp", 0.0)), float(WAVE_PCT[clampi(tier - 1, 0, 2)]) * 100.0])
		return super._shockwave(u, tier)


var _s = null


func _mk(side: String, i: int, hp: float) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var x: float = -120.0 - 60.0 * float(i) if side == "left" else 120.0 + 60.0 * float(i)
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2(x, 40.0 * float(i)))
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["no_move"] = true
	u["no_basic"] = true
	u["equips"] = []
	u["eq_state"] = {}
	u["_probe_i"] = i
	_s._units.append(u)
	return u


func _case(tag: String, n_per_side: int, hp: float, tier_l: int, tier_r: int) -> void:
	print("")
	print("══ %s: 每边 %d 只 · 最大生命 %.0f · 盾档 左%d / 右%d · 左0 普攻右0 一下 400 ══" % [tag, n_per_side, hp, tier_l, tier_r])
	_s._units.clear()
	_s._pending_shots.clear()
	_s._adf_ct = 0
	var L: Array = []
	var R: Array = []
	for i in range(n_per_side):
		L.append(_mk("left", i, hp))
		R.append(_mk("right", i, hp))
	_s._synergy._by_side = {"left": ({"盾": tier_l} if tier_l > 0 else {}), "right": ({"盾": tier_r} if tier_r > 0 else {})}
	var p := ProbeShield.new(_s)
	_s._shield_syn = p
	var us0: int = Time.get_ticks_usec()
	_s._damage._apply_damage_from(L[0], R[0], 400, Color.WHITE)
	var us: int = Time.get_ticks_usec() - us0
	var dead_l := 0
	var dead_r := 0
	for u in L:
		if not u["alive"]: dead_l += 1
	for u in R:
		if not u["alive"]: dead_r += 1
	for ln in p.lines:
		print(ln)
	if p.lines.size() >= 20:
		print("  …(只打前 20 行)")
	print("  ⇒ 这【一下】普攻同步引出 冲击波 %d 发 · on_damaged 最深嵌套 %d 层 · _apply_damage_from 本帧调用 %d 次 · 耗时 %.1f ms"
		% [p.waves, p.max_depth, int(_s._adf_ct), float(us) / 1000.0])
	print("  ⇒ 同一调用内阵亡: 左 %d/%d · 右 %d/%d · 左0 血 %.0f · 右0 血 %.0f" % [dead_l, L.size(), dead_r, R.size(), float(L[0]["hp"]), float(R[0]["hp"])])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	var orig = _s._shield_syn
	_case("A 对照 · 4000 血(一发 320 < 400)", 1, 4000.0, 3, 3)
	_case("B 6000 血(一发 480 ≥ 400)", 1, 6000.0, 3, 3)
	_case("C 只有右边有盾羁绊 · 6000 血", 1, 6000.0, 0, 3)
	_case("D 5v5 · 6000 血", 5, 6000.0, 3, 3)
	_case("E 5v5 · 12000 血(一发 960 ⇒ 一次放 2 发)", 5, 12000.0, 3, 3)
	if OS.has_environment("PROBE_BIG"):
		_case("F 1v1 · 60000 血(一发 4800 ⇒ 一次放 5 发)", 1, 60000.0, 3, 3)
	_s._shield_syn = orig
	print("")
	print("PROBE DONE")
	get_tree().quit(0)
