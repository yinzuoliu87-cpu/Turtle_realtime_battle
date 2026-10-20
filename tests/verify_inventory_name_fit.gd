extends Node
## verify_inventory_name_fit.gd — 背包格里【每一件】装备名都放得下, 且不贴边带(2026-10-20)
##
## 由来: 「迷你水晶球A」在背包格里末尾的 A 顶到槽框边带上。
##   原来名字框宽 = 格宽 − 2×SLOT_PAD(=82px), 12 号字 6 个半宽 ≈ 79px ⇒ 字墨右缘离边带只剩 1~2px。
##   改法见 `InventoryScene._fit_cell_name`: 两侧再留 NAME_BREATH, 放不下逐级缩字号, 再不行才换行。
##
## 判据量的是【字墨】不是 Label 框: Label 框一直在边带里(旧判据 13 就量框, 所以一直绿),
##   贴边的是字。字墨宽 = Label 实际字体 × 实际字号的 get_string_size, 居中排布。
##
## ★分母: 全部装备逐件放进背包, 数到的格内名字数必须 == 装备总数, 且最长的那件在场。
##
## 跑法: bash godot-quiet.sh res://tests/verify_inventory_name_fit.tscn --quit-after 1200

const InvScript := preload("res://scripts/scenes/InventoryScene.gd")
## 槽框贴图 slot-frame.png 实测金属边带厚 6px(第 7 列起是格内), 名字字墨离边带至少留这么多
const MIN_GAP := 2.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _find_named(n: Node, nm: String, out: Array) -> void:
	if n is Label and str(n.name) == nm:
		out.append(n)
	for c in n.get_children():
		_find_named(c, nm, out)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 背包格装备名放得下 ===")
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	for _q in range(4):
		await get_tree().process_frame

	var names: Dictionary = {}
	var longest := ""
	GameState.persistent_bench = []
	for e in DataRegistry.phase2_equipment:
		if not (e is Dictionary):
			continue
		var nm := str((e as Dictionary).get("name", ""))
		GameState.persistent_bench.append({"id": str((e as Dictionary).get("id", "")), "star": 3})
		names[nm] = true
		if nm.length() > longest.length():
			longest = nm
	var total: int = GameState.persistent_bench.size()
	_ok("★分母: 装备表 %d 件, 最长名「%s」%d 字" % [total, longest, longest.length()],
		total >= 90 and longest.length() >= 6)

	var sc = load("res://scenes/Inventory.tscn").instantiate()
	get_tree().root.add_child(sc)
	for _i in range(20):
		await get_tree().process_frame
	## 进场会把羁绊赠送件之类剔掉/补进来 —— 以场上真实背包为准, 再按它重建一次
	GameState.persistent_bench = GameState.persistent_bench.filter(func(it): return names.has(
		str(DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {}).get("name", ""))))
	sc._rebuild()
	for _i in range(10):
		await get_tree().process_frame

	var labs: Array = []
	_find_named(sc, "CellName", labs)
	var seen: Dictionary = {}
	var worst_gap := 999.0
	var worst := ""
	var bad: Array = []
	var fs_hist: Dictionary = {}
	var stretched: Array = []
	var lb_avail: float = InvScript.SLOT - (InvScript.SLOT_PAD + InvScript.NAME_BREATH) * 2.0
	for l in labs:
		var lb := l as Label
		var txt := lb.text
		if not names.has(txt):
			continue
		seen[txt] = true
		var box := lb.get_parent() as Control
		var br: Rect2 = box.get_global_rect()
		var lr: Rect2 = lb.get_global_rect()
		var f: Font = lb.get_theme_font("font")
		var fs: int = lb.get_theme_font_size("font_size")
		fs_hist[fs] = int(fs_hist.get(fs, 0)) + 1
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		## 单行: 字墨居中; 换行: 字墨宽不超过框宽
		var ink_w: float = tw if lb.get_line_count() <= 1 else minf(tw, lr.size.x)
		var x0: float = lr.position.x + (lr.size.x - ink_w) * 0.5
		var x1: float = x0 + ink_w
		var inner0: float = br.position.x + InvScript.SLOT_PAD
		var inner1: float = br.end.x - InvScript.SLOT_PAD
		var gap: float = minf(x0 - inner0, inner1 - x1)
		if gap < worst_gap:
			worst_gap = gap
			worst = "%s(字号 %d, 字宽 %.1f, 框宽 %.1f)" % [txt, fs, tw, lr.size.x]
		var one_line: bool = lb.get_line_count() <= 1
		if OS.get_environment("NF_DUMP") != "":
			print("      ", txt, " lr=", lr, " br=", br, " tw=", tw, " min=", lb.get_minimum_size(), " fs=", fs)
		## ★根因那一维: 名字框被 Label 的最小尺寸撑宽(建格时还没进树、量的是兜底字体),
		##   框一宽, 居中的字就整体往右挪, 换台设备(兜底字体不同)就顶到边带上。
		if lr.size.x > lb_avail + 0.5:
			stretched.append("%s 框宽 %.1f > %.1f" % [txt, lr.size.x, lb_avail])
		if gap < MIN_GAP or (one_line and tw > lr.size.x + 0.5) or fs < InvScript.NAME_FS_MIN or lr.end.y > br.end.y - InvScript.SLOT_PAD + 0.5:
			bad.append("%s gap=%.1f fs=%d tw=%.1f box=%.1f 单行=%s" % [txt, gap, fs, tw, lr.size.x, str(one_line)])
	print("    [探针] 字号分布 %s · 最紧的一件 %s 离边带 %.1fpx" % [str(fs_hist), worst, worst_gap])
	_ok("★分母: 背包里量到 %d 种装备名(应 = %d)" % [seen.size(), names.size()], seen.size() == names.size(),
		"缺: %s" % str(names.keys().filter(func(k): return not seen.has(k))))
	_ok("★分母: 最长的「%s」在场" % longest, seen.has(longest))
	_ok("★★名字框没被撑宽(都 ≤ %.0fpx)" % lb_avail, stretched.is_empty(), str(stretched))
	_ok("★★全部装备名字墨离槽框边带 ≥ %.0fpx、单行不溢出、字号 ≥ %d、不压底边" % [MIN_GAP, InvScript.NAME_FS_MIN],
		bad.is_empty(), str(bad))

	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 背包格装备名放得下" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
