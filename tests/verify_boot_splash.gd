extends Node
## verify_boot_splash.gd —— 启动时不出 Godot 标(用户 2026-10-28「不是它会弹那个 godot 引擎吗？把这个东西去掉」)
##
## ① 引擎启动画面不画图(show_image = false), 只铺底色
## ② boot_splash/image 指向一张存在的图 —— ★iOS 启动屏(Launch Screen.storyboard)不看 show_image:
##    没设 storyboard 自定义图时用 boot_splash/image, 这一项再空就用引擎自带的 Godot 标
##    (Godot 4.6.3 platform/ios/export/export_plugin.cpp 约 165-190 行)。
## ③ 那张图整张是纯色, 且就是底色 ⇒ iPhone 启动屏上看到的是一块底色, 没有任何标

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	print("=== 启动画面不出 Godot 标 ===")
	var show = ProjectSettings.get_setting("application/boot_splash/show_image", true)
	_ok("① ★启动画面不画图", show == false, str(show))
	var path := str(ProjectSettings.get_setting("application/boot_splash/image", ""))
	_ok("② ★boot_splash/image 设了(否则 iOS 启动屏回落成 Godot 标)", path != "", path)
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	var img: Image = null
	if path != "" and FileAccess.file_exists(path):
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	_ok("② 那张图读得到", img != null and not img.is_empty(), path)
	if img != null and not img.is_empty():
		var off := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if absf(c.r - bg.r) > 1.5 / 255.0 or absf(c.g - bg.g) > 1.5 / 255.0 or absf(c.b - bg.b) > 1.5 / 255.0 or c.a < 0.99:
					off += 1
		_ok("③ ★整张都是底色(%d 像素)" % (img.get_width() * img.get_height()), off == 0, "不是底色的像素 %d" % off)
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
