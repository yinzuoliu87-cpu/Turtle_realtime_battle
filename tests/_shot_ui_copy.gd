extends Node
## _shot_ui_copy.gd —— 全游戏文案走查台(DEV 工具, `_` 开头不被门禁自动发现)。方案书 docs/plans/20261101f-全游戏文案按商业口吻.md。
## 每一屏(清单在 `_ui_copy_screens.gd`)按两种比例各走一遍, 把屏上**看得见的每一句**写成 <名字>_<比例>.txt;
## 开窗口跑时顺手存 <名字>_<比例>.png。无头也能跑(只出文字, 量的是 Control 的矩形, 不需要渲染)。
## 末尾附「版面」: 被截 / 出屏 / 两句互相压住(与门禁同一把尺 `_ui_copy_screens.layout_issues`)。
##
##   UI_COPY_OUT=<目录> [UI_COPY_ONLY=menu_tue,shop] bash godot-quiet.sh res://tests/_shot_ui_copy.tscn --quit-after 99999
##   (要图: WINDOW=1 ... --position 2000,80)

const SC := preload("res://tests/_ui_copy_screens.gd")
const TP := preload("res://tests/_finals_text_probe.gd")

const SIZES := [["phone", Vector2i(1560, 720)], ["ipad", Vector2i(960, 720)]]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	var out := OS.get_environment("UI_COPY_OUT")
	if out == "":
		out = "user://ui_copy"
	DirAccess.make_dir_recursive_absolute(out)
	var only := OS.get_environment("UI_COPY_ONLY")
	var want: Array = SC.names() if only == "" else Array(only.split(","))
	var headless := DisplayServer.get_name() == "headless"
	for sz in SIZES:
		get_window().size = sz[1]
		for _i in range(3):
			await get_tree().process_frame
		for nm in want:
			SC.setup(str(nm))
			var n: Node = SC.make(str(nm))
			add_child(n)
			await SC.settle(1.6)
			await SC.post(str(nm), n)
			## 切页签会重播列表 / 详情滑入(延迟 0.25 + 0.42 秒, 带回弹): 等 0.5 秒量到的是回弹到一半的位置
			await SC.settle(1.2)
			var vp := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			var items := TP.collect(get_tree().root, vp)
			var lay := SC.layout_issues(get_tree().root, items, vp)
			var txt := TP.dump(items) + "\n\n## 版面\n" + "\n".join(PackedStringArray(lay))
			var f := FileAccess.open("%s/%s_%s.txt" % [out, nm, sz[0]], FileAccess.WRITE)
			f.store_string(txt)
			f.close()
			if not headless:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, nm, sz[0]])
			print("[UICOPY] %s %s 句数 %d 版面 %d" % [nm, sz[0], items.size(), lay.size()])
			SC.drop(n)
			for _i in range(3):
				await get_tree().process_frame
	SC.teardown()
	get_tree().quit(0)
