extends Node
## verify_big_title.gd — 结算屏大字美术字门禁(2026-10-27 用户选「方案 A」)
##
## 图: tools/build_big_titles.py 生成, 存 1 倍源图; 贴: scripts/util/big_title.gd(BigTitle.apply)。
##   ① 表对账: BigTitle 的三张表 == 生成脚本 WORDS(文字 → 文件名一一对应), 每张图都在、能加载
##   ② 图是 1 倍源图: 硬边(alpha 只有 0 / 255)、高 ≤ 40 源像素(防止把放大后的图存进来再放大一次)
##   ③ 覆盖: battle_hud._result_headline 能返回的每一句、左栏能写的每一句、各路能写的每一个字, 表里都有图
##      —— 从源码里抽字面量, 以后加一句新的大字没出图就红
##   ④ 真建结算屏(1560×720): 胜 / 负 / 封存三种, 大字、左栏、各路都挂着图; 最近邻; 整数倍; 标签自己的字透明;
##      图在视口里、不压下一句
##   ⑤ 没有图的文字: apply 返回 false, 不挂图, 标签照旧显示自己的字
##   ⑥ 尺子自检: 硬边判据对一张带半透明像素的图要判「不是硬边」
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_big_title.tscn --quit-after 6000

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
const GEN := "res://tools/build_big_titles.py"
const HUD_SRC := "res://scripts/scenes/battle/battle_hud.gd"
const SETTLE_SRC := "res://scripts/scenes/battle/settle_screen.gd"
const MAX_SRC_H := 40

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true                                  # 不许写真存档
	var bak := {"lane_results": gs.lane_results.duplicate(), "dual_active": gs.dual_active,
		"finals_pending_reveal": (gs.finals_pending_reveal as Dictionary).duplicate()}
	_check_tables()
	_check_coverage()
	_check_fallback()
	_check_ruler()
	await _check_screen()
	gs.lane_results = bak["lane_results"]
	gs.dual_active = bak["dual_active"]
	gs.finals_pending_reveal = bak["finals_pending_reveal"]
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 结算屏大字美术字" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _all_tables() -> Dictionary:
	## 文件名 → 文字(三张表合起来; 文件名不重)
	var out := {}
	for t in [BigTitle.BIG, BigTitle.RAIL, BigTitle.LANE]:
		for k in t:
			out[str(t[k])] = str(k)
	return out


static func _hard_edged(img: Image) -> bool:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var a := img.get_pixel(x, y).a8
			if a != 0 and a != 255:
				return false
	return true


func _check_tables() -> void:
	var src := FileAccess.get_file_as_string(GEN)
	_ok("① ★分母: 读到生成脚本", src.length() > 200, GEN)
	## WORDS 里的每一行: ("big_win", "胜利", BIG, GOLD),
	var re := RegEx.new()
	re.compile("\\(\"([a-z_]+)\", \"([^\"]+)\", (BIG|SMALL),")
	var gen := {}
	for m in re.search_all(src):
		gen[m.get_string(1)] = m.get_string(2)
	var mine := _all_tables()
	_ok("① ★分母: 生成脚本 %d 张 / BigTitle 表 %d 条" % [gen.size(), mine.size()], gen.size() >= 10 and mine.size() >= 10)
	var diff: Array = []
	for k in gen:
		if not mine.has(k) or str(mine[k]) != str(gen[k]):
			diff.append("%s=%s" % [k, gen[k]])
	for k in mine:
		if not gen.has(k):
			diff.append("表里多出 %s" % k)
	_ok("① 两张表一一对应(文件名 → 文字)", diff.is_empty(), str(diff))
	var bad: Array = []
	var nimg := 0
	for k in mine:
		var tex := load(BigTitle.DIR + str(k) + ".png") as Texture2D
		if tex == null:
			bad.append("%s 加载不了" % k)
			continue
		nimg += 1
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		if img.get_height() > MAX_SRC_H:
			bad.append("%s 高 %d > %d(存的不是 1 倍源图)" % [k, img.get_height(), MAX_SRC_H])
		if not _hard_edged(img):
			bad.append("%s 有半透明像素" % k)
	_ok("② %d 张图都在、1 倍源图、硬边" % nimg, nimg == mine.size() and bad.is_empty(), str(bad))


## 抽出某个函数体里 return 行上的全部字符串字面量(一行里有几个抽几个: `return "胜利" if won else "失败"`)
static func _literals_in_func(src: String, fn: String) -> Array:
	var i := src.find("func " + fn + "(")
	if i < 0:
		return []
	var j := src.find("\nfunc ", i + 5)
	var body := src.substr(i, (j if j > 0 else src.length()) - i)
	var re := RegEx.new()
	re.compile("\"([^\"]+)\"")
	var out: Array = []
	for line in body.split("\n"):
		if not line.strip_edges().begins_with("return "):
			continue
		for m in re.search_all(line):
			var s := m.get_string(1)
			if not out.has(s):
				out.append(s)
	return out


func _check_coverage() -> void:
	var hud := FileAccess.get_file_as_string(HUD_SRC)
	var heads := _literals_in_func(hud, "_result_headline")
	_ok("③ ★分母: _result_headline 抽到 %d 句" % heads.size(), heads.size() >= 4, str(heads))
	var miss: Array = []
	for s in heads:
		if not BigTitle.BIG.has(s):
			miss.append(s)
	_ok("③ 胜负大字的每一句都有图", miss.is_empty(), "缺 %s" % str(miss))
	var st := FileAccess.get_file_as_string(SETTLE_SRC)
	## 左栏: var word := _lbl("已封存" if sealed else ("胜利" if won else "失败"), ...
	var re := RegEx.new()
	re.compile("var word := _lbl\\(\"([^\"]+)\" if sealed else \\(\"([^\"]+)\" if won else \"([^\"]+)\"\\)")
	var m := re.search(st)
	var rail: Array = [m.get_string(1), m.get_string(2), m.get_string(3)] if m != null else []
	_ok("③ ★分母: 左栏抽到 %d 句" % rail.size(), rail.size() == 3, str(rail))
	miss = []
	for s in rail:
		if not BigTitle.RAIL.has(s):
			miss.append(s)
	_ok("③ 左栏胜负的每一句都有图", miss.is_empty(), "缺 %s" % str(miss))
	## 各路: var res := "胜" if who == "left" else ("负" if who == "right" else "平")
	re.compile("var res := \"([^\"]+)\" if who == \"left\" else \\(\"([^\"]+)\" if who == \"right\" else \"([^\"]+)\"\\)")
	m = re.search(st)
	var lane: Array = [m.get_string(1), m.get_string(2), m.get_string(3)] if m != null else []
	_ok("③ ★分母: 各路抽到 %d 个字" % lane.size(), lane.size() == 3, str(lane))
	miss = []
	for s in lane:
		if not BigTitle.LANE.has(s):
			miss.append(s)
	_ok("③ 各路胜负的每个字都有图", miss.is_empty(), "缺 %s" % str(miss))


func _check_fallback() -> void:
	var l := Label.new()
	l.text = "没有这张图"
	var got := BigTitle.apply(l, BigTitle.BIG)
	_ok("⑤ 没有图的文字: 不挂图、标签照旧可见", not got and l.get_child_count() == 0 and is_equal_approx(l.self_modulate.a, 1.0))
	l.free()


func _check_ruler() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var clean := _hard_edged(img)
	img.set_pixel(2, 2, Color(1, 1, 1, 0.5))
	_ok("⑥ 尺子自检: 全不透明判硬边、带一个半透明像素判不是", clean and not _hard_edged(img))


## 标签挂的图: 存在、可见、最近邻、尺寸 = 源图 × SCALE、标签自己的字透明。返回出错原因(空 = 对)
func _art_problem(l: Label, want_file: String) -> String:
	if l == null:
		return "标签不在"
	var art := l.get_node_or_null(BigTitle.ART_NODE) as TextureRect
	if art == null or art.texture == null:
		return "「%s」没挂图" % l.text
	if not art.texture.resource_path.ends_with("/" + want_file + ".png"):
		return "「%s」挂的是 %s" % [l.text, art.texture.resource_path]
	if not art.is_visible_in_tree():
		return "「%s」的图不可见" % l.text
	if art.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		return "「%s」不是最近邻" % l.text
	if not art.size.is_equal_approx(art.texture.get_size() * BigTitle.SCALE):
		return "「%s」图 %s ≠ 源图 %s × %d" % [l.text, str(art.size), str(art.texture.get_size()), BigTitle.SCALE]
	if l.self_modulate.a > 0.001:
		return "「%s」标签自己的字没透明(会和图叠两层)" % l.text
	return ""


func _open(sc, sealed: bool, won: bool) -> Node:
	var gs = get_node_or_null("/root/GameState")
	if sc._hud._settle != null and is_instance_valid(sc._hud._settle):
		sc._hud._settle.queue_free()
	await get_tree().process_frame
	sc._st_lane_hist = []
	sc._units.clear()
	gs.dual_active = true
	gs.lane_results = {"top": "right", "bottom": "left"}
	gs.finals_pending_reveal = {"round": 1, "match": 0} if sealed else {}
	sc._settled = false
	sc._hud._show_banner(won)
	for _i in range(12):
		await get_tree().process_frame
	return sc._hud._settle


func _check_screen() -> void:
	var v := Vector2i(1560, 720)
	get_tree().root.content_scale_size = v
	get_tree().root.size = v
	for _q in range(4):
		await get_tree().process_frame
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame
	sc.set_process(false)
	sc.set_physics_process(false)
	var vp: Rect2 = sc.get_viewport().get_visible_rect()
	for case in [["胜", false, true, "big_win", "rail_win"], ["负", false, false, "big_lose", "rail_lose"],
			["封存", true, true, "big_sealed", "rail_sealed"]]:
		var tag: String = case[0]
		var scr = await _open(sc, case[1], case[2])
		_ok("[%s] ★分母: 结算屏建出来了" % tag, scr != null)
		if scr == null:
			continue
		var p1: Control = scr.pages[0]
		var slot := p1.find_child("ResultSlot", true, false) as Control
		var big: Label = (slot.get_child(0) as Label) if slot != null and slot.get_child_count() > 0 else null
		_ok("[%s] ④ 胜负大字挂着图" % tag, _art_problem(big, case[3]) == "", _art_problem(big, case[3]))
		## 图不压下一句: 等滑入落位再量(滑入 = 横向, 纵向不动, 但还是等它停下)
		for _i in range(40):
			await get_tree().process_frame
		if big != null and big.get_node_or_null(BigTitle.ART_NODE) != null:
			var ar: Rect2 = (big.get_node(BigTitle.ART_NODE) as Control).get_global_rect()
			var nxt: Control = p1.get_child(slot.get_index() + 1) as Control if slot.get_index() + 1 < p1.get_child_count() else null
			_ok("[%s] ④ 大字图在视口里、不压下一句" % tag, vp.encloses(ar) and nxt != null and ar.end.y <= nxt.get_global_rect().position.y + 0.5,
				"图 %s / 下一句 %s" % [str(ar), str(nxt.get_global_rect()) if nxt != null else "null"])
		## 左栏: 第一个带 BigTitleArt 的标签之外, 找文字 = 左栏那句的标签
		var rail_l: Label = null
		for c in scr.find_children("*", "Label", true, false):
			var cl := c as Label
			if cl != big and BigTitle.RAIL.has(cl.text) and not p1.is_ancestor_of(cl):
				rail_l = cl
				break
		_ok("[%s] ④ 左栏胜负挂着图" % tag, _art_problem(rail_l, case[4]) == "", _art_problem(rail_l, case[4]))
		var lanes: Node = p1.find_child("LaneResults", true, false)
		if case[1]:
			_ok("[%s] ④ 封存时不画各路(与 verify_settle_pages ⑧ 同一条)" % tag, lanes == null or lanes.get_child_count() == 0)
			continue
		var probs: Array = []
		var nlane := 0
		for c in (lanes.find_children("*", "Label", true, false) if lanes != null else []):
			if BigTitle.LANE.has((c as Label).text):
				nlane += 1
				var want := str(BigTitle.LANE[(c as Label).text])
				var p := _art_problem(c as Label, want)
				if p != "":
					probs.append(p)
		_ok("[%s] ④ 各路 %d 块胜负都挂着图" % [tag, nlane], nlane == 2 and probs.is_empty(), str(probs))
	sc.queue_free()
