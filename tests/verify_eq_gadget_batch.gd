extends Node
## verify_eq_gadget_batch.gd — 奇械三件(085 压电陶瓷片 / 086 六分仪浮游炮 / 087 盗令潜水钟)
## 逐件焊死 + 演出物理模型门禁。
##
## 规格 = docs/plans/20260805-装备逐件重做.md §0.5(用户逐件亲手写·已定稿)
## 接口 = docs/plans/20260806-实装契约-批④.md
##
## ★本文件的规矩(照抄批①/批②/批③ 的口径, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。合成单位坐标放 ARENA 【内】。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 触发一律走【真入口】: 伤害走 `battle._damage._apply_damage(_from)` 中央管线,
##     每帧走 `_equip_sys._eq_tick`, 偷技能走 `_trainer_sys._cast_active`
##     (memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」)。
##   · 不依赖任何演出 tween(CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##
## ★★**085 / 087 吃 DoT 那两条的判法**(主会话 2026-08-06 补的窄口
##   `EquipSystem._b4_on_damaged_any`, 从 `_apply_damage` 调):
##   打完 DoT **同帧同步**断言, **不 await 任何一帧** —— 因为 EqGadgetBatch 的
##   `tick_unit` 也会兜底结算, 隔一帧再断言的话【窄口被删掉也照样绿】(假绿灯)。
##   另外还有一条源码断言直接查 `battle_damage.gd` 里有没有那行调用。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_gadget_batch.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const GVfx := preload("res://scripts/scenes/battle/gadget_eq_vfx.gd")

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


## 干净合成单位: 放 ARENA 中心附近, 清掉一切会干扰精确数值的减伤/护盾/暴击/增幅。
## ★携带者一律用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%。
func _mk(id: String, side: String, off: Vector2, hp: float = 100000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["base_atk"] = float(u.get("atk", 0.0))
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
	u["aspd_perm"] = 1.0
	u["echarge_perm"] = 1.0
	u["move_perm"] = 1.0
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["size_mult"] = 1.0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["skill_cd"] = {}            # 空冷却表 ⇒ _apply_energy_bank 不消耗银行, 龟能量得准
	u["energy_bank"] = 0.0
	u["dot_stacks"] = {}
	u["dot_src"] = {}
	u["active_skills"] = []
	_s._units.append(u)
	return u


## 装上一件装备(只挂条目 + 批④ 常驻守卫, 不跑属性管线 —— 属性会污染"效果加了多少"的量测)。
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	u["_b4_eq"] = true
	_g().on_spawn(u, iid, clampi(star, 1, 3) - 1)
	return u


func _g():
	return _s._equip_sys._gadget_sys


## 逐帧喂 tick_unit(自管计时全部按 delta 走 ⇒ 门禁能精确控制时间, 不用等墙钟)。
func _step(u: Dictionary, seconds: float, dt: float = 0.05) -> int:
	var k: int = int(round(seconds / dt))
	for _i in range(k):
		_g().tick_unit(u, dt)
		_s._ballistics._step_pending_shots(dt)   # 大师技能的到达结算走这条真管线(不是 tween)
	return k


func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


func _in_world(nd) -> bool:
	return nd != null and is_instance_valid(nd) and nd.get_parent() == _s._world


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 奇械三件 085/086/087 (2026-08-06 用户逐件重做) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	_t_dispatch()
	_t085_piezo()
	_t086_sextant()
	_t087_dive_ballast()
	_t087_dive_steal()
	await _t_teardown()
	await _t_vfx_physics()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 奇械三件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⓪ 分发纪律与接线 —— 三件各自落在指定的钩子上, 且【真的有人调】
# ─────────────────────────────────────────────────────────────
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	var eqs: String = _strip("res://scripts/systems/equip/equip_system.gd")
	var apply: String = _strip("res://scripts/systems/equip/equip_stats_apply.gd")
	var batch: String = _strip("res://scripts/systems/equip/eq_gadget_batch.gd")
	var vfxs: String = _strip("res://scripts/scenes/battle/gadget_eq_vfx.gd")
	var dmg_src: String = _strip("res://scripts/scenes/battle/battle_damage.gd")
	var lane: String = _strip("res://scripts/scenes/battle/dual_lane_flow.gd")
	_ok("⓪ ★分母: 六份被读的源码都非空", eqs.length() > 20000 and apply.length() > 2000
		and batch.length() > 4000 and vfxs.length() > 3000 and dmg_src.length() > 5000
		and lane.length() > 5000,
		"eq=%d apply=%d batch=%d vfx=%d dmg=%d lane=%d" % [eqs.length(), apply.length(),
		batch.length(), vfxs.length(), dmg_src.length(), lane.length()])

	_ok("⓪ 三个 id 都在 B4_OWNER 里路由到 gadget",
		_s._equip_sys.B4_OWNER.get("p2eq_085", "") == "gadget"
		and _s._equip_sys.B4_OWNER.get("p2eq_086", "") == "gadget"
		and _s._equip_sys.B4_OWNER.get("p2eq_087", "") == "gadget",
		"085=%s 086=%s 087=%s" % [_s._equip_sys.B4_OWNER.get("p2eq_085", "?"),
		_s._equip_sys.B4_OWNER.get("p2eq_086", "?"), _s._equip_sys.B4_OWNER.get("p2eq_087", "?")])
	_ok("⓪ `_b4('p2eq_085/086/087')` 三个都指到同一个 EqGadgetBatch 实例",
		_s._equip_sys._b4("p2eq_085") == _g() and _s._equip_sys._b4("p2eq_086") == _g()
		and _s._equip_sys._b4("p2eq_087") == _g(), "sys=%s" % str(_g()))

	# ── ★真入口: 两条伤害路径【各自】真的调得到 on_damaged ──
	var ot: String = _fn_body(eqs, "func _eq_on_target")
	_ok("⓪ ★分母: `_eq_on_target` 函数体非空", ot.length() > 200, "len=%d" % ot.length())
	_ok("⓪ ★接线: 普攻/技能路 `_eq_on_target` 真的调 `_b4t.on_damaged(`",
		ot.contains("_b4t.on_damaged("), "")
	_ok("⓪ ★★接线: DoT/真伤路 `_apply_damage` 真的调 `_b4_on_damaged_any(u, src, dmg)`"
		+ "(085 的 DoT 与 087 的压载舱全靠它)",
		dmg_src.contains("_b4_on_damaged_any(u, src, dmg)"), "")
	_ok("⓪ ★接线: `_apply_damage` 与 `_apply_damage_from` 【两条路】都调 `_spec.absorb`"
		+ "(087 压载舱吃全路的根)",
		_fn_body(dmg_src, "func _apply_damage(").contains("_spec.absorb(u, d)")
		and _fn_body(dmg_src, "func _apply_damage_from(").contains("_spec.absorb(u, d)"), "")
	var et: String = _fn_body(eqs, "func _eq_tick")
	_ok("⓪ ★接线: `_eq_tick` 里 `_b4_eq` 守卫真的把 tick_unit 派给 `_b4_all()`",
		et.contains("_b4_eq") and et.contains("tick_unit(u, delta)"), "")
	_ok("⓪ ★接线: 登场钩 `_b4_on_spawn_all` 真的写 `_b4_eq` 并调 `sys.on_spawn(`",
		apply.contains("u[\"_b4_eq\"] = true") and apply.contains("sys.on_spawn("), "")
	_ok("⓪ ★接线: 换路撤场真的遍历 `_b4_all()` 调 `clear_all()`",
		lane.contains("_b4_all()") and lane.contains("_b4ref.clear_all()"), "")
	# ── 全局 tick(演出推进 + 孤儿自扫): 2026-08-06 从 `_eq_tick` 搬进 `tick_global`,
	#    由主循环每帧直调 ⇒ 与"场上有没有带装备的活单位"解耦。搬回去就会停摆。
	var rb_src: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var tg: String = _fn_body(eqs, "func tick_global")
	_ok("⓪ ★分母: `tick_global` 函数体非空", tg.length() > 60, "len=%d" % tg.length())
	_ok("⓪ ★接线: `tick_global` 真的遍历 `_b4_all()` 调 `.tick(delta)`"
		+ "(浮游炮演出 + 孤儿自扫走这条)",
		tg.contains("_b4_all()") and tg.contains("_b4s.tick(delta)"), "")
	_ok("⓪ ★接线: 主循环每帧直调 `_equip_sys.tick_global(dt)`"
		+ "(★不许再退回挂在「该单位有装备」那道闸里面 —— 那样会停摆)",
		rb_src.contains("_equip_sys.tick_global(dt)"), "")
	_ok("⓪ ★`_eq_tick` 里【没有】再调一次 `_b4s.tick(`(搬走后留一份就是每帧推进两次)",
		not et.contains("_b4s.tick("), "")

	# ── 焊死口径 ①: 本文件零裸随机 ──
	var bare := RegEx.new()
	bare.compile("(?<![\\.\\w])(randf|randi|randf_range|randi_range|randfn)\\s*\\(")
	var nbare: int = bare.search_all(batch).size() + bare.search_all(vfxs).size()
	_ok("⓪ ★焊死①: 本路两个文件里【零】裸全局随机(必须走 battle._battle_rng)",
		nbare == 0, "裸调用 %d 处" % nbare)
	var nrng: int = batch.count("_battle_rng.")
	_ok("⓪ ★分母: 产品码里确实用了播种 RNG(不是「一个随机都没有」所以才 0 裸调用)",
		nrng >= 3, "_battle_rng 出现 %d 次" % nrng)

	# ── 焊死口径 ②: 打出的每一段伤害都 from_equip=true ──
	var calls := RegEx.new()
	calls.compile("_apply_damage_from\\([^\\n]*")
	var bad: int = 0
	var tot: int = 0
	for m in calls.search_all(batch):
		tot += 1
		if not m.get_string().contains("false, true)"):
			bad += 1
	_ok("⓪ ★焊死②: 本文件所有 `_apply_damage_from` 都 from_equip=true(不回钩 on-hit 防自激)",
		tot >= 3 and bad == 0, "共 %d 处, 违规 %d 处" % [tot, bad])

	# ── 焊死口径 ③: 没有"拿 _t 直接和常数比"的写法 ──
	var badt := RegEx.new()
	badt.compile("battle\\._t\\s*[<>]=?\\s*[0-9]")
	_ok("⓪ ★焊死③: 没有 `battle._t < 常数` 这种跨路会炸的写法(全部自管累加器/到期时刻)",
		badt.search_all(batch).size() == 0, "命中 %d 处" % badt.search_all(batch).size())

	# ── 087 必须走大师技能的【真入口】, 不许自己抄一份施法逻辑 ──
	_ok("⓪ ★087 走真入口: 产品码调 `_trainer_sys._cast_active(`",
		batch.contains("_trainer_sys._cast_active("), "")
	_ok("⓪ ★087 不抄副本: 产品码里没有任何 `_cast_hook(` / `_cast_tame(` 这类直点分支",
		not batch.contains("_cast_hook(") and not batch.contains("_cast_tame(")
		and not batch.contains("_cast_glacier(") and not batch.contains("_cast_hunt_order("), "")
	# ── 087 的"最远敌人"必须用标准层, 不许再在本文件手抄一份 ──
	#    memory [[fb-hand-rolled-copies-drift]]: 抄一次永远落后一次 ——
	#    以后给 `_nearest_enemy` 加的闸门不会同步到副本上, 所以把"没有副本"焊进门禁。
	var tgtsrc: String = _strip("res://scripts/scenes/battle/battle_targeting.gd")
	_ok("⓪ ★分母: `battle_targeting.gd` 里真的有标准层 `_farthest_enemy`",
		tgtsrc.contains("func _farthest_enemy(u: Dictionary)"), "len=%d" % tgtsrc.length())
	_ok("⓪ ★087 水柱选靶走标准层 `battle._targeting._farthest_enemy(`",
		batch.contains("battle._targeting._farthest_enemy("), "")
	_ok("⓪ ★087 本文件里【没有】自己手抄的 `func _farthest_enemy`(收编后不许回退成副本)",
		not batch.contains("func _farthest_enemy"), "")
	# 标准层两个选靶函数的闸门必须逐条一致 —— 改一个忘了另一个, 就是下一个"副本漂移"
	var fb: String = _fn_body(tgtsrc, "func _farthest_enemy")
	var nb: String = _fn_body(tgtsrc, "func _nearest_enemy(")
	_ok("⓪ ★分母: 标准层两个选靶函数体都非空", fb.length() > 150 and nb.length() > 150,
		"far=%d near=%d" % [fb.length(), nb.length()])
	# ★"两边一致"单独一条会【空过】—— 两边【都】漏掉某个闸门时它也成立。
	#   所以先各自查"这个闸门在不在"(分母), 再查"两边一不一致"。
	var gates: Array = ["untargetable_until", "is_trainer", "_is_hostile"]
	var miss_far: Array = []
	var miss_near: Array = []
	var diff_g: Array = []
	for g in gates:
		if not fb.contains(str(g)):
			miss_far.append(str(g))
		if not nb.contains(str(g)):
			miss_near.append(str(g))
		if fb.contains(str(g)) != nb.contains(str(g)):
			diff_g.append(str(g))
	_ok("⓪ ★分母: 标准层 `_farthest_enemy` 自己真的写了三道闸(黑洞/大师不被主动索敌/敌我判定)"
		+ " —— 不是两边都漏所以「一致」",
		miss_far.is_empty(), "缺: %s" % (str(miss_far) if not miss_far.is_empty() else "无"))
	_ok("⓪ ★分母: 标准层 `_nearest_enemy` 也写了同样三道闸", miss_near.is_empty(),
		"缺: %s" % (str(miss_near) if not miss_near.is_empty() else "无"))
	_ok("⓪ ★标准层 `_farthest_enemy` 与 `_nearest_enemy` 的选靶闸门逐条一致"
		+ "(改一个忘了另一个 = 下一个「副本漂移」)",
		diff_g.is_empty(), "两边不一致的闸门: %s" % (str(diff_g) if not diff_g.is_empty() else "无"))

	var pool: Array = _g().DIVE_SKILLS.duplicate()
	pool.sort()
	var real: Array = _s.TRAINER_SKILLS.keys()
	real.sort()
	_ok("⓪ ★087 候选池 ≡ TRAINER_SKILLS 的全部 6 个 key(少一个/多一个都红)",
		pool.size() == 6 and pool == real, "本件=%s 真表=%s" % [str(pool), str(real)])


# ─────────────────────────────────────────────────────────────
# ① 085 压电陶瓷片 — 受到的伤害 5/9/15% → 龟能, 每秒上限 20/40/60
# ─────────────────────────────────────────────────────────────
func _t085_piezo() -> void:
	print("── ① 085 压电陶瓷片 ──")
	var foe: Dictionary = _mk("fortune", "right", Vector2(180, 0))
	# 一发 300 名义伤害: 转化量 15 / 27 / 45, 都【没有】碰到每秒上限 20/40/60
	var want: Array = [15.0, 27.0, 45.0]
	var got: Array = []
	for si in range(3):
		var u: Dictionary = _mk("fortune", "left", Vector2(-180, float(si) * 40.0))
		_equip(u, "p2eq_085", si + 1)
		_s._damage._apply_damage_from(foe, u, 300, Color.WHITE, 0.0, false, false)
		got.append(float(u.get("energy_bank", 0.0)))
	_ok("085 ★分母: 三个星级都真的转出了龟能(不是三个 0)",
		got[0] > 0.0 and got[1] > 0.0 and got[2] > 0.0, "实测 %s" % str(got))
	for si in range(3):
		_ok("085 %d★ 挨 300 伤害 → 转 %.0f 龟能(300 × 5/9/15%%)" % [si + 1, want[si]],
			absf(got[si] - want[si]) < 0.51, "实测 %.3f 期望 %.1f" % [got[si], want[si]])

	# ── 每秒上限 20/40/60: 同一秒内狂挨打, 转化量必须卡在上限 ──
	var caps: Array = [20.0, 40.0, 60.0]
	var capped: Array = []
	for si in range(3):
		var u2: Dictionary = _mk("fortune", "left", Vector2(-240, float(si) * 40.0))
		_equip(u2, "p2eq_085", si + 1)
		for _k in range(12):
			_s._damage._apply_damage_from(foe, u2, 2000, Color.WHITE, 0.0, false, false)
		capped.append(float(u2.get("energy_bank", 0.0)))
	_ok("085 ★分母: 12 发 ×2000 伤害确实打进去了(不是一发都没打到)",
		capped[0] > 0.0 and capped[2] > 0.0, "实测 %s" % str(capped))
	for si in range(3):
		_ok("085 %d★ 同一秒挨 24000 伤害 → 转化封顶在 %.0f 龟能/秒" % [si + 1, caps[si]],
			absf(capped[si] - caps[si]) < 0.51, "实测 %.3f 期望 %.1f" % [capped[si], caps[si]])

	# ── 护盾挡掉的伤害【算】(用户拍板) ──
	var us: Dictionary = _mk("fortune", "left", Vector2(-300, 0))
	_equip(us, "p2eq_085", 3)
	us["shield"] = 100000.0
	var hp0: float = us["hp"]
	_s._damage._apply_damage_from(foe, us, 300, Color.WHITE, 0.0, false, false)
	_ok("085 ★护盾挡掉的伤害【算】: 血一点没掉, 龟能照转 45",
		absf(float(us["hp"]) - hp0) < 0.01 and absf(float(us["energy_bank"]) - 45.0) < 0.51,
		"掉血 %.2f 龟能 %.3f (期望 掉血0 / 龟能45)" % [hp0 - float(us["hp"]), float(us["energy_bank"])])

	# ── ★★DoT 每一跳【算】: 走真入口 _apply_damage(DoT/真伤路), 且【同帧同步】断言 ──
	#    不 await —— tick_unit 也会兜底结算, 隔帧再断言的话窄口被删也照样绿(假绿灯)。
	var ud: Dictionary = _mk("fortune", "left", Vector2(-300, 80))
	_equip(ud, "p2eq_085", 3)
	var e_before: float = float(ud.get("energy_bank", 0.0))
	_s._damage._apply_damage(ud, 200, Color.WHITE, foe, "dot")
	var e_after: float = float(ud.get("energy_bank", 0.0))
	_ok("085 ★★DoT 每一跳【算】: `_apply_damage` 打 200 灼烧 → 同帧就转出 30 龟能"
		+ "(200 × 15%; 隔帧断言会被 tick_unit 兜底掩盖成假绿灯)",
		absf(e_after - e_before - 30.0) < 0.51,
		"转化 %.3f 期望 30.0 (before=%.3f after=%.3f)" % [e_after - e_before, e_before, e_after])

	# ── 幂等: 同一段伤害不许被结算两次 ──
	var again: float = _g().piezo_settle(ud)
	_ok("085 ★幂等: 同一段伤害再结算一次必须返回 0(装两把/多处派发都不会翻倍)",
		absf(again) < 0.001, "第二次返回 %.4f 期望 0" % again)

	# ── 真入口 `_eq_tick`: 不直接点 tick_unit 也要能推进(证明派发链是活的) ──
	var ue: Dictionary = _mk("fortune", "left", Vector2(-300, 160))
	_equip(ue, "p2eq_085", 3)
	ue["_st_taken"] = int(ue.get("_st_taken", 0)) + 400   # 伪装成"有一段伤害没被 on_damaged 收到"
	_s._equip_sys._eq_tick(ue, 0.016)
	_ok("085 ★真入口: 走 `_equip_sys._eq_tick` 也能把残差转掉(400 × 15% = 60, 正好等于 3★ 每秒上限)",
		absf(float(ue.get("energy_bank", 0.0)) - 60.0) < 0.51,
		"实测 %.3f 期望 60.0" % float(ue.get("energy_bank", 0.0)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ② 086 六分仪浮游炮
# ─────────────────────────────────────────────────────────────
func _t086_sextant() -> void:
	print("── ② 086 六分仪浮游炮 ──")
	var foe: Dictionary = _mk("fortune", "right", Vector2(200, 0))
	foe["maxHp"] = 9.0e7
	foe["hp"] = 9.0e7

	# ── 成型曲线: 每 3 秒 1 门, 18 秒满 6 门, 之后不再涨 ──
	var u: Dictionary = _mk("fortune", "left", Vector2(-200, 0))
	u["atk"] = 100.0
	u["base_atk"] = 100.0
	_equip(u, "p2eq_086", 1)
	var marks: Array = []
	_step(u, 2.9)
	marks.append(int(u.get("_sext_n", -1)))
	_step(u, 0.2)
	marks.append(int(u.get("_sext_n", -1)))
	_step(u, 6.0)
	marks.append(int(u.get("_sext_n", -1)))
	_step(u, 9.1)
	marks.append(int(u.get("_sext_n", -1)))
	_step(u, 30.0)
	marks.append(int(u.get("_sext_n", -1)))
	_ok("086 成型曲线: 2.9 秒 0 门 / 3.1 秒 1 门 / 9.1 秒 3 门 / 18.2 秒 6 门 / 48 秒后仍 6 门(上限)",
		marks == [0, 1, 3, 6, 6], "实测 %s 期望 [0, 1, 3, 6, 6]" % str(marks))

	# ── 被动魔抗 10/15/20 每门 ──
	var mrs: Array = []
	for si in range(3):
		var m: Dictionary = _mk("fortune", "left", Vector2(-260, 60.0 + float(si) * 40.0))
		m["atk"] = 100.0
		m["base_atk"] = 100.0
		_equip(m, "p2eq_086", si + 1)
		_step(m, 3.1)
		var one: float = float(m["mr"])
		_step(m, 15.1)
		mrs.append([one, float(m["mr"]), int(m.get("_sext_n", -1))])
	_ok("086 ★分母: 三个星级都真的长出了 6 门炮", mrs[0][2] == 6 and mrs[1][2] == 6 and mrs[2][2] == 6,
		"门数 %d/%d/%d" % [mrs[0][2], mrs[1][2], mrs[2][2]])
	var want_one: Array = [10.0, 15.0, 20.0]
	var want_six: Array = [60.0, 90.0, 120.0]
	for si in range(3):
		_ok("086 %d★ 被动魔抗: 1 门 +%.0f / 满 6 门 +%.0f" % [si + 1, want_one[si], want_six[si]],
			absf(mrs[si][0] - want_one[si]) < 0.01 and absf(mrs[si][1] - want_six[si]) < 0.01,
			"实测 1门=%.2f 6门=%.2f" % [mrs[si][0], mrs[si][1]])

	# ── 单发伤害 = 携带者 0.3/0.4/0.5 ATK 物理 ──
	var want_shot: Array = [30.0, 40.0, 50.0]
	for si in range(3):
		var g: Dictionary = _mk("fortune", "left", Vector2(-320, float(si) * 40.0))
		g["atk"] = 100.0
		g["base_atk"] = 100.0
		_equip(g, "p2eq_086", si + 1)
		var h0: float = float(foe["hp"])
		var mult: float = [0.3, 0.4, 0.5][si]
		var hit: bool = _g().sext_fire_one(g, mult)
		var d: float = h0 - float(foe["hp"])
		_ok("086 %d★ 单门炮一发 = 携带者 %.1f × ATK(100) = %.0f 物理" % [si + 1, mult, want_shot[si]],
			hit and absf(d - want_shot[si]) < 0.51, "实测 %.2f 期望 %.1f" % [d, want_shot[si]])

	# ── 终极射线: 每条 200/350/1000 魔法, 条数 = 在场炮数 ──
	for si in range(3):
		var q: Dictionary = _mk("fortune", "left", Vector2(-380, float(si) * 40.0))
		q["atk"] = 100.0
		q["base_atk"] = 100.0
		_equip(q, "p2eq_086", si + 1)
		_step(q, 18.2)
		foe["hp"] = 9.0e7
		var h0: float = float(foe["hp"])
		var rays: int = _g().sext_ultimate(q, si)
		var d: float = h0 - float(foe["hp"])
		var per: float = [200.0, 350.0, 1000.0][si]
		_ok("086 %d★ 终极射线: 6 门炮各一条 = 6 × %.0f = %.0f 魔法" % [si + 1, per, per * 6.0],
			rays == 6 and absf(d - per * 6.0) < 3.0,
			"条数 %d 总伤 %.1f 期望 6 条 / %.1f" % [rays, d, per * 6.0])

	# ── 阈值 40/30/20 次: 打满就自动放终极, 且计数器归零(循环) ──
	for si in range(3):
		var w: Dictionary = _mk("fortune", "left", Vector2(-440, float(si) * 40.0))
		w["atk"] = 100.0
		w["base_atk"] = 100.0
		_equip(w, "p2eq_086", si + 1)
		_step(w, 18.2)
		var need: int = [40, 30, 20][si]
		var st: Dictionary = w["eq_state"]["p2eq_086"]
		st["shots"] = need - 1
		w["_sext_ults"] = 0
		foe["hp"] = 9.0e7
		_step(w, 2.1)
		_ok("086 %d★ 累计 %d 次攻击后自动放终极, 且计数器归零(每当…后 = 循环)"
			% [si + 1, need],
			int(w.get("_sext_ults", 0)) >= 1 and int(st.get("shots", -1)) < need,
			"放了 %d 轮, 计数器 = %d (期望 ≥1 轮 / 计数 < %d)"
			% [int(w.get("_sext_ults", 0)), int(st.get("shots", -1)), need])

	# ── ★真入口: 走 `_equip_sys._eq_tick`(每帧的真派发链)也能长出浮游炮 ──
	#    memory [[fb-verify-must-run-the-real-path]]: 只调自己的 tick_unit 的话,
	#    `_eq_tick` 里那道 `_b4_eq` 守卫被删掉门禁也照样绿。
	var re: Dictionary = _mk("fortune", "left", Vector2(-500, 0))
	re["atk"] = 100.0
	re["base_atk"] = 100.0
	_equip(re, "p2eq_086", 3)
	for _i in range(62):
		_s._equip_sys._eq_tick(re, 0.05)
	_ok("086 ★真入口: 走 `_equip_sys._eq_tick` 跑 3.1 秒也长出第 1 门炮(证明派发链是活的)",
		int(re.get("_sext_n", 0)) == 1, "实测 %d 门 期望 1" % int(re.get("_sext_n", 0)))

	# ── ★随机三处全部走播种 RNG: 同种子重放必须一模一样 ──
	var r1: Array = _sext_rng_trace(12345)
	var r2: Array = _sext_rng_trace(12345)
	var r3: Array = _sext_rng_trace(999)
	_ok("086 ★分母: RNG 轨迹非空(不是两个空数组在比)", r1.size() >= 6, "轨迹长度 %d" % r1.size())
	_ok("086 ★焊死①: 飞散点走播种 `_battle_rng` —— 同种子重放【逐点相同】(裸 randf 做不到)",
		r1 == r2, "重放一致=%s" % str(r1 == r2))
	_ok("086 ★分母: 换个种子轨迹【必须不同】(否则是把坐标写死了, 上一条恒真)",
		r1 != r3, "不同种子一致=%s" % str(r1 == r3))

	# ── 飞散点必须落在战场内 ──
	var inside: int = 0
	for p in r1:
		if _s.ARENA.has_point(p):
			inside += 1
	_ok("086 飞散点全部落在 ARENA 内(飞出地图外的射线画不出来)",
		r1.size() > 0 and inside == r1.size(), "%d/%d 在场内" % [inside, r1.size()])
	_s._units.clear()


## 用指定种子跑一次终极, 把 6 个飞散点抄出来。
func _sext_rng_trace(seed_v: int) -> Array:
	_s._battle_rng.seed = seed_v
	var foe: Dictionary = _mk("fortune", "right", Vector2(220, 0))
	foe["maxHp"] = 9.0e7
	foe["hp"] = 9.0e7
	var u: Dictionary = _mk("fortune", "left", Vector2(-220, 0))
	u["atk"] = 100.0
	u["base_atk"] = 100.0
	_equip(u, "p2eq_086", 3)
	var st: Dictionary = u["eq_state"]["p2eq_086"]
	var dr: Array = []
	for k in range(6):
		dr.append({"ang": 0.0, "ft": 0.0, "sx": 0.0, "sy": 0.0, "scat": 0.0})
	st["drones"] = dr
	_g().sext_ultimate(u, 2)
	var out: Array = []
	for d in dr:
		out.append(Vector2(float(d["sx"]), float(d["sy"])))
	_s._units.clear()
	return out


# ─────────────────────────────────────────────────────────────
# ③ 087 效果二 — 压载舱
# ─────────────────────────────────────────────────────────────
func _t087_dive_ballast() -> void:
	print("── ③ 087 盗令潜水钟 · 压载舱 ──")
	var foe: Dictionary = _mk("fortune", "right", Vector2(200, 0))

	# ── 舱容 = 自身最大生命的 60/90/150% ──
	var caps: Array = []
	for si in range(3):
		var u: Dictionary = _mk("fortune", "left", Vector2(-200, float(si) * 40.0), 1000.0)
		_equip(u, "p2eq_087", si + 1)
		_step(u, 0.05)
		caps.append(_s._spec.val(u, "p2eq_087_ballast"))
	var want_cap: Array = [600.0, 900.0, 1500.0]
	_ok("087 ★分母: 三个星级都真的开出了舱(不是三个 0)",
		caps[0] > 0.0 and caps[1] > 0.0 and caps[2] > 0.0, "实测 %s" % str(caps))
	for si in range(3):
		_ok("087 %d★ 压载舱容量 = 最大生命(1000) × %.0f%% = %.0f"
			% [si + 1, want_cap[si] / 10.0, want_cap[si]],
			absf(caps[si] - want_cap[si]) < 0.51, "实测 %.2f 期望 %.1f" % [caps[si], want_cap[si]])

	# ── 受到的伤害先灌进舱里(舱满前一点血不掉) —— 走真入口普攻/技能路 ──
	var u2: Dictionary = _mk("fortune", "left", Vector2(-260, 0), 1000.0)
	_equip(u2, "p2eq_087", 3)
	_step(u2, 0.05)
	var hp0: float = float(u2["hp"])
	_s._damage._apply_damage_from(foe, u2, 700, Color.WHITE, 0.0, false, false)
	_ok("087 ★受伤先灌舱(普攻/技能路): 挨 700 伤害, 血一点没掉, 舱里存了 700 水",
		absf(float(u2["hp"]) - hp0) < 0.01 and absf(_g().dive_water(u2) - 700.0) < 0.51,
		"掉血 %.2f 水量 %.2f (期望 0 / 700)" % [hp0 - float(u2["hp"]), _g().dive_water(u2)])

	# ── ★★DoT/真伤路也灌: 同帧同步断言(不 await) ──
	var w_before: float = _g().dive_water(u2)
	_s._damage._apply_damage(u2, 300, Color.WHITE, foe, "dot")
	_ok("087 ★★DoT 路也灌舱: `_apply_damage` 打 300 灼烧 → 同帧水量 +300, 血仍不掉",
		absf(_g().dive_water(u2) - w_before - 300.0) < 0.51
		and absf(float(u2["hp"]) - hp0) < 0.01,
		"水量 %.2f→%.2f 掉血 %.2f" % [w_before, _g().dive_water(u2), hp0 - float(u2["hp"])])

	# ── 舱满后才真的掉血 ──
	_s._damage._apply_damage_from(foe, u2, 800, Color.WHITE, 0.0, false, false)
	_ok("087 舱满(1500)之后溢出的 300 才真的掉血",
		absf(_g().dive_water(u2) - 1500.0) < 0.51 and absf(hp0 - float(u2["hp"]) - 300.0) < 0.51,
		"水量 %.2f 掉血 %.2f (期望 1500 / 300)" % [_g().dive_water(u2), hp0 - float(u2["hp"])])

	# ── 抽水: 舱内 10% 还成生命 + 朝【最远】的敌人喷等量水柱 ──
	var near: Dictionary = _mk("fortune", "right", Vector2(60, 0))
	var far: Dictionary = _mk("fortune", "right", Vector2(520, 0))
	var u3: Dictionary = _mk("fortune", "left", Vector2(-260, 120), 1000.0)
	_equip(u3, "p2eq_087", 3)
	_step(u3, 0.05)
	_s._damage._apply_damage_from(foe, u3, 1000, Color.WHITE, 0.0, false, false)
	u3["hp"] = 400.0
	var nh0: float = float(near["hp"])
	var fh0: float = float(far["hp"])
	var pumped: float = _g().dive_pump(u3)
	_ok("087 抽水量 = 舱内(1000)的 10%% = 100", absf(pumped - 100.0) < 0.51,
		"实测 %.2f 期望 100.0" % pumped)
	_ok("087 抽出来的水【还成生命】: 血 400 → 500", absf(float(u3["hp"]) - 500.0) < 0.51,
		"实测 %.2f 期望 500.0" % float(u3["hp"]))
	_ok("087 抽水后舱内水少了 100(舱又空出这么多可以再灌)",
		absf(_g().dive_water(u3) - 900.0) < 0.51, "实测 %.2f 期望 900.0" % _g().dive_water(u3))
	_ok("087 ★水柱打的是【最远】的敌人(520 码那只), 不是最近的(60 码那只)"
		+ " —— 抄成 _nearest_enemy 这条就红",
		absf(fh0 - float(far["hp"]) - 100.0) < 1.01 and absf(nh0 - float(near["hp"])) < 0.01,
		"最远掉 %.2f(期望100) 最近掉 %.2f(期望0)" % [fh0 - float(far["hp"]), nh0 - float(near["hp"])])

	# ── 层数: 每 10% 最大生命 1 层, 每层 +3% 移速 +3 护甲, 上限 15 层 ──
	var u4: Dictionary = _mk("fortune", "left", Vector2(-320, 200), 1000.0)
	_equip(u4, "p2eq_087", 3)
	_step(u4, 0.05)
	_s._damage._apply_damage_from(foe, u4, 350, Color.WHITE, 0.0, false, false)
	_g().tick_unit(u4, 0.016)
	var n3: int = _g().dive_stacks(u4)
	_ok("087 层数: 舱内 350 水 / 最大生命 1000 ⇒ 3 层(取整, 不是 3.5)", n3 == 3, "实测 %d 期望 3" % n3)
	_ok("087 3 层 ⇒ 护甲 +9 · 移速 ×1.09",
		absf(float(u4["def"]) - 9.0) < 0.01 and absf(float(u4.get("move_perm", 1.0)) - 1.09) < 0.001,
		"def=%.2f move_perm=%.4f (期望 9 / 1.09)" % [float(u4["def"]), float(u4.get("move_perm", 1.0))])
	_s._damage._apply_damage_from(foe, u4, 1150, Color.WHITE, 0.0, false, false)
	_g().tick_unit(u4, 0.016)
	var n15: int = _g().dive_stacks(u4)
	_ok("087 满舱(1500 水 = 150% 最大生命)⇒ 层数封顶 15(不是 15 层以上)",
		n15 == 15, "实测 %d 期望 15" % n15)
	_ok("087 15 层 ⇒ 护甲 +45 · 移速 ×1.45",
		absf(float(u4["def"]) - 45.0) < 0.01 and absf(float(u4.get("move_perm", 1.0)) - 1.45) < 0.001,
		"def=%.2f move_perm=%.4f (期望 45 / 1.45)" % [float(u4["def"]), float(u4.get("move_perm", 1.0))])

	# ── ★真入口: 走 `_equip_sys._eq_tick` 也能开出压载舱(同 086 那条的理由) ──
	var re7: Dictionary = _mk("fortune", "left", Vector2(-440, 320), 1000.0)
	_equip(re7, "p2eq_087", 3)
	_s._equip_sys._eq_tick(re7, 0.05)
	_ok("087 ★真入口: 走 `_equip_sys._eq_tick` 一帧就开出 1500 容量的压载舱(证明派发链是活的)",
		absf(_s._spec.val(re7, "p2eq_087_ballast") - 1500.0) < 0.51,
		"实测 %.2f 期望 1500.0" % _s._spec.val(re7, "p2eq_087_ballast"))

	# ── 抽水节拍 = 每 2 秒 ──
	var u5: Dictionary = _mk("fortune", "left", Vector2(-380, 260), 1000.0)
	_equip(u5, "p2eq_087", 3)
	_step(u5, 0.05)
	_s._damage._apply_damage_from(foe, u5, 1000, Color.WHITE, 0.0, false, false)
	u5["_dive_pumped_total"] = 0.0
	_step(u5, 1.9)
	var p19: float = float(u5.get("_dive_pumped_total", 0.0))
	_step(u5, 0.2)
	var p21: float = float(u5.get("_dive_pumped_total", 0.0))
	_ok("087 抽水节拍: 1.9 秒还没抽过, 2.1 秒抽了一次(每 2 秒)",
		absf(p19) < 0.001 and p21 > 0.0, "1.9s=%.3f 2.1s=%.3f" % [p19, p21])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ④ 087 效果一 — 偷训龟大师的主动技能
# ─────────────────────────────────────────────────────────────
func _t087_dive_steal() -> void:
	print("── ④ 087 盗令潜水钟 · 偷技能 ──")
	# 敌人放在 600 码(猎龟令/驯服的射程)以内, 否则那两招会空放
	var e1: Dictionary = _mk("fortune", "right", Vector2(180, 0))
	e1["maxHp"] = 9.0e7
	e1["hp"] = 9.0e7
	var e2: Dictionary = _mk("fortune", "right", Vector2(240, 90))
	e2["maxHp"] = 9.0e7
	e2["hp"] = 9.0e7

	# ── 3★ 每 4 秒偷一个: 3.9 秒还没偷, 4.1 秒偷到第一个 ──
	var u: Dictionary = _mk("fortune", "left", Vector2(-200, 0))
	_equip(u, "p2eq_087", 3)
	_step(u, 3.9)
	var n39: int = int(u.get("_dive_steal_n", 0))
	_step(u, 0.2)
	var n41: int = int(u.get("_dive_steal_n", 0))
	_ok("087 3★ 偷取间隔 4 秒: 3.9 秒偷 0 个, 4.1 秒偷到 1 个",
		n39 == 0 and n41 == 1, "3.9s=%d 4.1s=%d (期望 0 / 1)" % [n39, n41])

	# ── 偷完 6 个就停机, 且【不重复】 ──
	_step(u, 40.0)
	var st: Dictionary = u["eq_state"]["p2eq_087"]
	var stolen: Array = st.get("stolen", [])
	var uniq: Dictionary = {}
	for s in stolen:
		uniq[str(s)] = true
	_ok("087 ★分母: 真的偷到了技能(不是一个都没偷成)", stolen.size() > 0,
		"已偷 %d 个: %s" % [stolen.size(), str(stolen)])
	_ok("087 3★ 44 秒内把 6 个主动技【全部】偷完", stolen.size() == 6,
		"实测 %d 个: %s" % [stolen.size(), str(stolen)])
	_ok("087 ★每一路不会偷到重复的(6 个各不相同)", uniq.size() == stolen.size(),
		"去重后 %d / 原 %d" % [uniq.size(), stolen.size()])
	_step(u, 40.0)
	_ok("087 全部偷完并释放过后【不再偷取】(再跑 40 秒还是 6 个)",
		(st.get("stolen", []) as Array).size() == 6,
		"实测 %d 期望 6" % (st.get("stolen", []) as Array).size())

	# ── 1★ / 2★ 的间隔是 15 / 10 秒 ──
	var ivs: Array = []
	for si in range(2):
		var m: Dictionary = _mk("fortune", "left", Vector2(-260, 60.0 + float(si) * 40.0))
		_equip(m, "p2eq_087", si + 1)
		var iv: float = [15.0, 10.0][si]
		_step(m, iv - 0.2)
		var a: int = int(m.get("_dive_steal_n", 0))
		_step(m, 0.4)
		var b: int = int(m.get("_dive_steal_n", 0))
		ivs.append([a, b])
	_ok("087 1★ 偷取间隔 15 秒(14.8 秒 0 个 / 15.2 秒 1 个)",
		ivs[0] == [0, 1], "实测 %s 期望 [0, 1]" % str(ivs[0]))
	_ok("087 2★ 偷取间隔 10 秒(9.8 秒 0 个 / 10.2 秒 1 个)",
		ivs[1] == [0, 1], "实测 %s 期望 [0, 1]" % str(ivs[1]))

	# ── ★真入口证据: 偷到「驯服」时目标身上真的出现了 tame 标记 ──
	#    tame 的效果只有 `_trainer_sys._cast_tame` → `_tame_mark` 会写, 自己抄一份施法逻辑写不出来。
	var tamed: bool = e1.get("_tamed_marked", false) or e2.get("_tamed_marked", false)
	var hunted: bool = float(e1.get("hunt_until", 0.0)) > 0.0 or float(e2.get("hunt_until", 0.0)) > 0.0
	_ok("087 ★★真入口: 偷来的【驯服】真的在敌人身上打了 tame 标记(只有 `_cast_tame` 会写)",
		tamed, "e1=%s e2=%s" % [str(e1.get("_tamed_marked", false)), str(e2.get("_tamed_marked", false))])
	_ok("087 ★★真入口: 偷来的【猎龟令】真的写了 hunt_until(只有 `_cast_hunt_order` 会写)",
		hunted, "e1=%.2f e2=%.2f" % [float(e1.get("hunt_until", 0.0)), float(e2.get("hunt_until", 0.0))])
	_ok("087 ★真入口: 偷来的【冰川】真的在场上留了冰川区域",
		(_s._glacier_zones as Array).size() > 0, "冰川区域 %d 个" % (_s._glacier_zones as Array).size())

	# ── 施法后不留痕: `_tr_active` 必须还原掉(携带者不是训龟大师) ──
	_ok("087 施法后把 `_tr_active` 还原掉(携带者不该变成「装了主动技的大师」)",
		not u.has("_tr_active"), "残留 = %s" % str(u.get("_tr_active", "<无>")))

	# ── ★空放不消耗名额: 没有敌人时 target 类的两招放不出去, 名额留着 ──
	#    ★播固定种子: 抽谁是随机的, 不播种会让"跑多久才凑齐 4 招"在 CI 上飘
	#    (memory [[fb-ci-vs-local-divergence]])。
	for k in range(_s._units.size() - 1, -1, -1):
		if str((_s._units[k] as Dictionary).get("side", "")) == "right":
			(_s._units[k] as Dictionary)["alive"] = false
	_s._battle_rng.seed = 20260806
	var v: Dictionary = _mk("fortune", "left", Vector2(-320, 160))
	_equip(v, "p2eq_087", 3)
	_step(v, 400.0)
	var vs: Array = (v["eq_state"]["p2eq_087"] as Dictionary).get("stolen", [])
	_ok("087 ★分母: 没有敌人时也还是偷到了几招(不是一招都没放出去 ⇒ 上一条不是空检查)",
		vs.size() >= 1, "已偷 %d 个: %s" % [vs.size(), str(vs)])
	_ok("087 ★空放不消耗名额: 场上没有活敌人时【猎龟令/驯服】反复被拒、名额一直留着,"
		+ " 另外 4 招(none/dir/point)全部偷完就停",
		vs.size() == 4 and not vs.has("tame") and not vs.has("hunt_order"),
		"已偷 %d 个: %s (期望 4 个且不含 tame/hunt_order)" % [vs.size(), str(vs)])

	# ── 换路重置: on_spawn 把本路已偷列表清空 ──
	_g().on_spawn(v, "p2eq_087", 2)
	_ok("087 ★换路重置: on_spawn 把本路已偷列表清空(下一路可以重新偷)",
		((v["eq_state"]["p2eq_087"] as Dictionary).get("stolen", []) as Array).is_empty(),
		"重置后 %d 个" % ((v["eq_state"]["p2eq_087"] as Dictionary).get("stolen", []) as Array).size())

	# ── ★偷谁走播种 RNG: 同种子重放序列一致 ──
	var s1: Array = _steal_trace(4242)
	var s2: Array = _steal_trace(4242)
	var s3: Array = _steal_trace(7)
	_ok("087 ★分母: 偷取序列非空", s1.size() >= 4, "长度 %d" % s1.size())
	_ok("087 ★焊死①: 偷谁走播种 `_battle_rng` —— 同种子重放序列【逐个相同】", s1 == s2,
		"重放一致=%s (%s)" % [str(s1 == s2), str(s1)])
	_ok("087 ★分母: 换种子序列【必须不同】(否则是按固定顺序偷, 上一条恒真)", s1 != s3,
		"seed4242=%s seed7=%s" % [str(s1), str(s3)])
	_s._units.clear()


func _steal_trace(seed_v: int) -> Array:
	_s._battle_rng.seed = seed_v
	var e: Dictionary = _mk("fortune", "right", Vector2(200, 0))
	e["maxHp"] = 9.0e7
	e["hp"] = 9.0e7
	var u: Dictionary = _mk("fortune", "left", Vector2(-200, 0))
	_equip(u, "p2eq_087", 3)
	_step(u, 30.0)
	var out: Array = ((u["eq_state"]["p2eq_087"] as Dictionary).get("stolen", []) as Array).duplicate()
	_s._units.clear()
	return out


# ─────────────────────────────────────────────────────────────
# ⑥ 撤场三条路 —— tick 推进演出 / 孤儿自扫 / 阵亡即撤 / clear_all
#    ★这一组是补上来的: 原先门禁一次都没调过 `EqGadgetBatch.tick(delta)`,
#      于是"演出到寿会不会 free""携带者没了会不会撤"全是没测过的代码。
# ─────────────────────────────────────────────────────────────
func _t_teardown() -> void:
	print("── ⑥ 撤场 / 孤儿自扫 / 演出推进 ──")
	var foe: Dictionary = _mk("fortune", "right", Vector2(200, 0))
	foe["maxHp"] = 9.0e7
	foe["hp"] = 9.0e7
	_g().tick(0.6)                      # 先把前几组留下的陈旧登记扫干净, 免得干扰计数
	await get_tree().process_frame

	# ── ① tick(delta) 真的推进演出寿命(不靠 tween, CLAUDE.md §3.5) ──
	var a: Dictionary = _mk("fortune", "left", Vector2(-200, 0))
	a["atk"] = 100.0
	a["base_atk"] = 100.0
	_equip(a, "p2eq_086", 3)
	var tr = _g().vfx.sextant_shot(a, foe)
	_ok("⑥ ★分母: 射击曳光真的建出来并挂进 battle._world", _in_world(tr),
		"parent=%s" % (str((tr as Node).get_parent()) if tr != null else "无节点"))
	_g().tick(0.05)
	var alive_early: bool = is_instance_valid(tr)
	_g().tick(0.2)
	await get_tree().process_frame
	_ok("⑥ `tick(delta)` 推进演出: 0.05 秒时曳光还在, 0.25 秒(>0.16 寿命)后被 free",
		alive_early and not is_instance_valid(tr),
		"0.05s 还在=%s / 0.25s 还在=%s (期望 true / false)"
		% [str(alive_early), str(is_instance_valid(tr))])

	# ── ② 孤儿自扫: 携带者从 battle._units 里消失(换路重建/被替换)⇒ 演出撤掉 ──
	var b: Dictionary = _mk("fortune", "left", Vector2(-260, 0))
	b["atk"] = 100.0
	b["base_atk"] = 100.0
	_equip(b, "p2eq_086", 3)
	_step(b, 3.1)
	var bn: Array = (b.get("_sext_nodes", []) as Array).duplicate()
	_ok("⑥ ★分母: 孤儿用例的浮游炮真的建出来了", bn.size() == 1 and _in_world(bn[0]),
		"节点 %d 个" % bn.size())
	for i in range(_s._units.size() - 1, -1, -1):
		if is_same(_s._units[i], b):
			_s._units.remove_at(i)
	_g().tick(0.6)
	await get_tree().process_frame
	_ok("⑥ ★自扫兜底: 携带者已不在 battle._units 里 ⇒ 0.5 秒内它的浮游炮被撤掉"
		+ "(换路不是节点变孤儿的唯一途径, clear_all 兜不到这条)",
		bn.size() == 1 and not is_instance_valid(bn[0]),
		"还活着=%s 期望 false" % str(bn.size() == 1 and is_instance_valid(bn[0])))

	# ── ③ 阵亡即撤: 走真入口 `_eq_on_death` ──
	var c: Dictionary = _mk("fortune", "left", Vector2(-320, 0))
	c["atk"] = 100.0
	c["base_atk"] = 100.0
	_equip(c, "p2eq_086", 3)
	_step(c, 3.1)
	var cn: Array = (c.get("_sext_nodes", []) as Array).duplicate()
	_ok("⑥ ★分母: 阵亡用例的浮游炮真的建出来了", cn.size() == 1 and _in_world(cn[0]),
		"节点 %d 个" % cn.size())
	c["alive"] = false
	_s._equip_sys._eq_on_death(c, null)
	await get_tree().process_frame
	_ok("⑥ 携带者阵亡 ⇒ 走真入口 `_equip_sys._eq_on_death` 就把浮游炮撤了",
		cn.size() == 1 and not is_instance_valid(cn[0]),
		"还活着=%s 期望 false" % str(cn.size() == 1 and is_instance_valid(cn[0])))

	# ── ④ clear_all(换路撤场): 浮游炮 + 水位计全收干净 ──
	var d: Dictionary = _mk("fortune", "left", Vector2(-380, 0), 1000.0)
	d["atk"] = 100.0
	d["base_atk"] = 100.0
	_equip(d, "p2eq_086", 3)
	_step(d, 3.1)
	var e7: Dictionary = _mk("fortune", "left", Vector2(-440, 0), 1000.0)
	_equip(e7, "p2eq_087", 3)
	_step(e7, 0.05)
	var dn: Array = (d.get("_sext_nodes", []) as Array).duplicate()
	var g7 = e7.get("_dive_bg", null)
	# ★还要放一条【不挂在任何携带者身上】的在途演出(终极射线)。
	#   只验"炮 + 水位计没了"是**假绿灯**: 那两样 `clear_all` 里的逐携带者 detach 循环
	#   就收掉了, 把 `vfx.clear()` 整行删掉这条断言照样绿(反向验证 ⑳ 实测 0 红)。
	#   在途射线不属于任何携带者 ⇒ **只有 `vfx.clear()` 收得掉**, 加上它才分得开。
	var rays: Array = _g().vfx.sextant_ultimate(d, [[Vector2(d["pos"]), Vector2(foe["pos"])]])
	_ok("⑥ ★分母: 换路前浮游炮 / 压载水位计 / 一条在途终极射线都在场上",
		dn.size() == 1 and _in_world(dn[0]) and _in_world(g7)
		and rays.size() == 1 and _in_world(rays[0]),
		"炮 %d 个 / 水位计=%s / 在途射线 %d 条" % [dn.size(), str(_in_world(g7)), rays.size()])
	_g().clear_all()
	await get_tree().process_frame
	_ok("⑥ ★换路撤场 `clear_all`: 浮游炮 + 水位计 + 【在途终极射线】全都真的没了"
		+ "(漏清就是把上一路的演出整个带进下一路, 而且不会报错)",
		dn.size() == 1 and not is_instance_valid(dn[0]) and not is_instance_valid(g7)
		and rays.size() == 1 and not is_instance_valid(rays[0]),
		"炮还活着=%s 水位计还活着=%s 在途射线还活着=%s (期望 三个 false)"
		% [str(dn.size() == 1 and is_instance_valid(dn[0])), str(is_instance_valid(g7)),
		str(rays.size() == 1 and is_instance_valid(rays[0]))])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ⑤ 演出层 —— 五条物理性质 + 节点真的进了 _world
# ─────────────────────────────────────────────────────────────
func _t_vfx_physics() -> void:
	print("── ⑤ 演出物理模型 ──")
	var vf = GVfx.new(_s)

	# ① 面能量密度守恒: r ∝ √E ⇒ 4 倍能量 = 2 倍半径(与 E 无关的纯尺度律)
	var ratios: Array = []
	for e in [1.0, 7.5, 60.0]:
		ratios.append(GVfx.spark_radius(e * 4.0) / maxf(1e-9, GVfx.spark_radius(e)))
	var ok1: bool = true
	for r in ratios:
		if absf(float(r) - 2.0) > 0.0005:
			ok1 = false
	_ok("⑤① 085 火花: 面能量密度守恒 ⇒ 半径 ∝ √E, 4 倍能量恰好 2 倍半径(线性会给 4)",
		ok1 and ratios.size() == 3, "三点比值 %s 期望 [2, 2, 2]" % str(ratios))

	# ② 正 n 边形排布: 最小两两角距 ≡ 2π/n, 且每门到中心距离全等
	var n: int = 6
	var offs: Array = []
	for k in range(n):
		offs.append(GVfx.orbit_offset(k, n, 0.37, 74.0))
	var min_gap: float = TAU
	var rmin: float = INF
	var rmax: float = -INF
	for i in range(n):
		rmin = minf(rmin, (offs[i] as Vector2).length())
		rmax = maxf(rmax, (offs[i] as Vector2).length())
		for j in range(n):
			if i == j:
				continue
			var g: float = absf(GVfx.orbit_angle(i, n, 0.0) - GVfx.orbit_angle(j, n, 0.0))
			g = minf(g, TAU - g)
			min_gap = minf(min_gap, g)
	_ok("⑤② 086 环绕: 6 门炮正六边形排布 ⇒ 最小两两角距 ≡ 2π/6 = 1.0472(挤成一堆会更小)",
		absf(min_gap - TAU / 6.0) < 1e-6, "实测 %.6f 期望 %.6f" % [min_gap, TAU / 6.0])
	_ok("⑤② 086 环绕: 6 门炮到携带者的距离【全等】(才叫环绕, 不是散在附近)",
		absf(rmax - rmin) < 1e-6 and absf(rmin - 74.0) < 1e-6,
		"min=%.6f max=%.6f 期望都是 74" % [rmin, rmax])

	# ③ 终极射线: 长度恒等式 + 朝向 + 指数余辉
	var a2 := Vector2(_s.ARENA.position.x + 100.0, _s.ARENA.position.y + 100.0)
	var b2 := Vector2(_s.ARENA.position.x + 700.0, _s.ARENA.position.y + 420.0)
	var beams: Array = vf.sextant_ultimate({}, [[a2, b2]])
	_ok("⑤③ ★分母: 终极射线真的建出了节点且【真的挂进 battle._world】",
		beams.size() == 1 and _in_world(beams[0]),
		"条数 %d parent=%s" % [beams.size(), str((beams[0] as Node).get_parent()) if beams.size() > 0 else "无"])
	var want_len: float = a2.distance_to(b2) * _s.WS
	_ok("⑤③ 086 射线长度 ≡ 两点真实距离 × WS(不是「看着差不多长」)",
		beams.size() == 1 and absf((beams[0] as MeshInstance3D).scale.x - want_len) < 1e-4,
		"scale.x=%.6f 期望 %.6f" % [(beams[0] as MeshInstance3D).scale.x if beams.size() > 0 else -1.0, want_len])
	var wa: Vector3 = _s._world_pos(a2, 0.0)
	var wb: Vector3 = _s._world_pos(b2, 0.0)
	var want_dir: Vector3 = (wb - wa).normalized()
	var got_dir: Vector3 = ((beams[0] as MeshInstance3D).global_transform.basis.x).normalized() if beams.size() > 0 else Vector3.ZERO
	_ok("⑤③ 086 射线【朝向】: 节点 basis 的 +X 轴 ≡ 两点世界方向单位向量"
		+ "(memory: 旋转互相抵消光看是看不出来的)",
		got_dir.dot(want_dir) > 0.99999, "点积 %.6f 期望 1.0" % got_dir.dot(want_dir))
	var a0: float = GVfx.ray_alpha(0.0)
	var ah: float = GVfx.ray_alpha(GVfx.RAY_HALF)
	var a2h: float = GVfx.ray_alpha(GVfx.RAY_HALF * 2.0)
	_ok("⑤③ 086 余辉走指数衰减: 一个半衰期剩 1/2, 两个半衰期剩 1/4(线性淡出给不出 1/4)",
		absf(ah / a0 - 0.5) < 1e-5 and absf(a2h / a0 - 0.25) < 1e-5,
		"1半衰=%.6f 2半衰=%.6f 期望 0.5 / 0.25" % [ah / a0, a2h / a0])

	# ④ 水柱: 定长径比柱体 ⇒ 半径 ∝ ∛V
	var jr: Array = []
	for v in [1.0, 12.5, 400.0]:
		jr.append(GVfx.jet_radius(v * 8.0) / maxf(1e-9, GVfx.jet_radius(v)))
	var ok4: bool = true
	for r in jr:
		if absf(float(r) - 2.0) > 0.0005:
			ok4 = false
	_ok("⑤④ 087 水柱: 定长径比柱体 ⇒ 半径 ∝ ∛V, 8 倍水量恰好 2 倍粗(线性给 8, 面积律给 2.83)",
		ok4 and jr.size() == 3, "三点比值 %s 期望 [2, 2, 2]" % str(jr))

	# ⑤ 压载水位计: 填充宽度 / 底槽宽度 ≡ 水位比
	var gu: Dictionary = _mk("fortune", "left", Vector2(0, 0), 1000.0)
	var fg = vf.dive_gauge(gu, 375.0, 1500.0)
	var bg = gu.get("_dive_bg", null)
	_ok("⑤⑤ ★分母: 水位计的底槽与填充条【真的挂进 battle._world】",
		_in_world(fg) and _in_world(bg),
		"fg=%s bg=%s" % [str(_in_world(fg)), str(_in_world(bg))])
	var ratio: float = (fg as MeshInstance3D).scale.x / maxf(1e-9, (bg as MeshInstance3D).scale.x)
	_ok("⑤⑤ 087 水位计: 填充宽度 / 底槽宽度 ≡ 水位比(375/1500 = 0.25)",
		absf(ratio - 0.25) < 1e-4, "实测 %.6f 期望 0.25" % ratio)
	var fg2 = vf.dive_gauge(gu, 1500.0, 1500.0)
	var ratio2: float = (fg2 as MeshInstance3D).scale.x / maxf(1e-9, (bg as MeshInstance3D).scale.x)
	_ok("⑤⑤ ★分母: 满舱时填充 ≡ 底槽全宽(比例真的在动, 不是两个都写死)",
		absf(ratio2 - 1.0) < 1e-4, "实测 %.6f 期望 1.0" % ratio2)

	# ── 撤场: detach / clear 真的 free 掉节点 ──
	var du: Dictionary = _mk("fortune", "left", Vector2(80, 0), 1000.0)
	var drones: Array = []
	for k in range(6):
		drones.append({"ang": float(k), "ft": 0.0, "sx": 0.0, "sy": 0.0, "scat": 0.0})
	var nodes: Array = vf.sextant_sync(du, drones, 74.0)
	vf.dive_gauge(du, 100.0, 1000.0)
	_ok("⑤ ★分母: 6 门炮体 + 水位计都建出来且挂进了 _world",
		nodes.size() == 6 and _in_world(nodes[0]) and _in_world(du.get("_dive_bg", null)),
		"炮体 %d 个" % nodes.size())
	var freed: int = vf.detach(du)
	_ok("⑤ 撤场: detach 真的 free 掉 6 门炮 + 水位计底槽/填充 = 8 个节点", freed == 8,
		"实测 free %d 个 期望 8" % freed)
	await get_tree().process_frame
	var still: int = 0
	for nd in nodes:
		if is_instance_valid(nd):
			still += 1
	_ok("⑤ 撤场: 下一帧那 6 个节点【真的没了】(不是只从表里摘掉)", still == 0,
		"还活着 %d 个 期望 0" % still)
	var left: int = vf.clear()
	_ok("⑤ clear() 把本层剩下的节点也收干净(返回真的 free 了几个 ≥ 1)", left >= 1,
		"free 了 %d 个" % left)
	_s._units.clear()
