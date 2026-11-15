extends Node
## 探针(不是门禁, 2026-11-15): 钻石斧被动 6「治疗 → 4 秒蓄力(梯形预警)→ 猛砸」在真实对局路径上演出出不出来。
## 用户 11-15「我玩的时候看那个…(小木斧的钻石技能)整个技能特效都没出现啊，都有 bug」。
## 建场: 本机存档 axe_stage = 4(钻石斧, 解锁被动 6)、没选最终造物; 左边带小木斧的龟, 右边一个木桩。
## 逐帧打: 斧头龟能 / 放治疗 / 进蓄力 / 梯形场节点(在不在树上、显隐、子节点)/ 斧头当前动作 / 砸下 / 砸下特效节点。
## 跑法(可加 --write-movie 录像): <godot> --path . --fixed-fps 60 --quit-after 2400 res://tests/probes/_probe_diamond_axe.tscn

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
var _scn = null
var _fr := 0
var _ax = null
var _last := ""
var _secs := 26.0


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.set("axe_stage", 4)
	gs.set("axe_exp_total", 480)
	gs.set("axe_final", "")
	print("[探针] 存档: axe_stage=%s axe_exp_total=%s axe_final=「%s」" % [str(gs.get("axe_stage")), str(gs.get("axe_exp_total")), str(gs.get("axe_final"))])
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
	var lx: float = ar.position.x + ar.size.x * 0.38
	var u: Dictionary = _scn._debug._edit_place_unit("basic", "left", Vector2(lx, cy))
	u["_edit_equips"] = [{"id": "p2eq_096", "star": 1}]
	_scn._debug._edit_place_unit("stone", "right", Vector2(lx + 260.0, cy))
	_scn._debug._edit_start_battle()
	for v in _scn._units:
		if v is Dictionary and str(v.get("side", "")) == "right":
			v["no_basic"] = true
			v["no_move"] = true
	get_tree().node_added.connect(_on_add)


var _adds: Array = []


func _on_add(n: Node) -> void:
	if _ax == null:
		return
	var tag := ""
	if n is Sprite3D and (n as Sprite3D).texture != null:
		tag = (n as Sprite3D).texture.resource_path.get_file()
	elif n is MeshInstance3D:
		tag = "Mesh:" + str(n.name)
	elif n is Node3D and str(n.name) != "":
		tag = "Node3D:" + str(n.name)
	if tag != "" and (tag.contains("axe") or tag.contains("eq096") or tag.begins_with("Mesh") or tag.begins_with("Node3D")):
		_adds.append(tag)


func _process(_d: float) -> void:
	if _scn == null:
		return
	_fr += 1
	for nm in ["_edit_palette", "_edit_brush_bar", "_edit_grid_popup"]:
		var c = _scn.get(nm)
		if c != null and is_instance_valid(c) and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
	if _ax == null:
		for v in _scn._units:
			if v is Dictionary and bool(v.get("_eq_axe", false)):
				_ax = v
				print("[帧 %d | t %.2f] 斧头召唤出来: 名字「%s」 _axe_pv=%d 龟能上限 %s" % [_fr, float(_scn._t), str(v.get("label", "")), int(v.get("_axe_pv", -1)), str(v.get("maxEnergy", "?"))])
	if _ax != null:
		var ax: Dictionary = _ax
		var charging: bool = ax.has("_axe_charge_t0")
		var fld = ax.get("_axe_field", null)
		var fs := "无"
		if fld != null and is_instance_valid(fld):
			var kids: Array = []
			for k in (fld as Node).get_children():
				kids.append("%s(%s)" % [str(k.name), "显" if (k is Node3D and (k as Node3D).visible) else "隐"])
			fs = "在树上=%s 显=%s 子节点 %s" % [str((fld as Node).is_inside_tree()), str((fld as Node3D).visible), str(kids)]
		var line := "龟能 %3d · 蓄力 %s · 动作 %s · 梯形场 %s" % [int(float(ax.get("energy", 0.0)) / 10.0) * 10, "是" if charging else "否",
			str(ax.get("_axe_last_action", ax.get("anim_action", ""))), fs]
		if line != _last or not _adds.is_empty():
			print("[帧 %d | t %.2f] %s%s" % [_fr, float(_scn._t), line, (" · 新建 " + str(_adds)) if not _adds.is_empty() else ""])
			_last = line
			_adds.clear()
	if float(_scn._t) >= _secs:
		get_tree().quit(0)
