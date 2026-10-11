extends Node
## verify_equip_stun_via_entry.gd —— 038 电磁波 / 056 飞镖的眩晕必须走 `_stun` 唯一入口(2026-10-11 全项目通读第七条)
##
## ★读码疑点: 两处直接写 `stun_until`, 不经 `_stun` ⇒ 无视免控窗口(cc_immune_until: 小将不可阻挡 / 财神投币期)、
##   不吃韧性(tenacity)。系统机制权威 §8: 全部眩晕/冻结走 `_stun`。
## ★判据走产品函数: 免控窗口内被命中 ⇒ stun_until 不涨; 有 50% 韧性 ⇒ 眩晕时长减半。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _pair() -> Array:
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("basic", "left", c)
	var b: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(60, 0))
	b["maxHp"] = 1.0e6
	b["hp"] = 1.0e6
	b["stun_until"] = 0.0
	_s._units.append(a)
	_s._units.append(b)
	_s._over = false
	return [a, b]


## 038: 直接打一发电磁波命中
func _hit038(b_setup: Callable) -> float:
	var ab := _pair()
	b_setup.call(ab[1])
	_s._equip_sys._sigwave._apply(ab[0], ab[1], 10.0)
	return float(ab[1]["stun_until"]) - _s._t


## 056: 带飞镖普攻 DART_EVERY 下
func _hit056(b_setup: Callable) -> float:
	var ab := _pair()
	var a: Dictionary = ab[0]
	a["equips"] = [{"id": "p2eq_056", "star": 1}]
	a["eq_state"] = {}
	b_setup.call(ab[1])
	for i in range(EquipSystem.DART_EVERY):
		_s._equip_sys._eq_on_hit(a, ab[1], 1, true, false)
	return float(ab[1]["stun_until"]) - _s._t


func _ready() -> void:
	await get_tree().process_frame
	print("=== 装备眩晕走 _stun 入口 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._edit_mode = false
	for spec in [["038 电磁波", "_hit038", SignalWaveSystem.WAVE_STUN], ["056 飞镖", "_hit056", EquipSystem.DART_KNOCKUP_SEC]]:
		var fn := Callable(self, str(spec[1]))
		var full: float = fn.call(func(_b): pass)
		_ok("★分母: %s 普通目标被眩晕 ≈ %.1f 秒" % [spec[0], float(spec[2])], absf(full - float(spec[2])) < 0.05, "%.2f 秒" % full)
		var imm: float = fn.call(func(b): b["cc_immune_until"] = _s._t + 99.0)
		_ok("★★%s: 免控窗口内不被眩晕" % spec[0], imm <= 0.001, "%.2f 秒" % imm)
		var ten: float = fn.call(func(b): b["tenacity"] = 0.5)
		_ok("★★%s: 50%% 韧性 ⇒ 眩晕减半" % spec[0], absf(ten - float(spec[2]) * 0.5) < 0.05, "%.2f 秒" % ten)

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
