class_name QueueFoundOverlay
extends CanvasLayer
## 闯关赛「匹配成功 · 即将进入对局」全屏遮罩(2026-10-29 · 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.1-5 / U5 · A9)。
##
## 排队中回了主页、在别的页面(主页 / 图鉴 / 排行榜 / 好友 / 战绩页回放 / 赛况板观战……)时配上 ⇒ 会话
##   (`referee_run.gd` `_found`)调 `show_then(tree, then)`: 盖住一切约 HOLD_SEC 秒 + 一声短音效, 然后调 `then`(换到匹配屏的 VS 卡)
##   并淡出自删。**没有接受键**(Valorant 式): 配上那一刻服务端已经建好任务, 拒绝不了(方案书 §2.13 共同做法 4)。
## 用户 10-29「全部今天做完」认可 U5 / U6(正在看回放或观战也直接带走)。
##
## ★样子按 docs/plans/20261027-UI美术规矩.md: 标题有底板(横贯全屏的深色横带 + 上下金线, 不借别屏的缎带图) /
##   标题字 72 号(12 的倍数)、描边 24(= 字号 ÷ 3)、落影 6 / 一屏一件事(只说「匹配成功」与下一步) /
##   标题从左侧滑入(T_BASE · BACK 缓出), 不缩放弹入 / 横带下一条进度条随时间走满 = 「马上就进」, 不用倒数字。
##   全部是代码画的色块与字, 不用任何贴图 ⇒ 没有借用素材。
## ★计时走墙钟(`Time.get_ticks_msec`), 不走 delta: 回放 / 观战可能改了 `Engine.time_scale`, 也可能把场景树停了
##   (process_mode = ALWAYS 只保证它会跑, 不保证 delta 是真时间)。
## ★挂在 root 上、layer 高于各屏 HUD(工作室开场 StudioIntro 9000 之下 —— 开场只在冷启动, 那时不可能有排队)。
##   吞掉所有点击: 1.5 秒里点到下面那一屏的按钮会把人带去别处。
## 音效: assets/audio/sfx/queue_found.wav(tools/build_queue_found_sfx.py 合成, 确定性)。

const NODE := "QueueFoundOverlay"
const LAYER := 8800
const HOLD_SEC := 1.5            ## 盖多久再调 then(秒, 墙钟)
const FADE_SEC := 0.25           ## 调完 then 之后淡出(新场景在这段里接上, 不闪旧屏)
const SFX := "res://assets/audio/sfx/queue_found.wav"
const TXT_TITLE := "匹配成功"
const TXT_SUB := "即将进入对局"

const BAND_H := 236.0
const BAR_W := 420.0
const BAR_H := 12.0
const COL_DIM := Color(0.02, 0.03, 0.06, 0.72)
const COL_BAND := Color("#0f1a33")
const COL_BAND_IN := Color("#16244a")
const COL_GOLD := Color("#e8b84a")
const COL_GOLD_SH := Color("#7a4a12")
const COL_TITLE := Color("#fff6dc")
const COL_INK := Color("#0c1220")
const COL_SUB := Color("#c9d6e4")
const COL_BAR_BG := Color("#070b16")
const COL_BAR := Color("#ffd34a")

## 门禁读: 这一层调过几次 then(应恰好 1)。
var calls := 0
var _thens: Array = []
var _t0 := 0
var _done := false
var _root: Control = null
var _band: Control = null
var _title: Label = null
var _sub: Label = null
var _fill: ColorRect = null
var _sfx: AudioStreamPlayer = null


## 会话配上时调: 盖一层, 约 HOLD_SEC 秒后调 `then`。已经盖着一层(同一帧配上两次之类)⇒ 不叠第二层, 回调挂到那一层上。
static func show_then(tree: SceneTree, then: Callable) -> void:
	if tree == null or tree.root == null:
		if then.is_valid():
			then.call()
		return
	var old := tree.root.get_node_or_null(NODE) as QueueFoundOverlay
	if old != null and not old._done and not old.is_queued_for_deletion():
		old._thens.append(then)
		return
	var ov := QueueFoundOverlay.new()
	ov.name = NODE
	ov.layer = LAYER
	ov.process_mode = Node.PROCESS_MODE_ALWAYS
	ov._thens.append(then)
	## 延后一拍挂: 调用方可能正在某个场景的 _ready / 信号回调里, root 那一刻不收孩子。
	tree.root.add_child.call_deferred(ov)


## 从盖上到现在过了多少秒(墙钟)。
func elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = COL_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_build_band()
	_layout()
	get_viewport().size_changed.connect(_layout)
	if ResourceLoader.exists(SFX) and not Audio.mute_sfx:
		_sfx = AudioStreamPlayer.new()
		_sfx.name = "Sfx"
		_sfx.stream = load(SFX)
		_sfx.volume_db = linear_to_db(maxf(0.0001, Audio.sfx_volume))
		add_child(_sfx)
		_sfx.play()
	## 入场: 横带竖向展开(T_BASE), 标题从左滑入(T_BASE · BACK 缓出), 副标与进度条随后淡入。
	_band.scale = Vector2(1.0, 0.0)
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_band, "scale", Vector2.ONE, UIPalette.T_BASE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var home: float = _title.position.x
	_title.position.x = home - 160.0
	tw.tween_property(_title, "position:x", home, UIPalette.T_BASE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_title, "modulate:a", 1.0, UIPalette.T_TAP)
	tw.tween_property(_sub, "modulate:a", 1.0, UIPalette.T_BASE)


## 横贯全屏的横带: 深底 + 上下各一道金线(下面压一道暗线, 像素台阶)+ 标题 + 副标 + 进度条。
func _build_band() -> void:
	_band = Control.new()
	_band.name = "Band"
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_band)
	for spec in [["Body", COL_BAND], ["Inner", COL_BAND_IN], ["GoldTop", COL_GOLD], ["GoldTopSh", COL_GOLD_SH],
			["GoldBot", COL_GOLD], ["GoldBotSh", COL_GOLD_SH]]:
		var r := ColorRect.new()
		r.name = str(spec[0])
		r.color = spec[1]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band.add_child(r)
	_title = Label.new()
	_title.name = "Title"
	_title.text = TXT_TITLE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UISkin.title_label(_title, 72)
	_title.add_theme_color_override("font_color", COL_TITLE)
	_title.add_theme_color_override("font_outline_color", COL_INK)
	_title.add_theme_constant_override("outline_size", 24)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.add_theme_constant_override("shadow_outline_size", 24)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(_title)
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.text = TXT_SUB
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 26)
	_sub.add_theme_color_override("font_color", COL_SUB)
	_sub.add_theme_color_override("font_outline_color", COL_INK)
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(_sub)
	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBg"
	bar_bg.color = COL_BAR_BG
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(bar_bg)
	_fill = ColorRect.new()
	_fill.name = "BarFill"
	_fill.color = COL_BAR
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(_fill)


## 按视口摆位(任何比例都横贯全宽、竖向居中)。
func _layout() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	_band.position = Vector2(0.0, roundf((vs.y - BAND_H) / 2.0))
	_band.size = Vector2(vs.x, BAND_H)
	_band.pivot_offset = Vector2(vs.x / 2.0, BAND_H / 2.0)
	var w := vs.x
	_rect("Body", Rect2(0, 0, w, BAND_H))
	_rect("Inner", Rect2(0, 12, w, BAND_H - 24))
	_rect("GoldTop", Rect2(0, 0, w, 6))
	_rect("GoldTopSh", Rect2(0, 6, w, 3))
	_rect("GoldBot", Rect2(0, BAND_H - 6, w, 6))
	_rect("GoldBotSh", Rect2(0, BAND_H - 9, w, 3))
	_title.position = Vector2(0.0, 30.0)
	_title.size = Vector2(w, 96.0)
	_sub.position = Vector2(0.0, 130.0)
	_sub.size = Vector2(w, 40.0)
	var bx := roundf((w - BAR_W) / 2.0)
	_rect("BarBg", Rect2(bx - 3, 186.0 - 3, BAR_W + 6, BAR_H + 6))
	_fill.position = Vector2(bx, 186.0)
	_fill.size = Vector2(BAR_W * clampf(elapsed() / HOLD_SEC, 0.0, 1.0), BAR_H)


func _rect(n: String, r: Rect2) -> void:
	var c := _band.get_node_or_null(n) as Control
	if c != null:
		c.position = r.position
		c.size = r.size


func _process(_delta: float) -> void:
	var e := elapsed()
	if _fill != null:
		## 进度条按 3 像素一格走(像素台阶, 不是平滑拉长)
		_fill.size.x = floorf(BAR_W * clampf(e / HOLD_SEC, 0.0, 1.0) / 3.0) * 3.0
	if _done or e < HOLD_SEC:
		return
	_done = true
	var cbs := _thens.duplicate()
	_thens.clear()
	for cb in cbs:
		if (cb as Callable).is_valid():
			calls += 1
			(cb as Callable).call()
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	tw.tween_callback(queue_free)
