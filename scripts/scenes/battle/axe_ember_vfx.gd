class_name AxeEmberVfx
extends RefCounted
## 096 小木斧 · 余烬之斧【处决】—— 天降轨道激光 (2026-09-15 重做)
##
## ★由来: 用户 2026-09-15「9/9处决没余烬的专属特效啊，还是这个特效不明显？我需要你参考lol比较新版本的
##   无限火力里击杀敌人时一道激光从天击中敌人的那种处决」。
##   旧演出(`AxeFinalVfx.ember_execute`, 已删)是一根 0.34×2.6×0.34 米红色 BoxMesh 闪 0.35 秒 ——
##   正是特效纪律禁掉的那一类, 也读不出"从天而降"。
## ★参考: LoL 无限火力「轨道激光」终结特效, 1080p60 实拍逐帧; 分段与尺寸见 `tools/blender_ember_laser.py` 头注,
##   素材逐帧见 docs/studies/20260915d-096余烬处决激光-{光柱,穹顶,地光}逐帧.md。
##
## ★三层**同一条时间轴**: 一个 tween 同时推三张帧表(`apply_frame`), 不会错帧 ——
##   ① 光柱 eq096-ember-laser-beam.png    竖直公告板 BILLBOARD_FIXED_Y(全轴公告板会随相机俯仰倒下去)
##   ② 穹顶 eq096-ember-laser-dome.png    竖直公告板, 整层 45% 透明
##      (锁调色板会把 alpha<24 切掉、其余一律不透明 ⇒ 半透明烤不进去, 只能引擎整层给)
##   ③ 地光 eq096-ember-laser-ground.png  贴地(axis = AXIS_Y 本身就是平铺, 别再转 -90°)
##
## ★结算不在这里(CLAUDE.md §3.5): 处决伤害与 +150 龟能在 `AxeFinalForms.ember_on_hit` 里同步结算,
##   结算完同一个调用里建本演出; 这里只画。帧 0 是击杀闪光 = 目标死掉的那一刻。
const TEX_BEAM := "res://assets/sprites/vfx/eq096-ember-laser-beam.png"
const TEX_DOME := "res://assets/sprites/vfx/eq096-ember-laser-dome.png"
const TEX_GROUND := "res://assets/sprites/vfx/eq096-ember-laser-ground.png"

const N_FRAMES := 32
const FPS := 20.0
const DUR := 1.6                   # = N_FRAMES / FPS
## 像素尺寸 = 龟立绘同一个口径(Blender 0.01 m/像素渲, 像素化缩到 0.0425 m/像素)。
const TEXEL_M := 0.0425
## 帧高(像素): 光柱 626 = 26.6 米 / 穹顶 200 = 8.5 米。
## ★光柱要这么高: 8.5 米帧时柱顶 7.9 米, 战斗镜头里投影在屏幕 y=407/1280(脚在 696),
##   平切的柱顶落在屏幕中上部 = 一根悬空柱子, 读不出从天而降(2026-09-15 门禁量出来的)。
const BEAM_FH := 626
const DOME_FH := 200
## 竖直两层的帧底都在地下 0.6 米(Blender 相机中心 z = 帧高/2 − 0.6) ⇒ 帧中心离地 = 帧高/2 − 0.6。
##   ★地面线必须落在帧底往上 0.6 米处 —— 否则光柱要么悬空、要么冲击点埋进地里(门禁按真像素行量这条)。
const UPRIGHT_GROUND_ABOVE_BOTTOM := 0.6
const BEAM_CENTER_Y := BEAM_FH * TEXEL_M * 0.5 - UPRIGHT_GROUND_ABOVE_BOTTOM
const DOME_CENTER_Y := DOME_FH * TEXEL_M * 0.5 - UPRIGHT_GROUND_ABOVE_BOTTOM
const DOME_ALPHA := 0.45
const GROUND_Y := 0.03

var battle = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


## 演出开始 `t` 秒时该播第几帧。20fps 逐帧, 末帧停住(不 drop 最后一帧)。
static func frame_at(t: float) -> int:
	return clampi(int(floor(t * FPS)), 0, N_FRAMES - 1)


## 把激光根节点下三层同时推到 `t` 秒那一帧。tween 调它, 门禁也直接调它(不等 tween)。
static func apply_frame(root: Node, t: float) -> void:
	if not is_instance_valid(root):
		return
	var f: int = frame_at(t)
	for c in root.get_children():
		if c is Sprite3D:
			(c as Sprite3D).frame = f


func _layer(path: String, upright: bool, center_y: float, prio: int, alpha: float) -> Sprite3D:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = N_FRAMES
	s.frame = 0
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.render_priority = prio
	s.pixel_size = TEXEL_M
	s.modulate = Color(1.0, 1.0, 1.0, alpha)
	if upright:
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.position = Vector3(0.0, center_y, 0.0)
	else:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y
		s.position = Vector3(0.0, center_y, 0.0)
		## ★贴地层要测深度: 站在前面的龟挡住地上的光。第一版三层都不测深度, 录像里整圈地光画在邻居身上。
		##   竖直两层仍不测深度 —— 它们的公告板平面穿过被处决者本身, 测深度会和立绘抢同一深度闪烁。
		s.no_depth_test = false
	return s


## 在被处决者脚下放一道轨道激光。返回根节点(三层都挂在它下面, 播完整个收掉)。
func execute(pos2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	var ground: Sprite3D = _layer(TEX_GROUND, false, GROUND_Y, 6, 1.0)
	var dome: Sprite3D = _layer(TEX_DOME, true, DOME_CENTER_Y, 7, DOME_ALPHA)
	var beam: Sprite3D = _layer(TEX_BEAM, true, BEAM_CENTER_Y, 8, 1.0)
	if ground == null or dome == null or beam == null:
		for s in [ground, dome, beam]:
			if s != null:
				s.free()
		return null
	var root := Node3D.new()
	root.name = "EmberOrbitalLaser"
	root.position = battle._world_pos(pos2d, 0.0)
	ground.name = "Ground"
	dome.name = "Dome"
	beam.name = "Beam"
	root.add_child(ground)
	root.add_child(dome)
	root.add_child(beam)
	root.set_meta("ember_laser", true)
	battle._world.add_child(root)
	## ★显式标注类型: `battle` 是无类型的注入宿主, `:=` 推不出 Tween(Parse Error)。
	var tw: Tween = battle._reg_tween()
	## ★捕获实例 id 不捕获节点: 时停/换路时根节点可能先被收掉, 捕获节点会报 `Lambda capture ... freed`
	##   (全息斧脉冲 2026-09-15 踩过, 见 axe_final_vfx.gd `holo_pulse` 注释)。
	var rid: int = root.get_instance_id()
	tw.tween_method(func(t: float) -> void:
		var r = instance_from_id(rid)
		if is_instance_valid(r):
			apply_frame(r as Node, t)
	, 0.0, DUR - 0.001, DUR)
	tw.tween_callback(func() -> void:
		var r = instance_from_id(rid)
		if is_instance_valid(r):
			(r as Node).queue_free())
	return root
