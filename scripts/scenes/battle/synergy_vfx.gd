class_name SynergyVfx
extends RefCounted

## synergy_vfx.gd — 十条羁绊【演出层】的共用基建 (方案书 docs/plans/20260804-羁绊特效批.md · 批 A · A1)
##
## ★这份文件现在【还没有任何业务调用方】—— 这是 A1 的设计，不是漏接线。
##   方案书批 A 原文:「先建壳, 后面每条只加一行」; 批 B/C 的每条羁绊演出
##   才会写成 `battle._vfx._syn.ground_ring(...)` 这样的一行。
##   在那之前, 唯一的调用方是门禁 tests/verify_synergy_vfx.gd。
##   ⚠ 所以别拿"某函数存在"当验收 —— 见 memory [[fb-verify-must-run-the-real-path]]。
##   接线证据是 BattleVfx._init 里真的 new 了一份 (battle._vfx._syn != null), 门禁第 ① 组断言的就是它。
##
## ★为什么不直接用 battle._skill_ring / _beam_vfx / _glow_bb 而要再包一层 (方案书 R2):
##   主场景那几个入口【不守 _world == null】(RB:_skill_ring / _splash_ring_bold / _bolt_line /
##   _burst_vfx / _fly_vfx / _aura_vfx / _beam_vfx / _glow_bb 全都直接 _world.add_child)。
##   在"只建单位不建世界"的数值测试里那是 SCRIPT ERROR 而不是 FAIL, 会被 run-tests.sh 的
##   FATAL 正则接住 ⇒ 整批红且看着像别的问题。本层每个入口都先过 _has_world()。
##
## ★零素材 (用户铁律「不要复用素材除非我指明了」, 2026-08-03 定 / 08-04 重申):
##   本层所有贴图都是 VfxTex 逐像素现算的 —— 程序化生成【不产出可复用的图】,
##   同 vfx_textures.gd:23-25 已确立的立场。门禁 ⑧ 断言这些贴图的 resource_path 是空串
##   (即"不是从磁盘 load 来的资源")。
##
## ★贴地类只设 axis, 【不加 rotation】(方案书 R10 / memory [[fb-axis-y-plus-rotation-cancels]]):
##   Sprite3D.axis = AXIS_Y 本身就是平铺, 再叠 rotation.x = -90 会把它掰成竖环
##   (|世界法线·上| 从 1.000 变 0.000, 2026-07-30 立了整整一场)。
##   ice_system 里那个 -90 是对的, 因为【它没设 axis】—— 别抄一半。
##   门禁 ④ 量的就是 |世界法线·上| > 0.99。
##
## ★撤场 (方案书 R7): 本层建的每个节点都进 _owned; clear() 一次性 free 掉还活着的。
##   换路时 _dl_clear_units() 只 free 单位、_reg_tween 只 kill tween, 【不会】动挂在 _world 上的节点。


## 节点上打的自定义 meta 键。
## ★门禁按 meta 数而不是按节点名/贴图路径数 —— 程序生成的贴图 resource_path 是空串,
##   按路径数会全部数成 0 (verify_ms_tier_vfx.gd:164 那条注释记的就是这个坑)。
const META_KEY := "synergy_vfx"

## _owned 的上限, 照 RB:_reg_tween 的 512 一样是"最后一道闸"(方案书 R12 手机端预算)。
const OWNED_CAP := 256

var battle

## 本层建出来、还没自销的节点 (R7 撤场用)。存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []

## 【批 B·B2】怒气冲击波的爆轰模型 (Sedov–Taylor + Friedlander)。见 shockwave_vfx.gd。
var _shock: ShockwaveVfx = null
## 正在播的冲击波句柄。每帧由 tick() 推进 —— **不用 tween**:
##   ① 无头 CI 下 create_tween 推进不稳(CLAUDE.md §3.5), ② 走 sim 的 delta 才跟时停/换路同步。
var _shocks: Array = []


func _init(b) -> void:
	battle = b
	_shock = ShockwaveVfx.new(b)


## 世界在不在 (R2)。所有对外入口的第一行都是它。
func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


## 挂进 _world + 打 meta + 记账。
func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


# ============================================================================
#  §原语 —— 批 B/C 的每条羁绊演出都从这里取
# ============================================================================

## 贴地环。radius_px = 场地【像素】半径 (与 battle._skill_ring 的 2D 接口同口径)。
##   bold=true → 双层 + 关深度测试 (地板/珊瑚高度盖不住, 同 RB:_splash_ring_bold)。
##   返回主环节点; 世界不在时返回 null。
##
## ⚠ 参数在【本函数返回时就已经是最终值】, tween 只负责放大/淡出 ——
##   这样门禁下一行就能判, 不用等任何动画 (方案书 §7.1)。
func ground_ring(pos2d: Vector2, col: Color, radius_px: float, bold: bool = false, dur: float = 0.35) -> Node3D:
	if not _has_world():
		return null
	var tex := VfxTex._make_ring_texture(col)
	var target_ps: float = (radius_px * 2.0 * battle.WS) / float(maxi(1, tex.get_width()))
	var main: Sprite3D = null
	var layers: int = 2 if bold else 1
	for k in range(layers):
		var r := Sprite3D.new()
		r.texture = tex
		r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		r.axis = Vector3.AXIS_Y
		r.shaded = false
		r.transparent = true
		if bold:
			r.no_depth_test = true
			r.render_priority = 11
		var fade: float = 1.0 if k == 0 else 0.55
		r.modulate = Color(col.r, col.g, col.b, col.a * fade)
		r.position = battle._world_pos(pos2d, 0.05)
		var ps_k: float = target_ps * (1.0 if k == 0 else 1.22)
		r.pixel_size = ps_k * 0.4
		_adopt(r, "ground_ring")
		# ★把【最终】pixel_size 记在节点自己身上, 门禁量真实对象而不是在测试里把公式抄一遍。
		#   memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」——
		#   把产品代码改成写死坐标, 抄公式的那条门禁照样绿。
		r.set_meta("target_ps", ps_k)
		var tw: Tween = battle._reg_tween()
		tw.set_parallel(true)
		tw.tween_property(r, "pixel_size", ps_k, dur * (1.0 if k == 0 else 1.25))
		tw.tween_property(r, "modulate:a", 0.0, dur * (1.0 if k == 0 else 1.25))
		tw.chain().tween_callback(r.queue_free)
		if k == 0:
			main = r
	return main


## 贴地能量带 A→B (收殓的灵魂流 / 炮台的能量束 / 冲击波的能量带都走它)。
##   width_px = 带宽的场地像素数。贴图是 VfxTex 现算的激光束 (零素材)。
##   几何照 RB:_beam_vfx (沿 +X 拉伸 + rotation.y 对齐), 但【守 _world】且零素材。
func energy_band(a2d: Vector2, b2d: Vector2, col: Color, width_px: float = 26.0, dur: float = 0.32) -> Node3D:
	if not _has_world():
		return null
	var wf: Vector3 = battle._world_pos(a2d, 0.35)
	var wt: Vector3 = battle._world_pos(b2d, 0.35)
	var seg: Vector3 = wt - wf
	var seg_len: float = seg.length()
	if seg_len < 0.01:
		return null
	var tex := VfxTex._make_laser_beam_tex(col)
	var th: int = maxi(1, tex.get_height())
	var tw_px: int = maxi(1, tex.get_width())
	var ps: float = (width_px * battle.WS) / float(th)
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 10
	s.modulate = Color(col.r, col.g, col.b, col.a)
	s.pixel_size = ps
	s.position = wf + seg * 0.5
	s.rotation.y = -atan2(seg.z, seg.x)
	s.scale = Vector3(seg_len / maxf(0.001, float(tw_px) * ps), 1.0, 1.0)
	_adopt(s, "energy_band")
	var tw: Tween = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(s.queue_free)
	return s


## 柱状光 (共鸣 / 觉醒 / 破土的那一下)。height_m = 光柱世界高度 (米)。
##   ★用 BILLBOARD_FIXED_Y 而不是 BILLBOARD_ENABLED —— 全轴 billboard 会让光柱
##   随相机俯仰倒下去; FIXED_Y 只绕 Y 转, 柱子永远竖着。
func light_pillar(pos2d: Vector2, col: Color, height_m: float = 4.2, dur: float = 0.55) -> Node3D:
	if not _has_world():
		return null
	var tex := VfxTex._make_lightshaft_texture()
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.transparent = true
	s.modulate = Color(col.r, col.g, col.b, 0.0)
	s.pixel_size = height_m / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(pos2d, height_m * 0.5)
	_adopt(s, "light_pillar")
	var tw: Tween = battle._reg_tween()
	tw.tween_property(s, "modulate:a", col.a, dur * 0.22)
	tw.tween_interval(maxf(0.02, dur * 0.34))
	tw.tween_property(s, "modulate:a", 0.0, dur * 0.44)
	tw.tween_callback(s.queue_free)
	return s


## 一次性 GPU 粒子迸发 (方案书 §2.5 路线②·零素材)。
##   ★门禁只断言【节点与参数】, 绝不数粒子 —— 无头 dummy renderer 下 GPU 模拟大概率不跑
##   (方案书 R11)。参数在本函数返回时就是最终值。
func spark_burst(pos2d: Vector2, col: Color, height: float = 0.6, amount: int = 18) -> Node3D:
	if not _has_world():
		return null
	var ps := GPUParticles3D.new()
	ps.amount = maxi(1, amount)
	ps.lifetime = 0.45
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.22
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 70.0
	mat.initial_velocity_min = 1.8
	mat.initial_velocity_max = 4.2
	mat.gravity = Vector3(0, -6.5, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.05
	mat.color = col
	ps.process_material = mat
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = VfxTex._make_fire_glow_tex()
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1, 1, 1, 1)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = battle._world_pos(pos2d, height)
	_adopt(ps, "spark_burst")
	ps.emitting = true
	var tw: Tween = battle._reg_tween()
	tw.tween_interval(ps.lifetime + 0.2)
	tw.tween_callback(ps.queue_free)
	return ps


# ============================================================================
#  §批 B·B2 —— 盾【怒气冲击波】
# ============================================================================

## 怒气冲击波的伤害数字色 (shield_synergy_system.gd:101 用的就是这个)。
## 演出与数字同色, 玩家才能把"这个波"和"那个数"连起来。
const RAGE_COL := Color(1.0, 0.851, 0.239, 0.95)      # #ffd93d

## 放一发怒气冲击波。**羁绊系统侧只写这一行。**
##
## ★fired = 本次 `_rage` 里连发了几次 —— 未决点 U2 用户拍板 **B「同帧合并成一个更大的」**。
##   合并倍率不是拍的: Hopkinson–Cranz 立方根定律 R ∝ W^(1/3)(见 shockwave_vfx.gd 文件头 ④)。
##   ⚠ **合并的只有演出**: 伤害与护盾照旧一次不少地发 fired 次。
##
## src2 = 施放者位置; tgt2 = 被打的那个敌人的位置 (用来画"是谁挨了这一下")。
func rage_shockwave(src2: Vector2, tgt2: Vector2, fired: int) -> Dictionary:
	if not _has_world():
		return {}
	var h: Dictionary = _shock.make_blast(src2, RAGE_COL, fired)
	if h.is_empty():
		return {}
	_adopt(h["shock"], "shockwave")
	_adopt(h["ring"], "shockwave_ring")
	_adopt(h["dust"], "shockwave_dust")
	_shocks.append(h)
	# 从施放者到被打者的一道能量带 —— 冲击波本身是全向的, 这条带才说明"命中的是他"。
	if tgt2.distance_squared_to(src2) > 1.0:
		energy_band(src2, tgt2, RAGE_COL, 22.0, 0.26)
		spark_burst(tgt2, RAGE_COL, 0.5, 14)
	# 轻震: 5 连发也只到 0.077 < JUICE_SHAKE_HEAVY(0.10), 见 SHAKE_BASE 注释
	battle._shake(ShockwaveVfx.SHAKE_BASE * ShockwaveVfx.energy_scale(fired))
	return h


## 每帧推进正在播的冲击波。接线在 `shield_synergy_system.tick()` 第一行。
## ★不走 tween: 无头 CI 下 tween 推进不稳(CLAUDE.md §3.5), 而且走 sim 的 delta
##   才能跟时停/换路同步 —— 同 `_tentacle_vfx.tick(dt)` 的做法。
func tick(delta: float) -> void:
	if _shocks.is_empty():
		return
	var keep: Array = []
	for h in _shocks:
		if _shock.advance(h, delta):
			keep.append(h)
			continue
		for k in ShockwaveVfx.NODE_KEYS:
			var n = h[k]
			if is_instance_valid(n):
				n.queue_free()
	_shocks = keep


# ============================================================================
#  §跨阈值只放一次 —— 纯函数, 不烘任何数字
# ============================================================================

## value 跨过了几个阈值 (thresholds 必须升序)。0 = 一个都没跨。
## ★阈值【由调用方传】, 本层不烘数字 —— 四条滚雪球的具体档位是方案书 U4, 用户还没拍板。
func tier_of(value: float, thresholds: Array) -> int:
	var t := 0
	for x in thresholds:
		if value >= float(x):
			t += 1
	return t


## 档位是否【刚刚涨上去】。同档反复喂返回 false, 跨进下一档返回 true。
##   store 是随便一个存放状态的 Dictionary (通常就是单位字典)。
##   ⚠ 只把它当【容器】用, 绝不拿单位字典当别的 Dictionary 的 key —— CLAUDE.md §3.2。
##   档位【回落】时静默同步 (不放特效, 但下次再涨回来要能重放)。
func tier_advance(store: Dictionary, key: String, tier: int) -> bool:
	if store == null:
		return false
	var prev: int = int(store.get(key, 0))
	if tier <= prev:
		store[key] = tier
		return false
	store[key] = tier
	return true


# ============================================================================
#  §撤场 (R7)
# ============================================================================

## free 掉本层建出来、还活着的所有节点; 返回真的 free 掉几个。
## 换路 / 战斗结束时调 —— _dl_clear_units() 只 free 单位, 不会动这些。
func clear() -> int:
	var freed := 0
	for n in _owned:
		if is_instance_valid(n):
			n.queue_free()
			freed += 1
	_owned.clear()
	## ★句柄表也要清 —— 只 free 节点不清表, 下一帧 tick() 会拿着已 free 的句柄
	##   继续 advance(), 那是"写了没人清"的另一半 (memory [[fb-write-without-reader-and-fake-gates]])。
	_shocks.clear()
	return freed


## 本层还活着的节点数 (kind 为空 = 不筛类型)。调试/自检用。
func alive_count(kind: String = "") -> int:
	var n := 0
	for x in _owned:
		if not is_instance_valid(x):
			continue
		if kind != "" and str(x.get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
