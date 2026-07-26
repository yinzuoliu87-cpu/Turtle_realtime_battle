class_name IceSystem
extends RefCounted
## 冰龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _ice_fissure_go(u: Dictionary, si: int, start: Vector2, dir: Vector2) -> void:
	battle._shake(0.14)
	_ice_burst(start)                              # 砸地冰爆
	var reach: float = 500.0
	var width: float = 90.0
	var fdur: float = 0.9
	_ice_fissure_vfx(start, dir, reach, fdur)      # 冰道: 一排冰刺racing forward
	for o in battle._enemies_of(u):
		var along: float = (o["pos"] - start).dot(dir)
		if along < 0.0 or along > reach:
			continue
		if not battle._on_line(start, dir, o["pos"], width):
			continue
		var d: float = clampf(along / reach, 0.0, 1.0) * fdur
		var tw = battle._reg_tween()
		tw.tween_interval(d)                       # 冰道推进到该敌才结算
		tw.tween_callback(_ice_fissure_hit.bind(u, o, si))

func _ice_fissure_hit(u: Dictionary, o: Dictionary, si: int) -> void:
	if not o.get("alive", false):
		return
	battle._apply_damage_from(u, o, battle._resolve_dmg(u, float([25, 40, 60][si]), o, true), Color("#bfe9ff"), 0.0, false, true)   # 魔法伤
	if not o.get("airborne", false) and not o.get("_knock_immune", false):   # 免击飞(017不沉之锚): 直接设airborne会绕过_knockback的守卫(用户2026-07-19"修吧")
		o["airborne"] = true; o["vy"] = 6.6; o["vx"] = 0.0; o["vz"] = 0.0   # 竖直击飞~0.6s(2*6.6/22)
	var fz: float = [1.0, 1.8, 2.5][si]   # freeze dur per star (user 2026-07-03)
	battle._freeze(o, fz)
	battle._frozen_encase(o, fz)                         # 冰封特效持续fzs
	_ice_burst(o["pos"])

func _ice_fissure_vfx(start: Vector2, dir: Vector2, reach: float, fdur: float) -> void:
	# 布隆式: 地面裂开→冰脊/冰墙密排erupt(中脊高两侧矮)+平铺冰原+寒雾; 留存~2.8s后按生成序从头到尾消退
	var perp: Vector2 = dir.orthogonal()
	var field_life: float = 2.8
	var field = load("res://assets/sprites/vfx/ice-field.png")
	var n: int = 26                                          # 密排冰刺=连成冰墙(非稀疏一排)
	for i in range(1, n + 1):
		var f: float = float(i) / float(n)
		var lat: float = randf_range(-46.0, 46.0)
		var hs: float = lerpf(1.4, 0.68, absf(lat) / 46.0) * randf_range(0.82, 1.15)   # 中脊高两侧矮
		var pos: Vector2 = start + dir * (reach * f) + perp * lat
		var tw = battle._reg_tween()
		tw.tween_interval(f * fdur)
		tw.tween_callback(battle._spawn_ice_spike.bind(pos, hs, field_life))
	var m: int = 13
	for i in range(1, m + 1):
		var f: float = float(i) / float(m)
		var pos: Vector2 = start + dir * (reach * f)
		var tf = battle._reg_tween()
		tf.tween_interval(f * fdur)
		tf.tween_callback(_ice_field_patch.bind(field, pos, dir, field_life))
		var tm = battle._reg_tween()
		tm.tween_interval(f * fdur)
		tm.tween_callback(_frost_mist.bind(pos + perp * randf_range(-42.0, 42.0)))

func _ice_field_patch(tex: Texture2D, pos2d: Vector2, dir: Vector2, life: float) -> void:
	if tex == null:
		return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.axis = Vector3.AXIS_Y                                # 躺平贴地=冰原
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(0.72, 0.88, 1.0, 0.0)
	spr.rotation.y = -atan2(dir.y, dir.x)
	spr.pixel_size = (155.0 * battle.WS) / float(maxi(1, int(tex.get_width())))
	spr.position = battle._world_pos(pos2d, 0.04)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.tween_property(spr, "modulate:a", 0.55, 0.12)
	tw.tween_interval(life)
	tw.tween_property(spr, "modulate:a", 0.0, 0.4)
	tw.tween_callback(spr.queue_free)

func _frost_mist(pos2d: Vector2) -> void:
	var tex = VfxTex._make_fire_glow_tex()
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(0.72, 0.9, 1.0, 0.5)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (randf_range(55.0, 92.0) * battle.WS) / float(maxi(1, int(tex.get_width())))
	spr.position = battle._world_pos(pos2d, 0.5)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", battle._world_pos(pos2d, 1.15), 0.7)
	tw.tween_property(spr, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(spr.queue_free)


# ============================================================================
#  迷你水晶球 030/031 (可视叠层+引爆) + 亡灵骷髅 032 + 复活海螺变形 033
# ============================================================================

func _ice_throw_go(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var t = battle._nearest_enemy(u)
	if t == null: return
	var tex: Texture2D = load("res://assets/sprites/vfx/ice-bottle.png")
	var spr = Sprite3D.new()
	if tex != null:
		spr.texture = tex
		spr.pixel_size = (46.0 * battle.WS) / float(maxi(1, int(tex.get_width())))
	else:
		spr.texture = VfxTex._make_fire_glow_tex()
		spr.modulate = Color(0.6, 0.85, 1.0)
		spr.pixel_size = 0.02
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var from2d: Vector2 = u["pos"]
	spr.position = battle._world_pos(from2d, 1.1)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.tween_method(_ice_bottle_arc.bind(spr, from2d, t["pos"]), 0.0, 1.0, 0.6)
	tw.tween_callback(_ice_bottle_hit.bind(spr, u, t, si))

func _ice_bottle_arc(pf: float, spr: Sprite3D, from2d: Vector2, to2d: Vector2) -> void:
	if is_instance_valid(spr):
		spr.position = battle._world_pos(from2d.lerp(to2d, pf), 1.0 + sin(pf * PI) * 2.4)

func _ice_bottle_hit(spr: Sprite3D, u: Dictionary, t: Dictionary, si: int) -> void:
	if is_instance_valid(spr): spr.queue_free()
	if not t.get("alive", false): return
	battle._apply_damage_from(u, t, battle._resolve_dmg(u, float([40, 60, 100][si]), t, true), Color("#bfe9ff"), 0.0, false, true)
	t["spd_move_mult"] = 0.8; t["spd_aspd_mult"] = 0.9; t["spd_dbf_until"] = battle._t + 5.0
	_ice_burst(t["pos"])
	_frost_puff(t["pos"])
	battle._shake(0.06)
	battle._knockback(u, t, 16.0)
	battle._skill_ring(t["pos"], Color(0.7, 0.9, 1.0, 0.55), 62.0)

func _ice_burst(pos2d: Vector2) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/ice-shatter.png")
	if tex == null: return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.hframes = 5
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.no_depth_test = true
	var fw: float = float(maxi(1, int(tex.get_width()))) / 5.0
	spr.pixel_size = (115.0 * battle.WS) / fw
	spr.position = battle._world_pos(pos2d, 0.95)
	battle._world.add_child(spr)
	var t = battle._reg_tween()
	t.tween_method(battle._zap_frame.bind(spr), 0.0, 5.0, 0.34)
	t.tween_callback(spr.queue_free)

func _frost_puff(pos2d: Vector2) -> void:
	var tex = VfxTex._make_fire_glow_tex()
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(0.62, 0.82, 1.0, 0.5)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (78.0 * battle.WS) / float(maxi(1, int(tex.get_width())))
	spr.position = battle._world_pos(pos2d, 0.72)
	battle._world.add_child(spr)
	var t = battle._reg_tween()
	t.tween_interval(0.35)
	t.tween_property(spr, "modulate:a", 0.0, 0.5)
	t.tween_callback(spr.queue_free)

# 029 冰封水母: 冰封目标 + 护盾泡
func _sk_ice_frost(u: Dictionary, tgt: Dictionary) -> void:      # 寒冰龟·冰霜 ✅ (圆形冰霜场: 5秒/每0.5秒一跳/圈内-25%魔抗)
	var center: Vector2 = u["pos"]
	if tgt != null and tgt.get("alive", false):
		center = tgt["pos"]
	else:
		var es = battle._pick_enemies_of(u)
		if not es.is_empty(): center = es[0]["pos"]
	var radius = 150.0
	var tw = battle._reg_tween()
	for i in range(10):   # 5秒 / 每0.5秒 = 10跳
		tw.tween_callback(_ice_frost_tick.bind(u, center, radius))
		tw.tween_interval(0.5)

func _ice_frost_tick(u: Dictionary, center: Vector2, radius: float) -> void:
	_ice_frost_rain(center, radius)
	for o in battle._enemies_of(u):
		if not o.get("alive", false):
			continue
		if o["pos"].distance_to(center) <= radius:
			battle._buff(o, "mr", -0.25, true, 0.65)   # 圈内 -25%魔抗(刷新, 略>0.5s跳间隔)
			battle._apply_damage_from(u, o, battle._atk_dmg(u, 0.18, o, true), Color("#bfe9ff"))

func _ice_frost_rain(center: Vector2, radius: float) -> void:    # 冰霜场视觉: 范围环 + 几片落冰
	battle._skill_ring(center, Color(0.55, 0.85, 1.0, 0.4), radius)
	var tex = "res://assets/sprites/skills/ice-spike.png"
	var has_tex = ResourceLoader.exists(tex)
	for i in range(5):
		var off = Vector2(battle._juice_rng.randf_range(-radius, radius), battle._juice_rng.randf_range(-radius, radius))
		if off.length() > radius:
			continue
		var sh = Sprite3D.new()
		if has_tex:
			sh.texture = load(tex)
			sh.pixel_size = 0.016
			sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			sh.texture = VfxTex._make_bolt_texture(Color(0.6, 0.85, 1.0))
			sh.pixel_size = 0.01
		sh.modulate = Color(0.7, 0.9, 1.0, 0.95)
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.shaded = false
		sh.transparent = true
		var ground = battle._world_pos(center + off, 0.05)
		sh.position = ground + Vector3(0.0, 2.2, 0.0)
		battle._world.add_child(sh)
		var twr = battle._reg_tween()
		twr.set_parallel(true)
		twr.tween_property(sh, "position", ground, 0.35)
		twr.tween_property(sh, "modulate:a", 0.0, 0.3).set_delay(0.18)
		twr.chain().tween_callback(sh.queue_free)

func _sk_ice_freeze(u: Dictionary, tgt: Dictionary) -> void:    # 寒冰龟·冰封 ✅ (冰锥弹道→命中0.6魔法+冻结1.5s)
	if tgt == null or not tgt.get("alive", false):
		return
	battle._fire_ice_shard(u, tgt, battle._atk_dmg(u, 0.6, tgt, true))

func _sk_ice_team_shield(u: Dictionary) -> void:               # 寒冰龟·团队护盾(用户2026-07-11重设计·120龟能): 全体友军5%施法者maxHp冰霜盾4秒·盾破/到期爆炸250码1×ATK魔法; 独狼(无其他友军)盾×4·爆炸5×ATK
	var others = battle._allies_of(u, false)                         # 不含自己
	var solo: bool = others.is_empty()
	var shield_amt: float = u["maxHp"] * (0.20 if solo else 0.05)   # 5%施法者maxHp; 独狼×4=20%
	var boom_mult: float = 5.0 if solo else 1.0                     # 爆炸1×ATK; 独狼5×ATK
	for o in battle._allies_of(u):                                    # 含自己=全体友军
		_frost_shield_burst(o)                                 # 若已挂上一发未爆→先结算(防覆盖丢爆裂)
		battle._grant_shield(o, shield_amt, 4.0)                      # 冰霜盾·4秒
		o["frost_shield_until"] = battle._t + 4.0                     # 爆裂追踪(独立通用shield_until): 到期/盾清零/持盾者死 任一→爆
		o["frost_shield_src"] = u
		o["frost_shield_boom"] = boom_mult
		battle._aura_vfx("res://assets/sprites/vfx/fx-hex-bubble.png", o, 62.0, Color(0.68, 0.9, 1.0, 0.62), 4.0, 0.9)   # 六棱冰晶护盾泡(4秒·罩住友军)

# 冰霜护盾爆裂: 到期/被打破(盾清零)/持盾者死 触发 → 持盾者250码内敌 boom×ATK 魔法 + 冰爆冲击环
# 冰霜护盾爆裂: 到期/被打破(盾清零)/持盾者死 触发 → 持盾者250码内敌 boom×ATK 魔法 + 冰爆冲击环
func _frost_shield_burst(ally: Dictionary) -> void:
	if float(ally.get("frost_shield_until", 0.0)) <= 0.0:
		return
	ally["frost_shield_until"] = 0.0
	if battle._burst_depth >= 32:                    # 与泡泡盾共用级联深度上限(死亡链互爆防卡死·用户2026-07-19)
		if not battle._burst_cap_warned:
			battle._burst_cap_warned = true
			printerr("[GUARD] 泡泡/冰霜盾爆裂级联深度超32→截断(防卡死)")
		return
	battle._burst_depth += 1
	var src = ally.get("frost_shield_src", null)
	var boom: float = float(ally.get("frost_shield_boom", 1.0))
	ally.erase("frost_shield_src")
	if src is Dictionary:
		var c: Vector2 = ally["pos"]
		for o in battle._enemies_of(src):
			if o.get("alive", false) and o["pos"].distance_to(c) <= 250.0:
				battle._apply_damage_from(src, o, battle._atk_dmg(src, boom, o, true), Color("#bfe9ff"))   # boom×ATK 魔法(1或5)
		battle._burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", c, 520.0, 0.14)   # 冰爆冲击环(≈250码半径)
		battle._skill_ring(c, Color(0.68, 0.9, 1.0, 0.6), 250.0)
		battle._vfx._impact_particles(c, 0.0); battle._shake(0.05)
	battle._burst_depth -= 1


# 寒冰登场寒气特效: 蓝霜地环×2 + 上升冰晶 (敌人小, 寒冰自身big)
func _ice_chill_vfx(pos2d: Vector2, big: bool = false) -> void:
	var r: float = 84.0 if big else 52.0
	battle._skill_ring(pos2d, Color(0.55, 0.85, 1.0, 0.95), r)         # 外层寒环
	battle._skill_ring(pos2d, Color(0.85, 0.96, 1.0, 0.55), r * 0.5)  # 内层亮霜
	var n: int = 8 if big else 5
	var tex = "res://assets/sprites/skills/ice-spike.png"
	var has_tex = ResourceLoader.exists(tex)
	for i in range(n):
		var sh = Sprite3D.new()
		if has_tex:
			sh.texture = load(tex)
			sh.pixel_size = 0.02 if big else 0.013
			sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			sh.texture = VfxTex._make_bolt_texture(Color(0.6, 0.85, 1.0))
			sh.pixel_size = 0.01
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.shaded = false
		sh.transparent = true
		sh.modulate = Color(0.62, 0.86, 1.0, 0.95)
		var ang = TAU * float(i) / float(n)
		var off = Vector2(cos(ang), sin(ang)) * (r * 0.45)
		sh.position = battle._world_pos(pos2d + off, 0.35)
		battle._world.add_child(sh)
		var tw = battle._reg_tween()
		tw.set_parallel(true)
		tw.tween_property(sh, "position:y", sh.position.y + (0.9 if big else 0.6), 0.55)
		tw.tween_property(sh, "modulate:a", 0.0, 0.55)
		tw.chain().tween_callback(sh.queue_free)
