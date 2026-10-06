extends Node
## verify_leaderboard_header — 排行榜【每一行画出来的三个成绩】必须就是【真数据的那三个量】,
## 而且三列的顺序**一行都不许乱**。
##
## ═══ 它原来守的是什么, 为什么判据要换 ═══
## 2026-09-19 实拍巡检当场看见: A8 改排序那轮改了标题、改了每行文案、改了比较器,
## **漏了表头那一行** ⇒ 屏幕上表头写着「击杀蛋数」, 而数据是「0胜 · ♥5 · 0横扫」。
## 而 `verify_leaderboard_sort`(11 条)一条都没红 —— 它只测 `Backend.leaderboard()`
## 这个函数, 没有任何判据看得见 UI 上的字。⇒ 本门禁当时的形状是「表头词 ↔ 行里词」逐项对账。
##
## 2026-09-28 产品把**表头行整个拆掉**了(用户:「图鉴、排行榜什么我一点也看不出来
## 游戏的味道, 全是 ai 味和网页味」——「排名 | 玩家 | 胜·余命·横扫」正是后台表格的标志),
## 同一轮里成绩也从一条拼接串「0胜 · ♥8 · 0横扫」改成了**三格「图标 + 数字」**。
## 于是原来那两条分母(「找得到表头行」「找得到表头的成绩列」)开始报红 ——
## **产品对了, 判据还在量旧样子**(本仓记过的「门禁把 bug 钉在原地」那一类)。
##
## ⇒ 判据不是删掉了事, 而是把**同一件要守的事**挪到数据行上量:
##   「成绩三列对得上、顺序不乱」。表头没了, 那就让**每一行自己**证明这件事。
##
## ═══ 判据形状 ═══
## ★走**真场景实例 + 真节点**: 读活节点的 `text` / `texture` / `StyleBox`,
##   不在源码里找字符串(源码子串匹配是假判据 —— 把整段画行的代码删掉它照样绿)。
## ★**先灌真人行再量**: 全新档的榜本来就只有自己一行(产品行为, 见 `_setup_lb_rows.gd`),
##   拿那块占位屏量"每一行"等于只量了一行。种子脚本跑不起来 ⇒ 当场判红, 不许静默跳过。
## ★自己那三个量**钉成互不相同的数** —— 全是 0 的话, 列顺序调乱了判据一样全绿。
##   (「0胜 · ♥8 · 0横扫」正好是两个 0: 那种数据下 ①③ 都是空检查。)

const SEED_PATH := "res://tests/_setup_lb_rows.gd"

## ★三个数必须两两不同(下面 ① 有一条断言看着它) —— 这是本门禁能不能看见"列乱了"的前提。
const SELF_WINS := 12
const SELF_HEARTS := 5
const SELF_SWEEPS := 3

## ★2026-10-06 换形状(用户「积分赛写上名字，剩余生命，胜场，总场次啊 ，都给我做」):
##   成绩从「三格 图标+数字」改成**表头纯文字列名 + 行里纯数字**(照 使命召唤手游 / 英雄联盟手游),
##   列 = 剩余生命 | 胜场 | 总场次。原来这份判据把「带成绩图标的行」当数据行 ⇒ 图标一拿掉**分母当场 0 行**。
##   ⇒ 数据行改认「一条带 4 个整数的行(名次 + 三成绩)」; 图标那几条改成「表头三列名 + 格里零图标」。
## 列的语义(表头文字必须逐字是这三个词, 顺序不许乱):
const COL_WORDS := ["剩余生命", "胜场", "总场次"]
const SELF_BATTLES := 17

## ★过期量词: A8 之前榜是按击杀龟蛋数排的。屏幕上再出现它 = 又漂了一次。
const STALE_TERMS := ["蛋数", "击杀蛋"]

## ★分母下限: 灌了 14 条真人行 + 自己, 面板画得下 11 行。少于这个数 = 量到了占位屏。
const MIN_DATA_ROWS := 8

var _pass := 0
var _fail := 0
var _seed = null


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


## 屏上最大的那块 Panel = 榜本身(不按名字/不按尺寸常量认 —— 那等于"我说是就是")。
func _board(n: Node) -> Control:
	var best: Control = null
	var best_a := 0.0
	var st: Array = [n]
	while not st.is_empty():
		var c = st.pop_back()
		if c is Panel and (c as Control).is_visible_in_tree():
			var r: Rect2 = (c as Control).get_global_rect()
			var a: float = r.size.x * r.size.y
			if a > best_a:
				best_a = a
				best = c as Control
		for ch in c.get_children():
			st.append(ch)
	return best


## 把榜里的【带字标签】和【行内小图标】按 y 聚成一条条"行"。
## ★聚类而不是按行号算坐标: 行距/内边距全是产品自己的常量, 判据不该抄一份。
func _bands(board: Control) -> Array:
	var items: Array = []
	var st: Array = [board]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			var rc: Rect2 = c.get_global_rect()
			if c is Label and str((c as Label).text).strip_edges() != "":
				items.append({"k": "L", "n": c, "y": rc.get_center().y, "x": rc.position.x})
			elif c is TextureRect and (c as TextureRect).texture != null \
					and rc.size.x <= 24.0 and rc.size.y <= 24.0 and rc.size.x >= 8.0:
				items.append({"k": "T", "n": c, "y": rc.get_center().y, "x": rc.position.x})
		for ch in n.get_children():
			st.append(ch)
	items.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))
	var out: Array = []
	for it in items:
		if out.is_empty() or absf(float(it["y"]) - float((out[out.size() - 1] as Dictionary)["y"])) > 14.0:
			out.append({"y": float(it["y"]), "items": [it]})
		else:
			((out[out.size() - 1] as Dictionary)["items"] as Array).append(it)
	return out


## 这个 Label 是不是住在一块【自己的九宫格签牌】里(名次牌 / 「你」签)?
## ★`board` 要排掉: 榜面板本身也是一块套了九宫格的 Panel, 不排的话**每一个**标签
##   都被判成"住在签牌里" ⇒ ④ 那条会报"第 4 名也有牌位"(第一版实测 8 处, 全是它)。
func _plate_of(l: Label, board: Control) -> StyleBoxTexture:
	var p := l.get_parent()
	if p == board:
		return null
	if p is Panel and (p as Panel).has_theme_stylebox_override("panel"):
		var sb = (p as Panel).get_theme_stylebox("panel")
		if sb is StyleBoxTexture:
			return sb as StyleBoxTexture
	return null


## 榜里所有【整行宽的签牌底】(前三名的台阶 / 自己那行), 记下 y 与它的染色。
func _wide_bands(board: Control) -> Array:
	var out: Array = []
	var bw: float = board.get_global_rect().size.x
	var st: Array = [board]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Panel and (n as Control).is_visible_in_tree() and n != board:
			var c := n as Control
			var r: Rect2 = c.get_global_rect()
			if r.size.x > bw * 0.8 and (c as Panel).has_theme_stylebox_override("panel"):
				var sb = (c as Panel).get_theme_stylebox("panel")
				if sb is StyleBoxTexture:
					out.append({"y": r.get_center().y, "c": (sb as StyleBoxTexture).modulate_color})
		for ch in n.get_children():
			st.append(ch)
	return out


func _count_tex(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is TextureRect and (ch as TextureRect).texture != null and (ch as Control).is_visible_in_tree():
			c += 1
		c += _count_tex(ch)
	return c


func _find_named(n: Node, nm: String) -> Label:
	if n is Label and str(n.name) == nm:
		return n as Label
	for ch in n.get_children():
		var r := _find_named(ch, nm)
		if r != null:
			return r
	return null


func _find_band(wides: Array, y: float):
	for w in wides:
		if absf(float((w as Dictionary)["y"]) - y) <= 14.0:
			return (w as Dictionary)["c"]
	return null


func _far(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.15


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	_ok("① ★分母: GameState 在位", gs != null)
	if gs != null:
		gs.test_mode = true
		gs.season_wins = SELF_WINS
		gs.hearts = SELF_HEARTS
		gs.season_sweeps = SELF_SWEEPS
		gs.season_total_battles = SELF_BATTLES
	## ★这一条不是走过场: 三个数只要有两个相等, 下面 ③ 的"列顺序"就成了空检查。
	_ok("① ★分母: 自己那三个量两两不同(相等的话列顺序乱了也照样绿)",
		SELF_WINS != SELF_HEARTS and SELF_HEARTS != SELF_BATTLES and SELF_WINS != SELF_BATTLES,
		"%d / %d / %d" % [SELF_HEARTS, SELF_WINS, SELF_BATTLES])

	## ★★不灌真人行就只有自己一行(产品行为) ⇒ "每一行"这句话没有分母。
	##   种子脚本第一版有过 Parse Error 而 `has_method` 静默为 false —— 跑不起来当场红。
	_seed = load(SEED_PATH) if ResourceLoader.exists(SEED_PATH) else null
	_ok("① ★分母: 种子脚本 `_setup_lb_rows` 跑得起来(跑不起来 = 量的是只有我一行的占位屏)",
		_seed != null and _seed.has_method("run") and _seed.has_method("clear"))
	if _seed != null and _seed.has_method("run"):
		_seed.run()

	var ps: PackedScene = load("res://scenes/Leaderboard.tscn")
	_ok("① ★分母: Leaderboard.tscn 载得进来", ps != null)
	if ps == null:
		_done()
		return
	var inst: Node = ps.instantiate()
	add_child(inst)
	## ★等它自己把行画完(本屏在 `_ready` 里同步建节点, 一帧足够; 多等两帧保险)。
	await get_tree().process_frame
	await get_tree().process_frame

	var board := _board(inst)
	_ok("① ★分母: 找得到榜面板", board != null,
		"%.0fx%.0f" % [board.size.x, board.size.y] if board != null else "")
	if board == null:
		_finish(inst)
		return

	var bands := _bands(board)
	var all_text: Array = []
	var data: Array = []          # 数据行 = 带 4 个整数(名次 + 三成绩)的那些行
	var n_icons := 0
	for b in bands:
		var items: Array = (b as Dictionary)["items"]
		var ints: Array = []
		for it in items:
			var d: Dictionary = it
			if str(d["k"]) == "T":
				n_icons += 1
			else:
				var lb := d["n"] as Label
				all_text.append(str(lb.text))
				if str(lb.text).is_valid_int():
					ints.append(d)
		ints.sort_custom(func(p, q): return float(p["x"]) < float(q["x"]))
		if ints.size() >= 4:
			data.append({"y": float((b as Dictionary)["y"]), "ints": ints, "items": items})

	_ok("① ★分母: 屏上真的建出了 Label", all_text.size() >= 20, "共 %d 个" % all_text.size())
	## ★★真分母: "每一行都含三个成绩数"这句话, 得先有足够多的行。
	_ok("① ★★分母: 量到的数据行 ≥ %d" % MIN_DATA_ROWS, data.size() >= MIN_DATA_ROWS,
		"实得 %d 行" % data.size())
	if data.is_empty():
		_finish(inst)
		return

	## ── ② 表头 = 用户的三个词 / 格里零图标 / 每行 4 个数且列对齐 ─────────
	var heads: Array = []
	for i in range(COL_WORDS.size()):
		var h := _find_named(board, "LbColHead%d" % i)
		heads.append(str(h.text) if h != null else "(缺)")
	_ok("② ★★表头三列 = 「剩余生命」「胜场」「总场次」(用户原词, 顺序不许乱)", heads == COL_WORDS, str(heads))
	## ★任何尺寸的贴图都算(行内小图标那条过滤只认 8~24px, 一张 32px 的奖杯会从缝里漏过去)。
	n_icons += _count_tex(board)
	_ok("② 格里不画图标(用户「排行榜里的奖杯是？」)", n_icons == 0, "%d 个" % n_icons)
	var bad_shape: Array = []
	for r in data:
		if ((r as Dictionary)["ints"] as Array).size() != 4:
			bad_shape.append("y=%.0f 数字%d" % [float((r as Dictionary)["y"]), ((r as Dictionary)["ints"] as Array).size()])
	_ok("② 每一行都是【4 个数字(名次 + 三成绩)】", bad_shape.is_empty(),
		"%d 行不合形状 %s" % [bad_shape.size(), str(bad_shape.slice(0, 3))])
	## 列对齐: 每行第 N 个成绩数的**右沿**都 = 表头第 N 列名的右沿(≤1px)。
	var x_drift: Array = []
	var measured := 0
	for r2 in data:
		var ii: Array = (r2 as Dictionary)["ints"]
		for j in range(1, mini(4, ii.size())):
			var h2 := _find_named(board, "LbColHead%d" % (j - 1))
			if h2 == null:
				continue
			var cr: Rect2 = (((ii[j] as Dictionary)["n"]) as Label).get_global_rect()
			measured += 1
			if absf(cr.end.x - h2.get_global_rect().end.x) > 1.0:
				x_drift.append("y=%.0f 第%d列 %.1f≠%.1f" % [float((r2 as Dictionary)["y"]), j - 1, cr.end.x,
					h2.get_global_rect().end.x])
	_ok("② ★列对齐逐行一致: 每个成绩数右沿 = 表头那一列右沿(≤1px)", x_drift.is_empty() and measured >= MIN_DATA_ROWS * 3,
		"量了 %d 格 %s" % [measured, str(x_drift.slice(0, 3))])

	## ── ③ 三列 ↔ 真数据: 列顺序真的是「剩余生命 → 胜场 → 总场次」 ─────────────
	## 「你」那一行认法: 屏上那枚「你」签(产品用它标自己, 不是测试自己插的标记)。
	var self_y := -1.0
	for r3 in data:
		for it3 in ((r3 as Dictionary)["items"] as Array):
			var dd: Dictionary = it3
			if str(dd["k"]) == "L" and str((dd["n"] as Label).text).strip_edges() == "你":
				self_y = float((r3 as Dictionary)["y"])
	_ok("③ ★分母: 榜上找得到【你】那一行", self_y >= 0.0,
		"找不到 = 下面三条数值对账全是空检查")
	var self_row: Dictionary = {}
	for r4 in data:
		if absf(float((r4 as Dictionary)["y"]) - self_y) <= 1.0:
			self_row = r4
	if not self_row.is_empty() and (self_row["ints"] as Array).size() == 4:
		var got: Array = []
		for j in range(1, 4):
			got.append(int(str((((self_row["ints"] as Array)[j] as Dictionary)["n"] as Label).text)))
		var want := [SELF_HEARTS, SELF_WINS, SELF_BATTLES]
		for j2 in range(3):
			_ok("③ ★第 %d 列(%s)画的就是真数据的那个量" % [j2, COL_WORDS[j2]],
				int(got[j2]) == int(want[j2]),
				"屏上 %s ↔ 真值 %s" % [str(got), str(want)])
	else:
		_ok("③ ★你那一行取得到四个数", false, "实得 %s" % str(self_row.keys()))

	## 整块榜按【胜场 → 剩余生命】递减(横扫不上屏, 只在两者都相同时定先后 ⇒ 屏上允许相等)。
	var order_bad: Array = []
	var prev: Array = []
	var ranks: Array = []
	for r5 in data:
		var ii2: Array = (r5 as Dictionary)["ints"]
		if ii2.size() != 4:
			continue
		ranks.append(int(str(((ii2[0] as Dictionary)["n"] as Label).text)))
		var cur: Array = [int(str(((ii2[2] as Dictionary)["n"] as Label).text)),
			int(str(((ii2[1] as Dictionary)["n"] as Label).text))]
		if not prev.is_empty():
			if cur[0] > prev[0] or (cur[0] == prev[0] and cur[1] > prev[1]):
				order_bad.append("%s 高于上一行 %s" % [str(cur), str(prev)])
		prev = cur
	_ok("③ 整块榜按【胜场 → 剩余生命】字典序不增", order_bad.is_empty() and ranks.size() >= MIN_DATA_ROWS,
		"%d 处 %s" % [order_bad.size(), str(order_bad.slice(0, 2))])
	var rank_bad := false
	for k in range(1, ranks.size()):
		if int(ranks[k]) <= int(ranks[k - 1]):
			rank_bad = true
	_ok("③ 名次从上往下严格递增", not rank_bad and ranks.size() >= MIN_DATA_ROWS, str(ranks))

	## ── ④ 前三名看得出来: 金/银/铜三块牌位, 第 4 名起没有 ──────────
	var plates: Array = []
	var plate_bad: Array = []
	for r6 in data:
		var ii2: Array = (r6 as Dictionary)["ints"]
		if ii2.is_empty():
			continue
		var rl := (ii2[0] as Dictionary)["n"] as Label
		var rk := int(str(rl.text))
		var pl := _plate_of(rl, board)
		if rk <= 3:
			if pl == null:
				plate_bad.append("第%d名没有牌位" % rk)
			else:
				plates.append(pl.modulate_color)
		elif pl != null:
			plate_bad.append("第%d名也套了牌位(那前三就不特殊了)" % rk)
	_ok("④ ★前三名各有一块牌位, 第 4 名起没有", plate_bad.is_empty(),
		"%d 处 %s" % [plate_bad.size(), str(plate_bad.slice(0, 3))])
	_ok("④ ★分母: 真的取到了三块牌位", plates.size() == 3, "实得 %d 块" % plates.size())
	if plates.size() == 3:
		_ok("④ 金/银/铜三块牌位的颜色两两不同(不是同一块牌重复三次)",
			_far(plates[0], plates[1]) and _far(plates[1], plates[2]) and _far(plates[0], plates[2]),
			str(plates))

	## ── ⑤ 「你」那一行显眼: 整行底签 + 一枚「你」签 ──────────────
	var wides := _wide_bands(board)
	_ok("⑤ ★分母: 量到整行宽的底签", wides.size() >= 2, "实得 %d 条" % wides.size())
	var self_band = _find_band(wides, self_y) if self_y >= 0.0 else null
	_ok("⑤ ★你那一行有一条整行底签(不是只把字换个颜色)", self_band != null,
		str(self_band))
	if self_band != null:
		var medal_y: Array = []
		for r7 in data:
			var ii3: Array = (r7 as Dictionary)["ints"]
			if ii3.is_empty():
				continue
			if int(str(((ii3[0] as Dictionary)["n"] as Label).text)) <= 3:
				medal_y.append(float((r7 as Dictionary)["y"]))
		var clash: Array = []
		for my in medal_y:
			var mc = _find_band(wides, float(my))
			if mc != null and not _far(self_band as Color, mc as Color):
				clash.append("y=%.0f" % float(my))
		_ok("⑤ 你那一行的底签颜色和前三名的台阶都不一样", clash.is_empty(), str(clash))

	## ── ⑥ 旧样子不许回来 ──────────────────────────────────────
	for st2 in STALE_TERMS:
		var hit: Array = []
		for t in all_text:
			if str(t).contains(str(st2)):
				hit.append(str(t))
		_ok("⑥ ★屏上不含过期量词「%s」(A8 漏改的就是它)" % str(st2), hit.is_empty(), str(hit.slice(0, 3)))
	## 成绩不许再拼回一条串。原来那条是「%d胜 · ♥%d · %d横扫」—— 判据卡它的真形状:
	## 同一段文字里同时出现两个量 = 又拼回去了。
	var spliced: Array = []
	for t2 in all_text:
		var s := str(t2)
		if s.contains("横扫") and (s.contains("胜") or s.contains("♥")):
			spliced.append(s)
	_ok("⑥ ★成绩没有被拼回一条串(每个量该有自己的图标和数字)", spliced.is_empty(),
		str(spliced.slice(0, 3)))
	_finish(inst)


func _finish(inst: Node) -> void:
	if inst != null:
		inst.queue_free()
	## ★`pool_override` 是 static, 活过场景切换 —— 用完必须清。
	if _seed != null and _seed.has_method("clear"):
		_seed.clear()
	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 排行榜成绩三列对账 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 排行榜成绩三列对账 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
