extends Node

## verify_hook.gd — 法术圆盘·钩锁 核心机制门禁 (用户 2026-07-23; 2026-07-24 照锤石Q返工手感)
## 规则(仔细照 Wild Rift 锤石Q): 大师朝方向甩钩(射程600·线上第一个可选敌)→ 眩晕4秒(吃韧性)
##   + 4秒内【一段段拽】(非匀速·每0.6s拽一下·每下42码) + 期间受伤×1.25; 命中CD20 / 空放CD只10(返还10)。
##   手感: 前摇HOOK_WINDUP + 中速飞行HOOK_MISSILE_SPD + 到达才结算(_pending_shots定时·无头也稳)。
## ★结算全是纯函数(不依赖演出 tween), 直接 .new() 战斗脚本测(照 verify_pirate_hook 教训)。

const Battle := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _mk(side: String, x: float, y: float, extra: Dictionary = {}) -> Dictionary:
	var u := {"side": side, "alive": true, "id": "basic", "pos": Vector2(x, y),
		"maxHp": 1000.0, "hp": 1000.0}
	for k in extra:
		u[k] = extra[k]
	return u

func _ready() -> void:
	var b = Battle.new()
	b._t = 0.0

	# ═══ ① _hook_first_target: 射程600 + 线上 + 不选大师 ═══
	var L := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var near := _mk("right", 300.0, 0.0)     # 正东 300, 在射程+线上 → 该被钩
	var far  := _mk("right", 900.0, 0.0)     # 正东 900 > 600 → 不钩
	var off  := _mk("right", 300.0, 200.0)   # 偏离直线 200 > 带宽80 → 不钩
	var enTr := _mk("right", 200.0, 0.0, {"is_trainer": true})   # 敌方大师(线上更近)→ 定向不选
	b._units = [L, near, far, off, enTr]

	var t1 = b._hook_first_target(L, Vector2(1, 0))
	_ok("★钩锁选中射程内线上最近敌", t1 != null and is_same(t1, near))
	_ok("★钩锁不选敌方大师(点4规则同源)", t1 == null or not is_same(t1, enTr))
	_ok("射程外(>600)不钩", not is_same(b._hook_first_target(L, Vector2(1, 0)), far))
	_ok("偏离直线(perp>80)不钩", b._hook_first_target(L, Vector2(0, 1)) == null or not is_same(b._hook_first_target(L, Vector2(0, 1)), off))
	_ok("身后的敌不钩(along<0)", b._hook_first_target(L, Vector2(-1, 0)) == null)

	# ═══ ② _hook_grab: 眩晕(吃韧性)+ 拖拽标记 + 受伤放大 + 触发证据 ═══
	var v0 := _mk("right", 300.0, 0.0)
	b._hook_grab(L, v0)
	_ok("钩住→眩晕4秒(无韧性)", abs(float(v0.get("stun_until", 0.0)) - 4.0) < 0.01, "%.2f" % float(v0.get("stun_until", 0.0)))
	_ok("★钩住→标记4秒拖拽", abs(float(v0.get("_hook_pull_until", 0.0)) - 4.0) < 0.01)
	_ok("★钩住→受伤放大窗口4秒", abs(float(v0.get("hook_vuln_until", 0.0)) - 4.0) < 0.01)
	_ok("拖拽指向施法大师", is_same(v0.get("_hook_pull_by", null), L))
	_ok("同步触发证据 _hooked_by(非tween假断言)", is_same(v0.get("_hooked_by", null), L))
	var vTen := _mk("right", 300.0, 0.0, {"tenacity": 0.5})
	b._hook_grab(L, vTen)
	_ok("★眩晕吃韧性(0.5韧性→4×0.5=2秒)", abs(float(vTen.get("stun_until", 0.0)) - 2.0) < 0.01, "%.2f" % float(vTen.get("stun_until", 0.0)))

	# ═══ ③ _cast_hook: CD 门 + 命中CD20 / 空放CD10 ═══
	var L2 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var e2 := _mk("right", 300.0, 0.0)
	b._units = [L2, e2]
	_ok("★命中→返回true", b._cast_hook(L2, Vector2(1, 0)) == true)
	_ok("★命中→CD=20", abs(float(L2.get("_active_cd", 0.0)) - 20.0) < 0.01, "%.1f" % float(L2.get("_active_cd", 0.0)))
	_ok("CD未好→不能再放(返回false)", b._cast_hook(L2, Vector2(1, 0)) == false)
	var L3 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	b._units = [L3]   # 场上无敌 → 空放
	_ok("★空放→返回false", b._cast_hook(L3, Vector2(1, 0)) == false)
	_ok("★空放→CD只10(返还10)", abs(float(L3.get("_active_cd", 0.0)) - 10.0) < 0.01, "%.1f" % float(L3.get("_active_cd", 0.0)))

	# ═══ ④ _mitigate_incoming: 被钩4秒内受伤 ×1.25 ═══
	var hv := _mk("right", 0.0, 0.0, {"hook_vuln_until": 5.0})   # _t=0 < 5 → 生效
	_ok("★被钩→受伤×1.25(100→125)", abs(b._mitigate_incoming(hv, 100.0, false, false) - 125.0) < 0.5, "%.1f" % b._mitigate_incoming(hv, 100.0, false, false))
	var nohv := _mk("right", 0.0, 0.0, {"hook_vuln_until": 0.0})
	_ok("未被钩→不放大(100→100)", abs(b._mitigate_incoming(nohv, 100.0, false, false) - 100.0) < 0.5)
	_ok("自损(is_self)不吃放大", abs(b._mitigate_incoming(hv, 100.0, false, true) - 100.0) < 0.5)

	# ═══ ⑤ _tick_hooks: CD扣减 + 被钩单位【一段段】拽(非匀速·锤石口径) ═══
	var Lc := _mk("left", 400.0, 300.0, {"is_trainer": true, "_active_cd": 5.0})
	var pulled := _mk("right", 700.0, 300.0, {"_hook_pull_until": 10.0, "_hook_pull_by": Lc, "_hook_tug_t0": 0.0})
	b._units = [Lc, pulled]
	# 拽窗口内 _t∈[0,0.15): 快速拽一段 ≈ HOOK_TUG_DIST(42码)
	var d0: float = pulled["pos"].distance_to(Lc["pos"])
	for step in [0.0, 0.03, 0.06, 0.09, 0.12]:
		b._t = step
		b._tick_hooks(0.03)
	var d_tug: float = pulled["pos"].distance_to(Lc["pos"])
	_ok("★一下拽≈42码(分段·非匀速)", abs((d0 - d_tug) - 42.0) < 5.0, "拽了 %.1f 码" % (d0 - d_tug))
	_ok("★钩锁CD每帧扣减", float(Lc.get("_active_cd", 0.0)) < 5.0, "%.2f" % float(Lc.get("_active_cd", 0.0)))
	# 停顿期 _t∈[0.15,0.6): 不拽(证明是一段段, 不是匀速)
	var d_before: float = pulled["pos"].distance_to(Lc["pos"])
	for step in [0.18, 0.30, 0.45, 0.58]:
		b._t = step
		b._tick_hooks(0.03)
	var d_after: float = pulled["pos"].distance_to(Lc["pos"])
	_ok("★停顿期不拽(证明非匀速·是一段段)", abs(d_before - d_after) < 0.5, "停顿期又移了 %.2f 码" % abs(d_before - d_after))

	# ═══ ⑥ 接线证据(分母): Q键 / AI / _process tick / mitigate ═══
	var src: String = ""
	if Battle is GDScript:
		src = (Battle as GDScript).source_code
	_ok("★Q键接了 _player_cast_hook", src.contains("_player_cast_hook") and src.contains("KEY_Q"))
	_ok("★_process 挂了 _tick_hooks", src.contains("_tick_hooks(delta)"))
	_ok("★敌方大师 AI 放主动已接线(_cast_active分派)", src.contains("_tick_trainer_ai") and src.contains("_cast_active(u,"))
	_ok("★装配分派入口 _cast_active 存在", src.contains("func _cast_active") and src.contains('"fury_potion":') and src.contains('"glacier":'))
	_ok("★受伤放大接进 _mitigate_incoming", src.contains("hook_vuln_until"))

	b.free()
	print("ALL PASS — 钩锁核心机制(射程/眩晕/拖拽/受伤/CD/接线)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
