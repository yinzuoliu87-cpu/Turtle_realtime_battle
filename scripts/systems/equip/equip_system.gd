class_name EquipSystem
extends RefCounted
## 装备效果系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 【装备与角色技能分开管理·用户定向】所有 _eq_/_tick_eq_ 效果在此; 类内名字不变, 外部名加 battle.

var battle
var _stats: EquipStatsApply   # 被动属性/flag 应用子系统(2026-07-26 从本文件分出·spawn期·区别于主动效果)
var _eq_drone_halve: bool = false   # 无人机减半标记(随本系统)

func _init(b) -> void:
	battle = b
	_stats = EquipStatsApply.new(b)

func _eq_on_basic_attack(u: Dictionary, tgt = null) -> void:   # 每普攻(不算多段): 008珊瑚刺计数 / 017不沉之锚普攻消耗充能锚击
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) == "p2eq_017":   # 不沉之锚: 每次普攻消耗1沉锚充能→击飞最前敌+眩晕(用户2026-07-02)
			var ast: Dictionary = u["eq_state"].get("p2eq_017", {})
			if int(ast.get("anchor_charges", 0)) > 0:
				var at = battle._targeting._nearest_enemy(u)
				if at != null:
					var si17: int = _eq_si(int(e.get("star", 1)))
					ast["anchor_charges"] = int(ast["anchor_charges"]) - 1
					u["anchor_swing_t"] = battle._t   # 本发普攻算"持有充能"→攻速×2 (用户2026-07-19)
					var adm: int = battle._resolve_dmg(u, [0.4, 0.6, 3.0][si17] * (u["def"] + u["mr"]) + at["maxHp"] * [0.06, 0.15, 0.70][si17], at, false)   # 用户2026-07-19: 原裸值不吃护甲=真伤, 改走护甲(物理必吃甲)
					battle._damage._apply_damage_from(u, at, adm, Color("#9be7ff"), 0.0, false, true)
					battle._damage._knockback(u, at, 60.0); battle._freeze(at, battle.CTRL_SEC)
					battle._skill_ring(at["pos"], Color(0.6, 0.85, 1.0, 0.6), 60.0)
					u["eq_state"]["p2eq_017"] = ast
		if str(e["id"]) == "p2eq_039":   # 竹制弓箭: 每第3段普攻消耗1次生长充能→射强化竹箭(用户2026-07-19)
			var b39: Dictionary = u["eq_state"].get("p2eq_039", {})
			b39["bamboo_hits"] = int(b39.get("bamboo_hits", 0)) + 1
			if int(b39["bamboo_hits"]) >= 3 and int(b39.get("bamboo_charges", 0)) > 0:
				var t39 = battle._targeting._nearest_enemy(u)
				if t39 != null:
					b39["bamboo_hits"] = 0
					b39["bamboo_charges"] = int(b39["bamboo_charges"]) - 1
					var si39: int = _eq_si(int(e.get("star", 1)))
					# 回血+永久成长延到绿球落回自己身上才生效(竹叶龟同款)
					battle._spawn_bamboo_arrow(u, t39, [25, 30, 35][si39] + int(u["maxHp"] / battle.HP_MULT * 0.06), [50.0, 70.0, 90.0][si39])
			u["eq_state"]["p2eq_039"] = b39
		if str(e["id"]) == "p2eq_027" and tgt != null and tgt is Dictionary and tgt.get("alive", false):   # 电棍: 就绪→本次普攻消耗1层附魔法伤+眩晕(用户2026-07-03)
			var bst: Dictionary = u["eq_state"].get("p2eq_027", {})
			if bst.get("baton_ready", false) and int(bst.get("baton_charges", 0)) > 0:
				var si27: int = _eq_si(int(e.get("star", 1)))
				bst["baton_charges"] = int(bst["baton_charges"]) - 1
				bst["baton_ready"] = false; bst["baton_cd"] = 0.0
				u["eq_state"]["p2eq_027"] = bst
				battle._damage._apply_damage_from(u, tgt, battle._resolve_dmg(u, float([30, 40, 50][si27]), tgt, true), Color("#7ecbff"), 0.0, false, true)
				battle._freeze(tgt, [2.5, 2.5, 3.0][si27])   # 眩晕 1.5s(CTRL_SEC默认) → 2.5/2.5/3 按星级(用户2026-07-19)
				battle._chain_zap(tgt["pos"])
		# 珊瑚刺008: 旧「每5次普攻」计数器已删(与_tick_coral每9秒重复触发·用户2026-07-19)

func _eq_ice_fissure(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	battle._damage._grant_shield(u, [100.0, 160.0, 250.0][si])   # 释放即上盾一次
	battle._shield_bubble(u)
	var t = battle._targeting._nearest_enemy(u)
	if t == null:
		return
	var dir: Vector2 = (t["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	battle._anticipate(u)                                 # 蓄力砸地
	var tw = battle._reg_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(battle._ice_fissure_go.bind(u, si, u["pos"], dir))

# 水晶碎片火花: 弹出+缓旋+淡出 (光束/引爆/扫射点缀)
# 030 单段水晶光束结算: 从携带者当前位置沿 dir 无限直线, 全线敌魔法伤+1层水晶
func _eq_crystal_line(u: Dictionary, si: int) -> void:   # 迷你水晶球A030: 每7秒朝最近敌方向连发2/2/3段贯穿光束(错峰0.2s)
	if not u.get("alive", false): return
	var t4 = battle._targeting._nearest_enemy(u)
	if t4 == null: return
	var dir2: Vector2 = (t4["pos"] - u["pos"]).normalized()
	if dir2 == Vector2.ZERO: dir2 = Vector2.RIGHT
	for _seg in range([2, 2, 3][si]):
		var twc = battle._reg_tween()
		twc.tween_interval(float(_seg) * 0.2)   # 施加水晶间隔0.2s(用户)
		twc.tween_callback(battle._crystal_line_seg.bind(u, si, dir2))

# 031: 水晶射线360度扫一圈(1.5s), 射线扫到敌人即结算魔法伤+叠层
func _eq_crystal_sweep(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var center: Vector2 = u["pos"]
	var reach: float = 1000.0
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # 加色发光(水晶能量)
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.set_meta("mat", mat)
	battle._world.add_child(im)
	var start_a: float = randf() * TAU
	var state: Dictionary = {"prev": start_a}
	battle._crystal_spark(center, 1.1)
	var tw = battle._reg_tween()
	# 先慢后快再慢(ease-in-out): 匀速被否, 甩动有加速度
	tw.tween_method(battle._crystal_sweep_step.bind(u, si, reach, state, im, imesh, mat), start_a, start_a + TAU, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(im.queue_free)

# 032: 登场召唤亡灵骷髅 (双抗20000近乎免疫, 存活15s自灭, 死亡200码内%最大生命真伤)
func _eq_summon_turret(u: Dictionary, si: int) -> void:   # 穿甲遗弹058(重做): 登场召唤不可移动的炮台
	if not u.get("alive", false): return
	var tr = battle._spawn_summon(u, "turret", [500.0, 1000.0, 1800.0][si], [20.0, 30.0, 45.0][si],
		{"label": "炮台", "spr_id": "turret", "col_size": 44.0, "hp_w": 32.0,
		 "atk_interval": 2.0, "atk_range": 2000.0, "move_spd": 0.0, "melee": false})
	if tr == null: return
	tr["eq_state"] = {}; tr["equips"] = []
	tr["_eq_turret"] = true
	tr["_turret_si"] = si
	tr["move_spd"] = 0.0; tr["no_move"] = true      # 移速为0
	tr["crit"] = 0.0; tr["armor_pen"] = 0.0
	u["_turret_ref"] = tr                            # 只用 is_same 比较, 绝不当Dict键/深比较
	# 登场演出: 蓝白部署环 + 起降形变
	battle._splash_ring_bold(tr["pos"], Color(0.42, 0.82, 1.0), 110.0)
	battle._skill_ring(tr["pos"], Color(0.5, 0.88, 1.0, 0.7), 62.0)
	if is_instance_valid(tr["sprite"]):
		var bs: Vector3 = tr["sprite"].scale
		tr["sprite"].scale = Vector3(bs.x * 1.3, 0.05, bs.z)
		var dtw = battle._reg_tween()
		dtw.tween_property(tr["sprite"], "scale", bs, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _tick_eq_turret(u: Dictionary, delta: float) -> void:   # 058: 炮台双抗随携带者存活 / 携带者在400码内得攻速 / 锁定红线
	var tr = u.get("_turret_ref", null)
	if not (tr is Dictionary):
		return
	if not tr.get("alive", false):
		u["_turret_aspd_mult"] = 1.0
		battle._update_turret_line(tr)
		return
	var si: int = int(u.get("_turret_si", 0))
	var res: float = ([70.0, 85.0, 100.0][si] if u.get("alive", false) else 0.0)   # 携带者阵亡→双抗归零
	if absf(float(tr.get("base_def", -1.0)) - res) > 0.01:
		tr["base_def"] = res; tr["base_mr"] = res
		battle._recalc_stats(tr)
	var near: bool = u.get("alive", false) and (u["pos"] - tr["pos"]).length() <= 400.0
	u["_turret_aspd_mult"] = (1.0 + [0.20, 0.30, 0.40][si]) if near else 1.0   # 直接赋值(不累加·不会泄漏)
	battle._update_turret_line(tr)

func _eq_summon_skeleton(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var sk = battle._spawn_summon(u, "skeleton", [19.0, 21.0, 25.0][si] * battle.HP_MULT, [3.0, 5.0, 8.0][si], {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "atk_interval": 1.0 / 1.2, "atk_range": 70.0, "melee": true, "move_spd": 130.0})
	if sk == null: return
	sk["base_def"] = 20000.0; sk["base_mr"] = 20000.0; sk["def"] = 20000.0; sk["mr"] = 20000.0
	sk["summon_life"] = 15.0
	sk["boom_pct_true"] = [0.08, 0.13, 0.20][si]
	sk["boom_radius"] = 200.0
	battle._skill_ring(sk["pos"], Color(0.4, 1.0, 0.55, 0.6), 40.0)
	for k in range(5):
		battle._bone_speck(sk["pos"] + Vector2(randf_range(-24, 24), randf_range(-24, 24)))
	if is_instance_valid(sk["sprite"]):
		var base_sc: Vector3 = sk["sprite"].scale
		sk["sprite"].scale = Vector3(base_sc.x, 0.05, base_sc.z)
		var tw = battle._reg_tween()
		tw.tween_property(sk["sprite"], "scale", base_sc, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# 亡灵爆: 绿冲击环 + 绿辉爆闪 + 骨渣四射 (骷髅自灭/被杀 + 海螺变形共用基元)
func _tick_eq_intervals(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		var iid: String = str(e["id"])
		var iv: float = float(battle._EQ_CUSTOM_IV.get(iid, 0.0))
		if iv <= 0.0: continue
		var si: int = _eq_si(int(e.get("star", 1)))
		if iid == "p2eq_037": battle._ensure_candle(u)   # 蜡烛从开局就悬在头顶(不等首次tick)
		var stt: Dictionary = u["eq_state"].get(iid, {})
		stt["iv_t"] = float(stt.get("iv_t", 0.0)) + delta
		if float(stt["iv_t"]) >= iv:
			stt["iv_t"] = float(stt["iv_t"]) - iv
			match iid:
				"p2eq_004": _eq_tyrantfang_tick(u, si)
				"p2eq_048": _eq_pistol_volley(u, si)
				"p2eq_049": _eq_crossbow_volley(u, si)
				"p2eq_050": _eq_gatling_burst(u, si)
				"p2eq_051": _eq_laser_pistol(u, si)
				"p2eq_053": _eq_shotgun_blast(u, si)
				"p2eq_057": _eq_sniper_windup(u, si)
				"p2eq_022": _eq_fuel_throw(u, si)
				"p2eq_028": _eq_ice_throw(u, si)
				"p2eq_030": _eq_crystal_line(u, si)
				"p2eq_031": _eq_crystal_sweep(u, si)
				"p2eq_037": _eq_candle_tick(u, si, stt)
				"p2eq_038": _eq_signal_tick(u, si)
				"p2eq_040": _eq_fpga_tick(u, si)
				"p2eq_042": _eq_ripple_tick(u, si)
				"p2eq_052": _eq_revolver_tick(u, si, stt)
		u["eq_state"][iid] = stt

# 涟漪回血特效(AI生成动画): 青绿涟漪水波躺平贴地, 帧播一次扩散淡出. 用于涟漪药剂042每个受益友军
func _eq_crossbow_volley(u: Dictionary, si: int) -> void:   # 连发弩049: 每8秒朝最远敌方向依次射1/2/3发, 命中沿途首敌(可被前排挡), 按已损血加伤
	if not u.get("alive", false): return
	var far49 := _eq_farthest_enemies(u, false)
	if far49.is_empty(): return
	var dir49: Vector2 = (far49[0]["pos"] - u["pos"]).normalized()
	var fire49 := func():
		if not u.get("alive", false): return
		var ft49 = _eq_first_in_line(u, dir49, 42.0)
		if ft49 == null: return
		var lost49: float = clampf((1.0 - ft49["hp"] / ft49["maxHp"]) / 0.3, 0.0, 1.0)
		battle._muzzle_flash(u["pos"], dir49, Color("#d8f0a8"))
		battle._spawn_eq_bolt(u, ft49, battle._atk_dmg(u, lerpf(0.8, 1.3, lost49), ft49), "res://assets/sprites/vfx/crossbow-bolt.png", Color("#eaffd0"))
	battle._queue_shots([1, 2, 3][si], 0.12, fire49, u)

func _eq_gatling_burst(u: Dictionary, si: int) -> void:   # 幽灵加特林050: 每8秒连打20/30/60发随机分布+永久减甲(单目标累计上限)
	if not u.get("alive", false): return
	var g_shred: float = [1.0, 2.0, 3.0][si]
	var g_cap: float = [15.0, 25.0, 40.0][si]
	var g_mul: float = [0.1, 0.12, 0.14][si]
	var fire50 := func():
		if not u.get("alive", false): return
		var es50 = battle._targeting._pick_enemies_of(u)
		if es50.is_empty(): return
		var o50 = es50[battle._battle_rng.randi() % es50.size()]
		battle._muzzle_flash(u["pos"], (o50["pos"] - u["pos"]), Color("#d0ffff"))
		battle._spawn_eq_bolt(u, o50, battle._atk_dmg(u, g_mul, o50), "res://assets/sprites/vfx/bullet.png", Color("#d0ffff"), false, 0, 0.02)
		var g_acc: float = float(o50.get("gatling_shred_acc", 0.0))
		if g_acc < g_cap:
			var g_dec: float = minf(g_shred, g_cap - g_acc)
			o50["base_def"] = maxf(0.0, o50["base_def"] - g_dec); o50["gatling_shred_acc"] = g_acc + g_dec; battle._recalc_stats(o50)
	battle._queue_shots([20, 30, 60][si], 0.03, fire50, u)

func _eq_laser_pistol(u: Dictionary, si: int) -> void:   # 激光手枪051: 每8秒穿透红激光, 首敌满伤+流血, 身后敌半伤半流血
	if not u.get("alive", false): return
	var dir4: Vector2 = (battle._targeting._nearest_enemy(u)["pos"] - u["pos"]).normalized() if battle._targeting._nearest_enemy(u) != null else Vector2.RIGHT
	var first = _eq_first_in_line(u, dir4, 50.0)
	if first != null:
		var endp51: Vector2 = u["pos"] + dir4 * 2600.0   # 无限穿透: 光束画到场外(伤害判定 battle._on_line 本就无距离上限, 原340码只是视觉长度→表现短于实际打击范围·用户2026-07-19"改为无限穿透")
		battle._muzzle_flash(u["pos"], dir4, Color("#ff5a72"))
		battle._laser_beam(u["pos"], endp51, Color(1.0, 0.24, 0.36, 0.85), 0.22, 0.22)   # 红辉(宽)
		battle._laser_beam(u["pos"], endp51, Color(1.0, 0.92, 0.94, 0.95), 0.07, 0.14)   # 白核(细)
		battle._damage._apply_damage_from(u, first, battle._atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
		battle._damage._apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
		battle._vfx._hit_spark(first)
		for o in battle._targeting._enemies_of(u):
			if not is_same(o, first) and battle._on_line(first["pos"], dir4, o["pos"], 50.0):
				battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, [0.75, 1.0, 1.4][si], o), Color("#ff8aa0"), 0.0, false, true)
				battle._damage._apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si] * 0.5)), u)   # 身后50%流血

func _eq_shotgun_blast(u: Dictionary, si: int) -> void:   # 霰弹贝古053: 朝最近敌扇形散开, 每颗弹珠沿自己的直线飞, 撞到第一个敌人才结算伤害并消失; 被8发及以上命中→眩晕
	if not u.get("alive", false): return
	var t53 = battle._targeting._nearest_enemy(u)
	var dir53: Vector2 = (t53["pos"] - u["pos"]).normalized() if t53 != null else Vector2.RIGHT
	battle._muzzle_flash(u["pos"], dir53, Color("#ffe0a0"))
	battle._skill_ring(u["pos"] + dir53 * 22.0, Color(1.0, 0.85, 0.4, 0.7), 26.0)
	var n53: int = [12, 14, 18][si]
	var step53: float = deg_to_rad(battle.SHOTGUN_PELLET_DEG)
	var touched: Array = []
	var maxdur: float = 0.0
	for k in range(n53):
		var off53: float = (float(k) - float(n53 - 1) * 0.5) * step53   # 均匀分布在中线两侧
		var d53: Vector2 = dir53.rotated(off53)
		var hit53 = _eq_first_in_line(u, d53, 40.0)                     # 这条线上最近的敌人=挡住这颗弹珠的那个
		var endp: Vector2 = (hit53["pos"] if hit53 != null else u["pos"] + d53 * 1800.0)   # 没挡住→无限飞出场外
		var dur53: float = clampf(u["pos"].distance_to(endp) / 1500.0, 0.10, 0.75)         # 恒定弹速
		maxdur = maxf(maxdur, dur53)
		if hit53 == null:
			battle._ballistics._shotgun_pellet(u["pos"], endp, Color(1.0, 0.86, 0.5, 0.95), dur53)
			continue
		if not battle._arr_has_unit(touched, hit53): touched.append(hit53)
		var _tg: Dictionary = hit53
		battle._ballistics._shotgun_pellet(u["pos"], endp, Color(1.0, 0.86, 0.5, 0.95), dur53, func() -> void:
			if not _tg.get("alive", false): return
			battle._damage._apply_damage_from(u, _tg, battle._atk_dmg(u, 0.22, _tg), Color("#ffd07a"), 0.0, false, true)
			_tg["_sg_hits"] = int(_tg.get("_sg_hits", 0)) + 1)
	# 全部弹珠落地后再判眩晕(命中计数记在单位自身字段 —— 不拿单位字典当Dict键, 见 2026-07-19 卡死教训)
	if touched.is_empty(): return
	battle._pending_shots.append({"delay": maxdur + 0.06, "src": u, "fn": func() -> void:
		for o in touched:
			if int(o.get("_sg_hits", 0)) >= 8 and o.get("alive", false): battle._freeze(o, battle.CTRL_SEC)
			o.erase("_sg_hits")})

func _eq_pistol_volley(u: Dictionary, si: int) -> void:   # 黄铜手铳048: 每8秒依次射4/5/6发, 每发命中直线首敌(错峰: 枪口闪+子弹+火花)
	if not u.get("alive", false): return
	var t48 = battle._targeting._nearest_enemy(u)
	var dir48: Vector2 = (t48["pos"] - u["pos"]).normalized() if t48 != null else Vector2.RIGHT
	var mul48: float = [0.5, 0.54, 0.6][si]
	var fire48 := func():
		if not u.get("alive", false): return
		var ft48 = _eq_first_in_line(u, dir48, 36.0)
		if ft48 == null: return
		battle._muzzle_flash(u["pos"], dir48, Color("#ffe08a"))
		battle._spawn_eq_bolt(u, ft48, battle._atk_dmg(u, mul48, ft48), "res://assets/sprites/vfx/bullet.png", Color("#fff0b0"), false, 0, 0.026)
	battle._queue_shots([4, 5, 6][si], 0.08, fire48, u)

func _eq_ripple_tick(u: Dictionary, si: int) -> void:
	var low042 = null; var lv042 := INF
	if si == 2:
		for o in battle._targeting._allies_of(u):
			var p042: float = CombatMath.hp_frac(o["hp"], o["maxHp"])
			if p042 < lv042: lv042 = p042; low042 = o
	for o in battle._targeting._allies_of(u):
		var pct042: float = [0.03, 0.06, 0.10][si]
		if si == 2 and is_same(o, low042): pct042 *= 2.0
		var amt42: float = (o["maxHp"] - o["hp"]) * pct042
		if amt42 >= 1.0:
			battle._damage._heal(o, amt42)
			battle._ripple_heal_vfx(o["pos"], 105.0)   # AI生成涟漪回血动画

func _eq_revolver_tick(u: Dictionary, si: int, stt: Dictionary) -> void:
	if int(stt.get("revolver_bullets", 0)) > 0:
		var es3 = battle._targeting._pick_enemies_of(u)
		if not es3.is_empty():
			stt["revolver_bullets"] = int(stt["revolver_bullets"]) - 1
			var o = es3[battle._battle_rng.randi() % es3.size()]
			battle._muzzle_flash(u["pos"], (o["pos"] - u["pos"]), Color("#ffe08a"))
			battle._spawn_eq_bolt(u, o, battle._resolve_dmg(u, u["atk"] * [3.0, 5.0, 9.0][si] + [150.0, 310.0, 1200.0][si], o, false), "res://assets/sprites/vfx/bullet.png", Color("#ffe6a8"), false, 0, 0.034)   # 左轮重弹(真子弹, 大一号)

# 蛋糕蜡烛037: 头顶悬浮真蜡烛精灵(带火苗辉光), 随相位 熄灭/微弱/燃烧 亮暗变化; 持续存在直到携带者死
func _eq_candle_tick(u: Dictionary, si: int, stt: Dictionary) -> void:
	battle._ensure_candle(u)
	var c = u.get("_candle_spr", null)
	var ph: int = int(stt.get("candle", 0))
	stt["candle"] = (ph + 1) % 3
	if ph == 0:   # 熄灭: 蜡烛变暗(火苗弱下去, 无效果)
		if c != null and is_instance_valid(c):
			battle._reg_tween().tween_property(c, "modulate", Color(0.5, 0.5, 0.58, 1.0), 0.35)
	elif ph == 1:   # 微弱: 蜡烛点亮 + 250码光圈 + 圈内友军5s逐渐回血
		if c != null and is_instance_valid(c):
			battle._reg_tween().tween_property(c, "modulate", Color(1, 1, 1, 1), 0.35)
		var hv37: float = [20, 30, 44][si] + u["atk"] * [0.5, 0.7, 1.0][si]
		battle._heal_circle_vfx(u["pos"], 250.0, 5.0)   # AI生成回血阵动画
		u["candle_hot_rate"] = hv37 / 5.0
		u["candle_hot_until"] = battle._t + 5.0
		for a37 in battle._targeting._allies_of(u, false):
			if a37["pos"].distance_to(u["pos"]) <= 250.0:
				a37["candle_hot_rate"] = (hv37 * 0.5) / 5.0
				a37["candle_hot_until"] = battle._t + 5.0
	elif ph == 2:   # 燃烧: 火苗爆燃(蜡烛过亮+弹一下) + 原地爆炸, 499码内敌各受魔法伤+灼烧
		if c != null and is_instance_valid(c):
			var ct = battle._reg_tween(); ct.set_parallel(true)
			ct.tween_property(c, "modulate", Color(1.4, 1.15, 0.85, 1.0), 0.12)
			ct.tween_property(c, "scale", Vector3.ONE * 1.3, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			ct.chain().tween_property(c, "scale", Vector3.ONE, 0.25)
		battle._boom_wave(u["pos"], 260.0)   # AI生成爆炸波动画(原地大爆炸)
		battle._shake(0.06)
		var dmg37: float = float([20, 30, 44][si]) + u["atk"] * [0.5, 0.7, 1.0][si]
		for o in battle._targeting._enemies_of(u):
			if o["pos"].distance_to(u["pos"]) <= 500.0:   # 499→500(用户2026-07-19)
				battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, dmg37, o, true), Color("#ffb066"), 0.0, false, true)   # 魔法伤(蓝字), 非真伤
				battle._damage._apply_dot_stacks(o, "burn", [20, 30, 40][si], u)
				battle._boom_wave(o["pos"], 110.0)   # 每个被波及敌小爆

func _eq_signal_tick(u: Dictionary, si: int) -> void:
	var lo: Array = [0.10, 0.25, 0.70]; var hi: Array = [0.16, 0.40, 0.80]
	var amp: float = randf_range(lo[si], hi[si])
	# 真·增伤(damage_amp): 放大所有伤害, 不再是 +%攻击力(那样只放大吃ATK的段·用户2026-07-19"38要是amp")
	var contributed: float = float(u.get("signal_amp", 0.0))
	u["damage_amp"] = maxf(0.0, float(u.get("damage_amp", 0.0)) - contributed)      # 先撤掉本件的旧贡献
	var cur: float = (contributed if battle._t < float(u.get("signal_until", 0.0)) else 0.0)  # 已过期则不参与"取较大者"
	amp = maxf(cur, amp)
	u["damage_amp"] = float(u.get("damage_amp", 0.0)) + amp
	u["signal_amp"] = amp
	u["signal_until"] = battle._t + 3.5
	battle._signal_pulse(u["pos"])
	battle._vfx._float_text(u["pos"] + Vector2(0, -58), "增伤+%d%%" % int(amp * 100.0), Color("#ffcf5a"))

# 信号脉冲(038): 头顶弹出青蓝 signal-wave 广播图标(升起放大淡出, 2个错峰=脉冲广播) + 脚下青光环
func _eq_fpga_tick(u: Dictionary, si: int) -> void:
	battle._skill_ring(u["pos"], Color(0.4, 0.9, 1.0, 0.42), 46.0)
	var codes := ["00", "01", "10", "11"]
	var ccols := [Color("#7ad0ff"), Color("#a0ff8a"), Color("#ffd05a"), Color("#ff8ad0")]
	var n: int = [1, 2, 4][si]
	for k in range(n):
		var pick: int = battle._battle_rng.randi() % 4
		var xoff: float = (float(k) - float(n - 1) / 2.0) * 34.0
		battle._vfx._float_text(u["pos"] + Vector2(xoff, -72.0), codes[pick], ccols[pick])   # 二进制码头顶跳
		match pick:
			0: battle._damage._heal(u, u["maxHp"] * 0.05); u["base_def"] += 12; u["base_mr"] += 12; battle._recalc_stats(u)   # 用户2026-07-19: +2 → +12
			1: u["base_atk"] += 15; u["lifesteal"] += 0.07; battle._recalc_stats(u)                            # 用户2026-07-19: +5/+4% → +15/+7%
			2:
				u["damage_amp"] = float(u.get("damage_amp", 0.0)) + 0.15   # 10: 真·增伤(放大所有伤害·用户2026-07-19"amp要"); 原 battle._damage._buff(atk,15%) 只放大吃ATK的段, 而040自己不给攻击力
				battle._pending_shots.append({"delay": 3.5, "fn": func(): u["damage_amp"] = maxf(0.0, float(u.get("damage_amp", 0.0)) - 0.15), "src": u})
			3:
				u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + 0.25   # 11: 受到伤害-25%(真伤除外·用户2026-07-19: 原误做+25%护甲对魔/真伤无效→改真减伤)
				battle._pending_shots.append({"delay": 3.5, "fn": func(): u["damage_reduction"] = maxf(0.0, float(u.get("damage_reduction", 0.0)) - 0.25), "src": u})


func _eq_ebb_surge(u: Dictionary, hp_add: float, atk_add: float, dur: float) -> void:   # 退潮浊液041: 涨潮期开始
	if not u.get("alive", false) or u.get("_ebb_on", false): return
	u["_ebb_on"] = true
	u["maxHp"] += hp_add; u["hp"] += hp_add
	u["base_atk"] = float(u.get("base_atk", 0.0)) + atk_add
	u["atk_range"] = float(u.get("atk_range", 70.0)) + 50.0
	u["size_mult"] = float(u.get("size_mult", 1.0)) * 1.3      # 体积+30%(走size_mult, 每帧juice从base起算不会覆盖)
	battle._recalc_stats(u)
	battle._ebb_tide_fx(u, true)
	battle._vfx._float_text(u["pos"] + Vector2(0, -70), "涨潮", Color("#5fe0d0"))
	battle._pending_shots.append({"delay": dur, "fn": func(): _eq_ebb_recede(u, hp_add, atk_add), "src": u})

func _eq_ebb_recede(u: Dictionary, hp_add: float, atk_add: float) -> void:   # 退潮浊液041: 到期还原
	if not u.get("_ebb_on", false): return
	u["_ebb_on"] = false
	u["maxHp"] = maxf(1.0, float(u["maxHp"]) - hp_add)
	u["hp"] = minf(float(u["hp"]), float(u["maxHp"]))          # 退潮不致死, 只削到新上限
	u["base_atk"] = maxf(0.0, float(u.get("base_atk", 0.0)) - atk_add)
	u["atk_range"] = maxf(10.0, float(u.get("atk_range", 70.0)) - 50.0)
	u["size_mult"] = maxf(0.01, float(u.get("size_mult", 1.0)) / 1.3)
	battle._recalc_stats(u)
	if u.get("alive", false):
		battle._ebb_tide_fx(u, false)
		battle._vfx._float_text(u["pos"] + Vector2(0, -70), "退潮", Color("#8fb8c8"))

func _eq_dumbbell_routine(u: Dictionary, si: int) -> void:   # 原地锻炼(锁攻+锁充能)→+锻炼层(maxHp,局内每场重置)→蓄力→掷哑铃击退
	if not u.get("alive", false): return
	u["_slam"] = true   # 锁AI/普攻/移动/龟能充能(都在_tick_unit早返回前)
	for _b in range(3):   # 锻炼动作: 3下蹲起形变
		if not u.get("alive", false): u["_slam"] = false; return
		battle._anticipate(u)
		await battle._wait_sim(0.3)
	if not is_instance_valid(self): return
	var stt: Dictionary = u["eq_state"].get("p2eq_020", {})   # 锻炼层(eq_state局内计数, 每场战斗重置)
	stt["exercise"] = int(stt.get("exercise", 0)) + 1
	u["eq_state"]["p2eq_020"] = stt
	var gain: float = [40.0, 75.0, 110.0][si]   # 锻炼层+maxHp&当前生命(用户2026-07-19: 20/25/30→40/75/110)。★不乘HP_MULT: 装备hp已是最终值(见L45规则), 原来乘了→实发120/225/330=文案的3倍
	u["maxHp"] += gain; u["hp"] += gain
	battle._skill_ring(u["pos"], Color(0.8, 0.9, 1.0, 0.42), 48.0)   # 锻炼强化光
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)   # 蓄力
	await battle._wait_sim(0.35)
	u["_slam"] = false
	if not u.get("alive", false): return
	var t = battle._targeting._nearest_enemy(u)
	if t == null: return
	var dmg: int = maxi(1, int(u["maxHp"] / battle.HP_MULT * [0.05, 0.07, 0.10][si]))
	battle._throw_dumbbell(u, t, dmg)

func _eq_fuel_throw(u: Dictionary, si: int) -> void:   # 余烬燃油瓶022: 每8秒→短蓄力→抛物线掷出火瓶(翻滚·余烬拖尾)→碎裂溅火+灼烧+真火5秒
	if not u.get("alive", false): return
	if battle._targeting._nearest_enemy(u) == null: return
	battle._anticipate(u)   # 短蓄力
	await battle._wait_sim(0.3)
	if not is_instance_valid(self) or not u.get("alive", false): return
	var t = battle._targeting._nearest_enemy(u)
	if t == null: return
	var from2d: Vector2 = u["pos"]
	var to2d: Vector2 = t["pos"]
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/sprites/equip/ember-flask.png")   # 真瓶子立绘当投掷物(原来是一团光球)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # ★翻滚要真转; BILLBOARD会吃掉roll(001飞斩的教训)
	spr.shaded = false; spr.transparent = true
	spr.no_depth_test = true; spr.render_priority = 5
	spr.pixel_size = (42.0 * battle.WS) / float(maxi(1, spr.texture.get_height()))
	spr.position = battle._world_pos(from2d, 1.15)
	battle._world.add_child(spr)
	var dist: float = from2d.distance_to(to2d)
	var tw = battle._reg_tween()
	tw.tween_method(battle._fuel_flask_step.bind(spr, from2d, to2d, clampf(dist / 900.0, 0.55, 1.5)), 0.0, 1.0, clampf(dist / 620.0, 0.45, 1.05))
	tw.tween_callback(battle._fuel_bottle_hit.bind(spr, u, t, si))

# 028 冰霜冻露瓶: 蓄力→抛物线缓慢扔冰瓶→砸敌魔法伤+冰寒+冰爆
func _eq_ice_throw(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	if battle._targeting._nearest_enemy(u) == null: return
	battle._anticipate(u)
	var tw = battle._reg_tween()
	tw.tween_interval(0.32)
	tw.tween_callback(battle._ice_throw_go.bind(u, si))

func _eq_broadsword(u: Dictionary, si: int) -> void:   # 锈蚀阔剑007(重做·用户2026-07-19): 朝方向高举斩→宽刃剑气墙沿dir扫2000码(wisp_dir朝向·等距不歪)+贴地冲击带(no_depth_test)·命中给盾
	var flat: int = [20, 35, 60][si]
	var sc: float = [0.5, 0.8, 1.1][si]
	var shp: float = [0.5, 0.75, 1.0][si]
	var t = battle._targeting._nearest_enemy(u)
	var dir: Vector2 = ((t["pos"] - u["pos"]).normalized() if t != null else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)
	var front: Vector2 = u["pos"] + dir * 55.0
	var zsgn: float = 1.0 if dir.x >= 0.0 else -1.0   # 挥砍方向: 敌在左则镜像上扬/下劈
	# ① 起手: 阔剑高举(朝挥击侧)→下劈 (保留节奏/动作)
	var sword := Sprite3D.new()
	sword.texture = VfxTex._make_vblade_texture(Color(0.92, 0.94, 1.0))
	sword.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sword.shaded = false; sword.transparent = true
	sword.pixel_size = 0.015
	sword.offset = Vector2(0, 38)
	sword.flip_h = dir.x < 0.0                        # 朝挥击方向那侧
	sword.modulate = Color(0.92, 0.94, 1.0, 0.0)
	sword.position = battle._world_pos(front, 0.6)
	sword.rotation = Vector3(-0.6, 0.0, 1.15 * zsgn)  # x=面镜头, z=上扬蓄势(随方向镜像)
	sword.scale = Vector3(0.5, 0.5, 0.5)
	battle._world.add_child(sword)
	var gt = battle._reg_tween(); gt.set_parallel(true)
	gt.tween_property(sword, "modulate:a", 1.0, 0.28)
	gt.tween_property(sword, "scale", Vector3(1.5, 1.5, 1.5), 0.4)
	await battle._wait_sim(0.6)
	if not u.get("alive", false):
		if is_instance_valid(sword): sword.queue_free()
		return
	var dt = battle._reg_tween()   # 下劈: z从上扬挥到下劈(随方向镜像)
	dt.tween_property(sword, "rotation:z", -1.35 * zsgn, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await dt.finished
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._splash_ring_bold(front, Color(1.0, 0.5, 0.24, 0.92), 130.0)   # 劈地冲击环(赤金·no_depth_test·不被地板盖)
	if is_instance_valid(sword):
		var sf = battle._reg_tween(); sf.tween_property(sword, "modulate:a", 0.0, 0.16); sf.tween_callback(sword.queue_free)
	# ② 宽刃剑气墙沿dir扫2000码 (wisp_dir朝向: 凸刃立起·尖朝行进方向·等距不歪) — 有效+特效距离均2000(用户)
	if battle._bladewall_tex == null: battle._bladewall_tex = VfxTex._make_bladewall_texture(Color(1.0, 0.36, 0.18))   # 炽焰赤金: 白热前刃→橙红刃身(对比青地板·破甲灼刃)
	var qi := Sprite3D.new()
	qi.texture = battle._bladewall_tex
	qi.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	qi.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 手动basis: camera_basis×roll(尖朝dir屏幕方向)
	qi.shaded = false; qi.transparent = true
	qi.pixel_size = 0.058
	qi.modulate = Color(1.0, 0.96, 0.9, 0.98)   # 近白暖调, 让贴图赤金本色出来(不二次染色)
	battle._world.add_child(qi)
	var obasis: Basis = (battle._cam.global_transform.basis if battle._cam != null else Basis.IDENTITY)   # dir恒定→朝向算一次
	if battle._cam != null:
		var s0: Vector2 = battle._cam.unproject_position(battle._world_pos(front, 0.9))
		var s1: Vector2 = battle._cam.unproject_position(battle._world_pos(front + dir * 60.0, 0.9))
		var sd: Vector2 = s1 - s0
		if sd.length() > 0.5:
			obasis = battle._cam.global_transform.basis * Basis(Vector3(0, 0, 1), atan2(-sd.y, sd.x) - PI / 2.0)
	var reach := 2000.0
	var traveled := 0.0
	var trail_next := 0.0
	var hit: Array = []
	while traveled < reach and is_instance_valid(qi) and is_instance_valid(self):
		await battle.get_tree().process_frame
		if not u.get("alive", false): break
		traveled += 820.0 * battle.get_process_delta_time()
		var pos: Vector2 = front + dir * traveled
		qi.global_transform = Transform3D(obasis, battle._world_pos(pos, 0.9))
		if traveled >= trail_next:                    # 贴地冲击带: 沿途撒no_depth_test小环(floor-proof)
			trail_next += 240.0
			battle._splash_ring_bold(pos, Color(1.0, 0.46, 0.2, 0.55), 85.0)   # 赤金贴地拖痕
		for o in battle._targeting._enemies_of(u):
			if not o.get("alive", false): continue
			var seen := false
			for h in hit:
				if is_same(h, o): seen = true; break   # ★引用比较(is_same)·不用 o in hit(字典内容哈希=053卡死同类坑)
			if seen: continue
			if (o["pos"] - front).dot(dir) <= traveled and battle._on_line(front, dir, o["pos"], 95.0):
				hit.append(o)
				var dd: int = battle._resolve_dmg(u, u["atk"] * sc + float(flat), o, false)
				battle._damage._apply_damage_from(u, o, dd, Color("#dfe8ff"), 0.0, false, true)
				battle._damage._grant_shield(u, dd * shp)             # 命中一个即给盾(用户)
				battle._weapon_slash(u["pos"], o["pos"], Color(1.0, 0.62, 0.34))   # 命中破甲斩弧(赤金)
				battle._vfx._hit_spark(o)
	if is_instance_valid(qi):
		var ft = battle._reg_tween(); ft.tween_property(qi, "modulate:a", 0.0, 0.2); ft.tween_callback(qi.queue_free)


func _eq_sword_storm(u: Dictionary, si: int) -> void:   # 千刃风暴(用户改造): 蓄力→身后召一排剑→剑阵前移穿过全体敌
	var flat: int = [70, 100, 400][si]
	var sc: float = [0.8, 1.3, 4.0][si]
	var t = battle._targeting._nearest_enemy(u)
	var dir: Vector2 = ((t["pos"] - u["pos"]).normalized() if t != null else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var ang: float = -atan2(dir.y, dir.x)
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)
	var glow := Sprite3D.new()
	glow.texture = VfxTex._make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
	glow.modulate = Color(0.7, 0.82, 1.0, 0.0); glow.pixel_size = 0.02
	glow.position = battle._world_pos(u["pos"] - dir * 100.0, 1.0)
	battle._world.add_child(glow)
	var gt = battle._reg_tween()
	gt.tween_property(glow, "modulate:a", 0.85, 0.4)
	gt.parallel().tween_property(glow, "scale", Vector3(2.8, 2.8, 2.8), 0.45)
	await battle._wait_sim(0.45)
	if is_instance_valid(glow): glow.queue_free()
	if not u.get("alive", false): return
	var n := 7
	var swords: Array = []
	for k in range(n):   # 生成剑: 身后错峰淡入+放大(先横排, 垂直行进)
		var off: float = (float(k) - float(n - 1) / 2.0) * 85.0
		var sp := Sprite3D.new()
		sp.texture = VfxTex._make_sword_texture(Color(0.85, 0.9, 1.0))
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sp.axis = Vector3.AXIS_Y
		sp.shaded = false; sp.transparent = true; sp.pixel_size = 0.07
		sp.rotation = Vector3(0.0, ang + PI / 2.0, 0.0)
		sp.position = battle._world_pos(u["pos"] - dir * 130.0 + perp * off, 0.4)
		sp.modulate = Color(0.85, 0.9, 1.0, 0.0)
		sp.scale = Vector3(0.3, 0.3, 0.3)
		battle._world.add_child(sp)
		var st = battle._reg_tween(); st.set_parallel(true)
		st.tween_property(sp, "modulate:a", 0.95, 0.2).set_delay(float(k) * 0.03)
		st.tween_property(sp, "scale", Vector3.ONE, 0.25).set_delay(float(k) * 0.03)
		swords.append(sp)
	await battle._wait_sim(0.42)   # 等一排剑生成完
	if not u.get("alive", false): return
	for spr in swords:   # 调转方向: 一排剑同时旋转对准行进方向(带回弹)
		if is_instance_valid(spr):
			battle._reg_tween().tween_property(spr, "rotation:y", ang, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await battle._wait_sim(0.34)
	if not u.get("alive", false): return
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	var reach := 1050.0
	var traveled := 0.0
	var hit: Array = []
	while traveled < reach and is_instance_valid(self):
		await battle.get_tree().process_frame
		traveled += 650.0 * battle.get_process_delta_time()   # 剑速(用户:慢点)
		var front_along: float = -130.0 + traveled
		for i in range(swords.size()):
			var sp = swords[i]
			if is_instance_valid(sp):
				var off2: float = (float(i) - float(n - 1) / 2.0) * 85.0
				sp.position = battle._world_pos(u["pos"] + dir * front_along + perp * off2, 0.4)
		for o in battle._targeting._enemies_of(u):
			if battle._arr_has_unit(hit, o) or not o.get("alive", false): continue
			if (o["pos"] - u["pos"]).dot(dir) <= front_along:
				hit.append(o)
				battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, u["atk"] * sc + float(flat), o, false), Color("#dfe8ff"), 0.0, false, true)
				battle._skill_ring(o["pos"], Color(0.82, 0.9, 1.0, 0.5), 44.0)
	for sp2 in swords:
		if is_instance_valid(sp2):
			var ft = battle._reg_tween()
			ft.tween_property(sp2, "modulate:a", 0.0, 0.14)
			ft.tween_callback(sp2.queue_free)

# ---- 暴君之牙p2eq_004 主动: 剧毒獠牙(参考LoL蛇女Cassiopeia E「双生毒牙」·用户2026-07-19) ----
func _eq_tyrantfang_tick(u: Dictionary, si: int) -> void:   # 每6秒(经_EQ_CUSTOM_IV)射毒牙: 魔法伤1/1.8/4×ATK + 回复100%造成伤害(削弱·用户2026-07-23, 原2/3/7)
	var t = battle._targeting._nearest_enemy(u)
	if t == null: return
	battle._ballistics._fire_venom_fang(u, t, [1.0, 1.8, 4.0][si] * float(u.get("atk", 0.0)))

# 给单位"+N点龟能": 实时版龟能=冷却充能同一事实, 折算 N×0.075 秒扣掉所有技能剩余冷却.
func _eq_grant_energy(u: Dictionary, amount: float) -> void:   # 给龟能=存"龟能银行"(溢出留到下次不浪费, 用户: 贝母021)
	if amount <= 0.0:
		return
	u["energy_bank"] = float(u.get("energy_bank", 0.0)) + amount
	battle._apply_energy_bank(u)

# 娜美式潮浪(海浪护符043): 朝敌人2D方向的对角潮浪 — 从敌人反方向(身后)400码涌起 → 沿"朝敌人"方向慢速推过全场 → 连续宽浪墙(垂直于行进方向铺开)翻涌 → 命中击飞(用户2026-07-04: 全场横扫+2D对角朝敌)
func _eq_water_wave(u: Dictionary, si: int) -> void:
	var enemies = battle._targeting._enemies_of(u)
	var allies = battle._targeting._allies_of(u)
	var ec: Vector2 = u["pos"] + Vector2(500.0, 0.0)   # 敌人质心(默认右)
	if not enemies.is_empty():
		ec = Vector2.ZERO
		for e in enemies: ec += e["pos"]
		ec /= float(enemies.size())
	var dvec: Vector2 = ec - u["pos"]
	var dir: Vector2 = Vector2.RIGHT if dvec.length() < 1.0 else dvec.normalized()   # 浪行进方向=朝敌人(2D可对角)
	var perp: Vector2 = Vector2(-dir.y, dir.x)          # 浪墙铺开方向(垂直于行进)
	var startc: Vector2 = u["pos"] - dir * 400.0        # 敌人反方向(身后)400码涌起
	var maxfwd: float = 0.0; var pmin: float = INF; var pmax: float = -INF
	for o in allies + enemies:
		maxfwd = maxf(maxfwd, (o["pos"] - startc).dot(dir))       # 沿行进方向最远单位
		var pp: float = (o["pos"] - u["pos"]).dot(perp)           # 沿浪墙方向的跨度
		pmin = minf(pmin, pp); pmax = maxf(pmax, pp)
	if pmin > pmax: pmin = -150.0; pmax = 150.0
	var tdist: float = maxfwd + 320.0                   # 推过最远单位再多320
	var windup: float = 0.5
	var travel: float = 2.0                             # 慢速(用户)
	battle._anticipate(u)
	battle._water_charge_windup(u, windup)
	battle._spawn_tidal_wave(startc, dir, perp, pmin - 75.0, pmax + 75.0, tdist, windup, travel)
	for o in allies:
		var oo: Dictionary = o
		var fwd: float = clampf((o["pos"] - startc).dot(dir), 0.0, tdist)
		var d: float = windup + fwd / tdist * travel
		var fn := func():
			if not oo.get("alive", false): return
			battle._damage._grant_shield(oo, [40.0, 95.0, 120.0][si])
			oo["base_def"] += [2, 3, 5][si]; oo["base_mr"] += [2, 3, 5][si]; battle._recalc_stats(oo)
			battle._water_splash(oo["pos"], true)
		battle._pending_shots.append({"delay": d, "fn": fn, "src": u})
	for o in enemies:
		var oo2: Dictionary = o
		var fwd2: float = clampf((o["pos"] - startc).dot(dir), 0.0, tdist)
		var d2: float = windup + fwd2 / tdist * travel
		var fn2 := func():
			if not oo2.get("alive", false): return
			battle._damage._apply_damage_from(u, oo2, battle._resolve_dmg(u, float([60, 110, 200][si]), oo2, true), Color("#9be7ff"), 0.0, false, true)   # 魔法伤(蓝字)
			oo2["base_def"] = maxf(0.0, oo2["base_def"] - [2, 3, 5][si]); oo2["base_mr"] = maxf(0.0, oo2["base_mr"] - [2, 3, 5][si]); battle._recalc_stats(oo2)
			battle._water_splash(oo2["pos"], false)
			battle._knock_up(oo2, oo2["pos"] - dir * 60.0, 6.5)   # 娜美式击飞: 顺浪方向往前推(非直上)
			battle._vfx._hit_spark(oo2)
		battle._pending_shots.append({"delay": d2, "fn": fn2, "src": u})

# 潮浪墙: 沿perp(垂直行进)铺一排大浪crest拼成连续宽墙, 整墙从startc沿dir推进tdist; 翻涌帧循环
# 开战: 全装备纯属性 + 永久 flag 加到携带者 (在 spawn 被动之后, 让属性叠上不被覆盖).
# ── 工具 ──
# ── 工具 ──
func _eq_si(star: int) -> int:
	return clampi(star, 1, 3) - 1

func _eq_first_in_line(u: Dictionary, dir: Vector2, width: float):
	var best = null; var bd := INF
	for o in battle._targeting._pick_enemies_of(u):
		if battle._on_line(u["pos"], dir, o["pos"], width):
			var dd: float = (o["pos"] - u["pos"]).length_squared()
			if dd < bd: bd = dd; best = o
	return best

func _eq_farthest_enemies(u: Dictionary, half: bool) -> Array:
	var es = battle._targeting._enemies_of(u)
	es.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() > (b["pos"] - u["pos"]).length_squared())
	if half:
		return es.slice(0, maxi(1, es.size() / 2))
	return es

# 某一方是否有存活单位携带某装备 (飞镖靶子标记用)
func _eq_charge(stt: Dictionary, key: String, amt: float, cap: float, on_full: Callable) -> void:
	var a: float = (amt * 0.5 if _eq_drone_halve else amt)   # 浮游炮触发→充能减半
	var v: float = float(stt.get(key, 0.0)) + a
	if v >= cap:
		stt[key] = v - cap
		on_full.call()
	else:
		stt[key] = v

# ============================================================================
#  on-hit (每段命中后, attacker 视角)
# ============================================================================
# ============================================================================
#  on-hit (每段命中后, attacker 视角)
# ============================================================================
func _eq_on_hit(src: Dictionary, tgt: Dictionary, dmg: int) -> void:
	if src.get("equips", []).is_empty():
		return
	# AoE 判定(启发式): 同帧内 src 命中≥2个不同目标 → 范围技能 (供 002 等"范围减半"用; 首个目标算单体)
	var _fr: int = Engine.get_process_frames()
	if int(src.get("_onhit_fr", -1)) != _fr:
		src["_onhit_fr"] = _fr; src["_onhit_tgts"] = []
	var _otl: Array = src["_onhit_tgts"]
	if not battle._arr_has_unit(_otl, tgt): _otl.append(tgt)
	var is_aoe: bool = _otl.size() >= 2
	for e in src["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = src["eq_state"].get(iid, {})
		match iid:
			"p2eq_004":   # 暴君之牙: 处决<斩杀线敌 (削弱·用户2026-07-23: 斩杀线 4/6/12% ×(1+暴击率), 原 5/7/10%+10/15/40%×暴击)
				var line: float = [0.04, 0.06, 0.12][si] * (1.0 + float(src["crit"]))
				if tgt["alive"] and not tgt.get("eq_exec_immune", false) and tgt["hp"] < tgt["maxHp"] * line:
					var was: bool = tgt["alive"]
					battle._vfx._float_text(tgt["pos"], "-999999", battle._VC.color_of(battle._VC.cls_for("damage", "true", true)), true, "damage", "true")   # 处决=固定跳-999999真伤大字(实际伤害=剩余血, 用户)
					tgt["hp"] = 0.0
					if was: battle._kill(tgt, src)
			"p2eq_002":   # 海带卷刀: 命中→施加流血层 (范围技能触发减半; 3★流血层数天然可叠)
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"] * (0.5 if is_aoe else 1.0)))
				battle._damage._apply_dot_stacks(tgt, "bleed", battle._cyeq_n(bs), src)
			"p2eq_003":   # 锋利鲨齿: 溅射200码内敌 + 醒目双层冲击环(no_depth_test防地板盖)+每敌立式火花(用户2026-07-19)
				var frac: float = [0.15, 0.28, 0.50][si]
				battle._splash_ring_bold(tgt["pos"], Color(1.0, 0.80, 0.36, 0.95), 200.0)   # 醒目双环从命中点扩到200码·恒画在地板之上
				for o in battle._targeting._enemies_of(src):
					if not is_same(o, tgt) and (o["pos"] - tgt["pos"]).length() <= 200.0:
						battle._damage._apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
						battle._vfx._hit_spark(o)   # 每个被溅射敌人身上一记立式火花(胸高billboard·地板高度盖不住)
			"p2eq_005":   # 双生匕首: 命中概率追加一刀双生刺击
				if battle._battle_rng.randf() < [0.5, 0.75, 1.0][si]:
					battle._damage._apply_damage_from(src, tgt, battle._atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ff4444"), 0.0, false, true)
			"p2eq_023":   # 灼热火珊瑚(被动): 每段额外灼烧 + 充能
				var burn: int = maxi(1, roundi([2.0, 5.0, 8.0][si] + [0.07, 0.11, 0.15][si] * src["atk"]))
				battle._damage._apply_dot_stacks(tgt, "burn", battle._cyeq_n(burn), src)
				_eq_charge(stt, "fire_mana", 10.0, 100.0, func(): _eq_fire_coral_active(src, si))   # 法力: 每段命中+10, 满100放主动(用户2026-07-19: 原每段+1满8)
			"p2eq_009":   # 宽刃弯刀: 充刃能, 满100→直线伤害
				_eq_charge(stt, "blade_energy", [20.0, 20.0, 25.0][si] * (0.5 if is_aoe else 1.0), 100.0, func(): _eq_wide_blade(src, tgt, si))
			"p2eq_026":   # 雷电法杖: 充能25, 满100→连锁闪电
				_eq_charge(stt, "thunder", 25.0, 100.0, func(): battle._chain_windup(src, si))
			"p2eq_029":   # 冰封水母: 概率额外魔伤+冻结, 冻结→自护盾
					pass
			"p2eq_054":   # 瞄准镜: 必中→命中时目标身上一瞬锁定框(表现无视闪避)
				battle._reticle_flash(tgt, Color("#ff6a5a"))
			"p2eq_055":   # 靶向器: 命中标记目标 (+20% 受伤) 2回合
				tgt["eq_marked_until"] = battle._t + 5.0
				battle._mark_vfx(tgt, 5.0, Color("#ff4d4d"))
		src["eq_state"][iid] = stt

# 雷电法杖 026: 连锁闪电
# 雷电法杖 026: 连锁闪电
func _eq_chain_lightning(u: Dictionary, si: int) -> void:
	var enemies = battle._targeting._enemies_of(u)
	if enemies.is_empty():
		return
	var hops: int = [4, 5, 6][si]
	var dmg: int = [40, 60, 90][si]
	# 目标序列: 首个随机, 之后每跳=离当前最近(优先未命中; 无未命中则跳已命中, 排除刚打的→两目标间来回弹)
	var seq: Array = []
	var hit: Array = []  # ★2026-07-10 闪退真因: 不能拿【单位字典】当 Dictionary 的 key —— Godot 会对 key 求哈希, 单位字典里有 summons/summon_owner 等互相引用的结构 → recursive_hash 无限递归 → 每次查表刷一条 ERROR: Max recursion reached。改用 Array(.has 走 == 不哈希)。
	var first = enemies[battle._battle_rng.randi() % enemies.size()]
	seq.append(first); hit.append(first)
	var cur = first
	for h in range(hops - 1):
		var cpos: Vector2 = cur["pos"]
		var best_new = null; var bd_new := INF
		var best_any = null; var bd_any := INF
		for o in enemies:
			if is_same(o, cur):
				continue
			var d: float = o["pos"].distance_squared_to(cpos)
			if d < bd_any: bd_any = d; best_any = o
			if not battle._arr_has_unit(hit, o) and d < bd_new: bd_new = d; best_new = o
		var nxt = best_new if best_new != null else best_any
		if nxt == null:
			break
		seq.append(nxt); hit.append(nxt); cur = nxt
	# 逐跳错峰(0.12s): 画锯齿弧+命中爆闪+魔法伤害
	var prev_pos: Vector2 = u["pos"]
	for i in range(seq.size()):
		var tgt = seq[i]
		var tw = battle._reg_tween()
		tw.tween_interval(float(i) * 0.2)
		tw.tween_callback(battle._chain_segment.bind(u, prev_pos, tgt, dmg))
		prev_pos = tgt["pos"]

func _eq_laser_sweep(u: Dictionary, tgt: Dictionary, si: int) -> void:   # 扇形斩(120度/半径=射程,3★2×/朝目标)+回血; 只命中1→蓄力→竖劈冲击波
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var ang: float = -atan2(dir.y, dir.x)
	var base_rng: float = float(u.get("atk_range", 70.0))
	var rng: float = base_rng * (2.0 if si == 2 else 1.0)
	battle._anticipate(u)   # 预备
	battle._laser_blade_sweep(u, u["pos"], dir, rng, 60.0)   # 笔直红激光长刃平滑扫过扇形(带拖尾)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	var cos60: float = cos(deg_to_rad(60.0))
	var hits: Array = []
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var d: float = rel.length()
		if d > rng: continue
		if dir.dot(rel / maxf(1.0, d)) < cos60: continue
		hits.append(o)
	var tot: int = 0
	for o in hits:
		var dd: int = battle._resolve_dmg(u, u["atk"] * [0.6, 1.0, 8.0][si] + [15.0, 32.0, 200.0][si], o, false)
		battle._damage._apply_damage_from(u, o, dd, Color("#9bf0ff"), 0.0, false, true)
		tot += dd
	if tot > 0: battle._damage._heal(u, tot * [0.35, 0.8, 1.0][si])
	if hits.size() == 1:
		var glow := Sprite3D.new()
		glow.texture = VfxTex._make_fire_glow_tex()
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
		glow.modulate = Color(1.0, 0.28, 0.3, 0.0); glow.pixel_size = 0.02
		glow.position = battle._world_pos(u["pos"], 1.0)
		battle._world.add_child(glow)
		var gt = battle._reg_tween(); gt.tween_property(glow, "modulate:a", 0.9, 0.2); gt.parallel().tween_property(glow, "scale", Vector3(2.2, 2.2, 2.2), 0.2)
		var tele := Sprite3D.new()   # 蓄力预警线(细红激光, 指示竖劈路径)
		tele.texture = VfxTex._make_laser_beam_tex(Color(1.0, 0.25, 0.28))
		tele.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tele.axis = Vector3.AXIS_Y
		tele.shaded = false; tele.transparent = true
		tele.pixel_size = (base_rng * 2.0) * battle.WS / 100.0
		tele.rotation = Vector3(0.0, ang, 0.0)
		tele.position = battle._world_pos(u["pos"] + dir * base_rng, 0.1)
		tele.scale = Vector3(1.0, 0.35, 1.0); tele.modulate = Color(1.0, 0.3, 0.3, 0.0)
		battle._reg_tween().tween_property(tele, "modulate:a", 0.5, 0.18)
		await battle._wait_sim(0.2)
		if is_instance_valid(tele):
			var telf = battle._reg_tween()
			telf.tween_property(tele, "modulate:a", 0.0, 0.1)
			telf.tween_callback(tele.queue_free)
		if is_instance_valid(glow): glow.queue_free()
		if not u.get("alive", false): return
		_eq_laser_chop(u, hits[0], si, base_rng)

func _eq_laser_chop(u: Dictionary, tgt: Dictionary, si: int, base_range: float) -> void:   # 竖劈冲击波(同斩击伤害/宽80/移动2×射程/短暂击飞0.1s)
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var origin: Vector2 = u["pos"]
	var reach: float = base_range * 2.0
	battle._shake(battle.JUICE_SHAKE_BIG)
	battle._vfx._play_anim_vfx("res://assets/sprites/vfx/laser-cleave-anim.png", tgt["pos"], 155.0, 20.0, 1.5, false)   # 竖劈5帧砸向目标(用户素材·斜刃下落→劈地红爆)
	var wave := Sprite3D.new()
	wave.texture = load("res://assets/sprites/vfx/laser-wave.png")   # 气波·弧形红光墙(用户2026-07-12·横扫新月转90°凸面朝前)
	wave.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wave.billboard = BaseMaterial3D.BILLBOARD_ENABLED; wave.shaded = false; wave.transparent = true
	var _wwh: float = 3.0   # 气波墙世界高
	wave.pixel_size = _wwh / float(maxi(1, int(wave.texture.get_height())))
	wave.modulate = Color(1.0, 0.85, 0.85, 0.98)
	battle._world.add_child(wave)
	var traveled: float = 0.0
	var last_tr: float = -100.0
	var hit: Array = []
	while traveled < reach and is_instance_valid(wave) and is_instance_valid(self):
		await battle.get_tree().process_frame
		traveled += 550.0 * battle.get_process_delta_time()
		wave.position = battle._world_pos(origin + dir * traveled, _wwh * 0.5)   # 底边贴地不入地(用户2026-07-12)
		if traveled - last_tr >= 80.0:   # 气波拖尾: 每隔80码一道淡残影(减少·不糊成雾·用户2026-07-12)
			last_tr = traveled
			var tr := Sprite3D.new()
			tr.texture = wave.texture
			tr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			tr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tr.shaded = false; tr.transparent = true
			tr.pixel_size = wave.pixel_size; tr.scale = wave.scale * 0.9
			tr.position = wave.position; tr.modulate = Color(1.0, 0.55, 0.55, 0.18)
			battle._world.add_child(tr)
			var tt = battle._reg_tween(); tt.tween_property(tr, "modulate:a", 0.0, 0.22); tt.tween_callback(tr.queue_free)
		for o in battle._targeting._enemies_of(u):
			if battle._arr_has_unit(hit, o) or not o.get("alive", false): continue
			if (o["pos"] - origin).dot(dir) <= traveled and battle._on_line(origin, dir, o["pos"], 80.0):
				hit.append(o)
				battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, u["atk"] * [0.6, 1.0, 8.0][si] + [15.0, 32.0, 200.0][si], o, false), Color("#9bf0ff"), 0.0, false, true)
				battle._damage._knockback(u, o, 0.0, 0.2, 0.0)
	if is_instance_valid(wave):
		var wf = battle._reg_tween(); wf.tween_property(wave, "modulate:a", 0.0, 0.15); wf.tween_callback(wave.queue_free)

func _eq_wide_blade(src: Dictionary, tgt: Dictionary, si: int) -> void:   # 宽刃弯刀(用户改造·剑魔Q式): 预警环形扇区(500~800码60度)→黄色月光斩→伤害
	var cen := Vector2.ZERO; var ec := 0   # 方向朝敌方整体(质心), 角度对携带者稳定(用户)
	for _o in battle._targeting._enemies_of(src):
		if _o.get("alive", false): cen += _o["pos"]; ec += 1
	if ec > 0: cen /= float(ec)
	var aimpt: Vector2 = cen if ec > 0 else tgt["pos"]
	var dir: Vector2 = (aimpt - src["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var ang: float = -atan2(dir.y, dir.x)
	# 释放点位: 沿aim在±2000码内自选, 令band中心(650码=500~800中点)落在敌群质心 → band形状大小不动但罩住近敌(用户2026-07-19)
	var offset: float = clampf((aimpt - src["pos"]).length() - 650.0, -2000.0, 2000.0)
	var org: Vector2 = src["pos"] + dir * offset
	var tel := Sprite3D.new()   # 1) 预警扇区(脉动黄)
	tel.texture = VfxTex._make_sector_tex(Color(1.0, 0.78, 0.2, 1.0))
	tel.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tel.axis = Vector3.AXIS_Y
	tel.shaded = false; tel.transparent = true
	tel.pixel_size = 0.15   # 128px=800码
	tel.rotation = Vector3(0.0, ang, 0.0)
	tel.position = battle._world_pos(org + dir * 400.0, 0.08)   # 扇区apex在释放点org
	tel.modulate = Color(1.0, 0.78, 0.2, 0.0)
	battle._world.add_child(tel)
	var tt = battle._reg_tween()
	tt.tween_property(tel, "modulate:a", 0.5, 0.12)
	for _p in range(2):
		tt.tween_property(tel, "modulate:a", 0.28, 0.14)
		tt.tween_property(tel, "modulate:a", 0.6, 0.14)
	await battle._wait_sim(0.56)
	if not src.get("alive", false):
		if is_instance_valid(tel): tel.queue_free()
		return
	if is_instance_valid(tel):
		var tf = battle._reg_tween(); tf.tween_property(tel, "modulate:a", 0.0, 0.12); tf.tween_callback(tel.queue_free)
	battle._shake(battle.JUICE_SHAKE_HEAVY)   # 2) 黄色月光斩(弯月闪电 5帧逐帧, 放大, 用户)
	var moon := Sprite3D.new()
	moon.texture = VfxTex._make_moon_sheet(Color(1.0, 0.88, 0.25))
	moon.hframes = 5; moon.frame = 0
	moon.billboard = BaseMaterial3D.BILLBOARD_DISABLED; moon.axis = Vector3.AXIS_Y
	moon.shaded = false; moon.transparent = true
	moon.pixel_size = 0.15   # 128px=800码, 与预警扇区同尺寸
	moon.rotation = Vector3(0.0, ang, 0.0)
	moon.position = battle._world_pos(org + dir * 400.0, 0.12)   # apex在释放点org, 与预警扇区同位置→斩击必在区内
	battle._world.add_child(moon)
	var mf = battle._reg_tween()   # 逐帧播 5帧
	for _fi in range(5):
		mf.tween_callback(battle._set_sprite_frame.bind(moon, _fi))
		mf.tween_interval(0.11)   # 放慢帧速(用户)
	mf.tween_callback(moon.queue_free)
	var cos30: float = cos(deg_to_rad(30.0))   # 3) 伤害(斩击命中扇区内敌)
	var hits: Array = []
	for o in battle._targeting._enemies_of(src):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - org   # 相对释放点org判定(band中心已对齐敌群→近敌进band)
		var dist: float = rel.length()
		if dist < 500.0 or dist > 800.0: continue
		if dir.dot(rel / maxf(1.0, dist)) < cos30: continue
		hits.append(o)
	var mult: float = ([2.0, 2.5, 3.0][si]) if hits.size() <= 1 else 1.0
	for o in hits:   # 同帧两段同时结算: 物理(红)+真实(白); 飘字各自随机抛物散开(不叠, 无延时)
		battle._damage._apply_damage_from(src, o, int(battle._atk_dmg(src, [0.5, 0.7, 0.9][si], o) * mult), Color("#ff5a5a"), 0.0, false, true)
		battle._damage._apply_damage_from(src, o, int([30, 45, 60][si] * mult), Color("#ffffff"), 0.0, true, true)
# 灼热火珊瑚 023(主动满法力)
# 灼热火珊瑚 023(主动满法力)
func _eq_fire_coral_active(src: Dictionary, si: int) -> void:   # 灼热火珊瑚023主动: 蓄力→挥出60°扇形火焰波(缓移550码,边挥边扩)→接触敌施60灼烧
	if not src.get("alive", false): return
	var es = battle._targeting._enemies_of(src)
	var dir := Vector2.RIGHT
	if not es.is_empty():
		var cen := Vector2.ZERO
		for o in es: cen += o["pos"]
		dir = (cen / float(es.size()) - src["pos"]).normalized()
	battle._anticipate(src); battle._shake(battle.JUICE_SHAKE_HEAVY)   # 蓄力
	await battle._wait_sim(0.4)
	if not is_instance_valid(self) or not src.get("alive", false): return
	var origin: Vector2 = src["pos"]
	var wave := Sprite3D.new()   # 橙火弯月波(躺平朝dir, 边挥边扩)
	wave.texture = VfxTex._make_qi_texture(Color(1.0, 0.5, 0.15))
	wave.billboard = BaseMaterial3D.BILLBOARD_DISABLED; wave.axis = Vector3.AXIS_Y; wave.shaded = false; wave.transparent = true
	wave.pixel_size = 0.06; wave.rotation.y = -atan2(dir.y, dir.x); wave.modulate = Color(1.0, 0.58, 0.22)   # 橙火色
	wave.position = battle._world_pos(origin, 0.4)
	battle._world.add_child(wave)
	var hit: Array = []
	var traveled := 0.0
	var half := deg_to_rad(30.0)   # 60°扇形半角
	while traveled < 550.0 and is_instance_valid(wave) and is_instance_valid(self):
		await battle.get_tree().process_frame
		traveled += 320.0 * battle.get_process_delta_time()   # 缓慢外移
		wave.position = battle._world_pos(origin + dir * traveled, 0.4)
		wave.scale = Vector3(2.2 + traveled / 550.0 * 4.5, 3.2, 1.0)   # 边挥边扩
		for o in battle._targeting._enemies_of(src):
			if battle._arr_has_unit(hit, o): continue
			var rel: Vector2 = o["pos"] - origin
			if rel.dot(dir) <= 0.0: continue
			if absf(rel.angle_to(dir)) > half: continue   # 60°扇形内
			if absf(rel.length() - traveled) > 65.0: continue   # 波前带
			hit.append(o)
			battle._damage._apply_dot_stacks(o, "burn", [40, 60, 90][si], src)   # 用户2026-07-19: 原固定60不吃星级
			battle._skill_ring(o["pos"], Color(1.0, 0.5, 0.2, 0.6), 46.0)
	if is_instance_valid(wave):
		var tw = battle._reg_tween(); tw.tween_property(wave, "modulate:a", 0.0, 0.2); tw.tween_callback(wave.queue_free)

# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
func _eq_on_target(u: Dictionary, src: Dictionary, dmg: int) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_013", "p2eq_014":   # 受击硬化: +def/mr (cap20层); 013满层给护盾
				var cur: int = int(stt.get("harden_stacks", 0))
				var hcap: int = int(stt.get("harden_cap", 20))
				if cur < hcap:
					cur += 1
					var inc: float = float(stt.get("harden_inc", 1.0))
					u["base_def"] += inc; u["base_mr"] += inc
					battle._recalc_stats(u)
					stt["harden_stacks"] = cur
					if cur >= hcap and not bool(stt.get("harden_given", false)):
						if iid == "p2eq_013":   # 013满层: 海胆护盾(特殊紫色) 100/170/250 + 5/12/20%最大生命(用户2026-07-19; 原50/60/80金盾)
							var _usb: float = float(u.get("shield", 0.0))
							battle._damage._grant_shield(u, [100.0, 170.0, 250.0][si] + u["maxHp"] * [0.05, 0.12, 0.20][si])
							var _ugot: float = float(u.get("shield", 0.0)) - _usb   # 实际获盾(经shield_amp/上限后)
							u["urchin_sh_left"] = _ugot
							u["urchin_sh_rate"] = _ugot / 10.0   # 10秒内线性衰减完(用户2026-07-19"慢慢衰减")
							battle._urchin_shield_fx(u)   # 紫刺环+紫字, 与普通金盾区分
						stt["harden_given"] = true
			"p2eq_015":   # 荆棘海胆: 反伤真伤 + 施流血给攻击者
				if src.get("alive", false) and battle._is_hostile(u, src):
					var refl: float = float(dmg) * float(stt.get("reflect_pct", 0.10))
					if refl >= 1.0:
						battle._damage._apply_damage_from(u, src, int(refl), Color("#c9a36b"), 0.0, true, true)   # 反伤=真实伤害跳白字(原_raw_lose静默不跳数字=bug); from_equip防循环
					battle._damage._apply_dot_stacks(src, "bleed", maxi(1, roundi(float(stt.get("reflect_bleed", 2.0)))), u)
			"p2eq_017":   # 不沉之锚: 每次受伤→治疗生命%最低友军 (1/2/15%自身maxHp), 累积满100→+1沉锚充能
				var heal_amt: float = u["maxHp"] * [0.01, 0.02, 0.15][si]
				# 生命百分比最低的友军 (含自己)
				var low = null; var lv := INF
				for o in battle._targeting._allies_of(u):
					var p: float = CombatMath.hp_frac(o["hp"], o["maxHp"])
					if p < lv: lv = p; low = o
				var done: float = 0.0
				if low != null:
					done = battle._damage._heal(low, heal_amt)   # 只按【实际】回进去的血攒锚(满血空奶不攒·用户2026-07-19)
				var acc: float = float(stt.get("anchor_accum", 0.0)) + done
				while acc >= 250.0:          # 累积治疗满250→+1充能 (用户2026-07-19: 100→250)
					acc -= 250.0
					stt["anchor_charges"] = int(stt.get("anchor_charges", 0)) + 1
				stt["anchor_accum"] = acc
		u["eq_state"][iid] = stt

# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
func _eq_on_dodge(u: Dictionary) -> void:
	for e in u.get("equips", []):
		if str(e["id"]) == "p2eq_046":   # 幽灵墨鱼: 闪避→永久护盾
			var stt: Dictionary = u["eq_state"].get("p2eq_046", {})
			battle._damage._grant_shield(u, float(stt.get("ghost_shield", 30.0)))
			battle._shield_dome(u)   # 专属护盾罩(不复用faint battle._shield_bubble)

# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
func _eq_bloodletting(u: Dictionary, si: int) -> void:   # 饮血护符坠(011): 一段一段连斩(每刀~0.11s顺序打出,各命中随机敌,衰减0.85^k); 吸血溢出转盾结尾汇总
	var n: int = [5, 6, 8][si]
	var sh0: float = u["shield"]
	for k in range(n):
		if not u.get("alive", false): break
		var es = battle._targeting._pick_enemies_of(u)
		if es.is_empty(): break
		var o = es[battle._battle_rng.randi() % es.size()]
		var decay: float = pow(0.85, k)
		battle._blood_slash(u["pos"], o["pos"], 0.0)   # 这一刀立即砍
		battle._damage._apply_damage_from(u, o, int((battle._resolve_dmg(u, u["atk"] * [0.5, 0.7, 1.0][si] + [40.0, 50.0, 70.0][si], o, false)) * decay), Color("#ff8aa0"), 0.33, false, true)
		await battle._wait_sim(0.3)   # 一段一段: 每0.3s一刀
	if not is_instance_valid(self): return
	var shg: int = int(u["shield"] - sh0)   # 连斩吸血溢出转的盾, 结尾汇总一次
	if shg > 0: battle._vfx._float_text(u["pos"] + Vector2(28, -46), "护盾+" + str(shg), Color("#8ad7ff"), false, "shield")

func _eq_on_cast(u: Dictionary, tgt: Dictionary) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		if battle._stress: battle._dbg_op = "eqcast:" + iid   # 卡死猎手: 定位是哪件装备on-cast卡住(用户2026-07-19)
		match iid:
			"p2eq_027":   # 电棍: 电击已移到 _eq_on_basic_attack(普攻命中消耗1层, 用户2026-07-03); on_cast不处理
				pass
			"p2eq_017":   # 不沉之锚: 锚击移到_eq_on_basic_attack(普攻消耗1充能, 用户2026-07-02); on_cast不处理
				pass
			"p2eq_006":   # 千刃风暴: 移到每7秒 _tick_sword_storm(用户); on_cast不处理
				pass
			"p2eq_007":   # 锈蚀阔剑: 移到每6秒 _tick_broadsword(用户); on_cast不处理
				pass
			"p2eq_008":   # 双穿珊瑚刺: 移到每6秒 _tick_coral(用户); on_cast不处理
				pass
			"p2eq_011":   # 饮血护符坠: 一段一段顺序连斩(async, 每刀~0.11s), 见 _eq_bloodletting
				_eq_bloodletting(u, si)
			"p2eq_014":   # 深海堡垒甲: 汲取移到 _tick_fortress(硬化满20层后每8秒汲取, 用户2026-07-02); on_cast不处理
				pass
			"p2eq_022":   # 余烬燃油瓶: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_fuel_throw, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_028":   # 冰霜冻露瓶: 改为每6秒定时(battle._EQ_CUSTOM_IV→_eq_ice_throw, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_030":   # 迷你水晶球A: 改为每7秒定时(battle._EQ_CUSTOM_IV→_eq_crystal_line, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_031":   # 迷你水晶球B: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_crystal_sweep, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_039":   # 竹制弓箭: 改为每第3段普攻消耗1次充能(_eq_on_basic_attack, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_048":   # 黄铜手铳: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_pistol_volley, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_049":   # 连发弩: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_crossbow_volley, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_050":   # 幽灵加特林: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_gatling_burst, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_051":   # 激光手枪: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_laser_pistol, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_053":   # 霰弹贝古: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_shotgun_blast, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_057":   # 狙击长管: 改为每8秒定时(battle._EQ_CUSTOM_IV→_eq_sniper, 用户2026-07-19); on_cast不处理
				pass
			"p2eq_010":   # 激光长刃: 移到独立计时器 _tick_laser(第二普攻扇形斩); on_cast不处理
				pass

# 水晶叠层 (A/B共用); splash=true(B 3★): 引爆范围扩大50%波及邻格敌
# 水晶叠层 (A/B共用); splash=true(B 3★): 引爆范围扩大50%波及邻格敌
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int) -> void:
	var lv = battle._add_stack(o, "p2crystal", 1, 3)
	if lv >= 3:
		battle._consume_stacks(o, "p2crystal")
		battle._crystal_stack_set(o, 0)
		battle._crystal_detonate(o["pos"])
		battle._damage._apply_damage_from(src, o, battle._resolve_dmg(src, float(o["maxHp"]) * [0.14, 0.17, 0.20][si], o, true), Color("#bfa8ff"), 0.0, false, true)
	else:
		battle._crystal_stack_set(o, lv)   # 更新可视层数

# 狙击长管 057: 递归开枪
# 狙击长管 057: 递归开枪
func _eq_sniper_windup(u: Dictionary, si: int) -> void:   # 狙击长管057: 每8秒先蓄力1秒(瞄准线+枪口聚能+锁定环)再开枪(用户2026-07-19)
	if not u.get("alive", false): return
	var low = null; var lv := INF
	for o in battle._targeting._pick_enemies_of(u):
		var p: float = CombatMath.hp_frac(o["hp"], o["maxHp"])
		if p < lv: lv = p; low = o
	if low == null: return
	battle._sniper_charge_fx(u, low)
	battle._pending_shots.append({"delay": 1.0, "fn": func(): _eq_sniper(u, si, 0), "src": u})   # 递归追加的后续枪仍是"立即", 不再各蓄1秒

func _eq_sniper(u: Dictionary, si: int, depth: int) -> void:
	if depth >= 12:
		return
	var low = null; var lv := INF
	for o in battle._targeting._pick_enemies_of(u):
		var p: float = o["hp"] / o["maxHp"]
		if p < lv: lv = p; low = o
	if low == null:
		return
	var dir: Vector2 = (low["pos"] - u["pos"]).normalized()
	battle._muzzle_flash(u["pos"], dir, Color("#ff5a5a"))
	battle._shake(battle.JUICE_SHAKE_HEAVY)                                                  # 开枪后坐(用户2026-07-19)
	battle._skill_ring(u["pos"] + dir * 28.0, Color(1.0, 0.42, 0.36, 0.8), 46.0)      # 枪口爆环
	var _snd: float = 1.5 if OS.has_environment("XDBG") else 0.28
	var _tip: Vector2 = low["pos"] + dir * 150.0
	battle._laser_beam(u["pos"], _tip, Color(1.0, 0.24, 0.28, 0.82), 0.17, _snd, 1.0)          # 粗红外辉(醒目狙击曳光)
	battle._laser_beam(u["pos"], _tip, Color(1.0, 0.92, 0.86, 0.96), 0.06, _snd * 0.85, 1.02)   # 白热细核(高速弹道感)
	battle._vfx._hit_spark(low)
	var killed := false
	for o in battle._targeting._enemies_of(u):
		if battle._on_line(u["pos"], dir, o["pos"], 36.0):
			var before: bool = o["alive"]
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, [2.0, 3.0, 7.0][si], o), Color("#ff4444"), 0.0, false, true)
			if before and not o["alive"]:
				killed = true
	if killed:
		_eq_sniper(u, si, depth + 1)

# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
func _eq_on_kill(killer: Dictionary, _victim: Dictionary) -> void:
	for e in killer.get("equips", []):
		if str(e["id"]) == "p2eq_004":   # 暴君之牙: 处决后回20龟能 (无龟能单位改回40血)
			if battle._has_energy_system(killer):
				_eq_grant_energy(killer, 20.0)
			else:
				battle._damage._heal(killer, 40.0)

# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 (+ 左轮052 敌亡补弹)
# ============================================================================
# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 (+ 左轮052 敌亡补弹)
# ============================================================================
func _eq_on_death(u: Dictionary, _killer) -> void:
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_033":   # 复活海螺: 彻底阵亡→原位变形成小虫(通用打法/攻速0.65) + 亡灵变形演出
				battle._conch_transform(u["pos"])
				var worm = battle._spawn_summon(u, "worm", [400.0, 900.0, 5000.0][si], [30.0, 55.0, 200.0][si], {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})   # 小虫只有星级无等级(去_lvl_mult), 数值即实际
				if worm != null:
					worm["pos"] = u["pos"]
					worm["atk_interval"] = 1.0 / 0.65
					if is_instance_valid(worm["sprite"]):
						worm["sprite"].position = battle._world_pos(u["pos"], battle.GROUND_LIFT)
						var wsc: Vector3 = worm["sprite"].scale
						worm["sprite"].scale = Vector3.ZERO
						var wtw = battle._reg_tween()
						wtw.tween_interval(0.12)
						wtw.tween_property(worm["sprite"], "scale", wsc, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					worm["eq_state"] = {}; worm["equips"] = []
					if si == 2:   # 3★: 标记每周期分裂
						worm["worm_split"] = true
			"p2eq_035":   # 黄铜齿轮: 死亡不销毁不结算(产币走 _tick_gear 每6秒实时到账, 与死亡无关)
				pass
	# 左轮052: 任何敌人阵亡 → 对方(u的敌方)持左轮的存活单位 +1发子弹 (上限6)
	for o in battle._units:
		if o["alive"] and battle._eff_side(o) != battle._eff_side(u):
			for e2 in o.get("equips", []):
				if str(e2["id"]) == "p2eq_052":
					var rst: Dictionary = o["eq_state"].get("p2eq_052", {})
					rst["revolver_bullets"] = mini(6, int(rst.get("revolver_bullets", 0)) + 1)
					o["eq_state"]["p2eq_052"] = rst

# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
func _eq_check_hp_threshold(u: Dictionary) -> void:
	if u.get("hp50_fired", false) or u["hp"] > u["maxHp"] * 0.5 or not u["alive"]:
		return
	var fired := false
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_044":   # 深海项链: 首次<50%救命回血(龟上半身绿光脉动, 用户: 简单绿光即可, 不复用037魔法阵)
				battle._damage._heal(u, u["maxHp"] * [0.12, 0.27, 0.40][si]); fired = true
				battle._heal_body_glow(u)
			"p2eq_045":   # 珍珠耳环: 首次<50%救命回血(龟身绿光)+抛物线火球
				battle._damage._heal(u, u["maxHp"] * [0.15, 0.29, 0.65][si])
				battle._heal_ascend(u)   # 绿光环上浮(045专属, 不复用044)
				var balls: int = [1, 1, 2][si]
				var es = battle._targeting._pick_enemies_of(u)
				for b in range(balls):
					if es.is_empty(): break
					var o = es[battle._battle_rng.randi() % es.size()]
					battle._spawn_fireball(u, o, int(o["maxHp"] * [0.08, 0.17, 0.30][si]), [30, 70, 150][si])
					battle._skill_ring(o["pos"], Color(1.0, 0.45, 0.12, 0.6), 50.0)   # 火球爆裂环
				fired = true
	if fired:
		u["hp50_fired"] = true

# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
func _eq_tick(u: Dictionary, delta: float) -> void:
	u["eq_timer"] = u.get("eq_timer", 0.0) + delta
	if u["eq_timer"] < battle.EQ_TICK:
		return
	u["eq_timer"] = 0.0
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_001":   # 锈蚀短剑: 移到每帧 _tick_rustblade (每3s就绪 + 100码射程内有敌即劈); 周期tick不处理
				pass
			"p2eq_012":   # 龟苓膏块: 移到 _tick_jelly (每4s, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_016":   # 铁壁盾: 全队盾移到 _tick_ironwall(每5秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_018":   # 守护贝壳: 自回血移到 _tick_shell(每8秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_019":   # 海葵药膏: 移到 _tick_anemone(每7秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_020":   # 哑铃: 移到 _tick_dumbbell(每10秒编排:锻炼锁攻锁充能→掷哑铃击退, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_021":   # 守护贝母: 移到 _tick_barnacle(每5秒连接→自己+最高攻友军 +10龟能+10%攻速本场, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_024":   # 龙蛋: 每周期+1吐息, 满3→喷火龙直线扫射
				stt["dragon_stacks"] = int(stt.get("dragon_stacks", 0)) + 1
				if int(stt["dragon_stacks"]) >= 3:
					stt["dragon_stacks"] = 0
					_eq_dragon_breath(u, si)
			"p2eq_025":   # 雷鸣贝壳: 移到每帧 _tick_thunder(每4秒/道间错峰/大雷/伤害在雷中段跳, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_027":   # 电棍: 移到on_cast(施法后电击, 用户描述); 周期tick不处理
				pass
			"p2eq_035":   # 黄铜齿轮: 齿轮层改每6s(_tick_gear), 周期tick不处理
				pass
			"p2eq_034":   # 玩偶小熊: 移到每帧 _tick_doll(4s派小熊 + 满层蓄力召大熊); 周期tick不处理
				pass
			"p2eq_036":   # 温泉蛋: 孵化进度, 满100→全队均摊护盾(一次)
				battle._egg_add_progress(u, 5.0)   # 每周期+5 (其余源: 敌死+10/己死+15/造成×0.1/承受×0.1)
			"p2eq_042":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_043":   # 海浪护符: 每周期+1巨浪层, 满→横排扫敌我
				stt["wave"] = int(stt.get("wave", 0)) + 1
				if int(stt["wave"]) >= [3, 2, 2][si]:
					stt["wave"] = 0
					_eq_water_wave(u, si)
			"p2eq_052":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_037":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_038":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_040":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_056":   # 飞镖: 每周期向所有带"靶子"(被击飞)的敌各射1镖+流血
				if OS.has_environment("EQDEMO_EQUIP") and str(OS.get_environment("EQDEMO_EQUIP")) == "p2eq_056":   # demo: 无击飞源→强制标靶看飞镖volley
					for _e in battle._targeting._enemies_of(u):
						if _e.get("alive", false):
							battle._mark_vfx(_e, 5.0, Color("#ffa040")); _e["eq_target_until"] = battle._t + 5.0
				for o in battle._targeting._enemies_of(u):
					if battle._t < o.get("eq_target_until", 0.0):
						o["eq_target_until"] = 0.0
						o["_mark_until"] = battle._t   # 靶子锁定框消失
						battle._spawn_eq_bolt(u, o, battle._resolve_dmg(u, u["atk"] * [1.5, 3.0, 9.0][si] + [130.0, 190.0, 600.0][si], o, false), "res://assets/sprites/vfx/dart.png", Color("#ffe0b0"), true, maxi(1, roundi(u["atk"] * 0.1)))
		u["eq_state"][iid] = stt

# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
# 024 喷火龙(定稿场景): 龙低空沿"敌方质心方向的线"掠射, 边飞边点燃 burn-loop 真像素火燃烧带, 命中敌=fx_explosion金爆+着火+魔伤, 掠过友=绿治疗环
# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
# 024 喷火龙(定稿场景): 龙低空沿"敌方质心方向的线"掠射, 边飞边点燃 burn-loop 真像素火燃烧带, 命中敌=fx_explosion金爆+着火+魔伤, 掠过友=绿治疗环
func _eq_dragon_breath(u: Dictionary, si: int) -> void:
	var es = battle._targeting._pick_enemies_of(u)
	if es.is_empty():
		return
	var cen := Vector2.ZERO
	for o in es:
		cen += o["pos"]
	cen /= float(es.size())
	var anchor = es[0]                               # 瞄最靠质心的敌人=保证龙穿过它(不是瞄质心从两敌之间缝里穿)
	var abest := INF
	for o in es:
		var dd: float = o["pos"].distance_squared_to(cen)
		if dd < abest:
			abest = dd; anchor = o
	var dir: Vector2 = (anchor["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var start: Vector2 = u["pos"]
	var reach: float = 340.0                         # 飞到最远敌人身后(真穿过去), 不再固定760码够不着
	for o in es:
		reach = maxf(reach, (o["pos"] - start).dot(dir) + 260.0)
	var end: Vector2 = start + dir * reach
	var total: float = maxf(1.0, start.distance_to(end))
	var dur: float = clampf(reach / 480.0, 1.6, 2.6)  # 按距离定时长=恒定速度
	battle._anticipate(u)
	battle._dragon_sys._dragon_windup(start)                            # 前摇: 召唤点聚火蓄能(~0.55s)再爆发出龙(修"一下冒出来")
	var twd = battle._reg_tween()
	twd.tween_interval(0.55)
	twd.tween_callback(battle._dragon_sys._dragon_unleash.bind(u, si, start, end, dir, total, dur))
