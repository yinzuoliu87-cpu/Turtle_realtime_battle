extends Node
## verify_bomb_items.gd —— 炸弹 10 件 + 剑 2 费武士刀 逐件结算（2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md §4.2 / §4.3）
##
## 只验结算（不依赖演出）：干净合成单位（护甲 / 魔抗 / 减伤 / 闪避 0，出手方暴击 0），时钟手动推进 `_t`，
##   直接调批系统的 tick_unit / tick / on_basic / on_death / on_spawn。数字一律从 EqBombBatch 常量算期望值。
## 判据（每件至少一条「数对」、一条「边界外不触发」）：
##   097 3★ 必触发；目标 100 码内的敌人挨 70% 攻击力；150 码外的不挨
##   098 第 6 秒炸：120 码内挨（70+20% 攻击力）、被击飞；自己得 250 盾；5.9 秒还没炸
##   099 第 6 秒扔、0.6 秒后落：挨（280+60% 攻击）、护甲 −30，4 秒后护甲还原
##   100 烟里的友军被设成不可选中（最近敌人选不到它）；它一普攻就现形并追加（160+50% 攻击）真伤
##   101 目标先减速 40%；2 秒后炸（120+30% 攻击）；粘液 1.5 秒内叠 3 次 18 层中毒
##   102 登场埋 5 颗；敌人踩上去 ⇒ 320 物理 + 眩晕 0.8 秒；空中单位不踩
##   103 阵亡 ⇒ 250 码内挨 80% 自身最大生命；300 码外不挨
##   104 第 1 颗（900+100% 攻击）；第 2 颗 ×1.1；跨路（单位重建、同一身份键）继续叠；一局结束清零
##   105 召唤 10000 血炮筒；每炮 +8 龟能；满 100 进重炮；重炮每发净 −2；重炮直线击退 + 50 层流血
##   106 召唤 12000 血、200 双抗；被打死 ⇒ 600 码内挨 2000 物理 + 携带者 20% 最大生命真伤 + 120 层流血；3★ 不衰减，1★ 每秒 −10%
##   107 召唤 2700 血小将；三次剑气波、第四次蓄力 1.5 秒回 15% 最大生命后吹 3 道龙卷风击飞 1 秒
##   同名两件：两份各自计时（两颗手雷）
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const B := preload("res://scripts/systems/equip/eq_bomb_batch.gd")

var _n := 0
var _fail := 0
var _s
var _bs


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, pos: Vector2, ids: Array = [], star: int = 3, hp: float = 100000.0, atk: float = 100.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("green", side, pos)
	u["maxHp"] = hp
	u["hp"] = hp
	u["atk"] = atk
	u["base_atk"] = atk
	for k in ["shield", "flat_dr", "def", "base_def", "mr", "base_mr", "crit", "dodge", "armor_pen", "armor_pen_pct",
			"magic_pen", "magic_pen_pct", "damage_reduction", "damage_amp", "def_shred", "tenacity"]:
		u[k] = 0.0
	u["airborne"] = false
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": star})
	u["equips"] = eq
	u["eq_state"] = {}
	return u


func _c() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


## 清场 + 放单位
func _place(units: Array) -> void:
	_bs.clear_all()
	_s._units.clear()
	_s._units.append_array(units)


## 推进 sec 秒（0.05 一步）：携带者 tick_unit + 全局 tick
func _adv(sec: float, carriers: Array = []) -> void:
	var steps := int(round(sec / 0.05))
	for i in range(steps):
		_s._t = float(_s._t) + 0.05
		for u in carriers:
			_bs.tick_unit(u, 0.05)
		_bs.tick(0.05)


func _lost(u: Dictionary) -> float:
	return float(u["maxHp"]) - float(u["hp"])


func _near(a: float, b: float, tol: float = 1.5) -> bool:
	return absf(a - b) <= tol


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_bs = _s._equip_sys._bomb_sys
	_s._t = 1000.0
	print("=== 炸弹 10 件 + 武士刀 逐件结算 ===")
	var c := _c()

	## ── 097 鞭炮 ──
	var me := _mk("left", c + Vector2(-100, 0), ["p2eq_097"])
	var t1 := _mk("right", c + Vector2(100, 0))
	var t2 := _mk("right", c + Vector2(100, 90))
	var t3 := _mk("right", c + Vector2(100, 150))
	_place([me, t1, t2, t3])
	_bs.on_basic(me, t1, "p2eq_097", 2)
	var w97: float = float(B.CRACKER_ATK[2]) * 100.0
	_ok("097 3★ 必触发：目标与 100 码内挨 %.0f；150 码外不挨" % w97,
		_near(_lost(t1), w97) and _near(_lost(t2), w97) and _lost(t3) == 0.0, "%.0f / %.0f / %.0f" % [_lost(t1), _lost(t2), _lost(t3)])
	var cnt := 0
	for i in range(200):
		t1["hp"] = t1["maxHp"]
		_bs.on_basic(me, t1, "p2eq_097", 0)
		if _lost(t1) > 0.0:
			cnt += 1
	_ok("097 1★ 触发率约 40%%（200 次 %d 次）" % cnt, cnt > 55 and cnt < 105)

	## ── 098 爆竹筒 ──
	me = _mk("left", c + Vector2(-50, 0), ["p2eq_098"])
	t1 = _mk("right", c + Vector2(50, 0))
	t2 = _mk("right", c + Vector2(200, 0))
	_place([me, t1, t2])
	_adv(5.9, [me])
	_ok("098 5.9 秒还没炸", _lost(t1) == 0.0)
	_adv(0.15, [me])
	var w98: float = float(B.TUBE_FLAT[2]) + B.TUBE_ATK * 100.0
	_ok("098 第 6 秒：120 码内挨 %.0f、被击飞；250 码外不挨" % w98, _near(_lost(t1), w98) and bool(t1["airborne"]) and _lost(t2) == 0.0,
		"%.0f air %s / %.0f" % [_lost(t1), str(t1["airborne"]), _lost(t2)])
	_ok("098 自己得 %.0f 盾" % float(B.TUBE_SHIELD[2]), _near(float(me["shield"]), float(B.TUBE_SHIELD[2])), "盾 %.0f" % float(me["shield"]))

	## ── 099 手雷 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_099"])
	t1 = _mk("right", c + Vector2(100, 0))
	t2 = _mk("right", c + Vector2(130, 30))
	_place([me, t1, t2])
	_adv(6.0 + B.GRENADE_FLY + 0.1, [me])
	var w99: float = float(B.GRENADE_FLAT[2]) + B.GRENADE_ATK * 100.0
	_ok("099 第 6 秒扔、落地：挨 %.0f；护甲 −%.0f" % [w99, float(B.GRENADE_SHRED[2])],
		_near(_lost(t1), w99) and _near(_lost(t2), w99) and _near(float(t1["def"]), -float(B.GRENADE_SHRED[2])),
		"%.0f / %.0f · 护甲 %.1f" % [_lost(t1), _lost(t2), float(t1["def"])])
	_adv(B.GRENADE_SHRED_SEC + 0.1, [])
	_ok("099 4 秒后护甲还原", _near(float(t1["def"]), 0.0, 0.01), "护甲 %.1f" % float(t1["def"]))

	## ── 100 烟雾弹 ──
	me = _mk("left", c + Vector2(-50, 0), ["p2eq_100"])
	var al := _mk("left", c + Vector2(-50, 60))
	var far := _mk("left", c + Vector2(-400, 0))
	t1 = _mk("right", c + Vector2(50, 0))
	_place([me, al, far, t1])
	_adv(8.0 + B.SMOKE_PULSE + 0.1, [me])
	_ok("100 烟里的友军不可选中、烟外的可以", _s._is_untargetable(al) and _s._is_untargetable(me) and not _s._is_untargetable(far),
		"al %s me %s far %s" % [str(_s._is_untargetable(al)), str(_s._is_untargetable(me)), str(_s._is_untargetable(far))])
	var nb = _s._targeting._nearest_enemy(t1)
	_ok("100 敌人选最近目标选不到烟里的（只能选烟外的）", nb is Dictionary and is_same(nb, far))
	_s._equip_sys._eq_on_basic_attack(al, t1)
	var w100: float = float(B.SMOKE_TRUE_FLAT[2]) + B.SMOKE_TRUE_ATK * 100.0
	_ok("100 潜行中普攻：现形 + 追加 %.0f 真伤" % w100, not _s._is_untargetable(al) and _near(_lost(t1), w100), "%.0f" % _lost(t1))
	t1["hp"] = t1["maxHp"]
	_s._equip_sys._eq_on_basic_attack(al, t1)
	_ok("100 现形后再普攻不再追加", _lost(t1) == 0.0)

	## ── 101 粘弹 ──
	me = _mk("left", c + Vector2(-100, 0), ["p2eq_101"])
	t1 = _mk("right", c + Vector2(100, 0))
	t2 = _mk("right", c + Vector2(100, 60))
	_place([me, t1, t2])
	_adv(8.05, [me])
	_ok("101 第 8 秒：目标减速 40%%（移速倍率 0.6）", _near(float(t1.get("slow_mag", 1.0)), 1.0 - B.STICKY_SLOW, 0.001) and float(t1["slow_until"]) > float(_s._t),
		"mag %.2f" % float(t1.get("slow_mag", 1.0)))
	_adv(B.STICKY_FUSE + 0.05, [])
	var w101: float = float(B.STICKY_FLAT[2]) + B.STICKY_ATK * 100.0
	_ok("101 2 秒后爆：挨 %.0f" % w101, _near(_lost(t1), w101), "%.0f" % _lost(t1))
	_adv(B.GOO_SEC + 0.05, [])
	var p1: int = int(t1["dot_stacks"].get("poison", 0)) if t1.get("dot_stacks") is Dictionary else -1
	_ok("101 粘液 1.5 秒：叠 3 次 × %d 层中毒（目标与 130 码内的敌人）" % int(B.GOO_POISON[2]),
		_bs.stat["goo_tick"] == 3 and p1 >= 3 * int(B.GOO_POISON[2]) - 0 and int(t2["dot_stacks"].get("poison", 0)) > 0,
		"goo %d · 层 %d / %d" % [_bs.stat["goo_tick"], p1, int(t2["dot_stacks"].get("poison", 0))])

	## ── 102 地雷 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_102"])
	t1 = _mk("right", c + Vector2(400, 0))
	_place([me, t1])
	_bs.place_team_mines()
	_ok("102 3★ 登场埋 %d 颗" % int(B.MINE_COUNT[2]), _bs._mines.size() == int(B.MINE_COUNT[2]), "%d" % _bs._mines.size())
	var mp: Vector2 = _bs._mines[0]["pos"]
	t1["airborne"] = true
	t1["pos"] = mp
	_adv(0.05)
	_ok("102 空中单位不踩", _lost(t1) == 0.0 and _bs._mines.size() == int(B.MINE_COUNT[2]))
	t1["airborne"] = false
	_adv(0.05)
	_ok("102 踩中：挨 %.0f 物理 + 眩晕 %.1f 秒；那颗雷没了" % [float(B.MINE_DMG[2]), B.MINE_STUN],
		_near(_lost(t1), float(B.MINE_DMG[2])) and _near(float(t1["stun_until"]) - float(_s._t), B.MINE_STUN, 0.06) and _bs._mines.size() == int(B.MINE_COUNT[2]) - 1,
		"%.0f · 眩晕剩 %.2f · 雷 %d" % [_lost(t1), float(t1["stun_until"]) - float(_s._t), _bs._mines.size()])
	var fbase: float = _s._arena_center.x - float(LineupPos.FORMATION_DX)
	_ok("102 默认埋在本方队形中心往前 %.0f 码（朝敌方）" % B.MINE_FWD, absf(mp.x - (fbase + B.MINE_FWD)) < 1.0, "雷 x %.0f · 队形中心 x %.0f" % [mp.x, fbase])

	## ── 103 炸药桶 ──
	me = _mk("left", c, ["p2eq_103"], 3, 5000.0)
	t1 = _mk("right", c + Vector2(200, 0))
	t2 = _mk("right", c + Vector2(300, 0))
	_place([me, t1, t2])
	_bs.on_death(me, "p2eq_103", 2)
	var w103: float = float(B.BARREL_PCT[2]) * 5000.0
	_ok("103 阵亡：250 码内挨 %.0f（自身最大生命 80%%）；300 码外不挨" % w103, _near(_lost(t1), w103) and _lost(t2) == 0.0,
		"%.0f / %.0f" % [_lost(t1), _lost(t2)])

	## ── 104 定时炸弹 ──
	me = _mk("left", c + Vector2(-100, 0), ["p2eq_104"])
	me["_food_key"] = "L#turtleA"
	t1 = _mk("right", c + Vector2(100, 0))
	_place([me, t1])
	_bs.reset_match()
	_adv(8.1, [me])
	_adv(B.TIMER_FUSE, [me])
	var w104: float = float(B.TIMER_FLAT[2]) + B.TIMER_ATK * 100.0
	var l1 := _lost(t1)
	_ok("104 第 1 颗：挨 %.0f" % w104, _near(l1, w104), "%.0f" % l1)
	t1["hp"] = t1["maxHp"]
	_adv(8.0, [me])
	_ok("104 第 2 颗 ×%.2f" % (1.0 + B.TIMER_STACK), _near(_lost(t1), w104 * (1.0 + B.TIMER_STACK)), "%.0f" % _lost(t1))
	## 换路：单位重建（新字典）、同一身份键 ⇒ 叠层继续
	var me2 := _mk("left", c + Vector2(-100, 0), ["p2eq_104"])
	me2["_food_key"] = "L#turtleA"
	t1 = _mk("right", c + Vector2(100, 0))
	_place([me2, t1])
	_ok("104 换路后同一只龟的叠层保留（已绑 2 颗）", _bs.timer_stacks_of(me2) == 2, "%d" % _bs.timer_stacks_of(me2))
	_bs.reset_match()
	_ok("104 一局结束清零", _bs.timer_stacks_of(me2) == 0)

	## ── 105 炮筒 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_105"])
	t1 = _mk("right", c + Vector2(100, 0), [], 3, 10000000.0)
	_place([me, t1])
	_bs.on_spawn(me, "p2eq_105", 2)
	var cs: Dictionary = _bs.cannon_state(0)
	var cu: Dictionary = cs.get("u", {})
	_ok("105 召唤炮筒 %.0f 血 / %.0f 攻，站在携带者后方" % [float(B.CANNON_HP[2]), float(B.CANNON_ATK[2])],
		not cu.is_empty() and _near(float(cu["maxHp"]), float(B.CANNON_HP[2])) and _near(float(cu["atk"]), float(B.CANNON_ATK[2])) and float(cu["pos"].x) < float(me["pos"].x),
		"hp %.0f atk %.0f x %.0f" % [float(cu.get("maxHp", 0)), float(cu.get("atk", 0)), float(cu.get("pos", Vector2.ZERO).x)])
	_s._units.append(cu)
	cu["crit"] = 0.0
	_adv(B.CANNON_IV + 0.01)
	_adv(0.9)   # 普通炮弹要飞一段(CANNON_BALL_SPD)才落到身上结算
	var en_want: float = minf(B.CANNON_EN_MAX, (B.CANNON_IV + 0.01 + 0.9) / B.SEC_PER_ENERGY)
	_ok("105 每炮 100%% 攻击（%.0f）；龟能照全局规则涨（1 点 = %.3f 秒 ⇒ %.2f 秒 %.1f）" % [float(B.CANNON_ATK[2]), B.SEC_PER_ENERGY, B.CANNON_IV + 0.91, en_want],
		_near(_lost(t1), float(B.CANNON_ATK[2])) and _near(float(cs["en"]), en_want, 0.3), "%.0f · 龟能 %.0f" % [_lost(t1), float(cs["en"])])
	cs["en"] = B.CANNON_EN_MAX
	t1["hp"] = t1["maxHp"]
	_adv(B.CANNON_IV + 0.01)
	_adv(1.2)
	_ok("105 龟能满 ⇒ 重炮：直线飞行命中，%.0f%% 攻击 + %d 层流血 + 击退，每发 −%.0f 龟能" % [B.CANNON_HEAVY_MULT * 100.0, int(B.CANNON_HEAVY_BLEED[2]), float(B.CANNON_HEAVY_COST[2])],
		bool(cs["heavy"]) and _bs.stat["cannon_heavy"] >= 1 and _lost(t1) >= B.CANNON_HEAVY_MULT * float(B.CANNON_ATK[2]) - 1.5 and int(t1["dot_stacks"].get("bleed", 0)) >= int(B.CANNON_HEAVY_BLEED[2]),
		"heavy %s · 挨 %.0f · 流血 %d · 龟能 %.0f" % [str(cs["heavy"]), _lost(t1), int(t1["dot_stacks"].get("bleed", 0)), float(cs["en"])])
	var exited := false
	var reentered := false
	for i in range(60):
		t1["pos"] = c + Vector2(100, 0)
		t1["airborne"] = false
		_adv(B.CANNON_IV)
		if not bool(cs["heavy"]):
			exited = true
		elif exited:
			reentered = true
	_ok("105 重炮把龟能耗尽后回到普通炮击，普通炮击攒满再进重炮（循环）", exited and reentered, "退出 %s 再进 %s" % [str(exited), str(reentered)])

	## ── 106 遥控炸弹 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_106"], 3, 20000.0)
	t1 = _mk("right", c + Vector2(100, 0))
	t2 = _mk("right", c + Vector2(800, 0))
	_place([me, t1, t2])
	_bs.on_spawn(me, "p2eq_106", 2)
	var ru: Dictionary = _bs._remotes[0]["u"]
	_s._units.append(ru)
	_ok("106 召唤 %.0f 血、%.0f 双抗" % [float(B.REMOTE_HP[2]), float(B.REMOTE_RES[2])],
		_near(float(ru["maxHp"]), float(B.REMOTE_HP[2])) and _near(float(ru["def"]), float(B.REMOTE_RES[2])) and _near(float(ru["mr"]), float(B.REMOTE_RES[2])))
	_adv(1.0)
	_ok("106 3★ 不衰减", _near(float(ru["hp"]), float(B.REMOTE_HP[2])), "%.0f" % float(ru["hp"]))
	ru["pos"] = c + Vector2(0, 0)
	_adv(0.05)
	ru["hp"] = 0.0
	_s._kill(ru)
	_adv(0.05)
	var w106: float = float(B.REMOTE_FLAT[2]) + float(B.REMOTE_TRUE_PCT[2]) * 20000.0
	_ok("106 被打死 ⇒ 600 码内挨 %.0f 物理 + 携带者 20%% 最大生命真伤（共 %.0f）+ %d 层流血；600 码外不挨" % [float(B.REMOTE_FLAT[2]), w106, int(B.REMOTE_BLEED[2])],
		_near(_lost(t1), w106) and int(t1["dot_stacks"].get("bleed", 0)) >= int(B.REMOTE_BLEED[2]) and _lost(t2) == 0.0 and _bs.stat["remote_boom"] == 1,
		"%.0f · 流血 %d · 远 %.0f · 爆 %d" % [_lost(t1), int(t1["dot_stacks"].get("bleed", 0)), _lost(t2), _bs.stat["remote_boom"]])
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_106"], 1, 20000.0)
	_place([me, t1])
	_bs.on_spawn(me, "p2eq_106", 0)
	ru = _bs._remotes[0]["u"]
	_s._units.append(ru)
	_adv(1.0)
	_ok("106 1★ 每秒 −10%% 最大生命", _near(float(ru["hp"]), float(B.REMOTE_HP[0]) * 0.9, 3.0), "%.0f" % float(ru["hp"]))

	## ── 107 武士刀 ──
	me = _mk("left", c + Vector2(-200, 0), ["p2eq_107"])
	t1 = _mk("right", c + Vector2(100, 0))
	_place([me, t1])
	_bs.on_spawn(me, "p2eq_107", 2)
	var ks: Dictionary = _bs.katana_state(0)
	var ku: Dictionary = ks["u"]
	_s._units.append(ku)
	ku["pos"] = c + Vector2(-100, 0)
	ku["crit"] = 0.0
	_ok("107 召唤小将 %.0f 血 / %.0f 攻" % [float(B.KATANA_HP[2]), float(B.KATANA_ATK[2])],
		_near(float(ku["maxHp"]), float(B.KATANA_HP[2])) and _near(float(ku["atk"]), float(B.KATANA_ATK[2])))
	var waves := []
	for i in range(3):
		t1["hp"] = t1["maxHp"]
		ks["en"] = B.KATANA_EN_MAX
		_adv(1.0)
		waves.append(_lost(t1))
	var w107: float = B.KATANA_WAVE_MULT * float(B.KATANA_ATK[2])
	_ok("107 前三次：剑气波各 %.0f（150%% 攻击）" % w107, _near(waves[0], w107) and _near(waves[1], w107) and _near(waves[2], w107) and _bs.stat["katana_wave"] == 3,
		str(waves))
	t1["hp"] = t1["maxHp"]
	ku["hp"] = float(ku["maxHp"]) * 0.5
	ks["en"] = B.KATANA_EN_MAX
	_adv(0.05)
	_ok("107 第四次：蓄力中（不出波）", float(ks["charge"]) >= 0.0 and _bs.stat["katana_wave"] == 3)
	_adv(B.KATANA_CHARGE)
	var healed: float = float(ku["hp"]) - float(ku["maxHp"]) * 0.5
	_ok("107 蓄力 1.5 秒回 15%% 最大生命（%.0f）" % (B.KATANA_HEAL_TOTAL * float(ku["maxHp"])), _near(healed, B.KATANA_HEAL_TOTAL * float(ku["maxHp"]), 2.0), "%.0f" % healed)
	_adv(1.0)
	var w107t: float = B.KATANA_TORNADO_MULT * float(B.KATANA_ATK[2])
	_ok("107 然后 3 道龙卷风：挨 %.0f（300%% 攻击，三道扇形同一目标只吃中间那道）、击飞" % w107t,
		_bs.stat["katana_tornado"] == 3 and _near(_lost(t1), w107t) and bool(t1["airborne"]),
		"龙卷 %d · 挨 %.0f · air %s" % [_bs.stat["katana_tornado"], _lost(t1), str(t1["airborne"])])

	## ── 同名两件各自计时 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_099", "p2eq_099"])
	t1 = _mk("right", c + Vector2(100, 0))
	_place([me, t1])
	var g0: int = _bs.stat["grenade"]
	_adv(6.0 + B.GRENADE_FLY + 0.1, [me])
	_ok("同名两件：两颗手雷各炸一次（第二颗吃到第一颗的破甲，伤害更高）", _bs.stat["grenade"] - g0 == 2 and _lost(t1) > 2.0 * w99 + 1.0, "%d 颗 · 挨 %.0f" % [_bs.stat["grenade"] - g0, _lost(t1)])

	print("")
	print("ALL PASS — 炸弹 10 件 + 武士刀 (%d 条)" % _n if _fail == 0 and _n >= 30 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
