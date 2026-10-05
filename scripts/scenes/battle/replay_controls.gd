class_name ReplayControls
extends RefCounted
## replay_controls.gd — 看回放时的操作条与收尾卡(方案书 docs/plans/20261005-回放体验打磨.md)。
##
## 用户 2026-10-05:「模拟下打开窗口看这周比赛回放，找任何不合理的问题，比如玩家手感，ai味，然后全部给我修好」。
##
## 改之前看回放只有左上角一行「回放」两个字 + 一颗 Godot 默认灰钮「退出回放」:
##   不能暂停、不能快进(一局 1 倍速要看将近两分钟)、看不出谁对谁、打到哪一路、还剩多久;
##   结束时战场中央飘一行「回放结束 —— 失败」+ 同一颗灰钮, 没有「再看一遍」。
## 照市面上的回放器(王者/皇室战争/荒野乱斗/云顶的回放)补齐四样:
##   ① 左上「回放」铭牌: 谁对谁 + 现在打到哪一路
##   ② 底部操作条: 暂停/继续 · 1/2/4 倍速 · 进度条(每一路开打处一道刻度) · 已播/全场时长 · 退出回放
##   ③ 暂停时屏幕中间一块「已暂停」签牌
##   ④ 收尾卡: 谁赢了 + 双方 + 全场时长 · 「再看一遍」「返回」
##
## ★只用现成的皮: 底板 = 战斗信息面板那块金属框(`SettleScreen.frame_style()`, 结算屏同一张),
##   按钮 = `UISkin.button()` 的签牌/木牌。不新增素材、不用圆角卡片/渐变/emoji。
## ★倍速与暂停不碰 sim: 只改 `ReplayRecorder.time_mult()`(一帧跑几步), 步长不变 ⇒ 校验点照样逐个比。
## ★放这里的理由(CLAUDE.md §5): 不在 `_sim_step` 调用链上 ⇒ 不进主文件; battle_hud 已近上限 ⇒ 单独一个文件。

const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")

const COL_GOLD := Color("#ffd93d")
const COL_LOSS := Color("#ff6b6b")
const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const STRIP_H := 64.0
const BTN_H := 48.0
const CARD_DELAY := 1.2            # 最后一击落地后再出收尾卡(真实秒)

## 节点名 —— 门禁按名字找, 不按下标、不抄文案。
const N_PAUSE := "ReplayPause"
const N_SPEED := "ReplaySpeed"
const N_EXIT := "ReplayExit"
const N_AGAIN := "ReplayAgain"
const N_BACK := "ReplayBack"
const N_CARD := "ReplayEndCard"
const N_PAUSED := "ReplayPausedTag"
const N_TIME := "ReplayTime"
const N_LANE := "ReplayLane"
const N_NAMES := "ReplayNames"

var battle
var root: Control = null           # 全屏、不吃点击; battle_hud._replay_bar 指向它
var strip: PanelContainer = null
var pause_btn: Button = null
var speed_btn: Button = null
var exit_btn: Button = null
var time_lb: Label = null
var lane_lb: Label = null
var names_lb: Label = null
var paused_tag: Control = null
var card: Control = null
var _track: Control = null
var _fill: ColorRect = null
var _names: Dictionary = {}


func _init(b) -> void:
	battle = b


func _vp() -> Vector2:
	return Vector2(battle.get_viewport().get_visible_rect().size)


func build() -> Control:
	var vp := _vp()
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	root = Control.new()
	root.name = "ReplayControls"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	## ★自己一层, 压在 UI 层上面: 单位头顶血条也挂在 `_ui_layer` 里、而且比这里**晚建**(每路重建),
	##   同一层里后建的画在上面 ⇒ 实拍收尾卡左上角压着一条血条。独立一层就不受建的先后影响。
	var cl := CanvasLayer.new()
	cl.name = "ReplayLayer"
	cl.layer = int(battle._ui_layer.layer) + 1
	battle.add_child(cl)
	cl.add_child(root)
	_names = ReplayRecorder.side_names(battle._replay.rec, ReplayRecorder.viewer_name)
	_build_plate(m)
	_build_strip(vp, m)
	_build_paused_tag(vp)
	var tm := Timer.new()
	tm.wait_time = 0.1
	tm.autostart = true
	tm.process_mode = Node.PROCESS_MODE_ALWAYS
	tm.timeout.connect(refresh)
	root.add_child(tm)
	refresh()
	return root


# ─────────────────────────────── 左上铭牌 ───────────────────────────────

func _build_plate(m: Vector4) -> void:
	var pc := PanelContainer.new()
	pc.name = "ReplayPlate"
	pc.add_theme_stylebox_override("panel", _frame(16, 10))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.position = Vector2(m.x, m.y + 70.0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	top.add_child(_lbl("回放", 20, COL_GOLD))
	lane_lb = _lbl("", 18, COL_TEXT)
	lane_lb.name = N_LANE
	top.add_child(lane_lb)
	var l := str(_names.get("l", ""))
	var r := str(_names.get("r", ""))
	## 对阵图那一场: 认不出谁是录像方(对手快照的名字对不上这一场的两个人)时, 至少按对阵图上的顺序写出两个人。
	var pair = ReplayRecorder.play_names.get("pair", [])
	if l == "" and r == "" and pair is Array and (pair as Array).size() == 2:
		l = str(pair[0])
		r = str(pair[1])
		_names = {"l": l, "r": r}
	if l != "" or r != "":
		names_lb = _lbl("%s  对  %s" % [l if l != "" else "?", r if r != "" else "?"], 15, COL_SUB)
		names_lb.name = N_NAMES
		names_lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names_lb.custom_minimum_size = Vector2(220, 0)
		vb.add_child(names_lb)
	root.add_child(pc)


# ─────────────────────────────── 底部操作条 ───────────────────────────────

func _build_strip(vp: Vector2, m: Vector4) -> void:
	strip = PanelContainer.new()
	strip.name = "ReplayStrip"
	strip.add_theme_stylebox_override("panel", _frame(18, 8))
	strip.mouse_filter = Control.MOUSE_FILTER_STOP     # 点在条上不穿到战场
	var w: float = clampf(vp.x * 0.52, 600.0, 780.0)
	strip.custom_minimum_size = Vector2(w, STRIP_H)
	strip.size = Vector2(w, STRIP_H)
	strip.position = Vector2((vp.x - w) * 0.5, vp.y - m.w - STRIP_H + 6.0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(hb)
	pause_btn = _btn("暂停", 92.0, Color.WHITE)
	pause_btn.name = N_PAUSE
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	sc.events = [ev]
	pause_btn.shortcut = sc
	pause_btn.shortcut_in_tooltip = false
	pause_btn.pressed.connect(toggle_pause)
	hb.add_child(pause_btn)
	speed_btn = _btn("", 104.0, Color.WHITE)
	speed_btn.name = N_SPEED
	speed_btn.pressed.connect(cycle_speed)
	hb.add_child(speed_btn)
	## 进度条: 深色槽 + 金色填充 + 每一路开打处一道刻度。
	_track = Control.new()
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track.custom_minimum_size = Vector2(120, BTN_H)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_track)
	time_lb = _lbl("", 16, COL_TEXT)
	time_lb.name = N_TIME
	time_lb.custom_minimum_size = Vector2(96, 0)
	time_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(time_lb)
	exit_btn = _btn("退出回放", 120.0, Color(0.80, 0.84, 0.90))
	exit_btn.name = N_EXIT
	exit_btn.pressed.connect(battle._hud._replay_exit)
	hb.add_child(exit_btn)
	root.add_child(strip)
	_track.resized.connect(_layout_track)
	_layout_track.call_deferred()


func _layout_track() -> void:
	if _track == null or not is_instance_valid(_track):
		return
	for c in _track.get_children():
		c.queue_free()
	var w := _track.size.x
	var y := _track.size.y * 0.5 - 3.0
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.9)
	bg.position = Vector2(0, y)
	bg.size = Vector2(w, 6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(bg)
	_fill = ColorRect.new()
	_fill.color = COL_GOLD
	_fill.position = Vector2(0, y)
	_fill.size = Vector2(0, 6)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_fill)
	var tot := float(maxi(1, battle._replay.total_steps()))
	for s in battle._replay.fight_steps():
		var tk := ColorRect.new()
		tk.color = Color(0.85, 0.92, 1.0, 0.85)
		tk.position = Vector2(roundf(w * clampf(float(s) / tot, 0.0, 1.0)) - 1.0, y - 5.0)
		tk.size = Vector2(2, 16)
		tk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_track.add_child(tk)
	refresh()


func _build_paused_tag(vp: Vector2) -> void:
	var pc := PanelContainer.new()
	pc.name = N_PAUSED
	pc.add_theme_stylebox_override("panel", _frame(26, 12))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(_lbl("已暂停", 26, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	pc.visible = false
	root.add_child(pc)
	pc.reset_size()
	pc.position = Vector2((vp.x - 160.0) * 0.5, vp.y * 0.5 - 40.0)
	pc.custom_minimum_size = Vector2(160, 0)
	paused_tag = pc


# ─────────────────────────────── 操作 ───────────────────────────────

func toggle_pause() -> void:
	if battle._replay.finished or battle._replay.diverged_at >= 0:
		return
	battle._replay.paused = not battle._replay.paused
	refresh()


func cycle_speed() -> void:
	battle._replay.cycle_speed()
	refresh()


static func clock(steps: int) -> String:
	var sec := maxi(0, int(floor(float(steps) / 60.0)))
	return "%d:%02d" % [sec / 60, sec % 60]


## 每 0.1 秒刷一次(暂停时也刷: 时钟由 Timer 驱动, 不挂在 sim 步上)。
func refresh() -> void:
	if root == null or not is_instance_valid(root):
		return
	var rp = battle._replay
	if pause_btn != null:
		pause_btn.text = "继续" if rp.paused else "暂停"
	if speed_btn != null:
		speed_btn.text = "%d 倍速" % int(rp.speed)
	if paused_tag != null:
		paused_tag.visible = rp.paused and card == null
	var tot: int = rp.total_steps()
	var cur: int = mini(int(battle._sim_step_n), tot) if tot > 0 else int(battle._sim_step_n)
	if time_lb != null:
		time_lb.text = "%s / %s" % [clock(cur), clock(tot)] if tot > 0 else clock(cur)
	if _fill != null and is_instance_valid(_fill) and _track != null and tot > 0:
		_fill.size.x = _track.size.x * clampf(float(cur) / float(tot), 0.0, 1.0)
	if lane_lb != null:
		var ln := str(GameState.current_lane) if GameState != null and GameState.current_lane != null else ""
		lane_lb.text = str(battle._LANE_CN.get(ln, ""))   # 路名唯一出处


# ─────────────────────────────── 收尾 ───────────────────────────────

## 播完: 等最后一击落地, 再出收尾卡。
func show_end(won: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	strip.visible = false
	if paused_tag != null:
		paused_tag.visible = false
	var tm := Timer.new()
	tm.one_shot = true
	tm.wait_time = CARD_DELAY
	tm.process_mode = Node.PROCESS_MODE_ALWAYS
	tm.timeout.connect(func() -> void: _end_card(won, false))
	root.add_child(tm)
	tm.start()


## 对不上: 当场停、当场出卡(只有「返回」)。
func show_mismatch() -> void:
	if root == null or not is_instance_valid(root):
		return
	strip.visible = false
	_end_card(false, true)


func _end_card(won: bool, broken: bool) -> void:
	if card != null or root == null or not is_instance_valid(root):
		return
	if battle._dmg_stats != null and battle._dmg_stats.panel != null and is_instance_valid(battle._dmg_stats.panel):
		battle._dmg_stats.panel.visible = false
	var dim := ColorRect.new()
	dim.name = N_CARD
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	card = dim
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", SettleScreenS.frame_style())
	pc.custom_minimum_size = Vector2(560, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	var title: String
	var col: Color
	if broken:
		title = "回放中断"
		col = COL_LOSS
	else:
		title = ReplayRecorder.end_caption(won)
		var own := ReplayRecorder.play_names.is_empty()
		col = (COL_GOLD if won else COL_LOSS) if own else COL_GOLD
	var tl := _lbl(title, 44, col, HORIZONTAL_ALIGNMENT_CENTER)
	tl.name = "ReplayResult"
	vb.add_child(tl)
	var sub := ""
	if broken:
		sub = "这场回放出了点问题，没法继续往下播"
	else:
		var l := str(_names.get("l", ""))
		var r := str(_names.get("r", ""))
		if l != "" and r != "":
			sub = "%s  对  %s" % [l, r]
		var tot: int = battle._replay.total_steps()
		if tot > 0:
			sub += ("  ·  " if sub != "" else "") + "全场 " + clock(tot)
	if sub != "":
		vb.add_child(_lbl(sub, 20, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	if not broken:
		var ag := Button.new()
		ag.name = N_AGAIN
		ag.text = "再看一遍"
		SettleScreenS.dress_btn(ag, Color("#ffd27a"), Color("#ffe7a0"))
		ag.pressed.connect(func() -> void: ReplayRecorder.play_again(battle.get_tree(), battle._replay.rec))
		hb.add_child(ag)
	var bk := Button.new()
	bk.name = N_BACK
	bk.text = back_label()
	SettleScreenS.dress_btn(bk, Color("#c9d3de"), Color("#e8f0f6"))
	bk.pressed.connect(battle._hud._replay_exit)
	hb.add_child(bk)


## 「返回」按钮说清回哪一页。
static func back_label() -> String:
	var s := ReplayRecorder.exit_scene()
	if s.ends_with("GauntletBoard.tscn"):
		return "返回赛况"
	if s.ends_with("BracketMap.tscn"):
		return "返回对阵图"
	if s.ends_with("Record.tscn"):
		return "返回战绩"
	return "返回"


# ─────────────────────────────── 小工具 ───────────────────────────────

func _frame(h: int, v: int) -> StyleBox:
	var sb: StyleBox = SettleScreenS.frame_style().duplicate()
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


func _btn(t: String, w: float, tint: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.add_theme_font_size_override("font_size", 18)
	UISkin.button(b, tint)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, COL_TEXT)
	return b


## 与结算屏同一个小工具(不抄一份: dup_primitive 棘轮按函数体哈希抓副本)。
static func _lbl(t: String, fs: int, c: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return SettleScreenS._lbl(t, fs, c, align)
