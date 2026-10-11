extends Node
## verify_reset_save_clears.gd —— 「重置存档」要清掉赛季重置会清的每一个字段(2026-10-11 全项目通读 B3)
##
## ★reset_save 是 start_new_season 的手抄副本(memory fb-hand-rolled-copies-drift), 原来漏了
##   loadouts / chest_treasure_value / chest_treasures_won。
## ★判据: 三个字段写非默认值 → reset_save() → 与 start_new_season() 之后的值一致;
##   另外静态比两函数赋值的字段集: start_new_season 清的, reset_save 必须也清(不许再漂)。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _assigned(src: String, fname: String) -> Array:
	var i := src.find("\nfunc %s(" % fname)   # 行首那个(注释里也可能出现 "func xxx(")
	var j := src.find("\nfunc ", i + 5)
	var body := src.substr(i, (j if j > 0 else src.length()) - i)
	print("    [%s] 函数体 %d 字符" % [fname, body.length()])
	var re := RegEx.new()
	re.compile("(?m)^\\t([a-z_][a-z0-9_]*)\\s*=")
	var out: Array = []
	for m in re.search_all(body):
		if not (m.get_string(1) in out):
			out.append(m.get_string(1))
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== 重置存档清干净 ===")
	var gs = GameState
	gs.test_mode = true
	var src := FileAccess.get_file_as_string("res://autoload/GameState.gd").replace("\r\n", "\n")
	var season := _assigned(src, "start_new_season")
	var reset := _assigned(src, "reset_save")
	_ok("★分母: 两个函数都找到了字段赋值", season.size() > 10 and reset.size() > 10, "%d / %d" % [season.size(), reset.size()])
	var miss: Array = []
	for f in season:
		if not (f in reset):
			miss.append(f)
	_ok("★★赛季重置清的字段, 重置存档也都清", miss.is_empty(), "漏: %s" % str(miss))
	gs.loadouts = {"basic": 3}
	gs.chest_treasure_value = 999
	gs.chest_treasures_won = [1, 2]
	gs.reset_save()
	_ok("★重置后技能选择清空", (gs.loadouts as Dictionary).is_empty(), str(gs.loadouts))
	_ok("★重置后宝箱龟财宝清零", int(gs.chest_treasure_value) == 0 and (gs.chest_treasures_won as Array).is_empty(),
		"%s / %s" % [str(gs.chest_treasure_value), str(gs.chest_treasures_won)])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
