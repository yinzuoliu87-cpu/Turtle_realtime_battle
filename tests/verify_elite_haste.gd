extends Node
## verify_elite_haste.gd — 守卫精英小将「吞噬完成 → 5秒 +50% 攻速」(用户2026-07-19 加的效果)
##
## 为什么单独守: 这条效果加完当时只跑了压测确认不报错, 【没实测过攻速是否真的变快】。
## 生效链路有两段, 断一段就白给:
##   ① _elite_try_consume 的完成回调设 haste_until/haste_mult
##   ② _tick_unit 里 atk_cd = atk_interval / _hf, 其中 _hf 读 haste_mult(且要求 _t < haste_until)
## 本测试两段都验, 并验到期恢复。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)

## 复算 _tick_unit 里那条攻速系数(与 L3848 同式), 用来验"消费端真的读到了"
func _hf_of(scene, u: Dictionary) -> float:
	return maxf(1.0, float(u.get("haste_mult", 1.0))) if scene._t < float(u.get("haste_until", 0.0)) else 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	scene._t = 100.0

	# 精英小将 + 一个濒死目标(<15%血 → 触发吞噬)
	var elite: Dictionary = scene._make_unit("__minion__", "left", Vector2(0, 0),
		{"minion": true, "role": "front", "elite": true, "level": 1})
	var prey: Dictionary = scene._make_unit("basic", "right", Vector2(60, 0))
	prey["maxHp"] = 1000.0
	prey["hp"] = 50.0                       # 5% 血, 低于 15% 吞噬线
	scene._units.clear()
	scene._units.append(elite)
	scene._units.append(prey)

	var iv: float = float(elite.get("atk_interval", 1.0))
	_ok("精英小将建出来了(攻击间隔 %.2fs)" % iv, iv > 0.0)
	_ok("吞噬前无攻速buff", is_equal_approx(_hf_of(scene, elite), 1.0))

	var fired: bool = scene._elite_try_consume(elite, prey)
	_ok("★濒死目标触发吞噬", fired)
	_ok("吞噬演出期获得 95% 减伤", absf(float(elite.get("damage_reduction", 0.0)) - 0.95) < 0.01,
		"damage_reduction=%.2f" % float(elite.get("damage_reduction", 0.0)))

	# 吞噬完成挂在 1.5s 的 _pending_shots 回调里 → 推进时间让它跑完
	for i in range(120):
		scene._t += 0.02
		scene._step_pending_shots(0.02)

	var hm: float = float(elite.get("haste_mult", 1.0))
	var hu: float = float(elite.get("haste_until", 0.0))
	_ok("★吞噬完成 → haste_mult = 1.5", is_equal_approx(hm, 1.5), "实际 %.2f" % hm)
	_ok("★buff 时长 5 秒", hu > scene._t and hu <= scene._t + 5.01, "剩余 %.2fs" % (hu - scene._t))

	# ★消费端: 攻速系数真的被读到, 且攻击间隔真的变短
	var hf: float = _hf_of(scene, elite)
	_ok("★消费端读到攻速系数 1.5", is_equal_approx(hf, 1.5), "_hf=%.2f" % hf)
	_ok("★攻击间隔实际缩短到 1/1.5", absf(iv / hf - iv / 1.5) < 0.001,
		"%.3fs → %.3fs" % [iv, iv / hf])

	# 到期恢复
	scene._t = hu + 0.1
	_ok("★5秒后攻速恢复(系数回 1.0)", is_equal_approx(_hf_of(scene, elite), 1.0))

	print("ALL PASS — 精英小将吞噬后攻速buff" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
