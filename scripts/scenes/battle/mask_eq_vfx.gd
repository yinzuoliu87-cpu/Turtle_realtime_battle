class_name MaskEqVfx
extends MagicEqVfx
## mask_eq_vfx.gd —— 面具 10 件(127~136)的演出层(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)
## 继承魔法书演出层拿通用小工具(拖尾 / 朝向 / 帧推进); 每件的招牌演出各自写在这里, 不复用别的装备的招牌素材(CLAUDE.md §10 第 5 条)。
## 结算一律在 eq_mask_batch.gd(sim 侧), 这里只画。


# ════════════════════════════════════════ 136 千面【里世界】 ════════════════════════════════════════
## 用户 11-26「地图上需要有个按钮，可以调整观众的视角，从主地图切换到里世界」。
## 里世界开着时屏幕上方出一个按钮; 切到里世界视角 ⇒ 只看得见里世界里的人(battle_render 读 EqMaskBatch.ow_hidden),
## 整屏罩一层暗紫; 切回主世界 ⇒ 里世界的人隐去。结束时按钮收起、视角回主世界。
var _ow_btn: Button = null
var _ow_tint: ColorRect = null


func _ow_ui_parent():
	var l = battle.get("_ui_layer")
	return l if l != null and is_instance_valid(l) else null


func ow_open() -> void:
	var p = _ow_ui_parent()
	if p == null:
		return
	if _ow_tint == null or not is_instance_valid(_ow_tint):
		_ow_tint = ColorRect.new()
		_ow_tint.color = Color(0.22, 0.05, 0.32, 0.38)
		_ow_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ow_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ow_tint.visible = false
		p.add_child(_ow_tint)
		p.move_child(_ow_tint, 0)
	if _ow_btn == null or not is_instance_valid(_ow_btn):
		_ow_btn = Button.new()
		_ow_btn.size = Vector2(150, 40)
		battle._style_hud_btn(_ow_btn)
		_ow_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		_ow_btn.pressed.connect(_ow_toggle)
		p.add_child(_ow_btn)
	var vs: Vector2 = battle.get_viewport().get_visible_rect().size
	_ow_btn.position = Vector2(vs.x * 0.5 - 75.0, 64.0)
	_ow_btn.visible = true
	_ow_refresh()


func _ow_toggle() -> void:
	var m = battle._equip_sys._mask_sys
	m.ow_view = not bool(m.ow_view)
	_ow_refresh()


func _ow_refresh() -> void:
	var on := bool(battle._equip_sys._mask_sys.ow_view)
	if _ow_btn != null and is_instance_valid(_ow_btn):
		_ow_btn.text = "回到主世界" if on else "观看里世界"
	if _ow_tint != null and is_instance_valid(_ow_tint):
		_ow_tint.visible = on


func ow_close(_reason: String) -> void:
	battle._equip_sys._mask_sys.ow_view = false
	if _ow_btn != null and is_instance_valid(_ow_btn):
		_ow_btn.visible = false
	_ow_refresh()


func clear() -> void:
	super.clear()
	for g in _gb:
		for key in ["beam", "ground", "up", "mask"]:
			_gb_free(g[key])
	_gb.clear()
	if _ow_btn != null and is_instance_valid(_ow_btn):
		_ow_btn.visible = false
	if _ow_tint != null and is_instance_valid(_ow_tint):
		_ow_tint.visible = false


# ════════════════════════════════════════ 135 黄金面具【金光】 ════════════════════════════════════════
## 分段(用户 11-25 夜 / 11-26 原话:「面具突然上天上射出一道金光…目标…一道金光从上往下打中它」「金光肯定是有延时的嘛」「一直盯」):
##   0.00–0.30 秒  面具(135 自己的图标)从头顶飞上天, 越飞越小
##   0.30–0.50 秒  面具朝天射出一道细金光(光柱从面具往上长到屏幕顶)
##   0.50–1.00 秒  金光从天上往下落到目标身上(光柱下沿从天顶降到脚下)
##   1.00 秒起     落地: 脚下金光炸开; 光柱一直钉着目标、跟着它走, 粗细呼吸; 伤害每涨一秒光柱更亮更粗
##   目标死  ⇒ 光柱 0.25 秒内收细消失; 打死的东西头上飘「+1 深海币」
const GB_TEX := "res://assets/sprites/vfx/mask-gold-beam.png"
const GG_TEX := "res://assets/sprites/vfx/mask-gold-ground.png"
const GB_TOP := 14.0            # 光柱顶端离地(米) —— 屏幕顶以上
const GB_W := 54.0              # 光柱宽(码)
const GB_RISE := 3.6            # 面具升到离地 3.6 米(还在屏幕里, 11-26 自查: 原来升到 9.8 米一下子出了画面)
const GB_UP_END := 0.30
const GB_SHOOT_END := 0.50
var _gb: Array = []             # {B, mask, up, beam, ground, t, delay, state, fade}


func _gb_tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null


func _gb_col(len_m: float, w_m: float, col: Color) -> Sprite3D:
	var t := _gb_tex(GB_TEX)
	if t == null or not _ok():
		return null
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.centered = true
	s.offset = Vector2(0.0, float(t.get_height()) * 0.5)   # 原点 = 光柱下沿
	s.pixel_size = w_m / float(t.get_width())
	s.modulate = col
	battle._world.add_child(s)
	_gb_len(s, len_m)
	return s


func _gb_len(s: Sprite3D, len_m: float) -> void:
	if s == null or not is_instance_valid(s) or s.texture == null:
		return
	var full: float = float(s.texture.get_height()) * s.pixel_size
	s.scale = Vector3(s.scale.x if s.scale.x > 0.0 else 1.0, maxf(0.001, len_m / full), 1.0)


func gold_cast(u: Dictionary, tgt: Dictionary, delay: float, B: Dictionary) -> void:
	if not _ok():
		return
	var head: Vector3 = battle._world_pos(Vector2(u["pos"]), body_h(u) * 2.0 + 0.4)
	var m := _icon("p2eq_135", head, 40.0)
	_gb.append({"B": B, "owner": u, "tgt": tgt, "mask": m, "up": null, "beam": null, "ground": null, "t": 0.0, "delay": delay,
		"state": "wind", "fade": 0.0, "head": head})


func gold_land(B: Dictionary) -> void:
	for g in _gb:
		if is_same(g["B"], B):
			g["state"] = "beam"
			var tgt = g["tgt"]
			if tgt is Dictionary:
				var t := _gb_tex(GG_TEX)
				if t != null:
					var s := Sprite3D.new()
					s.texture = t
					s.shaded = false
					s.transparent = true
					s.no_depth_test = true
					s.render_priority = 10
					s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
					s.offset = Vector2(0.0, float(t.get_height()) * 0.5 - 8.0)
					s.pixel_size = (110.0 * float(battle.WS)) / float(t.get_width())
					battle._world.add_child(s)
					s.position = battle._world_pos(Vector2((tgt as Dictionary)["pos"]), 0.02)
					g["ground"] = s


func gold_end(B: Dictionary) -> void:
	for g in _gb:
		if is_same(g["B"], B) and str(g["state"]) != "fade":
			g["state"] = "fade"
			g["fade"] = 0.0


func gold_coin(u: Dictionary, victim: Dictionary) -> void:
	if battle.get("_vfx") != null and battle._vfx.has_method("_float_text"):
		battle._vfx._float_text(Vector2(victim["pos"]) + Vector2(0.0, -70.0), "+1 深海币", Color("#ffd54a"))


func _gb_free(n) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()


func _tick_gold(delta: float) -> void:
	var keep: Array = []
	for g in _gb:
		g["t"] = float(g["t"]) + delta
		var t: float = float(g["t"])
		var tgt = g["tgt"]
		var tp: Vector3 = battle._world_pos(Vector2((tgt as Dictionary)["pos"]), 0.0) if tgt is Dictionary else Vector3.ZERO
		var w_m: float = GB_W * float(battle.WS)
		match str(g["state"]):
			"wind":
				## ① 面具飞上天
				var m = g["mask"]
				if m != null and is_instance_valid(m):
					var k: float = clampf(t / GB_UP_END, 0.0, 1.0)
					var h0: Vector3 = g["head"]
					(m as Sprite3D).position = h0.lerp(Vector3(h0.x, GB_RISE, h0.z), k * k)
					(m as Sprite3D).modulate.a = 1.0 - clampf((t - GB_UP_END) / 0.2, 0.0, 1.0)
				## ② 面具朝天射一道细金光
				if t >= GB_UP_END and g["up"] == null:
					g["up"] = _gb_col(0.1, w_m * 0.45, Color(1.0, 0.92, 0.55, 0.95))
					var h1: Vector3 = g["head"]
					if g["up"] != null:
						(g["up"] as Sprite3D).position = Vector3(h1.x, GB_RISE, h1.z)
				if g["up"] != null and is_instance_valid(g["up"]):
					var ku: float = clampf((t - GB_UP_END) / (GB_SHOOT_END - GB_UP_END), 0.0, 1.0)
					_gb_len(g["up"], (GB_TOP - GB_RISE) * ku)
					(g["up"] as Sprite3D).modulate.a = 0.95 * (1.0 - clampf((t - GB_SHOOT_END) / 0.25, 0.0, 1.0))
				## ③ 金光从天上落下来
				if t >= GB_SHOOT_END and tgt is Dictionary:
					if g["beam"] == null:
						g["beam"] = _gb_col(0.1, w_m, Color(1.0, 0.95, 0.7, 0.9))
					var kd: float = clampf((t - GB_SHOOT_END) / maxf(0.05, float(g["delay"]) - GB_SHOOT_END), 0.0, 1.0)
					var bot: float = lerpf(GB_TOP, 0.0, kd * kd)
					var bm = g["beam"]
					if bm != null and is_instance_valid(bm):
						(bm as Sprite3D).position = Vector3(tp.x, bot, tp.z)
						_gb_len(bm, GB_TOP - bot)
			"beam":
				var bm2 = g["beam"]
				if bm2 == null and tgt is Dictionary:
					g["beam"] = _gb_col(GB_TOP, w_m, Color(1.0, 0.95, 0.7, 0.9))
					bm2 = g["beam"]
				var el: float = maxf(0.0, float(battle._t) - float((g["B"] as Dictionary).get("start", battle._t)))
				var grow: float = minf(1.0 + 0.08 * floorf(el), 1.8)          # 每涨一秒更粗(封顶 1.8 倍)
				var breath: float = 1.0 + 0.07 * sin(t * 12.0)
				if bm2 != null and is_instance_valid(bm2):
					(bm2 as Sprite3D).position = Vector3(tp.x, 0.0, tp.z)
					(bm2 as Sprite3D).scale.x = grow * breath
					_gb_len(bm2, GB_TOP)
					var br: float = minf(1.0, 0.75 + 0.05 * floorf(el))
					(bm2 as Sprite3D).modulate = Color(1.0, 0.93 + 0.07 * br, 0.6 + 0.35 * br, 0.85 + 0.15 * br)
				var gr = g["ground"]
				if gr != null and is_instance_valid(gr):
					(gr as Sprite3D).position = Vector3(tp.x, 0.02, tp.z)
					(gr as Sprite3D).scale = Vector3.ONE * grow * (1.0 + 0.06 * sin(t * 9.0))
			"fade":
				g["fade"] = float(g["fade"]) + delta
				var kf: float = clampf(float(g["fade"]) / 0.25, 0.0, 1.0)
				for key in ["beam", "ground", "up", "mask"]:
					var n = g[key]
					if n != null and is_instance_valid(n):
						(n as Sprite3D).modulate.a = (1.0 - kf) * (n as Sprite3D).modulate.a
						if key == "beam":
							(n as Sprite3D).scale.x = maxf(0.05, (n as Sprite3D).scale.x * (1.0 - kf * 0.5))
				if kf >= 1.0:
					for key in ["beam", "ground", "up", "mask"]:
						_gb_free(g[key])
					continue
		## 面具飞完就收掉
		if t > GB_SHOOT_END + 0.3 and g["mask"] != null:
			_gb_free(g["mask"])
			g["mask"] = null
		if t > GB_SHOOT_END + 0.3 and g["up"] != null:
			_gb_free(g["up"])
			g["up"] = null
		keep.append(g)
	_gb = keep


func tick(delta: float) -> void:
	super.tick(delta)
	_tick_gold(delta)
