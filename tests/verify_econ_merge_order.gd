extends Node
## verify_econ_merge_order.gd — 三合一 / 圣光护盾收回的结果不许随「统领装备表」字典的键序变(2026-11-24)
##
## 由来: 上周 alex + 4 个陪练号被服务器判 apply:equip:full。auto_merge_all 原来按 persistent_equipped.keys() 的顺序
##   找第一只交出装备的龟、把升星件放回它身上; 字典键序 = 插入顺序, 手机读档后(存档 JSON 按键名排序写盘)变字母序,
##   服务器重放从不读档 ⇒ 同一条「买入触发三合一」两边把升星件放到不同的龟身上(探针 tests/probes/_probe_econ_cap_overflow.gd)。
## 判据:
##   A 同一份背包 + 装备, 只是字典里石头龟 / 海盗龟谁在前不同(= 读档前 / 读档后)⇒ 三合一后两边逐字相同;
##     升星件放在按 id 排第一的那只交出装备的龟身上(pirate)。分母: 两份字典键序真的不同、真的合成了。
##   B 两只龟都戴着羁绊赠送的圣光护盾、要收回一件 ⇒ 两种键序收回的是同一只身上的。
## 反向: equipped_pids 改回不排序(直接用 keys())⇒ A、B 都红(2026-11-24 实测)。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_econ_merge_order.tscn

const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const ITEM := "p2eq_074"
const P2T := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, ("  " + detail) if detail != "" else "")


func _setup(gs, equipped: Dictionary, bench: Array) -> void:
	EconReplay.week_start(gs)
	gs.season_leaders = ["stone", "hunter", "pirate"]
	gs.season_level = 6
	gs.persistent_equipped = equipped
	gs.persistent_bench = bench
	gs.dual_lineup = gs.default_dual_lineup()


func _snap(gs) -> String:
	## 过一遍 JSON 再写: stringify 按键名排序(只比内容), 读回来整数一律成浮点(读档那份的 3.0 与没读档的 3 是同一个数)
	return JSON.stringify(JSON.parse_string(JSON.stringify({"eq": gs.persistent_equipped, "bench": gs.persistent_bench})))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 三合一 / 圣光护盾收回不随字典键序变 ===")
	var gs = GameState
	var tm0: bool = gs.test_mode
	gs.test_mode = true
	gs.econ_quiet = int(gs.econ_quiet) + 1
	var backup := {}
	for k in EconReplay.KEYS:
		var v = gs.get(k)
		backup[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v

	print("--- A 三合一 ---")
	## 石头龟先穿上(插入顺序 stone → pirate), 读档后变字母序(pirate → stone)
	var ins := {}
	ins["stone"] = [{"id": ITEM, "star": 1}, {"id": "p2eq_027", "star": 3}]
	ins["pirate"] = [{"id": ITEM, "star": 1}]
	var srt: Dictionary = JSON.parse_string(JSON.stringify(ins))
	_ok("A 分母: 两份字典键序真的不同(插入序 %s / 读档序 %s)" % [str(ins.keys()), str(srt.keys())], ins.keys() != srt.keys())
	_setup(gs, ins.duplicate(true), [{"id": ITEM, "star": 1}])
	gs.auto_merge_all()
	var a1 := _snap(gs)
	var a1_pirate: Array = (gs.persistent_equipped as Dictionary).get("pirate", [])
	var a1_stone: Array = (gs.persistent_equipped as Dictionary).get("stone", [])
	_setup(gs, srt.duplicate(true), [{"id": ITEM, "star": 1}])
	gs.auto_merge_all()
	var a2 := _snap(gs)
	var merged := a1_pirate.any(func(it): return str(it.get("id")) == ITEM and int(it.get("star")) == 2)
	_ok("A 分母: 真的合成了(背包 1 + 两只龟各 1 ⇒ 一件 ★2)", merged or a1_stone.any(func(it): return str(it.get("id")) == ITEM and int(it.get("star")) == 2), a1)
	_ok("★★A 插入序 / 读档序两边三合一结果逐字相同", a1 == a2, "\n      插入序 %s\n      读档序 %s" % [a1, a2])
	_ok("A 升星件放回按 id 排第一的交出装备的龟(pirate), 石头龟只剩 027", merged and a1_stone.size() == 1, "stone %s / pirate %s" % [str(a1_stone), str(a1_pirate)])

	print("--- B 圣光护盾收回 ---")
	## 猎人龟带 3 件不同的盾 ⇒ 盾羁绊 1 档 ⇒ 该有 1 件赠品; 石头龟 / 海盗龟各戴 1 件 ⇒ 要收回 1 件
	var shields: Array = []
	for e in DataRegistry.phase2_equipment:
		var eid := str((e as Dictionary).get("id", ""))
		if eid != "p2eq_095" and "盾" in P2T.types_of(eid) and shields.size() < 3:
			shields.append({"id": eid, "star": 1})
	var g_ins := {}
	g_ins["stone"] = [{"id": "p2eq_095", "star": 1}]
	g_ins["hunter"] = shields
	g_ins["pirate"] = [{"id": "p2eq_095", "star": 1}]
	var g_srt: Dictionary = JSON.parse_string(JSON.stringify(g_ins))
	_setup(gs, g_ins.duplicate(true), [])
	var want: int = int(gs.shield_grant_count())
	gs.sync_synergy_grants()
	var b1 := _snap(gs)
	_setup(gs, g_srt.duplicate(true), [])
	gs.sync_synergy_grants()
	var b2 := _snap(gs)
	_ok("B 分母: 这套阵容该有 1 件赠品、身上戴 2 件 ⇒ 正好收回 1 件(要比出收的是谁)", want == 1 and shields.size() == 3, "want=%d 盾 %d 件" % [want, shields.size()])
	_ok("★★B 两种键序收回的是同一只身上的", b1 == b2, "\n      插入序 %s\n      读档序 %s" % [b1, b2])

	for k in backup:
		gs.set(k, backup[k])
	gs.econ_quiet = int(gs.econ_quiet) - 1
	gs.test_mode = tm0
	print("")
	print("ALL PASS — 三合一 / 圣光护盾收回不随字典键序变 (%d 条)" % _n if _fail == 0 and _n >= 6 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
