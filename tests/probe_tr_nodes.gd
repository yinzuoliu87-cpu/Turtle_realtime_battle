extends Node
## 探针: 直接调某个大师技的【演出函数】, 同一帧内前后快照 _world, 精确隔离它加了什么。
##
## ★为什么要"同一帧" —— 我第一版探针在 1.6 秒窗口里比对新增节点, 结果四技输出一模一样:
##   抓到的全是【环境气泡】(持续生成的 Sprite3D, 也是程序生成、resource_path 为空,
##   按路径根本分不开)。窗口一放宽就被噪声灌满。
## ★也不走预览循环 —— 那样每 period 放一次, 分不清是哪一次加的。
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _collect(n: Node, out: Dictionary) -> void:
	if n is Sprite3D or n is GPUParticles3D or n is MeshInstance3D:
		out[n.get_instance_id()] = n
	for c in n.get_children():
		_collect(c, out)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var s = RTScene.new()
	get_tree().root.add_child(s)
	var el := 0.0
	while el < 1.2:
		await get_tree().process_frame
		el += get_process_delta_time()
	var origin: Vector2 = s._arena_center
	var dir := Vector2.RIGHT
	var tr: Dictionary = s._spawn._make_unit(s.TRAINER_ID, "left", origin - dir * 260.0, {"trainer": true})
	var tgt: Dictionary = s._spawn._make_unit("basic", "right", origin + dir * 300.0, {})
	tgt["_review_dummy"] = true
	s._units.append(tr); s._units.append(tgt)
	var which := OS.get_environment("TRSK")
	# ── 同一帧: 快照 → 调演出 → 再快照 ──
	var a: Dictionary = {}
	_collect(s._world, a)
	match which:
		"hook":  s._trainer_sys._hook_dramatize(tr, tgt)
		"fury":  s._trainer_sys._fury_dramatize(tr, origin + dir * 200.0)
		"whistle":
			s._trainer_sys._whistle_note(tr)
			s._trainer_sys._whistle_spirit_dramatize(tr, tr["pos"], dir)
		"glacier": s._trainer_sys._glacier_dramatize(origin - dir * 120.0, dir)
		"hunt":  s._trainer_sys._hunt_dramatize(tr, tgt, 0.45)
		"tame":  s._trainer_sys._tame_dramatize(tr, tgt, 0.45)
		"stone": s._ballistics._fire_trainer_rock(tr, tgt, false)
	var b: Dictionary = {}
	_collect(s._world, b)
	print("=== %s: 演出函数【同一帧内】新增的节点 ===" % which)
	var n := 0
	for id in b:
		if a.has(id): continue
		n += 1
		var nd: Node = b[id]
		if nd is Sprite3D:
			var sp := nd as Sprite3D
			var t: Texture2D = sp.texture
			var path := "(程序生成)" if (t == null or t.resource_path == "") else t.resource_path.get_file()
			var wh: float = (float(t.get_height()) * sp.pixel_size) if t != null else 0.0
			print("  Sprite3D  %-26s pixel_size=%.4f  世界高=%.2f m  贴图=%s" %
				[path, sp.pixel_size, wh, ("%dx%d" % [t.get_width(), t.get_height()]) if t != null else "无"])
		else:
			print("  %-9s %s" % [nd.get_class(), nd.name])
	if n == 0:
		print("  ★一个节点都没加")
	print("  ── 合计 %d 个 ── (参考: 龟立绘世界高 %.1f m)" % [n, s.TARGET_BODY_H])
	get_tree().quit(0)
