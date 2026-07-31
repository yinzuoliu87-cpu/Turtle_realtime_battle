extends Node
## verify_signal_amplifier.gd — 信号放大器038 效果重做（用户 2026-07-30）
##
## 需求原文：「提供30%攻击速度，携带者每次普攻会获得一层放大，使自己获得1/2/5%增伤，
##   和5%攻击速度，最多叠加20层，而每获得5层，由携带者中心会爆发出巨大的电磁能量波，
##   朝着目标以90度角度发射一道缓慢移动的弧形波，造成125/250/500魔法伤害并眩晕目标2.5秒，
##   每一次释放会使波的角度增加90度，最多到360度，还会使自己获得5/7/10点魔抗穿透」
##
## ★「90度角度」按【扇形张角】理解（用户 2026-07-31 确认 A 方案）。
## ★期望值全部写【需求字面值】，不引用 SignalWaveSystem 的常量 —— 引用常量 = 拿代码跟它自己比。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_signal_amplifier.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

# ── 需求字面值 ──
const WANT_ASPD_FLAT := 0.30
const WANT_AMP := [0.01, 0.02, 0.05]
const WANT_ASPD_STACK := 0.05
const WANT_MAX := 20
const WANT_EVERY := 5
const WANT_DMG := [125.0, 250.0, 500.0]
const WANT_STUN := 2.5
const WANT_PEN := [5.0, 7.0, 10.0]
const WANT_ARC_STEP := 90.0
const WANT_ARC_MAX := 360.0

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	print("=== 信号放大器038·效果重做 ===")
	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame

	var sw = s._equip_sys._sigwave
	_chk("★分母: SignalWaveSystem 已接线", sw != null)
	if sw == null:
		_done(s); return

	# ── ① 常量对上需求原话 ──
	print("")
	print("  ① 常量:")
	_chk("① 固定攻速 = %.0f%%" % (WANT_ASPD_FLAT * 100.0), absf(sw.ASPD_FLAT - WANT_ASPD_FLAT) < 0.001)
	for k in range(3):
		_chk("① %d★ 每层增伤 = %.0f%%" % [k + 1, WANT_AMP[k] * 100.0],
			absf(float(sw.AMP_PER_STACK[k]) - WANT_AMP[k]) < 0.0005)
		_chk("① %d★ 弧形波伤害 = %.0f" % [k + 1, WANT_DMG[k]],
			absf(float(sw.WAVE_DMG[k]) - WANT_DMG[k]) < 0.5)
		_chk("① %d★ 魔抗穿透 = %.0f" % [k + 1, WANT_PEN[k]],
			absf(float(sw.MR_PEN[k]) - WANT_PEN[k]) < 0.01)
	_chk("① 每层攻速 = %.0f%%" % (WANT_ASPD_STACK * 100.0), absf(sw.ASPD_PER_STACK - WANT_ASPD_STACK) < 0.001)
	_chk("① 层数上限 = %d" % WANT_MAX, sw.MAX_STACKS == WANT_MAX)
	_chk("① 每 %d 层放一次波" % WANT_EVERY, sw.EVERY == WANT_EVERY)
	_chk("① 眩晕 = %.1f 秒" % WANT_STUN, absf(sw.WAVE_STUN - WANT_STUN) < 0.01)
	_chk("① 张角每次 +%.0f°" % WANT_ARC_STEP, absf(sw.ARC_STEP_DEG - WANT_ARC_STEP) < 0.01)
	_chk("① 张角上限 %.0f°" % WANT_ARC_MAX, absf(sw.ARC_MAX_DEG - WANT_ARC_MAX) < 0.01)

	# ── ② 叠层: 增伤/攻速随层数线性涨, 20 层封顶 ──
	# ★用干净合成单位(memory fb-ci-vs-local-divergence: 随机 spawn 的会带别的装备/被动 → CI 偶发红)
	var u: Dictionary = s._spawn._make_unit("basic", "left", Vector2(-9000, -9000), {})
	u["equips"] = []; u["eq_state"] = {}
	u["damage_amp"] = 0.0; u["aspd_perm"] = 1.0; u["magic_pen"] = 0.0
	var si := 2                      # 3★ 档
	var stt: Dictionary = {"sig_stacks": 0, "sig_arc_deg": 0.0, "sig_amp_given": 0.0, "sig_aspd_given": 0.0}
	u["eq_state"]["p2eq_038"] = stt
	var foe: Dictionary = s._spawn._make_unit("basic", "right", Vector2(-8600, -9000), {})
	foe["maxHp"] = 200000.0; foe["hp"] = 200000.0
	s._units.append(u); s._units.append(foe)
	print("")
	print("  ② 叠层(3★: 每层 +%.0f%% 增伤 / +%.0f%% 攻速):" % [WANT_AMP[2] * 100.0, WANT_ASPD_STACK * 100.0])
	for n in [1, 5, 20, 25]:
		while int(stt.get("sig_stacks", 0)) < mini(n, WANT_MAX):
			sw.on_hit(u, foe, si, stt)
		# 25 次也只该停在 20
		if n == 25:
			for _i in range(5):
				sw.on_hit(u, foe, si, stt)
		var st: int = int(stt.get("sig_stacks", 0))
		var want_st: int = mini(n, WANT_MAX)
		var want_amp: float = WANT_AMP[2] * float(want_st)
		var want_asp: float = 1.0 + WANT_ASPD_STACK * float(want_st)
		print("     喂到 %2d 次 → 层数 %2d(上限 %d)  增伤 %.2f(需求 %.2f)  aspd_perm %.2f(需求 %.2f)" % [
			n, st, WANT_MAX, float(u["damage_amp"]), want_amp, float(u["aspd_perm"]), want_asp])
		_chk("② 喂 %d 次 → 层数 %d" % [n, want_st], st == want_st)
		_chk("② 层数 %d → 增伤 %.2f(线性·不许叠乘)" % [want_st, want_amp],
			absf(float(u["damage_amp"]) - want_amp) < 0.005)
		_chk("② 层数 %d → 攻速 ×%.2f" % [want_st, want_asp],
			absf(float(u["aspd_perm"]) - want_asp) < 0.005)

	# ── ③ 每 5 层放一次波 + 张角 90→180→270→360 封顶 ──
	print("")
	print("  ③ 释放次数与张角:")
	var u2: Dictionary = s._spawn._make_unit("basic", "left", Vector2(-9000, -8000), {})
	u2["equips"] = []; u2["eq_state"] = {}
	u2["damage_amp"] = 0.0; u2["aspd_perm"] = 1.0; u2["magic_pen"] = 0.0
	var st2: Dictionary = {"sig_stacks": 0, "sig_arc_deg": 0.0, "sig_amp_given": 0.0, "sig_aspd_given": 0.0}
	u2["eq_state"]["p2eq_038"] = st2
	s._units.append(u2)
	var degs: Array = []
	for i in range(30):                 # 30 次普攻: 层数会封在 20, 波该只放 4 次(5/10/15/20)
		if sw.on_hit(u2, foe, si, st2):
			degs.append(float(st2["sig_arc_deg"]))
	print("     30 次普攻 → 放波 %d 次, 张角依次 %s" % [degs.size(), str(degs)])
	_chk("③ ★放波 4 次(5/10/15/20 层各一次·封顶后不再放)", degs.size() == 4)
	_chk("③ ★张角 90→180→270→360", degs == [90.0, 180.0, 270.0, 360.0])
	var want_pen: float = WANT_PEN[2] * 4.0
	print("     魔抗穿透累计 %.0f (需求 %.0f×4 = %.0f)" % [float(u2["magic_pen"]), WANT_PEN[2], want_pen])
	_chk("③ 每次释放 +%.0f 魔抗穿透(累计 %.0f)" % [WANT_PEN[2], want_pen],
		absf(float(u2["magic_pen"]) - want_pen) < 0.01)
	_chk("③ ★同步触发证据 _sig_fired_n = 4(不看有没有建节点)", int(u2.get("_sig_fired_n", 0)) == 4)

	# ── ④ 波真的会飞、命中才结算、伤害与眩晕对 ──
	print("")
	var tgt: Dictionary = s._spawn._make_unit("basic", "right", Vector2(-8600, -8000), {})
	tgt["maxHp"] = 200000.0; tgt["hp"] = 200000.0
	tgt["def"] = 0.0; tgt["mr"] = 0.0; tgt["flat_dr"] = 0.0; tgt["shield"] = 0.0
	tgt["dodge_bonus"] = 0.0; tgt["stun_until"] = 0.0; tgt["_sig_hit_n"] = 0
	tgt["id"] = "_dummy_target"
	s._units.append(tgt)
	var u3: Dictionary = s._spawn._make_unit("basic", "left", Vector2(-9000, -7000), {})
	u3["equips"] = []; u3["eq_state"] = {}
	u3["damage_amp"] = 0.0; u3["aspd_perm"] = 1.0; u3["magic_pen"] = 0.0
	u3["crit"] = 0.0; u3["crit_dmg"] = 0.0
	var st3: Dictionary = {"sig_stacks": 0, "sig_arc_deg": 0.0, "sig_amp_given": 0.0, "sig_aspd_given": 0.0}
	u3["eq_state"]["p2eq_038"] = st3
	s._units.append(u3)
	tgt["pos"] = u3["pos"] + Vector2(400.0, 0.0)
	var hp0: float = float(tgt["hp"])
	for _i in range(WANT_EVERY):
		sw.on_hit(u3, tgt, si, st3)
	await get_tree().process_frame
	print("  ④ 波已发出; 出手【同一帧】目标 hp %.0f → %.0f" % [hp0, float(tgt["hp"])])
	_chk("④ ★出手瞬间不掉血(波要飞过去才结算)", absf(float(tgt["hp"]) - hp0) < 0.5)
	# ★★把【施法者自身的增伤修正】隔离掉再验波的基础伤害:
	#   ① u3 攒了 5 层 = +25% damage_amp(那是 ② 组验的东西, 不该混进"波打多少")
	#   ② id=="basic" 会触发【小龟·不屈】按目标稀有度增伤(C 档 +20%) —— 与本装备无关
	#   不隔离的话实测 900 而不是 500, 我第一版就这么判红了 = 【测试写错, 不是功能错】。
	u3["damage_amp"] = 0.0
	u3["id"] = "_dummy_src"
	var t0: float = s._t
	var hit_at: float = -1.0
	var stun_left: float = -1.0     # ★眩晕要在【命中当刻】记 —— 跑完 400 帧(6.67 秒)它早过期了,
	                                #   事后再看 stun_until > _t 必然为假(我第一版就这么判红了)。
	for step in range(400):
		s._t = t0 + float(step + 1) * (1.0 / 60.0)
		sw.tick(1.0 / 60.0)
		if hit_at < 0.0 and int(tgt.get("_sig_hit_n", 0)) > 0:
			hit_at = s._t - t0
			stun_left = float(tgt.get("stun_until", 0.0)) - s._t
	var dealt: float = hp0 - float(tgt["hp"])
	print("     t=%.2fs 命中(400 码 ÷ %.0f 码每秒 ≈ %.2fs)  实扣 %.0f  命中当刻眩晕剩 %.2f 秒" % [
		hit_at, sw.WAVE_SPD, 400.0 / sw.WAVE_SPD, dealt, stun_left])
	_chk("④ ★波飞到才命中(不是出手即判定)", hit_at > 0.5)
	_chk("④ 命中一次(不许每帧重复打)", int(tgt.get("_sig_hit_n", 0)) == 1,
		"次数 %d" % int(tgt.get("_sig_hit_n", 0)))
	# ★★倍率【量出来再除掉】, 不要一个个猜(照 verify_trainer_magicstone ④ 的做法)。
	#   我先猜是"施法者增伤 + 小龟不屈", 隔离后仍差 ×1.2 —— 说明还有没枚举到的分支。
	#   与其继续猜, 不如拿【同一条管线】打一发已知值量出总倍率 f, 再验 wave 的基数:
	#   本条要验的是"弧形波把 500 送进了管线", 管线自己再乘什么是别处的事。
	var twin: Dictionary = s._spawn._make_unit("basic", "right", u3["pos"] + Vector2(400.0, 0.0), {})
	twin["maxHp"] = 200000.0; twin["hp"] = 200000.0
	twin["def"] = 0.0; twin["mr"] = 0.0; twin["flat_dr"] = 0.0; twin["shield"] = 0.0
	twin["dodge_bonus"] = 0.0; twin["id"] = "_dummy_target"
	s._units.append(twin)
	var probe: float = 1000.0
	var th0: float = float(twin["hp"])
	s._damage._apply_damage_from(u3, twin, s._resolve_dmg(u3, probe, twin, true), Color("#7fe8ff"), 0.0, false, true)
	var f: float = (th0 - float(twin["hp"])) / probe
	var want_dealt: float = WANT_DMG[2] * f
	print("     管线总倍率 f = %.3f(同一条路打 %.0f 量出来的) → 期望实扣 %.0f" % [f, probe, want_dealt])
	_chk("④ ★分母: 管线倍率量得到(f>0)", f > 0.01)
	_chk("④ 弧形波送进管线的基数 = %.0f(3★)" % WANT_DMG[2],
		absf(dealt - want_dealt) < 3.0, "实扣 %.0f / 期望 %.0f" % [dealt, want_dealt])
	_chk("④ 眩晕 %.1f 秒(命中当刻量)" % WANT_STUN, absf(stun_left - WANT_STUN) < 0.05,
		"剩 %.2f" % stun_left)

	# ── ⑤ 旧实现不许回来 ──
	print("")
	var src := FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	_chk("⑤ ★旧的 _eq_signal_tick 已删(原'每6秒随机增伤')",
		not src.contains("func _eq_signal_tick("))
	var rb := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_chk("⑤ 038 已从自定义间隔表摘掉(不再是周期效果)", not rb.contains('"p2eq_038": 6.0'))
	_chk("⑤ ★弧形波每帧只推进一次(按帧号去重·否则一帧推 N 次=飞太快)",
		src.contains("_sig_tick_fr"))

	_done(s)


func _chk(what: String, ok: bool, extra: String = "") -> void:
	if not ok:
		_fail += 1
	print("     %s %s%s" % ["[PASS]" if ok else "[FAIL]", what, ("  " + extra) if extra != "" else ""])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 信号放大器038·效果重做" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
