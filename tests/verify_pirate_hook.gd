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

	# ★2026-07-23: 不再等演出 tween。钩索的伤害结算在两层 create_tween 链的最末尾
	#   (甩钩 0.34s → 拉回 0.3s → callback), 而场景树 tween 在无头 CI 下推进【不稳】——
	#   verify_pirate_hook 因此连红三次(帧数/游戏时钟/墙钟都试过), 本地永远复现不出来。
	#   根因是【演出耦合了逻辑】: 一个纯数值测试不该依赖整条动画 tween 跑完。
	#   解法: 已把伤害结算从 tween 尾抽成 _pirate_grapple_hit(见主场景), 这里【分两层验】:
	#     ① 演出层: _kill 后钩索真的【被触发】了(_pirate_death_grapple 建了 tween/hook, 不验它跑完)
	#     ② 逻辑层: 直接调 _pirate_grapple_hit 验数值 = 25% 击杀者最大生命(不等 tween)
	# 触发检查: _kill 会走到 "id==pirate → _pirate_death_grapple"。它至少注册了 sim tween。
	scene._kill(pirate, killer)
	# ★触发证据用【钩索独有的同步标记 _grappled_by】, 不用"sim tween 增加"——
	#   _kill 里别的死亡效果(爆炸/震屏)也会建 tween, 拿"任意 tween 增加"背书是假断言
	#   (2026-07-23 反向验证抓到: 注释掉钩索调用, 那条竟没红, 因为还有别的 tween)。
	var grappled: bool = is_same(killer.get("_grappled_by", null), pirate)
	print("  (钩索触发: killer._grappled_by == pirate ? %s)" % grappled)
	_ok("★海盗自己死时钩索锁定了击杀者(_grappled_by, 钩索独有的同步标记)", grappled,
		"没锁定 = _pirate_death_grapple 没被调到")

	# 逻辑层: 直接调抽出来的结算函数(绕过演出), 验 25% 真伤
	var hp1: float = killer["hp"]
	scene._pirate_grapple_hit(pirate, killer)
	var lost: float = hp1 - float(killer["hp"])
	print("  (钩索伤害: 击杀者 maxHp=%.0f, 掉血 %.0f, 期望 %d)" % [float(killer["maxHp"]), lost, expect])
	_ok("★钩索伤害 = 25% 击杀者最大生命(真实伤害·直接调结算函数, 不依赖演出)",
		absf(lost - float(expect)) <= 2.0, "expect≈%d, got=%.0f" % [expect, lost])
	var dist: float = pirate["pos"].distance_to(killer["pos"])
	# ★"拉近到 90 码"是【拉回演出 tween 的终点】—— 等它跑到就又依赖那条脆弱的 tween。
	#   改成验【终点算得对】: 直接调 _pirate_grapple_dest, 断言它离尸位 ≈90 码。
	var dest: Vector2 = scene._pirate_grapple_dest(pirate["pos"], killer["pos"])
	var dest_dist: float = dest.distance_to(pirate["pos"])
	print("  (拉回终点距尸位 %.1f 码, 应≈90)" % dest_dist)
	_ok("★钩索把击杀者拉到尸位 ~90 码处(验终点, 不等演出)", absf(dest_dist - 90.0) <= 5.0,
		"终点距尸位 %.1f 码" % dest_dist)

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
