extends Node
## _probe_twoclocks.gd — 探针: 主菜单一屏上到底有没有【两条时钟】
##
## 不推理, 只打数值。问三件事:
##   ① `GameState.ranked_quota_full()` **不带参**(= MainMenuScene.gd:335 的写法)
##      与 `ranked_quota_full(那一刻)`(= `_open_shop()` / `_battle_block_msg()` 的写法)
##      在同一刻会不会给出**不同答案**。
##   ② 同样问 `gauntlet_can_play()`。
##   ③ 真建一屏主菜单(`clock_override_ts` 钉死在某一刻), 量**屏幕上真画出来的两样东西**:
##      · 状态行 L2 说今天是什么日子
##      · 商店那一行有没有 🔒
##      两者若来自不同的时钟, 屏幕会自己打自己的脸。

const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 2026-09-14 周一 00:00:00 UTC —— 锚点。往后逐日加 86400。
const MON := 1789344000


func _lbls(n: Node, out: Array) -> void:
	if n is Label:
		var tx := str((n as Label).text)
		if not out.has(tx):
			out.append(tx)          # 描边 = 同一句话 5 份, 只留一份
	for c in n.get_children():
		_lbls(c, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  拿不到 GameState"); get_tree().quit(1); return
	gs.test_mode = true

	var real: int = int(Time.get_unix_time_from_system())
	print("=== 探针: 主菜单一屏两条时钟 ===")
	print("真实墙钟 %d  ISO星期=%d  阶段=%s" % [
		real, _P2.iso_weekday_utc(real), _P2.phase_at_utc(real)])
	print("RANKED_QUOTA=%d  PHASE_MODE_LIVE(gauntlet)=%s (finals)=%s" % [
		int(_P2.RANKED_QUOTA), str(_P2.phase_mode_live(_P2.PHASE_GAUNTLET)),
		str(_P2.phase_mode_live(_P2.PHASE_FINALS))])

	# ── ① / ② 纯函数层: 不带参 vs 带参 ─────────────────────────────
	gs.hearts = 8
	gs.season_total_battles = 5
	gs.ranked_used = int(_P2.RANKED_QUOTA)         # 配额打满
	gs.promoted = true                              # 有闯关赛资格
	gs.gauntlet_wins = 1
	gs.gauntlet_losses = 1
	print("")
	print("--- ① ranked_quota_full / ② gauntlet_can_play: 不带参 vs 带参 ---")
	print("    (ranked_used=%d/%d, promoted=true, 闯关 1-1)" % [
		int(gs.ranked_used), int(_P2.RANKED_QUOTA)])
	print("  %-26s %-9s | quota:无参 带参 | gauntlet:无参 带参" % ["钉住的那一刻", "阶段"])
	var names := ["周一 rest", "周二 ranked", "周四 ranked",
		"周五23:59:59", "周六00:00:00", "周六 gauntlet",
		"周六23:59:59", "周日00:00:00", "周日23:59:59", "下周一00:00:00"]
	var stamps := [MON, MON + 86400, MON + 3 * 86400,
		MON + 5 * 86400 - 1, MON + 5 * 86400, MON + 5 * 86400 + 43200,
		MON + 6 * 86400 - 1, MON + 6 * 86400, MON + 7 * 86400 - 1, MON + 7 * 86400]
	var diff_q := 0
	var diff_g := 0
	for i in range(stamps.size()):
		var t: int = int(stamps[i])
		var qn: bool = gs.ranked_quota_full()          # 不带参 = 335 行的写法
		var qp: bool = gs.ranked_quota_full(t)         # 带参 = _open_shop() 的写法
		var gn: bool = gs.gauntlet_can_play()
		var gp: bool = gs.gauntlet_can_play(t)
		if qn != qp:
			diff_q += 1
		if gn != gp:
			diff_g += 1
		print("  %-26s %-9s |   %-5s %-5s |     %-5s %-5s %s" % [
			str(names[i]), _P2.phase_at_utc(t), str(qn), str(qp), str(gn), str(gp),
			("  <<< 矛盾" if (qn != qp or gn != gp) else "")])
	print("  分母: 构造了 %d 个时刻; quota 两种写法答案不同 %d 个 / gauntlet 不同 %d 个" % [
		stamps.size(), diff_q, diff_g])

	# ── ③ 真建一屏, 量画出来的东西 ────────────────────────────────
	print("")
	print("--- ③ 真建一屏主菜单(clock_override_ts 钉死), 量屏幕上画出来的 ---")
	for probe_i in range(3):
		var pin: int = [MON + 3 * 86400, MON + 5 * 86400 + 43200, MON + 6 * 86400 + 43200][probe_i]
		var tag: String = ["周四(积分赛)", "周六(闯关赛)", "周日(决赛日)"][probe_i]
		var scene = MENU.new()
		scene.clock_override_ts = pin                # ★必须在 _ready 之前钉
		add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		var all: Array = []
		if scene.page_box != null:
			_lbls(scene.page_box, all)
		var content_txt: Array = []
		if scene.content_root != null:
			_lbls(scene.content_root, content_txt)
		var shop_line := ""
		for s in all:
			if str(s).find("商店") >= 0:
				shop_line = str(s)
		var l2 := ""
		var two = scene.content_root.find_child(str(MENU.STATUS_TWO_LINE), true, false) \
			if scene.content_root != null else null
		if two != null:
			var tl: Array = []
			_lbls(two, tl)
			if tl.size() >= 2:
				l2 = str(tl[1])
		print("  钉 %s" % tag)
		print("    状态行 L2 画出来的      : 「%s」" % l2)
		print("    商店那一行画出来的      : 「%s」  (有锁=%s)" % [
			shop_line, str(shop_line.find("🔒") >= 0)])
		print("    _open_shop() 的判据     : ranked_quota_full(钉住那刻) = %s" % str(
			gs.ranked_quota_full(pin)))
		print("    335 行的判据(不带参)    : ranked_quota_full()        = %s" % str(
			gs.ranked_quota_full()))
		print("    _battle_block_msg(钉刻) : 「%s」" % str(scene._battle_block_msg(pin)))
		var painted_lock: bool = shop_line.find("🔒") >= 0
		var entry_says: bool = gs.ranked_quota_full(pin)
		print("    ⇒ 画出来的锁 = %s / 入口的判据 = %s  %s" % [
			str(painted_lock), str(entry_says),
			("★★★ 自相矛盾" if painted_lock != entry_says else "一致")])
		scene.queue_free()
		await get_tree().process_frame

	print("PROBE DONE")
	get_tree().quit(0)
