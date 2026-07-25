class_name LayoutEditor
extends RefCounted
## 选龟页·F9布局编辑器(dev·拖坐标/导出·_input/_rl_val/_rl_line和坐标态留主场景)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _toggle_layout_edit() -> void:
	host._edit_mode = not host._edit_mode
	if host._edit_mode:
		_build_edit_layer()
		host._flash_status("🔧 布局编辑开: 拖=移动 · 右下角=缩放 · F10导出坐标 · 再按F9关")
	else:
		if is_instance_valid(host._edit_layer):
			host._edit_layer.queue_free()
		host._edit_layer = null
		host._edit_handles.clear()
		host._drag_key = ""
		host._flash_status("布局编辑关")


func _build_edit_layer() -> void:
	if is_instance_valid(host._edit_layer):
		host._edit_layer.queue_free()
	host._edit_handles.clear()
	host._edit_layer = Control.new()
	host._edit_layer.name = "EditLayer"
	host._edit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	host._edit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._edit_layer.z_index = 4096   # 盖在 UI/Root 之上
	var ui = host.get_node_or_null("UI")
	(ui if ui != null else self).add_child(host._edit_layer)
	var tip = Label.new()
	tip.text = "布局编辑 · 拖绿框=移动 · 拖右下角黄块=缩放 · 拖完点右上「保存坐标」→"
	tip.add_theme_color_override("font_color", Color("#ffe6b0"))
	tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	tip.add_theme_constant_override("outline_size", 4)
	tip.add_theme_font_size_override("font_size", 13)
	tip.position = Vector2(12, 4)
	host._edit_layer.add_child(tip)
	# 右上角大「保存坐标」按钮 — 点一下写文件, 我直接读, 你不用抄任何东西
	var save_btn = Button.new()
	save_btn.text = "💾 保存坐标"
	save_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.custom_minimum_size = Vector2(150, 40)
	save_btn.position = Vector2(host._vp().x - 164, 4)
	var ssb = StyleBoxFlat.new()
	ssb.bg_color = Color("#2e7d46")
	ssb.set_corner_radius_all(8)
	ssb.set_border_width_all(2)
	ssb.border_color = Color("#7fe6a0")
	save_btn.add_theme_stylebox_override("normal", ssb)
	host._edit_layer.add_child(save_btn)
	save_btn.pressed.connect(_save_rl_file)
	for key in host._place_reg.keys():   # 只给已放置区块建把手(自动跳过未建的 synergy)
		if is_instance_valid(host._place_reg[key]):
			_make_edit_handle(str(key))


func _make_edit_handle(key: String) -> void:
	var rc = host._rect(key)
	var handle = Panel.new()
	handle.position = rc.position
	handle.size = rc.size
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.85, 0.60, 0.14)
	sb.border_color = Color("#3cf0a0")
	sb.set_border_width_all(2)
	handle.add_theme_stylebox_override("panel", sb)
	host._edit_layer.add_child(handle)
	var lbl = Label.new()
	lbl.add_theme_color_override("font_color", Color("#ffffff"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = Vector2(4, 2)
	handle.add_child(lbl)
	var grip = Panel.new()
	grip.size = Vector2(18, 18)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	var gsb = StyleBoxFlat.new()
	gsb.bg_color = Color("#ffd93d")
	grip.add_theme_stylebox_override("panel", gsb)
	handle.add_child(grip)
	grip.position = handle.size - grip.size
	host._edit_handles[key] = {"handle": handle, "label": lbl, "grip": grip}
	handle.gui_input.connect(func(ev): _handle_input(key, "move", ev))
	grip.gui_input.connect(func(ev): _handle_input(key, "resize", ev))
	_update_edit_label(key)


func _handle_input(key: String, mode: String, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (ev as InputEventMouseButton).pressed:
			host._drag_key = key
			host._drag_mode = mode
			host._drag_last = host.get_viewport().get_mouse_position()
		elif host._drag_key == key:
			host._drag_key = ""
			print("[RL] \"%s\": %s" % [key, host._rl_line(key)])


func _update_edit_label(key: String) -> void:
	var h: Dictionary = host._edit_handles.get(key, {})
	if not h.has("label") or not is_instance_valid(h["label"]):
		return
	var r = host._rl_val(key)
	(h["label"] as Label).text = "%s\nx%d y%d\nw%d h%d" % [key, int(round(float(r["x"]))), int(round(float(r["y"]))), int(round(float(r["w"]))), int(round(float(r["h"])))]


func _export_rl() -> void:
	var out = "\n===== 复制以下 RL (含你拖动后的坐标) =====\nconst RL := {\n"
	for key in host.RL.keys():
		out += "\t\"%s\": %s\n" % [key, host._rl_line(str(key))]
	out += "}\n===== 结束 =====\n"
	print(out)
	host._flash_status("📋 已导出 RL 坐标到控制台 (终端复制给我)")


## 保存坐标到文件 — 用户点按钮即写 user://rl_layout.txt, 我直接读回 (免抄免复制)
func _save_rl_file() -> void:
	var out = "const RL := {\n"
	for key in host.RL.keys():
		out += "\t\"%s\": %s\n" % [key, host._rl_line(str(key))]
	out += "}\n"
	var f = FileAccess.open("user://rl_layout.txt", FileAccess.WRITE)
	if f == null:
		host._flash_status("❌ 保存失败 (FileAccess null)")
		return
	f.store_string(out)
	f.close()
	print(out)
	host._flash_status("💾 已保存 → user://rl_layout.txt (告诉我一声我就读)")


# ══════════════════════════════════════════════════════════════
# 点按信息弹窗 — 被动/技能 点一下弹名+描述 (PC点击 + 手机点触 都行·点空白关)
#   悬停 tooltip 只 PC 有; 手机无 hover → 加点按弹窗补齐. 用户2026-07-18.
# ══════════════════════════════════════════════════════════════
