extends Node
## verify_eq_bow_batch.gd — 弓箭 4 件(073/074/075/076)逐件焊死 + 演出物理模型门禁
##
## 规格: docs/plans/20260805-装备逐件重做.md §0.5【用户逐件亲手写的定稿】
## 实装: scripts/systems/equip/eq_bow_batch.gd  ·  演出: scripts/scenes/battle/bow_eq_vfx.gd
##
## ★本文件的规矩(契约 §7, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。
##   · 合成单位坐标放 ARENA 【内】—— 放外面会被钳到同一点(500 帧红 1500 帧绿那次)。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##     (唯一例外是"两个常量必须相等"这类**同一性**断言, 那本来就要读两边。)
##   · 触发一律走【真入口】(_eq_on_basic_attack / _eq_on_hit / _eq_on_cast / fire_equip_effect),
##     并且至少各有一条【经中央伤害管线 _apply_damage_from 的端到端】断言 ——
##     memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」。
##   · 概率/分布类【播种 RNG】测经验频率, 不靠"跑几次看看"(CI 必然偶发红)。
##   · **不依赖任何演出 tween / 弹道飞完**(CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##     箭雨与连射的推进全靠同步喂 `tick(delta)`。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##   · 美术断言查**真的显示进 `_world`** 且**量真实节点**(不是把公式在测试里抄一遍 ——
##     memory [[fb-write-without-reader-and-fake-gates]]: 抄公式的门禁, 产品改成写死也照样绿)。
##
## 跑法: <godot> --headless --path . res://tests/verify_eq_bow_batch.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null

const SEED := 20260806
const TRIALS := 1200
const RAY_N := 4000


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位。★携带者一律 `fortune` 不用 `basic`:
##   小龟·不屈会给小龟造成的一切伤害 +20%, 拿 basic 当携带者验"22 点加成"会量到 26。
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
	u["armor_pen_pct"] = 0.0
	u["magic_pen_pct"] = 0.0
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["corrode_stacks"] = 0
	u["corrode_tier"] = 0
	u["aspd_perm"] = 1.0
	u["dots"] = []
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 流血层数存在 `u["dot_stacks"]["bleed"]`(层数式 DoT), 不在 `u["dots"]`
## (后者是诅咒/这类按秒的 DoT)。两者是两套机制, 别搞反。
func _bleed(u: Dictionary) -> int:
	return int((u.get("dot_stacks", {}) as Dictionary).get("bleed", 0))


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
	print("=== 弓箭 4 件(073 藤蔓弓弦 / 074 鲸骨胸甲 / 075 银色箭袋 / 076 连发弩机) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	_t_dispatch()
	_t_stats()
	_t073_vine_bow()
	_t073_aspd()
	_t073_random_and_nochain()
	_t074_bone_cuirass()
	_t075_amp()
	_t075_rain()
	_t076_passive()
	_t076_volley()
	_t076_steal()
	_t_vfx_physics()
	_t_vfx_nodes()
	_t_readouts_fixture()

	_s._equip_sys._bow_sys.clear()
	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 弓箭 4 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════
# ⓪ 分发纪律与接线 —— 四件各自落在【已有的】钩子上, 没有新增分发口
# ═════════════════════════════════════════════════════════════
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	## ★先剥注释再找分派 —— 否则会命中我自己写的说明文字(前几份门禁的作者都吃过这个亏)
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	var groups := {
		"func _eq_on_basic_attack": ["p2eq_073", "p2eq_074", "p2eq_076"],
		"func _eq_on_hit": ["p2eq_075"],
		"func _eq_on_cast": ["p2eq_076"],
		"func fire_equip_effect": ["p2eq_075"],
	}
	var total := 0
	for hdr in groups:
		var body: String = _fn_body(code, str(hdr))
		_ok("⓪ ★分母: %s 的函数体非空(空串会让下面那条恒真)" % str(hdr),
			body.length() > 200, "len=%d" % body.length())
		var miss: Array = []
		for iid in groups[hdr]:
			total += 1
			if not body.contains("\"%s\": _bow_sys." % iid):
				miss.append(iid)
		_ok("⓪ %s 里 %s 分派到 _bow_sys" % [str(hdr), str(groups[hdr])], miss.is_empty(), "缺 %s" % str(miss))
	_ok("⓪ ★分母: 一共查了 %d 个分派点(应为 6)" % total, total == 6, "total=%d" % total)
	## ★★接线一: EquipSystem 真的 new 了 EqBowBatch(不是"文件存在但没人用")
	_ok("⓪ ★★接线: battle._equip_sys._bow_sys 真的存在",
		_s._equip_sys._bow_sys != null and _s._equip_sys._bow_sys is EqBowBatch,
		str(_s._equip_sys._bow_sys))
	_ok("⓪ ★★接线: 它自己也真的 new 了演出层 BowEqVfx",
		_s._equip_sys._bow_sys._vfx != null and _s._equip_sys._bow_sys._vfx is BowEqVfx)
	## ★★接线二: 每帧节拍真的被 _eq_tick 调(箭雨/连射全靠它推进; 不接线就是"排了永远不发")
	_ok("⓪ ★★接线: _eq_tick 里真的调 _bow_sys.tick(delta)",
		code.contains("_bow_sys.tick(delta)"))
	## ★★接线三: 075 的 6 秒周期真的在周期表里
	_ok("⓪ 075 的周期是 6.0 秒(用户原文「每 6 秒」)",
		absf(float(EquipSystem.EQ_IV_BATCH1.get("p2eq_075", 0.0)) - 6.0) < 0.0001,
		"iv=%s" % str(EquipSystem.EQ_IV_BATCH1.get("p2eq_075", 0.0)))
	_ok("⓪ 073/076 【不】排周期(它们要比 0.25 秒更细的精度, 走每帧 tick)",
		not EquipSystem.EQ_IV_BATCH1.has("p2eq_073") and not EquipSystem.EQ_IV_BATCH1.has("p2eq_076"))
	## ★旧效果函数必须【彻底消失】—— 只删分派不删函数 = 死代码被"断言函数存在"型门禁保护着
	##   (memory [[fb-verify-must-run-the-real-path]])
	var raw: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var ghosts: Array = []
	for fn in ["func _eq_vine_bow", "func _eq_bone_quiver", "func _eq_eagle_lens", "func _eq_corroder"]:
		if raw.contains(fn):
			ghosts.append(fn)
	_ok("⓪ ★旧的四个 AI 编的效果函数已彻底删除(不是只删分派留死代码)",
		ghosts.is_empty(), str(ghosts))
	## ★演出与效果的节拍是【同一个数】: 076 每 0.15 秒一发, 反冲振子也按 0.15 秒排
	##   (2026-08-12 用户把 0.25 改成 0.15 —— 改一处两处都得动, 这条就是防漏改的)
	_ok("⓪ ★连射节拍与反冲节拍焊死相等(0.15 秒)",
		absf(EqBowBatch.VOLLEY_IV - BowEqVfx.RECOIL_IV) < 1e-9
			and absf(EqBowBatch.VOLLEY_IV - 0.15) < 1e-9,
		"volley=%.4f recoil=%.4f" % [EqBowBatch.VOLLEY_IV, BowEqVfx.RECOIL_IV])


# ═════════════════════════════════════════════════════════════
# ⓪b 属性(equip_stats.STATS) —— 逐星硬写, 不读被测表
# ═════════════════════════════════════════════════════════════
func _t_stats() -> void:
	print("── ⓪b 四件的逐星属性 ──")
	var ES := preload("res://scripts/gamedata/equip_stats.gd")
	var want := {
		"p2eq_073": [{"crit": 0.10, "_rangeAdd": 50}, {"crit": 0.18, "_rangeAdd": 70}, {"crit": 0.30, "_rangeAdd": 100}],
		"p2eq_074": [{"hp": 50, "_aspdPct": 6}, {"hp": 120, "_aspdPct": 11}, {"hp": 260, "_aspdPct": 18}],
		"p2eq_075": [{"atk": 12, "_rangeAdd": 40}, {"atk": 30, "_rangeAdd": 60}, {"atk": 68, "_rangeAdd": 90}],
		"p2eq_076": [{"atk": 20, "_lifestealPct": 6, "critDmg": 0.15}, {"atk": 50, "_lifestealPct": 11, "critDmg": 0.28}, {"atk": 115, "_lifestealPct": 18, "critDmg": 0.50}],
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
	_ok("⓪b ★分母: 一共核了 %d 个属性字段(073/074/075 各 2×3 + 076 3×3 = 27)" % checked, checked == 27, "checked=%d" % checked)
	## ★射程走 flat 通道并真的进 _eff_range(先加后乘) —— 光写进 STATS 没人读就是白写
	_s._units.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, -400.0))
	var base_rng: float = _s._eff_range(u)
	_s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_073", 3)
	_ok("⓪b ★073 3★ 的 +100 码射程真的进了 _eff_range(flat, 先加后乘)",
		absf(_s._eff_range(u) - (base_rng + 100.0)) < 0.51,
		"%.1f → %.1f (期望 +100)" % [base_rng, _s._eff_range(u)])
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ① 073 藤蔓弓弦 · 藤蔓箭伤害
#    「每次普攻时小球向随机目标射藤蔓箭, 20/30/45% ATK 物理;
#      可单独暴击, 暴击转真实伤害」
# ═════════════════════════════════════════════════════════════
func _t073_vine_bow() -> void:
	print("── ① 073 藤蔓弓弦 · 藤蔓箭 ──")
	for si in range(3):
		var pct: float = [0.20, 0.30, 0.45][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -300.0)), "p2eq_073", si + 1)
		u["atk"] = 200.0
		u["base_atk"] = 200.0
		u["crit"] = 0.0                                  # 必不暴 ⇒ 走物理段
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, -300.0))
		var h0: float = float(t["hp"])
		_s._equip_sys._eq_on_basic_attack(u, t)          # ★真入口
		var want: float = 200.0 * pct
		_ok("① 073 si=%d 非暴击 → %.0f 物理(ATK 200 × 20/30/45%%, 护甲 0)" % [si, want],
			absf(h0 - float(t["hp"]) - want) < 0.51, "实掉 %.1f" % (h0 - float(t["hp"])))
		_ok("① 073 si=%d ★分母: eq_state 记到这一发(vine_shots=1)" % si,
			int((u["eq_state"].get("p2eq_073", {}) as Dictionary).get("vine_shots", 0)) == 1,
			"shots=%d" % int((u["eq_state"].get("p2eq_073", {}) as Dictionary).get("vine_shots", 0)))
	## ★暴击段: 暴击率 100% ⇒ 必暴 ⇒ 转【真实伤害】且吃全局暴伤倍率(1.5)
	for si2 in range(3):
		var pct2: float = [0.20, 0.30, 0.45][si2]
		_s._units.clear()
		var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -260.0)), "p2eq_073", si2 + 1)
		c["atk"] = 200.0
		c["base_atk"] = 200.0
		c["crit"] = 1.0
		c["crit_dmg"] = 1.5
		var ct: Dictionary = _mk("basic", "right", Vector2(-100.0, -260.0))
		ct["def"] = 200.0                                # ★护甲拉满: 真伤应当【完全无视】它
		ct["base_def"] = 200.0
		var c0: float = float(ct["hp"])
		_s._equip_sys._eq_on_basic_attack(c, ct)
		var wc: float = 200.0 * pct2 * 1.5
		_ok("① 073 si=%d 暴击 → %.0f 真实伤害(转真伤: 目标 200 护甲一点没减)" % [si2, wc],
			absf(c0 - float(ct["hp"]) - wc) < 0.51,
			"实掉 %.1f 期望 %.0f" % [c0 - float(ct["hp"]), wc])
	## ★分母(反向): 同样 200 护甲、同样星级, 不暴击时【应该】被护甲砍掉一大截 ——
	##   证明上一条的"没减"不是因为这条路径本来就不吃护甲
	_s._units.clear()
	var n1: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -220.0)), "p2eq_073", 3)
	n1["atk"] = 200.0
	n1["base_atk"] = 200.0
	n1["crit"] = 0.0
	var nt: Dictionary = _mk("basic", "right", Vector2(-100.0, -220.0))
	nt["def"] = 200.0
	nt["base_def"] = 200.0
	var n0: float = float(nt["hp"])
	_s._equip_sys._eq_on_basic_attack(n1, nt)
	## 减伤曲线 1 − r/(r+40): 200 护甲 ⇒ ×0.16667 ⇒ 90 × 0.16667 = 15
	_ok("① 073 ★分母: 不暴击时护甲【真的在减】(90 打成 15, 减伤曲线 40/(200+40))",
		absf(n0 - float(nt["hp"]) - 15.0) < 0.51, "实掉 %.1f 期望 15" % (n0 - float(nt["hp"])))
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ①b 073 的攻速 buff: 2 秒 20/25/30%, **刷新不叠加**
# ═════════════════════════════════════════════════════════════
func _t073_aspd() -> void:
	print("── ①b 073 · 暴击给 2 秒攻速(刷新不叠加) ──")
	var tsave: float = _s._t
	for si in range(3):
		var pct: float = [0.20, 0.25, 0.30][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -180.0)), "p2eq_073", si + 1)
		u["atk"] = 100.0
		u["base_atk"] = 100.0
		u["crit"] = 1.0
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, -180.0))
		_ok("①b si=%d ★分母: 起手 aspd_perm = 1.000" % si,
			absf(float(u.get("aspd_perm", 1.0)) - 1.0) < 0.0001, "%.4f" % float(u.get("aspd_perm", 1.0)))
		_s._equip_sys._eq_on_basic_attack(u, t)
		_ok("①b si=%d 一次暴击 → aspd_perm = %.2f(+20/25/30%%)" % [si, 1.0 + pct],
			absf(float(u["aspd_perm"]) - (1.0 + pct)) < 0.0005,
			"实测 %.4f" % float(u["aspd_perm"]))
		## ★刷新不叠加: 再暴 5 次, 倍率一动不动, 只有到期时刻往后推
		var st0: Dictionary = u["eq_state"]["p2eq_073"]
		var until0: float = float(st0["vine_aspd_until"])
		_s._t += 1.0
		for _k in range(5):
			_s._equip_sys._eq_on_basic_attack(u, t)
		_ok("①b si=%d ★刷新【不叠加】: 再暴 5 次仍是 %.2f(叠加的话会到 %.2f)" % [si, 1.0 + pct, 1.0 + pct * 6.0],
			absf(float(u["aspd_perm"]) - (1.0 + pct)) < 0.0005,
			"实测 %.4f" % float(u["aspd_perm"]))
		var until1: float = float((u["eq_state"]["p2eq_073"] as Dictionary)["vine_aspd_until"])
		_ok("①b si=%d ★但到期时刻【真的往后推了】1 秒(是刷新不是无视)" % si,
			absf(until1 - until0 - 1.0) < 0.02, "Δ=%.3f" % (until1 - until0))
		## ★到期回收: 时钟推过 2 秒后喂一帧 tick, 增量原样还回去
		_s._t = until1 + 0.01
		_s._equip_sys._bow_sys.tick(0.016)
		_ok("①b si=%d ★2 秒到期 → aspd_perm 回到 1.000(把自己那份收回, 不是设回 1)" % si,
			absf(float(u["aspd_perm"]) - 1.0) < 0.0005, "实测 %.4f" % float(u["aspd_perm"]))
	## ★不吞别人的加成: 别的来源先给 +50%, 我上 30% 再到期, 应剩 1.50 不是 1.00
	_s._units.clear()
	_s._t = tsave
	var m: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -140.0)), "p2eq_073", 3)
	m["atk"] = 100.0
	m["base_atk"] = 100.0
	m["crit"] = 1.0
	m["aspd_perm"] = 1.50                                # 贝母021 / 枪羁绊等别的来源
	var mt: Dictionary = _mk("basic", "right", Vector2(-100.0, -140.0))
	_s._equip_sys._eq_on_basic_attack(m, mt)
	_ok("①b ★共存: 别人给的 1.50 上叠我的 30% = 1.80(加算通道, 不覆盖)",
		absf(float(m["aspd_perm"]) - 1.80) < 0.0005, "实测 %.4f" % float(m["aspd_perm"]))
	_s._t = float((m["eq_state"]["p2eq_073"] as Dictionary)["vine_aspd_until"]) + 0.01
	_s._equip_sys._bow_sys.tick(0.016)
	_ok("①b ★到期只收回【自己那 0.30】, 别人的 1.50 原样留着",
		absf(float(m["aspd_perm"]) - 1.50) < 0.0005, "实测 %.4f" % float(m["aspd_perm"]))
	_s._t = tsave
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ①c 073 的【随机目标】走已播种 RNG + 【不触发 on-hit】
# ═════════════════════════════════════════════════════════════
func _t073_random_and_nochain() -> void:
	print("── ①c 073 · 随机目标(播种 RNG) + 不触发 on-hit ──")
	## ★三个敌人, 播种后统计各自被打到的频率 —— 期望各 1/3
	_s._units.clear()
	var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -100.0)), "p2eq_073", 3)
	u["atk"] = 100.0
	u["base_atk"] = 100.0
	u["crit"] = 0.0
	var es: Array = []
	for k in range(3):
		es.append(_mk("basic", "right", Vector2(-100.0 + 80.0 * float(k), -100.0), 1.0e9))
	_s._battle_rng.seed = SEED
	var hp0: Array = []
	for o in es:
		hp0.append(float(o["hp"]))
	for _i in range(TRIALS):
		_s._equip_sys._eq_on_basic_attack(u, es[0])
	var hits: Array = []
	var tot := 0
	for k in range(3):
		var got: int = int(round((hp0[k] - float(es[k]["hp"])) / 45.0))   # 每发 45(100×0.45)
		hits.append(got)
		tot += got
	_ok("①c ★分母: %d 发全部落在这三个敌人身上(合计 %d)" % [TRIALS, tot], tot == TRIALS,
		"tot=%d 分布=%s" % [tot, str(hits)])
	var worst := 0.0
	for k in range(3):
		worst = maxf(worst, absf(float(hits[k]) / float(TRIALS) - 1.0 / 3.0))
	_ok("①c 随机目标三选一大致均匀(播种 RNG · %d 发, 最大偏差 %.3f < 0.05)" % [TRIALS, worst],
		worst < 0.05, "分布=%s" % str(hits))
	## ★同一个种子跑两遍, 分布【逐个相等】—— 这才是"走了受控 RNG"的判据
	##   (裸 randi() 每次不同, 会直接把 verify_battle_determinism 打红)
	var runs: Array = []
	for r in range(2):
		_s._units.clear()
		var u2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -60.0)), "p2eq_073", 3)
		u2["atk"] = 100.0
		u2["base_atk"] = 100.0
		u2["crit"] = 0.0
		var e2: Array = []
		for k2 in range(3):
			e2.append(_mk("basic", "right", Vector2(-100.0 + 80.0 * float(k2), -60.0), 1.0e9))
		_s._battle_rng.seed = SEED
		var seq: Array = []
		for _i2 in range(60):
			var before: Array = []
			for o2 in e2:
				before.append(float(o2["hp"]))
			_s._equip_sys._eq_on_basic_attack(u2, e2[0])
			for k3 in range(3):
				if float(e2[k3]["hp"]) < before[k3]:
					seq.append(k3)
					break
		runs.append(seq)
	_ok("①c ★★同种子两遍的命中序列【逐个相同】(60 发) = 真的走了 _battle_rng",
		runs[0] == runs[1] and (runs[0] as Array).size() == 60,
		"len=%d/%d" % [(runs[0] as Array).size(), (runs[1] as Array).size()])
	## ★不触发 on-hit 的探针 —— 2026-08-06 换掉了原来的做法。
	##   原来拿【083 潮汐细剑每次 on-hit 必叠一层】当同步探针, 但 083 已被用户整条重做
	##   (批④·EqBladeBatch), 旧的 `tide_layers` 字段随之消失 ⇒ 探针恒为 0, 那条分母直接红。
	##   ★换成 `_eq_on_hit` 自己的入口标记 `_onhit_fr`: 函数一进来就无条件写当前帧号
	##   (见 EquipSystem._eq_on_hit 开头的 AoE 判定)。**它不依赖任何一件装备** ——
	##   以后谁被重做都不会再把这个探针弄坏, 而且它量的正是"这个钩子到底进没进"。
	_s._units.clear()
	var w: Dictionary = _mk("fortune", "left", Vector2(-300.0, -20.0))
	w["equips"] = [{"id": "p2eq_073", "star": 3}]
	w["eq_state"] = {}
	w["atk"] = 100.0
	w["base_atk"] = 100.0
	w["crit"] = 0.0
	var wt: Dictionary = _mk("basic", "right", Vector2(-100.0, -20.0), 1.0e9)
	w["_onhit_fr"] = -999   # 先抹掉标记, 免得读到本帧更早的别的 on-hit
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_ok("①c ★★藤蔓箭【不触发 on-hit】(_eq_on_hit 的入口标记没被写)",
		int(w.get("_onhit_fr", -999)) == -999, "_onhit_fr=%d" % int(w.get("_onhit_fr", -999)))
	## ★分母: 同一对单位走【正常伤害路】必须真的进 on-hit —— 证明探针有效, 不是空检查
	w["_onhit_fr"] = -999
	_s._damage._apply_damage_from(w, wt, 100, Color("#ffffff"))
	_ok("①c ★★分母: 同一对单位走正常伤害路 → _eq_on_hit 确实进了(探针有效)",
		int(w.get("_onhit_fr", -999)) == Engine.get_process_frames(),
		"_onhit_fr=%d 当前帧=%d" % [int(w.get("_onhit_fr", -999)), Engine.get_process_frames()])
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ② 074 鲸骨胸甲 「每次普攻 +2/3/4% 最大生命护盾 + 10/20/30 魔法伤害」
# ═════════════════════════════════════════════════════════════
func _t074_bone_cuirass() -> void:
	print("── ② 074 鲸骨胸甲 · 普攻叠盾 + 附带魔伤 ──")
	for si in range(3):
		var pct: float = [0.02, 0.03, 0.04][si]
		var flat: float = [10.0, 20.0, 30.0][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 20.0), 5000.0), "p2eq_074", si + 1)
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 20.0))
		var h0: float = float(t["hp"])
		_s._equip_sys._eq_on_basic_attack(u, t)          # ★真入口
		_ok("② 074 si=%d 护盾 = %.0f(最大生命 5000 的 2/3/4%%)" % [si, 5000.0 * pct],
			absf(float(u["shield"]) - 5000.0 * pct) < 0.51, "shield=%.1f" % float(u["shield"]))
		_ok("② 074 si=%d 附带 %.0f 魔法伤害(魔抗 0)" % [si, flat],
			absf(h0 - float(t["hp"]) - flat) < 0.51, "实掉 %.1f" % (h0 - float(t["hp"])))
	## ★魔抗真的在吃这段(证明它是【魔法】伤害不是真伤): 40 魔抗 ⇒ ×0.5 ⇒ 30 打成 15
	_s._units.clear()
	var m: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 60.0), 5000.0), "p2eq_074", 3)
	var mt: Dictionary = _mk("basic", "right", Vector2(-100.0, 60.0))
	mt["mr"] = 40.0
	mt["base_mr"] = 40.0
	var m0: float = float(mt["hp"])
	_s._equip_sys._eq_on_basic_attack(m, mt)
	_ok("② 074 ★是【魔法】伤害不是真伤(40 魔抗 ⇒ 30 打成 15)",
		absf(m0 - float(mt["hp"]) - 15.0) < 0.51, "实掉 %.1f 期望 15" % (m0 - float(mt["hp"])))
	## ★★【无上限】: 全局护盾上限 2026-08-05 已删除 ⇒ 灌 60 下普攻 = 240% 最大生命
	##   旧的 SHIELD_CAP_MULT=1.5 会把它砍在 150% —— 这条断言就是那个上限的墓碑。
	_s._units.clear()
	var g: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 100.0), 5000.0), "p2eq_074", 3)
	var gt: Dictionary = _mk("basic", "right", Vector2(-100.0, 100.0))
	for _k in range(60):
		_s._equip_sys._eq_on_basic_attack(g, gt)
	_ok("② 074 ★★护盾【没有上限】: 60 下普攻 = 5000×4%×60 = 12000(旧上限会砍到 7500)",
		absf(float(g["shield"]) - 12000.0) < 0.51, "shield=%.1f" % float(g["shield"]))
	_ok("② 074 ★分母: 12000 确实超过了最大生命的 150%(7500) —— 这条断言不是恒真",
		float(g["shield"]) > float(g["maxHp"]) * 1.5,
		"shield=%.0f  1.5×maxHp=%.0f" % [float(g["shield"]), float(g["maxHp"]) * 1.5])
	_ok("② 074 ★分母: eq_state 记了 60 层(演出的甲片数就读它)",
		int((g["eq_state"].get("p2eq_074", {}) as Dictionary).get("bone_layers", 0)) == 60,
		"layers=%d" % int((g["eq_state"].get("p2eq_074", {}) as Dictionary).get("bone_layers", 0)))
	## ★附带魔伤【不触发 on-hit】—— 同上, 探针换成 `_eq_on_hit` 的入口标记 `_onhit_fr`
	##   (原来靠 083 叠层, 083 已被重做)。分母在 ①c 那段已经证明过探针有效。
	_s._units.clear()
	var w: Dictionary = _mk("fortune", "left", Vector2(-300.0, 140.0), 5000.0)
	w["equips"] = [{"id": "p2eq_074", "star": 3}]
	w["eq_state"] = {}
	var wt: Dictionary = _mk("basic", "right", Vector2(-100.0, 140.0))
	w["_onhit_fr"] = -999
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_ok("② 074 ★★附带魔伤【不触发 on-hit】(入口标记没被写)",
		int(w.get("_onhit_fr", -999)) == -999, "_onhit_fr=%d" % int(w.get("_onhit_fr", -999)))
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ③ 075 的被动增伤: 每距 100 码 +3/4/5%, 不封顶
# ═════════════════════════════════════════════════════════════
func _t075_amp() -> void:
	print("── ③ 075 银色箭袋 · 距离增伤(不封顶) ──")
	for si in range(3):
		var per: float = [0.03, 0.04, 0.05][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, 180.0)), "p2eq_075", si + 1)
		## 400 码 → +12/16/20%
		var t4: Dictionary = _mk("basic", "right", Vector2(-100.0, 180.0))
		var h0: float = float(t4["hp"])
		_s._equip_sys._eq_on_hit(u, t4, 1000)            # ★真入口
		var w4: float = round(1000.0 * per * 4.0)
		_ok("③ 075 si=%d 400 码 → 额外 %.0f(每 100 码 +3/4/5%%)" % [si, w4],
			absf(h0 - float(t4["hp"]) - w4) < 0.51, "实掉 %.1f 期望 %.0f" % [h0 - float(t4["hp"]), w4])
		## 贴脸 → 一点不加
		var t0: Dictionary = _mk("basic", "right", Vector2(-500.0, 180.0))
		var z0: float = float(t0["hp"])
		_s._equip_sys._eq_on_hit(u, t0, 1000)
		_ok("③ 075 si=%d ★分母: 贴脸(0 码) → 一点加伤都没有" % si,
			absf(z0 - float(t0["hp"])) < 0.01, "贴脸掉 %.1f" % (z0 - float(t0["hp"])))
		## 1600 码 → +48/64/80%, **不封顶**(旧版封在 +10/18/28%)
		var tf: Dictionary = _mk("basic", "right", Vector2(0.0, 180.0))
		tf["pos"] = (u["pos"] as Vector2) + Vector2(1600.0, 0.0)
		var c0: float = float(tf["hp"])
		_s._equip_sys._eq_on_hit(u, tf, 1000)
		var wf: float = round(1000.0 * per * 16.0)
		_ok("③ 075 si=%d ★不封顶: 1600 码 → 额外 %.0f(旧版会封在 100~280)" % [si, wf],
			absf(c0 - float(tf["hp"]) - wf) < 0.51, "实掉 %.1f 期望 %.0f" % [c0 - float(tf["hp"]), wf])
	## ★★端到端: 经中央伤害管线打 1000, 距离 400, 3★ ⇒ 目标共掉 1200
	_s._units.clear()
	var e2e: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, 220.0)), "p2eq_075", 3)
	var tgt: Dictionary = _mk("basic", "right", Vector2(-100.0, 220.0))
	var t0b: float = float(tgt["hp"])
	_s._damage._apply_damage_from(e2e, tgt, 1000, Color("#ffffff"))
	_ok("③ 075 ★★端到端: 经 _apply_damage_from 打 1000(400 码) → 实掉 1200",
		absf(t0b - float(tgt["hp"]) - 1200.0) < 0.51, "实掉 %.1f" % (t0b - float(tgt["hp"])))
	var bare: Dictionary = _mk("fortune", "left", Vector2(-500.0, 260.0))
	var t1: float = float(tgt["hp"])
	_s._damage._apply_damage_from(bare, tgt, 1000, Color("#ffffff"))
	_ok("③ 075 ★分母: 不带装备的同一发只掉 1000(证明那 200 是 075 加的)",
		absf(t1 - float(tgt["hp"]) - 1000.0) < 0.51, "实掉 %.1f" % (t1 - float(tgt["hp"])))
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ③b 075 的箭雨: 每 6 秒 / 半径 400 / 6 跳 / 每跳 ATK×0.25/0.35/0.5 + 3/4/5 层流血
# ═════════════════════════════════════════════════════════════
func _t075_rain() -> void:
	print("── ③b 075 · 箭雨(最密集处 · 半径 400 · 6 跳) ──")
	for si in range(3):
		var per: float = [0.25, 0.35, 0.5][si]
		var stk: int = [3, 4, 5][si]
		_s._units.clear()
		_s._equip_sys._bow_sys.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-600.0, 300.0)), "p2eq_075", si + 1)
		u["atk"] = 400.0
		u["base_atk"] = 400.0
		## 敌人贴在一起, 落点就是它们中间 ⇒ 携带者到落点 500 码 ⇒ 增伤 +15/20/25%
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 300.0))
		var h0: float = float(t["hp"])
		var n: int = _s._equip_sys._bow_sys.rain_hop(u, si, t["pos"])
		var amp: float = 1.0 + 500.0 / 100.0 * [0.03, 0.04, 0.05][si]
		var want: float = round(400.0 * per * amp)
		_ok("③b si=%d 一跳 = %.0f 物理(ATK 400 × 0.25/0.35/0.5, 已含 500 码的 +15/20/25%% 增伤)" % [si, want],
			absf(h0 - float(t["hp"]) - want) < 0.51, "实掉 %.1f 期望 %.0f" % [h0 - float(t["hp"]), want])
		_ok("③b si=%d 一跳施加 %d 层流血(需求 3/4/5)" % [si, stk],
			_bleed(t) == stk, "stacks=%d" % _bleed(t))
		_ok("③b si=%d ★分母: 这一跳确实命中了 1 个敌人" % si, n == 1, "n=%d" % n)
	## ★半径 400: 401 码外的完全不吃
	_s._units.clear()
	var r: Dictionary = _equip(_mk("fortune", "left", Vector2(-600.0, 340.0)), "p2eq_075", 3)
	r["atk"] = 400.0
	r["base_atk"] = 400.0
	var inside: Dictionary = _mk("basic", "right", Vector2(-100.0, 340.0))
	var outside: Dictionary = _mk("basic", "right", Vector2(-100.0, 340.0))
	outside["pos"] = (inside["pos"] as Vector2) + Vector2(401.0, 0.0)
	var i0: float = float(inside["hp"])
	var o0: float = float(outside["hp"])
	var hits: int = _s._equip_sys._bow_sys.rain_hop(r, 2, inside["pos"])
	_ok("③b ★半径 400: 圈内那个吃到了", float(inside["hp"]) < i0 - 0.5, "掉 %.1f" % (i0 - float(inside["hp"])))
	_ok("③b ★半径 400: 401 码外那个一点没吃(边界是 400 不是随便一个数)",
		absf(o0 - float(outside["hp"])) < 0.01, "圈外掉 %.1f" % (o0 - float(outside["hp"])))
	_ok("③b ★分母: 这一跳命中数 = 1(不是 0 也不是 2)", hits == 1, "hits=%d" % hits)
	## ★落点取【敌人最密集处】: 4 个挤在一起 + 1 个远在天边 → 落点必须覆盖那 4 个
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var d: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, 380.0)), "p2eq_075", 3)
	d["atk"] = 400.0
	d["base_atk"] = 400.0
	var cluster: Array = []
	for k in range(4):
		cluster.append(_mk("basic", "right", Vector2(-100.0 + 60.0 * float(k), 380.0)))
	var lone: Dictionary = _mk("basic", "right", Vector2(600.0, 380.0))
	var before: Array = []
	for o in cluster:
		before.append(float(o["hp"]))
	var l0: float = float(lone["hp"])
	_s._equip_sys._bow_sys.rain_start(d, 2)              # ★真入口(会开一轮 6 跳的雨)
	_s._equip_sys._bow_sys.tick(0.001)                   # 第 1 跳(t_next 从 0 起算 ⇒ 立即)
	var got := 0
	for k2 in range(4):
		if float(cluster[k2]["hp"]) < before[k2] - 0.5:
			got += 1
	_ok("③b ★落点取【最密集处】: 挤在一起的 4 个全被覆盖(实测 %d/4)" % got, got == 4, "got=%d" % got)
	_ok("③b ★分母: 远在天边的那个没被覆盖(证明落点不是全场)",
		absf(l0 - float(lone["hp"])) < 0.01, "孤立那个掉 %.1f" % (l0 - float(lone["hp"])))
	## ★6 跳: 同步喂满 1.5 秒的 tick, 恰好 6 跳(不多不少) —— 全同步, 不等任何演出
	for _k in range(150):
		_s._equip_sys._bow_sys.tick(0.01)
	var hops: int = int((d["eq_state"].get("p2eq_075", {}) as Dictionary).get("rain_hops", 0))
	_ok("③b ★一轮箭雨【正好 6 跳】(1.5 秒 ÷ 0.25 秒)", hops == 6, "hops=%d" % hops)
	## 再喂 3 秒也不会多跳一次
	for _k2 in range(300):
		_s._equip_sys._bow_sys.tick(0.01)
	_ok("③b ★分母: 再喂 3 秒仍是 6 跳(雨真的停了, 不是无限下)",
		int((d["eq_state"].get("p2eq_075", {}) as Dictionary).get("rain_hops", 0)) == 6,
		"hops=%d" % int((d["eq_state"].get("p2eq_075", {}) as Dictionary).get("rain_hops", 0)))
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ④ 076 的被动: 每第三下普攻 +1 层腐蚀, **只在弓箭羁绊激活时**
# ═════════════════════════════════════════════════════════════
func _t076_passive() -> void:
	print("── ④ 076 连发弩机 · 被动(仅弓箭羁绊激活时) ──")
	var saved = _s._synergy._by_side
	## ★无羁绊: 打 30 下一层都不该叠
	_s._units.clear()
	_s._synergy._by_side = {"left": {}, "right": {}}
	var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 420.0)), "p2eq_076", 3)
	var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 420.0))
	for _k in range(30):
		_s._equip_sys._eq_on_basic_attack(u, t)
	_ok("④ 076 ★无弓箭羁绊 → 打 30 下一层腐蚀都不叠(用户明确拍板)",
		int(t.get("corrode_stacks", 0)) == 0, "stacks=%d" % int(t.get("corrode_stacks", 0)))
	## ★有羁绊: 第 3 下才叠第一层
	_s._units.clear()
	_s._synergy._by_side = {"left": {"弓箭": 2}, "right": {}}
	var w: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 460.0)), "p2eq_076", 3)
	var wt: Dictionary = _mk("basic", "right", Vector2(-100.0, 460.0))
	_ok("④ 076 ★分母: 弓箭羁绊 2 档已激活(不激活下面全是恒真)",
		int(_s._synergy.tier_for(w, "弓箭")) == 2, "tier=%d" % int(_s._synergy.tier_for(w, "弓箭")))
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_ok("④ 076 前两下不叠(是【每第三下】不是【每下】)",
		int(wt.get("corrode_stacks", 0)) == 0, "stacks=%d" % int(wt.get("corrode_stacks", 0)))
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_ok("④ 076 第三下 → +1 层腐蚀", int(wt.get("corrode_stacks", 0)) == 1,
		"stacks=%d" % int(wt.get("corrode_stacks", 0)))
	_ok("④ 076 档位记的是【羁绊档】2(不是装备星级 3)",
		int(wt.get("corrode_tier", 0)) == 2, "tier=%d" % int(wt.get("corrode_tier", 0)))
	for _k2 in range(60):
		_s._equip_sys._eq_on_basic_attack(w, wt)
	_ok("④ 076 ★仍受 5 层上限(与弓箭羁绊共用同一套层数)",
		int(wt["corrode_stacks"]) == 5, "stacks=%d" % int(wt["corrode_stacks"]))
	## ★不把目标身上已有的高档位降下去
	wt["corrode_tier"] = 3
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_s._equip_sys._eq_on_basic_attack(w, wt)
	_ok("④ 076 ★不把目标已有的 3 档腐蚀降成 2 档(取 max, 否则等于自己削自己队伍)",
		int(wt["corrode_tier"]) == 3, "tier=%d" % int(wt["corrode_tier"]))
	## ★★共用的确实是羁绊那套 corrode_stacks(消费侧真的在读): 满 5 层 1 档 ⇒ 100 打成 121
	_s._units.clear()
	var vic: Dictionary = _mk("basic", "right", Vector2(0.0, 500.0))
	vic["corrode_stacks"] = 5
	vic["corrode_tier"] = 1
	var v0: float = float(vic["hp"])
	var plain: Dictionary = _mk("fortune", "left", Vector2(-200.0, 500.0))
	_s._damage._apply_damage_from(plain, vic, 100, Color("#ffffff"))
	_ok("④ 076 ★★共用羁绊的 corrode_stacks(满 5 层·1 档 → 100 打成 110, 再 +10% 转真伤 = 121)",
		absf(v0 - float(vic["hp"]) - 121.0) < 0.51, "实掉 %.1f 期望 121" % (v0 - float(vic["hp"])))
	_s._synergy._by_side = saved
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ④b 076 的主动: 发数 = 消耗 ÷ 8 · 2000 码贯穿 · 每穿一人 ×0.75(最低 25%)
# ═════════════════════════════════════════════════════════════
func _t076_volley() -> void:
	print("── ④b 076 · 连射(发数=消耗÷8 · 2000 码贯穿 · 衰减 0.75) ──")
	## ★发数查的是 battle._skill_cost, 不是抄的表
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, -420.0)), "p2eq_076", 3)
	u["atk"] = 120.0
	u["base_atk"] = 120.0
	u["energy_cost"] = {"fakeSkill": 90.0}
	u["pending"] = "K:fakeSkill"
	_ok("④b ★分母: battle._skill_cost 查到本次消耗 90 龟能",
		absf(float(_s._skill_cost(u, "fakeSkill")) - 90.0) < 0.01,
		"cost=%.1f" % float(_s._skill_cost(u, "fakeSkill")))
	_ok("④b 90 龟能 → 11 发(每 8 龟能一发, 向下取整)",
		_s._equip_sys._bow_sys.shots_for(u, "fakeSkill") == 11,
		"shots=%d" % _s._equip_sys._bow_sys.shots_for(u, "fakeSkill"))
	u["energy_cost"] = {"bigSkill": 210.0}
	u["pending"] = "K:bigSkill"
	_ok("④b 210 龟能 → 26 发(削弱后的量级: 210 ÷ 8 = 26.25)",
		_s._equip_sys._bow_sys.shots_for(u, "bigSkill") == 26,
		"shots=%d" % _s._equip_sys._bow_sys.shots_for(u, "bigSkill"))
	## ★真入口: 经 _eq_on_cast 排队, 再同步喂 tick 逐发射出
	var e1: Dictionary = _mk("basic", "right", Vector2(-500.0, -420.0), 1.0e9)
	u["energy_cost"] = {"fakeSkill": 50.0}
	u["pending"] = "K:fakeSkill"
	_s._equip_sys._eq_on_cast(u, e1)
	_ok("④b ★★真入口: 经 _eq_on_cast 排了 6 发(50 ÷ 8 = 6.25)",
		int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_planned", 0)) == 6,
		"planned=%d" % int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_planned", 0)))
	for _k in range(300):                                # 同步喂 3 秒(6 发 × 0.15 = 0.9 秒, 富余)
		_s._equip_sys._bow_sys.tick(0.01)
	var fired: int = int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_fired", 0))
	_ok("④b ★真的射出了 6 发(不多不少 · 全同步喂 tick, 不等演出)", fired == 6, "fired=%d" % fired)
	for _k2 in range(300):
		_s._equip_sys._bow_sys.tick(0.01)
	_ok("④b ★分母: 再喂 3 秒仍是 6 发(连射真的停了)",
		int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_fired", 0)) == 6,
		"fired=%d" % int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_fired", 0)))
	## ★贯穿 + 衰减: 五个敌人排成一条直线, 一发箭穿过去伤害应是 25.6→19.2→14.4→10.8→8.1
	##   (3★ / ATK 120: 0.08×120 + 16 = 25.6, 每穿一人 ×0.75)
	for si in range(3):
		_s._units.clear()
		_s._equip_sys._bow_sys.clear()
		var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, -380.0)), "p2eq_076", si + 1)
		c["atk"] = 120.0
		c["base_atk"] = 120.0
		var row: Array = []
		for k in range(5):
			row.append(_mk("basic", "right", Vector2(-500.0 + 120.0 * float(k), -380.0), 1.0e9))
		var b4: Array = []
		for o in row:
			b4.append(float(o["hp"]))
		var pierced: int = _s._equip_sys._bow_sys.volley_shot(c, si)
		_ok("④b si=%d ★分母: 一发箭穿过了 5 个人" % si, pierced == 5, "pierced=%d" % pierced)
		var base: float = 120.0 * [0.05, 0.06, 0.08][si] + [9.0, 13.0, 16.0][si]
		var bad: Array = []
		for k2 in range(5):
			var mult: float = maxf(0.25, pow(0.75, float(k2)))
			## 物理段与真伤段各自取整再相加(实装就是两段分开打的)
			var want: float = float(maxi(1, int(round(120.0 * [0.05, 0.06, 0.08][si] * mult)))) \
				+ float(maxi(1, int(round([9.0, 13.0, 16.0][si] * mult))))
			var got: float = b4[k2] - float(row[k2]["hp"])
			if absf(got - want) >= 0.51:
				bad.append("第%d个 实掉%.1f 期望%.1f" % [k2 + 1, got, want])
		_ok("④b si=%d 贯穿衰减 = 每穿一人 ×0.75(首个 %.1f 起算)" % [si, base], bad.is_empty(), str(bad))
	## ★衰减地板 25%: 穿到第 6 个之后 0.75^n 已低于 0.25, 应当被地板托住
	_ok("④b ★衰减地板: 0.75^5 = 0.2373 < 0.25 ⇒ 第 6 个起一律 25%%",
		absf(BowEqVfx.pierce_mult(5) - 0.25) < 1e-9 and absf(BowEqVfx.pierce_mult(9) - 0.25) < 1e-9,
		"n=5→%.4f n=9→%.4f" % [BowEqVfx.pierce_mult(5), BowEqVfx.pierce_mult(9)])
	## ★2000 码: 2001 码外的不被穿
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var f: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, -340.0)), "p2eq_076", 3)
	f["atk"] = 120.0
	f["base_atk"] = 120.0
	var near: Dictionary = _mk("basic", "right", Vector2(-500.0, -340.0), 1.0e9)
	var far: Dictionary = _mk("basic", "right", Vector2(-400.0, -340.0), 1.0e9)
	far["pos"] = (f["pos"] as Vector2) + Vector2(2001.0, 0.0)
	var fh0: float = float(far["hp"])
	var pn: int = _s._equip_sys._bow_sys.volley_shot(f, 2)
	_ok("④b ★2000 码封顶: 2001 码外那个没被穿到", absf(fh0 - float(far["hp"])) < 0.01,
		"远处掉 %.1f" % (fh0 - float(far["hp"])))
	_ok("④b ★分母: 这一发确实穿到了近处那个(穿透数 = 1)", pn == 1, "pierced=%d" % pn)
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ④c 076 偷龟能: 每穿一人偷 0.5/0.5/1 点, 双向(敌人真的少, 自己真的多)
# ═════════════════════════════════════════════════════════════
func _t076_steal() -> void:
	print("── ④c 076 · 每穿一人偷 0.5/0.5/1 点龟能(双向) ──")
	for si in range(3):
		var steal: float = [0.5, 0.5, 1.0][si]
		_s._units.clear()
		_s._equip_sys._bow_sys.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, -300.0)), "p2eq_076", si + 1)
		u["atk"] = 120.0
		u["base_atk"] = 120.0
		u["active_skills"] = ["mine"]
		u["energy_cost"] = {"mine": 100.0}
		u["skill_cd"] = {"mine": 7.5}                    # 100 龟能 × 0.075 = 满冷却
		var v: Dictionary = _mk("basic", "right", Vector2(-500.0, -300.0), 1.0e9)
		v["active_skills"] = ["theirs"]
		v["energy_cost"] = {"theirs": 100.0}
		v["skill_cd"] = {"theirs": 3.0}                  # 还差 3 秒好 ⇒ 有 40 点龟能的余量可被偷
		var mine0: float = float(u["skill_cd"]["mine"])
		var his0: float = float(v["skill_cd"]["theirs"])
		var pierced: int = _s._equip_sys._bow_sys.volley_shot(u, si)
		_ok("④c si=%d ★分母: 这一发穿到了 1 个人" % si, pierced == 1, "pierced=%d" % pierced)
		## 偷 N 点 = 敌人冷却【多】N×0.075 秒
		_ok("④c si=%d 敌人被偷走 %.1f 点龟能(冷却往后推 %.4f 秒)" % [si, steal, steal * 0.075],
			absf(float(v["skill_cd"]["theirs"]) - his0 - steal * 0.075) < 0.0005,
			"敌冷却 %.4f → %.4f" % [his0, float(v["skill_cd"]["theirs"])])
		## 自己冷却【少】同样多
		_ok("④c si=%d 自己拿到同样的 %.0f 点(冷却提前 %.4f 秒 · 一分不多造)" % [si, steal, steal * 0.075],
			absf(mine0 - float(u["skill_cd"]["mine"]) - steal * 0.075) < 0.0005,
			"己冷却 %.4f → %.4f" % [mine0, float(u["skill_cd"]["mine"])])
	## ★偷不动就不算偷: 敌人技能已经满冷却(没有可偷的余量) ⇒ 自己也拿不到
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var a: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, -260.0)), "p2eq_076", 3)
	a["atk"] = 120.0
	a["base_atk"] = 120.0
	a["active_skills"] = ["mine"]
	a["energy_cost"] = {"mine": 100.0}
	a["skill_cd"] = {"mine": 7.5}
	var b: Dictionary = _mk("basic", "right", Vector2(-500.0, -260.0), 1.0e9)
	b["active_skills"] = ["theirs"]
	b["energy_cost"] = {"theirs": 100.0}
	b["skill_cd"] = {"theirs": 7.5}                      # 已是满冷却 = 龟能 0, 偷不动
	var am0: float = float(a["skill_cd"]["mine"])
	_s._equip_sys._bow_sys.volley_shot(a, 2)
	_ok("④c ★敌人龟能已见底 → 偷不到 ⇒ 自己也【不凭空多】(冷却纹丝不动)",
		absf(float(a["skill_cd"]["mine"]) - am0) < 0.0005,
		"己冷却 %.4f → %.4f" % [am0, float(a["skill_cd"]["mine"])])
	_ok("④c ★分母: 敌人的冷却也没被推过满(7.5 封顶)",
		absf(float(b["skill_cd"]["theirs"]) - 7.5) < 0.0005, "敌冷却 %.4f" % float(b["skill_cd"]["theirs"]))
	## ★没有龟能系统的单位(纯平 A)偷不了 —— drain_energy 返回 0
	var dumb: Dictionary = _mk("basic", "right", Vector2(-300.0, -260.0), 1.0e9)
	dumb["active_skills"] = []
	_ok("④c ★无主动技的单位偷不到龟能(返回 0, 不是报错也不是凭空给)",
		absf(_s._equip_sys._bow_sys.drain_energy(dumb, 2.0)) < 0.0001,
		"drained=%.4f" % _s._equip_sys._bow_sys.drain_energy(dumb, 2.0))
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ⑤ 演出的【物理模型】—— 纯函数, 全部是闭式解的性质, 手调曲线一条都过不了
# ═════════════════════════════════════════════════════════════
func _t_vfx_physics() -> void:
	print("── ⑤ 演出物理模型(闭式解性质) ──")

	# ① 073 临界阻尼跟随 -------------------------------------------------
	## 离散积分器与解析阶跃响应【逐点相等】, 且对 dt 大小不敏感(精确离散化, 帧率无关)
	var worst_dt := 0.0
	for dt in [0.004, 0.016, 0.05, 0.1]:
		var p := Vector2.ZERO
		var v := Vector2.ZERO
		var steps: int = int(round(0.5 / float(dt)))
		for _i in range(steps):
			var r: Array = BowEqVfx.crit_damp_step(p, v, Vector2(100.0, 0.0), 9.0, float(dt))
			p = r[0]
			v = r[1]
		var want: float = 100.0 * BowEqVfx.step_response(9.0, float(steps) * float(dt))
		worst_dt = maxf(worst_dt, absf(p.x - want))
	_ok("⑤① 临界阻尼积分器 ≡ 解析解 1−(1+ωt)e^(−ωt)(dt 从 4ms 到 100ms 最大偏差 %.4f 码)" % worst_dt,
		worst_dt < 0.01, "worst=%.6f" % worst_dt)
	_ok("⑤① 解析解在 t=1/ω 处 = 1 − 2/e = 0.264241(不是随手一条缓动)",
		absf(BowEqVfx.step_response(9.0, 1.0 / 9.0) - 0.2642411) < 1e-6,
		"%.7f" % BowEqVfx.step_response(9.0, 1.0 / 9.0))
	## ★永不过冲(ζ=1 的定义性质): 扫 400 个点, 一次都不能 ≥ 1
	var over := 0
	var mono := true
	var prev := -1.0
	for i in range(400):
		var x: float = BowEqVfx.step_response(9.0, float(i) * 0.01)
		if x >= 1.0:
			over += 1
		if x < prev - 1e-12:
			mono = false
		prev = x
	_ok("⑤① ★永不过冲(临界阻尼): 400 个采样点没有一个 ≥ 1", over == 0, "over=%d" % over)
	_ok("⑤① ★且单调递增(欠阻尼会先冲过头再荡回来)", mono)
	## ★稳态滞后 = 2v/ω(精确)。"有滞后跟随不是硬绑"这句话的可量形式 —— 硬绑滞后恒为 0。
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var tgt := Vector2.ZERO
	var speed := 300.0
	## ⚠ dt 要够小: 目标先跑再积分会引入 v·dt/2 的离散偏置(dt=0.01 时是 1.5 码,
	##   正好把 66.67 量成 65.17 —— 实测过)。用 dt=0.001 把它压到 0.15 码, 低于容差。
	for _i2 in range(12000):                             # 匀速跑 12 秒, 进稳态
		tgt.x += speed * 0.001
		var r2: Array = BowEqVfx.crit_damp_step(pos, vel, tgt, 9.0, 0.001)
		pos = r2[0]
		vel = r2[1]
	var lag: float = tgt.x - pos.x
	_ok("⑤① ★匀速跟随的稳态滞后 = 2v/ω = %.2f 码(实测 %.2f)" % [BowEqVfx.lag_steady(speed, 9.0), lag],
		absf(lag - BowEqVfx.lag_steady(speed, 9.0)) < 0.51, "lag=%.3f" % lag)
	_ok("⑤① ★分母: 滞后确实不为 0(硬绑的话这里是 0, 这条断言才有意义)", lag > 10.0, "lag=%.2f" % lag)
	## 反冲: 动量守恒 ⇒ Δv 与射向严格反平行
	var dv: Vector2 = BowEqVfx.recoil_dv(Vector2(3.0, -4.0), 100.0)
	_ok("⑤① ★反冲严格反平行(动量守恒): dot(Δv, 单位射向) = −|Δv| = −100",
		absf(dv.dot(Vector2(3.0, -4.0).normalized()) + 100.0) < 1e-4 and absf(dv.length() - 100.0) < 1e-4,
		"dv=%s len=%.4f" % [str(dv), dv.length()])

	# ② 074 立方根壳层 + 黄金角 ------------------------------------------
	var bad_cube: Array = []
	for s0 in [0.05, 0.2, 0.6, 1.7]:
		var ratio: float = BowEqVfx.shell_radius_px(8.0 * float(s0)) / BowEqVfx.shell_radius_px(float(s0))
		if absf(ratio - 2.0) > 1e-6:
			bad_cube.append("s=%.2f ratio=%.6f" % [s0, ratio])
	_ok("⑤② ★立方根体积律: radius(8s)/radius(s) ≡ 2 对任意 s(线性半径会给 8)",
		bad_cube.is_empty(), str(bad_cube))
	_ok("⑤② 黄金角 = π(3−√5) = 137.50776°(不是拍的数)",
		absf(BowEqVfx.GOLDEN_ANGLE - PI * (3.0 - sqrt(5.0))) < 1e-12,
		"%.15f vs %.15f" % [BowEqVfx.GOLDEN_ANGLE, PI * (3.0 - sqrt(5.0))])
	var gap_phi: float = BowEqVfx.min_plate_gap(40, BowEqVfx.GOLDEN_ANGLE)
	var gap_rat: float = BowEqVfx.min_plate_gap(40, PI * 0.5)
	_ok("⑤② ★叶序排布不结块: 40 片时黄金角的最小间距 %.4f ≫ 90° 辐条排布的 %.4f" % [gap_phi, gap_rat],
		gap_phi > gap_rat * 2.0, "phi=%.5f rational=%.5f" % [gap_phi, gap_rat])
	_ok("⑤② ★分母: 两种排布都真的算出了非零间距(不是都返回 0)",
		gap_phi > 0.0 and gap_rat > 0.0, "phi=%.5f rat=%.5f" % [gap_phi, gap_rat])

	# ③ 075 高抛弹道 -----------------------------------------------------
	## 顶点 = R·tan60°/4 = 0.4330·R, 且恰在行程一半处(对称)
	var bad_apex: Array = []
	for rr in [200.0, 400.0, 900.0]:
		var apex: float = BowEqVfx.lob_apex_px(rr)
		if absf(apex - rr * 1.7320508 * 0.25) > 1e-3:
			bad_apex.append("R=%.0f apex=%.3f" % [rr, apex])
		if absf(BowEqVfx.lob_height_px(rr, 0.5) - apex) > 1e-3:
			bad_apex.append("R=%.0f 顶点不在半程" % rr)
		if absf(BowEqVfx.lob_height_px(rr, 0.3) - BowEqVfx.lob_height_px(rr, 0.7)) > 1e-3:
			bad_apex.append("R=%.0f 不对称" % rr)
	_ok("⑤③ ★真抛物线: 顶点 = R·tan60°/4 · 恰在半程 · 左右对称", bad_apex.is_empty(), str(bad_apex))
	_ok("⑤③ ★分母: 顶点高度不是 0(400 码射程 ⇒ 顶点 %.1f 码)" % BowEqVfx.lob_apex_px(400.0),
		BowEqVfx.lob_apex_px(400.0) > 100.0)
	## 飞行时间 ∝ √R —— 匀速直线会给 4 倍, ease 曲线给别的数
	var t1: float = BowEqVfx.lob_time_s(200.0)
	var t4: float = BowEqVfx.lob_time_s(800.0)
	_ok("⑤③ ★飞行时间 ∝ √R: T(4R)/T(R) = %.6f ≡ 2(匀速直线会给 4)" % (t4 / t1),
		absf(t4 / t1 - 2.0) < 1e-6, "T=%.4f/%.4f" % [t1, t4])

	# ③b 落点散布是二维正态(Rayleigh 半径), 不是均匀 --------------------
	_s._battle_rng.seed = SEED
	var sigma: float = 400.0 / 3.0
	var in1 := 0
	var in2 := 0
	for _i3 in range(RAY_N):
		var off: Vector2 = _s._equip_sys._bow_sys._vfx.scatter_offset(sigma)
		var d: float = off.length()
		if d <= sigma:
			in1 += 1
		if d <= sigma * 2.0:
			in2 += 1
	var f1: float = float(in1) / float(RAY_N)
	var f2: float = float(in2) / float(RAY_N)
	_ok("⑤③ ★Rayleigh: 1σ 内 %.4f ≈ 0.3935(一维正态是 0.6827, 均匀圆盘更不同)" % f1,
		absf(f1 - 0.393469) < 0.025, "实测 %.4f 期望 0.3935" % f1)
	_ok("⑤③ ★Rayleigh: 2σ 内 %.4f ≈ 0.8647" % f2, absf(f2 - 0.864665) < 0.020,
		"实测 %.4f 期望 0.8647" % f2)
	_ok("⑤③ ★分母: 1σ 的实测值离【一维正态的 0.6827】远得多(证明这条判据分得开)",
		absf(f1 - 0.6827) > 0.20, "|%.4f − 0.6827| = %.4f" % [f1, absf(f1 - 0.6827)])
	_ok("⑤③ CDF 闭式解自洽: rayleigh_cdf(σ,σ)=0.393469 · rayleigh_cdf(2σ,σ)=0.864665",
		absf(BowEqVfx.rayleigh_cdf(sigma, sigma) - 0.393469) < 1e-5
			and absf(BowEqVfx.rayleigh_cdf(sigma * 2.0, sigma) - 0.864665) < 1e-5,
		"%.6f / %.6f" % [BowEqVfx.rayleigh_cdf(sigma, sigma), BowEqVfx.rayleigh_cdf(sigma * 2.0, sigma)])
	## 最密集处: 纯几何、零 RNG ⇒ 同样输入必给同样输出, 且覆盖数不低于任一单点为心
	var pts: Array = [Vector2(0, 0), Vector2(100, 0), Vector2(0, 100), Vector2(90, 90), Vector2(3000, 3000)]
	var c1: Vector2 = BowEqVfx.densest_point(pts, 400.0)
	var c2: Vector2 = BowEqVfx.densest_point(pts, 400.0)
	_ok("⑤③ 最密集处是纯几何(零 RNG): 同样输入两次结果完全相同", c1 == c2, "%s vs %s" % [str(c1), str(c2)])
	var cov := 0
	for p in pts:
		if (p as Vector2).distance_to(c1) <= 400.0:
			cov += 1
	var best_single := 0
	for p2 in pts:
		var n := 0
		for q in pts:
			if (q as Vector2).distance_to(p2) <= 400.0:
				n += 1
		best_single = maxi(best_single, n)
	_ok("⑤③ ★落点覆盖数 %d ≥ 任一单敌为心的最好成绩 %d" % [cov, best_single],
		cov >= best_single and cov == 4, "cov=%d best=%d" % [cov, best_single])

	# ④ 076 Beer–Lambert + 连射节奏 --------------------------------------
	var bad_bl: Array = []
	for n2 in range(5):                                  # 触底(n=5)之前应逐点相等
		if absf(BowEqVfx.pierce_mult(n2) - BowEqVfx.beer_lambert(n2)) > 1e-9:
			bad_bl.append("n=%d %.9f vs %.9f" % [n2, BowEqVfx.pierce_mult(n2), BowEqVfx.beer_lambert(n2)])
	_ok("⑤④ ★0.75ⁿ ≡ e^(−nμ), μ = −ln0.75 = 0.28768(Beer–Lambert 吸收律)",
		bad_bl.is_empty(), str(bad_bl))
	var bad_a: Array = []
	for n3 in range(8):
		if absf(BowEqVfx.tracer_alpha(n3) - BowEqVfx.pierce_mult(n3)) > 1e-12:
			bad_a.append("n=%d" % n3)
	_ok("⑤④ ★★光迹亮度 ≡ 伤害倍率(同一个函数, 不抄第二遍) ⇒ 越穿越暗是可判定的",
		bad_a.is_empty(), str(bad_a))
	_ok("⑤④ ★分母: 亮度确实在掉(n=0 → %.3f, n=4 → %.3f)"
			% [BowEqVfx.tracer_alpha(0), BowEqVfx.tracer_alpha(4)],
		BowEqVfx.tracer_alpha(4) < BowEqVfx.tracer_alpha(0) * 0.5)
	## LTI 叠加: 两发的合成 ≡ 各自响应之和
	var worst_lti := 0.0
	for i4 in range(60):
		var tt: float = float(i4) * 0.01
		var both: float = BowEqVfx.recoil_sum(tt, [0.0, 0.25])
		var sep: float = BowEqVfx.recoil_impulse(tt) + BowEqVfx.recoil_impulse(tt - 0.25)
		worst_lti = maxf(worst_lti, absf(both - sep))
	_ok("⑤④ ★LTI 叠加: 两发合成 ≡ 各自响应之和(最大偏差 %.12f)" % worst_lti, worst_lti < 1e-9)
	## 节奏读得出来: 相邻两发间隔 0.25 秒时, 前一发的残余 < 峰值 5%
	var peak := 0.0
	for i5 in range(2500):
		peak = maxf(peak, absf(BowEqVfx.recoil_impulse(float(i5) * 0.0001)))
	var resid: float = absf(BowEqVfx.recoil_impulse(0.25))
	_ok("⑤④ ★节奏读得出 42 下: 0.25 秒后残余 %.4f 只有峰值 %.4f 的 %.2f%%(<5%%)"
			% [resid, peak, resid / maxf(1e-9, peak) * 100.0],
		resid / maxf(1e-9, peak) < 0.05, "ratio=%.5f" % (resid / maxf(1e-9, peak)))
	_ok("⑤④ ★分母: 峰值本身不是 0(否则上一条恒真)", peak > 0.3, "peak=%.4f" % peak)


# ═════════════════════════════════════════════════════════════
# ⑥ 美术接线: 演出节点真的显示进 _world, 且尺寸【量真实节点】
# ═════════════════════════════════════════════════════════════
func _t_vfx_nodes() -> void:
	print("── ⑥ 演出节点(真的进 _world · 量真实对象) ──")
	_ok("⑥ ★分母: 战斗世界 _world 真的建起来了(没有它下面全是空检查)",
		is_instance_valid(_s._world), str(_s._world))
	var vfx = _s._equip_sys._bow_sys._vfx
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()

	## ③ 箭雨落区环: 半径 400 码 —— 量【节点自己的 AABB × scale】, 不是把公式抄一遍
	var ring = vfx.rain_marker(Vector2(0.0, 0.0), 400.0, 1.5)
	_ok("⑥ 箭雨落区环真的挂进了 _world",
		is_instance_valid(ring) and _s._world.is_ancestor_of(ring), str(ring))
	if is_instance_valid(ring):
		## ★三段包络(2026-08-12 用户重设计:「先以中心展开一个圈…最后圈往中间关闭」):
		##   出生半径必须≈0(从中心展开), 推进到常驻段才是 400 码, 末段收回≈0。
		var r_born: float = ring.get_aabb().size.x * 0.5 * ring.scale.x
		_ok("⑥ ★【展开】出生半径 %.5f m ≈ 0(从圆心长出来, 不是一上来就满圈)" % r_born,
			r_born < 0.05, "r0=%.5f" % r_born)
		vfx.tick(0.30)                                   # 越过展开段
		var aabb: AABB = ring.get_aabb()
		var r_m: float = aabb.size.x * 0.5 * ring.scale.x
		var want_m: float = 400.0 * float(_s.WS)
		_ok("⑥ ★量真实节点: 落区环世界半径 %.4f m = 400 码 × WS = %.4f m" % [r_m, want_m],
			absf(r_m - want_m) < 0.01, "实测 %.5f 期望 %.5f" % [r_m, want_m])
		vfx.tick(1.15)                                   # 推到 t=1.45(总 1.5 秒, 收拢段 1.20~1.50)
		var r_close: float = ring.get_aabb().size.x * 0.5 * ring.scale.x
		_ok("⑥ ★【关闭】末段圈往中间收: %.4f m → %.4f m(收到 25%% 以内)" % [r_m, r_close],
			r_close < r_m * 0.25, "r_close=%.5f" % r_close)
		## 纯函数包络与真实节点同源(演出/门禁不许各算各的)
		_ok("⑥ ★包络纯函数: 展开中点 <1 · 常驻 =1 · 收拢末尾 ≈0",
			BowEqVfx.rain_ring_scale(BowEqVfx.RAIN_OPEN_SEC * 0.5, 1.5) < 1.0
			and absf(BowEqVfx.rain_ring_scale(0.75, 1.5) - 1.0) < 1e-6
			and BowEqVfx.rain_ring_scale(1.5, 1.5) < 1e-6, "")
		_ok("⑥ ★贴地: 环的顶点都在同一水平面(不是立起来的; 见 memory fb-axis-y-plus-rotation-cancels)",
			absf(ring.get_aabb().size.y) < 1e-4, "AABB.y=%.6f" % ring.get_aabb().size.y)

	## ③ 落箭: 数量对得上 · 全在 _world 里 · **起点高度 = 抛物线顶点**(量真实节点的 AABB)
	_s._battle_rng.seed = SEED
	var before_children: int = _s._world.get_child_count()
	var made_arrows: int = vfx.rain_arrows(Vector2(0.0, 0.0), 400.0, 7)
	## ★每支箭 = 箭身 + 地面影子 + 拖尾 三个节点
	##   (影子让观众提前看出落点; 拖尾画的是已走过的路径 —— 2026-08-12 用户点名要拖尾)
	_ok("⑥ 一跳箭雨真的建了 7 支落箭(各带影子+拖尾 ⇒ 21 个节点), 且都挂进了 _world",
		made_arrows == 7 and _s._world.get_child_count() - before_children == 21,
		"made=%d 新增子节点=%d" % [made_arrows, _s._world.get_child_count() - before_children])
	## ★按 meta 认箭, 不按子节点下标 —— 一支箭挂几个节点是会变的, 下标一变就量错对象
	var arrow = null
	for ai in range(_s._world.get_child_count() - 1, -1, -1):
		var cand = _s._world.get_child(ai)
		if cand is MeshInstance3D and (cand as Node).has_meta(BowEqVfx.META_KEY) 				and str((cand as Node).get_meta(BowEqVfx.META_KEY)) == "rain_arrow":
			arrow = cand
			break
	if is_instance_valid(arrow) and arrow is MeshInstance3D:
		## ★★用户 2026-08-12 判语:「完全看不到箭在动」⇒ 旧版把整条弹道焊进网格、节点不动。
		##   新版箭是真的在飞: 这里量【同一个节点】在连续两帧的世界坐标, 必须在动、且在下落。
		var a_node: MeshInstance3D = arrow
		vfx.tick(0.001)                                   # 让它进入飞行(t≈0: 最高点)
		var p0: Vector3 = a_node.position
		vfx.tick(BowEqVfx.RAIN_FLY_SEC * 0.5)
		var p1: Vector3 = a_node.position
		vfx.tick(BowEqVfx.RAIN_FLY_SEC * 0.5 - 0.002)
		var p2: Vector3 = a_node.position
		_ok("⑥ ★★箭真的在动: 三帧世界坐标 y = %.3f → %.3f → %.3f(单调下落)" % [p0.y, p1.y, p2.y],
			p0.y > p1.y and p1.y > p2.y and p0.y - p2.y > 1.0, "")
		_ok("⑥ ★落地那一下最快(自由落体): 后半程掉的 %.3f m > 前半程 %.3f m"
				% [p1.y - p2.y, p0.y - p1.y], (p1.y - p2.y) > (p0.y - p1.y), "")
		_ok("⑥ ★出发高度 = %.1f 码 × WS = %.3f m(量真实节点, 不是抄公式)"
				% [BowEqVfx.RAIN_FLY_H, BowEqVfx.RAIN_FLY_H * float(_s.WS)],
			absf(p0.y - BowEqVfx.RAIN_FLY_H * float(_s.WS)) < 0.25, "y0=%.4f" % p0.y)
		_ok("⑥ ★分母: 落箭是【斜】着扎下来的(水平也移动了 %.3f m > 0)"
				% Vector2(p0.x - p2.x, p0.z - p2.z).length(),
			Vector2(p0.x - p2.x, p0.z - p2.z).length() > 0.1, "")
		## ★★入射角【全程恒定】= 上一版"斜着射入"的读法(2026-08-12 用户点名要回这个),
		##   而不是从抛物线顶点起步(那个出发几乎水平、越落越陡)。量两段真实位移的仰角。
		var seg1 := Vector2(Vector2(p0.x - p1.x, p0.z - p1.z).length(), p0.y - p1.y)
		var seg2 := Vector2(Vector2(p1.x - p2.x, p1.z - p2.z).length(), p1.y - p2.y)
		var ang1: float = rad_to_deg(atan2(seg1.y, maxf(seg1.x, 1e-9)))
		var ang2: float = rad_to_deg(atan2(seg2.y, maxf(seg2.x, 1e-9)))
		_ok("⑥ ★★斜着射入: 前后两段入射角 %.2f° / %.2f° 一致(≈60°, 差 <0.5°)" % [ang1, ang2],
			absf(ang1 - ang2) < 0.5 and absf(ang1 - 60.0) < 1.5, "")
		## 飞行纯函数与真实节点同源
		_ok("⑥ ★飞行包络: u=0 在最高点(1.0) · u=1 落地(0.0) · 中点 0.75(自由落体不是线性)",
			absf(BowEqVfx.rain_fly_at(0.0).y - 1.0) < 1e-6
			and absf(BowEqVfx.rain_fly_at(1.0).y) < 1e-6
			and absf(BowEqVfx.rain_fly_at(0.5).y - 0.75) < 1e-6, "")

		## ★★拖尾(2026-08-12 用户:「箭我要有拖尾」): 量拖尾节点的真实 scale.y
		##   —— 长度 = 已飞过的距离(封顶), 所以它画的就是走过的那段路径。
		var trail = null
		for ti in range(_s._world.get_child_count()):
			var tc = _s._world.get_child(ti)
			if tc is MeshInstance3D and (tc as Node).has_meta(BowEqVfx.META_KEY) 					and str((tc as Node).get_meta(BowEqVfx.META_KEY)) == "rain_trail":
				trail = tc
		if is_instance_valid(trail):
			var tl_now: float = (trail as MeshInstance3D).scale.y
			_ok("⑥ ★★拖尾真的在长: 飞到末段时长度 %.3f m > 0(旧版没有拖尾)" % tl_now,
				tl_now > 0.5, "len=%.4f" % tl_now)
			_ok("⑥ ★拖尾封顶 %.0f 码(不会拉成横穿全场的一条白线)" % BowEqVfx.RAIN_TRAIL_MAX,
				tl_now <= BowEqVfx.RAIN_TRAIL_MAX * float(_s.WS) + 1e-3, "len=%.4f" % tl_now)
		else:
			_ok("⑥ ★★拖尾真的在长(★分母: 场上没找到拖尾节点)", false, "")
		## ★★落地【不凭空消失】(用户点名): 飞行体出列那一刻必须留下【插在地上的箭】+ 落尘。
		var stuck0: int = _count_kind("rain_stuck")
		vfx.tick(0.12)                                     # 越过飞行终点
		var stuck1: int = _count_kind("rain_stuck")
		_ok("⑥ ★★落地不凭空消失: 插在地上的箭 %d → %d(飞行体换成插着的那支, 再慢慢淡)"
			% [stuck0, stuck1], stuck1 > stuck0, "")
		_ok("⑥ ★落地掀起落尘 %d 处" % _count_kind("rain_dust"), _count_kind("rain_dust") > 0, "")

	## ★★整波【同向齐射】(2026-08-12 用户:「不是四面八方射过来的」):
	##   量每支箭来向与【第一支】的夹角, 全部 < 5°。
	##   ⚠ 别拿 atan2 的 min-max 当散布 —— 来向落在 ±180° 附近时会跨越环绕边界,
	##     算出 358° 的假散布(第一版断言就是这么假红的; 尺子要匹配被测概念)。
	var dirs: Array = []
	for ci in range(_s._world.get_child_count()):
		var nd = _s._world.get_child(ci)
		if not (nd is MeshInstance3D) or not (nd as Node).has_meta(BowEqVfx.META_KEY):
			continue
		if str((nd as Node).get_meta(BowEqVfx.META_KEY)) != "rain_arrow":
			continue
		var upv: Vector3 = (nd as MeshInstance3D).transform.basis.y.normalized()
		var hz := Vector2(upv.x, upv.z)
		if hz.length() > 1e-6:
			dirs.append(hz.normalized())
	var max_dev := 0.0
	if dirs.size() >= 2:
		var ref: Vector2 = dirs[0]
		for dv in dirs:
			max_dev = maxf(max_dev, rad_to_deg(absf(ref.angle_to(dv))))
	_ok("⑥ ★★同向齐射: %d 支箭的来向与首支最大夹角 %.2f°(同一侧压过来, 不是四面八方)"
			% [dirs.size(), max_dev],
		dirs.size() >= 5 and max_dev < 5.0, "n=%d dev=%.2f" % [dirs.size(), max_dev])

	## ④ 贯穿光迹: 2000 码长, 且**分段数 = 穿透点数 + 1**
	var tr = vfx.pierce_tracer(Vector2(-600.0, 0.0), Vector2.RIGHT, 2000.0, [0.25, 0.5])
	_ok("⑥ 贯穿光迹真的挂进了 _world",
		is_instance_valid(tr) and _s._world.is_ancestor_of(tr), str(tr))
	if is_instance_valid(tr):
		## ★★2026-08-12 用户:「这感觉像激光来的, 我需要箭和尾迹, 速度也太快了」——
		##   旧版是一条【瞬时铺满 2000 码】的分段光带(所以读成激光); 现在是一支【飞】的弩矢。
		##   判据随之改成: 量同一个节点的真实位移与速度, 以及尾迹随之变长。
		var b0: Vector3 = tr.position
		vfx.tick(0.10)
		var b1: Vector3 = tr.position
		var step_m: float = (b1 - b0).length()
		var want_step: float = BowEqVfx.BOLT_SPEED * 0.10 * float(_s.WS)
		_ok("⑥ ★★弩矢真的在飞: 0.10 秒走了 %.3f m = %.0f 码/秒 × 0.10 × WS = %.3f m"
				% [step_m, BowEqVfx.BOLT_SPEED, want_step],
			absf(step_m - want_step) < 0.05, "实测 %.4f 期望 %.4f" % [step_m, want_step])
		_ok("⑥ ★飞完 2000 码要 %.2f 秒(不是瞬时铺满 —— 那正是「像激光」的根因)"
				% (2000.0 / BowEqVfx.BOLT_SPEED),
			2000.0 / BowEqVfx.BOLT_SPEED > 0.5, "")
		## 尾迹: 与 075 落箭同一条做法(画的是已飞过的那段), 长度随飞行变长并封顶
		var btrail = null
		for bi in range(_s._world.get_child_count()):
			var bc = _s._world.get_child(bi)
			if bc is MeshInstance3D and (bc as Node).has_meta(BowEqVfx.META_KEY) 					and str((bc as Node).get_meta(BowEqVfx.META_KEY)) == "bolt_trail":
				btrail = bc
		_ok("⑥ ★★弩矢有尾迹, 且长度 %.3f m > 0 并封顶 %.0f 码"
				% [(btrail as MeshInstance3D).scale.y if is_instance_valid(btrail) else -1.0,
					BowEqVfx.BOLT_TRAIL_MAX],
			is_instance_valid(btrail) and (btrail as MeshInstance3D).scale.y > 0.1
			and (btrail as MeshInstance3D).scale.y <= BowEqVfx.BOLT_TRAIL_MAX * float(_s.WS) + 1e-3, "")

	## ① 藤蔓小球: 真的挂进 _world, 且【不硬绑】(携带者瞬移后小球还在原地追)
	var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, -200.0))
	var orb = vfx.ensure_orb(u)
	_ok("⑥ 藤蔓小球真的挂进了 _world", is_instance_valid(orb) and _s._world.is_ancestor_of(orb), str(orb))
	var p_before: Vector2 = u["_vine_orb_pos"]
	u["pos"] = (u["pos"] as Vector2) + Vector2(400.0, 0.0)
	vfx.orb_tick(u, 0.016)
	var moved: float = ((u["_vine_orb_pos"] as Vector2) - p_before).length()
	_ok("⑥ ★小球【不硬绑】: 携带者瞬移 400 码后一帧只追了 %.1f 码(硬绑会是 400)" % moved,
		moved > 0.1 and moved < 40.0, "moved=%.3f" % moved)

	## ② 护盾罩(2026-08-12 用户:「我要的是护盾罩子: 获得护盾/持续护盾/护盾破裂」)
	##    —— 膜 + 鲸骨肋条两个网格真的进 _world; 幂等(再调不新增)
	var b: Dictionary = _mk("fortune", "left", Vector2(-100.0, -200.0))
	var dh: Dictionary = vfx.dome_ensure(b)
	var shell = dh.get("shell", null)
	var omat = dh.get("mat", null)
	_ok("⑥ 护盾球真的挂进 _world, 且用的是流动 shader(不是 StandardMaterial 的死球)",
		is_instance_valid(shell) and _s._world.is_ancestor_of(shell)
		and omat is ShaderMaterial and (omat as ShaderMaterial).shader != null, "")
	## ★流动的事实源 = 每帧喂给 shader 的 u_t(不用 TIME —— 无头/暂停下可复现, 同 mana_beam)
	##   ⚠ null 安全回读(memory fb-null-readback-makes-test-silently-abort):
	##      未设过的参数回读是 null, float(null) 会让整个测试函数静默中止还照打 ALL PASS。
	var t_before = (omat as ShaderMaterial).get_shader_parameter("u_t")
	var tb: float = float(t_before) if t_before != null else -999.0
	vfx.dome_follow(b, 0.25)
	var t_after = (omat as ShaderMaterial).get_shader_parameter("u_t")
	var ta: float = float(t_after) if t_after != null else -999.0
	_ok("⑥ ★护盾球是【流动】的: 一帧 0.25 秒后 shader 时间 %.3f → %.3f(不动就是张静止贴图)" % [tb, ta],
		tb > -900.0 and ta > -900.0 and absf(ta - tb - 0.25) < 1e-4, "")
	var again: Dictionary = vfx.dome_ensure(b)
	_ok("⑥ ★幂等: 再调 dome_ensure 不新建(罩子只有一个, 不是叠一次加一层)",
		is_same(again.get("shell", null), shell), "")
	## ★尺寸【不随剩余盾量缩小】(用户 2026-08-11 对 071 定的同族约束)
	vfx.dome_follow(b, 1.0)                      # 先跑过弹出期
	var sc_full: float = (shell as Node3D).scale.x
	b["shield"] = 1.0                            # 盾被打到只剩 1 点
	vfx.dome_follow(b, 0.016)
	var sc_low: float = (shell as Node3D).scale.x
	_ok("⑥ ★罩子不随盾量缩小: 满盾 %.4f vs 剩 1 点 %.4f(呼吸 ±3.5%% 内)" % [sc_full, sc_low],
		absf(sc_full - sc_low) / maxf(sc_full, 1e-9) < 0.08 and sc_full > 0.0, "")
	## 破裂: 罩子没了、骨片飞出来
	var shards: int = vfx.dome_break(b)
	## ⚠ queue_free 是【延迟】释放 —— 同一帧里节点仍然 is_instance_valid,
	##   判"收掉了"要看 is_queued_for_deletion(拿 is_instance_valid 判会假红)。
	_ok("⑥ ★护盾破裂: 罩子收掉 + 炸出 %d 片骨片(不是直接消失)" % shards,
		shards == BowEqVfx.DOME_SHARDS and not b.has("_bone_dome")
		and (not is_instance_valid(shell) or (shell as Node).is_queued_for_deletion()),
		"shards=%d" % shards)
	## 撤场: detach 后罩子节点真的没了(换路自扫走的就是这条路)
	var b2: Dictionary = _mk("fortune", "left", Vector2(-140.0, -200.0))
	vfx.dome_ensure(b2)
	var freed: int = vfx.detach(b2)
	_ok("⑥ ★撤场: detach 释放了护盾球, 单位身上的引用被清干净",
		freed == 1 and not b2.has("_bone_dome"), "freed=%d" % freed)
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
# ⑦ 补验收(2026-08-11): 常驻小球 · holdfade · 甲片跟随 · 穿透爆点 · 装备格读数镜像
#    由来: VFXLAB 实拍复核 —— 1.0 秒那张没有球(case 注明"还没开打就该看得见")、
#    藤蔓箭 9 张 0 张可见(0.14 秒 + 出生即淡出)、甲片走位时吊在身后、
#    073/075/076 的核心机制在局内零读数。
# ═════════════════════════════════════════════════════════════
func _t_readouts_fixture() -> void:
	print("── ⑦ 补验收: 常驻件/淡出/跟随/读数(2026-08-11) ──")
	var vfx = _s._equip_sys._bow_sys._vfx

	# ⑦a 073 小球是常驻件 ------------------------------------------------
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -440.0)), "p2eq_073", 3)
	_s._equip_sys._bow_sys.tick(0.6)                     # > SWEEP_IV=0.5 ⇒ 自扫跑了一班
	_ok("⑦a ★★073 小球【常驻】: 一次普攻没打, 0.6 秒自扫后球已挂进 _world(规格首句是'获得'不是'普攻后获得')",
		is_instance_valid(u.get("_vine_orb", null)) and _s._world.is_ancestor_of(u["_vine_orb"]),
		str(u.get("_vine_orb", null)))
	var v0: Dictionary = _mk("fortune", "left", Vector2(-260.0, -440.0))
	_s._equip_sys._bow_sys.tick(0.6)
	_ok("⑦a ★分母: 没带 073 的单位不长球(自扫不是见人就发)", not v0.has("_vine_orb"))

	# ⑦b holdfade(量真实节点的材质, 不是抄公式) ---------------------------
	var ring = vfx.rain_marker(Vector2(0.0, 0.0), 400.0, 1.0)
	var rm: StandardMaterial3D = ring.material_override
	var a0: float = rm.albedo_color.a
	_ok("⑦b ★分母: 出生 alpha = 作者写的 0.85(旧版第一帧就被顶成 1.0)",
		absf(a0 - 0.85) < 0.001, "a0=%.3f" % a0)
	vfx.tick(0.5)                                        # 50% 寿命
	var a_mid: float = rm.albedo_color.a
	_ok("⑦b ★★holdfade: 50%% 寿命仍是出生亮度(%.3f = %.3f) —— 不再一出生就淡" % [a_mid, a0],
		absf(a_mid - a0) < 0.001, "mid=%.3f" % a_mid)
	vfx.tick(0.4)                                        # 90% 寿命 ⇒ 收到 (1-0.9)/0.3 = 1/3
	var a_late: float = rm.albedo_color.a
	_ok("⑦b ★90%% 寿命时收到出生亮度的 1/3 档(实测 %.3f)" % a_late,
		a_late < a0 * 0.5 and a_late > a0 * 0.1, "late=%.3f a0=%.3f" % [a_late, a0])

	# ⑦c 074 护盾罩三态: 获得 → 跟人 → 破裂(2026-08-12 用户点名的三个时刻) -----
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var b: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -400.0), 5000.0), "p2eq_074", 3)
	var bt: Dictionary = _mk("basic", "right", Vector2(-100.0, -400.0))
	_s._equip_sys._eq_on_basic_attack(b, bt)             # 真入口: 叠盾 + 建罩子 + 登记 owner
	_s._equip_sys._bow_sys.tick(0.016)                   # 看门人这一帧把 _bone_dome_on 立起来
	var dome0 = b.get("_bone_dome", null)
	_ok("⑦c ★【获得护盾】走真入口一次普攻就有罩子(不是只写了函数没人调)",
		dome0 is Dictionary and is_instance_valid((dome0 as Dictionary).get("shell", null))
		and bool(b.get("_bone_dome_on", false)), "")
	var pl0: Vector3 = ((dome0 as Dictionary)["shell"] as Node3D).position
	b["pos"] = (b["pos"] as Vector2) + Vector2(500.0, 0.0)
	_s._equip_sys._bow_sys.tick(0.016)
	var pl1: Vector3 = ((dome0 as Dictionary)["shell"] as Node3D).position
	var moved: float = (pl1 - pl0).length() / float(_s.WS)
	_ok("⑦c ★【持续护盾】罩子跟人走: 携带者瞬移 500 码后【一帧】跟了 %.1f 码" % moved,
		absf(moved - 500.0) < 1.0, "moved=%.2f" % moved)
	## 【护盾破裂】盾被打光那一帧 —— 破裂必须由看门人发, 不能等下次普攻
	var shell_ref = (dome0 as Dictionary)["shell"]
	b["shield"] = 0.0
	_s._equip_sys._bow_sys.tick(0.016)
	_ok("⑦c ★【护盾破裂】盾归零那一帧罩子就炸掉(不是等下次普攻才发现): broke_n=%d"
		% int(b.get("_bone_dome_broke_n", 0)),
		int(b.get("_bone_dome_broke_n", 0)) == 1 and not b.has("_bone_dome")
		and (not is_instance_valid(shell_ref) or (shell_ref as Node).is_queued_for_deletion())
		and not bool(b.get("_bone_dome_on", true)), "")
	## ★分母: 破裂后不再重复触发(每次盾归零只炸一次)
	_s._equip_sys._bow_sys.tick(0.016)
	_s._equip_sys._bow_sys.tick(0.016)
	_ok("⑦c ★分母: 之后两帧不再重复炸(broke_n 仍为 1)",
		int(b.get("_bone_dome_broke_n", 0)) == 1, "broke_n=%d" % int(b.get("_bone_dome_broke_n", 0)))

	# ⑦d 073 攻速 buff 的读数镜像(vine_buff_pct 0~100) --------------------
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var tsave: float = _s._t
	var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -360.0)), "p2eq_073", 3)
	c["atk"] = 100.0
	c["base_atk"] = 100.0
	c["crit"] = 1.0
	var ct: Dictionary = _mk("basic", "right", Vector2(-100.0, -360.0))
	_s._equip_sys._eq_on_basic_attack(c, ct)
	_ok("⑦d 073 暴击瞬间 vine_buff_pct = 100(触发瞬间读数就位)",
		absf(float((c["eq_state"]["p2eq_073"] as Dictionary).get("vine_buff_pct", -1.0)) - 100.0) < 0.001,
		"pct=%.2f" % float((c["eq_state"]["p2eq_073"] as Dictionary).get("vine_buff_pct", -1.0)))
	_s._t += 1.0
	_s._equip_sys._bow_sys.tick(0.016)                   # 镜像每帧衰减(走 _tick_orbs)
	var halfp: float = float((c["eq_state"]["p2eq_073"] as Dictionary).get("vine_buff_pct", -1.0))
	_ok("⑦d 1 秒后镜像 ≈ 50(剩 1/2 秒, 实测 %.1f)" % halfp, absf(halfp - 50.0) < 2.0, "pct=%.2f" % halfp)
	_s._t = float((c["eq_state"]["p2eq_073"] as Dictionary)["vine_aspd_until"]) + 0.01
	_s._equip_sys._bow_sys.tick(0.016)
	_ok("⑦d 到期后镜像回 0(条不许停在满格骗人)",
		absf(float((c["eq_state"]["p2eq_073"] as Dictionary).get("vine_buff_pct", -1.0))) < 0.001,
		"pct=%.2f" % float((c["eq_state"]["p2eq_073"] as Dictionary).get("vine_buff_pct", -1.0)))
	_s._t = tsave

	# ⑦e 076 被动"每第三下"的进度镜像(cross_step) -------------------------
	var saved = _s._synergy._by_side
	_s._units.clear()
	_s._synergy._by_side = {"left": {"弓箭": 1}, "right": {}}
	var w: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -320.0)), "p2eq_076", 3)
	var wt: Dictionary = _mk("basic", "right", Vector2(-100.0, -320.0))
	var steps: Array = []
	for _k in range(3):
		_s._equip_sys._eq_on_basic_attack(w, wt)
		steps.append(int((w["eq_state"]["p2eq_076"] as Dictionary).get("cross_step", -1)))
	_ok("⑦e 076 被动进度 cross_step 走 1→2→0(第三下触发那格清零)", steps == [1, 2, 0], str(steps))
	_s._units.clear()
	_s._synergy._by_side = {"left": {}, "right": {}}
	var w2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -280.0)), "p2eq_076", 3)
	var wt2: Dictionary = _mk("basic", "right", Vector2(-100.0, -280.0))
	_s._equip_sys._eq_on_basic_attack(w2, wt2)
	_ok("⑦e ★羁绊未激活 ⇒ 进度恒 0(不给玩家兑不了现的进度条)",
		int((w2["eq_state"]["p2eq_076"] as Dictionary).get("cross_step", -1)) == 0,
		"step=%d" % int((w2["eq_state"]["p2eq_076"] as Dictionary).get("cross_step", -1)))
	_s._synergy._by_side = saved

	# ⑦f 076 待射发数徽章(volley_left) ------------------------------------
	_s._units.clear()
	_s._equip_sys._bow_sys.clear()
	var q: Dictionary = _equip(_mk("fortune", "left", Vector2(-700.0, -240.0)), "p2eq_076", 3)
	q["atk"] = 120.0
	q["base_atk"] = 120.0
	q["energy_cost"] = {"fakeSkill": 50.0}
	q["pending"] = "K:fakeSkill"
	var _qe: Dictionary = _mk("basic", "right", Vector2(-500.0, -240.0), 1.0e9)
	_s._equip_sys._eq_on_cast(q, _qe)
	var q_st: Dictionary = q["eq_state"]["p2eq_076"]
	_ok("⑦f 排队瞬间徽章 = 6(50 龟能 ÷ 8)", int(q_st.get("volley_left", -1)) == 6,
		"left=%d" % int(q_st.get("volley_left", -1)))
	for _k2 in range(60):                                # 0.6 秒: 射了 2~3 发
		_s._equip_sys._bow_sys.tick(0.01)
	q_st = q["eq_state"]["p2eq_076"]
	var q_mid: int = int(q_st.get("volley_left", -1))
	## ★不钉死"0.6 秒 = 正好 N 发"(0.01 的二进制误差会让边界发漂一格) ——
	##   判据换成时刻恒等式: 徽章 ≡ 排的 − 射出的(对任意时刻成立, 帧率无关)
	_ok("⑦f ★逐发倒数中(0<left<6, 实测 %d)" % q_mid, q_mid > 0 and q_mid < 6, "left=%d" % q_mid)
	_ok("⑦f ★★恒等式: 徽章 = volley_planned − volley_fired(%d = %d − %d)"
			% [q_mid, int(q_st.get("volley_planned", -1)), int(q_st.get("volley_fired", -1))],
		q_mid == int(q_st.get("volley_planned", -1)) - int(q_st.get("volley_fired", -1)),
		str(q_st))
	for _k3 in range(300):                               # 再 3 秒: 必然射完
		_s._equip_sys._bow_sys.tick(0.01)
	_ok("⑦f 射完归 0(条不许停在非零骗人)",
		int((q["eq_state"]["p2eq_076"] as Dictionary).get("volley_left", -1)) == 0,
		"left=%d" % int((q["eq_state"]["p2eq_076"] as Dictionary).get("volley_left", -1)))

	# ⑦h ★★「每第三下【普攻】」真的只有普攻能触发(2026-08-12 用户问:「确定是只有普攻能触发的吧」)
	#     由来: 061 那一族(015/038/056/061/062/063/070)当初错挂在 _eq_on_hit 上,
	#     赛博龟的浮游炮/多段技/DoT 全能触发, 与规格「每次普攻」不符, 已补 basic 闸。
	#     弓箭这三件挂的是 _eq_on_basic_attack(全仓库唯一调用点 = _basic_attack), 本来就对 ——
	#     但"代码看着对"不算证据: 这里【走真实伤害入口】反证一遍, 谁把它改挂到 on_hit 就会红。
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()
	var pb: Dictionary = _equip(_mk("fortune", "left", Vector2(-800.0, 600.0), 4000.0), "p2eq_076", 3)
	var pe: Dictionary = _mk("basic", "right", Vector2(-700.0, 600.0), 100000.0)
	## ⚠ eq_state 的每件槽位是【懒建】的: 没触发过就还没有这个键。
	##   直接 pb["eq_state"]["p2eq_076"] 会运行时报错, 而那会【静默掐断整个测试函数】——
	##   剩余断言一条不跑, 却照样打 ALL PASS(memory fb-null-readback-makes-test-silently-abort)。
	##   我刚就是这么把 ⑦g/⑦h 整段弄没的, 靠"断言总数变少"才发现。
	_s._equip_sys._eq_on_basic_attack(pb, pe)          # 先走一发真普攻, 把槽位建出来
	var st_p: Dictionary = (pb.get("eq_state", {}) as Dictionary).get("p2eq_076", {})
	_ok("⑦h ★分母: 076 的 eq_state 槽位已建出来(否则下面全是空检查)", not st_p.is_empty(), "")
	st_p["cross_hits"] = 0
	## ① 技能/DoT/装备伤害走 _apply_damage_from(from_equip=true) —— 打十下
	for _sk in range(10):
		_s._damage._apply_damage_from(pb, pe, 50, Color("#ffffff"), 0.0, false, true)
	var after_skill: int = int((pb["eq_state"]["p2eq_076"] as Dictionary).get("cross_hits", 0))
	_ok("⑦h ★★10 下【非普攻】伤害后, 076 的普攻计数仍是 0(浮游炮/多段技/DoT 不该触发)",
		after_skill == 0, "cross_hits=%d" % after_skill)
	## ② 同样十下, 但走【普攻真入口】
	for _ba in range(10):
		_s._equip_sys._eq_on_basic_attack(pb, pe)
	var after_basic: int = int((pb["eq_state"]["p2eq_076"] as Dictionary).get("cross_hits", 0))
	_ok("⑦h ★分母: 10 下真普攻后计数 = 10(证明上一条不是「这个计数根本不会动」)",
		after_basic == 10, "cross_hits=%d" % after_basic)
	## ③ 073/074 同族同理(它们的规格也写着"每次普攻")
	var pb2: Dictionary = _equip(_mk("fortune", "left", Vector2(-860.0, 600.0), 4000.0), "p2eq_074", 3)
	var sh_before: float = float(pb2.get("shield", 0.0))
	for _sk2 in range(6):
		_s._damage._apply_damage_from(pb2, pe, 50, Color("#ffffff"), 0.0, false, true)
	_ok("⑦h ★074「每次普攻叠盾」同样只认普攻: 6 下非普攻伤害后护盾没涨",
		absf(float(pb2.get("shield", 0.0)) - sh_before) < 0.01,
		"shield %.1f → %.1f" % [sh_before, float(pb2.get("shield", 0.0))])
	_s._equip_sys._eq_on_basic_attack(pb2, pe)
	_ok("⑦h ★分母: 一下真普攻后 074 护盾确实涨了(%.1f → %.1f)"
			% [sh_before, float(pb2.get("shield", 0.0))],
		float(pb2.get("shield", 0.0)) > sh_before + 0.5, "")

	# ⑦i ★★发数 = 【那个技能真实消耗的龟能】÷ 8(2026-08-12 用户问:「消耗了80龟能就获得16个充能吗」)
	#     判据不拿合成数字, 走【真龟 + 真技能 + 真消耗查询】: 消耗改多少, 发数就跟着变。
	#     ★不在测试里抄一份消耗表 —— 那样产品改了消耗、门禁照样绿(手抄副本必漂)。
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()
	var cb: Dictionary = _equip(_mk("basic", "left", Vector2(-900.0, -700.0), 4000.0), "p2eq_076", 3)
	## ★2026-08-12 用户削弱: ÷5 → ÷8(80 龟能 16 发 → 10 发)
	for pair in [[80.0, 10], [78.0, 9], [40.0, 5], [8.0, 1], [7.0, 0]]:
		var cost: float = float(pair[0])
		var want_shots: int = int(pair[1])
		## 给这只龟这条技能设一个真实消耗(energy_cost 就是战斗读的那张表)
		cb["energy_cost"] = {"probeSkill": cost}
		cb["pending"] = "K:probeSkill"
		var real_cost: float = float(_s._skill_cost(cb, "probeSkill"))
		var got: int = _s._equip_sys._bow_sys.shots_for(cb, "probeSkill")
		_ok("⑦i 消耗 %.0f 龟能 → %d 发(= %.0f ÷ 8 向下取整; 战斗侧实测消耗 %.0f)"
				% [cost, want_shots, cost, real_cost],
			got == want_shots and absf(real_cost - cost) < 0.001, "实测 %d 发" % got)
	## ★分母: 没在放技能(pending 不是 K:) ⇒ 一发都不排(不会平白连射)
	cb["pending"] = ""
	_ok("⑦i ★分母: 没放技能时 0 发(cast_stype 空 ⇒ 不排连射)",
		_s._equip_sys._bow_sys.shots_for(cb, _s._equip_sys._bow_sys.cast_stype(cb)) == 0, "")
	## ★真入口一遍: on_cast_076 排的发数 = shots_for 给的数(徽章/计数都对得上)
	cb["energy_cost"] = {"probeSkill": 80.0}
	cb["pending"] = "K:probeSkill"
	_s._equip_sys._bow_sys.on_cast_076(cb, 2)
	var cst: Dictionary = (cb.get("eq_state", {}) as Dictionary).get("p2eq_076", {})
	_ok("⑦i ★★走真入口: 80 龟能的技能排了 %d 发, 徽章也是 %d(读数与机制同源)"
			% [int(cst.get("volley_planned", -1)), int(cst.get("volley_left", -1))],
		int(cst.get("volley_planned", -1)) == 10 and int(cst.get("volley_left", -1)) == 10, str(cst))
	## ★分母: 除数本身就是 8 —— 谁把它改回 5, 上面整张表连同这条一起红
	_ok("⑦i ★除数焊死为 8 龟能/发", absf(EqBowBatch.ENERGY_PER_SHOT - 8.0) < 1e-9,
		"ENERGY_PER_SHOT=%.2f" % EqBowBatch.ENERGY_PER_SHOT)

	# ⑦g 贯穿命中记号: **弩矢飞到谁, 谁那一刻才炸**(2026-08-12 重做; 旧版一发射出就全亮=激光读法)
	_s._equip_sys._bow_sys.clear()
	## ⚠ 量【增量】不量绝对数: queue_free 是延迟的, 前面用例射过的记号这一帧还挂在树上
	var base_mk: int = _count_kind("bolt_hit")
	var tr2 = vfx.pierce_tracer(Vector2(-600.0, 100.0), Vector2.RIGHT, 2000.0, [0.25, 0.5])
	_ok("⑦g ★分母: 弩矢节点建出来了(它不在, 下面全是空检查)",
		is_instance_valid(tr2) and _s._world.is_ancestor_of(tr2), str(tr2))
	_ok("⑦g ★发射瞬间【一个记号都没有】(激光才会开场全亮)",
		_count_kind("bolt_hit") - base_mk == 0, "新增=%d" % (_count_kind("bolt_hit") - base_mk))
	## 飞到 30% 处: 只该炸掉 0.25 那个点, 0.5 那个还没到
	vfx.tick(2000.0 * 0.30 / BowEqVfx.BOLT_SPEED)
	var mk1: int = _count_kind("bolt_hit") - base_mk
	_ok("⑦g ★★飞过第 1 个命中点(30% 行程)后只炸了 1 枚记号", mk1 == 1, "新增=%d" % mk1)
	## 飞完全程: 两个点都炸过
	vfx.tick(2000.0 * 0.75 / BowEqVfx.BOLT_SPEED)
	var mk2: int = _count_kind("bolt_hit") - base_mk
	_ok("⑦g ★★飞完全程后记号数 = 穿透点数 2(数得出穿了几个人)", mk2 == 2, "新增=%d" % mk2)

	# ⑦h 读数表两头焊死(写的字段 = 表里读的字段) --------------------------
	var ER := preload("res://scripts/gamedata/equip_readouts.gd")
	_ok("⑦h COUNT 表: 076 → volley_left", str(ER.COUNT.get("p2eq_076", "")) == "volley_left",
		str(ER.COUNT.get("p2eq_076", "缺行")))
	var r73: Array = ER.CHARGE.get("p2eq_073", [])
	_ok("⑦h CHARGE 表: 073 → vine_buff_pct / 满值 100",
		r73.size() >= 2 and str(r73[0]) == "vine_buff_pct" and absf(float(r73[1]) - 100.0) < 0.001,
		str(r73))
	var r75: Array = ER.CHARGE.get("p2eq_075", [])
	_ok("⑦h ★★CHARGE 表: 075 读 iv_t 且分母 = EQ_IV_BATCH1 的周期(改周期漏改这里, 条就走不满/提前满)",
		r75.size() >= 2 and str(r75[0]) == "iv_t"
			and absf(float(r75[1]) - float(EquipSystem.EQ_IV_BATCH1.get("p2eq_075", -1.0))) < 0.001,
		str(r75))
	var r76: Array = ER.CHARGE.get("p2eq_076", [])
	_ok("⑦h CHARGE 表: 076 → cross_step / 分母 3(每第三下)",
		r76.size() >= 2 and str(r76[0]) == "cross_step" and absf(float(r76[1]) - 3.0) < 0.001,
		str(r76))
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()


## 数场上某一类演出节点(按 BowEqVfx 打的 meta 认, 不按名字/下标 —— 下标会随节点数变)
func _count_kind(kind: String) -> int:
	var n := 0
	for i in range(_s._world.get_child_count()):
		var c = _s._world.get_child(i)
		if c is Node and (c as Node).has_meta(BowEqVfx.META_KEY) 				and str((c as Node).get_meta(BowEqVfx.META_KEY)) == kind:
			n += 1
	return n
