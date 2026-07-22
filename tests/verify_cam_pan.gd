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
	# ★挂 root 而不是挂 self: 本节点是 PROCESS_MODE_ALWAYS, 场景的 INHERIT 会继承成 ALWAYS,
	#   暂停测试就永远绿(2026-07-22 我第一版探针正是这么骗了自己, 得出"暂停能拖"的错结论)。
	get_tree().root.add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_pan_moves_camera(s)
	_test_clamp(s)
	_test_zoom_anchor_follows_pan(s)
	_test_no_direct_position_write()
	_test_drag_vs_click()
	await _test_pan_while_paused(s)
	_test_pause_clears_drag_state(s)
	await _test_touch_not_doubled(s)
	await _test_no_pan_without_button(s)
	await _test_pinch_release_resets_anchor(s)

	get_tree().paused = false
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
	# ★这里查的是 _cam_handle_input 而不是 _unhandled_input —— 相机输入 2026-07-22 抽了出去,
	#   为的是暂停期间由 ALWAYS 中继转发(见下面 _test_pan_while_paused)。原来两条断言写死
	#   _unhandled_input, 代码一搬家就红, 但功能完全正常 —— 这正是静态查串的通病, 所以
	#   拖动/点选之分改成下面的【事件序列行为测试】, 这里只留顺序这一条静态的。
	var ui := _func_body(src, "_cam_handle_input")
	_ok("★拖动逻辑在 _cam_handle_input 里", ui.contains("_cam_pan_by("))
	# 顺序: 必须在捏合之后(否则抢掉双指缩放)
	var i_pinch := ui.find("_pinch_prev = d")
	var i_pan := ui.find("_cam_pan_by(")
	_ok("★平移插在捏合缩放【之后】(不抢双指手势)", i_pinch >= 0 and i_pan > i_pinch,
		"捏合@%d 平移@%d" % [i_pinch, i_pan])


# ══════════════════════════════════════════════════════════════════════════
#  事件序列测试 (2026-07-22, 测试人员报「放大和拖动冲突」「点暂停后鼠标无法拖动」)
#  ★这四条都【必须真发事件】: 它们全是时序问题, 查源码字符串一条也抓不到。
#  ★场景必须挂在 get_tree().root 下 —— 挂在本测试节点(PROCESS_MODE_ALWAYS)下会让
#    INHERIT 继承成 ALWAYS, 暂停测试就永远是绿的(2026-07-22 我第一版探针就这么骗了自己)。
# ══════════════════════════════════════════════════════════════════════════

## 一次"按下 + 小幅拖动"的鼠标序列。
## ★位移必须【小到不顶 PAN_LIMIT】—— 2026-07-22 第一版用 4×40px, push_input 会把坐标
##   按内容缩放放大 20×, 于是 _cam_pan_by 一帧就吃 16.8m, 被 clamp 死在 9.0 上限。
##   结果"暂停 9.0 vs 平时 9.0"看着漂亮, 其实是两个饱和值在对比 —— 拆掉 _touch_seen
##   去重也照样绿。下面每条比较速度的断言都要先过 _assert_not_saturated。
func _mouse_drag(vp: Viewport) -> void:
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = Vector2(400, 300)
	vp.push_input(p)
	for i in 2:
		var m := InputEventMouseMotion.new()
		m.position = Vector2(400 + 3 * (i + 1), 300)
		m.relative = Vector2(3, 0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(m)


## 防"饱和假绿灯": 顶到 clamp 上限的量之间比较毫无意义
func _assert_not_saturated(what: String, v: float) -> void:
	_ok("%s 没顶到平移上限(否则速度比较是假的)" % what,
		v > 0.001 and v < RTScene.PAN_LIMIT - 0.5,
		"%.4f (上限 %.1f)" % [v, RTScene.PAN_LIMIT])


## ★暂停中必须还能拖动看战场
func _test_pan_while_paused(s) -> void:
	var vp := get_viewport()
	s._cam_pan_reset()
	_mouse_drag(vp)
	await get_tree().process_frame
	var run: float = s._cam_pan.length()
	_assert_not_saturated("基准拖动量", run)
	s._toggle_pause()
	await get_tree().process_frame
	_ok("暂停确实生效(主场景 can_process=false)", not s.can_process(),
		"若这条是 true, 下面那条就是假绿灯")
	s._cam_pan_reset()
	_mouse_drag(vp)
	await get_tree().process_frame
	var pau: float = s._cam_pan.length()
	_ok("★暂停中仍能拖动镜头(测试人员:「点暂停键鼠标似乎也无法拖动」)",
		pau > 0.001, "暂停中拖动量 %.4f (未暂停 %.4f)" % [pau, run])
	_ok("★暂停中的平移速度与平时一致(中继不能与主路双份处理→2倍速)",
		absf(pau - run) < 0.001, "暂停 %.4f vs 平时 %.4f" % [pau, run])
	get_tree().paused = false
	await get_tree().process_frame
	s._cam_pan_reset()
	_mouse_drag(vp)
	await get_tree().process_frame
	_ok("★恢复后速度也没被中继翻倍",
		absf(s._cam_pan.length() - run) < 0.001,
		"恢复后 %.4f vs 平时 %.4f" % [s._cam_pan.length(), run])


## ★暂停要清掉拖动脏态: 暂停若发生在拖动中途, release 永远收不到
func _test_pause_clears_drag_state(s) -> void:
	s._pan_active = true
	s._pan_moved = true
	s._touch_pts[0] = Vector2(10, 10)
	s._pinch_prev = 123.0
	s._toggle_pause()
	_ok("★暂停清掉 _pan_active(否则恢复后不按键镜头也在跑)", not s._pan_active)
	_ok("★暂停清掉 _pan_moved", not s._pan_moved)
	_ok("★暂停清掉多点触摸表", s._touch_pts.is_empty(), "剩 %d 点" % s._touch_pts.size())
	_ok("★暂停重置捏合基线", s._pinch_prev < 0.0, "%.1f" % s._pinch_prev)
	s._toggle_pause()
	get_tree().paused = false


## ★真触屏之后要忽略 emulate_mouse_from_touch 的模拟鼠标, 否则手机平移是 2 倍速
func _test_touch_not_doubled(s) -> void:
	var vp := get_viewport()
	s._cam_pan_reset()
	s._touch_pts.clear()
	s._touch_seen = false
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = Vector2(400, 300)
	vp.push_input(t)
	# ★必须把系统【同时】发出的模拟鼠标按下也推进去 —— emulate_mouse_from_touch 是
	#   触屏事件与模拟鼠标事件【成对】产生的。少了这一下, _pan_active 就是 false,
	#   下面那条 MouseMotion 无论有没有 _touch_seen 都不会平移 → 断言恒真。
	#   (2026-07-22 反向验证抓到: 拆掉 _touch_seen 这条测试照样绿。)
	var mp := InputEventMouseButton.new()
	mp.button_index = MOUSE_BUTTON_LEFT
	mp.pressed = true
	mp.position = Vector2(400, 300)
	vp.push_input(mp)
	_ok("模拟鼠标按下已进入平移态(否则下面是空检查)", s._pan_active)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = Vector2(403, 300)
	d.relative = Vector2(3, 0)
	vp.push_input(d)
	await get_tree().process_frame
	var after_touch: float = s._cam_pan.length()
	_ok("触屏单指拖动能平移", after_touch > 0.001, "%.4f" % after_touch)
	_assert_not_saturated("触屏拖动量", after_touch)
	_ok("★收到真触屏后置位 _touch_seen", s._touch_seen)
	# 紧跟着来的是同一次手指移动被系统模拟出来的鼠标事件
	var m := InputEventMouseMotion.new()
	m.position = Vector2(403, 300)
	m.relative = Vector2(3, 0)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(m)
	await get_tree().process_frame
	_ok("★模拟鼠标不再重复平移(否则手机上是设计值的 2 倍速)",
		absf(s._cam_pan.length() - after_touch) < 0.001,
		"触屏后 %.4f → 模拟鼠标后 %.4f" % [after_touch, s._cam_pan.length()])


## ★没按住左键就移动鼠标不能平移 —— release 被 GUI 控件吃掉时 _pan_active 会永久卡 true
func _test_no_pan_without_button(s) -> void:
	var vp := get_viewport()
	s._cam_pan_reset()
	s._touch_pts.clear()
	s._touch_seen = false
	s._pan_active = true          # 模拟"release 落在详情面板上被吃掉"后的残留状态
	s._pan_moved = false
	s._pan_from = Vector2(400, 300)
	for i in 4:
		var m := InputEventMouseMotion.new()
		m.position = Vector2(400 + 40 * (i + 1), 300)
		m.relative = Vector2(40, 0)
		m.button_mask = 0          # ★没按任何键
		vp.push_input(m)
	await get_tree().process_frame
	_ok("★_pan_active 卡住时, 空手移鼠标也不会平移(button_mask 兜底)",
		s._cam_pan.length() < 0.001, "平移了 %.4f" % s._cam_pan.length())


## ★捏合抬起一根手指后要重置平移起点, 否则剩下那根手指的移动被立刻当成拖视角
func _test_pinch_release_resets_anchor(s) -> void:
	var vp := get_viewport()
	s._cam_pan_reset()
	s._touch_pts.clear()
	s._touch_seen = false
	# ★坐标要跟【引擎记下的】比, 不能跟我写的屏幕像素比 —— push_input 会按内容缩放换算,
	#   2026-07-22 实测 300px 进去存成 6000, 拿原值当期望会得到一条假 FAIL。
	# ★而且捏合期间手指0必须【真的移动过】, 否则"最初落指点"恰好等于"当前位置",
	#   这条断言不修也绿 —— 是个空检查。
	for idx in 2:
		var t := InputEventScreenTouch.new()
		t.index = idx
		t.pressed = true
		t.position = Vector2(300 + 200 * idx, 300)
		vp.push_input(t)
	await get_tree().process_frame
	var first_anchor: Vector2 = s._pan_from       # 手指0 落指那一刻记下的起点
	for idx in 2:
		var d2 := InputEventScreenDrag.new()
		d2.index = idx
		d2.position = Vector2(200 + 400 * idx, 300)   # 手指0: 300→200, 手指1: 500→600 (张开)
		d2.relative = Vector2(-100 + 200 * idx, 0)
		vp.push_input(d2)
	await get_tree().process_frame
	var cur0: Vector2 = s._touch_pts.get(0, Vector2.ZERO)
	_ok("捏合中手指0确实移动了(否则下面那条是空检查)",
		cur0.distance_to(first_anchor) > 1.0,
		"落指@%s → 现在@%s" % [first_anchor, cur0])
	var up := InputEventScreenTouch.new()
	up.index = 1
	up.pressed = false
	up.position = Vector2(600, 300)
	vp.push_input(up)
	await get_tree().process_frame
	_ok("★抬指后平移起点重置到剩下那根手指的【当前位置】(不是最初落指点)",
		s._pan_from.distance_to(cur0) < 1.0,
		"_pan_from=%s 手指0当前=%s 最初落指=%s" % [s._pan_from, cur0, first_anchor])
	_ok("★抬指后 _pan_moved 归零(要求重新落指才允许平移)", not s._pan_moved)


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
