extends Node
## shot_synergy_vfx.gd — 羁绊特效【看得见吗】的自证台 (dev-only·不进门禁, 文件名不是 verify_*)
##
## ══════════════════════════════════════════════════════════════════════════
##  为什么不是"截一张 1280×720 全场图然后眯眼看"
## ══════════════════════════════════════════════════════════════════════════
## 上一轮就是那么干的, 结果把地图上的绿色海草装饰当成了某件装备的特效, 写了一整条错的结论。
## 本台子把"看得见吗"变成**可判定**的三件事:
##
##  ① **A/B 差分**: 同一机位先拍两张基线(A1/A2) —— 它们的差 = 这一帧的**噪声底**
##     (立绘待机动画 / 水面 / 相机微动)。然后放特效再拍, 差 = 噪声底 + 我画的东西。
##     `变化像素数 ÷ 噪声底` 这个比值回答的正是「这一坨到底是不是我画的」。
##  ② **标定**: 不假设"0.69 屏幕像素/码" —— 直接拿**真实相机** `unproject_position`
##     把两个相距 100 码的场地点投到屏幕上量出来。相机一 zoom 这个数就变, 假设值会错。
##  ③ **同参数只换档位的对照组**: 最后两个 case 是【羁绊档位 0】跑同一条真入口 ——
##     它们应该只剩噪声底。这是把"羁绊特效"与"地图装饰/别的特效"分开的唯一硬办法。
##
## ★**不能加 `--headless`** —— 无头没有真实渲染, 截出来是空图**而且不报错**。
##
## 跑法:
##   SHOT_OUT=<目录> "<godot>" --path . res://tests/shot_synergy_vfx.tscn
##
## 产物: `<SHOT_OUT>/<case>_base.png` `<case>_hit<i>.png` `<case>_diff.png`(变化像素高亮)
##       + 终端一张表(噪声底 / 变化像素 / 倍数 / 包围盒 / 换算成码)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 差分阈值: 单通道**变亮**超过这个值才算"这里多了东西"。
##
## ★★为什么是"变亮"而不是"变了"(两版都试过, 有实测):
##   第一版用"任一通道差 > 0.06"。结果**对照组(羁绊档位 0, 我一笔都没画)也报 4.5~8.3 倍** ——
##   打开差分图一看: 高亮的是【两只龟的立绘 + 水面/地形的抖动网点】, 一个我画的形状都没有。
##   那是渲染层自己的时间噪声(shader TIME / 抖动), 幅度小但铺满全屏, 按"变了没"数就压过一切。
##   ⇒ 改成【变亮】且门槛拉到 0.18: 本层的东西全是加性亮色(环/柱/带/火花),
##     而噪声是小幅度的明暗抖动。换完之后对照组掉到个位数, 尺子才开始能用。
const DIFF_EPS := 0.18

var _s
var _freeze := false
var _out := ""
var _cam_off := Vector3.ZERO
var _fov0 := 40.0
var _rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("BLACKMAP", "1")      # 环境背景纯黑(复用已有 env)
	OS.set_environment("NO_TRAINER", "1")    # 场外监视者是干扰项
	_out = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "res://"
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	_s = RB.new()
	add_child(_s)
	for _i in range(20):
		await get_tree().process_frame
	_hide_ui()
	_hide_cursor()
	# ★★把【模拟】冻住, 但让 tween 照常跑。
	#   第一版没冻: 单位每帧都在走位/挥手/水面在动 ⇒ 噪声底上万、包围盒糊满全屏,
	#   对照组(档位 0)的"倍数"还是 5.7 —— 那个尺子量不出任何东西。
	#   `_hitstop > 0` 走的是项目自己的**顿帧**路径: `_sim_step` 不再 `_tick_unit`(单位不动),
	#   `_render_step` 也拿 frozen(立绘动画停)。而 Tween 挂在场景树上, 不受它影响 ⇒ 特效照播。
	_freeze = true
	if _s._cam != null:
		_fov0 = float(_s._cam.fov)
		_cam_off = _s._cam_base - _s.CAM_TARGET
	_place_window_right_middle()

	print("[SHOT] 视口 %s   ARENA %s" % [str(get_viewport().get_visible_rect().size), str(_s.ARENA)])
	_print_roster()

	await _run_all()

	print("")
	print("┌──────────────────────────┬────────┬────────┬───────┬────────────────────────────┐")
	print("│ case                     │ 噪声底 │ 变化px │ 倍数  │ 包围盒(px) / 换算成码       │")
	print("├──────────────────────────┼────────┼────────┼───────┼────────────────────────────┤")
	for r in _rows:
		print("│ %-24s │ %6d │ %6d │ %5.1f │ %-26s │" % [
			str(r["name"]), int(r["noise"]), int(r["diff"]), float(r["ratio"]), str(r["box"])])
	print("└──────────────────────────┴────────┴────────┴───────┴────────────────────────────┘")
	print("[SHOT] 完成。图在 %s" % _out)
	get_tree().quit(0)


# ════════════════════════════════════════════════════════════════════════════
#  逐个 case —— 每条都调【羁绊系统的真函数】, 不是直接点演出层
# ════════════════════════════════════════════════════════════════════════════
func _run_all() -> void:
	var left = _side_unit("left")
	var right = _side_unit("right")
	if left == null or right == null:
		print("[SHOT] ✗ 场上没凑齐左右单位, 退出")
		return

	# ── 枪·第一座炮台(炮位在场边 ⇒ 焦点给炮位) ────────────────────
	await _case("gun_turret_one", _s._gun_syn._turret_pos("left", 0), 2.2,
		func():
			_tiers({"枪": 3})
			_s._gun_syn._turret_one("left"))

	# ── 枪·第二座·护盾相位(蓝) ────────────────────────────────────
	await _case("gun_t2_shield", _s._gun_syn._turret_pos("left", 1), 1.6,
		func():
			_tiers({"枪": 6})
			_s._gun_syn._t2_shield_phase["left"] = true
			_s._gun_syn._turret_two("left"))

	# ── 枪·第二座·弹幕相位(橙) ────────────────────────────────────
	await _case("gun_t2_barrage", _s._gun_syn._turret_pos("left", 1), 1.6,
		func():
			_tiers({"枪": 6})
			_s._gun_syn._t2_shield_phase["left"] = false
			_s._gun_syn._turret_two("left"))

	# ── 法器·共鸣(全队同时立柱) ───────────────────────────────────
	await _case("staff_resonance", Vector2(left["pos"]), 2.0,
		func():
			_tiers({"法器": 4})
			_s._staff_syn._resonance())

	# ── 法器·净化 ─────────────────────────────────────────────────
	await _case("staff_dispel", Vector2(left["pos"]), 3.0,
		func():
			_tiers({"法器": 4})
			left["stun_until"] = _s._t + 5.0
			left["slow_until"] = _s._t + 5.0
			_s._staff_syn.dispel(left, 2))

	# ── 遗物·觉醒(本批最重的一个) ─────────────────────────────────
	await _case("relic_awaken", Vector2(left["pos"]), 1.6,
		func():
			_tiers({"遗物": 4})
			_s._relic_syn._awaken_vfx("left"))

	# ── 遗物·生死界跌破 50% ───────────────────────────────────────
	await _case("relic_gate_down", Vector2(left["pos"]), 3.0,
		func():
			_tiers({"遗物": 4})
			left["_relic_atk_bonus"] = 0.05
			left["_relic_gate_vfx"] = 1
			left["hp"] = float(left["maxHp"]) * 0.30
			_s._relic_syn._gate_tick())

	# ── 食物·学院(开场一次性) ─────────────────────────────────────
	await _case("food_academy", Vector2(left["pos"]), 2.0,
		func():
			_tiers({"食物": 2})
			for u in _s._units:
				if u is Dictionary:
					u.erase("_academy_done")
			_s._food_syn.apply_all())

	# ── 药水·战利品(从尸体向全队辐射) ─────────────────────────────
	await _case("potion_harvest", Vector2(right["pos"]), 1.6,
		func():
			_tiers({"药水": 3})
			_s._potion_syn._prey["left"] = right
			_s._potion_syn.on_death(right))

	# ── 盾·收殓(尸体→受益者的灵魂流) ──────────────────────────────
	await _case("shield_reap", (Vector2(left["pos"]) + Vector2(right["pos"])) * 0.5, 1.6,
		func():
			_tiers({"盾": 3})
			left["equips"] = [{"id": _an_equip_of("盾"), "star": 1}]
			_s._shield_syn.on_enemy_died(right))

	# ── 弓箭·腐蚀满 5 层 ──────────────────────────────────────────
	await _case("bow_corrode_full", Vector2(right["pos"]), 3.0,
		func():
			_tiers({"弓箭": 3})
			for u in _s._units:
				if u is Dictionary:
					u["corrode_stacks"] = 0
					u["_corrode_vfx"] = 0
			for i in range(5):
				_s._bow_syn._t_corrode = 0.0
				_s._bow_syn.tick(3.0))

	# ── 奇械·冰封 ─────────────────────────────────────────────────
	await _case("gadget_freeze", Vector2(right["pos"]), 3.0,
		func():
			_tiers({"奇械": 2})
			right["_gad_freeze_cd"] = 0.0
			right["_gad_freeze_immune"] = 0.0
			for i in range(90):
				_s._gadget_syn.on_hit(left, right)
				if _s._vfx._syn.alive_count("polygon_ring") > 0:
					break)

	# ── 奇械·僵硬跨阈值 ───────────────────────────────────────────
	await _case("gadget_stiff", Vector2(right["pos"]), 3.0,
		func():
			_tiers({"奇械": 4})
			right["stiff_stacks"] = 0
			right["_stiff_vfx"] = 0
			for i in range(5):
				_s._gadget_syn.add_stiff(right, 1))

	# ══ ★对照组: 同一条真入口, 只把羁绊档位改成 0 ══════════════════
	#    它们应该只剩噪声底 —— 这是把"我画的"与"地图装饰/别的特效"分开的硬办法。
	await _case("CTRL_resonance_tier0", Vector2(left["pos"]), 2.0,
		func():
			_tiers({})
			_s._staff_syn._resonance())

	await _case("CTRL_corrode_tier0", Vector2(right["pos"]), 3.0,
		func():
			_tiers({})
			for u in _s._units:
				if u is Dictionary:
					u["corrode_stacks"] = 0
					u["_corrode_vfx"] = 0
			for i in range(5):
				_s._bow_syn._t_corrode = 0.0
				_s._bow_syn.tick(3.0))


## 跑一条: 复位 → 摆相机 → 两张基线(噪声底) → 触发 → 连拍 5 张 → 取变化最大的那张出图。
func _case(nm: String, focus: Vector2, zoom: float, fire: Callable) -> void:
	_tiers({})                                   # 拍基线时把档位清掉, 免得系统自己 tick 出东西
	_s._vfx._syn.clear()
	await get_tree().process_frame
	_aim(focus, zoom)
	await get_tree().process_frame
	_aim(focus, zoom)
	var a2: Image = await _grab()
	# ★★噪声底必须跨【和命中段完全相同的帧数】测。
	#   第一版只拍相邻两帧当噪声底(=12), 而命中段跨了 10 帧 —— 尺子长度都不一样。
	#   结果对照组(羁绊档位 0、我一笔都没画)也报"315 倍", 那个数是水面/环境 shader
	#   在这 10 帧里自己走的 TIME, 不是我画的。⇒ 先空跑一段一模一样长的, 取峰值当底。
	var noise := 0
	for i in range(5):
		var nimg: Image = await _grab()
		noise = maxi(noise, _diff_count(a2, nimg))
		if i == 4:
			nimg.save_png("%s/%s_noise.png" % [_out, nm])
		await get_tree().process_frame

	fire.call()

	var best: Image = null
	var best_n := -1
	var best_i := -1
	for i in range(5):                            # ★"每个效果至少看 5 遍" = 生命周期上 5 个采样点
		var img: Image = await _grab()
		var n: int = _diff_count(a2, img)
		img.save_png("%s/%s_hit%d.png" % [_out, nm, i])
		if n > best_n:
			best_n = n
			best = img
			best_i = i
		await get_tree().process_frame
	a2.save_png("%s/%s_base.png" % [_out, nm])

	var box: Rect2i = _diff_box(a2, best)
	var hi: Image = _diff_highlight(a2, best)
	hi.save_png("%s/%s_diff.png" % [_out, nm])

	# ★标定: 拿真实相机把两个相距 100 码的场地点投到屏幕上, 量出"多少屏幕像素 = 1 码"。
	var ppy: float = _px_per_yard(focus)
	var desc := "无变化"
	if box.size.x > 0:
		desc = "%dx%d @(%d,%d) ≈ %.0fx%.0f 码" % [
			box.size.x, box.size.y, box.position.x, box.position.y,
			float(box.size.x) / maxf(0.001, ppy), float(box.size.y) / maxf(0.001, ppy)]
	print("[SHOT] %-22s zoom=%.1f  %.3f px/码  噪声底=%d  峰值(第%d张)=%d  倍数=%.1f  盒=%s" % [
		nm, zoom, ppy, noise, best_i, best_n, float(best_n) / maxf(1.0, float(noise)), desc])
	_rows.append({"name": nm, "noise": noise, "diff": best_n,
		"ratio": float(best_n) / maxf(1.0, float(noise)), "box": desc})
	_tiers({})
	_s._vfx._syn.clear()


# ════════════════════════════════════════════════════════════════════════════
#  工具
# ════════════════════════════════════════════════════════════════════════════

## ★每帧把顿帧续上 —— `_sim_step` 里 `_hitstop -= dt` 会把它耗掉。
## Main 是 RB 的父节点 ⇒ 本函数先于 RB._process 执行, 这一帧就生效。
func _process(_d: float) -> void:
	if _freeze and _s != null and is_instance_valid(_s):
		_s._hitstop = 9999.0


## ⚠ 两边都要清 —— 只清 left 的话, right 的羁绊会在拍基线时自己 tick 出东西。
func _tiers(d: Dictionary) -> void:
	_s._synergy._by_side["left"] = d.duplicate()
	_s._synergy._by_side["right"] = {}


## 真·拉近: 改 fov(等效长焦), 不是把截图放大。★必须写 `_cam_zoom_base` ——
## `battle_render._update_camera_shake` 每帧无条件 `_cam.position = _cam_zoom_base`。
func _aim(f: Vector2, zoom: float) -> void:
	if _s._cam == null or not is_instance_valid(_s._cam):
		return
	var w: Vector3 = _s._world_pos(f, 1.0)
	_s._cam_zoom_base = w + _cam_off
	_s._cam.position = _s._cam_zoom_base
	_s._cam.fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov0 * 0.5)) / maxf(0.2, zoom))), 1.2, 90.0)
	_s._shake_amp = 0.0


## ★这就是"标定"。不假设 0.69 —— 每个 case 各量各的(zoom 不同, 这个数就不同)。
func _px_per_yard(f: Vector2) -> float:
	if _s._cam == null:
		return 0.0
	var p0: Vector2 = _s._cam.unproject_position(_s._world_pos(f, 0.0))
	var p1: Vector2 = _s._cam.unproject_position(_s._world_pos(f + Vector2(100.0, 0.0), 0.0))
	return p0.distance_to(p1) / 100.0


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## b 比 a【亮了】多少 —— 只认"多出来的光", 不认明暗抖动。
func _brighter(a: Color, b: Color) -> bool:
	return (b.r - a.r) > DIFF_EPS or (b.g - a.g) > DIFF_EPS or (b.b - a.b) > DIFF_EPS


func _diff_count(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_width() != b.get_width():
		return -1
	var n := 0
	for y in range(0, a.get_height(), 2):        # 隔行采样: 全量太慢, 比值口径一致即可
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if _brighter(ca, cb):
				n += 1
	return n


func _diff_box(a: Image, b: Image) -> Rect2i:
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if _brighter(ca, cb):
				x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## 变化像素高亮成品红, 其余压暗 —— 一眼看出"我画的那一坨长什么形状、在哪"。
func _diff_highlight(a: Image, b: Image) -> Image:
	var o := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if _brighter(ca, cb):
				o.set_pixel(x, y, cb)
			else:
				o.set_pixel(x, y, Color(cb.r * 0.16, cb.g * 0.16, cb.b * 0.16, 1.0))
	return o


func _side_unit(side: String):
	for u in _s._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side \
				and not u.get("_isEgg", false) and not u.get("is_trainer", false):
			return u
	return null


func _an_equip_of(t: String) -> String:
	var f := FileAccess.open("res://data/p2eq-types.json", FileAccess.READ)
	if f == null:
		return ""
	var p = JSON.parse_string(f.get_as_text())
	if not (p is Dictionary):
		return ""
	var ids: Array = (p as Dictionary).keys()
	ids.sort()
	for k in ids:
		if str((p as Dictionary)[k]) == t:
			return str(k)
	return ""


func _hide_ui() -> void:
	if _s._ui_layer != null and is_instance_valid(_s._ui_layer):
		_s._ui_layer.visible = false


## 藏光标 —— 本项目的光标是自绘的绿龟爪(CanvasLayer layer=4096), 会画进截图。
func _hide_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	var ct = _s.get_node_or_null("/root/CursorTheme")
	if ct == null:
		return
	for c in ct.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false


## 花名册 —— 看图时对着名单认人, 不靠猜(上一轮把海草当特效就是靠猜)。
func _print_roster() -> void:
	print("[SHOT] ── 场上花名册 ──")
	for u in _s._units:
		if not (u is Dictionary):
			continue
		print("    %-12s %-6s pos=(%.0f, %.0f) hp=%.0f/%.0f" % [
			str(u.get("id", "?")), str(u.get("side", "")),
			float(u["pos"].x), float(u["pos"].y),
			float(u.get("hp", 0.0)), float(u.get("maxHp", 0.0))])


func _place_window_right_middle() -> void:
	var scr: Vector2i = DisplayServer.screen_get_size()
	var win: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_position(Vector2i(
		maxi(0, scr.x - win.x - 40), maxi(0, int((scr.y - win.y) * 0.5))))
