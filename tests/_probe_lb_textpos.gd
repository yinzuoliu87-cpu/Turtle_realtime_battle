extends Node
## 排行榜四天那一轮(2026-10-06)的对齐量尺: 帧差法(同 _probe_textpos.gd)量每个 Label 的真实墨迹框。
## 打印: ① 每列 表头 vs 数字 墨迹右沿差 ② 名字 vs 头衔 墨迹底沿/中线差。需开窗口跑(要真渲染)。
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _ink(l: Label) -> Rect2:
	var a: Image = await _grab()
	l.visible = false
	var b: Image = await _grab()
	l.visible = true
	var x0 := 99999; var y0 := 99999; var x1 := -1; var y1 := -1
	var r: Rect2 = l.get_global_rect()
	for y in range(maxi(0, int(r.position.y) - 4), mini(a.get_height(), int(r.end.y) + 4)):
		for x in range(maxi(0, int(r.position.x) - 4), mini(a.get_width(), int(r.end.x) + 4)):
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2()
	return Rect2(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _ready() -> void:
	GameState.perf_lite = true
	var shot: Node = load("res://tests/_shot_lb_days.tscn").instantiate()
	add_child(shot)
	for _i in range(90): await get_tree().process_frame
	var lb: Node = shot.get_child(0)
	var body: Control = lb.get("_body")
	var heads := {}
	var stats := {}   # i -> [labels]
	var names := {}   # y -> label
	var marks := {}
	for ch in body.get_children():
		if not (ch is Label) or not (ch as Label).is_visible_in_tree():
			continue
		var nm := str(ch.name)
		if nm.begins_with("LbColHead"):
			heads[int(nm.substr(9))] = ch
		elif nm.begins_with("RowStat"):
			var i := int(nm.substr(7, 1))
			if not stats.has(i): stats[i] = []
			stats[i].append(ch)
		elif nm.begins_with("RowMark_"):
			marks[int(round(ch.position.y)) - 1] = ch
		elif absf(ch.position.x - lb.NAME_X) < 0.5 and str(ch.text) != "—":
			names[int(round(ch.position.y))] = ch
	var worst := 0.0
	for i in heads:
		var hr: Rect2 = await _ink(heads[i])
		var line := "列%d「%s」表头右沿 %.0f:" % [i, heads[i].text, hr.end.x]
		for l in stats.get(i, []):
			var rr: Rect2 = await _ink(l)
			var d: float = rr.end.x - hr.end.x
			worst = maxf(worst, absf(d))
			line += " %s(%+.0f)" % [l.text, d]
		print(line)
	print("[对齐] 列右沿最大偏差 %.0f px" % worst)
	var wv := 0.0
	for y in marks:
		if not names.has(y): continue
		var a: Rect2 = await _ink(names[y]); var b: Rect2 = await _ink(marks[y])
		var dc: float = b.get_center().y - a.get_center().y
		var db: float = b.end.y - a.end.y
		wv = maxf(wv, absf(dc))
		print("  %s / %s : 中线差 %+.1f  底沿差 %+.0f" % [names[y].text, marks[y].text, dc, db])
	print("[对齐] 名字-头衔 中线最大偏差 %.1f px" % wv)
	get_tree().quit(0)
