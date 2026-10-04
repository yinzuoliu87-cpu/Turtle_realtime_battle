extends Control
## 周六赛况板 —— 本周闯关赛全场战绩 + 最近打完的对局, 点一场看回放。
## 方案书: docs/plans/20261004-周末看回放.md §4.1。数据层(纯函数)在 `scripts/systems/replay/gauntlet_board.gd`。
##
## 用户 2026-10-04:「周六连对阵图都没有吗」「周六是怎么样的比如100位玩家开打」⇒ 选 A: 保留异步闯关, 加赛况板。
##
## ★版式: 左栏战绩榜、右栏对局流水(点名字 ⇒ 右栏只剩他的那几场)。皮全是仓里现成的:
##   行 = `slot-frame.png`(与战绩页同一张), 状态签 / 回放签 = `chip-frame.png`。不新加素材。
## ★机器人对手在这里与真人**同一种长相**: 名字与 #ID 都来自快照 profile, 数据层不分真假(也分不出)。
##   这一屏任何地方都不写「机器人」(用户 2026-10-04「不能让玩家知道是机器人」)。
## ★没接服务器 / 服务端不认这条查询 / 断网 ⇒ 顶上一句话, 不报错, 不建死按钮。

const TopBar = preload("res://scripts/util/top_bar.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")
const Board := preload("res://scripts/systems/replay/gauntlet_board.gd")
const ReplayFetcher := preload("res://scripts/systems/replay/replay_fetcher.gd")

## 看完回放回到这一页。
const SELF_SCENE := "res://scenes/GauntletBoard.tscn"
const TITLE := "周六赛况"
const W := 1280.0
const COL_Y := 128.0
const COL_H := 560.0
const LEFT_X := 40.0
const LEFT_W := 560.0
const RIGHT_X := 640.0
const RIGHT_W := 600.0
const ROW_H := 44.0
const AVATAR_PX := 40.0
const CHIP_W := 76.0
const REFRESH_SEC := 30.0
const REPLAY_LABEL := "回放"
const REPLAY_BUSY := "读取中"
const ALL_GAMES := "最近打完的对局"
const MINE := Color("#ffd93d")

var _top_bar = null
var _status: Label = null
var _players_box: VBoxContainer = null
var _games_box: VBoxContainer = null
var _games_title: Label = null
var _all_btn: Button = null
var _timer: Timer = null

## 门禁读: 数据 / 现在看的是谁(""= 全部) / 最近一次点回放的结果。
var data: Dictionary = {}
var focus_tag := ""
var load_state := ""            # "" 还没问 / loading / ok / 原因码
var last_replay_code := ""
var last_replay_msg := ""
var _busy := ""
var _inflight := false
var _closed := false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


func _ready() -> void:
	_bg()
	_top_bar = TopBar.new(self, {
		"title": TITLE,
		"palette": TopBar.DEEP,
		"width": W,
		"on_back": _back,
	})
	_all_btn = _top_bar.add_right_action("看全部", _show_all)
	_all_btn.name = "AllGamesBtn"
	_all_btn.visible = false

	_status = Label.new()
	_status.name = "BoardStatus"
	_status.position = Vector2(0.0, 92.0)
	_status.size = Vector2(W, 26.0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color("#9fb0c4"))
	add_child(_status)

	_players_box = _column(LEFT_X, LEFT_W, "战绩榜")
	_games_box = _column(RIGHT_X, RIGHT_W, ALL_GAMES)
	_games_title = _games_box.get_meta("title") as Label

	_timer = Timer.new()
	_timer.wait_time = REFRESH_SEC
	_timer.timeout.connect(refresh)
	add_child(_timer)
	_timer.start()
	refresh()
	UIFrame.attach(self)


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## 去服务端取一次(进页面 + 每 30 秒)。
func refresh() -> void:
	if _inflight or _busy != "":
		return
	var now: int = P2C.now_utc()
	var wk: int = P2C.week_anchor_utc(now)
	_closed = now >= P2C.gauntlet_close_ts(wk)
	if not SB.enabled():
		_set_status("no_backend")
		return
	if load_state == "":
		_set_status("loading")
	_inflight = SB.fetch_gauntlet_board_async(wk, _on_rows)
	if not _inflight:
		_set_status("no_backend")


func _on_rows(res: Dictionary) -> void:
	_inflight = false
	if not is_inside_tree():
		return
	if not res.has("rows"):
		## ★问不到就别抹掉上一份好数据(网络抖一下榜不许消失); 只换顶上那句话。
		_set_status(str(res.get("reason", res.get("err", "server"))))
		return
	set_rows(res["rows"])


## 喂行(门禁也直接调它)。
func set_rows(rows: Array) -> void:
	data = Board.build(rows, BE.my_tag(), _closed)
	_set_status("ok")
	_render()


func _set_status(code: String) -> void:
	load_state = code
	if _status == null:
		return
	var c := Color("#ff9b7a")
	var t := ""
	match code:
		"loading":
			t = "正在取本周闯关赛况…"
			c = Color("#9fb0c4")
		"ok":
			var pn: int = (data.get("players", []) as Array).size()
			var gn: int = (data.get("games", []) as Array).size()
			if gn == 0:
				t = "本周闯关赛还没有打完的对局"
			else:
				t = "本周闯关赛 · %d 人 · %d 场%s" % [pn, gn, " · 已收盘" if _closed else ""]
			c = Color("#9fb0c4")
		"unavailable":
			t = "赛况暂无"
		"no_backend":
			t = "这个版本没接服务器，看不到全场赛况"
		_:
			t = ReplayFetcher.message(code)
	_status.text = t
	_status.add_theme_color_override("font_color", c)


# ─────────────────────────────── 画 ───────────────────────────────

func _render() -> void:
	for c in _players_box.get_children():
		c.queue_free()
	var rank := 0
	for p in data.get("players", []):
		rank += 1
		_players_box.add_child(_player_row(p, rank))
	_render_games()


func _render_games() -> void:
	for c in _games_box.get_children():
		c.queue_free()
	var games: Array = data.get("games", [])
	if focus_tag != "":
		games = Board.games_of(games, focus_tag)
		var nm := focus_tag
		for p in data.get("players", []):
			if str(p["tag"]) == focus_tag:
				nm = "%s %s" % [str(p["name"]), focus_tag]
		_games_title.text = "%s 今天的对局" % nm
	else:
		_games_title.text = ALL_GAMES
	_all_btn.visible = focus_tag != ""
	for g in games:
		_games_box.add_child(_game_row(g))


## 一栏 = 小标题 + 滚动列表。返回列表本体(小标题挂在 meta 上)。
func _column(x: float, w: float, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(x, COL_Y)
	v.custom_minimum_size = Vector2(w, 0)
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var lh := Label.new()
	lh.text = title
	lh.add_theme_font_size_override("font_size", 14)
	lh.add_theme_color_override("font_color", Color("#58d3ff"))
	v.add_child(lh)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(w, COL_H - 30.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	list.set_meta("title", lh)
	return list


## 一行的牌子(与战绩页同一张 `slot-frame.png`, 颜色走 modulate)。
func _plate(tint: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.098, 0.133, 0.176, 1.0)
	sb.set_corner_radius_all(0)
	sb.border_width_left = 4
	sb.border_color = tint
	var st := UISkin.nine("slot-frame.png", 12, sb)
	if st is StyleBoxTexture:
		(st as StyleBoxTexture).modulate_color = tint
	st.content_margin_left = 14; st.content_margin_right = 14
	st.content_margin_top = 8; st.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", st)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return pc


const STATE_TINT := {
	"in": Color(1.30, 1.06, 0.60),
	"out": Color(0.56, 0.63, 0.76),
	"running": Color(0.80, 1.10, 1.08),
}
const STATE_FONT := {
	"in": Color("#ffe3a0"),
	"out": Color("#7f8c99"),
	"running": Color("#9ff0e0"),
}


func _player_row(p: Dictionary, rank: int) -> Control:
	var st := str(p.get("state", "running"))
	var pc := _plate(STATE_TINT.get(st, Color.WHITE))
	pc.name = "PlayerRow"
	pc.set_meta("tag", str(p["tag"]))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var rk := _label(str(rank), 16, Color("#c7b489"))
	rk.custom_minimum_size = Vector2(28, ROW_H)
	rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(rk)
	hb.add_child(_avatar(str(p.get("avatar", "")), st == "out"))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 0)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(nv)
	var me := bool(p.get("me", false))
	nv.add_child(_label(str(p["name"]) + ("（我）" if me else ""), 15, MINE if me else Color("#e8eef5")))
	nv.add_child(_label(str(p["tag"]), 11, Color("#77889a")))
	var rec := _label("%d-%d" % [int(p["w"]), int(p["l"])], 22, Color("#ffffff"))
	rec.custom_minimum_size = Vector2(52, ROW_H)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(rec)
	hb.add_child(_chip(str(p["state_text"]), STATE_TINT.get(st, Color.WHITE), STATE_FONT.get(st, Color.WHITE)))
	_hit(pc, "PlayerBtn", str(p["tag"]), _on_player_pressed.bind(str(p["tag"])))
	if focus_tag != "" and focus_tag == str(p["tag"]):
		pc.modulate = Color(1.15, 1.15, 1.15)
	return pc


func _game_row(g: Dictionary) -> Control:
	var lw := bool(g.get("lw", false))
	var pc := _plate(Color(0.80, 0.90, 1.05))
	pc.name = "GameRow"
	pc.set_meta("match_id", str(g["id"]))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var tl := _label(_rel_time(int(g.get("t", 0))), 11, Color("#7f8c99"))
	tl.custom_minimum_size = Vector2(56, ROW_H)
	hb.add_child(tl)
	hb.add_child(_side_box(g["l"], lw))
	var vs := _label("对", 13, Color("#77889a"))
	vs.custom_minimum_size = Vector2(22, ROW_H)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(vs)
	hb.add_child(_side_box(g["r"], not lw))
	hb.add_child(_chip(REPLAY_LABEL, Color(0.74, 0.84, 0.98), Color("#c9d6e4"), "ReplayChipText"))
	var names := {"l": str(g["l"].get("name", "?")), "r": str(g["r"].get("name", "?"))}
	_hit(pc, "GameBtn", str(g["id"]), _on_game_pressed.bind(str(g["id"]), names))
	return pc


## 对局里的一方: 头像 + 名字。赢的那一方名字亮金、带一个「赢」字; 输的压暗。
func _side_box(s: Dictionary, won: bool) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_avatar(str(s.get("avatar", "")), not won))
	var nm := str(s.get("name", "?"))
	var me := str(s.get("tag", "")) != "" and str(s.get("tag", "")) == BE.my_tag()
	var lb := _label(nm + ("（我）" if me else ""), 14,
		(MINE if won else Color("#6f7f8e")))
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.clip_text = true
	hb.add_child(lb)
	if won:
		hb.add_child(_label("赢", 13, MINE))
	return hb


func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 签牌(`chip-frame.png`, 与战绩页「回放」签同一张)。
func _chip(t: String, tint: Color, fc: Color, label_name: String = "") -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(CHIP_W, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#26313d")
	fb.set_corner_radius_all(0)
	var sb := UISkin.nine("chip-frame.png", 7, fb)
	if sb is StyleBoxTexture:
		(sb as StyleBoxTexture).modulate_color = tint
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	chip.add_theme_stylebox_override("panel", sb)
	var l := _label(t, 13, fc)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if label_name != "":
		l.name = label_name
	chip.add_child(l)
	return chip


func _avatar(pid: String, dim: bool) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#070d16") if dim else Color("#0a1422")
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color("#2a3946") if dim else Color("#6a5a34")
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(AVATAR_PX, AVATAR_PX)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(AVATAR_PX, AVATAR_PX)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		tex.modulate = Color(0.46, 0.52, 0.60)
	var path := "res://assets/sprites/avatars/%s.png" % pid
	if pid != "" and ResourceLoader.exists(path):
		tex.texture = load(path)
	pc.add_child(tex)
	return pc


## 整行是热区(透明按钮盖在牌子上; 宽 ≥ 200 ⇒ 触控下限的豁免条件, 与战绩页回放行同一个做法)。
func _hit(pc: PanelContainer, nm: String, key: String, cb: Callable) -> void:
	var bt := Button.new()
	bt.name = nm
	bt.set_meta("key", key)
	bt.focus_mode = Control.FOCUS_NONE
	bt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		bt.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	bt.mouse_entered.connect(func() -> void: pc.self_modulate = Color(1.12, 1.12, 1.12))
	bt.mouse_exited.connect(func() -> void: pc.self_modulate = Color.WHITE)
	bt.pressed.connect(cb)
	pc.add_child(bt)


func _rel_time(t: int) -> String:
	if t <= 0:
		return ""
	var d: int = maxi(0, P2C.now_utc() - t)
	if d < 60:
		return "刚刚"
	if d < 3600:
		return "%d 分钟前" % (d / 60)
	if d < 86400:
		return "%d 小时前" % (d / 3600)
	return "%d 天前" % (d / 86400)


# ─────────────────────────────── 点 ───────────────────────────────

func _on_player_pressed(tag: String) -> void:
	if _busy != "":
		return
	focus_tag = "" if focus_tag == tag else tag
	_render()


func _show_all() -> void:
	focus_tag = ""
	_render()


func _on_game_pressed(id: String, names: Dictionary) -> void:
	if _busy != "":
		return
	_busy = id
	_set_busy(id, true)
	ReplayFetcher.open(get_tree(), id, _on_replay_done, SELF_SCENE, names)


## `ReplayFetcher.open` 的回调, 恰好一次。code == "" ⇒ 已经换到战斗场了。
func _on_replay_done(code: String, msg: String) -> void:
	last_replay_code = code
	last_replay_msg = msg
	var id := _busy
	_busy = ""
	if code == "":
		return
	_set_busy(id, false)
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", Color("#ff9b7a"))


func _set_busy(id: String, busy: bool) -> void:
	for b in find_children("GameBtn", "Button", true, false):
		(b as Button).disabled = busy
		if str((b as Button).get_meta("key", "")) == id:
			var t := (b as Button).get_parent().find_child("ReplayChipText", true, false) as Label
			if t != null:
				t.text = REPLAY_BUSY if busy else REPLAY_LABEL


func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
	var ov := ColorRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.color = Color(0.031, 0.047, 0.078, 0.35)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
