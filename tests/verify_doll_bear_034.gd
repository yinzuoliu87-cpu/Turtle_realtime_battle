extends Node
## verify_doll_bear_034.gd — 034 玩偶小熊【小熊 → 大熊 → 熊掌/冲击波】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「每 `DOLL_IV`(4) 秒派出一只小熊走向最近的敌人, 造成(**1/2/5×攻击力 + 100/210/1000**)
##   物理伤害并将其击飞, 同时携带者 +1 大熊层; 大熊层满 **5/3/1** 层时**装备销毁**,
##   携带者蓄力 `DOLL_CHARGE_SEC`(1.2) 秒后在空位召唤一只大熊
##   (生命 **1600/3000/15000** · 攻击力 **70/120/2000** · 护甲与魔抗各 `BEAR_RESIST`(70)
##    · 攻击速度 `BEAR_ASPD`(0.7)/秒 · 近战)。
##   大熊普攻为熊掌(**1×攻击力物理**)并每次累积 1 层, 满 `BEAR_PAW_STACKS`(2) 层时
##   下一击改为冲击波(射程临时扩至 `BEAR_WAVE_RANGE`(600) 码): 造成
##   `BEAR_WAVE_COEF`(1.5)×攻击力物理伤害, 将命中的敌人击飞并拉回身前
##   `BEAR_WAVE_PULL`(70) 码, 随后层数清零。」
##
## ★★★本轮修的那条: **大熊的熊掌伤害埋在 tween 里** ——
##   `_big_bear_attack` 用 `_reg_tween().tween_interval(0.315)` + `tween_callback(_bear_paw_hit)`,
##   而 tween 走**未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5)
##   ⇒ **大熊的普攻一下都不结算**。大熊是这件 5 费装备的主要输出(★3 攻击力 2000),
##   等于召出来的东西在打空气。现在走共享原语 `EquipTickSystem.schedule`,
##   结算体搬进 `EquipTickSystem._tick_bear_paw_hit`(带 `_tick_` 前缀, 审计跟得到)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ET := preload("res://scripts/systems/equip/equip_tick_system.gd")

const BEAR_HP := [1600.0, 3000.0, 15000.0]
const BEAR_ATK := [70.0, 120.0, 2000.0]
const LAYER_CAP := [5, 3, 1]
const DOLL_FLAT := [100.0, 210.0, 1000.0]
const DOLL_COEF := [1.0, 2.0, 5.0]

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
	u["hp"] = 900000.0
	u["maxHp"] = 900000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["def"] = 0.0
	u["mr"] = 0.0
	return u


func _bears() -> Array:
	var out: Array = []
	for o in _s._units:
		if o.get("is_big_bear", false) and o.get("alive", false):
			out.append(o)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 034 玩偶小熊: 每 %.0f 秒一只小熊 · 满层召大熊 ===" % ET.DOLL_IV)
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	# ── ① ★分母: 文案里那一串常量在代码里是这些 ────────────────────
	_ok("① ★分母: 派熊周期 %.0f 秒 / 蓄力 %.1f 秒 / 熊掌 %d 层出波 / 波射程 %.0f 码 / 波系数 %.1f×ATK / 拉回 %.0f 码"
		% [ET.DOLL_IV, ET.DOLL_CHARGE_SEC, ET.BEAR_PAW_STACKS, ET.BEAR_WAVE_RANGE,
		   ET.BEAR_WAVE_COEF, ET.BEAR_WAVE_PULL],
		absf(ET.DOLL_IV - 4.0) < 0.01 and ET.BEAR_PAW_STACKS == 2
			and absf(ET.BEAR_WAVE_RANGE - 600.0) < 0.01 and absf(ET.BEAR_WAVE_COEF - 1.5) < 0.01
			and absf(ET.BEAR_RESIST - 70.0) < 0.01 and absf(ET.BEAR_ASPD - 0.7) < 0.01)

	# ── ② ★★攒层: 每 DOLL_IV 秒 +1 层; 差一点点还不该加 ─────────────
	_s._units.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	c2["equips"] = [{"id": "p2eq_034", "star": 1}]
	c2["eq_state"] = {"p2eq_034": {"doll_si": 0}}
	_s._units.append(c2)
	_s._units.append(_mk(700.0, 400.0, "right"))
	ets._tick_doll(c2, ET.DOLL_IV - 0.2)
	_ok("② ★分母: 差 0.2 秒时还没派熊(%d 层)"
		% int(c2["eq_state"]["p2eq_034"].get("bear_layers", 0)),
		int(c2["eq_state"]["p2eq_034"].get("bear_layers", 0)) == 0,
		"卡住「每 %.0f 秒」那个数" % ET.DOLL_IV)
	ets._tick_doll(c2, 0.3)
	_ok("② ★★满 %.0f 秒派出一只小熊并 +1 层(实测 %d 层)"
		% [ET.DOLL_IV, int(c2["eq_state"]["p2eq_034"].get("bear_layers", 0))],
		int(c2["eq_state"]["p2eq_034"].get("bear_layers", 0)) == 1)

	# ── ③ ★★★层满 5/3/1 → 装备销毁 + 召出大熊, 属性吃星级 ───────────
	for si in [0, 1, 2]:
		_s._units.clear()
		var c3: Dictionary = _mk(500.0, 400.0, "left")
		c3["equips"] = [{"id": "p2eq_034", "star": [1, 2, 3][si]}]
		c3["eq_state"] = {"p2eq_034": {"doll_si": si}}
		_s._units.append(c3)
		_s._units.append(_mk(700.0, 400.0, "right"))
		## 喂满 cap 个周期
		for _k in range(LAYER_CAP[si]):
			ets._tick_doll(c3, ET.DOLL_IV + 0.01)
		_ok("③ ★★%d 星: 攒到 %d 层就进入蓄力(cap = %d)"
			% [si + 1, int(c3["eq_state"]["p2eq_034"].get("bear_layers", 0)), LAYER_CAP[si]],
			bool(c3["eq_state"]["p2eq_034"].get("bear_charging", false)),
			"文案: 大熊层满 5/3/1 层时装备销毁")
		## 蓄力是 `await _wait_sim(DOLL_CHARGE_SEC)` —— 走**游戏钟**, 推 sim 就能到点。
		## ★★但**必须 await 帧**: `_wait_sim` 内部是 `while _t < t_end: await process_frame`,
		##   只在 for 里连推 `_sim_step` 而不让出帧, 那个协程**永远没机会醒**
		##   ⇒ 大熊一只都召不出来, 而那是**门禁自己的 0** 不是产品的。
		for _k in range(int(ET.DOLL_CHARGE_SEC * 60.0) + 20):
			_s._sim_step(_s.SIM_DT, false, false)
			await get_tree().process_frame
		var bs: Array = _bears()
		if bs.is_empty():
			_ok("③ ★★★%d 星: 蓄力完召出大熊" % [si + 1], false, "一只都没有")
			continue
		var b: Dictionary = bs[0]
		_ok("③ ★★★%d 星大熊: 血 %.0f(应 %.0f) / 攻 %.0f(应 %.0f) / 双抗 %.0f+%.0f(应 %.0f+%.0f) / 攻击间隔 %.4f(应 %.4f)"
			% [si + 1, float(b["maxHp"]), BEAR_HP[si], float(b["atk"]), BEAR_ATK[si],
			   float(b["def"]), float(b["mr"]), ET.BEAR_RESIST, ET.BEAR_RESIST,
			   float(b["atk_interval"]), 1.0 / ET.BEAR_ASPD],
			absf(float(b["maxHp"]) - BEAR_HP[si]) < 1.0 and absf(float(b["atk"]) - BEAR_ATK[si]) < 1.0
				and absf(float(b["def"]) - ET.BEAR_RESIST) < 0.01
				and absf(float(b["mr"]) - ET.BEAR_RESIST) < 0.01
				and absf(float(b["atk_interval"]) - 1.0 / ET.BEAR_ASPD) < 0.001)
		_ok("③ ★★%d 星: 装备已销毁(bear_done)" % [si + 1],
			bool(c3["eq_state"]["p2eq_034"].get("bear_done", false)),
			"文案明写「装备销毁」")
		## ★★★大熊的**体型**: 它叫「大熊」而且是这件 5 费装备攒一整局的产物,
		##   立绘必须明显比龟大。实拍量过: 原来 col_size=48 ⇒ 世界高 1.71 m,
		##   屏幕上只有 36 像素, **比基础龟(~42px)还矮**。
		##   判据落在**世界高度**(= TARGET_BODY_H × col_size / 56)而不是屏幕像素 ——
		##   屏幕像素会随台子的 zoom 变, 世界高度不会(memory [[fb-judge-must-fit-the-shape]])。
		if si == 2 and is_instance_valid(b.get("sprite", null)):
			var bspr = b["sprite"]
			var bh: float = float(bspr.pixel_size) * float(bspr.texture.get_height()) 				/ maxf(1.0, float(bspr.vframes))
			_ok("③ ★★★大熊立绘世界高 %.2f m, 必须 > 龟的 %.2f m × 1.3"
				% [bh, _s.TARGET_BODY_H],
				bh > _s.TARGET_BODY_H * 1.3,
				"叫「大熊」就不能比小龟还矮(改之前 1.71 m = 0.86 个龟高)")

	# ── ④ ★★★本轮修的那条: 大熊熊掌**真的结算**(改之前恒为 0) ─────────
	_s._units.clear()
	ets._bolt_q.clear()
	var c4: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c4)
	var bear: Dictionary = _s._spawn._spawn_summon(c4, "bear", 15000.0, 2000.0,
		{"label": "大熊", "spr_id": "doll-bear", "col_size": 48.0, "hp_w": 36.0, "melee": true,
		 "atk_interval": 1.0 / ET.BEAR_ASPD, "atk_range": ET.BEAR_RANGE})
	_ok("④ ★分母: 大熊建出来了", bear != null)
	if bear != null:
		bear["is_big_bear"] = true
		bear["bear_stacks"] = 0
		bear["bear_star"] = 2
		bear["eq_state"] = {}
		bear["equips"] = []
		## ★★把大熊【自己的普攻】关掉: 它是场上的真单位, 推 sim 时会按 atk_interval 自己挥,
		##   于是「我调了一次 `_big_bear_attack`」实测变成两层、队列里还多一项 ——
		##   那是**门禁自己造的噪声**(memory [[fb-make-the-noise-deterministic]]: 把噪声源关掉再量)。
		bear["no_basic"] = true
		bear["no_move"] = true
		bear["atk_interval"] = 9999.0
		bear["atk_cd"] = 9999.0
		var foe4: Dictionary = _mk(560.0, 400.0, "right")
		_s._units.append(foe4)
		var h4: float = float(foe4["hp"])
		_s._big_bear_attack(bear, foe4)
		_ok("④ ★分母: 挥击刚起手还没结算(掉血 %.0f 应为 0)" % (h4 - float(foe4["hp"])),
			absf(h4 - float(foe4["hp"])) < 0.01,
			"命中延到挥击接触帧(整套时长的 45%%), 不是攻击一开始")
		## 推够接触时刻 + 余量。改之前这里恒为 0(tween 无头下推不动)。
		for _k in range(int(ET.BEAR_PAW_HIT_AT * 60.0) + 20):
			_s._sim_step(_s.SIM_DT, false, false)
		var d4: float = h4 - float(foe4["hp"])
		_ok("④ ★★★推 sim 之后熊掌**确实打出伤害**(实得 %.0f)" % d4, d4 > 0.0,
			"若为 0: 伤害埋在 tween 里而 tween 无头下推不动 —— 大熊在打空气")
		_ok("④ ★★熊掌是 1×攻击力物理(实得 %.0f, 攻击力 %.0f)" % [d4, float(bear["atk"])],
			absf(d4 - float(bear["atk"])) < 2.0,
			"目标双抗为 0, 所以 1×ATK 应原样落地")
		_ok("④ 共享延时队列已排空(没有漏结算的项)", ets._bolt_q.is_empty(),
			"剩 %d 项" % ets._bolt_q.size())

		# ── ⑤ ★★熊掌每次 +1 层, 满 2 层把射程临时扩到 600 ──────────────
		_ok("⑤ ★★一击之后 %d 层(应 1)" % int(bear.get("bear_stacks", -1)),
			int(bear.get("bear_stacks", -1)) == 1)
		_ok("⑤ 此时射程还是近战 %.0f 码" % float(bear.get("atk_range", -1.0)),
			float(bear.get("atk_range", 0.0)) < ET.BEAR_WAVE_RANGE)
		_s._big_bear_attack(bear, foe4)
		_ok("⑤ ★★★满 %d 层 ⇒ 射程临时扩到 %.0f 码(实测 %.0f)"
			% [ET.BEAR_PAW_STACKS, ET.BEAR_WAVE_RANGE, float(bear.get("atk_range", -1.0))],
			absf(float(bear.get("atk_range", 0.0)) - ET.BEAR_WAVE_RANGE) < 0.01,
			"文案: 满 2 层时下一击改为冲击波(射程临时扩至 600 码)")
		for _k in range(int(ET.BEAR_PAW_HIT_AT * 60.0) + 20):
			_s._sim_step(_s.SIM_DT, false, false)
		_ok("⑤ ★★两击之后 %d 层(应 %d)" % [int(bear.get("bear_stacks", -1)), ET.BEAR_PAW_STACKS],
			int(bear.get("bear_stacks", -1)) == ET.BEAR_PAW_STACKS)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 22:
		print("  [FAIL] ★断言只有 %d 条(<22) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 034 玩偶小熊" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
