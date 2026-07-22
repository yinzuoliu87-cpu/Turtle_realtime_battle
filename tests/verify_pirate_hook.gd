extends Node
## verify_pirate_hook.gd — 自证: 海盗「掠夺」被动的死亡钩索 = 原版语义
## 跑法: godot --headless --path . res://tests/verify_pirate_hook.tscn --quit-after 300
##
## 回合制【原版】逐字（回合制 pets.json passive.desc）:
##   「海盗龟开局轰击随机敌人…；死亡时钩锁【击杀者】，同样造成 25%最大生命值 真实伤害。」
## 用户〖#15〗「掠夺我是说被动的【原版】海盗被动」
##
## 原实装 bug: 「任意敌人阵亡 → 存活的敌对海盗龟钩索【最近敌】」——触发条件与目标都不对。
##
## 本测试直接构造两只单位, 调 _kill(pirate, killer), 断言:
##   1. 击杀者掉了 25% 自身最大生命 (真实伤害, 穿双抗)
##   2. 击杀者被拉近到海盗尸位 90 码
##   3. 【非海盗】单位死亡时不触发钩索
##   4. 海盗被【召唤物】以外的单位杀死才算(is_summon 海盗不触发)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	print("=== 1. 海盗阵亡 → 钩锁击杀者 ===")
	var pirate: Dictionary = _find(scene, "pirate")
	if pirate.is_empty():
		# 场上没有海盗 → 手工造一只
		pirate = scene._make_unit("pirate", "left", Vector2(500, 400))
		scene._units.append(pirate)
	var killer: Dictionary = _first_enemy(scene, pirate)
	if killer.is_empty():
		print("  – 找不到敌方单位, 跳过"); _done(); return

	# ★隔离: 场景仍在 tick, 其它单位会打 killer → 只留 pirate + killer 存活, 并清掉 killer 身上的 DoT
	for o in scene._units:
		if o is Dictionary and o != pirate and o != killer:
			o["alive"] = false
	killer["stacks"] = {}
	killer["dots"] = []
	killer["_review_dummy"] = false   # ★评审假人"受击即回满", 会把伤害抹平 → 关掉才测得到真伤害
	killer["hp"] = killer["maxHp"]
	# ★★2026-07-10 轮G 才查明的真 flaky 源: got=188 vs expect=125, 188 = 125×1.5 = 【暴击】。
	#   `_apply_damage_from(..., raw=true)` 的真实伤害【照样掷暴击】(见该函数 "if raw and src.has(\"crit\")"),
	#   海盗 crit=0.25 / crit_dmg=1.5 → 每 4 次就有 1 次 188。
	#   我此前把它归咎于"场景 tick 污染", 并声称"连跑5次证明不flaky" —— 25% 的概率 5 次抓不到, 那句话是说早了。
	#   本测试只想验【钩索基础伤害 = 25% 击杀者最大生命】, 与暴击无关 → 把暴击率置 0 消除随机。
	pirate["crit"] = 0.0
	killer["pos"] = pirate["pos"] + Vector2(600, 0)     # 放远一点, 验证拉近
	var hp0: float = killer["hp"]
	var expect: int = int(float(killer["maxHp"]) * 0.25)

	scene._kill(pirate, killer)
	# ★不能死等墙钟时间。2026-07-22 在 CI(Linux)上连红两次而本地 6/6 全过, 根因是机制级的:
	#   战斗时钟 `_t` 用的是【钳制后】的 delta(_process 开头 `delta = minf(delta, 0.1)` 防卡死),
	#   而 get_tree().create_timer() 用的是【未钳制】的真实帧 delta。
	#   慢机器上一帧超过 0.1 秒时, 计时器按真实时间走、战斗时钟最多只走 0.1/帧
	#   → 游戏时间落后于计时器 → 1.4 秒到点时钩索还没结算 → got=0。
	#   改成【轮询等效果真的落地】: 快慢机器都对, 且比死等更快返回。
	# ★等待上限该用【墙钟】, 不是帧数、也不是游戏时钟。2026-07-23 一次踩了两个坑:
	#   ① 按【帧数】(600) —— 本地 94 帧就落地, 但 CI 无头帧率极高、每帧只推进 1ms 上下,
	#      同样的时间要跑上千帧 → 循环没退出 → "ALL PASS" 没打出来 →
	#      run-tests.sh 判 FAIL(rc=0、致命报错=0), 看着像断言失败, 其实是被帧预算掐断。
	#   ② 按【游戏时钟 _t】—— 更糟: _kill 之后战斗判定结束(_over), _t 直接不走了,
	#      实测 "游戏时间 0.00 秒 / 94 帧"。拿一个冻结的时钟当尺子, 永远不会超时。
	#   钩索是 tween 驱动的(甩钩→拉拽→到位才结算), tween 走真实时间, 所以墙钟才是对的尺子。
	var _ms0: int = Time.get_ticks_msec()
	var _frames := 0
	while Time.get_ticks_msec() - _ms0 < 5000 and float(killer["hp"]) >= hp0:
		await get_tree().process_frame
		_frames += 1
	print("  (钩索落地: 墙钟 %d 毫秒 / %d 帧)" % [Time.get_ticks_msec() - _ms0, _frames])
	# ★这条辅助函数叫 _ok 不是 _fail(本文件里 _fail 是个计数用的 int) —— 我又一次凭印象写函数名,
	#   今天第三次(range/atk_range、spr/sprite)。写之前 grep 一下实际名字。
	_ok("钩索在超时前结算了(超时 = 根本没触发, 不是数值不对)",
		float(killer["hp"]) < hp0, "等了 %d 毫秒仍未结算" % (Time.get_ticks_msec() - _ms0))

	var lost: float = hp0 - float(killer["hp"])
	_ok("击杀者受到 ≈25% 自身最大生命的伤害", absf(lost - float(expect)) <= 2.0,
		"expect≈%d, got=%.0f" % [expect, lost])
	var dist: float = pirate["pos"].distance_to(killer["pos"])
	_ok("击杀者被拉近到海盗尸位 ~90 码", dist <= 95.0, "dist=%.1f" % dist)

	print("=== 2. 非海盗死亡 → 不触发钩索 ===")
	var other: Dictionary = _find_not(scene, "pirate")
	var k2: Dictionary = _first_enemy(scene, other)
	if other.is_empty() or k2.is_empty():
		print("  – 场上凑不出组合, 跳过")
	else:
		for o2 in scene._units:
			if o2 is Dictionary and o2 != other and o2 != k2:
				o2["alive"] = false
		k2["stacks"] = {}
		k2["dots"] = []
		k2["_review_dummy"] = false
		k2["hp"] = k2["maxHp"]
		var before: float = k2["hp"]
		scene._kill(other, k2)
		await get_tree().process_frame
		_ok("非海盗阵亡时击杀者不掉血(无钩索)", is_equal_approx(before, float(k2["hp"])),
			"before=%.0f after=%.0f" % [before, float(k2["hp"])])

	print("=== 3. 源码级: 不再是「任意敌死→钩最近敌」 ===")
	var src := _src("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("触发条件是 u.id == pirate", src.find("u.get(\"id\", \"\") == \"pirate\" and not u.get(\"is_summon\", false) and killer is Dictionary") >= 0)
	_ok("目标是 killer, 不是 _nearest_enemy", src.find("var kk: Dictionary = killer") >= 0)   # 2026-07-14钩索动画重做后变量改名

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 海盗死亡钩索 = 原版语义(自己死 → 钩击杀者)")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _find(scene, pid: String) -> Dictionary:
	for u in scene._units:
		if u is Dictionary and str(u.get("id", "")) == pid and u.get("alive", false):
			return u
	return {}


func _find_not(scene, pid: String) -> Dictionary:
	for u in scene._units:
		if u is Dictionary and str(u.get("id", "")) != pid and u.get("alive", false) and not u.get("is_summon", false):
			return u
	return {}


func _first_enemy(scene, u: Dictionary) -> Dictionary:
	if u.is_empty(): return {}
	for o in scene._units:
		if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) != str(u.get("side", "")):
			return o
	return {}


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	var s := f.get_as_text()
	f.close()
	return s
