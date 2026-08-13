extends Node
## verify_equip_types.gd — 装备【类型羁绊】的结构门禁（批 1 · 方案书 20260802-装备扩充 §7 批1⑤）
##
## ★为什么必须先有它：实测 `grep -rln "Phase2Types|羁绊|p2eq-types" tests/` = **0** ——
##   类型集合 / 每件归类 / 档位阈值 / 羁绊 Tab，**一个测试都没有**。
##   而批 1 要同时做「删学派」「类型 12→10」「9 件重新归类」「阈值全改」四件事，
##   没有门禁的话**改错了不会有任何东西变红**（方案书 R4：本方案最大的假绿灯面）。
##
## ★这个文件是【先于实现】写的，写完当场在【未改】状态跑过一次，确认它 FAIL 了 6 条
##   （12 个类型 / 护符饰品还在 / 9 件还没搬 / 阈值还是旧的 / TIER_DESCS 段数不匹配 / 羁绊 Tab 是 11 学派）。
##   —— 这就是它"会 FAIL"的证明，不需要再造变异（memory [[fb-verify-check-can-fail]]）。
##
## 守六组：
##   ① 类型集合恰好是这 10 个（护符 / 饰品必须【不在】—— 反向断言，防"改了名单却没删干净"）
##   ② 每件装备恰好 1 个类型，且 59 件全覆盖、无孤儿 id、无指向已删类型的条目
##   ③ 每个类型的件数 == 方案书 §4.4.2 的「现→后」列（这是 9 件重新归类的判据）
##   ④ 档位阈值 == 方案书 §4.5.1（10 件的类型 [2,5,8,10] / 9 件的 [3,6,9]）
##   ⑤ TIER_DESCS / stats 的【段数】必须与 tiers 长度一致，且每段非空
##      —— 拆档最容易漏的就是这个：阈值改成 4 档而文案只有 2 段，面板会读越界
##   ⑥ 顶档阈值 == 该类型件数（方案书 D5「顶档 == 件数是有意为之」，焊死免得被当 bug 改掉）
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_types.tscn

## ★phase2_types.gd 没有 class_name(它是 RefCounted 纯数据表), 全项目都靠 preload 引 ——
## 照 CodexScene.gd:49 / InventoryScene.gd:14 的既有写法。
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const TYPES_JSON := "res://data/p2eq-types.json"

## 方案书 §4.4.2「现→后」列 —— ★写【字面值】不引用被测常量，否则是恒真式
## （本项目 verify_trainer_magicstone 第一版真栽过：引用被测常量，改掉常量测试照样全绿）。
const WANT_COUNT := {
	"奇械": 10, "法器": 10, "灵物": 10, "遗物": 10, "剑": 9,
	"弓箭": 9, "枪": 9, "盾": 9, "药水": 9, "食物": 9,
}
## 方案书 §4.5.1 新阈值
const WANT_TIERS := {
	"奇械": [2, 5, 8, 10], "法器": [2, 5, 8, 10], "灵物": [2, 5, 8, 10], "遗物": [2, 5, 8, 10],
	"剑": [3, 6, 9], "弓箭": [3, 6, 9], "枪": [3, 6, 9], "盾": [3, 6, 9],
	"药水": [3, 6, 9], "食物": [3, 6, 9],
}
## 方案书 §4.4.2 的【最终 94 件态】件数 —— ⑥「顶档 == 件数」是对这一列说的（D5），
## 与"现在有几件"无关。★批 1~2 期间 35 件还没加，所以顶档【暂时够不到】：
##   例如剑顶档 9 而现在只有 7 件。这是"先定阈值、后加装备"这个批次顺序的必然结果，
##   在批 3 做完之前，十个类型的顶档全部不可达。
##   **这期间没有玩法影响** —— 羁绊在战斗里本来就一行效果都没有（方案书 §2.5，
##   `apply_team_start` 全仓库零调用方），玩家只是在背包羁绊面板上看到一个够不到的档位。
##   ⑧ 把这件事显式记账，免得批 3 之前有人看到"顶档点不亮"以为是 bug。
const WANT_FINAL := {
	"奇械": 10, "法器": 10, "灵物": 10, "遗物": 10, "剑": 9,
	"弓箭": 9, "枪": 9, "盾": 9, "药水": 9, "食物": 9,
}
## 已解散的类型 —— 出现即红（D2）
const GONE := ["护符", "饰品"]
## 批 1 不加装备, 件数仍是 59（批 3 会逐子批改成 71/82/94, 那时这条要跟着改 —— 方案书 R6 同款设计:
## 它逼你显式确认件数变了, 而不是让件数悄悄漂）
## p2eq-types.json 只映射【上架的 94 件】—— 羁绊赠送的圣光护盾(p2eq_095)【故意没有类型】:
## 给它"盾"就会【送盾 → 盾件数+1 → 档位涨 → 再送盾】无限循环。
const WANT_ITEMS := 94

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
	print("=== 装备类型羁绊结构门禁 (批1) ===")

	var f := FileAccess.open(TYPES_JSON, FileAccess.READ)
	if f == null:
		print("  [FAIL] 读不到 ", TYPES_JSON)
		get_tree().quit(1)
		return
	var map: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	# ── ① 类型集合 ──────────────────────────────────────────────
	var keys: Array = Phase2Types.TYPES.keys()
	keys.sort()
	var want_keys: Array = WANT_COUNT.keys()
	want_keys.append("香火")
	want_keys.sort()
	## ★2026-08-13 新增第 11 条「香火」(用户:「093应该有两个羁绊: 遗物和香火」)。
	##   它只有 1 档、没有逐档属性(收益全部来自刻痕), 所以不进 WANT_COUNT 的费用分布表。
	_ok("① 类型集合 = 10 条常规 + 香火", keys == want_keys,
		"实得 %d 个: %s" % [keys.size(), str(keys)])
	for g in GONE:
		_ok("① ★已解散的「%s」不在 TYPES 里(反向断言)" % g, not Phase2Types.TYPES.has(g))
		_ok("① ★已解散的「%s」不在 TYPE_EMOJI/TYPE_NAME/TIER_DESCS 里" % g,
			not Phase2Types.TYPE_EMOJI.has(g) and not Phase2Types.TYPE_NAME.has(g)
			and not Phase2Types.TIER_DESCS.has(g))

	# ── ② 每件恰好 1 个类型 · 全覆盖 · 无孤儿 ────────────────────
	_ok("② ★分母: p2eq-types.json 有 %d 条映射" % WANT_ITEMS, map.size() == WANT_ITEMS,
		"实得 %d 条" % map.size())
	## ★值可以是【字符串或数组】(一件装备可属多条羁绊, 2026-08-13): 逐个类型验存在。
	var orphan: Array = []       # 指向不存在类型的条目
	for iid in map:
		var vs: Array = (map[iid] if map[iid] is Array else [map[iid]])
		for one in vs:
			if not Phase2Types.TYPES.has(str(one)):
				orphan.append("%s→%s" % [iid, str(one)])
	_ok("② ★没有指向已删类型的装备(9 件重新归类的判据)", orphan.is_empty(),
		"孤儿 %d 件: %s" % [orphan.size(), str(orphan.slice(0, 6))])
	# 装备表里的每件都要有类型（反过来: json 里不能有表里没有的 id）
	# ★只对【上架】的件要求"必须有类型" —— 羁绊赠送的圣光护盾(p2eq_095)故意没有类型
	#   (给它"盾"会造成 送盾→盾数+1→档位涨→再送盾 的无限循环)。
	var eq_ids: Array = []
	for e in DataRegistry.phase2_equipment:
		if e is Dictionary and int((e as Dictionary).get("shopAvailable", 0)) == 1:
			eq_ids.append(str(e.get("id", "")))
	var missing: Array = []
	for iid in eq_ids:
		if not map.has(iid):
			missing.append(iid)
	var extra: Array = []
	for iid in map:
		if not (str(iid) in eq_ids):
			extra.append(str(iid))
	_ok("② 上架 %d 件全都有类型 · json 里也没有多余 id" % eq_ids.size(),
		missing.is_empty() and extra.is_empty(),
		"缺 %s / 多 %s" % [str(missing), str(extra)])

	# ── ③ 每类型件数 ────────────────────────────────────────────
	var cnt: Dictionary = {}
	## ★值可以是数组(一件多羁绊) ⇒ 逐个类型计数; 093 因此同时进遗物与香火两格。
	for iid in map:
		for one in (map[iid] if map[iid] is Array else [map[iid]]):
			cnt[str(one)] = int(cnt.get(str(one), 0)) + 1
	var bad_cnt: Array = []
	for t in WANT_COUNT:
		var got: int = int(cnt.get(t, 0))
		if got != int(WANT_COUNT[t]):
			bad_cnt.append("%s 期望 %d 实得 %d" % [t, int(WANT_COUNT[t]), got])
	_ok("③ ★十个类型件数逐个吻合(合计应 %d)" % WANT_ITEMS, bad_cnt.is_empty(), str(bad_cnt))

	# ── ④ 档位阈值 ──────────────────────────────────────────────
	var bad_t: Array = []
	for t in WANT_TIERS:
		var d = Phase2Types.TYPES.get(t, {})
		var got: Array = (d as Dictionary).get("tiers", []) if d is Dictionary else []
		if str(got) != str(WANT_TIERS[t]):
			bad_t.append("%s 期望 %s 实得 %s" % [t, str(WANT_TIERS[t]), str(got)])
	_ok("④ ★十个类型阈值逐个吻合(4档 [2,5,8,10] / 3档 [3,6,9])", bad_t.is_empty(), str(bad_t))

	# ── ⑤ 段数一致 ──────────────────────────────────────────────
	# 拆档最容易漏这个: 阈值改成 4 档、文案还是 2 段 → 面板读越界。
	var bad_seg: Array = []
	for t in WANT_TIERS:
		var n: int = (WANT_TIERS[t] as Array).size()
		var descs: Array = Phase2Types.TIER_DESCS.get(t, [])
		var stats: Array = (Phase2Types.TYPES.get(t, {}) as Dictionary).get("stats", [])
		if descs.size() != n:
			bad_seg.append("%s TIER_DESCS %d 段 ≠ %d 档" % [t, descs.size(), n])
		if stats.size() != n:
			bad_seg.append("%s stats %d 段 ≠ %d 档" % [t, stats.size(), n])
		for i in range(descs.size()):
			if str(descs[i]).strip_edges() == "":
				bad_seg.append("%s 第%d档文案是空的" % [t, i + 1])
	_ok("⑤ ★TIER_DESCS/stats 段数 == 档数, 且每段非空", bad_seg.is_empty(), str(bad_seg))

	# ── ⑥ 顶档 == 【最终】件数（D5，焊死） ──────────────────────
	var bad_top: Array = []
	for t in WANT_TIERS:
		var tiers: Array = WANT_TIERS[t]
		var top: int = int(tiers[tiers.size() - 1])
		if top != int(WANT_FINAL[t]):
			bad_top.append("%s 顶档 %d ≠ 最终件数 %d" % [t, top, int(WANT_FINAL[t])])
	_ok("⑥ ★顶档阈值 == 该类型【最终】件数(D5 有意为之, 不是 bug)", bad_top.is_empty(), str(bad_top))

	# ── ⑧ 顶档可达性【记账】—— 批 3 加完 35 件之前顶档够不到, 这是已知且无影响的 ──
	var unreach: Array = []
	for t in WANT_TIERS:
		var tiers2: Array = WANT_TIERS[t]
		if int(tiers2[tiers2.size() - 1]) > int(WANT_COUNT[t]):
			unreach.append("%s(%d/%d)" % [t, int(WANT_COUNT[t]), int(tiers2[tiers2.size() - 1])])
	# ★这条【不是】"越少越好"的断言, 而是"必须与当前批次一致"的记账:
	#   现在是 59 件态 ⇒ 十个类型的顶档都够不到, 就该是 10 个;
	#   批 3 每加一个子批, WANT_COUNT 跟着改, 这个数自然往下掉, 全加完应为 0。
	#   哪天它对不上, 说明件数与阈值有一边改漏了。
	_ok("⑧ 顶档可达性记账: %d 件态下有 %d 个类型顶档不可达(应 %d)"
			% [WANT_ITEMS, unreach.size(), _want_unreachable()],
		unreach.size() == _want_unreachable(),
		str(unreach))

	# ── ⑦ ★计数口径: 按装备 id【去重】、不看星（用户 2026-08-03 拍板）────
	# 带两件一模一样的剑只算 1 个羁绊数 ⇒ 顶档 == 集齐该类型的全部装备。
	# ★重要后果: **合成 3★ 不再扣羁绊数**（去重前 3 件同款算 3、合成后剩 1 算 1 ⇒ −2;
	#   去重后本来就算 1 ⇒ ±0）。这推翻了方案书 §4.5.2「走宽与走高互斥」的论点 ——
	#   但那个设计等于"升星要罚你掉羁绊", 玩家会觉得憋屈。
	# ★背包面板(calc_active)与战斗侧(synergy_system._calc_tiers)【必须同口径】,
	#   否则面板亮着顶档而打起来不是 —— 那是最难查的一类 bug。这条守的就是面板侧。
	var a1: String = _first_of("剑")
	var a2: String = _second_of("剑")
	var a3: String = _third_of("剑")
	# 5 个条目 / 但只有 3 个不同 id ⇒ 应记 3
	var team := [{"_p2_equips": [
		{"id": a1, "star": 1}, {"id": a1, "star": 3}, {"id": a1, "star": 1},
		{"id": a2, "star": 1}, {"id": a3, "star": 1},
	]}]
	var act: Array = Phase2Types.calc_active(team)
	var sword := 0
	for a in act:
		if str(a.get("type", "")) == "剑":
			sword = int(a.get("count", 0))
	_ok("⑦ ★计数口径: 5 个条目但只有 3 个不同 id → 记作 3(按 id 去重, 不看星)", sword == 3,
		"实得 %d" % sword)

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 装备类型羁绊结构(批1)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 当前件数态下【应有】几个类型顶档够不到 —— 从 WANT_COUNT/WANT_TIERS 直接算,
## 不写死。批3 每加一个子批这个数自然往下掉, 全加完是 0。
func _want_unreachable() -> int:
	var n := 0
	for t in WANT_TIERS:
		var tt: Array = WANT_TIERS[t]
		if int(tt[tt.size() - 1]) > int(WANT_COUNT[t]):
			n += 1
	return n


func _first_of(t: String) -> String:
	var f := FileAccess.open(TYPES_JSON, FileAccess.READ)
	var map: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for iid in map:
		if str(map[iid]) == t:
			return str(iid)
	return ""


func _third_of(t: String) -> String:
	return _nth_of(t, 3)


func _nth_of(t: String, n: int) -> String:
	var f := FileAccess.open(TYPES_JSON, FileAccess.READ)
	var map: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var seen := 0
	for iid in map:
		if str(map[iid]) == t:
			seen += 1
			if seen == n:
				return str(iid)
	return ""


func _second_of(t: String) -> String:
	var f := FileAccess.open(TYPES_JSON, FileAccess.READ)
	var map: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var seen := 0
	for iid in map:
		if str(map[iid]) == t:
			seen += 1
			if seen == 2:
				return str(iid)
	return ""
