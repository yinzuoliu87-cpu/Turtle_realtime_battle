extends Node
## verify_eq_blade_batch.gd — 盾+剑 4 件(081/082/083/084)逐件焊死 + 演出模型门禁
##
## 规格: docs/plans/20260805-装备逐件重做.md §0.5【用户逐件亲手写的定稿】
## 实装: scripts/systems/equip/eq_blade_batch.gd  ·  演出: scripts/scenes/battle/blade_eq_vfx.gd
##
## ★本文件的规矩(契约 §8, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。
##   · 合成单位坐标放 ARENA 【内】—— 放外面会被钳到同一点(500 帧红 1500 帧绿那次)。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##     (唯一例外是"演出与结算必须用同一个数"这类**同一性**断言, 那本来就要读两边。)
##   · 触发一律走【真入口】: `_apply_damage_from` / `_apply_damage`(两条伤害路!) /
##     `_eq_on_basic_attack` / `_eq_on_hit` / `_eq_tick` / `_b4_on_spawn_all` /
##     `SwordsmanSystem.on_basic_attack + tick`。
##     memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」。
##   · **不依赖任何演出 tween / 弹道飞完**(CLAUDE.md §3.5): 084 的十字斩靠同步喂
##     `battle._t` + `_blade_sys.tick(dt)` 推进, 判定全是即时的。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##
## 跑法: <godot> --headless --path . res://tests/verify_eq_blade_batch.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EqBladeBatch := preload("res://scripts/systems/equip/eq_blade_batch.gd")

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


## 干净合成单位。★携带者不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%, 量不准。
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
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["armor_pen_pct"] = 0.0
	u["magic_pen_pct"] = 0.0
	u["aspd_perm"] = 1.0
	u["dots"] = []
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["no_basic"] = true    # ★场景自己的 sim 不要替我出手(数值组全同步判定)
	u["no_move"] = true
	u["move_spd"] = 0.0
	_s._units.append(u)
	return u


func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 走【真登场钩】: EquipStatsApply._b4_on_spawn_all()(它也负责点亮 `_b4_eq` 常驻守卫)
func _spawn_all() -> void:
	_s._equip_sys._stats._b4_on_spawn_all()


func _blade():
	return _s._equip_sys._blade_sys


## 同步推进 n 步 × dt 秒: 显式推战斗时钟 + 喂 EqBladeBatch.tick。
## ★不依赖任何 tween / 真实帧率(CLAUDE.md §3.5)。
func _adv(n: int, dt: float) -> void:
	for k in range(n):
		_s._t += dt
		_blade().tick(dt)


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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 盾+剑 4 件(081 藤编圆盾 / 082 砗磲护心甲 / 083 潮汐细剑 / 084 手半剑) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0     # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准
	_s._over = true       # ★冻结场景自己的 sim: 本门禁全部同步判定, 时钟由我显式推
	_s._units.clear()

	_t_dispatch()
	_t_stats()
	_t081_charge()
	_t081_guard()
	_t081_dot_and_stars()
	_t082_reflect()
	_t082_dot_gate()
	_t082_charge_and_basic()
	_t083_passive()
	_t083_stacks()
	await _t083_swordsman()
	_t084_melee_wiring()
	_t084_cross_slash()
	_t084_ranged()
	_t084_realtime()
	_t_vfx()
	_t_slash_direction()

	_blade().clear_all()
	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 盾+剑 4 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════
# ⓪ 分发纪律与接线 —— 四件落在【已有的】钩子上, 演出与结算共用同一批数
# ═════════════════════════════════════════════════════════════
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	_ok("⓪ ★分母: equip_system.gd 剥注释后非空", code.length() > 20000, "len=%d" % code.length())
	var owner: Dictionary = EquipSystem.B4_OWNER
	var miss: Array = []
	for iid in ["p2eq_081", "p2eq_082", "p2eq_083", "p2eq_084"]:
		if str(owner.get(iid, "")) != "blade":
			miss.append(iid)
	_ok("⓪ B4_OWNER 把 081~084 四件全路由到 blade", miss.is_empty(), "缺 %s" % str(miss))
	_ok("⓪ ★分母: B4_OWNER 一共 17 件(批④ 全表)", owner.size() == 17, "size=%d" % owner.size())
	_ok("⓪ ★★接线: battle._equip_sys._blade_sys 真的存在且是 EqBladeBatch",
		_blade() != null and _blade() is EqBladeBatch, str(_blade()))
	_ok("⓪ ★★接线: 它自己也真的 new 了演出层 BladeEqVfx",
		_blade().vfx != null and _blade().vfx is BladeEqVfx)
	## 每帧节拍真的被调到(084 的十字斩分段/剑波全靠它推进; 不接线 = "排了永远不发")。
	## ★2026-08-06 主会话把【全局】那一半从 `_eq_tick` 抽成了 `tick_global` ——
	##   原来它挂在主循环的"该单位有装备"闸里面, 场上没有带装备的活单位时全局在途表会停摆
	##   (十字斩的剑波正好是这种"携带者死了也该飞完"的东西)。所以这里分两条查, 且要查到主循环。
	var body: String = _fn_body(code, "func tick_global")
	_ok("⓪ ★分母: tick_global 函数体非空", body.length() > 60, "len=%d" % body.length())
	_ok("⓪ tick_global 里真的遍历 _b4_all() 调 tick(delta)【全局在途表】",
		body.contains("_b4_all()") and body.contains(".tick(delta)"))
	var rbraw: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⓪ ★★主循环 _sim_step 真的每帧调 _equip_sys.tick_global(dt)(抽出来没人调 = 剑波永远不飞)",
		_fn_body(rbraw, "func _sim_step").contains("_equip_sys.tick_global(dt)"))
	var ubody: String = _fn_body(code, "func _eq_tick")
	_ok("⓪ ★分母: _eq_tick 函数体非空", ubody.length() > 400, "len=%d" % ubody.length())
	_ok("⓪ _eq_tick 里真的遍历 _b4_all() 调 tick_unit(u, delta)【逐单位】",
		ubody.contains("_b4_all()") and ubody.contains("tick_unit(u, delta)"))
	## ★★两条伤害路径都接了 on_damaged(CLAUDE.md §3.3) —— 少一条 081 就吃不到 DoT
	_ok("⓪ ★§3.3: _eq_on_target(普攻/技能路) 调 on_damaged",
		_fn_body(code, "func _eq_on_target").contains(".on_damaged(u, src,"))
	_ok("⓪ ★§3.3: _b4_on_damaged_any(DoT/真伤路) 也调 on_damaged",
		_fn_body(code, "func _b4_on_damaged_any").contains(".on_damaged(u, src,"))
	var dmgcode: String = _strip("res://scripts/scenes/battle/battle_damage.gd")
	_ok("⓪ ★§3.3: battle_damage 的 _apply_damage 里真的调了 _b4_on_damaged_any",
		_fn_body(dmgcode, "func _apply_damage(").contains("_b4_on_damaged_any"))
	## ★旧效果必须【彻底消失】—— 只删分派不删实现 = 死代码被"断言函数存在"型门禁保护着
	var ghosts: Array = []
	for pair in [["res://scripts/systems/equip/equip_system.gd", "_eq_fang_refresh"],
			["res://scripts/systems/equip/equip_stats_apply.gd", "_fang_pct"],
			["res://scripts/systems/equip/equip_stats_apply.gd", "_clam_dr"],
			["res://scripts/scenes/battle/battle_damage.gd", "_clam_dr"]]:
		if _strip(str(pair[0])).contains(str(pair[1])):
			ghosts.append(str(pair[1]) + " @ " + str(pair[0]).get_file())
	_ok("⓪ ★旧的 082 减伤(_clam_dr) / 084 半血加攻(_fang_*) 已从代码里彻底删除",
		ghosts.is_empty(), str(ghosts))
	## ★演出与结算【同一个数】: 剑波速度 + 十字斩两段的扇形半角
	_ok("⓪ ★焊死: 剑波速度 EqBladeBatch.WAVE_SPD == BladeEqVfx.WAVE_SPD",
		absf(EqBladeBatch.WAVE_SPD - BladeEqVfx.WAVE_SPD) < 1e-9,
		"效果 %.1f / 演出 %.1f" % [EqBladeBatch.WAVE_SPD, BladeEqVfx.WAVE_SPD])
	_ok("⓪ ★焊死: 横斩半角 = 60°(120°/2), 竖斩半角 = 30°(60°/2), 演出侧同值",
		absf(BladeEqVfx.slash_half_rad(1) - deg_to_rad(60.0)) < 1e-6
			and absf(BladeEqVfx.slash_half_rad(3) - deg_to_rad(30.0)) < 1e-6,
		"横 %.6f 竖 %.6f" % [BladeEqVfx.slash_half_rad(1), BladeEqVfx.slash_half_rad(3)])
	## 本批一件都不用 EQ_PERIOD(契约 §2)
	_ok("⓪ 081~084 一件都没排进周期表 EQ_IV_BATCH1(全部自管计时)",
		not EquipSystem.EQ_IV_BATCH1.has("p2eq_081") and not EquipSystem.EQ_IV_BATCH1.has("p2eq_082")
			and not EquipSystem.EQ_IV_BATCH1.has("p2eq_083") and not EquipSystem.EQ_IV_BATCH1.has("p2eq_084"))
	## ★确定性: 本文件不许有裸随机
	var raw: String = FileAccess.get_file_as_string("res://scripts/systems/equip/eq_blade_batch.gd")
	_ok("⓪ ★eq_blade_batch.gd 里没有裸 randi()/randf()(确定性铁律)",
		not raw.contains(" randi()") and not raw.contains(" randf()")
			and not raw.contains("=randi()") and not raw.contains("=randf()"))


# ═════════════════════════════════════════════════════════════
# ⓪b 属性(EquipStats.STATS) —— 逐星硬写, 不读被测表
# ═════════════════════════════════════════════════════════════
func _t_stats() -> void:
	print("── ⓪b 四件的逐星属性 ──")
	var ES := preload("res://scripts/gamedata/equip_stats.gd")
	var want := {
		"p2eq_081": [{"hp": 50, "def": 6}, {"hp": 120, "def": 13}, {"hp": 260, "def": 22}],
		"p2eq_082": [{"hp": 70, "mr": 8}, {"hp": 170, "mr": 17}, {"hp": 380, "mr": 30}],
		"p2eq_083": [{"atk": 18, "crit": 0.10}, {"atk": 42, "crit": 0.18}, {"atk": 92, "crit": 0.30}],
		"p2eq_084": [{"_aspdPct": 10, "_mspdPct": 7}, {"_aspdPct": 18, "_mspdPct": 13}, {"_aspdPct": 30, "_mspdPct": 22}],
	}
	var checked := 0
	for iid in want:
		for si in range(3):
			var got: Dictionary = ES.STATS[iid][si]
			var exp: Dictionary = want[iid][si]
			var bad: Array = []
			if got.size() != exp.size():
				bad.append("字段数 %d≠%d" % [got.size(), exp.size()])
			for k in exp:
				checked += 1
				if not got.has(k) or absf(float(got[k]) - float(exp[k])) > 0.0001:
					bad.append("%s=%s 期望 %s" % [str(k), str(got.get(k, "缺")), str(exp[k])])
			_ok("⓪b %s %d★ 属性 = %s" % [iid, si + 1, str(exp)], bad.is_empty(), str(bad))
	_ok("⓪b ★分母: 一共核了 %d 个属性字段(4 件 × 3 星 × 2 项 = 24)" % checked, checked == 24, "checked=%d" % checked)


# ═════════════════════════════════════════════════════════════
# ① 081 藤编圆盾 · 充能条
#    「每累计受到自身 40/35/30% 最大生命值的伤害后举盾」
# ═════════════════════════════════════════════════════════════
func _charge081(u: Dictionary) -> float:
	return float(((u["eq_state"] as Dictionary).get("p2eq_081", {}) as Dictionary).get("charge", 0.0))


func _hit(atk: Dictionary, u: Dictionary, dmg: int) -> void:
	_s._damage._apply_damage_from(atk, u, dmg, Color("#ffffff"))


func _t081_charge() -> void:
	print("── ① 081 藤编圆盾: 充能条阈值(3★ = 30% 最大生命) ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_081", 3)
	_spawn_all()
	_ok("① ★分母: 开局充能条 = 0 且没在举盾", _charge081(u) == 0.0 and not _blade().b81_guarding(u),
		"charge=%.1f" % _charge081(u))
	_hit(atk, u, 1000)
	_ok("① 挨 1000 → 充能条 1000(3★ 阈值 = 10000×30% = 3000, 还没满)",
		absf(_charge081(u) - 1000.0) < 0.51 and not _blade().b81_guarding(u), "charge=%.1f" % _charge081(u))
	_hit(atk, u, 1000)
	_ok("① 再挨 1000 → 2000, 仍未举盾", absf(_charge081(u) - 2000.0) < 0.51 and not _blade().b81_guarding(u),
		"charge=%.1f" % _charge081(u))
	_hit(atk, u, 1000)
	_ok("① ★第 3 下满 3000 → 举盾(30% 最大生命)", _blade().b81_guarding(u),
		"charge=%.1f guarding=%s" % [_charge081(u), str(_blade().b81_guarding(u))])
	_ok("① 举盾瞬间充能条归零(「举盾结束后重新开始计数」)", absf(_charge081(u)) < 0.01,
		"charge=%.1f" % _charge081(u))


func _t081_guard() -> void:
	print("── ① 081: 举盾期的双抗/护盾/不计充能/不扣攻速/到期回收 ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_081", 3)
	_spawn_all()
	var aspd0: float = float(u["aspd_perm"])
	var iv0: float = float(u["atk_interval"])
	_hit(atk, u, 3000)
	_ok("① 举盾中 +140 双抗(3★): def/mr 各 = 140",
		absf(float(u["def"]) - 140.0) < 0.01 and absf(float(u["mr"]) - 140.0) < 0.01,
		"def=%.1f mr=%.1f" % [float(u["def"]), float(u["mr"])])
	_ok("① 举盾给 160 护盾值(3★)", absf(float(u["shield"]) - 160.0) < 0.51, "shield=%.1f" % float(u["shield"]))
	## ★★用户 2026-08-06 最终拍板「举盾不扣攻速」—— 方案书记了这条方向翻转过两次, 这里焊住
	_ok("① ★★举盾【不扣攻速】: aspd_perm 与 atk_interval 一个都没动",
		absf(float(u["aspd_perm"]) - aspd0) < 1e-9 and absf(float(u["atk_interval"]) - iv0) < 1e-9,
		"aspd %.4f→%.4f  iv %.4f→%.4f" % [aspd0, float(u["aspd_perm"]), iv0, float(u["atk_interval"])])
	## 举盾期间受到的伤害【不计入】充能条
	_hit(atk, u, 2000)
	_ok("① ★举盾期间挨 2000 → 充能条仍是 0(不计入)", absf(_charge081(u)) < 0.01,
		"charge=%.1f" % _charge081(u))
	## 到期回收: 3★ 举盾 3.5 秒
	_s._t += 3.4
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("① 3.4 秒时还在举盾(3★ 时长 3.5 秒)", _blade().b81_guarding(u))
	_s._t += 0.2
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("① ★3.6 秒 → 落盾, 双抗按【自己给的那一份】撤回到 0",
		not _blade().b81_guarding(u) and absf(float(u["def"])) < 0.01 and absf(float(u["mr"])) < 0.01,
		"def=%.1f mr=%.1f" % [float(u["def"]), float(u["mr"])])
	## 落盾后重新开始计数
	_hit(atk, u, 700)
	_ok("① 落盾后再挨 700 → 充能条重新从 0 开始计, 现在 700",
		absf(_charge081(u) - 700.0) < 0.51, "charge=%.1f" % _charge081(u))


func _t081_dot_and_stars() -> void:
	print("── ① 081: ★DoT 也计入充能条(§3.3 两条路) + 逐星阈值/时长 + 多件取高星 ──")
	## ★★这一条守的是 CLAUDE.md §3.3: on_damaged 只挂一条路的话, 灼烧/中毒/流血打的伤害
	##   完全不进充能条 —— 规格写的是"累计受到…的伤害", DoT 也是伤害。
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_081", 3)
	_spawn_all()
	_s._damage._apply_damage(u, 800, Color("#ff8844"), atk, "dot")
	_ok("① ★DoT 路(_apply_damage) 打 800 → 充能条涨到 800", absf(_charge081(u) - 800.0) < 0.51,
		"charge=%.1f" % _charge081(u))
	_hit(atk, u, 200)
	_ok("① ★普攻路(_apply_damage_from) 再打 200 → 1000(两条路加在同一根条上)",
		absf(_charge081(u) - 1000.0) < 0.51, "charge=%.1f" % _charge081(u))
	## 逐星: 1★ 阈值 40% / 举盾 2.5 秒
	_s._units.clear()
	var u1: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var a1: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u1, "p2eq_081", 1)
	_spawn_all()
	_hit(a1, u1, 3999)
	_ok("① 1★ 阈值 = 40% 最大生命 = 4000: 打 3999 不举盾", not _blade().b81_guarding(u1),
		"charge=%.1f" % _charge081(u1))
	_hit(a1, u1, 1)
	_ok("① 1★ 打满 4000 → 举盾, +50 双抗 + 60 护盾",
		_blade().b81_guarding(u1) and absf(float(u1["def"]) - 50.0) < 0.01
			and absf(float(u1["shield"]) - 60.0) < 0.51,
		"def=%.1f shield=%.1f" % [float(u1["def"]), float(u1["shield"])])
	_s._t += 2.4
	_s._equip_sys._eq_tick(u1, 0.016)
	var still: bool = _blade().b81_guarding(u1)
	_s._t += 0.2
	_s._equip_sys._eq_tick(u1, 0.016)
	_ok("① 1★ 举盾时长 = 2.5 秒(2.4 秒还在 / 2.6 秒已落)", still and not _blade().b81_guarding(u1))
	## 2★ 阈值 35% / 举盾 3 秒 / +80 双抗 / 100 护盾
	_s._units.clear()
	var u2: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var a2: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u2, "p2eq_081", 2)
	_spawn_all()
	_hit(a2, u2, 3500)
	_ok("① 2★ 阈值 35% = 3500 → 举盾, +80 双抗 + 100 护盾",
		_blade().b81_guarding(u2) and absf(float(u2["def"]) - 80.0) < 0.01
			and absf(float(u2["shield"]) - 100.0) < 0.51,
		"def=%.1f shield=%.1f" % [float(u2["def"]), float(u2["shield"])])
	## ★多件同带取【星级更高的那一件】, 且同一段伤害只累计一次
	_s._units.clear()
	var um: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var am: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	um["equips"] = [{"id": "p2eq_081", "star": 1}, {"id": "p2eq_081", "star": 3}]
	um["eq_state"] = {}
	_spawn_all()
	_hit(am, um, 1000)
	_ok("① ★带两把 081(1★+3★): 一段 1000 伤害只累计【一次】(不是 2000)",
		absf(_charge081(um) - 1000.0) < 0.51, "charge=%.1f" % _charge081(um))
	_hit(am, um, 2000)
	_ok("① ★两把同带取更高星: 阈值按 3★ 的 30%(3000) 触发, 且只举一次盾",
		_blade().b81_guarding(um) and absf(float(um["def"]) - 140.0) < 0.01,
		"def=%.1f (若两把各加一份会是 190)" % float(um["def"]))


# ═════════════════════════════════════════════════════════════
# ② 082 砗磲护心甲 · 护心反伤
# ═════════════════════════════════════════════════════════════
func _t082_reflect() -> void:
	print("── ② 082 砗磲护心甲: 反伤 3/5/8 点魔法 + 不触发对方反伤 ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_082", 3)
	_equip(atk, "p2eq_082", 3)     # ★攻击者也带一件 —— 验"反伤不触发对方的反伤"
	_spawn_all()
	_ok("② ★分母: 开局双方反伤次数都是 0",
		_blade().b82_reflects(u) == 0 and _blade().b82_reflects(atk) == 0)
	var hp0: float = float(atk["hp"])
	_hit(atk, u, 500)
	_ok("② 3★ 每受一段攻击反伤 8 点魔法给攻击者(攻击者魔抗 0 ⇒ 实扣 8)",
		absf(hp0 - float(atk["hp"]) - 8.0) < 0.51, "攻击者掉血 %.1f" % (hp0 - float(atk["hp"])))
	_ok("② 携带者记 1 次反伤", _blade().b82_reflects(u) == 1, "n=%d" % _blade().b82_reflects(u))
	_ok("② ★★反伤【不】触发对方的反伤(from_equip=true 防无限套娃): 攻击者反伤次数仍为 0",
		_blade().b82_reflects(atk) == 0, "n=%d" % _blade().b82_reflects(atk))
	## 逐星 1★=3 / 2★=5
	for pair in [[1, 3.0], [2, 5.0]]:
		_s._units.clear()
		var c: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
		var a: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
		_equip(c, "p2eq_082", int(pair[0]))
		_spawn_all()
		var h0: float = float(a["hp"])
		_hit(a, c, 500)
		_ok("② %d★ 反伤 %d 点" % [int(pair[0]), int(pair[1])],
			absf(h0 - float(a["hp"]) - float(pair[1])) < 0.51, "实扣 %.1f" % (h0 - float(a["hp"])))
	## 多段攻击每段独立计数
	_s._units.clear()
	var c2: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
	var a2: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(c2, "p2eq_082", 3)
	_spawn_all()
	for k in range(4):
		_hit(a2, c2, 100)
	_ok("② 多段攻击【每段独立计数】: 打 4 段 → 反伤 4 次", _blade().b82_reflects(c2) == 4,
		"n=%d" % _blade().b82_reflects(c2))


func _t082_dot_gate() -> void:
	print("── ② 082: ★DoT 每跳【不算】一段攻击(用户 2026-08-06 拍板) ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_082", 3)
	_spawn_all()
	var hp0: float = float(atk["hp"])
	for k in range(5):
		_s._damage._apply_damage(u, 100, Color("#ff8844"), atk, "dot")
	_ok("② ★DoT 路打 5 跳 → 反伤次数仍是 0(灼烧/中毒/流血不喂充能)",
		_blade().b82_reflects(u) == 0, "n=%d" % _blade().b82_reflects(u))
	_ok("② ★DoT 路 5 跳也没有反伤打到攻击者身上", absf(hp0 - float(atk["hp"])) < 0.01,
		"攻击者掉血 %.1f" % (hp0 - float(atk["hp"])))
	## ★分母: 同一副探针走普攻路必须涨 —— 证明上面那两条不是"钩子根本没被调"
	_hit(atk, u, 100)
	_ok("② ★★分母: 同一只龟走普攻路(_apply_damage_from)打 1 段 → 反伤次数涨到 1",
		_blade().b82_reflects(u) == 1, "n=%d" % _blade().b82_reflects(u))


func _t082_charge_and_basic() -> void:
	print("── ② 082: 每反伤 15 次攒一层 → 普攻消耗一层(回血 + 100% 魔抗魔伤) ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_082", 3)
	_spawn_all()
	u["base_mr"] = 50.0
	_s._recalc_stats(u)
	_ok("② ★分母: 携带者魔抗被设成 50(强化普攻的附带魔伤应等于它)",
		absf(float(u["mr"]) - 50.0) < 0.01, "mr=%.1f" % float(u["mr"]))
	for k in range(14):
		_hit(atk, u, 10)
	_ok("② 反伤 14 次 → 还没攒到一层充能", _blade().b82_charges(u) == 0,
		"charges=%d" % _blade().b82_charges(u))
	_hit(atk, u, 10)
	_ok("② ★第 15 次反伤 → 攒到 1 层充能", _blade().b82_charges(u) == 1,
		"charges=%d" % _blade().b82_charges(u))
	## 普攻消耗一层: 走【真入口】_eq_on_basic_attack
	u["hp"] = 5000.0
	var thp: float = float(atk["hp"])
	_s._equip_sys._eq_on_basic_attack(u, atk)
	_ok("② ★普攻消耗一层充能(走真入口 _eq_on_basic_attack)", _blade().b82_charges(u) == 0,
		"charges=%d" % _blade().b82_charges(u))
	_ok("② 3★ 回复 10% 最大生命 = 1000(5000 → 6000)", absf(float(u["hp"]) - 6000.0) < 1.01,
		"hp=%.1f" % float(u["hp"]))
	_ok("② ★附带「相当于自身 100% 魔抗」的魔法伤害 = 50",
		absf(thp - float(atk["hp"]) - 50.0) < 0.51, "目标掉血 %.1f" % (thp - float(atk["hp"])))
	## 没充能时普攻什么都不做(不白回血)
	u["hp"] = 5000.0
	var thp2: float = float(atk["hp"])
	_s._equip_sys._eq_on_basic_attack(u, atk)
	_ok("② 没充能时普攻不回血也不附带魔伤",
		absf(float(u["hp"]) - 5000.0) < 0.01 and absf(thp2 - float(atk["hp"])) < 0.01,
		"hp=%.1f 目标掉血 %.1f" % [float(u["hp"]), thp2 - float(atk["hp"])])
	## ★多件同带: 一次普攻只消耗【一层】(不是每份各消耗一层)
	## ⚠ 这条守的是去重口径 —— 分派循环按份数连着调 n 次, 帧号去重在"一帧跑多个 sim 步"时会漏,
	##   所以实现用的是【按份数取模】。这里带两把、攒两层, 一次普攻应当只掉一层。
	_s._units.clear()
	var um: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var am: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	um["equips"] = [{"id": "p2eq_082", "star": 3}, {"id": "p2eq_082", "star": 3}]
	um["eq_state"] = {}
	_spawn_all()
	for k in range(30):
		_hit(am, um, 10)
	_ok("② ★带两把 082: 30 段攻击只反伤 30 次(不是 60), 攒到 2 层",
		_blade().b82_reflects(um) == 30 and _blade().b82_charges(um) == 2,
		"n=%d charges=%d" % [_blade().b82_reflects(um), _blade().b82_charges(um)])
	_s._equip_sys._eq_on_basic_attack(um, am)
	_ok("② ★带两把 082: 一次普攻只消耗【一层】(剩 1 层, 不是 0)",
		_blade().b82_charges(um) == 1, "charges=%d" % _blade().b82_charges(um))
	_s._equip_sys._eq_on_basic_attack(um, am)
	_ok("② ★★分母: 第二次普攻把最后一层也消耗掉(证明上一条不是「钩子根本没跑」)",
		_blade().b82_charges(um) == 0, "charges=%d" % _blade().b82_charges(um))


# ═════════════════════════════════════════════════════════════
# ③ 083 潮汐细剑
# ═════════════════════════════════════════════════════════════
func _t083_passive() -> void:
	print("── ③ 083 潮汐细剑: 被动「每损失 1% 生命 +0.2/0.3/0.4% 攻速」 ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	_equip(u, "p2eq_083", 3)
	_spawn_all()
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("③ ★分母: 满血时不给攻速(aspd_perm = 1.0)", absf(float(u["aspd_perm"]) - 1.0) < 1e-6,
		"aspd_perm=%.4f" % float(u["aspd_perm"]))
	u["hp"] = 5000.0
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("③ 3★ 剩 50% 血 → +20% 攻速(50 × 0.4%)", absf(float(u["aspd_perm"]) - 1.20) < 1e-4,
		"aspd_perm=%.4f" % float(u["aspd_perm"]))
	u["hp"] = 1000.0
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("③ ★实时跟随: 掉到剩 10% 血 → +36% 攻速(90 × 0.4%), 不是在旧值上叠",
		absf(float(u["aspd_perm"]) - 1.36) < 1e-4, "aspd_perm=%.4f" % float(u["aspd_perm"]))
	u["hp"] = 10000.0
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("③ 血回满 → 攻速加成退回 0(撤旧贡献是镜像的, 不留残值)",
		absf(float(u["aspd_perm"]) - 1.0) < 1e-6, "aspd_perm=%.4f" % float(u["aspd_perm"]))
	## 1★ / 2★
	for pair in [[1, 0.2], [2, 0.3]]:
		_s._units.clear()
		var c: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
		_equip(c, "p2eq_083", int(pair[0]))
		_spawn_all()
		c["hp"] = 5000.0
		_s._equip_sys._eq_tick(c, 0.016)
		var want: float = 1.0 + 50.0 * float(pair[1]) / 100.0
		_ok("③ %d★ 剩 50%% 血 → +%.0f%% 攻速" % [int(pair[0]), 50.0 * float(pair[1])],
			absf(float(c["aspd_perm"]) - want) < 1e-4,
			"aspd_perm=%.4f 期望 %.4f" % [float(c["aspd_perm"]), want])


func _t083_stacks() -> void:
	print("── ③ 083: 连续命中同一目标叠层(≤20)· 每层 +1/1.5/2% 增伤 + 0.5% 吸血 ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
	var t1: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	var t2: Dictionary = _mk("fortune", "right", Vector2(200.0, 120.0))
	_equip(u, "p2eq_083", 3)
	_spawn_all()
	_ok("③ ★分母: 开局 0 层、无增伤、无吸血",
		_blade().b83_stacks(u) == 0 and absf(float(u["damage_amp"])) < 1e-9
			and absf(float(u["lifesteal"])) < 1e-9)
	for k in range(3):
		_hit(u, t1, 100)
	_ok("③ 连打同一目标 3 下 → 3 层", _blade().b83_stacks(u) == 3, "stacks=%d" % _blade().b83_stacks(u))
	_ok("③ 3 层 3★ → 增伤 6%(3×2%) + 吸血 1.5%(3×0.5%)",
		absf(float(u["damage_amp"]) - 0.06) < 1e-6 and absf(float(u["lifesteal"]) - 0.015) < 1e-6,
		"amp=%.4f ls=%.4f" % [float(u["damage_amp"]), float(u["lifesteal"])])
	_hit(u, t2, 100)
	_ok("③ ★切换目标 → 层数清空后从 1 起算", _blade().b83_stacks(u) == 1,
		"stacks=%d" % _blade().b83_stacks(u))
	_ok("③ 切目标后增伤/吸血跟着回到 1 层的量(2% / 0.5%)",
		absf(float(u["damage_amp"]) - 0.02) < 1e-6 and absf(float(u["lifesteal"]) - 0.005) < 1e-6,
		"amp=%.4f ls=%.4f" % [float(u["damage_amp"]), float(u["lifesteal"])])
	for k in range(30):
		_hit(u, t2, 100)
	_ok("③ ★打 31 下同一目标 → 层数封顶 20(不是 31)", _blade().b83_stacks(u) == 20,
		"stacks=%d" % _blade().b83_stacks(u))
	_ok("③ 满 20 层 3★ → 增伤 40% + 吸血 10%(0.5%×20, 不随星级变)",
		absf(float(u["damage_amp"]) - 0.40) < 1e-6 and absf(float(u["lifesteal"]) - 0.10) < 1e-6,
		"amp=%.4f ls=%.4f" % [float(u["damage_amp"]), float(u["lifesteal"])])
	## 目标死亡 → 清空(走每帧真入口 _eq_tick)
	t2["alive"] = false
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("③ ★目标死亡也算切换目标: 层数清空, 增伤/吸血一并撤回",
		_blade().b83_stacks(u) == 0 and absf(float(u["damage_amp"])) < 1e-9
			and absf(float(u["lifesteal"])) < 1e-9,
		"stacks=%d amp=%.4f ls=%.4f" % [_blade().b83_stacks(u), float(u["damage_amp"]), float(u["lifesteal"])])
	## 1★ / 2★ 每层增伤
	for pair in [[1, 0.01], [2, 0.015]]:
		_s._units.clear()
		var c: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
		var tt: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
		_equip(c, "p2eq_083", int(pair[0]))
		_spawn_all()
		for k in range(4):
			_hit(c, tt, 100)
		_ok("③ %d★ 4 层 → 增伤 %.1f%%" % [int(pair[0]), 4.0 * float(pair[1]) * 100.0],
			absf(float(c["damage_amp"]) - 4.0 * float(pair[1])) < 1e-6,
			"amp=%.4f" % float(c["damage_amp"]))


func _t083_swordsman() -> void:
	print("── ③ 083: ★剑羁绊【剑士】的追打【计入】连续命中(用户 2026-08-06 拍板) ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
	var t1: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_083", 3)
	u["equips"] = [{"id": "p2eq_083", "star": 3}]
	_spawn_all()
	_s._synergy._by_side["left"] = {"剑": 1}   # 剑 1 档 = 追打 1 次(测试台架, 断言仍走真追打路径)
	_ok("③ ★分母: 剑羁绊档位真的被点亮成 1 档", int(_s._synergy.tier_for(u, "剑")) == 1,
		"tier=%d" % int(_s._synergy.tier_for(u, "剑")))
	_hit(u, t1, 100)
	var s0: int = _blade().b83_stacks(u)
	_ok("③ ★分母: 一次普攻命中先给 1 层", s0 == 1, "stacks=%d" % s0)
	## 走【真入口】: SwordsmanSystem.on_basic_attack 排队 → tick 到点打出 → 管线回钩 _eq_on_hit
	_s._swordsman.on_basic_attack(u, t1)
	_s._t += 5.0
	_s._swordsman.tick(0.016)
	_ok("③ ★★剑士追打打出后, 层数从 1 涨到 2(追打计入连续命中)",
		_blade().b83_stacks(u) == 2, "stacks=%d" % _blade().b83_stacks(u))
	await get_tree().process_frame


# ═════════════════════════════════════════════════════════════
# ④ 084 手半剑
# ═════════════════════════════════════════════════════════════
func _t084_melee_wiring() -> void:
	print("── ④ 084 手半剑【近战携带】: 450 码射程 + 技能换成 80 龟能的后撤十字斩 ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
	_mk("fortune", "right", Vector2(200.0, 0.0))
	_ok("④ ★分母: fortune 出厂是近战(melee=true), 射程 100",
		bool(u["melee"]) and absf(float(u["atk_range"]) - 100.0) < 0.01,
		"melee=%s range=%.1f" % [str(u["melee"]), float(u["atk_range"])])
	var o_skills: Array = (u.get("active_skills", []) as Array).duplicate()
	_equip(u, "p2eq_084", 3)
	_spawn_all()
	_ok("④ 近战携带 → 获得 450 码射程", absf(float(u["atk_range"]) - 450.0) < 0.01,
		"atk_range=%.1f" % float(u["atk_range"]))
	_ok("④ ★只改射程【数值】, 不改 melee 标记(用户拍板)", bool(u["melee"]) == true,
		"melee=%s" % str(u["melee"]))
	_ok("④ 技能被替换(原技能表被换掉)", (u["active_skills"] as Array) != o_skills,
		"%s → %s" % [str(o_skills), str(u["active_skills"])])
	_ok("④ ★换成的技花费 = 80 龟能(走引擎 _skill_cost 真表, 不是自己发明一个数)",
		absf(_s._skill_cost(u, EqBladeBatch.HH_SKILL) - 80.0) < 1e-6,
		"cost=%.1f" % _s._skill_cost(u, EqBladeBatch.HH_SKILL))
	_ok("④ 充满 80 龟能要 6.0 秒(引擎口径 cost×0.075)",
		absf(_s._skill_cd(u, EqBladeBatch.HH_SKILL) - 6.0) < 1e-6,
		"cd=%.3f" % _s._skill_cd(u, EqBladeBatch.HH_SKILL))
	_ok("④ 龟能条真的挂在引擎的 skill_cd 上(由 _tick_skill_cd 每帧扣)",
		(u["skill_cd"] as Dictionary).has(EqBladeBatch.HH_SKILL), str(u["skill_cd"]))
	## 引擎侧真的会把 skill_cd 扣下去(不是我自己扣) —— 走真入口 _tick_skill_cd
	var cd0: float = float((u["skill_cd"] as Dictionary)[EqBladeBatch.HH_SKILL])
	_s._tick_skill_cd(u, 1.0)
	_ok("④ ★引擎 _tick_skill_cd 真的在给这个技充能(1 秒扣 1 秒)",
		absf(cd0 - float((u["skill_cd"] as Dictionary)[EqBladeBatch.HH_SKILL]) - 1.0) < 1e-4,
		"%.3f → %.3f" % [cd0, float((u["skill_cd"] as Dictionary)[EqBladeBatch.HH_SKILL])])
	## ★★把【现状】钉进断言, 而不是顺手绕过去:
	##   引擎那张 `_IMPL_SKILLS` 与 `_do_skill` 的 match 都在 RealtimeBattle3DScene.gd(共享文件),
	##   本路不能改 ⇒ 十字斩现在走 EqBladeBatch 的自驱。主会话要接的是【两行】——
	##   `_IMPL_SKILLS` 加一条 + `_do_skill` 分派到 `cast_cross_slash`。
	##   只接一半(加了常量没加分派)会让技能【静默变哑】: 引擎选中它 → _do_skill 没分支 → 什么都不发生,
	##   而自驱那边看到 `_IMPL_SKILLS.has()` 为真会主动让位 ⇒ 两边都不发。这条断言就是堵这个。
	##   2026-08-06 主会话把两行都接上了 ⇒ 下面这些断言现在守的是"两行还在、且真的被走到"。
	var rbcode: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var wired: bool = _s._IMPL_SKILLS.has(EqBladeBatch.HH_SKILL)
	var dispatched: bool = rbcode.contains("cast_cross_slash")
	_ok("④ ★★十字斩的两行要么都接要么都不接(只接一半 = 技能静默变哑)",
		wired == dispatched,
		"_IMPL_SKILLS 收录=%s / _do_skill 分派=%s" % [str(wired), str(dispatched)])
	_ok("④ ★分母: 这条断言读到的主场景源码非空", rbcode.length() > 100000, "len=%d" % rbcode.length())
	## ★★证据一(对应 `_IMPL_SKILLS` 那一行): 引擎的**选技链路**真的会挑中这个技。
	##   `_pick_ready_skill` 里 `if not _IMPL_SKILLS.has(st): continue` —— 没那一行就永远返回 ""。
	(u["skill_cd"] as Dictionary)[EqBladeBatch.HH_SKILL] = 0.0
	u["skill_gcd_until"] = 0.0
	_ok("④ ★★引擎 _pick_ready_skill 真的挑中【后撤十字斩】(= `_IMPL_SKILLS` 那一行被走到)",
		str(_s._pick_ready_skill(u)) == EqBladeBatch.HH_SKILL,
		"挑中的是 '%s'" % str(_s._pick_ready_skill(u)))
	## ★头顶龟能条: battle_render 对不在 _IMPL_SKILLS 的 type 直接 continue ⇒ 接表前恒为 0。
	##   ★量【真实节点】的宽度, 不是把那段公式在门禁里抄一遍(抄公式的门禁, 产品改成写死也照样绿)。
	(u["skill_cd"] as Dictionary)[EqBladeBatch.HH_SKILL] = 3.0   # 满冷却 6.0 的一半 ⇒ 充能 50%
	_s._render._render_step(0.016, false, false)
	var enf = u.get("en_fill", null)
	_ok("④ ★分母: 携带者头顶真的有龟能条节点", enf != null and is_instance_valid(enf), str(enf))
	_ok("④ ★★头顶龟能条真的跟着这个技走(充能 50% → 条宽 = 满宽的一半; 接表前它恒为 0)",
		enf != null and absf(float(enf.size.x) - _s.BAR_W * 0.5) < 0.51,
		"条宽 %.2f / 满宽 %.2f" % [float(enf.size.x) if enf != null else -1.0, _s.BAR_W])
	## 后撤落点几何(纯函数, 不等 tween)
	_s._units.clear()
	var a: Dictionary = _mk("fortune", "left", Vector2(0.0, 0.0))
	var b: Dictionary = _mk("fortune", "right", Vector2(300.0, 0.0))
	var dest: Vector2 = _blade().cross_retreat_dest(a, b)
	_ok("④ 后撤落点 = 背对目标 150 码(纯几何, 不依赖任何 tween)",
		absf((dest - a["pos"]).length() - 150.0) < 0.01
			and absf((dest - a["pos"]).normalized().angle_to(Vector2.LEFT)) < 1e-4,
		"位移 %.2f 码, 方向 %s" % [(dest - a["pos"]).length(), str((dest - a["pos"]).normalized())])
	a["pos"] = Vector2(_s.ARENA.position.x + 20.0, _s.ARENA.position.y + 200.0)
	b["pos"] = a["pos"] + Vector2(300.0, 0.0)
	var d2: Vector2 = _blade().cross_retreat_dest(a, b)
	_ok("④ 后撤落点被钳在场地内(贴左边界时不会退出去)",
		d2.x >= _s.ARENA.position.x - 0.01 and d2.x <= _s.ARENA.end.x + 0.01, "dest=%s" % str(d2))


func _t084_cross_slash() -> void:
	print("── ④ 084【后撤十字斩】四段伤害: 3★ 全中 = 475 + 5.1×ATK ──")
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-100.0, 0.0))
	var tgt: Dictionary = _mk("fortune", "right", Vector2(-20.0, 0.0), 1000000.0)
	_equip(u, "p2eq_084", 3)
	_spawn_all()
	u["base_atk"] = 100.0
	_s._recalc_stats(u)
	_ok("④ ★分母: 携带者 ATK 被设成 100(四段公式里的 ATK 项)",
		absf(float(u["atk"]) - 100.0) < 0.01, "atk=%.1f" % float(u["atk"]))
	_ok("④ ★分母: 目标出厂零承伤记录", int(tgt.get("_st_taken", 0)) == 0)
	## ★★走【引擎真入口】: _cast_skill → _do_skill 的 match → cast_cross_slash。
	##   这是主会话加的那两行是否真被用上的**唯一证据** —— 注释掉 `_do_skill` 那一行, 这条立刻红。
	(u["skill_cd"] as Dictionary)[EqBladeBatch.HH_SKILL] = 0.0
	u["skill_gcd_until"] = 0.0
	var fired: bool = _s._cast_skill(u, tgt, EqBladeBatch.HH_SKILL)
	_ok("④ ★★经引擎真入口 _cast_skill → _do_skill 施放了一次十字斩(= `_do_skill` 那一行被走到)",
		fired and int(u.get("_b84_casts", 0)) == 1,
		"_cast_skill=%s casts=%d" % [str(fired), int(u.get("_b84_casts", 0))])
	## ★★★自驱确实【停手】了, 没有双发。
	##   注意此刻 `skill_cd` 仍是 0(冷却由 _tick_unit 在 _cast_skill 【之后】重置, 这里没走那一步),
	##   所以只要自驱还活着, 下面这几帧 _eq_tick 一定会再放一次 —— 这条断言因此是硬的。
	for k in range(5):
		_s._equip_sys._eq_tick(u, 0.016)
	_ok("④ ★★★引擎接管后自驱让位: 连喂 5 帧 _eq_tick(且冷却仍是 0)也没有第二次施放",
		int(u.get("_b84_casts", 0)) == 1 and _blade().b84_pending() == 2,
		"casts=%d pending=%d(双发会是 2 / 4)" % [int(u.get("_b84_casts", 0)), _blade().b84_pending()])
	_ok("④ 后撤已发生: 携带者与目标的距离变成 230 码(80 + 150)",
		absf((tgt["pos"] - u["pos"]).length() - 230.0) < 0.51,
		"dist=%.1f" % (tgt["pos"] - u["pos"]).length())
	_ok("④ ★分母: 十字斩排了 2 段待结算(横组 / 竖组), 此刻还没有伤害",
		_blade().b84_pending() == 2 and int(tgt.get("_st_taken", 0)) == 0,
		"pending=%d taken=%d" % [_blade().b84_pending(), int(tgt.get("_st_taken", 0))])
	## ★用 0.02 秒的小步推进(不是一次跳 0.26 秒) —— 步长太大时剑波会在生成的【同一步】就飞完
	##   230 码撞上目标, 于是"横斩"和"横波"两段的伤害叠在一次读数里, 分不开。
	##   (第一版就是这么写的, 量到 445 = 270+175。这行注释留着, 别再退回去。)
	## ★★2026-08-29 起近战携带 084 还带 **{C:HH_MELEE_AMP} 增伤**(用户新加), 所以四段的实得
	##   都是【底伤 × (1 + 增伤)】。★期望值**从常量推导**, 不写死新数字 ——
	##   写死的话下次调增伤系数, 这里就又漂了(memory [[fb-refactor-creates-the-drift-it-removes]])。
	var _amp3: float = 1.0 + float(EqBladeBatch.HH_MELEE_AMP[2])       # 3★
	var _amp1: float = 1.0 + float(EqBladeBatch.HH_MELEE_AMP[0])       # 1★
	var _e1: int = int(round(270.0 * _amp3))
	var _e2: int = int(round(175.0 * _amp3))
	var _e3: int = int(round(330.0 * _amp3))
	var _e4: int = int(round(210.0 * _amp3))
	_ok("④ ★分母: 3★ 近战增伤真的挂上了(×%.2f)" % _amp3,
		absf(float(u.get("damage_amp", 0.0)) - float(EqBladeBatch.HH_MELEE_AMP[2])) < 0.0001,
		"damage_amp=%.3f" % float(u.get("damage_amp", 0.0)))
	_adv(13, 0.02)
	var d1: int = int(tgt.get("_st_taken", 0))
	_ok("④ ① 横斩(250 码 120° 扇形) = (130 + 1.4×ATK) × 增伤 = %d" % _e1,
		absf(float(d1 - _e1)) <= 1.0, "实得 %d" % d1)
	## 横波: 900 码/秒推进, 目标在 230 码处, 波前带 ±60 → 再过 0.19~0.32 秒命中
	_adv(12, 0.02)
	var d2: int = int(tgt.get("_st_taken", 0)) - d1
	_ok("④ ② 横波(直线贯穿) = (85 + 0.9×ATK) × 增伤 = %d" % _e2,
		absf(float(d2 - _e2)) <= 1.0, "实得 %d" % d2)
	## 推进到第 ③ 段(0.60 秒)
	_adv(6, 0.02)
	var d3: int = int(tgt.get("_st_taken", 0)) - d1 - d2
	_ok("④ ③ 竖斩(250 码) = (160 + 1.7×ATK) × 增伤 = %d" % _e3,
		absf(float(d3 - _e3)) <= 1.0, "实得 %d" % d3)
	## 竖波
	_adv(14, 0.02)
	var d4: int = int(tgt.get("_st_taken", 0)) - d1 - d2 - d3
	_ok("④ ④ 竖波(竖向贯穿) = (100 + 1.1×ATK) × 增伤 = %d" % _e4,
		absf(float(d4 - _e4)) <= 1.0, "实得 %d" % d4)
	## ★★这条同时是"没有双发"的硬证据: 引擎放一次 + 自驱也放一次的话合计会是 1970。
	## ★★这条同时是"没有双发"的硬证据: 引擎放一次 + 自驱也放一次的话合计会翻倍。
	var _eall: int = _e1 + _e2 + _e3 + _e4
	_ok("④ ★四段全中合计 = %d 且【只结算一遍】(底伤 985 × 增伤; 双发会是两倍)" % _eall,
		absf(float(int(tgt.get("_st_taken", 0)) - _eall)) <= 2.0,
		"合计 %d" % int(tgt.get("_st_taken", 0)))
	## 波飞完要收干净(不然会带进下一路)
	_adv(20, 0.06)
	_ok("④ 剑波飞满 700 码后自动收掉(在途表清空)", _blade().b84_waves() == 0,
		"waves=%d" % _blade().b84_waves())
	## 1★ 四段(只验横斩与竖斩两段的字面值, 波同源)
	_s._units.clear()
	var u1: Dictionary = _mk("fortune", "left", Vector2(-100.0, 0.0))
	var g1: Dictionary = _mk("fortune", "right", Vector2(-40.0, 0.0), 1000000.0)
	_equip(u1, "p2eq_084", 1)
	_spawn_all()
	u1["base_atk"] = 100.0
	_s._recalc_stats(u1)
	var hit1: int = _blade().cross_slash_hit(u1, Vector2.RIGHT, 0, 1)
	_ok("④ 1★ ① 横斩 = (40 + 0.6×100) × 增伤 = %d(且真的命中 1 个目标)" % int(round(100.0 * _amp1)),
		hit1 == 1 and absf(float(int(g1.get("_st_taken", 0)) - int(round(100.0 * _amp1)))) <= 1.0,
		"hit=%d dmg=%d" % [hit1, int(g1.get("_st_taken", 0))])
	var before3: int = int(g1.get("_st_taken", 0))
	_blade().cross_slash_hit(u1, Vector2.RIGHT, 0, 3)
	_ok("④ 1★ ③ 竖斩 = (50 + 0.7×100) × 增伤 = %d" % int(round(120.0 * _amp1)),
		absf(float(int(g1.get("_st_taken", 0)) - before3 - int(round(120.0 * _amp1)))) <= 1.0,
		"实得 %d" % (int(g1.get("_st_taken", 0)) - before3))
	## 扇形是真的有角度(背后的敌人打不到)
	_s._units.clear()
	var u2: Dictionary = _mk("fortune", "left", Vector2(0.0, 0.0))
	var back: Dictionary = _mk("fortune", "right", Vector2(-150.0, 0.0), 1000000.0)
	_equip(u2, "p2eq_084", 3)
	_spawn_all()
	var hitb: int = _blade().cross_slash_hit(u2, Vector2.RIGHT, 2, 1)
	_ok("④ ★横斩是 120° 扇形不是全场: 正后方 150 码的敌人打不到",
		hitb == 0 and int(back.get("_st_taken", 0)) == 0,
		"hit=%d taken=%d" % [hitb, int(back.get("_st_taken", 0))])


func _t084_ranged() -> void:
	print("── ④ 084【远程携带】: 射程固定 100 + 三项属性 + 每转化 100 码 +20% ──")
	_s._units.clear()
	var u: Dictionary = _mk("cyber", "left", Vector2(-200.0, 0.0), 3000.0)
	_ok("④ ★分母: cyber 出厂是远程, 射程 450(§0.5 表里的「裸远程龟」那一行)",
		not bool(u["melee"]) and absf(float(u["atk_range"]) - 450.0) < 0.01,
		"melee=%s range=%.1f" % [str(u["melee"]), float(u["atk_range"])])
	u["base_atk"] = 200.0
	_s._recalc_stats(u)
	var hp0: float = float(u["maxHp"])
	_equip(u, "p2eq_084", 3)
	_spawn_all()
	_ok("④ ★★有效射程被【真的】固定成 100 码(量 battle._eff_range, 不是自造键)",
		absf(_s._eff_range(u) - 100.0) < 0.01, "_eff_range=%.2f" % _s._eff_range(u))
	_ok("④ 转化量 = 450 − 100 = 350 码", absf(float(u.get("_b84_conv", -1.0)) - 350.0) < 0.01,
		"conv=%.1f" % float(u.get("_b84_conv", -1.0)))
	_ok("④ 倍率 = 1 + 20% × (350/100) = ×1.70(§0.5 表)",
		absf(float(u.get("_b84_mult", 0.0)) - 1.70) < 1e-4, "mult=%.4f" % float(u.get("_b84_mult", 0.0)))
	_ok("④ 3★ 最大生命 +%d × 1.70 = +%d(基数由 HH_RANGED_HP 推导)"
			% [int(EqBladeBatch.HH_RANGED_HP[2]), int(round(float(EqBladeBatch.HH_RANGED_HP[2]) * 1.70))],
		absf(float(u["maxHp"]) - hp0 - float(EqBladeBatch.HH_RANGED_HP[2]) * 1.70) < 1.51,
		"maxHp %.0f → %.0f" % [hp0, float(u["maxHp"])])
	_ok("④ 3★ 生命偷取 = 15% × 1.70 = 25.5%(§0.5 表)",
		absf(float(u["lifesteal"]) - 0.255) < 1e-4, "ls=%.4f" % float(u["lifesteal"]))
	_ok("④ 3★ 额外攻击力 = 登场攻击力 200 × 20% × 1.70 = +68",
		absf(float(u["atk"]) - 268.0) < 0.51, "atk=%.1f" % float(u["atk"]))
	_ok("④ ★远程侧【不】替换主动技能(规格明写)", not (u["active_skills"] as Array).has(EqBladeBatch.HH_SKILL),
		str(u["active_skills"]))
	## 1★ / 2★
	## ★基数从 HH_RANGED_HP 取, 不写死 —— 2026-08-29 用户把它从 200/400/1000 提到
	##   300/700/3000, 写死的话这里就漂了。
	for pair in [[1, float(EqBladeBatch.HH_RANGED_HP[0]), 0.10],
			[2, float(EqBladeBatch.HH_RANGED_HP[1]), 0.125]]:
		_s._units.clear()
		var c: Dictionary = _mk("cyber", "left", Vector2(-200.0, 0.0), 3000.0)
		var h0: float = float(c["maxHp"])
		_equip(c, "p2eq_084", int(pair[0]))
		_spawn_all()
		_ok("④ %d★ 最大生命 +%.0f × 1.70" % [int(pair[0]), float(pair[1])],
			absf(float(c["maxHp"]) - h0 - float(pair[1]) * 1.7) < 1.51,
			"实得 +%.0f" % (float(c["maxHp"]) - h0))
		_ok("④ %d★ 生命偷取 = %.1f%% × 1.70" % [int(pair[0]), float(pair[2]) * 100.0],
			absf(float(c["lifesteal"]) - float(pair[2]) * 1.7) < 1e-4, "ls=%.4f" % float(c["lifesteal"]))


func _t084_realtime() -> void:
	print("── ④ 084: ★★射程转化是【实时】的(战斗中拿到射程也要被转化掉) ──")
	_s._units.clear()
	var u: Dictionary = _mk("cyber", "left", Vector2(-200.0, 0.0), 3000.0)
	var hp0: float = float(u["maxHp"])
	_equip(u, "p2eq_084", 3)
	_spawn_all()
	_ok("④ ★分母: 登场时倍率 ×1.70 / 生命 +%d / 吸血 25.5%%" % int(round(float(EqBladeBatch.HH_RANGED_HP[2]) * 1.70)),
		absf(float(u["_b84_mult"]) - 1.70) < 1e-4
			and absf(float(u["maxHp"]) - hp0 - float(EqBladeBatch.HH_RANGED_HP[2]) * 1.70) < 1.51,
		"mult=%.4f maxHp+%.0f" % [float(u["_b84_mult"]), float(u["maxHp"]) - hp0])
	## 战斗中拿到 +100 码 flat 射程(073 藤蔓弓弦口径) → 走每帧真入口 _eq_tick 重算
	u["range_add"] = float(u.get("range_add", 0.0)) + 100.0
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("④ ★★战斗中 +100 码射程 → 转化量 450, 倍率 ×1.90(§0.5 「+073」那一行)",
		absf(float(u["_b84_conv"]) - 450.0) < 0.01 and absf(float(u["_b84_mult"]) - 1.90) < 1e-4,
		"conv=%.1f mult=%.4f" % [float(u["_b84_conv"]), float(u["_b84_mult"])])
	_ok("④ ★★属性跟着实时长: 最大生命 +%d / 吸血 28.5%%" % int(round(float(EqBladeBatch.HH_RANGED_HP[2]) * 1.90)),
		absf(float(u["maxHp"]) - hp0 - float(EqBladeBatch.HH_RANGED_HP[2]) * 1.90) < 1.51
			and absf(float(u["lifesteal"]) - 0.285) < 1e-4,
		"maxHp+%.0f ls=%.4f" % [float(u["maxHp"]) - hp0, float(u["lifesteal"])])
	_ok("④ ★有效射程仍然恰好是 100(新拿到的射程被【卖掉】了, 不是加上去)",
		absf(_s._eff_range(u) - 100.0) < 0.01, "_eff_range=%.2f" % _s._eff_range(u))
	## 再拿 % 射程(065/075 口径) —— 另一条通道也要被吃掉
	u["range_perm"] = float(u.get("range_perm", 1.0)) + 0.20
	_s._equip_sys._eq_tick(u, 0.016)
	_ok("④ ★% 射程通道也被实时转化: 自然射程 (450+100)×1.2 = 660 → 转化 560 → ×2.12",
		absf(float(u["_b84_conv"]) - 560.0) < 0.51 and absf(float(u["_b84_mult"]) - 2.12) < 1e-3,
		"conv=%.1f mult=%.4f" % [float(u["_b84_conv"]), float(u["_b84_mult"])])
	_ok("④ 有效射程还是 100(两条通道都卖掉了)", absf(_s._eff_range(u) - 100.0) < 0.01,
		"_eff_range=%.2f" % _s._eff_range(u))
	## 反向: 属性不会每帧越滚越大(差量施加, 不是每帧再加一次)
	var mh: float = float(u["maxHp"])
	for k in range(20):
		_s._equip_sys._eq_tick(u, 0.016)
	_ok("④ ★连跑 20 帧属性纹丝不动(差量施加, 不是每帧再加一遍)",
		absf(float(u["maxHp"]) - mh) < 0.51, "maxHp %.0f → %.0f" % [mh, float(u["maxHp"])])
	## 多件同带取更高星
	_s._units.clear()
	var um: Dictionary = _mk("cyber", "left", Vector2(-200.0, 0.0), 3000.0)
	var h0m: float = float(um["maxHp"])
	um["equips"] = [{"id": "p2eq_084", "star": 1}, {"id": "p2eq_084", "star": 3}]
	um["eq_state"] = {}
	_spawn_all()
	_ok("④ ★带两把 084(1★+3★): 按 3★ 给一份, 不是两份相加",
		absf(float(um["maxHp"]) - h0m - float(EqBladeBatch.HH_RANGED_HP[2]) * 1.70) < 1.51,
		"maxHp+%.0f" % (float(um["maxHp"]) - h0m))


# ═════════════════════════════════════════════════════════════
# ⑤ 演出层: 可验证的模型性质 + 零素材 + 撤场
# ═════════════════════════════════════════════════════════════

## ★★十字斩**指得出方向**(2026-08-09 补上一直挂着的缺口)。
## 旧注释白纸黑字写着「`_dir` 没被用上 —— 弧是 billboard, billboard 会吃掉 roll」。
## 解法不是放弃 billboard 的朝向, 而是自己算基: `face_basis(视轴, roll)`
## = 正对镜头(不会被 52° 俯视压扁) + 面内旋转(指得出方向)。
## ⚠ 与 094 闪电那条同族: billboard 的"完全对齐相机"**包含 roll**, 想自己控制 roll 就不能用它。
func _t_slash_direction() -> void:
	var BV := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")
	## ① 纯函数: 场地方向 → 屏幕内 roll。右 = 0; 左 = ±π; 上下互为反号。
	_ok("④D 向右劈 roll = 0", absf(BV.dir_to_roll(Vector2(1, 0))) < 1e-6,
		"%.4f" % BV.dir_to_roll(Vector2(1, 0)))
	_ok("④D 向左劈 roll = ±π", absf(absf(BV.dir_to_roll(Vector2(-1, 0))) - PI) < 1e-6,
		"%.4f" % BV.dir_to_roll(Vector2(-1, 0)))
	var up_r: float = BV.dir_to_roll(Vector2(0, -1))
	var dn_r: float = BV.dir_to_roll(Vector2(0, 1))
	_ok("④D 上下互为反号(不是同一个角)", up_r * dn_r < 0.0, "上 %.4f / 下 %.4f" % [up_r, dn_r])
	## ② ★2.5D 纵深压缩: 场地上的 45° 在屏幕上**不是** 45°(横向 0.6755 px/码、纵深 0.5267)。
	##    不压这一下斜着劈的刀会指偏 —— 这条就是守那个压缩系数真的被用上了。
	var d45: float = BV.dir_to_roll(Vector2(1, -1))
	_ok("④D ★场地 45° 在屏幕上被纵深压缩(≠ 45°, 且落在 0~45° 之间)",
		d45 > 0.01 and d45 < PI * 0.25 - 0.01, "%.4f 弧度 = %.2f°" % [d45, rad_to_deg(d45)])
	## ③ 量【真实节点】: 关掉了 billboard, 且 meta 上记的 roll 与方向一致
	var su: Dictionary = _mk("basic", "left", Vector2(0, 0))
	_s._units = [su]
	_blade().vfx.clear()
	_blade().vfx.cross_slash(su, Vector2(-1, 0), 1)
	var sn: Sprite3D = null
	for x in _blade().vfx._owned:
		if is_instance_valid(x) and x is Sprite3D and (x as Node).has_meta("slash_roll"):
			sn = x as Sprite3D
			break
	_ok("④D 分母: 拿到十字斩的弧节点", sn != null)
	if sn != null:
		_ok("④D ★★必须关掉 billboard(开着就吃掉 roll, 方向永远指不出来)",
			sn.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "billboard=%d" % int(sn.billboard))
		_ok("④D 节点记的 roll 与方向算出来的一致",
			absf(float(sn.get_meta("slash_roll", 0.0)) - BV.dir_to_roll(Vector2(-1, 0))) < 1e-6)
	_blade().vfx.clear()
	_s._units.clear()


func _t_vfx() -> void:
	print("── ⑤ 演出层 BladeEqVfx: 模型性质 / 零素材 / 撤场 ──")
	## ① 081 临界阻尼(ζ=1): x̂(0)=0 · 单调 · 恒 < 1(永不过冲) · x̂(1/ω)=1−2/e
	var w: float = 11.0
	_ok("⑤① 举盾开合 x̂(0) = 0", absf(BladeEqVfx.guard_open(w, 0.0)) < 1e-12)
	_ok("⑤① 举盾开合 x̂(1/ω) = 1 − 2/e = 0.2642411(ζ=1 的解析解)",
		absf(BladeEqVfx.guard_open(w, 1.0 / w) - 0.264241117657) < 1e-9,
		"实得 %.12f" % BladeEqVfx.guard_open(w, 1.0 / w))
	var mono := true
	var over := false
	var prev := -1.0
	for i in range(400):
		var v: float = BladeEqVfx.guard_open(w, float(i) * 0.01)
		if v < prev - 1e-12:
			mono = false
		if v > 1.0:
			over = true
		prev = v
	_ok("⑤① 举盾开合严格单调增 且 **永不过冲**(欠阻尼 ζ<1 会 >1, 一测就分开)",
		mono and not over, "单调=%s 过冲=%s (采样 400 点)" % [str(mono), str(over)])
	## ② 082 平方反比: I(d₀)/I(0) ≡ 0.5, 与 d₀ 无关
	var ratios: Array = []
	for d0 in [50.0, 220.0, 900.0]:
		ratios.append(BladeEqVfx.reflect_intensity(float(d0), float(d0)) / BladeEqVfx.reflect_intensity(0.0, float(d0)))
	var all_half := true
	for r in ratios:
		if absf(float(r) - 0.5) > 1e-12:
			all_half = false
	_ok("⑤② 反伤束亮度 I(d₀)/I(0) ≡ 0.5, 与 d₀ 无关(线性/指数衰减都给不出这个数)",
		all_half, str(ratios))
	## ③ 083 对数刻度: g(0)=0 · g(20)=1 · g(4) > 4/20(前段被拉开)
	_ok("⑤③ 层数辉光 g(0)=0 且 g(20)=1",
		absf(BladeEqVfx.stack_glow(0)) < 1e-12 and absf(BladeEqVfx.stack_glow(20) - 1.0) < 1e-12,
		"g(0)=%.6f g(20)=%.6f" % [BladeEqVfx.stack_glow(0), BladeEqVfx.stack_glow(20)])
	_ok("⑤③ g(4) > 0.2 = 线性刻度的值(低层区间被拉开, 1→2 层看得出来)",
		BladeEqVfx.stack_glow(4) > 0.2 + 1e-6, "g(4)=%.6f 线性 0.200000" % BladeEqVfx.stack_glow(4))
	## ④ 084 剑波匀速: 位移 ∝ t, 且演出与结算共用 WAVE_SPD
	var p1: Vector2 = BladeEqVfx.wave_pos(Vector2.ZERO, Vector2.RIGHT, 0.2)
	var p2: Vector2 = BladeEqVfx.wave_pos(Vector2.ZERO, Vector2.RIGHT, 0.4)
	_ok("⑤④ 剑波匀速直线: t 翻倍位移就翻倍(0.2s→%.0f 码, 0.4s→%.0f 码)" % [p1.x, p2.x],
		absf(p2.x - 2.0 * p1.x) < 1e-6 and absf(p1.x - 180.0) < 1e-6)
	## ★零素材: 贴图是程序化现算的(resource_path 空串 = 不是从磁盘 load 的资源)
	var texs: Array = [VfxTex._make_disc_texture(), VfxTex._make_thin_ring_tex(),
		VfxTex._make_slash_texture(Color.WHITE), VfxTex._make_wave_texture(Color.WHITE),
		VfxTex._make_laser_beam_tex(Color.WHITE)]
	var loaded: Array = []
	for t in texs:
		if str((t as Texture2D).resource_path) != "":
			loaded.append(str((t as Texture2D).resource_path))
	_ok("⑤ ★零素材: 演出用的 5 张贴图全是 VfxTex 现算的(resource_path 都是空串)",
		loaded.is_empty(), "从磁盘来的: %s" % str(loaded))
	_ok("⑤ ★分母: 一共查了 %d 张贴图" % texs.size(), texs.size() == 5)
	## 撤场: 建了节点 → clear() 后归零
	_s._units.clear()
	_blade().clear_all()          # 先归零, 免得前面几组留下的盾面混进计数
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0), 10000.0)
	var atk: Dictionary = _mk("fortune", "right", Vector2(200.0, 0.0))
	_equip(u, "p2eq_081", 3)
	_spawn_all()
	_ok("⑤ ★分母: clear_all() 之后演出层确实是空的(0 节点 0 常驻盾)",
		_blade().vfx.owned_count() == 0 and _blade().vfx.guard_count() == 0,
		"owned=%d guards=%d" % [_blade().vfx.owned_count(), _blade().vfx.guard_count()])
	_hit(atk, u, 3000)
	var built: int = _blade().vfx.owned_count()
	_ok("⑤ ★分母: 举盾真的建出了演出节点(不是「函数存在但没人调」)", built > 0, "节点数=%d" % built)
	_ok("⑤ 举盾期有一面常驻盾(guard_count = 1)", _blade().vfx.guard_count() == 1,
		"guards=%d" % _blade().vfx.guard_count())
	_blade().clear_all()
	_ok("⑤ ★换路撤场 clear_all() 后演出节点与常驻盾全部归零(漏了就带进下一路)",
		_blade().vfx.owned_count() == 0 and _blade().vfx.guard_count() == 0
			and _blade().b84_waves() == 0 and _blade().b84_pending() == 0,
		"owned=%d guards=%d waves=%d pending=%d" % [_blade().vfx.owned_count(),
			_blade().vfx.guard_count(), _blade().b84_waves(), _blade().b84_pending()])
