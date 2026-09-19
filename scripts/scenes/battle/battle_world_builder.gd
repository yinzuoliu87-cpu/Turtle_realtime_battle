class_name BattleWorldBuilder
extends RefCounted
## 战场世界构建(viewport/tilemap/相机/环境/地面/竞技场/装饰/远景/光柱/气泡/navmesh·开局一次)
## 类内名不变;外部名加 battle.

## 地砖之间的缝隙【绝对宽度】(米)。0 = 无缝。
##
## ★★2026-07-31 定为 0。演进过程值得记下来, 免得有人以为"留点缝更有质感":
##   · 原来是比例式 "格宽 × 0.94"。网格加密一倍时它让缝【条数翻倍而单条只减半】,
##     整块地面读作"灯芯绒" —— 而这正是原地图被吐槽成"一块瓷砖地板"的根由。
##   · 改成绝对宽度后实测 0.055 / 0.030 / 0.014 三档, 一度定在 0.030。
##   · 但那时贴图还是【按格 UV】贴的, 表面本身就是网格, 缝只是帮凶。
##     等贴图改成世界坐标采样、表面连成一片之后再看, 缝就成了唯一还在喊"这是网格"的东西。
##   · 最后一轮实测 0.030 / 0.012 / 0: 0.012 反而最差(残余虚线 = 摩尔纹),
##     0 让海底变成一整片连续画面, 剩下的只有设计本身(岛形/石台/水)。
##   ★担心的 z-fighting 没有出现: 砖顶面全部共面于 y=0, 侧面夹在相邻砖之间看不见;
##     板子最外圈的侧面对着 void, 那里没有共面对象。抓图逐帧确认过。
const TILE_GAP_M := 0.0

## ═══ 地砖调色板 / 细节贴图 / 每 type 材质 ═══════════════════════════════
## ★2026-07-31 从 RealtimeBattle3DScene 搬来: 主场景被 arch_budget 冻结在 8600 行,
##   而这三样(调色板/贴图表/材质)本来就属于【建地面】这一层。搬完主场景 8549 行。
##   做成 static —— 主场景侧 BattleWorldBuilder.tile_material(ti) 直接调, 不用拿实例。
const TILE_COLS := {0: Color(0.169, 0.184, 0.118), 1: Color(0.122, 0.722, 0.769), 2: Color(0.361, 0.318, 0.259), 3: Color(0.290, 0.251, 0.188)}
## ★★**暖石台调色板**(2026-09-20 用户「别被深海局限住了」→「你自己定」)。
##   grass `#2b2f1e` / water `#1fb8c4`(**不动**) / stone `#5c5142` / sand `#4a4030`。
##   依据: 153 帧真实游戏内画面实测 —— 参考主色里**洋红-紫-暖橙占 54.0%,
##   青 180–210 只占 3.2%**, 而本项目整个压在那 3.2% 上(暖色只有 2.3%)。
##   三套候选实拍量过: **A 暖石台 23.3%** / B 洋红紫 4.1% / C 橄榄绿 6.6% ⇒ 取 A。
##   ★水色不动: 参考自己也画水, 只是**水比地面暗**(v0.19.413 已压暗)。
##   青水 + 暖石台 = **冷暖对比**而不是同色堆叠 —— 这才是改暖的理由。
##   ★四项全被 `tests/verify_ground_palette.gd` 钉着; 此前只有水有钉子。

## 每 tile type 的地砖细节贴图(P1·用户 2026-07-30「地图再度需要提升」)。
##
## ★这是【灰度亮度细节图】不是彩色图。原因: 本函数的既有管线就是
##   albedo_color(TILE_COLS = 锁死的暗深海夜调色板·场景地图方案.md§4)
##   × 灰度贴图, VfxTex._make_tile_texture() 的注释原文是「灰度→材质albedo_color上色」。
##   直接塞彩色图会 ①和锁死调色板相乘变成一团黑 ②等于偷偷换掉那套锁死的配色。
##   转灰度后色相仍由锁死调色板给, 新增的只是【真实的像素细节】。
##
## ★素材是 PixelLab 全新生成的(用户铁律「不要复用素材」), 16 张 best-of-N 里挑的 4 张,
##   挑选时【避开带独立道具的】(珊瑚/海星/贝壳) —— 一格图要重复 80~150 次,
##   带个珊瑚就等于满地一模一样的珊瑚(同 2026-07-23「太密+很多相同装饰」的教训)。
##   源图与挑选依据见 docs/plans/20260730b-*.md §8。
const TILE_TEX := {
	0: "res://assets/sprites/map/tile-silt.png",    # grass=深海淤泥(细颗粒)
	1: "res://assets/sprites/map/tile-water.png",   # water=水纹网(叠在滚动波纹 shader 上)
	2: "res://assets/sprites/map/tile-stone.png",   # stone=卵石铺面石台
	3: "res://assets/sprites/map/tile-sand.png",    # sand=沙纹
}

## 取某 type 的细节贴图; 文件缺了退回程序生成的斜网格(而不是崩/白图)。
## ★不做静默兜底以外的事: 缺图会 push_warning, 免得"看着像做完了"(同 TRAINER_SPRITE 的规矩)。
static var _tile_tex_cache: Dictionary = {}
static func tile_detail_tex(ti: int) -> Texture2D:
	if _tile_tex_cache.has(ti):
		return _tile_tex_cache[ti]
	var p: String = str(TILE_TEX.get(ti, ""))
	var t: Texture2D = null
	if p != "" and ResourceLoader.exists(p):
		t = load(p)
	if t == null:
		push_warning("[tile] 地砖细节贴图缺失: %s → 退回程序生成斜网格" % p)
		t = VfxTex._make_tile_texture()
	_tile_tex_cache[ti] = t
	return t

const SH_WATER := preload("res://scripts/scenes/battle/shaders/ground_water.gdshader")
const SH_LAND := preload("res://scripts/scenes/battle/shaders/ground_land.gdshader")
const MAP_PATH := "res://data/maps/arena.json"

## 每 type 的地面材质。ws/cx/cy = 主场景的 WS 与 ARENA 中心 —— 由调用方传, 【不在这里复制一份常量】
## (同一个数值在两处各写各的, 是这个项目今天已经栽过四次的坑)。
##
## ★★2026-07-31「做一板大的」: 水与陆共用一张【地图距离场】(见 map_field.gd)。
##   改前每块砖只知道自己是什么类型 ⇒ 水陆交界只能是硬切: 亮青(98)直接怼上暗淤泥(32),
##   中间零过渡, 近景放大一眼看穿, 是全图最不"精美"的地方。
##   有了距离场, 岸线泡沫 / 水深分级 / 湿沙带 全在 shader 里一次拿到。
##   所有梯度都过 4×4 Bayer 抖动再量化 —— 像素画表现渐变靠有序抖动, 不靠平滑插值。
static func tile_material(ti: int, ws: float, cx: float, cy: float) -> Material:
	var f: Dictionary = MapField.get_field(MAP_PATH, ws, cx, cy)
	var sm := ShaderMaterial.new()
	sm.shader = SH_WATER if ti == 1 else SH_LAND
	sm.set_shader_parameter("detail_tex", tile_detail_tex(ti))
	if ti != 1:
		sm.set_shader_parameter("base_col", TILE_COLS.get(ti, Color(0.2, 0.2, 0.2)))
	if not f.is_empty():
		sm.set_shader_parameter("map_field", f["tex"])
		sm.set_shader_parameter("map_org", f["org"])
		sm.set_shader_parameter("map_size", f["size"])
		sm.set_shader_parameter("field_r", MapField.FIELD_R)
	else:
		push_warning("[tile] 地图距离场烘不出来 → 岸线/水深退化成平涂")
	# ★低画质/移动端: 关掉焦散与沉积起伏(约 13 个正弦/片元)。
	#   ★桌面 A/B/A 背对背实测【差值在噪声内】(开179.5 关179.6 再开179.6), 别引用"省 21%"那种数字 ——
	#     那是我一度被热降频骗出来的。这个开关是给低端移动设备的安全阀, 不是桌面实测收益。
	#   ★放在 if/else 【外面】—— 它跟距离场烘没烘出来无关, 任何情况都该设。
	sm.set_shader_parameter("rich_fx",
		not (GameState != null and GameState.perf_lite))
	return sm


var battle

## ★2026-07-27 修 nav RID 泄漏: NavigationServer2D.map_create()/region_create() 建的是【服务器 RID】,
## 不归任何节点所有 → 战斗场景 queue_free() 释放不掉, 必须显式 free_rid()。
## 全仓库原来一处 free_rid 都没有, 战斗场景也没有 _exit_tree/PREDELETE → 每建一个战斗场景
## 就永久漏 1 个 map + 1 个 region(实测 4 个场景漏 4 个, 完全线性; 队列 30 场退出报告也是 30 个)。
## 与真机玩家报告同形: tests/probe_leak.gd 注释记着〖2026-07-10〗「打到一半突然黑屏然后闪退」。
##
## 为什么挂在这个 RefCounted 上而不是主战斗场景: ①主文件有 arch 预算棘轮(冻结行数), 不宜再加代码
## ②本类就是 navmesh 的创建者, 谁创建谁释放 ③battle 被 free 时本对象引用计数归零 → PREDELETE 必触发,
## 且此刻 battle 可能已失效, 所以【RID 要在本地留一份】, 不能回头读 battle._nav_map。
var _own_nav_map: RID
var _own_nav_region: RID


func _init(b) -> void:
	battle = b


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# ★必须【内联】, 不能调 _free_nav_rids() —— PREDELETE 时脚本实例已在析构中,
		#   对 self 的方法调用会报 "Attempt to call function ... in base 'null instance'"
		#   (2026-07-27 实测: 第一版就是这么写的, PREDELETE 触发了但 RID 一个没放掉)。
		if _own_nav_region.is_valid():
			NavigationServer2D.free_rid(_own_nav_region)
		if _own_nav_map.is_valid():
			NavigationServer2D.free_rid(_own_nav_map)


## 释放自己建的 nav 服务器 RID。先 region 后 map(region 挂在 map 上)。幂等。
func _free_nav_rids() -> void:
	if _own_nav_region.is_valid():
		NavigationServer2D.free_rid(_own_nav_region)
		_own_nav_region = RID()
	if _own_nav_map.is_valid():
		NavigationServer2D.free_rid(_own_nav_map)
		_own_nav_map = RID()

# ----------------------------------------------------------------------------
#  SubViewport 合成: 3D 渲进它 → SubViewportContainer 贴满屏; 2D UI 叠上面.
#  (GL Compatibility 下主窗口截图丢直接渲染的 3D → SubViewport 截图可靠; unproject 1:1 可用)
# ----------------------------------------------------------------------------
func _build_viewport() -> void:
	var vp_size = Vector2i(1280, 720)
	if battle.get_viewport() != null:
		var s = battle.get_viewport().get_visible_rect().size
		if s.x > 1 and s.y > 1:
			vp_size = Vector2i(s)
	var container = SubViewportContainer.new()
	container.name = "ViewportContainer"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_layer = CanvasLayer.new()
	bg_layer.name = "WorldLayer"
	bg_layer.layer = 0
	battle.add_child(bg_layer)
	bg_layer.add_child(container)
	battle._sub = SubViewport.new()
	battle._sub.name = "World3D"
	battle._sub.size = vp_size
	battle._sub.transparent_bg = false
	battle._sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	battle._sub.handle_input_locally = false
	# ★A4 黑屏排查: 移动端 SubViewport + MSAA 在部分安卓 GPU 上有问题 → 移动端默认关 MSAA。桌面保留 2X。
	battle._sub.msaa_3d = Viewport.MSAA_DISABLED if battle._is_mobile() else Viewport.MSAA_2X
	# 低画质模式(设置里的开关·持久化): 关抗锯齿 + 3D 渲染分辨率 ×0.75 (UI 层不受影响, 仍是原生分辨率)
	if GameState != null and GameState.perf_lite:
		battle._sub.msaa_3d = Viewport.MSAA_DISABLED
		battle._sub.scaling_3d_scale = 0.75
	container.add_child(battle._sub)
	battle._world = Node3D.new()
	battle._world.name = "World"
	battle._sub.add_child(battle._world)

# ═══ 新地图 tile 系统 (MultiMesh 方块地面 · 数据驱动 map.json · 纯视觉不改玩法) ═══
# 5类型: 0 grass主地面 / 1 water水凹 / 2 stone石台凸 / 3 sand浅滩 / 4 void空(不渲染)
func _build_tilemap_ground() -> void:
	if battle._load_tilemap():                 # 优先数据驱动 map.json
		if not OS.has_environment("MAPEDIT"): _build_tilemap_decor()   # 装饰: 正式对局/TILEMAP都加, 仅编辑器不加(免遮挡刷格)
		return
	var TILE = 48.0                    # px/格 (fallback: json缺失时程序化生成·同阶段0逻辑)
	var A = battle.ARENA
	var mg = 6                         # 外扩格数(填满画面·远处沉黑)
	var cols = int(ceil(A.size.x / TILE)) + mg * 2
	var rows = int(ceil(A.size.y / TILE)) + mg * 2
	var x0 = A.position.x - float(mg) * TILE
	var y0 = A.position.y - float(mg) * TILE
	var tw_m = TILE * battle.WS
	var cx = A.position.x + A.size.x * 0.5
	var cy = A.position.y + A.size.y * 0.5
	var xf_grass: Array = []; var xf_water: Array = []; var xf_stone: Array = []
	for r in range(rows):
		for c in range(cols):
			var px = x0 + (float(c) + 0.5) * TILE
			var py = y0 + (float(r) + 0.5) * TILE
			var t = "grass"; var h = 0.0
			var dx = (px - cx) / (A.size.x * 0.32)
			var dy = (py - cy) / (A.size.y * 0.42)
			if dx * dx + dy * dy < 1.0:                                   # 中央椭圆=水池(颜色区分·去高低差2026-07-15)
				t = "water"; h = 0.0
			elif (px < A.position.x + A.size.x * 0.15 or px > A.position.x + A.size.x * 0.85) and py > A.position.y and py < A.position.y + A.size.y:
				t = "stone"; h = 0.0                                      # 两端石台(颜色区分·不抬高=特效不掉地下)
			var xf = Transform3D(Basis(), battle._world_pos(Vector2(px, py), h - battle.TILE_SINK))
			match t:
				"water": xf_water.append(xf)
				"stone": xf_stone.append(xf)
				_: xf_grass.append(xf)
	battle._tilemap_add(xf_grass, Vector3(maxf(0.02, tw_m - TILE_GAP_M), battle.TILE_THICK, maxf(0.02, tw_m - TILE_GAP_M)), Color(0.10, 0.14, 0.26))   # 暗蓝主地面
	battle._tilemap_add(xf_water, Vector3(maxf(0.02, tw_m - TILE_GAP_M), battle.TILE_THICK, maxf(0.02, tw_m - TILE_GAP_M)), Color(0.12, 0.72, 0.78))   # 青水(凹)
	battle._tilemap_add(xf_stone, Vector3(maxf(0.02, tw_m - TILE_GAP_M), battle.TILE_THICK, maxf(0.02, tw_m - TILE_GAP_M)), Color(0.24, 0.26, 0.38))   # 石台(凸)

# 阶段4: 边框密植发光水草/珊瑚(确定性种子·只非战斗区=ARENA外) + 氛围辉光粒子
## ═══ 场地边界的体积(P1-5) ═════════════════════════════════════════════
## 用户 2026-09-18 说战斗场景很烂; 对标 30 款同类型好游戏后, 边界是差距最明确的一条:
## 好游戏的场地边界从来不是「颜色换一下」, 而是一个**能看见侧面的构件**。
## 本项目现在 tile 板厚只有 `TILE_THICK = 0.15 米` ⇒ 投到屏上 **2.63 px**(实测, 见
## `tests/_probe_pxm.gd`), 等于一张贴纸直接切进黑色虚空。
##
## ★数值全部来自实测标定, 不是拍脑袋(方案书 R15):
##   · 参考(TFT 实测·做过透视校正): 竖面 ÷ 角色屏幕高 = 0.81
##   · 本项目: 龟屏幕高中位 38 px ⇒ 目标竖面 ≈ 31 px
##   · 龟与本构件都是**朝相机的 billboard**(不吃 cos50.8° 俯角压缩)
##     ⇒ 世界高 = 31 ÷ 27.78 = **1.11 米**
##     ⚠ 若哪天改成真实竖直几何, 同样 31 px 要 **1.75 米** —— 差 1.58 倍, 别混用。
##   · 贴图 64×32(由 128×64 整数降半), 渲染高 31 px ≈ 1:1, 不打烂像素网格。
##   · 结构照实测: 亮竖面被**上下两条暗缝**夹住(顶沿投影 + 落地接触影) ——
##     实测里竖面是全场【最亮】的, 不是我原先以为的「一段暗侧面」。
##
## ★只做南北向(屏幕上的水平边)的连续条带 —— 实测 49 个可见边界格里 **42 个在画面上 1/3**,
##   全是远端的南北向边; 东西向边基本落在左右 185px 的 UI 栏后面, 按格单发即可。
const WALL_TEX := "res://assets/sprites/map/wall-edge.png"
const WALL_H_M := 1.11          # 世界高(米) —— billboard 口径, 见上
const WALL_TEX_H := 32.0        # 贴图原生高(texel)
const WALL_COL := Color(0.227, 0.247, 0.361)   # = TILE_COLS[2] 石台色, **不新增颜色**(调色板硬锁·只在下面调明度)
## ★光照补偿。墙卡是 UNSHADED(明暗由贴图给), 而地面是**吃光的**(主光 1.15 + 补光 0.45 + 环境光 0.85)
##   ⇒ 同一个调色板色, 墙比地面暗一大截。第一版实拍就是这么栽的: 标定要求墙比场内地面
##   **亮 23%~40%**, 实测反而更暗。
##   ★★这个数只能【实拍量】不能算。我手算过一版: 贴图竖面均值 171/255 ⇒ 预测 ×2.34 落在 +30%,
##     实拍复量却是 **+97%**(墙像素中位 152 vs 地面 77) —— 整整过头一倍。
##     原因是"贴图均值"不等于"渲染出来的墙像素中位"(亮砖块占多数, 暗缝把均值拉低了)。
##     ⇒ 按实拍反解 ×1.55。★同族教训见 memory「我拍的阈值会把好素材改坏」。
##   ★只乘明度不动色相 —— 三通道同比例缩放, 调色板的 hue 一个度都没转。
##   ⚠ 这个数依赖【地面有多亮】。若哪天动了灯光(见 R13), 必须重量一次, 不能照抄。
##   ⚠ 复量方法: 拿"加墙前/后同种子两张实拍"做差分分割出墙像素(别用我拍的亮度阈值),
##     取中位与场内地面中位比 —— 用方框平均会被段间空隙稀释(第一次就读成 +2%)。
const WALL_H_M_GEO := 1.75    # 真实竖直几何口径(同样读出 31px 要 1.75 米, billboard 只要 1.11)
const WALL_COL_LIT := Color(0.62, 0.66, 0.86)   # 吃光后的基色(不再乘 WALL_GAIN)

## ═══ 场内暖色点光源（2026-09-20）═══════════════════════════════════
## ★★为什么有它：全仓 `OmniLight3D`/`SpotLight3D` **一个都没有**。
##   实测本项目场内亮核 2.33%，但色相全是 **183~204°（青）**——那是岸线高光和光柱，
##   **不是光源**。而参考里每屏有 0~4 个**暖色**光源。
##
## ★规格是量出来的不是拍的（`docs/design/20260920-场内道具规格调研.md` §⑤，
##   6 张参考图逐个人工定位 + 程序测量 13 个光源）：
##     个数   每屏 **2.2 个**（区间 0~4）
##     发光核 合计 **0.299%** 场地面积；单个 0.004%~0.587%
##     色相   **中位 57°**，9/13 落在 15~60°（暖黄橙）
##   代表值：TFT_2 火盆 `#FDF77B`(57°) / HadesII_1 神龛 `#F6EE53`(57°) / CotL 纸灯笼 `#FDDA68`(46°)
##
## ★为什么是**点光源**而不是再画一块亮贴图：贴图只会再多一块"高饱和色块"，
##   而 153 帧实测说本项目的病正是**一整块**（最大连通块 15.65% vs 参考 p50 0.43%）。
##   点光源给的是**衰减的光晕**——它自带明度过渡，正是判据④「亮坡比」要的东西。
const LAMP_COL := Color(0.992, 0.969, 0.482)   # #FDF77B · 色相 57°(参考中位)
const LAMP_N := 3                              # 参考每屏 2.2 个(0~4) ⇒ 取 3
const LAMP_ENERGY := 2.2
const LAMP_RANGE_M := 7.5
## 位置（ARENA 归一化 0~1）。★避开正中心的接战区，放在参考里"外圈但不贴边"的位置——
##   实测本项目中心半区只有 5% 有东西（参考 15%），而纯装饰在内圈是 **0 件**。
const LAMP_AT := [Vector2(0.22, 0.30), Vector2(0.78, 0.30), Vector2(0.50, 0.78)]
## ★★**光要有来源物** —— 用户 2026-09-07「你不能凭空没有逻辑出现」。
##   只放 `OmniLight3D` 而不画灯具, 地上就是三团凭空出现的暖斑 ——
##   参考里每个暖光都有实体(火盆/灯笼/火把), 实测 13 个光源无一例外。
## ★素材**全新生成**(PixelLab, 铁律「新内容一律新素材」), 实测:
##   64×64 · 发光核色相中位 **42°**(规格区间 15~60°) · **零半透明像素**(硬边像素画)。
const LAMP_TEX := "res://assets/sprites/map/brazier.png"
const LAMP_H_M := 1.28          # 火盆世界高(米)。按 ~50 texels/m 口径: 64 texel ÷ 50 = 1.28

## ★★★这个常量已经连着【三轮】需要重标定, 记一笔: 1.55(v0.19.405) → 1.70(水面重做) → 2.05(灯光重做)。
##   每次都是因为"地面变亮了、墙没跟着变" —— 根因是**墙卡是 UNSHADED 而地面吃光**,
##   两者之间只靠这一个手工标定的数连着。⇒ **它是脆的**, 已登记成方案书 20260918b 的 W8。
##   真正的解法是让墙也吃光(或按灯光能量推导增益), 那是独立一轮的活, 本轮不做。
##   ⚠ 在那之前: **任何动灯光/地面亮度的改动, 都必须重跑一次实拍标定**, 别照抄这个数。
## ★★2026-09-18(同日·水面重做后) 1.55 → 1.70: 上面那句「这个数依赖地面有多亮」当场应验 ——
##   水面重做把场内地面明度从 78.2 抬到 81.6, 墙就从 +24% 掉到 **+18%**, 掉出标定区间(+23~40%)。
##   ⇒ 只要动灯光/地面亮度, 这个数必须重量。方案书 20260918b 的 W3 登记的就是这条。

func build_edge_wall(grid: Array, w: int, h: int, tile: float, ox: float, oy: float) -> Array:
	var made: Array = []
	var tex: Texture2D = load(WALL_TEX) if ResourceLoader.exists(WALL_TEX) else null
	if tex == null:
		push_warning("[edge_wall] 贴图缺失: %s —— 不画边界墙(不做静默兜底)" % WALL_TEX)
		return made

	## 取格子类型; 越界当 void(4)
	var at := func(r: int, c: int) -> int:
		if r < 0 or r >= h or c < 0 or c >= w:
			return 4
		var row: Array = grid[r]
		if c >= row.size():
			return 4
		return int(row[c])

	## ── 把「岛↔void」的每条格边收成线段, 再串成连续折线 ───────────────
	## ★★2026-09-19 换实现。原来是【逐格墙卡】(每段 run 一张 QuadMesh billboard),
	##   2026-09-18 实拍四向全画当场否掉 ——「一层层错开互相重叠的砖带」, 只好退到只画朝北一圈。
	##   ★根因不是"岛的轮廓是阶梯", 是**卡片各自独立**: 斜边上相邻 run 分属不同行,
	##     每张卡各自发卡、各自朝相机, 于是读成一堆错开的砖。
	##   ★参考里 15 张边界裁图(shapecal/edge/)**没有一张是逐格卡**:
	##     Arknights_4/BrawlStars_3 是台地挤出侧面; BrawlStars_2/4 绿篱; ClashOfClans_2 城墙件排成一条;
	##     CultOfTheLamb_1 白石 curb; HadesII_1/Hades_1 栏杆女儿墙; Hades_0 骨柱环; TFT_1 植被带。
	##     **共同点是「边界上有一条连续构件」, 不是「轮廓必须是直边」** ——
	##     C 类(格子化阶梯)在参考里有 8 张, 格子阶梯本身不是病, **裸着的阶梯边**才是。
	##   ⇒ 现在: 整圈边界抽成折线, 生成**一个 ArrayMesh 的连续竖直带**(连续 UV、不断开)。
	var segs: Array = []                                  # [[Vector2 a, Vector2 b], ...] 像素口径
	for r in range(h):
		for c in range(w):
			if at.call(r, c) == 4:
				continue
			var x0 := ox + float(c) * tile
			var y0 := oy + float(r) * tile
			var x1 := x0 + tile
			var y1 := y0 + tile
			if at.call(r - 1, c) == 4:
				segs.append([Vector2(x0, y0), Vector2(x1, y0)])
			if at.call(r + 1, c) == 4:
				segs.append([Vector2(x1, y1), Vector2(x0, y1)])
			if at.call(r, c - 1) == 4:
				segs.append([Vector2(x0, y1), Vector2(x0, y0)])
			if at.call(r, c + 1) == 4:
				segs.append([Vector2(x1, y0), Vector2(x1, y1)])
	if segs.is_empty():
		push_warning("[edge_wall] 一条边界段都没收到 —— 地图全是 void? 不画(不做静默兜底)")
		return made

	var loops := _chain_loops(segs)
	var root := Node3D.new()
	root.name = "EdgeWall"
	battle._world.add_child(root)
	made.append(root)
	var mi := _edge_band_mesh(loops, tex)
	if mi != null:
		root.add_child(mi)
		made.append(mi)
	return made


## 把零散线段串成首尾相接的折线环。返回 [[Vector2...], ...]。
## ★串不起来的(孤立段)单独成一条开口折线 —— **不静默丢掉**, 丢了就是边界缺口。
func _chain_loops(segs: Array) -> Array:
	var start_map: Dictionary = {}                        # key(起点) -> [段下标...]
	var key := func(p: Vector2) -> String:
		return "%.1f_%.1f" % [p.x, p.y]
	for i in range(segs.size()):
		var k: String = key.call((segs[i] as Array)[0])
		if not start_map.has(k):
			start_map[k] = []
		(start_map[k] as Array).append(i)
	var used := {}
	var loops: Array = []
	for i in range(segs.size()):
		if used.has(i):
			continue
		var poly: Array = [(segs[i] as Array)[0], (segs[i] as Array)[1]]
		used[i] = true
		var guard := 0
		while guard < segs.size() + 4:
			guard += 1
			var k: String = key.call(poly[poly.size() - 1])
			if not start_map.has(k):
				break
			var nxt := -1
			for j in start_map[k]:
				if not used.has(int(j)):
					nxt = int(j)
					break
			if nxt < 0:
				break
			used[nxt] = true
			poly.append((segs[nxt] as Array)[1])
			if poly[poly.size() - 1].is_equal_approx(poly[0]):
				break
		if poly.size() >= 3:
			loops.append(poly)
	return loops


## 沿折线生成一条连续竖直带(单个 ArrayMesh)。
## ★高度用 WALL_H_M_GEO 不是 WALL_H_M: 前者是**真实竖直几何**口径, 后者是 billboard 口径 ——
##   同样要在屏幕上读出 31px, 真几何要 1.75 米、billboard 只要 1.11 米(差 1.58 倍, 见上一篇标定)。
## ★双面不剔除: 远端(北)那一圈的外表面背对相机, 不关剔除就看不见 ——
##   而 42/49 个可见边界格恰恰都在那一圈。绿篱/栏杆类构件本来也都是双面片。
func _edge_band_mesh(loops: Array, tex: Texture2D) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tex_w_m: float = WALL_H_M_GEO * (float(tex.get_width()) / WALL_TEX_H)
	var quads := 0
	for poly in loops:
		var pts: Array = poly
		var run := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg_m: float = a.distance_to(b) * battle.WS
			if seg_m <= 0.0001:
				continue
			var u0: float = run / tex_w_m
			var u1: float = (run + seg_m) / tex_w_m
			run += seg_m
			var a_lo: Vector3 = battle._world_pos(a, 0.0)
			var b_lo: Vector3 = battle._world_pos(b, 0.0)
			var a_hi: Vector3 = a_lo + Vector3(0.0, WALL_H_M_GEO, 0.0)
			var b_hi: Vector3 = b_lo + Vector3(0.0, WALL_H_M_GEO, 0.0)
			st.set_uv(Vector2(u0, 1.0)); st.add_vertex(a_lo)
			st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b_lo)
			st.set_uv(Vector2(u1, 0.0)); st.add_vertex(b_hi)
			st.set_uv(Vector2(u0, 1.0)); st.add_vertex(a_lo)
			st.set_uv(Vector2(u1, 0.0)); st.add_vertex(b_hi)
			st.set_uv(Vector2(u0, 0.0)); st.add_vertex(a_hi)
			quads += 1
	if quads == 0:
		push_warning("[edge_wall] 折线串起来了但一个四边形都没生成 —— 不画")
		return null
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "EdgeBand"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = WALL_COL_LIT
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST     # 像素画不许插值成糊
	m.texture_repeat = true
	## ★★吃光(W8): 原来是 UNSHADED + 手工标定的 `WALL_GAIN` —— 那个数被地面亮度牵着走,
	##   2026-09-18 一天内重标定了三次(1.55→1.70→2.05)。真实几何吃光之后, 亮度跟着灯光走,
	##   不再需要那个常量。**W8 关闭。**
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 场内暖色点光源。返回建出来的节点（调用方登记/清场用）。
func build_field_lamps() -> Array:
	var made: Array = []
	var root := Node3D.new()
	root.name = "FieldLamps"
	battle._world.add_child(root)
	made.append(root)
	var A: Rect2 = battle.ARENA
	var tex: Texture2D = load(LAMP_TEX) if ResourceLoader.exists(LAMP_TEX) else null
	if tex == null:
		push_warning("[field_lamps] 火盆贴图缺失: %s —— 光会没有来源物(不做静默兜底)" % LAMP_TEX)
	for uv in LAMP_AT:
		var px := A.position + Vector2(A.size.x * uv.x, A.size.y * uv.y)
		var lamp := OmniLight3D.new()
		lamp.light_color = LAMP_COL
		lamp.light_energy = LAMP_ENERGY
		lamp.omni_range = LAMP_RANGE_M
		## ★不投影：这是氛围光不是主光，投影会让 28 只龟各拖一条影子、且吃性能。
		lamp.shadow_enabled = false
		## 抬离地面一点，光晕才铺得开（贴地会被地面自己挡掉一半）。
		## 光源抬到火盆碗口高度(不是贴地), 光晕才铺得开且看着像是火发出来的。
		lamp.position = battle._world_pos(px, LAMP_H_M * 0.85)
		root.add_child(lamp)
		made.append(lamp)
		## ★灯具本体: billboard 立绘(不吃俯角压缩), 底部贴地。
		if tex != null:
			var s := Sprite3D.new()
			s.texture = tex
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画不许插值成糊
			s.shaded = false
			s.pixel_size = LAMP_H_M / float(tex.get_height())
			s.position = battle._world_pos(px, LAMP_H_M * 0.5)
			root.add_child(s)
			made.append(s)
	return made


func _build_tilemap_decor() -> void:
	var root = Node3D.new(); root.name = "TileDecor"; battle._world.add_child(root)
	var rng = RandomNumberGenerator.new(); rng.seed = 20260714
	var A = battle.ARENA
	var cx = A.position.x + A.size.x * 0.5
	var cy = A.position.y + A.size.y * 0.5
	# ★点2(用户2026-07-23: 测试反馈太密+很多相同装饰): 去掉原glow-coral/glow-kelp各2遍的人为加权刷屏,
	#   并补 PixelLab 生成的 4 种新装饰(扇贝/石头/海星/海草·壳石生植不同类)增加种类, 现共 11 种。
	var kelp = ["deco_kelp", "deco_coral_pink", "deco_coral_orange", "deco_rocks", "deco_scallop", "deco_boulder", "deco_starfish", "deco_seagrass", "glow-kelp", "glow-anem", "glow-coral"]
	var mg = 200.0   # ★装饰带收窄 288→200(点2: 太密)
	var step = 120.0   # ★网格放大 80→120(点2: 稀疏)
	var placed: Array = []   # ★防扎堆: 记已放点, 太近(<70px)跳过(点2: 原无间距检查→成簇)
	var py = A.position.y - mg
	while py < A.end.y + mg:
		var px = A.position.x - mg
		while px < A.end.x + mg:
			var outside_arena = not A.has_point(Vector2(px, py))
			var do = pow((px - cx) / (A.size.x * 0.72), 2.0) + pow((py - cy) / (A.size.y * 0.92), 2.0)   # <1=地图内有tile
			if outside_arena and do < 0.98 and rng.randf() < 0.30:   # ★概率 0.58→0.30(点2: 稀疏一半)
				var jx = px + rng.randf_range(-26.0, 26.0)
				var jy = py + rng.randf_range(-26.0, 26.0)
				var jp = Vector2(jx, jy)
				var too_close = false
				for pp in placed:
					if (pp as Vector2).distance_to(jp) < 70.0:
						too_close = true; break
				if not too_close:
					placed.append(jp)
					var img: String = kelp[rng.randi() % kelp.size()]
					var spr = battle._map_billboard("res://assets/sprites/map/%s.png" % img, jp, rng.randf_range(1.5, 2.7))
					var s = rng.randf_range(0.82, 1.28) * (1.15 if do > 0.7 else 1.0)   # 越靠边框越大(框边压)
					spr.scale = Vector3(s * (-1.0 if rng.randf() < 0.5 else 1.0), s, s)   # ★随机水平镜像破"一模一样"(点2)
					var _b: float = rng.randf_range(0.82, 1.08)   # ★明暗/色相抖动(点2: 原modulate死值Color(0.5,0.68,0.92)→全同)
					## ★★2026-09-18 环境色偏从 (0.50,0.68,0.92) 放松到 (0.88,0.94,1.00)。
					## 原值把【红通道砍掉一半】, 11 种颜色各异的装饰全被拉进同一个暗蓝紫区间(实测):
					##   deco_coral_orange #f0d060 亮金黄 → #788d58 暗橄榄
					##   deco_starfish     #e07000 亮橙   → #704c00 暗棕
					##   deco_scallop      #f0d0f0 亮粉白 → #788ddc 灰蓝紫
					## 这不是在遵守硬锁调色板 —— 调色板(场景地图方案.md §4)明确写着
					## 「发光点缀(珊瑚/水草) 粉#ff6ba3 / 紫#7c5cff / 青#3be0c0」, 装饰【本来就该是彩色的】。
					## 同一文件的 _build_decorations 用的也是 (0.92,0.96,1.0), 0.50 那个是异常值。
					spr.modulate = Color(clampf(0.88 * _b + rng.randf_range(-0.05, 0.05), 0.0, 1.0), clampf(0.94 * _b, 0.0, 1.0), clampf(1.00 * _b + rng.randf_range(-0.04, 0.04), 0.0, 1.0))
					root.add_child(spr)
			px += step
		py += step
	_build_midground(root)      # P2: 中距离地标(补远景与边框装饰带之间那段空白)
	_build_tilemap_ambient(root)


## ═══ P2 · 中景地标 (用户 2026-07-30「地图再度需要提升」· 拍板 U7 顺序 P1→P2→P4→P3) ═══
##
## ★为什么要这一层: 现在只有【远景三层】(渐变水幕/远礁剪影/水面光柱, 在 z≈-19)
##   和【边框装饰带】(ARENA 外 0~200px 的小水草珊瑚)。两者之间是空的 ——
##   画面上从"贴着场地的小装饰"直接跳到"很远的剪影", 中间没有过渡, 纵深断层。
##   本层补的就是那段: ARENA 外 200~520px 的环带, 放少量【大件】地标。
##
## ★别往边框装饰带里加密度 —— 2026-07-23 测试反馈「太密 + 很多相同装饰」已经调稀过一轮
##   (概率 0.58→0.30、步长 80→120、带宽 288→200)。所以这里是【另起一层】且数量很少。
##
## ★大气透视: 越远 → 越暗、越偏背景蓝、alpha 越低。这是"读出距离"的关键 ——
##   远景礁石那边的注释也记着同一条(前景尺度的礁石拉到远处会因细节密度不对而读不出距离)。
##
## ★确定性: 用【播种】RNG。裸随机会被 rng_discipline 门禁拦(护确定性回放)。
const MID_OBJS := [
	{"img": "mid_shipwreck", "h": 3.9, "w": 1.25},      # 沉船船体(宽扁)
	{"img": "mid_coral_pillar", "h": 5.4, "w": 0.55},   # 珊瑚礁柱(高瘦·尖端微发光)
	{"img": "mid_stone_column", "h": 5.0, "w": 0.45},   # 断裂石柱(高瘦)
]
const MID_BAND_IN := 280.0     # 环带内沿(留在边框装饰带外沿之外一截, 不重叠也不挤)
## ★环带宽度调过两轮: 200~520 时沉船在画面上沿又大又黑抢戏; 推到 260~640 又太远,
##   珊瑚礁柱/石柱全跑出画面, 只剩两个船体剪影。280~480 是"看得见但不抢戏"的那一档。
const MID_BAND_OUT := 480.0    # 环带外沿
const MID_COUNT := 13          # 总件数。少而大 = 地标; 多了就变回"装饰刷屏"
const MID_MIN_GAP := 260.0     # 两件之间最小间距(码), 防扎堆

func _build_midground(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730                       # 播种(不用裸随机·护 rng_discipline 棘轮)
	var A: Rect2 = battle.ARENA      # ★不能用 := —— battle 是无类型变量, 推不出 A 的类型(编译直接红)
	var cx: float = A.position.x + A.size.x * 0.5
	var cy: float = A.position.y + A.size.y * 0.5
	var placed: Array = []
	var tries := 0
	while placed.size() < MID_COUNT and tries < 400:
		tries += 1
		# 极坐标撒点: 角度均匀, 半径落在环带内(按椭圆缩放, 贴合场地长宽比)
		var a: float = rng.randf() * TAU
		var t: float = rng.randf()
		var band: float = MID_BAND_IN + (MID_BAND_OUT - MID_BAND_IN) * t
		var p := Vector2(cx + cos(a) * (A.size.x * 0.5 + band),
						cy + sin(a) * (A.size.y * 0.5 + band))
		var too_close := false
		for q in placed:
			if (q as Vector2).distance_to(p) < MID_MIN_GAP:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var ob: Dictionary = MID_OBJS[rng.randi() % MID_OBJS.size()]
		var path: String = "res://assets/sprites/map/%s.png" % str(ob["img"])
		if not ResourceLoader.exists(path):
			push_warning("[midground] 中景素材缺失: %s" % path)
			continue
		# 远近: t=0 贴场地(大而清), t=1 最远(小而暗)。★同时缩尺寸和压色, 只压色会显得"贴纸"
		var far: float = t
		var hh: float = float(ob["h"]) * lerpf(1.0, 0.72, far)
		var spr: Sprite3D = battle._map_billboard(path, p, hh)
		if spr.texture == null:
			continue
		# 大气透视: 往背景蓝里压, 越远越狠; alpha 也降(让远景水幕透一点上来)
		# ★第一版压得不够: 沉船在画面上沿又大又黑, 抢戏且贴着 HUD 带, 读起来像"悬在水中"
		#   而不是远处地标。往外推 + 压小 + 再压暗一档后才退回背景层。
		var k: float = lerpf(0.50, 0.24, far)
		spr.modulate = Color(k * 0.72, k * 0.86, k * 1.12, lerpf(0.80, 0.45, far))
		if rng.randf() < 0.5:
			spr.scale = Vector3(-1.0, 1.0, 1.0)   # 随机水平镜像, 破"一模一样"
		root.add_child(spr)

func _build_tilemap_ambient(root: Node3D) -> void:   # 氛围辉光粒子: 覆盖场地·冰蓝→白·缓上飘·ADD发光
	var p = GPUParticles3D.new()
	p.amount = 100
	p.lifetime = 6.5
	p.local_coords = false
	p.position = Vector3(0.0, 2.0, 0.0)
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(battle.ARENA.size.x * battle.WS * 0.55, 4.0, battle.ARENA.size.y * battle.WS * 0.55)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 28.0
	pm.initial_velocity_min = 0.12
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.0, 0.12, 0.0)
	pm.scale_min = 0.3
	pm.scale_max = 0.95
	var grad = Gradient.new()
	grad.set_color(0, Color(0.40, 0.70, 1.0, 0.0))
	grad.add_point(0.3, Color(0.58, 0.84, 1.0, 0.85))
	grad.add_point(0.7, Color(0.86, 0.95, 1.0, 0.7))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gtex = GradientTexture1D.new(); gtex.gradient = grad
	pm.color_ramp = gtex
	p.process_material = pm
	var dm = StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm = QuadMesh.new(); qm.size = Vector2(0.1, 0.1); qm.material = dm
	p.draw_pass_1 = qm
	root.add_child(p)

func _build_camera() -> void:
	battle._cam = Camera3D.new()
	battle._cam.name = "Camera3D"
	battle._cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	battle._cam.fov = 50.0
	# 场地上方偏后俯视下来 (3/4). 抬高+拉远以容纳 ~27×12.5 米全场.
	battle._cam.position = Vector3(0.0, 18.9, 25.5)   # 放大1.4×后同比拉远(0,13.5,18.2→×1.4), 角度不变框住更大场地
	if battle.MAP_V2 or OS.has_environment("TILEMAP") or OS.has_environment("MAPEDIT"):          # ★新地图相机: 微调更陡(俯角~36°→~51°)+低FOV, 更像地图俯视(用户2026-07-13"我定更陡的")
		battle._cam.fov = 40.0
		battle._cam.position = Vector3(0.0, 28.0, 22.0)   # 俯角 atan2(27.4,22)≈51°; fov40拉远补框
	battle._world.add_child(battle._cam)
	battle._cam.look_at(battle.CAM_TARGET, Vector3.UP)
	battle._cam_base = battle._cam.position               # Phase4: 震屏围绕此基准偏移, 衰减后精确归位
	battle._cam_zoom_base = battle._cam_base              # 初始缩放基准=默认位(zoom=1)
	battle._juice_rng.randomize()
	# ★sim RNG 种子化(Phase1): TURTLE_SEED=<int> 时确定(测试/回放)·否则 randomize()(默认·手感不变)
	var _bseed = OS.get_environment("TURTLE_SEED")
	if _bseed != "" and _bseed.is_valid_int():
		battle._battle_rng.seed = int(_bseed)
		battle._deterministic = true   # 固定 sim 步长 → 同种子+同帧序 = 可复现(headless 回放/验证/CI)
	else:
		battle._battle_rng.randomize()

func _build_environment() -> void:
	# 主光 (顶光偏前侧): 暖白, 给立绘/地面立体受光. shaded=false 立绘不吃光, 但地面/影/召唤体吃 → 仍出体积感.
	var light = DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	## ★★2026-09-18 灯光重做(用户「都要仔细重做」): 1.15 → 1.55, 配合环境光 0.85 → 0.55。
	##   **这一版是 A/B 实测挑出来的, 不是调出来的**。试了三个变体, 每个都实拍复量:
	##     V1 现状                  中间调 53.5 · 色数 116 · 亮部饱和 0.621 · 近中性 1.6%
	##     V2 环境光中性化(同明度)    中间调 53.3 · 色数 113 · 亮部饱和 0.619 · 近中性 1.6%  ← **几乎零变化**
	##     V3 环境0.55 + 主光1.55    中间调 55.7 · 色数 125 · 亮部饱和 0.486 · 近中性 2.7%  ← 取这个
	##   ★V2 否掉的是我自己的假设(「把环境光去饱和能降整体饱和度」) —— 实测不成立, 幸好没直接改。
	##   ★★V3 的优势**跑了 5 次基线确认过不是噪声**(同一份代码):
	##     亮部饱和 0.542~0.621(极差 0.079) → V3 0.486 落在区间外; 色数 113~116 → 125; 中间调 52.6~54.5 → 55.7。
	##     而"近中性"基线 1.6~3.0、V3 2.7 **落在噪声内 ⇒ 这一项不算改善, 不许拿它邀功**。
	##   ⚠ 动这两个数就要重标定 `WALL_GAIN`(见本文件 WALL_GAIN 处的长注)。
	light.light_energy = 1.55
	light.light_color = Color(1.0, 0.96, 0.86)
	battle._world.add_child(light)
	# 补光 (深海冷蓝, 从对侧低角打来): 给阴影面注入海水冷色, 避免死黑, 加层次.
	var fill = DirectionalLight3D.new()
	fill.name = "FillCold"
	fill.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.42, 0.66, 0.85)
	battle._world.add_child(fill)
	## ★★★2026-09-18 实测警告 —— 【不要】把这个分支改成常开。
	##   这半边(灯光/天空)和地面那半边(MAP_V2)本是 2026-07-13 同一套「暗深海夜」设计,
	##   但地面靠 `const MAP_V2 := true` 常开了, 灯光却留在 `TILEMAP` env 后面 ⇒
	##   **正式对局两个月来跑的一直是「暗地面 + 亮灯光」的混搭**。
	##   看上去是个该修的漏接, 实测结论**相反**(同种子 A/B, 噪声底已量):
	##     TILEMAP 未设(现状)  中间调 29.3% / 有效色数 96  ⇒ tools/battle_scene_audit.py 2/2 过
	##     TILEMAP=1(配套设计) 中间调 13.1% / 有效色数 76  ⇒ **0/2 全红**
	##     两版差异 |Δ明度|>8 占 64.1%, 而同码重跑的噪声底只有 26.4% ⇒ 真效应不是抖动。
	##   根因: 陆地 shader 吃光(`ground_land` 没写 unshaded), 而水是 `unshaded` 不吃 ⇒
	##   一压灯只压暗陆地、青水不动 ⇒ 构图被反转成「发光轮廓框着一个黑洞」——
	##   正是 `ground_water.gdshader:9-10` 自己警告过的那个失败模式。
	##   ★13.1%/76 几乎就是 v0.19.403 提亮之前的那组数(11.1%/73) ⇒
	##     **这套灯光本身就是「战斗背景很烂」的成因之一**, 它关着是走运不是缺陷。
	##   ★留着不删: 这是用户 2026-07-13 那天的设计意图, 未拍板不擅自删。
	##     但谁想"把漏接补上"之前, 先跑一遍上面那个 A/B。
	if OS.has_environment("TILEMAP"):    # 暗深海夜: 压暗主/补光(★见上, 实测更差, 别常开)
		light.light_energy = 0.62
		fill.light_energy = 0.30

	var env = Environment.new()
	# 背景: 由亮到暗的深海立式渐变 (天空 SkyMaterial 程序生成, 无外部图) → 远处不再是单色硬墙.
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.07, 0.26, 0.36)      # 顶部亮蓝绿 (阳光浅海, 卡通鲜活)
	sky_mat.sky_horizon_color = Color(0.14, 0.42, 0.48)  # 水平线亮青 (背景是明亮海水不是黑幕)
	sky_mat.ground_bottom_color = Color(0.1, 0.32, 0.4)
	sky_mat.ground_horizon_color = Color(0.14, 0.42, 0.48)
	sky_mat.sky_energy_multiplier = 0.7
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 环境光: 取自天空 + 冷蓝, 让立绘背景与角色统一在深海调里.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.40, 0.58, 0.70)
	env.ambient_light_energy = 0.55   # ★与上面主光 1.55 是一对(A/B 实测 V3), 别单独改一个
	if OS.has_environment("TILEMAP"):    # 暗深海夜: 天空/环境光压暗成深夜(#0a0e1a深底) ★与上面那处同一套, 实测更差(见 _build_environment 开头的长注), 别常开
		sky_mat.sky_top_color = Color(0.020, 0.050, 0.110)
		sky_mat.sky_horizon_color = Color(0.030, 0.070, 0.140)
		sky_mat.ground_bottom_color = Color(0.010, 0.030, 0.080)
		sky_mat.ground_horizon_color = Color(0.030, 0.060, 0.120)
		sky_mat.sky_energy_multiplier = 0.35
		env.ambient_light_color = Color(0.10, 0.16, 0.26)
		env.ambient_light_energy = 0.45
	# 深海雾: 远处沉入蓝黑给纵深 (Compatibility 下 fog 为 per-pixel 简化雾, 仍能拉出远近层次).
	#   雾色压得很暗 (近背景色), 能量低 → 远处沉黑而非提亮成灰 (避免远地/边缘被雾刷亮成灰带).
	# ★2026-07-21 用户:「除了地板以外, 天空背景没有任何东西, 需要设计天空」。
	#   根因不是"没画天空", 而是【看不到天空】+【远处被雾吃光】:
	#     相机俯角约 51°(pos(0,28,22) look_at(0,0.6,0), fov40) → 画面上沿射线仍在水平线下方 31°,
	#     所以 ProceduralSky 的天空半球一个像素都进不了画面; 上方那条带其实是
	#     "地砖以外的远处地面", 而 fog_density=0.022 + 近黑雾色把它刷成了纯黑。
	#   对策: ①雾密度大幅下调并把雾色提到深海青(远处读作"水深"而不是"虚空")
	#         ②另加远景背景层 _build_far_backdrop()(渐变水幕 + 远礁剪影 + 光柱)
	# ★辉光(bloom): 水下场景的标配 —— 亮青的水与岸线泡沫会向周围渗出一点光晕,
	#   画面立刻从"平涂色块"变成"有介质的水体"。阈值调高 ⇒ 只有【最亮的那一档】发光
	#   (水/泡沫/技能特效), 暗地与立绘不受影响, 不会整体发糊。
	#   ★移动端与低画质关掉: glow 是全屏多次降采样, 是这套画面里最贵的一项。
	env.glow_enabled = not battle._is_mobile()
	env.glow_intensity = 0.26
	env.glow_strength = 0.95
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.105, 0.150)   # 提亮 + 偏青: 远处是海水不是黑洞
	env.fog_light_energy = 0.55
	env.fog_sun_scatter = 0.0
	env.fog_density = 0.008                            # 0.022 → 0.008: 远景能透出来
	# 色调 + 微调: filmic tonemap 给"正经游戏"质感, 略提对比/降饱和到冷调.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.96
	if OS.has_environment("BLACKMAP") or OS.has_environment("VFXISO"):   # 临时黑地图/纯特效隔离(验证VFX·弄完删env)
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0)
		env.glow_enabled = false
		env.fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.6)
		env.ambient_light_energy = 1.0
		env.adjustment_enabled = false
	# ★VFXLAB_GLOW=1: 黑场里把泛光开回来(桌面真机的同一套参数) —— 给用户【验收观看】用,
	#   让台子看到的 = 玩家看到的(2026-08-11 发现: 黑场关 bloom ⇒ 一直在比真机更"干"的环境验收)。
	#   ⚠ 默认不开: BLACKMAP 是染色法/差分量测的基线环境, 泛光会污染逐像素判定 —— 基线不能动。
	if OS.has_environment("VFXLAB_GLOW"):
		env.glow_enabled = true
	var we = WorldEnvironment.new()
	we.environment = env
	battle._world.add_child(we)

func _build_ground() -> void:
	if OS.has_environment("VFXISO"): return   # 纯特效隔离: 不建地面/装饰(只留特效对比参考·弄完删env)
	# 🔬 特效调试台(VFXLAB): 同样一张地图都不建 —— tile/装饰海草/远景/光柱/氛围粒子全跳过。
	# ★"关的方式要可靠"= 真的不建, 不是调暗/移出屏幕。上一轮把地图上的绿色海草
	#   误判成 091 的甲片, 根因就是场上有太多和特效同色同尺度的东西。
	#   台子自己会铺一张暗地板(battle_vfx_lab._build_dark_floor)当参照面。
	## ★★例外: `VFXLAB_REALMAP=1` 要**真实地图**(2026-09-03 加)。
	##   判断"预警区把地面纹理化"这类效果时黑场是错的场地 —— 参考里区内亮度只有 103%,
	##   靠的是纹理对比度 +46%; 黑场地面亮度 ~10, 同样叠加算出来 364%, 读成"一块板"。
	##   **黑场适合看"特效自己长什么样", 不适合看"特效与地面的关系"。**
	if OS.has_environment("VFXLAB") and not OS.has_environment("VFXLAB_REALMAP"): return
	# ★远景背景层("天空")在所有模式都建 —— 不像障碍物那样只在双路(用户 2026-07-21)
	if not OS.has_environment("MAPEDIT"):
		_build_far_backdrop(battle._world)
	# ★新地图: MultiMesh方块tile地面(暗深海夜色·数据驱动·用户2026-07-13定案·纯视觉不改玩法)
	## ★★2026-09-18 这里原来是 `if battle.MAP_V2 or TILEMAP or MAPEDIT: _build_tilemap_ground(); return`,
	##   后面还跟着 40 行旧 PlaneMesh 地面。而 `MAP_V2` 是 **const := true** ⇒ 条件恒真 ⇒
	##   那 40 行(连同 `_make_ground_material` 71 行、`_build_arena_ring`、`_make_arena_ring_texture`、
	##   `ARENA_RING_*`/`GROUND_NEAR`/`GROUND_FAR`/`CAUSTIC_SPEED`) **一行都跑不到**, 共 135 行已删。
	##   ★`tools/zero_caller_audit.py` 抓不到这个形状 —— 它们**每一个都有调用者**,
	##     链条是在顶上被一个恒真常量剪断的。为此加了第三道网 `const_branch`(见该文件)。
	##   ★别把 `if` 加回来: `MAP_V2=false 回退旧地面` 在旧地面删掉之后是**假话**,
	##     `TILEMAP` 对地面也早就是 no-op(它现在只剩 `_build_environment` 里的灯光/天空两处还在读)。
	_build_tilemap_ground()


# 屏幕暗角材质 (canvas_item shader): 按屏幕 UV 半径平滑压暗四角. 用 shader 算 → alpha/RGB 精确,
#   不像 GradientTexture2D 经 TextureRect 那样把透明区露成灰. center 全透, 0.65 半径外渐暗到角最暗.
# 建地图道具(布局B): 中央大礁+上下错位墙+两端基地穹顶围栏. 幂等(已建则跳过, 跨路复用同一张图).
func _build_map_props() -> void:
	if battle._world.has_node("MapProps"):
		battle._reset_domes()   # 障碍静态复用, 但每路重置基地围栏(恢复罩住)
		return
	var root = Node3D.new(); root.name = "MapProps"; battle._world.add_child(root)
	var c = battle._arena_center
	# ★rx/ry 必须贴合【视觉半宽】—— 用户 2026-07-21:「障碍物的生效范围比看起来的大很多」。
	#   battle._map_billboard 按【图高】归一到 h 米, 宽度按图比例被动决定, 所以视觉半宽是算得出来的:
	#     视觉半宽(游戏px) = 图宽 × (h / 图高) / battle.WS / 2
	#     reef_big  128×128, h=2.7 → 56.2 px   (旧 rx=168, 是视觉的 3.0 倍)
	#     reef_wall  96×72,  h=1.5 → 41.7 px   (旧 rx=104, 是视觉的 2.5 倍)
	#   再叠加 navmesh 的 battle.OBSTACLE_MARGIN, 旧值实际挡到 196px —— 单位离礁石老远就开始拐弯。
	#   现在取略大于视觉半宽(留一点手感余量), ry 按原来的长宽比例同步收。
	battle._obstacles = [
		{"c": c, "rx": 60.0, "ry": 36.0, "img": "reef_big", "h": 2.7},                 # 中央大礁(视觉半宽56)
		{"c": c + Vector2(-235.0, -198.0), "rx": 45.0, "ry": 20.0, "img": "reef_wall", "h": 1.5},  # 上墙(左偏·视觉半宽42)
		{"c": c + Vector2(235.0, 198.0), "rx": 45.0, "ry": 20.0, "img": "reef_wall", "h": 1.5},     # 下墙(右偏)
	]
	for ob in battle._obstacles:
		root.add_child(battle._map_billboard("res://assets/sprites/map/%s.png" % str(ob["img"]), ob["c"], float(ob["h"])))
	# 基地穹顶围栏(加性发光, 罩蛋) — 两端基地
	for pair in [["left", battle.ARENA.position.x + 70.0], ["right", battle.ARENA.end.x - 70.0]]:
		var dome = battle._map_billboard("res://assets/sprites/map/base_dome.png", Vector2(float(pair[1]), c.y), 3.0, true)
		dome.scale = Vector3(1.9, 1.9, 1.9)   # 罩大盖住蛋
		root.add_child(dome)
		battle._base_domes[str(pair[0])] = dome
	_build_decorations(root)   # 珊瑚/海草/礁石 铺边框住战场+填空地(纯装饰无footprint)
	_build_lightshafts(root)   # 水面光柱(加性发光, 深海氛围)
	_build_bubbles(root)       # 漂浮气泡颗粒

# 装饰景物: 珊瑚/海草/礁石 沿上下边框+四角+基地周围铺 (纯装饰, 无导航footprint, 不挡移动). 固定布局(可复现).
# 装饰景物: 珊瑚/海草/礁石 沿上下边框+四角+基地周围铺 (纯装饰, 无导航footprint, 不挡移动). 固定布局(可复现).
func _build_decorations(root: Node3D) -> void:
	var A = battle.ARENA
	var top: float = A.position.y + 46.0
	var bot: float = A.end.y - 40.0
	var cx: float = battle._arena_center.x
	var decos = [
		[A.position.x+190, top+8, "deco_kelp", 2.4, 1.0], [A.position.x+430, top+34, "deco_coral_pink", 1.9, 1.1],
		[cx-300, top, "deco_rocks", 1.2, 1.0], [cx-40, top+22, "deco_coral_orange", 1.7, 1.0],
		[cx+300, top, "deco_kelp", 2.2, 0.9], [A.end.x-430, top+30, "deco_coral_pink", 1.8, 1.0], [A.end.x-190, top+6, "deco_rocks", 1.3, 1.1],
		[A.position.x+320, bot, "deco_coral_orange", 1.8, 1.15], [cx-380, bot-12, "deco_rocks", 1.2, 1.0],
		[cx-70, bot, "deco_kelp", 2.3, 1.0], [cx+300, bot-16, "deco_coral_pink", 1.9, 1.0], [A.end.x-350, bot, "deco_kelp", 2.2, 0.95],
		[A.position.x+165, battle._arena_center.y-165, "deco_coral_orange", 1.5, 0.9], [A.position.x+165, battle._arena_center.y+165, "deco_coral_pink", 1.6, 0.9],
		[A.end.x-165, battle._arena_center.y-165, "deco_coral_pink", 1.6, 0.9], [A.end.x-165, battle._arena_center.y+165, "deco_coral_orange", 1.5, 0.9],
	]
	var drng = RandomNumberGenerator.new(); drng.seed = 20260723   # ★点2: 给固定装饰加随机镜像/抖动破重复
	for de in decos:
		var spr = battle._map_billboard("res://assets/sprites/map/%s.png" % str(de[2]), Vector2(float(de[0]), float(de[1])), float(de[3]))
		var sc: float = float(de[4])
		spr.scale = Vector3(sc * (-1.0 if drng.randf() < 0.5 else 1.0), sc, sc)   # ★随机水平镜像(点2)
		var _b: float = drng.randf_range(0.86, 1.0)   # ★明暗抖动(点2: 原死值Color(0.92,0.96,1.0)→全同)
		spr.modulate = Color(0.92 * _b + drng.randf_range(-0.04, 0.04), 0.96 * _b, 1.0 * _b)
		root.add_child(spr)

# 水面光柱: 几道加性发光的柔和光束(billboard竖条), 打进深海竞技场 → 氛围/纵深.
## ═══ 远景背景层(「天空」) ═══ 用户 2026-07-21:「天空背景没有任何东西, 需要设计天空」
##
## 相机俯角约 51°, 地平线【永远不在画面里】, 所以真正要填的不是天空半球, 而是
## 画面上沿那片「地砖以外的远处」。这里造三层, 由远及近:
##   ①渐变水幕: 一面大幕布, 上浅下深(越靠上越接近水面透光) —— 给纵深底色, 取代原来的纯黑
##   ②远礁剪影: 一排压暗的礁石轮廓, 高低错落 —— 让远处有"地形"而不是一块平色
##   ③水面光柱: 复用已有的 _build_lightshafts 手法, 从上方斜射
## 全部 unshaded + 关阴影, 不参与光照计算(纯背景, 不该被战场光影影响)。
func _build_far_backdrop(root: Node3D) -> void:
	var holder = Node3D.new()
	holder.name = "FarBackdrop"
	root.add_child(holder)

	# ★2026-07-22: 旧的"渐变海床平面"(150×16 的平 PlaneMesh @ z=-22)已删 ——
	#   它只铺 z∈[-30,-14], 最坏机位要看到 z=-42.2 → 上方 15% 纯黑。
	#   现由 _build_far_terrain() 的真地形网格(200×120m)统一承担, 两层并存会打架。

	# ── ②远景地形: 三层纵深 ────────────────────────────────────
	# ★可见高度是随距离变的(算过): 画面上沿射线 y_top = 28 - 0.606×(22-z)
	#     z=-15 → 5.6m   z=-18 → 3.8m   z=-21 → 1.9m   z=-24 → 0.1m
	#   所以【越近的层能放越高的东西】。第一版所有剪影都压到 1.8~3.6m 摆在同一深度带,
	#   看着就是零散几块、没有纵深(用户 2026-07-21:「太弱了」)。改成三层, 由近及远:
	#     近层 高而清晰 → 中层 → 远层 矮而淡, 叠出天际线。
	# ★2026-07-21 第二版(用户:「你直接这样贴一个图也不太行」)。
	#   第一版是【把前景那几张礁石精灵随机撒到远处再调暗】—— 撒出来的是"更多装饰",
	#   不是地貌: 没有连续的山脊线、没有落差, 每块之间都是空的, 所以读作贴图。
	#   改成【程序生成的连续山脊剪影】: 一条通宽的锯齿轮廓, 三层由近及远叠出天际线。
	# ★俯视下【越远的东西在屏幕上越高】, 所以由远及近 = 由上往下堆。
	#   可见高度上限 y_top = 28 - 0.606×(22-z): z=-17.5→4.0m  z=-20→2.5m  z=-22.4→1.1m。
	#   第二版曾把最近一层做到 4.6m ≈ 顶满整条可见带 → 就是一整块大色斑, 后两层被它全挡住。
	#   现在每层只占各自上限的一半左右, 才叠得出天际线。
	# ★颜色必须【贴着背景水色】只差一点 —— 远景是雾里的地貌不是剪纸。
	#   第二版用 (0.30,0.52,0.66) 比背景亮一大截, 就成了一块亮青色卡纸。
	# ★颜色第三版: 前一版把山脊做成【比背景暗】的剪影 → 实测在 y≈32~50 压出一条纯黑带
	#   (#00101E/#000410, 采样见下面渐变面的注释)。filmic tonemap 把暗部再吃一半, 暗剪影必然糊成黑。
	#   水下远景地貌是【雾里的亮轮廓】(同雾中远山), 越远越亮越贴雾色 —— 按这个来。
	# ★2026-07-22 第三版(用户「感觉你还是在贴一个墙就完事？」):
	#   前两版的"山脊"是 billboard=DISABLED 的 Sprite3D —— 字面意义上的【三面立着的平板】。
	#   固定机位能糊弄, 一动镜头就散架。实拍证明: 缩小0.72+平移9m 时画面上方 15% 是纯黑,
	#   因为远景海床只铺到 z=-30 而最坏机位要看到 z=-42.2(差 12.2 米)。
	#   现在改成【一张真地形网格】: 有真实高低与透视, 平移缩放都不穿帮。
	_build_far_terrain(holder)
	_build_backdrop_thicket(holder)     # ★②a 密集竖直剪影带(2026-09-18, 见该函数长注)

	# ── ②b 远景发光群(珊瑚/海葵/海带) ──────────────────────────
	# 剪影只有轮廓没有"生气"。加一层加性发光的小点缀, 让远处天际线有光斑闪烁感,
	# 这也是深海题材最能出氛围的一笔。
	var glows = ["glow-coral", "glow-anem", "glow-kelp"]
	var grng = RandomNumberGenerator.new()
	grng.seed = 20260722
	for i in range(14):   # ★远景发光 22→14(点2: 减重复的发光刷屏)
		var gp = "res://assets/sprites/map/%s.png" % glows[i % glows.size()]
		if not ResourceLoader.exists(gp):
			continue
		var gtex: Texture2D = load(gp)
		var gs = Sprite3D.new()
		gs.texture = gtex
		gs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		gs.shaded = false
		gs.transparent = true
		var gm = StandardMaterial3D.new()
		gm.albedo_texture = gtex        # ★★必须给覆盖材质设贴图!
		# material_override 会【整个替换】Sprite3D 自己的材质, 不设 albedo_texture
		# 就渲染成一块【纯白方块】—— 我在这和远景光柱上连犯两次, 都是截图才看出来
		# (用户 2026-07-21 看到顶部一排白方块)。现有的 _build_lightshafts 是对的, 可对照。
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD      # 加性=发光
		gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		gm.disable_fog = true
		gs.material_override = gm
		var gsc = grng.randf_range(0.7, 1.7)
		gs.pixel_size = gsc / float(maxi(1, gtex.get_height()))
		var gd = grng.randf()
		# 冷青→蓝紫 随机, 远的更淡
		var gcol = Color(0.35, 0.95, 1.00).lerp(Color(0.62, 0.45, 1.00), grng.randf())
		gcol.a = 0.50 - gd * 0.22
		gs.modulate = gcol
		gs.position = Vector3(grng.randf_range(-29.0, 29.0), gsc * 0.45 + 0.15, -16.0 - gd * 6.8)
		gs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(gs)

	# ── ③远景水面光柱 ─────────────────────────────────────────
	# ★注: 第一次加这个渲染成了几根"死白竖条", 我当时以为是可见带太窄、把它删了 —— 判断错了。
	#   真因是【material_override 没设 albedo_texture】(见上), 修好后光柱是正常的。
	#   教训: 看到渲染异常先查材质/贴图有没有接上, 别急着归因于"角度/尺寸不合适"。
	var stex = VfxTex._make_lightshaft_texture()
	for i in range(6):
		var sh = Sprite3D.new()
		sh.texture = stex
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.shaded = false
		sh.transparent = true
		var sm = StandardMaterial3D.new()
		sm.albedo_texture = stex        # ★同上, 不能漏
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		sm.disable_fog = true
		sh.material_override = sm
		sh.pixel_size = 0.030
		sh.modulate = Color(0.42, 0.80, 1.0, 0.22)
		sh.position = Vector3(-26.0 + float(i) * 10.5, 1.6, -18.5)
		# ★2026-07-21 第二版: 原来 billboard=ENABLED 且不带倾角 → 渲染成一排【笔直的竖白条打在地板上】,
		#   像聚光灯不像水下光柱。真实的丁达尔光是从【水面斜射下来】的。
		#   billboard 关掉才能转; 远景本来就正对相机(相机在 +z 看向 -z), 不转也朝向对。
		sh.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		sh.rotation_degrees = Vector3(0.0, 0.0, 11.0 if (i % 2 == 0) else -8.0)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(sh)

	# ── ④鱼群 + ⑤气泡柱: 背景"活起来"的关键 ────────────────────
	# ★这才是第一版最大的漏 —— 整条远景带零动态。前景在打架、背景一动不动,
	#   再多装饰也读作"贴了张图"(用户 2026-07-21)。
	_build_far_fish(holder)
	_build_far_bubbles(holder)


## 程序生成一条山脊剪影贴图: 通宽锯齿轮廓, 下方实心上方透明, 顶沿带一道亮边(轮廓可读).
##   ★不用美术图 —— 现有礁石精灵是【前景尺度】的, 拉到远处会因细节密度不对而"读不出距离"。
# ----------------------------------------------------------------------------
#  §FARTERRAIN — 远景真地形 (2026-07-22 第三版)
#
#  ★为什么必须是真网格而不是平板精灵:
#    前两版用 billboard=DISABLED 的 Sprite3D 当"山脊" = 三面立着的平板。
#    固定机位看着还行, 一动镜头(用户刚要的平移/缩放)立刻散架 —— 没有视差、没有厚度、边会走完。
#    实拍(CAMPROBE 探针驱到极限)证明: 缩小0.72 + 平移9m 时画面上方 15% 是【纯黑】。
#
#  ★尺寸是算出来的不是拍脑袋: 最坏机位(缩小0.72+后移9m)画面上沿射线打到地面在 z=-42.2,
#    横向 x∈[-34.5, 52.5]。所以铺 200×120 米(z∈[-90,+30], x∈±100)带足余量。
#
#  ★战场范围内必须【严格平坦】: 场上有 40+ 贴地特效画在 y=0(裂地/毒圈/冲击环…),
#    地形一旦在那里起伏就会穿模。所以起伏量按到战场中心的距离做 smoothstep 淡入,
#    近处恒为 0。
# ----------------------------------------------------------------------------

## ═══ 远景【密集竖直剪影带】(2026-09-18 · 用户「咩咩启示录是个很好的场景参考」) ═══
##
## ★由来: 用户看过 v0.19.407 后说「还是不能细看」, 并问「岛以外的部分怎么搞, 背景怎么做」。
##   去把咩咩启示录的官方发售预告抽了 **167 帧**逐帧看(docs/studies/20260918-咩咩启示录场景与特效逐帧.md),
##   量出来的结论只有一条最关键:
##     **全片 167 帧里没有任何一帧是「场地 + 纯黑虚空」。**
##     外面要么是密集竖直剪影(帧 153-158)、要么是建筑(帧 16)、要么地形直接铺满出画(帧 1-5/43-44/73-82)。
##
## ★照着量出来的做(帧 155 做过 1:1 逐像素测量):
##   · 背景是**密集的竖直元素一层层往后叠**(石柱/树干), 不是稀疏几个剪影
##   · 参差**交给素材**不交给几何 —— 本素材实测逐列顶端参差 **59 px**
##   · 高饱和色极少: 参考里红烛只占全画面 **0.99%**(14 个离散块)
##
## ★为什么是"加一层"而不是改 `_build_far_terrain`: 那条路已经被用户否过三次
##   (「太弱了」/「你直接这样贴一个图也不太行」/「感觉你还是在贴一个墙就完事？」),
##   它现在是一张真地形网格、负责**天际线轮廓**。本层负责的是**中近景的密度**, 两件事。
##
## ★三层由近及远, 越远越矮越淡 —— 可见高度上限是算得出来的(见上方 _build_far_backdrop 的注):
##   y_top = 28 - 0.606×(22-z) ⇒ z=-16 → 4.97m / z=-19 → 3.15m / z=-22 → 1.33m。
##   每层只占各自上限的一半左右, 才叠得出纵深(顶满就是一整块色斑, 后层全被挡住)。
const BACKDROP_THICKET := "res://assets/sprites/map/backdrop-kelpband.png"

func _build_backdrop_thicket(holder: Node3D) -> void:
	var tex: Texture2D = load(BACKDROP_THICKET) if ResourceLoader.exists(BACKDROP_THICKET) else null
	if tex == null:
		push_warning("[backdrop] 剪影带贴图缺失: %s —— 不画(不做静默兜底)" % BACKDROP_THICKET)
		return
	var th: int = maxi(1, tex.get_height())
	## z / 世界高(米) / 颜色 —— 越远越淡越贴雾色(★不是"越远越暗": 水下远景是雾里的亮轮廓,
	##   做成暗剪影会被 filmic tonemap 再吃一半、糊成一条纯黑带, 这是本文件上方记过的老坑)。
	## ★铺多宽是【算出来的】不是估的: 相机在 (0,28,22)、fov 40(竖直)、16:9。
	##   到 z 层的距离 d = hypot(28, 22-z); 可见竖向 = 2·d·tan(20°); 可见横向 = 竖向 × 16/9。
	##     z=-16 → d=47.2 → 竖 34.4m → **横 61.1m**
	##     z=-19 → d=50.0 → 竖 36.4m → **横 64.7m**
	##     z=-22 → d=52.8 → 竖 38.4m → **横 68.3m**
	##   ★第一版每层只铺 5~7 张(约 31m), 实拍只盖住画面上方中间一小段、两侧仍是空的。
	##   现在按上面的横向可见宽 + 20% 余量算张数(镜头还能缩放/平移)。
	var layers := [
		{"z": -16.0, "h": 2.5, "col": Color(0.20, 0.30, 0.44), "span": 73.0},
		{"z": -19.0, "h": 1.7, "col": Color(0.24, 0.35, 0.48), "span": 78.0},
		{"z": -22.0, "h": 0.9, "col": Color(0.28, 0.40, 0.52), "span": 82.0},
	]
	for L in layers:
		var zz: float = float(L["z"])
		var hh: float = float(L["h"])
		var w_m: float = hh * (float(tex.get_width()) / float(th))   # 按图比例定宽
		var cnt: int = maxi(3, int(ceil(float(L["span"]) / maxf(0.01, w_m * 0.92))))
		for i in range(cnt):
			var s := Sprite3D.new()
			s.name = "Thicket_%d_%d" % [int(-zz), i]
			s.texture = tex
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 远景是背景板, 不该跟着镜头转
			s.shaded = false
			s.transparent = true
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD      # 剪影边缘不要半透拖尾
			s.pixel_size = hh / float(th)
			s.modulate = L["col"]
			## 相邻两张各偏半张宽, 拼成通宽的一条; 左右各多铺一张防镜头缩放时露边
			var x: float = (float(i) - float(cnt - 1) * 0.5) * w_m * 0.92
			s.position = Vector3(x, hh * 0.5 - 0.15, zz)
			if i % 2 == 1:
				s.scale = Vector3(-1.0, 1.0, 1.0)              # 隔一张镜像, 破"同一个印章"
			holder.add_child(s)

func _build_far_terrain(holder: Node3D) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half = battle.FAR_TERRAIN_SIZE * 0.5
	var seg = battle.FAR_TERRAIN_SEG
	var stepx = battle.FAR_TERRAIN_SIZE.x / float(seg.x)
	var stepz = battle.FAR_TERRAIN_SIZE.y / float(seg.y)
	# 顶点色做大气透视: 越远越亮越贴雾色(水下远景是雾里的亮轮廓, 同雾中远山)。
	#   第二版把山脊做成"比背景暗的剪影"→ 在 y≈32~50 压出一条纯黑带(filmic tonemap 把暗部再吃一半)。
	var near_col = Color(0.070, 0.125, 0.190)
	var far_col = Color(0.205, 0.455, 0.520)
	for iz in range(seg.y):
		for ix in range(seg.x):
			var x0 = -half.x + float(ix) * stepx
			var x1 = x0 + stepx
			# ★中心 z=-30 → 覆盖 z∈[-90,+30]。
			#   第一版把偏移写成 +SIZE.y*0.5-30 = +30, 结果铺成了 z∈[-30,+90] —— 整片地形在【相机身后】,
			#   远处一点没铺, 于是上方仍是纯黑(四机位验收里 panup 黑占比 38%)。符号错, 不是参数不对。
			var z0 = -half.y + float(iz) * stepz + battle.FAR_TERRAIN_CENTER_Z
			var z1 = z0 + stepz
			var quad = [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
			# 两个三角形 (0,1,2) (0,2,3)
			for tri in [[0, 2, 1], [0, 3, 2]]:
				for k in tri:
					var q: Vector2 = quad[k]
					var y = battle._far_terrain_height(q.x, q.y)
					# 越远(z 越负)越贴雾色; 同时高处略提亮 → 山脊顶自然亮一点
					var t: float = clampf((-q.y - 12.0) / 34.0, 0.0, 1.0)
					var c = near_col.lerp(far_col, pow(t, 0.72))
					c = c.lightened(clampf(y * 0.06, 0.0, 0.16))
					st.set_color(c)
					st.add_vertex(Vector3(q.x, y - 0.05, q.y))
	st.generate_normals()
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 与其余远景一致, 不吃主光
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = false   # ★这次【要】吃雾: 地平线交给雾去化, 才没有几何硬边
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


func _build_far_fish(holder: Node3D) -> void:
	var ftex = battle._make_fish_texture()
	var rng = RandomNumberGenerator.new()
	rng.seed = 20260723                       # 确定性: 每局一致
	var span = 84.0                          # 横向行程 (比可见宽度大, 出画外才回卷)
	for s in range(5):                        # 5 群
		var school = Node3D.new()
		holder.add_child(school)
		var zz: float = rng.randf_range(-17.0, -22.5)
		var depth: float = inverse_lerp(-17.0, -22.5, zz)        # 0=近 1=远
		var yy: float = rng.randf_range(0.6, 2.0) * (1.0 - depth * 0.45)
		var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
		# 尺寸/亮度: 40m 外 0.32m 高只有 6px, 太小认不出是鱼 —— 放大到 10~18px 这一档
		var scl: float = rng.randf_range(0.55, 0.95) * (1.0 - depth * 0.35)
		# ★要比背景水色【亮】才看得见(背景实测 #0D3349 ~ (0.05,0.20,0.28));
		#   暗鱼在 filmic tonemap 下会直接糊进背景, 同山脊那次的坑
		var col = Color(0.46, 0.72, 0.86).lerp(Color(0.30, 0.50, 0.66), depth)
		var n = rng.randi_range(5, 9)
		for i in range(n):
			var fs = Sprite3D.new()
			fs.texture = ftex
			fs.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			fs.shaded = false
			fs.transparent = true
			fs.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			fs.pixel_size = scl / float(ftex.get_height())
			fs.modulate = col
			# 群内错位: 不要排成一条直线
			fs.position = Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(-0.5, 0.5),
								  rng.randf_range(-0.5, 0.5))
			fs.scale.x = -1.0 if dir < 0.0 else 1.0   # 朝向跟着游动方向(贴图默认朝右)
			fs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			school.add_child(fs)
		var x0: float = -span * 0.5 * dir + rng.randf_range(-14.0, 14.0)
		school.position = Vector3(x0, yy, zz)
		var dur: float = span / rng.randf_range(1.4, 2.6)         # 远的慢 → 视差
		var tw = battle._reg_tween().bind_node(school).set_loops()
		tw.tween_property(school, "position:x", x0 + span * dir, dur)
		tw.tween_callback(func() -> void:
			if is_instance_valid(school):
				school.position.x = x0)
		# ★随机初相位: 不给的话所有群都从行程起点(画面外 ±42)出发, 而那个深度可见范围只有 ±30,
		#   单圈 32~60 秒 —— 开局几十秒内一条鱼都看不到(第一次就是这么"做了等于没做")。
		tw.custom_step(rng.randf() * dur)


## 远景气泡柱: 几处海床喷口不断冒泡上升, 给"水体"以垂直方向的动.
##   可见高度有限(z≈-19 处约 3.8m), 所以升到 ~2.6m 就淡出, 不做更高。
func _build_far_bubbles(holder: Node3D) -> void:
	var btex = VfxTex._make_lightshaft_texture()   # 复用: 上下渐隐的软条, 缩到很小就是一颗软光点
	var rng = RandomNumberGenerator.new()
	rng.seed = 20260724
	for v in range(3):                              # 3 处喷口
		var vx: float = rng.randf_range(-24.0, 24.0)
		var vz: float = rng.randf_range(-17.5, -21.0)
		for i in range(7):                          # 每口 7 颗, 用延迟错开成一串
			var bs = Sprite3D.new()
			bs.texture = btex
			bs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bs.shaded = false
			bs.transparent = true
			var bm = StandardMaterial3D.new()
			bm.albedo_texture = btex          # ★material_override 必须设贴图, 否则渲成纯白方块(本文件踩过两次)
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			bm.disable_fog = true
			bs.material_override = bm
			var bsc: float = rng.randf_range(0.10, 0.22)
			bs.pixel_size = bsc / float(btex.get_height())
			bs.modulate = Color(0.55, 0.88, 1.0, 0.34)
			bs.position = Vector3(vx + rng.randf_range(-0.5, 0.5), 0.05, vz)
			bs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(bs)
			var rise: float = rng.randf_range(2.0, 2.7)
			var dur: float = rng.randf_range(3.2, 5.0)
			var tw = battle._reg_tween().bind_node(bs).set_loops()
			tw.tween_interval(float(i) * dur / 7.0)          # 同口内错峰 → 连成一串而不是齐射
			tw.tween_property(bs, "position:y", rise, dur)
			tw.parallel().tween_property(bs, "modulate:a", 0.0, dur).set_delay(dur * 0.55)
			tw.tween_callback(func() -> void:
				if is_instance_valid(bs):
					bs.position.y = 0.05
					bs.modulate.a = 0.34)


func _build_lightshafts(root: Node3D) -> void:
	var tex = VfxTex._make_lightshaft_texture()
	var cx: float = battle._arena_center.x
	var shafts = [[cx-520.0, 0.26], [cx-150.0, 0.34], [cx+250.0, 0.24], [cx+560.0, 0.3]]
	for sh in shafts:
		var spr = Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = tex
		spr.material_override = m
		spr.pixel_size = 9.0 / float(tex.get_height())   # 光柱高 ≈9米
		spr.modulate = Color(1, 1, 1, float(sh[1]))
		spr.position = battle._world_pos(Vector2(float(sh[0]), battle._arena_center.y), 4.2)
		root.add_child(spr)


# 漂浮气泡颗粒: CPUParticles3D 缓缓上升的小圆点, 满场飘 → 深海有生气.
# 漂浮气泡颗粒: CPUParticles3D 缓缓上升的小圆点, 满场飘 → 深海有生气.
func _build_bubbles(root: Node3D) -> void:
	var p = CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(battle.ARENA.size.x * battle.WS * 0.5, 0.3, battle.ARENA.size.y * battle.WS * 0.5)
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0, 0.28, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.55
	p.scale_amount_min = 0.018
	p.scale_amount_max = 0.05
	var bm = StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX   # 普通alpha混合(非加性实心球)→ 真气泡(透明+亮环+高光点)
	bm.albedo_texture = VfxTex._make_bubble_texture()
	bm.albedo_color = Color(1, 1, 1, 0.55)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm = QuadMesh.new(); qm.size = Vector2(1.0, 1.0)
	p.mesh = qm
	p.material_override = bm
	p.position = battle._world_pos(battle._arena_center, 0.2)
	root.add_child(p)


# 每路重置基地围栏(恢复显示+满尺寸) — 障碍复用但围栏每路重新罩住.
# 建 2D navmesh: 外边界=ARENA内缩(单位半径), 挖洞=障碍footprint+margin. 幂等. 只挡移动.
func _build_navmesh() -> void:
	if battle._nav_ready:
		return
	if battle._obstacles.is_empty():
		return
	_free_nav_rids()          # 防御: 万一被重复调用(现在有 _nav_ready 幂等守卫), 先放掉上一份再建
	battle._nav_map = NavigationServer2D.map_create()
	_own_nav_map = battle._nav_map          # ★本地留一份: PREDELETE 时 battle 可能已失效
	NavigationServer2D.map_set_cell_size(battle._nav_map, 1.0)
	NavigationServer2D.map_set_active(battle._nav_map, true)
	battle._nav_region = NavigationServer2D.region_create()
	_own_nav_region = battle._nav_region
	NavigationServer2D.region_set_map(battle._nav_region, battle._nav_map)
	NavigationServer2D.region_set_enabled(battle._nav_region, true)
	var poly = NavigationPolygon.new()
	poly.cell_size = 1.0
	var src = NavigationMeshSourceGeometryData2D.new()
	var m: float = 24.0   # 边界内缩(单位半径), 别贴墙
	src.add_traversable_outline(PackedVector2Array([
		battle.ARENA.position + Vector2(m, m),
		Vector2(battle.ARENA.end.x - m, battle.ARENA.position.y + m),
		battle.ARENA.end - Vector2(m, m),
		Vector2(battle.ARENA.position.x + m, battle.ARENA.end.y - m),
	]))
	for ob in battle._obstacles:   # 障碍挖洞: footprint椭圆 + 单位半径margin(留出绕行间隙)
		src.add_obstruction_outline(battle._ellipse_pts(ob["c"], float(ob["rx"]) + battle.OBSTACLE_MARGIN, float(ob["ry"]) + battle.OBSTACLE_MARGIN, 14))
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	NavigationServer2D.region_set_navigation_polygon(battle._nav_region, poly)
	NavigationServer2D.map_force_update(battle._nav_map)
	battle._nav_ready = true

# 返回单位朝目标该走的方向: 有navmesh→沿路点绕障; 否则/无路径→直奔(straight). 路径每单位缓存~0.4s.
