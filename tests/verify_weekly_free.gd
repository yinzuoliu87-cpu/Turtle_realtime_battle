extends Node
## verify_weekly_free.gd —— 每号每周的限免龟（WeeklyFree）。方案书 20261105c §4.2、20261107 §4.3 / §4.9；接口契约 §4。
##
## 判据（需求原文的字面值）：
##   W1 28 只 = data/pets.json 的 28 只（同顺序）；= 迁移 20261109b `pet_all_ids()` 那 28 只（静态读迁移文件逐只比）
##   W2 ★纯函数：FNV-1a 标准向量（"" / "a"）+ 一组钉死的输入 ⇒ 钉死的 7 只（金标由一份独立的 Python 实现按同一算法算出：
##      h = FNV-1a32("账号|周锚点|龟") ，按 (h, 龟 id) 升序，跳过拥有取前 7；跨进程、跨机器都必须逐只相同）
##   W3 ★同号同周两次调用逐只相同；每次恰 7 只、互不重复、都在 28 只里
##   W4 ★换周就变：50 个号 × 下一周，限免那 7 只（集合）每一个都不同
##   W5 ★跳过已拥有：随机 200 组拥有，限免与拥有不相交；拥有 ≤ 21 ⇒ 恰 7 只；拥有 22 / 28 ⇒ 6 / 0 只
##   W6 ★周中新拥有一只限免龟 ⇒ 只换掉那一只（另 6 只不动），补进来的是排序里的下一只
##   W7 拥有 ∪ 限免：allowed = 拥有（只认 28 只）∪ 限免，按 28 只的顺序
##   W8 不同的号同一周大多不同（不是所有人同一批）
## ★分母：每条都打印比了多少组。

const MIG := "res://server/supabase/migrations/20261109b_pet_levels.sql"
const ACCT := "6f1c2b3a-9d4e-4f50-8a61-7b2c3d4e5f60"
const WEEK := 1762732800
## 金标（独立实现：FNV-1a 32 位 over UTF-8 "账号|周锚点|龟"，按 (哈希, 龟 id) 升序）
const GOLD_FREE := ["dice", "space", "diamond", "gambler", "line", "ninja", "bubble"]
const GOLD_NEXT_WEEK := ["angel", "line", "bubble", "stone", "crystal", "bamboo", "ninja"]
const GOLD_EMPTY_ACCT := ["stone", "candy", "rainbow", "crystal", "hiding", "space", "diamond"]

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 每号每周的限免龟(WeeklyFree) ===")
	## W1
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		ids.append(str((p as Dictionary)["id"]))
	_ok("W1 28 只 = data/pets.json 的 28 只(同顺序)", ids == Array(WeeklyFree.ALL) and ids.size() == 28, "%d 只" % ids.size())
	var sql := FileAccess.get_file_as_string(MIG)
	var re := RegEx.create_from_string("array\\[('basic'[^\\]]*)\\]")
	var m := re.search(sql)
	var sql_ids: Array = []
	if m != null:
		for t in m.get_string(1).split(","):
			sql_ids.append(t.strip_edges().trim_prefix("'").trim_suffix("'"))
	_ok("W1 = 迁移 20261109b pet_all_ids() 那 28 只(逐只)", sql_ids == Array(WeeklyFree.ALL), "%d 只" % sql_ids.size())
	## W2
	_ok("W2 FNV-1a 标准向量: \"\" = 0x811c9dc5, \"a\" = 0xe40c292c",
		WeeklyFree.fnv1a32("") == 0x811c9dc5 and WeeklyFree.fnv1a32("a") == 0xe40c292c,
		"%x / %x" % [WeeklyFree.fnv1a32(""), WeeklyFree.fnv1a32("a")])
	var f0 := WeeklyFree.free_ids(ACCT, WEEK, [])
	_ok("W2 ★钉死的输入 ⇒ 钉死的 7 只(独立实现算的金标)", f0 == GOLD_FREE, str(f0))
	_ok("W2 ★下一周 ⇒ 金标", WeeklyFree.free_ids(ACCT, WEEK + 604800, []) == GOLD_NEXT_WEEK,
		str(WeeklyFree.free_ids(ACCT, WEEK + 604800, [])))
	_ok("W2 没登录(空账号)也是确定的一组", WeeklyFree.free_ids("", 0, []) == GOLD_EMPTY_ACCT, str(WeeklyFree.free_ids("", 0, [])))
	## W3
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261109
	var bad3: Array = []
	var accts: Array = []
	for i in range(50):
		accts.append("%08x-%04x-4%03x-8%03x-%012x" % [rng.randi(), rng.randi() % 0x10000, rng.randi() % 0x1000,
			rng.randi() % 0x1000, rng.randi() * 0x10000 + rng.randi() % 0x10000])
	for a in accts:
		var x := WeeklyFree.free_ids(a, WEEK, [])
		var y := WeeklyFree.free_ids(a, WEEK, [])
		var uniq := {}
		for p in x:
			uniq[p] = true
		if x != y or x.size() != 7 or uniq.size() != 7 or not _all_in(x):
			bad3.append(a)
	_ok("W3 ★同号同周两次逐只相同、恰 7 只、不重复、都在 28 只里(%d 个号)" % accts.size(), bad3.is_empty(), str(bad3.slice(0, 3)))
	## W4
	var same4: Array = []
	for a in accts:
		if _sorted(WeeklyFree.free_ids(a, WEEK, [])) == _sorted(WeeklyFree.free_ids(a, WEEK + 604800, [])):
			same4.append(a)
	_ok("W4 ★换周就变: %d 个号的下一周限免集合都不同" % accts.size(), same4.is_empty(), str(same4.slice(0, 3)))
	## W5
	var bad5: Array = []
	for k in range(200):
		var own: Array = []
		var want := rng.randi_range(0, 21)
		var pool: Array = Array(WeeklyFree.ALL).duplicate()
		for _j in range(want):
			own.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		var a: String = accts[k % accts.size()]
		var fr := WeeklyFree.free_ids(a, WEEK, own)
		var hit := false
		for p in fr:
			if own.has(p):
				hit = true
		if hit or fr.size() != 7:
			bad5.append("%s 拥有 %d 只 ⇒ 限免 %d 只 %s" % [a.substr(0, 8), own.size(), fr.size(), "撞拥有" if hit else ""])
	var own22: Array = Array(WeeklyFree.ALL).slice(0, 22)
	_ok("W5 ★跳过已拥有: 200 组(拥有 0~21 只)限免与拥有不相交、恰 7 只", bad5.is_empty(), str(bad5.slice(0, 3)))
	_ok("W5 拥有 22 只 ⇒ 6 只; 拥有 28 只 ⇒ 0 只", WeeklyFree.free_ids(ACCT, WEEK, own22).size() == 6
		and WeeklyFree.free_ids(ACCT, WEEK, Array(WeeklyFree.ALL)).is_empty())
	## W6
	var bad6: Array = []
	var cases6 := 0
	for a in accts:
		var own0: Array = []
		var base := WeeklyFree.free_ids(a, WEEK, own0)
		for x in base:
			var own1: Array = own0.duplicate()
			own1.append(x)
			var nf := WeeklyFree.free_ids(a, WEEK, own1)
			var kept := 0
			var added: Array = []
			for p in nf:
				if base.has(p):
					kept += 1
				else:
					added.append(p)
			## 补进来的 = 排序里跳过 own1 之后的第 7 只(= 原来第 8 个没拥有的)
			var ordr := WeeklyFree.order(a, WEEK)
			var nxt := ""
			var cnt := 0
			for p in ordr:
				if own1.has(p):
					continue
				cnt += 1
				if cnt == 7:
					nxt = p
					break
			cases6 += 1
			if kept != 6 or added.size() != 1 or added[0] != nxt or nf.has(x):
				bad6.append("%s 新拥有 %s ⇒ 留 %d 只 补 %s(应补 %s)" % [a.substr(0, 8), x, kept, str(added), nxt])
	_ok("W6 ★周中新拥有一只限免龟 ⇒ 只换掉那一只、补的是排序里的下一只(%d 组)" % cases6, bad6.is_empty() and cases6 == 350,
		str(bad6.slice(0, 3)))
	## W7
	var own7 := ["lava", "stone", "not_a_turtle"]
	var al := WeeklyFree.allowed_ids(ACCT, WEEK, own7)
	var exp7: Array = []
	var fr7 := WeeklyFree.free_ids(ACCT, WEEK, own7)
	for p in WeeklyFree.ALL:
		if p == "lava" or p == "stone" or fr7.has(p):
			exp7.append(p)
	_ok("W7 拥有 ∪ 限免(只认 28 只、按 28 只顺序): 9 只", al == exp7 and al.size() == 9 and not al.has("not_a_turtle"), str(al))
	_ok("W7 all_allowed: 拥有的 + 限免的 ⇒ 真; 混进一只两边都不在的 ⇒ 假",
		WeeklyFree.all_allowed(ACCT, WEEK, own7, ["lava", fr7[0], fr7[6]])
		and not WeeklyFree.all_allowed(ACCT, WEEK, own7, ["lava", fr7[0], _outside(al)]))
	## W8
	var distinct := {}
	for a in accts:
		distinct[str(_sorted(WeeklyFree.free_ids(a, WEEK, [])))] = true
	_ok("W8 不同的号同一周不是同一批(%d 个号 ⇒ %d 种)" % [accts.size(), distinct.size()], distinct.size() >= 45)
	_finish()


func _all_in(a: Array) -> bool:
	for p in a:
		if not WeeklyFree.ALL.has(p):
			return false
	return true


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


func _outside(al: Array) -> String:
	for p in WeeklyFree.ALL:
		if not al.has(p):
			return p
	return ""


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 限免龟" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
