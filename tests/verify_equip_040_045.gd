extends Node
## verify_equip_040_045.gd — 040 FPGA板 / 041 退潮浊液 / 042 涟漪药剂 /
##                            043 海浪护符 / 044 深海项链 / 045 地狱护盾 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 【040】每 `FPGA_IV`(6) 秒随机抽 `FPGA_PICKS`(1/2/4) 个 2-bit 状态(可重复):
##   00 = 回复 5% 最大生命 + 累计 +12 双抗; 01 = 累计 +15 攻击力与 +7% 生命偷取;
##   10 = `FPGA_BUFF_SEC`(3.5) 秒内增伤 +15%; 11 = 3.5 秒内受伤减免 25%。
##   登场还给【对方】随机 1/2/3 个敌人各一把古灵精怪枪。
## 【041】登场 `TIDE_DELAY`(5) 秒后涨潮: +250/400/650 最大生命、+10/16/25 攻击力、
##   体积 +`TIDE_SIZE_UP`(30)%、射程 +`TIDE_RANGE_UP`(50) 码, 持续 8/11/15 秒;
##   到期**全部还原**(退潮**不致死**, 只把生命削到新上限)。
## 【042】每 `RIPPLE_IV`(8) 秒为全队(含自己)各回复其**已损失生命**的 3/6/10%;
##   ★3 时**生命百分比最低**的友军获得**双倍**回复。
## 【043】法力满时从身后 `WAVE_BACK`(400) 码涌起浪墙横扫全场, **敌我双方都会被扫到**:
##   友军 +40/95/120 护盾并**永久** +2/3/5 双抗; 敌人受 60/110/200 魔法伤害并**永久** -2/3/5 双抗。
##   负面被动: 该法器的法力条上限提升 50/25/0%。
## 【044】生命首次降至 `LOWHP_GATE`(50)% 以下时, 在 `NECKLACE_HOT_SEC`(6) 秒内
##   逐渐回复 20/40/80% 最大生命(每场一次)。
## 【045】同样的触发线, `EARRING_HOT_SEC`(8) 秒内逐渐回复 30/60/100% 最大生命,
##   并向 1/1/2 名随机敌人发火球: 8/17/30% 目标最大生命的魔法伤害 + 30/70/150 层灼烧(每场一次)。
##
## ★这六件**结算层全都健康** —— 延时一律走 `_pending_shots`(sim 时钟), 没有一处埋在 tween 上。
##   它们的缺口是**六件里五件没有台子、全部没有属于自己的门禁**。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")

const EXP_PICKS := [1, 2, 4]      # ★写死: 判据不许拿被测常量当期望值(那是恒真式)
const EXP_NECK_SEC := 6.0
const EXP_EAR_SEC := 8.0
const TIDE_HP := [250.0, 400.0, 650.0]
const TIDE_ATK := [10.0, 16.0, 25.0]
const TIDE_DUR := [8.0, 11.0, 15.0]
const RIPPLE_PCT := [0.03, 0.06, 0.10]
const WAVE_SHIELD := [40.0, 95.0, 120.0]
const WAVE_DMG := [60.0, 110.0, 200.0]
const WAVE_RESIST := [2, 3, 5]
const NECK_PCT := [0.20, 0.40, 0.80]
const EAR_PCT := [0.30, 0.60, 1.00]

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
	u["hp"] = 10000.0
	u["maxHp"] = 10000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["shield"] = 0.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 040 FPGA板 / 041 退潮浊液 / 042 涟漪药剂 / 043 海浪护符 / 044 深海项链 / 045 地狱护盾 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ══════════════ 040 FPGA板 ══════════════
	_ok("① ★分母: 每 %.0f 秒抽 %s 个状态 / 00 回血 %.0f%%+%d 双抗 / 01 +%d 攻 / buff %.1f 秒"
		% [ES.FPGA_IV, str(ES.FPGA_PICKS), ES.FPGA_00_HEAL_PCT * 100.0, ES.FPGA_00_RESIST,
		   ES.FPGA_01_ATK, ES.FPGA_BUFF_SEC],
		absf(ES.FPGA_IV - 6.0) < 0.01 and ES.FPGA_PICKS == [1, 2, 4]
			and ES.FPGA_00_RESIST == 12 and ES.FPGA_01_ATK == 15
			and absf(ES.FPGA_BUFF_SEC - 3.5) < 0.01 and absf(ES.FPGA_00_HEAL_PCT - 0.05) < 0.001)
	## ★★抽几个状态吃星级 —— 判据落在「一次 tick 之后四项累计量一共动了多少次」。
	##   四种状态各自改不同的字段, 所以把四项变化量加起来数"动了几次"是对随机不敏感的。
	for si in [0, 2]:
		_s._units.clear()
		var c: Dictionary = _mk(500.0, 400.0, "left")
		c["hp"] = 5000.0        # 留出回血空间, 免得 00 的回血被血满吃掉
		_s._units.append(c)
		_s._units.append(_mk(700.0, 400.0, "right"))
		var d0: float = float(c["base_def"])
		var a0: float = float(c["base_atk"])
		var amp0: float = float(c.get("damage_amp", 0.0))
		var dr0: float = float(c.get("damage_reduction", 0.0))
		_s._equip_sys._eq_fpga_tick(c, si)
		var picks := 0
		picks += int(round((float(c["base_def"]) - d0) / float(ES.FPGA_00_RESIST)))
		picks += int(round((float(c["base_atk"]) - a0) / float(ES.FPGA_01_ATK)))
		picks += int(round((float(c.get("damage_amp", 0.0)) - amp0) / ES.FPGA_10_AMP))
		picks += int(round((float(c.get("damage_reduction", 0.0)) - dr0) / ES.FPGA_11_DR))
		_ok("① ★★★%d 星一次抽了 %d 个状态(应 %d 个)" % [si + 1, picks, EXP_PICKS[si]],
			picks == EXP_PICKS[si],
			"四种状态各改不同字段 ⇒ 把四项变化量加起来数【动了几次】, 对随机不敏感")

	## ★★00 档的「回血」与「+12 双抗」是同一档的两件事 —— 一直抽到抽出 00 为止,
	##   判据落在**那一抽**的回血量, 对随机不敏感(不是"看这次运气好不好")。
	_s._units.clear()
	var c0: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c0)
	_s._units.append(_mk(700.0, 400.0, "right"))
	var got00 := false
	var heal00 := 0.0
	for _r in range(80):
		c0["hp"] = 5000.0                        # 每抽前压回半血, 免得回血被血满吃掉
		var dd0: float = float(c0["base_def"])
		_s._equip_sys._eq_fpga_tick(c0, 0)
		if float(c0["base_def"]) > dd0:
			got00 = true
			heal00 = float(c0["hp"]) - 5000.0
			break
	_ok("① ★★00 档同时回了 %.0f 血(应 %.0f = %.0f%% 最大生命)"
		% [heal00, float(c0["maxHp"]) * ES.FPGA_00_HEAL_PCT, ES.FPGA_00_HEAL_PCT * 100.0],
		got00 and absf(heal00 - float(c0["maxHp"]) * ES.FPGA_00_HEAL_PCT) < 1.0,
		"文案: 00 = 回复 5% 最大生命 **并** 累计 +12 双抗 —— 两件事都要发生")

	## ★★10/11 是**限时** buff(文案写的 3.5 秒), 不是永久 —— 抽到为止, 然后推过期
	_s._units.clear()
	_s._pending_shots.clear()
	var c1: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c1)
	_s._units.append(_mk(700.0, 400.0, "right"))
	var got_tmp := false
	for _r2 in range(80):
		_s._equip_sys._eq_fpga_tick(c1, 0)
		if float(c1.get("damage_amp", 0.0)) > 0.0 or float(c1.get("damage_reduction", 0.0)) > 0.0:
			got_tmp = true
			break
	var amp_on: float = float(c1.get("damage_amp", 0.0)) + float(c1.get("damage_reduction", 0.0))
	_ok("① ★分母: 抽到了一个限时档(增伤 %.2f + 减伤 %.2f)" % [
		float(c1.get("damage_amp", 0.0)), float(c1.get("damage_reduction", 0.0))],
		got_tmp and amp_on > 0.0)
	for _k1 in range(int(ceil((ES.FPGA_BUFF_SEC + 0.3) / _s.SIM_DT))):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("① ★★★%.1f 秒后限时档自己退了(增伤 %.2f / 减伤 %.2f, 都应 0)"
		% [ES.FPGA_BUFF_SEC, float(c1.get("damage_amp", 0.0)),
		   float(c1.get("damage_reduction", 0.0))],
		float(c1.get("damage_amp", 0.0)) < 0.001 and float(c1.get("damage_reduction", 0.0)) < 0.001,
		"文案写的是「3.5 秒内」, 不是永久")

	# ══════════════ 041 退潮浊液 ══════════════
	_ok("② ★分母: 登场 %.0f 秒后涨潮 / 体积 +%.0f%% / 射程 +%.0f 码"
		% [ES.TIDE_DELAY, ES.TIDE_SIZE_UP * 100.0, ES.TIDE_RANGE_UP],
		absf(ES.TIDE_DELAY - 5.0) < 0.01 and absf(ES.TIDE_SIZE_UP - 0.30) < 0.001
			and absf(ES.TIDE_RANGE_UP - 50.0) < 0.01)
	for si in [0, 2]:
		_s._units.clear()
		var t1: Dictionary = _mk(500.0, 400.0, "left")
		_s._units.append(t1)
		_s._units.append(_mk(700.0, 400.0, "right"))
		var hp0: float = float(t1["maxHp"])
		var atk0: float = float(t1["base_atk"])
		var rng0: float = float(t1.get("atk_range", 70.0))
		var siz0: float = float(t1.get("size_mult", 1.0))
		_s._equip_sys._eq_ebb_surge(t1, TIDE_HP[si], TIDE_ATK[si], TIDE_DUR[si])
		_ok("② ★★★%d 星涨潮: 最大生命 +%.0f / 攻击 +%.0f / 射程 +%.0f / 体积 ×%.2f"
			% [si + 1, float(t1["maxHp"]) - hp0, float(t1["base_atk"]) - atk0,
			   float(t1["atk_range"]) - rng0, float(t1["size_mult"]) / siz0],
			absf(float(t1["maxHp"]) - hp0 - TIDE_HP[si]) < 0.5
				and absf(float(t1["base_atk"]) - atk0 - TIDE_ATK[si]) < 0.5
				and absf(float(t1["atk_range"]) - rng0 - ES.TIDE_RANGE_UP) < 0.5
				and absf(float(t1["size_mult"]) / siz0 - (1.0 + ES.TIDE_SIZE_UP)) < 0.01)
		## ★★★退潮**不致死**: 先把血压到只剩一点, 再退潮 —— 生命只该被削到新上限, 不该死
		t1["hp"] = 30.0
		_s._equip_sys._eq_ebb_recede(t1, TIDE_HP[si], TIDE_ATK[si])
		_ok("② ★★★%d 星退潮后全部还原(最大生命 %.0f / 攻击 %.0f / 射程 %.0f / 体积 ×%.2f)"
			% [si + 1, float(t1["maxHp"]), float(t1["base_atk"]), float(t1["atk_range"]),
			   float(t1["size_mult"])],
			absf(float(t1["maxHp"]) - hp0) < 0.5 and absf(float(t1["base_atk"]) - atk0) < 0.5
				and absf(float(t1["atk_range"]) - rng0) < 0.5
				and absf(float(t1["size_mult"]) - siz0) < 0.01)
		_ok("② ★★★%d 星退潮**不致死**(血 30 → %.0f, 仍活着 = %s)"
			% [si + 1, float(t1["hp"]), str(t1.get("alive", false))],
			t1.get("alive", false) and float(t1["hp"]) > 0.0,
			"文案明写「退潮不会致死, 只把生命削到新上限」")

	# ══════════════ 042 涟漪药剂 ══════════════
	_ok("③ ★分母: 每 %.0f 秒回一次" % ES.RIPPLE_IV, absf(ES.RIPPLE_IV - 8.0) < 0.01)
	_s._units.clear()
	var c3: Dictionary = _mk(500.0, 400.0, "left")
	c3["hp"] = 4000.0                      # 已损 6000
	var mate3: Dictionary = _mk(560.0, 400.0, "left")
	mate3["hp"] = 9000.0                   # 已损 1000(血量百分比更高)
	var low3: Dictionary = _mk(620.0, 400.0, "left")
	low3["hp"] = 1000.0                    # 已损 9000(血量百分比**最低**)
	var foe3: Dictionary = _mk(900.0, 400.0, "right")
	foe3["hp"] = 4000.0
	for x in [c3, mate3, low3, foe3]:
		_s._units.append(x)
	var b_c: float = float(c3["hp"])
	var b_m: float = float(mate3["hp"])
	var b_l: float = float(low3["hp"])
	var b_f: float = float(foe3["hp"])
	_s._equip_sys._eq_ripple_tick(c3, 2)
	var heal_m: float = float(mate3["hp"]) - b_m
	var heal_l: float = float(low3["hp"]) - b_l
	_ok("③ ★分母: 全队(含自己)都回了血(自己 +%.0f / 队友 +%.0f / 残血友军 +%.0f)"
		% [float(c3["hp"]) - b_c, heal_m, heal_l],
		float(c3["hp"]) > b_c and heal_m > 0.0 and heal_l > 0.0)
	_ok("③ ★★回的是【已损失生命】的 %.0f%%(队友已损 1000 ⇒ 应回 %.0f, 实回 %.0f)"
		% [RIPPLE_PCT[2] * 100.0, 1000.0 * RIPPLE_PCT[2], heal_m],
		absf(heal_m - 1000.0 * RIPPLE_PCT[2]) < 1.0,
		"不是按最大生命算 —— 血越残回得越多")
	_ok("③ ★★★3 星: **血量百分比最低**的那个拿双倍(已损 9000 ⇒ 应回 %.0f, 实回 %.0f)"
		% [9000.0 * RIPPLE_PCT[2] * 2.0, heal_l],
		absf(heal_l - 9000.0 * RIPPLE_PCT[2] * 2.0) < 1.0)
	_ok("③ ★★敌人不回血(%.0f 应 0)" % (float(foe3["hp"]) - b_f),
		absf(float(foe3["hp"]) - b_f) < 0.01)

	# ══════════════ 043 海浪护符 ══════════════
	_ok("④ ★分母: 从身后 %.0f 码涌起 / 法力条上限提升 %s%%"
		% [ES.WAVE_BACK, str(_s._staff_syn.MANA_FULL_PCT.get("p2eq_043", []))],
		absf(ES.WAVE_BACK - 400.0) < 0.01)
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		var c4: Dictionary = _mk(500.0, 400.0, "left")
		var ally4: Dictionary = _mk(560.0, 400.0, "left")
		var foe4: Dictionary = _mk(900.0, 400.0, "right")
		## ★★敌人得先有双抗底子: 产品那一行是 `maxf(0.0, base_def - N)`,
		##   底子本来就是 0 的话扣完还是 0 —— 那是**门禁自己**没给它底子, 不是产品没扣。
		foe4["base_def"] = 50.0
		foe4["base_mr"] = 50.0
		for x in [c4, ally4, foe4]:
			_s._units.append(x)
		var ad0: float = float(ally4["base_def"])
		var fd0: float = float(foe4["base_def"])
		var fh0: float = float(foe4["hp"])
		_s._equip_sys._eq_water_wave(c4, si)
		_ok("④ ★分母(%d 星): 浪墙把敌我都排进了队列(%d 项)" % [si + 1, _s._pending_shots.size()],
			_s._pending_shots.size() >= 3,
			"文案明写「敌我双方都会被扫到」")
		## 推够 前摇 + 横扫全场
		for _k in range(240):
			_s._sim_step(_s.SIM_DT, false, false)
		_ok("④ ★★★%d 星友军: 护盾 +%.0f(应 %.0f) 且**永久** +%.0f 双抗(应 %d)"
			% [si + 1, float(ally4["shield"]), WAVE_SHIELD[si],
			   float(ally4["base_def"]) - ad0, WAVE_RESIST[si]],
			absf(float(ally4["shield"]) - WAVE_SHIELD[si]) < 0.5
				and absf(float(ally4["base_def"]) - ad0 - float(WAVE_RESIST[si])) < 0.01)
		_ok("④ ★★★%d 星敌人: 掉血 %.0f 且**永久** -%.0f 双抗(应 -%d)"
			% [si + 1, fh0 - float(foe4["hp"]), fd0 - float(foe4["base_def"]), WAVE_RESIST[si]],
			fh0 - float(foe4["hp"]) > 0.0
				and absf(fd0 - float(foe4["base_def"]) - float(WAVE_RESIST[si])) < 0.01)
		_ok("④ %d 星队列已排空" % [si + 1], _s._pending_shots.is_empty(),
			"剩 %d 项" % _s._pending_shots.size())

	# ══════════════ 044 / 045 残血触发 ══════════════
	_ok("⑤ ★分母: 触发线 %.0f%% / 044 摊 %.0f 秒 / 045 摊 %.0f 秒"
		% [ES.LOWHP_GATE * 100.0, ES.NECKLACE_HOT_SEC, ES.EARRING_HOT_SEC],
		absf(ES.LOWHP_GATE - 0.5) < 0.001 and absf(ES.NECKLACE_HOT_SEC - 6.0) < 0.01
			and absf(ES.EARRING_HOT_SEC - 8.0) < 0.01)
	for item in ["p2eq_044", "p2eq_045"]:
		var pct: Array = NECK_PCT if item == "p2eq_044" else EAR_PCT
		var secs: float = EXP_NECK_SEC if item == "p2eq_044" else EXP_EAR_SEC
		_s._units.clear()
		_s._pending_shots.clear()
		var c5: Dictionary = _mk(500.0, 400.0, "left")
		c5["equips"] = [{"id": item, "star": 3}]
		c5["eq_state"] = {}
		_s._units.append(c5)
		var foe5: Dictionary = _mk(900.0, 400.0, "right")
		_s._units.append(foe5)
		## ★血还在线上时不该触发 —— 卡住 LOWHP_GATE 那个数
		c5["hp"] = float(c5["maxHp"]) * (ES.LOWHP_GATE + 0.02)
		_s._equip_sys._eq_check_hp_threshold(c5)
		_ok("⑤ ★★%s 血在 %.0f%% 时**不**触发" % [item, (ES.LOWHP_GATE + 0.02) * 100.0],
			not bool(c5.get("hp50_fired", false)) and float(c5.get("eq_hot_rate", 0.0)) == 0.0,
			"卡住 LOWHP_GATE = %.0f%% 这条线" % (ES.LOWHP_GATE * 100.0))
		## 掉到线下 ⇒ 触发, 且是【摊在 N 秒里】不是瞬回
		c5["hp"] = float(c5["maxHp"]) * (ES.LOWHP_GATE - 0.02)
		var before: float = float(c5["hp"])
		_s._equip_sys._eq_check_hp_threshold(c5)
		_ok("⑤ ★★★%s 掉到线下触发了" % item, bool(c5.get("hp50_fired", false)))
		_ok("⑤ ★★★%s 是【摊在 %.0f 秒里】不是瞬回(当场只回了 %.0f, 速率 %.1f/秒)"
			% [item, secs, float(c5["hp"]) - before, float(c5.get("eq_hot_rate", 0.0))],
			absf(float(c5["hp"]) - before) < 1.0
				and absf(float(c5.get("eq_hot_rate", 0.0)) - float(c5["maxHp"]) * pct[2] / secs) < 1.0,
			"文案明写「在 N 秒内**逐渐**回复」")
		## ★★每场只一次
		c5["hp"] = float(c5["maxHp"]) * 0.1
		c5["eq_hot_rate"] = 0.0
		c5["eq_hot_until"] = 0.0
		_s._equip_sys._eq_check_hp_threshold(c5)
		_ok("⑤ ★★★%s **每场战斗只触发一次**(再掉到 10%% 也不再起)" % item,
			float(c5.get("eq_hot_rate", 0.0)) == 0.0,
			"靠 hp50_fired 拦着")
		if item == "p2eq_045":
			_ok("⑤ ★★★045 同时发了火球(在途投射物 %d 个, ★3 应 2 个)"
				% _s._projectiles.size(),
				_s._projectiles.size() == 2,
				"文案: 向 1/1/2 名随机敌人发射火球; ★3 是 2 个")

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 28:
		print("  [FAIL] ★断言只有 %d 条(<28) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 040~045" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
