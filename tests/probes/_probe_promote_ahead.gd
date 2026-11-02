extends Node
## _probe_promote_ahead.gd — 只读侦察: 「周六闯关赛见」那一支在周二~周四**能不能走到**。
##
## 怀疑: `_gauntlet_ahead()` 读 `GameState.promoted`, 而 `promoted` 只在
##   `settle_ranked_close()`(周五 23:00 UTC 收盘之后)才可能变 true
##   ⇒ 周二~周四**无论胜场多少**它恒为 false
##   ⇒ 0 命 / 配额打满的人被告知「下周一开新的一轮」, 而他周六其实真有 6 场可打。

const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _MENU := preload("res://scripts/scenes/MainMenuScene.gd")

const WD := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var m = _MENU.new()
	var anchor: int = _P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	print("=== 常量(分母) ===")
	print("  PROMOTE_WINS=%d  RANKED_QUOTA=%d  GAUNTLET_QUOTA=%d" % [
		int(_P2C.PROMOTE_WINS), int(_P2C.RANKED_QUOTA), int(_P2C.GAUNTLET_QUOTA)])
	print("  积分赛收盘 = 周%d %d:00 UTC" % [int(_P2C.RANKED_CLOSE_WD), int(_P2C.WEEK_CLOSE_HOUR_UTC)])

	print("=== A. 一个【胜场远超晋级线、但还没到周五收盘】的玩家 ===")
	gs.season_wins = 20
	gs.ranked_used = int(_P2C.RANKED_QUOTA)      # 配额打满
	gs.hearts = 0                                 # 0 命
	gs.promoted = false                           # ★真实状态: 收盘前一定是 false
	gs.gauntlet_wins = 0
	gs.gauntlet_losses = 0
	print("  season_wins=%d(线=%d)  ranked_used=%d  hearts=%d  promoted=%s" % [
		int(gs.season_wins), int(_P2C.PROMOTE_WINS), int(gs.ranked_used),
		int(gs.hearts), str(gs.promoted)])
	for d in range(1, 8):
		var ts: int = anchor + (d - 1) * 86400 + 12 * 3600
		print("  %s: _gauntlet_ahead()=%s  点开打 → 「%s」" % [
			WD[d - 1], str(m._gauntlet_ahead()), str(m._battle_block_msg(ts))])

	print("=== B. 同一个玩家, 把 promoted 手动置 true(=收盘后的状态) ===")
	gs.promoted = true
	for d in range(1, 8):
		var ts2: int = anchor + (d - 1) * 86400 + 12 * 3600
		print("  %s: _gauntlet_ahead()=%s  点开打 → 「%s」" % [
			WD[d - 1], str(m._gauntlet_ahead()), str(m._battle_block_msg(ts2))])

	print("=== C. 端到端: 让产品自己的收盘逻辑跑一遍(不手改 promoted) ===")
	gs.promoted = false
	gs.week_anchor_ts = anchor
	gs.season_wins = 20
	var fri_close: int = _P2C.ranked_close_ts(anchor)
	print("  收盘时刻 = %d" % fri_close)
	print("  收盘前 60 秒 settle_ranked_close → 补发 %d 场, promoted=%s" % [
		int(gs.settle_ranked_close(fri_close - 60)), str(gs.promoted)])
	print("  收盘后 60 秒 settle_ranked_close → 补发 %d 场, promoted=%s  ← 这才翻 true" % [
		int(gs.settle_ranked_close(fri_close + 60)), str(gs.promoted)])
	var sat: int = anchor + 5 * 86400 + 12 * 3600
	print("  周六再点开打 → 「%s」  (空串 = 真能打)" % str(m._battle_block_msg(sat)))
	print("  gauntlet_can_play(周六) = %s" % str(gs.gauntlet_can_play(sat)))

	print("=== D. 分母: 「周六闯关赛见」这句话在哪几天出现过 ===")
	gs.promoted = false
	var hit_false: Array = []
	var hit_true: Array = []
	for d in range(1, 8):
		var ts3: int = anchor + (d - 1) * 86400 + 12 * 3600
		if str(m._battle_block_msg(ts3)).find("周六闯关赛见") >= 0:
			hit_false.append(WD[d - 1])
	gs.promoted = true
	for d in range(1, 8):
		var ts4: int = anchor + (d - 1) * 86400 + 12 * 3600
		if str(m._battle_block_msg(ts4)).find("周六闯关赛见") >= 0:
			hit_true.append(WD[d - 1])
	print("  promoted=false 时出现在: %s  ← 这就是【收盘前】的真实状态" % str(hit_false))
	print("  promoted=true  时出现在: %s  ← 分母: 这句话本身不是死字符串" % str(hit_true))

	m.free()
	print("PROBE4 DONE")
	get_tree().quit(0)
