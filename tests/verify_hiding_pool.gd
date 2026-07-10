extends Node
## verify_hiding_pool.gd — 守卫: 缩头召唤池 = 全部 A/B/C 稀有度的龟, 且每只能当随从不崩
##
## 用户〖2026-07-11〗:「缩头乌龟只能召唤A及以下的」「确保涵盖所有A，B，C的」
##   → _hiding_pool() 运行时从稀有度动态生成; 本测试断言它【恰好】= 全部 A/B/C 龟(不多不少),
##     且逐只 _make_unit 当随从不崩(捕过去只测了固定 12 只名单)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	# 从 pets.json 算出应有的 A/B/C 集合
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	var pets: Array = doc["pets"] if (doc is Dictionary and doc.has("pets")) else doc
	var want: Dictionary = {}
	for p in pets:
		var r := str(p.get("rarity", ""))
		if r == "A" or r == "B" or r == "C":
			want[str(p.get("id", ""))] = true

	var pool: Array = scene._hiding_pool()
	var got: Dictionary = {}
	for x in pool:
		got[str(x)] = true

	# ── 自检探针 ──
	_ok("自检·阳性(basic 是 C 级, 应在池里)", want.has("basic"))
	_ok("自检·阴性(shell 是 SSS 级, 不该在池里)", not want.has("shell"))
	_ok("自检·阴性(headless 是 SS 级, 不该在池里)", not want.has("headless"))

	# ── 1. 池 == 全部 A/B/C ──
	var extra: Array = []
	for x in got.keys():
		if not want.has(x):
			extra.append(x)
	var lack: Array = []
	for x in want.keys():
		if not got.has(x):
			lack.append(x)
	_ok("缩头池 = 全部 A/B/C 稀有度的龟", extra.is_empty() and lack.is_empty(),
		"多出 %s / 缺少 %s (池 %d 只)" % [str(extra), str(lack), pool.size()])

	# ── 2. 每只都能当随从 spawn 不崩 ──
	var crashed: Array = []
	for pid in want.keys():
		var m: Dictionary = scene._make_unit(str(pid), "right", Vector2(900, 400))
		if m.is_empty() or not m.has("hp"):
			crashed.append(str(pid))
	_ok("每只 A/B/C 龟都能 _make_unit 当随从", crashed.is_empty(), str(crashed))

	print("")
	if _fail == 0:
		print("ALL PASS — 缩头池 = 全 A/B/C(", want.size(), "只), 无 S/SS/SSS, 逐只可当随从")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
