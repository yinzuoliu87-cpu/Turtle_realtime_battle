extends Node
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
func _ready():
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new(); add_child(s)
	await get_tree().process_frame
	var u = s._spawn._make_unit("__minion__", "left", Vector2(600,474), {"minion": true, "role": "front", "level": 1})
	for k in ["id","active_skills","passive","skills","atk","maxHp","atk_interval","atk_range","melee","echarge","energy"]:
		print("[M] ", k, " = ", u.get(k, "<none>"))
	get_tree().quit()
