extends Node
## verify_axe.gd — 096 小木斧·三期骨架 (2026-08-31)
##
## ★需求原文(用户 2026-08-31)节选:
##   「小木斧（1费）：为携带者提供20最大生命值，10攻击力，2护甲，2魔抗。
##     会有一个斧头召唤物（初始为木斧）登场，近战，普攻造成1ATK，攻速为0.8每秒。
##     斧头召唤物拥有500+已收集的经验值最大生命值，30+0.05已收集的经验值攻击力，5护甲和5魔抗」
##   「被动1: 这个装备不会进行升星，在卡池没有数量限制。」
##   「主动治疗140龟能：斧头召唤物回复5%最大生命值并为自己提供5%最大生命值护盾。」
##   「被动2（木斧解锁）: 斧头召唤物每次普攻对有任何护盾的目标会窃取10%护盾值作为普通给自己。」
##
## ★★这份门禁里最容易写假的四条:
##   · 「历史累计」—— 只验一个字段等于没验。进化时**进度条清零而累计值不变**才是那条口径,
##     两个字段各验各的都会漏(memory: 一个数存两份必漂)。
##   · 「不升星」—— 只断言"名单里有它"是数我自己插的标记。要走**真合成入口** try_merge_all,
##     喂三件 1★ 进去, 看它到底合没合。
##   · 「卡池无限」—— 只验 left() 返回大数不够, 那是恒真式。要**真买 N 次**看张数掉不掉。
##   · 「偷盾」—— 只验自己涨了盾, 而目标掉没掉没人管 ⇒ 凭空造盾也照样绿。两边都要量。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const EP := preload("res://scripts/gamedata/equip_pool.gd")
const ES := preload("res://scripts/gamedata/equip_stats.gd")

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
	print("=== 096 小木斧 · 三期骨架 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── ① 分母: 常量表就是需求给的字面值 ──
	_ok("★分母: 装备给携带者 +%.0f生命/+%.0f攻击/+%.0f甲/+%.0f抗"
			% [AE.OWNER_HP, AE.OWNER_ATK, AE.OWNER_DEF, AE.OWNER_MR],
		AE.OWNER_HP == 20.0 and AE.OWNER_ATK == 10.0 and AE.OWNER_DEF == 2.0 and AE.OWNER_MR == 2.0)
	_ok("★分母: 召唤物 %.0f+经验 血 / %.0f+%.2f×经验 攻 / %.0f双抗 / %.1f攻速"
			% [AE.MINION_HP_BASE, AE.MINION_ATK_BASE, AE.MINION_ATK_PER_EXP, AE.MINION_DEF, AE.MINION_ASPD],
		AE.MINION_HP_BASE == 500.0 and AE.MINION_ATK_BASE == 30.0
			and absf(AE.MINION_ATK_PER_EXP - 0.05) < 1e-9 and AE.MINION_DEF == 5.0
			and AE.MINION_MR == 5.0 and absf(AE.MINION_ASPD - 0.8) < 1e-9)
	_ok("★分母: 进化阈值 80/110/130/160 + 最终 %d" % AE.FINAL_NEED,
		[int(AE.STAGES[1]["need"]), int(AE.STAGES[2]["need"]),
		 int(AE.STAGES[3]["need"]), int(AE.STAGES[4]["need"])] == [80, 110, 130, 160]
			and AE.FINAL_NEED == 400)
	_ok("★分母: 主动 %.0f 龟能 → 回 %.0f%% + 盾 %.0f%%; 偷盾 %.0f%%"
			% [AE.ACTIVE_ENERGY, AE.ACTIVE_HEAL_PCT * 100.0, AE.ACTIVE_SHIELD_PCT * 100.0,
			   AE.SHIELD_STEAL_PCT * 100.0],
		AE.ACTIVE_ENERGY == 140.0 and absf(AE.ACTIVE_HEAL_PCT - 0.05) < 1e-9
			and absf(AE.ACTIVE_SHIELD_PCT - 0.05) < 1e-9 and absf(AE.SHIELD_STEAL_PCT - 0.10) < 1e-9)
	## ★费用封顶 5(未决点 ③) —— 钻石斧 5 费, 最终造物**不再 +1**
	var costs: Array = []
	for st in AE.STAGES:
		costs.append(int(st["cost"]))
	var fin_max := 0
	for f in AE.FINALS:
		fin_max = maxi(fin_max, int(f["cost"]))
	_ok("★费用封顶 5 费(未决点③): 档位 %s · 最终造物最高 %d" % [str(costs), fin_max],
		costs == [1, 2, 3, 4, 5] and fin_max == 5)

	# ── ② 装备属性: STATS 镜像 = AxeEvolution 的那一份 ──
	var st1: Dictionary = ES.STATS.get("p2eq_096", [{}, {}, {}])[0]
	_ok("装备属性表与 AxeEvolution 一致(两边不许各写一份)",
		float(st1.get("hp", 0)) == AE.OWNER_HP and float(st1.get("atk", 0)) == AE.OWNER_ATK
			and float(st1.get("def", 0)) == AE.OWNER_DEF and float(st1.get("mr", 0)) == AE.OWNER_MR,
		str(st1))
	var st3: Dictionary = ES.STATS.get("p2eq_096", [{}, {}, {}])[2]
	_ok("★三档同值(它不升星, 永远只有 1★)", st1 == st3, "%s vs %s" % [str(st1), str(st3)])

	# ── ③ 召唤物: 走真入口召唤, 逐项量 ──
	_s._units.clear()
	var owner: Dictionary = _mk("left", Vector2(-160.0, 0.0))
	owner["equips"] = [{"id": "p2eq_096", "star": 1}]
	owner["eq_state"] = {}
	_s._equip_sys._stats._eq_apply_all_stats()
	_ok("★登场标记已置(pending 模式, 同 058/032)", owner.get("_axe_pending", false) == true)
	var ax = _s._equip_sys._axe.summon(owner)
	_ok("召唤出斧头了", ax is Dictionary and ax.get("alive", false))
	if ax is Dictionary:
		var want_hp: float = AE.minion_hp(0, 0)
		var want_atk: float = AE.minion_atk(0, 0)
		_ok("斧头最大生命 = %.0f(经验 0 → 500+0)" % want_hp,
			absf(float(ax["maxHp"]) - want_hp) < 0.51, "%.1f" % float(ax["maxHp"]))
		_ok("斧头攻击力 = %.0f(经验 0 → 30+0)" % want_atk,
			absf(float(ax["atk"]) - want_atk) < 0.51, "%.1f" % float(ax["atk"]))
		_ok("斧头双抗 = 5/5", absf(float(ax["def"]) - 5.0) < 0.51 and absf(float(ax["mr"]) - 5.0) < 0.51,
			"def=%.1f mr=%.1f" % [float(ax["def"]), float(ax["mr"])])
		_ok("斧头攻速 = 0.8 次/秒(atk_interval = 1.25 秒)",
			absf(float(ax["atk_interval"]) - 1.25) < 0.01, "%.3f" % float(ax["atk_interval"]))
		_ok("斧头是近战", bool(ax.get("melee", false)) == true)
		_ok("★龟能上限 = 140(主动住在召唤物身上, 不是携带者)",
			absf(float(ax["maxEnergy"]) - AE.ACTIVE_ENERGY) < 0.01, "%.0f" % float(ax["maxEnergy"]))

	## ★★历史累计 vs 进度条: 经验涨了, 召唤物就该更壮(未决点 ⑥)
	var hp0: float = AE.minion_hp(0, 0)
	var hp200: float = AE.minion_hp(200, 0)
	var atk200: float = AE.minion_atk(200, 0)
	_ok("★★公式吃的是【历史累计】: 200 点经验 → 血 %.0f / 攻 %.0f" % [hp200, atk200],
		absf(hp200 - 700.0) < 0.01 and absf(atk200 - 40.0) < 0.01
			and hp200 > hp0, "500+200=%.0f · 30+0.05×200=%.0f" % [hp200, atk200])

	# ── ④ 主动: 攒满 140 → 回血 + 给自己盾, 然后清空 ──
	if ax is Dictionary:
		ax["hp"] = float(ax["maxHp"]) * 0.5
		ax["shield"] = 0.0
		ax["shield_amp"] = 0.0
		ax["heal_amp"] = 0.0
		ax["energy"] = AE.ACTIVE_ENERGY - 1.0
		var h_before: float = float(ax["hp"])
		var fired_low: bool = _s._equip_sys._axe.cast_heal(ax)
		_s._damage._heal_flush(ax)
		_ok("★分母: 龟能不满(139/140)时不放", not fired_low and absf(float(ax["hp"]) - h_before) < 0.01)
		ax["energy"] = AE.ACTIVE_ENERGY
		var fired: bool = _s._equip_sys._axe.cast_heal(ax)
		_s._damage._heal_flush(ax)
		var want_h: float = float(ax["maxHp"]) * AE.ACTIVE_HEAL_PCT
		var want_sh: float = float(ax["maxHp"]) * AE.ACTIVE_SHIELD_PCT
		_ok("主动: 回 %.0f 生命(5%%最大生命)" % want_h,
			fired and absf(float(ax["hp"]) - h_before - want_h) < 0.51,
			"回了 %.1f" % (float(ax["hp"]) - h_before))
		_ok("主动: 给自己 %.0f 护盾(5%%最大生命)" % want_sh,
			absf(float(ax["shield"]) - want_sh) < 0.51, "%.1f" % float(ax["shield"]))
		_ok("★主动放完龟能清零", absf(float(ax["energy"])) < 0.01, "%.1f" % float(ax["energy"]))

	# ── ⑤ 被动2 偷盾: 目标掉多少 = 自己涨多少 ──
	##   ★只验"自己涨了"会放过"凭空造盾"; 只验"目标掉了"会放过"偷了没给自己"。两边都要量。
	_s._units.clear()
	var ax2: Dictionary = _mk("left", Vector2(-160.0, 60.0))
	ax2["_eq_axe"] = true
	ax2["shield"] = 0.0
	ax2["shield_amp"] = 0.0
	var foe: Dictionary = _mk("right", Vector2(160.0, 60.0))
	foe["shield"] = 1000.0
	var got: float = _s._equip_sys._axe.steal_shield(ax2, foe)
	_ok("被动2: 偷走目标 10% 护盾 = 100", absf(got - 100.0) < 0.51, "%.1f" % got)
	_ok("被动2 ★目标真的掉了这么多(不是凭空造盾)",
		absf(float(foe["shield"]) - 900.0) < 0.51, "目标剩 %.1f" % float(foe["shield"]))
	_ok("被动2 ★偷到的进了自己的【普通护盾】",
		absf(float(ax2["shield"]) - 100.0) < 0.51, "自己 %.1f" % float(ax2["shield"]))
	## ★「特殊护盾也转普通」—— 圣光盾是拿 `_holyShieldVal` 在同一个池子上打的标记,
	##   偷完之后标记不许超过池子(否则血条会画出比护盾还长的一截)。
	foe["shield"] = 500.0
	foe["_holyShieldVal"] = 500.0
	_s._equip_sys._axe.steal_shield(ax2, foe)
	_ok("被动2 ★特殊护盾(圣光)也照偷, 且标记不超过剩余护盾",
		float(foe["_holyShieldVal"]) <= float(foe["shield"]) + 0.01,
		"标记 %.1f / 池 %.1f" % [float(foe["_holyShieldVal"]), float(foe["shield"])])
	## ★没盾的目标偷不到 —— 分母
	var nosh: Dictionary = _mk("right", Vector2(160.0, 100.0))
	nosh["shield"] = 0.0
	_ok("★分母: 目标没盾时偷到 0", absf(_s._equip_sys._axe.steal_shield(ax2, nosh)) < 0.01)
	## ★非斧头单位偷不到 —— 分母(防"这段代码对谁都生效")
	var notaxe: Dictionary = _mk("left", Vector2(-160.0, 100.0))
	foe["shield"] = 1000.0
	_ok("★分母: 不是斧头的单位偷不到", absf(_s._equip_sys._axe.steal_shield(notaxe, foe)) < 0.01)

	# ── ⑥ 被动1 上半: 不升星(走真合成入口, 不是数名单) ──
	_ok("★NO_STAR 名单里有 096", EP.NO_STAR.has("p2eq_096"))
	var bench_bak = gs.bench_inventory.duplicate(true)
	var eqp_bak = gs.equipped_p2.duplicate(true)
	gs.equipped_p2 = {}
	gs.bench_inventory = [gs.mk_eq("p2eq_096", 1), gs.mk_eq("p2eq_096", 1), gs.mk_eq("p2eq_096", 1)]
	var merged: Array = gs.try_merge_all("left")
	var stars: Array = []
	for b in gs.bench_inventory:
		stars.append(int(b.get("star", 1)))
	_ok("★★三件 1★ 小木斧丢进真合成入口 → 一件都不合(仍是三件 1★)",
		merged.is_empty() and stars == [1, 1, 1],
		"合成 %d 次 · 星级 %s" % [merged.size(), str(stars)])
	## ★分母: 换一件**会**升星的装备, 同样三件必须合出 2★ —— 否则上面那条可能是
	##   "合成入口整个坏了"而不是"这件被排除了"。
	gs.bench_inventory = [gs.mk_eq("p2eq_058", 1), gs.mk_eq("p2eq_058", 1), gs.mk_eq("p2eq_058", 1)]
	var merged2: Array = gs.try_merge_all("left")
	var stars2: Array = []
	for b in gs.bench_inventory:
		stars2.append(int(b.get("star", 1)))
	_ok("★分母: 换成会升星的 058, 同样三件必须合出 2★(证明合成入口是活的)",
		not merged2.is_empty() and stars2.has(2),
		"合成 %d 次 · 星级 %s" % [merged2.size(), str(stars2)])
	gs.bench_inventory = bench_bak
	gs.equipped_p2 = eqp_bak

	# ── ⑦ 被动1 下半: 卡池无限(真买 N 次看张数掉不掉) ──
	var pool: Dictionary = {"p2eq_096": 3, "p2eq_058": 3}
	for _k in range(20):
		EP.take(pool, "p2eq_096", 1)
	_ok("★★买 20 次小木斧, 池里的张数一点不掉(卡池无限制)",
		int(pool["p2eq_096"]) == 3 and EP.left(pool, "p2eq_096") >= 999,
		"池 %d · left() %d" % [int(pool["p2eq_096"]), EP.left(pool, "p2eq_096")])
	var ok58 := true
	for _k in range(3):
		if not EP.take(pool, "p2eq_058", 1):
			ok58 = false
	_ok("★分母: 换成普通装备 058, 买 3 次后张数归 0 且第 4 次买不到(证明池子是活的)",
		ok58 and int(pool["p2eq_058"]) == 0 and not EP.take(pool, "p2eq_058", 1),
		"058 剩 %d" % int(pool["p2eq_058"]))

	# ── ⑧ 【大轮开始】必须把砍伐经验清干净 ──
	##   ★用户 2026-09-01 问「一大轮开始时有多少用例与斧头有关」—— 当时是 **0 条**。
	##     四个字段在 GameState 里加了、重置也写了, 却**一条都没验** ——
	##     这正是"写进去了没人读/没人验"那类账: 代码在, 但没人证明它真会被清。
	##   ★判据分三段: 先塞非零值 → 跑真入口 start_new_season() → 四个字段全归零。
	##     只验其中一个等于没验(进度条与累计值是**两个**字段, 见未决点 ⑥)。
	var bak_ss := {"bar": gs.axe_exp_bar, "tot": gs.axe_exp_total,
			"st": gs.axe_stage, "fin": gs.axe_final, "sid": gs.season_id}
	gs.axe_exp_bar = 77
	gs.axe_exp_total = 888
	gs.axe_stage = 3
	gs.axe_final = "ember"
	_ok("★分母: 大轮重置【前】四个字段确实是非零的(否则下面那条恒真)",
		gs.axe_exp_bar == 77 and gs.axe_exp_total == 888 and gs.axe_stage == 3
			and gs.axe_final == "ember")
	gs.start_new_season()
	_ok("★★大轮开始 → 砍伐经验四个字段全部归零(进度条/累计/档位/最终造物)",
		gs.axe_exp_bar == 0 and gs.axe_exp_total == 0 and gs.axe_stage == 0
			and gs.axe_final == "",
		"bar=%d total=%d stage=%d final=%s" % [gs.axe_exp_bar, gs.axe_exp_total,
			gs.axe_stage, str(gs.axe_final)])
	## ★存档往返【不能靠真的存盘验】—— `GameState.save()` 在 `test_mode` 下直接 return
	##   (那是对的设计: 测试不许污染真存档)。我第一版就是这么写的, 当场红, 差点当成产品 bug。
	##   ⇒ 判据落在**源码的两侧键**: 存的字典里有这四个键, 读的那侧也各读一次。
	##     少一侧就是"存了没人读"或"读了没人存", 那才是真会漂的地方。
	var gs_src: String = FileAccess.get_file_as_string("res://autoload/GameState.gd")
	var miss_save: Array = []
	var miss_load: Array = []
	for k in ["axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final"]:
		if gs_src.find("\"" + k + "\": " + k) < 0:
			miss_save.append(k)
		if gs_src.find(k + " = " + "int(data.get(") < 0 and gs_src.find(k + " = " + "str(data.get(") < 0:
			miss_load.append(k)
	_ok("★分母: 读得到 GameState 源码(读不到=下面两条是空检查)", gs_src.length() > 5000,
		"%d 字符" % gs_src.length())
	_ok("★★四个字段都写进了存档字典", miss_save.is_empty(), str(miss_save))
	_ok("★★四个字段都从存档里读回来(存了没人读 = 重启就丢)", miss_load.is_empty(), str(miss_load))
	## ★收尾还原(测试不许污染真存档)
	gs.axe_exp_bar = int(bak_ss["bar"])
	gs.axe_exp_total = int(bak_ss["tot"])
	gs.axe_stage = int(bak_ss["st"])
	gs.axe_final = str(bak_ss["fin"])
	gs.season_id = int(bak_ss["sid"])
	gs.save()

	# ── ⑧ 装备本体登记齐了 ──
	var e96: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_096", {})
	_ok("096 名字 = 小木斧 · 1 费", str(e96.get("name", "")) == "小木斧" and int(e96.get("cost", 0)) == 1,
		"%s / %s 费" % [str(e96.get("name", "")), str(e96.get("cost", ""))])
	_ok("096 图标在盘上", ResourceLoader.exists("res://assets/sprites/equip/wood-axe.png"),
		str(e96.get("img", "")))

	if _n < 31:
		print("  [FAIL] ★分母: 断言只有 %d 条(<31)" % _n)
		_fail += 1
	print("ALL PASS — 096 小木斧三期" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
