extends Node
## verify_gremlin_gun.gd — 古灵精怪枪 + FPGA板登场塞枪 (2026-08-31·二期)
##
## ★需求原文(用户 2026-08-31):
##   「PFGA板加个新效果：登场时给对方随机1/2/3个敌人提供1把古灵精怪枪。」
##   「古灵精怪枪：提供1攻击力，1生命值，1攻击速度。
##     携带者每次普攻会使自己受到1%最大生命值真实伤害。」
##   已拍板: ①「1攻击速度」= **+1%**（不是 +1 次/秒）· ⑤ 自伤**能打死**携带者。
##
## ★★这份门禁里最容易写假的三条, 各自的陷阱写在断言旁边:
##   · 「+1% 攻速」—— 只断言 `aspd_perm` 变大是没用的, +1 和 +0.01 都会变大。
##   · 「真实伤害」—— 拿一个没抗性的假人测, 真伤和物理给出同一个数, 判不出来。
##   · 「FPGA 给的是对方」—— 只数"有几个人拿到枪"的话, 全给自己人也照样绿。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const GG := preload("res://scripts/systems/equip/gremlin_gun.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk(side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", side, c + off)
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 古灵精怪枪 / FPGA板登场塞枪 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── ① 分母: 常量表就是需求给的字面值 ──
	_ok("★分母: 一把枪 = +%.0f攻击 / +%.0f生命 / +%.0f%%攻速; 自伤 %.0f%%最大生命"
			% [GG.ATK_PER_GUN, GG.HP_PER_GUN, GG.ASPD_PCT_PER_GUN * 100.0, GG.SELF_TRUE_PCT * 100.0],
		GG.ATK_PER_GUN == 1.0 and GG.HP_PER_GUN == 1.0
			and absf(GG.ASPD_PCT_PER_GUN - 0.01) < 1e-9 and absf(GG.SELF_TRUE_PCT - 0.01) < 1e-9)
	_ok("★分母: FPGA 逐星塞 %s 把" % str(ES.FPGA_GUNS), ES.FPGA_GUNS == [1, 2, 3])

	# ── ② 给一把: 三项属性各加多少(逐项量差值, 不是"变大了就行") ──
	_s._units.clear()
	var u: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	var a0: float = float(u["atk"])
	var m0: float = float(u["maxHp"])
	var h0: float = float(u["hp"])
	var s0: float = float(u.get("aspd_perm", 1.0))
	var cnt: int = _s._equip_sys._gremlin.give(u)
	_ok("给一把后 gremlin_guns = 1", cnt == 1 and int(u.get("gremlin_guns", 0)) == 1,
		"cnt=%d" % cnt)
	_ok("+1 攻击力", absf(float(u["atk"]) - a0 - 1.0) < 1e-6, "%.2f→%.2f" % [a0, float(u["atk"])])
	_ok("+1 最大生命(且当前血同步涨, 不是白给个上限)",
		absf(float(u["maxHp"]) - m0 - 1.0) < 1e-6 and absf(float(u["hp"]) - h0 - 1.0) < 1e-6,
		"maxHp %.1f→%.1f  hp %.1f→%.1f" % [m0, float(u["maxHp"]), h0, float(u["hp"])])
	## ★★这一条必须量【差值等于 0.01】—— 只判"aspd_perm 变大了"的话,
	##   把 +1% 写成字面的 +1(每秒多一次攻击)也照样绿, 而那正是未决点 ① 要防的错。
	_ok("★★攻速 = +1%(不是 +1 次/秒): aspd_perm 差值恰好 0.01",
		absf(float(u["aspd_perm"]) - s0 - 0.01) < 1e-9,
		"%.4f→%.4f 差 %.4f" % [s0, float(u["aspd_perm"]), float(u["aspd_perm"]) - s0])

	# ── ③ 可叠加 ──
	_s._equip_sys._gremlin.give(u)
	_ok("再给一把可叠加: 2 把 → 攻击 +2、攻速 +2%",
		int(u["gremlin_guns"]) == 2 and absf(float(u["atk"]) - a0 - 2.0) < 1e-6
			and absf(float(u["aspd_perm"]) - s0 - 0.02) < 1e-9,
		"guns=%d atk=%.1f aspd_perm=%.4f" % [int(u["gremlin_guns"]), float(u["atk"]), float(u["aspd_perm"])])

	# ── ④ 自伤: 只有普攻算, 且按当前最大生命的 1% ──
	_s._units.clear()
	var v: Dictionary = _mk("left", Vector2(-120.0, 40.0))
	var w: Dictionary = _mk("right", Vector2(120.0, 40.0))
	_s._equip_sys._gremlin.give(v)
	v["maxHp"] = 2000.0
	v["hp"] = 2000.0
	_ok("★纯函数: 2000 血 × 1% × 1 把 = 20", absf(_s._equip_sys._gremlin.self_damage(v) - 20.0) < 1e-6,
		"%.2f" % _s._equip_sys._gremlin.self_damage(v))
	var vh: float = float(v["hp"])
	_s._equip_sys._gremlin.on_hit(v, false)                 # 非普攻
	_s._damage._heal_flush(v)
	_ok("★非普攻不自伤(与 002/023/026 同口径)", absf(float(v["hp"]) - vh) < 0.01,
		"hp %.1f→%.1f" % [vh, float(v["hp"])])
	_s._equip_sys._gremlin.on_hit(v, true)                  # 普攻
	_s._damage._heal_flush(v)
	_ok("普攻自伤 20 点", absf(vh - float(v["hp"]) - 20.0) < 0.51,
		"掉 %.1f" % (vh - float(v["hp"])))
	## ★没枪的人一点都不掉 —— 分母, 防"这段代码对谁都生效"
	var wh: float = float(w["hp"])
	_s._equip_sys._gremlin.on_hit(w, true)
	_s._damage._heal_flush(w)
	_ok("★分母: 没枪的单位普攻一点都不自伤", absf(float(w["hp"]) - wh) < 0.01,
		"hp %.1f→%.1f" % [wh, float(w["hp"])])

	# ── ⑤ 真实伤害: 把产品真读的减伤通道全拉满, 一点都不许少 ──
	##   ★字段名是 `def` / `flat_dr` / `damage_reduction` —— 上一轮我喂 `armor`/`dr_mult`,
	##     全仓没人读, 那条"是真实伤害"的断言当场被反向验证抓成假的。
	_s._units.clear()
	var t1: Dictionary = _mk("left", Vector2(-120.0, 80.0))
	var t2: Dictionary = _mk("left", Vector2(-120.0, 120.0))
	for t in [t1, t2]:
		_s._equip_sys._gremlin.give(t)
		t["maxHp"] = 2000.0
		t["hp"] = 2000.0
		t["shield"] = 0.0
	t2["def"] = 9999.0
	t2["mr"] = 9999.0
	t2["flat_dr"] = 500.0
	t2["damage_reduction"] = 0.9
	var b1: float = float(t1["hp"])
	var b2: float = float(t2["hp"])
	_s._equip_sys._gremlin.on_hit(t1, true)
	_s._equip_sys._gremlin.on_hit(t2, true)
	_s._damage._heal_flush(t1)
	_s._damage._heal_flush(t2)
	var d1: float = b1 - float(t1["hp"])
	var d2: float = b2 - float(t2["hp"])
	_ok("★★是真实伤害: 护甲/魔抗/固定减伤/百分比减伤全拉满后一点没少",
		d1 > 1.0 and absf(d1 - d2) < 0.51, "无抗掉 %.1f / 满抗掉 %.1f" % [d1, d2])

	# ── ⑥ 能打死携带者(未决点 ⑤ 用户拍板「能打死」) ──
	_s._units.clear()
	var dyer: Dictionary = _mk("left", Vector2(-120.0, 160.0))
	_s._equip_sys._gremlin.give(dyer)
	dyer["maxHp"] = 2000.0
	dyer["shield"] = 0.0
	dyer["hp"] = 5.0                              # 比一次自伤(20)还少
	_s._equip_sys._gremlin.on_hit(dyer, true)
	_s._damage._heal_flush(dyer)
	_ok("★★自伤能把携带者打死(不是留 1 血)",
		not dyer.get("alive", true) or float(dyer["hp"]) <= 0.0,
		"alive=%s hp=%.1f" % [str(dyer.get("alive", true)), float(dyer["hp"])])

	# ── ⑦ FPGA 登场: 给【对方】1/2/3 个【不重复】的敌人 ──
	for si in range(3):
		_s._units.clear()
		var carrier: Dictionary = _mk("left", Vector2(-200.0, 0.0))
		var mates: Array = [_mk("left", Vector2(-200.0, 40.0)), _mk("left", Vector2(-200.0, 80.0))]
		var foes: Array = []
		for k in range(4):
			foes.append(_mk("right", Vector2(200.0, -60.0 + 40.0 * float(k))))
		var given: int = _s._equip_sys._eq_fpga_hand_out_guns(carrier, si)
		var n_foe: int = 0
		var n_dup: int = 0
		for f in foes:
			var g: int = int(f.get("gremlin_guns", 0))
			if g > 0:
				n_foe += 1
			if g > 1:
				n_dup += 1
		## ★★这三条缺一不可:
		##   给的把数对 / 全给了【敌方】 / 【不重复】(同一个人塞两把不算两个敌人)
		var n_ally: int = int(carrier.get("gremlin_guns", 0))
		for m in mates:
			n_ally += int(m.get("gremlin_guns", 0))
		_ok("FPGA si=%d 塞出 %d 把(需求 1/2/3)" % [si, ES.FPGA_GUNS[si]],
			given == ES.FPGA_GUNS[si] and n_foe == ES.FPGA_GUNS[si],
			"返回 %d · 拿到枪的敌人 %d" % [given, n_foe])
		_ok("FPGA si=%d ★★一把都没落到自己人身上(含携带者)" % si, n_ally == 0,
			"己方拿到 %d 把" % n_ally)
		_ok("FPGA si=%d ★不重复: 没有敌人拿到 2 把" % si, n_dup == 0, "重复 %d 人" % n_dup)

	## ★敌人不够时有几个给几个(不许崩、不许死循环)
	_s._units.clear()
	var c2: Dictionary = _mk("left", Vector2(-200.0, 0.0))
	var only1: Dictionary = _mk("right", Vector2(200.0, 0.0))
	var g2: int = _s._equip_sys._eq_fpga_hand_out_guns(c2, 2)   # 3★ 想塞 3 把, 只有 1 个敌人
	_ok("★敌人不够时有几个给几个(3★ 只有 1 个敌人 → 给 1 把)",
		g2 == 1 and int(only1.get("gremlin_guns", 0)) == 1, "给出 %d" % g2)

	# ── ⑧ FPGA 原有效果一条没丢(新增不是替换) ──
	var e40: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_040", {})
	var d40: String = str(e40.get("effectDesc1", ""))
	_ok("★FPGA 原有的 2-bit 四态一条没丢(新增不是替换)",
		d40.find("00=") >= 0 and d40.find("01=") >= 0 and d40.find("10=") >= 0 and d40.find("11=") >= 0,
		"len=%d" % d40.length())

	# ── ⑨ ★★「**扔**」这个动作真的演出来了 ──
	## ★需求原话是「会**扔**给目标一把古灵精怪枪」。原来整条发枪路径
	##   (`_eq_fpga_hand_out_guns`)**一个 vfx 调用都没有** —— 属性静悄悄加上去,
	##   玩家看不到发生过什么。2026-09-01 逐句核对原话时抓到(第 2 句)。
	## ★★判据落在**世界里真的多出了一个会飞的节点**, 不是"我插了个标记":
	##   数 `battle._world` 的子节点增量 —— 那是产品自己的账。
	##   (memory [[fb-gate-must-measure-requirement-not-my-hook]])
	var thrower: Dictionary = _s._spawn._make_unit("basic", "left",
		_s.ARENA.position + _s.ARENA.size * 0.5)
	_s._units.append(thrower)
	var victim: Dictionary = _s._spawn._make_unit("basic", "right",
		_s.ARENA.position + _s.ARENA.size * 0.5 + Vector2(260, 0))
	_s._units.append(victim)
	var n_before: int = _s._world.get_child_count()
	_s._vfx._throw_item(thrower, victim, "gremlin-gun.png", "古灵精怪枪", Color("#8ae06a"))
	var n_after: int = _s._world.get_child_count()
	_ok("★★★扔出去的东西**真的在世界里建出来了**(子节点 %d → %d)" % [n_before, n_after],
		n_after > n_before, "没有增量 = 又是一次'写了没人看见'")
	## ★分母: 缺图时**不画**, 而不是拿别的图顶替(素材不复用铁律)
	var n2: int = _s._world.get_child_count()
	_s._vfx._throw_item(thrower, victim, "__不存在的图__.png", "x", Color.WHITE)
	_ok("★分母: 图不存在时不画(也不拿别的图顶替)",
		_s._world.get_child_count() == n2, "凭空多了节点")
	## ★素材真的在盘上, 且**不是**复用别件装备的图
	_ok("★★古灵精怪枪有自己的新素材(不复用 eq-pistol-idle / conch-shotgun)",
		ResourceLoader.exists("res://assets/sprites/vfx/gremlin-gun.png"))
	## ★发枪的产品入口真的调了它 —— 不是只有门禁在调(零调用者那一整类)
	var src40: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var seg: int = src40.find("func _eq_fpga_hand_out_guns")
	var seg_end: int = src40.find("func ", seg + 10)
	_ok("★★★发枪的产品入口里真的调了 _throw_item(分母: 函数体 %d 字)"
		% maxi(0, seg_end - seg),
		seg >= 0 and seg_end > seg
		and src40.substr(seg, seg_end - seg).contains("_throw_item("))

	if _n < 24:
		print("  [FAIL] ★分母: 断言只有 %d 条(<24)" % _n)
		_fail += 1
	print("ALL PASS — 古灵精怪枪/FPGA" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
