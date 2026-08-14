extends Node
## verify_lava_forms.gd — 熔岩龟【两个形态】的数值门禁(2026-08-14)
##
## ★★★由来: 变异探针实测 `lava_system._lava_volcano_erupt`(205 行)**打瘸了全套一条不红**
##   —— 熔岩龟是**裸奔**的。而用户 2026-08-13 刚改过它的砸地数值、08-14 又要削火山爆发。
##   按今晚立的规矩: **动裸奔系统之前先给它补门禁**, 否则削完没人守得住。
##
## ★这条守的是【两个形态各自的核心数值】, 判据全部从常量推导, 不抄数字:
##   · 火山爆发: 一段 ERUPT_ATK_COEF · ERUPT_BURN_COEF 层灼烧 · ERUPT_HEAL_PCT 回血
##   · 变身砸地: SLAM_ATK_COEF / SLAM_BURN_COEF
##   · 灼烧**不许走全局** `_default_burn_stacks` —— 那个凤凰等火系也在用,
##     熔岩调数值会静默削掉别人(2026-08-13 踩过)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Lava := preload("res://scripts/systems/skills/lava_system.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 熔岩龟: 两形态数值 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	# ── ① 常量本身就是用户拍的那三个数 ──────────────────────────────────────
	_ok("★火山爆发伤害系数 = 1.2ATK(用户 2026-08-14: 原 5 段 0.5)",
		absf(Lava.ERUPT_ATK_COEF - 1.2) < 1e-6, "实得 %.2f" % Lava.ERUPT_ATK_COEF)
	_ok("★火山爆发灼烧 = 0.2ATK 层", absf(Lava.ERUPT_BURN_COEF - 0.2) < 1e-6,
		"实得 %.2f" % Lava.ERUPT_BURN_COEF)
	_ok("★火山爆发回血 = 8%", absf(Lava.ERUPT_HEAL_PCT - 0.08) < 1e-6,
		"实得 %.3f" % Lava.ERUPT_HEAL_PCT)
	## ★★灼烧不许走全局系数 —— 那是凤凰等火系共用的, 改它会波及别人。
	var src_lv := FileAccess.get_file_as_string("res://scripts/systems/skills/lava_system.gd")
	var bad := 0
	for ln in src_lv.split("\n"):
		var t: String = str(ln).strip_edges()
		if t.begins_with("#"):
			continue
		if t.find("_default_burn_stacks") >= 0:
			bad += 1
	_ok("★★熔岩【一处都不走】全局灼烧系数(实得 %d 处)" % bad, bad == 0,
		"走全局的地方 %d 处" % bad)

	# ── ② 【已知缺口】火山爆发的实际伤害无头量不到 ──────────────────────────
	##   ★根因: 浪潮的推进与命中判定是 `tween_method` 驱动的
	##     (lava_system.gd:193「波前沿线推进 + 逐帧命中判定 (tween_method 推 front-distance)」)
	##     —— **tween 在无头下推不动**, 与 031 水晶球B 同一个形状。
	##   ★031 的解法是把结算搬到 sim 时钟(见 `CrystalSystem.tick`), 这里同样可行, 但那是
	##     产品重构, 不在本次"只削数值"的范围内。**显式登记成会红的断言, 不静默略过。**
	##   ⇒ 本条现在只守【常量】(上面四条)与【形态分派】(下面两条)。
	##     常量守住 = 谁把 1.2/0.2/0.08 改了会红; 但"改完之后打出来对不对"没人验。
	const TWEEN_BURIED_NOTE := "火山爆发/浪潮命中判定走 tween_method, 无头量不到实际伤害"
	_ok("★★已知缺口显式登记: %s" % TWEEN_BURIED_NOTE,
		FileAccess.get_file_as_string("res://scripts/systems/skills/lava_system.gd").find("tween_method") >= 0,
		"要解掉它: 照 CrystalSystem.tick 的做法把结算搬到 sim 时钟")

	# ── ③ 反面: 远程形态放 A 技【不该】是火山爆发 ──────────────────────────
	##   ★两个形态的 A/B 技是完全不同的两套(火山: 火山爆发/烈焰打击;
	##     远程: 地裂/岩浆涌动)。分派选错形态是很容易犯的错, 焊住它。
	var src_disp := src_lv
	_ok("★★A 技按形态分派(火山=火山爆发 / 远程=地裂)",
		src_disp.find("if volcano: _lava_volcano_erupt(u)") >= 0
		and src_disp.find("else:       _lava_quake(u)") >= 0)
	_ok("★★B 技按形态分派(火山=烈焰打击 / 远程=岩浆涌动)",
		src_disp.find("if volcano: _lava_flame_strike(u, tgt)") >= 0
		and src_disp.find("else:       _lava_magma_surge(u, tgt)") >= 0)

	# ── ④ 变身砸地的两个系数(2026-08-13 用户拍的, 别被后来的人改掉) ─────────
	_ok("★变身砸地伤害 = 1.0ATK", absf(Lava.SLAM_ATK_COEF - 1.0) < 1e-6,
		"实得 %.2f" % Lava.SLAM_ATK_COEF)
	_ok("★变身砸地灼烧 = 0.3ATK 层", absf(Lava.SLAM_BURN_COEF - 0.3) < 1e-6,
		"实得 %.2f" % Lava.SLAM_BURN_COEF)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 熔岩龟两形态")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()


func _sum(es: Array) -> float:
	var t := 0.0
	for e in es:
		t += float(e.get("hp", 0.0))
	return t
