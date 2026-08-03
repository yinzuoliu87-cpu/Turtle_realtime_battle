extends Node
## verify_equip_batch3.gd — 35 件新装备（批 3 · 方案书 20260802-装备扩充 §7 批3）
##
## ★这一批的价值不是"选择变多"，而是**类型曝光被拉平**（方案书 §4.4.3）：
##   改之前灵物在 Lv5 的期望曝光只有 0.512（全池最低，前期几乎见不到），
##   药水 / 食物在 Lv10 只有 0.462 / 0.518（后期几乎消失，因为它们只有 1/2 费的货）。
##   ⇒ "想凑哪个羁绊"原本是被"这个类型有没有对应费用档的货"决定的，而不是被玩家决定的。
##   **这条门禁直接量那个数**，而不是只数"有没有 94 件"。
##
## ★★35 件全部是【纯属性装备，不带主动效果】—— 这是明确的范围决定（理由写在
##   `tools/oneoff/gen_batch3_items.py` 的文件头）。⑤ 专门断言它们的文案**不承诺机制**，
##   免得日后有人加了效果文案却没实装（本项目最恨的"文案说得到、实装做不到"）。
##
## 守五组：
##   ① 件数 94，且每个类型的件数 / 每费用的件数与方案书 §4.4.2 逐格吻合
##   ② 新增 35 件每件都有：类型、三档属性（非空）、emoji、名字不重复
##   ③ ★曝光拉平：十个类型在 Lv5/8/10 的期望曝光**标准差**必须显著低于改前
##   ④ 池深覆盖到每一件新装备（漏一件 = 那件永远抽不到）
##   ⑤ ★纯属性件的文案里不出现机制词（"每秒/每次/触发/造成/召唤/概率"）
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_batch3.tscn

const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")
const EquipPoolS := preload("res://scripts/gamedata/equip_pool.gd")
const Phase2Config := preload("res://scripts/gamedata/phase2_config.gd")

const WANT_TOTAL := 94
## 方案书 §4.4.2 最终态（写字面值，不引用被测数据）
const WANT_BY_TYPE := {
	"奇械": [2, 2, 2, 2, 2], "法器": [2, 2, 3, 2, 1], "灵物": [2, 2, 2, 2, 2],
	"遗物": [2, 2, 3, 2, 1], "剑": [2, 2, 2, 2, 1], "弓箭": [3, 3, 1, 1, 1],
	"枪": [2, 2, 1, 2, 2], "盾": [2, 1, 3, 2, 1], "药水": [3, 2, 1, 2, 1],
	"食物": [2, 2, 2, 2, 1],
}
const WANT_BY_COST := [22, 20, 20, 19, 13]
const NEW_FIRST := 60      # p2eq_060 起是批3 新增
## 改前（59 件态）的曝光标准差，来自方案书 §4.4.3 —— ★这是"改善了没有"的基准线，
## 不是随手填的阈值：Lv5 0.331 / Lv8 0.203 / Lv10 0.289。
const BEFORE_STD := {5: 0.331, 8: 0.203, 10: 0.289}
## 机制词：纯属性件的文案里出现任何一个，说明有人写了没实装的效果
const MECH_WORDS := ["每秒", "每 2.5", "每2.5", "触发", "造成", "召唤", "概率", "冷却", "叠加", "命中时"]

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
	await get_tree().process_frame
	print("=== 35 件新装备 (批3) ===")
	var eqs: Array = DataRegistry.phase2_equipment
	var f := FileAccess.open("res://data/p2eq-types.json", FileAccess.READ)
	var ty: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	# ── ① 件数与分布 ────────────────────────────────────────────
	_ok("① ★分母: 装备 %d 件" % WANT_TOTAL, eqs.size() == WANT_TOTAL, "实得 %d" % eqs.size())
	var by_tc: Dictionary = {}
	var by_cost := [0, 0, 0, 0, 0]
	for e in eqs:
		var eid: String = str((e as Dictionary).get("id", ""))
		var c: int = clampi(int((e as Dictionary).get("cost", 1)), 1, 5)
		var t: String = str(ty.get(eid, ""))
		by_cost[c - 1] += 1
		if not by_tc.has(t):
			by_tc[t] = [0, 0, 0, 0, 0]
		(by_tc[t] as Array)[c - 1] += 1
	var bad: Array = []
	for t in WANT_BY_TYPE:
		var got: Array = by_tc.get(t, [0, 0, 0, 0, 0])
		if str(got) != str(WANT_BY_TYPE[t]):
			bad.append("%s 期望 %s 实得 %s" % [t, str(WANT_BY_TYPE[t]), str(got)])
	_ok("① 十个类型的费用分布逐格吻合方案书 §4.4.2", bad.is_empty(), str(bad))
	_ok("① 每费用件数 == %s" % str(WANT_BY_COST), str(by_cost) == str(WANT_BY_COST),
		"实得 %s" % str(by_cost))

	# ── ② 新件完整性 ────────────────────────────────────────────
	var names: Dictionary = {}
	var dup: Array = []
	var incomplete: Array = []
	var new_n := 0
	for e in eqs:
		var d: Dictionary = e
		var eid: String = str(d.get("id", ""))
		var nm: String = str(d.get("name", ""))
		if names.has(nm):
			dup.append(nm)
		names[nm] = true
		var idx: int = int(eid.replace("p2eq_", ""))
		if idx < NEW_FIRST:
			continue
		new_n += 1
		var st: Array = EquipStats.STATS.get(eid, [])
		if st.size() != 3 or (st[0] as Dictionary).is_empty() or (st[2] as Dictionary).is_empty():
			incomplete.append("%s 属性档 %d 段" % [eid, st.size()])
		if str(d.get("emoji", "")) == "" or nm == "" or not ty.has(eid):
			incomplete.append("%s 缺 emoji/名字/类型" % eid)
		if str(d.get("baseStats1", "")).strip_edges() == "":
			incomplete.append("%s baseStats1 空" % eid)
	_ok("② ★分母: 新增 %d 件(p2eq_%03d 起)" % [new_n, NEW_FIRST], new_n == 35, "实得 %d" % new_n)
	_ok("② 新件三档属性 / emoji / 名字 / 类型 / 属性串 全都齐", incomplete.is_empty(),
		str(incomplete.slice(0, 5)))
	_ok("② 全表 94 件名字不重复", dup.is_empty(), str(dup))

	# ── ③ ★曝光拉平（这一批的真正收益） ────────────────────────
	# E_type(Lv) = Σ(该类型每费用的件数 × 该费用出货率 / 该费用总件数) × 每次刷新格数(10)
	var std_line: Array = []
	var worse: Array = []
	for lv in [5, 8, 10]:
		var odds: Array = Phase2Config.SHOP_COST_ODDS[lv - 1]
		var es: Array = []
		for t in WANT_BY_TYPE:
			var e_t := 0.0
			for c in range(5):
				if by_cost[c] > 0:
					e_t += float((by_tc[t] as Array)[c]) * (float(odds[c]) / 100.0) / float(by_cost[c])
			es.append(e_t * 10.0)
		var mean := 0.0
		for v in es:
			mean += v
		mean /= float(es.size())
		var var_ := 0.0
		for v in es:
			var_ += (v - mean) * (v - mean)
		var std: float = sqrt(var_ / float(es.size()))
		std_line.append("Lv%d %.3f(改前 %.3f)" % [lv, std, float(BEFORE_STD[lv])])
		if std >= float(BEFORE_STD[lv]):
			worse.append("Lv%d 标准差 %.3f 没有低于改前的 %.3f" % [lv, std, float(BEFORE_STD[lv])])
	_ok("③ ★★类型曝光离散度低于改前(这才是加 35 件的收益)", worse.is_empty(),
		" / ".join(PackedStringArray(std_line)))

	# ── ④ 池深覆盖 ──────────────────────────────────────────────
	var pool: Dictionary = EquipPoolS.full_pool(eqs)
	var nopool: Array = []
	for e in eqs:
		var eid2: String = str((e as Dictionary).get("id", ""))
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and EquipPoolS.left(pool, eid2) <= 0:
			nopool.append(eid2)
	_ok("④ 每件上架装备在池里都有张数(漏一件=那件永远抽不到)", nopool.is_empty(), str(nopool))

	# ── ⑤ ★纯属性件的文案不承诺机制 ────────────────────────────
	var lying: Array = []
	for e in eqs:
		var d2: Dictionary = e
		var idx2: int = int(str(d2.get("id", "")).replace("p2eq_", ""))
		if idx2 < NEW_FIRST:
			continue
		var txt: String = str(d2.get("effectDesc1", "")) + str(d2.get("effectDesc3", ""))
		for w in MECH_WORDS:
			if txt.contains(w):
				lying.append("%s 文案含「%s」" % [str(d2.get("id", "")), w])
				break
	_ok("⑤ ★纯属性件的文案里不出现机制词(防'文案说得到、实装做不到')", lying.is_empty(),
		str(lying.slice(0, 5)))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 35 件新装备(批3)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
