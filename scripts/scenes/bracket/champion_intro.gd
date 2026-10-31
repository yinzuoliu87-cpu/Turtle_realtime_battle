class_name ChampionIntro
extends CanvasLayer
## champion_intro.gd —— 冠军杯开场: 组冠军依次亮相(G7)。可以叠在任何一屏上的独立层。
## 依据 学到的.md 2-3(冠军杯第一轮前所有组冠军依次亮相)、1-14(登场挂来历「第 X 组冠军」, 上届冠军单独标「卫冕」)、
##   1-4(开场先亮出上一届冠军)。
## 拍子: 标题(冠军杯 · 组冠军登场)0.9 s → 每人 1.0 s(从右侧冲到中央、落位白闪、挂来历缎带, 再收进底部一排)
##        → 收尾「冠军杯 即将开播」1.0 s → 自己淡出、发 finished、自删。6 位组冠军 ≈ 7.9 s。
## ★不放按钮; 点屏 = 这一位直接落定(进下一位前停 0.25 s)。按时间算状态, 不用 Tween(同 ChampionShow)。
##
## 用法: ChampionIntro.open(host, ChampionData.cup_intro(view, week, rows, defending_acc)).finished.connect(...)
## data: {"entrants": [{"name", "avatar", "origin": "A 组冠军", "defending": bool, "lineup": [...]}, ...],
##        "week", "edition", "date", "total": 本周决赛日总人数}

signal entrant_shown(index: int)
signal finished

const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const FX := preload("res://scripts/scenes/bracket/champion_fx.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")

const LAYER := 95
const T_TITLE := 0.9
const T_EACH := 1.0
const T_END := 1.0
const T_OUT := 0.3
const SKIP_HOLD := 0.25
const TITLE_Y := 70.0          # 标题缎带中心 y

var data: Dictionary = {}
var auto_advance := true
var t := 0.0
var elapsed := 0.0
var skips := 0
var shown_log: Array = []      # [[index, 落位时刻]]
var vp := Vector2(1280, 720)
var c := Vector2(640, 360)
var _root: Control
var _bg: TextureRect
var _fx
var _flash: ColorRect
var _flash_t := -99.0
var _title: Control
var _sub: Label
var _end: Label
var _cards: Array = []         # {node, slot: Vector2, t0}
var _done := false
var _shown := {}
var face_px := 240.0           # 亮相那一位的头像边长(= 屏高 1/3)
var card_size := Vector2(360, 372)
var present_c := Vector2(640, 345)


static func create(d: Dictionary) -> ChampionIntro:
	var s := ChampionIntro.new()
	s.data = d
	return s


static func open(host: Node, d: Dictionary) -> ChampionIntro:
	var s := create(d)
	host.add_child(s)
	return s


func entrants() -> Array:
	var a = data.get("entrants", [])
	return a if a is Array else []


## 总长(到自删为止)。
func total_length() -> float:
	return T_TITLE + T_EACH * entrants().size() + T_END + T_OUT


func node(nm: String) -> Node:
	return _root.find_child(nm, true, false) if _root != null else null


func _ready() -> void:
	layer = LAYER
	vp = data["vp"] if data.get("vp", null) is Vector2 else get_viewport().get_visible_rect().size   # 门禁量两种比例时直接给
	c = vp * 0.5
	_root = Control.new()
	_root.name = "IntroRoot"
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)
	_bg = UI.tex_rect(UI.TEX_BG, vp, "ArenaBg")
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.position = Vector2.ZERO
	_bg.modulate = Color(0.5, 0.45, 0.5, 0.0)
	_root.add_child(_bg)
	UI.box(_root, Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.03, 0.45), "Dim")
	_fx = FX.new()
	_fx.size = vp
	_root.add_child(_fx)
	_title = UI.ribbon(_root, Vector2(c.x, TITLE_Y), 480, "冠军杯", 48, "gold", "IntroTitle")
	var n := entrants().size()
	var sub := "组冠军登场 · %d 位" % n
	var ed := DATA.edition_line(int(data.get("week", 0)), int(data.get("edition", -1)))
	if ed != "":
		sub += " · " + ed
	_sub = UI.label_in(_root, Rect2(0, TITLE_Y + 54, vp.x, 32), sub, 24, UI.TXT, false, "IntroSub")
	_end = UI.label_in(_root, Rect2(0, c.y - 60, vp.x, 84), "冠军杯 即将开播", 60, UI.GOLD, true, "IntroEnd")
	_end.modulate.a = 0.0
	## 亮相那一位: 头像占屏 1/3 高(手机 240 · iPad 逻辑 320); 卡 = 头像 + 来历缎带 + 名字
	face_px = roundf(vp.y / 3.0)
	card_size = Vector2(maxf(face_px + 40.0, 360.0), face_px + 132.0)
	present_c = Vector2(c.x, TITLE_Y + 88.0 + card_size.y * 0.5)
	## 底部一排: 每位缩到头像约 0.46 倍(手机 110 px), 一排放不下再缩
	var n_f := maxf(1.0, float(n))
	var small := minf(0.44, (vp.x - 80.0) / n_f / (card_size.x + 16.0))
	var slot_w := card_size.x * small + 16.0
	var row_y := vp.y - card_size.y * small * 0.5 - 12.0
	for i in range(n):
		var e: Dictionary = entrants()[i]
		var card := _make_card(e, i)
		var sx := c.x + (float(i) - float(n - 1) * 0.5) * slot_w
		_cards.append({"node": card, "slot": Vector2(sx, row_y), "t0": T_TITLE + T_EACH * i, "small": small})
	_flash = UI.box(_root, Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0), "WhiteFlash")
	_apply()


func _make_card(e: Dictionary, i: int) -> Control:
	var w := card_size.x
	var fp := face_px
	var card := Control.new()
	card.name = "Entrant%d" % i
	card.size = card_size
	card.pivot_offset = card_size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(card)
	var defending := bool(e.get("defending", false))
	UI.portrait(card, Vector2(w * 0.5, fp * 0.5 + 4.0), fp, str(e.get("avatar", "")), UI.GOLD if defending else UI.BRONZE_HI, "Face")
	UI.box(card, Rect2(w * 0.5 - fp * 0.5, 4.0, fp, fp), Color(1, 1, 1, 0), "CardFlash")
	UI.ribbon(card, Vector2(w * 0.5, fp + 34.0), 320, str(e.get("origin", "")), 36, "red", "Origin")
	UI.label_in(card, Rect2(-80, fp + 74.0, w + 160, 56), str(e.get("name", "")), 48, UI.TXT, true, "Name")
	if defending:
		var badge := Control.new()
		badge.name = "Defending"
		badge.size = Vector2(156, 60)
		badge.position = Vector2(w * 0.5 + fp * 0.5 - 96.0, 14.0)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)
		UI.plate(badge, Rect2(0, 0, 156, 60), UI.GOLD, UI.GOLD_DEEP)
		UI.tex_at(badge, UI.TEX_TROPHY, Vector2(32, 30), Vector2(48, 48))
		UI.label_in(badge, Rect2(56, 0, 96, 60), "卫冕", 36, Color("#fff4c8"), true, "DefendingText")
	card.visible = false
	return card


func _process(dt: float) -> void:
	if auto_advance:
		advance(minf(dt, 0.1))


func advance(dt: float) -> void:
	if _done:
		return
	t += dt
	elapsed += dt
	_fx.step(dt)
	_apply()
	if t >= total_length():
		_done = true
		finished.emit()
		queue_free()


## 点屏: 正在亮相的这一位直接落定, 停 SKIP_HOLD 秒进下一位。
func skip_beat() -> void:
	var n := entrants().size()
	if t < T_TITLE:
		skips += 1
		t = T_TITLE - 0.01
		_apply()
		return
	var i := int(floor((t - T_TITLE) / T_EACH))
	if i >= 0 and i < n:
		var land := T_TITLE + T_EACH * i + T_EACH - SKIP_HOLD
		if t < land:
			skips += 1
			t = land
	_apply()


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (ev as InputEventMouseButton).pressed:
		skip_beat()
		_root.accept_event()


func _apply() -> void:
	var tot := total_length()
	var kin := UI.ease_out(UI.seg(t, 0.0, 0.35))
	_bg.modulate.a = kin
	var out := 1.0 - UI.seg(t, tot - T_OUT, tot)
	_root.modulate.a = out
	## 标题缎带落下
	_title.position.y = lerpf(-_title.size.y, TITLE_Y - _title.size.y * 0.5, UI.ease_back(UI.seg(t, 0.05, 0.45)))
	_sub.modulate.a = UI.seg(t, 0.35, 0.7)
	_fx.rays_alpha = 0.4 * kin
	_fx.rays_radius = maxf(vp.x, vp.y) * 0.6
	for i in range(_cards.size()):
		var cd: Dictionary = _cards[i]
		var card: Control = cd["node"]
		var t0: float = cd["t0"]
		if t < t0:
			card.visible = false
			continue
		card.visible = true
		var lt := t - t0
		var k_in := UI.ease_out(UI.seg(lt, 0.0, 0.25))        # 从右侧冲到中央
		var k_out := UI.ease_out(UI.seg(lt, 0.72, 0.98))     # 收进底部一排
		var center := present_c
		var start := Vector2(vp.x + card_size.x, present_c.y)
		var slot: Vector2 = cd["slot"]
		var small: float = cd["small"]
		var p := start.lerp(center, k_in).lerp(slot, k_out)
		var sc := lerpf(1.0, small, k_out)
		card.scale = Vector2.ONE * sc
		card.position = p - card_size * 0.5
		card.z_index = 10 if k_out < 1.0 else 0
		(card.find_child("CardFlash", false, false) as ColorRect).color.a = (1.0 - UI.seg(lt, 0.22, 0.4)) if lt >= 0.22 else 0.0
		if lt >= 0.22 and not _shown.has(i):
			_shown[i] = true
			_flash_t = elapsed - (lt - 0.22)
			_fx.burst(center + Vector2(0, card_size.y * 0.2), 22, 460.0)
			shown_log.append([i, elapsed - (lt - 0.22)])
			entrant_shown.emit(i)
		if lt < 0.98:
			_fx.rays_center = center
	var fa := elapsed - _flash_t
	_flash.color.a = 0.55 * (1.0 - UI.seg(fa, 0.03, 0.12)) if fa >= 0.0 else 0.0
	var te := T_TITLE + T_EACH * _cards.size()
	_end.modulate.a = UI.seg(t, te, te + 0.3)
	_end.scale = Vector2.ONE * lerpf(1.6, 1.0, UI.ease_out(UI.seg(t, te, te + 0.3)))
