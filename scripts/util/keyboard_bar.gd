class_name KeyboardBar
extends CanvasLayer
## 手机打字输入条(2026-10-28, 用户认可方向稿「行」; 方案书 docs/plans/20261028-手机打字输入条.md)。
##
## 照 6 款横屏手游打字时的共同做法: 键盘弹起时, 键盘正上方贴一条整宽输入条, 字放大打在条里,
##   右边是「清空 / 完成」(以及这一处要的副键), 原界面不挪。点条以外的地方 = 完成。
##
## ★为什么条里另起一个输入框, 而原输入框改成「点一下打开条」的显示框:
##   原框不拿焦点 ⇒ 全程只有条里那一个框拿焦点 ⇒ 键盘只弹一次(两个框互相交接焦点会让键盘收了又弹)。
##   条里每打一个字就同步写回原框, 原界面的确认 / 提交逻辑一行不用改。
## ★只在有虚拟键盘的设备上接管(手机); 桌面 / 无头照旧直接在原框里打 —— 玩家路径以外一字不动。
##   门禁用 `vkb_override_vp` 注入键盘高度, 把这一支造出来量(同 SettingsScene.vkb_override_vp 那个模式)。
## ★编辑中脚本改写条里的字(换一个 / 粘贴 / 清空 / 超字数截断)之后要把新字重新交给系统键盘
##   (`_resync`) —— 引擎在 iOS 上用一个隐藏文本框转发按键, 脚本写 `.text` 不会同步给它,
##   不同步的话下一次退格会按旧字删(Godot 4.6.3 drivers/apple_embedded/godot_keyboard_input_view.mm)。
##
## 用法: `KeyboardBar.attach(edit, {...})` —— edit 是原来的 LineEdit / TextEdit。选项:
##   "primary": String       主键文字(默认「完成」)
##   "primary_cb": Callable  主键 / 回车除了收起之外还要做的事(收起之后调, 传入最终文字)
##   "extras": Array         副键 [[文字, Callable(bar)], ...](换一个 / 粘贴 / 收起)
##   "count_max": int        字数上限(> 0 才显示「n / max」)
##   "count_fn": Callable    怎么数字数(默认 length)
##   "max_length": int       条里输入框的硬上限(默认跟原框; 会打中文的框给 0, 提交时再校验)
##   "tag_fn": Callable      多行条左上的小签文字(问题反馈的类型)
##   "title": String         多行条左上的说明(「问题描述」)
##   "lines": int            多行条最多显示几行(默认 3)

const DIR := "res://assets/sprites/ui/keyboard_bar/"
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const NODE := "KeyboardBar"
const LAYER := 7000

## 【门禁注入点】键盘高度(视口单位)。< 0 = 读真机。≥ 0 时也视为「有虚拟键盘」, 条会接管。
static var vkb_override_vp: float = -1.0
## 上一次量到的键盘高(视口单位)。键盘高要等弹出动画播完才拿得到 ⇒ 先按上次的摆, 没量过按 52% 估。
static var _last_kb: float = 0.0
## 现在开着的那一条(同一时刻只有一条)。
static var _open: KeyboardBar = null

## 尺寸(视口单位, 720 高)。单行条 96 = 81 触摸线 + 上下各 7.5。
const BAR_H := 96.0
const ROW_H := 81.0
const PAD := 24.0
const GAP := 16.0
const FONT := 32
const FONT_MULTI := 28
const FONT_SMALL := 20
const FONT_KEY := 26
const KEY_W := 150.0
const CLEAR_HIT := 81.0
const EST_KB := 0.52            ## 没量过时的估计: 中文候选栏 / 预测栏那一档(走查 52%)
const KEY_BOTTOM := 12.0        ## 键底座下沿 4 源像素 ×3 是唇边, 字落在键面正中

const COL_TEXT := Color("#e8f0ff")
const COL_DIM := Color("#a8c0e4")        ## 条上说明字 / 字数(颜色随素材, tools/build_keyboard_bar_ui.py 头注)
const COL_ERR := Color("#ff9a9a")
const COL_PH := Color("#6c80a6")
const COL_KEY_MAIN := Color("#2e1a06")   ## 金键上的字: 深棕不描边
const COL_KEY_SUB := Color("#f6eed6")    ## 石板键上的字: 奶油色 + 细描边
const COL_KEY_SUB_OL := Color("#283042")
const COL_TAG := Color("#effffa")
const COL_TAG_OL := Color("#125458")

var src: Control = null
var edit: Control = null           ## 条里那一个真正拿焦点的框(LineEdit 或 TextEdit)
var opts: Dictionary = {}
var multi := false
var _panel: Panel = null
var _slot: Panel = null
var _count: Label = null
var _status: Label = null
var _tag: Label = null
var _keys: Array = []
var _seen_kb := false
var _zero_frames := 0
var _closing := false


## 这台设备上条要不要接管(手机 = 有虚拟键盘; 门禁注入了键盘高也算)。
static func active() -> bool:
	if vkb_override_vp >= 0.0:
		return true
	return DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and SafeArea.is_mobile()


static func is_open() -> bool:
	return _open != null and is_instance_valid(_open) and not _open._closing


static func current() -> KeyboardBar:
	return _open if is_open() else null


## 把一个原输入框接到条上。桌面 / 无头不接管(返回 false), 原框照旧。
static func attach(e: Control, o: Dictionary = {}) -> bool:
	if e == null or not active():
		return false
	e.focus_mode = Control.FOCUS_NONE
	## 会打中文的框不设硬上限(拼音组字时字母先进框, 上限会吞字), 提交时再校验 —— 原框跟着改, 否则写回时被截断。
	if o.has("max_length") and e is LineEdit:
		(e as LineEdit).max_length = int(o["max_length"])
	e.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	e.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (ev as InputEventMouseButton).pressed:
			e.accept_event()
			open(e, o))
	e.set_meta("kb_bar", true)
	return true


## 昵称框(首次起名 / 设置改名 / 绑定屏)共用的接法: 字数按规范化后数、条里有「换一个」、不设硬上限。
## ★三处各写一份必然漂(memory `fb-hand-rolled-copies-drift`)。
static func attach_nickname(e: LineEdit) -> bool:
	return attach(e, {
		"max_length": 0,
		"count_max": _P2C.NICK_MAX,
		"count_fn": func(t: String) -> int: return _P2C.nickname_clean(t).length(),
		"extras": [[_P2C.NICK_REROLL, func(bar: KeyboardBar) -> void:
			bar.set_text(_P2C.nickname_suggest(bar.get_text()))]],
	})


## 打开条(已经开着别的就先收掉那一条)。
static func open(e: Control, o: Dictionary = {}) -> KeyboardBar:
	if is_open():
		_open.close(false)
	var b := KeyboardBar.new()
	b.name = NODE
	b.layer = LAYER
	b.src = e
	b.opts = o
	b.multi = e is TextEdit
	e.add_child(b)
	b._build()
	_open = b
	return b


## 视口单位的键盘高。0 = 没有键盘(或还没弹完)。
static func kb_height(vs: Vector2) -> float:
	if vkb_override_vp >= 0.0:
		return vkb_override_vp
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var win := Vector2(DisplayServer.window_get_size())
	var px := float(DisplayServer.virtual_keyboard_get_height())
	if px <= 0.0 or win.y <= 1.0 or vs.y <= 1.0:
		return 0.0
	return px * (vs.y / win.y)


## 条现在该摆的键盘高: 真值 > 上次量到的 > 估计。
static func kb_for_layout(vs: Vector2) -> float:
	var kb := kb_height(vs)
	if kb > 0.0:
		return kb
	return _last_kb if _last_kb > 0.0 else roundf(vs.y * EST_KB)


func _vs() -> Vector2:
	var vp := src.get_viewport() if src != null and src.is_inside_tree() else null
	return Vector2(vp.get_visible_rect().size) if vp != null else Vector2(1280, 720)


# ─────────────────────────────── 建 ───────────────────────────────

func _build() -> void:
	## 点条以外 = 完成(iPhone 键盘没有收起键; 引擎里点空白处也不会让输入框失焦)。
	var catcher := Control.new()
	catcher.name = "Outside"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close(false))
	add_child(catcher)

	_panel = Panel.new()
	_panel.name = "Bar"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _nine("bar.png", [4, 4, 4, 2], Color("#1d2c4c")))
	add_child(_panel)

	_slot = Panel.new()
	_slot.name = "Slot"
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_theme_stylebox_override("panel", _nine("slot-focus.png", [4, 4, 4, 4], Color("#0b1220")))
	_panel.add_child(_slot)

	if multi:
		var te := TextEdit.new()
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		te.add_theme_font_size_override("font_size", FONT_MULTI)
		te.virtual_keyboard_enabled = true
		te.placeholder_text = (src as TextEdit).placeholder_text
		te.text = (src as TextEdit).text
		te.text_changed.connect(_on_text_changed)
		edit = te
	else:
		var le := LineEdit.new()
		var s := src as LineEdit
		le.placeholder_text = s.placeholder_text
		le.virtual_keyboard_type = s.virtual_keyboard_type
		le.max_length = int(opts.get("max_length", s.max_length))
		le.text = s.text
		le.add_theme_font_size_override("font_size", FONT)
		le.text_changed.connect(func(_t: String) -> void: _on_text_changed())
		le.text_submitted.connect(func(_t: String) -> void: _on_primary())
		edit = le
	edit.name = "Edit"
	for slot in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(slot, StyleBoxEmpty.new())
	edit.add_theme_color_override("font_color", COL_TEXT)
	edit.add_theme_color_override("font_placeholder_color", COL_PH)
	edit.add_theme_color_override("caret_color", Color("#ffd93d"))
	if edit is TextEdit:
		edit.add_theme_color_override("background_color", Color(0, 0, 0, 0))
	_slot.add_child(edit)

	_count = Label.new()
	_count.name = "Count"
	_count.add_theme_font_size_override("font_size", FONT_SMALL)
	_count.add_theme_color_override("font_color", COL_DIM)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_count)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", FONT_SMALL)
	_status.add_theme_color_override("font_color", COL_ERR)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.clip_text = true
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_status)

	if multi:
		_tag = Label.new()
		_tag.name = "Tag"
		_tag.add_theme_font_size_override("font_size", FONT_SMALL)
		_tag.add_theme_color_override("font_color", COL_TAG)
		_tag.add_theme_color_override("font_outline_color", COL_TAG_OL)
		_tag.add_theme_constant_override("outline_size", 4)
		_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_tag.add_theme_stylebox_override("normal", _nine("tag.png", [3, 3, 3, 3], Color("#1c7672"), [12, 2, 12, 2]))
		_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(_tag)
		var title := Label.new()
		title.name = "Title"
		title.text = str(opts.get("title", ""))
		title.add_theme_font_size_override("font_size", FONT_SMALL)
		title.add_theme_color_override("font_color", COL_DIM)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(title)

	## 清空 ×: 看起来 33×33, 可点 81×81(只在有字时出现)。
	var clr := PixelKey.HitButton.new()
	clr.name = "Clear"
	clr.flat = true
	clr.focus_mode = Control.FOCUS_NONE
	clr.icon = PixelKey.up(DIR + "icon-clear.png")
	if clr.icon == null:
		clr.text = "×"
		clr.add_theme_font_size_override("font_size", 30)
	clr.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clr.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		clr.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	clr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clr.pressed.connect(func() -> void: set_text(""))
	_panel.add_child(clr)

	for ex in opts.get("extras", []):
		var cb: Callable = ex[1]
		_keys.append(_key("Extra" + str(_keys.size()), str(ex[0]), false, func() -> void: cb.call(self)))
	_keys.append(_key("Primary", str(opts.get("primary", "完成")), true, _on_primary))

	_on_text_changed()
	_layout()
	## 拿焦点 ⇒ 弹键盘(LineEdit / TextEdit 在获得焦点时自己调 virtual_keyboard_show)。
	edit.grab_focus()
	if edit is LineEdit:
		(edit as LineEdit).caret_column = (edit as LineEdit).text.length()
		(edit as LineEdit).edit()
	else:
		var te2 := edit as TextEdit
		te2.set_caret_line(te2.get_line_count() - 1)
		te2.set_caret_column(te2.get_line(te2.get_line_count() - 1).length())


func _key(n: String, label: String, primary: bool, cb: Callable) -> Button:
	var b := PixelKey.HitButton.new()
	b.name = n
	b.text = label
	b.add_theme_font_size_override("font_size", FONT_KEY)
	var up := DIR + ("key-gold.png" if primary else "key-steel.png")
	var dn := DIR + ("key-gold-down.png" if primary else "key-steel-down.png")
	if ResourceLoader.exists(up) and ResourceLoader.exists(dn):
		PixelKey.skin(b, up, dn, 12.0, KEY_BOTTOM)
	else:
		UISkin.card_button(b)
		b.focus_mode = Control.FOCUS_NONE
	var fc := COL_KEY_MAIN if primary else COL_KEY_SUB
	if not primary:
		b.add_theme_color_override("font_outline_color", COL_KEY_SUB_OL)
		b.add_theme_constant_override("outline_size", 4)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fc)
	b.pressed.connect(cb)
	_panel.add_child(b)
	return b


## 1 倍源图 ×3 的九宫格; 素材不在 ⇒ 纯色退路。content = 内容边距(视口单位)。
func _nine(file: String, margin: Array, fallback: Color, content: Array = [0, 0, 0, 0]) -> StyleBox:
	var tex := PixelKey.up(DIR + file)
	var sb: StyleBox
	if tex == null:
		var f := StyleBoxFlat.new()
		f.bg_color = fallback
		sb = f
	else:
		var t := StyleBoxTexture.new()
		t.texture = tex
		t.texture_margin_left = float(margin[0] * PixelKey.SCALE)
		t.texture_margin_top = float(margin[1] * PixelKey.SCALE)
		t.texture_margin_right = float(margin[2] * PixelKey.SCALE)
		t.texture_margin_bottom = float(margin[3] * PixelKey.SCALE)
		sb = t
	sb.content_margin_left = float(content[0])
	sb.content_margin_top = float(content[1])
	sb.content_margin_right = float(content[2])
	sb.content_margin_bottom = float(content[3])
	return sb


# ─────────────────────────────── 摆 ───────────────────────────────

## 条的高: 单行 96; 多行 = 说明行 + 槽(随行数涨, 最多 lines 行, 再多就在槽里滚)。
func bar_height() -> float:
	if not multi:
		return BAR_H
	var te := edit as TextEdit
	var lh := float(te.get_line_height()) if te != null else 36.0
	var lines := 1
	if te != null:
		lines = 0
		for i in range(te.get_line_count()):
			lines += te.get_line_wrap_count(i) + 1
	lines = clampi(lines, 1, int(opts.get("lines", 3)))
	return 44.0 + maxf(ROW_H, lh * float(lines) + 20.0) + 12.0


func _layout() -> void:
	var vs := _vs()
	var kb := kb_for_layout(vs)
	var ins := SafeArea.insets(vs)
	var h := bar_height()
	_panel.position = Vector2(0.0, roundf(vs.y - kb - h))
	_panel.size = Vector2(vs.x, h)
	var left := ins.x + PAD
	var right := vs.x - ins.z - PAD
	## 右边的键从右往左排。
	var x := right
	for i in range(_keys.size() - 1, -1, -1):
		var b := _keys[i] as Button
		x -= KEY_W
		b.position = Vector2(x, h - 7.5 - ROW_H)
		b.size = Vector2(KEY_W, ROW_H)
		b.pad = 0.0
		x -= GAP
	var slot_top := 7.5 if not multi else 44.0
	var slot_h := ROW_H if not multi else h - 44.0 - 12.0
	_slot.position = Vector2(left, slot_top)
	_slot.size = Vector2(x - left, slot_h)
	var clr := _panel.get_node("Clear") as Button
	var count_w := 120.0 if int(opts.get("count_max", 0)) > 0 and not multi else 0.0
	clr.position = Vector2(_slot.position.x + _slot.size.x - CLEAR_HIT, slot_top + (slot_h - CLEAR_HIT) / 2.0) if not multi \
		else Vector2(_slot.position.x + _slot.size.x - CLEAR_HIT, slot_top)
	clr.size = Vector2(CLEAR_HIT, CLEAR_HIT if not multi else minf(CLEAR_HIT, slot_h))
	edit.position = Vector2(16.0, 0.0 if not multi else 6.0)
	edit.size = Vector2(_slot.size.x - 16.0 - CLEAR_HIT - count_w, slot_h if not multi else slot_h - 12.0)
	if multi:
		_tag.position = Vector2(left, 6.0)
		_tag.size = Vector2(_tag.get_minimum_size().x, 32.0)
		var title := _panel.get_node("Title") as Label
		title.position = Vector2(_tag.position.x + _tag.size.x + GAP, 6.0)
		title.size = Vector2(300.0, 32.0)
		_count.position = Vector2(_slot.position.x + _slot.size.x - 200.0, 6.0)
		_count.size = Vector2(200.0, 32.0)
		_status.position = Vector2(title.position.x + 140.0, 6.0)
		_status.size = Vector2(maxf(0.0, _count.position.x - title.position.x - 150.0), 32.0)
	else:
		_count.position = Vector2(_slot.position.x + _slot.size.x - CLEAR_HIT - count_w, slot_top)
		_count.size = Vector2(count_w, ROW_H)
		## 报错与字数共用一个位置: 有报错时字数让出来。
		_status.position = Vector2(_slot.position.x + _slot.size.x - CLEAR_HIT - 360.0, slot_top)
		_status.size = Vector2(360.0, ROW_H)
		_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_count.visible = _status.text == ""


func _process(_dt: float) -> void:
	if _closing or src == null or not is_instance_valid(src):
		return
	var vs := _vs()
	var kb := kb_height(vs)
	if kb > 0.0:
		_last_kb = kb
		_seen_kb = true
		_zero_frames = 0
	elif _seen_kb and vkb_override_vp < 0.0:
		## 系统把键盘收了(iPad 收起键 / 安卓返回键)⇒ 条跟着收。等几帧, 换输入法时高度会短暂归 0。
		_zero_frames += 1
		if _zero_frames > 8:
			close(false)
			return
	if multi and _tag != null:
		var tf = opts.get("tag_fn")
		_tag.text = str(tf.call()) if tf is Callable and (tf as Callable).is_valid() else ""
		_tag.visible = _tag.text != ""
	_layout()


# ─────────────────────────────── 字 ───────────────────────────────

func get_text() -> String:
	return str(edit.get("text")) if edit != null else ""


## 脚本改写条里的字(换一个 / 粘贴 / 清空)。改完把光标放到末尾并同步给系统键盘。
func set_text(t: String) -> void:
	if edit is LineEdit:
		var le := edit as LineEdit
		le.text = t
		le.caret_column = le.text.length()
	else:
		var te := edit as TextEdit
		te.text = t
		te.set_caret_line(te.get_line_count() - 1)
		te.set_caret_column(te.get_line(te.get_line_count() - 1).length())
	_on_text_changed()
	_resync()


func set_status(t: String, is_error: bool = true) -> void:
	if _status != null:
		_status.text = t
		_status.add_theme_color_override("font_color", COL_ERR if is_error else COL_DIM)


func _resync() -> void:
	if edit == null or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if not edit.has_focus():
		return
	var t := get_text()
	if edit is LineEdit:
		var le := edit as LineEdit
		DisplayServer.virtual_keyboard_show(t, le.get_global_rect(),
			le.virtual_keyboard_type as DisplayServer.VirtualKeyboardType, le.max_length, le.caret_column, -1)
	else:
		DisplayServer.virtual_keyboard_show(t, edit.get_global_rect(),
			DisplayServer.KEYBOARD_TYPE_MULTILINE, -1, t.length(), -1)


func _on_text_changed() -> void:
	var t := get_text()
	var mx := int(opts.get("count_max", 0))
	## 多行(反馈)有硬上限: 超了截回去 —— 截完必须同步给系统键盘, 否则下一次退格按旧字删。
	if multi and int(opts.get("max_length", 0)) > 0 and t.length() > int(opts.get("max_length", 0)):
		set_text(t.left(int(opts.get("max_length", 0))))
		return
	_mirror(t)
	if _count != null:
		if mx > 0:
			var fn = opts.get("count_fn")
			var n: int = int(fn.call(t)) if fn is Callable and (fn as Callable).is_valid() else t.length()
			_count.text = "%d / %d" % [n, mx]
			_count.add_theme_color_override("font_color", COL_ERR if n > mx else COL_DIM)
		else:
			_count.text = ""
	var clr := _panel.get_node_or_null("Clear") if _panel != null else null
	if clr != null:
		(clr as Control).visible = t != ""
	set_status("")


## 写回原框(原界面的确认 / 提交照旧读原框)。
func _mirror(t: String) -> void:
	if src == null or not is_instance_valid(src):
		return
	if src is LineEdit:
		var s := src as LineEdit
		if s.text != t:
			s.text = t
	elif src is TextEdit:
		var s2 := src as TextEdit
		if s2.text != t:
			s2.text = t


func _on_primary() -> void:
	var t := get_text()
	var cb = opts.get("primary_cb")
	close(false)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(t)


## 收起: 交还键盘、写回原框、拆掉条。
func close(_submit: bool = false) -> void:
	if _closing:
		return
	_closing = true
	_mirror(get_text())
	if edit != null and edit.has_focus():
		edit.release_focus()
	if _open == self:
		_open = null
	queue_free()
