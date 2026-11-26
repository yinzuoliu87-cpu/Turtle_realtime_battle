extends Node
## verify_gold_mask_persist.gd —— 135 黄金面具层数跨对局保留、只记在这一件上(2026-11-27 · 方案书 20261125c §5 · 迁移 20261127b)
##   用户 11-26「合成…层数是保留下来的」; 11-27「直接做就好了呀」。
## 判据:
##   A 合成: 三件 1★ 黄金面具(层数 2 / 3 / 0)合成 ⇒ 2★ 那件层数 5(背包里的那条三合一)
##   B 经济资产比对不含 gm_stk(层数变了不算漂移; 同 093 的 chg)
##   C 结果单 → 回包解析 parse_gold: 键要「龟|份号」、值要正数, 单件单局按 50 夹
##   D RefereeWatch.apply_gold: 按份号写回那只龟身上的第几件黄金面具; 找不到的那一项丢掉
##   E 裁判封顶 gold_cap: 合计压到服务器合计以内(按固定顺序扣), 服务器 0 ⇒ 全清
##   F 局内账 → 结果单 gold_new_of: 只出这一方、不出小将
##   G 进战斗那一步(eq_entry)带着层数; 局内开场按层数加最大生命 / 攻击
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RJ := preload("res://scripts/referee/referee_job.gd")
const EL := preload("res://scripts/gamedata/econ_ledger.gd")

var _n := 0
var _fail := 0


func _ok(name: String, c: bool, info: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", info)


func _gm(id: String, star: int, gm: int) -> Dictionary:
	var d := {"id": id, "star": star}
	if gm > 0:
		d["gm_stk"] = gm
	return d


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	print("=== 135 黄金面具层数跨对局 ===")

	## A 合成
	gs.persistent_bench = [_gm("p2eq_135", 1, 2), _gm("p2eq_135", 1, 3), _gm("p2eq_135", 1, 0)]
	gs.persistent_equipped = {}
	gs.auto_merge_all()
	var got = gs.persistent_bench[0] if (gs.persistent_bench as Array).size() == 1 else {}
	_ok("A 三件 1★(层数 2 / 3 / 0)合成 ⇒ 一件 2★ 层数 5", got is Dictionary and int(got.get("star", 0)) == 2 and int(got.get("gm_stk", 0)) == 5,
		str(gs.persistent_bench))

	## B 资产比对不含层数
	gs.persistent_equipped = {"ninja": [_gm("p2eq_135", 2, 5)]}
	var fp0: String = EL.fingerprint(gs)
	gs.persistent_equipped["ninja"][0]["gm_stk"] = 9
	_ok("B 层数 5 → 9 资产指纹不变(不算经济漂移)", EL.fingerprint(gs) == fp0)
	gs.persistent_equipped["ninja"][0]["star"] = 3
	_ok("B ★分母: 星级变了指纹会变(比对真在比)", EL.fingerprint(gs) != fp0)

	## C 回包解析
	var pg: Dictionary = RN.parse_gold({"ninja|p2eq_135": 3, "dice|p2eq_135#2": 80.0, "bad": 4, "x|p2eq_135": 0, "y|p2eq_135": "7", "z|p2eq_135": -2})
	_ok("C 解析: 合法两项留下(80 夹到 50), 键不对 / 0 / 字符串 / 负数丢掉", pg == {"ninja|p2eq_135": 3, "dice|p2eq_135#2": 50}, str(pg))
	_ok("C 不是字典 ⇒ 空", RN.parse_gold(5).is_empty() and RN.parse_gold(null).is_empty())

	## D 写回
	gs.persistent_equipped = {"ninja": [_gm("p2eq_135", 1, 0), _gm("p2eq_001", 1, 0), _gm("p2eq_135", 2, 1)], "dice": [_gm("p2eq_002", 1, 0)]}
	var hit: bool = RW.apply_gold(gs, {"gold_new": {"ninja|p2eq_135#2": 4, "ninja|p2eq_135": 2, "dice|p2eq_135": 9, "ghost|p2eq_135": 1}})
	var ne: Array = gs.persistent_equipped["ninja"]
	_ok("D 份号对上那一件: 第一件 0+2、第二件 1+4; 没有那件(dice / ghost)的丢掉", hit and int(ne[0].get("gm_stk", 0)) == 2 and int(ne[2].get("gm_stk", 0)) == 5
		and not ne[1].has("gm_stk") and not (gs.persistent_equipped["dice"][0] as Dictionary).has("gm_stk"), str(gs.persistent_equipped))
	_ok("D 回包没这个键 ⇒ 什么都不做", not RW.apply_gold(gs, {}) and not RW.apply_gold(gs, {"gold_new": {}}))

	## E 封顶
	var root := {"equipped": {"b_pet": [_gm("p2eq_135", 1, 5)], "a_pet": [_gm("p2eq_135", 1, 10), _gm("p2eq_001", 1, 0)]},
		"minions": [{"equips": [_gm("p2eq_135", 1, 4)]}]}
	var tot: int = RJ.gold_cap(root, 12)
	var a10: int = int(root["equipped"]["a_pet"][0].get("gm_stk", 0))
	var b5: int = int(root["equipped"]["b_pet"][0].get("gm_stk", 0))
	var m4: int = int(root["minions"][0]["equips"][0].get("gm_stk", 0))
	_ok("E 合计 19 压到 12: 按键排序先 equipped.a_pet 10 再 b_pet 留 2、小将 0", tot == 12 and a10 == 10 and b5 == 2 and m4 == 0, "%d %d %d %d" % [tot, a10, b5, m4])
	var root2 := {"equipped": {"p": [_gm("p2eq_135", 1, 7)]}}
	_ok("E 服务器 0 ⇒ 全清(键也删)", RJ.gold_cap(root2, 0) == 0 and not (root2["equipped"]["p"][0] as Dictionary).has("gm_stk"))
	var root3 := {"equipped": {"p": [_gm("p2eq_135", 1, 7)]}}
	_ok("E 服务器给得多 ⇒ 原样(不会变多)", RJ.gold_cap(root3, 99) == 7 and int(root3["equipped"]["p"][0]["gm_stk"]) == 7)

	## F 局内账 → 结果单
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	var ms = s._equip_sys._mask_sys
	ms.gold_gain = {"left|ninja|p2eq_135": 3, "left|ninja|p2eq_135#2": 1, "left|__minion__|p2eq_135": 2, "right|dice|p2eq_135": 6}
	_ok("F 左方: 两件龟身上的, 不出小将、不出右方", ms.gold_new_of("left") == {"ninja|p2eq_135": 3, "ninja|p2eq_135#2": 1}, str(ms.gold_new_of("left")))
	_ok("F 右方", ms.gold_new_of("right") == {"dice|p2eq_135": 6}, str(ms.gold_new_of("right")))

	## G 进战斗带着层数
	var ent: Dictionary = EqBombBatch.eq_entry(_gm("p2eq_135", 2, 6), 0)
	_ok("G eq_entry 带着 gm_stk", int(ent.get("gm_stk", 0)) == 6, str(ent))

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 黄金面具层数跨对局 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
