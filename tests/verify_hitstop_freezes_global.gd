extends Node
## verify_hitstop_freezes_global.gd — 顿帧(hit-stop)期间【全局在途表】与游戏钟一起定格
##
## 用户 2026-10-04 拍板 U9(docs/plans/20260915b-*.md):「也停」。
## 修前: `_sim_step` 里 `_equip_sys.tick_global(dt)` 在 `if frozen:` 分支【之前】无条件跑,
##   游戏钟 `_t` 顿帧里停、全局在途表照走 ⇒ 080 直升机「携带者阵亡后继续飞 10 秒」
##   按游戏钟只过约 6.3 秒就坠机(D6 探针: doom_t 涨 10.000, 其中 3.733 落在游戏钟没动的帧里)。
## 判据走真路径: 直接调 `_s._sim_step(SIM_DT, frozen, false)`, 不经任何复刻。
##   ① 分母: 直升机在场、携带者已阵亡(倒计时该走)
##   ② 分母: 不冻结的 N 步里 doom_t 确实走了 N×SIM_DT(否则下面的「没走」是恒真)
##   ③ 分母: 冻结那 N 步真的进了顿帧分支(_hitstop 被扣掉 N×SIM_DT)且游戏钟没动
##   ④ ★冻结那 N 步里 doom_t 一点没涨、直升机位置一点没动
## 反向验证: 把主循环那行 `if not frozen:` 去掉 ⇒ ④ 红(doom_t 涨 N×SIM_DT)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const N := 30

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", t, ("  " + ex) if ex != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", t, "  ", ex)


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 顿帧期间全局在途表与游戏钟一起停(U9) ===")
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true
	await _wait(40)
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-200, 0))
	var b: Dictionary = _s._spawn._make_unit("stone", "right", c + Vector2(260, 0))
	for u in [a, b]:
		u["no_move"] = true
		u["no_basic"] = true
		u["move_spd"] = 0.0
		u["maxHp"] = 99999.0
		u["hp"] = 99999.0
		_s._units.append(u)
	await _wait(10)
	var gun = _s._equip_sys._gun_sys
	gun._spawn_heli(b, 2, 300.0)
	var h: Dictionary = gun._helis[0] if gun._helis.size() > 0 else {}
	## 携带者「阵亡」: 换成一份不在 _units 里的已死替身 —— 不去杀真单位, 免得触发团灭/换路把场子收掉
	if not h.is_empty():
		h["owner"] = {"alive": false, "side": "right", "pos": Vector2(b["pos"]), "id": "stone"}
	_s.set_process(false)   # 从这里起只由本门禁一步步喂 sim
	_ok("① 分母: 直升机在场且携带者已阵亡", not h.is_empty() and gun._heli_doomed(h),
		"helis=%d" % gun._helis.size())
	if h.is_empty():
		_finish(); return
	var dt: float = float(_s.SIM_DT)

	## ② 不冻结: 倒计时该走
	_s._hitstop = 0.0
	var d0: float = float(h.get("doom_t", 0.0))
	for _i in range(N):
		_s._sim_step(dt, false, false)
	var d1: float = float(h.get("doom_t", 0.0))
	_ok("② 分母: 不冻结 %d 步 doom_t 走了 %d×SIM_DT" % [N, N], absf((d1 - d0) - N * dt) < 1e-4,
		"Δ=%.4f 期望 %.4f" % [d1 - d0, N * dt])

	## ③④ 冻结
	_s._hitstop = 10.0
	var t0: float = float(_s._t)
	var p0: Vector2 = Vector2(h.get("pos", Vector2.ZERO))
	for _i in range(N):
		_s._sim_step(dt, true, false)
	var d2: float = float(h.get("doom_t", 0.0))
	_ok("③ 分母: 冻结 %d 步真的进了顿帧分支(_hitstop 扣掉 %d×SIM_DT)" % [N, N],
		absf((10.0 - float(_s._hitstop)) - N * dt) < 1e-4, "hitstop=%.4f" % float(_s._hitstop))
	_ok("③ 分母: 冻结期间游戏钟 _t 没动", absf(float(_s._t) - t0) < 1e-9, "Δt=%.4f" % (float(_s._t) - t0))
	_ok("④ ★冻结期间 080 倒计时 doom_t 一点没涨(与游戏钟同步)", absf(d2 - d1) < 1e-9,
		"Δdoom=%.4f(修前 = %.4f)" % [d2 - d1, N * dt])
	_ok("④ ★冻结期间直升机位置一点没动", Vector2(h.get("pos", Vector2.ZERO)).distance_to(p0) < 1e-6,
		"Δpos=%.4f" % Vector2(h.get("pos", Vector2.ZERO)).distance_to(p0))
	_finish()


func _finish() -> void:
	print("")
	if _fail == 0 and _n >= 6:
		print("ALL PASS (%d 条)" % _n)
		get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n])
		get_tree().quit(1)
