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

## 常驻炮台("side|idx" → {root,yaw,barrel,mat_r,recoil})。
## ★炮台是常驻结构, 不进 _fx 那种"活一会儿就没"的队列。
var _turrets: Dictionary = {}
var _mesh_tur_base: ArrayMesh = null
var _mesh_tur_barrel: ArrayMesh = null

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


## 【批 B3】多边形轮廓环 —— **本层第二个形状**。
##
## ★为什么不是"再加一个圆环就够了"：十类羁绊里有四类都要"脚下一圈"
##   (弓箭腐蚀 / 奇械僵硬 / 遗物古纹 / 食物成长)。全用 `ground_ring` 的话，
##   同场时它们只差一个颜色 —— 这正是装备那边踩过的坑
##   (四件召唤物共用一个白光球，玩家分不出谁是谁)。
##   多边形给的是**剪影级**的区分：3 边(弓箭·尖锐啃噬) / 6 边(奇械·结晶) / 8 边(遗物·石阵)，
##   缩到 30 像素也还能一眼分开，而四个同心圆不能。
##
## ★仍然零素材：贴图是本函数逐像素现算的(同 VfxTex 的立场)，`resource_path` 是空串。
## ★贴地规矩同 `ground_ring`：只设 `axis = AXIS_Y`，**不加 rotation**(R10)。
static var _poly_tex_cache: Dictionary = {}
static func _make_poly_ring_tex(sides: int) -> ImageTexture:
	var n: int = clampi(sides, 3, 12)
	if _poly_tex_cache.has(n):
		return _poly_tex_cache[n]
	var N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) * 0.5
	var rmax := c - 3.0
	var step := TAU / float(n)
	var apo: float = cos(PI / float(n))       # 外接圆 → 内切圆(边中点)的比
	# ★线宽是【看图定的】不是拍的: 第一版 half_w=2.0, 实拍(shots/bow_corrode_full_hit1.png)
	#   在 zoom=3 下只有约 3.4 屏幕像素, 酸绿细线压在青蓝地图上几乎读不出。加粗 30%。
	var half_w := 2.6                          # 线半宽(纹理像素)
	var soft := 2.0                            # 软边宽度
	for y in range(N):
		for x in range(N):
			var dx := float(x) - c
			var dy := float(y) - c
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.5:
				continue
			# 该极角上多边形边界的半径 (正 n 边形的极坐标方程)
			var k: float = fposmod(atan2(dy, dx) + step * 0.5, step) - step * 0.5
			var rb: float = rmax * apo / maxf(0.2, cos(k))
			var d: float = absf(r - rb)
			if d > half_w + soft:
				continue
			var a: float = clampf(1.0 - maxf(0.0, d - half_w) / soft, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_poly_tex_cache[n] = t
	return t


## 贴地多边形环。参数与 `ground_ring` 同口径(radius_px = 场地像素外接半径)。
## ⚠ 与 `ground_ring` 一样：**返回时参数已是最终值**，tween 只放大/淡出 ⇒ 门禁下一行就能判。
func polygon_ring(pos2d: Vector2, col: Color, radius_px: float, sides: int = 6,
		bold: bool = false, dur: float = 0.42) -> Node3D:
	if not _has_world():
		return null
	var tex := _make_poly_ring_tex(sides)
	var target_ps: float = (radius_px * 2.0 * battle.WS) / float(maxi(1, tex.get_width()))
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.transparent = true
	if bold:
		s.no_depth_test = true
		s.render_priority = 11
	s.modulate = col
	s.position = battle._world_pos(pos2d, 0.05)
	s.pixel_size = target_ps * 0.45
	_adopt(s, "polygon_ring")
	# 同 ground_ring: 把【最终】pixel_size 与边数记在节点自己身上, 门禁量真实对象不抄公式。
	s.set_meta("target_ps", target_ps)
	s.set_meta("sides", clampi(sides, 3, 12))
	var tw: Tween = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "pixel_size", target_ps, dur)
	tw.tween_property(s, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(s.queue_free)
	return s


## 【批 B3】一点 → 多点的辐射能量带 (第三个构图母题)。
##
## ★它不是新贴图，是 `energy_band` 的**编排**：一个中心向 N 个目标同时拉带。
##   写成独立入口的理由有两条，都不是"图省事"：
##   ① "谁向谁"这件事本身就是要传达的信息(第二座炮台的护盾/弹幕相位、战利品的"从这具尸体分给全队")；
##   ② 门禁要能【单独断言这一条】—— 埋在调用方的 for 循环里就只能断言"带的总数"，
##      而那个数会被同帧别的带污染。
## 返回真的画出来几条(零长度的会被 `energy_band` 自己挡掉)。
func radial_spokes(from2d: Vector2, tos: Array, col: Color, width_px: float = 20.0,
		dur: float = 0.30) -> int:
	if not _has_world():
		return 0
	var n := 0
	for p in tos:
		if not (p is Vector2):
			continue
		if energy_band(from2d, p as Vector2, col, width_px, dur) != null:
			n += 1
	return n


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
#  §批 B3 —— 另外七类羁绊的演出入口 (2026-08-06)
#
#  ★★【一类一个视觉母题】。这不是审美偏好, 是上一轮的教训:
#    装备那边四件召唤物共用同一个白光球, 玩家分不出谁是谁。
#    同一场里可能同时亮着 3~4 类羁绊, 所以【形状】必须先分开, 颜色只是第二道。
#
#  | 类型 | 形状母题 | 颜色 | 已有/新增 |
#  |---|---|---|---|
#  | 盾   | **圆形冲击波**(Sedov–Taylor) | 琥珀 #ffd93d | 已有(B2) |
#  | 灵物 | **实体触手**(程序化管状网格)  | 紫 #b388ff   | 已有(tentacle_vfx) |
#  | 弓箭 | **三角环**(尖锐=腐蚀啃噬)     | 酸绿 #a8e063 | 本批 |
#  | 奇械 | **六边环**(结晶/齿轮)         | 冰青 #7fe3ff | 本批 |
#  | 遗物 | **八边环 + 金柱**(古代石阵)   | 古金 #d4a34a | 本批 |
#  | 法器 | **竖直光柱**(施法感)          | 蓝紫 #9b8cff | 本批 |
#  | 枪   | **柱 + 辐射带**               | 深橙#ff7043 / 正蓝#4d8cff(两相位) | 本批 |
#  | 食物 | **圆环上涨 + 上升火花**       | 翠绿 #4fd97f | 本批 |
#  | 药水 | **辐射带**(从尸体分给全队)    | 品红 #e64bd0 | 本批 |
#  | 剑   | (本批不做, 见文件末尾 §未做)  | — | — |
#
#  ★铁律: **本节每个函数都不参与任何结算** —— 只读位置、只建节点。
#    调用方在伤害/治疗结算【完】之后才调它, 且每个入口都能被门禁单独调用
#    (CLAUDE.md §3.5: 数值测试不许依赖 tween 跑完)。
# ============================================================================

## ★★这 12 个颜色【两两的 RGB 距离必须 > 0.15】，门禁 `verify_synergy_vfx_types` ⑤ 组守着。
##   第一版有四对没过(最惨的 0.074)，是门禁抓出来的，不是我先想到的：
##     · 枪·护盾 #7fd0ff ↔ 奇械 #7fe3ff = **0.074**  (两个几乎一样的浅蓝)
##     · 枪·弹幕 #ffb74d ↔ 药水 #ff9f43 = 0.101      (而且两条【都是辐射带】，形状也一样)
##     · 食物 #8bd96a ↔ 弓箭 #a8e063   = 0.121
##     · 盾 #ffd93d ↔ 枪·弹幕 #ffb74d  = 0.147
##   ⇒ 改成下面这组(枪·弹幕转深橙、枪·护盾转正蓝、食物转翠绿、生死界转绯红)。
##   第二版又被门禁抓出一条更隐蔽的: 枪·弹幕 ↔ 药水 **形状也一样**(两条都是辐射带),
##     颜色只差 0.185 —— 同形状的两条撞色比不同形状的严重得多,
##     所以门禁对"同形状"那一档要求 > 0.30。⇒ 药水改成**品红** #e64bd0(与 🧪 也更搭)。
##   现在: 任意两条最接近 0.172(遗物·觉醒 ↔ 盾·收殓一档), 同形状最接近 0.427。
##   ⚠ 别"顺手调好看一点" —— 调之前先跑那条门禁，它会告诉你撞了哪一对。
const COL_GUN_BARRAGE := Color(1.0, 0.439, 0.263, 0.95)    # #ff7043 枪·弹幕相位(深橙)
const COL_GUN_SHIELD  := Color(0.302, 0.549, 1.0, 0.95)    # #4d8cff 枪·护盾相位(正蓝)
const COL_STAFF       := Color(0.608, 0.549, 1.0, 0.95)    # #9b8cff 法器(蓝紫)
const COL_STAFF_PURE  := Color(1.0, 1.0, 0.925, 0.95)      # 净化 = 近白
const COL_RELIC       := Color(0.831, 0.639, 0.290, 0.95)  # #d4a34a 遗物(古金)
const COL_RELIC_LOW   := Color(0.878, 0.192, 0.192, 0.95)  # #e03131 生死界跌破 50%(绯红)
const COL_FOOD        := Color(0.310, 0.851, 0.498, 0.95)  # #4fd97f 食物(翠绿)
const COL_POTION      := Color(0.902, 0.294, 0.816, 0.95)  # #e64bd0 药水(品红)
const COL_BOW         := Color(0.659, 0.878, 0.388, 0.95)  # #a8e063 弓箭(酸绿)
const COL_GADGET      := Color(0.498, 0.890, 1.0, 0.95)    # #7fe3ff 奇械(冰青)
const COL_SHIELD_REAP := Color(1.0, 0.914, 0.659, 0.95)    # #ffe9a8 盾·收殓(与既有反击同色)

## 各类型的多边形边数 —— **母题的核心**, 改这三个数就是改玩家认牌的方式。
const SIDES_BOW := 3
const SIDES_GADGET := 6
const SIDES_RELIC := 8


# ── 枪 ───────────────────────────────────────────────────────────────────────

## 枪·第一座炮台开火(每 2.5 秒)。origin=炮位, end2d=射线终点, hits=被打中的敌人位置。
##
## ★现状是一条 900 码长的 `_bolt_line` 从**看不见的地方**射出来 —— 玩家读不到"有一座炮台"。
##   本入口在【炮位】上放一根矮光柱(开火那一下才有), 加上命中点的火花。
## ⚠ **不建常驻本体**: U6「逻辑实体要不要画本体」用户尚未拍板,
# ══════════════════════════════════════════════════════════════════
#  §枪·炮台实体(2026-08-12 用户:「比如枪, 炮台我完全没看到啊」)
# ══════════════════════════════════════════════════════════════════
## 实拍复核: 炮台**根本没有实体** —— 只有每 2.5 秒在炮位闪 0.32 秒的一根光柱,
## 而炮位在场地 12%/18% 宽处(队伍后方) ⇒ 玩家看到的是"凭空飞来一条橙线"。
## ⇒ 造一座【常驻】炮台: 六棱底座 + 顶盖 + 可转炮塔与炮管; 开火时转向目标 + 后坐 + 炮口闪。
## ★炮台不是单位(无血量/不被选中/不参与选靶), 所以它只是演出层的常驻节点, 由 tick 保活。

## 炮台尺寸(码): 底座半径 / 底座高 / 炮管长
const TURRET_R_PX := 34.0
const TURRET_H_PX := 46.0
const TURRET_BARREL_PX := 46.0
## 后坐位移(码)与恢复时间常数(秒)
const TURRET_RECOIL_PX := 12.0
const TURRET_RECOIL_TAU := 0.16


## 六棱底座 + 顶盖(单位尺度: 半径 1 / 高 1)
static func _build_turret_base() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hi := Color(1, 1, 1, 1.0)
	var mid := Color(1, 1, 1, 0.72)
	var lo := Color(1, 1, 1, 0.34)
	for k in range(6):
		var t0: float = float(k) * TAU / 6.0
		var t1: float = float(k + 1) * TAU / 6.0
		_tri3(st, [Vector3(cos(t0), 0.0, sin(t0)), lo], [Vector3(cos(t0), 1.0, sin(t0)), mid],
			[Vector3(cos(t1), 1.0, sin(t1)), mid])
		_tri3(st, [Vector3(cos(t0), 0.0, sin(t0)), lo], [Vector3(cos(t1), 1.0, sin(t1)), mid],
			[Vector3(cos(t1), 0.0, sin(t1)), lo])
	for k2 in range(6):
		var u0: float = float(k2) * TAU / 6.0
		var u1: float = float(k2 + 1) * TAU / 6.0
		_tri3(st, [Vector3(0.0, 1.02, 0.0), hi],
			[Vector3(cos(u0) * 0.92, 1.0, sin(u0) * 0.92), mid],
			[Vector3(cos(u1) * 0.92, 1.0, sin(u1) * 0.92), mid])
	return _commit3(st)


## 炮管(单位长: 沿 +X 伸出 1, 方管) + 炮口环
static func _build_turret_barrel() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hi := Color(1, 1, 1, 1.0)
	var mid := Color(1, 1, 1, 0.70)
	var w := 0.24
	for axis in [Vector3(0, w, 0), Vector3(0, 0, w)]:
		_tri3(st, [Vector3.ZERO + axis, mid], [Vector3(1.0, 0, 0) + axis, hi],
			[Vector3(1.0, 0, 0) - axis, hi])
		_tri3(st, [Vector3.ZERO + axis, mid], [Vector3(1.0, 0, 0) - axis, hi],
			[Vector3.ZERO - axis, mid])
	for k in range(8):
		var t0: float = float(k) * TAU / 8.0
		var t1: float = float(k + 1) * TAU / 8.0
		_tri3(st, [Vector3(1.0, 0, 0), hi],
			[Vector3(1.0, cos(t0) * w * 1.7, sin(t0) * w * 1.7), hi],
			[Vector3(1.0, cos(t1) * w * 1.7, sin(t1) * w * 1.7), mid])
	return _commit3(st)


static func _tri3(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _commit3(st: SurfaceTool) -> ArrayMesh:
	var m := ArrayMesh.new()
	st.commit(m)
	return m


## 保活一座炮台(幂等)。key = "side|idx"。每 tick 调 ⇒ 炮台一直站在那儿。
## ★这是"炮台看得见"的事实源: 门禁量它在不在 _world、站没站在炮位上。
func gun_turret_ensure(key: String, pos2d: Vector2, shield_phase: bool = false) -> Node3D:
	if not _has_world():
		return null
	var h = _turrets.get(key, null)
	if h is Dictionary and is_instance_valid((h as Dictionary).get("root", null)):
		var rt0 = (h as Dictionary)["root"]
		rt0.position = battle._world_pos(pos2d, 0.0)
		return rt0
	if _mesh_tur_base == null:
		_mesh_tur_base = _build_turret_base()
	if _mesh_tur_barrel == null:
		_mesh_tur_barrel = _build_turret_barrel()
	var col: Color = COL_GUN_SHIELD if shield_phase else COL_GUN_BARRAGE
	var ws: float = float(battle.WS)
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.0)
	_adopt(root, "gun_turret")
	var base := MeshInstance3D.new()
	base.mesh = _mesh_tur_base
	base.material_override = _turret_mat(Color(col.r * 0.55, col.g * 0.55, col.b * 0.62, 0.95))
	base.scale = Vector3(TURRET_R_PX * ws, TURRET_H_PX * ws, TURRET_R_PX * ws)
	root.add_child(base)
	## 转的是【炮塔】不是底座 —— 真炮台就是这样
	var yawn := Node3D.new()
	yawn.position = Vector3(0.0, TURRET_H_PX * ws, 0.0)
	root.add_child(yawn)
	var barrel := MeshInstance3D.new()
	barrel.mesh = _mesh_tur_barrel
	var mr := _turret_mat(Color(col.r, col.g, col.b, 1.0))
	barrel.material_override = mr
	barrel.scale = Vector3.ONE * (TURRET_BARREL_PX * ws)
	yawn.add_child(barrel)
	_turrets[key] = {"root": root, "yaw": yawn, "barrel": barrel, "mat_r": mr,
		"recoil": 0.0, "pos": pos2d}
	return root


static func _turret_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


## 开火: 炮塔转向目标 + 后坐 + 炮口闪。返回是否真的开了(没这座炮台就 false)。
func gun_turret_fire(key: String, target2d: Vector2, shield_phase: bool = false) -> bool:
	var h = _turrets.get(key, null)
	if not (h is Dictionary):
		return false
	var rt = (h as Dictionary).get("root", null)
	if not is_instance_valid(rt):
		return false
	var yawn = (h as Dictionary).get("yaw", null)
	if is_instance_valid(yawn):
		var here := Vector2(rt.position.x, rt.position.z)
		var to: Vector3 = battle._world_pos(target2d, 0.0)
		var d := Vector2(to.x - here.x, to.z - here.y)
		if d.length() > 1e-5:
			yawn.rotation.y = -atan2(d.y, d.x)
	(h as Dictionary)["recoil"] = 1.0
	var col: Color = COL_GUN_SHIELD if shield_phase else COL_GUN_BARRAGE
	## 炮口闪落在【炮管末端】: 用存下来的场地坐标 + 朝向算, 不做 world→field 逆变换
	## (_world_pos 可能带偏移/缩放, 逆算会把火花甩到别处 —— 上一版就飘到了屏幕左上角)
	var pf: Vector2 = (h as Dictionary).get("pos", Vector2.ZERO)
	var dirf: Vector2 = (target2d - pf)
	if dirf.length() > 1e-5:
		dirf = dirf.normalized()
	else:
		dirf = Vector2.RIGHT
	spark_burst(pf + dirf * (TURRET_BARREL_PX * 1.05), col, TURRET_H_PX * float(battle.WS) * 1.1, 8)
	return true


## 每帧: 后坐恢复 + 炮口亮度回落。由 GunSynergySystem.tick 调。
func gun_turret_tick(delta: float) -> void:
	for key in _turrets.keys():
		var h = _turrets[key]
		if not (h is Dictionary):
			continue
		if not is_instance_valid((h as Dictionary).get("root", null)):
			_turrets.erase(key)
			continue
		var r: float = maxf(0.0, float((h as Dictionary).get("recoil", 0.0)) - delta / TURRET_RECOIL_TAU)
		(h as Dictionary)["recoil"] = r
		var barrel = (h as Dictionary).get("barrel", null)
		if is_instance_valid(barrel):
			barrel.position.x = -TURRET_RECOIL_PX * float(battle.WS) * r
		var mr = (h as Dictionary).get("mat_r", null)
		if mr is StandardMaterial3D:
			var c: Color = COL_GUN_BARRAGE
			(mr as StandardMaterial3D).albedo_color = Color(minf(c.r * (1.0 + 0.6 * r), 1.0),
				minf(c.g * (1.0 + 0.6 * r), 1.0), minf(c.b * (1.0 + 0.6 * r), 1.0), 1.0)


## 撤走一座炮台(掉档/换路/撤场)。返回是否真的撤了。
func gun_turret_free(key: String) -> bool:
	var h = _turrets.get(key, null)
	if not (h is Dictionary):
		return false
	var rt = (h as Dictionary).get("root", null)
	if is_instance_valid(rt):
		rt.queue_free()
	_turrets.erase(key)
	return true


## 场上现有几座炮台(门禁分母)
func gun_turret_count() -> int:
	var n := 0
	for k in _turrets.keys():
		var h = _turrets[k]
		if h is Dictionary and is_instance_valid((h as Dictionary).get("root", null)):
			n += 1
	return n


##   常驻节点还要处理换路撤场 + 一张新炮台素材 ⇒ 本批只做"开火瞬间标出炮位"。
func gun_turret_one(origin2d: Vector2, hits: Array) -> Node3D:
	if not _has_world():
		return null
	var pil := light_pillar(origin2d, COL_GUN_BARRAGE, 2.2, 0.32)
	for p in hits:
		if p is Vector2:
			spark_burst(p as Vector2, COL_GUN_BARRAGE, 0.5, 10)
	return pil


## 枪·第二座炮台的相位(每 5 秒)。shield_phase=true → 蓝色能量辐射给全队; false → 橙色弹幕射向敌方全体。
##
## ★这条唯一要传达的信息就是**相位可辨** —— 现状护盾靠通用金环、弹幕靠伤害数字,
##   "这次是给盾还是打人"完全看不出。⇒ 颜色 + 辐射对象 两条一起分。
func gun_turret_two(origin2d: Vector2, targets: Array, shield_phase: bool) -> int:
	if not _has_world():
		return 0
	var col: Color = COL_GUN_SHIELD if shield_phase else COL_GUN_BARRAGE
	light_pillar(origin2d, col, 2.8, 0.38)
	var n: int = radial_spokes(origin2d, targets, col, 20.0, 0.32)
	for p in targets:
		if not (p is Vector2):
			continue
		if shield_phase:
			ground_ring(p as Vector2, col, 34.0, false, 0.34)
		else:
			spark_burst(p as Vector2, col, 0.5, 12)
	return n


# ── 法器 ─────────────────────────────────────────────────────────────────────

## 法器·共鸣(顶档, 每 7.5 秒: 全队回 15% 最大生命 + 净化 2 种减益)。
## 7.5 秒一次 ⇒ §2.3 判定"可以做重的"。全队【同时】一道蓝紫光柱 + 轻震。
func staff_resonance(positions: Array) -> int:
	if not _has_world():
		return 0
	var n := 0
	for p in positions:
		if not (p is Vector2):
			continue
		if light_pillar(p as Vector2, COL_STAFF, 4.6, 0.62) != null:
			n += 1
	if n > 0:
		battle._shake(0.035)      # 极轻: 远小于 JUICE_SHAKE_HEAVY(0.10)
	return n


## 法器·净化(清掉了 kinds 【种】减益)。★缺的正是"清掉了什么" ⇒ 近白迸发 + 白环, 环随种数变大。
func staff_dispel(pos2d: Vector2, kinds: int) -> Node3D:
	if not _has_world() or kinds <= 0:
		return null
	var k: int = mini(kinds, 3)
	spark_burst(pos2d, COL_STAFF_PURE, 0.8, 8 + 6 * k)
	return ground_ring(pos2d, COL_STAFF_PURE, 26.0 + 9.0 * float(k), false, 0.30)


## 法器·某一件法器的法力条满了、效果被触发的那一瞬。
## ★U3(法力条要不要做可见 UI)用户未拍板 ⇒ 按方案书建议的 **C: 只做"响了"的闪光**, 进度条另议。
func staff_mana_full(pos2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	return light_pillar(pos2d, COL_STAFF, 2.4, 0.30)


# ── 遗物 ─────────────────────────────────────────────────────────────────────

## 遗物·觉醒(本路开打满 20 秒的那一下·一次性·全场级) —— 本批最重的一个。
## 全队同时: 高金柱 + 脚下八边形古纹环(bold, 地形盖不住) + 中等震屏。
func relic_awaken(positions: Array) -> int:
	if not _has_world():
		return 0
	var n := 0
	for p in positions:
		if not (p is Vector2):
			continue
		var v: Vector2 = p as Vector2
		light_pillar(v, COL_RELIC, 5.4, 0.80)
		polygon_ring(v, COL_RELIC, 52.0, SIDES_RELIC, true, 0.60)
		spark_burst(v, COL_RELIC, 0.5, 16)
		n += 1
	if n > 0:
		battle._shake(0.075)
	return n


## 遗物·生死界跨 50% 线。down=true 跌破(加攻→吸血翻倍) / false 回到线上。
## ★这是一个**明确的阈值事件**, 现状毫无提示 —— 玩家看不出自己的行为模式刚刚变了。
func relic_gate(pos2d: Vector2, down: bool) -> Node3D:
	if not _has_world():
		return null
	var col: Color = COL_RELIC_LOW if down else COL_RELIC
	if down:
		spark_burst(pos2d, col, 0.7, 14)
	return polygon_ring(pos2d, col, 44.0, SIDES_RELIC, true, 0.44)


# ⛔ 这里曾经有 `relic_ancient_step()`(远古之力跨 34/67/100% 的八边环) ——
#   **用户 2026-08-07 拍板不做阈值特效，别加回来**(方案书 §5 U4)。
#   连同 `relic_synergy_system.ANCIENT_VFX_STEPS` / `_ancient_step_vfx()` 一起拆净。


# ── 食物 ─────────────────────────────────────────────────────────────────────

## 食物·学院(开场一次性给全队 +100/220 最大生命)。绿环上涨 + 上升火花。
func food_academy(positions: Array) -> int:
	if not _has_world():
		return 0
	var n := 0
	for p in positions:
		if not (p is Vector2):
			continue
		# bold(双层 + 关深度测试): 实拍(shots/food_academy_hit1.png)单层绿环压在青蓝地图上
		# 对比度最低的一条(变亮像素只有噪声底的 5.9 倍, 全表最低)。
		ground_ring(p as Vector2, COL_FOOD, 40.0, true, 0.50)
		spark_burst(p as Vector2, COL_FOOD, 0.35, 14)
		n += 1
	return n


# ⛔ 这里曾经有 `food_growth_step()`(成长跨 100/300/600 的绿环) ——
#   **用户 2026-08-07 拍板不做阈值特效，别加回来**(方案书 §5 U4)。
#   连同 `food_synergy_system.GROW_VFX_STEPS` 与 `_grow()` 里的调用一起拆净。


# ── 药水 ─────────────────────────────────────────────────────────────────────

## 药水·战利品(猎物阵亡 → 全队攻击力永久 +5/8)。
## ★缺的是"这份收益从哪来" ⇒ 从**尸体**向全队每个人辐射一条橙带 + 每人一簇火花。
func potion_harvest(src2d: Vector2, positions: Array) -> int:
	if not _has_world():
		return 0
	var n: int = radial_spokes(src2d, positions, COL_POTION, 18.0, 0.36)
	for p in positions:
		if p is Vector2:
			spark_burst(p as Vector2, COL_POTION, 0.55, 10)
	return n


## 药水·猎物被标记的那一刻(现状只有一次橙色飘字, 2.5 秒后就完全看不出谁是猎物)。
## ⚠ **常驻标记做不到**: 它该是头顶状态徽章, 而 `HEAD_ROW_CAP=4` 已满、超出【静默截断】(U5 未拍板)。
##   ⇒ 本批只把"被选中那一下"做重(准星式双环), 常驻那半条诚实留空。
func potion_prey_mark(pos2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	ground_ring(pos2d, COL_POTION, 30.0, false, 0.55)
	return ground_ring(pos2d, COL_POTION, 52.0, true, 0.55)


# ── 盾 ───────────────────────────────────────────────────────────────────────

## 盾·收殓(敌方阵亡 → 最近的携带盾者得该单位 30% 最大生命的护盾)。
## ★现状只有一个通用金环, **看不出是从那具尸体收来的** ⇒ 尸体 → 受益者的一道灵魂流。
func shield_reap(from2d: Vector2, to2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	spark_burst(to2d, COL_SHIELD_REAP, 0.55, 12)
	# 带宽 20→34: 实拍(shots/shield_reap_hit0.png)那条灵魂流横跨大半个屏幕却只有几像素粗,
	# 在满屏地图纹理上读不出"从这具尸体来的"。
	return energy_band(from2d, to2d, COL_SHIELD_REAP, 34.0, 0.42)


# ── 弓箭 ─────────────────────────────────────────────────────────────────────

## 弓箭·腐蚀叠满 5 层的那一刻(此后它受到的伤害有 10/20/35% 转成真实伤害)。
## ★这是**规则级切换**, 现状零显示。三角环 = 弓箭的母题(尖锐啃噬)。
func bow_corrode_full(pos2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	spark_burst(pos2d, COL_BOW, 0.5, 10)
	return polygon_ring(pos2d, COL_BOW, 42.0, SIDES_BOW, true, 0.46)


# ── 奇械 ─────────────────────────────────────────────────────────────────────

## 奇械·冰封命中(全队攻击 15/25/40% 概率冻结 1.5 秒)。
## ★频率安全: 同目标 2.5 秒 CD + 解冻后 1.5 秒免疫两道闸 ⇒ 全场 ≤1.5 次/秒, §2.3 判定"可以做重的"。
## ⚠ 现状只有 `_freeze` 的通用冰蓝小环(半径 48) —— 那是**所有冻结来源共用**的,
##   读不出"这是奇械羁绊冻的"。六边霜环是奇械专属母题。
func gadget_freeze(pos2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	spark_burst(pos2d, COL_GADGET, 0.6, 12)
	return polygon_ring(pos2d, COL_GADGET, 40.0, SIDES_GADGET, true, 0.44)


# ⛔ 这里曾经有 `gadget_stiff_step()`(僵硬跨 5/10/20 层的六边环) ——
#   **用户 2026-08-07 拍板不做阈值特效，别加回来**(方案书 §5 U4)。
#   连同 `gadget_synergy_system.STIFF_VFX_STEPS` 与 `add_stiff()` 里的调用一起拆净。


# ============================================================================
#  §"只放一次" —— 纯函数, 不烘任何数字
# ============================================================================

# ⛔ 这里曾经还有一个 `tier_of(value, thresholds)`(算跨过几个阈值)。
#   三个阈值提示拆掉后它【只剩测试在调】—— 零业务调用者的死代码被"断言函数存在"型
#   门禁保护着，正是 memory [[fb-verify-must-run-the-real-path]] 那个坑 ⇒ 一并删。
#   下面的 `tier_advance` 【不能删】: 弓箭腐蚀满 5 层(bow_synergy_system.gd:130)还在用它当
#   "这一轮放过了没"的闸，那不是阈值提示、是单次事件去重。


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


# ============================================================================
#  §批 B3 【本轮没做到的】—— 写下来免得下一个人当成"已经好了"
#
#  1. **常驻显示一条都没做**(腐蚀层数 / 僵硬层数 / 猎物标记 / 火控准星 / 法力条进度)。
#     根因是同一个: 它们该走**头顶徽章**, 而 `HEAD_ROW_CAP = 4`(RB:5838) 已被
#     electric/ink/cyber_ai/crystal 占满, 超出的会被 `mini(items.size(), CAP)` **静默截断**
#     —— 加了也看不见, 而且不报错(方案书 R6 / 未决点 U5, 用户尚未拍板)。
#     ⇒ 本批一律只做"事件那一瞬", 持续态诚实留空。
#  2. **剑(剑士追打 / 血祭)一条都没做。** 追打是全表最高频的(6 只带剑 ≈ 10 次/秒),
#     方案书 §2.3 判定"只能做极轻的";血祭是连续量(损失百分比 → 攻击力), 只能做常驻红光。
#     两条都不是"有明确触发瞬间"的形状, 与本批的取舍口径不符 ⇒ 留给下一批。
#  3. **逻辑实体的本体仍然不可见**(三座炮台 / 亡魂立绘)。U6「画不画本体」未拍板,
#     且画本体要处理常驻节点的换路撤场 + 一张新炮台素材。本批只在【开火那一瞬】
#     用一根矮光柱标出炮位 —— 玩家能读到"那儿有个东西在打", 但读不到"有三座"。
#  4. **枪·第二座弹幕相位的伤害数字仍是浅蓝 `#9bdcff`**(`gun_synergy_system._turret_two`),
#     而我把弹幕相位的演出画成了**深橙**(为了和护盾相位分开)。数字与演出不同色。
#     没顺手改是因为它属于既有数值/文案侧, 本批是演出批(方案书 R14)。**这是一条已知的不一致。**
#  5. **食物那条对比度最低**: 翠绿环压在青蓝色海底地图上, 实拍变亮像素只有噪声底的 4.8 倍
#     (全表最低; 最高的枪·弹幕是 2240 倍)。已改成 bold 双层缓解, 但仍是最弱的一条。
# ============================================================================


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
