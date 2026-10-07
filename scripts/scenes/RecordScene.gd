extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
## 对局卡共享件(与周六赛况板 / 周日对阵图同一套, 2026-10-07 抽出)。
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
var _top_bar = null

## RecordScene — 战绩: 顶上一块总览(出战/胜/负/胜率 + 最近几场的胜负小方块) + 每场一张对局卡。
##
## ═══ 2026-10-07 第三版: 对局卡(用户「回放系统也是个问题呢」) ═══
## 新玩家实录(C:/tmp/newplayer/rp_sheet.jpg): 一大片绿底上只有一条小战报 + 一个很小的「回放」签牌,
##   看不出这一行能点、也看不出跟谁打的。参考(C:/tmp/rpref/big.jpg):
##   · 荒野乱斗 Battle Log —— 每场一张满宽卡, 顶上一条结果横幅, 下面两边阵容头像 + 中间 VS;
##     最上面一排最近 25 场的胜负小方块。
##   · 皇室战争 Battle Log —— 结果横幅「VICTORY」+ 双方 + 右下一颗大的「Watch」。
## ⇒ 照这两家的骨架: 横幅(胜利/失败 + 时长 + 多久之前) / 我方三头像 VS 对手三头像 + 双方名字 / 右边一颗「观看」。
## ★「观看」只在 `ReplayFetcher.has_replay` 为真的那一行出(不放死按钮, 沿用 S3 的规矩)。
## ★皮全用现成的: 卡 = `slot-frame.png` 九宫格(图鉴列表行同一张), 总览 = `panel-frame.png`,
##   按钮 = `UISkin.pixel_button()` 像素按钮(2026-10-07 从大木牌换掉); 横幅/小方块 = 实心色块 + 右下 2px 暗边(像素斜面, 不是网页盒)。
##
## 【对手这一维】写入侧 `GameState.record_match()` 从 2026-10-07 起多存 `foe`(对手三统领 id)
##   和 `foe_name`(对手快照里的名字, 与对局顶栏右边那个名字同一出处)。
##   老记录没有这两个键 ⇒ 右边画三个空槽、不写名字(版式不跳)。

## 回合制 PoC 留下的模式名(老存档里的旧记录才会命中; 实时版只写 "实时")。
const MODE_LABEL := {"single": "野生", "pve": "野生", "dungeon": "深海闯关", "custom": "切磋",
	"boss": "首领", "boss-pick": "指定首领", "test": "测试"}

const W := 1280.0
const PANEL_W := 960.0
const TOP_Y := 96.0

## ══ 对局卡的尺寸 ══
## 总览右边那排小方块(最近几场, 新的在左)。
const DOT_PX := 26.0
const DOT_MAX := 20

const COL_WIN := Color("#ffcf4d")
const COL_WIN_EDGE := Color("#8a5a10")
const COL_LOSS := Color("#a8343c")
const COL_LOSS_EDGE := Color("#4a1216")

## ══ 回放入口(跨设备回放 S3, docs/plans/20261003-跨设备回放.md) ══
const ReplayFetcher := preload("res://scripts/systems/replay/replay_fetcher.gd")
const Backend := preload("res://scripts/net/backend.gd")
const WATCH_LABEL := "观看"
const WATCH_BUSY := "读取中"
const LIST_TITLE := "最近对局"
## 节点名 —— 门禁按名字找。
const N_CARD := "RecordCard"       # + 下标
const N_WATCH := "ReplayBtn"
const N_FOE := "FoeName"
const N_DOTS := "RecentDots"
## 列表小标题 —— 取回放失败时那句话借它的位置说(就在列表正上方, 不挤动列表)。
var _list_title: Label = null
## 正在取的那一行(""= 没有)。取的时候所有「观看」都不能再点, 回调回来一定复原。
var _rp_busy := ""
## 最近一次「观看」的结果(门禁读: 原因码 / 那句话)。
var last_replay_code := ""
var last_replay_msg := ""
## 进这一屏时清掉的本机回放缓存 id(门禁读)。
var pruned_replays: Array = []


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _ready() -> void:
	## 本机回放缓存清理(删「不在战绩里 + 比上周一还旧 + 不在上传队列」的, 规则见 `ReplayFetcher.prune_cache`)。
	pruned_replays = ReplayFetcher.prune_cache(ReplayFetcher.P2C.now_utc())
	_bg()

	## 顶栏走全项目同一个原语 `TopBar`: 返回箭头 + 裸页名。
	_top_bar = TopBar.new(self, {
		"title": "战绩",
		"palette": TopBar.DEEP,
		"width": W,
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
	})

	var hist: Array = GameState.match_history
	var n: int = mini(20, hist.size())

	var root := VBoxContainer.new()
	root.position = Vector2((W - PANEL_W) / 2.0, TOP_Y)
	root.custom_minimum_size = Vector2(PANEL_W, 0)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_overview(hist, n))

	var lh := Label.new()
	lh.text = LIST_TITLE
	lh.add_theme_font_size_override("font_size", 14)
	lh.add_theme_color_override("font_color", Color("#58d3ff"))
	root.add_child(lh)
	_list_title = lh

	## 列表: 卡高 ≈ 146 + 间距 10 ⇒ 516 高露出三张多一点(下一张露头 = 告诉人还能往下滑)。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, 516)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if hist.is_empty():
		var eb := VBoxContainer.new()
		eb.custom_minimum_size = Vector2(PANEL_W, 110)
		eb.alignment = BoxContainer.ALIGNMENT_CENTER
		eb.add_theme_constant_override("separation", 8)
		list.add_child(eb)
		var e1 := Label.new()
		e1.text = "暂无战绩"
		e1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e1.add_theme_font_size_override("font_size", 17)
		e1.add_theme_color_override("font_color", Color("#c7b489"))
		eb.add_child(e1)
		var e2 := Label.new()
		e2.text = "暂无对局记录"
		e2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e2.add_theme_font_size_override("font_size", 12)
		e2.add_theme_color_override("font_color", Color("#77889a"))
		eb.add_child(e2)
	else:
		## ★时钟走 `Phase2Config.now_utc()`(全项目唯一一条可注入的时钟; 默认 = 系统时钟) ——
		##   回放按钮的可见期按周界判(周二 00:00 UTC 清上周的), 门禁要能把「现在」钉在周一 23:59 / 周二 00:00。
		var now: int = ReplayFetcher.P2C.now_utc()
		var me := str(Backend.player_display_name())
		for i in range(n):
			list.add_child(_match_card(hist[i], now, me, i))

	# ★UI 双端适配: 把内容装进 1280×720 设计框并居中于真实视口。必须放在 _ready 最后。
	UIFrame.attach(self)


# ─────────────────────────────── 总览 ───────────────────────────────

## 总览: 左边四个数(出战/胜/负/胜率), 右边最近几场的胜负小方块(荒野乱斗 Battle Log 顶上那一排)。
func _overview(hist: Array, n: int) -> Control:
	var total: int = GameState.battles_total
	var wins: int = GameState.battles_won
	var losses: int = maxi(0, total - wins)
	var rate: int = int(round(float(wins) / total * 100.0)) if total > 0 else 0
	var overview := PanelContainer.new()
	var ovsb := StyleBoxFlat.new()
	ovsb.bg_color = Color(20.0 / 255.0, 32.0 / 255.0, 40.0 / 255.0, 1.0)
	ovsb.set_corner_radius_all(0)
	ovsb.content_margin_left = 24; ovsb.content_margin_right = 24
	ovsb.content_margin_top = 14; ovsb.content_margin_bottom = 14
	## 金属大框(和背包/图鉴的面板同一张)。冷色底留在 modulate 里(战绩屏整体冷蓝调)。
	var ovtex := UISkin.nine("panel-frame.png", 20, ovsb)
	if ovtex is StyleBoxTexture:
		var t := ovtex as StyleBoxTexture
		t.modulate_color = Color(0.72, 0.92, 1.12, 1.0)
		t.content_margin_left = 24; t.content_margin_right = 24
		t.content_margin_top = 14; t.content_margin_bottom = 14
	overview.add_theme_stylebox_override("panel", ovtex)
	overview.custom_minimum_size = Vector2(PANEL_W, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	overview.add_child(row)
	row.add_child(_stat("出战", str(total), "#ffffff"))
	row.add_child(_stat("胜", str(wins), "#ffcf4d"))
	row.add_child(_stat("负", str(losses), "#ff8a8a"))
	row.add_child(_stat("胜率", "%d%%" % rate, "#58d3ff"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	## 小方块: 两行各 10 个, 新的在左上。没有记录就不画这一块。
	if n > 0:
		var grid := GridContainer.new()
		grid.name = N_DOTS
		grid.columns = 10
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(grid)
		for i in range(mini(DOT_MAX, n)):
			grid.add_child(_dot(str((hist[i] as Dictionary).get("result", "")) == "win"))
	return overview


func _stat(label: String, value: String, color: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(76, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 28)
	v.add_theme_color_override("font_color", Color(color))
	box.add_child(v)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
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
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("#3a2400") if won else Color("#ffd6d0"))
	pc.add_child(l)
	return pc


# ─────────────────────────────── 对局卡 ───────────────────────────────

## 一场 = 一张卡: [横幅 胜利/失败 · 时长 · 多久之前] / [我方三头像 VS 对手三头像 …… 观看]。
## ★胜负一眼分得出不只靠颜色: 横幅上写着「胜利」/「失败」两个字, 横幅底色金 / 暗红是附带的。
func _match_card(m: Dictionary, now: int, me: String, idx: int = 0) -> Control:
	var won: bool = str(m.get("result", "")) == "win"
	var pc := PanelContainer.new()
	pc.name = N_CARD + str(idx)        # 每张一个确定的名字(同名兄弟会被引擎改成 @…@ 名)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 卡框 = `MatchCard.card_style()`(slot-frame 九宫格, 三屏同一张)。
	pc.add_theme_stylebox_override("panel", MatchCard.card_style())
	pc.custom_minimum_size = Vector2(PANEL_W, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	vb.add_child(_banner(m, won))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(pad)
	body.add_child(MatchCard.side(me, m.get("lineup", []), false, ""))
	body.add_child(MatchCard.vs_label(MatchCard.NAME_H + MatchCard.AVATAR_PX - 6.0))
	body.add_child(MatchCard.side(str(m.get("foe_name", "")), m.get("foe", []), true, N_FOE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(sp)
	if ReplayFetcher.has_replay(m, now):
		body.add_child(_watch_btn(str(m.get("replay_id", ""))))
	return pc


## 结果横幅: 实心色条, 左「胜利」/「失败」, 右「时长 m:ss · 多久之前」。
func _banner(m: Dictionary, won: bool) -> Control:
	return MatchCard.banner("胜利" if won else "失败", _info_line(m),
		Color("#b98a22") if won else Color("#7a252c"), Color("#5e420c") if won else Color("#3a0f13"),
		Color("#fff1c4") if won else Color("#ffd6d0"), Color("#3a2400") if won else Color("#f0c2bc"))


## 横幅右边那一行: 「时长 0:28 · 3 分钟前」。老回合制记录写模式名 + 回合数。
func _info_line(m: Dictionary) -> String:
	var mode := str(m.get("mode", ""))
	var n := int(m.get("turn", 0))
	var parts: Array = []
	if mode == "实时" or mode == "":
		if n > 0:
			parts.append("时长 %d:%02d" % [n / 60, n % 60])
	else:
		parts.append("%s · %d 回合" % [str(MODE_LABEL.get(mode, mode)), n])
	var rel := _rel_time(int(m.get("ts", 0)))
	if rel != "":
		parts.append(rel)
	return "  ·  ".join(parts)


## 「观看」: 金色像素按钮(`MatchCard.big_btn` → `UISkin.pixel_button`), 只在有录像的卡上出。
func _watch_btn(id: String) -> Button:
	var bt := MatchCard.big_btn(WATCH_LABEL, N_WATCH)
	bt.set_meta("replay_id", id)
	bt.pressed.connect(_on_replay_pressed.bind(id))
	return bt


func _on_replay_pressed(id: String) -> void:
	if _rp_busy != "":
		return
	_rp_busy = id
	_set_replay_busy(id, true)
	if _list_title != null:
		_list_title.text = LIST_TITLE
		_list_title.add_theme_color_override("font_color", Color("#58d3ff"))
	ReplayFetcher.open(get_tree(), id, _on_replay_done)


## `ReplayFetcher.open` 的回调, 恰好一次。code == "" ⇒ 已经换到战斗场了。
func _on_replay_done(code: String, msg: String) -> void:
	last_replay_code = code
	last_replay_msg = msg
	var id := _rp_busy
	_rp_busy = ""
	if code == "":
		return
	_set_replay_busy(id, false)
	if _list_title != null:
		_list_title.text = msg
		_list_title.add_theme_color_override("font_color", Color("#ff9b7a"))


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


func _bg() -> void:
	# RecordScene 套主菜单 tile bg = menu-bg-tile.png 平铺 (512px repeat) over 深绿底 #1a3a2a, 上叠暗渐变.
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)   # #1a3a2a 深绿底
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 漂移 -512→0 / 25s linear 循环
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := tile.create_tween().set_loops()
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	# 暗渐变遮罩 (顶 alpha.15 → 底 .40)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.15),
		Color(0.031, 0.047, 0.078, 0.25),
		Color(0.031, 0.047, 0.078, 0.40),
	])
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
