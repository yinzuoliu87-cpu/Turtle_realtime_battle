extends Node
## verify_battle_camera.gd — 对局镜头俯角钉在 40°(跟咩咩启示录一样), 跟俯角走的系数一律从 BattleCam 推。
##
## ★由来: 用户 2026-11-15「不是更陡吧，就是更平着看」; 11-16 看完五档对比视频问「咩咩启示录用的是哪个角度」,
##   又说「我只想要跟它一样的这个角度就好了」。量法(平放在地上的圆, 画面上 高÷宽 = sin(俯角)):
##   咩咩启示录 Steam 官方地牢战斗截图的贴地白圈 ⇒ ≈40°(±1°)。只改角度, 视距 / fov / 注视点不动。
##
## 判据:
##   ① BattleCam 自洽: SIN_P / COS_P = sin / cos(PITCH_DEG); |POS − TARGET| = DIST; FORWARD 是单位向量且指向注视点
##   ② ★俯角 = 40°(用户拍板 —— 写字面值, 不引用被测常量)
##   ③ 真建对局场景: 镜头 fov / 机位 = BattleCam; 由**真相机变换**现算的俯角 = 40° ±0.05°
##   ④ ★投影比: 屏幕正中那条视线的落地点放一个半径 3 米的圆, 用真相机 unproject 一圈 360 点取外接框,
##      高÷宽 ≈ sin(40°); EquipSystem.SWORD_SCREEN_SQUASH 与实测投影比差 < 0.01
##      (那条常量的注释早就写着「焊了一条门禁量真实投影比」, 实际没有 —— 这条补上)
##   ⑤ 静态扫描 scripts/: 不许再出现 51° 机位的字面值(机位 / 视轴 / 视轴反方向), 一律走 BattleCam
##
## 反向验证(2026-11-16 做过): PITCH_DEG 改 51 ⇒ ① ② 红(SIN_P 没跟着改) ; SWORD_SCREEN_SQUASH 改回 0.78 ⇒ ④ 红;
##   battle_world_builder 改回 Vector3(0.0, 28.0, 22.0) ⇒ ③ ⑤ 红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_battle_camera.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "   ", d)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 对局镜头: 俯角 40°(跟咩咩启示录一样) ===")
	var p := deg_to_rad(BattleCam.PITCH_DEG)

	## ① 自洽
	_ok("① SIN_P = sin(PITCH_DEG)", absf(BattleCam.SIN_P - sin(p)) < 1e-6, "%.7f vs %.7f" % [BattleCam.SIN_P, sin(p)])
	_ok("① COS_P = cos(PITCH_DEG)", absf(BattleCam.COS_P - cos(p)) < 1e-6, "%.7f vs %.7f" % [BattleCam.COS_P, cos(p)])
	_ok("① |POS − TARGET| = DIST", absf((BattleCam.POS - BattleCam.TARGET).length() - BattleCam.DIST) < 1e-3,
		"%.4f vs %.4f" % [(BattleCam.POS - BattleCam.TARGET).length(), BattleCam.DIST])
	_ok("① FORWARD 单位向量且从机位指向注视点",
		absf(BattleCam.FORWARD.length() - 1.0) < 1e-5 and BattleCam.FORWARD.dot((BattleCam.TARGET - BattleCam.POS).normalized()) > 0.99999,
		str(BattleCam.FORWARD))

	## ② 用户拍板的值(字面值)
	_ok("② ★俯角 = 40°(用户 11-16「我只想要跟它一样的这个角度就好了」)", is_equal_approx(BattleCam.PITCH_DEG, 40.0),
		"%.2f°" % BattleCam.PITCH_DEG)
	_ok("② 视距 / fov / 注视点没跟着动(只改角度): 35.13915 / 40 / (0,0.6,0)",
		absf(BattleCam.DIST - 35.13915) < 1e-4 and is_equal_approx(BattleCam.FOV, 40.0) and BattleCam.TARGET.is_equal_approx(Vector3(0.0, 0.6, 0.0)))

	## ③ 真建场景
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam: Camera3D = s._cam
	_ok("③ ★分母: 对局场景建出了镜头", cam != null and is_instance_valid(cam))
	if cam == null or not is_instance_valid(cam):
		_finish()
		return
	_ok("③ 镜头 fov = BattleCam.FOV", is_equal_approx(cam.fov, BattleCam.FOV), "%.2f" % cam.fov)
	_ok("③ 默认机位 = BattleCam.POS", Vector3(s._cam_base).is_equal_approx(BattleCam.POS), "%s vs %s" % [str(s._cam_base), str(BattleCam.POS)])
	var fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var got_pitch := rad_to_deg(asin(-fwd.y))
	_ok("③ ★真相机现算俯角 = 40° ±0.05°", absf(got_pitch - 40.0) < 0.05, "%.3f°" % got_pitch)

	## ④ 投影比
	var vp := cam.get_viewport().get_visible_rect().size
	_ok("④ ★分母: 视口有尺寸(unproject 才有意义)", vp.x > 0.0 and vp.y > 0.0, str(vp))
	var o: Vector3 = cam.global_position
	var ground_c := o + fwd * (o.y / -fwd.y)
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	var n := 0
	for i in 360:
		var a := TAU * float(i) / 360.0
		var sp := cam.unproject_position(ground_c + Vector3(cos(a) * 3.0, 0.0, sin(a) * 3.0))
		mn = mn.min(sp)
		mx = mx.max(sp)
		n += 1
	var w := mx.x - mn.x
	var h := mx.y - mn.y
	_ok("④ ★分母: 圆周 %d 个点都投上了屏幕, 外接框宽 > 50 px" % n, n == 360 and w > 50.0, "宽 %.1f 高 %.1f" % [w, h])
	var ratio := h / maxf(w, 0.001)
	_ok("④ 地面圆 高÷宽 = sin(40°) ±0.01", absf(ratio - sin(deg_to_rad(40.0))) < 0.01, "实测 %.4f, sin40° = %.4f" % [ratio, sin(deg_to_rad(40.0))])
	_ok("④ ★EquipSystem.SWORD_SCREEN_SQUASH 跟实测投影比差 < 0.01", absf(ES.SWORD_SCREEN_SQUASH - ratio) < 0.01,
		"常量 %.4f / 实测 %.4f" % [ES.SWORD_SCREEN_SQUASH, ratio])
	s.queue_free()
	await get_tree().process_frame

	## ⑤ 静态扫描
	var bad: Array = []
	var files := _gd_files("res://scripts")
	_ok("⑤ ★分母: 扫到 scripts/ 下 %d 个 .gd" % files.size(), files.size() > 100)
	var pats := ["Vector3(0.0, 28.0, 22.0)", "Vector3(0.0, -27.4, -22.0)", "Vector3(0.0, 0.780, 0.626)"]
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for pat in pats:
			if src.contains(pat):
				bad.append("%s: %s" % [f, pat])
	_ok("⑤ scripts/ 里没有 51° 机位字面值(一律走 BattleCam)", bad.is_empty(), str(bad))
	_finish()


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var nm := d.get_next()
	while nm != "":
		if d.current_is_dir():
			if not nm.begins_with("."):
				out.append_array(_gd_files(dir + "/" + nm))
		elif nm.ends_with(".gd"):
			out.append(dir + "/" + nm)
		nm = d.get_next()
	return out


func _finish() -> void:
	if _fail == 0:
		print("ALL PASS")
	else:
		print("FAILED %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
