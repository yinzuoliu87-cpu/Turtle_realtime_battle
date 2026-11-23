extends Node
## 英文版走屏(2026-11-18 · 方案书 docs/plans/20261118c-语言选项.md §4.3 / §6):
## 用 verify_ui_copy 的同一套 52 屏(tests/_ui_copy_screens.gd)与可见文字采集器(tests/_finals_text_probe.gd),
## 在【英文】下逐屏走一遍, 把屏上还含汉字的每一句记下来 —— 既是翻译的待办清单, 也是验收口径(P1/P2: 含汉字的句数 = 0)。
##
## 输出: .out/i18n/visible_zh.tsv(句子 \t 屏 \t 节点路径)+ 末行「ALL DONE 屏数 句数 含汉字 N」。
## 跑法: TURTLE_LANG=en APPDATA=<临时> XDG_DATA_HOME=<临时> TURTLE_SUPABASE=" " SHIP=1 \
##        <godot> --headless --audio-driver Dummy --path . res://tests/_i18n_screens.tscn --quit-after 300000
##       I18N_ONLY=a,b 只走这几屏; I18N_SIZE=phone|ipad 只走一种比例(默认只走手机, 省时间)。

const SC := preload("res://tests/_ui_copy_screens.gd")
const TP := preload("res://tests/_finals_text_probe.gd")
const SIZES := {"phone": Vector2i(1560, 720), "ipad": Vector2i(960, 720)}
const OUT := "res://.out/i18n/visible_zh.tsv"
const OUT_OVER := "res://.out/i18n/overflow.tsv"

var _han := RegEx.new()


func _ready() -> void:
	_han.compile("[\\x{4e00}-\\x{9fff}]")
	await get_tree().process_frame
	var only := OS.get_environment("I18N_ONLY")
	var want: Array = SC.names() if only == "" else Array(only.split(","))
	var size_key := OS.get_environment("I18N_SIZE")
	if not SIZES.has(size_key):
		size_key = "phone"
	print("[i18n] 语言 %s · %d 屏 · %s" % [TranslationServer.get_locale(), want.size(), size_key])
	get_window().size = SIZES[size_key]
	for _i in range(3):
		await get_tree().process_frame
	var seen := {}
	var rows: Array = []
	var over_seen := {}
	var over_rows: Array = []
	var n_items := 0
	for nm in want:
		SC.setup(str(nm))
		var n: Node = SC.make(str(nm))
		add_child(n)
		await SC.settle(1.6)
		await SC.post(str(nm), n)
		await SC.settle(1.2)
		## 开窗口跑时每屏存一张(I18N_SHOT=1; 无头没有画面, 不存)
		if OS.get_environment("I18N_SHOT") == "1" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var sd := "res://.out/i18n/shots"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sd))
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [sd, str(nm), int(get_viewport().get_visible_rect().size.x)])
		var vp := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		for it in TP.collect(get_tree().root, vp):
			n_items += 1
			var t := str(it["text"])
			## 控件自动翻译: 屏上显示的是 atr(text), 不是 text 本身(采集器读的是 text)
			var nd := get_tree().root.get_node_or_null(NodePath(str(it["path"])))
			if nd != null and nd.can_auto_translate():
				t = String(nd.atr(t))
			## 溢出(2026-11-23): 不折行的 Label / Button, 一行字的宽度超过控件宽 ⇒ 记下来(英文比中文长, 无头也能量)
			var ow := _overflow_px(nd, t)
			if ow > 2.0:
				var ok_key := "%s|%s" % [t, str(nm)]
				if not over_seen.has(ok_key):
					over_seen[ok_key] = true
					over_rows.append("%d\t%s\t%s\t%s" % [int(ow), t.replace("\n", "⏎").replace("\t", " "), str(nm), str(it["path"])])
			if _han.search(t) == null:
				continue
			if seen.has(t):
				continue
			seen[t] = true
			rows.append("%s\t%s\t%s" % [t.replace("\n", "⏎").replace("\t", " "), str(nm), str(it["path"])])
		SC.drop(n)
		for _i in range(3):
			await get_tree().process_frame
	SC.teardown()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.out/i18n"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	for r in rows:
		f.store_line(r)
	f.close()
	var f2 := FileAccess.open(OUT_OVER, FileAccess.WRITE)
	for r in over_rows:
		f2.store_line(r)
	f2.close()
	print("溢出(超出控件宽 > 2px) %d 处 → %s" % [over_rows.size(), OUT_OVER])
	print("ALL DONE 屏 %d · 句 %d · 含汉字(去重) %d → %s" % [want.size(), n_items, rows.size(), OUT])
	get_tree().quit(0)


## 一行字超出控件宽多少像素(不折行、不裁剪省略的 Label / Button; 其余返回 0)。
func _overflow_px(nd: Node, t: String) -> float:
	if nd == null or not (nd is Label or nd is Button):
		return 0.0
	var c := nd as Control
	if nd is Label:
		var lb := nd as Label
		if lb.autowrap_mode != TextServer.AUTOWRAP_OFF or lb.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or lb.clip_text:
			return 0.0
	if nd is Button:
		var bt := nd as Button
		if bt.clip_text or bt.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or bt.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return 0.0
	var f: Font = c.get_theme_font("font")
	var fs: int = c.get_theme_font_size("font_size")
	if f == null:
		return 0.0
	var w := 0.0
	for line in t.split("
"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	var avail := c.size.x
	if nd is Button:
		var sb: StyleBox = c.get_theme_stylebox("normal")
		if sb != null:
			avail -= sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
		var ic: Texture2D = (nd as Button).icon
		if ic != null:
			avail -= ic.get_width()
	return w - avail
