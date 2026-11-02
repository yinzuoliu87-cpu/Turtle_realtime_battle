extends Node
## 量登录墙上【渲染出来】的说明文字行数 —— 不是源码行数。
##
## ★为什么要单独量: `login_wall_body()` 一条串在窄屏上会自动折成两行,
##   而参考表里「说明文字行数」量的是**玩家眼睛看到几行**。
##   源码 2 条 ≠ 屏幕 2 行。照源码填进参考表就是编数。
##
## 判据: Label 且不是按钮/输入框的文字 ⇒ 算说明; 用 get_line_count() 拿真行数。

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for vp in [Vector2i(1280, 720), Vector2i(1560, 720)]:
		get_tree().root.content_scale_size = vp
		get_tree().root.size = vp
		var st := preload("res://scenes/Settings.tscn").instantiate()
		get_tree().root.add_child(st)
		for i in range(20):
			await get_tree().process_frame
		_dump("视口 %dx%d" % [vp.x, vp.y], st)
		st.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _dump(tag: String, st: Node) -> void:
	print("")
	print("══════ %s ══════" % tag)
	var layer = st.get("_email_layer")
	if layer == null:
		print("  墙没立起来 —— 这一轮不算数(分母为 0)")
		return
	var labels: Array = []
	_walk(layer, labels)
	var total := 0
	for l in labels:
		var n: int = l.get_line_count()
		total += n
		print("  %d 行 | %s" % [n, str(l.text).replace("\n", "⏎")])
	print("  ── 渲染说明行数合计 = %d (Label 个数 %d) ──" % [total, labels.size()])

func _walk(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label and (c as Label).visible and str((c as Label).text).strip_edges() != "":
			out.append(c)
		_walk(c, out)
