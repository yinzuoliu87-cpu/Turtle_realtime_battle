extends Node
## _probe_cursor_size.gd — 台账 ④ 的探针(不进门禁)。先量再改。
##
## 要量到的数:
##   ① 爪子贴图里【真正不透明】的那块有多大(art px) —— 控件框是 24×24, 但画出来的可能不是
##   ② `_process` 那段 `base_scl / cf` 在各窗口尺寸下算出多少 ⇒ 屏幕物理像素 / 设计像素各是多少
##   ③ clampf(cf, 0.5, 4.0) 的下界在哪些窗口尺寸下【真的被夹住】(= "屏幕固定 24px" 的承诺破在哪)
##   ④ 和屏上真元件比: 战斗摆位屏的「开打」钮(220×62 设计px)、仓库自己的触控下限 TOUCH_MIN=81
##   ⑤ 手机上到底有没有这只爪子(读 _ready 的早退条件)
##
## 跑法: <godot> --headless --path . res://tests/_probe_cursor_size.tscn --quit-after 300

const CT := preload("res://autoload/CursorTheme.gd")
const UICONS := preload("res://tests/verify_ui_consistency.gd")

## 设计基准(project.godot window/size/viewport_*)
const DESIGN := Vector2(1280.0, 720.0)


func _art_bbox(tex: ImageTexture) -> Rect2i:
	var img := tex.get_image()
	var minx := img.get_width()
	var miny := img.get_height()
	var maxx := -1
	var maxy := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.01:
				minx = mini(minx, x); miny = mini(miny, y)
				maxx = maxi(maxx, x); maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


func _ready() -> void:
	var ct = CT.new()          # 不加进树 ⇒ 不跑 _ready(headless 会早退, 拿不到贴图)
	var point: ImageTexture = ct._build(2, ct._point_cols, ct._point_rects, 24, 24)
	var fist: ImageTexture = ct._build(2, ct._fist_cols, ct._fist_rects, 24, 22)
	print("── ① 贴图与真实不透明范围 ──")
	print("  ART 常量 = %d   控件框 (custom_minimum_size/size) = %d×%d" % [ct.ART, ct.ART, ct.ART])
	for pair in [["POINT", point, 2], ["FIST", fist, 2]]:
		var tex: ImageTexture = pair[1]
		var sc: int = int(pair[2])
		var bb := _art_bbox(tex)
		# 贴图是按 _build(scale=2) 放大的 ⇒ 折回 art px
		print("  %s 贴图=%d×%d(scale=%d) ⇒ art %d×%d;  不透明 bbox(art px) = %d×%d @ (%d,%d)" % [
			str(pair[0]), tex.get_width(), tex.get_height(), sc,
			tex.get_width() / sc, tex.get_height() / sc,
			bb.size.x / sc, bb.size.y / sc, bb.position.x / sc, bb.position.y / sc])
	var pbb := _art_bbox(point)
	## ★★别拿 `ART` 当"这只爪多高" —— 真正决定绘制尺寸的是 `_g.size`(控件框), 而它曾经
	##   被默认 `expand_mode` 上调成贴图尺寸 48(见 CursorTheme §CURSOR_SCALE ②)。
	##   所以这里**真建一次爪子, 量它的控件框**, 不用常量代替。
	add_child(ct)
	await get_tree().process_frame
	ct._build_cursor()
	await get_tree().process_frame
	var paw_art := (ct._g as Control).size.y   # 控件框竖向尺寸 = 在设计像素里画多高(scale=1 时)
	print("  ★真实控件框 _g.size = %s  (ART=%d; 两者不等就是 expand_mode 顺序那个 bug)"
		% [str((ct._g as Control).size), ct.ART])
	print("  不透明 bbox 折回 art px = %d×%d" % [pbb.size.x / 2, pbb.size.y / 2])

	print("── ② / ③ 各窗口尺寸下的 cf 与实际尺寸 ──")
	print("  公式: stretch mode=canvas_items / aspect=expand ⇒ cf = min(win.x/1280, win.y/720)")
	print("  旧代码: cf = clampf(cf, 0.5, 4.0); _cur.scale = base_scl/cf ⇒ 设计px = 控件框/cf")
	print("  现代码: _cur.scale = base_scl(不碰 cf) ⇒ 设计px = 控件框, 恒定")
	print("  ⚠ 下表是【旧缩放口径 × 当前控件框(%d)】。真实旧态控件框是 48(expand_mode 顺序那个 bug),"
		% int(paw_art))
	print("    所以历史上的设计px 是下表的【两倍】(640 宽时 96 = 开打钮高的 155%)。")
	print("    当前真实数值别看这张表 —— 看 verify_ui_consistency 的 CURSOR_SCALE 那一节(量的是活对象)。")
	print("  %-13s %-9s %-9s %-7s %-9s %-9s %-8s" % [
		"窗口", "cf_真实", "cf_用的", "夹住?", "设计px", "物理px", "占开打钮高"])
	var cases := [
		Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440),
		Vector2(640, 360), Vector2(624, 351), Vector2(480, 270),
		Vector2(1560, 720), Vector2(2556, 1179), Vector2(800, 600),
	]
	for win in cases:
		var cf_real: float = minf(win.x / DESIGN.x, win.y / DESIGN.y)
		var cf_used: float = clampf(cf_real, 0.5, 4.0)
		var design_px: float = paw_art / cf_used
		var phys_px: float = design_px * cf_real
		print("  %-13s %-9.4f %-9.4f %-7s %-9.1f %-9.1f %.0f%%" % [
			"%dx%d" % [int(win.x), int(win.y)], cf_real, cf_used,
			("★夹住" if not is_equal_approx(cf_real, cf_used) else "-"),
			design_px, phys_px, design_px / 62.0 * 100.0])

	print("── ④ 参照物(设计px) ──")
	print("  摆位屏「▶ 开 打」钮 = 220×62 (dual_lane_flow.gd custom_minimum_size)")
	print("  摆位提示条 Label    = 460×24")
	print("  仓库自己的触控下限 verify_ui_consistency.TOUCH_MIN = %.0f (44pt)" % UICONS.TOUCH_MIN)
	print("  爪子(不透明高) art px = %.0f" % paw_art)

	print("── ⑤ 手机上有没有这只爪子(读 _ready 的早退条件) ──")
	var src := FileAccess.get_file_as_string("res://autoload/CursorTheme.gd")
	print("  headless 早退      = %s" % str(src.contains("DisplayServer.get_name() == \"headless\"")))
	print("  Android/iOS 早退   = %s" % str(src.contains("OS.get_name() in [\"Android\", \"iOS\"]")))
	print("  当前 OS = %s  DisplayServer = %s" % [OS.get_name(), DisplayServer.get_name()])

	print("── ⑥ 真实 get_screen_transform 能不能在无头里当尺子 ──")
	var vp := get_viewport()
	print("  window.size=%s  viewport.visible_rect=%s  screen_transform.scale=%s" % [
		str(get_window().size), str(vp.get_visible_rect().size),
		str(vp.get_screen_transform().get_scale())])
	get_window().size = Vector2i(624, 351)
	await get_tree().process_frame
	await get_tree().process_frame
	print("  改窗口到 624x351 后: viewport.visible_rect=%s  screen_transform.scale=%s" % [
		str(vp.get_visible_rect().size), str(vp.get_screen_transform().get_scale())])

	ct.queue_free()
	print("PROBE DONE")
	get_tree().quit(0)
