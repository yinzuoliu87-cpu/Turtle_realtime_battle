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
## 这个地块类型该用什么颜色 —— **主题优先, 没给就用那套已批准的 `TILE_COLS`**。
##
## ★★★2026-10-03 为什么是"覆盖"而不是"替换": `TILE_COLS` 是**用户 2026-09-20 拍过板的**
##   (「别被深海局限住了」→「你自己定」, 三套候选实拍量过取 A 暖石台),
##   而且 `tests/verify_ground_palette.gd` 把它和设计文档 §4 那张表**焊在一起**。
##   四版主题是**加法**: 不覆盖就还是那套批准过的; 用户选中哪一版, 再把那版扶正成 `TILE_COLS` + 改文档。
##   ⇒ 任何一版都不会**悄悄**改掉一个已拍板的决定(memory `fb-pin-user-words-dont-drift`)。
##
## ★水(ti==1)不走这里 —— 它由 `ground_water.gdshader` 自己的颜色参数管, 见下方 `apply_theme_water`。
static func theme_tile_col(ti: int) -> Color:
	var c: Dictionary = ArenaTheme.cfg()
	match ti:
		0: return c.get("ground_col", TILE_COLS.get(0, Color(0.2, 0.2, 0.2)))
		2: return c.get("stone_col", TILE_COLS.get(2, Color(0.2, 0.2, 0.2)))
		## ★★sand 必须走 `shore_col` 不是 `ground_col`。第一版映射错了, 于是 base 下
		##   沙地被画成草色 —— `verify_tile_texture ④`「TILE_COLS 是锁死的」当场抓住。
		##   ★那条判据救了一次: 它比的是**产品材质的 base_col == TILE_COLS**, 所以
		##   任何"悄悄换掉已锁死调色板"的改动都会红, 哪怕画面统计判据全绿。
		3: return c.get("shore_col", TILE_COLS.get(3, Color(0.2, 0.2, 0.2)))
	return TILE_COLS.get(ti, Color(0.2, 0.2, 0.2))


static func tile_material(ti: int, ws: float, cx: float, cy: float) -> Material:
	var f: Dictionary = MapField.get_field(MAP_PATH, ws, cx, cy, bool(ArenaTheme.cfg().get("outer_sea", false)))
	var sm := ShaderMaterial.new()
	sm.shader = SH_WATER if ti == 1 else SH_LAND
	sm.set_shader_parameter("detail_tex", tile_detail_tex(ti))
	if ti != 1:
		sm.set_shader_parameter("base_col", theme_tile_col(ti))
		## ★聚光强度按主题(`base` 不给 ⇒ shader 默认 0.18 = 原值, 逐值不变)。
		var _ed = ArenaTheme.cfg().get("edge_dark", null)
		if _ed != null:
			sm.set_shader_parameter("edge_dark", float(_ed))
		## ★焦散按主题(base 不给 ⇒ shader 默认值逐值不变)。暗林=0(林地无水波光), 深礁=整片铺满。
		if ArenaTheme.cfg().has("spot_amt"):
			var _A: Rect2 = RealtimeBattle3DScene.ARENA
			var _ac: Vector2 = _A.position + _A.size * 0.5
			sm.set_shader_parameter("spot_c", Vector2((_ac.x - cx) * ws, (_ac.y - cy) * ws))
			sm.set_shader_parameter("spot_half", _A.size * 0.5 * ws)
		## ★主题地面纹理(detail_tex/detail_scale): 参考地面是手绘的草/泥笔触, 不是程序砖纹。base 不给 ⇒ 原砖纹。
		var _dt: String = str(ArenaTheme.cfg().get("detail_tex", ""))
		if _dt != "" and ResourceLoader.exists("res://assets/sprites/map/themes/%s.png" % _dt):
			sm.set_shader_parameter("detail_tex", load("res://assets/sprites/map/themes/%s.png" % _dt))
			sm.set_shader_parameter("tex_scale", float(ArenaTheme.cfg().get("detail_scale", 0.32)))
		## ★岸线切角色: shader 默认是 base 的青色浅水; 主题的海是暗色 ⇒ 不改就在岸边留一圈青色细边(实拍放大照出来的)。
		if ArenaTheme.cfg().has("water_col"):
			sm.set_shader_parameter("shore_water_col", ArenaTheme.cfg()["water_col"])
		for _k in ["caustic_amt", "caustic_far", "caustic_col", "caustic_scale", "detail_amt", "sed_amt", "caustic_web", "edge_soft", "spot_amt", "smooth_shade"]:
			var _v = ArenaTheme.cfg().get(_k, null)
			if _v != null:
				sm.set_shader_parameter(_k, _v)
	else:
		## ★水也按主题走。四色**同源于一个 `water_col`**: 浅/深/浪尖/泡沫各自从它推出来,
		##   而不是每版手填四个色 —— 手填四份必然有一份忘了改(memory `fb-hand-rolled-copies-drift`)。
		## ★判据 `verify_arena_themes` ④ 焊死「海必须比陆暗」, 所以这里只许往暗里推。
		var wc: Color = ArenaTheme.cfg().get("water_col", Color(0.122, 0.722, 0.769))
		sm.set_shader_parameter("shallow_col", wc)
		sm.set_shader_parameter("deep_col", wc.darkened(0.42))
		## ★主题: 浪尖/泡沫/岸线切角/细节纹也必须跟着主题走。原来只换了水体色,
		##   这三样还是默认的青白 ⇒ 四版的黑海在岸边拐角下面泛出一团青白光、海面散着蓝紫小点(实拍放大照出)。
		if ArenaTheme.cfg().has("water_col"):
			sm.set_shader_parameter("crest_col", wc.lightened(0.10))
			sm.set_shader_parameter("foam_col", wc.lightened(0.18))
			sm.set_shader_parameter("shore_land_col", ArenaTheme.cfg().get("wall_col", wc))
			sm.set_shader_parameter("detail_amt", 0.0)
			sm.set_shader_parameter("caustic_amt", 0.0)
		## ⛔ 这里试过「浪尖/泡沫映天色」(物理上对: 水反射环境), 动机是**凑有效色数**。
		##   实测 81 → 78, **反而更低** —— 浪尖与泡沫只出现在很小的面积上, 而判据数的是
		##   占到 0.1% 面积以上的颜色。⇒ 撤回, 保持从 water_col 同源推出。
		##   ★★更要紧的是那次测量把**整个方向**推翻了: 拿同一把尺子量咩咩自己的暗地牢
		##   (raw_01) = **79 色 / 中间调 16.5%**, **低于**我们门禁的 88 / 24%。
		##   那两个阈值是拿一张**亮场**截图标定的(表里 174/59.7% ≈ raw_04 的 175/56.9%),
		##   暗场景本来就达不到。我差点为了凑这个数把调色板一路改坏
		##   (memory `fb-calibrate-the-ruler-before-trusting-it`)。
		## ★2026-10-05 镜头可达范围: 主题的格子海不再往板沿压到近黑, 与外海(ArenaOuter)同色接上。base 不给 ⇒ 0.18 原值。
		if ArenaTheme.cfg().has("sea_edge_floor"):
			sm.set_shader_parameter("edge_floor", float(ArenaTheme.cfg()["sea_edge_floor"]))
		if ArenaTheme.cfg().has("sea_crest_deep"):
			sm.set_shader_parameter("crest_deep", float(ArenaTheme.cfg()["sea_crest_deep"]))
		if ArenaTheme.cfg().has("sea_wave_style"):
			sm.set_shader_parameter("wave_style", int(ArenaTheme.cfg()["sea_wave_style"]))
		sm.set_shader_parameter("crest_col", wc.lightened(0.55))
		sm.set_shader_parameter("foam_col", wc.lightened(0.82))
		sm.set_shader_parameter("shore_land_col", theme_tile_col(0).darkened(0.18))
	if not f.is_empty():
		sm.set_shader_parameter("map_field", f["tex"])
		sm.set_shader_parameter("map_org", f["org"])
		sm.set_shader_parameter("map_size", f["size"])
		sm.set_shader_parameter("field_r", MapField.FIELD_R)
	else:
		push_warning("[tile] 地图距离场烘不出来 → 岸线/水深退化成平涂")
	# ★焦散与沉积起伏(shader `rich_fx`, 默认 true)常开。原来低画质会关掉它; 2026-10-07 画质设置整个删了
	#   (桌面 A/B/A 背对背实测差值在噪声内: 开179.5 关179.6 再开179.6)。uniform 留着当低端机的安全阀。
	return sm


var battle

## 火源登记(主题氛围粒子用): 场内灯 / 周边光点 / 吊灯的精灵。火星**只从这些灯具身上冒**,
## 不满场撒 —— 粒子要有因(方案书 §4.5-2)。读它的是 `_build_theme_ambient`。
var _flames: Array = []

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
	container.add_child(battle._sub)
	battle._world = Node3D.new()
	battle._world.name = "World"
	battle._sub.add_child(battle._world)

# ═══ 新地图 tile 系统 (MultiMesh 方块地面 · 数据驱动 map.json · 纯视觉不改玩法) ═══
# 5类型: 0 grass主地面 / 1 water水凹 / 2 stone石台凸 / 3 sand浅滩 / 4 void空(不渲染)
func _build_tilemap_ground() -> void:
	## ★2026-10-05 外海铺到镜头看得见的最远处(主题才有; 用户「镜头是可以移动缩放的啊，有一堆问题啊」)。
	ArenaOuter.build_outer_sea(battle)
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
## 海岸线的边界段 —— 【陆地格 ↔ 非陆地格】那条界, 不是「非虚空 ↔ 虚空」。
##
## ★★★2026-10-03 用户:「要么中间就是可活动的陆地，外边为海，以此为边界」「**墙移到海岸线吧**」
##
## 【改前跟的是哪条界】`非void ↔ void` —— 也就是「所有渲染出来的东西」的最外沿。
##   在改前那张图上(岛心→潟湖→浅滩→虚空)那条界画在**浅滩的外缘**, 离玩家走得到的地方
##   外扩 左298/右334/上192/下194 px ⇒ 玩家看见的最明显的构件**不是**玩法边界。
##   翻成「岛→海→虚空」之后它会落在**海的外缘** —— 更远, 更不是边界。
##
## 【现在跟的是】陆地(grass/stone/sand) ↔ 非陆地(water/void)。
##   因为岛 == 可活动区(`tools/gen_arena_map.py` 的 `ISLE` 与 `ArenaShape.N` 同一个超椭圆),
##   所以这条界**就是**玩法边界, 一条线同时是"看得见的"和"走得到的"。
##
## ⚠ 竖面高度的标定值 `WALL_H`(照 TFT 实测: 竖面 ÷ 角色屏幕高 = 0.81 ⇒ 31px ⇒ 世界高 1.11 米)
##   **一个字没动** —— 本次只换"画在哪条界上", 不换"画多高"。
##   `tests/verify_edge_wall.gd` 里那条独立重算同步改成同一口径, 并反向验证过会红。
const _LAND_TYPES := [0, 2, 3]            # grass / stone / sand (water=1 void=4 不是陆)

func _coast_edge_segs(at: Callable, w: int, h: int, ox: float, oy: float, tile: float) -> Array:
	var segs: Array = []                              # [[Vector2 a, Vector2 b], ...] 像素口径
	for r in range(h):
		for c in range(w):
			if not (int(at.call(r, c)) in _LAND_TYPES):
				continue
			var x0 := ox + float(c) * tile
			var y0 := oy + float(r) * tile
			var x1 := x0 + tile
			var y1 := y0 + tile
			if not (int(at.call(r - 1, c)) in _LAND_TYPES):
				segs.append([Vector2(x0, y0), Vector2(x1, y0)])
			if not (int(at.call(r + 1, c)) in _LAND_TYPES):
				segs.append([Vector2(x1, y1), Vector2(x0, y1)])
			if not (int(at.call(r, c - 1)) in _LAND_TYPES):
				segs.append([Vector2(x0, y1), Vector2(x0, y0)])
			if not (int(at.call(r, c + 1)) in _LAND_TYPES):
				segs.append([Vector2(x1, y0), Vector2(x1, y1)])
	return segs


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

## ═══ 地面碎料层（2026-09-20）═══════════════════════════════════════
## ★★为什么有它：`docs/design/20260920-场内道具规格调研.md` 实测 ——
##   参考里 Brotato_3 的地面碎料 **296 件/Mpx@1080p**、覆盖 **2.20%**、中位高 **0.12×角色高**，
##   而本项目 **0 件**（结构性：`_build_tilemap_decor` 的装饰带全在 ARENA 外扩 200px 上）。
## ★同类型游戏（TFT / Underlords / Brotato）**盘内立体道具都是 0 件** ——
##   它们靠「盘外岸边 + 满地小碎料」撑画面。本项目属于这一类，
##   **不该照 Hades 往盘内堆桶和瓮**（那会挡走位、也不是同构参考的做法）。
## ⇒ 盘内只铺**碎料**：贴地、极矮、无碰撞、不挡视线。
##
## ★走 MultiMesh 不是 N 个 Sprite3D：280 个独立节点每帧都要被引擎遍历，
##   而它们是**完全静态**的 —— 一次性烘进一个 MultiMesh，引擎按一次 draw call 画完。
const DETRITUS := [
	"res://assets/sprites/map/deco_rubble.png",
	"res://assets/sprites/map/deco_grasstuft.png",
]
## ★★**这两个数是实拍反解出来的, 而且量坐标换过一次**。
##   第一版按「参考 296 件/Mpx × 本场地 Mpx」算出 280 件/0.34m。
## ★★然后我拿**活战斗的两张实拍做差分**去量, 得出「723 件/Mpx·覆盖 7.16%」说超了2.4倍,
##   回头调小两版——**全是错的**。拿已知答案标定才发现:
##   **N=0(零碎料)量出 391 件/4.31%**, 比 N=290 还多 ——
##   战斗是活的, 单位在动、飘字在跳, 差分量的是**战斗位移**不是碎料。
##   ⇒ 换成 `MAPEDIT=1` 的**静态场**(不生成单位)量, 两张只差碎料。
## 静态场真值(N=0 为基准):
##   290 件/0.185m ⇒  56 件/Mpx · 覆盖 0.12%   ← **其实铺得太少**(与活战斗量的结论相反)
##   1540 件/0.34m  ⇒ 574 件/Mpx · 覆盖 2.97%
##   **820 件/0.38m  ⇒ 349 件/Mpx · 覆盖 2.05%**  ← 取这档(参考 296 / 2.20%)
## ★★★2026-10-03 **820 → 0**。用户原话:「**别管brotato的**」。
##   这一层当初(2026-09-20)加进来的全部依据就是上面那句「参考里 Brotato_3 的地面碎料
##   296 件/Mpx、覆盖 2.20%」—— **那个参考被作废了, 依据跟着没了**。
##   实拍也印证: `tools/battle_scene_check.py` 的 ⑤「中带高频密度」台账 18.74,
##   而参考值 4.90% / 目标 ≤5.20% —— 满地碎料正是最吵的那一项。
## ★为什么留着常量而不是删掉整层: 剩下两份参考(咩咩 178 件/Mpx · Botworld 战斗场 0 件)
##   **还没定要像哪个**(方案书 `20261003-岛与海作为边界.md` 风险 5)。
##   改成 0 ⇒ 这一层整个不生成; 哪天定了像咩咩, 把这个数调回去即可, 不用重写代码。
## ⚠ 不许在"没定参考"的情况下自己拍一个中间值 —— 那是 memory
##   `fb-my-thresholds-degrade-good-assets` 和 `fb-my-goal-can-be-wrong-not-just-my-code` 那两类。
const DETRITUS_N := 0
const DETRITUS_SIZE_M := 0.38
const DETRITUS_SEED := 20260920

## ★★★这个常量已经连着【三轮】需要重标定, 记一笔: 1.55(v0.19.405) → 1.70(水面重做) → 2.05(灯光重做)。
##   每次都是因为"地面变亮了、墙没跟着变" —— 根因是**墙卡是 UNSHADED 而地面吃光**,
##   两者之间只靠这一个手工标定的数连着。⇒ **它是脆的**, 已登记成方案书 20260918b 的 W8。
##   真正的解法是让墙也吃光(或按灯光能量推导增益), 那是独立一轮的活, 本轮不做。
##   ⚠ 在那之前: **任何动灯光/地面亮度的改动, 都必须重跑一次实拍标定**, 别照抄这个数。
## ★★2026-09-18(同日·水面重做后) 1.55 → 1.70: 上面那句「这个数依赖地面有多亮」当场应验 ——
##   水面重做把场内地面明度从 78.2 抬到 81.6, 墙就从 +24% 掉到 **+18%**, 掉出标定区间(+23~40%)。
##   ⇒ 只要动灯光/地面亮度, 这个数必须重量。方案书 20260918b 的 W3 登记的就是这条。

## ★★画出来的地面与崖边(主题 `ground_tileset`): PixelLab Wang 图块, 按四角「地面/深渊」选块。
## 依据(开发者原话): 咩咩「all the art is hand drawn, minus a few shaders」—— 地面和平台边缘是画的,
##   不是 shader 调色 + 代码软化。用户 2026-10-03:「人家是用代码解决的吗」。
## 做法: 地图格心当角点, 图块铺在格心之间的对偶网格上(每块的四角 = 相邻四个格子是不是陆地)。
##   贴图: assets/sprites/map/themes/tilesets/<名>.png, 选块表: <名>.json = {"tile": 像素, "wang": {"0..15": [x,y]}}。
## base 不给 ⇒ 不建, 一个像素不动。
func build_tileset_ground(grid: Array, w: int, h: int, tile: float, ox: float, oy: float) -> Array:
	var made: Array = []
	var nm: String = str(ArenaTheme.cfg().get("ground_tileset", ""))
	if nm == "":
		return made
	var png: String = "res://assets/sprites/map/themes/tilesets/%s.png" % nm
	var js: String = "res://assets/sprites/map/themes/tilesets/%s.json" % nm
	if not ResourceLoader.exists(png) or not FileAccess.file_exists(js):
		push_warning("[tileset_ground] 图块缺失: %s —— 不铺(不做静默兜底)" % nm)
		return made
	var tex: Texture2D = load(png)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(js))
	var tpx: float = float(meta.get("tile", 32))
	var wang: Dictionary = meta.get("wang", {})
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	var is_land := func(r: int, c: int) -> int:
		if r < 0 or r >= h or c < 0:
			return 0
		var row: Array = grid[r]
		if c >= row.size():
			return 0
		var v: int = int(row[c])
		return 1 if (v == 0 or v == 2 or v == 3) else 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	var y: float = 0.004
	for r in range(-1, h):
		for c in range(-1, w):
			var nw: int = is_land.call(r, c)
			var ne: int = is_land.call(r, c + 1)
			var sw: int = is_land.call(r + 1, c)
			var se: int = is_land.call(r + 1, c + 1)
			var key: String = str(nw * 8 + ne * 4 + sw * 2 + se)
			if key == "0" or not wang.has(key):
				continue      # 全是深渊的块不铺: 被灯照成一片灰板(实拍), 让底下的黑海露出来
			var xy: Array = wang[key]
			var u0: float = float(xy[0]) / tw
			var v0: float = float(xy[1]) / th
			var u1: float = (float(xy[0]) + tpx) / tw
			var v1: float = (float(xy[1]) + tpx) / th
			## 四角 = 相邻四个格心
			var p00: Vector3 = battle._world_pos(Vector2(ox + (float(c) + 0.5) * tile, oy + (float(r) + 0.5) * tile), y)
			var p10: Vector3 = battle._world_pos(Vector2(ox + (float(c) + 1.5) * tile, oy + (float(r) + 0.5) * tile), y)
			var p01: Vector3 = battle._world_pos(Vector2(ox + (float(c) + 0.5) * tile, oy + (float(r) + 1.5) * tile), y)
			var p11: Vector3 = battle._world_pos(Vector2(ox + (float(c) + 1.5) * tile, oy + (float(r) + 1.5) * tile), y)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(p10)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(p01)
			quads += 1
	if quads == 0:
		push_warning("[tileset_ground] 一块都没铺")
		return made
	var mi := MeshInstance3D.new()
	mi.name = "TilesetGround"
	mi.mesh = st.commit()
	## 小 shader: 贴图 × 主题着色 × 中心聚光(图块原色是生成器给的鲜绿/粉红崖边, 要压进主题色调;
	##   参考 mixed_034 中心亮池、四周沉暗)。吃光照(火把照得亮)。
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : filter_nearest, source_color;
uniform vec4 tint : source_color = vec4(1.0);
// 目标色(参考截帧地面中位数实测): 色相 0..1 / 饱和 / 亮度。图块只贡献明暗笔触, 颜色对齐参考。
uniform vec3 hsv_target = vec3(-1.0, 0.0, 0.0);
uniform vec2 spot_c = vec2(0.0);
uniform vec2 spot_half = vec2(1.0);
uniform float spot_amt = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = texture(tex, UV).rgb * tint.rgb;
	if (hsv_target.x >= 0.0) {
		// 以图块地面中位亮度 0.55 为基准保留明暗起伏, 色相/饱和统一到目标
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		float v = clamp(hsv_target.z * lum / 0.55, 0.0, 1.0);
		vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
		vec3 p = abs(fract(vec3(hsv_target.x) + k) * 6.0 - 3.0);
		c = v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), hsv_target.y);
	}
	float sr = length((wpos.xz - spot_c) / spot_half);
	c *= 1.0 - spot_amt * smoothstep(0.30, 1.05, sr);
	ALBEDO = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", ArenaTheme.cfg().get("ground_tileset_tint", Color(1, 1, 1)))
	if ArenaTheme.cfg().has("ground_tileset_hsv"):
		m.set_shader_parameter("hsv_target", ArenaTheme.cfg()["ground_tileset_hsv"])
	var _A: Rect2 = battle.ARENA
	var _c3: Vector3 = battle._world_pos(_A.position + _A.size * 0.5, 0.0)
	var _e3: Vector3 = battle._world_pos(_A.end, 0.0)
	m.set_shader_parameter("spot_c", Vector2(_c3.x, _c3.z))
	m.set_shader_parameter("spot_half", Vector2(absf(_e3.x - _c3.x), absf(_e3.z - _c3.z)))
	m.set_shader_parameter("spot_amt", float(ArenaTheme.cfg().get("spot_amt", 0.0)))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle._world.add_child(mi)
	made.append(mi)
	return made


func build_edge_wall(grid: Array, w: int, h: int, tile: float, ox: float, oy: float) -> Array:
	var made: Array = []
	if str(ArenaTheme.cfg().get("ground_tileset", "")) != "":
		return made    # ★崖边已经画在图块里, 不再立代码墙
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
	var segs: Array = _coast_edge_segs(at, w, h, ox, oy, tile)
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
	## ★主题可压低海岸竖面(wall_h, 默认 1.0 = 原值): 墙沿格子走成台阶, 一高就是一排方块;
	##   参考的平台边沿是一道矮边 + 草丛, 不是一圈围墙。
	var _wh: float = float(ArenaTheme.cfg().get("wall_h", 1.0))
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
			var a_hi: Vector3 = a_lo + Vector3(0.0, WALL_H_M_GEO * _wh, 0.0)
			var b_hi: Vector3 = b_lo + Vector3(0.0, WALL_H_M_GEO * _wh, 0.0)
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
	## ★★★2026-10-03 海岸线竖面按主题上色。
	##   实拍四版拼图照出来的: 这道墙**四版一模一样**, 而它是画面上最显眼的构件之一
	##   ⇒ 四个世界共用同一道边界, 看着就像"同一张图换了个滤镜"。
	##   咩咩每个生态区的边界也都不一样(地牢是石 curb、沼泽是木栈、营地是草坡)。
	## ★★用**专用键 `wall_col`**, 而且 `base` **刻意不给** —— 与远景端点同一套做法。
	##   我第一版图省事直接拿 `stone_col` 推: 算出来 base 会变成 (0.629,0.604,0.570),
	##   而原值 `WALL_COL_LIT` 是 (0.620,0.660,0.860) —— **不相等**, 等于悄悄改掉已验收的画面。
	##   (这已经是今晚第三次差点这样: 远景斜坡、沙地映射、这里。
	##    形状都一样 —— "顺手复用一个相近的键", 而相近 ≠ 相等。)
	var _wt: Dictionary = ArenaTheme.cfg()
	m.albedo_color = _wt.get("wall_col", WALL_COL_LIT)
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
	_flames = []   # ★本函数(含周边光点)每次重建都重登记火源(MAPEDIT 刷格会重调)
	var root := Node3D.new()
	root.name = "FieldLamps"
	battle._world.add_child(root)
	made.append(root)
	var A: Rect2 = battle.ARENA
	## ★主题可换灯具(lamp_tex/lamp_h): 参考里场内光源是插在地上的红火把, 不是黄火盆。base 不给 ⇒ 原火盆。
	var _ltn: String = str(ArenaTheme.cfg().get("lamp_tex", ""))
	var _lt_path: String = ("res://assets/sprites/map/themes/%s.png" % _ltn) if _ltn != "" else LAMP_TEX
	var _lh: float = float(ArenaTheme.cfg().get("lamp_h", LAMP_H_M))
	var tex: Texture2D = load(_lt_path) if ResourceLoader.exists(_lt_path) else null
	if tex == null:
		push_warning("[field_lamps] 火盆贴图缺失: %s —— 光会没有来源物(不做静默兜底)" % _lt_path)
	for uv in LAMP_AT:
		var px := A.position + Vector2(A.size.x * uv.x, A.size.y * uv.y)
		var lamp := OmniLight3D.new()
		## ★★2026-10-03 灯色/强度按主题走。`LAMP_COL`(#FDF77B·色相 57°, 参考中位) 与
		##   `LAMP_ENERGY` 是 2026-09-18 标定的, 作为【主题没给时的兜底】保留。
		##   ⚠ 与主光不同: 主光改了会把整张图的曝光推歪(试过, 已撤回); 点光是**加法**的,
		##   改它只会往画面里**加**颜色 —— 参考里暗场的色彩变化正是靠彩色点光来的。
		var _lc: Dictionary = ArenaTheme.cfg()
		lamp.light_color = _lc.get("light_col", LAMP_COL)
		lamp.light_energy = LAMP_ENERGY * float(_lc.get("light_energy", 1.0))
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
			s.pixel_size = _lh / float(tex.get_height())
			s.position = battle._world_pos(px, _lh * 0.5)
			root.add_child(s)
			made.append(s)
			_flames.append(s)
			if ArenaTheme.cfg().has("rim_halo_col"):
				var _hz = _rim_halo(px, ArenaTheme.cfg()["rim_halo_col"], float(ArenaTheme.cfg().get("rim_halo_size", 2.0)) * 1.6)
				root.add_child(_hz)
	made.append_array(_build_rim_lights())   # ★主题: 周边一圈彩色小光点(base 不给 ⇒ 什么都不加)
	made.append_array(_build_edge_tufts())   # ★主题: 平台边沿一圈草/海草丛(base 不给 ⇒ 什么都不加)
	if bool(ArenaTheme.cfg().get("use_layout", false)):
		made.append_array(_build_layout_props())   # ★主题: 按设计布局摆(ArenaTheme.LAYOUT), 不随机撒
	else:
		made.append_array(_build_field_tufts())  # ★主题: 场内成簇草丛(base 不给 ⇒ 什么都不加)
	made.append_array(_build_ring_lanterns())  # ★主题: 外围树林里悬着的红光(base 不给 ⇒ 不加)
	if not bool(ArenaTheme.cfg().get("use_layout", false)):
		made.append_array(_build_field_tufts("field_piles", 20261006))  # ★主题: 场内骨堆(mixed_033/034/012)
	return made


## 周边一圈彩色小光点 —— 主题专用, `base` 不给就一盏不加。
##
## ★★依据是**真实游玩**截帧(桌面 `咩咩参考_真实游玩20张.jpg`): 20 张里几乎张张都有
##   沿平台边沿排的一圈小光源 —— Darkwood 是红烛, Anchordeep 是绿/白光球。
##   每盏都有**来源物**(烛台/光球精灵), 不是凭空的光斑。我们原来只有场内 3 盏火盆。
## ★摆在**岛边沿外侧一点**(岸上/浅水), 不占可活动区: 椭圆可活动区本来就只有矩形的 78.5%。
## ★性能: 真光源(OmniLight3D)只开 `rim_light_real` 盏, 其余只画精灵 + 加性光晕 ——
##   28 只龟的场景里铺几十盏真点光会掉帧(本仓有 _probe_fps 量过点光开销)。
func _build_rim_lights() -> Array:
	var made: Array = []
	var cfg: Dictionary = ArenaTheme.cfg()
	var n: int = int(cfg.get("rim_lights", 0))
	if n <= 0:
		return made
	var img: String = str(cfg.get("rim_light_tex", ""))
	var path: String = "res://assets/sprites/map/themes/%s.png" % img
	var tex: Texture2D = load(path) if (img != "" and ResourceLoader.exists(path)) else null
	if tex == null:
		push_warning("[rim_lights] 光点贴图缺失: %s —— 不铺(光必须有来源物, 不做静默兜底)" % path)
		return made
	var n_real: int = int(cfg.get("rim_light_real", 6))
	var col: Color = cfg.get("light_col", LAMP_COL)
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	var root := Node3D.new()
	root.name = "RimLights"
	battle._world.add_child(root)
	made.append(root)
	for i in range(n):
		var th: float = TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		## ★★第一版摆在岛外(半径 1.02~1.08): 实拍四版**一盏都看不出来** ——
		##   点光照到的是近黑的海, 等于没照亮任何东西; 顶上那一圈还被岸边竖崖挡住。
		##   参考里蜡烛是**放在平台边沿上**, 把地面照出一圈光池。⇒ 挪到边沿内侧。
		var _rr: Array = cfg.get("rim_light_r", [0.90, 0.97])
		var rr: float = rng.randf_range(float(_rr[0]), float(_rr[1]))
		var p := Vector2(c.x + cos(th) * A.size.x * 0.5 * rr, c.y + sin(th) * A.size.y * 0.5 * rr)
		## ★探针: 光点 24 个节点都建了, 实拍看不见 —— 0.55 米只有火盆(1.28 米)的四成, 压不过亮地面。
		## ★2026-10-04 主题可给第二/三种灯具(rim_light_tex_alt), 轮流摆: 18 盏同一张图一眼看得出是复制的。
		##   高度按素材名单给(rim_light_h_of), 没写的用 rim_light_h。base 不给 ⇒ 一种灯, 原样。
		var _path_i: String = path
		var _alts: Array = cfg.get("rim_light_tex_alt", [])
		var _h_i: float = float(cfg.get("rim_light_h", 0.55))
		if not _alts.is_empty() and i % (_alts.size() + 1) != 0:
			var _an: String = str(_alts[(i % (_alts.size() + 1)) - 1])
			var _ap: String = "res://assets/sprites/map/themes/%s.png" % _an
			if ResourceLoader.exists(_ap):
				_path_i = _ap
				_h_i = float((cfg.get("rim_light_h_of", {}) as Dictionary).get(_an, _h_i))
		var s = battle._map_billboard(_path_i, p, _h_i)
		## ★参考(mixed_033/034/035)里的光是**饱和的红**、带一圈地面光晕; 我们的烛火是黄的 ⇒ 着色 + 地面光晕。
		s.modulate = cfg.get("rim_light_mod", Color(1, 1, 1))
		root.add_child(s)
		_flames.append(s)
		if cfg.has("rim_halo_col"):
			root.add_child(_rim_halo(p, cfg["rim_halo_col"], float(cfg.get("rim_halo_size", 2.0))))
		if i % maxi(1, n / maxi(1, n_real)) == 0:
			var L := OmniLight3D.new()
			L.light_color = col
			L.light_energy = float(cfg.get("rim_light_energy", 1.4))
			L.omni_range = float(cfg.get("rim_light_range", 3.2))
			L.shadow_enabled = false
			L.position = battle._world_pos(p, 0.5)
			root.add_child(L)
	return made


## 外围树林里悬着的光(主题 ring_lanterns = 个数, ring_lantern_col = 颜色)。
## ★依据 mixed_033/034/035、mixed_012: 参考最有辨识度的红光**挂在平台外的暗林里**, 是暗底上的饱和红点;
##   我们的红光只照在黄绿地面上, 混成了橙色。
func _build_ring_lanterns() -> Array:
	var made: Array = []
	var cfg: Dictionary = ArenaTheme.cfg()
	var n: int = int(cfg.get("ring_lanterns", 0))
	if n <= 0:
		return made
	var col: Color = cfg.get("ring_lantern_col", Color(1.0, 0.1, 0.1, 0.9))
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261007
	var root := Node3D.new()
	root.name = "RingLanterns"
	battle._world.add_child(root)
	made.append(root)
	for i in range(n):
		var th: float = TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		if sin(th) > 0.3:
			continue                      # 下半圈(镜头前)不挂: 会挡战场
		var rr: float = rng.randf_range(1.08, 1.22)
		var p := Vector2(c.x + cos(th) * A.size.x * 0.5 * rr, c.y + sin(th) * A.size.y * 0.5 * rr)
		var g := _glow_puff(p, col, rng.randf_range(0.7, 1.0))
		g.position.y += rng.randf_range(0.8, 1.8)   # 悬在半空
		root.add_child(g)
	return made


## 物件脚下贴地的一块椭圆深色影(径向渐变, 普通混合)。w = 物件世界宽。
func _contact_shadow(p: Vector2, alpha: float, w: float) -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, alpha))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.55, Color(0, 0, 0, alpha * 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = gt
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, w * 0.55)
	var mi := MeshInstance3D.new()
	mi.name = "PropShadow"
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = battle._world_pos(p, 0.03)
	return mi


## 立着的一团加性辉光 + 一盏点光, 罩在发光物件(珍珠)上。h = 物件世界高。
func _glow_puff(p: Vector2, col: Color, h: float) -> Node3D:
	var n := Node3D.new()
	n.name = "GlowPuff"
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, col.a))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.3, Color(col.r, col.g, col.b, col.a * 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var s := Sprite3D.new()
	s.texture = gt
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.pixel_size = h * 2.6 / 64.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = gt
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s.material_override = m
	s.position = battle._world_pos(p, h * 0.42)
	n.add_child(s)
	var L := OmniLight3D.new()
	L.light_color = Color(col.r, col.g, col.b)
	L.light_energy = 1.4
	L.omni_range = h * 2.2
	L.shadow_enabled = false
	L.position = battle._world_pos(p, h * 0.5)
	n.add_child(L)
	return n


## 光点脚下贴地的一圈加性光晕(径向渐变)。点光只照得出很淡的一圈, 参考里的光池是饱和的一大片。
func _rim_halo(p: Vector2, col: Color, size: float) -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, col.a))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.35, Color(col.r, col.g, col.b, col.a * 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = gt
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "RimHalo"
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = battle._world_pos(p, 0.04)
	return mi


## 平台**边沿**一圈草/海草丛 —— 主题专用, `base` 不给就一件不加。
## ★依据(真实游玩截帧): 参考里平台边沿一圈长满草丛/海草丛, 把"地面在哪里结束"描出来;
##   我们的边沿是光的。这些丛长在可活动区的**最外一圈**(r ≥ 0.86), 只是装饰, 不挡路。
## ★立着的(billboard), 不是贴地 —— 参考里草丛是竖着长的, 有高度。
func _build_edge_tufts() -> Array:
	var made: Array = []
	var cfg: Dictionary = ArenaTheme.cfg()
	var names: Array = cfg.get("edge_tufts", [])
	var n: int = int(cfg.get("edge_tufts_n", 0))
	if names.is_empty() or n <= 0:
		return made
	var paths: Array = []
	for nm in names:
		var p: String = "res://assets/sprites/map/themes/%s.png" % str(nm)
		if ResourceLoader.exists(p):
			paths.append(p)
	if paths.is_empty():
		push_warning("[edge_tufts] 素材一张都没有 —— 不铺(不做静默兜底)")
		return made
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	var root := Node3D.new()
	root.name = "EdgeTufts"
	battle._world.add_child(root)
	made.append(root)
	var hr: Array = cfg.get("edge_tufts_h", [0.6, 1.1])
	for i in range(n):
		var th: float = rng.randf_range(0.0, TAU)
		var _er: Array = cfg.get("edge_tufts_r", [0.86, 0.99])
		var rr: float = rng.randf_range(float(_er[0]), float(_er[1]))
		var p2 := Vector2(c.x + cos(th) * A.size.x * 0.5 * rr, c.y + sin(th) * A.size.y * 0.5 * rr)
		var s = battle._map_billboard(str(paths[rng.randi_range(0, paths.size() - 1)]), p2,
			rng.randf_range(float(hr[0]), float(hr[1])))
		var sc: float = rng.randf_range(0.85, 1.2)
		s.scale = Vector3(sc * (-1.0 if rng.randf() < 0.5 else 1.0), sc, sc)
		s.modulate = cfg.get("edge_tufts_mod", Color(1, 1, 1))
		root.add_child(s)
	return made


## 按 ArenaTheme.LAYOUT 逐件摆场内物件(素材取主题的 field_tufts / field_piles, 着色与接地影同随机版)。
func _build_layout_props() -> Array:
	var made: Array = []
	var cfg: Dictionary = ArenaTheme.cfg()
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var root := Node3D.new()
	root.name = "LayoutProps"
	battle._world.add_child(root)
	made.append(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008                    # 只用来挑同类素材里的哪一张 + 镜像, 位置全来自布局表
	var lists := {"t": cfg.get("field_tufts", []), "p": cfg.get("field_piles", [])}
	var mods := {"t": cfg.get("field_tufts_mod", Color(1, 1, 1)), "p": cfg.get("field_piles_mod", Color(1, 1, 1))}
	var _ps: float = float(cfg.get("prop_shadow", 0.0))
	var n_put := 0
	## ★2026-10-04 主题可让同类素材**轮流**摆(prop_cycle): 随机挑在 11 个物件堆位上把一张图挑成了 5/6,
	##   同一个精灵重复看得出来(判据 verify_arena_variety)。不给 ⇒ 原随机挑法, rng 序列逐值不变(暗林不动)。
	var _cyc: bool = bool(cfg.get("prop_cycle", false))
	var _cyc_n := {"t": 0, "p": 0}
	for row in ArenaTheme.LAYOUT:
		var kind: String = str(row[2])
		var names: Array = lists.get(kind, [])
		if names.is_empty():
			continue
		var _pick: int
		if _cyc:
			_pick = int(_cyc_n.get(kind, 0)) % names.size()
			_cyc_n[kind] = int(_cyc_n.get(kind, 0)) + 1
		else:
			_pick = rng.randi_range(0, names.size() - 1)
		var path: String = "res://assets/sprites/map/themes/%s.png" % str(names[_pick])
		if not ResourceLoader.exists(path):
			continue
		var p2 := Vector2(c.x + float(row[0]) * A.size.x * 0.5, c.y + float(row[1]) * A.size.y * 0.5)
		var s = battle._map_billboard(path, p2, float(row[3]))
		if rng.randf() < 0.5:
			s.scale = Vector3(-1.0, 1.0, 1.0)
		s.modulate = mods[kind]
		root.add_child(s)
		if _ps > 0.0 and s.texture != null:
			root.add_child(_contact_shadow(p2, _ps, s.pixel_size * float(s.texture.get_width()) * 1.1))
		n_put += 1
	if n_put == 0:
		push_warning("[layout_props] 布局表一件都没摆出来")
	return made


## 场内**成簇**的草/海草丛 —— 主题专用, `base` 不给就一件不加。
## ★依据(真实游玩截帧 mixed_033/034, anchordeep_005/011): 地面中间也散着一簇簇大草丛/海草,
##   不只边沿一圈; 我们的场内只有几像素的碎屑, 远看是一块空地。
## ★成簇(每簇 3~5 丛)而不是均匀撒 —— 均匀撒读作噪点; 避开正中心(r < 0.30)留出交战区。
func _build_field_tufts(key: String = "field_tufts", seed: int = 20261005) -> Array:
	var made: Array = []
	var cfg: Dictionary = ArenaTheme.cfg()
	var names: Array = cfg.get(key, [])
	var nc: int = int(cfg.get(key + "_clusters", 0))
	if names.is_empty() or nc <= 0:
		return made
	var paths: Array = []
	for nm in names:
		var p: String = "res://assets/sprites/map/themes/%s.png" % str(nm)
		if ResourceLoader.exists(p):
			paths.append(p)
	if paths.is_empty():
		push_warning("[%s] 素材一张都没有 —— 不铺(不做静默兜底)" % key)
		return made
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var root := Node3D.new()
	root.name = "FieldTufts" if key == "field_tufts" else "FieldPiles"
	battle._world.add_child(root)
	made.append(root)
	var hr: Array = cfg.get(key + "_h", [0.5, 0.9])
	for k in range(nc):
		var th: float = TAU * (float(k) + rng.randf_range(-0.35, 0.35)) / float(nc)
		var rr: float = rng.randf_range(0.36, 0.80)
		var cc := Vector2(c.x + cos(th) * A.size.x * 0.5 * rr, c.y + sin(th) * A.size.y * 0.5 * rr)
		for j in range(rng.randi_range(3, 5)):
			var p2: Vector2 = cc + Vector2(rng.randf_range(-38.0, 38.0), rng.randf_range(-22.0, 22.0))
			var s = battle._map_billboard(str(paths[rng.randi_range(0, paths.size() - 1)]), p2,
				rng.randf_range(float(hr[0]), float(hr[1])))
			var sc: float = rng.randf_range(0.8, 1.2)
			s.scale = Vector3(sc * (-1.0 if rng.randf() < 0.5 else 1.0), sc, sc)
			s.modulate = cfg.get(key + "_mod", Color(1, 1, 1))
			root.add_child(s)
			## ★接地影(prop_shadow = 不透明度): 参考每件物件脚下都有一块深色影, 没有就像贴上去的。
			var _ps: float = float(cfg.get("prop_shadow", 0.0))
			if _ps > 0.0:
				root.add_child(_contact_shadow(p2, _ps, s.pixel_size * float(s.texture.get_width()) * sc * 1.1))
	return made


## 地面碎料层。返回建出来的节点。
## ★★位置规则（实测出来的，不是拍的）：
##   本项目中心半区只有 **5%** 有东西（1 件，还是碰撞礁石），参考是 **15%**，
##   而**纯装饰在内圈 0 件**。碎料正好补这一块 —— 它贴地、不挡走位。
## ★不落在水里：只铺在非 void 且非 water 的格子上（地图 `types` 里 water=1）。
func build_detritus(grid: Array, w: int, h: int, tile: float, ox: float, oy: float) -> Array:
	var made: Array = []
	var texes: Array = []
	## ★★2026-10-03 主题碎件。依据是**真实游玩**截帧(桌面 `咩咩参考_真实游玩20张.jpg`):
	##   真实战斗房间的地面散着大量低对比小碎件(骨头/碎石/草屑/贝壳)。
	##   我之前说的「战斗区几乎是空的」是拿 BOSS **宣传图**得出的, 错了。
	## ★主题碎件只用**新做的**素材(用户:「不要复用，从新做」); `base` 不给 ⇒ 走原来那套(N=0 = 不铺)。
	var _tc: Dictionary = ArenaTheme.cfg()
	var _tdn: Array = _tc.get("detritus", [])
	var n_total: int = int(_tc.get("detritus_n", DETRITUS_N))
	var paths: Array = DETRITUS
	if not _tdn.is_empty():
		paths = []
		for nm in _tdn:
			paths.append("res://assets/sprites/map/themes/%s.png" % str(nm))
	if n_total <= 0:
		return made
	for path in paths:
		if ResourceLoader.exists(path):
			texes.append(load(path))
	## ★分母：贴图一张都没有就别画，也别静默兜底 —— 兜底会让"素材没导入"看起来像"设计如此"。
	if texes.is_empty():
		push_warning("[detritus] 碎料贴图一张都没有 —— 不铺(不做静默兜底)")
		return made

	var root := Node3D.new()
	root.name = "Detritus"
	battle._world.add_child(root)
	made.append(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = DETRITUS_SEED          # ★固定种子: 同一张图每次开局碎料位置一致(确定性)
	## 可落点 = 非 void(4) 且 非 water(1) 的格子
	var cells: Array = []
	for r in range(h):
		var row: Array = grid[r]
		for c in range(w):
			if c >= row.size():
				continue
			var ti := int(row[c])
			if ti == 4 or ti == 1:
				continue
			cells.append(Vector2i(c, r))
	if cells.is_empty():
		push_warning("[detritus] 一个可落点都没有 —— 不铺")
		return made

	## 每种贴图一个 MultiMesh
	var per: int = int(ceil(float(n_total) / float(texes.size())))
	for tex in texes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := QuadMesh.new()
		var _ds: float = float(ArenaTheme.cfg().get("detritus_size", DETRITUS_SIZE_M))
		q.size = Vector2(_ds, _ds)
		## ★贴地: QuadMesh 默认立在 XY 面, 掰平成 XZ。
		##   ⚠ 这里**不能**照抄 `axis = AXIS_Y` 那套 —— 那是 Sprite3D 的属性,
		##     QuadMesh 得靠实例 transform 转。(本项目记过「AXIS_Y 加 -90 旋转会抵消」。)
		mm.mesh = q
		mm.instance_count = per
		var placed := 0
		## ★碎件偏向边沿: 参考(真实游玩截帧)里碎件**堆在平台边沿与石头周围**, 中间较干净;
		##   均匀撒出来是"一地纸屑"(V2 第一版实拍)。按格子到中心的归一化半径 r 做接受率 r^bias。
		var _bias: float = float(ArenaTheme.cfg().get("detritus_edge_bias", 0.0))
		var _A: Rect2 = battle.ARENA
		var _c: Vector2 = _A.position + _A.size * 0.5
		for k in range(per):
			var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			if _bias > 0.0:
				for _try in range(12):
					var _cx := ox + (float(cell.x) + 0.5) * tile
					var _cy := oy + (float(cell.y) + 0.5) * tile
					var _r: float = clampf(sqrt(pow((_cx - _c.x) / (_A.size.x * 0.5), 2.0) + pow((_cy - _c.y) / (_A.size.y * 0.5), 2.0)), 0.0, 1.0)
					if rng.randf() < pow(_r, _bias):
						break
					cell = cells[rng.randi_range(0, cells.size() - 1)]
			var px := ox + (float(cell.x) + rng.randf()) * tile
			var py := oy + (float(cell.y) + rng.randf()) * tile
			var b := Basis()
			b = b.rotated(Vector3(1, 0, 0), -PI * 0.5)                  # 掰平贴地
			b = b.rotated(Vector3(0, 1, 0), rng.randf() * TAU)          # 随机朝向, 免得一眼看出是同一张图
			var s: float = rng.randf_range(0.72, 1.25)                  # 大小抖动
			mm.set_instance_transform(k, Transform3D(b.scaled(Vector3(s, s, s)),
				battle._world_pos(Vector2(px, py), 0.055)))             # 略高于砖顶(TILE 顶面 y≈0.05)
			placed += 1
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = ArenaTheme.cfg().get("detritus_tint", Color(1, 1, 1, 1))   # ★主题着色(base 不给=白=原样)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST        # 像素画不许插值成糊
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR      # 硬边像素画: 裁剪不混合
		m.alpha_scissor_threshold = 0.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL          # 吃光, 跟地面一起亮/暗
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		made.append(mi)
	return made


func _build_tilemap_decor() -> void:
	var root = Node3D.new(); root.name = "TileDecor"; battle._world.add_child(root)
	var rng = RandomNumberGenerator.new(); rng.seed = 20260714
	var A = battle.ARENA
	var cx = A.position.x + A.size.x * 0.5
	var cy = A.position.y + A.size.y * 0.5
	# ★点2(用户2026-07-23: 测试反馈太密+很多相同装饰): 去掉原glow-coral/glow-kelp各2遍的人为加权刷屏,
	#   并补 PixelLab 生成的 4 种新装饰(扇贝/石头/海星/海草·壳石生植不同类)增加种类, 现共 11 种。
	## ★★2026-10-03 这一层(边框密植)也按主题换素材。原来写死的是**海底系**
	##   (海草/珊瑚/海星/扇贝) —— 用户 2026-10-02:「这些珊瑚海草不适合你听明白了吗」。
	##   主题给了 `ring_props` 就用主题的; `base`(现状) 仍用原来这张表, 一个像素不动。
	var _tc: Dictionary = ArenaTheme.cfg()
	var _tp: Array = _tc.get("ring_props", [])
	var kelp = ["deco_kelp", "deco_coral_pink", "deco_coral_orange", "deco_rocks", "deco_scallop", "deco_boulder", "deco_starfish", "deco_seagrass", "glow-kelp", "glow-anem", "glow-coral"]
	if not _tp.is_empty() and not str(_tp[0]).begins_with("("):
		kelp = []
		for _p in _tp:
			kelp.append("themes/" + str(_p))
	var mg = 200.0   # ★装饰带收窄 288→200(点2: 太密)
	## ★主题不铺这一圈: 它在岛外 200px 宽的黑海面上种东西, 主题素材(贝壳等)脚下没地,
	##   实拍飘在画面上方(用户 2026-10-03:「装饰物乱飞到上面」)。主题外围只留站在边沿上的 ThemeRing。
	if bool(_tc.get("no_base_midground", false)):
		mg = -1.0e9
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
	## ★★★2026-10-03 前景框边挂在这里, 理由有两条:
	##   ① **这条路才跑**: 地图是数据驱动的, `_build_tilemap_ground` 载入 json 后就 return,
	##      程序化那条路(`_build_map_props`)根本不跑 —— 我第一版挂在那里, 探针实测一行都没打出来
	##      (「函数写好了、门禁全绿、游戏里看不见」的经典形状)。
	##   ② **继承 MAPEDIT 闸**: 中景就是这么挂的, 判据 `verify_midground ②` 按**源码字面**
	##      认那句单行的 `if not OS.has_environment("MAPEDIT"): _build_tilemap_decor()`。
	##      我一度把它改成多行 ⇒ 那条判据当场红。挂进来就不用动那一行。
	_build_foreground_band()
	## ★★★2026-10-03 主题环也挂这里。
	##   它原来挂在 `_build_map_props()` 里 —— 和前景框边**一模一样的坑**:
	##   地图是数据驱动的, `_build_tilemap_ground` 载入 json 后就 return,
	##   那条程序化的路根本不跑 ⇒ 我写的「簇心 + 小半径散布」**一次都没执行过**,
	##   屏幕上看到的主题物件全是**本函数**(边框密植)换了素材名的结果。
	##   ⇒ 我一度据此声称"装饰已改成成组摆放", 那是假的; 是判据
	##   `verify_arena_density` 的分母断言「找得到 ThemeRing 容器吗」把它抓出来的。
	##   ★同一个坑今晚踩了两次 ⇒ 以后往世界里加层, **第一件事是确认这条路跑不跑**。
	_build_theme_decorations(root)
	## ★2026-10-04 主题: 中景灌木团 + 挂在巨树干上的吊灯 + 灯旁火星。base 不给 ⇒ 三个都一件不加。
	_build_theme_midground(root)
	_build_hang_lamps(root)
	## ★主题不画那层冰蓝上飘辉光(100 粒·满场·缓上飘 = 水下气泡的另一副面孔), 换成灯旁火星。base 照旧。
	if bool(_tc.get("no_base_midground", false)):
		_build_theme_ambient(root)
	else:
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
	## ★主题不摆默认中景(沉船/紫海葵等): 那是默认画面的素材, 不看主题照摆 ⇒ 漏进四版,
	##   而且摆在岛外的黑海面上, 实拍读作「悬在半空乱飞」(用户 2026-10-03 指出)。
	if bool(ArenaTheme.cfg().get("no_base_midground", false)):
		return
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
	## ★★开局选图(用户 2026-10-04「每场随机一张」)。必须是建场的**第一步**: 往下每一层都读 ArenaTheme.cfg()。
	##   种子此刻已定(`_build_camera` 播种 → `note_battle_seed` 登记 → 回放 `_replay.start()` 覆盖成录像里的种子)。
	##   只读种子这个整数做哈希, 不从 `_battle_rng` 取数(取了模拟就变) —— 判据 `verify_arena_theme_pick`。
	pick_arena_theme()
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
	## ★★★2026-10-03 **试过按主题调主光, 撤回了。**
	##   实测: dusk 在动它之前是「中间调 49.9% / 色数 96」, 按主题给系数之后扫了三档,
	##   最好只有 38.9% / 74 —— 四版全部低于阈值。
	##   根因: 1.55 / (1.0,0.96,0.86) 是 2026-09-18「都要仔细重做」那轮**认真标定**的,
	##   我拿一组拍脑袋的系数把它覆盖了(memory `fb-my-thresholds-degrade-good-assets`)。
	##   ★而且方向本来就错: 参考里**咩咩的暗地牢有 174 色**, 靠的是**彩色点光 + 物件**,
	##   不是把主光调暗。四版的差异该从**加法的层**(远景渐变/带灯具的点光/物件)来。
	##   ⇒ 主光保持标定值不动; `sun_col`/`sun_energy` 两个键留在主题表里**暂未接线**,
	##     等物件层建完再评估要不要微调(接线前它们是死配置, 这一点如实写在这)。
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
	#   ★移动端关掉: glow 是全屏多次降采样, 是这套画面里最贵的一项。
	env.glow_enabled = not battle._is_mobile()
	env.glow_intensity = 0.26
	env.glow_strength = 0.95
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	## ★同主光: 试过把雾色换成主题的地平线色, 一并撤回(它吃掉大片远景面积, 实测把色数从 96 压到 74)。
	## ★主题雾色: 用**专用键 `fog_col`**, base 刻意不给 ⇒ 原值逐值不变。
	##   (之前试过拿 bg_horizon 推, 连带改了 dusk 的曝光被我撤回; 这次只给明确要的主题。
	##    参考 mixed_035 整个房间被红雾浸着, 光靠几盏点光做不出来。)
	env.fog_light_color = ArenaTheme.cfg().get("fog_col", Color(0.035, 0.105, 0.150))
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

## 开局选图的**唯一**入口(`_build_environment` 第一行调; 门禁 `verify_arena_theme_pick` ④ 也直接调它量随机流状态)。
## ★只读 `_battle_rng.seed` 这个整数, 不调 randi/randf —— 调了就从模拟随机流里拿走一个数。
func pick_arena_theme() -> String:
	return ArenaTheme.choose_for_battle(int(battle._battle_rng.seed), _is_formal_battle(), _is_tutorial_battle())


## ★也是「不计赛季」的判据(用户 2026-10-07「在调试场里打的为什么会计入局数啊」):
##   `_settle_season` 读它 ⇒ 调试场/特效台/地图编辑器打完不加场次、不扣命、不发币、不上传快照。门禁 verify_debug_no_season。
func _is_dev_tool_battle() -> bool:
	return battle.DEBUG_EDIT or OS.has_environment("VFXLAB") or OS.has_environment("MAPEDIT")


## 这一局打完会不会进赛季结算(扣命 / 记闯关战绩 / 发奖)。条件与 `_settle_season` 开头那几条 early return 一致。
## ★给键盘用(2026-10-10 实操查实): R 重开 / ESC 回主菜单原来**不分场合** ⇒ 计分对局里一按就把这一局抹掉,
##   负场不记、命不扣 —— 与用户 2026-07-30「认输 = 整场负, 不许直接回主菜单」相反。
func _is_scored_match() -> bool:
	if battle._replay != null and battle._replay.is_playing():
		return false
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null or bool(gs.get("tutorial_active")) or _is_dev_tool_battle():
		return false
	return (gs.get("season_leaders") is Array) and (gs.get("season_leaders") as Array).size() >= 1


## 键盘守卫(`_unhandled_input` 第一句调): 计分对局没打完时吞掉 R / ESC 并返回 true。
##   ESC = 弹认输确认(框开着再按 = 收起); R 什么都不做。其余情况返回 false, 主文件照旧处理。
func _scored_key_guard(keycode: int) -> bool:
	if keycode != KEY_R and keycode != KEY_ESCAPE:
		return false
	if battle._settled or not _is_scored_match():
		return false
	if keycode == KEY_ESCAPE:
		if battle._info_panel != null and is_instance_valid(battle._info_panel):
			return false                     # 详情面板开着 → 交给主文件先关面板
		var sp = battle._surrender_panel
		if sp != null and is_instance_valid(sp) and sp.visible:
			battle._hide_surrender_confirm()
		else:
			battle._show_surrender_confirm()
	return true


## 这一场是不是**教学战斗**(GameState.tutorial_active 且走双路)。
## ★用户 2026-10-04 拍板(「可以」): 教学固定暗林一张, 不跟正式对局随机。
func _is_tutorial_battle() -> bool:
	if _is_dev_tool_battle() or GameState == null:
		return false
	return bool(battle._is_dual_lane_mode()) and bool(GameState.get("tutorial_active"))


## 这一场算不算**正式对局**(地图按种子随机): 双路对局(积分赛/周六/周日), 且不是教学、不是开发工具。
## ★调试场(DEBUG_EDIT)/特效台(VFXLAB)/地图编辑器(MAPEDIT)不算 ⇒ 它们保持进场前的 active(默认 V0_BASE,
##   环境变量 ARENA_THEME 仍可强制)。审阅台/EQDEMO 在双路下本来就被绕过, 不双路时自然不算。
## ★教学也走双路, 但不算(固定 ArenaTheme.TUTORIAL_THEME, 见 `_is_tutorial_battle`)。
func _is_formal_battle() -> bool:
	if _is_dev_tool_battle() or _is_tutorial_battle():
		return false
	return bool(battle._is_dual_lane_mode())


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
	## ★主题换障碍的**外观**(obstacle_tex = {原图名: 主题素材名 | [素材名...]}), 不换 footprint:
	##   碰撞椭圆 rx/ry 是 2026-07-21 按「视觉半宽」标定的玩法尺寸 ⇒ 主题素材按**同一视觉半宽**反推高度,
	##   看起来多宽就挡多宽。base 不给 ⇒ 原礁石, 一个像素不动。
	var _otex: Dictionary = ArenaTheme.cfg().get("obstacle_tex", {})
	var _oi := 0
	for ob in battle._obstacles:
		var _on: String = str(ob["img"])
		if _otex.has(_on):
			root.add_child(_theme_obstacle(ob, _otex[_on], _oi))
			_oi += 1
		else:
			root.add_child(battle._map_billboard("res://assets/sprites/map/%s.png" % _on, ob["c"], float(ob["h"])))
	_clear_layout_on_obstacles()
	# 基地穹顶围栏(加性发光, 罩蛋) — 两端基地
	for pair in [["left", battle.ARENA.position.x + 70.0], ["right", battle.ARENA.end.x - 70.0]]:
		var dome = battle._map_billboard("res://assets/sprites/map/base_dome.png", Vector2(float(pair[1]), c.y), 3.0, true)
		dome.scale = Vector3(1.9, 1.9, 1.9)   # 罩大盖住蛋
		root.add_child(dome)
		battle._base_domes[str(pair[0])] = dome
	## ★★2026-10-04 真对局(双路)走的是**这条**路, 而调试场/门禁走的是 `_build_tilemap_decor` ——
	##   主题在这里漏了三样(实拍 v0.19.524 暗林双路对局):
	##     ① 主题环建了**第二遍**(tilemap 那条已经建过 ThemeRing, 同种子同位置叠两层)
	##     ② 顶上 4 道水面光柱照画(用户 2026-10-03「还有顶上那4个光柱？」指的就是这 4 道 ——
	##        远景那 6 道当时关了, 这 4 道在另一条路上, 门禁只量调试场所以一直没抓到)
	##     ③ 满场往上飘的气泡照画(方案书 §4.5-2 点名要删的那个)
	##   ⇒ 主题: 环已存在就不重建; 光柱/气泡不画(只删错的)。base 三行照旧, 一个像素不动。
	var _themed: bool = bool(ArenaTheme.cfg().get("no_base_midground", false))
	if not (_themed and battle._world.find_child("ThemeRing", true, false) != null):
		_build_theme_decorations(root)
	# 珊瑚/海草/礁石 铺边框住战场+填空地(纯装饰无footprint)
	if not _themed:
		_build_lightshafts(root)   # 水面光柱(加性发光, 深海氛围)
		_build_bubbles(root)       # 漂浮气泡颗粒
	elif battle._world.find_child("ThemeAmbient", true, false) == null:
		_build_theme_ambient(root)

# 装饰景物: 珊瑚/海草/礁石 沿上下边框+四角+基地周围铺 (纯装饰, 无导航footprint, 不挡移动). 固定布局(可复现).
# 装饰景物: 珊瑚/海草/礁石 沿上下边框+四角+基地周围铺 (纯装饰, 无导航footprint, 不挡移动). 固定布局(可复现).
## 主题装饰环 —— **成组** + **中空外密**。
##
## ★★★2026-10-03。原来那张 `_build_decorations` 是**写死的坐标表**:
##   16 件 / 4 类 / 沿上下两条直线一字排开, 实测 Clark-Evans **R = 1.13**(比随机还均匀)、
##   y 坐标只有 11 个不同值、中间 642px 一件都没有。
##
## 【参考怎么做】逐张看咩咩(raw_18 BOSS 场最明显):
##   **战斗区几乎是空的, 细节全推到周边一圈** —— 中间只有零散石板, 四周密集高草/烛台/菌丛。
##   实测 R = **0.66**(23 张里 22 张 < 1 = 成组), 单屏中位 **79 件 / 7~8 类**。
##
## 【所以这里做两件事】
##   ① **成组**: 先在环上选 `clusters` 个簇心, 再在每个簇心周围撒 k 件 —— 均匀撒出来的是 R≈1,
##      只有"簇心 + 小半径散布"才压得到 0.66。
##   ② **中空外密**: 簇心一律落在**岛外**的环带上(ARENA 之外), 战斗区内一件不放。
##      ★顺带解掉一条约束: 椭圆可活动区只有矩形的 78.5%, 往里摆东西会再吃活动空间。
##
## ★确定性: 用**播种** RNG(`rng_discipline` 门禁拦裸随机, 护确定性回放)。
## 前景框边 —— 压住画面下沿的一条剪影带。**本仓原来一层都没有。**
##
## ★★★2026-10-03 由来: 逐张看咩咩才发现的一条构图装置(上一轮那份统计报告量不出来) ——
##   `raw_13`(沼泽) 用**超大荷叶**压住上下两边、`raw_04`(营地日景) 用一整排**高草**压住下沿、
##   `raw_18`(BOSS 场) 左右下角是大片橙草。它们都**部分遮挡**画面, 而且比场内任何东西都近。
##   作用有两个, 缺了就"少一层":
##     ① 给画面一个**最近的深度层** —— 没有它, 最近的东西就是单位本身, 画面是平的;
##     ② 把视线往中间收 —— 参考的战斗区几乎是空的, 靠四周收束才不散。
##
## ★为什么用 side 视角的素材而不是 top-down: 它是"立在镜头前"的东西, 不是躺在地上的。
## ★为什么贴在相机近处而不是场地边缘: 要的是**遮挡**, 不是"场地边上有草"。
##   放场地边就又变成一圈装饰(我们已经有那一层了)。
##
## ⚠ 只做**下沿**。上沿被血条/VS 那条 HUD 占着(实拍可见), 再压一条会打架。
func _build_foreground_band() -> void:   # ★不收 root: 它挂在相机上, 不挂在世界树上
	var cfg: Dictionary = ArenaTheme.cfg()
	var img: String = str(cfg.get("fg_band", ""))
	if img == "" or img.begins_with("("):
		return                                   # `base`(现状) 没有这一层, 保持原样
	var path: String = "res://assets/sprites/map/themes/%s.png" % img
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null or battle._cam == null:
		return
	## ★★★第一版把它摆在战场平面上(`ARENA.end.y + 210`) —— **实拍里完全看不见**,
	##   因为那已经在相机可见范围之外(实测 ARENA 下方只有约 124px 可见余量)。
	##   前景层按定义就该**挂在相机前面**: 它是"立在镜头前的东西", 不是"场地边上的草"。
	##   ⇒ 做成 `battle._cam` 的子节点, 用相机局部坐标摆位, 与场地几何完全解耦。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	## ★★★位置与宽度是**探针量出来的**, 不是拍的:
	##   第一版 local y = -1.46 ⇒ `unproject_position` 报屏幕 y = **1748**, 而视口只有 1280 高
	##   —— 整条带在画面底下很远的地方, 所以"函数跑了却看不见"。
	##   实测相机 fov=40° / near=0.05 / 视口 1280×1280; 在 z=-2.35 处
	##   半高 = 2.35·tan20° = 0.855 世界单位 ↔ 640px ⇒ **1 世界单位 ≈ 748px**。
	##   最终成图是 1280×720(从 1280×1280 视口裁出) ⇒ 可见区纵向约 y∈[280,1000]。
	##   ⇒ 要把带压在可见区下沿 ⇒ 屏幕 y≈960 ⇒ 偏离中心 320px ⇒ local y ≈ -0.43。
	## ★宽度同理: 贴图 400px 宽, 要铺满 1280px 的 1.3 倍 ⇒ 2.22 世界单位 ⇒ pixel_size ≈ 0.0055。
	## ★★2026-10-04 `fg_band_px`(主题给) ⇒ **单张整幅**分层剪影(fg_sea_band):
	##   旧图是两张 400px 锯齿草带左右各铺一张、中段重叠; 新图是**画好构图**的一整幅
	##   (两角大海带框边、中段压低让出视线、远/中/近三层), 两张叠着会把构图叠乱 ⇒ 只铺一张。
	##   贴图是**灰度**: 灰度 = 层深(远亮近暗), 颜色仍由 fg_band_col 给, `fg_band_gain` 把灰度抬回剪影色量级。
	##   1280×720 实测 1 世界单位 ≈ 421px(竖向 fov 40°·z=-2.35) ⇒ px 0.00475 ≈ 每格 2 屏幕像素, 800 格宽 ≈ 3.8 单位(宽屏手机也盖得住)。
	## ★★2026-10-04 两角海带丛整体下压 45 格(贴图本身改了, 不是参数): 探针 `tests/_probe_fg_corner`
	##   把龟摆到可活动椭圆底部左/右弧上逐角度量「立绘被前景盖住的像素比例」——
	##   原图在 130°~145° 盖住 54%~86%(左)/ 31%~68%(右, 镜像), 下压后最坏 6.5%(只擦到脚)。
	var _one: bool = cfg.has("fg_band_px")
	var n := 1 if _one else 2
	var _gain: float = float(cfg.get("fg_band_gain", 1.0))
	## ★2026-10-04 `fg_band_layer_gain` = [近, 中, 远] 各层单独增益(主题给; 不给 ⇒ 贴图原样, 一个像素不变)。
	##   由来: 深礁主题色接近黑, 远层(灰度 ~0.66~0.94)乘出来实拍中位亮度只有 22/255、
	##   中层被暗角压到 0 ⇒ 三层读成一坨。modulate 是乘法、对三层一视同仁, 拉不开层次 ⇒ 改贴图灰度。
	var _lg: Array = cfg.get("fg_band_layer_gain", [])
	if _lg.size() == 3:
		var _lifted: Array = _fg_band_layer_lift(tex, _lg)
		tex = _lifted[0]
		_gain *= float(_lifted[1])
	var _made: Array = []
	for i in range(n):
		var q := Sprite3D.new()
		q.texture = tex
		q.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		q.shaded = false
		q.transparent = true
		q.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		q.pixel_size = float(cfg["fg_band_px"]) if _one else 0.0055 * rng.randf_range(0.96, 1.10)
		## 相机局部坐标: x 横向铺三段(互相重叠), y 压在画面下沿, z 最近。
		## ★fg_band_y: 草尖高的剪影带(2026-10-03 fg_grass_band)放在 -0.54 会盖住下沿交战的龟 ⇒ 主题可往下压。
		var _x: float = 0.0 if _one else (float(i) - 0.5) * 1.05
		var _jy: float = 0.0 if _one else rng.randf_range(-0.03, 0.03)
		q.position = Vector3(_x, float(cfg.get("fg_band_y", -0.54)) + _jy, -2.35)
		var sx: float = (-1.0 if i == 1 else 1.0)          # 中段镜像, 破平铺感
		q.scale = Vector3(sx, 1.0, 1.0)
		## ★压暗: 前景是**剪影**不是主角(咩咩的前景草带实测比场内暗一大截)。
		var bl: float = 0.40 if _one else rng.randf_range(0.34, 0.46)
		## ★贴图已清成纯白剪影(原图是靛蓝 + 品红噪点 + 白高光, 四版共用 ⇒ 暗林前景是蓝紫带亮点);
		##   颜色由主题给(fg_band_col), 小幅明暗抖动保留。
		var _fc: Color = cfg.get("fg_band_col", Color(0.06, 0.06, 0.09))
		var _m: float = bl / 0.40 * _gain
		q.modulate = Color(_fc.r * _m, _fc.g * _m, _fc.b * _m)
		q.sorting_offset = 8.0                              # 压在所有东西前面
		q.set_meta("fg_band", img)                          # 打标: 判据按它认前景带(分层增益后贴图换成 ImageTexture, 没有路径可认)
		battle._cam.add_child(q)
		_made.append(q)
		## ★2026-10-05 镜头可达范围: 单张整幅宽 3.8 单位, 而 20:9(2.22) 手机在 z=-2.35 处可见宽就是 3.80 ——
		##   再宽一点的屏(21:9 = 2.33)两边就露出带子的断头。左右各补一张**镜像**(镜像 ⇒ 接缝两侧是同一列像素, 无缝),
		##   ≤2.17 的屏上它们完全在画面外 ⇒ 默认画面一个像素不变。判据 `verify_cam_extent` ④。
		if _one:
			var bw: float = float(tex.get_width()) * q.pixel_size
			for sgn in [-1.0, 1.0]:
				var fl: Sprite3D = q.duplicate()
				fl.position = q.position + Vector3(sgn * bw, 0.0, 0.0)
				fl.scale = Vector3(-q.scale.x, 1.0, 1.0)
				fl.set_meta("fg_band", img)
				fl.set_meta("fg_band_flank", true)
				battle._cam.add_child(fl)
				_made.append(fl)
	## ★★2026-10-07 用户「前景海草那一层改成跟着场地走，不再是贴在屏幕上的一条」:
	##   挂在相机上 ⇒ 拖动/缩放时它钉在屏幕下沿(录屏里像一条贴纸, 放大后底部还露出硬边)。
	##   ⇒ 摆好之后把它们**按相机为中心等比推到地面深度**再挂进世界: 默认机位下屏上一个像素不变,
	##     之后平移/缩放时它和地面以同样的视差移动、同样变大变小。见 `_fg_band_to_world`。
	if not _made.is_empty():
		_fg_band_to_world.call_deferred(_made)


## 把挂在相机上的前景带搬进世界(见 `_build_foreground_band` 末尾的说明)。
## ★以相机为中心做**等比缩放**(位移 × f、pixel_size × f): 从相机看过去每个像素的方向都不变 ⇒ 默认机位画面不变。
## ★f 取主带中心那条视线打到地面(y = FG_GROUND_Y)的距离 ÷ 原距离; 两侧镜像补带用**同一个** f, 接缝不错位。
const FG_GROUND_Y := 0.0
func _fg_band_to_world(bands: Array) -> void:
	var cam: Camera3D = battle._cam
	if cam == null or not is_instance_valid(cam) or battle._world == null:
		return
	var cpos: Vector3 = cam.global_position
	var main: Sprite3D = null
	for q in bands:
		if is_instance_valid(q) and not (q as Node).has_meta("fg_band_flank"):
			main = q
			break
	if main == null:
		return
	var d: Vector3 = main.global_position - cpos
	if d.y >= -0.0001:
		return                                          # 视线不朝下(不该发生): 留在相机上, 不冒险
	var t: float = (FG_GROUND_Y - cpos.y) / d.y         # 视线打到地面的参数(以原距离为 1)
	var f: float = maxf(1.0, t)
	for q in bands:
		if not is_instance_valid(q):
			continue
		var sq := q as Sprite3D
		var gt: Transform3D = sq.global_transform
		sq.get_parent().remove_child(sq)
		battle._world.add_child(sq)
		sq.global_transform = Transform3D(gt.basis, cpos + (gt.origin - cpos) * f)
		sq.pixel_size *= f
		## ★推到地面深度后下半截在地面之下 ⇒ 不关深度测试会被地面挡掉(实拍整条带消失)。它本来就是「压在所有东西前面」的剪影。
		sq.no_depth_test = true
		sq.set_meta("fg_band_world", true)


## 前景剪影带的分层增益: 灰度贴图按层(近 < FG_LAYER_MID_FROM ≤ 中 < FG_LAYER_FAR_FROM ≤ 远)各乘一个系数。
## ★为了不削顶(远层最亮格 240 × 2 会溢出 255): 贴图里除以最大系数 K, 再把 K 还给 modulate ⇒ 返回 [新贴图, K]。
## 阈值按 fg_sea_band 的实际灰阶定: 近 56/68/69 · 中 82~134 · 远 157~240(三层之间有空档)。
const FG_LAYER_MID_FROM := 75
const FG_LAYER_FAR_FROM := 150

func _fg_band_layer_lift(tex: Texture2D, lg: Array) -> Array:
	var img: Image = tex.get_image()
	if img == null:
		push_warning("[fg_band] 取不到贴图像素, 分层增益不生效")
		return [tex, 1.0]
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var k_near: float = float(lg[0])
	var k_mid: float = float(lg[1])
	var k_far: float = float(lg[2])
	var kmax: float = maxf(k_near, maxf(k_mid, k_far))
	var d: PackedByteArray = img.get_data()
	for i in range(0, d.size(), 4):
		if d[i + 3] == 0:
			continue
		var g: int = d[i]
		var k: float = k_near if g < FG_LAYER_MID_FROM else (k_mid if g < FG_LAYER_FAR_FROM else k_far)
		var v: int = clampi(int(round(float(g) * k / kmax)), 0, 255)
		d[i] = v
		d[i + 1] = v
		d[i + 2] = v
	var out := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)
	return [ImageTexture.create_from_image(out), kmax]


func _build_theme_decorations(root: Node3D) -> void:
	var cfg: Dictionary = ArenaTheme.cfg()
	var props: Array = cfg.get("ring_props", [])
	if props.is_empty() or str(props[0]).begins_with("("):
		_build_decorations(root)       # ★`base`(现状) 走老的那张坐标表, 一个像素不动
		return
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var rx: float = A.size.x * 0.5
	var ry: float = A.size.y * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	## ★★具名容器: 判据 `verify_arena_density` **只量这一层**。
	##   第一版判据捞的是全场所有 Sprite3D(边框密植 + 中景 + 远景光斑 + 本层 = 214 个),
	##   主题环只占一小部分 ⇒ 把本层的散布半径从 118 改到 900(簇彻底消失)**判据照样绿**。
	##   「判据没错, 但被测对象被稀释了」—— 必须把被测对象单独圈出来。
	var ring_root := Node3D.new()
	ring_root.name = "ThemeRing"
	root.add_child(ring_root)
	var dens: float = float(cfg.get("ring_density", 1.0))
	var clusters: int = int(round(11.0 * dens))          # 簇数
	var per: int = 7                                     # 每簇件数上限 ⇒ 约 70~90 件, 对齐参考中位 79
	## ★主题可压每簇件数(ring_per): 巨树干一簇 7 棵挤成一堵墙, 参考里是一棵棵分开站的。
	var per_min: int = mini(3, int(cfg.get("ring_per", per)))
	per = int(cfg.get("ring_per", per))
	var _ring_k := 0
	for i in range(clusters):
		## 簇心: 环上均匀取角, 再加抖动; 半径 1.04~1.30 倍 ⇒ 落在岛外的海面/岸上
		## ★★角度**偏向上下**而不是环上均匀: 实测 ARENA 投到 1280×720 后
		##   左右几乎没有可见余量(左 x=11~179 / 右 x=1101~1269, 还被侧边栏压着),
		##   而上有 205px、下有 124px。均匀撒的话一大半件数落在屏幕外 = 白做。
		##   做法: 角度先均匀取, 再往 ±90°(上下)**挤** —— `asin` 重映射把密度压到两极。
		var th0: float = TAU * (float(i) + rng.randf_range(-0.28, 0.28)) / float(clusters)
		var s: float = sin(th0)
		var th: float = asin(clampf(signf(s) * pow(absf(s), 0.45), -1.0, 1.0))
		if cos(th0) < 0.0:
			th = PI - th
		## ★半径收到 1.02~1.16: 1.30 把簇心推到画面外(第一版实拍基本看不见)
		## ★主题可把整圈收到平台边沿(ring_r): 摆在岛外黑海面上的物件脚下没有地, 透视一抬就飘到画面上方。
		var _rr: Array = cfg.get("ring_r", [1.02, 1.16])
		var rr: float = rng.randf_range(float(_rr[0]), float(_rr[1]))
		## ★`ring_avoid_bottom`: 高大的框边物(树干)落在**下方正中**会站进画面挡住战场
		##   (V1 第一版实拍: 几棵树干立在岛面下半部中间)。参考里树干在左右两侧与上方。
		if bool(cfg.get("ring_avoid_bottom", false)) and sin(th) > 0.35 and absf(cos(th)) < 0.75:
			continue
		var cxp: float = c.x + cos(th) * rx * rr
		var cyp: float = c.y + sin(th) * ry * rr
		var n: int = rng.randi_range(per_min, per)
		for _j in range(n):
			## 簇内散布: 半径很小才成"组"; 大了就又摊成均匀
			var a2: float = rng.randf_range(0.0, TAU)
			var d2: float = rng.randf_range(0.0, 1.0)
			d2 = sqrt(d2) * float(cfg.get("ring_spread", 118.0))
			var px: float = cxp + cos(a2) * d2
			var py: float = cyp + sin(a2) * d2 * 0.62      # 俯视压扁
			## ★prop_cycle(同 _build_layout_props): 轮流挑, 不让随机数把一款摆成大多数。不给 ⇒ 原随机挑法(暗林逐值不变)。
			var img: String
			if bool(cfg.get("prop_cycle", false)):
				img = str(props[_ring_k % props.size()])
				_ring_k += 1
			else:
				img = str(props[rng.randi_range(0, props.size() - 1)])
			var path: String = "res://assets/sprites/map/themes/%s.png" % img
			if not ResourceLoader.exists(path):
				continue
			## ★高度由主题给: 参考里框边的东西**比角色大好几倍**(树干/巨叶), 原来固定 1.1~2.0 米太小。
			var _rh: Array = cfg.get("ring_h", [1.1, 2.0])
			## ★按素材名单独给高度(ring_h_of = {素材名: [lo, hi]}): 树干/海草要高, 贝壳这类矮物件按同一高度会大到压进战场。
			var _rho: Dictionary = cfg.get("ring_h_of", {})
			if _rho.has(img):
				_rh = _rho[img]
			var h: float = rng.randf_range(float(_rh[0]), float(_rh[1]))
			var spr = battle._map_billboard(path, Vector2(px, py), h)
			var sc: float = rng.randf_range(0.80, 1.25)
			spr.scale = Vector3(sc * (-1.0 if rng.randf() < 0.5 else 1.0), sc, sc)
			var b: float = rng.randf_range(0.82, 1.0)
			spr.modulate = Color(b, b * 0.98, b * 0.96)
			## ★主题按素材名着色(ring_mod = {素材名: Color}), 让同一件新素材进别的色调世界; 没写的不动。
			var _rm: Dictionary = cfg.get("ring_mod", {})
			if _rm.has(img):
				spr.modulate = spr.modulate * (_rm[img] as Color)
			ring_root.add_child(spr)
			## ★按素材名加辉光(ring_glow_of = {素材名: Color}): anchordeep_010/011 的珍珠是**发光的**,
			##   一团柔白光晕把周围照亮; 只有贴图没有光 = 一颗白球。
			var _rg: Dictionary = cfg.get("ring_glow_of", {})
			if _rg.has(img):
				ring_root.add_child(_glow_puff(Vector2(px, py), _rg[img] as Color, h * sc))


## ═══ 2026-10-04 主题剩下的四层: 挡路障碍外观 / 中景灌木团 / 吊灯 / 灯旁火星 ═══
## 方案书 `docs/plans/20261003-四版完整地图.md` §4.4 第 4 条「把主题真的画出来」。
## ★每一层挂**具名容器**(ThemeObstacle / ThemeMid / ThemeHangLamps / ThemeAmbient),
##   判据 `verify_arena_layers_drawn` / `verify_island_ambient` 只量这些容器(memory `fb-new-layer-must-prove-its-path-runs`)。
## ★base 一律不给对应的键 ⇒ 每个函数开头就 return, 一件不加。

const THEME_TEX := "res://assets/sprites/map/themes/%s.png"
var _img_cache: Dictionary = {}
var _flame_cache: Dictionary = {}


func _tex_img(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var k: String = tex.resource_path
	if k != "" and _img_cache.has(k):
		return _img_cache[k]
	var im: Image = tex.get_image()
	if im == null:
		return null
	if im.is_compressed():
		im.decompress()
	if k != "":
		_img_cache[k] = im
	return im


func _cam_basis() -> Basis:
	if battle._cam == null:
		return Basis()
	return battle._cam.global_transform.basis if battle._cam.is_inside_tree() else battle._cam.transform.basis


## 公告板精灵上第 (px, py) 个贴图像素在世界里的位置(Sprite3D 默认 centered; 公告板的轴 = 相机的右/上)。
## ★Sprite3D 的 offset 以像素计、y 向上: 贴图第 py 行落在本地 y = offset.y + h/2 - py。
func sprite_px_world(s: Sprite3D, px: float, py: float) -> Vector3:
	var w: float = float(s.texture.get_width())
	var h: float = float(s.texture.get_height())
	var lx: float = s.offset.x + px - w * 0.5
	var ly: float = s.offset.y + h * 0.5 - py
	var b: Basis = _cam_basis()
	var o: Vector3 = s.global_position if s.is_inside_tree() else s.position
	return o + (b.x * lx * s.scale.x + b.y * ly * s.scale.y) * s.pixel_size


## ★2026-10-04 主题可给自己的「光源像素」色域(flame_rgb = {"r": [lo, hi], "g": [..], "b": [..]}, 开区间):
##   深礁的灯是发绿光的藻/珍珠, 不是火 —— 暖色判据一个像素都认不出来, 吊灯就没有光、也没有浮游光点。
##   不给 ⇒ 原暖色判据(暗林/紫墟/赤林), 逐值不变。
const FLAME_RGB_WARM := {"r": [0.85, 2.0], "g": [0.30, 0.85], "b": [-1.0, 0.45]}


## 灯具贴图里「火」的像素重心(亮暖色像素)。找不到 ⇒ (-1,-1), 调用方跳过(火星必须有火源)。
func _flame_px(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2(-1, -1)
	var k: String = tex.resource_path
	if _flame_cache.has(k):
		return _flame_cache[k]
	var im: Image = _tex_img(tex)
	var out := Vector2(-1, -1)
	var fr: Dictionary = ArenaTheme.cfg().get("flame_rgb", FLAME_RGB_WARM)
	var r0: float = float(fr["r"][0])
	var r1: float = float(fr["r"][1])
	var g0: float = float(fr["g"][0])
	var g1: float = float(fr["g"][1])
	var b0: float = float(fr["b"][0])
	var b1: float = float(fr["b"][1])
	if im != null:
		var sx := 0.0
		var sy := 0.0
		var n := 0
		var hits: Array = []
		for y in range(im.get_height()):
			for x in range(im.get_width()):
				var c: Color = im.get_pixel(x, y)
				if c.a > 0.5 and c.r > r0 and c.r < r1 and c.g > g0 and c.g < g1 and c.b > b0 and c.b < b1:
					sx += float(x) + 0.5
					sy += float(y) + 0.5
					n += 1
					hits.append(Vector2i(x, y))
		if n > 0:
			out = Vector2(sx / float(n), sy / float(n))
			## ★2026-10-04 光源是一圈(光球外圈亮、正中发白)时重心落在圈心, 周围 3×3 一格光源色都没有 ⇒
			##   这种情况才吸附到最近的光源像素。3×3 里有光源像素(暗林那几盏都是)就原样不动, 暗林逐值不变。
			var ci := Vector2i(int(floor(out.x)), int(floor(out.y)))
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if hits.has(ci + Vector2i(dx, dy)):
						near = true
			if not near:
				var best: Vector2i = hits[0]
				for h in hits:
					if Vector2(h).distance_squared_to(out) < Vector2(best).distance_squared_to(out):
						best = h
				out = Vector2(float(best.x) + 0.5, float(best.y) + 0.5)
	_flame_cache[k] = out
	return out


## ★2026-10-04 布局表(ArenaTheme.LAYOUT)里有一格物件堆正好落在下墙的碰撞椭圆上(u0.28 v0.44 = 中心 +235,+198),
##   两张图叠在一起读作「一坨带刺的东西」—— 正是暗林留下的差距「障碍外观要和角色轮廓分得开」。
##   布局表四版共用, 改表会动暗林 ⇒ 主题开 layout_clear_obstacles 才把**落在障碍碰撞椭圆附近(见下)**的
##   布局物件和它的接地影删掉。障碍要等本函数才有, 所以在这里清, 不在摆布局时清。不给 ⇒ 一件不动(暗林/base 不变)。
## ★「叠在一起」是屏幕上的事: 那堆东西其实站在下墙**身后** 1.9 个 ry(探针实测), 立起来的图往上画, 被墙压住下半截。
##   ⇒ 横向放大 1.3 倍、纵深放大 2.5 倍的椭圆(纵深方向是屏幕上下)。
func _clear_layout_on_obstacles() -> void:
	if not bool(ArenaTheme.cfg().get("layout_clear_obstacles", false)):
		return
	var lp: Node = battle._world.find_child("LayoutProps", true, false)
	if lp == null:
		return
	for ch in lp.get_children():
		if not (ch is Node3D):
			continue
		var p: Vector3 = (ch as Node3D).position
		for ob in battle._obstacles:
			var o3: Vector3 = battle._world_pos(ob["c"], 0.0)
			var dx: float = (p.x - o3.x) / (float(ob["rx"]) * battle.WS * 1.3)
			var dz: float = (p.z - o3.z) / (float(ob["ry"]) * battle.WS * 2.5)
			if dx * dx + dz * dz < 1.0:
				ch.set_meta("cleared_on_obstacle", true)
				ch.visible = false
				ch.queue_free()
				break


## 挡路障碍换外观: 按**原图的视觉宽**反推主题素材的高度 ⇒ 看起来多宽就挡多宽(footprint 一个数不动)。
func _theme_obstacle(ob: Dictionary, spec, idx: int) -> Node3D:
	var cfg: Dictionary = ArenaTheme.cfg()
	var nm: String = str(spec[idx % (spec as Array).size()]) if spec is Array else str(spec)
	var path: String = THEME_TEX % nm
	var base_path: String = "res://assets/sprites/map/%s.png" % str(ob["img"])
	var base_tex: Texture2D = load(base_path) if ResourceLoader.exists(base_path) else null
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var holder := Node3D.new()
	holder.name = "ThemeObstacle"
	if tex == null or base_tex == null:
		push_warning("[theme_obstacle] 素材缺失: %s —— 退回原礁石(不做静默替换)" % path)
		holder.add_child(battle._map_billboard(base_path, ob["c"], float(ob["h"])))
		return holder
	## 原图视觉宽(米) = 图宽 × (h ÷ 图高); 主题素材已裁到包围盒 ⇒ 同宽 = 同 footprint 口径
	var vis_w: float = float(base_tex.get_width()) * float(ob["h"]) / float(base_tex.get_height())
	var h: float = vis_w * float(tex.get_height()) / float(tex.get_width())
	var _ps: float = float(cfg.get("prop_shadow", 0.0))
	if _ps > 0.0:
		holder.add_child(_contact_shadow(ob["c"], _ps, vis_w * 1.1))
	var s: Sprite3D = battle._map_billboard(path, ob["c"], h)
	s.modulate = cfg.get("obstacle_mod", Color(1, 1, 1))
	s.set_meta("vis_w", vis_w)
	holder.add_child(s)
	return holder


## 中景: 平台**上沿**一圈暗色灌木团, 站在边沿上、在巨树干身后(参考 mixed_033/034 平台外两角的暗绿灌木团)。
## ★只摆上半圈(屏幕上方 = 离镜头远): 下半圈的大件会挡住身后的龟(2026-10-04 实拍教训)。
## ★不摆到岛外黑海面上: 半径 ≤ mid_r 上限(用户 2026-10-03「装饰物乱飞到上面」)。
func _build_theme_midground(root: Node3D) -> void:
	var cfg: Dictionary = ArenaTheme.cfg()
	var names: Array = cfg.get("mid_props", [])
	var n: int = int(cfg.get("mid_n", 0))
	if n <= 0 or names.is_empty():
		return
	var paths: Array = []
	for nm in names:
		if ResourceLoader.exists(THEME_TEX % str(nm)):
			paths.append(THEME_TEX % str(nm))
	if paths.is_empty():
		push_warning("[theme_mid] 中景素材一张都没有 —— 不铺")
		return
	var mid := Node3D.new()
	mid.name = "ThemeMid"
	root.add_child(mid)
	var A: Rect2 = battle.ARENA
	var c: Vector2 = A.position + A.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	var arc: Array = cfg.get("mid_arc", [205.0, 335.0])
	var rr_lim: Array = cfg.get("mid_r", [1.02, 1.10])
	var hr: Array = cfg.get("mid_h", [2.0, 2.8])
	var _ps: float = float(cfg.get("prop_shadow", 0.0))
	for i in range(n):
		var th: float = deg_to_rad(lerpf(float(arc[0]), float(arc[1]), (float(i) + rng.randf_range(0.25, 0.75)) / float(n)))
		var rr: float = rng.randf_range(float(rr_lim[0]), float(rr_lim[1]))
		var p := Vector2(c.x + cos(th) * A.size.x * 0.5 * rr, c.y + sin(th) * A.size.y * 0.5 * rr)
		var s: Sprite3D = battle._map_billboard(str(paths[i % paths.size()]), p, rng.randf_range(float(hr[0]), float(hr[1])))
		if rng.randf() < 0.5:
			s.scale = Vector3(-1.0, 1.0, 1.0)
		s.modulate = cfg.get("mid_mod", Color(1, 1, 1))
		mid.add_child(s)
		if _ps > 0.0 and s.texture != null:
			mid.add_child(_contact_shadow(p, _ps, s.pixel_size * float(s.texture.get_width()) * 0.9))


## 吊灯: 铁支架**钉在巨树干上**挂一盏船灯(参考 Darkwood 的红光挂在平台外的暗林里)。
## ★★2026-10-03 第一版「悬在黑里的红光」被用户指为乱飞(没有挂点) ⇒ 撤了。这版每盏都有宿主树干:
##   支架底板的像素 = 宿主树干那一行**最靠屏幕右侧的不透明像素**往里收 2 格 —— 判据逐盏验「底板压在树皮上」。
## ★不镜像: 永远挂在树干的屏幕右侧, 支架底板在灯图的左沿(素材朝向), 镜像就成了「灯挂在空中、支架朝外」。
func _build_hang_lamps(root: Node3D) -> void:
	var cfg: Dictionary = ArenaTheme.cfg()
	var texs: Array = cfg.get("hang_lamp_tex", [])
	var n: int = int(cfg.get("hang_lamps", 0))
	var hosts: Array = cfg.get("hang_on", [])
	if n <= 0 or texs.is_empty() or hosts.is_empty():
		return
	var ring: Node = root.find_child("ThemeRing", true, false)
	if ring == null:
		push_warning("[hang_lamps] 找不到 ThemeRing —— 没有树干可挂, 不挂(不许悬空)")
		return
	var cz: float = battle._world_pos(battle.ARENA.position + battle.ARENA.size * 0.5, 0.0).z
	var cand: Array = []
	for t in ring.get_children():
		if t is Sprite3D and t.texture != null and t.global_position.z < cz \
				and hosts.has(t.texture.resource_path.get_file().get_basename()):
			cand.append(t)
	if cand.is_empty():
		push_warning("[hang_lamps] 上半圈没有可挂的树干")
		return
	cand.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	var hang := Node3D.new()
	hang.name = "ThemeHangLamps"
	root.add_child(hang)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var at: Array = cfg.get("hang_at", [0.30, 0.40])
	var lamp_h: float = float(cfg.get("hang_lamp_h", 0.9))
	var b: Basis = _cam_basis()
	var k_n: int = mini(n, cand.size())
	for k in range(k_n):
		var t: Sprite3D = cand[int(round(float(k) * float(cand.size() - 1) / float(maxi(1, k_n - 1))))]
		var im: Image = _tex_img(t.texture)
		if im == null:
			continue
		var row: int = clampi(int(float(im.get_height()) * (1.0 - rng.randf_range(float(at[0]), float(at[1])))), 0, im.get_height() - 1)
		var xmin := -1
		var xmax := -1
		for x in range(im.get_width()):
			if im.get_pixel(x, row).a > 0.5:
				if xmin < 0:
					xmin = x
				xmax = x
		if xmin < 0:
			continue
		## 屏幕右侧那一格: 没镜像取 xmax; 镜像(scale.x<0)后 xmin 才在右边。往树干里收 2 格, 底板压在树皮上。
		## ★2026-10-04 最外侧那格可能是一根伸出去的藤/一块掉落的碎石(紫墟断柱实测: 底板落在空像素上)
		##   ⇒ 从屏幕右侧往里找**连续 3 格不透明**的第一段, 取它往里第 3 格。轮廓实心时与原算法逐格相同(暗林不变)。
		var edge_px: float = -1.0
		if t.scale.x > 0.0:
			for x in range(xmax, xmin + 1, -1):
				if im.get_pixel(x, row).a > 0.5 and im.get_pixel(x - 1, row).a > 0.5 and im.get_pixel(x - 2, row).a > 0.5:
					edge_px = float(x) - 1.5
					break
		else:
			for x in range(xmin, xmax - 1):
				if im.get_pixel(x, row).a > 0.5 and im.get_pixel(x + 1, row).a > 0.5 and im.get_pixel(x + 2, row).a > 0.5:
					edge_px = float(x) + 2.5
					break
		if edge_px < 0.0:
			continue
		var edge_w: Vector3 = sprite_px_world(t, edge_px, float(row) + 0.5)
		var lt_path: String = THEME_TEX % str(texs[k % texs.size()])
		if not ResourceLoader.exists(lt_path):
			continue
		var lt: Texture2D = load(lt_path)
		var lim: Image = _tex_img(lt)
		## 支架底板 = 灯图最左一列的不透明像素(纵向取中)
		var pl_x := -1
		var ys: Array = []
		for x in range(lim.get_width()):
			for y in range(lim.get_height()):
				if lim.get_pixel(x, y).a > 0.5:
					ys.append(y)
			if not ys.is_empty():
				pl_x = x
				break
		if pl_x < 0:
			continue
		var pl_y: float = (float(ys[0]) + float(ys[ys.size() - 1])) * 0.5 + 0.5
		var s := Sprite3D.new()
		s.name = "HangLamp"
		s.texture = lt
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.pixel_size = lamp_h / float(lt.get_height())
		var lx: float = float(pl_x) + 0.5 - float(lt.get_width()) * 0.5
		var ly: float = float(lt.get_height()) * 0.5 - pl_y
		s.position = edge_w - (b.x * lx + b.y * ly) * s.pixel_size + b.z * 0.06   # 往镜头挪一点, 画在树干前面
		s.set_meta("host", t)
		s.set_meta("plate_px", Vector2(float(pl_x) + 0.5, pl_y))
		hang.add_child(s)
		_flames.append(s)
		var fp: Vector2 = _flame_px(lt)
		if fp.x >= 0.0:
			var L := OmniLight3D.new()
			L.light_color = cfg.get("light_col", LAMP_COL)
			L.light_energy = float(cfg.get("hang_light_energy", 1.2))
			L.omni_range = float(cfg.get("hang_light_range", 2.6))
			L.shadow_enabled = false
			hang.add_child(L)
			L.global_position = sprite_px_world(s, fp.x, fp.y)
			## 灯罩外一圈加性光晕: 点光只照得亮树皮, 暗底上看不出「这里有一盏灯」(第一版实拍只有 20px 的暗点)
			var gl := Sprite3D.new()
			gl.name = "HangGlow"
			var gg := Gradient.new()
			var lc: Color = cfg.get("light_col", LAMP_COL)
			gg.set_color(0, Color(lc.r, lc.g, lc.b, 0.55))
			gg.set_color(1, Color(lc.r, lc.g, lc.b, 0.0))
			var gt := GradientTexture2D.new()
			gt.gradient = gg
			gt.fill = GradientTexture2D.FILL_RADIAL
			gt.fill_from = Vector2(0.5, 0.5)
			gt.fill_to = Vector2(1.0, 0.5)
			gt.width = 64
			gt.height = 64
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			gm.albedo_texture = gt
			gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			gl.texture = gt
			gl.material_override = gm
			gl.pixel_size = lamp_h * 1.6 / 64.0
			gl.set_meta("host", t)   # 光晕跟灯一样吊在宿主树干上(落地点 = 宿主的脚)
			hang.add_child(gl)
			gl.global_position = L.global_position + b.z * 0.03


## 主题氛围粒子 = **灯旁火星**: 每个登记过的火源冒几颗短命火星, 不满场撒。
## ★为什么是这样(方案书 §4.5-2「动态只删错的, 不凭空造新动态」):
##   删掉的是满场往上飘的气泡 + 冰蓝辉光(水下的东西); 留下的只有「火上方有火星」这一条**有因**的动态,
##   每颗只活约 1 秒、升不过半米 —— 不会读成「气泡往上飘」。参数没有视频标定过, 只取量级。
## ★不开(ambient_lamp_embers 不给)的主题只建一个空容器: 「删掉错的」对四版都成立, 「加火星」只给已做到位的暗林。
func _build_theme_ambient(root: Node3D) -> void:
	var cfg: Dictionary = ArenaTheme.cfg()
	var amb := Node3D.new()
	amb.name = "ThemeAmbient"
	root.add_child(amb)
	if not bool(cfg.get("ambient_lamp_embers", false)):
		return
	var col: Color = cfg.get("ambient_col", Color(1.0, 0.55, 0.25, 0.8))
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, col.a))
	g.set_color(1, Color(col.r, col.g * 0.5, col.b * 0.3, 0.0))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	## ★BILLBOARD_PARTICLES 才吃每颗粒子的 scale; 用 ENABLED 会丢掉 scale ⇒ 每颗都是 1 米大的方块(第一版实拍)。
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var dot := GradientTexture2D.new()          # 圆点(中心实·边缘透), 不是方块
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dg.add_point(0.45, Color(1, 1, 1, 0.9))
	dot.gradient = dg
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 16
	dot.height = 16
	mat.albedo_texture = dot
	for f in _flames:
		if not is_instance_valid(f) or not (f is Sprite3D) or f.texture == null:
			continue
		var fp: Vector2 = _flame_px(f.texture)
		if fp.x < 0.0:
			continue
		var e := CPUParticles3D.new()
		e.name = "Embers"
		e.amount = int(cfg.get("ember_amount", 3))
		e.lifetime = 1.1
		e.local_coords = false
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = 0.06
		e.direction = Vector3(0, 1, 0)
		e.spread = 25.0
		e.initial_velocity_min = 0.12
		e.initial_velocity_max = 0.32
		e.gravity = Vector3(0, 0.10, 0)
		e.scale_amount_min = 0.6
		e.scale_amount_max = 1.0
		e.color_ramp = g
		var q := QuadMesh.new()
		q.size = Vector2(0.07, 0.07)   # 一颗火星 ≈ 7 厘米 ≈ 屏上 2~3 像素
		e.mesh = q
		e.material_override = mat
		e.set_meta("flame", f)
		amb.add_child(e)
		e.global_position = sprite_px_world(f, fp.x, fp.y)


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
	## ★主题(no_base_midground)关掉以下全部水下专用远景: 海带剪影带 / 水面光柱 / 鱼群 / 气泡柱。
	##   它们是默认画面(水下)的东西, 不看主题照画 ⇒ 四版顶上一直挂着光柱(用户 2026-10-03 指出)。
	var _uw: bool = not bool(ArenaTheme.cfg().get("no_base_midground", false))
	if _uw:
		_build_backdrop_thicket(holder)     # ★②a 密集竖直剪影带(2026-09-18, 见该函数长注)

	# ── ②b 远景发光群(珊瑚/海葵/海带) ──────────────────────────
	# 剪影只有轮廓没有"生气"。加一层加性发光的小点缀, 让远处天际线有光斑闪烁感,
	# 这也是深海题材最能出氛围的一笔。
	var glows = ["glow-coral", "glow-anem", "glow-kelp"]
	## ★海底发光群(珊瑚/海葵/海带)只属于水下设定。主题的远景是「沉进黑」就不画 ——
	##   V1 实拍顶上还飘着鱼和紫色光点, 就是这一层。base(现状) 照画, 一个像素不动。
	## ★只有水下类远景(base 的 undersea / 深礁的 deep_glow)才画; 其余主题(暗林/紫墟/赤林)一律不画。
	##   第一版只判 into_black, V3/V4 换了别的远景做法就会把珊瑚光点又放出来。
	if not (str(ArenaTheme.cfg().get("bg_kind", "undersea")) in ["undersea", "deep_glow"]):
		glows = []
	## ★主题一律不画: 远处半空的紫海葵/珊瑚光点读作「悬在天上」(用户 2026-10-03 指出)。
	if bool(ArenaTheme.cfg().get("no_base_midground", false)):
		glows = []
	var grng = RandomNumberGenerator.new()
	grng.seed = 20260722
	for i in range(14 if not glows.is_empty() else 0):   # ★远景发光 22→14(点2: 减重复的发光刷屏); 主题清空时整段不跑(否则 i % 0)
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
	for i in range(6 if _uw else 0):
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
	if _uw:
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

## 远景的【深度→颜色】斜坡: 0 = 最近(贴 bg_top), 1 = 最远(贴 bg_horizon)。
## 允许传 <0 / >1 外推, 因为远地形与天际光斑本来就比三层剪影更近/更远。
##
## ★★为什么做成一条斜坡而不是每层填一个色: 换主题时只要给两个端点,
##   中间全自动跟着走 —— 手填 N 个色必然有一个忘了改(memory `fb-hand-rolled-copies-drift`)。
## ★规律照搬 2026-07-22 第三版的标定结论:「越远越亮、越贴雾色」(水下/雾中远山同理),
##   所以 bg_horizon 必须比 bg_top 亮; 四版的配置都满足这一条。
## ★★★`fallback` 是**必填**的: 主题没给远景端点时, 原样返回该调用点的原字面值。
##   为什么必须这样: `V0_BASE`(现状·已验收) 的全部意义是「什么都没换」, 而这五个远景色
##   (三层剪影 + 远地形近/远 + 天际光斑)**本来就不在一条直线上** —— 拿两个端点的斜坡
##   怎么都推不出它们。我第一版给斜坡填了兜底端点, 结果 base 的远景整体被压暗了,
##   而五条画面判据**照样全绿**(它们量的是统计量, 不是具体某个色) —— 差一点就悄悄改掉了
##   一套已验收的画面。(memory `fb-my-thresholds-degrade-good-assets`)
func _bg_ramp(f: float, fallback: Color) -> Color:
	var c: Dictionary = ArenaTheme.cfg()
	if not (c.has("bg_top") and c.has("bg_horizon")):
		return fallback
	var a: Color = c.get("bg_top", fallback)
	var b: Color = c.get("bg_horizon", fallback)
	return Color(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1.0)


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
		## ★★2026-10-03 三层剪影的颜色改从**主题**推(四版完整地图)。
		##   原值 (0.20,0.30,0.44)/(0.24,0.35,0.48)/(0.28,0.40,0.52) 是 2026-07-22 第三版标定的,
		##   规律是「越远越亮、越贴雾色」(水下远景 = 雾里的亮轮廓, 同雾中远山)。
		##   ⇒ 这里**保住那条规律**, 只把端点换成主题色: 近层贴 bg_top, 远层贴 bg_horizon。
		##   ⚠ 不许各层手填三个色 —— 那样换主题必有一层忘了改(memory `fb-hand-rolled-copies-drift`)。
		{"z": -16.0, "h": 2.5, "col": _bg_ramp(0.00, Color(0.20, 0.30, 0.44)), "span": 73.0},
		{"z": -19.0, "h": 1.7, "col": _bg_ramp(0.50, Color(0.24, 0.35, 0.48)), "span": 78.0},
		{"z": -22.0, "h": 0.9, "col": _bg_ramp(1.00, Color(0.28, 0.40, 0.52)), "span": 82.0},
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
	## ★同三层剪影: 远地形的近/远端色也从主题推, 保住「越远越亮越贴雾色」那条规律。
	var near_col = _bg_ramp(-0.35, Color(0.070, 0.125, 0.190))
	var far_col = _bg_ramp(1.30, Color(0.205, 0.455, 0.520))
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
		var col = _bg_ramp(1.55, Color(0.46, 0.72, 0.86)).lerp(_bg_ramp(0.95, Color(0.30, 0.50, 0.66)), depth)
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
		spr.set_meta("light_shaft", true)   # 打标: 判据 verify_arena_layers_drawn 数「主题里 0 道」(只是元数据, 画面不变)
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
	## ★★2026-10-04 这一层**只属于 base**(现状·已验收): 主题在 `_build_map_props` 里根本不进这里
	##   (满场往上飘的气泡在岛上是错的, 方案书 §4.5-2 点名要删)。主题的氛围粒子在 `_build_theme_ambient`。
	##   原来这里有一张按 ambient_kind 分支的表(沙尘/火星/反光/斜雨), 四版都不再走到这里 ⇒ 删掉, 免得读着像还在生效。
	##   base 的四个值**逐值不变**。
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
	## ★颜色也按主题(base 不给 ⇒ 原值 (1,1,1,0.55) 逐值不变)
	bm.albedo_color = ArenaTheme.cfg().get("ambient_col", Color(1, 1, 1, 0.55))
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
	## ★★寻路图必须【同步】生效(2026-10-04 修回放「约 40 次红 1 次 · 第 360 步校验点 5」)。
	##   Godot 4.6 默认 map / region 都是**异步迭代**: 下面那行 `map_force_update` 对异步图是空操作,
	##   新图要等下一个**物理帧**同步之后 `map_get_path` 才有路 —— 之前一律返回空 ⇒ `_nav_dir` 走直线。
	##   物理帧按**墙钟**走, 不按 sim 步走 ⇒ 开打头几步「直奔还是绕障」取决于建场到开打那几帧真实花了多久:
	##   回放摆位期 8 倍速快进, 建场到开打只隔约 5 帧, 机器快到这 5 帧不满 1/60 秒就分叉。
	##   探针(tests/_probe_nav_sync.gd, --fixed-fps 1000): 默认 ⇒ 建完 6 帧内 iter=0 / path=0;
	##   map+region 关异步后 ⇒ `map_force_update` 当场 iter=1 / path=11。
	##   ⇒ 两个都关异步, 建完当场可用, 与帧率/墙钟无关。门禁: verify_replay_roundtrip V1b。
	NavigationServer2D.map_set_use_async_iterations(battle._nav_map, false)
	battle._nav_region = NavigationServer2D.region_create()
	_own_nav_region = battle._nav_region
	NavigationServer2D.region_set_use_async_iterations(battle._nav_region, false)
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
