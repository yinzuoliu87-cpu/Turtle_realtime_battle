extends Node
## verify_hp_ticks.gd — 血条刻度: 1000 一个大刻度, 100 一个小刻度
##
## 用户 2026-10-04 原话:「二是我们血条现在是500一个大刻度对吧，改为1000大刻度，100小刻度」
## 方案书 docs/plans/20261004-五件新需求.md §②。
##
## ★走真对象: 建一根真 HpBar, 喂真单位字典(update_state), 再拿它自己的 _bm / bar_w 去问
##   tick_values —— 而 _draw 画刻度也只走 tick_values(T9 守着这条, 防"判据量的函数没人调")。
##
## 断言:
##   T1 ★maxHp 4500 → 大 4 根(1000/2000/3000/4000) + 小 40 根
##   T2 ★没有 500 那一道大刻度了(改前的规则)
##   T3 小刻度不落在大刻度上(不重复画)
##   T4 小刻度太密就收(沿用改前的 2% 条宽闸): 4900 画、5100 收(边界 5000 本身不当断言, 浮点贴边)
##   T5 ★小刻度收了, 大刻度照画: 10000 血 → 9 根大刻度(改前这里一根都没有)
##   T6 大刻度自己也有闸: 6 万血 → 0 根(1.47px < 1.76px)
##   T7 护盾撑开分母(barMax), 刻度跟着 barMax 走: 4500 血 + 1000 盾 → 大 5 根、小刻度收
##   T8 Boss 条(160 宽)闸按自己的宽度算
##   T9 _draw 走 tick_values(源码判据)

const HpBarScript = preload("res://scripts/scenes/hp_bar.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 14


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _bar(unit: Dictionary, boss := false) -> Node2D:
	var hb = HpBarScript.new()
	add_child(hb)
	hb.setup(true, boss)
	hb.update_state(unit)
	return hb


func _ticks(unit: Dictionary, boss := false) -> Dictionary:
	var hb = _bar(unit, boss)
	var tk: Dictionary = HpBarScript.tick_values(float(hb._bm), float(hb.bar_w))
	hb.queue_free()
	return tk


func _ready() -> void:
	await get_tree().process_frame
	print("=== 血条刻度 1000 大 / 100 小 ===")
	_ok("常量: 大刻度 1000", HpBarScript.TICK_MAJOR == 1000.0, str(HpBarScript.TICK_MAJOR))
	_ok("常量: 小刻度 100", HpBarScript.TICK_MINOR == 100.0, str(HpBarScript.TICK_MINOR))

	var t := _ticks({"hp": 4500.0, "maxHp": 4500.0})
	_ok("★T1 maxHp 4500 → 大刻度 4 根", (t["major"] as Array).size() == 4, str(t["major"]))
	_ok("★T1 maxHp 4500 → 小刻度 40 根", (t["minor"] as Array).size() == 40, "%d 根" % (t["minor"] as Array).size())
	_ok("★T2 没有 500 那一道大刻度", not (t["major"] as Array).has(500.0))
	var overlap := 0
	for v in t["minor"]:
		if (t["major"] as Array).has(v):
			overlap += 1
	_ok("T3 小刻度不落在大刻度上", overlap == 0, "重叠 %d" % overlap)

	t = _ticks({"hp": 4900.0, "maxHp": 4900.0})
	_ok("T4 4900 血: 小刻度照画(1.80px ≥ 2%×88=1.76px)", (t["minor"] as Array).size() == 44, "%d 根" % (t["minor"] as Array).size())
	t = _ticks({"hp": 5100.0, "maxHp": 5100.0})
	_ok("T4 5100 血: 小刻度收起(太密)", (t["minor"] as Array).is_empty(), "%d 根" % (t["minor"] as Array).size())
	_ok("T4 5100 血: 大刻度仍在", (t["major"] as Array).size() == 5, str(t["major"]))

	t = _ticks({"hp": 10000.0, "maxHp": 10000.0})
	_ok("★T5 1 万血: 小刻度收、大刻度 9 根照画", (t["minor"] as Array).is_empty() and (t["major"] as Array).size() == 9,
		"大 %d / 小 %d" % [(t["major"] as Array).size(), (t["minor"] as Array).size()])

	t = _ticks({"hp": 60000.0, "maxHp": 60000.0})
	_ok("T6 6 万血: 大刻度也收(1.47px)", (t["major"] as Array).is_empty(), "%d 根" % (t["major"] as Array).size())

	t = _ticks({"hp": 4500.0, "maxHp": 4500.0, "shield": 1000.0})
	_ok("T7 4500 血 + 1000 盾: 刻度跟 barMax(5500) 走 → 大 5 根", (t["major"] as Array).size() == 5, str(t["major"]))
	_ok("T7 4500 血 + 1000 盾: 小刻度收(1.6px)", (t["minor"] as Array).is_empty())

	t = _ticks({"hp": 8000.0, "maxHp": 8000.0}, true)
	_ok("T8 Boss 条 8000 血: 160 宽下小刻度 2px < 3.2px 收起、大刻度 7 根",
		(t["minor"] as Array).is_empty() and (t["major"] as Array).size() == 7,
		"大 %d / 小 %d" % [(t["major"] as Array).size(), (t["minor"] as Array).size()])

	var src := FileAccess.get_file_as_string("res://scripts/scenes/hp_bar.gd")
	var i0 := src.find("func _draw()")
	var i1 := src.find("## ── 血条刻度", i0 + 5)   # _draw 后面紧跟刻度常量段; 只截 _draw 本体
	var body := src.substr(i0, i1 - i0) if i0 >= 0 else ""
	_ok("T9 _draw 的刻度走 tick_values(不另写一套)", body.contains("tick_values(_bm, w)") and not body.contains("500.0"),
		"_draw 长 %d 字" % body.length())

	_ok("分母: 断言条数 %d ≥ %d" % [_n, MIN_ASSERTS], _n >= MIN_ASSERTS)
	print("ALL PASS — 血条刻度" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
