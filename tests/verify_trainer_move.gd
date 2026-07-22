extends Node

## verify_trainer_move.gd — 训龟大师操控: PC 键盘 / 移动端摇杆 (用户 2026-07-22)
##
## 用户逐字:「这个不行，还是分pc和移动2版吧，移动要遥感，循规大师的移速为130，pc你看看怎么做」
##   → 移动端 = 虚拟摇杆(推翻了我原先"不做摇杆"的建议)
##   → PC = 我定的键盘 WASD/方向键(鼠标三种手势已排满: 拖=平移/点=选中/滚轮=缩放)
##   → 移速 130
##
## ★无头跑不了真键盘/真手指, 所以移动逻辑抽成 _trainer_move_by(u, dir, delta) 直接喂向量;
##   摇杆本身则真建控件、真发 InputEvent 去验。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const VirtualJoystick := preload("res://scripts/scenes/virtual_joystick.gd")

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
	for i in 8:
		await get_tree().process_frame

	_test_speed(s)
	_test_clamp(s)
	_test_only_mine(s)
	_test_input_sources(s)
	await _test_joystick_widget()

	s.queue_free()
	print("ALL PASS — 训龟大师操控(PC键盘/移动摇杆/移速130)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 移速正好 130, 且摇杆半推 = 半速
func _test_speed(s) -> void:
	var u = s._my_trainer()
	_ok("找得到我方训龟大师", u != null)
	if u == null:
		return
	_ok("★移速字段是 130", is_equal_approx(float(u["move_spd"]), 130.0), "move_spd=%.1f" % float(u["move_spd"]))
	# 放到场地中间再测, 免得被边界 clamp 干扰
	u["pos"] = Vector2(900.0, 500.0)
	var p0: Vector2 = u["pos"]
	s._trainer_move_by(u, Vector2.RIGHT, 1.0)
	var moved: float = u["pos"].distance_to(p0)
	print("  [实测] 满推 1 秒移动 %.1f 码" % moved)
	_ok("★满推 1 秒走 130 码", is_equal_approx(moved, 130.0), "%.2f" % moved)
	# 摇杆可以半推 —— 长度 0.5 的向量应当只走一半
	u["pos"] = Vector2(900.0, 500.0)
	s._trainer_move_by(u, Vector2.RIGHT * 0.5, 1.0)
	var half: float = u["pos"].distance_to(Vector2(900.0, 500.0))
	print("  [实测] 半推 1 秒移动 %.1f 码" % half)
	_ok("★摇杆半推 = 半速(不是一律满速)", is_equal_approx(half, 65.0), "%.2f" % half)
	# 零向量不该动(死区/没输入)
	u["pos"] = Vector2(900.0, 500.0)
	s._trainer_move_by(u, Vector2.ZERO, 1.0)
	_ok("没有输入时不动", u["pos"].is_equal_approx(Vector2(900.0, 500.0)))
	# 朝向跟着走
	s._trainer_move_by(u, Vector2.LEFT, 0.1)
	_ok("向左走时朝左", not bool(u.get("face_right", true)))
	s._trainer_move_by(u, Vector2.RIGHT, 0.1)
	_ok("向右走时朝右", bool(u.get("face_right", false)))


## ② 一直推也不能飞出战场
func _test_clamp(s) -> void:
	var u = s._my_trainer()
	if u == null:
		return
	for i in 200:
		s._trainer_move_by(u, Vector2(1.0, 1.0).normalized(), 0.5)
	var a: Rect2 = RTScene.ARENA
	print("  [实测] 狂推 200 次后位置 %s ; 战场 %s" % [u["pos"], a])
	_ok("★推到天涯也留在战场内(否则会走出地图)",
		u["pos"].x <= a.end.x + 0.01 and u["pos"].y <= a.end.y + 0.01
		and u["pos"].x >= a.position.x - 0.01 and u["pos"].y >= a.position.y - 0.01,
		"%s" % u["pos"])


## ③ 只操控我方那个, 碰不到对面的人机
func _test_only_mine(s) -> void:
	var mine = s._my_trainer()
	var foe = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "right":
			foe = u
	_ok("场上有对面的训龟大师", foe != null)
	if mine == null or foe == null:
		return
	_ok("★_my_trainer 拿到的是我方(left)", str(mine.get("side", "")) == "left", str(mine.get("side", "")))
	# ★把敌方那个挪到数组【最前面】再问一次 —— 否则这条是【靠 spawn 顺序巧合】通过的:
	#   左边那个恰好先 spawn, 于是"返回第一个训龟大师"也能蒙对。
	#   2026-07-22 反向验证抓到: 去掉 side=="left" 判断照样全绿。
	var order: Array = s._units.duplicate()
	s._units.erase(foe)
	s._units.insert(0, foe)
	var mine2 = s._my_trainer()
	print("  [实测] 把敌方训龟大师挪到数组首位后, _my_trainer 返回的是 %s 方"
		% (str(mine2.get("side", "")) if mine2 != null else "null"))
	_ok("★★换成敌方在前也仍然拿到我方(证明是真按阵营判, 不是取第一个)",
		mine2 != null and str(mine2.get("side", "")) == "left",
		"拿到了 %s" % (str(mine2.get("side", "")) if mine2 != null else "null"))
	s._units = order
	var foe_p0: Vector2 = foe["pos"]
	for i in 10:
		s._trainer_input_tick(0.1)
	print("  [实测] 连跑 10 次输入 tick 后, 敌方训龟大师位移 %.4f" % foe["pos"].distance_to(foe_p0))
	_ok("★玩家输入动不了对面那个(它是人机)", foe["pos"].is_equal_approx(foe_p0))


## ④ 两条输入源: 有摇杆读摇杆, 没摇杆读键盘
func _test_input_sources(s) -> void:
	_ok("PC(无摇杆)且没按键时输入为零", s._trainer_input_vec().is_equal_approx(Vector2.ZERO),
		"%s" % s._trainer_input_vec())
	# 挂一个摇杆上去 → 输入源必须切到摇杆
	var joy := VirtualJoystick.new()
	s.add_child(joy)
	s._joystick = joy
	joy.value = Vector2(0.5, -0.25)
	var got: Vector2 = s._trainer_input_vec()
	print("  [实测] 摇杆 value=%s → _trainer_input_vec()=%s" % [joy.value, got])
	_ok("★有摇杆时读摇杆(移动端这条路)", got.is_equal_approx(Vector2(0.5, -0.25)))
	s._joystick = null
	joy.queue_free()
	# 结构: PC 那条分支必须真读键盘, 不能是空壳
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var body := _code_only(_func_body(src, "_trainer_input_vec"))
	var n_keys := 0
	for k in ["KEY_A", "KEY_D", "KEY_W", "KEY_S", "KEY_LEFT", "KEY_RIGHT", "KEY_UP", "KEY_DOWN"]:
		if body.contains(k):
			n_keys += 1
	print("  [分母] PC 分支里认的按键 %d 个(WASD + 四方向)" % n_keys)
	_ok("★PC 走键盘 WASD + 方向键", n_keys == 8, "只认了 %d 个" % n_keys)


## ⑤ 摇杆控件本身
func _test_joystick_widget() -> void:
	var joy := VirtualJoystick.new()
	add_child(joy)
	await get_tree().process_frame
	_ok("★摇杆 mouse_filter=STOP(吃掉本区域事件, 不抢镜头平移)",
		joy.mouse_filter == Control.MOUSE_FILTER_STOP,
		"mouse_filter=%d" % joy.mouse_filter)
	_ok("摇杆有尺寸(0 尺寸=摸不到)", joy.size.x > 10.0 and joy.size.y > 10.0, "%s" % joy.size)

	# 真发触屏事件: 按在中心 → 死区内 → 不该输出
	var c: Vector2 = joy.size * 0.5
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = c
	joy._gui_input(t)
	_ok("按在正中心不输出", joy.value.is_equal_approx(Vector2.ZERO), "%s" % joy.value)
	# ★真正测死区: 要按在【偏离中心但仍在死区内】的位置。
	#   只按正中心测的是"零距离"不是死区 —— 2026-07-22 反向验证抓到: 把死区判断换成
	#   `r > 0.0 ? ... : ZERO` 照样全绿, 因为正中心 r 恰好是 0。
	var inside: float = VirtualJoystick.RADIUS * VirtualJoystick.DEADZONE * 0.5   # 死区内的一半处
	var d0 := InputEventScreenDrag.new()
	d0.index = 0
	d0.position = c + Vector2(inside, 0.0)
	joy._gui_input(d0)
	print("  [实测] 偏离中心 %.1f px(死区 %.1f px 内) → value=%s" % [inside, VirtualJoystick.RADIUS * VirtualJoystick.DEADZONE, joy.value])
	_ok("★★死区内的微小位移不输出(防手指微抖导致人物慢慢漂)",
		joy.value.is_equal_approx(Vector2.ZERO), "%s" % joy.value)
	# 死区外一点点就该有输出, 否则死区太大等于摇杆不灵
	var d1 := InputEventScreenDrag.new()
	d1.index = 0
	d1.position = c + Vector2(VirtualJoystick.RADIUS * (VirtualJoystick.DEADZONE + 0.15), 0.0)
	joy._gui_input(d1)
	_ok("★刚出死区就有输出(死区不能大到让摇杆变迟钝)", joy.value.length() > 0.0, "%s" % joy.value)
	# 拖到右边缘 → 满推向右
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = c + Vector2(VirtualJoystick.RADIUS, 0.0)
	joy._gui_input(d)
	print("  [实测] 拖到右边缘 → value=%s (长度 %.3f)" % [joy.value, joy.value.length()])
	_ok("★拖到边缘 = 满推", is_equal_approx(joy.value.length(), 1.0), "长度 %.3f" % joy.value.length())
	_ok("★方向正确(向右)", joy.value.x > 0.9)
	# 拉过头也不该超过 1(否则会超速)
	d.position = c + Vector2(VirtualJoystick.RADIUS * 5.0, 0.0)
	joy._gui_input(d)
	_ok("★拉出底盘也不超过满推(否则会超速)", joy.value.length() <= 1.0 + 1e-5,
		"长度 %.3f" % joy.value.length())
	# 第二根手指落在摇杆上要被忽略(防两指各拉一次)
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.pressed = true
	t2.position = c + Vector2(0.0, VirtualJoystick.RADIUS)
	var before: Vector2 = joy.value
	joy._gui_input(t2)
	_ok("★第二根手指被忽略(防两指各拉一次=速度翻倍)", joy.value.is_equal_approx(before),
		"被第二根手指改成了 %s" % joy.value)
	# 抬手归零
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = d.position
	joy._gui_input(up)
	_ok("★抬手后归零(否则会一直往那个方向漂)", joy.value.is_equal_approx(Vector2.ZERO), "%s" % joy.value)
	joy.queue_free()


func _func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	return src.substr(start, j - start)


func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out
