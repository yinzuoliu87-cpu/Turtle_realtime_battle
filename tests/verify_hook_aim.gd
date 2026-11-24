extends Node
## verify_hook_aim.gd —— 训龟大师钩锁 AI 瞄准(2026-11-24, RULES_VER 9)。
## 用户 11-24:「锁链的话，目前来说，特效应该没什么要动的，现在只是准头问题，它有的时候乱丢啊，这个瞄准目标。」
## 探针 tests/probes/_probe_hook_aim(双方都装钩锁, 打完整局数每一钩): 3 局 25 钩 = 钩中瞄的 13 / 钩中别人 4 / 落空 8。根因:
##   ① 选靶名单 _trainer_targets 没排「围栏没破的龟蛋」, 钩头碰撞名单 _pick_enemies_of 排了 ⇒ 11 钩瞄蛋, 横穿全场碰不到
##   ② 瞄目标出手那一刻的位置, 走动的目标飞到时已不在
## 改后 6 局 45 钩: 钩中瞄的 40(89%)。
## 判据(直接 new 战斗脚本、手搭单位, 同 verify_hook; 钩头按 delta 推进、每步碰撞, 不靠 tween):
##   ① ★选靶: 围栏没破 / 已破的龟蛋都不选(抽 50 次); 分母: 旧名单 _trainer_targets 里确实有那颗蛋
##   ② 提前量: 这一步在走 ⇒ 落点 = 位置 + 位移速度 × (前摇 + 距离 / 钩速); 这一步没动(哪怕画面用的 vel 留着旧值)⇒ 原位
##   ③ ★端到端: 目标横着走, 按 _ai_aim 甩 ⇒ 钩中它; 分母: 瞄原位甩 ⇒ 落空(证明提前量真起作用)
## 反向验证(11-24): _random_hook_target 去掉「不选龟蛋」⇒ ① 红; _hook_lead 恒返回原位 ⇒ ② ③ 红; _hook_lead 改读 vel ⇒ ②「没动」红。

const Battle := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, x: float, y: float, extra: Dictionary = {}) -> Dictionary:
	var u := {"side": side, "alive": true, "id": "basic", "pos": Vector2(x, y), "maxHp": 1000.0, "hp": 1000.0}
	for k in extra:
		u[k] = extra[k]
	return u


## 钩头飞 t 秒(每步 0.02 秒), 目标照它的 vel 匀速走; 返回被钩住的单位(没钩住 = null)。
func _fly(b, tgt: Dictionary, t: float):
	for _i in range(int(t / 0.02)):
		b._t += 0.02
		tgt["pos"] = (tgt["pos"] as Vector2) + (tgt["vel"] as Vector2) * 0.02
		b._trainer_sys._track_motion(0.02)
		b._trainer_sys._tick_hook_flights(0.02)
		if tgt.has("_hooked_by"):
			return tgt
	return null


func _ready() -> void:
	print("=== 训龟大师钩锁 AI 瞄准 ===")
	var b = Battle.new()
	b._t = 10.0
	## ── ① 选靶不选龟蛋 ──
	var L := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var egg_f := _mk("right", 300.0, 0.0, {"id": "__egg__", "_isEgg": true, "_egg_fence": true})
	var egg_o := _mk("right", 350.0, 80.0, {"id": "__egg__", "_isEgg": true})
	var foe := _mk("right", 500.0, 120.0)
	b._units = [L, egg_f, egg_o, foe]
	var old_pool: Array = b._targeting._trainer_targets(L)
	var had_egg := false
	for o in old_pool:
		if is_same(o, egg_f):
			had_egg = true
	_ok("分母: 旧选靶名单 _trainer_targets 里有围栏没破的龟蛋(这就是原来乱丢的来源)", had_egg, "名单 %d 个" % old_pool.size())
	var picked_egg := 0
	var picked_foe := 0
	for _i in 50:
		var t = b._targeting._random_hook_target(L)
		if t != null and bool((t as Dictionary).get("_isEgg", false)):
			picked_egg += 1
		elif t != null and is_same(t, foe):
			picked_foe += 1
	_ok("① ★抽 50 次: 龟蛋(围栏没破 / 已破)一次都不选, 都选那只龟", picked_egg == 0 and picked_foe == 50, "蛋 %d / 龟 %d" % [picked_egg, picked_foe])
	b._units = [L, egg_f, egg_o]
	_ok("① 射程内只剩龟蛋 ⇒ 不放(返回 null)", b._targeting._random_hook_target(L) == null)
	## ── ② 提前量 ──
	## 位移速度由 _track_motion 记: 上一步在 (1000, -2), 这一步 (1000, 0), dt 0.02 ⇒ 100 码/秒朝下
	var mv := _mk("right", 1000.0, -2.0)
	b._units = [L, mv]
	b._trainer_sys._track_motion(0.02)
	mv["pos"] = Vector2(1000.0, 0.0)
	b._trainer_sys._track_motion(0.02)
	var p_lead: Vector2 = b._trainer_sys._hook_lead(L, mv)
	var t0: float = b.HOOK_WINDUP + 1000.0 / b.HOOK_MISSILE_SPD
	var p1: Vector2 = Vector2(1000.0, 100.0 * t0)
	var t1: float = b.HOOK_WINDUP + p1.length() / b.HOOK_MISSILE_SPD
	var want: Vector2 = Vector2(1000.0, 100.0 * t1)
	_ok("② 刚在走 ⇒ 瞄它飞到时的位置(前摇 + 距离 / 钩速, 迭代一次)", p_lead.distance_to(want) < 0.5, "%s vs %s" % [str(p_lead), str(want)])
	mv["vel"] = Vector2(0.0, 100.0)               # 画面用的 vel 留着旧值(停下不清零)——提前量不该读它
	b._trainer_sys._track_motion(0.02)             # 这一步没动
	var p_stale: Vector2 = b._trainer_sys._hook_lead(L, mv)
	_ok("② 这一步没动(哪怕 vel 还留着旧值)⇒ 瞄原位", p_stale.distance_to(Vector2(1000.0, 0.0)) < 0.01, str(p_stale))
	## ── ③ 端到端: 横着走的目标 ──
	for lead in [true, false]:
		var L3 := _mk("left", 0.0, 0.0, {"is_trainer": true, "_tr_active": "hook"})
		var m3 := _mk("right", 1000.0, -152.0, {"vel": Vector2(0.0, 100.0)})
		b._units = [L3, m3]
		b._trainer_sys._track_motion(0.02)
		m3["pos"] = Vector2(1000.0, -150.0)
		b._trainer_sys._track_motion(0.02)   # 已经在走: 100 码/秒朝下
		b._trainer_sys._flights = []
		var aim: Vector2 = (b._trainer_sys._ai_aim(L3) as Vector2) if lead else (m3["pos"] as Vector2) - (L3["pos"] as Vector2)
		b._trainer_sys._cast_hook(L3, aim)
		var got = _fly(b, m3, b.HOOK_WINDUP + b.HOOK_RANGE / b.HOOK_MISSILE_SPD + 0.2)
		if lead:
			_ok("③ ★按 _ai_aim(带提前量)甩 ⇒ 钩中横着走的目标", got != null and is_same(got, m3), "钩住=%s" % str(got != null))
		else:
			_ok("③ 分母: 瞄它出手时的位置甩 ⇒ 落空(钩子飞到时它已走开 %.0f 码)" % (100.0 * (b.HOOK_WINDUP + 1000.0 / b.HOOK_MISSILE_SPD)),
				got == null)
	b.free()
	print("ALL PASS (%d)" % _n if _fail == 0 else "FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
