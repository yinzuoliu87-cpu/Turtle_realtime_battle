extends Node
## verify_equip_stats_source.gd — 守卫「装备属性只有一个事实源」
##
## 背景(2026-07-20 规范化):
##   装备的属性数值有两份: 代码里的 `P2RT.STATS`(战斗实装真取值) 和
##   data/phase2-equipment.json 里手写的 `baseStats1` 字符串(展示用镜像)。
##   两者靠【人工核对】保持一致 —— tools/hp_s9_equip.py 的注释写着"已核实逐星逐字段 0 差异",
##   但没有任何机制阻止它以后漂移。图鉴此前直接打印 baseStats1, 于是玩家看到的可能不是实装值。
##
## 本轮已把图鉴改成走 P2RT.stat_line_all_stars()。本测试守两件事:
##   A. 图鉴/背包【不准】再回退到直接打印 baseStats1 —— 源码级防复发
##   B. baseStats1 里出现的数字, 必须都能在该装备的 STATS 里找到
##      (它还被云端同步工具当展示串推上去, 删不掉, 那就锁住它)
##
## ★为什么 B 用"数字集合包含"而不是字符串相等: 两者格式本就不同
##   ("+攻8/14/30·护穿5/7/10" vs "攻击力 +8/+14/+30 · 护甲穿透 +5/+7/+10"),
##   能核的是数值本身。反向验证见文件末尾 _selftest_can_fail()。

const P2RT := preload("res://scripts/engine/phase2_equip_runtime.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	var eq_list: Array = _load_equipment()
	_ok("装备数据已载入", eq_list.size() > 0, "%d 件" % eq_list.size())

	_test_no_raw_basestats_in_ui()
	_test_formatter_sanity()
	_test_mirror_numbers_match(eq_list)
	_selftest_can_fail()

	print("ALL PASS — 装备属性单一事实源(P2RT.STATS)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _load_equipment() -> Array:
	var f := FileAccess.open("res://data/phase2-equipment.json", FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		return parsed
	if parsed is Dictionary:
		for k in ["equipment", "items"]:
			if parsed.has(k) and parsed[k] is Array:
				return parsed[k]
	return []


## A. UI 不准直接打印 baseStats1(防复发)
func _test_no_raw_basestats_in_ui() -> void:
	for path in ["res://scripts/scenes/CodexScene.gd", "res://scripts/scenes/InventoryScene.gd"]:
		var src := _src(path)
		var bad := 0
		for line in src.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			# 取值并往界面上放 = 回退了; 只在注释里提到它不算
			if t.contains("baseStats1"):
				bad += 1
		_ok("%s 不再直接取用 baseStats1" % path.get_file(), bad == 0, "残留 %d 处" % bad)


## B1. 格式化器本身可用
func _test_formatter_sanity() -> void:
	var lines: Array = P2RT.stat_lines_all_stars("p2eq_003")
	_ok("stat_lines_all_stars 有输出", lines.size() > 0, "%d 个字段" % lines.size())
	var s: String = P2RT.stat_line_all_stars("p2eq_003")
	_ok("三星合并串含 1★/2★/3★ 三个值", s.count("/") >= 2, s)
	# 缺失星级补 "—" 而不是崩
	var missing: String = P2RT.stat_line_all_stars("p2eq_不存在")
	_ok("未知装备返回兜底串而非崩溃", missing == "无属性加成", missing)


## B2. baseStats1 里的数字必须都在 STATS 里存在
func _test_mirror_numbers_match(eq_list: Array) -> void:
	var checked := 0
	var bad: Array = []
	for e in eq_list:
		var eid: String = str(e.get("id", ""))
		var mirror: String = str(e.get("baseStats1", ""))
		if eid == "" or mirror.strip_edges() == "":
			continue
		var code_nums: Dictionary = _numbers_of_stats(eid)
		if code_nums.is_empty():
			continue
		checked += 1
		for n in _numbers_in(mirror):
			if not code_nums.has(n):
				bad.append("%s(%s) 文案有 %s 但 STATS 里没有" % [eid, str(e.get("name", "")), n])
				break
	# ★打印分母: N=0 是空检查, 不是通过
	_ok("baseStats1 数值 ⊆ STATS 数值", bad.is_empty(),
		"核了 %d 件; 分歧: %s" % [checked, "; ".join(PackedStringArray(bad)) if not bad.is_empty() else "无"])
	_ok("★核对分母非空(防空检查)", checked >= 50, "checked=%d" % checked)


## 某装备三个星级下 STATS 里出现过的所有数值(按玩家可见口径, 与 stat_lines 同)
func _numbers_of_stats(eid: String) -> Dictionary:
	var out: Dictionary = {}
	for s in [1, 2, 3]:
		for kv in P2RT.stat_lines(eid, s):
			for n in _numbers_in(str(kv[1])):
				out[n] = true
	return out


func _numbers_in(s: String) -> Array:
	var re := RegEx.new()
	re.compile("\\d+(?:\\.\\d+)?")
	var out: Array = []
	for m in re.search_all(s):
		out.append(m.get_string())
	return out


## ★证明本测试会 FAIL: 拿一个刻意错的镜像串去过 B2 的判据, 必须被判为不匹配。
## (没有这段, "0 分歧" 可能只是判据恒真。)
func _selftest_can_fail() -> void:
	var code_nums: Dictionary = _numbers_of_stats("p2eq_003")
	var fake := "+攻99999/88888/77777"
	var caught := false
	for n in _numbers_in(fake):
		if not code_nums.has(n):
			caught = true
			break
	_ok("★自证: 伪造的错误数值会被判据抓出来", caught,
		"p2eq_003 的 STATS 数值集=%s" % [code_nums.keys()])
	_ok("★自证: 真实镜像串不会被误报", _numbers_in("+攻8/14/30").all(func(n): return code_nums.has(n)))


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
