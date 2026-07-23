extends Node
## verify_inventory_stats.gd — 守卫「背包显示每件装备提供的属性, 且写完整」
## (用户 2026-07-19:「在背包里我要看到每件装备提供的属性，必须写完整」)
##
## ★核心断言: P2RT.stat_lines 覆盖的字段 == RealtimeBattle3DScene._eq_apply_one_stats 实装的字段。
##   这两处若脱节, 背包就会【漏显示某类加成】—— 而且不会报错, 只会让玩家看到不完整的信息。
##   本项目已发生过同类事故: reflectPct/healAmp/shieldAmp/shieldHealPct 四类"数值表里写了、
##   单位字段也确实被消费, 但从没往里写" → 属性栏骗人。

const P2RT := preload("res://scripts/engine/equip_stats.gd")   # 2026-07-23: stat_lines 已抽到 equip_stats
const QUOTE := "\""
var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame

	# ── A. 实装读了哪些字段 vs 格式化函数认得哪些 ──
	var f := FileAccess.open("res://scripts/scenes/RealtimeBattle3DScene.gd", FileAccess.READ)
	var impl := {}
	var inside := false
	while f != null and not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("func _eq_apply_one_stats"): inside = true; continue
		if inside and line.begins_with("func "): break
		if not inside: continue
		var m := RegEx.new()
		m.compile("st[.]has[(]" + QUOTE + "([A-Za-z_]+)" + QUOTE + "[)]")
		var r := m.search(line)
		if r: impl[r.get_string(1)] = true
	if f != null: f.close()
	_ok("解析到实装读取的字段", impl.size() >= 10, "共 %d 个: %s" % [impl.size(), impl.keys()])

	var f2 := FileAccess.open("res://scripts/engine/equip_stats.gd", FileAccess.READ)
	var fmt := {}
	var ins2 := false
	while f2 != null and not f2.eof_reached():
		var line := f2.get_line()
		if line.begins_with("static func stat_lines"): ins2 = true; continue
		if ins2 and line.begins_with("static func "): break
		if not ins2: continue
		var m2 := RegEx.new()
		m2.compile("st[.]has[(]" + QUOTE + "([A-Za-z_]+)" + QUOTE + "[)]")
		var r2 := m2.search(line)
		if r2: fmt[r2.get_string(1)] = true
	if f2 != null: f2.close()

	var missing: Array = []
	for k in impl.keys():
		if not fmt.has(k): missing.append(k)
	_ok("★背包格式化覆盖了实装的全部字段(不漏显示)", missing.is_empty(),
		"漏: %s" % [missing])
	# ★不是所有属性都走 _eq_apply_one_stats 的平铺路径。
	#   有的经 _buff() 之类的专用分支实装 —— 这类字段允许只出现在格式化器里,
	#   但必须在此登记, 且下面会验证它【真的被战斗代码读到】, 免得这里变成藏孤儿字段的后门。
	var alt_path := {
		"dodgePct": "p2eq_046 幽灵墨鱼: 经 _buff(u, \"dodge\", ...) 给永久闪避, 不走平铺属性",
	}
	var extra: Array = []
	for k in fmt.keys():
		if not impl.has(k) and not alt_path.has(k): extra.append(k)
	_ok("格式化没有实装里不存在的字段(非平铺路径的须在 alt_path 登记)",
		extra.is_empty(), "多: %s" % [extra])

	# 登记在 alt_path 的字段, 必须能在战斗场源码里找到取用点 —— 否则就是幽灵字段
	var bat_src := ""
	var fb := FileAccess.open("res://scripts/scenes/RealtimeBattle3DScene.gd", FileAccess.READ)
	if fb != null:
		bat_src = fb.get_as_text()
		fb.close()
	var ghost: Array = []
	for k in alt_path.keys():
		if not bat_src.contains(str(k)): ghost.append(k)
	_ok("★alt_path 登记的字段在战斗代码里真被取用(防幽灵字段)",
		ghost.is_empty() and not alt_path.is_empty(),
		"登记 %d 个, 取不到的: %s" % [alt_path.size(), ghost])

	# ── B. 59 件 × 3 星 全部能出结果, 无空白无异常 ──
	var eqs: Array = DataRegistry.phase2_equipment
	_ok("装备 59 件", eqs.size() == 59, "%d" % eqs.size())
	var empty: Array = []
	var bad: Array = []
	for e in eqs:
		for star in [1, 2, 3]:
			var rows: Array = P2RT.stat_lines(str(e.get("id", "")), star)
			if rows.is_empty(): empty.append("%s★%d" % [e.get("id"), star]); continue
			for kv in rows:
				if str(kv[0]).strip_edges() == "" or str(kv[1]).strip_edges() == "":
					bad.append("%s★%d %s" % [e.get("id"), star, kv])
	_ok("★59件×3星 无空标签/空数值", bad.is_empty(), "%s" % [bad.slice(0, 4)])
	_ok("无属性的装备数量合理(应为0或极少)", empty.size() <= 3, "无属性: %s" % [empty.slice(0, 6)])

	# ── C. 按星级取值(不是恒取1星) ──
	var s1: String = P2RT.stat_line_compact("p2eq_001", 1)
	var s3: String = P2RT.stat_line_compact("p2eq_001", 3)
	_ok("★不同星级给出不同属性(按 star 取表)", s1 != s3, "1★=%s | 3★=%s" % [s1, s3])
	_ok("1★ 含攻击力+5(锈蚀短剑)", s1.contains("+5"), s1)
	_ok("3★ 含攻击力+20", s3.contains("+20"), s3)

	print("ALL PASS — 背包装备属性完整显示" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
