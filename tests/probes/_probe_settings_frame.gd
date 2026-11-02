extends Node
## 探针(临时): 设置屏「文字压边带」在**开弹框前/后**分别量到了什么。
## 判据逐字照抄 verify_ui_consistency 的 _audit 里那一段(framed 收集 + 最小包含框 + over),
## 但把中间量全打出来: 每个 Label 的控件矩形 / ink 矩形 / 被配到哪个框 / 框的边带 / over。

const MIN_WAIT := 2.0
const MAX_WAIT := 8.0

var _band_cache: Dictionary = {}
var _frame_cache: Dictionary = {}


func _is_frame_tex(tex: Texture2D) -> bool:
	var key := tex.resource_path
	if _frame_cache.has(key):
		return bool(_frame_cache[key])
	var img := tex.get_image()
	var ok := false
	if img != null and img.get_width() >= 16 and img.get_height() >= 16:
		var b := _band_of(tex)
		ok = b >= 3.0 and b <= 0.35 * float(img.get_width())
	_frame_cache[key] = ok
	return ok


func _band_of(tex: Texture2D) -> float:
	var key := tex.resource_path
	if _band_cache.has(key):
		return float(_band_cache[key])
	var img := tex.get_image()
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var ctr := img.get_pixel(cx, cy)
	var bl := 0
	var bt := 0
	if ctr.a < 0.04:
		for x in range(0, cx):
			if img.get_pixel(x, cy).a < 0.04 and x > 0:
				bl = x
				break
		for y in range(0, cy):
			if img.get_pixel(cx, y).a < 0.04 and y > 0:
				bt = y
				break
	else:
		for x2 in range(cx, 0, -1):
			var c := img.get_pixel(x2, cy)
			if c.a < 0.04 or maxf(maxf(absf(c.r - ctr.r), absf(c.g - ctr.g)), absf(c.b - ctr.b)) > 0.12:
				bl = x2
				break
		for y2 in range(cy, 0, -1):
			var c2 := img.get_pixel(cx, y2)
			if c2.a < 0.04 or maxf(maxf(absf(c2.r - ctr.r), absf(c2.g - ctr.g)), absf(c2.b - ctr.b)) > 0.12:
				bt = y2
				break
	var band := float(maxi(bl, bt))
	_band_cache[key] = band
	return band


func _ink_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var f: Font = l.get_theme_font("font")
	if f == null:
		return r
	var fs: int = l.get_theme_font_size("font_size")
	var ts: Vector2 = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		ts.x = minf(ts.x, r.size.x)
		ts.y = float(maxi(l.get_visible_line_count(), 1)) * f.get_height(fs)
	var w: float = minf(ts.x, r.size.x)
	var h: float = minf(ts.y, r.size.y)
	var x := r.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = r.position.x + (r.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = r.position.x + (r.size.x - w)
	var y := r.position.y
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = r.position.y + (r.size.y - h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = r.position.y + (r.size.y - h)
	return Rect2(x, y, w, h)


func _settle(root: Node) -> bool:
	var last := -1.0
	var same := 0
	var t0: float = float(Time.get_ticks_msec()) / 1000.0
	while float(Time.get_ticks_msec()) / 1000.0 - t0 < MAX_WAIT:
		await get_tree().process_frame
		if float(Time.get_ticks_msec()) / 1000.0 - t0 < MIN_WAIT:
			continue
		var acc := 0.0
		var st: Array = [root]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var r := (n as Control).get_global_rect()
				acc += r.position.x + r.position.y * 3.0 + r.size.x * 7.0 + r.size.y * 11.0
			for ch in n.get_children():
				st.append(ch)
		if absf(acc - last) < 0.5:
			same += 1
			if same >= 6:
				return true
		else:
			same = 0
		last = acc
	return false


## 框宿主 owner 与文字 txt 的树上关系(verify_ui_consistency._frame_owns 的判据同一套)
func _rel(owner, txt) -> String:
	if owner == null or txt == null:
		return "?"
	var n: Node = txt as Node
	while n != null:
		if n == owner:
			return "祖先★"
		n = n.get_parent()
	if (owner as Node).get_parent() != null \
		and (owner as Node).get_parent() == (txt as Node).get_parent():
		return "同父兄弟★"
	return "跨层"


func _path_of(n: Node, root: Node) -> String:
	var parts: Array = []
	var c: Node = n
	while c != null and c != root:
		parts.push_front("%s(%s)" % [str(c.name), c.get_class()])
		c = c.get_parent()
	return "/".join(parts)


## 照抄 _audit 的收集: labels(ink 矩形) + framed(三种框)
func _collect(root: Node) -> Dictionary:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var vp_area: float = maxf(1.0, vp.x * vp.y)
	var labels: Array = []
	var framed: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			if n is TextureRect and (n as TextureRect).texture != null \
				and c.size.x * c.size.y < vp_area * 0.20 \
				and c.size.x * c.size.y >= 4000.0 and minf(c.size.x, c.size.y) >= 40.0 \
				and _is_frame_tex((n as TextureRect).texture):
				var ft: Texture2D = (n as TextureRect).texture
				var sx: float = c.size.x / maxf(1.0, float(ft.get_width()))
				framed.append([c.get_global_rect(), _band_of(ft) * sx, 0.0,
					"TexRect %s" % _path_of(n, root), n])
			if n is NinePatchRect and (n as NinePatchRect).texture != null:
				var np := n as NinePatchRect
				framed.append([c.get_global_rect(), _band_of(np.texture), _band_of(np.texture),
					"NinePatch %s" % _path_of(n, root), n])
			if n is Label and str((n as Label).text).strip_edges().length() >= 1:
				var lb := n as Label
				labels.append([_ink_rect(lb), str(lb.text), lb.get_global_rect(),
					_path_of(n, root), n])
			for slot in ["panel", "normal", "background", "fill"]:
				if not c.has_theme_stylebox_override(slot):
					continue
				var sb = c.get_theme_stylebox(slot)
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					var bb := _band_of((sb as StyleBoxTexture).texture)
					framed.append([c.get_global_rect(), bb, bb,
						"SBTex[%s] %s <%s>" % [slot, _path_of(n, root),
							(sb as StyleBoxTexture).texture.resource_path.get_file()], n])
		for ch in n.get_children():
			st.append(ch)
	return {"labels": labels, "framed": framed}


func _dump(tag: String, root: Node, targets: Array) -> void:
	var col := _collect(root)
	var labels: Array = col["labels"]
	var framed: Array = col["framed"]
	print("──── %s ── labels=%d framed=%d" % [tag, labels.size(), framed.size()])
	for fi in range(framed.size()):
		var fr: Rect2 = framed[fi][0]
		print("   [框%2d] %s  rect=(%.0f,%.0f %.0fx%.0f) area=%.0f band=(%.1f,%.1f)" % [
			fi, str(framed[fi][3]), fr.position.x, fr.position.y, fr.size.x, fr.size.y,
			fr.size.x * fr.size.y, float(framed[fi][1]), float(framed[fi][2])])
	var flagged: Array = []
	for k in range(labels.size()):
		var lr: Rect2 = labels[k][0]
		var txt: String = str(labels[k][1])
		var cr: Rect2 = labels[k][2]
		var cc := lr.position + lr.size * 0.5
		var best := -1
		var best_a := 1.0e18
		for fi2 in range(framed.size()):
			var fr2: Rect2 = framed[fi2][0]
			if not fr2.has_point(cc):
				continue
			var ar: float = fr2.size.x * fr2.size.y
			if ar < best_a:
				best_a = ar
				best = fi2
		var want := false
		for t in targets:
			if txt.find(str(t)) >= 0:
				want = true
		if want:
			## ★把【所有】包住字块中心的框都摆出来 + 各自的 over + 与这段字的**关系**,
			##   这样"老规则配到谁 / 新规则配到谁 / 它自己那个框到底越没越"一眼可读。
			print("   ◇「%s」 所有包住它的框:" % txt.substr(0, 24))
			for fi3 in range(framed.size()):
				var frx: Rect2 = framed[fi3][0]
				if not frx.has_point(cc):
					continue
				var mx3: float = float(framed[fi3][1])
				var my3: float = float(framed[fi3][2])
				var inn: Rect2 = Rect2(frx.position + Vector2(mx3, my3),
					frx.size - Vector2(mx3, my3) * 2.0)
				var ov: float = maxf(maxf(inn.position.y - lr.position.y,
					(lr.position.y + lr.size.y) - (inn.position.y + inn.size.y)),
					maxf(inn.position.x - lr.position.x,
					(lr.position.x + lr.size.x) - (inn.position.x + inn.size.x)))
				var it: Rect2 = frx.intersection(lr)
				var la2: float = lr.size.x * lr.size.y
				print("        area=%-8.0f over=%-8.1f 覆盖=%.2f  关系=%-10s %s" % [
					frx.size.x * frx.size.y, ov,
					(it.size.x * it.size.y) / la2 if la2 > 0.0 else -1.0,
					_rel(framed[fi3][4], labels[k][4]), str(framed[fi3][3])])
		var over := -9999.0
		var frac := -1.0
		var inner := Rect2()
		if best >= 0:
			var fr3: Rect2 = framed[best][0]
			var inter2: Rect2 = fr3.intersection(lr)
			var la: float = lr.size.x * lr.size.y
			frac = (inter2.size.x * inter2.size.y) / la if la > 0.0 else -1.0
			var mx: float = float(framed[best][1])
			var my: float = float(framed[best][2])
			inner = Rect2(fr3.position + Vector2(mx, my), fr3.size - Vector2(mx, my) * 2.0)
			if la > 0.0 and inter2.size.x > 0.0 and frac >= 0.60 \
				and inner.size.x > 0.0 and inner.size.y > 0.0:
				over = maxf(maxf(inner.position.y - lr.position.y,
					(lr.position.y + lr.size.y) - (inner.position.y + inner.size.y)),
					maxf(inner.position.x - lr.position.x,
					(lr.position.x + lr.size.x) - (inner.position.x + inner.size.x)))
		if over > 2.0:
			flagged.append("%s+%.0f" % [txt.substr(0, 50), over])
		if not want:
			continue
		print("   ◆「%s」 %s" % [txt.substr(0, 24), str(labels[k][3])])
		print("       ctrl=(%.1f,%.1f %.1fx%.1f)  ink=(%.1f,%.1f %.1fx%.1f)  ctr=(%.1f,%.1f)" % [
			cr.position.x, cr.position.y, cr.size.x, cr.size.y,
			lr.position.x, lr.position.y, lr.size.x, lr.size.y, cc.x, cc.y])
		if best < 0:
			print("       配到的框: 无(中心不在任何框里) ⇒ 这一条判据碰不到它")
		else:
			print("       配到的框: [框%d] %s" % [best, str(framed[best][3])])
			print("       inner=(%.1f,%.1f %.1fx%.1f) 覆盖率=%.2f  over=%.1f" % [
				inner.position.x, inner.position.y, inner.size.x, inner.size.y, frac, over])
	print("   ★ 这一刻的 frame 违规表(%d 条): %s" % [flagged.size(), str(flagged)])


func _run_one(open_id: String, targets: Array) -> void:
	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	var s1: bool = await _settle(inst)
	print("═══════════ %s ═══════════ (settle1=%s)" % [open_id, str(s1)])
	_dump("开弹框【前】", inst, targets)
	if open_id == "conflict":
		inst._open_conflict_dialog()
	else:
		inst._ask_reset()
	var s2: bool = await _settle(inst)
	print("   (settle2=%s)" % str(s2))
	_dump("开弹框【后】", inst, targets)
	inst.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		if int(gs.season_total_battles) <= 0:
			gs.season_total_battles = 3
		print("[探针] bgm=%.2f sfx=%.2f debug_build=%s" % [
			float(gs.bgm_volume), float(gs.sfx_volume), str(OS.is_debug_build())])
	await get_tree().process_frame
	var tg := ["画质", "%", "两边的存档", "重置所有", "云端的存档", "音乐", "音效"]
	await _run_one("conflict", tg)
	await _run_one("reset", tg)
	print("PROBE DONE")
	get_tree().quit()
