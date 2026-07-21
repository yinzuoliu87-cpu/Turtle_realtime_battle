extends Node
## verify_cam_pan.gd — 守卫「视角移动」(用户 2026-07-21 需求5)
##
## 「在放大功能的基础上设计个视角移动, 比如手机端触屏拖动来移动摄像机位置, 电脑端就按住推动」
##
## ★这个功能有三个会互相打架的坑, 每个都单独守:
##   A. 震屏每帧无条件覆写 _cam.position —— 平移若直接写 position 会被逐帧抹掉,
##      必须并进 _cam_zoom_base 这条唯一通路。
##   B. 拖动与点选冲突 —— 原来"按下即判定点选/关面板", 加了拖动后每次拖屏都会误开/误关详情面板,
##      必须按位移阈值区分。
##   C. 缩放锚点 —— 缩放若恒围绕战场原点, 平移到边角再缩放视野会被"吸"回中心, 手感很怪。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame

	_test_pan_moves_camera(s)
	_test_clamp(s)
	_test_zoom_anchor_follows_pan(s)
	_test_no_direct_position_write()
	_test_drag_vs_click()

	s.queue_free()
	print("ALL PASS — 视角移动(拖动/边界/缩放锚点/不与点选打架)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 平移真的会改变相机位置, 且方向"跟手"
func _test_pan_moves_camera(s) -> void:
	if s._cam == null:
		_ok("相机已建", false, "_cam 为空")
		return
	_ok("相机已建", true)
	s._cam_pan = Vector3.ZERO
	s._apply_cam_zoom()
	var p0: Vector3 = s._cam_zoom_base
	s._cam_pan_by(100.0, 0.0)      # 向右拖 100px
	var p1: Vector3 = s._cam_zoom_base
	_ok("★拖动会改变相机基准位置", not p0.is_equal_approx(p1),
		"%s → %s" % [p0, p1])
	# 内容跟手: 向右拖, 视野中心应往左移(相机 x 减小)
	_ok("★拖动方向跟手(向右拖→视野往左)", p1.x < p0.x, "x: %.3f → %.3f" % [p0.x, p1.x])
	# 平移只在地面平面上, 不改高度
	_ok("平移不改相机高度(y 不变)", is_equal_approx(p0.y, p1.y), "y %.3f → %.3f" % [p0.y, p1.y])

	# 反向拖回来应接近原位
	s._cam_pan_by(-100.0, 0.0)
	_ok("拖回去能回到原位附近", s._cam_zoom_base.distance_to(p0) < 0.05,
		"回到 %s (原 %s)" % [s._cam_zoom_base, p0])
	s._cam_pan_reset()
	_ok("★有复位函数且能归零", s._cam_pan.is_equal_approx(Vector3.ZERO))


## 边界: 拖再远也不能把视野甩出战场
func _test_clamp(s) -> void:
	s._cam_pan_reset()
	for i in range(200):
		s._cam_pan_by(500.0, 500.0)    # 疯狂往一个方向拖
	var lim: float = RTScene.PAN_LIMIT
	_ok("★平移被 clamp 住(拖到天涯也不会丢失战场)",
		absf(s._cam_pan.x) <= lim + 0.001 and absf(s._cam_pan.z) <= lim + 0.001,
		"pan=%s 上限=%.1f" % [s._cam_pan, lim])
	s._cam_pan_reset()


## 缩放锚点跟着平移走 —— 否则平移后缩放会被"吸"回原点
func _test_zoom_anchor_follows_pan(s) -> void:
	s._cam_pan_reset()
	s._cam_zoom = 1.0
	s._apply_cam_zoom()
	# 平移一段, 再缩放, 视野中心应仍在平移后的位置附近(而不是弹回原点)
	s._cam_pan_by(200.0, 0.0)
	var after_pan_x: float = s._cam_zoom_base.x
	s._cam_zoom = 1.8
	s._apply_cam_zoom()
	var after_zoom_x: float = s._cam_zoom_base.x
	# 缩放会沿视轴推拉, x 会变但不应回到 0 附近(那就是被吸回原点了)
	_ok("★平移后缩放不会被吸回战场原点",
		absf(after_zoom_x) > absf(after_pan_x) * 0.4,
		"平移后 x=%.3f, 缩放后 x=%.3f" % [after_pan_x, after_zoom_x])
	s._cam_zoom = 1.0
	s._cam_pan_reset()


## A 坑: 平移不能直接写 _cam.position(会被震屏每帧抹掉)
func _test_no_direct_position_write() -> void:
	var src := _src()
	# _cam_pan_by 的函数体里不许出现直接写 position
	var body := _func_body(src, "_cam_pan_by")
	_ok("★平移函数不直接写 _cam.position(否则被震屏逐帧抹掉)",
		not body.contains("_cam.position ="),
		"函数体 %d 字符" % body.length())
	_ok("★平移通过 _apply_cam_zoom 统一落位(唯一通路)",
		body.contains("_apply_cam_zoom()"))
	# 缩放基准计算里要含平移量
	var zb := _func_body(src, "_apply_cam_zoom")
	_ok("★缩放基准把平移量算进去了", zb.contains("_cam_pan"),
		"_apply_cam_zoom 体 %d 字符" % zb.length())


## B 坑: 拖动与点选要能区分
func _test_drag_vs_click() -> void:
	var src := _src()
	_ok("有拖动位移阈值常量", src.contains("PAN_THRESHOLD"))
	_ok("阈值合理(既不会误触也不迟钝)",
		RTScene.PAN_THRESHOLD >= 4.0 and RTScene.PAN_THRESHOLD <= 24.0,
		"%.1f px" % RTScene.PAN_THRESHOLD)
	var ui := _func_body(src, "_unhandled_input")
	_ok("★拖动逻辑在 _unhandled_input 里", ui.contains("_cam_pan_by("))
	_ok("★超阈值的拖动会 return(不当点选→不误开/误关详情面板)",
		ui.contains("_pan_moved"),
		"没有拖动/点选区分 = 每次拖屏都会误触面板")
	# 顺序: 必须在捏合之后(否则抢掉双指缩放)
	var i_pinch := ui.find("_pinch_prev = d")
	var i_pan := ui.find("_cam_pan_by(")
	_ok("★平移插在捏合缩放【之后】(不抢双指手势)", i_pinch >= 0 and i_pan > i_pinch,
		"捏合@%d 平移@%d" % [i_pinch, i_pan])


func _func_body(src: String, fname: String) -> String:
	var out := ""
	var inside := false
	for line in src.split("\n"):
		if line.begins_with("func " + fname + "("):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


func _src() -> String:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
