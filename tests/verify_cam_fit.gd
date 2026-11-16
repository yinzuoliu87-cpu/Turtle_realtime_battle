extends Node
## verify_cam_fit.gd — 画幅取景: 不管什么画幅, 两个蛋连罩子都落在两侧头像栏之间; 手机宽屏画面不变。
##
## ★由来(2026-11-16): 镜头只保证竖直方向看全(KEEP_HEIGHT)。实拍: iPad 4:3 两个蛋整个出画
##   (51° 与 40° 都是, 蛋心 x = −9 / 1289, 画面宽 1280), 16:9 蛋罩压在头像栏底下。
##   修法见 scripts/scenes/battle/cam_fit.gd: 按真实画幅 + 栏内沿 + 蛋的位置算镜头沿视轴退多远, 只退不进。
##
## 判据:
##   ① 纯函数 CamFit.scale_for: 手机 1560×720 ⇒ k = 1(画面不变); 16:9 / 4:3 ⇒ k > 1;
##      按算出的 k 用针孔模型投回去, 罩子外沿恰好落在「栏内沿 + 留白」以内
##   ② 真场景(调试场, 走产品入口 CamFit.apply): 四种画幅下用【真相机】unproject 两个蛋罩的外沿,
##      都在两栏内沿以内; 手机画幅镜头基准 == BattleCam.POS(一个像素不变); 机位仍在 40° 视轴上
##   ③ 接线: 头像栏建好就取景(battle_hud._build_team_panels 调 CamFit); 双路摆蛋的内缩码数 == CamFit.EGG_INSET
##
## 反向验证(2026-11-16 做过): scale_for 恒返 1 ⇒ ① ② 红; 去掉 battle_hud 那行调用 ⇒ ③ 红;
##   EGG_INSET 改 40 ⇒ ③ 红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_cam_fit.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ASPECTS := [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2400, 1000)]

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "   ", d)


## 针孔投影(与 CamFit 推导同一个模型, 但这里直接按机位算, 不走 CamFit 的公式)
func _proj_x(p: Vector3, k: float, vp: Vector2) -> float:
	var pos: Vector3 = BattleCam.TARGET + (BattleCam.POS - BattleCam.TARGET) * k
	var basis := Basis.looking_at(BattleCam.TARGET - pos, Vector3.UP)
	var rel: Vector3 = basis.inverse() * (p - pos)
	var f: float = (vp.y * 0.5) / tan(deg_to_rad(BattleCam.FOV) * 0.5)
	return vp.x * 0.5 + rel.x * f / -rel.z


func _ready() -> void:
	await get_tree().process_frame
	print("=== 画幅取景: 两个蛋连罩子都在两侧头像栏之间 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var pts: Array = CamFit.egg_points(s)
	_ok("★分母: 两个蛋罩共 4 个外沿点", pts.size() == 4, str(pts.size()))

	## ① 纯函数
	var W := CamFit.PANEL_FALLBACK_W
	var M := CamFit.MARGIN_PX
	for c in [[Vector2(1560, 720), "手机 19.5:9"], [Vector2(1280, 720), "16:9"], [Vector2(1280, 960), "iPad 4:3"]]:
		var vp: Vector2 = c[0]
		var k: float = CamFit.scale_for(pts, vp, W, vp.x - W, BattleCam.FOV)
		var lo := 1e9
		var hi := -1e9
		for p in pts:
			var x: float = _proj_x(p, k, vp)
			lo = minf(lo, x)
			hi = maxf(hi, x)
		if c[1] == "手机 19.5:9":
			_ok("① 手机画幅 k = 1(画面不变)", is_equal_approx(k, 1.0), "k=%.3f" % k)
		else:
			_ok("① %s 要退远 k > 1" % c[1], k > 1.05, "k=%.3f" % k)
		_ok("① %s 按 k=%.3f 投回去罩子外沿在 [%.0f, %.0f] 以内" % [c[1], k, W + M, vp.x - W - M],
			lo >= W + M - 0.5 and hi <= vp.x - W - M + 0.5, "实投 [%.1f, %.1f]" % [lo, hi])

	## ② 真场景 + 真相机
	var n_asp := 0
	for asp in ASPECTS:
		get_tree().root.size = asp
		if s._sub != null and is_instance_valid(s._sub):
			s._sub.size = asp
		await get_tree().process_frame
		var cam: Camera3D = s._cam
		var vs: Vector2 = cam.get_viewport().get_visible_rect().size
		CamFit.apply(s)
		s._shake_amp = 0.0
		s._cam_zoom = 1.0
		s._cam_pan = Vector3.ZERO
		s._apply_cam_zoom()
		cam.position = s._cam_zoom_base
		var e: Vector2 = CamFit.panel_edges(s, vs)
		var lo2 := 1e9
		var hi2 := -1e9
		for p in pts:
			var sp: Vector2 = cam.unproject_position(p)
			lo2 = minf(lo2, sp.x)
			hi2 = maxf(hi2, sp.x)
		var k2: float = float(s.get_meta("cam_fit_k", -1.0))
		n_asp += 1
		_ok("② %s(内容 %s) k=%.3f: 真相机下蛋罩外沿 [%.1f, %.1f] 在两栏内沿 (%.0f, %.0f) 之间" % [asp, vs, k2, lo2, hi2, e.x, e.y],
			lo2 >= e.x and hi2 <= e.y)
		var off: Vector3 = Vector3(s._cam_base) - BattleCam.TARGET
		_ok("② %s 机位仍在 40° 视轴上(只改距离)" % asp, absf(rad_to_deg(atan2(off.y, off.z)) - BattleCam.PITCH_DEG) < 0.01,
			"%.3f°" % rad_to_deg(atan2(off.y, off.z)))
		if asp.x * 720 >= asp.y * 1560:
			_ok("② %s 宽屏: 镜头基准 == BattleCam.POS(一个像素不变)" % asp, Vector3(s._cam_base).is_equal_approx(BattleCam.POS),
				"%s" % str(s._cam_base))
	_ok("★分母: 量了 %d 种画幅" % n_asp, n_asp == ASPECTS.size())
	get_tree().root.size = Vector2i(1280, 720)
	s.queue_free()
	await get_tree().process_frame

	## ③ 接线
	var hud := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	var i0 := hud.find("func _build_team_panels")
	var i1 := hud.find("\nfunc ", i0 + 10)
	var body := hud.substr(i0, i1 - i0) if i0 >= 0 and i1 > i0 else ""
	_ok("③ ★分母: 找到 battle_hud._build_team_panels", body.length() > 100)
	_ok("③ 头像栏建好就取景(_build_team_panels 里调 CamFit.apply_now_and_next_frame)", body.contains("CamFit.apply_now_and_next_frame(battle)"))
	var dl := FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	var ins := "%.1f" % CamFit.EGG_INSET
	_ok("③ 双路摆蛋内缩 == CamFit.EGG_INSET(%s 码)" % ins,
		dl.contains("battle.ARENA.position.x + %s, _cy)" % ins) and dl.contains("battle.ARENA.end.x - %s, _cy)" % ins))
	RB.DEBUG_EDIT = false
	if _fail == 0:
		print("ALL PASS")
	else:
		print("FAILED %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
