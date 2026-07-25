class_name SmolderSystem
extends RefCounted
## 阴燃母火/爆燃系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 类内 _smolder_* 名字不变→内部互调零改动;只外部名加 battle. 前缀。无状态成员。

var battle

func _init(b) -> void:
	battle = b

func _smolder_mother(origin: Vector2, dir: Vector2) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/dragon-mother.png")
	if tex == null:
		return
	var d := Sprite3D.new()
	d.texture = tex
	d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	d.shaded = false
	d.transparent = true
	d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	d.flip_h = (dir.x < 0.0)
	d.pixel_size = (300.0 * battle.WS) / float(maxi(1, int(tex.get_width())))
	var far: Vector2 = origin - dir * 260.0
	var behind: Vector2 = origin - dir * 150.0
	d.position = battle._world_pos(far, 3.0)
	d.modulate = Color(1, 1, 1, 0)
	battle._world.add_child(d)
	var tw = battle._reg_tween()
	tw.tween_property(d, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_method(_smolder_mom_fly.bind(d, far, behind), 0.0, 1.0, 0.5)
	tw.tween_interval(0.7)
	tw.tween_property(d, "modulate:a", 0.0, 0.35)
	tw.tween_callback(d.queue_free)

func _smolder_mom_fly(p: float, d: Sprite3D, a: Vector2, b: Vector2) -> void:
	if is_instance_valid(d):
		d.position = battle._world_pos(a.lerp(b, p), 3.0 - p * 0.7)

func _smolder_erupt(origin: Vector2, dir: Vector2, reach: float, si: int) -> void:
	battle._shake(0.12)
	_smolder_flash()
	_smolder_burst(origin, dir)
	_smolder_fire_wave(origin, dir, reach, si)
	_smolder_ground_embers(origin, dir, reach)

func _smolder_burst(origin: Vector2, dir: Vector2) -> void:   # 喷发瞬间嘴部大亮团(扩张淡出)
	var tex := VfxTex._make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.9, 0.65, 1.0)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	spr.pixel_size = (90.0 * battle.WS) / tw_w
	spr.position = battle._world_pos(origin + dir * 45.0, 1.45)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "pixel_size", (260.0 * battle.WS) / tw_w, 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(spr.queue_free)

func _smolder_flash() -> void:
	if battle._ui_layer == null or not is_instance_valid(battle._ui_layer):
		return
	var rect := ColorRect.new()
	rect.color = Color(1.0, 0.85, 0.6, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle._ui_layer.add_child(rect)
	var tw = battle._reg_tween()
	tw.tween_property(rect, "color:a", 0.3, 0.05)
	tw.tween_property(rect, "color:a", 0.0, 0.28)
	tw.tween_callback(rect.queue_free)

func _smolder_fire_wave(origin: Vector2, dir: Vector2, reach: float, si: int) -> void:
	var perp: Vector2 = dir.orthogonal()
	var waves: int = 26
	var dur: float = 0.62
	for w in range(waves):
		var wt: float = (float(w) / float(waves)) * dur
		for k in range(5):                              # 每波5团=更密实的火墙
			var lateral: float = randf_range(-1.0, 1.0)
			var voff: float = randf_range(-0.1, 1.25)   # 垂直体积: 火焰堆成一堵墙(非一条线)
			var tw = battle._reg_tween()
			tw.tween_interval(wt)
			tw.tween_callback(_smolder_spawn_blob.bind(origin, dir, perp, lateral, voff, reach))
	for c in range(3):                                  # 亮脊: 3个白热核错峰沿中线冲(中心最烫)
		var tc = battle._reg_tween()
		tc.tween_interval(float(c) * 0.12)
		tc.tween_callback(_smolder_spawn_core.bind(origin, dir, reach))

func _smolder_spawn_blob(origin: Vector2, dir: Vector2, perp: Vector2, lateral: float, voff: float, reach: float) -> void:
	var tex := VfxTex._make_fire_glow_tex()
	var travel: float = randf_range(0.42, 0.6)
	var endp: Vector2 = origin + dir * (reach * randf_range(0.7, 1.05)) + perp * (lateral * reach * 0.26)
	var spr := Sprite3D.new()
	spr.texture = tex
	var heat: float = 1.0 - absf(lateral) * 0.8
	spr.modulate = Color(1.0, 0.28 + heat * 0.6, 0.04 + heat * 0.42, 0.92)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (randf_range(72.0, 140.0) * battle.WS) / float(maxi(1, int(tex.get_width())))
	var h: float = 1.05 + voff
	spr.position = battle._world_pos(origin, h)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_smolder_blob_fly.bind(spr, origin, endp, h), 0.0, 1.0, travel)
	tw.tween_property(spr, "modulate:a", 0.0, travel)
	tw.chain().tween_callback(spr.queue_free)

func _smolder_blob_fly(p: float, spr: Sprite3D, a: Vector2, b: Vector2, h: float) -> void:
	if is_instance_valid(spr):
		spr.position = battle._world_pos(a.lerp(b, p), h + sin(p * PI) * 0.22)

func _smolder_spawn_core(origin: Vector2, dir: Vector2, reach: float) -> void:
	var tex := VfxTex._make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.95, 0.7, 1.0)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (175.0 * battle.WS) / float(maxi(1, int(tex.get_width())))
	spr.position = battle._world_pos(origin, 1.25)
	battle._world.add_child(spr)
	var endp: Vector2 = origin + dir * (reach * 0.92)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_smolder_blob_fly.bind(spr, origin, endp, 1.3), 0.0, 1.0, 0.6)
	tw.tween_property(spr, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(spr.queue_free)

func _smolder_ground_embers(origin: Vector2, dir: Vector2, reach: float) -> void:
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	for i in range(1, 9):
		var f: float = float(i) / 9.0
		var pos: Vector2 = origin + dir * (reach * f)
		var tw = battle._reg_tween()
		tw.tween_interval(f * 0.5)
		tw.tween_callback(_smolder_ember_at.bind(pos, burn))

func _smolder_ember_at(pos2d: Vector2, burn: Texture2D) -> void:
	if burn == null:
		return
	battle.play_sheet_vfx(pos2d, burn, 8, 95.0, 1.1, 0.12)
