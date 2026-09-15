extends Node
## verify_axe_batch10.gd — 096 小木斧 第十批六条修正(E3 E4 E5 E9 E10 E11)
##
## ★由来(2026-09-15, 087~096 调查 · 方案书 20260915c):
##   E3 亡灵之斧死后永远不重生 —— `axe_system.tick` 先判「斧头死了就 return」, 重生检查在后面走不到;
##      而且 `_kill` 已经把立绘淡出藏起、打上 `_dead_done` 死亡守卫, 只把 alive 改回 true
##      会得到一把【看不见、0 血也打不死】的斧头。
##   E4 效率层每层 +4% 攻速没人读 —— `eff_aspd_mult` 只有门禁在调, `aspd_mult` 不读它。
##   E5 横扫 / 强化猛砸 / 钻石猛砸写着物理伤害却不吃护甲。
##   E9 余烬之光用常量覆写共享字段, 到期直接写 0(施放前已有的减伤 / 吸血 / 免控被抹掉)。
##   E10 回旋镖判定没有射程上限, 演出只画 750 码 ⇒ 远处的敌人挨打却看不到镖飞到。
##      (判定不改 —— 改的是演出画到被打中的最远那个, 数值一个不动)
##   E11 全息斧的「友军」包含训龟大师和龟蛋。
## ★判据量产品自己的账(血量 / aspd_mult / 字段 / 世界里真的节点), 不数我插的标记。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

var _s = null
var _n := 0
var _fail := 0


## 数引擎报错的 Logger(Godot 4.5+)。★引擎报错不经过 GDScript, 只有挂 Logger 才在脚本里数得到。
##   探针实测(2026-09-15): 故意调一个捕获物已释放的 lambda ⇒ 这里收到 1 条, code 就是报错原文。
class ErrTap extends Logger:
	var lam := 0
	var probe := 0
	var mx := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array) -> void:
		mx.lock()
		if code.contains("Lambda capture") or rationale.contains("Lambda capture"):
			lam += 1
		if code.contains("ERRTAP_PROBE_096") or rationale.contains("ERRTAP_PROBE_096"):
			probe += 1
		mx.unlock()


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _c() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


func _mk_axe(pv: int, final_key: String = "", atk: float = 100.0) -> Dictionary:
	var ax: Dictionary = _s._spawn._make_unit("basic", "left", _c())
	_s._units.append(ax)
	ax["_eq_axe"] = true
	ax["_axe_pv"] = pv
	if final_key != "":
		ax["_axe_final"] = final_key
	ax["id"] = "__axe_probe__"
	ax["crit"] = 0.0
	ax["atk"] = atk
	ax["maxHp"] = 10000.0
	ax["hp"] = 5000.0
	ax["maxEnergy"] = 1000.0
	ax["energy"] = 0.0
	ax["atk_range"] = 200.0
	ax["damage_amp"] = 0.0
	ax["armor_pen"] = 0.0
	ax["armor_pen_pct"] = 0.0
	return ax


func _mk_foe(off: Vector2, def: float = 0.0, hp: float = 200000.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", "right", _c() + off)
	_s._units.append(u)
	u["id"] = "__foe_probe__"
	u["maxHp"] = hp
	u["hp"] = hp
	u["def"] = def
	u["base_def"] = def
	u["mr"] = 0.0
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["shield"] = 0.0
	u["dodge_bonus"] = 0.0
	return u


func _mk_ally(off: Vector2, hp_ratio: float) -> Dictionary:
	var a: Dictionary = _s._spawn._make_unit("basic", "left", _c() + off)
	_s._units.append(a)
	a["id"] = "__ally_probe__"
	a["maxHp"] = 5000.0
	a["hp"] = 5000.0 * hp_ratio
	a["maxEnergy"] = 1000.0
	a["energy"] = 0.0
	a["shield"] = 0.0
	return a


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 096 小木斧 第十批(E3 E4 E5 E9 E10 E11) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t_e3_undead_revive()
	_t_e4_eff_aspd()
	_t_e5_armor()
	_t_e9_ember_restore()
	_t_e10_boomerang_reach()
	_t_e11_holo_pool()
	await _t_holo_pulse_capture()

	if _n < 30:
		print("  [FAIL] ★分母: 断言只有 %d 条(<30) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 096 第十批(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  E3 亡灵之斧: 走真入口死一次 → 到点重生(看得见) → 还能再死
# ══════════════════════════════════════════════════════════════
func _t_e3_undead_revive() -> void:
	print("--- E3 亡灵之斧重生 ---")
	_s._units.clear()
	var carrier: Dictionary = _s._spawn._make_unit("basic", "left", _c() + Vector2(-80, 0))
	_s._units.append(carrier)
	var ax: Dictionary = _mk_axe(4, "undead")
	carrier["_axe_ref"] = ax
	var foe: Dictionary = _mk_foe(Vector2(150, 0))
	var spr = ax.get("sprite", null)
	_ok("★分母: 斧头有立绘节点(可见性量得到)", is_instance_valid(spr))
	ax["hp"] = 0.0
	_s._kill(ax, foe)
	_ok("★分母: 真入口 _kill 之后斧头死了、并排上了重生",
		not bool(ax.get("alive", true)) and ax.has("_axe_revive_at"),
		"alive=%s revive_at=%s" % [str(ax.get("alive")), str(ax.get("_axe_revive_at", "无"))])
	_ok("★分母: _kill 打上了死亡守卫 _dead_done(不清掉就再也死不了)", bool(ax.get("_dead_done", false)))
	## ★`_kill` 的立绘淡出与 hide 挂在 tween 上, 无头下这几行之间一帧都不推 ⇒ 立绘此刻其实还没被藏。
	##   真实对局里重生在 2.5 秒后, 那时淡出早已走完。把淡出的【终态】直接写上再验「重生恢复可见」 ——
	##   第一版没写, 判据量的是「从没被藏过」: 变异 Z53 删掉恢复可见那几行照样全绿。
	if is_instance_valid(spr):
		spr.modulate.a = 0.0
		spr.visible = false
	for _k in ["shadow", "ring", "contact"]:
		var _nd = ax.get(_k, null)
		if is_instance_valid(_nd):
			_nd.visible = false
	_ok("★分母: 重生前立绘确实是藏着的(淡出终态)", is_instance_valid(spr) and not bool(spr.visible))
	_s._equip_sys._axe.tick(carrier, 0.016)
	_ok("★分母: 还没到 %.1f 秒时不站起来" % AF.UNDEAD_REVIVE_DELAY, not bool(ax.get("alive", true)))
	_s._t = float(ax.get("_axe_revive_at", 0.0)) + 0.01
	_s._equip_sys._axe.tick(carrier, 0.016)
	_ok("★★E3 到点真的站起来了(走 axe_system.tick 真入口; 修前斧头死了 tick 第一行就 return)",
		bool(ax.get("alive", false)), "alive=%s" % str(ax.get("alive")))
	_ok("E3 带 %.0f%% 最大生命回来" % (AF.UNDEAD_REVIVE_HP_PCT * 100.0),
		is_equal_approx(float(ax.get("hp", 0.0)), 10000.0 * AF.UNDEAD_REVIVE_HP_PCT),
		"hp=%.0f" % float(ax.get("hp", 0.0)))
	var vis_ok: bool = is_instance_valid(spr) and bool(spr.visible) and float(spr.modulate.a) > 0.99
	_ok("★★E3 立绘重新可见(_kill 把它淡出并 hide 了, 只改 alive 是一把隐形斧头)", vis_ok,
		("visible=%s a=%.2f" % [str(spr.visible), float(spr.modulate.a)]) if is_instance_valid(spr) else "无节点")
	var br = ax.get("bar_root", null)
	_ok("E3 血条重新显示", is_instance_valid(br) and bool(br.visible),
		("visible=%s" % str(br.visible)) if is_instance_valid(br) else "没有血条节点")
	_ok("★★E3 死亡守卫清掉了", not bool(ax.get("_dead_done", false)))
	ax["hp"] = 0.0
	_s._kill(ax, foe)
	_ok("★★E3 重生后再被打死是真的死了(守卫没清的话 _kill 第一行就 return, 0 血站着)",
		not bool(ax.get("alive", true)), "alive=%s" % str(ax.get("alive")))
	_ok("E3 一场只重生一次: 第二次死不再排重生", not ax.has("_axe_revive_at"))


# ══════════════════════════════════════════════════════════════
#  E4 效率层: 每层 +4% 攻速真的进了攻速总倍率
# ══════════════════════════════════════════════════════════════
func _t_e4_eff_aspd() -> void:
	print("--- E4 效率层攻速 ---")
	_s._units.clear()
	var ax: Dictionary = _mk_axe(3)
	ax["aspd_perm"] = 1.0
	ax["haste_until"] = 0.0
	var pas = _s._equip_sys._axe._pas
	var m0: float = _s.aspd_mult(ax)
	for _k in range(7):
		pas.add_eff(ax)
	_ok("★分母: 真入口 add_eff 叠了 7 层", pas.eff_stacks(ax) == 7, "层数 %d" % pas.eff_stacks(ax))
	var m7: float = _s.aspd_mult(ax)
	var want: float = 1.0 + AE.EFF_ASPD * 7.0
	_ok("★★E4 7 层: 攻速总倍率 ×%.4f(应 ×%.2f; 修前恒为 ×1.00)" % [m7 / maxf(1e-6, m0), want],
		absf(m7 / maxf(1e-6, m0) - want) < 1e-4, "m0=%.4f m7=%.4f" % [m0, m7])
	var iv: float = float(ax.get("atk_interval", 1.0))
	_ok("E4 真实攻击间隔 atk_interval / aspd_mult 缩成原来的 1/%.2f(%.3f → %.3f 秒)"
		% [want, iv / m0, iv / m7], absf((iv / m0) / (iv / m7) - want) < 1e-4)
	_s._t = float(_s._t) + AE.EFF_DUR + 0.1
	_ok("E4 效率层过期后攻速回到原值(不残留)", absf(_s.aspd_mult(ax) - m0) < 1e-6,
		"%.4f vs %.4f" % [_s.aspd_mult(ax), m0])


# ══════════════════════════════════════════════════════════════
#  E5 横扫 / 强化猛砸 / 钻石猛砸 吃护甲
# ══════════════════════════════════════════════════════════════
func _t_e5_armor() -> void:
	print("--- E5 三段物理伤害吃护甲 ---")
	_s._units.clear()
	var ax: Dictionary = _mk_axe(3)
	var main: Dictionary = _mk_foe(Vector2(100, 0))
	var soft: Dictionary = _mk_foe(Vector2(120, 40), 0.0)
	var hard: Dictionary = _mk_foe(Vector2(120, -40), 300.0)
	var s0: float = float(soft["hp"])
	var h0: float = float(hard["hp"])
	_s._equip_sys._axe.on_hit(ax, main, true)       # 第 1 下普攻 = 横扫
	var ds: float = s0 - float(soft["hp"])
	var dh: float = h0 - float(hard["hp"])
	var want_h: int = _s._phys_after_armor(ax, 100.0, hard)
	_ok("★分母: 横扫扫到了 0 护甲那只(掉 %.0f, 应为 100)" % ds, absf(ds - 100.0) < 1.01)
	_ok("★★E5 横扫: 300 护甲那只掉 %.0f, 等于护甲公式 %d(修前与 0 护甲同为 100)" % [dh, want_h],
		absf(dh - float(want_h)) < 1.01 and dh < ds - 1.0)

	ax["_axe_smash_ready"] = true
	var h1: float = float(hard["hp"])
	var extra: float = _s._equip_sys._axe._pas.smash_on_hit(ax, hard)
	var want_s: int = _s._phys_after_armor(ax, 100.0 * AE.SMASH_ATK, hard)
	var got_s: float = h1 - float(hard["hp"])
	_ok("★分母: 强化猛砸真的触发了(额外 %.0f)" % extra, extra > 0.0)
	_ok("★★E5 强化猛砸: 300 护甲掉 %.0f, 等于护甲公式 %d(修前 %.0f)" % [got_s, want_s, 100.0 * AE.SMASH_ATK],
		absf(got_s - float(want_s)) < 1.01 and float(want_s) < 100.0 * AE.SMASH_ATK - 1.0)

	_s._units.clear()
	_s._units.append(ax)
	var soft2: Dictionary = _mk_foe(Vector2(150, 20), 0.0)
	var hard2: Dictionary = _mk_foe(Vector2(150, -20), 300.0)
	var s2: float = float(soft2["hp"])
	var h2: float = float(hard2["hp"])
	ax["_axe_charge_t0"] = float(_s._t) - AE.CHARGE_TIME
	ax["_axe_charge_dir"] = Vector2.RIGHT
	var n: int = _s._equip_sys._axe._pas.slam_settle(ax)
	var sl: float = s2 - float(soft2["hp"])
	var hl: float = h2 - float(hard2["hp"])
	var want_l: int = _s._phys_after_armor(ax, 100.0 * AE.SLAM_ATK, hard2)
	_ok("★分母: 钻石猛砸砸中 %d 个, 0 护甲那只掉 %.0f(应为 %.0f)" % [n, sl, 100.0 * AE.SLAM_ATK],
		n >= 2 and absf(sl - 100.0 * AE.SLAM_ATK) < 1.01)
	_ok("★★E5 钻石猛砸: 300 护甲掉 %.0f, 等于护甲公式 %d" % [hl, want_l],
		absf(hl - float(want_l)) < 1.01 and hl < sl - 1.0)


# ══════════════════════════════════════════════════════════════
#  E9 余烬之光: 到期还原施放前的值
# ══════════════════════════════════════════════════════════════
func _t_e9_ember_restore() -> void:
	print("--- E9 余烬之光到期还原 ---")
	_s._units.clear()
	var fin = _s._equip_sys._axe._fin
	var bx: Dictionary = _mk_axe(4, "ember")
	var t0: float = float(_s._t)
	bx["damage_reduction"] = 0.10
	bx["lifesteal"] = 0.05
	bx["cc_immune_until"] = t0 + 100.0
	fin.ember_light_cast(bx)
	_ok("★分母: 余烬之光在线: 减伤 %.2f / 吸血 %.2f(应为 %.2f / %.2f)"
		% [float(bx["damage_reduction"]), float(bx["lifesteal"]), AF.EMBER_LIGHT_DR, AF.EMBER_LIGHT_LIFESTEAL],
		is_equal_approx(float(bx["damage_reduction"]), AF.EMBER_LIGHT_DR)
		and is_equal_approx(float(bx["lifesteal"]), AF.EMBER_LIGHT_LIFESTEAL))
	_s._t = t0 + AF.EMBER_LIGHT_TIME + 0.1
	fin.ember_light_tick(bx)
	_ok("★分母: 那一层真的过期了", fin.ember_light_stacks(bx) == 0)
	_ok("★★E9 到期减伤回到施放前的 0.10(修前写成 0)", is_equal_approx(float(bx["damage_reduction"]), 0.10),
		"实测 %.3f" % float(bx["damage_reduction"]))
	_ok("★★E9 到期吸血回到施放前的 0.05(修前写成 0)", is_equal_approx(float(bx["lifesteal"]), 0.05),
		"实测 %.3f" % float(bx["lifesteal"]))
	_ok("★E9 施放前就有的免控(到 t0+100)没被抹掉", float(bx.get("cc_immune_until", 0.0)) >= t0 + 100.0 - 1e-3,
		"实测 %.2f 期望 ≥ %.2f" % [float(bx.get("cc_immune_until", 0.0)), t0 + 100.0])

	var cx: Dictionary = _mk_axe(4, "ember")
	var t1: float = float(_s._t)
	cx["damage_reduction"] = 0.30
	fin.ember_light_cast(cx)
	_ok("E9 施放前已有 0.30 减伤: 在线期间取大仍是 0.30(与蓄力 / 插地同口径, 不降)",
		is_equal_approx(float(cx["damage_reduction"]), 0.30), "实测 %.3f" % float(cx["damage_reduction"]))
	_s._t = t1 + AF.EMBER_LIGHT_TIME + 0.1
	fin.ember_light_tick(cx)
	_ok("E9 到期仍是 0.30", is_equal_approx(float(cx["damage_reduction"]), 0.30),
		"实测 %.3f" % float(cx["damage_reduction"]))


# ══════════════════════════════════════════════════════════════
#  E10 回旋镖: 演出画到被打中的最远那个
# ══════════════════════════════════════════════════════════════
func _nodes_with_meta(root: Node, key: String, out: Array) -> void:
	if root.has_meta(key):
		out.append(root)
	for ch in root.get_children():
		_nodes_with_meta(ch, key, out)


func _new_boom_reach(ax: Dictionary, before: Array) -> float:
	var after: Array = []
	_nodes_with_meta(_s, "boom_to2d", after)
	var reach := -1.0
	for nd in after:
		if before.has(nd):
			continue
		reach = maxf(reach, ((nd as Node).get_meta("boom_to2d") as Vector2).distance_to(ax["pos"]))
	return reach


func _t_e10_boomerang_reach() -> void:
	print("--- E10 回旋镖演出射程 ---")
	_s._units.clear()
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe(4, "seraph")
	var far: Dictionary = _mk_foe(Vector2(1300, 0))
	var before: Array = []
	_nodes_with_meta(_s, "boom_to2d", before)
	var hp0: float = float(far["hp"])
	var hit: int = fin.seraph_boomerang_settle(ax, Vector2.RIGHT)
	_ok("★分母: 1300 码外的敌人照样挨打(判定没改 · 命中 %d)" % hit, hit == 1 and float(far["hp"]) < hp0)
	var reach: float = _new_boom_reach(ax, before)
	_ok("★分母: 世界里真的多出一把回旋镖节点", reach >= 0.0, "reach=%.0f" % reach)
	_ok("★★E10 镖画到了被打中的最远那个敌人(画到 %.0f 码, 应 ≥ 1300; 修前固定 %.0f)"
		% [reach, AF.SERAPH_BOOM_R * 2.5], reach >= 1300.0)

	_s._units.clear()
	_s._units.append(ax)
	var near: Dictionary = _mk_foe(Vector2(200, 0))
	var before2: Array = []
	_nodes_with_meta(_s, "boom_to2d", before2)
	fin.seraph_boomerang_settle(ax, Vector2.RIGHT)
	var reach2: float = _new_boom_reach(ax, before2)
	_ok("E10 敌人都在近处时仍按原来的 %.0f 码画(演出长度只往远处补, 不缩)" % (AF.SERAPH_BOOM_R * 2.5),
		absf(reach2 - AF.SERAPH_BOOM_R * 2.5) < 1.0, "reach=%.0f near_hp=%.0f" % [reach2, float(near["hp"])])


# ══════════════════════════════════════════════════════════════
#  E11 全息斧: 友军名单排除训龟大师与龟蛋
# ══════════════════════════════════════════════════════════════
func _t_e11_holo_pool() -> void:
	print("--- E11 全息斧友军名单 ---")
	_s._units.clear()
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe(4, "holo")
	ax["hp"] = 10000.0                     # 满血, 不跟友军抢"最低血"
	var trainer: Dictionary = _mk_ally(Vector2(-60, 0), 0.05)
	trainer["is_trainer"] = true
	var egg: Dictionary = _mk_ally(Vector2(-60, 40), 0.05)
	egg["_isEgg"] = true
	var mate: Dictionary = _mk_ally(Vector2(-60, -40), 0.50)
	var got = fin.holo_on_hit(ax)
	_ok("★★E11 普攻护盾给了普通友军, 不是血更低的训龟大师 / 龟蛋",
		got is Dictionary and is_same(got, mate),
		"给了 %s" % (str((got as Dictionary).get("id", "?")) if got is Dictionary else "null"))
	var th: float = float(trainer["hp"])
	var eh: float = float(egg["hp"])
	var mh: float = float(mate["hp"])
	fin.holo_aura_tick(ax)
	_ok("★分母: 法阵这一跳奶到了普通友军(+%.0f)" % (float(mate["hp"]) - mh), float(mate["hp"]) > mh)
	_ok("★★E11 法阵不奶训龟大师和龟蛋(修前各 +%.0f)" % AF.HOLO_AURA_HEAL,
		is_equal_approx(float(trainer["hp"]), th) and is_equal_approx(float(egg["hp"]), eh),
		"大师 %+.0f 蛋 %+.0f" % [float(trainer["hp"]) - th, float(egg["hp"]) - eh])


# ══════════════════════════════════════════════════════════════
#  全息 / 亡灵演出: 宿主比 tween 先释放 ⇒ 引擎报「Lambda capture at index 0 was freed」
# ══════════════════════════════════════════════════════════════
## ★由来(2026-09-15): 用户要 096 九个形态分开看, 批量录像里全息斧那段日志 19 条
##   `Lambda capture at index 0 was freed`, 其余八段 0 条。探针: 关掉 holo_pulse ⇒ 同一 16 秒窗口 3 → 0 条。
##   根因: 法阵本体按 tween 时钟到点释放, 脉冲按战斗时钟排 ⇒ 顿帧时最后一次脉冲的 tween 跑过本体释放的时刻,
##   lambda 捕获的根节点已释放, 引擎每帧报一条(lambda 体内的 is_instance_valid 拦不住)。
## ★同日下午: 程序法阵与 holo_pulse 已删(用户「8/9也是，完全没达标」, 换成 AxeHoloVfx / AxeUndeadVfx 烘焙帧表),
##   法阵本体改由战斗时钟切帧、到期同步释放, 不再有脉冲 tween。**意图不变**: 演出里还剩的 tween ——
##   数据块飞行 / 数据流根节点延时释放 / 亡灵之魂飞回 —— 宿主都可能先没(插地到期、斧头死亡、换路清场)。
##   这里把宿主【故意在 tween 还在跑的时候释放】, 量引擎报了几条。
## ★判据量【引擎真的报了几条】(Logger), 不数我插的标记; 另用分母断言证明「tween 还在跑、宿主已释放」真的形成了。
func _t_holo_pulse_capture() -> void:
	print("--- 全息 / 亡灵演出: 宿主比 tween 先释放(引擎报错条数) ---")
	_s._units.clear()
	var fin = _s._equip_sys._axe._fin
	var tap := ErrTap.new()
	OS.add_logger(tap)
	push_warning("ERRTAP_PROBE_096 门禁自检: 证明 Logger 接得到引擎输出(警告, 不是报错)")
	## 全息: 插地(法阵 + 护罩) → 一跳(脉冲 / 反馈 / 加速圈) → 普攻(数据流)
	var hx: Dictionary = _mk_axe(4, "holo")
	_mk_ally(Vector2(-260, 60), 0.3)
	fin.begin_active(hx)
	fin.holo_aura_tick(hx)
	fin.holo_on_hit(hx)
	var stream = null
	for c in _s._world.get_children():
		if str(c.name).begins_with("holo_stream") and not c.is_queued_for_deletion():
			stream = c
	_ok("★分母: 法阵与数据流真的建出来并挂进世界(数据块 %d 块)"
		% ((stream as Node).get_child_count() if stream is Node else -1),
		is_instance_valid(hx.get("_holo_field_spr", null)) and stream is Node3D and (stream as Node).get_child_count() >= 3)
	## 亡灵: 一跳里被抽走的魂
	var ux: Dictionary = _mk_axe(4, "undead")
	var foe: Dictionary = _mk_foe(Vector2(120, 40))
	var got: Dictionary = fin.vfx_undead.ring_tick(ux, [foe])
	var souls: Array = got.get("souls", [])
	_ok("★分母: 亡灵之魂真的建出来了(%d 缕)" % souls.size(), souls.size() == 1)
	var running := 0
	for tw in _s._sim_tweens:
		if tw != null and tw.is_valid() and tw.is_running():
			running += 1
	## ★宿主【立刻】全部释放: 数据块要飞 0.3 秒、魂要飞 0.45 秒, 此刻 tween 都还在跑
	fin.vfx_holo.end_plant(hx)
	if stream is Node:
		(stream as Node).free()
	for sp in souls:
		if is_instance_valid(sp):
			(sp as Node).free()
	_ok("★分母: 宿主释放的这一刻还有 %d 条 tween 在跑 —— 「捕获物先释放」真的形成" % running,
		running >= 3 and not is_instance_valid(stream))
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 700:
		await get_tree().process_frame
	OS.remove_logger(tap)
	_ok("★分母: Logger 真的接得到引擎输出(自检警告 %d 条)" % tap.probe, tap.probe >= 1)
	## ★标签里不许出现报错原文的英文 —— run-tests 的致命正则按原文匹配, 会把这行 PASS 自己判成致命报错。
	_ok("★★tween 跑过宿主释放的时刻, 引擎 0 条「lambda 捕获物已释放」报错(修前每帧一条)",
		tap.lam == 0, "%d 条" % tap.lam)
