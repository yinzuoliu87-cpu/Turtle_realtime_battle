extends RefCounted
## _finals_text_probe.gd —— 决赛日「此刻屏上看得见的每一句字」采集器(实拍台 `_shot_finals_day.gd` 与门禁
##   `verify_finals_copy.gd` 共用; 不是测试本身)。2026-11-01 用户看对阵图:「作为玩家看到的东西是什么呢？」
## ★量的是**屏上真的看得见的**: 节点在树里可见、整条祖先链 modulate 不透明、矩形与视口(及裁剪祖先)有交集、字非空。
##   只认 Label / Button / RichTextLabel(解析后文字) —— 决赛日屏自画字(draw_string)的几处另由门禁按函数返回值量。
## 返回 [{"text", "rect": Rect2(屏幕坐标), "path", "cls"}], 按 y 再按 x 排好。


static func collect(root: Node, vp: Rect2) -> Array:
	var out: Array = []
	_walk(root, vp, out)
	out.sort_custom(func(a, b) -> bool:
		var ra: Rect2 = a["rect"]
		var rb: Rect2 = b["rect"]
		if absf(ra.position.y - rb.position.y) > 4.0:
			return ra.position.y < rb.position.y
		return ra.position.x < rb.position.x)
	return out


static func _walk(n: Node, vp: Rect2, out: Array) -> void:
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var t := text_of(n as Control)
		if t.strip_edges() != "" and _alpha(n as Control) > 0.05:
			var r := screen_rect(n as Control)
			var clip := _clip_rect(n as Control, vp)
			if r.size.x > 0.5 and r.size.y > 0.5 and clip.intersects(r):
				out.append({"text": t, "rect": r, "path": str(n.get_path()), "cls": n.get_class()})
	for c in n.get_children():
		_walk(c, vp, out)


static func text_of(c: Control) -> String:
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is Label:
		var lb := c as Label
		if lb.visible_ratio <= 0.0 or lb.visible_characters == 0:
			return ""
		return lb.text
	if c is Button:
		return (c as Button).text
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


static func screen_rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return xf * Rect2(Vector2.ZERO, c.size)


## 整条祖先链(到 CanvasLayer 为止)的不透明度。
static func _alpha(c: Control) -> float:
	var a := c.self_modulate.a
	var n: Node = c
	while n != null and not (n is CanvasLayer) and not (n is Viewport):
		if n is CanvasItem:
			a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


## 裁剪: 祖先里开了 clip_contents 的 Control(滚动框)把看得见的范围收窄。
static func _clip_rect(c: Control, vp: Rect2) -> Rect2:
	var r := vp
	var n: Node = c.get_parent()
	while n != null and not (n is CanvasLayer) and not (n is Viewport):
		if n is Control and (n as Control).clip_contents:
			var pr := screen_rect(n as Control)
			r = r.intersection(pr) if r.intersects(pr) else Rect2()
		n = n.get_parent()
	return r


## 一份采集结果 → 多行文本(实拍台写盘 / 门禁打印失败现场用)。
static func dump(items: Array) -> String:
	var lines := PackedStringArray()
	for it in items:
		var r: Rect2 = it["rect"]
		lines.append("[%4d,%4d %4dx%3d] %s  <%s>" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y),
			str(it["text"]).replace("\n", " ⏎ "), str(it["path"]).get_file()])
	return "\n".join(lines)
