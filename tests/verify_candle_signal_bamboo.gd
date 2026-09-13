extends Node
## verify_candle_signal_bamboo.gd — 037 蛋糕蜡烛 + 038 信号放大器 + 039 竹制弓箭 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 【037】蜡烛在 `CANDLE_PHASES`(3) 个阶段间循环, 每 `CANDLE_IV`(5) 秒切换并触发:
##   熄灭无效果; 微弱阶段携带者在 5 秒内持续回复共(20/30/44 + 0.5/0.7/1.0×攻击力)生命,
##   `CANDLE_HEAL_R`(250) 码内友军各按**半数**持续回复;
##   燃烧阶段对 `CANDLE_BURN_R`(500) 码内所有敌人各造成同额**魔法伤害**并施加 **20/30/40 层灼烧**。
##
## 【038】提供 `ASPD_FLAT`(30)% 攻速; 每次普攻 +1 层放大, 每层 **1/2/5% 增伤** +
##   `ASPD_PER_STACK`(5)% 攻速, 最多 `MAX_STACKS`(20) 层; 每满 `EVERY`(5) 层放一道弧形波,
##   命中 **125/250/500 魔法伤害**并眩晕 `WAVE_STUN`(2.5) 秒; 每释放一次张角 +`ARC_STEP_DEG`(90)°
##   (上限 `ARC_MAX_DEG`(360)°), 并使自己**永久** +**5/7/10** 点魔抗穿透。
##
## 【039】获得 **6/10/15** 次生长充能; 每第 **3** 段普攻消耗 1 次: 射一发竹箭造成
##   (25/30/35 + `BAMBOO_ARROW_MAXHP_PCT`(6)% 自身最大生命)魔法伤害, 命中后绿球飞回携带者 ——
##   **落到身上才结算**: 回复自身 6% 最大生命, 并使自身最大生命**永久 +50/70/90**。
##
## ★★★039 那句「落到身上才结算」原来挂在 `_spawn_bamboo_orb` 的 `tween_method` 末尾,
##   而 tween 走**未钳制的真实 delta, 无头下推不动**(§3.5) ⇒ **回血与永久成长一次都不落**。
##   我第一次全仓扫这条病时只找了 `tween_interval`, **漏了 `tween_method` 这一族** ——
##   重扫之后 039(竹叶生命球) 与 053(散弹枪弹珠) 都在其中, 本轮一起挪到共享原语。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")
const SW := preload("res://scripts/systems/equip/signal_wave_system.gd")

const CANDLE_FLAT := [20.0, 30.0, 44.0]
const CANDLE_COEF := [0.5, 0.7, 1.0]
const CANDLE_BURN := [20, 30, 40]
const BAMBOO_CHARGES := [6, 10, 15]
const BAMBOO_GROW := [50.0, 70.0, 90.0]

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["def"] = 0.0
	u["mr"] = 0.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 037 蛋糕蜡烛 + 038 信号放大器 + 039 竹制弓箭 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ══════════════ 037 蛋糕蜡烛 ══════════════
	_ok("① ★分母: %d 个阶段 / 每 %.0f 秒切 / 回血半径 %.0f 码 / 爆燃半径 %.0f 码 / 友军按 %.1f 折"
		% [ES.CANDLE_PHASES, ES.CANDLE_IV, ES.CANDLE_HEAL_R, ES.CANDLE_BURN_R, ES.CANDLE_ALLY_HALF],
		ES.CANDLE_PHASES == 3 and absf(ES.CANDLE_IV - 5.0) < 0.01
			and absf(ES.CANDLE_HEAL_R - 250.0) < 0.01 and absf(ES.CANDLE_BURN_R - 500.0) < 0.01)

	## ★三个阶段【按顺序循环】: 熄灭(无效果) → 微弱(回血) → 燃烧(伤害)
	_s._units.clear()
	var c1: Dictionary = _mk(500.0, 400.0, "left")
	var ally1: Dictionary = _mk(560.0, 400.0, "left")          # 250 码内
	var far_ally: Dictionary = _mk(1100.0, 400.0, "left")      # 600 码外
	var foe1: Dictionary = _mk(700.0, 400.0, "right")          # 500 码内
	var foe_far: Dictionary = _mk(1300.0, 400.0, "right")      # 800 码外
	for x in [c1, ally1, far_ally, foe1, foe_far]:
		_s._units.append(x)
	var st1: Dictionary = {"candle": 0}
	## 阶段 0 = 熄灭 ⇒ 什么都不该发生
	var hf0: float = float(foe1["hp"])
	_s._equip_sys._eq_candle_tick(c1, 2, st1)
	_ok("① ★★【熄灭】阶段无效果(敌人掉血 %.0f 应 0, 友军没拿到回血速率)"
		% (hf0 - float(foe1["hp"])),
		absf(hf0 - float(foe1["hp"])) < 0.01 and float(ally1.get("candle_hot_rate", 0.0)) == 0.0)
	## 阶段 1 = 微弱 ⇒ 携带者 + 圈内友军拿到持续回血速率, 圈外的不拿
	_s._equip_sys._eq_candle_tick(c1, 2, st1)
	var want_rate: float = (CANDLE_FLAT[2] + float(c1["atk"]) * CANDLE_COEF[2]) / ES.CANDLE_IV
	_ok("② ★★★【微弱】携带者回血速率 %.2f/秒(应 %.2f = (44+1.0×ATK)/%.0f 秒)"
		% [float(c1.get("candle_hot_rate", -1.0)), want_rate, ES.CANDLE_IV],
		absf(float(c1.get("candle_hot_rate", -1.0)) - want_rate) < 0.01)
	_ok("② ★★★圈内(60 码)友军按**半数**(%.2f 应 %.2f)"
		% [float(ally1.get("candle_hot_rate", -1.0)), want_rate * ES.CANDLE_ALLY_HALF],
		absf(float(ally1.get("candle_hot_rate", -1.0)) - want_rate * ES.CANDLE_ALLY_HALF) < 0.01,
		"文案明写「各按半数」")
	_ok("② ★★圈外(600 码 > %.0f)友军**没有**回血(%.2f 应 0)"
		% [ES.CANDLE_HEAL_R, float(far_ally.get("candle_hot_rate", 0.0))],
		float(far_ally.get("candle_hot_rate", 0.0)) == 0.0,
		"挡多了也是错")
	## 阶段 2 = 燃烧 ⇒ 圈内敌人挨魔法伤 + 灼烧层; 圈外不挨
	var h1: float = float(foe1["hp"])
	var h2: float = float(foe_far["hp"])
	_s._equip_sys._eq_candle_tick(c1, 2, st1)
	var d1: float = h1 - float(foe1["hp"])
	_ok("③ ★分母:【燃烧】圈内(200 码)敌人挨打了 %.0f" % d1, d1 > 0.0)
	_ok("③ ★★圈外(800 码 > %.0f)的没挨打(%.0f)" % [ES.CANDLE_BURN_R, h2 - float(foe_far["hp"])],
		absf(h2 - float(foe_far["hp"])) < 0.01)
	_ok("③ ★★★灼烧 %d 层(★3 应 %d)"
		% [int((foe1["dot_stacks"] as Dictionary).get("burn", -1)), CANDLE_BURN[2]],
		int((foe1["dot_stacks"] as Dictionary).get("burn", -1)) == CANDLE_BURN[2])
	## ★伤害是魔法(吃魔抗)
	var hardy: Dictionary = _mk(700.0, 460.0, "right")
	hardy["mr"] = 500.0
	_s._units.append(hardy)
	var hh: float = float(hardy["hp"])
	st1["candle"] = 2
	_s._equip_sys._eq_candle_tick(c1, 2, st1)
	var dh: float = hh - float(hardy["hp"])
	_ok("③ ★★魔抗 500 吃得明显少 ⇒ 是【魔法伤害】(软 %.0f vs 硬 %.0f)" % [d1, dh], dh < d1 * 0.5)

	# ══════════════ 038 信号放大器 ══════════════
	_ok("④ ★分母: 固定攻速 %.0f%% / 每层攻速 %.0f%% / 上限 %d 层 / 每 %d 层放波 / 眩晕 %.1f 秒 / 张角 +%.0f°(上限 %.0f°)"
		% [SW.ASPD_FLAT * 100.0, SW.ASPD_PER_STACK * 100.0, SW.MAX_STACKS, SW.EVERY,
		   SW.WAVE_STUN, SW.ARC_STEP_DEG, SW.ARC_MAX_DEG],
		SW.MAX_STACKS == 20 and SW.EVERY == 5 and absf(SW.ARC_STEP_DEG - 90.0) < 0.01
			and absf(SW.ARC_MAX_DEG - 360.0) < 0.01 and absf(SW.WAVE_STUN - 2.5) < 0.01)
	_s._units.clear()
	var c4: Dictionary = _mk(500.0, 400.0, "left")
	var t4: Dictionary = _mk(700.0, 400.0, "right")
	_s._units.append(c4)
	_s._units.append(t4)
	var sig = _s._equip_sys._sigwave
	var st4: Dictionary = {}
	var pen0: float = float(c4.get("magic_pen", 0.0))
	## 喂 EVERY 次普攻 ⇒ 正好放一次波
	for k in range(SW.EVERY):
		sig.on_hit(c4, t4, 2, st4)
	_ok("④ ★★★满 %d 层放了 %d 次波(应 1 次)" % [SW.EVERY, int(c4.get("_sig_fired_n", 0))],
		int(c4.get("_sig_fired_n", 0)) == 1,
		"同步触发证据 `_sig_fired_n` 是产品自己记的, 不是门禁插的")
	_ok("④ ★★★每放一次 +%.0f 点魔抗穿透(★3), 实测 %.0f → %.0f"
		% [SW.MR_PEN[2], pen0, float(c4.get("magic_pen", 0.0))],
		absf(float(c4.get("magic_pen", 0.0)) - pen0 - SW.MR_PEN[2]) < 0.01,
		"文案: 永久获得 5/7/10 点魔抗穿透")
	_ok("④ ★★张角第一次是 %.0f°(应 %.0f°)" % [float(st4.get("sig_arc_deg", -1.0)), SW.ARC_STEP_DEG],
		absf(float(st4.get("sig_arc_deg", -1.0)) - SW.ARC_STEP_DEG) < 0.01)
	## 再喂 EVERY 次 ⇒ 第二次波, 张角 +90°
	for k in range(SW.EVERY):
		sig.on_hit(c4, t4, 2, st4)
	_ok("④ ★★第二次放波后张角 %.0f°(应 %.0f°)"
		% [float(st4.get("sig_arc_deg", -1.0)), SW.ARC_STEP_DEG * 2.0],
		absf(float(st4.get("sig_arc_deg", -1.0)) - SW.ARC_STEP_DEG * 2.0) < 0.01,
		"文案: 每释放一次张角增加 90 度")
	## ★★★张角封顶。**这一条第一版是恒真式**, 反向验证当场抓到:
	##   层数封顶在 MAX_STACKS(20)、每 EVERY(5) 层放一次 ⇒ **一场最多只放 4 次波**,
	##   4 × 90° = 360° 正好等于 ARC_MAX_DEG —— 把 `minf(ARC_MAX_DEG, …)` 那道闸整个拿掉,
	##   算出来还是 360°, 判据照样绿。要真的测到那道闸, 必须**让第 5 次波发生**。
	##   ⇒ 手动把层数清零再喂一轮(模拟"如果还能再放一次")。
	for k in range(SW.EVERY * 4):
		sig.on_hit(c4, t4, 2, st4)
	_ok("④ ★分母: 一场最多 %d 次波(层数封顶 %d ÷ 每 %d 层) ⇒ 张角走到 %.0f°"
		% [SW.MAX_STACKS / SW.EVERY, SW.MAX_STACKS, SW.EVERY, float(st4.get("sig_arc_deg", -1.0))],
		absf(float(st4.get("sig_arc_deg", -1.0)) - SW.ARC_MAX_DEG) < 0.01)
	st4["sig_stacks"] = 0                      # ★让开层数那道闸, 逼出第 5 次波
	for k in range(SW.EVERY):
		sig.on_hit(c4, t4, 2, st4)
	_ok("④ ★★★第 5 次波之后张角仍封在 %.0f°(实测 %.0f°) —— 这一条测的是 minf 那道闸"
		% [SW.ARC_MAX_DEG, float(st4.get("sig_arc_deg", -1.0))],
		absf(float(st4.get("sig_arc_deg", -1.0)) - SW.ARC_MAX_DEG) < 0.01,
		"拿掉 minf 就会变成 450°")
	_ok("④ ★★层数封顶在 %d 层(实测 %d 层)"
		% [SW.MAX_STACKS, int(st4.get("sig_stacks", -1))],
		int(st4.get("sig_stacks", -1)) <= SW.MAX_STACKS,
		"文案: 最多叠加 20 层")

	# ══════════════ 039 竹制弓箭 ══════════════
	_ok("⑤ ★分母: 回血/伤害的自身最大生命占比 %.0f%%" % (ES.BAMBOO_ARROW_MAXHP_PCT * 100.0),
		absf(ES.BAMBOO_ARROW_MAXHP_PCT - 0.06) < 0.001)
	for si in [0, 1, 2]:
		_s._units.clear()
		var c5: Dictionary = _mk(500.0, 400.0, "left")
		c5["equips"] = [{"id": "p2eq_039", "star": [1, 2, 3][si]}]
		c5["eq_state"] = {}
		_s._units.append(c5)
		_s._equip_sys._stats._eq_apply_one_stats(c5, "p2eq_039", [1, 2, 3][si])
		_ok("⑤ ★★★%d 星起手 %d 次生长充能(应 %d)"
			% [si + 1, int(c5["eq_state"].get("p2eq_039", {}).get("bamboo_charges", -1)), BAMBOO_CHARGES[si]],
			int(c5["eq_state"].get("p2eq_039", {}).get("bamboo_charges", -1)) == BAMBOO_CHARGES[si],
			"充能由 equip_stats_apply 给, 不是门禁喂的")

	## ★★每第 3 段普攻才消耗 1 次充能
	_s._units.clear()
	var c6: Dictionary = _mk(500.0, 400.0, "left")
	c6["equips"] = [{"id": "p2eq_039", "star": 3}]
	c6["eq_state"] = {}
	_s._units.append(c6)
	_s._equip_sys._stats._eq_apply_one_stats(c6, "p2eq_039", 3)
	var foe6: Dictionary = _mk(700.0, 400.0, "right")
	_s._units.append(foe6)
	var ch0: int = int(c6["eq_state"]["p2eq_039"]["bamboo_charges"])
	_s._equip_sys._eq_on_basic_attack(c6, foe6)
	_s._equip_sys._eq_on_basic_attack(c6, foe6)
	_ok("⑥ ★★前两段普攻**不**消耗充能(%d → %d)"
		% [ch0, int(c6["eq_state"]["p2eq_039"]["bamboo_charges"])],
		int(c6["eq_state"]["p2eq_039"]["bamboo_charges"]) == ch0,
		"文案: 每第 3 段普攻消耗 1 次")
	_s._equip_sys._eq_on_basic_attack(c6, foe6)
	_ok("⑥ ★★★第 3 段消耗 1 次(%d → %d)"
		% [ch0, int(c6["eq_state"]["p2eq_039"]["bamboo_charges"])],
		int(c6["eq_state"]["p2eq_039"]["bamboo_charges"]) == ch0 - 1)

	# ── ⑦ ★★★本轮修的那条:「落到身上才结算」真的会落 ─────────────────
	## 改之前它挂在 `_spawn_bamboo_orb` 的 tween 末尾 ⇒ 回血与永久成长一次都不落。
	_s._units.clear()
	_s._equip_tick_sys._bolt_q.clear()
	var c7: Dictionary = _mk(500.0, 400.0, "left")
	c7["hp"] = 50000.0          # 留出回血空间
	_s._units.append(c7)
	## ★★场上必须有个敌人: 共享队列的排空挂在 `_sim_step` 的 `_fight_on` 块里,
	##   只剩我方一个单位时战斗判定已结束 ⇒ 队列永远不排空, 量出来的 0 是**门禁自己的 0**
	##   (033 的台子刚栽过同一个: 携带者一死我方全灭, 小虫站着不动)。
	_s._units.append(_mk(900.0, 400.0, "right"))
	var hp_before: float = float(c7["maxHp"])
	var cur_before: float = float(c7["hp"])
	var grow: float = BAMBOO_GROW[2]
	_s._spawn_bamboo_orb(Vector2(700.0, 400.0), c7["pos"], func() -> void:
		_s._damage._heal(c7, c7["maxHp"] * ES.BAMBOO_ARROW_MAXHP_PCT)
		c7["maxHp"] += grow
		c7["hp"] += grow)
	_ok("⑦ ★分母: 球刚飞出去还没结算(最大生命 %.0f 未变)" % float(c7["maxHp"]),
		absf(float(c7["maxHp"]) - hp_before) < 0.01,
		"文案明写「落到身上才结算」—— 出手那一刻不该结算")
	## 推够飞行时长(常量, 不是我拍的数)
	for _k in range(int(_s.BAMBOO_ORB_FLY * 60.0) + 20):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("⑦ ★★★推 sim 之后**落地结算了**: 最大生命 %.0f → %.0f(永久 +%.0f)"
		% [hp_before, float(c7["maxHp"]), grow],
		absf(float(c7["maxHp"]) - hp_before - grow) < 0.01,
		"若没变: 结算埋在 tween 里而 tween 无头下推不动 —— 就是 §3.5 那条老病")
	_ok("⑦ ★★同一下还回了血(当前生命 %.0f → %.0f)" % [cur_before, float(c7["hp"])],
		float(c7["hp"]) > cur_before + grow,
		"回血与永久成长是同一个回调里的两件事, 断了会一起断")
	_ok("⑦ 共享延时队列已排空", _s._equip_tick_sys._bolt_q.is_empty(),
		"剩 %d 项" % _s._equip_tick_sys._bolt_q.size())

	# ── ⑧ ★★★037 燃烧: 演出范围 = 判定范围 / 爆炸与命中是两件事 ──────
	## 用户 2026-09-13:「没符合实际爆炸范围?」「爆炸和命中是一回事吗我问你, 为什么用相同特效?」
	## 判据落在**真实建出来的精灵**(世界尺寸 + 用的哪张图), 不是读常量算。
	_s._units.clear()
	var c8: Dictionary = _mk(500.0, 400.0, "left")
	c8["equips"] = [{"id": "p2eq_037", "star": 3}]
	c8["eq_state"] = {"p2eq_037": {"candle": 2}}
	_s._units.append(c8)
	var foe8: Dictionary = _mk(760.0, 400.0, "right")   # 260 码, 在 500 码判定圈内
	foe8["no_basic"] = true; foe8["no_move"] = true
	_s._units.append(foe8)
	var n8: int = _s._anim_fx.size()
	var h8: float = float(foe8["hp"])
	_s._equip_sys._eq_candle_tick(c8, 2, c8["eq_state"]["p2eq_037"])
	var burst = null
	var ign = null
	for e8 in _s._anim_fx:
		var sp8 = e8["spr"]
		if not is_instance_valid(sp8) or sp8.texture == null:
			continue
		var rp: String = str(sp8.texture.resource_path)
		if rp.ends_with("candle-fire-burst.png"):
			burst = sp8
		elif rp.ends_with("candle-ignite.png"):
			ign = sp8
	_ok("⑧ ★分母: 燃烧那一下建出了 %d 个帧动画(之前 %d)" % [_s._anim_fx.size() - n8, n8],
		_s._anim_fx.size() - n8 >= 2)
	_ok("⑧ ★★爆炸与命中用的是**两张不同的图**(爆炸 %s / 点燃 %s)"
		% ["有" if burst != null else "无", "有" if ign != null else "无"],
		burst != null and ign != null,
		"上一版两处用同一张表只换缩放 —— 爆炸是蜡烛炸开, 命中是那个敌人被点燃, 不是一回事")
	if burst != null:
		## 世界宽度 = cell texel × pixel_size ÷ WS = 码
		var wy: float = float(_s._vfx.CFIRE_CELL) * float(burst.pixel_size) / _s.WS
		_ok("⑧ ★★★爆炸演出半径 %.0f 码 = 判定半径 %.0f 码(CANDLE_BURN_R)"
			% [wy * 0.5, ES.CANDLE_BURN_R],
			absf(wy * 0.5 - ES.CANDLE_BURN_R) <= 6.0,
			"上一版画成 255.6 码宽 = 判定的四分之一; 判据量的是真实精灵的世界尺寸")
		_ok("⑧ ★整数倍缩放(像素风): pixel_size / 0.0426 = %.2f 应为整数"
			% (float(burst.pixel_size) / 0.0426),
			absf(float(burst.pixel_size) / 0.0426 - round(float(burst.pixel_size) / 0.0426)) < 0.02)
	_ok("⑧ ★★圈内敌人确实挨了魔法伤(掉血 %.0f)" % (h8 - float(foe8["hp"])),
		h8 - float(foe8["hp"]) > 0.0)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 32:
		print("  [FAIL] ★断言只有 %d 条(<32) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 037/038/039" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
