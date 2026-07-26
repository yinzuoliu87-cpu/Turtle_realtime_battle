class_name PirateSystem
extends RefCounted
## 海盗龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _sk_pirate_rum(u: Dictionary) -> void:                     # 海盗龟·朗姆酒(120龟能): 海盗船扔酒瓶→每秒回4%maxHP×6秒(HoT绿回血) + 护甲魔抗各+0.15A×6秒(暖色酒气护光)
	u["rum_until"] = battle._t + 6.0; u["rum_dps"] = u["maxHp"] * 0.04   # 每秒回4%maxHP×6秒(分秒HoT·per-frame _heal结算)
	u["rum_glow_until"] = battle._t + 6.0                               # 暖色酒气护光标记
	var _rum_dr: float = u["atk"] * 0.15                          # 回合制 pirate·heal defUpAtkPct{pct:15} → +15%×ATK 双抗·6秒
	battle._buff(u, "def", _rum_dr, false, 6.0); battle._buff(u, "mr", _rum_dr, false, 6.0)
	battle._buff(u, "def", u["atk"] * 0.5, false, 6.0)                  # +0.5A护甲(用户2026-07-14确认保留·连同上方0.15A=护甲共+0.65A/魔抗+0.15A)
	var ship = _pirate_get_ship(u)                             # 海盗船扔酒瓶(从持久船抛向海盗)
	var ship2d: Vector2 = (ship.get_meta("ship2d") if ship != null else u["pos"] + Vector2(0.0, -220.0))
	var ship_h: float = (ship.get_meta("ship_h") if ship != null else 5.0)
	var uu: Dictionary = u
	_pirate_rum_bottle(ship2d, ship_h, u["pos"], func() -> void:   # 酒瓶到手: 饮酒琥珀爆+环
		if not uu.get("alive", false): return
		battle._gambler_sys._gambler_pop(uu["pos"], float(uu.get("height", 0.0)) + 0.5, Color(0.95, 0.62, 0.25, 0.85))
		battle._skill_ring(uu["pos"], Color(0.95, 0.62, 0.25, 0.55), 52.0))

func _pirate_rum_bottle(from2d: Vector2, from_h: float, to2d: Vector2, on_land: Callable) -> void:   # 朗姆酒瓶: 船抛真酒瓶(equip-rum-icon)翻滚飞向海盗→到手调on_land
	var b = Sprite3D.new()
	var bt = load("res://assets/sprites/equip/equip-rum-icon.png")
	if bt == null:
		if on_land.is_valid(): on_land.call()
		return
	b.texture = bt
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 手动面向相机+翻滚(酒瓶旋转)
	b.shaded = false; b.transparent = true
	b.pixel_size = (46.0 * battle.WS) / float(maxi(1, bt.get_height()))
	b.position = battle._world_pos(from2d, from_h)
	battle._world.add_child(b)
	var dur: float = clampf(from2d.distance_to(to2d) / 900.0, 0.4, 0.7)
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:
		if not is_instance_valid(b): return
		var flat: Vector2 = from2d.lerp(to2d, p)
		var hh: float = from_h * (1.0 - p) + 2.4 * sin(PI * p) + 1.0   # 高抛物(船高抛给海盗)
		b.position = battle._world_pos(flat, maxf(0.4, hh))
		if battle._cam != null:                                # 面向相机+屏幕内翻滚
			var tf: Transform3D = b.global_transform
			tf.basis = battle._cam.global_transform.basis * Basis(Vector3(0, 0, 1), p * TAU * 2.5)
			b.global_transform = tf
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(b): b.queue_free()
		if on_land.is_valid(): on_land.call())

func _pirate_rum_bubble(u: Dictionary) -> void:   # 酒气暖泡(HoT期上飘·暖琥珀·区别中毒绿)
	var pos2d: Vector2 = u["pos"] + Vector2(randf_range(-15.0, 15.0), randf_range(-2.0, 8.0))
	var spr = battle._glow_bb(pos2d, 0.4, 34.0, Color(0.95, 0.68, 0.3, 0.85))
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(spr, "position", battle._world_pos(pos2d, 1.1), 0.6)
	tw.tween_property(spr, "material_override:albedo_color", Color(0.95, 0.68, 0.3, 0.0), 0.6)
	tw.chain().tween_callback(spr.queue_free)

func _sk_pirate_volley(u: Dictionary, tgt) -> void:              # 海盗龟·火炮齐射(用户2026-07-14补演出): 海盗船高空驶入→对目标800码区降炮弹雨6发·命中才跳伤害·每发0.5A+2%maxHp
	# 每发 = 0.5×ATK + 2%目标最大生命 → 6发全中共 3.0A + 12%maxHp
	# (旧注释写 0.17A/1.7% 是回合制口径, 实时版代码里【没有任何 0.17 系数】; 2026-07-22 订正)
	if tgt == null or not tgt.get("alive", false): tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var ship = _pirate_get_ship(u)                            # 持久演出船(一只·驻场·各招共用·不淡出)
	var ship2d: Vector2 = (ship.get_meta("ship2d") if ship != null else Vector2(tgt["pos"].x, battle.ARENA.position.y + 55.0))
	var ship_h: float = (ship.get_meta("ship_h") if ship != null else 6.5)
	for i in range(6):                                          # 6发炮弹·各朝随机敌发射·落点250码AOE(命中打伤害·用户2026-07-14)
		battle._pending_shots.append({"delay": 0.4 + float(i) * 0.28, "src": u, "fn": func() -> void:
			var cand: Array = []
			for o in battle._targeting._pick_enemies_of(u):
				if o.get("alive", false): cand.append(o)
			if cand.is_empty(): return
			var aim: Dictionary = cand[battle._battle_rng.randi() % cand.size()]   # 随机敌
			var land: Vector2 = aim["pos"] + Vector2(randf_range(-32.0, 32.0), randf_range(-32.0, 32.0))   # 落点略散=炮击手感
			_pirate_ship_muzzle(ship2d, ship_h)                # 船炮口闪
			_pirate_cannonball(ship2d, ship_h, land, func() -> void:   # 炮弹到点才结算(命中才跳)
				battle._burst_vfx("res://assets/sprites/vfx/cannon-blast.png", land, 230.0, 0.3)
				battle._shake(0.05)
				battle._skill_ring(land, Color(1.0, 0.55, 0.3, 0.5), 250.0)   # 落点250码范围环
				for o in battle._targeting._enemies_of(u):                        # 落点250码内: 0.5A+2%目标maxHp 物理(红)
					if o.get("alive", false) and o["pos"].distance_to(land) <= 250.0:
						battle._apply_damage_from(u, o, battle._atk_dmg(u, 0.5, o) + int(o["maxHp"] * 0.02), Color("#ff4444")))
			})

func _pirate_get_ship(u: Dictionary) -> Sprite3D:   # 该海盗的持久演出船(一只·首次建后驻场·火炮/朗姆/登场轰击共用·不重复生成不淡出·用户2026-07-14"船是一只在的")
	var ex = u.get("_perf_ship", null)
	if ex != null and is_instance_valid(ex): return ex
	var side = str(u.get("side", "left"))
	var acx: float = (battle.ARENA.position.x + battle.ARENA.end.x) * 0.5
	var sx: float = acx + (-230.0 if side == "left" else 230.0)
	var ship2d = Vector2(clampf(sx, battle.ARENA.position.x + 150.0, battle.ARENA.end.x - 150.0), battle.ARENA.position.y + 55.0)   # 驻场后方
	var ship = _pirate_perf_ship(ship2d, 6.5, side)
	if ship != null:
		ship.set_meta("ship2d", ship2d)
		ship.set_meta("ship_h", 6.5)
		u["_perf_ship"] = ship
		_pirate_ship_bob(ship)
	return ship

func _pirate_ship_bob(ship: Sprite3D) -> void:   # 驻场轻摇(海浪起伏)
	var base_y: float = ship.position.y
	var bob = ship.create_tween().set_loops()
	bob.tween_property(ship, "position:y", base_y + 0.22, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(ship, "position:y", base_y, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ship.set_meta("bob_tw", bob)   # 存bob供冲锋时杀掉

func _pirate_perf_ship(pos2d: Vector2, h: float, side: String) -> Sprite3D:   # 建演出海盗船sprite(纯装饰·骷髅旗): 淡入
	var path = "res://assets/sprites/skills/pirate-ship.png"
	if not ResourceLoader.exists(path): path = "res://assets/sprites/battle/pirate-ship.png"
	if not ResourceLoader.exists(path): return null
	var tex: Texture2D = load(path)
	var s = Sprite3D.new()
	s.texture = tex
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.flip_h = (side == "right")
	s.pixel_size = (250.0 * battle.WS) / float(maxi(1, tex.get_height()))
	s.modulate = Color(1, 1, 1, 0)
	s.position = battle._world_pos(pos2d, h)
	battle._world.add_child(s)
	var tin = battle._reg_tween()
	tin.tween_property(s, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	return s

func _pirate_ship_muzzle(ship2d: Vector2, h: float) -> void:   # 船炮口闪(橙火光pop)
	var g = battle._glow_bb(ship2d + Vector2(randf_range(-30.0, 30.0), 10.0), h - 0.4, 70.0, Color(1.0, 0.78, 0.32, 0.9))
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3.ONE * 1.6, 0.22)
	tw.tween_property(g, "material_override:albedo_color", Color(1.0, 0.78, 0.32, 0.0), 0.22)
	tw.chain().tween_callback(g.queue_free)

func _pirate_cannonball(from2d: Vector2, from_h: float, to2d: Vector2, on_land: Callable) -> void:   # 炮弹: 从船抛物下落到落点→自销调on_land
	var ball = Sprite3D.new()
	ball.texture = VfxTex._make_glow_texture()
	ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ball.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ball.shaded = false; ball.transparent = true
	ball.modulate = Color(0.16, 0.14, 0.13, 1.0)   # 深铁色炮弹
	ball.pixel_size = (28.0 * battle.WS) / float(maxi(1, ball.texture.get_height()))
	ball.position = battle._world_pos(from2d, from_h)
	battle._world.add_child(ball)
	var dur: float = clampf(from2d.distance_to(to2d) / 950.0, 0.34, 0.62)
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:
		if not is_instance_valid(ball): return
		var flat: Vector2 = from2d.lerp(to2d, p)
		var hh: float = from_h * pow(1.0 - p, 1.7) + 1.2 * sin(PI * p)   # 抛物下落(先抛起再重力加速落地)
		ball.position = battle._world_pos(flat, maxf(0.1, hh))
		if int(p * 20.0) % 3 == 0:   # 烟尾
			var sm = battle._glow_bb(flat, maxf(0.2, hh), 16.0, Color(0.4, 0.38, 0.36, 0.5))
			var st = battle._reg_tween(); st.tween_property(sm, "material_override:albedo_color", Color(0.4, 0.38, 0.36, 0.0), 0.3); st.tween_callback(sm.queue_free)
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if is_instance_valid(ball): ball.queue_free()
		if on_land.is_valid(): on_land.call())

# 海盗船·技能三(封板L379): 首次充能满召唤实体船→冲锋撞目标(第一敌200码1.0A魔法+击飞2秒)→留场; 船=HP1.5×/ATK1.0×/无双抗/攻速0.8射程300/普攻射最近敌0.4A
func _sk_pirate_ship(u: Dictionary, tgt) -> void:
	if not u.get("ship_summoned", false):
		u["ship_summoned"] = true
		battle._spawn_pirate_ship(u, tgt)                          # 首次: 召唤船+冲锋撞
	else:
		_pirate_shotgun(u, tgt)                             # 后续: 海盗龟放霰弹

# 海盗龟·霰弹(封板L361·选海盗船后续充能满): 朝目标60度扇面喷8颗弹丸·每颗命中方向第一敌0.5A物理+40码击退·射程400
# 海盗龟·霰弹(封板L361·选海盗船后续充能满): 朝目标60度扇面喷8颗弹丸·每颗命中方向第一敌0.5A物理+40码击退·射程400
func _pirate_shotgun(u: Dictionary, tgt) -> void:
	var aim = tgt if (tgt != null and tgt.get("alive", false)) else battle._targeting._nearest_enemy(u)
	if aim == null:
		return
	var base_dir: Vector2 = aim["pos"] - u["pos"]
	if base_dir.length() < 1.0:
		base_dir = Vector2.RIGHT
	base_dir = base_dir.normalized()
	battle._muzzle_flash(u["pos"], base_dir, Color("#ffd9a0"))
	battle._skill_ring(u["pos"] + base_dir * 22.0, Color(1.0, 0.82, 0.4, 0.7), 26.0)
	var half: float = deg_to_rad(30.0)                      # 60度扇面=±30度
	for i in range(8):
		var frac: float = (float(i) / 7.0) * 2.0 - 1.0      # -1..1 均分
		var d: Vector2 = base_dir.rotated(half * frac)
		battle._shotgun_pellet(u["pos"], u["pos"] + d * 400.0, Color(1.0, 0.86, 0.5, 0.95), 0.72)   # 弹丸VFX(射程400·慢速用户2026-07-14)
		var hit = battle._basic_first_blocker(u, d)                # 该方向路径第一敌(含蛋·障碍穿我方不挡)
		if hit != null and hit["pos"].distance_to(u["pos"]) <= 400.0:
			battle._apply_damage_from(u, hit, battle._atk_dmg(u, 0.5, hit), Color("#ffd07a"))   # 0.5A物理
			var pd: Vector2 = (hit["pos"] - u["pos"]).normalized()               # 40码轻击退(不用_knockback避免8连击飞震屏)
			hit["pos"] += pd * 40.0
			hit["pos"].x = clampf(hit["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
			hit["pos"].y = clampf(hit["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
			battle._vfx._hit_spark(hit)

func _pirate_ship_charge(ship, from2d: Vector2, from_h: float, to2d: Vector2, on_impact: Callable) -> void:   # 演出船俯冲: 从后方高空冲向撞击点·边冲边变大·拉水花航迹
	if ship == null or not is_instance_valid(ship):
		if on_impact.is_valid(): on_impact.call()
		return
	var base_sc: Vector3 = ship.scale
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:
		if not is_instance_valid(ship): return
		var flat: Vector2 = from2d.lerp(to2d, p)
		var hh: float = lerpf(from_h, 0.7, p * p)          # 加速俯冲(重力式下沉)
		ship.position = battle._world_pos(flat, hh)
		ship.scale = base_sc * lerpf(1.0, 1.7, p)          # 冲近变大(逼近感)
		if int(p * 22.0) % 2 == 0:
			_pirate_ship_wake(flat + Vector2(0.0, 10.0))   # 船尾水花航迹
	, 0.0, 1.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 俯冲放慢(用户"再慢一点"·1.5s更有气势)
	tw.tween_callback(func() -> void:
		if on_impact.is_valid(): on_impact.call())

func _pirate_death_grapple(pirate: Dictionary, killer: Dictionary) -> void:
	# 死亡钩索(用户2026-07-14做观感): 从尸位甩铁钩爪(带链条)飞向击杀者→抓住猛拉回尸位90码→25%击杀者maxHp真伤
	if killer == null or not killer.get("alive", false): return
	killer["_grappled_by"] = pirate   # ★同步标记: 钩索确实锁定了击杀者(演出/伤害都在 tween 里, 无头 CI 下不稳; 测试用这个即时证据)
	var from2d: Vector2 = pirate["pos"]
	var kpos: Vector2 = killer["pos"]
	var dir: Vector2 = from2d - kpos
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var htex = load("res://assets/sprites/vfx/grapple-hook.png")
	var hook = Sprite3D.new()
	hook.texture = htex; hook.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hook.billboard = BaseMaterial3D.BILLBOARD_DISABLED; hook.shaded = false; hook.transparent = true
	hook.pixel_size = (50.0 * battle.WS) / float(maxi(1, htex.get_height()))
	hook.position = battle._world_pos(from2d, 1.0)
	battle._world.add_child(hook)
	var throw_dur: float = clampf(from2d.distance_to(kpos) / 1500.0, 0.16, 0.34)
	var ct = [0.0]
	var pk: Dictionary = pirate; var kk: Dictionary = killer
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:   # ① 甩钩爪飞向击杀者(带链条拖尾)
		if not is_instance_valid(hook): return
		var hp2: Vector2 = from2d.lerp(kpos, p)
		hook.position = battle._world_pos(hp2, 1.0)
		battle._face_screen_dir(hook, from2d, kpos)
		ct[0] += 0.02
		if ct[0] >= 0.05:
			ct[0] = 0.0
			_pirate_chain(from2d, hp2)
	, 0.0, 1.0, throw_dur)
	tw.tween_callback(func() -> void:   # ② 抓住→猛拉回尸位
		if not kk.get("alive", false):
			if is_instance_valid(hook): hook.queue_free()
			return
		battle._skill_ring(kk["pos"], Color(1.0, 0.85, 0.4, 0.65), 42.0)
		var dest: Vector2 = _pirate_grapple_dest(from2d, kpos)
		battle._stun(kk, 0.5, "_pirate_death_grapple", true)   # 拉拽期定身(不乱动)
		var kstart: Vector2 = kk["pos"]
		var ct2 = [0.0]
		var pull = battle._reg_tween()
		pull.tween_method(func(q: float) -> void:
			if not kk.get("alive", false): return
			kk["pos"] = kstart.lerp(dest, q)
			if is_instance_valid(hook): hook.position = battle._world_pos(kk["pos"], 1.0)
			ct2[0] += 0.02
			if ct2[0] >= 0.05:
				ct2[0] = 0.0
				_pirate_chain(from2d, kk["pos"])
		, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		pull.tween_callback(func() -> void:   # ③ 到位: 真伤+爆炸
			if is_instance_valid(hook): hook.queue_free()
			_pirate_grapple_hit(pk, kk)))

## 钩索拉回的终点: 尸位方向 90 码处(clamp 进场)。纯几何, 供演出和测试共用。
func _pirate_grapple_dest(pirate_pos: Vector2, killer_pos: Vector2) -> Vector2:
	var dir: Vector2 = (pirate_pos - killer_pos)
	dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	var dest: Vector2 = pirate_pos - dir * 90.0
	dest.x = clampf(dest.x, battle.ARENA.position.x, battle.ARENA.end.x)
	dest.y = clampf(dest.y, battle.ARENA.position.y, battle.ARENA.end.y)
	return dest


## 钩索到位的实际结算(25% 击杀者最大生命·真实伤害) + 命中演出。
## ★从演出 tween 里抽出来单独一个函数, 为的是【可测】——
##   演出是两层 battle.create_tween 链(甩钩 0.34s → 拉回 0.3s → callback), 场景树 tween 在无头 CI 下
##   推进不稳(2026-07-23: verify_pirate_hook 连红三次都卡在这, 本地永远复现不出)。
##   把数值结算和演出解耦: 演出末尾调它, 测试也直接调它, 不再等整条 tween 跑完。
func _pirate_grapple_hit(pk, kk) -> void:
	if not (kk is Dictionary and kk.get("alive", false)):
		return
	battle._apply_damage_from(pk, kk, int(float(kk["maxHp"]) * 0.25), Color("#ffd07a"), 0.0, true)
	battle._burst_vfx("res://assets/sprites/vfx/cannon-blast.png", kk["pos"], 120.0, 0.4)
	battle._shake(0.06)


func _pirate_chain(from2d: Vector2, to2d: Vector2) -> void:   # 钩索链条(chain-bolt 束·短命·连续调=连续链)
	battle._beam_vfx("res://assets/sprites/vfx/chain-bolt.png", from2d, to2d, 18.0, Color(0.82, 0.9, 1.0, 0.9), 0.13)

func _pirate_ship_wake(pos2d: Vector2) -> void:   # 航迹水花(青白·上飘淡出)
	var w = battle._glow_bb(pos2d, 0.3, 40.0, Color(0.7, 0.92, 1.0, 0.7))
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(w, "scale", Vector3.ONE * 1.5, 0.4)
	tw.tween_property(w, "material_override:albedo_color", Color(0.7, 0.92, 1.0, 0.0), 0.4)
	tw.chain().tween_callback(w.queue_free)

func _pirate_ship_splash(pos2d: Vector2) -> void:   # 撞击大水花爆(青白泡沫团炸开+飞溅水珠·明显·用户2026-07-14"没看到水花")
	var dt = load("res://assets/sprites/vfx/dust-impact.png")
	var dth: float = float(maxi(1, dt.get_height())) if dt != null else 64.0
	for k in range(3):   # 3团青白泡沫(不透明·扩张淡出=能盖住亮水面)
		if dt == null: break
		var f = Sprite3D.new()
		f.texture = dt
		f.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		f.billboard = BaseMaterial3D.BILLBOARD_ENABLED; f.shaded = false; f.transparent = true
		f.modulate = Color(0.82, 0.96, 1.0, 0.96)   # 青白泡沫
		f.pixel_size = ((150.0 + float(k) * 50.0) * battle.WS) / dth
		f.position = battle._world_pos(pos2d + Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 10.0)), 0.45 + float(k) * 0.25)
		battle._world.add_child(f)
		var tw = battle._reg_tween(); tw.set_parallel(true)
		tw.tween_property(f, "scale", Vector3.ONE * (1.7 + float(k) * 0.35), 0.42).from(Vector3.ONE * 0.5).set_delay(float(k) * 0.04)
		tw.tween_property(f, "modulate:a", 0.0, 0.52)
		tw.chain().tween_callback(f.queue_free)
	for i in range(12):   # 飞溅水珠(向外+抛物上飞)
		var ang: float = TAU * float(i) / 12.0 + randf_range(-0.25, 0.25)
		var drop = battle._glow_bb(pos2d, 0.4, 16.0, Color(0.9, 0.97, 1.0, 0.95))
		var dest2d: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * randf_range(70.0, 180.0)
		var peak: float = randf_range(1.6, 3.2)
		var dtw = battle._reg_tween()
		dtw.tween_method(func(p: float) -> void:
			if not is_instance_valid(drop): return
			drop.position = battle._world_pos(pos2d.lerp(dest2d, p), 0.4 + peak * sin(PI * p))
		, 0.0, 1.0, 0.48).set_trans(Tween.TRANS_SINE)
		dtw.parallel().tween_property(drop, "material_override:albedo_color", Color(0.9, 0.97, 1.0, 0.0), 0.48)
		dtw.chain().tween_callback(drop.queue_free)

# 赛博龟阵亡 → 浮游炮全部组装成机甲 (独立单位)