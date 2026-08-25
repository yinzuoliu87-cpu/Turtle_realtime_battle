extends Node
## verify_eq_potion_batch.gd — 药水四件(065 鲨肝油 / 066 鲸涎浓浆 / 067 毒药瓶 / 068 深海气压罐)
## 逐件焊死 + 演出物理模型门禁。
##
## 规格 = docs/plans/20260805-装备逐件重做.md §0.5(用户逐件亲手写·已定稿)
## 接口 = docs/plans/20260805-实装契约.md §7
##
## ★本文件的规矩(照抄批①/批② 的口径, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。合成单位坐标放 ARENA 【内】。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 触发一律走【真入口】(_eq_on_basic_attack / _eq_on_target / _eq_on_death /
##     fire_equip_effect / tick_unit), 且至少各有一条经中央管线的端到端断言
##     (memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」)。
##   · 不依赖任何演出 tween(CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##   · 容差 < 0.51 或精确相等。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_potion_batch.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BeamVfxRef := preload("res://scripts/scenes/battle/mana_beam_vfx.gd")
const PVfx := preload("res://scripts/scenes/battle/potion_eq_vfx.gd")

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
## ★携带者一律用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%,
##   拿 basic 当携带者去验精确数值会量偏(批①/批②/20260801 三份门禁都实测过这个坑)。
func _mk(id: String, side: String, off: Vector2, hp: float = 1000.0) -> Dictionary:
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
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["size_mult"] = 1.0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["dot_stacks"] = {}
	u["dot_src"] = {}
	_s._units.append(u)
	return u


## 装上一件装备(只挂条目, 不跑属性管线 —— 属性会污染"效果加了多少"的量测)。
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 取【已剥注释】源码里某个函数的函数体(到下一个顶格 func 为止)。
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


## 节点真的挂进了 battle._world 吗(★美术断言不能只判"函数被调过")
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
	print("=== 药水四件 065/066/067/068 (2026-08-05 用户逐件重做) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	_t_dispatch()
	_t065_shark_oil()
	_t066_whale_brew()
	await _t067_poison_vial()
	_t068_pressure_can()
	_t_vfx_physics()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 药水四件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⓪ 分发纪律与接线 —— 四件各自落在指定的钩子上, 且旧实现【已删净】
# ─────────────────────────────────────────────────────────────
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	# ★先剥注释再找 —— 否则会命中我自己写的说明文字(前三份门禁的作者都因此吃过亏)
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	var apply: String = _strip("res://scripts/systems/equip/equip_stats_apply.gd")
	var batch: String = _strip("res://scripts/systems/equip/eq_potion_batch.gd")
	var rb_src: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var dmg_src: String = _strip("res://scripts/scenes/battle/battle_damage.gd")
	var render: String = _strip("res://scripts/scenes/battle/battle_render.gd")
	_ok("⓪ ★分母: 五份被读的源码都非空", code.length() > 20000 and apply.length() > 2000
		and batch.length() > 4000 and rb_src.length() > 50000 and dmg_src.length() > 5000,
		"equip=%d apply=%d batch=%d rb=%d dmg=%d" % [code.length(), apply.length(),
		batch.length(), rb_src.length(), dmg_src.length()])

	# ── 落点: 每件都在它该在的那个钩子里 ──
	var ba: String = _fn_body(code, "func _eq_on_basic_attack")
	var ot: String = _fn_body(code, "func _eq_on_target")
	var od: String = _fn_body(code, "func _eq_on_death")
	var fe: String = _fn_body(code, "func fire_equip_effect")
	var et: String = _fn_body(code, "func _eq_tick")
	var flags: String = _fn_body(apply, "func _eq_apply_flags")
	_ok("⓪ ★分母: 六个宿主函数体都非空", ba.length() > 200 and ot.length() > 200
		and od.length() > 200 and fe.length() > 200 and et.length() > 100 and flags.length() > 500,
		"ba=%d ot=%d od=%d fe=%d et=%d flags=%d" % [ba.length(), ot.length(), od.length(),
		fe.length(), et.length(), flags.length()])

	var miss: Array = []
	if not ba.contains("\"p2eq_065\": _potion_sys._eq_shark_oil("):
		miss.append("065 没接进 _eq_on_basic_attack")
	if not ba.contains("\"p2eq_068\": _potion_sys._eq_pressure_sip("):
		miss.append("068 普攻被动没接进 _eq_on_basic_attack")
	if not ba.contains("_potion_sys._eq_poison_touch("):
		miss.append("067 普攻中毒没接进 _eq_on_basic_attack")
	if not ot.contains("\"p2eq_068\": _potion_sys._eq_pressure_store("):
		miss.append("068 充能没接进 _eq_on_target")
	if not od.contains("\"p2eq_067\": _potion_sys._eq_vial_cleanse("):
		miss.append("067 阵亡撤减益没接进 _eq_on_death")
	if not fe.contains("\"p2eq_067\": _potion_sys._eq_poison_vial("):
		miss.append("067 周期投瓶没接进 fire_equip_effect")
	if not et.contains("_potion_sys.tick_unit("):
		miss.append("每帧 tick_unit 没接进 _eq_tick")
	_ok("⓪ 四件各自落在指定的钩子上(且分派写成 \"id\": _sys._fn( —— tooltip 审计靠这个锚点)",
		miss.is_empty(), str(miss))

	# ── 周期表: 067 的 6 秒写在 EQ_IV_BATCH1 里 ──
	## ★2026-08-25 文案根除: 这个 6.0 抽成了 EquipSystem.VIAL_IV(文案指着它),
	##   源码里已经没有 `"p2eq_067": 6.0` 这串字面量 —— 比【常量的值】+ 确认表确实引用它。
	_ok("⓪ 067 的触发间隔 6 秒登记在 EQ_IV_BATCH1",
		is_equal_approx(EquipSystem.VIAL_IV, 6.0)
			and (code.contains("\"p2eq_067\": VIAL_IV") or code.contains("\"p2eq_067\": 6.0")),
		"VIAL_IV=%.1f, 表里没引用它" % EquipSystem.VIAL_IV)

	# ── 常驻守卫: 四件都点亮 _potion_tick, 且 066/068 都预置了【本路】t0 ──
	var fmiss: Array = []
	for iid in ["p2eq_065", "p2eq_066", "p2eq_067", "p2eq_068"]:
		if not flags.contains("\"%s\"" % iid):
			fmiss.append("%s 不在 _eq_apply_flags 里" % iid)
	if not flags.contains("stt[\"brew_t0\"] = battle._t"):
		fmiss.append("066 没预置本路 t0(brew_t0)")
	if not flags.contains("stt[\"can_t0\"] = battle._t"):
		fmiss.append("068 没预置本路 t0(can_t0)")
	_ok("⓪ 四件都在 _eq_apply_flags 点亮 _potion_tick, 且 066/068 预置了本路 t0", fmiss.is_empty(), str(fmiss))
	_ok("⓪ ★分母: _eq_apply_flags 里 _potion_tick 出现 4 次(四件各一次)",
		flags.count("_potion_tick") == 4, "出现 %d 次" % flags.count("_potion_tick"))

	# ── ★★旧实现必须删净: 零调用者的死函数会被"断言函数存在"这类门禁保护住 ──
	#    (memory [[fb-verify-must-run-the-real-path]]: 我曾对着零调用者的死函数"目视确认新实现")
	var dead: Array = []
	for fn in ["_eq_spring_moss", "_eq_surge_brew", "_eq_hunter_flask", "elixir_total", "SURGE_ICD"]:
		if code.contains(fn):
			dead.append(fn)
	_ok("⓪ ★旧的 065/066/067/068 实现在 equip_system.gd 里已删净(不留死函数)",
		dead.is_empty(), "还剩: %s" % str(dead))

	# ── ★★接线: 这几个钩子【真的被中央管线调】—— 否则上面全绿而游戏里一件都不触发 ──
	_ok("⓪ ★★接线: 主场景的普攻真的调 _eq_on_basic_attack",
		rb_src.contains("_eq_on_basic_attack(u, tgt)"))
	_ok("⓪ ★★接线: battle_damage 的普攻/技能路真的调 _eq_on_target",
		dmg_src.contains("_eq_on_target(u, src, dmg)"))
	_ok("⓪ ★★接线: 主场景的周期分发真的调 fire_equip_effect",
		code.contains("fire_equip_effect(u, iid,"))
	_ok("⓪ ★★接线: 体型倍率 size_mult 真的被渲染层读(否则 066「+40% 体型」是看不见的)",
		render.contains("size_mult"), "battle_render.gd 里找不到 size_mult")

	# ── 效果本体确实住在自己的文件里(契约 §1: 一路一个文件) ──
	var own: Array = []
	for fn in ["func _eq_shark_oil(", "func _eq_whale_brew(", "func _eq_poison_vial(",
			"func _eq_vial_land(", "func _eq_poison_touch(", "func _eq_pressure_store(",
			"func _eq_pressure_release(", "func _eq_pressure_sip(", "func _eq_beam_step(",
			"func tick_unit("]:
		if not batch.contains(fn):
			own.append(fn)
	_ok("⓪ 十个效果函数都住在 eq_potion_batch.gd(契约 §1 一路一个文件)", own.is_empty(), str(own))


# ─────────────────────────────────────────────────────────────
# 065 / 066 / 067 / 068 / 演出物理 —— 逐件填充(见下)
# ─────────────────────────────────────────────────────────────
## 065 鲨肝油(药水·3费):
##   属性 射程+50(三星同值) / 攻速 10/20/30% / 吸血 3/6/10%
##   效果 每次普攻 +5 龟能; 每次普攻 +1/2/4% 攻速, ★不设上限, 换路重置
func _t065_shark_oil() -> void:
	print("── 065 鲨肝油 · 普攻滚雪球攻速 + 龟能 ──")
	# ① 属性表(期望值硬写, 不读 STATS 自己)
	var st: Array = _s.EquipStats.STATS.get("p2eq_065", [])
	_ok("065 ★分母: STATS 里有三星三条", st.size() == 3, "size=%d" % st.size())
	var bad: Array = []
	var want_r: Array = [50, 50, 50]
	var want_a: Array = [10, 20, 30]
	var want_l: Array = [3, 6, 10]
	for i in range(mini(3, st.size())):
		if int((st[i] as Dictionary).get("_rangeAdd", -1)) != int(want_r[i]):
			bad.append("★%d 射程 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("_rangeAdd", "无")), int(want_r[i])])
		if int((st[i] as Dictionary).get("_aspdPct", -1)) != int(want_a[i]):
			bad.append("★%d 攻速 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("_aspdPct", "无")), int(want_a[i])])
		if int((st[i] as Dictionary).get("_lifestealPct", -1)) != int(want_l[i]):
			bad.append("★%d 吸血 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("_lifestealPct", "无")), int(want_l[i])])
	_ok("065 属性 = 射程+50/50/50 · 攻速+10/20/30% · 吸血+3/6/10%", bad.is_empty(), str(bad))

	# ② ★射程走 flat 通道 `range_add`, 且 `_eff_range` 先加后乘 —— 端到端量真实射程
	_s._units.clear()
	var r0: Dictionary = _mk("fortune", "left", Vector2(-300.0, -160.0), 1000.0)
	r0["atk_range"] = 70.0
	r0["range_add"] = 0.0
	r0["range_perm"] = 1.0
	_ok("065 ★分母: 不带装备时射程就是基础 70", absf(_s._eff_range(r0) - 70.0) < 0.51,
		"实得 %.2f" % _s._eff_range(r0))
	var r1: Dictionary = _mk("fortune", "left", Vector2(-260.0, -160.0), 1000.0)
	r1["atk_range"] = 70.0
	r1["range_add"] = 0.0
	r1["range_perm"] = 1.0
	_s._equip_sys._stats._eq_apply_one_stats(r1, "p2eq_065", 1)
	_ok("065 ★射程是 flat 50 码(近战 70 → 120), 走 range_add 不是百分比",
		absf(_s._eff_range(r1) - 120.0) < 0.51, "实得 %.2f 期望 120" % _s._eff_range(r1))
	_ok("065 1★ 被动攻速 +10% 落到 aspd_perm(1.00 → 1.10)",
		absf(float(r1.get("aspd_perm", 1.0)) - 1.10) < 0.005, "实得 %.4f" % float(r1.get("aspd_perm", 1.0)))
	_ok("065 1★ 吸血 +3% 落到 lifesteal(0 → 0.03)",
		absf(float(r1.get("lifesteal", 0.0)) - 0.03) < 0.005, "实得 %.4f" % float(r1.get("lifesteal", 0.0)))
	# ★分母: 射程加成【不是】百分比 —— 若误写成 range_perm, 70×1.5 也是 105 而不是 120
	_ok("065 ★分母: range_perm 一点没动(证明加的是 flat 通道不是倍率通道)",
		absf(float(r1.get("range_perm", 1.0)) - 1.0) < 0.001, "range_perm=%.4f" % float(r1.get("range_perm", 1.0)))

	# ③ 每次普攻叠攻速 —— 走【真入口】_eq_on_basic_attack
	for si in range(3):
		var per: float = [0.01, 0.02, 0.04][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -120.0), 1000.0), "p2eq_065", si + 1)
		u["skill_cd"] = {}          # 清空技能冷却 → 龟能银行不被抽走, 量得到 +5 本身
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, -120.0), 9000.0)
		_s._equip_sys._eq_on_basic_attack(u, t)
		_ok("065 si=%d 一次普攻 +%.0f%% 攻速(需求 1/2/4%%)" % [si, per * 100.0],
			absf(float(u.get("aspd_perm", 1.0)) - (1.0 + per)) < 0.0005,
			"aspd_perm %.4f 期望 %.4f" % [float(u.get("aspd_perm", 1.0)), 1.0 + per])
		_ok("065 si=%d 一次普攻 +5 龟能(进龟能银行)" % si,
			absf(float(u.get("energy_bank", 0.0)) - 5.0) < 0.005,
			"energy_bank %.2f" % float(u.get("energy_bank", 0.0)))
		# ★不设上限(用户 2026-08-05 原话「没上限」): 再打 199 次, 一共 200 次
		for _k in range(199):
			_s._equip_sys._eq_on_basic_attack(u, t)
		_ok("065 si=%d ★不设上限: 200 次普攻 = 1 + 200×%.2f = %.2f" % [si, per, 1.0 + 200.0 * per],
			absf(float(u.get("aspd_perm", 1.0)) - (1.0 + 200.0 * per)) < 0.005,
			"aspd_perm %.4f 期望 %.4f" % [float(u.get("aspd_perm", 1.0)), 1.0 + 200.0 * per])
		_ok("065 si=%d 200 次普攻 = 1000 龟能(每次 5 点, 不漏不重)" % si,
			absf(float(u.get("energy_bank", 0.0)) - 1000.0) < 0.51,
			"energy_bank %.2f 期望 1000" % float(u.get("energy_bank", 0.0)))
		_ok("065 si=%d 层数计到 eq_state(200 层)" % si,
			int(u["eq_state"].get("p2eq_065", {}).get("oil_stacks", 0)) == 200,
			"oil_stacks=%d" % int(u["eq_state"].get("p2eq_065", {}).get("oil_stacks", 0)))

	# ④ ★分母: 不带 065 的单位普攻, 攻速与龟能一点不动(证明上面不是"谁普攻都涨")
	_s._units.clear()
	var nb: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -80.0), 1000.0), "p2eq_002", 3)
	nb["skill_cd"] = {}
	var nt: Dictionary = _mk("basic", "right", Vector2(-100.0, -80.0), 9000.0)
	for _k in range(20):
		_s._equip_sys._eq_on_basic_attack(nb, nt)
	_ok("065 ★分母: 不带 065 的单位打 20 次普攻 → 攻速/龟能一点没动",
		absf(float(nb.get("aspd_perm", 1.0)) - 1.0) < 0.0005 and absf(float(nb.get("energy_bank", 0.0))) < 0.005,
		"aspd_perm=%.4f bank=%.2f" % [float(nb.get("aspd_perm", 1.0)), float(nb.get("energy_bank", 0.0))])

	# ⑤ ★换路重置: 层数只存在【单位字典】上, 系统对象里不留任何跨单位/跨路的残留。
	#    造第二只同款携带者, 只打 1 次 → 必须是 1.04 而不是接着上一只的 9.00。
	_s._units.clear()
	var a2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -40.0), 1000.0), "p2eq_065", 3)
	a2["skill_cd"] = {}
	var t2: Dictionary = _mk("basic", "right", Vector2(-100.0, -40.0), 9000.0)
	for _k in range(50):
		_s._equip_sys._eq_on_basic_attack(a2, t2)
	var b2: Dictionary = _equip(_mk("fortune", "left", Vector2(-260.0, -40.0), 1000.0), "p2eq_065", 3)
	b2["skill_cd"] = {}
	_s._equip_sys._eq_on_basic_attack(b2, t2)
	_ok("065 ★换路重置: 新建的携带者从 1.00 起算(1 次普攻 = 1.04, 不接上一只的 3.00)",
		absf(float(b2.get("aspd_perm", 1.0)) - 1.04) < 0.0005,
		"新单位 aspd_perm=%.4f 期望 1.0400; 老单位 %.4f" % [float(b2.get("aspd_perm", 1.0)), float(a2.get("aspd_perm", 1.0))])
	_s._units.clear()


## 066 鲸涎浓浆(药水·4费): 登场第 11 秒喝药 → 免疫控制到战斗结束 + 十项属性 + 体型 +40%。
## ★★两颗地雷都在这一件上: ① CLAUDE.md §3.4 `_t` 跨路累加(必须自存 t0);
##   ② 免疫是【五条通道】, 只挡一条 = 半个免疫。
func _t066_whale_brew() -> void:
	print("── 066 鲸涎浓浆 · 第 11 秒变身 + 五条通道免控 ──")
	# ① 属性表(期望值硬写)
	var st: Array = _s.EquipStats.STATS.get("p2eq_066", [])
	_ok("066 ★分母: STATS 里有三星三条", st.size() == 3, "size=%d" % st.size())
	var bad: Array = []
	var we: Array = [20, 35, 60]
	var wm: Array = [6, 11, 18]
	for i in range(mini(3, st.size())):
		if int((st[i] as Dictionary).get("_maxEnergy", -1)) != int(we[i]):
			bad.append("★%d 初始龟能 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("_maxEnergy", "无")), int(we[i])])
		if int((st[i] as Dictionary).get("_mspdPct", -1)) != int(wm[i]):
			bad.append("★%d 移速 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("_mspdPct", "无")), int(wm[i])])
	_ok("066 属性 = 初始龟能+20/35/60 · 移速+6/11/18%", bad.is_empty(), str(bad))

	# ② ★★CLAUDE.md §3.4: 全局钟 `_t` 跨上路→下路→决胜累加、永不重置。
	#    把 `_t` 推到 5000(= 已经打过上路)再开新的一路 —— 直接判 `_t >= 11` 会【一开场就喝】。
	_s._units.clear()
	var t_save: float = _s._t
	_s._t = 5000.0
	var d1: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 0.0), 1000.0), "p2eq_066", 3)
	_s._equip_sys._stats._eq_apply_one_stats(d1, "p2eq_066", 3)   # 走真管线预置本路 t0
	_ok("066 ★分母: 本路开战管线把 t0 记成【当前】时刻 5000(不是 0)",
		absf(float(d1["eq_state"]["p2eq_066"].get("brew_t0", -1.0)) - 5000.0) < 0.51,
		"brew_t0=%.2f" % float(d1["eq_state"]["p2eq_066"].get("brew_t0", -1.0)))
	var atk_ref: float = float(d1["base_atk"])
	_s._equip_sys._potion_sys.tick_unit(d1, 0.016)
	_ok("066 ★★跨路地雷: 下路一开场(_t=5000, 本路才过 0 秒) → 【不】喝药",
		not bool(d1["eq_state"]["p2eq_066"].get("brew_done", false)),
		"brew_done=%s base_atk %.1f→%.1f" % [str(d1["eq_state"]["p2eq_066"].get("brew_done", false)),
		atk_ref, float(d1["base_atk"])])
	_s._t = 5010.9
	_s._equip_sys._potion_sys.tick_unit(d1, 0.016)
	_ok("066 ★本路第 10.9 秒仍不喝(阈值是 11 秒整, 不是 10)",
		not bool(d1["eq_state"]["p2eq_066"].get("brew_done", false)),
		"brew_done=%s" % str(d1["eq_state"]["p2eq_066"].get("brew_done", false)))
	_s._t = 5011.05
	_s._equip_sys._potion_sys.tick_unit(d1, 0.016)
	_ok("066 ★本路第 11.05 秒 → 喝下去了",
		bool(d1["eq_state"]["p2eq_066"].get("brew_done", false)),
		"brew_done=%s" % str(d1["eq_state"]["p2eq_066"].get("brew_done", false)))

	# ③ 十项属性(3★, 期望值逐条硬写自 §0.5 的表)
	var got: Array = []
	var checks := [
		["生命偷取 +20%", float(d1.get("lifesteal", 0.0)), 0.20, 0.005],
		["最大生命 +400", float(d1["maxHp"]) - 1000.0, 400.0, 0.51],
		["护甲 +25", float(d1["base_def"]), 25.0, 0.51],
		["魔抗 +25", float(d1["base_mr"]), 25.0, 0.51],
		["攻速 +25%", float(d1.get("aspd_perm", 1.0)) - 1.0, 0.25, 0.005],
		["暴击率 +25%", float(d1.get("crit", 0.0)), 0.25, 0.005],
		["暴击伤害 +18%", float(d1.get("crit_dmg", 1.5)) - 1.5, 0.18, 0.005],
		["龟能充能 +10%", float(d1.get("echarge_perm", 1.0)) - 1.0, 0.10, 0.005],
		["攻击力 +25", float(d1["base_atk"]) - atk_ref, 25.0, 0.51],
		["护甲穿透 +10", float(d1.get("armor_pen", 0.0)), 10.0, 0.51],
		["魔法穿透 +10", float(d1.get("magic_pen", 0.0)), 10.0, 0.51],
	]
	for c in checks:
		if absf(float(c[1]) - float(c[2])) >= float(c[3]):
			got.append("%s 实得 %.4f 期望 %.4f" % [str(c[0]), float(c[1]), float(c[2])])
	_ok("066 3★ 喝药后十一项属性逐条对上(§0.5 的表)", got.is_empty(), str(got))
	_ok("066 ★生命是【最大生命与当前生命同时 +400】(不是只加上限)",
		absf(float(d1["hp"]) - 1400.0) < 0.51, "hp=%.1f 期望 1400" % float(d1["hp"]))

	# ④ 只喝一次: 再 tick 200 次(时间一路推到本路第 60 秒), 属性不再涨
	var atk_after: float = float(d1["base_atk"])
	var hp_after: float = float(d1["maxHp"])
	for k in range(200):
		_s._t = 5011.05 + float(k) * 0.25
		_s._equip_sys._potion_sys.tick_unit(d1, 0.25)
	_ok("066 ★只喝一次: 再跑 200 帧(到本路第 60 秒) 攻击力/最大生命一点不再涨",
		absf(float(d1["base_atk"]) - atk_after) < 0.01 and absf(float(d1["maxHp"]) - hp_after) < 0.01,
		"base_atk %.1f→%.1f maxHp %.1f→%.1f" % [atk_after, float(d1["base_atk"]), hp_after, float(d1["maxHp"])])

	# ⑤ 体型 +40% —— 真的写进 u["size_mult"](battle_render 读它, 影子跟着涨)
	var brew_t: float = float(d1["eq_state"]["p2eq_066"].get("brew_at_t", 0.0))
	_s._t = brew_t + 2.0
	_s._equip_sys._potion_sys.tick_unit(d1, 0.016)
	_ok("066 体型终值 = ×1.40(+40%, 三星同值)",
		absf(float(d1.get("size_mult", 1.0)) - 1.40) < 0.005,
		"size_mult=%.4f 期望 1.4000" % float(d1.get("size_mult", 1.0)))
	# ★过冲: 首峰时刻的体型必须【超过】终值(阻尼振子的超调, 单调缓动给不出)
	_s._t = brew_t + 0.193721      # t_p = π/ω_d, ζ=0.30 ωn=17.0 ⇒ ω_d=16.216967
	_s._equip_sys._potion_sys.tick_unit(d1, 0.016)
	_ok("066 ★变身瞬间【过冲回稳】: 首峰体型 = 1 + 0.40×1.372275 = 1.5489(> 终值 1.40)",
		absf(float(d1.get("size_mult", 1.0)) - 1.548910) < 0.005,
		"峰值 size_mult=%.4f 期望 1.5489" % float(d1.get("size_mult", 1.0)))
	_s._t = brew_t + 3.0
	_s._equip_sys._potion_sys.tick_unit(d1, 0.016)

	# ⑥ ★★五条免疫通道 —— 逐条量, 且每条都配一个【没喝药】的同款单位当分母
	_s._units.clear()
	_s._t = 6000.0
	var im: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 40.0), 1000.0), "p2eq_066", 3)
	im["eq_state"]["p2eq_066"] = {"brew_t0": 5988.0, "brew_done": false}
	_s._equip_sys._potion_sys.tick_unit(im, 0.016)
	_ok("066 ★分母: 免疫组的携带者确实已经喝下去了(否则下面全是空检查)",
		bool(im["eq_state"]["p2eq_066"].get("brew_done", false)),
		"brew_done=%s" % str(im["eq_state"]["p2eq_066"].get("brew_done", false)))
	var ctl: Dictionary = _equip(_mk("fortune", "left", Vector2(-260.0, 40.0), 1000.0), "p2eq_002", 3)
	var foe: Dictionary = _mk("basic", "right", Vector2(100.0, 40.0), 9000.0)

	# a) 眩晕
	_s._damage._stun(im, 3.0, "test")
	_s._damage._stun(ctl, 3.0, "test")
	_ok("066 免疫① 眩晕: 携带者不进眩晕(cc_immune_until 挡在唯一入口)",
		float(im.get("stun_until", 0.0)) <= _s._t, "stun_until=%.2f _t=%.2f" % [float(im.get("stun_until", 0.0)), _s._t])
	_ok("066 免疫① ★分母: 同一发眩晕打在没喝药的单位上【是生效的】",
		float(ctl.get("stun_until", 0.0)) > _s._t, "对照 stun_until=%.2f" % float(ctl.get("stun_until", 0.0)))
	# b) 冻结(走同一个唯一入口, 但要单独验 —— 它是另一个调用点)
	_s._freeze(im, 3.0)
	_ok("066 免疫② 冻结: 携带者不进冻结",
		float(im.get("stun_until", 0.0)) <= _s._t, "stun_until=%.2f" % float(im.get("stun_until", 0.0)))
	# c) 击飞
	im["airborne"] = false
	ctl["airborne"] = false
	_s._damage._knockback(foe, im, 60.0)
	_s._damage._knockback(foe, ctl, 60.0)
	_ok("066 免疫③ 击飞: 携带者不被击飞(_knock_immune)",
		not bool(im.get("airborne", false)), "airborne=%s" % str(im.get("airborne", false)))
	_ok("066 免疫③ ★分母: 同一发击飞打在没喝药的单位上【是生效的】",
		bool(ctl.get("airborne", false)), "对照 airborne=%s" % str(ctl.get("airborne", false)))
	ctl["airborne"] = false
	# d) 减速通道一: slow_until / slow_mag
	im["slow_until"] = _s._t + 5.0
	im["slow_mag"] = 0.4
	ctl["slow_until"] = _s._t + 5.0
	ctl["slow_mag"] = 0.4
	_s._equip_sys._potion_sys.tick_unit(im, 0.016)
	_ok("066 免疫④ 减速通道一(slow_until/slow_mag): 携带者身上清掉了",
		float(im.get("slow_until", 0.0)) <= _s._t, "slow_until=%.2f _t=%.2f" % [float(im.get("slow_until", 0.0)), _s._t])
	_ok("066 免疫④ ★分母: 同一条减速挂在没喝药的单位上【留得住】",
		float(ctl.get("slow_until", 0.0)) > _s._t, "对照 slow_until=%.2f" % float(ctl.get("slow_until", 0.0)))
	# e) 减速通道二 + 减攻速: spd_move_mult / spd_aspd_mult + spd_dbf_until
	#    ⚠ 这是【另一条并行通道】, 只挡通道一 = 半个免疫(契约 §4 焊死)
	im["spd_move_mult"] = 0.5
	im["spd_aspd_mult"] = 0.7
	im["spd_dbf_until"] = _s._t + 5.0
	ctl["spd_move_mult"] = 0.5
	ctl["spd_aspd_mult"] = 0.7
	ctl["spd_dbf_until"] = _s._t + 5.0
	_s._equip_sys._potion_sys.tick_unit(im, 0.016)
	_ok("066 免疫⑤ 减速通道二(spd_move_mult): 0.5 → 1.0",
		absf(float(im.get("spd_move_mult", 1.0)) - 1.0) < 0.001, "spd_move_mult=%.3f" % float(im.get("spd_move_mult", 1.0)))
	_ok("066 免疫⑥ 减攻速(spd_aspd_mult): 0.7 → 1.0",
		absf(float(im.get("spd_aspd_mult", 1.0)) - 1.0) < 0.001, "spd_aspd_mult=%.3f" % float(im.get("spd_aspd_mult", 1.0)))
	_ok("066 免疫⑤⑥ ★分母: 同两条挂在没喝药的单位上【留得住】(0.5 / 0.7 原样)",
		absf(float(ctl.get("spd_move_mult", 1.0)) - 0.5) < 0.001 and absf(float(ctl.get("spd_aspd_mult", 1.0)) - 0.7) < 0.001,
		"对照 move=%.3f aspd=%.3f" % [float(ctl.get("spd_move_mult", 1.0)), float(ctl.get("spd_aspd_mult", 1.0))])
	# ★不许误伤【增益】: 同一条通道也被熔岩/凤凰用来加速, 抹掉就是没收自己的加速
	im["spd_move_mult"] = 1.3
	im["spd_dbf_until"] = _s._t + 5.0
	_s._equip_sys._potion_sys.tick_unit(im, 0.016)
	_ok("066 ★不误伤增益: 同通道的【加速】(1.3, 熔岩/凤凰在用)一点不动",
		absf(float(im.get("spd_move_mult", 1.0)) - 1.3) < 0.001, "spd_move_mult=%.3f 期望 1.300" % float(im.get("spd_move_mult", 1.0)))
	# f) 僵硬(奇械羁绊的减攻速, 走 stiff_stacks 另一套)
	_s._gadget_syn.add_stiff(im, 5)
	_s._gadget_syn.add_stiff(ctl, 5)
	_s._equip_sys._potion_sys.tick_unit(im, 0.016)
	_ok("066 免疫⑦ 僵硬(奇械 stiff_stacks): 5 层 → 0 层",
		int(im.get("stiff_stacks", 0)) == 0, "stiff_stacks=%d" % int(im.get("stiff_stacks", 0)))
	_ok("066 免疫⑦ ★分母: 同样 5 层僵硬挂在没喝药的单位上【留得住】",
		int(ctl.get("stiff_stacks", 0)) == 5, "对照 stiff_stacks=%d" % int(ctl.get("stiff_stacks", 0)))
	# g) 嘲讽
	_s._taunt(foe, [im, ctl], 5.0)
	_s._equip_sys._potion_sys.tick_unit(im, 0.016)
	_ok("066 免疫⑧ 嘲讽: taunt_until 清零且 taunt_by 断开",
		float(im.get("taunt_until", 0.0)) <= _s._t and im.get("taunt_by", null) == null,
		"taunt_until=%.2f taunt_by=%s" % [float(im.get("taunt_until", 0.0)), str(im.get("taunt_by", null) != null)])
	_ok("066 免疫⑧ ★分母: 同一次嘲讽挂在没喝药的单位上【留得住】",
		float(ctl.get("taunt_until", 0.0)) > _s._t and ctl.get("taunt_by", null) != null,
		"对照 taunt_until=%.2f" % float(ctl.get("taunt_until", 0.0)))
	_s._t = t_save
	_s._units.clear()


## 067 毒药瓶(药水·4费):
##   ① 每 6 秒朝【敌人最密集处】投瓶 → 400 码内 +40/70/110 层中毒
##   ② 携带者存活时, 中毒的敌人受到的治疗与获得的护盾【减半】
##   ③ 普攻额外 +3/5/8 层中毒
func _t067_poison_vial() -> void:
	print("── 067 毒药瓶 · 最密集处投瓶 + 中毒者反治疗 ──")
	# ① 属性表(期望值硬写)
	var st: Array = _s.EquipStats.STATS.get("p2eq_067", [])
	_ok("067 ★分母: STATS 里有三星三条", st.size() == 3, "size=%d" % st.size())
	var bad: Array = []
	var wh: Array = [110, 280, 650]
	var wa: Array = [15, 38, 90]
	var wp: Array = [10, 20, 38]
	for i in range(mini(3, st.size())):
		if int((st[i] as Dictionary).get("hp", -1)) != int(wh[i]):
			bad.append("★%d 生命 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("hp", "无")), int(wh[i])])
		if int((st[i] as Dictionary).get("atk", -1)) != int(wa[i]):
			bad.append("★%d 攻击 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("atk", "无")), int(wa[i])])
		if int((st[i] as Dictionary).get("magicPen", -1)) != int(wp[i]):
			bad.append("★%d 法穿 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("magicPen", "无")), int(wp[i])])
	_ok("067 属性 = 生命110/280/650 · 攻15/38/90 · 法穿10/20/38", bad.is_empty(), str(bad))

	# ② ★「最密集的地方」: 以每个敌人为圆心取 400 码数圈内敌人数, 取最多的那个位置。
	#    摆一个 3 人簇(彼此 <400) + 一个孤立的远处敌 ⇒ 落点必须落在簇里, n=3。
	_s._units.clear()
	var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, 80.0), 3000.0), "p2eq_067", 3)
	# ★★孤立的那只【故意排在最前面】—— 否则"取第一个"这种错误实现会和"取最密集的"
	#   碰巧同解, 这条断言就成了永远绿的假门禁(反向验证时实测撞到过, 已改)。
	var far: Dictionary = _mk("basic", "right", Vector2(560.0, 80.0), 9000.0)
	var e1: Dictionary = _mk("basic", "right", Vector2(0.0, 80.0), 9000.0)
	var e2: Dictionary = _mk("basic", "right", Vector2(120.0, 80.0), 9000.0)
	var e3: Dictionary = _mk("basic", "right", Vector2(-120.0, 80.0), 9000.0)
	var d0: Dictionary = _s._equip_sys._potion_sys._eq_vial_dest(c)
	_ok("067 ★分母: 场上 4 个敌人都在敌方名单里(否则密度是空算的)",
		_s._targeting._enemies_of(c).size() == 4, "敌人数=%d" % _s._targeting._enemies_of(c).size())
	_ok("067 ★最密集处 = 3 人簇的中心那只(圈内 3 人), 不是随便一只",
		bool(d0["ok"]) and int(d0["n"]) == 3 and ((d0["pos"] as Vector2) - (e1["pos"] as Vector2)).length() < 0.51,
		"落点 %s 期望 %s n=%d" % [str(d0["pos"]), str(e1["pos"]), int(d0["n"])])
	_ok("067 ★分母: 孤立的远处敌(圈内只有它自己 1 人)【没被选中】",
		((d0["pos"] as Vector2) - (far["pos"] as Vector2)).length() > 0.51,
		"落点 %s 孤立敌 %s" % [str(d0["pos"]), str(far["pos"])])
	# ★确定性、不掷骰: 连算 30 次结果逐字节一致
	var same := true
	for _k in range(30):
		var dk: Dictionary = _s._equip_sys._potion_sys._eq_vial_dest(c)
		if (dk["pos"] as Vector2) != (d0["pos"] as Vector2) or int(dk["n"]) != int(d0["n"]):
			same = false
	_ok("067 ★判据是确定性的: 连算 30 次落点与人数完全一致(不掷骰)", same, "落点 %s" % str(d0["pos"]))

	# ③ 落地施毒 —— 走【真结算入口】_eq_vial_land, 不等抛物线演出(CLAUDE.md §3.5)
	for si in range(3):
		var want: int = [40, 70, 110][si]
		_s._units.clear()
		var k: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, 120.0), 3000.0), "p2eq_067", si + 1)
		var near: Dictionary = _mk("basic", "right", Vector2(0.0, 120.0), 9000.0)
		var edge: Dictionary = _mk("basic", "right", Vector2(390.0, 120.0), 9000.0)
		var out: Dictionary = _mk("basic", "right", Vector2(460.0, 120.0), 9000.0)
		_s._equip_sys._potion_sys._eq_vial_land(k, si, Vector2(near["pos"]))
		_ok("067 si=%d 落点上的敌人 +%d 层中毒(需求 40/70/110)" % [si, want],
			int((near["dot_stacks"] as Dictionary).get("poison", 0)) == want,
			"实得 %d 层" % int((near["dot_stacks"] as Dictionary).get("poison", 0)))
		_ok("067 si=%d 半径边缘内(390 码 < 400)照样中毒 %d 层" % [si, want],
			int((edge["dot_stacks"] as Dictionary).get("poison", 0)) == want,
			"实得 %d 层" % int((edge["dot_stacks"] as Dictionary).get("poison", 0)))
		_ok("067 si=%d ★分母: 400 码外(460 码)的敌人一层都没有" % si,
			int((out["dot_stacks"] as Dictionary).get("poison", 0)) == 0,
			"实得 %d 层" % int((out["dot_stacks"] as Dictionary).get("poison", 0)))

	# ④ 普攻额外中毒 3/5/8 层 —— 走真入口 _eq_on_basic_attack
	for si in range(3):
		var want2: int = [3, 5, 8][si]
		_s._units.clear()
		var k2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 160.0), 3000.0), "p2eq_067", si + 1)
		var t2: Dictionary = _mk("basic", "right", Vector2(-100.0, 160.0), 9000.0)
		_s._equip_sys._eq_on_basic_attack(k2, t2)
		_ok("067 si=%d 普攻额外 +%d 层中毒(需求 3/5/8)" % [si, want2],
			int((t2["dot_stacks"] as Dictionary).get("poison", 0)) == want2,
			"实得 %d 层" % int((t2["dot_stacks"] as Dictionary).get("poison", 0)))

	# ⑤ ★中毒是【既有机制】不是另造的: 每秒伤害 = 当前层数, 结算后层数衰减到 80%
	_s._units.clear()
	var p1: Dictionary = _mk("basic", "right", Vector2(0.0, 200.0), 9000.0)
	p1["dot_stacks"] = {"poison": 100}
	var hp0: float = float(p1["hp"])
	_s._tick_dot_stacks(p1)
	_ok("067 ★复用既有中毒: 100 层 → 这一跳掉 100 点(每秒伤害=层数, 魔抗 0)",
		absf(hp0 - float(p1["hp"]) - 100.0) < 0.51, "实掉 %.1f" % (hp0 - float(p1["hp"])))
	_ok("067 ★复用既有中毒: 结算后层数衰减到 80(80%)",
		int((p1["dot_stacks"] as Dictionary).get("poison", 0)) == 80,
		"实得 %d 层" % int((p1["dot_stacks"] as Dictionary).get("poison", 0)))

	# ⑥ ★被动: 中毒的敌人 受到的治疗 与 获得的护盾 各【减半】—— 端到端量真实治疗/护盾
	_s._units.clear()
	var carrier: Dictionary = _equip(_mk("fortune", "left", Vector2(-400.0, 240.0), 3000.0), "p2eq_067", 3)
	var sick: Dictionary = _mk("basic", "right", Vector2(0.0, 240.0), 9000.0)
	var well: Dictionary = _mk("basic", "right", Vector2(120.0, 240.0), 9000.0)
	sick["dot_stacks"] = {"poison": 10}
	sick["hp"] = 5000.0
	well["hp"] = 5000.0
	_s._equip_sys._potion_sys.tick_unit(carrier, 0.016)
	var sh0: float = float(sick["hp"])
	var wh0: float = float(well["hp"])
	_s._damage._heal(sick, 100.0)
	_s._damage._heal(well, 100.0)
	_ok("067 ★中毒者受到的治疗减半: 100 → 50",
		absf(float(sick["hp"]) - sh0 - 50.0) < 0.51, "实回 %.2f 期望 50" % (float(sick["hp"]) - sh0))
	_ok("067 ★分母: 没中毒的敌人照收满额 100",
		absf(float(well["hp"]) - wh0 - 100.0) < 0.51, "实回 %.2f 期望 100" % (float(well["hp"]) - wh0))
	sick["shield"] = 0.0
	well["shield"] = 0.0
	_s._damage._grant_shield(sick, 100.0)
	_s._damage._grant_shield(well, 100.0)
	_ok("067 ★中毒者获得的护盾减半: 100 → 50",
		absf(float(sick["shield"]) - 50.0) < 0.51, "实得 %.2f 期望 50" % float(sick["shield"]))
	_ok("067 ★分母: 没中毒的敌人照收满额 100 护盾",
		absf(float(well["shield"]) - 100.0) < 0.51, "实得 %.2f 期望 100" % float(well["shield"]))

	# ⑦ ★★口径钉死: 是【×0.5】不是【−0.5 个百分点】。
	#    目标本来带 +30% 护盾增幅 ⇒ ×0.5 得 100×1.30×0.5 = 65; 若写成 -0.5 会得到 100×0.80 = 80。
	_s._units.clear()
	var c3: Dictionary = _equip(_mk("fortune", "left", Vector2(-400.0, 280.0), 3000.0), "p2eq_067", 3)
	var amp: Dictionary = _mk("basic", "right", Vector2(0.0, 280.0), 9000.0)
	amp["dot_stacks"] = {"poison": 10}
	amp["shield_amp"] = 0.30
	_s._equip_sys._potion_sys.tick_unit(c3, 0.016)
	amp["shield"] = 0.0
	_s._damage._grant_shield(amp, 100.0)
	_ok("067 ★口径 ×0.5 而不是 −50 个百分点: 目标自带 +30% 盾增 ⇒ 100×1.30×0.5 = 65(不是 80)",
		absf(float(amp["shield"]) - 65.0) < 0.51, "实得 %.2f 期望 65" % float(amp["shield"]))
	# ★幂等: 连跑 20 帧不会越减越多
	for _k in range(20):
		_s._equip_sys._potion_sys.tick_unit(c3, 0.016)
	amp["shield"] = 0.0
	_s._damage._grant_shield(amp, 100.0)
	_ok("067 ★幂等: 连跑 20 帧后仍然正好 65(不是每帧再减一次)",
		absf(float(amp["shield"]) - 65.0) < 0.51, "实得 %.2f 期望 65" % float(amp["shield"]))

	# ⑧ ★撤销: 毒清了 + 过了悬挂窗口 ⇒ 盾增幅回到 +30%(100 → 130)
	#    ⚠ 到期扫描是【每帧一次】的全局操作(用 Engine.get_process_frames() 去重, 同 _sigwave),
	#      所以这里必须真的跨一帧再 tick —— 同一帧内连调 tick_unit 只会扫一次。
	amp["dot_stacks"] = {}
	var tk: float = _s._t
	_s._t = tk + 1.0                      # 悬挂 0.30 秒, 1 秒后必然过期
	await get_tree().process_frame
	_s._t = tk + 1.0
	_s._equip_sys._potion_sys.tick_unit(c3, 0.016)
	amp["shield"] = 0.0
	_s._damage._grant_shield(amp, 100.0)
	_ok("067 ★毒结束 → 减益自动撤销, 盾增幅回到 +30%(100 → 130)",
		absf(float(amp["shield"]) - 130.0) < 0.51, "实得 %.2f 期望 130" % float(amp["shield"]))
	_s._t = tk

	# ⑨ ★携带者阵亡 → 立刻撤销(不等悬挂窗口) —— 走真入口 _eq_on_death
	_s._units.clear()
	var c4: Dictionary = _equip(_mk("fortune", "left", Vector2(-400.0, 320.0), 3000.0), "p2eq_067", 3)
	var s4: Dictionary = _mk("basic", "right", Vector2(0.0, 320.0), 9000.0)
	s4["dot_stacks"] = {"poison": 10}
	s4["shield_amp"] = 0.0
	_s._equip_sys._potion_sys.tick_unit(c4, 0.016)
	_ok("067 ★分母: 携带者活着时减益确实挂上了(shield_amp = −0.5)",
		absf(float(s4.get("shield_amp", 0.0)) + 0.5) < 0.005, "shield_amp=%.4f" % float(s4.get("shield_amp", 0.0)))
	_s._equip_sys._eq_on_death(c4, null)
	_ok("067 ★携带者阵亡 → 立刻撤销(shield_amp 回 0, 不留永久减半)",
		absf(float(s4.get("shield_amp", 0.0))) < 0.005, "shield_amp=%.4f" % float(s4.get("shield_amp", 0.0)))
	_s._units.clear()


## RC 泄放的累计比例 —— ★门禁【自己写死】这条公式(τ = T/3 = 1.0 秒, T = 3.0 秒),
## 不调被测的 PotionEqVfx.beam_frac。契约 §7:「期望值硬写不读被测常量」。
## 门禁【自己】算的累计泄放比例。
##
## ★2026-08-11: 曲线从 RC 指数泄放换成 LoL 圣光维克兹 R 的实测包络
##   (逐帧量出来的: 蓄势 → 爬升 → 持续 → **末端峰值** → 一帧切断)。
## ★独立性说明: 这里**读同一张表 `ENV`(数据), 但积分是门禁自己写的**(梯形法) ——
##   与旧版"读同一个 τ、公式自己写"是同一级别的独立性。
##   如果直接调 `BeamVfx.env_frac`, 两边就是同一次计算 = 代数恒等 = 假门禁。
func _rc_frac(t: float) -> float:
	var tt: float = clampf(t / 3.0, 0.0, 1.0)
	var tbl: Array = BeamVfxRef.ENV
	var acc := 0.0
	var tot := 0.0
	for i in range(tbl.size() - 1):
		var a: Array = tbl[i]
		var b: Array = tbl[i + 1]
		var t0: float = float(a[0])
		var t1: float = float(b[0])
		tot += (float(a[1]) + float(b[1])) * 0.5 * (t1 - t0)
		if tt >= t1:
			acc += (float(a[1]) + float(b[1])) * 0.5 * (t1 - t0)
		elif tt > t0:
			var k: float = (tt - t0) / maxf(t1 - t0, 1e-6)
			acc += (float(a[1]) + lerpf(float(a[1]), float(b[1]), k)) * 0.5 * (tt - t0)
	return 0.0 if tot <= 0.0 else clampf(acc / tot, 0.0, 1.0)


## 068 深海气压罐(药水·5费):
##   受伤 ×60/100/200% 进充能条(上限 = 最大生命 20/40/100%)
##   本路第 12 秒起每 12 秒: 清空充能 → 法力护盾(充能 100/120/300%, 8 秒衰减)
##                        + 2000 码法力激光(3 秒共 充能 100/120/600% 魔法伤害)
##   法力护盾存在时锁充能条; 普攻 +5 龟能 + 回血 20/35/50
func _t068_pressure_can() -> void:
	print("── 068 深海气压罐 · 挨打充能 → 法力护盾 + 法力激光 ──")
	# ① 属性表(期望值硬写)
	var st: Array = _s.EquipStats.STATS.get("p2eq_068", [])
	_ok("068 ★分母: STATS 里有三星三条", st.size() == 3, "size=%d" % st.size())
	var bad: Array = []
	var wh: Array = [180, 460, 1100]
	var wa: Array = [10, 18, 30]
	var ws: Array = [15, 25, 40]
	for i in range(mini(3, st.size())):
		if int((st[i] as Dictionary).get("hp", -1)) != int(wh[i]):
			bad.append("★%d 生命 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("hp", "无")), int(wh[i])])
		if int((st[i] as Dictionary).get("_aspdPct", -1)) != int(wa[i]):
			bad.append("★%d 攻速 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("_aspdPct", "无")), int(wa[i])])
		if int((st[i] as Dictionary).get("shieldHealPct", -1)) != int(ws[i]):
			bad.append("★%d 治疗与护盾 %s≠%d" % [i + 1, str((st[i] as Dictionary).get("shieldHealPct", "无")), int(ws[i])])
	_ok("068 属性 = 生命180/460/1100 · 攻速10/18/30% · 治疗与护盾强度15/25/40%", bad.is_empty(), str(bad))
	_ok("068 ★用户点名: 走【合并字段 shieldHealPct】而不是拆成 healAmp + shieldAmp",
		not (st[0] as Dictionary).has("healAmp") and not (st[0] as Dictionary).has("shieldAmp"),
		"1★ 的键: %s" % str((st[0] as Dictionary).keys()))

	# ② ★★§0.5 的量级表逐格验(以 3000 血携带者为例) —— 两级放大是【有意的】, 不许顺手调平
	#    | 星 | 充满需实际挨打 | 法力护盾 | 激光伤害 |
	#    | 1★ |     1000       |   600    |   600    |
	#    | 2★ |     1200       |  1440    |  1440    |
	#    | 3★ |     1500       |  9000    | 18000    |
	var hit_need: Array = [1000.0, 1200.0, 1500.0]
	var want_sh: Array = [600.0, 1440.0, 9000.0]
	var want_beam: Array = [600.0, 1440.0, 18000.0]
	var want_cap: Array = [600.0, 1200.0, 3000.0]
	for si in range(3):
		_s._units.clear()
		_s._spec.clear_all()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, -220.0), 3000.0), "p2eq_068", si + 1)
		var foe: Dictionary = _mk("basic", "right", Vector2(500.0, -220.0), 500000.0)
		u["eq_state"]["p2eq_068"] = {"can_t0": 0.0, "can_charge": 0.0, "can_fired": 0}
		# 挨【一发】刚好充满的伤害 —— 走真入口 _eq_on_target
		_s._equip_sys._eq_on_target(u, foe, int(hit_need[si]))
		var chg: float = float(u["eq_state"]["p2eq_068"].get("can_charge", 0.0))
		_ok("068 si=%d 挨打 %.0f → 充能条满 %.0f(转化 60/100/200%%, 上限 = 最大生命 20/40/100%%)"
			% [si, hit_need[si], want_cap[si]],
			absf(chg - want_cap[si]) < 0.51, "实得 %.2f 期望 %.0f" % [chg, want_cap[si]])
		# ★★2026-08-06 补: 【DoT / 真伤】那条伤害路径也要给充能条充能。
		#   实装那路如实报了「068 的充能只吃 _apply_damage_from(普攻/技能), DoT 不进充能条」——
		#   因为 `_eq_on_target` 只挂在一条路上。而用户原文是「将**收到的**伤害储存」, 无"仅限普攻"限定。
		#   ⇒ CLAUDE.md §3.3 那一类的实现遗漏。主会话补了窄口(不动 _eq_on_target, 免得
		#     硬化层/冰封反制从每一跳灼烧触发)。这条断言守住那个窄口。
		var dot_u: Dictionary = _equip(_mk("fortune", "left", Vector2(-480.0, -180.0), 3000.0), "p2eq_068", si + 1)
		# ★走【真实的上装备管线】点亮常驻字段 —— 本文件的 `_equip()` 只塞 equips 数组,
		#   而 `_potion_tick` 这个每帧守卫是 `_eq_apply_flags` 点亮的。不走真入口的话,
		#   我测的就不是"装上这件会发生什么", 而是"手搓的字典会发生什么"。
		_s._equip_sys._stats._eq_apply_flags(dot_u, "p2eq_068", si + 1)
		_ok("068 si=%d ★分母: 真实上装备管线点亮了 _potion_tick" % si,
			bool(dot_u.get("_potion_tick", false)),
			"没点亮 ⇒ 下面那条 DoT 充能断言是空检查")
		dot_u["eq_state"]["p2eq_068"] = {"can_t0": 0.0, "can_charge": 0.0, "can_fired": 0}
		dot_u["def"] = 0.0; dot_u["mr"] = 0.0; dot_u["shield"] = 0.0; dot_u["flat_dr"] = 0.0
		_s._damage._apply_damage(dot_u, 100, Color(1, 1, 1))       # 走 DoT/真伤那条真入口
		var dchg: float = float(dot_u["eq_state"]["p2eq_068"].get("can_charge", 0.0))
		var dwant: float = 100.0 * [0.60, 1.00, 2.00][si]
		_ok("068 si=%d ★★DoT/真伤路也充能(挨 100 → 存 %.0f)" % [si, dwant],
			absf(dchg - dwant) < 0.51,
			"实得 %.2f —— 只挂一条伤害路径 = 被灼烧/中毒打半天充能条纹丝不动(§3.3)" % dchg)

		# 再挨 9999 也不超过上限
		_s._equip_sys._eq_on_target(u, foe, 9999)
		_ok("068 si=%d ★充能条封顶(再挨 9999 也还是 %.0f)" % [si, want_cap[si]],
			absf(float(u["eq_state"]["p2eq_068"].get("can_charge", 0.0)) - want_cap[si]) < 0.51,
			"实得 %.2f" % float(u["eq_state"]["p2eq_068"].get("can_charge", 0.0)))
		# 释放
		_s._equip_sys._potion_sys._eq_pressure_release(u, si, u["eq_state"]["p2eq_068"])
		_ok("068 si=%d 法力护盾 = 充能 × 100/120/300%% = %.0f" % [si, want_sh[si]],
			absf(_s._spec.val(u, "p2eq_068_mana") - want_sh[si]) < 0.51,
			"实得 %.2f 期望 %.0f" % [_s._spec.val(u, "p2eq_068_mana"), want_sh[si]])
		_ok("068 si=%d 激光总伤害 = 充能 × 100/120/600%% = %.0f" % [si, want_beam[si]],
			absf(float(u["eq_state"]["p2eq_068"].get("beam_total", 0.0)) - want_beam[si]) < 0.51,
			"实得 %.2f 期望 %.0f" % [float(u["eq_state"]["p2eq_068"].get("beam_total", 0.0)), want_beam[si]])
		_ok("068 si=%d 释放后充能条清零" % si,
			absf(float(u["eq_state"]["p2eq_068"].get("can_charge", 0.0))) < 0.51,
			"实得 %.2f" % float(u["eq_state"]["p2eq_068"].get("can_charge", 0.0)))
	_s._spec.clear_all()

	# ③ ★法力护盾走 SpecialBalance(契约 §2): 8 秒【线性】衰减, 独立于普通 shield
	_s._units.clear()
	_s._spec.clear_all()
	var m: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, -180.0), 3000.0), "p2eq_068", 3)
	var mf: Dictionary = _mk("basic", "right", Vector2(500.0, -180.0), 500000.0)
	m["eq_state"]["p2eq_068"] = {"can_t0": 0.0, "can_charge": 1000.0, "can_fired": 0}
	_s._equip_sys._potion_sys._eq_pressure_release(m, 2, m["eq_state"]["p2eq_068"])
	_ok("068 ★分母: 法力护盾挂上了 3000(1000 充能 × 300%)",
		absf(_s._spec.val(m, "p2eq_068_mana") - 3000.0) < 0.51, "实得 %.2f" % _s._spec.val(m, "p2eq_068_mana"))
	_ok("068 ★法力护盾【不】占用普通护盾条(u.shield 仍是 0)",
		absf(float(m.get("shield", 0.0))) < 0.51, "u.shield=%.2f" % float(m.get("shield", 0.0)))
	_s._spec.tick(4.0)
	_ok("068 ★8 秒线性衰减: 走 4 秒 → 剩一半 1500",
		absf(_s._spec.val(m, "p2eq_068_mana") - 1500.0) < 0.51, "实得 %.2f 期望 1500" % _s._spec.val(m, "p2eq_068_mana"))

	# ④ ★「法力护盾存在时锁充能条」
	m["eq_state"]["p2eq_068"]["can_charge"] = 0.0
	_s._equip_sys._eq_on_target(m, mf, 500)
	_ok("068 ★法力护盾存在期间【锁充能条】: 挨 500 伤害充能仍是 0",
		absf(float(m["eq_state"]["p2eq_068"].get("can_charge", 0.0))) < 0.51,
		"实得 %.2f" % float(m["eq_state"]["p2eq_068"].get("can_charge", 0.0)))
	_s._spec.tick(5.0)          # 再走 5 秒 → 衰减完(4+5 > 8)
	_ok("068 ★分母: 8 秒走完法力护盾已耗尽",
		_s._spec.val(m, "p2eq_068_mana") <= 0.001, "实得 %.4f" % _s._spec.val(m, "p2eq_068_mana"))
	_s._equip_sys._eq_on_target(m, mf, 500)
	_ok("068 ★护盾没了 → 充能条解锁(挨 500 × 200% = 1000)",
		absf(float(m["eq_state"]["p2eq_068"].get("can_charge", 0.0)) - 1000.0) < 0.51,
		"实得 %.2f 期望 1000" % float(m["eq_state"]["p2eq_068"].get("can_charge", 0.0)))
	_s._spec.clear_all()

	# ⑤ ★★CLAUDE.md §3.4 跨路计时: 「登场后的第 12 秒」按【本路】起算
	_s._units.clear()
	_s._spec.clear_all()
	var t_save: float = _s._t
	_s._t = 9000.0
	var p: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, -140.0), 3000.0), "p2eq_068", 3)
	var pf: Dictionary = _mk("basic", "right", Vector2(500.0, -140.0), 500000.0)
	_s._equip_sys._stats._eq_apply_one_stats(p, "p2eq_068", 3)   # 走真管线预置本路 t0
	_ok("068 ★分母: 本路开战管线把 t0 记成【当前】时刻 9000(不是 0)",
		absf(float(p["eq_state"]["p2eq_068"].get("can_t0", -1.0)) - 9000.0) < 0.51,
		"can_t0=%.2f" % float(p["eq_state"]["p2eq_068"].get("can_t0", -1.0)))
	_s._equip_sys._eq_on_target(p, pf, 100)
	_s._equip_sys._potion_sys.tick_unit(p, 0.016)
	_ok("068 ★★跨路地雷: 下路一开场(_t=9000, 本路才过 0 秒) → 【不】释放",
		int(p["eq_state"]["p2eq_068"].get("can_fired", -1)) == 0,
		"can_fired=%d" % int(p["eq_state"]["p2eq_068"].get("can_fired", -1)))
	_s._t = 9011.9
	_s._equip_sys._potion_sys.tick_unit(p, 0.016)
	_ok("068 ★本路第 11.9 秒仍不释放(阈值是 12 秒整)",
		int(p["eq_state"]["p2eq_068"].get("can_fired", -1)) == 0,
		"can_fired=%d" % int(p["eq_state"]["p2eq_068"].get("can_fired", -1)))
	_s._t = 9012.1
	_s._equip_sys._potion_sys.tick_unit(p, 0.016)
	_ok("068 ★本路第 12.1 秒 → 第一次释放",
		int(p["eq_state"]["p2eq_068"].get("can_fired", -1)) == 1,
		"can_fired=%d" % int(p["eq_state"]["p2eq_068"].get("can_fired", -1)))
	_s._t = 9023.9
	_s._equip_sys._potion_sys.tick_unit(p, 0.016)
	_ok("068 ★后续每 12 秒: 第 23.9 秒还不到第二次",
		int(p["eq_state"]["p2eq_068"].get("can_fired", -1)) == 1,
		"can_fired=%d" % int(p["eq_state"]["p2eq_068"].get("can_fired", -1)))
	_s._t = 9024.1
	_s._equip_sys._potion_sys.tick_unit(p, 0.016)
	_ok("068 ★后续每 12 秒: 第 24.1 秒第二次释放",
		int(p["eq_state"]["p2eq_068"].get("can_fired", -1)) == 2,
		"can_fired=%d" % int(p["eq_state"]["p2eq_068"].get("can_fired", -1)))
	_s._t = t_save
	_s._spec.clear_all()

	# ⑥ ★法力激光: 3 秒里打出的【总量】= 设计值, 且逐跳按 RC 泄放曲线(与亮度同一条)
	_s._units.clear()
	_s._spec.clear_all()
	var b: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, -100.0), 3000.0), "p2eq_068", 3)
	var tgt: Dictionary = _mk("basic", "right", Vector2(500.0, -100.0), 500000.0)
	b["eq_state"]["p2eq_068"] = {"can_t0": 0.0, "can_charge": 3000.0, "can_fired": 0}
	_s._equip_sys._potion_sys._eq_pressure_release(b, 2, b["eq_state"]["p2eq_068"])
	var total: float = 18000.0                      # 3000 充能 × 600%
	var hp_b0: float = float(tgt["hp"])
	var expect := 0.0
	var real_first := 0.0
	var real_last := 0.0
	for k in range(12):                             # 12 跳 × 0.25 秒 = 3.0 秒
		expect += maxf(1.0, roundf(total * (_rc_frac(0.25 * float(k + 1)) - _rc_frac(0.25 * float(k)))))
		var hp_step: float = float(tgt["hp"])
		_s._equip_sys._potion_sys._eq_beam_step(b, 0.25)
		if k == 0:
			real_first = hp_step - float(tgt["hp"])
		if k == 11:
			real_last = hp_step - float(tgt["hp"])
	_ok("068 ★激光总量守恒: 3 秒结束时账本 beam_paid = 18000(精确)",
		absf(float(b["eq_state"]["p2eq_068"].get("beam_paid", 0.0)) - total) < 0.51,
		"beam_paid=%.3f 期望 %.0f" % [float(b["eq_state"]["p2eq_068"].get("beam_paid", 0.0)), total])
	# ★容差 ±12 而不是 ±0.51: 每一跳都过 `maxf(1, round(...))`/`maxi(1, …)` 两道取整,
	#   12 跳最多攒 12 点误差。收得比这更紧就是在守取整噪声, 不是守数值契约。
	_ok("068 ★激光实发伤害 = 门禁独立算的 12 跳实测包络之和 %.0f" % expect,
		absf(hp_b0 - float(tgt["hp"]) - expect) < 12.5,
		"实掉 %.1f 期望 %.1f" % [hp_b0 - float(tgt["hp"]), expect])
	_ok("068 ★分母: 12 跳都真的打中了(同步触发证据 _mana_beam_n)",
		int(tgt.get("_mana_beam_n", 0)) == 12, "_mana_beam_n=%d" % int(tgt.get("_mana_beam_n", 0)))
	_ok("068 ★3 秒后激光结束(beam_total 归零, 不会永远打下去)",
		absf(float(b["eq_state"]["p2eq_068"].get("beam_total", 0.0))) < 0.001,
		"beam_total=%.3f" % float(b["eq_state"]["p2eq_068"].get("beam_total", 0.0)))
	# ★前后不均匀 —— ★★量的是【目标实际掉的血】, 不是拿门禁自己的公式跟自己比
	#   (memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」)。
	#   匀速泄放会让两跳相等(比值 1.0), 这条就红。
	# ★★2026-08-11 判据【方向翻转】: 旧版是 RC 指数泄放(开场即满、越打越弱),
	#   新版照 LoL 圣光维克兹 R 的实测包络 —— **最亮的一瞬是结束前那一帧**。
	#   逐帧实测: 峰值出现在 t=2.40/2.50s 处, 然后一帧切断。
	#   这一条红过一次, 而且红得对 —— 它如实抓住了这次行为变更。
	#   匀速会让两跳相等(比值 1.0), 这条就红; 换回指数衰减(first 远大于 last)也红。
	_ok("068 ★★能量泄放是【越打越狠】(量实发伤害): 第 12 跳 %.0f ≥ 第 1 跳 %.0f 的 3 倍" % [real_last, real_first],
		real_last >= real_first * 3.0,
		"实发 first=%.0f last=%.0f 比 %.2f" % [real_first, real_last, real_last / maxf(1.0, real_first)])

	# ⑦ ★光柱几何: 2000 码长 × 半宽 58 码的条带, 范围内打、范围外不打
	_s._units.clear()
	_s._spec.clear_all()
	var g: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, -220.0), 3000.0), "p2eq_068", 3)
	var g_far: Dictionary = _mk("basic", "right", Vector2(500.0, -220.0), 500000.0)      # 最远敌(定向)
	var g_mid: Dictionary = _mk("basic", "right", Vector2(0.0, -220.0), 500000.0)        # 轴上
	var g_edge: Dictionary = _mk("basic", "right", Vector2(0.0, -170.0), 500000.0)       # 侧偏 50 < 58
	var g_out: Dictionary = _mk("basic", "right", Vector2(0.0, -140.0), 500000.0)        # 侧偏 80 > 58
	var g_back: Dictionary = _mk("basic", "right", Vector2(-560.0, -220.0), 500000.0)    # 在身后
	g["eq_state"]["p2eq_068"] = {"can_t0": 0.0, "can_charge": 100.0, "can_fired": 0}
	_s._equip_sys._potion_sys._eq_pressure_release(g, 2, g["eq_state"]["p2eq_068"])
	_s._equip_sys._potion_sys._eq_beam_step(g, 0.25)
	_ok("068 光柱几何: 轴上的敌人被贯穿", int(g_mid.get("_mana_beam_n", 0)) >= 1,
		"n=%d" % int(g_mid.get("_mana_beam_n", 0)))
	_ok("068 光柱几何: 侧偏 50 码(< 半宽 58)照样被打中", int(g_edge.get("_mana_beam_n", 0)) >= 1,
		"n=%d" % int(g_edge.get("_mana_beam_n", 0)))
	_ok("068 光柱几何 ★分母: 侧偏 80 码(> 半宽 58)【没被打中】", int(g_out.get("_mana_beam_n", 0)) == 0,
		"n=%d" % int(g_out.get("_mana_beam_n", 0)))
	_ok("068 光柱几何 ★分母: 站在身后的敌人【没被打中】(光柱只朝前)",
		int(g_back.get("_mana_beam_n", 0)) == 0, "n=%d" % int(g_back.get("_mana_beam_n", 0)))
	_ok("068 光柱朝【最远】的那个敌人打(它自己也吃到)", int(g_far.get("_mana_beam_n", 0)) >= 1,
		"n=%d" % int(g_far.get("_mana_beam_n", 0)))

	# ⑧ 普攻被动: +5 龟能 + 回复 20/35/50 生命
	for si in range(3):
		var wheal: float = [20.0, 35.0, 50.0][si]
		_s._units.clear()
		var s8: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -60.0), 3000.0), "p2eq_068", si + 1)
		s8["hp"] = 1000.0
		s8["skill_cd"] = {}
		var t8: Dictionary = _mk("basic", "right", Vector2(-100.0, -60.0), 9000.0)
		_s._equip_sys._eq_on_basic_attack(s8, t8)
		_ok("068 si=%d 普攻回复 %.0f 生命(需求 20/35/50)" % [si, wheal],
			absf(float(s8["hp"]) - 1000.0 - wheal) < 0.51, "实回 %.2f" % (float(s8["hp"]) - 1000.0))
		_ok("068 si=%d 普攻 +5 龟能" % si,
			absf(float(s8.get("energy_bank", 0.0)) - 5.0) < 0.005,
			"energy_bank=%.2f" % float(s8.get("energy_bank", 0.0)))
	_s._spec.clear_all()
	_s._units.clear()


## 演出层的【物理模型】门禁 —— 契约 §6:
##   这一批一件参考素材都没有 ⇒ 触手那条「逐帧量参考」无从下手, 改走冲击波那条:
##   **验模型的解析性质**(等距零点 / 对数缩减率 / 尺度不变 / 守恒量 / 无记忆性)。
##   手调出来的缓动曲线**一条都过不了**。
##   ★所有期望值在本文件里【独立写死】(带推导), 不读 PotionEqVfx 的常量。
func _t_vfx_physics() -> void:
	## (065 薄膜干涉物理门禁已随特效撤除删除 —— 用户 2026-08-11「不要特效」,
	##  函数已删, 留门禁=保护死代码。层数读数走 PANEL_COUNT 徽章, verify_eq_readouts 守。)
	print("── ★演出物理模型 · 066 二阶欠阻尼阶跃响应 ──")
	# ⑤ 边界: y(0)=0, y(∞)→1
	_ok("066vfx 阶跃响应 y(0) = 0", absf(PVfx.damped_step(0.0)) < 1e-9, "y(0)=%.9f" % PVfx.damped_step(0.0))
	_ok("066vfx 阶跃响应 y(3 秒) → 1(包络 e^(−ζωₙt) 已衰到 1e-7)",
		absf(PVfx.damped_step(3.0) - 1.0) < 1e-4, "y(3)=%.9f" % PVfx.damped_step(3.0))

	# ⑥ ★首峰: Mp = e^(−πζ/√(1−ζ²)) = 0.372326, 恰在 t_p = π/ω_d = 0.193723 秒
	#    (ζ=0.30, ωₙ=17.0 ⇒ ω_d = 17×√0.91 = 16.216966)
	var best := -1.0
	var best_t := -1.0
	var tt := 0.0
	while tt < 1.2:
		var y: float = PVfx.damped_step(tt)
		if y > best:
			best = y
			best_t = tt
		tt += 0.00002
	_ok("066vfx ★最大超调量 Mp = e^(−πζ/√(1−ζ²)) = 0.372326(峰值 1.372326)",
		absf(best - 1.372326) < 5e-4, "实测峰值 %.6f" % best)
	_ok("066vfx ★首峰时刻 t_p = π/ω_d = 0.193723 秒",
		absf(best_t - 0.193723) < 1e-3, "实测 %.6f 秒" % best_t)

	# ⑦ ★★对数缩减率 —— 这条是"真阻尼振动"与"手画回弹曲线"的分水岭:
	#    相邻【交替】极值的偏差比恒为 e^(πζ/√(1−ζ²)) = 2.685818, 对任意 k 都一样。
	var ext: Array = []
	var t2 := 0.0002
	while t2 < 1.1:
		var ya: float = PVfx.damped_step(t2 - 0.0002) - 1.0
		var yb: float = PVfx.damped_step(t2) - 1.0
		var yc: float = PVfx.damped_step(t2 + 0.0002) - 1.0
		if (yb > ya and yb > yc) or (yb < ya and yb < yc):
			ext.append(absf(yb))
		t2 += 0.0002
	_ok("066vfx ★分母: 找到 %d 个极值(要 ≥ 3 个才能验「相邻两次的比」两回)" % ext.size(),
		ext.size() >= 3, "ext=%d" % ext.size())
	var rbad := 0.0
	for i in range(1, mini(4, ext.size())):
		rbad = maxf(rbad, absf(float(ext[i - 1]) / maxf(1e-9, float(ext[i])) - 2.685818))
	_ok("066vfx ★★对数缩减: 相邻极值之比恒 = e^(πζ/√(1−ζ²)) = 2.685818(对每一对都成立)",
		ext.size() >= 3 and rbad < 0.02, "最大偏差 %.5f" % rbad)
	_ok("066vfx ★存在【二次峰】(t = 3π/ω_d = 0.581168 处再次冲过终值, y = 1+Mp³ = 1.051614) —— 单调缓动给不出",
		absf(PVfx.damped_step(0.581168) - 1.051614) < 5e-4, "y=%.6f" % PVfx.damped_step(0.581168))

	print("── ★演出物理模型 · 067 Fick 扩散毒云 + 真抛物线 ──")
	# ⑧ ★尺度不变: R(t) = √(4Dt) ⇒ R(4t)/R(t) ≡ 2, 与 t 无关(手调"半径匀速涨"过不了)
	var sbad := 0.0
	for t in [0.05, 0.2, 0.5, 1.0, 2.0, 3.5]:
		sbad = maxf(sbad, absf(PVfx.cloud_radius(float(t) * 4.0) / maxf(1e-9, PVfx.cloud_radius(float(t))) - 2.0))
	_ok("067vfx ★★半径 ∝ √t(尺度不变): R(4t)/R(t) ≡ 2, 对 6 个不同的 t 都成立",
		sbad < 1e-6, "最大偏差 %.9f" % sbad)
	# ★峰值 ∝ 1/t ⇒ peak(t)×t 恒定 = 1/(4πD) = 5.960859e-06
	var pbad := 0.0
	for t in [0.05, 0.2, 0.5, 1.0, 2.0, 3.5]:
		pbad = maxf(pbad, absf(PVfx.cloud_peak(float(t)) * float(t) - 5.960859e-06))
	_ok("067vfx ★峰值浓度 ∝ 1/t: peak(t)×t ≡ 1/(4πD) = 5.960859e-06",
		pbad < 1e-11, "最大偏差 %s" % str(pbad))
	# ★★质量守恒 ∮c·2πr dr ≡ M(=1), 对任意 t —— "越大越淡"的手调做法过不了这一条
	var mbad := 0.0
	for t in [0.2, 1.0, 3.0]:
		var rmax: float = PVfx.cloud_radius(float(t)) * 5.0
		var steps := 20000
		var dr: float = rmax / float(steps)
		var acc := 0.0
		for i in range(steps):
			var r0: float = float(i) * dr
			var r1: float = float(i + 1) * dr
			acc += 0.5 * (PVfx.cloud_conc(r0, float(t)) * r0 + PVfx.cloud_conc(r1, float(t)) * r1) * dr
		acc *= TAU                       # ×2π
		mbad = maxf(mbad, absf(acc - 1.0))
	_ok("067vfx ★★质量守恒: 数值积分 ∮c·2πr dr ≡ 1, 对 t=0.2/1.0/3.0 都成立",
		mbad < 0.005, "最大偏差 %.6f" % mbad)
	# ★定标: t=1.0 秒时的可见边缘(峰值 5% 等浓度线)恰好等于效果半径 400 码
	_ok("067vfx 定标: t=1.0 秒的可见边缘 = 400 码(= 药瓶的效果半径, 演出与判定同一个数)",
		absf(PVfx.cloud_edge_radius(1.0) - 400.0) < 0.51, "实得 %.3f" % PVfx.cloud_edge_radius(1.0))
	# ⑨ 真抛物线: 关于 s=0.5 严格对称 / 顶点恰在 0.5 / 二阶差分恒定(= 常重力)
	var apex := 190.0
	var asym := 0.0
	for i in range(51):
		var s: float = float(i) / 100.0
		asym = maxf(asym, absf(PVfx.arc_height(s, apex) - PVfx.arc_height(1.0 - s, apex)))
	_ok("067vfx 抛物线关于 s=0.5 严格对称", asym < 1e-6, "最大不对称 %.9f" % asym)
	_ok("067vfx 抛物线顶点恰在 s=0.5 且等于抛高(端点落地为 0)",
		absf(PVfx.arc_height(0.5, apex) - apex) < 1e-6 and absf(PVfx.arc_height(0.0, apex)) < 1e-9
		and absf(PVfx.arc_height(1.0, apex)) < 1e-9,
		"h(0.5)=%.6f h(0)=%.9f h(1)=%.9f" % [PVfx.arc_height(0.5, apex), PVfx.arc_height(0.0, apex), PVfx.arc_height(1.0, apex)])
	var dd2: float = -1.0
	var d2bad := 0.0
	for i in range(1, 99):
		var s0: float = float(i - 1) / 100.0
		var s1: float = float(i) / 100.0
		var s2: float = float(i + 1) / 100.0
		var v: float = PVfx.arc_height(s2, apex) - 2.0 * PVfx.arc_height(s1, apex) + PVfx.arc_height(s0, apex)
		if dd2 < -0.5:
			dd2 = v
		else:
			d2bad = maxf(d2bad, absf(v - dd2))
	_ok("067vfx ★二阶差分恒定(= 常重力, 真抛物线; 手画的弧线做不到)",
		d2bad < 1e-9, "二阶差分 %.9f 最大偏差 %s" % [dd2, str(d2bad)])

	print("── ★演出物理模型 · 068 RC 泄放 ──")
	# ⑩ ★★无记忆性: i(t+Δ)/i(t) 与 t 无关 —— 这是指数函数的定义性质,
	#    任何多项式/缓动都不满足。Δ=0.4 ⇒ 比值恒为 e^(−0.4) = 0.670320。
	var rmax2 := 0.0
	for t in [0.0, 0.3, 0.7, 1.1, 1.9, 2.5]:
		var r: float = PVfx.beam_current(float(t) + 0.4) / maxf(1e-12, PVfx.beam_current(float(t)))
		rmax2 = maxf(rmax2, absf(r - 0.670320))
	_ok("068vfx ★★无记忆性: i(t+0.4)/i(t) ≡ e^(−0.4) = 0.670320, 对 6 个 t 都一样",
		rmax2 < 1e-5, "最大偏差 %.9f" % rmax2)
	_ok("068vfx i(0) = 1(起爆瞬间满电流)", absf(PVfx.beam_current(0.0) - 1.0) < 1e-9,
		"i(0)=%.9f" % PVfx.beam_current(0.0))
	_ok("068vfx 半衰期 τ·ln2 = 0.693147 秒处电流恰好剩一半",
		absf(PVfx.beam_current(0.693147) - 0.5) < 1e-5, "i(t½)=%.9f" % PVfx.beam_current(0.693147))
	_ok("068vfx 泄放比例 Q(0)=0 与 Q(3 秒)=1 都是【精确】的(总量不多不少)",
		absf(PVfx.beam_frac(0.0)) < 1e-12 and absf(PVfx.beam_frac(3.0) - 1.0) < 1e-12,
		"Q(0)=%.12f Q(3)=%.12f" % [PVfx.beam_frac(0.0), PVfx.beam_frac(3.0)])

	print("── ★美术: 节点真的显示进 battle._world ──")
	# (⑪ 065 油膜光晕美术门禁已随特效撤除删除)
	_s._units.clear()
	var vf = _s._equip_sys._potion_sys.vfx()
	var au: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 300.0), 1000.0), "p2eq_065", 3)
	# ⑫ 067 毒云: 节点进 _world, 且半径按 √t 长
	var cl: Dictionary = vf.vial_cloud(Vector2(au["pos"]))
	_ok("067 ★美术: 毒云【真的挂进 battle._world】", _in_world(cl.get("nd", null)),
		"parent=%s" % (str((cl.get("nd", null) as Node).get_parent()) if cl.has("nd") else "无节点"))
	vf.apply_at(cl, 0.0)
	var s_a: float = (cl["nd"] as MeshInstance3D).scale.x
	# u=0 ⇒ t=0.18; 找一个 t=4×0.18=0.72 的 u ⇒ u=(0.72−0.18)/4.0=0.135
	vf.apply_at(cl, 0.135)
	var s_b: float = (cl["nd"] as MeshInstance3D).scale.x
	_ok("067 ★美术: 毒云节点尺寸真的按 √t 长(t 变 4 倍 ⇒ 半径正好 2 倍)",
		absf(s_b / maxf(1e-9, s_a) - 2.0) < 0.01, "比值 %.5f (%.4f → %.4f)" % [s_b / maxf(1e-9, s_a), s_a, s_b])

	# ⑬ 068 法力激光 + 充能条
	var bm: Dictionary = vf.mana_beam(Vector2(au["pos"]), Vector2.RIGHT)
	_ok("068 ★美术: 法力激光【真的挂进 battle._world】", _in_world(bm.get("nd", null)),
		"parent=%s" % (str((bm.get("nd", null) as Node).get_parent()) if bm.has("nd") else "无节点"))
	_ok("068 ★美术: 光柱长度 = 2000 码 × WS(0.024) = 48.0 米(与判定长度同一个数)",
		absf((bm["nd"] as MeshInstance3D).scale.x - 48.0) < 0.01,
		"scale.x=%.4f" % (bm["nd"] as MeshInstance3D).scale.x)
	vf.apply_at(bm, 0.0)
	var a_full: float = ((bm["nd"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a
	vf.apply_at(bm, 0.693147 / 3.0)      # 半衰期处
	var a_half: float = ((bm["nd"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a
	_ok("068 ★美术: 光柱亮度也走同一条泄放曲线(半衰期处亮度恰好剩一半)",
		absf(a_half / maxf(1e-9, a_full) - 0.5) < 0.005, "比值 %.5f (%.4f → %.4f)" % [a_half / maxf(1e-9, a_full), a_full, a_half])
	# ── 充能条: 头顶那条已于 2026-08-11 拆除, 读数改走【装备图标框】────────────
	#   ★为什么拆(干净台实拍量出来的, 不是觉得):
	#     ① 那条白线根本不在头顶, 是**横穿龟的身体** —— BAR_LIFT=1.28 对不上龟的身高,
	#        读起来像贴图划痕(用户 2026-08-11:「我手机上看感觉不满意」);
	#     ② 用户 2026-08-08 定过「充能条和层数不要放头顶, 在装备图标框里」;
	#     ③ 它**跨路残留** —— 两片挂在 `_world` 下, potion_eq_vfx 没有 clear_all、
	#        `charge_bar_clear` 零调用者 ⇒ 换路后永远钉在上一路的位置。
	#   需求没变(玩家得看出"快满了"), 变的是出口 ⇒ 这里改断言新出口, 覆盖不减。
	_ok("068 ★美术: 充能读数在【装备图标框】里(不是头顶自造条)",
		(_s.PANEL_CHARGE as Dictionary).has("p2eq_068"),
		"PANEL_CHARGE 里没有 068 —— 那就是拆了头顶条又没接新出口, 玩家彻底看不到")
	_ok("068 ★美术: 读的是归一化镜像 can_pct(上限随 maxHp 变, 不能拿原始值当分母)",
		str(((_s.PANEL_CHARGE as Dictionary).get("p2eq_068", [""]) as Array)[0]) == "can_pct")
	_ok("068 ★美术 ★分母: 头顶条的函数确实已经不存在了(留着就会有人再调)",
		not vf.has_method("charge_bar"),
		"potion_eq_vfx 还有 charge_bar() —— 拆干净才不会复发")
	vf.film_clear(au)
	_s._units.clear()
