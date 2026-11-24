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


## 我方携带者: 近战小将, 只会普攻(清掉技能; 小将本来就没有被动) —— 用户 11-24「友方带一件这件装备…只能攻击，不应该有任何除了攻击以外的东西」
static func _me(d: Vector2, eq: Array, extra: Dictionary = {}) -> Dictionary:
	var u := _u("__minion__", "left", d, {"minion": true, "role": "front", "level": 1, "plain": true, "equips": eq, "hp": 8000.0, "killable": false})
	u.merge(extra, true)
	return u


## 靶子: 小将身板(不带任何被动)、站桩、打不死; `n` = 1 只或 3 只(范围类看半径)
static func _dummies(dx: float = 80.0, n: int = 3, ai: bool = false, hp: float = 20000.0, atk: float = 0.0) -> Array:
	var o: Array = []
	var spots := [Vector2(dx, 0), Vector2(dx + 70, -70), Vector2(dx + 70, 70)]
	for i in range(n):
		o.append(_u("__minion__", "right", spots[i], {"minion": true, "role": "front", "level": 1, "plain": true, "hp": hp, "killable": ai, "ai": ai, "atk": atk}))
	return o


## 每条: [摆位, 录几秒]
static func cases() -> Dictionary:
	return {
		## 羁绊: 持有人不动不打(只为凑 3 件炸弹 = 1 档), 只看导弹本身
		"missile": [[_me(Vector2(-300, 0), _eq([102, 103, 97]), {"idle": true})] + _dummies(60, 3) + [_u("__minion__", "right", Vector2(280, 0), {"minion": true, "plain": true, "hp": 20000.0, "killable": false})], 15.0],
		"cracker": [[_me(Vector2(-10, 0), _eq([97]))] + _dummies(60, 3), 12.0],
		"tube": [[_me(Vector2(-10, 0), _eq([98]))] + _dummies(60, 3), 16.0],
		"grenade": [[_me(Vector2(-10, 0), _eq([99]))] + _dummies(60, 3), 16.0],
		## 烟雾弹: 两只会打的敌人冲过来, 看它们选不中烟里的我方
		"smoke": [[_me(Vector2(-200, -40), _eq([100]), {"hold": true}), _me(Vector2(-200, 60), [], {"hold": true})] + _dummies(150, 2, true, 8000.0, 60.0), 20.0],
		"sticky": [[_me(Vector2(-10, 0), _eq([101]))] + _dummies(60, 3), 20.0],
		## 地雷: 我方站住, 两只会动的敌人走过来踩雷
		"mine": [[_me(Vector2(-400, 0), _eq([102]), {"hold": true})] + _dummies(250, 2, true, 20000.0, 30.0), 14.0],
		## 炸药桶: 我方站住、血少, 会打的敌人把它打死
		"barrel": [[_me(Vector2(-10, 0), _eq([103]), {"hold": true, "hp": 400.0, "killable": true})] + _dummies(60, 3, true, 20000.0, 300.0), 14.0],
		"timer": [[_me(Vector2(-10, 0), _eq([104]))] + _dummies(60, 3), 23.0],
		"cannon": [[_u("__summon__", "left", Vector2(-300, 0), {"ghost_eq": "p2eq_105", "equips": _eq([105]), "minion": true, "fe": true})] + _dummies(160, 3), 14.0],
		"remote": [[_u("__summon__", "left", Vector2(-300, 0), {"ghost_eq": "p2eq_106", "equips": _eq([106], 1), "minion": true})] + _dummies(150, 3), 14.0],
		"katana": [[_u("__summon__", "left", Vector2(-160, 0), {"ghost_eq": "p2eq_107", "equips": _eq([107]), "minion": true, "fe": true})] + _dummies(60, 3), 16.0],
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
	var row: Array = cases().get(case, [[], 0.0])
	var units: Array = row[0]
	if not OS.has_environment("REC_SEC"):
		_max = float(row[1])
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
