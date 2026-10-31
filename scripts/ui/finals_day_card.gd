extends Control
## 主菜单决赛日「今天的事」卡(2026-10-31 方案书 20261031c 块 M ①②③ · G14 / G15 / J-1 / 2-1 / 2-2 / 3-1 / 6-3 / 9-11 / 1-11):
##   ┌ 决赛日 ─────────────── [开赛倒计时 | ● 开播中 | 已结束] ┐   ← 状态带三态
##   │ [小组赛 18:00  还有 0:19:32] [冠军杯赛 20:00  还有 2:19:32] │   ← 两张子卡各自倒计时 / 进行中 / 已结束
##   │  小组赛          冠军杯赛                                   │
##   │ [半决赛][决赛]  [1/4][半决赛][决赛]  🏆                     │   ← 我这一路: 打完翻 ✓ / ✗, 尽头奖杯
##   │ (头像) 上周冠军 某某                                        │   ← 上周冠军挂门面(拿不到 ⇒ 今天的看点)
##   └────────────────────────────────────────────────────────────┘
## 整张卡点了直达对阵图(P19 一步到); 主按钮(我的比赛 / 观看开播)在卡下面, 由 menu_finals_day 建。
## ★没进决赛日的人没有「我这一路」, 那一格只写今天的事: 本周 N 人 · 几组 + 此刻在播谁 / 冠军杯赛冠军(今天的看点)。
##   ★不预告下一场比赛(用户 10-31 追问「为什么在这儿提示新的比赛」): 下一站归主菜单的每周赛程条管。
## ★卡底用主菜单玩家卡同一块木板(menu/hud/card.png, 同一屏同一种材质); 子卡 / 格子是暗槽 + 细边、直角硬边。
## 动的: 倒计时每秒走 · 开播点一闪一闪 · 开播那张子卡金边呼吸 · 我这一格呼吸 · 结果到了格子翻牌 · 奖杯隔几秒闪一下。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _F := preload("res://scripts/ui/finals_day_feed.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")

const NODE_NAME := "FinalsCard"
const SIZE := Vector2(480, 272)
const PLATE := "res://assets/sprites/menu/hud/card.png"
const BADGE := "res://assets/sprites/menu/weekend/badge-finals.png"
const TROPHY := "res://assets/sprites/bracket/bracket-trophy.png"
const N_STATE := "FcState"
const N_SUB_G := "FcSubGroup"
const N_SUB_C := "FcSubCup"
const N_PATH := "FcPath"
const N_CHAMP := "FcChamp"
const N_TAP := "FcTap"
const N_WALL := "FcWall"
const WALL_W := 112.0
const PAD := 20.0
const SUB_Y := 62.0
const SUB_H := 74.0
const PATH_Y := 146.0
const CELL := Vector2(62, 46)
const CHAMP_Y := 224.0
const GOLD := Color("#ffc94a")
const CREAM := Color("#fff4d6")
const DIM := Color("#b9b2a6")
const GREEN := Color("#8fdc5a")
const RED := Color("#e0574c")
const SLOT_BG := Color("#1c120a")

const TXT_S3 := {_M.S3_COUNT: "开赛倒计时", _M.S3_LIVE: "开播中", _M.S3_END: "已结束"}

var font: Font = null
## 门禁读: 此刻画的
var state3 := ""
var cells: Array = []
var flips := 0
var _state_lb: Label
var _state_bg: ColorRect
var _state_dot: ColorRect
var _subs: Dictionary = {}         # "g" / "c" → {"box", "edge", "name", "time", "line", "dot"}
var _path_box: Control
var _cell_nodes: Array = []
var _cell_sig := ""
var _champ_box: Control
var _champ_sig := "-"
var _t := 0.0
## 点「冠军墙」⇒ 调它(menu_finals_day 接; 门禁读有没有接上)
var on_wall: Callable = Callable()


func _init(f: Font = null) -> void:
	font = f
	name = NODE_NAME
	size = SIZE
	custom_minimum_size = SIZE
	pivot_offset = SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := NinePatchRect.new()
	plate.name = "FcPlate"
	if ResourceLoader.exists(PLATE):
		plate.texture = load(PLATE)
	plate.patch_margin_left = 40
	plate.patch_margin_right = 40
	plate.patch_margin_top = 16
	plate.patch_margin_bottom = 16
	plate.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	plate.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.size = SIZE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	## 抬头: 徽章 + 决赛日 + 右边状态签
	if ResourceLoader.exists(BADGE):
		var bd := TextureRect.new()
		bd.texture = load(BADGE)
		bd.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bd.position = Vector2(PAD, 16)      # ★16 = 木板上沿边带(card.png 九宫格上边 16), 不压边带(verify_ui_consistency)
		bd.size = Vector2(34, 38)
		bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bd)
	var tl := _lb("FcTitle", "决赛日", 28, CREAM, Vector2(PAD + 44, 16), Vector2(200, 38))
	add_child(tl)
	_state_bg = ColorRect.new()
	_state_bg.name = "FcStateBg"
	_state_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_state_bg)
	_state_dot = ColorRect.new()
	_state_dot.size = Vector2(8, 8)
	_state_dot.color = Color("#fff4ee")
	_state_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_state_dot)
	_state_lb = _lb(N_STATE, "", 17, CREAM, Vector2.ZERO, Vector2(10, 28))
	_state_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_state_lb)
	## 两张子卡
	var sw := (SIZE.x - PAD * 2.0 - 12.0) / 2.0
	_subs["g"] = _sub(N_SUB_G, _P2.STAGE_GROUP, Vector2(PAD, SUB_Y), Vector2(sw, SUB_H))
	_subs["c"] = _sub(N_SUB_C, _P2.STAGE_CUP, Vector2(PAD + sw + 12.0, SUB_Y), Vector2(sw, SUB_H))
	_path_box = Control.new()
	_path_box.name = N_PATH
	_path_box.position = Vector2(PAD, PATH_Y)
	_path_box.size = Vector2(SIZE.x - PAD * 2.0, 70)
	_path_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_path_box)
	_champ_box = Control.new()
	_champ_box.name = N_CHAMP
	_champ_box.position = Vector2(PAD, CHAMP_Y)
	_champ_box.size = Vector2(SIZE.x - PAD * 2.0, 34)
	_champ_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_champ_box)


func _lb(nm: String, txt: String, fs: int, col: Color, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = txt
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("#140a03"))
	l.add_theme_constant_override("outline_size", 6)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 暗槽 + 2px 细边(直角)。返回 [底, 边]。
func _slot(parent: Control, pos: Vector2, sz: Vector2, edge_col: Color) -> Array:
	var edge := ColorRect.new()
	edge.color = edge_col
	edge.position = pos
	edge.size = sz
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(edge)
	var bg := ColorRect.new()
	bg.color = SLOT_BG
	bg.position = pos + Vector2(2, 2)
	bg.size = sz - Vector2(4, 4)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return [bg, edge]


func _sub(nm: String, stage: String, pos: Vector2, sz: Vector2) -> Dictionary:
	var box := Control.new()
	box.name = nm
	box.position = pos
	box.size = sz
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var s := _slot(box, Vector2.ZERO, sz, Color("#5a4630"))
	var n := _lb("Name", stage, 20, CREAM, Vector2(12, 6), Vector2(sz.x - 24, 28))
	box.add_child(n)
	var t := _lb("Time", "", 20, GOLD, Vector2(12, 6), Vector2(sz.x - 24, 28))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(t)
	var dot := ColorRect.new()
	dot.size = Vector2(8, 8)
	dot.position = Vector2(12, 48)
	dot.color = RED
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(dot)
	var ln := _lb("Line", "", 18, GREEN, Vector2(12, 38), Vector2(sz.x - 24, 28))
	box.add_child(ln)
	return {"box": box, "edge": s[1], "name": n, "time": t, "line": ln, "dot": dot}


# ══════════════════════════════ 每秒一拍 ══════════════════════════════

## 按此刻画: `now` = 主菜单那一拍的钟; `ent` = 进了决赛日; f = finals_day_feed.feeds()。
func paint(now: int, ent: bool, f: Dictionary) -> void:
	var groups: Array = f.get("groups", [])
	var cup: Dictionary = f.get("cup", {})
	var group: Dictionary = f.get("group", {})
	state3 = _M.state3(now, groups, cup)
	_paint_state()
	_paint_sub(_subs["g"], _M.group_state(now, groups), _M.seat_ts(now), now)
	_paint_sub(_subs["c"], _M.cup_state(now, cup), _M.cup_ts(now), now)
	cells = _M.path_cells(ent, group, cup, groups, now)
	_paint_path(ent, groups, cup, spectator_lines(now, groups, cup) if not ent else [])
	## 冠军杯赛决出(已揭晓)⇒ 这一行换成这一届的冠军杯赛冠军 + 「冠军墙」入口; 之前挂上周冠军
	var sd := _M.champion_visible(cup, now)
	if sd >= 0 and now >= _M.cup_ts(now):
		var wk: int = _P2.week_anchor_utc(now)
		_paint_champ({"head": "冠军杯赛冠军", "name": _M.name_of(cup, sd), "avatar": _F.avatar_of(wk, _M.tag_of(cup, sd)), "wall": true})
	else:
		var pc: Dictionary = _F.prev_champ
		_paint_champ({"head": "上周冠军", "name": str(pc.get("name", "")), "avatar": str(pc.get("avatar", "")), "wall": false})


func _paint_state() -> void:
	var txt := str(TXT_S3.get(state3, ""))
	_state_lb.text = txt
	var w: float = 18.0 + (font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x if font != null else txt.length() * 17.0)
	var live := state3 == _M.S3_LIVE
	if live:
		w += 14.0
	var x := SIZE.x - PAD - w
	_state_bg.position = Vector2(x, 17)
	_state_bg.size = Vector2(w, 28)
	_state_bg.color = Color("#b8342b") if live else (Color("#5c4a1c") if state3 == _M.S3_COUNT else Color("#3c3a36"))
	_state_dot.visible = live
	_state_dot.position = Vector2(x + 9, 27)
	_state_lb.position = Vector2(x + (14.0 if live else 0.0), 17)
	_state_lb.size = Vector2(w - (14.0 if live else 0.0), 28)


func _paint_sub(s: Dictionary, st: String, at: int, now: int) -> void:
	(s["time"] as Label).text = _P2.local_hhmm(at)
	var ln: Label = s["line"]
	var dot: ColorRect = s["dot"]
	dot.visible = st == _M.S3_LIVE
	ln.position.x = 26.0 if st == _M.S3_LIVE else 12.0
	match st:
		_M.S3_COUNT:
			ln.text = "还有 %s" % _M.clock_text(at - now, true)
			ln.add_theme_color_override("font_color", GREEN)
			(s["edge"] as ColorRect).color = Color("#5a4630")
			(s["box"] as Control).modulate = Color.WHITE
		_M.S3_LIVE:
			ln.text = "进行中"
			ln.add_theme_color_override("font_color", Color("#ff8a7a"))
			(s["edge"] as ColorRect).color = GOLD
			(s["box"] as Control).modulate = Color.WHITE
		_:
			ln.text = "已结束"
			ln.add_theme_color_override("font_color", DIM)
			(s["edge"] as ColorRect).color = Color("#3a3028")
			(s["box"] as Control).modulate = Color(0.75, 0.72, 0.68)


## 「我这一路」。格子数 / 段不变就只换状态(结果到了那一格翻牌); 变了重排。
func _paint_path(ent: bool, groups: Array, cup: Dictionary, spect: Array) -> void:
	var sig := ""
	for c in cells:
		sig += "%s/%s;" % [str(c["sec"]), str(c["label"])]
	if not ent:
		sig = "spect:%s" % "|".join(PackedStringArray(spect))
	if sig != _cell_sig:
		_cell_sig = sig
		for ch in _path_box.get_children():
			ch.queue_free()
		_cell_nodes.clear()
		if not ent:
			_spectator_line(spect)
			return
		_build_cells()
	for i in range(mini(cells.size(), _cell_nodes.size())):
		_paint_cell(_cell_nodes[i], str(cells[i]["st"]))
	if not _cell_nodes.is_empty():
		var end := _M.path_end(cells)
		var tro: CanvasItem = _path_box.get_node_or_null("FcTrophy")
		if tro != null:
			tro.modulate = Color.WHITE if end == 1 else (Color(0.42, 0.40, 0.38) if end == -1 else Color(0.85, 0.82, 0.76))


## 观众那一格的两行(只说今天): [规模 / 今天的两段, 此刻在播谁 / 冠军杯赛冠军 / 进行到哪]。纯读数, 门禁直接量。
static func spectator_lines(now: int, groups: Array, cup: Dictionary) -> Array:
	var n := 0
	for g in groups:
		n += int((g as Dictionary).get("size", 0)) if g is Dictionary else 0
	var l1 := ("本周 %d 人进入决赛日 · %d 组" % [n, groups.size()]) if n > 0 		else "今天 %s %s · %s %s" % [_P2.local_hhmm(_M.seat_ts(now)), _P2.STAGE_GROUP, _P2.local_hhmm(_M.cup_ts(now)), _P2.STAGE_CUP]
	var l2 := ""
	var ph := _M.phase(now, groups, cup)
	var live: Array = _M.live_all(groups, cup, now)
	if ph == _M.PH_DONE:
		l2 = "%s冠军 %s" % [_P2.STAGE_CUP, _M.name_of(cup, _M.champion_visible(cup, now))]
	elif not live.is_empty():
		var t: Dictionary = live[0]
		var pr := _M.pair_names(t["b"], int(t["r"]), int(t["m"]), now)
		l2 = "正在开播：%s 对 %s" % [pr[0], pr[1]] if str(pr[0]) != "" else "%s开播中" % _M.stage_line(t["b"], int(t["r"]))
	elif ph == _M.PH_PRE:
		l2 = "点「观看开播」进入对阵图"
	else:
		l2 = "%s进行中" % (_P2.STAGE_CUP if ph in [_M.PH_CUP, _M.PH_INTER] else _P2.STAGE_GROUP)
	return [l1, l2]


func _spectator_line(spect: Array) -> void:
	var a := _lb("FcSpect1", str(spect[0]), 19, CREAM, Vector2(0, 6), Vector2(_path_box.size.x, 28))
	_path_box.add_child(a)
	var b := _lb("FcSpect2", str(spect[1]), 17, DIM, Vector2(0, 36), Vector2(_path_box.size.x, 26))
	b.clip_text = true
	_path_box.add_child(b)


func _build_cells() -> void:
	var x := 0.0
	var prev := ""
	var sec_x := {}
	for i in range(cells.size()):
		var c: Dictionary = cells[i]
		if str(c["sec"]) != prev:
			if prev != "":
				x += 10.0
			prev = str(c["sec"])
			sec_x[prev] = x
		var cell := Control.new()
		cell.name = "FcCell%d" % i
		cell.position = Vector2(x, 22)
		cell.size = CELL
		cell.pivot_offset = CELL / 2.0
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_path_box.add_child(cell)
		var s := _slot(cell, Vector2.ZERO, CELL, Color("#4a3a28"))
		var lb := _lb("L", str(c["label"]), 14, DIM, Vector2(2, 2), Vector2(CELL.x - 4, 20))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.add_theme_constant_override("outline_size", 4)
		cell.add_child(lb)
		var mark := _Mark.new()
		mark.position = Vector2((CELL.x - 14.0) / 2.0, 24)
		mark.size = Vector2(14, 14)
		cell.add_child(mark)
		_cell_nodes.append({"node": cell, "edge": s[1], "label": lb, "mark": mark, "st": ""})
		x += CELL.x + 6.0
	## 段名(小组赛 / 冠军杯赛)写在那几格上面
	for k in sec_x:
		var t := _lb("FcSec_" + str(k), _P2.STAGE_GROUP if str(k) == "group" else _P2.STAGE_CUP, 15, Color("#d8c9a8"),
			Vector2(float(sec_x[k]), 0), Vector2(200, 20))
		t.add_theme_constant_override("outline_size", 4)
		_path_box.add_child(t)
	## 尽头奖杯(48px = 原件 96 的一半, 整数缩放)
	if ResourceLoader.exists(TROPHY):
		var tr := TextureRect.new()
		tr.name = "FcTrophy"
		tr.texture = load(TROPHY)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(x + 4.0, 18)
		tr.size = Vector2(48, 48)
		tr.pivot_offset = Vector2(24, 24)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_path_box.add_child(tr)


func _paint_cell(cn: Dictionary, st: String) -> void:
	var prev := str(cn["st"])
	if prev == st:
		return
	cn["st"] = st
	var node: Control = cn["node"]
	var apply := func() -> void:
		var edge: ColorRect = cn["edge"]
		var lb: Label = cn["label"]
		var mark = cn["mark"]
		match st:
			_M.C_WON, _M.C_BYE:
				edge.color = GREEN
				lb.add_theme_color_override("font_color", CREAM)
				mark.kind = "check"
				mark.col = GREEN if st == _M.C_WON else Color("#6aa04a")
			_M.C_LOST:
				edge.color = RED
				lb.add_theme_color_override("font_color", CREAM)
				mark.kind = "cross"
				mark.col = RED
			_M.C_NOW:
				edge.color = GOLD
				lb.add_theme_color_override("font_color", GOLD)
				mark.kind = "dot"
				mark.col = GOLD
			_M.C_SKIP:
				edge.color = Color("#2e261e")
				lb.add_theme_color_override("font_color", Color("#6a6258"))
				mark.kind = "dash"
				mark.col = Color("#5a5248")
			_:
				edge.color = Color("#4a3a28")
				lb.add_theme_color_override("font_color", DIM)
				mark.kind = ""
		mark.queue_redraw()
	## 刚建好那一下直接画; 状态变了(结果到了)⇒ 翻牌: 横向压扁 → 换 → 弹回
	if prev == "" or not node.is_inside_tree():
		apply.call()
		return
	flips += 1
	var tw := node.create_tween()
	tw.tween_property(node, "scale:x", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(apply)
	tw.tween_property(node, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _paint_champ(pc: Dictionary) -> void:
	var sig := "%s|%s|%s|%s" % [str(pc.get("head", "")), str(pc.get("name", "")), str(pc.get("avatar", "")), str(pc.get("wall", false))]
	if sig == _champ_sig:
		return
	_champ_sig = sig
	for ch in _champ_box.get_children():
		_champ_box.remove_child(ch)
		ch.queue_free()
	if str(pc.get("name", "")) != "":
		var av := MatchCard.avatar(str(pc.get("avatar", "")), 32.0, false, false, str(pc["name"]).left(1))
		av.position = Vector2(0, 1)
		_champ_box.add_child(av)
		var a := _lb("FcChampHead", str(pc.get("head", "")), 16, DIM, Vector2(42, 3), Vector2(80, 28))
		_champ_box.add_child(a)
		var nw := _champ_box.size.x - 124 - (WALL_W + 8.0 if bool(pc.get("wall", false)) else 0.0)
		var b := _lb("FcChampName", str(pc["name"]), 20, Color("#ffe27a"), Vector2(124, 2), Vector2(nw, 30))
		b.clip_text = true
		_champ_box.add_child(b)
		if bool(pc.get("wall", false)):
			_wall_btn()
	else:
		## 拿不到上周冠军 ⇒ 写今天的看点(冠军拿什么)
		var c := _lb("FcChampHead", "冠军杯赛冠军获得「冠军」头衔", 17, DIM, Vector2(0, 3), Vector2(_champ_box.size.x, 28))
		_champ_box.add_child(c)


## 「冠军墙」入口(卡片里的动作钮 = UISkin.card_button 那一种): 看得见的键 112×34, 点击区按触摸线 81 往上下补(叠在整张卡的点击区上面)。
func _wall_btn() -> void:
	var vis := Button.new()
	vis.name = "FcWallFace"
	vis.text = "冠军墙"
	vis.focus_mode = Control.FOCUS_NONE
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vis.add_theme_font_size_override("font_size", 17)
	UISkin.card_button(vis)
	vis.position = Vector2(_champ_box.size.x - WALL_W, 0)
	vis.size = Vector2(WALL_W, 34)
	_champ_box.add_child(vis)
	var hit := Button.new()
	hit.name = N_WALL
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.position = Vector2(_champ_box.size.x - WALL_W, 17.0 - 40.5)
	hit.size = Vector2(WALL_W, 81)
	hit.mouse_entered.connect(func() -> void: vis.modulate = Color(1.2, 1.15, 1.05))
	hit.mouse_exited.connect(func() -> void: vis.modulate = Color.WHITE)
	hit.pressed.connect(func() -> void:
		if on_wall.is_valid():
			on_wall.call())
	_champ_box.add_child(hit)


func _process(delta: float) -> void:
	_t += delta
	## 开播点一闪一闪; 开播那张子卡金边呼吸; 我这一格呼吸; 奖杯隔 4 秒亮一下
	var blink := 0.55 + 0.45 * absf(sin(_t * 3.2))
	_state_dot.modulate.a = blink
	for k in _subs:
		var s: Dictionary = _subs[k]
		(s["dot"] as CanvasItem).modulate.a = blink
		var e: ColorRect = s["edge"]
		if e.color == GOLD or e.color.is_equal_approx(GOLD):
			e.modulate = Color(1.0 + 0.35 * absf(sin(_t * 2.2)), 1.0 + 0.3 * absf(sin(_t * 2.2)), 1.0, 1.0)
		else:
			e.modulate = Color.WHITE
	for cn in _cell_nodes:
		var ed: ColorRect = cn["edge"]
		ed.modulate = Color(1.0 + 0.4 * absf(sin(_t * 2.6)), 1.0 + 0.35 * absf(sin(_t * 2.6)), 1.0, 1.0) if str(cn["st"]) == _M.C_NOW else Color.WHITE
	var tro: CanvasItem = _path_box.get_node_or_null("FcTrophy")
	if tro != null:
		## 隔 4 秒亮一下(提亮, 不缩放 —— 像素图非整数缩放会糊)
		var ph := fmod(_t, 4.0)
		var k := sin(ph / 0.6 * PI) if ph < 0.6 else 0.0
		tro.self_modulate = Color(1.0 + 0.7 * k, 1.0 + 0.6 * k, 1.0 + 0.3 * k, 1.0)


## 格子里那个记号(像素块画的 ✓ / ✗ / ● / —, 不靠字体里有没有这个字)。
class _Mark extends Control:
	var kind := ""
	var col := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var px := 2.0
		var pts: Array = []
		match kind:
			"check":
				pts = [[0, 3], [1, 4], [2, 5], [3, 4], [4, 3], [5, 2], [6, 1]]
			"cross":
				pts = [[0, 0], [1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [6, 6], [6, 0], [5, 1], [4, 2], [2, 4], [1, 5], [0, 6]]
			"dot":
				pts = [[2, 2], [3, 2], [4, 2], [2, 3], [3, 3], [4, 3], [2, 4], [3, 4], [4, 4]]
			"dash":
				pts = [[1, 3], [2, 3], [3, 3], [4, 3], [5, 3]]
		for p in pts:
			## 粗一点: 每个点画 2×2 个像素格
			draw_rect(Rect2(Vector2(float(p[0]), float(p[1])) * px, Vector2(px * 1.5, px * 1.5)), col)
