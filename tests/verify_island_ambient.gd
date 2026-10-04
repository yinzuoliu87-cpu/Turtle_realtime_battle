extends Node
## verify_island_ambient.gd — 主题的氛围粒子: 删掉满场上飘的气泡, 只留**有因**的灯旁火星; base 一个值不动
##
## ★由来: 方案书 §4.4「四版的氛围粒子(base 那层还是向上飘的气泡)」+ §4.5-2
##   「动态只有静态参考 ⇒ 本轮不凭空造新动态, 只删明显错的(向上飘的气泡、从水面打下来的光柱)」。
##   2026-10-04 实拍(暗林·真对局): 满场一圈圈黄色气泡环 + 冰蓝辉光往上飘 —— 两层都是水下的东西。
## ★判据量产品真的建出来的粒子节点(调试场 + 真对局那条 `_build_map_props` 都跑):
##   ① 主题里**没有满场撒的发射器**(发射盒边长 > 2 米 = 覆盖战场的那种)
##   ② 每个发射器都**坐在一盏灯的火上**: 独立把发射点反投回宿主灯具贴图, 那一格必须是亮暖色的火
##   ③ 火星升不过半米(寿命 × 最大初速 + ½·重力·寿命² ≤ 0.6 米), 不会读成「往上飘的气泡」
##   ④ base: 气泡与冰蓝辉光两层都还在, 四个运动参数逐值不变(默认画面绝不能变)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const FIELD_BOX := 2.0
const RISE_MAX := 0.6

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 主题氛围粒子 ===")
	var keep: String = AT.active
	RB.DEBUG_EDIT = true

	## ── base: 两层都在, 参数逐值不变 ──
	AT.active = AT.V0_BASE
	var sb = RB.new()
	add_child(sb)
	await get_tree().process_frame
	await get_tree().process_frame
	sb._world_builder._build_map_props()
	var bp: Array = _particles(sb._world)
	var bubbles: Array = bp.filter(func(p): return p is CPUParticles3D)
	var glows: Array = bp.filter(func(p): return p is GPUParticles3D)
	_ok("[base] ★分母: 气泡层(CPUParticles3D)在", bubbles.size() == 1, "%d" % bubbles.size())
	_ok("[base] ★分母: 冰蓝辉光层(GPUParticles3D)在", glows.size() == 1, "%d" % glows.size())
	if bubbles.size() == 1:
		var b: CPUParticles3D = bubbles[0]
		var same: bool = b.direction == Vector3(0, 1, 0) and b.gravity == Vector3(0, 0.28, 0) \
			and is_equal_approx(b.initial_velocity_min, 0.2) and is_equal_approx(b.initial_velocity_max, 0.55) \
			and (b.material_override as StandardMaterial3D).albedo_color == Color(1, 1, 1, 0.55)
		_ok("[base] ★★气泡的方向/重力/初速/颜色逐值不变(默认画面绝不能变)", same,
			"dir %s g %s v %.2f~%.2f" % [b.direction, b.gravity, b.initial_velocity_min, b.initial_velocity_max])
	sb.queue_free()
	await get_tree().process_frame

	_ok("★分母: 至少有一版标成「已画出来」", AT.DRAWN.size() >= 1, str(AT.DRAWN))
	for th in AT.DRAWN:
		AT.active = str(th)
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		s._world_builder._build_map_props()
		await get_tree().process_frame
		var ps: Array = _particles(s._world)
		_ok("[%s] ★分母: 有氛围粒子(灯旁火星) ≥ 10 处" % th, ps.size() >= 10, "%d 处" % ps.size())
		var field: Array = []
		var off: Array = []
		var high: Array = []
		for p in ps:
			if p is GPUParticles3D:
				field.append("GPU 辉光层")
				continue
			var e: CPUParticles3D = p
			if e.emission_shape == CPUParticles3D.EMISSION_SHAPE_BOX and \
					(e.emission_box_extents.x > FIELD_BOX or e.emission_box_extents.z > FIELD_BOX):
				field.append("盒 %s" % e.emission_box_extents)
			var f = e.get_meta("flame", null)
			if f == null or not is_instance_valid(f) or not (f is Sprite3D):
				off.append("无火源")
				continue
			var px: Vector2 = _world_px(s, f, e.global_position)
			var im: Image = (f as Sprite3D).texture.get_image()
			if im.is_compressed():
				im.decompress()
			## 3×3 邻域里有亮暖色像素即算坐在火上(重心可能落在两颗火苗像素之间)
			## ★2026-10-04 主题给了自己的光源色域(flame_rgb, 深礁是冷绿藻灯)就按它判, 两侧各放宽 0.05;
			##   不给 ⇒ 原暖色判据(r>0.8 且 b<0.5)逐字不变。
			var fr: Dictionary = AT.cfg_of(str(th)).get("flame_rgb", {})
			var hit := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var ix: int = int(floor(px.x)) + dx
					var iy: int = int(floor(px.y)) + dy
					if ix >= 0 and iy >= 0 and ix < im.get_width() and iy < im.get_height():
						var c: Color = im.get_pixel(ix, iy)
						if fr.is_empty():
							if c.a > 0.5 and c.r > 0.8 and c.b < 0.5:
								hit = true
						elif c.a > 0.5 and _in(c.r, fr["r"]) and _in(c.g, fr["g"]) and _in(c.b, fr["b"]):
							hit = true
			if not hit:
				off.append("%s 像素(%.1f,%.1f)不是火" % [(f as Sprite3D).texture.resource_path.get_file(), px.x, px.y])
			var rise: float = e.lifetime * e.initial_velocity_max + 0.5 * maxf(0.0, e.gravity.y) * e.lifetime * e.lifetime
			if rise > RISE_MAX:
				high.append("升 %.2f 米" % rise)
		_ok("[%s] ★★没有满场撒的发射器(满场上飘 = 水下气泡)" % th, field.is_empty(), str(field))
		_ok("[%s] ★★每处火星都坐在一盏灯的火上(反投回灯具贴图验)" % th, off.is_empty() and not ps.is_empty(), str(off))
		_ok("[%s] ★★火星升不过 %.1f 米(不读成往上飘的气泡)" % [th, RISE_MAX], high.is_empty(), str(high))
		s.queue_free()
		await get_tree().process_frame
	AT.active = keep
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 主题氛围粒子" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 色域判断(放宽 0.05): v 落在 (lo-0.05, hi+0.05) 里
func _in(v: float, rng: Array) -> bool:
	return v > float(rng[0]) - 0.05 and v < float(rng[1]) + 0.05


## 世界点 → 公告板精灵贴图像素(独立实现, 不调产品的换算)
func _world_px(s, sp: Sprite3D, w: Vector3) -> Vector2:
	var b: Basis = s._cam.global_transform.basis
	var d: Vector3 = w - sp.global_position
	var lx: float = d.dot(b.x) / (sp.pixel_size * sp.scale.x)
	var ly: float = d.dot(b.y) / (sp.pixel_size * sp.scale.y)
	return Vector2(lx - sp.offset.x + float(sp.texture.get_width()) * 0.5,
		sp.offset.y + float(sp.texture.get_height()) * 0.5 - ly)


func _particles(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is CPUParticles3D or c is GPUParticles3D:
			out.append(c)
		out.append_array(_particles(c))
	return out
