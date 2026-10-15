extends Node
## verify_apply_damage_args.gd —— `_apply_damage` 第 4 个参数是 src(单位字典或 null), 不许传 bool(2026-10-11 全项目通读 A7)
##
## ★枪羁绊炮台二在携枪者全灭后的回退分支写成 `_apply_damage(t, dmg, col, true)` ⇒ true 进了 src 位,
##   bucket 仍是默认 "dot" ⇒ 本该无视受害者减免的真伤变成吃减免(钻石结构/岩层/铁壁)的持续伤害, 统计也记成 DoT。
## ★两半: ① 运行时: 同一发 100 点打钻石龟, bucket="tru" 吃满 / 默认 dot 被「结构」减免(证明桶决定吃不吃受害者减免, 分母);
##   ② 源码扫描: 全仓 `_apply_damage(` 调用第 4 个实参不许是 true/false 字面量。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with("."):
				_walk(dir.path_join(f), out)
		elif f.ends_with(".gd"):
			out.append(dir.path_join(f))
		f = d.get_next()


func _ready() -> void:
	await get_tree().process_frame
	print("=== _apply_damage 第 4 参是 src ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var t: Dictionary = s._spawn._make_unit("green", "right", c)
	t["flat_dr"] = 10.0   # 016 铁壁盾式每段固定减免: 只对非真伤生效(_mitigate_incoming 的 not raw)。原用钻石结构, 2026-10-15 它并入了减伤属性
	s._units.append(t)
	t["maxHp"] = 1.0e6
	t["hp"] = 1.0e6
	s._damage._apply_damage(t, 100, Color.WHITE, null, "tru")
	var tru: float = 1.0e6 - float(t["hp"])
	t["hp"] = 1.0e6
	s._damage._apply_damage(t, 100, Color.WHITE)
	var dot: float = 1.0e6 - float(t["hp"])
	_ok("★分母: tru 桶吃满、默认 dot 桶被每段固定减免(桶决定吃不吃受害者减免)", absf(tru - 100.0) < 0.5 and dot < tru - 0.5,
		"tru %.0f / dot %.0f" % [tru, dot])
	var files: Array = []
	_walk("res://scripts", files)
	_walk("res://autoload", files)
	var re := RegEx.new()
	re.compile("_apply_damage\\(([^,()]+(?:\\([^()]*\\))?[^,()]*,){3}\\s*(true|false)\\s*[,)]")
	var bad: Array = []
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for m in re.search_all(src):
			bad.append("%s: %s" % [str(f).get_file(), m.get_string().left(80)])
	_ok("★分母: 扫了 %d 个脚本" % files.size(), files.size() > 100)
	_ok("★★全仓没有把 bool 传进 _apply_damage 的 src 位", bad.is_empty(), str(bad))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
