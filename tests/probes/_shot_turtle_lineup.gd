extends Node
## 截图(2026-11-05 方案书 20261105b): 外包 11 只新待机 + 没换的几只摆在同一个战场上, 看大小比例与画风。
##   SHOT_OUT=res://.out/shots/lineup.png <godot> --path . res://tests/probes/_shot_turtle_lineup.tscn --resolution 1280x720
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const NEW := ["basic", "lightning", "shell", "lava", "phoenix", "stone", "bamboo", "fortune", "ice", "angel", "rainbow"]
const OLD := ["ninja", "two_head", "ghost", "pirate"]
func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = false
	var s = RB.new()
	add_child(s)
	for _i in range(4):
		await get_tree().process_frame
	s._units.clear()
	var a: Rect2 = s.ARENA
	var ids: Array = NEW + OLD
	for i in range(ids.size()):
		var col := i % 5
		var row := i / 5
		var p := Vector2(a.position.x + 140.0 + col * (a.size.x - 280.0) / 4.0, a.position.y + 90.0 + row * (a.size.y - 160.0) / 2.0)
		var u: Dictionary = s._spawn._make_unit(str(ids[i]), "left" if i < NEW.size() else "right", p)
		u["no_move"] = true
		u["no_basic"] = true
		u["active_skills"] = []
		s._units.append(u)
	s._edit_mode = false
	s._over = true
	for _i in range(40):
		await get_tree().process_frame
	## 只藏调试面板与底部选龟条(找到写着这些字的 Label, 往上爬到界面层下面那一级)
	var q: Array = [s]
	while not q.is_empty():
		var nd: Node = q.pop_back()
		if nd is Label and str((nd as Label).text) in ["调试场", "左队[友军]"]:
			var up: Node = nd
			while up.get_parent() != null and not (up.get_parent() is CanvasLayer) and up.get_parent() != s:
				up = up.get_parent()
			if up is CanvasItem:
				(up as CanvasItem).visible = false
		for c in nd.get_children():
			q.append(c)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "res://.out/shots/lineup.png")
	print("[SHOT] ok")
	get_tree().quit()
