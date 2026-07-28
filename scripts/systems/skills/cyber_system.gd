class_name CyberSystem
extends RefCounted
## 赛博龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _sk_cyber_cannon(u: Dictionary, tgt) -> void:              # 赛博龟·能量大炮(用户#15: 对一条直线蓄力后发长激光能量射线·线上敌各1A物理+0.1A×浮游炮数真伤·炮越多越猛)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var drones: int = int(u.get("drone_n", 0))   # 浮游炮改纯视觉后从计数取(2026-07-15)
	var uu = u
	# ★照Lux R终极闪光重做(用户2026-07-15: 节奏效果全参考·配色换科技青蓝): 蓄力0.9s(能量向心+细瞄准线)→贯屏三层巨柱瞬现→残光衰减+衍射颗粒
	for i in range(8):                                          # 蓄力: 青色能量向心汇聚
		var sa: float = TAU * float(i) / 8.0 + battle._juice_rng.randf_range(-0.3, 0.3)
		var soff: Vector2 = Vector2(cos(sa), sin(sa)) * battle._juice_rng.randf_range(60.0, 100.0)
		var sp = Sprite3D.new()
		sp.texture = VfxTex._make_fire_glow_tex()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.007
		sp.modulate = Color(0.55, 0.95, 1.0, 0.0)
		sp.position = battle._world_pos(u["pos"] + soff, battle._juice_rng.randf_range(0.5, 1.3))
		battle._world.add_child(sp)
		var st = battle._reg_tween()
		st.tween_interval(float(i) * 0.07)
		st.tween_property(sp, "modulate:a", 0.9, 0.1)
		st.tween_property(sp, "position", battle._world_pos(u["pos"], 0.9), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		st.parallel().tween_property(sp, "modulate:a", 0.0, 0.35)
		st.tween_callback(sp.queue_free)
	for k in range(3):                                          # 蓄力期: 细青瞄准线(参考Lux R的细线预警·3段脉冲)
		battle._pending_shots.append({"delay": 0.05 + 0.28 * float(k), "fn": func() -> void:
			if uu.get("alive", false):
				battle._bolt_line(uu["pos"], uu["pos"] + dir * 1300.0, Color(0.5, 0.9, 1.0, 0.35))
		, "src": u})
	var fire = func() -> void:                                 # 发射: 贯屏巨柱(三层: 白热核心+主青束+外晕)瞬现
		if not uu.get("alive", false): return
		for o in battle._targeting._enemies_of(uu):
			if not o.get("alive", false): continue
			if not battle._on_line(uu["pos"], dir, o["pos"], 70.0): continue    # 直线判定带宽±70码
			if o["pos"].distance_to(uu["pos"]) > 900.0: continue
			battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, 1.0, o), Color("#9bf0ff"))                          # 1A物理
			if drones > 0:
				battle._damage._apply_damage_from(uu, o, int(uu["atk"] * 0.1 * drones), Color("#d0ffff"), 0.0, true)  # 0.1A×浮游炮数真伤
			battle._vfx._hit_spark(o)
		var endp: Vector2 = uu["pos"] + dir * 1300.0
		battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", uu["pos"], endp, 90.0, Color(1.0, 1.0, 1.0, 1.0), 0.35)     # ①白热核心束
		battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", uu["pos"], endp, 200.0, Color(0.55, 0.93, 1.0, 0.85), 0.55) # ②主青束
		battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", uu["pos"], endp, 340.0, Color(0.4, 0.8, 1.0, 0.4), 0.8)     # ③外晕束(残光最久)
		battle._gambler_sys._gambler_pop(uu["pos"] + dir * 30.0, 0.9, Color(0.85, 1.0, 1.0, 0.95))                          # 发射爆闪
		battle._shake(battle.JUICE_SHAKE_BIG); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
		for j in range(12):                                     # 衍射颗粒沿线散落(参考Lux R残光棱彩颗粒)
			var pp: Vector2 = uu["pos"] + dir * battle._juice_rng.randf_range(80.0, 1000.0) + Vector2(-dir.y, dir.x) * battle._juice_rng.randf_range(-70.0, 70.0)
			var gk = Sprite3D.new()
			gk.texture = VfxTex._make_fire_glow_tex()
			gk.billboard = BaseMaterial3D.BILLBOARD_ENABLED; gk.shaded = false; gk.transparent = true
			gk.pixel_size = 0.004
			gk.modulate = Color(battle._juice_rng.randf_range(0.6, 1.0), 1.0, 1.0, 0.9)
			gk.position = battle._world_pos(pp, battle._juice_rng.randf_range(0.3, 1.2))
			battle._world.add_child(gk)
			var gt = battle._reg_tween(); gt.set_parallel(true)
			gt.tween_property(gk, "position", battle._world_pos(pp, 1.6 + battle._juice_rng.randf_range(0.0, 0.5)), 0.6)
			gt.tween_property(gk, "modulate:a", 0.0, 0.6)
			gt.chain().tween_callback(gk.queue_free)
	battle._muzzle_flash(u["pos"], dir, Color("#9bf0ff"))             # 起手枪口闪
	battle._pending_shots.append({"delay": 0.9, "fn": fire, "src": u})   # 蓄力0.9s→发射(Lux R节奏)

func _sk_cyber_hijack(u: Dictionary) -> void:                   # 赛博龟·侵入(135龟能·用户2026-07-16: 4秒→5秒/120→135·Botworld黑客): 黑1随机敌5秒倒戈(side改赛博方·标hijacked→打原队友+被原队友打·不算存活数·击杀归赛博·蛋免控·可黑多个)
	var es: Array = []
	for o in battle._targeting._pick_enemies_of(u):
		if o.get("alive", false) and not o.get("_eggImmune", false) and not o.get("hijacked", false):
			es.append(o)
	if es.is_empty(): return
	var v: Dictionary = es[battle._battle_rng.randi() % es.size()]
	# ★2026-07-22 重做: 【不再改写 side】。旧实现 v["side"] = u["side"] 把它变成赛博方的"真友军"
	#   → 赛博全队索敌/技能都跳过它(用户主诉"我方要能打"), 还会给它加治疗; 且衍生出
	#   死亡不归队 / 跨路串阵营 / 单路瞬间判胜 / 召唤物串队 四类问题。
	#   现在只挂标记, 敌我关系由 battle._is_hostile 统一裁决(见 §HOSTILE)。
	v["_hijack_orig_side"] = str(v["side"])   # 保留: _eff_side / 统计分组 / 归队清标记都读它
	v["hijacked"] = true
	v["hijack_until"] = battle._t + 5.0                                # 5秒(用户2026-07-16: 4→5)
	v["_hijack_by"] = u                                         # 人头归属: 被侵入者杀的算赛博的(用户2026-07-22, 赛博自己死了也算)
	v["taunt_until"] = 0.0; v["taunt_by"] = null               # 清嘲讽残留(防倒戈期错误锁定)
	v["stun_until"] = 0.0                                       # 解控(立即可倒戈行动)
	battle._hijack_fx_attach(v)                                        # 全身红光 + 电流环绕(用户2026-07-22)
	battle._vfx._float_text(v["pos"] + Vector2(0, -56), "侵入!", Color("#3fffd0"))
	battle._skill_ring(v["pos"], Color(0.25, 1.0, 0.82, 0.5), 52.0)
	battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], v["pos"], 30.0, Color(0.25, 1.0, 0.82, 0.75), 0.6)   # 侵入数据链(用户07-07仅给"参考Botworld黑客机器人"·具体视觉无原话)

func _sk_cyber_smart(u: Dictionary) -> void:                   # 赛博龟·智能AI(封板·40龟能·充能型): +1充能→冲刺重定位(kite拉到理想射程·躲贴身); 常驻走位+登场+20%移速 [完整行动脑(躲大招/对齐激光)留F5]
	u["cyber_ai_charge"] = int(u.get("cyber_ai_charge", 0)) + 1
	_cyber_smart_dash(u)
	battle._skill_ring(u["pos"], Color(0.3, 0.9, 1.0, 0.5), 46.0)

func _cyber_smart_dash(u: Dictionary) -> void:   # 智能走位冲刺核心(主动放技+被动躲避共用·用户2026-07-16): 绕自身200码采样16候选打分(离敌远+离墙远)·800码/s真位移
	var ne = battle._targeting._nearest_enemy(u)
	if ne == null: return
	var best: Vector2 = u["pos"]
	var best_score = -INF
	var es = battle._targeting._enemies_of(u)
	for i in range(16):
		var aa: float = TAU * float(i) / 16.0
		var cand: Vector2 = u["pos"] + Vector2(cos(aa), sin(aa)) * 200.0
		cand.x = clampf(cand.x, battle.ARENA.position.x + 50.0, battle.ARENA.end.x - 50.0)
		cand.y = clampf(cand.y, battle.ARENA.position.y + 40.0, battle.ARENA.end.y - 40.0)
		var d_enemy = INF
		for o in es:
			if o.get("alive", false): d_enemy = minf(d_enemy, cand.distance_to(o["pos"]))
		var d_wall: float = minf(minf(cand.x - battle.ARENA.position.x, battle.ARENA.end.x - cand.x), minf(cand.y - battle.ARENA.position.y, battle.ARENA.end.y - cand.y))
		var score: float = minf(d_enemy, 420.0) + minf(d_wall, 160.0) * 0.8
		if score > best_score:
			best_score = score
			best = cand
	battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], best, 44.0, Color(0.3, 0.9, 1.0, 0.6), 0.28)
	var from4: Vector2 = u["pos"]
	var uu4 = u
	var dur4: float = maxf(0.05, from4.distance_to(best) / 800.0)
	u["_slam"] = true
	var dt4 = battle._reg_tween()
	dt4.tween_method(func(q: float) -> void:
		if uu4.get("alive", false): uu4["pos"] = from4.lerp(best, q)
	, 0.0, 1.0, dur4)
	dt4.tween_callback(func() -> void: uu4["_slam"] = false)

# 泡泡·束缚: 定身目标 1.5s + 束缚期间每受一段伤害 永久-X护甲/魔抗 (见 battle._damage._apply_damage_from 钩子)
func _cyber_assemble_mech(u: Dictionary) -> void:   # 阵亡演出(用户2026-07-16理想效果): 本体消散→浮游炮游动集结→各自对最近敌蓄力→贯穿激光0.4A魔法→飞向集结点→机甲5秒组装(血/攻/甲/抗从低涨到设定值·期间不能动)→就位近战
	var n: int = int(u.get("drone_n", 0))
	if n <= 0:
		return
	battle._mech_incoming[str(u.get("side", "left"))] = battle._t + 3.0   # 死→机甲spawn(2.8s)空档桥接: 此侧仍算存活防提前团灭/破蛋(用户2026-07-18)
	var arr: Array = u.get("_drones", [])
	u["_drones"] = []
	u["drone_n"] = 0
	var cpos: Vector2 = u["pos"]
	var retreat: float = -1.0 if str(u.get("side", "left")) == "left" else 1.0   # 集结点=尸位向己方后场偏120码
	var gather: Vector2 = cpos + Vector2(retreat * 120.0, 0.0)
	gather.x = clampf(gather.x, battle.ARENA.position.x + 60.0, battle.ARENA.end.x - 60.0)
	gather.y = clampf(gather.y, battle.ARENA.position.y + 40.0, battle.ARENA.end.y - 40.0)
	var uu: Dictionary = u
	var live: Array = []
	for d in arr:
		if is_instance_valid(d.get("spr")): live.append(d["spr"])
	# ① 浮游炮自由飞散(用户2026-07-16: 散点=竞技场内任何地方·别密集)·错峰起飞·时长不一
	var scat: Array = []
	for i in range(live.size()):
		var spr = live[i]
		var fpos = Vector2(randf_range(battle.ARENA.position.x + 40.0, battle.ARENA.end.x - 40.0), randf_range(battle.ARENA.position.y + 30.0, battle.ARENA.end.y - 30.0))
		scat.append(fpos)
		var ft = battle._reg_tween()
		ft.tween_interval(randf() * 0.35)
		ft.tween_property(spr, "position", battle._world_pos(fpos, randf_range(1.1, 1.8)), randf_range(0.6, 1.2)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# ② 蓄力(0.6s炮身发亮)→各自对最近敌射贯穿激光(0.4×赛博ATK魔法·线上全体)
	var atk_ref: float = float(u["atk"])
	battle._pending_shots.append({"delay": 0.75, "fn": func() -> void:
		for spr2 in live:
			if is_instance_valid(spr2):
				var ch = battle._reg_tween()
				ch.tween_property(spr2, "modulate", Color(1.6, 1.9, 2.2), 0.55)
	, "src": u})
	battle._pending_shots.append({"delay": 1.35, "fn": func() -> void:   # ★Gaster Blaster式(认证参考: 官方光束2帧@30fps瞬展全宽·蓄力口部聚能·发射后坐): 每炮蓄力光球0.45s→厚白束瞬展+后坐
		for i2 in range(live.size()):
			var spr3 = live[i2]
			if not is_instance_valid(spr3): continue
			var dpos: Vector2 = scat[i2] if i2 < scat.size() else gather   # 激光从各自散点发射
			var best = null
			var bd = INF
			for o in battle._units:
				if battle._is_hostile(uu, o) and o.get("alive", false) and not o.get("_egg_fence", false):
					var dd: float = dpos.distance_to(o["pos"])
					if dd < bd: bd = dd; best = o
			if best == null: continue
			var ldir: Vector2 = (best["pos"] - dpos)
			if ldir.length() < 1.0: ldir = Vector2.RIGHT
			ldir = ldir.normalized()
			var orb = Sprite3D.new()                                # 口部聚能光球(蓄力0.45s膨胀)
			orb.texture = VfxTex._make_fire_glow_tex()
			orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; orb.shaded = false; orb.transparent = true
			orb.pixel_size = 0.005
			orb.modulate = Color(0.85, 1.0, 1.0, 0.9)
			orb.position = battle._world_pos(dpos + ldir * 16.0, 1.4)
			battle._world.add_child(orb)
			var ot = battle._reg_tween()
			ot.tween_property(orb, "scale", Vector3(3.2, 3.2, 3.2), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			ot.tween_callback(func() -> void:
				if is_instance_valid(orb): orb.queue_free()
				if is_instance_valid(spr3):                          # 后坐: 炮体向后弹再回位(Gaster Blaster标志)
					var rb = battle._reg_tween()
					rb.tween_property(spr3, "position", spr3.position + battle._world_pos(dpos - ldir * 34.0, 1.4) - battle._world_pos(dpos, 1.4), 0.08)
					rb.tween_property(spr3, "position", spr3.position, 0.25)
				var endp2: Vector2 = dpos + ldir * 1300.0
				battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", dpos, endp2, 150.0, Color(1.0, 1.0, 1.0, 1.0), 0.7)   # 厚白核心束(用户2026-07-16: 更宽更明显更持久)
				battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", dpos, endp2, 250.0, Color(0.6, 0.95, 1.0, 0.75), 1.0) # 青晕外束(略久=收细消散感)
				battle._shake(0.03)
				for o2 in battle._units:
					if battle._is_hostile(uu, o2) and o2.get("alive", false) and battle._on_line(dpos, ldir, o2["pos"], 40.0):
						battle._damage._apply_damage_from(uu, o2, battle._resolve_dmg(uu, atk_ref * 0.4, o2, true), Color("#7ee8ff"))      # 0.4A魔法(蓝字)
						battle._vfx._hit_spark(o2))
	, "src": u})
	# ③ 飞向集结点消失(2.4s起·等激光演出完)
	battle._pending_shots.append({"delay": 2.4, "fn": func() -> void:
		for spr4 in live:
			if not is_instance_valid(spr4): continue
			var ct = battle._reg_tween(); ct.set_parallel(true)
			ct.tween_property(spr4, "position", battle._world_pos(gather, 0.8), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			ct.tween_property(spr4, "modulate:a", 0.15, 0.3)
			ct.chain().tween_callback(spr4.queue_free)
	, "src": u})
	# ④ 机甲组装(2.8s起·5秒血/攻/甲/抗从10%涨到设定值·期间_slam锁不能动不能打)
	var _lv: int = int(u.get("level", 1))
	var final_hp: float = (40.0 + 1.0 * float(_lv)) * float(n)   # 用户2026-07-18定: 生命=(40+1×每级)×炮数
	var final_atk: float = (4.0 + 0.1 * float(_lv)) * float(n)   # 用户2026-07-18定: 攻击=(4+0.1×每级)×炮数
	var final_def: float = 60.0 + 2.0 * float(_lv)               # 护甲魔抗=60+2×等级(用户2026-07-16定)
	battle._pending_shots.append({"delay": 2.8, "fn": func() -> void:
		battle._gambler_sys._gambler_pop(gather, 0.8, Color(0.7, 0.98, 1.0, 0.95))
		battle._skill_ring(gather, Color(0.5, 0.9, 1.0, 0.7), 80.0)
		battle._shake(battle.JUICE_SHAKE_HEAVY)
		var mech = battle._spawn._spawn_summon(uu, "mech", final_hp, final_atk, {
			"label": "机甲", "spr_id": "mech", "col_size": 40.0, "hp_w": 46.0, "melee": true,
			"move_spd": 95.0, "atk_interval": 1.0, "atk_range": 100.0,   # 机甲=近战坦克档(用户2026-07-28移速定位化: 原130比全表任何龟都快); 近战最低标准100防卡位(用户2026-07-16"70会卡位")
			"special": "mech_blast", "special_cd": 2.5, "special_scale": 1.5,
		})
		if mech == null: return
		mech["pos"] = gather
		mech["_slam"] = true                                     # 组装期锁AI(不能移动/攻击)
		mech["_assembling"] = true                               # 组装期免疫攻击(伤害闸·用户2026-07-16"期间也不能被攻击")
		mech["untargetable_until"] = battle._t + 5.05                   # 不可被索敌
		mech["maxHp"] = final_hp; mech["hp"] = maxf(1.0, final_hp * 0.01)   # ★maxHp固定=满, hp从~0涨→血条0%填到100%(用户2026-07-18: 是血条填充·不是扩maxHp)
		mech["atk"] = 0.0; mech["base_atk"] = 0.0
		mech["def"] = 0.0; mech["base_def"] = 0.0; mech["mr"] = 0.0; mech["base_mr"] = 0.0
		var mref: Dictionary = mech
		var spr5 = mech.get("sprite", null)
		if is_instance_valid(spr5):
			spr5.modulate = Color(1, 1, 1, 0.45)                 # 组装中半透明→逐渐成型
			var mt = battle._reg_tween()
			mt.tween_property(spr5, "modulate:a", 1.0, 5.0)
		var grow = battle._reg_tween()                                 # 5秒属性增长(血条0%→100%填充·攻/甲/抗0→满·组装期免伤无扣血)
		grow.tween_method(func(g: float) -> void:
			if not mref.get("alive", false): return
			mref["maxHp"] = final_hp
			var _seg: float = floorf(g * 10.0) / 10.0             # ★一段段回复(10段·每0.5s一段)从0填到满(用户2026-07-18: 700血就5秒内分段回到700)
			mref["hp"] = maxf(1.0, final_hp * _seg)
			mref["atk"] = lerpf(0.0, final_atk, g)
			mref["base_atk"] = mref["atk"]
			mref["def"] = lerpf(0.0, final_def, g); mref["base_def"] = mref["def"]
			mref["mr"] = lerpf(0.0, final_def, g); mref["base_mr"] = mref["mr"]
		, 0.0, 1.0, 5.0)
		grow.tween_callback(func() -> void:                      # 就位: 解锁+解除免疫+白闪+环
			if not mref.get("alive", false): return
			mref["_slam"] = false
			mref["_assembling"] = false
			battle._vfx._flash(mref, Color(1.6, 1.9, 2.2))
			battle._skill_ring(mref["pos"], Color(0.6, 0.95, 1.0, 0.8), 64.0)
			battle._shake(battle.JUICE_SHAKE_LIGHT))
		var weld = [0]                                          # 组装特效: 5秒内周期焊接火花+电弧
		var wt = battle._reg_tween()
		wt.tween_method(func(_g: float) -> void:
			weld[0] += 1
			if weld[0] % 6 != 0 or not mref.get("alive", false): return
			var wp: Vector2 = (mref["pos"] as Vector2) + Vector2(randf_range(-28.0, 28.0), randf_range(-16.0, 16.0))
			var wk = Sprite3D.new()
			wk.texture = VfxTex._make_fire_glow_tex()
			wk.billboard = BaseMaterial3D.BILLBOARD_ENABLED; wk.shaded = false; wk.transparent = true
			wk.pixel_size = 0.006
			wk.modulate = Color(0.8, 1.0, 1.0, 1.0)
			wk.position = battle._world_pos(wp, randf_range(0.3, 1.2))
			battle._world.add_child(wk)
			var wtw = battle._reg_tween()
			wtw.tween_property(wk, "modulate:a", 0.0, 0.18)
			wtw.tween_callback(wk.queue_free)
		, 0.0, 1.0, 5.0)
	, "src": u})
## 该单位的立绘原图是否朝右(需要翻转修正)。
##
## ★为什么不能只查 id: 召唤物的 id 是 `"_summon_" + kind`(如 "_summon_mech"), 永远匹配不上
## ART_FACES_RIGHT 里按龟 id 写的条目 → 2026-07-19 用户报「机甲建模也反了」就是这么来的:
## mech.png 原图朝右, 但例外表对召唤物根本不生效。所以这里对召唤物再按 summon_kind 查一次。