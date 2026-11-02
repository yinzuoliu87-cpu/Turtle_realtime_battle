extends Node
## _probe_paw.gd — 爪子的真实几何(探针)。量控件框、绘制尺寸、热点偏移。
func _ready() -> void:
	await get_tree().process_frame
	var ct = load("res://autoload/CursorTheme.gd").new()
	add_child(ct)
	await get_tree().process_frame
	ct._build_cursor()
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	ct._process(0.0)
	var S: Vector2 = ct._g.size
	print("ART 常量          = %d   (HOT/ORIGIN 都是这个坐标系)" % ct.ART)
	print("_g.size(控件框)   = %s   ⇒ 每个美术像素画成 %.2f 设计px" % [str(S), S.y / float(ct.ART)])
	print("_glow.size        = %s" % str(ct._glow.size))
	print("_cur.scale        = %s" % str(ct._cur.scale))
	print("设计px 高         = %.1f" % (S.y * ct._cur.get_global_transform().get_scale().y))
	# 热点: 美术坐标 (11,1) 那一点【画在哪】 vs 代码认为它在哪(= 鼠标点)
	var art_tip := Vector2(11.0, 1.0)
	var drawn: Vector2 = ct._g.get_global_transform() * Vector2(art_tip.x * S.x / ct.ART, art_tip.y * S.y / ct.ART)
	var assumed: Vector2 = ct._cur.get_global_transform() * ct.HOT
	print("爪尖画在           = %s" % str(drawn))
	print("代码认为爪尖在     = %s  (= 鼠标点)" % str(assumed))
	print("★热点偏移          = %s  (非 0 = 尖端没落在鼠标点上)" % str(drawn - assumed))
	print("DONE")
	get_tree().quit(0)
