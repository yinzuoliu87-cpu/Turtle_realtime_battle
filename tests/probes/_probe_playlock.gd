extends Node
## _probe_playlock.gd — ①的探针: 配额打满时「开始战斗」与「商店」各自长什么样 + 飘字压在谁身上。
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
var _menu: Node = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.season_total_battles = 3
	gs.season_id = 2
	gs.season_level = 4
	gs.hearts = 8
	gs.coins = 1240
	gs.meta_deepsea_coins = 380
	gs.promoted = false
	gs.gauntlet_wins = 0
	gs.gauntlet_losses = 0
	gs.season_wins = 0
	gs.ranked_used = int(P2C.RANKED_QUOTA)          # ★配额打满
	var TH := 1789603200                             # 2026-09-24 周四 UTC
	print("★分母: ranked_quota_full(周四) = %s  (ranked_used=%d / quota=%d)" % [
		str(gs.ranked_quota_full(TH)), int(gs.ranked_used), int(P2C.RANKED_QUOTA)])
	_menu = load("res://scenes/MainMenu.tscn").instantiate()
	_menu.clock_override_ts = TH
	get_tree().root.add_child(_menu)
	if _menu is Control:
		(_menu as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(_menu as Control).size = Vector2(1280, 720)
	Engine.time_scale = 12.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	for _i in range(4):
		await get_tree().process_frame

	print("")
	print("=== page_box 直属子节点 (按钮栈) ===")
	var pb: Control = _menu.get("page_box")
	for c in pb.get_children():
		var r: Rect2 = (c as Control).get_global_rect()
		print("  <%s> %s  y %.0f..%.0f x %.0f..%.0f  mod=%s  文字=%s  🔒=%s" % [
			c.get_class(), c.name, r.position.y, r.end.y, r.position.x, r.end.x,
			str((c as Control).modulate), _texts(c), str(_has_lock(c))])
	print("")
	print("=== _battle_block_msg / _open_shop 各自的判据 ===")
	print("  _battle_block_msg(周四) = 「%s」" % _menu._battle_block_msg(1789603200))
	print("  GameState.is_eliminated() = %s" % str(gs.is_eliminated()))
	print("  season_total_battles = %d" % int(gs.season_total_battles))
	print("")
	print("=== 飘字压在谁身上 ===")
	var before: Array = _menu.get_children()
	_menu._open_shop()
	var toast: Control = null
	for ch in _menu.get_children():
		if not before.has(ch) and ch is Label:
			toast = ch
	if toast != null:
		var tr: Rect2 = toast.get_global_rect()
		print("  toast rect y %.0f..%.0f x %.0f..%.0f  「%s」" % [
			tr.position.y, tr.end.y, tr.position.x, tr.end.x, str((toast as Label).text)])
		var f: Font = (toast as Label).get_theme_font("font")
		var fs: int = (toast as Label).get_theme_font_size("font_size")
		if f != null:
			print("  文字实际宽 = %.0f px (控件 %.0f px) ⇒ %s" % [
				f.get_string_size((toast as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
				tr.size.x,
				"放得下" if f.get_string_size((toast as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= tr.size.x else "★溢出"])
		var all: Array = []
		_collect(_menu, all)
		print("  与它重叠的可见控件:")
		for c in all:
			if c == toast: continue
			var r2: Rect2 = (c as Control).get_global_rect()
			if r2.size.x >= 1279.0 and r2.size.y >= 719.0: continue
			var it: Rect2 = tr.intersection(r2)
			if it.size.x > 0.5 and it.size.y > 0.5:
				print("    ★压 %.0f×%.0f  <%s> %s y %.0f..%.0f x %.0f..%.0f 「%s」" % [
					it.size.x, it.size.y, c.get_class(), c.name, r2.position.y, r2.end.y,
					r2.position.x, r2.end.x, _texts(c).substr(0, 18)])
	print("")
	print("=== 全屏可见控件占用的 y 带 (找空档给提示条) ===")
	var all2: Array = []
	_collect(_menu, all2)
	all2.sort_custom(func(a, b): return float((a as Control).get_global_rect().position.y) < float((b as Control).get_global_rect().position.y))
	for c in all2:
		var r3: Rect2 = (c as Control).get_global_rect()
		if r3.size.x >= 1279.0 and r3.size.y >= 719.0: continue
		print("  y %6.0f..%6.0f  x %6.0f..%6.0f  <%s> %-18s 「%s」" % [
			r3.position.y, r3.end.y, r3.position.x, r3.end.x, c.get_class(),
			str(c.name).substr(0, 18), _texts(c).substr(0, 20)])
	get_tree().quit(0)


func _texts(n: Node) -> String:
	var out := ""
	for x in _walk(n):
		if x is Label and str((x as Label).text).strip_edges() != "":
			out += str((x as Label).text) + "|"
	return out


func _has_lock(n: Node) -> bool:
	return _texts(n).find("🔒") >= 0


func _walk(n: Node) -> Array:
	var o: Array = [n]
	for c in n.get_children():
		o.append_array(_walk(c))
	return o


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var ct: Control = c
			if ct.size.x > 0.5 and ct.size.y > 0.5:
				out.append(ct)
		_collect(c, out)
