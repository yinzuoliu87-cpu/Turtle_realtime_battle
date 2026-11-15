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
		## 技能选成这次改的那两个: 猎人「隐蔽」(翻滚, skillPool 下标 2)、赛博「智能AI」(下标 3); 默认是精准射击 / 能量大炮
		var lo: Dictionary = (gs.loadouts as Dictionary).duplicate()
		lo["hunter"] = 2
		lo["cyber"] = 3
		gs.loadouts = lo
	if OS.has_environment("REC_SECS"):
		_secs = float(OS.get_environment("REC_SECS"))
	OS.set_environment("TURTLE_SEED", "424242")
	## 新地图(用户 11-15「这个旧的调试场怎么还用的是旧地图啊」): 默认暗林, REC_THEME 可指定 dusk / reef / shoal / storm
	ArenaTheme.active = OS.get_environment("REC_THEME") if ArenaTheme.MATCH_POOL.has(OS.get_environment("REC_THEME")) else BattleDebugArena.DEV_THEME
	ArenaTheme._picked = ""
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
	## 调试场的编辑面板(左侧)与底部笔刷栏挡住半个场地 ⇒ 录像时藏掉(只留战场、血条、顶栏)
	for nm in ["_edit_palette", "_edit_brush_bar", "_edit_grid_popup"]:
		var c = _scn.get(nm)
		if c != null and is_instance_valid(c) and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
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
		## 整局离场地四边最近多少(用户 11-15「这翻墙里面的那就是 bug 喽」: 看还贴不贴墙)
		var ar: Rect2 = _scn.ARENA
		var p: Vector2 = u["pos"]
		var e: float = minf(minf(p.x - ar.position.x, ar.end.x - p.x), minf(p.y - ar.position.y, ar.end.y - p.y))
		_last[id + "_edge"] = minf(float(_last.get(id + "_edge", INF)), e)
	if _el >= _secs:
		print("[EDGE] 整局离场地边最近: 猎人 %.0f 码 · 赛博 %.0f 码" % [float(_last.get("hunter_edge", -1.0)), float(_last.get("cyber_edge", -1.0))])
		get_tree().quit(0)
