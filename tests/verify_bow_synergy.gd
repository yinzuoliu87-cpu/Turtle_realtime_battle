extends Node
## verify_bow_synergy.gd — 弓箭羁绊【处决 / 腐蚀穿透 / 腐蚀叠层】(用户 2026-08-03 定)
##
## ★三条的作用域【各不相同】, 这是最容易看错也最容易实现错的地方:
##   处决 = 全队(用户改, 原规格是"携带弓箭者") · 穿透 = 全队 · 腐蚀叠层 = 全场敌人
##
## ★弓箭【不给暴伤】(用户定) ⇒ 属性档是全表最弱的(顶档带3件 DPS 仅 ×1.33),
##   强度全压在这三条机制上。所以这三条的断言比别的类型更要紧。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BOW := preload("res://scripts/systems/equip/bow_synergy_system.gd")

var _n := 0
var _fail := 0
var _scene
func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new(); add_child(s); _scene = s
	await get_tree().process_frame; await get_tree().process_frame
	var BW := _ids("弓箭", 9)
	_ok("★分母: 找到 %d 件弓箭" % BW.size(), BW.size() >= 9)
	print("=== 弓箭羁绊 ===")

	# ── ① 腐蚀·穿透: 全队(不带弓箭的也吃), 且档1没有 ──
	for cfg in [[3, 0.04], [6, 0.10], [9, 0.22]]:
		var team_n: int = int(cfg[0])
		var me := _mk("left", [])            # ★本龟【不带弓箭】—— 验"全队"
		var units: Array = [me]
		var k := 0
		while k < team_n:
			units.append(_mk("left", BW.slice(k, mini(k + 3, team_n)))); k += 3
		units.append(_mk("right", []))
		_run(s, units)
		_ok("① 弓箭 %d 件: 不带弓箭的队友也吃 %.0f%% 穿透(全队)" % [team_n, float(cfg[1]) * 100.0],
			absf(float(me.get("armor_pen_pct", 0.0)) - float(cfg[1])) < 0.001,
			"实得 %.2f" % float(me.get("armor_pen_pct", 0.0)))
		if team_n == 9:
			_ok("① 魔抗穿透与护甲穿透同值(%.0f%%)" % (float(cfg[1])*100.0), absf(float(me.get("magic_pen_pct", 0.0)) - float(cfg[1])) < 0.001, "实得 %.2f" % float(me.get("magic_pen_pct", 0.0)))
			_ok("① ★敌方【不】吃我方的穿透", absf(float(units[units.size()-1].get("armor_pen_pct", 0.0))) < 0.001)

	# ── ② 处决: ★全队(用户改), 斩杀线按各自暴击率 ──
	var arch := _mk("left", BW.slice(0, 3))      # 带 3 件弓箭
	var mate := _mk("left", [])                  # 不带弓箭的队友
	var t1 := _mk("right", []); var t2 := _mk("right", [])
	_run(s, [arch, mate, _mk("left", BW.slice(3, 6)), _mk("left", BW.slice(6, 9)), t1, t2])
	arch["crit"] = 0.66                          # 顶档带3件的暴击
	mate["crit"] = 0.0
	# 斩杀线: arch = 10% + 6.6% = 16.6% / mate = 10%
	t1["hp"] = t1["maxHp"] * 0.12                # 12% 血: arch 能处决, mate 不能
	s._bow_syn.on_hit(mate, t1)
	_ok("② ★不带弓箭的队友也有处决, 但线是基数 10%%(12%% 血 → 杀不掉)",
		t1.get("alive", false), "存活=%s" % str(t1.get("alive", false)))
	s._bow_syn.on_hit(arch, t1)
	_ok("② ★★带3件弓箭者线是 16.6%%(12%% 血 → 处决)", not t1.get("alive", true),
		"存活=%s" % str(t1.get("alive", true)))
	t2["hp"] = t2["maxHp"] * 0.08                # 8% 血: mate 也能杀
	s._bow_syn.on_hit(mate, t2)
	_ok("② ★★8%% 血时【不带弓箭的队友】也能处决 —— 这就是改成全员的意义",
		not t2.get("alive", true), "存活=%s" % str(t2.get("alive", true)))
	# 对照: 未激活时谁都不处决
	var lone := _mk("left", BW.slice(0, 2))
	var lt := _mk("right", [])
	_run(s, [lone, lt])
	lt["hp"] = lt["maxHp"] * 0.01
	s._bow_syn.on_hit(lone, lt)
	_ok("② ★对照: 只有 2 件弓箭(未达首档) → 1%% 血也不处决", lt.get("alive", false))

	# ── ③ 腐蚀叠层: ★【三档都有】(用户 2026-08-03 定, 回到原设计的形状) ──
	#   每层 +2/3/4% 受伤 · 满 5 层转真伤 10/20/35% —— 数值随【施加方】的档位变。
	for cfg in [[3, 1, 0.02, 0.10], [6, 2, 0.03, 0.20], [9, 3, 0.04, 0.35]]:
		var tn: int = int(cfg[0])
		var foe := _mk("right", [])
		var ally := _mk("left", [])
		var arr: Array = [ally, foe]
		var kk := 0
		while kk < tn:
			arr.append(_mk("left", BW.slice(kk, mini(kk + 3, tn)))); kk += 3
		_run(s, arr)
		s._bow_syn.clear()
		for _i in range(8):
			s._bow_syn._t_corrode = 0.0
			s._bow_syn.tick(2.6)
		_ok("③ 弓箭 %d 件: 敌人叠满 5 层(封顶)" % tn, int(foe.get("corrode_stacks", 0)) == 5,
			"实得 %d" % int(foe.get("corrode_stacks", 0)))
		_ok("③ 弓箭 %d 件: 记下施加方档位 %d" % [tn, int(cfg[1])],
			int(foe.get("corrode_tier", 0)) == int(cfg[1]), "实得 %d" % int(foe.get("corrode_tier", 0)))
		_ok("③ 弓箭 %d 件: 每层 +%.0f%% → 5 层 = ×%.2f" % [tn, float(cfg[2]) * 100.0, 1.0 + 5.0 * float(cfg[2])],
			absf(BOW.vuln_mult(foe) - (1.0 + 5.0 * float(cfg[2]))) < 0.001, "实得 ×%.2f" % BOW.vuln_mult(foe))
		_ok("③ 弓箭 %d 件: 满层转真伤 %.0f%%" % [tn, float(cfg[3]) * 100.0],
			absf(BOW.true_share(foe) - float(cfg[3])) < 0.001, "实得 %.2f" % BOW.true_share(foe))
		_ok("③ ★弓箭 %d 件: 我方一层都不吃" % tn, int(ally.get("corrode_stacks", 0)) == 0,
			"实得 %d" % int(ally.get("corrode_stacks", 0)))
		if tn == 9:
			foe["corrode_stacks"] = 4
			_ok("③ ★对照: 4 层【不】转真伤(必须满 5 层)", absf(BOW.true_share(foe)) < 0.001)
	# 对照: 未激活(2件)一层都不叠
	var nb := _mk("left", BW.slice(0, 2))
	var nf := _mk("right", [])
	_run(s, [nb, nf])
	s._bow_syn.clear()
	s._bow_syn._t_corrode = 0.0
	s._bow_syn.tick(2.6)
	_ok("③ ★对照: 只有 2 件弓箭(未达首档) → 一层都不叠",
		int(nf.get("corrode_stacks", 0)) == 0, "实得 %d" % int(nf.get("corrode_stacks", 0)))

	s._units.clear(); s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 弓箭羁绊" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _ids(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if _scene.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == t:
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n: break
	return out

func _run(s, units: Array) -> void:
	s._units.clear(); s._units.append_array(units)
	s._synergy._by_side = {"left": {}, "right": {}}
	s._synergy.apply_all()
	s._bow_syn.apply_all()

func _mk(side: String, ids: Array) -> Dictionary:
	var c: Vector2 = _scene.ARENA.position + _scene.ARENA.size * 0.5
	var off := Vector2(-200.0, 0.0) if side == "left" else Vector2(200.0, 0.0)
	var u: Dictionary = _scene._spawn._make_unit("green", side, c + off)
	u["maxHp"] = 1000.0; u["hp"] = 1000.0; u["shield"] = 0.0
	u["crit"] = 0.0; u["armor_pen_pct"] = 0.0; u["magic_pen_pct"] = 0.0
	u["corrode_stacks"] = 0
	var e: Array = []
	for i in ids: e.append({"id": str(i), "star": 1})
	u["equips"] = e; u["eq_state"] = {}
	return u
