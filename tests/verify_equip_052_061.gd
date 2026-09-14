extends Node
## verify_equip_052_061.gd — 052 左轮 / 053 霰弹 / 054 瞄准镜 / 055 病毒箭头 /
##                            056 飞镖 / 057 狙击 / 058 炮台 / 059 沙漏 /
##                            060 水母伞 / 061 钻孔螺 (2026-09-14 · 第六批 10 件)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 【052】6 发子弹（任何敌人阵亡 +1，上限 6；每场重置）；每 4 秒向 1 名随机敌人射 1 发；
##        子弹为 0 时停火。
## 【053】每 8 秒朝最近敌打 12/14/18 颗弹珠（相邻夹角 2.5 度）；每颗撞到路径上第一个敌人
##        造成 0.22×ATK 物理并消失；同一次齐射被 **8 颗及以上**命中 → 眩晕。
## 【054】造成的伤害**无视闪避**（必中）。
## 【055】本场累计造成 400 点伤害后发钩索炸弹；炸弹每 1 秒对宿主造成 3/6/6% 其最大生命值物理伤害。
## 【056】任何敌人被己方击飞时挂「靶子」；携带者每周期向带靶子的敌各射 1 镖，命中后**移除靶子**。
## 【057】每 8 秒**锁定生命百分比最低**的敌人蓄力 1 秒后开枪；击杀则重选再来一枪（每枪都要蓄力）。
## 【058】登场召唤不可移动炮台：500/1000/1800 生命、20/30/45 攻击、0.5 次/秒、2000 码射程；
##        携带者存活 → 炮台 +70/85/100 双抗；携带者在 400 码内 → 携带者自身攻速 +20/30/40%。
## 【059】第 10 秒起蓄力 1 秒后时停，持续 4/7/20 秒。
## 【060】每 7 秒开伞 2.5 秒：自身与 200 码内队友 +11/22/35% 减伤 + 15% 闪避；
##        结束时携带者回复 50/80/130 生命。
## 【061】每次**普攻**命中额外造成目标最大生命 2/2.5/3% 魔法伤害并叠 1/1/2 层破损（上限 20，不衰减）；
##        打在**已满 20 层**的目标上时这段伤害转**真实伤害**。
##
## ★期望值全部写死在门禁自己这儿，**不读被测常量**（读常量 = 恒真式）。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const EXP_REVOLVER_AMMO := 6
const EXP_SHOTGUN_N := [12, 14, 18]
const EXP_SHOTGUN_COEF := 0.22
const EXP_SHOTGUN_STUN_HITS := 8
const EXP_TRIGGER_DMG := 400
const EXP_BOMB_PCT := [0.03, 0.06, 0.06]
const EXP_TURRET_HP := [500.0, 1000.0, 1800.0]
const EXP_TURRET_ATK := [20.0, 30.0, 45.0]
const EXP_TURRET_ASPD := 0.5
const EXP_TURRET_RES := [70.0, 85.0, 100.0]
const EXP_TURRET_BUFF_ASPD := 1.00   # 携带者在 400 码内的自身攻速加成(用户 2026-09-14 从 20/30/40% 统一到 100%)
const EXP_TS_START := 10.0
const EXP_TS_DUR := [4.0, 7.0, 20.0]
const EXP_PARASOL_DR := [0.11, 0.22, 0.35]
const EXP_PARASOL_DODGE := 0.15
const EXP_PARASOL_R := 200.0
const EXP_BREACH_CAP := 20
const EXP_BREACH_PCT := [0.02, 0.025, 0.03]
const EXP_BREACH_ADD := [1, 1, 2]

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
	u["no_basic"] = true
	u["no_move"] = true
	return u


func _advance(sec: float) -> void:
	var steps: int = int(sec / _s.SIM_DT) + 1
	for _k in range(steps):
		var t0: float = _s._t
		_s._sim_step(_s.SIM_DT, false, false)
		if absf(_s._t - t0) < 1e-6:
			_s._t += _s.SIM_DT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 052 左轮 / 053 霰弹 / 054 瞄准镜 / 055 病毒箭头 / 056 飞镖 / 057 狙击 / 058 炮台 / 059 沙漏 / 060 伞 / 061 钻孔螺 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var ES = _s._equip_sys

	# ══════════════ 052 左轮: 弹匣 ══════════════
	_s._units.clear()
	_s._pending_shots.clear()
	_s._over = false
	var c1: Dictionary = _mk(400.0, 400.0, "left")
	c1["equips"] = [{"id": "p2eq_052", "star": 3}]
	c1["eq_state"] = {}
	## ★走真实入口让产品自己写初始弹数, 不手喂(手喂 = 恒真式)
	ES._stats._eq_apply_one_stats(c1, "p2eq_052", 3)
	_s._units.append(c1)
	var e1: Dictionary = _mk(800.0, 400.0, "right")
	_s._units.append(e1)
	var st1: Dictionary = c1["eq_state"].get("p2eq_052", {})
	_ok("① ★分母: 产品自己写出了初始弹数 %s" % str(st1.get("revolver_bullets", "缺")),
		st1.has("revolver_bullets"))
	_ok("① ★★★初始弹数 = %d" % EXP_REVOLVER_AMMO,
		int(st1.get("revolver_bullets", -1)) == EXP_REVOLVER_AMMO)
	var before1: int = int(st1["revolver_bullets"])
	ES._eq_revolver_tick(c1, 2, st1)
	_ok("① ★★★射一发扣一发(%d → %d)" % [before1, int(st1["revolver_bullets"])],
		int(st1["revolver_bullets"]) == before1 - 1)
	## 打空 → 停火(弹数不许变负, 也不许再产生弹道)
	st1["revolver_bullets"] = 0
	_s._pending_shots.clear()
	ES._eq_revolver_tick(c1, 2, st1)
	_ok("① ★★★子弹为 0 时停火(弹数仍是 %d, 没变负)" % int(st1["revolver_bullets"]),
		int(st1["revolver_bullets"]) == 0,
		"文案: 子弹为 0 时停火(装备不消失)")
	## 敌人阵亡 → +1, 且不许超过上限
	st1["revolver_bullets"] = EXP_REVOLVER_AMMO
	c1["eq_state"]["p2eq_052"] = st1
	ES._eq_on_death(e1, c1)
	_ok("① ★★★已满时敌人阵亡不许超上限(%d)" % int(c1["eq_state"]["p2eq_052"]["revolver_bullets"]),
		int(c1["eq_state"]["p2eq_052"]["revolver_bullets"]) == EXP_REVOLVER_AMMO)
	c1["eq_state"]["p2eq_052"]["revolver_bullets"] = 2
	ES._eq_on_death(e1, c1)
	_ok("① ★★★敌人阵亡 +1 发(2 → %d)" % int(c1["eq_state"]["p2eq_052"]["revolver_bullets"]),
		int(c1["eq_state"]["p2eq_052"]["revolver_bullets"]) == 3,
		"文案: 任何敌人阵亡时 +1 发")

	# ══════════════ 053 霰弹: 弹珠数 / 每颗系数 / 8 颗眩晕 ══════════════
	## ★★弹珠没有数组容器(走 `_ballistics._shotgun_pellet` 的回调), 数不出来。
	##   判据改成: **把敌人放到 60 码近处**, 让整个扇面(★3 半角 (18-1)/2×2.5 = 21.25°,
	##   在 60 码处横向只散开约 23 码)全部打在同一个人身上 ⇒
	##   **总伤害 ÷ 单颗伤害 = 颗数**, 数出来的是产品自己的账。
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		_s._over = false
		var c2: Dictionary = _mk(400.0, 400.0, "left")
		_s._units.append(c2)
		var e2: Dictionary = _mk(460.0, 400.0, "right")   # 只隔 60 码
		_s._units.append(e2)
		var h2: float = float(e2["hp"])
		ES._eq_shotgun_blast(c2, si)
		_advance(1.6)
		var dmg2: float = h2 - float(e2["hp"])
		_ok("② ★分母(%d 星): 弹珠真的打到人了(掉 %.0f)" % [si + 1, dmg2], dmg2 > 0.0,
			"0 的话下面那条是空检查")
		## 单颗 = SHOTGUN_COEF × ATK × 小龟【不屈】增伤(合成单位是 basic, 稀有度 C = ×1.20)
		var one2: float = float(c2["atk"]) * EXP_SHOTGUN_COEF * 1.20
		var hits2: float = dmg2 / maxf(0.01, one2)
		_ok("② ★★★%d 星: 打中 %.1f 颗(应 %d 颗 —— 60 码处整个扇面都在人身上)"
			% [si + 1, hits2, EXP_SHOTGUN_N[si]],
			absf(hits2 - float(EXP_SHOTGUN_N[si])) < 1.0,
			"文案: 12/14/18 颗, 每颗 %.2f×攻击力" % EXP_SHOTGUN_COEF)
		## 文案: 同一次齐射被 8 颗及以上命中 → 眩晕。★3 打 18 颗全中, 必须眩晕。
		if si == 2:
			_ok("② ★★★被 %d 颗(≥%d)命中 ⇒ 眩晕(stun_until %.2f > 当前 %.2f)"
				% [EXP_SHOTGUN_N[si], EXP_SHOTGUN_STUN_HITS,
				   float(e2.get("stun_until", 0.0)), _s._t],
				float(e2.get("stun_until", 0.0)) > _s._t,
				"文案: 同一次齐射被 8 颗及以上弹珠命中的敌人眩晕")

	# ══════════════ 054 瞄准镜: 必中 ══════════════
	## ★★两个坑, 都记下来:
	##   ① 闪避**上限是 DODGE_CAP = 0.75**, 不是 100% —— 我第一版按"100% 闪避的靶子"写判据,
	##     产品把 1.0 钳成 0.75, 于是反证那条"一次都打不中"当场红, 而产品是对的。
	##   ② GDScript 的格式化陷阱: 字符串里写 `100%` 会被 `%` 运算符当成格式符吃掉,
	##     整条 `%.2f` 原样打出来。要写百分号必须 `%%`。
	## ⇒ 判据改成对随机不敏感(memory [[fb-make-assertions-rng-insensitive]]):
	##   带镜的 20 发**全中**(必中是确定性的), 不带镜的 40 发**明显打不中那么多**。
	_s._units.clear()
	_s._over = false
	var c3: Dictionary = _mk(400.0, 400.0, "left")
	c3["equips"] = [{"id": "p2eq_054", "star": 3}]
	c3["eq_state"] = {}
	ES._stats._eq_apply_one_stats(c3, "p2eq_054", 3)
	_s._units.append(c3)
	_ok("③ ★★★带瞄准镜 ⇒ 产品自己写上了「不可被闪避」标记",
		bool(c3.get("eq_cannot_be_dodged", false)),
		"文案: 造成的伤害无视闪避(必中)")
	var e3: Dictionary = _mk(700.0, 400.0, "right")
	## 靶子的闪避走**真机制**(buff → _recalc_stats → dodge_bonus), 不手写那个输出字段
	(e3["buffs"] as Array).append({"stat": "dodge", "amount": 1.0, "pct": false,
		"until": _s._t + 1.0e9, "src_eq": "test"})
	_s._recalc_stats(e3)
	_s._units.append(e3)
	var dodge3: float = float(e3.get("dodge_bonus", 0.0))
	_ok("③ ★分母: 靶子闪避被钳到上限 %.2f(产品 DODGE_CAP)" % dodge3,
		dodge3 > 0.7,
		"若为 0, 下面两条都是空检查")
	## 带镜: 20 发必须发发都中
	var land_scope: int = 0
	for _k in range(20):
		var hp_b: float = float(e3["hp"])
		_s._damage._apply_damage_from(c3, e3, 500, Color.WHITE)
		if float(e3["hp"]) < hp_b:
			land_scope += 1
	_ok("③ ★★★必中: 带镜打 20 发, 中了 %d 发(应 20)" % land_scope, land_scope == 20)
	## 不带镜: 40 发在 0.75 闪避下期望只中 10 发左右
	var c3b: Dictionary = _mk(400.0, 430.0, "left")
	_s._units.append(c3b)
	var land_plain: int = 0
	for _k in range(40):
		var hp_c: float = float(e3["hp"])
		_s._damage._apply_damage_from(c3b, e3, 500, Color.WHITE)
		if float(e3["hp"]) < hp_c:
			land_plain += 1
	_ok("③ ★★分母(反证): 不带镜打 40 发只中 %d 发(闪避 %.2f ⇒ 期望约 10; 判 < 24)"
		% [land_plain, dodge3],
		land_plain < 24,
		"这条证明上面那条「20 发全中」不是恒真式 —— 没有它, 闪避根本没生效也照样绿")

	# ══════════════ 058 炮台 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		_s._over = false
		var c4: Dictionary = _mk(400.0, 400.0, "left")
		c4["_turret_si"] = si
		_s._units.append(c4)
		_s._units.append(_mk(900.0, 400.0, "right"))
		var n0: int = _s._units.size()
		ES._eq_summon_turret(c4, si)
		_ok("④ ★分母(%d 星): 召出来了(单位数 %d → %d)" % [si + 1, n0, _s._units.size()],
			_s._units.size() > n0)
		var tr = null
		for o in _s._units:
			if o.get("_eq_turret", false):
				tr = o
		_ok("④ ★分母: 找得到那座炮台", tr != null)
		if tr == null:
			continue
		_ok("④ ★★★%d 星炮台 %.0f 生命 / %.0f 攻击(文案 %.0f / %.0f)"
			% [si + 1, float(tr["maxHp"]), float(tr["base_atk"]), EXP_TURRET_HP[si], EXP_TURRET_ATK[si]],
			absf(float(tr["maxHp"]) - EXP_TURRET_HP[si]) < 1.0
				and absf(float(tr["base_atk"]) - EXP_TURRET_ATK[si]) < 1.0,
			"★这一条同时守着 HP_MULT 陷阱: 召唤物血若被多乘一次会是 3 倍(032 骷髅就栽过)")
		_ok("④ ★★炮台不可移动(move_spd = %.0f)" % float(tr.get("move_spd", -1.0)),
			absf(float(tr.get("move_spd", -1.0))) < 0.01)
		_ok("④ ★★攻速 %.2f 次/秒(atk_interval %.2f 秒)"
			% [1.0 / maxf(0.01, float(tr["atk_interval"])), float(tr["atk_interval"])],
			absf(1.0 / maxf(0.01, float(tr["atk_interval"])) - EXP_TURRET_ASPD) < 0.01)
		## 携带者存活 → 炮台拿双抗; 阵亡 → 归零
		ES._tick_eq_turret(c4, 0.1)
		_ok("④ ★★★携带者存活 ⇒ 炮台双抗 %.0f(文案 %.0f)" % [float(tr["base_def"]), EXP_TURRET_RES[si]],
			absf(float(tr["base_def"]) - EXP_TURRET_RES[si]) < 0.01)
		c4["alive"] = false
		ES._tick_eq_turret(c4, 0.1)
		_ok("④ ★★★携带者阵亡 ⇒ 炮台双抗归零(%.0f)" % float(tr["base_def"]),
			absf(float(tr["base_def"])) < 0.01)
		c4["alive"] = true
		## 携带者靠近 → 自身攻速倍率; 走远 → 回 1.0
		c4["pos"] = tr["pos"]
		ES._tick_eq_turret(c4, 0.1)
		var near_m: float = float(c4.get("_turret_aspd_mult", 0.0))
		c4["pos"] = (tr["pos"] as Vector2) + Vector2(3000.0, 0.0)
		ES._tick_eq_turret(c4, 0.1)
		var far_m: float = float(c4.get("_turret_aspd_mult", 0.0))
		_ok("④ ★★★靠近炮台自身攻速倍率 %.2f(应 %.2f), 走远回 %.2f" % [near_m, 1.0 + EXP_TURRET_BUFF_ASPD, far_m],
			absf(near_m - (1.0 + EXP_TURRET_BUFF_ASPD)) < 0.01 and absf(far_m - 1.0) < 0.01,
			"用户 2026-09-14 拍板: 20/30/40%% → 三档统一 +100%%")

	# ══════════════ 061 钻孔螺: 破损层 / 满层转真伤 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._over = false
		var c5: Dictionary = _mk(400.0, 400.0, "left")
		_s._units.append(c5)
		var e5: Dictionary = _mk(700.0, 400.0, "right")
		e5["mr"] = 500.0          # 堆满魔抗: 魔法伤会被削, 真伤不会 —— 这是分辨两者的尺子
		e5["base_mr"] = 500.0
		_s._units.append(e5)
		var sb = ES._spirit_sys
		_ok("⑤ ★分母: 找得到灵物批系统", sb != null)
		if sb == null:
			break
		var h5: float = float(e5["hp"])
		sb._eq_drill_snail(c5, e5, si, true)
		var d_first: float = h5 - float(e5["hp"])
		_ok("⑤ ★★★%d 星: 一次普攻叠 %d 层破损(实测 %d)"
			% [si + 1, EXP_BREACH_ADD[si], sb.breach_of(e5)],
			sb.breach_of(e5) == EXP_BREACH_ADD[si],
			"文案: 施加 1/1/2 层【破损】")
		_ok("⑤ ★分母: 这一击真的打了伤害(%.0f)" % d_first, d_first > 0.0)
		## 非普攻不许触发(文案「每次**普攻**命中」)
		var b_before: int = sb.breach_of(e5)
		sb._eq_drill_snail(c5, e5, si, false)
		_ok("⑤ ★★★非普攻不触发(层数仍是 %d)" % sb.breach_of(e5),
			sb.breach_of(e5) == b_before,
			"文案写的是「每次**普攻**命中」")
		## 满层 → 转真实伤害: 用魔抗 500 的靶子对比, 真伤明显更高
		e5["breach_stacks"] = EXP_BREACH_CAP
		var h5b: float = float(e5["hp"])
		sb._eq_drill_snail(c5, e5, si, true)
		var d_true: float = h5b - float(e5["hp"])
		_ok("⑤ ★★★满 %d 层后转真实伤害(满层 %.0f > 未满层 %.0f, 靶子魔抗 500)"
			% [EXP_BREACH_CAP, d_true, d_first],
			d_true > d_first * 1.5,
			"文案: 打在已有上限层破损的目标身上时这段伤害转为真实伤害")
		_ok("⑤ ★★层数封顶 %d(再打也不涨: %d)" % [EXP_BREACH_CAP, sb.breach_of(e5)],
			sb.breach_of(e5) == EXP_BREACH_CAP)

	# ══════════════ 055 病毒箭头: 累计 400 伤害 → 挂钩索炸弹 → 每秒啃血 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		_s._over = false
		var c6: Dictionary = _mk(400.0, 400.0, "left")
		c6["equips"] = [{"id": "p2eq_055", "star": si + 1}]
		c6["eq_state"] = {}
		_s._units.append(c6)
		var e6: Dictionary = _mk(700.0, 400.0, "right")
		e6["maxHp"] = 10000.0
		e6["hp"] = 10000.0
		_s._units.append(e6)
		## 未到阈值 ⇒ 不许挂弹(这条先立着, 下一条才证明"到了就挂")
		c6["_st_dealt"] = EXP_TRIGGER_DMG - 1
		_s._equip_tick_sys._tick_targeter(c6, 0.1)
		_ok("⑥ ★★★没到 %d 点累计伤害时不挂弹(hookbomb_pct = %.3f)"
			% [EXP_TRIGGER_DMG, float(e6.get("hookbomb_pct", 0.0))],
			float(e6.get("hookbomb_pct", 0.0)) <= 0.0,
			"文案: 本场累计造成 400 点伤害后才发钩索炸弹")
		c6["_st_dealt"] = EXP_TRIGGER_DMG
		_s._equip_tick_sys._tick_targeter(c6, 0.1)
		_ok("⑥ ★★★够 %d 点后挂上了炸弹(每秒 %.0f%% 目标最大生命, 文案 %.0f%%)"
			% [EXP_TRIGGER_DMG, float(e6.get("hookbomb_pct", 0.0)) * 100.0,
			   EXP_BOMB_PCT[si] * 100.0],
			absf(float(e6.get("hookbomb_pct", 0.0)) - EXP_BOMB_PCT[si]) < 0.001)
		## 推 1 秒 ⇒ 宿主掉 pct × maxHp
		var h6: float = float(e6["hp"])
		_advance(1.05)
		var lost6: float = h6 - float(e6["hp"])
		var want6: float = float(e6["maxHp"]) * EXP_BOMB_PCT[si]
		_ok("⑥ ★★★推 1 秒宿主掉 %.0f(应约 %.0f = %.0f%% 最大生命; 物理伤会被护甲削, 靶子护甲 0)"
			% [lost6, want6, EXP_BOMB_PCT[si] * 100.0],
			lost6 > want6 * 0.7 and lost6 < want6 * 1.6,
			"文案: 每 1 秒对其造成 3/6/6%% 其最大生命值的物理伤害")
		## "首次" —— 同一件不许再挂第二次
		c6["_st_dealt"] = EXP_TRIGGER_DMG * 10
		var e6b: Dictionary = _mk(760.0, 400.0, "right")
		_s._units.append(e6b)
		_s._equip_tick_sys._tick_targeter(c6, 0.1)
		_ok("⑥ ★★同一件只挂一次(新来的敌人没被挂: %.3f)" % float(e6b.get("hookbomb_pct", 0.0)),
			float(e6b.get("hookbomb_pct", 0.0)) <= 0.0,
			"文案: 本场累计造成 400 点伤害后(首次)")

	# ══════════════ 057 狙击: 蓄力锁定的目标就是开枪打的那个 ══════════════
	## ★★这一条钉住 2026-09-14 的修复: 原来蓄力时选最低血画瞄准线, 1 秒后开火**重新选一遍**,
	##   这一秒里谁掉了血枪就打到别人身上, 而玩家看到的线一直指着原来那个。
	_s._units.clear()
	_s._pending_shots.clear()
	_s._over = false
	var c7: Dictionary = _mk(300.0, 400.0, "left")
	_s._units.append(c7)
	var a7: Dictionary = _mk(700.0, 400.0, "right")      # 蓄力时它最低血 ⇒ 会被锁定
	a7["hp"] = 5000.0
	var b7: Dictionary = _mk(700.0, 600.0, "right")      # 另一条线上, 不在 a7 那条直线上
	b7["hp"] = 90000.0
	_s._units.append(a7)
	_s._units.append(b7)
	var ha7: float = float(a7["hp"])
	ES._eq_sniper_charge_then_fire(c7, 2, 0)
	## 蓄力这 1 秒里把 b7 打成全场最低血 —— 旧代码会改打 b7
	b7["hp"] = 10.0
	var hb7_after_set: float = float(b7["hp"])   # ★基线要在**我改完血之后**取, 否则打印出来的
	_advance(1.3)                                #   "b 掉了多少"里混着我自己写的那一下, 会骗读日志的人
	_ok("⑦ ★★★打的是**蓄力时锁定的那个**(锁定的 a 掉 %.0f; 蓄力期间被我压成全场最低血的 b 掉 %.0f)"
		% [ha7 - float(a7["hp"]), hb7_after_set - float(b7["hp"])],
		ha7 - float(a7["hp"]) > 0.0,
		"旧代码会在开火时**重新选一遍**最低血 ⇒ 改打 b(它在另一条线上), a 一点不掉")
	_ok("⑦ ★★分母: a 与 b 不在同一条直线上(a y=%.0f / b y=%.0f)" % [float(a7["pos"].y), float(b7["pos"].y)],
		absf(float(a7["pos"].y) - float(b7["pos"].y)) > 100.0,
		"若在同一条线上, 打谁都会把两个都扫到 ⇒ 上面那条就分辨不出来了")

	# ══════════════ 060 磷光水母伞: 开伞给减伤 + 闪避, 收伞回血 ══════════════
	for si in [0, 2]:
		_s._units.clear()
		_s._over = false
		var c8: Dictionary = _mk(400.0, 400.0, "left")
		c8["equips"] = [{"id": "p2eq_060", "star": si + 1}]
		c8["eq_state"] = {}
		_s._units.append(c8)
		var near8: Dictionary = _mk(400.0 + EXP_PARASOL_R * 0.5, 400.0, "left")   # 伞内
		var far8: Dictionary = _mk(400.0 + EXP_PARASOL_R * 3.0, 400.0, "left")    # 伞外
		_s._units.append(near8)
		_s._units.append(far8)
		var st8: Dictionary = {}
		ES._spirit_sys._parasol_open(c8, si, st8)
		_ok("⑦ ★★★%d 星开伞: 伞内队友拿到 %.0f%% 减伤(文案 %.0f%%)"
			% [si + 1, float(near8.get("damage_reduction", 0.0)) * 100.0, EXP_PARASOL_DR[si] * 100.0],
			absf(float(near8.get("damage_reduction", 0.0)) - EXP_PARASOL_DR[si]) < 0.001)
		_s._recalc_stats(near8)
		_ok("⑦ ★★★伞内队友拿到 %.0f%% 闪避(文案 %.0f%%)"
			% [float(near8.get("dodge_bonus", 0.0)) * 100.0, EXP_PARASOL_DODGE * 100.0],
			absf(float(near8.get("dodge_bonus", 0.0)) - EXP_PARASOL_DODGE) < 0.001)
		_ok("⑦ ★★★分母: **伞外**的队友一点都没拿到(减伤 %.2f / 闪避 %.2f 应都是 0)"
			% [float(far8.get("damage_reduction", 0.0)), float(far8.get("dodge_bonus", 0.0))],
			absf(float(far8.get("damage_reduction", 0.0))) < 0.001
				and absf(float(far8.get("dodge_bonus", 0.0))) < 0.001,
			"没有这一条, 半径 %.0f 码写成无穷大也照样绿" % EXP_PARASOL_R)

	print("---- %d 条, 失败 %d ----" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS — 052~061 第六批")
	else:
		print("有 %d 条 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
