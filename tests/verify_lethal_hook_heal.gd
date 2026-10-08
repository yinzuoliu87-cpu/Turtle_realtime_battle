## verify_lethal_hook_heal.gd — 致命一击不能被受击钩子里回的那点血救活(2026-10-08 用户「天使龟有不死bug」)
##
## ★由来(重放用户那局实测): 敌方天使龟带护心甲 082(受击反伤)+ 生命偷取。被打到 0 之后、`_kill` 之前,
##   反伤以【被打的这只】为来源再结算一次伤害, 生命偷取当场给它回 0.04 血 ⇒ `hp <= 0` 不成立 ⇒ 不死。
##   每次挨打都重演: 血条空着、人照样动, 从第 27 秒挂到第 60 秒。
## ★修法(battle_damage 两条路): 扣血 + 正规免死处理完之后立刻记下 `_lethal`, 最后以它为准。
##   附带: `_kill` 开头记死亡处理计数 —— 反伤链里内层已经处理过一次死亡(复活)时, 外层不许拿过期的 `_lethal` 补刀。
##
## 判据量真实单位、走真伤害入口 `_apply_damage_from`, 反伤用通用反伤字段 `reflect`(与护心甲同一类: 受击即以自己为来源打回去)。
##   A  受害方 反伤 + 生命偷取, 1 血挨一刀 ⇒ 必须死(修复前: 活着, 血量 0.0x)
##   A0 分母: 反伤与生命偷取真的发生了(攻击方掉血 / 受害方回过血)
##   B  受害方再带天使祝福复活, 攻击方带暴君之牙(命中处决 ⇒ 钩子里内层先死一次) ⇒ 复活一次后活着, 血量 ≈ 25%(修复的第一版会被外层补刀打死)
##   C  DoT 路径(_apply_damage)同一判据: 1 血吃一跳 ⇒ 死
## 跑法: <godot> --headless --path . res://tests/verify_lethal_hook_heal.tscn --quit-after 3000
extends Node

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DT := 1.0 / 60.0

var _n := 0
var _fail := 0
var s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	gs.dual_active = true
	gs.current_lane = "top"
	gs.lane_results = {}
	print("=== 致命一击不被受击钩子救活 ===")
	s = RB.new()
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)
	s._over = false
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	s._dl_sys._dl_start_fight()
	for _i in range(2):
		s._sim_step(DT, false, false)

	# ── A: 反伤 + 生命偷取, 1 血挨一刀 ──
	var atk := _unit("basic", "left", Vector2(-200, 0))
	var vic := _unit("angel", "right", Vector2(-120, 0))
	vic["reflect"] = 0.5
	vic["lifesteal"] = 0.2
	vic["hp"] = 1.0
	var atk_hp0 := float(atk["hp"])
	var vic_ls0 := float(vic.get("_st_heal", 0.0))
	s._damage._apply_damage_from(atk, vic, 200, Color.WHITE)
	_ok("A0 ★分母: 反伤真的打回去了(攻击方 %.0f → %.0f)" % [atk_hp0, float(atk["hp"])], float(atk["hp"]) < atk_hp0)
	_ok("A0 ★分母: 受害方的生命偷取真的回过血(承疗统计 %.2f → %.2f)" % [vic_ls0, float(vic.get("_st_heal", 0.0))],
		float(vic.get("_st_heal", 0.0)) > vic_ls0)
	_ok("★★A 1 血挨 200 ⇒ 死(反伤时的生命偷取救不了命)", not vic.get("alive", true),
		"alive=%s hp=%.3f" % [str(vic.get("alive")), float(vic["hp"])])

	# ── B: 再带祝福复活; 攻击方带暴君之牙(004 命中处决) ⇒ 受击钩子里【内层】先处理一次死亡(复活),
	#    外层不许再拿过期的「致命」补刀(修复第一版就栽在这: 重放里复活后当场又死) ──
	var atk2 := _unit("basic", "left", Vector2(-200, 120))
	atk2["equips"] = [{"id": "p2eq_004", "star": 3}]
	atk2["eq_state"]["p2eq_004"] = {}
	var vic2 := _unit("angel", "right", Vector2(-120, 120))
	vic2["reflect"] = 0.5
	vic2["lifesteal"] = 0.2
	vic2["_angel_revive"] = true
	vic2["hp"] = 1.0
	s._damage._apply_damage_from(atk2, vic2, 200, Color.WHITE)
	var pct := float(vic2["hp"]) / float(vic2["maxHp"])
	_ok("B0 ★分母: 复活真的触发了(reborn_used)", bool(vic2.get("reborn_used", false)))
	_ok("B0 ★分母: 这一击里死亡处理恰好发生 1 次(_kill_n=%d)" % int(vic2.get("_kill_n", 0)), int(vic2.get("_kill_n", 0)) == 1)
	_ok("★★B 复活一次后活着, 血量≈25%%(没被外层过期的「致命」补刀): alive=%s hp=%.0f/%.0f" % [str(vic2.get("alive")), float(vic2["hp"]), float(vic2["maxHp"])],
		vic2.get("alive", false) and pct > 0.15)

	# ── C: DoT 路径同一判据 ──
	var vic3 := _unit("angel", "right", Vector2(-120, 240))
	vic3["hp"] = 1.0
	s._damage._apply_damage(vic3, 50, Color.WHITE, atk, "tru", false)
	_ok("★C DoT 路径: 1 血吃一跳 50 ⇒ 死", not vic3.get("alive", true), "alive=%s hp=%.3f" % [str(vic3.get("alive")), float(vic3["hp"])])

	print("ALL PASS — 致命一击判定 (%d 项)" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


func _unit(id: String, side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit(id, side, c + off)
	s._units.append(u)
	u["shield"] = 0.0
	return u
