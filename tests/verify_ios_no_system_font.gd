extends Node
## verify_ios_no_system_font.gd — iOS 上回退链里不许有系统字体(2026-10-13 内测)
##
## 由来: iOS 内测玩家每开一个界面上报几十条 `FreeType: Error loading font: ''`(两个号 3 小时 161 次)。
##   主题回退链里的 SystemFont 在 iOS 上取不到(空路径), Noto SC 里没有的字形每个字号都去问它一次。
## 判据(FontKit.platform_override 冒充 iOS; 桌面真跑不到那条分支):
##   ① 分母: 主题默认字体回退链里本来有 SystemFont
##   ② 冒充 iOS 后剥掉 ⇒ 0 个 SystemFont, 打包 Noto SC 与 Noto Emoji 仍在
##   ③ 匹配页 / 主菜单自己造的粗体回退链里也没有 SystemFont
##   ④ 桌面(不冒充)时匹配页粗体仍挂 SystemFont(不许把桌面的雅黑 / 彩色 emoji 一起拿掉)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_ios_no_system_font.tscn

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _count_sys(f: Font) -> int:
	var n := 0
	if f == null:
		return 0
	for fb in f.fallbacks:
		if fb is SystemFont:
			n += 1
	if f is FontVariation and (f as FontVariation).base_font != null:
		n += _count_sys((f as FontVariation).base_font)
	return n


func _paths(f: Font) -> Array:
	var out: Array = []
	for fb in f.fallbacks:
		if fb is FontFile:
			out.append(str((fb as FontFile).resource_path))
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== iOS 上回退链里没有系统字体 ===")
	var th: Theme = ThemeDB.get_project_theme()
	_ok("① 分母: 拿到项目主题与默认字体", th != null and th.default_font != null)
	if th == null or th.default_font == null:
		_done()
		return
	var f: Font = th.default_font.duplicate(true)
	var before := _count_sys(f)
	_ok("① 分母: 主题默认字体回退链里本来有 SystemFont", before >= 1, "n=%d" % before)

	FontKit.platform_override = "iOS"
	var removed := FontKit.strip_from(f)
	_ok("② ★冒充 iOS 剥掉后回退链里 0 个 SystemFont", _count_sys(f) == 0, "剩 %d" % _count_sys(f))
	_ok("② 剥掉的个数 = 原来的个数", removed == before, "%d vs %d" % [removed, before])
	var ps := _paths(f)
	_ok("② 打包 Noto SC 仍在", ps.has("res://assets/fonts/NotoSansSC-Regular.otf"), str(ps))
	_ok("② 打包 Noto Emoji 仍在", ps.has("res://assets/fonts/NotoEmoji-Regular.ttf"), str(ps))

	var mm = load("res://scripts/scenes/MatchmakingScene.gd").new()
	var mf: Font = mm.call("_bold_font")
	_ok("③ ★冒充 iOS: 匹配页粗体回退链里没有 SystemFont", _count_sys(mf) == 0, "n=%d" % _count_sys(mf))
	mm.free()
	var menu = load("res://scripts/scenes/MainMenuScene.gd").new()
	var bf: Font = menu.call("_bold_font")
	_ok("③ ★冒充 iOS: 主菜单粗体回退链里没有 SystemFont", _count_sys(bf) == 0, "n=%d" % _count_sys(bf))
	menu.free()

	FontKit.platform_override = "Windows"
	var mm2 = load("res://scripts/scenes/MatchmakingScene.gd").new()
	var mf2: Font = mm2.call("_bold_font")
	_ok("④ 桌面: 匹配页粗体仍挂 SystemFont(雅黑 / 彩色 emoji 不许一起拿掉)", _count_sys(mf2) >= 1, "n=%d" % _count_sys(mf2))
	mm2.free()
	FontKit.platform_override = ""
	_done()


func _done() -> void:
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — iOS 上回退链里没有系统字体 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
