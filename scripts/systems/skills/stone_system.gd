class_name StoneSystem
extends RefCounted
## 石头龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _sk_stone_rock_shield(u: Dictionary) -> void:               # 石头龟·岩石护盾(用户设计: 合并岩石护甲+磐石·100龟能): 全队盾0.2A+5%maxHp + 自身双抗+20%5秒
	for o in battle._targeting._allies_of(u):
		battle._grant_shield(o, u["atk"] * 1.0 + u["maxHp"] * 0.06, 4.0)   # 全队盾=1×石头ATK+6%【石头龟】最大生命(用户2026-07-11: 0.2A+5%→1A+6%)·每友军等量·4秒
		o["rock_shield_until"] = battle._t + 4.0                          # 标记"石头岩石护盾"来源: LoL式六棱屏障VFX + 锁龟能(持盾期不充能), 盾破/到期即释放(用户2026-07-11)
		battle._skill_ring(o["pos"], Color(0.79, 0.64, 0.42, 0.45), 46.0)
	battle._buff(u, "def", 0.2, true, 5.0)   # 自身护甲+20%(pct·5秒)
	battle._buff(u, "mr", 0.2, true, 5.0)    # 自身魔抗+20%

func _rock_chunk_erupt(pos2d: Vector2) -> void:   # 岩石破土冒起(石棕灰)→短留→碎(仿 _gold_chunk_erupt·换石色)
	var tex: Texture2D = load("res://assets/sprites/vfx/gold-chunk.png")
	if tex == null: return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(randf_range(0.5, 0.62), randf_range(0.44, 0.54), randf_range(0.36, 0.44), 0.0)   # 石棕灰·起始透明
	var sc: float = randf_range(0.8, 1.35)
	spr.pixel_size = (1.5 * sc) / float(maxi(1, int(tex.get_height())))
	var wh: float = float(tex.get_height()) * spr.pixel_size
	var base_pos: Vector3 = battle._world_pos(pos2d, wh * 0.42)
	spr.position = base_pos - Vector3(0.0, 0.55, 0.0)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", base_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 破土弹出
	tw.tween_property(spr, "modulate:a", 1.0, 0.1)
	tw.chain().tween_interval(0.16)
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(spr.queue_free)

func _sk_stone_taunt(u: Dictionary) -> void:                    # 石头龟·嘲讽(用户设计·120龟能): 500码敌4秒硬嘲讽 + 自身1A永久盾 + 0.5×护甲减伤4秒 + 将结束砸地(400码1A魔法+击飞1.2s)
	var victims: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false) and o["pos"].distance_to(u["pos"]) <= 500.0:
			victims.append(o)
	battle._taunt(u, victims, 4.0)
	battle._grant_shield(u, u["atk"] * 1.0)          # 1A永久盾(dur=0·不随嘲讽消失)
	u["stone_dr_until"] = battle._t + 4.0            # 0.5×护甲%减伤4秒
	u["energy_lock_until"] = battle._t + 3.5        # 砸击(3.5s)之后龟能才重新充能(用户#8"砸击后龟能才重新充能")
	battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 500.0, Color(0.86, 0.68, 0.42, 0.42), 4.0)   # 500码仇恨光环(嘲讽4秒·贴地跟随·用户#8)
	var uu = u
	var slam = func() -> void:                # 蓄力3.5s→砸地(在4秒嘲讽内·K'Sante Q3式)
		if not uu.get("alive", false): return
		battle._burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", uu["pos"], 220.0)   # 砸地岩石冲击(用户2026-07-06"像地面猛砸")
		for o in battle._targeting._enemies_of(uu):
			if o.get("alive", false) and o["pos"].distance_to(uu["pos"]) <= 400.0:
				battle._apply_damage_from(uu, o, battle._atk_dmg(uu, 1.0, o, true), Color("#c8a878"))
				if not o.get("airborne", false):
						battle._knockback(uu, o, 80.0, 3.6111)   # 击飞【1.2秒·峰高6.5】(用户2026-07-11) — vy=6.0×3.6111=21.667
						o["knock_g"] = -36.111            # 配重力-36.111→ 滞空=2×21.667/36.111=1.2s·峰高=21.667²/(2×36.111)=6.5(解耦时长与抛高)
		battle._shake(0.06)
	battle._pending_shots.append({"delay": 3.5, "fn": slam, "src": u})

func _sk_rock_shockwave(u: Dictionary) -> void:                  # 石头龟·岩石之躯 主动: 前方带状(±90)岩脊向前破土推进, (0.5DEF+0.5MR)×(1+4%岩层)物理 + 【必中眩晕2s】+ 击退60
#   (2026-07-19订正: 头注释原写"1%×层眩晕1.5s"是旧版, 用户2026-07-11已改成必中2秒, 见下方 battle._stun 那行); 伤害随波前经过逐个同步(用户2026-07-11补VFX·原=只1个130px环)
	var tgt = battle._targeting._acquire_target(u)
	var dir: Vector2 = (Vector2.RIGHT if tgt == null else (tgt["pos"] - u["pos"]))
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp = Vector2(-dir.y, dir.x)
	var layers: int = int(u.get("rock_layers", 0))
	var origin: Vector2 = u["pos"]
	var uu = u
	var windup = 0.16                                       # 起手踏地时长
	var wave_spd = 900.0                                    # 岩脊波前推进速度(码/秒)
	# ── 起手: 石头抬身猛踏(_slam_voff 抬→砸) ──
	var smt = battle._reg_tween()
	smt.tween_method(func(v: float): uu["_slam_voff"] = Vector3(0.0, v, 0.0), 0.0, 0.55, 0.1).set_ease(Tween.EASE_OUT)
	smt.chain().tween_method(func(v: float): uu["_slam_voff"] = Vector3(0.0, v, 0.0), 0.55, 0.0, 0.06).set_ease(Tween.EASE_IN)
	smt.chain().tween_callback(func(): uu["_slam_voff"] = Vector3.ZERO)
	# ── 踏地瞬间(windup 后): 震屏+顿帧+脚下碎石+起手环 ──
	var wf = func() -> void:
		battle._shake(battle.JUICE_SHAKE_HEAVY); battle._hitstop = maxf(battle._hitstop, 0.05)
		battle._vfx._impact_particles(origin, 0.0)
		battle._burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", origin, 210.0, 0.06)
		battle._skill_ring(origin, Color(0.79, 0.64, 0.42, 0.6), 120.0)
	battle._pending_shots.append({"delay": windup, "src": u, "fn": wf})
	# ── 岩脊沿 dir 向前破土推进(铺满带宽·波前渐进) ──
	var reach = 820.0
	var step = 44.0
	var d = 34.0
	while d < reach:
		var cp: Vector2 = origin + dir * d
		var dl: float = windup + d / wave_spd
		var pa: Vector2 = cp + perp * randf_range(-32.0, 32.0)
		var fa = func() -> void: _rock_chunk_erupt(pa)
		battle._pending_shots.append({"delay": dl, "src": u, "fn": fa})
		if randf() < 0.7:
			var pb: Vector2 = cp + perp * randf_range(-86.0, 86.0)
			var fb = func() -> void: _rock_chunk_erupt(pb)
			battle._pending_shots.append({"delay": dl, "src": u, "fn": fb})
		d += step
	# ── 伤害: 前方带状(几何不变)·随波前经过逐个同步结算 ──
	var dmgv: int = int((u["def"] * 0.5 + u["mr"] * 0.5) * (1.0 + 0.04 * layers))
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - origin
		if rel.dot(dir) <= 0.0: continue                     # 只前方
		if absf(rel.dot(perp)) > 90.0: continue              # 带宽~180
		var oo = o
		var hit_delay: float = windup + maxf(0.0, rel.dot(dir)) / wave_spd
		var hf = func() -> void:
			if not oo.get("alive", false): return
			battle._apply_damage_from(uu, oo, dmgv, Color("#c8a878"))
			battle._stun(oo, 2.0, "_sk_rock_shockwave")   # 命中即眩晕2秒(用户2026-07-11: 除击退外必附2s眩晕·原1%×层概率改必中·头顶通用眩晕圈由_update_stun_vfx画)
			battle._knockback(uu, oo, 60.0)
			_rock_chunk_erupt(oo["pos"])                     # 命中点额外破土
			battle._vfx._flash(oo)
		battle._pending_shots.append({"delay": hit_delay, "src": u, "fn": hf})

