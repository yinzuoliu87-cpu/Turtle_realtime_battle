extends Node
## verify_copy_effect.gd —— 龟壳「复制」抄来的技能按 60% 结算（2026-11-09）。
##
## 由来：交接 11-08 L 报「冰封 / 墨水炸弹没按 60% 结算；复制效果 60%→65% 掉血不变」。
##   整类探针 tests/probes/_probe_copy_ratio.gd 量出 81 个可抄技能里有伤害的 57 个，36 个复制后照样 100%。
##   原来 60%（龟壳 dmg_out_mult + battle._copy_fx_mult）只在 `_do_skill` 同步那一段生效，两个根因：
##   ① 延后结算（弹道 / sim 补间回调 / 不带 src 的延后子弹 / 协程 await 之后 / 施法者每帧状态 / 地面区域 /
##      装备批次自己的队列与波 / 追踪箭 / 盾到期爆裂 / 召唤物）结算那一刻倍率早已复位；
##   ② `_apply_damage`（DoT / 真伤那条路）从来不乘（CLAUDE.md §4.3 两条路都要改），诅咒也不缩。
##   修法：ShellSystem.ctx_capture / ctx_enter / ctx_exit —— 建的那一刻记下复制上下文，结算那一刻还原（同装备统计 tally）。
##
## 判据（需求原文的字面值：复制「以 60% 效果释放」，ShellSystem.COPY_EFFECT）：
##   每个技能两局：A = 走真入口 `_sk_shell_copy`（敌人身上只挂这一个技能 ⇒ 候选池确定）；B = 龟壳直接 `_do_skill`。
##   全新战斗场、同一随机种子、每帧恰一步 sim、同一窗口 ⇒ 敌人掉血 A / B = COPY_EFFECT（±0.05，整数取整误差）。
##   每种结算方式挑一个代表（下面 CASES 第二列），外加两个修之前就对的（同步段 / 带 src 的延后子弹）当对照。
## ★分母：每个技能直接放都要真打出伤害（B > 0），否则这条断言是空的。
## ★改坏验证（2026-11-09 做过）：去掉 battle_ballistics 弹道命中那段 ctx_enter ⇒ iceFreeze 比值回到 1.000 变红；
##   去掉 _apply_damage 那段乘法 ⇒ 下面「两条伤害路径」那条红(★basicChiWave 不走这条路, 拿它当代表打不红)；
##   去掉 _add_curse 缩时长 ⇒ ghostStorm 红；召唤物不写倍率 ⇒ pirateShipPassive 红；
##   朗姆酒每秒回血不乘倍率 ⇒ pirateRum 治疗 1.000 红；防守转治疗去掉 "_copy": null ⇒ hidingDefend 治疗 0.360 红。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_copy_effect.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")
const WINDOW := 300
const HP := 1.0e6
const SEED := 20261109
const TOL := 0.05

## [技能, 结算方式]
const CASES := [
	["bambooSpikes", "对照: 带 src 的延后子弹(修之前就对)"],
	["ninjaBackstab", "对照: 同步段(修之前就对)"],
	["iceFreeze", "弹道命中"],
	["lineInkBomb", "sim 补间回调"],
	["basicChiWave", "不带 src 的延后子弹(原来那条只认带 src 的)"],
	["ghostStorm", "诅咒(缩时长)"],
	["basicSlam", "协程 await 之后"],
	["diceFlashStrike", "施法者每帧状态"],
	["lavaQuake", "地面区域每跳"],
	["eqCrossSlash", "装备批次自己的队列 + 波"],
	["hunterBarrage", "追踪箭分支"],
	["bubbleShield", "盾到期爆裂"],
	["crystalBarrier", "盾破放的延后子弹"],
	["minionRocket", "延后子弹里起的协程"],
	["pirateShipPassive", "召唤物"],
]

## 护盾 / 治疗(规则「60% 效果 = 伤害 + 护盾 / 治疗 / DoT」的后两样; 2026-11-09 整类探针 tests/probes/_probe_copy_support):
##   [技能, 量哪样, 说明]。龟壳血量上限放大到 10 万、开局掉一半(第一版 412 血 ⇒ 朗姆酒两边都回满、比值被上限卡成 1)。
const SUPPORT := [
	["stoneRockShield", "shield", "对照: 施放时给盾(修之前就对)"],
	["pirateRum", "heal", "每帧回血(施放时定每秒回多少)"],
	["hidingDefend", "heal", "剩余护盾转治疗(护盾已打过折, 不许再折)"],
]

var _pass := 0
var _fail := 0


func _ok(name: String, cond: bool, info: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", name, ("  (" + info + ")") if info != "" else "")
	else:
		_fail += 1
		print("  FAIL  ", name, ("  (" + info + ")") if info != "" else "")


func _case(skill: String, copy: bool) -> float:
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	s._deterministic = true
	s._battle_rng.seed = SEED
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var sh: Dictionary = s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["energy"] = 0.0
	sh["crit"] = 0.0
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	foe["active_skills"] = [skill]
	foe["maxHp"] = HP
	foe["hp"] = HP
	foe["no_basic"] = true
	foe["no_move"] = true
	foe["energy"] = 0.0
	s._units.clear()
	s._units.append(sh)
	s._units.append(foe)
	s._over = false
	if copy:
		s._shell_sys._sk_shell_copy(sh, foe)
	else:
		s._do_skill(sh, foe, skill)
	for _i in range(WINDOW):
		await get_tree().process_frame
	var dmg: float = HP - float(foe["hp"])
	## 复制窗口外倍率必须复位: 龟壳 dmg_out_mult = 1、全局 _copy_fx_mult = 1(漏 exit 会让龟壳之后所有伤害都打六折)
	if copy and (float(sh.get("dmg_out_mult", 1.0)) != 1.0 or float(s._copy_fx_mult) != 1.0 or s._shell_sys.copy_src != null):
		dmg = -999.0
	s.queue_free()
	await get_tree().process_frame
	return dmg


## ★两条伤害路径各喂同一发名义伤害(CLAUDE.md §4.3): 龟壳 dmg_out_mult = 1 与 = COPY_EFFECT 各打一个全新的敌人,
##   掉血之比 = COPY_EFFECT。不依赖任何技能走哪条路(改坏验证时发现 basicChiWave 并不走 _apply_damage,
##   拿技能当代表守不住这一条)。
func _paths_check() -> void:
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	s._deterministic = true
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var sh: Dictionary = s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["crit"] = 0.0
	s._units.clear()
	s._units.append(sh)
	for path in ["_apply_damage_from(真伤)", "_apply_damage(真伤桶)"]:
		var got: Array = []
		for mult in [1.0, ShellSystem.COPY_EFFECT]:
			var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
			foe["maxHp"] = HP
			foe["hp"] = HP
			foe["dodge_bonus"] = 0.0
			s._units.append(foe)
			sh["dmg_out_mult"] = mult
			if path.begins_with("_apply_damage_from"):
				s._damage._apply_damage_from(sh, foe, 1000, Color.WHITE, 0.0, true)
			else:
				s._damage._apply_damage(foe, 1000, Color.WHITE, sh, "tru")
			got.append(HP - float(foe["hp"]))
		sh["dmg_out_mult"] = 1.0
		var r: float = (float(got[1]) / float(got[0])) if float(got[0]) > 0.0 else -1.0
		_ok("分母 %s 名义 1000 真打出伤害" % path, float(got[0]) > 0.0, "%.0f" % float(got[0]))
		_ok("★%s: 龟壳倍率 %s 时掉血之比 = %.3f" % [path, ShellSystem.COPY_EFFECT, r], absf(r - ShellSystem.COPY_EFFECT) <= 0.01,
			"%.0f → %.0f" % [float(got[0]), float(got[1])])
	s.queue_free()
	await get_tree().process_frame


func _case_support(skill: String, copy: bool) -> Dictionary:
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	s._deterministic = true
	s._battle_rng.seed = SEED
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var sh: Dictionary = s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["energy"] = 0.0
	sh["maxHp"] = 100000.0
	sh["hp"] = 50000.0
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	foe["active_skills"] = [skill]
	foe["maxHp"] = HP
	foe["hp"] = HP
	foe["no_basic"] = true
	foe["no_move"] = true
	foe["energy"] = 0.0
	s._units.clear()
	s._units.append(sh)
	s._units.append(foe)
	s._over = false
	var last := float(sh["hp"])
	if copy:
		s._shell_sys._sk_shell_copy(sh, foe)
	else:
		s._do_skill(sh, foe, skill)
	var shield_max := float(sh.get("shield", 0.0))
	var heal := 0.0
	for _i in range(WINDOW):
		await get_tree().process_frame
		shield_max = maxf(shield_max, float(sh.get("shield", 0.0)))
		var h := float(sh["hp"])
		if h > last:
			heal += h - last
		last = h
	s.queue_free()
	await get_tree().process_frame
	return {"shield": shield_max, "heal": heal}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 龟壳复制按 %s 结算 · %d 个技能 · 窗口 %d 帧 ===" % [ShellSystem.COPY_EFFECT, CASES.size(), WINDOW])
	var n_real := 0
	var n_run := 0
	var only := OS.get_environment("VCE_ONLY")   # 改坏验证时只跑指定的几个(逗号分隔)
	for cs in CASES:
		var sk: String = str(cs[0])
		if only != "" and not only.split(",").has(sk):
			continue
		n_run += 1
		_ok("%s 是可复制技能" % sk, CopyRules.can_copy(sk, RB._IMPL_SKILLS))
		var a: float = await _case(sk, true)
		var b: float = await _case(sk, false)
		_ok("分母 %s 直接放打出伤害" % sk, b > 0.0, "%.0f" % b)
		if b > 0.0:
			n_real += 1
		_ok("%s 放完复制窗口外倍率已复位" % sk, a != -999.0)
		var r: float = (a / b) if b > 0.0 else -1.0
		_ok("★%s · %s: 复制 / 直接 = %.3f ≈ %s" % [sk, str(cs[1]), r, ShellSystem.COPY_EFFECT],
			absf(r - ShellSystem.COPY_EFFECT) <= TOL, "复制 %.0f · 直接 %.0f" % [a, b])
	if only == "":
		_ok("分母: %d / %d 个技能直接放都打出了伤害" % [n_real, CASES.size()], n_real == CASES.size() and n_run == CASES.size())
	elif n_run > 0:
		_ok("分母: %d / %d 个技能直接放都打出了伤害" % [n_real, n_run], n_real == n_run)
	for cs in SUPPORT:
		var sk: String = str(cs[0])
		if only != "" and not only.split(",").has(sk):
			continue
		var a: Dictionary = await _case_support(sk, true)
		var b: Dictionary = await _case_support(sk, false)
		var key: String = str(cs[1])
		var r: float = (float(a[key]) / float(b[key])) if float(b[key]) > 0.5 else -1.0
		_ok("分母 %s 直接放真给了%s" % [sk, "盾" if key == "shield" else "治疗"], float(b[key]) > 0.5, "%.0f" % float(b[key]))
		_ok("★%s · %s: 复制 / 直接 %s = %.3f ≈ %s" % [sk, str(cs[2]), "盾" if key == "shield" else "治疗", r, ShellSystem.COPY_EFFECT],
			absf(r - ShellSystem.COPY_EFFECT) <= TOL, "复制 %.0f · 直接 %.0f" % [float(a[key]), float(b[key])])
	if only == "" or only.split(",").has("paths"):
		await _paths_check()
	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _pass)
	else:
		print("FAIL %d / %d" % [_fail, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)
