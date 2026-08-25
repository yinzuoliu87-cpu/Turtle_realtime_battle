class_name HeadlessSystem
extends RefCounted
## 无头骑士·恐惧/镰刀/触须系统(从主场景抽出)
## 类内簇函数名不变→内部互调零改动;外部名加 battle. 前缀。

## 【灵魂打击】龟能充满后接下来 N 次普攻强化, 第 N 下落地挥镰刀。
## 【亡灵(被动)】登场自带生命偷取 + 越残血攻击越高 + 首次濒死免死一段时间。
## ★三处分别在: battle_spawn(生命偷取) / 主场景 _tick_unit(残血增攻) / battle_damage(免死)。
const UNDEAD_LIFESTEAL := 0.22   # 登场即获得的生命偷取
const UNDEAD_ATK_PER_LOST := 1.0 # 每损失 1 份生命 → 攻击力 +1 份(1:1)
const UNDEAD_DEATHFLOOR := 5.0   # 首次濒死后免死多少秒(期间生命不会降到 1 以下)
## ★"最高 +100%" **不是另一个常量** —— 它是 `clampf(lost_pct, 0, 1)` 的结构性上限
##   (最多只能损失 100% 生命)。文案里那个 100% 指向 UNDEAD_ATK_PER_LOST 的百分比形式。
## 【灵魂打击】龟能消耗与「攒满要多久」。★后者是**推导**: 龟能 × 全局充能系数。
##   SkillEnergy 没有 class_name(防 F5 未声明崩), 所以 preload 它再引用。
const _SE := preload("res://scripts/systems/skill_energy.gd")
const SOUL_ENERGY := 80.0        # 龟能消耗(真值由 SkillEnergy.SKILL_COST 反过来引用本常量)
const SOUL_FULL_SEC := SOUL_ENERGY * _SE.CD_FACTOR   # 推导: 攒满约几秒(文案里那个 ≈6)
const SOUL_HITS := 3             # 强化几次普攻
const SOUL_ATK_COEF := 0.5       # 每次额外 ×ATK 魔法
const SOUL_CURHP_PCT := 0.10     # 每次额外 + 目标【当前】生命 × 魔法
const SOUL_RANGE_BONUS := 60.0   # 强化窗口期间射程 +
const SCYTHE_ARC_DEG := 100.0    # 镰刀横扫: 正面锥角(半角 50°)
const SCYTHE_RANGE := 300.0      # 镰刀横扫: 半径(码)
const SCYTHE_KNOCK := 300.0      # 镰刀横扫: 击退(码·从龟朝外)
## 【恐吓】咆哮范围。★三处共用(粒子铺满 / 扩散延迟归一 / 判定), 抽一个。
const FEAR_RADIUS := 200.0       # 恐吓半径(码)
const SCYTHE_CURSE_SEC := 3.0    # 镰刀横扫: 诅咒秒数(每秒 5% 目标最大生命 真伤)

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
		battle._vfx._hit_spark(tref)
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

func _headless_scythe_telegraph(center: Vector2, aim: Vector2, dur: float) -> void:   # 镰刀预警扇形(Camille W式): 100度锥填充+外缘半环高亮(300码·时长由 dur 参数给, 唯一调用方 _headless_scythe 传 0.5s)
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

func _headless_scythe(u: Dictionary) -> void:                  # 镰刀横扫(Camille W式/用户2026-07-17): 撤紫焰+恢复射程->蓄力0.55s->预警扇形0.5s->镰刀扫过+结算(100度300码敌击退300从龟朝外+幽灵诅咒3s·用户2026-07-30 第六轮 5→3)->解锁龟能
	var uu: Dictionary = u
	var sspr = u.get("_soul_spr", null)                        # 撤紫焰tell
	if sspr is Sprite3D and is_instance_valid(sspr): (sspr as Sprite3D).queue_free()
	u["_soul_spr"] = null
	u["headless_soul_stacks"] = 0
	u["atk_range"] = float(u.get("headless_soul_base_range", 100.0))   # 恢复基础射程(强化窗口结束)
	var tgt = battle._targeting._nearest_enemy(u)
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
		var half2 := deg_to_rad(SCYTHE_ARC_DEG * 0.5)
		for o in battle._targeting._enemies_of(uu):
			if not o.get("alive", false): continue
			var to: Vector2 = (o["pos"] as Vector2) - (uu["pos"] as Vector2)
			if to.length() > SCYTHE_RANGE: continue
			if to.length() < 1.0: continue
			if absf(aim2.angle_to(to.normalized())) > half2: continue   # 100度锥(半角50度)
			battle._vfx._hit_spark(o)
			if not o.get("_eggImmune", false):
				_headless_knock_out(o, to.normalized(), SCYTHE_KNOCK)     # 击退300码从龟朝外
				battle._damage._add_curse(o, SCYTHE_CURSE_SEC, uu)   # 幽灵式诅咒3秒(5→3·用户2026-07-30 第六轮·总量 288→173)
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

func _sk_headless_fear(u: Dictionary, _tgt = null) -> void:      # 无头·恐吓(封板·110龟能): 半径200码内所有敌 定身+缴械+锁技3秒(蛋免控·无伤害); 2026-07-17演出: 咆哮紫黑气爆+三道恐惧波纹+紫雾盘+颤抖恐惧标记(删技能名飘字=UI规矩)
	var cx: Vector2 = u["pos"]
	var burst = Sprite3D.new()                                  # 咆哮: 自身紫黑气爆
	burst.texture = VfxTex._make_fire_glow_tex()
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED; burst.shaded = false; burst.transparent = true
	burst.pixel_size = (120.0 * battle.WS) / 128.0
	burst.modulate = Color(0.55, 0.15, 0.7, 0.9)
	burst.position = battle._world_pos(cx, 0.8)
	burst.scale = Vector3.ONE * 0.4
	battle._world.add_child(burst)
	var bt = battle._reg_tween(); bt.set_parallel(true)
	bt.tween_property(burst, "scale", Vector3.ONE * 1.6, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(burst, "modulate:a", 0.0, 0.3)
	bt.chain().tween_callback(burst.queue_free)
	battle._shake(0.06)
	for wi in range(3):                                          # 三道恐惧波纹先后扩到200码(半径)
		var wv = Sprite3D.new()
		wv.texture = VfxTex._make_thin_ring_tex()
		wv.billboard = BaseMaterial3D.BILLBOARD_DISABLED; wv.axis = Vector3.AXIS_Y
		wv.shaded = false; wv.transparent = true
		wv.modulate = Color(0.7, 0.3, 0.9, 0.85)
		wv.pixel_size = (20.0 * battle.WS) / 256.0
		wv.position = battle._world_pos(cx, 0.065)
		battle._world.add_child(wv)
		var wt = battle._reg_tween()
		wt.tween_interval(0.09 * float(wi))
		wt.tween_method(func(q: float) -> void:
			if is_instance_valid(wv):
				wv.pixel_size = (maxf(20.0, 400.0 * q) * battle.WS) / 256.0
				wv.modulate.a = 0.85 * (1.0 - q * 0.7)
		, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		wt.tween_property(wv, "modulate:a", 0.0, 0.15)
		wt.tween_callback(wv.queue_free)
	# 用户2026-07-17: 黑紫雾团从中心爆开铺满整个200码范围->缓慢消散(废原小紫雾盘·改分布式雾团铺满)
	var mtex = VfxTex._make_fire_glow_tex()
	var core = Sprite3D.new()                                  # 中心黑核浓雾(体内涌出)
	core.texture = mtex
	core.billboard = BaseMaterial3D.BILLBOARD_ENABLED; core.shaded = false; core.transparent = true
	core.pixel_size = (140.0 * battle.WS) / 128.0
	core.modulate = Color(0.08, 0.03, 0.14, 0.0)
	core.position = battle._world_pos(cx, 0.8)
	core.scale = Vector3.ONE * 0.3
	battle._world.add_child(core)
	var cot = battle._reg_tween(); cot.set_parallel(true)
	cot.tween_property(core, "scale", Vector3.ONE * 2.8, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cot.tween_property(core, "modulate:a", 0.98, 0.18)
	cot.chain().tween_interval(1.8)
	cot.chain().tween_property(core, "modulate:a", 0.0, 1.4)
	cot.chain().tween_callback(core.queue_free)
	for pi in range(42):                                        # 42团黑紫雾铺满200码半径(加密加浓·用户2026-07-17"黑雾不够密集不够明显")
		var pa: float = randf() * TAU
		var pr: float = FEAR_RADIUS * sqrt(randf())                   # sqrt=均匀铺满圆盘
		var pp = cx + Vector2(cos(pa), sin(pa)) * pr
		var puff = Sprite3D.new()
		puff.texture = mtex
		puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED; puff.shaded = false; puff.transparent = true
		var pcol: Color = [Color(0.16, 0.06, 0.24), Color(0.3, 0.1, 0.45), Color(0.42, 0.18, 0.6)][pi % 3]
		puff.modulate = Color(pcol.r, pcol.g, pcol.b, 0.0)
		puff.position = battle._world_pos(pp, randf_range(0.4, 1.0))
		puff.scale = Vector3.ONE * 0.3
		battle._world.add_child(puff)
		var psz: float = randf_range(95.0, 155.0)   # 加大
		puff.pixel_size = (psz * battle.WS) / 128.0
		var dly: float = 0.02 + 0.28 * clampf(pr / FEAR_RADIUS, 0.0, 1.0)   # 由近及远扩散(爆开铺满感)
		var ppt = battle._reg_tween()
		ppt.tween_interval(dly)
		ppt.tween_property(puff, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ppt.parallel().tween_property(puff, "modulate:a", randf_range(0.75, 0.95), 0.28)   # 更浓
		ppt.chain().tween_interval(1.3)
		ppt.chain().tween_property(puff, "modulate:a", 0.0, randf_range(1.0, 1.6))   # 缓慢消散(错峰)
		ppt.tween_callback(puff.queue_free)
	# 贴地黑紫雾盘(范围可视200码)缓散
	var pool = battle._px_ground_sprite(mtex, cx, 400.0, Color(0.28, 0.07, 0.42, 0.6), 0.06)   # 贴地雾盘更浓
	var pt = battle._reg_tween()
	pt.tween_interval(1.8)
	pt.tween_property(pool, "modulate:a", 0.0, 1.4)
	pt.tween_callback(pool.queue_free)
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(cx) > FEAR_RADIUS: continue
		if o.get("_eggImmune", false): continue
		battle._damage._stun(o, 3.0, "_sk_headless_fear")
		_headless_fear_mark(o)

## ★★2026-08-22 文案根除: 万千触须这一组原来全是函数体里的裸字面量。
const TENDRIL_RADIUS := 1500.0    # 无差别命中半径(码)
const TENDRIL_LIFESTEAL := 0.22   # 本次施法额外 + 生命偷取
const TENDRIL_PASS_SEC := 0.3     # 伸出/穿过 在施法后第几秒
const TENDRIL_DETACH_SEC := 3.0   # 收回/脱离 在施法后第几秒
const TENDRIL_SELF_STUN := 4.0    # 自身硬控全程(秒)
const TENDRIL_PASS_FOE := 1.0     # 穿过时 对敌 ×ATK
const TENDRIL_PASS_ALLY := 0.5    # 穿过时 对友 ×ATK
const TENDRIL_DETACH_FOE := 1.5   # 收回时 对敌 ×ATK
const TENDRIL_DETACH_ALLY := 0.5  # 收回时 对友 ×ATK

func _sk_headless_tendrils(u: Dictionary, _tgt = null) -> void:  # 无头·万千触须(封板·160龟能·虐杀原形毁灭者Q1): 1500码内无差别触须(用户2026-07-19; 原为全场)·伸0.3s→停→收3.0s·自身硬控·+22%吸血; 2026-07-17演出: 起手紫黑气爆+裂纹环→100根触须朝上半球随机方向爆出布满全场(Q9"特效得布满")波前由近及远爆出→痉挛定格→3.0s撕扯缩回+吸血红珠回流
	battle._damage._stun(u, TENDRIL_SELF_STUN, "_sk_headless_tendrils", true)   # 自身硬控全程(施法动作·亡灵拉全场自己也搭进去)
	var center: Vector2 = u["pos"]
	var uu: Dictionary = u
	# 用户2026-07-17: 中心一个病毒状黑色球体随触须爆发脉动(变大变小)
	var virus = Sprite3D.new()
	virus.texture = load("res://assets/sprites/vfx/fx-black-hole.png")
	virus.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	virus.billboard = BaseMaterial3D.BILLBOARD_ENABLED; virus.shaded = false; virus.transparent = true
	virus.pixel_size = (120.0 * battle.WS) / float(maxi(1, virus.texture.get_height()))
	virus.modulate = Color(0.12, 0.05, 0.16, 0.0)               # 黑紫病毒球
	virus.position = battle._world_pos(center, 0.75)
	virus.scale = Vector3.ONE * 0.2
	battle._world.add_child(virus)
	battle._follow_vfx.append({"spr": virus, "unit": u, "h": 0.75})    # 跟随龟身(死亡自动清)
	var vgt = battle._reg_tween()
	vgt.tween_property(virus, "modulate:a", 0.95, 0.15)         # 涌出
	vgt.parallel().tween_property(virus, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var vpt = battle._reg_tween()                                     # 脉动(变大变小·病毒感)3s
	vpt.tween_method(func(q: float) -> void:
		if is_instance_valid(virus):
			var puls: float = 1.0 + sin(q * TAU * 5.0) * 0.28   # 5次脉动
			virus.scale = Vector3.ONE * puls
			virus.rotation.y = q * TAU * 0.6                    # 缓转(蠕动感)
	, 0.0, 1.0, 3.0)
	vpt.tween_property(virus, "scale", Vector3.ONE * 0.1, 0.35)   # 收缩没入体内
	vpt.parallel().tween_property(virus, "modulate:a", 0.0, 0.35)
	vpt.chain().tween_callback(virus.queue_free)
	var burst = Sprite3D.new()                                  # 起手: 紫黑气爆+震屏顿帧+地面裂纹环
	burst.texture = VfxTex._make_fire_glow_tex()
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED; burst.shaded = false; burst.transparent = true
	burst.pixel_size = (200.0 * battle.WS) / 128.0
	burst.modulate = Color(0.6, 0.08, 0.3, 0.98)   # 起手体内生物质暗红爆(2026-07-17)
	burst.position = battle._world_pos(center, 0.8)
	burst.scale = Vector3.ONE * 0.3
	battle._world.add_child(burst)
	var bt = battle._reg_tween(); bt.set_parallel(true)
	bt.tween_property(burst, "scale", Vector3.ONE * 2.4, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(burst, "modulate:a", 0.0, 0.28)
	bt.chain().tween_callback(burst.queue_free)
	battle._shake(0.1)
	battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
	var crack = battle._px_ground_sprite(VfxTex._make_pixel_ring_tex(), center, 60.0, Color(0.6, 0.2, 0.75, 0.8), 0.06)
	var ct = battle._reg_tween()
	ct.tween_method(func(q: float) -> void:
		if is_instance_valid(crack): crack.pixel_size = (maxf(60.0, 500.0 * q) * battle.WS) / 48.0
	, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ct.tween_property(crack, "modulate:a", 0.0, 0.3)
	ct.tween_callback(crack.queue_free)
	# 触须从龟身球心朝【上半球任意三维方向】爆发(用户2026-07-17"想象球体只留上半球·朝上半球任意方向射"·虐杀原形2)
	for ti in range(100):                                       # 100根: 方位角0-360×仰角(偏低角·上半球)
		var az: float = randf() * TAU                            # 方位角
		var od = Vector2(cos(az), sin(az))
		var e01: float = randf(); e01 = e01 * e01                # 平方偏低→更多触须近平射(用户2026-07-17"更多低角度")
		var elev: float = deg_to_rad(4.0 + 82.0 * e01)           # 仰角: 大量近平射→少数冲天
		var L: float = randf_range(340.0, 860.0) * 1.2 * (1.0 - 0.25 * e01)   # 长度: 低角度更长+20%(用户2026-07-17仅视觉·布满竞技场)
		var dly: float = randf_range(0.0, 0.14)                  # 错峰爆出(炸开感)
		_headless_tendril_shoot(center, od, elev, L, randf() < 0.4, dly, randf_range(2.0, 2.4))
	var pass_fn = func():                                      # 伸/穿过(≈0.3s铺满): 无差别 敌1A+眩晕 / 友0.5A+眩晕(刷新不叠)
		for o in battle._units:
			if not o.get("alive", false) or is_same(o, uu): continue
			if (o["pos"] as Vector2).distance_to(center) > TENDRIL_RADIUS: continue   # 射程1500码(用户2026-07-19; 原为全场无差别)
			var sc: float = TENDRIL_PASS_FOE if battle._is_hostile(uu, o) else TENDRIL_PASS_ALLY
			battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, sc, o), Color("#9b3bff"), TENDRIL_LIFESTEAL)
			if not o.get("_eggImmune", false):
				battle._damage._stun(o, 2.7, "_sk_headless_tendrils", true)   # 眩晕持续到脱离
				o["_tendril_stun"] = true
			_headless_tendril_shoot(center, ((o["pos"] as Vector2) - center).normalized() if ((o["pos"] as Vector2) - center).length() > 1.0 else Vector2.RIGHT, deg_to_rad(18.0), maxf(90.0, (o["pos"] as Vector2).distance_to(center)), true, 0.0, 2.4)   # 命中者: 从龟身甩一根粗触须缠住
			if battle._is_hostile(uu, o): _headless_drain_dot(o["pos"], uu)   # 吸血红珠回流
	battle._pending_shots.append({"delay": TENDRIL_PASS_SEC, "fn": pass_fn, "src": u})
	var detach_fn = func():                                    # 收/脱离(≈3.0s): 无差别 敌1.5A / 友0.5A + 回复行动(解眩晕)
		battle._shake(0.12)
		for o in battle._units:
			if not o.get("alive", false) or is_same(o, uu): continue
			if (o["pos"] as Vector2).distance_to(center) > TENDRIL_RADIUS: continue   # 射程1500码(用户2026-07-19; 原为全场无差别)
			var sc: float = TENDRIL_DETACH_FOE if battle._is_hostile(uu, o) else TENDRIL_DETACH_ALLY
			battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, sc, o), Color("#ff3b6b"), TENDRIL_LIFESTEAL)
			battle._vfx._hit_spark(o)
			if o.get("_tendril_stun", false):
				o["_tendril_stun"] = false
				o["stun_until"] = battle._t   # 解眩晕→回复行动
			if battle._is_hostile(uu, o): _headless_drain_dot(o["pos"], uu)   # 脱离撕扯再吸一口
	battle._pending_shots.append({"delay": TENDRIL_DETACH_SEC, "fn": detach_fn, "src": u})

func _sk_headless_soul_charge(u: Dictionary) -> void:           # 无头·灵魂打击(机制大改·用户2026-07-17拍板·80龟能): 触发→下3次攻击强化(射程+60·各额外0.5A+10%当前HP魔法·牙齿闭合)→第3下落地蓄力→镰刀横扫(100°300码击退300+幽灵诅咒3s·Camille W); 全程锁龟能, 扫完解锁清零重充
	u["headless_soul_stacks"] = SOUL_HITS
	u["headless_soul_base_range"] = float(u.get("atk_range", 100.0))
	u["atk_range"] = float(u["headless_soul_base_range"]) + SOUL_RANGE_BONUS   # 强化窗口+60射程(用户"60+基础射程")
	u["energy_lock_until"] = battle._t + 999.0                            # 锁龟能条到镰刀扫完(_headless_scythe置回_t)
	var old = u.get("_soul_spr", null)
	if old is Sprite3D and is_instance_valid(old): (old as Sprite3D).queue_free()
	var fl = Sprite3D.new()                                     # 紫焰绕颈tell(循环·3次+镰刀全程亮·bind_node防泄漏)
	fl.texture = VfxTex._make_fire_glow_tex()
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fl.shaded = false; fl.transparent = true
	fl.pixel_size = (34.0 * battle.WS) / 128.0
	fl.modulate = Color(0.75, 0.3, 1.0, 0.9)
	fl.position = battle._world_pos(u["pos"], 1.5)
	battle._world.add_child(fl)
	u["_soul_spr"] = fl
	var uref: Dictionary = u
	var lt = battle.create_tween().set_loops()
	lt.bind_node(fl)
	lt.tween_method(func(q: float) -> void:
		if not is_instance_valid(fl): return
		if uref.get("alive", false):
			var aa: float = q * TAU
			fl.position = battle._world_pos((uref["pos"] as Vector2) + Vector2(cos(aa), sin(aa)) * 26.0, 1.5 + sin(aa * 2.0) * 0.12)
	, 0.0, 1.0, 0.9)
	battle._skill_ring(u["pos"], Color(0.6, 0.23, 0.7, 0.5), 44.0)
	battle._pending_shots.append({"delay": 7.0, "fn": func():            # 兜底: 7秒内没打完3下(无敌/被控)→强制镰刀收尾防永锁龟能
		if int(uref.get("headless_soul_stacks", 0)) > 0: _headless_scythe(uref), "src": u})

