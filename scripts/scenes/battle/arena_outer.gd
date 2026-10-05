class_name ArenaOuter
extends RefCounted
## 镜头能看到的【整个】范围 —— 平移/缩放的夹紧 + 岛外的海铺到看得见的最远处。
##
## ★由来(用户 2026-10-05):「地图的话我们镜头是可以移动缩放的啊，有一堆问题啊，这一个晚上你必须优化完」
##   四张图之前只在**默认机位**验收过。探针 `tests/_probe_cam_extent` 把镜头摆到 最远/最近/
##   各平移极限 × 两个画幅逐张拍, 照出来的病几乎全是同一个形状:
##     ① 岛外的海只铺到地图格子的椭圆边(58×34 格), 再往外是近黑的远景地形 ⇒ 拉远/平移就是
##        一座岛飘在一大片纯黑里, 海的外沿还露出一圈格子台阶;
##     ② 平移上限是与缩放无关的 ±9 米方框 ⇒ 默认/拉远时能把整座岛推到画面一角, 剩下全是虚空。
##   ⇒ 两件事都做: 夹紧(镜头不许看到不该看的地方) + 铺满(夹紧之内看得到的地方都有东西)。
##
## ★本文件不碰模拟: 只建外观节点、只改镜头。`verify_arena_theme_pick` 的「主题不改模拟」照旧成立。

## ── 平移夹紧 ─────────────────────────────────────────────────────────────
## 注视点处画面半宽/半纵深(米)一旦超过「内容范围」就不许再往外推。
## 内容范围 = 岛(ARENA 半宽 19.2 / 半纵深 8.7 米) + 一圈余量 —— 余量里有海岸、外围物件、外海。
const VIEW_X_EXT := 22.0
const VIEW_Z_EXT := 11.0
## 再收也给一点手感: 视野已经大过内容时(默认/拉远)仍能平移这么多(米)。
## ★x ≥ 2.2: `verify_cam_pan` 的「拖 100px 再拖回来回到原位」在默认缩放下走 2.1 米, 下限比它小就被夹住、回不到原位。
const PAN_MIN := Vector2(3.0, 2.0)


## 当前缩放/画幅下的平移上限 (x = 左右, y = 前后/世界 z)。
## ★按【当前】视口算: 同一缩放下宽屏手机(1560×720)视野比 16:9 宽 ⇒ 横向能推的更少。
static func pan_limits(b) -> Vector2:
	var cap: float = float(b.PAN_LIMIT)
	if b._cam == null or not is_instance_valid(b._cam):
		return Vector2(cap, cap)
	var off: Vector3 = b._cam_base - b.CAM_TARGET
	var L: float = off.length()
	if L < 0.01:
		return Vector2(cap, cap)
	var vs: Vector2 = b._cam.get_viewport().get_visible_rect().size
	var aspect: float = vs.x / maxf(1.0, vs.y)
	var dist: float = L / maxf(0.01, float(b._cam_zoom))
	var t: float = tan(deg_to_rad(b._cam.fov) * 0.5)            # KEEP_HEIGHT ⇒ fov 是竖向
	var sin_pitch: float = clampf(off.y / L, 0.2, 1.0)
	var hw: float = dist * t * aspect                            # 注视点处画面半宽
	var hd: float = dist * t / sin_pitch                         # 注视点处地面上的半纵深
	return Vector2(clampf(VIEW_X_EXT - hw, PAN_MIN.x, cap), clampf(VIEW_Z_EXT - hd, PAN_MIN.y, cap))


## ── 外海 ─────────────────────────────────────────────────────────────────
## 一张大平面, 用**同一个**潟湖水材质(`outer_mode` = 恒为深水、没有岸线/泡沫/板沿压暗),
## 所以格子海与外海的颜色是同一条公式算出来的 ⇒ 接缝处逐像素连续(格子台阶消失)。
## 尺寸按最坏机位算: 最远缩放 0.72 + 夹紧后的平移 + 最宽画幅 2.4:1 ⇒
##   画面上沿打到地面 z≈-34、那里半宽 ≈ 62 米; 下沿 z≈+20。铺 x∈±110, z∈[-110,+50] 带足余量。
const SEA_SIZE := Vector2(220.0, 160.0)
const SEA_CENTER_Z := -30.0
## 比格子海上表面(y=0)低一点: 格子海所在之处它被盖住, 只在格子外露出来; 又高过远景地形的平地(-0.05)。
const SEA_Y := -0.02
const FAR_SINK := 3.5
const SEA_CELL := 2.0


static func build_outer_sea(b) -> MeshInstance3D:
	var cfg: Dictionary = ArenaTheme.cfg()
	if not bool(cfg.get("outer_sea", false)):
		return null                                   # `base`(现状) 没有这一层, 一个像素不动
	var pm := PlaneMesh.new()
	pm.size = SEA_SIZE
	## ★必须细分: 本项目跑 gl_compatibility, 雾按**顶点**算。4 个顶点的大平面, 顶点全在 100 米开外
	##   ⇒ 整张平面被插值成「很浓的雾」, 比旁边的格子海亮一截, 格子海的台阶外沿反而被描出来(实拍)。
	##   细分到与格子同一量级(约 2 米), 雾就和格子海逐点一致。
	pm.subdivide_width = int(SEA_SIZE.x / SEA_CELL) - 1
	pm.subdivide_depth = int(SEA_SIZE.y / SEA_CELL) - 1
	var mi := MeshInstance3D.new()
	mi.name = "OuterSea"
	mi.mesh = pm
	mi.position = Vector3(0.0, SEA_Y, SEA_CENTER_Z)
	var c: Vector2 = b._arena_center
	var m: ShaderMaterial = BattleWorldBuilder.tile_material(1, b.WS, c.x, c.y)
	m.set_shader_parameter("outer_mode", true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b._world.add_child(mi)
	## 远景地形(`FarBackdrop`)在战场 26 米外起伏到 ~2.5 米 —— 会从外海里顶出一块块近黑的「岛」。
	## 主题的远处是海 ⇒ 把它整体沉到外海下面(不删: base 的天际线还靠它)。
	var fb: Node3D = b._world.get_node_or_null("FarBackdrop")
	if fb != null:
		fb.position.y -= FAR_SINK
	return mi
