class_name SpearEqVfx
extends MaskEqVfx
## spear_eq_vfx.gd —— 长矛羁绊【百夫长】+ 10 件长矛 + 筹码的演出层(2026-11-26 · 方案书 20261126 / 20261126b)。结算全在 sim 侧, 这里只画。
## 继承面具演出层拿帧条工具(_strip / _tick_mfx)与炸弹层的 _ring / _anim。
## 素材来源见 tools/assetgen/pack_spear_chip_art.py 头注(全部 PixelLab 生成, 没有照参考)。
##
## 分段:
##   百夫长登场(11-26 夜重做, 用户「召唤物的登场，登场动画…别敷衍了」):
##     0 ~ 0.7 秒  落点先打下一道金色光柱(逐帧闪动), 地上影子随高度由小变大; 百夫长举着盾从 9 米高处加速落下(下落途中把盾举起)
##     0.7 秒落地  金色冲击环 + 尘土裂地(逐帧, 不是程序圆环)+ 重震屏; 全场敌人同一步被击飞(sim 在落地那一步结算, 画面对得上)
##   普攻        刺(attack 帧条, 命中帧见 AttackHits); 第 4 下掷矛: 掷矛帧条 + 一根罗马重标枪按 sim 位置飞
##   龟甲阵      举盾帧条放慢到 3 秒; 3 档的连刺 = 脚下一圈小闪; 放盾横扫 = 一圈大环; 4 档骑兵 = 奔马帧条沿 sim 路线跑
const V := "res://assets/sprites/vfx/"
const CENT_SHEETS := {"attack": "eq-centurion-attack.png", "throw": "eq-centurion-throw.png", "shield": "eq-centurion-shield.png", "brace": "eq-centurion-brace.png", "rise": "eq-centurion-rise.png", "sweep": "eq-centurion-sweep.png"}
const CENT_FW := 192   # 11-27 换 PixelLab「角色」流程新形象: 192 方帧(人约 127 像素高)
const LAND_H := 9.0
var _cent_cache := {}
var _lands: Array = []       # {u, t}
var _spear_nodes: Array = [] # {s, node}
var _cav_nodes: Array = []   # {c, node}


func _cent_sd(key: String, fps: float) -> Dictionary:
	if not _cent_cache.has(key):
		var p: String = V + str(CENT_SHEETS[key])
		var sd := {}
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			sd = battle._sprite_dict_from(t, {"frames": (t.get_width() / CENT_FW) * (t.get_height() / CENT_FW), "frameW": CENT_FW, "frameH": CENT_FW, "duration": 800}, false)   # 42 帧的举盾帧条排成 2 行(贴图最大边 ≤ 4096)
		_cent_cache[key] = sd
	var out: Dictionary = (_cent_cache[key] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func _cent_play(p: Dictionary, key: String, fps: float) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _cent_sd(key, fps)
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, "cent_" + key, true)


func _proj(tex: String, from: Vector2, dir: Vector2, len_m: float) -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(V + tex):
		return null
	var t: Texture2D = load(V + tex)
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = len_m / float(t.get_width())
	s.position = battle._world_pos(from, 1.0)
	battle._world.add_child(s)
	_orient_to(s, dir)
	return s


# ── 百夫长 ──
## 登场(11-27 用户, 方案书附录 B): 0 秒落点亮出预警标记圈 → CENT_PLANT_T 他自己的长矛从高空直插圈心 → 最后 CENT_DROP_SEC 本人从画面外高空砸下(残影)
##   → 落地那一步(cent_impact)裂坑 + 震屏 + 整岛地裂。旧的通用金光柱删了(用户「这个落下的这个光特效，你是不是偷偷复用了什么东西」)。
const CENT_MARKER_M := 20.0     # 预警标记圈直径(米; 4 → 9 → 14 → 20, 用户 11-27 三次「再大点啊」)
const CENT_TRAIL_M := 7.0       # 下坠光尾长(米)
const CENT_DROP_H := 14.0       # 本人从多高砸下来(米; 刚好在画面上沿外: 30 米时先慢后快、进画面只剩最后一两帧, 11-27 录像量过)
const CENT_DROP_SEC := 0.5      # 砸下来用时(落地前最后这段; 约最后 0.2 秒在画面里, 带残影)
const CENT_PLANT_T := 0.35      # 长矛插进圈心的时刻
const CENT_PLANT_FALL := 0.12   # 长矛从高空落下用时
const CENT_PLANT_H0 := 16.0     # 长矛从多高落(米)
const CENT_PLANT_M := 4.2       # 插着的长矛高(米; 2.6 时全景下只剩一根细线)
const CENT_PLANT_BURY := 0.35   # 矛尖扎进地里多深(米)

## 登场分层(11-27, 研究稿 R 落地插矛 / R 冲击 / R 下坠彗星)
const DOWN := Vector3(0.0, 0.0, -PI * 0.5)   # 本地 +X 转成朝下(抛物面尖端朝地, 口朝上)


## 一组同形锥(尖端朝下): [着色器, 长, 口径, 往后错开(米), 参数, 绘制顺序]
func _cone_set(spec: Array, pos: Vector3, rot: Vector3) -> Array:
	var parts: Array = []
	for sp in spec:
		var prm: Dictionary = (sp[4] as Dictionary).duplicate()
		prm["prog"] = 0.0
		prm["fade"] = 1.0
		var mi := Cent3dVfx.node(battle._world, Cent3dVfx.gen_shock(float(sp[1]), float(sp[2]), 8, 20), sp[0], CONE_SP, prm, int(sp[5]))
		mi.rotation = rot
		mi.position = pos
		parts.append({"node": mi, "off": float(sp[3])})
	return parts


func _cone_set_tick(parts: Array, pos: Vector3, axis: Vector3, t: float, fade: float, vis: bool) -> void:
	for p in parts:
		var n = p["node"]
		if n == null or not is_instance_valid(n):
			continue
		(n as MeshInstance3D).visible = vis
		(n as MeshInstance3D).position = pos - axis * float(p["off"])
		var m: ShaderMaterial = (n as MeshInstance3D).material_override
		m.set_shader_parameter("prog", t * 8.0)
		m.set_shader_parameter("fade", fade)


func _cone_set_free(parts) -> void:
	if parts is Array:
		for p in parts:
			_free(p["node"])


## 连续冒的粒子(星尘 / 星点): 方向 = 世界方向
func _stream_ps(pos: Vector3, dir: Vector3, amount: int, life: float, v0: float, v1: float, spread: float, sz: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = life
	ps.randomness = 0.7
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0.0, -0.5, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _gold_ramp(0.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(sz)
	ps.position = pos
	battle._world.add_child(ps)
	return ps


func _stop_ps(ps) -> void:
	if ps != null and is_instance_valid(ps):
		(ps as GPUParticles3D).emitting = false
		_aegis_junk.append({"node": ps, "left": 1.2})


## 一次性迸射(碎石用彩色贴图 + 普通混合; 星尘用金色光点 + 叠加)
func _burst_ps(pos: Vector3, amount: int, life: float, v0: float, v1: float, spread: float, grav: float, sz: float, rock: bool) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = life
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.randomness = 0.8
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0.0, grav, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.8
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	if rock:
		var gd := Gradient.new()
		gd.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
		gd.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var gt := GradientTexture1D.new()
		gt.gradient = gd
		pm.color_ramp = gt
		var qm := QuadMesh.new()
		qm.size = Vector2(sz, sz)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = Cent3dVfx.tex("rock.png")
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		qm.material = sm
		ps.draw_pass_1 = qm
	else:
		pm.color_ramp = _gold_ramp(1.0)
		ps.draw_pass_1 = _mote_quad(sz)
	ps.process_material = pm
	ps.position = pos
	ps.emitting = true
	battle._world.add_child(ps)
	_aegis_junk.append({"node": ps, "left": life + 0.4})


## 贴地的单张光(亮光 / 暗光垫底): 统一推帧最后 0.15 秒淡掉删除
func _ground_glow(pos2: Vector2, size_m: float, col: Color, life: float) -> void:
	var s := _strip(Cent3dVfx.AT + "glow.png", 1, battle._world_pos(pos2, 0.06), size_m, 0.0, false, life, true, null, 0.0)
	if s != null:
		s.modulate = col


## 一圈往外推的环(土浪 / 余震): 半径 r 米, rd 秒扩完
func _ring_wave(pos2: Vector2, r: float, rd: float, mid: Color, hot: Color, delay: float) -> void:
	if not _ok():
		return
	var ring := Cent3dVfx.node(battle._world, Cent3dVfx.gen_fan(0.1, r, TAU, 0.08, 56, 6), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "open": 1.0, "shell_k": 0.0, "fade": 0.0,
		 "col_mid": Vector3(mid.r, mid.g, mid.b), "col_hot": Vector3(hot.r, hot.g, hot.b)}, 0)
	ring.position = battle._world_pos(pos2, 0.0)
	_stabs.append({"parts": [], "bills": [], "ring": ring, "t": -delay, "life": rd + delay, "rd": rd, "p0": Vector3.ZERO, "d3": Vector3.ZERO, "dist": 0.0})


func cent_land(p: Dictionary, sec: float) -> void:
	p["_slam_voff"] = Vector3(0.0, CENT_DROP_H, 0.0)   # 先在画面外的高空
	var mk := _strip(V + "spear-cent-marker.png", 8, battle._world_pos(Vector2(p["pos"]), 0.05), CENT_MARKER_M, 10.0, true, sec + 0.05, true, null, 0.0)
	var sp: Sprite3D = null
	if _ok() and ResourceLoader.exists(V + "spear-cent-plant.png"):
		sp = Sprite3D.new()
		sp.texture = load(V + "spear-cent-plant.png")
		sp.shaded = false
		sp.transparent = true
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sp.pixel_size = CENT_PLANT_M / float(sp.texture.get_height())
		sp.offset = Vector2(0.0, float(sp.texture.get_height()) * 0.5)   # 原点 = 矛尖(底边)
		sp.visible = false
		battle._world.add_child(sp)
	var tr := _strip(V + "spear-cent-trail.png", 6, battle._world_pos(Vector2(p["pos"]), CENT_DROP_H), CENT_TRAIL_M, 16.0, true, sec, false, null, 0.0)
	if tr != null:
		tr.visible = false   # 开始砸下那一刻才亮(下面 tick 里跟着本体)
	var comet: Array = _cone_set([
		[CONE_MIX, 3.4, 1.05, 0.0, {"col": Vector4(0.2, 0.06, 0.02, 0.5), "rim_mix": 0.45, "tail": 0.55, "apex": 0.2}, 10],
		[CONE_MIX, 2.8, 0.85, 0.0, {"col": Vector4(1.0, 0.74, 0.25, 0.6), "rim_mix": 0.7, "tail": 0.5, "apex": 1.0}, 11],
		[CONE_ADD, 3.4, 0.95, 0.0, {"col": Vector4(0.85, 0.28, 0.1, 0.55), "rim_mix": 0.5, "tail": 0.45, "apex": 0.6}, 12],
		[CONE_MIX, 6.5, 1.15, 0.3, {"col": Vector4(1.0, 0.95, 0.8, 0.8), "rim_mix": 0.0, "tail": 0.6, "apex": 0.0, "streaks": 20.0}, 12],
	], battle._world_pos(Vector2(p["pos"]), CENT_DROP_H), DOWN) if _ok() else []
	_cone_set_tick(comet, Vector3.ZERO, Vector3.DOWN, 0.0, 1.0, false)
	_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec), "mk": mk, "sp": sp, "tr": tr, "planted": false, "ghost": 0.0,
		"comet": comet, "dust": null, "plant_fx": [], "plant_ps": null})
	_cent_play(p, "brace", 42.0 / maxf(0.1, sec))   # 举盾下蹲的姿势砸下来, 落地时正好举满


## 下落残影: 复制本体此刻这一帧, 金色半透明, 0.15 秒淡掉
func _drop_ghost(u: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var src: Sprite3D = spr
	var g := Sprite3D.new()
	g.texture = src.texture
	g.hframes = src.hframes
	g.vframes = src.vframes
	g.frame = src.frame
	g.pixel_size = src.pixel_size
	g.offset = src.offset
	g.flip_h = src.flip_h
	g.billboard = src.billboard
	g.shaded = false
	g.transparent = true
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.modulate = Color(1.0, 0.85, 0.45, 0.5)
	battle._world.add_child(g)
	g.global_position = src.global_position
	## 登记进 _mfx 由统一推帧淡出删除(直播录得到; 不登记则 _fade_out 管不到, 11-27 录像里留成一根红柱)
	_mfx.append({"node": g, "nf": maxi(1, g.hframes * g.vframes), "fps": 0.0, "t": 0.0, "life": 0.15, "loop": false, "follow": null, "h": 0.0, "hold": g.frame})


func cent_impact(p: Dictionary) -> void:
	p["_slam_voff"] = Vector3.ZERO
	_cent_play(p, "rise", 12.0 / SpearSynergySystem.RISE_SEC)   # 砸地后蹲住 → 撑起 → 站直(11-27 用户「应该是有个蹲起…然后站起身，然后再移动」), 播完自动回待机
	var d_m: float = 1200.0 * float(battle.WS)   # 11-27 第二次「裂坑圈可以大一倍」: 600 → 1200 码 ≈ 29 米(岛宽约 38 米) #   # 落地裂坑直径(11-27 用户「下坠的那个地裂的这个圈还可以再大点啊」: 380 → 600 码 ≈ 14.4 米, 与预警圈同大)
	_strip(V + "spear-cent-impact.png", 8, battle._world_pos(Vector2(p["pos"]), 0.07), d_m, 14.0, false, 8.0 / 14.0, true, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	## 研究稿 R 冲击: 亮闪 → 暗光垫底 → 土浪环 + 两道余震环 + 碎石 / 星尘迸射
	var c2 := Vector2(p["pos"])
	_ground_glow(c2, 12.0, Color(0.12, 0.05, 0.02, 0.6), 0.5)
	_ground_glow(c2, 8.0, Color(1.0, 0.85, 0.5, 1.0), 0.18)
	_ring_wave(c2, 9.0, 0.55, Color(0.55, 0.4, 0.25), Color(0.85, 0.72, 0.5), 0.0)       # 土浪
	_ring_wave(c2, 6.5, 0.25, Color(1.0, 0.62, 0.14), Color(1.0, 0.95, 0.8), 0.0)        # 余震环 1
	_ring_wave(c2, 13.0, 0.35, Color(1.0, 0.62, 0.14), Color(1.0, 0.95, 0.8), 0.08)      # 余震环 2
	if _ok():
		_burst_ps(battle._world_pos(c2, 0.3), 40, 0.9, 5.0, 10.0, 70.0, -14.0, 0.26, true)    # 碎石
		_burst_ps(battle._world_pos(c2, 0.5), 60, 0.8, 3.0, 7.0, 60.0, -3.0, 0.13, false)     # 星尘
	_island_cracks(Vector2(p["pos"]))   # 整座岛的地面一起裂开(11-27 用户「应该是整个地面都出现全部地裂呀」)


## 登场砸地 = 整座岛的地面一起裂开: 从落点往四面八方 ISLAND_RAYS 条主裂缝一直裂到岛边, 每条随机分出岔缝; 不按敌人位置走。
##   与击飞同一步全部出现(不做往外蔓延, 画面不晚于结算), 之后金光褪去、暗缝合上(帧条 8 帧 @8 = 1 秒)。
##   一段裂缝帧 128×28(两端等高可拼), 宽 w 米 ⇒ 一段长 w × 128 / 28 米; 碰到岛边的最后一段按剩余长度缩短、变细收尾。
##   随机数用本地的(按落点播种): 纯演出, 不碰对局随机流。
const ISLAND_RAYS := 12
const CRACK_MAIN_W := 0.85   # 主裂缝宽(米)
const CRACK_BR_W := 0.5      # 岔缝宽(米)
const CRACK_FPS := 8.0


func _island_cracks(c: Vector2) -> void:
	if not _ok() or not ResourceLoader.exists(V + "spear-cent-crack.png"):
		return
	var t: Texture2D = load(V + "spear-cent-crack.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(c.x) * 131.0 + absf(c.y) * 7.0) + 1
	for i in range(ISLAND_RAYS):
		var base: float = TAU * float(i) / float(ISLAND_RAYS) + rng.randf_range(-0.15, 0.15)
		_crack_ray(t, rng, c, base, CRACK_MAIN_W, 12, true)


func _crack_ray(t: Texture2D, rng: RandomNumberGenerator, start: Vector2, base: float, w: float, max_n: int, branch: bool) -> void:
	var pos: Vector2 = start
	var seg_px: float = w * 128.0 / 28.0 / float(battle.WS)
	for k in range(max_n):
		var ang: float = base + rng.randf_range(-0.35, 0.35)
		var dir := Vector2(cos(ang), sin(ang))
		var nxt: Vector2 = pos + dir * seg_px
		if not ArenaShape.in_rect_shape(nxt, battle.ARENA, 6.0):
			for f in [0.7, 0.45, 0.25]:   # 岛边: 最后一段缩短变细收尾
				var q: Vector2 = pos + dir * seg_px * f
				if ArenaShape.in_rect_shape(q, battle.ARENA, 6.0):
					_crack_piece(t, rng, pos, q, w * f)
					break
			return
		_crack_piece(t, rng, pos, nxt, w)
		if branch and rng.randf() < 0.4:
			var side: float = 1.0 if rng.randf() < 0.5 else -1.0
			_crack_ray(t, rng, nxt, ang + side * rng.randf_range(0.5, 0.95), CRACK_BR_W, 3, false)
		pos = nxt


## 一段裂缝: 贴地帧条, 宽 w 米(一段长 = w × 128 / 28), 从 a 铺到 b
func _crack_piece(t: Texture2D, rng: RandomNumberGenerator, a: Vector2, b: Vector2, w: float) -> void:
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = 8
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.no_depth_test = false
	s.render_priority = -1   # 贴地的先画, 单位压在上面(同 _strip flat)
	s.pixel_size = w / 28.0
	s.flip_v = rng.randf() < 0.5   # 同一段裂纹不连着重复
	var w3: Vector3 = battle._world_pos(b, 0.0) - battle._world_pos(a, 0.0)
	s.position = battle._world_pos((a + b) * 0.5, 0.06)
	s.rotation.y = atan2(-w3.z, w3.x)
	battle._world.add_child(s)
	_mfx.append({"node": s, "nf": 8, "fps": CRACK_FPS, "t": 0.0, "life": 8.0 / CRACK_FPS, "loop": false, "follow": null, "h": 0.0})


## 普攻(11-27 用户「普攻也没有特效」): 刺出那一下(sim 结算同一步)从矛尖朝目标射出一道金白突刺气劲(逐帧: 矛尖闪 → 光尾拉长 → 碎成火星),
##   2 档起贯穿 ⇒ 气劲一路穿到目标身后(长度 = 结算的贯穿线); 目标身上迸火星
const CENT_TIP_H := 1.3     # 矛尖离地高(米, 新画的百夫长平端长矛的高度)


## 普攻矛刃光叠加层: 一只百夫长一个节点, 首次普攻时建; 每帧跟本体同帧号 / 位置 / 朝向 / 尺寸, 只在本体播普攻帧条时显示
const CENT_GLOW_TEX := "res://assets/sprites/vfx/eq-centurion-attack-glow.png"
var _cent_glows: Array = []   # {u, node, mf}

func _cent_glow_on(u: Dictionary) -> void:
	for g in _cent_glows:
		if is_same(g["u"], u):
			return
	if not _ok() or not ResourceLoader.exists(CENT_GLOW_TEX):
		return
	var t: Texture2D = load(CENT_GLOW_TEX)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = maxi(1, t.get_width() / 192)
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	battle._world.add_child(s)
	_mfx.append({"node": s, "nf": s.hframes, "fps": 0.0, "t": 0.0, "life": 0.0, "loop": false, "follow": null, "h": 0.0, "hold": 0})
	_cent_glows.append({"u": u, "node": s, "mf": _mfx.back()})
	_tick_cent_glows()


func _tick_cent_glows() -> void:
	var keep: Array = []
	for g in _cent_glows:
		var n = g["node"]
		var u: Dictionary = g["u"]
		var spr = u.get("sprite", null)
		if n == null or not is_instance_valid(n) or not is_instance_valid(spr) or not u.get("alive", false):
			_free(n)
			continue
		var s: Sprite3D = n
		var src: Sprite3D = spr
		var tx = (u.get("anim_sd", {}) as Dictionary).get("tex", null)
		var on: bool = tx != null and (tx as Texture2D).resource_path.ends_with("eq-centurion-attack.png") and src.frame < s.hframes
		(g["mf"] as Dictionary)["hold"] = src.frame if on else 0
		s.frame = src.frame if on else 0
		s.modulate = Color(1.0, 1.0, 1.0, 1.0 if on else 0.0)
		s.pixel_size = src.pixel_size
		s.offset = src.offset
		s.flip_h = src.flip_h
		s.global_position = src.global_position
		keep.append(g)
	_cent_glows = keep


## 普攻冲击罩(11-27 第六轮, 用户「武器头部有一层冲击罩一样的冲击波…冲出去」): 刺到最远那一帧, 矛头外面裹两层 3D 激波罩
##   (Cent3dVfx.gen_shock 旋转抛物面 + cent_shock.gdshader), 沿真实刺击方向(朝目标)往前冲 CENT_SHOCK_DIST、边冲边张大, CENT_SHOCK_SEC 散掉
##   起点 = 命中帧矛尖(帧里 (21,161), 脚底 (96,191) ⇒ 立足点往前 75 像素、离地 30 像素, 按镜头的左右 / 上下轴换成世界坐标)
const CENT_IMP_FWD_PX := 75.0
const CENT_IMP_UP_PX := 30.0
const CENT_SHOCK_SEC := 0.34
const CENT_SHOCK_DIST := 2.0
const CENT_ARROW_M := 2.6     # 突刺气劲基准长(米): 定粗细; 实际长度 = 人身前 → 罩子头部
const CENT_ARROW_BACK := 1.0  # 箭尾在命中帧矛尖往回多少米(人身前一点)
const CENT_SHOCK_SPD := 16.0   # 冲击罩飞行速度(米/秒): 二档整条线(目标 + 260 码)约 0.6 秒
const CONE_MIX: Shader = preload("res://assets/shaders/cent_cone_mix.gdshader")
const CONE_ADD: Shader = preload("res://assets/shaders/cent_cone_add.gdshader")
const CONE_SP := ["prog", "fade"]
var _stabs: Array = []   # 普攻冲击罩 {parts, bills, ring, t, life, p0, d3, dist}
var _shocks: Array = []   # {node, mat, t, life, p0, d3, dist, s0, s1, spin}


func _shock(p0: Vector3, d3: Vector3, mesh: Mesh, params: Dictionary, life: float, dist: float, s0: Vector3, s1: Vector3, spin: float) -> void:
	if not _ok():
		return
	var mi := Cent3dVfx.node(battle._world, mesh, Cent3dVfx.SHOCK_SHADER, Cent3dVfx.SHOCK_SP, params, 10)
	var fl := Vector3(d3.x, 0.0, d3.z)
	var yaw: float = Cent3dVfx.yaw_of(Vector2(fl.x, fl.z).normalized()) if fl.length() > 0.001 else 0.0
	var pitch: float = atan2(d3.y, maxf(0.001, fl.length()))
	mi.rotation = Vector3(0.0, yaw, pitch)
	mi.position = p0
	mi.scale = s0
	_shocks.append({"node": mi, "mat": mi.material_override, "t": 0.0, "life": life, "p0": p0, "d3": d3.normalized(), "dist": dist, "s0": s0, "s1": s1, "spin": spin})


func _tick_shocks(delta: float) -> void:
	var keep: Array = []
	for s in _shocks:
		var n = s["node"]
		if n == null or not is_instance_valid(n):
			continue
		s["t"] = float(s["t"]) + delta
		var k: float = float(s["t"]) / float(s["life"])
		if k >= 1.0:
			_free(n)
			continue
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # 先快后慢
		(n as MeshInstance3D).position = Vector3(s["p0"]) + Vector3(s["d3"]) * float(s["dist"]) * e
		(n as MeshInstance3D).scale = (s["s0"] as Vector3).lerp(s["s1"] as Vector3, e)
		var mat: ShaderMaterial = s["mat"]
		mat.set_shader_parameter("prog", float(s["t"]) * float(s["spin"]))
		mat.set_shader_parameter("fade", 1.0 - smoothstep(0.45, 1.0, k))
		keep.append(s)
	_shocks = keep


func _cent_impact_dome(u: Dictionary, tg: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not _ok() or not is_instance_valid(spr):
		return
	var px: float = float((spr as Sprite3D).pixel_size)
	var fr: bool = bool((spr as Sprite3D).flip_h)   # 原画朝左; 翻转 = 朝右
	var base: Vector3 = (spr as Sprite3D).global_position
	var cb: Basis = battle._cam.global_transform.basis if battle.get("_cam") != null else Basis.IDENTITY   # 立绘是朝镜头的板: 帧里的左右 / 上下 = 镜头的 x / y 轴
	var tip: Vector3 = base + cb.x * (CENT_IMP_FWD_PX * px * (1.0 if fr else -1.0)) + cb.y * (CENT_IMP_UP_PX * px)
	if tg.is_empty():
		return
	## 朝敌人冲(11-27 用户「方向朝哪儿呢？你应该朝着敌人啊」): 地面方向 = 矛尖 → 目标; 二档起沿穿刺线再延 LINE_LEN(与结算同一条线)
	var tgp: Vector3 = battle._world_pos(Vector2(tg["pos"]), tip.y)
	var fl := Vector3(tgp.x - tip.x, 0.0, tgp.z - tip.z)
	var d3: Vector3 = fl.normalized() if fl.length() > 0.05 else Vector3(1.0 if fr else -1.0, 0.0, 0.0)
	var tier: int = int(u.get("_cent_tier", 1))
	var dist: float = fl.length() + (SpearSynergySystem.LINE_LEN * float(battle.WS) if tier >= 2 else 0.6)
	tip += d3 * 0.25   # 尖端略超出矛尖: 矛头罩在里面
	## 朝向压平: 去掉 75% 朝镜头 / 背镜头的分量(画面上的矛永远横着刺), 路线仍是 d3
	var camf := Vector3(cb.z.x, 0.0, cb.z.z).normalized() if Vector3(cb.z.x, 0.0, cb.z.z).length() > 0.01 else Vector3.BACK
	var d3v: Vector3 = d3 - camf * d3.dot(camf) * 0.75
	d3v = d3v.normalized() if d3v.length() > 0.2 else Vector3(cb.x.x, 0.0, cb.x.z).normalized() * (1.0 if fr else -1.0)
	var yaw: float = Cent3dVfx.yaw_of(Vector2(d3v.x, d3v.z))
	var w: Node3D = battle._world
	## 罩: 同一个抛物面叠 4 层 + 流光层(研究稿「方法」1–4): [着色器, 长, 口径, 起始缩放, 结束缩放, 往后错开(米), 参数, 绘制顺序]
	var spec: Array = [
		[CONE_MIX, 1.9, 0.62, 0.55, 1.35, 0.0, {"col": Vector4(0.22, 0.07, 0.02, 0.55), "rim_mix": 0.35, "tail": 0.5, "apex": 0.2}, 10],    # 暗层: 亮的下面垫一层深褐, 沙地上压得住
		[CONE_MIX, 1.5, 0.5, 0.5, 1.25, 0.0, {"col": Vector4(1.0, 0.72, 0.22, 0.6), "rim_mix": 0.7, "tail": 0.5, "apex": 0.9}, 11],       # 主亮层(短一点)
		[CONE_ADD, 1.9, 0.55, 0.5, 1.3, 0.0, {"col": Vector4(0.75, 0.25, 0.12, 0.55), "rim_mix": 0.5, "tail": 0.45, "apex": 0.6}, 12],    # 叠加发光中层
		[CONE_MIX, 1.9, 0.56, 0.5, 1.3, 0.0, {"col": Vector4(0.95, 0.35, 0.06, 0.4), "rim_mix": 0.2, "tail": 0.55, "apex": 0.3, "rings": 3.0}, 11],   # 流动填充(波纹往后退)
		[CONE_MIX, 2.6, 0.75, 0.55, 1.4, 0.15, {"col": Vector4(1.0, 0.95, 0.8, 0.8), "rim_mix": 0.0, "tail": 0.6, "apex": 0.0, "streaks": 22.0}, 12],   # 流光: 一条条往后飞
	]
	var parts: Array = []
	for sp in spec:
		var prm: Dictionary = (sp[6] as Dictionary).duplicate()
		prm["prog"] = 0.0
		prm["fade"] = 1.0
		var mi := Cent3dVfx.node(w, Cent3dVfx.gen_shock(float(sp[1]), float(sp[2]), 8, 24), sp[0], CONE_SP, prm, int(sp[7]))
		mi.rotation = Vector3(0.0, yaw, 0.0)
		parts.append({"node": mi, "s0": float(sp[3]), "s1": float(sp[4]), "off": float(sp[5])})
	## 头: 叠加光晕 + 十字星芒(研究稿 Missle Head Glow / leading star)
	var bills: Array = []
	for b in [["glow.png", 1.6, Color(1.0, 0.95, 0.8, 0.95), 13], ["xstar.png", 2.3, Color(1.0, 0.88, 0.6, 1.0), 14]]:
		var s := Sprite3D.new()
		s.texture = Cent3dVfx.tex(str(b[0]))
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.no_depth_test = true
		s.render_priority = int(b[3])
		s.modulate = b[2]
		s.pixel_size = float(b[1]) / float(s.texture.get_width())
		s.position = tip
		w.add_child(s)
		bills.append({"node": s, "col": b[2]})
	## 出手: 矛尖一圈垂直于刺击方向的径向冲击环(研究稿 Temp_Mesh 径向网格)
	var ring := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.05, 0.9, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "open": 1.0, "shell_k": 0.05}, 12)
	ring.position = tip
	ring.rotation = Vector3(0.0, yaw, PI * 0.5)   # 扇面本来平躺(XZ 面), 绕 Z 转 90° 立成垂直于刺击方向
	## 火花往前迸
	var ps := GPUParticles3D.new()
	ps.amount = 16
	ps.lifetime = 0.32
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.randomness = 0.7
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.0, 0.0)
	pm.spread = 22.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0.0, -4.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.1)
	ps.position = tip
	ps.rotation = Vector3(0.0, yaw, 0.0)
	ps.emitting = true
	w.add_child(ps)
	_aegis_junk.append({"node": ps, "left": 0.6})
	## 头部加强(11-27 第二轮「冲击到的头部…需要更多明显的特效」): 激波前沿亮环 + 外贴暗环(折射边) + 横向拉丝光 + 两侧往后甩的火花
	var yaw2: float = yaw
	var te := Cent3dVfx.tex("energy.png")
	var fr_dark := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.42, 1.0, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": te, "open": 1.0, "shell_k": 0.55, "col_mid": Vector3(0.18, 0.08, 0.03), "col_hot": Vector3(0.25, 0.12, 0.05)}, 11)
	var fr_hot := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.2, 0.62, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": te, "open": 1.0, "shell_k": 0.62, "col_mid": Vector3(1.0, 0.8, 0.4), "col_hot": Vector3(1.0, 1.0, 0.95)}, 13)
	for fnode in [fr_dark, fr_hot]:
		(fnode as Node3D).rotation = Vector3(0.0, yaw2, PI * 0.5)
		(fnode as Node3D).position = tip
	var streak := Sprite3D.new()   # 横向拉丝光
	streak.texture = Cent3dVfx.tex("xstar.png")
	streak.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	streak.shaded = false
	streak.transparent = true
	streak.no_depth_test = true
	streak.render_priority = 14
	streak.modulate = Color(1.0, 0.92, 0.7, 0.9)
	streak.pixel_size = 2.6 / float(streak.texture.get_width())
	streak.position = tip
	w.add_child(streak)
	bills.append({"node": streak, "col": streak.modulate, "sx": 3.2})
	var spray := GPUParticles3D.new()
	spray.amount = 36
	spray.lifetime = 0.28
	spray.randomness = 0.7
	spray.local_coords = false
	spray.fixed_fps = 30
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(-1.0, 0.0, 0.0)
	spm.spread = 38.0
	spm.initial_velocity_min = 2.0
	spm.initial_velocity_max = 5.0
	spm.gravity = Vector3(0.0, -3.0, 0.0)
	spm.scale_min = 0.6
	spm.scale_max = 1.3
	spm.color_ramp = _gold_ramp(1.0)
	spray.process_material = spm
	spray.draw_pass_1 = _mote_quad(0.09)
	spray.position = tip
	spray.rotation = Vector3(0.0, yaw2, 0.0)
	w.add_child(spray)
	## 突刺气劲: 箭尾固定在人身前(命中帧矛尖往回 CENT_ARROW_BACK 米), 箭头贴着罩子头部, 长度跟着拉长(粗细不变)
	var tail: Vector3 = tip - d3 * CENT_ARROW_BACK
	var arrow := _dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(u["pos"]), Vector2(d3.x, d3.z), CENT_ARROW_M, 24.0, 0.0, tip.y)
	if arrow != null:
		(_mfx.back() as Dictionary)["loop"] = true   # 帧条循环, 跟罩子同生同灭(_stab_free 删)
		(_mfx.back() as Dictionary)["nf"] = 6   # 只循环前 6 帧: 第 7 帧是收尾几乎全空, 循环到它箭会闪没
		arrow.render_priority = 13   # 画在罩子各层(10–12)上面: 箭头在罩子里看得清
		_arrow_span(arrow, tail, tip)
	## 热扭曲 11-27 试过读屏幕纹理(hint_screen_texture): 兼容渲染器 + 战场在 SubViewport 里, 3D 特效读到的是一片平滑色、没有地面画面
	##   (强制 mip 0 也一样; 探针: 平移 + 染红后整块无砖纹), 扭曲只是一团糊 ⇒ 这一层不做; 桌面没有黑屏
	var haze = null
	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": maxf(CENT_SHOCK_SEC, dist / CENT_SHOCK_SPD), "p0": tip, "d3": d3, "dist": dist,
		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y, "arrow": arrow, "tail": tail, "haze": haze})
	## 认领这一刺的冲击波(二档起): 罩子 / 箭头改跟结算的波头走, 到头(cent_wave_end)再淡掉
	for i in range(_wave_wait.size() - 1, -1, -1):
		if is_same(_wave_wait[i]["u"], u):
			(_stabs.back() as Dictionary)["w"] = _wave_wait[i]["w"]
			(_stabs.back() as Dictionary)["life"] = 99.0
			_wave_wait.remove_at(i)
			break
	_wave_wait = _wave_wait.filter(func(x): return not is_same(x["u"], u))


## 突刺气劲从 a 拉到 b: 帧里箭的有效长约 108 / 128 帧宽 ⇒ 横向缩放 = 距离 / (CENT_ARROW_M × 0.84)
func _arrow_span(s: Sprite3D, a: Vector3, b: Vector3) -> void:
	var ln: float = maxf(0.3, a.distance_to(b))
	s.position = (a + b) * 0.5
	s.scale = Vector3(ln / (CENT_ARROW_M * 0.84), 1.0, 1.0)


## 二档: 冲击罩头部改跟着结算那道冲击波走(sim 的波头位置), 到头再淡掉
var _wave_wait: Array = []   # 结算先发 cent_wave、后发 cent_thrust: 波先存这里, 罩子建好时认领 {u, w}

func cent_wave(u: Dictionary, wv: Dictionary) -> void:
	_wave_wait.append({"u": u, "w": wv})


func cent_wave_hit(_wv: Dictionary, o: Dictionary) -> void:
	## 波头扫到一个敌人: 那个人身上炸一下(闪光 + 冲击环 + 火花 + 轻震)
	var op := Vector2(o["pos"])
	_cent_burst(battle._world_pos(op, 1.0), 0.0, 1.3)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(op, 0.6), 1.8, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	var fl := Sprite3D.new()
	fl.texture = Cent3dVfx.tex("glow.png")
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false
	fl.transparent = true
	fl.no_depth_test = true
	fl.render_priority = 13
	fl.modulate = Color(1.0, 0.95, 0.8, 0.95)
	fl.pixel_size = 2.0 / float(fl.texture.get_width())
	fl.position = battle._world_pos(op, 1.0)
	battle._world.add_child(fl)
	_mfx.append({"node": fl, "nf": 1, "fps": 0.0, "t": 0.0, "life": 0.18, "loop": false, "follow": null, "h": 0.0})
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.15)


func cent_wave_end(wv: Dictionary) -> void:
	for st in _stabs:
		if st.get("w") is Dictionary and is_same(st["w"], wv) and not st.has("end_t"):
			st["end_t"] = float(st["t"])


func _stab_free(st: Dictionary) -> void:
	for p in st["parts"]:
		_free(p["node"])
	for b in st["bills"]:
		_free(b["node"])
	_free(st.get("ring"))
	for f in st.get("front", []):
		_free(f)
	_stop_ps(st.get("spray"))
	_free(st.get("arrow"))
	_free(st.get("haze"))


func _tick_stabs(delta: float) -> void:
	var keep: Array = []
	for st in _stabs:
		st["t"] = float(st["t"]) + delta
		var t: float = float(st["t"])
		var k: float = t / float(st["life"])
		var rg = st.get("ring")
		if rg != null and is_instance_valid(rg):
			var rk: float = maxf(0.0, t) / float(st.get("rd", 0.22))
			if rk >= 1.0:
				_free(rg)
				st["ring"] = null
			else:
				var rm: ShaderMaterial = (rg as MeshInstance3D).material_override
				rm.set_shader_parameter("shell_k", 0.05 + 0.9 * rk)
				rm.set_shader_parameter("fade", 1.0 - rk * rk)
				rm.set_shader_parameter("t", t)
		var follow = st.get("w")
		if st.has("end_t"):
			k = maxf(k, 0.55 + 0.45 * (t - float(st["end_t"])) / 0.15)   # 波到头: 0.15 秒淡掉
		if k >= 1.0:
			_stab_free(st)
			continue
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # 先快后慢
		var d3: Vector3 = st["d3"]
		var pos: Vector3 = Vector3(st["p0"]) + d3 * float(st["dist"]) * e
		if follow is Dictionary:   # 二档: 头部 = 结算那道冲击波的波头(碰到谁才扣谁)
			pos = battle._world_pos(Vector2(follow["pos"]), float(st.get("h", 1.0)))
			e = clampf(t / 0.25, 0.0, 1.0)
		var fd: float = 1.0 - smoothstep(0.45, 1.0, k)
		## 头部: 前沿亮环 / 暗环跟着波头(亮环一直跳), 两侧火花, 地面焦痕 + 小尘团
		var fi := 0
		for f in st.get("front", []):
			if f != null and is_instance_valid(f):
				(f as Node3D).position = pos + d3 * (0.05 if fi == 1 else -0.02)
				(f as Node3D).scale = Vector3.ONE * lerpf(0.6, 1.15, e) * (1.0 + (0.12 * sin(t * 50.0) if fi == 1 else 0.0))
				var fm: ShaderMaterial = (f as MeshInstance3D).material_override
				fm.set_shader_parameter("t", t)
				fm.set_shader_parameter("fade", fd)
			fi += 1
		var ar0 = st.get("arrow")   # 突刺气劲: 箭头尖贴着罩子头部往前走
		if ar0 != null and is_instance_valid(ar0):
			_arrow_span(ar0 as Sprite3D, Vector3(st["tail"]), pos + d3 * 0.1)
			(ar0 as Sprite3D).modulate = Color(1.0, 1.0, 1.0, fd)
		var sp0 = st.get("spray")
		if sp0 != null and is_instance_valid(sp0):
			(sp0 as GPUParticles3D).position = pos
			(sp0 as GPUParticles3D).emitting = fd > 0.3
		## 地面焦痕: 按上一帧 → 这一帧的线段每 0.25 米铺一点(按时间落点时, 每帧波头走半米多, 柔光点断开成一颗一颗)
		var g2 := Vector2(pos.x / float(battle.WS) + float(battle._arena_center.x), pos.z / float(battle.WS) + float(battle._arena_center.y))
		var gl = st.get("skid_p")
		if fd > 0.3:
			var seg_from: Vector2 = gl if gl is Vector2 else g2
			var n_d: int = mini(12, int(seg_from.distance_to(g2) * float(battle.WS) / 0.25))
			for di in range(1, n_d + 1):
				var gp: Vector2 = seg_from.lerp(g2, float(di) / float(n_d))
				_ground_glow(gp, 0.8, Color(0.15, 0.07, 0.03, 0.4), 0.6)
				_ground_glow(gp, 0.35, Color(1.0, 0.75, 0.35, 0.65), 0.25)
			if n_d > 0 or not (gl is Vector2):
				st["skid_p"] = g2
		for p in st["parts"]:
			var n = p["node"]
			if n == null or not is_instance_valid(n):
				continue
			(n as MeshInstance3D).position = pos - d3 * float(p["off"])
			(n as MeshInstance3D).scale = Vector3.ONE * lerpf(float(p["s0"]), float(p["s1"]), e)
			var mat: ShaderMaterial = (n as MeshInstance3D).material_override
			mat.set_shader_parameter("prog", t * 8.0)
			mat.set_shader_parameter("fade", fd)
		var fl: float = 0.75 + 0.5 * fmod(t * 37.0, 1.0)   # 星芒逐帧闪(研究稿 leading star 寿命 0.2 秒、每秒 20 颗)
		for b in st["bills"]:
			var bn = b["node"]
			if bn == null or not is_instance_valid(bn):
				continue
			(bn as Sprite3D).position = pos + d3 * 0.05
			var bsx: float = float(b.get("sx", 1.0))
			(bn as Sprite3D).scale = Vector3(bsx, 1.0 / bsx if bsx > 1.0 else 1.0, 1.0) * fl * lerpf(0.8, 1.15, e)
			var c: Color = b["col"]
			(bn as Sprite3D).modulate = Color(c.r, c.g, c.b, c.a * fd)
		keep.append(st)
	_stabs = keep


func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:
	var a := Vector2(u["pos"])
	var b := Vector2(t["pos"])
	var d: Vector2 = b - a
	if d.length() < 1.0:
		d = _face(u)
	var dir := d.normalized()
	var ln: float = maxf(80.0, d.length()) + (SpearSynergySystem.LINE_LEN if n > 1 else 20.0)
	var mid: Vector2 = a + dir * (ln * 0.5)
	## 金色突刺气劲改由 _cent_impact_dome 建、跟着冲击罩走(11-27 用户「像箭头一样的…也跟着罩子方向去走」); 原来在这里原地画一次
	_cent_glow_on(u)   # 矛刃光叠加层(贴着矛, 跟本体同帧)
	_cent_impact_dome(u, t)   # 矛头裹着冲击罩冲出去(第六轮 3D)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(b, 0.6), 1.3, 20.0, false, 6.0 / 20.0, false, null, 0.0)


## 掷矛起手(结算侧第 3 下刺完、回待机停一拍后调): 掷矛动作 7 帧 @12 = 0.58 秒, 出手帧在第 2 帧(结算 THROW_RELEASE 同一刻发飞矛)
func cent_throw_begin(u: Dictionary) -> void:
	_cent_play(u, "throw", 14.0)   # 15 帧 @14, 出手帧下标 4(结算 THROW_RELEASE 0.29 同一刻)


## 掷矛飞矛分层(11-27, 研究稿 Q 普通飞矛): 跟着飞矛走的一组层, 矛头在飞矛节点往前 JAV_HEAD 米处
const JAV_HEAD := 1.15


func _jav_fx(head: Vector3, yaw: float) -> Dictionary:
	var w: Node3D = battle._world
	## [着色器, 长, 口径, 往后错开(米), 参数, 绘制顺序]
	var spec: Array = [
		[CONE_MIX, 1.1, 0.34, 0.0, {"col": Vector4(0.2, 0.06, 0.02, 0.5), "rim_mix": 0.4, "tail": 0.5, "apex": 0.2}, 10],     # 暗罩
		[CONE_MIX, 0.9, 0.28, 0.0, {"col": Vector4(1.0, 0.74, 0.25, 0.65), "rim_mix": 0.65, "tail": 0.5, "apex": 1.0}, 11],    # 金罩
		[CONE_ADD, 1.1, 0.32, 0.0, {"col": Vector4(0.8, 0.3, 0.12, 0.55), "rim_mix": 0.5, "tail": 0.45, "apex": 0.6}, 12],    # 叠加发光罩
		[CONE_MIX, 3.2, 0.3, 0.3, {"col": Vector4(1.0, 0.95, 0.8, 0.75), "rim_mix": 0.0, "tail": 0.7, "apex": 0.0, "streaks": 16.0}, 12],   # 流光拖尾
		[CONE_MIX, 3.6, 0.36, 0.3, {"col": Vector4(0.18, 0.1, 0.05, 0.35), "rim_mix": 0.3, "tail": 0.75, "apex": 0.0}, 9],    # 暗拖尾
	]
	var parts: Array = []
	for sp in spec:
		var prm: Dictionary = (sp[4] as Dictionary).duplicate()
		prm["prog"] = 0.0
		prm["fade"] = 1.0
		var mi := Cent3dVfx.node(w, Cent3dVfx.gen_shock(float(sp[1]), float(sp[2]), 8, 20), sp[0], CONE_SP, prm, int(sp[5]))
		mi.rotation = Vector3(0.0, yaw, 0.0)
		mi.position = head
		parts.append({"node": mi, "off": float(sp[3])})
	var bills: Array = []
	## [贴图, 宽(米), 颜色, 绘制顺序, 横向拉伸]
	for b in [["glow.png", 1.2, Color(0.12, 0.05, 0.02, 0.5), 9, 1.0], ["glow.png", 0.9, Color(1.0, 0.95, 0.8, 0.85), 13, 1.0],
			["xstar.png", 1.4, Color(1.0, 0.9, 0.65, 0.9), 14, 2.2]]:
		var s := Sprite3D.new()
		s.texture = Cent3dVfx.tex(str(b[0]))
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.no_depth_test = true
		s.render_priority = int(b[3])
		s.modulate = b[2]
		s.pixel_size = float(b[1]) / float(s.texture.get_width())
		s.scale = Vector3(float(b[4]), 1.0 / sqrt(float(b[4])), 1.0)
		s.position = head
		w.add_child(s)
		bills.append({"node": s, "sx": float(b[4])})
	var ps := GPUParticles3D.new()   # 一路火花(往后落下)
	ps.amount = 40
	ps.lifetime = 0.35
	ps.randomness = 0.6
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1.0, 0.15, 0.0)
	pm.spread = 18.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0.0, -2.5, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.08)
	ps.position = head
	ps.rotation = Vector3(0.0, yaw, 0.0)
	w.add_child(ps)
	return {"parts": parts, "bills": bills, "ps": ps, "t": 0.0}


func _jav_tick(fx: Dictionary, head: Vector3, d3: Vector3, delta: float) -> void:
	fx["t"] = float(fx.get("t", 0.0)) + delta
	var t: float = float(fx["t"])
	for p in fx["parts"]:
		var n = p["node"]
		if n != null and is_instance_valid(n):
			(n as MeshInstance3D).position = head - d3 * float(p["off"])
			((n as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("prog", t * 9.0)
	var fl: float = 0.8 + 0.4 * fmod(t * 31.0, 1.0)
	for b in fx["bills"]:
		var bn = b["node"]
		if bn != null and is_instance_valid(bn):
			(bn as Sprite3D).position = head
			var sx: float = float(b["sx"])
			(bn as Sprite3D).scale = Vector3(sx, 1.0 / sqrt(sx), 1.0) * (fl if sx > 1.0 else 1.0)
	var ps = fx.get("ps")
	if ps != null and is_instance_valid(ps):
		(ps as GPUParticles3D).position = head
		(ps as GPUParticles3D).emitting = true


func _jav_free(fx) -> void:
	if not (fx is Dictionary):
		return
	for p in fx.get("parts", []):
		_free(p["node"])
	for b in fx.get("bills", []):
		_free(b["node"])
	var ps = fx.get("ps")
	if ps != null and is_instance_valid(ps):
		(ps as GPUParticles3D).emitting = false
		_aegis_junk.append({"node": ps, "left": 0.4})


## 径向冲击环 + 火花迸射(出手 / 命中共用; 底层元素)
func _cent_burst(pos: Vector3, yaw: float, ring_m: float) -> void:
	if not _ok():
		return
	var w: Node3D = battle._world
	var ring := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.05, ring_m, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "open": 1.0, "shell_k": 0.05}, 12)
	ring.position = pos
	ring.rotation = Vector3(0.0, yaw, PI * 0.5)
	var ps := GPUParticles3D.new()
	ps.amount = 18
	ps.lifetime = 0.35
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.randomness = 0.7
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.2, 0.0)
	pm.spread = 50.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.1)
	ps.position = pos
	ps.rotation = Vector3(0.0, yaw, 0.0)
	ps.emitting = true
	w.add_child(ps)
	_aegis_junk.append({"node": ps, "left": 0.6})
	_stabs.append({"parts": [], "bills": [], "ring": ring, "t": 0.0, "life": 0.25, "p0": pos, "d3": Vector3.ZERO, "dist": 0.0})


func cent_throw(_u: Dictionary, s: Dictionary) -> void:
	_dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(s["pos"]) + Vector2(s["dir"]) * 90.0, Vector2(s["dir"]), 180.0 * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)   # 出手那一下的气劲
	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 2.4)
	if n != null:
		var d2: Vector2 = Vector2(s["dir"]).normalized()
		var d3 := Vector3(d2.x, 0.0, d2.y)
		var yaw: float = Cent3dVfx.yaw_of(d2)
		var head: Vector3 = battle._world_pos(Vector2(s["pos"]), 1.0) + d3 * JAV_HEAD
		_cent_burst(battle._world_pos(Vector2(s["pos"]), 1.0), yaw, 1.1)   # 出手: 径向冲击环 + 火花
		_spear_nodes.append({"s": s, "node": n, "fx": _jav_fx(head, yaw), "d3": d3})


## 11-27: 三批里程序画的圆圈全部换成画出来的帧条(用户「lion 太敷衍了吧」之后自查出 18 处)
func cent_spear_hit(o: Dictionary) -> void:
	_cent_burst(battle._world_pos(Vector2(o["pos"]), 1.0), 0.0, 1.0)   # 命中: 径向冲击环 + 火花迸射
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.6, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 1.0, 16.0, false, 7.0 / 16.0, false, null, 0.0)


func cent_spear_drop(s: Dictionary) -> void:
	for r in _spear_nodes:
		if is_same(r["s"], s):
			_free(r["node"])
			_jav_free(r.get("fx"))
	_spear_nodes = _spear_nodes.filter(func(r): return not is_same(r["s"], s))


## 龟甲阵(11-27 附录 D, 按特效师流程分层; 用户「真正厉害的三 D 美术师肯定不会说只做一层这个盾吧」): 全部是世界空间 3D 层, 绕 Y 转到举盾方向
##   外层盾面 / 内层盾面(小一圈、纹理反向滚 ⇒ 厚度视差) / 两端翼焰 / 盾前地面扇形 —— 同一个节奏推(张开 → 撑 → 放盾侵蚀)
##   扎稳冲击环(贴地一圈 0.3 秒扩开) / 盾底上飘光点(GPU 粒子) / 受击涟漪(本体掉血那一步, 盾面朝攻击者那点起一圈) /
##   每 0.5 秒穿盾矛光(= 帧条捅出帧) / 放盾: 侵蚀从上往下烧掉 + 碎光片往外迸
##   方向 = 本体朝向那一侧最近的敌人(接近正上 / 正下也算), 举盾那一刻定下
var _aegis: Array = []      # {u, node(外层), parts, ring, motes, t, dir, yaw, off, hp, rips, jab}
var _rays: Array = []       # 穿盾矛光 {node, mat, t}
var _aegis_junk: Array = [] # 放完要再留一会儿的(碎光片粒子) {node, left}
const AEGIS_R := 1.45       # 外层弧半径(米)
const AEGIS_ARC := 2.2      # 张角(弧度, 约 126°)
const AEGIS_H := 3.0        # 盾高(米), 比人高半个身位
const AEGIS_LEAN := 0.35    # 顶部往外翻(米)
const AEGIS_OPEN_SEC := 0.15
const AEGIS_BRK_SEC := 0.3
const AEGIS_JAB_IV := 0.5   # 盾后出刺节奏(= 结算 POKE_IV、帧条捅出帧)
const AEGIS_RAY_SEC := 0.25
const AEGIS_RING_SEC := 0.3


func _aegis_dir(u: Dictionary) -> Vector2:
	var spr = u.get("sprite", null)
	var fx: float = (1.0 if (spr as Sprite3D).flip_h else -1.0) if is_instance_valid(spr) else _face(u).x   # 本体帧条原画朝左, flip_h = 朝右
	var best: Vector2 = Vector2(fx, 0.0)
	var bd := INF
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		var d: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
		if d.x * fx < -0.25 * d.length() or d.length() < 1.0:   # 朝向那一侧 + 接近竖直的(上下方)都算
			continue
		if d.length() < bd:
			bd = d.length()
			best = d.normalized()
	return best


func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))   # 42 帧 / 3 秒 = 14 fps: 盾后出刺的捅出帧恰好落在 0.5 / 1.0 / … 秒(= 结算 POKE_IV)
	battle._vfx._flash(u, Color(1.0, 0.9, 0.55), 0.12)   # 扎稳那一下本体闪白金
	cent_shield_off(u)
	if _ok():
		var w: Node3D = battle._world
		var dir := _aegis_dir(u)
		var yaw: float = Cent3dVfx.yaw_of(dir)
		var pos: Vector3 = battle._world_pos(Vector2(u["pos"]), 0.0)
		var te := Cent3dVfx.tex("energy.png")
		var tr := Cent3dVfx.tex("erode.png")
		var inner := Cent3dVfx.node(w, Cent3dVfx.gen_aegis(AEGIS_R - 0.14, AEGIS_ARC * 0.96, AEGIS_H * 0.9, AEGIS_LEAN * 0.8, 24, 10),
			Cent3dVfx.AEGIS_SHADER, Cent3dVfx.AEGIS_SP, {"tex_energy": te, "tex_erode": tr, "layer": 1.0,
			"size_m": Vector2((AEGIS_R - 0.14) * AEGIS_ARC * 0.96, AEGIS_H * 0.9)})
		var outer := Cent3dVfx.node(w, Cent3dVfx.gen_aegis(AEGIS_R, AEGIS_ARC, AEGIS_H, AEGIS_LEAN, 28, 12),
			Cent3dVfx.AEGIS_SHADER, Cent3dVfx.AEGIS_SP, {"tex_energy": te, "tex_erode": tr, "tex_sigil": Cent3dVfx.tex("sigil.png"),
			"layer": 0.0, "size_m": Vector2(AEGIS_R * AEGIS_ARC, AEGIS_H)})
		var parts: Array = [inner, outer]
		for side in [-1.0, 1.0]:
			parts.append(Cent3dVfx.node(w, Cent3dVfx.gen_aegis_flare(AEGIS_R, AEGIS_ARC, AEGIS_H * 0.85, 0.9, side, 8, 10),
				Cent3dVfx.FLARE_SHADER, Cent3dVfx.FLARE_SP, {"tex_flame": Cent3dVfx.tex("flame.png"), "tex_energy": te}))
		parts.append(Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.35, AEGIS_R + 1.6, AEGIS_ARC * 1.04, 0.03, 28, 10),
			Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP, {"tex_energy": te, "shell_k": (AEGIS_R - 0.35) / (AEGIS_R + 1.25)}))
		var ring := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.2, 2.4, TAU, 0.04, 48, 6), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
			{"tex_energy": te, "open": 1.0, "shell_k": 0.05})
		ring.position = pos
		for n in parts:
			(n as Node3D).position = pos
			(n as Node3D).rotation = Vector3(0.0, yaw, 0.0)
		var motes := _aegis_motes(pos, yaw)
		_aegis.append({"u": u, "node": outer, "parts": parts, "ring": ring, "motes": motes, "t": 0.0, "dir": dir, "yaw": yaw,
			"off": -1.0, "hp": float(u.get("hp", 0.0)), "rips": [], "jab": 0})
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.5)


func _gold_ramp(a0: float) -> GradientTexture1D:
	var gd := Gradient.new()
	gd.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
	gd.colors = PackedColorArray([Color(1.0, 0.9, 0.55, a0), Color(1.0, 0.92, 0.6, 1.0), Color(1.0, 0.7, 0.25, 0.8), Color(1.0, 0.5, 0.1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = gd
	return gt


func _mote_quad(sz: float) -> QuadMesh:
	var qm := QuadMesh.new()
	qm.size = Vector2(sz, sz)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = Cent3dVfx.tex("mote.png")
	sm.no_depth_test = true
	sm.render_priority = 10
	qm.material = sm
	return qm


## 盾底一排金色光点往上飘(撑盾期间一直冒)
func _aegis_motes(pos: Vector3, yaw: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = 36
	ps.lifetime = 1.1
	ps.randomness = 0.6
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.1, AEGIS_R * sin(AEGIS_ARC * 0.5) * 0.95)
	pm.emission_shape_offset = Vector3(AEGIS_R * 0.9, 0.15, 0.0)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.0, 0.3, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _gold_ramp(0.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.14)
	ps.position = pos
	ps.rotation = Vector3(0.0, yaw, 0.0)
	battle._world.add_child(ps)
	return ps


## 放盾: 碎光片从盾面往外迸、往下落(一次性)
func _aegis_shards(pos: Vector3, yaw: float) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 44
	ps.lifetime = 0.7
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.randomness = 0.8
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.08, AEGIS_H * 0.45, AEGIS_R * sin(AEGIS_ARC * 0.5) * 0.9)
	pm.emission_shape_offset = Vector3(AEGIS_R, AEGIS_H * 0.5, 0.0)
	pm.direction = Vector3(1.0, 0.25, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0.0, -7.0, 0.0)
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.17)
	ps.position = pos
	ps.rotation = Vector3(0.0, yaw, 0.0)
	ps.emitting = true
	battle._world.add_child(ps)
	_aegis_junk.append({"node": ps, "left": 1.0})


## 穿盾矛光(每 0.5 秒, 跟帧条捅出帧同一刻): 从盾心往前穿出去 2.6 米, 方向在盾的正前方左右略错开
func _aegis_ray(a: Dictionary) -> void:
	var k: int = int(a["jab"])
	var yaw: float = float(a["yaw"]) + [0.0, -0.18, 0.15, -0.08, 0.2][k % 5]
	var wdir := Vector3(cos(yaw), 0.0, -sin(yaw))
	var mi := Cent3dVfx.node(battle._world, Cent3dVfx.gen_ray_cross(2.6, 0.55), Cent3dVfx.RAY_SHADER, Cent3dVfx.RAY_SP,
		{"tex_ray": Cent3dVfx.tex("ray.png"), "prog": 0.0}, 10)
	mi.position = battle._world_pos(Vector2((a["u"] as Dictionary)["pos"]), 0.0) + wdir * (AEGIS_R * 0.85) + Vector3(0.0, 1.35, 0.0)
	mi.rotation = Vector3(0.0, yaw, 0.0)
	_rays.append({"node": mi, "mat": mi.material_override, "t": 0.0})


## 受击涟漪: 本体掉血那一步, 盾面朝最近敌人那一点起一圈(弧上的位置按敌人相对盾正前方的角度算)
func _aegis_ripple(a: Dictionary) -> void:
	var u: Dictionary = a["u"]
	var tg = battle._targeting._nearest_enemy(u)
	var ang := 0.0
	if tg is Dictionary:
		var d: Vector2 = Vector2(tg["pos"]) - Vector2(u["pos"])
		ang = wrapf(atan2(d.y, d.x) - atan2((a["dir"] as Vector2).y, (a["dir"] as Vector2).x), -PI, PI)
	var n: int = (a["rips"] as Array).size()
	(a["rips"] as Array).append(Vector4(clampf(0.5 + ang / AEGIS_ARC, 0.12, 0.88), 0.32 + 0.36 * fmod(float(n) * 0.618, 1.0), 0.0, 1.0))
	if (a["rips"] as Array).size() > 4:
		(a["rips"] as Array).pop_front()


func _aegis_free(a: Dictionary) -> void:
	for n in a.get("parts", []):
		_free(n)
	_free(a.get("ring"))
	_free(a.get("motes"))


## 放盾: 按侵蚀图从上往下烧掉(AEGIS_BRK_SEC) + 碎光片, 烧完再删节点
func cent_shield_off(u: Dictionary) -> void:
	for a in _aegis:
		if is_same(a["u"], u) and float(a["off"]) < 0.0:
			a["off"] = 0.0
			var m = a.get("motes")
			if m != null and is_instance_valid(m):
				(m as GPUParticles3D).emitting = false
			_aegis_shards(battle._world_pos(Vector2(u["pos"]), 0.0), float(a["yaw"]))


func _tick_aegis(delta: float) -> void:
	var keep: Array = []
	for a in _aegis:
		var n = a["node"]
		var u: Dictionary = a["u"]
		if n == null or not is_instance_valid(n):
			_aegis_free(a)
			continue
		if not u.get("alive", false) and float(a["off"]) < 0.0:
			cent_shield_off(u)
		a["t"] = float(a["t"]) + delta
		var t: float = float(a["t"])
		var pos: Vector3 = battle._world_pos(Vector2(u["pos"]), 0.0)
		var on: bool = float(a["off"]) < 0.0
		## 受击涟漪: 掉血那一步起一圈
		var hp: float = float(u.get("hp", 0.0))
		if on and hp < float(a["hp"]) - 0.5:
			_aegis_ripple(a)
		a["hp"] = hp
		var rv: Array = []
		for r in a["rips"]:
			var r4: Vector4 = r
			r4.z += delta
			rv.append(r4)
		a["rips"] = rv
		## 穿盾矛光(0.5 / 1.0 / … 秒)
		var jn: int = int(t / AEGIS_JAB_IV)
		if on and jn > int(a["jab"]):
			a["jab"] = jn
			_aegis_ray(a)
		var ph: float = fmod(t, AEGIS_JAB_IV)
		var fl: float = maxf(0.0, 1.0 - ph / 0.15) if t >= AEGIS_JAB_IV - 0.001 and ph < 0.15 and on else 0.0
		var k: float = 0.0
		if not on:
			a["off"] = float(a["off"]) + delta
			k = minf(1.0, float(a["off"]) / AEGIS_BRK_SEC)
		var op: float = minf(1.0, t / AEGIS_OPEN_SEC)
		var pop: float = 1.0 + 0.08 * DetMath.dsin(PI * clampf(t / 0.24, 0.0, 1.0))   # 张开时整面高度回弹一下
		for i in range((a["parts"] as Array).size()):
			var p = a["parts"][i]
			if p == null or not is_instance_valid(p):
				continue
			(p as Node3D).position = pos
			if i < 2:
				(p as Node3D).scale = Vector3(1.0, pop, 1.0)
			var mat: ShaderMaterial = (p as MeshInstance3D).material_override
			mat.set_shader_parameter("t", t)
			mat.set_shader_parameter("open", op)
			mat.set_shader_parameter("close", k)
			mat.set_shader_parameter("fade", 1.0)
			if i < 2:
				mat.set_shader_parameter("flash", fl)
				for ri in range(4):
					var rr: Vector4 = rv[rv.size() - 1 - ri] if ri < rv.size() else Vector4(0.5, 0.5, 9.0, 0.0)
					mat.set_shader_parameter("rip%d" % ri, rr)
		var mo = a.get("motes")
		if mo != null and is_instance_valid(mo):
			(mo as Node3D).position = pos
		var rg = a.get("ring")
		if rg != null and is_instance_valid(rg):
			var rk: float = t / AEGIS_RING_SEC
			if rk >= 1.0:
				_free(rg)
				a["ring"] = null
			else:
				var rm: ShaderMaterial = (rg as MeshInstance3D).material_override
				rm.set_shader_parameter("shell_k", 0.05 + 0.9 * rk)
				rm.set_shader_parameter("fade", 1.0 - rk * rk)
				rm.set_shader_parameter("t", t)
		if k >= 1.0:
			_aegis_free(a)
			continue
		keep.append(a)
	_aegis = keep
	## 穿盾矛光 / 碎光片的收尾
	var kr: Array = []
	for r in _rays:
		var rn = r["node"]
		if rn == null or not is_instance_valid(rn):
			continue
		r["t"] = float(r["t"]) + delta
		var pk: float = float(r["t"]) / AEGIS_RAY_SEC
		if pk >= 1.0:
			_free(rn)
			continue
		(r["mat"] as ShaderMaterial).set_shader_parameter("prog", pk)
		kr.append(r)
	_rays = kr
	var kj: Array = []
	for j in _aegis_junk:
		j["left"] = float(j["left"]) - delta
		if float(j["left"]) <= 0.0:
			_free(j["node"])
			continue
		kj.append(j)
	_aegis_junk = kj


## 3 档举盾期间每 0.5 秒刺周围: 朝范围里每个敌人各一道短突刺气劲 + 火星(结算同一步, 范围 = POKE_R)
func cent_poke(u: Dictionary) -> void:
	var a := Vector2(u["pos"])
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false) or DetMath.dist(Vector2(o["pos"]), a) > SpearSynergySystem.POKE_R:
			continue
		var d: Vector2 = Vector2(o["pos"]) - a
		var dir: Vector2 = d.normalized() if d.length() > 1.0 else _face(u)
		var ln: float = maxf(60.0, d.length())
		_dir_strip(SV + "spear-cent-thrust.png", 7, a + dir * (ln * 0.5), dir, ln * float(battle.WS), 28.0, 7.0 / 28.0, CENT_TIP_H * 0.8)
		_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.0, 20.0, false, 6.0 / 20.0, false, null, 0.0)


func cent_sweep(u: Dictionary) -> void:
	_cent_play(u, "sweep", 16.0)   # 本体原地转一圈横扫(12 帧 0.75 秒; 用户 11-27「原地横扫转一圈」)
	## 一圈金白横扫气刃贴地转开、往外甩土(spear-cent-sweep, 俯视画); 画里气刃外缘约占画布 0.8 ⇒ 按横扫半径 260 换算
	var sw := _strip(SV + "spear-cent-sweep.png", 9, battle._world_pos(Vector2(u["pos"]), 0.06), 260.0 * 2.0 * float(battle.WS) / 0.8, 16.0, false, 9.0 / 16.0, true, null, 0.0)
	if sw != null:
		sw.modulate = Color(1.35, 1.25, 1.0, 1.0)   # 11-27「技能特效感觉都不明显」: 提亮、放慢一点
	for o in battle._targeting._enemies_of(u):   # 扫到的每个敌人身上迸火星(结算同一步, 范围 = SWEEP_R)
		if o.get("alive", false) and DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= SpearSynergySystem.SWEEP_R:
			_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.3, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.6)


## 骑兵冲锋(11-27 补, 同舞狮冲撞那次用户「冲锋方向什么特效都没有吗？」): 马身后灰白风线 + 马头前一团被冲开的尘浪 + 马蹄一路扬土
##   (原画都给「朝左冲」画: 风线往右拖、尘浪往左翻 ⇒ 往右冲一律翻过来)
func cent_cav(c: Dictionary) -> void:
	var dir: Vector2 = Vector2(c["dir"])
	var fr: bool = dir.x > 0.0
	var parts: Array = []
	for spec in [["spear-cav-speed.png", 4, 1.3, 12.0, 80.0, 0.35], ["spear-cav-dustbow.png", 6, 1.5, 14.0, -50.0, 0.0]]:
		var sp := _strip(V + str(spec[0]), int(spec[1]), battle._world_pos(Vector2(c["pos"]), float(spec[5])), float(spec[2]), float(spec[3]), true, 0.0)
		if sp != null:
			sp.flip_h = fr
			parts.append({"n": sp, "back": float(spec[4]), "h": float(spec[5])})
	var n := _strip(V + "eq-cavalry-run.png", 8, battle._world_pos(Vector2(c["pos"]), 0.0), 2.6, 10.0, true, 0.0)   # 最后加 ⇒ 画在最上面; 11-27 冲锋 520 → 300 码/秒, 跑帧 14 → 10 fps
	if n != null:
		n.flip_h = fr   # 原画朝左; 往右冲就翻过来
		## 罩住人马全身的能量罩(11-27 用户「像赛亚冲锋一样…要有个罩子…不要很明显的贴图的那种感觉」): 3D 水滴形外壳,
		##   只有轮廓边亮、正面透明(人马在里面看得清), 壳面气流线往后流, 前端最亮; 朝冲锋方向
		var bow := Cent3dVfx.node(battle._world, Cent3dVfx.gen_sheath(4.2, 1.35, 16, 28), Cent3dVfx.SHEATH_SHADER, Cent3dVfx.SHEATH_SP,
			{"t": 0.0, "fade": 1.0}, 10)
		bow.scale = Vector3(1.0, 0.9, 0.8)
		bow.rotation = Vector3(0.0, Cent3dVfx.yaw_of(dir), 0.0)
		## 研究稿 R 彗星 / 滑行彗星: 暗色外壳垫底 + 包身亮光晕(下垫暗光) + 马头往后的尾流 + 一路星尘
		var dk := Cent3dVfx.node(battle._world, Cent3dVfx.gen_sheath(4.2, 1.35, 16, 28), Cent3dVfx.SHEATH_SHADER, Cent3dVfx.SHEATH_SP,
			{"t": 0.0, "fade": 1.0, "col_edge": Vector3(0.16, 0.07, 0.03), "col_hot": Vector3(0.3, 0.14, 0.05)}, 9)
		dk.scale = Vector3(1.06, 0.95, 0.85)
		dk.rotation = bow.rotation
		var fxc := {"dark": dk, "bills": [], "wake": [], "ps": null}
		## 包身光画在马身后(绘制顺序 < 立绘的 9), 当衬底; 11-27 自查: 画在马前面时整匹马被奶白光盖住
		for b in [["glow.png", 4.4, Color(0.14, 0.06, 0.02, 0.4), 7], ["glow.png", 3.4, Color(1.0, 0.78, 0.38, 0.45), 8]]:
			var gs := Sprite3D.new()
			gs.texture = Cent3dVfx.tex(str(b[0]))
			gs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			gs.shaded = false
			gs.transparent = true
			gs.no_depth_test = true
			gs.render_priority = int(b[3])
			gs.modulate = b[2]
			gs.pixel_size = float(b[1]) / float(gs.texture.get_width())
			battle._world.add_child(gs)
			fxc["bills"].append({"node": gs, "col": b[2]})
		fxc["wake"] = _cone_set([
			[CONE_MIX, 5.5, 1.3, 0.0, {"col": Vector4(0.18, 0.08, 0.03, 0.35), "rim_mix": 0.4, "tail": 0.7, "apex": 0.0}, 9],
			[CONE_MIX, 5.0, 1.15, 0.0, {"col": Vector4(1.0, 0.92, 0.72, 0.75), "rim_mix": 0.0, "tail": 0.65, "apex": 0.0, "streaks": 22.0}, 12],
		], battle._world_pos(Vector2(c["pos"]), 1.0), Vector3(0.0, Cent3dVfx.yaw_of(dir), 0.0))
		fxc["ps"] = _stream_ps(battle._world_pos(Vector2(c["pos"]), 1.2), Vector3(-dir.x, 0.4, -dir.y), 80, 0.6, 1.0, 3.0, 25.0, 0.11)
		_cav_nodes.append({"c": c, "node": n, "parts": parts, "dust_t": 0.0, "bow": bow, "bt": 0.0, "fxc": fxc, "trench_t": 0.0})


## 骑兵撞人(11-27 用户「命中特效也没有」): 撞点沿冲锋方向炸开一层冲击罩 + 大号火星 + 扬土 + 轻震屏
func cent_cav_hit(c: Dictionary, o: Dictionary) -> void:
	var d2: Vector2 = Vector2(c["dir"])
	_shock(battle._world_pos(Vector2(o["pos"]) + d2 * 10.0, 1.0), Vector3(d2.x, 0.0, d2.y), Cent3dVfx.gen_shock(0.9, 0.8, 8, 20),
		{"prog": 0.0, "fade": 1.0, "rings": 2.0, "rim_pow": 1.2, "tail": 0.45, "col_a": Vector3(1.0, 0.96, 0.85), "col_b": Vector3(1.0, 0.66, 0.28)},
		0.32, 1.3, Vector3(0.5, 0.5, 0.5), Vector3(1.5, 1.5, 1.5), 8.0)
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 2.0, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 马蹄踏过扬土(底层扬尘)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.6), 2.4, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.25)


func _cav_fx_free(fxc, hard: bool) -> void:
	if not (fxc is Dictionary):
		return
	_free(fxc.get("dark"))
	for gb in fxc.get("bills", []):
		_free(gb["node"])
	_cone_set_free(fxc.get("wake"))
	if hard:
		_free(fxc.get("ps"))
	else:
		_stop_ps(fxc.get("ps"))


func cent_cav_end(c: Dictionary) -> void:
	for r in _cav_nodes:
		if is_same(r["c"], c):
			_free(r["node"])
			_free(r.get("bow"))
			_cav_fx_free(r.get("fxc"), false)
			for pt in r.get("parts", []):
				if pt["n"] != null and is_instance_valid(pt["n"]):
					_fade_out(pt["n"] as Sprite3D, 0.12)
	_cav_nodes = _cav_nodes.filter(func(r): return not is_same(r["c"], c))


# ── 10 件长矛 ──


func javelin_fly(u: Dictionary, tg: Dictionary):
	return _proj("spear-javelin.png", Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), 1.4)


func javelin_step(node, p2: Vector2, to2: Vector2) -> void:
	if node != null and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, 1.0)
		_orient_to(node, to2 - p2)


func javelin_end(node, _hit: bool) -> void:
	_free(node)


func eternal_fly(u: Dictionary, tg: Dictionary):
	return _proj("spear-gungnir.png", Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), 2.0)


func eternal_step(node, p2: Vector2, to2: Vector2) -> void:
	javelin_step(node, p2, to2)


func eternal_end(node, hit: bool, tg: Dictionary) -> void:
	_free(node)
	if hit and tg.get("alive", false):
		_ring(Vector2(tg["pos"]), 70.0, Color(0.85, 0.95, 1.0, 0.95), 0.4)


## ── 10 件长矛的演出(11-26 夜按用户改过的机制重做; 素材来历见 pack_spear_chip_art.py, 全部 PixelLab 逐帧, 没照参考) ──
##   137 竹矛    出手处一圈尘; 浪头每推进 45 码地里刺出一丛竹刺(刺出 → 停 → 缩回, 逐帧), 一路连成一道浪
##   138 鱼叉    叉按速度飞, 尾巴拖一根绳连回携带者; 叉中后绳子绷在两人之间直到松开, 每拽一下目标脚下起尘
##   139 标枪    飞矛照旧, 命中处一点红(流血)
##   140 骑枪    冲势攒满: 头顶燃烧的枪尖标记(逐帧)亮到这一击打出; 命中: 朝出手方向的冲击波 + 尘(目标被击飞由引擎抛)
##   141 长戟    钢蓝新月横扫, 大小按这一下实际扫的半径(= 射程)、朝出手方向
##   142 盾矛    举盾: 身前立起一面大盾(0.2 秒升起, 鹰徽随存下的伤害越来越亮); 放盾: 盾收起, 扇形冲击波按结算同一速度推出去
##   143 方天画戟 蓄力: 脚下红金火焰聚气(逐帧); 跃起: 携带者真的跳起来再砸下(抛物线); 落地: 大裂坑冲击(逐帧)+ 震屏;
##              之后 4 秒脚下留余焰, 每次攻击一圈红金刃环(大小 = 结算半径)
##   144 投矛器  目标那一圈先亮红色警示圈; 矛一根根从高处按速度落下, 扎进地里起尘、矛杆抖两下(逐帧)
##   146 圣枪    11-26 晚重做: 圣枪护盾 / 引导光环 / 光球 / 砸中友方光柱 / 砸中敌方星爆 + 护盾回流(见下面 146 那一段)
const SV := "res://assets/sprites/vfx/"
const RING_FILL := 1.16   # 刃环在 128 帧里约占 110 像素 ⇒ 帧宽 = 直径 × 1.16
const CRATER_FILL := 1.1  # 裂坑冲击在 128 帧里约占 116 像素
const ROPE_THICK_M := 0.14
var _ropes: Array = []    # 138 {a(携带者), b(目标或 null), node(绳), harp(飞行中的叉节点)}
var _lance_on := {}       # 140 携带者立绘实例 id → _mfx 那一条
var _shields: Array = []  # 142 {u, node, t, sec}
var _swv: Array = []      # 142 冲击波 {node, o, dir, r}
var _leaps: Array = []    # 143 {u, t, air}
var _fall: Array = []     # 144 {d, node, t, dur}


## 一条横排帧条, 按 2D 方向转(飞行物同款 _orient_to), 记进 _mfx 推帧 / 到时收
func _dir_strip(path: String, nf: int, at: Vector2, dir: Vector2, len_m: float, fps: float, life: float, h: float = 1.0) -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = nf
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = len_m / float(t.get_width() / nf)
	s.position = battle._world_pos(at, h)
	battle._world.add_child(s)
	_orient_to(s, dir)
	_mfx.append({"node": s, "nf": nf, "fps": fps, "t": 0.0, "life": life, "loop": false, "follow": null, "h": h})
	return s


func _uid(u: Dictionary) -> int:
	var spr = u.get("sprite", null)
	return (spr as Object).get_instance_id() if is_instance_valid(spr) else 0


func _face(u: Dictionary) -> Vector2:
	return Vector2(1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else -1.0, 0.0)


# ── 137 竹矛 ──
func bamboo_wave(u: Dictionary, _dir: Vector2) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 0.8, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 竹刺破土那一下脚下扬土


func bamboo_spike(at: Vector2, _dir: Vector2) -> void:
	_strip(SV + "spear-bamboo-spike.png", 13, battle._world_pos(at, 0.0), 1.3, 26.0, false, 13.0 / 26.0, false, null, 0.0)


# ── 138 鱼叉 ──
func harpoon_fly(u: Dictionary, tg: Dictionary):
	var n := _proj("spear-harpoon.png", Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), 1.3)
	var rope := _rope_node()
	_ropes.append({"a": u, "b": null, "node": rope, "harp": n})
	return n


func _rope_node() -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(SV + "spear-rope.png"):
		return null
	var t: Texture2D = load(SV + "spear-rope.png")
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 8
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = 0.01
	battle._world.add_child(s)
	return s


func harpoon_step(node, p2: Vector2, to2: Vector2) -> void:
	if node != null and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, 1.0)
		_orient_to(node, to2 - p2)


func harpoon_end(node, hit: bool, _me: Dictionary, tg: Dictionary) -> void:
	for r in _ropes:
		if is_same(r["harp"], node):
			r["harp"] = null
			if hit and tg.get("alive", false):
				r["b"] = tg   # 叉中: 绳子改绷在两人之间, 直到 harpoon_release
				_strip(SV + "spear-harpoon-splash.png", 9, battle._world_pos(Vector2(tg["pos"]), 0.0), 1.3, 18.0, false, 9.0 / 18.0, false, null, 0.0)   # 叉中: 溅一团海水
			else:
				_free(r["node"])
				r["node"] = null
	_ropes = _ropes.filter(func(r): return r["node"] != null)
	_free(node)


func harpoon_pull(_src: Dictionary, o: Dictionary) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 0.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 被拽一下脚下蹭起土


func harpoon_release(_src: Dictionary, o: Dictionary) -> void:
	for r in _ropes:
		if is_same(r["b"], o):
			_free(r["node"])
			r["node"] = null
	_ropes = _ropes.filter(func(r): return r["node"] != null)


func _tick_ropes() -> void:
	for r in _ropes:
		var n = r["node"]
		if n == null or not is_instance_valid(n):
			continue
		var a: Dictionary = r["a"]
		var bp: Vector3
		if r["b"] is Dictionary:
			bp = battle._world_pos(Vector2((r["b"] as Dictionary)["pos"]), 0.9)
		elif r["harp"] != null and is_instance_valid(r["harp"]):
			bp = (r["harp"] as Sprite3D).position
		else:
			continue
		var ap: Vector3 = battle._world_pos(Vector2(a["pos"]), 0.9)
		var mid: Vector3 = (ap + bp) * 0.5
		(n as Sprite3D).position = mid
		var len_m: float = maxf(0.05, Vector2(bp.x - ap.x, bp.z - ap.z).length())
		var tex: Texture2D = (n as Sprite3D).texture
		(n as Sprite3D).pixel_size = ROPE_THICK_M / float(tex.get_height())   # 粗细固定, 只沿长度方向拉(统一缩放时一拉长就粗成一条木板, 11-26 夜录像)
		_orient_screen(n, bp - ap)
		(n as Sprite3D).scale = Vector3(len_m / (float(tex.get_width()) * (n as Sprite3D).pixel_size), 1.0, 1.0)


# ── 139 标枪 ──
func javelin_bleed(tg: Dictionary) -> void:
	_strip(SV + "spear-javelin-blood.png", 7, battle._world_pos(Vector2(tg["pos"]), 0.3), 1.1, 18.0, false, 7.0 / 18.0, false, null, 0.0)   # 扎中迸血(流血)


# ── 140 骑枪 ──
func lance_ready(u: Dictionary, on: bool) -> void:
	var k := _uid(u)
	var f = _lance_on.get(k, null)
	if on:
		if f is Dictionary and is_instance_valid((f as Dictionary)["node"]):
			return
		var s := _strip(SV + "spear-lance-ready.png", 4, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.55, 10.0, true, 0.0, false, u, HEAD_H)
		if s != null:
			_lance_on[k] = _mfx.back()
	else:
		if f is Dictionary:
			_free((f as Dictionary)["node"])
		_lance_on.erase(k)


func lance_hit(u: Dictionary, t: Dictionary) -> void:
	_dir_strip(SV + "spear-lance-hit.png", 7, Vector2(t["pos"]), Vector2(t["pos"]) - Vector2(u["pos"]), 1.8, 18.0, 7.0 / 18.0, 0.8)


# ── 141 长戟 ──
func halb_sweep(u: Dictionary, fdir: Vector2, rng: float) -> void:
	var r_m: float = rng * float(battle.WS)
	var at: Vector2 = Vector2(u["pos"]) + fdir * rng * 0.45
	var s := _strip(SV + "spear-halb-sweep.png", 7, battle._world_pos(at, 0.0), maxf(1.2, r_m * 1.3), 20.0, false, 7.0 / 20.0, false, null, 0.0)
	if s != null:
		s.flip_h = fdir.x < 0.0   # 原画朝右扫
		s.position.y -= r_m * 0.25


# ── 142 盾矛 ──
func shsp_raise(u: Dictionary, sec: float) -> void:
	var s := _strip(SV + "spear-scutum.png", 4, battle._world_pos(Vector2(u["pos"]), 0.0), 1.15, 6.0, true, 0.0, false, null, 0.0)
	if s != null:
		s.scale = Vector3(1.0, 0.05, 1.0)
		_shields.append({"u": u, "node": s, "t": 0.0, "sec": sec})


func shsp_release(u: Dictionary, dir: Vector2, _sh: float, _store: float) -> void:
	for sd in _shields:
		if is_same(sd["u"], u):
			_free(sd["node"])
	_shields = _shields.filter(func(sd): return not is_same(sd["u"], u))
	var n := _dir_strip(SV + "spear-shsp-wave.png", 7, Vector2(u["pos"]), dir, 2.2, 7.0 * EqSpearBatch.SHSP_WAVE_SPD / EqSpearBatch.SHSP_WAVE_LEN, EqSpearBatch.SHSP_WAVE_LEN / EqSpearBatch.SHSP_WAVE_SPD + 0.05, 0.6)
	if n != null:
		_swv.append({"node": n, "o": Vector2(u["pos"]), "dir": dir, "r": 0.0})


func _tick_shields(delta: float) -> void:
	var keep: Array = []
	for sd in _shields:
		var u: Dictionary = sd["u"]
		var n = sd["node"]
		if n == null or not is_instance_valid(n) or not u.get("alive", false):
			_free(n)
			continue
		sd["t"] = float(sd["t"]) + delta
		var k: float = clampf(float(sd["t"]) / 0.2, 0.0, 1.0)
		(n as Sprite3D).scale = Vector3(1.0, maxf(0.05, k), 1.0)   # 0.2 秒从地上升起
		(n as Sprite3D).position = battle._world_pos(Vector2(u["pos"]) + _face(u) * 30.0, 0.0)
		var store := 0.0
		for a in (u.get("_shsp_act", {}) as Dictionary).values():
			store += float((a as Dictionary).get("store", 0.0))
		var g: float = clampf(store / maxf(1.0, float(u.get("maxHp", 1.0)) * 0.3), 0.0, 1.0)
		(n as Sprite3D).modulate = Color(1.0 + 0.7 * g, 1.0 + 0.55 * g, 1.0 + 0.1 * g, 1.0)   # 存得越多鹰徽越亮
		keep.append(sd)
	_shields = keep
	var keep2: Array = []
	for w in _swv:
		var n2 = w["node"]
		if n2 == null or not is_instance_valid(n2):
			continue
		w["r"] = minf(EqSpearBatch.SHSP_WAVE_LEN, float(w["r"]) + EqSpearBatch.SHSP_WAVE_SPD * delta)
		(n2 as Sprite3D).position = battle._world_pos(Vector2(w["o"]) + Vector2(w["dir"]) * float(w["r"]), 0.6)
		keep2.append(w)
	_swv = keep2


# ── 143 方天画戟 ──
func ftj_charge(_u: Dictionary, _frac: float) -> void:
	pass   # 挨打攒战意没有单独的画面(信息面板里有读数); 攒满那一下由 ftj_wind 起演出


func ftj_wind(u: Dictionary, wind: float, _air: float) -> void:
	_strip(SV + "spear-ftj-charge.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), 1.7, 14.0, true, wind + 0.1, false, u, 0.0)


func ftj_leap(u: Dictionary, air: float) -> void:
	_leaps.append({"u": u, "t": 0.0, "air": air})


func ftj_slam(u: Dictionary, r: float, buff: float) -> void:
	var d_m: float = r * 2.0 * float(battle.WS) * CRATER_FILL * 0.85   # 裂坑的碎石圈 ≈ 结算半径; 满尺寸不透明时铺满半个画面(11-26 夜录像)
	var cr := _strip(SV + "spear-ftj-crater.png", 9, battle._world_pos(Vector2(u["pos"]), 0.06), d_m, 14.0, false, 9.0 / 14.0, true, null, 0.0)
	if cr != null:
		cr.modulate = Color(1.0, 1.0, 1.0, 0.8)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	var s := _strip(SV + "spear-ftj-charge.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), 1.1, 12.0, true, buff, false, u, 0.0)
	if s != null:
		s.modulate = Color(1.0, 1.0, 1.0, 0.6)   # 横扫状态里脚下留一小簇余焰


func _tick_leaps(delta: float) -> void:
	var keep: Array = []
	for l in _leaps:
		var u: Dictionary = l["u"]
		l["t"] = float(l["t"]) + delta
		var k: float = clampf(float(l["t"]) / maxf(0.05, float(l["air"])), 0.0, 1.0)
		if not u.get("alive", false) or k >= 1.0:
			u["_slam_voff"] = Vector3.ZERO
			continue
		u["_slam_voff"] = Vector3(0.0, 4.0 * 3.0 * k * (1.0 - k), 0.0)   # 抛物线, 顶点 3 米
		keep.append(l)
	_leaps = keep


# ── 144 投矛器 ──
func atl_cast(_u: Dictionary, c: Vector2, r: float) -> void:
	## 落点画一块红色警示区(俯视, 虚线边 + 往里指的矛形箭头, 循环闪), 直到最后一根矛落地; 画里圆约占画布 0.9
	_strip(SV + "spear-atl-target.png", 4, battle._world_pos(c, 0.05), r * 2.0 * float(battle.WS) / 0.9, 8.0, true,
		EqSpearBatch.ATL_SPREAD_SEC + EqSpearBatch.ATL_FALL_H / EqSpearBatch.ATL_FALL_SPD, true, null, 0.0)


func atl_drop(d: Dictionary) -> void:
	if not _ok() or not ResourceLoader.exists(SV + "spear-atl-fall.png"):
		return
	var t: Texture2D = load(SV + "spear-atl-fall.png")
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.offset = Vector2(0.0, float(t.get_height()) * 0.5)
	s.pixel_size = 2.0 / float(t.get_height())   # 11-27 自查录像: 1.3 米在正常镜头下像一根细棍, 看不出是矛 ⇒ 2 米
	battle._world.add_child(s)
	var h0: float = EqSpearBatch.ATL_FALL_H * float(battle.WS)
	s.position = battle._world_pos(Vector2(d["at"]), h0)
	_fall.append({"d": d, "node": s, "t": 0.0, "dur": EqSpearBatch.ATL_FALL_H / EqSpearBatch.ATL_FALL_SPD, "h0": h0})


func atl_land(d: Dictionary, _hit: bool) -> void:
	for f in _fall:
		if is_same(f["d"], d):
			_free(f["node"])
	_fall = _fall.filter(func(f): return not is_same(f["d"], d))
	_strip(SV + "spear-atl-stuck.png", 7, battle._world_pos(Vector2(d["at"]), 0.0), 1.6, 12.0, false, 7.0 / 12.0, false, null, 0.0)


func _tick_fall(delta: float) -> void:
	for f in _fall:
		var n = f["node"]
		if n == null or not is_instance_valid(n):
			continue
		f["t"] = float(f["t"]) + delta
		var k: float = clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		(n as Sprite3D).position = battle._world_pos(Vector2(f["d"]["at"]), float(f["h0"]) * (1.0 - k))   # 按速度匀速落


func ftj_spin(u: Dictionary) -> void:
	var d_m: float = EqSpearBatch.FTJ_R * 2.0 * float(battle.WS) * RING_FILL
	_strip(SV + "spear-ftj-ring.png", 6, battle._world_pos(Vector2(u["pos"]), 0.08), d_m, 24.0, true, 0.5, true, u, 0.08)


## ── 146 圣枪(11-26 晚用户重做 · 方案书 20261126c 附录 A 分段表 · 参考 docs/studies/20261126-参考-娜美W冲击之潮.md) ──
##   ① 圣枪护盾: 一支金色长枪从头顶落下插进脚边, 地面冲击环 + 金色十字(holy-guard, 12 帧)
##   ③ 引导: 头顶细金环 + 十字星 + 刻度慢转 + 光点汇聚(holy-channel, 循环), 跟着携带者, 引导结束才收
##   ④ 光球: 白金光球 + 十字星 + 呼吸光环(holy-orb, 循环), 按飞行方向转, 按速度飞(结算在 sim, 这里只跟着画)
##   ⑤ 砸中友方: 落点金色光柱(holy-ally, 0.65 秒) + 「等级 +1」
##   ⑥ 砸中敌方: 金色十字星爆(旧圣枪自己的 spear-holy-burst) + 一颗小光点从敌人飞回携带者(对应拿到的护盾)
##   娜美 W 的办法: 同一种飞行物, 落点分两种 —— 友方是往上的光柱(增益), 敌方是往外炸的星爆(伤害)。
const HOLY_GUARD_M := 5.0       # holy-guard-up 帧高(米, 100 像素): 插住的枪露出地面约 2.5 米, 从角色头顶露出一大截
const HOLY_GUARD_BELOW := 16.0  # 帧里锚点(脚底)下面还有多少像素(打包脚本打印的)
const HOLY_GUARD_GROUND_M := 3.6  # holy-guard-ground 帧宽(米, 72 像素): 冲击环最大直径约 3 米
const HOLY_ALLY_M := 4.0        # holy-ally 帧高(米): 光柱约 3.5 米
const HOLY_ALLY_BELOW := 13.0
const HOLY_CH_M := 3.2          # holy-channel 帧高(米)
const HOLY_CH_SINK := 0.5       # 再往下沉 0.5 米: 光环离地约 1.45 米, 在血条下面(2.3 米会被血条挡住, 11-26 录像量过; 同 HEAD_H 的教训)
const HOLY_CH_BELOW := 13.0
const HOLY_ORB_M := 1.3         # 光球帧宽(米)
const HOLY_BACK_SEC := 0.35     # 敌方那颗回流光点飞回携带者的时长(纯演出)
var _holy_ch := {}              # 携带者立绘实例 id → 引导光环节点
var _holy_back: Array = []      # {node, from(Vector2), to(单位), t}
var _holy_spears: Array = []    # 插着的圣枪 {f(_mfx 那一条), t, life}: 落下(帧 0~8) → 定格插着 → 最后 3 帧碎散
const HOLY_SPEAR_HOLD := 8      # holy-guard-up 第 8 帧 = 插住、还没开始碎


## 圣枪护盾的一份(4 秒内每秒一份): 地面金环在脚下再亮一次 + 金色「+N 圣枪护盾」(和血条那段同色)
func holy_guard_tick(u: Dictionary, amt: int) -> void:
	var at := Vector2(u["pos"])
	_strip(SV + "holy-guard-ground.png", 12, battle._world_pos(at + Vector2(0.0, -12.0), 0.02), HOLY_GUARD_GROUND_M, 13.0, false, 12.0 / 13.0, true, u, 0.02)   # 往后 12 码: 圆心对上立绘脚底(11-26 录像量过)
	if amt > 0:
		battle._vfx._float_text(u["pos"] + Vector2(0, -52), Lang.t("+%d 圣枪护盾") % amt, Color("#ffc43a"), false, "shield")


func _tick_holy_spears(delta: float) -> void:
	var keep: Array = []
	for h in _holy_spears:
		var f: Dictionary = h["f"]
		var n = f["node"]
		if n == null or not is_instance_valid(n):
			continue
		h["t"] = float(h["t"]) + delta
		var t: float = float(h["t"])
		var tail: float = float(h["life"]) - 3.0 / 13.0
		f["hold"] = mini(int(t * 13.0), HOLY_SPEAR_HOLD) if t < tail else mini(HOLY_SPEAR_HOLD + 1 + int((t - tail) * 13.0), 11)
		keep.append(h)
	_holy_spears = keep


func _feet_strip(path: String, nf: int, at: Vector2, h_m: float, below_px: float, fps: float, loop: bool, life: float, follow = null, sink: float = 0.0) -> Sprite3D:
	if not ResourceLoader.exists(path):
		return null
	var th: float = float((load(path) as Texture2D).get_height())
	var off: float = below_px * h_m / maxf(1.0, th) + sink   # 锚点(脚底)对上地面: 帧底边往下挪锚点下面那几像素(sink = 再往下沉)
	return _strip(path, nf, battle._world_pos(at, -off), h_m, fps, loop, life, false, follow, -off)


## 圣枪插在角色站的位置(用户 11-26「不应该说插在人的位置吗？角色的位置上吗？」): 拆两层, 同一时间轴(12 帧 13fps)。
##   立着的(holy-guard-up): 枪落下插进角色脚下, 往画面里退 4 码 + 开深度测试 ⇒ 立在角色身后、被身体挡住, 枪杆从头顶露出一大截;
##   贴地的(holy-guard-ground, 俯视渲染): 闪光 + 冲击环 + 十字平铺在角色脚下(单位压在上面)。
##   第一版画在人前面压住身体、第二版挪到身后 46 码、第三版一张贴图开深度测试 ⇒ 地面那半圈被地面切掉 —— 都不对。
func holy_guard(u: Dictionary, resist: int) -> void:
	var at := Vector2(u["pos"])
	var life: float = float(EqSpearBatch.HOLY_GUARD_SEC) - 1.0 + 3.0 / 13.0 + 0.25   # 枪插到给完最后一份再收(最后一份在第 3 秒)
	var s := _feet_strip(SV + "holy-guard-up.png", 12, at + Vector2(0.0, -4.0), HOLY_GUARD_M, HOLY_GUARD_BELOW, 13.0, false, life)   # 插住就不动(不跟人走)
	if s != null:
		s.no_depth_test = false
		s.render_priority = -1
		_holy_spears.append({"f": _mfx.back(), "t": 0.0, "life": life})
	battle._vfx._float_text(u["pos"] + Vector2(0, -88), Lang.t("护甲和魔抗 +%d") % resist, Color("#ffe08a"))   # 分段表 ②: 双抗


func holy_channel(u: Dictionary, on: bool) -> void:
	var k := _uid(u)
	_free(_holy_ch.get(k, null))
	_holy_ch.erase(k)
	if on:
		var s := _feet_strip(SV + "holy-channel.png", 12, Vector2(u["pos"]), HOLY_CH_M, HOLY_CH_BELOW, 12.0, true, 600.0, u, HOLY_CH_SINK)
		if s != null:
			_holy_ch[k] = s


func _holy_orb_node(at: Vector2, dir: Vector2, len_m: float) -> Sprite3D:
	var path := SV + "holy-orb.png"
	if not _ok() or not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = 8
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = len_m / float(t.get_width() / 8)
	s.position = battle._world_pos(at, 1.0)
	battle._world.add_child(s)
	_orient_to(s, dir)
	_mfx.append({"node": s, "nf": 8, "fps": 12.0, "t": 0.0, "life": 600.0, "loop": true, "follow": null, "h": 1.0})
	return s


## 光球走弧线(用户 11-26「不要直直飞呀，一个弧线啊」): 结算在 sim 里按直线距离与速度(飞到碰到才算), 这里只把画面高度抬成一道抛物线 ——
##   进度 k = 已飞 / (已飞 + 剩下), 高度 = 1 米 + 弧高 × sin(πk), 弧高随两人距离(1 ~ 2 米)。落到目标那一下高度回到 1 米。
const HOLY_ORB_ARC_M := 2.0     # 弧顶最高(米)
const HOLY_ORB_ARC_MIN := 1.0   # 弧顶最低(米): 贴脸的目标也要看得出是一道弧(0.5 米时录像里像直线, 11-26)
func holy_orb_fly(u: Dictionary, tg: Dictionary, _ally: bool):
	var n := _holy_orb_node(Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), HOLY_ORB_M)
	if n != null:
		n.set_meta("from", Vector2(u["pos"]))
	return n


func holy_orb_step(node, p2: Vector2, to2: Vector2) -> void:
	if node == null or not is_instance_valid(node):
		return
	var from: Vector2 = (node as Node).get_meta("from", p2)
	var gone: float = from.distance_to(p2)
	var left: float = p2.distance_to(to2)
	var k: float = gone / maxf(1.0, gone + left)
	var arc: float = clampf((gone + left) * 0.012, HOLY_ORB_ARC_MIN, HOLY_ORB_ARC_M)
	var h: float = 1.0 + arc * sin(PI * k)
	var here: Vector3 = battle._world_pos(p2, h)
	(node as Sprite3D).position = here
	## 拖尾跟着弧线切线方向(上升段头朝上、下落段头朝下): 往前看一小步算屏幕上的走向
	var step: float = minf(12.0, left)
	var p3: Vector2 = p2 + (to2 - p2).normalized() * step if left > 0.5 else p2
	var k3: float = (gone + step) / maxf(1.0, gone + left)
	var ahead: Vector3 = battle._world_pos(p3, 1.0 + arc * sin(PI * k3))
	if ahead.distance_to(here) > 0.0001:
		_orient_screen(node, ahead - here)


func holy_orb_end(node, hit: bool, tg: Dictionary, ally: bool) -> void:
	_free(node)
	if not hit or not tg.get("alive", false):
		return
	var at := Vector2(tg["pos"])
	if ally:
		_feet_strip(SV + "holy-ally.png", 9, at, HOLY_ALLY_M, HOLY_ALLY_BELOW, 14.0, false, 9.0 / 14.0, tg)
		battle._vfx._float_text(tg["pos"] + Vector2(0, -64), Lang.t("等级 +1"), Color("#ffe08a"))
	else:
		_strip(SV + "spear-holy-burst.png", 9, battle._world_pos(at, 0.0), 2.2, 18.0, false, 9.0 / 18.0, false, null, 0.0)


## 敌方光球命中后给携带者的那层护盾: 一颗小光点从敌人飞回携带者(sim 里护盾当场就给了, 这里只是让人看得出护盾从哪来)
func holy_shield_back(from_u: Dictionary, to_u: Dictionary) -> void:
	var n := _holy_orb_node(Vector2(from_u["pos"]), Vector2(to_u["pos"]) - Vector2(from_u["pos"]), HOLY_ORB_M * 0.55)
	if n != null:
		_holy_back.append({"node": n, "from": Vector2(from_u["pos"]), "to": to_u, "t": 0.0})


func _tick_holy_back(delta: float) -> void:
	var keep: Array = []
	for b in _holy_back:
		var n = b["node"]
		if n == null or not is_instance_valid(n):
			continue
		b["t"] = float(b["t"]) + delta
		var k: float = clampf(float(b["t"]) / HOLY_BACK_SEC, 0.0, 1.0)
		var dst := Vector2((b["to"] as Dictionary)["pos"])
		var p: Vector2 = Vector2(b["from"]).lerp(dst, k * k)   # 先慢后快, 被携带者「吸」回去
		(n as Sprite3D).position = battle._world_pos(p, 1.0 + 0.6 * sin(PI * k))
		_orient_to(n, dst - p)
		if k >= 1.0:
			_free(n)
		else:
			keep.append(b)
	_holy_back = keep


# ── 筹码 ──
## 151 黑 / 152 紫: 开场每个友军头顶落下一枚旋转的筹码(0.5 秒落到胸口), 落下时一圈对应颜色的环(物理盾灰白 / 魔法盾紫)
var _drops: Array = []   # {f(_mfx 那一条), a(友军), t, phys}


func chip_team_shield(u: Dictionary, phys: bool) -> void:
	var side := str(u.get("side", ""))
	for a in battle._units:
		if not (a is Dictionary) or not (a as Dictionary).get("alive", false) or str((a as Dictionary).get("side", "")) != side:
			continue
		var s := _strip(SV + ("chip-spin-black.png" if phys else "chip-spin-purple.png"), 6, battle._world_pos(Vector2(a["pos"]), 2.6), 0.8, 14.0, true, 0.0, false, a, 2.6)
		if s != null:
			s.offset = Vector2.ZERO
			_drops.append({"f": _mfx.back(), "a": a, "t": 0.0, "phys": phys})


func _tick_drops(delta: float) -> void:
	var keep: Array = []
	for d in _drops:
		var f: Dictionary = d["f"]
		d["t"] = float(d["t"]) + delta
		var k: float = clampf(float(d["t"]) / 0.5, 0.0, 1.0)
		f["h"] = lerpf(2.6, 1.0, k * k)
		if k >= 1.0:
			_free(f["node"])
			var a: Dictionary = d["a"]
			if a.get("alive", false):
				var g := _strip(SV + "chip-shield-glint.png", 7, battle._world_pos(Vector2(a["pos"]), 0.5), 1.1, 18.0, false, 7.0 / 18.0, false, null, 0.0)
				if g != null:   # 落进胸口: 盾光一闪(物理灰白 / 魔法紫)
					g.modulate = Color(0.92, 0.92, 1.0, 1.0) if bool(d["phys"]) else Color(0.8, 0.55, 1.0, 1.0)
			continue
		keep.append(d)
	_drops = keep


## 153 黄: 登场 / 每挡掉一次控制 ⇒ 头顶黄色筹码转一圈(它自己的图标转一圈的帧条) + 胸口金色盾光(同一枚 0.5 秒内只画一次)
var _cc_last := {}


func chip_cc_block(u: Dictionary) -> void:
	var key: int = (u.get("sprite") as Object).get_instance_id() if is_instance_valid(u.get("sprite")) else 0
	var t := float(battle._t)
	if t - float(_cc_last.get(key, -9.0)) < 0.5:
		return
	_cc_last[key] = t
	var s := _strip(SV + "chip-spin-yellow.png", 6, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.8, 12.0, false, 6.0 / 12.0, false, u, HEAD_H)
	if s != null:
		s.offset = Vector2.ZERO
	var g := _strip(SV + "chip-shield-glint.png", 7, battle._world_pos(Vector2(u["pos"]), 0.5), 1.1, 18.0, false, 7.0 / 18.0, false, u, 0.5)
	if g != null:
		g.modulate = Color(1.0, 0.85, 0.3, 1.0)


func chip_grey_full(u: Dictionary) -> void:
	_strip(SV + "chip-grey-flare.png", 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 14.0, false, 7.0 / 14.0, false, u, 0.0)


## 155 金: 第 8 秒每个友军身上罩一个金色护罩(逐帧闪动, 半透明 —— 人隔着护罩看得见), 罩 3 秒
##   (11-26 夜录像自查: 原来只有一圈程序画的黄线, 看不出「护罩」; 用户 11-25 说过不许拿程序圆环交差)
func chip_gold_guard(u: Dictionary, sec: float) -> void:
	var side := str(u.get("side", ""))
	for a in battle._units:
		if not (a is Dictionary) or not (a as Dictionary).get("alive", false) or str((a as Dictionary).get("side", "")) != side:
			continue
		var s := _strip(SV + "chip-gold-dome.png", 6, battle._world_pos(Vector2(a["pos"]), -0.15), 2.2, 12.0, true, sec, false, a, -0.15)
		if s != null:
			s.modulate = Color(1.0, 1.0, 1.0, 0.5)


## 154 棕色筹码复活(11-26 夜): 倒地 ⇒ 一枚大棕色筹码在头顶转 2.5 秒(它自己的图标转一圈的帧条, 不借威尼斯的面具和光环);
##   身体半透明随血量变实与威尼斯同一段渲染(battle_render 读 _ven_until); 起身 ⇒ 筹码 0.15 秒落进胸口 + 一圈金棕环
var _browns: Array = []   # {u, f(_mfx 那一条), up(-1 = 未起)}


func chip_brown_down(u: Dictionary, sec: float) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.1, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 倒地扬土
	var s := _strip(SV + "chip-spin-brown.png", 6, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.8, 10.0, true, sec + 0.5, false, u, HEAD_H)
	if s != null:
		s.offset = Vector2.ZERO
		_browns.append({"u": u, "f": _mfx.back(), "up": -1.0})


func chip_brown_up(u: Dictionary) -> void:
	for b in _browns:
		if is_same(b["u"], u):
			b["up"] = 0.0
	_strip(SV + "chip-brown-rise.png", 7, battle._world_pos(Vector2(u["pos"]), 0.0), 2.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 起身: 金棕光柱带着筹码往上冲


func _tick_browns(delta: float) -> void:
	var keep: Array = []
	for b in _browns:
		var f: Dictionary = b["f"]
		if not is_instance_valid(f["node"]):
			continue
		if float(b["up"]) < 0.0:
			keep.append(b)
			continue
		b["up"] = float(b["up"]) + delta
		var k: float = clampf(float(b["up"]) / 0.15, 0.0, 1.0)
		f["h"] = lerpf(HEAD_H, 0.6, k * k)
		if k >= 1.0:
			_free(f["node"])
			continue
		keep.append(b)
	_browns = keep


# ── 帧推进 ──
func tick(delta: float) -> void:
	super.tick(delta)
	_tick_drops(delta)
	_tick_browns(delta)
	_tick_ropes()
	_tick_shields(delta)
	_tick_leaps(delta)
	_tick_fall(delta)
	_tick_aegis(delta)
	_tick_shocks(delta)
	_tick_stabs(delta)
	_tick_cent_glows()
	_tick_holy_back(delta)
	_tick_holy_spears(delta)
	## 百夫长登场: 预警圈 → 长矛插进圈心 → 本人从高空砸下(残影)
	var keep: Array = []
	for l in _lands:
		var u: Dictionary = l["u"]
		l["t"] = float(l["t"]) + delta
		var t: float = float(l["t"])
		var sec: float = float(l["sec"])
		var t0: float = maxf(0.0, sec - CENT_DROP_SEC)
		if t < t0:
			u["_slam_voff"] = Vector3(0.0, CENT_DROP_H, 0.0)
		else:
			var k: float = clampf((t - t0) / CENT_DROP_SEC, 0.0, 1.0)
			u["_slam_voff"] = Vector3(0.0, CENT_DROP_H * (1.0 - k * k), 0.0)   # 加速砸下(落地那一刻由 cent_impact 归零)
			var tr = l.get("tr")
			if tr != null and is_instance_valid(tr):   # 下坠光尾: 挂在本体头顶上方, 跟着往下砸
				(tr as Sprite3D).visible = k < 1.0
				(tr as Sprite3D).position = battle._world_pos(Vector2(u["pos"]), CENT_DROP_H * (1.0 - k * k) + 1.6)
			## 彗星罩裹着本体往下砸(尖端在脚下), 一路往上留星尘
			var hb: float = CENT_DROP_H * (1.0 - k * k)
			_cone_set_tick(l["comet"], battle._world_pos(Vector2(u["pos"]), hb - 0.3), Vector3.DOWN, t, 1.0, k < 1.0)
			if l.get("dust") == null and _ok():
				l["dust"] = _stream_ps(battle._world_pos(Vector2(u["pos"]), hb), Vector3.UP, 50, 0.6, 0.5, 2.0, 30.0, 0.12)
			var dps = l.get("dust")
			if dps != null and is_instance_valid(dps):
				(dps as GPUParticles3D).position = battle._world_pos(Vector2(u["pos"]), hb + 1.0)
			l["ghost"] = float(l["ghost"]) - delta
			if float(l["ghost"]) <= 0.0 and k < 1.0:
				l["ghost"] = 0.04
				_drop_ghost(u)
		var sp = l["sp"]
		if sp != null and is_instance_valid(sp):
			if t >= CENT_PLANT_T - CENT_PLANT_FALL:
				(sp as Sprite3D).visible = true
				var kk: float = clampf((t - (CENT_PLANT_T - CENT_PLANT_FALL)) / CENT_PLANT_FALL, 0.0, 1.0)
				(sp as Sprite3D).position = battle._world_pos(Vector2(u["pos"]), lerpf(CENT_PLANT_H0, -CENT_PLANT_BURY, kk * kk))
				if kk >= 1.0 and not bool(l["planted"]):
					l["planted"] = true
					## 插矛: 竖直光罩 + 地面亮光(下垫暗光) + 横向星芒 + 星点往上飘, 一直到本人砸下
					var up2 := Vector2(u["pos"])
					var rest: float = maxf(0.2, float(l["sec"]) - t + 0.1)
					_ground_glow(up2, 5.5, Color(0.14, 0.05, 0.02, 0.55), rest)
					_ground_glow(up2, 3.4, Color(1.0, 0.78, 0.38, 0.9), rest)
					l["plant_fx"] = _cone_set([
						[CONE_MIX, 2.6, 0.55, 0.0, {"col": Vector4(0.25, 0.05, 0.02, 0.45), "rim_mix": 0.5, "tail": 0.6, "apex": 0.3}, 10],
						[CONE_ADD, 2.2, 0.42, 0.0, {"col": Vector4(1.0, 0.7, 0.3, 0.6), "rim_mix": 0.6, "tail": 0.55, "apex": 1.2}, 12],
						[CONE_ADD, 2.6, 0.5, 0.0, {"col": Vector4(0.9, 0.15, 0.08, 0.45), "rim_mix": 0.5, "tail": 0.5, "apex": 0.6}, 12],
					], battle._world_pos(up2, 0.05), DOWN)
					l["plant_ps"] = _stream_ps(battle._world_pos(up2, 0.3), Vector3.UP, 40, 1.0, 2.0, 4.0, 15.0, 0.12)
					var fl := Sprite3D.new()   # 横向星芒(插地那一下)
					fl.texture = Cent3dVfx.tex("xstar.png")
					fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					fl.shaded = false
					fl.transparent = true
					fl.no_depth_test = true
					fl.render_priority = 14
					fl.modulate = Color(1.0, 0.88, 0.6, 1.0)
					fl.pixel_size = 2.0 / float(fl.texture.get_width())
					fl.scale = Vector3(3.0, 0.35, 1.0)
					fl.position = battle._world_pos(up2, 0.4)
					battle._world.add_child(fl)
					_mfx.append({"node": fl, "nf": 1, "fps": 0.0, "t": 0.0, "life": 0.35, "loop": false, "follow": null, "h": 0.0})
					_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 2.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)
					_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(u["pos"]), 0.3), 2.6, 20.0, false, 6.0 / 20.0, false, null, 0.0)
					battle._shake(battle.JUICE_SHAKE_HEAVY * 0.35)
		if bool(l["planted"]):
			_cone_set_tick(l["plant_fx"], battle._world_pos(Vector2(u["pos"]), 0.05), Vector3.DOWN, t, 1.0, true)
		if t >= sec or not u.get("alive", false):
			u["_slam_voff"] = Vector3.ZERO
			_cone_set_free(l.get("comet"))
			_cone_set_free(l.get("plant_fx"))
			_stop_ps(l.get("dust"))
			_stop_ps(l.get("plant_ps"))
			var tr2 = l.get("tr")
			if tr2 != null and is_instance_valid(tr2):
				(tr2 as Node).queue_free()   # 落地那一刻收掉下坠光尾(11-27 录像: 原来竖在头顶上方又留了 0.7 秒)
			if sp != null and is_instance_valid(sp):
				_mfx.append({"node": sp, "nf": 1, "fps": 0.0, "t": 0.0, "life": 0.3, "loop": false, "follow": null, "h": 0.0})   # 插地长矛落地后淡掉删除(统一推帧, 直播录得到)
			continue
		keep.append(l)
	_lands = keep
	## 飞矛 / 投矛器的矛 / 骑兵: 位置跟 sim
	for r in _spear_nodes:
		var n = r["node"]
		if n != null and is_instance_valid(n):
			(n as Sprite3D).position = battle._world_pos(Vector2(r["s"]["pos"]), 1.0)
			if r.get("fx") is Dictionary:   # 百夫长飞矛: 分层特效跟着矛头
				_jav_tick(r["fx"], (n as Sprite3D).position + Vector3(r["d3"]) * JAV_HEAD, Vector3(r["d3"]), delta)
	for r3 in _cav_nodes:
		var n3 = r3["node"]
		if n3 != null and is_instance_valid(n3):
			var cp: Vector2 = Vector2(r3["c"]["pos"])
			var face: float = 1.0 if Vector2(r3["c"]["dir"]).x > 0.0 else -1.0
			(n3 as Sprite3D).position = battle._world_pos(cp, 0.0)
			for pt in r3.get("parts", []):
				if pt["n"] != null and is_instance_valid(pt["n"]):
					(pt["n"] as Sprite3D).position = battle._world_pos(cp - Vector2(face, 0.0) * float(pt["back"]), float(pt["h"]))
			var bw = r3.get("bow")
			if bw != null and is_instance_valid(bw):   # 能量罩: 罩在人马身上(中心离地 1.15 米), 气流按时间往后流; 最后 0.25 秒淡掉
				r3["bt"] = float(r3.get("bt", 0.0)) + delta
				(bw as MeshInstance3D).position = battle._world_pos(cp + Vector2(r3["c"]["dir"]) * 10.0, 1.15)
				var bm: ShaderMaterial = (bw as MeshInstance3D).material_override
				bm.set_shader_parameter("t", float(r3["bt"]))
				var cf: float = clampf(float(r3["c"]["left"]) / (SpearSynergySystem.CAV_SPD * 0.25), 0.0, 1.0) * minf(1.0, float(r3["bt"]) / 0.15)
				bm.set_shader_parameter("fade", cf)
				var fxc = r3.get("fxc")
				if fxc is Dictionary:
					var cd2: Vector2 = Vector2(r3["c"]["dir"])
					var shell_p: Vector3 = battle._world_pos(cp + cd2 * 10.0, 1.15)
					var dk = fxc.get("dark")
					if dk != null and is_instance_valid(dk):
						(dk as MeshInstance3D).position = shell_p
						var dm: ShaderMaterial = (dk as MeshInstance3D).material_override
						dm.set_shader_parameter("t", float(r3["bt"]))
						dm.set_shader_parameter("fade", cf)
					for gb in fxc["bills"]:
						if gb["node"] != null and is_instance_valid(gb["node"]):
							(gb["node"] as Sprite3D).position = shell_p
							var gc: Color = gb["col"]
							(gb["node"] as Sprite3D).modulate = Color(gc.r, gc.g, gc.b, gc.a * cf)
					var d3c := Vector3(cd2.x, 0.0, cd2.y)
					_cone_set_tick(fxc["wake"], battle._world_pos(cp + cd2 * 70.0, 1.0), d3c, float(r3["bt"]), cf, true)
					var wp = fxc.get("ps")
					if wp != null and is_instance_valid(wp):
						(wp as GPUParticles3D).position = battle._world_pos(cp, 1.2)
					## 地上沟痕: 暗沟 + 发光线(研究稿 MakerTrench 暗沟 + 发光裂纹), 每 0.05 秒落一点, 暗沟留 1 秒、亮线留 0.35 秒
					r3["trench_t"] = float(r3.get("trench_t", 0.0)) + delta
					if float(r3["trench_t"]) >= 0.05 and cf > 0.3:
						r3["trench_t"] = 0.0
						_ground_glow(cp - cd2 * 30.0, 1.3, Color(0.16, 0.08, 0.03, 0.45), 1.0)
						_ground_glow(cp - cd2 * 30.0, 0.55, Color(1.0, 0.72, 0.3, 0.8), 0.35)
			r3["dust_t"] = float(r3.get("dust_t", 0.0)) + delta
			if float(r3["dust_t"]) >= 0.08:   # 马蹄一路扬土(底层扬尘)
				r3["dust_t"] = 0.0
				var ds := _strip(LION_DUST, 7, battle._world_pos(cp - Vector2(face, 0.0) * 40.0, 0.0), 0.55, 16.0, false, 7.0 / 16.0, false, null, 0.0)
				if ds != null:
					ds.flip_h = face < 0.0


func clear() -> void:
	super.clear()
	_cent_glows.clear()
	for k in _holy_ch:
		_free(_holy_ch[k])
	_holy_ch.clear()
	for b in _holy_back:
		_free(b["node"])
	_holy_back.clear()
	_holy_spears.clear()
	_drops.clear()
	_browns.clear()
	_cc_last.clear()
	_lance_on.clear()
	for a in _aegis:
		_aegis_free(a)
	_aegis.clear()
	for r in _rays:
		_free(r["node"])
	_rays.clear()
	for j in _aegis_junk:
		_free(j["node"])
	_aegis_junk.clear()
	for sk in _shocks:
		_free(sk["node"])
	_shocks.clear()
	for st in _stabs:
		for p in st["parts"]:
			_free(p["node"])
		for b in st["bills"]:
			_free(b["node"])
		_free(st.get("ring"))
		for f in st.get("front", []):
			_free(f)
		_free(st.get("spray"))
		_free(st.get("arrow"))
		_free(st.get("haze"))
	_stabs.clear()
	_wave_wait.clear()
	for r4 in _cav_nodes:
		_free(r4.get("bow"))
		_cav_fx_free(r4.get("fxc"), true)
		for pt in r4.get("parts", []):
			_free(pt["n"])
	for r5 in _spear_nodes:   # 清场直接删(不进 _aegis_junk: 它在上面已经清过)
		var f5 = r5.get("fx")
		if f5 is Dictionary:
			for p5 in f5.get("parts", []):
				_free(p5["node"])
			for b5 in f5.get("bills", []):
				_free(b5["node"])
			_free(f5.get("ps"))
	for arr in [_spear_nodes, _cav_nodes, _ropes, _shields, _swv, _fall]:
		for r in arr:
			_free(r["node"])
	_spear_nodes.clear()
	_cav_nodes.clear()
	_ropes.clear()
	_shields.clear()
	_swv.clear()
	_fall.clear()
	for l in _leaps:
		if (l["u"] as Dictionary).has("_slam_voff"):
			(l["u"] as Dictionary)["_slam_voff"] = Vector3.ZERO
	_leaps.clear()
	_lands.clear()
