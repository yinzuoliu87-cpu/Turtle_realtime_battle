extends RefCounted
## DEV 钩子(配 tests/_shot_scene.gd 的 SHOT_POST): 把【某个控件的系统 tooltip】真的叫出来,
## 以便实拍它到底把 BBCode 画成了什么。
##
## 由来 2026-10-02: `team_select/detail_panel.gd:194` 把 `SkillText.render_bbcode()` 的结果
## 直接塞进 `chip.tooltip_text`, 而 chip 是裸 `PanelContainer`(没覆写 `_make_custom_tooltip`,
## 也没挂 `rich_tooltip.gd`) ⇒ 走 Godot 的系统 tooltip = 纯 `Label` ⇒ BBCode 原样印给玩家。
## ★不靠推理, 靠把 tooltip 真的叫出来再抓视口纹理。
##
## 用法(由 _shot_scene.gd 调):
##   SHOT_SCENE=res://scenes/TeamSelect.tscn SHOT_POST=res://tests/_post_ts_tooltip.gd \
##   SHOT_PET=<龟id> TIP_WHERE=passive|skill SHOT_OUT=... \
##   <godot> --path . res://tests/_shot_scene.tscn --position 5000,5000
##
## ★两条实测结论(都栽过, 记在这免得下次重走):
##   ① `Input.parse_input_event` 喂不动 GUI 的 hover —— 要用 `Viewport.push_input()`。
##      而且要【先在控件外面动一下再移进来】, 一次就位不换 mouse_over。
##   ② Godot 4.6 的 tooltip 宿主类名是 **`PopupPanel`**, 里面不含 "Tooltip" 字样
##      (旧版叫 TooltipPanel)。按类名找 "tooltip" 会把"浮出来了"误判成"没浮出来" ——
##      我第一版就是这么误判的, 而窗口里其实已经有它了。


static func run(scene: Node) -> void:
	var pid := OS.get_environment("SHOT_PET")
	if pid == "":
		pid = "basic"
	scene.detail_pet_id = pid
	scene._detail._refresh_detail()
	await scene.get_tree().process_frame
	await scene.get_tree().process_frame
	var where := OS.get_environment("TIP_WHERE")
	if where == "":
		where = "passive"
	## 在【指定那一块】里找带 tooltip 的可悬浮控件 —— 按容器找, 不按节点名找。
	var hostc: Node = scene._dt_passive if where == "passive" else scene._detail_bottom
	var hit: Control = null
	var stack: Array = [hostc]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if str(c.tooltip_text) != "" and c.is_visible_in_tree() \
					and c.mouse_filter == Control.MOUSE_FILTER_STOP:
				hit = c
				break
		for ch in n.get_children():
			stack.append(ch)
	if hit == null:
		print("[TIP] 没在 %s 块里找到带 tooltip 的控件" % where)
		return
	print("[TIP] 命中 %s  脚本=%s  rect=%s" % [hit.get_class(),
		("无" if hit.get_script() == null else str(hit.get_script().resource_path)),
		str(hit.get_global_rect())])
	print("[TIP] tooltip_text(原文) = |%s|" % str(hit.tooltip_text).replace("\n", "⏎"))
	## ★直接问产品自己: 这个控件给不给自定义 tooltip 宿主?
	##   ⚠ 没覆写的控件上**连这个方法都不存在**(实测 `Invalid call. Nonexistent function
	##     '_make_custom_tooltip' in base 'PanelContainer'`) —— 所以要先 has_method。
	if not hit.has_method("_make_custom_tooltip"):
		print("[TIP] ★没有 _make_custom_tooltip 这个方法 ⇒ 走系统 tooltip(纯 Label)")
	else:
		var custom = hit._make_custom_tooltip(str(hit.tooltip_text))
		print("[TIP] _make_custom_tooltip 返回 = %s" % ("null(⇒系统纯文本 tooltip)" if custom == null else str(custom.get_class())))
		if custom != null:
			custom.free()
	var ctr: Vector2 = hit.get_global_rect().get_center()
	var vp: Viewport = scene.get_viewport()
	## 先在控件外面动一下再移进来 —— GUI 的 hover 按"位置变了"算, 一次就位不换 mouse_over。
	for d in [Vector2(0, -140), Vector2(0, -60), Vector2.ZERO, Vector2(1, 0)]:
		var e := InputEventMouseMotion.new()
		e.position = ctr + d
		e.global_position = e.position
		e.relative = Vector2(1, 1)
		vp.push_input(e)
	print("[TIP] 已把鼠标推到 %s, 等 tooltip 浮出(默认延迟 0.5 秒)" % str(ctr))
	## ★轮着查, 不是等一个固定帧数就下结论 —— tooltip 可能晚来, 也可能来了又被收掉。
	var seen := false
	for _i in range(24):
		for _j in range(10):
			await scene.get_tree().process_frame
		var np := _count_popup(scene)
		if np > 0 and not seen:
			seen = true
			print("[TIP] 第 %d 帧附近 tooltip 出现了" % ((_i + 1) * 10))
			_dump_tip(scene)
		if _i % 6 == 5:
			print("[TIP] 第 %d 帧: hover=%s  popup数=%d" % [(_i + 1) * 10,
				("null" if vp.gui_get_hovered_control() == null else str(vp.gui_get_hovered_control().get_class())),
				np])
	if not seen:
		print("[TIP] ⚠ 240 帧内 tooltip 一次都没浮出来")
		_dump_tip(scene)


static func _count_popup(scene: Node) -> int:
	var q: Array = [scene.get_tree().root]
	var n_pop := 0
	while not q.is_empty():
		var n: Node = q.pop_back()
		if n is Popup:
			n_pop += 1
		for ch in n.get_children():
			q.append(ch)
	return n_pop


## 把 tooltip 宿主(Popup)里【真正画字的那个控件】是什么、画的是什么字打出来。
## ★这才是"吃不吃 BBCode"的直接证据: Label.text 就是屏幕上的字(原样);
##   RichTextLabel.get_parsed_text() 是去掉标记后的字(说明标记被当标记吃掉了)。
static func _dump_tip(scene: Node) -> void:
	var q: Array = [scene.get_tree().root]
	var found := false
	while not q.is_empty():
		var n: Node = q.pop_back()
		if n is Popup or (n is Window and n != scene.get_tree().root):
			print("[TIP] tooltip 宿主 = %s(name=%s) visible=%s" % [n.get_class(), n.name, str((n as Window).visible)])
			var q2: Array = [n]
			while not q2.is_empty():
				var m: Node = q2.pop_back()
				if m is RichTextLabel:
					found = true
					print("[TIP] ★里面是 RichTextLabel(吃 BBCode) · 解析后文字 = |%s|"
						% str((m as RichTextLabel).get_parsed_text()).replace("\n", "⏎"))
				elif m is Label:
					found = true
					print("[TIP] ★里面是 Label(不吃 BBCode) · 屏幕上原样印出来的字 = |%s|"
						% str((m as Label).text).replace("\n", "⏎"))
				for c2 in m.get_children():
					q2.append(c2)
		for ch in n.get_children():
			q.append(ch)
	if not found:
		print("[TIP] ⚠ tooltip 没浮出来(树上没有 Popup)")
