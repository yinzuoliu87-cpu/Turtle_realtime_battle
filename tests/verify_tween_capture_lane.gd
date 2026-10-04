extends Node
## verify_tween_capture_lane.gd — 演出 tween / 延时回调【捕获的节点先被释放】的场景门禁
##
## ══════════════════════════════════════════════════════════════════════
##  由来(2026-10-04 · tween_capture_audit 台账逐处判那一轮)
## ══════════════════════════════════════════════════════════════════════
## 台账里 47 处「lambda 捕获了可能被释放的节点」逐处读完之后, 结论是:
##   · **换路本身不会炸** —— `_dl_clear_units()` 先把 `_sim_tweens` 全部 kill,
##     再兜底扫 `_world`; 被 kill 的 tween 回调永远不会再被调。(场景①守住这个顺序)
##   · 真会炸的是【两条时钟错开】(memory fb-second-clock-drops-events):
##       - 顿帧: `_step_sim_tweens` 照走, 而 `_pending_shots` / `_wait_sim` 不走
##         ⇒ tween 跑在延时回调前面 ⇒ tween 链先把节点释放了, 延时回调才来取它。(场景②: 财宝风暴)
##       - 时停: 时停前建的 tween 被定格, 而携带者的协程照走
##         ⇒ 协程先把节点释放了, 时停一解除定格的 tween 接着跑。(场景③: 千刃风暴)
##
## ★判据量【引擎真的报了几条】(Logger·Godot 4.5+), 不数我插的标记。
##   「Lambda capture ... freed」是引擎在**调用 lambda 之前**打的, lambda 体里的
##   is_instance_valid 拦不住; 只有挂 Logger 才在脚本里数得到(同 verify_axe_batch10)。
## ★每个场景先用分母断言证明「捕获物已释放、而回调还没跑」这个局面**真的形成了**,
##   否则 0 条报错是空检查。
## ★标签里不许出现报错原文的英文 —— run-tests 的致命正则按原文匹配。
## ★全程手推 sim(`_sim_step`), 顿帧/时停由参数直接给 —— 与机器快慢无关(CLAUDE.md §2 低帧率那节)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


## 数引擎报错的 Logger。lam = 「捕获物已释放」那条; err = 其余一切非警告的报错(SCRIPT ERROR 等)。
class ErrTap extends Logger:
	var lam := 0
	var err := 0
	var probe := 0
	var first := ""
	var mx := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		mx.lock()
		if code.contains("ERRTAP_PROBE_TWCAP") or rationale.contains("ERRTAP_PROBE_TWCAP"):
			probe += 1
		elif error_type != Logger.ERROR_TYPE_WARNING:
			if code.contains("Lambda capture") or rationale.contains("Lambda capture"):
				lam += 1
			else:
				err += 1
			if first == "":
				first = (code + " | " + rationale).substr(0, 160)
		mx.unlock()


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 演出 tween / 延时回调: 捕获物先释放(换路 / 顿帧 / 时停) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	## ★手推 sim: 关掉场景自己的 _process, 顿帧(frozen)与时停(in_ts)由下面直接传参。
	_s.set_process(false)

	await _t_lane_clear()
	await _t_chest_hitstop()
	await _t_sword_timestop()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 捕获物先释放的三种时序都不报错" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ──────────────────────────────── 工具 ────────────────────────────────

func _reset_field() -> void:
	_s._units.clear()
	_s._pending_shots.clear()
	_s._over = false
	_s._hitstop = 0.0
	if not _s._timestop._ts_active.is_empty():
		_s._timestop._end_timestop()


func _mk(id: String, side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = 1.0e8
	u["hp"] = 1.0e8
	_s._units.append(u)
	return u


## 推 n 步 sim。每步之后等一帧 —— queue_free 要到帧末才真的释放。
func _steps(n: int, frozen: bool = false, in_ts: bool = false) -> void:
	for _i in range(n):
		_s._sim_step(_s.SIM_DT, frozen, in_ts)
		await get_tree().process_frame


func _live_tweens() -> int:
	var k := 0
	for tw in _s._sim_tweens:
		if tw != null and tw.is_valid():
			k += 1
	return k


func _world_with_tex(path: String) -> Array:
	var out: Array = []
	if not is_instance_valid(_s._world):
		return out
	for c in _s._world.get_children():
		if c is Sprite3D and not c.is_queued_for_deletion() and (c as Sprite3D).texture != null \
				and str((c as Sprite3D).texture.resource_path) == path:
			out.append(c)
	return out


func _tap_on() -> ErrTap:
	var tap := ErrTap.new()
	OS.add_logger(tap)
	push_warning("ERRTAP_PROBE_TWCAP 门禁自检: 证明 Logger 接得到引擎输出(警告, 不是报错)")
	return tap


func _tap_off(tap: ErrTap, label: String) -> void:
	OS.remove_logger(tap)
	_ok("[%s] ★分母: Logger 真的接得到引擎输出(自检 %d 条)" % [label, tap.probe], tap.probe >= 1)
	_ok("[%s] ★★引擎 0 条「lambda 捕获物已释放」" % label, tap.lam == 0, "%d 条 · 首条: %s" % [tap.lam, tap.first])
	_ok("[%s] ★★引擎 0 条其他报错(脚本报错等)" % label, tap.err == 0, "%d 条 · 首条: %s" % [tap.err, tap.first])


# ──────────────── ① 换路: 台账里的演出全在途时走真入口 _dl_clear_units ────────────────
## 判它们「换路无害」的理由: `_dl_clear_units` 把在途 sim tween 全部 kill 并从 `_sim_tweens` 拿掉,
## 然后才兜底扫 `_world`。(sim tween 一律 paused、只由 `_step_sim_tweens` 按 sim 步喂 ⇒ kill 与
## 「拿掉」任一条都足以让它不再走; 2026-10-04 变异实测: 只删 kill 照样绿, 两条都删 ⇒ 当场上千条报错。)
## 有人把这两条一起删了, 台账里剩下那 31 处有一大半会当场炸 ⇒ 这里守住它。
func _t_lane_clear() -> void:
	print("--- ① 换路(真入口 _dl_clear_units): 演出全在途时清场 ---")
	_reset_field()
	var chest: Dictionary = _mk("chest", "left", Vector2(-260, 0))
	var star: Dictionary = _mk("star", "left", Vector2(-260, 120))
	var candy: Dictionary = _mk("candy", "left", Vector2(-260, -120))
	var sw: Dictionary = _mk("basic", "left", Vector2(-360, 60))
	var foe: Dictionary = _mk("basic", "right", Vector2(160, 0))
	_mk("basic", "right", Vector2(220, 90))
	var tap := _tap_on()
	_s._chest_sys._sk_chest_storm(chest, foe)          # 台账 chest_system:406
	_s._star_sys._sk_star_gravity_warp(star)           # 台账 star_system:151/186/297/314
	_s._star_sys._sk_star_wave(star)                   # 台账 star_system:364/404
	_s._candy_sys._sk_candy_hammer(candy, foe)         # 台账 candy_system:70
	_s._headless_sys._headless_scythe_sweep(chest["pos"], Vector2.RIGHT)   # 台账 headless_system:347/367
	_s._rocket_sys._rocket_smoke_plume(foe["pos"])     # 台账 rocket_system:146
	_s._vfx._play_egg_shatter(foe)                     # 台账 battle_vfx:145
	_s._equip_sys._eq_sword_storm(sw, 1)               # 台账 equip_system:1198(地缝)+ 剑
	await _steps(30)                                    # 0.5 秒: 吸入 / 举锤 / 扫刀 / 地缝都在半路
	var live0: int = _live_tweens()
	var world0: int = _s._world.get_child_count()
	_ok("★分母: 清场这一刻有 %d 条 sim tween 还活着(台账里那些链在半路)" % live0, live0 >= 20)
	_s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	var world1: int = _s._world.get_child_count()
	_ok("★分母: 换路真的把在途演出节点扫掉了(世界子节点 %d → %d)" % [world0, world1], world1 < world0 - 20)
	## 换路之后接着推: 被 kill 的 tween 不该再调回调; 还活着的协程(千刃风暴)回来要自己认得节点没了
	_mk("basic", "left", Vector2(-200, 0))
	_mk("basic", "right", Vector2(200, 0))
	_s._over = false
	await _steps(240)
	_tap_off(tap, "换路")


# ──────────────── ② 顿帧: 财宝风暴的逐跳回调落在底盘释放之后 ────────────────
## 风暴底盘 disc 由 tween 链在 2.1+0.5 秒处释放; 5 跳伤害走 `_pending_shots`, 最后一跳在 2.0 秒。
## 顿帧期间 tween 照走、延时队列不走 ⇒ 一场里累计顿帧 > 0.6 秒, 最后一跳就晚于底盘释放。
## 这里一次给足顿帧(3 秒), 就是把「累计」压成一段。
func _t_chest_hitstop() -> void:
	print("--- ② 顿帧: 财宝风暴逐跳回调 vs 底盘 tween 链 ---")
	_reset_field()
	var chest: Dictionary = _mk("chest", "left", Vector2(-260, 0))
	var foe: Dictionary = _mk("basic", "right", Vector2(120, 0))
	var before: Array = _world_with_tex("res://assets/sprites/vfx/coin-storm-spiral.png")
	var tap := _tap_on()
	_s._chest_sys._sk_chest_storm(chest, foe)
	var discs: Array = []
	for d in _world_with_tex("res://assets/sprites/vfx/coin-storm-spiral.png"):
		if not before.has(d):
			discs.append(d)
	_ok("★分母: 风暴底盘真的建出来了(%d 张)" % discs.size(), discs.size() == 2)
	await _steps(2)                                     # 第 0 跳(delay 0)正常落地
	var hp_a: float = float(foe["hp"])
	await _steps(int(3.0 / _s.SIM_DT), true)            # 顿帧 3 秒: tween 走完并释放底盘, 延时队列一步没动
	var freed := 0
	for d in discs:
		if not is_instance_valid(d):
			freed += 1
	var queued := 0
	for p in _s._pending_shots:
		if is_same(p.get("src"), chest):
			queued += 1
	_ok("★分母: 底盘已被 tween 链释放(%d/%d), 而逐跳回调还排着 %d 条 —— 「捕获物先释放」真的形成" % [freed, discs.size(), queued],
		freed == discs.size() and queued >= 3)
	await _steps(int(2.5 / _s.SIM_DT))                  # 顿帧结束: 剩下几跳落地
	var left := 0
	for p in _s._pending_shots:
		if is_same(p.get("src"), chest):
			left += 1
	_ok("★分母: 剩下的跳真的都跑了(队列余 %d 条)且照样结算伤害(目标掉血 %.0f)" % [left, hp_a - float(foe["hp"])],
		left == 0 and float(foe["hp"]) < hp_a)
	_tap_off(tap, "顿帧·财宝风暴")


# ──────────────── ③ 时停: 千刃风暴「剑长出来」的 tween 被定格, 携带者的协程先把剑飞完释放 ────────────────
func _t_sword_timestop() -> void:
	print("--- ③ 时停: 千刃风暴(携带者协程照走, 定格的 tween 解冻后接着跑) ---")
	_reset_field()
	var sw: Dictionary = _mk("basic", "left", Vector2(-420, 0))
	_mk("basic", "right", Vector2(150, 0))
	var sword_tex := "res://assets/sprites/equip_vfx/sword_up.png"
	var tap := _tap_on()
	_s._equip_sys._eq_sword_storm(sw, 1)
	## 等剑冒出来(地缝 0.45 秒之后)
	var swords: Array = []
	var guard := 0
	while swords.is_empty() and guard < 120:
		await _steps(1)
		guard += 1
		for c in _s._world.get_children():
			if c is Sprite3D and not c.is_queued_for_deletion() and (c as Sprite3D).region_enabled \
					and (c as Sprite3D).texture != null and (c as Sprite3D).texture == _s._equip_sys._sword_up_tex():
				swords.append(c)
	_ok("★分母: 剑冒出来了(%d 把, 第 %d 步)" % [swords.size(), guard], swords.size() >= 3)
	## 剑刚冒头 = 「长出来」那条 tween 刚建好 ⇒ 此刻开时停, 它就被定格
	_s._timestop._ts_charge_casters = [sw]
	_s._timestop._ts_maxstar = 3
	_s._timestop._ts_fire()
	var frozen_n: int = _s._timestop._ts_frozen_tweens.size()
	_ok("★分母: 时停真的开了(携带者 %d 个), 定格了 %d 条 tween" % [_s._timestop._ts_active.size(), frozen_n],
		_s._timestop._ts_active.size() == 1 and frozen_n >= swords.size())
	## 时停里推 5 秒: 携带者的协程 蓄力→转平→飞完→淡出释放
	await _steps(int(5.0 / _s.SIM_DT), false, true)
	var freed := 0
	for x in swords:
		if not is_instance_valid(x):
			freed += 1
	var still := 0
	for tw in _s._timestop._ts_frozen_tweens:
		if tw != null and tw.is_valid():
			still += 1
	_ok("★分母: 剑已被携带者协程释放(%d/%d), 而定格的 tween 还有 %d 条没放完 —— 「捕获物先释放」真的形成" % [freed, swords.size(), still],
		freed == swords.size() and still >= 1)
	_s._timestop._end_timestop()
	await _steps(int(1.0 / _s.SIM_DT))                  # 解冻: 定格的 tween 接着跑完
	_tap_off(tap, "时停·千刃风暴")
