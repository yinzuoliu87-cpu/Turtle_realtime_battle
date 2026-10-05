extends Node
## verify_cam_extent.gd — 镜头能到的每一个极限机位, 画面里都不许有「什么都没有」的地方。
##
## ★由来(用户 2026-10-05):「地图的话我们镜头是可以移动缩放的啊，有一堆问题啊，这一个晚上你必须优化完」
##   四张图只在默认机位验收过。实拍(`tests/_probe_cam_extent`, 对照表 docs/plans/img-20261005-镜头地图/)
##   照出来的病几乎都是一个形状: **岛外的海只铺到地图格子的椭圆边, 再往外是近黑的虚空**,
##   而平移上限是与缩放无关的 ±9 米方框 ⇒ 拉远 / 平移就是一座岛飘在一大片纯黑里。
##
## ★为什么是几何判据不是截图: 门禁跑 --headless, 不渲染。所以量的是**真建出来的对象**
##   (外海 MeshInstance3D 的包围盒、格子地图每一格的类型、海材质上真实设置的颜色参数),
##   光线用**真相机**的变换与 fov, 镜头位置走**产品自己的入口**(`_apply_cam_zoom` / `_cam_pan_by` 拖到极限,
##   让夹紧自己决定落在哪) —— 不在测试里另抄一份公式。
##
## 判据:
##   ① 四张图 × 四个画幅 × 27 个极限机位(默认/最近/最远 + 三档缩放 × 8 个平移极限),
##      每个机位从视口四条边(各 41 点) + 内部 16×9 网格打光线到地面:
##      落点必须被「有颜色的东西」盖住 —— 外海(包围盒内且海色不是近黑) / 格子地图里的非 void 格。
##      ★分母: 每张图采样光线总数 > 0, 且外海节点存在。
##   ② 海色不是近黑: 外海与格子海用的 deep 色 × 着色压暗(body_dim) 在 sRGB 下最大通道 ≥ SEA_MIN;
##      格子海在板子外沿再乘 edge_floor 也 ≥ SEA_MIN(否则板沿一圈仍是黑的)。
##   ③ 平移夹紧随缩放: 拉远/默认时拖到天涯, 平移量 ≤ 下限(只给一点手感); 拉近时仍能推出去 ≥ 4 米(没把平移锁死)。
##   ④ 前景剪影带横向盖满画面: 各画幅(最宽 2.4:1)在带子那个深度的可见宽度 ≤ 带子(含两侧镜像补片)的总宽。
##   ⑤ base(调试场默认)不受影响: 没有外海节点; 格子海的 edge_floor / crest_deep / wave_style 仍是 shader 原默认值。
##
## 反向验证(2026-10-05 做过, 见方案书 docs/plans/20261003-四版完整地图.md §7):
##   外海尺寸退回格子大小 ⇒ ① 红; 海色退回原近黑值 ⇒ ② 红; 平移夹紧退回固定 ±9 ⇒ ③ 红; 去掉镜像补片 ⇒ ④ 红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const AO := preload("res://scripts/scenes/battle/arena_outer.gd")

## sRGB 最大通道下限(0..1)。原来四版的海: 暗林 0.010 / 深礁 0.013 / 紫墟 0.004 / 赤林 0.043 —— 实拍全是纯黑一片。
## 现在: 暗林 0.064 / 深礁 0.117 / 紫墟 0.19 / 赤林 0.21, 实拍读得出是暗色水面。0.05 卡在两组之间。
const SEA_MIN := 0.05
const ASPECTS := [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2400, 1000)]

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "   ", d)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 镜头极限机位: 画面里没有虚空 ===")
	var keep: String = AT.active
	var keep_forced: String = AT.forced
	AT.forced = ""
	RB.DEBUG_EDIT = true
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/arena.json"))
	_ok("★分母: 地图 json 读得到", meta != null and meta.has("grid"))

	## ── ⑤ base: 不建外海, 海 shader 参数全是原默认 ──
	AT.active = AT.V0_BASE
	var sb = RB.new()
	add_child(sb)
	await get_tree().process_frame
	await get_tree().process_frame
	sb._world_builder._build_map_props()
	_ok("⑤[base] 没有外海节点(默认画面一个像素不动)", sb._world.find_child("OuterSea", true, false) == null)
	var bw: ShaderMaterial = _grid_water_mat(sb)
	_ok("⑤[base] ★分母: 找得到格子海材质", bw != null)
	if bw != null:
		_ok("⑤[base] 格子海 edge_floor / crest_deep / wave_style 没被设置(= shader 原默认 0.18 / 0.25 / 0)",
			bw.get_shader_parameter("edge_floor") == null and bw.get_shader_parameter("crest_deep") == null and bw.get_shader_parameter("wave_style") == null,
			"%s / %s / %s" % [bw.get_shader_parameter("edge_floor"), bw.get_shader_parameter("crest_deep"), bw.get_shader_parameter("wave_style")])
	sb.queue_free()
	await get_tree().process_frame

	var n_themes := 0
	for th in AT.MATCH_POOL:
		AT.active = str(th)
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		s._world_builder._build_map_props()          # ★真对局(双路)调的同一个函数
		await get_tree().process_frame
		n_themes += 1
		print("--- [%s] ---" % th)
		var sea: MeshInstance3D = s._world.find_child("OuterSea", true, false)
		_ok("[%s] ★分母: 外海节点存在" % th, sea != null and sea.mesh != null)
		if sea == null or sea.mesh == null:
			s.queue_free()
			await get_tree().process_frame
			continue
		## ── ② 海色 ──
		var sm: ShaderMaterial = sea.material_override
		var gm: ShaderMaterial = _grid_water_mat(s)
		_ok("[%s] ★分母: 找得到格子海材质" % th, gm != null)
		var e_sea: float = _sea_lum(sm)
		_ok("[%s] ② 外海是暗色水面不是近黑(sRGB 最大通道 ≥ %.2f)" % [th, SEA_MIN], e_sea >= SEA_MIN, "%.3f" % e_sea)
		_ok("[%s] ② 外海材质是「恒深水」模式(与格子海同一条颜色公式)" % th, sm.get_shader_parameter("outer_mode") == true)
		if gm != null:
			var ef = gm.get_shader_parameter("edge_floor")
			var e_edge: float = _sea_lum(gm, float(ef) if ef != null else 0.18)
			_ok("[%s] ② 格子海在板子外沿(× edge_floor)也不是近黑" % th, e_edge >= SEA_MIN, "%.3f (edge_floor=%s)" % [e_edge, ef])
		var sea_ok: bool = e_sea >= SEA_MIN
		var ab: AABB = sea.global_transform * sea.mesh.get_aabb()
		## ── ① 光线覆盖 ──
		var tot := 0
		var bad := 0
		var worst := ""
		for asp in ASPECTS:
			_set_view(s, asp)
			var vs: Vector2 = s._cam.get_viewport().get_visible_rect().size
			## ★比的是**画幅比**: 项目拉伸模式会把视口换算成「高 720 / 宽按比例扩」的内容尺寸(实测 1024×768 → 1280×960)。
			var want: float = float(asp.x) / float(asp.y)
			if absf(vs.x / vs.y - want) > 0.01:
				_ok("[%s] ★分母: 视口画幅设得进去 %s" % [th, asp], false, "实际 %s" % vs)
				continue
			for cfgc in _cam_configs(s):
				_set_cam(s, cfgc[1], cfgc[2])
				var res: Array = _rays(s, ab, sea_ok, meta, vs.x / vs.y)
				tot += int(res[0])
				if int(res[1]) > 0:
					bad += int(res[1])
					if worst == "":
						worst = "%s %s 落空 %d/%d 例 %s" % [asp, cfgc[0], res[1], res[0], res[2]]
		_ok("[%s] ★分母: 采样光线 > 0" % th, tot > 0, "%d 条" % tot)
		_ok("[%s] ① ★★所有极限机位 × 4 个画幅, 画面里每条采样光线都落在有东西的地方" % th, bad == 0,
			"落空 %d/%d %s" % [bad, tot, worst])
		## ── ③ 平移夹紧 ──
		_set_view(s, Vector2i(1560, 720))
		for zz in [[RB.CAM_ZOOM_MIN, "最远"], [1.0, "默认"]]:
			_set_cam(s, zz[0], Vector2(1, 1))
			var p: Vector3 = s._cam_pan
			_ok("[%s] ③ %s缩放下拖到天涯, 平移只给一点手感(≤ %s 米)" % [th, zz[1], AO.PAN_MIN],
				absf(p.x) <= AO.PAN_MIN.x + 0.001 and absf(p.z) <= AO.PAN_MIN.y + 0.001, "pan=%s" % p)
		_set_cam(s, RB.CAM_ZOOM_MAX, Vector2(1, 0))
		_ok("[%s] ③ 拉到最近仍能横向推出去 ≥ 4 米(没把平移锁死)" % th, absf(s._cam_pan.x) >= 4.0, "pan=%s" % s._cam_pan)
		## ── ④ 前景带横向盖满 ──
		var bands: Array = []
		for ch in s._cam.get_children():
			if ch is Sprite3D and ch.has_meta("fg_band"):
				bands.append(ch)
		_ok("[%s] ④ ★分母: 前景带节点存在" % th, bands.size() >= 1, "%d 张" % bands.size())
		var lo := 1e9
		var hi := -1e9
		var bz := -2.35
		for q in bands:
			var hw_q: float = float((q as Sprite3D).texture.get_width()) * (q as Sprite3D).pixel_size * 0.5
			lo = minf(lo, q.position.x - hw_q)
			hi = maxf(hi, q.position.x + hw_q)
			bz = q.position.z
		var need: float = absf(bz) * tan(deg_to_rad(s._cam.fov) * 0.5) * 2.4
		_ok("[%s] ④ 前景带在 2.4:1 画幅下横向盖满(需要 ±%.2f)" % [th, need], lo <= -need and hi >= need, "带子 x∈[%.2f, %.2f]" % [lo, hi])
		s.queue_free()
		await get_tree().process_frame
	_ok("★分母: 四张图都量到了", n_themes == AT.MATCH_POOL.size(), "%d" % n_themes)
	AT.active = keep
	AT.forced = keep_forced
	RB.DEBUG_EDIT = false
	print("ALL PASS — 镜头极限机位无虚空" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 画幅: 相机所在视口(真对局 = SubViewport, 无头单测里相机可能直接挂在根窗口上)与根窗口都设成这个尺寸。
func _set_view(s, asp: Vector2i) -> void:
	get_tree().root.size = asp
	if s._sub != null and is_instance_valid(s._sub):
		s._sub.size = asp


func _grid_water_mat(s) -> ShaderMaterial:
	for n in s._world.find_children("*", "MultiMeshInstance3D", true, false):
		var m = n.material_override
		if m is ShaderMaterial and m.shader != null and str(m.shader.resource_path).ends_with("ground_water.gdshader"):
			return m
	return null


## 海水在深水处的着色结果(与 ground_water.gdshader 同式: deep_col 线性化 × body_dim), 返回 sRGB 最大通道。
func _sea_lum(m: ShaderMaterial, extra: float = 1.0) -> float:
	var dc = m.get_shader_parameter("deep_col")
	var bd = m.get_shader_parameter("body_dim")
	var body: float = (float(bd) if bd != null else 0.62) * extra
	if dc == null:
		return 0.0
	var lin: Color = (dc as Color).srgb_to_linear()
	var c := Color(lin.r * body, lin.g * body, lin.b * body).linear_to_srgb()
	return maxf(c.r, maxf(c.g, c.b))


## [名字, 缩放, 平移方向]。方向 = 拖到那个方向的极限(屏幕 x 右 / y 下), 夹紧由产品决定。
func _cam_configs(_s) -> Array:
	var r: Array = [["默认", 1.0, Vector2.ZERO], ["最近", RB.CAM_ZOOM_MAX, Vector2.ZERO], ["最远", RB.CAM_ZOOM_MIN, Vector2.ZERO]]
	for zn in [["最远", RB.CAM_ZOOM_MIN], ["默认", 1.0], ["最近", RB.CAM_ZOOM_MAX]]:
		for k in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			r.append(["%s 平移%s" % [zn[0], k], zn[1], k])
	return r


## 走产品入口: 设缩放 → `_apply_cam_zoom`(含夹紧) → 往那个方向猛拖(`_cam_pan_by`, 含夹紧)。
func _set_cam(s, zoom: float, dir: Vector2) -> void:
	s._shake_amp = 0.0
	s._cam_zoom = zoom
	s._cam_pan = Vector3.ZERO
	s._apply_cam_zoom()
	if dir != Vector2.ZERO:
		for _k in range(40):
			s._cam_pan_by(-dir.x * 80.0, -dir.y * 80.0)
	s._cam.position = s._cam_zoom_base


## 返回 [光线数, 落空数, 第一条落空的描述]。
func _rays(s, sea_ab: AABB, sea_ok: bool, meta: Dictionary, aspect: float) -> Array:
	var xf: Transform3D = s._cam.global_transform
	var t: float = tan(deg_to_rad(s._cam.fov) * 0.5)
	var pts: Array = []
	for i in range(41):
		var u: float = -0.995 + 1.99 * float(i) / 40.0
		pts.append(Vector2(u, 0.995))
		pts.append(Vector2(u, -0.995))
		pts.append(Vector2(0.995, u))
		pts.append(Vector2(-0.995, u))
	for gy in range(9):
		for gx in range(16):
			pts.append(Vector2(-0.95 + 1.9 * gx / 15.0, -0.95 + 1.9 * gy / 8.0))
	var n := 0
	var bad := 0
	var first := ""
	for p in pts:
		n += 1
		var d: Vector3 = (xf.basis * Vector3(p.x * t * aspect, p.y * t, -1.0)).normalized()
		if d.y >= -0.0001:
			bad += 1
			if first == "": first = "ndc%s 打到天上" % p
			continue
		var hit: Vector3 = xf.origin + d * (-(xf.origin.y) / d.y)
		if _covered(s, hit, sea_ab, sea_ok, meta):
			continue
		bad += 1
		if first == "":
			first = "ndc%s → 地面(%.1f, %.1f)" % [p, hit.x, hit.z]
	return [n, bad, first]


func _covered(s, hit: Vector3, sea_ab: AABB, sea_ok: bool, meta: Dictionary) -> bool:
	if sea_ok and hit.x >= sea_ab.position.x and hit.x <= sea_ab.end.x and hit.z >= sea_ab.position.z and hit.z <= sea_ab.end.z:
		return true
	## 格子地图: 世界 → 像素口径 → 格
	var px: float = hit.x / RB.WS + s._arena_center.x
	var py: float = hit.z / RB.WS + s._arena_center.y
	var tile: float = float(meta["tile"])
	var c: int = int(floor((px - float(meta["origin_x"])) / tile))
	var r: int = int(floor((py - float(meta["origin_y"])) / tile))
	var grid: Array = meta["grid"]
	if r < 0 or r >= grid.size() or c < 0 or c >= (grid[r] as Array).size():
		return false
	var v: int = int(grid[r][c])
	if v == 4:
		return false
	if v == 1:
		return sea_ok
	return true
