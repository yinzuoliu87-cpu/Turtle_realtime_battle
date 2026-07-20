extends Node
## verify_sudden_death.gd — 守卫「战场决胜」机制 + 龟蛋数值（用户 2026-07-19 定的规则）
##
## 为什么必须守：这两块改坏了【不会报错、不会卡死】，只会悄悄改变平衡，
## 靠跑压测和看日志都发现不了。T4 测试覆盖盘点时发现它们在裸奔。
##
## 决胜规则（用户拍板）：本战场开打满 40 秒 → 治疗效果 ×50%，之后每 5 秒全场累计 +25% 增伤，
##   持续到本战场结束。★计时按【战场】各自算，不能用全局 _t（_t 跨路累加不重置）。
## 龟蛋（用户拍板）：生命 3000+300×等级 / 双抗 60+15×等级 / 围栏额外 +200 / 决胜期每秒自损 5% 最大生命。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame

	# ── A. 决胜常量 = 用户拍板值 ──
	_ok("SD_START = 40 秒", is_equal_approx(RTScene.SD_START, 40.0), "%.1f" % RTScene.SD_START)
	_ok("SD_STEP = 5 秒", is_equal_approx(RTScene.SD_STEP, 5.0), "%.1f" % RTScene.SD_STEP)
	_ok("SD_AMP_PER = +25%/档", is_equal_approx(RTScene.SD_AMP_PER, 0.25), "%.2f" % RTScene.SD_AMP_PER)
	_ok("SD_HEAL_MULT = 治疗×50%", is_equal_approx(RTScene.SD_HEAL_MULT, 0.5), "%.2f" % RTScene.SD_HEAL_MULT)

	# ── B. 档位随时间推进 ──
	s._sd_t0 = 0.0
	s._sd_stacks = 0
	s._over = false
	for t in [10.0, 39.9]:
		s._t = t; s._sd_tick()
	_ok("40 秒前不进入决胜", s._sd_stacks == 0, "档=%d" % s._sd_stacks)
	_ok("40 秒前治疗不打折", is_equal_approx(s._sd_heal_mult(), 1.0))

	s._t = 40.0; s._sd_tick()
	_ok("★满 40 秒 → 第 1 档 (+25%)", s._sd_stacks == 1 and is_equal_approx(s._sd_amp(), 0.25), "档=%d 增伤=%.2f" % [s._sd_stacks, s._sd_amp()])
	_ok("★进入决胜 → 治疗 ×50%", is_equal_approx(s._sd_heal_mult(), 0.5))

	s._t = 45.0; s._sd_tick()
	_ok("45 秒 → 第 2 档 (+50%)", s._sd_stacks == 2 and is_equal_approx(s._sd_amp(), 0.5), "档=%d 增伤=%.2f" % [s._sd_stacks, s._sd_amp()])
	s._t = 60.0; s._sd_tick()
	_ok("60 秒 → 第 5 档 (+125%)", s._sd_stacks == 5 and is_equal_approx(s._sd_amp(), 1.25), "档=%d 增伤=%.2f" % [s._sd_stacks, s._sd_amp()])

	# ── C. ★按战场计时, 不是按局 ──
	# _t 跨路累加不重置。换路时 _dl_start_fight 会重置 _sd_t0 —— 这条错了会导致下路一开场就进决胜。
	s._sd_t0 = 120.0     # 模拟: 下路在全局 _t=120 时开打
	s._sd_stacks = 0
	s._t = 150.0         # 全局 130+ 但本战场才 30 秒
	s._sd_tick()
	_ok("★换路后按本战场计时(本场30秒→不该进决胜)", s._sd_stacks == 0,
		"_t=150 _sd_t0=120 → 本场30秒, 档=%d" % s._sd_stacks)
	s._t = 160.0         # 本战场满 40 秒
	s._sd_tick()
	_ok("★本战场满40秒才进决胜", s._sd_stacks == 1, "档=%d" % s._sd_stacks)

	# ── D. 龟蛋数值 ──
	_ok("围栏额外双抗 = 200", is_equal_approx(RTScene.EGG_FENCE_RES, 200.0), "%.0f" % RTScene.EGG_FENCE_RES)
	_ok("决胜自损间隔 = 1 秒", is_equal_approx(RTScene.EGG_SELFLOSS_IV, 1.0), "%.1f" % RTScene.EGG_SELFLOSS_IV)
	_ok("决胜自损 = 5% 最大生命", is_equal_approx(RTScene.EGG_SELFLOSS_PCT, 0.05), "%.2f" % RTScene.EGG_SELFLOSS_PCT)

	var lvl := 8
	var egg: Dictionary = s._make_unit("__egg__", "left", Vector2(0, 0),
		{"egg": true, "egg_side": "left", "level": lvl, "hp": 5400.0, "hp_max": 3000.0 + 300.0 * lvl})
	var want_res: float = 60.0 + 15.0 * float(lvl) + RTScene.EGG_FENCE_RES
	_ok("★Lv%d 蛋围栏内双抗 = 60+15×等级+200" % lvl,
		is_equal_approx(float(egg["def"]), want_res) and is_equal_approx(float(egg["mr"]), want_res),
		"def=%.0f mr=%.0f 期望 %.0f" % [float(egg["def"]), float(egg["mr"]), want_res])
	_ok("蛋免控(_eggImmune)", egg.get("_eggImmune", false))
	_ok("蛋不可移动/不普攻", egg.get("no_move", false) and egg.get("no_basic", false))

	print("ALL PASS — 战场决胜 + 龟蛋数值" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
