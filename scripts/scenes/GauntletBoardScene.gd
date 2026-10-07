extends Control
## 周六赛况板 —— 本周闯关赛全场战绩 + 最近打完的对局, 点「观看」看别人的那一场。
## 方案书: docs/plans/20261004-周末看回放.md §4.1; 第三轮版式 docs/plans/20261005-回放体验打磨.md「第三轮」。
## 数据层(纯函数)在 `scripts/systems/replay/gauntlet_board.gd`。
##
## 用户 2026-10-04:「周六连对阵图都没有吗」「周六是怎么样的比如100位玩家开打」⇒ 选 A: 保留异步闯关, 加赛况板。
## 用户 2026-10-07:「回放我说最重要的是周六周日啊，观看别人的啊」⇒ 第三轮按 TV Royale 重做:
##   原来一行一场的小条 + 一枚很小的「回放」签, 右半屏大片空着(docs/plans/ref/20261007-周末观战参考/before.jpg)。
##   现在: 左栏战绩榜(名次 / 头像 / 名字 / 战绩 / 状态), 右栏每场一张满宽对局卡
##   (横幅「谁获胜 · 多久之前」/ 双方名字 + 三统领头像 VS / 右边一颗大的「观看」)。
## ★卡片件与战绩页同一套(`scripts/scenes/record/match_card.gd`), 不另抄一份。
## ★「观看」只在 `Board.watchable(g)` 为真的卡上出(不放死按钮)。
## ★机器人对手在这里与真人**同一种长相**: 名字与 #ID 都来自快照 profile, 数据层不分真假(也分不出)。
##   这一屏任何地方都不写「机器人」(用户 2026-10-04「不能让玩家知道是机器人」)。
## ★没接服务器 / 服务端不认这条查询 / 断网 ⇒ 屏幕正中一块提示框(金属框 + 像素图标), 不报错, 不建死按钮。
## ★★2026-10-07 实时观赛(docs/plans/20261007-实时观赛.md, 用户「周六即有回放也有正在打的啊」):
##   右栏顶上「正在打」: 每场一张卡(双方名字 + 阵容 + VS + 红底「直播」横幅, **不写胜负**) + 「观赛」;
##   战绩榜上正在打的人, 状态签换成红色「直播」。打完那一场从这里消失、出现在「最近对局」(写胜负 + 「观看」=回放)。
##   数据: 服务端 `live_matches`(`SupabaseNet.fetch_live_board_async`, 每 10 秒)。表没部署 / 断网 ⇒ 这一块不出, 不报错。

const TopBar = preload("res://scripts/util/top_bar.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")
const Board := preload("res://scripts/systems/replay/gauntlet_board.gd")
const ReplayFetcher := preload("res://scripts/systems/replay/replay_fetcher.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const Live := preload("res://scripts/systems/replay/live_spectate.gd")

## 看完回放回到这一页。
const SELF_SCENE := "res://scenes/GauntletBoard.tscn"
const TITLE := "周六赛况"
const W := 1280.0
const H := 720.0
const COL_Y := 124.0
const COL_BOTTOM := 708.0
const LEFT_X := 24.0
const LEFT_W := 420.0
const RIGHT_X := 464.0
const RIGHT_W := 792.0
const ROW_H := 64.0
const ROW_AVATAR := 48.0
const CARD_AVATAR := 52.0
const REFRESH_SEC := 30.0
const WATCH_LABEL := "观看"
const WATCH_BUSY := "读取中"
const ALL_GAMES := "最近对局"
const LIVE_HEAD := "正在打"
const LIVE_REFRESH_SEC := 10.0
const LIVE_RED := Color("#d8473f")
const MINE := Color("#ffd93d")
## 节点名 —— 门禁按名字找。
const N_CARD := "GameCard"
const N_WATCH := "GameBtn"
const N_LIVE_CARD := "LiveCard"
const N_LIVE_BTN := "LiveBtn"
const N_LIVE_CHIP := "LiveChip"
const N_SUB_HEAD := "GamesSubHead"

var _top_bar = null
var _status: Label = null
var _players_box: VBoxContainer = null
var _games_box: VBoxContainer = null
var _games_title: Label = null
var _cols: Array = []
var _notice: Dictionary = {}
var _all_btn: Button = null
var _timer: Timer = null

## 门禁读: 数据 / 现在看的是谁(""= 全部) / 最近一次点观看的结果。
var data: Dictionary = {}
var focus_tag := ""
var load_state := ""            # "" 还没问 / loading / ok / 原因码
var last_replay_code := ""
var last_replay_msg := ""
var _busy := ""
var _inflight := false
var _closed := false
## 正在打(门禁读): 筛过的卡。`_base` = 只由「最近对局」算出来的那份(标直播之前), `_live_rows` = 服务端原始行。
var live_games: Array = []
var _live_rows: Array = []
var _live_inflight := false
var _base: Dictionary = {}


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
	_all_btn = _top_bar.add_right_action("查看全部", _show_all)
	_all_btn.name = "AllGamesBtn"
	_all_btn.visible = false

	_players_box = _column(LEFT_X, LEFT_W, "战绩榜")
	_games_box = _column(RIGHT_X, RIGHT_W, ALL_GAMES)
	_games_title = _games_box.get_meta("title") as Label

	## ★提示框先建、字后建(加入顺序 = 绘制顺序)。
	_notice = MatchCard.notice_panel(self, 620.0)
	var np := _notice["panel"] as PanelContainer
	np.position = Vector2((W - 620.0) * 0.5, 260.0)
	np.visible = false

	## 顶上那一行: 有数据时是「本周闯关赛 · N 人 · M 场」, 出错时是那句话; 没数据时由正中的提示框说。
	_status = Label.new()
	_status.name = "BoardStatus"
	_status.position = Vector2(0.0, 92.0)
	_status.size = Vector2(W, 26.0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color("#9fb0c4"))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	_timer = Timer.new()
	_timer.wait_time = REFRESH_SEC
	_timer.timeout.connect(refresh)
	add_child(_timer)
	_timer.start()
	var lt := Timer.new()
	lt.wait_time = LIVE_REFRESH_SEC
	lt.timeout.connect(_refresh_live)
	add_child(lt)
	lt.start()
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
	## ★先标「在路上」再发: 回包同步回来时(假传输 / 缓存)回调先于这一行返回, 后标会把它永远卡在「在路上」。
	_inflight = true
	if not SB.fetch_gauntlet_board_async(wk, _on_rows):
		_inflight = false
		_set_status("no_backend")
	_refresh_live()


## 去问「本周还在打的」(进页面 + 每 10 秒)。没接服务器就什么都不发。
func _refresh_live() -> void:
	if _live_inflight or not SB.enabled():
		return
	var now: int = P2C.now_utc()
	_live_inflight = true
	if not SB.fetch_live_board_async(P2C.week_anchor_utc(now), now - SB.LIVE_BOARD_WINDOW_SEC, _on_live_rows):
		_live_inflight = false


func _on_live_rows(res: Dictionary) -> void:
	_live_inflight = false
	if not is_inside_tree():
		return
	if res.has("rows"):
		set_live_rows(res["rows"])
	elif str(res.get("reason", "")) == "unavailable":
		set_live_rows([])          # 表还没部署: 不出这一块
	## 断网 / 超时: 留着上一份, 下一拍再问(「还在打吗」每次按服务端钟重算)。


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
	_base = Board.build(rows, BE.my_tag(), _closed)
	_apply_live()
	_set_status("ok")
	_render()


## 喂直播行(门禁也直接调它)。
func set_live_rows(rows: Array) -> void:
	_live_rows = rows.duplicate()
	_apply_live()
	if load_state == "ok" or not live_games.is_empty():
		_set_status("ok")
	_render()


## 「最近对局」那份 + 直播行 ⇒ 屏上那份(`data`): 筛出还在打的卡, 战绩榜标「直播」(没上榜的补一行 0-0)。
func _apply_live() -> void:
	data = _base.duplicate(true)
	if data.is_empty():
		data = {"players": [], "games": []}
	var ids: Array = []
	for g in data.get("games", []):
		ids.append(str(g["id"]))
	live_games = Board.live_games(_live_rows, ids, P2C.now_utc())
	Board.mark_live(data, live_games, BE.my_tag())


func _set_status(code: String) -> void:
	load_state = code
	if _status == null:
		return
	var c := Color("#ff9b7a")
	var t := ""
	var sub := ""
	var icon := "icon-quota"
	match code:
		"loading":
			t = "读取中…"
			c = Color("#9fb0c4")
		"ok":
			var pn: int = (data.get("players", []) as Array).size()
			var gn: int = (data.get("games", []) as Array).size()
			var ln: int = live_games.size()
			if gn == 0 and ln == 0:
				t = "暂无已完成对局"
				sub = "周六闯关赛对局结束后在此显示"
				icon = "icon-record"
			else:
				t = "本周闯关赛 · %d 人 · %d 场%s%s" % [pn, gn, (" · 正在打 %d 场" % ln) if ln > 0 else "",
					" · 已截止" if _closed else ""]
			c = Color("#9fb0c4")
		"unavailable":
			t = "赛况暂无"
			icon = "icon-lock"
		"no_backend":
			t = "当前版本不支持在线赛况"
			icon = "icon-lock"
		_:
			t = ReplayFetcher.message(code)
			sub = "每 %d 秒自动刷新" % int(REFRESH_SEC)
	_status.text = t
	_status.add_theme_color_override("font_color", c)
	## 有内容就留在顶上那一行; 一点内容都没有 ⇒ 整页只剩这一句, 放进正中的提示框里说。
	var empty: bool = (data.get("players", []) as Array).is_empty() and (data.get("games", []) as Array).is_empty()
	_layout_status(empty, sub, icon)


## 两种摆法: 顶上一行小字 / 正中一块提示框。★框里的主文抄 `_status.text`(门禁与旧调用点都读 `_status`,
##   它仍是唯一那份字; 框只是换个地方把它说出来)。
func _layout_status(empty: bool, sub: String, icon: String) -> void:
	for c in _cols:
		(c as Control).visible = not empty
	(_notice["panel"] as PanelContainer).visible = empty
	_status.visible = not empty
	if empty:
		MatchCard.notice_set(_notice, _status.text, sub, icon)


# ─────────────────────────────── 画 ───────────────────────────────

func _render() -> void:
	for c in _players_box.get_children():
		_players_box.remove_child(c)     # 先摘下再释放: 新建的同名节点才拿得到原名(门禁按名字找)
		c.queue_free()
	var rank := 0
	for p in data.get("players", []):
		rank += 1
		_players_box.add_child(_player_row(p, rank))
	_render_games()


func _render_games() -> void:
	for c in _games_box.get_children():
		_games_box.remove_child(c)
		c.queue_free()
	var games: Array = data.get("games", [])
	var lives: Array = live_games
	if focus_tag != "":
		games = Board.games_of(games, focus_tag)
		lives = Board.games_of(lives, focus_tag)
		var nm := focus_tag
		for p in data.get("players", []):
			if str(p["tag"]) == focus_tag:
				nm = "%s %s" % [str(p["name"]), focus_tag]
		_games_title.text = "%s 的对局" % nm
	else:
		_games_title.text = LIVE_HEAD if not lives.is_empty() else ALL_GAMES
	_all_btn.visible = focus_tag != ""
	## 正在打的在最上面; 下面一条小标题「最近对局」隔开打完的(只在两种都有时出)。
	var k := 0
	for g in lives:
		_games_box.add_child(_live_card(g, k))
		k += 1
	if not lives.is_empty() and not games.is_empty():
		var sh := _label(ALL_GAMES, 16, Color("#58d3ff"))
		sh.name = N_SUB_HEAD
		_games_box.add_child(sh)
	var i := 0
	for g in games:
		_games_box.add_child(_game_card(g, i))
		i += 1


## 一栏 = 小标题 + 滚动列表。返回列表本体(小标题挂在 meta 上)。
func _column(x: float, w: float, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(x, COL_Y)
	v.custom_minimum_size = Vector2(w, 0)
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	_cols.append(v)
	var lh := Label.new()
	lh.text = title
	lh.add_theme_font_size_override("font_size", 16)
	lh.add_theme_color_override("font_color", Color("#58d3ff"))
	v.add_child(lh)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(w, COL_BOTTOM - COL_Y - 30.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	list.set_meta("title", lh)
	return list


const STATE_TINT := {
	"in": Color(1.30, 1.06, 0.60),
	"out": Color(0.56, 0.63, 0.76),
	"running": Color(0.80, 1.10, 1.08),
}
## 状态签: 实心斜面块(底色, 暗边, 字色)。
const STATE_CHIP := {
	"in": [Color("#b98a22"), Color("#5e420c"), Color("#fff1c4")],
	"out": [Color("#3a4654"), Color("#1c242e"), Color("#9aa8b6")],
	"running": [Color("#1f6f63"), Color("#0c312b"), Color("#d8fff6")],
	"live": [Color("#c0392f"), Color("#5c120d"), Color("#ffffff")],
}


## 战绩榜一行: 名次 / 头像 / 名字 + #ID / 战绩 / 状态签。整行是热区(点名字 ⇒ 右栏只剩他的那几场)。
func _player_row(p: Dictionary, rank: int) -> Control:
	var st := str(p.get("state", "running"))
	var pc := PanelContainer.new()
	pc.name = "PlayerRow"
	pc.set_meta("tag", str(p["tag"]))
	pc.add_theme_stylebox_override("panel", MatchCard.card_style(STATE_TINT.get(st, Color.WHITE), 12, 6))
	pc.custom_minimum_size = Vector2(LEFT_W - 12.0, ROW_H)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var rk := _label(str(rank), 20, Color("#ffd93d") if rank <= 3 else Color("#c7b489"))
	rk.custom_minimum_size = Vector2(30, 0)
	rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(rk)
	hb.add_child(MatchCard.avatar(str(p.get("avatar", "")), ROW_AVATAR, false, st == "out"))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 0)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(nv)
	var me := bool(p.get("me", false))
	var nm := _label(str(p["name"]) + ("（我）" if me else ""), 17, MINE if me else Color("#e8eef5"))
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nv.add_child(nm)
	nv.add_child(_label(str(p["tag"]), 13, Color("#8796a6")))
	var rec := _label("%d-%d" % [int(p["w"]), int(p["l"])], 26, Color("#ffffff"))
	rec.custom_minimum_size = Vector2(60, 0)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	rec.add_theme_constant_override("outline_size", 4)
	hb.add_child(rec)
	if bool(p.get("live", false)):
		## 正在打 ⇒ 状态签换成红色「直播」(皇室战争部落列表里正在打的人旁那颗红点)。
		var lc := _chip(Live.TAG_LIVE, STATE_CHIP["live"])
		lc.name = N_LIVE_CHIP
		hb.add_child(lc)
	else:
		hb.add_child(_chip(str(p["state_text"]), STATE_CHIP.get(st, STATE_CHIP["running"])))
	_hit(pc, "PlayerBtn", str(p["tag"]), _on_player_pressed.bind(str(p["tag"])))
	if focus_tag != "" and focus_tag == str(p["tag"]):
		pc.modulate = Color(1.3, 1.22, 0.95)
	return pc


## 一场 = 一张卡(TV Royale 的骨架): [横幅 谁获胜 · 多久之前] / [左三头像 VS 右三头像 …… 观看]。
## ★胜负不只靠颜色: 横幅上写着胜者的名字; 胜者名字金色, 负者压暗。
func _game_card(g: Dictionary, idx: int) -> Control:
	var lw := bool(g.get("lw", false))
	var pc := PanelContainer.new()
	pc.name = N_CARD + str(idx)
	pc.set_meta("match_id", str(g["id"]))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", MatchCard.card_style())
	pc.custom_minimum_size = Vector2(RIGHT_W - 12.0, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	var mine := _is_me(g["l"]) or _is_me(g["r"])
	vb.add_child(MatchCard.banner("%s 获胜" % Board.winner_name(g), _rel_time(int(g.get("t", 0))),
		Color("#5a4a1c") if mine else Color("#24394e"), Color("#2a2008") if mine else Color("#0f1c28"),
		MINE, Color("#c9d6e4")))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(pad)
	body.add_child(_side_of(g["l"], lw, false))
	body.add_child(MatchCard.vs_label(MatchCard.NAME_H + CARD_AVATAR - 4.0))
	body.add_child(_side_of(g["r"], not lw, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(sp)
	if Board.watchable(g):
		var names := {"l": str(g["l"].get("name", "?")), "r": str(g["r"].get("name", "?"))}
		var bt := MatchCard.big_btn(WATCH_LABEL, N_WATCH)
		bt.set_meta("key", str(g["id"]))
		bt.set_meta("label", WATCH_LABEL)
		bt.pressed.connect(_on_game_pressed.bind(str(g["id"]), names))
		body.add_child(bt)
	return pc


## 正在打的一场: [红底横幅「直播」· 多久前开打] / [左三头像 VS 右三头像 …… 观赛]。
## ★不写胜负: 双方名字同一种颜色、都不压暗(观赛 ≠ 回放, 看之前不知道结果)。
func _live_card(g: Dictionary, idx: int) -> Control:
	var pc := PanelContainer.new()
	pc.name = N_LIVE_CARD + str(idx)
	pc.set_meta("match_id", str(g["id"]))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", MatchCard.card_style(Color(1.0, 0.80, 0.78)))
	pc.custom_minimum_size = Vector2(RIGHT_W - 12.0, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	var rt := _rel_time(int(g.get("t", 0)))
	vb.add_child(MatchCard.banner(Live.TAG_LIVE, (rt + "开打") if rt != "" else "",
		LIVE_RED, Color("#4a0f0b"), Color("#ffffff"), Color("#ffe1dc")))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(pad)
	body.add_child(_live_side(g["l"], false))
	body.add_child(MatchCard.vs_label(MatchCard.NAME_H + CARD_AVATAR - 4.0))
	body.add_child(_live_side(g["r"], true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(sp)
	var names := {"l": str(g["l"].get("name", "?")), "r": str(g["r"].get("name", "?"))}
	var bt := MatchCard.big_btn(Live.BTN_WATCH, N_LIVE_BTN, MatchCard.WATCH_SIZE, MatchCard.BTN_LIVE)
	bt.set_meta("key", str(g["id"]))
	bt.set_meta("label", Live.BTN_WATCH)
	bt.pressed.connect(_on_live_pressed.bind(str(g["id"]), names))
	body.add_child(bt)
	return pc


## 正在打的一方: 名字 + 三统领头像, 两边一样亮(不剧透)。
func _live_side(s: Dictionary, flip: bool) -> Control:
	var nm := str(s.get("name", "?")) + ("（我）" if _is_me(s) else "")
	return MatchCard.side(nm, s.get("lineup", []), flip, "", CARD_AVATAR, Color("#e8eef5"), false)


func _is_me(s: Dictionary) -> bool:
	return str(s.get("tag", "")) != "" and str(s.get("tag", "")) == BE.my_tag()


## 对局里的一方: 名字(胜者金色 / 负者压暗) + 三统领头像。没有阵容(老查询)⇒ 三个空槽, 版式不跳。
func _side_of(s: Dictionary, won: bool, flip: bool) -> Control:
	var nm := str(s.get("name", "?")) + ("（我）" if _is_me(s) else "")
	return MatchCard.side(nm, s.get("lineup", []), flip, "", CARD_AVATAR,
		MINE if won else Color("#8a98a8"), not won)


func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 状态签: 实心斜面块(与战绩页胜负小方块同一种做法)。
func _chip(t: String, spec: Array) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(76, 30)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", MatchCard.bevel(spec[0], spec[1], 6, 2))
	var l := _label(t, 15, spec[2])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip


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


## 点「观赛」⇒ 取那一行直播 → 版本 / 还在不在打 → 进战斗场按观赛方式跟播(`live_spectate.gd`)。
func _on_live_pressed(id: String, names: Dictionary) -> void:
	if _busy != "":
		return
	_busy = id
	_set_busy(id, true)
	Live.open_live(get_tree(), id, _on_replay_done, SELF_SCENE, names)


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


## 取的时候: 所有「观看」都点不了; 被点的那一颗写「读取中」。复原时全部放开。
func _set_busy(id: String, busy: bool) -> void:
	for b in find_children(N_WATCH, "Button", true, false) + find_children(N_LIVE_BTN, "Button", true, false):
		var bt := b as Button
		bt.disabled = busy
		if str(bt.get_meta("key", "")) == id:
			bt.text = WATCH_BUSY if busy else str(bt.get_meta("label", WATCH_LABEL))


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
