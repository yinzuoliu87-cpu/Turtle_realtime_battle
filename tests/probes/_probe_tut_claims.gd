extends Node

## _probe_tut_claims.gd — 探针: 量教学文案声称的【方位/状态】到底是什么
## 只打数值, 不做断言。用完即弃。

const STEPS := "res://data/tutorial-steps.json"

var _scenes := {
	"team_select": "res://scenes/TeamSelect.tscn",
	"shop": "res://scenes/Shop.tscn",
	"inventory": "res://scenes/Inventory.tscn",
	"codex": "res://scenes/Codex.tscn",
}


func _walk(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _zone(r: Rect2, vp: Vector2) -> String:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return "空矩形"
	var cx := (r.position.x + r.size.x * 0.5) / vp.x
	var cy := (r.position.y + r.size.y * 0.5) / vp.y
	var h := "左" if cx < 1.0 / 3.0 else ("中" if cx < 2.0 / 3.0 else "右")
	var v := "上" if cy < 1.0 / 3.0 else ("中" if cy < 2.0 / 3.0 else "下")
	return "%s%s (cx=%.3f cy=%.3f)" % [v, h, cx, cy]


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp: Vector2 = get_viewport().get_visible_rect().size
	print("[探针] 视口 = ", vp)

	# ★真新号态: season_leaders 空 ⇒ _roster_locked=false ⇒ 全选模式(教学就是这个态)
	GameState.tutorial_active = true
	GameState.tutorial_mandatory = true
	GameState.season_leaders = []
	GameState.left_team = ([] as Array[String])
	GameState.dual_lineup = {}
	GameState.meta_deepsea_coins = 20

	var td = get_node_or_null("/root/TutorialDirector")
	print("[探针] TutorialDirector.is_active() = ", td != null and td.is_active())

	for key in ["team_select", "shop", "inventory", "codex"]:
		GameState.tutorial_stage = "match1_pick" if key == "team_select" else key
		var inst = load(_scenes[key]).instantiate()
		add_child(inst)
		for _i in range(6):
			await get_tree().process_frame
		print("── [%s] stage=%s" % [key, GameState.tutorial_stage])
		# 锚点
		if inst.has_method("_tutorial_anchor"):
			for nm in ["roster", "slots", "confirm", "offer", "coins", "lanes", "backpack", "tabs"]:
				var r: Rect2 = inst.call("_tutorial_anchor", nm)
				if r.size.x > 0.0:
					print("    锚点 %-9s %s  %s" % [nm, str(r), _zone(r, vp)])
		# 真按钮文字 + 位置
		if td != null:
			td.attach_next_button(inst, key)
			for _i in range(3):
				await get_tree().process_frame
		var all: Array = []
		_walk(inst, all)
		var nb := 0
		for n in all:
			if n is Button:
				var b: Button = n
				var gr: Rect2 = b.get_global_rect()
				if gr.size.x <= 0.0:
					continue
				nb += 1
				print("    按钮 '%s' disabled=%s %s %s" % [b.text, b.disabled, str(gr), _zone(gr, vp)])
		print("    [分母] 可见按钮 %d 个" % nb)
		# 选龟屏: 阵容到底有没有龟
		if key == "team_select":
			print("    GameState.left_team = ", GameState.left_team)
			print("    scene.team = ", inst.get("team"))
			print("    _roster_locked = ", inst.get("_roster_locked"))
			# 详情面板在哪
			for fld in ["_dt_portrait", "_dt_stats", "_detail_bottom", "_grid_flow", "_synergy_box"]:
				var c = inst.get(fld)
				if c is Control:
					print("    %s %s %s" % [fld, str((c as Control).get_global_rect()), _zone((c as Control).get_global_rect(), vp)])
		inst.queue_free()
		await get_tree().process_frame

	GameState.tutorial_active = false
	GameState.tutorial_stage = ""
	print("PROBE DONE")
	get_tree().quit(0)
