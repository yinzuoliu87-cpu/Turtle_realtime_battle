extends Node
## _probe_codex_cardlines.gd — 图鉴龟页: 卡片/被动条/普攻条里【半截行】与【没切却提示"点开看全部"】(只量不判·非门禁)
const SCN := preload("res://scenes/Codex.tscn")
var _inst


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_inst = SCN.instantiate()
	add_child(_inst)
	await _settle(10)
	_inst._switch_tab("pets")
	await _settle(6)
	var n_rt := 0
	var n_partial := 0
	var n_falsehint := 0
	var n_hint := 0
	for i in range(_inst._items.size()):
		var it: Dictionary = _inst._items[i]
		if it.has("_minion"):
			continue
		_inst._select(i)
		await _settle(5)
		var hints := 0
		for c in _inst.detail.get_children():
			if c is Label and str((c as Label).text) == "查看全部" and (c as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				hints += 1
		n_hint += hints
		for c in _inst.detail.get_children():
			if not (c is RichTextLabel):
				continue
			var rt := c as RichTextLabel
			if rt.fit_content:
				continue
			n_rt += 1
			var lc := rt.get_line_count()
			var h := rt.size.y
			var ch := rt.get_content_height()
			var txt := rt.get_parsed_text()
			for li in range(lc):
				var off := rt.get_line_offset(li)
				var nxt: float = rt.get_line_offset(li + 1) if li + 1 < lc else ch
				if off < h - 1.0 and nxt > h + 2.0:
					n_partial += 1
					print("PARTIAL %s line %d/%d off=%.0f next=%.0f box_h=%.0f 「%s」" % [it.get("id"), li + 1, lc, off, nxt, h, txt.substr(0, 40).replace("\n", "⏎")])
			# 被提示为"被切"但切掉的只有空白
			if ch > h + 0.5 and h > 40.0:
				var vis_end := -1
				for li in range(lc):
					if rt.get_line_offset(li) >= h - 1.0:
						vis_end = li
						break
				if vis_end >= 0:
					var hidden_all_blank := true
					# 粗判: 文本去掉尾部空白后, 行数是否 <= 可见行数
					var trimmed := txt.strip_edges(false, true)
					if trimmed.count("\n") + 1 > vis_end:
						hidden_all_blank = false
					if hidden_all_blank and txt != trimmed:
						n_falsehint += 1
						print("FALSEHINT %s visible_lines=%d total=%d trailing_ws=%d 「%s」" % [it.get("id"), vis_end, lc, txt.length() - trimmed.length(), txt.substr(0, 30).replace("\n", "⏎")])
	print("SUMMARY clipped-rt=%d partial-lines=%d false-hints(仅尾部空白被切)=%d hints-drawn=%d" % [n_rt, n_partial, n_falsehint, n_hint])
	print("PROBE DONE")
	get_tree().quit(0)
