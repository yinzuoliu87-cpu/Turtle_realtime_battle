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
		s.no_depth_test = false   # 贴地的要被站着的单位挡住(单位立绘有的走不透明通道, 光靠先画盖不住)
		s.render_priority = -1   # 贴地的(冲击环 / 警示区 / 横扫气刃)先画, 单位压在上面(11-27 录像: 舞狮冲击环盖住了身体)
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
	_ow_button_show()


## 只建 / 显示镜头切换按钮(场景是 3D 节点, 看直播时由镜像给; 按钮是 2D 界面, 播放端得自己建 —— 见 stream_sync)
func _ow_button_show() -> void:
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
		battle._cam_world_off = (battle._world_pos(Vector2(battle._arena_center) + OtherworldSystem.OW_SHIFT, 0.0) - battle._world_pos(Vector2(battle._arena_center), 0.0)) if on else Vector3.ZERO   # = OtherworldStage.center3(); 直接按常量算, 播放端没有 sim 侧的场景对象
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


## 看直播 / 录像(播放端不跑 sim, ow_open / ow_close 都不会被调): 每个渲染步之后由 stream_player 调。
##   单位的 `_ow`(在里世界)字段在流里 ⇒ 有活着的单位在里世界 = 里世界开着: 显示切换按钮、隐去不在观众所看世界的人(ow_hidden);
##   没有了 = 关了: 收按钮、镜头回主世界。(11-26 夜探针 _probe_stream_mask: 原来本机按钮 89 次 / 播放 0 次, 隐去 178 / 0)
func stream_sync(units: Array) -> void:
	var m = battle._equip_sys._mask_sys
	var any := false
	for u in units:
		if u is Dictionary and (u as Dictionary).get("alive", false) and bool((u as Dictionary).get("_ow", false)):
			any = true
			break
	if any == bool(m.stream_ow):
		return
	m.stream_ow = any
	if any:
		_ow_button_show()
	else:
		m.ow_view = false
		if _ow_btn != null and is_instance_valid(_ow_btn):
			_ow_btn.visible = false
		_ow_refresh()


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
	_ven.clear()
	for f in _mflies:
		_free(f["node"])
	_mflies.clear()
	_gas_last.clear()
	_fox_last.clear()
	_lion_in.clear()
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


# ════════════════════════════════════════ 偷脸 / 127 / 129 / 130 / 131 / 132 / 133 ════════════════════════════════════════
## 11-26 夜补齐(分段与素材来历见 pack_mask_art.py 头注; 全部逐帧帧条, 没照参考):
##   偷脸复制   原版身上飘出一张淡蓝魂面具(逐帧), 0.45 秒飞到复制体身上, 落点一圈淡蓝环; 复制体常驻淡蓝微透明(_body_tint)
##   复制体赠属性 金绿光球(逐帧)0.5 秒飞到最近友军, 落点一圈金绿环
##   127 纸面具  登场一圈纸色环; 反击纸刃(逐帧旋转)按 sim 飞行位置走, 碰到身体才结算(sim 侧)
##   129 京剧   换脸: 头顶一张脸 0.45 秒变成下一张(逐帧变脸), 停 0.6 秒淡出; 红脸普攻 = 目标身上红色真伤火花; 白脸偷龟能 = 白色光球从目标飞回
##   130 舞狮   登场爆竹(逐帧); 蓄力 = 脚下红金环; 冲撞 = 换成冲撞帧条循环(走引擎走路通道), 停下换回; 撞到人 = 一圈红金环
##   131 小丑   被嘲讽的敌人头上一张嘲笑小丑脸(逐帧循环), 嘲讽多久挂多久
##   132 鬼面   潜行 / 现形各一团暗红烟(逐帧)
##   133 防毒   挡下灼烧 / 中毒 / 流血时身前一团毒气撞上滤网散开(逐帧; 同一只 0.5 秒内只画一次)
const MV := "res://assets/sprites/vfx/"
const HEAD_H := 1.6   # 头顶演出的离地高(血条下面; 2.3 会被血条挡住, 11-26 录像量过)
var _mflies: Array = []   # {node, a(单位或 Vector2), b(单位), t, dur, h, done(Callable)}
var _gas_last := {}       # 单位 → 上次画挡毒的时间(按实例 id)


func _upos(x) -> Vector2:
	return Vector2((x as Dictionary)["pos"]) if x is Dictionary else Vector2(x)


func _fly_strip(path: String, nf: int, a, b: Dictionary, dur: float, h: float, size_m: float, col: Color, done: Callable = Callable()) -> void:
	var s := _strip(path, nf, battle._world_pos(_upos(a), h), size_m, 12.0, true, 0.0, false, null, 0.0)
	if s == null:
		return
	s.offset = Vector2.ZERO
	s.modulate = col
	_mflies.append({"node": s, "a": _upos(a), "b": b, "t": 0.0, "dur": dur, "h": h, "done": done})


func _tick_mflies(delta: float) -> void:
	var keep: Array = []
	for f in _mflies:
		var n = f["node"]
		if n == null or not is_instance_valid(n):
			continue
		f["t"] = float(f["t"]) + delta
		var k: float = clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var b: Dictionary = f["b"]
		var p: Vector2 = Vector2(f["a"]).lerp(Vector2(b["pos"]), k * k * (3.0 - 2.0 * k))
		(n as Sprite3D).position = battle._world_pos(p, float(f["h"]) + sin(k * PI) * 0.6)   # 抛一道弧
		if k >= 1.0 or not b.get("alive", false):
			_free(n)
			if k >= 1.0 and (f["done"] as Callable).is_valid():
				(f["done"] as Callable).call()
			continue
		keep.append(f)
	_mflies = keep


## 偷脸: 复制体生成
func mask_copy_spawn(c: Dictionary, o: Dictionary) -> void:
	c["_body_tint"] = Color(0.55, 0.8, 1.6, 0.75)   # 复制体常驻淡蓝微透明(受击闪白照常叠上去); 一眼分得出哪只是偷来的
	_fly_strip(MV + "mask-copy-spirit.png", 4, o, c, 0.45, 1.2, 1.4, Color(1, 1, 1, 0.95),
		func() -> void: _ring(Vector2(c["pos"]), 70.0, Color(0.55, 0.85, 1.0, 0.9), 0.35))


## 偷脸: 复制体死, 属性给最近友军
func mask_gift(u: Dictionary, b: Dictionary) -> void:
	_fly_strip(MV + "mask-gift-orb.png", 4, Vector2(u["pos"]), b, 0.5, 1.2, 0.7, Color(1, 1, 1, 1),
		func() -> void: _ring(Vector2(b["pos"]), 60.0, Color(0.8, 1.0, 0.45, 0.9), 0.35))


## 127 纸面具
func paper_shield(u: Dictionary) -> void:
	_ring(Vector2(u["pos"]), 55.0, Color(0.95, 0.93, 0.85, 0.9), 0.4)


func paper_shot(u: Dictionary, _s: Dictionary):
	var n := _strip(MV + "mask-paper-blade.png", 4, battle._world_pos(Vector2(u["pos"]), 1.0), 0.8, 16.0, true, 0.0, false, null, 0.0)
	if n != null:
		n.offset = Vector2.ZERO
	return n


func paper_step(node, p2: Vector2) -> void:
	if node != null and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, 1.0)


func paper_shot_end(node, hit: bool) -> void:
	## 近身反击飞行往往只有 0.1 秒(两三帧): 命中处再留 0.2 秒让纸刃转着淡出, 看得见「掷回去了」
	if hit and node != null and is_instance_valid(node):
		var s2 := _strip(MV + "mask-paper-blade.png", 4, (node as Sprite3D).position, 0.8, 16.0, true, 0.22, false, null, 0.0)
		if s2 != null:
			s2.offset = Vector2.ZERO
	_free(node)


## 129 京剧脸谱
func face_swap(u: Dictionary, face: int) -> void:
	if not bool(u.get("_face_shown", false)):
		u["_face_shown"] = true
		if face == 0:
			return   # 开打进红脸不画变脸(没有「上一张脸」)
	var path: String = [MV + "mask-face-wr.png", MV + "mask-face-rk.png", MV + "mask-face-kw.png"][clampi(face, 0, 2)]
	var nf: int = [7, 4, 7][clampi(face, 0, 2)]
	var fps := 14.0
	_strip(path, nf, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.8, fps, false, float(nf) / fps + 0.6, false, u, HEAD_H)


func face_red_hit(_u: Dictionary, tgt: Dictionary) -> void:
	_strip(MV + "mask-face-redhit.png", 7, battle._world_pos(Vector2(tgt["pos"]), 0.6), 0.9, 18.0, false, 7.0 / 18.0, false, tgt, 0.6)


func face_white_steal(u: Dictionary, tgt: Dictionary) -> void:
	_fly_strip(MV + "mask-gift-orb.png", 4, tgt, u, 0.35, 1.2, 0.5, Color(0.8, 0.9, 1.0, 1.0))


## 130 舞狮
var _lion_run_sd := {}


## 登场(11-26 夜重做, 用户「召唤物的登场，登场动画…别敷衍了」): 舞狮从携带者身后 3 米外用奔跑帧条一个跃步扑进场(抛物线, 0.45 秒),
##   落地那一下炸爆竹。只是画面偏移(_slam_voff), 结算位置不动 ⇒ 不影响对局结果。原来: 原地一声爆竹、狮子凭空出现。
const LION_IN_SEC := 0.45
var _lion_in: Array = []   # {p, t, from(画面偏移起点)}


func lion_spawn(p: Dictionary) -> void:
	var face: float = 1.0 if bool(p.get("face_right", str(p.get("side", "left")) == "left")) else -1.0
	var from := Vector3(-3.0 * face, 0.0, 0.0)
	p["_slam_voff"] = from
	_lion_in.append({"p": p, "t": 0.0, "from": from})
	p["_lion_in_now"] = true
	lion_run(p, Vector2(face, 0.0))   # 扑进来这一段播奔跑帧条(画面偏移着, 不拖彩绸)
	p.erase("_lion_in_now")


func _tick_lion_in(delta: float) -> void:
	var keep: Array = []
	for L in _lion_in:
		var p: Dictionary = L["p"]
		L["t"] = float(L["t"]) + delta
		var k: float = clampf(float(L["t"]) / LION_IN_SEC, 0.0, 1.0)
		if not p.get("alive", false):
			p["_slam_voff"] = Vector3.ZERO
			continue
		var from: Vector3 = L["from"]
		p["_slam_voff"] = from * (1.0 - k) + Vector3(0.0, 1.4 * sin(k * PI), 0.0)
		if k >= 1.0:
			p["_slam_voff"] = Vector3.ZERO
			lion_stop(p)
			_strip(MV + "mask-lion-pop.png", 9, battle._world_pos(Vector2(p["pos"]), 0.0), 2.4, 14.0, false, 9.0 / 14.0, false, null, 0.0)
			continue
		keep.append(L)
	_lion_in = keep


## 11-27 冲撞重做两轮: 用户「冲刺特效呢」→「冲锋方向你自己从来没有设计过吗…撞到敌人什么特效？…去搜这个塞恩的 R」
##   照塞恩 R 逐帧研究(docs/studies/20261127-参考-塞恩R冲撞.md)的节奏, 配色换成舞狮红金:
##   ① 蓄力 0.45 秒: 压低扒地(lwind) + 扬土; ★狮头前方先聚一团金红能量球(mask-lion-gather, 从小火星长大), 告诉玩家要往哪冲
##   ② 冲锋: ★整只裹在红色冲击能量里(eq-masklion-charge-fire, 前缘最亮; 冲锋全程锁朝向, 冲过目标不掉头)
##          + 身后速度线(mask-lion-speed) + 红金彩绸(mask-lion-ribbon) + 脚下一路扬土
##   ③ 撞上分三拍(塞恩: 接触亮星 0 秒 → 碎片喷 + 抛起 0.03 秒 → 地面冲击环 0.17 秒 → 变暗焦痕淡出 0.6 秒):
##          接触点金白亮星(底层火星) → 鞭炮碎屑炸开(mask-lion-hit) + 目标被撞飞(sim 里 _knockback, 真的抛起)
##          → 0.17 秒后目标脚下炸开地面冲击环(mask-lion-shock, 俯视画: 亮橙 → 暗红 → 焦痕 → 淡出)
const LION_DUST := "res://assets/sprites/vfx/basic-slam-dust.png"   # 7 帧 56×40(底层扬尘, CLAUDE.md §10 第 5 条许共用)
const LION_SPARK := "res://assets/sprites/vfx/spear-hit-spark.png"   # 6 帧 48×48(底层火星)
const LION_DUST_EVERY := 0.09
const LION_SHOCK_DELAY := 0.17
var _lion_wind_sd := {}
var _lion_fire_sd := {}
var _lion_trails: Array = []   # {p, dir, parts:[{n, back, h}], dust_t, wind?}
var _lion_later: Array = []    # {t, o(Vector2 位置)} 延后炸开的地面冲击环


func _lion_face(dir: Vector2) -> float:
	return 1.0 if dir.x >= 0.0 else -1.0


## 身后 back_px 像素处的世界坐标(负数 = 身前)
func _lion_behind(p: Dictionary, dir: Vector2, back_px: float, h: float) -> Vector3:
	return battle._world_pos(Vector2(p["pos"]) - Vector2(_lion_face(dir), 0.0) * back_px, h)


func _lion_dust(p: Dictionary, dir: Vector2, back_px: float, h_m: float) -> void:
	var s := _strip(LION_DUST, 7, _lion_behind(p, dir, back_px, 0.0), h_m, 16.0, false, 7.0 / 16.0, false, null, 0.0)
	if s != null:
		s.flip_h = _lion_face(dir) < 0.0


## 原画都是给「朝左跑」画的(冲击罩凸向左 / 彩绸和速度线往右拖) ⇒ 往右跑一律翻过来
func _lion_part(p: Dictionary, dir: Vector2, path: String, nf: int, back: float, h: float, h_m: float, fps: float, loop: bool, life: float) -> Dictionary:
	var n := _strip(path, nf, _lion_behind(p, dir, back, h), h_m, fps, loop, life, false, null, 0.0)
	if n != null:
		n.flip_h = _lion_face(dir) > 0.0
	return {"n": n, "back": back, "h": h}


func lion_windup(p: Dictionary, dir: Vector2, sec: float) -> void:
	if _lion_wind_sd.is_empty() and ResourceLoader.exists(MV + "eq-masklion-windup.png"):
		var t: Texture2D = load(MV + "eq-masklion-windup.png")
		## 时长比蓄力略长一点: 冲出去之前一直停在最后一两帧(压到最低), 不会绕回站姿
		_lion_wind_sd = battle._sprite_dict_from(t, {"frames": t.get_width() / 112, "frameW": 112, "frameH": 112, "duration": int(sec * 1000.0) + 60}, false)
	if not p.get("alive", false):
		return
	if not _lion_wind_sd.is_empty():
		battle._set_anim_sheet(p, _lion_wind_sd, "", true)
	_lion_dust(p, dir, 34.0, 0.55)
	## 狮头前方聚能: 7 帧正好在蓄力时长里从小火星长成一整团, 冲出去那一刻最大
	var orb := _lion_part(p, dir, MV + "mask-lion-gather.png", 7, -46.0, 0.25, 1.0, 7.0 / maxf(0.2, sec), false, sec + 0.05)
	_lion_trails.append({"p": p, "dir": dir, "parts": [orb], "dust_t": -sec * 0.5, "wind": true})   # 扒到一半再扬一团


func lion_run(p: Dictionary, _dir: Vector2) -> void:
	if _lion_run_sd.is_empty() and ResourceLoader.exists(MV + "eq-masklion-charge.png"):
		var t: Texture2D = load(MV + "eq-masklion-charge.png")
		_lion_run_sd = battle._sprite_dict_from(t, {"frames": t.get_width() / 112, "frameW": 112, "frameH": 112, "duration": 600}, false)
	## 冲锋用「整只裹在红色冲击能量里」的帧条(用户 11-27「冲击的时候，它整个身上应该是这个冲击波的这个红红色特效」);
	##   160 宽, 狮身仍在中间 112 宽 ⇒ 居中显示, 大小 / 脚底和普通帧条一样。登场扑进来那一段仍用普通奔跑帧
	if _lion_fire_sd.is_empty() and ResourceLoader.exists(MV + "eq-masklion-charge-fire.png"):
		var tf: Texture2D = load(MV + "eq-masklion-charge-fire.png")
		_lion_fire_sd = battle._sprite_dict_from(tf, {"frames": 8, "frameW": tf.get_width() / 8, "frameH": tf.get_height(), "duration": 600}, false)
	var sd: Dictionary = _lion_run_sd if (p.has("_lion_in_now") or _lion_fire_sd.is_empty()) else _lion_fire_sd
	if sd.is_empty() or not p.get("alive", false):
		return
	if not p.has("_lion_walk_sd"):
		p["_lion_walk_sd"] = p.get("run_sd", {})
	p["run_sd"] = sd                                   # 冲撞期间「走路」帧条 = 冲撞帧条(引擎按速度切走路, 不会和它抢)
	battle._set_anim_sheet(p, sd, "", true)
	if p.has("_lion_in_now"):
		return   # 登场扑进来那一段只播帧条, 不加冲锋特效
	_lion_trail_end(p)
	var parts: Array = [
		_lion_part(p, _dir, MV + "mask-lion-speed.png", 4, 70.0, 0.15, 0.85, 14.0, true, 0.0),    # 身后速度线
		_lion_part(p, _dir, MV + "mask-lion-ribbon.png", 6, 78.0, 0.18, 0.7, 12.0, true, 0.0),    # 身后彩绸
	]   # 狮头前的弯月冲击罩(mask-lion-bow)11-27 去掉: 整只已裹在红色冲击能量里, 再套一层罩子多余(用户「冲击罩不适合」)
	_lion_trails.append({"p": p, "dir": _dir, "parts": parts, "dust_t": 0.0})


func _lion_trail_end(p: Dictionary) -> void:
	var keep: Array = []
	for T in _lion_trails:
		if is_same(T["p"], p):
			for part in T["parts"]:
				var n = part["n"]
				if n != null and is_instance_valid(n):
					_fade_out(n as Sprite3D, 0.12)
			continue
		keep.append(T)
	_lion_trails = keep


func _fade_out(s: Sprite3D, sec: float) -> void:
	for f in _mfx:
		if f["node"] == s:
			f["t"] = 0.0
			f["life"] = sec + 0.15   # _tick_mfx 在最后 0.15 秒淡出
			f["follow"] = null


func _tick_lion_trails(delta: float) -> void:
	var keep: Array = []
	for T in _lion_trails:
		var p: Dictionary = T["p"]
		if not p.get("alive", false):
			for part in T["parts"]:
				var n0 = part["n"]
				if n0 != null and is_instance_valid(n0):
					(n0 as Node).queue_free()
			continue
		var dir: Vector2 = T["dir"]
		for part in T["parts"]:
			var n = part["n"]
			if n != null and is_instance_valid(n):
				(n as Sprite3D).position = _lion_behind(p, dir, float(part["back"]), float(part["h"]))
		T["dust_t"] = float(T["dust_t"]) + delta
		if bool(T.get("wind", false)):
			if float(T["dust_t"]) >= 0.0 and not bool(T.get("dusted", false)):
				T["dusted"] = true
				_lion_dust(p, dir, 40.0, 0.7)
			var alive_part := false
			for part in T["parts"]:
				if part["n"] != null and is_instance_valid(part["n"]):
					alive_part = true
			if alive_part or float(T["dust_t"]) < 0.0:
				keep.append(T)
			continue
		if float(T["dust_t"]) >= LION_DUST_EVERY:
			T["dust_t"] = 0.0
			_lion_dust(p, dir, 26.0, 0.45)
		keep.append(T)
	_lion_trails = keep
	var later: Array = []
	for L in _lion_later:
		L["t"] = float(L["t"]) - delta
		if float(L["t"]) > 0.0:
			later.append(L)
			continue
		## 地面冲击环(俯视画, 贴地): 亮橙 → 暗红 → 焦痕 → 淡出, 11 帧约 0.6 秒
		_strip(MV + "mask-lion-shock.png", 11, battle._world_pos(Vector2(L["o"]), 0.04), 2.8, 18.0, false, 11.0 / 18.0, true, null, 0.0)
	_lion_later = later


func lion_stop(p: Dictionary) -> void:
	_lion_trail_end(p)
	if p.has("_lion_walk_sd"):
		p["run_sd"] = p["_lion_walk_sd"]
	if p.get("alive", false) and (is_same(p.get("anim_sd", null), _lion_run_sd) or is_same(p.get("anim_sd", null), _lion_fire_sd) or is_same(p.get("anim_sd", null), _lion_wind_sd)):
		battle._set_anim_sheet(p, p.get("idle_sd", {}), "", true)


## 撞上(塞恩 R 的三拍): 接触亮星 → 鞭炮碎屑炸开(目标同一步被 sim 撞飞) → 0.17 秒后地面冲击环
func lion_hit(p: Dictionary, o: Dictionary) -> void:
	var at: Vector2 = Vector2(o["pos"])
	var mid: Vector2 = at.lerp(Vector2(p["pos"]), 0.35)   # 接触点 = 狮头碰到目标的地方
	_strip(LION_SPARK, 6, battle._world_pos(mid, 0.45), 1.4, 24.0, false, 6.0 / 24.0, false, null, 0.0)
	_strip(MV + "mask-lion-hit.png", 9, battle._world_pos(at, -0.35), 2.5, 20.0, false, 9.0 / 20.0, false, null, 0.0)
	_lion_later.append({"t": LION_SHOCK_DELAY, "o": at})


## 普攻咬中(11-27, 用户「lion 太敷衍了吧，特效，攻击特效」): 目标身上上下两排金色狮牙张开 → 合拢白闪 → 火星纸屑散开(8 帧 0.33 秒)
func lion_bite(_p: Dictionary, o: Dictionary) -> void:
	if not (o as Dictionary).has("pos"):
		return
	_strip(MV + "mask-lion-bite.png", 8, battle._world_pos(Vector2(o["pos"]), 0.0), 1.7, 24.0, false, 8.0 / 24.0, false, null, 0.0)


## 131 小丑面具
func clown_taunt(u: Dictionary, tg: Array, sec: float) -> void:
	## 11-27: 原来是一圈程序画的粉环 ⇒ 换成携带者身上炸开一团粉紫彩纸 + 星星 + 小铃铛(mask-clown-burst)
	_strip(MV + "mask-clown-burst.png", 9, battle._world_pos(Vector2(u["pos"]), -0.2), 2.6, 18.0, false, 9.0 / 18.0, false, null, 0.0)
	if sec <= 0.0:
		return
	for o in tg:
		if o is Dictionary and (o as Dictionary).get("alive", false):
			_strip(MV + "mask-clown-jeer.png", 4, battle._world_pos(Vector2(o["pos"]), HEAD_H), 0.6, 8.0, true, sec, false, o, HEAD_H)


## 132 鬼面
func ghost_hide(u: Dictionary, _sec: float) -> void:
	_strip(MV + "mask-ghost-puff.png", 9, battle._world_pos(Vector2(u["pos"]), 0.0), 1.8, 16.0, false, 9.0 / 16.0, false, null, 0.0)


func ghost_reveal(u: Dictionary) -> void:
	_strip(MV + "mask-ghost-puff.png", 9, battle._world_pos(Vector2(u["pos"]), 0.0), 1.4, 18.0, false, 9.0 / 18.0, false, null, 0.0)


## 128 狐狸面具: 打最大生命比自己高很多的目标(增伤到上限一半以上)时, 目标身上冒一簇狐火(逐帧); 同一个目标 0.6 秒内只冒一次
var _fox_last := {}


func fox_fire(tgt: Dictionary) -> void:
	var spr = tgt.get("sprite")
	var key: int = (spr as Object).get_instance_id() if is_instance_valid(spr) else 0
	var t := float(battle._t)
	if t - float(_fox_last.get(key, -9.0)) < 0.6:
		return
	_fox_last[key] = t
	_strip(MV + "mask-fox-fire.png", 7, battle._world_pos(Vector2(tgt["pos"]), 0.6), 1.25, 16.0, false, 7.0 / 16.0, false, tgt, 0.7)


## 133 防毒面具
func gas_block(u: Dictionary) -> void:
	var key: int = (u.get("sprite") as Object).get_instance_id() if is_instance_valid(u.get("sprite")) else 0
	var t := float(battle._t)
	if t - float(_gas_last.get(key, -9.0)) < 0.5:
		return
	_gas_last[key] = t
	_strip(MV + "mask-gas-block.png", 7, battle._world_pos(Vector2(u["pos"]), 0.5), 1.0, 14.0, false, 7.0 / 14.0, false, u, 0.5)


# ════════════════════════════════════════ 134 威尼斯面具【复活】 ════════════════════════════════════════
## 用户 11-26:「复活动画…2.5 秒之内的血量逐渐增起来，然后有这个复活的光环」。分段(没照参考, 素材见 pack_mask_art.py 头注):
##   0.0–0.4 秒  白金面具(逐帧呼吸发光)从胸口升到头顶; 身体变灰白(battle_render 读 _ven_t0 / _ven_until)
##   0.0–2.5 秒  脚下金白复活光环(逐帧沿环跑光, 循环), 前 0.3 秒由小涨满; 血条随 sim 从 1 涨到 30/45/70%, 身体随之回色
##   2.5 秒      面具 0.15 秒落回胸口; 一道金白光柱 + 白羽毛炸开(逐帧, 0.55 秒散尽)
const VEN_MASK := "res://assets/sprites/vfx/mask-venice-mask.png"
const VEN_HALO := "res://assets/sprites/vfx/mask-venice-halo.png"
const VEN_BURST := "res://assets/sprites/vfx/mask-venice-burst.png"
var _ven: Array = []   # {u, t, mask(_mfx 那条), halo(_mfx 那条), up(起身后的秒数, -1 = 未起)}


func venice_down(u: Dictionary, sec: float) -> void:
	var p3: Vector3 = battle._world_pos(Vector2(u["pos"]), 0.0)
	var halo := _strip(VEN_HALO, 8, p3, 2.6, 10.0, true, sec + 0.4, false, u, -1.3)
	var hf = _mfx.back() if halo != null else null
	var mask := _strip(VEN_MASK, 8, p3, 0.75, 8.0, true, 0.0, false, u, 0.6)
	var mf = _mfx.back() if mask != null else null
	if halo != null:
		halo.scale = Vector3(0.2, 0.2, 0.2)
	_ven.append({"u": u, "t": 0.0, "mask": mf, "halo": hf, "up": -1.0})


func venice_up(u: Dictionary) -> void:
	for V in _ven:
		if is_same(V["u"], u):
			V["up"] = 0.0
	_strip(VEN_BURST, 9, battle._world_pos(Vector2(u["pos"]), 0.0), 3.2, 16.0, false, 9.0 / 16.0, false, u, 0.0)


func _tick_ven(delta: float) -> void:
	var keep: Array = []
	for V in _ven:
		var u: Dictionary = V["u"]
		var mf = V["mask"]
		var hf = V["halo"]
		V["t"] = float(V["t"]) + delta
		var t: float = float(V["t"])
		if not u.get("alive", false):
			continue
		if hf is Dictionary and is_instance_valid((hf as Dictionary)["node"]):
			var hs: float = clampf(t / 0.3, 0.2, 1.0)
			((hf as Dictionary)["node"] as Sprite3D).scale = Vector3(hs, hs, hs)
		if float(V["up"]) < 0.0:
			if mf is Dictionary:
				(mf as Dictionary)["h"] = lerpf(0.6, 1.6, clampf(t / 0.4, 0.0, 1.0))   # 从胸口升到头顶(血条下面, 别被血条挡住)
			keep.append(V)
			continue
		V["up"] = float(V["up"]) + delta
		var k: float = clampf(float(V["up"]) / 0.15, 0.0, 1.0)
		if mf is Dictionary:
			(mf as Dictionary)["h"] = lerpf(1.6, 0.6, k * k)                    # 落回胸口
			if k >= 1.0:
				_free((mf as Dictionary)["node"])
		if hf is Dictionary and k >= 1.0:
			_free((hf as Dictionary)["node"])
		if k < 1.0:
			keep.append(V)
	_ven = keep


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
	_tick_mflies(delta)
	_tick_lion_in(delta)
	_tick_lion_trails(delta)
	_tick_ven(delta)
	_tick_gold(delta)
	_tick_ow(delta)
