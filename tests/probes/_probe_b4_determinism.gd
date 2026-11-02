extends Node
## _probe_b4_determinism.gd — 批④ 17 件全在场时的【确定性】探针
## ★`_` 开头 ⇒ 不被 run-tests.sh 的 `verify_*.gd` 自动发现。临时探针, 不是门禁。
##
## ★分层对照(不然分不清是"17 件破了确定性"还是"我这个场景本来就不确定"):
##   ⓪ 复刻 verify_battle_determinism 的场景(1 攻击龟 + 1 假人)     → 已知应当确定
##   ① 同样两只, 但左边这只带 5 件批④                                 → 装备层
##   ② 3v3 裸装                                                        → 多单位/移动层
##   ③ 3v3 带满 17 件                                                  → 全量
## 每一档都打印 `_deterministic`(det 模式没开的话整档结论作废)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const ALL17: Array = [
	"p2eq_077", "p2eq_078", "p2eq_079", "p2eq_080", "p2eq_081", "p2eq_082",
	"p2eq_083", "p2eq_084", "p2eq_085", "p2eq_086", "p2eq_087", "p2eq_088",
	"p2eq_089", "p2eq_090", "p2eq_091", "p2eq_093", "p2eq_094",
]

var _fail := 0
var _n := 0
var _last_det := false

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond: print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _fp_parts(scene) -> Array:
	var parts: Array = []
	for u in scene._units:
		parts.append("%s|%s:%.2f:%.1f:%.1f" % [
			str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)),
			float((u.get("pos", Vector2()) as Vector2).x),
			float((u.get("pos", Vector2()) as Vector2).y)])
	parts.sort()
	return parts


## pairs = [[turtle_id, side, dx, dy, equips], ...]
func _run_once(pairs: Array, frames: int) -> Array:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	for p in pairs:
		var u: Dictionary = s._debug._edit_place_unit(str(p[0]), str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
	s._debug._edit_start_battle()
	for _i in range(frames):
		await get_tree().process_frame
	_last_det = bool(s._deterministic)
	var parts := _fp_parts(s)
	var extra := "det=%s;t=%.4f;units=%d" % [str(s._deterministic), float(s._t), s._units.size()]
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return [extra + ";" + "|".join(parts), parts, extra]


func _diff(a: Array, b: Array) -> String:
	var out: Array = []
	for i in range(maxi(a.size(), b.size())):
		var x: String = str(a[i]) if i < a.size() else "<缺>"
		var y: String = str(b[i]) if i < b.size() else "<缺>"
		if x != y:
			out.append("%s ≠ %s" % [x, y])
	return " ;; ".join(out).substr(0, 420)


func _pair_test(tag: String, pairs: Array, frames: int) -> void:
	OS.set_environment("TURTLE_SEED", "20260806")
	var a: Array = await _run_once(pairs, frames)
	var b: Array = await _run_once(pairs, frames)
	OS.set_environment("TURTLE_SEED", "")
	_ok(tag, str(a[0]) == str(b[0]), "%s   %s" % [str(a[2]), _diff(a[1], b[1])])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	print("=== ⓪ 对照: 复刻 verify_battle_determinism 的场景(2 单位·裸装) ===")
	await _pair_test("⓪ 2 单位裸装 · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, []], ["basic", "right", 400.0, 300.0, []]], 200)

	print("=== ① 同样 2 单位, 左边带 5 件批④(077/080/086/087/094 —— 全批用了 RNG 的那几件) ===")
	await _pair_test("① 2 单位 + 5 件用 RNG 的批④ · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, ["p2eq_077", "p2eq_080", "p2eq_086", "p2eq_087", "p2eq_094"]],
		 ["basic", "right", 400.0, 300.0, []]], 200)

	print("=== ①a 只带 077(唯一走 _spawn_summon 且【不覆盖落点】的一件) ===")
	await _pair_test("①a 2 单位 + 只带 077 · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, ["p2eq_077"]], ["basic", "right", 400.0, 300.0, []]], 200)

	print("=== ①b 带 080/086/087/094(这四件自己掷骰, 但全走 _battle_rng) ===")
	await _pair_test("①b 2 单位 + 080/086/087/094 · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, ["p2eq_080", "p2eq_086", "p2eq_087", "p2eq_094"]],
		 ["basic", "right", 400.0, 300.0, []]], 200)

	print("=== ①c 只带 079(也走 _spawn_summon, 但生成后【立刻覆盖】落点) ===")
	await _pair_test("①c 2 单位 + 只带 079 · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, ["p2eq_079"]], ["basic", "right", 400.0, 300.0, []]], 200)

	print("=== ①d ★对照: 【旧】装备 058 穿甲遗弹 / 032 亡灵骷髅(同样走 _spawn_summon) ===")
	await _pair_test("①d 2 单位 + 旧装备 058(炮台) · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, ["p2eq_058"]], ["basic", "right", 400.0, 300.0, []]], 200)
	await _pair_test("①e 2 单位 + 旧装备 032(骷髅) · 同种子两遍指纹相同",
		[["basic", "left", 320.0, 300.0, ["p2eq_032"]], ["basic", "right", 400.0, 300.0, []]], 200)

	print("=== ② 对照: 3v3 裸装(只多了单位数与移动) ===")
	var bare3: Array = [
		["stone", "left", 320.0, 220.0, []], ["basic", "left", 320.0, 320.0, []],
		["ninja", "left", 320.0, 420.0, []],
		["basic", "right", 900.0, 220.0, []], ["basic", "right", 900.0, 320.0, []],
		["basic", "right", 900.0, 420.0, []]]
	await _pair_test("② 3v3 裸装 200 帧 · 同种子两遍指纹相同", bare3, 200)
	await _pair_test("②' 3v3 裸装 500 帧(跑到真交火) · 同种子两遍指纹相同", bare3, 500)

	print("=== ③ 3v3 带满 17 件 ===")
	var full3: Array = []
	for k in range(3):
		var el: Array = []
		for i in range(ALL17.size()):
			if i % 3 == k:
				el.append(ALL17[i])
		full3.append([["stone", "basic", "ninja"][k], "left", 320.0, 220.0 + 100.0 * float(k), el])
	for k in range(3):
		full3.append(["basic", "right", 900.0, 220.0 + 100.0 * float(k), []])
	await _pair_test("③ 3v3 + 17 件全在场 · 同种子两遍指纹相同", full3, 200)

	print("")
	if _fail == 0: print("ALL PASS — 批④确定性探针 %d 条" % _n)
	else: print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
