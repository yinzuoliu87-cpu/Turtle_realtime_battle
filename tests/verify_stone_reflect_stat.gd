extends Node
## verify_stone_reflect_stat.gd — 石头龟坚壁(2026-10-07 用户改数值)+「反伤属性」口径
##
## 用户原话:「被动改为每2秒获得额外10%护甲，至多获得100%额外护甲。获得相当于2%+0.1%护甲+0.1%魔抗的反伤」
##          「所以明白吗，这个是属于反伤的属性了」
## ⇒ 坚壁的反弹就是【反伤属性】: 信息面板「反伤」一栏显示的数 == 结算时真正弹回去的比例。
## 判据全部量真对象:
##   ① 面板(_info_stat_tiles 那一格) 的反伤 == StoneSystem.reflect_of(u) == 2% + 0.1%×护甲 + 0.1%×魔抗
##   ② 真打一下: 攻击者被弹回的伤害 == int(受到伤害 × 反伤属性)
##   ③ 真跑被动 tick: 每 2 秒护甲 +10% 开局护甲, 涨到 +100% 封顶; 反伤随护甲一起涨
##   ④ 非石头龟不吃这一份(反伤属性只等于通用 reflect)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const InfoPanel := preload("res://scripts/scenes/battle/info_panel.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _reflect_tile(ip, u: Dictionary) -> String:
	for r in ip._info_stat_tiles(u):
		if str((r as Array)[1]) == "反伤":
			return str((r as Array)[2])
	return "(没有反伤这一格)"


func _ready() -> void:
	await get_tree().process_frame
	print("=== 石头龟坚壁 + 反伤属性 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var ip = InfoPanel.new(s)
	var st: Dictionary = s._spawn._make_unit("stone", "left", c)
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(60, 0))
	s._units.clear()
	s._units.append(st)
	s._units.append(foe)
	s._edit_mode = false
	s._over = false

	# ── ① 面板 == 公式 ──
	var d0: float = float(st["def"])
	var m0: float = float(st["mr"])
	var want: float = 0.02 + 0.001 * d0 + 0.001 * m0
	_ok("★分母: 石头龟开局有护甲与魔抗", d0 > 0.0 and m0 > 0.0, "def=%.1f mr=%.1f" % [d0, m0])
	_ok("★★反伤属性 == 2% + 0.1%×护甲 + 0.1%×魔抗", absf(StoneSystem.reflect_of(st) - want) < 1e-6,
		"%.4f vs %.4f" % [StoneSystem.reflect_of(st), want])
	var tile := _reflect_tile(ip, st)
	_ok("★★信息面板「反伤」一格显示的就是它(不是 0%)", tile == ip._pct(want), "%s vs %s" % [tile, ip._pct(want)])

	# ── ② 真打一下, 弹回去的 == int(伤害 × 反伤属性) ──
	st["shield"] = 0.0
	## ★反伤不暴击(用户 2026-10-07「改为不能吧」): 把石头龟暴击率拉满, 弹回去的仍须恰好是比例 —— 会暴击的话这条必红。
	st["crit"] = 1.0
	var hp_f0: float = float(foe["hp"])
	var hp_s0: float = float(st["hp"])
	var dmg := 300   # ★别打死: 石头龟 1008 血, 打死时掉血被血量截住, 量不出实际吃到多少
	s._damage._apply_damage_from(foe, st, dmg, Color.WHITE)
	var got: float = hp_f0 - float(foe["hp"])
	_ok("★分母: 石头龟真吃到了这一下", float(st["hp"]) < float(st["maxHp"]))
	## ★按石头龟【实际吃到】的那一下算: 攻击者是小龟, 它的「不屈」按目标稀有度增伤(C +20%), 实际吃到的不是 1000。
	var taken: float = hp_s0 - float(st["hp"])
	_ok("★★攻击者被弹回的伤害 == int(实际吃到的伤害 × 反伤属性)", absf(got - float(int(taken * want))) <= 1.0,
		"taken=%.0f got=%.1f want=%d" % [taken, got, int(taken * want)])

	# ── ③ 被动 tick: 每 2 秒 +10% 开局护甲, 至多 +100% ──
	var base0: float = float(st["base_def"])
	var r_before: float = StoneSystem.reflect_of(st)
	st["_ptimer"] = 0.0
	s._tick_periodic_passive(st, 1.9)
	_ok("★1.9 秒: 还没涨", absf(float(st["base_def"]) - base0) < 1e-6, "%.2f" % float(st["base_def"]))
	s._tick_periodic_passive(st, 0.2)
	_ok("★★满 2 秒: 护甲 + 开局护甲×10%", absf(float(st["base_def"]) - base0 * 1.1) < 1e-4,
		"%.3f vs %.3f" % [float(st["base_def"]), base0 * 1.1])
	_ok("★★护甲涨了 ⇒ 反伤属性跟着涨", StoneSystem.reflect_of(st) > r_before,
		"%.4f → %.4f" % [r_before, StoneSystem.reflect_of(st)])
	for i in range(30):
		s._tick_periodic_passive(st, 2.0)
	_ok("★★至多 +100%: 封顶在开局护甲 ×2", absf(float(st["base_def"]) - base0 * 2.0) < 1e-4,
		"%.3f vs %.3f" % [float(st["base_def"]), base0 * 2.0])

	# ── ④ 非石头龟只有通用反伤 ──
	foe["reflect"] = 0.07
	_ok("★别的龟: 反伤属性 == 通用 reflect(不吃坚壁那一份)", absf(StoneSystem.reflect_of(foe) - 0.07) < 1e-9)

	# ── ⑤ 015 荆棘海胆(4 费): 反伤属性含它那一份, 弹一次、不暴击 ──
	##   015 有专属分支自己发反伤(累计 thorn_accum), 通用结算不含它 ⇒ 面板读 reflect_of, 结算各走各的。
	var h: Dictionary = s._spawn._make_unit("ninja", "left", c + Vector2(0, 400))
	var a: Dictionary = s._spawn._make_unit("ninja", "right", c + Vector2(60, 400))
	h["equips"] = [{"id": "p2eq_015", "star": 1}]
	s._equip_sys._stats._eq_apply_one_stats(h, "p2eq_015", 1)
	s._equip_sys._stats._eq_apply_flags(h, "p2eq_015", 1)
	s._units.append(h)
	s._units.append(a)
	var th: float = float(s._equip_sys.THORN_REFLECT[0])
	_ok("★分母: 015 装上了(eq_state 有 reflect_pct)", absf(StoneSystem.reflect_of(h) - th) < 1e-9,
		"%.3f vs %.3f" % [StoneSystem.reflect_of(h), th])
	_ok("★★信息面板「反伤」一格含 015 那一份(不是 0%)", _reflect_tile(ip, h) == ip._pct(th), _reflect_tile(ip, h))
	_ok("★通用结算那一份不含 015(否则弹两次)", absf(StoneSystem.reflect_generic(h)) < 1e-9)
	h["crit"] = 1.0
	h["shield"] = 0.0
	var ah0: float = float(a["hp"])
	var hh0: float = float(h["hp"])
	s._damage._apply_damage_from(a, h, 300, Color.WHITE, 0.0, false, false, false, true, false, true)
	var taken_h: float = hh0 - float(h["hp"])
	var back: float = ah0 - float(a["hp"])
	_ok("★分母: 015 携带者真吃到了这一下", taken_h > 0.0, "%.0f" % taken_h)
	_ok("★★015: 弹回去的 == int(实际吃到 × 12%) —— 只弹一次、暴击率拉满也不暴击",
		absf(back - float(int(taken_h * th))) <= 1.0, "taken=%.0f back=%.0f want=%d" % [taken_h, back, int(taken_h * th)])

	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
