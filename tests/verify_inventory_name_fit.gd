extends Node
## verify_inventory_name_fit.gd — 背包格里【每一件】的字都够大且不贴边带; 名字在选中后的底栏里放得下
##
## 由来: 「迷你水晶球A」在背包格里末尾的 A 顶到槽框边带上(2026-10-20)。
## ★★2026-10-21 手机版改了契约: 格子里不再写装备名(12 号字在 iPhone 上 1 毫米出头, 而 96 格放不下
##   20 号的 5 字名)。格子里只剩【图标 + 星级】, 名字在选中后的底部操作条第一行(20 号字)。
##   ⇒ 本门禁改量: ① 格子里没有装备名 ② 格子里每一行字 ≥ 20 号、字墨离边带 ≥ 2px
##                 ③ 最长名那件选中后, 底栏第一行写着它的名字、20 号、不被截。
##
## ★分母: 全部装备逐件放进背包, 数到的格数必须 == 装备总数, 且最长的那件在场。
##
## 跑法: bash godot-quiet.sh res://tests/verify_inventory_name_fit.tscn --quit-after 1200

const InvScript := preload("res://scripts/scenes/InventoryScene.gd")
## 槽框贴图 slot-frame.png 实测金属边带厚 6px(第 7 列起是格内), 格内字墨离边带至少留这么多
const MIN_GAP := 2.0
const MIN_FONT := 20

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

	## 格子 = 背包滚动区里那一层、宽 = SLOT 的控件
	var cells: Array = []
	var st: Array = [sc]
	while not st.is_empty():
		var n = st.pop_back(); st.append_array(n.get_children())
		if n is Control and absf((n as Control).size.x - InvScript.SLOT) < 0.5 and absf((n as Control).size.y - InvScript.SLOT) < 0.5:
			var p = n.get_parent()
			if p != null and p.get_parent() is ScrollContainer:
				cells.append(n)
	_ok("★分母: 背包里量到 %d 格(应 ≥ %d 件)" % [cells.size(), names.size()], cells.size() >= names.size())
	var name_in_cell: Array = []
	var small: Array = []
	var tight: Array = []
	var n_lbl := 0
	for c in cells:
		var br: Rect2 = (c as Control).get_global_rect()
		for ch in (c as Node).get_children():
			if not (ch is Label):
				continue
			var lb := ch as Label
			if lb.text.strip_edges() == "" or lb.text == "·":
				continue
			n_lbl += 1
			if names.has(lb.text):
				name_in_cell.append(lb.text)
			var fs: int = lb.get_theme_font_size("font_size")
			if fs < MIN_FONT:
				small.append("「%s」%d" % [lb.text, fs])
			var f: Font = lb.get_theme_font("font")
			var tw: float = f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var lr: Rect2 = lb.get_global_rect()
			var x0: float = lr.position.x + (lr.size.x - tw) * 0.5
			var gap: float = minf(x0 - (br.position.x + InvScript.SLOT_PAD), (br.end.x - InvScript.SLOT_PAD) - (x0 + tw))
			if gap < MIN_GAP:
				tight.append("「%s」离边带 %.1f" % [lb.text, gap])
	_ok("★分母: 格子里量到 %d 行字(星级)" % n_lbl, n_lbl >= names.size())
	_ok("★★格子里不再写装备名", name_in_cell.is_empty(), str(name_in_cell.slice(0, 4)))
	_ok("★★格子里每一行字 ≥ %d 号" % MIN_FONT, small.is_empty(), str(small.slice(0, 4)))
	_ok("★★格子里的字墨离边带 ≥ %.0fpx" % MIN_GAP, tight.is_empty(), str(tight.slice(0, 4)))
	## ③ 最长名那件选中 → 底栏第一行是它的名字
	var li := -1
	for k in range(GameState.persistent_bench.size()):
		if str(DataRegistry.phase2_equipment_by_id.get(str(GameState.persistent_bench[k].get("id", "")), {}).get("name", "")) == longest:
			li = k
	_ok("★分母: 最长的「%s」在场" % longest, li >= 0)
	if li >= 0:
		sc._on_bench_click(li)
		for _i in range(6):
			await get_tree().process_frame
		var head: RichTextLabel = null
		var st2: Array = [sc]
		while not st2.is_empty():
			var n2 = st2.pop_back(); st2.append_array(n2.get_children())
			if n2 is RichTextLabel and (n2 as Control).is_visible_in_tree() and str((n2 as RichTextLabel).get_parsed_text()).begins_with(longest):
				head = n2
		_ok("★★选中后底栏第一行写着它的名字", head != null)
		if head != null:
			var hf: Font = head.get_theme_font("normal_font")
			var hfs: int = head.get_theme_font_size("normal_font_size")
			var hw: float = hf.get_string_size(str(head.get_parsed_text()), HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
			_ok("★★底栏名字 ≥ %d 号且整行放得下(字宽 %.0f ≤ 框宽 %.0f)" % [MIN_FONT, hw, head.size.x],
				hfs >= MIN_FONT and hw <= head.size.x + 0.5)

	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 背包格装备名放得下" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
