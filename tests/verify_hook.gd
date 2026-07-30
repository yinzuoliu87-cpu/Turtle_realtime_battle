extends Node

## verify_hook.gd — 法术圆盘·钩锁 核心机制门禁 (用户 2026-07-23; 2026-07-24 照锤石Q返工手感)
## 规则(仔细照 Wild Rift 锤石Q): 大师朝方向甩钩(射程600)→ 眩晕4秒(吃韧性)
##   + 4秒内【一段段拽】(非匀速·每0.6s拽一下·每下42码) + 期间受伤×1.25; 命中CD20 / 空放CD只10(返还10)。
##
## ★★2026-07-30 重做成【真 skillshot】。改前是【出手瞬间就判定命中】的假 skillshot:
##   出手那一刻沿方向选定目标, 到点必钩, 飞行期间目标走开/跑出射程/绕背后全无效。
##   而 HOOK_MISSILE_SPD 的注释写着「用户2026-07-26 再−40%: 950→570·更像可躲skillshot」
##   —— 那次降速的意图就是让它可躲, 但判定在出手瞬间, 降速【根本没让它变可躲】。
##   用户 2026-07-30:「lol锤石的Q哪有这么锁的？」
##   现在: 钩头按 delta 逐帧推进(不用 tween → 无头可测), 每帧 HOOK_HIT_R 碰撞检测。
##   ★本门禁 ③ 组的核心是【飞行中走开躲得掉】—— 那是这次改动唯一的行为判据。
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

	var t1 = b._trainer_sys._hook_first_target(L, Vector2(1, 0))
	_ok("★钩锁选中射程内线上最近敌", t1 != null and is_same(t1, near))
	_ok("★钩锁不选敌方大师(点4规则同源)", t1 == null or not is_same(t1, enTr))
	_ok("射程外(>600)不钩", not is_same(b._trainer_sys._hook_first_target(L, Vector2(1, 0)), far))
	_ok("偏离直线(perp>80)不钩", b._trainer_sys._hook_first_target(L, Vector2(0, 1)) == null or not is_same(b._trainer_sys._hook_first_target(L, Vector2(0, 1)), off))
	_ok("身后的敌不钩(along<0)", b._trainer_sys._hook_first_target(L, Vector2(-1, 0)) == null)

	# ═══ ② _hook_grab: 眩晕(吃韧性)+ 拖拽标记 + 受伤放大 + 触发证据 ═══
	var v0 := _mk("right", 300.0, 0.0)
	b._trainer_sys._hook_grab(L, v0)
	_ok("钩住→眩晕4秒(无韧性)", abs(float(v0.get("stun_until", 0.0)) - 4.0) < 0.01, "%.2f" % float(v0.get("stun_until", 0.0)))
	_ok("★钩住→标记4秒拖拽", abs(float(v0.get("_hook_pull_until", 0.0)) - 4.0) < 0.01)
	_ok("★钩住→受伤放大窗口4秒", abs(float(v0.get("hook_vuln_until", 0.0)) - 4.0) < 0.01)
	_ok("拖拽指向施法大师", is_same(v0.get("_hook_pull_by", null), L))
	_ok("同步触发证据 _hooked_by(非tween假断言)", is_same(v0.get("_hooked_by", null), L))
	var vTen := _mk("right", 300.0, 0.0, {"tenacity": 0.5})
	b._trainer_sys._hook_grab(L, vTen)
	_ok("★眩晕吃韧性(0.5韧性→4×0.5=2秒)", abs(float(vTen.get("stun_until", 0.0)) - 2.0) < 0.01, "%.2f" % float(vTen.get("stun_until", 0.0)))

	# ═══ ③ ★真 skillshot: 出手不锁定 / 飞行中能躲 / 空放要飞满才返还 ═══
	# 推进钩子飞行的小工具: 按固定步长喂 delta(delta 制 → 无头也稳, 不依赖 tween)
	var fly := func(bb, t: float) -> void:
		var n := int(t / 0.02)
		for _i in range(n):
			bb._t += 0.02
			bb._trainer_sys._tick_hook_flights(0.02)

	# ── ③-a 出手: 不预选目标, 返回"是否成功放出", CD 立刻进 20 ──
	var L2 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var e2 := _mk("right", 300.0, 0.0)
	b._units = [L2, e2]
	b._t = 0.0
	b._trainer_sys._flights = []
	_ok("★出手→返回true(语义=成功放出, 不再是'将命中')",
		b._trainer_sys._cast_hook(L2, Vector2(1, 0)) == true)
	_ok("★出手即进 CD=20(命中/空放只决定要不要返还)",
		abs(float(L2.get("_active_cd", 0.0)) - 20.0) < 0.01, "%.1f" % float(L2.get("_active_cd", 0.0)))
	_ok("★出手时还没钩到人(不再是出手就判定)", not e2.has("_hooked_by"))
	_ok("★场上多了一个在飞的钩子", b._trainer_sys._flights.size() == 1)
	_ok("CD未好→不能再放(返回false)", b._trainer_sys._cast_hook(L2, Vector2(1, 0)) == false)

	# ── ③-b 站着不动 → 钩子飞到就该钩住 ──
	fly.call(b, 0.35 + 300.0 / 570.0 + 0.10)
	_ok("★站着不动→被钩住(_hooked_by 是那个大师)", is_same(e2.get("_hooked_by", null), L2))
	_ok("★命中后飞行结束(钩子已回收)", b._trainer_sys._flights.is_empty())
	_ok("★命中→提前解除甩钩站定", float(L2.get("_cast_lock_until", 9e9)) <= b._t + 0.001)

	# ── ③-c ★★核心: 出手后【走开】必须躲得掉 ──
	var L4 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var e4 := _mk("right", 300.0, 0.0)
	b._units = [L4, e4]
	b._t = 0.0
	b._trainer_sys._flights = []
	b._trainer_sys._cast_hook(L4, Vector2(1, 0))
	fly.call(b, 0.35 + 0.10)              # 前摇过 + 刚出手一点
	e4["pos"] = Vector2(300.0, 400.0)      # ★目标横向闪开(远超 HOOK_HIT_R=70)
	fly.call(b, 300.0 / 570.0 + 0.60)     # 让钩子飞满射程
	_ok("★★飞行中走开→躲掉了(没有 _hooked_by)", not e4.has("_hooked_by"),
		"实际 %s" % str(e4.get("_hooked_by", null)))
	_ok("★躲掉后按空放返还 CD=10", abs(float(L4.get("_active_cd", 0.0)) - 10.0) < 0.01,
		"%.1f" % float(L4.get("_active_cd", 0.0)))
	_ok("★躲掉后钩子已回收", b._trainer_sys._flights.is_empty())

	# ── ③-d 反过来: 出手时线上没人, 飞行中【走进来】要能钩到 ──
	var L5 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var e5 := _mk("right", 300.0, 500.0)   # 出手时远离钩子路径
	b._units = [L5, e5]
	b._t = 0.0
	b._trainer_sys._flights = []
	b._trainer_sys._cast_hook(L5, Vector2(1, 0))
	fly.call(b, 0.35 + 0.10)
	e5["pos"] = Vector2(260.0, 0.0)        # ★走进钩子路径
	fly.call(b, 300.0 / 570.0 + 0.20)
	_ok("★★出手时不在线上、飞行中走进来→钩得到(旧实现永远钩不到)",
		is_same(e5.get("_hooked_by", null), L5))

	# ── ③-e 空放: 全场无敌 → 要【飞满射程】才返还, 出手那一刻仍是 20 ──
	var L3 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	b._units = [L3]
	b._t = 0.0
	b._trainer_sys._flights = []
	_ok("★空放也返回true(放出去了)", b._trainer_sys._cast_hook(L3, Vector2(1, 0)) == true)
	_ok("★空放【出手瞬间】CD 仍是 20(还没飞完, 不知道会不会中)",
		abs(float(L3.get("_active_cd", 0.0)) - 20.0) < 0.01, "%.1f" % float(L3.get("_active_cd", 0.0)))
	fly.call(b, 0.35 + 600.0 / 570.0 + 0.10)
	_ok("★飞满射程未命中→返还成 CD=10", abs(float(L3.get("_active_cd", 0.0)) - 10.0) < 0.01,
		"%.1f" % float(L3.get("_active_cd", 0.0)))

	# ── ③-f 大师死了 → 在飞的钩子作废 ──
	var L6 := _mk("left", 0.0, 0.0, {"is_trainer": true})
	var e6 := _mk("right", 300.0, 0.0)
	b._units = [L6, e6]
	b._t = 0.0
	b._trainer_sys._flights = []
	b._trainer_sys._cast_hook(L6, Vector2(1, 0))
	L6["alive"] = false
	fly.call(b, 0.35 + 300.0 / 570.0 + 0.10)
	_ok("★大师死了→钩子作废(不会隔着尸体钩人)", not e6.has("_hooked_by"))
	_ok("★大师死了→钩子已回收", b._trainer_sys._flights.is_empty())

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
	# 拽窗口内 _t∈[0,0.2): 快速拽一段 ≈ HOOK_TUG_DIST(70码·用户2026-07-26)
	var d0: float = pulled["pos"].distance_to(Lc["pos"])
	for step in [0.0, 0.03, 0.06, 0.09, 0.12, 0.15, 0.18]:
		b._t = step
		b._trainer_sys._tick_hooks(0.03)
	var d_tug: float = pulled["pos"].distance_to(Lc["pos"])
	_ok("★一下拽≈70码(分段·非匀速)", abs((d0 - d_tug) - 70.0) < 12.0, "拽了 %.1f 码" % (d0 - d_tug))
	_ok("★钩锁CD每帧扣减", float(Lc.get("_active_cd", 0.0)) < 5.0, "%.2f" % float(Lc.get("_active_cd", 0.0)))
	# 停顿期 _t∈[0.2,1.0): 不拽(每秒才拽一下·证明是一段段)
	var d_before: float = pulled["pos"].distance_to(Lc["pos"])
	for step in [0.30, 0.50, 0.75, 0.95]:
		b._t = step
		b._trainer_sys._tick_hooks(0.03)
	var d_after: float = pulled["pos"].distance_to(Lc["pos"])
	_ok("★停顿期不拽(每秒1下·非匀速)", abs(d_before - d_after) < 0.5, "停顿期又移了 %.2f 码" % abs(d_before - d_after))
	# ★共拖4下·每下70=总≈280码(用户2026-07-26"每秒70码共4秒拖4下"): 起点拉远跑满4秒眩晕, 数总位移
	var far_u := _mk("right", 900.0, 300.0, {"_hook_pull_until": 4.0, "_hook_pull_by": Lc, "_hook_tug_t0": 0.0})
	b._units = [Lc, far_u]
	var dfar0: float = far_u["pos"].distance_to(Lc["pos"])
	var tt: float = 0.0
	while tt < 4.0:
		b._t = tt
		b._trainer_sys._tick_hooks(0.03)
		tt += 0.03
	var moved: float = dfar0 - far_u["pos"].distance_to(Lc["pos"])
	_ok("★4秒内共拖4下≈280码(4×70·每秒1下)", moved > 250.0 and moved < 320.0, "4秒共拖 %.0f 码" % moved)

	# ═══ ⑥ 接线证据(分母): Q键 / AI / _process tick / mitigate ═══
	var src: String = ""
	if Battle is GDScript:
		src = (Battle as GDScript).source_code + "
" + FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")   # 2026-07-25: 大师技能已抽到 trainer/
	_ok("★Q键接了 _player_cast_hook", src.contains("_player_cast_hook") and src.contains("KEY_Q"))
	_ok("★sim 主循环挂了 _tick_hooks(2026-07-25 Phase4: 在 _sim_step·_process/累加器调 _sim_step)", src.contains("_tick_hooks(dt)") and src.contains("_sim_step(SIM_DT"))
	_ok("★敌方大师 AI 放主动已接线(_cast_active分派)", src.contains("_tick_trainer_ai") and src.contains("_cast_active(u,"))
	_ok("★装配分派入口 _cast_active 存在", src.contains("func _cast_active") and src.contains('"fury_potion":') and src.contains('"glacier":'))
	_ok("★受伤放大接进 _mitigate_incoming", src.contains("hook_vuln_until"))

	b.free()
	print("ALL PASS — 钩锁核心机制(射程/眩晕/拖拽/受伤/CD/接线)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
