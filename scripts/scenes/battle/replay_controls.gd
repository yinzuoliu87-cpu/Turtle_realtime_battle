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
##   ② 进度条上每一路开打处的刻度下面写路名, 当前那一路的字点亮。参考: 部落冲突回放底栏、皇室战争回放。
##   ★点路名**不跳转**: ReplayRecorder 只能从第 0 步往前逐步重算(没有存档点, 没有 seek),
##     做跳转等于另造一条「快进到第 N 步」的路径, 那是确定性风险(方案书 §已知风险)。
##
## ★★★2026-10-27 第三轮(用户看了方向稿与风格稿:「回放也要用这个大的这个框框按钮吗？」「这个样式，你又用旧素材是吧？」,
##   风格稿回「行吧」; docs/plans/20261027-UI美术规矩.md §4.6-6):
##   原来是整条不透明金属底板 + 三颗棕底文字大框(商店卡片按钮)。照 13 个商业回放画面的共同做法改成:
##     左下一颗红色退出键 · 右下两颗小方形图标键(暂停 ↔ 播放、x1 → x2 → x4)· 中间一条**没有底板**的细进度条
##     (深色凹槽 + 金色已播 + 每一路开打处一颗菱形 + 播放头, 菱形下面写路名全称)· 进度条右端时间。
##   素材全是这一屏专门新画的(tools/build_replay_queue_ui.py → assets/sprites/ui/replay_bar/), ×3 最近邻(PixelKey)。
##   键看起来 60, 可点 84(用户 10-27 定)。右下两颗键让开法术圆盘(battle_hud._build_spell_disc 同一个公式)。
##   ★退出要确认(方向稿定的): 键小、挨着屏幕边, 误触一下整场回放就没了 ⇒ 点退出先出一个小弹框, 弹框里的按钮属于弹框 ⇒ `UISkin.card_button`。
##   观赛 / 逐帧直播的「退出」是同一颗红键、同样先确认。
## ★倍速与暂停不碰 sim: 只改 `ReplayRecorder.time_mult()`(一帧跑几步), 步长不变 ⇒ 校验点照样逐个比。
## ★放这里的理由(CLAUDE.md §5): 不在 `_sim_step` 调用链上 ⇒ 不进主文件; battle_hud 已近上限 ⇒ 单独一个文件。
##
## ★★2026-10-07 观赛(docs/plans/20261007-实时观赛.md, 用户「观赛和回放是两码事明白吗」):
##   观赛(`ReplayRecorder.is_live()`: 周六直播 / 周日开播)**不建**操作条与「已暂停」签牌 ——
##   没有暂停 / 倍速 / 进度条 / 全场时长; 只有左下角「退出」与底部一行状态(同步中 / 下路准备中)。
##   收尾卡只揭晓谁赢 + 「返回」, 没有「再看一遍」(那是回放)。参考: 皇室战争观战(同一套 HUD + Live 小签, 无播放控制)。
##
## ★★2026-10-20 逐帧直播(状态流, `ReplayRecorder.mode == "stream"`): 回放(播放器 `controls`: 已打完的局)用**同一条**操作条,
##   暂停 / 倍速改的是播放器(StreamPlayer.paused / speed), 进度条**可以拖**: 松手那一刻 `StreamPlayer.seek`(从最近的 keyframe 解,
##   不重算; 播放模式本来就没有 sim)。观赛(正在算 / 周六自己那一场 / 周日开播)照旧只有左下角「退出」。
##   「再看一遍」仍然没有(收尾卡那一条不变)。

const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")

const COL_GOLD := Color("#ffd93d")
const COL_LOSS := Color("#ff6b6b")
const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const COL_INK := Color("#070b16")            # 字的描边色 = 素材的最深描边(没有底板, 字要自己立得住)
## 底部这一带的高(屏底安全边距之上): 6 + 键 60 + 18。幕布上的牌子(dual_lane_flow)在它上面那块里居中。
const STRIP_H := 84.0
const BTN_H := 56.0                          # 退出确认框里的按钮
const KEY_GAP := 12.0                        # 暂停与倍速之间
const DISC_GAP := 18.0                       # 倍速键与法术圆盘之间
const BAR_GAP := 30.0                        # 进度条两端与退出键 / 时间之间
## 进度条上路名的字(按开打顺序; 刻度只画录像里真有的那几路)。全称(用户 10-07「我们叫上路战场，下路战场，终极战场」)。
const TICK_NAMES := ["上路战场", "下路战场", "终极战场"]
const TICK_LW := 96.0             # 一个路名占的宽(四字 20px + 描边余量), 挨得太近时往右推开
const BAR_SRC_H := 11             # 进度条源像素高(= 播放头); 槽在第 3~7 行, 菱形在第 2~8 行
const CARD_DELAY := 1.2            # 最后一击落地后再出收尾卡(真实秒)

## 素材(1 倍源图, PixelKey ×3)。
const KEY_NEUTRAL := "res://assets/sprites/ui/replay_bar/key-neutral.png"
const KEY_NEUTRAL_DOWN := "res://assets/sprites/ui/replay_bar/key-neutral-down.png"
const KEY_RED := "res://assets/sprites/ui/replay_bar/key-red.png"
const KEY_RED_DOWN := "res://assets/sprites/ui/replay_bar/key-red-down.png"
const ICON_PAUSE := "res://assets/sprites/ui/replay_bar/icon-pause.png"
const ICON_PLAY := "res://assets/sprites/ui/replay_bar/icon-play.png"
const ICON_EXIT := "res://assets/sprites/ui/replay_bar/icon-exit.png"
const ICON_SPEED := {1: "res://assets/sprites/ui/replay_bar/icon-x1.png", 2: "res://assets/sprites/ui/replay_bar/icon-x2.png",
	4: "res://assets/sprites/ui/replay_bar/icon-x4.png"}
const GROOVE := "res://assets/sprites/ui/replay_bar/groove.png"
const FILL := "res://assets/sprites/ui/replay_bar/fill.png"
const MARK_REACHED := "res://assets/sprites/ui/replay_bar/mark-reached.png"
const MARK_NEXT := "res://assets/sprites/ui/replay_bar/mark-next.png"
const PLAYHEAD := "res://assets/sprites/ui/replay_bar/playhead.png"

## 退出确认框的字
const TXT_ASK_REPLAY := "退出回放？"
const TXT_ASK_WATCH := "退出观看？"
const TXT_ASK_STAY := "继续观看"
const TXT_ASK_LEAVE := "退出"

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
const N_MARK := "ReplayMark_"           # + 下标: 每一路开打处的菱形
const N_TRACK := "ReplayTrack"           # 进度槽(状态流回放时可拖)
const N_FILL := "ReplayFill"
const N_HEAD := "ReplayHead"
const N_EXIT_ASK := "ReplayExitAsk"      # 退出确认框(整屏暗幕)
const N_EXIT_YES := "ReplayExitYes"
const N_EXIT_NO := "ReplayExitNo"
const N_LIVE_EXIT := "LiveExit"          # 观赛: 左下角「退出」
const N_LIVE_STATUS := "LiveStatus"      # 观赛: 底部状态(同步中 / 下路准备中)
const N_LIVE_SHADE := "LiveSyncShade"    # 观赛: 追帧时盖住战场的暗幕(追帧一帧 8 步, 幕布 / 演出叠成一团, 不给人看)

var battle
var root: Control = null           # 全屏、不吃点击; battle_hud._replay_bar 指向它
var strip: Control = null          # 底部这一带(没有底板): 退出键 · 进度条 · 时间 · 暂停 · 倍速
var pause_btn: Button = null
var speed_btn: Button = null
var exit_btn: Button = null
var time_lb: Label = null
var tick_lbs: Array = []
var paused_tag: Control = null
var card: Control = null
var exit_ask: Control = null
var _track: Control = null
var _fill: TextureRect = null
var _head: TextureRect = null
var _marks: Array = []             # [TextureRect, 那一路开打的步号]
var _names: Dictionary = {}
var live_exit: Button = null
var live_status: PanelContainer = null
var live_shade: ColorRect = null
var _live_lb: Label = null
## 状态流回放: 进度条正在被拖(松手才跳), 拖到的横坐标(_track 里)
var _drag := false
var _drag_x := 0.0


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
	var _stream: bool = str(battle._replay.mode) == "stream"   # 逐帧直播播放端(StreamPlayer): 回放有操作条(拖动 = seek), 观赛只有「退出」; 都没有「再看一遍」
	_names = StreamHud.side_names() if _stream else ReplayRecorder.side_names(battle._replay.rec, ReplayRecorder.viewer_name)
	## 对阵图那一场: 认不出谁是录像方(对手快照的名字对不上这一场的两个人)时, 收尾卡至少按对阵图上的顺序写出两个人。
	var pair = ReplayRecorder.play_names.get("pair", [])
	if str(_names.get("l", "")) == "" and str(_names.get("r", "")) == "" and pair is Array and (pair as Array).size() == 2:
		_names = {"l": str(pair[0]), "r": str(pair[1])}
	if _stream and not _stream_ctl():
		_build_stream_exit(vp, m)
	elif _stream:
		_build_strip(vp, m)            # 起播倍速由入口挂进 pending(StreamWatch.enter: 沿用上一次选的), 这里不改 —— 建条比播放晚一帧, 改了会盖掉已经在播的倍速
		_build_paused_tag(vp)
	elif battle._replay.is_live():
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

## [退出]  ━━━◆━━━━▮━━━━━◇━━━━  0:09 / 0:37  [暂停][x1]  (法术圆盘)
##         上路战场      下路战场
## 没有底板: 每一件自带深色描边, 下面透出战场。`ReplayStrip` 只是一个不吃点击的容器(装备说明小卡按它的上沿让位)。
func _build_strip(vp: Vector2, m: Vector4) -> void:
	var key := PixelKey.KEY_PX
	var y_key: float = vp.y - m.w - key
	var top: float = y_key - 6.0
	var right: float = vp.x - m.z - SpellDisc.R * 2.0 - DISC_GAP      # 法术圆盘左缘再空 DISC_GAP(battle_hud._build_spell_disc 同一个公式)
	strip = Control.new()
	strip.name = "ReplayStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 只有键与进度槽吃点击, 别处点穿到战场
	strip.position = Vector2(m.x, top)
	strip.size = Vector2(right - m.x, vp.y - m.w - top)
	root.add_child(strip)
	exit_btn = _key(N_EXIT, KEY_RED, KEY_RED_DOWN, ICON_EXIT)
	exit_btn.position = Vector2(0.0, y_key - top)
	exit_btn.pressed.connect(_ask_exit)
	strip.add_child(exit_btn)
	speed_btn = _key(N_SPEED, KEY_NEUTRAL, KEY_NEUTRAL_DOWN, str(ICON_SPEED[1]))
	speed_btn.position = Vector2(strip.size.x - key, y_key - top)
	speed_btn.pressed.connect(cycle_speed)
	strip.add_child(speed_btn)
	pause_btn = _key(N_PAUSE, KEY_NEUTRAL, KEY_NEUTRAL_DOWN, ICON_PAUSE)
	pause_btn.position = Vector2(speed_btn.position.x - KEY_GAP - key, y_key - top)
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	sc.events = [ev]
	pause_btn.shortcut = sc
	pause_btn.shortcut_in_tooltip = false
	pause_btn.pressed.connect(toggle_pause)
	strip.add_child(pause_btn)
	## 时间: m6x11 32 号(原生 16 号 ×2), 右对齐贴在暂停键左边, 竖向对齐进度槽中线
	time_lb = _lbl("0:00 / 0:00", 32, COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	time_lb.name = N_TIME
	time_lb.add_theme_color_override("font_outline_color", COL_INK)
	time_lb.add_theme_constant_override("outline_size", 8)
	strip.add_child(time_lb)                                  # 先进树再量(没进树时量出来的高是 0, §8-3)
	var tf := time_lb.get_theme_font("font")
	var tfs := time_lb.get_theme_font_size("font_size")
	var tw: float = tf.get_string_size("00:00 / 00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 8.0
	var th: float = tf.get_height(tfs)
	time_lb.size = Vector2(tw, th)
	var groove_mid: float = 3.0 * PixelKey.SCALE + 2.5 * PixelKey.SCALE      # 槽在进度条第 3~7 行 ⇒ 中线 = 5.5 行
	time_lb.position = Vector2(pause_btn.position.x - 24.0 - tw, roundf(groove_mid - th / 2.0))
	## 进度条: 宽取 3 的倍数(素材 ×3, 端头不落半格)
	_track = Control.new()
	_track.name = N_TRACK
	var x0: float = key + BAR_GAP
	var w: float = floorf((time_lb.position.x + tw - _time_ink_w() - BAR_GAP - x0) / float(PixelKey.SCALE)) * float(PixelKey.SCALE)
	_track.position = Vector2(x0, 0.0)
	_track.size = Vector2(maxf(60.0, w), float(BAR_SRC_H * PixelKey.SCALE))
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _stream_ctl():
		_track.mouse_filter = Control.MOUSE_FILTER_STOP          # 状态流回放: 进度条可拖(重算回放不行: 只能从第 0 步往前算)
		_track.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_track.gui_input.connect(_on_track_input)
	strip.add_child(_track)
	_layout_track()


## 时间那一串字实际墨迹的宽(右对齐: 标签框左边留的空白不算进进度条与时间之间的距离)。
func _time_ink_w() -> float:
	if time_lb == null:
		return 0.0
	return time_lb.get_theme_font("font").get_string_size("0:00 / 0:00", HORIZONTAL_ALIGNMENT_LEFT, -1,
		time_lb.get_theme_font_size("font_size")).x


func _layout_track() -> void:
	if _track == null or not is_instance_valid(_track):
		return
	for c in _track.get_children():
		_track.remove_child(c)       # 先摘下再释放: 新建的路名才拿得到原名(门禁按名字找)
		c.queue_free()
	tick_lbs.clear()
	_marks.clear()
	var s := PixelKey.SCALE
	var w := _track.size.x
	## 槽: 九宫格(左右端头各 1 源像素不拉伸), 在第 3~7 行
	var gv := NinePatchRect.new()
	gv.texture = PixelKey.up(GROOVE)
	gv.patch_margin_left = s
	gv.patch_margin_right = s
	gv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gv.position = Vector2(0.0, 3.0 * s)
	gv.size = Vector2(w, 5.0 * s)
	gv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(gv)
	## 已播: 1×3 的金色三层, 横向拉伸, 叠在槽的 1~3 行
	_fill = PixelKey.sprite(FILL)
	_fill.name = N_FILL
	_fill.position = Vector2(float(s), 4.0 * s)
	_fill.size = Vector2(0.0, 3.0 * s)
	_track.add_child(_fill)
	var tot := float(maxi(1, battle._replay.total_steps()))
	var fs: Array = battle._replay.fight_steps()
	var prev_x := -INF
	for i in range(fs.size()):
		var x: float = _bar_x(clampf(float(fs[i]) / tot, 0.0, 1.0))
		var mk := PixelKey.sprite(MARK_NEXT)
		mk.name = N_MARK + str(i)
		mk.position = Vector2(x - 3.0 * s, 2.0 * s)
		_track.add_child(mk)
		_marks.append([mk, int(fs[i])])
		if i >= TICK_NAMES.size():
			continue
		## 路名: 以菱形为中心; 挨得太近就往右推开一个字宽, 两端不出槽。
		var cx: float = x + s * 0.5
		var lx: float = maxf(cx - TICK_LW * 0.5, prev_x + TICK_LW)
		lx = clampf(lx, 0.0, maxf(0.0, w - TICK_LW))
		prev_x = lx
		var lb := _lbl(str(TICK_NAMES[i]), 20, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER)
		lb.name = N_TICK_LBL + str(i)
		lb.add_theme_color_override("font_outline_color", COL_INK)
		lb.add_theme_constant_override("outline_size", 8)
		lb.position = Vector2(lx, float(BAR_SRC_H * s) + 2.0)
		lb.size = Vector2(TICK_LW, 26)
		_track.add_child(lb)
		tick_lbs.append(lb)
	_head = PixelKey.sprite(PLAYHEAD)
	_head.name = N_HEAD
	_head.position = Vector2(_bar_x(0.0) - 2.0 * s, 0.0)
	_track.add_child(_head)
	refresh()


## 进度 f(0..1)落在进度条的哪一列(左缘像素, 3 的倍数): 槽两端各 1 源像素是端头。
func _bar_x(f: float) -> float:
	var s := float(PixelKey.SCALE)
	var cols: float = maxf(1.0, _track.size.x / s - 2.0)
	return s * (1.0 + roundf(cols * clampf(f, 0.0, 1.0)))


## 一颗像素图标键(看起来 60, 可点 84)。暂停时也要能按 ⇒ PROCESS_MODE_ALWAYS。
func _key(nm: String, up: String, down: String, icon: String) -> Button:
	var b := PixelKey.icon_key(nm, up, down, icon)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b


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
	live_exit = _key(N_LIVE_EXIT, KEY_RED, KEY_RED_DOWN, ICON_EXIT)
	live_exit.position = Vector2(m.x, vp.y - m.w - PixelKey.KEY_PX)
	live_exit.pressed.connect(_ask_exit)
	root.add_child(live_exit)
	live_status = PanelContainer.new()
	live_status.name = N_LIVE_STATUS
	live_status.add_theme_stylebox_override("panel", _frame(26, 10))
	live_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_lb = _lbl("", 24, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	live_status.add_child(_live_lb)
	live_status.visible = false
	root.add_child(live_status)


## 逐帧直播播放端: 只有左下角一颗「退出」(与观赛那颗同位置同样子); 确认后与回放退出相同(`_replay_exit`)。
func _build_stream_exit(vp: Vector2, m: Vector4) -> void:
	exit_btn = _key(N_EXIT, KEY_RED, KEY_RED_DOWN, ICON_EXIT)
	exit_btn.position = Vector2(m.x, vp.y - m.w - PixelKey.KEY_PX)
	exit_btn.pressed.connect(_ask_exit)
	root.add_child(exit_btn)


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


## 暂停时屏幕中间「已暂停」: 像素标题字 48 号 + 描边(没有底板, 不再借结算屏的金属框)。
func _build_paused_tag(vp: Vector2) -> void:
	var lb := _lbl("已暂停", 48, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	lb.name = N_PAUSED
	UISkin.title_label(lb, 48)
	lb.add_theme_color_override("font_outline_color", COL_INK)
	lb.add_theme_constant_override("outline_size", 16)       # §4.1-5: 描边 = 字号 ÷ 3 ⇒ 每边一个源像素
	lb.visible = false
	lb.size = Vector2(vp.x, 64.0)
	lb.position = Vector2(0.0, roundf(vp.y * 0.5 - 40.0))
	root.add_child(lb)
	paused_tag = lb


# ─────────────────────────────── 退出确认 ───────────────────────────────

## 点退出键: 先问一句(键小、贴着屏幕边, 误触一下整场回放就没了)。收尾卡已经出来了 ⇒ 卡上有「返回」, 不用再问。
func _ask_exit() -> void:
	if exit_ask != null and is_instance_valid(exit_ask):
		return
	var dim := ColorRect.new()
	dim.name = N_EXIT_ASK
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(dim)
	exit_ask = dim
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", SettleScreenS.frame_style())
	pc.custom_minimum_size = Vector2(440, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	var watching: bool = battle._replay.is_live() or (str(battle._replay.mode) == "stream" and not _stream_ctl())
	var tl := _lbl(TXT_ASK_WATCH if watching else TXT_ASK_REPLAY, 24, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	UISkin.title_label(tl, 24)                                # 弹框标题 24 号(§4.1)
	vb.add_child(tl)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var stay := _btn(TXT_ASK_STAY, 160.0)
	stay.name = N_EXIT_NO
	stay.pressed.connect(_close_ask)
	hb.add_child(stay)
	var leave := _btn(TXT_ASK_LEAVE, 160.0)
	leave.name = N_EXIT_YES
	leave.pressed.connect(battle._hud._replay_exit)
	hb.add_child(leave)


func _close_ask() -> void:
	if exit_ask != null and is_instance_valid(exit_ask):
		exit_ask.queue_free()
	exit_ask = null


# ─────────────────────────────── 操作 ───────────────────────────────

## 状态流回放(有操作条)吗。观赛 / 普通重算回放 ⇒ false。
func _stream_ctl() -> bool:
	var rp = battle._replay
	return rp != null and str(rp.mode) == "stream" and rp.player != null and bool(rp.player.controls)


## 暂停 / 倍速作用在谁身上: 状态流 ⇒ 播放器; 重算回放 ⇒ ReplayRecorder(它们的 paused / speed 同名同义)。
func _clock_owner():
	return battle._replay.player if _stream_ctl() else battle._replay


func toggle_pause() -> void:
	if _stream_ctl():
		var st := str(battle._replay.player.state)
		if st == "ended" or st == "error":
			return
	elif battle._replay.finished or battle._replay.diverged_at >= 0:
		return
	var o = _clock_owner()
	o.paused = not o.paused
	refresh()


func cycle_speed() -> void:
	battle._replay.cycle_speed()
	if _stream_ctl():
		battle._replay.player.speed = float(battle._replay.speed)
	refresh()


## 状态流回放: 跳到全场的 f(0..1)处。返回播放器 seek 的结果。
func seek_frac(f: float) -> bool:
	if not _stream_ctl():
		return false
	var tot: int = battle._replay.total_steps()
	if tot <= 0:
		return false
	var ok: bool = battle._replay.player.seek(int(roundf(clampf(f, 0.0, 1.0) * float(tot))))
	refresh()
	return ok


## 进度槽上的按下 / 拖 / 松手(触屏由引擎转成鼠标事件)。拖的时候只挪金色填充, 松手才跳(跳一次要从 keyframe 解)。
func _on_track_input(ev: InputEvent) -> void:
	if card != null or _track == null:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		_drag_x = mb.position.x
		if mb.pressed:
			_drag = true
		elif _drag:
			_drag = false
			seek_frac(_drag_x / maxf(1.0, _track.size.x))
		refresh()
	elif ev is InputEventMouseMotion and _drag:
		_drag_x = (ev as InputEventMouseMotion).position.x
		refresh()


static func clock(steps: int) -> String:
	var sec := maxi(0, int(floor(float(steps) / 60.0)))
	return "%d:%02d" % [sec / 60, sec % 60]


## 每 0.1 秒刷一次(暂停时也刷: 时钟由 Timer 驱动, 不挂在 sim 步上)。
func refresh() -> void:
	if root == null or not is_instance_valid(root):
		return
	var rp = battle._replay
	var sctl := _stream_ctl()
	if str(rp.mode) == "stream" and not sctl:
		return
	if rp.is_live():
		_sync_live()
		return
	var o = _clock_owner()
	if pause_btn != null:
		var want: String = ICON_PLAY if o.paused else ICON_PAUSE      # 暂停着 ⇒ 键上画「播放」(按下去接着播)
		if PixelKey.icon_of(pause_btn) != want.get_file().trim_prefix("icon-").trim_suffix(".png"):
			PixelKey.set_icon(pause_btn, want)
	if speed_btn != null:
		var sp: String = str(ICON_SPEED.get(int(rp.speed), ICON_SPEED[1]))
		if PixelKey.icon_of(speed_btn) != sp.get_file().trim_prefix("icon-").trim_suffix(".png"):
			PixelKey.set_icon(speed_btn, sp)
	if paused_tag != null:
		paused_tag.visible = o.paused and card == null
	var tot: int = rp.total_steps()
	var now_step: int = maxi(0, int(rp.player.applied)) if sctl else int(battle._sim_step_n)
	if sctl and _drag and _track != null and tot > 0:
		now_step = int(roundf(clampf(_drag_x / maxf(1.0, _track.size.x), 0.0, 1.0) * float(tot)))
	var cur: int = mini(now_step, tot) if tot > 0 else now_step
	if time_lb != null:
		time_lb.text = "%s / %s" % [clock(cur), clock(tot)] if tot > 0 else clock(cur)
	if _fill != null and is_instance_valid(_fill) and _track != null and tot > 0:
		var fx: float = _bar_x(float(cur) / float(tot))
		_fill.size.x = maxf(0.0, fx - _fill.position.x)
		if _head != null and is_instance_valid(_head):
			_head.position.x = fx - 2.0 * PixelKey.SCALE
	## 路分界菱形: 播到了那一路 ⇒ 奶白, 还没到 ⇒ 钢蓝
	for mk in _marks:
		var tr = mk[0]
		if tr == null or not is_instance_valid(tr):
			continue
		var want_tex: String = MARK_REACHED if cur >= int(mk[1]) else MARK_NEXT
		if (tr as TextureRect).texture == null or (tr as TextureRect).texture.resource_path != want_tex:
			(tr as TextureRect).texture = load(want_tex)
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
	_close_ask()                           # 收尾卡上有「返回」, 退出确认框不再留着
	if battle._dmg_stats != null and battle._dmg_stats.panel != null and is_instance_valid(battle._dmg_stats.panel):
		battle._dmg_stats.panel.visible = false
	if live_exit != null:
		live_exit.visible = false          # 收尾卡上有「返回」, 左下角那颗不再留着
	var stream: bool = str(battle._replay.mode) == "stream"
	if stream and exit_btn != null:
		exit_btn.visible = false
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
	## 固定文案(胜利 / 失败 / 回放中断 / 直播中断)用像素标题字 48 号; 「<昵称> 获胜」是玩家输入的字, 照旧正文字体 44 号
	##   (docs/plans/20261027-UI美术规矩.md §4.1 硬规矩 2)。判据与 ReplayRecorder.end_caption 同一条: 有没有拿到名字。
	var nick_title: bool = not broken and str(ReplayRecorder.play_names.get("l" if won else "r", "")) != ""
	if not nick_title:
		UISkin.title_label(tl, 48)
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
		if tot > 0 and lv == null and (not stream or _stream_ctl()):       # 观赛不报全场时长(状态流只有回放报)
			sub += ("  ·  " if sub != "" else "") + "全场 " + clock(tot)
	if sub != "":
		vb.add_child(_lbl(sub, 20, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	if not broken and lv == null and not stream:          # 「再看一遍」只有回放有(状态流没有输入录像, 再看一遍会变成本机重算)
		var ag := Button.new()
		ag.name = N_AGAIN
		ag.text = "再看一遍"
		SettleScreenS.dress_btn(ag, Color("#ffe7a0"))
		ag.pressed.connect(func() -> void: ReplayRecorder.play_again(battle.get_tree(), battle._replay.rec))
		hb.add_child(ag)
	var bk := Button.new()
	bk.name = N_BACK
	bk.text = back_label()
	SettleScreenS.dress_btn(bk, Color("#e8f0f6"))
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


## 退出确认框里的按钮: 属于弹框 ⇒ `UISkin.card_button`(与商店「购买」同一种; 用户 10-22 定, 不用木牌)。
func _btn(t: String, w: float) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.add_theme_font_size_override("font_size", 22)
	UISkin.card_button(b)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, COL_TEXT)
	return b


## 与结算屏同一个小工具(不抄一份: dup_primitive 棘轮按函数体哈希抓副本)。
static func _lbl(t: String, fs: int, c: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return SettleScreenS._lbl(t, fs, c, align)
