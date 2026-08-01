extends Node
## verify_codex_browse.gd — 图鉴【每一条都点开一遍】(用户 2026-08-01 报「精英小将的描述都挤在一块」)
##
## ★这个门禁本身就是那次事故的产物。根因是 detail_views.gd 里写了 host.ceilf(...) ——
##   ceilf 是全局内建函数, 不是节点方法, 调用直接 SCRIPT ERROR, 于是那行的 return 永远执行不到,
##   每段正文都拿到同一个 y → 全叠在一起。
##   ★它【只在渲染精英小将详情时】才触发, 而当时没有任何门禁会去点开那几条 →
##     bug 从 2026-07-26 图鉴拆分那天一直活到用户报上来。
##
## ★判据不靠断言, 靠 run-tests.sh 的致命报错正则:
##   FATAL 里已经有 'SCRIPT ERROR|Nonexistent|Invalid call' —— 只要真把每条都点开,
##   任何一条渲染路径报错都会让本测试判红。所以这里的关键是【覆盖率】而不是断言数:
##   下面那条"点开数 == 条目数"的分母断言, 就是防止哪天列表变了却只点到前几条。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_codex_browse.tscn

const SCN := preload("res://scenes/Codex.tscn")
const TABS := ["pets", "equips", "synergies", "status", "rules"]

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 图鉴逐条浏览(每条详情都渲染一遍) ===")
	var inst = SCN.instantiate()
	add_child(inst)
	for _i in range(60):
		await get_tree().process_frame

	var total := 0
	for tab in TABS:
		inst._switch_tab(tab)
		for _i in range(8):
			await get_tree().process_frame
		var cnt: int = inst._items.size()
		var opened := 0
		for idx in range(cnt):
			inst._select(idx)
			await get_tree().process_frame
			opened += 1
		total += opened
		_ok("%s 页每一条都点开了 (%d/%d)" % [tab, opened, cnt], opened == cnt and cnt > 0,
			"条目 %d" % cnt)

	# ★分母: 全表条目数。少于这个说明列表没建全, 上面的"每条都点开"就是空检查。
	_ok("★分母: 五个页签合计点开 %d 条(≥100)" % total, total >= 100, "total=%d" % total)

	# ★精英小将必须真的被渲染到 —— 它在 pets 页【末尾】, 只点前几条永远碰不到,
	#   而 ceilf 那个 bug 恰恰只在它的详情里触发。
	inst._switch_tab("pets")
	for _i in range(8):
		await get_tree().process_frame
	var last: int = inst._items.size() - 1
	inst._select(last)
	for _i in range(4):
		await get_tree().process_frame
	var kids: int = inst.detail.get_child_count()
	_ok("★pets 末条(精英小将)详情真渲染出了内容", kids >= 5, "详情子节点 %d 个" % kids)

	inst.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 图鉴逐条浏览" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
