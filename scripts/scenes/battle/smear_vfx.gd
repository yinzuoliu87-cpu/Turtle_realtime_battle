class_name SmearVfx
extends RefCounted
## 弧形刀光(月牙拖影)。2026-11-05 孤注一掷重做 —— 用户:「孤注一掷这个问题是你整个镰刀都是一个平滑运动，这是确定是你学到的东西吗？这个得改呀」。
## 参考 LoL 德莱厄斯 Q 逐帧(docs/studies/20261105-镰刀参考-德莱厄斯Q逐帧.md):
##   挥出后约 0.1 秒扫过并命中(先快后慢); 刀后一条【连续】月牙刀光, 刀头最宽最亮、往后变细变淡; 扫完约 0.2 秒收掉。
##   我们原来是一张镰刀图 0.4 秒匀速转 120°, 每帧留一张分开的红色复制图(梳子状), 伤害数字第 0 帧就跳完 —— 刀和伤害对不上。
## 画法: ImmediateMesh 贴地扇环, 每一格只用一个颜色(顶点不插值 ⇒ 硬边色带, 和像素画风一致); 三条色带 = 外缘亮边 / 主体 / 内缘暗边。
## 只是演出: 不读写任何对局状态, 不进 sim。

const SEGS := 30

## 先快后慢(三次缓出): 前一半时间就扫过约 87% 的角度。
static func ease_out(x: float) -> float:
	var c: float = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c) * (1.0 - c)

## 缓出的反函数: 刀头扫到进度 s(0~1) 的那一刻 / sweep_sec。用来让命中闪光正好落在刀经过敌人的那一帧。
static func time_at(s: float) -> float:
	return 1.0 - pow(1.0 - clampf(s, 0.0, 1.0), 1.0 / 3.0)

## 贴地月牙刀光。base_ang: 扇形中线角(弧度, 2D 坐标); half: 半角(弧度); r_out: 外半径(码);
## pal = [外缘亮边, 主体, 内缘暗边] 三个颜色(alpha 是该色带的最大不透明度)。返回节点(调用方一般不用管, 结束自动删)。
static func sweep(battle, origin2d: Vector2, base_ang: float, half: float, r_out: float, sweep_sec: float, fade_sec: float, pal: Array, height: float = 0.06) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = battle._world_pos(origin2d, height)
	battle._world.add_child(mi)
	var total: float = sweep_sec + fade_sec
	var tw = battle._reg_tween().bind_node(mi)
	tw.tween_method(func(t: float) -> void: _draw(im, t, base_ang, half, r_out, sweep_sec, fade_sec, pal, battle.WS), 0.0, total, total)
	tw.tween_callback(mi.queue_free)
	return mi

static func _draw(im: ImmediateMesh, t: float, base_ang: float, half: float, r_out: float, sweep_sec: float, fade_sec: float, pal: Array, ws: float) -> void:
	im.clear_surfaces()
	var p_lead: float = ease_out(t / sweep_sec)
	## 尾巴追刀头: 刀挥出 35% 时间后尾巴才开始收, 扫完之后尾巴继续往刀头收拢(刀光由尾向头消失)
	var p_tail: float = ease_out((t - sweep_sec * 0.35) / (sweep_sec * 0.65 + fade_sec * 0.8))
	var fade: float = 1.0 if t <= sweep_sec else clampf(1.0 - (t - sweep_sec) / maxf(0.001, fade_sec), 0.0, 1.0)
	var a_lead: float = -half + 2.0 * half * p_lead
	var a_tail: float = -half + 2.0 * half * minf(p_tail, p_lead)
	if a_lead - a_tail < 0.004 or fade <= 0.0:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGS):
		var s0: float = float(i) / SEGS
		var s1: float = float(i + 1) / SEGS
		var sm: float = (s0 + s1) * 0.5
		var a0: float = base_ang + a_tail + (a_lead - a_tail) * s0
		var a1: float = base_ang + a_tail + (a_lead - a_tail) * s1
		## 刀头最宽: 带宽从尾巴 16% 半径长到刀头 62% 半径
		var w: float = r_out * (0.16 + 0.46 * pow(sm, 1.4))
		## 不透明度按 6 级台阶从尾到头递增(硬边色带; 4 级时接缝太显眼)
		var lvl: float = (floorf(sm * 6.0) + 1.0) / 6.0
		var bright: float = 0.45 if sm > 0.9 else 0.0     # 刀头最后一格往白里提
		var bands := [
			[r_out - w * 0.14, r_out, pal[0]],
			[r_out - w * 0.62, r_out - w * 0.14, pal[1]],
			[r_out - w, r_out - w * 0.62, pal[2]],
		]
		for b in bands:
			var c: Color = (b[2] as Color).lerp(Color(1, 1, 1, (b[2] as Color).a), bright)
			c.a = (b[2] as Color).a * lvl * fade
			im.surface_set_color(c)
			_quad(im, a0, a1, float(b[0]), float(b[1]), ws)
	im.surface_end()

static func _quad(im: ImmediateMesh, a0: float, a1: float, r_in: float, r_o: float, ws: float) -> void:
	var c0 := Vector2(cos(a0), sin(a0))
	var c1 := Vector2(cos(a1), sin(a1))
	var p00 := Vector3(c0.x * r_in * ws, 0.0, c0.y * r_in * ws)
	var p01 := Vector3(c0.x * r_o * ws, 0.0, c0.y * r_o * ws)
	var p10 := Vector3(c1.x * r_in * ws, 0.0, c1.y * r_in * ws)
	var p11 := Vector3(c1.x * r_o * ws, 0.0, c1.y * r_o * ws)
	im.surface_add_vertex(p00); im.surface_add_vertex(p01); im.surface_add_vertex(p11)
	im.surface_add_vertex(p00); im.surface_add_vertex(p11); im.surface_add_vertex(p10)
