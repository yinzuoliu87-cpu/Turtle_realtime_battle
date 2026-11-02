extends Node
## _probe_satrow.gd — 状态行「顶穿控件」剖面探针 (2026-09-28)
## 打两张表: ① 七天逐天的 ink 宽 / 框宽  ② 那一行的竖向剖面(holder + 每个子控件 + 上下邻居)

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

const MON := 1789344000
const NOON := 43200
const WD := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("no GameState"); get_tree().quit(1); return
	gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	gs.season_id = 1
	gs.season_level = 1
	gs.hearts = 3
	gs.ranked_used = 7
	gs.battles_won = 7
	gs.battles_total = 11
	gs.season_total_battles = 3
	gs.promoted = true
	gs.gauntlet_wins = 2
	gs.gauntlet_losses = 1

	var m = MENU.new()
	var f = m._bold_font()
	var box: float = float(MENU.LEFT_W) - 8.0
	print("=== ① 七天逐天 ink 宽 / 框宽 %.0f (纯函数口径, 字号 18) ===" % box)
	for d in range(7):
		var ts: int = MON + d * 86400 + NOON
		var gl: String = str(m._phase_status_line(ts))
		var txt: String = "第 %d 大轮 · Lv %d   ♥ %d/8   本周 %d/%d" % [
			int(gs.season_id), int(gs.season_level), int(gs.hearts),
			int(gs.ranked_used), int(P2.RANKED_QUOTA)]
		if gl != "":
			txt = "第 %d 大轮 · Lv %d   %s" % [int(gs.season_id), int(gs.season_level), gl]
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		print("  %s  ink %7.1f  框 %.0f  %s  「%s」" % [
			WD[d], w, box, ("OVER +%.0f" % (w - box)) if w > box else "ok      ", txt])
	## 周日三态
	print("  --- 周日三态 ---")
	for st in [[true, 4, 1, "已晋级"], [true, 1, 3, "止步"], [false, 0, 0, "没资格"]]:
		gs.promoted = bool(st[0]); gs.gauntlet_wins = int(st[1]); gs.gauntlet_losses = int(st[2])
		var gl2: String = str(m._phase_status_line(MON + 6 * 86400 + NOON))
		var t2: String = "第 %d 大轮 · Lv %d   %s" % [int(gs.season_id), int(gs.season_level), gl2]
		var w2: float = f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		print("  %-6s ink %7.1f  框 %.0f  %s 「%s」" % [str(st[3]), w2, box,
			("OVER +%.0f" % (w2 - box)) if w2 > box else "ok      ", t2])
	## 单段宽度: 身份段 / 相位段 分开量(两行版式的前提)
	print("  --- 分段宽 (两行版式的前提) ---")
	gs.promoted = true; gs.gauntlet_wins = 2; gs.gauntlet_losses = 1
	var head: String = "第 %d 大轮 · Lv %d" % [int(gs.season_id), int(gs.season_level)]
	print("     身份段(无♥) 「%s」 ink %.1f" % [head, f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x])
	var head2: String = "第 %d 大轮 · Lv %d   ♥ %d/8" % [int(gs.season_id), int(gs.season_level), int(gs.hearts)]
	print("     身份段(带♥) 「%s」 ink %.1f" % [head2, f.get_string_size(head2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x])
	for d in range(7):
		var gl3: String = str(m._phase_status_line(MON + d * 86400 + NOON))
		if gl3 == "":
			gl3 = "♥ %d/8   本周 %d/%d" % [int(gs.hearts), int(gs.ranked_used), int(P2.RANKED_QUOTA)]
		print("     %s 相位段 ink %7.1f 「%s」 (17号 %.1f / 16号 %.1f)" % [WD[d],
			f.get_string_size(gl3, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, gl3,
			f.get_string_size(gl3, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x,
			f.get_string_size(gl3, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x])
	## 字高
	for sz in [16, 17, 18]:
		print("     字号 %d: 行高 %.1f (ascent %.1f descent %.1f)" % [sz,
			f.get_height(sz), f.get_ascent(sz), f.get_descent(sz)])
	m.free()

	print("")
	print("=== ② 竖向剖面 (真渲染, 钉周六) ===")
	var pk = load("res://scenes/MainMenu.tscn")
	var mm = pk.instantiate()
	mm.clock_override_ts = MON + 5 * 86400 + NOON
	get_tree().root.add_child(mm)
	if mm is Control:
		(mm as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(mm as Control).size = Vector2(1280, 720)
	for _i in range(480):
		await get_tree().process_frame
	var all: Array = []
	_collect(mm, all)
	print("  可见控件 %d 个" % all.size())
	## 找 holder: 含「大轮」Label 的最近 Control 祖先(直接是 content_root 的子)
	var row_holder: Control = null
	for c in all:
		if c is Label and str((c as Label).text).find("大轮") >= 0:
			var p = c
			while p != null and p.get_parent() != mm.get("content_root"):
				p = p.get_parent()
			if p is Control:
				row_holder = p
			break
	if row_holder == null:
		print("  !! 找不到状态行 holder")
	else:
		var hr: Rect2 = row_holder.get_global_rect()
		print("  holder rect  y %.1f..%.1f  x %.1f..%.1f  size %.0fx%.0f  min %s" % [
			hr.position.y, hr.end.y, hr.position.x, hr.end.x, hr.size.x, hr.size.y,
			str(row_holder.get_combined_minimum_size())])
		var kids: Array = []
		_collect(row_holder, kids)
		for k in kids:
			var kr: Rect2 = (k as Control).get_global_rect()
			var tag := ""
			if k is Label:
				tag = "「%s」sz=%s" % [str((k as Label).text).substr(0, 40),
					str((k as Label).get_theme_font_size("font_size"))]
			print("     %-14s y %6.1f..%6.1f x %6.1f..%6.1f  %5.0fx%-5.0f min %s %s" % [
				k.get_class(), kr.position.y, kr.end.y, kr.position.x, kr.end.x,
				kr.size.x, kr.size.y, str((k as Control).get_combined_minimum_size()), tag])
	## 上下邻居
	print("  --- 上下邻居 (按 y 排序, 只列 x<520 的左栏 + 赛程条) ---")
	var rows: Array = []
	for c in all:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x >= 1279.0 and r.size.y >= 719.0:
			continue
		if c.get_parent() != mm.get("content_root") and c.get_parent() != mm.get("page_box"):
			continue
		rows.append([r, c])
	rows.sort_custom(func(a, b): return (a[0] as Rect2).position.y < (b[0] as Rect2).position.y)
	for rr in rows:
		var r2: Rect2 = rr[0]
		print("     y %6.1f..%6.1f x %6.1f..%6.1f %5.0fx%-5.0f %s %s" % [
			r2.position.y, r2.end.y, r2.position.x, r2.end.x, r2.size.x, r2.size.y,
			(rr[1] as Node).get_class(), _tag(rr[1])])
	print("  常量: STATUS_Y=%.0f MENU_Y=%.0f ROW_H=%.0f MENU_N=%d 栈底=%.0f STRIP_BOTTOM=%.0f" % [
		float(MENU.STATUS_Y), float(MENU.MENU_Y), float(MENU.ROW_H), int(MENU.MENU_N),
		float(MENU.MENU_Y) + float(MENU.MENU_N) * float(MENU.ROW_H), float(MENU.STRIP_BOTTOM)])
	print("PROBE DONE")
	get_tree().quit(0)


func _tag(n: Node) -> String:
	var q: Array = [n]
	while not q.is_empty():
		var x = q.pop_front()
		if x is Label and str((x as Label).text).strip_edges() != "":
			return "「%s」" % str((x as Label).text).substr(0, 28)
		for ch in x.get_children():
			q.append(ch)
	return ""


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			out.append(c)
		_collect(c, out)
