extends Node
## verify_battle_font_bundled.gd —— 对局里的飘字 / 3D 标签不靠系统字体补字(2026-11-15)。
## 用户 11-15:「在我的苹果手机上显示什么那些对局内的那个…字体啥的，全部会变成乱码，这个东西一直没解决。」
## 根因: 飘字字体原来直接是 m6x11(只有英文数字), 中文飘字(闪避 / 亡灵 / 眩晕…)和 3D 标签(♠ / ♪)缺的字全靠系统字体补;
##   电脑上系统自带中文字体补上了, iOS 上 Godot 取不到系统字体(FontKit 头注) ⇒ 乱码。
## 判据(只认打包进游戏的字体, 不算系统字体):
##   ① 分母: 从代码里收集所有 `_float_text(` 调用里写死的非 ASCII 字符 + 3D 标签的 ♠ / ♪(≥ 20 个不同的字)
##   ② ★每一个字在 `FontKit.bundled_pixel_chain()`(m6x11 → 思源黑体 → Noto Emoji)里都有字形
##   ③ 反证: m6x11 单独确实没有中文(否则 ② 是空检查)
##   ④ 接线: 对局场景的飘字字体就是这条链; 三个 3D 标签都设了它
## 反向验证(11-15): `_float_num_font` 改回 m6x11 ⇒ ④ 红; 链里拿掉思源黑体 ⇒ ② 红(列出缺的字)。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _scan(dir: String, chars: Dictionary) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(dir.path_join(f))
		for line in src.split("\n"):
			if line.find("_float_text(") < 0 or line.strip_edges().begins_with("#") or line.strip_edges().begins_with("func "):
				continue
			var code: String = line.split("#")[0]
			var re := RegEx.new()
			re.compile("\"([^\"]*)\"")
			for m in re.search_all(code):
				for ch in m.get_string(1):
					if ch.unicode_at(0) > 127:
						chars[ch] = true
	for d in da.get_directories():
		_scan(dir.path_join(d), chars)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 对局飘字 / 3D 标签不靠系统字体 ===")
	var chars := {}
	_scan("res://scripts", chars)
	for c in ["♠", "♪"]:
		chars[c] = true
	_ok("① 分母: 飘字 / 标签里写死的非 ASCII 字 %d 个(≥ 20)" % chars.size(), chars.size() >= 20, "".join(chars.keys().slice(0, 40)))
	var chain: Font = FontKit.bundled_pixel_chain()
	var miss: Array = []
	for c in chars.keys():
		if not chain.has_char(str(c).unicode_at(0)):
			miss.append(c)
	_ok("② ★每个字在打包字体链里都有字形(缺 %d 个)" % miss.size(), miss.is_empty(), "".join(miss))
	var m6: Font = load("res://assets/fonts/m6x11.ttf")
	_ok("③ 反证: m6x11 单独没有「闪」「亡」(所以原来中文全靠系统字体补)", not m6.has_char("闪".unicode_at(0)) and not m6.has_char("亡".unicode_at(0)))
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var ff: Font = s._vfx._float_num_font()
	_ok("④ 对局飘字字体就是打包字体链", ff == chain and ff.has_char("闪".unicode_at(0)))
	s.queue_free()
	await get_tree().process_frame
	for rel in ["res://scripts/systems/equip/hookbomb_system.gd", "res://scripts/systems/skills/gambler_system.gd", "res://scripts/systems/trainer/trainer_system.gd"]:
		var src := FileAccess.get_file_as_string(rel)
		_ok("④ %s 的 3D 标签设了打包字体链" % rel.get_file(), src.contains(".font = FontKit.bundled_pixel_chain()"))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
