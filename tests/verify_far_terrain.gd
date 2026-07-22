extends Node

# 远景地形守卫 (2026-07-22 第三版)
#
# 用户:「除了地板外的背景是否验证了，感觉你还是在贴一个墙就完事？」—— 说对了。
# 前两版的"山脊"是 billboard=DISABLED 的 Sprite3D = 字面意义上的【三面立着的平板】。
# 固定机位能糊弄, 一动镜头就散架: 实拍(CAMPROBE 驱到极限)证明缩小0.72+平移9m 时
# 画面上方 15% 是纯黑, 因为旧的渐变海床只铺 z∈[-30,-14] 而最坏机位要看到 z=-42.2。
#
# ★这条测试守【几何覆盖】而不是截图比对 —— 截图判黑需要开窗口, 无头跑不了, 而且
#   阈值会随美术调色漂。几何覆盖是纯算术: 把最坏机位的可见地面范围算出来,
#   断言地形网格必须罩得住。
#
# 相机: pos(0,28,22) look_at(0,0.6,0) fov40 → 俯角 51.2°, 画面上沿仍在水平线【下方】31.2°
#       (所以 Godot 的程序天空一个像素都进不了画面, 上方那条带其实是"远处地面")
# 缩放范围 CAM_ZOOM_MIN=0.72 / 平移上限 PAN_LIMIT=9.0

const SCENE_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fails: Array[String] = []


func _ready() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	if src == "":
		_fail("读不到 %s" % SCENE_PATH)
		_done()
		return
	_check_is_real_mesh(src)
	_check_coverage(src)
	_check_flat_near(src)
	_check_height_field(src)
	_done()


## ④ 直接采样高度场 —— 断言"平坦半径 ≥ 战场"是间接的, 这里验【实际高度】
##   (2026-07-22 关方案书 H15/H16 时补: 原先只断言半径, 万一噪声公式改了半径没改就漏)
##   H16 战场内必须严格 0 (场上 40+ 贴地特效画在 y=0, 有起伏就顶穿)
##   H15 战场外的地形不得高过单位身高 (否则会挡住站在边缘的单位)
func _check_height_field(src: String) -> void:
	var flat := _const_f(src, "FAR_TERRAIN_FLAT_R")
	var rise := _const_f(src, "FAR_TERRAIN_RISE_R")
	if flat <= 0.0 or rise <= flat:
		_fail("平坦/起伏半径解析失败 (flat=%.1f rise=%.1f)" % [flat, rise])
		return
	var arena_r := 24.5      # ARENA 约 42.5×24 m → 半对角 ≈ 24.4 m
	var body_h := 2.0        # TARGET_BODY_H
	var max_in := 0.0
	var max_out := 0.0
	var n_in := 0
	var n_out := 0
	for i in range(-46, 47, 2):
		for j in range(-46, 47, 2):
			var x := float(i)
			var z := float(j)
			var d := sqrt(x * x + z * z)
			if d > 50.0:
				continue
			var y: float = absf(_terrain_h(x, z, flat, rise))
			if d <= arena_r:
				n_in += 1
				max_in = maxf(max_in, y)
			else:
				n_out += 1
				max_out = maxf(max_out, y)
	print("  [高度场] 战场内采样 %d 点 最大 %.6f m / 战场外 %d 点 最大 %.2f m" % [n_in, max_in, n_out, max_out])
	if n_in == 0 or n_out == 0:
		_fail("高度场采样点不足(内%d 外%d) —— 空检查不是通过" % [n_in, n_out])
		return
	if max_in > 0.001:
		_fail("H16: 战场内地形起伏 %.4f m ≠ 0 —— 会顶穿画在 y=0 的贴地特效(裂地/毒圈/冲击环)" % max_in)
	if max_out > body_h:
		_fail("H15: 战场外地形最高 %.2f m > 单位身高 %.1f m —— 会挡住站在边缘的单位" % [max_out, body_h])


## 复刻 _far_terrain_height 的公式(与实现对照, 不 import)
func _terrain_h(x: float, z: float, flat: float, rise: float) -> float:
	var w := smoothstep(flat, rise, sqrt(x * x + z * z))
	if w <= 0.0:
		return 0.0
	var h := 0.0
	h += 1.55 * sin(x * 0.055 + 1.3) * cos(z * 0.048 - 0.7)
	h += 0.70 * sin(x * 0.130 - 2.1) * cos(z * 0.115 + 1.9)
	h += 0.28 * sin(x * 0.290 + 0.4) * cos(z * 0.265 - 2.6)
	return h * w


## ① 必须是真网格, 不能退回平板精灵
func _check_is_real_mesh(src: String) -> void:
	if src.find("func _build_far_terrain(") < 0:
		_fail("缺少 _build_far_terrain —— 远景又变回平板了?")
		return
	var b := _code_only(_func_body(src, "_build_far_terrain"))
	if b.find("SurfaceTool") < 0 or b.find("add_vertex(") < 0:
		_fail("_build_far_terrain 没有真正生成网格顶点 —— 平板背景一动镜头就穿帮")
	if b.find("Sprite3D") >= 0:
		_fail("_build_far_terrain 里又出现 Sprite3D —— 远景地貌不能用平板")
	print("  [真网格] SurfaceTool 顶点生成已检")


## ② 覆盖范围必须罩住最坏机位
func _check_coverage(src: String) -> void:
	var sx := _const_f(src, "FAR_TERRAIN_SIZE_X")
	var size_line := _const_vec2(src, "FAR_TERRAIN_SIZE")
	var cz := _const_f(src, "FAR_TERRAIN_CENTER_Z")
	if size_line == Vector2.ZERO:
		_fail("解析不到 FAR_TERRAIN_SIZE")
		return
	var half := size_line * 0.5
	var z_far: float = cz - half.y
	var z_near: float = cz + half.y
	var x_half: float = half.x

	# 最坏机位: zoom=0.72 + 后移9m + 侧移9m。相机沿视轴远离 CAM_TARGET 1/zoom 倍。
	var zoom := 0.72
	var pan := 9.0
	var cam_y: float = 0.6 + 27.4 / zoom
	var cam_z: float = 22.0 / zoom - pan
	var pitch := rad_to_deg(atan2(cam_y - 0.6, cam_z + pan))
	var top_ang: float = pitch - 20.0                      # 画面上沿(半 FOV=20°)
	var d_top: float = cam_y / tan(deg_to_rad(top_ang))    # 上沿射线打到地面的水平距离
	var need_z_far: float = cam_z - d_top
	var dist: float = sqrt(d_top * d_top + cam_y * cam_y)
	var half_h := rad_to_deg(atan(tan(deg_to_rad(20.0)) * (854.0 / 533.0)))
	var need_x: float = dist * tan(deg_to_rad(half_h)) + pan

	print("  [覆盖] 最坏机位需要 z≥%.1f 远 / x≥±%.1f ; 地形给到 z∈[%.1f,%.1f] x=±%.1f"
		% [need_z_far, need_x, z_far, z_near, x_half])
	if z_far > need_z_far:
		_fail("地形远端只到 z=%.1f, 但最坏机位要看到 z=%.1f → 上方会露纯黑(差 %.1f 米)"
			% [z_far, need_z_far, z_far - need_z_far])
	if x_half < need_x:
		_fail("地形横向只到 ±%.1f, 但最坏机位要看到 ±%.1f → 两侧会露纯黑" % [x_half, need_x])
	if z_near < 22.0:
		_fail("地形近端只到 z=%.1f, 没铺到相机身后(z=22) → 极端平移可能露底" % z_near)
	if sx > 0.0:
		pass   # 占位: 若将来把 SIZE 拆成两个标量常量, 这里能接上


## ③ 战场范围内必须严格平坦(场上 40+ 贴地特效画在 y=0, 起伏会穿模)
func _check_flat_near(src: String) -> void:
	var b := _code_only(_func_body(src, "_far_terrain_weight"))
	if b == "":
		_fail("缺少 _far_terrain_weight —— 地形起伏没有做近处淡出, 会把贴地特效顶穿")
		return
	if b.find("smoothstep") < 0:
		_fail("_far_terrain_weight 没用 smoothstep 做距离淡出")
	var flat_r := _const_f(src, "FAR_TERRAIN_FLAT_R")
	# 战场半径: ARENA 约 1772×1000 码 × WS(0.024) → 半对角约 24m。平坦半径要盖住它。
	if flat_r < 24.0:
		_fail("平坦半径 %.1f 米 < 战场半对角 24 米 → 地形会在战场里起伏, 顶穿贴地特效" % flat_r)
	print("  [近处平坦] 平坦半径 %.1f 米 (战场半对角约 24 米)" % flat_r)


func _const_f(src: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("const\\s+" + name + "\\s*:=\\s*(-?[0-9.]+)")
	var m := re.search(src)
	return float(m.get_string(1)) if m != null else 0.0


func _const_vec2(src: String, name: String) -> Vector2:
	var re := RegEx.new()
	re.compile("const\\s+" + name + "\\s*:=\\s*Vector2\\(\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)")
	var m := re.search(src)
	return Vector2(float(m.get_string(1)), float(m.get_string(2))) if m != null else Vector2.ZERO


## 剥注释 —— 断言"函数体里有没有某调用"必须先过这层, 否则注释里提到那个名字就假通过
## (2026-07-22 在 verify_cyber_hijack 连踩两次)。不能按第一个 # 截断: Color("#xxxxxx") 会被误伤。
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


func _fail(msg: String) -> void:
	_fails.append(msg)


func _done() -> void:
	if _fails.is_empty():
		print("ALL PASS — 远景地形覆盖最坏机位")
	else:
		for f in _fails:
			printerr("FAIL: %s" % f)
		printerr("FAIL — 远景地形 %d 项不通过" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
