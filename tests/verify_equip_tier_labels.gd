extends Node
## verify_equip_tier_labels.gd — 图鉴装备分星表用短标签(2026-10-14)
##
## 方案书: docs/plans/20261014-装备分星短标签.md · 标签表: scripts/gamedata/equip_tier_labels.gd
## 判据:
##   ① 每件有分档数的装备都有标签, 且条数 == 正文里的分档数(对不上会静默退回整句, 这条挡住)
##   ② 标签表里没有多余的件(删了装备 / 去掉了分档却留着标签)
##   ③ 真渲染: 镇海杵分星表第一条效果行是「猛砸伤害」, 带三档数值; 不再出现「对 500 码内的敌人造成」整句
##   ④ 正负号贴在每档数上(「最大生命值 +300 / +700 / +3000」)
##   分母: 有分档数的装备 ≥ 80 件, 标签 ≥ 250 条

const CD := preload("res://scripts/scenes/codex/detail_views.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _plain(eq: Dictionary) -> String:
	return SkillText.equip_full(eq) + "\n" + SkillText.render_consts(str(eq.get("effectDesc3", "")))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 装备分星短标签 ===")
	var items := 0
	var labels := 0
	var bad: Array = []
	var ids := {}
	for eq in DataRegistry.phase2_equipment:
		var eid := str(eq.get("id", ""))
		ids[eid] = true
		var vals: Array = CD.tier_values_in_order(_plain(eq))
		if vals.is_empty():
			continue
		items += 1
		var lab: Array = EquipTierLabels.LABELS.get(eid, [])
		labels += lab.size()
		if lab.size() != vals.size():
			bad.append("%s %s: 分档 %d / 标签 %d" % [eid, str(eq.get("name", "")), vals.size(), lab.size()])
	_ok("分母: 有分档数的装备 ≥ 80 件、标签 ≥ 250 条", items >= 80 and labels >= 250, "%d 件 / %d 条" % [items, labels])
	_ok("① ★每件的标签条数 == 正文分档数", bad.is_empty(), str(bad.slice(0, 6)))
	var extra: Array = []
	for k in EquipTierLabels.LABELS:
		if not ids.has(k):
			extra.append(k)
	_ok("② 标签表里没有多余的件", extra.is_empty(), str(extra))

	var e90: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_090", {})
	var lines: PackedStringArray = CD.tier_breakdown_lines(_plain(e90), [], 1, "p2eq_090")
	var strip := RegEx.create_from_string("\\[[^\\]]*\\]")
	var first := strip.sub(lines[0], "", true) if lines.size() > 0 else ""
	_ok("③ ★镇海杵第一条效果行是「猛砸伤害 150 / 300 / 4000」", first.begins_with("猛砸伤害") and first.contains("150 / 300 / 4000"), first)
	var whole := strip.sub("\n".join(lines), "", true)
	_ok("③ 不再出现整句「对 500 码内的敌人造成」", not whole.contains("码内的敌人造成"), whole.substr(0, 60))
	var e84: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_084", {})
	var l84 := strip.sub("\n".join(CD.tier_breakdown_lines(_plain(e84), [], 1, "p2eq_084")), "", true)
	_ok("④ 正负号贴在每档数上", l84.contains("最大生命值  +300 / +700 / +3000"), l84.substr(l84.find("最大生命值"), 40))

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 装备分星短标签 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
