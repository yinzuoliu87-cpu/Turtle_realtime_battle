extends Node
## verify_contact_email.gd —— 设置页公开联系方式(2026-10-20 · App Store 审核指南 1.2)
##
## 方案书 `docs/plans/20261020-AppStore上架.md` D8: 1.2 用户生成内容四样之一「公开联系方式」。
##
## ① 设置页看得到邮箱: 按钮上的字就是 `CONTACT_EMAIL`, 在屏内、在右框竖向范围内
##    —— 桌面(三组) / 手机(两组, 注入 `display_row_override=0`) × 开发包 / 正式包, 四种都量
## ② 不压别的: 任意两个可点区域不重叠; 「已复制」那一格不压任何可点区域
## ③ 点按 ⇒ 复制: 注入剪贴板接收端, 点了之后收到的恰好是那个邮箱, 值栏出「已复制」;
##    点之前值栏是空的(分母: 否则「出现了已复制」是恒真)
## ④ 剪贴板不可用(无头 DisplayServer)且没注入 ⇒ **不许说已复制**
## ⑤ 与隐私政策抬头的联系方式是同一个地址(两处写的不一样 = 审核员看到两个邮箱)

const SET := preload("res://scripts/scenes/SettingsScene.gd")
const PRIVACY := "res://docs/隐私政策.md"

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


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _nested(a: Node, b: Node) -> bool:
	var p := a.get_parent()
	while p != null:
		if p == b:
			return true
		p = p.get_parent()
	return false


## 设计框(1280×720)坐标: `UIFrame.attach` 把整页收进一个框并按真实视口居中/缩放,
##   全局坐标随无头视口尺寸变 ⇒ 一律换算回按钮所在那个框的局部坐标再量。
var _frame: CanvasItem = null


func _dr(c: Control) -> Rect2:
	if _frame == null:
		return c.get_global_rect()
	return _frame.get_global_transform().affine_inverse() * c.get_global_rect()


func _ready() -> void:
	await get_tree().process_frame
	print("=== 设置页联系方式 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	## ①② 四种版式
	for disp in [1, 0]:
		for rel in [false, true]:
			var tag := "%s/%s" % ["桌面" if disp == 1 else "手机", "正式包" if rel else "开发包"]
			SET.display_row_override = disp
			SET.release_override = rel
			var sc: Control = SET.new()
			add_child(sc)
			await _frames(3)
			SET.display_row_override = -1
			SET.release_override = false
			## 分母: 版式注入真的生效了(手机没有「显示」分段钮, 桌面有)
			var seg = sc.find_child(SET.SEG_DISPLAY + "Window", true, false)
			_ok("[%s] ★分母: 版式注入生效(「显示」行%s)" % [tag, "在" if disp == 1 else "不在"],
				(seg != null) == (disp == 1))
			var b = sc.find_child(SET.CONTACT_BTN, true, false)
			_ok("[%s] ★设置页有联系邮箱按钮, 字就是邮箱" % tag,
				b is Button and (b as Button).text == SET.CONTACT_EMAIL and (b as Button).is_visible_in_tree(),
				str(b.text if b is Button else b))
			if not (b is Button):
				sc.queue_free()
				continue
			_frame = (b as Button).get_parent() as CanvasItem
			var r: Rect2 = _dr(b as Button)
			_ok("[%s] 按钮在右框竖向范围内(104..626)" % tag,
				r.position.y >= 104.0 - 0.5 and r.end.y <= 626.0 + 0.5, str(r))
			_ok("[%s] 按钮在 1280×720 内" % tag, Rect2(0, 0, 1280, 720).encloses(r), str(r))
			## 同一行左名「联系我们」: 竖向中线与按钮对齐(±2)
			var lbl_ok := false
			for n in _walk(sc):
				if n is Label and (n as Label).text == "联系我们":
					var lr: Rect2 = _dr(n as Label)
					lbl_ok = absf(lr.get_center().y - r.get_center().y) <= 2.0 and lr.end.x <= r.position.x
			_ok("[%s] 左名「联系我们」与按钮同一行、在它左边" % tag, lbl_ok)
			## 可点区域两两不重叠(穷举)
			var hits: Array = []
			for n in _walk(sc):
				if not (n is Control) or not (n as Control).is_visible_in_tree():
					continue
				var c := n as Control
				var cr: Rect2 = _dr(c)
				if cr.size.x <= 0.5 or cr.size.y <= 0.5 or (cr.size.x >= 1279.0 and cr.size.y >= 719.0):
					continue
				if (c is BaseButton and not (c as BaseButton).disabled) \
						or (not (c is BaseButton) and c.mouse_filter == Control.MOUSE_FILTER_STOP):
					hits.append(c)
			var bad: Array = []
			for i in range(hits.size()):
				for j in range(i + 1, hits.size()):
					if _nested(hits[i], hits[j]) or _nested(hits[j], hits[i]):
						continue
					var it: Rect2 = _dr(hits[i] as Control).intersection(_dr(hits[j] as Control))
					if it.size.x > 0.5 and it.size.y > 0.5:
						bad.append("%s×%s" % [hits[i].name, hits[j].name])
			print("  [分母] [%s] 可点区域 %d 个" % [tag, hits.size()])
			_ok("[%s] ★分母: 扫到可点区域 ≥5" % tag, hits.size() >= 5, str(hits.size()))
			_ok("[%s] ★★任意两个可点区域不重叠" % tag, bad.is_empty(), " / ".join(bad))
			var done = sc.find_child(SET.CONTACT_DONE, true, false)
			_ok("[%s] 值栏「已复制」那一格在, 点之前是空的" % tag,
				done is Label and (done as Label).text == "", str(done))
			if done is Label:
				var dr: Rect2 = _dr(done as Label)
				var over: Array = []
				for h in hits:
					var it2: Rect2 = _dr(h as Control).intersection(dr)
					if it2.size.x > 0.5 and it2.size.y > 0.5:
						over.append(str(h.name))
				_ok("[%s] 值栏不压任何可点区域, 且在右框右沿(1186)以内" % tag,
					over.is_empty() and dr.end.x <= 1186.5, "%s %s" % [str(over), str(dr)])
			sc.queue_free()
			await _frames(1)

	## ③ 点按 ⇒ 复制
	var sc2: Control = SET.new()
	add_child(sc2)
	await _frames(2)
	var got: Array = []
	SET.clipboard_sink = func(s: String) -> void: got.append(s)
	var b2 = sc2.find_child(SET.CONTACT_BTN, true, false)
	var d2 = sc2.find_child(SET.CONTACT_DONE, true, false)
	if b2 is Button and d2 is Label:
		_ok("★分母: 点之前没有复制过、值栏为空", got.is_empty() and (d2 as Label).text == "")
		(b2 as Button).pressed.emit()
		await _frames(1)
		_ok("★★点按 ⇒ 剪贴板收到的恰好是那个邮箱", got == [SET.CONTACT_EMAIL], str(got))
		_ok("★★点按 ⇒ 值栏出「已复制」", (d2 as Label).text == SET.CONTACT_COPIED and SET.CONTACT_COPIED == "已复制",
			(d2 as Label).text)
	else:
		_ok("点按那一节的被测对象在场", false, "%s %s" % [str(b2), str(d2)])
	SET.clipboard_sink = Callable()
	sc2.queue_free()

	## ④ 剪贴板不可用 ⇒ 不许说已复制
	var sc3: Control = SET.new()
	add_child(sc3)
	await _frames(2)
	var has_cb := DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	var b3 = sc3.find_child(SET.CONTACT_BTN, true, false)
	var d3 = sc3.find_child(SET.CONTACT_DONE, true, false)
	if b3 is Button and d3 is Label:
		(b3 as Button).pressed.emit()
		await _frames(1)
		if has_cb:
			_ok("系统剪贴板可用 ⇒ 已复制且剪贴板里就是邮箱",
				(d3 as Label).text == "已复制" and DisplayServer.clipboard_get() == SET.CONTACT_EMAIL)
		else:
			_ok("★系统剪贴板不可用(无头)⇒ 不说「已复制」", (d3 as Label).text == "", (d3 as Label).text)
	else:
		_ok("剪贴板不可用那一节的被测对象在场", false)
	sc3.queue_free()

	## ⑤ 与隐私政策同一个地址
	var f := FileAccess.open(PRIVACY, FileAccess.READ)
	var head := ""
	if f != null:
		for i in range(6):
			head += f.get_line() + "\n"
		f.close()
	_ok("★分母: 读到隐私政策抬头", head.find("隐私政策") >= 0, str(head.length()))
	_ok("★隐私政策抬头的联系方式 == 设置页邮箱",
		head.find("联系方式：" + SET.CONTACT_EMAIL) >= 0, head.strip_edges().substr(0, 120))

	_finish()


func _finish() -> void:
	print("=== 共 %d 条 ===" % _n)
	if _fail == 0 and _n >= 20:
		print("ALL PASS")
	else:
		print("FAIL x%d (共 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
