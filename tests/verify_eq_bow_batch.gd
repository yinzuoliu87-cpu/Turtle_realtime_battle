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
	print("=== 弓箭 4 件(073 藤蔓弓弦 / 074 鲸骨胸甲 / 075 测距绳结 / 076 连发弩机) ===")
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
	## ★演出与效果的节拍是【同一个数】: 076 每 0.25 秒一发, 反冲振子也按 0.25 秒排
	_ok("⓪ ★连射节拍与反冲节拍焊死相等(0.25 秒)",
		absf(EqBowBatch.VOLLEY_IV - BowEqVfx.RECOIL_IV) < 1e-9
			and absf(EqBowBatch.VOLLEY_IV - 0.25) < 1e-9,
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
	print("── ③ 075 测距绳结 · 距离增伤(不封顶) ──")
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
# ④b 076 的主动: 发数 = 消耗 ÷ 5 · 2000 码贯穿 · 每穿一人 ×0.75(最低 25%)
# ═════════════════════════════════════════════════════════════
func _t076_volley() -> void:
	print("── ④b 076 · 连射(发数=消耗÷5 · 2000 码贯穿 · 衰减 0.75) ──")
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
	_ok("④b 90 龟能 → 18 发(每 5 龟能一发)",
		_s._equip_sys._bow_sys.shots_for(u, "fakeSkill") == 18,
		"shots=%d" % _s._equip_sys._bow_sys.shots_for(u, "fakeSkill"))
	u["energy_cost"] = {"bigSkill": 210.0}
	u["pending"] = "K:bigSkill"
	_ok("④b 210 龟能 → 42 发(方案书量级表的那一行)",
		_s._equip_sys._bow_sys.shots_for(u, "bigSkill") == 42,
		"shots=%d" % _s._equip_sys._bow_sys.shots_for(u, "bigSkill"))
	## ★真入口: 经 _eq_on_cast 排队, 再同步喂 tick 逐发射出
	var e1: Dictionary = _mk("basic", "right", Vector2(-500.0, -420.0), 1.0e9)
	u["energy_cost"] = {"fakeSkill": 50.0}
	u["pending"] = "K:fakeSkill"
	_s._equip_sys._eq_on_cast(u, e1)
	_ok("④b ★★真入口: 经 _eq_on_cast 排了 10 发(50 ÷ 5)",
		int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_planned", 0)) == 10,
		"planned=%d" % int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_planned", 0)))
	for _k in range(300):                                # 同步喂 3 秒(10 发 × 0.25 = 2.5 秒)
		_s._equip_sys._bow_sys.tick(0.01)
	var fired: int = int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_fired", 0))
	_ok("④b ★真的射出了 10 发(不多不少 · 全同步喂 tick, 不等演出)", fired == 10, "fired=%d" % fired)
	for _k2 in range(300):
		_s._equip_sys._bow_sys.tick(0.01)
	_ok("④b ★分母: 再喂 3 秒仍是 10 发(连射真的停了)",
		int((u["eq_state"].get("p2eq_076", {}) as Dictionary).get("volley_fired", 0)) == 10,
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
# ④c 076 偷龟能: 每穿一人偷 1/1/2 点, 双向(敌人真的少, 自己真的多)
# ═════════════════════════════════════════════════════════════
func _t076_steal() -> void:
	print("── ④c 076 · 每穿一人偷 1/1/2 点龟能(双向) ──")
	for si in range(3):
		var steal: float = float([1, 1, 2][si])
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
		_ok("④c si=%d 敌人被偷走 %.0f 点龟能(冷却往后推 %.4f 秒)" % [si, steal, steal * 0.075],
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
		var aabb: AABB = ring.get_aabb()
		var r_m: float = aabb.size.x * 0.5 * ring.scale.x
		var want_m: float = 400.0 * float(_s.WS)
		_ok("⑥ ★量真实节点: 落区环世界半径 %.4f m = 400 码 × WS = %.4f m" % [r_m, want_m],
			absf(r_m - want_m) < 0.01, "实测 %.5f 期望 %.5f" % [r_m, want_m])
		_ok("⑥ ★贴地: 环的顶点都在同一水平面(不是立起来的; 见 memory fb-axis-y-plus-rotation-cancels)",
			absf(ring.get_aabb().size.y) < 1e-4, "AABB.y=%.6f" % ring.get_aabb().size.y)

	## ③ 落箭: 数量对得上 · 全在 _world 里 · **起点高度 = 抛物线顶点**(量真实节点的 AABB)
	_s._battle_rng.seed = SEED
	var before_children: int = _s._world.get_child_count()
	var made_arrows: int = vfx.rain_arrows(Vector2(0.0, 0.0), 400.0, 7)
	_ok("⑥ 一跳箭雨真的建了 7 支落箭, 且都挂进了 _world",
		made_arrows == 7 and _s._world.get_child_count() - before_children == 7,
		"made=%d 新增子节点=%d" % [made_arrows, _s._world.get_child_count() - before_children])
	var arrow = _s._world.get_child(_s._world.get_child_count() - 1)
	if is_instance_valid(arrow) and arrow is MeshInstance3D:
		## 行程 run = 400×0.9 = 360 码 ⇒ 顶点 = lob_apex_px(720) = 720×tan60°/4 = 311.77 码
		## AABB 的最高点 = 抛物线顶点 + 光带半宽(2.4 码) —— 后者是几何厚度, 不是误差。
		## 行程 run = 400×0.9 = 360 码 ⇒ 顶点 = lob_apex_px(720) = 720×tan60°/4 = 311.769 码。
		var top_m: float = (arrow as MeshInstance3D).get_aabb().end.y
		var want_top: float = (720.0 * 1.7320508 * 0.25 + 2.4) * float(_s.WS)
		_ok("⑥ ★量真实节点: 落箭起点高 %.4f m = (抛物线顶点 311.769 + 光带半宽 2.4)×WS = %.4f m" % [top_m, want_top],
			absf(top_m - want_top) < 0.002, "实测 %.5f 期望 %.5f" % [top_m, want_top])
		_ok("⑥ ★分母: 落箭真的是【斜的】(水平行程 %.3f m > 0, 垂直掉下来会是 0)"
				% (arrow as MeshInstance3D).get_aabb().size.x,
			(arrow as MeshInstance3D).get_aabb().size.x > 0.1)

	## ④ 贯穿光迹: 2000 码长, 且**分段数 = 穿透点数 + 1**
	var tr = vfx.pierce_tracer(Vector2(-600.0, 0.0), Vector2.RIGHT, 2000.0, [0.25, 0.5])
	_ok("⑥ 贯穿光迹真的挂进了 _world",
		is_instance_valid(tr) and _s._world.is_ancestor_of(tr), str(tr))
	if is_instance_valid(tr):
		var len_m: float = tr.get_aabb().size.x
		var want_len: float = 2000.0 * float(_s.WS)
		_ok("⑥ ★量真实节点: 光迹世界长度 %.4f m = 2000 码 × WS = %.4f m" % [len_m, want_len],
			absf(len_m - want_len) < 0.05, "实测 %.5f 期望 %.5f" % [len_m, want_len])
		var mesh: ArrayMesh = tr.mesh
		## 三段(0→0.25→0.5→1.0) × 2 三角形 × 3 顶点 = 18 个顶点
		var vtx: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		_ok("⑥ 穿 2 人 ⇒ 光迹分成 3 段(18 个顶点), 每段一个亮度档", vtx == 18, "verts=%d" % vtx)

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

	## ② 骨甲片: 层数 = 节点数, 且每片都在 _world 里
	var b: Dictionary = _mk("fortune", "left", Vector2(-100.0, -200.0))
	var made: int = vfx.plates_refresh(b, 0.30, 12)
	var in_world := 0
	for p in b.get("_bone_plates", []):
		if is_instance_valid(p) and _s._world.is_ancestor_of(p):
			in_world += 1
	_ok("⑥ 骨甲 12 层 → 12 片甲, 且 12 片全在 _world 里",
		made == 12 and in_world == 12, "made=%d in_world=%d" % [made, in_world])
	## 壳半径按体积律涨: 8 倍护盾 ⇒ 半径 2 倍(量【真实节点到本体的距离】)
	var base_pos: Vector3 = _s._world_pos(b["pos"], 0.55)
	var d1: float = (b["_bone_plates"][0] as Node3D).position.distance_to(base_pos)
	vfx.plates_refresh(b, 0.30 * 8.0, 12)
	var d2: float = (b["_bone_plates"][0] as Node3D).position.distance_to(base_pos)
	_ok("⑥ ★量真实节点: 护盾 ×8 → 甲片离体距离 %.4f → %.4f, 比值 %.4f ≈ 2"
			% [d1, d2, d2 / maxf(1e-9, d1)],
		absf(d2 / maxf(1e-9, d1) - 2.0) < 0.02, "ratio=%.5f" % (d2 / maxf(1e-9, d1)))
	## 撤场: detach 后节点真的没了(换路自扫走的就是这条路)
	var freed: int = vfx.detach(b)
	_ok("⑥ ★撤场: detach 释放了 12 片甲, 且单位身上的引用被清干净",
		freed == 12 and not b.has("_bone_plates"), "freed=%d" % freed)
	_s._equip_sys._bow_sys.clear()
	_s._units.clear()
