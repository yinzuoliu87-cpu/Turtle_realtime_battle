extends Node
## 猎人龟【翻滚】/ 赛博龟【智能AI】走位录像台(不是门禁, 2026-11-15)。
## 用户 11-15「…这个位移你都是一个劲的往后退…感觉不是很合理」「走位的话你按你思路做吧」→ 改前 / 改后各录一段给用户看。
## 调试场(DEBUG_EDIT): 我方 猎人龟 + 赛博龟 + 石头龟(前排近战); 对面 石头龟 + 钻石龟(近战) + 赌神龟(远程)。
##   满龟能(两只频繁放技能); 对面放开会走会打; 固定种子 ⇒ 改前改后同一局开场。录 REC_SECS 秒后自己 quit。
## 跑法(右屏、静音):
##   APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 \
##     --write-movie <输出>/kite.avi --fixed-fps 60 --quit-after 1500 res://tests/_rec_kite.tscn
## 每次冲刺 / 翻滚打一行 [DASH](时刻 · 谁 · 起点 → 落点 · 离最近敌人), 看录像时对照。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _scn = null
var _el := 0.0
var _secs := 20.0
var _last := {}


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	if OS.has_environment("REC_SECS"):
		_secs = float(OS.get_environment("REC_SECS"))
	OS.set_environment("TURTLE_SEED", "424242")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	_scn = load(BATTLE_SCENE).instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	_scn._debug._edit_clear()
	_scn._edit_dummy_killable = true
	_scn._edit_dummy_hp = 7000.0
	_scn._edit_full_energy = true
	var ar: Rect2 = _scn.ARENA
	var cy: float = ar.position.y + ar.size.y * 0.5
	var lx: float = ar.position.x + ar.size.x * 0.30
	var rx: float = ar.position.x + ar.size.x * 0.72
	_scn._debug._edit_place_unit("hunter", "left", Vector2(lx - 60.0, cy - 110.0))
	_scn._debug._edit_place_unit("cyber", "left", Vector2(lx - 60.0, cy + 110.0))
	_scn._debug._edit_place_unit("stone", "left", Vector2(lx + 80.0, cy))
	_scn._debug._edit_place_unit("stone", "right", Vector2(rx - 60.0, cy - 60.0))
	_scn._debug._edit_place_unit("diamond", "right", Vector2(rx - 40.0, cy + 90.0))
	_scn._debug._edit_place_unit("gambler", "right", Vector2(rx + 120.0, cy))
	_scn._debug._edit_start_battle()
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "right":
			u.erase("no_basic")      # 调试场的敌人默认是不动的假人: 放开, 会走会打
			u.erase("no_move")
	print("[REC] 开打 · 场地 %s" % str(ar))


func _process(delta: float) -> void:
	if _scn == null:
		return
	_el += delta
	for u in _scn._units:
		if not (u is Dictionary) or str(u.get("side", "")) != "left":
			continue
		var id: String = str(u.get("id", ""))
		if id != "hunter" and id != "cyber":
			continue
		var k: String = "%s:%d" % [id, (u as Object).get_instance_id() if u is Object else 0]
		var flag: bool = bool(u.get("hunter_roll_active", false)) or bool(u.get("_slam", false))
		if flag and not bool(_last.get(id, false)):
			var ne = _scn._targeting._nearest_enemy(u)
			var dest: Vector2 = u.get("_roll_dest", u["pos"]) if id == "hunter" else u["pos"]
			print("[DASH] %.2f 秒 %s 从 %s 离最近敌人 %.0f 码" % [_el, id, str((u["pos"] as Vector2).round()),
				DetMath.dist(u["pos"], ne["pos"]) if ne != null else -1.0])
		_last[id] = flag
	if _el >= _secs:
		get_tree().quit(0)
