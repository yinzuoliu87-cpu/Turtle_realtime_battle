extends Node
## _probe_status_row_days.gd — 只读剖面: 主菜单**状态行**七天各说什么, 字有多宽。
##
## 要量三件事(先打剖面再定阈值, memory `fb-judge-must-fit-the-shape`):
##   ① `_status_row()` 真的走 `_now_ts()` 了吗 —— 注入七天, 那一行的字变不变;
##   ② 周日那一行还摆着 `♥ N/8` 与 `本周 N/24` 吗(两个数周日全程冻结);
##   ③ 每一天那一行的**真实字宽**是多少 —— 换词之前先知道控件只有 LEFT_W-8 = 374px。

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

const MON := 1789344000    # 2026-09-14 周一 00:00 UTC
const NOON := 43200
const WD := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


func _find_row(n: Node, out: Array) -> void:
	if n is Label and str((n as Label).text).find("大轮") >= 0:
		var t: String = str((n as Label).text)
		if not out.has(t):
			out.append(t)
	for c in n.get_children():
		_find_row(c, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.hearts = 3
	gs.ranked_used = 7
	gs.season_id = 1
	gs.season_level = 1
	gs.promoted = true
	gs.gauntlet_wins = 2
	gs.gauntlet_losses = 1

	print("=== A. 纯函数: _phase_status_line(七天) ===")
	var m = MENU.new()
	for d in range(7):
		var ts: int = MON + d * 86400 + NOON
		print("  %s %-8s 「%s」" % [WD[d], P2.phase_at_utc(ts), m._phase_status_line(ts)])
	print("=== B. 注入时钟后【不传参】那个调用(bug ③ 的形状) ===")
	for d in range(7):
		m.clock_override_ts = MON + d * 86400 + NOON
		print("  %s 不传参 → 「%s」" % [WD[d], m._phase_status_line()])
	m.clock_override_ts = 0
	m.free()

	print("=== C. 真渲染路径: 建 MainMenu, 钉死时钟, 读那一行的字 + 量真实字宽 ===")
	var pk = load("res://scenes/MainMenu.tscn")
	for d in range(7):
		var mm = pk.instantiate()
		mm.clock_override_ts = MON + d * 86400 + NOON
		get_tree().root.add_child(mm)
		for _i in range(6):
			await get_tree().process_frame
		var rows: Array = []
		_find_row(mm, rows)
		var txt: String = str(rows[0]) if rows.size() > 0 else "<没找到那一行>"
		var f = mm._bold_font()
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		print("  %s %-8s 宽 %6.1f / 框 374  「%s」" % [
			WD[d], P2.phase_at_utc(MON + d * 86400 + NOON), w, txt])
		mm.queue_free()
		await get_tree().process_frame

	print("=== D. 分母: 周日那两个数真的冻着吗(走产品自己的结算) ===")
	var h0: int = int(gs.hearts)
	var u0: int = int(gs.ranked_used)
	gs.finals_settle_sealed()
	gs.finals_reveal(true)
	print("  finals 结算前后: hearts %d→%d  ranked_used %d→%d" % [
		h0, int(gs.hearts), u0, int(gs.ranked_used)])
	print("  phase_uses_ranked_quota(finals)=%s / (ranked)=%s" % [
		str(P2.phase_uses_ranked_quota(P2.PHASE_FINALS)),
		str(P2.phase_uses_ranked_quota(P2.PHASE_RANKED))])

	print("PROBE DONE")
	get_tree().quit(0)
