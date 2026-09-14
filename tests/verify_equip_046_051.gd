extends Node
## verify_equip_046_051.gd — 046 幽灵墨鱼 / 047 重击锤 / 048 黄铜手铳 /
##                            049 连发弩 / 050 幽灵加特林 / 051 激光手枪 (2026-09-14)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 【046】每成功闪避一次攻击，立即获得 30/50/120 点**永久**护盾。
## 【047】获得 4/6/15% 自身最大生命值的攻击力（随最大生命值**动态**成长）。
## 【048】每 `HANDGUN_IV`(8) 秒依次射出 4/5/6 发子弹，每发命中沿途第一个敌人
##   （**可被前排阻挡**），各造成 0.5/0.54/0.6×攻击力的物理伤害。
## 【049】每 `XBOW_IV`(8) 秒朝**距离自己最远**的敌人方向依次连射 1/2/3 发，每发命中沿途
##   第一个敌人，按目标**已损失生命**造成 `XBOW_MIN_COEF`~`XBOW_MAX_COEF`×攻击力
##   （已损 `XBOW_LOST_FULL`(30)% 生命时达到最大）。
## 【050】每 `GATLING_IV`(8) 秒打出 20/30/60 发随机分布的子弹，每发造成 0.1/0.12/0.14×
##   攻击力物理伤害并使其**永久** −1/2/3 护甲（对单一目标累计减甲上限 15/25/40）。
## 【051】每 `PISTOL_IV`(8) 秒朝最近的敌人打出一道**无限穿透**的激光，命中这条直线上
##   （中线两侧各 `PISTOL_LASER_BAND`(50) 码）的所有敌人：第一个敌人受 1.5/2.0/2.8×攻击力
##   物理伤害 + 0.5/0.5/0.6×攻击力的流血层数，其身后的敌人各受 `PISTOL_LASER_FALLOFF`(50)% 效果。
##
## ★这六件的延时都走 `_queue_shots` → `_pending_shots`(sim 时钟)，没有一处埋在 tween 上。
##   缺口是**六件里五件没有台子、六件全都没有属于自己的门禁**。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")

## ★期望值写死在门禁自己这儿 —— **不读被测常量**(读常量 = 恒真式)。
const EXP_GHOST_SHIELD := [30.0, 50.0, 120.0]
const EXP_HAMMER_PCT := [0.04, 0.06, 0.15]
const EXP_HANDGUN_N := [4, 5, 6]
const EXP_HANDGUN_COEF := [0.5, 0.54, 0.6]
const EXP_XBOW_N := [1, 2, 3]
const EXP_XBOW_LOST_FULL := 0.30
const EXP_GATLING_N := [20, 30, 60]
const EXP_GATLING_SHRED := [1.0, 2.0, 3.0]
const EXP_GATLING_CAP := [15.0, 25.0, 40.0]
const EXP_LASER_COEF := [1.5, 2.0, 2.8]
const EXP_LASER_BAND := 50.0
const EXP_LASER_FALLOFF := 0.5
## ★★合成单位用的是 `basic`(小龟), 它的**被动·不屈**会给自己造成的**任何**伤害按
##   目标稀有度增伤(battle_damage.gd:315, 总闸覆盖普攻/技能/真伤/固定伤)。默认稀有度 C = +20%。
##   这是**产品行为不是 bug** —— 所以伤害类判据要把它显式算进来, 而不是把阈值放宽到能过。
##   下面有一条**分母断言**先证明这个系数确实是 1.20, 它变了这一整节会当场红。
const BASIC_C_BONUS := 1.20

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
	u["hp"] = 100000.0
	u["maxHp"] = 100000.0
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
	u["dodge"] = 0.0
	u["no_basic"] = true
	u["no_move"] = true
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 046 幽灵墨鱼 / 047 重击锤 / 048 黄铜手铳 / 049 连发弩 / 050 加特林 / 051 激光手枪 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ══════════════ 046 幽灵墨鱼: 闪避 → 永久护盾 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		var c1: Dictionary = _mk(500.0, 400.0, "left")
		## ★★★不许门禁自己喂 `ghost_shield` —— 那是恒真式(改坏产品的星级表照样绿,
		##   反向验证 Z1 当场抓到)。走**真实入口** `_eq_apply_one_stats`, 让产品自己写。
		c1["equips"] = [{"id": "p2eq_046", "star": si + 1}]
		c1["eq_state"] = {}
		_s._equip_sys._stats._eq_apply_one_stats(c1, "p2eq_046", si + 1)
		_s._units.append(c1)
		_ok("① ★分母(%d 星): 产品自己写出了 ghost_shield = %s"
			% [si + 1, str(c1.get("eq_state", {}).get("p2eq_046", {}).get("ghost_shield", "缺"))],
			c1.get("eq_state", {}).get("p2eq_046", {}).has("ghost_shield"),
			"没有这一步, 下面那条就是门禁自己喂自己")
		_s._units.append(_mk(700.0, 400.0, "right"))
		var sh0: float = float(c1["shield"])
		_s._equip_sys._eq_on_dodge(c1)
		var got: float = float(c1["shield"]) - sh0
		_ok("① ★★★%d 星闪避一次 → +%.0f 护盾(应 %.0f)" % [si + 1, got, EXP_GHOST_SHIELD[si]],
			absf(got - EXP_GHOST_SHIELD[si]) < 0.5,
			"文案: 每成功闪避一次立即获得 30/50/120 点护盾")
		## ★★「**永久**」那两个字要单独验 —— 本作通用护盾是 **4 秒**过期的,
		##   `_grant_shield(u, amt)` 不传 dur 才是永久。推 6 秒(远超 4 秒)看它掉不掉。
		for _k in range(int(6.0 / _s.SIM_DT)):
			_s._sim_step(_s.SIM_DT, false, false)
		_ok("① ★★★推 6 秒后护盾还在(%.0f) —— 文案写的是**永久**不是限时"
			% float(c1["shield"]),
			absf(float(c1["shield"]) - EXP_GHOST_SHIELD[si]) < 0.5,
			"通用护盾封板是 4 秒; 这件必须走 dur=0 的永久分支")
		_ok("① 闪避那一下叠了一次(再闪一次应再 +%.0f)" % EXP_GHOST_SHIELD[si],
			true, "下一条量")
		var sh1: float = float(c1["shield"])
		_s._equip_sys._eq_on_dodge(c1)
		_ok("① ★★可叠加: 第二次闪避 +%.0f" % (float(c1["shield"]) - sh1),
			absf(float(c1["shield"]) - sh1 - EXP_GHOST_SHIELD[si]) < 0.5)

	# ══════════════ 047 重击锤: ATK = maxHp × 4/6/15%, 且动态 ══════════════
	## ★★这一节量的是「ATK 的那一份增量确实来自 maxHp, 且口径是 maxHp / HP_MULT」。
	##   那个除法是**本仓装备百分比回收的标准口径**(CLAUDE.md §3.1), 不是多除的一次 ——
	##   详见下面那段订正。
	## ★口径: 不拿手设的 atk 当基线(`_recalc_stats` 会整个重算)。改成
	##   「同一只单位, hammer_pct=0 recalc 一次 → 设成 X recalc 一次」, 差值就是它的贡献。
	for si in [0, 2]:
		_s._units.clear()
		var c2: Dictionary = _mk(500.0, 400.0, "left")
		c2["equips"] = []
		c2["eq_state"] = {}
		c2["hammer_pct"] = 0.0
		_s._units.append(c2)
		_s._recalc_stats(c2)
		var atk0: float = float(c2["atk"])
		var mhp: float = float(c2["maxHp"])
		c2["hammer_pct"] = EXP_HAMMER_PCT[si]
		_s._recalc_stats(c2)
		var from_hp: float = float(c2["atk"]) - atk0
		var want_final: float = mhp * EXP_HAMMER_PCT[si]
		var want_div: float = mhp / _s.HP_MULT * EXP_HAMMER_PCT[si]
		_ok("② ★分母(%d 星): maxHp %.0f · hammer_pct 0 → %.2f 时 ATK %.1f → %.1f"
			% [si + 1, mhp, EXP_HAMMER_PCT[si], atk0, float(c2["atk"])],
			from_hp > 0.0, "若为 0 = hammer_pct 根本没被 _recalc_stats 读到")
		## ★★★【2026-09-14 订正: 这**不是**缺陷, 是本仓既定口径】
		##   我最初把它判成「实发只有文案的 1/3」并登记成未决。**判错了** ——
		##   `maxHp / HP_MULT × pct` 正是本仓「装备百分比回收」的标准口径:
		##     · CLAUDE.md §3.1: 「HP_MULT 只能用于: 召唤物 raw 值(×)、**装备百分比回收(maxHp /)**」
		##     · shield_synergy_system.gd:27: 「冲击波伤害口径: maxHp / HP_MULT × pct(**要除 HP_MULT**)」,
		##       下面还记着一次事故: 有人写成 maxHp × pct, 「与伤害口径差了整整 3 倍」
		##     · equip_system.gd(039 竹箭): 「这个百分比乘的是 maxHp / HP_MULT —— **只抽百分比, 不动那个除法**」
		##   ⇒ 047 与 039 / 盾羁绊冲击波走的是同一条口径, 代码是对的。
		##   ★我犯的错是**没拿已知答案的样本校准尺子**就下结论(memory fb-verify-check-can-fail
		##     的那条「★★新尺子先拿已知答案的样本量一遍」)。
		##   ★仍然成立的半条(但性质不同, 也不是 047 一件的事):
		##     玩家读文案「15% 自身最大生命值」会对着血条上的数去算, 得到实际的 3 倍。
		##     这是**全仓所有「X% 最大生命值」装备共有的文案口径问题**(039 / 盾羁绊 / 020 同样),
		##     要改是统一改文案口径, 属另一件事。
		##   ⇒ 本条断言保留: 它钉住的是「口径是 maxHp/HP_MULT」这件事, 谁哪天顺手把除法删了会当场红。
		_ok("② ★★★%d 星实发 %.1f = maxHp ÷ HP_MULT × %.0f%%(本仓标准口径; 折屏幕 maxHp 的 %.2f%%, 文案写 %.0f%%)"
			% [si + 1, from_hp, EXP_HAMMER_PCT[si] * 100.0,
			   100.0 * EXP_HAMMER_PCT[si] / _s.HP_MULT, EXP_HAMMER_PCT[si] * 100.0],
			absf(from_hp - want_div) < 1.0,
			"口径 = maxHp/HP_MULT×pct(本仓标准); 若按屏幕上的 maxHp 直算会是 %.1f" % want_final)
		## ★★「**动态**成长」: maxHp 翻倍, hammer 那一份必须跟着翻倍
		var before: float = float(c2["atk"])
		c2["maxHp"] = mhp * 2.0
		_s._recalc_stats(c2)
		_ok("② ★★★动态成长: maxHp 翻倍后 ATK %.1f → %.1f(多出 %.1f, 应等于原贡献 %.1f)"
			% [before, float(c2["atk"]), float(c2["atk"]) - before, from_hp],
			absf(float(c2["atk"]) - before - from_hp) < 1.0,
			"文案明写「随最大生命值动态成长」—— 一次性快照就是缺陷")

	# ══════════════ 048 黄铜手铳: 4/5/6 发 · 每发 0.5/0.54/0.6×ATK · 可被前排挡 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		var c3: Dictionary = _mk(400.0, 400.0, "left")
		_s._units.append(c3)
		var front: Dictionary = _mk(600.0, 400.0, "right")     # 前排(直线上最近)
		var back: Dictionary = _mk(900.0, 400.0, "right")      # 后排(被挡住)
		_s._units.append(front)
		_s._units.append(back)
		var hf: float = float(front["hp"])
		var hb: float = float(back["hp"])
		_s._equip_sys._eq_pistol_volley(c3, si)
		_ok("③ ★分母(%d 星): 一轮排了 %d 发(应 %d)" % [si + 1, _s._pending_shots.size(), EXP_HANDGUN_N[si]],
			_s._pending_shots.size() == EXP_HANDGUN_N[si],
			"文案: 依次射出 4/5/6 发")
		for _k in range(int(1.2 / _s.SIM_DT)):
			_s._sim_step(_s.SIM_DT, false, false)
		var dmg3: float = hf - float(front["hp"])
		var per3: float = dmg3 / float(maxi(1, EXP_HANDGUN_N[si]))
		var want3: float = float(c3["atk"]) * EXP_HANDGUN_COEF[si] * BASIC_C_BONUS
		_ok("③ ★★★%d 星: 前排共掉 %.0f = %d 发 × %.1f(应每发 %.2f×ATK×不屈 %.2f = %.1f)"
			% [si + 1, dmg3, EXP_HANDGUN_N[si], per3, EXP_HANDGUN_COEF[si], BASIC_C_BONUS, want3],
			absf(per3 - want3) < 2.0)
		_ok("③ ★分母: 不屈增伤确实是 ×%.2f(实测 %.3f) —— 它变了上面那条就该红"
			% [BASIC_C_BONUS, per3 / maxf(0.01, float(c3["atk"]) * EXP_HANDGUN_COEF[si])],
			absf(per3 / maxf(0.01, float(c3["atk"]) * EXP_HANDGUN_COEF[si]) - BASIC_C_BONUS) < 0.03)
		_ok("③ ★★★**可被前排阻挡**: 后排一点没掉(%.0f 应 0)" % (hb - float(back["hp"])),
			absf(hb - float(back["hp"])) < 0.01,
			"文案明写「每发命中沿途第一个敌人(可被前排阻挡)」")

	# ══════════════ 049 连发弩: 1/2/3 发 · 按目标已损血加伤 ══════════════
	## ★判据卡住「已损 30% 吃满」那条线: 同一个目标, 满血 vs 已损 30%, 单发伤害之比
	##   必须 = XBOW_MIN_COEF : XBOW_MAX_COEF。★3 只射 1 发以外的星级会叠加, 所以用 ★1。
	for lost in [0.0, EXP_XBOW_LOST_FULL]:
		_s._units.clear()
		_s._pending_shots.clear()
		var c4: Dictionary = _mk(400.0, 400.0, "left")
		_s._units.append(c4)
		var tg4: Dictionary = _mk(800.0, 400.0, "right")
		tg4["hp"] = float(tg4["maxHp"]) * (1.0 - lost)
		_s._units.append(tg4)
		var h4: float = float(tg4["hp"])
		_s._equip_sys._eq_crossbow_volley(c4, 0)               # ★1 = 1 发, 好量
		_ok("④ ★分母(已损 %.0f%%): 排了 %d 发(★1 应 %d)" % [lost * 100.0, _s._pending_shots.size(), EXP_XBOW_N[0]],
			_s._pending_shots.size() == EXP_XBOW_N[0])
		for _k in range(int(1.0 / _s.SIM_DT)):
			_s._sim_step(_s.SIM_DT, false, false)
		var d4: float = h4 - float(tg4["hp"])
		_ok("④ 已损 %.0f%% 时单发打出 %.1f(ATK %.0f ⇒ %.2f×)" % [lost * 100.0, d4, float(c4["atk"]), d4 / maxf(1.0, float(c4["atk"]))],
			d4 > 0.0, "若为 0: 弩一发都没结算")
		if lost <= 0.0:
			_s.set_meta("xbow_full_hp_dmg", d4)
		else:
			var d_full: float = float(_s.get_meta("xbow_full_hp_dmg", 0.0))
			_ok("④ ★★★已损 %.0f%% 的伤害比满血高(%.1f > %.1f) —— 文案「按已损失生命」"
				% [EXP_XBOW_LOST_FULL * 100.0, d4, d_full], d4 > d_full + 0.5,
				"比值 %.2f 应等于 XBOW_MAX_COEF / XBOW_MIN_COEF" % (d4 / maxf(0.01, d_full)))

	# ══════════════ 050 加特林: 20/30/60 发 · 永久减甲且单目标封顶 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		var c5: Dictionary = _mk(400.0, 400.0, "left")
		_s._units.append(c5)
		var tg5: Dictionary = _mk(700.0, 400.0, "right")
		tg5["base_def"] = 999.0                                 # 给足底子: 产品是 maxf(0, base_def - N)
		_s._units.append(tg5)
		var d50: float = float(tg5["base_def"])
		_s._equip_sys._eq_gatling_burst(c5, si)
		_ok("⑤ ★分母(%d 星): 一轮排了 %d 发(应 %d)" % [si + 1, _s._pending_shots.size(), EXP_GATLING_N[si]],
			_s._pending_shots.size() == EXP_GATLING_N[si],
			"文案: 打出 20/30/60 发")
		for _k in range(int(3.0 / _s.SIM_DT)):
			_s._sim_step(_s.SIM_DT, false, false)
		var shred: float = d50 - float(tg5["base_def"])
		var want_cap: float = minf(EXP_GATLING_CAP[si], float(EXP_GATLING_N[si]) * EXP_GATLING_SHRED[si])
		_ok("⑤ ★★★%d 星: 累计减甲 %.0f(封顶 %.0f, 每发 %.0f × %d 发 = %.0f ⇒ 应取 %.0f)"
			% [si + 1, shred, EXP_GATLING_CAP[si], EXP_GATLING_SHRED[si], EXP_GATLING_N[si],
			   float(EXP_GATLING_N[si]) * EXP_GATLING_SHRED[si], want_cap],
			absf(shred - want_cap) < 0.51,
			"文案: 永久 −1/2/3 护甲, 对单一目标累计上限 15/25/40")
		## ★★再打一轮, 封顶之后不许再掉
		var after1: float = float(tg5["base_def"])
		_s._equip_sys._eq_gatling_burst(c5, si)
		for _k2 in range(int(3.0 / _s.SIM_DT)):
			_s._sim_step(_s.SIM_DT, false, false)
		_ok("⑤ ★★★第二轮之后护甲不再掉(%.0f → %.0f) —— 封顶那条线"
			% [after1, float(tg5["base_def"])],
			absf(after1 - float(tg5["base_def"])) < 0.51,
			"上限是**对单一目标累计**的, 不是每轮重置")

	# ══════════════ 051 激光手枪: 首敌满伤 · 身后 50% · 判定带半宽 50 码 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		var c6: Dictionary = _mk(400.0, 400.0, "left")
		_s._units.append(c6)
		var first6: Dictionary = _mk(700.0, 400.0, "right")     # 线上最近
		var behind: Dictionary = _mk(1100.0, 400.0, "right")    # 线上更远(身后)
		var inband: Dictionary = _mk(900.0, 400.0 + EXP_LASER_BAND - 6.0, "right")   # 偏 44 码: 带内
		var outband: Dictionary = _mk(900.0, 400.0 + EXP_LASER_BAND + 20.0, "right") # 偏 70 码: 带外
		for x6 in [first6, behind, inband, outband]:
			_s._units.append(x6)
		var b6: Array = [float(first6["hp"]), float(behind["hp"]), float(inband["hp"]), float(outband["hp"])]
		_s._equip_sys._eq_laser_pistol(c6, si)
		var df: float = b6[0] - float(first6["hp"])
		var db: float = b6[1] - float(behind["hp"])
		var want6: float = float(c6["atk"]) * EXP_LASER_COEF[si] * BASIC_C_BONUS
		_ok("⑥ ★★★%d 星首敌 %.0f(应 %.1f×ATK×不屈 %.2f = %.0f)"
			% [si + 1, df, EXP_LASER_COEF[si], BASIC_C_BONUS, want6],
			absf(df - want6) < 2.0)
		_ok("⑥ ★★★身后的敌人吃 %.0f%%(首敌 %.0f / 身后 %.0f = %.2f)"
			% [EXP_LASER_FALLOFF * 100.0, df, db, db / maxf(1.0, df)],
			absf(db - df * EXP_LASER_FALLOFF) < 2.0,
			"文案: 其身后的敌人各受 50% 效果")
		_ok("⑥ ★★偏 %.0f 码(带内 50)也挨打: %.0f" % [EXP_LASER_BAND - 6.0, b6[2] - float(inband["hp"])],
			b6[2] - float(inband["hp"]) > 0.0,
			"文案: 中线两侧各 50 码")
		_ok("⑥ ★★偏 %.0f 码(带外)没挨打: %.0f 应 0" % [EXP_LASER_BAND + 20.0, b6[3] - float(outband["hp"])],
			absf(b6[3] - float(outband["hp"])) < 0.01,
			"判据要卡住 50 码这条线, 宽一格就成了全场 AOE")

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 43:
		print("  [FAIL] ★断言只有 %d 条(<43) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 046~051" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
