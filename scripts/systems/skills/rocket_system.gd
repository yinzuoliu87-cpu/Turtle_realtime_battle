class_name RocketSystem
extends RefCounted
## 小将火箭技能系统
## 类内簇函数名不变;外部名加 battle. 前缀。

var battle

func _init(b) -> void:
	battle = b

# 蓄力表现: 枪口聚能球(由小渐大·橙→白热·脉动)+ 四周火星吸入 + 脚下能量环脉冲 (整段~1.5s·发射前一刻收束)
func _rocket_charge_vfx(u: Dictionary, aim: Vector2) -> void:
	var muzzle: Vector2 = (u["pos"] as Vector2) + aim * 34.0
	var orb := Sprite3D.new()
	orb.texture = VfxTex._make_fire_glow_tex()
	orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; orb.shaded = false; orb.transparent = true
	orb.pixel_size = (26.0 * battle.WS) / 128.0
	orb.modulate = Color(1.0, 0.5, 0.18, 0.0)
	orb.position = battle._world_pos(muzzle, 0.95); orb.scale = Vector3.ONE * 0.3
	battle._world.add_child(orb)
	var ot = battle._reg_tween(); ot.set_parallel(true)
	ot.tween_property(orb, "scale", Vector3.ONE * 1.4, 1.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 越蓄越大
	ot.tween_property(orb, "modulate", Color(1.0, 0.95, 0.78, 0.95), 1.35)                                        # 橙→白热
	ot.chain().tween_property(orb, "modulate:a", 0.0, 0.14)                                                       # 发射前收束(被吐成导弹)
	ot.chain().tween_callback(orb.queue_free)
	var uu := u
	for i in range(9):                                  # 火星从外圈飞入枪口(能量汇聚感)
		var idx: int = i
		battle._pending_shots.append({"delay": 0.15 + float(i) * 0.13, "src": u, "fn": func() -> void:
			if not uu.get("alive", false) or not battle.is_inside_tree(): return
			var ang: float = float(idx) * 0.92 + 0.5
			var from2: Vector2 = muzzle + Vector2(cos(ang), sin(ang)) * 58.0
			var gl := Sprite3D.new()
			gl.texture = VfxTex._make_glow_texture()
			gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; gl.shaded = false; gl.transparent = true
			gl.pixel_size = 0.015
			gl.modulate = Color(1.0, 0.8, 0.45, 0.9)
			gl.position = battle._world_pos(from2, 0.95)
			battle._world.add_child(gl)
			var gt = battle._reg_tween()
			gt.tween_method(func(t: float) -> void:
				if is_instance_valid(gl): gl.position = battle._world_pos(from2.lerp(muzzle, t), 0.95)
			, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			gt.parallel().tween_property(gl, "modulate:a", 0.0, 0.3)
			gt.tween_callback(gl.queue_free)
		})
	battle._skill_ring(u["pos"], Color(1.0, 0.6, 0.2, 0.55), 42.0)   # 脚下能量环脉冲×2
	battle._pending_shots.append({"delay": 0.75, "src": u, "fn": func() -> void:
		if uu.get("alive", false): battle._skill_ring(uu["pos"], Color(1.0, 0.72, 0.32, 0.5), 46.0)})

# 枪口特效: 白热闪(瞬爆大→收) + 3条锥形喷火 + 火星前喷 + 后坐推退
# 枪口特效: 白热闪(瞬爆大→收) + 3条锥形喷火 + 火星前喷 + 后坐推退
func _rocket_muzzle_flash(u: Dictionary, muzzle: Vector2, aim: Vector2) -> void:
	battle._shake(0.13); battle._add_hitstop(0.03)
	var fl := Sprite3D.new()
	fl.texture = VfxTex._make_fire_glow_tex()
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fl.shaded = false; fl.transparent = true
	fl.pixel_size = (72.0 * battle.WS) / 128.0
	fl.modulate = Color(1.0, 0.97, 0.85, 0.95)
	fl.position = battle._world_pos(muzzle, 0.95); fl.scale = Vector3.ONE * 0.4
	battle._world.add_child(fl)
	var flt = battle._reg_tween(); flt.set_parallel(true)
	flt.tween_property(fl, "scale", Vector3.ONE * 1.25, 0.09).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	flt.tween_property(fl, "modulate:a", 0.0, 0.16)
	flt.chain().tween_callback(fl.queue_free)
	for k in range(3):                                  # 锥形喷火(3条·中间最长)
		var spread: float = (float(k) - 1.0) * 0.32
		var d2: Vector2 = aim.rotated(spread)
		battle._bolt_line(muzzle, muzzle + d2 * (108.0 - absf(spread) * 130.0), Color(1.0, 0.85, 0.5, 0.85 - absf(spread) * 0.55))
	for k2 in range(7):                                 # 火星前喷(锥内散开·抛物淡出)
		var a2: Vector2 = aim.rotated(randf_range(-0.5, 0.5))
		var reach: float = randf_range(45.0, 95.0)
		var sp := Sprite3D.new()
		sp.texture = VfxTex._make_glow_texture()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.pixel_size = randf_range(0.008, 0.016)
		sp.modulate = Color(1.0, 0.82, 0.4, 1.0)
		sp.position = battle._world_pos(muzzle, 0.95)
		battle._world.add_child(sp)
		var dest: Vector2 = muzzle + a2 * reach
		var spt = battle._reg_tween(); spt.set_parallel(true)
		spt.tween_method(func(t: float) -> void:
			if is_instance_valid(sp): sp.position = battle._world_pos(muzzle.lerp(dest, t), 0.95 + 0.25 * sin(t * PI))
		, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spt.tween_property(sp, "modulate:a", 0.0, 0.28)
		spt.chain().tween_callback(sp.queue_free)
	var uu := u                                         # 后坐: 小将被向后推一下再回
	var base: Vector2 = uu["pos"]
	var kt = battle._reg_tween()
	kt.tween_method(func(t: float) -> void:
		if uu.get("alive", false): uu["pos"] = base - aim * (5.0 * sin(t * PI))
	, 0.0, 1.0, 0.16)

# 尾焰喷团: 白热→橙→烟灰·膨胀淡出 (导弹每~0.022s在尾部丢一团→连成推进尾迹)
# 尾焰喷团: 白热→橙→烟灰·膨胀淡出 (导弹每~0.022s在尾部丢一团→连成推进尾迹)
func _rocket_exhaust_puff(pos2d: Vector2, h: float, dir: Vector2) -> void:
	var p := Sprite3D.new()
	p.texture = VfxTex._make_fire_glow_tex()
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED; p.shaded = false; p.transparent = true
	p.pixel_size = (22.0 * battle.WS) / 128.0
	p.modulate = Color(1.0, 0.9, 0.6, 0.9)              # 白热
	var jitter: Vector2 = dir.orthogonal() * randf_range(-4.0, 4.0)
	p.position = battle._world_pos(pos2d + jitter, h)
	p.scale = Vector3.ONE * randf_range(0.7, 1.0)
	battle._world.add_child(p)
	var t = battle._reg_tween(); t.set_parallel(true)
	t.tween_property(p, "scale", Vector3.ONE * 1.7, 0.34)                        # 膨胀
	t.tween_property(p, "modulate", Color(0.5, 0.32, 0.28, 0.0), 0.34)          # 白热→橙→烟灰→透
	t.chain().tween_callback(p.queue_free)

# 附加冲击波环(从近0膨胀到full·比_skill_ring起步更小更猛)
func _rocket_shock_ring(center: Vector2, col: Color, radius: float, dur: float) -> void:
	var r := Sprite3D.new()
	r.texture = VfxTex._make_ring_texture(col)
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED; r.axis = Vector3.AXIS_Y
	r.shaded = false; r.transparent = true
	r.modulate = Color(col.r, col.g, col.b, col.a)
	r.position = battle._world_pos(center, 0.06)
	var target_ps: float = (radius * 2.0 * battle.WS) / 96.0
	r.pixel_size = target_ps * 0.08
	battle._world.add_child(r)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(r, "pixel_size", target_ps, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(r.queue_free)

# 爆后上升烟柱(~1.5s·6团黑烟渐升渐大渐隐)
# 爆后上升烟柱(~1.5s·6团黑烟渐升渐大渐隐)
func _rocket_smoke_plume(center: Vector2) -> void:
	for k in range(6):
		var off: Vector2 = Vector2(randf_range(-38.0, 38.0), randf_range(-38.0, 38.0))
		var sm := Sprite3D.new()
		sm.texture = VfxTex._make_fire_glow_tex()
		sm.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sm.shaded = false; sm.transparent = true
		sm.pixel_size = (58.0 * battle.WS) / 128.0
		sm.modulate = Color(0.32, 0.28, 0.26, 0.0)
		battle._world.add_child(sm)
		var cc: Vector2 = center + off
		var rise: float = randf_range(2.4, 3.6)
		var s0: float = randf_range(0.5, 0.8)
		var s1: float = randf_range(1.7, 2.3)
		var peak: float = randf_range(0.35, 0.5)
		var smref := sm
		var mt = battle._reg_tween()
		mt.tween_method(func(t: float) -> void:
			if not is_instance_valid(smref): return
			var a: float = (t / 0.18) if t < 0.18 else (1.0 - (t - 0.18) / 0.82)
			smref.modulate.a = clampf(a, 0.0, 1.0) * peak
			smref.position = battle._world_pos(cc, 0.6 + rise * t)
			smref.scale = Vector3.ONE * lerpf(s0, s1, t)
		, 0.0, 1.0, 1.5)
		mt.tween_callback(sm.queue_free)

# 地面焦痕(快显→驻留→~0.8s渐隐)
# 地面焦痕(快显→驻留→~0.8s渐隐)
func _rocket_scorch(center: Vector2) -> void:
	var sc := Sprite3D.new()
	sc.texture = VfxTex._make_fire_glow_tex()
	sc.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sc.axis = Vector3.AXIS_Y
	sc.shaded = false; sc.transparent = true
	sc.pixel_size = (300.0 * battle.WS) / 128.0
	sc.modulate = Color(0.12, 0.09, 0.08, 0.0)
	sc.position = battle._world_pos(center, 0.04)
	battle._world.add_child(sc)
	var t = battle._reg_tween()
	t.tween_property(sc, "modulate:a", 0.55, 0.1)
	t.tween_interval(0.7)
	t.tween_property(sc, "modulate:a", 0.0, 0.8)
	t.tween_callback(sc.queue_free)
