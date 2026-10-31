class_name BracketChrome
extends RefCounted
## bracket_chrome.gd —— 周日对阵图屏幕上的固定件(2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md §4 B 行)
##
## 不跟着对阵走的那几件, 自上而下:
##   · 缎带大标题(冠军杯赛 / 小组赛 · A 组) + 右上阶段页签(小组赛 / 冠军杯赛)
##   · 组页签(⑩ · P9 P10): 「全部」+「A 组 … F 组」, 我那组带「你」, 有场在开播的组挂红灯 —— 原来的「上一组 / 下一组」石板键撤掉
##   · 一句我的处境(⑥ · P3 · Dota A01「YOUR GRAND FINAL MATCH IS IN PROGRESS」)+ 倒计时那一行(`_tip`)+ 备战那一行(`_shop_row`)
##   · 底部: 左「我这一路」格子条(⑯ · G15)/ 中唯一主按钮(⑳ · G25 · S 清单第 5 条)/ 右「下一场 A 对 B · hh:mm」(⑬ · G3)
## ★只读场景的判定, 自己不判胜负 / 不判开播; 倒计时一律走场景的 `countdown_text`(同一种写法只有一份)。
## ★触控热区 ≥ 81(全项目同一条线); 视觉牌子可以比热区小(牌子是热区按钮底下 show_behind_parent 的一块)。

const _H := preload("res://scripts/scenes/bracket/bracket_hero.gd")

const TEX_CHECK := "res://assets/sprites/ui/icon-check.png"
const CHIP_H := 81.0          # 热区
## M 的全局决赛日小条(autoload `FinalsDay`, 48 高、≤ 560 宽): 在场时给它在底部那一条上面留一行停靠位(`finals_bar_dock`),
##   小条居中停在那里, 不再自己找位置落到「我这一路」上(M 截图 14-960)。两比例都量过不重叠(verify_bracket_redo)。
const DOCK_GROUP := "finals_bar_dock"
const AVOID_GROUP := "finals_bar_avoid"
const DOCK_H := 54.0
const CHIP_VIS := 50.0        # 看得见的牌子
const FOOT_H := 92.0          # 底部那一条的高

var s
var hdr: Control = null
var live_texts: Array = []    # [[Label, Callable], ...] 每 0.5 秒刷新
var _blink: Array = []
var _t := 0.0


func _init(scene) -> void:
	s = scene


func clear() -> void:
	if hdr != null and is_instance_valid(hdr):
		hdr.queue_free()
	hdr = null
	live_texts.clear()
	_blink.clear()


func tick(dt: float) -> void:
	_t += dt
	for nd in _blink:
		if is_instance_valid(nd):
			(nd as CanvasItem).modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 5.0))


func refresh_texts() -> void:
	for it in live_texts:
		if is_instance_valid(it[0]):
			(it[0] as Control).set("text", str((it[1] as Callable).call()))


# ═══════════════════════════════════════════════════════════════════
#  搭整条(对阵 / 宫格 / 空态都调): 返回对阵区上下沿 {"top", "bottom"}
# ═══════════════════════════════════════════════════════════════════
func build(vp: Vector2, with_board: bool) -> Dictionary:
	clear()
	hdr = Control.new()
	hdr.name = "HeroHeader"
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(hdr)
	s.move_child(hdr, s._canvas.get_index() + 1)
	var sm: Vector4 = SafeArea.margins(vp, 0.0)
	## ── 缎带大标题 ──
	var rib_w: float = clampf(vp.x * 0.27, 300.0, 430.0)
	var rib := Rect2(Vector2((vp.x - rib_w) * 0.5, 6.0), Vector2(rib_w, 58.0))
	s._hero._ribbon(hdr, rib, str(s._info.hero_title()), 24, false)
	if s._top_bar != null and s._top_bar.title_label != null:
		var tl: Label = s._top_bar.title_label
		tl.visible = tl.position.x + tl.get_combined_minimum_size().x + 16.0 < rib.position.x
	## ── 阶段页签(右上): 热区 81 高, 牌子 50 高 ──
	_style_stage_tabs(vp, sm)
	## ── 冠军墙入口(G12 · 往届冠军): 页签左边; 放不下(窄屏缎带占了)就放到页签下面靠右 ──
	_wall_button(vp, sm, rib)
	var y := 66.0
	## ── 组页签 ──
	if bool(s._info.chips_on()):
		_group_chips(vp, y)
		y += CHIP_H - 6.0
	else:
		_hide_chips()
	## ── 一句处境 ──
	var st := s._hero._label("", 20, _H.GOLD, true) as Label
	st.name = "HeroStatus"
	st.position = Vector2(0.0, y)
	st.size = Vector2(vp.x, 28.0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.text = str(s._info.hero_status_line())
	st.add_to_group(AVOID_GROUP)
	hdr.add_child(st)
	live_texts.append([st, func() -> String: return str(s._info.hero_status_line())])
	y += 30.0
	## (收盘后不预告下一场比赛 —— 用户 10-31「为什么在这儿提示新的比赛」: 「下一站」归主菜单的每周赛程条,
	##   对阵图收盘只讲结果: 领奖台 / 冠军 / 比分 / 参赛者滚动。)
	## ── 倒计时 / 备战两行(场景的 `_tip` / `_shop_row`, 门禁读它们): 位置在这里定, 字在轮询里写 ──
	s._hero_line0_y = y
	var shop_txt: String = str(s.shop_row_text())
	s._hero_line1_y = y + 24.0
	var tip_on: bool = str(s.tip_text()) != "" or (s._tip != null and s._tip.visible)
	if tip_on:
		y += 24.0
	if shop_txt != "":
		y += 22.0
	_style_line(s._tip, 17, _H.TXT)
	_style_line(s._shop_row, 16, _H.GOLD)
	if s._tip != null:
		s._tip.position = Vector2(0.0, s._hero_line0_y)
		s._tip.size = Vector2(vp.x, 22.0)
	if s._shop_row != null:
		s._shop_row.position = Vector2(0.0, s._hero_line1_y if tip_on else s._hero_line0_y)
		s._shop_row.size = Vector2(vp.x, 22.0)
		if not tip_on:
			s._hero_line1_y = s._hero_line0_y
	var top := y + 40.0
	var bottom := vp.y - FOOT_H - 6.0
	if with_board and bool(s.finals_bar_on()):
		var dock := Control.new()
		dock.name = "FinalsBarDock"
		dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.position = Vector2(vp.x * 0.5 - 290.0, vp.y - FOOT_H - DOCK_H - 2.0)
		dock.size = Vector2(580.0, DOCK_H - 4.0)
		dock.add_to_group(DOCK_GROUP)
		hdr.add_child(dock)
		bottom -= DOCK_H
	## ── 底部 ──
	if with_board:
		_footer(vp, sm)
	return {"top": top, "bottom": bottom}


func _style_line(lb: Label, fs: int, col: Color) -> void:
	if lb == null:
		return
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.02, 0.95))
	lb.add_theme_constant_override("outline_size", 5)


## 一块「热区按钮 + 底下的牌子」: 牌子用 show_behind_parent 画在按钮字的后面。
static func plate_button(b: Button, w: float, on: bool, gold_edge: bool = false) -> void:
	for sk in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(sk, StyleBoxEmpty.new())
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, CHIP_H)
	b.size = b.custom_minimum_size
	for k in b.get_children():
		if str(k.name) == "Plate":
			k.queue_free()
	var plate := Control.new()
	plate.name = "Plate"
	plate.show_behind_parent = true
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(0.0, (CHIP_H - CHIP_VIS) * 0.5)
	plate.size = Vector2(w, CHIP_VIS)
	b.add_child(plate)
	var edge := _H.GOLD if on else (_H.GOLD_DEEP if gold_edge else _H.BRONZE)
	var bg := Color("#3a2a20") if on else Color("#1d161b")
	_add_box(plate, Rect2(-2, -2, w + 4, CHIP_VIS + 4), _H.INK)
	_add_box(plate, Rect2(0, 0, w, CHIP_VIS), edge)
	_add_box(plate, Rect2(2, 2, w - 4, CHIP_VIS - 4), bg)
	if on:
		_add_box(plate, Rect2(2, CHIP_VIS - 6, w - 4, 4), _H.GOLD)
	b.add_theme_color_override("font_color", _H.GOLD if on else _H.TXT_DIM)
	b.add_theme_color_override("font_hover_color", _H.GOLD if on else _H.TXT)
	b.add_theme_color_override("font_pressed_color", _H.GOLD)
	b.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.02, 0.95))
	b.add_theme_constant_override("outline_size", 4)


static func _add_box(parent: Control, r: Rect2, col: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = col
	cr.position = r.position
	cr.size = Vector2(maxf(r.size.x, 1.0), maxf(r.size.y, 1.0))
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)
	return cr


func _style_stage_tabs(vp: Vector2, sm: Vector4) -> void:
	if s._tabs == null:
		return
	var tw := 0.0
	for i in range(s._tabs.get_child_count()):
		var tb := s._tabs.get_child(i) as Button
		var on: bool = (i == 0 and str(s._view) == "bucket") or (i == 1 and str(s._view) == "finals")
		var f: Font = tb.get_theme_font("font")
		var w := 132.0
		if f != null:
			w = maxf(120.0, ceilf(f.get_string_size(tb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x) + 36.0)
		tb.add_theme_font_size_override("font_size", 19)
		plate_button(tb, w, on)
		tw += w
	s._tabs.add_theme_constant_override("separation", 8)
	tw += 8.0 * float(maxi(0, s._tabs.get_child_count() - 1))
	s._tabs.position = Vector2(vp.x - tw - 16.0 - sm.z, -8.0)
	s._tabs.size = Vector2(tw, CHIP_H)


func _wall_button(vp: Vector2, sm: Vector4, rib: Rect2) -> void:
	var b := Button.new()
	b.name = "ChampionWallBtn"
	b.text = "冠军墙"
	b.add_theme_font_size_override("font_size", 18)
	var w := 108.0
	plate_button(b, w, false, true)
	b.pressed.connect(func(): s._ceremony.open_wall())
	hdr.add_child(b)
	var tx: float = s._tabs.position.x if s._tabs != null else vp.x - 16.0 - sm.z
	var x := tx - w - 8.0
	var y := -8.0
	if x < rib.end.x + 8.0:
		x = vp.x - w - 16.0 - sm.z
		y = 66.0
	b.position = Vector2(x, y)


# ── 组页签(⑩): 「全部」+ 各组。点哪一组看哪一组; 「全部」= 宫格总览(⑲) ──
func _group_chips(vp: Vector2, y: float) -> void:
	var bar: HBoxContainer = s._spec_bar
	bar.visible = true
	for i in [0, 1, 2]:
		(bar.get_child(i) as Control).visible = false
	for k in bar.get_children():
		if k.has_meta("chip"):
			bar.remove_child(k)
			k.queue_free()
	var items: Array = s._info.chip_items()       # [{"key": "all"/组号, "text", "on", "mine", "live"}]
	var total_w := 0.0
	for it in items:
		var b := Button.new()
		b.set_meta("chip", str(it["key"]))
		b.name = "GroupChip"
		b.text = str(it["text"])
		b.add_theme_font_size_override("font_size", 17)
		var f: Font = b.get_theme_font("font")
		var w := 86.0
		if f != null:
			w = maxf(76.0, ceilf(f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x) + 30.0)
		plate_button(b, w, bool(it["on"]), bool(it["mine"]))
		var key = it["key"]
		b.pressed.connect(func(): s.pick_chip(key))
		bar.add_child(b)
		var plate: Control = b.get_node_or_null("Plate")
		if bool(it["mine"]) and plate != null:
			## 我那一组: 右上角一枚金色「你」
			var ys := s._hero._label("你", 11, Color("#2a1a06"), false) as Label
			_add_box(plate, Rect2(w - 17, -6, 18, 16), _H.GOLD)
			ys.position = Vector2(w - 17, -7)
			ys.size = Vector2(18, 16)
			ys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plate.add_child(ys)
		if bool(it["live"]) and plate != null:
			## 这一组有场在开播: 左上一盏红灯(G23 · 宫格那一格同一个意思)
			var lamp := _add_box(plate, Rect2(5, 5, 7, 7), _H.LIVE)
			_blink.append(lamp)
		total_w += w
	bar.add_theme_constant_override("separation", 6)
	total_w += 6.0 * float(maxi(0, items.size() - 1))
	bar.position = Vector2((vp.x - total_w) * 0.5, y - 8.0)
	bar.size = Vector2(total_w, CHIP_H)


func _hide_chips() -> void:
	var bar: HBoxContainer = s._spec_bar
	if bar == null:
		return
	for k in bar.get_children():
		if k.has_meta("chip"):
			bar.remove_child(k)
			k.queue_free()


# ═══════════════════════════════════════════════════════════════════
#  底部: 我这一路 · 主按钮 · 下一场
# ═══════════════════════════════════════════════════════════════════
func _footer(vp: Vector2, sm: Vector4) -> void:
	var y0 := vp.y - FOOT_H
	var cta: Dictionary = s._info.cta_spec()
	var cta_w := 0.0
	if not cta.is_empty():
		cta_w = _place_cta(vp, cta)
	var side_w := (vp.x - cta_w) * 0.5 - 24.0
	var path: Dictionary = s._info.my_path()
	if not (path.get("cells", []) as Array).is_empty() and side_w >= 200.0:
		_path_strip(Rect2(Vector2(14.0 + sm.x, y0), Vector2(side_w - sm.x, FOOT_H - 8.0)), path)
	var nx: Dictionary = s._info.next_info()
	if not nx.is_empty() and side_w >= 210.0:
		_next_plate(Rect2(Vector2(vp.x * 0.5 + cta_w * 0.5 + 18.0, y0 + 10.0), Vector2(side_w - 6.0 - sm.z, FOOT_H - 26.0)), nx)


## 唯一主按钮。返回它的宽。
func _place_cta(vp: Vector2, spec: Dictionary) -> float:
	var b: Button = s.ensure_cta()
	b.visible = true
	b.disabled = not bool(spec.get("enabled", false))
	b.text = str(spec.get("text", ""))
	b.set_meta("rm", spec.get("rm", Vector2i(-1, -1)))
	b.set_meta("kind", str(spec.get("kind", "")))
	var kind := str(spec.get("kind", ""))
	var skin := UISkin.PX_RED if (kind == "live" or kind == "live_pick") else (UISkin.PX_GOLD if (kind == "cup" or kind == "replay") else UISkin.PX_SLATE)
	if str(b.get_meta("skin", "")) != skin:
		UISkin.pixel_button(b, skin, 5)
		b.set_meta("skin", skin)
	b.add_theme_font_size_override("font_size", 22 if (kind == "live" or kind == "live_pick") else 19)
	var f: Font = b.get_theme_font("font")
	var w := 320.0
	if f != null:
		w = clampf(f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x + 64.0, 300.0, 460.0)
	b.custom_minimum_size = Vector2(w, 72.0)
	b.size = b.custom_minimum_size
	b.position = Vector2((vp.x - w) * 0.5, vp.y - b.size.y - 12.0)
	b.pivot_offset = b.size * 0.5
	b.set_meta("breathe", kind == "live" or kind == "live_pick")
	if bool(spec.get("tick", false)):
		live_texts.append([b, func() -> String: return str(s._info.cta_spec().get("text", b.text))])
	return w


## 「我这一路」(⑯ · G15 · PTCG Live 3-1): 小组赛几格 + 冠军杯赛几格, 尽头奖杯; 打完翻 ✓ / ✗。
func _path_strip(r: Rect2, path: Dictionary) -> void:
	var box := Control.new()
	box.name = "MyPath"
	box.add_to_group(AVOID_GROUP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = r.position
	box.size = r.size
	hdr.add_child(box)
	var cells: Array = path.get("cells", [])
	var split := int(path.get("split", cells.size()))
	var cw := clampf((r.size.x - 44.0 - 10.0) / float(maxi(1, cells.size())) - 6.0, 30.0, 44.0)
	var x := 0.0
	var cy := 22.0
	var title := s._hero._label("我这一路", 13, _H.TXT_DIM, true) as Label
	title.position = Vector2(0, 0)
	title.size = Vector2(120, 18)
	box.add_child(title)
	for i in range(cells.size()):
		if i == split and split > 0:
			x += 10.0                  # 小组赛 | 冠军杯赛 之间留一道缝
		var c: Dictionary = cells[i]
		var rc := Rect2(Vector2(x, cy), Vector2(cw, cw))
		_cell(box, rc, str(c.get("state", "pending")))
		var lb := s._hero._label(str(c.get("label", "")), 12, _H.TXT if str(c.get("state", "")) != "locked" else _H.TXT_FAINT, true) as Label
		lb.position = Vector2(x - 8.0, cy + cw + 2.0)
		lb.size = Vector2(cw + 16.0, 16.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(lb)
		x += cw + 6.0
	## 尽头奖杯(夺冠 = 亮, 其余压暗)
	if ResourceLoader.exists(_H.TEX_TROPHY):
		var tr := TextureRect.new()
		tr.texture = load(_H.TEX_TROPHY)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.size = Vector2(cw + 8.0, cw + 8.0)
		tr.position = Vector2(x + 2.0, cy - 4.0)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not bool(path.get("champion", false)):
			tr.modulate = Color(0.45, 0.42, 0.42, 0.9)
		box.add_child(tr)


func _cell(box: Control, rc: Rect2, st: String) -> void:
	_add_box(box, rc.grow(2.0), _H.INK)
	var edge := _H.BRONZE
	var bg := Color("#1d161b")
	match st:
		"won":
			edge = _H.GOLD
			bg = Color("#5a4220")
		"bye":
			edge = _H.GOLD_DEEP
			bg = Color("#3a2c1e")
		"lost":
			edge = _H.LOSS
			bg = Color("#2a1416")
		"live", "next":
			edge = _H.GOLD
			bg = Color("#2b2016")
		"locked":
			edge = Color("#3a3034")
			bg = Color("#141015")
	var e := _add_box(box, rc, edge)
	_add_box(box, rc.grow(-2.0), bg)
	match st:
		"won", "bye":
			if ResourceLoader.exists(TEX_CHECK):
				var tr := TextureRect.new()
				tr.texture = load(TEX_CHECK)
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.position = rc.position + Vector2(4, 4)
				tr.size = rc.size - Vector2(8, 8)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if st == "bye":
					tr.modulate = Color(0.8, 0.72, 0.55, 0.85)
				box.add_child(tr)
		"lost":
			s._hero._x_mark(box, rc.grow(-4.0))
		"live":
			var lamp := _add_box(box, Rect2(rc.get_center() - Vector2(5, 5), Vector2(10, 10)), _H.LIVE)
			_blink.append(lamp)
			_blink.append(e)
		"next":
			_blink.append(e)


## 「下一场 A 对 B · hh:mm」(⑬ · G3 · TI / CRL「NEXT MATCH」条)
func _next_plate(r: Rect2, nx: Dictionary) -> void:
	var box := Control.new()
	box.name = "NextMatch"
	box.add_to_group(AVOID_GROUP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = r.position
	box.size = r.size
	hdr.add_child(box)
	_add_box(box, Rect2(Vector2(-2, -2), r.size + Vector2(4, 4)), _H.INK)
	_add_box(box, Rect2(Vector2.ZERO, r.size), _H.BRONZE)
	_add_box(box, Rect2(Vector2(2, 2), r.size - Vector2(4, 4)), Color("#1d161b"))
	var hd := s._hero._label(str(nx.get("head", "下一场")), 13, _H.GOLD, true) as Label
	hd.position = Vector2(10, 2)
	hd.size = Vector2(r.size.x - 20, 20)
	box.add_child(hd)
	var tm := s._hero._label(str(nx.get("time", "")), 13, _H.TXT_DIM, false) as Label
	tm.position = Vector2(10, 2)
	tm.size = Vector2(r.size.x - 20, 20)
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(tm)
	var vs := s._hero._label(str(nx.get("pair", "")), 17, _H.TXT, true) as Label
	vs.name = "NextPair"
	vs.position = Vector2(10, 22)
	vs.size = Vector2(r.size.x - 20, r.size.y - 26)
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(vs)
