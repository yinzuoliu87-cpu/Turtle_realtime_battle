extends RefCounted
## _proto_settle_pages.gd — 结算屏【分页重做】的一次性原型 (2026-10-04, 只为出示意图)
##
## ⚠ 这不是产品代码: 只被 tests/_probe_settle_real.gd 在 PS_PROTO=1 时调用,
##   数据全部走产品自己的读数(_st_lane_hist / _st_row / _st_merge_all / lane_results / 奖励字段),
##   只是换一种排法。方案书见 docs/plans/20261004-结算屏重做.md。
##
## 版式要点(都是方案书 §4 的数):
##   · 左侧竖页签栏(战果 / 我方 / 敌方) —— 横屏多出来的是【宽】不是高, 页签放左边不吃表的高度
##   · 正文字号 ≥ 22 逻辑px(= 11.9pt, 过 iOS HIG 的 11pt 下限); 数字 24
##   · 一页只放一队, 行高 46 ⇒ 合计页 8 行 = 368, 一页放得下, 不用滚
##   · 按钮行永远在右下(与原版同一条底线: 按钮永远够得着)

const F_RESULT := 84
const F_H1 := 30
const F_BODY := 22
const F_NUM := 24
const F_CAP := 18
const ROW_SEP := 10
const RAIL_W := 220.0
const TAB_H := 96.0

var battle
var hud
var root: Control
var pages: Array = []          # [Control] 三页
var rail_btns: Array = []
var lane_pages: Array = []     # 产品同口径: [{lane,title,left,right}]


func _init(b) -> void:
	battle = b
	hud = b._hud


func build(layer: CanvasLayer, won: bool) -> void:
	_collect()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.035, 0.06, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vp: Vector2 = battle.get_viewport().get_visible_rect().size
	var sm: Vector4 = SafeArea.margins(vp, 6.0)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(sm.x + 18))
	m.add_theme_constant_override("margin_right", int(sm.z + 28))
	m.add_theme_constant_override("margin_top", int(sm.y + 18))
	m.add_theme_constant_override("margin_bottom", int(sm.w + 18))
	root.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	m.add_child(hb)
	## ── 左: 竖页签栏
	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_W, 0)
	rail.add_theme_constant_override("separation", 12)
	hb.add_child(rail)
	var big_small := Label.new()
	big_small.text = "胜利" if won else "失败"
	big_small.add_theme_font_size_override("font_size", 40)
	big_small.add_theme_color_override("font_color", Color("#ffd93d") if won else Color("#ff6b6b"))
	big_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail.add_child(big_small)
	for t in ["战果", "我方", "敌方"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(RAIL_W, TAB_H)
		b.add_theme_font_size_override("font_size", F_H1)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var idx := rail_btns.size()
		b.pressed.connect(func() -> void: show_page(idx))
		rail.add_child(b)
		rail_btns.append(b)
	var pager := Label.new()
	pager.name = "Pager"
	pager.text = "← 左右滑动翻页 →"
	pager.add_theme_font_size_override("font_size", F_CAP)
	pager.add_theme_color_override("font_color", Color("#7d8b9c"))
	pager.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail.add_child(pager)
	## ── 右: 页体 + 底部按钮
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	hb.add_child(right)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(body)
	pages.append(_page_result(won))
	pages.append(_page_team("left", "我方", Color("#7ec8ff")))
	pages.append(_page_team("right", "敌方", Color("#ff9a9a")))
	for p in pages:
		(p as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		body.add_child(p)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 24)
	right.add_child(btns)
	btns.add_child(_btn("前往商店", Color("#ffc23c"), Color("#3a1f00")))
	btns.add_child(_btn("返回主菜单", Color("#5aa0d8"), Color("#04121e")))
	show_page(0)


func show_page(i: int) -> void:
	for k in range(pages.size()):
		(pages[k] as Control).visible = (k == i)
	for k in range(rail_btns.size()):
		var b: Button = rail_btns[k]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.66, 0.18, 0.95) if k == i else Color(0.12, 0.17, 0.24, 0.9)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", Color("#2a1600") if k == i else Color("#cfe6ff"))
		b.add_theme_color_override("font_hover_color", Color("#2a1600") if k == i else Color("#cfe6ff"))


func _btn(t: String, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(250, 84)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", fg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	return b


func _lbl(t: String, fs: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = align
	return l


## 与产品 `_build_stats_panel` 同口径地收集分路数据
func _collect() -> void:
	for snap in battle._st_lane_hist:
		lane_pages.append({"lane": snap["lane"], "title": battle._LANE_CN.get(snap["lane"], str(snap["lane"])),
			"left": snap["left"], "right": snap["right"]})
	var cur = {"lane": "cur", "title": "本场", "left": [], "right": []}
	for u in battle._units:
		var sd = battle._eff_side(u)
		if sd == "left" or sd == "right":
			(cur[sd] as Array).append(battle._st_row(u))
	if not ((cur["left"] as Array).is_empty() and (cur["right"] as Array).is_empty()):
		var cl = str(GameState.current_lane)
		cur["title"] = battle._LANE_CN.get(cl, "本场")
		lane_pages.append(cur)
	if lane_pages.size() > 1:
		lane_pages.append({"lane": "all", "title": "合计",
			"left": hud._st_merge_all(lane_pages, "left"), "right": hud._st_merge_all(lane_pages, "right")})


## ── 第 1 页: 战果(胜负 / 各路 / 奖励 / 我方 MVP)
func _page_result(won: bool) -> Control:
	var gs = battle.get_node_or_null("/root/GameState")
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	var acc := Color("#ffd93d") if won else Color("#ff6b6b")
	v.add_child(_lbl("胜利" if won else "失败", F_RESULT, acc, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_lbl(hud._result_subtitle(won, gs), F_BODY + 2, Color("#9fb3c8"), HORIZONTAL_ALIGNMENT_CENTER))
	## 各路: 一路一块, 大字胜负
	var lr: Dictionary = gs.get("lane_results") if gs != null and gs.get("lane_results") is Dictionary else {}
	if not lr.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 26)
		for ln in ["top", "bottom", "final"]:
			if not lr.has(ln):
				continue
			var who := str(lr[ln])
			var box := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.10, 0.15, 0.22, 0.9)
			sb.content_margin_left = 28; sb.content_margin_right = 28
			sb.content_margin_top = 10; sb.content_margin_bottom = 12
			box.add_theme_stylebox_override("panel", sb)
			var bv := VBoxContainer.new()
			bv.add_child(_lbl(str(battle._LANE_CN.get(ln, ln)), F_CAP + 2, Color("#9fb3c8"), HORIZONTAL_ALIGNMENT_CENTER))
			var res := "胜" if who == "left" else ("负" if who == "right" else "平")
			bv.add_child(_lbl(res, 40, Color("#ffd93d") if who == "left" else Color("#ff6b6b"), HORIZONTAL_ALIGNMENT_CENTER))
			box.add_child(bv)
			row.add_child(box)
		v.add_child(row)
	## 奖励: 直接用产品的块, 只把字号放大(原 13/24 → 18/34)
	var chips: Control = hud._build_reward_chips(gs)
	if chips != null:
		(chips as HBoxContainer).add_theme_constant_override("separation", 44)
		for col in chips.get_children():
			var ls: Array = col.get_children()
			if ls.size() >= 2:
				(ls[0] as Label).add_theme_font_size_override("font_size", F_CAP)
				(ls[1] as Label).add_theme_font_size_override("font_size", 34)
		v.add_child(chips)
	## 我方 MVP 一行
	var all: Array = (lane_pages.back() as Dictionary)["left"] if not lane_pages.is_empty() else []
	var mi: int = hud._st_mvp_index(all)
	if mi >= 0:
		var r: Dictionary = all[mi]
		var mv := HBoxContainer.new()
		mv.alignment = BoxContainer.ALIGNMENT_CENTER
		mv.add_theme_constant_override("separation", 16)
		mv.add_child(_lbl("本场 MVP", F_BODY, Color("#ffd93d")))
		mv.add_child(_avatar(r, 64))
		mv.add_child(_lbl(str(r["name"]), F_H1, Color("#ffffff")))
		mv.add_child(_lbl("打出 %d" % int(r["_st_dealt"]), F_H1, Color("#ffd93d")))
		v.add_child(mv)
	return v


func _avatar(r: Dictionary, sz: float) -> Control:
	var id := str(r.get("id", ""))
	var p: String = battle.SPRITE_DIR + "avatars/" + id + ".png"
	if bool(r.get("_st_multi", false)) and not bool(r.get("is_summon", false)):
		p = battle.SPRITE_DIR + "pets/minion.png"
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(sz, sz)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(p):
		tr.texture = load(p)
	return tr


## ── 第 2/3 页: 一队一页
func _page_team(side: String, title: String, hc: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_lbl(title, F_H1 + 4, hc))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	## 分路切换: 合计 / 上路 / 下路(默认合计)
	var tables: Array = []
	var seg_btns: Array = []
	var order: Array = []
	for i in range(lane_pages.size() - 1, -1, -1):
		order.append(i)
	for i in order:
		var b := Button.new()
		b.text = str(lane_pages[i]["title"])
		b.custom_minimum_size = Vector2(110, 56)
		b.add_theme_font_size_override("font_size", F_BODY)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		head.add_child(b)
		seg_btns.append(b)
	v.add_child(head)
	for i in order:
		var t := _team_table(lane_pages[i][side])
		t.visible = (i == order[0])
		v.add_child(t)
		tables.append(t)
	for k in range(seg_btns.size()):
		var kk := k
		(seg_btns[k] as Button).pressed.connect(func() -> void:
			for j in range(tables.size()):
				(tables[j] as Control).visible = (j == kk))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.66, 0.18, 0.95) if k == 0 else Color(0.12, 0.17, 0.24, 0.9)
		(seg_btns[k] as Button).add_theme_stylebox_override("normal", sb)
		(seg_btns[k] as Button).add_theme_color_override("font_color", Color("#2a1600") if k == 0 else Color("#cfe6ff"))
	return v


func _team_table(rows: Array) -> Control:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", ROW_SEP)
	var hd := ["", "打出", "扛住", "治疗", "击杀"]
	for i in range(5):
		var l := _lbl(hd[i], F_CAP + 2, Color("#ffd93d"), HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size = Vector2(360 if i == 0 else 130, 0)
		g.add_child(l)
	var mi: int = hud._st_mvp_index(rows)
	var maxd := 1
	for r in rows:
		maxd = maxi(maxd, int(r["_st_dealt"]))
	for ri in range(rows.size()):
		var r: Dictionary = rows[ri]
		var dead := not bool(r.get("alive", true))
		var nc := HBoxContainer.new()
		nc.custom_minimum_size = Vector2(360, 46)
		nc.add_theme_constant_override("separation", 10)
		nc.add_child(_avatar(r, 40))
		var nm := _lbl(str(r["name"]), F_BODY, Color("#8a96a3") if dead else Color("#ffffff"))
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nc.add_child(nm)
		if dead:
			var dl := _lbl("阵亡", F_CAP, Color("#7d8b9c"))
			dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nc.add_child(dl)
		if ri == mi:
			var mv := _lbl("MVP", F_CAP, Color("#ffd93d"))
			mv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nc.add_child(mv)
		g.add_child(nc)
		var raw := [int(r["_st_dealt"]), int(r["_st_taken"]), int(r["_st_heal"]), int(r["_st_kills"])]
		for i in range(4):
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(130, 0)
			cell.alignment = BoxContainer.ALIGNMENT_CENTER
			var l := _lbl(hud.settle_cell_text(raw[i]), F_NUM, Color("#4e5b68") if raw[i] == 0 else (Color("#ffd93d") if ri == mi else Color("#e8f0f6")), HORIZONTAL_ALIGNMENT_RIGHT)
			cell.add_child(l)
			if i == 0 and raw[0] > 0:
				## 打出那一列带一根占比条: 一眼看出谁是主力, 不用逐个比数字
				var bar := ColorRect.new()
				bar.color = Color("#ffd93d") if ri == mi else Color("#5aa0d8")
				bar.custom_minimum_size = Vector2(130.0 * float(raw[0]) / float(maxd), 4)
				bar.size_flags_horizontal = Control.SIZE_SHRINK_END
				cell.add_child(bar)
			g.add_child(cell)
	return g
