extends Node
## verify_battle_rng_seed.gd — Phase1(sim/演出分离): sim 战斗 RNG 单一受控源 _battle_rng 种子化
## 守: TURTLE_SEED 设时 _battle_rng 用该固定种子(→可复现)。
## ⚠诚实边界: 这只验"sim RNG 源装好·可种子化"。完整"同种子→一战两遍同结果"还需【消费顺序确定】
##   (dict 迭代序 / tween 回调序 = Phase4)·不在本测范围。Phase1 交付=决定结果的随机收束到一个可控源。
## 单实例(重场景·按 BSOD 风险记忆只开一个)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	OS.set_environment("TURTLE_SEED", "77777")
	RB.DEBUG_EDIT = true                     # 空编辑场·不跑整场战斗(轻)
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("★TURTLE_SEED 设时 _battle_rng 用该固定种子(可复现)", int(s._battle_rng.seed) == 77777, "seed=%d" % int(s._battle_rng.seed))
	_ok("★TURTLE_SEED 设时 _deterministic=true(Phase2b: _process 走固定步长 SIM_DT)", s._deterministic == true)
	# _juice_rng(演出)必须【不】被种子化 —— 否则回放画面卡死(Cliffski)。它走 randomize, seed≠77777
	_ok("★_juice_rng(演出)不被种子化(与 sim rng 分离)", int(s._juice_rng.seed) != 77777, "juice seed=%d" % int(s._juice_rng.seed))
	s.queue_free()
	OS.set_environment("TURTLE_SEED", "")
	print("ALL PASS — _battle_rng 可种子化 + 与 _juice_rng 演出随机分离(Phase1 RNG 源就位)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
