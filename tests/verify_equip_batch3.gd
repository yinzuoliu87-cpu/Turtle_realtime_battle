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

## 上架 94 件(不含羁绊赠送的 p2eq_095, 它 shopAvailable=0)
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
	# ★只数【上架】的件 —— 羁绊赠送的圣光护盾(p2eq_095, shopAvailable=0)不属于装备池,
	#   它既不参与费用分布、也没有类型, 混进来会让下面每一条分布断言都错。
	var eqs: Array = []
	for _e in DataRegistry.phase2_equipment:
		if _e is Dictionary and int((_e as Dictionary).get("shopAvailable", 0)) == 1:
			eqs.append(_e)
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
		## ★值可能是数组(一件多羁绊, 2026-08-13): 费用分布验的是**品类**, 取首要类型。
		var _tv = ty.get(eid, "")
		var t: String = str(_tv[0]) if (_tv is Array and not (_tv as Array).is_empty()) else str(_tv)
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
	_ok("② 上架 %d 件名字不重复" % eqs.size(), dup.is_empty(), str(dup))

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
		var eid2: String = str(d2.get("id", ""))
		if _has_effect_impl(eid2):
			continue        # 已实装的件, 文案【就该】写机制 —— 见下方 _has_effect_impl 的说明
		for w in MECH_WORDS:
			if txt.contains(w):
				lying.append("%s 文案含「%s」但效果层里没有它" % [eid2, w])
				break
	_ok("⑤ ★没实装的件文案里不出现机制词(防'文案说得到、实装做不到')", lying.is_empty(),
		str(lying.slice(0, 5)))
	# ★★反过来也要守: 已实装的件【必须】把逐星数值写进文案, 否则玩家买了不知道买了什么
	#   (方案书 20260804 R6:「不写文案 = 玩家买了不知道买了什么」, 这条不是可选项)。
	# ★判据取【文案里有没有 a/b/c 三元组】而不是"有没有某几个关键词" ——
	#   关键词表是给"没实装"那一半用的黑名单, 拿它当白名单会漏(实测漏掉 p2eq_089:
	#   "法力条集满时为全队回复 1.5/2.5/4% 已损失生命" 一个关键词都不含, 但它显然写了效果)。
	#   而三元组是硬判据, 且写下去之后 tools/tooltip_number_audit.py 会逐个去代码里对账。
	var trip := RegEx.new()
	trip.compile("\\d+(\\.\\d+)?/\\d+(\\.\\d+)?/\\d+(\\.\\d+)?")
	var silent: Array = []
	var impl := 0
	for e3 in eqs:
		var d3: Dictionary = e3
		var eid3: String = str(d3.get("id", ""))
		if int(eid3.replace("p2eq_", "")) < NEW_FIRST:
			continue
		if not _has_effect_impl(eid3):
			continue
		impl += 1
		var txt3: String = str(d3.get("effectDesc1", "")) + str(d3.get("effectDesc3", ""))
		if trip.search(txt3) == null:
			silent.append(eid3)
	_ok("⑤ ★★分母: 批3 里已实装效果的件 = %d 件(0 件的话下面那条是空检查)" % impl, impl > 0,
		"impl=%d" % impl)
	_ok("⑤ ★★已实装的件必须把逐星数值写进文案(反过来的那一半)", silent.is_empty(),
		str(silent.slice(0, 5)))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 35 件新装备(批3)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


var _impl_src := ""

## 这件装备在【效果层】里有没有实装分支。
##
## ★2026-08-04: 批 3 的 35 件原本【全部是纯属性】, 所以 ⑤ 本来写成"一个机制词都不许出现"。
##   批①(方案书 20260804-新装备35件效果) 实装了其中 15 件的周期效果, 它们的文案当然
##   必须写出机制 —— 于是这条断言从"全体禁言"升级成【双向对账】:
##     · 效果层里【没有】这件 ⇒ 文案一个机制词都不许写(原来的那一半, 一字未松)
##     · 效果层里【有】这件   ⇒ 文案【必须】写出机制(新加的那一半)
##   判据是"效果层源码里出现这个 id 字面量"(先剥注释, 免得命中说明文字) ——
##   比维护一张手写白名单强: 白名单会漂, 而漂了以后这条门禁就会保护一个谎言。
func _has_effect_impl(eid: String) -> bool:
	if _impl_src == "":
		for p in ["res://scripts/systems/equip/equip_system.gd",
				"res://scripts/systems/equip/equip_stats_apply.gd",
				"res://scripts/systems/equip/equip_tick_system.gd",
				# ★092 剧毒飞行物(2026-08-05)整件单独成文件, 且【故意没有】match 分支
				#   (它不是"周期到点触发一次"的形状, 驱动挂在 RelicSynergySystem.tick)。
				#   不把它加进这张名单, 这条门禁就会把一件真装了的装备判成"文案说得到做不到" ——
				#   与 memory [[project-god-file-decomposition]] 坑16「审计器的文件名单跟不上拆分」同形。
				"res://scripts/systems/equip/eq_venom_drone.gd"]:
			for ln in FileAccess.get_file_as_string(p).split("\n"):
				var hi: int = ln.find("#")
				_impl_src += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return _impl_src.contains("\"%s\"" % eid)
