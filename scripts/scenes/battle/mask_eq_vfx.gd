class_name MaskEqVfx
extends MagicEqVfx
## mask_eq_vfx.gd —— 面具 10 件(127~136)的演出层(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)
## 继承魔法书演出层拿通用小工具(拖尾 / 朝向 / 帧推进); 每件的招牌演出各自写在这里, 不复用别的装备的招牌素材(CLAUDE.md §10 第 5 条)。
## 结算一律在 eq_mask_batch.gd(sim 侧), 这里只画。


# ════════════════════════════════════════ 通用: 帧条特效节点 ════════════════════════════════════════
## 一条特效 = 一张横排帧条。follow = 跟着某个单位走(h = 离地高)。
var _mfx: Array = []   # {node, nf, fps, t, life, loop, follow, h}


func _strip(path: String, nf: int, pos3: Vector3, h_m: float, fps: float, loop: bool, life: float, flat: bool = false, follow = null, h_off: float = 0.0) -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = nf
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if flat:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y
		s.pixel_size = h_m / float(t.get_width() / nf)   # 贴地的: h_m 当作宽
	else:
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.offset = Vector2(0.0, float(t.get_height()) * 0.5)   # 原点 = 底边
		s.pixel_size = h_m / float(t.get_height())
	s.position = pos3
	battle._world.add_child(s)
	_mfx.append({"node": s, "nf": nf, "fps": fps, "t": 0.0, "life": life, "loop": loop, "follow": follow, "h": h_off})
	return s


func _tick_mfx(delta: float) -> void:
	var keep: Array = []
	for f in _mfx:
		var n = f["node"]
		if n == null or not is_instance_valid(n):
			continue
		f["t"] = float(f["t"]) + delta
		var t: float = float(f["t"])
		var k: int = int(t * float(f["fps"]))
		(n as Sprite3D).frame = (k % int(f["nf"])) if bool(f["loop"]) else mini(k, int(f["nf"]) - 1)
		var fo = f["follow"]
		if fo is Dictionary:
			if not (fo as Dictionary).get("alive", false):
				(n as Node).queue_free()
				continue
			(n as Sprite3D).position = battle._world_pos(Vector2((fo as Dictionary)["pos"]), float(f["h"]))
		var life: float = float(f["life"])
		if life > 0.0:
			if t >= life:
				(n as Node).queue_free()
				continue
			if t > life - 0.15:
				(n as Sprite3D).modulate.a = clampf((life - t) / 0.15, 0.0, 1.0)
		keep.append(f)
	_mfx = keep


func _free(n) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()


# ════════════════════════════════════════ 136 千面【里世界】 ════════════════════════════════════════
## 参考莫德凯撒 R(研究 docs/studies/20261126-参考-莫德凯撒R死亡之境.md, 用户 11-26 看过「可以参考」):
##   抓取 0.6 秒  被拽的人头上出紫色面具印记(逐帧明灭); 携带者身前伸出紫色鬼手, 0.6 秒里飞过去攥拳抓住
##   进入        两人原地炸开紫雾, 消失; 站过的地方各留一道紫色裂隙(逐帧)+ 倒计时数字; 里世界平台上两人落点各炸一团紫雾
##   偷属性(每秒) 三颗紫色魂火从被偷的人飞向携带者; 携带者头上飘「+攻 +甲 +抗」; 被偷的人身体越来越灰(battle_render 读 _ow_drained)
##   携带者      脚下一圈紫色鬼火光环(逐帧), 偷得越多越大, 留到这一路结束
##   回来        主世界裂隙收掉; 回来的人各落一道紫色光柱
## 镜头切换按钮: 图标(进: 箭头 + 漩涡面具 / 回: 回头箭头 + 小岛), 用户 11-26「不要以文字形式，以图标形式」。
const OW_ICON_IN := "res://assets/sprites/ui/hud-ow-enter.png"
const OW_ICON_BACK := "res://assets/sprites/ui/hud-ow-back.png"
const OWV := "res://assets/sprites/vfx/"
var _ow_btn: Button = null
var _ow_btn_ic: TextureRect = null
var _ow_stage: OtherworldStage = null
var _ow_rifts: Array = []     # {node, label}
var _ow_auras: Array = []     # {u, node}
var _ow_flies: Array = []     # 魂火 {node, from_u, to_u, t, dur} / 回落光柱 {node, drop, t, dur}
var _ow_hands: Array = []     # {node, from, fh, to_u, t, dur}


func _ow_ui_parent():
	var l = battle.get("_ui_layer")
	return l if l != null and is_instance_valid(l) else null


func ow_grab(cu: Dictionary, v: Dictionary, sec: float) -> void:
	if not _ok():
		return
	## 11-26 自查: 印记 0.9 米 / 鬼手 1.5 米在默认镜头下几乎看不见 ⇒ 1.5 / 2.6 米
	var hv: float = body_h(v) * 2.0 + 0.6
	_strip(OWV + "ow-sigil.png", 4, battle._world_pos(Vector2(v["pos"]), hv), 1.5, 8.0, true, sec + 0.15, false, v, hv)
	var hand := _strip(OWV + "ow-hand.png", 9, battle._world_pos(Vector2(cu["pos"]), body_h(cu)), 2.6, 9.0 / sec, false, sec + 0.05)
	if hand != null:
		hand.flip_h = float(Vector2(v["pos"]).x) < float(Vector2(cu["pos"]).x)
		hand.offset = Vector2.ZERO
		_ow_hands.append({"node": hand, "from": Vector2(cu["pos"]), "fh": body_h(cu), "to_u": v, "t": 0.0, "dur": sec})


func ow_pull(cu: Dictionary, v: Dictionary, p0c: Vector2, p0v: Vector2) -> void:
	if not _ok():
		return
	for p in [p0c, p0v]:
		_strip(OWV + "ow-mist.png", 9, battle._world_pos(p, 0.0), 2.6, 15.0, false, 0.6)
		var r := _strip(OWV + "ow-rift.png", 4, battle._world_pos(p, 0.03), 2.2, 6.0, true, 0.0, true)
		var lb := Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.font_size = 64
		lb.pixel_size = 0.012
		lb.outline_size = 14
		lb.modulate = Color("#d9b8ff")
		lb.outline_modulate = Color(0.12, 0.02, 0.2)
		lb.position = battle._world_pos(p, 1.2)
		battle._world.add_child(lb)
		_ow_rifts.append({"node": r, "label": lb})
	for u in [cu, v]:
		_strip(OWV + "ow-mist.png", 9, battle._world_pos(Vector2(u["pos"]), 0.0), 2.6, 15.0, false, 0.6)


func ow_steal(th: Dictionary, vi: Dictionary, got: Dictionary) -> void:
	if not _ok():
		return
	for k in range(3):
		var w := _strip(OWV + "ow-wisp.png", 4, battle._world_pos(Vector2(vi["pos"]), body_h(vi)), 0.95, 10.0, true, 0.0)
		if w != null:
			_ow_flies.append({"node": w, "from_u": vi, "to_u": th, "t": -0.12 * float(k), "dur": 0.45})
	## 飘字只在观众正看着里世界时出(飘字是屏幕层, 镜头不在那边时会投到画面角落 —— 11-26 自查); 0 的那项不写
	if bool(battle._equip_sys._mask_sys.ow_view) and battle.get("_vfx") != null and battle._vfx.has_method("_float_text"):
		var parts: Array = []
		for pr in [["base_atk", "攻"], ["base_def", "甲"], ["base_mr", "抗"]]:
			var v2: int = int(round(float(got.get(pr[0], 0.0))))
			if v2 > 0:
				parts.append("+%d%s" % [v2, pr[1]])
		if not parts.is_empty():
			battle._vfx._float_text(Vector2(th["pos"]) + Vector2(0.0, -60.0), " ".join(parts), Color("#c79bff"))
	var has := false
	for a in _ow_auras:
		if is_same(a["u"], th):
			has = true
	if not has:
		var n := _strip(OWV + "ow-aura.png", 8, battle._world_pos(Vector2(th["pos"]), 0.0), 2.4, 9.0, true, 0.0, false, th, 0.0)
		if n != null:
			n.render_priority = 8
			n.no_depth_test = false
			_ow_auras.append({"u": th, "node": n})


func ow_open() -> void:
	if _ow_stage == null:
		_ow_stage = OtherworldStage.new(battle)
	_ow_stage.build()
	var p = _ow_ui_parent()
	if p == null:
		return
	if _ow_btn == null or not is_instance_valid(_ow_btn):
		_ow_btn = Button.new()
		_ow_btn.size = Vector2(60, 46)
		battle._style_hud_btn(_ow_btn)
		if battle.get("_hud") != null and battle._hud.has_method("_insp_btn_skin"):
			battle._hud._insp_btn_skin(_ow_btn)
		_ow_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		_ow_btn_ic = TextureRect.new()
		_ow_btn_ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_ow_btn_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_ow_btn_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_ow_btn_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ow_btn_ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ow_btn_ic.offset_left = 6
		_ow_btn_ic.offset_right = -6
		_ow_btn_ic.offset_top = 4
		_ow_btn_ic.offset_bottom = -4
		_ow_btn.add_child(_ow_btn_ic)
		_ow_btn.pressed.connect(_ow_toggle)
		p.add_child(_ow_btn)
	var vs: Vector2 = battle.get_viewport().get_visible_rect().size
	_ow_btn.position = Vector2(vs.x * 0.5 - 30.0, 64.0)
	_ow_btn.visible = true
	_ow_refresh()


func _ow_toggle() -> void:
	var m = battle._equip_sys._mask_sys
	m.ow_view = not bool(m.ow_view)
	_ow_refresh()


func _ow_refresh() -> void:
	var on := bool(battle._equip_sys._mask_sys.ow_view)
	if _ow_btn != null and is_instance_valid(_ow_btn):
		_ow_btn.tooltip_text = "回到主世界" if on else "观看里世界"
		if _ow_btn_ic != null and is_instance_valid(_ow_btn_ic):
			var ip: String = OW_ICON_BACK if on else OW_ICON_IN
			_ow_btn_ic.texture = load(ip) if ResourceLoader.exists(ip) else null
	if battle.get("_cam_world_off") != null:
		battle._cam_world_off = (_ow_stage.center3() - battle._world_pos(Vector2(battle._arena_center), 0.0)) if (on and _ow_stage != null) else Vector3.ZERO
		battle._apply_cam_zoom()


func ow_close(_reason: String, returned: Array = []) -> void:
	battle._equip_sys._mask_sys.ow_view = false
	if _ow_btn != null and is_instance_valid(_ow_btn):
		_ow_btn.visible = false
	_ow_refresh()
	if _ow_stage != null:
		_ow_stage.free_stage()
	for r in _ow_rifts:
		_free(r["node"])
		_free(r["label"])
	_ow_rifts.clear()
	for u in returned:
		if u is Dictionary and (u as Dictionary).get("alive", false):
			var pl := _strip(OWV + "ow-pillar2.png", 6, battle._world_pos(Vector2((u as Dictionary)["pos"]), 0.0), 7.0, 14.0, true, 0.7)
			if pl != null:
				pl.scale = Vector3(1.0, 0.05, 1.0)
				_ow_flies.append({"node": pl, "drop": true, "t": 0.0, "dur": 0.15})
			_strip(OWV + "ow-mist.png", 9, battle._world_pos(Vector2((u as Dictionary)["pos"]), 0.0), 2.0, 15.0, false, 0.6)


func _tick_ow(delta: float) -> void:
	if _ow_stage != null:
		_ow_stage.tick(delta)
	## 倒计时数字
	var ow = battle._equip_sys._mask_sys.ow
	for r in _ow_rifts:
		var lb = r["label"]
		if lb != null and is_instance_valid(lb) and ow.active:
			(lb as Label3D).text = str(int(ceil(maxf(0.0, OtherworldSystem.OW_SEC - (float(battle._t) - float(ow.t0))))))
	## 鬼手飞过去
	var keep_h: Array = []
	for h in _ow_hands:
		var n = h["node"]
		if n == null or not is_instance_valid(n):
			continue
		h["t"] = float(h["t"]) + delta
		var k: float = clampf(float(h["t"]) / float(h["dur"]), 0.0, 1.0)
		var to_u: Dictionary = h["to_u"]
		var a: Vector3 = battle._world_pos(Vector2(h["from"]), float(h["fh"]))
		var b: Vector3 = battle._world_pos(Vector2(to_u["pos"]), body_h(to_u))
		(n as Sprite3D).position = a.lerp(b, 1.0 - pow(1.0 - minf(1.0, k / 0.7), 2.0))
		keep_h.append(h)
	_ow_hands = keep_h
	## 魂火飞向携带者 / 回落光柱从天上落下
	var keep: Array = []
	for f in _ow_flies:
		var n2 = f["node"]
		if n2 == null or not is_instance_valid(n2):
			continue
		f["t"] = float(f["t"]) + delta
		if bool(f.get("drop", false)):
			(n2 as Sprite3D).scale = Vector3(1.0, clampf(float(f["t"]) / float(f["dur"]), 0.05, 1.0), 1.0)
			if float(f["t"]) < float(f["dur"]):
				keep.append(f)
			continue
		var t: float = float(f["t"])
		if t < 0.0:
			(n2 as Sprite3D).visible = false
			keep.append(f)
			continue
		(n2 as Sprite3D).visible = true
		var fu: Dictionary = f["from_u"]
		var tu: Dictionary = f["to_u"]
		var kk: float = clampf(t / float(f["dur"]), 0.0, 1.0)
		var pa: Vector3 = battle._world_pos(Vector2(fu["pos"]), body_h(fu))
		var pb: Vector3 = battle._world_pos(Vector2(tu["pos"]), body_h(tu))
		var mid: Vector3 = (pa + pb) * 0.5 + Vector3(0.0, 1.2, 0.0)
		var q: Vector3 = pa.lerp(mid, kk).lerp(mid.lerp(pb, kk), kk)
		(n2 as Sprite3D).position = q - Vector3(0.0, 0.25, 0.0)
		if kk >= 1.0:
			(n2 as Node).queue_free()
			continue
		keep.append(f)
	_ow_flies = keep
	## 携带者光环: 偷得越多越大(封顶 1.6 倍)
	var keep_a: Array = []
	for a2 in _ow_auras:
		var u: Dictionary = a2["u"]
		var n3 = a2["node"]
		if n3 == null or not is_instance_valid(n3) or not u.get("alive", false):
			_free(n3)
			continue
		var sc: float = 0.9 + minf(0.7, float(u.get("_ow_stolen", 0.0)) / 120.0)
		(n3 as Sprite3D).scale = Vector3(sc, sc, sc)
		keep_a.append(a2)
	_ow_auras = keep_a


func clear() -> void:
	super.clear()
	for g in _gb:
		for key in ["beam", "ring", "splash", "up", "mask"]:
			_free(g.get(key))
	_gb.clear()
	for f in _mfx:
		_free(f["node"])
	_mfx.clear()
	for r in _ow_rifts:
		_free(r["node"])
		_free(r["label"])
	_ow_rifts.clear()
	_ow_auras.clear()
	_ow_flies.clear()
	_ow_hands.clear()
	if _ow_stage != null:
		_ow_stage.free_stage()
	if battle.get("_cam_world_off") != null and battle._cam_world_off != Vector3.ZERO:
		battle._cam_world_off = Vector3.ZERO
		battle._apply_cam_zoom()
	if _ow_btn != null and is_instance_valid(_ow_btn):
		_ow_btn.visible = false


# ════════════════════════════════════════ 135 黄金面具【金光】 ════════════════════════════════════════
## 参考云顶第 8 赛季五费雷欧娜激光(研究 docs/studies/20261126-参考-云顶雷欧娜金光.md, 用户 11-26 看过「可以参考」)。
## 分段(研究第五节):
##   0.00–0.30 秒  面具从头顶飞上天, 朝天射一道细金光(用户设计)
##   0.30–0.85 秒  锁定: 目标脚下金橙锁定圈; 从天到目标【一帧出现】整根细金红预警线(先粗 0.35 → 收成细线 0.12)
##   0.85–1.00 秒  开火爆胀: 预警线 0.08 秒内胀到 1.35 倍再落回 1 倍粗; 底部向两侧喷火花(逐帧)
##   1.00 秒起     三层光柱(逐帧: 白芯 / 金黄 / 橙边 + 红纹流动 + 粗细呼吸), 伤害每涨一秒更粗更亮
##   目标死        光柱一帧消失, 原地一小团金灰烟(逐帧); 头上飘「+1 深海币」
const GB_ANIM := "res://assets/sprites/vfx/mask-gold-beam-anim.png"
const GB_RING := "res://assets/sprites/vfx/mask-gold-ring.png"
const GB_SPLASH := "res://assets/sprites/vfx/mask-gold-splash.png"
const GB_SMOKE := "res://assets/sprites/vfx/mask-gold-smoke.png"
const GB_TOP := 14.0
const GB_W := 70.0              # 光柱满宽(码)
const GB_RISE := 3.6
const GB_UP_END := 0.30
const GB_FIRE := 0.85
var _gb: Array = []


func _gb_col(len_m: float, w_m: float, col: Color) -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(GB_ANIM):
		return null
	var t: Texture2D = load(GB_ANIM)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = 6
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.offset = Vector2(0.0, float(t.get_height()) * 0.5)
	s.pixel_size = w_m / float(t.get_width() / 6)
	s.modulate = col
	battle._world.add_child(s)
	_gb_len(s, len_m)
	return s


func _gb_len(s, len_m: float) -> void:
	if s == null or not is_instance_valid(s) or (s as Sprite3D).texture == null:
		return
	var full: float = float((s as Sprite3D).texture.get_height()) * (s as Sprite3D).pixel_size
	(s as Sprite3D).scale.y = maxf(0.001, len_m / full)


func gold_cast(u: Dictionary, tgt: Dictionary, delay: float, B: Dictionary) -> void:
	if not _ok():
		return
	var head: Vector3 = battle._world_pos(Vector2(u["pos"]), body_h(u) * 2.0 + 0.4)
	var m := _icon("p2eq_135", head, 40.0)
	_gb.append({"B": B, "owner": u, "tgt": tgt, "mask": m, "up": null, "beam": null, "ring": null, "splash": null,
		"t": 0.0, "delay": delay, "state": "wind", "head": head})


func gold_land(B: Dictionary) -> void:
	for g in _gb:
		if is_same(g["B"], B):
			g["state"] = "beam"


func gold_end(B: Dictionary) -> void:
	for g in _gb:
		if is_same(g["B"], B) and str(g["state"]) != "done":
			g["state"] = "done"
			var bm = g.get("beam")
			if bm != null and is_instance_valid(bm) and float(g["t"]) >= GB_FIRE:
				_strip(GB_SMOKE, 6, (bm as Sprite3D).position, 1.3, 14.0, false, 0.45)   # 原版: 一帧消失, 留一小团烟
			for key in ["beam", "ring", "splash", "up", "mask"]:
				_free(g.get(key))


func gold_coin(_u: Dictionary, victim: Dictionary) -> void:
	if battle.get("_vfx") != null and battle._vfx.has_method("_float_text"):
		battle._vfx._float_text(Vector2(victim["pos"]) + Vector2(0.0, -70.0), "+1 深海币", Color("#ffd54a"))


func _tick_gold(delta: float) -> void:
	var keep: Array = []
	for g in _gb:
		if str(g["state"]) == "done":
			continue
		g["t"] = float(g["t"]) + delta
		var t: float = float(g["t"])
		var tgt = g["tgt"]
		if not (tgt is Dictionary):
			continue
		var tp: Vector3 = battle._world_pos(Vector2((tgt as Dictionary)["pos"]), 0.0)
		var w_m: float = GB_W * float(battle.WS)
		## ① 面具飞上天 + 朝天细光
		var m = g["mask"]
		if m != null and is_instance_valid(m):
			var k: float = clampf(t / GB_UP_END, 0.0, 1.0)
			var h0: Vector3 = g["head"]
			(m as Sprite3D).position = h0.lerp(Vector3(h0.x, GB_RISE, h0.z), k * k)
			(m as Sprite3D).modulate.a = 1.0 - clampf((t - GB_UP_END) / 0.25, 0.0, 1.0)
			if t > GB_UP_END + 0.3:
				_free(m)
				g["mask"] = null
		if t >= GB_UP_END * 0.6 and g["up"] == null and t < GB_UP_END + 0.3:
			var h1: Vector3 = g["head"]
			g["up"] = _gb_col(GB_TOP - GB_RISE, w_m * 0.18, Color(1.0, 0.95, 0.75, 0.9))
			if g["up"] != null:
				(g["up"] as Sprite3D).position = Vector3(h1.x, GB_RISE, h1.z)
		if g["up"] != null and is_instance_valid(g["up"]):
			(g["up"] as Sprite3D).modulate.a = 0.9 * (1.0 - clampf((t - GB_UP_END) / 0.3, 0.0, 1.0))
			if t > GB_UP_END + 0.3:
				_free(g["up"])
				g["up"] = null
		if t < GB_UP_END:
			keep.append(g)
			continue
		## ② 锁定圈 + 预警线(一帧出现整根)
		if g["ring"] == null:
			g["ring"] = _strip(GB_RING, 1, tp + Vector3(0, 0.03, 0), 2.6, 0.0, true, 0.0, true, tgt, 0.03)
		if g["beam"] == null:
			g["beam"] = _gb_col(GB_TOP, w_m, Color(1.0, 0.55, 0.3, 0.75))
		var bm = g["beam"]
		if bm == null or not is_instance_valid(bm):
			keep.append(g)
			continue
		(bm as Sprite3D).position = Vector3(tp.x, 0.0, tp.z)
		(bm as Sprite3D).frame = int(t * 14.0) % 6
		var fire_at: float = minf(GB_FIRE, float(g["delay"]) - 0.15)
		if t < fire_at:
			var kt: float = clampf((t - GB_UP_END) / 0.1, 0.0, 1.0)   # 先粗 0.35 → 0.1 秒内收成细线 0.12
			(bm as Sprite3D).scale.x = lerpf(0.35, 0.12, kt)
			(bm as Sprite3D).modulate = Color(1.0, 0.5, 0.28, 0.8)
			var rg = g["ring"]
			if rg != null and is_instance_valid(rg):
				(rg as Sprite3D).scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 18.0))
		else:
			## ③ 开火爆胀 + ④ 持续
			var kb: float = clampf((t - fire_at) / 0.08, 0.0, 1.0)
			var el: float = maxf(0.0, float(battle._t) - float((g["B"] as Dictionary).get("start", battle._t))) if str(g["state"]) == "beam" else 0.0
			var grow: float = minf(1.0 + 0.07 * floorf(el), 1.6)
			var burst: float = lerpf(0.12, 1.35, kb) if kb < 1.0 else lerpf(1.35, 1.0, clampf((t - fire_at - 0.08) / 0.1, 0.0, 1.0))
			(bm as Sprite3D).scale.x = burst * grow
			var br: float = minf(1.0, 0.8 + 0.05 * floorf(el))
			(bm as Sprite3D).modulate = Color(1.0, 0.95 + 0.05 * br, 0.85 + 0.15 * br, 1.0)
			if g["splash"] == null:
				g["splash"] = _strip(GB_SPLASH, 6, tp, 2.0, 16.0, true, 0.0, false, tgt, 0.0)
			var sp = g["splash"]
			if sp != null and is_instance_valid(sp):
				(sp as Sprite3D).scale = Vector3.ONE * grow
			var rg2 = g["ring"]
			if rg2 != null and is_instance_valid(rg2):   # 开火后锁定圈 0.2 秒淡掉
				(rg2 as Sprite3D).modulate.a = 1.0 - clampf((t - fire_at) / 0.2, 0.0, 1.0)
		keep.append(g)
	_gb = keep


func tick(delta: float) -> void:
	super.tick(delta)
	_tick_mfx(delta)
	_tick_gold(delta)
	_tick_ow(delta)
