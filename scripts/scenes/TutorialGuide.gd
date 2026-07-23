extends Node

const STEPS_PATH := "res://data/tutorial-steps.json"
## TutorialGuide — 新手教程步骤引导 (1:1 PoC src/scenes/TutorialGuide.ts)。
## 顶部/底部非阻挡横幅: 序号徽章 + 提示文 + 下一步/知道了/完成 + 跳过。玩家照提示在真实战斗里操作,
## advanceOn 事件由 BattleScene 在对应动作发生时 notify → 自动推进。
## 用法: var g = preload(".../TutorialGuide.gd").new(); add_child(g); g.start(steps, on_done)
##   steps = [{ "text": String, "advanceOn"?: String, "anchor"?: "top"|"bottom" }]

var _steps: Array = []
var _idx: int = 0
var _on_done: Callable
var _layer: CanvasLayer
var _panel: PanelContainer
var _badge: Label
var _text: RichTextLabel
var _btn_row: HBoxContainer
# ── 高亮遮罩(手把手指引): 四块暗幕围住目标矩形挖洞 ──
var _mask: Array = []                # 4 个 ColorRect(上/下/左/右), 把非目标区域压暗+挡点击
var _ring: ColorRect                 # 目标矩形的亮边框
var _mandatory: bool = false         # 首次强制: 无"跳过"按钮
var _anchor_fn: Callable             # (name:String)->Rect2 屏幕矩形; 空=不高亮
var _cur_hl: String = ""             # 当前步的高亮锚点名(每帧重贴, 见 _process)


## on_done: 走完/跳过的回调。mandatory: 首次强制(无跳过)。anchor_fn: 把 step.highlight 名字换成屏幕 Rect2。
func start(steps: Array, on_done: Callable, mandatory: bool = false, anchor_fn: Callable = Callable()) -> void:
	_steps = steps
	_on_done = on_done
	_mandatory = mandatory
	_anchor_fn = anchor_fn
	# ★暂停时也要能读引导/点按钮/高亮跟随 → ALWAYS(战斗可暂停; 见 §3.4 process_mode 坑)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_render()


## ★每帧重贴当前步高亮: 控件首帧可能还没布局好(rect 为 0)→挖空洞会退回无高亮;
##   下一帧布局好了自动补上。同时兼顾窗口 resize / 控件移动(如商店换货重排)。
func _process(_dt: float) -> void:
	if _cur_hl != "" and _anchor_fn.is_valid():
		_apply_highlight(_cur_hl)


func notify(event: String) -> void:
	if _idx < _steps.size() and str(_steps[_idx].get("advanceOn", "")) == event:
		_next()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 8000
	add_child(_layer)
	# ★暗幕四块(挖洞高亮)先建 → 在提示条【下方】。默认覆盖全屏(高亮矩形为空时=整幕压暗)。
	#   四块围住目标矩形留出中间的洞 —— 洞内可点(玩家按引导操作), 洞外被暗幕挡住(STOP)。
	#   不用 shader: 四块 ColorRect 拼一个"回字形"最简单也最稳。
	for i in 4:
		var m := ColorRect.new()
		m.color = Color(0, 0, 0, 0.62)
		m.mouse_filter = Control.MOUSE_FILTER_STOP   # 洞外挡点击 = 逼玩家只能点洞里
		_layer.add_child(m)
		_mask.append(m)
	_ring = ColorRect.new()
	_ring.color = Color(1, 0.85, 0.25, 0.0)          # 透明填充; 只画边框(用 _draw 覆盖)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_script(preload("res://scripts/scenes/tutorial_ring.gd"))
	_layer.add_child(_ring)
	_set_mask_visible(false)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.110, 0.204, 0.96)   # rgba(18,28,52,.96)
	sb.set_border_width_all(2); sb.border_color = Color("#ffd93d")
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.55)   # PoC box-shadow 0 6px 30px rgba(0,0,0,.55)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	# 行: 徽章 + 文字
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 13)
	_badge.add_theme_color_override("font_color", Color("#3a1f00"))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#ffd93d")
	bsb.set_corner_radius_all(6)
	bsb.content_margin_left = 9; bsb.content_margin_right = 9
	bsb.content_margin_top = 2; bsb.content_margin_bottom = 2
	_badge.add_theme_stylebox_override("normal", bsb)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	_text.add_theme_color_override("default_color", Color("#eaf0fa"))
	row.add_child(_text)
	# 按钮行
	_btn_row = HBoxContainer.new()
	_btn_row.alignment = BoxContainer.ALIGNMENT_END
	_btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(_btn_row)


func _render() -> void:
	if _idx >= _steps.size():
		return
	var step: Dictionary = _steps[_idx]
	# 锚点: top → 顶部 14; bottom → 底部 120
	var anchor := str(step.get("anchor", "top"))
	if anchor == "bottom":
		_panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
		_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_panel.offset_top = -120.0 - 80.0; _panel.offset_bottom = -120.0
	else:
		_panel.anchor_top = 0.0; _panel.anchor_bottom = 0.0
		_panel.grow_vertical = Control.GROW_DIRECTION_END
		_panel.offset_top = 14.0; _panel.offset_bottom = 14.0 + 80.0
	_badge.text = "%d/%d" % [_idx + 1, _steps.size()]
	_text.text = _html_b_to_bbcode(str(step.get("text", "")))
	# ★高亮遮罩: 这一步指定了 highlight 目标 → 挖洞压暗其余; 没指定 → 无遮罩(纯提示条)
	#   _cur_hl 记住当前锚点名, _process 每帧重贴(布局时序/resize 稳)。
	_cur_hl = str(step.get("highlight", ""))
	_apply_highlight(_cur_hl)
	# 重建按钮
	for c in _btn_row.get_children():
		c.queue_free()
	var is_last := _idx == _steps.size() - 1
	# ★首次强制(mandatory)时不给"跳过"; ❓ 重玩(非 mandatory)才有
	if not is_last and not _mandatory:
		var skip := Button.new()
		skip.text = "跳过教程"
		skip.add_theme_font_size_override("font_size", 14)
		skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		skip.pressed.connect(_finish)
		_btn_row.add_child(skip)
	var nxt := Button.new()
	nxt.text = "完成 ✓" if is_last else ("知道了" if step.has("advanceOn") else "下一步 ▶")
	nxt.add_theme_font_size_override("font_size", 14)
	nxt.add_theme_color_override("font_color", Color("#3a1f00"))
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color("#ffc23c")
	nsb.set_corner_radius_all(7)
	nsb.content_margin_left = 18; nsb.content_margin_right = 18
	nsb.content_margin_top = 7; nsb.content_margin_bottom = 7
	nxt.add_theme_stylebox_override("normal", nsb)
	nxt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	nxt.pressed.connect(_next)
	_btn_row.add_child(nxt)


## 挖洞高亮: 把 highlight 名字换成屏幕矩形, 四块暗幕围住它。空名字 = 无高亮(纯提示条)。
func _apply_highlight(hl_name: String) -> void:
	if hl_name == "" or not _anchor_fn.is_valid():
		_set_mask_visible(false)
		return
	var rect: Rect2 = _anchor_fn.call(hl_name)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		# 锚点解析失败(控件还没布局好/名字错) → 别挖个空洞把全屏挡死, 退回无高亮
		push_warning("[Tutorial] 高亮锚点 '%s' 解析出空矩形 → 本步不挖洞" % hl_name)
		_set_mask_visible(false)
		return
	var pad := 8.0
	rect = rect.grow(pad)
	var vp: Vector2 = Vector2(_layer.get_viewport().get_visible_rect().size)
	# 四块: 上/下/左/右, 拼成"回"字, 中间留 rect 这个洞
	_mask[0].position = Vector2(0, 0);                    _mask[0].size = Vector2(vp.x, rect.position.y)                       # 上
	_mask[1].position = Vector2(0, rect.end.y);           _mask[1].size = Vector2(vp.x, vp.y - rect.end.y)                     # 下
	_mask[2].position = Vector2(0, rect.position.y);      _mask[2].size = Vector2(rect.position.x, rect.size.y)                # 左
	_mask[3].position = Vector2(rect.end.x, rect.position.y); _mask[3].size = Vector2(vp.x - rect.end.x, rect.size.y)          # 右
	_ring.position = rect.position
	_ring.size = rect.size
	_ring.queue_redraw()
	_set_mask_visible(true)


func _set_mask_visible(on: bool) -> void:
	for m in _mask:
		m.visible = on
	if _ring != null:
		_ring.visible = on


func _next() -> void:
	_idx += 1
	if _idx >= _steps.size():
		_finish()
		return
	_render()


func _finish() -> void:
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


# <b>...</b> → [b]...[/b] (PoC 教程文用 HTML 粗体)
func _html_b_to_bbcode(s: String) -> String:
	return s.replace("<b>", "[b]").replace("</b>", "[/b]")

## 从 data/tutorial-steps.json 取某个场景的步骤。
## ★取不到就返回空数组, 调用方据此【不显示引导】而不是崩 —— 引导缺失不该让游戏挂掉。
static func steps_for(key: String) -> Array:
	var raw := FileAccess.get_file_as_string(STEPS_PATH)
	if raw == "":
		push_warning("[TutorialGuide] 读不到 %s" % STEPS_PATH)
		return []
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("[TutorialGuide] %s 不是对象" % STEPS_PATH)
		return []
	var arr = parsed.get(key, [])
	return arr if arr is Array else []


## 一行接入: 有引导步骤才建节点。返回 guide 实例(没有步骤则 null)。
## 调用方拿到实例后可在关键动作处调 guide.notify("事件名") 推进。
## host 可实现 _tutorial_anchor(name)->Rect2 提供高亮锚点; on_done 走完回调。
## mandatory: 首次强制(无跳过)。
static func attach(host: Node, key: String, on_done: Callable = Callable(), mandatory: bool = false) -> Node:
	var steps := steps_for(key)
	if steps.is_empty():
		return null
	var g = load("res://scripts/scenes/TutorialGuide.gd").new()
	host.add_child(g)
	g.add_to_group("tut_overlay")   # ★场景 _rebuild(买装备/装备后重建)要【跳过】本组, 否则引导被 queue_free
	var anchor_fn := Callable()
	if host.has_method("_tutorial_anchor"):
		anchor_fn = Callable(host, "_tutorial_anchor")
	var cb: Callable = on_done if on_done.is_valid() else func() -> void: pass
	g.start(steps, cb, mandatory, anchor_fn)
	return g
