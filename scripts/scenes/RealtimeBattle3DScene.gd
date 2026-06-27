extends Node3D
## RealtimeBattle3DScene — 2.5D 战斗骨架验证 (Phase 1, 见 docs/design/2.5D战斗架构方案.md §四.1)
## 纯验证画面观感: 3D空间 + 2D立绘 billboard + 真高度击飞抛物 + blob影随高缩放.
## ⚠ 不接战斗逻辑, 全程序化在 _ready 搭场景; 占位美术(现成avatars + 占位地面).
## 验证点: "真3D击飞抛物 + blob影跟XZ不跟Y" 的观感对不对.

const AVATAR_DIR := "res://assets/sprites/avatars/"
const UNIT_IDS := ["basic", "stone", "ninja", "lava"]   # 现成立绘, glob 找
const UNIT_XZ := [                                       # 各龟在地面 XZ 落点 (米)
	Vector3(-4.5, 0.0, -1.8),
	Vector3(-1.5, 0.0,  1.6),
	Vector3( 1.8, 0.0, -1.8),
	Vector3( 4.5, 0.0,  1.6),
]
const PIXEL_SIZE := 0.012                 # 立绘 像素→米; 龟约 1.5~2 米高
const GROUND_LIFT := 0.35                 # 立绘落地基线略抬 → billboard 竖面下缘不插进地面被遮(俯角下硬切线)
const SHADOW_BASE := Vector3(1.9, 1.0, 1.0)  # blob 影底面尺度 (X宽 Z窄=椭圆压扁朝镜头)
const SHADOW_BASE_A := 0.6                # blob 影底透明度
const GRAVITY := -20.0                    # 击飞重力 (m/s^2)
const LAUNCH_VY := 7.5                    # 击飞竖直初速
const LAUNCH_INTERVAL := 2.5              # 每隔 N 秒挑一个龟击飞

var _units: Array = []                    # 每元素 {sprite, shadow, base_xz, vy, vx, vz, airborne, hp_label}
var _launch_t := 0.0
var _next_launch := 0
var _cam: Camera3D
var _hp_layer: CanvasLayer
var _world: Node3D                        # 3D 内容挂载点 (SubViewport 内, 防 GL Compat 主窗口截图丢3D)

func _ready() -> void:
	_build_viewport()       # SubViewport: 3D 渲进它再贴满屏 → 截图含3D + 正确合成 2D UI 在上
	_build_camera()
	_build_environment()
	_build_ground()
	_build_units()
	_build_hp_overlay()
	# DEV 截图 (SELFSHOT=<秒>): 绕过 ShotDiff 直接从主视口存盘. GL Compat 下主窗口 get_image()
	#   不含直接渲染的 3D, 但本场景 3D 走 SubViewportContainer(2D元素) → 主视口可正常截到. 无副作用.
	if OS.has_environment("SELFSHOT"):
		_self_screenshot()

# --- SubViewport: 3D 世界渲染到它, 再用 SubViewportContainer 贴满主屏 ---
# 为何: GL Compatibility 渲染器下, 主 Window 视口的 get_texture().get_image() 不含 3D
#   (rinfo 证实 3D 真在画, 只是主窗口截图丢3D) → 用 SubViewport 截图可靠含3D, 且这是
#   2.5D 把 2D UI(血条) 干净叠在 3D 之上的标准合成架构. SubViewport 满屏 1:1 → unproject 坐标直接可用.
func _build_viewport() -> void:
	var vp_size := Vector2i(1280, 720)
	if get_viewport() != null:
		var s := get_viewport().get_visible_rect().size
		if s.x > 1 and s.y > 1:
			vp_size = Vector2i(s)
	var container := SubViewportContainer.new()
	container.name = "ViewportContainer"
	container.stretch = true                       # 子 SubViewport 拉伸填满容器
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 用 CanvasLayer 兜底确保贴在持久背景(layer -100)之上、HP overlay 之下
	var bg_layer := CanvasLayer.new()
	bg_layer.name = "WorldLayer"
	bg_layer.layer = 0
	add_child(bg_layer)
	bg_layer.add_child(container)
	var sub := SubViewport.new()
	sub.name = "World3D"
	sub.size = vp_size
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.handle_input_locally = false
	sub.msaa_3d = Viewport.MSAA_2X                  # 抗锯齿, billboard 边缘干净
	container.add_child(sub)
	_world = Node3D.new()
	_world.name = "World"
	sub.add_child(_world)

# --- 相机: 固定 3/4 俯角 (~50° 看下来), 透视 ---
func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 55.0
	# 场地上方偏后, 俯视下来. pos(0,11,13) 看 (0,0.8,0) → 俯角 ≈ atan(11/13)≈40°,
	# 配 fov55 把 x∈[-4.5,4.5]·z∈[-1.8,1.6] 4 龟+击飞弧线全收进 1280x720 画面.
	_cam.position = Vector3(0.0, 11.0, 13.0)
	_world.add_child(_cam)
	# look_at 需节点已入树 → 先 add_child 再调 (否则报 "Node not inside tree")
	_cam.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)   # 看向场地中心略抬, 把龟放画面中部

# --- 光: 柔和方向光从上打下 + 环境补光 ---
func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)   # 从上偏侧打下, 给立体感
	light.light_energy = 1.05
	light.light_color = Color(1.0, 0.97, 0.9)
	_world.add_child(light)

	# 世界环境: 深海氛围 + 环境光抬暗部 (否则 billboard 背光太黑)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.09, 0.14)        # 深海背景
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.6, 0.7)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.12, 0.18)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

# --- 地面: PlaneMesh 24×14 米, 深海色占位材质 ---
func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 14.0)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.22, 0.26)            # 深蓝绿 占位
	mat.roughness = 0.9
	mat.metallic = 0.0
	mi.material_override = mat
	_world.add_child(mi)

# --- 单位: Sprite3D billboard 立绘 + blob 暗影 ---
func _build_units() -> void:
	for i in range(UNIT_IDS.size()):
		var id: String = UNIT_IDS[i]
		var base_xz: Vector3 = UNIT_XZ[i]
		var tex: Texture2D = load(AVATAR_DIR + id + ".png")
		# 立绘 billboard sprite
		var spr := Sprite3D.new()
		spr.name = "Unit_" + id
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED        # 永远朝相机
		spr.pixel_size = PIXEL_SIZE
		spr.shaded = false                                       # 立绘不吃光照, 保持清晰
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD           # 防透明排序闪烁
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# 锚点: 脚底贴地 → 贴图底边对齐节点原点 (offset 把图整体上抬半个高度); 节点再抬 GROUND_LIFT
		if tex != null:
			spr.offset = Vector2(0.0, tex.get_height() * 0.5)
		spr.position = Vector3(base_xz.x, GROUND_LIFT, base_xz.z)
		_world.add_child(spr)

		# blob 暗影: 程序生成 radial 渐变贴图 → Sprite3D 躺平贴地
		var shadow := Sprite3D.new()
		shadow.name = "Shadow_" + id
		shadow.texture = _make_blob_texture()
		shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		shadow.axis = Vector3.AXIS_Y                             # 绕 Y 躺平 → 面朝上贴地
		shadow.pixel_size = 0.01
		shadow.shaded = false
		shadow.transparent = true
		shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED       # 影要软边不能 discard
		shadow.modulate = Color(1, 1, 1, SHADOW_BASE_A)
		shadow.scale = SHADOW_BASE
		shadow.position = Vector3(base_xz.x, 0.02, base_xz.z)    # 贴地略抬防 z-fight
		_world.add_child(shadow)

		_units.append({
			"id": id, "sprite": spr, "shadow": shadow, "base_xz": base_xz,
			"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
			"hp_label": null,
		})

# --- 程序生成 blob 影贴图: radial 渐变 中心黑→边缘透明 ---
func _make_blob_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.55))      # 中心 (offset 0)
	grad.set_color(1, Color(0, 0, 0, 0.0))        # 边缘透明 (offset 1)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	return gt

# --- HP 条 overlay: CanvasLayer + unproject_position 定位 (验证 overlay 投影) ---
func _build_hp_overlay() -> void:
	_hp_layer = CanvasLayer.new()
	_hp_layer.name = "HPOverlay"
	add_child(_hp_layer)
	for u in _units:
		var bar := _make_hp_bar()
		_hp_layer.add_child(bar)
		u["hp_label"] = bar

func _make_hp_bar() -> Control:
	# 简单血条: 背景(暗) + 前景(绿), 居中锚到单位头顶
	var root := Control.new()
	root.custom_minimum_size = Vector2(60, 8)
	root.size = Vector2(60, 8)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(60, 8)
	bg.position = Vector2(0, 0)
	root.add_child(bg)
	var fg := ColorRect.new()
	fg.color = Color(0.2, 0.85, 0.35, 0.95)
	fg.size = Vector2(56, 4)
	fg.position = Vector2(2, 2)
	root.add_child(fg)
	return root

## DEBUG 自截图: 等若干帧让击飞演示跑起来 + frame_post_draw 保证 3D 入帧缓冲再存盘.
func _self_screenshot() -> void:
	var delay := 3.0
	var s := OS.get_environment("SELFSHOT")
	if s.is_valid_float() and s.to_float() > 0.1:
		delay = s.to_float()
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := "res://_25d_self.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
	img.save_png(out)
	get_tree().quit()

func _process(delta: float) -> void:
	_step_launch_scheduler(delta)
	_step_physics(delta)
	_update_overlay()

# 每隔 LAUNCH_INTERVAL 秒挑下一个龟击飞 (轮询循环, 让截图抓到空中)
func _step_launch_scheduler(delta: float) -> void:
	if _units.is_empty():
		return
	_launch_t += delta
	if _launch_t >= LAUNCH_INTERVAL:
		_launch_t = 0.0
		var u: Dictionary = _units[_next_launch % _units.size()]
		_next_launch += 1
		if not u["airborne"]:
			_launch(u)

func _launch(u: Dictionary) -> void:
	u["airborne"] = true
	u["vy"] = LAUNCH_VY
	# 横向击飞: 随机方向滑出去一段 (真"飞出去再砸地")
	var ang := randf() * TAU
	u["vx"] = cos(ang) * 3.0
	u["vz"] = sin(ang) * 3.0

func _step_physics(delta: float) -> void:
	for u in _units:
		if not u["airborne"]:
			continue
		# 真抛物: vy 受重力, height 积分; 横向同时滑
		u["vy"] += GRAVITY * delta
		u["height"] += u["vy"] * delta
		var spr: Sprite3D = u["sprite"]
		var shadow: Sprite3D = u["shadow"]
		var nx: float = spr.position.x + u["vx"] * delta
		var nz: float = spr.position.z + u["vz"] * delta
		if u["height"] <= 0.0:
			# 砸回地面
			u["height"] = 0.0
			u["vy"] = 0.0
			u["vx"] = 0.0
			u["vz"] = 0.0
			u["airborne"] = false
		# 立绘: XZ + Y(高度+落地基线抬升); 影: 跟 XZ 不跟 Y (关键!)
		spr.position = Vector3(nx, u["height"] + GROUND_LIFT, nz)
		shadow.position = Vector3(nx, 0.02, nz)
		# blob 影随高度缩放变淡: y 越高 影越小越淡
		var s: float = 1.0 - clampf(u["height"] / 3.0, 0.0, 0.7)
		shadow.scale = SHADOW_BASE * s
		shadow.modulate.a = SHADOW_BASE_A * s

# 血条 overlay: 每帧 unproject 单位头顶世界坐标 → 屏幕像素
func _update_overlay() -> void:
	if _cam == null:
		return
	for u in _units:
		var bar: Control = u["hp_label"]
		if bar == null:
			continue
		var spr: Sprite3D = u["sprite"]
		# 头顶世界坐标 = 立绘位置 + 约 2 米高 (龟头顶上方)
		var head := spr.position + Vector3(0, 2.2, 0)
		if _cam.is_position_behind(head):
			bar.visible = false
			continue
		bar.visible = true
		var screen: Vector2 = _cam.unproject_position(head)
		bar.position = screen - Vector2(30, 4)   # 居中 (血条宽60)
