extends Node
## 探针(不是门禁, 2026-11-15): 糖果锤蓄力中被眩晕 ⇒ 这一锤作废(被控规则), 排好的锤头能量节点要一起删掉。
## 跑法: <godot> --headless --path . --fixed-fps 60 --quit-after 900 res://tests/probes/_probe_candy_energy_cancel.tscn

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
var _scn = null
var _fr := 0
var _cast_fr := -1
var _swirls: Array = []
var _stunned := false


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var lo: Dictionary = (gs.loadouts as Dictionary).duplicate()
	lo["candy"] = 1
	gs.loadouts = lo
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
	_scn._edit_full_energy = true
	var ar: Rect2 = _scn.ARENA
	var cy: float = ar.position.y + ar.size.y * 0.5
	var lx: float = ar.position.x + ar.size.x * 0.40
	_scn._debug._edit_place_unit("candy", "left", Vector2(lx, cy))
	_scn._debug._edit_place_unit("stone", "right", Vector2(lx + 110.0, cy))
	_scn._debug._edit_start_battle()
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "right":
			u["no_basic"] = true
			u["no_move"] = true
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is Sprite3D and (n as Sprite3D).texture != null and (n as Sprite3D).texture.resource_path.ends_with("candy-swirl.png"):
			_swirls.append(n)
			if _cast_fr < 0:
				_cast_fr = _fr)


func _process(_d: float) -> void:
	if _scn == null:
		return
	_fr += 1
	var cd: Dictionary = {}
	for u in _scn._units:
		if u is Dictionary and str(u.get("id", "")) == "candy":
			cd = u
	if cd.is_empty():
		return
	## 糖果锤生效后第 3 帧把糖果龟眩晕 1 秒(锤还没砸下去)
	if _cast_fr >= 0 and not _stunned and _fr >= _cast_fr + 3:
		_scn._damage._stun(cd, 1.0, "probe", true)
		_stunned = true
		print("[探针] 第 %d 帧糖果锤生效、第 %d 帧眩晕; 锤头能量漩涡建了 %d 个" % [_cast_fr, _fr, _swirls.size()])
	if _stunned and _fr == _cast_fr + 40:
		var alive := 0
		for n in _swirls:
			if is_instance_valid(n):
				alive += 1
		var slam := 0
		for n in _scn._world.get_children():
			if n is Sprite3D and (n as Sprite3D).texture != null and (n as Sprite3D).texture.resource_path.ends_with("candy-slam.png"):
				slam += 1
		print("[探针] 砸地时刻过后: 锤头能量漩涡还剩 %d / %d 个 · 砸地序列帧 %d 个(应为 0: 这一锤作废)" % [alive, _swirls.size(), slam])
		print("ALL PASS" if alive == 0 and slam == 0 and _swirls.size() > 0 else "FAILED")
		get_tree().quit(0)
