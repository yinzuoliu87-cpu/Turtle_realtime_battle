extends Node
## verify_eq058_036_045.gd — 058→远古炮台 / 036 回血改公式 / 045→地狱护盾 (2026-08-31)
##
## ★需求原文(用户 2026-08-31):
##   「穿甲遗弹改为远古炮台并重做图标，温泉蛋的生命恢复改为每秒回复
##     2/5/10+0.3/0.8/1.2%最大生命值，珍珠耳环改命为地狱护盾并重做图标」
##   045 走 (a): **只改名换图, 效果照旧**(用户:「a，有啥对不上的」)。
##
## ★★036 的判据必须【拿两种不同 maxHp 各量一次】——
##   只用一种血量的话, "定额 2 + 0.3%×1000 = 5" 和 "定额 5 + 0%" 给出同一个数,
##   两种实现分不开, 把百分比那一半删掉门禁照样绿。
##   (同族: 上一轮"多件取最大"那条就是因为测试数据让两种行为同解才成了假门禁。)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EquipTickSystem := preload("res://scripts/systems/equip/equip_tick_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 装 036、给定 maxHp、跑一次回血节拍 → 回报这一秒回了多少
func _heal_once(star: int, maxhp: float) -> float:
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-120.0, 0.0))
	u["equips"] = [{"id": "p2eq_036", "star": star}]
	u["eq_state"] = {"p2eq_036": {}}
	_s._units.append(u)
	_s._equip_sys._stats._eq_apply_all_stats()
	u["maxHp"] = maxhp
	u["hp"] = maxhp * 0.5          # 留出回血空间, 满血会被 _heal 截断
	u["heal_amp"] = 0.0
	var h0: float = float(u["hp"])
	_s._equip_tick_sys._tick_hotspring(u, EquipTickSystem.HOTSPRING_IV)
	return float(u["hp"]) - h0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 058 远古炮台 / 036 回血 / 045 地狱护盾 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	# ── 036: 逐星 × 两种血量 ──
	var flat: Array = EquipTickSystem.HOTSPRING_FLAT
	var pct: Array = EquipTickSystem.HOTSPRING_PCT
	_ok("036 ★分母: 常量表 = 定额 %s + 百分比 %s" % [str(flat), str(pct)],
		flat == [2.0, 5.0, 10.0] and pct == [0.003, 0.008, 0.012])
	var ok_all := true
	var detail: Array = []
	for si in range(3):
		for mh in [1000.0, 6000.0]:
			var got: float = _heal_once(si + 1, mh)
			var want: float = float(flat[si]) + mh * float(pct[si])
			detail.append("%d★/%.0fHP: %.1f(期望 %.1f)" % [si + 1, mh, got, want])
			if absf(got - want) > 0.6:
				ok_all = false
	_ok("036 ★★逐星 × 两种血量都等于【定额 + 百分比×最大生命】", ok_all, " · ".join(detail))

	## ★分母的另一半: 两种血量下的回血必须【不一样】——
	##   一样就说明百分比那半没生效, 而上面那条可能因为凑巧的数字仍然绿。
	var lo: float = _heal_once(3, 1000.0)
	var hi: float = _heal_once(3, 6000.0)
	_ok("036 ★★血量翻 6 倍 → 回血必须变多(证明百分比那半真的在算)",
		hi > lo + 20.0, "1000HP 回 %.1f / 6000HP 回 %.1f" % [lo, hi])

	# ── 058 / 045: 改名换图, 效果不动 ──
	var e58: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_058", {})
	_ok("058 名字 = 远古炮台", str(e58.get("name", "")) == "远古炮台", str(e58.get("name", "")))
	_ok("058 图标换成专属新图且文件在盘上",
		str(e58.get("img", "")) == "equip/ancient-turret.png"
		and ResourceLoader.exists("res://assets/sprites/equip/ancient-turret.png"))
	_ok("058 ★效果文案一个字没动(只换名换图)",
		str(e58.get("effectDesc1", "")).contains("召唤一座不可移动的炮台"))

	var e45: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_045", {})
	_ok("045 名字 = 地狱护盾", str(e45.get("name", "")) == "地狱护盾", str(e45.get("name", "")))
	_ok("045 图标换成专属新图且文件在盘上",
		str(e45.get("img", "")) == "equip/hell-shield.png"
		and ResourceLoader.exists("res://assets/sprites/equip/hell-shield.png"))
	## ★这条防的是"以后有人看名字叫护盾, 就顺手把效果改成加护盾" ——
	##   用户 2026-08-31 明知名字与效果不对应, 拍板 (a) 照旧。
	_ok("045 ★★效果仍是【残血回血 + 火球点燃】(用户拍板 (a), 名字与效果不对应是有意的)",
		str(e45.get("effectDesc1", "")).contains("发射火球")
		and str(e45.get("effectDesc1", "")).contains("回复"))

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 9:
		print("  [FAIL] ★分母: 断言只有 %d 条(<9)" % _n)
		_fail += 1
	print("ALL PASS — 058/036/045" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
