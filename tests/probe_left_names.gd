extends Node
## 探针: 我方(左)前两只龟为什么没有名字/头像。打真实字段值, 不推理。
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	print("=== GameState 侧 ===")
	if gs != null:
		gs.test_mode = true
		print("  season_leaders = %s" % str(gs.get("season_leaders")))
		print("  dual_ghost     = %s" % str(gs.get("dual_ghost")))
		print("  current_lane   = %s" % str(gs.get("current_lane")))
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	print("=== _units 逐个 ===")
	print("  %-6s %-14s %-10s %-6s %s" % ["side", "id", "name", "类型", "头像"])
	for u in s._units:
		var kind := "龟"
		if u.get("is_trainer", false): kind = "大师"
		elif u.get("_isEgg", false): kind = "蛋"
		elif u.get("is_minion", false) or u.get("minion", false): kind = "小将"
		elif u.get("is_summon", false): kind = "召唤"
		var tex = s._unit_portrait_texture(u)
		var has_tex: String = "有" if tex != null else "★无"
		var nm: String = str(u.get("name", ""))
		if nm == "": nm = "★空"
		print("  %-6s %-14s %-10s %-6s %s" % [str(u.get("side", "")), str(u.get("id", "")), nm, kind, has_tex])
	print("=== STATS 里有没有这些 id ===")
	for u in s._units:
		var iid := str(u.get("id", ""))
		if iid != "" and not s.STATS.has(iid):
			print("  ★ id '%s' 不在 STATS 表里(side=%s)" % [iid, str(u.get("side", ""))])
	print("=== _data_by_id 里有没有 ===")
	for u in s._units:
		var iid := str(u.get("id", ""))
		if iid != "" and not s._data_by_id.has(iid):
			print("  ★ id '%s' 不在 _data_by_id(pets.json) 里" % iid)
	get_tree().quit(0)
