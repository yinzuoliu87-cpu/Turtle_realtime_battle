extends Node
## 探针(不是门禁, 2026-11-15): 糖果龟普攻【横扫大锤】一下, 逐帧记「动作显示第几帧 · 目标掉血 · 伤害数字冒出 · 命中特效建出」。
## 用户 11-15「这个普通攻击命中帧到底是哪一帧？到什么时候跳数字？什么时候就跳出这个命中特效的？不对吧？」
## 11-15 结论: 命中 = 第 5 帧(从 1 数; 11-07 用户通过的「锤子扫到正前方」那一帧), 数字与特效同在那一刻(差 1/60 秒), 原登记就是对的。
## 跑法: <godot> --headless --path . --fixed-fps 60 --quit-after 900 res://tests/probes/_probe_candy_hit_timing.tscn

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
var _scn = null
var _cd = null
var _tg = null
var _fr := 0
var _ev: Array = []
var _last := ""
var _hp0 := -1.0
var _hits := 0


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	OS.set_environment("TURTLE_SEED", "424242")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	_scn = load(BATTLE_SCENE).instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	_scn._debug._edit_clear()
	_scn._edit_dummy_killable = false
	_scn._edit_dummy_hp = 60000.0
	_scn._edit_full_energy = false
	var ar: Rect2 = _scn.ARENA
	var cy: float = ar.position.y + ar.size.y * 0.5
	var lx: float = ar.position.x + ar.size.x * 0.40
	_cd = _scn._debug._edit_place_unit("candy", "left", Vector2(lx, cy))
	_tg = _scn._debug._edit_place_unit("stone", "right", Vector2(lx + 110.0, cy))
	_scn._debug._edit_start_battle()
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "right":
			u["no_basic"] = true
			u["no_move"] = true
	get_tree().node_added.connect(_on_add)


func _on_add(n: Node) -> void:
	if n is Sprite3D and (n as Sprite3D).texture != null:
		var p: String = (n as Sprite3D).texture.resource_path.get_file()
		if p.begins_with("candy-"):
			_ev.append("特效建出 " + p)
	elif n is Label:
		var par := n.get_parent()
		if par != null and (par is CanvasLayer or (par is HBoxContainer and par.get_parent() is CanvasLayer)):
			_ev.append("数字冒出「%s」" % (n as Label).text)


func _process(_d: float) -> void:
	if _scn == null:
		return
	_fr += 1
	var cd: Dictionary = {}
	var tg: Dictionary = {}
	for u in _scn._units:
		if u is Dictionary and str(u.get("id", "")) == "candy":
			cd = u
		elif u is Dictionary and str(u.get("side", "")) == "right":
			tg = u
	if cd.is_empty() or tg.is_empty():
		return
	var hp: float = float(tg.get("hp", 0.0))
	if _hp0 >= 0.0 and hp < _hp0:
		_ev.append("目标掉血 %.0f" % (_hp0 - hp))
	_hp0 = hp
	var spr = cd.get("sprite", null)
	var act: String = str(cd.get("anim_action", ""))
	var shown: int = int(spr.frame) if is_instance_valid(spr) else -1
	var st: String = str(cd.get("state", ""))
	var line := "动作 %-7s 显示第 %2d 帧(从 1 数) · 状态 %-7s" % [act, shown + 1, st]
	if line != _last or not _ev.is_empty():
		print("[帧 %4d | t %.3f] %s %s" % [_fr, float(_scn._t), line, ("· " + " · ".join(_ev)) if not _ev.is_empty() else ""])
		_last = line
	if _ev.any(func(e): return str(e).begins_with("目标掉血")):
		_hits += 1
	_ev.clear()
	if _hits >= 3:
		get_tree().quit(0)
