extends Node
## 探针: 登录墙换框之后「文字压边带」到底越在哪一边、越多少。
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const UIC := preload("res://tests/verify_ui_consistency.gd")


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = ""
	for _i in range(4):
		await get_tree().process_frame
	var st = SET.new()
	st.acct_override = 1
	add_child(st)
	for _i in range(20):
		await get_tree().process_frame
	var aud = UIC.new()
	add_child(aud)
	await get_tree().process_frame
	## 找那个带贴图的框, 打它的带宽与内容区
	var st_arr: Array = [st]
	while not st_arr.is_empty():
		var n = st_arr.pop_back()
		if n is Control and (n as Control).has_theme_stylebox_override("panel"):
			var sb = (n as Control).get_theme_stylebox("panel")
			if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
				var bb: float = aud._band_of((sb as StyleBoxTexture).texture)
				var r: Rect2 = (n as Control).get_global_rect()
				print("[探针] 框 %s  rect=%s  量到的边带=%.1f" % [n.get_class(), str(r), bb])
				print("       内容区 = %s" % str(Rect2(r.position + Vector2(bb, bb), r.size - Vector2(bb, bb) * 2.0)))
		for ch in n.get_children():
			st_arr.append(ch)
	## 打每个 Label 的 ink rect
	var st2: Array = [st]
	while not st2.is_empty():
		var n2 = st2.pop_back()
		if n2 is Label and str((n2 as Label).text).strip_edges() != "":
			var ir: Rect2 = aud._ink_rect(n2 as Label)
			print("[探针] Label 「%s」 控件=%s  ink=%s" % [
				str((n2 as Label).text).substr(0, 14).replace("\n", "/"),
				str((n2 as Label).get_global_rect()), str(ir)])
		for ch2 in n2.get_children():
			st2.append(ch2)
	get_tree().quit(0)
