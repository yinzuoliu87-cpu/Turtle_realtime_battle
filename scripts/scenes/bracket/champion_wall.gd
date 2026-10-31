class_name ChampionWall
extends CanvasLayer
## champion_wall.gd —— 冠军墙(G12 · 名人堂): 历届冠军杯冠军, 一届一块铭牌(第几届 · 日期 · 冠军 · 来历 · 夺冠阵容 · 决赛录像)。
## 依据 学到的.md 4-5(赛事入口常驻「历周冠军名单」)、6-7(冠军墙 = 名人堂)、J-8(往届对阵图永久保留)、1-8 / 8-9(名次进永久展示位)。
## ★数据全部用现成的读接口, 服务端一个字不改:
##   · 每一届 = `finals_week_view(那一周)` 的 `cup`(`SupabaseNet.fetch_finals_week_cb`, 排行榜「上周终榜」也走它)
##   · 决赛录像 = `ReplayFetcher.open_finals(周, 杯组号, 决赛轮, 0)`(对阵图点格子同一条路)
##   · 夺冠阵容 = `matches` 行(ChampionData.finals_rows_query); **这条现在没有现成的取数函数** ⇒ 拿不到时铭牌只画冠军头像,
##     不画阵容那一格(见报告「需要补的」)。
##
## 用法:
##   var w := ChampionWall.open(host, {"entries": [...]})        # 已有数据
##   var w := ChampionWall.open(host, {"loading": true}); w.load_weeks(本周周锚点, 8)   # 自己去取近 8 届
##   w.replay_requested.connect(func(rp): ...)   # 不接就自己调 ReplayFetcher.open_finals 去播
##   w.finished.connect(...)                     # 点「返回」(层已自删)

signal replay_requested(rp: Dictionary)
signal finished

const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")
const SB := preload("res://scripts/net/supabase.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")

const LAYER := 98
const ROW_H := 132.0

var data: Dictionary = {}
var entries: Array = []
var vp := Vector2(1280, 720)
var c := Vector2(640, 360)
var _root: Control
var _list: VBoxContainer
var _scroll: ScrollContainer
var _state: Label
var _msg: Label
var _pending := 0
var _got: Dictionary = {}       # week → entry
var t := 0.0


static func create(d: Dictionary) -> ChampionWall:
	var s := ChampionWall.new()
	s.data = d
	return s


static func open(host: Node, d: Dictionary) -> ChampionWall:
	var s := create(d)
	host.add_child(s)
	return s


func node(nm: String) -> Node:
	return _root.find_child(nm, true, false) if _root != null else null


func _ready() -> void:
	layer = LAYER
	vp = data["vp"] if data.get("vp", null) is Vector2 else get_viewport().get_visible_rect().size   # 门禁量两种比例时直接给
	c = vp * 0.5
	_root = Control.new()
	_root.name = "WallRoot"
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := UI.tex_rect(UI.TEX_BG, vp, "ArenaBg")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.position = Vector2.ZERO
	bg.modulate = Color(0.55, 0.5, 0.55, 1.0)
	_root.add_child(bg)
	UI.box(_root, Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.03, 0.55), "Dim")
	UI.ribbon(_root, Vector2(c.x, 62), 320, "冠军墙", 48, "gold", "WallTitle")
	UI.label_in(_root, Rect2(0, 106, vp.x, 30), "历届冠军杯冠军", 22, UI.TXT, false, "WallSub")
	var back := UI.button("返回", 170, "BtnBack", false)
	back.position = Vector2(28, 22)
	back.pressed.connect(close)
	_root.add_child(back)
	var lw := minf(vp.x - 120.0, 1120.0)
	_scroll = ScrollContainer.new()
	_scroll.name = "WallScroll"
	_scroll.position = Vector2(c.x - lw * 0.5, 146)
	_scroll.size = Vector2(lw, vp.y - 146 - 24)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "WallList"
	_list.custom_minimum_size = Vector2(lw - 16, 0)
	_list.add_theme_constant_override("separation", 14)
	_scroll.add_child(_list)
	_state = UI.label_in(_root, Rect2(0, c.y - 20, vp.x, 40), "", 26, UI.TXT_DIM, false, "WallState")
	_msg = UI.label_in(_root, Rect2(0, vp.y - 56, vp.x, 34), "", 22, Color("#ffb3a8"), false, "WallMsg")
	var e = data.get("entries", [])
	set_entries(e if e is Array else [])
	if bool(data.get("loading", false)):
		_state.text = "正在读取往届冠军…"


func _process(dt: float) -> void:
	t += dt
	## 本届那一块的奖杯轻轻浮动(墙不是一张死图)
	var tr := _root.find_child("WallTrophy0", true, false) as Control
	if tr != null:
		tr.position.y = roundf(4.0 + sin(t * 2.2) * 3.0)


func set_entries(arr: Array) -> void:
	entries = []
	for e in arr:
		if e is Dictionary and str((e as Dictionary).get("name", "")) != "":
			entries.append(e)
	entries.sort_custom(func(a, b): return int(a.get("week", 0)) > int(b.get("week", 0)))
	for ch in _list.get_children():
		_list.remove_child(ch)             # ★先摘下再释放(同名行进来时旧的还在会被引擎改名)
		ch.queue_free()
	for i in range(entries.size()):
		_list.add_child(_row(entries[i], i))
	_state.text = "" if not entries.is_empty() else "还没有往届冠军杯冠军"


func _row(e: Dictionary, i: int) -> Control:
	var w: float = _list.custom_minimum_size.x
	var row := Control.new()
	row.name = "WallRow%d" % i
	row.custom_minimum_size = Vector2(w, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var latest := i == 0
	var body := UI.plate(row, Rect2(4, 4, w - 8, ROW_H - 8), UI.GOLD if latest else UI.BRONZE, UI.PLATE)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bh := ROW_H - 8
	## 届数 + 日期
	var ed := int(e.get("edition", 0))
	UI.label_in(body, Rect2(14, 18, 140, 40), ("第 %d 届" % ed) if ed > 0 else "冠军杯", 24, UI.GOLD, true, "WallEdition%d" % i)
	UI.label_in(body, Rect2(14, 62, 140, 30), str(e.get("date", "")), 20, UI.TXT_DIM, false, "WallDate%d" % i)
	## 奖杯 + 冠军头像 + 名字 / 来历 / 亚军
	var trh := Control.new()
	trh.name = "WallTrophy%d" % i
	trh.size = Vector2(96, 96)
	trh.position = Vector2(150, 4)
	trh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(trh)
	UI.tex_at(trh, UI.TEX_TROPHY, Vector2(48, 48), Vector2(96, 96))
	UI.portrait(body, Vector2(296, bh * 0.5), 88, str(e.get("avatar", "")), UI.GOLD if latest else UI.BRONZE_HI, "WallFace%d" % i)
	var nx := 356.0
	UI.label_in(body, Rect2(nx, 14, 330, 46), str(e.get("name", "")), 36, UI.GOLD, true, "WallName%d" % i, HORIZONTAL_ALIGNMENT_LEFT)
	var parts: Array = []
	if str(e.get("origin", "")) != "":
		parts.append(str(e["origin"]))
	if int(e.get("entrants", 0)) > 0:
		parts.append("%d 人冠军" % int(e["entrants"]))
	UI.label_in(body, Rect2(nx, 62, 330, 28), " · ".join(parts), 20, UI.TXT, false, "WallInfo%d" % i, HORIZONTAL_ALIGNMENT_LEFT)
	if str(e.get("runner_up", "")) != "":
		UI.label_in(body, Rect2(nx, 90, 330, 26), "亚军 " + str(e["runner_up"]), 18, UI.TXT_DIM, false, "WallRunner%d" % i,
			HORIZONTAL_ALIGNMENT_LEFT)
	## 夺冠阵容(拿到了才画)
	var lu: Array = e.get("lineup", []) if e.get("lineup", []) is Array else []
	for k in range(mini(3, lu.size())):
		var id := str(lu[k])
		UI.portrait(body, Vector2(nx + 320 + k * 66, bh * 0.5), 60, id, UI.RARITY.get(UI.pet_rarity(id), UI.BRONZE), "WallTurtle%d_%d" % [i, k])
	## 决赛录像
	var rp: Dictionary = e.get("replay", {}) if e.get("replay", {}) is Dictionary else {}
	var b := UI.button("决赛录像", 200, "WallReplay%d" % i, latest)
	b.position = Vector2(w - 8 - 200 - 18, (bh - UI.BTN_H) * 0.5)
	b.disabled = rp.is_empty()
	b.pressed.connect(_on_replay.bind(rp))
	body.add_child(b)
	if latest:
		var tag := UI.label_in(body, Rect2(158, 98, 80, 24), "最新", 18, UI.GOLD, false, "WallLatest")
		tag.add_theme_constant_override("outline_size", 4)
	return row


func _on_replay(rp: Dictionary) -> void:
	if rp.is_empty():
		return
	if not replay_requested.get_connections().is_empty():
		replay_requested.emit(rp)
		return
	_msg.text = "读取中…"
	RF.open_finals(get_tree(), int(rp["week"]), int(rp["bucket"]), int(rp["round"]), int(rp["match"]),
		func(code: String, msg: String) -> void:
			if is_instance_valid(_msg):
				_msg.text = msg if code != "" else "")


## 自己去取最近 n 届(本周起往回数, 每周一次 finals_week_view)。取到一届画一届; 都没取到 = 空墙那句话。
func load_weeks(cur_week: int, n: int = 8) -> void:
	_got = {}
	_pending = 0
	_state.text = "正在读取往届冠军…"
	for k in range(n):
		var wk := cur_week - k * DATA.WEEK_SEC
		if wk < DATA.CUP_FIRST_WEEK:
			break
		if SB.fetch_finals_week_cb(wk, _on_week.bind(wk)):
			_pending += 1
	if _pending == 0:
		set_entries([])


func _on_week(res: Dictionary, wk: int) -> void:
	_pending -= 1
	if not is_instance_valid(_list):
		return
	var e := DATA.wall_entry(wk, res)
	if not e.is_empty():
		_got[wk] = e
	if _pending <= 0 or not e.is_empty():
		set_entries(_got.values())
		if _pending > 0:
			_state.text = ""


func close() -> void:
	finished.emit()
	queue_free()
