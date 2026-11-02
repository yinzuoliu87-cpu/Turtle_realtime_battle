extends Node
## _probe_newuser2.gd — 只读侦察: 全新玩家逐屏看到的原文(离线/后端连不上)。
## 每屏都真实例化, 等入场落定, 把所有 Label/Button/LineEdit 文字打出来。

const _SB := preload("res://scripts/net/supabase.gd")
const _BE := preload("res://scripts/net/backend.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")

var SCENES := ["Settings", "Leaderboard", "Record", "Codex", "Inventory",
	"TrainerConfig", "BracketMap", "Shop", "TeamSelect"]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	print("=== 环境: enabled=%s state=%s email='%s' wall=%s ===" % [
		str(_SB.enabled()), _SB.service_state(), str(gs.account_email),
		str(_P2C.login_wall_on(_SB.enabled(), str(gs.account_email)))])
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame

	print("=== 第一场对手(全新玩家 season_total_battles=%d) ===" % int(gs.season_total_battles))
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	var g: Dictionary = _BE.find_opponent(int(gs.season_total_battles), [], rng)
	print("  ghost_id   = '%s'" % str(g.get("ghost_id", "")))
	print("  profile    = %s" % str(g.get("profile", {})))
	print("  leaders    = %s" % str(g.get("leaders", [])))
	print("  是 bot?    = %s" % str(g.get("is_bot", "(无此键)")))
	print("  match_src_counts = %s" % str(_BE.match_src_counts))

	for s in SCENES:
		await _dump(s)

	print("PROBE2 DONE")
	get_tree().quit(0)


func _dump(name: String) -> void:
	var path := "res://scenes/%s.tscn" % name
	print("================ 屏: %s ================" % name)
	var packed = load(path)
	if packed == null:
		print("  [载不到]"); return
	var n = packed.instantiate()
	get_tree().root.add_child(n)
	if n is Control:
		(n as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(n as Control).size = Vector2(1280, 720)
	# 墙钟等: 入场 tween + 异步回调
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var out: Array = []
	if is_instance_valid(n):
		_gather(n, out)
	# 去重相邻重复(描边是 5 份同文字的 Label)
	var uniq: Array = []
	for t in out:
		if uniq.is_empty() or str(uniq[uniq.size() - 1]) != str(t):
			uniq.append(t)
	print("  文字 %d 条(去描边重复后 %d):" % [out.size(), uniq.size()])
	for t in uniq:
		print("    · %s" % str(t).replace("\n", " ⏎ "))
	if is_instance_valid(n):
		n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _gather(n: Node, out: Array) -> void:
	if n is Label and (n as Label).text.strip_edges() != "":
		if (n as Label).visible:
			out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append("[BTN%s] %s" % ["(禁)" if (n as Button).disabled else "", (n as Button).text])
	elif n is RichTextLabel and (n as RichTextLabel).text.strip_edges() != "":
		out.append("[RT] " + (n as RichTextLabel).text)
	elif n is LineEdit:
		out.append("[EDIT ph='%s']" % (n as LineEdit).placeholder_text)
	for c in n.get_children():
		_gather(c, out)
