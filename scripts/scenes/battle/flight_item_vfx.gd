class_name FlightItemVfx
extends RefCounted
## flight_item_vfx.gd —— 飞行物 / 残影类小演出(2026-11-25 从 battle_vfx.gd 拆出来: 那边到了 3000 行上限, arch_budget 守)
##   · 113 弯匕攻速暴涨的金色残影(渲染层调, 播放端也画)
##   · 扔东西(古灵精怪枪)的三段演出: 建节点 / 按通用飞行物的进度摆 / 落地
## 全是静态函数, battle 作参数(同 battle_vfx 里的写法: battle._world / battle._world_pos / battle._reg_tween)。


## 扔东西(古灵精怪枪)的演出, 分三段由通用飞行物驱动(11-25 起按飞行速度, 不再自己按固定秒数补间):
##   throw_item_node 建节点 → throw_item_step 每步按飞行进度摆(真抛物线 + 翻滚) → throw_item_land 到了(火花 + 飘字 + 淡出)
const THROW_ITEM_H0 := 1.1                      # 出手在胸口高度(与 lava-rock 那条一致)
static func throw_item_node(battle, from2d: Vector2, img: String):
	var p := Sprite3D.new()
	var path := "res://assets/sprites/vfx/" + img
	if not ResourceLoader.exists(path) or battle._world == null:
		return null                             # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	p.texture = load(path)
	p.pixel_size = (30.0 * battle.WS) / float(maxi(1, p.texture.get_height()))
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.position = battle._world_pos(from2d, THROW_ITEM_H0)
	battle._world.add_child(p)
	return p


static func throw_item_step(battle, p, from2d: Vector2, to2d: Vector2, s: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	var arc: float = clampf(from2d.distance_to(to2d) * 0.004, 0.5, 2.2)   # 远则拱高
	## 真抛物线: 4·h·s(1−s) 是拱高为 h 的标准形(与 090 浪潮同一条公式, 不另立)
	p.position = battle._world_pos(from2d.lerp(to2d, s), THROW_ITEM_H0 + arc * 4.0 * s * (1.0 - s))
	p.rotation.z = s * TAU * 1.5             # 翻滚 —— 扔出去的东西会转


static func throw_item_land(battle, p, tgt: Dictionary, label: String, col: Color, hit: bool) -> void:
	if hit:
		battle._vfx._hit_spark(tgt)
		battle._vfx._float_text(Vector2(tgt["pos"]) + Vector2(0, -66), label, col)
	if p == null or not is_instance_valid(p):
		return
	## ★落地才淡 —— 不是从出手就开始淡(那正是"淡出病": 实拍读成一团灰)
	var tw: Tween = battle._reg_tween()
	tw.bind_node(p)
	tw.tween_property(p, "modulate:a", 0.0, 0.18)
	tw.tween_callback(p.queue_free)


## 113 弯匕攻速暴涨的金色残影(11-25 用户「还不够明显」): 复制当前身体帧 → 纯金色发光剪影(assets/shaders/haste_silhouette.gdshader),
##   往身后飘 0.4 米再淡出。站着连砍时残影也会往后拉开(读成「快」); 前几帧的挥砍姿势留在残影里 = 一道快影。纯视觉, 渲染层调。
##   ★用着色器换色, 不用 modulate: modulate 是乘法, 乘在绿龟上是一团土黄(>1 也被截住), 实拍过两次。
const _HASTE_SIL := preload("res://assets/shaders/haste_silhouette.gdshader")
static func haste_afterimage(battle, spr, face_right: bool) -> void:
	if not is_instance_valid(spr) or not spr.is_inside_tree():
		return
	var ai := Sprite3D.new()
	ai.texture = spr.texture
	ai.frame = 0
	ai.hframes = spr.hframes
	ai.vframes = spr.vframes
	ai.frame = clampi(int(spr.frame), 0, maxi(0, int(ai.hframes) * int(ai.vframes) - 1))
	ai.pixel_size = spr.pixel_size
	ai.billboard = spr.billboard
	ai.flip_h = spr.flip_h
	ai.offset = spr.offset
	ai.shaded = false
	ai.transparent = true
	ai.texture_filter = spr.texture_filter
	ai.scale = spr.scale
	var mat := ShaderMaterial.new()
	mat.shader = _HASTE_SIL
	mat.set_shader_parameter("tex", spr.texture)
	mat.set_shader_parameter("fade", 0.5)
	mat.render_priority = -1   # 画在本体后面: 本体后画、盖住残影(原来残影盖在人身上, 人被一团金光糊住)
	ai.material_override = mat
	battle._world.add_child(ai)
	var back := Vector3(-0.4 if face_right else 0.4, 0.0, 0.0)
	ai.global_position = spr.global_position + back * 0.25   # 一出生就往身后错开一点
	var tw: Tween = battle._reg_tween()
	tw.bind_node(ai)
	tw.set_parallel(true)
	tw.tween_property(ai, "global_position", spr.global_position + back, 0.3)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 0.5, 0.0, 0.3)
	tw.chain().tween_callback(ai.queue_free)
