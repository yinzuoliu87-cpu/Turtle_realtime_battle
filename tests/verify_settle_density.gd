extends Node
## verify_settle_density.gd — 结算战报表【零值不印数字】门禁 (2026-10-02)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户两次点名这一屏(「这些 ui 很 ai 味」/「每场打完后结算界面能
##    下滑吗, 不能啊, 有很多单位看不到啊」)。
## ══════════════════════════════════════════════════════════════════
## 实测(v0.19.504 · 1560x720 · 每侧注入 14 只): 这一屏 **89 个数字 token**,
## 其中 88 个来自战报表的「看得见的 22 行 x 4 个数值格」。
## 参考侧 11 张同品类结算屏里, **逐单位印数字**的那几张是每只 1~2 个
## (Brawl Stars 2 / Heroes of Rings 1), 我们是每只 4 个。
##
## ⇒ 改法: **一列不删**(哪几列显示是用户 2026-08-02 拍过板的), 只把 `0` 换成
##   占位符 —— 不治疗的龟治疗栏本来就该是空的, 不是"治疗了 0"。
##
## ══ 这条门禁量的是什么 ══
## 走**真控件树**(`get_global_rect()` 那一侧的真对象), 不读常量、不模拟公式:
##   ① 分母: 表里确实有 N 行 x 4 个数值格, 且 N>0
##   ② 分母: 这批数据里【零值格】和【非零格】**两种都有**(缺一种这条就是空检查)
##   ③ 没有任何一个数值格印着 "0"
##   ④ 零值格印的就是 `BattleHud.SETTLE_ZERO_MARK`(与产品同一个常量, 不自己拼)
##   ⑤ 非零格印的就是那个整数本身(一个有效数字都没丢)
##   ⑥ 屏上数字 token 总数 == 非零统计值的个数(这就是"密度"那条断言本身)
##
## ★反向验证: 把 `settle_cell_text` 改回 `str(v)` ⇒ ③④⑥ 立刻红(已验, 见方案书)。
##
## 跑法: bash godot-quiet.sh res://tests/verify_settle_density.tscn --quit-after 1500

const SCENE := "res://scenes/RealtimeBattle3D.tscn"

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
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	for _q in range(4):
		await get_tree().process_frame
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame

	## ── 造名单: 故意混进【四种都是 0】和【四种都非零】两类 ──────────
	##   ★不混进零值的话 ③④ 永远绿 = 空检查; 不混进非零的话 ⑤ 永远绿。
	var made := 0
	for side in ["left", "right"]:
		for k in range(8):
			var u = sc._spawn._make_unit("green", side, sc.ARENA.position + sc.ARENA.size * 0.5
				+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
			if not (u is Dictionary):
				continue
			if k % 2 == 0:
				## 偶数只: 四项全 0 (= 一只什么都没干的龟, 真对局里到处都是)
				u["_st_dealt"] = 0; u["_st_taken"] = 0; u["_st_heal"] = 0; u["_st_kills"] = 0
			else:
				u["_st_dealt"] = 1000 + 137 * k
				u["_st_taken"] = 500 + 91 * k
				u["_st_heal"] = 40 * k
				u["_st_kills"] = 1 + k % 3
			if not sc._arr_has_unit(sc._units, u):
				sc._units.append(u)
			made += 1
	_ok("★分母: 造出 %d 只(名单不够长这条就不是真场面)" % made, made >= 12, "made=%d" % made)
	for _i in range(6):
		await get_tree().process_frame

	## ── 产品自己的账: 这一页该印哪些数 ───────────────────────────
	## 单路 ⇒ 结算表只有「本场」一页 = 当前 `_units` 按 `_eff_side` 分栏。
	## 走 `battle._st_row()`(产品自己的取数函数), 不在这里另抄一份字段名。
	## ★★必须在 `_show_banner` 的【同一帧之前】取 —— 场上那几只原生单位还在互相打,
	##   晚 20 帧再读, `_st_taken` 已经涨了 ⇒ 逐值对账必然对不上(第一版就红在这里,
	##   零/非零的个数却是对的, 看着像"少了一个数"其实是"数变大了")。
	var want_zero := 0
	var want_num := 0
	var want_vals: Dictionary = {}       # 文本 -> 该出现几次
	for u in sc._units:
		var sd: String = sc._eff_side(u)
		if sd != "left" and sd != "right":
			continue
		var row: Dictionary = sc._st_row(u)
		for key in ["_st_dealt", "_st_taken", "_st_heal", "_st_kills"]:
			var v: int = int(row.get(key, 0))
			if v == 0:
				want_zero += 1
			else:
				want_num += 1
				want_vals[str(v)] = int(want_vals.get(str(v), 0)) + 1
	_ok("★分母: 这批数据里【零值格 %d】与【非零格 %d】两种都有(缺一种 = 空检查)"
		% [want_zero, want_num], want_zero > 0 and want_num > 0)

	sc._hud._show_banner(true)
	for _i in range(20):
		await get_tree().process_frame

	## ── 屏幕侧: 走真控件树找数值格 ───────────────────────────────
	## ★2026-10-04 结算屏三页: 表在「我方」「敌方」两页上, 默认停的「战果」页一张表都没有
	##   ⇒ 两页各翻过去收一次(只收**看得见**的表, 不然合计/分路几份叠在一起会重复数)。
	var grids: Array = []
	var scr = sc._hud._settle
	_ok("★分母: 结算屏建出来了(三页)", scr != null and (scr.pages as Array).size() == 3)
	for pi in [1, 2]:
		scr.show_page(pi)
		for _i in range(4):
			await get_tree().process_frame
		_find_grids(sc._ui_layer, grids)
	var cells: Array = []                # 只收【数值格】那 4 个 Label
	var rows := 0
	for g in grids:
		var kids: Array = (g as Node).get_children()
		var i := 0
		while i < kids.size():
			if kids[i] is HBoxContainer:
				rows += 1
				for j in range(1, 5):
					if i + j < kids.size() and kids[i + j] is Label:
						cells.append(kids[i + j])
				i += 5
				continue
			i += 1
	_ok("① 分母: 真控件树里找到 %d 行 x 4 = %d 个数值格, 且与数据侧对得上(%d)"
		% [rows, cells.size(), want_zero + want_num],
		rows > 0 and cells.size() == rows * 4 and cells.size() == want_zero + want_num,
		"rows=%d cells=%d want=%d grids=%d" % [rows, cells.size(), want_zero + want_num, grids.size()])

	var mark: String = sc._hud.SETTLE_ZERO_MARK
	var got_zero := 0
	var got_num := 0
	var bad_zero := 0
	var got_vals: Dictionary = {}
	for c in cells:
		var t: String = (c as Label).text.strip_edges()
		if t == "0":
			bad_zero += 1
		if t == mark:
			got_zero += 1
		elif t.is_valid_int():
			got_num += 1
			got_vals[t] = int(got_vals.get(t, 0)) + 1
	_ok("③ 一个数值格都没印 \"0\"(分母 %d 格)" % cells.size(), bad_zero == 0, "印了 0 的格 = %d" % bad_zero)
	_ok("④ 零值格印的是产品自己的占位符 \"%s\" —— %d 个, 与数据侧 %d 个一致"
		% [mark, got_zero, want_zero], got_zero == want_zero,
		"got=%d want=%d" % [got_zero, want_zero])
	_ok("⑤ 非零格一个有效数字都没丢(逐值对账)", got_vals == want_vals,
		"屏上 %d 种值 / 数据侧 %d 种值" % [got_vals.size(), want_vals.size()])
	_ok("⑥ ★密度: 屏上数字 token = %d == 非零统计值个数 %d(改前是 %d, 降 %.0f%%)"
		% [got_num, want_num, cells.size(),
		   100.0 * float(cells.size() - got_num) / maxf(1.0, float(cells.size()))],
		got_num == want_num, "got=%d want=%d" % [got_num, want_num])

	## ⑦ 纯函数本身(门禁与屏幕读同一个答案 —— 这条若与上面打架就是有人抄了第二份)
	_ok("⑦ settle_cell_text(0)==占位符 且 settle_cell_text(123)==\"123\"",
		sc._hud.settle_cell_text(0) == mark and sc._hud.settle_cell_text(123) == "123",
		"0->%s  123->%s" % [sc._hud.settle_cell_text(0), sc._hud.settle_cell_text(123)])

	print("")
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d/%d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## 结算表那几个 GridContainer(columns==5)。递归找, 不假设树的层级
## (memory [[fb-recursive-scan-not-structured-walk]]: 别按我以为的层级走)。
func _find_grids(n: Node, acc: Array) -> void:
	if n is GridContainer and (n as GridContainer).columns == 5 and (n as Control).is_visible_in_tree():
		acc.append(n)
	for ch in n.get_children():
		_find_grids(ch, acc)
