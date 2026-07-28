extends Node
## verify_shop_merge_pips.gd — 商店「合成进度 N/3」显示的口径, 必须等于真实合成规则
##
## 由来 (2026-07-29)：用户问「符合局内规则么」。一查确实不符 ——
##   `GameState.auto_merge_all()` 的合成键是 "id|star"：必须【同 id 且同星】3 件才合。
##   而 `ShopScene._owned_count()` 原先【不分星级】地数同 id 件数。
## 实测(探针原文)：背包 1×★2 + 1×★1 → 数出 2 → 商店显示「合成进度 2/3」、圆点亮 2 颗；
##   再买 1 件 ★1 后 ★1=2 / ★2=1，**根本没合成**。进度条是承诺，这个承诺兑现不了。
##
## ★这条不是查 UI 好不好看，是查【显示的数字和真实规则是不是同一套】。
##   老的「已有N」文案是同一个错，只是文字没有进度条那么像承诺，所以没人发现。
##
## 查四件事：
##   ① 对照组: 纯 3×★1 确实会合成 (否则后面的"没合成"可能是别的原因 → 假阳性)
##   ② ★混星: 1×★2 + 1×★1 时, 商店数出来的必须是 1 (只数 ★1), 不是 2
##   ③ ★承诺兑现: 商店数到 2 时, 再买 1 件确实会合成
##   ④ 分母: 装备表非空
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shop_merge_pips.tscn

const SHOP := preload("res://scenes/Shop.tscn")
const EID := "p2eq_001"
const MERGE_N := 3        # 3 件同款同星 → 升 1 星

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.persistent_equipped = {}
	print("=== 商店合成进度口径 (装备 %s) ===" % EID)

	# ── ④ 分母 ──
	var dr = get_node_or_null("/root/DataRegistry")
	var n_eq: int = (dr.phase2_equipment as Array).size() if dr != null else 0
	print("  装备表 N=%d (★分母)" % n_eq)
	_chk("④ ★分母: 装备表非空", n_eq > 0)

	var sc = SHOP.instantiate()
	add_child(sc)
	for _i in range(4):
		await get_tree().process_frame

	# ── ① 对照组: 3×★1 到底合不合 ──
	gs.persistent_bench = []
	for _i in range(MERGE_N):
		gs.persistent_bench.append({"id": EID, "star": 1})
	gs.auto_merge_all()
	var s2_ctrl := _count(gs, 2)
	print("")
	print("  ① 对照组 %d×★1 → 合成后 ★2 数量 = %d (期望 1)" % [MERGE_N, s2_ctrl])
	_chk("① 合成机制本身是通的(否则后面的判断没意义)", s2_ctrl == 1)

	# ── ② ★混星时只该数 ★1 ──
	gs.persistent_bench = [
		{"id": EID, "star": 2},   # 已经合过一次的, 【不该】算进"再买1件就合成"的进度
		{"id": EID, "star": 1},
	]
	var owned: int = sc._owned_count(EID)
	print("")
	print("  ② 背包 = 1×★2 + 1×★1  →  商店数出 %d 件 (期望 1: 只数 ★1)" % owned)
	print("     圆点会亮 %d 颗 / 文案「合成进度 %d/%d」" % [owned, owned, MERGE_N])
	_chk("② ★混星时只数同星级(★2 不算进 ★1 的合成进度)", owned == 1)

	# ── ③ ★进度条的承诺必须兑现 ──
	#    构造"商店数到 MERGE_N-1 件"的局面, 再买 1 件, 必须真的合成。
	gs.persistent_bench = [{"id": EID, "star": 2}]        # 掺一件高星干扰
	for _i in range(MERGE_N - 1):
		gs.persistent_bench.append({"id": EID, "star": 1})
	var shown: int = sc._owned_count(EID)
	var s2_before := _count(gs, 2)
	gs.persistent_bench.append({"id": EID, "star": 1})    # 模拟"再买 1 件"
	gs.auto_merge_all()
	var s2_after := _count(gs, 2)
	print("")
	print("  ③ 商店显示「%d/%d」时再买 1 件: ★2 %d → %d" % [shown, MERGE_N, s2_before, s2_after])
	_chk("③ 显示的是「差 1 件」(%d/%d)" % [MERGE_N - 1, MERGE_N], shown == MERGE_N - 1)
	_chk("③ ★进度条的承诺兑现了(真的合成了)", s2_after > s2_before)

	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 商店合成进度口径" if _fail == 0 else "FAIL x%d — 显示口径与合成规则不一致" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _count(gs, star: int) -> int:
	var n := 0
	for it in gs.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == EID and int(it.get("star", 1)) == star:
			n += 1
	return n


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])
