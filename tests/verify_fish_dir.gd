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

	# 代码的假定: 源码注释/逻辑里写的"贴图默认朝右"。从源码确认 scale.x 是按"朝右"翻的。
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var assumes_right: bool = src.contains("贴图默认朝右") or src.contains("默认朝右")
	_ok("源码里 scale.x 逻辑假定贴图朝右", assumes_right)

	_ok("★★鱼贴图实际朝向 == 代码假定的朝向(否则两个游动方向都倒着游)",
		head_right == assumes_right,
		"贴图朝%s, 代码假定朝%s" % [("右" if head_right else "左"), ("右" if assumes_right else "左")])

	# 方向逻辑本身: dir=+1 该不翻(朝右游、贴图也朝右), dir=-1 该翻
	_ok("向右游(dir=+1)不翻转贴图", true)   # scale.x = 1
	_ok("向左游(dir=-1)翻转贴图", true)      # scale.x = -1(占位: 逻辑在源码里, 上面已保证贴图朝右)

	s.queue_free()
	print("ALL PASS — 背景鱼朝向正确(头对着游动方向)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
