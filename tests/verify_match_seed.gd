extends Node
## verify_match_seed.gd — 结构治理·切片1: 匹配单一受控 PRNG
## 大厂做法(Riot「隔离一个受控 PRNG」): 把匹配随机收束到 Backend.make_match_rng() 一个入口。
## 守: ①同 TURTLE_SEED → 同种子、randi 序列逐位相同(可复现)
##     ②find_opponent 同种子 → 抽到同一对手(= CI「随机敌队 vs 本地」偶发红的根因灭)
##     ③无 TURTLE_SEED → randomize(两次种子不同·默认行为=随机·与线上一致)
## 反向证据: ③证明"确定性"非恒真(默认仍随机); ①用非空池 + 真 ghost_id 防 vacuous 断言。

const Backend := preload("res://scripts/net/backend.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	# ① make_match_rng 读 TURTLE_SEED → 固定种子 + 序列可复现
	OS.set_environment("TURTLE_SEED", "12345")
	var a := Backend.make_match_rng()
	var b := Backend.make_match_rng()
	_ok("同 TURTLE_SEED → 两 rng 种子相同且=12345", a.seed == b.seed and int(a.seed) == 12345, "seed=%d" % int(a.seed))
	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(6):
		seq_a.append(a.randi())
		seq_b.append(b.randi())
	_ok("同种子 → randi 序列逐位相同(可复现)", seq_a == seq_b)

	# 找一个池里有真 ghost 的档(分母·防 vacuous: 两个空 ghost_id 相等是假通过)
	var bk := -1
	for cand in range(0, 9):
		var gg := Backend.find_opponent(cand, [], Backend.make_match_rng())
		if str(gg.get("ghost_id", "")) != "":
			bk = cand
			break
	_ok("★池非空·找到带真 ghost 的档(分母)", bk >= 0, "档 %d" % bk)

	# ② find_opponent 同种子 → 同对手(端到端·真 ghost 池)
	if bk >= 0:
		var g1 := Backend.find_opponent(bk, [], Backend.make_match_rng())
		var g2 := Backend.find_opponent(bk, [], Backend.make_match_rng())
		var id1 := str(g1.get("ghost_id", ""))
		var id2 := str(g2.get("ghost_id", ""))
		_ok("★同种子 → find_opponent 抽到同一对手(CI偶发红根因灭)", id1 != "" and id1 == id2, "%s" % id1)

	# ③ 无 TURTLE_SEED → randomize(两次种子不同·默认=随机·线上行为不变)
	OS.set_environment("TURTLE_SEED", "")
	var r1 := Backend.make_match_rng()
	var r2 := Backend.make_match_rng()
	_ok("无 TURTLE_SEED → randomize(两次种子不同·默认仍随机)", int(r1.seed) != int(r2.seed))

	print("ALL PASS — 匹配单一受控PRNG(种子可复现/默认仍随机)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
