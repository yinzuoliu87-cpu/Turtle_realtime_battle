extends Node
## 临时探针(用完即删)。三件事:
##  A) 量 CodexScene._add_text 的【居中锚】偏多少(走真入口 + 门禁同一把尺子 Font.get_string_size)。
##  B) 数【双形态龟】详情页的网页盒 —— verify_ui_consistency 只量列表第一条,
##     形态切换钮只在熔岩龟/双头龟身上画, 棘轮从来没数到过它。
##  C) 把门禁的【文字压边带】判据推到**五个 Tab 的每一条**上 ——
##     这正是 verify_ui_consistency 的覆盖缺口(它只量第一条), 而 _add_text 的锚点一改,
##     受影响的 7 个 ox!=0 调用点分散在装备页/羁绊页/被动条/技能卡上。
## 判据逐字照抄 verify_ui_consistency: _band_of / _ink_rect / over > 2.0。

const SCN := preload("res://scenes/Codex.tscn")

const SAMPLES := ["近战斗士", "远程射手", "C", "SSS", "Lv 1", "945", "持续伤害", "羁绊赠送"]

var _band_cache: Dictionary = {}


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


## 一条详情页: 返回 [压边带命中数组, 网页盒数, 九宫格框数, 带字标签数]
func _audit_detail(detail: Control) -> Array:
	var framed: Array = []
	var labels: Array = []
	var web := 0
	for c in detail.get_children():
		if not (c is Control):
			continue
		var ctl := c as Control
		for slot in ["panel", "normal", "background", "fill"]:
			if not ctl.has_theme_stylebox_override(slot):
				continue
			var sb = ctl.get_theme_stylebox(slot)
			if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
				var bb := _band_of((sb as StyleBoxTexture).texture)
				framed.append([ctl.get_global_rect(), bb])
			elif sb is StyleBoxFlat:
				var f2 := sb as StyleBoxFlat
				if f2.border_width_top > 0 and f2.border_width_bottom > 0 \
						and f2.border_width_left > 0 and f2.border_width_right > 0 \
						and f2.bg_color.a < 0.95:
					web += 1
		if ctl is Label and str((ctl as Label).text).strip_edges() != "":
			labels.append([_ink_rect(ctl as Label), str((ctl as Label).text)])
	var hits: Array = []
	for k in range(labels.size()):
		var lr: Rect2 = labels[k][0]
		var cc := lr.position + lr.size * 0.5
		var best := -1
		var best_a := 1.0e18
		for fi in range(framed.size()):
			var fr: Rect2 = framed[fi][0]
			if not fr.has_point(cc):
				continue
			var ar: float = fr.size.x * fr.size.y
			if ar < best_a:
				best_a = ar
				best = fi
		if best < 0:
			continue
		var fr2: Rect2 = framed[best][0]
		var inter2: Rect2 = fr2.intersection(lr)
		var la: float = lr.size.x * lr.size.y
		if la <= 0.0 or inter2.size.x <= 0.0 or (inter2.size.x * inter2.size.y) / la < 0.60:
			continue
		var mx: float = float(framed[best][1])
		var inner := Rect2(fr2.position + Vector2(mx, mx), fr2.size - Vector2(mx, mx) * 2.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		var over: float = maxf(maxf(inner.position.y - lr.position.y,
			(lr.position.y + lr.size.y) - (inner.position.y + inner.size.y)),
			maxf(inner.position.x - lr.position.x,
			(lr.position.x + lr.size.x) - (inner.position.x + inner.size.x)))
		if over > 2.0:
			hits.append("%s+%.0f" % [str(labels[k][1]).substr(0, 18), over])
	return [hits, web, framed.size(), labels.size()]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var inst = SCN.instantiate()
	add_child(inst)
	for _i in range(20):
		await get_tree().process_frame

	print("=== A) _add_text 居中锚(ox=0.5) 实测偏移 ===")
	var worst := 0.0
	for s in SAMPLES:
		var want_cx := 400.0
		var lbl: Label = inst._add_text(want_cx, 300.0, str(s), 16, "#ffffff", 0.5, 0.5, true)
		await get_tree().process_frame
		var f: Font = lbl.get_theme_font("font")
		var real_w: float = f.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var off: float = (lbl.position.x + real_w / 2.0) - want_cx
		worst = maxf(worst, absf(off))
		print("  「%s」  真宽 %6.1f   旧式估宽(len*16*0.62) %6.1f   ⇒ 居中偏移 %+6.1f px"
			% [str(s), real_w, float(str(s).length()) * 16.0 * 0.62, off])
	print("  最大绝对偏移 = %.1f px" % worst)

	print("=== B) 双形态龟详情页 + C) 五个 Tab 逐条压边带 ===")
	var tabs: Array = ["pets", "equips", "synergies", "status"]
	var tot_hits: Array = []
	var tot_web := 0
	var tot_framed := 0
	var tot_lbl := 0
	var tot_n := 0
	var dualform := 0
	for tab in tabs:
		inst._switch_tab(str(tab))
		for _j in range(8):
			await get_tree().process_frame
		var n: int = inst._items.size()
		var t_hits: Array = []
		var t_web := 0
		for i in range(n):
			inst._select(i)
			for _k in range(3):
				await get_tree().process_frame
			var r: Array = _audit_detail(inst.detail)
			t_hits.append_array(r[0] as Array)
			t_web += int(r[1])
			tot_framed += int(r[2])
			tot_lbl += int(r[3])
			tot_n += 1
			var it = inst._items[i]
			if it is Dictionary:
				var mel = (it as Dictionary).get("meleeSkills", [])
				var vol = (it as Dictionary).get("volcanoSkills", [])
				if (mel is Array and not (mel as Array).is_empty()) \
						or (vol is Array and not (vol as Array).is_empty()):
					dualform += 1
					print("    [双形态] 「%s」 网页盒 %d / 框 %d / 压边带 %s"
						% [str((it as Dictionary).get("name", "?")), int(r[1]), int(r[2]), str(r[0])])
		print("  %-11s %3d 条   网页盒 %d   压边带 %d %s"
			% [str(tab), n, t_web, t_hits.size(), str(t_hits.slice(0, 6))])
		tot_hits.append_array(t_hits)
		tot_web += t_web
	print("  ── 合计: 量了 %d 条详情页 / 框 %d 个 / 带字标签 %d 个 ──" % [tot_n, tot_framed, tot_lbl])
	print("  分母: 双形态龟 %d 只(0 就是空检查)" % dualform)
	print("  网页盒 %d   压边带 %d   %s" % [tot_web, tot_hits.size(), str(tot_hits.slice(0, 10))])
	print("PROBE DONE")
	get_tree().quit()
