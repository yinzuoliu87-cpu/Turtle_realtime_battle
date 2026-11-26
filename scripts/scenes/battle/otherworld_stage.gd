class_name OtherworldStage
extends RefCounted
## otherworld_stage.gd —— 136 千面【里世界】那块场地的画面(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)
##
## 用户 11-26:「需要设计一版地图…里世界…跟现在这个丛林地图是没有关系的…整个场景是阴暗的…你自己看看怎么设计，不是说画面变暗吧？」
##
## ── 设计(构图 / 意图) ───────────────────────────────────────────
##   · 位置: 主岛往远处挪 OtherworldSystem.OW_SHIFT(2600 像素 ≈ 62 米), 大小与主岛相同(技能射程 / 走位空间不变)。
##   · 意图: 「被拽进千面的面具里」—— 一块悬在虚空里的黑曜石平台, 四周什么都没有; 远处悬着几张巨大的面具在看这场决斗。
##   · 层次(由远到近):
##       ① 虚空: 整块深紫黑底, 盖住主岛那边的海(只在里世界附近, 不伸到主岛)
##       ② 远景: 平台后方高处悬着 3 张巨大面具(两种: 裂瓷面具 / 哭泣面具), 逐帧动画(眼光明灭、烟雾飘、上下浮)
##       ③ 平台: 黑曜石地砖平铺, 按岛形裁成椭圆, 边缘碎口带一圈暗紫微光
##       ④ 中央法阵: 紫色符文圆阵, 四个面具符号(千面的「面」)
##       ⑤ 外圈: 6 座鬼火灯台(逐帧火苗) + 4 根断柱, 沿平台边缘摆, 前排两侧留空不挡人
##   · 光: 全是自发光的贴图(不受场景主光影响), 整体压在暗紫、只有法阵 / 鬼火 / 面具眼睛是亮的。
## 素材来源(如实): PixelLab create_image_pro_flash 生成, 动的三样用 animate_image 首尾钉原画; 见 tools/assetgen/pack_mask_art.py。
const DIR := "res://assets/sprites/vfx/"
const GROUND_SH := preload("res://scripts/scenes/battle/shaders/otherworld_ground.gdshader")

var battle
var root: Node3D = null
var _anims: Array = []      # {node, nf, fps}
var _t := 0.0


func _init(b) -> void:
	battle = b


func _tex(n: String) -> Texture2D:
	var p := DIR + n
	return load(p) if ResourceLoader.exists(p) else null


func center3() -> Vector3:
	return battle._world_pos(Vector2(battle._arena_center) + OtherworldSystem.OW_SHIFT, 0.0)


func _spr(tex_name: String, pos: Vector3, h_m: float, hframes: int = 1, fps: float = 0.0) -> Sprite3D:
	var t := _tex(tex_name)
	if t == null:
		return null
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = hframes
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.offset = Vector2(0.0, float(t.get_height()) * 0.5)   # 原点 = 底边
	s.pixel_size = h_m / float(t.get_height())
	s.position = pos
	root.add_child(s)
	if hframes > 1:
		_anims.append({"node": s, "nf": hframes, "fps": fps, "ph": float(_anims.size()) * 0.37})
	return s


func build() -> void:
	if root != null and is_instance_valid(root):
		return
	if battle.get("_world") == null or not is_instance_valid(battle._world):
		return
	root = Node3D.new()
	root.name = "OtherworldStage"
	battle._world.add_child(root)
	var c := center3()
	var ws: float = float(battle.WS)
	var aw: float = battle.ARENA.size.x * ws
	var ah: float = battle.ARENA.size.y * ws
	## ① 虚空(比平台大一圈, 但不伸到主岛: 62 米外)
	var void_m := MeshInstance3D.new()
	var vq := PlaneMesh.new()
	## 往主岛方向(画面上方)伸 45 米、往近处伸 30 米: 盖住镜头里看得到的海(11-26 自查: 顶上露出主图的海浪), 又碰不到 62 米外的主岛
	vq.size = Vector2(aw + 120.0, 75.0)
	void_m.mesh = vq
	var vmat := StandardMaterial3D.new()
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vmat.albedo_color = Color(0.035, 0.02, 0.06)
	void_m.material_override = vmat
	void_m.position = c + Vector3(0.0, -0.4, -7.5)
	root.add_child(void_m)
	## ①b 虚空背板: 平台后方立一堵深紫黑的墙, 挡住镜头远处的海(在主岛镜头的背后, 主世界视角看不到它)
	var wall := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(aw + 160.0, 60.0)
	wall.mesh = wq
	wall.material_override = vmat
	wall.position = Vector3(c.x, 8.0, c.z - ah * 0.5 - 14.0)
	root.add_child(wall)
	## ③ 平台
	var g := MeshInstance3D.new()
	var pq := PlaneMesh.new()
	pq.size = Vector2(aw + 2.0, ah + 2.0)
	g.mesh = pq
	var gm := ShaderMaterial.new()
	gm.shader = GROUND_SH
	gm.set_shader_parameter("tile_tex", _tex("ow-tile.png"))
	gm.set_shader_parameter("tiles", Vector2((aw + 2.0) / 1.28, (ah + 2.0) / 1.28))   # 一块地砖 1.28 米(≈ 50 像素 / 米, 同主岛地面)
	g.material_override = gm
	g.position = c
	root.add_child(g)
	## ④ 中央法阵(贴地)
	var ct := _tex("ow-circle.png")
	if ct != null:
		var cs := Sprite3D.new()
		cs.texture = ct
		cs.shaded = false
		cs.transparent = true
		cs.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		cs.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		cs.axis = Vector3.AXIS_Y
		cs.pixel_size = (ah * 0.78) / float(ct.get_height())
		cs.position = c + Vector3(0.0, 0.02, 0.0)
		cs.modulate = Color(1, 1, 1, 0.85)
		root.add_child(cs)
	## ② 远景巨面具(平台后方高处)
	## 11-26 自查: 原来挂太高被顶栏挡住 ⇒ 压低、往平台后沿靠(整张露在平台和顶栏之间)
	var back_z: float = c.z - ah * 0.5 - 1.5
	_spr("ow-maskA.png", Vector3(c.x - aw * 0.30, -1.2, back_z), 6.5, 8, 6.0)
	_spr("ow-maskB.png", Vector3(c.x + 0.0, -0.6, back_z - 2.5), 8.0, 8, 5.0)
	_spr("ow-maskA.png", Vector3(c.x + aw * 0.32, -1.4, back_z - 0.5), 6.0, 8, 7.0)
	## ⑤ 外圈: 鬼火灯台 6 座 + 断柱 4 根, 沿椭圆边缘(前排正中留空)
	var ang_l := [200.0, 245.0, 295.0, 340.0, 160.0, 20.0]
	for a in ang_l:
		var r: float = deg_to_rad(float(a))
		var p := c + Vector3(cos(r) * aw * 0.46, 0.0, sin(r) * ah * 0.44)
		_spr("ow-brazier.png", p, 3.2, 8, 9.0)
	for a in [225.0, 270.0, 315.0, 180.0]:
		var r2: float = deg_to_rad(float(a) + 12.0)
		var p2 := c + Vector3(cos(r2) * aw * 0.49, 0.0, sin(r2) * ah * 0.49)
		_spr("ow-pillar.png", p2, 4.6)
	## 暗紫点光(只照平台; 贴图是自发光的, 这盏灯给单位身上一点紫边)
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.35, 1.0)
	l.light_energy = 1.4
	l.omni_range = 18.0
	l.position = c + Vector3(0.0, 4.0, 0.0)
	root.add_child(l)


func tick(delta: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	_t += delta
	for a in _anims:
		var n = a["node"]
		if n != null and is_instance_valid(n):
			(n as Sprite3D).frame = int((_t + float(a["ph"])) * float(a["fps"])) % int(a["nf"])


func free_stage() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	_anims.clear()
