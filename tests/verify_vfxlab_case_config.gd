extends Node
## verify_vfxlab_case_config.gd — VFXLAB 台子配置表的结构门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  为什么要有这一条
## ════════════════════════════════════════════════════════════════════════
## 装备逐件体检里同一个配置坑栽了**六次**(023/026/029/030/031/043): `mana_kick` 给了
## 100, 而**未激活法器羁绊时法力条满值是 `MANA_FULL_BY_TIER[0] = 200`** ⇒ 只灌半条 ⇒
## 整段录下来什么都不发生, 而**台子不会报错**, 读出来的结论是"这件装备没效果"。
##
## 这类坑的共性: **配置是数据, 错了没有任何运行时症状** —— 只能靠这种表级门禁按住。
## 判据一律落在"这条配置能不能达成它自己的目的", 不落在"某个字段等于某个数"。
const LAB := preload("res://scripts/gamedata/vfxlab_cases.gd")
const STAFF := preload("res://scripts/systems/equip/staff_synergy_system.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _ready() -> void:
	print("=== VFXLAB 台子配置表 ===")
	var ids: Array = LAB.ids()
	_ok("★分母: 登记了 %d 个 case" % ids.size(), ids.size() >= 40)

	## ① mana_kick 灌得满灌不满 ────────────────────────────────────────────
	## 满值 = 档位满值 × 该件自己的倍率。**档 0 的 200 是最大值**(羁绊只会把它往下压),
	## 所以判据拿档 0 算 —— 灌够 200×倍率的, 无论台子配没配 tier 都一定能满。
	var kicked: Array = []
	var short: Array = []
	var partial: Array = []
	var not_staff: Array = []
	for id in ids:
		var c: Dictionary = LAB.get_case(id)
		var kick: float = float(c.get("mana_kick", 0.0))
		if kick <= 0.0:
			continue
		kicked.append(id)
		if bool(c.get("mana_partial", false)):
			partial.append(id)
			continue
		var eq: String = str(c.get("eq", ""))
		if P2T.type_of(eq) != "法器":
			not_staff.append("%s(%s=%s)" % [id, eq, P2T.type_of(eq)])
			continue
		var mult: Array = STAFF.MANA_FULL_PCT.get(eq, [])
		var star: int = clampi(int(c.get("star", 3)), 1, 3)
		var need: float = STAFF.MANA_FULL_BY_TIER[0]
		if not mult.is_empty():
			need *= 1.0 + float(mult[star - 1]) * 0.01
		if kick < need:
			short.append("%s(灌 %.0f < 满 %.0f)" % [id, kick, need])
	_ok("★分母: %d 个 case 配了 mana_kick(其中 %d 个显式标了半满)" % [kicked.size(), partial.size()],
		kicked.size() >= 10)
	_ok("① ★★配了 mana_kick 的 case 一律灌得满(短的 %d 个)" % short.size(), short.is_empty(),
		"; ".join(short) if not short.is_empty()
			else "档 0 满值 %.0f; 故意只灌半条的要显式写 mana_partial: true" % STAFF.MANA_FULL_BY_TIER[0])
	_ok("① ★灌法力的 case 身上那件必须是【法器】(否则灌了没人接): 越界 %d 个" % not_staff.size(),
		not_staff.is_empty(), "; ".join(not_staff))
	## ★分母的分母: 判据得真的算过"倍率"这一维, 否则 043 这种负面被动件是漏的
	_ok("★分母: 满值倍率表里有 %d 件(043 海浪护符 = %s)"
		% [STAFF.MANA_FULL_PCT.size(), str(STAFF.MANA_FULL_PCT.get("p2eq_043", []))],
		STAFF.MANA_FULL_PCT.has("p2eq_043"))

	## ② 拍点必须落在 dur 之内 ────────────────────────────────────────────
	## 超出 dur 的拍点**永远拍不到**, 而台子照样正常退出 —— 又一种"没有症状"的配置错。
	var out_of_dur: Array = []
	var unsorted: Array = []
	var n_shots := 0
	for id in ids:
		var c2: Dictionary = LAB.get_case(id)
		var shots: Array = c2.get("shots", [])
		if shots.is_empty():
			continue
		n_shots += 1
		var dur: float = float(c2.get("dur", 0.0))
		var prev: float = -1.0
		for t in shots:
			if float(t) > dur:
				out_of_dur.append("%s(拍点 %.2f > dur %.2f)" % [id, float(t), dur])
				break
		for t2 in shots:
			if float(t2) < prev:
				unsorted.append(id)
				break
			prev = float(t2)
	_ok("★分母: %d 个 case 配了拍点" % n_shots, n_shots >= 30)
	_ok("② ★拍点全落在 dur 之内(越界 %d 个)" % out_of_dur.size(), out_of_dur.is_empty(),
		"; ".join(out_of_dur))
	_ok("② 拍点按时间递增(乱序 %d 个)" % unsorted.size(), unsorted.is_empty(), "; ".join(unsorted))

	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 7:
		print("  [FAIL] ★断言只有 %d 条(<7) —— 用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — VFXLAB 配置表" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
