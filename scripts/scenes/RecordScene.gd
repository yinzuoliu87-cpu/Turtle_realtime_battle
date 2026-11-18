extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
## 对局卡共享件(与周六赛况板 / 周日对阵图同一套, 2026-10-07 抽出)。
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const BLCard := preload("res://scripts/scenes/record/battle_log_card.gd")
const BLN := preload("res://scripts/net/battle_log_net.gd")
var _top_bar = null

## RecordScene — 战绩。
##
## ═══ 2026-11-18 第四版(方案书 docs/plans/20261118-对局记录重做.md) ═══
## 用户 11-18「对局记录现在就只有…积分赛…周日是不是没有啊？偷袭的是不是也没有啊？…时间双方的装备也没有…背景也不是很好」。
##   · 数据: 服务器 `my_battle_log`(积分赛 / 周六闯关赛 / 周日决赛 / 偷袭, 双方三统领 + 各自装备 + 时间 + 两路胜负)
##     + 本机老记录里服务器没有的那几行(按录像号去重; 没联网时只剩本机那几行)。
##   · 版式: 顶上一排赛事页签(全部 / 积分赛 / 闯关赛 / 决赛 / 偷袭) + 一行总览(场次 / 胜 / 负 / 胜率 + 最近胜负小方块);
##     下面每场一张卡(`BattleLogCard`: 云顶对局记录式「头像下一排装备」+ 皇室 Battle Log 式左右对照 + 观看)。
##   · 背景: 深色底占位(满屏底图都被别的页面用着, 不借; 专属底图 11-19 PixelLab 额度重置后出)。
## ★「观看」只在有录像的那一行出(不放死按钮): 服务器行看 `replay`(matches 里有), 决赛行走 `open_finals`, 本机行沿用 `ReplayFetcher.has_replay`。
## ★录像版本与本机不同(`ReplayRecorder.version_differs`)⇒ 本机行的「观看」换成灰签「版本不同」。

## 回合制 PoC 留下的模式名(老存档里的旧记录才会命中; 实时版只写 "实时")。
const MODE_LABEL := {"single": "野生", "pve": "野生", "dungeon": "深海闯关", "custom": "切磋",
	"boss": "首领", "boss-pick": "指定首领", "test": "测试"}

const W := 1280.0
const PANEL_W := BLCard.CARD_W
const TOP_Y := 92.0

## 总览右边那排小方块(最近几场, 新的在左)。
const DOT_PX := 22.0
const DOT_MAX := 20

const COL_WIN := Color("#ffcf4d")
const COL_WIN_EDGE := Color("#8a5a10")
const COL_LOSS := Color("#a8343c")
const COL_LOSS_EDGE := Color("#4a1216")

## ══ 回放入口(跨设备回放 S3, docs/plans/20261003-跨设备回放.md) ══
const ReplayFetcher := preload("res://scripts/systems/replay/replay_fetcher.gd")
const Backend := preload("res://scripts/net/backend.gd")
const _RW := preload("res://scripts/systems/replay/referee_watch.gd")
const WATCH_LABEL := "观看"
const WATCH_BUSY := "载入中"
const WATCH_SIZE := Vector2(140, 84)   # 短边 ≥ 81 = 44pt 触控线(verify_replay_watch ⑤)
const LIST_TITLE := "最近对局"
const MORE_LABEL := "加载更多"
const TXT_LOADING := "正在读取服务器上的对局…"
const TXT_OFFLINE := "连不上服务器，只显示这台设备上的对局"
const TXT_EMPTY := "暂无战绩"
const TXT_EMPTY_SUB := "参加积分赛、闯关赛、决赛或偷袭后，对局将显示在这里。"
## 赛事页签: [键, 字]。键 = 行的 kind(all = 全部)。
const TABS := [["all", "全部"], ["ranked", "积分赛"], ["gauntlet", "闯关赛"], ["finals", "决赛"], ["raid", "偷袭"]]
## 节点名 —— 门禁按名字找。
const N_CARD := "RecordCard"       # + 下标
const N_WATCH := "ReplayBtn"
const N_FOE := "FoeName"
const N_DOTS := "RecentDots"
const N_TAB := "Tab_"              # + 键
const N_MORE := "MoreBtn"
## 列表小标题 —— 取回放失败 / 服务器状态那句话借它的位置说(就在列表正上方, 不挤动列表)。
var _list_title: Label = null
## 正在取的那一行(""= 没有)。取的时候所有「观看」都不能再点, 回调回来一定复原。
var _rp_busy := ""
## 最近一次「观看」的结果(门禁读: 原因码 / 那句话)。
var last_replay_code := ""
var last_replay_msg := ""
## 进这一屏时清掉的本机回放缓存 id(门禁读)。
var pruned_replays: Array = []
## 数据: 服务器行(按 id 倒序) / 本机行 / 当前页签 / 服务器状态(loading / ok / off / net)/ 还能不能往下翻。
var server_rows: Array = []
var local_rows: Array = []
var tab := "all"
var server_state := "loading"
var _more := false
var _list: VBoxContainer = null
var _overview_box: Control = null
var _tabs_row: HBoxContainer = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn")

func _ready() -> void:
	## 本机回放缓存清理(删「不在战绩里 + 比上周一还旧 + 不在上传队列」的, 规则见 `ReplayFetcher.prune_cache`)。
	pruned_replays = ReplayFetcher.prune_cache(ReplayFetcher.P2C.now_utc())
	_bg()

	## 顶栏走全项目同一个原语 `TopBar`: 返回箭头 + 裸页名。
	_top_bar = TopBar.new(self, {
		"title": "战绩",
		"palette": TopBar.DEEP,
		"width": W,
		"on_back": func(): SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn"),
	})

	var me := str(Backend.player_display_name())
	var hist: Array = GameState.match_history
	for i in range(mini(20, hist.size())):
		if hist[i] is Dictionary:
			var r := BLN.from_local(ReplayFetcher.card_row(hist[i]), me)
			local_rows.append(r)

	var root := VBoxContainer.new()
	root.position = Vector2((W - PANEL_W) / 2.0, TOP_Y)
	root.custom_minimum_size = Vector2(PANEL_W, 0)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 8)
	root.add_child(_tabs_row)
	_overview_box = VBoxContainer.new()
	root.add_child(_overview_box)

	var lh := Label.new()
	lh.add_theme_font_size_override("font_size", 14)
	root.add_child(lh)
	_list_title = lh

	## 列表: 卡高 ≈ 150 + 间距 10 ⇒ 露出三张多一点(下一张露头 = 告诉人还能往下滑)。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	server_state = "loading"
	_render()
	BLN.fetch(0, _on_fetched)

	# ★UI 双端适配: 把内容装进 1280×720 设计框并居中于真实视口。必须放在 _ready 最后。
	UIFrame.attach(self)


# ─────────────────────────────── 数据 ───────────────────────────────

func _on_fetched(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		server_state = "off" if str(res.get("reason", "")) == "off" else "net"
		_render()
		return
	var got: Array = res.get("rows", [])
	server_rows.append_array(got)
	_more = got.size() >= BLN.PAGE
	server_state = "ok"
	_render()


func _on_more() -> void:
	if server_rows.is_empty() or server_state == "loading":
		return
	server_state = "loading"
	_render()
	BLN.fetch(int((server_rows[-1] as Dictionary).get("id", 0)), _on_fetched)


## 要画的行: 服务器行 + 本机行里服务器没有的(按录像号去重), 按时间倒序; 再按页签过滤。
func rows_shown() -> Array:
	var seen := {}
	for r in server_rows:
		var mid := str((r as Dictionary).get("match_id", ""))
		if mid != "":
			seen[mid] = true
	var loc: Array = []
	for r in local_rows:
		var mid2 := str((r as Dictionary).get("match_id", ""))
		if mid2 == "" or not seen.has(mid2):
			loc.append(r)
	## ★两边各自已是新的在前(服务器按 id 倒序 / 本机按记录顺序)⇒ 归并, 不整体重排: sort_custom 不保序,
	##   本机那几行的先后会乱(门禁按本机记录的顺序找第几张卡, 11-18 就这样对错了卡)。时间相同 / 本机没时间 ⇒ 服务器的在前。
	var all: Array = []
	var i := 0
	var j := 0
	while i < server_rows.size() or j < loc.size():
		if j >= loc.size() or (i < server_rows.size()
				and int((server_rows[i] as Dictionary).get("at", 0)) >= int((loc[j] as Dictionary).get("at", 0))):
			all.append(server_rows[i])
			i += 1
		else:
			all.append(loc[j])
			j += 1
	if tab == "all":
		return all
	return all.filter(func(r) -> bool: return str((r as Dictionary).get("kind", "")) == tab)


# ─────────────────────────────── 画 ───────────────────────────────

func _render() -> void:
	var rows := rows_shown()
	_render_tabs()
	## ★先 remove_child 再 queue_free: 光 queue_free 的话旧节点这一帧还占着名字, 新建的同名节点(RecentDots / Tab_*)
	##   会被引擎改成 @…@ 名, 门禁按名字就找不到了(2026-11-18 实拍时页签就这样丢的)。
	_drop_children(_overview_box)
	_overview_box.add_child(_overview(rows))
	match server_state:
		"loading":
			_say(TXT_LOADING, Color("#9fb2c4"))
		"ok":
			_say(LIST_TITLE, Color("#58d3ff"))
		_:
			_say(TXT_OFFLINE, Color("#ff9b7a"))
	_drop_children(_list)
	if rows.is_empty():
		_list.add_child(_empty())
		return
	var now: int = ReplayFetcher.P2C.now_utc()
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		_list.add_child(BLCard.make(r, now, i, N_CARD, _watch_for(r, now), N_FOE))
	if _more and server_state == "ok":
		var mb := MatchCard.big_btn(MORE_LABEL, N_MORE, Vector2(200, 52), UISkin.PX_SLATE, 18)
		mb.mouse_filter = Control.MOUSE_FILTER_PASS
		mb.pressed.connect(_on_more)
		var cc := CenterContainer.new()
		cc.add_child(mb)
		_list.add_child(cc)


func _drop_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _say(text: String, col: Color) -> void:
	if _list_title != null:
		_list_title.text = text
		_list_title.add_theme_color_override("font_color", col)


## 页签: 每个带场数(按已读到的行数)。当前那个金色, 其余深色。
func _render_tabs() -> void:
	_drop_children(_tabs_row)
	var keep := tab
	tab = "all"
	var all := rows_shown()
	tab = keep
	for t in TABS:
		var key := str(t[0])
		var n := all.size() if key == "all" else all.filter(func(r) -> bool: return str((r as Dictionary).get("kind", "")) == key).size()
		var bt := MatchCard.big_btn("%s %d" % [str(t[1]), n], N_TAB + key, Vector2(132, 44),
			UISkin.PX_GOLD if key == tab else UISkin.PX_SLATE, 17)
		bt.pressed.connect(func() -> void:
			tab = key
			_render())
		_tabs_row.add_child(bt)


## 空态: 两行字(说什么时候会有)。
func _empty() -> Control:
	var eb := VBoxContainer.new()
	eb.custom_minimum_size = Vector2(PANEL_W, 110)
	eb.alignment = BoxContainer.ALIGNMENT_CENTER
	eb.add_theme_constant_override("separation", 8)
	var e1 := Label.new()
	e1.text = TXT_EMPTY
	e1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e1.add_theme_font_size_override("font_size", 17)
	e1.add_theme_color_override("font_color", Color("#c7b489"))
	eb.add_child(e1)
	var e2 := Label.new()
	e2.text = TXT_EMPTY_SUB
	e2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e2.add_theme_font_size_override("font_size", 12)
	e2.add_theme_color_override("font_color", Color("#77889a"))
	eb.add_child(e2)
	return eb


# ─────────────────────────────── 总览 ───────────────────────────────

## 总览: 左边四个数(场次 / 胜 / 负 / 胜率, 按当前页签), 右边最近几场的胜负小方块。
func _overview(rows: Array) -> Control:
	var total: int = rows.size()
	var wins: int = rows.filter(func(r) -> bool: return bool((r as Dictionary).get("won", false))).size()
	var losses: int = maxi(0, total - wins)
	var rate: int = int(round(float(wins) / total * 100.0)) if total > 0 else 0
	var overview := PanelContainer.new()
	var ovsb := StyleBoxFlat.new()
	ovsb.bg_color = Color("#0e1824e6")
	ovsb.border_color = Color("#2c3a4c")
	ovsb.set_border_width_all(2)
	ovsb.set_corner_radius_all(0)
	ovsb.content_margin_left = 20; ovsb.content_margin_right = 20
	ovsb.content_margin_top = 6; ovsb.content_margin_bottom = 6
	overview.add_theme_stylebox_override("panel", ovsb)
	overview.custom_minimum_size = Vector2(PANEL_W, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	overview.add_child(row)
	row.add_child(_stat("场次", str(total), "#ffffff"))
	row.add_child(_stat("胜", str(wins), "#ffcf4d"))
	row.add_child(_stat("负", str(losses), "#ff8a8a"))
	row.add_child(_stat("胜率", "%d%%" % rate, "#58d3ff"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	## 小方块: 两行各 10 个, 新的在左上。没有记录就不画这一块。
	if total > 0:
		var grid := GridContainer.new()
		grid.name = N_DOTS
		grid.columns = 10
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(grid)
		for i in range(mini(DOT_MAX, total)):
			grid.add_child(_dot(bool((rows[i] as Dictionary).get("won", false))))
	return overview


func _stat(label: String, value: String, color: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(70, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 24)
	v.add_theme_color_override("font_color", Color(color))
	box.add_child(v)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#99aabb"))
	box.add_child(l)
	return box


## 一个胜负小方块: 实心色块 + 右下 2px 暗边(像素斜面), 块上一个字。
func _dot(won: bool) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", MatchCard.bevel(COL_WIN if won else COL_LOSS, COL_WIN_EDGE if won else COL_LOSS_EDGE, 0, 0))
	pc.custom_minimum_size = Vector2(DOT_PX, DOT_PX)
	var l := Label.new()
	l.text = "胜" if won else "负"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#3a2400") if won else Color("#ffd6d0"))
	pc.add_child(l)
	return pc


# ─────────────────────────────── 观看 ───────────────────────────────

## 这一行的「观看」(null = 不出): 服务器行有录像 / 决赛行 / 本机行有录像。录像号 = match_id。
func _watch_for(r: Dictionary, now: int) -> Control:
	var kind := str(r.get("kind", ""))
	var id := str(r.get("match_id", ""))
	if kind == "local":
		var m: Dictionary = r.get("local", {})
		if not ReplayFetcher.has_replay(m, now):
			return null
		if ReplayRecorder.version_differs(str(m.get("client_version", ""))):
			return MatchCard.off_tag(MatchCard.VER_DIFF, WATCH_SIZE)
		return _watch_btn(id)
	if kind == "finals" and not (r.get("finals", {}) as Dictionary).is_empty():
		return _watch_btn(id)
	if bool(r.get("replay", false)) and id != "":
		return _watch_btn(id)
	return null


## 「观看」: 金色像素按钮, 只在有录像的卡上出。
func _watch_btn(id: String) -> Button:
	var bt := MatchCard.big_btn(WATCH_LABEL, N_WATCH, WATCH_SIZE, MatchCard.BTN_WATCH, 20)
	bt.set_meta("replay_id", id)
	## 按在「观看」上起手也要能滑列表(2026-10-31 verify_scroll_touch_sweep 实测: STOP 时那里起手 Δ=0, 每张卡右边一大块)。
	##   滑过的那一下不算点: 滚动框一开始拖就广播 SCROLL_BEGIN, 引擎自己把按下作废(门禁「快甩」验过)。
	bt.mouse_filter = Control.MOUSE_FILTER_PASS
	bt.pressed.connect(_on_replay_pressed.bind(id))
	return bt


func _on_replay_pressed(id: String) -> void:
	if _rp_busy != "":
		return
	_rp_busy = id
	_set_replay_busy(id, true)
	_say(LIST_TITLE, Color("#58d3ff"))
	var row := _row_of(id)
	var foe := str((row.get("foe", {}) as Dictionary).get("name", ""))
	## 周日决赛: 按 (周, 组, 轮, 场) 取裁判采纳的那一份。
	if str(row.get("kind", "")) == "finals":
		var f: Dictionary = row.get("finals", {})
		ReplayFetcher.open_finals(get_tree(), int(row.get("week", 0)), int(f.get("bucket", 0)), int(f.get("round", 0)),
			int(f.get("match", 0)), _on_replay_done, "", {}, true)
		return
	## 我在右边(B)的那一局(周六在线配对 / 被偷袭的防守方): 录像左方是对手 ⇒ 名字左右照实写、「我方」指右边(RefereeWatch.watch_names 同一份)。
	if bool(row.get("b_side", false)):
		ReplayFetcher.open(get_tree(), id, _on_replay_done, "",
			_RW.watch_names({"side": "b", "foe_name": foe}))
		return
	ReplayFetcher.open(get_tree(), id, _on_replay_done)


## 录像号是 `id` 的那一行(没有 ⇒ {})。服务器行优先。
func _row_of(id: String) -> Dictionary:
	for r in server_rows + local_rows:
		if r is Dictionary and str((r as Dictionary).get("match_id", "")) == id:
			return r
	return {}


## `ReplayFetcher.open` 的回调, 恰好一次。code == "" ⇒ 已经换到战斗场了。
func _on_replay_done(code: String, msg: String) -> void:
	last_replay_code = code
	last_replay_msg = msg
	var id := _rp_busy
	_rp_busy = ""
	if code == "":
		return
	_set_replay_busy(id, false)
	_say(msg, Color("#ff9b7a"))


## 取的时候: 所有「观看」都点不了; 被点的那一颗写「读取中」。复原时全部放开。
func _set_replay_busy(id: String, busy: bool) -> void:
	for b in find_children(N_WATCH, "Button", true, false):
		var bt := b as Button
		bt.disabled = busy
		if str(bt.get_meta("replay_id", "")) == id:
			bt.text = WATCH_BUSY if busy else WATCH_LABEL


## 战绩条目的「多久之前」。
##
## ★写入侧存的是【秒】(`int(Time.get_unix_time_from_system())`), 这里按秒减(2026-09-17 修过一次毫秒错配)。
## ⚠ 设备时钟往回调会让 d 为负 ⇒ 落到「刚刚」(有意的兜底)。
## ⚠ 门禁 `tests/verify_record_reltime.gd` 逐字断言了
##   「刚刚」/「1 分钟前」/「5 分钟前」/「2 小时前」/「3 天前」/空串 六个串。
func _rel_time(ts: int) -> String:
	if ts <= 0:
		return ""
	var d := int(Time.get_unix_time_from_system()) - ts
	if d < 60:
		return "刚刚"
	if d < 3600:
		return "%d 分钟前" % int(d / 60.0)
	if d < 86400:
		return "%d 小时前" % int(d / 3600.0)
	if d < 172800:
		return "昨天"
	if d < 259200:
		return "前天"
	return "%d 天前" % int(d / 86400.0)


# ─────────────────────────────── 背景 ───────────────────────────────

## 深色底 + 上下暗角(占位: 专属底图 11-19 出)。
func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color("#0b1622")
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color("#16304a"), Color("#0e1e30"), Color("#070d15")])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
