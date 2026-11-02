extends Node
## _probe_finals_notoken.gd — 只读侦察: 周日决赛日, 【已晋级】的玩家在
## 「还没拿到 token」(冷启动头一秒 / 离线 / token 过期)那一刻, 对阵图屏说什么。
##
## 怀疑: `fetch_finals_async` 在 `_token == ""` 时**请求根本没发**却把
##   `_finals_tried` 标成 true, 而 `_finals_view` 是空的(没有 reason) ⇒
##   `_empty_text()` 一路掉到最后那句「本周没有你这一组 · 周六闯关赛晋级才进得来」。
## 这正是 2026-09-27 在**回包**那一侧刚修过的形状(reason == UNREACHABLE 那条)。

const _SB := preload("res://scripts/net/supabase.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _BM := preload("res://scripts/scenes/BracketMapScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame

	# ── 造一个【真的晋级了决赛日】的玩家 ──
	gs.promoted = true              # 积分赛收盘拿到闯关赛资格
	gs.gauntlet_wins = 4            # 闯关赛 4 胜 = 打进决赛日
	gs.gauntlet_losses = 0
	gs.account_id = "11111111-2222-3333-4444-555555555555"   # 有身份
	gs.finals_entered_week = _P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	print("=== 前提(分母) ===")
	print("  promoted=%s gauntlet_state=%s account_id 非空=%s" % [
		str(gs.promoted), gs.gauntlet_state(), str(str(gs.account_id) != "")])
	print("  enabled=%s  access_token='%s'  ← 空 = 匿名登录还在路上 / 离线 / 过期"
		% [str(_SB.enabled()), _SB.access_token()])

	# ── A: token 为空 → 真实入口 ──
	_SB.finals_clear()
	print("=== A. token 为空, 走真入口 fetch_finals_async ===")
	print("  调用前 finals_tried=%s  finals_cached=%s" % [
		str(_SB.finals_tried()), str(_SB.finals_cached())])
	_SB.fetch_finals_async(_P2C.week_anchor_utc(int(Time.get_unix_time_from_system())), -1)
	print("  调用后 finals_tried=%s  finals_cached=%s  ← 请求一个字节都没发出去" % [
		str(_SB.finals_tried()), str(_SB.finals_cached())])
	var bm = _BM.new()
	print("  屏幕中间那句 = 「%s」" % str(bm._empty_text()))
	bm.free()

	# ── B: 反向验证 —— 把「问过了」清掉, 同一个函数必须说别的话 ──
	print("=== B. 反向验证(finals_clear ⇒ tried=false) ===")
	_SB.finals_clear()
	var bm2 = _BM.new()
	print("  finals_tried=%s  屏幕中间那句 = 「%s」" % [
		str(_SB.finals_tried()), str(bm2._empty_text())])
	bm2.free()

	# ── C: 真实场景端到端(离线) ──
	print("=== C. 真 BracketMap 场景, 离线 ===")
	_SB.finals_clear()
	var packed = load("res://scenes/BracketMap.tscn")
	var n = packed.instantiate()
	get_tree().root.add_child(n)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var out: Array = []
	_gather(n, out)
	print("  finals_tried=%s finals_cached=%s" % [str(_SB.finals_tried()), str(_SB.finals_cached())])
	for t in out:
		print("    · %s" % str(t).replace("\n", " ⏎ "))
	n.queue_free()

	# ── D: 同族: 对手快照那条闸 ──
	print("=== D. 同族: fetch_opponent_async 也在无 token 时标 tried ===")
	_SB.opponent_clear()
	print("  调用前 opponent_tried=%s" % str(_SB.opponent_tried()))
	_SB.fetch_opponent_async(1, 1, 1, 1)
	print("  调用后 opponent_tried=%s opponent_cached=%s" % [
		str(_SB.opponent_tried()), str(_SB.opponent_cached())])
	print("  opponent_tip() = 「%s」" % str(_BM.opponent_tip(_SB.opponent_cached(), _SB.opponent_tried())))

	print("PROBE3 DONE")
	get_tree().quit(0)


func _gather(n: Node, out: Array) -> void:
	if n is Label and (n as Label).text.strip_edges() != "" and (n as Label).visible:
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append("[BTN] " + (n as Button).text)
	for c in n.get_children():
		_gather(c, out)
