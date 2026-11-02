extends Node
## _probe_set_overlap.gd — 量【设置页】上每个可见控件的真实 rect, 打出 y 序表 + 重叠明细。
## 目的: 确认「两个账号按钮压住音乐行」到底压在哪、压多少 —— 不靠读坐标推算。
const SETTINGS := preload("res://scenes/Settings.tscn")
const UIC := preload("res://tests/verify_ui_consistency.gd")
var _uic = null

func _ready() -> void:
	_uic = UIC.new()
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	for mail in ["", "someone@example.com"]:
		gs.account_id = "ae08e589-1111-2222-3333-444455556666"
		gs.account_email = mail
		var s = SETTINGS.instantiate()
		add_child(s)
		if s is Control:
			(s as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
			(s as Control).size = Vector2(1280, 720)
		for _i in range(40):
			await get_tree().process_frame
		print("")
		print("######## mail=「%s」  bind_layer=%s" % [mail, str(s._email_layer != null)])
		var rows: Array = []
		_walk(s, rows)
		rows.sort_custom(func(a, b): return float(a["r"].position.y) < float(b["r"].position.y))
		for r in rows:
			var rr: Rect2 = r["r"]
			print("  y %7.1f..%7.1f  x %7.1f..%7.1f  %-16s %-22s %-6s 「%s」" % [
				rr.position.y, rr.end.y, rr.position.x, rr.end.x,
				str(r["cls"]), str(r["name"]).substr(0, 22), str(r["kind"]), str(r["txt"]).substr(0, 26)])
		print("  --- 重叠 (Label ink ∪ BaseButton holder, 排除祖孙) ---")
		var n := 0
		for i in range(rows.size()):
			for j in range(i + 1, rows.size()):
				var a = rows[i]; var b = rows[j]
				if not (str(a["kind"]) in ["lbl", "btn"]) or not (str(b["kind"]) in ["lbl", "btn"]):
					continue
				if _nested(a["node"], b["node"]) or _nested(b["node"], a["node"]):
					continue
				var it: Rect2 = (a["r"] as Rect2).intersection(b["r"])
				if it.size.x > 0.5 and it.size.y > 0.5:
					n += 1
					print("    ★压 %.0f×%.0f : 「%s」<%s %s> × 「%s」<%s %s>" % [
						it.size.x, it.size.y, str(a["txt"]).substr(0, 14), a["cls"], a["kind"],
						str(b["txt"]).substr(0, 14), b["cls"], b["kind"]])
		print("  重叠对数 = %d" % n)
		s.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)


func _walk(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var ct: Control = c
			var r: Rect2 = ct.get_global_rect()
			if r.size.x > 0.5 and r.size.y > 0.5:
				var kind := "-"
				var txt := ""
				if ct is Label and str((ct as Label).text).strip_edges() != "":
					kind = "lbl"; txt = str((ct as Label).text)
					r = _uic._ink_rect(ct as Label)
				elif ct is BaseButton:
					kind = "btn"; txt = str((ct as Button).text) if ct is Button else ""
				elif ct.mouse_filter == Control.MOUSE_FILTER_STOP:
					kind = "hit"
				if not (r.size.x >= 1279.0 and r.size.y >= 719.0):
					out.append({"r": r, "cls": ct.get_class(), "name": ct.name, "kind": kind,
						"txt": txt, "node": ct})
		_walk(c, out)


func _nested(a: Node, b: Node) -> bool:
	var p := a.get_parent()
	while p != null:
		if p == b: return true
		p = p.get_parent()
	return false
