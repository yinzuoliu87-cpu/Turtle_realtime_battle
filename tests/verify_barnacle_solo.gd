extends Node
## verify_barnacle_solo.gd —— 021 守护贝母没有可连的友军时不许每帧发一次 buff(2026-10-11 全项目通读 A13)
## ★「首次立即连」的条件是 `link_target == null`; 没友军时 best=null 又写回 null ⇒ 下一帧条件仍成立 ⇒
##   每帧 +10 龟能 +10% 攻速无限叠。另外原来连的是 `_allies_of`(含训龟大师/龟蛋), 应走 `_allies_share_pool`。
## ★判据走产品 tick: 独狼携带者跑 2 秒(< 一个 5 秒周期) ⇒ 攻速只加一次。

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
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c)
	u["equips"] = [{"id": "p2eq_021", "star": 1}]
	u["eq_state"] = {}
	u["aspd_perm"] = 1.0
	s._units.clear()
	s._units.append(u)
	var steps: int = int(round(2.0 / float(s.SIM_DT)))
	for i in range(steps):
		s._equip_tick_sys._tick_barnacle(u, s.SIM_DT)
	var gain: float = float(u["aspd_perm"]) - 1.0
	_ok("★★独狼携带者 2 秒内攻速只加一次(+%.2f), 不是每帧叠" % EquipTickSystem.BARNACLE_ASPD,
		absf(gain - EquipTickSystem.BARNACLE_ASPD) < 1e-4, "2 秒共加 %.2f(%d 步)" % [gain, steps])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
