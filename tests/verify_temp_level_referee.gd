extends Node
## verify_temp_level_referee —— 临时等级器在服务器局里生效(2026-11-06)。
##
## 查出来的: 文案「本大轮该单位永久 +1 级」; 裁判开局把 candy_temp_levels 写死成 {}, 小将的 temp_lv 也不进快照 ⇒ 积分赛上裁判机后用了等于没用。
## 判据(真裁判入口):
##   A 快照带上 temp_levels(只带用过的)+ 小将 temp_lv
##   B ★同一局: 左方统领 +2 级 ⇒ 这只龟的最大生命 = 基线 × 等级倍率之比; 没用的龟不变(分母)
##   C ★右方同一条规则: 对手快照带 temp_levels ⇒ 对手那只同样放大
##   D ★小将: 左方小将 temp_lv ⇒ 生命变大
##   E 夹子: 别人传的快照写 999 ⇒ 按 10 算; 负数 / 不是数 ⇒ 0

const Backend := preload("res://scripts/net/backend.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fails := 0
var _n := 0
var _gs
var _b = null
var _hp := {}


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if d == "" else "  " + d))
	if not c:
		_fails += 1


func _on_battle(b) -> void:
	_b = b


## 只取开局第一眼的最大生命: 之后会被装备 / 技能改。
func _process(_d: float) -> void:
	if _b == null or not is_instance_valid(_b):
		return
	for u in _b._units:
		var k := "%s/%s" % [str(u.get("side", "")), str(u.get("id", ""))]
		if not _hp.has(k):
			_hp[k] = float(u.get("maxHp", 0.0))


func _snap_a(tl: Dictionary, minion_tl: int) -> Dictionary:
	_gs.start_new_season()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(["basic", "stone", "bamboo"])
	_gs.persistent_equipped = {}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": [], "temp_lv": minion_tl}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	_gs.candy_temp_levels = tl.duplicate()
	return Backend.build_ghost_snapshot("g_tl_a", {"name": "甲方", "avatar": "basic", "id": "g_tl_a"})


func _run(a: Dictionary, b: Dictionary) -> Dictionary:
	_b = null
	_hp = {}
	var job = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet", "key": {"week": 1},
		"seed": 77, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))
	var res: Dictionary = await RefereeRunner.run(self, job, _on_battle)
	_b = null
	return {"res": res, "hp": _hp.duplicate()}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	_gs.tutorial_active = false
	var keep: int = P2.now_override_ts
	P2.now_override_ts = P2.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600

	var a0 := _snap_a({}, 0)
	var a1 := _snap_a({"basic": 2}, 3)
	_ok("A 快照带上 temp_levels / 小将 temp_lv", int((a1.get("temp_levels", {}) as Dictionary).get("basic", 0)) == 2
		and int(((a1["minions"] as Dictionary)["top"] as Array)[0].get("temp_lv", 0)) == 3, str(a1.get("temp_levels")))
	_ok("A 没用过 ⇒ 没这个键(与机器人同形)", not a0.has("temp_levels"))
	var b: Dictionary = BP.one(16, 0, 0, 0)
	b["gl_ts"] = int(P2.now_utc()) - 300
	var foe := str((b.get("leaders", []) as Array)[0])
	var r0: Dictionary = await _run(a0, b)
	_ok("分母: 基线一局跑通", bool((r0["res"] as Dictionary).get("ok", false)), str((r0["res"] as Dictionary).get("error", "")))
	var b1: Dictionary = b.duplicate(true)
	b1["temp_levels"] = {foe: 2}
	var r1: Dictionary = await _run(a1, b1)
	_ok("分母: 带临时等级一局跑通", bool((r1["res"] as Dictionary).get("ok", false)), str((r1["res"] as Dictionary).get("error", "")))
	var h0: Dictionary = r0["hp"]
	var h1: Dictionary = r1["hp"]
	print("  基线 left/basic %.0f right/%s %.0f | 带等级 left/basic %.0f right/%s %.0f" % [float(h0.get("left/basic", 0)), foe, float(h0.get("right/" + foe, 0)), float(h1.get("left/basic", 0)), foe, float(h1.get("right/" + foe, 0))])
	var UM = load("res://scripts/combat/unit_scaling.gd")
	var lvl_a := int(a0.get("season_level", 1))
	var lvl_b := int(b.get("season_level", 1))
	## 按龟等级(2026-11-09): 对手快照带 lv 表 ⇒ 这只的底子是它自己的龟等级(机器人池 = 1 级), 临时等级加在它上面
	if TurtleLevel.level_in(TurtleLevel.table_of(b.get("lv")), foe) >= 1:
		lvl_b = TurtleLevel.level_in(TurtleLevel.table_of(b.get("lv")), foe)
	var want_a: float = float(UM.level_multiplier(lvl_a + 2)) / float(UM.level_multiplier(lvl_a))
	var want_b: float = float(UM.level_multiplier(lvl_b + 2)) / float(UM.level_multiplier(lvl_b))
	var got_a: float = float(h1.get("left/basic", 0.0)) / maxf(1.0, float(h0.get("left/basic", 0.0)))
	var got_b: float = float(h1.get("right/" + foe, 0.0)) / maxf(1.0, float(h0.get("right/" + foe, 0.0)))
	_ok("B ★左方 +2 级 ⇒ 最大生命按等级倍率放大(要 %.3f 实测 %.3f)" % [want_a, got_a], absf(got_a - want_a) < 0.02)
	_ok("B 分母: 没用的龟不变", absf(float(h1.get("left/stone", 0.0)) - float(h0.get("left/stone", -1.0))) < 1.0)
	_ok("C ★右方同一条规则(要 %.3f 实测 %.3f)" % [want_b, got_b], absf(got_b - want_b) < 0.02)
	var mkey := "left/__minion__"
	_ok("D ★左方小将 temp_lv ⇒ 生命变大", float(h1.get(mkey, 0.0)) > float(h0.get(mkey, 0.0)) * 1.05, "%.0f → %.0f" % [float(h0.get(mkey, 0.0)), float(h1.get(mkey, 0.0))])
	_ok("E 快照写 999 ⇒ 夹到 10", Backend.ghost_temp_level({"temp_levels": {"x": 999}}, "x") == 10)
	_ok("E 负数 / 不是数 / 没这个键 ⇒ 0", Backend.ghost_temp_level({"temp_levels": {"x": -3}}, "x") == 0
		and Backend.ghost_temp_level({"temp_levels": {"x": "9"}}, "x") == 0 and Backend.ghost_temp_level({}, "x") == 0)
	P2.now_override_ts = keep
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
