extends Node
## 探针: **0 命但已晋级**的人周六打闯关赛, 战绩记不记?
##
## ★为什么问这个: 命数矩阵(`_probe_hearts_matrix`)里 0 命的人**只有一格能打** ——
##   周六 + 已拿到闯关赛资格 + 闯关赛还没打完。而周一~五的屏幕明确答应他
##   「💀 本大轮已出局 · 但你已晋级, 周六闯关赛见」。
## ★而结算分支里 `if _last_was_exhibition:`(= `is_eliminated()`) **排在**
##   `elif _sk == SETTLE_GAUNTLET:` 前面 ⇒ 疑似走「表演赛(无 stake)」那一支。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		get_tree().quit(1); return
	gs.test_mode = true
	print("=== 0 命 + 已晋级 + 周六: 闯关赛战绩记不记 ===")
	for hearts in [3, 0]:
		gs.hearts = hearts
		gs.promoted = true
		gs.gauntlet_wins = 0
		gs.gauntlet_losses = 0
		gs.week_phase = P2.PHASE_GAUNTLET
		var sk: String = str(P2.settle_kind(str(gs.week_phase), P2.phase_mode_live(str(gs.week_phase))))
		var exhibition: bool = gs.is_eliminated()
		## 产品的分支顺序: 表演赛优先
		## ★产品现在的判据: 表演赛只在**积分赛**那一档成立(2026-09-27 修)
		var exhib_now: bool = exhibition and sk == P2.SETTLE_RANKED
		var branch: String = "表演赛(无 stake)" if exhib_now else ("闯关赛" if sk == P2.SETTLE_GAUNTLET else sk)
		## 真走一遍闯关赛记账, 看战绩变没变(只有走到那一支才会变)
		var w0 := int(gs.gauntlet_wins)
		if not exhib_now and sk == P2.SETTLE_GAUNTLET:
			gs.gauntlet_settle(true)
		print("  %d 命  settle_kind=%-9s 走的分支=%-16s 打赢一场后战绩 %d胜 → %d胜  %s" % [
			hearts, sk, branch, w0, int(gs.gauntlet_wins),
			("★战绩没记!" if int(gs.gauntlet_wins) == w0 else "")])
	print("")
	print("  ⇒ 0 命那一行如果战绩没记, 他**永远打不到 4 胜**, 进不了决赛日 ——")
	print("     而周一~五的屏幕刚答应过他「周六闯关赛见」。")
	get_tree().quit(0)
