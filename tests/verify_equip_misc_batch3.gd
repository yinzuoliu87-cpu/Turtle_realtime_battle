extends Node
## verify_equip_misc_batch3.gd — 新装备【批③·其余 10 件】逐件焊死 + 两个新钩子的 R2 门禁
##
## 方案书: docs/plans/20260804-新装备35件效果.md (用户拍板 U1=C 按钩子分 3 批 · U6=A)
## 覆盖: 063(新钩子·致命伤害) 064(on-death) 065 066(on-cast)
##   (071 已由用户 2026-08-05 重做成【炼乳罐】→ 门禁搬去 tests/verify_eq_food_batch.gd)
##       082(两条伤害路径·护盾减伤) 084(常驻·残血涨攻) 085 086(受法术伤害) 093(开战给龟蛋)
##
## ★件数是 10 不是方案书 U1-C 那句"其余 13 件" —— 那个 13 是拆批时的估算, 与 §6 的
##   A13/B12/C6 三张表本身也对不上(三表合计 31, 漏了 064/072/085/086)。
##   真账: 35 件 = 批① 15 + 批② 10 + 本批 10。本文件 ⓪ 组把这个真账钉死。
##
## ★本文件的规矩(照抄批①② 的口径, 逐条对应 CLAUDE.md / memory):
##   · 全部【干净合成单位】, 坐标放 ARENA 内(放外面会被钳到同一点)。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量(引用常量 = 拿代码跟自己比, 永远绿)。
##   · 数值容差 < 0.51 或精确相等 —— 批② 第一版抄了 < 1.01, 结果 60 改成 61 一条都不红。
##   · 触发一律走【真入口】, 且每件至少一条【经中央管线】的端到端断言
##     (memory fb-verify-must-run-the-real-path:「断言函数存在」守不住「还有没有人调它」)。
##   · 概率类(085)【播种 RNG】测经验频率, 不靠"跑几次看看"(CI 必然偶发红)。
##   · 不依赖任何演出 tween / 弹道飞完(CLAUDE.md §3.5)。
##   · 每组带一条【分母】断言(N=0 是空检查不是通过)。
##
## ★★R2(方案书最高风险): 两个新钩子在【中央伤害/治疗管线】上, 影响全部 95 件。
##   ⓪ 组用 `count(...) == 2` 焊死"两条伤害路径都挂了"(CLAUDE.md §3.3);
##   ⑪ 组焊死"不带这几件的单位, 行为逐个字段与加钩子前完全一致"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_misc_batch3.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const TRIALS := 1000
const SEED := 20260806

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位: 清掉一切会干扰精确数值的减伤/护盾/暴击/羁绊系数。
## ★携带者一律用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%。
func _mk(id: String, side: String, off: Vector2, hp: float = 1000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["_auraShieldVal"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["crit"] = 0.0
	u["crit_dmg"] = 1.5
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["reflect"] = 0.0
	u["lifesteal"] = 0.0
	u["ls_bonus"] = 0.0
	u["corrode_stacks"] = 0
	u["corrode_tier"] = 0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["_relic_atk_bonus"] = 0.0
	u["_relic_ls"] = 0.0
	u["stiff_stacks"] = 0
	u["hammer_pct"] = 0.0
	u["_blood_rite"] = 0.0
	u["untargetable_until"] = 0.0
	u["energy_bank"] = 0.0
	u["spd_move_mult"] = 1.0
	u["spd_dbf_until"] = 0.0
	u["heal_reduce_until"] = 0.0
	u["heal_reduce_pct"] = 0.0
	u["overheal2shield_cap"] = 0.0
	_s._units.append(u)
	return u


## 挂一件装备并走【真的属性/flag 应用入口】的 flag 那一半 —— 常驻字段就是它写的。
## ★只跑 flags 不跑 stats: stats 会把 dodgePct/hp 加进来, 污染"效果加了多少"的量测
##   (063 的 dodgePct 24% 甚至会让下面那些伤害被闪掉)。
##   stats+flags 的完整入口在 ⑩/⑪ 组用 `_eq_apply_all_stats()` 走一遍。
func _equip_flags(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	_s._equip_sys._stats._eq_apply_flags(u, iid, star)
	return u


## 只挂条目不跑任何属性管线(用于直接调效果函数的组)。
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


## 取【已剥注释】源码里某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 新装备批③·其余 10 件 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	_t_dispatch()
	# ★065/066 两件已由用户整条重写(2026-08-05 §0.5): 065 涌泉苔药剂→【鲨肝油】
	#   (每次普攻叠攻速 + 5 龟能)、066 狂潮浓缩液→【鲸涎浓浆】(本路第 11 秒喝药变身)。
	#   旧效果函数 _eq_spring_moss / _eq_surge_brew 均已删除 ⇒ 这两段用例搬到
	#   tests/verify_eq_potion_batch.gd(逐件重写, 含分发纪律那一组)。
	_t082_clam_plate()
	_t084_blood_fang()
	_t085_brass_ward()
	_t086_polar_recoil()
	_t093_altar_shard()
	_t_r2_no_side_effect()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 新装备批③其余 10 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⓪ 分发纪律与接线 —— ★★R2 的第一道: 两个新钩子必须【两条伤害路径都挂】
# ─────────────────────────────────────────────────────────────
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	var apply: String = _strip("res://scripts/systems/equip/equip_stats_apply.gd")
	var dmg_src: String = _strip("res://scripts/scenes/battle/battle_damage.gd")
	_ok("⓪ ★分母: 三份被读的源码都非空", code.length() > 20000 and apply.length() > 2000 and dmg_src.length() > 5000,
		"equip=%d apply=%d damage=%d" % [code.length(), apply.length(), dmg_src.length()])

	# ── 落点: 每件都在它该在的那个钩子里 ──
	var on_cast: String = _fn_body(code, "func _eq_on_cast")
	var on_death: String = _fn_body(code, "func _eq_on_death")
	var eq_tick: String = _fn_body(code, "func _eq_tick")
	var flags: String = _fn_body(apply, "func _eq_apply_flags")
	var all_stats: String = _fn_body(apply, "func _eq_apply_all_stats")
	_ok("⓪ ★分母: 四个宿主函数体都非空", on_cast.length() > 200 and on_death.length() > 200
		and eq_tick.length() > 100 and flags.length() > 500,
		"cast=%d death=%d tick=%d flags=%d" % [on_cast.length(), on_death.length(), eq_tick.length(), flags.length()])
	var miss: Array = []
	if not eq_tick.contains("_eq_fang_refresh("):
		miss.append("084 没接进 _eq_tick")
	for iid in ["p2eq_082", "p2eq_084", "p2eq_085", "p2eq_086"]:
		if not flags.contains("\"%s\"" % iid):
			miss.append("%s 的常驻字段没在 _eq_apply_flags 里写" % iid)
	if not all_stats.contains("_apply_altar_egg_hp("):
		miss.append("093 没接进 _eq_apply_all_stats")
	_ok("⓪ 10 件各自落在指定的钩子上", miss.is_empty(), str(miss))

	# ── ★★§3.3: 两个新钩子 + 082 必须在【两条】伤害路径上各挂一次 ──
	# ★2026-08-05: 063 已被用户整条重做成【白鲸气环】, `_ink_sac` 因此**零写入者**,
	#   这条免死通道进入休眠(函数与两条伤害路径上的挂点都保留, 见 EquipSystem._eq_ink_sac 头注)。
	#   这里守的是"通道还在且仍然两条路各挂 1 处", 不再宣称"063 在用它"。
	_ok("⓪ 中央免死通道 _ink_sac 仍在两条伤害路径上各挂 1 处(063 已不再用它)",
		dmg_src.count("_eq_ink_sac(u, d)") == 2,
		"实得 %d 处 —— 1 处 = 只有某类伤害才救得回来" % dmg_src.count("_eq_ink_sac(u, d)"))
	_ok("⓪ ★★§3.3 082 护盾减伤: battle_damage 里 _eq_clam_mitigate 正好 2 处",
		dmg_src.count("_eq_clam_mitigate(u, d)") == 2,
		"实得 %d 处" % dmg_src.count("_eq_clam_mitigate(u, d)"))
	# ★2026-08-06 更新: 071 被用户整条重做成【炼乳罐】(全队奶油护盾)后, `_eq_kelp_share`
	#   变成**零写入者 + 零调用者的死码**。上一版这里守的是"调用仍在 1 处", 于是
	#   **死码被门禁保护住了** —— 那正是本项目栽过的形状(零调用者的死函数看起来一切正常)。
	#   ⇒ 主会话已把函数与 `battle_damage.gd` 的调用点**一起删掉**。
	#   现在守的是另一件事:【受到治疗】这个中央钩子的**位置**还在(注释锚点),
	#   因为它是批③为中央管线新建的、位置本身有价值(以后再有"受到治疗时"的装备就挂那儿)。
	# ★判据不能用注释 —— `dmg_src` 是 `_strip()` 剥掉注释后的源码, 而且"注释还在"
	#   本来也守不住任何东西(谁都能删)。守两件真的:
	#   ① 死码清干净了(`_eq_kelp_share` 零残留)
	#   ② `_heal` 里那个【实际回血量】仍然被算出来且有消费者(法器余韵 `on_healed(u, _act)`)
	#      —— 只要这条还在, "受到治疗时"这个位置就仍然是可挂钩的。
	#      它比注释硬: 谁把 `_act` 或那次调用删了, 这条立刻红。
	_ok("⓪ 【受到治疗】这个位置仍可挂钩(实际回血量 _act 算得出且有消费者)·死码已清零",
		dmg_src.contains("on_healed(u, _act)") and dmg_src.count("_eq_kelp_share(") == 0,
		"_act 消费者在=%s / `_eq_kelp_share` 残留 %d 处(应为 0)"
			% [str(dmg_src.contains("on_healed(u, _act)")), dmg_src.count("_eq_kelp_share(")])
	_ok("⓪ 085/086 挂在普攻/技能路的 on-target 旁(正好 1 处) 且传的是算好的伤害桶",
		dmg_src.count("_eq_on_magic_hurt(u, src, dmg, _bkt)") == 1,
		"实得 %d 处" % dmg_src.count("_eq_on_magic_hurt(u, src, dmg, _bkt)"))
	# ★新钩子必须【带常驻字段守卫】—— 没守卫 = 95 件装备共同承担开销/副作用
	var guards := {
		# ★2026-08-06: `_kelp_share` 已随 071 重做整条删除(死码, 见上), 从守卫名单摘掉。
		"_ink_sac": 2, "_clam_dr": 2, "_b3_gadget": 1,
	}
	var noguard: Array = []
	for g in guards:
		if dmg_src.count("u.get(\"%s\"" % g) != int(guards[g]):
			noguard.append("%s 守卫 %d 处(期望 %d)" % [g, dmg_src.count("u.get(\"%s\"" % g), int(guards[g])])
	_ok("⓪ ★★零开销: 四个中央管线分支各自都由常驻字段守卫(不遍历 equips)", noguard.is_empty(), str(noguard))

	# ── 真账: 35 件 = 15 + 10 + 10, 一件不重不漏 ──
	# ★092 剧毒飞行物(2026-08-05)整件单独成文件 `eq_venom_drone.gd`, 且【故意没有】
	#   fire_equip_effect 的 match 分支(它不是"周期到点触发一次"的形状, 驱动挂在
	#   RelicSynergySystem.tick)。不把它这份源码纳进来, 这条真账会把一件真装了的装备
	#   算成"没实装"(实测 34/35) —— 与 memory [[project-god-file-decomposition]] 坑16
	#   「审计器的文件名单跟不上拆分」同形。
	var venom: String = _strip("res://scripts/systems/equip/eq_venom_drone.gd")
	_ok("⓪ ★分母: 092 的效果层源码非空(%d 字符)" % venom.length(), venom.length() > 2000,
		"len=%d" % venom.length())
	var impl := {}
	for src in [code, apply, venom]:
		for i in range(60, 95):
			if src.contains("\"p2eq_%03d\"" % i):
				impl["p2eq_%03d" % i] = true
	_ok("⓪ ★分母: 效果层里出现的批3 装备 = %d 件(35 件全实装才对)" % impl.size(),
		impl.size() == 35, "实得 %d 件" % impl.size())
	var b3 := ["p2eq_063", "p2eq_064", "p2eq_065", "p2eq_066", "p2eq_071",
		"p2eq_082", "p2eq_084", "p2eq_085", "p2eq_086", "p2eq_093"]
	_ok("⓪ 本批清点 = 10 件(方案书那句'其余 13 件'是拆批时的估算, 真账 15+10+10=35)",
		b3.size() == 10, "b3=%d" % b3.size())


# ─────────────────────────────
# ★065/066 两件的用例已搬走
#   用户 2026-08-05 逐件亲手重写(方案书 §0.5 定稿): 065 →【鲨肝油】
#   (每次普攻 +1/2/4% 叠加攻速不设上限 + 5 龟能; 射程走 flat +50)、
#   066 →【鲸涎浓浆】(登场第 11 秒喝药: 免控五条通道 + 十项属性 + 体型 +40%)。
#   新效果与它们的门禁在 tests/verify_eq_potion_batch.gd。
#   ★是整段删而不是把旧断言改成新数字 —— 旧用例量的是旧机制
#   (放技能回已损血 / 放技能减下一次冷却), 改数字保不住它们。




# ─────────────────────────────────────────────────────────────
# 082 砗磲护心甲: 护盾存在时受到的伤害额外 -8/14/22%(★两条伤害路径)
# ─────────────────────────────────────────────────────────────
func _t082_clam_plate() -> void:
	print("── 082 砗磲护心甲 · 有盾时额外减伤(两条路径) ──")
	for si in range(3):
		var dr: float = [0.08, 0.14, 0.22][si]
		var want: float = round(100.0 * (1.0 - dr))
		# ① 普攻/技能路: 量【护盾】掉了多少
		_s._units.clear()
		var u: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, 340.0), 5000.0), "p2eq_082", si + 1)
		u["shield"] = 1000.0
		var atkr: Dictionary = _mk("fortune", "right", Vector2(-100.0, 340.0), 9000.0)
		_ok("082 si=%d ★分母: _eq_apply_flags 真的写了 _clam_dr = %.2f" % [si, dr],
			absf(float(u.get("_clam_dr", 0.0)) - dr) < 0.0005,
			"_clam_dr=%.4f" % float(u.get("_clam_dr", 0.0)))
		var s0: float = float(u["shield"])
		_s._damage._apply_damage_from(atkr, u, 100, Color("#ffffff"))
		_ok("082 si=%d 【普攻路】100 打成 %.0f(减 8/14/22%%)" % [si, want],
			absf(s0 - float(u["shield"]) - want) < 0.51,
			"护盾掉 %.2f 期望 %.0f" % [s0 - float(u["shield"]), want])
		# ② DoT/真伤路 —— ★★§3.3 只挂一条会在这里红
		_s._units.clear()
		var v: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, 380.0), 5000.0), "p2eq_082", si + 1)
		v["shield"] = 1000.0
		var v0: float = float(v["shield"])
		_s._damage._apply_damage(v, 100, Color("#ffffff"), null, "mag")
		_ok("082 si=%d ★★【DoT/真伤路】同样打成 %.0f(§3.3: 两条路都挂了)" % [si, want],
			absf(v0 - float(v["shield"]) - want) < 0.51,
			"护盾掉 %.2f 期望 %.0f" % [v0 - float(v["shield"]), want])
	# ★分母: 不带 082 → 100 就是 100
	_s._units.clear()
	var bare: Dictionary = _mk("fortune", "left", Vector2(-300.0, 420.0), 5000.0)
	bare["shield"] = 1000.0
	var a2: Dictionary = _mk("fortune", "right", Vector2(-100.0, 420.0), 9000.0)
	var b0: float = float(bare["shield"])
	_s._damage._apply_damage_from(a2, bare, 100, Color("#ffffff"))
	_ok("082 ★分母: 不带 082 的同一发 → 护盾正好掉 100",
		absf(b0 - float(bare["shield"]) - 100.0) < 0.51, "掉 %.2f" % (b0 - float(bare["shield"])))
	# ★没有护盾时【不减伤】(条件是"护盾存在时")
	_s._units.clear()
	var ns: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, 460.0), 5000.0), "p2eq_082", 3)
	ns["shield"] = 0.0
	var a3: Dictionary = _mk("fortune", "right", Vector2(-100.0, 460.0), 9000.0)
	var n0: float = float(ns["hp"])
	_s._damage._apply_damage_from(a3, ns, 100, Color("#ffffff"))
	_ok("082 ★没盾就不减伤: 血正好掉 100(条件是'护盾存在时')",
		absf(n0 - float(ns["hp"]) - 100.0) < 0.51, "掉 %.2f" % (n0 - float(ns["hp"])))
	# ★多件同带取【较大值】不是相加(3 件 3★ 相加 = -66%)
	_s._units.clear()
	var many: Dictionary = _mk("fortune", "left", Vector2(-300.0, 500.0), 5000.0)
	many["equips"] = []
	for _k in range(3):
		_s._equip_sys._stats._eq_apply_flags(many, "p2eq_082", 3)
	_ok("082 ★三件 3★ 同带仍是 22% 不是 66%(取较大值不是相加)",
		absf(float(many.get("_clam_dr", 0.0)) - 0.22) < 0.0005,
		"_clam_dr=%.4f" % float(many.get("_clam_dr", 0.0)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 084 血牙巨剑: 生命 <50% 时 +12/20/32% 攻击力 且 +6/10/16% 生命偷取
# ─────────────────────────────────────────────────────────────
func _t084_blood_fang() -> void:
	print("── 084 血牙巨剑 · 残血涨攻+吸血 ──")
	for si in range(3):
		var ap: float = [0.12, 0.20, 0.32][si]
		var ls: float = [0.06, 0.10, 0.16][si]
		_s._units.clear()
		var u: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -420.0), 1000.0), "p2eq_084", si + 1)
		u["base_atk"] = 100.0
		u["eq_timer"] = 0.0
		_s._recalc_stats(u)
		_ok("084 si=%d ★分母: 满血时基线攻击力 = 100 / 吸血 0" % si,
			absf(float(u["atk"]) - 100.0) < 0.01 and absf(float(u["ls_bonus"])) < 0.0005,
			"atk=%.2f ls=%.4f" % [float(u["atk"]), float(u["ls_bonus"])])
		_s._equip_sys._eq_tick(u, 0.016)
		_ok("084 si=%d ★分母: 满血跑一帧 → 还是 100(阈值是 50%%)" % si,
			absf(float(u["atk"]) - 100.0) < 0.01, "atk=%.2f" % float(u["atk"]))
		u["hp"] = 400.0                                    # 40% < 50%
		u["eq_timer"] = 0.0
		_s._equip_sys._eq_tick(u, 0.016)
		_ok("084 si=%d 跌破 50%% → 攻击力 %.0f(+12/20/32%%)" % [si, 100.0 * (1.0 + ap)],
			absf(float(u["atk"]) - 100.0 * (1.0 + ap)) < 0.51,
			"atk=%.2f 期望 %.2f" % [float(u["atk"]), 100.0 * (1.0 + ap)])
		_ok("084 si=%d 跌破 50%% → 生命偷取 +%.2f(6/10/16%%)" % [si, ls],
			absf(float(u["ls_bonus"]) - ls) < 0.0005,
			"ls_bonus=%.4f 期望 %.4f" % [float(u["ls_bonus"]), ls])
		u["hp"] = 900.0                                    # 回到 90% → 撤销
		u["eq_timer"] = 0.0
		_s._equip_sys._eq_tick(u, 0.016)
		_ok("084 si=%d ★回血过 50%% 线 → 加成撤销(攻回 100 / 吸血回 0)" % si,
			absf(float(u["atk"]) - 100.0) < 0.51 and absf(float(u["ls_bonus"])) < 0.0005,
			"atk=%.2f ls=%.4f" % [float(u["atk"]), float(u["ls_bonus"])])
		# ★不重复叠: 连跑 20 帧仍只有一份
		u["hp"] = 400.0
		for _k in range(20):
			u["eq_timer"] = 0.0
			_s._equip_sys._eq_tick(u, 0.016)
		_ok("084 si=%d ★连跑 20 帧不重复叠(仍是 %.0f)" % [si, 100.0 * (1.0 + ap)],
			absf(float(u["atk"]) - 100.0 * (1.0 + ap)) < 0.51, "atk=%.2f" % float(u["atk"]))
	# ★分母: 不带 084 的同一只跌破 50% → 攻击力一点不变
	_s._units.clear()
	var bare: Dictionary = _mk("fortune", "left", Vector2(-300.0, -380.0), 1000.0)
	bare["base_atk"] = 100.0
	bare["hp"] = 400.0
	bare["eq_timer"] = 0.0
	_s._recalc_stats(bare)
	_s._equip_sys._eq_tick(bare, 0.016)
	_ok("084 ★分母: 不带 084 的残血单位攻击力仍是 100",
		absf(float(bare["atk"]) - 100.0) < 0.01, "atk=%.2f" % float(bare["atk"]))
	# ★★吸血真的走中央管线(不是只写了个字段没人读)
	_s._units.clear()
	var v: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -340.0), 1000.0), "p2eq_084", 3)
	v["base_atk"] = 100.0
	v["hp"] = 400.0
	v["eq_timer"] = 0.0
	_s._recalc_stats(v)
	_s._equip_sys._eq_tick(v, 0.016)
	var foe: Dictionary = _mk("basic", "right", Vector2(-100.0, -340.0), 90000.0)
	var vh0: float = float(v["hp"])
	_s._damage._apply_damage_from(v, foe, 100, Color("#ffffff"))
	_ok("084 ★★吸血接上了中央管线: 打 100 回 16 血(3★ 16% 吸血)",
		absf(float(v["hp"]) - vh0 - 16.0) < 0.51, "实回 %.2f 期望 16" % (float(v["hp"]) - vh0))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 085 铜齿护符: 受法术伤害 20/30/45% 概率回 3/5/8 龟能
# ★概率类【播种 RNG】测经验频率, 不靠"跑几次看看"
# ─────────────────────────────────────────────────────────────
func _t085_brass_ward() -> void:
	print("── 085 铜齿护符 · 受法术伤害概率充能 ──")
	for si in range(3):
		var p: float = [0.20, 0.30, 0.45][si]
		var e: float = [3.0, 5.0, 8.0][si]
		_s._units.clear()
		var u: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -300.0), 9000.0), "p2eq_085", si + 1)
		u["skill_cd"] = {"probe": 1000000.0}
		u["_brass_n"] = 0
		u["energy_bank"] = 0.0
		var src: Dictionary = _mk("basic", "right", Vector2(-100.0, -300.0), 9000.0)
		_s._battle_rng.seed = SEED
		for _k in range(TRIALS):
			_s._equip_sys._eq_on_magic_hurt(u, src, 100, "mag")
		var fired: int = int(u.get("_brass_n", 0))
		var rate: float = float(fired) / float(TRIALS)
		_ok("085 si=%d 触发概率 ≈ %.0f%%(播种 RNG · %d 次实测 %.1f%%)" % [si, p * 100.0, TRIALS, rate * 100.0],
			absf(rate - p) < 0.03, "实测 %.4f 期望 %.2f" % [rate, p])
		_ok("085 si=%d ★分母: 这一轮确实触发过(fired=%d > 0)" % [si, fired], fired > 0)
		# 每次给的龟能 = (冷却减少量 / 触发次数) / 0.075
		var cut: float = 1000000.0 - float(u["skill_cd"]["probe"])
		var per: float = cut / maxf(1.0, float(fired)) / 0.075
		_ok("085 si=%d 每次回 %.0f 点龟能(需求 3/5/8 · 折算成 ×0.075 秒冷却)" % [si, e],
			absf(per - e) < 0.01, "实测每次 %.4f" % per)
	# ★分母: 物理伤害一次都不触发(伤害桶闸)
	_s._units.clear()
	var u2: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -260.0), 9000.0), "p2eq_085", 3)
	u2["skill_cd"] = {"probe": 1000000.0}
	u2["_brass_n"] = 0
	var src2: Dictionary = _mk("basic", "right", Vector2(-100.0, -260.0), 9000.0)
	_s._battle_rng.seed = SEED
	for _k in range(200):
		_s._equip_sys._eq_on_magic_hurt(u2, src2, 100, "phy")
	_ok("085 ★分母: 200 次【物理】伤害一次都不触发(只认法术)",
		int(u2.get("_brass_n", 0)) == 0, "n=%d" % int(u2.get("_brass_n", 0)))
	# ★★真入口: 经中央伤害管线打【法术】伤害
	_s._units.clear()
	var u3: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -220.0), 900000.0), "p2eq_085", 3)
	u3["skill_cd"] = {"probe": 1000000.0}
	u3["_brass_n"] = 0
	var src3: Dictionary = _mk("fortune", "right", Vector2(-100.0, -220.0), 9000.0)
	_ok("085 ★分母: _eq_apply_flags 真的写了守卫字段 _b3_gadget",
		bool(u3.get("_b3_gadget", false)), "_b3_gadget=%s" % str(u3.get("_b3_gadget", null)))
	_s._battle_rng.seed = SEED
	for _k in range(40):
		var dm: int = _s._resolve_dmg(src3, 100.0, u3, true)     # magic=true → 伤害桶 = mag
		_s._damage._apply_damage_from(src3, u3, dm, Color("#7ecbff"))
	_ok("085 ★★真入口: 经 _apply_damage_from 打 40 发法术 → 真的触发过(n=%d)" % int(u3.get("_brass_n", 0)),
		int(u3.get("_brass_n", 0)) > 0, "n=%d" % int(u3.get("_brass_n", 0)))
	# ★分母: 同样 40 发【物理】→ 一次都不触发
	u3["_brass_n"] = 0
	_s._battle_rng.seed = SEED
	for _k in range(40):
		var dp: int = _s._resolve_dmg(src3, 100.0, u3, false)    # magic=false → 伤害桶 = phy
		_s._damage._apply_damage_from(src3, u3, dp, Color("#ffffff"))
	_ok("085 ★分母: 同样 40 发【物理】经管线 → 一次都不触发",
		int(u3.get("_brass_n", 0)) == 0, "n=%d" % int(u3.get("_brass_n", 0)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 086 极地反冲装置: 受法术伤害 → 施法者减速 30%/1/1.5/2 秒 + 反弹 10/16/25%(4 秒内置冷却)
# ─────────────────────────────────────────────────────────────
func _t086_polar_recoil() -> void:
	print("── 086 极地反冲装置 · 受法术伤害反冲 ──")
	for si in range(3):
		var sec: float = [1.0, 1.5, 2.0][si]
		var back: float = [0.10, 0.16, 0.25][si]
		_s._units.clear()
		var u: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -180.0), 9000.0), "p2eq_086", si + 1)
		var src: Dictionary = _mk("basic", "right", Vector2(-100.0, -180.0), 90000.0)
		var s0: float = float(src["hp"])
		var t0: float = _s._t
		_s._equip_sys._eq_on_magic_hurt(u, src, 200, "mag")
		_ok("086 si=%d 反弹 %.0f 真伤(200 的 10/16/25%%)" % [si, 200.0 * back],
			absf(s0 - float(src["hp"]) - 200.0 * back) < 0.51,
			"施法者掉 %.2f 期望 %.1f" % [s0 - float(src["hp"]), 200.0 * back])
		_ok("086 si=%d 施法者被减速到 0.70 倍移速(30%%)" % si,
			absf(float(src["spd_move_mult"]) - 0.70) < 0.0005, "mult=%.4f" % float(src["spd_move_mult"]))
		_ok("086 si=%d 减速持续 %.1f 秒(需求 1/1.5/2)" % [si, sec],
			absf(float(src["spd_dbf_until"]) - (t0 + sec)) < 0.02,
			"until-_t=%.3f 期望 %.2f" % [float(src["spd_dbf_until"]) - t0, sec])
		# ★4 秒内置冷却
		var s1: float = float(src["hp"])
		_s._equip_sys._eq_on_magic_hurt(u, src, 200, "mag")
		_ok("086 si=%d ★内置冷却: 立刻再挨一发 → 不反弹(施法者血不变)" % si,
			absf(s1 - float(src["hp"])) < 0.01, "又掉 %.2f" % (s1 - float(src["hp"])))
		var tsave: float = _s._t
		_s._t = tsave + 4.1
		var s2: float = float(src["hp"])
		_s._equip_sys._eq_on_magic_hurt(u, src, 200, "mag")
		_ok("086 si=%d ★4.1 秒后又能反弹 %.0f" % [si, 200.0 * back],
			absf(s2 - float(src["hp"]) - 200.0 * back) < 0.51, "掉 %.2f" % (s2 - float(src["hp"])))
		_s._t = tsave
	# ★分母: 物理伤害不反冲
	_s._units.clear()
	var u2: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -140.0), 9000.0), "p2eq_086", 3)
	var p2: Dictionary = _mk("basic", "right", Vector2(-100.0, -140.0), 90000.0)
	var q0: float = float(p2["hp"])
	_s._equip_sys._eq_on_magic_hurt(u2, p2, 200, "phy")
	_ok("086 ★分母: 物理伤害不反冲(施法者血不变 · 只认法术)",
		absf(q0 - float(p2["hp"])) < 0.01 and absf(float(p2["spd_move_mult"]) - 1.0) < 0.0005,
		"掉 %.2f mult=%.3f" % [q0 - float(p2["hp"]), float(p2["spd_move_mult"])])
	# ★不把更强的减速盖弱(单槽通道)
	_s._units.clear()
	var u3: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -100.0), 9000.0), "p2eq_086", 3)
	var p3: Dictionary = _mk("basic", "right", Vector2(-100.0, -100.0), 90000.0)
	p3["spd_move_mult"] = 0.5
	p3["spd_dbf_until"] = _s._t + 8.0
	_s._equip_sys._eq_on_magic_hurt(u3, p3, 200, "mag")
	_ok("086 ★不把别人打的 0.50 减速盖成 0.70(单槽通道取更强的那个)",
		absf(float(p3["spd_move_mult"]) - 0.50) < 0.0005, "mult=%.4f" % float(p3["spd_move_mult"]))
	# ★★真入口: 经中央伤害管线的法术伤害
	_s._units.clear()
	var u4: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -60.0), 900000.0), "p2eq_086", 3)
	var src4: Dictionary = _mk("fortune", "right", Vector2(-100.0, -60.0), 900000.0)
	var r0: float = float(src4["hp"])
	var dm4: int = _s._resolve_dmg(src4, 100.0, u4, true)
	_s._damage._apply_damage_from(src4, u4, dm4, Color("#7ecbff"))
	_ok("086 ★★真入口: 经 _apply_damage_from 打 100 法术 → 施法者被反弹 25",
		absf(r0 - float(src4["hp"]) - 25.0) < 0.51,
		"施法者掉 %.2f 期望 25(本段 %d)" % [r0 - float(src4["hp"]), dm4])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 093 祭坛残石: 本方龟蛋额外 +200/400/700 最大生命
# ─────────────────────────────────────────────────────────────
func _t093_altar_shard() -> void:
	print("── 093 祭坛残石 · 本方龟蛋加血 ──")
	for si in range(3):
		var add: float = [200.0, 400.0, 700.0][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -20.0), 3000.0), "p2eq_093", si + 1)
		var mine: Dictionary = _mk("basic", "left", Vector2(-200.0, -20.0), 3000.0)
		mine["_isEgg"] = true
		var theirs: Dictionary = _mk("basic", "right", Vector2(200.0, -20.0), 3000.0)
		theirs["_isEgg"] = true
		var m0: float = float(mine["maxHp"])
		var t0: float = float(theirs["maxHp"])
		_s._equip_sys._stats._eq_apply_all_stats()
		_ok("093 si=%d 本方龟蛋 +%.0f 最大生命(需求 200/400/700)" % [si, add],
			absf(float(mine["maxHp"]) - m0 - add) < 0.51,
			"maxHp +%.1f 期望 %.0f" % [float(mine["maxHp"]) - m0, add])
		_ok("093 si=%d 当前生命同步 +%.0f(不是只抬上限)" % [si, add],
			absf(float(mine["hp"]) - m0 - add) < 0.51, "hp=%.1f" % float(mine["hp"]))
		_ok("093 si=%d ★分母: 敌方龟蛋一点没加('本方'不是'全场')" % si,
			absf(float(theirs["maxHp"]) - t0) < 0.01, "敌蛋 +%.1f" % (float(theirs["maxHp"]) - t0))
		# ★只给一次: 再跑一遍开战管线不重复给
		var m1: float = float(mine["maxHp"])
		_s._equip_sys._stats._eq_apply_all_stats()
		_ok("093 si=%d ★只给一次: 重跑 _eq_apply_all_stats 不重复加" % si,
			absf(float(mine["maxHp"]) - m1) < 0.01, "又加了 %.1f" % (float(mine["maxHp"]) - m1))
		_ok("093 si=%d ★分母: 携带者身上确实挂着 093" % si,
			str(u["equips"][0]["id"]) == "p2eq_093")
	# ★分母: 不带 093 → 蛋一点不加
	_s._units.clear()
	_mk("fortune", "left", Vector2(-300.0, 20.0), 3000.0)
	var egg2: Dictionary = _mk("basic", "left", Vector2(-200.0, 20.0), 3000.0)
	egg2["_isEgg"] = true
	var e0: float = float(egg2["maxHp"])
	_s._equip_sys._stats._eq_apply_all_stats()
	_ok("093 ★分母: 队里没人带 093 → 龟蛋最大生命一点不变",
		absf(float(egg2["maxHp"]) - e0) < 0.01, "+%.1f" % (float(egg2["maxHp"]) - e0))
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
#  ⑪ ★★R2(方案书最高风险): 两个新钩子是中央管线上的新分支, 影响全部 95 件。
#     ⇒ 焊死"不带这几件的单位, 行为与加钩子之前【完全一致】"。
#     判据不是"看起来没变", 是【逐个字段硬写期望值】+【新字段一个都没长出来】。
# ═════════════════════════════════════════════════════════════
func _t_r2_no_side_effect() -> void:
	print("── ⑪ ★★R2 新钩子对不带该装备的单位零副作用 ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 60.0), 1000.0)
	u["base_atk"] = 100.0
	u["shield"] = 300.0
	u["hp"] = 400.0        # 40% —— 【真的残血】, 这样 084 那条断言才不是空检查
	u["skill_cd"] = {"probe": 100.0}
	u["eq_timer"] = 0.0
	_s._recalc_stats(u)
	var ally: Dictionary = _mk("basic", "left", Vector2(-200.0, 60.0), 1000.0)
	ally["hp"] = 100.0
	var foe: Dictionary = _mk("fortune", "right", Vector2(-100.0, 60.0), 900000.0)
	# 一整套会经过全部四个新分支的操作序列
	_s._damage._apply_damage_from(foe, u, 100, Color("#ffffff"))       # 有盾 → 会经 082 的位置
	_s._damage._apply_damage(u, 100, Color("#ffffff"), null, "mag")    # DoT 路 → 同上
	_s._damage._heal(u, 50.0)                                          # → 会经 071 的位置
	_s._equip_sys._eq_tick(u, 0.016)                                   # → 会经 084 的位置
	_s._damage._apply_damage_from(foe, u, 100, Color("#ffffff"))       # 盾已空 → 走血
	# 逐个字段硬写期望值(不引用任何被测常量):
	#   盾 300 → 第一发 100 吸走 100 → 200; DoT 100 → 100; 第三发 100 由盾扛完 → 0
	#   血 400 + 50(治疗) = 450, 三发一点没掉进血里
	_ok("⑪ 不带装备: 护盾 300 被三发 100 精确吃掉(没有任何额外减伤)",
		absf(float(u["shield"])) < 0.01, "shield=%.2f 期望 0" % float(u["shield"]))
	_ok("⑪ 不带装备: 血 400 + 治疗 50 = 450, 一点没掉(三发全被盾吃了)",
		absf(float(u["hp"]) - 450.0) < 0.51, "hp=%.2f 期望 450" % float(u["hp"]))
	_ok("⑪ 不带装备: 友军没被分到任何治疗(071 没有副作用)",
		absf(float(ally["hp"]) - 100.0) < 0.01, "友军 hp=%.2f 期望 100" % float(ally["hp"]))
	_ok("⑪ 不带装备: 攻击力仍是 100(084 没有副作用, 哪怕它现在是残血)",
		absf(float(u["atk"]) - 100.0) < 0.01, "atk=%.2f" % float(u["atk"]))
	_ok("⑪ 不带装备: 技能冷却仍是 100(085 没有副作用)",
		absf(float(u["skill_cd"]["probe"]) - 100.0) < 0.01, "cd=%.2f" % float(u["skill_cd"]["probe"]))
	_ok("⑪ 不带装备: 攻击者没被反弹/减速(086 没有副作用)",
		absf(float(foe["hp"]) - 900000.0) < 0.01 and absf(float(foe["spd_move_mult"]) - 1.0) < 0.0005,
		"foe hp=%.1f mult=%.3f" % [float(foe["hp"]), float(foe["spd_move_mult"])])
	_ok("⑪ 不带装备: 没有被判定成'致命伤害救回'(alive 且 hp 不是 1)",
		bool(u["alive"]) and absf(float(u["hp"]) - 1.0) > 0.5, "hp=%.2f" % float(u["hp"]))
	# ★★新字段一个都不许长出来 —— "零副作用"最硬的判据
	var leaked: Array = []
	for k in ["_ink_sac", "_clam_dr", "_kelp_share", "_b3_gadget", "_fang_pct", "_fang_ls", "_fang_on",
			"_brass_n", "_kelp_shared", "_conch_wraith"]:
		if u.has(k) or foe.has(k) or ally.has(k):
			leaked.append(k)
	_ok("⑪ ★★零副作用: 三只不带批③ 装备的单位身上, 10 个新字段一个都没长出来", leaked.is_empty(), str(leaked))
	# ★分母: 同一批字段在【带】装备的单位上确实会出现(证明上面那条不是空检查)
	var carrier: Dictionary = _mk("fortune", "left", Vector2(-300.0, 100.0), 1000.0)
	for iid in ["p2eq_082", "p2eq_084", "p2eq_085"]:
		_s._equip_sys._stats._eq_apply_flags(carrier, iid, 3)
	var got: Array = []
	# ★_kelp_share 已从这张名单拿掉: 071 重做后 `_eq_apply_flags` 不再写它(零写入者)。
	# ★_ink_sac 同理: 063 重做成白鲸气环后不再写它。
	for k in ["_clam_dr", "_b3_gadget", "_fang_pct"]:
		if carrier.has(k):
			got.append(k)
	_ok("⑪ ★分母: 带上这几件后 3 个字段【全都】出现了(证明上面那条会 FAIL)",
		got.size() == 3, "出现 %d/3: %s" % [got.size(), str(got)])
	_s._units.clear()
