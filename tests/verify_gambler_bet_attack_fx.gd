extends Node
## verify_gambler_bet_attack_fx.gd —— 赌神龟: 多重打击与赌注的牌算作攻击, 触发攻击时 / 普攻命中的装备效果(2026-11-11)
##
## 用户 11-11:「多重打击能不能触发攻击特效？…白鲸气环的三环应该是能触发…它是被算作普通攻击，能够触发攻击特效…
##   鲨肝油的那个叠攻速，它这个也应该能触发…那这个七下和其他的多重打击是不是都应该能够触发攻击特效？啊，这个应该是能的呀」
##   ① 被动多重打击连出来的那一发(`_chained_atk`)是真普攻 ⇒ 065 鲨肝油 +1 层(原来就成立, 这里钉住)
##   ② 赌注的牌甩出 = 一次攻击 ⇒ 065 +1 层(`GamblerSystem.bet_card_on_throw`)
##   ③ 赌注的牌落地 as_attack ⇒ 063 白鲸气环给目标挂 1 层; 对照: 不算攻击的同一张牌不挂(分母: 证明闸门真的在起作用)
##   ④ 真入口 `_sk_gambler_bet`(多重打击关掉, 只有 7 张): 7 张牌甩完 ⇒ 065 正好 +7
##   ⑤ 源码: 赌注的牌不点剑士(bet_card_on_throw 里没有 swordsman); 补间回调与兜底都走 bet_card_land; 7 张与追加牌都传 as_attack = true
## 用户 11-11 追加「多重打击触发的攻击特效仅有百分之五十效果」(范围: 被动连击那几发 + 赌注里多重打击追加的牌; 数值减半, 触发与计数不打折):
##   ⑥ 被动连击那一发: 鲨肝油的攻速加成 = 平常的一半, 层数照 +1   ⑦ 那一发的弹道记录带 multi_fx = 0.5(命中时用), 平常的 = 1
##   ⑧ 赌注追加的牌: 攻速加成减半; 赌注本身那 7 张照满   ⑨ 白鲸气环: 多重打击那张牌引爆的伤害 ≈ 平常的一半, 环照样清零(触发不打折)
##   ⑩ 窗口收尾: _copy_fx_mult / dmg_out_mult 都回到 1
## 结算从演出里抽出来直接调(CLAUDE.md §4.5), 不等补间。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ID_RING := "p2eq_063"
const ID_OIL := "p2eq_065"

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(id: String, px: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, Vector2(px, 400.0))
	u["hp"] = 100000.0
	u["maxHp"] = 100000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["shield"] = 0.0
	u["dodge"] = 0.0
	u["no_move"] = true
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	return u


func _gambler() -> Dictionary:
	var g: Dictionary = _mk("gambler", 500.0, "left")
	g["equips"] = [{"id": ID_RING, "star": 1}, {"id": ID_OIL, "star": 1}]
	g["eq_state"] = {}
	g["multi_base"] = -9.0   # 多重打击关掉(概率 < 0): 只量这一张 / 这 7 张, 不让连锁的随机数混进计数
	return g


func _oil(u: Dictionary) -> int:
	return int((u["eq_state"].get(ID_OIL, {}) as Dictionary).get("oil_stacks", 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 赌神龟: 多重打击 / 赌注的牌算作攻击 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var gsys = _s._gambler_sys

	# ① 被动多重打击连出来的那一发 = 真普攻
	_s._units.clear()
	_s._pending_shots.clear()
	var g1 := _gambler()
	var t1: Dictionary = _mk("basic", 700.0, "right")
	_s._units.append(g1)
	_s._units.append(t1)
	g1["_chained_atk"] = true
	var o0 := _oil(g1)
	_s._basic_attack(g1, t1)
	_ok("① 被动多重打击连出来的那一发(_chained_atk)走普攻 ⇒ 鲨肝油 +1 层", _oil(g1) == o0 + 1, "%d → %d" % [o0, _oil(g1)])

	# ② 赌注的牌甩出 = 一次攻击
	_s._units.clear()
	_s._pending_shots.clear()
	var g2 := _gambler()
	var t2: Dictionary = _mk("basic", 700.0, "right")
	_s._units.append(g2)
	_s._units.append(t2)
	gsys.bet_card_on_throw(g2, t2)
	_ok("② 赌注的牌甩出 ⇒ 鲨肝油 +1 层(攻击时的装备钩子)", _oil(g2) == 1, str(_oil(g2)))

	# ③ 落地: 算攻击 ⇒ 白鲸气环挂环; 对照: 不算攻击 ⇒ 不挂
	var r0: int = int(t2.get("whale_rings", 0))
	gsys.bet_card_land(g2, t2, 10, Color.WHITE, false, false)
	var r_off: int = int(t2.get("whale_rings", 0))
	gsys.bet_card_land(g2, t2, 10, Color.WHITE, false, true)
	var r_on: int = int(t2.get("whale_rings", 0))
	_ok("③ 分母: 不算攻击的同一张牌 ⇒ 白鲸气环不挂(技能不施环, 08-11 规格)", r_off == r0, "%d → %d" % [r0, r_off])
	_ok("③ ★赌注的牌落地算攻击 ⇒ 白鲸气环给目标挂 1 层", r_on == r_off + 1, "%d → %d" % [r_off, r_on])
	_ok("③ 落地之后「算作普攻」的标记已清掉(不串到下一次伤害)", not bool(g2.get("_hit_as_basic", false)))

	# ④ 真入口: 放一次赌注, 7 张牌甩完 ⇒ 鲨肝油正好 +7
	_s._units.clear()
	_s._pending_shots.clear()
	var g4 := _gambler()
	var t4: Dictionary = _mk("basic", 700.0, "right")
	_s._units.append(g4)
	_s._units.append(t4)
	gsys._sk_gambler_bet(g4, t4)
	var queued: int = _s._pending_shots.size()
	for _k in range(80):
		_s._ballistics._step_pending_shots(0.05)
	_ok("④ 分母: 赌注排进 7 张牌", queued >= 7, str(queued))
	_ok("④ ★真入口: 7 张牌甩完 ⇒ 鲨肝油正好 +7(每张都算一次攻击)", _oil(g4) == 7, str(_oil(g4)))

	# ⑤ 源码
	var src := FileAccess.get_file_as_string("res://scripts/systems/skills/gambler_system.gd").replace("\r\n", "\n")
	var i0 := src.find("func bet_card_on_throw(")
	var i1 := src.find("\nfunc ", i0 + 5)
	var body := src.substr(i0, i1 - i0) if i0 >= 0 and i1 > i0 else ""
	_ok("⑤ 分母: 找到 bet_card_on_throw", body.length() > 50)
	_ok("⑤ ★赌注的牌不点剑士(08-03 连击不触发剑士)", body.find("swordsman") < 0 and body.find("_swordsman") < 0)
	_ok("⑤ 补间回调与无贴图兜底都走 bet_card_land(没有绕过它直接扣血的)",
		src.count("bet_card_land(u, tgt, dmg, dcol, is_true, as_attack, multi)") == 2 and src.find("_apply_damage_from(u, tgt, dmg, dcol, 0.0, is_true)\n\t\tif roll_multi") < 0)
	_ok("⑤ 7 张牌与多重打击追加的牌都传 as_attack = true(追加的牌另传 multi = true)",
		src.find("else 1, true, false, true)") > 0 and src.find("_gambler_throw_hit(u, tgt, bdmg, false, false, true, true)") > 0)

	_multi_fx_checks(gsys)

	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


func _aspd(u: Dictionary) -> float:
	return float(u.get("aspd_perm", 1.0))


func _multi_fx_checks(gsys) -> void:
	print("--- 多重打击的攻击特效按 %.0f%% ---" % (GamblerSystem.MULTI_FX * 100.0))
	var per: float = float(EqPotionBatch.OIL_ASPD_PER_HIT[0])
	# ⑥ ⑦ 被动连击那一发(真普攻入口)
	_s._units.clear()
	_s._pending_shots.clear()
	var g := _gambler()
	var t: Dictionary = _mk("basic", 700.0, "right")
	_s._units.append(g)
	_s._units.append(t)
	g["_chained_atk"] = false
	var a0 := _aspd(g)
	_s._basic_attack(g, t)
	var a1 := _aspd(g)
	var fx_norm: float = float((_s._projectiles.back() as Dictionary).get("multi_fx", -1.0)) if not _s._projectiles.is_empty() else -1.0
	g["_chained_atk"] = true
	_s._basic_attack(g, t)
	var a2 := _aspd(g)
	var fx_chain: float = float((_s._projectiles.back() as Dictionary).get("multi_fx", -1.0)) if not _s._projectiles.is_empty() else -1.0
	g["_chained_atk"] = false
	_ok("⑥ 分母: 平常那一发鲨肝油 +%.2f 攻速" % per, absf((a1 - a0) - per) < 1e-6, "%.4f" % (a1 - a0))
	_ok("⑥ ★被动连击那一发: 攻速加成 = 平常的一半", absf((a2 - a1) - per * GamblerSystem.MULTI_FX) < 1e-6, "%.4f" % (a2 - a1))
	_ok("⑥ 层数照样 +1(触发与计数不打折)", _oil(g) == 2, str(_oil(g)))
	_ok("⑦ 连击那一发的弹道记着 multi_fx = %.1f, 平常那一发 = 1" % GamblerSystem.MULTI_FX,
		absf(fx_chain - GamblerSystem.MULTI_FX) < 1e-6 and absf(fx_norm - 1.0) < 1e-6, "%.2f / %.2f" % [fx_chain, fx_norm])
	_ok("⑩ 窗口收尾: 效果系数与伤害系数都回到 1", absf(float(_s._copy_fx_mult) - 1.0) < 1e-9 and absf(float(g.get("dmg_out_mult", 1.0)) - 1.0) < 1e-9)

	# ⑧ 赌注: 追加的牌减半, 本身那 7 张照满
	var b0 := _aspd(g)
	gsys.bet_card_on_throw(g, t, false)
	var b1 := _aspd(g)
	gsys.bet_card_on_throw(g, t, true)
	var b2 := _aspd(g)
	_ok("⑧ 赌注本身的牌: 攻速加成照满", absf((b1 - b0) - per) < 1e-6, "%.4f" % (b1 - b0))
	_ok("⑧ ★赌注里多重打击追加的牌: 攻速加成减半", absf((b2 - b1) - per * GamblerSystem.MULTI_FX) < 1e-6, "%.4f" % (b2 - b1))

	# ⑨ 白鲸气环引爆: 伤害减半, 环照样清零
	var trig: int = int(EqSpiritBatch.RING_TRIGGER)
	t["hp"] = 100000.0
	t["whale_rings"] = trig - 1
	gsys.bet_card_land(g, t, 10, Color.WHITE, false, true, false)
	var drop_full: float = 100000.0 - float(t["hp"])
	var rings_full: int = int(t.get("whale_rings", -1))
	t["hp"] = 100000.0
	t["whale_rings"] = trig - 1
	gsys.bet_card_land(g, t, 10, Color.WHITE, false, true, true)
	var drop_half: float = 100000.0 - float(t["hp"])
	var rings_half: int = int(t.get("whale_rings", -1))
	_ok("⑨ 分母: 平常那张牌把满层环引爆了(掉血 %.0f > 牌本身 10)" % drop_full, drop_full > 20.0 and rings_full == 0, "rings=%d" % rings_full)
	_ok("⑨ ★多重打击那张牌: 引爆伤害 ≈ 平常的一半(牌本身 10 照满)", absf((drop_half - 10.0) - (drop_full - 10.0) * GamblerSystem.MULTI_FX) <= 1.5,
		"引爆 %.0f vs %.0f" % [drop_half - 10.0, drop_full - 10.0])
	_ok("⑨ 环照样清零(触发不打折)", rings_half == 0, str(rings_half))
	_ok("⑩ 落地之后多重打击标记已清掉", absf(float(g.get("_multi_fx_hit", 1.0)) - 1.0) < 1e-9 and absf(float(_s._copy_fx_mult) - 1.0) < 1e-9)
