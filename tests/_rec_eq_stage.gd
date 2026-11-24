extends Node
## 装备演示台录像(不是门禁, 2026-11-24)。用户 11-24:「我不建议你这么去录…一整把一整把录…我们应该专门的这个演示台…去录视频」
##   「在小台上，你能摆放一个友方单位…可以是小龟，可以是任何召唤物。同样，我们有个敌方的靶子…观察特效会很方便」。
## 走真调试场(DEBUG_EDIT): 按 CASES 里那一条写好摆位存档(单独存档目录里的 user://debug_setup.json) → 进调试场(自动恢复摆位)
##   → 折叠编辑面板 → 点「开始」同一个入口(_edit_start_battle) → 录 REC_SEC 秒收工。
## 跑法(右屏、静音、单独存档目录; 一条一段):
##   APPDATA=<目录> XDG_DATA_HOME=<目录> SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " REC_CASE=cracker WINDOW=1 \
##     bash godot-quiet.sh --path . --resolution 1280x720 --position 2000,80 --write-movie <输出>/cracker.avi --fixed-fps 30 \
##     res://tests/_rec_eq_stage.tscn
## 摆位: 场地中心 (868,474); 我方在左、靶子在右。字段同调试场存档: id / side / px / py / hp / killable / equips / minion / role /
##   ghost_eq(召唤物笔刷: 隐形携带者带这件) / ai(敌方会动会打) / fe(满龟能)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const C := Vector2(868, 474)


static func _eq(ids: Array, star: int = 3) -> Array:
	var a: Array = []
	for i in ids:
		a.append({"id": "p2eq_%03d" % int(i), "star": star})
	return a


static func _u(id: String, side: String, d: Vector2, extra: Dictionary = {}) -> Dictionary:
	var u := {"id": id, "side": side, "px": C.x + d.x, "py": C.y + d.y, "hp": 6000.0, "killable": side == "left", "equips": []}
	u.merge(extra, true)
	return u


## 三只站桩靶子(一前两侧, 挨得近好看范围伤害)
static func _dummies(dx: float = 120.0, ai: bool = false, hp: float = 20000.0, atk: float = 0.0) -> Array:
	var o: Array = []
	for d in [Vector2(dx, 0), Vector2(dx + 70, -70), Vector2(dx + 70, 70)]:
		o.append(_u("basic", "right", d, {"hp": hp, "killable": ai, "ai": ai, "atk": atk}))
	return o


static func cases() -> Dictionary:
	return {
		"missile": [_u("basic", "left", Vector2(-260, -80), {"equips": _eq([97, 98, 99])}), _u("stone", "left", Vector2(-260, 80), {"equips": _eq([101, 103, 104])})] + _dummies(80) + [_u("basic", "right", Vector2(320, 0), {"hp": 20000.0, "killable": false})],
		"cracker": [_u("basic", "left", Vector2(-60, 0), {"equips": _eq([97])})] + _dummies(0),
		"tube": [_u("stone", "left", Vector2(-40, 0), {"equips": _eq([98])})] + _dummies(-20),
		"grenade": [_u("basic", "left", Vector2(-300, 0), {"equips": _eq([99])})] + _dummies(120),
		"smoke": [_u("basic", "left", Vector2(-200, -40), {"equips": _eq([100])}), _u("bamboo", "left", Vector2(-200, 60))] + _dummies(150, true, 8000.0),
		"sticky": [_u("basic", "left", Vector2(-260, 0), {"equips": _eq([101])})] + _dummies(120, true, 30000.0),
		"mine": [_u("stone", "left", Vector2(-400, 0), {"equips": _eq([102]), "hp": 40000.0, "killable": false, "hold": true})] + _dummies(250, true, 20000.0),
		"barrel": [_u("basic", "left", Vector2(-60, 0), {"equips": _eq([103]), "hp": 1500.0, "hold": true})] + _dummies(40, true, 20000.0, 200.0),
		"timer": [_u("basic", "left", Vector2(-260, 0), {"equips": _eq([104])})] + _dummies(120),
		"cannon": [_u("__summon__", "left", Vector2(-260, 0), {"ghost_eq": "p2eq_105", "equips": _eq([105]), "minion": true, "fe": true})] + _dummies(160),
		"remote": [_u("__summon__", "left", Vector2(-300, 0), {"ghost_eq": "p2eq_106", "equips": _eq([106], 1), "minion": true})] + _dummies(150),
		"katana": [_u("__summon__", "left", Vector2(-160, 0), {"ghost_eq": "p2eq_107", "equips": _eq([107]), "minion": true, "fe": true})] + _dummies(60),
	}


var _b = null
var _el := 0.0
var _max := 14.0
var _started := false


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var case := OS.get_environment("REC_CASE") if OS.has_environment("REC_CASE") else "cracker"
	if OS.has_environment("REC_SEC"):
		_max = float(OS.get_environment("REC_SEC"))
	var units: Array = cases().get(case, [])
	if units.is_empty():
		print("[REC] 没有这个演示: ", case)
		get_tree().quit(1)
		return
	GameState.test_mode = true
	var f := FileAccess.open("user://debug_setup.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"units": units, "loadouts": {}, "theme": BattleDebugArena.DEV_THEME}))
	f.close()
	BattleDebugArena.enter_with_saved_theme()
	RB.DEBUG_EDIT = true
	RB._edit_collapsed = true
	_b = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_b)
	print("[REC] 演示 ", case, " · ", units.size(), " 个单位")


func _process(d: float) -> void:
	_el += d
	if _b == null or not is_instance_valid(_b):
		return
	if not _started and _el > 0.6:
		_started = true
		_b._debug._edit_start_battle()
		print("[REC] %.2f 开打 · 场上 %d 单位" % [_el, _b._units.size()])
	var bs = _b._equip_sys._bomb_sys
	for k in bs.stat:
		if int(bs.stat[k]) != int(_seen.get(k, 0)):
			print("[EV] %.2f %s %d" % [_el, k, int(bs.stat[k])])
			_seen[k] = int(bs.stat[k])
	if int(_b._bomb_syn.strikes) != int(_seen.get("missile", 0)):
		print("[EV] %.2f missile %d" % [_el, int(_b._bomb_syn.strikes)])
		_seen["missile"] = int(_b._bomb_syn.strikes)
	if OS.has_environment("REC_PROBE") and int(_el * 2.0) != int((_el - d) * 2.0):
		for u in _b._units:
			print("[PROBE] %.1f %s %s pos=%s hp=%s alive=%s nm=%s nb=%s sk=%s st=%s atk=%s cd=%s rng=%s stun=%s" % [_el, str(u.get("side", "")), str(u.get("id", "")), str(u.get("pos", "")), str(int(u.get("hp", 0))), str(u.get("alive", false)), str(u.get("no_move", false)), str(u.get("no_basic", false)), str(u.get("active_skills", [])), str(u.get("state", "")), str(u.get("atk", 0)), str(u.get("atk_cd", 0)), str(u.get("atk_range", 0)), str(u.get("stun_until", 0))])
		print("[PROBE] mines ", _b._equip_sys._bomb_sys._mines.size(), " over=", _b._over, " edit=", _b._edit_mode)
	if _el > _max:
		print("[REC] %.2f 收工" % _el)
		get_tree().quit(0)


var _seen := {}
