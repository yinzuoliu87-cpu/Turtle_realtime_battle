extends Node

const STEPS_PATH := "res://data/tutorial-steps.json"
## TutorialGuide — 新手教程的一屏引导条。
##
## ══════════════════════════════════════════════════════════════════════
##  2026-10-07 重做(方案书 docs/plans/20261007-新手教程重做.md §4.4)
## ══════════════════════════════════════════════════════════════════════
## 用户「行」认可的方向: 每一步只有**一句短的祈使句**; 高亮目标 + 手势指针;
##   **玩家做了那个动作才前进**; 不要长段阅读, 不要一串「下一步」。
## ⇒ 本条**没有任何按钮**(原来的「下一步 / 知道了 / 完成 / 跳过」全删 —— B2/B3 都是它们造的:
##   不买也能翻页、三格还空着就点「知道了」翻过去)。跳过教程在导演挂的外壳上(tutorial_chrome.gd)。
## ⇒ 每一步都靠 `advanceOn` 事件前进; 事件可「越级」: 玩家做了后面那步的动作,
##   前面没做的步一并算完成(例: 没拖龟直接按开始战斗), 不会卡死。
## ⇒ **等宿主可以引导了才显示**(B6 那一类: 屏有入场动画时, 提示比内容先到):
##   宿主给 ready_fn 就用它; 没给 ⇒ 等本步目标矩形连续 STABLE_FRAMES 帧不动。
##
## steps = [{ "text", "highlight", "advanceOn", "point"?, "hand"?("tap"|"drag"), "anchor"?("top"|"bottom"|"right") }]

const HAND_TEX := "res://assets/sprites/ui/tut-hand.png"
const HAND_SCALE := 3.0
## 指尖在源图里的像素位置(18×19 的手, 食指尖)。
const HAND_TIP := Vector2(6.5, 0.0)
## 目标矩形连续这么多帧位置不变才算「布局/入场动画走完了」。
const STABLE_FRAMES := 4
## 首帧解析出空矩形是正常的(容器还没跑布局) ⇒ 撑过这几帧还空才报一条警告。
const HL_GRACE_FRAMES := 3

var _steps: Array = []
var _idx: int = 0
var _on_done: Callable
var _anchor_fn: Callable             # (name:String)->Rect2 屏幕矩形
var _ready_fn: Callable              # ()->bool 宿主可以引导了吗; 空 = 只看目标矩形稳定
var _layer: CanvasLayer
var _panel: PanelContainer
var _text: Label
var _hand: TextureRect
var _mask: Array = []                # 4 个 ColorRect(上/下/左/右), 洞外压暗 + 挡点击
var _ring: ColorRect
var _cur_hl: String = ""
var _shown: bool = false             # 本步已经显示过(之后不再因目标轻微移动而闪)
var _stable_n: int = 0
var _last_rect := Rect2()
var _t: float = 0.0
var _hl_empty_frames: int = 0
var _hl_warned: bool = false


func start(steps: Array, on_done: Callable, anchor_fn: Callable = Callable(), ready_fn: Callable = Callable()) -> void:
	_steps = steps
	_on_done = on_done
	_anchor_fn = anchor_fn
	_ready_fn = ready_fn
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_render()


## 是否正显示在屏上(门禁量「演出期间不出提示」用的就是这个)。
func is_showing() -> bool:
	return _layer != null and _layer.visible


func current_text() -> String:
	return _text.text if _text != null else ""


func notify(event: String) -> void:
	for j in range(_idx, _steps.size()):
		if str((_steps[j] as Dictionary).get("advanceOn", "")) == event:
			_idx = j + 1
			if _idx >= _steps.size():
				_finish()
			else:
				_render()
			return


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 8000
	_layer.visible = false
	add_child(_layer)
	for i in 4:
		var m := ColorRect.new()
		m.color = Color(0, 0, 0, 0.58)
		m.mouse_filter = Control.MOUSE_FILTER_STOP   # 洞外挡点击 = 只能点洞里那一处
		_layer.add_child(m)
		_mask.append(m)
	_ring = ColorRect.new()
	_ring.color = Color(1, 0.85, 0.25, 0.0)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_script(preload("res://scripts/scenes/tutorial_ring.gd"))
	_layer.add_child(_ring)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.110, 0.204, 0.94)
	sb.set_border_width_all(2); sb.border_color = Color("#ffd93d")
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 26; sb.content_margin_right = 26
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(_panel)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 24)
	_text.add_theme_color_override("font_color", Color("#fff3c4"))
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_text.add_theme_constant_override("outline_size", 4)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_text)
	_hand = TextureRect.new()
	_hand.name = "TutorialHand"
	if ResourceLoader.exists(HAND_TEX):
		_hand.texture = load(HAND_TEX)
	_hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.stretch_mode = TextureRect.STRETCH_SCALE
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts: Vector2 = _hand.texture.get_size() if _hand.texture != null else Vector2(18, 19)
	_hand.size = ts * HAND_SCALE
	_layer.add_child(_hand)


func _render() -> void:
	if _idx >= _steps.size():
		return
	var step: Dictionary = _steps[_idx]
	_text.text = str(step.get("text", ""))
	_cur_hl = str(step.get("highlight", ""))
	_shown = false
	_stable_n = 0
	_last_rect = Rect2()
	_hl_empty_frames = 0
	_hl_warned = false
	_show(false)


func _process(dt: float) -> void:
	if _idx >= _steps.size() or _layer == null:
		return
	_t += dt
	var host_ok: bool = (not _ready_fn.is_valid()) or bool(_ready_fn.call())
	var rect := _target_rect(_cur_hl)
	if not host_ok:
		_show(false)
		_shown = false
		_stable_n = 0
		return
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_hl_empty_frames += 1
		if _hl_empty_frames >= HL_GRACE_FRAMES and not _hl_warned:
			_hl_warned = true
			push_warning("[Tutorial] 高亮锚点 '%s' 连续 %d 帧解析出空矩形 → 本步暂不显示(本步只报这一条)"
				% [_cur_hl, _hl_empty_frames])
		_show(false)
		_shown = false
		_stable_n = 0
		return
	_hl_empty_frames = 0
	if not _shown:
		if rect.is_equal_approx(_last_rect):
			_stable_n += 1
		else:
			_stable_n = 0
		_last_rect = rect
		if _stable_n < STABLE_FRAMES:
			_show(false)
			return
		_shown = true
	_show(true)
	_apply_highlight(rect)
	_place_panel(rect)
	_place_hand(rect)


## 显示 / 收起整条引导。★暗幕本身也一起关: 只关图层的话, 暗幕节点的 visible 仍是 true,
##   而它们是 MOUSE_FILTER_STOP 的 —— 不能指望引擎对「图层隐藏」的命中判定替我们挡住。
func _show(on: bool) -> void:
	_layer.visible = on
	for m in _mask:
		(m as Control).visible = on
	_ring.visible = on


func _target_rect(hl_name: String) -> Rect2:
	if hl_name == "" or not _anchor_fn.is_valid():
		return Rect2()
	var r = _anchor_fn.call(hl_name)
	return r if r is Rect2 else Rect2()


## 挖洞高亮: 四块暗幕围住目标矩形。
func _apply_highlight(target: Rect2) -> void:
	var rect := target.grow(8.0)
	var vp: Vector2 = Vector2(_layer.get_viewport().get_visible_rect().size)
	_mask[0].position = Vector2(0, 0);                         _mask[0].size = Vector2(vp.x, maxf(0.0, rect.position.y))
	_mask[1].position = Vector2(0, rect.end.y);                _mask[1].size = Vector2(vp.x, maxf(0.0, vp.y - rect.end.y))
	_mask[2].position = Vector2(0, rect.position.y);           _mask[2].size = Vector2(maxf(0.0, rect.position.x), rect.size.y)
	_mask[3].position = Vector2(rect.end.x, rect.position.y);  _mask[3].size = Vector2(maxf(0.0, vp.x - rect.end.x), rect.size.y)
	_ring.position = rect.position
	_ring.size = rect.size
	_ring.queue_redraw()


## 提示条: 贴着目标放 —— 目标下方放得下就放下方, 否则放上方, 都放不下才退到屏顶(不压目标)。
##   (第一版按「目标在哪半屏就放另一半」, 实拍盖住了选龟屏标题、商店里和购买提示叠在一起。)
func _place_panel(target: Rect2) -> void:
	var vp: Vector2 = Vector2(_layer.get_viewport().get_visible_rect().size)
	var sz: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = sz
	const GAP := 20.0
	const HAND_ROOM := 64.0
	var y: float
	var where := str((_steps[_idx] as Dictionary).get("anchor", ""))
	## "right": 贴在指点处(point, 缺省=目标)右侧、垂直居中 —— 目标上下紧挨着别的内容(背包上方是战场行、完成钮下方是龟卡)时用。
	##   右侧放不下才退回下面的常规规则。
	if where == "right":
		var base := target
		var pt_name := str((_steps[_idx] as Dictionary).get("point", ""))
		if pt_name != "":
			var r2 := _target_rect(pt_name)
			if r2.size.x > 0.0 and r2.size.y > 0.0:
				base = r2
		var rx: float = base.end.x + HAND_ROOM
		var ry: float = base.get_center().y - sz.y * 0.5
		if rx + sz.x + 12.0 <= vp.x and ry >= 8.0 and ry + sz.y + 8.0 <= vp.y:
			_panel.position = Vector2(round(rx), round(ry))
			return
	if where == "top":
		y = 22.0
	elif where == "bottom":
		y = vp.y - sz.y - 22.0
	elif target.end.y + HAND_ROOM + sz.y + 8.0 <= vp.y:
		y = target.end.y + HAND_ROOM      # 下方要让出手势指针的高度(指尖在目标里, 手掌伸出目标下沿)
	elif target.position.y - GAP - sz.y >= 8.0:
		y = target.position.y - GAP - sz.y
	else:
		y = 22.0
	var x: float = clampf(target.get_center().x - sz.x * 0.5, 12.0, vp.x - sz.x - 12.0)
	_panel.position = Vector2(round(x), round(y))


## 手势指针: 点按类在目标上「按下 - 抬起」循环; 拖动类从目标拖向右侧循环。
func _place_hand(target: Rect2) -> void:
	if _hand.texture == null:
		_hand.visible = false
		return
	var step: Dictionary = _steps[_idx]
	var pr := target
	var pt_name := str(step.get("point", ""))
	if pt_name != "":
		var r2 := _target_rect(pt_name)
		if r2.size.x > 0.0 and r2.size.y > 0.0:
			pr = r2
	var tip: Vector2 = pr.get_center()
	if pr.size.y > 120.0 or pr.size.x > 320.0:
		tip = pr.get_center()
	else:
		tip.y = pr.position.y + pr.size.y * 0.62
	var off := Vector2.ZERO
	var a := 1.0
	if str(step.get("hand", "tap")) == "drag":
		var cyc: float = fmod(_t, 1.6) / 1.6
		var k: float = clampf(cyc / 0.75, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		off = Vector2(150.0, -30.0) * k
		a = 1.0 if cyc < 0.8 else maxf(0.0, 1.0 - (cyc - 0.8) / 0.2)
	else:
		off.y = 10.0 + 8.0 * sin(_t * TAU * 1.4)
	_hand.modulate.a = a
	_hand.visible = true
	_hand.position = (tip + off - HAND_TIP * HAND_SCALE).round()


func _finish() -> void:
	_idx = _steps.size()
	if _layer != null:
		_show(false)
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


## 控件的屏幕矩形 —— 只有它**真的看得见**(在树里可见 + 一路往上的透明度乘积 ≥ 0.98)才返回;
##   否则空矩形 ⇒ 本步先不显示。★B6 那一类(提示比内容先到)的另一半: 入场动画常常是**淡入**不是位移,
##   只看「矩形连续几帧不动」挡不住(实拍: 结算屏「前往商店」还没淡进来, 洞已经挖在一块空地上)。
static func vis_rect(c) -> Rect2:
	if c == null or not is_instance_valid(c) or not (c is Control) or not (c as Control).is_visible_in_tree():
		return Rect2()
	var a := 1.0
	var n: Node = c
	while n != null and n is CanvasItem:
		a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	if a < 0.98:
		return Rect2()
	return (c as Control).get_global_rect()


## 从 data/tutorial-steps.json 取某一屏的步骤。取不到返回空数组(不显示引导, 不崩)。
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


## 一行接入: 有步骤才建节点。返回实例(没有步骤 ⇒ null)。
## anchor_fn 缺省用 host._tutorial_anchor; ready_fn 缺省 = 只等目标矩形稳定。
static func attach(host: Node, key: String, on_done: Callable = Callable(),
		anchor_fn: Callable = Callable(), ready_fn: Callable = Callable()) -> Node:
	var steps := steps_for(key)
	if steps.is_empty():
		return null
	var g = load("res://scripts/scenes/TutorialGuide.gd").new()
	g.name = "TutorialGuide"
	host.add_child(g)
	g.add_to_group("tut_overlay")   # ★商店/背包 `_rebuild()` 跳过本组, 否则引导被 queue_free
	var af := anchor_fn
	if not af.is_valid() and host.has_method("_tutorial_anchor"):
		af = Callable(host, "_tutorial_anchor")
	var cb: Callable = on_done if on_done.is_valid() else func() -> void: pass
	g.start(steps, cb, af, ready_fn)
	return g
