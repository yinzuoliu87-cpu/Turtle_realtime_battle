extends Node
## verify_shield_shockwave_no_recursion.gd — 盾羁绊【怒气冲击波】双方互弹不再无限递归
##
## ★由来(2026-11-01, 方案书 20261031e R6 记下、本次修):
##   冲击波 = 自身最大生命 × 4/6/8% 的真伤, 走 `_apply_damage_from(..., raw=true)` 且 from_equip 缺省 false
##   ⇒ `_post_hit_hooks` 把它当成一次普通受击, 回调对面的 `_shield_syn.on_damaged` ⇒ 对面攒怒气。
##   单发 ≥ 阈值 400(顶档 8% × 最大生命 ≥ 5000)时, 对面挨一发就回敬一发, 一路互弹。
##   而【阵亡】要等 `_apply_damage_from` 末尾的 `_kill` 才落地 —— 在嵌套的受击钩子里,
##   血已经是 0 的单位 `alive` 还是 true ⇒ 链永远不会因为有人死了而停下。
##   探针(tests/probes/_probe_shield_wave_recursion.gd)实测: 1v1 · 6000 血 · 一下 400 的普攻
##   ⇒ 同步引出 350 发冲击波、嵌套 292 层、`Stack overflow`; 5v5 同条件一帧双方全灭。
## ★修法: 冲击波打出去的那一段【不给挨打的那一方攒怒气】(反击照旧) —— 与「反伤不触发反伤」、
##   圣光反击 from_equip=true 同一口径; 单边盾羁绊时挨打方没有档位, 本来就不攒, 数值一个不变。
##
## 三段:
##   ① 双方顶档 + 高血(>5000): 一下普攻精确算账 —— 只放 1 发(大伤害 3 发), 对面不回敬, 没人死
##   ② 单边盾羁绊(正常情况): 一串普攻逐下核对 发数 / 敌掉血 / 自得护盾 / 怒气余数 == 文案公式
##   ③ 双方顶档 + 高血 真打 600 步: 每步伤害调用数与冲击波数都有界, 双方都真的放过冲击波
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shield_shockwave_no_recursion.tscn --quit-after 3000

## 文案字面量(phase2_types.gd 盾羁绊三档 · 2026-08-03 用户定), 不读被测常量
const TXT_THRESHOLD := 400.0
const TXT_PCT := [0.04, 0.06, 0.08]
const TXT_SHIELD_FROM_DMG := 0.20
const CODE_CAP := 5            # 一次受击最多放 5 发(`_rage` 的 fired < 5, 防一次超大伤害刷出一串)


## 只数数的壳: 每次 `_shockwave` 被调就记一笔, 然后原样交给产品代码(不改任何行为)。
class CountShield extends ShieldSynergySystem:
	var waves := 0
	var by_side := {"left": 0, "right": 0}

	func _shockwave(u: Dictionary, tier: int):
		waves += 1
		var sd: String = str(u.get("side", ""))
		by_side[sd] = int(by_side.get(sd, 0)) + 1
		return super._shockwave(u, tier)


var _s = null
var _n := 0
var _fail := 0
var _orig_syn = null


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _mk(side: String, i: int, hp: float) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var x: float = -120.0 - 60.0 * float(i) if side == "left" else 120.0 + 60.0 * float(i)
	## ★green: 没有全局改伤害的被动(不用 basic —— 小龟【不屈】按稀有度增伤, 同 verify_shield_synergy)
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2(x, 40.0 * float(i)))
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["no_move"] = true
	u["no_basic"] = true
	u["equips"] = []
	u["eq_state"] = {}
	u["_shield_rage"] = 0.0
	_s._units.append(u)
	return u


func _setup(tier_l: int, tier_r: int) -> CountShield:
	_s._units.clear()
	_s._pending_shots.clear()
	_s._adf_ct = 0
	_s._synergy._by_side = {"left": ({"盾": tier_l} if tier_l > 0 else {}), "right": ({"盾": tier_r} if tier_r > 0 else {})}
	var cs := CountShield.new(_s)
	_s._shield_syn = cs
	return cs


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 盾羁绊冲击波: 双方互弹不递归 ===")
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	_orig_syn = _s._shield_syn

	_t2_single_side_numbers()      # 先跑正常情况: 修前修后都能跑完, 指纹可直接对比
	_t1_double_side_exact()
	await _t3_real_fight()

	_s._shield_syn = _orig_syn
	_s._synergy._by_side = {"left": {}, "right": {}}
	print("")
	if _n < 30:
		_fail += 1
		print("  [FAIL] ★分母: 断言只有 %d 条(<30) —— 有整段被跳过了" % _n)
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


# ── ① 双方顶档 + 高血: 一下普攻, 精确算账 ──
func _t1_double_side_exact() -> void:
	print("── ① 双方顶档盾羁绊 · 最大生命 > 5000: 一下普攻只引出一轮 ──")
	# 1v1 · 6000 血: 一发冲击波 480 ≥ 400(原触发条件)
	var cs := _setup(3, 3)
	var a: Dictionary = _mk("left", 0, 6000.0)
	var b: Dictionary = _mk("right", 0, 6000.0)
	var wave: int = int(6000.0 * float(TXT_PCT[2]))
	_ok("★分母: 一发冲击波 %d ≥ 阈值 %.0f(正是原来会互弹的条件)" % [wave, TXT_THRESHOLD], float(wave) >= TXT_THRESHOLD)
	_s._damage._apply_damage_from(a, b, 400, Color.WHITE)
	_ok("★★1v1 6000 血: 一下 400 只放 1 发冲击波(实测 %d; 修前 350 发、栈溢出)" % cs.waves, cs.waves == 1)
	_ok("★★右方放的那一发打到左方: 左掉 %.0f == 一发 %d" % [6000.0 - float(a["hp"]), wave],
		absf((6000.0 - float(a["hp"])) - float(wave)) < 0.5)
	_ok("★★左方不回敬: 右只掉普攻那 400(实测 %.0f, 护盾 %.1f)" % [6000.0 - float(b["hp"]), float(b["shield"])],
		absf((6000.0 - float(b["hp"])) - 400.0) < 0.5)
	_ok("★★冲击波那一段不给挨打方攒怒气: 左怒气 %.1f == 0" % float(a.get("_shield_rage", -1.0)),
		absf(float(a.get("_shield_rage", -1.0))) < 0.01)
	_ok("右方怒气 400 - 400 = 0(实测 %.1f)" % float(b.get("_shield_rage", -1.0)),
		absf(float(b.get("_shield_rage", -1.0))) < 0.01)
	_ok("右方护盾 = 冲击波 × 20%% = %.1f(实测 %.1f)" % [float(wave) * TXT_SHIELD_FROM_DMG, float(b["shield"])],
		absf(float(b["shield"]) - float(wave) * TXT_SHIELD_FROM_DMG) < 0.01)
	_ok("两边都活着(修前一帧双双阵亡)", bool(a["alive"]) and bool(b["alive"]))
	_ok("★本帧伤害调用只有 2 次(普攻 + 冲击波; 实测 %d, 修前 292)" % int(_s._adf_ct), int(_s._adf_ct) == 2)

	# 正常受击照样攒: 左方挨一下普攻 400 ⇒ 放 1 发, 右方同样不回敬
	_s._adf_ct = 0
	var ahp: float = float(a["hp"])
	var bhp: float = float(b["hp"])
	var bsh: float = float(b["shield"])
	_s._damage._apply_damage_from(b, a, 400, Color.WHITE)
	_ok("★对照: 左方挨【普攻】400 照样放冲击波(累计 %d 发)" % cs.waves, cs.waves == 2)
	_ok("对照: 右方挨那一发 %d(先吃护盾 %.1f; 实测 有效生命掉 %.1f)" % [wave, bsh, (bhp + bsh) - (float(b["hp"]) + float(b["shield"]))],
		absf(((bhp + bsh) - (float(b["hp"]) + float(b["shield"]))) - float(wave)) < 0.5)
	_ok("对照: 左方只掉普攻 400(实测 %.0f)" % (ahp - float(a["hp"])), absf((ahp - float(a["hp"])) - 400.0) < 0.5)
	_ok("对照: 右方挨冲击波不攒怒气(%.1f)" % float(b.get("_shield_rage", -1.0)), absf(float(b.get("_shield_rage", -1.0))) < 0.01)

	# 一次大伤害: 1200 ⇒ 放 3 发(「用 while 不用 if」那条规矩不受影响), 对面一发不回
	cs = _setup(3, 3)
	a = _mk("left", 0, 6000.0)
	b = _mk("right", 0, 6000.0)
	_s._damage._apply_damage_from(a, b, 1200, Color.WHITE)
	_ok("★大伤害: 一下 1200 放 3 发(实测 %d)" % cs.waves, cs.waves == 3)
	_ok("大伤害: 左掉 3 × %d = %d(实测 %.0f)" % [wave, wave * 3, 6000.0 - float(a["hp"])],
		absf((6000.0 - float(a["hp"])) - float(wave * 3)) < 0.5)
	_ok("大伤害: 右只掉 1200(实测 %.0f)" % (6000.0 - float(b["hp"])), absf((6000.0 - float(b["hp"])) - 1200.0) < 0.5)

	# 5v5 · 12000 血: 一发 960 ⇒ 修前一次回敬 2 发、一帧双方全灭
	cs = _setup(3, 3)
	var L: Array = []
	var R: Array = []
	for i in range(5):
		L.append(_mk("left", i, 12000.0))
		R.append(_mk("right", i, 12000.0))
	var w12: int = int(12000.0 * float(TXT_PCT[2]))
	_s._damage._apply_damage_from(L[0], R[0], 400, Color.WHITE)
	var alive := 0
	var lost_other := 0.0
	for u in L + R:
		if u["alive"]:
			alive += 1
		if not is_same(u, L[0]) and not is_same(u, R[0]):
			lost_other += 12000.0 - float(u["hp"])
	_ok("★★5v5 12000 血: 一下 400 只放 1 发(实测 %d; 修前 977 发)" % cs.waves, cs.waves == 1)
	_ok("★★5v5: 10 只全活着(实测 %d; 修前一帧全灭)" % alive, alive == 10)
	_ok("5v5: 左0 掉一发 %d(实测 %.0f), 其余 8 只没被波及(%.0f)" % [w12, 12000.0 - float(L[0]["hp"]), lost_other],
		absf((12000.0 - float(L[0]["hp"])) - float(w12)) < 0.5 and lost_other < 0.5)
	_ok("5v5: 本帧伤害调用 2 次(实测 %d)" % int(_s._adf_ct), int(_s._adf_ct) == 2)


# ── ② 单边盾羁绊: 一串普攻逐下核对(正常情况数值与修前逐数相同) ──
func _t2_single_side_numbers() -> void:
	print("── ② 单边盾羁绊(正常情况): 逐下 发数 / 敌掉血 / 自得护盾 / 怒气余数 ──")
	var hits: Array = [150, 300, 399, 1, 1200, 2500, 37, 400, 799]
	var fp: Array = []
	var checked := 0
	for tier in [1, 2, 3]:
		for mhp in [2000.0, 6000.0]:
			var cs := _setup(0, tier)
			var atk: Dictionary = _mk("left", 0, 900000.0)
			var me: Dictionary = _mk("right", 0, mhp)
			me["hp"] = mhp * 100.0     # 打不死: 只看冲击波账
			var wave: int = maxi(1, int(mhp * float(TXT_PCT[tier - 1])))
			var acc := 0.0
			var bad := ""
			for h in hits:
				me["shield"] = 0.0     # 每下清盾: 护盾只来自这一下放的冲击波
				var w0: int = cs.waves
				var a0: float = float(atk["hp"])
				_s._damage._apply_damage_from(atk, me, int(h), Color.WHITE)
				acc += float(h)
				var want_n := 0
				while acc >= TXT_THRESHOLD and want_n < CODE_CAP:
					acc -= TXT_THRESHOLD
					want_n += 1
				var got_n: int = cs.waves - w0
				var got_loss: float = a0 - float(atk["hp"])
				var got_sh: float = float(me["shield"])
				var got_acc: float = float(me.get("_shield_rage", -1.0))
				fp.append("%d/%d/%.0f/%.1f/%.0f" % [int(h), got_n, got_loss, got_sh, got_acc])
				checked += 1
				if got_n != want_n or absf(got_loss - float(want_n * wave)) > 0.5 \
						or absf(got_sh - float(want_n) * float(wave) * TXT_SHIELD_FROM_DMG) > 0.01 \
						or absf(got_acc - acc) > 0.01:
					bad += " [档%d 血%.0f 挨%d: 发 %d/%d 敌掉 %.0f/%d 盾 %.1f 怒 %.0f/%.0f]" % [tier, mhp, int(h),
						got_n, want_n, got_loss, want_n * wave, got_sh, got_acc, acc]
			_ok("档 %d · 最大生命 %.0f: %d 下普攻逐下 == 文案公式(一发 %d)" % [tier, mhp, hits.size(), wave], bad == "", bad)
	_ok("★分母: 核对了 %d 下(3 档 × 2 种血量 × %d 下)" % [checked, hits.size()], checked == 3 * 2 * hits.size())
	print("  单边指纹: %s" % " ".join(fp))


# ── ③ 双方顶档 + 高血, 真打 600 步 ──
func _t3_real_fight() -> void:
	print("── ③ 双方顶档 · 最大生命 8000 · 3v3 真打 600 步 ──")
	var cs := _setup(3, 3)
	var all: Array = []
	for i in range(3):
		for sd in ["left", "right"]:
			var u: Dictionary = _mk(sd, i, 8000.0)
			u["no_move"] = false
			u["no_basic"] = false
			u["atk"] = 160.0
			all.append(u)
	var max_adf := 0
	var max_wave_step := 0
	var steps := 0
	var hit_steps := 0
	for _k in range(600):
		var w0: int = cs.waves
		_s._sim_step(_s.SIM_DT, false, false)
		steps += 1
		max_adf = maxi(max_adf, int(_s._adf_ct))
		var dw: int = cs.waves - w0
		max_wave_step = maxi(max_wave_step, dw)
		if int(_s._adf_ct) > 0:
			hit_steps += 1
		for u in all:      # 保持两边都活着, 一直打满 600 步(只补血不碰怒气/护盾)
			if u["alive"] and float(u["hp"]) < 4000.0:
				u["hp"] = 8000.0
	var dead := 0
	for u in all:
		if not u["alive"]:
			dead += 1
	print("    实测: %d 步 · 有伤害的步 %d · 冲击波 左 %d / 右 %d · 单步最多 %d 发 · 单步伤害调用最多 %d · 阵亡 %d"
		% [steps, hit_steps, int(cs.by_side["left"]), int(cs.by_side["right"]), max_wave_step, max_adf, dead])
	_ok("★分母: 真打了(有伤害的步 %d ≥ 20; 修后实测 35, 修前打到第 9 步就全灭)" % hit_steps, hit_steps >= 20)
	_ok("★分母: 两边都真的放过冲击波(左 %d / 右 %d)" % [int(cs.by_side["left"]), int(cs.by_side["right"])],
		int(cs.by_side["left"]) > 0 and int(cs.by_side["right"]) > 0)
	_ok("★★单步冲击波 ≤ 6 发(实测 %d; 修前一下普攻就 350 发)" % max_wave_step, max_wave_step <= 6)
	_ok("★★单步伤害调用 ≤ 30 次(实测 %d; 修前 292 层嵌套)" % max_adf, max_adf <= 30)
	_ok("没有人在一帧里被互弹打死(阵亡 %d)" % dead, dead == 0)
	await get_tree().process_frame
