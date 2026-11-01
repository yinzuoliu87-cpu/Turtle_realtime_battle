extends RefCounted
## finals_watch_hud.gd — 周日开播观战页那几样(方案书 docs/plans/20261031c-周日赛事界面重做.md §4 C ⑤⑥⑦ · G17 G19 G20 G24)。
##
## 对局本身的顶栏(两端头像 + 名字 + 血条 + 中间 VS + 路名计时牌 +「开播」小签)不动; 这一层只补商业观战页有、我们没有的:
##   · 左上阶段标签: 红底「开播中」(点一明一暗)+「冠军杯赛 · 半决赛 · 第 1 / 2 场」(3-9、1-6)
##   · 比分: 贴在顶栏 VS 下面那一排三路点两侧 ⇒「1 ●●○ 0」(三路点本身就是三路灯: 一路一盏, 按赢家着色, 不另画一套); 来历跟在顶栏两端名字后面(G19 G24)
##   · 路名计时牌下面的拔河条: 双方此刻剩余总血量(播到哪算到哪, 单位表就是屏上这一路; 不预告, 不挂胜率 —— 结果预先算好, G19)
##   · 底部「下一场 X 对 Y · 20:14」条(G3 W-2)
##   · 右下助威键(法术圆盘左边): 展开四个固定表情, 点一个飘起来(不打字, 不绑奖励; G20 10-8)
##   · 路间幕布上压一块「上路战场 · 战果 / X 拿下这一路 / 1 : 0」(G24 9-4): 幕布原文写「本战场胜利 / 我方 : 对方」, 那是选手视角
##   · 迟到进来(G17): 默认实时; 左上多一颗「从头看」, 看着看着可以「回到直播」(状态流才有 —— 重算那条路只能往前算)
## 不挂: 观看人数(周日约 24 人, 个位数反而冷清, U8)、本场还剩、胜率(剧透)。
## ★放这里的理由(CLAUDE.md §5): 不在 `_sim_step` 调用链上; replay_controls 只留接线。只读对局状态, 一个字段都不写(「从头看」改的是播放器的播放头)。

const Ctx := preload("res://scripts/scenes/battle/finals_ctx.gd")
const SW_PATH := "res://scripts/systems/replay/stream_watch.gd"

const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const COL_GOLD := Color("#ffd93d")
const COL_GOLD_DIM := Color("#c9a24a")
const COL_LIVE := Color("#e04848")
## 灯色 = 顶栏那一边血条的颜色(battle_hud PK_BLUE / PK_RED: 左绿右紫)
const SIDE_COL := {"left": Color("#4ade80"), "right": Color("#a855f7")}
const TOP_Y := 88.0                 # 顶栏(名字行 + 主条 + 百分比斜牌)之下
const LAMP := 22.0
const LAMP_BIG := 34.0              # 路间插卡上的三路灯
const BREAK_H := 360.0              # 路间插卡那条亮带的高
const NARROW_W := 1280.0            # 比它窄 ⇒ 阶段标签挪到第二行
const TUG_W := 236.0
const CHEERS := ["cheer", "clap", "fire", "wow"]
const CHEER_DIR := "res://assets/sprites/finals/cheer-%s.png"
const CHEER_KEY := 88.0             # 助威键(看起来 88; 键底座与回放条同一套)
const KEY_UP := ReplayControls.KEY_NEUTRAL          # 回放条那颗中性键(同一个部件, 路径只在 replay_controls 写一份)
const KEY_DOWN := ReplayControls.KEY_NEUTRAL_DOWN
const CHEER_CD := 0.8               # 同一个人连点的间隔(秒)
const CHEER_RISE := 1.4             # 飘起来多久
## 迟到多少步算「开播后才进来」(10 秒 = 开场幕布那一段)
const LATE_STEPS := 600

const TXT_LIVE := "开播中"
const TXT_FROM_START := "从头看"
const TXT_BACK_LIVE := "回到直播"
const TXT_LANE_RESULT := "%s战果"
const TXT_LANE_TAKE := "%s 赢得%s"
const TXT_LANE_NEXT := "接下来：%s"
## 路名全称(用户 10-07「我们叫上路战场，下路战场，终极战场」)
const LANE_NAMES := {"top": "上路战场", "bottom": "下路战场", "final": "终极战场"}

## 节点名(门禁按名字找)
const N_ROOT := "FinalsWatch"
const N_TAG := "WatchStageTag"
const N_LIVE := "WatchLive"
const N_SCORE := "WatchScore_"      # + left / right
const N_ORIGIN := "WatchOrigin_"
const N_TUG := "WatchTug"           # meta frac
const N_NEXT := "WatchNext"
const N_CHEER := "WatchCheer_"      # + cheer / clap / fire / wow
const N_CHEER_KEY := "WatchCheerKey"  # 右下那一颗(按下展开四个表情)
const N_CHEERS := "WatchCheers"     # 展开的那一排
const N_CHEER_FX := "WatchCheerFx"
const N_BREAK := "WatchLaneBreak"
const N_FROM_START := "WatchFromStart"
const N_BAR_DOCK := "WatchBarDock"     # 全局决赛日小条的停靠位
const N_BREAK_DOCK := "WatchBreakDock" # 路间插卡期间小条的停靠位(跟着插卡显隐)

var battle
var ctl                             # replay_controls(取左右名字)
var root: Control = null
var st: Dictionary = {}
var _n: Dictionary = {}
var _tug_shown := 0.5
var _fx: Array = []                 # [节点, 出生时刻, 起点]
var _clock := 0.0
var _last_cheer := -99.0
var cheers_sent := 0                # 门禁分母
var late := false
var from_start := false
var _vp := Vector2.ZERO
var _anchors: Dictionary = {}       # 顶栏节点(三路点 / 路名牌 / 两端名字), 第一次找到就记住
var _ticker = null                  # 每帧钟(Ctx.start_ticker); 不标类型: 根释放后这里是失效实例


func _init(b, c) -> void:
	battle = b
	ctl = c


## 这一场要不要这一层: 入口给了决赛日轮次(对阵图点开的周日那一场)。
static func wanted(pn: Dictionary) -> bool:
	return Ctx.is_finals(pn)


func build(parent: Control, vp: Vector2, m: Vector4, names: Dictionary) -> Control:
	var pn: Dictionary = ReplayRecorder.play_names
	st = Ctx.stage_of(pn)
	root = Control.new()
	root.name = N_ROOT
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = vp
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(root)
	parent.move_child(root, 0)                       # 压在退出键 / 状态牌 / 收尾之下
	var cx: float = roundf(vp.x * 0.5)
	_vp = vp
	## 左上阶段标签: 红底「● 开播中」(点一明一暗)+ 轮次
	var tag := HBoxContainer.new()
	tag.name = N_TAG
	tag.add_theme_constant_override("separation", 10)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 窄屏(iPad 960)左上那一行会伸到顶栏中间的路名牌底下 ⇒ 挪到拔河条下面一行
	var tag_y: float = TOP_Y + 4.0 if vp.x >= NARROW_W else TOP_Y + 74.0
	tag.position = Vector2(m.x, tag_y)
	root.add_child(tag)
	var live := PanelContainer.new()
	live.name = N_LIVE
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color("#8a1c22")
	lsb.border_color = Color("#2a0608")
	lsb.set_border_width_all(2)
	lsb.set_corner_radius_all(0)
	lsb.content_margin_left = 10
	lsb.content_margin_right = 10
	lsb.content_margin_top = 1
	lsb.content_margin_bottom = 1
	live.add_theme_stylebox_override("panel", lsb)
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lhb := HBoxContainer.new()
	lhb.add_theme_constant_override("separation", 8)
	lhb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.add_child(lhb)
	var dot := ColorRect.new()
	dot.name = "LiveDot"
	dot.color = Color("#ffe9e9")
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lhb.add_child(dot)
	_n["live_dot"] = dot
	var ll := Ctx.title_lbl(TXT_LIVE, 24, Color("#ffe9e9"))
	lhb.add_child(ll)
	tag.add_child(live)
	_n["live"] = live
	var tt := Ctx.stage_tag(st)
	if tt != "":
		var tl := Label.new()
		tl.text = tt
		tl.add_theme_font_size_override("font_size", 26)
		tl.add_theme_color_override("font_color", Color("#ffe7a0"))
		Ctx.outline(tl, 8)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(tl)
		_n["tag_text"] = tl
	## 比分: 贴在顶栏 VS 下面那一排三路点(topbar_status LaneDots: 一路一盏, 灯色 = 赢下那一路的那一边)的两侧 ⇒ 「1 ●●○ 0」
	##   三路灯本身就是对局顶栏那一排, 这里不另画一套(同一件事两处画就会对不上)。
	for side in ["left", "right"]:
		var dg := Ctx.title_lbl("0", 24, COL_TEXT)
		dg.name = N_SCORE + side
		dg.size = Vector2(28, 30)
		root.add_child(dg)
		_n["dg_" + side] = dg
	## 来历: 跟在顶栏两端名字后面(「吃货一枚  B 组冠军」)
	var cards := Ctx.side_cards(pn, {"l": str(names.get("l", "")), "r": str(names.get("r", ""))})
	for side in ["left", "right"]:
		var org := Ctx.origin_of(cards[side], st)
		if org == "":
			continue
		var ol := Label.new()
		ol.name = N_ORIGIN + side
		ol.text = org
		ol.add_theme_font_size_override("font_size", 22)
		ol.add_theme_color_override("font_color", COL_GOLD)
		Ctx.outline(ol, 6)
		ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == "right" else HORIZONTAL_ALIGNMENT_LEFT
		ol.size = Vector2(220, 28)
		root.add_child(ol)
		_n["origin_" + side] = ol
	## 拔河条(路名计时牌下面)
	var tug := Control.new()
	tug.name = N_TUG
	tug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tug.size = Vector2(TUG_W, 10)
	tug.set_meta("frac", 0.5)
	tug.draw.connect(_draw_tug.bind(tug))
	root.add_child(tug)
	_n["tug"] = tug
	## 全局决赛日小条的停靠位: 拔河条下面正中(顶上那一整条是双方血条 / VS, 不是按钮, 小条自己量不出来)
	var dock := Ctx.bar_dock(N_BAR_DOCK, Rect2(cx - Ctx.BAR_W * 0.5, TOP_Y + 64.0, Ctx.BAR_W, Ctx.BAR_H))
	root.add_child(dock)
	_n["bar_dock"] = dock
	_place_top()
	## 下一场条(底部正中)
	var nl := Ctx.next_line(pn.get("next", {}) if pn.get("next", {}) is Dictionary else {})
	if nl != "":
		var np := PanelContainer.new()
		np.name = N_NEXT
		var nsb := StyleBoxFlat.new()
		nsb.bg_color = Color(0.03, 0.05, 0.10, 0.82)
		nsb.border_color = Color("#6a5a34")
		nsb.set_border_width_all(2)
		nsb.set_corner_radius_all(0)
		nsb.content_margin_left = 16
		nsb.content_margin_right = 16
		nsb.content_margin_top = 4
		nsb.content_margin_bottom = 4
		np.add_theme_stylebox_override("panel", nsb)
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nt := Label.new()
		nt.text = nl
		nt.add_theme_font_size_override("font_size", 24)
		nt.add_theme_color_override("font_color", COL_TEXT)
		Ctx.outline(nt, 6)
		np.add_child(nt)
		root.add_child(np)
		var sz := np.get_combined_minimum_size()
		np.size = sz
		np.position = Vector2(roundf(cx - sz.x * 0.5), vp.y - m.w - sz.y - 2.0)
		_n["next"] = np
	## 助威: 右下一颗键(法术圆盘左边, 与回放条让开圆盘同一个公式); 按下在它左边展开四个固定表情, 点一个 ⇒ 飘起来、收起
	var key_x: float = vp.x - m.z - SpellDisc.R * 2.0 - 18.0 - PixelKey.KEY_PX
	var key_y: float = vp.y - m.w - PixelKey.KEY_PX
	var ck := PixelKey.HitButton.new()
	ck.name = N_CHEER_KEY
	ck.pad = (PixelKey.HIT_PX - PixelKey.KEY_PX) / 2.0
	ck.custom_minimum_size = Vector2(PixelKey.KEY_PX, PixelKey.KEY_PX)
	ck.size = Vector2(PixelKey.KEY_PX, PixelKey.KEY_PX)
	PixelKey.skin(ck, KEY_UP, KEY_DOWN)
	ck.icon = PixelKey.up(CHEER_DIR % "cheer", 1)
	ck.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ck.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	ck.process_mode = Node.PROCESS_MODE_ALWAYS
	ck.position = Vector2(key_x, key_y)
	ck.pressed.connect(toggle_cheers)
	root.add_child(ck)
	_n["cheer_key"] = ck
	var row := HBoxContainer.new()
	row.name = N_CHEERS
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kh := CHEER_KEY
	row.size = Vector2(4.0 * kh + 24.0, kh)
	row.position = Vector2(key_x - 10.0 - row.size.x, vp.y - m.w - kh)
	row.visible = false
	root.add_child(row)
	_n["cheers"] = row
	for nm in CHEERS:
		var b := PixelKey.HitButton.new()
		b.name = N_CHEER + nm
		b.pad = 4.0
		b.custom_minimum_size = Vector2(kh, kh)
		b.size = Vector2(kh, kh)
		PixelKey.skin(b, KEY_UP, KEY_DOWN)
		b.icon = PixelKey.up(CHEER_DIR % nm, 2)          # 32 源像素 ×2 = 64, 键面 88 − 两边 12 正好放下
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.pressed.connect(cheer.bind(nm))
		row.add_child(b)
	## 路间幕布上那一块(平时藏着)
	_build_break(vp)
	late = joined_late()
	if late and _can_seek():
		var fs := PixelKey.HitButton.new()           # 叠在画面上的控制键 ⇒ 像素键底座(与回放条同一套), 不用卡片按钮
		fs.name = N_FROM_START
		fs.pad = 10.0
		fs.text = TXT_FROM_START
		fs.add_theme_font_size_override("font_size", 22)
		PixelKey.skin(fs, KEY_UP, KEY_DOWN, 16.0, 6.0)
		fs.custom_minimum_size = Vector2(136, 54)
		fs.size = Vector2(136, 54)
		fs.process_mode = Node.PROCESS_MODE_ALWAYS
		fs.position = Vector2(m.x, tag_y + 42.0)
		fs.pressed.connect(toggle_from_start)
		root.add_child(fs)
		_n["from_start"] = fs
	## 自己这几样不是按钮, 全局决赛日小条量不出来 ⇒ 登记让路
	Ctx.bar_avoid([tag, _n["dg_left"], _n["dg_right"], _n["tug"], _n.get("origin_left"), _n.get("origin_right"), _n.get("next"),
		_n["cheer_key"], _n["cheers"], _n.get("from_start")])
	_disconnect()                        # 同一个对象再搭一次(换比例)⇒ 钟跟着挂到新根上
	_ticker = Ctx.start_ticker(root, self)
	refresh()
	return root


## 路间幕布那一块(G24 9-4): 赛事转播的比分插卡 —— 整屏深底(与幕布同色, 盖住幕布那块金属面板)+ 中间一条横贯的亮带
##   (斜纹 + 比分背后一圈金光 + 上下金线), 带子上沿压一条红缎带写路名(美术字)+「战果」, 下面「X 拿下上路」、
##   大比分(美术字数字, 领先的一边金、另一边冷灰, 两侧名字)、三路灯、「接下来 · 下路战场」。不画框, 不像弹窗。
func _build_break(vp: Vector2) -> void:
	var bk := Control.new()
	bk.name = N_BREAK
	bk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bk.size = vp
	bk.visible = false
	bk.set_meta("band_y", roundf(vp.y * 0.5 - BREAK_H * 0.5 + 16.0))
	bk.draw.connect(_draw_break_bg.bind(bk))
	root.add_child(bk)
	_n["break"] = bk
	var by: float = float(bk.get_meta("band_y"))
	var cx: float = roundf(vp.x * 0.5)
	## 插卡期间全局决赛日小条的停靠位: 缎带上方那块空地正中(插卡是整屏, 小条自己找位置会落到左下角压住退出键)
	var bdock := Ctx.bar_dock(N_BREAK_DOCK, Rect2(cx - Ctx.BAR_W * 0.5, roundf((by - 44.0 - Ctx.BAR_H) * 0.5), Ctx.BAR_W, Ctx.BAR_H))
	bk.add_child(bdock)
	## 红缎带: 路名美术字 +「战果」
	var rib := Control.new()
	rib.name = "BreakRibbon"
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rib.size = Vector2(minf(600.0, vp.x - 120.0), 92)
	rib.position = Vector2(roundf(cx - rib.size.x * 0.5), by - 44.0)
	rib.draw.connect(_draw_red_ribbon.bind(rib))
	bk.add_child(rib)
	var t1 := Ctx.title_lbl("", 48, COL_GOLD)
	t1.name = "BreakTitle"
	t1.self_modulate.a = 0.0                    # 字(「上路战场 · 战果」)留给门禁 / 读屏; 画面是下面那一排美术字
	t1.size = Vector2(rib.size.x, 78)
	rib.add_child(t1)
	_n["break_title"] = t1
	var trow := HBoxContainer.new()
	trow.name = "BreakTitleArt"
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 12)
	trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trow.size = Vector2(rib.size.x, 78)
	rib.add_child(trow)
	_n["break_title_row"] = trow
	var t2 := Label.new()
	t2.name = "BreakWho"
	t2.add_theme_font_size_override("font_size", 30)
	t2.add_theme_color_override("font_color", COL_TEXT)
	Ctx.outline(t2, 8)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.size = Vector2(vp.x, 40)
	t2.position = Vector2(0, by + 58.0)
	t2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bk.add_child(t2)
	_n["break_who"] = t2
	var sy: float = by + 104.0
	for side in ["left", "right"]:
		var dg := Ctx.title_lbl("0", 72, COL_GOLD)
		dg.name = "BreakDigit_" + side
		dg.size = Vector2(80, 96)
		dg.position = Vector2(cx + (-118.0 if side == "left" else 38.0), sy)
		bk.add_child(dg)
		Ctx.set_digit(dg, 0, true)
		_n["bdg_" + side] = dg
		var nl := Label.new()
		nl.name = "BreakName_" + side
		nl.add_theme_font_size_override("font_size", 30)
		nl.add_theme_color_override("font_color", SIDE_COL[side])
		Ctx.outline(nl, 8)
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == "left" else HORIZONTAL_ALIGNMENT_LEFT
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var nw: float = clampf(cx - 160.0 - 40.0, 120.0, 380.0)
		nl.size = Vector2(nw, 96)
		nl.position = Vector2(cx - 150.0 - nw if side == "left" else cx + 150.0, sy)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bk.add_child(nl)
		_n["break_" + side] = nl
	var colon := Ctx.title_lbl(":", 72, Color("#fff6dc"))
	colon.size = Vector2(40, 96)
	colon.position = Vector2(cx - 20.0, sy - 4.0)
	bk.add_child(colon)
	var lr := HBoxContainer.new()
	lr.name = "BreakLamps"
	lr.alignment = BoxContainer.ALIGNMENT_CENTER
	lr.add_theme_constant_override("separation", 18)
	lr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lr.size = Vector2(vp.x, 70)
	lr.position = Vector2(0, sy + 108.0)
	bk.add_child(lr)
	for ln in Ctx.LANES:
		var lp := Control.new()
		lp.name = "BreakLamp_" + str(ln)
		lp.custom_minimum_size = Vector2(LAMP_BIG + 40.0, LAMP_BIG + 30.0)
		lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lp.set_meta("side", "")
		lp.set_meta("cur", false)
		lp.set_meta("px", LAMP_BIG)
		lp.draw.connect(_draw_lamp.bind(lp, str(Ctx.LANE_SHORT[ln])))
		lr.add_child(lp)
		_n["blamp_" + str(ln)] = lp
	var t4 := Label.new()
	t4.name = "BreakNext"
	t4.add_theme_font_size_override("font_size", 26)
	t4.add_theme_color_override("font_color", Color("#c9d8ea"))
	Ctx.outline(t4, 6)
	t4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t4.size = Vector2(vp.x, 34)
	t4.position = Vector2(0, sy + 186.0)
	t4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bk.add_child(t4)
	_n["break_next"] = t4


## 缎带标题那一排: 路名美术字(上路战场 / 下路战场 / 终极战场)+「战果」(标题字)。路变了才重建。
func _set_break_title(cur: String) -> void:
	var row: HBoxContainer = _n["break_title_row"]
	if str(row.get_meta("lane", "")) == cur:
		return
	row.set_meta("lane", cur)
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var art := Ctx.art_rect(str(Ctx.ART.get(str(LANE_NAMES.get(cur, "")), "")))
	if art != null:
		art.custom_minimum_size = art.size
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(art)
	var r2 := Ctx.title_lbl("战果", 36, Color("#fff2c8"))
	r2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(r2)


# ─────────────────────────────── 刷新 ───────────────────────────────

## 这一路的结果 + 正在结算的那一路(幕布出来时结果还没记进 lane_results, 记账在幕布 5 秒后)。
func lane_state() -> Dictionary:
	var lr: Dictionary = (GameState.lane_results as Dictionary).duplicate() if GameState != null and GameState.lane_results is Dictionary else {}
	var cur := str(GameState.current_lane) if GameState != null and GameState.current_lane != null else ""
	var settling := str(battle.get("_dl_state")) == "lane_settle"
	if settling and Ctx.LANES.has(cur) and not lr.has(cur):
		var lo := str(battle.get("_dl_pending_loser"))
		if lo == "left" or lo == "right":
			lr[cur] = "right" if lo == "left" else "left"
	return {"lr": lr, "cur": cur, "settling": settling}


## 顶栏里的一个节点此刻在屏上的矩形(找不到 = 空矩形; 找到一次就记住)。
func _anchor(nm: String) -> Rect2:
	var nd = _anchors.get(nm, null)
	if nd == null or not is_instance_valid(nd):
		nd = battle.find_child(nm, true, false) if battle is Node else null
		_anchors[nm] = nd
	if nd is Control and (nd as Control).is_visible_in_tree():
		return (nd as Control).get_global_rect()
	return Rect2()


## 比分 / 来历 / 拔河条贴着顶栏摆(顶栏没建出来时退回按屏宽算的位置)。
func _place_top() -> void:
	var cx: float = roundf(_vp.x * 0.5)
	var dots := _anchor("LaneDots")
	if dots.size.x <= 0.0:
		dots = Rect2(cx - 30.0, TOP_Y - 14.0, 60.0, 16.0)
	var dl: Control = _n["dg_left"]
	var dr: Control = _n["dg_right"]
	var dy: float = roundf(dots.get_center().y - dl.size.y * 0.5)
	dl.position = Vector2(dots.position.x - 10.0 - dl.size.x, dy)
	dr.position = Vector2(dots.end.x + 10.0, dy)
	var row := _anchor("LaneRow")
	var ty: float = (row.end.y + 8.0) if row.size.y > 0.0 else TOP_Y + 48.0
	(_n["tug"] as Control).position = Vector2(cx - TUG_W * 0.5, roundf(ty))
	if _n.has("bar_dock"):
		(_n["bar_dock"] as Control).position = Vector2(roundf(cx - Ctx.BAR_W * 0.5), roundf(ty) + 18.0)
	for side in ["left", "right"]:
		if not _n.has("origin_" + side):
			continue
		var ol: Label = _n["origin_" + side]
		var nm := _anchor("TopName_" + ("L" if side == "left" else "R"))
		if nm.size.x > 0.0:
			var lab := battle.find_child("TopName_" + ("L" if side == "left" else "R"), true, false) as Label
			var w: float = lab.get_theme_font("font").get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				lab.get_theme_font_size("font_size")).x if lab != null else 0.0
			var y: float = roundf(nm.get_center().y - ol.size.y * 0.5)
			if side == "left":
				ol.position = Vector2(nm.position.x + w + 14.0, y)
			else:
				ol.position = Vector2(nm.end.x - w - 14.0 - ol.size.x, y)
		else:
			ol.position = Vector2(_vp.x * 0.5 + (-60.0 - ol.size.x if side == "left" else 60.0), 6.0)   # 顶栏没建出来: 摆在名字那一行的中间两侧


## 每 0.1 秒(replay_controls 的计时器)。
func refresh() -> void:
	if root == null or not is_instance_valid(root):
		return
	_place_top()
	var ls := lane_state()
	var lp := Ctx.lamps(ls["lr"], str(ls["cur"]))
	var sc := Ctx.lamp_score(lp)
	for it in lp:
		var bl: Control = _n["blamp_" + str(it[0])]
		bl.set_meta("side", str(it[1]))
		bl.queue_redraw()
	(_n["dg_left"] as Label).text = str(sc[0])
	(_n["dg_right"] as Label).text = str(sc[1])
	## 路间幕布: 压一块路比分
	var bk: Control = _n["break"]
	var show: bool = bool(ls["settling"]) and (ctl == null or ctl.card == null)
	var was_shown := bk.visible
	bk.visible = show
	if show:
		var cur := str(ls["cur"])
		var w := str((ls["lr"] as Dictionary).get(cur, ""))
		var names: Dictionary = ctl._names if ctl != null else {}
		var who := str(names.get("l" if w == "left" else "r", ""))
		(_n["break_title"] as Label).text = TXT_LANE_RESULT % str(LANE_NAMES.get(cur, cur))
		_set_break_title(cur)
		(_n["break_who"] as Label).text = (TXT_LANE_TAKE % [who, str(Ctx.LANE_SHORT.get(cur, ""))]) if who != "" else ""
		Ctx.set_digit(_n["bdg_left"], int(sc[0]), int(sc[0]) >= int(sc[1]))
		Ctx.set_digit(_n["bdg_right"], int(sc[1]), int(sc[1]) >= int(sc[0]))
		(_n["break_left"] as Label).text = str(names.get("l", ""))
		var nxt := ""
		if int(sc[0]) < 2 and int(sc[1]) < 2:
			var i := Ctx.LANES.find(cur)
			nxt = TXT_LANE_NEXT % str(LANE_NAMES.get(str(Ctx.LANES[i + 1]), "")) if i >= 0 and i + 1 < Ctx.LANES.size() else ""
		(_n["break_next"] as Label).text = nxt
		(_n["break_right"] as Label).text = str(names.get("r", ""))
	## 顶上那几样在幕布 / 收尾时收起(幕布上有自己的那一块)
	var top_vis: bool = not show and (ctl == null or ctl.card == null)
	for k in ["tug", "dg_left", "dg_right", "origin_left", "origin_right"]:
		if _n.has(k):
			(_n[k] as CanvasItem).visible = top_vis
	(root.get_node(N_TAG) as CanvasItem).visible = top_vis
	var no_card: bool = ctl == null or ctl.card == null
	(_n["cheer_key"] as Control).visible = no_card
	if not no_card:
		(_n["cheers"] as Control).visible = false
	if _n.has("next"):
		(_n["next"] as Control).visible = no_card and not (_n["cheers"] as Control).visible   # 表情排展开时让位
	if _n.has("from_start"):
		(_n["from_start"] as Button).text = TXT_BACK_LIVE if from_start else TXT_FROM_START
		(_n["from_start"] as Control).visible = (ctl == null or ctl.card == null) and _can_seek()
	## 小条停靠位: 只在观战画面本身时留着(开场 VS / 收尾各有自己的停靠位, 路间插卡时小条自己找位置)
	if _n.has("bar_dock"):
		(_n["bar_dock"] as Control).visible = top_vis and (ctl == null or ctl.vs == null)
	if was_shown != show:
		Ctx.bar_nudge()                          # 路间插卡进出: 小条马上换到对应那一块停靠位


## 每帧: 拔河条平滑追到此刻的比例; 助威飘字往上飘。
func _tick(dt: float) -> void:
	if root == null or not is_instance_valid(root):
		_disconnect()
		return
	_clock += dt
	(_n["live_dot"] as CanvasItem).modulate.a = 0.35 + 0.65 * Ctx.wave(_clock * 0.8)     # 「开播中」那个点一明一暗
	var units: Array = battle.get("_units") if battle.get("_units") is Array else []
	var want := Ctx.tug_frac(Ctx.tug(units))
	_tug_shown += (want - _tug_shown) * clampf(dt * 5.0, 0.0, 1.0)
	var tug: Control = _n["tug"]
	tug.set_meta("frac", _tug_shown)
	tug.set_meta("want", want)
	tug.queue_redraw()
	var keep: Array = []
	for f in _fx:
		var nd: Control = f[0]
		if nd == null or not is_instance_valid(nd):
			continue
		var age: float = _clock - float(f[1])
		if age >= CHEER_RISE:
			nd.queue_free()
			continue
		var p := age / CHEER_RISE
		nd.position = (f[2] as Vector2) + Vector2(-30.0 * Ctx.ease_out(p), -170.0 * Ctx.ease_out(p))
		nd.scale = Vector2.ONE * (Ctx.mix(0.4, 1.0, Ctx.ease_back(Ctx.k01(age, 0.0, 0.25))))
		nd.modulate.a = 1.0 - Ctx.k01(p, 0.65, 0.35)
		keep.append(f)
	_fx = keep


func _disconnect() -> void:
	Ctx.stop_ticker(_ticker)
	_ticker = null


# ─────────────────────────────── 助威 ───────────────────────────────

## 右下那颗键: 展开 / 收起四个表情。
func toggle_cheers() -> void:
	var row: Control = _n["cheers"]
	row.visible = not row.visible
	refresh()


## 按一个固定表情: 从那颗键上飘起一个大号的同款(本机; 不打字、不绑奖励), 表情排收起。连点有间隔。返回 true = 飘出来了。
func cheer(nm: String) -> bool:
	if not CHEERS.has(nm) or _clock - _last_cheer < CHEER_CD:
		return false
	_last_cheer = _clock
	var b: Control = _n["cheer_key"]
	(_n["cheers"] as Control).visible = false
	refresh()
	var tr := TextureRect.new()
	tr.name = N_CHEER_FX
	tr.texture = PixelKey.up(CHEER_DIR % nm, 3)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(96, 96)
	tr.pivot_offset = tr.size * 0.5
	var at: Vector2 = (b.global_position - root.global_position) if b != null else root.size * 0.5
	var p0 := at + Vector2(-18.0, -104.0)
	tr.position = p0
	root.add_child(tr)
	_fx.append([tr, _clock, p0])
	cheers_sent += 1
	return true


# ─────────────────────────────── 迟到 / 从头看 ───────────────────────────────

## 开播后才进来(G17): 开播会话「该到第几步」超过开场幕布那一段。
func joined_late() -> bool:
	var sw = load(SW_PATH)
	var cur: Dictionary = sw.current
	if str(cur.get("kind", "")) == "premiere" and cur.get("premiere", null) is Dictionary:
		return int(sw.premiere_target(cur["premiere"])) >= LATE_STEPS
	var lv = battle._replay.live if battle._replay != null and battle._replay.is_live() else null
	if lv != null and str(lv.kind) == "premiere":
		return int(lv.target_step()) >= LATE_STEPS
	return false


## 状态流播放器在, 而且守卫已经放手(没在「正在连接」)才能跳。
func _can_seek() -> bool:
	var rp = battle._replay
	if rp == null or str(rp.mode) != "stream" or rp.player == null:
		return false
	return str(rp.player.hold_text) == "" and str(rp.player.state) != "ended" and str(rp.player.state) != "error"


## 「从头看」↔「回到直播」。返回播放器 seek 的结果。
func toggle_from_start() -> bool:
	if not _can_seek():
		return false
	var pl = battle._replay.player
	var ok := false
	if not from_start:
		ok = bool(pl.seek(maxi(0, int(pl.first_step))))
	else:
		var sw = load(SW_PATH)
		var cur: Dictionary = sw.current
		var tgt := int(sw.premiere_target(cur.get("premiere", {}))) if cur.get("premiere", null) is Dictionary else int(pl.applied)
		ok = bool(pl.seek(tgt))
	if ok:
		from_start = not from_start
	refresh()
	return ok


# ─────────────────────────────── 画(硬边) ───────────────────────────────

## 一盏路灯: 方形像素灯(暗座 + 亮芯), 亮了是赢下那一路的那一边的颜色; 正在打的那一路描一圈金; 下面写路名。
func _draw_lamp(c: Control, lab: String) -> void:
	var sd := str(c.get_meta("side", ""))
	var cur := bool(c.get_meta("cur", false))
	var px := float(c.get_meta("px", LAMP))
	var box := Rect2(roundf(c.size.x * 0.5 - px * 0.5), 0, px, px)
	c.draw_rect(box.grow(3), Ctx.COL_INK)
	c.draw_rect(box, Color("#1a2230"))
	if sd != "":
		var col: Color = SIDE_COL[sd]
		c.draw_rect(box.grow(-3), col)
		c.draw_rect(Rect2(box.position + Vector2(4, 4), Vector2(6, 4)), Color(1, 1, 1, 0.55))
	elif cur:
		c.draw_rect(box.grow(-6), Color(1.0, 0.85, 0.35, 0.35))
	if cur:
		c.draw_rect(box.grow(5), COL_GOLD, false, 2.0)
	var f := c.get_theme_default_font()
	var fs := 22 if px > LAMP else 16
	var w := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(roundf(c.size.x * 0.5 - w * 0.5), px + float(fs) + 4.0)
	c.draw_string_outline(f, pos, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Ctx.COL_INK)
	c.draw_string(f, pos, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_TEXT if sd != "" or cur else COL_SUB)


## 拔河条: 深槽 + 左色从左、右色从右, 交界处一道白缝(往哪边推一眼看得出)。
func _draw_tug(c: Control) -> void:
	var s := c.size
	var f := clampf(float(c.get_meta("frac", 0.5)), 0.0, 1.0)
	c.draw_rect(Rect2(-2, -2, s.x + 4.0, s.y + 4.0), Ctx.COL_INK)
	var split: float = roundf(s.x * f)
	var lc: Color = SIDE_COL["left"]
	var rc: Color = SIDE_COL["right"]
	c.draw_rect(Rect2(0, 0, split, s.y), lc.darkened(0.25))
	c.draw_rect(Rect2(0, 0, split, 4), lc)
	c.draw_rect(Rect2(split, 0, s.x - split, s.y), rc.darkened(0.25))
	c.draw_rect(Rect2(split, 0, s.x - split, 4), rc)
	c.draw_rect(Rect2(split - 2.0, -4, 4, s.y + 8.0), Color("#fff6dc"))


## 路间插卡的底: 整屏幕布同色深底 + 中间一条亮带(三级阶梯明暗 + 斜纹 + 比分背后金光 + 上下金线两端渐隐)。硬边。
func _draw_break_bg(c: Control) -> void:
	var s := c.size
	var by := float(c.get_meta("band_y", s.y * 0.3))
	var band := Rect2(0, by, s.x, BREAK_H)
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.05, 0.09, 1.0))
	c.draw_rect(band, Color(0.05, 0.08, 0.15))
	c.draw_rect(Rect2(0, by + BREAK_H * 0.18, s.x, BREAK_H * 0.64), Color(0.07, 0.11, 0.20))
	c.draw_rect(Rect2(0, by + BREAK_H * 0.32, s.x, BREAK_H * 0.36), Color(0.09, 0.14, 0.25))
	Ctx.draw_hatch(c, band, Color(1, 1, 1, 0.04), 14.0)
	Ctx.draw_rays(c, Vector2(s.x * 0.5, by + 152.0), BREAK_H * 0.44, 60.0, Color(1.0, 0.84, 0.36, 0.10))      # 光芒收在亮带里
	var gold := Color("#d8b45a")
	var seg := roundf(s.x * 0.04)
	for y in [by, by + BREAK_H - 3.0]:
		c.draw_rect(Rect2(seg * 8.0, y, s.x - seg * 16.0, 3.0), gold)
		for i in range(8):
			var col := Color(gold.r, gold.g, gold.b, float(i + 1) / 9.0)
			c.draw_rect(Rect2(seg * float(i), y, seg, 3.0), col)
			c.draw_rect(Rect2(s.x - seg * float(i + 1), y, seg, 3.0), col)


func _draw_red_ribbon(c: Control) -> void:
	Ctx.draw_ribbon(c, c.size, 78.0, true)
