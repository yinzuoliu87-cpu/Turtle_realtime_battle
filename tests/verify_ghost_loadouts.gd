extends Node
## verify_ghost_loadouts.gd — 鬼影对手要用【它自己选的技能】，不是一律签名技
##
## ══════════════════════════════════════════════════════════════════════
##  由来（2026-09-17，查大轮赛制 v2 §10「拿现有代码当尺子」时捞出来的）
## ══════════════════════════════════════════════════════════════════════
## 消费侧一直活着：`RealtimeBattle3DScene.gd:5192-5193` 读 `GameState.foe_loadouts[id]`
## 决定**敌方龟用哪个技能**，注释写着「敌侧: ghost快照的技能选择(**用户 2026-07-15 ghost带技能**)」。
## 而生产侧 `backend.gd` 的 `build_ghost_snapshot` **写死 `"loadouts": {}`**，全仓 0 处补写
## ⇒ 打到的鬼影**永远**用 `idx = 1` 签名技（`:5183` `var idx := 1`），
## 一个用户点名要过的功能静默失效。**此前 0 条门禁覆盖**（全仓只有探针 `tests/_duel.gd:241` 喂过非空值）。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★这类 bug 的形状是「生产侧写了空、消费侧照读」——**只验一侧必然抓不到**：
##   · 只验快照里有 loadouts ⇒ 消费侧断了也全绿（「写了没人读」）
##   · 只验消费侧会读 ⇒ 生产侧写空也全绿（「读了没人写」，正是这次的形状）
##   ⇒ 所以 ① 走**真生产函数** `build_ghost_snapshot()` 拿快照，
##      ② 再把它喂给**真消费路径**（`GameState.foe_loadouts` ← 快照，然后问真正的选技函数 `_resolve_chosen_index` 拿 idx），
##      ③ 断言拿到的是玩家选的那个 idx，而不是默认 1。
## ★每条配分母：先证明「玩家确实选了一个不是 1 的技能」，否则"等于玩家的选择"是恒真式。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 鬼影快照要带技能选择 ===")

	# ── 摆一个「玩家选了非默认技能」的局面 ──
	var PID := "basic"
	var PICK := 2                       # ★写死 2：默认是 1，选 2 才能把「是不是默认」区分开
	## ★`left_team` 是带类型标注的 Array[String], 直接赋裸 Array 会**运行时**报
	##   「Invalid assignment ... of type Array」⇒ `_ready` 当场中止、后面的断言一条都不跑,
	##   而退出码仍是 0(同族 memory fb-null-readback-makes-test-silently-abort)。用 assign()。
	gs.left_team.assign([PID, "stone", "bamboo"])
	gs.season_leaders = [PID, "stone", "bamboo"]
	gs.loadouts = {PID: PICK}
	gs.season_total_battles = 5

	_ok("① ★分母: 玩家的选择不是默认值(默认 idx=1)", PICK != 1, "玩家选了 idx=%d" % PICK)

	# ── ② 走真生产函数拿快照 ──
	var snap: Dictionary = Backend.build_ghost_snapshot("probe_ghost", {"name": "探针"})
	var lo = snap.get("loadouts", null)
	_ok("② ★分母: 真生产函数吐出了快照", snap is Dictionary and not snap.is_empty())
	_ok("② 快照里带了 loadouts 且不是空字典(这正是修之前的样子)",
		lo is Dictionary and not (lo as Dictionary).is_empty(),
		"loadouts=%s" % str(lo))
	_ok("② 快照记的就是玩家选的那个 idx",
		lo is Dictionary and int((lo as Dictionary).get(PID, -1)) == PICK,
		"快照里 %s = %s" % [PID, str((lo as Dictionary).get(PID, null)) if lo is Dictionary else "n/a"])
	## 只带这份快照里真有的龟 —— 不把玩家对别的龟的选择一起传上云
	gs.loadouts["notinteam"] = 3
	var snap2: Dictionary = Backend.build_ghost_snapshot("probe_ghost", {"name": "探针"})
	var lo2: Dictionary = snap2.get("loadouts", {})
	_ok("② 不在阵容里的龟不进快照(别把无关选择传上云)",
		not lo2.has("notinteam"), "loadouts 的键 = %s" % str(lo2.keys()))
	gs.loadouts.erase("notinteam")

	# ── ③ 把快照喂进真消费路径, 问真正的选技函数 `_resolve_chosen_index` 拿 idx ──
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame

	## 消费侧的真入口: RealtimeBattle3DScene.gd:1566 就是这么把快照灌进 foe_loadouts 的
	gs.foe_loadouts = (snap.get("loadouts", {}) as Dictionary).duplicate(true)
	var idx_foe: int = scene._resolve_chosen_index(PID, false)    # false = 敌侧(不走玩家 loadouts)
	var idx_mine: int = scene._resolve_chosen_index(PID, true)    # true  = 我方
	_ok("③ ★★敌侧拿到的是【对方选的技能】而不是默认签名技",
		idx_foe == PICK, "敌侧 idx=%d(应为 %d, 默认是 1)" % [idx_foe, PICK])
	_ok("③ ★分母: 我方那条一直是通的(对照组)", idx_mine == PICK,
		"我方 idx=%d" % idx_mine)

	# ── ④ 快照没带这只龟时, 回落到默认 —— 别因为修了这条就崩 ──
	gs.foe_loadouts = {}
	var idx_empty: int = scene._resolve_chosen_index(PID, false)
	_ok("④ 快照缺这只龟 → 回落默认 idx=1(老快照/bot 走这条)", idx_empty == 1,
		"idx=%d" % idx_empty)

	scene.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 鬼影技能选择" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
