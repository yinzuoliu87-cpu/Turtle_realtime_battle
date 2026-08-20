class_name StarSystem
extends RefCounted
## 星龟·引力/星浪/虫洞技能系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调。
## 类内 _sk_star_* 名字不变;外部名加 battle. 前缀。无状态成员。

var battle

func _init(b) -> void:
	battle = b

## 虫洞锁龟能的兜底时长(秒)。虫洞正常会在爆炸那一刻主动解锁; 这个数只是
## "万一虫洞被换路/死亡等路径提前销毁"时的保险丝 —— 宁可早解锁也不能永久锁死。
## ★地图对角线约 2600 码 ÷ 140 码/s ≈ 19 秒, 取 25 秒留余量。
const WORMHOLE_LOCK_FALLBACK := 25.0


func _sk_star_gravity_warp(u: Dictionary) -> void:             # 星际龟·扭曲空间「奇点」(封板数值不动: 普通=敌阵中心500码全体0.8A魔法; 强化星能满=+过中心镜像换位(落点=center*2-pos, 钳进 ARENA)+清空星能; 120龟能)
	# 演出重设计照发条R官方逐帧(C:/tmp/ori_burst: b13施放三件套/b13-b24吸入0.37s/b25-27屏息/b28爆发帧/b29-b34拉拽0.2s)·星际×2放慢换算
	# 用户2026-07-16批准: 伤害挪到爆发帧结算+施法锁(技2先例); 同日整改: ①普通版施法可积攒星能·强化版才锁星能 ②强化换位=重力抛物线甩飞过中心点落对端·落地即恢复行动("延中心点到对端") ③特效范围=伤害范围500码对齐 ④节奏再减慢30%→吸入1.03s/爆发帧1.24s/拉拽0.57s
	var es: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false): es.append(o)
	if es.is_empty(): return
	var center := Vector2.ZERO
	for o in es: center += o["pos"]
	center /= float(es.size())
	var charged: bool = float(u.get("star_energy", 0.0)) >= u["maxHp"] * 0.40   # 星能满→强化
	var uu := u
	u["energy_lock_until"] = maxf(float(u.get("energy_lock_until", 0.0)), battle._t + 2.4)   # 施法锁龟能(爆发/拽完提前恢复·兜底防永锁)
	if charged:
		u["star_lock_until"] = float(u["energy_lock_until"])     # 用户2026-07-16: 普通版施法可积攒星能; 强化版才锁星能不积攒
	var glow := VfxTex._make_fire_glow_tex()
	var rtex := VfxTex._make_pixel_ring_tex()
	var stex := VfxTex._make_star_texture()
	var wtex := VfxTex._make_ring_texture(Color(1, 1, 1, 1))
	# ── 预告(0.21s): 奇点从地里升起由小长大 + 白紫细范围环从中心扩到500码(h≥0.06防掉地下)
	var core := Sprite3D.new()
	core.texture = load("res://assets/sprites/vfx/fx-black-hole.png")
	core.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	core.billboard = BaseMaterial3D.BILLBOARD_ENABLED; core.shaded = false; core.transparent = true
	core.pixel_size = (64.0 * battle.WS) / float(maxi(1, core.texture.get_height()))
	core.position = battle._world_pos(center, 0.12)
	core.scale = Vector3.ONE * 0.2
	battle._world.add_child(core)
	var halo := Sprite3D.new()                                   # 紫罗兰软晕(吸入全程渐亮=充能感)
	halo.texture = glow
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED; halo.shaded = false; halo.transparent = true
	halo.pixel_size = (150.0 * battle.WS) / 128.0
	halo.modulate = Color(0.62, 0.45, 1.0, 0.28)
	halo.position = battle._world_pos(center, 0.86)
	battle._world.add_child(halo)
	var ct = battle._reg_tween(); ct.set_parallel(true)
	ct.tween_property(core, "position", battle._world_pos(center, 0.9), 0.21).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ct.tween_property(core, "scale", Vector3.ONE, 0.21).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_property(halo, "modulate:a", 0.85, 1.03)
	var tr_tex := VfxTex._make_thin_ring_tex()                          # 细线环(48px像素环放大到1000码=满地白格子, 自验截图抓过)
	var ring := Sprite3D.new()
	ring.texture = tr_tex
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ring.axis = Vector3.AXIS_Y
	ring.shaded = false; ring.transparent = true
	ring.modulate = Color(0.9, 0.82, 1.0, 0.9)
	ring.pixel_size = (20.0 * battle.WS) / 256.0
	ring.position = battle._world_pos(center, 0.065)
	battle._world.add_child(ring)
	var rt = battle._reg_tween()
	rt.tween_method(func(q: float) -> void:
		if is_instance_valid(ring): ring.pixel_size = (maxf(20.0, 1000.0 * q) * battle.WS) / 256.0
	, 0.0, 1.0, 0.21).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_interval(0.6)
	rt.tween_property(ring, "modulate:a", 0.0, 0.31)             # 屏息段渐隐(不瞬删)
	rt.tween_callback(ring.queue_free)
	if charged:                                                  # 强化锚点①: 贴地紫黑吸积盘持续自转(远看即知强化)
		var vtex: Texture2D = load("res://assets/sprites/vfx/fx-vortex.png")
		var disk = battle._px_ground_sprite(vtex, center, 170.0, Color(0.55, 0.35, 0.95, 0.8), 0.07)
		var dkt = battle._reg_tween(); dkt.set_parallel(true)
		dkt.tween_method(func(q: float) -> void:
			if is_instance_valid(disk): disk.rotation.y = q * TAU * 2.4
		, 0.0, 1.0, 1.86)
		dkt.tween_property(disk, "modulate:a", 0.0, 0.43).set_delay(1.43)
		dkt.chain().tween_callback(disk.queue_free)
		for o in es:                                             # 强化锚点②前奏: 敌人脚下指向中心的紫色拉力短痕
			if not o.get("alive", false) or (o["pos"] as Vector2).distance_to(center) > 500.0: continue
			var pd: Vector2 = (center - (o["pos"] as Vector2)).normalized()
			battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", o["pos"], (o["pos"] as Vector2) + pd * 46.0, 14.0, Color(0.62, 0.42, 1.0, 0.5), 0.86, 0.06)
	# ── 吸入(0→1.03s): 白色烟圈螺旋内收拖彗尾(EASE_IN先慢后快·同时到达) + 紫星尘被吸向中心
	var wisp_n: int = 8 if charged else 6
	for wi in range(wisp_n):
		var a0: float = TAU * float(wi) / float(wisp_n) + randf() * 0.6
		var r0: float = randf_range(400.0, 500.0)
		var h0: float = randf_range(0.4, 1.1)
		var dly: float = randf_range(0.0, 0.26)
		var mv: float = 1.03 - dly
		var wisp := Sprite3D.new()
		wisp.texture = wtex
		wisp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; wisp.shaded = false; wisp.transparent = true
		wisp.pixel_size = (34.0 * battle.WS) / 96.0
		wisp.modulate = Color(1, 1, 1, 0.0)
		wisp.position = battle._world_pos(center + Vector2(cos(a0), sin(a0)) * r0, h0)
		battle._world.add_child(wisp)
		var tail_i := [0]
		var wt = battle._reg_tween()
		wt.tween_interval(dly)
		wt.tween_method(func(q: float) -> void:
			if not is_instance_valid(wisp): return
			var rr: float = r0 * (1.0 - q)
			var aa: float = a0 + q * 1.6
			wisp.position = battle._world_pos(center + Vector2(cos(aa), sin(aa)) * rr, lerpf(h0, 0.9, q))
			wisp.modulate.a = 0.85 * clampf(q / 0.12, 0.0, 1.0) * clampf((1.0 - q) / 0.15, 0.0, 1.0)   # 淡入淡出(有来处有去处)
			tail_i[0] += 1
			if tail_i[0] % 3 == 0:                               # 彗尾: 渐隐光点链
				var tp := Sprite3D.new()
				tp.texture = glow
				tp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tp.shaded = false; tp.transparent = true
				tp.pixel_size = 0.004
				tp.modulate = Color(0.95, 0.9, 1.0, 0.5)
				tp.position = wisp.position
				battle._world.add_child(tp)
				var tpt = battle._reg_tween()
				tpt.tween_property(tp, "modulate:a", 0.0, 0.3)
				tpt.tween_callback(tp.queue_free)
		, 0.0, 1.0, mv).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		wt.tween_callback(wisp.queue_free)
	var dust_i := [0]
	var sdt = battle._reg_tween()
	sdt.tween_method(func(_q: float) -> void:                    # 紫星尘被吸向中心(技2星尘留痕的反向)
		dust_i[0] += 1
		if dust_i[0] % 4 != 0: return
		var da: float = randf() * TAU
		var dp := Sprite3D.new()
		dp.texture = stex
		dp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dp.shaded = false; dp.transparent = true
		dp.pixel_size = 0.005
		dp.modulate = Color(0.8, 0.65, 1.0, 0.75)
		dp.position = battle._world_pos(center + Vector2(cos(da), sin(da)) * randf_range(140.0, 470.0), randf_range(0.1, 0.6))
		battle._world.add_child(dp)
		var dpt = battle._reg_tween(); dpt.set_parallel(true)
		dpt.tween_property(dp, "position", battle._world_pos(center, 0.85), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		dpt.tween_property(dp, "modulate:a", 0.0, 0.38)
		dpt.chain().tween_callback(dp.queue_free)
	, 0.0, 1.0, 0.94)
	# ── 屏息(1.03-1.24s)→爆发帧(1.24s): 伤害本帧结算(用户批)+白紫爆闪+透镜波纹+强化拉拽
	var do_burst := func() -> void:
		if not uu.get("alive", false):                           # 施法者阵亡→奇点静默消散(有去处), 不结算
			if is_instance_valid(core):
				var cf = battle._reg_tween(); cf.set_parallel(true)
				cf.tween_property(core, "scale", Vector3.ONE * 0.1, 0.43)
				cf.tween_property(core, "position", battle._world_pos(center, 0.08), 0.43)
				cf.tween_property(halo, "modulate:a", 0.0, 0.43)
				cf.chain().tween_callback(func() -> void: core.queue_free(); halo.queue_free())
			return
		if not charged:                                          # 普通版: 爆发即恢复龟能(星能本就不锁·可积攒)
			uu["energy_lock_until"] = battle._t
		var victims: Array = []
		for o2 in battle._targeting._enemies_of(uu):                               # 爆发帧结算(同帧飘字·封板0.8A魔法)
			if not o2.get("alive", false): continue
			if (o2["pos"] as Vector2).distance_to(center) > 500.0: continue
			battle._damage._apply_damage_from(uu, o2, battle._atk_dmg(uu, 0.8, o2, true), Color("#b09bff"))
			battle._vfx._hit_spark(o2)
			victims.append(o2)
		battle._shake(0.12 if charged else 0.08)
		var fl := Sprite3D.new()                                 # 白紫爆闪(白核紫边)
		fl.texture = glow
		fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fl.shaded = false; fl.transparent = true
		fl.pixel_size = (170.0 * battle.WS) / 128.0
		fl.modulate = Color(1.0, 0.96, 1.0, 0.95)
		fl.position = battle._world_pos(center, 0.9)
		fl.scale = Vector3.ONE * 0.5
		battle._world.add_child(fl)
		var flt = battle._reg_tween(); flt.set_parallel(true)
		flt.tween_property(fl, "scale", Vector3.ONE * 2.6, 0.43).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flt.tween_property(fl, "modulate:a", 0.0, 0.43)
		flt.chain().tween_callback(fl.queue_free)
		var ltex: Texture2D = load("res://assets/sprites/vfx/fx-shock-ring.png")
		var lens = battle._px_ground_sprite(ltex, center, 40.0, Color(0.85, 0.75, 1.0, 0.85), 0.068)   # 透镜波纹: 空间"拧了一下"
		var lt = battle._reg_tween()
		lt.tween_method(func(q: float) -> void:
			if is_instance_valid(lens):
				lens.pixel_size = (maxf(40.0, 1000.0 * q) * battle.WS) / float(maxi(1, ltex.get_height()))
				lens.modulate.a = 0.85 * (1.0 - q)
		, 0.0, 1.0, 0.36)
		lt.tween_callback(lens.queue_free)
		if not charged:                                          # 普通版收尾: 奇点缩小沉回地里(与来处对称)+淡紫残痕
			var cd = battle._reg_tween(); cd.set_parallel(true)
			cd.tween_property(core, "scale", Vector3.ONE * 0.12, 0.64).set_delay(0.36)
			cd.tween_property(core, "position", battle._world_pos(center, 0.08), 0.64).set_delay(0.36)
			cd.tween_property(halo, "modulate:a", 0.0, 0.71).set_delay(0.29)
			cd.chain().tween_callback(func() -> void: core.queue_free(); halo.queue_free())
			var mark = battle._px_ground_sprite(rtex, center, 300.0, Color(0.6, 0.45, 0.95, 0.4), 0.06)
			var mkt = battle._reg_tween()
			mkt.tween_property(mark, "modulate:a", 0.0, 0.7)
			mkt.tween_callback(mark.queue_free)
			return
		# ── 强化锚点③(用户2026-07-16"换位=延中心点到对端"): 重力抛物线甩飞穿过中心点落对端0.57s·落地即恢复行动 头顶紫螺旋跟飞+尾迹+沿途白火花
		uu["star_energy"] = 0.0                                  # 爆发帧清空星能(强化代价)
		var vtex2: Texture2D = load("res://assets/sprites/vfx/fx-vortex.png")
		for o3 in victims:
			if o3.get("_eggImmune", false): continue
			if o3.get("airborne", false): continue               # 已滞空不叠加juggle
			var from3: Vector2 = o3["pos"]
			var oref3: Dictionary = o3
			var dest3 = Vector2(clampf(center.x * 2.0 - from3.x, battle.ARENA.position.x, battle.ARENA.end.x), clampf(center.y * 2.0 - from3.y, battle.ARENA.position.y, battle.ARENA.end.y))   # 换位=过奇点镜像落对侧(用户2026-07-16"延中心点到对端": 左右对调, 非聚拢; 镜像保距→落点互不重叠)
			if o3.has("_home_pos"): o3["_home_pos"] = dest3      # 评审假人: 落点即新驻点(原归位逻辑会把人走回出生位→用户看到"拖到对端又回去"; 真实对局无_home_pos零影响)
			battle._damage._knockback(uu, o3, 0.0, 1.05, 0.0)                   # 起跳vy=6.3(滞空0.57s)+震屏顿帧; 落地juice物理tick自带(压扁+尘+轻震)
			var mvt = battle._reg_tween()                              # 真抛物线弧: 水平匀速直线(linear无缓动)+竖直重力=被甩飞过中心点(用户2026-07-16"很真实的被重力拖拽·飞过中心点·落到对端后回复行动"→无定身, 落地即自由; airborne期分离/AI本就不生效)
			mvt.tween_method(func(q: float) -> void:
				if oref3.get("alive", false) and oref3.get("airborne", false):
					oref3["pos"] = from3.lerp(dest3, q)
			, 0.0, 1.0, 0.57)
			battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", from3, dest3, 26.0, Color(0.72, 0.55, 1.0, 0.55), 0.64)
			var swirl := Sprite3D.new()                          # 头顶紫螺旋丝带(发条R翻卷标记b29-b41)
			swirl.texture = vtex2
			swirl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; swirl.shaded = false; swirl.transparent = true
			swirl.pixel_size = (46.0 * battle.WS) / float(maxi(1, vtex2.get_height()))
			swirl.modulate = Color(0.78, 0.6, 1.0, 0.0)
			swirl.position = battle._world_pos(from3, 1.2)
			swirl.scale = Vector3.ONE * 0.5
			battle._world.add_child(swirl)
			var spark_i := [0]
			var pt3 = battle._reg_tween()
			pt3.tween_method(func(q: float) -> void:             # 跟飞: 螺旋悬在头顶(含击飞高度), 沿途白粉火花
				if not is_instance_valid(swirl): return
				if oref3.get("alive", false):
					swirl.position = battle._world_pos(oref3["pos"], float(oref3.get("height", 0.0)) + 1.2)
				swirl.modulate.a = 0.9 * clampf(q / 0.2, 0.0, 1.0)
				swirl.scale = Vector3.ONE * (0.5 + q * 0.5)
				spark_i[0] += 1
				if spark_i[0] % 5 == 0 and oref3.get("alive", false):   # 沿途白粉火花星屑(发条R脚下迸溅)
					var sp := Sprite3D.new()
					sp.texture = stex
					sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
					sp.pixel_size = 0.006
					sp.modulate = Color(1.0, 0.9, 0.95, 0.95)
					sp.position = battle._world_pos((oref3["pos"] as Vector2) + Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0)), maxf(0.05, float(oref3.get("height", 0.0)) * randf()))
					battle._world.add_child(sp)
					var spt = battle._reg_tween()
					spt.tween_property(sp, "modulate:a", 0.0, 0.3)
					spt.tween_callback(sp.queue_free)
			, 0.0, 1.0, 0.6)
			pt3.tween_callback(func() -> void:                   # 落地: 受击白星+螺旋卷动放大渐隐(不瞬删)
				if oref3.get("alive", false): battle._vfx._hit_spark(oref3)
				if is_instance_valid(swirl):
					var st2 = battle._reg_tween(); st2.set_parallel(true)
					st2.tween_property(swirl, "scale", Vector3.ONE * 1.35, 0.5)
					st2.tween_property(swirl, "modulate:a", 0.0, 0.5)
					st2.chain().tween_callback(swirl.queue_free))
		var fin = battle._reg_tween()                                  # 拽完落地: 恢复锁+奇点吃饱膨胀一拍再缩灭+紫环印记缓隐
		fin.tween_interval(0.75)
		fin.tween_callback(func() -> void:
			if uu.get("alive", false):
				uu["energy_lock_until"] = battle._t
				uu["star_lock_until"] = battle._t
			if is_instance_valid(core):
				var eat = battle._reg_tween()
				eat.tween_property(core, "scale", Vector3.ONE * 1.3, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				eat.tween_property(core, "scale", Vector3.ONE * 0.1, 0.57)
				eat.parallel().tween_property(core, "position", battle._world_pos(center, 0.08), 0.57)
				eat.parallel().tween_property(halo, "modulate:a", 0.0, 0.57)
				eat.chain().tween_callback(func() -> void: core.queue_free(); halo.queue_free())
			var mark2 = battle._px_ground_sprite(rtex, center, 300.0, Color(0.6, 0.45, 0.95, 0.45), 0.06)
			var mk2 = battle._reg_tween()
			mk2.tween_property(mark2, "modulate:a", 0.0, 1.7)
			mk2.tween_callback(mark2.queue_free))
	var master = battle._reg_tween()
	master.tween_interval(1.03)
	master.tween_callback(func() -> void:                        # 屏息: 奇点脉动一拍(爆发前的静默b25-b27)
		if is_instance_valid(core):
			var pt = battle._reg_tween()
			pt.tween_property(core, "scale", Vector3.ONE * 1.16, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			pt.tween_property(core, "scale", Vector3.ONE, 0.1))
	master.tween_interval(0.21)
	master.tween_callback(do_burst)

func _sk_star_wave(u: Dictionary) -> void:                       # 星际龟·星波(封板数值·2026-07-16演出重设计"星潮扩散/天崩"): 普通=扩散环1.16s波扫到才结算1.0A魔法; 星能满追加巨彗星敌阵中心【真伤=100%消耗的星能】(落地结算·400码)+清空星能
	var charged: bool = float(u.get("star_energy", 0.0)) >= u["maxHp"] * 0.40
	var uu2 := u
	var origin: Vector2 = u["pos"]
	u["energy_lock_until"] = maxf(float(u.get("energy_lock_until", 0.0)), battle._t + (3.2 if charged else 1.8))   # 施法锁龟能(用户2026-07-16)·②③提前恢复
	u["star_lock_until"] = float(u["energy_lock_until"])                                                    # 星能同锁(积累暂停)
	var stex := VfxTex._make_star_texture()
	var glow0 := VfxTex._make_fire_glow_tex()
	# ── 起手(0.36s): 4颗小星被吸进龟身(聚能预兆)
	for gi in range(4):
		var ga: float = TAU * float(gi) / 4.0 + randf() * 0.5
		var gs := Sprite3D.new()
		gs.texture = stex
		gs.billboard = BaseMaterial3D.BILLBOARD_ENABLED; gs.shaded = false; gs.transparent = true
		gs.pixel_size = 0.009
		gs.modulate = Color(1.0, 0.95, 1.0, 0.95)
		gs.position = battle._world_pos(origin + Vector2(cos(ga), sin(ga)) * randf_range(90.0, 140.0), randf_range(0.3, 1.0))
		battle._world.add_child(gs)
		var gt = battle._reg_tween(); gt.set_parallel(true)
		gt.tween_property(gs, "position", battle._world_pos(origin, 0.8), 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		gt.tween_property(gs, "modulate:a", 0.0, 0.12).set_delay(0.28)
		gt.chain().tween_callback(gs.queue_free)
	# ── 波环扩散(0.4s起·1.16s推到520码): 双层贴地环+环带12星随波转·波前扫到才结算·尽头碎星屑
	var rtex := VfxTex._make_pixel_ring_tex()
	var wave := func() -> void:
		if not uu2.get("alive", false): return
		var rc = battle._px_ground_sprite(rtex, origin, 20.0, Color(0.95, 0.9, 1.0, 0.95), 0.06)    # 锐利白紫波前
		var rh = battle._px_ground_sprite(rtex, origin, 20.0, Color(0.65, 0.45, 1.0, 0.5), 0.055)   # 外侧紫晕带(略大=带宽感)
		var wstars: Array = []
		for wi in range(12):                                      # 环带嵌星(随波旋转)
			var ws := Sprite3D.new()
			ws.texture = stex
			ws.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ws.shaded = false; ws.transparent = true
			ws.pixel_size = 0.008
			ws.modulate = Color(1.0, 0.95, 1.0, 0.9)
			ws.position = battle._world_pos(origin, 0.25)
			battle._world.add_child(ws)
			wstars.append(ws)
		var hitset: Array = []                                    # 波前扫到才结算(⛔不拿单位字典当键)
		var dust_t := [0.0]
		var wt = battle._reg_tween()
		wt.tween_method(func(q: float) -> void:
			var r: float = 520.0 * q
			if is_instance_valid(rc): rc.pixel_size = (maxf(20.0, r * 2.0) * battle.WS) / float(maxi(1, rtex.get_height()))
			if is_instance_valid(rh):
				rh.pixel_size = (maxf(20.0, r * 2.0 + 56.0) * battle.WS) / float(maxi(1, rtex.get_height()))
				rh.modulate.a = 0.5 * (1.0 - q * 0.5)
			for wi2 in range(wstars.size()):
				var ws2 = wstars[wi2]
				if not is_instance_valid(ws2): continue
				var wa: float = TAU * float(wi2) / 12.0 + q * 2.6
				ws2.position = battle._world_pos(origin + Vector2(cos(wa), sin(wa)) * r, 0.25)
			dust_t[0] += 1.0
			if int(dust_t[0]) % 4 == 0 and r > 40.0:              # 波过留痕: 星尘微光点0.4s渐隐
				var da: float = randf() * TAU
				var dp := Sprite3D.new()
				dp.texture = glow0
				dp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dp.shaded = false; dp.transparent = true
				dp.pixel_size = 0.004
				dp.modulate = Color(0.85, 0.7, 1.0, 0.8)
				dp.position = battle._world_pos(origin + Vector2(cos(da), sin(da)) * randf_range(r * 0.4, r * 0.95), randf_range(0.1, 0.5))
				battle._world.add_child(dp)
				var dpt = battle._reg_tween()
				dpt.tween_property(dp, "modulate:a", 0.0, 0.8)
				dpt.tween_callback(dp.queue_free)
			for o in battle._targeting._enemies_of(uu2):                            # 波前扫到才结算1.0A魔法(近先远后·封板系数)
				if not o.get("alive", false) or battle._arr_has_unit(hitset, o): continue
				if (o["pos"] as Vector2).distance_to(origin) > r: continue
				hitset.append(o)
				battle._damage._apply_damage_from(uu2, o, battle._atk_dmg(uu2, 1.0, o, true), Color("#c9b0ff"))
				battle._vfx._hit_spark(o)
				for hb in range(2):                                # 命中: 2颗小星从敌身弹出
					var ha: float = randf() * TAU
					var hs := Sprite3D.new()
					hs.texture = stex
					hs.billboard = BaseMaterial3D.BILLBOARD_ENABLED; hs.shaded = false; hs.transparent = true
					hs.pixel_size = 0.007
					hs.modulate = Color(1.0, 0.95, 1.0, 1.0)
					hs.position = battle._world_pos(o["pos"], 0.7)
					battle._world.add_child(hs)
					var ht = battle._reg_tween(); ht.set_parallel(true)
					ht.tween_property(hs, "position", battle._world_pos((o["pos"] as Vector2) + Vector2(cos(ha), sin(ha)) * randf_range(30.0, 60.0), 0.15), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					ht.tween_property(hs, "modulate:a", 0.0, 0.7)
					ht.chain().tween_callback(hs.queue_free)
		, 0.0, 1.0, 1.16)
		wt.tween_callback(func() -> void:                         # 消散: 环碎成一圈星屑向外散开(不凭空消失)
			if not charged and uu2.get("alive", false):
				uu2["energy_lock_until"] = battle._t                      # 基础版: 波结束恢复龟能/星能
				uu2["star_lock_until"] = battle._t
			if is_instance_valid(rc):                              # 波前慢慢消散0.55s(用户2026-07-16: 不准瞬间消失)
				var rcf = battle._reg_tween()
				rcf.tween_property(rc, "modulate:a", 0.0, 0.55)
				rcf.tween_callback(rc.queue_free)
			if is_instance_valid(rh):
				var rhf = battle._reg_tween()
				rhf.tween_property(rh, "modulate:a", 0.0, 0.55)
				rhf.tween_callback(rh.queue_free)
			for wi3 in range(wstars.size()):
				var ws3 = wstars[wi3]
				if not is_instance_valid(ws3): continue
				var wa3: float = TAU * float(wi3) / 12.0 + 2.6
				var wt3 = battle._reg_tween(); wt3.set_parallel(true)
				wt3.tween_property(ws3, "position", battle._world_pos(origin + Vector2(cos(wa3), sin(wa3)) * 580.0, 0.1), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				wt3.tween_property(ws3, "modulate:a", 0.0, 0.6)
				wt3.chain().tween_callback(ws3.queue_free))
	battle._pending_shots.append({"delay": 0.4, "fn": wave, "src": u})
	if charged:                                                   # ── 强化: 巨彗星「天崩」(逐帧订正asol_hi a30/a38/a44)
		var es: Array = []
		for o in battle._targeting._enemies_of(u):
			if o.get("alive", false): es.append(o)
		if es.is_empty(): return
		var center := Vector2.ZERO
		for o in es: center += o["pos"]
		center /= float(es.size())
		var burst: float = float(u.get("star_energy", 0.0))       # 100%消耗的星能→彗星真伤(用户2026-07-16改·替代封板1.5A魔法)
		u["star_energy"] = 0.0                                    # 施放即消耗全部星能
		var ring1 = battle._px_ground_sprite(rtex, center, 800.0, Color(0.75, 0.5, 1.0, 0.0), 0.05)   # 紫双环预警
		var ring2 = battle._px_ground_sprite(rtex, center, 640.0, Color(0.9, 0.7, 1.0, 0.0), 0.055)
		var rt = battle._reg_tween(); rt.set_parallel(true)
		rt.tween_property(ring1, "modulate:a", 0.7, 0.3)
		rt.tween_property(ring2, "modulate:a", 0.55, 0.3)
		var orbs: Array = []                                      # 环上节点珠×3(a30)
		for oi in range(3):
			var orb := Sprite3D.new()
			orb.texture = glow0
			orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; orb.shaded = false; orb.transparent = true
			orb.pixel_size = 0.009
			orb.modulate = Color(1.0, 0.97, 1.0, 0.95)
			orb.position = battle._world_pos(center + Vector2(400.0, 0.0), 0.15)
			battle._world.add_child(orb)
			orbs.append(orb)
		var pillar := Sprite3D.new()                              # 天光柱预兆: 细紫光垂到落点·1s变亮变粗
		pillar.texture = glow0
		pillar.billboard = BaseMaterial3D.BILLBOARD_ENABLED; pillar.shaded = false; pillar.transparent = true
		pillar.pixel_size = 0.006
		pillar.modulate = Color(0.75, 0.55, 1.0, 0.25)
		pillar.position = battle._world_pos(center, 2.6)
		pillar.scale = Vector3(0.4, 14.0, 1.0)
		battle._world.add_child(pillar)
		var obt = battle._reg_tween(); obt.set_parallel(true)
		obt.tween_property(pillar, "modulate:a", 0.7, 1.9)
		obt.tween_property(pillar, "pixel_size", 0.014, 1.9)
		obt.chain().tween_method(func(q: float) -> void:
			for oi2 in range(orbs.size()):
				var ob2 = orbs[oi2]
				if not is_instance_valid(ob2): continue
				var oa: float = TAU * float(oi2) / 3.0 + q * 1.6
				ob2.position = battle._world_pos(center + Vector2(cos(oa), sin(oa)) * 400.0, 0.15)
		, 0.0, 1.0, 0.001)
		var obr = battle._reg_tween()                                   # 节点珠绕环(独立驱动1s)
		obr.tween_method(func(q: float) -> void:
			for oi3 in range(orbs.size()):
				var ob3 = orbs[oi3]
				if not is_instance_valid(ob3): continue
				var oa2: float = TAU * float(oi3) / 3.0 + q * 1.7
				ob3.position = battle._world_pos(center + Vector2(cos(oa2), sin(oa2)) * 400.0, 0.15)
		, 0.0, 1.0, 2.0)
		var rise_t = battle._reg_tween()                                # 地面星屑被吸起(反向预兆·每0.12s一粒)
		rise_t.tween_method(func(q: float) -> void:
			if int(q * 8.0) != int(maxf(0.0, q - 0.125) * 8.0):
				var ra: float = randf() * TAU
				var rp: Vector2 = center + Vector2(cos(ra), sin(ra)) * randf_range(60.0, 320.0)
				var rs := Sprite3D.new()
				rs.texture = stex
				rs.billboard = BaseMaterial3D.BILLBOARD_ENABLED; rs.shaded = false; rs.transparent = true
				rs.pixel_size = 0.007
				rs.modulate = Color(0.9, 0.8, 1.0, 0.85)
				rs.position = battle._world_pos(rp, 0.1)
				battle._world.add_child(rs)
				var rst = battle._reg_tween(); rst.set_parallel(true)
				rst.tween_property(rs, "position", battle._world_pos(rp, randf_range(1.6, 2.6)), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				rst.tween_property(rs, "modulate:a", 0.0, 0.5)
				rst.chain().tween_callback(rs.queue_free)
		, 0.0, 1.0, 2.0)
		var comet := func() -> void:                              # 2.0s后(见文末 _pending_shots delay): 坠落0.5s(大火球头+束状粗光柱+嵌星+坠落微震)
			if is_instance_valid(pillar):                          # 天光柱: 坠落瞬间快速隐去(彗星接管); 紫环保留到撞击后慢散
				var pf = battle._reg_tween()
				pf.tween_property(pillar, "modulate:a", 0.0, 0.15)
				pf.tween_callback(pillar.queue_free)
			for ob4 in orbs:
				if is_instance_valid(ob4): ob4.queue_free()
			if not uu2.get("alive", false): return
			var from2: Vector2 = center + Vector2(520.0, -420.0)
			var fdir: Vector2 = (from2 - center).normalized()
			var head := Sprite3D.new()                            # 白炽大火球头(~90码)
			var htex: Texture2D = load("res://assets/sprites/vfx/comet-head.png")
			if htex != null:
				head.texture = htex
				head.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				head.pixel_size = (90.0 * battle.WS) / float(maxi(1, htex.get_height()))
			else:
				head.texture = glow0
				head.pixel_size = 0.03
			head.billboard = BaseMaterial3D.BILLBOARD_ENABLED; head.shaded = false; head.transparent = true
			head.modulate = Color(1.0, 0.97, 1.0, 1.0)
			head.position = battle._world_pos(from2, 4.2)
			battle._world.add_child(head)
			battle._shake(0.04)                                           # 坠落中就开始微震
			var ct2 = battle._reg_tween()
			ct2.tween_method(func(pv: float) -> void:
				if not is_instance_valid(head): return
				var cp: Vector2 = from2.lerp(center, pv)
				var ch2: float = 4.2 * (1.0 - pv) + 0.4 * pv
				head.position = battle._world_pos(cp, ch2)
				head.rotation.z = -atan2(-fdir.y, fdir.x) + PI
				battle._bolt_line(cp, cp + fdir * 280.0, Color(1.0, 0.97, 1.0, 0.92))                                # 束状粗光柱: 白炽核
				battle._bolt_line(cp + fdir.orthogonal() * 8.0, cp + fdir * 250.0, Color(0.8, 0.55, 1.0, 0.6))       # 紫晕两翼
				battle._bolt_line(cp - fdir.orthogonal() * 8.0, cp + fdir * 250.0, Color(0.6, 0.4, 0.95, 0.45))
				var tr := Sprite3D.new()                                                                       # 残柱留光
				tr.texture = glow0
				tr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tr.shaded = false; tr.transparent = true
				tr.pixel_size = 0.016
				tr.modulate = Color(0.85, 0.65, 1.0, 0.7)
				tr.position = battle._world_pos(cp, ch2)
				battle._world.add_child(tr)
				var trt = battle._reg_tween()
				trt.tween_property(tr, "modulate:a", 0.0, 0.6)
				trt.tween_callback(tr.queue_free)
				if int(pv * 20.0) % 3 == 0:                                                                    # 沿途嵌星(f_022)
					var sst := Sprite3D.new()
					sst.texture = stex
					sst.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sst.shaded = false; sst.transparent = true
					sst.pixel_size = 0.01
					sst.modulate = Color(1.0, 0.97, 1.0, 1.0)
					sst.position = battle._world_pos(cp + Vector2(randf_range(-18.0, 18.0), randf_range(-12.0, 12.0)), ch2 + randf_range(-0.2, 0.3))
					battle._world.add_child(sst)
					var sstt = battle._reg_tween()
					sstt.tween_property(sst, "modulate:a", 0.0, 1.0)
					sstt.tween_callback(sst.queue_free)
			, 0.0, 1.0, 0.5)
			ct2.tween_callback(func() -> void:
				if is_instance_valid(head): head.queue_free()
				for o2 in battle._targeting._enemies_of(uu2):                        # 伤害撞击帧结算(用户2026-07-16: 100%消耗星能·真实伤害·400码)
					if o2.get("alive", false) and o2["pos"].distance_to(center) <= 400.0:
						battle._damage._apply_damage_from(uu2, o2, maxi(1, int(burst)), Color("#ffffff"), 0.0, true)
				if uu2.get("alive", false):
					uu2["energy_lock_until"] = battle._t                  # 巨彗星造成伤害后才恢复龟能/星能(用户2026-07-16)
					uu2["star_lock_until"] = battle._t
				if is_instance_valid(ring1):                       # 紫色地面预警环: 撞击后慢慢消散0.9s(用户2026-07-16)
					var r1f = battle._reg_tween()
					r1f.tween_property(ring1, "modulate:a", 0.0, 0.9)
					r1f.tween_callback(ring1.queue_free)
				if is_instance_valid(ring2):
					var r2f = battle._reg_tween()
					r2f.tween_property(ring2, "modulate:a", 0.0, 0.9)
					r2f.tween_callback(ring2.queue_free)
				battle._screen_flash_light()                              # 全屏轻白闪一拍
				battle._shake(battle.JUICE_SHAKE_BIG); battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
				var core := Sprite3D.new()                         # 白金光核膨胀
				core.texture = glow0
				core.billboard = BaseMaterial3D.BILLBOARD_ENABLED; core.shaded = false; core.transparent = true
				core.pixel_size = (70.0 * battle.WS) / float(maxi(1, glow0.get_width()))
				core.modulate = Color(1.0, 0.95, 0.82, 1.0)
				core.position = battle._world_pos(center, 0.5)
				battle._world.add_child(core)
				var cot = battle._reg_tween(); cot.set_parallel(true)
				cot.tween_property(core, "pixel_size", (220.0 * battle.WS) / float(maxi(1, glow0.get_width())), 0.64)
				cot.tween_property(core, "modulate:a", 0.0, 0.7)
				cot.chain().tween_callback(core.queue_free)
				for pi2 in range(9):                               # 紫黑烟尘花瓣(a38: 向外+上翻卷·膨胀渐隐0.7s)
					var pa2: float = TAU * float(pi2) / 9.0 + randf() * 0.35
					var petal := Sprite3D.new()
					petal.texture = glow0
					petal.billboard = BaseMaterial3D.BILLBOARD_ENABLED; petal.shaded = false; petal.transparent = true
					petal.pixel_size = (randf_range(90.0, 130.0) * battle.WS) / float(maxi(1, glow0.get_width()))
					petal.modulate = Color(0.4, 0.1, 0.2, 0.85) if pi2 % 3 == 0 else Color(0.22, 0.08, 0.32, 0.9)
					petal.position = battle._world_pos(center + Vector2(cos(pa2), sin(pa2)) * 40.0, 0.4)
					battle._world.add_child(petal)
					var pt2 = battle._reg_tween(); pt2.set_parallel(true)
					pt2.tween_property(petal, "position", battle._world_pos(center + Vector2(cos(pa2), sin(pa2)) * randf_range(150.0, 230.0), randf_range(1.0, 1.9)), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					pt2.tween_property(petal, "pixel_size", petal.pixel_size * 1.7, 1.1)
					pt2.tween_property(petal, "modulate:a", 0.0, 1.4)
					pt2.chain().tween_callback(petal.queue_free)
				battle._burst_vfx("res://assets/sprites/vfx/comet-impact.png", center, 320.0, 1.6)
				battle._skill_ring(center, Color(1.0, 0.85, 1.0, 0.65), 400.0)
				battle._skill_ring(center, Color(0.7, 0.5, 1.0, 0.5), 240.0)
				var cons: Array = []                               # 星座刻印(a38): 6星细线相连·缓亮定格缓隐
				for si0 in range(6):
					var ca0: float = TAU * float(si0) / 6.0 + randf_range(-0.35, 0.35)
					cons.append(center + Vector2(cos(ca0), sin(ca0)) * randf_range(120.0, 240.0))
				for si2 in range(cons.size()):
					battle._bolt_line(cons[si2], cons[(si2 + 1) % cons.size()], Color(0.9, 0.8, 1.0, 0.4))
					var cst := Sprite3D.new()
					cst.texture = stex
					cst.billboard = BaseMaterial3D.BILLBOARD_ENABLED; cst.shaded = false; cst.transparent = true
					cst.pixel_size = 0.013
					cst.modulate = Color(1.0, 0.95, 1.0, 0.0)
					cst.position = battle._world_pos(cons[si2], randf_range(0.4, 1.2))
					battle._world.add_child(cst)
					var cstt = battle._reg_tween()
					cstt.tween_property(cst, "modulate:a", 1.0, 0.6)
					cstt.tween_interval(0.6)
					cstt.tween_property(cst, "modulate:a", 0.0, 2.0)
					cstt.tween_callback(cst.queue_free)
				for si in range(12):                               # 外围星星闪点
					var sa2: float = TAU * float(si) / 12.0 + randf_range(-0.2, 0.2)
					var sp2: Vector2 = center + Vector2(cos(sa2), sin(sa2)) * randf_range(60.0, 260.0)
					var ss := Sprite3D.new()
					ss.texture = stex
					ss.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ss.shaded = false; ss.transparent = true
					ss.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
					ss.pixel_size = 0.012 * randf_range(0.7, 1.3)
					ss.modulate = Color(1.0, 0.95, 1.0, 0.0)
					ss.position = battle._world_pos(sp2, randf_range(0.3, 1.4))
					battle._world.add_child(ss)
					var st2 = battle._reg_tween()
					st2.tween_interval(randf() * 0.2)
					st2.tween_property(ss, "modulate:a", 1.0, 0.08)
					st2.tween_property(ss, "modulate:a", 0.0, 1.0)
					st2.tween_callback(ss.queue_free)
				for sr2 in range(4):                               # 星痕余韵(a44: 沿坠落方向星串1.2s缓隐)
					var rp2: Vector2 = center + fdir * (40.0 + 55.0 * float(sr2)) + Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0))
					var rst2 := Sprite3D.new()
					rst2.texture = stex
					rst2.billboard = BaseMaterial3D.BILLBOARD_ENABLED; rst2.shaded = false; rst2.transparent = true
					rst2.pixel_size = 0.009
					rst2.modulate = Color(1.0, 0.95, 1.0, 0.9)
					rst2.position = battle._world_pos(rp2, 0.3 + 0.25 * float(sr2))
					battle._world.add_child(rst2)
					var rstt2 = battle._reg_tween()
					rstt2.tween_property(rst2, "modulate:a", 0.0, 2.4)
					rstt2.tween_callback(rst2.queue_free))
		battle._pending_shots.append({"delay": 2.0, "fn": comet, "src": u})

# (已废弃的 2026-07-09 版说明: 吸经过敌90码+经过即1段伤害。现行实现见下方 _sk_star_wormhole 头注释:
#  引力150码/捕获100码/伤害只在抵达边界爆炸时结算。留此行仅为标记该段旧描述已作废。)
func _sk_star_wormhole(u: Dictionary, tgt) -> void:                # 星际龟·虫洞(用户2026-07-16重做): 蓄力→140码/s直线飞到地图边界→引力场150码真重力吸(1/r²加速度·弧线卷入)→捕获100码吸着走(绕洞打转·位移被主导·可攻可被打)→边界爆炸=1.5A×(1+5%每秒·发射时刻定格)魔法+携带者炸开
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var start: Vector2 = u["pos"]
	## ★★★用户 2026-08-14:「虫洞是战斗时间越久…每一路的时间」
	##   —— 机制按代码走(战斗时长, 不是虫洞寿命), 但基准改成【本路】开打时刻。
	##   原来用 `battle._t`, 那是**跨上路→下路→决胜一直累加、永不重置**的全局时钟
	##   (CLAUDE.md §3.4 专门警告过)⇒ 下路一开场倍率就已经 10.5×、决胜 24×,
	##   而不是文案与设计意图的 1.5×。
	##   `battle._sd_t0` = 本战场开打时刻, `_dl_start_fight` 每路重置 —— 现成的正确基准。
	var lane_sec: float = maxf(0.0, battle._t - battle._sd_t0)             # 本路已打秒数
	var mult: float = 1.5 * (1.0 + 0.05 * lane_sec)                        # 爆炸伤害=1.5A×(1+5%每秒)·发射时刻定格
	var uu := u
	## ★★用户 2026-08-14:「释放虫洞时锁龟能, 直到虫洞消失」。
	##   虫洞飞到地图边界才炸, 时长不固定(140 码/s × 到边界的距离) ⇒ **不能设固定秒数**,
	##   只能发射时锁死、爆炸那一刻解锁。用现成的 `energy_lock_until`(泡泡盾/星波彗星同款)。
	##   ★锁到一个远期时刻而不是 INF: 万一虫洞被别的路径提前销毁(换路/单位死亡),
	##     也有兜底解锁, 不会把龟能永久锁死 —— 今晚凤凰那次"忘了清旗子=永久无敌"的教训。
	u["energy_lock_until"] = battle._t + WORMHOLE_LOCK_FALLBACK
	battle._anticipate(u)                                                  # 短暂蓄力前摇
	var fire := func() -> void:
		if not uu.get("alive", false): return
		var hole := Sprite3D.new()                                  # 虫洞视觉(fx-vortex真旋涡)
		hole.texture = load("res://assets/sprites/vfx/fx-vortex.png")
		hole.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hole.shaded = false; hole.transparent = true
		hole.modulate = Color(1.0, 1.0, 1.0, 0.95)
		hole.pixel_size = (240.0 * battle.WS) / 128.0
		hole.position = battle._world_pos(start, 0.4)
		battle._world.add_child(hole)
		# 飞行终点=地图边界(射线与ARENA求交·用户2026-07-16"在地图边界爆炸")
		var end_d: float = 99999.0
		if absf(dir.x) > 0.001:
			end_d = minf(end_d, ((battle.ARENA.end.x - 30.0 - start.x) / dir.x) if dir.x > 0.0 else ((battle.ARENA.position.x + 30.0 - start.x) / dir.x))
		if absf(dir.y) > 0.001:
			end_d = minf(end_d, ((battle.ARENA.end.y - 24.0 - start.y) / dir.y) if dir.y > 0.0 else ((battle.ARENA.position.y + 24.0 - start.y) / dir.y))
		end_d = maxf(80.0, end_d)
		var grav: Array = []    # 引力场内敌 [{o, vel}] (⛔不拿单位字典当Dict键)
		var caught: Array = []  # 被捕获携带敌 [{o, ang, rr}]
		var pd := [0.0]
		var suck := [0.0]
		var step := func(d: float) -> void:
			var dt: float = maxf(0.0, (d - pd[0]) / 140.0)          # 本帧时长(推进速度140码/s换算)
			pd[0] = d
			var c: Vector2 = start + dir * d
			if is_instance_valid(hole): hole.position = battle._world_pos(c, 0.4)
			for o in battle._targeting._enemies_of(uu):                                # ① 引力场150码: 真重力1/r²加速度(近强远弱·弧线卷入)
				if not o.get("alive", false) or o.get("_eggImmune", false): continue
				var carried := false
				for cg in caught:
					if cg["o"] == o: carried = true; break
				if carried: continue
				var r: float = (o["pos"] as Vector2).distance_to(c)
				if r > 150.0: continue
				if r <= 100.0:                                       # ② 捕获(100码·用户定): 吸着走·绕洞打转
					var rel: Vector2 = (o["pos"] as Vector2) - c
					caught.append({"o": o, "ang": atan2(rel.y, rel.x), "rr": maxf(50.0, r)})
					battle._skill_ring(o["pos"], Color(0.75, 0.6, 1.0, 0.6), 44.0)
					continue
				var gi := -1
				for k in range(grav.size()):
					if grav[k]["o"] == o: gi = k; break
				if gi < 0:
					grav.append({"o": o, "vel": Vector2.ZERO}); gi = grav.size() - 1
				var acc: float = 900000.0 / maxf(r, 45.0) / maxf(r, 45.0)   # 1/r²引力(150码≈40码/s²→45码≈444·封顶防瞬吸)
				var g2: Dictionary = grav[gi]
				g2["vel"] = (g2["vel"] as Vector2) * 0.985 + (c - (o["pos"] as Vector2)).normalized() * acc * dt
				o["pos"] = (o["pos"] as Vector2) + (g2["vel"] as Vector2) * dt
			for cg2 in caught:                                       # ③ 携带: 跟虫洞走+绕洞缓转·半径缓收(事件视界打转)
				var oc: Dictionary = cg2["o"]
				if not oc.get("alive", false): continue
				cg2["ang"] = float(cg2["ang"]) + dt * 2.2
				cg2["rr"] = maxf(52.0, float(cg2["rr"]) - 26.0 * dt)
				oc["pos"] = c + Vector2(cos(float(cg2["ang"])), sin(float(cg2["ang"]))) * float(cg2["rr"])
			suck[0] += 1.0
			if int(suck[0]) % 5 == 0 and is_instance_valid(hole):    # 星尘吸入粒子
				var pa: float = randf() * TAU
				var pp: Vector2 = c + Vector2(cos(pa), sin(pa)) * randf_range(120.0, 200.0)
				var dust := Sprite3D.new()
				dust.texture = VfxTex._make_fire_glow_tex()
				dust.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dust.shaded = false; dust.transparent = true
				dust.pixel_size = 0.004
				dust.modulate = Color(0.8, 0.6, 1.0, 0.85)
				dust.position = battle._world_pos(pp, randf_range(0.2, 0.9))
				battle._world.add_child(dust)
				var dtw = battle._reg_tween(); dtw.set_parallel(true)
				dtw.tween_property(dust, "position", battle._world_pos(c + dir * 20.0, 0.4), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				dtw.tween_property(dust, "modulate:a", 0.0, 0.4)
				dtw.chain().tween_callback(dust.queue_free)
		var boom := func() -> void:                                  # ④ 边界爆炸: 原伤害值一次性结算+携带者炸开
			var c3: Vector2 = start + dir * end_d
			battle._shake(0.12)
			battle._skill_ring(c3, Color(0.85, 0.7, 1.0, 0.9), 70.0)
			battle._skill_ring(c3, Color(0.6, 0.45, 1.0, 0.55), 170.0)
			var fl := Sprite3D.new()                                 # 紫白爆闪
			fl.texture = VfxTex._make_fire_glow_tex()
			fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fl.shaded = false; fl.transparent = true
			fl.pixel_size = (60.0 * battle.WS) / float(maxi(1, VfxTex._make_fire_glow_tex().get_width()))
			fl.modulate = Color(0.92, 0.8, 1.0, 1.0)
			fl.position = battle._world_pos(c3, 0.5)
			battle._world.add_child(fl)
			var ft = battle._reg_tween(); ft.set_parallel(true)
			ft.tween_property(fl, "pixel_size", fl.pixel_size * 3.2, 0.3)
			ft.tween_property(fl, "modulate:a", 0.0, 0.3)
			ft.chain().tween_callback(fl.queue_free)
			for k2 in range(12):                                     # 星尘四散
				var sa: float = TAU * float(k2) / 12.0 + randf() * 0.3
				var sd := Sprite3D.new()
				sd.texture = VfxTex._make_star_texture()
				sd.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sd.shaded = false; sd.transparent = true
				sd.pixel_size = 0.007
				sd.modulate = Color(0.9, 0.8, 1.0, 1.0)
				sd.position = battle._world_pos(c3, 0.5)
				battle._world.add_child(sd)
				var sdt = battle._reg_tween(); sdt.set_parallel(true)
				sdt.tween_property(sd, "position", battle._world_pos(c3 + Vector2(cos(sa), sin(sa)) * randf_range(90.0, 170.0), 0.1), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				sdt.tween_property(sd, "modulate:a", 0.0, 0.45)
				sdt.chain().tween_callback(sd.queue_free)
			var boomed: Array = []
			for cg3 in caught:                                       # 携带者: 吃伤+炸开
				var ob: Dictionary = cg3["o"]
				if not ob.get("alive", false): continue
				boomed.append(ob)
				battle._damage._apply_damage_from(uu, ob, battle._atk_dmg(uu, mult, ob, true), Color("#c9a0ff"))
				battle._knock_up(ob, c3, 6.6)
			for o3 in battle._targeting._enemies_of(uu):                               # 爆炸半径150码内其余敌也吃原伤害
				if not o3.get("alive", false) or boomed.has(o3): continue
				if (o3["pos"] as Vector2).distance_to(c3) > 150.0: continue
				battle._damage._apply_damage_from(uu, o3, battle._atk_dmg(uu, mult, o3, true), Color("#c9a0ff"))
			## ★虫洞消失 ⇒ 解锁龟能(设成当前时刻 = 立即到期, 与星波彗星同一写法)
			if uu.get("alive", false):
				uu["energy_lock_until"] = battle._t
			if is_instance_valid(hole): hole.queue_free()
		var tw = battle._reg_tween()
		tw.tween_method(step, 0.0, end_d, end_d / 140.0).set_trans(Tween.TRANS_LINEAR)   # 140码/s推进到边界
		tw.chain().tween_callback(boom)
	battle._pending_shots.append({"delay": 0.3, "fn": fire, "src": u})     # 蓄力0.3s→发射
