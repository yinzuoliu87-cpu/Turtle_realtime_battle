extends Node
## verify_gun_synergy.gd — 枪羁绊【三座炮台 / 金弹 / 火控】(用户 2026-08-03 定)
##
## ★炮台做成【逻辑实体】而不是场上单位 —— 原设计里它没有血量也不会被摧毁,
##   只是"一个位置 + 一个计时器"。方案书把它估成"全表最贵的一条"是按【新单位】算的
##   (生成/朝向/弹道/阵亡/换路重建), 那套复杂度这里根本不需要。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const GUN := preload("res://scripts/systems/equip/gun_synergy_system.gd")

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
	var G := _ids("枪", 9)
	_ok("★分母: 找到 %d 件枪" % G.size(), G.size() >= 9)
	print("=== 枪羁绊 ===")

	# ── ① 火控: 顶档才有, 按【携带者身上】件数, 最高 40% ──
	for cfg in [[3, 3, 0.0], [6, 3, 0.0], [9, 3, 0.40], [9, 1, 0.20], [9, 0, 0.0]]:
		var tn: int = int(cfg[0]); var mine: int = int(cfg[1])
		var me := _mk("left", G.slice(0, mine))
		var arr: Array = [me]
		var k: int = mine
		while k < tn:
			arr.append(_mk("left", G.slice(k, mini(k + 3, tn)))); k += 3
		arr.append(_mk("right", []))
		_run(s, arr)
		_ok("① 枪 %d 件·本龟带 %d 把 → 火控 %.0f%%" % [tn, mine, float(cfg[2]) * 100.0],
			absf(float(me.get("_fire_ctrl", 0.0)) - float(cfg[2])) < 0.001,
			"实得 %.2f" % float(me.get("_fire_ctrl", 0.0)))

	# ── ② 炮台一: 3 件起, 直线打敌人 + 给最低血友军回血 ──
	var c1 := _mk("left", G.slice(0, 3))
	var hurt := _mk("left", [])
	hurt["hp"] = hurt["maxHp"] * 0.2
	var f1 := _mk("right", []); var f2 := _mk("right", [])
	# 把两个敌人摆在炮台→最近敌的直线上
	var org: Vector2 = s._gun_syn._turret_pos("left", 0)
	f1["pos"] = org + Vector2(300, 0); f2["pos"] = org + Vector2(600, 0)
	_run(s, [c1, hurt, f1, f2])
	var h0: float = float(hurt["hp"])
	var e1: float = float(f1["hp"]); var e2: float = float(f2["hp"])
	s._gun_syn._t_acc = 0.0
	s._gun_syn.tick(2.6)
	_ok("② 炮台一: 直线上【两个】敌人都吃到伤害",
		float(f1["hp"]) < e1 and float(f2["hp"]) < e2,
		"敌1 -%.0f / 敌2 -%.0f" % [e1 - float(f1["hp"]), e2 - float(f2["hp"])])
	_ok("② 炮台一: 最低血友军回了血(30%% × 造成伤害)", float(hurt["hp"]) > h0,
		"%.0f → %.0f" % [h0, float(hurt["hp"])])
	# 对照: 2 件不够, 一炮不放
	var lone := _mk("left", G.slice(0, 2))
	var lf := _mk("right", [])
	lf["pos"] = s._gun_syn._turret_pos("left", 0) + Vector2(300, 0)
	_run(s, [lone, lf])
	var lh: float = float(lf["hp"])
	s._gun_syn._t_acc = 0.0
	s._gun_syn.tick(2.6)
	_ok("② ★对照: 只有 2 件枪(未达首档) → 炮台不生成", absf(float(lf["hp"]) - lh) < 0.5,
		"敌掉 %.0f" % (lh - float(lf["hp"])))

	# ── ③ 炮台二: 6 件起, 护盾↔弹幕交替 ──
	var c2 := _mk("left", G.slice(0, 3))
	var ally2 := _mk("left", [])
	var foe2 := _mk("right", [])
	foe2["pos"] = s._gun_syn._turret_pos("left", 0) + Vector2(0, 400)   # 挪出直线, 隔离炮台一
	_run(s, [c2, ally2, _mk("left", G.slice(3, 6)), foe2])
	s._gun_syn.clear()
	ally2["shield"] = 0.0
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	## ★★2026-08-12 重做: 炮台二不再"调用即到账" —— 先蓄力 CHARGE_SEC, 再释放星浪,
	##   每个目标等【波扫到它】才吃效果(用户:「炮台也不要直接去放, 而是有个蓄力」
	##   「波碰到单位才施加效果」)。所以判据分三段量, 不能只看一次调用后的结果。
	_ok("③ ★蓄力期间【还没到账】(这一拍打算做什么记在 _t2_last, 不靠等演出)",
		absf(float(ally2.get("shield", 0.0))) < 0.01
		and bool((s._gun_syn._t2_last.get("left", {}) as Dictionary).get("shield", false)),
		"护盾 %.1f · 记账 %s" % [float(ally2.get("shield", 0.0)), str(s._gun_syn._t2_last.get("left", {}))])
	## 推进 sim 定时器: 蓄力 0.55 秒 + 波从炮位走到友军的时间
	var d_ally: float = s._gun_syn._turret_pos("left", 1).distance_to(Vector2(ally2["pos"]))
	var need: float = SynergyVfx.CHARGE_SEC + d_ally / SynergyVfx.WAVE_SPEED + 0.05
	var steps: int = int(ceil(need / 0.02))
	for _i in range(steps):
		s._ballistics._step_pending_shots(0.02)
	_ok("③ 炮台二(每5秒)·第一拍: 波扫到后转护盾均摊全队", float(ally2.get("shield", 0.0)) > 0.0,
		"护盾 %.0f(等了 %.2f 秒: 蓄力 %.2f + 波程 %.0f 码)"
		% [float(ally2.get("shield", 0.0)), need, SynergyVfx.CHARGE_SEC, d_ally])
	## ★波是【由近及远】到的: 造一近一远两个友军, 近的先拿到盾
	var near_a := _mk("left", [])
	var far_a := _mk("left", [])
	near_a["pos"] = s._gun_syn._turret_pos("left", 1) + Vector2(60.0, 0.0)
	far_a["pos"] = s._gun_syn._turret_pos("left", 1) + Vector2(560.0, 0.0)
	near_a["shield"] = 0.0
	far_a["shield"] = 0.0
	_run(s, [c2, near_a, far_a, _mk("left", G.slice(3, 6)), foe2])
	s._gun_syn.clear()
	s._gun_syn._t2_shield_phase["left"] = true
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	for _j in range(int(ceil((SynergyVfx.CHARGE_SEC + 0.16) / 0.02))):
		s._ballistics._step_pending_shots(0.02)
	var near_first: bool = float(near_a.get("shield", 0.0)) > 0.0 and absf(float(far_a.get("shield", 0.0))) < 0.01
	_ok("③ ★★波扫到才生效: 近的(60 码)已拿到盾 %.0f, 远的(560 码)还没 %.0f"
			% [float(near_a.get("shield", 0.0)), float(far_a.get("shield", 0.0))], near_first, "")
	for _k in range(int(ceil(560.0 / SynergyVfx.WAVE_SPEED / 0.02)) + 6):
		s._ballistics._step_pending_shots(0.02)
	_ok("③ ★波走到远处后, 远的也拿到盾 %.0f" % float(far_a.get("shield", 0.0)),
		float(far_a.get("shield", 0.0)) > 0.0, "")
	## 第二拍: 相位翻成弹幕(红波打人)
	var fh: float = float(foe2["hp"])
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	var d_foe: float = s._gun_syn._turret_pos("left", 1).distance_to(Vector2(foe2["pos"]))
	for _m in range(int(ceil((SynergyVfx.CHARGE_SEC + d_foe / SynergyVfx.WAVE_SPEED + 0.06) / 0.02))):
		s._ballistics._step_pending_shots(0.02)
	_ok("③ 炮台二(每5秒)·第二拍: 化弹幕打敌方全体(波扫到才掉血)", float(foe2["hp"]) < fh,
		"敌掉 %.0f" % (fh - float(foe2["hp"])))
	# 对照: 3 件时没有第二座
	var c3 := _mk("left", G.slice(0, 3))
	var ally3 := _mk("left", [])
	var foe3 := _mk("right", [])
	foe3["pos"] = s._gun_syn._turret_pos("left", 0) + Vector2(0, 400)
	_run(s, [c3, ally3, foe3])
	s._gun_syn.clear()
	ally3["shield"] = 0.0
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	## ★对照组也要把定时器推完 —— 否则"没护盾"可能只是"还没到账", 那就是个假对照
	for _n in range(int(ceil((SynergyVfx.CHARGE_SEC + 2.0) / 0.02))):
		s._ballistics._step_pending_shots(0.02)
	_ok("③ ★对照: 3 件时【没有】第二座炮台(不给护盾)",
		absf(float(ally3.get("shield", 0.0))) < 0.5, "护盾 %.0f" % float(ally3.get("shield", 0.0)))

	# ── ④ 金弹: 射满 4/3/2 发额外射一发 ──
	for cfg2 in [[3, 4], [6, 3], [9, 2]]:
		var tn2: int = int(cfg2[0]); var per: int = int(cfg2[1])
		var gu := _mk("left", G.slice(0, 3))
		var arr2: Array = [gu]
		var kk: int = 3
		while kk < tn2:
			arr2.append(_mk("left", G.slice(kk, mini(kk + 3, tn2)))); kk += 3
		arr2.append(_mk("right", []))
		_run(s, arr2)
		s._pending_shots.clear()
		gu["_gun_shot_ct"] = {}
		s._queue_shots(per, 0.05, func() -> void: pass, gu, "p2eq_048")
		_ok("④ 枪 %d 件: 射满 %d 发 → 多出 1 发金弹(共 %d 条)" % [tn2, per, per + 1],
			s._pending_shots.size() == per + 1, "实得 %d" % s._pending_shots.size())
	# 对照: 未激活不给金弹
	var g0 := _mk("left", G.slice(0, 2))
	_run(s, [g0, _mk("right", [])])
	s._pending_shots.clear(); g0["_gun_shot_ct"] = {}
	s._queue_shots(6, 0.05, func() -> void: pass, g0, "p2eq_048")
	_ok("④ ★对照: 未激活(2件) → 6 发就是 6 发, 没有金弹",
		s._pending_shots.size() == 6, "实得 %d" % s._pending_shots.size())

	# ══════════════════════════════════════════════════════════════
	# ★★炮台是【看得见的实体】(2026-08-12 用户:「比如枪, 炮台我完全没看到啊」)
	#    由来: 以前炮台只是"一个坐标 + 每 2.5 秒闪 0.32 秒的一根光柱",
	#    场上没有任何"这里有一座炮台"的东西 ⇒ 玩家读到的是"凭空飞来一条橙线"。
	#    现在 GunSynergySystem.tick 每帧保活一座常驻炮台节点(底座+炮塔+炮管)。
	#    ★量的是【真实节点在不在 _world、站没站在炮位上】, 不是"某函数存在"。
	# ══════════════════════════════════════════════════════════════
	var sv = _scene._vfx._syn
	_ok("★分母: 演出层在位(它不在, 下面全是空检查)", sv != null, str(sv))
	if sv != null:
		# 3 件枪 = 档1 ⇒ 第一座炮台; 先清干净再建
		for k0 in ["left|0", "left|1", "left|2", "right|0", "right|1", "right|2"]:
			sv.gun_turret_free(k0)
		var g3: Array = _ids("枪", 3)
		_run(_scene, [_mk("left", g3), _mk("right", [])])
		_scene._gun_syn.tick(0.016)
		_ok("★★档1(3 件枪): 场上真的站着 1 座炮台(不是只有开火那一闪)",
			sv.gun_turret_count() == 1, "count=%d" % sv.gun_turret_count())
		# 炮台站在【炮位】上 —— 量真实节点世界坐标 vs _turret_pos 的换算
		var want: Vector3 = _scene._world_pos(_scene._gun_syn._turret_pos("left", 0), 0.0)
		var got = sv.gun_turret_ensure("left|0", _scene._gun_syn._turret_pos("left", 0), 0)
		_ok("★炮台站在炮位上(偏差 %.4f m)" % (got.position - want).length() if got != null else "★炮台节点缺失",
			got != null and (got.position - want).length() < 1e-3, "")
		_ok("★炮台真的挂在 _world 下(不是建了没进场景树)",
			got != null and _scene._world.is_ancestor_of(got), "")
		# 6 件枪 = 档2 ⇒ 两座
		var g6: Array = _ids("枪", 6)
		_run(_scene, [_mk("left", g6), _mk("right", [])])
		_scene._gun_syn.tick(0.016)
		_ok("★★档2(6 件枪): 两座炮台都站着", sv.gun_turret_count() == 2,
			"count=%d" % sv.gun_turret_count())
		# 开火: 炮塔真的转向目标(量 yaw), 且有后坐
		var tgt := Vector2(_scene.ARENA.position.x + _scene.ARENA.size.x * 0.8,
			_scene.ARENA.position.y + _scene.ARENA.size.y * 0.5)
		var fired: bool = sv.gun_turret_fire("left|0", tgt)
		_ok("★开火入口真的认这座炮台(返回 true)", fired, "")
		# ★分母: 不存在的炮台开火必须返回 false(否则上一条可能是"永远 true")
		_ok("★分母: 不存在的炮台开火返回 false", not sv.gun_turret_fire("left|9", tgt), "")
		# ★★档3(9 件枪) = 三座, 且【三种形态各不相同】(2026-08-12 用户:「那是有3种炮台, 你确定有吗」)
		#    权威 TIER_DESCS["枪"]: 炮台一轰击 / 炮台二能量(相位) / 炮台三·火控 —— 第三座以前根本没建。
		var g9: Array = _ids("枪", 9)
		_run(_scene, [_mk("left", g9), _mk("right", [])])
		_scene._gun_syn.tick(0.016)
		_ok("★★档3(9 件枪): 三座炮台都站着(第三座=火控塔)", sv.gun_turret_count() == 3,
			"count=%d" % sv.gun_turret_count())
		var kinds: Array = []
		for ki in range(3):
			var nd = sv.gun_turret_ensure("left|%d" % ki, _scene._gun_syn._turret_pos("left", ki), ki)
			kinds.append(nd != null)
		_ok("★三座各自建得出来(kind 0/1/2)", kinds == [true, true, true], str(kinds))
		## 形态真的不同: 火控塔的碟【在转】而炮一/炮二不转(量真实节点的旋转)
		var d0: float = sv._turrets["left|2"]["barrel"].rotation.z
		_scene._gun_syn.tick(0.5)
		var d1: float = sv._turrets["left|2"]["barrel"].rotation.z
		_ok("★炮台三·火控: 雷达碟在转(0.5 秒转过 %.3f rad) —— 它不开火, 转就是它在工作的证据"
				% absf(d1 - d0), absf(d1 - d0) > 0.5, "")
		var b0x: float = sv._turrets["left|0"]["barrel"].rotation.z
		_scene._gun_syn.tick(0.5)
		_ok("★分母: 炮台一的管【不转】(0.5 秒转过 %.3f rad ≈ 0) —— 三座不是同一个形态"
				% absf(sv._turrets["left|0"]["barrel"].rotation.z - b0x),
			absf(sv._turrets["left|0"]["barrel"].rotation.z - b0x) < 1e-6, "")
		## ★★火控【开局一次性附魔】(2026-08-12 用户:「只要有该局给所有携带枪的友军一个
		##   附魔的动作 …… 只需要战斗开始后展示一个演示特效就好」) —— 旧的每 1.6 秒
		##   拉光束那套已删, 判据随之改成"一局一次、每人一套附魔演出"。
		var before_e: int = _scene._world.get_child_count()
		var ench: int = sv.gun_firectrl_enchant("left|2", [Vector2(100.0, 100.0), Vector2(200.0, 120.0)])
		_ok("★炮台三给 2 个携枪者各放了一次附魔(返回 %d)" % ench, ench == 2, "n=%d" % ench)
		var per: int = 1 + SynergyVfx.ENCHANT_MOTES        # 符文环 + 上浮金点
		var added: int = _scene._world.get_child_count() - before_e
		_ok("★附魔真的建了节点: 新增 %d 个(每人 1 环 + %d 金点 + 1 道接通束)"
				% [added, SynergyVfx.ENCHANT_MOTES], added >= 2 * per, "added=%d" % added)
		## 符文环【从脚下升到头顶】—— 停在脚下只是个圈, 升上去才读成"被附魔过"
		var ring_y0 := -1.0
		for ei in range(_scene._world.get_child_count() - 1, -1, -1):
			var ec = _scene._world.get_child(ei)
			if ec is MeshInstance3D and (ec as Node).has_meta("synergy_vfx") \
					and str((ec as Node).get_meta("synergy_vfx")) == "enchant_ring":
				ring_y0 = (ec as Node3D).position.y
				break
		_ok("★符文环出生在【脚下】(y=%.3f ≈ 0), 再由 tween 升到头顶" % ring_y0,
			ring_y0 >= 0.0 and ring_y0 < 0.2, "y=%.3f" % ring_y0)
		## ★分母: 不存在的火控塔 → 0 人(证明上面不是"永远返回人数")
		_ok("★分母: 不存在的火控塔附魔 0 人",
			sv.gun_firectrl_enchant("left|9", []) == 0, "")
		## ★不做周期性表现: 连续 tick 3 秒不该再新增附魔节点(用户只要开局一次)
		var n_before: int = _count_meta("enchant_ring")
		for _t3 in range(150):
			_scene._gun_syn.tick(0.02)
		_ok("★★不做周期性表现: tick 3 秒后附魔环没有新增(%d → %d)"
				% [n_before, _count_meta("enchant_ring")],
			_count_meta("enchant_ring") <= n_before, "")


		# ★★炮台一的三样演出(2026-08-12 用户:「第一座要改为激光直线, 被治疗的友军用绿光回复
		#    效果(中上半身冒绿光), 激光命中要有命中效果」) —— 量真实节点, 不是"函数存在"。
		var before_n: int = _scene._world.get_child_count()
		var lz = sv.gun_laser(Vector2(300.0, 400.0), Vector2.RIGHT, 800.0)
		_ok("★激光节点真的挂进 _world",
			lz != null and _scene._world.is_ancestor_of(lz), str(lz))
		if lz != null:
			## 激光是【两层】的(外晕 + 白热芯) —— 单层匀亮线正是上一版读成"一条橙线"的原因。
			## 三层 × 每层 2 三角 × 3 顶点 = 18 个顶点
			var lv: int = ((lz.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				as PackedVector3Array).size()
			_ok("★激光是多层的(顶点数 %d = 3 层 × 2 三角 × 3)" % lv, lv == 18, "verts=%d" % lv)
			var lw: float = lz.get_aabb().size.z
			_ok("★激光的宽度来自外晕(%.3f m ≈ 2×%.0f 码×WS)" % [lw, 17],
				lw > 0.1, "w=%.4f" % lw)
		var hit_node = sv.gun_laser_hit(Vector2(500.0, 400.0), Vector2.RIGHT)
		_ok("★命中花节点真的挂进 _world(激光命中要有命中效果)",
			hit_node != null and _scene._world.is_ancestor_of(hit_node), str(hit_node))
		var heal_made: int = sv.heal_glow(Vector2(320.0, 420.0))
		_ok("★治疗绿光建了 %d 个节点(光柱 + 胸口光晕 + %d 颗上浮绿点)"
				% [heal_made, SynergyVfx.HEAL_MOTES],
			heal_made == 2 + SynergyVfx.HEAL_MOTES, "made=%d" % heal_made)
		## 绿光的高度: 底在【中上半身】(胸口 0.55 米)而不是脚下 —— 用户点名的位置
		var glow_y := -1.0
		for gi in range(_scene._world.get_child_count() - 1, -1, -1):
			var gc = _scene._world.get_child(gi)
			if gc is Sprite3D and (gc as Node).has_meta("synergy_vfx") \
					and str((gc as Node).get_meta("synergy_vfx")) == "heal_glow":
				glow_y = (gc as Node3D).position.y
				break
		_ok("★绿光柱在【中上半身】起(底 0.55 米 ⇒ 中心 y=%.2f > 0.55)" % glow_y,
			glow_y > 0.55, "y=%.3f" % glow_y)
		_ok("★分母: 这三样真的往场景树里加了东西(%d → %d)"
				% [before_n, _scene._world.get_child_count()],
			_scene._world.get_child_count() > before_n, "")

		# 掉档: 0 件枪 ⇒ 炮台撤走(不许"羁绊没了炮台还杵在那")
		_run(_scene, [_mk("left", []), _mk("right", [])])
		_scene._gun_syn.tick(0.016)
		_ok("★★掉档(0 件枪): 炮台被撤走 count=%d" % sv.gun_turret_count(),
			sv.gun_turret_count() == 0, "")

	s._units.clear(); s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 枪羁绊" if _fail == 0 else "FAIL x%d" % _fail)
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
	s._gun_syn.apply_all()

func _mk(side: String, ids: Array) -> Dictionary:
	var c: Vector2 = _scene.ARENA.position + _scene.ARENA.size * 0.5
	var off := Vector2(-200.0, 0.0) if side == "left" else Vector2(200.0, 0.0)
	var u: Dictionary = _scene._spawn._make_unit("green", side, c + off)
	u["maxHp"] = 3000.0; u["hp"] = 3000.0; u["shield"] = 0.0
	u["crit"] = 0.0; u["def"] = 0.0; u["base_def"] = 0.0; u["mr"] = 0.0; u["base_mr"] = 0.0
	u["flat_dr"] = 0.0; u["dodge_bonus"] = 0.0
	var e: Array = []
	for i in ids: e.append({"id": str(i), "star": 1})
	u["equips"] = e; u["eq_state"] = {}
	return u


## 数场上带某个 synergy_vfx meta 的节点(按 meta 认, 不按名字/下标)
func _count_meta(kind: String) -> int:
	var n := 0
	for i in range(_scene._world.get_child_count()):
		var c = _scene._world.get_child(i)
		if c is Node and (c as Node).has_meta("synergy_vfx") \
				and str((c as Node).get_meta("synergy_vfx")) == kind:
			n += 1
	return n
