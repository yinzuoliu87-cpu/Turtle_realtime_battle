class_name RainbowSystem
extends RefCounted
## 彩虹龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _rainbow_enh_prism_proc(u: Dictionary) -> void:            # 强化棱镜4色(用户设计·每5秒抽1): 橙全体友军+10%吸血5s / 黄随机敌灼烧0.67A / 青随机敌冰寒5s / 紫随机敌诅咒5s
	var c: int = battle._battle_rng.randi() % 4
	var es: Array = battle._pick_enemies_of(u)
	match c:
		0:
			for o in battle._allies_of(u):
				battle._buff(o, "lifesteal", 0.1, false, 5.0)
			battle._vfx._float_text(u["pos"] + Vector2(0, -60), "橙·全体吸血", Color("#ff9d3c"))
		1:
			if not es.is_empty():
				var t = es[battle._battle_rng.randi() % es.size()]
				battle._apply_dot_stacks(t, "burn", maxi(1, int(round(float(u["atk"]) * 0.67))), u)
		2:
			if not es.is_empty():
				var t2 = es[battle._battle_rng.randi() % es.size()]
				t2["spd_aspd_mult"] = 0.7; t2["spd_dbf_until"] = battle._t + 5.0   # 冰寒-30%攻速5秒
		3:
			if not es.is_empty():
				var t3 = es[battle._battle_rng.randi() % es.size()]
				battle._add_dot(t3, "curse", t3["maxHp"] * 0.05, 5.0, u)             # 诅咒每秒5%maxHp真伤5秒
	battle._skill_ring(u["pos"], Color(0.8, 0.6, 1.0, 0.4), 48.0)

# 棱镜护盾施法特效: 七彩爆发从彩虹龟扩散 + 每友军护盾罩+棱镜色pop (用户2026-07-13补·"棱镜"主题)
func _rainbow_prism_shield_vfx(u: Dictionary) -> void:
	# 施法者: 6色空心环错峰扩散 → 彩虹涟漪(空心+alpha混合→色分明不糊白)
	for i in range(battle._PRISM_RAINBOW.size()):
		var col: Color = battle._PRISM_RAINBOW[i]
		var tw = battle._reg_tween()
		tw.tween_interval(i * 0.07)
		tw.tween_callback(func() -> void:
			if not u.get("alive", false): return
			var r = Sprite3D.new()
			r.texture = VfxTex._make_ring_texture(col)
			r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			r.shaded = false; r.transparent = true
			r.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			r.modulate = Color(col.r, col.g, col.b, 0.95)
			r.pixel_size = (66.0 * battle.WS) / 96.0
			r.position = battle._world_pos(u["pos"], 0.9)
			battle._world.add_child(r)
			var rt = battle._reg_tween(); rt.set_parallel(true)
			rt.tween_property(r, "scale", Vector3.ONE * 4.2, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			rt.tween_property(r, "modulate:a", 0.0, 0.55)
			rt.chain().tween_callback(r.queue_free))
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	# 每友军: 护盾罩(复用现成)
	for o in battle._allies_of(u):
		battle._shield_dome(o)

func _rainbow_storm_tick(u: Dictionary, center: Vector2, radius: float, ti: int) -> void:
	if not u.get("alive", false):
		return
	var col: Color = battle._PRISM_RAINBOW[ti % battle._PRISM_RAINBOW.size()]
	# 每跳: 中心冲击波脉冲(贴地扩散环·当跳色→节拍可感)
	var pulse = Sprite3D.new()
	pulse.texture = VfxTex._make_ring_texture(Color(1, 1, 1))
	pulse.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pulse.axis = Vector3.AXIS_Y
	pulse.shaded = false; pulse.transparent = true
	pulse.modulate = Color(col.r, col.g, col.b, 0.9)
	pulse.position = battle._world_pos(center, 0.08)
	pulse.pixel_size = (60.0 * battle.WS) / 96.0
	battle._world.add_child(pulse)
	var ptw = battle._reg_tween(); ptw.set_parallel(true)
	ptw.tween_property(pulse, "scale", Vector3.ONE * (radius * 2.0 / 60.0), 0.5)
	ptw.tween_property(pulse, "modulate:a", 0.0, 0.5)
	ptw.chain().tween_callback(pulse.queue_free)
	# 圈内敌: 削护甲魔抗 + 伤害 + 碎甲可视化
	for o in battle._enemies_of(u):
		if not o.get("alive", false):
			continue
		if o["pos"].distance_to(center) <= radius:
			battle._buff(o, "def", -0.20, true, 0.65)   # 圈内-20%护甲
			battle._buff(o, "mr", -0.20, true, 0.65)    # 圈内-20%魔抗
			battle._apply_damage_from(u, o, battle._atk_dmg(u, 0.1, o, true), Color("#ff8ad8"))
			battle._apply_damage_from(u, o, int(u["atk"] * 0.05), Color("#fff0a0"), 0.0, true)   # 8跳共0.8魔+0.4真=原值
			battle._storm_shred(o)   # ★碎甲: 把"削护甲魔抗"可视化

# 碎甲: 削防御的可视化(AI棱镜碎片爆在敌人身上)
func _rainbow_storm_end(u: Dictionary) -> void:
	for n in u.get("storm_nodes", []):
		if n == null or not is_instance_valid(n):
			continue
		if n is GPUParticles3D:
			n.emitting = false                       # 停发, 剩余粒子自然消散再销
			var dt = battle._reg_tween(); dt.tween_interval(1.4); dt.tween_callback(n.queue_free)
		else:
			var ft = battle._reg_tween(); ft.tween_interval(0.25); ft.tween_callback(n.queue_free)
	u["storm_nodes"] = []
	var disc = u.get("storm_disc", null)   # 兼容旧字段(防遗留)
	if disc != null and is_instance_valid(disc):
		disc.queue_free()
	u["storm_disc"] = null

func _sk_rainbow_shield(u: Dictionary) -> void:                  # 彩虹龟·棱镜护盾 ✅
	_rainbow_prism_shield_vfx(u)   # 七彩棱镜爆发+每友军护盾罩(用户2026-07-13补施法特效)
	for o in battle._allies_of(u):
		battle._grant_shield(o, u["atk"] * 0.65, 4.0)   # 彩虹棱镜护盾(通用护盾4秒·封板L268)

func _sk_rainbow_storm(u: Dictionary) -> void:                  # 彩虹龟·全色风暴 (重做2026-07-13: AI棱镜漩涡+GPU彩虹粒子+碎甲可视化-20%护甲魔抗+亮边AOE·期间锁龟能)
	u["storm_until"] = battle._t + 4.0                 # 风暴4秒期间龟能锁定(用户)
	var center: Vector2 = u["pos"]              # 固定施法点
	var radius = 140.0
	var nodes: Array = []
	# ① 旋转棱镜漩涡(AI素材·贴地·加性发光·4s转3圈)
	var vtex: Texture2D = load("res://assets/sprites/vfx/rainbow-vortex.png")
	if vtex != null:
		var pivot = Node3D.new()
		pivot.position = battle._world_pos(center, 0.06)
		battle._world.add_child(pivot)
		var mi = MeshInstance3D.new()
		var q = QuadMesh.new(); q.size = Vector2(radius * 2.3 * battle.WS, radius * 2.3 * battle.WS)
		mi.mesh = q
		var m = StandardMaterial3D.new()
		m.albedo_texture = vtex
		m.albedo_color = Color(1, 1, 1, 0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD          # 加性发光(黑底自然透明)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mi.material_override = m
		mi.rotation_degrees = Vector3(-90, 0, 0)              # 躺平贴地
		pivot.add_child(mi)
		var fin = battle._reg_tween(); fin.tween_property(mi, "material_override:albedo_color", Color(1, 1, 1, 0.92), 0.3)
		var spin = battle._reg_tween(); spin.tween_property(pivot, "rotation:y", -TAU * 3.0, 4.0)   # 4s转3圈
		nodes.append(pivot)
	# ② 亮边圈(AOE边界·贴地)
	var rim = Sprite3D.new()
	rim.texture = VfxTex._make_ring_texture(Color(1, 1, 1))
	rim.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	rim.axis = Vector3.AXIS_Y
	rim.shaded = false; rim.transparent = true
	rim.modulate = Color(0.78, 0.9, 1.0, 0.85)
	rim.position = battle._world_pos(center, 0.05)
	rim.pixel_size = (radius * 2.0 * battle.WS) / 96.0
	battle._world.add_child(rim)
	nodes.append(rim)
	# ③ GPU彩虹粒子(圆盘内上升·全光谱ramp·240颗=暴风能量/体积)
	var ps = battle._storm_particles(center, radius)
	if ps != null: nodes.append(ps)
	u["storm_nodes"] = nodes
	var tw = battle._reg_tween()
	for i in range(8):   # 4秒 / 每0.5秒 = 8跳
		tw.tween_callback(_rainbow_storm_tick.bind(u, center, radius, i))
		tw.tween_interval(0.5)
	tw.tween_callback(_rainbow_storm_end.bind(u))

# 全色风暴 GPU 粒子: 圆盘内发射, 上升, 全光谱彩虹ramp (240颗=暴风能量体积)
func _sk_rainbow_reflect(u: Dictionary) -> void:               # 彩虹龟·反射弹射 (重做2026-07-13: 棱镜光束敌我间反射弹跳·治友绿/伤敌全色魔法)
	var allies = battle._allies_of(u)
	var enemies = battle._enemies_of(u)
	var prev: Vector2 = u["pos"]                # 弹射起点=彩虹龟
	for i in range(6):
		var _ally: bool = (i % 2 == 0)
		var target = null
		if _ally:
			if not allies.is_empty(): target = allies[(i / 2) % allies.size()]
		else:
			if not enemies.is_empty(): target = enemies[(i / 2) % enemies.size()]
		if target == null: continue
		var from_p: Vector2 = prev
		var tp: Vector2 = target["pos"]
		prev = tp                               # 下一段从这里继续弹(链式反射)
		var tref: Dictionary = target
		var _col: Color = battle._PRISM_RAINBOW[i]
		var tw = battle._reg_tween()
		tw.tween_interval(float(i) * 0.22)      # 逐段错峰=看得见弹射依次跳(0.09→0.22减慢·用户2026-07-14)
		tw.tween_callback(func() -> void:
			battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", from_p, tp, 30.0, Color(_col.r, _col.g, _col.b, 0.9), 0.55, 0.9)   # 棱镜反射光束(当跳色·时长0.3→0.55更慢更看得清)
			if _ally:
				if tref.get("alive", false): battle._heal(tref, u["atk"] * 0.5)
				battle._reflect_pop(tp, float(tref.get("height", 0.0)), Color(0.3, 1.0, 0.5, 0.9))    # 治友=绿pop
			else:
				if tref.get("alive", false): battle._apply_damage_from(u, tref, battle._atk_dmg(u, 0.5, tref, true), Color("#ff8ad8"))
				battle._reflect_pop(tp, float(tref.get("height", 0.0)), Color(_col.r, _col.g, _col.b, 0.95)))   # 伤敌=当跳色pop

# 反射弹射命中pop(加性glow缩放淡出)
