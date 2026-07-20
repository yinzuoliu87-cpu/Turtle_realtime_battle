extends Node
## verify_eq_hp_grants.gd — 守卫「装备的固定生命加成 = 文案写的值」
##
## 起因(2026-07-19): 020 哑铃写成 `[40,75,110][si] * HP_MULT`(HP_MULT=3.0) → 实发 120/225/330,
## 而文案是「每层最大生命与当前生命+40/75/110」; 039 竹制弓箭同病(50/70/90 实发 150/210/270)。
## 更麻烦的是同一个盲区还污染了文案核对: 当时"把59件装备文案改成与代码一致"是【只读数组字面量】,
## 于是文案和代码各错各的、还互相印证。这个 bug 也是之前那批僵持局的真凶之一。
##
## 断言:
##   A. 020 哑铃 3★ 跑一轮锻炼, maxHp 与当前生命各 +110(文案值), 不是 330。
##   B. 静态扫描: 不允许再出现「固定生命加成 × HP_MULT」的写法。
##      HP_MULT 按 RealtimeBattle3DScene.gd L45 的规则只能用于【召唤raw值(×)】和【装备%回收(maxHp/)】。
##
## ★为什么要静态扫描: A 只盖得住哑铃这一件。这类错误的形态是"数值对、表达式尾巴上多了乘数",
##   逐件写运行时断言成本太高, 静态扫一遍能拦住整类复发。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"

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
	await _test_dumbbell()
	_test_no_hpmult_on_flat_grants()
	print("ALL PASS — 装备固定生命加成 == 文案值" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)

## A. 020 哑铃 3★: 一轮锻炼应 +110 maxHp / +110 当前生命
func _test_dumbbell() -> void:
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	var u: Dictionary = {
		"id": "basic", "name": "测试龟", "side": "left", "alive": true,
		"hp": 1000.0, "maxHp": 1000.0, "atk": 50.0, "pos": Vector2(0, 0),
		"eq_state": {}, "equips": [], "buffs": [],
		"crit": 0.0, "crit_dmg": 1.5, "dmg_dealt": 0.0, "def": 20.0, "mr": 20.0,   # 掷哑铃阶段会读这些, 缺了会刷 SCRIPT ERROR(断言仍过, 但输出脏)
	}
	var hp0: float = u["hp"]
	var mx0: float = u["maxHp"]
	scene._eq_dumbbell_routine(u, 2)          # si=2 → 3★ → 文案 +110
	await get_tree().create_timer(1.6).timeout   # 锻炼有 3×0.3s 蹲起动作, 等它走完
	var d_mx: float = float(u["maxHp"]) - mx0
	var d_hp: float = float(u["hp"]) - hp0
	_ok("020 哑铃 3★ 最大生命 +110(文案值, 非 330)", is_equal_approx(d_mx, 110.0), "实际 +%.0f" % d_mx)
	_ok("020 哑铃 3★ 当前生命同步 +110", is_equal_approx(d_hp, 110.0), "实际 +%.0f" % d_hp)
	var stt: Dictionary = u["eq_state"].get("p2eq_020", {})
	_ok("020 锻炼层 +1", int(stt.get("exercise", 0)) == 1, "层数=%d" % int(stt.get("exercise", 0)))
	scene.queue_free()
	await get_tree().process_frame

## B. 静态: 固定生命加成不得乘 HP_MULT
func _test_no_hpmult_on_flat_grants() -> void:
	var f := FileAccess.open(SRC_PATH, FileAccess.READ)
	if f == null:
		_ok("读取战斗场源码", false, "打不开 " + SRC_PATH)
		return
	var bad: Array = []
	var ln := 0
	while not f.eof_reached():
		var line := f.get_line()
		ln += 1
		if not line.contains("HP_MULT"):
			continue
		# 合法用法: 召唤 raw 值(_spawn_summon 的 hp 参数 × HP_MULT) / 百分比回收(maxHp / HP_MULT) / 常量定义 / 注释
		if line.contains("/ HP_MULT") or line.contains("_spawn_summon") or line.contains("const HP_MULT"):
			continue
		var t := line.strip_edges()
		if t.begins_with("#"):
			continue
		# 到这里还带 "* HP_MULT" 的, 都是可疑的固定值放大
		if line.contains("* HP_MULT"):
			bad.append("L%d: %s" % [ln, t.substr(0, 90)])
	f.close()
	_ok("无「固定生命加成 × HP_MULT」写法(装备hp已是最终值·见L45规则)",
		bad.is_empty(), "; ".join(bad))
