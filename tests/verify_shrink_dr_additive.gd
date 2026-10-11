extends Node
## verify_shrink_dr_additive.gd —— 缩头的 80% 减伤要「加上去、到点减回来」, 不许抹掉别的减伤(2026-10-11 全项目通读第五条)
##
## ★读码疑点: `_sk_hiding_shrink` 写 `damage_reduction = 0.8`、3 秒后写 `= 0.0` ——
##   而其余来源(011 / 香火石 / 060 水母伞 / 精英)全是 += / -=。缩头期间别的减伤被盖掉,
##   3 秒后更是被清成 0, 永久丢失。
## ★判据: 先挂 0.25 减伤(模拟 011), 放缩头, 推 sim 过 3 秒 ⇒ 必须回到 0.25。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 缩头减伤叠加 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("hiding", "left", c)
	s._units.append(u)
	## 场上要有敌人, 否则 _check_end 当场判胜负 ⇒ _over=true ⇒ 延时队列不再推进(3 秒后的还原永远不跑)
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(900, 0))
	foe["atk"] = 0.0
	s._units.append(foe)
	s._edit_mode = false
	s._over = false
	u["damage_reduction"] = 0.25
	s._hiding_sys._sk_hiding_shrink(u)
	var during: float = float(u.get("damage_reduction", 0.0))
	_ok("★缩头期间: 原有 0.25 + 缩头 %.2f 都在" % HidingSystem.SHRINK_DR,
		absf(during - (0.25 + HidingSystem.SHRINK_DR)) < 1e-4, "damage_reduction = %.3f" % during)
	var steps: int = int(round(3.3 / float(s.SIM_DT)))
	for i in range(steps):
		s._sim_step(s.SIM_DT, false, false)
	var after: float = float(u.get("damage_reduction", 0.0))
	_ok("★★缩头结束(3 秒后): 回到原来的 0.25, 不是 0", absf(after - 0.25) < 1e-4, "damage_reduction = %.3f" % after)

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
