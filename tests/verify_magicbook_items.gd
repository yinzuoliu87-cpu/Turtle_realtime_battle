extends Node
## verify_magicbook_items.gd —— 魔法书 10 件逐件结算(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md §4.2)
##
## 只验结算(不依赖演出): 干净合成单位(护甲 / 魔抗 / 减伤 / 增伤 / 暴击 0), 时钟手动推进 `_t`,
##   直接调批系统的 tick_unit / tick / on_basic / on_spawn / on_unit_cast 与通用飞行物的 _step_flights。
##   期望值一律从 EqMagicBatch 常量算(★3, 下标 2), 「这次消耗的龟能」= 测试自己给的 COST。
##   117 学徒笔记: 第 1、2 次攻击不射, 第 3 次射一枚追踪飞弹, 打到挨（60+30% 攻击）魔法
##   118 羊皮咒卷: 释放技能 ⇒ 200 护盾
##   119 烈焰法典: 火球飞向最近的敌人(远的不挨), （150+60% 攻击）魔法 + 灼烧 = 龟能 × 0.25 层
##   120 霜语魔典: 300 码内敌人挨（90+30% 攻击）魔法 + 冰寒 龟能 × 0.03 秒; 圈外不挨
##   121 风暴之书: 5.9 秒不落, 第 6 秒 3 名随机敌人(不重复)各挨（120+40% 攻击）魔法, 第 4 名不挨
##   122 治愈圣典: 生命比例最低的友军每秒回（60+20% 攻击）, 持续 龟能 × 0.1 秒; 满血那个不挂
##   123 亡者之书: 三种骷髅属性对表 · 存在 龟能 × 0.15 秒后化灰 · 战士狂怒(减伤 / 吸血 / 额外 50% 物理, 4 秒后撤)
##       · 法师爆裂(目标 200 码内 200% 攻击魔法) · 祭司浪潮(敌: 固定物理 + 击飞 + 眩晕 + 减魔抗; 友: 回血; 每人一次)
##   124 镜像魔典: 本路首次释放 ⇒ 排一次再放; 第二次不排; 充能存满 200 ⇒ 下一次释放再排; 再放那次不存充能、不再排
##   125 禁咒全书: 龟能消耗 −25; 放过技能后下一次攻击射禁咒弹(主目标全额 + 200 码内 50%); 再下一次不射
##   126 浮空魔典: 释放技能 ⇒ 临时最大生命 +2000(同时回血), 到期按比例削回;
##       近战: 环上敌人每 0.5 秒挨（50+10% 攻击）魔法 + 自己 70 护盾(封顶 1000);
##       远程: ≥ 6% 最大生命的单次伤害吸 1500(书页 6 → 5), 小伤害不挡, 书页用完不挡, 3 秒长回一张
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const M := preload("res://scripts/systems/equip/eq_magic_batch.gd")
const COST := 100.0

var _n := 0
var _fail := 0
var _s
var _ms


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, pos: Vector2, ids: Array = [], star: int = 3, hp: float = 100000.0, atk: float = 100.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("green", side, pos)
	u["maxHp"] = hp
	u["hp"] = hp
	u["atk"] = atk
	u["base_atk"] = atk
	for k in ["shield", "flat_dr", "def", "base_def", "mr", "base_mr", "crit", "dodge", "armor_pen", "armor_pen_pct",
			"magic_pen", "magic_pen_pct", "damage_reduction", "damage_amp", "def_shred", "tenacity", "heal_amp", "shield_amp", "lifesteal"]:
		u[k] = 0.0
	u["airborne"] = false
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": star})
	u["equips"] = eq
	u["eq_state"] = {}
	return u


func _c() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


func _place(units: Array) -> void:
	_ms.clear_all()
	_s._ballistics.clear_flights()
	_s._units.clear()
	_s._units.append_array(units)


func _adv(sec: float, carriers: Array = []) -> void:
	var steps := int(round(sec / 0.05))
	for i in range(steps):
		_s._t = float(_s._t) + 0.05
		for u in carriers:
			_ms.tick_unit(u, 0.05)
		_ms.tick(0.05)
		_s._ballistics._step_flights(0.05)


func _lost(u: Dictionary) -> float:
	return float(u["maxHp"]) - float(u["hp"])


func _near(a: float, b: float, tol: float = 1.5) -> bool:
	return absf(a - b) <= tol


func _stk(u: Dictionary, k: String) -> int:
	return int((u.get("dot_stacks", {}) as Dictionary).get(k, 0)) if u.get("dot_stacks") is Dictionary else 0


func _cast(u: Dictionary, tgt) -> void:
	_ms.on_unit_cast(u, tgt, "", COST, false)


func _skels() -> Array:
	var out: Array = []
	for o in _s._units:
		if o is Dictionary and str(o.get("id", "")).begins_with("_summon_skel_"):
			out.append(o)
	return out


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_ms = _s._equip_sys._magic_sys
	_s._t = 1000.0
	print("=== 魔法书 10 件逐件结算 ===")
	var c := _c()
	var me: Dictionary
	var t1: Dictionary
	var t2: Dictionary

	## ── 117 学徒笔记 ──
	me = _mk("left", c + Vector2(-200, 0), ["p2eq_117"])
	t1 = _mk("right", c + Vector2(200, 0))
	_place([me, t1])
	_ms.on_basic(me, t1, "p2eq_117", 2)
	_ms.on_basic(me, t1, "p2eq_117", 2)
	var n2: int = int(_ms.stat["note"])
	_ms.on_basic(me, t1, "p2eq_117", 2)
	var n3: int = int(_ms.stat["note"])
	var lost_fly := _lost(t1)
	_adv(1.0)
	var w117: float = float(M.NOTE_FLAT[2]) + M.NOTE_ATK * 100.0
	_ok("117 前两次不射、第 3 次射; 飞到才挨 %.0f 魔法" % w117, n2 == 0 and n3 == 1 and lost_fly == 0.0 and _near(_lost(t1), w117),
		"射 %d→%d · 出手时掉 %.0f · 落地后 %.0f" % [n2, n3, lost_fly, _lost(t1)])

	## ── 118 羊皮咒卷 ──
	me = _mk("left", c, ["p2eq_118"])
	_place([me])
	_cast(me, null)
	_ok("118 释放技能 ⇒ %.0f 护盾" % float(M.SCROLL_SHIELD[2]), _near(float(me["shield"]), float(M.SCROLL_SHIELD[2])), "护盾 %.1f" % float(me["shield"]))

	## ── 119 烈焰法典 ──
	me = _mk("left", c + Vector2(-200, 0), ["p2eq_119"])
	t1 = _mk("right", c + Vector2(100, 0))
	t2 = _mk("right", c + Vector2(500, 0))
	_place([me, t1, t2])
	_cast(me, t2)
	_adv(1.5)
	var w119: float = float(M.FIRE_FLAT[2]) + M.FIRE_ATK * 100.0
	var burn_want := int(floor(COST * float(M.FIRE_BURN_PER_EN[2])))
	_ok("119 火球打最近的(%.0f 魔法 + %d 层灼烧), 远的不挨" % [w119, burn_want],
		_near(_lost(t1), w119, 3.0) and _stk(t1, "burn") >= burn_want - 1 and _lost(t2) == 0.0 and _stk(t2, "burn") == 0,
		"近 %.0f / 灼烧 %d · 远 %.0f" % [_lost(t1), _stk(t1, "burn"), _lost(t2)])

	## ── 120 霜语魔典 ──
	me = _mk("left", c, ["p2eq_120"])
	t1 = _mk("right", c + Vector2(200, 0))
	t2 = _mk("right", c + Vector2(400, 0))
	_place([me, t1, t2])
	var t0: float = float(_s._t)
	_cast(me, null)
	var w120: float = float(M.FROST_FLAT[2]) + M.FROST_ATK * 100.0
	var sec120: float = COST * float(M.FROST_SEC_PER_EN[2])
	_ok("120 300 码内挨 %.0f 魔法 + 冰寒 %.1f 秒(移速 ×%.2f), 圈外不挨" % [w120, sec120, 1.0 - M.FROST_MOVE_DOWN],
		_near(_lost(t1), w120) and _near(float(t1.get("spd_dbf_until", 0.0)) - t0, sec120, 0.01)
			and _near(float(t1.get("spd_move_mult", 1.0)), 1.0 - M.FROST_MOVE_DOWN, 0.001) and _lost(t2) == 0.0,
		"内 %.0f / %.2f 秒 / ×%.2f · 外 %.0f" % [_lost(t1), float(t1.get("spd_dbf_until", 0.0)) - t0, float(t1.get("spd_move_mult", 1.0)), _lost(t2)])

	## ── 121 风暴之书 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_121"])
	var foes: Array = []
	for i in range(4):
		foes.append(_mk("right", c + Vector2(200, -150 + i * 100)))
	_place([me] + foes)
	_adv(5.9, [me])
	var early: int = int(_ms.stat["storm"])
	_adv(0.2, [me])
	var w121: float = float(M.STORM_FLAT[2]) + M.STORM_ATK * 100.0
	var hit_n := 0
	var all_ok := true
	for f in foes:
		if _lost(f) > 0.0:
			hit_n += 1
			all_ok = all_ok and _near(_lost(f), w121)
	_ok("121 5.9 秒不落, 第 6 秒 %d 名各挨 %.0f, 第 4 名不挨" % [M.STORM_N, w121], early == 0 and hit_n == M.STORM_N and all_ok,
		"早 %d · 命中 %d 名" % [early, hit_n])

	## ── 122 治愈圣典 ──
	me = _mk("left", c, ["p2eq_122"])
	t1 = _mk("left", c + Vector2(80, 0))
	t1["hp"] = 50000.0
	t2 = _mk("left", c + Vector2(-80, 0))
	_place([me, t1, t2])
	_cast(me, null)
	var per: float = float(M.HOLY_FLAT[2]) + float(M.HOLY_ATK[2]) * 100.0
	var sec122: float = COST * M.HOLY_SEC_PER_EN
	_adv(1.0)
	var h1: float = float(t1["hp"]) - 50000.0
	_adv(sec122 + 2.0)
	var htot: float = float(t1["hp"]) - 50000.0
	_ok("122 最低比例友军每秒回 %.0f, 共 %.0f 秒(≈%.0f); 满血的不挂" % [per, sec122, per * sec122],
		_near(h1, per) and _near(htot, per * floor(sec122), per + 1.0) and float(t2["hp"]) == float(t2["maxHp"]),
		"第 1 秒 %.0f · 总 %.0f" % [h1, htot])

	## ── 123 亡者之书 ──
	me = _mk("left", c + Vector2(-200, 0), ["p2eq_123"])
	t1 = _mk("right", c + Vector2(200, 0))
	_place([me, t1])
	_cast(me, t1)
	var sk: Array = _skels()
	var life: float = COST * M.SKEL_SEC_PER_EN
	_ok("123 释放技能 ⇒ 随机召出 1 具骷髅", sk.size() == 1, "%d 具 · %s" % [sk.size(), str(sk[0].get("id", "")) if not sk.is_empty() else "-"])
	_adv(life - 0.2)
	var alive_mid: bool = not sk.is_empty() and sk[0].get("alive", false)
	_adv(0.4)
	_ok("123 存在 %.1f 秒后化灰" % life, alive_mid and not sk.is_empty() and not sk[0].get("alive", false))
	## 三种属性对表
	var kinds_ok := true
	var detail := ""
	for kd in [["skel_warrior", M.SKW_HP, M.SKW_ATK, M.SKW_RES], ["skel_mage", M.SKM_HP, M.SKM_ATK, M.SKM_RES], ["skel_priest", M.SKP_HP, M.SKP_ATK, M.SKP_RES]]:
		_place([me, t1])
		var rec: Dictionary = _ms._summon_skeleton(me, 2, COST, str(kd[0]))
		var p: Dictionary = rec.get("u", {})
		var good: bool = not p.is_empty() and _near(float(p["maxHp"]), float(kd[1][2])) and _near(float(p["atk"]), float(kd[2][2])) \
			and _near(float(p["def"]), float(kd[3][2])) and _near(float(p["mr"]), float(kd[3][2]))
		kinds_ok = kinds_ok and good
		detail += "%s %.0f/%.0f/%.0f  " % [kd[0], float(p.get("maxHp", 0)), float(p.get("atk", 0)), float(p.get("def", 0))]
	_ok("123 三种骷髅属性对表(★3)", kinds_ok, detail)
	## 战士狂怒
	_place([me, t1])
	var rw: Dictionary = _ms._summon_skeleton(me, 2, COST, "skel_warrior")
	var pw: Dictionary = rw["u"]
	pw["pos"] = Vector2(t1["pos"]) + Vector2(-50, 0)
	var _base_rw: int = int(_ms.stat["skel_cast"])
	rw["en"] = M.SKEL_EN_MAX
	_adv(0.05)
	var _pre_rw: int = int(_ms.stat["skel_cast"])
	_adv(float(M.SKEL_WINDUP["skel_warrior"]) + 0.05)   # 前摇走完才结算
	var dr_on: float = float(pw.get("damage_reduction", 0.0))
	_ok("123 骷髅技能有前摇: 龟能满的那一步不结算, 走完 %.2f 秒才放" % float(M.SKEL_WINDUP["skel_warrior"]), _pre_rw == _base_rw and int(_ms.stat["skel_cast"]) == _base_rw + 1,
		"前摇里 %d 次 · 之后 %d 次" % [_pre_rw, int(_ms.stat["skel_cast"])])
	var ls_on: float = float(pw.get("lifesteal", 0.0))
	var l0 := _lost(t1)
	_ms.on_any_basic(pw, t1)
	var extra: float = _lost(t1) - l0
	var en_locked: float = float(rw["en"])
	_adv(1.0)
	var en_still: float = float(rw["en"])
	_adv(M.SKW_RAGE_SEC)
	_ok("123 战士狂怒: 减伤 +%.0f%% / 吸血 +%.0f%% / 攻击额外 %.0f 物理 / 锁龟能; %.0f 秒后撤" % [M.SKW_DR * 100, M.SKW_LS * 100, M.SKW_EXTRA * float(M.SKW_ATK[2]), M.SKW_RAGE_SEC],
		_near(dr_on, M.SKW_DR, 0.001) and _near(ls_on, M.SKW_LS, 0.001) and _near(extra, M.SKW_EXTRA * float(M.SKW_ATK[2]))
			and en_locked == 0.0 and en_still == 0.0 and _near(float(pw.get("damage_reduction", 0.0)), 0.0, 0.001),
		"减伤 %.2f 吸血 %.2f 额外 %.0f 龟能 %.0f→%.0f 撤后减伤 %.2f" % [dr_on, ls_on, extra, en_locked, en_still, float(pw.get("damage_reduction", 0.0))])
	## 法师爆裂
	t1 = _mk("right", c + Vector2(200, 0))   # 新靶子(上一段战士打过的那个已经掉了血)
	var t3 := _mk("right", c + Vector2(350, 0))
	var t4 := _mk("right", c + Vector2(600, 0))
	_place([me, t1, t3, t4])
	var rm: Dictionary = _ms._summon_skeleton(me, 2, COST, "skel_mage")
	rm["en"] = M.SKEL_EN_MAX
	var pm: Dictionary = rm["u"]
	pm["pos"] = Vector2(t1["pos"]) + Vector2(-100, 0)
	_adv(0.05)
	var _pre_rm: int = int(_ms.stat["skel_cast"])
	_adv(float(M.SKEL_WINDUP["skel_mage"]) + 0.05)   # 前摇走完才结算
	var w_bl: float = M.SKM_BLAST_ATK * float(M.SKM_ATK[2])
	_ok("123 法师爆裂: 目标与 200 码内各挨 %.0f 魔法, 圈外不挨" % w_bl, _near(_lost(t1), w_bl) and _near(_lost(t3), w_bl) and _lost(t4) == 0.0,
		"%.0f / %.0f / %.0f" % [_lost(t1), _lost(t3), _lost(t4)])
	## 祭司浪潮
	var ally := _mk("left", c + Vector2(0, 0))
	ally["hp"] = 50000.0
	t1 = _mk("right", c + Vector2(250, 0))
	_place([me, ally, t1])
	var _wh0: int = int(_ms.stat["wave_hit"])
	var rp: Dictionary = _ms._summon_skeleton(me, 2, COST, "skel_priest")
	var pp: Dictionary = rp["u"]
	pp["pos"] = c + Vector2(-200, 0)
	rp["en"] = M.SKEL_EN_MAX
	_adv(0.05 + float(M.SKEL_WINDUP["skel_priest"]))   # 前摇走完, 浪潮出手
	var tw0: float = float(_s._t)
	_adv(0.5)
	var ally_mid: float = float(ally["hp"]) - 50000.0
	var t1_mid := _lost(t1)
	_adv(2.0)
	var stun_left: float = float(t1.get("stun_until", 0.0)) - tw0
	var mr_buf := false
	for b in t1.get("buffs", []):
		if str((b as Dictionary).get("tag", "")) == "skel_wave_mr" and _near(float(b["amount"]), -M.WAVE_MR_SHRED, 0.001):
			mr_buf = true
	_ok("123 祭司浪潮慢慢推: 先过友军(回 %.0f)、后到敌人(%.0f 物理 + 眩晕 + 魔抗 −%.0f%%), 每人一次" % [float(M.WAVE_HEAL[2]), float(M.WAVE_DMG[2]), M.WAVE_MR_SHRED * 100],
		_near(ally_mid, float(M.WAVE_HEAL[2])) and t1_mid == 0.0 and _near(_lost(t1), float(M.WAVE_DMG[2])) and stun_left > M.WAVE_STUN and mr_buf
			and int(_ms.stat["wave_hit"]) - _wh0 == 1,
		"0.55 秒: 友 +%.0f 敌 %.0f · 2.55 秒: 敌 %.0f 眩晕到 +%.2f 减魔抗 %s 命中 %d" % [ally_mid, t1_mid, _lost(t1), stun_left, str(mr_buf), int(_ms.stat["wave_hit"]) - _wh0])

	## ── 124 镜像魔典 ──
	me = _mk("left", c, ["p2eq_124"])
	t1 = _mk("right", c + Vector2(200, 0))
	_place([me, t1])
	_ms.on_unit_cast(me, t1, "x", 50.0, false)
	var e1: int = _ms._echo.size()
	_ms.on_unit_cast(me, t1, "x", 50.0, false)
	var e2: int = _ms._echo.size()
	_ms.on_unit_cast(me, t1, "x", 50.0, true)   # 再放那次: 不存充能、不再排
	var e3: int = _ms._echo.size()
	_ms.on_unit_cast(me, t1, "x", 100.0, false)   # 50 + 50 + 100 = 200 ⇒ 存满、清空、挂上
	var e4: int = _ms._echo.size()
	_ms.on_unit_cast(me, t1, "x", 10.0, false)   # 挂上之后的下一次 ⇒ 再排
	var e5: int = _ms._echo.size()
	_ok("124 本路首次 ⇒ 排再放; 第二次不排; 再放那次不存不排; 存满 %.0f 后下一次 ⇒ 排" % float(M.MIRROR_THR[2]),
		e1 == 1 and e2 == 1 and e3 == 1 and e4 == 1 and e5 == 2, "%d %d %d %d %d" % [e1, e2, e3, e4, e5])

	## ── 125 禁咒全书 ──
	me = _mk("left", c + Vector2(-200, 0), ["p2eq_125"])
	var sk0: String = str(me.get("active_skills", [""])[0]) if not me.get("active_skills", []).is_empty() else ""
	var cost_before: float = float(_s._skill_cost(me, sk0))
	_ms.on_spawn(me, "p2eq_125", 2)
	var cost_after: float = float(_s._skill_cost(me, sk0))
	_ok("125 龟能消耗 −%.0f" % float(M.FORB_CUT[2]), _near(cost_before - cost_after, float(M.FORB_CUT[2]), 0.01), "%.0f → %.0f(%s)" % [cost_before, cost_after, sk0])
	t1 = _mk("right", c + Vector2(200, 0))
	t2 = _mk("right", c + Vector2(330, 0))
	t3 = _mk("right", c + Vector2(500, 0))
	_place([me, t1, t2, t3])
	_ms.on_basic(me, t1, "p2eq_125", 2)
	var pre: int = int(_ms.stat["forb"])
	var rep0: bool = bool(me.get("_basic_replaced", false))
	_cast(me, t1)
	_ms.on_basic(me, t1, "p2eq_125", 2)
	var rep1: bool = bool(me.get("_basic_replaced", false))
	me.erase("_basic_replaced")   # 主场景普攻本体读到就清(这里手动清, 模拟那一步)
	_ms.on_basic(me, t1, "p2eq_125", 2)
	var rep2: bool = bool(me.get("_basic_replaced", false))
	_ok("125 放过技能后的那一下攻击变成禁咒弹(原攻击不打): 只有那一下打标记", not rep0 and rep1 and not rep2, "%s %s %s" % [rep0, rep1, rep2])
	_adv(1.0)
	var w125: float = float(M.FORB_FLAT[2]) + M.FORB_ATK * 100.0 + float(M.FORB_MAXHP[2]) * 100000.0
	_ok("125 没放技能不射; 放过后下一次射 1 枚: 主目标 %.0f, 200 码内 50%%, 圈外不挨" % w125,
		pre == 0 and int(_ms.stat["forb"]) == 1 and _near(_lost(t1), w125, 2.0) and _near(_lost(t2), w125 * M.FORB_SPLASH, 2.0) and _lost(t3) == 0.0,
		"射 %d · %.0f / %.0f / %.0f" % [int(_ms.stat["forb"]), _lost(t1), _lost(t2), _lost(t3)])

	## ── 126 浮空魔典 · 通用临时最大生命 ──
	me = _mk("left", c, ["p2eq_126"])
	me["hp"] = 50000.0
	_place([me])
	_cast(me, null)
	var mx1: float = float(me["maxHp"])
	var hp1: float = float(me["hp"])
	_adv(COST * M.TOME_SEC_PER_EN + 0.1)
	_ok("126 释放技能 ⇒ 最大生命 +%.0f(同时回血), %.0f 秒后削回" % [float(M.TOME_HP[2]), COST * M.TOME_SEC_PER_EN],
		_near(mx1, 100000.0 + float(M.TOME_HP[2])) and _near(hp1, 50000.0 + float(M.TOME_HP[2])) and _near(float(me["maxHp"]), 100000.0),
		"%.0f/%.0f → %.0f/%.0f" % [hp1, mx1, float(me["hp"]), float(me["maxHp"])])

	## ── 126 近战: 书页环绕 ──
	me = _mk("left", c, ["p2eq_126"])
	me["melee"] = true
	t1 = _mk("right", c + Vector2(M.PAGE_R, 0))
	t2 = _mk("right", c + Vector2(400, 0))
	_place([me, t1, t2])
	_ms.on_spawn(me, "p2eq_126", 2)
	_adv(0.2, [me])   # 第 0 张书页开打就在 t1 身上; 0.2 秒内下一张还没转到
	var w126: float = float(M.PAGE_FLAT[2]) + M.PAGE_ATK * 100.0
	_ok("126 近战: 书页碰到环上的敌人 ⇒ 挨 %.0f 魔法、自己得 %.0f 护盾; 一直贴着不重复打; 远处不挨" % [w126, float(M.PAGE_SHIELD[2])],
		_near(_lost(t1), w126) and _near(float(me["shield"]), float(M.PAGE_SHIELD[2])) and _lost(t2) == 0.0,
		"%.0f / 盾 %.0f / 远 %.0f" % [_lost(t1), float(me["shield"]), _lost(t2)])
	## 每张书页各自判定碰撞: 转一整圈(2π / 角速度), 6 张书页各从 t1 身上扫过一次 ⇒ 恰好 6 次; 远处的 t2 一次没有
	var h0: int = int(_ms.stat["page_hit"])
	t1["hp"] = t1["maxHp"]
	_adv(TAU / M.PAGE_W, [me])
	var nh: int = int(_ms.stat["page_hit"]) - h0
	_ok("126 近战: 转一圈 %.1f 秒, 每张书页碰到敌人各结算一次 ⇒ %d 次(按碰撞, 不按定时)" % [TAU / M.PAGE_W, int(M.PAGE_N[2])],
		nh == int(M.PAGE_N[2]) and _near(_lost(t1), w126 * float(M.PAGE_N[2]), 3.0) and _lost(t2) == 0.0,
		"%d 次 · %.0f · 远 %.0f" % [nh, _lost(t1), _lost(t2)])
	## 封顶口径 = 护盾 4 秒到期之内本件最多给 1000(测试台不跑护盾到期 ⇒ 量「任意 4 秒窗口里增加了多少」)
	var shs: Array = [float(me["shield"])]
	for i in range(400):
		_adv(0.05, [me])
		shs.append(float(me["shield"]))
	var win: int = int(round(M.PAGE_SHIELD_SEC / 0.05))
	var worst := 0.0
	for i in range(win, shs.size()):
		worst = maxf(worst, float(shs[i]) - float(shs[i - win]))
	_ok("126 近战: 本件给的护盾 %.0f 秒内封顶 %.0f" % [M.PAGE_SHIELD_SEC, float(M.PAGE_SHIELD_CAP[2])],
		worst <= float(M.PAGE_SHIELD_CAP[2]) + 0.5 and worst > 0.0, "4 秒内最多 +%.0f" % worst)

	## ── 126 远程: 书页格挡 ──
	me = _mk("left", c, ["p2eq_126"])
	me["melee"] = false
	_place([me])
	_ms.on_spawn(me, "p2eq_126", 2)
	var big: float = 10000.0
	var r1: float = _ms.page_block(me, big)
	var small: float = 0.05 * 100000.0
	var r2: float = _ms.page_block(me, small)
	for i in range(int(M.PAGE_N[2]) - 1):
		_ms.page_block(me, big)
	var r3: float = _ms.page_block(me, big)
	_adv(float(M.PAGE_REGEN[2]) + 0.05, [me])
	var r4: float = _ms.page_block(me, big)
	_ok("126 远程: ≥%.0f%% 最大生命的一下吸 %.0f, 小伤害不挡, %d 张用完不挡, %.1f 秒长回一张" % [M.PAGE_BLOCK_PCT * 100, float(M.PAGE_BLOCK_MAX[2]), int(M.PAGE_N[2]), float(M.PAGE_REGEN[2])],
		_near(r1, big - float(M.PAGE_BLOCK_MAX[2])) and r2 == small and r3 == big and _near(r4, big - float(M.PAGE_BLOCK_MAX[2])),
		"%.0f / %.0f / %.0f / %.0f" % [r1, r2, r3, r4])

	print("─────────────── %d 项, FAIL %d ───────────────" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
