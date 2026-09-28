extends Node
## 一次性探针: 图鉴「换形态」钮到底在不在屏幕上、在哪。
## ★由来(2026-09-28): 我把 `_render_skill_cards` 里那一块拆成 `_form_switch_button()` 之后,
##   实拍双头龟那一页**看不到那颗钮**。拆分前后两张图逐像素相同(diff bbox=None) ⇒
##   不是拆坏的; 但"看不见"这件事本身要有个说法, 所以打这支探针量真实矩形。
## 跑法: godot --headless --path . res://tests/_probe_form_btn.tscn --quit-after 600


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var inst = (load("res://scenes/Codex.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(30):
		await get_tree().process_frame
	inst.call("_switch_tab", "pets")
	for _i in range(4):
		await get_tree().process_frame
	var items: Array = inst.get("_items")
	for i in range(items.size()):
		var d: Dictionary = items[i] as Dictionary
		var ms = d.get("meleeSkills", [])
		var vs = d.get("volcanoSkills", [])
		var has_m: bool = ms is Array and not (ms as Array).is_empty()
		var has_v: bool = vs is Array and not (vs as Array).is_empty()
		if not (has_m or has_v):
			continue
		inst.call("_select", i)
		for _j in range(8):
			await get_tree().process_frame
		print("── %s (idx %d, melee=%s volcano=%s) ──"
			% [str(d.get("name", "?")), i, str(has_m), str(has_v)])
		var vp: Rect2 = Rect2(Vector2.ZERO, Vector2(get_tree().root.size))
		var found := 0
		var stack: Array = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is Label and str((n as Label).text).find("换成") >= 0:
				found += 1
				var l := n as Label
				print("   「%s」 vis=%s rect=%s 在视口内=%s"
					% [l.text, str(l.is_visible_in_tree()), str(l.get_global_rect()),
						str(vp.intersects(l.get_global_rect()))])
		if found == 0:
			print("   **一个「换成…」的 Label 都没有** —— 钮根本没建")
	inst.queue_free()
	get_tree().quit(0)
