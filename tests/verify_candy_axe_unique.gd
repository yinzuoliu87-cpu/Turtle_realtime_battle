extends Node
## verify_candy_axe_unique.gd —— 糖果罐不许抽出第二把小木斧; 自动三合一跳过不升星的件(2026-10-11 全项目通读 B2)
##
## ★读码发现: 糖果罐 1 费池含 p2eq_096 且不查 axe_owned(); auto_merge_all 不跳 EquipPool.NO_STAR
##   (try_merge_all 跳了)。小木斧「只能拥有一把、不升星」(用户 2026-08-31)。
## ★判据走产品函数: 已有一把斧头时连抽 400 次 _candy_jar_pick_equip([1]) ⇒ 一次都不出 096;
##   背包放 3 把 1★ 小木斧调 auto_merge_all ⇒ 不合成 2★。

const EP := preload("res://scripts/gamedata/equip_pool.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 糖果罐与小木斧唯一性 ===")
	var gs = GameState
	gs.test_mode = true
	var keep_bench: Array = gs.persistent_bench.duplicate(true)
	var keep_eq = gs.persistent_equipped.duplicate(true)
	var axe_cost: int = 0
	for e in DataRegistry.phase2_equipment:
		if str(e.get("id", "")) == "p2eq_096":
			axe_cost = int(e.get("cost", 0))
	_ok("★分母: 小木斧在装备表里(费 %d)" % axe_cost, axe_cost > 0)
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	var hit0 := 0
	for i in range(400):
		if gs._candy_jar_pick_equip([axe_cost]) == "p2eq_096":
			hit0 += 1
	_ok("★分母: 没有斧头时, 同费池里确实抽得到它(%d/400)" % hit0, hit0 > 0)
	gs.persistent_bench = [gs.mk_eq("p2eq_096", 1)]
	var hit1 := 0
	for i in range(400):
		if gs._candy_jar_pick_equip([axe_cost]) == "p2eq_096":
			hit1 += 1
	_ok("★★已有一把斧头 ⇒ 糖果罐 400 次一次都不出第二把", hit1 == 0, "%d/400" % hit1)
	gs.persistent_bench = [gs.mk_eq("p2eq_096", 1), gs.mk_eq("p2eq_096", 1), gs.mk_eq("p2eq_096", 1)]
	gs.auto_merge_all()
	var stars: Array = []
	for it in gs.persistent_bench:
		stars.append(int(it.get("star", 1)))
	_ok("★★3 把 1★ 小木斧 ⇒ auto_merge_all 不合成(不升星的件)", stars.size() == 3 and not (2 in stars), str(stars))
	gs.persistent_bench = keep_bench
	gs.persistent_equipped = keep_eq
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
