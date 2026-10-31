extends Control
## 「你的半决赛 19 秒后开播 · 观看」顶部横幅(2026-10-31 方案书 20261031c 块 M ⑤ · J-3 / J-5 / Brawlhalla「YOUR MATCH IS ACTIVE」/ 王者「比赛即将开始：10」)。
## 不论人在哪一屏都弹(全局层里); 从顶部滑下来, 不挡整屏(没有遮罩, 只占顶上中间一块: 主菜单玩家卡与货币条之间, 两比例同宽)。
##   ┌────────────────────────────────────────────────┐
##   │ (19)  你的半决赛 19 秒后开播                       │   ← 倒计时圆环(一秒一格往回走) + 标题
##   │  ◯    C 组 · 吃货一枚 对 Kiki                       │
##   │ [我] VS [对手]               [稍后] [ 观看 ]       │   ← 双方头像 + VS 盾徽; 「观看」主按钮亮色呼吸
##   └────────────────────────────────────────────────┘
## ★还没开播就点「观看」⇒ 不硬开(点开只能对着第 0 步干等), 改成「开播后自动进入」, 到点由 layer 自动开。
## 按钮一律 UISkin.card_button(卡片 / 弹框里不用木牌按钮); 头像框 / VS 盾徽与冠军仪式、观战开场同一套(同一场赛事)。

const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const VS_CREST := "res://assets/sprites/finals/vs-crest-gold.png"
const N_TITLE := "FdPopTitle"
const N_SUB := "FdPopSub"
const N_WATCH := "FdPopWatch"
const N_LATER := "FdPopLater"
const N_RING := "FdPopRing"

const W := 560.0                 # ★主菜单顶上玩家卡右沿到货币条左沿那一段只有 ~575(两比例同), 放得进去、两边各留几像素
const H := 188.0
const AV := 58.0
const GOLD := Color("#d9a441")
const TXT_WATCH := "观看"
const TXT_LATER := "稍后"
const TXT_AUTO := "开播后自动进入"
const LEAD := 30.0               # 圆环满格 = 30 秒

var title: Label
var sub: Label
var watch: Button
var later: Button
var ring: Control
var key := ""                    # 哪一场(组:轮-场)
var armed := false               # 点过「观看」、等开播自动进
var stage_name := "比赛"         # 「你的半决赛」那三个字(轮次名)
var _last_title := ""
var _t := 0.0
var _me_av: Control
var _opp_av: Control

signal watch_pressed
signal later_pressed


func _init() -> void:
	name = "FinalsDayPopup"
	size = Vector2(W, H)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	## 硬边像素横幅: 墨线 + 金边 + 暗底 + 上沿亮线(与冠军仪式的牌同一种做法)
	UI.box(self, Rect2(Vector2(-3, -3), size + Vector2(6, 6)), UI.INK)
	UI.box(self, Rect2(Vector2.ZERO, size), GOLD)
	UI.box(self, Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color("#1d1708"))
	UI.box(self, Rect2(Vector2(3, 3), Vector2(W - 6, 2)), GOLD.lightened(0.3))
	UI.box(self, Rect2(Vector2(3, H - 9), Vector2(W - 6, 6)), Color("#120c05"))        # 底下一条暗边(厚度)
	ring = _Ring.new()
	ring.name = N_RING
	ring.position = Vector2(18, 12)
	ring.size = Vector2(72, 72)
	add_child(ring)
	title = _lb(N_TITLE, 26, Color("#ffd27a"), 6)
	title.position = Vector2(104, 10)
	title.size = Vector2(W - 104 - 16, 38)
	add_child(title)
	sub = _lb(N_SUB, 18, Color("#fff1d6"), 4)
	sub.position = Vector2(104, 50)
	sub.size = Vector2(W - 104 - 16, 30)
	sub.clip_text = true
	add_child(sub)
	## 第二行: 双方头像 + VS 盾徽(左), 两颗键(右)
	var row_y := 96.0
	var mid := row_y + 81.0 * 0.5
	_me_av = UI.portrait(self, Vector2(18 + AV * 0.5, mid), AV, "", Color("#7ee08a"), "FdPopMe")
	var vs := UI.tex_at(self, VS_CREST, Vector2(18 + AV + 32, mid), Vector2(48, 48), "FdPopVs")
	vs.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_opp_av = UI.portrait(self, Vector2(18 + AV + 64 + AV * 0.5, mid), AV, "", Color("#e0574c"), "FdPopOpp")
	later = _btn(N_LATER, TXT_LATER, Vector2(110, 81))
	later.position = Vector2(W - 16 - 190 - 10 - 110, row_y)
	later.pressed.connect(func() -> void: later_pressed.emit())
	add_child(later)
	watch = _btn(N_WATCH, TXT_WATCH, Vector2(190, 81))
	watch.position = Vector2(W - 16 - 190, row_y)
	watch.add_theme_color_override("font_color", Color("#ffe9a8"))
	watch.add_theme_font_size_override("font_size", 28)
	watch.pressed.connect(func() -> void: watch_pressed.emit())
	add_child(watch)


func _lb(nm: String, fs: int, col: Color, ol: int) -> Label:
	var l := Label.new()
	l.name = nm
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", ol)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(nm: String, txt: String, sz: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.custom_minimum_size = sz
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 24)
	UISkin.card_button(b)
	return b


## 双方头像(id 空 = 默认头像)。
func set_pair(me_av: String, opp_av: String) -> void:
	for pr in [[_me_av, me_av], [_opp_av, opp_av]]:
		var face := (pr[0] as Control).get_node_or_null("Face") as TextureRect
		if face != null:
			face.texture = UI.tex(UI.avatar_path(str(pr[1])))


## 写字。`secs` ≥ 0 ⇒「你的半决赛 N 秒后开播」(每秒一跳, 圆环少一格); -1 ⇒「你的半决赛开播中」;
##   -2 ⇒「你的半决赛即将开播」(小组赛等翻面: 服务端给的时刻到了还没翻, 圆环转圈等)。
func paint(secs: int, line: String) -> void:
	var t := ""
	if secs >= 0:
		t = "你的%s %d 秒后开播" % [stage_name, maxi(1, secs)]
	elif secs == -2:
		t = "你的%s即将开播" % stage_name
	else:
		t = "你的%s开播中" % stage_name
	if t != _last_title:
		_last_title = t
		title.text = t
		## 数字跳一下(倒数在动)
		title.pivot_offset = Vector2(0, title.size.y / 2.0)
		title.scale = Vector2(1.06, 1.06)
		title.create_tween().tween_property(title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sub.text = line
	ring.secs = secs
	ring.frac = clampf(float(secs) / LEAD, 0.0, 1.0) if secs >= 0 else 0.0
	ring.queue_redraw()
	var waiting := secs >= 0 or secs == -2
	watch.text = TXT_AUTO if armed and waiting else TXT_WATCH
	watch.add_theme_font_size_override("font_size", 20 if armed and waiting else 28)
	watch.disabled = armed and waiting


## 从顶部滑下来(先藏在屏外) + 落定时冲亮一下。
func enter(home: Vector2) -> void:
	position = Vector2(home.x, home.y - H - 20.0)
	var tw := create_tween()
	tw.tween_property(self, "position", home, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate", Color(1.35, 1.3, 1.15, 1.0), 0.1)
	tw.tween_property(self, "modulate", Color.WHITE, 0.4)


func _process(delta: float) -> void:
	_t += delta
	## 「观看」亮色呼吸(就绪光, 与主菜单主按钮同一种节奏); 等开播时不呼吸
	var k := 0.5 + 0.5 * sin(_t * 3.4)
	watch.modulate = Color(1.0 + 0.28 * k, 1.0 + 0.22 * k, 1.0 + 0.05 * k, 1.0) if not watch.disabled else Color.WHITE
	ring.spin = _t
	if int(ring.secs) < 0:
		ring.queue_redraw()                   # 转圈 / 红点闪都要每帧重画


## 倒计时圆环: 暗槽一整圈 + 金色那一段按剩余秒数往回缩, 中间是秒数。开播中 ⇒ 红点一闪一闪 + 「开播」。
class _Ring extends Control:
	var frac := 1.0
	var secs := 30
	var spin := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 5.0
		draw_circle(c, r + 4.0, Color("#0b0809"))
		draw_arc(c, r, 0.0, TAU, 48, Color("#3a2a14"), 8.0, false)
		if secs == -2:
			## 即将开播: 一段金弧转圈(等服务端翻面)
			draw_arc(c, r, spin * 4.0, spin * 4.0 + TAU * 0.3, 16, Color("#f4c552"), 8.0, false)
		elif secs >= 0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color("#f4c552"), 8.0, false)
			var f := get_theme_default_font()
			var s := str(maxi(0, secs))
			var fs := 26
			var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(f, c + Vector2(-w * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
			draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ffe9a8"))
		else:
			draw_arc(c, r, 0.0, TAU, 48, Color("#d8473f"), 8.0, false)
			var a := 0.45 + 0.55 * absf(sin(spin * 4.0))
			draw_circle(c, 9.0, Color(1.0, 0.95, 0.93, a))
