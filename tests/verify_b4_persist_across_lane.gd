extends Node
## verify_b4_persist_across_lane.gd — 常驻修正类(082/084/093)在【换路后】仍生效 (2026-08-25)
##
## 补 `docs/plans/20260804-新装备35件效果.md` 那条自标「❌」的验收项。
##
## ★它和 `verify_b4_lane_leak` 是**同一枚硬币的两面, 缺一不可**:
##     · lane_leak 守的是「换路后**该没的**要没」(召唤物/直升机/炮台/碑光环)
##     · 本文件守的是「换路后**该在的**要在」(装备的常驻修正被重新应用上)
##   只有前者时, 把装备注入整个删掉照样全绿 —— 什么都没有当然也没泄漏。
##
## ★必须走真入口 `_dl_build_lane_field()`(换路唯一管线), 且**先断言单位真的被重建了**
##   (`is_same(旧, 新) == false`) —— 否则"修正还在"可能只是因为我拿的还是同一个字典,
##   那是恒真式。(memory [[fb-write-without-reader-and-fake-gates]]: 换路类门禁的老坑)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_b4_persist_across_lane.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BLADE := preload("res://scripts/systems/equip/eq_blade_batch.gd")

## 三件常驻修正类 —— 与方案书那条验收项逐字对应。
const EQS := [
	{"id": "p2eq_082", "star": 2},    # 砗磲护心甲: 反伤 + 充能(常驻账在 eq_state)
	{"id": "p2eq_084", "star": 2},    # 手半剑: 近战改射程 / 远程把射程换成属性(常驻形态)
	{"id": "p2eq_093", "star": 2},    # 香火石: 刻痕带来的增伤/减伤(常驻加成)
]

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 场上那只【带这三件】的我方龟。
func _carrier():
	for u in _s._units:
		if str(u.get("side", "")) != "left":
			continue
		var ids := []
		for e in (u.get("equips", []) as Array):
			ids.append(str((e as Dictionary).get("id", "")))
		if "p2eq_084" in ids:
			return u
	return null


## 这只龟身上【常驻修正真的生效了】的证据 —— 量产品自己的字段, 不数我插的标记。
func _evidence(u: Dictionary) -> Dictionary:
	var ids := []
	for e in (u.get("equips", []) as Array):
		ids.append(str((e as Dictionary).get("id", "")))
	var st: Dictionary = u.get("eq_state", {})
	return {
		"eq_ids": ids,
		"b84_mode": str(u.get("_b84_mode", "")),          # 084 定了形态才会有
		"range": float(u.get("atk_range", 0.0)),          # 084 近战侧把射程改成 HH_MELEE_RANGE
		"st082": st.has("p2eq_082"),                      # on_spawn 跑过才会建这一条账
		"st093": st.has("p2eq_093"),
	}


## ★★换路要走【清场 + 重建】两步。
##   `_dl_build_lane_field()` **只 spawn 不清场** —— 清场在 `_dl_next_lane` 里
##   (`_st_snapshot_lane` → `_dl_clear_units()` → 重 spawn)。
##   我第一版只调 build, 结果两路的单位叠在场上, `_carrier()` 拿回的还是【上一路那只】
##   ⇒ "修正还在" 变成恒真式。**是下面那条 `is_same(旧,新)==false` 的分母断言当场逼出来的** ——
##   没有它, 这份门禁会以"全绿"的样子存在, 而它其实什么都没验。
func _build_lane(lane: String, first: bool = false) -> void:
	if not first:
		_s._dl_sys._dl_clear_units()
	_gs.current_lane = lane
	_s._dl_sys._dl_build_lane_field()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 常驻修正类(082/084/093)换路后仍生效 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	## 两路都摆一只带这三件的龟 —— 换路后阵容是【重新从 dual_lineup 生成】的,
	## 所以下一路也得配上, 否则测的是"下一路本来就没这只龟"而不是"修正丢了"。
	var lead: Array = _gs.season_leaders if _gs.season_leaders is Array else []
	var id0: String = str(lead[0]) if lead.size() > 0 else "stone"
	var id1: String = str(lead[1]) if lead.size() > 1 else "basic"
	var id2: String = str(lead[2]) if lead.size() > 2 else "diamond"
	_gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": id0, "slot": 0, "equips": EQS.duplicate(true)},
			{"kind": "leader", "id": id1, "slot": 1},
			{"kind": "minion", "role": "front"},
		],
		"bottom": [
			{"kind": "leader", "id": id2, "slot": 2, "equips": EQS.duplicate(true)},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "back"},
		],
	}

	_build_lane("top", true)
	await get_tree().process_frame
	var u0 = _carrier()
	_ok("★分母: 上路真的生成了带这三件的龟", u0 != null)
	if u0 == null:
		_done()
		return
	var e0 := _evidence(u0)
	_ok("★分母: 三件都注入到它身上了 %s" % str(e0["eq_ids"]),
		"p2eq_082" in e0["eq_ids"] and "p2eq_084" in e0["eq_ids"] and "p2eq_093" in e0["eq_ids"])
	_ok("① 上路: 084 定了形态(_b84_mode=%s)" % e0["b84_mode"], str(e0["b84_mode"]) != "")
	_ok("① 上路: 082 的常驻账建起来了(on_spawn 跑过)", bool(e0["st082"]))
	_ok("① 上路: 093 的常驻账建起来了", bool(e0["st093"]))

	# ── 换路 ──────────────────────────────────────────────
	_build_lane("bottom")
	await get_tree().process_frame
	var u1 = _carrier()
	_ok("★分母: 下路也生成了带这三件的龟", u1 != null)
	if u1 == null:
		_done()
		return
	## ★★这条是本文件成立的前提: 单位必须**真的被重建**过。
	##   如果 `is_same(u0, u1)` 为真, 下面"修正还在"是恒真式 —— 那不是门禁, 是自欺。
	_ok("★★分母: 换路后是【全新的单位字典】(is_same(旧,新) == false)", not is_same(u0, u1))

	var e1 := _evidence(u1)
	_ok("★★② 换路后三件仍在它身上 %s" % str(e1["eq_ids"]),
		"p2eq_082" in e1["eq_ids"] and "p2eq_084" in e1["eq_ids"] and "p2eq_093" in e1["eq_ids"])
	_ok("★★② 换路后 084 的形态被【重新定过】(_b84_mode=%s)" % e1["b84_mode"],
		str(e1["b84_mode"]) != "")
	_ok("★★② 换路后 082 的常驻账在", bool(e1["st082"]))
	_ok("★★② 换路后 093 的常驻账在", bool(e1["st093"]))
	## 084 近战侧会把射程改成 HH_MELEE_RANGE —— 若这一路的携带者是近战, 顺带验它真改了。
	if str(e1["b84_mode"]) == "melee":
		_ok("② 084 近战侧射程 = %d(不是原生射程)" % int(BLADE.HH_MELEE_RANGE),
			absf(float(e1["range"]) - BLADE.HH_MELEE_RANGE) < 0.01,
			"实得 %.0f" % float(e1["range"]))
	else:
		_ok("② 084 远程侧: 射程被转化掉(有效射程不再是原生值)", float(e1["range"]) > 0.0,
			"mode=%s range=%.0f" % [str(e1["b84_mode"]), float(e1["range"])])
	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 10:
		print("  [FAIL] ★分母: 断言只有 %d 条(<10) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 常驻修正跨路仍生效" if _fail == 0 else "FAIL x%d — 常驻修正跨路仍生效" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
