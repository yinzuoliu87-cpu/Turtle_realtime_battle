extends SceneTree
## 像素 diff 工具 (dev) — 客观对比 PoC 截图 vs Godot 截图, 高亮超阈值差异区。
## 用法: DIFF_A=poc.png DIFF_B=godot.png DIFF_OUT=diff.png DIFF_T=0.12 godot --headless -s diff_images.gd
##   DIFF_A=PoC 基准, DIFF_B=Godot, DIFF_OUT=差异图(红=差异, 灰=Godot底), DIFF_T=色距阈值 0..1 (默认0.12)。
## 输出: 差异图 PNG + 控制台打印差异像素% (整体 + 分九宫格, 便于定位是哪块差)。

func _init() -> void:
	var pa := OS.get_environment("DIFF_A")
	var pb := OS.get_environment("DIFF_B")
	var po := OS.get_environment("DIFF_OUT") if OS.has_environment("DIFF_OUT") else "res://_diff.png"
	var thresh := 0.12
	if OS.has_environment("DIFF_T"):
		thresh = OS.get_environment("DIFF_T").to_float()
	var a := Image.new()
	var b := Image.new()
	if a.load(pa) != OK:
		print("DIFF ERROR: load A failed: ", pa); quit(); return
	if b.load(pb) != OK:
		print("DIFF ERROR: load B failed: ", pb); quit(); return
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	if b.get_size() != a.get_size():
		b.resize(a.get_width(), a.get_height(), Image.INTERPOLATE_BILINEAR)
	var w := a.get_width()
	var h := a.get_height()
	var da := a.get_data()
	var db := b.get_data()
	var n := da.size()
	var dd := PackedByteArray()
	dd.resize(n)
	var tb := thresh * 441.673   # sqrt(3)*255 → 阈值换成 0..441 的 RGB 欧氏距离
	var tb2 := tb * tb
	# 九宫格差异计数 (定位是哪块差)
	var grid := [0,0,0, 0,0,0, 0,0,0]
	var gtot := [0,0,0, 0,0,0, 0,0,0]
	var ndiff := 0
	var idx := 0
	for y in range(h):
		var gy := mini(2, y * 3 / h)
		for x in range(w):
			var dr := float(da[idx]) - float(db[idx])
			var dg := float(da[idx + 1]) - float(db[idx + 1])
			var dbb := float(da[idx + 2]) - float(db[idx + 2])
			var dist2 := dr * dr + dg * dg + dbb * dbb
			var gi := gy * 3 + mini(2, x * 3 / w)
			gtot[gi] += 1
			if dist2 > tb2:
				ndiff += 1
				grid[gi] += 1
				dd[idx] = 255; dd[idx + 1] = 0; dd[idx + 2] = 0; dd[idx + 3] = 255
			else:
				var lum := int((float(db[idx]) * 0.3 + float(db[idx + 1]) * 0.59 + float(db[idx + 2]) * 0.11) * 0.5)
				dd[idx] = lum; dd[idx + 1] = lum; dd[idx + 2] = lum; dd[idx + 3] = 255
			idx += 4
	var diff := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dd)
	diff.save_png(po)
	var total := w * h
	var pct := 100.0 * ndiff / float(total)
	print("DIFF %.2f%% (>%.2f) %d/%d  size=%dx%d -> %s" % [pct, thresh, ndiff, total, w, h, po])
	var names := ["TL","TC","TR", "ML","MC","MR", "BL","BC","BR"]
	var parts := PackedStringArray()
	for i in range(9):
		var gp: float = 100.0 * float(grid[i]) / float(maxi(1, gtot[i]))
		if gp >= 1.0:
			parts.append("%s=%.0f%%" % [names[i], gp])
	print("  hotspots: ", " ".join(parts) if parts.size() > 0 else "(none >1%)")
	quit()
