extends Node
## verify_keyboard_bar.gd —— 手机打字输入条(2026-10-28, docs/plans/20261028-手机打字输入条.md)
##
## 无头没有虚拟键盘(has_feature 恒假) ⇒ 用 `KeyboardBar.vkb_override_vp` 注入键盘高, 把手机那一支造出来量。
## ① 桌面 / 无头不接管: 原框照旧能拿焦点(玩家路径以外一字不动)
## ② 组件本身(单行): 点原框 ⇒ 条打开; 条底 = 键盘顶(英文 299 / 中文 373 / 估计 52% 三档); 条里字 ≥ 30;
##    键 ≥ 81 高、全在屏内且不在键盘下; 打字写回原框; 字数「n / 8」; 换一个 / 清空真改了字且写回;
##    回车 / 主键收起并回调; 点条外 = 收起; 收起后原框留着最后的字
## ③ 多行(问题反馈): 条随行数涨, 最多 3 行; 左上小签 = 当前类型; 超 500 字截回; 提交 = 弹框自己的提交
## ④ 四处真接上了: 首次起名 / 设置改名 / 绑定屏(昵称 / 邮箱 / 验证码 + 粘贴) / 问题反馈 / 好友 ID(英文键盘 + 主键查找)
## ⑤ 反馈弹框的键加高到 81, 框没出屏
## ⑥ 验证码粘贴只取数字(纯函数)

const SET := preload("res://scripts/scenes/SettingsScene.gd")
const PANEL := preload("res://scripts/scenes/feedback_panel.gd")
const FLS := preload("res://scripts/scenes/FirstLaunchScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const KB_EN := 299.0     ## iPhone 横屏英文键盘 162pt(走查)
const KB_ZH := 373.0     ## + 中文候选栏 40pt

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _tap(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = c.size / 2.0
	c.gui_input.emit(ev)


## 模拟系统键盘逐字送进来(真机上 iOS 隐藏文本框也是这样逐字发按键给获得焦点的框)。
func _type(t: String) -> void:
	for ch in t:
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		Input.parse_input_event(ev)
		var up := InputEventKey.new()
		up.pressed = false
		up.unicode = ch.unicode_at(0)
		Input.parse_input_event(up)
	await _frames(2)


func _vs() -> Vector2:
	return Vector2(get_viewport().get_visible_rect().size)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 手机打字输入条 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await _t_desktop()
	await _t_single()
	await _t_multi()
	await _t_wired()
	_t_paste()
	KeyboardBar.vkb_override_vp = -1.0
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


## ① 桌面 / 无头不接管
func _t_desktop() -> void:
	KeyboardBar.vkb_override_vp = -1.0
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var e := LineEdit.new()
	host.add_child(e)
	var took := KeyboardBar.attach(e)
	_ok("① 无虚拟键盘 ⇒ 不接管", not took and not KeyboardBar.active(), str(took))
	_ok("① 原框照旧能拿焦点", e.focus_mode == Control.FOCUS_ALL, str(e.focus_mode))
	_tap(e)
	await _frames(1)
	_ok("① 点原框不弹条", not KeyboardBar.is_open())
	host.queue_free()
	await _frames(1)


func _bar_checks(tag: String, kb: float) -> void:
	var bar := KeyboardBar.current()
	_ok(tag + " 条开着", bar != null)
	if bar == null:
		return
	var vs := _vs()
	var p := bar.get_node("Bar") as Panel
	var bottom := p.position.y + p.size.y
	_ok(tag + " ★条底 = 键盘顶", absf(bottom - (vs.y - kb)) <= 0.5, "条底 %.1f 键盘顶 %.1f" % [bottom, vs.y - kb])
	_ok(tag + " 条整宽", absf(p.size.x - vs.x) <= 0.5 and p.position.x == 0.0, str(p.size))
	_ok(tag + " 条顶在屏内", p.position.y >= 0.0, str(p.position.y))
	var fs: int = bar.edit.get_theme_font_size("font_size")
	_ok(tag + " ★条里字 ≥ 28(原框 16~24)", fs >= 28, str(fs))
	_ok(tag + " 条里的框拿着焦点", bar.edit.has_focus())
	var keys := 0
	for k in p.get_children():
		if not (k is Button) or not (k as Button).visible or k.name == "Clear":
			continue
		keys += 1
		var r := (k as Control).get_global_rect()
		_ok(tag + " 键「%s」≥ 81 高、不在键盘下、不出屏" % (k as Button).text,
			r.size.y >= 81.0 and r.end.y <= vs.y - kb + 0.5 and r.position.x >= 0.0 and r.end.x <= vs.x + 0.5, str(r))
	_ok(tag + " 分母: 条上至少一颗键", keys >= 1, str(keys))


## ② 单行
func _t_single() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var e := LineEdit.new()
	e.text = "芝士奶盖"
	e.max_length = 16
	e.position = Vector2(500, 300); e.size = Vector2(300, 81)
	host.add_child(e)
	var got: Array = []
	KeyboardBar.vkb_override_vp = KB_ZH
	var took := KeyboardBar.attach(e, {"max_length": 0, "count_max": 8, "primary_cb": func(t: String) -> void: got.append(t),
		"extras": [["换一个", func(bar: KeyboardBar) -> void: bar.set_text("海盐柠檬")]]})
	_ok("② 有键盘 ⇒ 接管, 原框不再拿焦点", took and e.focus_mode == Control.FOCUS_NONE, str(e.focus_mode))
	_ok("② 会打中文的框去掉硬上限(拼音组字会吞字)", e.max_length == 0, str(e.max_length))
	_tap(e)
	await _frames(2)
	await _bar_checks("②中文", KB_ZH)
	var bar := KeyboardBar.current()
	if bar == null:
		host.queue_free()
		return
	_ok("② 条里预填原框的字", bar.get_text() == "芝士奶盖", bar.get_text())
	_ok("② 字数「4 / 8」", (bar.get_node("Bar/Count") as Label).text == "4 / 8", (bar.get_node("Bar/Count") as Label).text)
	## 换一档键盘高: 条跟着走
	KeyboardBar.vkb_override_vp = KB_EN
	await _frames(2)
	await _bar_checks("②英文", KB_EN)
	## 键盘高还没量到(0)⇒ 按上次量到的摆
	KeyboardBar.vkb_override_vp = 0.0
	await _frames(2)
	var p := bar.get_node("Bar") as Panel
	_ok("② 键盘高 0 ⇒ 按上次量到的(299)摆", absf(p.position.y + p.size.y - (_vs().y - KB_EN)) <= 0.5, str(p.position.y + p.size.y))
	KeyboardBar._last_kb = 0.0
	await _frames(2)
	var est := roundf(_vs().y * KeyboardBar.EST_KB)
	_ok("② 没量过 ⇒ 按 52% 估", absf(p.position.y + p.size.y - (_vs().y - est)) <= 0.5, "%.1f vs %.1f" % [p.position.y + p.size.y, _vs().y - est])
	KeyboardBar.vkb_override_vp = KB_ZH
	await _frames(2)
	## 打字(模拟系统键盘逐字送进来)⇒ 写回原框
	var le := bar.edit as LineEdit
	await _type("呀")
	_ok("② ★打字写回原框", e.text == "芝士奶盖呀", e.text)
	_ok("② 字数跟着变「5 / 8」", (bar.get_node("Bar/Count") as Label).text == "5 / 8")
	## 换一个 / 清空
	(bar.get_node("Bar/Extra0") as Button).pressed.emit()
	await _frames(1)
	_ok("② 换一个改了条里的字并写回", bar.get_text() == "海盐柠檬" and e.text == "海盐柠檬", e.text)
	_ok("② 改完光标在末尾", le.caret_column == le.text.length(), str(le.caret_column))
	(bar.get_node("Bar/Clear") as Button).pressed.emit()
	await _frames(1)
	_ok("② 清空 ⇒ 两边都空", bar.get_text() == "" and e.text == "", e.text)
	_ok("② 空了清空键藏起来", not (bar.get_node("Bar/Clear") as Control).visible)
	await _type("小龟")
	## 回车 = 主键: 收起 + 回调
	le.text_submitted.emit(le.text)
	await _frames(2)
	_ok("② 回车收起条", not KeyboardBar.is_open())
	_ok("② 回车回调拿到最终字", got == ["小龟"], str(got))
	_ok("② 收起后原框留着最后的字", e.text == "小龟", e.text)
	## 点条外 = 收起(不回调)
	_tap(e)
	await _frames(2)
	bar = KeyboardBar.current()
	_ok("② 再点原框又打开", bar != null)
	if bar != null:
		var out := bar.get_node("Outside") as Control
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		out.gui_input.emit(ev)
		await _frames(2)
		_ok("② 点条外 ⇒ 收起", not KeyboardBar.is_open())
		_ok("② 点条外不当提交", got.size() == 1, str(got))
	host.queue_free()
	await _frames(1)


## ③ 多行(问题反馈)
func _t_multi() -> void:
	KeyboardBar.vkb_override_vp = KB_ZH
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var dim: Control = PANEL.open(host)
	await _frames(2)
	var ed := dim.find_child(PANEL.EDIT, true, false) as TextEdit
	_ok("③ 反馈描述框接上了", ed != null and ed.has_meta("kb_bar") and ed.focus_mode == Control.FOCUS_NONE)
	## ⑤ 键 81 高, 框在屏内
	for n in [PANEL.SUBMIT, PANEL.CANCEL, PANEL.KIND_PREFIX + "crash"]:
		var b := dim.find_child(n, true, false) as Control
		if b == null:
			for c in dim.find_children(PANEL.KIND_PREFIX + "*", "Button", true, false):
				b = c
				break
		_ok("⑤ 「%s」≥ 81 高" % n, b != null and b.size.y >= 81.0, str(b.size if b != null else null))
	var box: Control = (dim.get_child(0) as Control)
	var br := box.get_global_rect()
	_ok("⑤ 反馈框在屏内", br.position.y >= 0.0 and br.end.y <= _vs().y, str(br))
	if ed == null:
		host.queue_free()
		return
	## 切到第二类, 再打开条
	var kinds := dim.find_children(PANEL.KIND_PREFIX + "*", "Button", true, false)
	if kinds.size() >= 2:
		(kinds[1] as Button).pressed.emit()
	_tap(ed)
	await _frames(2)
	await _bar_checks("③多行", KB_ZH)
	var bar := KeyboardBar.current()
	if bar == null:
		host.queue_free()
		return
	var tag := bar.get_node("Bar/Tag") as Label
	_ok("③ ★左上小签 = 当前选的类型", tag.visible and tag.text == str(PANEL.KINDS[1][1]), tag.text)
	var te := bar.edit as TextEdit
	var h1 := bar.bar_height()
	te.insert_text_at_caret("第一行\n第二行")
	await _frames(2)
	var h2 := bar.bar_height()
	_ok("③ 两行 ⇒ 条变高", h2 > h1, "%.0f → %.0f" % [h1, h2])
	te.insert_text_at_caret("\n三\n四\n五\n六")
	await _frames(2)
	var h3 := bar.bar_height()
	te.insert_text_at_caret("\n七")
	await _frames(2)
	_ok("③ 超过 3 行不再涨(在槽里滚)", absf(bar.bar_height() - h3) < 0.5 and h3 > h2, "%.0f / %.0f" % [h3, bar.bar_height()])
	await _bar_checks("③多行·涨高后", KB_ZH)
	_ok("③ 写回原框", ed.text == te.text, str(ed.text.length()))
	## 超 500 字截回
	bar.set_text("字".repeat(600))
	await _frames(1)
	_ok("③ ★超 500 字截回(条里与原框都是 500)", te.text.length() == 500 and ed.text.length() == 500, "%d / %d" % [te.text.length(), ed.text.length()])
	## 提交 = 弹框自己的提交: 空描述 ⇒ 弹框状态行报「请填写问题描述」
	bar.set_text("")
	(bar.get_node("Bar/Primary") as Button).pressed.emit()
	await _frames(2)
	var st := dim.find_child(PANEL.STATUS, true, false) as Label
	_ok("③ 条里「提交」走弹框的提交(空描述被拦)", not KeyboardBar.is_open() and st != null and st.text != "", st.text if st != null else "null")
	## 收起键
	_tap(ed)
	await _frames(2)
	bar = KeyboardBar.current()
	var opened := bar != null
	if opened:
		(bar.get_node("Bar/Extra0") as Button).pressed.emit()
		await _frames(2)
	_ok("③ 「收起」收起条", opened and not KeyboardBar.is_open(), "开了=%s 还开着=%s" % [opened, KeyboardBar.is_open()])
	host.queue_free()
	await _frames(1)


## ④ 四处真接上了
func _t_wired() -> void:
	KeyboardBar.vkb_override_vp = KB_ZH
	## 首次起名
	var fl: Node = (load("res://scenes/FirstLaunch.tscn") as PackedScene).instantiate()
	add_child(fl)
	await _frames(2)
	fl.call("open_naming")
	await _frames(2)
	var ne := fl.find_child(FLS.N_NAME_EDIT, true, false) as LineEdit
	_ok("④ 首次起名的名字框接上了", ne != null and ne.has_meta("kb_bar"))
	if ne != null:
		_tap(ne)
		await _frames(2)
		var bar := KeyboardBar.current()
		_ok("④ 起名条有「换一个」", bar != null and (bar.get_node("Bar/Extra0") as Button).text == P2C.NICK_REROLL)
		if bar != null:
			var before := bar.get_text()
			(bar.get_node("Bar/Extra0") as Button).pressed.emit()
			await _frames(1)
			_ok("④ 起名条「换一个」换了名字且写回", bar.get_text() != before and ne.text == bar.get_text(), "%s → %s" % [before, ne.text])
			bar.close()
	fl.queue_free()
	await _frames(1)
	## 设置: 改名 / 绑定屏
	var sc: Control = SET.new()
	add_child(sc)
	await _frames(2)
	sc.call("_open_rename_dialog")
	await _frames(2)
	var re := sc.find_child(SET.RENAME_EDIT, true, false) as LineEdit
	_ok("④ 设置改名框接上了", re != null and re.has_meta("kb_bar") and re.max_length == 0)
	sc.call("_close_rename_dialog")
	sc.call("_open_email_dialog", SB.FLOW_BIND)
	await _frames(2)
	for f in ["_nick_edit", "_email_edit", "_code_edit"]:
		var x = sc.get(f)
		_ok("④ 绑定屏 %s 接上了" % f, x is LineEdit and (x as LineEdit).has_meta("kb_bar"))
	var ce = sc.get("_code_edit")
	## 无头没有剪贴板(调了会刷 ERROR)⇒ 只在有剪贴板的显示服务器上量「粘贴」那一下; 取数字的纯函数在 ⑥ 量。
	var has_clip := DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	if ce is LineEdit:
		if has_clip:
			DisplayServer.clipboard_set("您的验证码：1234 5678")
		_tap(ce)
		await _frames(2)
		var bar := KeyboardBar.current()
		_ok("④ 验证码条有「粘贴」", bar != null and (bar.get_node("Bar/Extra0") as Button).text == "粘贴")
		if bar != null:
			if has_clip:
				(bar.get_node("Bar/Extra0") as Button).pressed.emit()
				await _frames(1)
				_ok("④ 粘贴只取数字并写回", bar.get_text() == "12345678" and (ce as LineEdit).text == "12345678", bar.get_text())
			bar.close()
	sc.queue_free()
	await _frames(1)
	## 好友 ID
	var page: Node = (load("res://scenes/Friends.tscn") as PackedScene).instantiate()
	add_child(page)
	await _frames(3)
	var ie := page.find_child("IdEdit", true, false) as LineEdit
	_ok("④ 好友 ID 框接上了, 英文键盘", ie != null and ie.has_meta("kb_bar") and ie.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS)
	if ie != null:
		_tap(ie)
		await _frames(2)
		var bar := KeyboardBar.current()
		_ok("④ 好友条主键是「查找」", bar != null and (bar.get_node("Bar/Primary") as Button).text == "查找", (bar.get_node("Bar/Primary") as Button).text if bar != null else "")
		if bar != null:
			bar.close()
	page.queue_free()
	await _frames(1)


## ⑥ 粘贴只取数字
func _t_paste() -> void:
	_ok("⑥ 粘贴取数字: 带空格换行", SET.code_digits(" 1234\n5678 ") == "12345678")
	_ok("⑥ 粘贴取数字: 带中文前缀", SET.code_digits("验证码：87654321。") == "87654321")
	_ok("⑥ 粘贴取数字: 没有数字 ⇒ 空", SET.code_digits("abc") == "")
