extends Node
## verify_synergy_rest5.gd — 剩下五个类型的羁绊机制真的生效（2026-08-03）
##
## 药水【猎物/战利品/斩首】· 奇械【铸币/冰封/僵硬/易碎】· 食物【成长/学院】
## 灵物【触手/闪避追击/亡灵】· 遗物【生死界/远古之力/龟蛋加固/觉醒】
##
## ★这五个类型之前**只有属性生效**，十条主动机制一条都没实装。
##   所以本门禁一条都不验"函数在不在"，全部验**单位字典/场上状态真的变了**
##   （memory [[fb-verify-must-run-the-real-path]]）。
##
## ★期望值一律**写死字面数**，不读被测常量 —— 读常量就是恒真式，
##   改数值时两边一起变、门禁照样全绿（法器那次实测变异 0 FAIL，见 verify_staff_synergy 注释）。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_rest5.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 剩下五个类型的羁绊机制 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var po: Array = _ids("药水", 9)
	var ga: Array = _ids("奇械", 10)
	var fo: Array = _ids("食物", 9)
	var sp: Array = _ids("灵物", 10)
	var re: Array = _ids("遗物", 10)
	_ok("★分母: 药水%d 奇械%d 食物%d 灵物%d 遗物%d(各需 9/10/9/10/10 件才验得了顶档)"
		% [po.size(), ga.size(), fo.size(), sp.size(), re.size()],
		po.size() >= 9 and ga.size() >= 10 and fo.size() >= 9 and sp.size() >= 10 and re.size() >= 10)

	# ═══════════════ 药水 ═══════════════
	print("── 药水 ──")
	# 对照: 未激活(2 件, 首档 3) → 不选猎物
	var p0 := _run([_mk("left", po.slice(0, 2)), _mk("right", [])])
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	_ok("★对照: 药水未激活(2 件) → 不选猎物", not _s._potion_syn.is_prey_of("left", p0[1]))

	# 首档: 敌方血最高的那只被标为猎物
	var pa := _run([_mk("left", po.slice(0, 3)), _mk("right", []), _mk("right", [])])
	pa[1]["hp"] = 1000.0
	pa[2]["hp"] = 2500.0                          # 这只血最高
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	_ok("猎物 = 敌方【当前生命值最高】的那只(2500 那只, 不是 1000 那只)",
		_s._potion_syn.is_prey_of("left", pa[2]) and not _s._potion_syn.is_prey_of("left", pa[1]))
	_ok("猎物增伤 ×1.15(首档 +15%)", absf(_s._potion_syn.amp_for(pa[0], pa[2]) - 1.15) < 0.001,
		"×%.3f" % _s._potion_syn.amp_for(pa[0], pa[2]))
	_ok("★非猎物不增伤 ×1.00", absf(_s._potion_syn.amp_for(pa[0], pa[1]) - 1.0) < 0.001)

	# ── 属性: 治疗强度 / 护盾强度 + 一点点初始龟能(用户 2026-08-04 定) ──
	# ★原来这栏是纯 `_maxEnergy` 5/11/20。但龟能在实时版【不是资源, 是逐技冷却】——
	#   它唯一的作用是开局把各技冷却各减 `龟能 × 0.075` 秒, 【一次性】。
	#   顶档 3 件 = 4.5 秒, 之后再无影响; 而玩家看文案写着"+20 最大龟能",
	#   根本不知道那等于 1.5 秒。⇒ 主属性换成治疗/护盾强度, 龟能只留一点点。
	var pe: Dictionary = _run([_mk("left", po.slice(0, 3))])[0]
	_ok("药水属性: 带 3 件(首档) → 治疗强度 +18%(每件 6%)",
		absf(float(pe.get("heal_amp", 0.0)) - 0.18) < 0.001, "heal_amp=%.3f" % float(pe.get("heal_amp", 0.0)))
	_ok("药水属性: 护盾强度 +18%(每件 6%)",
		absf(float(pe.get("shield_amp", 0.0)) - 0.18) < 0.001, "shield_amp=%.3f" % float(pe.get("shield_amp", 0.0)))
	_ok("药水属性: 仍留一点点初始龟能(每件 2 → 带 3 件 = 6 ≈ 开局各技冷却 -0.45 秒)",
		absf(float(pe.get("init_energy_bonus", 0.0)) - 6.0) < 0.001,
		"init_energy_bonus=%.1f" % float(pe.get("init_energy_bonus", 0.0)))
	# ★真的作用在【结算】上, 不只是字段好看
	pe["hp"] = float(pe["maxHp"]) * 0.5
	pe["shield"] = 0.0
	var _hb: float = float(pe["hp"])
	_s._damage._heal(pe, 100.0)
	_ok("治疗强度真的生效: 回 100 → 实收 118", absf(float(pe["hp"]) - _hb - 118.0) < 1.0,
		"实收 %.1f" % (float(pe["hp"]) - _hb))
	_s._damage._grant_shield(pe, 100.0)
	_ok("护盾强度真的生效: 给 100 盾 → 实得 118", absf(float(pe["shield"]) - 118.0) < 1.0,
		"实得 %.1f" % float(pe["shield"]))

	# 战利品: 档2(6 件) 击杀猎物 → 全队 +5 攻
	var pb := _run([_mk("left", po.slice(0, 3)), _mk("left", po.slice(3, 6)), _mk("right", [])])
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	var atk_b: float = float(pb[0]["base_atk"])
	_s._potion_syn.on_death(pb[2])
	_ok("战利品(档2): 猎物阵亡 → 全队 base_atk +5(不要求击杀者带药水)",
		absf(float(pb[0]["base_atk"]) - atk_b - 5.0) < 0.01
		and absf(float(pb[1]["base_atk"]) - atk_b - 5.0) < 0.01,
		"%.0f → %.0f / %.0f" % [atk_b, float(pb[0]["base_atk"]), float(pb[1]["base_atk"])])
	_ok("★档1 没有战利品(HARVEST_ATK[0]=0)", _potion_harvest_tier1(po))

	# ── ★战利品【以场重置】(用户 2026-08-04:「改」) ──────────────
	# 和食物成长同一件事: 只写单位字典的话每换一路都打回原形。
	# 这里【真的模拟一次换路】: 丢掉旧字典、造一批全新的同名单位, 再看攻击力在不在。
	_s._potion_syn.reset_match()
	var hv := _run([_mk("left", po.slice(0, 3)), _mk("left", po.slice(3, 6)), _mk("right", [])])
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	_s._potion_syn.on_death(hv[2])                 # 杀 1 只猎物 → 全队 +5
	_ok("★换路前: 上路杀 1 猎物 → +5 攻", absf(float(hv[0]["base_atk"]) - 105.0) < 0.01,
		"base_atk=%.0f" % float(hv[0]["base_atk"]))
	var hv2 := _run([_mk("left", po.slice(0, 3)), _mk("left", po.slice(3, 6))])
	var hb_fresh: float = float(hv2[0]["base_atk"])
	_s._potion_syn.restore()
	_ok("★换路后: 上一路攒的 +5 真的重放回来了(以场重置)",
		absf(float(hv2[0]["base_atk"]) - hb_fresh - 5.0) < 0.01,
		"%.0f → %.0f" % [hb_fresh, float(hv2[0]["base_atk"])])
	_s._potion_syn.restore()
	_ok("★同一路里 restore 调两次不叠", absf(float(hv2[0]["base_atk"]) - hb_fresh - 5.0) < 0.01,
		"base_atk=%.0f" % float(hv2[0]["base_atk"]))
	_ok("★整场结束 reset_match() 后清零", _harvest_reset_clears(po))

	# 斩首: 顶档(9 件) 猎物 <20% 血 → 处决
	var pc := _run([_mk("left", po.slice(0, 3)), _mk("left", po.slice(3, 6)),
		_mk("left", po.slice(6, 9)), _mk("right", [])])
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	pc[3]["hp"] = float(pc[3]["maxHp"]) * 0.15
	var beheaded: bool = _s._potion_syn.try_behead(pc[0], pc[3])
	_ok("斩首(顶档): 猎物血 15% < 20% → 直接处决", beheaded and float(pc[3]["hp"]) <= 0.0,
		"beheaded=%s hp=%.0f" % [str(beheaded), float(pc[3]["hp"])])
	var pd := _run([_mk("left", po.slice(0, 3)), _mk("left", po.slice(3, 6)),
		_mk("left", po.slice(6, 9)), _mk("right", [])])
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	pd[3]["hp"] = float(pd[3]["maxHp"]) * 0.25
	_ok("★斩首不越线: 血 25% > 20% → 不处决", not _s._potion_syn.try_behead(pd[0], pd[3]))

	# ═══════════════ 奇械 ═══════════════
	print("── 奇械 ──")
	var g0 := _run([_mk("left", ga.slice(0, 1))])
	_s._gadget_syn.reset_match()
	_s._gadget_syn._t_coin = 0.0
	_s._gadget_syn.tick(2.6)
	_ok("★对照: 奇械未激活(1 件, 首档 2) → 一枚都不铸", _s._gadget_syn.minted("left") == 0,
		"铸了 %d 枚" % _s._gadget_syn.minted("left"))

	var g1 := _run([_mk("left", ga.slice(0, 2))])
	_s._gadget_syn.reset_match()
	for i in range(9):
		_s._gadget_syn._t_coin = 0.0
		_s._gadget_syn.tick(2.6)
	_ok("铸币(首档): 每跳 1 枚, 跳 9 次但【本场上限 5 枚】→ 停在 5",
		_s._gadget_syn.minted("left") == 5, "铸了 %d 枚" % _s._gadget_syn.minted("left"))
	var g2 := _run([_mk("left", ga.slice(0, 5))])
	_s._gadget_syn.reset_match()
	for i2 in range(20):
		_s._gadget_syn._t_coin = 0.0
		_s._gadget_syn.tick(2.6)
	_ok("铸币(档2): 每跳 2 枚, 上限 9 枚", _s._gadget_syn.minted("left") == 9,
		"铸了 %d 枚" % _s._gadget_syn.minted("left"))

	# 僵硬: 档3(8 件) 每次命中叠 1 层, 20 层 = ×0.60 攻击力
	var g3 := _run([_mk("left", ga.slice(0, 8)), _mk("right", [])])
	var foe: Dictionary = g3[1]
	var fa0: float = float(foe["atk"])
	for i3 in range(25):
		_s._gadget_syn.on_hit(g3[0], foe)
	_ok("僵硬(档3): 叠到 20 层封顶(打了 25 次)", int(foe.get("stiff_stacks", 0)) == 20,
		"%d 层" % int(foe.get("stiff_stacks", 0)))
	_ok("僵硬 20 层 → 攻击力 ×0.60", absf(float(foe["atk"]) - fa0 * 0.60) < 0.5,
		"%.1f → %.1f (期望 %.1f)" % [fa0, float(foe["atk"]), fa0 * 0.60])
	_s._gadget_syn._expire_stiff()
	_ok("★僵硬未到期不清(5 秒内)", int(foe.get("stiff_stacks", 0)) == 20)
	foe["stiff_until"] = _s._t - 1.0
	_s._gadget_syn._expire_stiff()
	_ok("僵硬到期 → 层数清零且攻击力还原",
		int(foe.get("stiff_stacks", 0)) == 0 and absf(float(foe["atk"]) - fa0) < 0.5,
		"atk=%.1f (原 %.1f)" % [float(foe["atk"]), fa0])
	# 档2(5 件) 没有僵硬
	var g4 := _run([_mk("left", ga.slice(0, 5)), _mk("right", [])])
	for i4 in range(5):
		_s._gadget_syn.on_hit(g4[0], g4[1])
	_ok("★档2 没有僵硬(STIFF_TIER=3)", int(g4[1].get("stiff_stacks", 0)) == 0,
		"%d 层" % int(g4[1].get("stiff_stacks", 0)))

	# 易碎: 顶档(10 件) 对被眩晕的敌人 ×1.25
	var g5 := _run([_mk("left", ga.slice(0, 10)), _mk("right", [])])
	_ok("★易碎: 敌人【没被控】时不增伤 ×1.00",
		absf(_s._gadget_syn.brittle_mult(g5[1]) - 1.0) < 0.001)
	g5[1]["stun_until"] = _s._t + 5.0
	_ok("易碎(顶档): 被眩晕/冻结的敌人受伤 ×1.25",
		absf(_s._gadget_syn.brittle_mult(g5[1]) - 1.25) < 0.001,
		"×%.3f" % _s._gadget_syn.brittle_mult(g5[1]))
	var g6 := _run([_mk("left", ga.slice(0, 8)), _mk("right", [])])
	g6[1]["stun_until"] = _s._t + 5.0
	_ok("★档3 没有易碎(BRITTLE_TIER=4)", absf(_s._gadget_syn.brittle_mult(g6[1]) - 1.0) < 0.001)

	# ═══════════════ 食物 ═══════════════
	print("── 食物 ──")
	var f0 := _run([_mk("left", fo.slice(0, 2))])
	_s._food_syn.apply_all()
	var mh0: float = float(f0[0]["maxHp"])
	_s._food_syn._t_grow = 0.0
	_s._food_syn.tick(2.6)
	_ok("★对照: 食物未激活(2 件, 首档 3) → 不长血",
		absf(float(f0[0]["maxHp"]) - mh0) < 0.01)

	# 首档 3 件: 每件食物每跳 +8 → 带 3 件 = +24
	var f1 := _run([_mk("left", fo.slice(0, 3))])
	var mh1: float = float(f1[0]["maxHp"])
	var hp1: float = float(f1[0]["hp"])
	_s._food_syn._t_grow = 0.0
	_s._food_syn.tick(2.6)
	_ok("成长(首档): 带 3 件食物, 一跳 +24 最大生命(8 × 3)",
		absf(float(f1[0]["maxHp"]) - mh1 - 24.0) < 0.01,
		"%.0f → %.0f" % [mh1, float(f1[0]["maxHp"])])
	_ok("★成长同时加【当前生命】(否则每跳血条百分比往下掉)",
		absf(float(f1[0]["hp"]) - hp1 - 24.0) < 0.01)
	# 不带食物的队友不长血
	var f2 := _run([_mk("left", fo.slice(0, 3)), _mk("left", [])])
	var mh2: float = float(f2[1]["maxHp"])
	_s._food_syn._t_grow = 0.0
	_s._food_syn.tick(2.6)
	_ok("★成长是【携带者】: 不带食物的队友一点不长",
		absf(float(f2[1]["maxHp"]) - mh2) < 0.01)

	# ── ★成长【以场重置, 不是以路重置】(用户 2026-08-04) ────────────
	# 换路会 `_dl_clear_units()` + `_make_unit()` 重建单位字典 ⇒ 只写在字典上的累积
	# 连字典一起没了。这里【真的模拟一次换路】: 丢掉旧字典、造全新的同名单位, 再看血在不在。
	# ⚠ 断言"restore 函数存在"守不住这件事 —— 那是 memory [[fb-verify-must-run-the-real-path]]
	#   反复踩过的坑; 必须量重建【之后】的 maxHp。
	_s._food_syn.reset_match()
	var fc := _run([_mk("left", fo.slice(0, 3))])
	_s._food_syn.restore()                     # 贴身份键(开战时那一步)
	for _i in range(5):
		_s._food_syn._t_grow = 0.0
		_s._food_syn.tick(2.6)                 # 上路攒 5 跳 = 5 × 24 = 120
	var grown: float = float(fc[0]["_food_grown"])
	_ok("★换路前: 上路攒了 120 最大生命(5 跳 × 24)", absf(grown - 120.0) < 0.01, "攒了 %.0f" % grown)
	# ★真·换路: 旧字典整个丢掉, 造一批【全新的】同名单位(和 _dl_build_lane_field 一样)
	var fd := _run([_mk("left", fo.slice(0, 3))])
	_ok("★对照: 新建的单位本身是干净的(没带任何成长)",
		absf(float(fd[0].get("_food_grown", 0.0))) < 0.01)
	var mh_fresh: float = float(fd[0]["maxHp"])
	_s._food_syn.restore()
	_ok("★换路后: 上一路攒的 120 真的重放回来了(以场重置, 不是以路)",
		absf(float(fd[0]["maxHp"]) - mh_fresh - 120.0) < 0.01,
		"%.0f → %.0f" % [mh_fresh, float(fd[0]["maxHp"])])
	_ok("★整场结束 reset_match() 后清零(下一场重新开始)", _food_reset_clears(fo))

	# 学院(档2, 6 件): 全队 +100, 不带食物的也吃
	var f3 := _run([_mk("left", fo.slice(0, 3)), _mk("left", fo.slice(3, 6)), _mk("left", [])])
	var a_before: float = float(f3[2]["maxHp"])
	_s._food_syn.apply_all()
	_ok("学院(档2): 全队 +100 最大生命(不带食物的队友也吃)",
		absf(float(f3[2]["maxHp"]) - a_before - 100.0) < 0.01,
		"%.0f → %.0f" % [a_before, float(f3[2]["maxHp"])])
	var a_mid: float = float(f3[2]["maxHp"])
	_s._food_syn.apply_all()
	_ok("★学院只加【一次】(apply_all 调两遍不叠)",
		absf(float(f3[2]["maxHp"]) - a_mid) < 0.01, "%.0f" % float(f3[2]["maxHp"]))

	# ═══════════════ 灵物 ═══════════════
	print("── 灵物 ──")
	var s0 := _run([_mk("left", sp.slice(0, 1)), _mk("right", [])])
	var sh0: float = float(s0[1]["hp"])
	_s._spirit_syn._t_slap = 0.0
	_s._spirit_syn.tick(5.1)              # 拍击周期是 5 秒(用户 2026-08-04 定), 不是 2.5
	_ok("★对照: 灵物未激活(1 件, 首档 2) → 触手不拍",
		absf(float(s0[1]["hp"]) - sh0) < 0.01)

	# 首档(2 件): 1 个触手, 伤害 = 4% 目标 maxHp + 55 = 0.04×3000+55 = 175
	var s1 := _run([_mk("left", sp.slice(0, 2)), _mk("right", [])])
	var sh1: float = float(s1[1]["hp"])
	## ★先让触手真的站稳: `_spirit_syn.tick()` 会建触手, 但出土(T_EMERGE = 2 秒)
	##   期间 `strike()` 直接 return。而演出层的 tick 是主循环喂的, 这里得自己喂。
	##   (改之前伤害不管演出照打, 所以这个坑一直被盖着。)
	_s._spirit_syn.tick(0.01)
	for _e in range(30):
		_s._tentacle_vfx.tick(0.12)
	_s._spirit_syn._t_slap = 0.0
	_s._spirit_syn.tick(5.1)              # 拍击周期是 5 秒(用户 2026-08-04 定), 不是 2.5
	## ★★ 2026-08-10 拍击改成【延后到视觉命中那一刻】才结算(方案 A):
	##   伤害不再在 `_slap()` 里立即打出, 而是等 T_WARN + T_REAR = 1.13 秒。
	##   原因: 改之前**伤害比视觉命中早 1.13 秒**, 预警圈彻底成了摆设。
	##   ★同步推一次待发队列即可, 不等帧也不等 tween ⇒ 仍然是确定性断言。
	## ★2026-08-22: 拍击伤害改挂在触手自己的"梢端触地"标志上(原走 _queue_shots 这条会漂的
	##   第二时钟, 实测一场里 13% 的拍击完整演出零伤害)。推进手柄换成 tv.tick, 小步喂
	##   (状态机要逐段过 WARN→REAR→SLAM)。判据(伤害数值)一个字没改。
	var _d5: float = _s._tentacle_vfx.hit_delay(1.0) + 0.05
	var _n5: int = maxi(1, int(ceil(_d5 / 0.01)))
	for _i5 in range(_n5):
		_s._tentacle_vfx.tick(_d5 / float(_n5))
	var dealt: float = sh1 - float(s1[1]["hp"])
	# ★期望值写死。原来写的是"100~260 之间"——太松: 把基数改小实伤仍落在区间内, 变异实测 0 FAIL。
	# ★2026-08-20 用户改数值:「拍击伤害为目标5%最大生命值+100物理伤害」(原 4% + 55),
	#   且「这是物理伤害就要按规则走啊」⇒ 现在**过 `_resolve_dmg` 吃护甲**。
	#   ⇒ 期望值不再写死一个数, 而是**拿产品自己的公式当基准**: 同一份 raw 喂 `_resolve_dmg`,
	#     断言实掉 == 它。这样以后再加任何一条物理修正, 这条断言自动跟上(比抄一遍公式强)。
	var _want_base: float = 3000.0 * _s._spirit_syn.HIT_HP_PCT + _s._spirit_syn.HIT_FLAT
	var _want: float = float(maxi(1, int(_s._resolve_dmg(s1[0], _want_base, s1[1], false) * 1.0)))
	_ok("触手(首档): 拍击 = (5%%×3000 + 100) 过物理减免 = %.0f" % _want, absf(dealt - _want) < 2.0,
		"实掉 %.0f / 期望 %.0f" % [dealt, _want])
	_ok("★触手数(首档 1 / 档2 起 2)",
		_s._spirit_syn.TENTACLES[0] == 1 and _s._spirit_syn.TENTACLES[1] == 2)

	# 【闪避蓄能】★2026-08-20 用户改机制: 闪避不再"立刻打 25 折追击", 而是**给每根触手 +1 层**;
	#   「任何一只」闪避都算、**不设上限**、5 件及以上才有。
	#   判据量的是**产品自己的层数账**(stack_of), 不是我插的标记。
	var s2 := _run([_mk("left", sp.slice(0, 3)), _mk("left", sp.slice(3, 5)), _mk("right", [])])
	_s._spirit_syn._stacks.clear()
	for i5 in range(8):
		_s._spirit_syn.on_dodge(s2[0] if i5 % 2 == 0 else s2[1])
	_ok("闪避蓄能(档2): 8 次闪避 = 8 层(不设上限)",
		_s._spirit_syn.stack_of("left", 0) == 8,
		"第0根 %d 层" % _s._spirit_syn.stack_of("left", 0))
	_ok("★每根触手各自一份(第1根也拿到 8 层)",
		_s._spirit_syn.stack_of("left", 1) == 8,
		"第1根 %d 层" % _s._spirit_syn.stack_of("left", 1))
	# 档1(2 件) 闪避不给层
	var s3 := _run([_mk("left", sp.slice(0, 2)), _mk("right", [])])
	_s._spirit_syn._stacks.clear()
	_s._spirit_syn.on_dodge(s3[0])
	_ok("★首档(2 件)闪避不给层(DODGE_STACK_MIN_TIER=2)",
		_s._spirit_syn.stack_of("left", 0) == 0,
		"%d 层" % _s._spirit_syn.stack_of("left", 0))

	# 亡灵: 首档(2 件) 阵亡 → 召唤亡魂, 继承 20%
	var s4 := _run([_mk("left", sp.slice(0, 2)), _mk("left", [])])
	var dead: Dictionary = s4[1]
	dead["maxHp"] = 1000.0
	dead["base_atk"] = 200.0
	dead["alive"] = false
	var n_before: int = _s._units.size()
	_s._spirit_syn.on_death(dead)
	_ok("亡灵(首档): 友方阵亡 → 场上多一只亡魂", _s._units.size() == n_before + 1,
		"%d → %d" % [n_before, _s._units.size()])
	var wr = _s._units[_s._units.size() - 1] if _s._units.size() > n_before else null
	_ok("亡魂继承 20%% 攻击力与生命(200→40 / 1000→200)",
		wr is Dictionary and absf(float(wr.get("maxHp", 0.0)) - 200.0) < 1.0,
		"maxHp=%.0f" % (float(wr.get("maxHp", 0.0)) if wr is Dictionary else -1.0))
	_ok("★首档亡魂死了【不再循环】(WRAITH_LOOPS[0]=0)",
		wr is Dictionary and int(wr.get("_wraith_loops", -1)) == 0,
		"loops=%d" % (int(wr.get("_wraith_loops", -1)) if wr is Dictionary else -1))
	var n_after: int = _s._units.size()
	if wr is Dictionary:
		wr["alive"] = false
		_s._spirit_syn.on_death(wr)
	_ok("★亡魂阵亡不再生新亡魂(首档) —— 否则是无限循环",
		_s._units.size() == n_after, "%d → %d" % [n_after, _s._units.size()])
	# 龟蛋不召唤
	var s5 := _run([_mk("left", sp.slice(0, 2)), _mk("left", [])])
	s5[1]["_isEgg"] = true
	s5[1]["alive"] = false
	var n2: int = _s._units.size()
	_s._spirit_syn.on_death(s5[1])
	_ok("★龟蛋阵亡不召唤亡魂(那一路已经结束了)", _s._units.size() == n2)

	# ═══════════════ 遗物 ═══════════════
	print("── 遗物 ──")
	var r0 := _run([_mk("left", re.slice(0, 1))])
	_s._relic_syn.apply_all()
	_ok("★对照: 遗物未激活(1 件, 首档 2) → 不加攻",
		absf(float(r0[0]["atk"]) - 100.0) < 0.01, "atk=%.1f" % float(r0[0]["atk"]))

	# 生死界: 首档(2 件) 满血 → +3% 攻
	var r1 := _run([_mk("left", re.slice(0, 2))])
	_s._relic_syn.apply_all()
	_ok("生死界(首档): 满血(>50%%) → 攻击力 ×1.03 = 103",
		absf(float(r1[0]["atk"]) - 103.0) < 0.01, "atk=%.2f" % float(r1[0]["atk"]))
	r1[0]["hp"] = float(r1[0]["maxHp"]) * 0.3
	_s._recalc_stats(r1[0])
	_ok("生死界: 掉到 30%% 血(<50%%) → 攻击力加成【消失】(回 100)",
		absf(float(r1[0]["atk"]) - 100.0) < 0.01, "atk=%.2f" % float(r1[0]["atk"]))
	# ★实际吸血 = `lifesteal + ls_bonus`(battle_damage.gd:226) —— 断言按【这个和】算,
	#   只看 ls_bonus 会漏掉羁绊给的那一份(第一版就漏了, 两边都读到 0)。
	var ls_low: float = float(r1[0]["lifesteal"]) + float(r1[0]["ls_bonus"])
	r1[0]["hp"] = float(r1[0]["maxHp"])
	_s._recalc_stats(r1[0])
	var ls_hi: float = float(r1[0]["lifesteal"]) + float(r1[0]["ls_bonus"])
	# 首档每件 +3%, 带 2 件 = 6% ⇒ 满血 0.06 / 残血 0.12(期望值写死, 不读常量)
	_ok("生死界: 满血吸血 6%%(2 件 × 3%%)", absf(ls_hi - 0.06) < 0.0001, "%.4f" % ls_hi)
	_ok("生死界: <50%% 时生命偷取【翻倍】→ 12%%", absf(ls_low - 0.12) < 0.0001, "%.4f" % ls_low)

	# 远古之力: 档2(5 件) 每跳全队 +4 攻, 上限 +150
	var r2 := _run([_mk("left", re.slice(0, 3)), _mk("left", re.slice(3, 5))])
	_s._relic_syn.apply_all()
	var ra0: float = float(r2[1]["base_atk"])
	_s._relic_syn._t_acc = 0.0
	_s._relic_syn.tick(2.6)
	# ★用户 2026-08-04:「远古之力改为获得增伤」⇒ 写的是 damage_amp 不是 base_atk。
	_ok("远古之力(档2): 一跳全队【增伤】+1%(不带遗物的队友也吃)",
		absf(float(r2[1].get("damage_amp", 0.0)) - 0.01) < 0.0001,
		"damage_amp=%.4f" % float(r2[1].get("damage_amp", 0.0)))
	_ok("★远古之力【不再动 base_atk】(改增伤后攻击力应原封不动)",
		absf(float(r2[1]["base_atk"]) - ra0) < 0.01,
		"base_atk %.1f → %.1f" % [ra0, float(r2[1]["base_atk"])])
	for i6 in range(60):
		_s._relic_syn._t_acc = 0.0
		_s._relic_syn.tick(2.6)
	_ok("远古之力上限 +15%(跳 60 次也停在 0.15)",
		absf(float(r2[1]["_ancient"]) - 0.15) < 0.0001, "累计 %.4f" % float(r2[1]["_ancient"]))
	_ok("★增伤真的作用在伤害上(damage_amp 是两处消费点在读的字段)",
		absf(float(r2[1].get("damage_amp", 0.0)) - 0.15) < 0.0001,
		"damage_amp=%.4f" % float(r2[1].get("damage_amp", 0.0)))

	# ── ★远古之力【以场重置】(用户 2026-08-04:「改」) ────────────
	_s._relic_syn.reset_match()
	var an := _run([_mk("left", re.slice(0, 3)), _mk("left", re.slice(3, 5))])
	_s._relic_syn.apply_all()
	for _k in range(3):
		_s._relic_syn._t_acc = 0.0
		_s._relic_syn.tick(2.6)                    # 档2 每跳 +1% → 攒到 3%
	_ok("★换路前: 上路攒了 3% 增伤", absf(float(an[0]["_ancient"]) - 0.03) < 0.0001,
		"_ancient=%.4f" % float(an[0]["_ancient"]))
	var an2 := _run([_mk("left", re.slice(0, 3)), _mk("left", re.slice(3, 5))])
	_s._relic_syn.apply_all()
	var da_fresh: float = float(an2[0].get("damage_amp", 0.0))
	_s._relic_syn.restore()
	_ok("★换路后: 上一路攒的 3% 增伤真的重放回来了",
		absf(float(an2[0].get("damage_amp", 0.0)) - da_fresh - 0.03) < 0.0001,
		"%.4f → %.4f" % [da_fresh, float(an2[0].get("damage_amp", 0.0))])
	_s._relic_syn.restore()
	_ok("★同一路里 restore 调两次不叠",
		absf(float(an2[0].get("damage_amp", 0.0)) - da_fresh - 0.03) < 0.0001)
	# ★这条是变异测出来缺的: 只验"能跨路"不验"换场会清", `reset_match` 改成 pass 照样全绿。
	_ok("★整场结束 reset_match() 后清零(下一场重新开始)", _ancient_reset_clears(re))

	# 龟蛋加固: 档2 +500
	var r3 := _run([_mk("left", re.slice(0, 3)), _mk("left", re.slice(3, 5))])
	r3[1]["_isEgg"] = true
	var eh0: float = float(r3[1]["maxHp"])
	_s._relic_syn.apply_all()
	_ok("龟蛋加固(档2): 本方龟蛋 +1200 最大生命(用户 2026-08-04 加强, 原 500)",
		absf(float(r3[1]["maxHp"]) - eh0 - 1200.0) < 0.01,
		"%.0f → %.0f" % [eh0, float(r3[1]["maxHp"])])
	# ★「并使龟蛋也开始释放攻击」—— 三个字段缺一不可: 蛋出厂 atk=0 / range=0 / no_basic=true
	# ★断【增量】不断绝对值: 合成单位的 base_atk 基线是 100(不是 0)。
	_ok("龟蛋反击(档2): 攻击力 +40", absf(float(r3[1]["base_atk"]) - 100.0 - 40.0) < 0.01,
		"base_atk=%.0f (基线 100)" % float(r3[1]["base_atk"]))
	_ok("★龟蛋反击: no_basic 关掉了(不关的话 AI 普攻整条不跑, 给了攻击力也不打)",
		not bool(r3[1].get("no_basic", false)))
	# ★★字段名必须是 `atk_range` —— 第一版我写的是 `range`(不存在的键), 蛋照样不打,
	#   而门禁读的也是同一个自造键 ⇒ 全绿。这里改成【量真正的消费点】: `battle._eff_range(u)`
	#   (RealtimeBattle3DScene.gd:7579 读 atk_range × range_perm), 写错键它就是 0。
	_ok("★龟蛋反击: 【真消费点】_eff_range 量到 420(出厂 0, 不给射程连人都选不到)",
		absf(_s._eff_range(r3[1]) - 420.0) < 0.01, "_eff_range=%.0f" % _s._eff_range(r3[1]))
	_ok("★龟蛋反击: 攻击间隔 2 秒(字段是 atk_interval, 不是每帧被覆写的 atk_cd)",
		absf(float(r3[1].get("atk_interval", 0.0)) - 2.0) < 0.01,
		"atk_interval=%.1f" % float(r3[1].get("atk_interval", 0.0)))
	var em: float = float(r3[1]["maxHp"])
	_s._relic_syn.apply_all()
	_ok("★龟蛋加固只加一次", absf(float(r3[1]["maxHp"]) - em) < 0.01)

	# 觉醒(顶档 10 件): 本路开打【满 20 秒】才触发 —— 且必须自存 t0(_t 跨路累加)
	var r4 := _run([_mk("left", re.slice(0, 3)), _mk("left", re.slice(3, 6)),
		_mk("left", re.slice(6, 10))])
	_s._relic_syn.apply_all()          # 这里会把 _t0 设成【当前】_t
	_s._relic_syn._t_acc = 0.0
	_s._relic_syn.tick(2.6)
	_ok("★觉醒不在开局触发(本路刚开打, 即使全局时钟 _t 已经很大)",
		not bool(_s._relic_syn._awakened.get("left", false)),
		"_t=%.1f _t0=%.1f" % [_s._t, _s._relic_syn._t0])
	_s._relic_syn._t0 = _s._t - 25.0    # 假装本路已经打了 25 秒
	var anc_before: float = float(r4[0]["_ancient"])
	_s._relic_syn._t_acc = 0.0
	_s._relic_syn.tick(2.6)
	# 顶档一跳 +2%; 觉醒把【已累积的】+50% ⇒ 0.02 → 0.02×1.5 + 0.02 = 0.05
	# ★"之后每跳翻倍"已按用户 2026-08-04 删掉, 所以当跳仍是 +2% 不是 +4%。
	_ok("觉醒(顶档 · 本路满 20 秒): 已累积的 +50% 【一次性】(0.02 → 0.05)",
		bool(_s._relic_syn._awakened.get("left", false))
		and absf(float(r4[0]["_ancient"]) - 0.05) < 0.0001,
		"%.4f → %.4f" % [anc_before, float(r4[0]["_ancient"])])
	var anc_awake: float = float(r4[0]["_ancient"])
	_s._relic_syn._t_acc = 0.0
	_s._relic_syn.tick(2.6)
	_ok("★觉醒后【不再每跳翻倍】: 下一跳仍是 +2%(不是 +4%)",
		absf(float(r4[0]["_ancient"]) - anc_awake - 0.02) < 0.0001,
		"这一跳涨了 %.4f" % (float(r4[0]["_ancient"]) - anc_awake))

	# ═══════════════ 接线: 真的挂在战斗上了 ═══════════════
	print("── 接线 ──")
	var src_main: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var src_dmg: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	for pair in [["_potion_syn.tick(", src_main], ["_gadget_syn.tick(", src_main],
			["_food_syn.tick(", src_main], ["_spirit_syn.tick(", src_main],
			["_relic_syn.tick(", src_main],
			["_potion_syn.on_death(", src_main], ["_spirit_syn.on_death(", src_main],
			["RelicSynergySystem.atk_mult(", src_main], ["GadgetSynergySystem.stiff_mult(", src_main],
			["RelicSynergySystem.lifesteal_bonus(", src_main], ["_gadget_syn.brittle_mult(", src_main],
			["_gadget_syn.minted(", src_main], ["_potion_syn.reset_match(", src_main],
			["_relic_syn.reset_match(", src_main],
			["_potion_syn.amp_for(", src_dmg], ["_potion_syn.try_behead(", src_dmg],
			["_gadget_syn.on_hit(", src_dmg], ["_spirit_syn.on_dodge(", src_dmg]]:
		_ok("★接线: %s 在活代码里" % str(pair[0]), str(pair[1]).find(str(pair[0])) >= 0)
	# 三个 apply_all 入口都补齐了(开战 / 换路 / 调试场) —— 少一个就是"某条路上羁绊不生效"
	var n_apply := 0
	for f in ["res://scripts/scenes/battle/battle_spawn.gd",
			"res://scripts/scenes/battle/dual_lane_flow.gd",
			"res://scripts/scenes/battle/battle_debug_arena.gd"]:
		var t: String = FileAccess.get_file_as_string(f)
		if t.find("_food_syn.apply_all()") >= 0 and t.find("_relic_syn.apply_all()") >= 0:
			n_apply += 1
	_ok("★三个 apply_all 入口(开战/换路/调试场)都接了食物学院与遗物", n_apply == 3, "只有 %d 处" % n_apply)

	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 剩下五个类型的羁绊机制" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 整场结束后成长归零：reset_match 之后再 restore，一点血都不该补
func _food_reset_clears(fo: Array) -> bool:
	_s._food_syn.reset_match()
	var u := _run([_mk("left", fo.slice(0, 3))])
	var mh: float = float(u[0]["maxHp"])
	_s._food_syn.restore()
	return absf(float(u[0]["maxHp"]) - mh) < 0.01


## 整场结束后远古之力归零：reset_match 之后再 restore，一点增伤都不该补
func _ancient_reset_clears(re: Array) -> bool:
	_s._relic_syn.reset_match()
	var u := _run([_mk("left", re.slice(0, 3)), _mk("left", re.slice(3, 5))])
	_s._relic_syn.apply_all()
	var d0: float = float(u[0].get("damage_amp", 0.0))
	_s._relic_syn.restore()
	return absf(float(u[0].get("damage_amp", 0.0)) - d0) < 0.0001


## 整场结束后战利品归零：reset_match 之后再 restore，一点攻击力都不该补
func _harvest_reset_clears(po: Array) -> bool:
	_s._potion_syn.reset_match()
	var u := _run([_mk("left", po.slice(0, 3))])
	var a0: float = float(u[0]["base_atk"])
	_s._potion_syn.restore()
	return absf(float(u[0]["base_atk"]) - a0) < 0.01


## 药水首档没有战利品：3 件时击杀猎物不涨攻
func _potion_harvest_tier1(po: Array) -> bool:
	var u := _run([_mk("left", po.slice(0, 3)), _mk("right", [])])
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(2.6)
	var a0: float = float(u[0]["base_atk"])
	_s._potion_syn.on_death(u[1])
	return absf(float(u[0]["base_atk"]) - a0) < 0.01


func _ids(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == t:
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n:
			break
	return out


## 干净合成单位。★用 "green" 不用 "basic"（小龟「不屈」按稀有度增伤会弄脏精确数值）。
func _mk(side: String, ids: Array) -> Dictionary:
	var eqs: Array = []
	for i in ids:
		eqs.append({"id": str(i), "star": 1})
	# ★位置分开: 合成单位挤在同一点会让"直线上所有敌人"之类的判定退化
	var px: float = 200.0 if side == "left" else 600.0
	return {"id": "green", "name": "合成", "side": side, "alive": true,
		"hp": 3000.0, "maxHp": 3000.0, "shield": 0.0, "equips": eqs, "eq_state": {},
		"base_atk": 100.0, "atk": 100.0, "base_def": 0.0, "def": 0.0,
		"base_mr": 0.0, "mr": 0.0, "crit": 0.0, "crit_dmg": 1.5,
		"armor_pen": 0.0, "magic_pen": 0.0, "lifesteal": 0.0, "buffs": [],
		"dots": [], "dot_stacks": {}, "stacks": {}, "dmg_dealt": 0.0,
		"untargetable_until": 0.0, "summons": [], "pos": Vector2(px, 300.0)}


func _run(units: Array) -> Array:
	_s._potion_syn.clear()      # 门禁在同一个场景实例里跑很多组, 显式清猎物标记(生产里换路会调)
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return units
