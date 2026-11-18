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
	var n_items := 0
	for nm in want:
		SC.setup(str(nm))
		var n: Node = SC.make(str(nm))
		add_child(n)
		await SC.settle(1.6)
		await SC.post(str(nm), n)
		await SC.settle(1.2)
		var vp := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		for it in TP.collect(get_tree().root, vp):
			n_items += 1
			var t := str(it["text"])
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
	print("ALL DONE 屏 %d · 句 %d · 含汉字(去重) %d → %s" % [want.size(), n_items, rows.size(), OUT])
	get_tree().quit(0)
