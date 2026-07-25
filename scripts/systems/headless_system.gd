class_name HeadlessSystem
extends RefCounted
## 无头骑士·恐惧/镰刀/触须系统(从主场景抽出)
## 类内簇函数名不变→内部互调零改动;外部名加 battle. 前缀。

var battle

func _init(b) -> void:
	battle = b

func _headless_fear_mark(o: Dictionary) -> void:               # 恐惧标记: 头顶紫骷髅高频颤抖~3秒(区别幽灵诅咒的静浮·2026-07-17)
	# 用户2026-07-17: 中招敌头顶留黑紫雾直到控制结束(~3s)才散(废颤抖骷髅标记)
	var mk := Sprite3D.new()
	mk.texture = VfxTex._make_fire_glow_tex()
	mk.billboard = BaseMaterial3D.BILLBOARD_ENABLED; mk.shaded = false; mk.transparent = true
	mk.pixel_size = (44.0 * battle.WS) / 128.0
	mk.modulate = Color(0.32, 0.1, 0.5, 0.0)
	mk.position = battle._world_pos(o["pos"], 2.1)
	battle._world.add_child(mk)
	var oref: Dictionary = o
	battle._follow_vfx.append({"spr": mk, "unit": o, "h": 2.1})        # 跟随单位(死亡自动清)
	var t = battle._reg_tween()
	t.tween_property(mk, "modulate:a", 0.85, 0.15)              # 现身
	t.tween_method(func(q: float) -> void:                      # 雾团轻缓浮动(控制期一直挂)
		if is_instance_valid(mk):
			mk.pixel_size = ((42.0 + sin(q * 6.0) * 4.0) * battle.WS) / 128.0
	, 0.0, 1.0, 2.55)
	t.tween_property(mk, "modulate:a", 0.0, 0.35)               # 控制结束->缓散
	t.tween_callback(mk.queue_free)

func _headless_tendril_shoot(center: Vector2, dir: Vector2, elev: float, length: float, big: bool, erupt_delay: float, hold_time: float) -> void:   # 万千触须·单根(用户2026-07-17"上半球三维爆发"): 从龟身球心沿三维方向(方位dir+仰角elev)伸出→抽打→缩回; 手动basis让长轴对准三维方向+面朝相机(非billboard)
	var vn: String = ["tendril-a", "tendril-b", "tendril-c"][randi() % 3]
	var tex: Texture2D = load("res://assets/sprites/vfx/%s.png" % vn)
	if tex == null or battle._cam == null: return
	var tw_px: int = maxi(1, tex.get_width())
	var th_px: int = maxi(1, tex.get_height())
	var thick: float = randf_range(88.0, 128.0) if big else randf_range(60.0, 92.0)   # 粗度×2(用户2026-07-17仅视觉)
	var ps: float = (thick * battle.WS) / float(tw_px)
	var dir3d := Vector3(dir.x * cos(elev), sin(elev), dir.y * cos(elev)).normalized()   # 三维朝向(水平dir×cos仰 + 上×sin仰)
	var start_w = battle._world_pos(center, 0.55)                             # 球心=龟身
	var full_len_w: float = length * battle.WS                                 # 触须世界长度
	var full_yscale: float = full_len_w / maxf(0.001, float(th_px) * ps)   # scale.y伸到full_len
	# 手动朝向: 局部Y(长轴/尖)对准dir3d, 面朝相机(绕长轴转到正对镜头)
	var to_cam = (battle._cam.global_position - start_w).normalized()
	var xaxis := dir3d.cross(to_cam)
	if xaxis.length() < 0.02: xaxis = dir3d.cross(Vector3.RIGHT)
	xaxis = xaxis.normalized()
	var zaxis := xaxis.cross(dir3d).normalized()
	var spk := Sprite3D.new()
	spk.texture = tex
	spk.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spk.shaded = false; spk.transparent = true
	spk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spk.offset = Vector2(0, float(th_px) * 0.5)                         # 底边=根锚在球心(从根往尖伸)
	spk.flip_h = randf() < 0.5
	spk.modulate = Color(1.5, 1.25, 1.25, 0.0)
	spk.pixel_size = ps
	spk.position = start_w
	spk.basis = Basis(xaxis, dir3d, zaxis)                             # 列: x宽/ y长轴=朝向/ z法线朝镜头
	spk.scale = Vector3(1.0, 0.01, 1.0)
	battle._world.add_child(spk)
	var st = battle._reg_tween()
	st.tween_interval(erupt_delay)
	st.tween_callback(func() -> void:                                  # 伸出瞬间根部暗红迸溅(球心)
		var rg := Sprite3D.new()
		rg.texture = VfxTex._make_fire_glow_tex()
		rg.billboard = BaseMaterial3D.BILLBOARD_ENABLED; rg.shaded = false; rg.transparent = true
		rg.pixel_size = (randf_range(14.0, 24.0) * battle.WS) / 128.0
		rg.modulate = Color(0.55, 0.12, 0.2, 0.55)
		rg.position = start_w
		battle._world.add_child(rg)
		var rt = battle._reg_tween()
		rt.tween_property(rg, "modulate:a", 0.0, 0.4)
		rt.tween_callback(rg.queue_free))
	st.tween_method(func(q: float) -> void:                            # 从球心沿三维方向伸出(scale.y生长·根不动)
		if not is_instance_valid(spk): return
		spk.scale.y = maxf(0.01, full_yscale * q)
		spk.modulate.a = clampf(q / 0.18, 0.0, 1.0)
	, 0.0, 1.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	st.tween_interval(maxf(0.1, hold_time))                            # 到位停顿抽打
	st.tween_method(func(q: float) -> void:                            # 缩回球心
		if not is_instance_valid(spk): return
		spk.scale.y = maxf(0.01, full_yscale * (1.0 - q))
		spk.modulate.a = maxf(0.0, 1.0 - q * 0.5)
	, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.tween_callback(spk.queue_free)

func _headless_reap_soul(from_pos: Vector2, u: Dictionary) -> void:   # 镰刀收割: 从命中敌扯出灵魂(紫白魂气)飞回无头龟(用户2026-07-17 F收割感)
	var soul := Sprite3D.new()
	soul.texture = load("res://assets/sprites/vfx/ghost-wisp.png")
	if soul.texture == null: soul.texture = VfxTex._make_fire_glow_tex()
	soul.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	soul.billboard = BaseMaterial3D.BILLBOARD_ENABLED; soul.shaded = false; soul.transparent = true
	soul.pixel_size = (46.0 * battle.WS) / float(maxi(1, soul.texture.get_height()))
	soul.modulate = Color(0.85, 0.7, 1.0, 0.0)
	soul.position = battle._world_pos(from_pos, 0.6)
	battle._world.add_child(soul)
	var uref: Dictionary = u
	var start: Vector2 = from_pos
	var st = battle._reg_tween()
	st.tween_property(soul, "modulate:a", 0.95, 0.1)           # 从敌身升起
	st.parallel().tween_property(soul, "position", battle._world_pos(from_pos, 1.3), 0.15)
	st.chain().tween_method(func(q: float) -> void:            # 飞回无头龟(活追踪)
		if is_instance_valid(soul) and uref.get("alive", false):
			soul.position = battle._world_pos(start.lerp(uref["pos"], q), lerpf(1.3, 0.9, q))
	, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.tween_property(soul, "modulate:a", 0.0, 0.1)
	st.tween_callback(soul.queue_free)

func _headless_drain_dot(from_pos: Vector2, u: Dictionary) -> void:   # 触须吸血: 红光珠从命中者飞回无头(22%吸血可视)
	var dot := Sprite3D.new()
	dot.texture = VfxTex._make_fire_glow_tex()
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dot.shaded = false; dot.transparent = true
	dot.pixel_size = 0.005
	dot.modulate = Color(1.0, 0.25, 0.35, 0.9)
	var start: Vector2 = from_pos + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
	dot.position = battle._world_pos(start, 0.6)
	battle._world.add_child(dot)
	var uref: Dictionary = u
	var dt = battle._reg_tween()
	dt.tween_method(func(q: float) -> void:
		if is_instance_valid(dot) and uref.get("alive", false):
			dot.position = battle._world_pos(start.lerp(uref["pos"], q), 0.6)
	, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dt.tween_property(dot, "modulate:a", 0.0, 0.1)
	dt.tween_callback(dot.queue_free)

func _headless_soul_bite(tgt: Dictionary) -> void:              # 灵魂强化命中·像素牙齿闭合(用户2026-07-17"牙齿闭合闭合时为命中"): 张口->竖压咬合(=命中帧)+白紫咬光+牙屑迸溅+轻震
	var pos: Vector2 = tgt["pos"]
	var h: float = float(tgt.get("height", 0.0)) + 0.85
	var jaw := Sprite3D.new()
	jaw.texture = load("res://assets/sprites/vfx/soul-jaw-open.png")
	jaw.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	jaw.billboard = BaseMaterial3D.BILLBOARD_ENABLED; jaw.shaded = false; jaw.transparent = true
	jaw.pixel_size = (96.0 * battle.WS) / 64.0
	jaw.modulate = Color(1, 1, 1, 0.0)
	jaw.position = battle._world_pos(pos, h)
	jaw.scale = Vector3(1.15, 1.4, 1.0)                          # 张口(竖向拉高)
	battle._world.add_child(jaw)
	var tref: Dictionary = tgt
	var bite := func() -> void:                                 # 咬合帧=命中: 换合口贴图+咬光+牙屑+火花+震
		if is_instance_valid(jaw): jaw.texture = load("res://assets/sprites/vfx/soul-jaw-closed.png")
		battle._hit_spark(tref)
		var g := Sprite3D.new()                                 # 白紫咬光
		g.texture = VfxTex._make_fire_glow_tex()
		g.billboard = BaseMaterial3D.BILLBOARD_ENABLED; g.shaded = false; g.transparent = true
		g.pixel_size = (66.0 * battle.WS) / 128.0
		g.modulate = Color(0.95, 0.85, 1.0, 0.9)
		g.position = battle._world_pos(pos, h)
		g.scale = Vector3.ONE * 0.5
		battle._world.add_child(g)
		var ggt = battle._reg_tween(); ggt.set_parallel(true)
		ggt.tween_property(g, "scale", Vector3.ONE * 1.6, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ggt.tween_property(g, "modulate:a", 0.0, 0.22)
		ggt.chain().tween_callback(g.queue_free)
		var stex := VfxTex._make_star_texture()
		for si in range(4):                                     # 牙屑迸溅(星屑代牙尖)
			var sp := Sprite3D.new()
			sp.texture = stex
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
			sp.pixel_size = 0.005
			sp.modulate = Color(0.9, 0.8, 1.0, 1.0)
			sp.position = battle._world_pos(pos, h)
			battle._world.add_child(sp)
			var sa: float = TAU * float(si) / 4.0 + 0.5
			var spt = battle._reg_tween(); spt.set_parallel(true)
			spt.tween_property(sp, "position", battle._world_pos(pos + Vector2(cos(sa), sin(sa)) * 40.0, h + randf_range(-0.2, 0.2)), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			spt.tween_property(sp, "modulate:a", 0.0, 0.3)
			spt.chain().tween_callback(sp.queue_free)
		battle._shake(0.04)
	var t = battle._reg_tween()
	t.tween_property(jaw, "modulate:a", 1.0, 0.06)              # 张口现身
	t.tween_callback(bite)
	t.tween_property(jaw, "scale", Vector3(0.95, 0.42, 1.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 竖向压扁=咬死(命中)
	t.tween_interval(0.08)
	t.tween_property(jaw, "modulate:a", 0.0, 0.13)
	t.tween_callback(jaw.queue_free)

func _headless_knock_out(o: Dictionary, dir: Vector2, dist: float) -> void:   # 镰刀击退: 从龟朝外抛飞dist码(抛物+滞空拉·空间换位先例)
	if not o.get("alive", false): return
	var from: Vector2 = o["pos"]
	var dest = Vector2(clampf(from.x + dir.x * dist, battle.ARENA.position.x, battle.ARENA.end.x), clampf(from.y + dir.y * dist, battle.ARENA.position.y, battle.ARENA.end.y))
	var oref: Dictionary = o
	if not o.get("airborne", false) and not o.get("_knock_immune", false):   # 免击飞(017不沉之锚): 直接设airborne会绕过_knockback的守卫(用户2026-07-19"修吧")
		o["airborne"] = true; o["vy"] = 6.0; o["vx"] = 0.0; o["vz"] = 0.0   # 竖直起跳~0.55s
	var mt = battle._reg_tween()
	mt.tween_method(func(q: float) -> void:
		if oref.get("alive", false) and oref.get("airborne", false): oref["pos"] = from.lerp(dest, q)
	, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _headless_scythe_telegraph(center: Vector2, aim: Vector2, dur: float) -> void:   # 镰刀预警扇形(Camille W式): 100度锥填充+外缘半环高亮(300码/0.25s)
	var half := deg_to_rad(50.0)
	var cone := Sprite3D.new()                                 # 实心扇形填充(Camille W式·apex在龟身)
	cone.texture = VfxTex._make_cone_tex()
	cone.billboard = BaseMaterial3D.BILLBOARD_DISABLED; cone.axis = Vector3.AXIS_Y
	cone.shaded = false; cone.transparent = true
	cone.modulate = Color(0.62, 0.35, 1.0, 0.0)
	cone.pixel_size = (300.0 * battle.WS) / 128.0                     # apex在贴图中心→半径=c(128px)映射300码
	cone.rotation.y = -atan2(aim.y, aim.x) - PI * 0.5          # 扇形朝上→转到aim方向
	cone.position = battle._world_pos(center, 0.055)
	battle._world.add_child(cone)
	var cnt = battle._reg_tween()
	cnt.tween_property(cone, "modulate:a", 0.9, 0.1)
	cnt.tween_interval(maxf(0.02, dur - 0.2))
	cnt.tween_property(cone, "modulate:a", 0.0, 0.12)
	cnt.tween_callback(cone.queue_free)
	for sgn in [-1.0, 1.0]:                                     # 2道边缘亮线(锥界)
		var d2 := aim.rotated(half * sgn)
		battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", center, center + d2 * 300.0, 26.0, Color(0.85, 0.55, 1.0, 0.98), dur, 0.07)
	var glow := VfxTex._make_fire_glow_tex()
	for i2 in range(19):                                        # 外缘弧线(300码/外圈加成感·连密)
		var a3: float = -half + 2.0 * half * float(i2) / 18.0
		var pd := center + aim.rotated(a3) * 300.0
		var dot := Sprite3D.new()
		dot.texture = glow
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dot.shaded = false; dot.transparent = true
		dot.pixel_size = 0.012
		dot.modulate = Color(0.95, 0.7, 1.0, 1.0)
		dot.position = battle._world_pos(pd, 0.2)
		battle._world.add_child(dot)
		var dt = battle._reg_tween()
		dt.tween_interval(dur)
		dt.tween_property(dot, "modulate:a", 0.0, 0.12)
		dt.tween_callback(dot.queue_free)

func _headless_scythe(u: Dictionary) -> void:                  # 镰刀横扫(Camille W式/用户2026-07-17): 撤紫焰+恢复射程->蓄力0.35s->预警扇形0.25s->镰刀扫过+结算(100度300码敌击退300从龟朝外+幽灵诅咒5s)->解锁龟能
	var uu: Dictionary = u
	var sspr = u.get("_soul_spr", null)                        # 撤紫焰tell
	if sspr is Sprite3D and is_instance_valid(sspr): (sspr as Sprite3D).queue_free()
	u["_soul_spr"] = null
	u["headless_soul_stacks"] = 0
	u["atk_range"] = float(u.get("headless_soul_base_range", 100.0))   # 恢复基础射程(强化窗口结束)
	var tgt = battle._nearest_enemy(u)
	var aim: Vector2 = ((tgt["pos"] - u["pos"]) as Vector2).normalized() if tgt != null else (Vector2.RIGHT if u.get("face_right", true) else Vector2.LEFT)
	if aim.length() < 0.5: aim = Vector2.RIGHT
	u["_scythe_aim"] = aim
	u["_slam"] = true                                          # 蓄力期定身(举镰)
	var raise := Sprite3D.new()                                # 蓄力: 头顶镰刀抬起+紫光聚
	raise.texture = load("res://assets/sprites/vfx/soul-scythe.png")
	raise.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	raise.billboard = BaseMaterial3D.BILLBOARD_ENABLED; raise.shaded = false; raise.transparent = true
	raise.pixel_size = (150.0 * battle.WS) / 96.0
	raise.modulate = Color(1, 1, 1, 0.0)
	raise.position = battle._world_pos(u["pos"], 1.6)
	battle._world.add_child(raise)
	var rt = battle._reg_tween()
	raise.pixel_size = (240.0 * battle.WS) / 96.0   # 蓄力镰刀也加大
	rt.tween_property(raise, "modulate:a", 1.0, 0.3)
	rt.tween_property(raise, "position", battle._world_pos(u["pos"], 2.5), 0.35)   # 举起蓄力(放慢)
	rt.tween_interval(0.4)
	rt.tween_property(raise, "modulate:a", 0.0, 0.15)
	rt.tween_callback(raise.queue_free)
	battle._pending_shots.append({"delay": 0.55, "fn": func():        # 蓄力后->预警扇形(节奏放慢)
		if uu.get("alive", false): _headless_scythe_telegraph(uu["pos"], uu.get("_scythe_aim", Vector2.RIGHT), 0.5), "src": u})
	battle._pending_shots.append({"delay": 1.05, "fn": func():        # 预警后->镰刀扫过+结算(节奏放慢·蓄力0.55+预警0.5)
		var aim2: Vector2 = uu.get("_scythe_aim", Vector2.RIGHT)
		uu["_slam"] = false                                    # 解定身
		uu["energy_lock_until"] = battle._t                           # 解锁龟能(清零重充)
		if not uu.get("alive", false): return
		_headless_scythe_sweep(uu["pos"], aim2)
		battle._shake(0.13); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
		var half2 := deg_to_rad(50.0)
		for o in battle._enemies_of(uu):
			if not o.get("alive", false): continue
			var to: Vector2 = (o["pos"] as Vector2) - (uu["pos"] as Vector2)
			if to.length() > 300.0: continue
			if to.length() < 1.0: continue
			if absf(aim2.angle_to(to.normalized())) > half2: continue   # 100度锥(半角50度)
			battle._hit_spark(o)
			if not o.get("_eggImmune", false):
				_headless_knock_out(o, to.normalized(), 300.0)     # 击退300码从龟朝外
				battle._add_dot(o, "curse", (o["maxHp"] as float) * 0.05, 5.0, uu)   # 幽灵式诅咒5秒(每秒5%maxHp真伤)
				_headless_fear_mark(o)                             # 紫标记示意中咒
				_headless_reap_soul(o["pos"], uu)                  # 收割感: 从敌身扯灵魂飞回无头龟(用户2026-07-17 F)
	, "src": u})

func _headless_scythe_sweep(center: Vector2, aim: Vector2) -> void:   # 镰刀横扫·柄尾钉龟身+刀身billboard绕柄尾转100度(用户2026-07-17终版·Camille W): rotation.z跟随投影后的场内径向→刀锋始终咬合地面扇形当前扫向(非平面乱转)→贴地宽亮刀光累积铺满100度footprint(等距主角)→收势整片白闪+顿帧震
	if battle._cam == null: return
	var half := deg_to_rad(50.0)
	var a0 := -deg_to_rad(60.0)                                # 起手刀锋后引(蓄势超-50度)
	var a1 := half                                            # 收势到+50度
	var grip = battle._world_pos(center, 0.5)                        # 柄尾支点=龟握持点(全程钉死)
	var blade_len := 250.0                                     # 镰刀视觉长度(billboard高·大而醒目)
	var tex: Texture2D = load("res://assets/sprites/vfx/soul-scythe-2.png")
	if tex == null: tex = load("res://assets/sprites/vfx/soul-scythe.png")
	var th_px: int = maxi(1, (tex as Texture2D).get_height())
	var ps: float = (blade_len * battle.WS) / float(th_px)
	# —— 地面扇形footprint(等距主角·随扫渐亮=扫过区被点亮) ——
	var cone := Sprite3D.new()
	cone.texture = VfxTex._make_cone_tex()
	cone.billboard = BaseMaterial3D.BILLBOARD_DISABLED; cone.axis = Vector3.AXIS_Y
	cone.shaded = false; cone.transparent = true
	cone.modulate = Color(0.7, 0.4, 1.1, 0.0)
	cone.pixel_size = (300.0 * battle.WS) / 128.0
	cone.rotation.y = -atan2(aim.y, aim.x) - PI * 0.5
	cone.position = battle._world_pos(center, 0.05)
	cone.no_depth_test = true; cone.render_priority = 16
	battle._world.add_child(cone)
	# —— 镰刀本体(billboard·柄尾锚origin·rotation.z绕柄尾扫) ——
	var scythe := Sprite3D.new()
	scythe.texture = tex
	scythe.billboard = BaseMaterial3D.BILLBOARD_DISABLED     # 手动basis控朝向(billboard会吞node旋转→刀不转)
	scythe.shaded = false; scythe.transparent = true
	scythe.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	scythe.offset = Vector2(0, float(th_px) * 0.5)           # 底边(柄尾)锚在origin→绕柄尾转
	scythe.no_depth_test = true; scythe.render_priority = 44
	scythe.modulate = Color(1.1, 0.95, 1.35, 0.0)
	scythe.pixel_size = ps
	scythe.position = grip
	battle._scythe_face_screen(scythe, center, aim, a0)            # 现身于后引角(蓄势)
	battle._world.add_child(scythe)
	var trailtex: Texture2D = load("res://assets/sprites/vfx/fx-trail.png")
	var etw: int = maxi(1, (trailtex as Texture2D).get_width()) if trailtex != null else 1
	var eth: int = maxi(1, (trailtex as Texture2D).get_height()) if trailtex != null else 1
	var mt = battle._reg_tween(); mt.set_parallel(true)
	mt.tween_property(scythe, "modulate:a", 1.0, 0.05)      # 刀身蓄势现身
	mt.tween_property(cone, "modulate:a", 0.22, 0.06)       # 扇形起底(预示扫向)
	# 挥砍: θ从a0快挥到a1(0.16s·慢起加速)·每帧billboard旋转+贴地宽亮刀光累积铺满扇形(footprint为主角)
	var swt = battle._reg_tween()
	swt.tween_method(func(q: float) -> void:
		if not is_instance_valid(scythe): return
		var theta: float = lerpf(a0, a1, q)
		battle._scythe_face_screen(scythe, center, aim, theta)
		if is_instance_valid(cone): cone.modulate.a = 0.22 + 0.5 * clampf((theta + half) / (2.0 * half), 0.0, 1.0)   # 扫过区渐亮
		if trailtex == null or theta < -half: return
		var d := aim.rotated(clampf(theta, -half, half))    # 贴地宽亮径向刀光(扫过处刷亮·累积成footprint)
		var edge := Sprite3D.new()
		edge.texture = trailtex
		edge.billboard = BaseMaterial3D.BILLBOARD_DISABLED; edge.axis = Vector3.AXIS_Y
		edge.shaded = false; edge.transparent = true
		var eps: float = (78.0 * battle.WS) / float(eth)           # 加宽(份量)
		edge.pixel_size = eps
		edge.modulate = Color(0.95, 0.72, 1.35, 0.82)       # 紫白刀光(非死白·刀身可读)
		edge.rotation.y = -atan2(d.y, d.x)
		edge.scale = Vector3((300.0 * battle.WS) / maxf(0.001, float(etw) * eps), 1.0, 1.0)
		edge.position = battle._world_pos(center + d * 150.0, 0.07)
		edge.no_depth_test = true; edge.render_priority = 24
		battle._world.add_child(edge)
		var et = battle._reg_tween()
		et.tween_interval(0.16)
		et.tween_property(edge, "modulate:a", 0.0, 0.36)
		et.tween_callback(edge.queue_free)
	, 0.0, 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)   # 慢起→加速(份量)
	swt.tween_callback(func() -> void:                        # 收势落地: 扇形整片白闪+顿帧震(收割定格)
		battle._scythe_face_screen(scythe, center, aim, a1)
		battle._shake(0.22); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
		if is_instance_valid(cone):
			var flt = battle._reg_tween()
			flt.tween_property(cone, "modulate", Color(0.95, 0.82, 1.3, 0.8), 0.04)   # 落地整片紫白闪(收割定格)
			flt.tween_property(cone, "modulate:a", 0.0, 0.34)
			flt.tween_callback(cone.queue_free))
	swt.tween_interval(0.1)                                   # 顿(收割定格·脆)
	swt.tween_property(scythe, "modulate:a", 0.0, 0.2)      # 镰刀化紫气消散(有去处)
	swt.tween_callback(scythe.queue_free)

func _headless_undead_vfx(u: Dictionary) -> void:               # 亡灵免死: 金白爆闪+紫焰冲柱+顿帧强调+金环跟随5秒(2026-07-17整改: 触发更醒目)
	battle._shake(0.14); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)             # 濒死不死=大事件: 顿帧+震
	var glow := VfxTex._make_fire_glow_tex()
	for ci in range(3):                                         # 亡灵紫焰冲柱(从脚下窜起·不屈)
		var col := Sprite3D.new()
		col.texture = glow
		col.billboard = BaseMaterial3D.BILLBOARD_ENABLED; col.shaded = false; col.transparent = true
		col.pixel_size = (float(70 - ci * 14) * battle.WS) / 128.0
		col.modulate = Color(0.7, 0.35, 1.0, 0.0)
		col.position = battle._world_pos(u["pos"], 0.4 + 0.55 * float(ci))
		battle._world.add_child(col)
		var cot = battle._reg_tween()
		cot.tween_property(col, "modulate:a", 0.85, 0.1).set_delay(0.05 * float(ci))
		cot.tween_interval(0.2)
		cot.tween_property(col, "modulate:a", 0.0, 0.35)
		cot.tween_callback(col.queue_free)
	var fb := Sprite3D.new()                                     # 触发瞬间金白闪
	fb.texture = glow
	fb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fb.shaded = false; fb.transparent = true
	fb.pixel_size = (110.0 * battle.WS) / 128.0
	fb.modulate = Color(1.0, 0.92, 0.6, 0.95)
	fb.position = battle._world_pos(u["pos"], 0.8)
	fb.scale = Vector3.ONE * 0.4
	battle._world.add_child(fb)
	var ft = battle._reg_tween(); ft.set_parallel(true)
	ft.tween_property(fb, "scale", Vector3.ONE * 1.6, 0.3)
	ft.tween_property(fb, "modulate:a", 0.0, 0.3)
	ft.chain().tween_callback(fb.queue_free)
	var ring := Sprite3D.new()                                   # 金环贴地跟随5秒(不死窗口可视)
	ring.texture = VfxTex._make_thin_ring_tex()
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ring.axis = Vector3.AXIS_Y
	ring.shaded = false; ring.transparent = true
	ring.modulate = Color(1.0, 0.85, 0.4, 0.9)
	ring.pixel_size = (110.0 * battle.WS) / 256.0
	ring.position = battle._world_pos(u["pos"], 0.065)
	battle._world.add_child(ring)
	battle._follow_vfx.append({"spr": ring, "unit": u, "h": 0.065})
	var rt = battle._reg_tween()
	for i in range(4):                                           # 呼吸4轮≈4.4s
		rt.tween_property(ring, "modulate:a", 0.45, 0.55)
		rt.tween_property(ring, "modulate:a", 0.9, 0.55)
	rt.tween_property(ring, "modulate:a", 0.0, 0.5)              # 第5秒渐隐(不瞬删)
	rt.tween_callback(ring.queue_free)
