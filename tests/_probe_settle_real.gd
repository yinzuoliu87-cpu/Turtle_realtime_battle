extends Node
## _probe_settle_real.gd — 打一整场【真实双路 6v6】到结算, 三页逐页实拍 + 量数 (2026-10-04)
##
## 只读探针: 不进门禁(文件名以 _ 开头, run-tests 不发现)。
## 第一版(方案书调查用)量的是旧的单页卡片 + 原型; 结算屏改成三页之后改成量【产品真屏】:
##   每页实拍一张, 并记下 字号(逻辑 px / pt) / 合计页总行与可见行 / 滚动条 / 按钮与页签矩形。
##
## ★不改 content_scale_size —— 保留 project.godot 的 1280x720 canvas_items + expand,
##   只把窗口(=根视口)设成目标物理分辨率, 这就是手机上的真实缩放链。
## ★必须开窗口才截得到图(无头抓到空图), 窗口放 --position 5000,5000(屏幕上不出现可见窗口)。
##
## 跑法(Git Bash):
##   PS_W=2340 PS_H=1080 PS_OUT=<目录> SHIP=1 DUALLANE=1 DL_AUTOFIGHT=1 NO_SAVE=1 QUIET=1 \
##   TURTLE_BACKEND=" " TURTLE_SUPABASE=" " APPDATA=<私有> XDG_DATA_HOME=<私有> \
##   <godot> --audio-driver Dummy --position 5000,5000 --resolution 2340x1080 --path . \
##     res://tests/_probe_settle_real.tscn --quit-after 400000

const SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _out := ""
var _log: Array = []


func _p(s: String) -> void:
	print("[PSR] " + s)
	_log.append(s)


func _ready() -> void:
	var w: int = int(OS.get_environment("PS_W")) if OS.get_environment("PS_W") != "" else 1280
	var h: int = int(OS.get_environment("PS_H")) if OS.get_environment("PS_H") != "" else 720
	_out = OS.get_environment("PS_OUT")
	get_tree().root.size = Vector2i(w, h)
	for _q in range(6):
		await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.season_leaders = ["stone", "bamboo", "hunter"]
		gs.season_total_battles = 3
		gs.season_level = 5
		gs.dual_active = true
		gs.dual_lineup = {}
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	Engine.time_scale = float(OS.get_environment("PS_TS")) if OS.get_environment("PS_TS") != "" else 6.0
	var t0 := Time.get_ticks_msec()
	while not bool(sc._settled):
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 600000:
			_p("超时: 10 分钟没结算")
			get_tree().quit(3)
			return
	Engine.time_scale = 1.0
	_p("结算出现 墙钟 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var _w := 0.0
	while _w < 2.0:
		await get_tree().process_frame
		_w += get_process_delta_time()
	await _measure(sc, w, h)
	var f := FileAccess.open(_out + "/measure_%dx%d.txt" % [w, h], FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))
		f.close()
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(_out + "/" + name)
	_p("实拍 %s rc=%d %dx%d" % [name, err, img.get_width(), img.get_height()])


func _measure(sc, w: int, h: int) -> void:
	var scr = sc._hud._settle
	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	var k: float = float(h) / vp.y
	_p("物理 %dx%d · 逻辑视口 %s · 1 逻辑px = %.3f 物理px = %.3f pt" % [w, h, str(vp), k, scr.PT_PER_PX])
	for i in range(3):
		scr.show_page(i)
		for _q in range(10):
			await get_tree().process_frame
		await _shot("settle_%dx%d_p%d.png" % [w, h, i + 1])
		var pg: Control = scr.pages[i]
		var body: Control = pg.get_parent()
		_p("第 %d 页「%s」 页内容最小高 %.0f / 页体高 %.0f" % [i + 1, scr.PAGE_NAMES[i],
			pg.get_combined_minimum_size().y, body.size.y])
		var fs_min := 999
		var st: Array = [pg]
		while not st.is_empty():
			var n = st.pop_back()
			if n is Label and (n as Control).is_visible_in_tree() and str((n as Label).text).strip_edges() != "":
				fs_min = mini(fs_min, (n as Label).get_theme_font_size("font_size"))
			for ch in (n as Node).get_children():
				st.append(ch)
		_p("   最小字号 %d 逻辑px = %.1f pt" % [fs_min, float(fs_min) * scr.PT_PER_PX])
		if i >= 1:
			var sc2: ScrollContainer = scr._scrolls[i - 1]
			var bar := sc2.get_v_scroll_bar()
			var rows := 0
			var vis := 0
			for g in scr._grids[i - 1]:
				if not (g as Control).visible:
					continue
				for ch in (g as Node).get_children():
					if ch is HBoxContainer:
						rows += 1
						if sc2.get_global_rect().encloses((ch as Control).get_global_rect()):
							vis += 1
			_p("   行 %d · 完整可见 %d · 滚动 max %.0f page %.0f · 提示「%s」" % [rows, vis, bar.max_value, bar.page, scr.more_hint.text])
	for b in scr.tab_btns:
		_p("页签 %s rect=%s" % [(b as Button).text, str((b as Control).get_global_rect())])
	for b in scr.btn_row.get_children():
		_p("按钮 %s rect=%s" % [(b as Button).text, str((b as Control).get_global_rect())])
