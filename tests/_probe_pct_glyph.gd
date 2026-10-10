extends Control
## _probe_pct_glyph.gd — 探针: 「%」与「×」在游戏字号下的像素对比(非 headless, 截窗口)
## 跑法: <godot> --audio-driver Dummy --resolution 1280x720 --position 2000,80 --path . res://tests/_probe_pct_glyph.tscn
## 环境变量 PCT_OUT=<png 路径>  (默认 C:/tmp/agG/pct.png)
##          PCT_ALT=<a.ttf;b.ttf>  额外按同样导入参数(无 AA/无 hinting)载入候选 ttf 逐行对比

const SIZES := [13, 15, 18, 22, 24]
const SAMPLE := "25% 30×攻击力 %× x 100% 1.5%"

func _mk_alt(path: String) -> Font:
	var ff := FontFile.new()
	ff.load_dynamic_font(path)
	ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	ff.hinting = TextServer.HINTING_NONE
	ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	ff.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]
	return ff

func _ready() -> void:
	var th: Theme = load("res://assets/themes/default_theme.tres")
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var m6: FontFile = load("res://assets/fonts/m6x11.ttf")
	for cp in [0x25, 0xD7]:
		print("[who] U+%04X m6x11.has_char=%s" % [cp, m6.has_char(cp)])
	var fonts := [["theme", th.default_font]]
	for p in OS.get_environment("PCT_ALT").split(";", false):
		fonts.append([p.get_file(), _mk_alt(p)])
	var x := 8.0
	for pair in fonts:
		var y := 8.0
		var cap := Label.new()
		cap.text = str(pair[0])
		cap.position = Vector2(x, y)
		cap.add_theme_font_size_override("font_size", 13)
		cap.modulate = Color(1, 0.8, 0.3)
		add_child(cap)
		y += 22
		for s in SIZES:
			var l := Label.new()
			l.add_theme_font_override("font", pair[1])
			l.add_theme_font_size_override("font_size", s)
			l.text = "%d %s" % [s, SAMPLE]
			l.position = Vector2(x, y)
			add_child(l)
			y += s * 1.8
		x += 400
		if x > 1200:
			break
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("PCT_OUT")
	if out == "": out = "C:/tmp/agG/pct.png"
	img.save_png(out)
	print("[saved] ", out, " ", img.get_size())
	get_tree().quit()
