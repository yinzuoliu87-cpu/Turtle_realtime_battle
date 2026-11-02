extends Node
## _probe_mmprofile.gd — 主菜单**竖向剖面** + 九宫格边带预算 (2026-09-28)
##
## 为什么先打这张表: 竖向余量极紧(上一轮实测**栈底与赛程条顶只差 1px**),
## 而「文字压边带」是 `verify_ui_consistency` 里**只降不升的棘轮**(MainMenu frame 基线 2)。
## 套九宫格之前必须先知道:
##   · 边带到底几像素(**从贴图里量**, 不读配置边距 —— 与门禁 `_band_of` 同一套算法)
##   · 每个格子里那两行字的**真实 rect**, 减去边带之后还剩不剩
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400
const WD_CN := ["一", "二", "三", "四", "五", "六", "日"]
const WD_LONG := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const TEX := ["panel-wide.png", "panel-wide-on.png", "panel-wide-flat.png",
	"chip-frame.png"]


## ★与 `verify_ui_consistency._band_of` **逐行同算法** —— 换一套尺子量出来的数字
##   跟门禁判红用的不是一个东西, 那种"算过了"等于没算。
func _band_of(tex: Texture2D) -> float:
	var img := tex.get_image()
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var ctr := img.get_pixel(cx, cy)
	var bl := 0
	var bt := 0
	if ctr.a < 0.04:
		for x in range(0, cx):
			if img.get_pixel(x, cy).a < 0.04 and x > 0:
				bl = x
				break
		for y in range(0, cy):
			if img.get_pixel(cx, y).a < 0.04 and y > 0:
				bt = y
				break
	else:
		for x2 in range(cx, 0, -1):
			var c := img.get_pixel(x2, cy)
			if c.a < 0.04 or maxf(maxf(absf(c.r - ctr.r), absf(c.g - ctr.g)),
					absf(c.b - ctr.b)) > 0.12:
				bl = x2
				break
		for y2 in range(cy, 0, -1):
			var c2 := img.get_pixel(cx, y2)
			if c2.a < 0.04 or maxf(maxf(absf(c2.r - ctr.r), absf(c2.g - ctr.g)),
					absf(c2.b - ctr.b)) > 0.12:
				bt = y2
				break
	return float(maxi(bl, bt))


func _ink(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var f: Font = l.get_theme_font("font")
	if f == null:
		return r
	var fs: int = l.get_theme_font_size("font_size")
	var ts: Vector2 = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var w: float = minf(ts.x, r.size.x)
	var h: float = minf(ts.y, r.size.y)
	var x := r.position.x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = r.position.x + (r.size.x - w) * 0.5
	elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = r.position.x + (r.size.x - w)
	var y := r.position.y
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y = r.position.y + (r.size.y - h) * 0.5
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y = r.position.y + (r.size.y - h)
	return Rect2(x, y, w, h)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.season_total_battles = 5
		gs.ranked_used = 5
		gs.hearts = 3
	await get_tree().process_frame

	print("=== ① 边带(与门禁 `_band_of` 同算法, **从贴图量**) ===")
	for t in TEX:
		var p := "res://assets/sprites/ui/" + str(t)
		if not ResourceLoader.exists(p):
			print("  %-22s 不在" % str(t))
			continue
		var tx: Texture2D = load(p)
		print("  %-22s %dx%d  band=%.0f" % [str(t), tx.get_width(), tx.get_height(),
			_band_of(tx)])

	var packed = load("res://scenes/MainMenu.tscn")
	for d in [4, 6, 7]:
		var ts: int = SUN0 + (0 if d == 7 else d) * 86400 + 12 * 3600
		var mm = packed.instantiate()
		mm.clock_override_ts = ts
		add_child(mm)
		for _i in range(8):
			await get_tree().process_frame
		print("")
		print("=== ② 竖向剖面 · %s ===" % WD_LONG[d - 1])
		## 全树 Control 按底沿排, 只看**赛程条以上**那一摞的最底
		var st: Array = [mm]
		var stack_bottom := 0.0
		var stack_who := ""
		var strip: Control = null
		while not st.is_empty():
			var n = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var c := n as Control
				var r := c.get_global_rect()
				if str(c.name) == "WeekStrip":
					strip = c
				elif r.size.x > 4.0 and r.size.y > 4.0 and r.size.y < 200.0 \
						and r.size.x < 1000.0 and r.position.y < 620.0 \
						and r.position.y + r.size.y > stack_bottom:
					stack_bottom = r.position.y + r.size.y
					stack_who = "%s<%s> %.0fx%.0f @%.0f,%.0f" % [c.get_class(),
						str(c.name).substr(0, 16), r.size.x, r.size.y, r.position.x, r.position.y]
			for ch in n.get_children():
				st.append(ch)
		print("  栈底(赛程条以上最低的那个) = %.1f   %s" % [stack_bottom, stack_who])
		if strip == null:
			print("  条子没建出来")
			mm.queue_free()
			await get_tree().process_frame
			continue
		var sr := strip.get_global_rect()
		print("  赛程条  顶沿=%.1f  底沿=%.1f  高=%.1f  宽=%.1f"
			% [sr.position.y, sr.position.y + sr.size.y, sr.size.y, sr.size.x])
		print("  ★栈底 → 条顶 的缝 = %.1f px" % (sr.position.y - stack_bottom))
		print("  条底 → 屏底(720) = %.1f px" % (720.0 - sr.position.y - sr.size.y))
		## 逐格
		var hb: Control = null
		for c2 in strip.get_children():
			if c2 is HBoxContainer:
				hb = c2
				break
		if hb == null:
			mm.queue_free()
			await get_tree().process_frame
			continue
		for cell in hb.get_children():
			if not (cell is Control):
				continue
			var cr: Rect2 = (cell as Control).get_global_rect()
			if cr.size.x < 2.0:
				continue
			var line := "    %-16s %6.1fx%-5.1f @y %.1f..%.1f" % [
				(cell as Control).get_class(), cr.size.x, cr.size.y,
				cr.position.y, cr.position.y + cr.size.y]
			var sub: Array = [cell]
			var top := 1.0e9
			var bot := -1.0e9
			var names: Array = []
			while not sub.is_empty():
				var q = sub.pop_back()
				if q is Label and str((q as Label).text).strip_edges() != "":
					var ir := _ink(q as Label)
					top = minf(top, ir.position.y)
					bot = maxf(bot, ir.position.y + ir.size.y)
					names.append("%s[%.1f..%.1f]" % [str((q as Label).text),
						ir.position.y, ir.position.y + ir.size.y])
				elif q is Button:
					names.append("Button<%s>" % str((q as Button).text).replace("\n", "/"))
					var br := (q as Button).get_global_rect()
					print("%s  门=%.0fx%.0f" % [line, br.size.x, br.size.y])
				for ch2 in q.get_children():
					sub.append(ch2)
			if bot > top:
				print("%s  字块 %.1f..%.1f (高 %.1f)  %s"
					% [line, top, bot, bot - top, str(names)])
				## 边带 7/8 两档各自还剩多少
				for band in [7.0, 8.0]:
					var inner_top: float = cr.position.y + band
					var inner_bot: float = cr.position.y + cr.size.y - band
					var over: float = maxf(inner_top - top, bot - inner_bot)
					print("        band=%.0f ⇒ 内容区 %.1f..%.1f  越界=%.1f  %s"
						% [band, inner_top, inner_bot, over,
						"← >2 会被判「压边带」" if over > 2.0 else "ok"])
		mm.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
