extends Node
## _probe_settle_real.gd — 打一整场【真实双路 6v6】到结算, 量结算屏 + 每页实拍 (2026-10-04)
##
## 只读探针: 不改产品代码, 不进门禁(文件名以 _ 开头, run-tests 不发现)。
## 为「结算屏为什么这么小 / 为什么只有一页」量数值:
##   卡片占屏比 / 表格行高 / 字号(逻辑 px 与物理 px) / 每页总行 vs 首屏可见行 / 各块高度。
##
## ★不改 content_scale_size —— 保留 project.godot 的 1280x720 canvas_items + expand,
##   只把窗口(=根视口)设成目标物理分辨率, 这就是手机上的真实缩放链。
## ★必须开窗口才截得到图(无头抓到空图), 窗口放 --position 5000,5000。
##
## 跑法(Git Bash):
##   PS_W=2340 PS_H=1080 PS_OUT=<目录> SHIP=1 DUALLANE=1 DL_AUTOFIGHT=1 NO_SAVE=1 QUIET=1 \
##   TURTLE_BACKEND=" " TURTLE_SUPABASE=" " APPDATA=<私有> XDG_DATA_HOME=<私有> \
##   <godot> --audio-driver Dummy --position 5000,5000 --resolution 2340x1080 --path . \
##     res://tests/_probe_settle_real.tscn --quit-after 200000

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
	if OS.get_environment("PS_PROTO") != "":
		await _proto(sc, w, h)
	var f := FileAccess.open(_out + "/measure_%dx%d.txt" % [w, h], FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))
		f.close()
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var sp := _out + "/" + name
	var err := img.save_png(sp)
	_p("实拍 %s rc=%d %dx%d" % [name, err, img.get_width(), img.get_height()])


func _measure(sc, w: int, h: int) -> void:
	var hud = sc._hud
	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	var k: float = float(h) / vp.y           # 逻辑 px → 物理 px
	_p("物理 %dx%d · 逻辑视口 %s · 缩放 k=%.3f (1 逻辑px = %.3f 物理px)" % [w, h, str(vp), k, k])
	var card: Control = hud._settle_card
	var scroll_outer: Control = card.get_parent()
	var outer: Control = scroll_outer.get_parent()
	var shell: Control = outer.get_parent()
	var sr: Rect2 = shell.get_global_rect()
	_p("卡片(九宫格外框) 逻辑 %s  占宽 %.0f%%  占高 %.0f%%  占面积 %.0f%%" % [str(sr), 100.0 * sr.size.x / vp.x, 100.0 * sr.size.y / vp.y, 100.0 * sr.size.x * sr.size.y / (vp.x * vp.y)])
	_p("外层滚动区 逻辑高 %.0f (预算 settle_outer_budget=%.0f)  卡内容最小高 %.0f" % [scroll_outer.size.y, hud.settle_outer_budget(vp), card.get_combined_minimum_size().y])
	## 卡片子块逐个高度
	for c in card.get_children():
		if c is Control and (c as Control).visible:
			var cc: Control = c
			var t := ""
			if cc is Label:
				t = "Label fs=%d '%s'" % [(cc as Label).get_theme_font_size("font_size"), (cc as Label).text.left(30)]
			else:
				t = cc.get_class()
			_p("  卡内块 h=%.0f  %s" % [cc.size.y, t])
	for c in outer.get_children():
		if c is Control and c != scroll_outer:
			_p("  按钮行(滚动区外) h=%.0f" % (c as Control).size.y)
	var inner: ScrollContainer = hud._settle_more_scroll
	var ir: Rect2 = inner.get_global_rect()
	_p("战报内层滚动区 逻辑 %s  占屏高 %.0f%%  物理高 %.0f px" % [str(ir), 100.0 * ir.size.y / vp.y, ir.size.y * k])
	var body: Control = inner.get_child(0)
	var pages: Array = body.get_children()
	## 页签按钮
	var tabs: Array = []
	var st: Array = [card]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Button and not ((n as Button).text in ["返回主菜单"]) and n.get_parent() is HBoxContainer and (n.get_parent() as Control).get_parent() is VBoxContainer:
			tabs.append(n)
		for ch in (n as Node).get_children():
			st.append(ch)
	tabs.reverse()
	var tab_txt: Array = []
	for b in tabs:
		tab_txt.append((b as Button).text + "(fs%d)" % (b as Button).get_theme_font_size("font_size"))
	_p("页签 %d 个: %s" % [tabs.size(), str(tab_txt)])
	await _shot("settle_%dx%d_default.png" % [w, h])
	_page_stats(hud, pages, inner, k, "默认页")
	for i in range(tabs.size()):
		(tabs[i] as Button).pressed.emit()
		for _q in range(6):
			await get_tree().process_frame
		await _shot("settle_%dx%d_tab%d.png" % [w, h, i])
		_page_stats(hud, pages, inner, k, "页签 %s" % (tabs[i] as Button).text)


func _page_stats(hud, pages: Array, inner: ScrollContainer, k: float, tag: String) -> void:
	var bar: VScrollBar = inner.get_v_scroll_bar()
	var fold: float = bar.value + bar.page
	for pg in pages:
		if not (pg as Control).visible:
			continue
		var tot := 0
		var vis := 0
		var row_h := 0.0
		var fs := 0
		var gw := 0.0
		for g in (pg as Node).get_children():
			if not (g is GridContainer):
				continue
			gw += (g as Control).size.x
			for ch in (g as Node).get_children():
				if ch is HBoxContainer:
					tot += 1
					if row_h == 0.0:
						row_h = (ch as Control).size.y + float((g as GridContainer).get_theme_constant("v_separation"))
						for l in (ch as Node).get_children():
							if l is Label:
								fs = (l as Label).get_theme_font_size("font_size")
								break
					if hud._settle_local_bottom(ch, inner.get_child(0)) <= fold + 0.5:
						vis += 1
		_p("%s: 两队总行 %d · 首屏看得全 %d · 行距 %.0f 逻辑px(%.0f 物理px) · 名字/数字字号 %d 逻辑px = %.1f 物理px · 两表总宽 %.0f · 提示「%s」" % [tag, tot, vis, row_h, row_h * k, fs, float(fs) * k, gw, hud._settle_more_hint.text])


## ── 原型: 藏掉产品结算卡, 用同一份数据排成三页, 每页实拍 + 量字号/行高
func _proto(sc, w: int, h: int) -> void:
	var center: Control = sc._hud._settle_card.get_parent().get_parent().get_parent().get_parent()
	center.visible = false
	var idx: int = center.get_index()
	var dim = center.get_parent().get_child(idx - 1)
	if dim is ColorRect:
		(dim as ColorRect).visible = false
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var P = load("res://tests/_proto_settle_pages.gd")
	var proto = P.new(sc)
	proto.build(layer, bool(GameState.lane_results.values().count("left") >= 2))
	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	var k: float = float(h) / vp.y
	for i in range(3):
		proto.show_page(i)
		for _q in range(8):
			await get_tree().process_frame
		await _shot("proto_%dx%d_p%d.png" % [w, h, i + 1])
		var pg: Control = proto.pages[i]
		var ov := pg.get_global_rect()
		_p("原型第 %d 页: 页体 %s · 页内容最小高 %.0f(可用 %.0f) · 是否溢出 %s" % [i + 1, str(ov), pg.get_combined_minimum_size().y, ov.size.y, str(pg.get_combined_minimum_size().y > ov.size.y + 0.5)])
		if i > 0:
			var rows := 0
			var rh := 0.0
			for t in pg.get_children():
				if t is GridContainer and (t as Control).visible:
					for ch in (t as Node).get_children():
						if ch is HBoxContainer:
							rows += 1
							rh = (ch as Control).size.y + 10.0
			_p("   可见行 %d · 行距 %.0f 逻辑px(%.0f 物理px) · 名字 22px=%.1f 物理px=%.1fpt · 数字 24px=%.1fpt" % [rows, rh, rh * k, 22.0 * k, 22.0 * 0.5417, 24.0 * 0.5417])
