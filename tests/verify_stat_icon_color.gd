extends Node

## verify_stat_icon_color.gd — 属性图标【纯白模板 + 运行时染色】这条链 (2026-10-01)
##
## 【由来】用户 2026-09-30「属性图标全部重做, 要像素风, 风格简洁统一, 你看 lol 没这么花」,
## 并在我交了一版彩色图之后点名「全部错误, 没有实现单色」。最终做法是:
##   素材 = 纯白剪影模板(22 张) → 消费点按属性 modulate 上色。
##
## 【这套做法有两个会静默坏掉的接缝, 本门禁就守这两个】
##   ① 素材那头: 哪天有人塞一张**彩色**图标进去, 画面上不会报错 —— modulate 是**乘法**,
##      乘在彩图上出来的是脏色。所以要量"每张图在不透明处只有一个 RGB, 且接近纯白"。
##   ② 代码那头: 哪天有人加一处新的属性图标消费点而**忘了染色**, 画面上就是一枚白方块。
##      白方块在暗底上看着像"图标就是白的", 不像 bug —— 所以靠源码扫描兜住。
##
## ★第 ⑤ 条量的是 `render_bbcode` 的**真实输出**(产品自己的账), 不是数我插的标记。
##   短式 `[img=W]` 没有 color 参数, 只要有人把长式改回短式, 这条当场红。

const ICON_DIR := "res://assets/sprites/stats"
const MAGENTA := Color("#ff00ff")   # stat_icon_color_of 故意不兜底成白, 没登记就返回这个

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	var names := _icon_names()
	print("  [分母] 盘上属性图标 %d 张" % names.size())
	_ok("★分母: 真扫到图标(扫到 0 张下面全是空检查)", names.size() >= 20,
		"只扫到 %d 张" % names.size())
	if names.size() < 20:
		_finish()
		return

	# ── ① 每张都登记了颜色, 没有落到洋红兜底 ──
	var unmapped: Array[String] = []
	var cols: Dictionary = {}
	for n in names:
		var c: Color = SkillText.stat_icon_color_of(n)
		if c.is_equal_approx(MAGENTA):
			unmapped.append(n)
		cols[c.to_html(false)] = true
	_ok("★每张图标都能解析出染色(没有落到洋红兜底)", unmapped.is_empty(),
		"没登记: %s" % str(unmapped))

	# ── ② 不是全染成一个色(全同 = 等于没染, 而且照样能过上一条) ──
	print("  [分母] 22 张解析出 %d 种不同颜色" % cols.size())
	_ok("★染出的颜色不少于 6 种(全同色 = 等于没染)", cols.size() >= 6,
		"只有 %d 种" % cols.size())

	# ── ③ 路径与 key 两种写法结果一致(消费点一半传路径一半传 key) ──
	_ok("★传路径与传 key 得到同一个色",
		SkillText.stat_icon_color_of("res://assets/sprites/stats/atk-icon.png")
			.is_equal_approx(SkillText.stat_icon_color_of("atk")),
		"路径 %s vs key %s" % [
			SkillText.stat_icon_color_of("res://assets/sprites/stats/atk-icon.png").to_html(false),
			SkillText.stat_icon_color_of("atk").to_html(false)])

	# ── ④ 素材真的是纯白模板(染色是乘法, 彩图乘出来是脏色) ──
	var not_white: Array[String] = []
	var multi: Array[String] = []
	for n in names:
		var tex: Texture2D = load("%s/%s-icon.png" % [ICON_DIR, n]) as Texture2D
		if tex == null:
			not_white.append("%s 载不出贴图" % n)
			continue
		var img := tex.get_image()
		var seen: Dictionary = {}
		var dimmest := 1.0
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a <= 0.03:
					continue
				seen[Color(px.r, px.g, px.b).to_html(false)] = true
				dimmest = minf(dimmest, maxf(px.r, maxf(px.g, px.b)))
		if seen.size() != 1:
			multi.append("%s 有 %d 种 RGB" % [n, seen.size()])
		elif dimmest < 0.90:
			not_white.append("%s 最亮通道只有 %.2f" % [n, dimmest])
	_ok("★每张在不透明处只有 1 种 RGB(彩图被 modulate 乘出来是脏色)", multi.is_empty(), str(multi))
	_ok("★那一种 RGB 接近纯白(模板必须是白的, 否则乘出来偏暗)", not_white.is_empty(), str(not_white))

	# ── ⑤ 文案里的内联图标: render_bbcode 的真实输出必须带 color= ──
	#    拿一条真含属性关键词的模板跑, 不自造标记。
	var bb: String = SkillText.render_bbcode("造成 {N:1*ATK} 伤害, 并提升攻击力与魔抗。",
		{"atk": 100.0}, {})
	var n_img := bb.count("[img")
	print("  [分母] render_bbcode 输出里 [img 共 %d 处" % n_img)
	_ok("★分母: 这条模板真的插出了内联图标(0 处 = 下一条是空检查)", n_img >= 2,
		"只有 %d 处, 原文: %s" % [n_img, bb])
	## ★不能数 `color=#` 的总数 —— 文字色 `[color=#xxxxxx]` 里也含这串(实测 2 枚图标时它是 5)。
	##   必须数【图标标签自己】那一段: `[img width=<px> color=#`。
	var n_dyed := bb.count("[img width=%d color=#" % SkillText.ICON_PX)
	_ok("★每一处 [img 都带 color=(短式 [img=W] 没有 color 参数, 改回去当场红)",
		n_img > 0 and n_dyed == n_img, "带 color 的 %d / 共 %d 处" % [n_dyed, n_img])
	var atk_hex := SkillText.stat_icon_color_of("atk").to_html(false)
	_ok("★内联图标的颜色就是该属性的固定身份色", bb.contains("atk-icon") and
		bb.contains("[img width=%d color=#%s]res://assets/sprites/stats/atk-icon.png" % [SkillText.ICON_PX, atk_hex]),
		"攻击应为 #%s" % atk_hex)

	# ── ⑥ 消费点都染了色 ──
	#    判据: 源码里引用了 sprites/stats/ 的 .gd, 必须也调了 stat_icon_color_of。
	var consumers := _gd_files_referencing("sprites/stats/")
	print("  [分母] 引用 sprites/stats/ 的 .gd 共 %d 个" % consumers.size())
	_ok("★分母: 真扫到消费点", consumers.size() >= 6, "只扫到 %d 个" % consumers.size())
	var undyed: Array[String] = []
	for f in consumers:
		var src := FileAccess.get_file_as_string(f)
		if not src.contains("stat_icon_color_of"):
			undyed.append(f.get_file())
	_ok("★每个消费点都调了 stat_icon_color_of(忘染 = 屏幕上一枚白方块, 不报错)",
		undyed.is_empty(), "没染的: %s" % str(undyed))

	_finish()


func _finish() -> void:
	print("ALL PASS — 属性图标纯白模板 + 运行时染色这条链" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _icon_names() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ICON_DIR)
	if d == null:
		return out
	for f in d.get_files():
		# 导出后资源是 .png.import → 运行时 get_files 可能给 .png 或 .png.import, 两种都认
		var b := str(f)
		if b.ends_with(".import"):
			b = b.trim_suffix(".import")
		if b.ends_with("-icon.png"):
			var k := b.trim_suffix("-icon.png")
			if not out.has(k):
				out.append(k)
	out.sort()
	return out


## 递归找所有引用了 `needle` 的 .gd —— ★不按"我以为的目录层级"走, 整棵树扫。
func _gd_files_referencing(needle: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://scripts"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(dir + "/" + sub)
		for f in d.get_files():
			if not str(f).ends_with(".gd"):
				continue
			var p: String = dir + "/" + str(f)
			var src := FileAccess.get_file_as_string(p)
			if src.contains(needle):
				out.append(p)
	out.sort()
	return out
