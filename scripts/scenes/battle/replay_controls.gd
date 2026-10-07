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
## ★★2026-10-07 第二轮(用户「回放系统也是个问题呢」, 新玩家实录 C:/tmp/newplayer/rp_sheet.jpg):
##   ① 左上铭牌**删掉**: 它写的「上路战场 / A 对 B」与对局顶栏(两端名字 + VS 下面的路名计时牌)一字不差地重复,
##      而且开场那块「三路开战 / 对阵」牌子出来时它正好压在牌子左上角。
##      「这是回放」改成顶栏路名牌左边一枚小签「回放」(topbar_status `ReplayMark`)。
##   ② 底部操作条放大(按钮 48→72 高, 条宽 52%→64% 视口), 进度条上每一路开打处的刻度下面写路名(上路 / 下路 / 终极),
##      当前那一路的字点亮。参考: 部落冲突回放底栏(大按钮 + 长进度条)、皇室战争回放。
##   ★点路名**不跳转**: ReplayRecorder 只能从第 0 步往前逐步重算(没有存档点, 没有 seek),
##     做跳转等于另造一条「快进到第 N 步」的路径, 那是确定性风险(方案书 §已知风险)。
## ★只用现成的皮: 底板 = 战斗信息面板那块金属框(`SettleScreen.frame_style()`, 结算屏同一张),
##   按钮 = `UISkin.button()` 的签牌/木牌。不新增素材、不用圆角卡片/渐变/emoji。
## ★倍速与暂停不碰 sim: 只改 `ReplayRecorder.time_mult()`(一帧跑几步), 步长不变 ⇒ 校验点照样逐个比。
## ★放这里的理由(CLAUDE.md §5): 不在 `_sim_step` 调用链上 ⇒ 不进主文件; battle_hud 已近上限 ⇒ 单独一个文件。
##
## ★★2026-10-07 观赛(docs/plans/20261007-实时观赛.md, 用户「观赛和回放是两码事明白吗」):
##   观赛(`ReplayRecorder.is_live()`: 周六直播 / 周日开播)**不建**操作条与「已暂停」签牌 ——
##   没有暂停 / 倍速 / 进度条 / 全场时长; 只有左下角「退出」与底部一行状态(同步中 / 下路准备中)。
##   收尾卡只揭晓谁赢 + 「返回」, 没有「再看一遍」(那是回放)。参考: 皇室战争观战(同一套 HUD + Live 小签, 无播放控制)。

const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")

const COL_GOLD := Color("#ffd93d")
const COL_LOSS := Color("#ff6b6b")
const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const STRIP_H := 112.0
const BTN_H := 72.0
## 进度条上路名的字(按开打顺序; 刻度只画录像里真有的那几路)。
const TICK_NAMES := ["上路", "下路", "终极"]
const TICK_LW := 48.0             # 一个路名占的宽(两字 18px + 余量), 挨得太近时往右推开
const BAR_Y := 18.0               # 进度槽在 _track 里的 y
const BAR_H := 8.0
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
const N_TICK_LBL := "ReplayTickLabel"   # + 下标 0/1/2(上路/下路/终极)
const N_LIVE_EXIT := "LiveExit"          # 观赛: 左下角「退出」
const N_LIVE_STATUS := "LiveStatus"      # 观赛: 底部状态(同步中 / 下路准备中)
const N_LIVE_SHADE := "LiveSyncShade"    # 观赛: 追帧时盖住战场的暗幕(追帧一帧 8 步, 幕布 / 演出叠成一团, 不给人看)
const LIVE_BTN := Vector2(128.0, 60.0)

var battle
var root: Control = null           # 全屏、不吃点击; battle_hud._replay_bar 指向它
var strip: PanelContainer = null
var pause_btn: Button = null
var speed_btn: Button = null
var exit_btn: Button = null
var time_lb: Label = null
var tick_lbs: Array = []
var paused_tag: Control = null
var card: Control = null
var _track: Control = null
var _fill: ColorRect = null
var _names: Dictionary = {}
var live_exit: Button = null
var live_status: PanelContainer = null
var live_shade: ColorRect = null
var _live_lb: Label = null


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
	## 对阵图那一场: 认不出谁是录像方(对手快照的名字对不上这一场的两个人)时, 收尾卡至少按对阵图上的顺序写出两个人。
	var pair = ReplayRecorder.play_names.get("pair", [])
	if str(_names.get("l", "")) == "" and str(_names.get("r", "")) == "" and pair is Array and (pair as Array).size() == 2:
		_names = {"l": str(pair[0]), "r": str(pair[1])}
	if battle._replay.is_live():
		_build_live(vp, m)
	else:
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


# ─────────────────────────────── 底部操作条 ───────────────────────────────

## [暂停][倍速][进度条 + 路名][已播/全场][退出回放]。底板 = 结算屏同一张金属框, 按钮 = 大木牌(短边 72 ≥ 56 ⇒ frame-rect)。
func _build_strip(vp: Vector2, m: Vector4) -> void:
	strip = PanelContainer.new()
	strip.name = "ReplayStrip"
	strip.add_theme_stylebox_override("panel", _frame(26, 20))
	strip.mouse_filter = Control.MOUSE_FILTER_STOP     # 点在条上不穿到战场
	var w: float = clampf(vp.x * 0.64, 820.0, 1060.0)
	w = minf(w, vp.x - m.x - m.z)
	strip.custom_minimum_size = Vector2(w, STRIP_H)
	strip.size = Vector2(w, STRIP_H)
	strip.position = Vector2((vp.x - w) * 0.5, vp.y - m.w - STRIP_H + 8.0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(hb)
	pause_btn = _btn("暂停", 112.0, Color.WHITE)
	pause_btn.name = N_PAUSE
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	sc.events = [ev]
	pause_btn.shortcut = sc
	pause_btn.shortcut_in_tooltip = false
	pause_btn.pressed.connect(toggle_pause)
	hb.add_child(pause_btn)
	speed_btn = _btn("", 128.0, Color.WHITE)
	speed_btn.name = N_SPEED
	speed_btn.pressed.connect(cycle_speed)
	hb.add_child(speed_btn)
	## 进度条: 深色槽 + 金色填充 + 每一路开打处一道刻度, 刻度下面写路名。
	_track = Control.new()
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track.custom_minimum_size = Vector2(160, BTN_H)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_track)
	time_lb = _lbl("", 20, COL_TEXT)
	time_lb.name = N_TIME
	time_lb.custom_minimum_size = Vector2(118, 0)
	time_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(time_lb)
	exit_btn = _btn("退出回放", 150.0, Color(0.80, 0.84, 0.90))
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
		_track.remove_child(c)       # 先摘下再释放: 新建的路名才拿得到原名(门禁按名字找)
		c.queue_free()
	tick_lbs.clear()
	var w := _track.size.x
	var y := BAR_Y
	## 槽: 暗底 + 上沿 1px 暗线 / 下沿 1px 亮线(像素凹槽), 不是圆角进度条。
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.95)
	bg.position = Vector2(0, y)
	bg.size = Vector2(w, BAR_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(bg)
	var lip := ColorRect.new()
	lip.color = Color(0.45, 0.55, 0.68, 0.55)
	lip.position = Vector2(0, y + BAR_H)
	lip.size = Vector2(w, 1)
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(lip)
	_fill = ColorRect.new()
	_fill.color = COL_GOLD
	_fill.position = Vector2(0, y)
	_fill.size = Vector2(0, BAR_H)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_fill)
	var tot := float(maxi(1, battle._replay.total_steps()))
	var fs: Array = battle._replay.fight_steps()
	var prev_x := -INF
	for i in range(fs.size()):
		var x: float = roundf(w * clampf(float(fs[i]) / tot, 0.0, 1.0))
		var tk := ColorRect.new()
		tk.color = Color(0.85, 0.92, 1.0, 0.9)
		tk.position = Vector2(x - 1.0, y - 6.0)
		tk.size = Vector2(2, BAR_H + 12.0)
		tk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_track.add_child(tk)
		if i >= TICK_NAMES.size():
			continue
		## 路名: 以刻度为中心; 挨得太近就往右推开一个字宽, 两端不出槽。
		var lx: float = maxf(x - TICK_LW * 0.5, prev_x + TICK_LW)
		lx = clampf(lx, 0.0, maxf(0.0, w - TICK_LW))
		prev_x = lx
		var lb := _lbl(str(TICK_NAMES[i]), 18, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER)
		lb.name = N_TICK_LBL + str(i)
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lb.add_theme_constant_override("outline_size", 4)
		lb.position = Vector2(lx, y + BAR_H + 8.0)
		lb.size = Vector2(TICK_LW, 24)
		_track.add_child(lb)
		tick_lbs.append(lb)
	refresh()


## 观赛: 左下角一颗「退出」+ 底部正中一块状态牌(平时藏着)。没有任何播放控制。
func _build_live(vp: Vector2, m: Vector4) -> void:
	## 追帧暗幕先建(加入顺序 = 绘制顺序): 状态牌与「退出」画在它上面。
	live_shade = ColorRect.new()
	live_shade.name = N_LIVE_SHADE
	live_shade.color = Color(0.02, 0.03, 0.06, 0.92)
	live_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	live_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_shade.visible = false
	root.add_child(live_shade)
	live_exit = _btn("退出", LIVE_BTN.x, Color(0.80, 0.84, 0.90))
	live_exit.name = N_LIVE_EXIT
	live_exit.custom_minimum_size = LIVE_BTN
	live_exit.size = LIVE_BTN
	live_exit.position = Vector2(m.x, vp.y - m.w - LIVE_BTN.y)
	live_exit.pressed.connect(battle._hud._replay_exit)
	root.add_child(live_exit)
	live_status = PanelContainer.new()
	live_status.name = N_LIVE_STATUS
	live_status.add_theme_stylebox_override("panel", _frame(26, 10))
	live_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_lb = _lbl("", 24, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	live_status.add_child(_live_lb)
	live_status.visible = false
	root.add_child(live_status)


func _sync_live() -> void:
	if live_status == null or not is_instance_valid(live_status):
		return
	var lv = battle._replay.live
	var t: String = str(lv.status) if lv != null and not bool(lv.broken) else ""
	live_status.visible = t != "" and card == null
	## 追帧中(一帧 8 步): 整屏暗幕 + 正中「同步中」; 平时: 底部正中一块小牌(下路准备中 / 卡在 horizon 上等数据)。
	var shade: bool = lv != null and bool(lv.catching) and t != "" and card == null
	if live_shade != null:
		live_shade.visible = shade
	if _live_lb.text != t:
		_live_lb.text = t
		live_status.reset_size()
	var vp := _vp()
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	var sz := live_status.get_combined_minimum_size()
	live_status.size = sz
	if shade:
		live_status.position = Vector2((vp.x - sz.x) * 0.5, (vp.y - sz.y) * 0.5)
	else:
		live_status.position = Vector2((vp.x - sz.x) * 0.5, vp.y - m.w - sz.y - 6.0)


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
	if rp.is_live():
		_sync_live()
		return
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
	## 路名: 正在打的那一路点亮(金), 打过的白, 没到的暗。
	var ln := str(GameState.current_lane) if GameState != null and GameState.current_lane != null else ""
	var cur_i: int = ["top", "bottom", "final"].find(ln)
	if ln == "done":
		cur_i = TICK_NAMES.size()
	for i in range(tick_lbs.size()):
		var lb = tick_lbs[i]
		if lb == null or not is_instance_valid(lb):
			continue
		var c: Color = COL_GOLD if i == cur_i else (COL_TEXT if i < cur_i else Color(0.50, 0.58, 0.68))
		(lb as Label).add_theme_color_override("font_color", c)


# ─────────────────────────────── 收尾 ───────────────────────────────

## 播完: 等最后一击落地, 再出收尾卡。
func show_end(won: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	if strip != null:
		strip.visible = false
	if live_status != null:
		live_status.visible = false
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
	if strip != null:
		strip.visible = false
	_end_card(false, true)


## 观赛中断(打的人断线 / 数据对不上): 当场出卡, 只有「返回」。
func show_broken() -> void:
	if root == null or not is_instance_valid(root):
		return
	if live_status != null:
		live_status.visible = false
	_end_card(false, true)


func _end_card(won: bool, broken: bool) -> void:
	if card != null or root == null or not is_instance_valid(root):
		return
	if battle._dmg_stats != null and battle._dmg_stats.panel != null and is_instance_valid(battle._dmg_stats.panel):
		battle._dmg_stats.panel.visible = false
	if live_exit != null:
		live_exit.visible = false          # 收尾卡上有「返回」, 左下角那颗不再留着
	if live_shade != null:
		live_shade.visible = false
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
	var lv = battle._replay.live if battle._replay.is_live() else null
	if broken:
		title = "回放中断"
		if lv != null:
			title = str(lv.broken_why) if str(lv.broken_why) != "" else lv.TXT_BROKEN
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
		sub = "回放异常，无法继续播放" if lv == null else ""
	else:
		var l := str(_names.get("l", ""))
		var r := str(_names.get("r", ""))
		if l != "" and r != "":
			sub = "%s  对  %s" % [l, r]
		var tot: int = battle._replay.total_steps()
		if tot > 0 and lv == null:       # 观赛不报全场时长
			sub += ("  ·  " if sub != "" else "") + "全场 " + clock(tot)
	if sub != "":
		vb.add_child(_lbl(sub, 20, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	if not broken and lv == null:          # 「再看一遍」只有回放有
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
	b.add_theme_font_size_override("font_size", 22)
	UISkin.button(b, tint)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, COL_TEXT)
	return b


## 与结算屏同一个小工具(不抄一份: dup_primitive 棘轮按函数体哈希抓副本)。
static func _lbl(t: String, fs: int, c: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return SettleScreenS._lbl(t, fs, c, align)
