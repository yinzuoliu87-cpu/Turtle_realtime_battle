extends Node
## verify_wave_amulet_carry.gd — 043 海浪护符的双抗增减【一局内跨战场保留, 新对局重置】(2026-11-14)
##
## 用户原话:「上路你给队友加的护甲，那么终极战场，那么这个队友还是有这个护甲加成，就是相当于跨路保留，
##   但是一场对局之后就重置」。实现在 scripts/systems/equip/eq_wave_amulet.gd。
##
## ★全程走真入口(同 verify_b4_persist_across_lane): 建场 `_dl_build_lane_field`、上一路结束记幸存者
##   `_dl_snapshot_survivors`、换路清场 `_dl_clear_units`、整场结束钩子 `_equip_tick_sys.reset_match`。
## ★判据是 A/B 对照, 不跟手算的属性底数比: 同一个终极战场建两次, 一次带着上路的账, 一次在整场结束钩子清账之后;
##   两次只差这本账 ⇒ 同一只龟的双抗差值必须正好是浪墙给的那 +5 / −5(3 星)。
##   这样终极战场羁绊档位和上路不同也影响不到判据。
## ★分母: 换路后必须是全新的单位字典(is_same == false), 否则「还在」是恒真式。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_wave_amulet_carry.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RESIST3 := 5.0     ## ★写死(3 星 ±5), 不读被测常量

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _build_lane(lane: String, first: bool = false) -> void:
	if not first:
		_s._dl_sys._dl_clear_units()
	_gs.current_lane = lane
	_s._dl_sys._dl_build_lane_field()


## 这一方 id 为 pid 的统领(不是召唤 / 蛋 / 大师)。
func _find(side: String, pid: String) -> Dictionary:
	for u in _s._units:
		if str(u.get("side", "")) == side and str(u.get("id", "")) == pid and not u.get("_isEgg", false) \
				and not u.get("is_summon", false) and not u.get("is_trainer", false) and not u.get("_isMinion", false):
			return u
	return {}


## 浪墙结算全部立刻跑完(只推浪墙自己的结算表, 不推整场 sim —— 推 sim 会混进普攻 / 技能)。
## 11-14 起浪墙判定是逐步碰撞(EquipTickSystem._tide_hits): 把每道浪的钟拨到推完, 再 tick 一次 ⇒ 推完那一步结算所有还没碰到的人。
func _flush_wave() -> int:
	var n := 0
	for h in _s._equip_tick_sys._tide_hits:
		n += (h["allies"] as Array).size() + (h["enemies"] as Array).size()
		h["t"] = float(h["windup"]) + float(h["travel"])
	_s._equip_tick_sys._tick_tide_hits(0.0)
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 043 海浪护符: 双抗增减一局内跨战场保留 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	var lead: Array = _gs.season_leaders if _gs.season_leaders is Array else []
	var id0: String = str(lead[0]) if lead.size() > 0 else "stone"
	var id1: String = str(lead[1]) if lead.size() > 1 else "basic"
	var id2: String = str(lead[2]) if lead.size() > 2 else "diamond"
	_gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": id0, "slot": 0},
			{"kind": "leader", "id": id1, "slot": 1},
			{"kind": "minion", "role": "front"},
		],
		"bottom": [
			{"kind": "leader", "id": id2, "slot": 2},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "back"},
		],
	}
	_gs.dual_survivors = {"left": [], "right": []}
	_s._equip_tick_sys.reset_match()

	# ── 上路: 浪墙打一次(3 星) ─────────────────────────────
	_build_lane("top", true)
	var a: Dictionary = _find("left", id0)
	## 敌人挑【双抗最高】的统领: 底子 < 5 的话减到 0 就不再减(原规则), 测不出「减了 5」。
	var f: Dictionary = {}
	for u in _s._units:
		if str(u.get("side", "")) == "right" and not u.get("_isEgg", false) and not u.get("is_summon", false) \
				and not u.get("is_trainer", false) and not u.get("_isMinion", false):
			if f.is_empty() or float(u["base_def"]) > float(f["base_def"]):
				f = u
	_ok("★分母: 上路有我方 %s 与一只敌方统领" % id0, not a.is_empty() and not f.is_empty())
	if a.is_empty() or f.is_empty():
		_done()
		return
	var fid: String = str(f["id"])
	_ok("★分母: 敌人 %s 护甲 %.0f / 魔抗 %.0f 都 ≥ 5(否则减到 0 就停, 测不出 −5)" % [fid, float(f["base_def"]), float(f["base_mr"])],
		float(f["base_def"]) >= RESIST3 and float(f["base_mr"]) >= RESIST3)
	_ok("★分母: 建场时贴上了跨路身份键(%s / %s)" % [str(a.get("_wave_key", "")), str(f.get("_wave_key", ""))],
		str(a.get("_wave_key", "")) != "" and str(f.get("_wave_key", "")) != "")
	var a_def0: float = float(a["base_def"]); var a_mr0: float = float(a["base_mr"])
	var f_def0: float = float(f["base_def"]); var f_mr0: float = float(f["base_mr"])
	_s._equip_sys._eq_water_wave(a, 2)
	var nq: int = _flush_wave()
	_ok("★分母: 浪墙排了 %d 项结算并全部跑完" % nq, nq >= 2)
	_ok("① 上路: 我方 %s 双抗 +5(护甲 %+.0f / 魔抗 %+.0f)" % [id0, float(a["base_def"]) - a_def0, float(a["base_mr"]) - a_mr0],
		absf(float(a["base_def"]) - a_def0 - RESIST3) < 0.01 and absf(float(a["base_mr"]) - a_mr0 - RESIST3) < 0.01)
	_ok("① 上路: 敌方 %s 双抗 −5(护甲 %+.0f / 魔抗 %+.0f)" % [fid, float(f["base_def"]) - f_def0, float(f["base_mr"]) - f_mr0],
		absf(float(f["base_def"]) - f_def0 + RESIST3) < 0.01 and absf(float(f["base_mr"]) - f_mr0 + RESIST3) < 0.01)
	_ok("★分母: 两只都活着进幸存名单", a.get("alive", false) and f.get("alive", false))
	_s._dl_sys._dl_snapshot_survivors()

	# ── 终极战场(带着上路的账) ─────────────────────────────
	_build_lane("final")
	var a1: Dictionary = _find("left", id0)
	var f1: Dictionary = _find("right", fid)
	_ok("★分母: 终极战场里找到了同一只我方 %s 与敌方 %s" % [id0, fid], not a1.is_empty() and not f1.is_empty())
	if a1.is_empty() or f1.is_empty():
		_done()
		return
	_ok("★★分母: 是【全新的单位字典】(is_same(旧,新) == false)", not is_same(a, a1) and not is_same(f, f1))
	var with_a := [float(a1["base_def"]), float(a1["base_mr"])]
	var with_f := [float(f1["base_def"]), float(f1["base_mr"])]

	# ── 整场结束钩子清账 → 同一个终极战场再建一次(对照) ──────────
	_s._equip_tick_sys.reset_match()
	_build_lane("final")
	var a2: Dictionary = _find("left", id0)
	var f2: Dictionary = _find("right", fid)
	_ok("★分母: 对照组也找到了这两只", not a2.is_empty() and not f2.is_empty())
	if a2.is_empty() or f2.is_empty():
		_done()
		return
	var da: Array = [with_a[0] - float(a2["base_def"]), with_a[1] - float(a2["base_mr"])]
	var dfo: Array = [with_f[0] - float(f2["base_def"]), with_f[1] - float(f2["base_mr"])]
	_ok("★★★② 终极战场: 我方 %s 仍带着上路的 +5 双抗(比清账后的同一只多 护甲 %+.0f / 魔抗 %+.0f)" % [id0, da[0], da[1]],
		absf(float(da[0]) - RESIST3) < 0.01 and absf(float(da[1]) - RESIST3) < 0.01)
	_ok("★★★② 终极战场: 敌方 %s 仍带着上路的 −5 双抗(比清账后的同一只 护甲 %+.0f / 魔抗 %+.0f)" % [fid, dfo[0], dfo[1]],
		absf(float(dfo[0]) + RESIST3) < 0.01 and absf(float(dfo[1]) + RESIST3) < 0.01)
	_ok("★★★③ 整场结束清账后再建: 账是空的(新对局不带上一局)", (_s._equip_sys._wave._carry as Dictionary).is_empty())
	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 海浪护符双抗跨路保留" if _fail == 0 else "FAIL x%d — 海浪护符双抗跨路保留" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
