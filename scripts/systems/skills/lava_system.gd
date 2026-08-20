class_name LavaSystem
extends RefCounted
## 熔岩带/火山系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 类内 _lava_*/_tick_lava_zones 名字与主场景一字不差 → 内部互调零改动;只外部名加 battle. 前缀。

## ★移速从 turtle_stats.ROLE 派生 —— 熔岩定位=近战法师(用户2026-07-28「熔岩龟两个形态下也按近战处理」)。
## 两形态都读这一档: 小形态虽 melee=false/射程400, 移速仍按近战档(见 ROLE_MELEE_EXEMPT)。
const _TS := preload("res://scripts/gamedata/turtle_stats.gd")
static var LAVA_SPD: float = float(_TS.STATS["lava"][1])
## 变身砸地(用户 2026-08-13 削弱): 伤害 1.2 → 1.0 ATK · 灼烧 0.67 → 0.3 ATK 层。
## ★灼烧用【本技专用】系数而不是全局 `_default_burn_stacks`(0.67) —— 那个凤凰等火系也在用,
##   改全局会连带削掉别人(凤凰的涅槃早就用自己的 NIRVANA_BURN_COEF, 同一手法)。
## 火山爆发(用户 2026-08-14 削弱): 原 5 段 0.5ATK + 全局灼烧 + 12% 回血
## ⇒ 一段 1.2ATK 魔法 · 0.2ATK 层灼烧(本技专用) · 8% 回血。
## ★★为什么灼烧要用本技专用系数: 全局 `_default_burn_stacks`(0.67) **凤凰等火系也在用**,
##   为熔岩调它会静默削掉别人 —— 2026-08-13 已经在砸地上踩过一次同样的坑。
const ERUPT_ATK_COEF := 1.2
const ERUPT_BURN_COEF := 0.2
const ERUPT_HEAL_PCT := 0.08
const SLAM_ATK_COEF := 1.0
const SLAM_BURN_COEF := 0.3
const VOLCANO_SPD_MULT := 1.2   # 火山形态相对提速(原 175/145≈1.21 的等效保留)

var battle
var _lava_zones: Array = []               # 持续熔岩地面区域 (熔岩龟·岩浆池等) {center,...}

func _init(b) -> void:
	battle = b

# ───────── 熔岩龟·持续地面区域系统 (岩浆池) ─────────
func _tick_lava_zones(_delta: float) -> void:   # 每帧: 周期结算池内敌 + 到期清理 (_process 内调)
	if _lava_zones.is_empty():
		return
	var keep: Array = []
	for z in _lava_zones:
		if battle._t >= float(z["next_tick"]):
			z["next_tick"] = float(z["next_tick"]) + 0.5
			var src: Dictionary = z["src"]
			if src != null and src.get("alive", false):
				var c: Vector2 = z["center"]
				var r: float = float(z["radius"])
				for o in battle._targeting._enemies_of(src):
					if not o.get("alive", false):
						continue
					if o["pos"].distance_to(c) > r:
						continue
					battle._damage._apply_damage_from(src, o, battle._atk_dmg(src, 0.06, o, true), Color("#ff7a33"))   # 0.06×ATK魔/0.5s
					o["slow_until"] = maxf(float(o.get("slow_until", 0.0)), battle._t + 0.6); o["slow_mag"] = 0.65   # 地裂减速35%(move×0.65·用户2026-07-09"35"·≥0.6s续)
					battle._damage._buff(o, "mr", -0.30, true, 0.6)                                              # 魔抗-30% (每跳刷新)
		if battle._t >= float(z["until"]):
			var disc = z.get("disc", null)
			if disc != null and is_instance_valid(disc):
				var tw = battle._reg_tween()
				tw.tween_property(disc, "modulate:a", 0.0, 0.35)
				tw.chain().tween_callback(disc.queue_free)
		else:
			keep.append(z)
	_lava_zones = keep

func _lava_quake(u: Dictionary) -> void:                         # 小·岩浆池: 敌最密处生成5秒岩浆池, 每0.5s池内敌 0.06ATK魔+减速35%+魔抗-30%
	var center: Vector2 = battle._densest_enemy_point(u, 180.0)
	var radius := 180.0
	var disc := Sprite3D.new()                                   # 持续贴地橙红岩浆盘
	disc.texture = battle._sheet("res://assets/sprites/vfx/fx_lava_pool.png")   # AI生成熔岩池贴图
	disc.billboard = BaseMaterial3D.BILLBOARD_DISABLED; disc.axis = Vector3.AXIS_Y   # 躺平贴地
	disc.shaded = false; disc.transparent = true
	disc.modulate = Color(1.0, 1.0, 1.0, 0.0)
	disc.pixel_size = (radius * 2.0 * battle.WS) / 768.0
	disc.position = battle._world_pos(center, 0.035)
	battle._world.add_child(disc)
	var rot = battle._reg_tween().bind_node(disc).set_loops()        # 缓旋=熔岩流动(静态图+代码动)  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	rot.tween_property(disc, "rotation:y", TAU, 7.0).from(0.0)
	var pt = battle._reg_tween()                                     # 淡入 + 5秒缓脉动
	pt.tween_property(disc, "modulate:a", 0.92, 0.25)
	for i in range(10):                                          # 5s / 0.5s = 10 次脉动
		pt.tween_property(disc, "modulate:a", 0.7, 0.25)
		pt.tween_property(disc, "modulate:a", 0.92, 0.25)
	_lava_zones.append({
		"center": center, "radius": radius, "until": battle._t + 5.0,
		"next_tick": battle._t + 0.5, "src": u, "disc": disc,
	})
	battle._skill_ring(center, Color(1.0, 0.45, 0.15, 0.5), radius)

func _lava_volcano_erupt(u: Dictionary) -> void:                 # 火山·火山爆发(用户2026-07-15定稿): 目标那头的尽头生成岩浆浪潮→朝火山龟压过来(250码/s)→穿过龟到另一头尽头消散; 碾过每敌击飞+一段 ERUPT_ATK_COEF(1.2)A 魔+ERUPT_BURN_COEF(0.2)A 灼烧+回血 ERUPT_HEAL_PCT(8%)
	var dir: Vector2 = battle._densest_enemy_point(u, 400.0) - u["pos"]   # 瞄准轴: 朝敌最密方向
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	var tdir: Vector2 = -dir                                       # ★行进方向=朝火山龟压过来(用户: 目标尽头生成→移向龟→穿过到另一端)
	var full_len := 1200.0                                         # 行进全长(目标侧尽头600→穿过龟→背后尽头600)
	var half_w := 140.0                                            # 浪半宽(全宽280码)
	var origin: Vector2 = u["pos"]
	var start: Vector2 = origin + dir * 600.0                      # 生成点=目标所在那头的尽头
	var ang := -atan2(tdir.y, tdir.x)                             # 浪体朝向=行进方向(前缘对着龟)
	var perp_axis := Vector2(-dir.y, dir.x)
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)
	# 1) 超长红矩形预警 (拉长 blob 沿 dir, ~0.6s, 横跨全场)
	var tel := Sprite3D.new()
	tel.texture = VfxTex._make_blob_texture()
	tel.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tel.axis = Vector3.AXIS_Y
	tel.shaded = false; tel.transparent = true
	tel.modulate = Color(1.0, 0.15, 0.05, 0.0)
	tel.position = battle._world_pos(origin, 0.03)                       # 预警=以龟为中心±600码走廊(浪的整条路径)
	tel.pixel_size = (full_len * battle.WS) / 128.0
	tel.scale = Vector3(1.0, 1.0, (half_w * 2.0) / full_len)      # 沿 dir 长, 横向窄
	tel.rotation = Vector3(0.0, ang, 0.0)                        # 朝向 dir
	battle._world.add_child(tel)
	var tt = battle._reg_tween()
	tt.tween_property(tel, "modulate:a", 0.42, 0.18)
	tt.tween_interval(0.42)
	await tt.finished
	# 2) 浪头飞沫 (GPUParticles3D·点缀): 随波前移动; 主体=下方shader浪丘
	var wave := GPUParticles3D.new()
	wave.amount = 220
	wave.lifetime = 0.4                                           # 短拖尾 (~0.4s)
	wave.one_shot = false
	wave.explosiveness = 0.0                                      # 持续发射 (墙体连续, 非一次爆)
	wave.local_coords = false                                     # 世界坐标: 发射后粒子留在原地 → 形成拖尾, 不随墙体平移
	wave.preprocess = 0.1                                         # 预热: 出现即是完整墙体非空
	var wmat := ParticleProcessMaterial.new()
	wmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	wmat.emission_box_extents = Vector3(0.12, 0.06, (half_w * battle.WS))   # 沿行进(本地x)薄, 垂直行进(本地z)宽=墙面; 旋转后对齐 dir
	wmat.direction = Vector3(0, 1, 0)                            # 主要向上喷 (火浪向上翻腾)
	wmat.spread = 32.0
	wmat.flatness = 0.0
	wmat.initial_velocity_min = 1.6
	wmat.initial_velocity_max = 4.2
	wmat.gravity = Vector3(0, -4.5, 0)                          # 下坠 → 翻卷的浪头
	wmat.scale_min = 0.7
	wmat.scale_max = 1.7
	# 颜色: 白热核 → 亮橙 → 暗红 → 透明 (火/岩浆)
	var wgrad := Gradient.new()
	wgrad.set_offset(0, 0.0); wgrad.set_color(0, Color(1.0, 0.95, 0.8, 1.0))    # 白热
	wgrad.add_point(0.3, Color(1.0, 0.6, 0.18, 1.0))                            # 亮橙
	wgrad.add_point(0.7, Color(0.95, 0.24, 0.05, 0.85))                         # 暗红
	wgrad.set_offset(wgrad.get_point_count() - 1, 1.0)
	wgrad.set_color(wgrad.get_point_count() - 1, Color(0.45, 0.04, 0.0, 0.0))   # 透明熄灭
	var wramp := GradientTexture1D.new()
	wramp.gradient = wgrad
	wmat.color_ramp = wramp
	wave.process_material = wmat
	wave.draw_pass_1 = battle._make_glow_quad(0.6)
	wave.rotation = Vector3(0.0, ang, 0.0)                       # 旋转发射盒+墙面对齐 dir
	wave.amount = 120                                              # 降为浪头飞沫(主体=shader浪丘·用户2026-07-15"粒子做不出浪潮感")
	wave.position = battle._world_pos(start, 0.12)                       # 起步: 自己脚前(娜美R式从施法者推出)
	battle._world.add_child(wave)
	wave.emitting = true
	var wall := MeshInstance3D.new()                              # ★浪体: 世界空间3D浪壳mesh(用户2026-07-15"就一个图在动?四面八方?"→非billboard平面图; 横轴⊥行进·剖面前脚→上升→浪尖前卷·任何方向朝向自动正确)
	var wim := ImmediateMesh.new()
	wall.mesh = wim
	var wsm := ShaderMaterial.new()
	wsm.shader = load("res://assets/shaders/lava_wave.gdshader")
	wall.material_override = wsm
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wall_w: float = (half_w * 2.0 + 60.0) * battle.WS                # 浪宽(横向·世界)
	var wall_len: float = wall_w * 1.05                           # 浪长(沿行进)=1.05×宽(用户2026-07-15: 前后变窄0.7倍·原1.5×)
	var wall_h: float = wall_w * 0.16                             # 低矮(观察: 高<1英雄·非墙)
	# 低矮拉长鼓包剖面(局部: +X=行进, Y=高, Z=横向): 前缘→鼓顶→长尾(闭环包过顶·两端捏合)
	var prof: Array = [Vector2(0.5, 0.0), Vector2(0.42, 0.55), Vector2(0.26, 0.95), Vector2(0.0, 1.0), Vector2(-0.28, 0.8), Vector2(-0.46, 0.35), Vector2(-0.5, 0.0)]   # (x前后±0.5×浪长, y高)
	var M := 16                                                   # 横向分段
	wim.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(M):
		var z0: float = (float(j) / float(M) - 0.5) * wall_w
		var z1: float = (float(j + 1) / float(M) - 0.5) * wall_w
		var cx0: float = float(j) / float(M) * 2.0 - 1.0
		var cx1: float = float(j + 1) / float(M) * 2.0 - 1.0
		var hf0: float = sqrt(maxf(0.0, 1.0 - pow(absf(cx0), 3.0)))   # 中段平坦成板(slab)·两端圆角捏合(体自闭合)
		var hf1: float = sqrt(maxf(0.0, 1.0 - pow(absf(cx1), 3.0)))
		for k in range(prof.size() - 1):
			var pa: Vector2 = prof[k]
			var pb: Vector2 = prof[k + 1]
			var va0 := Vector3(pa.x * wall_len * hf0, pa.y * wall_h * hf0, z0)
			var va1 := Vector3(pa.x * wall_len * hf1, pa.y * wall_h * hf1, z1)
			var vb0 := Vector3(pb.x * wall_len * hf0, pb.y * wall_h * hf0, z0)
			var vb1 := Vector3(pb.x * wall_len * hf1, pb.y * wall_h * hf1, z1)
			var ua: float = float(k) / float(prof.size() - 1)              # v=剖面弧位置0(前脚)→0.33(浪尖)→0.5(顶)→1(背脚): 白沫只给浪尖前缘一圈(按高度会把整个顶面刷白)
			var ub: float = float(k + 1) / float(prof.size() - 1)
			var u0: float = float(j) / float(M)
			var u1: float = float(j + 1) / float(M)
			var na0: Vector3 = (va0 - Vector3(0.0, wall_h * 0.25, z0)).normalized()   # 法线≈从浪芯轴向外(顶面朝上/前脸朝前)→shader按面向明暗=立体感
			var na1: Vector3 = (va1 - Vector3(0.0, wall_h * 0.25, z1)).normalized()
			var nb0: Vector3 = (vb0 - Vector3(0.0, wall_h * 0.25, z0)).normalized()
			var nb1: Vector3 = (vb1 - Vector3(0.0, wall_h * 0.25, z1)).normalized()
			wim.surface_set_normal(na0); wim.surface_set_uv(Vector2(u0, ua)); wim.surface_add_vertex(va0)
			wim.surface_set_normal(na1); wim.surface_set_uv(Vector2(u1, ua)); wim.surface_add_vertex(va1)
			wim.surface_set_normal(nb1); wim.surface_set_uv(Vector2(u1, ub)); wim.surface_add_vertex(vb1)
			wim.surface_set_normal(na0); wim.surface_set_uv(Vector2(u0, ua)); wim.surface_add_vertex(va0)
			wim.surface_set_normal(nb1); wim.surface_set_uv(Vector2(u1, ub)); wim.surface_add_vertex(vb1)
			wim.surface_set_normal(nb0); wim.surface_set_uv(Vector2(u0, ub)); wim.surface_add_vertex(vb0)
	wim.surface_end()
	wall.rotation = Vector3(0.0, ang, 0.0)                        # 朝向行进方向(世界空间·四面八方都对)
	wall.position = battle._world_pos(start, 0.04)                      # 底边贴地·从自己脚前出发
	battle._world.add_child(wall)
	tel.modulate.a = 0.42
	# 3) 波前沿线推进 + 逐帧命中判定 (tween_method 推 front-distance d: 0→full_len, 0.7s)
	var hit: Array = []  # ★2026-07-10 闪退真因: 不能拿【单位字典】当 Dictionary 的 key —— Godot 会对 key 求哈希, 单位字典里有 summons/summon_owner 等互相引用的结构 → recursive_hash 无限递归 → 每次查表刷一条 ERROR: Max recursion reached。改用 Array(.has 走 == 不哈希)。                                       # 已命中敌 (each-once)
	var step := func(d: float) -> void:
		var front: Vector2 = start + tdir * d                     # 当前波前位置 (从目标侧尽头朝火山龟压过来)
		if is_instance_valid(wave):
			wave.position = battle._world_pos(front, 0.12)
		if is_instance_valid(wall):
			wall.position = battle._world_pos(front, 0.04)               # 浪壳随波前推进(mesh底边即地面)
			(wall.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.92 + 0.08 * sin(battle._t * 13.0))
			if battle._juice_rng.randf() < 0.55:                         # 浪顶洒火星熔滴(行进点缀)
				var sx: Vector2 = front + perp_axis * battle._juice_rng.randf_range(-half_w * 0.8, half_w * 0.8)
				var sp := Sprite3D.new()
				sp.texture = VfxTex._make_fire_glow_tex()
				sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
				sp.pixel_size = 0.0042
				sp.modulate = Color(1.0, 0.8, 0.4, 0.95)
				sp.position = battle._world_pos(sx, wall_h * battle._juice_rng.randf_range(0.7, 1.0))
				battle._world.add_child(sp)
				var st = battle._reg_tween(); st.set_parallel(true)
				st.tween_property(sp, "position", battle._world_pos(sx + tdir * battle._juice_rng.randf_range(20.0, 60.0), 0.1), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				st.tween_property(sp, "modulate:a", 0.0, 0.4)
				st.chain().tween_callback(sp.queue_free)
			if battle._juice_rng.randf() < 0.6:                          # ★雾云尾迹(娜美R观察: 不规则软雾云包四周+尾部拖白雾)
				var mpos: Vector2 = front + perp_axis * battle._juice_rng.randf_range(-half_w * 1.1, half_w * 1.1) - tdir * battle._juice_rng.randf_range(0.0, 180.0)
				var mf := Sprite3D.new()
				mf.texture = VfxTex._make_fire_glow_tex()
				mf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
				mf.billboard = BaseMaterial3D.BILLBOARD_ENABLED; mf.shaded = false; mf.transparent = true
				mf.pixel_size = 0.013
				mf.modulate = Color(1.0, 0.62, 0.3, 0.22)         # 软橙雾(低alpha大团)
				mf.scale = Vector3(0.6, 0.6, 0.6)
				mf.position = battle._world_pos(mpos, battle._juice_rng.randf_range(0.2, wall_h * 0.9))
				battle._world.add_child(mf)
				var mt = battle._reg_tween(); mt.set_parallel(true)
				mt.tween_property(mf, "scale", Vector3(1.6, 1.6, 1.6), 0.7)
				mt.tween_property(mf, "position", battle._world_pos(mpos - tdir * 40.0 + perp_axis * battle._juice_rng.randf_range(-30.0, 30.0), wall_h * 1.1), 0.7)
				mt.tween_property(mf, "modulate:a", 0.0, 0.7)
				mt.chain().tween_callback(mf.queue_free)
		if is_instance_valid(tel):
			tel.modulate.a = lerpf(0.42, 0.12, clampf(d / full_len, 0.0, 1.0))
		for o in battle._targeting._enemies_of(u):
			if not o.get("alive", false):
				continue
			if battle._arr_has_unit(hit, o):
				continue
			var rel: Vector2 = o["pos"] - start
			var perp: float = absf(rel.dot(perp_axis))
			if perp >= half_w:
				continue                                          # 不在浪宽内
			var along: float = rel.dot(tdir)
			if along < -20.0 or along > d:
				continue                                          # 波前尚未扫到
			hit.append(o)                                         # 命中一次 (each-once; 用 Array 不用 Dictionary-key, 见下方注释)
			_lava_burst_vfx(o["pos"])                             # 命中飞溅(娜美R观察: 每敌一团泡沫飞溅·浪不停穿过)
			if not o.get("airborne", false) and not o.get("_knock_immune", false):                      # 击飞+击退加强(用户2026-07-15: vy 4→6·推力×1.6)
				o["airborne"] = true
				o["vy"] = 6.0
				o["vx"] = tdir.x * battle.KNOCK_PUSH * 1.6
				o["vz"] = tdir.y * battle.KNOCK_PUSH * 1.6
			## ★用户 2026-08-14 削弱: 5 段 0.5ATK(共 2.5ATK) → **一段 1.2ATK**;
			##   灼烧改用【本技专用系数】0.2ATK 层(原走全局 `_default_burn_stacks` 0.67 ——
			##   那个凤凰等火系也在用, 改它会静默削掉别人); 回血 12% → 8%。
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, ERUPT_ATK_COEF, o, true), Color("#ff7a33"))
			if o["alive"]:
				battle._damage._apply_dot_stacks(o, "burn", maxi(1, roundi(float(u["atk"]) * ERUPT_BURN_COEF)), u)
			battle._damage._heal(u, u["maxHp"] * ERUPT_HEAL_PCT)
	battle._gambler_sys._gambler_pop(start, 0.6, Color(1.0, 0.85, 0.5, 0.95))         # ★出生爆闪(娜美R观察: 浪在白亮爆闪中诞生·非淡入)
	battle._skill_ring(start, Color(1.0, 0.6, 0.2, 0.8), 70.0)
	for bi in range(6):                                           # 放射光条
		var ba: float = TAU * float(bi) / 6.0 + battle._juice_rng.randf_range(-0.2, 0.2)
		battle._bolt_line(start, start + Vector2(cos(ba), sin(ba)) * battle._juice_rng.randf_range(40.0, 80.0), Color(1.0, 0.9, 0.6, 0.9))
	battle._shake(battle.JUICE_SHAKE_BIG)
	var travel := 4.8                                             # 1200码/4.8s=250码/s(用户2026-07-15定)
	var wt = battle._reg_tween()
	wt.tween_method(step, 0.0, full_len, travel).set_trans(Tween.TRANS_SINE)
	wt.parallel().tween_property(tel, "modulate:a", 0.0, travel)   # 预警随浪推进淡出
	# 浪到端 → 停发射, 等拖尾消散, 清理 (用计时器避免 IntervalTweener 链式坑)
	await wt.finished
	if is_instance_valid(tel):
		tel.queue_free()
	if is_instance_valid(wall):
		var wf = battle._reg_tween()                                    # ★消散摊平(娜美R观察: 到端摊平变薄成一层膜+渐隐·非突然消失)
		wf.set_parallel(true)
		wf.tween_property(wall, "scale:y", 0.06, 0.45)
		wf.tween_property(wall, "scale:x", 1.55, 0.45)
		wf.tween_property(wall, "scale:z", 1.55, 0.45)
		var wref = wall
		wf.tween_method(func(v: float) -> void:
			if is_instance_valid(wref): (wref.material_override as ShaderMaterial).set_shader_parameter("intensity", v)
		, 1.0, 0.0, 0.45)
		wf.chain().tween_callback(wall.queue_free)
	if is_instance_valid(wave):
		wave.emitting = false
		await battle._wait_sim(wave.lifetime + 0.1)
		if is_instance_valid(wave):
			wave.queue_free()

func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 蓄力 → 目标脚下岩浆柱击飞 (1.5ATK魔 + 0.8ATK永久护盾)
	if tgt == null or not tgt.get("alive", false):
		return
	u["_slam"] = true
	battle._anticipate(u)
	var center: Vector2 = tgt["pos"]
	# 1) 蓄力 ~0.5s: 熔岩身上聚火光
	var glow := Sprite3D.new()
	glow.texture = VfxTex._make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.shaded = false; glow.transparent = true
	glow.pixel_size = 0.012
	glow.modulate = Color(1.0, 0.5, 0.15, 0.0)
	glow.scale = Vector3(0.5, 0.5, 0.5)
	glow.position = battle._world_pos(u["pos"], 0.4)
	battle._world.add_child(glow)
	var cg = battle._reg_tween()
	cg.tween_property(glow, "modulate:a", 0.9, 0.4).set_trans(Tween.TRANS_QUAD)
	cg.parallel().tween_property(glow, "scale", Vector3(1.6, 1.6, 1.6), 0.5)
	cg.tween_property(glow, "modulate:a", 0.0, 0.15)
	cg.chain().tween_callback(glow.queue_free)
	var charge = battle._reg_tween(); charge.tween_interval(0.5)
	await charge.finished
	# 目标可能中途死亡 → 在原落点继续演出/给盾, 不强求命中
	if tgt != null and tgt.get("alive", false):
		center = tgt["pos"]
	# 2) 目标脚下岩浆柱拔起 (~0.22s) — AI生成熔岩柱贴图 (单帧 Sprite3D, tween 演出)
	var pillar_tex: Texture2D = battle._sheet("res://assets/sprites/vfx/fx_lava_pillar.png")
	var pillar := Sprite3D.new()
	pillar.texture = pillar_tex
	pillar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pillar.shaded = false; pillar.transparent = true
	pillar.modulate = Color(1.0, 1.0, 1.0, 0.0)
	# 让柱约 180px 高 (按贴图实际高度归一)
	var pillar_h: float = float(pillar_tex.get_height()) if pillar_tex != null else 768.0
	pillar.pixel_size = (180.0 * battle.WS) / pillar_h
	pillar.scale = Vector3(0.3, 0.3, 0.3)
	pillar.position = battle._world_pos(center, 0.05)            # 起步低位 (略埋地)
	battle._world.add_child(pillar)
	var pt = battle._reg_tween()
	pt.set_parallel(true)                                  # 升起 + 放大 + 渐显
	pt.tween_property(pillar, "scale", Vector3(1.0, 1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt.tween_property(pillar, "position", battle._world_pos(center, 0.9), 0.22)
	pt.tween_property(pillar, "modulate:a", 1.0, 0.22)
	pt.chain().tween_interval(0.18)                        # 停顿
	pt.chain().tween_property(pillar, "modulate:a", 0.0, 0.18)
	pt.chain().tween_callback(pillar.queue_free)
	# 3) 击飞 目标 + 120px 内敌, 给目标伤害, 给自身护盾
	battle._shake(battle.JUICE_SHAKE_BIG); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
	battle._skill_ring(center, Color(1.0, 0.5, 0.18, 0.7), 120.0)
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(center) > 120.0: continue
		battle._knock_up(o, center, 9.0)
	if tgt != null and tgt.get("alive", false):
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, 1.5, tgt, true), Color("#ff9d5c"))
	battle._damage._grant_shield(u, u["atk"] * 0.8)
	u["_slam"] = false

func _lava_flame_strike(u: Dictionary, tgt: Dictionary) -> void: # 火山·重击: 蓄力猛砸击飞 1.3ATK+8%自身maxHP物理 + 20%吸血
	if tgt == null or not tgt.get("alive", false):
		return
	u["_slam"] = true
	battle._anticipate(u)
	var dir: Vector2 = (tgt["pos"] - u["pos"])
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	# 1) 蓄力 ~0.5s: 身上聚火光
	var glow := Sprite3D.new()
	glow.texture = VfxTex._make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.shaded = false; glow.transparent = true
	glow.pixel_size = 0.013
	glow.modulate = Color(1.0, 0.45, 0.12, 0.0)
	glow.scale = Vector3(0.5, 0.5, 0.5)
	glow.position = battle._world_pos(u["pos"], 0.4)
	battle._world.add_child(glow)
	var cg = battle._reg_tween()
	cg.tween_property(glow, "modulate:a", 0.92, 0.4).set_trans(Tween.TRANS_QUAD)
	cg.parallel().tween_property(glow, "scale", Vector3(1.8, 1.8, 1.8), 0.5)
	cg.tween_property(glow, "modulate:a", 0.0, 0.15)
	cg.chain().tween_callback(glow.queue_free)
	var charge = battle._reg_tween(); charge.tween_interval(0.5)
	await charge.finished
	# 2) 猛砸: 击飞目标 + 震屏顿帧 + (已正确的)伤害
	battle._shake(battle.JUICE_SHAKE_BIG); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
	if tgt != null and tgt.get("alive", false):
		battle._vfx._flash(u, Color(1.6, 0.7, 0.3))
		battle._skill_ring(tgt["pos"], Color(1.0, 0.4, 0.1, 0.7), 90.0)
		battle._vfx._impact_particles(tgt["pos"], 0.0)
		_lava_burst_vfx(tgt["pos"])                  # AI生成爆裂火球
		battle._knock_up(tgt, tgt["pos"] - dir * 10.0, 9.0)
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, 1.3, tgt) + int(u["maxHp"] * 0.08), Color("#ff7a33"), 0.20)
	u["_slam"] = false


# 熔岩之心·变身火山龟: 全属性提升(数据驱动 passive transform*) + 持续N秒 + 变身瞬间全体爆发灼烧吸血.
# ★怒气【不】在变身时清空 —— 火山期间怒气条当倒计时条匀速流失(用户2026-07-15), 归零在 _lava_revert。
func _lava_transform(u: Dictionary) -> void:
	if u.get("volcano", false):
		return
	var p: Dictionary = u.get("passive", {}) if u.get("passive", null) is Dictionary else {}
	var dur: float = float(p.get("transformDuration", 15))
	var hp_scale: float = float(p.get("transformHpScale", 2.5))
	var atk_scale: float = float(p.get("transformAtkScale", 0.2))
	var def_scale: float = float(p.get("transformDefScale", 0.2))
	var mr_scale: float = float(p.get("transformMrScale", 0.2))
	var base_atk: float = float(u["base_atk"])                    # 加成基准=攻击力(变身前)
	u["volcano"] = true                                           # 怒气条不清零: 火山15秒内当倒计时条匀速流失(用户2026-07-15)
	u["volcano_until"] = battle._t + dur
	u["_volcano_dur"] = dur
	u["melee"] = true; u["atk_range"] = 70.0; u["move_spd"] = LAVA_SPD * VOLCANO_SPD_MULT   # 火山形态=近战冲脸(用户2026-07-28: 两形态都按近战档·冲脸保+20%相对提速)
	# 属性提升 (1:1 pets.json: +ATK*2.5 最大HP / +ATK*0.2 攻防魔抗 flat); 用 buff(到期自动撤) + 直接加血上限(到期revert)
	battle._damage._buff(u, "atk", base_atk * atk_scale, false, dur)
	battle._damage._buff(u, "def", base_atk * def_scale, false, dur)
	battle._damage._buff(u, "mr",  base_atk * mr_scale,  false, dur)
	var hp_gain: float = base_atk * hp_scale
	u["_volcano_hp_gain"] = hp_gain
	u["maxHp"] += hp_gain; u["hp"] += hp_gain
	# 变身演出: 加里奥R式 跃升 → 敌最密处大圈预警 → 砸地击飞范围内全部敌 + 入场爆发AOE (异步)
	_lava_volcano_slam(u)

func _lava_revert(u: Dictionary) -> void:                        # 火山形态结束 → 变回小形态 (撤回血上限, 属性buff自然到期)
	u["volcano"] = false
	u["rage"] = 0.0                                               # 形态结束怒气正好归零(倒计时条走完·用户2026-07-15)
	u["melee"] = false; u["atk_range"] = 400.0; u["move_spd"] = LAVA_SPD   # 变回远程射程400, 但移速仍按【近战法师】档(用户2026-07-28拍板·ROLE_MELEE_EXEMPT)
	var hp_gain: float = float(u.get("_volcano_hp_gain", 0.0))
	if hp_gain > 0.0:
		u["maxHp"] = maxf(1.0, u["maxHp"] - hp_gain)
		u["hp"] = minf(u["hp"], u["maxHp"])
	u["_volcano_hp_gain"] = 0.0

func _lava_ult_revert(u: Dictionary) -> void:                   # 火山暴走5秒结束→撤回+20%maxHp
	if not u.get("alive", false): return
	var g: float = float(u.get("_lava_ult_hp", 0.0))
	if g <= 0.0: return
	u["maxHp"] = maxf(1.0, u["maxHp"] - g)
	u["hp"] = minf(u["hp"], u["maxHp"])
	u["_lava_ult_hp"] = 0.0

func _lava_pierce_bolt(u: Dictionary, tgt) -> void:             # 熔岩·穿透普攻: 贯穿全场岩浆光矢+沿途0.6A【魔法】+4%目标maxHp+0.07A灼烧层 (★旧注释写"真伤"与代码不符, 2026-07-10订正)
	var dir: Vector2 = ((tgt["pos"] - u["pos"]).normalized() if (tgt != null) else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	battle._bolt_line(u["pos"], u["pos"] + dir * 2000.0, Color(1.0, 0.5, 0.2, 0.95))
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if is_same(o, tgt) or battle._on_line(u["pos"], dir, o["pos"], 70.0):
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 0.6, o, true) + int(o["maxHp"] * 0.04), Color("#ff7a3c"))
			battle._damage._apply_dot_stacks(o, "burn", maxi(1, int(round(float(u["atk"]) * 0.07))), u)

func _lava_slam_telegraph(pos2d: Vector2, radius: float, dur: float) -> void:   # 落点预警(像素化·用户2026-07-15): 外硬边像素环+内环倒计时收缩到圆心+中心裂纹微光
	var outer = battle._px_ground_sprite(VfxTex._make_pixel_ring_tex(), pos2d, radius * 2.0, Color(1.0, 0.32, 0.1, 0.0), 0.045)
	var inner = battle._px_ground_sprite(VfxTex._make_pixel_ring_tex(), pos2d, radius * 2.0, Color(1.0, 0.62, 0.2, 0.0), 0.05)
	var crack = battle._px_ground_sprite(load("res://assets/sprites/vfx/lava-crack.png"), pos2d, radius * 1.1, Color(1, 1, 1, 0.0), 0.035)   # 中心裂纹预示(淡)
	var td = battle._reg_tween()
	td.set_parallel(true)
	td.tween_property(outer, "modulate:a", 0.85, 0.15)
	td.tween_property(inner, "modulate:a", 0.8, 0.15)
	td.tween_property(crack, "modulate:a", 0.3, 0.3)
	td.tween_property(inner, "scale", Vector3(0.06, 1.0, 0.06), dur).set_trans(Tween.TRANS_LINEAR)   # 内环收缩到圆心=倒计时
	td.chain().tween_callback(outer.queue_free)
	td.chain().tween_callback(inner.queue_free)
	td.chain().tween_callback(crack.queue_free)

func _lava_charge_vfx(u: Dictionary) -> void:   # 滞空蓄力: 火山龟身上聚火光 (越蓄越盛, 临砸最亮)
	var g := Sprite3D.new()
	g.texture = VfxTex._make_fire_glow_tex()
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.pixel_size = 0.015
	g.modulate = Color(1.0, 0.5, 0.15, 0.0)
	g.scale = Vector3(0.5, 0.5, 0.5)
	g.position = battle._world_pos(u["pos"], battle.LAVA_LEAP_H + 0.3)
	battle._world.add_child(g)
	var t = battle._reg_tween()
	t.tween_property(g, "modulate:a", 0.92, battle.LAVA_CHARGE_T * 0.8).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(g, "scale", Vector3(1.9, 1.9, 1.9), battle.LAVA_CHARGE_T)
	t.tween_property(g, "modulate:a", 0.0, battle.LAVA_SLAM_T + 0.05)
	t.tween_callback(g.queue_free)
	for i in range(8):                                            # 火星向心汇聚(吸能感·像素化设计2026-07-15)
		var sa: float = TAU * float(i) / 8.0 + battle._juice_rng.randf_range(-0.3, 0.3)
		var soff: Vector2 = Vector2(cos(sa), sin(sa)) * battle._juice_rng.randf_range(70.0, 110.0)
		var sp := Sprite3D.new()
		sp.texture = VfxTex._make_pixel_block_tex()
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.018
		sp.modulate = Color(1.0, 0.75, 0.3, 0.0)
		sp.position = battle._world_pos(u["pos"] + soff, battle.LAVA_LEAP_H + battle._juice_rng.randf_range(-0.3, 0.5))
		battle._world.add_child(sp)
		var st = battle._reg_tween()
		st.tween_interval(float(i) * 0.06)
		st.tween_property(sp, "modulate:a", 0.95, 0.08)
		st.tween_property(sp, "position", battle._world_pos(u["pos"], battle.LAVA_LEAP_H + 0.3), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		st.parallel().tween_property(sp, "modulate:a", 0.0, 0.3)
		st.tween_callback(sp.queue_free)

func _lava_volcano_slam(u: Dictionary) -> void:   # 加里奥R式: 高跃升+飞落点 → 滞空蓄力(预警) → 砸地击飞+爆发
	u["_slam"] = true
	u["untargetable_until"] = battle._t + battle.LAVA_LEAP_UP_T + battle.LAVA_CHARGE_T + battle.LAVA_SLAM_T + 0.05   # 滞空不可被主动索敌(能受伤·敌立刻换目标·用户2026-07-15)
	var start: Vector2 = u["pos"]
	var target: Vector2 = battle._densest_enemy_point(u, battle.LAVA_SLAM_RADIUS)
	battle._anticipate(u); battle._shake(battle.JUICE_SHAKE_HEAVY)
	_lava_slam_telegraph(target, battle.LAVA_SLAM_RADIUS, battle.LAVA_LEAP_UP_T + battle.LAVA_CHARGE_T + battle.LAVA_SLAM_T)
	for i in range(9):                                            # 起跳点像素尘土块弹开(2026-07-15像素化)
		var da: float = TAU * float(i) / 9.0 + battle._juice_rng.randf_range(-0.3, 0.3)
		var dp := Sprite3D.new()
		dp.texture = VfxTex._make_pixel_block_tex()
		dp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		dp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dp.shaded = false; dp.transparent = true
		dp.pixel_size = 0.02 * battle._juice_rng.randf_range(0.7, 1.2)
		dp.modulate = Color(0.75, 0.6, 0.45, 0.9)                # 土色尘块
		dp.position = battle._world_pos(start, 0.15)
		battle._world.add_child(dp)
		var de: Vector2 = start + Vector2(cos(da), sin(da)) * battle._juice_rng.randf_range(40.0, 85.0)
		var dt = battle._reg_tween(); dt.set_parallel(true)
		dt.tween_property(dp, "position", battle._world_pos(de, battle._juice_rng.randf_range(0.1, 0.5)), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dt.tween_property(dp, "modulate:a", 0.0, 0.38)
		dt.chain().tween_callback(dp.queue_free)
	# 1) 高跃升 + 同时飞向落点
	var up = battle._reg_tween(); up.set_parallel(true)
	up.tween_method(func(h): u["height"] = h, 0.0, battle.LAVA_LEAP_H, battle.LAVA_LEAP_UP_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_method(func(p): u["pos"] = p, start, target, battle.LAVA_LEAP_UP_T).set_trans(Tween.TRANS_SINE)
	await up.finished
	# 2) 滞空蓄力 (悬停高处, 火光渐聚, 不直接砸)
	_lava_charge_vfx(u)
	var hover = battle._reg_tween()
	hover.tween_interval(battle.LAVA_CHARGE_T)
	await hover.finished
	# 3) 砸地
	var down = battle._reg_tween()
	down.tween_method(func(h): u["height"] = h, battle.LAVA_LEAP_H, 0.0, battle.LAVA_SLAM_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await down.finished
	u["pos"] = target; u["height"] = 0.0
	u["untargetable_until"] = battle._t                                  # 落地恢复可被索敌
	_lava_slam_impact(u, target)
	u["_slam"] = false

# 爆裂火球: AI生成熔岩爆发贴图 (单帧 Sprite3D, scale 0.4→1.5 + alpha 1→0 绽放). 接地火球冲击
# 爆裂火球: AI生成熔岩爆发贴图 (单帧 Sprite3D, scale 0.4→1.5 + alpha 1→0 绽放). 接地火球冲击
func _lava_burst_vfx(pos2d: Vector2) -> void:
	var burst_tex: Texture2D = battle._sheet("res://assets/sprites/vfx/fx_lava_burst.png")
	var burst := Sprite3D.new()
	burst.texture = burst_tex
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	burst.shaded = false; burst.transparent = true
	burst.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var burst_h: float = float(burst_tex.get_height()) if burst_tex != null else 768.0
	burst.pixel_size = (200.0 * battle.WS) / burst_h        # 约 200px 直径基准 (scale 缩放)
	burst.scale = Vector3(0.4, 0.4, 0.4)
	burst.position = battle._world_pos(pos2d, 0.7)
	battle._world.add_child(burst)
	var bt = battle._reg_tween()
	bt.set_parallel(true)
	bt.tween_property(burst, "scale", Vector3(1.5, 1.5, 1.5), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(burst, "modulate:a", 0.0, 0.4)
	bt.chain().tween_callback(burst.queue_free)

func _lava_slam_impact(u: Dictionary, center: Vector2) -> void:   # 落地: 击飞范围内全部敌 + 入场爆发AOE
	battle._shake(battle.JUICE_SHAKE_BIG); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
	for ri in range(2):                               # 像素冲击环×2错峰扩散(硬边·替换软_skill_ring·2026-07-15像素化)
		var pring = battle._px_ground_sprite(VfxTex._make_pixel_ring_tex(), center, battle.LAVA_SLAM_RADIUS * 2.0, Color(1.0, 0.5 + 0.25 * float(ri), 0.15, 0.0), 0.05 + 0.01 * float(ri))
		pring.scale = Vector3(0.25, 1.0, 0.25)
		var rt = battle._reg_tween()
		rt.tween_interval(0.09 * float(ri))
		rt.tween_property(pring, "modulate:a", 0.95, 0.04)
		rt.tween_property(pring, "scale", Vector3(1.0, 1.0, 1.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.parallel().tween_property(pring, "modulate:a", 0.0, 0.32)
		rt.tween_callback(pring.queue_free)
	var crk = battle._px_ground_sprite(load("res://assets/sprites/vfx/lava-crack.png"), center, battle.LAVA_SLAM_RADIUS * 1.3, Color(1, 1, 1, 0.0), 0.04)   # 裂地贴片(停留后淡出)
	var ct = battle._reg_tween()
	ct.tween_property(crk, "modulate:a", 0.95, 0.06)
	ct.tween_interval(1.1)
	ct.tween_property(crk, "modulate:a", 0.0, 0.4)
	ct.tween_callback(crk.queue_free)
	var rtex: Texture2D = load("res://assets/sprites/vfx/lava-rock.png")   # 岩块碎片抛物弹射
	for i in range(10):
		var ra: float = TAU * float(i) / 10.0 + battle._juice_rng.randf_range(-0.25, 0.25)
		var rdist: float = battle._juice_rng.randf_range(70.0, 170.0)
		var rp := Sprite3D.new()
		rp.texture = rtex
		rp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		rp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; rp.shaded = false; rp.transparent = true
		rp.flip_h = battle._juice_rng.randf() < 0.5
		rp.pixel_size = (26.0 * battle.WS) / float(maxi(1, rtex.get_height())) * battle._juice_rng.randf_range(0.7, 1.3)
		rp.position = battle._world_pos(center, 0.5)
		battle._world.add_child(rp)
		var endp: Vector2 = center + Vector2(cos(ra), sin(ra)) * rdist
		var hpk: float = battle._juice_rng.randf_range(0.8, 1.5)
		var life: float = battle._juice_rng.randf_range(0.32, 0.5)
		var rw = battle._reg_tween()
		rw.tween_method(func(p: float) -> void:
			if is_instance_valid(rp): rp.position = battle._world_pos(center.lerp(endp, p), 0.5 + hpk * 4.0 * p * (1.0 - p) - 0.4 * p)   # 抛物(峰在中段·落回地)
		, 0.0, 1.0, life)
		rw.tween_property(rp, "modulate:a", 0.0, 0.1)
		rw.tween_callback(rp.queue_free)
	battle._vfx._flash(u, Color(1.6, 0.7, 0.3))
	battle._vfx._impact_particles(center, 0.0)
	_lava_burst_vfx(center)                           # AI生成爆裂火球
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if (o["pos"] - center).length() > battle.LAVA_SLAM_RADIUS: continue
		if not o.get("airborne", false) and not o.get("_knock_immune", false):
			var dir: Vector2 = (o["pos"] - center)
			dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
			o["airborne"] = true
			o["vy"] = battle.LAVA_SLAM_KNOCK_VY
			o["vx"] = dir.x * battle.KNOCK_PUSH * 0.7
			o["vz"] = dir.y * battle.KNOCK_PUSH * 0.7
		## ★2026-08-13 用户削弱: 砸地伤害 1.2 → 1.0 ATK, 灼烧 0.67 → 0.3 ATK 层。
		##   ★灼烧不再走全局 `_default_burn_stacks`(那是 0.67, 凤凰/别的火系也在用) ——
		##   改成砸地【专用】系数, 就近声明在这里(同凤凰 NIRVANA_BURN_COEF 的做法)。
		battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, SLAM_ATK_COEF, o, true), Color("#ff7a33"))
		battle._damage._apply_dot_stacks(o, "burn", maxi(1, roundi(float(u["atk"]) * SLAM_BURN_COEF)), u)
		battle._damage._heal(u, (o["maxHp"] - o["hp"]) * 0.08)

func _sk_lava_cast(u: Dictionary, tgt: Dictionary, set_id: String = "A") -> void:   # 熔岩龟·按选中技分派(A地裂/B岩浆涌动/C喷射)×形态变体
	var volcano: bool = u.get("volcano", false)
	match set_id:
		"A":
			if volcano: _lava_volcano_erupt(u)
			else:       _lava_quake(u)
		"B":
			if volcano: _lava_flame_strike(u, tgt)
			else:       _lava_magma_surge(u, tgt)
		_:
			_lava_quake(u)

# 通用·击飞: 把 o 从 center 上抛+外推 (1:1 _lava_slam_impact 的击飞段, 抽公共)
func _sk_lava_erupt(u: Dictionary, tgt) -> void:                # 熔岩龟·技三(用户设计): 火山形态=暴走(+20%maxHp5s+30%攻速+30%移速) / 普通形态=智能冲刺(保命撤/追击贴)+下发普攻穿透
	if u.get("volcano", false):
		var gain: float = u["maxHp"] * 0.20
		u["_lava_ult_hp"] = float(u.get("_lava_ult_hp", 0.0)) + gain
		u["maxHp"] += gain; u["hp"] += gain
		u["haste_mult"] = 1.3; u["haste_until"] = battle._t + 5.0        # +30%攻速
		u["spd_move_mult"] = 1.3; u["spd_dbf_until"] = battle._t + 5.0   # +30%移速
		var tw = battle._reg_tween()
		tw.tween_interval(5.0)
		tw.tween_callback(_lava_ult_revert.bind(u))
		battle._skill_ring(u["pos"], Color(1.0, 0.4, 0.1, 0.6), 62.0); battle._vfx._flash(u, Color(1.6, 0.9, 0.4))
		return
	var danger: bool = u["hp"] < u["maxHp"] * 0.35
	if not danger:
		for e in battle._targeting._enemies_of(u):
			if e.get("alive", false) and e.get("melee", false) and (e["pos"] - u["pos"]).length() < 110.0:
				danger = true; break
	if danger:                                                   # 保命: 背离最近威胁撤220码
		var threat = battle._targeting._nearest_enemy(u)
		var d: Vector2 = ((u["pos"] - threat["pos"]).normalized() if threat != null else Vector2.RIGHT)
		if d.length() < 0.1: d = Vector2.RIGHT
		u["pos"] += d * 220.0
		u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
	elif tgt != null and tgt.get("alive", false):               # 追击: 冲贴目标
		battle._dash_to(u, tgt, 80.0)
	u["atk_cd"] = 0.0                                            # 重置下次普攻(立刻可放)
	u["lava_pierce_next"] = true                                # 下一发熔岩弹变穿透
	battle._skill_ring(u["pos"], Color(1.0, 0.45, 0.15, 0.6), 54.0); battle._vfx._flash(u, Color(1.6, 0.9, 0.4))

