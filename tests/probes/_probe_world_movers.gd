extends Node
## 探针: 开发场(默认地图)里 `_world` 下哪些节点自己在动(位置 / 帧号 / 颜色), 按顶层子树分组。
## 用途: 11-20 删旧图后 verify_timestop_freeze 的背景分母(原 FarBackdrop 鱼群/气泡)没了, 找新图里在动的背景当尺子。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _s = null


func _snap(n: Node, out: Dictionary, path: String) -> void:
	for c in n.get_children():
		var p: String = path + "/" + c.name
		if c is Node3D:
			var rec: Array = [c.global_position, Color(0, 0, 0, 0), 0]
			if c is SpriteBase3D:
				rec[1] = c.modulate
				rec[2] = c.frame
			out[p] = rec
		_snap(c, out, p)


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true
	await _wait(40)
	_s._units.clear()
	await _wait(30)
	var a: Dictionary = {}
	_snap(_s._world, a, "")
	await _wait(90)
	var b: Dictionary = {}
	_snap(_s._world, b, "")
	var groups: Dictionary = {}
	var total: Dictionary = {}
	for k in a.keys():
		var top: String = str(k).split("/")[1] if str(k).split("/").size() > 1 else "?"
		total[top] = int(total.get(top, 0)) + 1
		if not b.has(k):
			continue
		var x: Array = a[k]
		var y: Array = b[k]
		var dp: float = (x[0] as Vector3).distance_to(y[0] as Vector3)
		var c0: Color = x[1]
		var c1: Color = y[1]
		var dc: float = absf(c0.a - c1.a) + absf(c0.r - c1.r) + absf(c0.g - c1.g) + absf(c0.b - c1.b)
		if dp > 0.0005 or dc > 0.002 or int(x[2]) != int(y[2]):
			if not groups.has(top):
				groups[top] = []
			(groups[top] as Array).append(str(k))
	print("MAP ", ArenaTheme.active)
	for top in total.keys():
		var g: Array = groups.get(top, [])
		print("  %-28s 在动 %3d / 共 %4d  例: %s" % [top, g.size(), int(total[top]), str(g.slice(0, 3))])
	print("tweens 已注册 ", (_s._sim_tweens as Array).size() if "_sim_tweens" in _s else -1)
	print("PROBE DONE")
	get_tree().quit()
