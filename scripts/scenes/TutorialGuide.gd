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
## steps = [{ "text", "highlight", "advanceOn", "point"?, "hand"?("tap"|"drag"|"none"), "anchor"?("top"|"bottom"|"right"|"left"), "auto"?(秒) }]
##
## ★v3(2026-10-20, 方案书 docs/plans/20261020-教程重写.md D7): 带 `auto` 的步 = **不阻塞的提示**(战斗里那两句)。
##   不压暗、不挡点击(本层所有控件 MOUSE_FILTER_IGNORE, 暗幕不显示)、不出手势、不暂停战斗;
##   淡入 → 停 `auto` 秒 → 淡出 → 自己前进。门禁量 `is_blocking()` 恒假。
##
## ★v5(2026-10-21, 分镜 docs/plans/20261021-教程分镜v5.md「引导形式」):
##   · 只有气泡 + **金色箭头**(用户「不要引导人物」; 原来的手势指针贴图换成代码画的箭头, 不借素材)。
##   · 点了暗幕(洞外)⇒ 气泡下多出一行说明(`_wrong_tap`, 分镜「点错有一句说明」), 2.5 秒后收起。
##   · 每一步变成当前步时, 宿主若有 `tut_step_shown(highlight)` 就调一次(商店据此到 E2 才显示「买经验」:
##     分镜「按钮教到才出现」)。
##   · 文案里的 `{pet}` / `{item}` 由宿主 `tut_text_vars()` 按那一刻的状态填(B1/B3 点名下一只龟, F1 点名刚买的装备)。

## 金色箭头(指向下方, 箭尖在控件坐标 ARROW_TIP)。代码画, 不用贴图。
const ARROW_SIZE := Vector2(40, 54)
const ARROW_TIP := Vector2(20, 54)
const ARROW_GOLD := Color("#ffd93d")
const ARROW_EDGE := Color("#3a2205")
## 点错那一行说明停留的秒数。
const WRONG_TAP_SEC := 2.5
## 气泡最宽占视口的比例(文案是一整句, 超了就折行)。
const PANEL_MAX_FRAC := 0.86
## 战斗提示带的上沿(视口高度的比例, 见 _place_panel 的 "band")。
const BAND_Y_FRAC := 0.2
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
var _hint: Label                     # 点错时气泡下那一行说明
var _hint_t: float = 0.0
var _hand: Control                   # 金色箭头(名字保留 _hand: 指针的动法仍由步骤的 hand 字段决定)
var _wrong_text: String = ""
var _mask: Array = []                # 4 个 ColorRect(上/下/左/右), 洞外压暗 + 挡点击
var _ring: ColorRect
var _cur_hl: String = ""
var _shown: bool = false             # 本步已经显示过(之后不再因目标轻微移动而闪)
var _stable_n: int = 0
var _last_rect := Rect2()
var _t: float = 0.0
var _hl_empty_frames: int = 0
var _hl_warned: bool = false
var _tip_t: float = 0.0              # 本步(不阻塞提示)已显示的秒数
const TIP_FADE := 0.35               # 不阻塞提示淡入 / 淡出各用的秒数


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


## 当前这一步是不是不阻塞的提示(带 `auto`)。
func is_tip() -> bool:
	return _idx < _steps.size() and float((_steps[_idx] as Dictionary).get("auto", 0.0)) > 0.0


## ★门禁用: 本层此刻有没有**能吃到点击**的可见控件(暗幕 / 任何非 IGNORE 的控件)。不阻塞提示期间必须恒假。
func is_blocking() -> bool:
	if _layer == null or not _layer.visible:
		return false
	for c in _layer.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
	return false


## 提示条此刻的屏幕矩形(没显示 = 空)。门禁量「不压别的控件」用。
func panel_rect() -> Rect2:
	if not is_showing() or _panel == null:
		return Rect2()
	return Rect2(_panel.position, _panel.size)


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
	for m2 in _mask:
		(m2 as Control).gui_input.connect(_on_mask_input)
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
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	_panel.add_child(vb)
	vb.add_child(_text)
	_hint = Label.new()
	_hint.name = "TutorialWrongTap"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color("#ffb08a"))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	vb.add_child(_hint)
	_wrong_text = wrong_tap_text()
	_hand = Control.new()
	_hand.name = "TutorialArrow"
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.size = ARROW_SIZE
	_hand.pivot_offset = ARROW_TIP
	_hand.draw.connect(_draw_arrow)
	_layer.add_child(_hand)


## 金色箭头: 竖杆 + 三角箭头, 深色描边(像素风直角, 不抗锯齿)。箭尖在 ARROW_TIP(底边中点)。
func _draw_arrow() -> void:
	var pts := PackedVector2Array([
		Vector2(13, 0), Vector2(27, 0), Vector2(27, 28), Vector2(39, 28),
		Vector2(20, 54), Vector2(1, 28), Vector2(13, 28)])
	_hand.draw_colored_polygon(pts, ARROW_GOLD)
	var outline := pts.duplicate()
	outline.append(pts[0])
	_hand.draw_polyline(outline, ARROW_EDGE, 3.0, false)
	_hand.draw_rect(Rect2(16, 3, 4, 22), Color(1, 1, 1, 0.45))   # 杆上一道高光


## 点了洞外的暗幕 ⇒ 气泡下出一行说明(不前进、不放行这次点击)。
func _on_mask_input(ev: InputEvent) -> void:
	var press: bool = (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if not press or is_tip() or _wrong_text == "":
		return
	_hint.text = _wrong_text
	_hint.visible = true
	_hint_t = WRONG_TAP_SEC


## 气泡下那一行说明此刻的字(没显示 = 空)。门禁读。
func wrong_tap_shown() -> String:
	return _hint.text if _hint != null and _hint.visible else ""


func _render() -> void:
	if _idx >= _steps.size():
		return
	var step: Dictionary = _steps[_idx]
	_cur_hl = str(step.get("highlight", ""))
	var host := get_parent()
	if host != null and host.has_method("tut_step_shown"):
		host.call("tut_step_shown", _cur_hl)
	_text.text = fill_text(str(step.get("text", "")), host)
	_fit_text_width()
	if _hint != null:
		_hint.visible = false
		_hint_t = 0.0
	_shown = false
	_stable_n = 0
	_last_rect = Rect2()
	_hl_empty_frames = 0
	_hl_warned = false
	_tip_t = 0.0
	_show(false)


func _process(dt: float) -> void:
	if _idx >= _steps.size() or _layer == null:
		return
	_t += dt
	if _hint_t > 0.0:
		_hint_t -= dt
		if _hint_t <= 0.0:
			_hint.visible = false
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
		## 不阻塞提示的目标会跟着战斗镜头走(蛋), 不要求「不动」—— 宿主就绪且连续几帧解析得出即可。
		if rect.is_equal_approx(_last_rect) or is_tip():
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
	if is_tip():
		## 不阻塞提示默认不出箭头; 步骤写明 hand: tap 时出(E1: 气泡挪到顶上, 箭头朝下指等级牌)。
		if str((_steps[_idx] as Dictionary).get("hand", "none")) == "tap":
			_place_hand(rect)
		else:
			_hand.visible = false
		_tick_tip(dt)
		return
	_place_hand(rect)


## 不阻塞提示: 淡入 → 停 → 淡出 → 前进。★时间只在真显示时累计(宿主没准备好时不偷跑)。
func _tick_tip(dt: float) -> void:
	var dur: float = float((_steps[_idx] as Dictionary).get("auto", 3.0))
	_tip_t += dt
	var a: float = clampf(minf(_tip_t / TIP_FADE, (dur + TIP_FADE - _tip_t) / TIP_FADE), 0.0, 1.0)
	_panel.modulate.a = a
	_ring.modulate.a = a
	if _hand.visible:
		_hand.modulate.a = a
	if _tip_t >= dur + TIP_FADE:
		_panel.modulate.a = 1.0
		_ring.modulate.a = 1.0
		_idx += 1
		if _idx >= _steps.size():
			_finish()
		else:
			_render()


## 显示 / 收起整条引导。★暗幕本身也一起关: 只关图层的话, 暗幕节点的 visible 仍是 true,
##   而它们是 MOUSE_FILTER_STOP 的 —— 不能指望引擎对「图层隐藏」的命中判定替我们挡住。
## ★不阻塞提示(`auto`)从不显示暗幕: 暗幕挡点击, 而战斗里不许挡。
func _show(on: bool) -> void:
	_layer.visible = on
	var tip := is_tip()
	for m in _mask:
		(m as Control).visible = on and not tip
	_ring.visible = on
	if not on and _hand != null:
		_hand.visible = false


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
	const HAND_ROOM := 64.0
	## 箭头画在目标上方 ⇒ 气泡放在目标上方时要让出箭头的高度(不阻塞提示没有箭头)。
	var GAP: float = 20.0 if is_tip() else 20.0 + ARROW_SIZE.y + 10.0
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
	## "left": 贴在目标左侧、垂直居中(战斗里顶部计时牌: 下方是战场, 提示条不许压单位与血条)。左侧放不下才退回常规规则。
	if where == "left":
		var lx: float = target.position.x - GAP - sz.x
		var ly: float = target.get_center().y - sz.y * 0.5
		if lx >= 12.0 and ly >= 8.0:
			_panel.position = Vector2(round(lx), round(ly))
			return
	## "band"(v5 战斗提示): 屏幕水平居中, 放在顶部 HUD(名字条 / PK 条 / 战场计时牌, 到约 0.18 屏)与场上单位头顶条
	##   (约 0.34 屏起)之间那条空带 —— 文案是一整句, 贴着目标放会压到头像栏 / 单位等级牌(实测 R2 红)。
	if where == "band":
		_panel.position = Vector2(round(maxf(12.0, (vp.x - sz.x) * 0.5)), round(vp.y * BAND_Y_FRAC))
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


## 金色箭头: 点按类在目标上方朝下指、上下浮动(目标太靠上就翻到下方朝上指); 拖动类从目标滑向右侧循环。
func _place_hand(target: Rect2) -> void:
	var step: Dictionary = _steps[_idx]
	if str(step.get("hand", "tap")) == "none":
		_hand.visible = false
		return
	var pr := target
	var pt_name := str(step.get("point", ""))
	if pt_name != "":
		var r2 := _target_rect(pt_name)
		if r2.size.x > 0.0 and r2.size.y > 0.0:
			pr = r2
	var tip: Vector2 = pr.get_center()
	var off := Vector2.ZERO
	var a := 1.0
	var up := false
	if str(step.get("hand", "tap")) == "drag":
		var cyc: float = fmod(_t, 1.6) / 1.6
		var k: float = clampf(cyc / 0.75, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		off = Vector2(150.0, -30.0) * k
		a = 1.0 if cyc < 0.8 else maxf(0.0, 1.0 - (cyc - 0.8) / 0.2)
	else:
		var inset: float = minf(12.0, pr.size.y * 0.25)
		var bob: float = 6.0 + 6.0 * sin(_t * TAU * 1.4)
		tip.y = pr.position.y + inset
		if tip.y - ARROW_SIZE.y - 14.0 < 0.0:   # 上方放不下 ⇒ 从下方朝上指
			up = true
			tip.y = pr.end.y - inset
			off.y = bob
		else:
			off.y = -bob
	_hand.rotation = PI if up else 0.0
	_hand.modulate.a = a
	_hand.visible = true
	_hand.position = (tip + off - ARROW_TIP).round()


## 箭尖此刻在屏幕上的位置(门禁量「箭头指在目标上」; 旋转绕箭尖, 所以朝上时箭尖位置不变)。
func arrow_tip() -> Vector2:
	return _hand.position + ARROW_TIP if _hand != null else Vector2.ZERO


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


## 文案里的 `{pet}` / `{item}` 等占位: 宿主 `tut_text_vars()` 给值(按那一刻的状态); 没给的原样留着(门禁扫「{」抓漏填)。
static func fill_text(t: String, host: Node) -> String:
	if not t.contains("{") or host == null or not host.has_method("tut_text_vars"):
		return t
	var vars = host.call("tut_text_vars")
	if not (vars is Dictionary):
		return t
	for k in (vars as Dictionary).keys():
		t = t.replace("{%s}" % str(k), str(vars[k]))
	return t


## 一整句太长 ⇒ 限宽折行(手机窄屏); 放得下就单行。
func _fit_text_width() -> void:
	if _text == null or _layer == null:
		return
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.custom_minimum_size = Vector2.ZERO
	var vpw: float = float(_layer.get_viewport().get_visible_rect().size.x) if _layer.is_inside_tree() else 1280.0
	var maxw: float = vpw * PANEL_MAX_FRAC - 52.0
	var f: Font = _text.get_theme_font("font")
	var fs: int = _text.get_theme_font_size("font_size")
	var w: float = f.get_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x if f != null else 0.0
	if w > maxw:
		_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_text.custom_minimum_size = Vector2(maxw, 0)


## 点错那一行说明(data/tutorial-steps.json 顶层 `_wrong_tap`)。
static func wrong_tap_text() -> String:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STEPS_PATH))
	return str((parsed as Dictionary).get("_wrong_tap", "")) if parsed is Dictionary else ""


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
	return attach_steps(host, steps_for(key), on_done, anchor_fn, ready_fn)


## 同 `attach`, 但步骤直接给(导演按战斗事件一句一句挂不阻塞提示时用)。
static func attach_steps(host: Node, steps: Array, on_done: Callable = Callable(),
		anchor_fn: Callable = Callable(), ready_fn: Callable = Callable()) -> Node:
	if steps.is_empty() or host == null:
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
