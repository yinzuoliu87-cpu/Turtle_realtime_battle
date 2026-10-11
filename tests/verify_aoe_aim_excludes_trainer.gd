extends Node
## verify_aoe_aim_excludes_trainer.gd —— 范围技选落点/弹射挑目标不许把训龟大师算进去(2026-10-11 全项目通读 A3)
## ★糖果炮弹雨 / 雷暴云 / 星际奇点 / 星际彗星 取「敌人质心」当落点, 彩虹反射按下标挑目标 —— 原来都用 `_enemies_of`
##   (含站在岛外后方的大师) ⇒ 落点被拉向岛外 / 白打大师一段。§PICK-TARGET: 选目标走 `_pick_enemies_of`;
##   结算仍是范围扫到谁算谁(大师照吃 AOE 波及)。
## ★判据(源码): 这 5 个函数体里取质心/挑目标的那一句用 _pick_enemies_of, 不许回到 _enemies_of。

var _n := 0
var _fail := 0
const SITES := [
	["res://scripts/systems/skills/candy_system.gd", "func _sk_candy_barrage("],
	["res://scripts/systems/skills/lightning_system.gd", "func _sk_lightning_barrage("],
	["res://scripts/systems/skills/rainbow_system.gd", "func _sk_rainbow_reflect("],
]


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 5)
	return src.substr(i, (j if j > 0 else src.length()) - i)


func _ready() -> void:
	await get_tree().process_frame
	for st in SITES:
		var b := _body(FileAccess.get_file_as_string(str(st[0])), str(st[1]))
		_ok("★★%s 选落点/目标走 _pick_enemies_of, 不用 _enemies_of" % str(st[1]).trim_prefix("func ").trim_suffix("("),
			b.length() > 50 and b.contains("_pick_enemies_of(u)") and not b.contains("_targeting._enemies_of(u)"), "函数体 %d 字符" % b.length())
	var star := FileAccess.get_file_as_string("res://scripts/systems/skills/star_system.gd")
	var n_pick := 0
	for line in star.split(String.chr(10)):
		if line.contains("_pick_enemies_of(u)") and line.contains("A3"):
			n_pick += 1
	_ok("★★星际龟奇点/彗星两处质心都走 _pick_enemies_of", n_pick >= 2, "%d 处" % n_pick)
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
