extends Node
## DEV 探针 —— 「画了但玩家看不见」全场排查(11-22)
##
## 由来: 用户 11-22「闪电龟被动的图标现在是看不到吗？」→ 查出是层数数字压在 24px 图标正中(9651e1d5 修);
##   用户接着「那诸如此类肯定还有很多问题啊」⇒ 同一类要一次量全, 不靠一处处看截图。
##
## 跑法(无头): SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_cover_sweep.tscn
##   借 verify_rules_fingerprint 那 5 局(裁判真入口; 覆盖 28 龟 / 全部装备 / 顶档羁绊 / 训龟大师),
##   每 SAMPLE_EVERY 个 sim 步量一遍画面上的节点, 并给每种单位(龟 / 小将 / 召唤物 / 大师)各开一次详情面板。
##
## 量三类(都按「出现过多少次 / 其中出问题多少次」聚合, 比例高的才是结构性问题, 飘字路过这种偶发的比例低):
##   A 图标被文字压住: 小图标(6~110px)的中心被画在它之后的非空文字罩住
##   B 建了却看不见: 可见的图标没贴图 / 缩成 0 / 整个在屏幕外
##   C 3D 标记被 2D 盖住: 单位身边的广告牌精灵, 六成以上面积被血条 / 牌子 / 徽章 / 卡片这些 2D 节点盖住
## 输出: .out/cover_sweep.txt

const FP := preload("res://tests/verify_rules_fingerprint.gd")
const SAMPLE_EVERY := 12
const ICON_MIN := 6.0
const ICON_MAX := 110.0
const OVERLAY_MAX_AREA := 22000.0     # 2D 遮挡物上限(超过的是全屏底板 / 暗角, 不算「盖住标记」)

var _fp
var _n := 0
var _samples := 0
var _A := {}
var _B := {}
var _C := {}
var _panel_done := {}
var _panel_at := -100
var _orph := {"samples": 0, "max": 0, "lanes": {}}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_anchor_ts = int(FP.SC.PIN_WEEK_ANCHOR)
	_fp = FP.new()
	var only := int(OS.get_environment("SWEEP_ONLY")) if OS.get_environment("SWEEP_ONLY") != "" else -1
	for i in range(FP.CASES.size()):
		if only >= 0 and i != only:
			continue
		var c: Dictionary = FP.CASES[i]
		var t0 := Time.get_ticks_msec()
		var res: Dictionary = await RefereeRunner.run(self, _fp._job(c), func(bt) -> void:
			bt.sim_stepped.connect(func() -> void: _on_step(bt)))
		print("[case] %s · %d 步 · %d ms · 累计采样 %d" % [str(c["tag"]), int(res.get("steps", 0)), Time.get_ticks_msec() - t0, _samples])
	_report()
	_fp.free()
	get_tree().quit(0)


func _on_step(bt) -> void:
	_n += 1
	if _n % SAMPLE_EVERY != 0:
		return
	if not is_instance_valid(bt) or bt._cam == null or not is_instance_valid(bt._cam):
		return
	_samples += 1
	var items: Array = []
	var layers: Array = []
	_find_layers(bt, layers)
	layers.sort_custom(func(a, b) -> bool: return a.layer < b.layer)
	for cl in layers:
		if cl.visible:
			_collect(cl, items)
	var vp: Rect2 = bt.get_viewport().get_visible_rect()
	if _samples - _panel_at > 2:
		_measure_2d(items, vp)
	_measure_3d(bt, items, vp)
	_count_orphans(bt)
	_maybe_open_panel(bt)


## ── 2D: 收可见 Control(按绘制先后) ──
func _find_layers(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is CanvasLayer:
			out.append(ch)
		elif not (ch is CanvasItem):
			_find_layers(ch, out)


func _collect(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is CanvasItem:
			if not (ch as CanvasItem).visible:
				continue
			if ch is Control:
				out.append(ch)
			_collect(ch, out)
		elif not (ch is CanvasLayer):
			_collect(ch, out)


## 实际绘制用的 z: 一路往上加(z_as_relative), 到画布层为止
func _ez(c: CanvasItem) -> int:
	var z := 0
	var n: Node = c
	while n != null and n is CanvasItem:
		z += (n as CanvasItem).z_index
		if not (n as CanvasItem).z_as_relative:
			break
		n = n.get_parent()
	return z


func _queued(n: Node) -> bool:
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


func _grect(c: Control) -> Rect2:
	return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)


func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	var first := true
	while n != null and n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		if first:
			a *= (n as CanvasItem).self_modulate.a
			first = false
		n = n.get_parent()
	return a


## 节点「是哪一种」: 往上数到画布层的节点名, 去掉数字 / 自动名里的 @ 段, 同一种元素聚到一起
func _ctx(n: Node) -> String:
	var parts: Array = []
	var cur: Node = n
	var k := 0
	while cur != null and not (cur is CanvasLayer) and k < 5:
		var nm := str(cur.name)
		if nm.begins_with("@"):
			nm = cur.get_class()
		var rx := RegEx.create_from_string("[0-9]+")
		nm = rx.sub(nm, "#", true)
		parts.push_front(nm)
		cur = cur.get_parent()
		k += 1
	return "/".join(parts)


func _tex_name(t: Texture2D) -> String:
	if t == null:
		return "<无贴图>"
	if t.resource_path != "":
		return t.resource_path.get_file()
	return "<" + t.get_class() + ">"


func _bump(d: Dictionary, key: String, hit: bool, ex: String) -> void:
	var e: Dictionary = d.get(key, {"seen": 0, "hit": 0, "ex": ""})
	e["seen"] = int(e["seen"]) + 1
	if hit:
		e["hit"] = int(e["hit"]) + 1
		if str(e["ex"]) == "":
			e["ex"] = ex
	d[key] = e


func _measure_2d(items: Array, vp: Rect2) -> void:
	var labels: Array = []
	for i in range(items.size()):
		var c = items[i]
		if c is Label and str((c as Label).text).strip_edges() != "" and _alpha(c) > 0.3:
			labels.append([i, c, _ez(c)])
	for i in range(items.size()):
		var c = items[i]
		if not (c is TextureRect):
			continue
		var tr := c as TextureRect
		if _queued(tr):
			continue
		var r := _grect(tr)
		var a := _alpha(tr)
		var key := _tex_name(tr.texture) + " @ " + _ctx(tr)
		## B: 可见却看不见
		if a > 0.1:
			var bad := ""
			if tr.texture == null:
				bad = "没贴图"
			elif r.size.x < 2.0 or r.size.y < 2.0:
				bad = "缩成 %.1f×%.1f" % [r.size.x, r.size.y]
			elif not vp.intersects(r):
				bad = "在屏幕外 %s" % str(r)
			_bump(_B, key, bad != "", bad)
		## A: 小图标中心被后画的文字罩住
		if tr.texture == null or a < 0.3:
			continue
		if r.size.x < ICON_MIN or r.size.y < ICON_MIN or r.size.x > ICON_MAX or r.size.y > ICON_MAX:
			continue
		if not vp.intersects(r):
			continue
		var cen := r.get_center()
		var hit := ""
		var tz := _ez(tr)
		for pair in labels:
			## 画在它上面 = z 更高, 或 z 相同而在节点树里更靠后
			if int(pair[2]) < tz or (int(pair[2]) == tz and int(pair[0]) <= i):
				continue
			var lb: Label = pair[1]
			var lr := _grect(lb)
			## 标签框上下有行距留白, 按字形大致所在取中间一段(上去 22%、下去 12%)
			var gl := Rect2(lr.position.x, lr.position.y + lr.size.y * 0.22, lr.size.x, lr.size.y * 0.66)
			if gl.has_point(cen):
				hit = "「%s」%s" % [str(lb.text).left(12), _ctx(lb)]
				break
		_bump(_A, key, hit != "", hit)


## ── 3D: 单位身边的广告牌精灵被 2D 盖住 ──
func _measure_3d(bt, items: Array, vp: Rect2) -> void:
	var covers: Array = []
	for c in items:
		if not (c is TextureRect or c is ColorRect or c is Panel or c is PanelContainer or c is Range or c is NinePatchRect):
			continue
		if _alpha(c) < 0.5:
			continue
		var r := _grect(c)
		var ar := r.size.x * r.size.y
		if ar < 16.0 or ar > OVERLAY_MAX_AREA:
			continue
		covers.append([r, _ctx(c)])
	var unit_pos: Array = []
	var unit_sprites: Array = []
	for u in bt._units:
		if u is Dictionary and u.get("alive", false):
			unit_pos.append(bt._world_pos(u["pos"], 0.0))
			if u.has("sprite") and is_instance_valid(u["sprite"]):
				unit_sprites.append(u["sprite"])
	var cam: Camera3D = bt._cam
	var right: Vector3 = cam.global_transform.basis.x.normalized()
	var up: Vector3 = cam.global_transform.basis.y.normalized()
	var sprites: Array = []
	_find_sprites(bt, sprites)
	for sp in sprites:
		var s3 := sp as Sprite3D
		if s3.texture == null or not s3.is_visible_in_tree() or s3.modulate.a < 0.3:
			continue
		if not BattleWorldBuilder._is_billboard(s3):
			continue
		var skip := false
		for us in unit_sprites:
			if is_same(us, s3):
				skip = true
				break
		if skip:
			continue
		var gp := s3.global_position
		var near := false
		for p in unit_pos:
			var d: Vector3 = p - gp
			if Vector2(d.x, d.z).length() < 1.6:
				near = true
				break
		if not near:
			continue
		var q := BattleWorldBuilder.sprite_quad(s3)
		var sc: Vector3 = s3.global_transform.basis.get_scale()
		var pts: Array = []
		for cx in [q.position.x, q.end.x]:
			for cy in [q.position.y, q.end.y]:
				var w: Vector3 = gp + right * cx * sc.x + up * cy * sc.y
				if cam.is_position_behind(w):
					continue
				pts.append(_to_screen(cam, cam.unproject_position(w)))
		if pts.size() < 4:
			continue
		var mn: Vector2 = pts[0]
		var mx: Vector2 = pts[0]
		for p2 in pts:
			mn = mn.min(p2)
			mx = mx.max(p2)
		var sr := Rect2(mn, mx - mn)
		if sr.size.x * sr.size.y < 64.0 or not vp.intersects(sr):
			continue
		var tot := 0
		var cov := 0
		var by := ""
		for gx in range(6):
			for gy in range(6):
				var pt := sr.position + Vector2((gx + 0.5) / 6.0 * sr.size.x, (gy + 0.5) / 6.0 * sr.size.y)
				tot += 1
				for cv in covers:
					if (cv[0] as Rect2).has_point(pt):
						cov += 1
						if by == "":
							by = str(cv[1])
						break
		var key := _tex_name(s3.texture) + " @ " + _ctx3(s3)
		_bump(_C, key, float(cov) / float(tot) >= 0.6, "盖住 %d%% 主要被 %s" % [cov * 100 / tot, by])


## 相机画在子视口里(WorldLayer/ViewportContainer/World3D): 子视口像素 → 主视口像素
func _to_screen(cam: Camera3D, p: Vector2) -> Vector2:
	var sv := cam.get_viewport()
	var ct = sv.get_parent() if sv != null else null
	if ct is SubViewportContainer and sv is SubViewport:
		var r := (ct as Control).get_global_transform_with_canvas() * Rect2(Vector2.ZERO, (ct as Control).size)
		var vs := Vector2((sv as SubViewport).size)
		return r.position + p * (r.size / vs)
	return p


func _find_g3(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			out.append(ch)
		_find_g3(ch, out)


func _find_sprites(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is Sprite3D:
			out.append(ch)
		_find_sprites(ch, out)


func _ctx3(n: Node) -> String:
	var parts: Array = []
	var cur: Node = n
	for _k in range(3):
		if cur == null:
			break
		var nm := str(cur.name)
		if nm.begins_with("@"):
			nm = cur.get_class()
		nm = RegEx.create_from_string("[0-9]+").sub(nm, "#", true)
		parts.push_front(nm)
		cur = cur.get_parent()
	return "/".join(parts)


## ── 详情面板: 每种单位开一次, 下一次采样量它 ──
func _maybe_open_panel(bt) -> void:
	if _samples - _panel_at < 10:
		return
	for u in bt._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var k := str(u.get("id", "")) + ("|tr" if u.get("is_trainer", false) else "") + ("|egg" if u.get("_isEgg", false) else "")
		if _panel_done.has(k):
			continue
		_panel_done[k] = true
		bt._hud._show_unit_info_panel(u)
		_panel_at = _samples
		return


func _report() -> void:
	var lines: Array = []
	lines.append("采样 %d 次 · 开过详情面板 %d 种单位: %s" % [_samples, _panel_done.size(), ", ".join(PackedStringArray(_panel_done.keys()))])
	for pair in [["A 图标中心被文字压住", _A], ["B 可见却看不见(没贴图 / 缩成 0 / 屏幕外)", _B], ["C 单位身边的 3D 标记六成以上被 2D 盖住", _C]]:
		var d: Dictionary = pair[1]
		var keys: Array = d.keys()
		var tot_seen := 0
		for k in keys:
			tot_seen += int(d[k]["seen"])
		keys = keys.filter(func(k) -> bool: return int(d[k]["hit"]) > 0)
		keys.sort_custom(func(a, b) -> bool:
			var ra: float = float(d[a]["hit"]) / float(d[a]["seen"])
			var rb: float = float(d[b]["hit"]) / float(d[b]["seen"])
			return ra > rb if absf(ra - rb) > 0.001 else int(d[a]["hit"]) > int(d[b]["hit"]))
		lines.append("")
		lines.append("== %s · 种类 %d(分母: 量过 %d 种 / %d 次) ==" % [str(pair[0]), keys.size(), d.size(), tot_seen])
		for k in keys:
			var e: Dictionary = d[k]
			lines.append("%5.0f%%  %4d/%-5d  %s  ‖ %s" % [100.0 * float(e["hit"]) / float(e["seen"]), int(e["hit"]), int(e["seen"]), str(k), str(e["ex"])])
	lines.append("")
	lines.append("== D 换路后残留的头顶徽章(不属于任何现存单位却可见): %d 次采样里出现, 同屏最多 %d 个 · 例 %s ==" % [int(_orph["samples"]), int(_orph["max"]), str(_orph["lanes"])])
	var f := FileAccess.open(DevOut.prep("res://.out/cover_sweep.txt"), FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(lines)) + "\n")
	f.close()
	print("\n".join(PackedStringArray(lines.slice(0, 12))))
	print("SWEEP DONE")


## D: 换路后留下的头顶徽章 —— _ui_layer 里长得像徽章(有 icon + num 子节点)、可见、却不在任何现存单位的池里
func _count_orphans(bt) -> void:
	var owned: Array = []
	for u in bt._units:
		if u is Dictionary:
			for k in ["_hbrow_stack", "_hbrow_status"]:
				for b in u.get(k, []):
					owned.append(b)
	var n := 0
	var ex := ""
	for c in bt._ui_layer.get_children():
		if c is Control and c.visible and not c.is_queued_for_deletion() and c.get_node_or_null("icon") != null and c.get_node_or_null("num") != null:
			var mine := false
			for b in owned:
				if is_same(b, c):
					mine = true
					break
			if not mine:
				n += 1
				if ex == "":
					var ic := c.get_node("icon") as TextureRect
					ex = "%s 数字「%s」缩放 %.2f 位置 %s" % [_tex_name(ic.texture), (c.get_node("num") as Label).text, c.scale.x, str(c.position)]
	if n > 0:
		_orph["samples"] = int(_orph["samples"]) + 1
		_orph["max"] = maxi(int(_orph["max"]), n)
		var lane := "epoch%d" % int(bt._dl_sys.lane_epoch)
		if not (_orph["lanes"] as Dictionary).has(lane):
			(_orph["lanes"] as Dictionary)[lane] = ex

