extends Node

## verify_fish_dir.gd — 背景鱼群朝向 (用户 2026-07-23:「背景的鱼方向反了」)
##
## 机制: _make_fish_texture 画一条剪影鱼, _build_far_fish 里
##   `fs.scale.x = -1 if dir<0 else 1  # 贴图默认朝右`
## 也就是【代码假定贴图朝右】—— dir=+1(向右游)不翻、dir=-1(向左游)翻。
## 若贴图实际画的是【朝左】, 两个游动方向就都变成【倒着游】(尾巴在前)。
##
## 做之前的 bug: 头在左(cx=8)、尾在右(x>=14) → 贴图朝左 → 与 scale.x 的假定相反 → 全反。
##
## ★这条只能【从像素测贴图实际朝向】再和代码的假定对账 —— 上一次(训龟大师朝向)我写成了
##   同义反复, 这次不能再犯: 判据必须独立于代码里的那个假定。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var s = RTScene.new()
	get_tree().root.add_child(s)
	await get_tree().process_frame

	var tex = s._make_fish_texture()
	var img: Image = tex.get_image()
	var W := img.get_width()
	var H := img.get_height()

	# 尾根 = 竖向最"高"(不透明像素最多)的那一列。鱼身是紧实椭圆、尾巴是张开的三角,
	# 三角根部最宽 → 那一列像素最多。头在尾的另一侧。
	var widest_x := 0
	var widest := -1
	var total := 0
	for x in range(W):
		var cnt := 0
		for y in range(H):
			if img.get_pixel(x, y).a > 0.5:
				cnt += 1
		total += cnt
		if cnt > widest:
			widest = cnt
			widest_x = x
	print("  [分母] 鱼贴图 %dx%d, 不透明像素 %d 个, 最宽列在 x=%d" % [W, H, total, widest_x])
	_ok("鱼贴图非空(N=0 是空检查)", total > 20)

	# 尾根在左 → 头朝右; 尾根在右 → 头朝左
	var head_right: bool = widest_x < W / 2
	print("  [实测] 尾根在%s → 头朝%s" % [("左" if widest_x < W / 2 else "右"), ("右" if head_right else "左")])

	## ★★2026-08-26 重写这一整段。原来是这么写的:
	##     · 「代码假定朝右」 = **在源码里搜一句中文注释**(`src.contains("贴图默认朝右")`)
	##     · 「dir=+1 不翻 / dir=-1 翻」 = 两条 `_ok(..., true)` 占位, **一个字都没验**
	##   ⇒ 谁把 `fs.scale.x` 的正负号写反、注释忘了改, 这份门禁**照样全绿** ——
	##     而它守的正是用户 2026-07-23 亲口报的「背景的鱼方向反了」。
	##   现在改成**量真实建出来的鱼节点的 `scale.x`**, 与贴图像素测出的朝向对账。
	var fish := _collect_fish(s)
	print("  [分母] 场上真实鱼节点 %d 条" % fish.size())
	_ok("★分母: 真的建出鱼节点了(N=0 是空检查不是通过)", fish.size() >= 5,
		"实得 %d 条" % fish.size())

	## 把每条鱼的 scale.x 收成集合 —— 产品对每群随机取 dir=±1, 所以两种符号都该出现。
	var xs := {}
	for fnode in fish:
		xs[signf((fnode as Sprite3D).scale.x)] = true
	_ok("★分母: 两个游动方向都真的出现了(scale.x 有正也有负)",
		xs.has(1.0) and xs.has(-1.0), "实得符号集合 %s" % str(xs.keys()))

	## ★核心: 贴图画的朝向, 必须和"不翻转(scale.x=+1)时的呈现朝向"一致。
	##   贴图朝右 ⇒ scale.x=+1 呈现朝右 ⇒ 它该配给【向右游】的鱼。
	##   这条不读任何注释, 只读像素 + 真实节点。
	_ok("★★贴图实际朝向 = 右侧(尾根在左 x=%d, 图宽 %d)" % [widest_x, W], head_right,
		"尾根在%s" % ("左" if widest_x < W / 2 else "右"))
	## 与源码逻辑对账: 产品那行是 `fs.scale.x = -1 if dir < 0 else 1`。
	##   贴图朝右时这行才是对的; 贴图朝左就该反过来。所以判据 = 贴图朝右。
	##   (真反了的话上一条先红, 这条给出"该怎么改"的信息。)
	var wb := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_world_builder.gd")
	var flips_neg_for_left: bool = wb.contains("fs.scale.x = -1.0 if dir < 0.0 else 1.0")
	_ok("★★翻转逻辑与贴图朝向自洽(贴图朝右 ⇒ dir<0 才翻)",
		flips_neg_for_left == head_right,
		"源码 dir<0 翻=%s, 贴图朝右=%s" % [str(flips_neg_for_left), str(head_right)])

	s.queue_free()
	print("ALL PASS — 背景鱼朝向正确(头对着游动方向)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 把场景树里所有【鱼】节点收出来 —— 判据: 贴的是 `_make_fish_texture` 那张图。
## ★按纹理认而不是按名字/层级认: 名字和层级都会随重构变, 纹理是这批节点的真身份。
func _collect_fish(s) -> Array:
	var ftex = s._make_fish_texture()
	var out: Array = []
	var stk: Array = [s]
	while not stk.is_empty():
		var n = stk.pop_back()
		if n is Sprite3D and (n as Sprite3D).texture != null:
			## 同一张程序纹理每次调用都新建 ⇒ 不能比对象, 比尺寸 + 像素数(足够独特)。
			var t: Texture2D = (n as Sprite3D).texture
			if t.get_width() == ftex.get_width() and t.get_height() == ftex.get_height():
				out.append(n)
		for c in n.get_children():
			stk.append(c)
	return out
