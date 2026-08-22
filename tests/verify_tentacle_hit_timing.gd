extends Node
## verify_tentacle_hit_timing.gd — 灵物触手【什么时候算命中】(2026-08-10 · 方案 A)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-10「触手有个明显问题, 什么时候算命中, 是拍下去打到目标啊」
## ══════════════════════════════════════════════════════════════════
## 改之前 `_slap()` 把伤害**全部结算完**才调 `strike()` 起演出。而正常拍击要走
##   预警 `T_WARN` 1.00s → 前摇 `T_REAR` 0.13s → `ST_SLAM` 第一帧爆闪(= 视觉命中)
## ⇒ **伤害比视觉命中早 1.13 秒**。两个后果:
##   ① 预警圈彻底成摆设 —— 伤害在预警**开始之前**就结算, 玩家走开也没用;
##   ② 打击名单用的是 1.13 秒前的站位。近战 95~120 码/秒 ⇒ 能走 107~136 码,
##      而伤害带半宽只有 120 码 ⇒ **画面上在带子外的挨打、站带子里的没挨打**。
##
## 用户拍板**方案 A**: 方向/带子在 t=0 定死(预警画的就是它), 但**吃伤害的名单
## 在【视觉命中那一刻】重算** —— 这样"看到预警走开"真的有用。
##
## ★这条门禁守三件事(缺一条前两条就可能是假绿):
##   ① 伤害**不在 t=0** 发生
##   ② 伤害在 `hit_delay()` 那一刻发生
##   ③ **t=0 在带子里、命中前走出去的敌人不挨打** ← 方案 A 的全部意义
##
## ★不用 tween、不等帧: `tick(dt)` 是同步的, 喂多少推进多少 ⇒ 确定性。
##
## ★★2026-08-22 机制变更: 伤害原来走 `_queue_shots` 这条**独立的第二时钟**, 到点再用
##   `is_striking()` 复核。那条路余量只有 0.15 秒、且时停时与演出冻结规则不同 ⇒
##   探针实测一场里 13% 的拍击【完整演出、零伤害】(用户 2026-08-22 报的正是这个)。
##   现在伤害挂在触手自己的"梢端触地"一次性标志上(与爆闪同一个)。
##   ⇒ 本用例的**判据一个字没改**(还是"t=0 不掉血 / 命中前 0.05 秒不掉血 /
##     推过去必须掉血 / 走出带子不挨打 / 撤回后不出伤"),
##     只把【推进时间的手柄】从 `_step_pending_shots` 换成 `tv.tick` —— 换的是尺子的握法,
##     不是尺子的刻度。
##   (CLAUDE.md §3.5: 测数值的用例不该依赖任何动画跑完。)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_hit_timing.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s
var _n := 0
var _fail := 0


## 把触手自己的时钟推进 sec 秒(小步喂 —— 状态机要逐段切换, 一大步会跳过 WARN→REAR→SLAM)
func _adv(sec: float) -> void:
	var n: int = maxi(1, int(ceil(sec / 0.01)))
	var h: float = sec / float(n)
	for _i in range(n):
		_s._tentacle_vfx.tick(h)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _dummy(side: String, p: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, p)
	u["alive"] = true
	u["pos"] = p
	u["hp"] = 999999.0
	u["maxHp"] = 999999.0
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	_s._units.append(u)
	return u


## 真正的灵物携带者（`_side_tier` 遍历本方单位算档，直写 `_by_side` 会得到假 PASS）
func _carrier(side: String, p: Vector2) -> Dictionary:
	var eq: Array = []
	for e in DataRegistry.phase2_equipment:
		if _s.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "灵物":
			eq.append({"id": str((e as Dictionary)["id"]), "star": 1})
		if eq.size() >= 5:
			break
	var u: Dictionary = _dummy(side, p)
	u["equips"] = eq
	u["eq_state"] = {}
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return u


## 让触手真的站稳（ST_EMERGE / ST_RETRACT 期间 `strike()` 直接 return）
func _stand_up(side: String, idx: int) -> void:
	_s._tentacle_vfx.ensure_forced(side, idx + 1)
	for _e in range(30):
		_s._tentacle_vfx.tick(0.12)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 什么时候算命中 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	if _s == null:
		print("  [FAIL] ⓪ 战场没建起来"); print("FAIL x1"); get_tree().quit(1); return
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var syn = _s._spirit_syn
	var tv = _s._tentacle_vfx

	# ── ⓪ 分母: 延迟必须 > 0, 否则下面全是空检查 ──────────────────
	var delay: float = tv.hit_delay(1.0)
	_ok("⓪ ★分母: 正常拍击的视觉命中延迟 = T_WARN + T_REAR = %.2f 秒" % delay,
		delay > 0.5, "delay=%.3f" % delay)
	_ok("⓪ 闪避追击(点刺)延迟 = 0 —— 它本来就是同帧, 不该被改",
		tv.hit_delay(0.25) == 0.0, "%.3f" % tv.hit_delay(0.25))

	var base := Vector2(_s.ARENA.position.x + 200.0,
		_s.ARENA.position.y + _s.ARENA.size.y * 0.5)
	_carrier("left", base)
	_ok("⓪ ★分母: 灵物档位 > 0", syn._side_tier("left") > 0,
		"档=%d" % syn._side_tier("left"))
	_stand_up("left", 0)
	var origin: Vector2 = syn.tentacle_pos("left", 0)

	# ══════════════════════════════════════════════════════════
	#  ① 伤害【不在 t=0】发生, 且在 hit_delay 那一刻发生
	# ══════════════════════════════════════════════════════════
	print("── ① 伤害必须等到触手真的拍到 ──")
	var tgt := _dummy("right", origin + Vector2(200.0, 0.0))
	var hp0: float = float(tgt["hp"])
	syn._slap("left", 0, 1.0)
	_ok("① ★★调完 _slap 的那一刻【不许】掉血(改之前就是这里直接扣完的)",
		absf(float(tgt["hp"]) - hp0) < 0.01,
		"hp %.0f → %.0f" % [hp0, float(tgt["hp"])])

	# 推到命中前一点点 —— 仍然不该掉血
	_adv(delay - 0.05)
	_ok("① ★命中前 0.05 秒仍然不掉血(证明不是随便延一点而是卡在那一刻)",
		absf(float(tgt["hp"]) - hp0) < 0.01,
		"hp %.0f" % float(tgt["hp"]))

	# 再推过去 —— 必须掉血
	_adv(0.10)
	_ok("① ★★推过 hit_delay 之后【必须】掉血",
		float(tgt["hp"]) < hp0 - 0.5,
		"hp %.0f → %.0f" % [hp0, float(tgt["hp"])])

	# ══════════════════════════════════════════════════════════
	#  ② 方案 A 的全部意义: 命中前走出带子的敌人【不该】挨打
	# ══════════════════════════════════════════════════════════
	print("── ② 预警期间走开就该躲掉(方案 A) ──")
	for u in _s._units.duplicate():
		if str(u.get("side", "")) == "right":
			_s._units.erase(u)
	# 选靶目标(定 dir = +X), 它自己不动 —— 保证带子方向稳定
	var anchor := _dummy("right", origin + Vector2(200.0, 0.0))
	# 这个一开始在带子里(横向 0 < 120)
	var runner := _dummy("right", origin + Vector2(320.0, 0.0))
	var r_hp0: float = float(runner["hp"])
	syn._slap("left", 0, 1.0)
	# ★t=0 时它确实在带子里 —— 不先证明这一点, 下面"没挨打"可能只是因为它本来就在外面
	_ok("② ★分母: t=0 时它确实在带子里",
		absf((Vector2(runner["pos"]) - origin).cross(Vector2.RIGHT)) < syn.HIT_HALF_W,
		"横向 %.0f < %.0f" % [absf((Vector2(runner["pos"]) - origin).cross(Vector2.RIGHT)), syn.HIT_HALF_W])
	# 预警期间它走开(横向拉到半宽之外)
	runner["pos"] = origin + Vector2(320.0, syn.HIT_HALF_W * 2.0)
	_adv(delay + 0.05)
	_ok("② ★★预警期间走出带子 ⇒ 不挨打(这一条就是方案 A 的全部意义)",
		absf(float(runner["hp"]) - r_hp0) < 0.01,
		"hp %.0f → %.0f" % [r_hp0, float(runner["hp"])])
	_ok("② ★分母: 没走的那个照样挨打(不然上一条可能只是整发拍击都没结算)",
		float(anchor["hp"]) < 999999.0 - 0.5,
		"anchor hp %.0f" % float(anchor["hp"]))

	# ══════════════════════════════════════════════════════════
	#  ③ 触手被撤回后, 在途的那一击不该再出伤
	# ══════════════════════════════════════════════════════════
	print("── ③ 撤回后在途的伤害要作废 ──")
	for u in _s._units.duplicate():
		if str(u.get("side", "")) == "right":
			_s._units.erase(u)
	var ghost := _dummy("right", origin + Vector2(200.0, 0.0))
	var g_hp0: float = float(ghost["hp"])
	syn._slap("left", 0, 1.0)
	tv.ensure_forced("left", 0)          # 档掉到 0 ⇒ 触手撤回
	_adv(delay + 0.05)
	_ok("③ ★触手撤回后, 在途那一击不再出伤(否则触手都没了还打人)",
		absf(float(ghost["hp"]) - g_hp0) < 0.01,
		"hp %.0f → %.0f" % [g_hp0, float(ghost["hp"])])

	# ══════════════════════════════════════════════════════════
	#  ④ 场上只剩【打不着的】敌人(未破壳的蛋 / 组装中的机甲):
	#     不许空烧拍击层数, 也不许当作"射程内有敌人"
	# ══════════════════════════════════════════════════════════
	## 用户 2026-08-22:「这触手很多时候该攻击的时候又不攻击, 比如机甲, 龟蛋破蛋」。
	## 【病根】判断"射程内有没有敌人"是手写的 `alive + 阵营`, 而 `_slap` 选靶走
	##   `_pick_enemies_of_side`(§PICK-TARGET: 排除围栏未破的蛋、机甲 5 秒组装期、训龟大师)。
	##   两个谓词不一样 ⇒ 只剩这两种敌人时: 前者说"有敌人"⇒ tick 扣层并调 `_slap`,
	##   `_slap` 拿到空名单直接 return 0 ⇒ 一下没打; `_reloc_tick` 也因"有敌人"而不搬家。
	##   ⇒ 触手杵在原地, 一边空烧层数一边什么都不做。
	print("── ④ 只剩打不着的敌人: 不空烧层数 ──")
	for u in _s._units.duplicate():
		if str(u.get("side", "")) == "right":
			_s._units.erase(u)
	var egg := _dummy("right", origin + Vector2(200.0, 0.0))
	egg["_egg_fence"] = true                     # 围栏未破: 可以被 AoE 波及, 但不可被主动索敌
	## ★分母①: 它确实在射程内 —— 不先证明这点, 下面"没打"可能只是因为它站太远
	_ok("④ ★分母: 蛋就在触手射程内",
		origin.distance_to(Vector2(egg["pos"])) <= float(tv.attack_range_2d),
		"距离 %.0f ≤ 射程 %.0f" % [origin.distance_to(Vector2(egg["pos"])), float(tv.attack_range_2d)])
	## ★分母②: 它确实【打不着】(闸门真的把它排除了), 否则这条用例测的是别的东西
	var pickable := false
	for f in _s._targeting._pick_enemies_of_side("left"):
		if is_same(f, egg):
			pickable = true
	_ok("④ ★分母: 蛋确实被选靶闸门排除(不可主动索敌)", not pickable)
	## 攒一层再 tick —— 修之前这一层会被吃掉
	syn._stacks[syn._sk("left", 0)] = 1
	_stand_up("left", 0)
	syn.tick(0.05)
	_ok("④ ★★只剩打不着的敌人时【不许扣层】(修之前: 层数没了、一下也没打)",
		syn.stack_of("left", 0) == 1, "剩 %d 层" % syn.stack_of("left", 0))
	_ok("④ ★★也不算作\"射程内有敌人\"(否则触手永远不会搬家去够得着的地方)",
		not syn._foe_in_range("left", 0))
	## ★★④b 搬家挑的目标也必须是【打得着的】。
	##   我第一版只修了 `_foe_in_range`, 漏了 `_reloc_tick` 里那份手写名单 ⇒
	##   触手会搬到蛋旁边、到了发现打不着、再搬 —— **反复搬家却永远不打**。
	##   同一个问题在三处各写一遍(在范围内/选靶/搬家)就是这个下场。
	##   判据: 全场只有一个打不着的蛋时, 连续推进 3 秒(RELOC_IDLE_T=1.0, 足够触发多次),
	##   触手的位置**不许**被搬到蛋附近。
	var pos_before: Vector2 = syn.tentacle_pos("left", 0)
	## ⚠ 必须**同时推进演出时钟**: `relocate()` 只是【发起】搬家(状态转 ST_RETRACT),
	##   位置要等撤回→再破土那套动作走完才变。第一版只调 `_reloc_tick` 不推 `tv.tick`,
	##   于是坐标永远不动 —— 反向验证时把坏代码也判成了绿(memory [[fb-gate-subject-never-constructed]]:
	##   判据没错, 被测的那件事根本没发生)。
	for _r in range(80):
		syn._reloc_tick(0.05)
		_adv(0.05)
	## ⚠ 判据是「**动没动**」不是「有没有靠近蛋」—— 第一版我写成"靠近蛋"就红不了:
	##   搬家公式是"退到距目标 0.70×射程处", 蛋在 200 码而 0.70×400=280 ⇒ 它其实是
	##   **搬离**蛋的(200→280)。判据比现象宽一格就抓不住(memory [[fb-judge-must-fit-the-shape]])。
	##   真正的病是"为一个打不着的敌人搬了家"——搬完还是打不着, 下一轮接着搬。
	var moved: float = syn.tentacle_pos("left", 0).distance_to(pos_before)
	_ok("④b ★★不许为了一个打不着的蛋搬家(搬完照样打不着, 会一直搬)",
		moved < 1.0 and int(tv.state_of("left", 0)) == 1,
		"位移 %.1f 码 · 状态 %d(1=一直待机, 变了就是发起过搬家)" % [moved, int(tv.state_of("left", 0))])

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 触手命中时刻" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
