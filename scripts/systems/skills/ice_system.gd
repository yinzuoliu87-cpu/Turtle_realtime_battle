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
	for o in battle._targeting._enemies_of(u):
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
	battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, float([25, 40, 60][si]), o, true), Color("#bfe9ff"), 0.0, false, true)   # 魔法伤
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
	var t = battle._targeting._nearest_enemy(u)
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
	battle._damage._apply_damage_from(u, t, battle._resolve_dmg(u, float([40, 60, 100][si]), t, true), Color("#bfe9ff"), 0.0, false, true)
	t["spd_move_mult"] = 0.8; t["spd_aspd_mult"] = 0.9; t["spd_dbf_until"] = battle._t + 5.0
	_ice_burst(t["pos"])
	_frost_puff(t["pos"])
	battle._shake(0.06)
	battle._damage._knockback(u, t, 16.0)
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
## ═══ 冰柱层 (用户 2026-07-28 加强) ═══
## 每段普攻 +1 层, 上限 ICICLE_MAX。每层给【自身】+5% 攻速 / +1% 护甲 / +1% 魔抗,
## 并让【冰霜】范围 +20%、持续 +0.5 秒。
## ★"每路战斗结束刷新"是白送的: 换路时 dual_lane_flow._dl_clear_units() 会清场再重 spawn,
##   单位字典整个重建 → icicle 字段天然归零, 不用另写重置(同 blood 天然每场重置的道理)。
const ICICLE_MAX := 20
const ICICLE_ASPD := 0.05      # 每层 +5% 攻速(3%→5%·用户2026-07-30 第六轮: 攒满20层 24.4→21.7 秒, 33秒内普攻 28→34 次)
const ICICLE_DEFMR := 0.01     # 每层 +1% 护甲 & 魔抗
const ICICLE_FROST_RADIUS := 0.20   # 每层 冰霜半径 +20%
const ICICLE_FROST_SEC := 0.5       # 每层 冰霜持续 +0.5 秒
const FREEZE_DMG := 2.5             # 冰封: ×ATK 魔法(常驻·用户2026-07-28: 原0.6常态/2.5满层→统一2.5)
const FREEZE_STUN_SEC := 2.5        # 冰封: 满 ICICLE_MAX 层冰柱时额外眩晕秒数

## 攒一层冰柱并把属性差量结算上去(只加增量, 不重复叠)
func _ice_gain_icicle(u: Dictionary) -> void:
	var n: int = int(u.get("icicle", 0))
	if n >= ICICLE_MAX:
		return
	u["icicle"] = n + 1
	# 攻速: atk_interval 越小越快 → 用总层数换算目标间隔, 避免逐层相乘的浮点漂移
	var base_iv: float = float(u.get("_icicle_base_iv", u.get("atk_interval", 1.0)))
	u["_icicle_base_iv"] = base_iv
	u["atk_interval"] = base_iv / (1.0 + ICICLE_ASPD * float(u["icicle"]))
	# 双抗: 按【开局基准】的百分比加, 同样只算总量
	var bd: float = float(u.get("_icicle_base_def", u.get("def", 0.0)))
	var bm: float = float(u.get("_icicle_base_mr", u.get("mr", 0.0)))
	u["_icicle_base_def"] = bd
	u["_icicle_base_mr"] = bm
	u["def"] = bd * (1.0 + ICICLE_DEFMR * float(u["icicle"]))
	u["mr"] = bm * (1.0 + ICICLE_DEFMR * float(u["icicle"]))


func _sk_ice_frost(u: Dictionary, tgt: Dictionary) -> void:      # 寒冰龟·冰霜 ✅ (圆形冰霜场: 5秒/每0.5秒一跳/圈内-25%魔抗)
	var center: Vector2 = u["pos"]
	if tgt != null and tgt.get("alive", false):
		center = tgt["pos"]
	else:
		var es = battle._targeting._pick_enemies_of(u)
		if not es.is_empty(): center = es[0]["pos"]
	# 冰柱层加强(用户2026-07-28): 每层 半径+20% / 持续+0.5秒 → 跳数随持续一起涨(恒每0.5秒一跳)
	var ic: int = int(u.get("icicle", 0))
	var radius: float = 150.0 * (1.0 + ICICLE_FROST_RADIUS * float(ic))
	var secs: float = 5.0 + ICICLE_FROST_SEC * float(ic)
	var ticks: int = maxi(1, roundi(secs / 0.5))
	_ice_frost_field(center, radius, secs)   # ★领域底层只建【一次】(旧版每跳重画范围环 → 闪烁)
	var tw = battle._reg_tween()
	for i in range(ticks):
		tw.tween_callback(_ice_frost_tick.bind(u, center, radius))
		tw.tween_interval(0.5)

func _ice_frost_tick(u: Dictionary, center: Vector2, radius: float) -> void:
	_ice_frost_rain(center, radius)   # 落冰(范围环已由 _ice_frost_field 常驻, 这里不再每跳重画)
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		if o["pos"].distance_to(center) <= radius:
			battle._damage._buff(o, "mr", -0.25, true, 0.65)   # 圈内 -25%魔抗(刷新, 略>0.5s跳间隔)
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 0.25, o, true), Color("#bfe9ff"))   # 每跳 0.18→0.25A(用户2026-07-30 第六轮·寒冰整只 10.8% 垫底)

## ══ 冰霜领域视觉 (2026-07-29 重做·用户「那种冰霜砸下来怎么做」) ══
##
## 旧版的问题(五条, 逐条对着改的):
##   ① 不是"砸"是"平移" —— tween 没设 EASE_IN, 匀速下滑, 没有重力感
##   ② 冰锥尖朝上 —— 用的 skills/ice-spike.png 是向上的水晶, 掉下来屁股朝地
##   ③ 落地什么都没有 —— 只是淡出, 没有碎裂/霜痕/震动
##   ④ 固定 5 片 —— 满 20 层冰柱半径 750 码时, 5 片撒在 5 倍大的圈里基本看不见
##   ⑤ 范围环每 0.5 秒重画 —— 闪烁, 不像一个稳定存在的"领域"
##
## 新版分五层(素材全新生成·未复用):
##   ① 领域底层 frost-field-ground.png —— 只在【首跳】建一次, 缓慢自转+呼吸, 跟着持续时长活
##   ② 预警      落点先出现小霜圈, 0.15 秒后冰锥才到
##   ③ 下落      frost-icicle-fall.png (尖朝下) 从 3.5 高加速坠落 (TRANS_QUAD/EASE_IN)
##   ④ 命中      GPU 冰屑粒子爆散 + 白蓝闪光 + 地面冲击环 + 极轻震屏
##   ⑤ 残留      地面霜痕渐隐
const FROST_ICICLE := "res://assets/sprites/vfx/frost-icicle-fall.png"
const FROST_FIELD := "res://assets/sprites/vfx/frost-field-ground.png"
const FROST_CHIP := "res://assets/sprites/vfx/frost-chip.png"

## 一跳的视觉: 按半径决定落几根, 每根独立预警→坠落→命中→残留.
func _ice_frost_rain(center: Vector2, radius: float) -> void:
	# ④ 片数跟半径走(旧版恒 5): 150码→5 根, 750码→16 根. 上限 16 防帧率.
	var n: int = clampi(3 + int(radius / 60.0), 5, 16)
	for i in range(n):
		# 极坐标均匀采样(旧版是方形取样再 continue 掉圈外的, 实际根数经常不足)
		var a: float = battle._juice_rng.randf() * TAU
		var r: float = sqrt(battle._juice_rng.randf()) * radius
		var at: Vector2 = center + Vector2(cos(a), sin(a)) * r
		var delay: float = battle._juice_rng.randf() * 0.30      # 错峰, 不要齐刷刷一起落
		battle._pending_shots.append({"delay": delay, "fn": _frost_icicle_drop.bind(at)})

## 领域底层(只在首跳建一次): 地面霜盘, 缓慢自转 + 呼吸, secs 秒后淡出.
func _ice_frost_field(center: Vector2, radius: float, secs: float) -> void:
	var tex: Texture2D = load(FROST_FIELD)
	if tex == null or battle._world == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED           # ★贴地不朝相机 —— 它是"地面上的一层霜"
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (radius * 2.0 * battle.WS) / float(maxi(1, tex.get_width()))
	spr.position = battle._world_pos(center, 0.02)
	spr.rotation_degrees = Vector3(-90.0, 0.0, 0.0)             # 平铺到地面
	spr.modulate = Color(0.72, 0.92, 1.0, 0.0)
	battle._world.add_child(spr)
	var tin = battle._reg_tween()
	tin.tween_property(spr, "modulate:a", 0.42, 0.35)
	# 缓慢自转(整个持续时长转 40 度) + 呼吸
	var trot = battle._reg_tween()
	trot.tween_property(spr, "rotation_degrees:y", 40.0, secs)
	var tbr = battle._reg_tween()
	tbr.set_loops(maxi(1, int(secs / 1.6)))
	tbr.tween_property(spr, "modulate:a", 0.30, 0.8)
	tbr.tween_property(spr, "modulate:a", 0.42, 0.8)
	var tout = battle._reg_tween()
	tout.tween_interval(maxf(0.1, secs - 0.4))
	tout.tween_property(spr, "modulate:a", 0.0, 0.4)
	tout.tween_callback(spr.queue_free)

## 一根冰锥的完整生命: 预警圈 → 加速坠落 → 命中(粒子+闪光+环+震) → 霜痕残留.
func _frost_icicle_drop(at: Vector2) -> void:
	if battle._world == null:
		return
	# ② 预警: 落点先出现一个小霜圈(0.15 秒), 给"要被砸了"的预期
	battle._skill_ring(at, Color(0.55, 0.85, 1.0, 0.30), 34.0)
	var tex: Texture2D = load(FROST_ICICLE)
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (54.0 * battle.WS) / float(maxi(1, tex.get_height()))
	spr.modulate = Color(0.85, 0.96, 1.0, 0.95)
	var ground: Vector3 = battle._world_pos(at, 0.06)
	spr.position = ground + Vector3(0.0, 3.5, 0.0)              # ③ 起点抬高(旧版 2.2)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.tween_interval(0.15)                                     # 等预警圈
	# ★重力感: TRANS_QUAD + EASE_IN, 0.22 秒(旧版线性 0.35 秒)
	tw.tween_property(spr, "position", ground, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if is_instance_valid(spr):
			spr.queue_free()
		_frost_impact(at))

## ④ 命中三件套: GPU 冰屑粒子 + 白蓝闪光 + 地面冲击环 + 极轻震屏; ⑤ 再留一小片霜痕.
func _frost_impact(at: Vector2) -> void:
	if battle._world == null:
		return
	_frost_chips(at)                                            # 粒子
	var g = battle._glow_bb(at, 0.35, 46.0, Color(0.80, 0.95, 1.0, 0.85))   # 闪光
	if g != null:
		var tg = battle._reg_tween()
		tg.set_parallel(true)
		tg.tween_property(g, "scale", Vector3.ONE * 2.1, 0.14)
		tg.tween_property(g.material_override, "albedo_color", Color(0.80, 0.95, 1.0, 0.0), 0.16)
		tg.chain().tween_callback(g.queue_free)
	battle._skill_ring(at, Color(0.70, 0.92, 1.0, 0.55), 58.0)  # 地面冲击环
	battle._shake(0.012)                                        # 极轻(一跳最多 16 根, 不能重)
	_frost_scar(at)                                             # 残留霜痕

## GPU 冰屑粒子: 向上+外扩, 重力回落. 照 battle_vfx._impact_particles 的结构改配色/形状.
func _frost_chips(at: Vector2) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 9
	ps.lifetime = 0.42
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 78.0
	mat.initial_velocity_min = 1.8
	mat.initial_velocity_max = 4.2
	mat.gravity = Vector3(0, -11.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.25
	mat.angular_velocity_min = -220.0
	mat.angular_velocity_max = 220.0
	mat.color = Color(0.82, 0.95, 1.0, 1.0)
	ps.process_material = mat
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var chip: Texture2D = load(FROST_CHIP)
	if chip != null:
		dm.albedo_texture = chip
	dm.albedo_color = Color(0.88, 0.97, 1.0, 1.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.13, 0.13)
	qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = battle._world_pos(at, 0.35)
	battle._world.add_child(ps)
	ps.emitting = true
	var tw = battle._reg_tween()
	tw.tween_interval(ps.lifetime + 0.15)
	tw.tween_callback(ps.queue_free)

## ⑤ 残留: 落点一小片霜痕, 0.9 秒渐隐(复用领域那张图缩小).
func _frost_scar(at: Vector2) -> void:
	var tex: Texture2D = load(FROST_FIELD)
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (72.0 * battle.WS) / float(maxi(1, tex.get_width()))
	spr.position = battle._world_pos(at, 0.03)
	spr.rotation_degrees = Vector3(-90.0, battle._juice_rng.randf() * 360.0, 0.0)
	spr.modulate = Color(0.80, 0.94, 1.0, 0.55)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.tween_interval(0.25)
	tw.tween_property(spr, "modulate:a", 0.0, 0.65)
	tw.tween_callback(spr.queue_free)
func _sk_ice_freeze(u: Dictionary, tgt: Dictionary) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	var stun: float = FREEZE_STUN_SEC if int(u.get("icicle", 0)) >= ICICLE_MAX else 0.0
	battle._ballistics._fire_ice_shard(u, tgt, battle._atk_dmg(u, FREEZE_DMG, tgt, true), stun)
	battle._damage._heal(u, float(u.get("def", 0.0)) + float(u.get("mr", 0.0)))

func _sk_ice_team_shield(u: Dictionary) -> void:               # 寒冰龟·团队护盾(用户2026-07-11重设计·120龟能): 全体友军5%施法者maxHp冰霜盾4秒·盾破/到期爆炸250码1×ATK魔法; 独狼(无其他友军)盾×4·爆炸5×ATK
	var others = battle._targeting._allies_of(u, false)                         # 不含自己
	var solo: bool = others.is_empty()
	var shield_amt: float = u["maxHp"] * (0.20 if solo else 0.05)   # 5%施法者maxHp; 独狼×4=20%
	var boom_mult: float = 5.0 if solo else 1.0                     # 爆炸1×ATK; 独狼5×ATK
	for o in battle._targeting._allies_of(u):                                    # 含自己=全体友军
		_frost_shield_burst(o)                                 # 若已挂上一发未爆→先结算(防覆盖丢爆裂)
		battle._damage._grant_shield(o, shield_amt, 4.0)                      # 冰霜盾·4秒
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
		for o in battle._targeting._enemies_of(src):
			if o.get("alive", false) and o["pos"].distance_to(c) <= 250.0:
				battle._damage._apply_damage_from(src, o, battle._atk_dmg(src, boom, o, true), Color("#bfe9ff"))   # boom×ATK 魔法(1或5)
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
