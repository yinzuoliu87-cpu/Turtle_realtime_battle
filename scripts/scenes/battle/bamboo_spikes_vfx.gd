class_name BambooSpikesVfx
extends RefCounted
## 竹叶龟·竹刺阵的演出(2026-11-05 重做)。只管画面: 不碰 sim、不用对局随机流(用演出随机流 _juice_rng)、不往单位字典写东西。
## 由来: 用户 11-05「竹叶龟的这个第三个技能，这很明显是不合格的。这个参考对象是大虫子的 Q 啊，你这也没有参考啊」。
##   原来: 通用技能环一闪就淡(蓄力还没完环就没了) → 0.6 秒时圈内零散冒 14 根冰刺贴图染绿的「小圣诞树」, 没有爆点、没有裂地。
## 参考 LoL 科加斯 Q「破裂」逐帧(docs/studies/20261105-竹刺阵参考-科加斯Q逐帧.md, 官网技能演示 0031_Q1, 30 fps):
##   ① 预警: 一圈细环 0.17 秒亮起后【一直亮到爆】; 环里地面有尘土往圆心聚(地下有东西要出来)
##   ② 爆点(第 20 帧): 圆心一团黄白闪光 → 两帧内变成铺满整圈的光罩, 目标被挑起
##   ③ 刺(第 23~24 帧): 沿圆周一整圈弯刺破土、向外翘; 圈里也有几根; 地面裂开发暗
##   ④ 光罩 0.3 秒褪掉, 刺和裂地留约 0.5 秒再收
## 竹叶龟版: 配色换成竹绿 / 土褐, 刺 = 斜切口竹桩(assets/sprites/vfx/bamboo-stake.png, 向外倾), 裂地 = bamboo-quake-crack.png
##   (两张都由 tools/assetgen/build_bamboo_spikes.py 生成, 硬边像素)。

const STAKE := "res://assets/sprites/vfx/bamboo-stake.png"
const CRACK := "res://assets/sprites/vfx/bamboo-quake-crack.png"
const COL_RING := Color(0.45, 0.95, 0.40)
const COL_DUST := Color(0.55, 0.42, 0.26)
const COL_FLASH := Color(1.0, 0.97, 0.75)
const COL_DOME := Color(0.55, 1.0, 0.45)
## ★实拍第一版(1.7 高 / 8 像素粗)像一地草, 连不成一圈 ⇒ 竹桩改粗(12 像素竿)、放大、圆周加到 26 根
const RIM_N := 26                # 圆周一圈刺(科加斯 Q 实数约 20 根; 我们圈 300 码更大, 多几根才连成圈)
const IN_N := 7                  # 圈内几根
const STAKE_H_RIM := 2.5         # 圆周刺高(世界单位)
const STAKE_H_IN := 1.9
const STAKE_H_HIT := 3.1         # 被打中的人脚下那根更粗更高
const HOLD := 0.5                # 刺与裂地停留(秒)


## 预警(放技能那一刻调): 环 0.15 秒亮起、保持到爆点; 圈内地面裂纹淡淡透出; 最后 0.35 秒尘土往圆心聚。
static func telegraph(battle, c: Vector2, r: float, windup: float) -> void:
	## 细环(高分辨率细线圆环)两道: 亮绿主环 + 外缘一道深绿边(第一版 96 像素像素环放大到 600 码是一圈粗带)
	## 外缘那道边 = 施法方阵营色(11-04 敌我描边规矩, 与共享环 _skill_ring 同一对颜色); 没有阵营时深绿
	var rs: String = str(battle._ring_side)
	var ec: Color = battle.RING_RIM_LEFT if rs == "left" else (battle.RING_RIM_RIGHT if rs == "right" else Color(0.06, 0.28, 0.08))
	var edge = _ground_spr(battle, VfxTex._make_thin_ring_tex(), c, r * 2.03, Color(ec.r, ec.g, ec.b, 0.0), 0.048, true)
	var ring = _ground_spr(battle, VfxTex._make_thin_ring_tex(), c, r * 2.0, Color(COL_RING.r, COL_RING.g, COL_RING.b, 0.0), 0.05, true)
	ring.set_meta("ring_target_ps", ring.pixel_size)   # 地面环标记(门禁 verify_ring_team_rim 按它认环)
	if rs == "left" or rs == "right":
		ring.set_meta("ring_rim", edge)
		ring.set_meta("ring_rim_side", rs)
	var fill = _ground_spr(battle, VfxTex._make_disc_texture(), c, r * 2.0, Color(0.20, 0.45, 0.16, 0.0), 0.035, true)
	var pre = battle._px_ground_sprite(load(CRACK), c, r * 1.2, Color(0.75, 0.9, 0.6, 0.0), 0.04)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(edge, "modulate:a", 0.8, 0.15)
	tw.tween_property(ring, "modulate:a", 1.0, 0.15)
	tw.tween_property(fill, "modulate:a", 0.16, 0.15)
	tw.tween_property(pre, "modulate:a", 0.25, windup)
	tw.chain().tween_callback(edge.queue_free)
	tw.chain().tween_callback(ring.queue_free)
	tw.chain().tween_callback(fill.queue_free)
	tw.chain().tween_callback(pre.queue_free)
	## 尘土向心聚(最后 0.35 秒): 12 颗土块从圈内各处往圆心爬
	var t0: float = maxf(0.0, windup - 0.35)
	for i in range(12):
		var a: float = TAU * float(i) / 12.0 + DetMath.rrange(battle._juice_rng, -0.25, 0.25)
		var d: float = r * DetMath.rrange(battle._juice_rng, 0.45, 0.9)
		var p0: Vector2 = c + Vector2(DetMath.dcos(a), DetMath.dsin(a)) * d
		var s := _block(battle, p0, 0.12, COL_DUST if i % 3 != 0 else COL_RING.lerp(COL_DUST, 0.4), 0.034)
		s.modulate.a = 0.0
		var p1: Vector3 = battle._world_pos(c + (p0 - c) * 0.25, 0.12)
		var tm = battle._reg_tween().bind_node(s)
		tm.tween_interval(t0 + 0.02 * float(i % 4))
		tm.tween_property(s, "modulate:a", 1.0, 0.05)
		tm.tween_property(s, "position", p1, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tm.tween_callback(s.queue_free)


## 爆点(竹刺结算那一刻调): hits = 被打中的敌人位置(脚下各一根粗竹桩)。
static func erupt(battle, c: Vector2, r: float, hits: Array) -> void:
	## ② 闪光: 圆心黄白一团, 0.07 秒涨大, 0.16 秒内收掉
	var fl := Sprite3D.new()
	fl.texture = VfxTex._make_fire_glow_tex()
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false; fl.transparent = true
	fl.modulate = COL_FLASH
	fl.pixel_size = (r * 0.7 * battle.WS) / float(maxi(1, fl.texture.get_height()))
	fl.scale = Vector3(0.45, 0.45, 0.45)
	fl.position = battle._world_pos(c, 0.5)
	battle._world.add_child(fl)
	var tf = battle._reg_tween().bind_node(fl)
	tf.tween_property(fl, "scale", Vector3(1.0, 1.0, 1.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tf.tween_property(fl, "modulate:a", 0.0, 0.16)
	tf.tween_callback(fl.queue_free)
	## 光罩: 铺满整圈的竹绿光(两帧内铺开), 0.35 秒褪掉
	var dome = _ground_spr(battle, VfxTex._make_fire_glow_tex(), c, r * 2.2, Color(COL_DOME.r, COL_DOME.g, COL_DOME.b, 0.85), 0.07, true)
	dome.scale = Vector3(0.4, 1.0, 0.4)
	var td = battle._reg_tween().bind_node(dome)
	td.tween_property(dome, "scale", Vector3(1.0, 1.0, 1.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	td.tween_property(dome, "modulate:a", 0.0, 0.35)
	td.tween_callback(dome.queue_free)
	## ③ 裂地: 整圈地面裂开(硬边像素), 停留后淡出
	var dark = _ground_spr(battle, VfxTex._make_disc_texture(), c, r * 2.0, Color(0.08, 0.16, 0.06, 0.0), 0.04, true)
	var ck = battle._px_ground_sprite(load(CRACK), c, r * 1.7, Color(0.62, 0.78, 0.5, 0.0), 0.045)
	for spr in [dark, ck]:
		var tc = battle._reg_tween().bind_node(spr)
		tc.tween_property(spr, "modulate:a", 0.38 if spr == dark else 0.6, 0.06)
		tc.tween_interval(HOLD)
		tc.tween_property(spr, "modulate:a", 0.0, 0.3)
		tc.tween_callback(spr.queue_free)
	## 竹刺: 圆周一整圈(向外倾) + 圈内几根 + 被打中的人脚下各一根粗的; 由内向外 0.05 秒错开冒出
	for i in range(RIM_N):
		var a: float = TAU * float(i) / float(RIM_N) + DetMath.rrange(battle._juice_rng, -0.08, 0.08)
		var d: float = r * DetMath.rrange(battle._juice_rng, 0.88, 1.0)
		var p: Vector2 = c + Vector2(DetMath.dcos(a), DetMath.dsin(a)) * d
		_stake(battle, p, c, STAKE_H_RIM * DetMath.rrange(battle._juice_rng, 0.85, 1.15), 0.04 + 0.012 * float(i % 3))
	for i in range(IN_N):
		var a: float = TAU * float(i) / float(IN_N) + DetMath.rrange(battle._juice_rng, -0.4, 0.4)
		var d: float = r * DetMath.rrange(battle._juice_rng, 0.18, 0.62)
		_stake(battle, c + Vector2(DetMath.dcos(a), DetMath.dsin(a)) * d, c, STAKE_H_IN * DetMath.rrange(battle._juice_rng, 0.85, 1.15), 0.015)
	for hp in hits:
		_stake(battle, hp, c, STAKE_H_HIT, 0.0)
	## 碎土与草叶往外崩
	for i in range(18):
		var a: float = TAU * float(i) / 18.0 + DetMath.rrange(battle._juice_rng, -0.2, 0.2)
		var p0: Vector2 = c + Vector2(DetMath.dcos(a), DetMath.dsin(a)) * r * DetMath.rrange(battle._juice_rng, 0.1, 0.5)
		var s := _block(battle, p0, 0.2, COL_DUST if i % 2 == 0 else COL_RING, 0.04 if i % 4 == 0 else 0.03)
		var p1: Vector2 = c + Vector2(DetMath.dcos(a), DetMath.dsin(a)) * r * DetMath.rrange(battle._juice_rng, 0.7, 1.15)
		var up: float = DetMath.rrange(battle._juice_rng, 1.2, 2.2)
		var tb = battle._reg_tween().bind_node(s)
		tb.set_parallel(true)
		tb.tween_property(s, "position:x", battle._world_pos(p1, 0.0).x, 0.42)
		tb.tween_property(s, "position:z", battle._world_pos(p1, 0.0).z, 0.42)
		tb.tween_property(s, "position:y", s.position.y + up, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tb.chain().tween_property(s, "position:y", 0.1, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tb.chain().tween_callback(s.queue_free)


## 一根竹桩: 从地下 0.08 秒顶出来(回弹), 按在圆心哪一侧选向外倾的那一格; 停 HOLD 秒后缩回地下并淡出。
static func _stake(battle, p: Vector2, c: Vector2, h: float, delay: float) -> void:
	var tex: Texture2D = load(STAKE)
	if tex == null:
		return
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = 3
	var dx: float = p.x - c.x
	s.frame = 1 if absf(dx) < 30.0 else (0 if dx < 0.0 else 2)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = h / float(maxi(1, tex.get_height()))
	var top: Vector3 = battle._world_pos(p, h * 0.5 - 0.05)
	s.position = top - Vector3(0.0, h, 0.0)
	s.modulate = Color(1, 1, 1, 0.0)
	battle._world.add_child(s)
	var tw = battle._reg_tween().bind_node(s)
	tw.tween_interval(delay)
	tw.tween_property(s, "modulate:a", 1.0, 0.02)
	tw.parallel().tween_property(s, "position", top, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_property(s, "position", top - Vector3(0.0, h * 0.6, 0.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.22)
	tw.tween_callback(s.queue_free)


## 平躺在地面的精灵(软光用线性过滤; 像素图走 battle._px_ground_sprite)。
static func _ground_spr(battle, tex: Texture2D, c: Vector2, size_px: float, col: Color, h: float, linear: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR if linear else BaseMaterial3D.TEXTURE_FILTER_NEAREST   # vfx-linear-ok: 线性只给程序软辉光与高分辨率细线环(_make_fire_glow_tex / _make_thin_ring_tex / _make_disc_texture), 像素图走 NEAREST
	s.modulate = col
	s.pixel_size = (size_px * battle.WS) / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(c, h)
	battle._world.add_child(s)
	return s


static func _block(battle, p: Vector2, h: float, col: Color, ps: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = VfxTex._make_pixel_block_tex()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.pixel_size = ps
	s.modulate = Color(col.r, col.g, col.b, 1.0)
	s.position = battle._world_pos(p, h)
	battle._world.add_child(s)
	return s
