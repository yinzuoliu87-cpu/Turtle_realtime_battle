extends Node
## DEV 探针: 登录墙的遮罩到底盖住了什么。★不是门禁(下划线开头 ⇒ 不被自动发现)。
##
## 起因: 实拍(2026-09-24 v0.19.440 真实开机)里「调试场」「重置所有存档」两个按钮
## 看着像没被墙压暗。但**在同一张图里放大是量不出亮度的** —— 手上没有"没被压暗的
## 那个按钮"当参照。所以这里做 A/B: 同一个按钮、同一个场景, 只差墙开/墙关,
## 直接读**视口像素**。
##
## ★必须有真窗口(headless 抓不到视口纹理) ⇒ 用 `--position 5000,5000` 挪到屏幕外。
## ★必须用真场景 `scenes/Settings.tscn`(根带全屏锚点)并挂进 `get_tree().root`,
##   裸 `SET.new()` 出来的是 0×0 的 Control, 量出来全是探针自己造的假象。
##
## 跑法: WALL=1 <godot> --path . res://tests/_probe_wall_cover.tscn \
##         --position 5000,5000 --resolution 1280x720 --audio-driver Dummy --quit-after 240

const SB := preload("res://scripts/net/supabase.gd")
const TARGET := "重置所有存档"


func _ready() -> void:
	await get_tree().process_frame
	var wall := OS.get_environment("WALL") == "1"
	## 墙开: 后端"配了" + 没绑邮箱。墙关: 绑了邮箱(同一份代码的另一支)
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._reset_auth_for_test()
	GameState.test_mode = true
	GameState.account_id = "uid-probe"
	GameState.account_email = "" if wall else "bound@x.co"

	var st = load("res://scenes/Settings.tscn").instantiate()
	get_tree().root.add_child(st)
	## ★等落位: 少等几帧会拍到还没铺开的版面(本仓踩过, 140 帧那次拍出四个木牌重叠)
	for _i in 30:
		await get_tree().process_frame

	print("=== 登录墙 A/B (WALL=%s) ===" % ("1 墙开" if wall else "0 墙关"))
	print("  视口 = ", get_window().size, "   后端 enabled = ", SB.enabled())
	var dim = st._email_layer
	var has_wall: bool = dim != null and is_instance_valid(dim)
	print("  墙在不在 = ", has_wall)
	if has_wall:
		var c := dim as Control
		print("  遮罩 rect = ", c.get_global_rect(), "  mouse_filter = ", c.mouse_filter,
			"  是不是最后一个子节点 = ", st.get_children().back() == dim)

	## 找到那个按钮(整棵子树里搜文字), 打它的 rect
	var lab := _find_label(st, TARGET)
	if lab == null:
		print("  ★没找到「%s」—— 探针失去意义, 不要把这当成结论" % TARGET)
		get_tree().quit(1)
		return
	var r: Rect2 = lab.get_global_rect()
	print("  「%s」 rect = %s" % [TARGET, str(r)])

	## ★读真实视口像素
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	print("  视口纹理 = %dx%d" % [img.get_width(), img.get_height()])
	_avg("按钮上的木框", img, Rect2(r.position + Vector2(20, 8), Vector2(60, 30)))
	_avg("页面背景(左上角)", img, Rect2(Vector2(8, 200), Vector2(60, 40)))
	get_tree().quit(0)


## 打一块矩形的平均 RGB + 亮度。★量平均不量极值(极值一个高光像素就骗过去了)。
func _avg(tag: String, img: Image, r: Rect2) -> void:
	var n := 0
	var acc := Vector3.ZERO
	var y := int(r.position.y)
	while y < int(r.position.y + r.size.y):
		var x := int(r.position.x)
		while x < int(r.position.x + r.size.x):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var c := img.get_pixel(x, y)
				acc += Vector3(c.r, c.g, c.b)
				n += 1
			x += 1
		y += 1
	if n == 0:
		print("    %-14s ★采到 0 个像素(矩形在视口外) —— 空检查" % tag)
		return
	acc /= float(n)
	var lum: float = 0.2126 * acc.x + 0.7152 * acc.y + 0.0722 * acc.z
	print("    %-14s RGB=(%.3f, %.3f, %.3f)  亮度=%.4f  (分母 %d 像素)" % [
		tag, acc.x, acc.y, acc.z, lum, n])


func _find_label(root: Node, needle: String) -> Label:
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_front()
		if n is Label and str((n as Label).text).find(needle) >= 0:
			return n as Label
		for k in (n as Node).get_children():
			stack.append(k)
	return null
